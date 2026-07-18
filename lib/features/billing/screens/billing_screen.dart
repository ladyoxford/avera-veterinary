import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  int? drugId;
  final quantity = TextEditingController(text: '1');
  final customer = TextEditingController();

  @override
  void dispose() {
    quantity.dispose();
    customer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: inventory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Billing unavailable: $error')),
        data: (items) {
          final selected = items.where((item) => item.id == drugId).firstOrNull;
          final qty = int.tryParse(quantity.text) ?? 1;
          final total = (selected?.sellingPrice ?? 0) * qty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<int>(
                value: drugId,
                decoration: const InputDecoration(
                  labelText: 'Bill Item',
                  prefixIcon: Icon(Iconsax.box),
                ),
                items: [
                  for (final item in items)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        '${item.drugName} • ${item.quantity} available',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => drugId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: customer,
                decoration: const InputDecoration(labelText: 'Customer'),
              ),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  title: const Text('Invoice Total'),
                  trailing: Text(
                    total.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: selected == null
                        ? null
                        : () => _recordSale(selected),
                    icon: const Icon(Iconsax.receipt_item),
                    label: const Text('Record Sale'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selected == null
                        ? null
                        : () => _printInvoice(selected, qty, total),
                    icon: const Icon(Iconsax.printer),
                    label: const Text('Print / PDF'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _recordSale(InventoryItem selected) async {
    await ref
        .read(clinicRepositoryProvider)
        .recordSale(
          drugId: selected.id,
          quantity: int.tryParse(quantity.text) ?? 1,
          price: selected.sellingPrice,
          customer: customer.text.trim(),
        );
    ref.invalidate(inventoryProvider);
    ref.invalidate(dashboardStatsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sale recorded and stock deducted.')),
    );
  }

  Future<void> _printInvoice(
    InventoryItem selected,
    int qty,
    double total,
  ) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'AVERA Veterinary Clinic',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Customer: ${customer.text.trim().isEmpty ? 'Walk-in' : customer.text.trim()}',
            ),
            pw.Text('Item: ${selected.drugName}'),
            pw.Text('Quantity: $qty'),
            pw.Text('Unit Price: ${selected.sellingPrice.toStringAsFixed(2)}'),
            pw.Divider(),
            pw.Text(
              'Total: ${total.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }
}
