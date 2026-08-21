import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/backend_configuration.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/inventory_catalog.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/remote_patient_selector.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_presentation_factory.dart';
import '../widgets/payment_capture_dialog.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final List<Animal> _patients = [];
  final List<RemotePatient> _remotePatients = [];
  late final String _submissionId = const Uuid().v4();
  final List<_ProductCharge> _products = [];
  final List<_ServiceCharge> _services = [];
  final _consultationFee = TextEditingController(text: '0');
  final _homeFee = TextEditingController(text: '0');
  bool _consultationEnabled = false;
  bool _homeEnabled = false;
  int? _invoiceId;
  String? _remoteInvoiceId;
  String _invoiceStatus = 'UNSAVED';
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
          final productSubtotal = _products.fold<double>(0, (sum, charge) {
            final item = allowedProducts
                .where((item) => item.id == charge.inventoryItemId)
                .firstOrNull;
            return sum + (item?.sellingPrice ?? 0) * charge.quantity;
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
              _PatientCard(
                patients: _selectedPatientLabels,
                onSelect: () => _selectPatient(replace: true),
                onAdd: _hasPatient ? () => _selectPatient() : null,
                onRemove: _removePatient,
              ),
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
                  charges: _products,
                  onChanged: (index, quantity) => setState(() {
                    if (quantity <= 0) {
                      _products.removeAt(index);
                    } else {
                      _products[index] = _products[index].copyWith(
                        quantity: quantity,
                      );
                    }
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
              Chip(label: Text(_invoiceStatus)),
              const SizedBox(height: 16),
              AveraPrimaryActionButton(
                label: _products.isEmpty
                    ? 'Record Payment'
                    : 'Record Payment & Deduct Stock',
                icon: Icons.receipt_long_outlined,
                loading: _busy,
                onPressed:
                    _busy ||
                        !session.can(Permissions.billingRecordPayment) ||
                        (_products.isNotEmpty &&
                            !session.can(Permissions.inventorySell))
                    ? null
                    : () => _pay(session, total),
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
                    onPressed: _busy || total <= 0
                        ? null
                        : () => _issueInvoice(session),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Issue Invoice'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _invoiceId == null && _remoteInvoiceId == null
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

  bool get _hasPatient => _patients.isNotEmpty || _remotePatients.isNotEmpty;

  List<_SelectedPatientLabel> get _selectedPatientLabels => [
    for (final patient in _remotePatients)
      _SelectedPatientLabel(
        id: patient.id,
        name: patient.name,
        hospitalNumber: patient.hospitalNumber,
      ),
    for (final patient in _patients)
      _SelectedPatientLabel(
        id: '${patient.id}',
        name: patient.animalName,
        hospitalNumber: patient.hospitalNumber,
      ),
  ];

  List<_BillingTarget> get _targets => [
    const _BillingTarget.general(),
    for (final patient in _remotePatients)
      _BillingTarget.remote(
        patientId: patient.id,
        label: patient.name,
        hospitalNumber: patient.hospitalNumber,
      ),
    for (final patient in _patients)
      _BillingTarget.local(
        animalId: patient.id,
        label: patient.animalName,
        hospitalNumber: patient.hospitalNumber,
      ),
  ];

  Future<void> _selectPatient({bool replace = false}) async {
    if (BackendConfiguration.isConfigured) {
      final patient = await showModalBottomSheet<RemotePatient>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.86,
          child: RemotePatientSelectorSheet(
            selectedId: replace && _remotePatients.length == 1
                ? _remotePatients.first.id
                : null,
            billingOwner: replace || _remotePatients.isEmpty
                ? null
                : _remotePatients.first,
            excludedIds: replace
                ? const {}
                : _remotePatients.map((patient) => patient.id).toSet(),
            title: replace ? 'Select Client Animal' : 'Add Animal',
          ),
        ),
      );
      if (patient != null && mounted) {
        setState(() {
          if (replace) _remotePatients.clear();
          if (!_remotePatients.any((value) => value.id == patient.id)) {
            _remotePatients.add(patient);
          }
          _patients.clear();
          _removeOrphanedCharges();
        });
      }
      return;
    }
    final patient = await showModalBottomSheet<Animal>(
      context: context,
      useSafeArea: true,
      builder: (context) => _BillingPatientPicker(
        ownerId: replace || _patients.isEmpty ? null : _patients.first.ownerId,
        excludedIds: replace
            ? const {}
            : _patients.map((patient) => patient.id).toSet(),
        title: replace ? 'Select Client Animal' : 'Add Animal',
      ),
    );
    if (patient != null && mounted) {
      setState(() {
        if (replace) _patients.clear();
        if (!_patients.any((value) => value.id == patient.id)) {
          _patients.add(patient);
        }
        _remotePatients.clear();
        _removeOrphanedCharges();
      });
    }
  }

  void _removePatient(String id) {
    if (_selectedPatientLabels.length <= 1) return;
    setState(() {
      _remotePatients.removeWhere((patient) => patient.id == id);
      _patients.removeWhere((patient) => '${patient.id}' == id);
      _removeOrphanedCharges();
    });
  }

  void _removeOrphanedCharges() {
    final remoteIds = _remotePatients.map((patient) => patient.id).toSet();
    final localIds = _patients.map((patient) => patient.id).toSet();
    _products.removeWhere(
      (charge) =>
          !charge.target.isGeneral &&
          ((charge.target.remotePatientId != null &&
                  !remoteIds.contains(charge.target.remotePatientId)) ||
              (charge.target.localAnimalId != null &&
                  !localIds.contains(charge.target.localAnimalId))),
    );
    _services.removeWhere(
      (charge) =>
          !charge.target.isGeneral &&
          ((charge.target.remotePatientId != null &&
                  !remoteIds.contains(charge.target.remotePatientId)) ||
              (charge.target.localAnimalId != null &&
                  !localIds.contains(charge.target.localAnimalId))),
    );
  }

  Future<void> _addProduct(List<InventoryItem> items) async {
    final product = await showModalBottomSheet<InventoryItem>(
      context: context,
      useSafeArea: true,
      builder: (context) => _BillingProductPicker(items: items),
    );
    if (product != null && mounted) {
      final target = await _selectChargeTarget();
      if (target != null && mounted) {
        setState(() => _products.add(_ProductCharge(product.id, 1, target)));
      }
    }
  }

  Future<_BillingTarget?> _selectChargeTarget() async {
    if (!_hasPatient) {
      _message('Select at least one animal before adding charges.');
      return null;
    }
    return showModalBottomSheet<_BillingTarget>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _ChargeTargetSheet(targets: _targets),
    );
  }

  Future<void> _addService() async {
    final description = TextEditingController();
    final amount = TextEditingController();
    final result = await showDialog<(String, double)>(
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
              Navigator.pop(context, (description.text.trim(), value));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    description.dispose();
    amount.dispose();
    if (result == null || !mounted) return;
    final target = await _selectChargeTarget();
    if (target != null && mounted) {
      setState(
        () => _services.add(_ServiceCharge(result.$1, result.$2, target)),
      );
    }
  }

  Future<InvoiceDetail?> _persistDraft(UserSession session) async {
    if (_patients.isEmpty) {
      _message('Select at least one animal before billing.');
      return null;
    }
    final primary = _patients.first;
    final result = await ref
        .read(clinicRepositoryProvider)
        .saveInvoiceDraft(
          session: session,
          invoiceId: _invoiceId,
          animalId: primary.id,
          additionalAnimalIds: _patients
              .skip(1)
              .map((animal) => animal.id)
              .toList(),
          products: [
            for (final charge in _products)
              InvoiceProductDraft(
                inventoryItemId: charge.inventoryItemId,
                quantity: charge.quantity,
                animalId: charge.target.localAnimalId,
                isGeneral: charge.target.isGeneral,
              ),
          ],
          services: [
            for (final charge in _services)
              InvoiceServiceDraft(
                description: charge.description,
                amount: charge.amount,
                animalId: charge.target.localAnimalId,
                isGeneral: charge.target.isGeneral,
              ),
          ],
          consultationFee: _consultationEnabled
              ? double.tryParse(_consultationFee.text) ?? 0
              : 0,
          homeServiceFee: _homeEnabled
              ? double.tryParse(_homeFee.text) ?? 0
              : 0,
        );
    if (mounted) {
      setState(() {
        _invoiceId = result.invoice.id;
        _invoiceStatus = result.invoice.status.toUpperCase();
      });
    }
    return result;
  }

  Future<void> _saveDraft(UserSession session) async {
    setState(() => _busy = true);
    try {
      if (BackendConfiguration.isConfigured) {
        await _persistRemoteInvoice(status: 'Draft');
        _message('Draft saved. Stock was not deducted.');
        return;
      }
      await _persistDraft(session);
      _message('Draft saved. Stock was not deducted.');
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _issueInvoice(UserSession session) async {
    setState(() => _busy = true);
    try {
      if (BackendConfiguration.isConfigured) {
        await _persistRemoteInvoice(status: 'Unpaid');
      } else {
        final draft = await _persistDraft(session);
        if (draft == null) return;
        final issued = await ref
            .read(clinicRepositoryProvider)
            .issueInvoice(session: session, invoiceId: draft.invoice.id);
        if (mounted) {
          setState(() => _invoiceStatus = issued.invoice.status.toUpperCase());
        }
      }
      _message('Invoice issued with an unpaid balance.');
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(UserSession session, double total) async {
    if (total <= 0) {
      _message('Add at least one billable item before recording payment.');
      return;
    }
    final payment = await showPaymentCaptureDialog(
      context: context,
      outstanding: total,
      currency: session.clinic.currency,
    );
    if (payment == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (BackendConfiguration.isConfigured) {
        final invoiceId = await _persistRemoteInvoice(status: 'Unpaid');
        final invoice = await ref
            .read(clinicalRemoteDataSourceProvider)
            .invoice(invoiceId);
        final invoiceMap = Map<String, dynamic>.from(
          invoice['invoice'] as Map? ?? const {},
        );
        final outstanding = _remoteNumber(invoiceMap['balance']);
        if (outstanding > 0) {
          await ref
              .read(clinicalRemoteDataSourceProvider)
              .recordInvoicePayment(
                invoiceId: invoiceId,
                payload: {
                  'submissionId': const Uuid().v4(),
                  'amount': payment.amount.clamp(0, outstanding).toDouble(),
                  'method': payment.method,
                  'paidAt': payment.paidAt.toUtc().toIso8601String(),
                  'reference': payment.reference,
                },
              );
        }
        final updated = await ref
            .read(clinicalRemoteDataSourceProvider)
            .invoice(invoiceId);
        final updatedInvoice = Map<String, dynamic>.from(
          updated['invoice'] as Map? ?? const {},
        );
        if (mounted) {
          setState(
            () => _invoiceStatus =
                updatedInvoice['status']?.toString().toUpperCase() ?? 'UNPAID',
          );
        }
        ref.invalidate(remoteDashboardProvider);
        _message('Payment recorded.');
        return;
      }
      final draft = await _persistDraft(session);
      if (draft == null) return;
      await ref
          .read(clinicRepositoryProvider)
          .issueInvoice(session: session, invoiceId: draft.invoice.id);
      final paid = await ref
          .read(clinicRepositoryProvider)
          .recordInvoicePayment(
            session: session,
            invoiceId: draft.invoice.id,
            amount: payment.amount,
            paymentMethod: payment.method,
            paidAt: payment.paidAt,
            reference: payment.reference,
          );
      if (mounted) {
        setState(() => _invoiceStatus = paid.invoice.status.toUpperCase());
      }
      ref.invalidate(inventoryProvider);
      ref.invalidate(dashboardStatsProvider);
      _message('Sale recorded and stock deducted.');
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _persistRemoteInvoice({required String status}) async {
    if (_remotePatients.isEmpty) {
      throw StateError('Select at least one animal before billing.');
    }
    final patient = _remotePatients.first;
    if (_products.isNotEmpty) {
      throw StateError(
        'Refresh inventory before recording product sales in production.',
      );
    }
    final services = _services.fold<double>(
      0,
      (sum, service) => sum + service.amount,
    );
    final consultation = _consultationEnabled
        ? double.tryParse(_consultationFee.text) ?? 0
        : 0;
    final home = _homeEnabled ? double.tryParse(_homeFee.text) ?? 0 : 0;
    final total = services + consultation + home;
    final created = await ref
        .read(clinicalRemoteDataSourceProvider)
        .createInvoice({
          'submissionId': _submissionId,
          'patientId': patient.id,
          'patientIds': _remotePatients.map((patient) => patient.id).toList(),
          'status': status,
          'subtotal': total,
          'total': total,
          'services': [
            for (final service in _services)
              {
                'description': service.description,
                'amount': service.amount,
                'quantity': 1,
                'unitPrice': service.amount,
                'patientId': service.target.remotePatientId,
              },
            if (consultation > 0)
              {
                'description': 'Consultation fee',
                'amount': consultation,
                'quantity': 1,
                'unitPrice': consultation,
                'patientId': null,
              },
            if (home > 0)
              {
                'description': 'Home service fee',
                'amount': home,
                'quantity': 1,
                'unitPrice': home,
                'patientId': null,
              },
          ],
        });
    if (mounted) {
      setState(() {
        _remoteInvoiceId = created['invoice_id']?.toString();
        _invoiceStatus =
            created['status']?.toString().toUpperCase() ?? status.toUpperCase();
      });
    }
    for (final selected in _remotePatients) {
      ref.invalidate(remotePatientMedicalFileProvider(selected.id));
    }
    final invoiceId = created['invoice_id']?.toString();
    if (invoiceId == null || invoiceId.isEmpty) {
      throw StateError('The invoice was saved without a valid reference.');
    }
    return invoiceId;
  }

  Future<void> _print(UserSession session) async {
    if (BackendConfiguration.isConfigured) {
      await _printRemoteInvoice(session);
      return;
    }
    final invoice = await ref
        .read(clinicRepositoryProvider)
        .getInvoiceDetail(session, _invoiceId!);
    if (invoice == null) return;
    final entry = await ref
        .read(clinicRepositoryProvider)
        .watchBillingHistory(session)
        .first
        .then(
          (items) => items
              .where((item) => item.invoice.id == invoice.invoice.id)
              .firstOrNull,
        );
    if (entry == null) return;
    final presentation = InvoicePresentationFactory.local(
      detail: invoice,
      entry: entry,
      session: session,
    );
    final bytes = await const InvoicePdfService().build(presentation);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          '${invoice.invoice.clinicNameSnapshot.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_${invoice.invoice.reference}.pdf',
    );
  }

  Future<void> _printRemoteInvoice(UserSession session) async {
    final invoiceId = _remoteInvoiceId;
    if (invoiceId == null) return;
    final payload = await ref
        .read(clinicalRemoteDataSourceProvider)
        .invoice(invoiceId);
    final presentation = InvoicePresentationFactory.remote(
      payload: payload,
      session: session,
    );
    final bytes = await const InvoicePdfService().build(presentation);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${presentation.invoiceNumber}.pdf',
    );
  }

  double _remoteNumber(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _SelectedPatientLabel {
  const _SelectedPatientLabel({
    required this.id,
    required this.name,
    required this.hospitalNumber,
  });

  final String id;
  final String name;
  final String hospitalNumber;
}

class _BillingTarget {
  const _BillingTarget.general()
    : isGeneral = true,
      localAnimalId = null,
      remotePatientId = null,
      label = 'General / Shared',
      hospitalNumber = null;

  const _BillingTarget.local({
    required int animalId,
    required this.label,
    required this.hospitalNumber,
  }) : isGeneral = false,
       localAnimalId = animalId,
       remotePatientId = null;

  const _BillingTarget.remote({
    required String patientId,
    required this.label,
    required this.hospitalNumber,
  }) : isGeneral = false,
       localAnimalId = null,
       remotePatientId = patientId;

  final bool isGeneral;
  final int? localAnimalId;
  final String? remotePatientId;
  final String label;
  final String? hospitalNumber;
}

class _ProductCharge {
  const _ProductCharge(this.inventoryItemId, this.quantity, this.target);
  final int inventoryItemId;
  final int quantity;
  final _BillingTarget target;

  _ProductCharge copyWith({int? quantity}) =>
      _ProductCharge(inventoryItemId, quantity ?? this.quantity, target);
}

class _ServiceCharge {
  const _ServiceCharge(this.description, this.amount, this.target);
  final String description;
  final double amount;
  final _BillingTarget target;
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({
    required this.patients,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
  });
  final List<_SelectedPatientLabel> patients;
  final VoidCallback onSelect;
  final VoidCallback? onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('ANIMALS', style: averaText(context).sectionLabel),
      const SizedBox(height: 8),
      AveraSurfaceCard(
        child: patients.isEmpty
            ? ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.pets_outlined)),
                title: const Text('Select client animal'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onSelect,
              )
            : Column(
                children: [
                  for (var index = 0; index < patients.length; index++) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(
                          patients[index].name.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Text(patients[index].name),
                      subtitle: Text(patients[index].hospitalNumber),
                      trailing: patients.length > 1
                          ? IconButton(
                              tooltip: 'Remove animal',
                              onPressed: () => onRemove(patients[index].id),
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                    ),
                    if (index < patients.length - 1) const Divider(height: 1),
                  ],
                  const Divider(height: 1),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Select more animals'),
                    ),
                  ),
                ],
              ),
      ),
    ],
  );
}

class _ChargeTargetSheet extends StatelessWidget {
  const _ChargeTargetSheet({required this.targets});
  final List<_BillingTarget> targets;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Apply charge to', style: averaText(context).sectionTitle),
        const SizedBox(height: 8),
        for (final target in targets)
          ListTile(
            leading: Icon(
              target.isGeneral ? Icons.groups_outlined : Icons.pets_outlined,
            ),
            title: Text(target.label),
            subtitle: target.hospitalNumber == null
                ? const Text('Client or visit-level charge')
                : Text(target.hospitalNumber!),
            onTap: () => Navigator.pop(context, target),
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
    required this.charges,
    required this.onChanged,
  });
  final List<InventoryItem> items;
  final List<_ProductCharge> charges;
  final void Function(int, int) onChanged;
  @override
  Widget build(BuildContext context) {
    if (charges.isEmpty) return const Text('No products added.');
    return Column(
      children: [
        for (var index = 0; index < charges.length; index++)
          if (items
              .where((item) => item.id == charges[index].inventoryItemId)
              .isNotEmpty)
            Builder(
              builder: (context) {
                final charge = charges[index];
                final item = items.firstWhere(
                  (item) => item.id == charge.inventoryItemId,
                );
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
                                '${charge.target.label} | Qty ${charge.quantity} x ${formatNaira(item.sellingPrice)}',
                                style: averaText(context).caption,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatNaira(item.sellingPrice * charge.quantity),
                          style: averaText(context).fieldValue,
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          onPressed: () =>
                              onChanged(index, charge.quantity - 1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${charge.quantity}'),
                        IconButton(
                          onPressed: charge.quantity < item.quantity
                              ? () => onChanged(index, charge.quantity + 1)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        TextButton(
                          onPressed: () => onChanged(index, 0),
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
  final List<_ServiceCharge> services;
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
            subtitle: Text(services[i].target.label),
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
  const _BillingPatientPicker({
    required this.ownerId,
    required this.excludedIds,
    required this.title,
  });
  final int? ownerId;
  final Set<int> excludedIds;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(title, style: averaText(context).sectionTitle),
          Expanded(
            child: StreamBuilder<List<Animal>>(
              stream: ref.watch(clinicRepositoryProvider).watchAnimals(),
              builder: (context, snapshot) {
                final animals = (snapshot.data ?? const <Animal>[])
                    .where(
                      (animal) =>
                          !excludedIds.contains(animal.id) &&
                          (ownerId == null || animal.ownerId == ownerId),
                    )
                    .toList();
                return ListView.builder(
                  itemCount: animals.length,
                  itemBuilder: (context, index) {
                    final animal = animals[index];
                    return ListTile(
                      title: Text(animal.animalName),
                      subtitle: Text(animal.hospitalNumber),
                      onTap: () => Navigator.pop(context, animal),
                    );
                  },
                );
              },
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
