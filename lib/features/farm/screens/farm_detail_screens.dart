import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import '../../../core/remote/api_client.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/animal_catalogue.dart';
import '../../../core/models/vaccine_catalogue.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/clinic_document_branding.dart';
import '../../shared/widgets/avera_ui.dart';
import '../services/farm_report_service.dart';
import '../widgets/farm_back_navigation.dart';

class FarmOverviewScreen extends ConsumerWidget {
  const FarmOverviewScreen({super.key, required this.farmId});
  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: FarmBackButton(fallbackPath: '/farm-records/$farmId'),
        title: const Text('Farm Overview'),
        actions: [
          if (session?.can(Permissions.farmsCreate) == true)
            IconButton(
              tooltip: 'Edit farm',
              onPressed: () => context.push('/farm-records/$farmId/edit'),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: StreamBuilder<List<FarmDashboardData>>(
        stream: ref.read(clinicRepositoryProvider).watchFarmDashboards(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data
              ?.where((data) => data.farm.id == farmId)
              .firstOrNull;
          if (data == null) {
            return const _DetailMessage(
              title: 'Farm unavailable',
              message: 'This farm is not available in the active clinic.',
            );
          }
          final populations = data.populationBySpecies;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              AveraPageHeader(
                title: data.farm.name,
                subtitle: data.farm.location ?? 'Location not recorded',
              ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              _InfoCard(
                rows: {
                  'Owner or organization':
                      data.farm.ownerOrganization ?? 'Not recorded',
                  'Contact': data.farm.contactNumber ?? 'Not recorded',
                  'Farm type': data.farm.farmType ?? 'Not recorded',
                  'Active units': '${data.activeUnits.length}',
                  'Last updated': DateFormat.yMMMd().add_jm().format(
                    data.lastUpdated,
                  ),
                },
              ),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Livestock Population'),
              const SizedBox(height: AveraSpacing.cardGap),
              _PopulationCard(populations: populations),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Species and Breeds'),
              const SizedBox(height: AveraSpacing.cardGap),
              AveraSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _speciesNames(data.farm.speciesJson),
                      style: averaText(context).fieldValue,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _breedNames(data.farm.breedJson),
                      style: averaText(context).listItemSubtitle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Most Recent Daily Record'),
              const SizedBox(height: AveraSpacing.cardGap),
              if (data.dailyRecords.isEmpty)
                const _DetailMessage(
                  title: 'No daily records',
                  message: 'Create a daily record to begin farm monitoring.',
                )
              else
                AveraAdministrationCard(
                  icon: Icons.event_note_outlined,
                  title: DateFormat.yMMMMd().format(
                    data.dailyRecords.first.recordDate,
                  ),
                  subtitle:
                      'Closing ${data.dailyRecords.first.closingPopulation} | '
                      '${data.dailyRecords.first.feedSuppliedKg.toStringAsFixed(1)} kg feed | '
                      '${data.dailyRecords.first.status}',
                  onTap: () => context.push(
                    '/farm-records/$farmId/daily/${data.dailyRecords.first.id}',
                  ),
                ),
              if (session != null &&
                  (session.can(Permissions.billingHistory) ||
                      session.can(Permissions.billingCreate))) ...[
                const SizedBox(height: AveraSpacing.sectionGap),
                _FarmBillingSection(
                  farmId: farmId,
                  currency: session.clinic.currency,
                  canViewHistory: session.can(Permissions.billingHistory),
                  canCreate: session.can(Permissions.billingCreate),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FarmBillingSection extends ConsumerStatefulWidget {
  const _FarmBillingSection({
    required this.farmId,
    required this.currency,
    required this.canViewHistory,
    required this.canCreate,
  });

  final String farmId;
  final String currency;
  final bool canViewHistory;
  final bool canCreate;

  @override
  ConsumerState<_FarmBillingSection> createState() =>
      _FarmBillingSectionState();
}

class _FarmBillingSectionState extends ConsumerState<_FarmBillingSection> {
  late Future<_FarmBillingSnapshot> _summary;

  @override
  void initState() {
    super.initState();
    _summary = _load();
  }

  Future<_FarmBillingSnapshot> _load() async {
    final session = ref.read(userSessionProvider).valueOrNull;
    if (session == null || !widget.canViewHistory) {
      return const _FarmBillingSnapshot();
    }
    if (!BackendConfiguration.isConfigured) {
      final entries = await ref
          .read(clinicRepositoryProvider)
          .watchBillingHistory(session)
          .first;
      final invoices = entries
          .where((entry) => entry.invoice.farmId == widget.farmId)
          .map(
            (entry) => _FarmInvoiceSummary(
              id: '${entry.invoice.id}',
              reference: entry.invoice.reference,
              date: entry.invoice.createdAt,
              total: entry.invoice.total,
              paid: entry.invoice.amountPaid - entry.invoice.refundTotal,
              balance: entry.invoice.balance,
              status: entry.invoice.status,
            ),
          )
          .toList();
      return _FarmBillingSnapshot.fromInvoices(invoices);
    }

    final source = ref.read(clinicalRemoteDataSourceProvider);
    final invoices = <_FarmInvoiceSummary>[];
    var page = 1;
    var hasNext = true;
    while (hasNext) {
      final response = await source.invoices(page: page, pageSize: 100);
      for (final json in response.items) {
        if (json['context_type']?.toString() != 'farm_visit' ||
            json['farm_id']?.toString() != widget.farmId) {
          continue;
        }
        invoices.add(_FarmInvoiceSummary.fromJson(json));
      }
      hasNext = response.hasNextPage;
      page++;
    }
    return _FarmBillingSnapshot.fromInvoices(invoices);
  }

  void _reload() => setState(() => _summary = _load());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AveraSectionHeader(
          title: 'Billing',
          subtitle: 'Invoices, payments and outstanding farm balances.',
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        if (widget.canViewHistory)
          FutureBuilder<_FarmBillingSnapshot>(
            future: _summary,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AveraSurfaceCard(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return AveraSurfaceCard(
                  child: Column(
                    children: [
                      const Text('Farm billing summary is unavailable.'),
                      TextButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final summary = snapshot.data ?? const _FarmBillingSnapshot();
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _BillingMetric(
                          label: 'Outstanding',
                          value: _money(summary.outstanding),
                        ),
                      ),
                      const SizedBox(width: AveraSpacing.cardGap),
                      Expanded(
                        child: _BillingMetric(
                          label: 'Total paid',
                          value: _money(summary.totalPaid),
                        ),
                      ),
                      const SizedBox(width: AveraSpacing.cardGap),
                      Expanded(
                        child: _BillingMetric(
                          label: 'Invoices',
                          value: '${summary.invoiceCount}',
                        ),
                      ),
                    ],
                  ),
                  if (summary.recent.isNotEmpty) ...[
                    const SizedBox(height: AveraSpacing.cardGap),
                    AveraSurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < summary.recent.length;
                            index++
                          ) ...[
                            ListTile(
                              title: Text(summary.recent[index].reference),
                              subtitle: Text(
                                '${DateFormat.yMMMd().format(summary.recent[index].date)} • '
                                '${_money(summary.recent[index].total)}',
                              ),
                              trailing: Text(summary.recent[index].status),
                              onTap: () => context.push(
                                '/billing/history?context=farm&farmId=${widget.farmId}'
                                '&invoiceId=${summary.recent[index].id}',
                              ),
                            ),
                            if (index < summary.recent.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        const SizedBox(height: AveraSpacing.cardGap),
        if (widget.canCreate)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/billing?farmId=${widget.farmId}'),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Bill Farm Visit'),
            ),
          ),
        if (widget.canViewHistory)
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => context.push(
                '/billing/history?context=farm&farmId=${widget.farmId}',
              ),
              icon: const Icon(Icons.history_rounded),
              label: const Text('View All Invoices'),
            ),
          ),
      ],
    );
  }

  String _money(double value) =>
      '${widget.currency} ${NumberFormat('#,##0.00').format(value)}';
}

class _BillingMetric extends StatelessWidget {
  const _BillingMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, style: averaText(context).listItemSubtitle),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: averaText(context).fieldValue),
        ),
      ],
    ),
  );
}

class _FarmBillingSnapshot {
  const _FarmBillingSnapshot({
    this.outstanding = 0,
    this.totalPaid = 0,
    this.invoiceCount = 0,
    this.recent = const [],
  });

