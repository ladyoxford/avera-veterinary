import assert from 'node:assert/strict';
import test from 'node:test';
import {
  ActivationEmailDeliveryService,
  ClinicAdministratorActivationService,
} from '../src/services/clinic-administrator-activation-service.js';
import { hashToken } from '../src/security/tokens.js';
import { verifyPassword } from '../src/security/passwords.js';

const environment = {
  ACTIVATION_TOKEN_TTL_MINUTES: 60,
  AVERA_ACTIVATION_BASE_URL: 'https://accounts.averavet.sbs/activate-clinic-admin',
  AVERA_STAFF_ACTIVATION_BASE_URL: 'https://accounts.averavet.sbs/activate-staff',
};

function service(pool) {
  return new ClinicAdministratorActivationService({
    pool,
    environment,
    deliveryService: new ActivationEmailDeliveryService({ environment }),
  });
}

function approvalHarness() {
  const state = {
    calls: [],
    application: {
      application_id: 'application-1',
      administrator_name: 'Ada Clinic Owner',
      administrator_email: 'ADA@EXAMPLE.COM',
      administrator_phone: '+2348000000000',
    },
    user: null,
    liveToken: null,
    tokenInsertCount: 0,
    membershipCount: 0,
  };
  const client = {
    async query(sql, parameters = []) {
      state.calls.push({ sql, parameters });
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.includes("set_config('avera.")) return { rows: [] };
      if (sql.includes('FROM clinic_applications') && sql.includes('FOR UPDATE')) return { rows: [state.application] };
      if (sql.includes('INSERT INTO roles')) return { rows: [{ role_id: 'role-admin' }] };
      if (sql.includes('SELECT permission_id, permission_key')) return { rows: [{ permission_id: 'permission-1', permission_key: 'patients.view' }] };
      if (sql.includes('INSERT INTO role_permissions')) return { rows: [] };
      if (sql.includes('SELECT * FROM users WHERE email')) return { rows: state.user ? [state.user] : [] };
      if (sql.includes('INSERT INTO users')) {
        state.user = {
          user_id: 'user-admin',
          clinic_id: parameters[0],
          full_name: parameters[1],
          email: parameters[2],
          phone: parameters[3],
          password_hash: null,
          account_type: 'ClinicAdministrator',
          status: 'PendingActivation',
          role_id: parameters[4],
        };
        return { rows: [state.user] };
      }
      if (sql.includes('UPDATE users') && sql.includes("status = 'PendingActivation'")) return { rows: [state.user] };
      if (sql.includes('INSERT INTO clinic_memberships')) {
        state.membershipCount = 1;
        return { rows: [] };
      }
      if (sql.includes('UPDATE clinic_applications')) return { rows: [] };
      if (sql.includes('SELECT token_id, expires_at FROM activation_tokens')) return { rows: state.liveToken ? [state.liveToken] : [] };
      if (sql.includes('UPDATE activation_tokens SET revoked_at')) {
        state.liveToken = null;
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO activation_tokens')) {
        state.tokenInsertCount += 1;
        state.liveToken = {
          token_id: `token-${state.tokenInsertCount}`,
          expires_at: parameters[4],
          token_hash: parameters[3],
        };
        return { rows: [{ token_id: state.liveToken.token_id }] };
      }
      if (sql.includes('SELECT clinic_id, name, status FROM clinics')) return { rows: [{ clinic_id: 'clinic-1', name: 'Ada Veterinary Clinic', status: 'Active' }] };
      if (sql.includes('SELECT * FROM users') && sql.includes("account_type = 'ClinicAdministrator'")) return { rows: state.user ? [state.user] : [] };
      if (sql.includes('INSERT INTO audit_logs')) return { rows: [] };
      throw new Error(`Unexpected approval query: ${sql}`);
    },
    release() {},
  };
  return {
    state,
    client,
    pool: {
      connect: async () => client,
      query: (...arguments_) => client.query(...arguments_),
    },
  };
}

