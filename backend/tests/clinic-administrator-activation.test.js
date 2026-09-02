import assert from 'node:assert/strict';
import test from 'node:test';
import {
  ActivationEmailDeliveryService,
  ClinicAdministratorActivationService,
} from '../src/services/clinic-administrator-activation-service.js';
import { hashToken } from '../src/security/tokens.js';
import { verifyPassword } from '../src/security/passwords.js';

const environment = {
  ACTIVATION_TOKEN_TTL_MINUTES: 60,
  AVERA_ACTIVATION_BASE_URL: 'https://accounts.averavet.sbs/activate-clinic-admin',
  AVERA_STAFF_ACTIVATION_BASE_URL: 'https://accounts.averavet.sbs/activate-staff',
};

function service(pool, deliveryService = new ActivationEmailDeliveryService({ environment })) {
  return new ClinicAdministratorActivationService({
    pool,
    environment,
    deliveryService,
  });
}

function approvalHarness() {
  const state = {
    calls: [],
    application: {
      application_id: 'application-1',
      administrator_name: 'Ada Clinic Owner',
      administrator_email: 'ADA@EXAMPLE.COM',
      administrator_phone: '+2348000000000',
    },
    user: null,
    liveToken: null,
    tokenInsertCount: 0,
    membershipCount: 0,
  };
  const client = {
    async query(sql, parameters = []) {
      state.calls.push({ sql, parameters });
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.includes("set_config('avera.")) return { rows: [] };
      if (sql.includes('FROM clinic_applications') && sql.includes('FOR UPDATE')) return { rows: [state.application] };
      if (sql.includes('SELECT role_id') && sql.includes('FROM roles')) return { rows: [] };
      if (sql.includes('INSERT INTO roles')) return { rows: [{ role_id: parameters[1] === 'clinic_administrator' ? 'role-admin' : `role-${parameters[1]}` }] };
      if (sql.includes('SELECT permission_id, permission_key') && sql.includes('ANY')) {
        return { rows: parameters[0].map((key, index) => ({ permission_id: `permission-${index}`, permission_key: key })) };
      }
      if (sql.includes('SELECT permission_id, permission_key')) return { rows: [{ permission_id: 'permission-1', permission_key: 'patients.view' }] };
      if (sql.includes('INSERT INTO role_permissions')) return { rows: [] };
      if (sql.includes('SELECT * FROM users WHERE email')) return { rows: state.user ? [state.user] : [] };
      if (sql.includes('INSERT INTO users')) {
        state.user = {
          user_id: 'user-admin',
          clinic_id: parameters[0],
          full_name: parameters[1],
          email: parameters[2],
          phone: parameters[3],
          password_hash: null,
          account_type: 'ClinicAdministrator',
          status: 'PendingActivation',
          role_id: parameters[4],
        };
        return { rows: [state.user] };
      }
      if (sql.includes('UPDATE users') && sql.includes("status = 'PendingActivation'")) return { rows: [state.user] };
      if (sql.includes('INSERT INTO clinic_memberships')) {
        state.membershipCount = 1;
        return { rows: [] };
      }
      if (sql.includes('UPDATE clinic_applications')) return { rows: [] };
      if (sql.includes('SELECT token_id, expires_at FROM activation_tokens')) return { rows: state.liveToken ? [state.liveToken] : [] };
      if (sql.includes('UPDATE activation_tokens SET revoked_at')) {
        state.liveToken = null;
        return { rows: [] };
      }
      if (
        sql.includes('UPDATE activation_tokens') &&
        sql.includes('delivery_method = $2')
      ) {
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO activation_tokens')) {
        state.tokenInsertCount += 1;
        state.liveToken = {
          token_id: `token-${state.tokenInsertCount}`,
          expires_at: parameters[4],
          token_hash: parameters[3],
        };
        return { rows: [{ token_id: state.liveToken.token_id }] };
      }
      if (sql.includes('SELECT clinic_id, name, status FROM clinics')) return { rows: [{ clinic_id: 'clinic-1', name: 'Ada Veterinary Clinic', status: 'Active' }] };
      if (sql.includes('SELECT * FROM users') && sql.includes("account_type = 'ClinicAdministrator'")) return { rows: state.user ? [state.user] : [] };
      if (sql.includes('INSERT INTO audit_logs')) return { rows: [] };
      throw new Error(`Unexpected approval query: ${sql}`);
    },
    release() {},
  };
  return {
    state,
    client,
    pool: {
      connect: async () => client,
      query: (...arguments_) => client.query(...arguments_),
    },
  };
}

