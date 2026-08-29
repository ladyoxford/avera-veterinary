import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { buildApp } from '../src/app.js';
import { sanitizeRequestUrl } from '../src/config/request-logging.js';

const fingerprint = '24:1E:7E:3A:D4:D4:59:5F:0C:D8:61:65:39:48:16:69:7E:1D:2A:4D:0E:E6:4E:78:E9:45:35:FD:4B:F7:73:7F';

test('asset links delegates the verified HTTPS host to the production Android app', async (context) => {
  const app = await buildApp({ environment: testEnvironment(), pool: unusedPool() });
  context.after(() => app.close());
  const response = await app.inject({ method: 'GET', url: '/.well-known/assetlinks.json' });
  assert.equal(response.statusCode, 200);
  const links = response.json();
  assert.equal(links[0].target.package_name, 'com.avera.vet');
  assert.deepEqual(links[0].relation, ['delegate_permission/common.handle_all_urls']);
  assert.deepEqual(links[0].target.sha256_cert_fingerprints, [fingerprint]);
});

test('fallback page contains no browser password form and never renders the activation token', async (context) => {
  const app = await buildApp({ environment: testEnvironment(), pool: unusedPool() });
  context.after(() => app.close());
  const secret = 'activation-secret-that-must-not-be-rendered';
  const response = await app.inject({
    method: 'GET',
    url: `/activate-clinic-admin?token=${secret}`,
  });
  assert.equal(response.statusCode, 200);
  assert.match(response.body, /Opening AVERA/);
  assert.match(response.body, /Open AVERA/);
  assert.doesNotMatch(response.body, new RegExp(secret));
  assert.doesNotMatch(response.body, /type=["']password/i);
  assert.equal(response.headers['cache-control'], 'no-store, max-age=0');
  assert.equal(response.headers['referrer-policy'], 'no-referrer');
});

test('staff activation fallback is token-safe and contains no browser password form', async (context) => {
  const app = await buildApp({ environment: testEnvironment(), pool: unusedPool() });
  context.after(() => app.close());
  const secret = 'staff-activation-secret-that-must-not-be-rendered';
  const response = await app.inject({
    method: 'GET',
    url: `/activate-staff?token=${secret}`,
  });
  assert.equal(response.statusCode, 200);
  assert.match(response.body, /Opening AVERA/);
  assert.doesNotMatch(response.body, new RegExp(secret));
  assert.doesNotMatch(response.body, /type=["']password/i);
});

test('backend starts without social OAuth configuration and exposes email auth only', async (context) => {
  const app = await buildApp({ environment: testEnvironment(), pool: unusedPool() });
  context.after(() => app.close());

  const emailAuth = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/sign-in',
    payload: {},
  });
  assert.equal(emailAuth.statusCode, 400);

  const providerStart = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/provider/start',
    payload: {},
  });
  const providerVerify = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/provider/link/verify',
    payload: {},
  });
  assert.equal(providerStart.statusCode, 404);
  assert.equal(providerVerify.statusCode, 404);
});

test('activation query tokens are removed from application request logs', () => {
  const secret = 'do-not-log-this-token';
  const sanitized = sanitizeRequestUrl(`/activate-clinic-admin?token=${secret}`);
  assert.equal(sanitized, '/activate-clinic-admin');
  assert.equal(sanitized.includes(secret), false);
  assert.equal(sanitizeRequestUrl('/health/ready'), '/health/ready');
});

test('Android manifest and production environment use the verified account domain', () => {
  const manifest = fs.readFileSync(
    new URL('../../android/app/src/main/AndroidManifest.xml', import.meta.url),
    'utf8',
  );
  assert.match(manifest, /android:autoVerify="true"/);
  assert.match(manifest, /android:scheme="https"/);
  assert.match(manifest, /android:host="accounts\.averavet\.sbs"/);
  assert.match(manifest, /android:pathPrefix="\/activate-clinic-admin"/);
  assert.match(manifest, /android:pathPrefix="\/activate-staff"/);
});

function unusedPool() {
  return {
    async query() {
      throw new Error('The public App Link routes must not query the database.');
    },
  };
}

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
    PAYSTACK_CURRENCY: 'NGN',
    allowedOrigins: ['http://localhost'],
    ACTIVATION_TOKEN_TTL_MINUTES: 60,
    AVERA_ACTIVATION_BASE_URL: 'https://accounts.averavet.sbs/activate-clinic-admin',
  };
}
