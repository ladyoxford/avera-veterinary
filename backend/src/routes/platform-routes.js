import { authenticate, requirePermission } from '../middleware/auth.js';
import { randomUUID } from 'node:crypto';
import { hasPermission, permissions } from '../security/permissions.js';
import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';
import { z } from 'zod';

export const platformLivePaymentClause =
  "status = 'Successful' AND gateway_response_summary->>'mode' = 'live'";

const userStatusSchema = z.object({
  status: z.enum(['Active', 'Suspended', 'Deactivated']),
  reason: z.string().trim().max(500).optional(),
});

const clinicApplicationSchema = z.object({
  clinicName: z.string().trim().min(2).max(160),
  accountEmail: z.string().trim().email().optional(),
  clinicEmail: z.string().trim().email().optional(),
  phoneNumber: z.string().trim().min(5).max(40),
  address: z.string().trim().min(2).max(500),
  city: z.string().trim().min(2).max(120),
  country: z.string().trim().min(2).max(120),
  administratorName: z.string().trim().min(2).max(160),
  administratorEmail: z.string().trim().email().optional(),
  administratorPhone: z.string().trim().min(5).max(40),
  professionalTitle: z.string().trim().max(160).optional().default(''),
  subscriptionPlan: z.enum(['Starter', 'Professional', 'Enterprise']),
  timeZone: z.string().trim().min(1).max(120).default('Africa/Lagos'),
  applicationId: z.string().uuid().optional(),
  draftAccessToken: z.string().trim().min(20).optional(),
}).superRefine((input, context) => {
  const emails = [input.accountEmail, input.administratorEmail, input.clinicEmail]
    .filter(Boolean)
    .map((email) => email.toLowerCase());
  if (emails.length === 0) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['accountEmail'], message: 'Account email is required.' });
  }
  if (new Set(emails).size > 1) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['accountEmail'], message: 'Registration uses one account email.' });
  }
}).transform((input) => ({
  ...input,
  accountEmail: String(
    input.accountEmail ?? input.administratorEmail ?? input.clinicEmail ?? '',
  ).toLowerCase(),
}));

const registrationPaymentInitializeSchema = z.object({
  accessToken: z.string().trim().min(20),
  billingCycle: z.enum(['monthly', 'annual']).default('monthly'),
  retry: z.boolean().optional().default(false),
});

const registrationPaymentPlanSchema = z.object({
  accessToken: z.string().trim().min(20),
});

const registrationPaymentVerifySchema = z.object({
  accessToken: z.string().trim().min(20),
  reference: z.string().trim().min(8).max(160),
});

const clinicApplicationPaymentScope = 'clinic-application-payment';
const clinicApplicationDraftScope = 'clinic-application-draft';

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

const clinicDeletionRequestSchema = z.object({
  reason: z.string().trim().min(3).max(500),
});

const clinicDeletionConfirmationSchema = z.object({
  code: z.string().trim().regex(/^\d{6}$/),
});

const platformListQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
  search: z.string().trim().max(160).optional(),
  status: z.string().trim().max(80).optional(),
}).strict();

const platformAuditQuerySchema = platformListQuerySchema.extend({
  action: z.string().trim().max(120).optional(),
  success: z.enum(['true', 'false']).optional(),
}).strict();