function tokenHarness({ expired = false, used = false } = {}) {
  const rawToken = 'secure-activation-token-with-more-than-32-characters';
  const state = {
    calls: [],
    userStatus: 'PendingActivation',
    passwordHash: null,
    usedAt: used ? new Date() : null,
    revokedAt: null,
  };
  const client = {
    async query(sql, parameters = []) {
      state.calls.push({ sql, parameters });
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.includes("set_config('avera.")) return { rows: [] };
      if (sql.includes('FROM activation_tokens t')) {
        if (parameters[0] !== hashToken(rawToken)) return { rows: [] };
        return {
          rows: [{
            token_id: 'token-1',
            user_id: 'user-1',
            clinic_id: 'clinic-1',
            expires_at: expired ? new Date(Date.now() - 1_000) : new Date(Date.now() + 60_000),
            used_at: state.usedAt,
            revoked_at: state.revokedAt,
            full_name: 'Ada Clinic Owner',
            email: 'ada@example.com',
            user_status: state.userStatus,
            clinic_name: 'Ada Veterinary Clinic',
            clinic_status: 'Active',
          }],
        };
      }
      if (sql.includes('UPDATE users') && sql.includes('password_hash')) {
        state.passwordHash = parameters[1];
        state.userStatus = 'Active';
        return { rows: [] };
      }
      if (sql.includes('UPDATE activation_tokens') && sql.includes('used_at = CASE')) {
        state.usedAt = parameters[2];
        return { rows: [] };
      }
      if (sql.includes('UPDATE clinic_memberships') || sql.includes('UPDATE sessions') || sql.includes('INSERT INTO audit_logs')) return { rows: [] };
      throw new Error(`Unexpected activation query: ${sql}`);
    },
    release() {},
  };
  return {
    rawToken,
    state,
    pool: {
      connect: async () => client,
      query: (...arguments_) => client.query(...arguments_),
    },
  };
}

function staffHarness({ expired = false, used = false, revoked = false, existingUser = null } = {}) {
  const rawToken = 'secure-staff-activation-token-with-more-than-32-characters';
  const state = {
    calls: [],
    userStatus: 'PendingActivation',
    membershipStatus: 'Invited',
    passwordHash: null,
    usedAt: used ? new Date() : null,
    revokedAt: revoked ? new Date() : null,
    tokenInsertCount: 0,
    staffSequence: 0,
  };
  const client = {
    async query(sql, parameters = []) {
      state.calls.push({ sql, parameters });
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.includes("set_config('avera.")) return { rows: [] };
      if (sql.includes('SELECT r.code FROM clinic_memberships')) return { rows: [{ code: 'clinic_administrator' }] };
      if (sql.includes('SELECT role_id, name, code FROM roles')) {
        return parameters[1] === 'role-vet'
          ? { rows: [{ role_id: 'role-vet', name: 'Veterinarian', code: 'veterinarian' }] }
          : { rows: [] };
      }
      if (sql.includes('SELECT * FROM users WHERE email')) return { rows: existingUser ? [existingUser] : [] };
      if (sql.includes('INSERT INTO clinic_staff_number_sequences')) return { rows: [] };
      if (sql.includes('UPDATE clinic_staff_number_sequences')) {
        state.staffSequence += 1;
        return { rows: [{ current_value: state.staffSequence }] };
      }
      if (sql.includes('INSERT INTO users')) return { rows: [{ user_id: 'staff-1', clinic_id: 'clinic-1', full_name: parameters[1], email: parameters[2], status: 'PendingActivation' }] };
      if (sql.includes('INSERT INTO clinic_memberships') || sql.includes('INSERT INTO staff_profiles')) return { rows: [] };
      if (sql.includes('SELECT name FROM clinics')) return { rows: [{ name: 'Ada Veterinary Clinic' }] };
      if (sql.includes('UPDATE activation_tokens SET revoked_at')) {
        state.revokedAt = new Date();
        return { rows: [] };
      }
      if (sql.includes("UPDATE activation_tokens SET delivery_method='email_submitted'")) return { rows: [] };
      if (sql.includes('INSERT INTO activation_tokens')) {
        state.tokenInsertCount += 1;
        return { rows: [{ token_id: `staff-token-${state.tokenInsertCount}` }] };
      }
      if (sql.includes('FROM activation_tokens t')) {
        if (parameters[0] !== hashToken(rawToken)) return { rows: [] };
        return { rows: [{
          token_id: 'staff-token-existing', user_id: 'staff-1', clinic_id: 'clinic-1',
          expires_at: expired ? new Date(Date.now() - 1000) : new Date(Date.now() + 60000),
          used_at: state.usedAt, revoked_at: state.revokedAt,
          full_name: 'Jane Vet', email: 'jane@example.com',
          user_status: state.userStatus, membership_status: state.membershipStatus,
          clinic_name: 'Ada Veterinary Clinic', clinic_status: 'Active', role_name: 'Veterinarian',
        }] };
      }
      if (sql.includes('UPDATE users SET password_hash')) {
        state.passwordHash = parameters[1];
        state.userStatus = 'Active';
        return { rows: [] };
      }
      if (sql.includes("UPDATE clinic_memberships SET membership_status='Active'")) {
        state.membershipStatus = 'Active';
        return { rows: [] };
      }
      if (sql.includes('UPDATE activation_tokens') && sql.includes('used_at=CASE')) {
        state.usedAt = parameters[2];
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO audit_logs')) return { rows: [] };
      throw new Error(`Unexpected staff activation query: ${sql}`);
    },
    release() {},
  };
  return {
    rawToken,
    state,
    pool: { connect: async () => client, query: (...arguments_) => client.query(...arguments_) },
  };
}

