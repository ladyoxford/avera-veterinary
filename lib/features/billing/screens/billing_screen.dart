import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/inventory_catalog.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  Animal? _patient;
  final Map<int, int> _products = {};
  final List<InvoiceServiceDraft> _services = [];
  final _consultationFee = TextEditingController(text: '0');
  final _homeFee = TextEditingController(text: '0');
  bool _consultationEnabled = false;
  bool _homeEnabled = false;
  int? _invoiceId;
  bool _busy = false;

  @override
  void dispose() {
    _consultationFee.dispose();
    _homeFee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final repository = ref.watch(clinicRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [
          if (session.can(Permissions.billingHistory))
            IconButton(
              tooltip: 'Billing History',
              onPressed: () => context.push('/billing/history'),
              icon: const Icon(Icons.history_rounded),
            ),
        ],
      ),
      body: StreamBuilder<List<InventoryItem>>(
        stream: repository.watchPermittedInventory(session),
        builder: (context, snapshot) {
          final allowedProducts = (snapshot.data ?? const <InventoryItem>[])
              .where((item) {
                final category =
                    item.categoryId ??
                    InventoryCategories.canonicalId(item.category);
                return repository.canSellInventoryCategory(session, category) &&
                    item.isSellable &&
                    !item.isArchived;
              })
              .toList();
          final productSubtotal = _products.entries.fold<double>(0, (
            sum,
            entry,
          ) {
            final item = allowedProducts
                .where((item) => item.id == entry.key)
                .firstOrNull;
            return sum + (item?.sellingPrice ?? 0) * entry.value;
          });
          final servicesSubtotal = _services.fold<double>(
            0,
            (sum, service) => sum + service.amount,
          );
          final double consultation = _consultationEnabled
              ? double.tryParse(_consultationFee.text) ?? 0
              : 0;
          final double home = _homeEnabled
              ? double.tryParse(_homeFee.text) ?? 0
              : 0;
          final total =
              productSubtotal + servicesSubtotal + consultation + home;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              _PatientCard(patient: _patient, onChange: _selectPatient),
              const SizedBox(height: 24),
              _SectionAction(
                title: 'Products',
                action: 'Add Product',
                onPressed: () => _addProduct(allowedProducts),
              ),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                child: _ProductLines(
                  items: allowedProducts,
                  quantities: _products,
                  onChanged: (id, quantity) => setState(() {
                    quantity <= 0
                        ? _products.remove(id)
                        : _products[id] = quantity;
                  }),
                ),
              ),
              const SizedBox(height: 20),
              _SectionAction(
                title: 'Services',
                action: 'Add Service',
                onPressed: _addService,
              ),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                child: _ServiceLines(
                  services: _services,
                  onRemove: (index) =>
                      setState(() => _services.removeAt(index)),
                ),
              ),
              const SizedBox(height: 20),
              _FeeCard(
                label: 'Consultation Fee',
                enabled: _consultationEnabled,
                controller: _consultationFee,
                onChanged: (value) =>
                    setState(() => _consultationEnabled = value),
                onAmountChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _FeeCard(
                label: 'Home Service Fee',
                enabled: _homeEnabled,
                controller: _homeFee,
                onChanged: (value) => setState(() => _homeEnabled = value),
                onAmountChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              _InvoiceSummary(
                products: productSubtotal,
                services: servicesSubtotal,
                consultation: consultation,
                home: home,
                total: total,
              ),
              const SizedBox(height: 8),
              Chip(label: Text(_invoiceId == null ? 'Pending' : 'Draft saved')),
              const SizedBox(height: 16),
              AveraPrimaryActionButton(
                label: 'Record Sale & Deduct Stock',
                icon: Icons.receipt_long_outlined,
                loading: _busy,
                onPressed: _busy || !session.can(Permissions.inventorySell)
                    ? null
                    : () => _pay(session),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _saveDraft(session),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Draft'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _invoiceId == null
                        ? null
                        : () => _print(session),
                    icon: const Icon(Icons.print_outlined),
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

  Future<void> _selectPatient() async {
    final patient = await showModalBottomSheet<Animal>(
      context: context,
      useSafeArea: true,
      builder: (context) => const _BillingPatientPicker(),
    );
    if (patient != null && mounted) setState(() => _patient = patient);
  }

  Future<void> _addProduct(List<InventoryItem> items) async {
    final product = await showModalBottomSheet<InventoryItem>(
      context: context,
      useSafeArea: true,
      builder: (context) => _BillingProductPicker(items: items),
    );
    if (product != null && mounted) {
      setState(
        () => _products.update(
          product.id,
          (value) => value + 1,
          ifAbsent: () => 1,
        ),
      );
    }
  }

  Future<void> _addService() async {
    final description = TextEditingController();
    final amount = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: description,
              decoration: const InputDecoration(
                labelText: 'Service description',
              ),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount (NGN)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(amount.text);
              if (description.text.trim().isEmpty ||
                  value == null ||
                  value < 0) {
                return;
              }
              setState(
                () => _services.add(
                  InvoiceServiceDraft(
                    description: description.text,
                    amount: value,
                  ),
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<InvoiceDetail?> _persistDraft(UserSession session) async {
    if (_patient == null) {
      _message('Select a patient before billing.');
      return null;
    }
    final result = await ref
        .read(clinicRepositoryProvider)
        .saveInvoiceDraft(
          session: session,
          invoiceId: _invoiceId,
          animalId: _patient!.id,
          products: [
            for (final entry in _products.entries)
              InvoiceProductDraft(
                inventoryItemId: entry.key,
                quantity: entry.value,
              ),
          ],
          services: _services,
          consultationFee: _consultationEnabled
              ? double.tryParse(_consultationFee.text) ?? 0
              : 0,
          homeServiceFee: _homeEnabled
              ? double.tryParse(_homeFee.text) ?? 0
              : 0,
        );
    if (mounted) setState(() => _invoiceId = result.invoice.id);
    return result;
  }

  Future<void> _saveDraft(UserSession session) async {
    setState(() => _busy = true);
    try {
      await _persistDraft(session);
      _message('Draft saved. Stock was not deducted.');
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(UserSession session) async {
    setState(() => _busy = true);
    try {
      final draft = await _persistDraft(session);
      if (draft == null) return;
      await ref
          .read(clinicRepositoryProvider)
          .payInvoice(session: session, invoiceId: draft.invoice.id);
      ref.invalidate(inventoryProvider);
      ref.invalidate(dashboardStatsProvider);
      _message('Sale recorded and stock deducted.');
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print(UserSession session) async {
    final invoice = await ref
        .read(clinicRepositoryProvider)
        .getInvoiceDetail(session, _invoiceId!);
    if (invoice == null) return;
    final document = pw.Document();
    final type = switch (invoice.invoice.status) {
      'Paid' => 'PAYMENT RECEIPT',
      'Voided' => 'VOIDED INVOICE',
      _ => 'DRAFT INVOICE',
    };
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            invoice.invoice.clinicNameSnapshot,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20),
          ),
          if ((invoice.invoice.clinicAddressSnapshot ?? '').isNotEmpty)
            pw.Text(invoice.invoice.clinicAddressSnapshot!),
          if ((invoice.invoice.clinicPhoneSnapshot ?? '').isNotEmpty)
            pw.Text('Phone: ${invoice.invoice.clinicPhoneSnapshot}'),
          if ((invoice.invoice.clinicEmailSnapshot ?? '').isNotEmpty)
            pw.Text('Email: ${invoice.invoice.clinicEmailSnapshot}'),
          pw.SizedBox(height: 16),
          pw.Text(
            type,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          pw.Text('Invoice: ${invoice.invoice.reference}'),
          pw.Text(
            'Patient: ${_patient?.animalName ?? 'Patient'} / ${_patient?.hospitalNumber ?? ''}',
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Product', 'Qty', 'Unit Price', 'Total'],
            data: [
              for (final line in invoice.products)
                [
                  line.productNameSnapshot,
                  '${line.quantity}',
                  formatNaira(line.unitPrice),
                  formatNaira(line.lineTotal),
                ],
            ],
          ),
          if (invoice.services.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Services'),
            for (final service in invoice.services)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(service.description),
                  pw.Text(formatNaira(service.amount)),
                ],
              ),
          ],
          pw.Divider(),
          pw.Text(
            'Products subtotal: ${formatNaira(invoice.invoice.productsSubtotal)}',
          ),
          pw.Text(
            'Services subtotal: ${formatNaira(invoice.invoice.servicesSubtotal)}',
          ),
          pw.Text(
            'Consultation fee: ${formatNaira(invoice.invoice.consultationFee)}',
          ),
          pw.Text(
            'Home service fee: ${formatNaira(invoice.invoice.homeServiceFee)}',
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'INVOICE TOTAL: ${formatNaira(invoice.invoice.total)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Thank you for choosing ${invoice.invoice.clinicNameSnapshot}.',
          ),
          pw.Text('Generated by AVERA Veterinary Practice Management.'),
        ],
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) => document.save(),
      name:
          '${invoice.invoice.clinicNameSnapshot.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_${invoice.invoice.reference}.pdf',
    );
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient, required this.onChange});
  final Animal? patient;
  final VoidCallback onChange;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Row(
      children: [
        const CircleAvatar(child: Icon(Icons.pets_outlined)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            patient == null
                ? 'Select patient'
                : '${patient!.animalName} / ${patient!.hospitalNumber}',
            style: averaText(context).fieldValue,
          ),
        ),
        TextButton(
          onPressed: onChange,
          child: Text(patient == null ? 'Select' : 'Change'),
        ),
      ],
    ),
  );
}

class _SectionAction extends StatelessWidget {
  const _SectionAction({
    required this.title,
    required this.action,
    required this.onPressed,
  });
  final String title, action;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: averaText(context).sectionLabel)),
      TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(action),
      ),
    ],
  );
}

