import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import Fastify from 'fastify';
import { withTenantTransaction } from '../src/database/pool.js';
import {
  farmContextSchema,
  farmPopulationMovementSchema,
  recordFarmPopulationMovement,
  readFarmContext,
  upsertFarmInvoiceContext,
  clinicalRoutes,
} from '../src/routes/clinical-routes.js';

const clinicId = '11111111-1111-4111-8111-111111111111';
const otherClinicId = '22222222-2222-4222-8222-222222222222';
const userId = '33333333-3333-4333-8333-333333333333';
const farmId = '44444444-4444-4444-8444-444444444444';
const unitId = '55555555-5555-4555-8555-555555555555';
const goatGroupId = '66666666-6666-4666-8666-666666666666';
const sheepGroupId = '77777777-7777-4777-8777-777777777777';
const treatmentId = '88888888-8888-4888-8888-888888888888';
const migratedCattleGroupId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const clientCattleGroupId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

test('farm archive is tenant-scoped, permission-checked and preserves all children', async (t) => {
  const app = Fastify();
  t.after(() => app.close());
  const calls = [];
  let tenant = clinicId;
  let allowed = true;
  let status = 'Active';
  const client = { release() {}, async query(sql, values) {
    calls.push({ sql, values });
    if (sql.startsWith('UPDATE farms')) {
      if (values[1] !== clinicId) return { rows: [] };
      status = values[0];
      return { rows: [{ farm_id: farmId, status }] };
    }
    return { rows: [] };
  } };
  app.decorate('pool', { connect: async () => client });
  app.addHook('onRoute', (options) => {
    const guards = options.preHandler ?? [];
    options.preHandler = [async (request) => {
      request.auth = { userId, clinicId: tenant, sessionId: 'session', permissions: allowed ? ['farms.create'] : [] };
    }, ...guards.slice(1)];
  });
  await clinicalRoutes(app);
  const send = (nextStatus) => app.inject({ method: 'PATCH', url: `/api/v1/farms/${farmId}/status`,
    payload: { name: 'Actual Farm', status: nextStatus, clinicId: otherClinicId } });
  assert.equal((await send('Archived')).statusCode, 200);
  assert.equal(status, 'Archived');
  assert.equal((await send('Active')).statusCode, 200);
  assert.equal(status, 'Active');
  assert.ok(calls.every(({ sql }) => !/DELETE|UPDATE farm_unit|UPDATE farm_treatment/i.test(sql)));
  tenant = otherClinicId;
  assert.equal((await send('Archived')).statusCode, 404);
  assert.equal(status, 'Active');
  allowed = false;
  const before = calls.length;
  assert.equal((await send('Archived')).statusCode, 403);
  assert.equal(calls.length, before);
});

function context(overrides = {}) {
  return {
    farmId,
    name: 'Mixed Unit Farm',
    clientName: 'Client',
    clientPhone: '08000000000',
    units: [{
      farmUnitId: unitId,
      name: 'Mixed Pen',
      unitType: 'Pen',
      species: 'species_goat',
      breed: 'breed_goat_red_sokoto',
      populations: [
        {
          farmUnitPopulationId: goatGroupId,
          speciesId: 'species_goat',
          breedId: 'breed_goat_red_sokoto',
          maleCount: 3,
          femaleCount: 10,
          unknownCount: 0,
        },
        {
          farmUnitPopulationId: sheepGroupId,
          speciesId: 'species_sheep',
          breedId: 'breed_sheep_yankasa',
          maleCount: 2,
          femaleCount: 5,
          unknownCount: 1,
        },
      ],
    }],
    treatments: [],
    ...overrides,
  };
}

function persistenceClient({ populationRows } = {}) {
  const calls = [];
  return {
    calls,
    async query(sql, values) {
      calls.push({ sql, values });
      if (sql.includes('SELECT farm_id FROM farms')) return { rows: [{ farm_id: farmId }] };
      if (sql.includes('SELECT farm_unit_id') && sql.includes('FROM farm_units')) return { rows: [{ farm_unit_id: unitId }] };
      if (sql.includes('SELECT farm_unit_population_id FROM farm_unit_populations')) {
        return { rows: populationRows ?? values[3].map((id) => ({ farm_unit_population_id: id })) };
      }
      if (sql.includes('SELECT farm_treatment_record_id FROM farm_treatment_records')) {
        return { rows: values[2].map((id) => ({ farm_treatment_record_id: id })) };
      }
      return { rows: [] };
    },
  };
}