function emailOutcomeHarness() {
  const state = { calls: [], deliveryMethod: null, deliveryReference: null };
  const client = {
    async query(sql, parameters = []) {
      state.calls.push({ sql, parameters });
      if (
        sql === 'BEGIN' ||
        sql === 'COMMIT' ||
        sql === 'ROLLBACK' ||
        sql.includes("set_config('avera.") ||
        sql.includes('INSERT INTO audit_logs')
      ) {
        return { rows: [] };
      }
      if (
        sql.includes('UPDATE activation_tokens') &&
        sql.includes('delivery_method = $2')
      ) {
        state.deliveryMethod = parameters[1];
        state.deliveryReference = parameters[3];
        return { rows: [] };
      }
      throw new Error(`Unexpected email outcome query: ${sql}`);
    },
    release() {},
  };
  return {
    state,
    pool: {
      connect: async () => client,
      query: (...arguments_) => client.query(...arguments_),
    },
  };
}

function issuedAdministratorToken() {
  return {
    tokenId: 'token-email-1',
    userId: 'user-admin-1',
    clinicId: 'clinic-1',
    rawToken: 'secure-activation-token-with-more-than-32-characters',
    expiresAt: new Date(Date.now() + 60_000),
    email: 'canonical@example.com',
    fullName: 'Ada Clinic Owner',
    clinicName: 'Ada Veterinary Clinic',
    actorUserId: 'platform-owner-1',
    sessionId: 'platform-session-1',
    ipAddress: '127.0.0.1',
  };
}

test('Resend acceptance requires a non-empty provider message ID', async () => {
  const provider = new ActivationEmailDeliveryService({
    environment: {
      ...environment,
      RESEND_API_KEY: 'test-key',
      ACTIVATION_EMAIL_FROM: 'AVERA <accounts@example.com>',
    },
    fetchImpl: async () => ({
      ok: true,
      async json() {
        return { id: 'resend-message-1' };
      },
    }),
  });

  const result = await provider.sendClinicAdministratorActivation({
    to: 'canonical@example.com',
    applicantName: 'Ada Clinic Owner',
    clinicName: 'Ada Veterinary Clinic',
    activationUrl: 'https://accounts.example.test/activate',
    expiresAt: new Date(Date.now() + 60_000),
    idempotencyKey: 'activation-token-email-1',
  });

  assert.equal(result.accepted, true);
  assert.equal(result.provider, 'resend');
  assert.equal(result.providerMessageId, 'resend-message-1');
  assert.ok(Date.parse(result.submittedAt));
});

test('SMTP transport submits account email through the configured Hostinger mailbox', async () => {
  let submitted;
  const provider = new ActivationEmailDeliveryService({
    environment: {
      ...environment,
      EMAIL_TRANSPORT: 'smtp',
      EMAIL_FROM: 'AVERA <accounts@avera.test>',
      SMTP_HOST: 'smtp.hostinger.com',
      SMTP_PORT: 465,
      SMTP_SECURE: 'true',
      SMTP_USER: 'accounts@avera.test',
      SMTP_PASSWORD: 'secret-from-environment',
    },
    smtpTransport: {
      async sendMail(message) {
        submitted = message;
        return {
          messageId: '<smtp-message-1@avera.test>',
          accepted: [message.to],
          rejected: [],
        };
      },
    },
  });

  const result = await provider.sendPasswordReset({
    to: 'owner@avera.test',
    fullName: 'AVERA Platform Owner',
    resetUrl: 'https://accounts.averavet.sbs/reset-password?token=opaque',
    expiresAt: new Date(Date.now() + 60_000),
    idempotencyKey: 'password-reset-1',
  });

  assert.equal(provider.provider, 'smtp');
  assert.equal(provider.providerLabel, 'SMTP');
  assert.equal(result.accepted, true);
  assert.equal(result.provider, 'smtp');
  assert.equal(result.providerMessageId, '<smtp-message-1@avera.test>');
  assert.equal(submitted.from, 'AVERA <accounts@avera.test>');
  assert.equal(submitted.to, 'owner@avera.test');
  assert.match(submitted.text, /reset-password\?token=opaque/);
  assert.equal(submitted.text.includes('secret-from-environment'), false);
});

