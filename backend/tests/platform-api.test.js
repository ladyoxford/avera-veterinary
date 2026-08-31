import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { buildApp } from '../src/app.js';
import {
  assertPlatformOwnerStatusChange,
  normalizeClinicStatus,
  platformLivePaymentClause,
  platformEmailStatus,
  queryPlatformOperations,
  queryPlatformClinics,
  queryPlatformSubscriptions,
  queryPlatformUsers,
} from '../src/routes/platform-routes.js';

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
  assert.equal(
    normalizeClinicStatus('RegistrationDraft', 'AwaitingPayment'),
    'Awaiting Payment',
  );
  assert.equal(normalizeClinicStatus('Active', 'AwaitingPayment'), 'Active');
});

test('platform clinic listing includes newly registered clinics awaiting payment', async () => {
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (sql.includes('SELECT count(*)::int AS count')) {
        return { rows: [{ count: 1 }] };
      }
      return {
        rows: [{
          clinic_id: 'clinic-new',
          name: 'New Veterinary Clinic',
          email: 'account@example.com',
          phone: '+2348000000000',
          address: '1 Clinic Road',
          city: 'Lagos',
          country: 'Nigeria',
          time_zone: 'Africa/Lagos',
          status: 'RegistrationDraft',
          subscription_plan: 'Professional',
          created_at: new Date('2026-08-29T08:00:00Z'),
          updated_at: new Date('2026-08-29T08:00:00Z'),
          application_reference: 'AVR-20260829-ABC123',
          application_status: 'AwaitingPayment',
          payment_status: 'Pending',
          account_email: 'account@example.com',
          application_submitted_at: new Date('2026-08-29T08:00:00Z'),
          subscription_status: null,
          user_count: 0,
          patient_count: 0,
        }],
      };
    },
  };

  const result = await queryPlatformClinics(client, { limit: 25 });

  assert.equal(result.total, 1);
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].status, 'Awaiting Payment');
  assert.equal(result.items[0].paymentStatus, 'Pending');
  assert.equal(result.items[0].accountEmail, 'account@example.com');
  assert.equal(
    calls.some(({ sql }) => sql.includes("status <> 'RegistrationDraft'")),
    false,
  );
});

test('Pending platform filter includes registration and approval queues', async () => {
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      return sql.includes('SELECT count(*)::int AS count')
        ? { rows: [{ count: 0 }] }
        : { rows: [] };
    },
  };

  await queryPlatformClinics(client, { status: 'Pending' });

  assert.deepEqual(calls[0].parameters[0], [
    'registrationdraft',
    'pending',
    'pendingapproval',
  ]);
});

test('platform subscription revenue excludes test payments while ledger keeps mode', async () => {
  const calls = [];
  const responses = [
    {
      rows: [{
        clinic_id: 'clinic-1',
        clinic_name: 'AVERA Clinic',
        email: 'clinic@example.com',
        subscription_id: 'subscription-1',
        plan: 'Enterprise',
        status: 'Active',
        billing_cycle: 'annual',
        current_period_start: new Date('2026-08-01T00:00:00Z'),
        current_period_ends_at: new Date('2027-08-01T00:00:00Z'),
        next_billing_date: new Date('2027-08-01T00:00:00Z'),
        cancel_at_period_end: false,
        updated_at: new Date('2026-08-30T00:00:00Z'),
        total_count: 1,
      }],
    },
    {
      rows: [{
        active: 1,
        expiring: 0,
        expired: 0,
        payment_issues: 0,
        monthly_revenue_minor: 500000,
      }],
    },
    {
      rows: [{
        payment_transaction_id: 'payment-1',
        clinic_id: 'clinic-1',
        clinic_name: 'AVERA Clinic',
        reference: 'AVERA-REFERENCE',
        gateway: 'Paystack',
        plan_code: 'Enterprise',
        billing_cycle: 'annual',
        amount_minor: 10000000,
        currency: 'NGN',
        status: 'Successful',
        payment_channel: 'card',
        mode: 'test',
        paid_at: new Date('2026-08-30T00:00:00Z'),
        created_at: new Date('2026-08-30T00:00:00Z'),
      }],
    },
  ];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      return responses.shift();
    },
  };

  const result = await queryPlatformSubscriptions(client, { pageSize: 25 });

  assert.equal(result.total, 1);
  assert.equal(result.summary.monthlyRevenueMinor, 500000);
  assert.equal(result.items[0].billingCycle, 'annual');
  assert.equal(result.payments[0].mode, 'test');
  assert.equal(result.payments[0].amountMinor, 10000000);
  assert.match(
    calls[1].sql,
    /gateway_response_summary->>'mode' = 'live'/,
  );
});

