import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/animal_catalogue.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/catalogue_selector.dart';
import '../widgets/farm_back_navigation.dart';
import 'farm_detail_screens.dart';

class FarmRecordsScreen extends ConsumerStatefulWidget {
  const FarmRecordsScreen({super.key});

  @override
  ConsumerState<FarmRecordsScreen> createState() => _FarmRecordsScreenState();
}

class _FarmRecordsScreenState extends ConsumerState<FarmRecordsScreen> {
  String _query = '';
  String _status = 'Active';
  Stream<List<FarmDashboardData>>? _dashboards;
  String? _clinicId;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final canCreate = session.can(Permissions.farmsCreate);
    if (!session.can(Permissions.farmsView)) {
      return const Scaffold(body: _FarmDenied());
    }
    if (_clinicId != session.clinic.clinicId) {
      _clinicId = session.clinic.clinicId;
      _dashboards = ref.read(clinicRepositoryProvider).watchFarmDashboards();
    }
    return Scaffold(
      appBar: AppBar(
        leading: const FarmBackButton(fallbackPath: '/more'),
        title: const Text('Farm Records'),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/farm-records/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Farm'),
            )
          : null,
      body: SafeArea(
        child: StreamBuilder<List<FarmDashboardData>>(
          stream: _dashboards,
          builder: (context, snapshot) {
            final all = snapshot.data ?? const <FarmDashboardData>[];
            final selected = all
                .where((data) => data.farm.status == _status)
                .toList();
            final farms = selected
                .where(
                  (data) =>
                      data.farm.name.toLowerCase().contains(
                        _query.toLowerCase(),
                      ) ||
                      (data.farm.location ?? '').toLowerCase().contains(
                        _query.toLowerCase(),
                      ),
                )
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.pageTopPadding,
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.bottomContentClearance,
              ),
              children: [
                Text(
                  'Manage livestock farms and daily production records.',
                  style: averaText(context).pageSubtitle,
                ),
                const SizedBox(height: AveraSpacing.subtitleToContentGap),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search farms...',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['Active', 'Archived']
                      .map(
                        (status) => ChoiceChip(
                          label: Text(
                            '$status (${all.where((data) => data.farm.status == status).length})',
                          ),
                          selected: _status == status,
                          onSelected: (_) => setState(() => _status = status),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: AveraSpacing.cardGap),
                if (snapshot.hasData) ...[
                  FarmPopulationSummary(
                    dashboards: selected,
                    countLabel: _status == 'Active'
                        ? 'Active Farms'
                        : 'Archived Farms',
                    count: selected.length,
                  ),
                  const SizedBox(height: AveraSpacing.sectionGap),
                  AveraSectionHeader(
                    title: 'Farms (${farms.length})',
                    action: canCreate
                        ? TextButton.icon(
                            onPressed: () => context.push('/farm-records/new'),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Farm'),
                          )
                        : null,
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                ],
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.hasError)
                  const _FarmMessage(
                    icon: Icons.error_outline_rounded,
                    title: 'Farm records unavailable',
                    message:
                        'Try again. Existing clinic data remains unchanged.',
                  )
                else if (farms.isEmpty)
                  const _FarmMessage(
                    icon: Icons.agriculture_outlined,
                    title: 'No farms yet',
                    message:
                        'Add a farm to begin tracking populations, feed and daily records.',
                  )
                else
                  for (final farm in farms) ...[
                    _FarmCard(data: farm),
                    const SizedBox(height: AveraSpacing.cardGap),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class FarmDetailScreen extends ConsumerStatefulWidget {
  const FarmDetailScreen({super.key, required this.farmId});

  final String farmId;

  @override
  ConsumerState<FarmDetailScreen> createState() => _FarmDetailScreenState();
}

class _FarmDetailScreenState extends ConsumerState<FarmDetailScreen> {
  late Stream<List<FarmDashboardData>> _dashboard;
  String? _clinicId;
  String _section = 'Animals';
  String _query = '';
  String? _species;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() =>
      _dashboard = ref.read(clinicRepositoryProvider).watchFarmDashboards();

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.can(Permissions.farmsView)) {
      return const Scaffold(body: _FarmDenied());
    }
    if (_clinicId != session.clinic.clinicId) {
      _clinicId = session.clinic.clinicId;
      _refresh();
    }
    return Scaffold(
      appBar: AppBar(
        leading: const FarmBackButton(fallbackPath: '/farm-records'),
        title: const Text('Farm Details'),
        actions: [
          if (session.can(Permissions.farmsCreate))
            IconButton(
              tooltip: 'Edit Farm',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  context.push('/farm-records/${widget.farmId}/edit'),
            ),
        ],
      ),
      floatingActionButton: session.can(Permissions.farmDailyRecord)
          ? FloatingActionButton.extended(
              onPressed: () async {
                final repository = ref.read(clinicRepositoryProvider);
                final existing = await repository.getFarmDailyRecordForDate(
                  widget.farmId,
                  DateTime.now(),
                );
                if (!context.mounted) return;
                final route = existing == null
                    ? '/farm-records/${widget.farmId}/daily'
                    : existing.status == 'Finalized'
                    ? '/farm-records/${widget.farmId}/daily/${existing.id}'
                    : '/farm-records/${widget.farmId}/daily'
                          '?recordId=${existing.id}';
                final changed = await context.push<bool>(route);
                if (changed == true && context.mounted) setState(_refresh);
              },
              icon: const Icon(Icons.today_outlined),
              label: const Text('Daily Record'),
            )
          : null,
      body: SafeArea(
        child: StreamBuilder<List<FarmDashboardData>>(
          stream: _dashboard,
          builder: (context, snapshot) {
            final matches = snapshot.data?.where(
              (data) => data.farm.id == widget.farmId,
            );
            final data = matches == null || matches.isEmpty
                ? null
                : matches.first;
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
            if (data == null) {
              return const _FarmMessage(
                icon: Icons.error_outline_rounded,
                title: 'Farm unavailable',
                message: 'This farm is not available in the active clinic.',
              );
            }
            final species = data.populationBySpecies.keys.toList();
            final visibleUnits = data.units.where((unit) {
              final groups = data.populations.where(
                (group) => group.farmUnitId == unit.id,
              );
              return unit.name.toLowerCase().contains(_query.toLowerCase()) &&
                  (_species == null ||
                      groups.any((group) => group.speciesId == _species) ||
                      (groups.isEmpty && unit.speciesId == _species));
            }).toList();
            return RefreshIndicator(
              onRefresh: () async => setState(_refresh),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  AveraSpacing.bottomContentClearance,
                ),
                children: [
                  Text(data.farm.name, style: averaText(context).pageTitle),
                  const SizedBox(height: 6),
                  Text(
                    data.farm.location ?? 'Location not recorded',
                    style: averaText(context).pageSubtitle,
                  ),
                  const SizedBox(height: AveraSpacing.subtitleToContentGap),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(label: Text(data.farm.status)),
                  ),
                  FarmPopulationSummary(
                    dashboards: [data],
                    countLabel: 'Active Units',
                    count: data.activeUnits.length,
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final section in [
                        'Animals',
                        'Farm Settings',
                        'Records',
                      ])
                        ChoiceChip(
                          label: Text(section),
                          selected: _section == section,
                          onSelected: (_) => setState(() => _section = section),
                        ),
                    ],
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                  if (_section == 'Farm Settings')
                    InkWell(
                      borderRadius: BorderRadius.circular(
                        AveraSpacing.cardRadius,
                      ),
                      onTap: () => context.push(
                        '/farm-records/${data.farm.id}/overview',
                      ),
                      child: AveraSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    species.isEmpty
                                        ? 'Species not recorded'
                                        : species
                                              .map(
                                                (id) =>
                                                    AnimalCatalogue.speciesById(
                                                      id,
                                                    )?.displayName ??
                                                    id,
                                              )
                                              .join(' | '),
                                    style: averaText(context).listItemSubtitle,
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _Metric(
                                    label: 'Population',
                                    value: '${data.currentPopulation} animals',
                                  ),
                                ),
                                Expanded(
                                  child: _Metric(
                                    label: 'Units',
                                    value: '${data.activeUnits.length} active',
                                  ),
                                ),
                              ],
                            ),
                            if (data.populationBySpecies.isNotEmpty) ...[
                              const Divider(height: 28),
                              for (final entry
                                  in data.populationBySpecies.entries) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        AnimalCatalogue.speciesById(
                                              entry.key,
                                            )?.displayName ??
                                            'Unassigned',
                                        style: averaText(
                                          context,
                                        ).listItemSubtitle,
                                      ),
                                    ),
                                    Text(
                                      '${entry.value}',
                                      style: averaText(context).fieldValue,
                                    ),
                                  ],
                                ),
                                if (entry !=
                                    data.populationBySpecies.entries.last)
                                  const SizedBox(height: 8),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (_section == 'Farm Settings') ...[
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Edit Farm Details'),
                      onTap: session.can(Permissions.farmsCreate)
                          ? () => context.push(
                              '/farm-records/${data.farm.id}/edit',
                            )
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Farm Overview & Billing'),
                      onTap: () => context.push(
                        '/farm-records/${data.farm.id}/overview',
                      ),
                    ),
                  ],
                  if (_section == 'Animals') ...[
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search animals...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text('All (${data.currentPopulation})'),
                          selected: _species == null,
                          onSelected: (_) => setState(() => _species = null),
                        ),
                        for (final entry in data.populationBySpecies.entries)
                          ChoiceChip(
                            label: Text(
                              '${AnimalCatalogue.speciesById(entry.key)?.displayName ?? entry.key} (${entry.value})',
                            ),
                            selected: _species == entry.key,
                            onSelected: (_) =>
                                setState(() => _species = entry.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: AveraSpacing.sectionGap),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Farm Units',
                            style: averaText(context).sectionTitle,
                          ),
                        ),
                        if (session.can(Permissions.farmUnitsManage))
                          TextButton.icon(
                            onPressed: () async {
                              final changed = await showModalBottomSheet<bool>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (_) =>
                                    _AddUnitSheet(farmId: data.farm.id),
                              );
                              if (changed == true && mounted) {
                                setState(_refresh);
                              }
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add Unit'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (visibleUnits.isEmpty)
                      const _FarmMessage(
                        icon: Icons.home_work_outlined,
                        title: 'No farm units',
                        message:
                            'Add pens, sectors, houses or paddocks to track occupancy.',
                      )
                    else
                      for (final unit in visibleUnits) ...[
                        AveraSurfaceCard(
                          child: ListTile(
                            onTap: () async {
                              await context.push<bool>(
                                '/farm-records/${data.farm.id}/units/${unit.id}',
                              );
                              if (mounted) setState(_refresh);
                            },
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              child: Icon(Icons.home_work_outlined),
                            ),
                            title: Text(
                              unit.name,
                              style: averaText(context).listItemTitle,
                            ),
                            subtitle: Text(
                              '${AnimalCatalogue.speciesById(unit.speciesId ?? '')?.displayName ?? 'Species not assigned'} | '
                              '${unit.unitType} | ${unit.maleCount} male | '
                              '${unit.femaleCount} female | ${unit.unknownCount} unknown',
                              style: averaText(context).listItemSubtitle,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (unit.capacity != null)
                                  Text(
                                    '${unit.maleCount + unit.femaleCount + unit.unknownCount}/${unit.capacity}',
                                    style: averaText(context).caption,
                                  ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AveraSpacing.cardGap),
                      ],
                  ],
                  if (_section == 'Records') ...[
                    const SizedBox(height: AveraSpacing.sectionGap),
                    Text(
                      'Daily Records',
                      style: averaText(context).sectionTitle,
                    ),
                    const SizedBox(height: 8),
                    if (data.dailyRecords.isEmpty)
                      const _FarmMessage(
                        icon: Icons.edit_calendar_outlined,
                        title: 'No daily records',
                        message:
                            'Create today\'s record to reconcile population, mortality and feed.',
                      )
                    else
                      for (final record in data.dailyRecords.take(10)) ...[
                        AveraSurfaceCard(
                          child: ListTile(
                            onTap: () => context.push(
                              '/farm-records/${data.farm.id}/daily/${record.id}',
                            ),
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Icon(
                                record.status == 'Finalized'
                                    ? Icons.task_alt_rounded
                                    : Icons.edit_note_rounded,
                              ),
                            ),
                            title: Text(
                              DateFormat.yMMMMd().format(record.recordDate),
                              style: averaText(context).listItemTitle,
                            ),
                            subtitle: Text(
                              'Opening ${record.openingPopulation} - Closing ${record.closingPopulation} - ${record.feedSuppliedKg.toStringAsFixed(1)} kg feed',
                              style: averaText(context).listItemSubtitle,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _RecordStatus(status: record.status),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AveraSpacing.cardGap),
                      ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class FarmDailyRecordScreen extends ConsumerStatefulWidget {
  const FarmDailyRecordScreen({super.key, required this.farmId});
  final String farmId;
  @override
  ConsumerState<FarmDailyRecordScreen> createState() =>
      _FarmDailyRecordScreenState();
}

class _FarmDailyRecordScreenState extends ConsumerState<FarmDailyRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _opening = TextEditingController(text: '0');
  final _births = TextEditingController(text: '0');
  final _purchases = TextEditingController(text: '0');
  final _transfersIn = TextEditingController(text: '0');
  final _mortality = TextEditingController(text: '0');
  final _sales = TextEditingController(text: '0');
  final _transfersOut = TextEditingController(text: '0');
  final _feed = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _tasks = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _opening,
      _births,
      _purchases,
      _transfersIn,
      _mortality,
      _sales,
      _transfersOut,
      _feed,
      _note,
      _tasks,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;
  double _double(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;
  int get _closing =>
      _int(_opening) +
      _int(_births) +
      _int(_purchases) +
      _int(_transfersIn) -
      _int(_mortality) -
      _int(_sales) -
      _int(_transfersOut);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: FarmBackButton(fallbackPath: '/farm-records/${widget.farmId}'),
      title: const Text('Daily Farm Record'),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          const AveraPageHeader(
            title: 'Daily Farm Record',
            subtitle: 'Reconcile population, feed and important farm notes.',
          ),
          const SizedBox(height: AveraSpacing.subtitleToContentGap),
          AveraLabeledFieldCard(
            label: 'Record Date',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(DateFormat.yMMMMd().format(_date)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: AveraSpacing.sectionGap),
          const AveraSectionHeader(title: 'Population Movement'),
          const SizedBox(height: 12),
          Text(
            'Use Farm Unit actions to record purchases and mortality. Those totals are reconciled here automatically.',
            style: averaText(context).caption,
          ),
          const SizedBox(height: 12),
          _numberField('Opening Population', _opening),
          _numberField('Births', _births),
          _numberField('Purchases', _purchases, readOnly: true),
          _numberField('Transfers In', _transfersIn),
          _numberField('Mortality', _mortality, readOnly: true),
          _numberField('Sales', _sales),
          _numberField('Transfers Out', _transfersOut),
          AveraSurfaceCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CLOSING POPULATION',
                  style: averaText(context).sectionLabel,
                ),
                Text('$_closing', style: averaText(context).listItemTitle),
              ],
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          _decimalField('Feed Supplied (kg)', _feed),
          const SizedBox(height: AveraSpacing.cardGap),
          AveraLabeledFieldCard(
            label: 'Daily Note',
            child: TextFormField(
              controller: _note,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText:
                    'Important observations, instructions or follow-up notes',
              ),
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          AveraLabeledFieldCard(
            label: 'Tasks for Tomorrow',
            child: TextFormField(
              controller: _tasks,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Enter follow-up actions',
              ),
            ),
          ),
          const SizedBox(height: AveraSpacing.sectionGap),
          AveraPrimaryActionButton(
            label: _saving ? 'Saving...' : 'Save Draft',
            icon: Icons.save_outlined,
            onPressed: _saving ? null : () => _save(finalize: false),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : () => _save(finalize: true),
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Finalize Daily Record'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _numberField(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AveraSpacing.cardGap),
    child: AveraLabeledFieldCard(
      label: label,
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: '0'),
        validator: (value) => (int.tryParse(value ?? '') ?? -1) < 0
            ? 'Enter zero or a positive number.'
            : null,
        onChanged: (_) => setState(() {}),
      ),
    ),
  );
  Widget _decimalField(String label, TextEditingController controller) =>
      AveraLabeledFieldCard(
        label: label,
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0.0'),
          validator: (value) => (double.tryParse(value ?? '') ?? -1) < 0
              ? 'Enter zero or a positive number.'
              : null,
        ),
      );

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime(DateTime.now().year + 1),
      initialDate: _date,
    );
    if (result != null && mounted) setState(() => _date = result);
  }

  Future<void> _save({required bool finalize}) async {
    if (!_formKey.currentState!.validate() || _closing < 0) {
      if (_closing < 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Closing population cannot be negative.'),
          ),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
      await ref
          .read(clinicRepositoryProvider)
          .saveFarmDailyRecord(
            session: session,
            farmId: widget.farmId,
            recordDate: _date,
            openingPopulation: _int(_opening),
            births: _int(_births),
            purchases: _int(_purchases),
            transfersIn: _int(_transfersIn),
            mortality: _int(_mortality),
            sales: _int(_sales),
            transfersOut: _int(_transfersOut),
            feedSuppliedKg: _double(_feed),
            dailyNote: _note.text,
            tasksForTomorrow: _tasks.text,
            finalize: finalize,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              finalize
                  ? 'Daily farm record finalized.'
                  : 'Daily farm record saved.',
            ),
          ),
        );
        context.pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AddUnitSheet extends ConsumerStatefulWidget {
  const _AddUnitSheet({required this.farmId});
  final String farmId;
  @override
  ConsumerState<_AddUnitSheet> createState() => _AddUnitSheetState();
}

class _AddUnitSheetState extends ConsumerState<_AddUnitSheet> {
  final _name = TextEditingController();
  final _capacity = TextEditingController();
  final _male = TextEditingController(text: '0');
  final _female = TextEditingController(text: '0');
  final _unknown = TextEditingController(text: '0');
  String _type = 'Pen';
  String? _speciesId;
  String? _breedId;
  bool _mixedSpecies = false;
  final List<_FarmPopulationDraft> _populationDrafts = [];
  bool _saving = false;
  late final Future<FarmDashboardData?> _farmData;

  @override
  void initState() {
    super.initState();
    _farmData = ref
        .read(clinicRepositoryProvider)
        .getFarmDashboard(widget.farmId);
    _populationDrafts.addAll([_FarmPopulationDraft(), _FarmPopulationDraft()]);
  }

  @override
  void dispose() {
    for (final controller in [_name, _capacity, _male, _female, _unknown]) {
      controller.dispose();
    }
    for (final draft in _populationDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Farm Unit', style: averaText(context).sectionTitle),
          const SizedBox(height: 16),
          AveraLabeledFieldCard(
            label: 'Unit Name',
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                hintText: 'Sector A, Pen 1 or House 2',
              ),
            ),
          ),
          const SizedBox(height: 12),
          AveraLabeledFieldCard(
            label: 'Unit Type',
            child: DropdownButtonFormField<String>(
              value: _type,
              items: const ['Pen', 'Sector', 'House', 'Paddock', 'Cage']
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
          ),
          const SizedBox(height: 12),
          Text('Population Type', style: averaText(context).sectionLabel),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Single species')),
              ButtonSegment(value: true, label: Text('Mixed species')),
            ],
            selected: {_mixedSpecies},
            onSelectionChanged: (selection) =>
                setState(() => _mixedSpecies = selection.first),
          ),
          const SizedBox(height: 12),
          FutureBuilder<FarmDashboardData?>(
            future: _farmData,
            builder: (context, snapshot) {
              final farm = snapshot.data?.farm;
              final configuredSpecies = farm == null
                  ? const <String>[]
                  : _jsonStringList(farm.speciesJson);
              final speciesOptions = configuredSpecies
                  .where((id) => AnimalCatalogue.speciesById(id) != null)
                  .toList();
              if (_mixedSpecies) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Animal Groups',
                      style: averaText(context).sectionLabel,
                    ),
                    const SizedBox(height: 8),
                    for (
                      var index = 0;
                      index < _populationDrafts.length;
                      index++
                    ) ...[
                      _FarmPopulationDraftCard(
                        key: ValueKey(_populationDrafts[index]),
                        draft: _populationDrafts[index],
                        speciesOptions: speciesOptions,
                        canRemove: _populationDrafts.length > 2,
                        onChanged: () => setState(() {}),
                        onRemove: () {
                          final draft = _populationDrafts.removeAt(index);
                          draft.dispose();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: () => setState(
                        () => _populationDrafts.add(_FarmPopulationDraft()),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Animal Group'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total: ${_populationDrafts.fold<int>(0, (sum, draft) => sum + draft.total)} animals',
                      style: averaText(context).listItemTitle,
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  CatalogueSelectionField(
                    key: const Key('farm-unit-species-selector'),
                    label: 'Species',
                    value: AnimalCatalogue.speciesById(_speciesId)?.displayName,
                    hintText:
                        snapshot.connectionState == ConnectionState.waiting
                        ? 'Loading species...'
                        : 'Search species',
                    enabled: speciesOptions.isNotEmpty,
                    onTap: () => _selectUnitSpecies(speciesOptions),
                  ),
                  const SizedBox(height: 12),
                  CatalogueSelectionField(
                    key: const Key('farm-unit-breed-selector'),
                    label: 'Breed or Type',
                    value: _breedId == null
                        ? null
                        : AnimalCatalogue.breedDisplayName(_breedId),
                    hintText: _speciesId == null
                        ? 'Select a species first'
                        : 'Search breed or type',
                    enabled: _speciesId != null,
                    onTap: _selectUnitBreed,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          AveraLabeledFieldCard(
            label: 'Capacity',
            child: TextField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Optional'),
            ),
          ),
          const SizedBox(height: 12),
          if (!_mixedSpecies)
            Row(
              children: [
                Expanded(child: _count('Male', _male)),
                const SizedBox(width: 8),
                Expanded(child: _count('Female', _female)),
                const SizedBox(width: 8),
                Expanded(child: _count('Unknown', _unknown)),
              ],
            ),
          const SizedBox(height: 20),
          AveraPrimaryActionButton(
            label: _saving ? 'Adding...' : 'Add Unit',
            icon: Icons.add_home_work_outlined,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    ),
  );
  Widget _count(String label, TextEditingController controller) =>
      AveraLabeledFieldCard(
        label: label,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0'),
        ),
      );

  Future<void> _selectUnitSpecies(List<String> speciesIds) async {
    final options = speciesIds
        .map(AnimalCatalogue.speciesById)
        .whereType<AnimalSpeciesOption>();
    final selected = await showSearchableCatalogueSelector(
      context: context,
      title: 'Select Unit Species',
      selectedId: _speciesId,
      options: animalSpeciesPickerOptions(species: options),
    );
    if (selected != null && mounted && selected != _speciesId) {
      setState(() {
        _speciesId = selected;
        _breedId = null;
      });
    }
  }

  Future<void> _selectUnitBreed() async {
    final speciesId = _speciesId;
    final species = AnimalCatalogue.speciesById(speciesId);
    if (speciesId == null || species == null) return;
    final selected = await showSearchableCatalogueSelector(
      context: context,
      title: 'Select ${species.displayName} Breed',
      selectedId: _breedId,
      options: [
        ...animalBreedPickerOptions(speciesId),
        if (AnimalCatalogue.isCustomBreedId(_breedId))
          CataloguePickerOption(
            id: _breedId!,
            title: AnimalCatalogue.breedDisplayName(_breedId),
            subtitle: 'Custom breed',
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final breed = AnimalCatalogue.breedById(selected);
    if (breed?.allowsCustomBreed == true &&
        !AnimalCatalogue.isCustomBreedId(selected)) {
      final customName = await requestCustomBreedName(
        context: context,
        species: species,
      );
      if (customName == null || !mounted) return;
      setState(() {
        _breedId = AnimalCatalogue.customBreedId(
          speciesId: speciesId,
          name: customName,
        );
      });
      return;
    }
    setState(() => _breedId = selected);
  }

  Future<void> _save() async {
    final values = [
      _male,
      _female,
      _unknown,
    ].map((controller) => int.tryParse(controller.text) ?? -1).toList();
    final populations = _mixedSpecies
        ? _populationDrafts.map((draft) => draft.toInput()).toList()
        : const <FarmUnitPopulationInput>[];
    final invalidMixed =
        _mixedSpecies &&
        (_populationDrafts.length < 2 ||
            populations.any(
              (item) =>
                  item.speciesId.isEmpty ||
                  [
                    item.maleCount,
                    item.femaleCount,
                    item.unknownCount,
                  ].any((value) => value < 0),
            ));
    if (_name.text.trim().isEmpty ||
        (!_mixedSpecies && _speciesId == null) ||
        (!_mixedSpecies && values.any((value) => value < 0)) ||
        invalidMixed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a unit name, select its species and use valid population counts.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
      await ref
          .read(clinicRepositoryProvider)
          .createFarmUnit(
            session: session,
            farmId: widget.farmId,
            name: _name.text,
            unitType: _type,
            speciesId: _speciesId,
            breedId: _breedId,
            capacity: int.tryParse(_capacity.text),
            maleCount: values[0],
            femaleCount: values[1],
            unknownCount: values[2],
            populations: populations,
          );
      if (mounted) {
        context.pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _FarmPopulationDraft {
  String? speciesId;
  String? breedId;
  final male = TextEditingController(text: '0');
  final female = TextEditingController(text: '0');
  final unknown = TextEditingController(text: '0');

  int _value(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? -1;

  int get total => [male, female, unknown]
      .map(_value)
      .where((value) => value > 0)
      .fold(0, (sum, value) => sum + value);

  FarmUnitPopulationInput toInput() => FarmUnitPopulationInput(
    speciesId: speciesId ?? '',
    breedId: breedId,
    maleCount: _value(male),
    femaleCount: _value(female),
    unknownCount: _value(unknown),
  );

  void dispose() {
    male.dispose();
    female.dispose();
    unknown.dispose();
  }
}

class _FarmPopulationDraftCard extends StatelessWidget {
  const _FarmPopulationDraftCard({
    super.key,
    required this.draft,
    required this.speciesOptions,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _FarmPopulationDraft draft;
  final List<String> speciesOptions;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AveraSurfaceCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Animal Group',
                  style: averaText(context).listItemTitle,
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: 'Remove animal group',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          CatalogueSelectionField(
            key: const Key('mixed-population-species-selector'),
            label: 'Species',
            value: AnimalCatalogue.speciesById(draft.speciesId)?.displayName,
            hintText: 'Search species',
            enabled: speciesOptions.isNotEmpty,
            onTap: () => _selectSpecies(context),
          ),
          const SizedBox(height: 10),
          CatalogueSelectionField(
            key: const Key('mixed-population-breed-selector'),
            label: 'Breed or type',
            value: draft.breedId == null
                ? null
                : AnimalCatalogue.breedDisplayName(draft.breedId),
            hintText: draft.speciesId == null
                ? 'Select a species first'
                : 'Search breed or type',
            enabled: draft.speciesId != null,
            onTap: () => _selectBreed(context),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final entry in [
                ('Male', draft.male),
                ('Female', draft.female),
                ('Unknown', draft.unknown),
              ]) ...[
                Expanded(
                  child: TextField(
                    controller: entry.$2,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: entry.$1),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                if (entry.$1 != 'Unknown') const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectSpecies(BuildContext context) async {
    final options = speciesOptions
        .map(AnimalCatalogue.speciesById)
        .whereType<AnimalSpeciesOption>();
    final selected = await showSearchableCatalogueSelector(
      context: context,
      title: 'Select Group Species',
      selectedId: draft.speciesId,
      options: animalSpeciesPickerOptions(species: options),
    );
    if (selected != null && selected != draft.speciesId) {
      draft.speciesId = selected;
      draft.breedId = null;
      onChanged();
    }
  }

  Future<void> _selectBreed(BuildContext context) async {
    final speciesId = draft.speciesId;
    final species = AnimalCatalogue.speciesById(speciesId);
    if (speciesId == null || species == null) return;
    final selected = await showSearchableCatalogueSelector(
      context: context,
      title: 'Select ${species.displayName} Breed',
      selectedId: draft.breedId,
      options: [
        ...animalBreedPickerOptions(speciesId),
        if (AnimalCatalogue.isCustomBreedId(draft.breedId))
          CataloguePickerOption(
            id: draft.breedId!,
            title: AnimalCatalogue.breedDisplayName(draft.breedId),
            subtitle: 'Custom breed',
          ),
      ],
    );
    if (selected == null || !context.mounted) return;
    final breed = AnimalCatalogue.breedById(selected);
    if (breed?.allowsCustomBreed == true &&
        !AnimalCatalogue.isCustomBreedId(selected)) {
      final customName = await requestCustomBreedName(
        context: context,
        species: species,
      );
      if (customName == null || !context.mounted) return;
      draft.breedId = AnimalCatalogue.customBreedId(
        speciesId: speciesId,
        name: customName,
      );
    } else {
      draft.breedId = selected;
    }
    onChanged();
  }
}

List<String> _jsonStringList(String value) {
  try {
    return (jsonDecode(value) as List).map((item) => '$item').toList();
  } catch (_) {
    return const [];
  }
}

class _FarmCard extends ConsumerWidget {
  const _FarmCard({required this.data});
  final FarmDashboardData data;
  Farm get farm => data.farm;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AveraSurfaceCard(
    child: InkWell(
      borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
      onTap: () => context.push('/farm-records/${farm.id}'),
      onLongPress: () => showFarmActions(context, ref, data),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.agriculture_rounded),
              ),
              title: Text(farm.name, style: averaText(context).listItemTitle),
              subtitle: Text(
                '${farm.location ?? 'Location not recorded'}\n${data.populationBySpecies.keys.map((id) => AnimalCatalogue.speciesById(id)?.displayName ?? id).join(' | ')}',
                style: averaText(context).listItemSubtitle,
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text(farm.status)),
            ),
            const Divider(),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Metric(
                  label: 'Total Animals',
                  value: '${data.currentPopulation}',
                ),
                _Metric(label: 'Units', value: '${data.activeUnits.length}'),
                _Metric(
                  label: 'Last Updated',
                  value: DateFormat.yMMMd().format(data.lastUpdated),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class FarmPopulationSummary extends StatelessWidget {
  const FarmPopulationSummary({
    super.key,
    required this.dashboards,
    required this.countLabel,
    required this.count,
  });
  final List<FarmDashboardData> dashboards;
  final String countLabel;
  final int count;

  @override
  Widget build(BuildContext context) {
    final species = <String, int>{};
    for (final data in dashboards) {
      for (final entry in data.populationBySpecies.entries) {
        species.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Metric(
                  label: 'Total Animals',
                  value:
                      '${species.values.fold<int>(0, (sum, value) => sum + value)}',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Metric(label: countLabel, value: '$count'),
              ),
            ],
          ),
          if (species.isNotEmpty) ...[
            const Divider(height: 28),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                for (final entry in species.entries)
                  Text(
                    '${AnimalCatalogue.speciesById(entry.key)?.displayName ?? 'Unassigned'}  ${entry.value}',
                    style: averaText(context).fieldValue,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> showFarmActions(
  BuildContext context,
  WidgetRef ref,
  FarmDashboardData data,
) async {
  final session = ref.read(userSessionProvider).valueOrNull;
  if (session == null) return;
  final colors = Theme.of(context).colorScheme;
  final archived = data.farm.status == 'Archived';
  final action = await showAveraActionSheet<String>(
    context: context,
    title: data.farm.name,
    description: data.farm.location,
    builder: (sheetContext) => Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.can(Permissions.farmsCreate))
              ListTile(
                leading: Icon(Icons.edit_outlined, color: colors.primary),
                title: const Text('Edit Farm Details'),
                subtitle: const Text('Update name, location and farm settings'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
            if (!archived && session.can(Permissions.farmUnitsManage))
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: colors.primary),
                title: const Text('Add Purchased Animals'),
                subtitle: const Text('Record animals added to this farm'),
                onTap: () => Navigator.pop(sheetContext, 'purchase'),
              ),
            if (!archived)
              const ListTile(
                enabled: false,
                leading: Icon(Icons.swap_vert, color: Colors.blue),
                title: Text('Transfer Animals'),
                subtitle: Text(
                  'Individual group transfers are not supported yet',
                ),
              ),
            if (!archived && session.can(Permissions.farmMortalityRecord))
              ListTile(
                leading: Icon(Icons.remove_circle_outline, color: colors.error),
                title: const Text('Record Mortality'),
                subtitle: const Text('Record deaths and update population'),
                onTap: () => Navigator.pop(sheetContext, 'mortality'),
              ),
            if (session.can(Permissions.farmsCreate))
              ListTile(
                leading: const Icon(
                  Icons.archive_outlined,
                  color: Colors.amber,
                ),
                title: Text(archived ? 'Reactivate Farm' : 'Archive Farm'),
                subtitle: const Text(
                  'Preserve all population, treatment and billing history',
                ),
                onTap: () => Navigator.pop(sheetContext, 'archive'),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'edit') {
    await context.push('/farm-records/${data.farm.id}/edit');
  } else if (action == 'purchase' || action == 'mortality') {
    final unit = await showAveraActionSheet<FarmUnit>(
      context: context,
      title: 'Select Farm Unit',
      builder: (sheetContext) => Flexible(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data.activeUnits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Add a farm unit first.'),
                ),
              for (final unit in data.activeUnits)
                ListTile(
                  title: Text(unit.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(sheetContext, unit),
                ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || unit == null) return;
    await showFarmPopulationMovement(
      context: context,
      farmId: data.farm.id,
      unit: unit,
      populations: data.populations
          .where((group) => group.farmUnitId == unit.id)
          .toList(),
      session: session,
      type: action == 'purchase'
          ? FarmPopulationMovementType.purchase
          : FarmPopulationMovementType.mortality,
    );
  } else if (action == 'archive') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(archived ? 'Reactivate Farm?' : 'Archive Farm?'),
        content: const Text('All existing records will be preserved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(archived ? 'Reactivate' : 'Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(clinicRepositoryProvider)
          .setFarmArchived(
            session: session,
            farmId: data.farm.id,
            archived: !archived,
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The farm status could not be updated. Please try again.',
            ),
          ),
        );
      }
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: averaText(context).sectionLabel),
      const SizedBox(height: 4),
      Text(value, style: averaText(context).fieldValue),
    ],
  );
}

class _RecordStatus extends StatelessWidget {
  const _RecordStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final success = status == 'Finalized';
    final color = success
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: averaText(
          context,
        ).caption.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _FarmMessage extends StatelessWidget {
  const _FarmMessage({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      children: [
        Icon(icon, size: 36),
        const SizedBox(height: 12),
        Text(title, style: averaText(context).listItemTitle),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: averaText(context).listItemSubtitle,
        ),
      ],
    ),
  );
}

class _FarmDenied extends StatelessWidget {
  const _FarmDenied();
  @override
  Widget build(BuildContext context) => const _FarmMessage(
    icon: Icons.lock_outline_rounded,
    title: 'Farm Records unavailable',
    message: 'You do not have permission to view farm records for this clinic.',
  );
}