test('empty, rejected, and unavailable provider responses are never successful', async () => {
  const configuredEnvironment = {
    ...environment,
    RESEND_API_KEY: 'test-key',
    ACTIVATION_EMAIL_FROM: 'AVERA <accounts@example.com>',
  };
  const message = {
    to: 'canonical@example.com',
    applicantName: 'Ada Clinic Owner',
    clinicName: 'Ada Veterinary Clinic',
    activationUrl: 'https://accounts.example.test/activate',
    expiresAt: new Date(Date.now() + 60_000),
    idempotencyKey: 'activation-token-email-2',
  };
  const cases = [
    {
      fetchImpl: async () => ({ ok: true, json: async () => ({}) }),
      failureCode: 'email_provider_missing_message_id',
    },
    {
      fetchImpl: async () => ({ ok: false, json: async () => ({}) }),
      failureCode: 'email_provider_rejected',
    },
    {
      fetchImpl: async () => {
        throw new Error('network unavailable');
      },
      failureCode: 'email_provider_unavailable',
    },
  ];

  for (const testCase of cases) {
    const provider = new ActivationEmailDeliveryService({
      environment: configuredEnvironment,
      fetchImpl: testCase.fetchImpl,
    });
    const result = await provider.sendClinicAdministratorActivation(message);
    assert.equal(result.accepted, false);
    assert.equal(result.providerMessageId, null);
    assert.equal(result.failureCode, testCase.failureCode);
  }
});

test('administrator email outcomes distinguish Submitted, DeliveryFailed, and ManualDeliveryRequired', async () => {
  const acceptedHarness = emailOutcomeHarness();
  const accepted = await service(acceptedHarness.pool, {
    configured: true,
    async sendClinicAdministratorActivation() {
      return {
        accepted: true,
        provider: 'resend',
        providerMessageId: 'resend-message-accepted',
        submittedAt: new Date().toISOString(),
      };
    },
  }).deliverIssuedToken(issuedAdministratorToken());
  assert.equal(accepted.deliveryMethod, 'email_submitted');
  assert.equal(accepted.emailState, 'Submitted');
  assert.equal('activationUrl' in accepted, false);
  assert.equal(acceptedHarness.state.deliveryMethod, 'email_submitted');
  assert.equal(
    acceptedHarness.state.deliveryReference,
    'resend-message-accepted',
  );

  const failedHarness = emailOutcomeHarness();
  const failed = await service(failedHarness.pool, {
    configured: true,
    async sendClinicAdministratorActivation() {
      return undefined;
    },
  }).deliverIssuedToken(issuedAdministratorToken());
  assert.equal(failed.deliveryMethod, 'email_failed');
  assert.equal(failed.emailState, 'DeliveryFailed');
  assert.equal('activationUrl' in failed, false);
  assert.equal(failedHarness.state.deliveryMethod, 'email_failed');
  assert.equal(
    failedHarness.state.calls.some(({ sql }) => sql.includes('UPDATE clinics')),
    false,
  );

  const manualHarness = emailOutcomeHarness();
  const manual = await service(manualHarness.pool, {
    configured: false,
  }).deliverIssuedToken(issuedAdministratorToken());
  assert.equal(manual.deliveryMethod, 'manual');
  assert.equal(manual.emailState, 'ManualDeliveryRequired');
  assert.equal(
    new URL(manual.activationUrl).searchParams.get('token'),
    issuedAdministratorToken().rawToken,
  );
});

test('free application approval requires explicit zero prices and creates no payment ledger entry', async () => {
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (
        ['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql) ||
        sql.includes("set_config('avera.")
      ) {
        return { rows: [] };
      }
      if (sql.includes('pg_advisory_xact_lock')) return { rows: [] };
      if (sql.includes('JOIN plans p') && sql.includes('FOR UPDATE OF a, c, p')) {
        return {
          rows: [{
            application_id: 'application-free-1',
            clinic_id: 'clinic-free-1',
            application_status: 'AwaitingPayment',
            payment_status: 'Pending',
            selected_plan: 'Starter',
            clinic_name: 'Free Veterinary Clinic',
            clinic_status: 'RegistrationDraft',
            monthly_amount_minor: 0,
            annual_amount_minor: 0,
          }],
        };
      }
      if (sql.includes('SELECT subscription_id') && sql.includes('FROM subscriptions')) {
        return { rows: [] };
      }
      if (
        sql.includes('UPDATE clinics') ||
        sql.includes('UPDATE clinic_applications') ||
        sql.includes('INSERT INTO subscriptions') ||
        sql.includes('INSERT INTO audit_logs')
      ) {
        return { rows: [] };
      }
      throw new Error(`Unexpected free approval query: ${sql}`);
    },
    release() {},
  };
  const activation = service({ connect: async () => client });
  activation.provisionOnApproval = async () => ({ issued: null });
  activation.activationStatus = async () => ({
    status: 'PendingActivation',
    deliveryMethod: 'email_submitted',
  });

  const result = await activation.approveFreeApplication({
    applicationId: 'application-free-1',
    clinicId: 'clinic-free-1',
    ipAddress: '127.0.0.1',
  });

  assert.equal(result.approved, true);
  assert.equal(
    calls.some(({ sql }) => sql.includes('INSERT INTO subscriptions')),
    true,
  );
  assert.equal(
    calls.some(({ sql }) =>
      sql.includes('subscription_payment_transactions') ||
      sql.includes('paystack')),
    false,
  );
});