test('all Platform revenue uses the canonical successful live-payment rule', () => {
  assert.equal(
    platformLivePaymentClause,
    "status = 'Successful' AND gateway_response_summary->>'mode' = 'live'",
  );
});

test('platform subscriptions apply status, search, and pagination on the server', async () => {
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (calls.length === 1) {
        return {
          rows: [{
            clinic_id: 'clinic-51',
            clinic_name: 'Expired Clinic',
            status: 'Expired',
            total_count: 126,
          }],
        };
      }
      if (calls.length === 2) {
        return { rows: [{ active: 0, expiring: 0, expired: 126, payment_issues: 0, monthly_revenue_minor: 0 }] };
      }
      return { rows: [] };
    },
  };

  const result = await queryPlatformSubscriptions(client, {
    page: 3,
    pageSize: 25,
    search: 'Expired',
    status: 'Expired',
  });

  assert.equal(result.total, 126);
  assert.equal(result.page, 3);
  assert.equal(result.hasNextPage, true);
  assert.deepEqual(calls[0].parameters, ['%Expired%', 'Expired', 25, 50]);
  assert.match(calls[0].sql, /coalesce\(s\.status, 'Pending'\) ILIKE \$2/);
});

test('Platform Owner status guard prevents self and last-owner lockout', () => {
  assert.throws(
    () => assertPlatformOwnerStatusChange({
      target: { user_id: 'owner-1', status: 'Active' },
      actingUserId: 'owner-1',
      nextStatus: 'Suspended',
      activeOwnerCount: 2,
    }),
    (error) => error.code === 'platform_owner_self_lockout',
  );
  assert.throws(
    () => assertPlatformOwnerStatusChange({
      target: { user_id: 'owner-2', status: 'Active' },
      actingUserId: 'owner-1',
      nextStatus: 'Deactivated',
      activeOwnerCount: 1,
    }),
    (error) => error.code === 'platform_owner_last_active',
  );
  assert.doesNotThrow(() => assertPlatformOwnerStatusChange({
    target: { user_id: 'owner-2', status: 'Active' },
    actingUserId: 'owner-1',
    nextStatus: 'Suspended',
    activeOwnerCount: 2,
  }));
});

test('platform user query returns sanitized platform account fields', async () => {
  const client = {
    async query(sql) {
      assert.match(sql, /PlatformOwner.*PlatformAdministrator/s);
      assert.doesNotMatch(sql, /password_hash/);
      return {
        rows: [{
          user_id: 'owner-1',
          full_name: 'Platform Owner',
          email: 'owner@example.com',
          phone: null,
          account_type: 'PlatformOwner',
          status: 'Active',
          email_verified_at: null,
          last_login_at: null,
          created_at: new Date('2026-08-30T00:00:00Z'),
          total_count: 1,
        }],
      };
    },
  };

  const result = await queryPlatformUsers(client);

  assert.equal(result.total, 1);
  assert.deepEqual(Object.keys(result.items[0]).sort(), [
    'accountType', 'createdAt', 'email', 'emailVerifiedAt', 'fullName',
    'lastLoginAt', 'phone', 'status', 'userId',
  ]);
});

