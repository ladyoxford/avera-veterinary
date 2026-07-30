import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import test from 'node:test';
import { PaystackSubscriptionGateway } from '../src/payments/paystack-subscription-gateway.js';
import {
  createPaymentReference,
  validateVerifiedPayment,
} from '../src/services/subscription-service.js';
import { verifyPaystackSignature } from '../src/routes/subscription-routes.js';
import { buildApp } from '../src/app.js';

const migration = fs.readFileSync(
  new URL('../migrations/006_subscription_payments.sql', import.meta.url),
  'utf8',
);

test('subscription payment migration enforces unique references and webhook identities', () => {
  assert.match(migration, /reference TEXT NOT NULL UNIQUE/);
  assert.match(migration, /UNIQUE \(gateway, event_identity\)/);
  assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /subscriptions_one_current_per_clinic_idx/);
});

test('Paystack signatures require the exact raw request body', () => {
  const secret = 'test-secret';
  const raw = Buffer.from('{"event":"charge.success","data":{"id":42}}');
  const signature = crypto.createHmac('sha512', secret).update(raw).digest('hex');
  assert.equal(verifyPaystackSignature(raw, signature, secret), true);
  assert.equal(
    verifyPaystackSignature(Buffer.from('{"event":"charge.success"}'), signature, secret),
    false,
  );
  assert.equal(verifyPaystackSignature(raw, 'invalid', secret), false);
});

test('payment references are unique and do not expose secrets', () => {
  const first = createPaymentReference({
    now: 100,
    randomBytes: () => Buffer.from('0000000000000001', 'hex'),
  });
  const second = createPaymentReference({
    now: 100,
    randomBytes: () => Buffer.from('0000000000000002', 'hex'),
  });
  assert.notEqual(first, second);
  assert.match(first, /^AVERA-100-[A-F0-9]{16}$/);
});

test('payment verification rejects status, amount, currency, and reference mismatches', () => {
  const expected = {
    reference: 'AVERA-1',
    amount_minor: 250000,
    currency: 'NGN',
  };
  const valid = {
    reference: 'AVERA-1',
    status: 'success',
    amount: 250000,
    currency: 'NGN',
  };
  assert.equal(validateVerifiedPayment(expected, valid), null);
  assert.equal(
    validateVerifiedPayment(expected, { ...valid, status: 'failed' }),
    'payment_not_successful',
  );
  assert.equal(
    validateVerifiedPayment(expected, { ...valid, amount: 1 }),
    'payment_amount_mismatch',
  );
  assert.equal(
    validateVerifiedPayment(expected, { ...valid, currency: 'USD' }),
    'payment_currency_mismatch',
  );
  assert.equal(
    validateVerifiedPayment(expected, { ...valid, reference: 'OTHER' }),
    'payment_reference_mismatch',
  );
});

test('Paystack gateway sends secrets only in server Authorization header', async () => {
  let captured;
  const gateway = new PaystackSubscriptionGateway({
    secretKey: 'server-secret',
    fetchImpl: async (url, options) => {
      captured = { url, options };
      return {
        ok: true,
        async json() {
          return {
            status: true,
            data: {
              authorization_url: 'https://checkout.paystack.test/session',
              access_code: 'safe-access-code',
            },
          };
        },
      };
    },
  });
  await gateway.initializeCheckout({
    email: 'billing@avera.test',
    amountMinor: 1000,
    currency: 'NGN',
    planCode: 'PLN_test',
    reference: 'AVERA-test',
    callbackUrl: 'avera://payments/callback',
    metadata: { clinicId: 'clinic-1' },
  });
  assert.equal(captured.options.headers.Authorization, 'Bearer server-secret');
  assert.equal(captured.options.body.includes('server-secret'), false);
});

test('subscription endpoints reject unauthenticated access', async (context) => {
  const app = await buildApp({
    environment: testEnvironment(),
    pool: {
      async query() {
        throw new Error('Database should not be reached without authentication.');
      },
    },
  });
  context.after(() => app.close());
  const response = await app.inject({
    method: 'GET',
    url: '/api/subscription/plans',
  });
  assert.equal(response.statusCode, 401);
});

test('Paystack webhook endpoint rejects an invalid signature before persistence', async (context) => {
  const app = await buildApp({
    environment: testEnvironment(),
    pool: {
      async query() {
        throw new Error('Invalid webhook must not reach persistence.');
      },
    },
  });
  context.after(() => app.close());
  const response = await app.inject({
    method: 'POST',
    url: '/api/payments/paystack/webhook',
    headers: {
      'content-type': 'application/json',
      'x-paystack-signature': 'invalid',
    },
    payload: { event: 'charge.success', data: { reference: 'AVERA-test' } },
  });
  assert.equal(response.statusCode, 401);
});

function testEnvironment() {
  return {
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgres://unused:unused@localhost:5432/unused',
    JWT_ACCESS_SECRET: 'a'.repeat(32),
    JWT_REFRESH_SECRET: 'b'.repeat(32),
    ACCESS_TOKEN_TTL_SECONDS: 900,
    REFRESH_TOKEN_TTL_DAYS: 30,
    PAYSTACK_SECRET_KEY: 'test-secret',
    PAYSTACK_WEBHOOK_SECRET: 'test-secret',
    APP_PAYMENT_CALLBACK_URL: 'avera://payments/callback',
    allowedOrigins: ['http://localhost'],
  };
}
