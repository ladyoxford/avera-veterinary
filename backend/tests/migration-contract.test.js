import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { signInSchema } from '../src/routes/auth-routes.js';
import {
  createPatientSchema,
  formatPatientHospitalNumber,
  suggestedPatientPrefix,
} from '../src/routes/clinical-routes.js';
import {
  clinicAdministratorPermissionKeys,
  permissionCatalog,
  platformOnlyPermissionKeys,
} from '../src/security/permission-catalog.js';

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

test('clinic administrator activation migration preserves passwordless pending accounts and one live token', () => {
  const activation = fs.readFileSync(
    new URL('../migrations/009_clinic_administrator_activation.sql', import.meta.url),
    'utf8',
  );
  assert.match(activation, /PendingActivation/);
  assert.match(activation, /ALTER COLUMN password_hash DROP NOT NULL/);
  assert.match(activation, /delivery_method/);
  assert.match(activation, /duplicate_live_tokens/);
  assert.match(activation, /activation_tokens_one_live_admin_token_idx/);
});

test('production permission migration backfills clinic administrators without platform-only access', () => {
  const permissionMigration = fs.readFileSync(
    new URL('../migrations/010_production_permission_catalog.sql', import.meta.url),
    'utf8',
  );
  for (const key of clinicAdministratorPermissionKeys) {
    assert.match(permissionMigration, new RegExp(key.replaceAll('.', '\\.')));
  }
  assert.equal(new Set(permissionCatalog).size, permissionCatalog.length);
  for (const required of [
    'dashboard.view',
    'patients.view',
    'consultations.create',
    'users.assign_permissions',
  ]) assert.ok(clinicAdministratorPermissionKeys.includes(required));
  for (const restricted of platformOnlyPermissionKeys) {
    assert.equal(clinicAdministratorPermissionKeys.includes(restricted), false);
  }
  assert.match(permissionMigration, /r\.name = 'Clinic Administrator'/);
  assert.match(permissionMigration, /ON CONFLICT DO NOTHING/);
  const cleanupMigration = fs.readFileSync(
    new URL('../migrations/011_remove_unassigned_platform_permissions.sql', import.meta.url),
    'utf8',
  );
  for (const restricted of platformOnlyPermissionKeys) {
    assert.match(cleanupMigration, new RegExp(restricted.replaceAll('.', '\\.')));
  }
  assert.match(cleanupMigration, /NOT EXISTS/);
});

test('production patient registration is clinic-scoped and idempotent', () => {
  const patientRegistration = fs.readFileSync(
    new URL('../migrations/012_patient_registration.sql', import.meta.url),
    'utf8',
  );
  assert.match(patientRegistration, /clinic_number_sequences/);
  assert.match(patientRegistration, /UNIQUE \(clinic_id, sequence_type, sequence_key\)/);
  assert.match(patientRegistration, /patients_clinic_submission_uidx/);
  assert.match(
    fs.readFileSync(new URL('../migrations/004_demo_clinical_domain.sql', import.meta.url), 'utf8'),
    /UNIQUE \(clinic_id, hospital_number\)/,
  );
  assert.match(patientRegistration, /ENABLE ROW LEVEL SECURITY/);
});

test('patient registration validates input and formats clinic numbering', () => {
  const valid = {
    submissionId: '5b8ea5ed-f09b-4ed3-b440-e490f2f4e32d',
    name: 'Luna',
    species: 'Cat',
    breed: 'Domestic Shorthair',
    sex: 'Female',
    dateOfBirth: '2024-06-01',
    owner: { fullName: 'Luna Owner', phone: '08000000000' },
  };
  assert.equal(createPatientSchema.safeParse(valid).success, true);
  assert.equal(createPatientSchema.safeParse({ ...valid, owner: { fullName: '', phone: '' } }).success, false);
  assert.equal(createPatientSchema.safeParse({ ...valid, dateOfBirth: 'not-a-date' }).success, false);
  assert.equal(suggestedPatientPrefix('Biocamp Veterinary Clinic'), 'BIOCAMP');
  assert.equal(formatPatientHospitalNumber('BIOCAMP', 2026, 1, 5), 'BIOCAMP-2026-00001');
  assert.equal(formatPatientHospitalNumber('AVR', 2026, 123456, 5), 'AVR-2026-123456');
});

test('patient detail and medical-file routes build complete SELECT queries', () => {
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  const detailQueries = routes.match(
    /client\.query\(`SELECT \$\{patientList\.select\} FROM \$\{patientList\.from\}/g,
  );

  assert.equal(detailQueries?.length, 2);
  assert.doesNotMatch(
    routes,
    /client\.query\(`\$\{patientList\.select\} FROM \$\{patientList\.from\}/,
  );
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
