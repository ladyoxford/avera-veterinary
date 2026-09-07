import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { patientNumberingSettingsSchema } from '../src/routes/clinical-routes.js';

test('patient numbering settings accept only collision-resistant supported formats', () => {
  assert.deepEqual(patientNumberingSettingsSchema.parse({
    prefix: ' crest2 ',
    sequenceLength: 6,
    resetYearly: false,
  }), {
    prefix: 'CREST2',
    sequenceLength: 6,
    resetYearly: false,
  });
  for (const invalid of [
    { prefix: '', sequenceLength: 6, resetYearly: true },
    { prefix: 'A-', sequenceLength: 6, resetYearly: true },
    { prefix: 'VALID', sequenceLength: 3, resetYearly: true },
    { prefix: 'VALID', sequenceLength: 11, resetYearly: true },
  ]) {
    assert.equal(patientNumberingSettingsSchema.safeParse(invalid).success, false);
  }
});

test('numbering settings are tenant scoped while preview remains non-consuming', async () => {
  const source = await readFile(new URL('../src/routes/clinical-routes.js', import.meta.url), 'utf8');
  const settingsStart = source.indexOf("app.put('/api/v1/patients/numbering-settings'");
  const createStart = source.indexOf("app.post('/api/v1/patients'", settingsStart);
  const settings = source.slice(settingsStart, createStart);
  const preview = source.slice(
    source.indexOf("app.get('/api/v1/patients/number-preview'"),
    settingsStart,
  );
  const create = source.slice(createStart, source.indexOf("app.get('/api/v1/patients/:patientId'", createStart));

  assert.match(settings, /requirePermission\(permissions\.patientsNumberingManage\)/);
  assert.match(settings, /WHERE clinic_id=\$5/);
  assert.match(settings, /request\.auth\.clinicId/);
  assert.match(settings, /hospital_number\.settings_changed/);
  assert.doesNotMatch(preview, /UPDATE clinic_number_sequences/);
  assert.match(create, /FOR UPDATE/);
  assert.match(create, /clinic_number_sequences/);
  assert.match(create, /UNIQUE|duplicate|registration_submission_id/i);
});
