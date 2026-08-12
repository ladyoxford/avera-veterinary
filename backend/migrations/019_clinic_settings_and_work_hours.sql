ALTER TABLE clinic_branding
  ADD COLUMN IF NOT EXISTS banner_path TEXT,
  ALTER COLUMN primary_color SET DEFAULT '#087F7B';

UPDATE clinic_branding
SET primary_color = CASE
  WHEN primary_color ~* '^#[0-9A-F]{6}$' THEN upper(primary_color)
  ELSE '#087F7B'
END
WHERE primary_color IS NULL
   OR primary_color !~ '^#[0-9A-F]{6}$';

ALTER TABLE clinic_branding
  ALTER COLUMN primary_color SET NOT NULL;

ALTER TABLE clinic_branding
  DROP CONSTRAINT IF EXISTS clinic_branding_primary_color_format;

ALTER TABLE clinic_branding
  ADD CONSTRAINT clinic_branding_primary_color_format
    CHECK (primary_color ~ '^#[0-9A-F]{6}$');

CREATE TABLE IF NOT EXISTS clinic_work_hours (
  clinic_id UUID PRIMARY KEY REFERENCES clinics(clinic_id),
  time_zone TEXT NOT NULL DEFAULT 'Africa/Lagos',
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  days JSONB NOT NULL DEFAULT '[
    {"weekday":"monday","isOpen":true,"openingTime":"08:00","closingTime":"18:00"},
    {"weekday":"tuesday","isOpen":true,"openingTime":"08:00","closingTime":"18:00"},
    {"weekday":"wednesday","isOpen":true,"openingTime":"08:00","closingTime":"18:00"},
    {"weekday":"thursday","isOpen":true,"openingTime":"08:00","closingTime":"18:00"},
    {"weekday":"friday","isOpen":true,"openingTime":"08:00","closingTime":"18:00"},
    {"weekday":"saturday","isOpen":true,"openingTime":"09:00","closingTime":"14:00"},
    {"weekday":"sunday","isOpen":false}
  ]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES users(user_id),
  CONSTRAINT clinic_work_hours_days_array CHECK (jsonb_typeof(days) = 'array')
);

INSERT INTO clinic_work_hours (clinic_id, time_zone)
SELECT clinic_id, coalesce(time_zone, 'Africa/Lagos')
FROM clinics
WHERE deleted_at IS NULL
ON CONFLICT (clinic_id) DO NOTHING;

ALTER TABLE clinic_work_hours ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS clinic_work_hours_tenant_policy ON clinic_work_hours;
CREATE POLICY clinic_work_hours_tenant_policy ON clinic_work_hours USING (
  current_setting('avera.is_platform_owner', true) = 'true'
  OR clinic_id::text = current_setting('avera.clinic_id', true)
);
