-- Tenant-scoped, idempotent storage for the shared Clinical Operations UI.
-- This complements the older specialist tables without rewriting existing rows.

CREATE TABLE IF NOT EXISTS clinical_operation_records (
  operation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  operation_type TEXT NOT NULL CHECK (operation_type IN (
    'Surgery', 'Prescription', 'Imaging', 'Document', 'Treatment'
  )),
  title TEXT NOT NULL,
  description TEXT,
  assigned_to TEXT,
  scheduled_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'Routine',
  estimated_amount NUMERIC(12,2),
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_by UUID REFERENCES users(user_id),
  submission_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (clinic_id, submission_id)
);

CREATE INDEX IF NOT EXISTS clinical_operations_clinic_type_date_idx
  ON clinical_operation_records (clinic_id, operation_type, scheduled_at DESC);

CREATE INDEX IF NOT EXISTS clinical_operations_patient_type_date_idx
  ON clinical_operation_records (clinic_id, patient_id, operation_type, scheduled_at DESC);

ALTER TABLE clinical_operation_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS clinical_operations_tenant_policy ON clinical_operation_records;
CREATE POLICY clinical_operations_tenant_policy ON clinical_operation_records
  USING (
    current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true)
  );

-- Standalone prescriptions created from Clinical Operations are valid without
-- first creating a consultation. Historical references remain unchanged.
ALTER TABLE prescriptions ALTER COLUMN consultation_id DROP NOT NULL;
