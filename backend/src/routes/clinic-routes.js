import { withTenantTransaction } from '../database/pool.js';
import { authenticate, requirePermission } from '../middleware/auth.js';
import { permissions } from '../security/permissions.js';

export async function clinicRoutes(app) {
  app.get('/api/v1/users', { preHandler: [authenticate, requirePermission(permissions.usersView)] }, async (request, reply) => {
    if (!request.auth.clinicId) return reply.code(400).send({ error: 'clinic_context_required', message: 'Select a clinic workspace first.' });
    const users = await withTenantTransaction(app.pool, request.auth, async (client) => (
      await client.query(
        `SELECT user_id, full_name, email, phone, account_type, status, role_id, last_login_at, created_at
           FROM users WHERE clinic_id = $1 AND deleted_at IS NULL ORDER BY full_name LIMIT 100`,
        [request.auth.clinicId],
      )
    )).rows;
    return { users };
  });

  app.get('/api/v1/roles', { preHandler: [authenticate, requirePermission(permissions.usersView)] }, async (request, reply) => {
    if (!request.auth.clinicId) return reply.code(400).send({ error: 'clinic_context_required', message: 'Select a clinic workspace first.' });
    const roles = await withTenantTransaction(app.pool, request.auth, async (client) => (
      await client.query('SELECT role_id, name, description, is_system_role FROM roles WHERE clinic_id = $1 AND deleted_at IS NULL ORDER BY name', [request.auth.clinicId])
    )).rows;
    return { roles };
  });

  app.get('/api/v1/permissions', { preHandler: [authenticate] }, async () => {
    const available = Object.values(permissions);
    return { permissions: available };
  });
}
