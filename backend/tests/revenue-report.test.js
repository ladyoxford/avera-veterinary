import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  allocateSignedLedgerCost,
  loadRevenueDrilldown,
  loadRevenueSummary,
  reportCte,
  revenueDrilldownMetrics,
  signedLedgerAmount,
} from '../src/services/revenue-report-service.js';

test('signed ledger treats receipts as positive and refunds as negative', () => {
  assert.equal(signedLedgerAmount({ amount: 100 }), 100);
  assert.equal(
    signedLedgerAmount({ amount: 25, transactionType: 'Refund' }),
    -25,
  );
  assert.equal(
    signedLedgerAmount({ amount: -25, transactionType: 'Refund' }),
    -25,
  );
});

test('signed cost allocation handles payments and refund periods symmetrically', () => {
  const allocation = (netSignedAmount) => allocateSignedLedgerCost({
    recordedCost: 40,
    netSignedAmount,
    invoiceTotal: 100,
  });

  assert.equal(allocation(100), 40, 'payment only');
  assert.equal(allocation(40), 16, 'partial payment');
  assert.equal(allocation(70), 28, 'multiple payments');
  assert.equal(allocation(50), 20, 'payments and partial refund in one period');
  assert.equal(allocation(0), 0, 'full refund in the same period');
  assert.equal(allocation(-25), -10, 'refund in a later period');
  assert.equal(allocation(130), 40, 'cost is capped at the full invoice cost');
});

test('PostgreSQL report uses raw signed amounts without a zero floor', () => {
  assert.match(reportCte, /p\.amount AS signed_amount/);
  assert.match(reportCte, /sum\(signed_amount\) AS paid_in_range/);
  assert.match(reportCte, /least\(pbi\.paid_in_range \/ pbi\.total, 1\)/);
  assert.doesNotMatch(reportCte, /greatest\(/i);
});

test('summary and drill-down use the same tenant/date filtered report CTE', async () => {
  const calls = [];
  const client = {
    async query(sql, values) {
      calls.push({ sql, values });
      if (sql.includes('AS total_value')) {
        return { rows: [{ total_value: '1250.00', total_count: 1 }] };
      }
      if (sql.includes("'payment' AS row_type")) {
        return { rows: [{ id: 'payment-1' }] };
      }
      return {
        rows: [{
          revenue: '1250.00',
          cost: '250.00',
          clinic_revenue: '1250.00',
          farm_revenue: '0',
          transaction_count: 1,
          missing_cost_lines: 0,
        }],
      };
    },
  };
  const period = {
    clinicId: 'clinic-a',
    from: '2026-08-01T00:00:00.000Z',
    to: '2026-09-01T00:00:00.000Z',
  };

  await loadRevenueSummary(client, period);
  const page = await loadRevenueDrilldown(client, {
    ...period,
    metric: 'revenue',
    page: 1,
    pageSize: 25,
  });

  assert.equal(page.totalValue, '1250.00');
  assert.equal(page.total, 1);
  assert.ok(calls.every((call) => call.values[0] === 'clinic-a'));
  assert.ok(calls.every((call) => call.sql.includes('FROM payments p')));
  assert.ok(calls.every((call) => call.sql.includes('p.clinic_id=$1')));
  assert.ok(calls.every((call) => call.sql.includes('p.paid_at >= $2')));
  assert.ok(calls.every((call) => call.sql.includes('p.paid_at < $3')));
  const summarySql = calls[0].sql;
  assert.match(
    summarySql,
    /CASE WHEN context_type='farm_visit'[\s\S]*THEN paid_in_range ELSE 0 END/,
  );
  assert.match(
    summarySql,
    /CASE WHEN context_type<>'farm_visit'[\s\S]*THEN paid_in_range ELSE 0 END/,
  );
  assert.match(summarySql, /sum\(transaction_count\)/);
});

test('financial endpoint remains authenticated, permission guarded, and paginated', () => {
  assert.deepEqual(revenueDrilldownMetrics, [
    'revenue',
    'gross_profit',
    'recorded_cost',
    'clinic_revenue',
    'farm_revenue',
    'settled_transactions',
  ]);
  const routes = readFileSync(
    new URL('../src/routes/clinical-routes.js', import.meta.url),
    'utf8',
  );
  assert.match(routes, /\/api\/v1\/billing\/revenue-drilldown/);
  assert.match(
    routes,
    /revenue-drilldown'[\s\S]{0,180}authenticate[\s\S]{0,120}permissions\.billingHistory/,
  );
  assert.match(routes, /pageSize: z\.coerce\.number\(\)\.int\(\)\.min\(1\)\.max\(100\)/);
});