test('free application approval rejects null pricing as unconfigured rather than free', async () => {
  const client = {
    async query(sql) {
      if (
        ['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql) ||
        sql.includes("set_config('avera.") ||
        sql.includes('pg_advisory_xact_lock')
      ) {
        return { rows: [] };
      }
      if (sql.includes('JOIN plans p') && sql.includes('FOR UPDATE OF a, c, p')) {
        return {
          rows: [{
            application_id: 'application-unconfigured-1',
            clinic_id: 'clinic-unconfigured-1',
            application_status: 'AwaitingPayment',
            payment_status: 'Pending',
            selected_plan: 'Starter',
            clinic_name: 'Unconfigured Clinic',
            clinic_status: 'RegistrationDraft',
            monthly_amount_minor: null,
            annual_amount_minor: null,
          }],
        };
      }
      throw new Error(`Unexpected unconfigured free approval query: ${sql}`);
    },
    release() {},
  };

  await assert.rejects(
    service({ connect: async () => client }).approveFreeApplication({
      applicationId: 'application-unconfigured-1',
      clinicId: 'clinic-unconfigured-1',
    }),
    (error) => error.code === 'payment_required',
  );
});

test('approval provisions exactly one passwordless pending administrator and is idempotent', async () => {
  const harness = approvalHarness();
  const activation = service(harness.pool);
  const context = {
    clinicId: 'clinic-1',
    clinicName: 'Ada Veterinary Clinic',
    actorUserId: 'platform-owner-1',
  };

  const first = await activation.provisionOnApproval(harness.client, context);
  const second = await activation.provisionOnApproval(harness.client, context);

  assert.equal(first.user.status, 'PendingActivation');
  assert.equal(first.user.password_hash, null);
  assert.ok(first.issued.rawToken);
  assert.equal(second.issued, null);
  assert.equal(harness.state.tokenInsertCount, 1);
  assert.equal(harness.state.membershipCount, 1);
  assert.equal(harness.state.calls.filter((call) => call.sql.includes('INSERT INTO users')).length, 1);
});

test('verified clinic payment automatically approves and submits activation email', async () => {
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (
        sql === 'BEGIN' ||
        sql === 'COMMIT' ||
        sql === 'ROLLBACK' ||
        sql.includes("set_config('avera.") ||
        sql.includes('pg_advisory_xact_lock') ||
        sql.includes('INSERT INTO audit_logs')
      ) {
        return { rows: [] };
      }
      if (sql.includes('FROM clinic_applications a')) {
        return {
          rows: [{
            application_id: 'application-paid',
            clinic_id: 'clinic-paid',
            application_status: 'Pending',
            payment_status: 'TestVerified',
            payment_reference: 'AVERA-PAID-1',
            clinic_name: 'Paid Veterinary Clinic',
            clinic_status: 'PendingApproval',
            transaction_status: 'Successful',
          }],
        };
      }
      if (sql.includes("UPDATE clinics") && sql.includes("status = 'Active'")) {
        return { rows: [] };
      }
      throw new Error(`Unexpected automatic approval query: ${sql}`);
    },
    release() {},
  };
  const activation = service({
    connect: async () => client,
    query: (...arguments_) => client.query(...arguments_),
  });
  activation.provisionOnApproval = async (_client, context) => {
    assert.equal(context.clinicId, 'clinic-paid');
    assert.equal(context.actorUserId, null);
    return {
      issued: {
        tokenId: 'activation-token-1',
        rawToken: 'not-returned-to-the-payment-client',
      },
    };
  };
  activation.deliverIssuedToken = async (issued) => {
    assert.equal(issued.tokenId, 'activation-token-1');
    return {
      status: 'PendingActivation',
      deliveryMethod: 'email_submitted',
    };
  };

  const result = await activation.approveAfterVerifiedPayment({
    applicationId: 'application-paid',
    clinicId: 'clinic-paid',
    reference: 'AVERA-PAID-1',
    mode: 'test',
  });

  assert.equal(result.approved, true);
  assert.equal(result.activation.deliveryMethod, 'email_submitted');
  assert.equal(
    calls.some((call) =>
      call.sql.includes("UPDATE clinics") && call.sql.includes("status = 'Active'")),
    true,
  );
  assert.equal(
    calls.some((call) =>
      call.sql.includes('INSERT INTO audit_logs') &&
      call.parameters[4] === 'clinic.auto_approved_after_verified_payment'),
    true,
  );
});

