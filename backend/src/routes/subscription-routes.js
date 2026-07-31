import crypto from 'node:crypto';
import { authenticate, requirePermission } from '../middleware/auth.js';
import { permissions } from '../security/permissions.js';

export async function subscriptionRoutes(app) {
  const service = app.subscriptionService;
  const manage = [authenticate, requirePermission(permissions.subscriptionsManage)];
  const initializePaystack = async (request, reply) => {
    const { clinicId, planCode, billingCycle } = request.body ?? {};
    if (!clinicId || !canAccessClinic(request.auth, clinicId)) {
      return forbidden(reply);
    }
    return handle(reply, () =>
      service.initializeCheckout({
        auth: request.auth,
        clinicId,
        planCode,
        billingCycle,
      }),
    );
  };
  const verifyPaystack = async (request, reply) =>
    handle(reply, async () => {
      const result = await service.verifyAndApply(
        request.params.reference,
        request.auth,
      );
      if (
        !result.subscription ||
        !canAccessClinic(request.auth, result.subscription.clinicId)
      ) {
        return forbidden(reply);
      }
      return result;
    });
  const receivePaystackWebhook = async (request, reply) => {
    const rawBody = request.rawBody;
    const signature = request.headers['x-paystack-signature'];
    const secret =
      app.environment.PAYSTACK_WEBHOOK_SECRET ??
      app.environment.PAYSTACK_SECRET_KEY;
    if (!Buffer.isBuffer(rawBody) || !signature || !secret) {
      return reply.code(401).send({ error: 'invalid_signature' });
    }
    if (!verifyPaystackSignature(rawBody, signature, secret)) {
      return reply.code(401).send({ error: 'invalid_signature' });
    }
    const payloadHash = crypto.createHash('sha256').update(rawBody).digest('hex');
    try {
      await service.persistWebhook({
        event: request.body,
        rawBody,
        payloadHash,
      });
      return reply.code(200).send({ received: true });
    } catch (error) {
      request.log.error(
        { code: error.code, event: request.body?.event },
        'Paystack webhook processing failed',
      );
      return reply.code(500).send({ error: 'webhook_processing_failed' });
    }
  };

  app.get('/api/subscription/plans', { preHandler: [authenticate] }, async () => ({
    plans: await service.listPlans(),
  }));

  app.get(
    '/api/clinics/:clinicId/subscription',
    { preHandler: [authenticate] },
    async (request, reply) => {
      if (!canAccessClinic(request.auth, request.params.clinicId)) return forbidden(reply);
      return {
        subscription: await service.getClinicSubscription(
          request.auth,
          request.params.clinicId,
        ),
      };
    },
  );

  app.get(
    '/api/clinics/:clinicId/subscription/payments',
    { preHandler: manage },
    async (request, reply) => {
      if (!canAccessClinic(request.auth, request.params.clinicId)) return forbidden(reply);
      return {
        payments: await service.listPayments(
          request.auth,
          request.params.clinicId,
        ),
      };
    },
  );

  app.post('/api/subscriptions/checkout', { preHandler: manage }, initializePaystack);
  app.post(
    '/api/v1/subscriptions/payments/paystack/initialize',
    { preHandler: manage },
    initializePaystack,
  );

  app.get(
    '/api/subscriptions/payments/:reference/verify',
    { preHandler: manage },
    verifyPaystack,
  );
  app.get(
    '/api/v1/subscriptions/payments/paystack/verify/:reference',
    { preHandler: manage },
    verifyPaystack,
  );

  app.post(
    '/api/clinics/:clinicId/subscription/cancel-renewal',
    { preHandler: manage },
    async (request, reply) => {
      if (!canAccessClinic(request.auth, request.params.clinicId)) return forbidden(reply);
      return handle(reply, async () => ({
        subscription: await service.cancelRenewal(
          request.auth,
          request.params.clinicId,
        ),
      }));
    },
  );

  app.post(
    '/api/clinics/:clinicId/subscription/reactivate',
    { preHandler: manage },
    async (request, reply) => {
      if (!canAccessClinic(request.auth, request.params.clinicId)) return forbidden(reply);
      return handle(reply, async () => ({
        subscription: await service.reactivateRenewal(
          request.auth,
          request.params.clinicId,
        ),
      }));
    },
  );

  app.post(
    '/api/clinics/:clinicId/subscription/change-plan',
    { preHandler: manage },
    async (request, reply) => {
      if (!canAccessClinic(request.auth, request.params.clinicId)) return forbidden(reply);
      return handle(reply, () =>
        service.changePlan(
          request.auth,
          request.params.clinicId,
          request.body?.planCode,
          request.body?.billingCycle,
        ),
      );
    },
  );

  app.post(
    '/api/payments/paystack/webhook',
    { config: { rateLimit: { max: 300, timeWindow: '1 minute' } } },
    receivePaystackWebhook,
  );
  app.post(
    '/api/v1/subscriptions/payments/paystack/webhook',
    { config: { rateLimit: { max: 300, timeWindow: '1 minute' } } },
    receivePaystackWebhook,
  );
}

export function verifyPaystackSignature(rawBody, signature, secret) {
  if (!Buffer.isBuffer(rawBody) || !signature || !secret) return false;
  const expected = crypto
    .createHmac('sha512', secret)
    .update(rawBody)
    .digest('hex');
  const supplied = Buffer.from(String(signature), 'utf8');
  const calculated = Buffer.from(expected, 'utf8');
  return (
    supplied.length === calculated.length &&
    crypto.timingSafeEqual(supplied, calculated)
  );
}

function canAccessClinic(auth, clinicId) {
  return (
    auth.clinicId === clinicId ||
    auth.accountType === 'PlatformOwner' ||
    auth.accountType === 'PlatformAdministrator'
  );
}

function forbidden(reply) {
  return reply.code(403).send({
    error: 'forbidden',
    message: 'You cannot manage subscriptions for this clinic.',
  });
}

async function handle(reply, action) {
  try {
    return await action();
  } catch (error) {
    if (error.statusCode) {
      return reply.code(error.statusCode).send({
        error: error.code ?? 'subscription_error',
        message: error.message,
      });
    }
    throw error;
  }
}
