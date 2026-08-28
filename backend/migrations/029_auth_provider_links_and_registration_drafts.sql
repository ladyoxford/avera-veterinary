CREATE TABLE IF NOT EXISTS user_auth_providers (
  provider_link_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  provider_type TEXT NOT NULL CHECK (provider_type IN ('google', 'apple')),
  provider_subject TEXT NOT NULL,
  provider_email CITEXT,
  verified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  linked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider_type, provider_subject),
  UNIQUE (user_id, provider_type)
);

CREATE TABLE IF NOT EXISTS auth_provider_link_challenges (
  challenge_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_type TEXT NOT NULL CHECK (provider_type IN ('google', 'apple')),
  provider_subject TEXT NOT NULL,
  provider_email CITEXT,
  target_email CITEXT NOT NULL,
  target_user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
  target_application_id UUID REFERENCES clinic_applications(application_id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  attempts_remaining INTEGER NOT NULL DEFAULT 5 CHECK (attempts_remaining >= 0),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  requested_from_ip INET,
  CHECK (
    (target_user_id IS NOT NULL AND target_application_id IS NULL)
    OR (target_user_id IS NULL AND target_application_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS user_auth_providers_user_idx
  ON user_auth_providers (user_id, provider_type);

CREATE INDEX IF NOT EXISTS auth_provider_link_challenges_active_idx
  ON auth_provider_link_challenges (challenge_id, expires_at)
  WHERE used_at IS NULL AND revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS auth_provider_link_challenges_target_email_idx
  ON auth_provider_link_challenges (target_email, created_at DESC);

ALTER TABLE user_auth_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_provider_link_challenges ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_auth_providers_platform_policy
  ON user_auth_providers
  USING (current_setting('avera.is_platform_owner', true) = 'true');

CREATE POLICY auth_provider_link_challenges_platform_policy
  ON auth_provider_link_challenges
  USING (current_setting('avera.is_platform_owner', true) = 'true');

COMMENT ON TABLE user_auth_providers IS
  'Verified Google and Apple identities linked to one canonical AVERA user.';

COMMENT ON TABLE auth_provider_link_challenges IS
  'Short-lived, single-use email verification challenges for provider linking.';
