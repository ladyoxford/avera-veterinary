import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { buildApp } from '../src/app.js';
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
        return {
          accepted: true,
          provider: 'resend',
          providerMessageId: 'email-1',
          submittedAt: new Date().toISOString(),
        };
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
  assert.equal(challenge.emailState, 'Submitted');
  assert.equal(challenge.providerMessageId, 'email-1');
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
    harness.calls.some(({ sql }) => sql.includes('UPDATE sessions')),
    true,
  );
  assert.equal(
    harness.calls.some(({ sql }) => sql.includes('UPDATE clinic_memberships')),
    true,
  );
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
  await assert.rejects(
    service.confirmDeletion({
      clinicId: 'clinic-1',
      requestId: challenge.requestId,
      code: delivered.code,
      actorUserId: 'owner-1',
      sessionId: 'session-1',
    }),
    (error) => error.code === 'clinic_deletion_request_unavailable',
  );
});

test('deletion email failure is explicit and deletes nothing', async () => {
  const harness = deletionHarness();
  const service = new ClinicDeletionService({
    pool: harness.pool,
    deliveryService: {
      configured: true,
      async sendClinicDeletionCode() {
        return undefined;
      },
    },
  });

  await assert.rejects(
    service.requestDeletion({
      clinicId: 'clinic-1',
      actorUserId: 'owner-1',
      sessionId: 'session-1',
      reason: 'Mutually agreed reset.',
    }),
    (error) =>
      error.code === 'clinic_deletion_email_failed' &&
      /Nothing was deleted/.test(error.message),
  );
  assert.equal(harness.state.request.status, 'DeliveryFailed');
  assert.equal(
    harness.calls.some(({ sql }) => sql.includes('UPDATE clinics\n')),
    false,
  );
});

test('expired deletion code cannot confirm', async () => {
  const harness = deletionHarness();
  let delivered;
  const service = new ClinicDeletionService({
    pool: harness.pool,
    deliveryService: {
      configured: true,
      async sendClinicDeletionCode(message) {
        delivered = message;
        return {
          accepted: true,
          provider: 'resend',
          providerMessageId: 'email-expired',
          submittedAt: new Date().toISOString(),
        };
      },
    },
  });
  const challenge = await service.requestDeletion({
    clinicId: 'clinic-1',
    actorUserId: 'owner-1',
    reason: 'Mutually agreed reset.',
  });
  harness.state.request.expires_at = new Date(Date.now() - 1_000);

  await assert.rejects(
    service.confirmDeletion({
      clinicId: 'clinic-1',
      requestId: challenge.requestId,
      code: delivered.code,
      actorUserId: 'owner-1',
    }),
    (error) => error.code === 'clinic_deletion_code_expired',
  );
  assert.equal(harness.state.request.status, 'Expired');
});

test('backend app registers the mutual deletion service', async (context) => {
  const app = await buildApp({
    environment: testEnvironment(),
    pool: { query: async () => ({ rows: [] }) },
  });
  context.after(() => app.close());
  assert.ok(app.clinicDeletionService instanceof ClinicDeletionService);
  assert.equal(typeof app.clinicDeletionService.requestDeletion, 'function');
});

test('Platform Owner deletion endpoint calls the registered service and sanitizes unknown failures', async (context) => {
  const pool = {
    async query(sql) {
      if (sql.includes('FROM sessions s JOIN users u')) {
        return {
          rows: [{
            session_id: 'platform-session-1',
            user_id: 'platform-owner-1',
            clinic_id: null,
            account_type: 'PlatformOwner',
            status: 'Active',
            revoked_at: null,
            expires_at: new Date(Date.now() + 60_000),
          }],
        };
      }
      throw new Error(`Unexpected route query: ${sql}`);
    },
  };
  const app = await buildApp({ environment: testEnvironment(), pool });
  context.after(() => app.close());
  const token = app.jwt.sign({
    userId: 'platform-owner-1',
    accountType: 'PlatformOwner',
    clinicId: null,
    sessionId: 'platform-session-1',
  });
  let received;
  app.clinicDeletionService.requestDeletion = async (value) => {
    received = value;
    return {
      requestId: 'request-1',
      recipientEmail: 'cl****@example.com',
      expiresAt: new Date(Date.now() + 60_000),
      attemptsRemaining: 5,
    };
  };

  const response = await app.inject({
    method: 'POST',
    url: '/api/v1/platform/clinics/clinic-1/deletion-requests',
    headers: { authorization: `Bearer ${token}` },
    payload: { reason: 'Mutually agreed reset.' },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(received.clinicId, 'clinic-1');
  assert.equal(response.json().deletionRequest.requestId, 'request-1');

  app.clinicDeletionService.requestDeletion = async () => {
    throw new TypeError(
      "Cannot read properties of undefined (reading 'requestDeletion')",
    );
  };
  const failed = await app.inject({
    method: 'POST',
    url: '/api/v1/platform/clinics/clinic-1/deletion-requests',
    headers: { authorization: `Bearer ${token}` },
    payload: { reason: 'Mutually agreed reset.' },
  });
  assert.equal(failed.statusCode, 503);
  assert.equal(failed.json().message, 'Deletion service is temporarily unavailable.');
  assert.doesNotMatch(failed.body, /Cannot read properties|requestDeletion/);
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
      if (
        sql.includes('UPDATE clinic_deletion_requests') &&
        sql.includes("status = 'DeliveryFailed'")
      ) {
        state.request.status = 'DeliveryFailed';
        return { rows: [] };
      }
      if (
        sql.includes('UPDATE clinic_deletion_requests') &&
        sql.includes("status = 'Expired'")
      ) {
        state.request.status = 'Expired';
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

function testEnvironment() {
  return {
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgres://unused:unused@localhost:5432/unused',
    JWT_ACCESS_SECRET: 'a'.repeat(32),
    JWT_REFRESH_SECRET: 'b'.repeat(32),
    TOTP_ENCRYPTION_KEY: 'c'.repeat(64),
    ACCESS_TOKEN_TTL_SECONDS: 900,
    REFRESH_TOKEN_TTL_DAYS: 30,
    PAYSTACK_SECRET_KEY: 'test-secret',
    PAYSTACK_WEBHOOK_SECRET: 'test-secret',
    PAYSTACK_CURRENCY: 'NGN',
    paymentCallbackUrl: 'avera://payments/callback',
    allowedOrigins: ['http://localhost'],
    ACTIVATION_TOKEN_TTL_MINUTES: 60,
    AVERA_ACTIVATION_BASE_URL:
      'https://accounts.averavet.sbs/activate-clinic-admin',
  };
}
