import { authenticate, requirePermission } from '../middleware/auth.js';
import { randomUUID } from 'node:crypto';
import { hasPermission, permissions } from '../security/permissions.js';
import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';
import { z } from 'zod';

const userStatusSchema = z.object({
  status: z.enum(['Active', 'Suspended', 'Deactivated']),
  reason: z.string().trim().max(500).optional(),
});

const clinicApplicationSchema = z.object({
  clinicName: z.string().trim().min(2).max(160),
  clinicEmail: z.string().trim().email(),
  phoneNumber: z.string().trim().min(5).max(40),
  address: z.string().trim().min(2).max(500),
  city: z.string().trim().min(2).max(120),
  country: z.string().trim().min(2).max(120),
  administratorName: z.string().trim().min(2).max(160),
  administratorEmail: z.string().trim().email(),
  administratorPhone: z.string().trim().min(5).max(40),
  professionalTitle: z.string().trim().max(160).optional().default(''),
  subscriptionPlan: z.enum(['Starter', 'Professional', 'Enterprise']),
  timeZone: z.string().trim().min(1).max(120).default('Africa/Lagos'),
});

const registrationPaymentInitializeSchema = z.object({
  accessToken: z.string().trim().min(20),
  billingCycle: z.enum(['monthly', 'annual']).default('monthly'),
  retry: z.boolean().optional().default(false),
});

const registrationPaymentVerifySchema = z.object({
  accessToken: z.string().trim().min(20),
  reference: z.string().trim().min(8).max(160),
});

const clinicApplicationPaymentScope = 'clinic-application-payment';

const clinicStatusSchema = z.object({
  status: z.enum([
    'Pending',
    'PendingApproval',
    'Active',
    'Suspended',
    'Rejected',
    'Archived',
  ]),
  reason: z.string().trim().min(3).max(500).optional(),
});

const clinicSubscriptionSchema = z.object({
  plan: z.enum(['Starter', 'Professional', 'Enterprise']),
  reason: z.string().trim().min(3).max(500).optional(),
});