test('verified payment retry reconciles an approved active clinic without changing payment state', async () => {
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (
        sql === 'BEGIN' ||
        sql === 'COMMIT' ||
        sql === 'ROLLBACK' ||
        sql.includes("set_config('avera.") ||
        sql.includes('pg_advisory_xact_lock') ||
        sql.includes('INSERT INTO audit_logs')
      ) {
        return { rows: [] };
      }
      if (sql.includes('FROM clinic_applications a')) {
        return {
          rows: [{
            application_id: 'application-repair',
            clinic_id: 'clinic-repair',
            application_status: 'Approved',
            payment_status: 'TestVerified',
            payment_reference: 'AVERA-REPAIR-1',
            clinic_name: 'Repair Veterinary Clinic',
            clinic_status: 'Active',
            transaction_status: 'Successful',
          }],
        };
      }
      throw new Error(`Unexpected reconciliation query: ${sql}`);
    },
    release() {},
  };
  const activation = service({
    connect: async () => client,
    query: (...arguments_) => client.query(...arguments_),
  });
  let reconciled = 0;
  activation.provisionOnApproval = async () => {
    reconciled += 1;
    return { issued: null };
  };
  activation.activationStatus = async () => ({
    status: 'PendingActivation',
    canResend: true,
  });

  const result = await activation.approveAfterVerifiedPayment({
    applicationId: 'application-repair',
    clinicId: 'clinic-repair',
    reference: 'AVERA-REPAIR-1',
    mode: 'test',
  });

  assert.equal(result.approved, true);
  assert.equal(reconciled, 1);
  assert.equal(result.activation.status, 'PendingActivation');
  assert.equal(
    calls.some(({ sql }) => sql.includes('UPDATE clinics')),
    false,
  );
  assert.equal(
    calls.some(({ sql }) => sql.includes('UPDATE clinic_applications') && sql.includes('payment_status')),
    false,
  );
});

test('canonical registration Account Email provisions the administrator through legacy application columns', async () => {
  const harness = approvalHarness();
  harness.state.application.administrator_email = null;
  harness.state.application.clinic_email = 'ACCOUNT@EXAMPLE.COM';

  const result = await service(harness.pool).provisionOnApproval(harness.client, {
    clinicId: 'clinic-1',
    clinicName: 'Ada Veterinary Clinic',
    actorUserId: 'platform-owner-1',
  });

  assert.equal(result.user.email, 'account@example.com');
  assert.equal(harness.state.membershipCount, 1);
});

test('activation token is hashed and plaintext is never passed to persistence', async () => {
  const harness = approvalHarness();
  const result = await service(harness.pool).provisionOnApproval(harness.client, {
    clinicId: 'clinic-1',
    clinicName: 'Ada Veterinary Clinic',
    actorUserId: 'platform-owner-1',
  });
  const tokenInsert = harness.state.calls.find((call) => call.sql.includes('INSERT INTO activation_tokens'));
  assert.equal(tokenInsert.parameters[3], hashToken(result.issued.rawToken));
  assert.notEqual(tokenInsert.parameters[3], result.issued.rawToken);
  assert.equal(JSON.stringify(harness.state.calls).includes(result.issued.rawToken), false);
});

test('expired and already-used activation tokens are rejected', async () => {
  for (const options of [{ expired: true }, { used: true }]) {
    const harness = tokenHarness(options);
    await assert.rejects(
      service(harness.pool).inspect(harness.rawToken),
      options.expired ? /expired/i : /already been used/i,
    );
  }
});

test('successful activation stores bcrypt only, enables login credentials, and prevents reuse', async () => {
  const harness = tokenHarness();
  const password = 'SecureClinic#2026';
  const result = await service(harness.pool).activate({
    rawToken: harness.rawToken,
    password,
    confirmPassword: password,
  });

  assert.equal(result.activated, true);
  assert.equal(harness.state.userStatus, 'Active');
  assert.notEqual(harness.state.passwordHash, password);
  assert.equal(await verifyPassword(password, harness.state.passwordHash), true);
  assert.equal(JSON.stringify(harness.state.calls).includes(password), false);
  await assert.rejects(
    service(harness.pool).activate({
      rawToken: harness.rawToken,
      password,
      confirmPassword: password,
    }),
    /already been used/i,
  );
});

test('staff invitation is passwordless, token-hashed, tenant-scoped, and pending activation', async () => {
  const harness = staffHarness();
  const result = await service(harness.pool).inviteStaff({
    clinicId: 'clinic-1', actorUserId: 'admin-1', fullName: 'Jane Vet',
    email: 'jane@example.com', roleId: 'role-vet',
    professionalTitle: 'Veterinary Surgeon', ipAddress: '127.0.0.1',
  });
  assert.equal(result.status, 'PendingActivation');
  assert.equal(result.staffNumber, '001');
  assert.equal(result.delivery.status, 'DeliveryUnavailable');
  const userInsert = harness.state.calls.find((call) => call.sql.includes('INSERT INTO users'));
  assert.match(userInsert.sql, /NULL,'ClinicStaff','PendingActivation'/);
  const tokenInsert = harness.state.calls.find((call) => call.sql.includes('INSERT INTO activation_tokens'));
  assert.equal(typeof tokenInsert.parameters[3], 'string');
  assert.equal(JSON.stringify(harness.state.calls).includes('secure-staff-activation-token'), false);
  const roleLookup = harness.state.calls.find((call) => call.sql.includes('SELECT role_id, name, code FROM roles'));
  assert.deepEqual(roleLookup.parameters, ['clinic-1', 'role-vet']);
});

