import assert from 'node:assert/strict';
import test from 'node:test';
import {
  decryptSecret,
  encryptSecret,
  generateRecoveryCodes,
  generateTotpSecret,
  hashRecoveryCode,
  normalizeRecoveryCode,
  verifyTotp,
} from '../src/security/mfa.js';
import { authenticator } from 'otplib';
import { buildApp } from '../src/app.js';

test('TOTP secrets are encrypted at rest and valid codes verify', () => {
  const secret = generateTotpSecret();
  const key = 'a'.repeat(64);
  const encrypted = encryptSecret(secret, key);
  assert.notEqual(encrypted, secret);
  assert.equal(encrypted.includes(secret), false);
  assert.equal(decryptSecret(encrypted, key), secret);
  assert.equal(verifyTotp(authenticator.generate(secret), secret), true);
  assert.equal(verifyTotp('00000', secret), false);
});

test('recovery codes are random, normalized and hash-only comparable', () => {
  const codes = generateRecoveryCodes();
  assert.equal(codes.length, 10);
  assert.equal(new Set(codes).size, codes.length);
  const normalized = normalizeRecoveryCode(codes[0]);
  assert.match(normalized, /^[A-F0-9]{16}$/);
  assert.equal(hashRecoveryCode(codes[0]), hashRecoveryCode(normalized));
  assert.equal(hashRecoveryCode(codes[0]).includes(normalized), false);
});

test('2FA management endpoints reject unauthenticated access', async (context) => {
  const app = await buildApp({
    environment: {
      NODE_ENV: 'test',
      LOG_LEVEL: 'silent',
      DATABASE_URL: 'postgres://unused:unused@localhost:5432/unused',
      JWT_ACCESS_SECRET: 'a'.repeat(32),
      JWT_REFRESH_SECRET: 'b'.repeat(32),
      TOTP_ENCRYPTION_KEY: 'c'.repeat(64),
      ACCESS_TOKEN_TTL_SECONDS: 900,
      REFRESH_TOKEN_TTL_DAYS: 30,
      PAYSTACK_SECRET_KEY: 'test-secret',
      PAYSTACK_WEBHOOK_SECRET: 'test-secret',
      APP_PAYMENT_CALLBACK_URL: 'avera://payments/callback',
      allowedOrigins: ['http://localhost'],
    },
    pool: {
      async query() {
        throw new Error(
          'Database should not be reached without authentication.',
        );
      },
    },
  });
  context.after(() => app.close());

  const requests = [
    { method: 'GET', url: '/api/v1/security/2fa/status' },
    { method: 'POST', url: '/api/v1/security/2fa/setup', payload: {} },
    { method: 'POST', url: '/api/v1/security/2fa/confirm', payload: {} },
    { method: 'POST', url: '/api/v1/security/2fa/disable', payload: {} },
    {
      method: 'POST',
      url: '/api/v1/security/2fa/recovery-codes/regenerate',
      payload: {},
    },
  ];
  for (const request of requests) {
    const response = await app.inject(request);
    assert.equal(response.statusCode, 401, request.url);
  }
});