test('migration 025 preserves legacy units and defaults old treatments to EntireUnit', () => {
  const sql = fs.readFileSync(
    new URL('../migrations/025_farm_mixed_populations.sql', import.meta.url),
    'utf8',
  );
  assert.match(sql, /CREATE TABLE IF NOT EXISTS farm_unit_populations/);
  assert.match(
    sql,
    /CREATE UNIQUE INDEX IF NOT EXISTS farm_unit_populations_group_unique\s+ON farm_unit_populations\s+\(clinic_id, farm_unit_id, lower\(btrim\(species_id\)\), lower\(btrim\(coalesce\(breed_id, ''\)\)\)\)/i,
  );
  assert.match(sql, /FROM farm_units u/);
  assert.match(sql, /NOT EXISTS[\s\S]*farm_unit_populations p/);
  assert.match(sql, /target_scope TEXT NOT NULL DEFAULT 'EntireUnit'/);
  assert.match(sql, /target_population_ids UUID\[\] NOT NULL DEFAULT '\{\}'::uuid\[\]/);
  assert.match(sql, /ENABLE ROW LEVEL SECURITY/);
  assert.doesNotMatch(sql, /DELETE FROM farm_units|DROP TABLE farm_units/);
});

test('migration 034 adds an idempotent tenant-scoped population movement ledger', () => {
  const sql = fs.readFileSync(
    new URL('../migrations/034_farm_population_movements.sql', import.meta.url),
    'utf8',
  );
  assert.match(sql, /CREATE TABLE IF NOT EXISTS farm_population_movements/);
  assert.match(sql, /UNIQUE \(clinic_id, submission_id\)/);
  assert.match(sql, /movement_type IN \('mortality', 'purchase'\)/);
  assert.match(sql, /quantity INTEGER NOT NULL CHECK \(quantity > 0\)/);
  assert.match(sql, /ENABLE ROW LEVEL SECURITY/);
  assert.doesNotMatch(sql, /UPDATE farm_unit_populations|DELETE FROM|DROP TABLE/i);
});

test('population movement validation requires positive canonical deltas', () => {
  const valid = {
    submissionId: '99999999-9999-4999-8999-999999999999',
    farmId,
    farmName: 'Mixed Unit Farm',
    farmUnitId: unitId,
    farmUnitName: 'Mixed Pen',
    farmUnitType: 'Pen',
    farmUnitPopulationId: goatGroupId,
    speciesId: 'species_goat',
    breedId: null,
    baselineMaleCount: 3,
    baselineFemaleCount: 10,
    baselineUnknownCount: 0,
    movementType: 'mortality',
    sex: 'male',
    quantity: 1,
    occurredAt: '2026-09-07T10:00:00.000Z',
  };
  assert.equal(farmPopulationMovementSchema.safeParse(valid).success, true);
  assert.equal(farmPopulationMovementSchema.safeParse({ ...valid, quantity: 0 }).success, false);
  assert.equal(farmPopulationMovementSchema.safeParse({ ...valid, sex: 'bull' }).success, false);
});

function movementClient({ ownedClinicId = clinicId } = {}) {
  const state = { male_count: 3, female_count: 10, unknown_count: 1 };
  const movements = new Map();
  const calls = [];
  return {
    calls,
    state,
    async query(sql, values) {
      calls.push({ sql, values });
      if (sql.includes('SELECT farm_id FROM farms')) {
        return { rows: values[0] === ownedClinicId ? [{ farm_id: farmId }] : [] };
      }
      if (sql.includes('SELECT farm_unit_id') && sql.includes('FROM farm_units')) {
        return { rows: values[0] === ownedClinicId ? [{ farm_unit_id: unitId }] : [] };
      }
      if (sql.includes('FROM farm_population_movements') && sql.includes('submission_id')) {
        return { rows: movements.has(values[1]) ? [movements.get(values[1])] : [] };
      }
      if (sql.includes('FROM farm_unit_populations') && sql.includes('FOR UPDATE')) {
        return { rows: values[0] === ownedClinicId ? [{ farm_unit_population_id: goatGroupId, ...state }] : [] };
      }
      if (sql.includes('UPDATE farm_unit_populations')) {
        const column = sql.match(/SET (male_count|female_count|unknown_count)=/)[1];
        state[column] += values[0];
        return { rows: [{ farm_unit_population_id: goatGroupId, ...state }] };
      }
      if (sql.includes('INSERT INTO farm_population_movements')) {
        movements.set(values[4], {
          farm_id: values[1],
          farm_unit_id: values[2],
          farm_unit_population_id: values[3],
          movement_type: values[5], sex: values[6], quantity: values[7],
        });
      }
      return { rows: [] };
    },
  };
}

