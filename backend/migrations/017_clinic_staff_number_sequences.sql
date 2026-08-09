-- Allocate immutable, clinic-scoped staff numbers without trusting clients.

ALTER TABLE staff_profiles
  ADD COLUMN IF NOT EXISTS clinic_id UUID REFERENCES clinics(clinic_id);

UPDATE staff_profiles profile
   SET clinic_id = users.clinic_id
  FROM users
 WHERE users.user_id = profile.user_id
   AND profile.clinic_id IS NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM staff_profiles
     WHERE clinic_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'Cannot enable clinic staff numbering: staff profiles with unresolved clinics exist.';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM staff_profiles
     WHERE staff_number IS NOT NULL
       AND btrim(staff_number) <> ''
     GROUP BY clinic_id, staff_number
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Cannot enable clinic staff numbering: duplicate clinic staff numbers require review.';
  END IF;
END $$;

ALTER TABLE staff_profiles
  ALTER COLUMN clinic_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS staff_profiles_clinic_staff_number_unique
  ON staff_profiles (clinic_id, staff_number)
  WHERE staff_number IS NOT NULL AND btrim(staff_number) <> '';

CREATE INDEX IF NOT EXISTS staff_profiles_clinic_idx
  ON staff_profiles (clinic_id);

CREATE TABLE IF NOT EXISTS clinic_staff_number_sequences (
  clinic_id UUID PRIMARY KEY REFERENCES clinics(clinic_id) ON DELETE CASCADE,
  current_value BIGINT NOT NULL DEFAULT 0 CHECK (current_value >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO clinic_staff_number_sequences (clinic_id, current_value)
SELECT clinic_id,
       coalesce(max(CASE
         WHEN staff_number ~ '^[0-9]+$' THEN staff_number::BIGINT
       END), 0)
  FROM staff_profiles
 GROUP BY clinic_id
ON CONFLICT (clinic_id) DO UPDATE
  SET current_value = greatest(
        clinic_staff_number_sequences.current_value,
        EXCLUDED.current_value
      ),
      updated_at = now();

ALTER TABLE clinic_staff_number_sequences ENABLE ROW LEVEL SECURITY;

CREATE POLICY clinic_staff_number_sequences_tenant_policy
  ON clinic_staff_number_sequences
  USING (
    current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true)
  );
