import { z } from 'zod';
import { authenticate, requirePermission } from '../middleware/auth.js';
import { permissions } from '../security/permissions.js';

const passwordSchema = z.object({ password: z.string().min(1) });
const confirmSchema = z.object({
  setupId: z.string().uuid(),
  code: z.string().regex(/^\d{6}$/),
});
const verifySchema = z.object({
  challengeToken: z.string().min(32),
  code: z.string().regex(/^\d{6}$/).optional(),
  recoveryCode: z.string().min(8).optional(),
}).refine((value) => Boolean(value.code || value.recoveryCode));
const disableSchema = z.object({
  password: z.string().min(1),
  codeOrRecovery: z.string().min(6),
});

export async function securityRoutes(app) {
  const adminGuard = [authenticate, requirePermission(permissions.twoFactorManageSelf)];

  app.get('/api/v1/security/2fa/status', { preHandler: adminGuard }, async (request) => (
    app.mfaService.status(request.auth.userId)
  ));

  app.post('/api/v1/security/2fa/setup', { preHandler: adminGuard }, async (request, reply) => {
    const parsed = passwordSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Enter your current password.' });
    try {
      return await app.mfaService.beginSetup(request.auth, parsed.data.password);
    } catch (_) {
      return reply.code(403).send({ error: 'reauthentication_failed', message: 'Reauthentication failed.' });
    }
  });

  app.post('/api/v1/security/2fa/confirm', { preHandler: adminGuard }, async (request, reply) => {
    const parsed = confirmSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Enter the six-digit code.' });
    try {
      return { recoveryCodes: await app.mfaService.confirmSetup(request.auth, parsed.data.setupId, parsed.data.code) };
    } catch (error) {
      return reply.code(400).send({ error: 'mfa_setup_failed', message: error.message });
    }
  });

  app.post('/api/v1/security/2fa/verify', {
    config: { rateLimit: { max: 10, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const parsed = verifySchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Enter a valid verification code.' });
    try {
      return await app.mfaService.verifyLoginChallenge(
        parsed.data.challengeToken,
        parsed.data.code,
        parsed.data.recoveryCode,
        request.ip,
      );
    } catch (error) {
      if (error.code === 'ACCOUNT_SUSPENDED') {
        return reply.code(403).send({ error: 'ACCOUNT_SUSPENDED', message: 'Account access is restricted.' });
      }
      return reply.code(401).send({ error: 'invalid_mfa_code', message: 'The verification code is invalid or expired.' });
    }
  });

  app.post('/api/v1/security/2fa/disable', { preHandler: adminGuard }, async (request, reply) => {
    const parsed = disableSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Password and verification code are required.' });
    try {
      await app.mfaService.disable(request.auth, parsed.data.password, parsed.data.codeOrRecovery);
      return reply.code(204).send();
    } catch (error) {
      return reply.code(400).send({ error: 'mfa_disable_failed', message: error.message });
    }
  });

  app.post('/api/v1/security/2fa/recovery-codes/regenerate', {
    preHandler: adminGuard,
  }, async (request, reply) => {
    const parsed = disableSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'validation_error',
        message: 'Password and verification code are required.',
      });
    }
    try {
      return {
        recoveryCodes: await app.mfaService.regenerateRecoveryCodes(
          request.auth,
          parsed.data.password,
          parsed.data.codeOrRecovery,
        ),
      };
    } catch (error) {
      return reply.code(400).send({
        error: 'recovery_code_regeneration_failed',
        message: error.message,
      });
    }
  });
}
