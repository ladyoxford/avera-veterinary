import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import Fastify from 'fastify';
import { clinicRoutes } from '../src/routes/clinic-routes.js';

import { ProfilePhotoStorageService } from '../src/services/profile-photo-storage-service.js';

const environment = {
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-secret-value',
  PROFILE_PHOTO_BUCKET: 'profile-photos',
};

test('actual profile DELETE rejects empty JSON but accepts bodyless 204 after database clear', async (t) => {
  const app = Fastify();
  t.after(() => app.close());
  const queries = [];
  let failDatabase = false;
  let cleanupCalls = 0;
  let slowCleanup;
  const client = { release() {}, async query(sql, values) {
    queries.push({ sql, values });
    if (sql.startsWith('UPDATE staff_profiles')) {
      assert.deepEqual(values, ['authenticated-user']);
      if (failDatabase) throw new Error('database unavailable');
    }
    return { rows: sql.startsWith('SELECT profile_photo_path')
      ? [{ profile_photo_path: 'clinic/authenticated-user/avatar.jpg' }] : [] };
  } };
  app.decorate('pool', { connect: async () => client });
  app.decorate('profilePhotoStorage', { async remove(path) {
    cleanupCalls++;
    assert.equal(path, 'clinic/authenticated-user/avatar.jpg');
    if (slowCleanup) return slowCleanup;
    throw new Error('secondary cleanup failed');
  } });
  // Authentication is isolated here; exercise the actual parser and route with
  // a fixed server-side identity, including a malicious query-string user ID.
  app.addHook('onRoute', (options) => {
    options.preHandler = async (request) => {
      request.auth = { userId: 'authenticated-user', clinicId: 'clinic', sessionId: 'session' };
    };
  });
  await clinicRoutes(app);
  const broken = await app.inject({ method: 'DELETE', url: '/api/v1/me/profile-photo',
    headers: { 'content-type': 'application/json' } });
  assert.equal(broken.statusCode, 400);
  assert.equal(broken.json().code, 'FST_ERR_CTP_EMPTY_JSON_BODY');
  assert.equal(queries.length, 0);
  const removed = await app.inject({ method: 'DELETE', url: '/api/v1/me/profile-photo?userId=another-user' });
  assert.equal(removed.statusCode, 204);
  assert.equal(removed.body, '');
  assert.equal(cleanupCalls, 1);
  assert.ok(queries.some(({ sql }) => sql === 'COMMIT'));
  failDatabase = true;
  const failed = await app.inject({ method: 'DELETE', url: '/api/v1/me/profile-photo' });
  assert.equal(failed.statusCode, 500);
  assert.equal(cleanupCalls, 1);
  assert.ok(queries.some(({ sql }) => sql === 'ROLLBACK'));
  failDatabase = false;
  let release;
  slowCleanup = new Promise((resolve) => { release = resolve; });
  let timeout;
  try {
    const response = await Promise.race([
      app.inject({ method: 'DELETE', url: '/api/v1/me/profile-photo' }),
      new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('Response waited for storage cleanup')), 1500); }),
    ]);
    assert.equal(response.statusCode, 204);
  } finally {
    clearTimeout(timeout);
    release();
  }
});

test('profile photo validation accepts images and rejects disguised content', () => {
  const storage = new ProfilePhotoStorageService({ environment });
  assert.doesNotThrow(() => storage.validate({
    contentType: 'image/jpeg',
    bytes: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
  }));
  assert.throws(
    () => storage.validate({ contentType: 'image/png', bytes: Buffer.from('not an image') }),
    /could not be read/,
  );
});

test('profile photos are scoped by clinic and authenticated user identifiers', () => {
  const storage = new ProfilePhotoStorageService({ environment });
  const first = storage.objectPath({ clinicId: 'clinic-a', userId: 'user-a', contentType: 'image/jpeg' });
  const next = storage.objectPath({ clinicId: 'clinic-a', userId: 'user-a', contentType: 'image/jpeg' });
  assert.match(first, /^clinic-a\/user-a\/avatars\/[0-9a-f-]+\.jpg$/);
  assert.notEqual(first, next);
});

test('profile photo object removal accepts missing objects and reports cleanup failures', async () => {
  const missing = new ProfilePhotoStorageService({
    environment,
    fetchImpl: async () => ({ ok: false, status: 404 }),
  });
  await assert.doesNotReject(() => missing.remove('clinic-a/user-a/avatar.jpg'));

  const failed = new ProfilePhotoStorageService({
    environment,
    fetchImpl: async () => ({ ok: false, status: 500 }),
  });
  await assert.rejects(
    () => failed.remove('clinic-a/user-a/avatar.jpg'),
    (error) => error.code === 'profile_photo_delete_failed' && error.statusCode === 502,
  );
});

test('patient profile photos are scoped by clinic and canonical patient identifiers', () => {
  const storage = new ProfilePhotoStorageService({ environment });
  assert.equal(
    storage.patientObjectPath({
      clinicId: 'clinic-a',
      patientId: 'patient-a',
      contentType: 'image/png',
    }),
    'clinic-a/patients/patient-a/avatar.png',
  );
  assert.notEqual(
    storage.patientObjectPath({
      clinicId: 'clinic-a', patientId: 'patient-a', contentType: 'image/jpeg',
    }),
    storage.patientObjectPath({
      clinicId: 'clinic-b', patientId: 'patient-a', contentType: 'image/jpeg',
    }),
  );
});

