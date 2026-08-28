import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { signInSchema } from '../src/routes/auth-routes.js';
import {
  createConsultationSchema,
  createAppointmentSchema,
  createInventoryItemSchema,
  addInventoryStockSchema,
  createInvoiceSchema,
  createReorderRequestSchema,
  createPatientSchema,
  createVaccinationSchema,
  formatPatientHospitalNumber,
  patientStatusSchema,
  patientsShareBillingOwner,
  recordInvoicePaymentSchema,
  replaceProductUnitsSchema,
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

test('subscription pricing migration seeds only approved paid plan amounts', () => {
  const pricing = fs.readFileSync(
    new URL('../migrations/020_subscription_plan_pricing.sql', import.meta.url),
    'utf8',
  );
  assert.match(pricing, /'Professional', 500000::BIGINT, 5000000::BIGINT/);
  assert.match(pricing, /'Enterprise', 1000000::BIGINT, 10000000::BIGINT/);
  assert.match(pricing, /currency = 'NGN'/);
  assert.doesNotMatch(pricing, /'Starter'/);
  assert.doesNotMatch(pricing, /PLN_/);
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
    brandName: 'AveraVet',
    manufacturer: 'Avera Veterinary Pharmaceuticals',
    shortDescription: 'Long-acting antibiotic injection',
    detailedDescription: 'For veterinary use under professional direction.',
    dosageForm: 'Injection',
    packSize: '100 mL',
    sku: 'AV-OXY-100',
    barcode: '1234567890123',
    activeIngredient: 'Oxytetracycline 200 mg/mL',
    dosageAndRoute: '1 mL per 10 kg body weight',
    withdrawalMeat: '21 days',
    withdrawalMilk: '7 days',
    warnings: 'Do not use in hypersensitive animals',
    storageConditions: 'Store below 30 C',
    supplier: 'Avera Medical Supply',
    availableToPublic: false,
  };
  assert.equal(createInventoryItemSchema.safeParse(inventory).success, true);
  assert.equal(
    createInventoryItemSchema.safeParse({ ...inventory, quantity: -1 }).success,
    false,
  );
  const { submissionId: _submissionId, ...update } = inventory;
  assert.equal(updateInventoryItemSchema.safeParse({ ...update, revision: 2 }).success, true);
  assert.equal(updateInventoryItemSchema.safeParse({ ...update, revision: 0 }).success, false);
  assert.equal(addInventoryStockSchema.safeParse({ quantityToAdd: 10 }).success, true);
  assert.equal(addInventoryStockSchema.safeParse({ quantityToAdd: 0 }).success, false);
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
    'billingRecordPayment',
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
  assert.equal(routes.match(/duplicateSubmission: true/g)?.length, 15);
  assert.match(
    routes,
    /app\.post\('\/api\/v1\/invoices\/:invoiceId\/payments'[\s\S]*permissions\.billingRecordPayment[\s\S]*duplicateSubmission: true/,
  );
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
  assert.match(
    routes,
    /app\.get\('\/api\/v1\/patients\/:patientId\/billing'[\s\S]*?permissions\.billingView/,
  );
  for (const [path, permission] of [
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

test('multi-patient invoices accept attributed and shared lines', () => {
  const patientId = 'a6c10dd9-2501-43db-b083-b613faaf8ea4';
  const secondPatientId = 'b6c10dd9-2501-43db-b083-b613faaf8ea5';
  const result = createInvoiceSchema.safeParse({
    submissionId: 'ae12d6d7-ee38-48db-9937-a5de1633f102',
    patientId,
    patientIds: [patientId, secondPatientId],
    status: 'Draft', subtotal: 15000, total: 15000,
    services: [
      { description: 'Vaccination', amount: 5000, patientId, quantity: 1, unitPrice: 5000 },
      { description: 'Farm call', amount: 10000, patientId: null, quantity: 1, unitPrice: 10000 },
    ],
  });
  assert.equal(result.success, true);
  assert.equal(result.data.services[1].patientId, null);
  assert.equal(createInvoiceSchema.safeParse({
    submissionId: 'ae12d6d7-ee38-48db-9937-a5de1633f102',
    patientId,
    patientIds: [patientId],
    status: 'Draft', subtotal: 5000, total: 5000,
    services: [{ description: 'Invalid', amount: 5000, patientId: 'OTHER-CLINIC' }],
  }).success, false);
});

test('multi-patient invoices recognize legacy duplicate owner rows safely', () => {
  assert.equal(patientsShareBillingOwner([
    { owner_id: 'owner-1', owner_phone: '0801 234 5678', owner_email: null },
    { owner_id: 'owner-2', owner_phone: '+234 801 234 5678', owner_email: null },
  ]), true);
  assert.equal(patientsShareBillingOwner([
    { owner_id: 'owner-1', owner_phone: '', owner_email: 'OWNER@example.com' },
    { owner_id: 'owner-2', owner_phone: '', owner_email: 'owner@example.com' },
  ]), true);
  assert.equal(patientsShareBillingOwner([
    { owner_id: 'owner-1', owner_phone: '08012345678', owner_email: 'one@example.com' },
    { owner_id: 'owner-2', owner_phone: '08099999999', owner_email: 'two@example.com' },
  ]), false);
});

test('invoice payment ledger migration is additive and idempotent', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/023_invoice_payment_ledger.sql', import.meta.url),
    'utf8',
  );
  assert.match(migration, /ADD COLUMN IF NOT EXISTS reference TEXT/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS recorded_by UUID REFERENCES users\(user_id\)/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS submission_id UUID/);
  assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS payments_clinic_submission_unique/);
  assert.match(migration, /WHERE submission_id IS NOT NULL/);
});

test('invoice payment payload is strict, idempotent, and uses canonical methods', () => {
  const valid = {
    submissionId: 'ae12d6d7-ee38-48db-9937-a5de1633f103',
    amount: 12500,
    method: 'Transfer',
    paidAt: '2026-08-20T12:00:00.000Z',
    reference: 'TRX-12500',
  };
  assert.equal(recordInvoicePaymentSchema.safeParse(valid).success, true);
  assert.equal(recordInvoicePaymentSchema.safeParse({ ...valid, amount: 0 }).success, false);
  assert.equal(recordInvoicePaymentSchema.safeParse({ ...valid, method: 'Cheque' }).success, false);
  assert.equal(recordInvoicePaymentSchema.safeParse({ ...valid, unexpected: true }).success, false);

  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /\/api\/v1\/invoices\/:invoiceId\/payments/);
  assert.match(routes, /FOR UPDATE/);
  assert.match(routes, /submission_id/);
  assert.match(routes, /payment_exceeds_balance/);
  assert.match(routes, /billing\.payment_recorded/);
});

test('multi-patient invoice migration is scoped, idempotent, and preserves records', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/022_multi_patient_invoices.sql', import.meta.url),
    'utf8',
  );
  assert.match(migration, /CREATE TABLE IF NOT EXISTS invoice_line_items/);
  assert.match(migration, /patient_id UUID REFERENCES patients/);
  assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS invoices_clinic_submission_unique/);
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /clinic_id::text = current_setting\('avera\.clinic_id'/);
  assert.doesNotMatch(migration, /DROP TABLE|TRUNCATE|DELETE FROM/i);
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /patientsShareBillingOwner\(patients\.rows\)/);
  assert.match(routes, /invoice_owner_mismatch/);
  assert.match(routes, /WHERE p\.clinic_id=\$1 AND p\.patient_id = ANY/);
  assert.match(routes, /duplicateSubmission: true/);
  assert.match(routes, /existing\.status === 'Draft' && input\.status === 'Paid'/);
  assert.match(routes, /existing\.status === 'Draft' && input\.status === 'Unpaid'/);
  assert.match(routes, /SET status='Unpaid', balance=total/);
  assert.match(routes, /action: 'billing\.invoice_issued'/);
  assert.match(routes, /SET status='Paid', amount_paid=total, balance=0/);
  assert.match(routes, /action: 'billing\.sale_recorded'/);
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