function tokenHarness({ expired = false, used = false } = {}) {
  const rawToken = 'secure-activation-token-with-more-than-32-characters';
  const state = {
    calls: [],
    userStatus: 'PendingActivation',
    passwordHash: null,
    usedAt: used ? new Date() : null,
    revokedAt: null,
  };
  const client = {
    async query(sql, parameters = []) {
      state.calls.push({ sql, parameters });
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.includes("set_config('avera.")) return { rows: [] };
      if (sql.includes('FROM activation_tokens t')) {
        if (parameters[0] !== hashToken(rawToken)) return { rows: [] };
        return {
          rows: [{
            token_id: 'token-1',
            user_id: 'user-1',
            clinic_id: 'clinic-1',
            expires_at: expired ? new Date(Date.now() - 1_000) : new Date(Date.now() + 60_000),
            used_at: state.usedAt,
            revoked_at: state.revokedAt,
            full_name: 'Ada Clinic Owner',
            email: 'ada@example.com',
            user_status: state.userStatus,
            clinic_name: 'Ada Veterinary Clinic',
            clinic_status: 'Active',
          }],
        };
      }
      if (sql.includes('UPDATE users') && sql.includes('password_hash')) {
        state.passwordHash = parameters[1];
        state.userStatus = 'Active';
        return { rows: [] };
      }
      if (sql.includes('UPDATE activation_tokens') && sql.includes('used_at = CASE')) {
        state.usedAt = parameters[2];
        return { rows: [] };
      }
      if (sql.includes('UPDATE clinic_memberships') || sql.includes('UPDATE sessions') || sql.includes('INSERT INTO audit_logs')) return { rows: [] };
      throw new Error(`Unexpected activation query: ${sql}`);
    },
    release() {},
  };
  return {
    rawToken,
    state,
    pool: {
      connect: async () => client,
      query: (...arguments_) => client.query(...arguments_),
    },
  };
}

function staffHarness({ expired = false, used = false, revoked = false } = {}) {
  const rawToken = 'secure-staff-activation-token-with-more-than-32-characters';
  const state = {
    calls: [],
    userStatus: 'PendingActivation',
    membershipStatus: 'Invited',
    passwordHash: null,
    usedAt: used ? new Date() : null,
    revokedAt: revoked ? new Date() : null,
    tokenInsertCount: 0,
  };
  const client = {
    async query(sql, parameters = []) {
      state.calls.push({ sql, parameters });
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.includes("set_config('avera.")) return { rows: [] };
      if (sql.includes('SELECT r.code FROM clinic_memberships')) return { rows: [{ code: 'clinic_administrator' }] };
      if (sql.includes('SELECT role_id, name, code FROM roles')) return { rows: [{ role_id: 'role-vet', name: 'Veterinarian', code: 'veterinarian' }] };
      if (sql.includes('SELECT * FROM users WHERE email')) return { rows: [] };
      if (sql.includes('INSERT INTO users')) return { rows: [{ user_id: 'staff-1', clinic_id: 'clinic-1', full_name: parameters[1], email: parameters[2], status: 'PendingActivation' }] };
      if (sql.includes('INSERT INTO clinic_memberships') || sql.includes('INSERT INTO staff_profiles')) return { rows: [] };
      if (sql.includes('SELECT name FROM clinics')) return { rows: [{ name: 'Ada Veterinary Clinic' }] };
      if (sql.includes('UPDATE activation_tokens SET revoked_at')) {
        state.revokedAt = new Date();
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO activation_tokens')) {
        state.tokenInsertCount += 1;
        return { rows: [{ token_id: `staff-token-${state.tokenInsertCount}` }] };
      }
      if (sql.includes('FROM activation_tokens t')) {
        if (parameters[0] !== hashToken(rawToken)) return { rows: [] };
        return { rows: [{
          token_id: 'staff-token-existing', user_id: 'staff-1', clinic_id: 'clinic-1',
          expires_at: expired ? new Date(Date.now() - 1000) : new Date(Date.now() + 60000),
          used_at: state.usedAt, revoked_at: state.revokedAt,
          full_name: 'Jane Vet', email: 'jane@example.com',
          user_status: state.userStatus, membership_status: state.membershipStatus,
          clinic_name: 'Ada Veterinary Clinic', clinic_status: 'Active', role_name: 'Veterinarian',
        }] };
      }
      if (sql.includes('UPDATE users SET password_hash')) {
        state.passwordHash = parameters[1];
        state.userStatus = 'Active';
        return { rows: [] };
      }
      if (sql.includes("UPDATE clinic_memberships SET membership_status='Active'")) {
        state.membershipStatus = 'Active';
        return { rows: [] };
      }
      if (sql.includes('UPDATE activation_tokens') && sql.includes('used_at=CASE')) {
        state.usedAt = parameters[2];
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO audit_logs')) return { rows: [] };
      throw new Error(`Unexpected staff activation query: ${sql}`);
    },
    release() {},
  };
  return {
    rawToken,
    state,
    pool: { connect: async () => client, query: (...arguments_) => client.query(...arguments_) },
  };
}

test('approval provisions exactly one passwordless pending administrator and is idempotent', async () => {
  const harness = approvalHarness();
  const activation = service(harness.pool);
  const context = {
    clinicId: 'clinic-1',
    clinicName: 'Ada Veterinary Clinic',
    actorUserId: 'platform-owner-1',
  };

  const first = await activation.provisionOnApproval(harness.client, context);
  const second = await activation.provisionOnApproval(harness.client, context);

  assert.equal(first.user.status, 'PendingActivation');
  assert.equal(first.user.password_hash, null);
  assert.ok(first.issued.rawToken);
  assert.equal(second.issued, null);
  assert.equal(harness.state.tokenInsertCount, 1);
  assert.equal(harness.state.membershipCount, 1);
  assert.equal(harness.state.calls.filter((call) => call.sql.includes('INSERT INTO users')).length, 1);
});

