import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import { loadEnvironment } from './config/env.js';
import { createPool } from './database/pool.js';
import { AuthService } from './services/auth-service.js';
import { healthRoutes } from './routes/health-routes.js';
import { authRoutes } from './routes/auth-routes.js';
import { platformRoutes } from './routes/platform-routes.js';
import { clinicRoutes } from './routes/clinic-routes.js';
import { syncRoutes } from './routes/sync-routes.js';
import { clinicalRoutes } from './routes/clinical-routes.js';
import { subscriptionRoutes } from './routes/subscription-routes.js';
import { PaystackSubscriptionGateway } from './payments/paystack-subscription-gateway.js';
import { SubscriptionService } from './services/subscription-service.js';
import { MfaService } from './services/mfa-service.js';
import { securityRoutes } from './routes/security-routes.js';
import {
  ActivationEmailDeliveryService,
  ClinicAdministratorActivationService,
} from './services/clinic-administrator-activation-service.js';

export async function buildApp({ environment = loadEnvironment(), pool } = {}) {
  const app = Fastify({ logger: { level: environment.LOG_LEVEL }, trustProxy: environment.NODE_ENV !== 'development' });
  const databasePool = pool ?? createPool(environment.DATABASE_URL);
  app.decorate('environment', environment);
  app.decorate('pool', databasePool);
  app.removeContentTypeParser('application/json');
  app.addContentTypeParser(
    'application/json',
    { parseAs: 'buffer' },
    (request, body, done) => {
      request.rawBody = body;
      try {
        done(null, JSON.parse(body.toString('utf8')));
      } catch (error) {
        error.statusCode = 400;
        done(error);
      }
    },
  );
  await app.register(cors, { origin: environment.allowedOrigins, credentials: false });
  await app.register(rateLimit, { global: true, max: 100, timeWindow: '1 minute' });
  await app.register(jwt, { secret: environment.JWT_ACCESS_SECRET });
  const authService = new AuthService({ pool: databasePool, environment, app });
  const mfaService = new MfaService({ pool: databasePool, environment, authService });
  authService.setMfaService(mfaService);
  app.decorate('authService', authService);
  app.decorate('mfaService', mfaService);
  const activationDeliveryService = new ActivationEmailDeliveryService({
    environment,
  });
  app.decorate(
    'activationService',
    new ClinicAdministratorActivationService({
      pool: databasePool,
      environment,
      deliveryService: activationDeliveryService,
    }),
  );
  const subscriptionGateway = new PaystackSubscriptionGateway({
    secretKey: environment.PAYSTACK_SECRET_KEY,
  });
  app.decorate(
    'subscriptionService',
    new SubscriptionService({
      pool: databasePool,
      environment,
      gateway: subscriptionGateway,
    }),
  );
  app.addHook('onRequest', async (request, reply) => {
    reply.header('X-Request-Id', request.id);
    reply.header('X-Content-Type-Options', 'nosniff');
  });
  app.setErrorHandler((error, request, reply) => {
    request.log.error(error);
    reply.code(error.statusCode ?? 500).send({ error: 'internal_error', message: 'The request could not be completed.', requestId: request.id });
  });
  await app.register(healthRoutes);
  await app.register(authRoutes);
  await app.register(securityRoutes);
  await app.register(platformRoutes);
  await app.register(clinicRoutes);
  await app.register(clinicalRoutes);
  await app.register(subscriptionRoutes);
  await app.register(syncRoutes);
  if (!pool) app.addHook('onClose', async () => { await databasePool.end(); });
  return app;
}
