import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { signInSchema } from '../src/routes/auth-routes.js';

const migration = fs.readFileSync(new URL('../migrations/001_secure_foundation.sql', import.meta.url), 'utf8');

test('secure foundation migration contains tenant, session, permission, and audit tables', () => {
  for (const table of ['clinics', 'users', 'roles', 'permissions', 'sessions', 'audit_logs', 'sync_metadata']) {
    assert.match(migration, new RegExp(`CREATE TABLE ${table}`));
  }
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /refresh_token_hash/);
});

test('membership migration supports one global identity across clinic memberships', () => {
  const memberships = fs.readFileSync(new URL('../migrations/002_memberships_and_platform.sql', import.meta.url), 'utf8');
  for (const table of ['clinic_memberships', 'activation_tokens', 'clinic_applications', 'platform_settings', 'plans']) {
    assert.match(memberships, new RegExp(`CREATE TABLE ${table}`));
  }
  assert.match(memberships, /UNIQUE \(user_id, clinic_id\)/);
  assert.match(memberships, /ENABLE ROW LEVEL SECURITY/);
});

test('authentication security migration protects MFA and revocation state', () => {
  const security = fs.readFileSync(
    new URL('../migrations/007_auth_security.sql', import.meta.url),
    'utf8',
  );
  assert.match(security, /token_version/);
  assert.match(security, /user_mfa_settings/);
  assert.match(security, /encrypted_totp_secret/);
  assert.match(security, /user_recovery_codes/);
  assert.match(security, /mfa_challenges/);
  assert.match(security, /security\.twoFactor\.manageSelf/);
});

test('demo clinical migration is tenant-scoped and identifies removable demo rows', () => {
  const demo = fs.readFileSync(new URL('../migrations/004_demo_clinical_domain.sql', import.meta.url), 'utf8');
  for (const table of ['owners', 'patients', 'consultations', 'laboratory_reports', 'hospitalizations', 'surgeries', 'inventory_products', 'invoices', 'payments', 'schedule_entries']) {
    assert.match(demo, new RegExp(`CREATE TABLE ${table}`));
  }
  assert.match(demo, /demo_dataset_id/);
  assert.match(demo, /is_demo BOOLEAN/);
  assert.match(demo, /ENABLE ROW LEVEL SECURITY/);
});

test('development seeding uses strict-validation .test identities and migrates legacy users in place', () => {
  const seed = fs.readFileSync(new URL('../src/database/seed-development.js', import.meta.url), 'utf8');
  assert.match(seed, /owner@avera\.test/);
  assert.match(seed, /admin@avera\.test/);
  assert.match(seed, /owner@avera\.local/);
  assert.match(seed, /admin@zevora\.local/);
  assert.match(seed, /UPDATE users SET email = \$1/);
  assert.match(seed, /account_type = \$3/);
  assert.match(seed, /SET password_hash = \$1/);
  assert.match(seed, /INSERT INTO clinic_memberships/);
  assert.match(seed, /UPDATE sessions SET revoked_at = now\(\)/);
});

test('sign-in validation accepts omitted optional fields but rejects null values', () => {
  assert.equal(signInSchema.safeParse({ email: 'admin@avera.test', password: 'unchanged' }).success, true);
  assert.equal(signInSchema.safeParse({ email: 'admin@avera.test', password: 'unchanged', deviceName: null }).success, false);
  assert.equal(signInSchema.safeParse({ email: 'not-an-email', password: 'unchanged' }).success, false);
  assert.equal(signInSchema.safeParse({ email: 'admin@avera.test', password: '' }).success, false);
});