function movement(overrides = {}) {
  return {
    submissionId: '99999999-9999-4999-8999-999999999999',
    farmId,
    farmName: 'Mixed Unit Farm',
    farmUnitId: unitId,
    farmUnitName: 'Mixed Pen',
    farmUnitType: 'Pen',
    farmUnitPopulationId: goatGroupId,
    speciesId: 'species_goat',
    breedId: null,
    baselineMaleCount: 3,
    baselineFemaleCount: 10,
    baselineUnknownCount: 1,
    movementType: 'mortality',
    sex: 'male',
    quantity: 1,
    occurredAt: '2026-09-07T10:00:00.000Z',
    source: null,
    notes: null,
    ...overrides,
  };
}

test('mortality decrements only the selected sex and duplicate submission is idempotent', async () => {
  const client = movementClient();
  const context = { clinicId, actorUserId: userId };
  const first = await recordFarmPopulationMovement(client, context, movement());
  assert.deepEqual(first.population, {
    farm_unit_population_id: goatGroupId,
    male_count: 2,
    female_count: 10,
    unknown_count: 1,
  });
  const duplicate = await recordFarmPopulationMovement(client, context, movement());
  assert.equal(duplicate.duplicateSubmission, true);
  assert.equal(client.state.male_count, 2);
});

test('purchase increments selected sex and mortality cannot exceed the locked count', async () => {
  const client = movementClient();
  const context = { clinicId, actorUserId: userId };
  const purchase = await recordFarmPopulationMovement(client, context, movement({
    submissionId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    movementType: 'purchase',
    sex: 'female',
    quantity: 2,
  }));
  assert.equal(purchase.population.female_count, 12);
  const rejected = await recordFarmPopulationMovement(client, context, movement({
    submissionId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    quantity: 4,
  }));
  assert.deepEqual(rejected, { error: 'insufficient_population', available: 3 });
  assert.equal(client.state.male_count, 3);
});

test('cross-clinic population movement cannot reach another tenant records', async () => {
  const client = movementClient();
  const result = await recordFarmPopulationMovement(
    client,
    { clinicId: otherClinicId, actorUserId: userId },
    movement(),
  );
  assert.deepEqual(result, { error: 'farm_mismatch' });
  assert.equal(client.state.male_count, 3);
});

test('farm context accepts mixed population groups and defaults legacy treatment targeting', () => {
  const parsed = farmContextSchema.parse(context({
    treatments: [{
      treatmentRecordId: treatmentId,
      farmUnitId: unitId,
      treatmentType: 'Deworming',
      occurredAt: '2026-08-24T10:00:00.000Z',
      billableAmount: 5000,
    }],
  }));
  assert.equal(parsed.units[0].populations.length, 2);
  assert.equal(parsed.treatments[0].targetScope, 'EntireUnit');
  assert.deepEqual(parsed.treatments[0].targetPopulationIds, []);
});

test('farm population edits upsert current groups and remove stale groups', async () => {
  const client = persistenceClient();
  assert.equal(await upsertFarmInvoiceContext(client, clinicId, userId, context()), true);
  const populationUpserts = client.calls.filter((call) =>
    call.sql.includes('INSERT INTO farm_unit_populations'));
  assert.equal(populationUpserts.length, 2);
  assert.ok(populationUpserts.every((call) => call.sql.includes('ON CONFLICT')));
  const staleDelete = client.calls.find((call) =>
    call.sql.includes('DELETE FROM farm_unit_populations'));
  assert.deepEqual(staleDelete.values, [clinicId, farmId, unitId, [goatGroupId, sheepGroupId]]);
});

test('mixed populations and treatment targets round-trip through the remote context', async () => {
  const calls = [];
  const client = {
    async query(sql, values) {
      calls.push({ sql, values });
      if (sql.includes('FROM farms WHERE')) {
        return { rows: [{ farm_id: farmId, name: 'Mixed Unit Farm' }] };
      }
      if (sql.includes('FROM farm_units')) {
        return { rows: [{ farm_unit_id: unitId, name: 'Mixed Pen' }] };
      }
      if (sql.includes('FROM farm_unit_populations')) {
        return {
          rows: [
            {
              farm_unit_population_id: goatGroupId,
              farm_unit_id: unitId,
              species_id: 'species_goat',
              breed_id: 'breed_goat_red_sokoto',
              male_count: 3,
              female_count: 10,
              unknown_count: 0,
            },
            {
              farm_unit_population_id: sheepGroupId,
              farm_unit_id: unitId,
              species_id: 'species_sheep',
              breed_id: 'breed_sheep_yankasa',
              male_count: 2,
              female_count: 5,
              unknown_count: 1,
            },
          ],
        };
      }
      if (sql.includes('FROM farm_treatment_records')) {
        return {
          rows: [{
            farm_treatment_record_id: treatmentId,
            farm_unit_id: unitId,
            target_scope: 'SelectedGroups',
            target_population_ids: [sheepGroupId],
          }],
        };
      }
      return { rows: [] };
    },
  };

  const saved = await readFarmContext(client, clinicId, farmId);

  assert.equal(saved.units[0].populations.length, 2);
  assert.equal(saved.units[0].populations[1].species_id, 'species_sheep');
  assert.equal(saved.treatments[0].target_scope, 'SelectedGroups');
  assert.deepEqual(saved.treatments[0].target_population_ids, [sheepGroupId]);
  assert.ok(calls.every((call) => call.values[0] === clinicId));
  assert.ok(calls.every((call) => call.values[1] === farmId));
});

