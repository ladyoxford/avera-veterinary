CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TYPE account_type AS ENUM ('PlatformOwner', 'PlatformAdministrator', 'ClinicAdministrator', 'ClinicStaff');
CREATE TYPE account_status AS ENUM ('Invited', 'Active', 'Suspended', 'Locked', 'Deactivated');
CREATE TYPE override_effect AS ENUM ('grant', 'restrict');

CREATE TABLE clinics (
  clinic_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'Pending',
  subscription_plan TEXT NOT NULL DEFAULT 'Starter',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  revision BIGINT NOT NULL DEFAULT 1,
  deleted_at TIMESTAMPTZ
);

CREATE TABLE branches (
  branch_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID, updated_by UUID, revision BIGINT NOT NULL DEFAULT 1, deleted_at TIMESTAMPTZ
);

CREATE TABLE roles (
  role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID REFERENCES clinics(clinic_id),
  name TEXT NOT NULL,
  description TEXT,
  is_system_role BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID, updated_by UUID, revision BIGINT NOT NULL DEFAULT 1, deleted_at TIMESTAMPTZ,
  UNIQUE (clinic_id, name)
);

CREATE TABLE permissions (
  permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  permission_key TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL
);

CREATE TABLE role_permissions (
  role_id UUID NOT NULL REFERENCES roles(role_id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES permissions(permission_id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE users (
  user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID REFERENCES clinics(clinic_id),
  full_name TEXT NOT NULL,
  email CITEXT NOT NULL UNIQUE,
  phone TEXT,
  password_hash TEXT NOT NULL,
  account_type account_type NOT NULL,
  status account_status NOT NULL DEFAULT 'Invited',
  role_id UUID REFERENCES roles(role_id),
  requires_password_change BOOLEAN NOT NULL DEFAULT false,
  email_verified_at TIMESTAMPTZ,
  last_login_at TIMESTAMPTZ,
  failed_login_count INTEGER NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID, updated_by UUID, revision BIGINT NOT NULL DEFAULT 1, deleted_at TIMESTAMPTZ,
  CHECK ((account_type IN ('PlatformOwner', 'PlatformAdministrator')) OR clinic_id IS NOT NULL)
);

CREATE TABLE user_permission_overrides (
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES permissions(permission_id) ON DELETE CASCADE,
  effect override_effect NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  PRIMARY KEY (user_id, permission_id)
);

CREATE TABLE devices (
  device_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  device_name TEXT, platform TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sessions (
  session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  device_id UUID REFERENCES devices(device_id),
  refresh_token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ,
  ip_address INET, user_agent TEXT
);

CREATE TABLE subscriptions (
  subscription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  plan TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'Pending', trial_ends_at TIMESTAMPTZ,
  current_period_ends_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sync_metadata (
  sync_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  entity_type TEXT NOT NULL, entity_id UUID NOT NULL, revision BIGINT NOT NULL DEFAULT 1,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(), deleted_at TIMESTAMPTZ
);

CREATE TABLE audit_logs (
  audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), clinic_id UUID REFERENCES clinics(clinic_id),
  acting_user_id UUID REFERENCES users(user_id), target_type TEXT NOT NULL, target_id UUID,
  action TEXT NOT NULL, previous_summary JSONB, new_summary JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), session_id UUID REFERENCES sessions(session_id), device_id UUID REFERENCES devices(device_id),
  ip_address INET, success BOOLEAN NOT NULL DEFAULT true, reason TEXT
);

CREATE INDEX users_clinic_id_idx ON users(clinic_id);
CREATE INDEX sessions_user_id_idx ON sessions(user_id);
CREATE INDEX audit_logs_clinic_created_idx ON audit_logs(clinic_id, created_at DESC);
CREATE INDEX sync_metadata_clinic_changed_idx ON sync_metadata(clinic_id, changed_at DESC);

ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_metadata ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY clinic_tenant_policy ON users USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
CREATE POLICY branch_tenant_policy ON branches USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
CREATE POLICY role_tenant_policy ON roles USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
CREATE POLICY subscription_tenant_policy ON subscriptions USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
CREATE POLICY sync_tenant_policy ON sync_metadata USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
CREATE POLICY audit_tenant_policy ON audit_logs USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