class _ProductLines extends StatelessWidget {
  const _ProductLines({
    required this.items,
    required this.quantities,
    required this.onChanged,
  });
  final List<InventoryItem> items;
  final Map<int, int> quantities;
  final void Function(int, int) onChanged;
  @override
  Widget build(BuildContext context) {
    if (quantities.isEmpty) return const Text('No products added.');
    return Column(
      children: [
        for (final entry in quantities.entries)
          if (items.where((item) => item.id == entry.key).isNotEmpty)
            Builder(
              builder: (context) {
                final item = items.firstWhere((item) => item.id == entry.key);
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.drugName,
                                style: averaText(context).fieldValue,
                              ),
                              Text(
                                'Qty ${entry.value} x ${formatNaira(item.sellingPrice)}',
                                style: averaText(context).caption,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatNaira(item.sellingPrice * entry.value),
                          style: averaText(context).fieldValue,
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          onPressed: () => onChanged(item.id, entry.value - 1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${entry.value}'),
                        IconButton(
                          onPressed: entry.value < item.quantity
                              ? () => onChanged(item.id, entry.value + 1)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        TextButton(
                          onPressed: () => onChanged(item.id, 0),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                    const Divider(),
                  ],
                );
              },
            ),
      ],
    );
  }
}

class _ServiceLines extends StatelessWidget {
  const _ServiceLines({required this.services, required this.onRemove});
  final List<InvoiceServiceDraft> services;
  final void Function(int) onRemove;
  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) return const Text('No services added.');
    return Column(
      children: [
        for (var i = 0; i < services.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(services[i].description),
            trailing: Wrap(
              children: [
                Text(formatNaira(services[i].amount)),
                IconButton(
                  onPressed: () => onRemove(i),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({
    required this.label,
    required this.enabled,
    required this.controller,
    required this.onChanged,
    required this.onAmountChanged,
  });
  final String label;
  final bool enabled;
  final TextEditingController controller;
  final ValueChanged<bool> onChanged;
  final ValueChanged<String> onAmountChanged;
  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: Row(
      children: [
        Expanded(
          child: enabled
              ? TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  onChanged: onAmountChanged,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    prefixText: 'NGN ',
                  ),
                )
              : Text('Not applied', style: averaText(context).fieldPlaceholder),
        ),
        Switch.adaptive(value: enabled, onChanged: onChanged),
      ],
    ),
  );
}

class _InvoiceSummary extends StatelessWidget {
  const _InvoiceSummary({
    required this.products,
    required this.services,
    required this.consultation,
    required this.home,
    required this.total,
  });
  final double products, services, consultation, home, total;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TotalRow('Products', products),
        _TotalRow('Services', services),
        _TotalRow('Consultation fee', consultation),
        _TotalRow('Home service fee', home),
        const Divider(),
        _TotalRow('Invoice Total', total, bold: true),
      ],
    ),
  );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});
  final String label;
  final double value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: bold
                ? averaText(context).listItemTitle
                : averaText(context).caption,
          ),
        ),
        Text(
          formatNaira(value),
          style: bold
              ? averaText(context).listItemTitle
              : averaText(context).fieldValue,
        ),
      ],
    ),
  );
}

