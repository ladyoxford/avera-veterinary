CREATE TABLE clinic_deletion_requests (
  request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  requested_by UUID NOT NULL REFERENCES users(user_id),
  recipient_email CITEXT NOT NULL,
  code_hash TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'Pending'
    CHECK (status IN (
      'Pending', 'Confirmed', 'Expired', 'Cancelled', 'DeliveryFailed'
    )),
  attempts_remaining INTEGER NOT NULL DEFAULT 5
    CHECK (attempts_remaining >= 0),
  reason TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  delivered_at TIMESTAMPTZ,
  delivery_reference TEXT,
  confirmed_at TIMESTAMPTZ,
  confirmed_by UUID REFERENCES users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX clinic_deletion_one_pending_per_clinic_idx
  ON clinic_deletion_requests (clinic_id)
  WHERE status = 'Pending';

CREATE INDEX clinic_deletion_requests_expiry_idx
  ON clinic_deletion_requests (status, expires_at);

ALTER TABLE clinic_deletion_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY clinic_deletion_requests_platform_policy
  ON clinic_deletion_requests
  USING (current_setting('avera.is_platform_owner', true) = 'true')
  WITH CHECK (current_setting('avera.is_platform_owner', true) = 'true');
