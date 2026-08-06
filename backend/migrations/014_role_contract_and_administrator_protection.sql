-- Separate stable role identifiers from human-readable role names and grant
-- role-management authority only to clinic administrators.
ALTER TABLE roles ADD COLUMN IF NOT EXISTS code TEXT;

UPDATE roles
SET code = COALESCE(
  NULLIF(lower(trim(both '_' FROM regexp_replace(name, '[^a-zA-Z0-9]+', '_', 'g'))), ''),
  'role_' || substr(replace(role_id::text, '-', ''), 1, 8)
)
WHERE code IS NULL OR btrim(code) = '';

UPDATE roles
SET code = 'clinic_administrator'
WHERE lower(name) = 'clinic administrator'
  AND code <> 'clinic_administrator';

WITH duplicate_codes AS (
  SELECT role_id,
         row_number() OVER (
           PARTITION BY clinic_id, code
           ORDER BY created_at, role_id
         ) AS duplicate_number
  FROM roles
  WHERE deleted_at IS NULL
)
UPDATE roles r
SET code = r.code || '_' || substr(replace(r.role_id::text, '-', ''), 1, 8)
FROM duplicate_codes d
WHERE d.role_id = r.role_id
  AND d.duplicate_number > 1;

ALTER TABLE roles ALTER COLUMN code SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS roles_clinic_code_unique
ON roles (clinic_id, code)
WHERE deleted_at IS NULL;

INSERT INTO permissions (permission_key, description)
VALUES ('staff.roles.manage', 'Manage clinic staff roles')
ON CONFLICT (permission_key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r
CROSS JOIN permissions p
WHERE r.code = 'clinic_administrator'
  AND r.clinic_id IS NOT NULL
  AND r.deleted_at IS NULL
  AND p.permission_key = 'staff.roles.manage'
ON CONFLICT DO NOTHING;
