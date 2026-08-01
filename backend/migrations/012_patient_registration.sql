ALTER TABLE clinics
  ADD COLUMN IF NOT EXISTS patient_number_prefix TEXT,
  ADD COLUMN IF NOT EXISTS patient_number_sequence_length INTEGER NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS patient_number_reset_yearly BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS patient_number_prefix_reviewed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS patient_number_last_changed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS patient_number_last_changed_by UUID REFERENCES users(user_id),
  ADD CONSTRAINT clinics_patient_number_prefix_format
    CHECK (patient_number_prefix IS NULL OR patient_number_prefix ~ '^[A-Z0-9]{2,8}$'),
  ADD CONSTRAINT clinics_patient_number_sequence_length_range
    CHECK (patient_number_sequence_length BETWEEN 4 AND 10);

ALTER TABLE patients
  ADD COLUMN IF NOT EXISTS registration_submission_id UUID,
  ADD COLUMN IF NOT EXISTS species_id TEXT,
  ADD COLUMN IF NOT EXISTS breed_id TEXT,
  ADD COLUMN IF NOT EXISTS is_date_of_birth_estimated BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS original_age_value INTEGER,
  ADD COLUMN IF NOT EXISTS original_age_unit TEXT,
  ADD COLUMN IF NOT EXISTS age_recorded_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS notes TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS patients_clinic_submission_uidx
  ON patients (clinic_id, registration_submission_id)
  WHERE registration_submission_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS clinic_number_sequences (
  sequence_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  sequence_type TEXT NOT NULL,
  sequence_key TEXT NOT NULL,
  current_value BIGINT NOT NULL DEFAULT 0 CHECK (current_value >= 0),
  sequence_length INTEGER NOT NULL DEFAULT 5 CHECK (sequence_length BETWEEN 4 AND 10),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (clinic_id, sequence_type, sequence_key)
);

CREATE INDEX IF NOT EXISTS clinic_number_sequences_clinic_idx
  ON clinic_number_sequences (clinic_id, sequence_type, sequence_key);

ALTER TABLE clinic_number_sequences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS clinic_number_sequences_tenant_policy ON clinic_number_sequences;
CREATE POLICY clinic_number_sequences_tenant_policy ON clinic_number_sequences USING (
  current_setting('avera.is_platform_owner', true) = 'true'
  OR clinic_id::text = current_setting('avera.clinic_id', true)
);