test('activation token is hashed and plaintext is never passed to persistence', async () => {
  const harness = approvalHarness();
  const result = await service(harness.pool).provisionOnApproval(harness.client, {
    clinicId: 'clinic-1',
    clinicName: 'Ada Veterinary Clinic',
    actorUserId: 'platform-owner-1',
  });
  const tokenInsert = harness.state.calls.find((call) => call.sql.includes('INSERT INTO activation_tokens'));
  assert.equal(tokenInsert.parameters[3], hashToken(result.issued.rawToken));
  assert.notEqual(tokenInsert.parameters[3], result.issued.rawToken);
  assert.equal(JSON.stringify(harness.state.calls).includes(result.issued.rawToken), false);
});

test('expired and already-used activation tokens are rejected', async () => {
  for (const options of [{ expired: true }, { used: true }]) {
    const harness = tokenHarness(options);
    await assert.rejects(
      service(harness.pool).inspect(harness.rawToken),
      options.expired ? /expired/i : /already been used/i,
    );
  }
});

test('successful activation stores bcrypt only, enables login credentials, and prevents reuse', async () => {
  const harness = tokenHarness();
  const password = 'SecureClinic#2026';
  const result = await service(harness.pool).activate({
    rawToken: harness.rawToken,
    password,
    confirmPassword: password,
  });

  assert.equal(result.activated, true);
  assert.equal(harness.state.userStatus, 'Active');
  assert.notEqual(harness.state.passwordHash, password);
  assert.equal(await verifyPassword(password, harness.state.passwordHash), true);
  assert.equal(JSON.stringify(harness.state.calls).includes(password), false);
  await assert.rejects(
    service(harness.pool).activate({
      rawToken: harness.rawToken,
      password,
      confirmPassword: password,
    }),
    /already been used/i,
  );
});

test('staff invitation is passwordless, token-hashed, tenant-scoped, and pending activation', async () => {
  const harness = staffHarness();
  const result = await service(harness.pool).inviteStaff({
    clinicId: 'clinic-1', actorUserId: 'admin-1', fullName: 'Jane Vet',
    email: 'jane@example.com', roleName: 'Veterinarian', ipAddress: '127.0.0.1',
  });
  assert.equal(result.status, 'PendingActivation');
  assert.equal(result.delivery.status, 'DeliveryUnavailable');
  const userInsert = harness.state.calls.find((call) => call.sql.includes('INSERT INTO users'));
  assert.match(userInsert.sql, /NULL,'ClinicStaff','PendingActivation'/);
  const tokenInsert = harness.state.calls.find((call) => call.sql.includes('INSERT INTO activation_tokens'));
  assert.equal(typeof tokenInsert.parameters[3], 'string');
  assert.equal(JSON.stringify(harness.state.calls).includes('secure-staff-activation-token'), false);
});

test('staff activation hashes the password, activates membership, and rejects expired or reused links', async () => {
  const harness = staffHarness();
  const password = 'SecureStaff#2026';
  const result = await service(harness.pool).activateStaff({
    rawToken: harness.rawToken, password, confirmPassword: password,
  });
  assert.equal(result.activated, true);
  assert.equal(harness.state.userStatus, 'Active');
  assert.equal(harness.state.membershipStatus, 'Active');
  assert.notEqual(harness.state.passwordHash, password);
  assert.equal(await verifyPassword(password, harness.state.passwordHash), true);
  await assert.rejects(service(harness.pool).activateStaff({
    rawToken: harness.rawToken, password, confirmPassword: password,
  }), /already been used/i);
  await assert.rejects(service(staffHarness({ expired: true }).pool).inspectStaff(
    staffHarness({ expired: true }).rawToken,
  ), /invalid|expired/i);
});

test('resend revokes the previous token and issues a different one', async () => {
  const harness = approvalHarness();
  const activation = service(harness.pool);
  const first = await activation.provisionOnApproval(harness.client, {
    clinicId: 'clinic-1',
    clinicName: 'Ada Veterinary Clinic',
    actorUserId: 'platform-owner-1',
  });
  const originalHash = hashToken(first.issued.rawToken);
  const resent = await activation.resend({
    clinicId: 'clinic-1',
    actorUserId: 'platform-owner-1',
  });

  assert.equal(resent.deliveryMethod, 'manual');
  assert.match(resent.activationUrl, /^https:\/\/accounts\.averavet\.sbs\/activate-clinic-admin\?token=/);
  assert.equal(harness.state.tokenInsertCount, 2);
  assert.notEqual(harness.state.liveToken.token_hash, originalHash);
});
