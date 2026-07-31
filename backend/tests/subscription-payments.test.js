import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import test from 'node:test';
import { PaystackSubscriptionGateway } from '../src/payments/paystack-subscription-gateway.js';
import {
  createPaymentReference,
  SubscriptionService,
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

test('checkout price and currency come from the server plan, not the client', async () => {
  const gatewayCalls = [];
  const client = transactionClient((sql) => {
    if (sql.includes('FROM plans')) {
      return {
        rows: [{
          plan_key: 'Professional',
          display_name: 'Professional',
          monthly_amount_minor: 250000,
          annual_amount_minor: 2500000,
          currency: 'NGN',
        }],
      };
    }
    if (sql.includes('FROM users')) {
      return { rows: [{ email: 'billing@clinic.test' }] };
    }
    return { rows: [] };
  });
  const service = new SubscriptionService({
    pool: transactionPool(client),
    environment: {
      PAYSTACK_CURRENCY: 'NGN',
      PAYSTACK_PROFESSIONAL_MONTHLY_PLAN_CODE: 'PLN_professional_test',
      paymentCallbackUrl: 'avera://payments/callback',
    },
    gateway: {
      configured: true,
      async initializeCheckout(input) {
        gatewayCalls.push(input);
        return {
          authorization_url: 'https://checkout.paystack.test/session',
          access_code: 'public-checkout-code',
        };
      },
    },
  });

  const checkout = await service.initializeCheckout({
    auth: {
      userId: 'user-1',
      clinicId: 'clinic-1',
      accountType: 'ClinicAdministrator',
      sessionId: 'session-1',
    },
    clinicId: 'clinic-1',
    planCode: 'Professional',
    billingCycle: 'monthly',
    amountMinor: 1,
  });

  assert.equal(gatewayCalls[0].amountMinor, 250000);
  assert.equal(gatewayCalls[0].currency, 'NGN');
  assert.equal(gatewayCalls[0].planCode, 'PLN_professional_test');
  assert.equal(JSON.stringify(checkout).includes('test-secret'), false);
  assert.equal(Object.hasOwn(checkout, 'secretKey'), false);
});

test('verified Paystack success activates exactly the referenced clinic subscription', async () => {
  const expected = pendingPayment();
  const client = transactionClient((sql) => {
    if (sql.includes('subscription_payment_transactions') && sql.includes('FOR UPDATE')) {
      return { rows: [expected] };
    }
    if (sql.includes('FROM subscriptions') && sql.includes('FOR UPDATE')) {
      return { rows: [] };
    }
    if (sql.includes('INSERT INTO subscriptions')) {
      return {
        rows: [{
          subscription_id: 'subscription-1',
          clinic_id: 'clinic-1',
          plan: 'Professional',
          status: 'Active',
          billing_cycle: 'monthly',
          gateway: 'paystack',
          current_period_start: new Date('2026-07-31T10:00:00Z'),
          current_period_ends_at: new Date('2026-08-31T10:00:00Z'),
          next_billing_date: new Date('2026-08-31T10:00:00Z'),
          cancel_at_period_end: false,
          updated_at: new Date('2026-07-31T10:00:00Z'),
        }],
      };
    }
    return { rows: [] };
  });
  const topLevelCalls = [];
  const pool = {
    ...transactionPool(client),
    async query(sql, parameters) {
      topLevelCalls.push({ sql, parameters });
      if (sql.includes('FROM subscription_payment_transactions')) {
        return { rows: [expected] };
      }
      return { rows: [] };
    },
  };
  const service = new SubscriptionService({
    pool,
    environment: {},
    gateway: {
      async verifyPayment() {
        return {
          id: 42,
          reference: expected.reference,
          status: 'success',
          amount: expected.amount_minor,
          currency: expected.currency,
          channel: 'card',
          paid_at: '2026-07-31T10:00:00Z',
          metadata: {
            clinicId: 'clinic-1',
            planCode: 'Professional',
            billingCycle: 'monthly',
          },
        };
      },
    },
  });

  const result = await service.verifyAndApply(expected.reference, {
    clinicId: 'clinic-1',
    accountType: 'ClinicAdministrator',
  });

  assert.equal(result.subscription.clinicId, 'clinic-1');
  assert.equal(result.subscription.planCode, 'Professional');
  assert.equal(result.subscription.status, 'Active');
  assert.equal(
    client.calls.filter((call) => call.sql.includes('UPDATE subscription_payment_transactions')).length,
    1,
  );
  assert.equal(
    client.calls.some((call) => call.sql.includes('UPDATE clinics SET subscription_plan')),
    true,
  );
});

test('mismatched Paystack verification never activates a subscription', async () => {
  const expected = pendingPayment();
  const topLevelCalls = [];
  let transactionOpened = false;
  const service = new SubscriptionService({
    pool: {
      async query(sql, parameters) {
        topLevelCalls.push({ sql, parameters });
        if (sql.includes('FROM subscription_payment_transactions')) {
          return { rows: [expected] };
        }
        return { rows: [] };
      },
      async connect() {
        transactionOpened = true;
        throw new Error('Activation transaction must not begin.');
      },
    },
    environment: {},
    gateway: {
      async verifyPayment() {
        return {
          reference: expected.reference,
          status: 'success',
          amount: 1,
          currency: 'NGN',
        };
      },
    },
  });

  await assert.rejects(
    service.verifyAndApply(expected.reference, {
      clinicId: 'clinic-1',
      accountType: 'ClinicAdministrator',
    }),
    (error) => error.code === 'payment_amount_mismatch',
  );
  assert.equal(transactionOpened, false);
  assert.equal(
    topLevelCalls.some((call) => call.sql.includes("SET status = 'Failed'")),
    true,
  );
});

test('repeated verification of a successful reference is idempotent', async () => {
  const expected = { ...pendingPayment(), status: 'Successful' };
  let gatewayCalled = false;
  const client = transactionClient((sql) => {
    if (sql.includes('FROM subscriptions')) {
      return {
        rows: [{
          subscription_id: 'subscription-1',
          clinic_id: 'clinic-1',
          plan: 'Professional',
          plan_name: 'Professional',
          status: 'Active',
          billing_cycle: 'monthly',
          gateway: 'paystack',
          cancel_at_period_end: false,
          updated_at: new Date(),
        }],
      };
    }
    return { rows: [] };
  });
  const pool = {
    ...transactionPool(client),
    async query(sql) {
      if (sql.includes('FROM subscription_payment_transactions')) {
        return { rows: [expected] };
      }
      return { rows: [] };
    },
  };
  const service = new SubscriptionService({
    pool,
    environment: {},
    gateway: {
      async verifyPayment() {
        gatewayCalled = true;
      },
    },
  });

  const result = await service.verifyAndApply(expected.reference, {
    clinicId: 'clinic-1',
    accountType: 'ClinicAdministrator',
  });

  assert.equal(gatewayCalled, false);
  assert.equal(result.payment.status, 'Successful');
  assert.equal(result.subscription.id, 'subscription-1');
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

function pendingPayment() {
  return {
    payment_transaction_id: 'payment-1',
    reference: 'AVERA-TEST-REFERENCE',
    clinic_id: 'clinic-1',
    subscription_id: null,
    gateway: 'paystack',
    plan_code: 'Professional',
    billing_cycle: 'monthly',
    amount_minor: 250000,
    currency: 'NGN',
    status: 'Pending',
    created_at: new Date('2026-07-31T09:00:00Z'),
  };
}

function transactionClient(respond) {
  const client = {
    calls: [],
    async query(sql, parameters = []) {
      client.calls.push({ sql, parameters });
      if (
        sql === 'BEGIN' ||
        sql === 'COMMIT' ||
        sql === 'ROLLBACK' ||
        sql.includes("set_config('avera.")
      ) {
        return { rows: [] };
      }
      return respond(sql, parameters);
    },
    release() {},
  };
  return client;
}

function transactionPool(client) {
  return {
    async connect() {
      return client;
    },
    async query() {
      return { rows: [] };
    },
  };
}
