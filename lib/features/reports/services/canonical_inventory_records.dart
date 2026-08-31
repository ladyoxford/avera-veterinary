import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/backend_configuration.dart';
import '../../../core/database/app_database.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/repositories/clinic_repository.dart';
import 'inventory_export_service.dart';

Future<List<InventoryExportRecord>> loadCanonicalInventoryRecords({
  required WidgetRef ref,
  required UserSession session,
}) async {
  if (BackendConfiguration.isConfigured) {
    final items = await ref
        .read(remoteInventoryListProvider.notifier)
        .refresh();
    return items
        .where((item) => !item.isArchived)
        .map(inventoryExportRecordFromRemote)
        .toList(growable: false);
  }

  final items = await ref
      .read(clinicRepositoryProvider)
      .readPermittedInventory(session);
  return items.map(inventoryExportRecordFromLocal).toList(growable: false);
}

InventoryExportRecord inventoryExportRecordFromLocal(InventoryItem item) =>
    InventoryExportRecord(
      name: item.drugName,
      category: item.category,
      subcategory: item.subcategory,
      brand: item.brandName,
      genericName: item.genericName,
      manufacturer: item.manufacturer,
      sku: item.sku,
      barcode: item.barcode,
      sellingPrice: item.sellingPrice,
      costPrice: item.buyingPrice,
      quantity: item.quantity,
      baseUnit: item.baseUnitLabel,
      packSize: item.packSize,
      batchNumber: item.batchNumber,
      expiryDate: item.expiryDate,
      storageConditions: item.storageConditions,
      status: item.quantity <= 0 ? 'Out of stock' : 'Active',
    );

InventoryExportRecord inventoryExportRecordFromRemote(
  RemoteInventoryItem item,
) => InventoryExportRecord(
  name: item.name,
  category: item.categoryName,
  subcategory: item.subcategoryName,
  brand: item.brandName,
  genericName: item.genericName,
  manufacturer: item.manufacturer,
  sku: item.sku,
  barcode: item.barcode,
  sellingPrice: item.sellingPrice.toDouble(),
  costPrice: item.purchasePrice?.toDouble(),
  quantity: item.quantity,
  baseUnit: item.baseUnitLabel,
  packSize: item.packSize,
  batchNumber: item.batchNumber,
  expiryDate: item.expiryDate,
  storageConditions: item.storageConditions,
  status: item.status,
);
