import { authenticate, requirePermission } from '../middleware/auth.js';
import { permissions } from '../security/permissions.js';
import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';
import { z } from 'zod';

const userStatusSchema = z.object({
  status: z.enum(['Active', 'Suspended', 'Deactivated']),
  reason: z.string().trim().max(500).optional(),
});

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

  app.patch('/api/v1/platform/users/:userId/status', {
    preHandler: [authenticate, requirePermission(permissions.clinicsSuspend)],
  }, async (request, reply) => {
    const parsed = userStatusSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Select a valid account status.' });
    }
    const updated = await withTenantTransaction(app.pool, { isPlatformOwner: true }, async (client) => {
      const previous = (await client.query(
        'SELECT user_id, clinic_id, full_name, account_type, status FROM users WHERE user_id = $1 AND deleted_at IS NULL FOR UPDATE',
        [request.params.userId],
      )).rows[0];
      if (!previous) return null;
      if (previous.account_type === 'PlatformOwner') {
        const count = await client.query("SELECT count(*)::int AS count FROM users WHERE account_type = 'PlatformOwner' AND status = 'Active' AND deleted_at IS NULL");
        if (previous.status === 'Active' && parsed.data.status !== 'Active' && count.rows[0].count <= 1) {
          const error = new Error('The protected primary Platform Owner cannot be suspended.');
          error.statusCode = 409;
          throw error;
        }
      }
      const suspended = parsed.data.status === 'Suspended';
      await client.query(
        `UPDATE users SET status = $1, token_version = token_version + 1,
          suspended_at = CASE WHEN $2 THEN now() ELSE suspended_at END,
          suspended_by_user_id = CASE WHEN $2 THEN $3 ELSE suspended_by_user_id END,
          suspension_reason = CASE WHEN $2 THEN $4 ELSE suspension_reason END,
          reactivated_at = CASE WHEN $1 = 'Active' THEN now() ELSE reactivated_at END,
          updated_at = now(), updated_by = $3
         WHERE user_id = $5`,
        [parsed.data.status, suspended, request.auth.userId, parsed.data.reason ?? null, previous.user_id],
      );
      await client.query(
        "UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL",
        [previous.user_id],
      );
      await client.query(
        "UPDATE devices SET revoked_at = now(), biometric_enabled = false WHERE user_id = $1 AND revoked_at IS NULL",
        [previous.user_id],
      );
      await client.query(
        "UPDATE mfa_challenges SET revoked_at = now() WHERE user_id = $1 AND consumed_at IS NULL AND revoked_at IS NULL",
        [previous.user_id],
      );
      await writeAudit(client, {
        clinicId: previous.clinic_id,
        actingUserId: request.auth.userId,
        targetType: 'User',
        targetId: previous.user_id,
        action: suspended ? 'user.suspended' : parsed.data.status === 'Active' ? 'user.reactivated' : 'user.deactivated',
        previousSummary: { status: previous.status },
        newSummary: { status: parsed.data.status },
        sessionId: request.auth.sessionId,
        ipAddress: request.ip,
        reason: parsed.data.reason,
      });
      return { userId: previous.user_id, status: parsed.data.status };
    });
    if (!updated) return reply.code(404).send({ error: 'not_found', message: 'User not found.' });
    return updated;
  });
}
