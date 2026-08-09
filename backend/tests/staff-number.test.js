import assert from 'node:assert/strict';
import test from 'node:test';
import { allocateClinicStaffNumber } from '../src/security/staff-number.js';

function sequenceClient() {
  const sequences = new Map();
  const calls = [];
  return {
    calls,
    async query(sql, parameters) {
      calls.push({ sql, parameters });
      const clinicId = parameters[0];
      if (sql.includes('INSERT INTO clinic_staff_number_sequences')) {
        if (!sequences.has(clinicId)) sequences.set(clinicId, 0);
        return { rows: [] };
      }
      if (sql.includes('UPDATE clinic_staff_number_sequences')) {
        const value = (sequences.get(clinicId) ?? 0) + 1;
        sequences.set(clinicId, value);
        return { rows: [{ current_value: value }] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
}

test('staff numbers are sequential, padded, and independent per clinic', async () => {
  const client = sequenceClient();
  assert.equal(await allocateClinicStaffNumber(client, 'clinic-a'), '001');
  assert.equal(await allocateClinicStaffNumber(client, 'clinic-a'), '002');
  assert.equal(await allocateClinicStaffNumber(client, 'clinic-b'), '001');
  const update = client.calls.find(({ sql }) =>
    sql.includes('UPDATE clinic_staff_number_sequences'));
  assert.match(update.sql, /current_value = current_value \+ 1/);
  assert.match(update.sql, /RETURNING current_value/);
});

test('near-concurrent allocations receive distinct values', async () => {
  const client = sequenceClient();
  const values = await Promise.all([
    allocateClinicStaffNumber(client, 'clinic-a'),
    allocateClinicStaffNumber(client, 'clinic-a'),
  ]);
  assert.deepEqual(values.sort(), ['001', '002']);
});

test('legacy non-numeric staff values are ignored by sequence initialization', async () => {
  const client = sequenceClient();
  await allocateClinicStaffNumber(client, 'clinic-a');
  const initialization = client.calls.find(({ sql }) =>
    sql.includes('INSERT INTO clinic_staff_number_sequences'));
  assert.match(initialization.sql, /staff_number ~ '\^\[0-9\]\+\$'/);
  assert.match(initialization.sql, /CASE/);
});
