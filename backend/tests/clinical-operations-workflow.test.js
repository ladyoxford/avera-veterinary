import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { clinicalOperationTransitions } from '../src/routes/clinical-routes.js';

test('all persisted clinical operation types have canonical transition graphs', () => {
  assert.deepEqual(Object.keys(clinicalOperationTransitions).sort(), [
    'Document', 'Imaging', 'Prescription', 'Surgery', 'Treatment',
  ]);
  assert.deepEqual(clinicalOperationTransitions.Surgery.Scheduled, [
    'Pre-operative', 'Cancelled',
  ]);
  assert.deepEqual(clinicalOperationTransitions.Surgery.Recovery, ['Completed']);
  assert.equal(clinicalOperationTransitions.Surgery.Completed, undefined);
  assert.ok(clinicalOperationTransitions.Treatment.Due.includes('Administered'));
  assert.ok(clinicalOperationTransitions.Imaging.Requested.includes('Scheduled'));
});

test('clinical operation detail and status routes enforce production safeguards', () => {
  const source = fs.readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(source, /app\.get\('\/api\/v1\/clinical-operations\/:operationId'/);
  assert.match(source, /app\.patch\('\/api\/v1\/clinical-operations\/:operationId\/status'/);
  assert.match(source, /WHERE r\.clinic_id=\$1 AND r\.operation_id=\$2/);
  assert.match(source, /FOR UPDATE/);
  assert.match(source, /invalid_status_transition/);
  assert.match(source, /clinicalOperationStatusPermission/);
  assert.match(source, /clinical_operation\.status_changed/);
  assert.match(source, /reason_required/);
});
