ALTER TABLE users
  ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suspended_by_user_id UUID REFERENCES users(user_id),
  ADD COLUMN IF NOT EXISTS suspension_reason TEXT,
  ADD COLUMN IF NOT EXISTS reactivated_at TIMESTAMPTZ;

ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS biometric_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS user_mfa_settings (
  user_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
  method TEXT NOT NULL DEFAULT 'totp',
  enabled BOOLEAN NOT NULL DEFAULT false,
  encrypted_totp_secret TEXT,
  pending_setup_id UUID,
  pending_secret_expires_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  recovery_codes_generated_at TIMESTAMPTZ,
  last_accepted_step BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_recovery_codes (
  recovery_code_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mfa_challenges (
  challenge_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  clinic_id UUID REFERENCES clinics(clinic_id) ON DELETE CASCADE,
  challenge_token_hash TEXT NOT NULL UNIQUE,
  device_name TEXT,
  platform TEXT,
  ip_address INET,
  user_agent TEXT,
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS mfa_challenges_user_active_idx
  ON mfa_challenges(user_id, expires_at DESC)
  WHERE consumed_at IS NULL AND revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS user_recovery_codes_user_active_idx
  ON user_recovery_codes(user_id)
  WHERE consumed_at IS NULL;

INSERT INTO permissions (permission_key, description)
VALUES ('security.twoFactor.manageSelf', 'Manage two-factor authentication for the signed-in Clinic Administrator')
ON CONFLICT (permission_key) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r
JOIN permissions p ON p.permission_key = 'security.twoFactor.manageSelf'
WHERE r.name = 'Clinic Administrator'
ON CONFLICT DO NOTHING;
