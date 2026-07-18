import { effectivePermissions, hasPermission } from '../security/permissions.js';
import { clinicAccess } from '../security/clinic-access.js';

export async function authenticate(request, reply) {
  try {
    await request.jwtVerify();
    const session = await request.server.pool.query(
      `SELECT s.session_id, u.*, s.revoked_at, s.expires_at FROM sessions s JOIN users u ON u.user_id = s.user_id
        WHERE s.session_id = $1`, [request.user.sessionId]);
    const row = session.rows[0];
    if (!row || row.revoked_at || row.expires_at < new Date() || row.status !== 'Active') throw new Error('Session is not active.');
    if (!(await clinicAccess(request.server.pool, row)).allowed) throw new Error('Clinic access is not active.');
    const permissions = await effectivePermissions(request.server.pool, row);
    request.auth = { userId: row.user_id, clinicId: row.clinic_id, accountType: row.account_type, sessionId: row.session_id, permissions };
  } catch (_) {
    return reply.code(401).send({ error: 'unauthorized', message: 'Authentication is required.' });
  }
}

export function requirePermission(permission) {
  return async (request, reply) => {
    if (!hasPermission(request, permission)) return reply.code(403).send({ error: 'forbidden', message: 'You do not have permission to perform this action.' });
  };
}
