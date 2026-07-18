import { z } from 'zod';
import { authenticate } from '../middleware/auth.js';
import { withTenantTransaction } from '../database/pool.js';

const operationSchema = z.object({
  operationId: z.string().uuid(),
  clinicId: z.string().uuid(),
  userId: z.string().uuid(),
  deviceId: z.string().min(1).max(200),
  entityType: z.enum(['patient', 'consultation', 'vaccination', 'schedule', 'inventory_item', 'invoice']),
  entityId: z.string().min(1).max(200),
  operationType: z.enum(['create', 'update']),
  localTimestamp: z.string().datetime(),
  baseVersion: z.number().int().nonnegative(),
  payload: z.record(z.string(), z.unknown()),
});

const permissionFor = (operation) => ({
  patient: operation.operationType === 'create' ? 'patients.create' : 'patients.edit',
  consultation: operation.operationType === 'create' ? 'consultations.create' : 'consultations.edit',
  vaccination: 'vaccinations.add',
  schedule: 'appointments.create',
  inventory_item: 'inventory.manage',
  invoice: 'billing.manage',
})[operation.entityType];

export async function syncRoutes(app) {
  app.post('/api/v1/sync/operations', { preHandler: authenticate }, async (request, reply) => {
    const parsed = operationSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'The offline operation is not valid.' });
    const operation = parsed.data;
    if (!request.auth.clinicId || request.auth.clinicId !== operation.clinicId || request.auth.userId !== operation.userId) {
      return reply.code(403).send({ error: 'tenant_access_denied', message: 'This offline operation does not belong to the active clinic workspace.' });
    }
    const permission = permissionFor(operation);
    if (!request.auth.permissions.includes('*') && !request.auth.permissions.includes(permission)) {
      return reply.code(403).send({ error: 'permission_denied', message: 'You do not have permission to synchronize this operation.' });
    }
    await withTenantTransaction(app.pool, request.auth, async (client) => {
      await client.query(
        `INSERT INTO sync_operations (operation_id, clinic_id, user_id, device_id, entity_type, entity_id, operation_type, local_timestamp, base_version, payload)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         ON CONFLICT (clinic_id, operation_id) DO NOTHING`,
        [operation.operationId, operation.clinicId, operation.userId, operation.deviceId, operation.entityType, operation.entityId, operation.operationType, operation.localTimestamp, operation.baseVersion, operation.payload],
      );
    });
    return reply.code(202).send({ status: 'Received', operationId: operation.operationId });
  });
}
