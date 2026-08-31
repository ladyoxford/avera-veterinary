import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const routes = fs.readFileSync(
  new URL('../src/routes/clinical-routes.js', import.meta.url),
  'utf8',
);

test('product cost snapshots preserve null, zero, and converted positive costs', () => {
  assert.match(
    routes,
    /unitCost:\s*row\.purchase_price == null\s*\n\s*\? null\s*\n\s*:\s*Number\(row\.purchase_price\) \* conversion/,
  );

  const snapshotCost = (purchasePrice, conversion) => (
    purchasePrice == null ? null : Number(purchasePrice) * conversion
  );

  assert.equal(snapshotCost(null, 10), null);
  assert.equal(snapshotCost(0, 10), 0);
  assert.equal(snapshotCost(125, 10), 1250);
});