  factory _FarmBillingSnapshot.fromInvoices(
    List<_FarmInvoiceSummary> invoices,
  ) {
    final active = invoices.where((invoice) => !invoice.isVoid).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return _FarmBillingSnapshot(
      outstanding: active.fold(0, (sum, invoice) => sum + invoice.balance),
      totalPaid: active.fold(0, (sum, invoice) => sum + invoice.paid),
      invoiceCount: active.length,
      recent: active.take(3).toList(),
    );
  }

  final double outstanding;
  final double totalPaid;
  final int invoiceCount;
  final List<_FarmInvoiceSummary> recent;
}

class _FarmInvoiceSummary {
  const _FarmInvoiceSummary({
    required this.id,
    required this.reference,
    required this.date,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
  });

  factory _FarmInvoiceSummary.fromJson(Map<String, dynamic> json) {
    double number(String key) =>
        double.tryParse(json[key]?.toString() ?? '') ?? 0;
    return _FarmInvoiceSummary(
      id: json['invoice_id']?.toString() ?? '',
      reference: json['invoice_number']?.toString() ?? 'Invoice',
      date:
          DateTime.tryParse(json['issued_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      total: number('total'),
      paid: number('amount_paid') - number('refund_total'),
      balance: number('balance'),
      status: json['status']?.toString() ?? 'Pending',
    );
  }

  final String id;
  final String reference;
  final DateTime date;
  final double total;
  final double paid;
  final double balance;
  final String status;

  bool get isVoid {
    final normalized = status.toLowerCase();
    return normalized == 'void' || normalized == 'voided';
  }
}

class FarmUnitDetailScreen extends ConsumerStatefulWidget {
  const FarmUnitDetailScreen({
    super.key,
    required this.farmId,
    required this.unitId,
  });
  final String farmId;
  final int unitId;

  @override
  ConsumerState<FarmUnitDetailScreen> createState() =>
      _FarmUnitDetailScreenState();
}

class _FarmUnitDetailScreenState extends ConsumerState<FarmUnitDetailScreen> {
  late Future<_FarmUnitTreatmentData?> _data;
  bool _allTreatments = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<_FarmUnitTreatmentData?> _load() async {
    final repository = ref.read(clinicRepositoryProvider);
    final unit = await repository.getFarmUnit(widget.farmId, widget.unitId);
    if (unit == null) return null;
    final dashboard = await repository.getFarmDashboard(widget.farmId);
    final treatments = await repository.getFarmUnitTreatments(
      farmId: widget.farmId,
      unitId: widget.unitId,
    );
    final populations = await repository.getFarmUnitPopulations(
      farmId: widget.farmId,
      unitId: widget.unitId,
    );
    final populationMovements = await repository.getFarmUnitPopulationHistory(
      farmId: widget.farmId,
      unitId: widget.unitId,
    );
    return _FarmUnitTreatmentData(
      unit: unit,
      farmName: dashboard?.farm.name ?? 'Not recorded',
      farmActive: dashboard?.farm.status == 'Active',
      populations: populations,
      treatments: treatments,
      populationMovements: populationMovements,
    );
  }

  int _tab = 0;
  String _filter = 'All';

  Future<void> _edit(_FarmUnitTreatmentData data) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EditUnitSheet(
        farmId: widget.farmId,
        unit: data.unit,
        populations: data.populations,
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Widget _card(String title, IconData icon, Widget child, {Widget? action}) =>
      AveraSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: averaText(context).sectionTitle),
                ),
                if (action != null) action,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );

