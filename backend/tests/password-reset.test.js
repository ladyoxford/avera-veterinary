import assert from 'node:assert/strict';
import test from 'node:test';

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

function requestHarness({ includeUser = true } = {}) {
  const state = {
    audits: [],
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
        state.audits.push(parameters[4]);
        return { rows: [] };
      }
      throw new Error(`Unexpected password reset request query: ${sql}`);
    },
    release() {},
  };
  return {
    state,
    pool: { connect: async () => client },
  };
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
