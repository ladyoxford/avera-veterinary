import assert from 'node:assert/strict';
import {
  createHash,
  generateKeyPairSync,
  sign,
} from 'node:crypto';
import test from 'node:test';

import { ProviderTokenVerifier } from '../src/security/provider-token-verifier.js';
import { SocialAuthService } from '../src/services/social-auth-service.js';

test('matching provider email requires a single-use code before linking one user', async () => {
  const harness = socialHarness({
    users: [{
      user_id: 'user-1',
      email: 'doctor@clinic.test',
      user_status: 'Active',
      account_type: 'ClinicAdministrator',
    }],
  });

  const started = await harness.service.begin({
    provider: 'google',
    idToken: 'google-doctor',
    ipAddress: '127.0.0.1',
  });

  assert.equal(started.action, 'verification_required');
  assert.equal(started.maskedEmail, 'do****@clinic.test');
  assert.equal(harness.state.links.length, 0);
  assert.equal(harness.delivery.messages.length, 1);
  assert.equal('code' in started, false);

  const deliveredCode = harness.delivery.messages[0].code;
  const wrongCode = deliveredCode === '000000' ? '000001' : '000000';
  await assert.rejects(
    harness.service.verify({ challengeId: started.challengeId, code: wrongCode }),
    (error) => error.code === 'provider_link_code_invalid',
  );
  assert.equal(
    harness.state.challenges.get(started.challengeId).attempts_remaining,
    4,
  );

  const verified = await harness.service.verify({
    challengeId: started.challengeId,
    code: deliveredCode,
  });
  assert.equal(verified.action, 'sign_in');
  assert.equal(verified.userId, 'user-1');
  assert.equal(harness.state.links.length, 1);

  await assert.rejects(
    harness.service.verify({
      challengeId: started.challengeId,
      code: deliveredCode,
    }),
    (error) => error.code === 'provider_link_code_used',
  );

  const nextSignIn = await harness.service.begin({
    provider: 'google',
    idToken: 'google-doctor',
  });
  assert.equal(nextSignIn.action, 'sign_in');
  assert.equal(nextSignIn.userId, 'user-1');
  assert.equal(harness.delivery.messages.length, 1);
});

test('invited staff remains in staff activation after secure provider linking', async () => {
  const harness = socialHarness({
    users: [{
      user_id: 'staff-1',
      email: 'vet@clinic.test',
      user_status: 'Invited',
      account_type: 'ClinicStaff',
    }],
  });
  const started = await harness.service.begin({
    provider: 'google',
    idToken: 'google-vet',
  });
  const outcome = await harness.service.verify({
    challengeId: started.challengeId,
    code: harness.delivery.messages[0].code,
  });

  assert.equal(outcome.action, 'staff_activation_required');
  assert.match(outcome.message, /staff activation/i);
  assert.equal(harness.state.links[0].user_id, 'staff-1');
});

test('unfinished applications resume while verified payments remain pending approval', async () => {
  const harness = socialHarness({
    applications: [{
      application_id: 'application-1',
      administrator_email: 'owner@clinic.test',
      status: 'AwaitingPayment',
      payment_status: 'Pending',
    }],
  });

  const draft = await harness.service.begin({
    provider: 'google',
    idToken: 'google-owner',
  });
  assert.equal(draft.action, 'resume_registration');
  assert.equal(draft.application.application_id, 'application-1');
  assert.equal(harness.delivery.messages.length, 0);

  harness.state.applications[0].status = 'Pending';
  const legacyUnpaid = await harness.service.begin({
    provider: 'google',
    idToken: 'google-owner',
  });
  assert.equal(legacyUnpaid.action, 'resume_registration');

  harness.state.applications[0].payment_status = 'Paid';
  const paid = await harness.service.begin({
    provider: 'google',
    idToken: 'google-owner',
  });
  assert.equal(paid.action, 'application_pending');
});

test('rejected and suspended applications remain restricted instead of starting over', async () => {
  const harness = socialHarness({
    applications: [{
      application_id: 'application-restricted',
      administrator_email: 'owner@clinic.test',
      status: 'Rejected',
      payment_status: 'Pending',
    }],
  });

  const rejected = await harness.service.begin({
    provider: 'google',
    idToken: 'google-owner',
  });
  assert.equal(rejected.action, 'application_restricted');
  assert.match(rejected.message, /not approved/i);

  harness.state.applications[0].status = 'Suspended';
  const suspended = await harness.service.begin({
    provider: 'google',
    idToken: 'google-owner',
  });
  assert.equal(suspended.action, 'application_restricted');
  assert.match(suspended.message, /suspended/i);
});