test('selected-group treatment persists only groups owned by the same unit', async () => {
  const client = persistenceClient();
  const value = context({
    treatments: [{
      treatmentRecordId: treatmentId,
      farmUnitId: unitId,
      treatmentType: 'Vaccination',
      occurredAt: '2026-08-24T10:00:00.000Z',
      billableAmount: 7500,
      targetScope: 'SelectedGroups',
      targetPopulationIds: [goatGroupId],
    }],
  });
  assert.equal(await upsertFarmInvoiceContext(client, clinicId, userId, value), true);
  const treatmentInsert = client.calls.find((call) =>
    call.sql.includes('INSERT INTO farm_treatment_records'));
  assert.equal(treatmentInsert.values[11], 'SelectedGroups');
  assert.deepEqual(treatmentInsert.values[12], [goatGroupId]);
});

test('cross-clinic or wrong-unit population targeting is rejected', async () => {
  const client = persistenceClient({ populationRows: [] });
  const value = context({
    treatments: [{
      treatmentRecordId: treatmentId,
      farmUnitId: unitId,
      treatmentType: 'Deworming',
      occurredAt: '2026-08-24T10:00:00.000Z',
      billableAmount: 5000,
      targetScope: 'SelectedGroups',
      targetPopulationIds: [sheepGroupId],
    }],
  });
  await assert.rejects(
    upsertFarmInvoiceContext(client, otherClinicId, userId, value),
    (error) => error.code === 'farm_population_mismatch',
  );
});

test('selected groups cannot be empty and entire-unit treatments cannot carry groups', () => {
  const selectedEmpty = context({
    treatments: [{
      treatmentRecordId: treatmentId,
      farmUnitId: unitId,
      treatmentType: 'Deworming',
      occurredAt: '2026-08-24T10:00:00.000Z',
      billableAmount: 5000,
      targetScope: 'SelectedGroups',
      targetPopulationIds: [],
    }],
  });
  assert.equal(farmContextSchema.safeParse(selectedEmpty).success, false);
  const entireWithGroup = structuredClone(selectedEmpty);
  entireWithGroup.treatments[0].targetScope = 'EntireUnit';
  entireWithGroup.treatments[0].targetPopulationIds = [goatGroupId];
  assert.equal(farmContextSchema.safeParse(entireWithGroup).success, false);
});


test('purchase sale mortality follow the approved ledger example with atomic rejection', async () => {
  const client = movementClient();
  Object.assign(client.state, {male_count: 24, female_count: 2, unknown_count: 0});
  const context = {clinicId, actorUserId: userId};
  const apply = (type, sex, quantity, submissionId) => recordFarmPopulationMovement(client, context, movement({movementType:type, sex, quantity, submissionId}));
  await apply('purchase', 'male', 5, 'purchase');
  assert.equal(client.state.male_count, 29);
  await apply('sale', 'male', 3, 'sale');
  assert.equal(client.state.male_count, 26);
  await apply('sale', 'male', 3, 'sale');
  assert.equal(client.state.male_count, 26);
  const inserted = () => client.calls.filter(c => c.sql.includes('INSERT INTO farm_population_movements')).length;
  const before = inserted();
  assert.equal((await apply('sale', 'male', 27, 'oversale')).error, 'insufficient_population');
  assert.equal((await apply('mortality', 'female', 3, 'overdeath')).error, 'insufficient_population');
  assert.equal(inserted(), before);
  await apply('mortality', 'female', 1, 'death');
  assert.deepEqual(client.state, {male_count:26, female_count:1, unknown_count:0});
  assert.equal(inserted(), 3);
});

test('movement validation accepts sale and rejects invalid quantity and sex', async () => {
  assert.equal(farmPopulationMovementSchema.safeParse(movement({movementType:'sale'})).success, true);
  const client = movementClient();
  for (const invalid of [{quantity:0}, {quantity:-1}, {quantity:1.5}, {sex:'invalid'}, {movementType:'invalid'}]) {
    assert.equal((await recordFarmPopulationMovement(client, {clinicId, actorUserId:userId}, movement(invalid))).error, 'invalid_movement');
  }
  assert.equal(client.calls.length, 0);
});