  Widget _information(_FarmUnitTreatmentData data, bool canEdit) {
    final u = data.unit;
    return _card(
      'Unit Information',
      Icons.info_outline,
      Column(
        children: [
          _InfoCard(
            rows: {
              'Species': data.populations
                  .map((p) => _speciesName(p.speciesId))
                  .toSet()
                  .join(', '),
              'Breed / group': data.populations
                  .map((p) => _breedName(p.breedId))
                  .toSet()
                  .join(', '),
              'Type': u.unitType,
              'Capacity': u.capacity?.toString() ?? 'Not set',
              'Current Stock':
                  '${u.maleCount + u.femaleCount + u.unknownCount}',
              'Status': u.status,
              'Farm / Location': data.farmName,
              'Date Created': DateFormat.yMMMd().format(u.createdAt),
              'Description': u.notes ?? 'Not recorded',
            },
          ),
          if (canEdit) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _edit(data),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Unit Details'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _transactions(_FarmUnitTreatmentData data, {bool recent = false}) {
    final movements = data.populationMovements.where(
      (m) => recent || _filter == 'All' || m.label == _filter,
    );
    final visible = recent ? movements.take(5) : movements;
    return _card(
      recent ? 'Recent Transactions' : 'Transactions',
      Icons.swap_horiz,
      Column(
        children: [
          if (!recent)
            Wrap(
              spacing: 8,
              children: [
                for (final label in ['All', 'Purchase', 'Sale', 'Mortality'])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == label,
                    onSelected: (_) => setState(() => _filter = label),
                  ),
              ],
            ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No transactions recorded.'),
            ),
          for (final movement in visible)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _movementColor(
                  movement.type,
                ).withValues(alpha: .12),
                child: Icon(
                  movement.type == 'purchase'
                      ? Icons.add
                      : movement.type == 'sale'
                      ? Icons.swap_horiz
                      : Icons.remove,
                  color: _movementColor(movement.type),
                ),
              ),
              title: Text(movement.label),
              subtitle: Text(
                '${DateFormat.yMMMd().format(movement.occurredAt)} • ${movement.details['sex'] ?? ''}\n${movement.description}',
              ),
              isThreeLine: true,
              trailing: Text(
                movement.signedQuantity,
                style: TextStyle(
                  color: _movementColor(movement.type),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                useSafeArea: true,
                isScrollControlled: true,
                builder: (_) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${movement.label} Details',
                        style: averaText(context).sectionTitle,
                      ),
                      const SizedBox(height: 16),
                      _InfoCard(
                        rows: {
                          'Farm': data.farmName,
                          'Unit': data.unit.name,
                          'Species / group':
                              '${movement.details['groupLabel'] ?? 'Not recorded'}',
                          'Type': movement.label,
                          'Quantity': movement.signedQuantity,
                          'Sex': '${movement.details['sex'] ?? 'Not recorded'}',
                          'Date': DateFormat.yMMMd().format(
                            movement.occurredAt,
                          ),
                          'Source / Buyer / Cause':
                              '${movement.details['source'] ?? 'Not recorded'}',
                          'Notes':
                              '${movement.details['notes'] ?? 'Not recorded'}',
                          'Recorded by':
                              '${movement.details['createdByName'] ?? movement.details['createdBy'] ?? 'Not recorded'}',
                          'Created':
                              '${movement.details['createdAt'] ?? 'Not recorded'}',
                          'Submission ID':
                              '${movement.details['submissionId'] ?? 'Not recorded'}',
                          'Details': movement.description,
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      action: recent
          ? TextButton(
              onPressed: () => setState(() => _tab = 2),
              child: const Text('See All'),
            )
          : null,
    );
  }

  Widget _health(_FarmUnitTreatmentData data) => _card(
    'Health & Management',
    Icons.health_and_safety_outlined,
    Column(
      children: [
        for (final entry in [
          ('Deworming', 'Deworming'),
          ('Vaccination', 'Vaccination'),
          ('Ectoparasite Control', 'Pour-On (Ticks)'),
        ])
          Builder(
            builder: (context) {
              final record = data.treatments
                  .where((t) => t.eventType == entry.$2)
                  .firstOrNull;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Last ${entry.$1}'),
                subtitle: Text(
                  '${record == null ? 'Not recorded' : DateFormat.yMMMd().format(record.occurredAt)}\nNext Due: ${record?.nextDueDate == null ? 'Not scheduled' : DateFormat.yMMMd().format(record!.nextDueDate!)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _tab = 3),
              );
            },
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final canEdit = session?.can(Permissions.farmUnitsManage) == true;
    return Scaffold(
      appBar: AppBar(
        leading: FarmBackButton(fallbackPath: '/farm-records/${widget.farmId}'),
        title: const Text('Farm Unit'),
        actions: [
          if (canEdit)
            TextButton.icon(
              onPressed: () async {
                final data = await _data;
                if (mounted && data != null) await _edit(data);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (_) => setState(() => _tab = 2),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'history',
                child: Text('Population History'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_FarmUnitTreatmentData?>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data;
            if (data == null) {
              return const _DetailMessage(
                title: 'Unit unavailable',
                message: 'Unable to load this farm unit. Please try again.',
              );
            }
            final unit = data.unit;
            final active = unit.status == 'Active' && data.farmActive;
            final total = unit.maleCount + unit.femaleCount + unit.unknownCount;
            final quickActions = _card(
              'Quick Actions',
              Icons.add_circle_outline,
              LayoutBuilder(
                builder: (context, constraints) {
                  Widget action(
                    FarmPopulationMovementType type,
                    String label,
                    String subtitle,
                    IconData icon,
                  ) {
                    final allowed =
                        active &&
                        (type == FarmPopulationMovementType.mortality
                            ? session?.can(Permissions.farmMortalityRecord) ==
                                  true
                            : canEdit);
                    return SizedBox(
                      width: constraints.maxWidth < 440
                          ? (type == FarmPopulationMovementType.purchase
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 12) / 2)
                          : (constraints.maxWidth - 24) / 3,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _movementColor(type.name),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: allowed
                            ? () => _recordPopulationMovement(
                                unit,
                                data.populations,
                                session!,
                                type,
                              )
                            : null,
                        child: Column(
                          children: [
                            Icon(icon),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(subtitle, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    );
                  }

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      action(
                        FarmPopulationMovementType.purchase,
                        'Purchase',
                        'Increase stock',
                        Icons.add_circle_outline,
                      ),
                      action(
                        FarmPopulationMovementType.sale,
                        'Sale',
                        'Decrease stock',
                        Icons.swap_horiz,
                      ),
                      action(
                        FarmPopulationMovementType.mortality,
                        'Mortality',
                        'Record deaths',
                        Icons.remove_circle_outline,
                      ),
                    ],
                  );
                },
              ),
            );
            final sexChart = _card(
              'Population by Sex',
              Icons.donut_large,
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 24,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CustomPaint(
                      painter: _SexDonutPainter([
                        unit.maleCount,
                        unit.femaleCount,
                        unit.unknownCount,
                      ], Theme.of(context).colorScheme.surfaceContainerHighest),
                      child: Center(
                        child: Text(
                          '$total\nAnimals',
                          textAlign: TextAlign.center,
                          style: averaText(context).sectionTitle,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in [
                        ('Male', unit.maleCount),
                        ('Female', unit.femaleCount),
                        ('Unknown', unit.unknownCount),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '${item.$1} ${item.$2} (${_percent(item.$2, total)}%)',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
            final overview = [
              quickActions,
              sexChart,
              _information(data, canEdit),
              _transactions(data, recent: true),
              _health(data),
              _card(
                'Notes',
                Icons.description_outlined,
                Text(unit.notes ?? 'No notes recorded.'),
                action: canEdit
                    ? TextButton(
                        onPressed: () => _edit(data),
                        child: const Text('Edit'),
                      )
                    : null,
              ),
            ];
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AveraSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  child: const Icon(
                                    Icons.cottage_outlined,
                                    size: 34,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    unit.name,
                                    style: averaText(context).pageTitle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Chip(label: Text(unit.status)),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 24,
                              runSpacing: 16,
                              children: [
                                _identityField(
                                  Icons.pets,
                                  data.populations
                                      .map((p) => _speciesName(p.speciesId))
                                      .toSet()
                                      .join(', '),
                                  'Species',
                                ),
                                _identityField(
                                  Icons.fence,
                                  unit.unitType,
                                  'Unit Type',
                                ),
                                _identityField(
                                  Icons.location_on_outlined,
                                  data.farmName,
                                  'Farm / Location',
                                ),
                                _identityField(
                                  Icons.calendar_month,
                                  DateFormat.yMMMd().format(unit.createdAt),
                                  'Date Created',
                                ),
                              ],
                            ),
                            if (unit.notes?.isNotEmpty == true) ...[
                              const SizedBox(height: 16),
                              Text(unit.notes!),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FarmUnitPopulationStats(unit: unit),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final item in [
                              (0, 'Overview', Icons.bar_chart),
                              (1, 'Animals', Icons.pets),
                              (2, 'Transactions', Icons.swap_horiz),
                              (3, 'Records', Icons.description_outlined),
                              (4, 'Settings', Icons.settings_outlined),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  avatar: Icon(item.$3, size: 18),
                                  label: Text(item.$2),
                                  selected: _tab == item.$1,
                                  onSelected: (_) =>
                                      setState(() => _tab = item.$1),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_tab == 0)
                        LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final card in overview)
                                SizedBox(
                                  width: constraints.maxWidth >= 850
                                      ? (constraints.maxWidth - 16) / 2
                                      : constraints.maxWidth,
                                  child: card,
                                ),
                            ],
                          ),
                        ),
                      if (_tab == 1)
                        _card(
                          'Population Groups',
                          Icons.pets,
                          Column(
                            children: [
                              for (final p in data.populations)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${_speciesName(p.speciesId)} • ${_breedName(p.breedId)}',
                                  ),
                                  subtitle: Text(
                                    'Male ${p.maleCount} • Female ${p.femaleCount} • Unknown ${p.unknownCount}',
                                  ),
                                  trailing: Text('${p.total}'),
                                ),
                            ],
                          ),
                        ),
                      if (_tab == 2) _transactions(data),
                      if (_tab == 3) ...[
                        if (session?.can(Permissions.farmHealthRecord) == true)
                          FilledButton.icon(
                            onPressed: active
                                ? () => _recordTreatment(
                                    unit,
                                    data.populations,
                                    session!,
                                  )
                                : null,
                            icon: const Icon(Icons.add),
                            label: const Text('Record Treatment'),
                          ),
                        const SizedBox(height: 16),
                        FarmTreatmentOverviewGrid(treatments: data.treatments),
                        const SizedBox(height: 20),
                        AveraSectionHeader(
                          title: _allTreatments
                              ? 'Treatment History'
                              : 'Recent Treatments',
                          action: TextButton(
                            onPressed: () => setState(
                              () => _allTreatments = !_allTreatments,
                            ),
                            child: Text(
                              _allTreatments ? 'Show Recent' : 'See All',
                            ),
                          ),
                        ),
                        if (data.treatments.isEmpty)
                          const Text('No treatments recorded.'),
                        for (final treatment
                            in (_allTreatments
                                ? data.treatments
                                : data.treatments.take(3)))
                          _TreatmentListTile(
                            treatment: treatment,
                            onTap: () => _showTreatmentDetails(treatment),
                          ),
                      ],
                      if (_tab == 4) _information(data, canEdit),
                      const SizedBox(height: 24),
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

  Widget _identityField(IconData icon, String value, String label) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> _recordTreatment(
    FarmUnit unit,
    List<FarmUnitPopulation> populations,
    UserSession session,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RecordTreatmentSheet(
        farmId: widget.farmId,
        unit: unit,
        populations: populations,
        session: session,
      ),
    );
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _recordPopulationMovement(
    FarmUnit unit,
    List<FarmUnitPopulation> populations,
    UserSession session,
    FarmPopulationMovementType type,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PopulationMovementSheet(
        farmId: widget.farmId,
        unit: unit,
        populations: populations,
        session: session,
        type: type,
      ),
    );
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _showTreatmentDetails(
    FarmHealthRecord treatment,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: .82,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          8,
          AveraSpacing.pageHorizontalPadding,
          24 + MediaQuery.viewPaddingOf(sheetContext).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(treatment.eventType, style: averaText(sheetContext).pageTitle),
            const SizedBox(height: 8),
            Text(
              treatment.product ?? 'Product not recorded',
              style: averaText(sheetContext).fieldValue,
            ),
            const SizedBox(height: 16),
            _InfoCard(
              rows: {
                'Date': DateFormat.yMMMd().format(treatment.occurredAt),
                'Animals treated': '${treatment.animalsCovered ?? 0}',
                'Dose': treatment.dose ?? 'Not recorded',
                'Route': treatment.route ?? 'Not recorded',
                'Batch': treatment.batchNumber ?? 'Not recorded',
                'Administered by': treatment.administeredBy ?? 'Not recorded',
                'Next due': treatment.nextDueDate == null
                    ? 'Not scheduled'
                    : DateFormat.yMMMd().format(treatment.nextDueDate!),
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _FarmUnitTreatmentData {
  const _FarmUnitTreatmentData({
    required this.unit,
    required this.populations,
    required this.treatments,
    required this.populationMovements,
    required this.farmName,
    required this.farmActive,
  });
  final String farmName;
  final bool farmActive;
  final FarmUnit unit;
  final List<FarmUnitPopulation> populations;
  final List<FarmHealthRecord> treatments;
  final List<FarmPopulationHistoryItem> populationMovements;
}

Future<bool?> showFarmPopulationMovement({
  required BuildContext context,
  required String farmId,
  required FarmUnit unit,
  required List<FarmUnitPopulation> populations,
  required UserSession session,
  required FarmPopulationMovementType type,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _PopulationMovementSheet(
    farmId: farmId,
    unit: unit,
    populations: populations,
    session: session,
    type: type,
  ),
);

class _PopulationMovementSheet extends ConsumerStatefulWidget {
  const _PopulationMovementSheet({
    required this.farmId,
    required this.unit,
    required this.populations,
    required this.session,
    required this.type,
  });

  final String farmId;
  final FarmUnit unit;
  final List<FarmUnitPopulation> populations;
  final UserSession session;
  final FarmPopulationMovementType type;

  @override
  ConsumerState<_PopulationMovementSheet> createState() =>
      _PopulationMovementSheetState();
}

class _PopulationMovementSheetState
    extends ConsumerState<_PopulationMovementSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  final _source = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  late int? _populationId;
  FarmPopulationSex _sex = FarmPopulationSex.unknown;
  DateTime _date = DateTime.now();
  bool _saving = false;

  final _submissionId = const Uuid().v4();
  bool get _decreases => widget.type != FarmPopulationMovementType.purchase;
  String get _label => widget.type == FarmPopulationMovementType.sale
      ? 'Sale'
      : _isMortality
      ? 'Mortality'
      : 'Purchase';
  bool get _isMortality => widget.type == FarmPopulationMovementType.mortality;

  @override
  void initState() {
    super.initState();
    _populationId = widget.populations.firstOrNull?.id;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _source.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Record $_label', style: averaText(context).sectionTitle),
            const SizedBox(height: 4),
            Text(widget.unit.name, style: averaText(context).sectionSubtitle),
            const SizedBox(height: 20),
            _InfoCard(
              rows: {
                'Current population':
                    '${widget.unit.maleCount + widget.unit.femaleCount + widget.unit.unknownCount}',
                _label:
                    '${_decreases ? '-' : '+'}${int.tryParse(_quantity.text) ?? 0}',
                'New population':
                    '${widget.unit.maleCount + widget.unit.femaleCount + widget.unit.unknownCount + (_decreases ? -1 : 1) * (int.tryParse(_quantity.text) ?? 0)}',
              },
            ),
            const SizedBox(height: 16),
            if (widget.populations.isEmpty)
              const Text('This unit does not have a population group.')
            else ...[
              AveraLabeledDropdownField<int>(
                label: 'Animal group',
                hintText: 'Select the population group',
                value: _populationId,
                items: [
                  for (final population in widget.populations)
                    DropdownMenuItem(
                      value: population.id,
                      child: Text(
                        '${_speciesName(population.speciesId)}${population.breedId == null ? '' : ' - ${_breedName(population.breedId)}'}',
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _populationId = value),
                validator: (value) =>
                    value == null ? 'Select an animal group.' : null,
              ),
              const SizedBox(height: 12),
              AveraLabeledTextField(
                label: 'Quantity',
                controller: _quantity,
                hintText: 'Number of animals',
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a quantity greater than zero.';
                  }
                  final population = widget.populations
                      .where((item) => item.id == _populationId)
                      .firstOrNull;
                  final available = switch (_sex) {
                    FarmPopulationSex.male => population?.maleCount ?? 0,
                    FarmPopulationSex.female => population?.femaleCount ?? 0,
                    FarmPopulationSex.unknown => population?.unknownCount ?? 0,
                  };
                  if (_decreases && parsed > available) {
                    return 'Only $available ${_sex.name} ${_speciesName(population?.speciesId).toLowerCase()} are currently available.';
                  }
                  return null;
                },
              ),
              if (!_decreases && _purchaseExceedsCapacity) ...[
                const SizedBox(height: 12),
                AveraSurfaceCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Population will exceed the current unit capacity of ${widget.unit.capacity}.',
                          style: averaText(context).listItemSubtitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              AveraLabeledDropdownField<FarmPopulationSex>(
                label: 'Sex',
                hintText: 'Select sex',
                value: _sex,
                items: const [
                  DropdownMenuItem(
                    value: FarmPopulationSex.male,
                    child: Text('Male'),
                  ),
                  DropdownMenuItem(
                    value: FarmPopulationSex.female,
                    child: Text('Female'),
                  ),
                  DropdownMenuItem(
                    value: FarmPopulationSex.unknown,
                    child: Text('Unknown'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _sex = value ?? FarmPopulationSex.unknown,
                      ),
              ),
              const SizedBox(height: 12),
              AveraLabeledFieldCard(
                label: 'Date',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DateFormat.yMMMMd().format(_date)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _saving ? null : _chooseDate,
                ),
              ),
              ...[
                const SizedBox(height: 12),
                AveraLabeledTextField(
                  label: _isMortality
                      ? 'Cause / diagnosis (optional)'
                      : _decreases
                      ? 'Buyer (optional)'
                      : 'Source / seller (optional)',
                  controller: _source,
                  hintText: 'Optional transaction details',
                ),
              ],
              const SizedBox(height: 12),
              if (!_isMortality) ...[
                AveraLabeledTextField(
                  label: 'Reference (optional)',
                  controller: _reference,
                  hintText: 'Purchase or sale reference',
                ),
                const SizedBox(height: 12),
              ],
              AveraLabeledTextField(
                label: _isMortality
                    ? 'Notes / cause of death (optional)'
                    : 'Notes (optional)',
                controller: _notes,
                hintText: 'Additional details',
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('Save $_label'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  bool get _purchaseExceedsCapacity {
    final capacity = widget.unit.capacity;
    final quantity = int.tryParse(_quantity.text.trim());
    if (capacity == null || quantity == null || quantity <= 0) return false;
    final current =
        widget.unit.maleCount +
        widget.unit.femaleCount +
        widget.unit.unknownCount;
    return current + quantity > capacity;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) ||
        _populationId == null ||
        _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .recordFarmPopulationMovement(
            session: widget.session,
            input: FarmPopulationMovementInput(
              submissionId: _submissionId,
              farmId: widget.farmId,
              farmUnitId: widget.unit.id,
              populationId: _populationId!,
              type: widget.type,
              sex: _sex,
              quantity: int.parse(_quantity.text.trim()),
              occurredAt: _date,
              source: _source.text,
              notes: [
                if (_reference.text.trim().isNotEmpty)
                  'Reference: ${_reference.text.trim()}',
                _notes.text.trim(),
              ].where((s) => s.isNotEmpty).join('\n'),
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _farmError(
                error,
                '$_label could not be saved. Please try again.',
              ),
            ),
          ),
        );
        setState(() => _saving = false);
      }
    }
  }
}

class FarmUnitSummaryCard extends StatelessWidget {
  const FarmUnitSummaryCard({
    required this.unit,
    this.populations = const [],
    super.key,
  });
  final FarmUnit unit;
  final List<FarmUnitPopulation> populations;

  @override
  Widget build(BuildContext context) {
    if (populations.length > 1) {
      final total = populations.fold<int>(
        0,
        (sum, group) =>
            sum + group.maleCount + group.femaleCount + group.unknownCount,
      );
      return AveraSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('POPULATION', style: averaText(context).sectionLabel),
            const SizedBox(height: 8),
            for (var index = 0; index < populations.length; index++) ...[
              _PopulationSummaryRow(population: populations[index]),
              if (index != populations.length - 1) const Divider(height: 20),
            ],
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL', style: averaText(context).sectionLabel),
                Text('$total animals', style: averaText(context).listItemTitle),
              ],
            ),
          ],
        ),
      );
    }
    return AveraSurfaceCard(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 9,
              child: _SummaryValue('SPECIES', _speciesName(unit.speciesId)),
            ),
            const VerticalDivider(width: 17, thickness: 1),
            Expanded(
              flex: 14,
              child: _SummaryValue('BREED', _breedName(unit.breedId)),
            ),
            const VerticalDivider(width: 17, thickness: 1),
            Expanded(
              flex: 10,
              child: _SummaryValue(
                'MALE / FEMALE',
                '${unit.maleCount} / ${unit.femaleCount}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopulationSummaryRow extends StatelessWidget {
  const _PopulationSummaryRow({required this.population});
  final FarmUnitPopulation population;

  @override
  Widget build(BuildContext context) {
    final total =
        population.maleCount + population.femaleCount + population.unknownCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _speciesName(population.speciesId),
                style: averaText(context).listItemTitle,
              ),
              Text(
                _breedName(population.breedId),
                style: averaText(context).listItemSubtitle,
              ),
              Text(
                '${population.maleCount} male • ${population.femaleCount} female'
                '${population.unknownCount > 0 ? ' • ${population.unknownCount} unknown' : ''}',
                style: averaText(context).caption,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text('$total', style: averaText(context).listItemTitle),
      ],
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          style: averaText(context).sectionLabel.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 3,
          softWrap: true,
          style: averaText(context).listItemTitle.copyWith(fontSize: 15),
        ),
      ],
    ),
  );
}

class FarmTreatmentOverviewGrid extends StatelessWidget {
  const FarmTreatmentOverviewGrid({required this.treatments, super.key});
  final List<FarmHealthRecord> treatments;

  @override
  Widget build(BuildContext context) {
    const types = [
      ('Deworming', Icons.check_circle_outline_rounded),
      ('Pour-On (Ticks)', Icons.south_rounded),
      ('Antitrypanocide', Icons.medication_outlined),
      ('Vaccination', Icons.vaccines_outlined),
    ];
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 134,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        return _TreatmentSummaryCard(
          title: type.$1,
          icon: type.$2,
          treatment: treatments
              .where((record) => record.eventType == type.$1)
              .firstOrNull,
        );
      },
    );
  }
}

class _TreatmentSummaryCard extends StatelessWidget {
  const _TreatmentSummaryCard({
    required this.title,
    required this.icon,
    required this.treatment,
  });
  final String title;
  final IconData icon;
  final FarmHealthRecord? treatment;

  @override
  Widget build(BuildContext context) {
    final due = treatment?.nextDueDate;
    final overdue = due != null && due.isBefore(DateTime.now());
    final dueSoon =
        due != null && !overdue && due.difference(DateTime.now()).inDays <= 30;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final color = overdue
        ? semantic.danger
        : dueSoon
        ? semantic.warning
        : treatment == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.primary;
    return AveraSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Text(
            title,
            maxLines: 2,
            softWrap: true,
            style: averaText(context).listItemTitle.copyWith(fontSize: 14),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _TreatmentDateValue(
                  label: 'LAST',
                  value: treatment == null
                      ? 'Not recorded'
                      : DateFormat.yMMMd().format(treatment!.occurredAt),
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TreatmentDateValue(
                  label: 'NEXT',
                  value: treatment == null
                      ? 'Not recorded'
                      : due == null
                      ? 'Not scheduled'
                      : DateFormat.yMMMd().format(due),
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TreatmentDateValue extends StatelessWidget {
  const _TreatmentDateValue({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: averaText(context).caption.copyWith(fontSize: 9)),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 2,
        softWrap: true,
        style: averaText(
          context,
        ).listItemSubtitle.copyWith(color: color, fontSize: 10.5),
      ),
    ],
  );
}

class _TreatmentListTile extends StatelessWidget {
  const _TreatmentListTile({required this.treatment, required this.onTap});
  final FarmHealthRecord treatment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    padding: EdgeInsets.zero,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          treatment.eventType == 'Vaccination'
              ? Icons.vaccines_outlined
              : Icons.medication_outlined,
        ),
      ),
      title: Text(
        '${treatment.eventType} — ${treatment.product ?? 'Not recorded'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: averaText(context).listItemTitle,
      ),
      subtitle: Text(
        [
          '${DateFormat.yMMMd().format(treatment.occurredAt)} • ${treatment.animalsCovered ?? 0} animals',
          treatment.administeredBy ?? 'Administered by not recorded',
          if (treatment.billableAmount != null)
            '${NumberFormat.currency(name: 'NGN', symbol: 'NGN ', decimalDigits: 0).format(treatment.billableAmount!)} billable',
        ].join('\n'),
        style: averaText(context).listItemSubtitle,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _RecordTreatmentSheet extends ConsumerStatefulWidget {
  const _RecordTreatmentSheet({
    required this.farmId,
    required this.unit,
    required this.populations,
    required this.session,
  });
  final String farmId;
  final FarmUnit unit;
  final List<FarmUnitPopulation> populations;
  final UserSession session;

  @override
  ConsumerState<_RecordTreatmentSheet> createState() =>
      _RecordTreatmentSheetState();
}

class _RecordTreatmentSheetState extends ConsumerState<_RecordTreatmentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _product = TextEditingController();
  final _manufacturer = TextEditingController();
  final _batch = TextEditingController();
  final _dose = TextEditingController();
  final _route = TextEditingController();
  final _animals = TextEditingController();
  final _charge = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'Deworming';
  VaccineProtocolDefinition? _protocol;
  DateTime _date = DateTime.now();
  DateTime? _nextDue;
  bool _saving = false;
  String _targetScope = 'EntireUnit';
  final Set<int> _selectedPopulationIds = {};

  int get _unitTotal => widget.populations.isEmpty
      ? widget.unit.maleCount +
            widget.unit.femaleCount +
            widget.unit.unknownCount
      : widget.populations.fold<int>(
          0,
          (sum, group) =>
              sum + group.maleCount + group.femaleCount + group.unknownCount,
        );

  int get _targetTotal {
    if (_targetScope == 'EntireUnit') return _unitTotal;
    return widget.populations
        .where((group) => _selectedPopulationIds.contains(group.id))
        .fold<int>(
          0,
          (sum, group) =>
              sum + group.maleCount + group.femaleCount + group.unknownCount,
        );
  }

  int get _animalsTreated => int.tryParse(_animals.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _animals.text = '$_unitTotal';
  }

  @override
  void dispose() {
    for (final controller in [
      _product,
      _manufacturer,
      _batch,
      _dose,
      _route,
      _animals,
      _charge,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final protocols = VaccineCatalogue.forSpecies(widget.unit.speciesId ?? '');
    const treatmentTypes = [
      'Deworming',
      'Pour-On (Ticks)',
      'Antitrypanocide',
      'Vaccination',
      'Other',
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AveraSpacing.pageHorizontalPadding,
        4,
        AveraSpacing.pageHorizontalPadding,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Record Treatment', style: averaText(context).pageTitle),
              const SizedBox(height: 4),
              Text(
                '${widget.unit.name.toUpperCase()} • $_unitTotal animals',
                style: averaText(context).listItemSubtitle,
              ),
              const SizedBox(height: 20),
              const _TreatmentSectionLabel('TREATMENT TYPE'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: treatmentTypes
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value),
                        selected: _type == value,
                        onSelected: (_) => setState(() {
                          _type = value;
                          _protocol = null;
                          if (value != 'Vaccination') _nextDue = null;
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              if (_type == 'Vaccination')
                _TreatmentField(
                  label: 'VACCINE',
                  child: DropdownButtonFormField<VaccineProtocolDefinition>(
                    value: _protocol,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: protocols.isEmpty
                          ? 'No compatible vaccine protocols'
                          : 'Select vaccine',
                    ),
                    items: protocols
                        .map(
                          (protocol) => DropdownMenuItem(
                            value: protocol,
                            child: Text(protocol.name),
                          ),
                        )
                        .toList(),
                    onChanged: protocols.isEmpty
                        ? null
                        : (value) => setState(() {
                            _protocol = value;
                            if (value != null) {
                              _product.text = value.name;
                              _route.text = value.defaultRoute.label;
                              _nextDue = value.suggestedDueDate(_date);
                            }
                          }),
                    validator: (_) =>
                        _type == 'Vaccination' && _protocol == null
                        ? 'Select a vaccine.'
                        : null,
                  ),
                )
              else
                _TreatmentField(
                  label: 'PRODUCT USED',
                  child: TextFormField(
                    controller: _product,
                    decoration: const InputDecoration(
                      hintText: 'Enter product name',
                    ),
                    validator: (value) => value?.trim().isEmpty == true
                        ? 'Enter the product used.'
                        : null,
                  ),
                ),
              const SizedBox(height: 16),
              _TreatmentFieldPair(
                left: _TreatmentField(
                  label: 'DOSE',
                  child: TextFormField(
                    controller: _dose,
                    decoration: const InputDecoration(hintText: 'e.g. 1 ml'),
                  ),
                ),
                right: _TreatmentField(
                  label: 'ROUTE',
                  child: TextFormField(
                    controller: _route,
                    decoration: const InputDecoration(hintText: 'e.g. Oral'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _TreatmentFieldPair(
                left: _TreatmentField(
                  label: 'MANUFACTURER',
                  child: TextFormField(
                    controller: _manufacturer,
                    decoration: const InputDecoration(hintText: 'Optional'),
                  ),
                ),
                right: _TreatmentField(
                  label: 'BATCH NUMBER',
                  child: TextFormField(
                    controller: _batch,
                    decoration: const InputDecoration(hintText: 'Optional'),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (widget.populations.length > 1) ...[
                const _TreatmentSectionLabel('TREAT'),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'EntireUnit',
                      label: Text('Entire unit'),
                    ),
                    ButtonSegment(
                      value: 'SelectedGroups',
                      label: Text('Selected groups'),
                    ),
                  ],
                  selected: {_targetScope},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _targetScope = selection.first;
                      if (_targetScope == 'EntireUnit') {
                        _selectedPopulationIds.clear();
                      }
                      _animals.text = '$_targetTotal';
                    });
                  },
                ),
                if (_targetScope == 'SelectedGroups') ...[
                  const SizedBox(height: 8),
                  AveraSurfaceCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: widget.populations.map((group) {
                        final count =
                            group.maleCount +
                            group.femaleCount +
                            group.unknownCount;
                        return CheckboxListTile(
                          value: _selectedPopulationIds.contains(group.id),
                          title: Text(_speciesName(group.speciesId)),
                          subtitle: Text(
                            '${_breedName(group.breedId)} • $count',
                          ),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedPopulationIds.add(group.id);
                              } else {
                                _selectedPopulationIds.remove(group.id);
                              }
                              _animals.text = _targetTotal == 0
                                  ? ''
                                  : '$_targetTotal';
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
              const _TreatmentSectionLabel('ANIMALS TREATED'),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Decrease animals treated',
                      onPressed: _animalsTreated <= 1
                          ? null
                          : () => _setAnimalsTreated(_animalsTreated - 1),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _animals,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          helperText:
                              'of $_targetTotal in this treatment target',
                        ),
                        validator: _validateAnimalCount,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Increase animals treated',
                      onPressed:
                          _targetTotal == 0 || _animalsTreated >= _targetTotal
                          ? null
                          : () => _setAnimalsTreated(_animalsTreated + 1),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _TreatmentSectionLabel('BILLING'),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                child: TextFormField(
                  controller: _charge,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    prefixText: '${widget.session.clinic.currency} ',
                    hintText: '0.00',
                    helperText: 'Optional amount for the farm visit invoice.',
                  ),
                  validator: (value) {
                    if (value?.trim().isEmpty == true) return null;
                    final parsed = double.tryParse(value!.trim());
                    return parsed == null || parsed < 0
                        ? 'Enter a valid amount.'
                        : null;
                  },
                ),
              ),
              const SizedBox(height: 20),
              const _TreatmentSectionLabel('SCHEDULE'),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _TreatmentDateRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date administered',
                      value: DateFormat.yMMMd().format(_date),
                      onTap: _pickDate,
                    ),
                    const Divider(height: 1),
                    _TreatmentDateRow(
                      icon: Icons.event_repeat_outlined,
                      label: 'Next due',
                      value: _nextDue == null
                          ? 'Not scheduled'
                          : DateFormat.yMMMd().format(_nextDue!),
                      onTap: _pickNextDue,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _TreatmentField(
                label: 'NOTES',
                child: TextFormField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Add observations or follow-up instructions',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save Treatment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setAnimalsTreated(int value) {
    setState(() => _animals.text = value.clamp(1, _targetTotal).toString());
  }

  String? _validateAnimalCount(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 1) return 'Enter at least one animal.';
    if (_targetScope == 'SelectedGroups' && _selectedPopulationIds.isEmpty) {
      return 'Select at least one animal group.';
    }
    if (parsed > _targetTotal) {
      return 'Cannot exceed the selected population ($_targetTotal).';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (value == null) return;
    setState(() {
      _date = value;
      if (_protocol != null) _nextDue = _protocol!.suggestedDueDate(value);
    });
  }

  Future<void> _pickNextDue() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _nextDue ?? _date.add(const Duration(days: 30)),
      firstDate: _date,
      lastDate: DateTime(_date.year + 10),
    );
    if (value != null) setState(() => _nextDue = value);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .recordFarmUnitTreatment(
            session: widget.session,
            farmId: widget.farmId,
            unitId: widget.unit.id,
            treatmentType: _type,
            product: _product.text,
            administeredAt: _date,
            animalsCovered: int.tryParse(_animals.text) ?? 0,
            targetScope: _targetScope,
            targetPopulationIds: _selectedPopulationIds,
            manufacturer: _manufacturer.text,
            batchNumber: _batch.text,
            dose: _dose.text,
            route: _route.text,
            nextDueDate: _nextDue,
            billableAmount: double.tryParse(_charge.text.trim()),
            notes: _notes.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _farmError(
                error,
                'Unable to save this treatment. Please try again.',
              ),
            ),
          ),
        );
        setState(() => _saving = false);
      }
    }
  }
}

class _TreatmentSectionLabel extends StatelessWidget {
  const _TreatmentSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: averaText(context).sectionLabel);
}

class _TreatmentField extends StatelessWidget {
  const _TreatmentField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_TreatmentSectionLabel(label), const SizedBox(height: 7), child],
  );
}

class _TreatmentFieldPair extends StatelessWidget {
  const _TreatmentFieldPair({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 350) {
        return Column(children: [left, const SizedBox(height: 16), right]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
    },
  );
}

class _TreatmentDateRow extends StatelessWidget {
  const _TreatmentDateRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    subtitle: Text(value),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class FarmDailyRecordDetailScreen extends ConsumerStatefulWidget {
  const FarmDailyRecordDetailScreen({
    super.key,
    required this.farmId,
    required this.recordId,
  });
  final String farmId;
  final String recordId;

  @override
  ConsumerState<FarmDailyRecordDetailScreen> createState() =>
      _FarmDailyRecordDetailScreenState();
}

class _FarmDailyRecordDetailScreenState
    extends ConsumerState<FarmDailyRecordDetailScreen> {
  late Future<FarmDailyRecordDetail?> _detail;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _detail = ref
        .read(clinicRepositoryProvider)
        .getFarmDailyRecordDetail(
          farmId: widget.farmId,
          recordId: widget.recordId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: FarmBackButton(fallbackPath: '/farm-records/${widget.farmId}'),
        title: const Text('Daily Farm Record'),
      ),
      body: FutureBuilder<FarmDailyRecordDetail?>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data;
          if (detail == null) {
            return const _DetailMessage(
              title: 'Daily record unavailable',
              message: 'This record is not available in the active clinic.',
            );
          }
          final record = detail.record;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              AveraPageHeader(
                title: detail.farm.name,
                subtitle: DateFormat.yMMMMd().format(record.recordDate),
              ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              _RecordBadge(status: record.status),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Population by Species'),
              const SizedBox(height: AveraSpacing.cardGap),
              _SpeciesMovementCard(detail: detail),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Farm Units'),
              const SizedBox(height: AveraSpacing.cardGap),
              if (detail.units.isEmpty)
                const _DetailMessage(
                  title: 'No units',
                  message: 'No farm units were attached to this record.',
                )
              else
                for (final unit in detail.units) ...[
                  AveraAdministrationCard(
                    icon: Icons.home_work_outlined,
                    title: unit.name,
                    subtitle:
                        '${_speciesName(unit.speciesId)} | ${_breedName(unit.breedId)} | '
                        '${unit.maleCount} male | ${unit.femaleCount} female | '
                        '${unit.unknownCount} unknown',
                    onTap: () => context.push(
                      '/farm-records/${widget.farmId}/units/${unit.id}',
                    ),
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                ],
              const AveraSectionHeader(title: 'Feed'),
              const SizedBox(height: AveraSpacing.cardGap),
              _FeedCard(detail: detail),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Mortality'),
              const SizedBox(height: AveraSpacing.cardGap),
              _MortalityCard(detail: detail),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Health and Management Events'),
              const SizedBox(height: AveraSpacing.cardGap),
              _EventsCard(detail: detail),
              const SizedBox(height: AveraSpacing.sectionGap),
              AveraLabeledFieldCard(
                label: 'Daily Note',
                child: Text(
                  record.dailyNote ?? 'No daily note recorded.',
                  style: averaText(context).fieldValue,
                ),
              ),
              if (record.tasksForTomorrow?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AveraSpacing.cardGap),
                AveraLabeledFieldCard(
                  label: 'Tasks for Tomorrow',
                  child: Text(
                    record.tasksForTomorrow!,
                    style: averaText(context).fieldValue,
                  ),
                ),
              ],
              const SizedBox(height: AveraSpacing.sectionGap),
              _InfoCard(
                rows: {
                  'Created by': record.createdByUserId,
                  'Created': DateFormat.yMMMd().add_jm().format(
                    record.createdAt,
                  ),
                  'Last edited by':
                      record.lastEditedByUserId ?? record.createdByUserId,
                  'Last edited': DateFormat.yMMMd().add_jm().format(
                    record.updatedAt,
                  ),
                  'Status': record.status,
                  if (record.correctionReason?.trim().isNotEmpty == true)
                    'Correction reason': record.correctionReason!,
                },
              ),
              const SizedBox(height: AveraSpacing.sectionGap),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _working ? null : () => _print(detail, session),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () => _savePdf(detail, session),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Save PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : () => _share(detail, session),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                  if (session?.can(Permissions.farmDailyRecord) == true)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final changed = await context.push<bool>(
                          '/farm-records/${widget.farmId}/daily'
                          '?recordId=${record.id}&correct=${record.status == 'Finalized'}',
                        );
                        if (changed == true && mounted) setState(_reload);
                      },
                      icon: const Icon(Icons.edit_note_outlined),
                      label: Text(
                        record.status == 'Finalized'
                            ? 'Correct Record'
                            : 'Edit Draft',
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _print(FarmDailyRecordDetail detail, UserSession? session) =>
      _run(
        () => const FarmReportService().printDailyRecord(
          detail: detail,
          preparedBy: session?.user.fullName ?? detail.record.createdByUserId,
          branding: session == null
              ? null
              : ClinicDocumentBranding.fromSession(session),
        ),
      );

  Future<void> _savePdf(FarmDailyRecordDetail detail, UserSession? session) =>
      _run(() async {
        final path = await const FarmReportService().saveDailyRecordPdf(
          detail: detail,
          preparedBy: session?.user.fullName ?? detail.record.createdByUserId,
          branding: session == null
              ? null
              : ClinicDocumentBranding.fromSession(session),
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Saved to $path')));
        }
      });

  Future<void> _share(FarmDailyRecordDetail detail, UserSession? session) =>
      _run(
        () => const FarmReportService().shareDailyRecord(
          detail: detail,
          preparedBy: session?.user.fullName ?? detail.record.createdByUserId,
          branding: session == null
              ? null
              : ClinicDocumentBranding.fromSession(session),
        ),
      );

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _farmError(error, 'Unable to continue. Please try again.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _EditUnitSheet extends ConsumerStatefulWidget {
  const _EditUnitSheet({
    required this.farmId,
    required this.unit,
    required this.populations,
  });
  final String farmId;
  final FarmUnit unit;
  final List<FarmUnitPopulation> populations;

  @override
  ConsumerState<_EditUnitSheet> createState() => _EditUnitSheetState();
}

class _EditUnitSheetState extends ConsumerState<_EditUnitSheet> {
  late final _name = TextEditingController(text: widget.unit.name);
  late final _capacity = TextEditingController(
    text: widget.unit.capacity?.toString() ?? '',
  );
  late final _type = TextEditingController(text: widget.unit.unitType);
  late final _notes = TextEditingController(text: widget.unit.notes ?? '');
  late String _status = widget.unit.status;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _type.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit Unit', style: averaText(context).pageTitle),
          const SizedBox(height: AveraSpacing.cardGap),
          if (widget.populations.length > 1) ...[
            AveraSurfaceCard(
              child: Text(
                'This mixed-species unit contains ${widget.populations.length} animal groups. Population groups remain preserved when these unit details are saved.',
                style: averaText(context).listItemSubtitle,
              ),
            ),
            const SizedBox(height: AveraSpacing.cardGap),
          ],
          for (final field in [
            ('Unit name', _name),
            ('Capacity', _capacity),
            ('Unit type', _type),
          ]) ...[
            AveraLabeledFieldCard(
              label: field.$1,
              child: TextField(
                controller: field.$2,
                keyboardType: field.$1 != 'Capacity'
                    ? TextInputType.text
                    : TextInputType.number,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
            const SizedBox(height: AveraSpacing.cardGap),
          ],
          AveraLabeledDropdownField<String>(
            label: 'Status',
            hintText: 'Unit status',
            value: _status,
            items: const [
              DropdownMenuItem(value: 'Active', child: Text('Active')),
              DropdownMenuItem(value: 'Archived', child: Text('Archived')),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _status = value ?? _status),
          ),
          const SizedBox(height: 16),
          AveraLabeledFieldCard(
            label: 'Description / Notes',
            child: TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: AveraSpacing.sectionGap),
          AveraPrimaryActionButton(
            label: 'Save Unit',
            icon: Icons.save_outlined,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_saving) return;
    final capacityText = _capacity.text.trim();
    if (capacityText.isNotEmpty &&
        (int.tryParse(capacityText) == null || int.parse(capacityText) < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a non-negative whole number for capacity.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
      await ref
          .read(clinicRepositoryProvider)
          .updateFarmUnitMetadata(
            session: session,
            farmId: widget.farmId,
            unitId: widget.unit.id,
            status: _status,
            name: _name.text,
            unitType: _type.text,
            capacity: int.tryParse(_capacity.text),
            notes: _notes.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_farmError(error, 'Unable to save unit details.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PopulationCard extends StatelessWidget {
  const _PopulationCard({required this.populations});
  final Map<String, int> populations;

  @override
  Widget build(BuildContext context) {
    final entries = populations.entries.toList()
      ..sort((a, b) => _speciesName(a.key).compareTo(_speciesName(b.key)));
    final total = entries.fold<int>(0, (sum, item) => sum + item.value);
    return AveraSurfaceCard(
      child: Column(
        children: [
          if (entries.isEmpty)
            Text(
              'No unit populations recorded.',
              style: averaText(context).listItemSubtitle,
            )
          else
            for (final entry in entries) ...[
              _KeyValueRow(
                label: _speciesPopulationLabel(entry.key, entry.value),
                value: '${entry.value}',
              ),
              if (entry != entries.last) const Divider(height: 24),
            ],
          const Divider(height: 28),
          _KeyValueRow(
            label: 'Total Population',
            value: '$total',
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _SpeciesMovementCard extends StatelessWidget {
  const _SpeciesMovementCard({required this.detail});
  final FarmDailyRecordDetail detail;

  @override
  Widget build(BuildContext context) {
    final movements = detail.speciesMovements;
    if (movements.isEmpty) {
      return AveraSurfaceCard(
        child: Column(
          children: [
            Text(
              'Legacy combined population',
              style: averaText(context).listItemTitle,
            ),
            const SizedBox(height: 10),
            _MovementRows(
              opening: detail.record.openingPopulation,
              births: detail.record.births,
              purchases: detail.record.purchases,
              transfersIn: detail.record.transfersIn,
              mortality: detail.record.mortality,
              sales: detail.record.sales,
              transfersOut: detail.record.transfersOut,
              closing: detail.record.closingPopulation,
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final movement in movements) ...[
          AveraSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _speciesName(movement.speciesId),
                  style: averaText(context).listItemTitle,
                ),
                const SizedBox(height: 10),
                _MovementRows(
                  opening: movement.openingPopulation,
                  births: movement.births,
                  purchases: movement.purchases,
                  transfersIn: movement.transfersIn,
                  mortality: movement.mortality,
                  sales: movement.sales,
                  transfersOut: movement.transfersOut,
                  closing: movement.closingPopulation,
                ),
              ],
            ),
          ),
          if (movement != movements.last)
            const SizedBox(height: AveraSpacing.cardGap),
        ],
      ],
    );
  }
}

class _MovementRows extends StatelessWidget {
  const _MovementRows({
    required this.opening,
    required this.births,
    required this.purchases,
    required this.transfersIn,
    required this.mortality,
    required this.sales,
    required this.transfersOut,
    required this.closing,
  });
  final int opening;
  final int births;
  final int purchases;
  final int transfersIn;
  final int mortality;
  final int sales;
  final int transfersOut;
  final int closing;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _KeyValueRow(label: 'Opening population', value: '$opening'),
      _KeyValueRow(label: 'Births', value: '$births'),
      _KeyValueRow(
        label: 'Purchased / transferred in',
        value: '${purchases + transfersIn}',
      ),
      _KeyValueRow(label: 'Deaths', value: '$mortality'),
      _KeyValueRow(
        label: 'Sold / transferred out',
        value: '${sales + transfersOut}',
      ),
      const Divider(height: 22),
      _KeyValueRow(
        label: 'Closing population',
        value: '$closing',
        strong: true,
      ),
    ],
  );
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.detail});
  final FarmDailyRecordDetail detail;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: detail.feedRecords.isEmpty
        ? Text(
            '${detail.record.feedSuppliedKg.toStringAsFixed(1)} kg total feed supplied.',
            style: averaText(context).fieldValue,
          )
        : Column(
            children: [
              for (final item in detail.feedRecords) ...[
                _KeyValueRow(
                  label: item.rationName,
                  value: '${item.totalSuppliedKg.toStringAsFixed(1)} kg',
                  strong: true,
                ),
                Text(
                  'Mixed ${item.totalMixedKg.toStringAsFixed(1)} kg | Remaining ${item.remainingKg.toStringAsFixed(1)} kg',
                  style: averaText(context).caption,
                ),
                if (item != detail.feedRecords.last) const Divider(height: 24),
              ],
            ],
          ),
  );
}

class _MortalityCard extends StatelessWidget {
  const _MortalityCard({required this.detail});
  final FarmDailyRecordDetail detail;

  @override
  Widget build(BuildContext context) {
    final speciesMortality = detail.speciesMovements
        .where((movement) => movement.mortality > 0)
        .toList();
    return AveraSurfaceCard(
      child: detail.mortalityRecords.isEmpty && speciesMortality.isEmpty
          ? Text(
              detail.record.mortality == 0
                  ? 'No mortality recorded.'
                  : '${detail.record.mortality} mortality in the legacy combined total.',
              style: averaText(context).fieldValue,
            )
          : Column(
              children: [
                if (detail.mortalityRecords.isEmpty)
                  for (final movement in speciesMortality) ...[
                    _KeyValueRow(
                      label: _speciesName(movement.speciesId),
                      value: '${movement.mortality}',
                      strong: true,
                    ),
                    Text(
                      'Cause and notes were not recorded.',
                      style: averaText(context).caption,
                    ),
                    if (movement != speciesMortality.last)
                      const Divider(height: 24),
                  ],
                for (final item in detail.mortalityRecords) ...[
                  _KeyValueRow(
                    label: _speciesName(item.speciesId),
                    value: '${item.numberDead}',
                    strong: true,
                  ),
                  Text(
                    '${item.suspectedCause}${item.notes == null ? '' : ' | ${item.notes}'}',
                    style: averaText(context).caption,
                  ),
                  if (item != detail.mortalityRecords.last)
                    const Divider(height: 24),
                ],
              ],
            ),
    );
  }
}

class _EventsCard extends StatelessWidget {
  const _EventsCard({required this.detail});
  final FarmDailyRecordDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.events.isEmpty && detail.healthRecords.isEmpty) {
      return AveraSurfaceCard(
        child: Text(
          'No health or management events recorded.',
          style: averaText(context).fieldValue,
        ),
      );
    }
    return AveraSurfaceCard(
      child: Column(
        children: [
          for (final item in detail.healthRecords) ...[
            _KeyValueRow(
              label: item.eventType,
              value: item.product ?? '-',
              strong: true,
            ),
            Text(
              [
                item.purpose,
                item.dose,
                item.route,
                item.notes,
              ].whereType<String>().join(' | '),
              style: averaText(context).caption,
            ),
            const Divider(height: 24),
          ],
          for (final item in detail.events) ...[
            _KeyValueRow(
              label: item.eventType,
              value: DateFormat.jm().format(item.occurredAt),
              strong: true,
            ),
            Text(
              item.description ?? 'No description',
              style: averaText(context).caption,
            ),
            if (item != detail.events.last) const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      children: [
        for (final entry in rows.entries) ...[
          _KeyValueRow(label: entry.key, value: entry.value),
          if (entry.key != rows.keys.last) const Divider(height: 24),
        ],
      ],
    ),
  );
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.strong = false,
  });
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: averaText(context).listItemSubtitle),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: strong
                ? averaText(context).listItemTitle
                : averaText(context).fieldValue,
          ),
        ),
      ],
    ),
  );
}

class _RecordBadge extends StatelessWidget {
  const _RecordBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Chip(
      avatar: Icon(
        status == 'Finalized'
            ? Icons.task_alt_rounded
            : Icons.edit_note_rounded,
        size: 18,
      ),
      label: Text(status),
    ),
  );
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: averaText(context).listItemTitle,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: averaText(context).listItemSubtitle,
          ),
        ],
      ),
    ),
  );
}

String _speciesName(String? id) =>
    AnimalCatalogue.speciesById(id)?.displayName ??
    (id == null || id == 'unassigned' ? 'Unassigned legacy animals' : id);

String _breedName(String? id) {
  return AnimalCatalogue.breedDisplayName(id);
}

String _speciesPopulationLabel(String id, int count) {
  final name = _speciesName(id);
  if (name == 'Cattle' || name == 'Sheep') return name;
  if (count == 1) return name;
  if (name.endsWith('s')) return name;
  return '${name}s';
}

String _speciesNames(String json) {
  try {
    return (jsonDecode(json) as List)
        .map((id) => _speciesName('$id'))
        .join(', ');
  } catch (_) {
    return 'Not recorded';
  }
}

String _breedNames(String json) {
  try {
    final values = (jsonDecode(json) as List)
        .map((id) => _breedName('$id'))
        .toList();
    return values.isEmpty ? 'No breeds recorded' : values.join(', ');
  } catch (_) {
    return 'No breeds recorded';
  }
}

Color _movementColor(String type) => type == 'sale'
    ? const Color(0xffd97706)
    : type == 'mortality'
    ? const Color(0xffd9303e)
    : const Color(0xff008b84);
String _percent(int count, int total) =>
    total == 0 ? '0' : (count * 100 / total).toStringAsFixed(1);

String _farmError(Object error, String fallback) {
  developer.log('Farm operation failed', name: 'avera.farm', error: error);
  if (error is ApiException) {
    return switch (error.code) {
      'insufficient_population' =>
        'There are not enough animals in the selected sex group. Reopen the form to check current stock.',
      'farm_archived' =>
        'Reactivate the farm or unit before recording a movement.',
      'permission_required' =>
        'You do not have permission to change this farm unit.',
      'session_expired' => 'Please sign in again to continue.',
      _ => fallback,
    };
  }
  if (error is StateError) {
    final message = error.message.toString();
    if (message.startsWith('Only ') ||
        message.startsWith('Enter ') ||
        message.startsWith('Reactivate ') ||
        message.startsWith('Amend the finalized') ||
        message.startsWith('The selected farm population')) {
      return message;
    }
  }
  return fallback;
}

class FarmUnitPopulationStats extends StatelessWidget {
  const FarmUnitPopulationStats({super.key, required this.unit});
  final FarmUnit unit;
  @override
  Widget build(BuildContext context) {
    final total = unit.maleCount + unit.femaleCount + unit.unknownCount;
    final capacity = unit.capacity;
    final ratio = capacity == null || capacity <= 0 ? null : total / capacity;
    final exceeded = capacity != null && total > capacity;
    final color = exceeded
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    Widget stat(
      String label,
      String value,
      String subtitle,
      IconData icon,
      Color tint, {
      bool progress = false,
    }) => AveraSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tint),
              const SizedBox(width: 8),
              Flexible(child: Text(label)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (progress) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: ratio?.clamp(0, 1) ?? 0,
              color: color,
              minHeight: 7,
              borderRadius: BorderRadius.circular(10),
            ),
          ],
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: progress ? color : null)),
        ],
      ),
    );
    final cards = [
      stat(
        'Total Animals',
        capacity == null ? '$total' : '$total / $capacity',
        ratio == null
            ? 'Capacity not set'
            : '${(ratio * 100).round()}% capacity',
        Icons.groups_outlined,
        color,
        progress: true,
      ),
      stat(
        'Males',
        '${unit.maleCount}',
        '${_percent(unit.maleCount, total)}%',
        Icons.male,
        Colors.blue,
      ),
      stat(
        'Females',
        '${unit.femaleCount}',
        '${_percent(unit.femaleCount, total)}%',
        Icons.female,
        Colors.pink,
      ),
      stat(
        'Unknown',
        '${unit.unknownCount}',
        '${_percent(unit.unknownCount, total)}%',
        Icons.help_outline,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards)
                SizedBox(
                  width: c.maxWidth >= 800
                      ? (c.maxWidth - 36) / 4
                      : (c.maxWidth - 12) / 2,
                  child: card,
                ),
            ],
          ),
        ),
        if (exceeded)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Population exceeds unit capacity by ${total - capacity} animals.',
              style: TextStyle(color: color),
            ),
          ),
      ],
    );
  }
}

class _SexDonutPainter extends CustomPainter {
  _SexDonutPainter(this.counts, this.emptyColor);
  final List<int> counts;
  final Color emptyColor;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(16, 16, size.width - 32, size.height - 32);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 27;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = emptyColor);
    final total = counts.fold<int>(0, (sum, count) => sum + count);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < counts.length; i++) {
      final sweep = counts[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        paint
          ..color = [
            const Color(0xff008b84),
            const Color(0xff8ddbd6),
            Colors.grey,
          ][i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SexDonutPainter oldDelegate) =>
      oldDelegate.counts.toString() != counts.toString() ||
      oldDelegate.emptyColor != emptyColor;
}
