import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createInvoiceSchema,
  deductInvoiceInventory,
  prepareProductLines,
} from '../src/routes/clinical-routes.js';
import { compactInvoiceNumber } from '../src/services/invoice-number.js';
import { permissions } from '../src/security/permissions.js';

const submissionId = '5f89862e-e0e4-46f5-a6ab-b48c2ed35214';
const productId = '25f96ec9-11bf-4934-ad17-46c69e4a1a2e';

function retailInput(overrides = {}) {
  return {
    submissionId,
    contextType: 'retail_sale',
    patientId: null,
    patientIds: [],
    clientName: null,
    clientPhone: null,
    status: 'Unpaid',
    subtotal: 4000,
    total: 4000,
    services: [],
    products: [{ inventoryProductId: productId, quantity: 2 }],
    farm: null,
    ...overrides,
  };
}

test('retail invoice schema allows product-only invoices without patient, farm, or customer', () => {
  const result = createInvoiceSchema.safeParse(retailInput());
  assert.equal(result.success, true);
  assert.equal(result.data.contextType, 'retail_sale');
  assert.equal(result.data.patientId, null);
  assert.equal(result.data.farm, null);
  assert.equal(result.data.clientName, null);
  assert.match(compactInvoiceNumber(submissionId), /^INV-[A-Z0-9-]+$/);
  assert.equal(permissions.inventorySell, 'inventory.sell');
});

test('retail invoice schema rejects services, entity links, and empty carts', () => {
  assert.equal(createInvoiceSchema.safeParse(retailInput({ products: [] })).success, false);
  assert.equal(createInvoiceSchema.safeParse(retailInput({
    services: [{ description: 'Consultation', amount: 1000 }],
  })).success, false);
  assert.equal(createInvoiceSchema.safeParse(retailInput({
    patientId: '72906cef-2e83-4d54-b52d-cd6f50f5b041',
  })).success, false);
  assert.equal(createInvoiceSchema.safeParse(retailInput({
    farm: {
      farmId: 'c33fd730-a264-4944-822c-28d4ca2be4a1',
      name: 'Farm',
      visitDate: '2026-09-02',
      units: [],
      treatments: [],
    },
  })).success, false);
});

test('retail product preparation uses canonical price and cost with null entity links', async () => {
  const client = {
    async query() {
      return {
        rows: [{
          inventory_product_id: productId,
          name: 'Balance Chicken Dinner',
          batch_number: 'B-1',
          expiry_date: null,
          purchase_price: '1600',
          selling_price: '2000',
          quantity: 10,
          base_unit_label: 'Can',
          is_sellable: true,
          is_archived: false,
          product_unit_id: null,
          unit_label: 'Can',
          conversion_to_base: 1,
          unit_selling_price: '2000',
        }],
      };
    },
  };
  const prepared = await prepareProductLines(client, 'clinic-1', [
    { inventoryProductId: productId, quantity: 2 },
  ]);
  assert.equal(prepared.error, undefined);
  assert.deepEqual(prepared.lines[0], {
    patientId: null,
    farmUnitId: null,
    inventoryProductId: productId,
    productUnitId: null,
    description: 'Balance Chicken Dinner',
    quantity: 2,
    unitPrice: 2000,
    lineTotal: 4000,
    displayUnit: 'Can',
    conversion: 1,
    baseQuantity: 2,
    unitCost: 1600,
    productName: 'Balance Chicken Dinner',
    batchNumber: 'B-1',
    expiryDate: null,
  });
});

test('multi-line insufficient stock performs no deductions', async () => {
  const writes = [];
  let productRead = 0;
  const client = {
    async query(sql) {
      if (sql.includes('SELECT inventory_deducted_at')) {
        return { rows: [{ inventory_deducted_at: null }] };
      }
      if (sql.includes('sum(l.base_quantity_snapshot)')) {
        return { rows: [
          { inventory_product_id: 'one', base_quantity: 2 },
          { inventory_product_id: 'two', base_quantity: 3 },
        ] };
      }
      if (sql.includes('SELECT inventory_product_id, quantity, name')) {
        productRead += 1;
        return productRead === 1
          ? { rows: [{ inventory_product_id: 'one', quantity: 5, name: 'One', base_unit_label: 'Vial' }] }
          : { rows: [{ inventory_product_id: 'two', quantity: 1, name: 'Two', base_unit_label: 'Can' }] };
      }
      writes.push(sql);
      return { rows: [] };
    },
  };
  await assert.rejects(
    deductInvoiceInventory(client, 'clinic-1', 'invoice-1'),
    (error) => error.code === 'insufficient_stock' && /Only 1 Can of Two/.test(error.message),
  );
  assert.deepEqual(writes, []);
});