test('staff invitation submits the selected role and rejects stale role IDs', async () => {
  const harness = staffHarness();
  let delivered;
  const deliveryService = {
    configured: true,
    async sendStaffActivation(message) {
      delivered = message;
      return {
        accepted: true,
        provider: 'resend',
        providerMessageId: 'resend-message-1',
        submittedAt: new Date().toISOString(),
      };
    },
  };
  const result = await service(harness.pool, deliveryService).inviteStaff({
    clinicId: 'clinic-1', actorUserId: 'admin-1', fullName: 'Jane Vet',
    email: 'jane@example.com', roleId: 'role-vet',
    professionalTitle: 'Veterinary Surgeon', ipAddress: '127.0.0.1',
  });
  assert.equal(result.delivery.status, 'Submitted');
  assert.equal(result.delivery.emailState, 'Submitted');
  assert.equal(result.delivery.provider, 'resend');
  assert.equal(result.delivery.providerMessageId, 'resend-message-1');
  assert.ok(Date.parse(result.delivery.submittedAt));
  assert.equal(delivered.to, 'jane@example.com');
  assert.equal(delivered.roleName, 'Veterinarian');
  assert.equal(delivered.professionalTitle, 'Veterinary Surgeon');
  assert.equal(delivered.staffNumber, '001');
  assert.match(delivered.activationUrl, /^https:\/\/accounts\.averavet\.sbs\/activate-staff\?token=/);

  await assert.rejects(
    service(staffHarness().pool).inviteStaff({
      clinicId: 'clinic-1', actorUserId: 'admin-1', fullName: 'Stale Role',
      email: 'stale@example.com', roleId: 'role-from-another-clinic',
    }),
    (error) => error.code === 'invalid_clinic_role' && error.statusCode === 400,
  );
});

test('staff invitation resend preserves role, title, and staff number', async () => {
  const harness = staffHarness();
  let delivered;
  const deliveryService = {
    configured: true,
    async sendStaffActivation(message) {
      delivered = message;
      return {
        accepted: true,
        provider: 'resend',
        providerMessageId: 'resend-message-2',
        submittedAt: new Date().toISOString(),
      };
    },
  };
  const originalQuery = harness.pool.query;
  harness.pool.query = originalQuery;
  const client = await harness.pool.connect();
  const originalClientQuery = client.query.bind(client);
  client.query = async (sql, parameters = []) => {
    if (sql.includes('SELECT u.*, c.name AS clinic_name')) {
      return {
        rows: [{
          user_id: 'staff-1',
          clinic_id: 'clinic-1',
          full_name: 'Jane Vet',
          email: 'jane@example.com',
          status: 'PendingActivation',
          clinic_name: 'Ada Veterinary Clinic',
          role_name: 'Veterinarian',
          professional_title: 'Veterinary Surgeon',
          staff_number: '007',
        }],
      };
    }
    return originalClientQuery(sql, parameters);
  };

  const result = await service(harness.pool, deliveryService).resendStaff({
    clinicId: 'clinic-1',
    actorUserId: 'admin-1',
    targetUserId: 'staff-1',
  });

  assert.equal(result.status, 'Submitted');
  assert.equal(result.emailState, 'Submitted');
  assert.equal(result.provider, 'resend');
  assert.equal(result.providerMessageId, 'resend-message-2');
  assert.ok(Date.parse(result.submittedAt));
  assert.equal(delivered.roleName, 'Veterinarian');
  assert.equal(delivered.professionalTitle, 'Veterinary Surgeon');
  assert.equal(delivered.staffNumber, '007');
  assert.equal(
    harness.state.calls.some(({ sql }) =>
      sql.includes('UPDATE clinic_staff_number_sequences')),
    false,
  );
});

test('pending and active duplicate staff invitations return specific safe conflicts', async () => {
  for (const [status, code] of [['PendingActivation', 'invitation_pending'], ['Active', 'email_in_use']]) {
    const harness = staffHarness({
      existingUser: { clinic_id: 'clinic-1', status },
    });
    await assert.rejects(
      service(harness.pool).inviteStaff({
        clinicId: 'clinic-1', actorUserId: 'admin-1', fullName: 'Jane Vet',
        email: 'jane@example.com', roleId: 'role-vet',
      }),
      (error) => error.code === code && error.statusCode === 409,
    );
  }
});

test('staff activation hashes the password, activates membership, and rejects expired or reused links', async () => {
  const harness = staffHarness();
  const password = 'SecureStaff#2026';
  const result = await service(harness.pool).activateStaff({
    rawToken: harness.rawToken, password, confirmPassword: password,
  });
  assert.equal(result.activated, true);
  assert.equal(harness.state.userStatus, 'Active');
  assert.equal(harness.state.membershipStatus, 'Active');
  assert.notEqual(harness.state.passwordHash, password);
  assert.equal(await verifyPassword(password, harness.state.passwordHash), true);
  await assert.rejects(service(harness.pool).activateStaff({
    rawToken: harness.rawToken, password, confirmPassword: password,
  }), /already been used/i);
  await assert.rejects(service(staffHarness({ expired: true }).pool).inspectStaff(
    staffHarness({ expired: true }).rawToken,
  ), /invalid|expired/i);
});