test('archived units reject transactions before population mutation', async () => {
  const client = movementClient();
  const query = client.query.bind(client);
  client.query = (sql, values) => sql.includes('SELECT farm_unit_id, status') ? {rows:[{farm_unit_id:unitId,status:'Archived'}]} : query(sql, values);
  assert.equal((await recordFarmPopulationMovement(client, {clinicId,actorUserId:userId}, movement({movementType:'sale'}))).error, 'farm_archived');
  assert.equal(client.calls.some(c => c.sql.includes('UPDATE farm_unit_populations')), false);
});


test('failed ledger insert rolls back the population update through the tenant transaction', async () => {
  const client = movementClient();
  const initial = {...client.state};
  const query = client.query.bind(client);
  client.release = () => {};
  client.query = async (sql, values) => {
    if (sql.includes('INSERT INTO farm_population_movements')) throw new Error('injected insert failure');
    if (sql === 'ROLLBACK') Object.assign(client.state,initial);
    return query(sql,values);
  };
  await assert.rejects(withTenantTransaction({connect:async () => client},{clinicId}, tx => recordFarmPopulationMovement(tx,{clinicId,actorUserId:userId},movement({movementType:'sale'}))),/injected insert failure/);
  assert.deepEqual(client.state,initial);
  assert.ok(client.calls.some(c => c.sql === 'ROLLBACK'));
  assert.equal(client.calls.some(c => c.sql === 'COMMIT'),false);
});


test('unit lifecycle is tenant scoped, permission checked, and retains populations', async (t) => {
  const app=Fastify(); t.after(() => app.close());
  let tenant=clinicId, allowed=true, status='Active';
  const calls=[];
  const client={release(){},async query(sql,values){
    calls.push({sql,values});
    if (sql.includes('SELECT farm_id FROM farms')) return {rows: values[0] === clinicId ? [{farm_id:farmId}] : []};
    if (sql.startsWith('UPDATE farm_units')) { if (values[1] !== clinicId) return {rows:[]}; status=values[0];return {rows:[{farm_unit_id:unitId,status}]}; }
    return {rows:[]};
  }};
  app.decorate('pool',{connect:async()=>client});
  app.addHook('onRoute', options => {const guards=options.preHandler??[]; options.preHandler=[async request=>{request.auth={userId,clinicId:tenant,sessionId:'session',permissions:allowed?['farms.units.manage']:[]};},...guards.slice(1)];});
  await clinicalRoutes(app);
  const send=status=>app.inject({method:'PATCH',url:`/api/v1/farms/${farmId}/units/${unitId}/status`,payload:{status,farmName:'Farm',name:'Pen',unitType:'Pen',clinicId:otherClinicId}});
  assert.equal((await send('Archived')).statusCode,200); assert.equal(status,'Archived');
  assert.equal((await send('Active')).statusCode,200); assert.equal(status,'Active');
  tenant=otherClinicId; assert.equal((await send('Archived')).statusCode,404); assert.equal(status,'Active');
  allowed=false; assert.equal((await send('Archived')).statusCode,403);
  assert.equal(calls.some(c=> /DELETE|UPDATE farm_unit_populations/.test(c.sql)),false);
});

for (const target of ['unit','population']) test(`movement rejects a foreign ${target} without mutation`, async () => {
  const client=movementClient(); const query=client.query.bind(client);
  client.query=(sql,values)=> (target==='unit' && sql.includes('SELECT farm_unit_id, status')) || (target==='population' && sql.includes('FROM farm_unit_populations') && sql.includes('FOR UPDATE')) ? {rows:[]} : query(sql,values);
  const result=await recordFarmPopulationMovement(client,{clinicId,actorUserId:userId},movement({movementType:'sale'}));
  assert.equal(result.error,target==='unit'?'farm_unit_mismatch':'farm_population_mismatch');
  assert.equal(client.calls.some(c=>c.sql.includes('UPDATE farm_unit_populations')),false);
});

