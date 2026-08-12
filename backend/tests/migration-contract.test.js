import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { signInSchema } from '../src/routes/auth-routes.js';
import {
  createConsultationSchema,
  createAppointmentSchema,
  createInventoryItemSchema,
  createInvoiceSchema,
  createPatientSchema,
  createVaccinationSchema,
  formatPatientHospitalNumber,
  patientStatusSchema,
  suggestedPatientPrefix,
  cancelAppointmentSchema,
  updateAppointmentSchema,
  updateInventoryItemSchema,
  updateConsultationSchema,
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

test('staff numbering migration is clinic scoped and concurrency safe', () => {
  const staffNumbering = fs.readFileSync(
    new URL('../migrations/017_clinic_staff_number_sequences.sql', import.meta.url),
    'utf8',
  );
  assert.match(staffNumbering, /ADD COLUMN IF NOT EXISTS clinic_id UUID/);
  assert.match(staffNumbering, /duplicate clinic staff numbers require review/);
  assert.match(staffNumbering, /staff_profiles_clinic_staff_number_unique/);
  assert.match(staffNumbering, /clinic_staff_number_sequences/);
  assert.match(staffNumbering, /PRIMARY KEY REFERENCES clinics\(clinic_id\)/);
  assert.match(staffNumbering, /staff_number ~ '\^\[0-9\]\+\$'/);
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
  const roleContractMigration = fs.readFileSync(
    new URL(
      '../migrations/014_role_contract_and_administrator_protection.sql',
      import.meta.url,
    ),
    'utf8',
  );
  for (const key of clinicAdministratorPermissionKeys.filter(
    (key) => key !== 'staff.roles.manage',
  )) {
    assert.match(permissionMigration, new RegExp(key.replaceAll('.', '\\.')));
  }
  assert.match(roleContractMigration, /staff\.roles\.manage/);
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
  assert.match(routes, /p\.is_date_of_birth_estimated/);
  assert.match(routes, /p\.original_age_value/);
  assert.match(routes, /p\.original_age_unit/);
  assert.match(routes, /p\.age_recorded_at/);
});

test('clinic mutation migration preserves idempotency, revisions, and soft deletion', () => {
  const mutations = fs.readFileSync(
    new URL('../migrations/013_clinic_mutation_contracts.sql', import.meta.url),
    'utf8',
  );

  assert.match(mutations, /consultations_clinic_submission_unique/);
  assert.match(mutations, /inventory_clinic_submission_unique/);
  assert.match(mutations, /submission_id UUID/);
  assert.match(mutations, /revision BIGINT NOT NULL DEFAULT 1/);
  assert.match(mutations, /deleted_at TIMESTAMPTZ/);
  assert.match(mutations, /WHERE submission_id IS NOT NULL/);
  assert.match(mutations, /UPDATE inventory_products[\s\S]*WHERE category_key IS NULL/);
});

test('production workflow migration adds idempotent vaccination, appointment, and staff invitation contracts', () => {
  const workflows = fs.readFileSync(
    new URL('../migrations/016_production_workflow_completion.sql', import.meta.url),
    'utf8',
  );
  assert.match(workflows, /ALTER TABLE vaccinations/);
  assert.match(workflows, /ALTER TABLE schedule_entries/);
  assert.match(workflows, /vaccinations_clinic_submission_idx/);
  assert.match(workflows, /schedule_entries_clinic_submission_idx/);
  assert.match(workflows, /activation_tokens_one_live_staff_token_idx/);
  assert.match(workflows, /purpose = 'StaffInvitation'/);
});

test('clinic mutation payloads reject unsafe patient, consultation, and inventory values', () => {
  assert.equal(patientStatusSchema.safeParse({ status: 'Deceased' }).success, true);
  assert.equal(patientStatusSchema.safeParse({ status: 'Deleted' }).success, false);

  const consultation = {
    submissionId: 'ab40733b-b109-4587-95cf-ed9264dfe4b8',
    patientId: '774d6508-e036-442f-80b1-b5a2ac89de66',
    chiefComplaint: 'Reduced appetite',
    veterinarian: 'Dr. Chinedu Emmanuel',
  };
  assert.equal(createConsultationSchema.safeParse(consultation).success, true);
  assert.equal(
    createConsultationSchema.safeParse({ ...consultation, chiefComplaint: ' ' }).success,
    false,
  );
  assert.equal(updateConsultationSchema.safeParse({
    revision: 1,
    chiefComplaint: 'Reduced appetite',
    history: 'Two days',
    diagnosis: 'Gastroenteritis',
  }).success, true);
  assert.equal(updateConsultationSchema.safeParse({
    revision: 0,
    chiefComplaint: 'Reduced appetite',
  }).success, false);
  assert.equal(updateConsultationSchema.safeParse({
    revision: 1,
    chiefComplaint: 'Reduced appetite',
    patientId: 'a6c10dd9-2501-43db-b083-b613faaf8ea4',
  }).success, false);

  const inventory = {
    submissionId: 'b695c4c7-c80a-466b-bfdc-a51dac4d40b3',
    name: 'Amoxicillin 250 mg',
    categoryId: 'drugs',
    categoryName: 'Drugs',
    quantity: 12,
    reorderLevel: 5,
    batchNumber: 'AMX-2026-01',
    expiryDate: '2027-06-30',
    purchasePrice: 1200,
    sellingPrice: 1800,
  };
  assert.equal(createInventoryItemSchema.safeParse(inventory).success, true);
  assert.equal(
    createInventoryItemSchema.safeParse({ ...inventory, quantity: -1 }).success,
    false,
  );
  const { submissionId: _submissionId, ...update } = inventory;
  assert.equal(updateInventoryItemSchema.safeParse({ ...update, revision: 2 }).success, true);
  assert.equal(updateInventoryItemSchema.safeParse({ ...update, revision: 0 }).success, false);
});

test('clinical mutation routes remain permission guarded and clinic scoped', () => {
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );

  for (const permissionName of [
    'patientsEdit',
    'consultationsCreate',
    'consultationsEdit',
    'inventoryCreate',
    'inventoryEdit',
    'vaccinationsAdd',
    'appointmentsCreate',
    'appointmentsEdit',
    'appointmentsCancel',
    'billingCreate',
  ]) {
    assert.match(
      routes,
      new RegExp(`requirePermission\\(permissions\\.${permissionName}\\)`),
    );
  }
  assert.match(routes, /WHERE clinic_id = \$1 AND patient_id = \$2/);
  assert.match(routes, /WHERE clinic_id = \$1 AND inventory_product_id = \$2/);
  assert.match(routes, /status = \$1,[\s\S]*revision = revision \+ 1/);
  assert.equal(
    routes.match(/ON CONFLICT \(clinic_id, submission_id\)/g)?.length,
    4,
  );
  assert.equal(routes.match(/duplicateSubmission: true/g)?.length, 10);
  assert.match(
    routes,
    /app\.get\('\/api\/v1\/consultations\/:consultationId'[\s\S]*permissions\.consultationsView/,
  );
  assert.match(
    routes,
    /app\.patch\('\/api\/v1\/consultations\/:consultationId'[\s\S]*permissions\.consultationsEdit/,
  );
  assert.match(routes, /revision_conflict/);
  assert.match(
    routes,
    /app\.get\('\/api\/v1\/vaccinations\/:vaccinationId'[\s\S]*permissions\.vaccinationsView/,
  );
  assert.match(
    routes,
    /app\.get\('\/api\/v1\/schedule\/:appointmentId'[\s\S]*permissions\.appointmentsView/,
  );
  assert.match(
    routes,
    /app\.patch\('\/api\/v1\/schedule\/:appointmentId'[\s\S]*permissions\.appointmentsEdit/,
  );
  assert.match(
    routes,
    /app\.post\('\/api\/v1\/schedule\/:appointmentId\/cancel'[\s\S]*permissions\.appointmentsCancel/,
  );
  assert.match(routes, /appointment\.rescheduled/);
  assert.match(routes, /appointment\.cancelled/);
  assert.match(routes, /lower\(s\.status\) <> 'cancelled'/);
  assert.match(routes, /membership_status='Active'/);
  assert.doesNotMatch(routes, /clinic_memberships[\s\S]{0,120}\.status='Active'/);
  assert.match(
    routes,
    /WHERE c\.clinic_id = \$1 AND c\.consultation_id = \$2/,
  );
  assert.match(
    routes,
    /consultation_id AS record_id, patient_id/,
  );
  for (const [path, permission] of [
    ['billing', 'billingView'],
    ['appointments', 'appointmentsView'],
    ['documents', 'mediaView'],
    ['images', 'mediaView'],
  ]) {
    assert.match(
      routes,
      new RegExp(`\\['${path}',[\\s\\S]*?permissions\\.${permission}`),
    );
  }
});

test('appointment update contracts are revision-safe and reject identity changes', () => {
  const update = {
    revision: 2,
    scheduledAt: '2026-08-12T09:30:00.000Z',
    visitType: 'Follow-up',
    assignedStaffId: null,
    notes: 'Review appetite and hydration.',
  };
  assert.equal(updateAppointmentSchema.safeParse(update).success, true);
  assert.equal(
    updateAppointmentSchema.safeParse({ ...update, revision: 0 }).success,
    false,
  );
  assert.equal(
    updateAppointmentSchema.safeParse({ ...update, patientId: 'patient-other' }).success,
    false,
  );
  assert.equal(cancelAppointmentSchema.safeParse({ revision: 2 }).success, true);
  assert.equal(
    cancelAppointmentSchema.safeParse({ revision: 2, clinicId: 'clinic-other' }).success,
    false,
  );
});

test('clinical operations use canonical patients and idempotent tenant storage', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/015_clinical_operations.sql', import.meta.url),
    'utf8',
  );
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(migration, /patient_id UUID NOT NULL REFERENCES patients/);
  assert.match(migration, /UNIQUE \(clinic_id, submission_id\)/);
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
  assert.match(routes, /patientExists\(client, request\.auth\.clinicId, input\.patientId\)/);
  assert.match(routes, /operationPermissions\[input\.operationType\]\.create/);
  assert.match(routes, /app\.post\('\/api\/v1\/clinical-operations'/);
});

test('patient-linked production mutations require canonical UUIDs', () => {
  const patientId = 'a6c10dd9-2501-43db-b083-b613faaf8ea4';
  const submissionId = 'ae12d6d7-ee38-48db-9937-a5de1633f102';
  assert.equal(createVaccinationSchema.safeParse({
    submissionId, patientId, vaccineName: 'Rabies',
    administeredAt: '2026-08-06T10:00:00.000Z',
  }).success, true);
  assert.equal(createAppointmentSchema.safeParse({
    submissionId, patientId, visitType: 'Consultation',
    scheduledAt: '2026-08-07T10:00:00.000Z',
  }).success, true);
  assert.equal(createInvoiceSchema.safeParse({
    submissionId, patientId, status: 'Draft', subtotal: 5000, total: 5000,
  }).success, true);
  for (const schema of [createVaccinationSchema, createAppointmentSchema, createInvoiceSchema]) {
    const result = schema.safeParse({
      submissionId, patientId: 'AVR-2026-00001', vaccineName: 'Rabies',
      administeredAt: '2026-08-06T10:00:00.000Z', visitType: 'Consultation',
      scheduledAt: '2026-08-07T10:00:00.000Z', status: 'Draft',
      subtotal: 5000, total: 5000,
    });
    assert.equal(result.success, false);
  }
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

test('production reminders are durable, tenant scoped, and deduplicated', () => {
  const reminders = fs.readFileSync(
    new URL('../migrations/018_production_reminders.sql', import.meta.url),
    'utf8',
  );
  assert.match(reminders, /CREATE TABLE IF NOT EXISTS clinic_notifications/);
  assert.match(reminders, /UNIQUE \(clinic_id, user_id, dedupe_key\)/);
  assert.match(reminders, /related_entity_type/);
  assert.match(reminders, /related_entity_id UUID/);
  assert.match(reminders, /read_at TIMESTAMPTZ/);
  assert.match(reminders, /dismissed_at TIMESTAMPTZ/);
  assert.match(reminders, /ENABLE ROW LEVEL SECURITY/);
  assert.match(reminders, /clinic_id::text = current_setting\('avera\.clinic_id'/);

  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /\/api\/v1\/reminders/);
  assert.match(routes, /\/api\/v1\/notifications/);
  assert.match(routes, /ORDER BY scheduled_at ASC/);
  assert.match(routes, /ON CONFLICT \(clinic_id,user_id,dedupe_key\)/);
  assert.match(routes, /lower\(s\.status\) NOT IN \('cancelled','completed','missed'\)/);
  assert.match(routes, /lower\(r\.status\) NOT IN \('completed','cancelled','administered','missed','withheld','archived'\)/);
  assert.match(routes, /NOT EXISTS \(\s*SELECT 1 FROM vaccinations newer/);
  assert.match(routes, /dismissObsoleteReminderNotifications/);
  assert.match(routes, /NOT \(dedupe_key = ANY\(\$3::text\[\]\)\)/);
  assert.doesNotMatch(routes, /dismissed_at=NULL/);
});

test('reminder feed covers dated clinical sources with exact ordering', () => {
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /FROM schedule_entries s JOIN patients p/);
  assert.match(routes, /v\.next_due_at, v\.next_due_at - interval '1 day'/);
  assert.match(routes, /r\.operation_type='\$\{type\}'/);
  assert.match(routes, /c\.follow_up_at/);
  assert.match(routes, /ORDER BY scheduled_at ASC LIMIT 100/);
  assert.match(routes, /lower\(v\.status\) NOT IN \('cancelled','archived'\)/);
  assert.match(routes, /newer\.administered_at > v\.administered_at/);
});

test('recent activity orders appointments by lifecycle activity, not future visit time', () => {
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(
    routes,
    /SELECT 'Schedule', 'Schedule', 'Schedule', schedule_entry_id, patient_id,\s+coalesce\(updated_at, created_at\), visit_type, status/,
  );
});
