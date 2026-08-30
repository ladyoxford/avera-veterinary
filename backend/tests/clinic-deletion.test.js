import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { ClinicDeletionService } from '../src/services/clinic-deletion-service.js';

const migration = fs.readFileSync(
  new URL('../migrations/031_mutual_clinic_deletion.sql', import.meta.url),
  'utf8',
);

test('mutual deletion migration stores only a hashed expiring code', () => {
  assert.match(migration, /code_hash TEXT NOT NULL/);
  assert.match(migration, /expires_at TIMESTAMPTZ NOT NULL/);
  assert.match(migration, /attempts_remaining INTEGER NOT NULL DEFAULT 5/);
  assert.match(migration, /WHERE status = 'Pending'/);
  assert.doesNotMatch(migration, /\bcode\s+TEXT\b/);
});

test('mutual deletion requires the emailed code and releases registration identity', async () => {
  const harness = deletionHarness();
  let delivered;
  const service = new ClinicDeletionService({
    pool: harness.pool,
    deliveryService: {
      configured: true,
      async sendClinicDeletionCode(message) {
        delivered = message;
        return { reference: 'email-1' };
      },
    },
  });

  const challenge = await service.requestDeletion({
    clinicId: 'clinic-1',
    actorUserId: 'owner-1',
    sessionId: 'session-1',
    reason: 'Clinic and Platform Owner agreed to reset the registration.',
  });

  assert.equal(delivered.to, 'clinic@example.com');
  assert.match(delivered.code, /^\d{6}$/);
  assert.equal(challenge.recipientEmail, 'cl****@example.com');
  assert.equal('code' in challenge, false);
  assert.notEqual(harness.state.request.code_hash, delivered.code);
  assert.equal(harness.state.request.status, 'Pending');

  await assert.rejects(
    service.confirmDeletion({
      clinicId: 'clinic-1',
      requestId: challenge.requestId,
      code: '000000' === delivered.code ? '111111' : '000000',
      actorUserId: 'owner-1',
      sessionId: 'session-1',
    }),
    (error) =>
      error.code === 'clinic_deletion_code_invalid' &&
      error.statusCode === 400,
  );
  assert.equal(harness.state.request.attempts_remaining, 4);
  assert.equal(
    harness.calls.some(({ sql }) => sql.includes('UPDATE clinics\n')),
    false,
  );

  const deleted = await service.confirmDeletion({
    clinicId: 'clinic-1',
    requestId: challenge.requestId,
    code: delivered.code,
    actorUserId: 'owner-1',
    sessionId: 'session-1',
  });

  assert.equal(deleted.status, 'Deleted');
  assert.equal(deleted.registrationEmailReleased, true);
  assert.equal(harness.state.request.status, 'Confirmed');
  assert.equal(
    harness.calls.some(
      ({ sql }) =>
        sql.includes('UPDATE users') &&
        sql.includes('deleted.averavet.invalid'),
    ),
    true,
  );
  assert.equal(
    harness.calls.some(
      ({ sql }) =>
        sql.includes('UPDATE clinic_applications') &&
        sql.includes("status = 'Deleted'") &&
        sql.includes('deleted.averavet.invalid'),
    ),
    true,
  );
  assert.equal(
    harness.calls.some(
      ({ sql }) =>
        sql.includes('UPDATE clinics') &&
        sql.includes("status = 'Archived'") &&
        sql.includes('deleted.averavet.invalid'),
    ),
    true,
  );
  assert.equal(
    harness.calls.some(({ sql }) => /^\s*DELETE\s+/i.test(sql)),
    false,
  );
});

function deletionHarness() {
  const calls = [];
  const state = { request: null };
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (
        sql === 'BEGIN' ||
        sql === 'COMMIT' ||
        sql === 'ROLLBACK' ||
        sql.includes("set_config('avera.")
      ) {
        return { rows: [] };
      }
      if (sql.includes('SELECT c.clinic_id, c.name, c.status')) {
        return {
          rows: [{
            clinic_id: 'clinic-1',
            name: 'Clinic One',
            status: 'Active',
            account_email: 'clinic@example.com',
          }],
        };
      }
      if (sql.includes('INSERT INTO clinic_deletion_requests')) {
        state.request = {
          request_id: parameters[0],
          clinic_id: parameters[1],
          requested_by: parameters[2],
          recipient_email: parameters[3],
          code_hash: parameters[4],
          status: 'Pending',
          attempts_remaining: parameters[5],
          reason: parameters[6],
          expires_at: parameters[7],
          clinic_name: 'Clinic One',
          clinic_status: 'Active',
        };
        return { rows: [] };
      }
      if (sql.includes('SELECT d.*, c.name AS clinic_name')) {
        return { rows: state.request ? [{ ...state.request }] : [] };
      }
      if (
        sql.includes('UPDATE clinic_deletion_requests') &&
        sql.includes('attempts_remaining = $2')
      ) {
        state.request.attempts_remaining = parameters[1];
        if (parameters[1] === 0) state.request.status = 'Cancelled';
        return { rows: [] };
      }
      if (
        sql.includes('UPDATE clinic_deletion_requests') &&
        sql.includes("status = 'Confirmed'")
      ) {
        state.request.status = 'Confirmed';
        return { rows: [] };
      }
      return { rows: [] };
    },
    release() {},
  };
  return {
    calls,
    state,
    pool: {
      async connect() {
        return client;
      },
      query: (...arguments_) => client.query(...arguments_),
    },
  };
}