function existingCattleGroupClient({
  existingPopulation = {
    farm_unit_population_id: migratedCattleGroupId,
    species_id: 'species_cattle',
    breed_id: 'breed_cattle_white_fulani_bunaji',
    male_count: 24,
    female_count: 2,
    unknown_count: 0,
  },
  populationInsert = 'reject',
  additionalPopulations = [],
  expectedClinicId = clinicId,
  expectedFarmId = farmId,
  expectedUnitId = unitId,
} = {}) {
  const calls = [];
  const movements = new Map();
  const withScope = (population) => ({
    clinic_id: expectedClinicId.toLowerCase(),
    farm_id: expectedFarmId.toLowerCase(),
    farm_unit_id: expectedUnitId.toLowerCase(),
    ...population,
  });
  const populations = [
    ...additionalPopulations.map(withScope),
    ...(existingPopulation ? [withScope(existingPopulation)] : []),
  ];
  const normalized = (value) => (value ?? '').trim().toLowerCase();
  const sameUuid = (left, right) => left?.toLowerCase() === right?.toLowerCase();
  const resultRow = (population, extra = {}) => ({ ...population, ...extra });
  return {
    calls,
    movements,
    populations,
    release() {},
    async query(sql, values = []) {
      calls.push({ sql, values });
      if (sql.includes('SELECT farm_id FROM farms')) {
        return {
          rows: sameUuid(values[0], expectedClinicId)
            && sameUuid(values[1], expectedFarmId)
            ? [{ farm_id: expectedFarmId.toLowerCase() }]
            : [],
        };
      }
      if (sql.includes('SELECT status FROM farms')) {
        return {
          rows: sameUuid(values[0], expectedClinicId)
            && sameUuid(values[1], expectedFarmId)
            ? [{ status: 'Active' }]
            : [],
        };
      }
      if (sql.includes('SELECT farm_unit_id, status FROM farm_units')) {
        return {
          rows: sameUuid(values[0], expectedClinicId)
            && sameUuid(values[1], expectedFarmId)
            && sameUuid(values[2], expectedUnitId)
            ? [{ farm_unit_id: expectedUnitId.toLowerCase(), status: 'Active' }]
            : [],
        };
      }
      if (sql.includes('FROM farm_unit_populations') && sql.includes('FOR UPDATE')) {
        assert.match(
          sql,
          /WHERE clinic_id=\$1 AND farm_id=\$2 AND farm_unit_id=\$3/,
        );
        if (sql.includes('farm_unit_population_id=$4')) {
          const found = populations.find((row) =>
            sameUuid(row.clinic_id, values[0])
              && sameUuid(row.farm_id, values[1])
              && sameUuid(row.farm_unit_id, values[2])
              && sameUuid(row.farm_unit_population_id, values[3]));
          return {
            rows: found
              ? [resultRow(found, {
                group_matches: normalized(found.species_id) === normalized(values[4])
                  && normalized(found.breed_id) === normalized(values[5]),
              })]
              : [],
          };
        }
        const found = populations.find((row) =>
          sameUuid(row.clinic_id, values[0])
            && sameUuid(row.farm_id, values[1])
            && sameUuid(row.farm_unit_id, values[2])
            && normalized(row.species_id) === normalized(values[3])
            && normalized(row.breed_id) === normalized(values[4]));
        return { rows: found ? [resultRow(found)] : [] };
      }
      if (sql.includes('INSERT INTO farm_unit_populations')) {
        if (populationInsert === 'reject') {
          throw new Error(
            'duplicate key value violates unique constraint "farm_unit_populations_group_unique"',
          );
        }
        assert.match(sql, /ON CONFLICT\s+DO NOTHING/i);
        const created = {
          clinic_id: values[1].toLowerCase(),
          farm_id: values[2].toLowerCase(),
          farm_unit_id: values[3].toLowerCase(),
          farm_unit_population_id: populationInsert === 'race'
            ? migratedCattleGroupId
            : values[0].toLowerCase(),
          species_id: values[4].trim(),
          breed_id: values[5]?.trim() || null,
          male_count: values[6],
          female_count: values[7],
          unknown_count: values[8],
        };
        populations.push(created);
        return { rows: populationInsert === 'race' ? [] : [resultRow(created)] };
      }
      if (sql.includes('FROM farm_population_movements')
          && sql.includes('submission_id')) {
        return { rows: movements.has(values[1]) ? [movements.get(values[1])] : [] };
      }
      if (sql.includes('UPDATE farm_unit_populations')) {
        const population = populations.find((row) =>
          sameUuid(row.clinic_id, values[1])
            && sameUuid(row.farm_id, values[2])
            && sameUuid(row.farm_unit_id, values[3])
            && sameUuid(row.farm_unit_population_id, values[4]));
        assert.ok(population, 'the canonical population row must be updated');
        const column = sql.match(/SET (male_count|female_count|unknown_count)=/)[1];
        population[column] += values[0];
        return { rows: [resultRow(population)] };
      }
      if (sql.includes('INSERT INTO farm_population_movements')) {
        assert.equal(
          movements.has(values[4]),
          false,
          'a submission ID must produce only one movement ledger row',
        );
        const row = {
          id: `movement-${movements.size + 1}`,
          createdAt: '2026-09-09T12:00:00.000Z',
          farm_unit_population_id: values[3].toLowerCase(),
          farm_id: values[1].toLowerCase(),
          farm_unit_id: values[2].toLowerCase(),
          movement_type: values[5],
          sex: values[6],
          quantity: values[7],
        };
        movements.set(values[4], row);
        return { rows: [row] };
      }
      return { rows: [] };
    },
  };
}

