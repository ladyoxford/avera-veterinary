import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {
  farmContextSchema,
  readFarmContext,
  upsertFarmInvoiceContext,
} from '../src/routes/clinical-routes.js';

const clinicId = '11111111-1111-4111-8111-111111111111';
const otherClinicId = '22222222-2222-4222-8222-222222222222';
const userId = '33333333-3333-4333-8333-333333333333';
const farmId = '44444444-4444-4444-8444-444444444444';
const unitId = '55555555-5555-4555-8555-555555555555';
const goatGroupId = '66666666-6666-4666-8666-666666666666';
const sheepGroupId = '77777777-7777-4777-8777-777777777777';
const treatmentId = '88888888-8888-4888-8888-888888888888';

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
      if (sql.includes('SELECT farm_unit_id FROM farm_units')) return { rows: [{ farm_unit_id: unitId }] };
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
  assert.match(sql, /FROM farm_units u/);
  assert.match(sql, /NOT EXISTS[\s\S]*farm_unit_populations p/);
  assert.match(sql, /target_scope TEXT NOT NULL DEFAULT 'EntireUnit'/);
  assert.match(sql, /target_population_ids UUID\[\] NOT NULL DEFAULT '\{\}'::uuid\[\]/);
  assert.match(sql, /ENABLE ROW LEVEL SECURITY/);
  assert.doesNotMatch(sql, /DELETE FROM farm_units|DROP TABLE farm_units/);
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