class _BillingPatientPicker extends ConsumerWidget {
  const _BillingPatientPicker();
  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('Select Patient', style: averaText(context).sectionTitle),
          Expanded(
            child: StreamBuilder<List<Animal>>(
              stream: ref.watch(clinicRepositoryProvider).watchAnimals(),
              builder: (context, snapshot) => ListView.builder(
                itemCount: snapshot.data?.length ?? 0,
                itemBuilder: (context, index) {
                  final animal = snapshot.data![index];
                  return ListTile(
                    title: Text(animal.animalName),
                    subtitle: Text(animal.hospitalNumber),
                    onTap: () => Navigator.pop(context, animal),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BillingProductPicker extends StatelessWidget {
  const _BillingProductPicker({required this.items});
  final List<InventoryItem> items;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('Add Product', style: averaText(context).sectionTitle),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final expired =
                    item.expiryDate?.isBefore(DateTime.now()) ?? false;
                return ListTile(
                  title: Text(item.drugName),
                  subtitle: Text(
                    '${item.quantity} available / ${formatNaira(item.sellingPrice)}',
                  ),
                  trailing: expired ? const Chip(label: Text('Expired')) : null,
                  enabled: !expired && item.quantity > 0,
                  onTap: !expired && item.quantity > 0
                      ? () => Navigator.pop(context, item)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
