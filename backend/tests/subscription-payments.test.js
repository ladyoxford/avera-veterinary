import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import test from 'node:test';
import { PaystackSubscriptionGateway } from '../src/payments/paystack-subscription-gateway.js';
import { loadEnvironment } from '../src/config/env.js';
import {
  createPaymentReference,
  SubscriptionService,
  validatePaystackDomain,
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

test('Paystack mode accepts test and live but rejects arbitrary values', () => {
  assert.equal(loadEnvironment(environmentInput({ PAYSTACK_MODE: 'test' })).PAYSTACK_MODE, 'test');
  assert.equal(loadEnvironment(environmentInput({ PAYSTACK_MODE: 'live' })).PAYSTACK_MODE, 'live');
  assert.throws(
    () => loadEnvironment(environmentInput({ PAYSTACK_MODE: 'sandbox' })),
    /Invalid enum value/,
  );
});

test('Paystack transaction domain must match the configured mode when supplied', () => {
  assert.equal(validatePaystackDomain('test', 'test'), null);
  assert.equal(validatePaystackDomain('live', 'live'), null);
  assert.equal(validatePaystackDomain('test', undefined), null);
  assert.equal(validatePaystackDomain('test', 'live'), 'payment_mode_mismatch');
  assert.equal(validatePaystackDomain('live', 'test'), 'payment_mode_mismatch');
  assert.equal(validatePaystackDomain('test', 'unknown'), 'payment_domain_invalid');
});

test('Paystack gateway refuses secret and public keys from the wrong mode', async () => {
  const testWithLiveKeys = new PaystackSubscriptionGateway({
    mode: 'test',
    secretKey: 'sk_live_redacted',
    publicKey: 'pk_live_redacted',
  });
  const liveWithTestKeys = new PaystackSubscriptionGateway({
    mode: 'live',
    secretKey: 'sk_test_redacted',
    publicKey: 'pk_test_redacted',
  });
  assert.equal(testWithLiveKeys.configured, false);
  assert.equal(liveWithTestKeys.configured, false);
  await assert.rejects(
    testWithLiveKeys.verifyPayment('AVERA-TEST'),
    (error) => error.code === 'payment_key_mode_mismatch' && !error.message.includes('sk_live_'),
  );
  await assert.rejects(
    liveWithTestKeys.verifyPayment('AVERA-LIVE'),
    (error) => error.code === 'payment_key_mode_mismatch' && !error.message.includes('sk_test_'),
  );
});

test('Paystack gateway sends secrets only in server Authorization header', async () => {
  let captured;
  const gateway = new PaystackSubscriptionGateway({
    mode: 'test',
    secretKey: 'sk_test_server_secret',
    publicKey: 'pk_test_public_key',
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
  assert.equal(captured.options.headers.Authorization, 'Bearer sk_test_server_secret');
  assert.equal(captured.options.body.includes('sk_test_server_secret'), false);
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

test('subscription verification preserves subscriptions.manage authorization', async (context) => {
  for (const authorized of [false, true]) {
    const pool = paymentRouteAuthPool({
      permissions: authorized ? ['subscriptions.manage'] : ['patients.view'],
    });
    const app = await buildApp({ environment: testEnvironment(), pool });
    context.after(() => app.close());
    let verificationCalled = false;
    app.subscriptionService.verifyConfiguredPayment = async () => {
      verificationCalled = true;
      return {
        payment: { reference: 'AVERA-TEST-REFERENCE', status: 'Successful' },
        subscription: null,
        verified: true,
        mode: 'test',
        subscriptionApplied: false,
      };
    };
    const token = app.jwt.sign({
      userId: 'user-1',
      accountType: 'ClinicAdministrator',
      clinicId: 'clinic-1',
      sessionId: 'session-1',
    });

    const response = await app.inject({
      method: 'GET',
      url: '/api/v1/subscriptions/payments/paystack/verify/AVERA-TEST-REFERENCE',
      headers: { authorization: `Bearer ${token}` },
    });

    assert.equal(response.statusCode, authorized ? 200 : 403);
    assert.equal(verificationCalled, authorized);
  }
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
      PAYSTACK_MODE: 'test',
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

test('test-mode verification records the payment without subscription mutations', async () => {
  const expected = pendingPayment();
  const updated = {
    ...expected,
    status: 'Successful',
    payment_channel: 'card',
    paid_at: new Date('2026-07-31T10:00:00Z'),
    gateway_response_summary: {
      gatewayStatus: 'success',
      mode: 'test',
      subscriptionApplied: false,
    },
  };
  const client = transactionClient((sql) => {
    if (/\bFROM subscriptions\b|\bUPDATE subscriptions\b|\bINSERT INTO subscriptions\b/.test(sql)) {
      throw new Error('Test verification must not touch subscriptions.');
    }
    if (sql.includes('UPDATE clinics') || sql.includes('audit_logs')) {
      throw new Error('Test verification must not touch clinics or audit logs.');
    }
    if (sql.includes('subscription_payment_transactions') && sql.includes('FOR UPDATE')) {
      return { rows: [expected] };
    }
    if (sql.includes('UPDATE subscription_payment_transactions')) {
      return { rows: [updated] };
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
    environment: { PAYSTACK_MODE: 'test' },
    gateway: {
      async verifyPayment() {
        return successfulVerification(expected, { domain: 'test' });
      },
    },
  });

  const result = await service.verifyConfiguredPayment(expected.reference, {
    clinicId: 'clinic-1',
    accountType: 'ClinicAdministrator',
  });

  assert.equal(result.verified, true);
  assert.equal(result.mode, 'test');
  assert.equal(result.subscriptionApplied, false);
  assert.equal(result.subscription, null);
  assert.equal(result.payment.status, 'Successful');
  assert.equal(
    client.calls.filter((call) => call.sql.includes('UPDATE subscription_payment_transactions')).length,
    1,
  );
  assert.equal(client.calls.some((call) => call.sql.includes('audit_logs')), false);
  assert.equal(client.calls.some((call) => call.sql.includes('UPDATE clinics')), false);
});

test('repeated test-mode verification is idempotent and does not call Paystack', async () => {
  const expected = {
    ...pendingPayment(),
    status: 'Successful',
    gateway_response_summary: {
      mode: 'test',
      subscriptionApplied: false,
    },
  };
  let gatewayCalled = false;
  let transactionOpened = false;
  const service = new SubscriptionService({
    pool: {
      async query() {
        return { rows: [expected] };
      },
      async connect() {
        transactionOpened = true;
        throw new Error('Idempotent verification must not open a transaction.');
      },
    },
    environment: { PAYSTACK_MODE: 'test' },
    gateway: {
      async verifyPayment() {
        gatewayCalled = true;
      },
    },
  });

  const result = await service.verifyConfiguredPayment(expected.reference, {
    clinicId: 'clinic-1',
    accountType: 'ClinicAdministrator',
  });

  assert.equal(gatewayCalled, false);
  assert.equal(transactionOpened, false);
  assert.equal(result.payment.status, 'Successful');
  assert.equal(result.subscriptionApplied, false);
});

test('test-mode verification preserves cross-clinic isolation', async () => {
  const expected = pendingPayment();
  let gatewayCalled = false;
  const service = new SubscriptionService({
    pool: {
      async query() {
        return { rows: [expected] };
      },
    },
    environment: { PAYSTACK_MODE: 'test' },
    gateway: {
      async verifyPayment() {
        gatewayCalled = true;
      },
    },
  });

  await assert.rejects(
    service.verifyConfiguredPayment(expected.reference, {
      clinicId: 'clinic-2',
      accountType: 'ClinicAdministrator',
    }),
    (error) => error.code === 'forbidden',
  );
  assert.equal(gatewayCalled, false);
});

test('configured verification selects verifyOnly in test and verifyAndApply in live', async () => {
  for (const mode of ['test', 'live']) {
    const calls = [];
    const service = new SubscriptionService({
      pool: {},
      environment: { PAYSTACK_MODE: mode },
      gateway: {},
    });
    service.verifyOnly = async () => {
      calls.push('verifyOnly');
      return { mode: 'test' };
    };
    service.verifyAndApply = async () => {
      calls.push('verifyAndApply');
      return { mode: 'live' };
    };

    const result = await service.verifyConfiguredPayment('AVERA-REFERENCE');

    assert.deepEqual(calls, [mode === 'test' ? 'verifyOnly' : 'verifyAndApply']);
    assert.equal(result.mode, mode);
  }
});

test('payment operations fail safely when PAYSTACK_MODE is missing', async () => {
  const service = new SubscriptionService({
    pool: {},
    environment: {},
    gateway: {},
  });

  await assert.rejects(
    service.verifyConfiguredPayment('AVERA-REFERENCE'),
    (error) =>
      error.code === 'payment_mode_not_configured' && error.statusCode === 503,
  );
});

test('charge.success webhook uses no-mutation verification in test and live apply in live', async () => {
  for (const mode of ['test', 'live']) {
    const calls = [];
    const poolCalls = [];
    const service = new SubscriptionService({
      pool: {
        async query(sql) {
          poolCalls.push(sql);
          if (sql.includes('INSERT INTO payment_webhook_events')) {
            return { rowCount: 1, rows: [{ payment_webhook_event_id: `event-${mode}` }] };
          }
          return { rowCount: 1, rows: [] };
        },
      },
      environment: { PAYSTACK_MODE: mode },
      gateway: {},
    });
    service.verifyOnly = async () => calls.push('verifyOnly');
    service.verifyAndApply = async () => calls.push('verifyAndApply');

    const result = await service.persistWebhook({
      event: { event: 'charge.success', data: { reference: 'AVERA-REFERENCE' } },
      rawBody: Buffer.from('{}'),
      payloadHash: `hash-${mode}`,
    });

    assert.equal(result.duplicate, false);
    assert.deepEqual(calls, [mode === 'test' ? 'verifyOnly' : 'verifyAndApply']);
    assert.equal(
      poolCalls.some((sql) => sql.includes("processing_status = 'Processed'")),
      true,
    );
  }
});

test('test-mode non-charge webhooks are acknowledged without subscription mutation', async () => {
  const calls = [];
  const service = new SubscriptionService({
    pool: {
      async query(sql) {
        calls.push(sql);
        if (sql.includes('INSERT INTO payment_webhook_events')) {
          return { rowCount: 1, rows: [{ payment_webhook_event_id: 'event-test' }] };
        }
        return { rowCount: 1, rows: [] };
      },
    },
    environment: { PAYSTACK_MODE: 'test' },
    gateway: {},
  });

  await service.persistWebhook({
    event: { event: 'subscription.disable', data: { subscription_code: 'SUB-1' } },
    rawBody: Buffer.from('{}'),
    payloadHash: 'hash-test-subscription-event',
  });

  assert.equal(calls.some((sql) => /\bUPDATE subscriptions\b/.test(sql)), false);
  assert.equal(calls.some((sql) => sql.includes("processing_status = 'Processed'")), true);
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
    PAYSTACK_MODE: 'test',
    PAYSTACK_SECRET_KEY: 'sk_test_server_secret',
    PAYSTACK_WEBHOOK_SECRET: 'test-secret',
    APP_PAYMENT_CALLBACK_URL: 'avera://payments/callback',
    allowedOrigins: ['http://localhost'],
  };
}

function environmentInput(overrides = {}) {
  return {
    NODE_ENV: 'test',
    DATABASE_URL: 'postgres://unused:unused@localhost:5432/unused',
    JWT_ACCESS_SECRET: 'a'.repeat(32),
    JWT_REFRESH_SECRET: 'b'.repeat(32),
    ...overrides,
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

function successfulVerification(expected, overrides = {}) {
  return {
    id: 42,
    reference: expected.reference,
    status: 'success',
    amount: expected.amount_minor,
    currency: expected.currency,
    channel: 'card',
    paid_at: '2026-07-31T10:00:00Z',
    metadata: {
      clinicId: expected.clinic_id,
      planCode: expected.plan_code,
      billingCycle: expected.billing_cycle,
    },
    ...overrides,
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

function paymentRouteAuthPool({ permissions }) {
  return {
    async query(sql) {
      if (sql.includes('FROM sessions s JOIN users u')) {
        return {
          rows: [{
            session_id: 'session-1',
            user_id: 'user-1',
            clinic_id: 'clinic-1',
            account_type: 'ClinicAdministrator',
            status: 'Active',
            revoked_at: null,
            expires_at: new Date(Date.now() + 60_000),
            role_id: 'role-1',
          }],
        };
      }
      if (sql.includes('LEFT JOIN clinic_memberships')) {
        return {
          rows: [{ membership_status: 'Active', clinic_status: 'Active' }],
        };
      }
      if (sql.includes('FROM role_permissions')) {
        return {
          rows: permissions.map((permission_key) => ({ permission_key })),
        };
      }
      if (sql.includes("effect = 'restrict'")) return { rows: [] };
      throw new Error(`Unexpected database query: ${sql}`);
    },
  };
}
