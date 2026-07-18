import { createPool } from '../database/pool.js';
import { loadEnvironment } from '../config/env.js';

const permissionDefinitions = [
  ['clinics.view', 'View the active clinic workspace'], ['dashboard.view', 'View clinic dashboard'],
  ['patients.view', 'View patients'], ['patients.create', 'Create patients'], ['patients.edit', 'Edit patients'],
  ['consultations.view', 'View consultations'], ['consultations.create', 'Create consultations'], ['consultations.edit', 'Edit consultations'],
  ['vaccinations.view', 'View vaccinations'], ['vaccinations.add', 'Add vaccinations'],
  ['laboratory.view', 'View laboratory reports'], ['laboratory.add', 'Add laboratory results'],
  ['hospitalization.view', 'View hospitalizations'], ['hospitalization.add', 'Add hospitalizations'],
  ['surgery.view', 'View surgeries'], ['surgery.add', 'Add surgeries'],
  ['prescriptions.view', 'View prescriptions'], ['prescriptions.create', 'Create prescriptions'],
  ['inventory.view', 'View inventory'], ['inventory.manage', 'Manage inventory'],
  ['appointments.view', 'View schedule'], ['appointments.create', 'Create schedule entries'],
  ['billing.view', 'View billing'], ['billing.manage', 'Manage billing'], ['media.view', 'View media'],
  ['users.view', 'View users'], ['users.create', 'Create users'], ['users.assign_roles', 'Assign roles'],
];

const environment = loadEnvironment();
if (environment.NODE_ENV === 'production' || !environment.demoDataGeneratorEnabled) {
  throw new Error('Demo access provisioning is disabled outside an enabled development or staging environment.');
}

const pool = createPool(environment.DATABASE_URL);
try {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const [key, description] of permissionDefinitions) {
      await client.query('INSERT INTO permissions (permission_key, description) VALUES ($1,$2) ON CONFLICT (permission_key) DO NOTHING', [key, description]);
    }
    const result = await client.query(
      `INSERT INTO role_permissions (role_id, permission_id)
       SELECT r.role_id, p.permission_id FROM roles r CROSS JOIN permissions p
        WHERE r.clinic_id IN (SELECT clinic_id FROM clinics WHERE is_demo = true)
          AND p.permission_key = ANY($1::text[])
       ON CONFLICT DO NOTHING`,
      [permissionDefinitions.map(([key]) => key)],
    );
    await client.query('COMMIT');
    console.log(`Granted demo clinical permissions to demo roles (${result.rowCount} new mappings).`);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
} finally {
  await pool.end();
}
