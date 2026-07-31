ALTER TABLE clinics
  ADD COLUMN IF NOT EXISTS email CITEXT,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS city TEXT,
  ADD COLUMN IF NOT EXISTS country TEXT,
  ADD COLUMN IF NOT EXISTS time_zone TEXT NOT NULL DEFAULT 'Africa/Lagos';

ALTER TABLE clinic_applications
  ADD COLUMN IF NOT EXISTS application_reference TEXT,
  ADD COLUMN IF NOT EXISTS clinic_name TEXT,
  ADD COLUMN IF NOT EXISTS clinic_email CITEXT,
  ADD COLUMN IF NOT EXISTS clinic_phone TEXT,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS city TEXT,
  ADD COLUMN IF NOT EXISTS country TEXT,
  ADD COLUMN IF NOT EXISTS time_zone TEXT,
  ADD COLUMN IF NOT EXISTS administrator_name TEXT,
  ADD COLUMN IF NOT EXISTS administrator_email CITEXT,
  ADD COLUMN IF NOT EXISTS administrator_phone TEXT,
  ADD COLUMN IF NOT EXISTS professional_title TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS clinic_applications_reference_uidx
  ON clinic_applications (application_reference)
  WHERE application_reference IS NOT NULL;

CREATE INDEX IF NOT EXISTS clinics_platform_status_created_idx
  ON clinics (status, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS clinic_applications_admin_email_status_idx
  ON clinic_applications (administrator_email, status, submitted_at DESC);
