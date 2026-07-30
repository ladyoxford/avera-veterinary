import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../repositories/clinic_repository.dart';

/// Development-only import for the supplied Bioqarah invoice 300519. It uses
/// the existing inventory and stock-movement ledger, so it never replaces
/// stock, and its audit key makes reruns harmless.
class BioqarahReceiptImporter {
  BioqarahReceiptImporter(this._db);
  final AppDatabase _db;

  static const invoiceNumber = '300519';
  static const supplier = 'Bioqarah Industries Ltd';
  static const total = 1057800.0;

  Future<void> importFor(UserSession session) async {
    if (!kDebugMode) {
      throw StateError(
        'Supplier receipt imports are available only in development.',
      );
    }
    if (!session.can('inventory.create')) {
      throw StateError('You do not have permission to receive inventory.');
    }
    final existing =
        await (_db.select(_db.auditLogs)..where(
              (row) =>
                  row.clinicId.equals(session.clinic.clinicId) &
                  row.action.equals('inventory.receipt_imported') &
                  row.entityId.equals('BIOQARAH-$invoiceNumber'),
            ))
            .getSingleOrNull();
    if (existing != null) {
      throw StateError(
        'Invoice $invoiceNumber has already been received into inventory.',
      );
    }
    final now = DateTime.now();
    await _db.transaction(() async {
      for (final line in _lines) {
        final current =
            await (_db.select(_db.inventoryItems)..where(
                  (item) =>
                      item.clinicId.equals(session.clinic.clinicId) &
                      item.drugName.equals(line.name),
                ))
                .getSingleOrNull();
        final previousQuantity = current?.quantity ?? 0;
        final nextQuantity = previousQuantity + line.quantity;
        final weightedCost = previousQuantity == 0
            ? line.unitCost
            : ((previousQuantity * current!.buyingPrice) +
                      (line.quantity * line.unitCost)) /
                  nextQuantity;
        final itemId =
            current?.id ??
            await _db
                .into(_db.inventoryItems)
                .insert(
                  InventoryItemsCompanion.insert(
                    clinicId: Value(session.clinic.clinicId),
                    drugName: line.name,
                    category: line.category,
                    categoryId: Value(line.categoryId),
                    quantity: const Value(0),
                    minimumQuantity: const Value(5),
                    buyingPrice: Value(line.unitCost),
                    sellingPrice: Value(line.sellingPrice ?? 0),
                    supplier: const Value(supplier),
                    location: Value(
                      line.baseUnit == 'Can'
                          ? 'Base unit: Can • Supplier crate: 24'
                          : 'Base unit: ${line.baseUnit}',
                    ),
                    isSellable: Value(line.sellingPrice != null),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                  ),
                );
        await (_db.update(
          _db.inventoryItems,
        )..where((row) => row.id.equals(itemId))).write(
          InventoryItemsCompanion(
            quantity: Value(nextQuantity),
            buyingPrice: Value(weightedCost),
            sellingPrice: current == null || line.sellingPrice != null
                ? Value(line.sellingPrice ?? 0)
                : const Value.absent(),
            isSellable: current == null || line.sellingPrice != null
                ? Value(line.sellingPrice != null)
                : const Value.absent(),
            supplier: const Value(supplier),
            updatedAt: Value(now),
          ),
        );
        await _db
            .into(_db.inventoryStockMovements)
            .insert(
              InventoryStockMovementsCompanion.insert(
                clinicId: session.clinic.clinicId,
                inventoryItemId: itemId,
                movementType: 'Receipt',
                quantityChange: line.quantity,
                quantityBefore: previousQuantity,
                quantityAfter: nextQuantity,
                performedByUserId: session.user.userId,
                reason: Value(
                  '$supplier invoice $invoiceNumber • ${line.supplierDescription}',
                ),
                createdAt: now,
              ),
            );
      }
      await _db
          .into(_db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(session.clinic.clinicId),
              userId: Value(session.user.userId),
              action: 'inventory.receipt_imported',
              entityType: const Value('InventoryReceipt'),
              entityId: const Value('BIOQARAH-300519'),
              details: Value(
                jsonEncode({
                  'supplier': supplier,
                  'invoice': invoiceNumber,
                  'total': total,
                  'lines': _lines.length,
                }),
              ),
              createdAt: now,
            ),
          );
      await _db
          .into(_db.clinicActivityEvents)
          .insert(
            ClinicActivityEventsCompanion.insert(
              id: 'inventory-received:bioqarah-$invoiceNumber',
              clinicId: session.clinic.clinicId,
              type: 'inventoryReceived',
              title: 'Inventory received',
              description:
                  'Invoice $invoiceNumber from $supplier was received. ${_lines.length} lines • NGN 1,057,800.',
              occurredAt: now,
              performedByUserId: Value(session.user.userId),
              relatedEntityType: const Value('InventoryReceipt'),
              relatedEntityId: const Value('BIOQARAH-300519'),
              module: const Value('Inventory'),
              metadata: Value(
                jsonEncode({'invoice': invoiceNumber, 'total': total}),
              ),
            ),
          );
    });
  }
}

