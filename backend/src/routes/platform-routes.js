import { authenticate, requirePermission } from '../middleware/auth.js';
import { permissions } from '../security/permissions.js';
import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';

export async function platformRoutes(app) {
  app.get('/api/v1/clinics', { preHandler: [authenticate, requirePermission(permissions.clinicsView)] }, async (request) => {
    const result = await app.pool.query('SELECT clinic_id, name, status, subscription_plan, created_at FROM clinics WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 100');
    return { clinics: result.rows };
  });

  app.patch('/api/v1/clinics/:clinicId/status', { preHandler: [authenticate, requirePermission(permissions.clinicsApprove)] }, async (request, reply) => {
    const allowed = new Set(['Pending', 'Active', 'Suspended', 'Rejected']);
    if (!allowed.has(request.body?.status)) return reply.code(400).send({ error: 'validation_error', message: 'Invalid clinic status.' });
    await withTenantTransaction(app.pool, { isPlatformOwner: true }, async (client) => {
      const previous = await client.query('SELECT status FROM clinics WHERE clinic_id = $1 FOR UPDATE', [request.params.clinicId]);
      if (!previous.rows[0]) return reply.code(404).send({ error: 'not_found', message: 'Clinic not found.' });
      await client.query('UPDATE clinics SET status = $1, updated_at = now(), updated_by = $2, revision = revision + 1 WHERE clinic_id = $3', [request.body.status, request.auth.userId, request.params.clinicId]);
      await writeAudit(client, { actingUserId: request.auth.userId, targetType: 'Clinic', targetId: request.params.clinicId, action: 'clinic.status_changed', previousSummary: { status: previous.rows[0].status }, newSummary: { status: request.body.status }, sessionId: request.auth.sessionId, ipAddress: request.ip });
    });
    return reply.code(204).send();
  });

  app.get('/api/v1/audit-logs', { preHandler: [authenticate, requirePermission(permissions.auditLogsView)] }, async (request) => {
    const result = await app.pool.query('SELECT audit_id, clinic_id, action, target_type, target_id, created_at, success FROM audit_logs ORDER BY created_at DESC LIMIT 100');
    return { auditLogs: result.rows };
  });
}
