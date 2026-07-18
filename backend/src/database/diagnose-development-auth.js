import { loadEnvironment } from '../config/env.js';
import { createPool } from './pool.js';
import { verifyPassword } from '../security/passwords.js';

const environment = loadEnvironment();
if (environment.NODE_ENV === 'production' || !environment.localDevelopmentAuth) {
  throw new Error('Development authentication diagnostics are disabled outside explicit local development mode.');
}

const adminEmail = 'admin@avera.test';
const ownerEmail = 'owner@avera.test';
const pool = createPool(environment.DATABASE_URL);

try {
  await pool.query('SELECT 1');
  console.log('database reachable: true');

  const [admin, owner, legacy] = await Promise.all([
    loadIdentity(adminEmail),
    loadIdentity(ownerEmail),
    pool.query("SELECT COUNT(*)::int AS count FROM users WHERE email IN ('owner@avera.local', 'admin@zevora.local')"),
  ]);

  reportIdentity('admin', admin);
  reportIdentity('owner', owner);
  console.log(`legacy development users remaining: ${legacy.rows[0].count}`);
  console.log(`admin password env set: ${Boolean(process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD)}`);
  console.log(`owner password env set: ${Boolean(process.env.DEVELOPMENT_PLATFORM_OWNER_PASSWORD)}`);
  console.log(`admin password matches env hash: ${await passwordMatches(admin, process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD)}`);
  console.log(`owner password matches env hash: ${await passwordMatches(owner, process.env.DEVELOPMENT_PLATFORM_OWNER_PASSWORD)}`);

  const apiBaseUrl = process.env.AUTH_DIAGNOSTIC_API_URL ?? `http://127.0.0.1:${environment.PORT}`;
  console.log(`sign-in endpoint admin result: ${await signInStatus(apiBaseUrl, adminEmail, process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD)}`);
  console.log(`sign-in endpoint owner result: ${await signInStatus(apiBaseUrl, ownerEmail, process.env.DEVELOPMENT_PLATFORM_OWNER_PASSWORD)}`);
} catch (error) {
  console.log('database reachable: false');
  console.error(`diagnostic failed: ${error.code ?? error.name}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}

async function loadIdentity(email) {
  const result = await pool.query(
    `SELECT u.email, u.status, u.password_hash, u.clinic_id, c.status AS clinic_status,
            COUNT(cm.membership_id)::int AS membership_count,
            COALESCE(bool_or(cm.membership_status = 'Active'), false) AS membership_active
       FROM users u
       LEFT JOIN clinics c ON c.clinic_id = u.clinic_id AND c.deleted_at IS NULL
       LEFT JOIN clinic_memberships cm
         ON cm.user_id = u.user_id AND cm.clinic_id = u.clinic_id AND cm.deleted_at IS NULL
      WHERE u.email = $1 AND u.deleted_at IS NULL
      GROUP BY u.user_id, c.status`,
    [email],
  );
  return result.rows[0] ?? null;
}

function reportIdentity(label, identity) {
  console.log(`${label} user exists: ${Boolean(identity)}`);
  console.log(`${label} email: ${identity?.email ?? 'not found'}`);
  console.log(`${label} account status: ${identity?.status ?? 'not found'}`);
  console.log(`${label} membership count: ${identity?.membership_count ?? 0}`);
  console.log(`${label} membership active: ${identity?.membership_active ?? false}`);
  console.log(`${label} clinic active: ${identity?.clinic_id ? identity.clinic_status === 'Active' : 'not applicable'}`);
  console.log(`${label} password hash exists: ${Boolean(identity?.password_hash)}`);
}

async function passwordMatches(identity, password) {
  if (!identity?.password_hash || !password) return false;
  return verifyPassword(password, identity.password_hash);
}

async function signInStatus(apiBaseUrl, email, password) {
  if (!password) return 'not tested (password env missing)';
  try {
    const response = await fetch(`${apiBaseUrl}/api/v1/auth/sign-in`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email, password, deviceName: 'Development auth diagnostic', platform: 'node' }),
    });
    if (response.status === 200) {
      const body = await response.json();
      if (typeof body.accessToken === 'string') {
        await fetch(`${apiBaseUrl}/api/v1/auth/sign-out`, {
          method: 'POST',
          headers: { authorization: `Bearer ${body.accessToken}` },
        });
      }
    }
    return `HTTP ${response.status}`;
  } catch {
    return 'unavailable';
  }
}