export async function platformRoutes(app) {
  app.post(
    '/api/v1/clinic-applications',
    { config: { rateLimit: { max: 5, timeWindow: '1 hour' } } },
    async (request, reply) => {
      const parsed = clinicApplicationSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'validation_error',
          message: 'Provide complete and valid clinic application details.',
        });
      }
      const input = parsed.data;
      const application = await withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        async (client) => {
          await client.query(
            'SELECT pg_advisory_xact_lock(hashtext($1))',
            [`clinic-application:${input.administratorEmail.toLowerCase()}`],
          );
          const duplicate = await client.query(
            `SELECT application_id
               FROM clinic_applications
              WHERE lower(administrator_email::text) = lower($1)
                AND status IN ('Pending', 'PendingApproval', 'Approved')
              LIMIT 1`,
            [input.administratorEmail],
          );
          if (duplicate.rows.length > 0) return null;

          const clinicId = randomUUID();
          const reference = `AVR-${new Date()
            .toISOString()
            .slice(0, 10)
            .replaceAll('-', '')}-${clinicId.slice(0, 6).toUpperCase()}`;
          await client.query(
            `INSERT INTO clinics
               (clinic_id, name, status, subscription_plan, email, phone,
                address, city, country, time_zone)
             VALUES ($1, $2, 'PendingApproval', $3, $4, $5, $6, $7, $8, $9)`,
            [
              clinicId,
              input.clinicName,
              input.subscriptionPlan,
              input.clinicEmail.toLowerCase(),
              input.phoneNumber,
              input.address,
              input.city,
              input.country,
              input.timeZone,
            ],
          );
          const inserted = await client.query(
            `INSERT INTO clinic_applications
               (clinic_id, status, selected_plan, payment_status,
                application_reference, clinic_name, clinic_email, clinic_phone,
                address, city, country, time_zone, administrator_name,
                administrator_email, administrator_phone, professional_title)
             VALUES
               ($1, 'Pending', $2, 'Pending', $3, $4, $5, $6, $7, $8,
                $9, $10, $11, $12, $13, $14)
             RETURNING application_id, application_reference, status, submitted_at`,
            [
              clinicId,
              input.subscriptionPlan,
              reference,
              input.clinicName,
              input.clinicEmail.toLowerCase(),
              input.phoneNumber,
              input.address,
              input.city,
              input.country,
              input.timeZone,
              input.administratorName,
              input.administratorEmail.toLowerCase(),
              input.administratorPhone,
              input.professionalTitle || null,
            ],
          );
          await writeAudit(client, {
            clinicId,
            actingUserId: null,
            targetType: 'Clinic',
            targetId: clinicId,
            action: 'clinic.application_submitted',
            newSummary: {
              applicationReference: reference,
              selectedPlan: input.subscriptionPlan,
              status: 'Pending',
            },
            ipAddress: request.ip,
          });
          return { ...inserted.rows[0], clinic_id: clinicId };
        },
      );
      if (!application) {
        return reply.code(409).send({
          error: 'application_exists',
          message: 'An active clinic application already exists for this administrator.',
        });
      }
      return reply.code(201).send({
        application: {
          applicationId: application.application_id,
          clinicId: application.clinic_id,
          reference: application.application_reference,
          selectedPlan: input.subscriptionPlan,
          status: 'Pending',
          paymentStatus: 'Pending',
          paymentAccessToken: createClinicApplicationPaymentToken(app, {
            applicationId: application.application_id,
            clinicId: application.clinic_id,
            selectedPlan: input.subscriptionPlan,
          }),
          submittedAt: application.submitted_at,
        },
      });
    },
  );

  app.post(
    '/api/v1/clinic-applications/:applicationId/payments/paystack/initialize',
    { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } },
    async (request, reply) => {
      const parsed = registrationPaymentInitializeSchema.safeParse(request.body);
      if (!parsed.success) return registrationPaymentValidationError(reply);
      const access = verifyClinicApplicationPaymentToken(
        app,
        parsed.data.accessToken,
        request.params.applicationId,
      );
      if (!access) return registrationPaymentForbidden(reply);
      return handleRegistrationPayment(reply, () =>
        app.subscriptionService.initializeApplicationCheckout({
          applicationId: access.applicationId,
          clinicId: access.clinicId,
          billingCycle: parsed.data.billingCycle,
          retry: parsed.data.retry,
        }),
      );
    },
  );

  app.post(
    '/api/v1/clinic-applications/:applicationId/payments/paystack/verify',
    { config: { rateLimit: { max: 30, timeWindow: '1 hour' } } },
    async (request, reply) => {
      const parsed = registrationPaymentVerifySchema.safeParse(request.body);
      if (!parsed.success) return registrationPaymentValidationError(reply);
      const access = verifyClinicApplicationPaymentToken(
        app,
        parsed.data.accessToken,
        request.params.applicationId,
      );
      if (!access) return registrationPaymentForbidden(reply);
      return handleRegistrationPayment(reply, () =>
        app.subscriptionService.verifyApplicationPayment({
          applicationId: access.applicationId,
          clinicId: access.clinicId,
          reference: parsed.data.reference,
        }),
      );
    },
  );

  const platformView = [
    authenticate,
    requirePlatformAccount,
    requirePermission(permissions.clinicsView),
  ];

  app.get('/api/v1/platform/overview', { preHandler: platformView }, async () =>
    withTenantTransaction(
      app.pool,
      { isPlatformOwner: true },
      async (client) => {
        const totals = (
          await client.query(
            `SELECT
              (SELECT count(*)::int FROM clinics
                WHERE deleted_at IS NULL) AS total_clinics,
              (SELECT count(*)::int FROM clinics
                WHERE deleted_at IS NULL AND lower(status) = 'active') AS active_clinics,
              (SELECT count(*)::int FROM clinics
                WHERE deleted_at IS NULL
                  AND lower(status) IN ('pending', 'pendingapproval')) AS pending_applications,
              (SELECT count(*)::int FROM clinics
                WHERE deleted_at IS NULL AND lower(status) = 'suspended') AS suspended_clinics,
              (SELECT count(*)::int FROM users
                WHERE deleted_at IS NULL AND status = 'Active') AS active_users,
              (SELECT count(*)::int FROM subscriptions
                WHERE status = 'Expired') AS expired_subscriptions,
              (SELECT COALESCE(sum(amount_minor), 0)::bigint
                 FROM subscription_payment_transactions
                WHERE status = 'Successful'
                  AND paid_at >= date_trunc('month', now())
                  AND paid_at < date_trunc('month', now()) + interval '1 month')
                AS monthly_revenue_minor`,
          )
        ).rows[0];
        const recent = await queryPlatformClinics(client, { limit: 5 });
        return {
          totalClinics: totals.total_clinics,
          activeClinics: totals.active_clinics,
          pendingApplications: totals.pending_applications,
          suspendedClinics: totals.suspended_clinics,
          activeUsers: totals.active_users,
          expiredSubscriptions: totals.expired_subscriptions,
          monthlyRevenueMinor: Number(totals.monthly_revenue_minor),
          currency: app.environment.PAYSTACK_CURRENCY ?? 'NGN',
          recentClinics: recent.items,
        };
      },
    ),
  );

  app.get('/api/v1/platform/clinics', { preHandler: platformView }, async (request) =>
    withTenantTransaction(
      app.pool,
      { isPlatformOwner: true },
      (client) =>
        queryPlatformClinics(client, {
          status: request.query?.status,
          limit: request.query?.pageSize,
          offset:
            (Math.max(1, Number(request.query?.page) || 1) - 1) *
            Math.min(100, Math.max(1, Number(request.query?.pageSize) || 25)),
        }),
    ),
  );

  app.get(
    '/api/v1/platform/clinics/:clinicId',
    { preHandler: platformView },
    async (request, reply) => {
      const clinic = await withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        (client) => loadPlatformClinic(client, request.params.clinicId),
      );
      if (!clinic) {
        return reply.code(404).send({
          error: 'not_found',
          message: 'Clinic not found.',
        });
      }
      return { clinic };
    },
  );

  app.patch(
    '/api/v1/platform/clinics/:clinicId/status',
    { preHandler: [authenticate, requirePlatformAccount] },
    async (request, reply) => {
      const parsed = clinicStatusSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'validation_error',
          message: 'Select a valid clinic status.',
        });
      }
      const permission =
        parsed.data.status === 'Suspended'
          ? permissions.clinicsSuspend
          : permissions.clinicsApprove;
      if (!hasPermission(request, permission)) {
        return reply.code(403).send({
          error: 'forbidden',
          message: 'You do not have permission to change this clinic status.',
        });
      }
      const storedStatus =
        parsed.data.status === 'Pending' ? 'PendingApproval' : parsed.data.status;
      const result = await withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        async (client) => {
          const previous = await loadPlatformClinic(
            client,
            request.params.clinicId,
            true,
          );
          if (!previous) return null;
          await client.query(
            `UPDATE clinics
                SET status = $1, updated_at = now(), updated_by = $2,
                    revision = revision + 1
              WHERE clinic_id = $3`,
            [storedStatus, request.auth.userId, request.params.clinicId],
          );
          let administratorProvision = null;
          if (storedStatus === 'Active') {
            const isInitialApproval = ['Pending', 'PendingApproval'].includes(
              previous.status,
            );
            if (isInitialApproval) {
              administratorProvision = await app.activationService.provisionOnApproval(
                client,
                {
                  clinicId: request.params.clinicId,
                  clinicName: previous.clinicName,
                  actorUserId: request.auth.userId,
                  sessionId: request.auth.sessionId,
                  ipAddress: request.ip,
                },
              );
            }
          }
          if (storedStatus === 'Suspended') {
            await client.query(
              `UPDATE sessions
                  SET revoked_at = now()
                WHERE user_id IN (
                  SELECT user_id FROM users WHERE clinic_id = $1
                ) AND revoked_at IS NULL`,
              [request.params.clinicId],
            );
          }
          await writeAudit(client, {
            clinicId: request.params.clinicId,
            actingUserId: request.auth.userId,
            targetType: 'Clinic',
            targetId: request.params.clinicId,
            action:
              storedStatus === 'Suspended'
                ? 'clinic.suspended'
                : storedStatus === 'Active'
                  ? 'clinic.approved_or_reactivated'
                  : 'clinic.status_changed',
            previousSummary: { status: previous.status },
            newSummary: { status: normalizeClinicStatus(storedStatus) },
            sessionId: request.auth.sessionId,
            ipAddress: request.ip,
            reason: parsed.data.reason,
          });
          return {
            clinic: await loadPlatformClinic(client, request.params.clinicId),
            issued: administratorProvision?.issued ?? null,
          };
        },
      );
      if (!result?.clinic) {
        return reply.code(404).send({
          error: 'not_found',
          message: 'Clinic not found.',
        });
      }
      const activation = result.issued
        ? await app.activationService.deliverIssuedToken(result.issued)
        : await app.activationService.activationStatus(request.params.clinicId);
      return { clinic: result.clinic, activation };
    },
  );

  app.get(
    '/api/v1/platform/clinics/:clinicId/administrator-activation',
    { preHandler: platformView },
    async (request) => ({
      activation: await app.activationService.activationStatus(
        request.params.clinicId,
      ),
    }),
  );

  app.post(
    '/api/v1/platform/clinics/:clinicId/administrator-activation/resend',
    {
      preHandler: [
        authenticate,
        requirePlatformAccount,
        requirePermission(permissions.clinicsApprove),
      ],
    },
    async (request, reply) => {
      try {
        const activation = await app.activationService.resend({
          clinicId: request.params.clinicId,
          actorUserId: request.auth.userId,
          sessionId: request.auth.sessionId,
          ipAddress: request.ip,
        });
        return { activation };
      } catch (error) {
        return reply.code(error.statusCode ?? 400).send({
          error: error.code ?? 'activation_resend_failed',
          message: error.message,
        });
      }
    },
  );

  app.patch(
    '/api/v1/platform/clinics/:clinicId/subscription',
    {
      preHandler: [
        authenticate,
        requirePlatformAccount,
        requirePermission(permissions.subscriptionsManage),
      ],
    },
    async (request, reply) => {
      const parsed = clinicSubscriptionSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'validation_error',
          message: 'Select a valid subscription plan.',
        });
      }
      const clinic = await withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        async (client) => {
          const previous = await loadPlatformClinic(
            client,
            request.params.clinicId,
            true,
          );
          if (!previous) return null;
          const plan = await client.query(
            'SELECT plan_key FROM plans WHERE plan_key = $1 AND active = true',
            [parsed.data.plan],
          );
          if (plan.rows.length === 0) {
            const error = new Error('The selected subscription plan is unavailable.');
            error.statusCode = 409;
            throw error;
          }
          await client.query(
            `UPDATE clinics
                SET subscription_plan = $1, updated_at = now(),
                    updated_by = $2, revision = revision + 1
              WHERE clinic_id = $3`,
            [parsed.data.plan, request.auth.userId, request.params.clinicId],
          );
          await client.query(
            `UPDATE subscriptions
                SET plan = $1, updated_at = now()
              WHERE clinic_id = $2
                AND status IN ('Trial', 'Pending Payment', 'Active',
                               'Past Due', 'Non-renewing')`,
            [parsed.data.plan, request.params.clinicId],
          );
          await writeAudit(client, {
            clinicId: request.params.clinicId,
            actingUserId: request.auth.userId,
            targetType: 'Subscription',
            targetId: request.params.clinicId,
            action: 'subscription.plan_changed_by_platform',
            previousSummary: { plan: previous.subscriptionPlan },
            newSummary: { plan: parsed.data.plan },
            sessionId: request.auth.sessionId,
            ipAddress: request.ip,
            reason: parsed.data.reason,
          });
          return loadPlatformClinic(client, request.params.clinicId);
        },
      );
      if (!clinic) {
        return reply.code(404).send({
          error: 'not_found',
          message: 'Clinic not found.',
        });
      }
      return { clinic };
    },
  );

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

