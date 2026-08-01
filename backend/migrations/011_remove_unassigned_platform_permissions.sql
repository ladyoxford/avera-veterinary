-- Platform permissions are provisioned with platform roles, not as part of the
-- clinic catalogue. Remove only unassigned rows created before that split.
DELETE FROM permissions p
WHERE p.permission_key = ANY(ARRAY[
  'clinics.approve',
  'clinics.suspend',
  'platform_users.manage',
  'platform_audit.view',
  'platform_plans.manage',
  'platform_support.access',
  'platform_announcements.manage',
  'platform_vera.manage'
]::text[])
AND NOT EXISTS (
  SELECT 1
  FROM role_permissions rp
  WHERE rp.permission_id = p.permission_id
);
