CREATE TABLE demo_datasets (
  dataset_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  generator_version TEXT NOT NULL,
  random_seed BIGINT NOT NULL,
  size_name TEXT NOT NULL,
  settings JSONB NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'Generating',
  record_counts JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES users(user_id)
);

ALTER TABLE clinics ADD COLUMN is_demo BOOLEAN NOT NULL DEFAULT false, ADD COLUMN demo_dataset_id UUID REFERENCES demo_datasets(dataset_id);
ALTER TABLE users ADD COLUMN is_demo BOOLEAN NOT NULL DEFAULT false, ADD COLUMN demo_dataset_id UUID REFERENCES demo_datasets(dataset_id);

CREATE TABLE owners (
  owner_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  full_name TEXT NOT NULL, phone TEXT NOT NULL, email CITEXT, address TEXT, city TEXT, state TEXT,
  preferred_contact_method TEXT NOT NULL DEFAULT 'Phone', emergency_contact TEXT, communication_consent BOOLEAN NOT NULL DEFAULT true,
  registered_at TIMESTAMPTZ NOT NULL, is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), revision BIGINT NOT NULL DEFAULT 1, deleted_at TIMESTAMPTZ
);

CREATE TABLE patients (
  patient_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), owner_id UUID NOT NULL REFERENCES owners(owner_id),
  hospital_number TEXT NOT NULL, name TEXT NOT NULL, species TEXT NOT NULL, breed TEXT, sex TEXT, reproductive_status TEXT,
  date_of_birth DATE NOT NULL, colour TEXT, current_weight_kg NUMERIC(8,2), microchip_number TEXT, status TEXT NOT NULL DEFAULT 'Active',
  allergies TEXT, alerts TEXT, insurance_status TEXT, primary_veterinarian_id UUID REFERENCES users(user_id), registered_at TIMESTAMPTZ NOT NULL,
  deceased_at TIMESTAMPTZ, image_placeholder TEXT, is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), revision BIGINT NOT NULL DEFAULT 1, deleted_at TIMESTAMPTZ,
  UNIQUE (clinic_id, hospital_number)
);

CREATE TABLE patient_weights (
  weight_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID NOT NULL REFERENCES patients(patient_id),
  measured_at TIMESTAMPTZ NOT NULL, weight_kg NUMERIC(8,2) NOT NULL, source TEXT NOT NULL DEFAULT 'Consultation', is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE consultations (
  consultation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID NOT NULL REFERENCES patients(patient_id), clinician_id UUID REFERENCES users(user_id),
  occurred_at TIMESTAMPTZ NOT NULL, chief_complaint TEXT NOT NULL, history TEXT, examination TEXT, weight_kg NUMERIC(8,2), temperature_c NUMERIC(4,1), pulse INTEGER, respiration INTEGER,
  assessment TEXT, differential_diagnoses TEXT, final_diagnosis TEXT, treatment TEXT, follow_up_at TIMESTAMPTZ, status TEXT NOT NULL, charge NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), revision BIGINT NOT NULL DEFAULT 1
);

