-- Durable, user-scoped reminder inbox generated from authoritative clinic data.
CREATE TABLE IF NOT EXISTS clinic_notifications (
  notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  user_id UUID NOT NULL REFERENCES users(user_id),
  dedupe_key TEXT NOT NULL,
  notification_type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'upcoming',
  related_entity_type TEXT NOT NULL,
  related_entity_id UUID NOT NULL,
  patient_id UUID REFERENCES patients(patient_id),
  scheduled_at TIMESTAMPTZ,
  reminder_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ,
  dismissed_at TIMESTAMPTZ,
  UNIQUE (clinic_id, user_id, dedupe_key)
);

CREATE INDEX IF NOT EXISTS clinic_notifications_user_inbox_idx
  ON clinic_notifications (clinic_id, user_id, created_at DESC)
  WHERE dismissed_at IS NULL;

ALTER TABLE clinic_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS clinic_notifications_tenant_policy ON clinic_notifications;
CREATE POLICY clinic_notifications_tenant_policy ON clinic_notifications
  USING (
    current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true)
  );