test('clinic settings migration provisions durable work hours and branding', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/019_clinic_settings_and_work_hours.sql', import.meta.url),
    'utf8',
  );
  assert.match(migration, /CREATE TABLE IF NOT EXISTS clinic_work_hours/);
  assert.match(migration, /days JSONB NOT NULL/);
  assert.match(migration, /INSERT INTO clinic_work_hours/);
  assert.match(migration, /ON CONFLICT \(clinic_id\) DO NOTHING/);
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS banner_path/);
  assert.match(migration, /clinic_branding_primary_color_format/);

  const routes = fs.readFileSync(
    new URL('../src/routes/clinic-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /\/api\/v1\/clinic\/settings/);
  assert.match(routes, /\/api\/v1\/clinic\/work-hours/);
  assert.match(routes, /\/api\/v1\/clinic\/branding/);
  assert.match(routes, /\/api\/v1\/clinic\/theme-color/);
  assert.match(routes, /clinic\.work_hours_updated/);
  assert.match(routes, /clinic\.theme_color_updated/);
});

test('patient photo migration preserves patients and adds only the photo path', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/021_patient_profile_photos.sql', import.meta.url),
    'utf8',
  );
  assert.match(migration, /ALTER TABLE patients/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS profile_photo_path TEXT/);
  assert.doesNotMatch(migration, /DROP TABLE|DELETE FROM patients|TRUNCATE/i);
});