export function createClinicApplicationPaymentToken(app, application) {
  const ttlMinutes =
    Number(app.environment.REGISTRATION_PAYMENT_TOKEN_TTL_MINUTES) || 1440;
  return app.jwt.sign(
    {
      scope: clinicApplicationPaymentScope,
      applicationId: application.applicationId,
      clinicId: application.clinicId,
      selectedPlan: application.selectedPlan,
      nonce: randomUUID(),
    },
    { expiresIn: ttlMinutes * 60 },
  );
}

function verifyClinicApplicationPaymentToken(app, token, applicationId) {
  try {
    const access = app.jwt.verify(token);
    if (
      access.scope !== clinicApplicationPaymentScope ||
      access.applicationId !== applicationId ||
      typeof access.clinicId !== 'string' ||
      access.clinicId.length === 0
    ) {
      return null;
    }
    return access;
  } catch (_) {
    return null;
  }
}

function registrationPaymentForbidden(reply) {
  return reply.code(403).send({
    error: 'registration_payment_access_denied',
    message: 'This clinic payment session is invalid or has expired.',
  });
}

function registrationPaymentValidationError(reply) {
  return reply.code(400).send({
    error: 'validation_error',
    message: 'Provide a valid clinic payment session.',
  });
}

async function handleRegistrationPayment(reply, action) {
  try {
    return await action();
  } catch (error) {
    if (error.statusCode) {
      return reply.code(error.statusCode).send({
        error: error.code ?? 'registration_payment_error',
        message: error.message,
      });
    }
    throw error;
  }
}

