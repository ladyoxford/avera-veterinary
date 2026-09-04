import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/models/inventory_catalog.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../state/retail_cart.dart';
import 'inventory_screen.dart';

class RetailCartScreen extends ConsumerStatefulWidget {
  const RetailCartScreen({super.key});

  @override
  ConsumerState<RetailCartScreen> createState() => _RetailCartScreenState();
}

class _RetailCartScreenState extends ConsumerState<RetailCartScreen> {
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  bool _submitting = false;
  String? _submissionId;
  String? _submissionFingerprint;

  @override
  void dispose() {
    _customerName.dispose();
    _customerPhone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scope = RetailCartScope(
      clinicId: session.clinic.clinicId,
      userId: session.user.userId,
      sessionEpoch: session.user.lastLogin?.microsecondsSinceEpoch,
    );
    final cart = ref.watch(retailCartProvider(scope));
    final controller = ref.read(retailCartProvider(scope).notifier);
    final canCheckout =
        session.can(Permissions.inventorySell) &&
        session.can(Permissions.billingCreate);
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          12,
          20,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          Text(
            'Retail sale - not linked to any patient',
            style: averaText(context).pageSubtitle,
          ),
          const SizedBox(height: 20),
          if (cart.isEmpty)
            AveraSurfaceCard(
              child: Column(
                children: [
                  const Icon(Icons.shopping_cart_outlined, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'Your retail cart is empty',
                    style: averaText(context).listItemTitle,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.go('/inventory'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Products'),
                  ),
                ],
              ),
            )
          else ...[
            for (final entry in cart.lines.entries) ...[
              _RetailCartLineCard(
                key: ValueKey('retail-cart-line-${entry.key}'),
                line: entry.value,
                onMinus: () => controller.decrement(entry.key),
                onPlus: () {
                  if (!controller.increment(entry.key)) {
                    _showMessage(
                      'Only ${entry.value.product.availableUnits} '
                      '${entry.value.product.unitLabel}${entry.value.product.availableUnits == 1 ? '' : 's'} '
                      'of ${entry.value.product.name} is currently available.',
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              key: const Key('retail-add-another-product'),
              onPressed: () => context.go('/inventory'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Another Product'),
            ),
            const SizedBox(height: 24),
            Text(
              'Customer Information',
              style: averaText(context).sectionTitle,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customerName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer name (optional)',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customerPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 24),
            Text('Order Summary', style: averaText(context).sectionTitle),
            const SizedBox(height: 10),
            AveraSurfaceCard(
              child: Column(
                children: [
                  _SummaryRow(
                    label: 'Subtotal',
                    value: formatNaira(cart.total),
                  ),
                  const SizedBox(height: 14),
                  const _SummaryRow(label: 'Discount', value: 'NGN 0'),
                  const Divider(height: 28),
                  _SummaryRow(
                    label: 'Total',
                    value: formatNaira(cart.total),
                    emphasized: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('retail-generate-invoice'),
              onPressed: canCheckout && !_submitting
                  ? () => _generateInvoice(session, scope)
                  : null,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.receipt_long_outlined),
              label: Text(_submitting ? 'Generating...' : 'Generate Invoice'),
            ),
            const SizedBox(height: 10),
            Text(
              'Customer name and phone can be added on the invoice, or left blank for a walk-in sale.',
              textAlign: TextAlign.center,
              style: averaText(context).caption,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _generateInvoice(
    UserSession session,
    RetailCartScope scope,
  ) async {
    if (_submitting) return;
    final cart = ref.read(retailCartProvider(scope));
    if (cart.isEmpty) return;
    setState(() => _submitting = true);
    try {
      String invoiceId;
      if (BackendConfiguration.isConfigured) {
        final canonical = await ref
            .read(remoteInventoryListProvider.notifier)
            .refresh();
        final canonicalProducts = canonical
            .where((item) => !item.isArchived && item.isSellable)
            .map(_cartProductFromRemote)
            .toList(growable: false);
        final controller = ref.read(retailCartProvider(scope).notifier);
        controller.reconcile(canonicalProducts);
        final refreshed = ref.read(retailCartProvider(scope));
        if (refreshed.isEmpty) {
          throw StateError('The selected products are no longer available.');
        }
        final response = await ref
            .read(clinicalRemoteDataSourceProvider)
            .createInvoice({
              'submissionId': _submissionIdFor(refreshed),
              'contextType': 'retail_sale',
              'patientId': null,
              'patientIds': const <String>[],
              'clientName': _blankToNull(_customerName.text),
              'clientPhone': _blankToNull(_customerPhone.text),
              'status': 'Unpaid',
              'subtotal': refreshed.total,
              'total': refreshed.total,
              'services': const <Map<String, dynamic>>[],
              'products': [
                for (final line in refreshed.lines.values)
                  {
                    'inventoryProductId': line.product.productId,
                    'productUnitId': line.product.unitId,
                    'patientId': null,
                    'farmUnitId': null,
                    'quantity': line.quantity,
                  },
              ],
              'farm': null,
            });
        invoiceId = '${response['invoice_id']}';
        await ref.read(remoteInventoryListProvider.notifier).refresh();
      } else {
        final detail = await ref
            .read(clinicRepositoryProvider)
            .createRetailInvoice(
              session: session,
              products: [
                for (final line in cart.lines.values)
                  InvoiceProductDraft(
                    inventoryItemId: line.product.localProductId!,
                    quantity: line.quantity,
                  ),
              ],
              customerName: _blankToNull(_customerName.text),
              customerPhone: _blankToNull(_customerPhone.text),
            );
        invoiceId = detail.invoice.id.toString();
      }
      ref.read(retailCartProvider(scope).notifier).clear();
      if (!mounted) return;
      _showMessage('Retail invoice generated.');
      context.go(
        '/billing/history?invoiceId=${Uri.encodeQueryComponent(invoiceId)}',
      );
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _submissionIdFor(RetailCartState cart) {
    final fingerprint = [
      for (final entry in cart.lines.entries)
        '${entry.key}:${entry.value.quantity}',
      _customerName.text.trim(),
      _customerPhone.text.trim(),
    ].join('|');
    if (_submissionId == null || _submissionFingerprint != fingerprint) {
      _submissionId = const Uuid().v4();
      _submissionFingerprint = fingerprint;
    }
    return _submissionId!;
  }
}

RetailCartProduct _cartProductFromRemote(RemoteInventoryItem item) {
  final base = item.productUnits.cast<RemoteProductUnit?>().firstWhere(
    (unit) => unit?.isBaseUnit == true,
    orElse: () => null,
  );
  return RetailCartProduct(
    productId: item.id,
    unitId: base?.id,
    name: item.name,
    unitLabel: base?.label ?? item.baseUnitLabel,
    unitPrice: (base?.sellingPrice ?? item.sellingPrice).toDouble(),
    availableBaseQuantity: item.quantity,
    conversionToBase: base?.conversionToBase ?? 1,
    imageReference: item.imageUrl,
  );
}

String? _blankToNull(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _friendlyError(Object error) {
  final text = error.toString().replaceFirst('Bad state: ', '');
  if (text.contains('SocketException') || text.contains('Connection')) {
    return 'The invoice could not be generated while the server is unavailable. Your cart has been kept.';
  }
  return text;
}

class _RetailCartLineCard extends StatelessWidget {
  const _RetailCartLineCard({
    super.key,
    required this.line,
    required this.onMinus,
    required this.onPlus,
  });

  final RetailCartLine line;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Row(
      children: [
        InventoryProductImage(
          name: line.product.name,
          imageReference: line.product.imageReference,
          width: 64,
          height: 72,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: averaText(context).listItemTitle,
              ),
              Text(
                '${formatNaira(line.product.unitPrice)} / ${line.product.unitLabel}',
                style: averaText(context).caption,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('retail-minus-${line.product.key}'),
                    onPressed: onMinus,
                    icon: const Icon(Icons.remove_rounded),
                    tooltip: 'Decrease quantity',
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${line.quantity}',
                      textAlign: TextAlign.center,
                      style: averaText(context).listItemTitle,
                    ),
                  ),
                  IconButton(
                    key: Key('retail-plus-${line.product.key}'),
                    onPressed: line.quantity < line.product.availableUnits
                        ? onPlus
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Increase quantity',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(formatNaira(line.total), style: averaText(context).listItemTitle),
      ],
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: emphasized
            ? averaText(context).listItemTitle
            : averaText(context).sectionSubtitle,
      ),
      Text(
        value,
        style: averaText(context).listItemTitle.copyWith(
          color: emphasized ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
    ],
  );
}
