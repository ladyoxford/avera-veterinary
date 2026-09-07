import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { ProfilePhotoStorageService } from '../src/services/profile-photo-storage-service.js';

const environment = {
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-secret-value',
  PROFILE_PHOTO_BUCKET: 'profile-photos',
};

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
  assert.equal(
    storage.objectPath({ clinicId: 'clinic-a', userId: 'user-a', contentType: 'image/jpeg' }),
    'clinic-a/user-a/avatar.jpg',
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