export async function platformRoutes(app) {
  app.post(
    '/api/v1/clinic-applications',
    // Carrier-grade NAT can place many legitimate mobile applicants behind one
    // public IP. The global limiter remains in force; this route allowance
    // prevents a handful of users from blocking clinic registration for an hour.
    { config: { rateLimit: { max: 20, timeWindow: '1 hour' } } },
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
            [`clinic-application:${input.applicationId ?? input.accountEmail}`],
          );
          const existing = (
            await client.query(
              input.applicationId
                ? `SELECT *
                     FROM clinic_applications
                    WHERE application_id = $1
                      AND status IN ('Draft', 'AwaitingPayment', 'Pending', 'PendingApproval', 'Approved')
                    FOR UPDATE`
                : `SELECT *
                     FROM clinic_applications
                    WHERE lower(administrator_email::text) = lower($1)
                      AND status IN ('Draft', 'AwaitingPayment', 'Pending', 'PendingApproval', 'Approved')
                    ORDER BY updated_at DESC, submitted_at DESC
                    LIMIT 1
                    FOR UPDATE`,
              [input.applicationId ?? input.accountEmail],
          )).rows[0];

          if (input.applicationId && !existing) {
            return { draftNotFound: true };
          }

          if (existing) {
            if (
              ['Paid', 'TestVerified'].includes(existing.payment_status) ||
              ['PendingApproval', 'Approved'].includes(existing.status)
            ) {
              return { blocked: true, application: existing };
            }
            const draftAccess = input.draftAccessToken
              ? verifyClinicApplicationDraftToken(app, input.draftAccessToken, existing.application_id)
              : null;
            if (
              !draftAccess ||
              input.applicationId !== existing.application_id ||
              draftAccess.clinicId !== existing.clinic_id ||
              draftAccess.accountEmail !== String(existing.administrator_email).toLowerCase()
            ) {
              return { resumeRequired: true, application: existing };
            }
            const accountEmailChanged =
              String(existing.administrator_email).trim().toLowerCase() !==
              input.accountEmail;
            const selectedPlanChanged =
              existing.selected_plan !== input.subscriptionPlan;
            if (
              existing.payment_reference &&
              (accountEmailChanged || selectedPlanChanged)
            ) {
              return {
                paymentSessionLocked: true,
                application: existing,
              };
            }
            await client.query(
              `UPDATE clinics
                  SET name = $2, subscription_plan = $3, email = $4, phone = $5,
                      address = $6, city = $7, country = $8, time_zone = $9,
                      status = 'RegistrationDraft', updated_at = now(),
                      revision = revision + 1
                WHERE clinic_id = $1`,
              [
                existing.clinic_id,
                input.clinicName,
                input.subscriptionPlan,
                input.accountEmail,
                input.phoneNumber,
                input.address,
                input.city,
                input.country,
                input.timeZone,
              ],
            );
            const updated = (
              await client.query(
                `UPDATE clinic_applications
                    SET status = 'AwaitingPayment', selected_plan = $2,
                        clinic_name = $3, clinic_email = $4, clinic_phone = $5,
                        address = $6, city = $7, country = $8, time_zone = $9,
                        administrator_name = $10, administrator_email = $4,
                        administrator_phone = $11, professional_title = $12,
                        updated_at = now()
                  WHERE application_id = $1
                  RETURNING *`,
                [
                  existing.application_id,
                  input.subscriptionPlan,
                  input.clinicName,
                  input.accountEmail,
                  input.phoneNumber,
                  input.address,
                  input.city,
                  input.country,
                  input.timeZone,
                  input.administratorName,
                  input.administratorPhone,
                  input.professionalTitle || null,
                ],
              )
            ).rows[0];
            await writeAudit(client, {
              clinicId: existing.clinic_id,
              actingUserId: null,
              targetType: 'ClinicApplication',
              targetId: existing.application_id,
              action: 'clinic.application_draft_updated',
              newSummary: { selectedPlan: input.subscriptionPlan, status: 'AwaitingPayment' },
              ipAddress: request.ip,
            });
            return { ...updated, created: false };
          }

          const clinicId = randomUUID();
          const reference = `AVR-${new Date()
            .toISOString()
            .slice(0, 10)
            .replaceAll('-', '')}-${clinicId.slice(0, 6).toUpperCase()}`;
          await client.query(
            `INSERT INTO clinics
               (clinic_id, name, status, subscription_plan, email, phone,
                address, city, country, time_zone)
             VALUES ($1, $2, 'RegistrationDraft', $3, $4, $5, $6, $7, $8, $9)`,
            [
              clinicId,
              input.clinicName,
              input.subscriptionPlan,
              input.accountEmail,
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
               ($1, 'AwaitingPayment', $2, 'Pending', $3, $4, $5, $6, $7, $8,
                $9, $10, $11, $12, $13, $14)
             RETURNING application_id, application_reference, status, submitted_at`,
            [
              clinicId,
              input.subscriptionPlan,
              reference,
              input.clinicName,
              input.accountEmail,
              input.phoneNumber,
              input.address,
              input.city,
              input.country,
              input.timeZone,
              input.administratorName,
              input.accountEmail,
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
          return { ...inserted.rows[0], clinic_id: clinicId, created: true };
        },
      );
      if (application.draftNotFound) {
        return reply.code(404).send({
          error: 'application_draft_not_found',
          message: 'This registration draft is no longer available.',
        });
      }
      if (application.resumeRequired) {
        return reply.code(409).send({
          error: 'application_resume_required',
          message: 'You already started registering this clinic. Continue from the device or verified provider that created it.',
        });
      }
      if (application.paymentSessionLocked) {
        return reply.code(409).send({
          error: 'application_payment_session_locked',
          message: 'This application already has a Paystack checkout. Keep its Account Email and plan unchanged, or start a separate clinic registration.',
        });
      }
      if (application.blocked) {
        const paid = ['Paid', 'TestVerified'].includes(application.application.payment_status);
        return reply.code(409).send({
          error: paid ? 'application_payment_verified' : 'application_pending_approval',
          message: paid
            ? 'Payment was received. Your clinic application is awaiting approval or activation.'
            : 'Your clinic application is already in the approval workflow.',
        });
      }
      let freePlanApproval = null;
      let paymentRequired = true;
      if (input.subscriptionPlan === 'Starter') {
        const plan = await app.subscriptionService.getApplicationPaymentPlan({
          applicationId: application.application_id,
          clinicId: application.clinic_id,
        });
        paymentRequired = plan.requiresPayment !== false;
        if (!paymentRequired) {
          freePlanApproval = await app.activationService.approveFreeApplication({
            applicationId: application.application_id,
            clinicId: application.clinic_id,
            ipAddress: request.ip,
          });
        }
      }
      return reply.code(application.created ? 201 : 200).send({
        application: {
          applicationId: application.application_id,
          clinicId: application.clinic_id,
          reference: application.application_reference,
          selectedPlan: input.subscriptionPlan,
          status: freePlanApproval?.approved ? 'Approved' : 'AwaitingPayment',
          paymentStatus: freePlanApproval?.approved
            ? 'NotRequired'
            : application.payment_status ?? 'Pending',
          paymentRequired,
          paymentAccessToken: paymentRequired
            ? createClinicApplicationPaymentToken(app, {
                applicationId: application.application_id,
                clinicId: application.clinic_id,
                selectedPlan: input.subscriptionPlan,
              })
            : null,
          draftAccessToken: createClinicApplicationDraftToken(app, {
            applicationId: application.application_id,
            clinicId: application.clinic_id,
            accountEmail: input.accountEmail,
          }),
          submittedAt: application.submitted_at,
          activation: freePlanApproval?.activation ?? null,
        },
      });
    },
  );

  app.post(
    '/api/v1/clinic-applications/:applicationId/payments/plan',
    { config: { rateLimit: { max: 30, timeWindow: '1 hour' } } },
    async (request, reply) => {
      const parsed = registrationPaymentPlanSchema.safeParse(request.body);
      if (!parsed.success) return registrationPaymentValidationError(reply);
      const access = verifyClinicApplicationPaymentToken(
        app,
        parsed.data.accessToken,
        request.params.applicationId,
      );
      if (!access) return registrationPaymentForbidden(reply);
      return handleRegistrationPayment(reply, async () => ({
        plan: await app.subscriptionService.getApplicationPaymentPlan({
          applicationId: access.applicationId,
          clinicId: access.clinicId,
        }),
      }));
    },
  );

  app.post(
    '/api/v1/clinic-applications/:applicationId/free-plan/continue',
    { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } },
    async (request, reply) => {
      const parsed = registrationPaymentPlanSchema.safeParse(request.body);
      if (!parsed.success) return registrationPaymentValidationError(reply);
      const access = verifyClinicApplicationPaymentToken(
        app,
        parsed.data.accessToken,
        request.params.applicationId,
      );
      if (!access) return registrationPaymentForbidden(reply);
      return handleRegistrationPayment(reply, async () => {
        const plan = await app.subscriptionService.getApplicationPaymentPlan({
          applicationId: access.applicationId,
          clinicId: access.clinicId,
        });
        if (plan.requiresPayment !== false) {
          const error = new Error('The selected plan requires verified payment.');
          error.code = 'payment_required';
          error.statusCode = 409;
          throw error;
        }
        const result = await app.activationService.approveFreeApplication({
          applicationId: access.applicationId,
          clinicId: access.clinicId,
          ipAddress: request.ip,
        });
        return {
          applicationApproved: result.approved === true,
          paymentRequired: false,
          paymentStatus: 'NotRequired',
          activation: result.activation,
        };
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
                  AND lower(status) IN
                    ('registrationdraft', 'pending', 'pendingapproval'))
                AS pending_applications,
              (SELECT count(*)::int FROM clinics
                WHERE deleted_at IS NULL AND lower(status) = 'suspended') AS suspended_clinics,
              (SELECT count(*)::int FROM users
                WHERE deleted_at IS NULL AND status = 'Active') AS active_users,
              (SELECT count(*)::int FROM subscriptions
                WHERE status = 'Expired') AS expired_subscriptions,
              (SELECT COALESCE(sum(amount_minor), 0)::bigint
                 FROM subscription_payment_transactions
                WHERE ${platformLivePaymentClause}
                  AND paid_at >= date_trunc('month', now())
                  AND paid_at < date_trunc('month', now()) + interval '1 month')
                AS monthly_revenue_minor,
              (SELECT count(*)::int FROM activation_tokens
                WHERE delivery_method = 'email_failed'
                  AND created_at >= now() - interval '24 hours')
                AS recent_email_failures,
              (SELECT count(*)::int FROM activation_tokens
                WHERE delivery_method IN ('email', 'email_submitted', 'delivered')
                  AND created_at >= now() - interval '24 hours')
                AS recent_email_submissions,
              (SELECT delivery_method FROM activation_tokens
                WHERE delivery_method IS NOT NULL
                ORDER BY created_at DESC LIMIT 1) AS latest_email_state,
              ((SELECT count(*) FROM patients
                  WHERE deleted_at IS NULL AND profile_photo_path IS NOT NULL)
                + (SELECT count(*) FROM inventory_products
                  WHERE deleted_at IS NULL AND image_path IS NOT NULL))::int
                AS storage_object_count`,
          )
        ).rows[0];
        const recent = await queryPlatformClinics(client, { limit: 5 });
        const emailConfigured = app.emailDeliveryService.configured;
        const storageConfigured = Boolean(
          app.environment.SUPABASE_URL &&
          app.environment.SUPABASE_SERVICE_ROLE_KEY,
        );
        return {
          totalClinics: totals.total_clinics,
          activeClinics: totals.active_clinics,
          pendingApplications: totals.pending_applications,
          suspendedClinics: totals.suspended_clinics,
          activeUsers: totals.active_users,
          expiredSubscriptions: totals.expired_subscriptions,
          monthlyRevenueMinor: Number(totals.monthly_revenue_minor),
          currency: app.environment.PAYSTACK_CURRENCY ?? 'NGN',
          emailDeliveryStatus: platformEmailStatus({
            configured: emailConfigured,
            failures: totals.recent_email_failures,
            submissions: totals.recent_email_submissions,
            latestState: totals.latest_email_state,
          }),
          systemHealthStatus: 'Operational',
          storageStatus: storageConfigured ? 'Configured' : 'Not configured',
          storageProvider: 'Supabase Storage',
          storageObjectCount: null,
          recentClinics: recent.items,
        };
      },
    ),
  );

  app.get(
    '/api/v1/platform/subscriptions',
    {
      preHandler: [
        authenticate,
        requirePlatformAccount,
        requirePermission(permissions.subscriptionsManage),
      ],
    },
    async (request, reply) => {
      const parsed = platformListQuerySchema.safeParse(request.query);
      if (!parsed.success) return platformListValidationError(reply);
      return withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        (client) => queryPlatformSubscriptions(client, parsed.data),
      );
    },
  );

  app.get(
    '/api/v1/platform/users',
    {
      preHandler: [
        authenticate,
        requirePlatformAccount,
        requirePermission(permissions.usersView),
      ],
    },
    async (request, reply) => {
      const parsed = platformListQuerySchema.safeParse(request.query);
      if (!parsed.success) return platformListValidationError(reply);
      return withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        (client) => queryPlatformUsers(client, parsed.data),
      );
    },
  );

  app.get(
    '/api/v1/platform/audit-logs',
    {
      preHandler: [
        authenticate,
        requirePlatformAccount,
        requirePermission(permissions.auditLogsView),
      ],
    },
    async (request, reply) => {
      const parsed = platformAuditQuerySchema.safeParse(request.query);
      if (!parsed.success) return platformListValidationError(reply);
      return withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        (client) => queryPlatformAuditLogs(client, parsed.data),
      );
    },
  );

  app.get(
    '/api/v1/platform/notifications',
    { preHandler: platformView },
    async () => withTenantTransaction(
      app.pool,
      { isPlatformOwner: true },
      queryPlatformNotifications,
    ),
  );

  app.get(
    '/api/v1/platform/operations/status',
    { preHandler: platformView },
    async () => {
      const checkedAt = new Date();
      const startedAt = process.hrtime.bigint();
      const persisted = await withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        queryPlatformOperations,
      );
      const databaseLatencyMs = Number(process.hrtime.bigint() - startedAt) / 1e6;
      const emailConfigured = app.emailDeliveryService.configured;
      const storageConfigured = Boolean(
        app.environment.SUPABASE_URL &&
        app.environment.SUPABASE_SERVICE_ROLE_KEY,
      );
      const paymentConfigured = Boolean(
        app.environment.PAYSTACK_MODE &&
        app.environment.PAYSTACK_SECRET_KEY,
      );
      return {
        system: {
          status: 'Operational',
          api: 'Operational',
          database: 'Connected',
          environment: app.environment.NODE_ENV,
          uptimeSeconds: Math.floor(process.uptime()),
          databaseLatencyMs: Number(databaseLatencyMs.toFixed(1)),
          checkedAt,
        },
        email: {
          provider: app.emailDeliveryService.providerLabel,
          configured: emailConfigured,
          status: platformEmailStatus({
            configured: emailConfigured,
            failures: persisted.recent_email_failures,
            submissions: persisted.recent_email_submissions,
            latestState: persisted.latest_email_state,
          }),
          recentSuccessfulSubmissions: Number(persisted.recent_email_submissions),
          recentFailedSubmissions: Number(persisted.recent_email_failures),
          latestState: persisted.latest_email_state,
          lastAttemptAt: persisted.last_email_attempt_at,
        },
        storage: {
          provider: 'Supabase Storage',
          configured: storageConfigured,
          status: storageConfigured ? 'Configured' : 'Not configured',
          objectCount: null,
          objectCountAvailable: false,
          actualBytesAvailable: false,
        },
        payments: {
          provider: 'Paystack',
          configured: paymentConfigured,
          status: paymentConfigured ? 'Configured' : 'Not configured',
          mode: app.environment.PAYSTACK_MODE ?? 'Not configured',
        },
      };
    },
  );

  app.get('/api/v1/platform/clinics', { preHandler: platformView }, async (request) =>
    withTenantTransaction(
      app.pool,
      { isPlatformOwner: true },
      (client) =>
        queryPlatformClinics(client, {
          status: request.query?.status,
          search: request.query?.search,
          paymentStatus: request.query?.paymentStatus,
          subscriptionPlan: request.query?.subscriptionPlan,
          sort: request.query?.sort,
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
      let result;
      try {
        result = await withTenantTransaction(
          app.pool,
          { isPlatformOwner: true },
          async (client) => {
          const previous = await loadPlatformClinic(
            client,
            request.params.clinicId,
            true,
          );
          if (!previous) return null;
          if (storedStatus === 'Active') {
            await assertClinicPaymentAllowsActivation(client, {
              clinicId: request.params.clinicId,
              previousStatus: previous.rawStatus,
              allowTestPayment: app.environment.PAYSTACK_MODE !== 'live',
            });
          }
          await client.query(
            `UPDATE clinics
                SET status = $1, updated_at = now(), updated_by = $2,
                    revision = revision + 1
              WHERE clinic_id = $3`,
            [storedStatus, request.auth.userId, request.params.clinicId],
          );
          let administratorProvision = null;
          if (storedStatus === 'Active') {
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
      } catch (error) {
        return reply.code(error.statusCode ?? 400).send({
          error: error.code ?? 'clinic_status_change_failed',
          message:
            error.message ?? 'The clinic status could not be changed right now.',
        });
      }
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

  app.post(
    '/api/v1/platform/clinics/:clinicId/administrator-activation/repair',
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
        return { activation, repaired: true };
      } catch (error) {
        return reply.code(error.statusCode ?? 400).send({
          error: error.code ?? 'administrator_repair_failed',
          message: error.message,
        });
      }
    },
  );

  app.post(
    '/api/v1/platform/clinics/:clinicId/payment/reconcile',
    {
      preHandler: [
        authenticate,
        requirePlatformAccount,
        requirePermission(permissions.clinicsApprove),
      ],
    },
    async (request, reply) => {
      const application = await withTenantTransaction(
        app.pool,
        { isPlatformOwner: true },
        async (client) => (
          await client.query(
            `SELECT application_id, clinic_id, payment_reference
               FROM clinic_applications
              WHERE clinic_id = $1
              ORDER BY submitted_at DESC
              LIMIT 1`,
            [request.params.clinicId],
          )
        ).rows[0],
      );
      if (!application?.payment_reference) {
        return reply.code(409).send({
          error: 'payment_reference_missing',
          message: 'This clinic application has no Paystack reference to verify.',
        });
      }
      try {
        return await app.subscriptionService.verifyApplicationPayment({
          applicationId: application.application_id,
          clinicId: application.clinic_id,
          reference: application.payment_reference,
          ipAddress: request.ip,
        });
      } catch (error) {
        return reply.code(error.statusCode ?? 400).send({
          error: error.code ?? 'payment_reconciliation_failed',
          message: error.message,
        });
      }
    },
  );

  app.post(
    '/api/v1/platform/clinics/:clinicId/deletion-requests',
    {
      config: { rateLimit: { max: 5, timeWindow: '1 hour' } },
      preHandler: [
        authenticate,
        requirePlatformAccount,
        requirePermission(permissions.clinicsApprove),
      ],
    },
    async (request, reply) => {
      if (request.auth.accountType !== 'PlatformOwner') {
        return reply.code(403).send({
          error: 'clinic_deletion_forbidden',
          message: 'Only the Platform Owner can request mutual clinic deletion.',
        });
      }
      const parsed = clinicDeletionRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'validation_error',
          message: 'Provide a short reason for the mutual deletion request.',
        });
      }
      try {
        return {
          deletionRequest: await app.clinicDeletionService.requestDeletion({
            clinicId: request.params.clinicId,
            actorUserId: request.auth.userId,
            sessionId: request.auth.sessionId,
            ipAddress: request.ip,
            reason: parsed.data.reason,
          }),
        };
      } catch (error) {
        const failure = clinicDeletionErrorResponse(
          error,
          'clinic_deletion_request_failed',
        );
        if (!failure.known) {
          request.log.error(
            { err: error, clinicId: request.params.clinicId },
            'Clinic deletion request failed',
          );
        }
        return reply.code(failure.statusCode).send({
          error: failure.code,
          message: failure.message,
        });
      }
    },
  );

  app.post(
    '/api/v1/platform/clinics/:clinicId/deletion-requests/:requestId/confirm',
    {
      config: { rateLimit: { max: 10, timeWindow: '15 minutes' } },
      preHandler: [
        authenticate,
        requirePlatformAccount,
        requirePermission(permissions.clinicsApprove),
      ],
    },
    async (request, reply) => {
      if (request.auth.accountType !== 'PlatformOwner') {
        return reply.code(403).send({
          error: 'clinic_deletion_forbidden',
          message: 'Only the Platform Owner can confirm mutual clinic deletion.',
        });
      }
      const parsed = clinicDeletionConfirmationSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: 'validation_error',
          message: 'Enter the six-digit code sent to the clinic Account Email.',
        });
      }
      try {
        return {
          deletion: await app.clinicDeletionService.confirmDeletion({
            clinicId: request.params.clinicId,
            requestId: request.params.requestId,
            code: parsed.data.code,
            actorUserId: request.auth.userId,
            sessionId: request.auth.sessionId,
            ipAddress: request.ip,
          }),
        };
      } catch (error) {
        const failure = clinicDeletionErrorResponse(
          error,
          'clinic_deletion_confirmation_failed',
        );
        if (!failure.known) {
          request.log.error(
            { err: error, clinicId: request.params.clinicId },
            'Clinic deletion confirmation failed',
          );
        }
        return reply.code(failure.statusCode).send({
          error: failure.code,
          message: failure.message,
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
    preHandler: [authenticate, requirePlatformOwner],
  }, async (request, reply) => {
    const parsed = userStatusSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Select a valid account status.' });
    }
    try {
      const updated = await withTenantTransaction(app.pool, { isPlatformOwner: true }, async (client) => {
      const previous = (await client.query(
        'SELECT user_id, clinic_id, full_name, account_type, status FROM users WHERE user_id = $1 AND deleted_at IS NULL FOR UPDATE',
        [request.params.userId],
      )).rows[0];
      if (!previous) return null;
      if (previous.account_type === 'PlatformOwner') {
        const count = await client.query("SELECT count(*)::int AS count FROM users WHERE account_type = 'PlatformOwner' AND status = 'Active' AND deleted_at IS NULL");
        assertPlatformOwnerStatusChange({
          target: previous,
          actingUserId: request.auth.userId,
          nextStatus: parsed.data.status,
          activeOwnerCount: count.rows[0].count,
        });
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
    } catch (error) {
      if (error.code === 'platform_owner_self_lockout' || error.code === 'platform_owner_last_active') {
        return reply.code(409).send({ error: error.code, message: error.message });
      }
      throw error;
    }
  });
}

export function platformUserStatusError(code, message) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = 409;
  return error;
}

export function assertPlatformOwnerStatusChange({
  target,
  actingUserId,
  nextStatus,
  activeOwnerCount,
}) {
  if (target.status !== 'Active' || nextStatus === 'Active') return;
  if (target.user_id === actingUserId) {
    throw platformUserStatusError(
      'platform_owner_self_lockout',
      'A Platform Owner cannot suspend or deactivate their own account.',
    );
  }
  if (Number(activeOwnerCount) <= 1) {
    throw platformUserStatusError(
      'platform_owner_last_active',
      'At least one active Platform Owner account must remain.',
    );
  }
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

export function createClinicApplicationDraftToken(app, application) {
  const ttlMinutes =
    Number(app.environment.REGISTRATION_DRAFT_TOKEN_TTL_MINUTES) || 10080;
  return app.jwt.sign(
    {
      scope: clinicApplicationDraftScope,
      applicationId: application.applicationId,
      clinicId: application.clinicId,
      accountEmail: String(application.accountEmail).trim().toLowerCase(),
      nonce: randomUUID(),
    },
    { expiresIn: ttlMinutes * 60 },
  );
}

function verifyClinicApplicationDraftToken(app, token, applicationId) {
  try {
    const access = app.jwt.verify(token);
    if (
      access.scope !== clinicApplicationDraftScope ||
      access.applicationId !== applicationId ||
      typeof access.clinicId !== 'string' ||
      typeof access.accountEmail !== 'string'
    ) {
      return null;
    }
    return access;
  } catch (_) {
    return null;
  }
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

async function requirePlatformOwner(request, reply) {
  if (request.auth?.accountType !== 'PlatformOwner') {
    return reply.code(403).send({
      error: 'forbidden',
      message: 'Platform Owner authorization is required.',
    });
  }
}

const safeClinicDeletionErrorCodes = new Set([
  'clinic_not_found',
  'clinic_deletion_email_missing',
  'clinic_deletion_email_unavailable',
  'clinic_deletion_email_failed',
  'clinic_deletion_request_not_found',
  'clinic_deletion_request_unavailable',
  'clinic_deletion_code_expired',
  'clinic_deletion_attempts_exhausted',
  'clinic_deletion_code_invalid',
]);

export function clinicDeletionErrorResponse(error, fallbackCode) {
  if (safeClinicDeletionErrorCodes.has(error?.code)) {
    return {
      known: true,
      statusCode: Number.isInteger(error.statusCode)
        ? error.statusCode
        : 400,
      code: error.code,
      message: error.message,
    };
  }
  return {
    known: false,
    statusCode: 503,
    code: fallbackCode,
    message: 'Deletion service is temporarily unavailable.',
  };
}

function platformListValidationError(reply) {
  return reply.code(400).send({
    error: 'validation_error',
    message: 'The Platform Owner list request is invalid.',
  });
}

export function platformEmailStatus({
  configured,
  failures = 0,
  submissions = 0,
  latestState,
}) {
  if (!configured) return 'Not configured';
  if (Number(failures) > 0 || latestState === 'email_failed') {
    return 'Attention required';
  }
  if (Number(submissions) > 0) return 'Operational';
  return 'Configured';
}

export async function queryPlatformSubscriptions(
  client,
  { page = 1, pageSize = 25, search, status } = {},
) {
  const limit = Math.min(100, Math.max(1, Number(pageSize) || 25));
  const offset = (Math.max(1, Number(page) || 1) - 1) * limit;
  const parameters = [];
  const clauses = ['c.deleted_at IS NULL'];
  if (search) {
    parameters.push(`%${String(search).trim()}%`);
    clauses.push(
      `(c.name ILIKE $${parameters.length} OR c.email::text ILIKE $${parameters.length})`,
    );
  }
  if (status) {
    parameters.push(String(status));
    clauses.push(`coalesce(s.status, 'Pending') ILIKE $${parameters.length}`);
  }
  parameters.push(limit, offset);
  const records = await client.query(
    `WITH latest_subscription AS (
       SELECT DISTINCT ON (clinic_id)
              clinic_id, subscription_id, plan, status, billing_cycle,
              current_period_start, current_period_ends_at, next_billing_date,
              cancel_at_period_end, updated_at
         FROM subscriptions
        ORDER BY clinic_id, updated_at DESC, created_at DESC
     )
     SELECT c.clinic_id, c.name AS clinic_name, c.email,
            c.subscription_plan AS clinic_plan,
            s.subscription_id, coalesce(s.plan, c.subscription_plan) AS plan,
            coalesce(s.status, 'Pending') AS status,
            coalesce(s.billing_cycle, 'monthly') AS billing_cycle,
            s.current_period_start, s.current_period_ends_at,
            s.next_billing_date, coalesce(s.cancel_at_period_end, false)
              AS cancel_at_period_end,
            s.updated_at, count(*) OVER()::int AS total_count
       FROM clinics c
       LEFT JOIN latest_subscription s ON s.clinic_id = c.clinic_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY c.name ASC, c.clinic_id ASC
      LIMIT $${parameters.length - 1} OFFSET $${parameters.length}`,
    parameters,
  );
  const summary = (
    await client.query(
      `WITH latest_subscription AS (
         SELECT DISTINCT ON (clinic_id)
                clinic_id, status, current_period_ends_at
           FROM subscriptions
          ORDER BY clinic_id, updated_at DESC, created_at DESC
       )
       SELECT count(*) FILTER (WHERE status = 'Active')::int AS active,
              count(*) FILTER (
                WHERE current_period_ends_at >= now()
                  AND current_period_ends_at < now() + interval '30 days'
              )::int AS expiring,
              count(*) FILTER (WHERE status = 'Expired')::int AS expired,
              count(*) FILTER (WHERE status IN ('Past Due', 'Pending Payment'))::int
                AS payment_issues,
              (SELECT coalesce(sum(amount_minor), 0)::bigint
                 FROM subscription_payment_transactions
                WHERE ${platformLivePaymentClause}
                  AND paid_at >= date_trunc('month', now())
                  AND paid_at < date_trunc('month', now()) + interval '1 month')
                AS monthly_revenue_minor
         FROM latest_subscription`,
    )
  ).rows[0];
  const payments = await client.query(
    `SELECT p.payment_transaction_id, p.clinic_id, c.name AS clinic_name,
            p.reference, p.gateway, p.plan_code, p.billing_cycle,
            p.amount_minor, p.currency, p.status, p.payment_channel,
            p.paid_at, p.created_at,
            coalesce(p.gateway_response_summary->>'mode', 'unknown') AS mode
       FROM subscription_payment_transactions p
       JOIN clinics c ON c.clinic_id = p.clinic_id
      WHERE c.deleted_at IS NULL
      ORDER BY coalesce(p.paid_at, p.created_at) DESC
      LIMIT 100`,
  );
  return {
    page: Math.max(1, Number(page) || 1),
    pageSize: limit,
    total: records.rows[0]?.total_count ?? 0,
    hasNextPage:
      offset + records.rows.length < (records.rows[0]?.total_count ?? 0),
    summary: {
      active: summary.active,
      expiring: summary.expiring,
      expired: summary.expired,
      paymentIssues: summary.payment_issues,
      monthlyRevenueMinor: Number(summary.monthly_revenue_minor),
    },
    items: records.rows.map((row) => ({
      clinicId: row.clinic_id,
      clinicName: row.clinic_name,
      email: row.email,
      subscriptionId: row.subscription_id,
      plan: row.plan,
      status: row.status,
      billingCycle: row.billing_cycle,
      currentPeriodStart: row.current_period_start,
      currentPeriodEnd: row.current_period_ends_at,
      nextBillingDate: row.next_billing_date,
      cancelAtPeriodEnd: row.cancel_at_period_end,
      updatedAt: row.updated_at,
    })),
    payments: payments.rows.map((row) => ({
      paymentId: row.payment_transaction_id,
      clinicId: row.clinic_id,
      clinicName: row.clinic_name,
      reference: row.reference,
      gateway: row.gateway,
      plan: row.plan_code,
      billingCycle: row.billing_cycle,
      amountMinor: Number(row.amount_minor),
      currency: row.currency,
      status: row.status,
      channel: row.payment_channel,
      mode: row.mode,
      paidAt: row.paid_at,
      createdAt: row.created_at,
    })),
  };
}

export async function queryPlatformUsers(
  client,
  { page = 1, pageSize = 25, search, status } = {},
) {
  const limit = Math.min(100, Math.max(1, Number(pageSize) || 25));
  const offset = (Math.max(1, Number(page) || 1) - 1) * limit;
  const parameters = [];
  const clauses = [
    "u.deleted_at IS NULL",
    "u.account_type IN ('PlatformOwner', 'PlatformAdministrator')",
  ];
  if (search) {
    parameters.push(`%${String(search).trim()}%`);
    clauses.push(
      `(u.full_name ILIKE $${parameters.length} OR u.email::text ILIKE $${parameters.length})`,
    );
  }
  if (status) {
    parameters.push(String(status));
    clauses.push(`u.status::text ILIKE $${parameters.length}`);
  }
  parameters.push(limit, offset);
  const result = await client.query(
    `SELECT u.user_id, u.full_name, u.email, u.phone, u.account_type,
            u.status, u.email_verified_at, u.last_login_at, u.created_at,
            count(*) OVER()::int AS total_count
       FROM users u
      WHERE ${clauses.join(' AND ')}
      ORDER BY u.created_at DESC, u.user_id DESC
      LIMIT $${parameters.length - 1} OFFSET $${parameters.length}`,
    parameters,
  );
  return {
    page: Math.max(1, Number(page) || 1),
    pageSize: limit,
    total: result.rows[0]?.total_count ?? 0,
    items: result.rows.map((row) => ({
      userId: row.user_id,
      fullName: row.full_name,
      email: row.email,
      phone: row.phone,
      accountType: row.account_type,
      status: row.status,
      emailVerifiedAt: row.email_verified_at,
      lastLoginAt: row.last_login_at,
      createdAt: row.created_at,
    })),
  };
}

export async function queryPlatformAuditLogs(
  client,
  { page = 1, pageSize = 25, search, status, action, success } = {},
) {
  const limit = Math.min(100, Math.max(1, Number(pageSize) || 25));
  const offset = (Math.max(1, Number(page) || 1) - 1) * limit;
  const parameters = [];
  const clauses = ['1 = 1'];
  if (search) {
    parameters.push(`%${String(search).trim()}%`);
    clauses.push(
      `(a.action ILIKE $${parameters.length} OR a.target_type ILIKE $${parameters.length} OR u.full_name ILIKE $${parameters.length} OR c.name ILIKE $${parameters.length})`,
    );
  }
  if (status) {
    parameters.push(String(status));
    clauses.push(`a.target_type ILIKE $${parameters.length}`);
  }
  if (action) {
    parameters.push(String(action));
    clauses.push(`a.action ILIKE $${parameters.length}`);
  }
  if (success != null) {
    parameters.push(success === 'true');
    clauses.push(`a.success = $${parameters.length}`);
  }
  parameters.push(limit, offset);
  const result = await client.query(
    `SELECT a.audit_id, a.clinic_id, c.name AS clinic_name,
            a.acting_user_id, u.full_name AS actor_name,
            a.target_type, a.target_id, a.action, a.previous_summary,
            a.new_summary, a.created_at, a.success, a.reason,
            count(*) OVER()::int AS total_count
       FROM audit_logs a
       LEFT JOIN users u ON u.user_id = a.acting_user_id
       LEFT JOIN clinics c ON c.clinic_id = a.clinic_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY a.created_at DESC, a.audit_id DESC
      LIMIT $${parameters.length - 1} OFFSET $${parameters.length}`,
    parameters,
  );
  return {
    page: Math.max(1, Number(page) || 1),
    pageSize: limit,
    total: result.rows[0]?.total_count ?? 0,
    items: result.rows.map((row) => ({
      auditId: row.audit_id,
      clinicId: row.clinic_id,
      clinicName: row.clinic_name,
      actingUserId: row.acting_user_id,
      actorName: row.actor_name,
      targetType: row.target_type,
      targetId: row.target_id,
      action: row.action,
      previousSummary: row.previous_summary,
      newSummary: row.new_summary,
      createdAt: row.created_at,
      success: row.success,
      reason: row.reason,
    })),
  };
}

export async function queryPlatformNotifications(client) {
  const result = await client.query(
    `SELECT * FROM (
       SELECT 'clinic:' || c.clinic_id::text AS id,
              'Clinic application requires review' AS title,
              c.name || ' is waiting for Platform Owner review.' AS message,
              'warning' AS severity,
              '/platform/clinics/' || c.clinic_id::text AS route,
              c.created_at
         FROM clinics c
        WHERE c.deleted_at IS NULL
          AND lower(c.status) IN ('registrationdraft', 'pending', 'pendingapproval')
       UNION ALL
       SELECT 'email:' || t.token_id::text,
              'Activation email submission failed',
              coalesce(c.name, 'A clinic') || ' needs activation email attention.',
              'error', '/platform/email', t.created_at
         FROM activation_tokens t
         LEFT JOIN clinics c ON c.clinic_id = t.clinic_id
        WHERE t.delivery_method = 'email_failed'
          AND t.created_at >= now() - interval '30 days'
       UNION ALL
       SELECT 'subscription:' || s.subscription_id::text,
              'Subscription expired',
              c.name || ' has an expired subscription.',
              'warning', '/platform/subscriptions?status=Expired', s.updated_at
         FROM subscriptions s
         JOIN clinics c ON c.clinic_id = s.clinic_id
        WHERE s.status = 'Expired' AND c.deleted_at IS NULL
     ) notification
     ORDER BY created_at DESC
     LIMIT 100`,
  );
  return {
    supportsReadState: false,
    items: result.rows.map((row) => ({
      id: row.id,
      title: row.title,
      message: row.message,
      severity: row.severity,
      route: row.route,
      createdAt: row.created_at,
    })),
  };
}

export async function queryPlatformOperations(client) {
  return (
    await client.query(
      `SELECT
        count(*) FILTER (
          WHERE delivery_method IN ('email', 'email_submitted', 'delivered')
            AND created_at >= now() - interval '24 hours'
        )::int AS recent_email_submissions,
        count(*) FILTER (
          WHERE delivery_method = 'email_failed'
            AND created_at >= now() - interval '24 hours'
        )::int AS recent_email_failures,
        (SELECT delivery_method FROM activation_tokens
          WHERE delivery_method IS NOT NULL
          ORDER BY created_at DESC LIMIT 1) AS latest_email_state,
        (SELECT max(created_at) FROM activation_tokens
          WHERE delivery_method IS NOT NULL) AS last_email_attempt_at,
        (SELECT count(*)::int FROM patients
          WHERE deleted_at IS NULL AND profile_photo_path IS NOT NULL)
          AS patient_photo_count,
        (SELECT count(*)::int FROM inventory_products
          WHERE deleted_at IS NULL AND image_path IS NOT NULL)
          AS inventory_image_count,
        ((SELECT count(*) FROM patients
            WHERE deleted_at IS NULL AND profile_photo_path IS NOT NULL)
          + (SELECT count(*) FROM inventory_products
            WHERE deleted_at IS NULL AND image_path IS NOT NULL))::int
          AS storage_object_count
       FROM activation_tokens`,
    )
  ).rows[0];
}

export async function queryPlatformClinics(
  client,
  {
    status,
    search,
    paymentStatus,
    subscriptionPlan,
    sort = 'newest',
    limit = 25,
    offset = 0,
  } = {},
) {
  const pageSize = Math.min(100, Math.max(1, Number(limit) || 25));
  const parameters = [];
  const clauses = ['c.deleted_at IS NULL'];
  if (status) {
    const normalizedStatus = String(status)
      .toLowerCase()
      .replaceAll(/[^a-z]/g, '');
    parameters.push(
      normalizedStatus === 'pending'
        ? ['registrationdraft', 'pending', 'pendingapproval']
        : normalizedStatus === 'awaitingpayment'
          ? ['registrationdraft']
          : [String(status).toLowerCase()],
    );
    clauses.push(`lower(c.status) = ANY($${parameters.length}::text[])`);
  }
  const normalizedSearch = String(search ?? '').trim();
  if (normalizedSearch) {
    parameters.push(`%${normalizedSearch}%`);
    clauses.push(`(
      c.name ILIKE $${parameters.length}
      OR COALESCE(a.administrator_email::text, a.clinic_email::text, c.email::text, '')
         ILIKE $${parameters.length}
      OR COALESCE(a.application_reference, '') ILIKE $${parameters.length}
      OR COALESCE(c.city, '') ILIKE $${parameters.length}
    )`);
  }
  if (paymentStatus) {
    parameters.push(String(paymentStatus).toLowerCase());
    clauses.push(
      `lower(COALESCE(a.payment_status, 'Pending')) = $${parameters.length}`,
    );
  }
  if (subscriptionPlan) {
    parameters.push(String(subscriptionPlan).toLowerCase());
    clauses.push(`lower(c.subscription_plan) = $${parameters.length}`);
  }
  const whereClause = clauses.join('\n AND ');
  const total = (
    await client.query(
      `SELECT count(*)::int AS count
         FROM clinics c
         ${platformClinicLateralJoins()}
        WHERE ${whereClause}`,
      parameters,
    )
  ).rows[0].count;
  parameters.push(pageSize, Math.max(0, Number(offset) || 0));
  const orderBy = switchPlatformClinicSort(sort);
  const rows = await client.query(
    `${platformClinicSelect()}
      WHERE ${whereClause}
      ORDER BY ${orderBy}
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
           a.application_id, a.application_reference,
           a.status AS application_status, a.payment_status,
           a.payment_reference, a.administrator_name,
           a.administrator_phone, a.professional_title,
           COALESCE(a.administrator_email, a.clinic_email, c.email)
             AS account_email,
           a.submitted_at AS application_submitted_at,
           p.status AS transaction_status,
           p.reference AS verified_payment_reference,
           p.amount_minor AS payment_amount_minor,
           p.currency AS payment_currency,
           p.billing_cycle AS payment_billing_cycle,
           p.paid_at AS payment_paid_at,
           p.gateway_response_summary AS payment_summary,
           s.status AS subscription_status,
           (SELECT count(*)::int FROM users u
             WHERE u.clinic_id = c.clinic_id AND u.deleted_at IS NULL) AS user_count,
           (SELECT count(*)::int FROM patients p
             WHERE p.clinic_id = c.clinic_id AND p.deleted_at IS NULL) AS patient_count
      FROM clinics c
      ${platformClinicLateralJoins()}`;
}

function platformClinicLateralJoins() {
  return `
    LEFT JOIN LATERAL (
      SELECT application_id, application_reference, status, payment_status,
             payment_reference, administrator_name, administrator_email,
             administrator_phone, professional_title, clinic_email, submitted_at
        FROM clinic_applications
       WHERE clinic_id = c.clinic_id
       ORDER BY submitted_at DESC LIMIT 1
    ) a ON true
    LEFT JOIN subscription_payment_transactions p
      ON p.reference = a.payment_reference AND p.clinic_id = c.clinic_id
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
    paymentReference: row.payment_reference,
    transactionStatus: row.transaction_status,
    paymentAmountMinor: row.payment_amount_minor == null
      ? null
      : Number(row.payment_amount_minor),
    paymentCurrency: row.payment_currency,
    paymentBillingCycle: row.payment_billing_cycle,
    paymentPaidAt: row.payment_paid_at,
    paymentSummary: row.payment_summary,
    applicationStatus: row.application_status,
    applicationId: row.application_id,
    accountEmail: row.account_email,
    administratorName: row.administrator_name,
    administratorPhone: row.administrator_phone,
    professionalTitle: row.professional_title,
    applicationReference: row.application_reference,
    applicationSubmittedAt: row.application_submitted_at,
    registrationDate: row.created_at,
    updatedAt: row.updated_at,
    userCount: row.user_count,
    patientCount: row.patient_count,
  };
}

function switchPlatformClinicSort(sort) {
  return {
    oldest: 'c.created_at ASC, c.clinic_id ASC',
    name: 'lower(c.name) ASC, c.clinic_id ASC',
    updated: 'c.updated_at DESC, c.clinic_id DESC',
  }[String(sort).toLowerCase()] ?? 'c.created_at DESC, c.clinic_id DESC';
}

export function normalizeClinicStatus(status) {
  const normalized = String(status).toLowerCase();
  if (normalized === 'registrationdraft') {
    return 'Awaiting Payment';
  }
  return normalized === 'pendingapproval' ? 'Pending' : status;
}

async function assertClinicPaymentAllowsActivation(
  client,
  { clinicId, previousStatus, allowTestPayment },
) {
  const application = (
    await client.query(
      `SELECT a.payment_status, a.payment_reference,
              p.status AS transaction_status
         FROM clinic_applications a
         LEFT JOIN subscription_payment_transactions p
           ON p.reference = a.payment_reference
          AND p.clinic_id = a.clinic_id
        WHERE a.clinic_id = $1
        ORDER BY a.submitted_at DESC
        LIMIT 1
        FOR UPDATE OF a`,
      [clinicId],
    )
  ).rows[0];
  const acceptedPaymentStatuses = allowTestPayment
    ? new Set(['Paid', 'TestVerified'])
    : new Set(['Paid']);
  if (
    application?.transaction_status === 'Successful' &&
    acceptedPaymentStatuses.has(application.payment_status)
  ) {
    return;
  }

  if (String(previousStatus).toLowerCase() === 'suspended') {
    const historicalPayment = (
      await client.query(
        `SELECT 1
           FROM subscription_payment_transactions
          WHERE clinic_id = $1 AND status = 'Successful'
          LIMIT 1`,
        [clinicId],
      )
    ).rows[0];
    if (historicalPayment) return;
  }

  const error = new Error(
    application?.payment_reference
      ? 'Paystack payment has not been verified for this clinic application. Reconcile payment before approval.'
      : 'This clinic application has no verified payment and cannot be approved.',
  );
  error.code = 'payment_not_verified';
  error.statusCode = 409;
  throw error;
}
