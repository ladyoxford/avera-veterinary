import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { buildApp } from '../src/app.js';
import { normalizeClinicStatus } from '../src/routes/platform-routes.js';

const migration = fs.readFileSync(
  new URL('../migrations/008_platform_clinic_profiles.sql', import.meta.url),
  'utf8',
);

test('platform clinic migration preserves production contact and application data', () => {
  assert.match(migration, /ADD COLUMN IF NOT EXISTS email CITEXT/);
  assert.match(migration, /application_reference TEXT/);
  assert.match(migration, /administrator_email CITEXT/);
  assert.match(migration, /clinics_platform_status_created_idx/);
});

test('PendingApproval is normalized for the Flutter Pending filter', () => {
  assert.equal(normalizeClinicStatus('PendingApproval'), 'Pending');
  assert.equal(normalizeClinicStatus('Pending'), 'Pending');
  assert.equal(normalizeClinicStatus('Active'), 'Active');
});

test('clinic accounts cannot access Platform Owner clinic APIs', async (context) => {
  const pool = {
    async query(sql) {
      if (sql.includes('FROM sessions s JOIN users u')) {
        return {
          rows: [
            {
              session_id: 'session-1',
              user_id: 'user-1',
              clinic_id: 'clinic-1',
              account_type: 'ClinicAdministrator',
              status: 'Active',
              revoked_at: null,
              expires_at: new Date(Date.now() + 60_000),
              role_id: null,
            },
          ],
        };
      }
      if (sql.includes('LEFT JOIN clinic_memberships')) {
        return {
          rows: [{ membership_status: 'Active', clinic_status: 'Active' }],
        };
      }
      if (sql.includes('FROM role_permissions') || sql.includes("effect = 'restrict'")) {
        return { rows: [] };
      }
      throw new Error(`Unexpected database query: ${sql}`);
    },
  };
  const app = await buildApp({ environment: testEnvironment(), pool });
  context.after(() => app.close());
  const token = app.jwt.sign({
    userId: 'user-1',
    accountType: 'ClinicAdministrator',
    clinicId: 'clinic-1',
    sessionId: 'session-1',
  });

  const response = await app.inject({
    method: 'GET',
    url: '/api/v1/platform/clinics',
    headers: { authorization: `Bearer ${token}` },
  });

  assert.equal(response.statusCode, 403);
  assert.equal(response.json().error, 'forbidden');

  const resend = await app.inject({
    method: 'POST',
    url: '/api/v1/platform/clinics/clinic-1/administrator-activation/resend',
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(resend.statusCode, 403);
  assert.equal(resend.json().error, 'forbidden');
});

function testEnvironment() {
  return {
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
    PAYSTACK_CURRENCY: 'NGN',
    paymentCallbackUrl: 'avera://payments/callback',
    allowedOrigins: ['http://localhost'],
    ACTIVATION_TOKEN_TTL_MINUTES: 60,
    AVERA_ACTIVATION_BASE_URL: 'avera://app/activate-clinic-admin',
  };
}