class _ReceiptLine {
  const _ReceiptLine(
    this.name,
    this.supplierDescription,
    this.categoryId,
    this.category,
    this.baseUnit,
    this.quantity,
    this.unitCost,
    this.sellingPrice,
  );
  final String name, supplierDescription, categoryId, category, baseUnit;
  final int quantity;
  final double unitCost;
  final double? sellingPrice;
}

const _lines = <_ReceiptLine>[
  _ReceiptLine(
    'Optimax ALS Dog Canned Food',
    'Optimax Can',
    'pet_food',
    'Pet Food',
    'Can',
    72,
    36400 / 24,
    2100,
  ),
  _ReceiptLine(
    'Nutri Pro ALS Dog Canned Food',
    'Nutri Pro Adult Can',
    'pet_food',
    'Pet Food',
    'Can',
    24,
    34500 / 24,
    2100,
  ),
  _ReceiptLine(
    'Chewy Pet Adult Canned Food',
    'Chewy Pet Adult',
    'pet_food',
    'Pet Food',
    'Can',
    72,
    21000 / 24,
    null,
  ),
  _ReceiptLine(
    'Dekra ALS Dog Canned Food',
    'Dekra Can Adult',
    'pet_food',
    'Pet Food',
    'Can',
    120,
    31500 / 24,
    1800,
  ),
  _ReceiptLine(
    'Booster Pate Puppy Canned Food',
    'Booster Pate Can',
    'pet_food',
    'Pet Food',
    'Can',
    72,
    48900 / 24,
    2800,
  ),
  _ReceiptLine(
    'Booster ALS Dog Canned Food',
    'Booster Can All Life Stages',
    'pet_food',
    'Pet Food',
    'Can',
    144,
    39700 / 24,
    null,
  ),
  _ReceiptLine(
    'Booster Cat Canned Food - Fish',
    'Booster Cat Can Fish',
    'pet_food',
    'Pet Food',
    'Can',
    24,
    41700 / 24,
    2500,
  ),
  _ReceiptLine(
    'Optimax Cat Canned Food',
    'Optimax Cat Can Food',
    'pet_food',
    'Pet Food',
    'Can',
    48,
    37500 / 24,
    2200,
  ),
  _ReceiptLine(
    'Frespet Cat Litter Sand 10 L',
    'Frespet Cat Litter Sand',
    'pet_accessories',
    'Pet Accessories',
    'Pack',
    1,
    13000,
    null,
  ),
  _ReceiptLine(
    'Dog Noodles',
    'Dog Noodles',
    'pet_food',
    'Pet Food',
    'Unit',
    30,
    1300,
    null,
  ),
  _ReceiptLine(
    'Silicon Brush',
    'Silicon Brush',
    'pet_accessories',
    'Pet Accessories',
    'Unit',
    10,
    2000,
    null,
  ),
  _ReceiptLine(
    'Zenbic Spray',
    'Zenbic Spray',
    'drugs',
    'Drugs',
    'Unit',
    3,
    4500,
    null,
  ),
  _ReceiptLine(
    'RBCF Syrup',
    'RBCF Syrup',
    'drugs',
    'Drugs',
    'Unit',
    3,
    4000,
    null,
  ),
  _ReceiptLine(
    'Command Wound Healing Oil',
    'Command Wound Healing Oil',
    'drugs',
    'Drugs',
    'Unit',
    27,
    2500,
    5000,
  ),
  _ReceiptLine(
    'Conditioning Shampoo',
    'Conditioning Shampoo',
    'grooming_supplies',
    'Grooming Supplies',
    'Unit',
    2,
    3000,
    null,
  ),
  _ReceiptLine(
    'Whitening Shampoo',
    'Whitening Shampoo',
    'grooming_supplies',
    'Grooming Supplies',
    'Unit',
    3,
    3000,
    null,
  ),
  _ReceiptLine(
    'Emporium Tick & Flea Soap',
    'Emporium Tick & Flea Soap',
    'grooming_supplies',
    'Grooming Supplies',
    'Unit',
    2,
    6000,
    null,
  ),
];
