import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const routes = readFileSync(new URL('../src/routes/clinical-routes.js', import.meta.url), 'utf8');
const revenue = readFileSync(new URL('../src/services/revenue-report-service.js', import.meta.url), 'utf8');
const permissions = readFileSync(new URL('../src/security/permissions.js', import.meta.url), 'utf8');
const migration = readFileSync(new URL('../migrations/032_records_archive_and_invoice_voiding.sql', import.meta.url), 'utf8');

test('active lists and revenue exclude voided invoices', () => {
  assert.match(routes, /i\.status <> 'Voided'/);
  assert.match(revenue, /AND i\.status <> 'Voided'/);
  assert.match(routes, /status <> 'Voided' AND balance > 0/);
});

test('invoice voiding is tenant scoped, permission protected, and reverses stock once', () => {
  assert.match(permissions, /billingVoid: 'billing\.void'/);
  assert.match(routes, /requirePermission\(permissions\.billingVoid\)/);
  assert.match(routes, /WHERE clinic_id=\$1 AND invoice_id=\$2 FOR UPDATE/);
  assert.match(routes, /if \(invoice\.inventory_deducted_at\)/);
  assert.match(routes, /'Invoice Void Reversal'/);
  assert.match(routes, /inventory_deducted_at=NULL/);
  assert.match(routes, /action: 'invoice\.voided'/);
});

test('inventory archive stores reason and preserves rows', () => {
  assert.match(routes, /reason: z\.enum\(\['Retired', 'OutOfStock'\]\)/);
  assert.match(routes, /is_archived=true/);
  assert.match(routes, /action: parsed\.data\.reason === 'OutOfStock' \? 'inventory\.out_of_stock' : 'inventory\.retired'/);
  assert.match(migration, /archive_reason TEXT/);
  assert.match(migration, /void_reason TEXT/);
  assert.doesNotMatch(routes, /DELETE FROM invoices/);
});
