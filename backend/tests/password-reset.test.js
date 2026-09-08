import assert from 'node:assert/strict';
import test from 'node:test';

import rateLimit from '@fastify/rate-limit';
import Fastify from 'fastify';

import { authRoutes } from '../src/routes/auth-routes.js';
import { verifyPassword } from '../src/security/passwords.js';
import { hashToken } from '../src/security/tokens.js';
import {
  PasswordResetService,
  passwordResetUrl,
} from '../src/services/password-reset-service.js';

const environment = {
  PASSWORD_RESET_TOKEN_TTL_MINUTES: 30,
  AVERA_PASSWORD_RESET_BASE_URL:
    'https://accounts.averavet.sbs/reset-password',
};

function requestHarness({
  includeUser = true,
  failDeliveryAudit = false,
  failDeliveryConnect = false,
  failDeliveryUpdate = false,
} = {}) {
  const state = {
    audits: [],
    connections: 0,
    delivery: null,
    issued: null,
  };
  const user = {
    user_id: 'platform-owner-1',
    clinic_id: null,
    full_name: 'AVERA Platform Owner',
    email: 'owner@avera.test',
    status: 'Active',
    password_hash: 'existing-password-hash',
  };
  const client = {
    async query(sql, parameters = []) {
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) return { rows: [] };
      if (sql.includes('FROM users') && sql.includes('WHERE email = $1')) {
        return { rows: includeUser ? [user] : [] };
      }
      if (
        sql.includes('UPDATE activation_tokens') &&
        sql.includes('SET revoked_at = $2')
      ) {
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO activation_tokens')) {
        state.issued = {
          userId: parameters[0],
          clinicId: parameters[1],
          purpose: parameters[2],
          tokenHash: parameters[3],
          expiresAt: parameters[4],
        };
        return { rows: [{ token_id: 'reset-token-1' }] };
      }
      if (
        sql.includes('UPDATE activation_tokens') &&
        sql.includes('delivery_method = $2')
      ) {
        if (failDeliveryUpdate) {
          const error = new Error('simulated delivery metadata failure');
          error.code = 'delivery_metadata_failed';
          throw error;
        }
        state.delivery = {
          method: parameters[1],
          submittedAt: parameters[2],
          reference: parameters[3],
          provider: parameters[4],
          failureCode: parameters[5],
        };
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO audit_logs')) {
        if (
          failDeliveryAudit &&
          parameters[4] === 'password.reset_email_submitted'
        ) {
          const error = new Error('simulated delivery audit failure');
          error.code = 'delivery_audit_failed';
          throw error;
        }
        state.audits.push(parameters[4]);
        return { rows: [] };
      }
      throw new Error(`Unexpected password reset request query: ${sql}`);
    },
    release() {},
  };
  return {
    state,
    pool: {
      async connect() {
        state.connections += 1;
        if (failDeliveryConnect && state.connections === 2) {
          const error = new Error('simulated delivery connection failure');
          error.code = 'delivery_connection_failed';
          throw error;
        }
        return client;
      },
    },
  };
}

async function forgotPasswordApp(passwordResetService) {
  const app = Fastify({ logger: false, trustProxy: true });
  app.decorate('environment', { NODE_ENV: 'production' });
  app.decorate('passwordResetService', passwordResetService);
  await app.register(rateLimit, { global: false });
  await app.register(authRoutes);
  await app.ready();
  return app;
}

function resetHarness({ expired = false } = {}) {
  const rawToken = 'password-reset-token-with-at-least-32-characters';
  const state = {
    audits: [],
    passwordHash: 'old-password-hash',
    sessionsRevoked: false,
    status: 'Locked',
    usedAt: null,
  };
  const client = {
    async query(sql, parameters = []) {
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) return { rows: [] };
      if (sql.includes('FROM activation_tokens t')) {
        if (parameters[0] !== hashToken(rawToken)) return { rows: [] };
        return {
          rows: [{
            token_id: 'reset-token-1',
            user_id: 'user-1',
            clinic_id: 'clinic-1',
            email: 'doctor@clinic.test',
            status: state.status,
            expires_at: expired
              ? new Date(Date.now() - 1_000)
              : new Date(Date.now() + 60_000),
            used_at: state.usedAt,
            revoked_at: null,
          }],
        };
      }
      if (sql.includes('UPDATE users') && sql.includes('password_hash = $2')) {
        state.passwordHash = parameters[1];
        state.status = 'Active';
        return { rows: [] };
      }
      if (
        sql.includes('UPDATE activation_tokens') &&
        sql.includes('SET used_at = $2')
      ) {
        state.usedAt = parameters[1];
        return { rows: [] };
      }
      if (
        sql.includes('UPDATE activation_tokens') &&
        sql.includes('token_id <> $4')
      ) {
        return { rows: [] };
      }
      if (sql.includes('UPDATE sessions SET revoked_at')) {
        state.sessionsRevoked = true;
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO audit_logs')) {
        state.audits.push(parameters[4]);
        return { rows: [] };
      }
      throw new Error(`Unexpected password reset completion query: ${sql}`);
    },
    release() {},
  };
  return {
    rawToken,
    state,
    pool: { connect: async () => client },
  };
}

