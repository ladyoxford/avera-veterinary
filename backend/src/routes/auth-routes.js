import { z } from 'zod';
import { authenticate } from '../middleware/auth.js';

export const signInSchema = z.object({ email: z.string().email(), password: z.string().min(1), deviceName: z.string().max(120).optional(), platform: z.string().max(60).optional() });
const refreshSchema = z.object({ refreshToken: z.string().min(40) });
const passwordSchema = z.object({ currentPassword: z.string().min(1), newPassword: z.string().min(12) });
const passwordResetRequestSchema = z.object({
  email: z.string().trim().email().max(254),
});
const passwordResetSchema = z.object({
  token: z.string().min(32).max(512),
  password: z.string().min(12).max(256),
  confirmPassword: z.string().min(12).max(256),
});
const activationTokenSchema = z.object({ token: z.string().min(32).max(512) });
const activationSchema = activationTokenSchema.extend({
  password: z.string().min(12).max(256),
  confirmPassword: z.string().min(12).max(256),
});
export async function authRoutes(app) {
  const signInRateLimit = app.environment.NODE_ENV === 'test' ? 100 : 5;
  app.post('/api/v1/auth/sign-in', { config: { rateLimit: { max: signInRateLimit, timeWindow: '15 minutes' } } }, async (request, reply) => {
    const parsed = signInSchema.safeParse(request.body);
    if (!parsed.success) {
      if (app.environment.NODE_ENV === 'development') {
        request.log.warn({ issues: parsed.error.issues.map((issue) => ({ path: issue.path.join('.'), code: issue.code })) }, 'Development sign-in validation failure');
      }
      return reply.code(400).send({ error: 'validation_error', message: 'Provide a valid email and password.' });
    }
    const result = await app.authService.signIn({ ...parsed.data, ipAddress: request.ip, userAgent: request.headers['user-agent'] });
    if (!result.ok) {
      if (app.environment.NODE_ENV === 'development') {
        request.log.warn({ email: parsed.data.email.toLowerCase(), reason: result.internalReason }, 'Development sign-in rejected');
      }
      return reply.code(result.status).send({ error: result.code, message: result.message });
    }
    return reply.code(200).send(result.session);
  });

  app.post('/api/v1/auth/forgot-password', {
    config: { rateLimit: { max: 5, timeWindow: '1 hour' } },
  }, async (request, reply) => {
    const parsed = passwordResetRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'validation_error',
        message: 'Provide a valid account email.',
      });
    }
    try {
      await app.passwordResetService.request({
        email: parsed.data.email,
        ipAddress: request.ip,
        userAgent: request.headers['user-agent'],
      });
      return reply.code(202).send({
        accepted: true,
        message: 'If an eligible AVERA account uses that email, a reset link has been sent.',
      });
    } catch (error) {
      return reply.code(error.statusCode ?? 503).send({
        error: error.code ?? 'password_reset_unavailable',
        message: error.message,
      });
    }
  });

  app.post('/api/v1/auth/reset-password', {
    config: { rateLimit: { max: 10, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const parsed = passwordResetSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'validation_error',
        message: 'Provide a valid reset token and matching strong passwords.',
      });
    }
    try {
      return await app.passwordResetService.reset({
        rawToken: parsed.data.token,
        password: parsed.data.password,
        confirmPassword: parsed.data.confirmPassword,
        ipAddress: request.ip,
      });
    } catch (error) {
      return reply.code(error.statusCode ?? 400).send({
        error: error.code ?? 'password_reset_failed',
        message: error.message,
      });
    }
  });

  app.post('/api/v1/auth/clinic-administrator-activation/status', {
    config: { rateLimit: { max: 20, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const parsed = activationTokenSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'A valid activation token is required.' });
    }
    try {
      return { activation: await app.activationService.inspect(parsed.data.token) };
    } catch (error) {
      return reply.code(error.statusCode ?? 400).send({ error: error.code ?? 'activation_invalid', message: error.message });
    }
  });

  app.post('/api/v1/auth/activate-clinic-administrator', {
    config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const parsed = activationSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Provide a valid token and matching strong passwords.' });
    }
    try {
      return await app.activationService.activate({
        rawToken: parsed.data.token,
        password: parsed.data.password,
        confirmPassword: parsed.data.confirmPassword,
        ipAddress: request.ip,
      });
    } catch (error) {
      return reply.code(error.statusCode ?? 400).send({ error: error.code ?? 'activation_failed', message: error.message });
    }
  });

  app.post('/api/v1/auth/staff-activation/status', {
    config: { rateLimit: { max: 20, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const parsed = activationTokenSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'A valid activation token is required.' });
    try {
      return { activation: await app.activationService.inspectStaff(parsed.data.token) };
    } catch (error) {
      return reply.code(error.statusCode ?? 400).send({ error: error.code ?? 'activation_invalid', message: error.message });
    }
  });

  app.post('/api/v1/auth/activate-staff', {
    config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const parsed = activationSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Provide a valid token and matching strong passwords.' });
    try {
      return await app.activationService.activateStaff({
        rawToken: parsed.data.token, password: parsed.data.password,
        confirmPassword: parsed.data.confirmPassword, ipAddress: request.ip,
      });
    } catch (error) {
      return reply.code(error.statusCode ?? 400).send({ error: error.code ?? 'activation_failed', message: error.message });
    }
  });

  app.post('/api/v1/auth/refresh', async (request, reply) => {
    const parsed = refreshSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'A refresh token is required.' });
    const result = await app.authService.refresh(parsed.data.refreshToken, request.ip);
    if (result?.restricted) return reply.code(403).send({ error: result.code, message: 'Account access is restricted.' });
    if (!result) return reply.code(401).send({ error: 'invalid_session', message: 'The session is no longer valid.' });
    return result;
  });

  app.post('/api/v1/auth/sign-out', { preHandler: authenticate }, async (request, reply) => {
    await app.authService.signOut(request.auth.sessionId, request.auth.userId);
    return reply.code(204).send();
  });

  app.post('/api/v1/auth/sign-out-all', { preHandler: authenticate }, async (request, reply) => {
    await app.authService.signOut(request.auth.sessionId, request.auth.userId, true);
    return reply.code(204).send();
  });

  app.get('/api/v1/auth/me', { preHandler: authenticate }, async (request) => {
    const result = await app.pool.query('SELECT * FROM users WHERE user_id = $1', [request.auth.userId]);
    return { user: await app.authService.currentUser(result.rows[0], request.auth.permissions) };
  });

  app.get('/api/v1/auth/sessions', { preHandler: authenticate }, async (request) => ({ sessions: await app.authService.sessions(request.auth.userId) }));

  app.delete('/api/v1/auth/sessions/:sessionId', { preHandler: authenticate }, async (request, reply) => {
    await app.authService.signOut(request.params.sessionId, request.auth.userId);
    return reply.code(204).send();
  });

  app.post('/api/v1/auth/change-password', { preHandler: authenticate }, async (request, reply) => {
    const parsed = passwordSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'A current and strong new password are required.' });
    try {
      await app.authService.changePassword({ user: request.auth, sessionId: request.auth.sessionId, ...parsed.data, ipAddress: request.ip });
      return reply.code(204).send();
    } catch (error) {
      return reply.code(400).send({ error: 'password_change_failed', message: error.message });
    }
  });
}