test('resend revokes the previous token and issues a different one', async () => {
  const harness = approvalHarness();
  const activation = service(harness.pool);
  const first = await activation.provisionOnApproval(harness.client, {
    clinicId: 'clinic-1',
    clinicName: 'Ada Veterinary Clinic',
    actorUserId: 'platform-owner-1',
  });
  const originalHash = hashToken(first.issued.rawToken);
  const resent = await activation.resend({
    clinicId: 'clinic-1',
    actorUserId: 'platform-owner-1',
  });

  assert.equal(resent.deliveryMethod, 'manual');
  assert.match(
    resent.activationUrl,
    /^https:\/\/accounts\.averavet\.sbs\/activate-clinic-admin\?token=/,
  );
  const resentToken = new URL(resent.activationUrl).searchParams.get('token');
  assert.notEqual(resentToken, first.issued.rawToken);
  assert.equal(hashToken(resentToken), harness.state.liveToken.token_hash);
  assert.equal(harness.state.tokenInsertCount, 2);
  assert.notEqual(harness.state.liveToken.token_hash, originalHash);
});

test('resend reconciles a missing administrator before issuing activation', async () => {
  const harness = approvalHarness();
  const activation = service(harness.pool);

  const resent = await activation.resend({
    clinicId: 'clinic-1',
    actorUserId: 'platform-owner-1',
    sessionId: 'platform-session-1',
  });

  assert.equal(resent.status, 'PendingActivation');
  assert.equal(resent.email, 'ada@example.com');
  assert.equal(resent.deliveryMethod, 'manual');
  assert.equal(harness.state.user.status, 'PendingActivation');
  assert.equal(harness.state.membershipCount, 1);
  assert.equal(harness.state.tokenInsertCount, 1);
  assert.equal(
    harness.state.calls.filter(({ sql }) => sql.includes('INSERT INTO users')).length,
    1,
  );
  assert.equal(
    harness.state.calls.some(({ sql, parameters }) =>
      sql.includes('INSERT INTO audit_logs') &&
      parameters[4] ===
        'administrator.provisioned_and_activation_submission_requested'),
    true,
  );
});

test('missing administrator exposes repair only when canonical application details are available', async () => {
  const client = {
    async query(sql) {
      if (
        sql === 'BEGIN' ||
        sql === 'COMMIT' ||
        sql === 'ROLLBACK' ||
        sql.includes("set_config('avera.")
      ) {
        return { rows: [] };
      }
      if (sql.includes('FROM users u')) return { rows: [] };
      if (sql.includes('FROM clinics c')) {
        return {
          rows: [{
            clinic_status: 'Active',
            administrator_name: 'Ada Clinic Owner',
            account_email: 'ada@example.com',
          }],
        };
      }
      throw new Error(`Unexpected activation status query: ${sql}`);
    },
    release() {},
  };

  const status = await service({
    connect: async () => client,
    query: (...arguments_) => client.query(...arguments_),
  }).activationStatus('clinic-1');

  assert.equal(status.status, 'NotProvisioned');
  assert.equal(status.canResend, true);
  assert.equal(status.email, 'ada@example.com');
  assert.match(status.reason, /can be repaired/i);
});

test('activation status exposes a persisted provider submission without claiming delivery', async () => {
  const submittedAt = new Date('2026-08-30T08:05:57.938Z');
  const client = {
    async query(sql) {
      if (
        sql === 'BEGIN' ||
        sql === 'COMMIT' ||
        sql === 'ROLLBACK' ||
        sql.includes("set_config('avera.")
      ) {
        return { rows: [] };
      }
      if (sql.includes('FROM users u')) {
        return {
          rows: [{
            full_name: 'Ada Clinic Owner',
            email: 'ada@example.com',
            status: 'PendingActivation',
            expires_at: new Date('2099-08-31T08:05:57.938Z'),
            used_at: null,
            revoked_at: null,
            delivery_method: 'email_submitted',
            delivered_at: submittedAt,
            delivery_reference: 'resend-message-1',
          }],
        };
      }
      throw new Error(`Unexpected activation status query: ${sql}`);
    },
    release() {},
  };

  const status = await service({
    connect: async () => client,
    query: (...arguments_) => client.query(...arguments_),
  }).activationStatus('clinic-1');

  assert.equal(status.emailState, 'Submitted');
  assert.equal(status.deliveryMethod, 'email_submitted');
  assert.equal(status.provider, 'resend');
  assert.equal(status.providerMessageId, 'resend-message-1');
  assert.equal(status.submittedAt, submittedAt);
  assert.equal(status.deliveredAt, null);
});