test('platform operational health uses persisted delivery and storage counts', async () => {
  const client = {
    async query(sql) {
      assert.match(sql, /profile_photo_path/);
      assert.match(sql, /image_path/);
      return {
        rows: [{
          recent_email_submissions: 4,
          recent_email_failures: 1,
          latest_email_state: 'email_failed',
          last_email_attempt_at: new Date('2026-08-30T00:00:00Z'),
          patient_photo_count: 7,
          inventory_image_count: 3,
          storage_object_count: 10,
        }],
      };
    },
  };

  const result = await queryPlatformOperations(client);
  assert.equal(result.storage_object_count, 10);
  assert.equal(result.recent_email_failures, 1);
  assert.equal(platformEmailStatus({ configured: false }), 'Not configured');
  assert.equal(
    platformEmailStatus({
      configured: true,
      failures: result.recent_email_failures,
      submissions: result.recent_email_submissions,
      latestState: result.latest_email_state,
    }),
    'Attention required',
  );
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

  const deletion = await app.inject({
    method: 'POST',
    url: '/api/v1/platform/clinics/clinic-1/deletion-requests',
    headers: { authorization: `Bearer ${token}` },
    payload: { reason: 'This account cannot request deletion.' },
  });
  assert.equal(deletion.statusCode, 403);
  assert.equal(deletion.json().error, 'forbidden');

  const userStatus = await app.inject({
    method: 'PATCH',
    url: '/api/v1/platform/users/user-1/status',
    headers: { authorization: `Bearer ${token}` },
    payload: { status: 'Suspended' },
  });
  assert.equal(userStatus.statusCode, 403);
  assert.equal(userStatus.json().error, 'forbidden');
});

test('Platform Administrators cannot mutate Platform Owner account status', async (context) => {
  const pool = {
    async query(sql) {
      if (sql.includes('FROM sessions s JOIN users u')) {
        return {
          rows: [{
            session_id: 'session-admin',
            user_id: 'platform-admin',
            clinic_id: null,
            account_type: 'PlatformAdministrator',
            status: 'Active',
            revoked_at: null,
            expires_at: new Date(Date.now() + 60_000),
            role_id: null,
          }],
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
    userId: 'platform-admin',
    accountType: 'PlatformAdministrator',
    clinicId: null,
    sessionId: 'session-admin',
  });

  const response = await app.inject({
    method: 'PATCH',
    url: '/api/v1/platform/users/owner-1/status',
    headers: { authorization: `Bearer ${token}` },
    payload: { status: 'Suspended' },
  });

  assert.equal(response.statusCode, 403);
  assert.equal(response.json().error, 'forbidden');
});

test('Platform Owner can suspend a Platform Administrator and the mutation is audited', async (context) => {
  let audited = false;
  const client = {
    async query(sql) {
      if (sql.includes('SELECT user_id, clinic_id, full_name')) {
        return { rows: [{
          user_id: 'platform-admin',
          clinic_id: null,
          full_name: 'Platform Administrator',
          account_type: 'PlatformAdministrator',
          status: 'Active',
        }] };
      }
      if (sql.includes('INSERT INTO audit_logs')) audited = true;
      return { rows: [] };
    },
    release() {},
  };
  const pool = {
    async query(sql) {
      if (sql.includes('FROM sessions s JOIN users u')) {
        return { rows: [{
          session_id: 'session-owner',
          user_id: 'owner-1',
          clinic_id: null,
          account_type: 'PlatformOwner',
          status: 'Active',
          revoked_at: null,
          expires_at: new Date(Date.now() + 60_000),
          role_id: null,
        }] };
      }
      throw new Error(`Unexpected database query: ${sql}`);
    },
    async connect() { return client; },
  };
  const app = await buildApp({ environment: testEnvironment(), pool });
  context.after(() => app.close());
  const token = app.jwt.sign({
    userId: 'owner-1',
    accountType: 'PlatformOwner',
    clinicId: null,
    sessionId: 'session-owner',
  });

  const response = await app.inject({
    method: 'PATCH',
    url: '/api/v1/platform/users/platform-admin/status',
    headers: { authorization: `Bearer ${token}` },
    payload: { status: 'Suspended', reason: 'Access review' },
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    userId: 'platform-admin',
    status: 'Suspended',
  });
  assert.equal(audited, true);
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
    AVERA_ACTIVATION_BASE_URL: 'https://accounts.averavet.sbs/activate-clinic-admin',
  };
}