test('inventory image migration preserves products and adds only the private object path', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/026_inventory_product_images.sql', import.meta.url),
    'utf8',
  );

  assert.match(migration, /ALTER TABLE inventory_products/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS image_path TEXT/);
  assert.doesNotMatch(migration, /DROP TABLE|DELETE FROM inventory_products|TRUNCATE/i);
});

test('inventory product profile migration is additive and public visibility is opt-in', () => {
  const profile = fs.readFileSync(
    new URL('../migrations/027_inventory_product_profiles.sql', import.meta.url),
    'utf8',
  );
  for (const column of [
    'brand_name',
    'sku',
    'barcode',
    'short_description',
    'detailed_description',
    'dosage_form',
    'pack_size',
    'withdrawal_other',
    'contraindications',
    'adverse_effects',
    'public_display_name',
  ]) assert.match(profile, new RegExp(`ADD COLUMN IF NOT EXISTS ${column} TEXT`));
  assert.match(profile, /available_to_public BOOLEAN NOT NULL DEFAULT false/);
  assert.match(profile, /ON inventory_products \(clinic_id, available_to_public\)/);
  assert.doesNotMatch(profile, /DROP TABLE|TRUNCATE|DELETE FROM inventory_products/i);
});

test('inventory subcategory migration is additive, nullable, and clinic scoped', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/028_inventory_product_subcategories.sql', import.meta.url),
    'utf8',
  );
  assert.match(migration, /ADD COLUMN IF NOT EXISTS subcategory_key TEXT/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS subcategory TEXT/);
  assert.match(
    migration,
    /inventory_products_subcategory_search_index[\s\S]*ON inventory_products \(clinic_id, subcategory_key\)/,
  );
  assert.match(migration, /WHERE deleted_at IS NULL AND is_archived = false/);
  assert.doesNotMatch(migration, /DROP TABLE|TRUNCATE|DELETE FROM inventory_products/i);

  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /subcategoryId: z\.string\(\)\.trim\(\)/);
  assert.match(routes, /subcategoryName: z\.string\(\)\.trim\(\)/);
  assert.match(routes, /i\.subcategory ILIKE \$3/);
  assert.match(routes, /category_key, subcategory, subcategory_key/);
});

test('Add Stock is permission guarded, additive, tenant scoped, and ledger backed', () => {
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /inventoryProductId\/add-stock/);
  assert.match(routes, /requirePermission\(permissions\.inventoryAdjust\)/);
  assert.match(routes, /const after = before \+ input\.quantityToAdd/);
  assert.match(routes, /WHERE clinic_id=\$1 AND inventory_product_id=\$2/);
  assert.match(routes, /INSERT INTO stock_movements/);
  assert.match(routes, /'inventory\.stock_added'/);
});

test('farm billing and product unit migration is additive, tenant scoped, and race safe', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/024_farm_billing_product_units.sql', import.meta.url),
    'utf8',
  );
  for (const table of [
    'inventory_product_units',
    'farms',
    'farm_units',
    'farm_treatment_records',
    'inventory_reorder_requests',
  ]) {
    assert.match(migration, new RegExp(`CREATE TABLE IF NOT EXISTS ${table}`));
  }
  assert.match(migration, /inventory_product_units_one_base/);
  assert.match(migration, /WHERE is_base_unit/);
  assert.match(migration, /conversion_to_base INTEGER NOT NULL CHECK \(conversion_to_base > 0\)/);
  assert.match(migration, /CHECK \(NOT is_base_unit OR conversion_to_base = 1\)/);
  assert.match(migration, /invoice_line_items_treatment_unique/);
  assert.match(migration, /WHERE source_treatment_record_id IS NOT NULL/);
  assert.match(migration, /inventory_deducted_at TIMESTAMPTZ/);
  assert.match(migration, /display_unit_snapshot TEXT/);
  assert.match(migration, /unit_cost_snapshot NUMERIC/);
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /clinic_id::text = current_setting\('avera\.clinic_id'/);
  assert.doesNotMatch(migration, /DROP TABLE|TRUNCATE|DELETE FROM inventory_products/i);
});

