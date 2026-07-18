import assert from 'node:assert/strict';
import test from 'node:test';
import { buildApp } from '../src/app.js';
import { loadEnvironment } from '../src/config/env.js';

const adminEmail = 'admin@avera.test';
const ownerEmail = 'owner@avera.test';

test('development authentication works end to end with status enforcement', async (t) => {
  assert.notEqual(process.env.NODE_ENV, 'production');
  assert.ok(process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD, 'DEVELOPMENT_CLINIC_ADMIN_PASSWORD must be set');
  assert.ok(process.env.DEVELOPMENT_PLATFORM_OWNER_PASSWORD, 'DEVELOPMENT_PLATFORM_OWNER_PASSWORD must be set');

  const environment = loadEnvironment({ ...process.env, NODE_ENV: 'test', LOG_LEVEL: 'silent' });
  const app = await buildApp({ environment });
  await app.ready();

  const admin = (await app.pool.query('SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL', [adminEmail])).rows[0];
  const owner = (await app.pool.query('SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL', [ownerEmail])).rows[0];
  assert.ok(admin, 'Seeded clinic administrator was not found');
  assert.ok(owner, 'Seeded platform owner was not found');
  const membership = (await app.pool.query('SELECT * FROM clinic_memberships WHERE user_id = $1 AND clinic_id = $2 AND deleted_at IS NULL', [admin.user_id, admin.clinic_id])).rows[0];
  const clinic = (await app.pool.query('SELECT * FROM clinics WHERE clinic_id = $1 AND deleted_at IS NULL', [admin.clinic_id])).rows[0];
  assert.ok(membership, 'Active clinic membership was not seeded');
  assert.ok(clinic, 'Administrator clinic was not found');

  const original = {
    userStatus: admin.status,
    failedLoginCount: admin.failed_login_count,
    lockedUntil: admin.locked_until,
    membershipStatus: membership.membership_status,
    clinicStatus: clinic.status,
  };

  try {
    await t.test('clinic administrator login, refresh, current user, and logout', async () => {
      const login = await signIn(app, adminEmail, process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD);
      assert.equal(login.statusCode, 200);
      const tokens = login.json();
      assert.equal(tokens.user.accountType, 'ClinicAdministrator');
      assert.equal(tokens.user.clinicId, admin.clinic_id);
      assert.ok(Array.isArray(tokens.user.permissions));
      assert.equal(typeof tokens.accessToken, 'string');
      assert.equal(typeof tokens.refreshToken, 'string');

      const refresh = await app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: tokens.refreshToken } });
      assert.equal(refresh.statusCode, 200);
      const refreshed = refresh.json();
      const me = await app.inject({ method: 'GET', url: '/api/v1/auth/me', headers: { authorization: `Bearer ${refreshed.accessToken}` } });
      assert.equal(me.statusCode, 200);
      assert.equal(me.json().user.email, adminEmail);
      const logout = await app.inject({ method: 'POST', url: '/api/v1/auth/sign-out', headers: { authorization: `Bearer ${refreshed.accessToken}` } });
      assert.equal(logout.statusCode, 204);
      const revokedRefresh = await app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: refreshed.refreshToken } });
      assert.equal(revokedRefresh.statusCode, 401);
    });

    await t.test('platform owner login routes by backend account type', async () => {
      const login = await signIn(app, ownerEmail, process.env.DEVELOPMENT_PLATFORM_OWNER_PASSWORD);
      assert.equal(login.statusCode, 200);
      const body = login.json();
      assert.equal(body.user.accountType, 'PlatformOwner');
      assert.deepEqual(body.user.permissions, ['*']);
      await signOut(app, body.accessToken);
    });

    await t.test('wrong password returns 401', async () => {
      const response = await signIn(app, adminEmail, 'incorrect-development-password');
      assert.equal(response.statusCode, 401);
      assert.equal(response.json().error, 'invalid_credentials');
    });

    await t.test('malformed email and empty password return 400', async () => {
      assert.equal((await signIn(app, 'not-an-email', 'anything')).statusCode, 400);
      assert.equal((await signIn(app, adminEmail, '')).statusCode, 400);
    });

    await t.test('email lookup is case insensitive', async () => {
      const response = await signIn(app, adminEmail.toUpperCase(), process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD);
      assert.equal(response.statusCode, 200);
      await signOut(app, response.json().accessToken);
    });

    await t.test('suspended user returns 403 with a valid password', async () => {
      await app.pool.query("UPDATE users SET status = 'Suspended' WHERE user_id = $1", [admin.user_id]);
      const response = await signIn(app, adminEmail, process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD);
      assert.equal(response.statusCode, 403);
      assert.equal(response.json().error, 'account_restricted');
      await app.pool.query("UPDATE users SET status = 'Active' WHERE user_id = $1", [admin.user_id]);
    });

    await t.test('inactive membership returns 403', async () => {
      await app.pool.query("UPDATE clinic_memberships SET membership_status = 'Suspended' WHERE membership_id = $1", [membership.membership_id]);
      const response = await signIn(app, adminEmail, process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD);
      assert.equal(response.statusCode, 403);
      assert.equal(response.json().error, 'membership_restricted');
      await app.pool.query("UPDATE clinic_memberships SET membership_status = 'Active' WHERE membership_id = $1", [membership.membership_id]);
    });

    await t.test('inactive clinic returns 403', async () => {
      await app.pool.query("UPDATE clinics SET status = 'Suspended' WHERE clinic_id = $1", [clinic.clinic_id]);
      const response = await signIn(app, adminEmail, process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD);
      assert.equal(response.statusCode, 403);
      assert.equal(response.json().error, 'clinic_restricted');
      await app.pool.query("UPDATE clinics SET status = 'Active' WHERE clinic_id = $1", [clinic.clinic_id]);
    });
  } finally {
    await app.pool.query(
      'UPDATE users SET status = $1, failed_login_count = $2, locked_until = $3 WHERE user_id = $4',
      [original.userStatus, original.failedLoginCount, original.lockedUntil, admin.user_id],
    );
    await app.pool.query('UPDATE clinic_memberships SET membership_status = $1 WHERE membership_id = $2', [original.membershipStatus, membership.membership_id]);
    await app.pool.query('UPDATE clinics SET status = $1 WHERE clinic_id = $2', [original.clinicStatus, clinic.clinic_id]);
    await app.close();
  }
});

function signIn(app, email, password) {
  return app.inject({
    method: 'POST',
    url: '/api/v1/auth/sign-in',
    payload: { email, password, deviceName: 'Authentication integration test', platform: 'node' },
  });
}

async function signOut(app, accessToken) {
  const response = await app.inject({ method: 'POST', url: '/api/v1/auth/sign-out', headers: { authorization: `Bearer ${accessToken}` } });
  assert.equal(response.statusCode, 204);
}
