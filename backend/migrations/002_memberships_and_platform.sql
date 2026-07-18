CREATE TYPE membership_status AS ENUM ('Invited', 'Active', 'Suspended', 'Deactivated');
CREATE TYPE token_purpose AS ENUM ('ClinicAdministratorActivation', 'StaffInvitation', 'PasswordReset', 'EmailVerification');

CREATE TABLE clinic_memberships (
  membership_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id) ON DELETE CASCADE,
  role_id UUID REFERENCES roles(role_id),
  membership_status membership_status NOT NULL DEFAULT 'Invited',
  branch_access JSONB NOT NULL DEFAULT '[]'::jsonb,
  invited_at TIMESTAMPTZ,
  activated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  revision BIGINT NOT NULL DEFAULT 1,
  deleted_at TIMESTAMPTZ,
  UNIQUE (user_id, clinic_id)
);

CREATE TABLE activation_tokens (
  token_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  clinic_id UUID REFERENCES clinics(clinic_id) ON DELETE CASCADE,
  purpose token_purpose NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  requested_from_ip INET,
  requested_from_device TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE clinic_applications (
  application_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID REFERENCES clinics(clinic_id),
  applicant_user_id UUID REFERENCES users(user_id),
  status TEXT NOT NULL DEFAULT 'Pending',
  selected_plan TEXT NOT NULL,
  payment_status TEXT NOT NULL DEFAULT 'Pending',
  payment_reference TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE platform_settings (
  setting_key TEXT PRIMARY KEY,
  setting_value JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES users(user_id)
);

CREATE TABLE plans (
  plan_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_key TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  feature_limits JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE clinic_settings (
  clinic_id UUID PRIMARY KEY REFERENCES clinics(clinic_id) ON DELETE CASCADE,
  settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  revision BIGINT NOT NULL DEFAULT 1
);

CREATE TABLE clinic_branding (
  clinic_id UUID PRIMARY KEY REFERENCES clinics(clinic_id) ON DELETE CASCADE,
  logo_path TEXT,
  primary_color TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID
);

CREATE TABLE staff_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
  professional_title TEXT,
  veterinary_license_number TEXT,
  staff_number TEXT,
  profile_photo_path TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO clinic_memberships (user_id, clinic_id, role_id, membership_status, activated_at, created_at, updated_at)
SELECT user_id, clinic_id, role_id,
  CASE WHEN status = 'Active' THEN 'Active'::membership_status
       WHEN status = 'Suspended' THEN 'Suspended'::membership_status
       WHEN status = 'Deactivated' THEN 'Deactivated'::membership_status
       ELSE 'Invited'::membership_status END,
  CASE WHEN status = 'Active' THEN now() ELSE NULL END, now(), now()
FROM users
WHERE clinic_id IS NOT NULL
ON CONFLICT (user_id, clinic_id) DO NOTHING;

CREATE INDEX clinic_memberships_clinic_status_idx ON clinic_memberships(clinic_id, membership_status);
CREATE INDEX clinic_memberships_user_status_idx ON clinic_memberships(user_id, membership_status);
CREATE INDEX activation_tokens_user_purpose_idx ON activation_tokens(user_id, purpose, expires_at DESC);
CREATE INDEX clinic_applications_status_submitted_idx ON clinic_applications(status, submitted_at DESC);

ALTER TABLE clinic_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinic_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinic_branding ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinic_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY clinic_memberships_tenant_policy ON clinic_memberships USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
CREATE POLICY clinic_settings_tenant_policy ON clinic_settings USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
CREATE POLICY clinic_branding_tenant_policy ON clinic_branding USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
CREATE POLICY clinic_applications_platform_policy ON clinic_applications USING (
  current_setting('avera.is_platform_owner', true) = 'true'
);
