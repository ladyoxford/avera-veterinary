import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(inventoryProvider);
    final date = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showItemDialog(context, ref),
        icon: const Icon(Iconsax.add),
        label: const Text('Item'),
      ),
      body: inventory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Inventory failed: $error')),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final low = item.quantity <= item.minimumQuantity;
            final expired = item.expiryDate?.isBefore(DateTime.now()) ?? false;
            return Slidable(
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                children: [
                  SlidableAction(
                    onPressed: (_) async {
                      await ref.read(clinicRepositoryProvider).deleteInventoryItem(item.id);
                      ref.invalidate(inventoryProvider);
                    },
                    icon: Iconsax.trash,
                    label: 'Delete',
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                ],
              ),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(expired ? Iconsax.timer_pause : Iconsax.box)),
                  title: Text(item.drugName),
                  subtitle: Text(
                    '${item.category} • Qty ${item.quantity} • Min ${item.minimumQuantity}\n'
                    'Batch ${item.batchNumber ?? '-'} • Exp ${item.expiryDate == null ? '-' : date.format(item.expiryDate!)}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      if (low) const Chip(label: Text('Low')),
                      if (expired) const Chip(label: Text('Expired')),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showItemDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final category = TextEditingController(text: 'Drugs');
    final quantity = TextEditingController(text: '1');
    final minimum = TextEditingController(text: '5');
    final selling = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Inventory Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Drug / Item Name')),
              TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
              TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
              TextField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum Quantity')),
              TextField(controller: selling, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final itemId = await ref.read(clinicRepositoryProvider).saveInventoryItem(
                    InventoryItemsCompanion.insert(
                      drugName: name.text.trim(),
                      category: category.text.trim(),
                      quantity: Value(int.tryParse(quantity.text) ?? 0),
                      minimumQuantity: Value(int.tryParse(minimum.text) ?? 0),
                      sellingPrice: Value(double.tryParse(selling.text) ?? 0),
                    ),
                  );
              final offline = ref.read(offlineAuthorizationSnapshotProvider);
              if (offline != null && offline.clinicId != null) {
                await ref.read(offlineSyncRepositoryProvider).enqueue(
                  clinicId: offline.clinicId!,
                  userId: offline.userId,
                  deviceId: await ref.read(offlineAuthorizationServiceProvider).deviceId(),
                  entityType: 'inventory_item',
                  entityId: itemId.toString(),
                  operationType: 'create',
                  payload: {'localInventoryItemId': itemId, 'name': name.text.trim(), 'category': category.text.trim(), 'quantity': int.tryParse(quantity.text) ?? 0},
                );
              }
              ref.invalidate(inventoryProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