CREATE TABLE vaccinations (
  vaccination_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID NOT NULL REFERENCES patients(patient_id), consultation_id UUID REFERENCES consultations(consultation_id),
  vaccine_name TEXT NOT NULL, manufacturer TEXT, batch_number TEXT, expiry_date DATE, route TEXT, dose TEXT, injection_site TEXT, administered_at TIMESTAMPTZ NOT NULL,
  next_due_at TIMESTAMPTZ, administered_by UUID REFERENCES users(user_id), certificate_number TEXT, notes TEXT, reminder_status TEXT, status TEXT NOT NULL,
  is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE laboratory_reports (
  laboratory_report_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID NOT NULL REFERENCES patients(patient_id), consultation_id UUID REFERENCES consultations(consultation_id),
  requested_at TIMESTAMPTZ NOT NULL, reported_at TIMESTAMPTZ, test_type TEXT NOT NULL, status TEXT NOT NULL, result_summary TEXT, result_values JSONB NOT NULL DEFAULT '{}'::jsonb,
  requested_by UUID REFERENCES users(user_id), reviewed_by UUID REFERENCES users(user_id), cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE hospitalizations (
  hospitalization_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID NOT NULL REFERENCES patients(patient_id), consultation_id UUID REFERENCES consultations(consultation_id),
  admitted_at TIMESTAMPTZ NOT NULL, discharged_at TIMESTAMPTZ, ward TEXT, cage_or_pen TEXT, attending_veterinarian_id UUID REFERENCES users(user_id), reason TEXT NOT NULL, diagnosis TEXT,
  treatment_plan JSONB NOT NULL DEFAULT '{}'::jsonb, outcome TEXT NOT NULL, cost NUMERIC(12,2) NOT NULL DEFAULT 0, is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE surgeries (
  surgery_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID NOT NULL REFERENCES patients(patient_id), consultation_id UUID REFERENCES consultations(consultation_id),
  performed_at TIMESTAMPTZ NOT NULL, procedure_name TEXT NOT NULL, surgeon_id UUID REFERENCES users(user_id), anaesthesia_protocol TEXT, complication_notes TEXT, recovery_notes TEXT,
  follow_up_at TIMESTAMPTZ, cost NUMERIC(12,2) NOT NULL DEFAULT 0, is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE inventory_products (
  inventory_product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), name TEXT NOT NULL, generic_name TEXT, category TEXT NOT NULL, manufacturer TEXT,
  supplier TEXT, batch_number TEXT, expiry_date DATE, purchase_price NUMERIC(12,2) NOT NULL, selling_price NUMERIC(12,2) NOT NULL, quantity INTEGER NOT NULL, reorder_level INTEGER NOT NULL,
  storage_conditions TEXT, controlled BOOLEAN NOT NULL DEFAULT false, status TEXT NOT NULL DEFAULT 'Active', is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE stock_movements (
  stock_movement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), inventory_product_id UUID NOT NULL REFERENCES inventory_products(inventory_product_id),
  consultation_id UUID REFERENCES consultations(consultation_id), occurred_at TIMESTAMPTZ NOT NULL, movement_type TEXT NOT NULL, quantity_delta INTEGER NOT NULL, reference TEXT,
  is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE prescriptions (
  prescription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID NOT NULL REFERENCES patients(patient_id), consultation_id UUID NOT NULL REFERENCES consultations(consultation_id), inventory_product_id UUID REFERENCES inventory_products(inventory_product_id),
  prescribed_at TIMESTAMPTZ NOT NULL, drug_name TEXT NOT NULL, concentration TEXT, dose TEXT, route TEXT, frequency TEXT, duration_days INTEGER, quantity INTEGER, instructions TEXT,
  prescriber_id UUID REFERENCES users(user_id), refill_status TEXT NOT NULL, is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE schedule_entries (
  schedule_entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID NOT NULL REFERENCES patients(patient_id), owner_id UUID NOT NULL REFERENCES owners(owner_id), assigned_staff_id UUID REFERENCES users(user_id),
  scheduled_at TIMESTAMPTZ NOT NULL, visit_type TEXT NOT NULL, status TEXT NOT NULL, notes TEXT, is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE invoices (
  invoice_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), owner_id UUID NOT NULL REFERENCES owners(owner_id), patient_id UUID REFERENCES patients(patient_id), consultation_id UUID REFERENCES consultations(consultation_id),
  invoice_number TEXT NOT NULL, status TEXT NOT NULL, subtotal NUMERIC(12,2) NOT NULL, tax NUMERIC(12,2) NOT NULL DEFAULT 0, discount NUMERIC(12,2) NOT NULL DEFAULT 0, total NUMERIC(12,2) NOT NULL, amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0, balance NUMERIC(12,2) NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL, due_at TIMESTAMPTZ, is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id), UNIQUE (clinic_id, invoice_number)
);

CREATE TABLE payments (
  payment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), invoice_id UUID NOT NULL REFERENCES invoices(invoice_id), paid_at TIMESTAMPTZ NOT NULL, amount NUMERIC(12,2) NOT NULL, method TEXT NOT NULL,
  is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE TABLE media_assets (
  media_asset_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id), patient_id UUID REFERENCES patients(patient_id), category TEXT NOT NULL, file_type TEXT NOT NULL, file_size_bytes INTEGER NOT NULL, placeholder_key TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL,
  is_demo BOOLEAN NOT NULL DEFAULT false, demo_dataset_id UUID REFERENCES demo_datasets(dataset_id)
);

CREATE INDEX owners_clinic_name_idx ON owners(clinic_id, full_name); CREATE INDEX owners_clinic_phone_idx ON owners(clinic_id, phone); CREATE INDEX owners_clinic_email_idx ON owners(clinic_id, email);
CREATE INDEX patients_clinic_name_idx ON patients(clinic_id, name); CREATE INDEX patients_clinic_hospital_idx ON patients(clinic_id, hospital_number); CREATE INDEX patients_clinic_species_idx ON patients(clinic_id, species); CREATE INDEX patients_clinic_microchip_idx ON patients(clinic_id, microchip_number);
CREATE INDEX consultations_clinic_occurred_idx ON consultations(clinic_id, occurred_at DESC); CREATE INDEX consultations_patient_occurred_idx ON consultations(patient_id, occurred_at DESC);
CREATE INDEX laboratory_clinic_reported_idx ON laboratory_reports(clinic_id, reported_at DESC); CREATE INDEX vaccinations_clinic_due_idx ON vaccinations(clinic_id, next_due_at); CREATE INDEX hospitalizations_clinic_admitted_idx ON hospitalizations(clinic_id, admitted_at DESC);
CREATE INDEX inventory_clinic_name_idx ON inventory_products(clinic_id, name); CREATE INDEX inventory_clinic_batch_idx ON inventory_products(clinic_id, batch_number); CREATE INDEX schedule_clinic_date_idx ON schedule_entries(clinic_id, scheduled_at); CREATE INDEX invoices_clinic_issued_idx ON invoices(clinic_id, issued_at DESC); CREATE INDEX payments_invoice_idx ON payments(invoice_id);

ALTER TABLE owners ENABLE ROW LEVEL SECURITY; ALTER TABLE patients ENABLE ROW LEVEL SECURITY; ALTER TABLE patient_weights ENABLE ROW LEVEL SECURITY; ALTER TABLE consultations ENABLE ROW LEVEL SECURITY; ALTER TABLE vaccinations ENABLE ROW LEVEL SECURITY; ALTER TABLE laboratory_reports ENABLE ROW LEVEL SECURITY; ALTER TABLE hospitalizations ENABLE ROW LEVEL SECURITY; ALTER TABLE surgeries ENABLE ROW LEVEL SECURITY; ALTER TABLE inventory_products ENABLE ROW LEVEL SECURITY; ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY; ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY; ALTER TABLE schedule_entries ENABLE ROW LEVEL SECURITY; ALTER TABLE invoices ENABLE ROW LEVEL SECURITY; ALTER TABLE payments ENABLE ROW LEVEL SECURITY; ALTER TABLE media_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY owners_tenant_policy ON owners USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY patients_tenant_policy ON patients USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY patient_weights_tenant_policy ON patient_weights USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY consultations_tenant_policy ON consultations USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY vaccinations_tenant_policy ON vaccinations USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY laboratory_reports_tenant_policy ON laboratory_reports USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY hospitalizations_tenant_policy ON hospitalizations USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY surgeries_tenant_policy ON surgeries USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY inventory_tenant_policy ON inventory_products USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY stock_movements_tenant_policy ON stock_movements USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY prescriptions_tenant_policy ON prescriptions USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY schedule_tenant_policy ON schedule_entries USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY invoices_tenant_policy ON invoices USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY payments_tenant_policy ON payments USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
CREATE POLICY media_tenant_policy ON media_assets USING (current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true));
