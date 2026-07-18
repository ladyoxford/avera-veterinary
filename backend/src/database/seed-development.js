import { loadEnvironment } from '../config/env.js';
import { createPool } from './pool.js';
import { hashPassword } from '../security/passwords.js';

const environment = loadEnvironment();
if (environment.NODE_ENV === 'production' || !environment.localDevelopmentAuth) {
  throw new Error('Development seeds are disabled outside explicit local development mode.');
}
if (!process.env.DEVELOPMENT_PLATFORM_OWNER_PASSWORD || !process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD) {
  throw new Error('Set development seed passwords in .env before running the development seed.');
}

const pool = createPool(environment.DATABASE_URL);
const client = await pool.connect();
try {
  await client.query('BEGIN');
  const permissionDefinitions = [
    ['patients.view', 'View patients'], ['patients.create', 'Create patients'], ['patients.edit', 'Edit patients'],
    ['consultations.view', 'View consultations'], ['consultations.create', 'Create consultations'], ['consultations.edit', 'Edit consultations'],
    ['vaccinations.view', 'View vaccinations'], ['vaccinations.add', 'Add vaccinations'],
    ['laboratory.view', 'View laboratory records'], ['laboratory.add', 'Add laboratory results'],
    ['inventory.view', 'View inventory'], ['inventory.edit', 'Edit inventory'],
    ['billing.view', 'View billing'], ['billing.manage', 'Manage billing'],
    ['users.view', 'View clinic users'], ['users.create', 'Create clinic users'], ['users.assign_roles', 'Assign clinic roles'],
    ['clinic_settings.edit', 'Edit clinic settings'], ['audit_logs.view', 'View clinic audit logs'],
    ['clinics.view', 'View clinics'], ['clinics.approve', 'Approve clinics'], ['clinics.suspend', 'Suspend clinics'], ['subscriptions.manage', 'Manage subscriptions'],
  ];
  for (const [key, description] of permissionDefinitions) {
    await client.query('INSERT INTO permissions (permission_key, description) VALUES ($1, $2) ON CONFLICT (permission_key) DO NOTHING', [key, description]);
  }
  const clinic = await client.query(
    `INSERT INTO clinics (name, status, subscription_plan)
     VALUES ('Zevora Veterinary Clinic', 'Active', 'Professional')
     ON CONFLICT DO NOTHING RETURNING clinic_id`,
  );
  const clinicId = clinic.rows[0]?.clinic_id ?? (await client.query("SELECT clinic_id FROM clinics WHERE name = 'Zevora Veterinary Clinic' LIMIT 1")).rows[0].clinic_id;
  const role = await client.query(
    `INSERT INTO roles (clinic_id, name, description, is_system_role)
     VALUES ($1, 'Clinic Administrator', 'Development clinic administrator', true)
     ON CONFLICT (clinic_id, name) DO UPDATE SET description = EXCLUDED.description
     RETURNING role_id`, [clinicId]);
  const adminRoleId = role.rows[0].role_id;
  await client.query(
    `INSERT INTO role_permissions (role_id, permission_id)
       SELECT $1, permission_id FROM permissions
      WHERE permission_key = ANY($2::text[])
      ON CONFLICT DO NOTHING`,
    [adminRoleId, ['patients.view', 'patients.create', 'patients.edit', 'consultations.view', 'consultations.create', 'consultations.edit', 'vaccinations.view', 'vaccinations.add', 'laboratory.view', 'laboratory.add', 'inventory.view', 'inventory.edit', 'billing.view', 'billing.manage', 'users.view', 'users.create', 'users.assign_roles', 'clinic_settings.edit', 'audit_logs.view']],
  );
  const owner = await ensureDevelopmentIdentity(client, {
    email: 'owner@avera.test',
    legacyEmail: 'owner@avera.local',
    accountType: 'PlatformOwner',
  });
  const ownerPasswordHash = await hashPassword(process.env.DEVELOPMENT_PLATFORM_OWNER_PASSWORD);
  let ownerUserId;
  if (!owner) {
    const insertedOwner = await client.query(
      `INSERT INTO users (full_name, email, password_hash, account_type, status)
       VALUES ('Platform Owner Development', 'owner@avera.test', $1, 'PlatformOwner', 'Active')
       RETURNING user_id`,
      [ownerPasswordHash],
    );
    ownerUserId = insertedOwner.rows[0].user_id;
    console.log('Created platform owner development account.');
  } else {
    ownerUserId = owner.user_id;
    await client.query(
      `UPDATE users
          SET password_hash = $1, status = 'Active', failed_login_count = 0,
              locked_until = NULL, updated_at = now()
        WHERE user_id = $2`,
      [ownerPasswordHash, ownerUserId],
    );
    await client.query('UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [ownerUserId]);
    console.log('Updated platform owner development account.');
  }
  const administrator = await ensureDevelopmentIdentity(client, {
    email: 'admin@avera.test',
    legacyEmail: 'admin@zevora.local',
    accountType: 'ClinicAdministrator',
  });
  const administratorPasswordHash = await hashPassword(process.env.DEVELOPMENT_CLINIC_ADMIN_PASSWORD);
  let administratorUserId;
  if (!administrator) {
    const insertedAdministrator = await client.query(
      `INSERT INTO users (clinic_id, full_name, email, password_hash, account_type, status, role_id)
       VALUES ($1, 'System Administrator', 'admin@avera.test', $2, 'ClinicAdministrator', 'Active', $3)
       RETURNING user_id`,
      [clinicId, administratorPasswordHash, adminRoleId],
    );
    administratorUserId = insertedAdministrator.rows[0].user_id;
    console.log('Created clinic administrator development account.');
  } else {
    administratorUserId = administrator.user_id;
    await client.query(
      `UPDATE users
          SET clinic_id = $1, role_id = $2, password_hash = $3, status = 'Active',
              failed_login_count = 0, locked_until = NULL, updated_at = now()
        WHERE user_id = $4`,
      [clinicId, adminRoleId, administratorPasswordHash, administratorUserId],
    );
    await client.query('UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [administratorUserId]);
    console.log('Updated clinic administrator development account.');
  }
  await client.query(
    `INSERT INTO clinic_memberships
       (user_id, clinic_id, role_id, membership_status, activated_at, created_at, updated_at)
     VALUES ($1, $2, $3, 'Active', now(), now(), now())
     ON CONFLICT (user_id, clinic_id) DO UPDATE
       SET role_id = EXCLUDED.role_id, membership_status = 'Active',
           activated_at = COALESCE(clinic_memberships.activated_at, now()),
           updated_at = now(), deleted_at = NULL`,
    [administratorUserId, clinicId, adminRoleId],
  );
  await client.query('COMMIT');
  console.log('Development seed completed.');
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
} finally {
  client.release();
  await pool.end();
}

async function ensureDevelopmentIdentity(client, { email, legacyEmail, accountType }) {
  const identities = await client.query(
    `SELECT user_id, email FROM users
      WHERE email IN ($1, $2) AND account_type = $3
      FOR UPDATE`,
    [email, legacyEmail, accountType],
  );
  const current = identities.rows.find((row) => row.email.toLowerCase() === email);
  const legacy = identities.rows.find((row) => row.email.toLowerCase() === legacyEmail);
  if (current && legacy) throw new Error(`Conflicting development identities exist for ${accountType}; resolve them before seeding.`);
  if (current) return current;
  if (!legacy) return null;
  // Rename in place so IDs, memberships, permissions, and audit history remain
  // attached; the caller refreshes the development-only password hash.
  await client.query('UPDATE users SET email = $1, updated_at = now() WHERE user_id = $2', [email, legacy.user_id]);
  return legacy;
}