async function requirePlatformAccount(request, reply) {
  if (
    request.auth?.accountType !== 'PlatformOwner' &&
    request.auth?.accountType !== 'PlatformAdministrator'
  ) {
    return reply.code(403).send({
      error: 'forbidden',
      message: 'Platform administration access is required.',
    });
  }
}

async function queryPlatformClinics(
  client,
  { status, limit = 25, offset = 0 } = {},
) {
  const pageSize = Math.min(100, Math.max(1, Number(limit) || 25));
  const parameters = [];
  let statusClause = '';
  if (status) {
    parameters.push(
      String(status).toLowerCase() === 'pending'
        ? ['pending', 'pendingapproval']
        : [String(status).toLowerCase()],
    );
    statusClause = ` AND lower(c.status) = ANY($${parameters.length}::text[])`;
  }
  const total = (
    await client.query(
      `SELECT count(*)::int AS count
         FROM clinics c
        WHERE c.deleted_at IS NULL${statusClause}`,
      parameters,
    )
  ).rows[0].count;
  parameters.push(pageSize, Math.max(0, Number(offset) || 0));
  const rows = await client.query(
    `${platformClinicSelect()}
      WHERE c.deleted_at IS NULL${statusClause}
      ORDER BY c.created_at DESC
      LIMIT $${parameters.length - 1} OFFSET $${parameters.length}`,
    parameters,
  );
  return {
    items: rows.rows.map(mapPlatformClinic),
    total,
    pageSize,
    hasNextPage: parameters.at(-1) + rows.rows.length < total,
  };
}

