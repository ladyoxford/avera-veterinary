import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import { compactInvoiceNumber } from '../src/services/invoice-number.js';

const now = new Date('2026-08-30T08:50:00.000Z');
const submissionId = 'a1b2c3d4-e5f6-4111-8111-111111111111';

test('future invoice numbers use a deterministic UTC date and 48-bit token', () => {
  const invoiceNumber = compactInvoiceNumber(submissionId, now);

  assert.equal(invoiceNumber, 'INV-260830-A1B2C3D4E5F6');
  assert.match(invoiceNumber, /^INV-\d{6}-[A-F0-9]{12}$/);
  assert.equal(compactInvoiceNumber(submissionId, now), invoiceNumber);
  assert.equal(invoiceNumber.split('-').at(-1).includes('-'), false);
});

test('submission identity and invoice date both contribute to the number', () => {
  const first = compactInvoiceNumber(
    submissionId,
    now,
  );
  const second = compactInvoiceNumber(
    'f5e6d7c8-2222-4222-8222-222222222222',
    now,
  );
  const nextDay = compactInvoiceNumber(
    submissionId,
    new Date('2026-08-31T00:00:00.000Z'),
  );

  assert.notEqual(first, second);
  assert.notEqual(first, nextDay);
});

test('lowercase UUID input produces an uppercase token without hyphens', () => {
  const invoiceNumber = compactInvoiceNumber(submissionId, now);
  const token = invoiceNumber.split('-').at(-1);

  assert.equal(token, 'A1B2C3D4E5F6');
  assert.doesNotMatch(token, /-/);
});

test('malformed or insufficient submission IDs are rejected', () => {
  for (const value of ['', 'a1b2c3d4', 'not-a-uuid', 'a1b2c3d4-e5f6']) {
    assert.throws(
      () => compactInvoiceNumber(value, now),
      /submission ID must be a valid UUID/,
    );
  }
  assert.throws(
    () => compactInvoiceNumber(submissionId, new Date('invalid')),
    /creation date must be valid/,
  );
});

test('PostgreSQL keeps invoice number uniqueness clinic-scoped', () => {
  const migration = fs.readFileSync(
    new URL('../migrations/004_demo_clinical_domain.sql', import.meta.url),
    'utf8',
  );

  assert.match(migration, /UNIQUE\s*\(clinic_id,\s*invoice_number\)/i);
});