test('product unit and reorder payloads enforce canonical inventory rules', () => {
  const base = {
    unitLabel: 'Vial',
    isBaseUnit: true,
    conversionToBase: 1,
    sellingPrice: 3200,
  };
  assert.equal(replaceProductUnitsSchema.safeParse({ units: [base] }).success, true);
  assert.equal(replaceProductUnitsSchema.safeParse({ units: [
    base,
    { unitLabel: 'Box', isBaseUnit: false, conversionToBase: 10, sellingPrice: 30000 },
  ] }).success, true);
  assert.equal(replaceProductUnitsSchema.safeParse({ units: [
    base,
    { ...base, unitLabel: 'Bottle' },
  ] }).success, false);
  assert.equal(replaceProductUnitsSchema.safeParse({ units: [
    base,
    { unitLabel: ' vial ', isBaseUnit: false, conversionToBase: 10, sellingPrice: 30000 },
  ] }).success, false);
  assert.equal(replaceProductUnitsSchema.safeParse({ units: [
    { ...base, conversionToBase: 2 },
  ] }).success, false);
  assert.equal(createReorderRequestSchema.safeParse({ requestedQuantity: 5 }).success, true);
  assert.equal(createReorderRequestSchema.safeParse({ requestedQuantity: 0 }).success, false);
});

test('farm invoice and package stock routes lock, scope, snapshot, and reject expiry', () => {
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /async function prepareProductLines/);
  assert.match(routes, /COALESCE\(u\.conversion_to_base, 1\)/);
  assert.match(routes, /COALESCE\(u\.selling_price, p\.selling_price\)/);
  assert.match(routes, /requested\.productUnitId != null && !row\.product_unit_id/);
  assert.match(routes, /FOR UPDATE/);
  assert.match(routes, /inventory_product_expired/);
  assert.match(routes, /Number\(row\.quantity\) < Number\(row\.base_quantity\)/);
  assert.match(routes, /SELECT inventory_deducted_at FROM invoices[\s\S]*FOR UPDATE/);
  assert.match(routes, /inventory_deducted_at\) return/);
  assert.match(routes, /source_treatment_record_id/);
  assert.match(routes, /display_unit_snapshot/);
  assert.match(routes, /conversion_to_base_snapshot/);
  assert.match(routes, /unit_cost_snapshot/);
  assert.match(routes, /request\.auth\.clinicId/);
  assert.match(routes, /duplicate_invoice_source/);
  assert.match(routes, /farm_unit_mismatch/);
  assert.match(routes, /input\.contextType === 'farm_visit'/);
  assert.match(routes, /farm_unit_id = ANY\(\$3::uuid\[\]\)/);
  assert.match(routes, /permissions\.inventoryAdjust/);
  assert.match(routes, /\/api\/v1\/inventory\/products\/:inventoryProductId\/units/);
  assert.match(routes, /\/api\/v1\/inventory\/products\/:inventoryProductId\/reorder-requests/);
  assert.match(routes, /\/api\/v1\/inventory\/products\/:inventoryProductId\/related/);
});

test('revenue summary is tenant scoped and based on settled payment dates', () => {
  const routes = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  const permissionsSource = fs.readFileSync(
    new URL('../src/security/permissions.js', import.meta.url),
    'utf8',
  );
  assert.match(permissionsSource, /billingHistory:\s*'billing\.history'/);
  assert.match(routes, /\/api\/v1\/billing\/revenue-summary/);
  assert.match(routes, /requirePermission\(permissions\.billingHistory\)/);
  assert.match(routes, /p\.clinic_id=\$1/);
  assert.match(routes, /p\.paid_at >= \$2/);
  assert.match(routes, /p\.paid_at < \$3/);
  assert.match(routes, /pbi\.context_type='farm_visit'/);
  assert.match(routes, /li\.unit_cost_snapshot \* li\.quantity/);
  assert.match(routes, /li\.invoice_line_item_id IS NOT NULL/);
});
