ALTER TYPE account_status ADD VALUE IF NOT EXISTS 'PendingActivation';

ALTER TABLE users
  ALTER COLUMN password_hash DROP NOT NULL;

ALTER TABLE users
  ADD CONSTRAINT users_active_password_required
  CHECK (
    status NOT IN ('Active', 'Locked')
    OR password_hash IS NOT NULL
  ) NOT VALID;

ALTER TABLE users
  VALIDATE CONSTRAINT users_active_password_required;

ALTER TABLE activation_tokens
  ADD COLUMN IF NOT EXISTS delivery_method TEXT,
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_reference TEXT;

WITH duplicate_live_tokens AS (
  SELECT token_id,
         row_number() OVER (
           PARTITION BY user_id, purpose
           ORDER BY created_at DESC, token_id DESC
         ) AS position
    FROM activation_tokens
   WHERE purpose = 'ClinicAdministratorActivation'
     AND used_at IS NULL
     AND revoked_at IS NULL
)
UPDATE activation_tokens token
   SET revoked_at = now()
  FROM duplicate_live_tokens duplicate
 WHERE token.token_id = duplicate.token_id
   AND duplicate.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS activation_tokens_one_live_admin_token_idx
  ON activation_tokens (user_id, purpose)
  WHERE purpose = 'ClinicAdministratorActivation'
    AND used_at IS NULL
    AND revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS activation_tokens_hash_active_idx
  ON activation_tokens (token_hash, expires_at)
  WHERE used_at IS NULL AND revoked_at IS NULL;
