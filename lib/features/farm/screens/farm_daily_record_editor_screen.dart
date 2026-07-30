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

class FarmDailyRecordEditorScreen extends ConsumerStatefulWidget {
  const FarmDailyRecordEditorScreen({
    super.key,
    required this.farmId,
    this.recordId,
    this.correctionMode = false,
  });

  final String farmId;
  final String? recordId;
  final bool correctionMode;

  @override
  ConsumerState<FarmDailyRecordEditorScreen> createState() =>
      _FarmDailyRecordEditorScreenState();
}

class _FarmDailyRecordEditorScreenState
    extends ConsumerState<FarmDailyRecordEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _feed = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _tasks = TextEditingController();
  final _correctionReason = TextEditingController();
  final _movements = <String, _MovementControllers>{};
  late Future<_DailyEditorData?> _loader;
  bool _saving = false;
  DateTime _recordDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  @override
  void dispose() {
    _feed.dispose();
    _note.dispose();
    _tasks.dispose();
    _correctionReason.dispose();
    for (final controllers in _movements.values) {
      controllers.dispose();
    }
    super.dispose();
  }

  Future<_DailyEditorData?> _load() async {
    final repository = ref.read(clinicRepositoryProvider);
    final dashboard = await repository.getFarmDashboard(widget.farmId);
    if (dashboard == null) return null;

    FarmDailyRecordDetail? detail;
    if (widget.recordId != null) {
      detail = await repository.getFarmDailyRecordDetail(
        farmId: widget.farmId,
        recordId: widget.recordId!,
      );
      if (detail == null) return null;
      _recordDate = detail.record.recordDate;
      _feed.text = detail.record.feedSuppliedKg.toString();
      _note.text = detail.record.dailyNote ?? '';
      _tasks.text = detail.record.tasksForTomorrow ?? '';
    }

    var previousClosingBySpecies = <String, int>{};
    if (detail == null) {
      final previousRecords =
          dashboard.dailyRecords
              .where((record) => record.recordDate.isBefore(_recordDate))
              .toList()
            ..sort((a, b) => b.recordDate.compareTo(a.recordDate));
      if (previousRecords.isNotEmpty) {
        final previousMovements = await repository
            .getFarmSpeciesMovementsForRecord(previousRecords.first.id);
        previousClosingBySpecies = {
          for (final movement in previousMovements)
            movement.speciesId: movement.closingPopulation,
        };
      }
    }

    final speciesIds = _decodeIds(dashboard.farm.speciesJson);
    for (final unit in dashboard.units) {
      if (unit.speciesId != null) speciesIds.add(unit.speciesId!);
    }
    for (final movement
        in detail?.speciesMovements ??
            const <FarmSpeciesPopulationMovement>[]) {
      speciesIds.add(movement.speciesId);
    }

    if (speciesIds.isEmpty) speciesIds.add('unassigned');
    final populations = dashboard.populationBySpecies;
    for (final speciesId in speciesIds) {
      final matching = detail?.speciesMovements.where(
        (item) => item.speciesId == speciesId,
      );
      final existing = matching == null || matching.isEmpty
          ? null
          : matching.first;
      _movements[speciesId] = _MovementControllers(
        opening:
            existing?.openingPopulation ??
            previousClosingBySpecies[speciesId] ??
            populations[speciesId] ??
            0,
        births: existing?.births ?? 0,
        purchases: existing?.purchases ?? 0,
        transfersIn: existing?.transfersIn ?? 0,
        mortality: existing?.mortality ?? 0,
        sales: existing?.sales ?? 0,
        transfersOut: existing?.transfersOut ?? 0,
      );
    }

    if (detail != null &&
        detail.speciesMovements.isEmpty &&
        _movements.isNotEmpty) {
      final legacy = _movements.values.first;
      legacy
        ..opening.text = '${detail.record.openingPopulation}'
        ..births.text = '${detail.record.births}'
        ..purchases.text = '${detail.record.purchases}'
        ..transfersIn.text = '${detail.record.transfersIn}'
        ..mortality.text = '${detail.record.mortality}'
        ..sales.text = '${detail.record.sales}'
        ..transfersOut.text = '${detail.record.transfersOut}';
    }

    return _DailyEditorData(dashboard: dashboard, detail: detail);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.correctionMode
              ? 'Correct Daily Record'
              : widget.recordId == null
              ? 'New Daily Record'
              : 'Edit Daily Record',
        ),
      ),
      body: FutureBuilder<_DailyEditorData?>(
        future: _loader,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(
              child: Text('This farm record is unavailable.'),
            );
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.pageTopPadding,
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.bottomContentClearance,
              ),
              children: [
                AveraPageHeader(
                  title: data.dashboard.farm.name,
                  subtitle:
                      '${DateFormat.yMMMMd().format(_recordDate)} | Population reconciles independently by species.',
                ),
                const SizedBox(height: AveraSpacing.subtitleToContentGap),
                for (final entry in _orderedMovements) ...[
                  _SpeciesMovementEditor(
                    speciesId: entry.key,
                    controllers: entry.value,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                ],
                AveraLabeledFieldCard(
                  label: 'Feed Supplied (kg)',
                  child: TextFormField(
                    controller: _feed,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _nonNegativeDecimal,
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
                const SizedBox(height: AveraSpacing.cardGap),
                AveraLabeledFieldCard(
                  label: 'Daily Notes',
                  child: TextFormField(
                    controller: _note,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Health, feed, production and management notes',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: AveraSpacing.cardGap),
                AveraLabeledFieldCard(
                  label: 'Tasks for Tomorrow',
                  child: TextFormField(
                    controller: _tasks,
                    maxLines: 3,
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
                if (widget.correctionMode) ...[
                  const SizedBox(height: AveraSpacing.cardGap),
                  AveraLabeledFieldCard(
                    label: 'Correction Reason',
                    child: TextFormField(
                      controller: _correctionReason,
                      maxLines: 3,
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Explain why this finalized record is being corrected.'
                          : null,
                      decoration: const InputDecoration(
                        hintText: 'Required for the audit history',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AveraSpacing.sectionGap),
                if (widget.correctionMode)
                  AveraPrimaryActionButton(
                    label: 'Save Correction',
                    icon: Icons.fact_check_outlined,
                    loading: _saving,
                    onPressed: _saving ? null : () => _save(finalize: true),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(finalize: false),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Draft'),
                  ),
                  if (session?.can(Permissions.farmDailyFinalize) == true) ...[
                    const SizedBox(height: 12),
                    AveraPrimaryActionButton(
                      label: 'Finalize Daily Record',
                      icon: Icons.task_alt_rounded,
                      loading: _saving,
                      onPressed: _saving ? null : () => _save(finalize: true),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  List<MapEntry<String, _MovementControllers>> get _orderedMovements =>
      _movements.entries.toList()..sort((left, right) {
        final leftName =
            AnimalCatalogue.speciesById(left.key)?.displayName ?? left.key;
        final rightName =
            AnimalCatalogue.speciesById(right.key)?.displayName ?? right.key;
        return leftName.compareTo(rightName);
      });

  Future<void> _save({required bool finalize}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final inputs = [
      for (final entry in _orderedMovements)
        FarmSpeciesMovementInput(
          speciesId: entry.key,
          openingPopulation: entry.value.valueOf(entry.value.opening),
          births: entry.value.valueOf(entry.value.births),
          purchases: entry.value.valueOf(entry.value.purchases),
          transfersIn: entry.value.valueOf(entry.value.transfersIn),
          mortality: entry.value.valueOf(entry.value.mortality),
          sales: entry.value.valueOf(entry.value.sales),
          transfersOut: entry.value.valueOf(entry.value.transfersOut),
        ),
    ];
    if (inputs.any((item) => item.closingPopulation < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A species closing population cannot be negative. Review its movements.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
      final record = await ref
          .read(clinicRepositoryProvider)
          .saveFarmDailyRecord(
            session: session,
            farmId: widget.farmId,
            recordDate: _recordDate,
            openingPopulation: inputs.fold(
              0,
              (sum, item) => sum + item.openingPopulation,
            ),
            births: inputs.fold(0, (sum, item) => sum + item.births),
            purchases: inputs.fold(0, (sum, item) => sum + item.purchases),
            transfersIn: inputs.fold(0, (sum, item) => sum + item.transfersIn),
            mortality: inputs.fold(0, (sum, item) => sum + item.mortality),
            sales: inputs.fold(0, (sum, item) => sum + item.sales),
            transfersOut: inputs.fold(
              0,
              (sum, item) => sum + item.transfersOut,
            ),
            feedSuppliedKg: double.tryParse(_feed.text) ?? 0,
            dailyNote: _note.text,
            tasksForTomorrow: _tasks.text,
            speciesMovements: inputs,
            correctionReason: _correctionReason.text,
            finalize: finalize,
          );
      if (!mounted) return;
      if (finalize || widget.correctionMode) {
        context.go('/farm-records/${widget.farmId}/daily/${record.id}');
      } else {
        Navigator.pop(context, true);
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

class _SpeciesMovementEditor extends StatelessWidget {
  const _SpeciesMovementEditor({
    required this.speciesId,
    required this.controllers,
    required this.onChanged,
  });

  final String speciesId;
  final _MovementControllers controllers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final name =
        AnimalCatalogue.speciesById(speciesId)?.displayName ??
        'Unassigned Species';
    final fields = <(String, TextEditingController)>[
      ('Opening Population', controllers.opening),
      ('Births', controllers.births),
      ('Purchases', controllers.purchases),
      ('Transfers In', controllers.transfersIn),
      ('Deaths', controllers.mortality),
      ('Sales', controllers.sales),
      ('Transfers Out', controllers.transfersOut),
    ];
    return AveraSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: averaText(context).sectionTitle),
          const SizedBox(height: 6),
          Text(
            'Closing population: ${controllers.closing}',
            style: averaText(context).sectionSubtitle,
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          for (final field in fields) ...[
            Text(field.$1, style: averaText(context).sectionLabel),
            const SizedBox(height: 6),
            TextFormField(
              controller: field.$2,
              keyboardType: TextInputType.number,
              onChanged: (_) => onChanged(),
              validator: _nonNegativeWholeNumber,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (field != fields.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MovementControllers {
  _MovementControllers({
    required int opening,
    required int births,
    required int purchases,
    required int transfersIn,
    required int mortality,
    required int sales,
    required int transfersOut,
  }) : opening = TextEditingController(text: '$opening'),
       births = TextEditingController(text: '$births'),
       purchases = TextEditingController(text: '$purchases'),
       transfersIn = TextEditingController(text: '$transfersIn'),
       mortality = TextEditingController(text: '$mortality'),
       sales = TextEditingController(text: '$sales'),
       transfersOut = TextEditingController(text: '$transfersOut');

  final TextEditingController opening;
  final TextEditingController births;
  final TextEditingController purchases;
  final TextEditingController transfersIn;
  final TextEditingController mortality;
  final TextEditingController sales;
  final TextEditingController transfersOut;

  int valueOf(TextEditingController controller) =>
      int.tryParse(controller.text) ?? 0;

  int get closing =>
      valueOf(opening) +
      valueOf(births) +
      valueOf(purchases) +
      valueOf(transfersIn) -
      valueOf(mortality) -
      valueOf(sales) -
      valueOf(transfersOut);

  void dispose() {
    opening.dispose();
    births.dispose();
    purchases.dispose();
    transfersIn.dispose();
    mortality.dispose();
    sales.dispose();
    transfersOut.dispose();
  }
}

class _DailyEditorData {
  const _DailyEditorData({required this.dashboard, required this.detail});
  final FarmDashboardData dashboard;
  final FarmDailyRecordDetail? detail;
}

Set<String> _decodeIds(String value) {
  try {
    return (jsonDecode(value) as List).map((item) => '$item').toSet();
  } catch (_) {
    return {};
  }
}

String? _nonNegativeWholeNumber(String? value) {
  final parsed = int.tryParse(value ?? '');
  return parsed == null || parsed < 0 ? 'Enter zero or a whole number.' : null;
}

String? _nonNegativeDecimal(String? value) {
  final parsed = double.tryParse(value ?? '');
  return parsed == null || parsed < 0
      ? 'Enter zero or a positive value.'
      : null;
}
