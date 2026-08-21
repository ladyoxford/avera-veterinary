ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS reference TEXT,
  ADD COLUMN IF NOT EXISTS recorded_by UUID REFERENCES users(user_id),
  ADD COLUMN IF NOT EXISTS submission_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS payments_clinic_submission_unique
  ON payments (clinic_id, submission_id)
  WHERE submission_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS payments_clinic_paid_at_index
  ON payments (clinic_id, paid_at DESC);
