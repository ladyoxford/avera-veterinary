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