test('Apple private relay requires an explicit existing email and verifies it before resume', async () => {
  const harness = socialHarness({
    applications: [{
      application_id: 'application-apple',
      administrator_email: 'owner@clinic.test',
      status: 'AwaitingPayment',
      payment_status: 'Pending',
    }],
  });

  const unresolved = await harness.service.begin({
    provider: 'apple',
    idToken: 'apple-relay',
    nonce: 'secure-nonce',
  });
  assert.equal(unresolved.action, 'account_email_required');

  const linking = await harness.service.begin({
    provider: 'apple',
    idToken: 'apple-relay',
    nonce: 'secure-nonce',
    existingEmail: 'owner@clinic.test',
  });
  assert.equal(linking.action, 'verification_required');
  const resumed = await harness.service.verify({
    challengeId: linking.challengeId,
    code: harness.delivery.messages[0].code,
  });
  assert.equal(resumed.action, 'resume_registration');
  assert.equal(resumed.application.application_id, 'application-apple');
  assert.equal(harness.state.links.length, 0);
});

test('provider verifier validates Google audience and Apple signature, audience, and nonce', async () => {
  const nonce = 'a-secure-raw-apple-nonce';
  const { privateKey, publicKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
  const publicJwk = publicKey.export({ format: 'jwk' });
  Object.assign(publicJwk, { kid: 'apple-test-key', alg: 'RS256', use: 'sig' });
  const appleToken = signedAppleToken({ privateKey, nonce });
  const verifier = new ProviderTokenVerifier({
    environment: {
      GOOGLE_OAUTH_CLIENT_IDS: 'google-client-id',
      APPLE_OAUTH_CLIENT_IDS: 'com.avera.app',
    },
    fetchImpl: async (url) => {
      if (String(url).startsWith('https://oauth2.googleapis.com/tokeninfo')) {
        return response({
          iss: 'https://accounts.google.com',
          aud: 'google-client-id',
          exp: Math.floor(Date.now() / 1000) + 300,
          sub: 'google-subject',
          email: 'Doctor@Clinic.Test',
          email_verified: 'true',
        });
      }
      return response({ keys: [publicJwk] });
    },
  });

  const google = await verifier.verify({
    provider: 'google',
    idToken: 'server-validated-token',
  });
  assert.equal(google.subject, 'google-subject');
  assert.equal(google.email, 'doctor@clinic.test');

  const apple = await verifier.verify({
    provider: 'apple',
    idToken: appleToken,
    nonce,
  });
  assert.equal(apple.subject, 'apple-subject');
  assert.equal(apple.isPrivateRelay, true);

  await assert.rejects(
    verifier.verify({
      provider: 'apple',
      idToken: appleToken,
      nonce: 'wrong-nonce',
    }),
    (error) => error.code === 'provider_token_invalid',
  );
});

function socialHarness({ users = [], applications = [] } = {}) {
  const state = {
    users: users.map((item) => ({ ...item })),
    applications: applications.map((item) => ({ ...item })),
    links: [],
    challenges: new Map(),
  };
  const identities = {
    'google-doctor': googleIdentity('google-doctor-sub', 'doctor@clinic.test'),
    'google-vet': googleIdentity('google-vet-sub', 'vet@clinic.test'),
    'google-owner': googleIdentity('google-owner-sub', 'owner@clinic.test'),
    'apple-relay': {
      provider: 'apple',
      subject: 'apple-relay-sub',
      email: 'relay@privaterelay.appleid.com',
      emailVerified: true,
      isPrivateRelay: true,
    },
  };
  const delivery = {
    configured: true,
    messages: [],
    async sendProviderLinkCode(message) {
      delivery.messages.push(message);
    },
  };
  const client = {
    async query(sql, parameters = []) {
      const query = sql.replace(/\s+/g, ' ').trim();
      if (
        ['BEGIN', 'COMMIT', 'ROLLBACK'].includes(query) ||
        query.includes("set_config('avera.")
      ) {
        return { rows: [] };
      }
      if (query.includes('FROM user_auth_providers p')) {
        const link = state.links.find(
          (item) =>
            item.provider_type === parameters[0] &&
            item.provider_subject === parameters[1],
        );
        const user = link
          ? state.users.find((item) => item.user_id === link.user_id)
          : null;
        return {
          rows: user
            ? [{
                user_id: user.user_id,
                user_status: user.user_status,
                account_type: user.account_type,
              }]
            : [],
        };
      }
      if (query.startsWith('UPDATE user_auth_providers')) return { rows: [] };
      if (query.includes('FROM users') && query.includes('lower(email::text)')) {
        const email = String(parameters[0]).toLowerCase();
        const user = state.users.find(
          (item) => String(item.email).toLowerCase() === email,
        );
        return { rows: user ? [{ ...user }] : [] };
      }
      if (
        query.includes('FROM clinic_applications') &&
        query.includes('lower(administrator_email::text)')
      ) {
        const email = String(parameters[0]).toLowerCase();
        const application = state.applications.find(
          (item) => String(item.administrator_email).toLowerCase() === email,
        );
        return { rows: application ? [{ ...application }] : [] };
      }
      if (
        query.startsWith('UPDATE auth_provider_link_challenges') &&
        query.includes('revoked_at = now()')
      ) {
        for (const challenge of state.challenges.values()) {
          if (
            challenge.provider_type === parameters[0] &&
            challenge.provider_subject === parameters[1] &&
            !challenge.used_at &&
            !challenge.revoked_at
          ) {
            challenge.revoked_at = new Date();
          }
        }
        return { rows: [] };
      }
      if (query.startsWith('INSERT INTO auth_provider_link_challenges')) {
        state.challenges.set(parameters[0], {
          challenge_id: parameters[0],
          provider_type: parameters[1],
          provider_subject: parameters[2],
          provider_email: parameters[3],
          target_email: parameters[4],
          target_user_id: parameters[5],
          target_application_id: parameters[6],
          code_hash: parameters[7],
          attempts_remaining: parameters[8],
          expires_at: parameters[9],
          requested_from_ip: parameters[10],
          used_at: null,
          revoked_at: null,
        });
        return { rows: [] };
      }
      if (
        query.includes('FROM auth_provider_link_challenges') &&
        query.includes('FOR UPDATE')
      ) {
        const challenge = state.challenges.get(parameters[0]);
        return { rows: challenge ? [{ ...challenge }] : [] };
      }
      if (
        query.startsWith('UPDATE auth_provider_link_challenges') &&
        query.includes('attempts_remaining = attempts_remaining - 1')
      ) {
        state.challenges.get(parameters[0]).attempts_remaining -= 1;
        return { rows: [] };
      }
      if (query.includes('SELECT user_id FROM user_auth_providers')) {
        const link = state.links.find(
          (item) =>
            item.provider_type === parameters[0] &&
            item.provider_subject === parameters[1],
        );
        return { rows: link ? [{ user_id: link.user_id }] : [] };
      }
      if (query.startsWith('INSERT INTO user_auth_providers')) {
        const existing = state.links.find(
          (item) =>
            item.user_id === parameters[0] &&
            item.provider_type === parameters[1],
        );
        const value = {
          user_id: parameters[0],
          provider_type: parameters[1],
          provider_subject: parameters[2],
          provider_email: parameters[3],
        };
        if (existing) Object.assign(existing, value);
        else state.links.push(value);
        return { rows: [] };
      }
      if (
        query.startsWith('UPDATE auth_provider_link_challenges') &&
        query.includes('used_at = now()')
      ) {
        state.challenges.get(parameters[0]).used_at = new Date();
        return { rows: [] };
      }
      if (query.includes('FROM users WHERE user_id = $1')) {
        const user = state.users.find((item) => item.user_id === parameters[0]);
        return { rows: user ? [{ ...user }] : [] };
      }
      if (query.includes('FROM clinic_applications WHERE application_id = $1')) {
        const application = state.applications.find(
          (item) => item.application_id === parameters[0],
        );
        return { rows: application ? [{ ...application }] : [] };
      }
      throw new Error(`Unexpected social-auth query: ${query}`);
    },
    release() {},
  };
  const pool = {
    async connect() {
      return client;
    },
    query: (...arguments_) => client.query(...arguments_),
  };
  return {
    state,
    delivery,
    service: new SocialAuthService({
      pool,
      deliveryService: delivery,
      tokenVerifier: {
        async verify({ idToken }) {
          const identity = identities[idToken];
          if (!identity) throw new Error(`Unknown identity token: ${idToken}`);
          return identity;
        },
      },
    }),
  };
}

function googleIdentity(subject, email) {
  return {
    provider: 'google',
    subject,
    email,
    emailVerified: true,
    isPrivateRelay: false,
  };
}

function signedAppleToken({ privateKey, nonce }) {
  const header = base64Url({ alg: 'RS256', kid: 'apple-test-key' });
  const claims = base64Url({
    iss: 'https://appleid.apple.com',
    aud: 'com.avera.app',
    exp: Math.floor(Date.now() / 1000) + 300,
    sub: 'apple-subject',
    email: 'relay@privaterelay.appleid.com',
    email_verified: 'true',
    nonce: createHash('sha256').update(nonce).digest('hex'),
  });
  const signature = sign(
    'RSA-SHA256',
    Buffer.from(`${header}.${claims}`),
    privateKey,
  ).toString('base64url');
  return `${header}.${claims}.${signature}`;
}

function base64Url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function response(body, ok = true) {
  return { ok, async json() { return body; } };
}