test('password reset requests issue a hashed token and email Platform Owners', async () => {
  const harness = requestHarness();
  let submittedMessage;
  const service = new PasswordResetService({
    pool: harness.pool,
    environment,
    deliveryService: {
      configured: true,
      provider: 'smtp',
      async sendPasswordReset(message) {
        submittedMessage = message;
        return {
          accepted: true,
          provider: 'smtp',
          providerMessageId: 'smtp-message-1',
          submittedAt: new Date().toISOString(),
        };
      },
    },
  });

  const result = await service.request({
    email: ' OWNER@AVERA.TEST ',
    ipAddress: '127.0.0.1',
    userAgent: 'test-agent',
  });

  assert.deepEqual(result, { accepted: true });
  const rawToken = new URL(submittedMessage.resetUrl).searchParams.get('token');
  assert.equal(harness.state.issued.clinicId, null);
  assert.equal(harness.state.issued.purpose, 'PasswordReset');
  assert.equal(harness.state.issued.tokenHash, hashToken(rawToken));
  assert.notEqual(harness.state.issued.tokenHash, rawToken);
  assert.equal(harness.state.delivery.method, 'email_submitted');
  assert.equal(harness.state.delivery.provider, 'smtp');
  assert.equal(harness.state.delivery.reference, 'smtp-message-1');
  assert.deepEqual(harness.state.audits, [
    'password.reset_requested',
    'password.reset_email_submitted',
  ]);
});

test('unknown reset email returns the same accepted response without issuing a token', async () => {
  const harness = requestHarness({ includeUser: false });
  let deliveries = 0;
  const service = new PasswordResetService({
    pool: harness.pool,
    environment,
    deliveryService: {
      configured: true,
      async sendPasswordReset() {
        deliveries += 1;
      },
    },
  });

  assert.deepEqual(
    await service.request({ email: 'unknown@avera.test' }),
    { accepted: true },
  );
  assert.equal(harness.state.issued, null);
  assert.equal(deliveries, 0);
});

for (const scenario of [
  {
    name: 'delivery metadata update fails',
    options: { failDeliveryUpdate: true },
    stage: 'delivery_metadata',
  },
  {
    name: 'delivery audit write fails',
    options: { failDeliveryAudit: true },
    stage: 'audit',
  },
  {
    name: 'delivery bookkeeping connection fails',
    options: { failDeliveryConnect: true },
    stage: 'connect',
  },
]) {
  test(`provider acceptance remains successful when ${scenario.name}`, async () => {
    const harness = requestHarness(scenario.options);
    const logs = [];
    const service = new PasswordResetService({
      pool: harness.pool,
      environment,
      logger: {
        error(details, message) {
          logs.push({ details, message });
        },
      },
      deliveryService: {
        configured: true,
        provider: 'resend',
        async sendPasswordReset() {
          return {
            accepted: true,
            provider: 'resend',
            providerMessageId: 'resend-message-accepted',
            submittedAt: new Date().toISOString(),
          };
        },
      },
    });

    assert.deepEqual(
      await service.request({ email: 'owner@avera.test' }),
      { accepted: true },
    );
    assert.equal(logs.length, 1);
    assert.equal(logs[0].details.providerAccepted, true);
    assert.equal(logs[0].details.provider, 'resend');
    assert.equal(logs[0].details.stage, scenario.stage);
    assert.equal(
      logs[0].details.event,
      'password_reset_delivery_bookkeeping_failed',
    );
    assert.equal(JSON.stringify(logs).includes('owner@avera.test'), false);
  });
}

test('password reset request fails when the email provider rejects delivery', async () => {
  const harness = requestHarness();
  const service = new PasswordResetService({
    pool: harness.pool,
    environment,
    deliveryService: {
      configured: true,
      provider: 'resend',
      async sendPasswordReset() {
        return {
          accepted: false,
          provider: 'resend',
          providerMessageId: null,
          submittedAt: null,
          failureCode: 'email_provider_rejected',
        };
      },
    },
  });

  await assert.rejects(
    service.request({ email: 'owner@avera.test' }),
    (error) => {
      assert.equal(error.code, 'password_reset_delivery_failed');
      assert.equal(error.statusCode, 503);
      return true;
    },
  );
  assert.equal(harness.state.delivery.method, 'email_failed');
  assert.equal(harness.state.delivery.failureCode, 'email_provider_rejected');
  assert.deepEqual(harness.state.audits, [
    'password.reset_requested',
    'password.reset_email_submission_failed',
  ]);
});

