-- Complete retry-safe clinical writes and staff activation without rewriting history.

ALTER TABLE vaccinations
  ADD COLUMN IF NOT EXISTS submission_id UUID,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS revision BIGINT NOT NULL DEFAULT 1;

CREATE UNIQUE INDEX IF NOT EXISTS vaccinations_clinic_submission_idx
  ON vaccinations (clinic_id, submission_id)
  WHERE submission_id IS NOT NULL;

ALTER TABLE schedule_entries
  ADD COLUMN IF NOT EXISTS submission_id UUID,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS revision BIGINT NOT NULL DEFAULT 1;

CREATE UNIQUE INDEX IF NOT EXISTS schedule_entries_clinic_submission_idx
  ON schedule_entries (clinic_id, submission_id)
  WHERE submission_id IS NOT NULL;

WITH duplicate_live_tokens AS (
  SELECT token_id,
         row_number() OVER (
           PARTITION BY user_id, purpose
           ORDER BY created_at DESC, token_id DESC
         ) AS position
    FROM activation_tokens
   WHERE purpose = 'StaffInvitation'
     AND used_at IS NULL
     AND revoked_at IS NULL
)
UPDATE activation_tokens token
   SET revoked_at = now()
  FROM duplicate_live_tokens duplicate
 WHERE token.token_id = duplicate.token_id
   AND duplicate.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS activation_tokens_one_live_staff_token_idx
  ON activation_tokens (user_id, purpose)
  WHERE purpose = 'StaffInvitation'
    AND used_at IS NULL
    AND revoked_at IS NULL;