test('existing normalized cattle group handles purchase sale and mortality without duplicate insert', async (t) => {
  const app = Fastify();
  t.after(() => app.close());
  const client = existingCattleGroupClient();
  app.decorate('pool', { connect: async () => client });
  app.addHook('onRoute', (options) => {
    const guards = options.preHandler ?? [];
    options.preHandler = [async (request) => {
      request.auth = {
        userId,
        clinicId,
        sessionId: 'session',
        permissions: ['farms.units.manage', 'farms.mortality.record'],
      };
    }, ...guards.slice(1)];
  });
  await clinicalRoutes(app);

  const send = (movementType, submissionId, speciesId, breedId) => app.inject({
    method: 'POST',
    url: `/api/v1/farms/${farmId}/population-movements`,
    payload: {
      ...movement({
        submissionId,
        farmUnitPopulationId: clientCattleGroupId,
        speciesId,
        breedId,
        movementType,
      }),
      farmUnitId: unitId,
      farmId,
    },
  });

  const purchase = await send(
    'purchase',
    '10000000-0000-4000-8000-000000000001',
    ' species_cattle ',
    ' breed_cattle_white_fulani_bunaji ',
  );
  assert.equal(purchase.statusCode, 201);
  assert.equal(
    purchase.json().population.farm_unit_population_id,
    migratedCattleGroupId,
  );
  assert.equal(client.populations[0].male_count, 25);
  assert.equal((await send(
    'purchase',
    '10000000-0000-4000-8000-000000000001',
    'species_cattle',
    'breed_cattle_white_fulani_bunaji',
  )).statusCode, 200);
  assert.equal(client.populations[0].male_count, 25);

  const sale = await send(
    'sale',
    '10000000-0000-4000-8000-000000000002',
    'SPECIES_CATTLE',
    'BREED_CATTLE_WHITE_FULANI_BUNAJI',
  );
  assert.equal(sale.statusCode, 201);
  assert.equal(client.populations[0].male_count, 24);
  assert.equal((await send(
    'sale',
    '10000000-0000-4000-8000-000000000002',
    'species_cattle',
    'breed_cattle_white_fulani_bunaji',
  )).statusCode, 200);
  assert.equal(client.populations[0].male_count, 24);

  const mortality = await send(
    'mortality',
    '10000000-0000-4000-8000-000000000003',
    'species_cattle',
    'breed_cattle_white_fulani_bunaji',
  );
  assert.equal(mortality.statusCode, 201);
  assert.equal(client.populations[0].male_count, 23);
  assert.equal((await send(
    'mortality',
    '10000000-0000-4000-8000-000000000003',
    'species_cattle',
    'breed_cattle_white_fulani_bunaji',
  )).statusCode, 200);
  assert.equal(client.populations[0].male_count, 23);
  assert.equal(client.populations.length, 1);
  assert.equal(client.movements.size, 3);
  assert.equal(
    client.calls.filter((call) =>
      call.sql.includes('INSERT INTO farm_population_movements')).length,
    3,
  );
  assert.ok([...client.movements.values()].every((row) =>
    row.farm_unit_population_id === migratedCattleGroupId));
  const audits = client.calls.filter((call) =>
    call.sql.includes('INSERT INTO audit_logs'));
  assert.equal(audits.length, 3);
  assert.ok(audits.every((call) => call.values[3] === migratedCattleGroupId));
  assert.equal(
    client.calls.some((call) => call.sql.includes('INSERT INTO farm_unit_populations')),
    false,
  );
  const normalizedLookups = client.calls.filter((call) =>
    call.sql.includes('lower(btrim(species_id))')
      && !call.sql.includes('AS group_matches'));
  assert.ok(normalizedLookups.length >= 3);
  assert.ok(normalizedLookups.every((call) =>
    call.values[0] === clinicId
      && call.values[1] === farmId
      && call.values[2] === unitId));
});