test('forgot-password returns HTTP 202 after provider acceptance despite audit failure', async (t) => {
  const harness = requestHarness({ failDeliveryAudit: true });
  const service = new PasswordResetService({
    pool: harness.pool,
    environment,
    deliveryService: {
      configured: true,
      provider: 'resend',
      async sendPasswordReset() {
        return {
          accepted: true,
          provider: 'resend',
          providerMessageId: 'resend-message-accepted',
          submittedAt: new Date().toISOString(),
        };
      },
    },
  });
  const app = await forgotPasswordApp(service);
  t.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/forgot-password',
    payload: { email: 'owner@avera.test' },
  });

  assert.equal(response.statusCode, 202);
  assert.deepEqual(response.json(), {
    accepted: true,
    message: 'If this email is registered, a password reset link has been sent.',
  });
});

test('forgot-password preserves a real provider failure', async (t) => {
  const harness = requestHarness();
  const service = new PasswordResetService({
    pool: harness.pool,
    environment,
    deliveryService: {
      configured: true,
      provider: 'resend',
      async sendPasswordReset() {
        return {
          accepted: false,
          provider: 'resend',
          failureCode: 'email_provider_unavailable',
        };
      },
    },
  });
  const app = await forgotPasswordApp(service);
  t.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/forgot-password',
    payload: { email: 'owner@avera.test' },
  });

  assert.equal(response.statusCode, 503);
  assert.equal(response.json().error, 'password_reset_delivery_failed');
});

test('forgot-password rate limiting uses trusted forwarded client addresses', async (t) => {
  let requests = 0;
  const app = await forgotPasswordApp({
    async request() {
      requests += 1;
      return { accepted: true };
    },
  });
  t.after(() => app.close());

  const send = (address) => app.inject({
    method: 'POST',
    url: '/api/v1/auth/forgot-password',
    headers: { 'x-forwarded-for': address },
    payload: { email: 'owner@avera.test' },
  });

  for (let index = 0; index < 5; index += 1) {
    assert.equal((await send('203.0.113.10')).statusCode, 202);
  }
  assert.equal((await send('203.0.113.11')).statusCode, 202);
  assert.equal((await send('203.0.113.10')).statusCode, 429);
  assert.equal(requests, 6);
});

test('password reset is single-use, unlocks the account, and revokes sessions', async () => {
  const harness = resetHarness();
  const service = new PasswordResetService({
    pool: harness.pool,
    environment,
    deliveryService: { configured: true },
  });
  const password = 'NewSecure!Password234';

  const result = await service.reset({
    rawToken: harness.rawToken,
    password,
    confirmPassword: password,
    ipAddress: '127.0.0.1',
  });

  assert.equal(result.reset, true);
  assert.equal(harness.state.status, 'Active');
  assert.equal(harness.state.sessionsRevoked, true);
  assert.equal(await verifyPassword(password, harness.state.passwordHash), true);
  assert.deepEqual(harness.state.audits, ['password.reset_completed']);
  await assert.rejects(
    service.reset({
      rawToken: harness.rawToken,
      password,
      confirmPassword: password,
    }),
    (error) => error.code === 'password_reset_invalid',
  );
});

test('expired password reset tokens cannot change the password', async () => {
  const harness = resetHarness({ expired: true });
  const service = new PasswordResetService({
    pool: harness.pool,
    environment,
    deliveryService: { configured: true },
  });

  await assert.rejects(
    service.reset({
      rawToken: harness.rawToken,
      password: 'NewSecure!Password234',
      confirmPassword: 'NewSecure!Password234',
    }),
    (error) => error.code === 'password_reset_invalid',
  );
  assert.equal(harness.state.passwordHash, 'old-password-hash');
  assert.equal(harness.state.sessionsRevoked, false);
});

test('password reset URL puts the opaque token only in the query string', () => {
  const url = new URL(
    passwordResetUrl(environment.AVERA_PASSWORD_RESET_BASE_URL, 'opaque-token'),
  );
  assert.equal(url.origin, 'https://accounts.averavet.sbs');
  assert.equal(url.pathname, '/reset-password');
  assert.equal(url.searchParams.get('token'), 'opaque-token');
});