test('inventory images are scoped by clinic and canonical product identifiers', () => {
  const storage = new ProfilePhotoStorageService({ environment });
  assert.equal(
    storage.inventoryObjectPath({
      clinicId: 'clinic-a',
      inventoryProductId: 'product-a',
      contentType: 'image/jpeg',
    }),
    'clinic-a/inventory/product-a/product.jpg',
  );
  assert.notEqual(
    storage.inventoryObjectPath({
      clinicId: 'clinic-a', inventoryProductId: 'product-a', contentType: 'image/png',
    }),
    storage.inventoryObjectPath({
      clinicId: 'clinic-b', inventoryProductId: 'product-a', contentType: 'image/png',
    }),
  );
});

test('clinic logo replacements use versioned tenant-scoped object paths', () => {
  const storage = new ProfilePhotoStorageService({ environment });
  const first = storage.brandObjectPath({
    clinicId: 'clinic-a',
    kind: 'logo',
    contentType: 'image/png',
  });
  const replacement = storage.brandObjectPath({
    clinicId: 'clinic-a',
    kind: 'logo',
    contentType: 'image/png',
  });
  const otherClinic = storage.brandObjectPath({
    clinicId: 'clinic-b',
    kind: 'logo',
    contentType: 'image/png',
  });
  assert.match(first, /^clinic-a\/branding\/logo\/[0-9a-f-]+\.png$/);
  assert.notEqual(first, replacement);
  assert.match(otherClinic, /^clinic-b\/branding\/logo\//);
});

test('clinic settings expose a durable logo reference and no active banner', async () => {
  const source = await readFile(new URL('../src/routes/clinic-routes.js', import.meta.url), 'utf8');
  const settings = source.slice(
    source.indexOf("app.get('/api/v1/clinic/settings'"),
    source.indexOf("app.patch('/api/v1/clinic/settings'"),
  );
  const branding = source.slice(
    source.indexOf("app.post('/api/v1/clinic/branding'"),
    source.indexOf("app.patch('/api/v1/clinic/theme-color'"),
  );
  assert.match(settings, /logoReference: clinic\.logoPath/);
  assert.doesNotMatch(settings, /bannerUrl/);
  assert.match(branding, /return \{ reference: path, url:/);
  assert.match(branding, /requirePermission\(permissions\.clinicSettingsEdit\)/);
});

test('patient photo route requires edit permission and tenant-scoped UUID lookup', async () => {
  const source = await readFile(new URL('../src/routes/clinical-routes.js', import.meta.url), 'utf8');
  const start = source.indexOf("app.post('/api/v1/patients/:patientId/profile-photo'");
  const end = source.indexOf("app.get('/api/v1/patients/:patientId/medical-file'", start);
  const route = source.slice(start, end);

  assert.ok(start >= 0);
  assert.match(route, /requirePermission\(permissions\.patientsEdit\)/);
  assert.match(route, /uuidSchema\.safeParse\(request\.params\)/);
  assert.match(route, /WHERE clinic_id = \$1 AND patient_id = \$2 AND deleted_at IS NULL/);
  assert.match(route, /request\.auth\.clinicId, params\.data\.patientId/);
  assert.match(route, /patient\.photo_updated/);
  assert.doesNotMatch(route, /profile_photo_path:/);
});

test('inventory photo route requires edit permission and tenant-scoped product lookup', async () => {
  const source = await readFile(new URL('../src/routes/clinical-routes.js', import.meta.url), 'utf8');
  const start = source.indexOf("app.post('/api/v1/inventory/products/:inventoryProductId/photo'");
  const end = source.indexOf("app.get('/api/v1/inventory/products/:inventoryProductId/units'", start);
  const route = source.slice(start, end);

  assert.ok(start >= 0);
  assert.match(route, /requirePermission\(permissions\.inventoryEdit\)/);
  assert.match(route, /inventoryUuidSchema\.safeParse\(request\.params\)/);
  assert.match(route, /WHERE clinic_id=\$1 AND inventory_product_id=\$2/);
  assert.match(route, /request\.auth\.clinicId, params\.data\.inventoryProductId/);
  assert.match(route, /inventory\.photo_updated/);
  assert.doesNotMatch(route, /image_path:/);
});

test('self profile routes never accept a target user id', async () => {
  const source = await readFile(new URL('../src/routes/clinic-routes.js', import.meta.url), 'utf8');
  for (const route of ['/api/v1/me/profile', '/api/v1/me/profile-photo']) {
    assert.match(source, new RegExp(route.replaceAll('/', '\\/')));
  }
  const selfSection = source.slice(source.indexOf("app.get('/api/v1/me/profile'"), source.indexOf("app.post('/api/v1/users/invitations'"));
  assert.match(selfSection, /request\.auth\.userId/);
  assert.doesNotMatch(selfSection, /request\.params\.userId/);
  const removal = selfSection.slice(
    selfSection.indexOf("app.delete('/api/v1/me/profile-photo'"),
  );
  assert.match(removal, /withTenantTransaction/);
  assert.match(removal, /profile\.photo_removed/);
  assert.match(removal, /\.catch\(\(\) => \{[\s\S]*request\.log\.warn/);
  assert.match(removal, /reply\.code\(204\)\.send\(\)/);
});

test('clinic staff routes await tenant queries before reading rows', async () => {
  const source = await readFile(new URL('../src/routes/clinic-routes.js', import.meta.url), 'utf8');
  const listStart = source.indexOf("app.get('/api/v1/users'");
  const detailStart = source.indexOf("app.get('/api/v1/users/:userId'");
  const rolesStart = source.indexOf("app.get('/api/v1/roles'");
  const listRoute = source.slice(listStart, detailStart);
  const detailRoute = source.slice(detailStart, rolesStart);

  assert.match(listRoute, /const usersResult = await withTenantTransaction/);
  assert.match(listRoute, /const users = usersResult\.rows/);
  assert.match(detailRoute, /const userResult = await withTenantTransaction/);
  assert.match(detailRoute, /const user = userResult\.rows\[0\]/);
});
