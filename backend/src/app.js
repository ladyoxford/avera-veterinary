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

export async function buildApp({ environment = loadEnvironment(), pool } = {}) {
  const app = Fastify({ logger: { level: environment.LOG_LEVEL }, trustProxy: environment.NODE_ENV !== 'development' });
  const databasePool = pool ?? createPool(environment.DATABASE_URL);
  app.decorate('environment', environment);
  app.decorate('pool', databasePool);
  await app.register(cors, { origin: environment.allowedOrigins, credentials: false });
  await app.register(rateLimit, { global: true, max: 100, timeWindow: '1 minute' });
  await app.register(jwt, { secret: environment.JWT_ACCESS_SECRET });
  app.decorate('authService', new AuthService({ pool: databasePool, environment, app }));
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
  await app.register(platformRoutes);
  await app.register(clinicRoutes);
  await app.register(clinicalRoutes);
  await app.register(syncRoutes);
  if (!pool) app.addHook('onClose', async () => { await databasePool.end(); });
  return app;
}