async function loadPlatformClinic(client, clinicId, forUpdate = false) {
  const result = await client.query(
    `${platformClinicSelect()}
      WHERE c.clinic_id = $1 AND c.deleted_at IS NULL
      ${forUpdate ? 'FOR UPDATE OF c' : ''}`,
    [clinicId],
  );
  return result.rows[0] ? mapPlatformClinic(result.rows[0]) : null;
}

function platformClinicSelect() {
  return `
    SELECT c.clinic_id, c.name, c.email, c.phone, c.address, c.city,
           c.country, c.time_zone, c.status, c.subscription_plan,
           c.created_at, c.updated_at,
           a.application_reference, a.payment_status,
           s.status AS subscription_status,
           (SELECT count(*)::int FROM users u
             WHERE u.clinic_id = c.clinic_id AND u.deleted_at IS NULL) AS user_count,
           (SELECT count(*)::int FROM patients p
             WHERE p.clinic_id = c.clinic_id AND p.deleted_at IS NULL) AS patient_count
      FROM clinics c
      LEFT JOIN LATERAL (
        SELECT application_reference, payment_status
          FROM clinic_applications
         WHERE clinic_id = c.clinic_id
         ORDER BY submitted_at DESC LIMIT 1
      ) a ON true
      LEFT JOIN LATERAL (
        SELECT status
          FROM subscriptions
         WHERE clinic_id = c.clinic_id
         ORDER BY updated_at DESC LIMIT 1
      ) s ON true`;
}

function mapPlatformClinic(row) {
  return {
    clinicId: row.clinic_id,
    clinicName: row.name,
    email: row.email,
    phoneNumber: row.phone,
    address: row.address,
    city: row.city,
    country: row.country,
    location: [row.city, row.country].filter(Boolean).join(', '),
    timeZone: row.time_zone,
    status: normalizeClinicStatus(row.status),
    rawStatus: row.status,
    subscriptionPlan: row.subscription_plan,
    subscriptionStatus: row.subscription_status,
    paymentStatus: row.payment_status,
    applicationReference: row.application_reference,
    registrationDate: row.created_at,
    updatedAt: row.updated_at,
    userCount: row.user_count,
    patientCount: row.patient_count,
  };
}

export function normalizeClinicStatus(status) {
  return String(status).toLowerCase() === 'pendingapproval'
    ? 'Pending'
    : status;
}
