import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
import '../services/billing_inventory_utils.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_presentation_factory.dart';
import '../widgets/payment_capture_dialog.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key, this.initialFarmId});

  final String? initialFarmId;

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final List<Animal> _patients = [];
  final List<RemotePatient> _remotePatients = [];
  final Map<int, String> _localOwnerNames = {};
  String _submissionId = const Uuid().v4();
  final List<_ProductCharge> _products = [];
  final List<_RemoteProductCharge> _remoteProducts = [];
  final List<_ServiceCharge> _services = [];
  final _consultationFee = TextEditingController(text: '0');
  final _homeFee = TextEditingController(text: '0');
  bool _consultationEnabled = false;
  bool _homeEnabled = false;
  int? _invoiceId;
  String? _remoteInvoiceId;
  String _invoiceStatus = 'UNSAVED';
  bool _busy = false;
  late _InvoiceContext _context;
  String? _farmId;
  FarmDashboardData? _farmDashboard;
  List<FarmInvoiceCandidate> _farmCandidates = const [];
  final Set<int> _selectedTreatmentIds = {};
  DateTime _farmVisitDate = DateTime.now();
  bool _farmLoading = false;

  @override
  void initState() {
    super.initState();
    _farmId = widget.initialFarmId;
    _context = _farmId == null ? _InvoiceContext.patient : _InvoiceContext.farm;
    if (_farmId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFarm(_farmId!));
    }
  }

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
    final usesRemoteInventory = BackendConfiguration.isConfigured;
    final remoteInventory = ref.watch(remoteInventoryListProvider);
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
          final allowedRemoteProducts = remoteInventory.items.where((item) {
            return repository.canSellInventoryCategory(
                  session,
                  item.categoryId,
                ) &&
                item.isSellable &&
                !item.isArchived;
          }).toList();
          final productSubtotal = usesRemoteInventory
              ? _remoteProducts.fold<double>(
                  0,
                  (sum, charge) => sum + charge.lineTotal,
                )
              : _products.fold<double>(0, (sum, charge) {
                  final item = allowedProducts
                      .where((item) => item.id == charge.inventoryItemId)
                      .firstOrNull;
                  return sum + (item?.sellingPrice ?? 0) * charge.quantity;
                });
          final hasProducts = usesRemoteInventory
              ? _remoteProducts.isNotEmpty
              : _products.isNotEmpty;
          final recordedTreatmentSubtotal = _context == _InvoiceContext.farm
              ? _farmCandidates
                    .where(
                      (candidate) =>
                          _selectedTreatmentIds.contains(candidate.record.id),
                    )
                    .fold<double>(
                      0,
                      (sum, candidate) =>
                          sum + (candidate.record.billableAmount ?? 0),
                    )
              : 0;
          final servicesSubtotal =
              recordedTreatmentSubtotal +
              _services.fold<double>(0, (sum, service) => sum + service.amount);
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
              _InvoiceContextSelector(
                value: _context,
                onChanged: _changeContext,
              ),
              const SizedBox(height: 20),
              if (_context == _InvoiceContext.patient)
                _PatientCard(
                  patients: _selectedPatientLabels,
                  onSelect: () => _selectPatient(replace: true),
                  onChangePatient: () => _selectPatient(replace: true),
                  onAdd: _hasPatient ? () => _selectPatient() : null,
                  onRemove: _removePatient,
                )
              else
                _FarmBillingContextCard(
                  dashboard: _farmDashboard,
                  loading: _farmLoading,
                  visitDate: _farmVisitDate,
                  onSelectFarm: _selectFarm,
                  onChangeDate: _selectFarmVisitDate,
                ),
              if (_context == _InvoiceContext.farm) ...[
                const SizedBox(height: 20),
                _RecordedFarmTreatments(
                  loading: _farmLoading,
                  candidates: _farmCandidates,
                  selectedIds: _selectedTreatmentIds,
                  onChanged: (id, selected) => setState(() {
                    if (selected) {
                      _selectedTreatmentIds.add(id);
                    } else {
                      _selectedTreatmentIds.remove(id);
                    }
                  }),
                ),
              ],
              const SizedBox(height: 24),
              _SectionAction(
                title: 'Products',
                action: 'Add Product',
                onPressed: usesRemoteInventory
                    ? () => _addRemoteProduct(allowedRemoteProducts)
                    : () => _addProduct(allowedProducts),
              ),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                child: usesRemoteInventory
                    ? _RemoteProductLines(
                        charges: _remoteProducts,
                        loading:
                            remoteInventory.isLoading &&
                            remoteInventory.items.isEmpty,
                        error: remoteInventory.error,
                        onRetry: () => ref
                            .read(remoteInventoryListProvider.notifier)
                            .refresh(),
                        onChanged: (index, quantity) => setState(() {
                          if (quantity <= 0) {
                            _remoteProducts.removeAt(index);
                          } else {
                            _remoteProducts[index] = _remoteProducts[index]
                                .copyWith(quantity: quantity);
                          }
                        }),
                      )
                    : _ProductLines(
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
              if (_context == _InvoiceContext.patient) ...[
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
              ],
              const SizedBox(height: 20),
              _InvoiceSummary(
                products: productSubtotal,
                services: servicesSubtotal,
                consultation: consultation,
                home: home,
                total: total,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: Chip(label: Text(_invoiceStatus)),
              ),
              const SizedBox(height: 16),
              AveraPrimaryActionButton(
                label: !hasProducts
                    ? 'Record Payment'
                    : 'Record Payment & Deduct Stock',
                icon: Icons.receipt_long_outlined,
                loading: _busy,
                onPressed:
                    _busy ||
                        !session.can(Permissions.billingRecordPayment) ||
                        (hasProducts && !session.can(Permissions.inventorySell))
                    ? null
                    : () => _pay(session, total),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _saveDraft(session),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Draft'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy || total <= 0
                          ? null
                          : () => _issueInvoice(session),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Issue Invoice'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _invoiceId == null && _remoteInvoiceId == null
                      ? null
                      : () => _print(session),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print / PDF'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeContext(_InvoiceContext value) async {
    if (value == _context) return;
    setState(() {
      _context = value;
      _invoiceId = null;
      _remoteInvoiceId = null;
      _invoiceStatus = 'UNSAVED';
      _submissionId = const Uuid().v4();
      _products.clear();
      _remoteProducts.clear();
      _services.clear();
    });
    if (value == _InvoiceContext.farm && _farmDashboard == null) {
      await _selectFarm();
    }
  }

  Future<void> _selectFarm() async {
    final farm = await showModalBottomSheet<Farm>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.82,
        child: _FarmPickerSheet(),
      ),
    );
    if (farm != null && mounted) await _loadFarm(farm.id);
  }

  Future<void> _loadFarm(String farmId) async {
    final session = ref.read(userSessionProvider).valueOrNull;
    if (session == null) return;
    setState(() {
      _farmLoading = true;
      _farmId = farmId;
      _selectedTreatmentIds.clear();
    });
    try {
      final repository = ref.read(clinicRepositoryProvider);
      final dashboard = await repository.getFarmDashboard(farmId);
      if (dashboard == null ||
          dashboard.farm.clinicId != session.clinic.clinicId) {
        throw StateError('This farm is not available in the active clinic.');
      }
      final candidates = await repository.getFarmInvoiceCandidates(
        session: session,
        farmId: farmId,
        visitDate: _farmVisitDate,
      );
      if (!mounted) return;
      setState(() {
        _farmDashboard = dashboard;
        _farmCandidates = candidates;
      });
    } catch (error) {
      if (mounted) _message(_cleanError(error));
    } finally {
      if (mounted) setState(() => _farmLoading = false);
    }
  }

  Future<void> _selectFarmVisitDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _farmVisitDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (value == null || !mounted) return;
    setState(() => _farmVisitDate = value);
    final farmId = _farmId;
    if (farmId != null) await _loadFarm(farmId);
  }

  bool get _hasPatient => _patients.isNotEmpty || _remotePatients.isNotEmpty;

  List<_SelectedPatientLabel> get _selectedPatientLabels => [
    for (final patient in _remotePatients)
      _SelectedPatientLabel(
        id: patient.id,
        name: patient.name,
        hospitalNumber: patient.hospitalNumber,
        species: patient.species,
        breed: patient.breed,
        ownerName: patient.ownerName,
      ),
    for (final patient in _patients)
      _SelectedPatientLabel(
        id: '${patient.id}',
        name: patient.animalName,
        hospitalNumber: patient.hospitalNumber,
        species: patient.species,
        breed: patient.breed,
        ownerName: _localOwnerNames[patient.id],
      ),
  ];

  List<_BillingTarget> get _targets => [
    const _BillingTarget.general(),
    if (_context == _InvoiceContext.farm)
      for (final unit in _farmDashboard?.units ?? const <FarmUnit>[])
        _BillingTarget.farmUnit(
          localFarmUnitId: unit.id,
          remoteFarmUnitId: _remoteFarmUnitId(unit.id),
          label: unit.name,
        ),
    if (_context == _InvoiceContext.patient) ...[
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
    ],
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
        final changingPatient =
            replace &&
            (_remotePatients.length != 1 ||
                _remotePatients.first.id != patient.id);
        final canApply =
            !changingPatient ||
            !_hasPatientSpecificCharges ||
            await _confirmPatientChange(patient.name);
        if (canApply && mounted) {
          _applyRemotePatient(patient, replace: replace);
        }
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
      final owner =
          await (ref
                  .read(databaseProvider)
                  .select(ref.read(databaseProvider).owners)
                ..where((row) => row.id.equals(patient.ownerId)))
              .getSingleOrNull();
      if (!mounted) return;
      final changingPatient =
          replace &&
          (_patients.length != 1 || _patients.first.id != patient.id);
      final canApply =
          !changingPatient ||
          !_hasPatientSpecificCharges ||
          await _confirmPatientChange(patient.animalName);
      if (canApply && mounted) {
        _applyLocalPatient(patient, owner?.fullName, replace: replace);
      }
    }
  }

  Future<bool> _confirmPatientChange(String nextPatientName) async {
    final currentNames = _selectedPatientLabels.map((patient) => patient.name);
    final currentLabel = currentNames.isEmpty
        ? 'the current patient'
        : currentNames.join(', ');
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Change Patient?'),
            content: Text(
              'Some selected items belong specifically to $currentLabel. '
              'Changing the patient to $nextPatientName will remove those '
              'patient-specific items, while keeping general charges.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Change Patient'),
              ),
            ],
          ),
        ) ??
        false;
  }

  bool get _hasPatientSpecificCharges =>
      _products.any((charge) => !charge.target.isGeneral) ||
      _remoteProducts.any((charge) => !charge.target.isGeneral) ||
      _services.any((charge) => !charge.target.isGeneral);

  void _applyRemotePatient(RemotePatient patient, {required bool replace}) {
    setState(() {
      if (replace) _remotePatients.clear();
      if (!_remotePatients.any((value) => value.id == patient.id)) {
        _remotePatients.add(patient);
      }
      _patients.clear();
      _removeOrphanedCharges();
    });
  }

  void _applyLocalPatient(
    Animal patient,
    String? ownerName, {
    required bool replace,
  }) {
    setState(() {
      if (replace) _patients.clear();
      if (!_patients.any((value) => value.id == patient.id)) {
        _patients.add(patient);
      }
      if (ownerName != null && ownerName.isNotEmpty) {
        _localOwnerNames[patient.id] = ownerName;
      }
      _remotePatients.clear();
      _removeOrphanedCharges();
    });
  }

  void _removePatient(String id) {
    if (_selectedPatientLabels.length <= 1) return;
    setState(() {
      _remotePatients.removeWhere((patient) => patient.id == id);
      _patients.removeWhere((patient) => '${patient.id}' == id);
      _localOwnerNames.removeWhere((animalId, _) => '$animalId' == id);
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
    _remoteProducts.removeWhere(
      (charge) =>
          !charge.target.isGeneral &&
          (charge.target.remotePatientId == null ||
              !remoteIds.contains(charge.target.remotePatientId)),
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

  Future<void> _addRemoteProduct(List<RemoteInventoryItem> items) async {
    if (items.isEmpty) {
      final inventoryState = ref.read(remoteInventoryListProvider);
      _message(
        inventoryState.error == null
            ? 'No sellable inventory products are available.'
            : 'Inventory could not be refreshed. Try again.',
      );
      return;
    }
    final product = await showModalBottomSheet<RemoteInventoryItem>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.78,
        child: _RemoteBillingProductPicker(items: items),
      ),
    );
    if (product == null || !mounted) return;
    final units = _billableUnits(product);
    if (units.isEmpty) {
      _message('This product has no unit with available stock.');
      return;
    }
    final unit = units.length == 1
        ? units.first
        : await showModalBottomSheet<_RemoteBillableUnit>(
            context: context,
            useSafeArea: true,
            showDragHandle: true,
            builder: (context) => _RemoteBillingUnitPicker(
              productName: product.name,
              units: units,
            ),
          );
    if (unit == null || !mounted) return;
    final target = await _selectChargeTarget();
    if (target == null || !mounted) return;
    setState(() {
      _remoteProducts.add(
        _RemoteProductCharge(
          inventoryProductId: product.id,
          productUnitId: unit.productUnitId,
          productName: product.name,
          unitLabel: unit.label,
          conversionToBase: unit.conversionToBase,
          unitPrice: unit.sellingPrice,
          availableBaseQuantity: product.quantity,
          quantity: 1,
          target: target,
        ),
      );
    });
  }

  List<_RemoteBillableUnit> _billableUnits(RemoteInventoryItem product) {
    return billableUnitsForInventoryProduct(product)
        .map(
          (unit) => _RemoteBillableUnit(
            productUnitId: unit.productUnitId,
            label: unit.label,
            conversionToBase: unit.conversionToBase,
            sellingPrice: unit.sellingPrice,
            availableBaseQuantity: unit.availableBaseQuantity,
          ),
        )
        .toList(growable: false);
  }

  Future<_BillingTarget?> _selectChargeTarget() async {
    if (_context == _InvoiceContext.patient && !_hasPatient) {
      _message('Select at least one animal before adding charges.');
      return null;
    }
    if (_context == _InvoiceContext.farm && _farmDashboard == null) {
      _message('Select a farm before adding charges.');
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
    final quantity = TextEditingController(text: '1');
    final unit = TextEditingController(text: 'service');
    final unitPrice = TextEditingController();
    final notes = TextEditingController();
    final result = await showDialog<_ServiceDraftResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Service'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Service / description',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unit,
                decoration: const InputDecoration(
                  labelText: 'Unit / basis (animal, visit, whole farm)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitPrice,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Unit price (NGN)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final count = double.tryParse(quantity.text);
              final price = double.tryParse(unitPrice.text);
              if (description.text.trim().isEmpty ||
                  count == null ||
                  count <= 0 ||
                  price == null ||
                  price < 0) {
                return;
              }
              Navigator.pop(
                context,
                _ServiceDraftResult(
                  description: description.text.trim(),
                  quantity: count,
                  unitLabel: unit.text.trim().isEmpty
                      ? 'service'
                      : unit.text.trim(),
                  unitPrice: price,
                  notes: notes.text.trim(),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    description.dispose();
    quantity.dispose();
    unit.dispose();
    unitPrice.dispose();
    notes.dispose();
    if (result == null || !mounted) return;
    final target = await _selectChargeTarget();
    if (target != null && mounted) {
      setState(
        () => _services.add(
          _ServiceCharge(
            description: result.description,
            quantity: result.quantity,
            unitLabel: result.unitLabel,
            unitPrice: result.unitPrice,
            notes: result.notes,
            target: target,
          ),
        ),
      );
    }
  }

  Future<InvoiceDetail?> _persistDraft(UserSession session) async {
    if (_context == _InvoiceContext.farm) {
      final dashboard = _farmDashboard;
      if (dashboard == null || _farmId == null) {
        _message('Select a farm before billing.');
        return null;
      }
      final result = await ref
          .read(clinicRepositoryProvider)
          .saveFarmInvoiceDraft(
            session: session,
            farmId: _farmId!,
            visitDate: _farmVisitDate,
            treatmentRecordIds: _selectedTreatmentIds,
            products: [
              for (final charge in _products)
                InvoiceProductDraft(
                  inventoryItemId: charge.inventoryItemId,
                  quantity: charge.quantity,
                  farmUnitId: charge.target.localFarmUnitId,
                ),
            ],
            services: [
              for (final charge in _services)
                FarmInvoiceServiceDraft(
                  description: _farmServiceDescription(charge),
                  amount: charge.amount,
                  farmUnitId: charge.target.localFarmUnitId,
                ),
            ],
          );
      if (mounted) {
        setState(() {
          _invoiceId = result.invoice.id;
          _invoiceStatus = result.invoice.status.toUpperCase();
        });
      }
      return result;
    }
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
    if (_context == _InvoiceContext.farm) {
      return _persistRemoteFarmInvoice(status: status);
    }
    if (_remotePatients.isEmpty) {
      throw StateError('Select at least one animal before billing.');
    }
    final patient = _remotePatients.first;
    if (_remoteProducts.any((charge) => charge.quantity > charge.maxQuantity)) {
      throw StateError('A selected product quantity exceeds available stock.');
    }
    final products = _remoteProducts.fold<double>(
      0,
      (sum, product) => sum + product.lineTotal,
    );
    final services = _services.fold<double>(
      0,
      (sum, service) => sum + service.amount,
    );
    final consultation = _consultationEnabled
        ? double.tryParse(_consultationFee.text) ?? 0
        : 0;
    final home = _homeEnabled ? double.tryParse(_homeFee.text) ?? 0 : 0;
    final total = products + services + consultation + home;
    final created = await ref
        .read(clinicalRemoteDataSourceProvider)
        .createInvoice({
          'submissionId': _submissionId,
          'patientId': patient.id,
          'patientIds': _remotePatients.map((patient) => patient.id).toList(),
          'status': status,
          'subtotal': total,
          'total': total,
          'products': [
            for (final product in _remoteProducts)
              {
                'inventoryProductId': product.inventoryProductId,
                'productUnitId': product.productUnitId,
                'quantity': product.quantity,
                'patientId': product.target.remotePatientId,
              },
          ],
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
    ref.invalidate(remoteInventoryListProvider);
    ref.invalidate(remoteDashboardProvider);
    final invoiceId = created['invoice_id']?.toString();
    if (invoiceId == null || invoiceId.isEmpty) {
      throw StateError('The invoice was saved without a valid reference.');
    }
    return invoiceId;
  }

  Future<String> _persistRemoteFarmInvoice({required String status}) async {
    final session = ref.read(userSessionProvider).valueOrNull;
    final dashboard = _farmDashboard;
    final farmId = _farmId;
    if (session == null || dashboard == null || farmId == null) {
      throw StateError('Select a farm before billing.');
    }
    if (_remoteProducts.any((charge) => charge.quantity > charge.maxQuantity)) {
      throw StateError('A selected product quantity exceeds available stock.');
    }

    final repository = ref.read(clinicRepositoryProvider);
    final currentCandidates = await repository.getFarmInvoiceCandidates(
      session: session,
      farmId: farmId,
      visitDate: _farmVisitDate,
    );
    final selected = currentCandidates
        .where(
          (candidate) => _selectedTreatmentIds.contains(candidate.record.id),
        )
        .toList();
    if (selected.length != _selectedTreatmentIds.length) {
      throw StateError(
        'One or more treatments were already billed or are no longer available.',
      );
    }

    final units = <String, Map<String, dynamic>>{};
    final populationsByUnit = <int, List<FarmUnitPopulation>>{};
    for (final unit in dashboard.units) {
      final remoteUnitId = _remoteFarmUnitId(unit.id);
      final populations = populationsByUnit[unit.id] ??= await repository
          .getFarmUnitPopulations(farmId: farmId, unitId: unit.id);
      units[remoteUnitId] = {
        'farmUnitId': remoteUnitId,
        'name': unit.name,
        'unitType': unit.unitType,
        'species': unit.speciesId,
        'breed': unit.breedId,
        'populations': [
          for (final population in populations)
            {
              'farmUnitPopulationId': _remotePopulationId(population.id),
              'speciesId': population.speciesId,
              'breedId': population.breedId,
              'maleCount': population.maleCount,
              'femaleCount': population.femaleCount,
              'unknownCount': population.unknownCount,
            },
        ],
      };
    }

    final treatments = <Map<String, dynamic>>[];
    final services = <Map<String, dynamic>>[];
    for (final candidate in selected) {
      final record = candidate.record;
      final unit = candidate.unit;
      final remoteUnitId = unit == null ? null : _remoteFarmUnitId(unit.id);
      final remoteTreatmentId = _remoteTreatmentId(record.id);
      final targetPopulationIds = unit == null
          ? const <String>[]
          : _localTargetPopulationIds(record.targetPopulationIdsJson)
                .where(
                  (id) => populationsByUnit[unit.id]!.any(
                    (population) => population.id == id,
                  ),
                )
                .map(_remotePopulationId)
                .toList();
      final amount = record.billableAmount ?? 0;
      treatments.add({
        'treatmentRecordId': remoteTreatmentId,
        'farmUnitId': remoteUnitId,
        'treatmentType': record.eventType,
        'productName': record.product,
        'occurredAt': record.occurredAt.toUtc().toIso8601String(),
        'animalsCovered': record.animalsCovered,
        'billableAmount': amount,
        'notes': record.notes,
        'targetScope': record.targetScope,
        'targetPopulationIds': targetPopulationIds,
      });
      services.add({
        'description':
            '${unit?.name ?? 'Farm'} - ${record.eventType}${record.product?.trim().isNotEmpty == true ? ' (${record.product})' : ''}',
        'amount': amount,
        'quantity': 1,
        'unitPrice': amount,
        'farmUnitId': remoteUnitId,
        'sourceTreatmentRecordId': remoteTreatmentId,
      });
    }
    for (final service in _services) {
      services.add({
        'description': _farmServiceDescription(service),
        'amount': service.amount,
        'quantity': service.quantity,
        'unitPrice': service.unitPrice,
        'farmUnitId': service.target.remoteFarmUnitId,
      });
    }

    final productTotal = _remoteProducts.fold<double>(
      0,
      (sum, product) => sum + product.lineTotal,
    );
    final serviceTotal = services.fold<double>(
      0,
      (sum, service) => sum + _remoteNumber(service['amount']),
    );
    final total = productTotal + serviceTotal;
    if (total <= 0) {
      throw StateError('Add at least one billable item.');
    }
    final created = await ref
        .read(clinicalRemoteDataSourceProvider)
        .createInvoice({
          'submissionId': _submissionId,
          'contextType': 'farm_visit',
          'patientIds': const <String>[],
          'status': status,
          'subtotal': total,
          'total': total,
          'products': [
            for (final product in _remoteProducts)
              {
                'inventoryProductId': product.inventoryProductId,
                'productUnitId': product.productUnitId,
                'quantity': product.quantity,
                'farmUnitId': product.target.remoteFarmUnitId,
              },
          ],
          'services': services,
          'farm': {
            'farmId': dashboard.farm.id,
            'name': dashboard.farm.name,
            'clientName':
                dashboard.farm.ownerOrganization ?? dashboard.farm.name,
            'clientPhone': dashboard.farm.contactNumber,
            'visitDate': DateFormat('yyyy-MM-dd').format(_farmVisitDate),
            'units': units.values.toList(),
            'treatments': treatments,
          },
        });
    final invoiceId = created['invoice_id']?.toString();
    if (invoiceId == null || invoiceId.isEmpty) {
      throw StateError('The invoice was saved without a valid reference.');
    }
    if (mounted) {
      setState(() {
        _remoteInvoiceId = invoiceId;
        _invoiceStatus =
            created['status']?.toString().toUpperCase() ?? status.toUpperCase();
      });
    }
    ref.invalidate(remoteInventoryListProvider);
    ref.invalidate(remoteDashboardProvider);
    return invoiceId;
  }

  String _farmServiceDescription(_ServiceCharge service) {
    final basis = service.unitLabel.trim();
    final notes = service.notes.trim();
    return '${service.description}${basis.isEmpty ? '' : ' ($basis)'}${notes.isEmpty ? '' : ' - $notes'}';
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

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('StateError: ', '');

  String _remoteFarmUnitId(int localId) => const Uuid().v5(
    Namespace.url.value,
    'avera:${_farmId ?? ''}:farm-unit:$localId',
  );

  String _remoteTreatmentId(int localId) => const Uuid().v5(
    Namespace.url.value,
    'avera:${_farmId ?? ''}:farm-treatment:$localId',
  );

  String _remotePopulationId(int localId) => const Uuid().v5(
    Namespace.url.value,
    'avera:${_farmId ?? ''}:farm-population:$localId',
  );

  List<int> _localTargetPopulationIds(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return const [];
    try {
      final value = jsonDecode(encoded);
      if (value is! List) return const [];
      return value
          .map((item) => item is int ? item : int.tryParse('$item'))
          .whereType<int>()
          .toList();
    } on FormatException {
      return const [];
    }
  }
}

enum _InvoiceContext { patient, farm }

class _SelectedPatientLabel {
  const _SelectedPatientLabel({
    required this.id,
    required this.name,
    required this.hospitalNumber,
    this.species,
    this.breed,
    this.ownerName,
  });

  final String id;
  final String name;
  final String hospitalNumber;
  final String? species;
  final String? breed;
  final String? ownerName;
}

class _BillingTarget {
  const _BillingTarget.general()
    : isGeneral = true,
      localAnimalId = null,
      remotePatientId = null,
      localFarmUnitId = null,
      remoteFarmUnitId = null,
      label = 'General / Shared',
      hospitalNumber = null;

  const _BillingTarget.local({
    required int animalId,
    required this.label,
    required this.hospitalNumber,
  }) : isGeneral = false,
       localAnimalId = animalId,
       remotePatientId = null,
       localFarmUnitId = null,
       remoteFarmUnitId = null;

  const _BillingTarget.remote({
    required String patientId,
    required this.label,
    required this.hospitalNumber,
  }) : isGeneral = false,
       localAnimalId = null,
       remotePatientId = patientId,
       localFarmUnitId = null,
       remoteFarmUnitId = null;

  const _BillingTarget.farmUnit({
    required this.localFarmUnitId,
    required this.remoteFarmUnitId,
    required this.label,
  }) : isGeneral = false,
       localAnimalId = null,
       remotePatientId = null,
       hospitalNumber = null;

  final bool isGeneral;
  final int? localAnimalId;
  final String? remotePatientId;
  final int? localFarmUnitId;
  final String? remoteFarmUnitId;
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

class _RemoteBillableUnit {
  const _RemoteBillableUnit({
    required this.productUnitId,
    required this.label,
    required this.conversionToBase,
    required this.sellingPrice,
    required this.availableBaseQuantity,
  });

  final String? productUnitId;
  final String label;
  final int conversionToBase;
  final double sellingPrice;
  final int availableBaseQuantity;

  int get availableQuantity =>
      conversionToBase <= 0 ? 0 : availableBaseQuantity ~/ conversionToBase;
}

class _RemoteProductCharge {
  const _RemoteProductCharge({
    required this.inventoryProductId,
    required this.productUnitId,
    required this.productName,
    required this.unitLabel,
    required this.conversionToBase,
    required this.unitPrice,
    required this.availableBaseQuantity,
    required this.quantity,
    required this.target,
  });

  final String inventoryProductId;
  final String? productUnitId;
  final String productName;
  final String unitLabel;
  final int conversionToBase;
  final double unitPrice;
  final int availableBaseQuantity;
  final int quantity;
  final _BillingTarget target;

  int get maxQuantity =>
      conversionToBase <= 0 ? 0 : availableBaseQuantity ~/ conversionToBase;
  double get lineTotal => quantity * unitPrice;

  _RemoteProductCharge copyWith({int? quantity}) => _RemoteProductCharge(
    inventoryProductId: inventoryProductId,
    productUnitId: productUnitId,
    productName: productName,
    unitLabel: unitLabel,
    conversionToBase: conversionToBase,
    unitPrice: unitPrice,
    availableBaseQuantity: availableBaseQuantity,
    quantity: quantity ?? this.quantity,
    target: target,
  );
}

class _ServiceCharge {
  const _ServiceCharge({
    required this.description,
    required this.quantity,
    required this.unitLabel,
    required this.unitPrice,
    required this.notes,
    required this.target,
  });
  final String description;
  final double quantity;
  final String unitLabel;
  final double unitPrice;
  final String notes;
  final _BillingTarget target;

  double get amount => quantity * unitPrice;
}

class _ServiceDraftResult {
  const _ServiceDraftResult({
    required this.description,
    required this.quantity,
    required this.unitLabel,
    required this.unitPrice,
    required this.notes,
  });

  final String description;
  final double quantity;
  final String unitLabel;
  final double unitPrice;
  final String notes;
}

class _InvoiceContextSelector extends StatelessWidget {
  const _InvoiceContextSelector({required this.value, required this.onChanged});

  final _InvoiceContext value;
  final ValueChanged<_InvoiceContext> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('INVOICE FOR', style: averaText(context).sectionLabel),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<_InvoiceContext>(
          segments: const [
            ButtonSegment(
              value: _InvoiceContext.patient,
              icon: Icon(Icons.pets_outlined),
              label: Text('Patient / Clinic'),
            ),
            ButtonSegment(
              value: _InvoiceContext.farm,
              icon: Icon(Icons.agriculture_outlined),
              label: Text('Farm'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    ],
  );
}

class _FarmBillingContextCard extends StatelessWidget {
  const _FarmBillingContextCard({
    required this.dashboard,
    required this.loading,
    required this.visitDate,
    required this.onSelectFarm,
    required this.onChangeDate,
  });

  final FarmDashboardData? dashboard;
  final bool loading;
  final DateTime visitDate;
  final VoidCallback onSelectFarm;
  final VoidCallback onChangeDate;

  @override
  Widget build(BuildContext context) {
    final farm = dashboard?.farm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SELECT FARM', style: averaText(context).sectionLabel),
        const SizedBox(height: 8),
        AveraSurfaceCard(
          child: loading && farm == null
              ? const Center(child: CircularProgressIndicator())
              : farm == null
              ? ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.agriculture_outlined),
                  ),
                  title: const Text('Select farm'),
                  subtitle: const Text('Use a persisted clinic farm record'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onSelectFarm,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          child: Icon(Icons.agriculture_outlined),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                farm.name,
                                style: averaText(context).listItemTitle,
                              ),
                              Text(
                                farm.ownerOrganization ?? farm.name,
                                style: averaText(context).listItemSubtitle,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: onSelectFarm,
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                    if (farm.contactNumber?.trim().isNotEmpty == true)
                      Text(farm.contactNumber!),
                    if (farm.location?.trim().isNotEmpty == true)
                      Text(farm.location!),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Visit date'),
                      subtitle: Text(DateFormat.yMMMMd().format(visitDate)),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: onChangeDate,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RecordedFarmTreatments extends StatelessWidget {
  const _RecordedFarmTreatments({
    required this.loading,
    required this.candidates,
    required this.selectedIds,
    required this.onChanged,
  });

  final bool loading;
  final List<FarmInvoiceCandidate> candidates;
  final Set<int> selectedIds;
  final void Function(int id, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<FarmInvoiceCandidate>>{};
    for (final candidate in candidates) {
      groups
          .putIfAbsent(candidate.unit?.name ?? 'General / Shared', () => [])
          .add(candidate);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECORDED SERVICES', style: averaText(context).sectionLabel),
        const SizedBox(height: 8),
        AveraSurfaceCard(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : candidates.isEmpty
              ? const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No unbilled treatment records found.'),
                    SizedBox(height: 4),
                    Text(
                      'You can still add professional services or products.',
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final group in groups.entries) ...[
                      Text(
                        group.key.toUpperCase(),
                        style: averaText(context).sectionLabel,
                      ),
                      for (final candidate in group.value)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: selectedIds.contains(candidate.record.id),
                          onChanged: (value) =>
                              onChanged(candidate.record.id, value ?? false),
                          title: Text(
                            '${candidate.record.eventType}${candidate.record.product?.trim().isNotEmpty == true ? ' - ${candidate.record.product}' : ''}',
                          ),
                          subtitle: Text(
                            '${candidate.record.animalsCovered ?? 0} animals',
                          ),
                          secondary: Text(
                            formatNaira(candidate.record.billableAmount ?? 0),
                          ),
                        ),
                      if (group.key != groups.keys.last) const Divider(),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _FarmPickerSheet extends ConsumerStatefulWidget {
  const _FarmPickerSheet();

  @override
  ConsumerState<_FarmPickerSheet> createState() => _FarmPickerSheetState();
}

class _FarmPickerSheetState extends ConsumerState<_FarmPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Farm', style: averaText(context).sectionTitle),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search farms',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<Farm>>(
              stream: ref
                  .watch(clinicRepositoryProvider)
                  .watchFarms(status: 'Active'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _query.trim().toLowerCase();
                final farms = snapshot.data!
                    .where(
                      (farm) =>
                          query.isEmpty ||
                          [
                                farm.name,
                                farm.ownerOrganization,
                                farm.contactNumber,
                                farm.location,
                              ]
                              .whereType<String>()
                              .join(' ')
                              .toLowerCase()
                              .contains(query),
                    )
                    .toList();
                if (farms.isEmpty) {
                  return const Center(
                    child: Text('No active farms match this search.'),
                  );
                }
                return ListView.separated(
                  itemCount: farms.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final farm = farms[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.agriculture_outlined),
                      ),
                      title: Text(farm.name),
                      subtitle: Text(
                        [
                          farm.ownerOrganization,
                          farm.contactNumber,
                          farm.location,
                        ].whereType<String>().join(' | '),
                      ),
                      onTap: () => Navigator.pop(context, farm),
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

class _PatientCard extends StatelessWidget {
  const _PatientCard({
    required this.patients,
    required this.onSelect,
    required this.onChangePatient,
    required this.onAdd,
    required this.onRemove,
  });
  final List<_SelectedPatientLabel> patients;
  final VoidCallback onSelect;
  final VoidCallback onChangePatient;
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
                      subtitle: Text(
                        [
                          patients[index].hospitalNumber,
                          if (patients[index].species?.isNotEmpty == true)
                            patients[index].species!,
                          if (patients[index].breed?.isNotEmpty == true)
                            patients[index].breed!,
                          if (patients[index].ownerName?.isNotEmpty == true)
                            'Owner: ${patients[index].ownerName}',
                        ].join(' | '),
                      ),
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
                      onPressed: onChangePatient,
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Change Patient'),
                    ),
                  ),
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

class _RemoteProductLines extends StatelessWidget {
  const _RemoteProductLines({
    required this.charges,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onChanged,
  });

  final List<_RemoteProductCharge> charges;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final void Function(int, int) onChanged;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (charges.isEmpty && error != null) {
      return Row(
        children: [
          const Expanded(child: Text('Inventory is temporarily unavailable.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }
    if (charges.isEmpty) return const Text('No products added.');
    return Column(
      children: [
        for (var index = 0; index < charges.length; index++) ...[
          Builder(
            builder: (context) {
              final charge = charges[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              charge.productName,
                              style: averaText(context).fieldValue,
                            ),
                            Text(
                              '${charge.target.label} | ${charge.quantity} ${charge.unitLabel} x ${formatNaira(charge.unitPrice)}',
                              style: averaText(context).caption,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatNaira(charge.lineTotal),
                        style: averaText(context).fieldValue,
                      ),
                    ],
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      IconButton(
                        tooltip: 'Reduce quantity',
                        onPressed: () => onChanged(index, charge.quantity - 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${charge.quantity}'),
                      IconButton(
                        tooltip: 'Increase quantity',
                        onPressed: charge.quantity < charge.maxQuantity
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
                ],
              );
            },
          ),
          if (index < charges.length - 1) const Divider(),
        ],
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

class _BillingProductPicker extends StatefulWidget {
  const _BillingProductPicker({required this.items});
  final List<InventoryItem> items;

  @override
  State<_BillingProductPicker> createState() => _BillingProductPickerState();
}

class _BillingProductPickerState extends State<_BillingProductPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items
        .where(
          (item) => matchesBillingText(_search.text, [
            item.drugName,
            item.genericName,
            item.brandName,
            item.categoryId,
            item.category,
            item.subcategoryId,
            item.subcategory,
            item.sku,
            item.barcode,
          ]),
        )
        .toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Add Product', style: averaText(context).sectionTitle),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search product, brand, category, SKU or barcode',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('No matching products.'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final expired =
                            item.expiryDate?.isBefore(DateTime.now()) ?? false;
                        return ListTile(
                          title: Text(item.drugName),
                          subtitle: Text(
                            '${item.quantity} ${item.baseUnitLabel} available / ${formatNaira(item.sellingPrice)}',
                          ),
                          trailing: expired
                              ? const Chip(label: Text('Expired'))
                              : const Icon(Icons.chevron_right_rounded),
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
}

class _RemoteBillingProductPicker extends StatefulWidget {
  const _RemoteBillingProductPicker({required this.items});

  final List<RemoteInventoryItem> items;

  @override
  State<_RemoteBillingProductPicker> createState() =>
      _RemoteBillingProductPickerState();
}

class _RemoteBillingProductPickerState
    extends State<_RemoteBillingProductPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final items = widget.items
        .where((item) => matchesBillingInventorySearch(item, _search.text))
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Product', style: averaText(context).sectionTitle),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search product, brand, category, SKU or barcode',
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No matching products.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final expired =
                          item.expiryDate != null &&
                          DateUtils.dateOnly(item.expiryDate!).isBefore(today);
                      final hasStock = item.quantity > 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.quantity} ${item.baseUnitLabel} available | ${billableUnitsForInventoryProduct(item).length} sale unit${billableUnitsForInventoryProduct(item).length == 1 ? '' : 's'}',
                        ),
                        trailing: expired
                            ? const Chip(label: Text('Expired'))
                            : const Icon(Icons.chevron_right_rounded),
                        enabled: !expired && hasStock,
                        onTap: !expired && hasStock
                            ? () => Navigator.pop(context, item)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RemoteBillingUnitPicker extends StatelessWidget {
  const _RemoteBillingUnitPicker({
    required this.productName,
    required this.units,
  });

  final String productName;
  final List<_RemoteBillableUnit> units;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Unit', style: averaText(context).sectionTitle),
        const SizedBox(height: 4),
        Text(productName, style: averaText(context).caption),
        const SizedBox(height: 12),
        for (final unit in units)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(unit.label),
            subtitle: Text(
              '${unit.availableQuantity} available | ${unit.conversionToBase} base unit${unit.conversionToBase == 1 ? '' : 's'} each',
            ),
            trailing: Text(
              formatNaira(unit.sellingPrice),
              style: averaText(context).fieldValue,
            ),
            onTap: () => Navigator.pop(context, unit),
          ),
      ],
    ),
  );
}