test('normalized population lookup treats null and empty breed as the same group', async () => {
  const client = existingCattleGroupClient();
  client.populations[0].breed_id = null;
  const result = await recordFarmPopulationMovement(
    client,
    { clinicId, actorUserId: userId },
    movement({
      submissionId: '10000000-0000-4000-8000-000000000004',
      farmUnitPopulationId: clientCattleGroupId,
      speciesId: ' SPECIES_CATTLE ',
      breedId: '',
      movementType: 'purchase',
      baselineMaleCount: 900,
      baselineFemaleCount: 900,
      baselineUnknownCount: 900,
    }),
  );

  assert.equal(result.population.farm_unit_population_id, migratedCattleGroupId);
  assert.deepEqual(
    client.populations.map((row) => ({
      id: row.farm_unit_population_id,
      male: row.male_count,
      female: row.female_count,
      unknown: row.unknown_count,
    })),
    [{ id: migratedCattleGroupId, male: 25, female: 2, unknown: 0 }],
  );
  assert.equal(
    client.calls.some((call) => call.sql.includes('INSERT INTO farm_unit_populations')),
    false,
  );
});

test('normalized population lookup stays scoped to the requested clinic and unit', async () => {
  const foreignPopulationId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const client = existingCattleGroupClient({
    additionalPopulations: [{
      clinic_id: otherClinicId,
      farm_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      farm_unit_id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      farm_unit_population_id: foreignPopulationId,
      species_id: 'species_cattle',
      breed_id: 'breed_cattle_white_fulani_bunaji',
      male_count: 80,
      female_count: 20,
      unknown_count: 0,
    }],
  });

  const result = await recordFarmPopulationMovement(
    client,
    { clinicId, actorUserId: userId },
    movement({
      submissionId: '10000000-0000-4000-8000-000000000007',
      farmUnitPopulationId: clientCattleGroupId,
      speciesId: 'species_cattle',
      breedId: 'breed_cattle_white_fulani_bunaji',
      movementType: 'purchase',
    }),
  );

  assert.equal(result.population.farm_unit_population_id, migratedCattleGroupId);
  assert.equal(
    client.populations.find((row) =>
      row.farm_unit_population_id === foreignPopulationId).male_count,
    80,
  );
  assert.equal(
    client.populations.find((row) =>
      row.farm_unit_population_id === migratedCattleGroupId).male_count,
    25,
  );
});

test('idempotent retries accept uppercase UUID spellings', async () => {
  const uppercaseFarmId = 'A4444444-4444-4444-8444-444444444444';
  const uppercaseUnitId = 'B5555555-5555-4555-8555-555555555555';
  const client = existingCattleGroupClient({
    expectedFarmId: uppercaseFarmId,
    expectedUnitId: uppercaseUnitId,
  });
  const input = movement({
    submissionId: '10000000-0000-4000-8000-000000000008',
    farmId: uppercaseFarmId,
    farmUnitId: uppercaseUnitId,
    farmUnitPopulationId: clientCattleGroupId.toUpperCase(),
    speciesId: 'species_cattle',
    breedId: 'breed_cattle_white_fulani_bunaji',
    movementType: 'purchase',
  });

  const first = await recordFarmPopulationMovement(
    client,
    { clinicId, actorUserId: userId },
    input,
  );
  const retry = await recordFarmPopulationMovement(
    client,
    { clinicId, actorUserId: userId },
    input,
  );

  assert.equal(first.population.male_count, 25);
  assert.equal(retry.duplicateSubmission, true);
  assert.equal(client.populations.at(-1).male_count, 25);
  assert.equal(
    client.calls.filter((call) =>
      call.sql.includes('INSERT INTO farm_population_movements')).length,
    1,
  );
});

for (const populationInsert of ['create', 'race']) {
  test(`missing population group uses the safe ${populationInsert} path`, async () => {
    const client = existingCattleGroupClient({
      existingPopulation: null,
      populationInsert,
    });
    const result = await recordFarmPopulationMovement(
      client,
      { clinicId, actorUserId: userId },
      movement({
        submissionId: populationInsert === 'create'
          ? '10000000-0000-4000-8000-000000000005'
          : '10000000-0000-4000-8000-000000000006',
        farmUnitPopulationId: clientCattleGroupId,
        speciesId: 'species_cattle',
        breedId: 'breed_cattle_white_fulani_bunaji',
        movementType: 'purchase',
      }),
    );

    assert.equal(client.populations.length, 1);
    assert.equal(client.populations[0].male_count, 4);
    assert.equal(
      result.population.farm_unit_population_id,
      populationInsert === 'race' ? migratedCattleGroupId : clientCattleGroupId,
    );
    assert.equal(client.movements.size, 1);
    const populationInserts = client.calls.filter((call) =>
      call.sql.includes('INSERT INTO farm_unit_populations'));
    assert.equal(populationInserts.length, 1);
    assert.match(populationInserts[0].sql, /ON CONFLICT\s+DO NOTHING/i);
    const normalizedLookups = client.calls.filter((call) =>
      call.sql.includes('lower(btrim(species_id))')
        && !call.sql.includes('AS group_matches'));
    assert.equal(normalizedLookups.length, populationInsert === 'race' ? 2 : 1);
  });
}
