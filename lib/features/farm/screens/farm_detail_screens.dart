import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/animal_catalogue.dart';
import '../../../core/models/vaccine_catalogue.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/clinic_document_branding.dart';
import '../../shared/widgets/avera_ui.dart';
import '../services/farm_report_service.dart';

class FarmOverviewScreen extends ConsumerWidget {
  const FarmOverviewScreen({super.key, required this.farmId});
  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
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
      body: FutureBuilder<FarmDashboardData?>(
        future: ref.read(clinicRepositoryProvider).getFarmDashboard(farmId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
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
                  'Active units': '${data.units.length}',
                  'Last updated': DateFormat.yMMMd().add_jm().format(
                    data.farm.updatedAt,
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
            ],
          );
        },
      ),
    );
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
    final treatments = await repository.getFarmUnitTreatments(
      farmId: widget.farmId,
      unitId: widget.unitId,
    );
    return _FarmUnitTreatmentData(unit: unit, treatments: treatments);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Farm Unit Details'),
        actions: [
          if (session?.can(Permissions.farmUnitsManage) == true)
            IconButton(
              tooltip: 'Edit unit',
              onPressed: () async {
                final data = await _data;
                final unit = data?.unit;
                if (!context.mounted || unit == null) return;
                final changed = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) =>
                      _EditUnitSheet(farmId: widget.farmId, unit: unit),
                );
                if (changed == true && context.mounted) {
                  setState(_reload);
                }
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: FutureBuilder<_FarmUnitTreatmentData?>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const _DetailMessage(
              title: 'Unit unavailable',
              message: 'This unit is not available in the active clinic.',
            );
          }
          final unit = data.unit;
          final total = unit.maleCount + unit.femaleCount + unit.unknownCount;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              AveraPageHeader(
                title: unit.name,
                subtitle:
                    '${unit.unitType} • $total/${unit.capacity ?? total} • ${unit.status}',
              ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              _UnitSummaryCard(unit: unit),
              if (unit.notes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AveraSpacing.cardGap),
                AveraLabeledFieldCard(
                  label: 'Notes',
                  child: Text(
                    unit.notes!,
                    style: averaText(context).fieldValue,
                  ),
                ),
              ],
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(
                title: 'Unit Records',
                subtitle:
                    'Health, reproduction, transfers and individual animal records.',
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              if (session?.can(Permissions.farmHealthRecord) == true) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _recordTreatment(unit, session!),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Record Treatment'),
                  ),
                ),
                const SizedBox(height: AveraSpacing.cardGap),
              ],
              _TreatmentOverviewGrid(treatments: data.treatments),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Recent Treatments'),
              const SizedBox(height: AveraSpacing.cardGap),
              if (data.treatments.isEmpty)
                const _DetailMessage(
                  title: 'No treatments recorded',
                  message:
                      'Record a treatment to begin this unit health history.',
                )
              else
                for (final treatment in data.treatments) ...[
                  _TreatmentListTile(
                    treatment: treatment,
                    onTap: () => _showTreatmentDetails(treatment),
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _recordTreatment(FarmUnit unit, UserSession session) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RecordTreatmentSheet(
        farmId: widget.farmId,
        unit: unit,
        session: session,
      ),
    );
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _showTreatmentDetails(FarmHealthRecord treatment) =>
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(treatment.eventType, style: averaText(context).pageTitle),
              const SizedBox(height: 8),
              Text(
                treatment.product ?? 'Product not recorded',
                style: averaText(context).fieldValue,
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
      );
}

class _FarmUnitTreatmentData {
  const _FarmUnitTreatmentData({required this.unit, required this.treatments});
  final FarmUnit unit;
  final List<FarmHealthRecord> treatments;
}

class _UnitSummaryCard extends StatelessWidget {
  const _UnitSummaryCard({required this.unit});
  final FarmUnit unit;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _SummaryValue('SPECIES', _speciesName(unit.speciesId))),
        Expanded(child: _SummaryValue('BREED', _breedName(unit.breedId))),
        Expanded(
          child: _SummaryValue(
            'MALE / FEMALE',
            '${unit.maleCount} / ${unit.femaleCount}',
          ),
        ),
      ],
    ),
  );
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: averaText(context).sectionLabel),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: averaText(context).listItemTitle,
        ),
      ],
    ),
  );
}

class _TreatmentOverviewGrid extends StatelessWidget {
  const _TreatmentOverviewGrid({required this.treatments});
  final List<FarmHealthRecord> treatments;

  @override
  Widget build(BuildContext context) {
    const types = [
      ('Deworming', Icons.check_circle_outline_rounded),
      ('Pour-On (Ticks)', Icons.south_rounded),
      ('Antitrypanocide', Icons.medication_outlined),
      ('Vaccination', Icons.vaccines_outlined),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        for (final type in types)
          _TreatmentSummaryCard(
            title: type.$1,
            icon: type.$2,
            treatment: treatments
                .where((record) => record.eventType == type.$1)
                .firstOrNull,
          ),
      ],
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
    final color = overdue
        ? Theme.of(context).extension<AppSemanticColors>()!.warning
        : Theme.of(context).colorScheme.primary;
    return AveraSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            treatment == null
                ? 'Not recorded'
                : 'Last: ${DateFormat.MMMd().format(treatment!.occurredAt)}'
                      '${due == null ? '' : ' • Next: ${DateFormat.MMMd().format(due)}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: averaText(context).listItemSubtitle.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _TreatmentListTile extends StatelessWidget {
  const _TreatmentListTile({required this.treatment, required this.onTap});
  final FarmHealthRecord treatment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AveraAdministrationCard(
    icon: treatment.eventType == 'Vaccination'
        ? Icons.vaccines_outlined
        : Icons.medication_outlined,
    title: '${treatment.eventType} — ${treatment.product ?? 'Not recorded'}',
    subtitle:
        '${DateFormat.yMMMd().format(treatment.occurredAt)} • ${treatment.animalsCovered ?? 0} animals • ${treatment.administeredBy ?? 'Not recorded'}',
    onTap: onTap,
  );
}

class _RecordTreatmentSheet extends ConsumerStatefulWidget {
  const _RecordTreatmentSheet({
    required this.farmId,
    required this.unit,
    required this.session,
  });
  final String farmId;
  final FarmUnit unit;
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
  final _notes = TextEditingController();
  String _type = 'Deworming';
  VaccineProtocolDefinition? _protocol;
  DateTime _date = DateTime.now();
  DateTime? _nextDue;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final total =
        widget.unit.maleCount +
        widget.unit.femaleCount +
        widget.unit.unknownCount;
    _animals.text = '$total';
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
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final protocols = VaccineCatalogue.forSpecies(widget.unit.speciesId ?? '');
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
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Treatment type'),
                items:
                    const [
                          'Deworming',
                          'Pour-On (Ticks)',
                          'Antitrypanocide',
                          'Vaccination',
                          'Other',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() {
                  _type = value ?? _type;
                  _protocol = null;
                }),
              ),
              const SizedBox(height: 12),
              if (_type == 'Vaccination')
                DropdownButtonFormField<VaccineProtocolDefinition>(
                  value: _protocol,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: protocols.isEmpty
                        ? 'No compatible vaccine protocols'
                        : 'Vaccine',
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
                  validator: (_) => _type == 'Vaccination' && _protocol == null
                      ? 'Select a vaccine.'
                      : null,
                )
              else
                TextFormField(
                  controller: _product,
                  decoration: const InputDecoration(labelText: 'Product used'),
                  validator: (value) => value?.trim().isEmpty == true
                      ? 'Enter the product used.'
                      : null,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _animals,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Animals treated'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dose,
                decoration: const InputDecoration(labelText: 'Dose'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _route,
                decoration: const InputDecoration(labelText: 'Route'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _manufacturer,
                decoration: const InputDecoration(labelText: 'Manufacturer'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _batch,
                decoration: const InputDecoration(labelText: 'Batch number'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date administered'),
                subtitle: Text(DateFormat.yMMMd().format(_date)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Next due'),
                subtitle: Text(
                  _nextDue == null
                      ? 'Not scheduled'
                      : DateFormat.yMMMd().format(_nextDue!),
                ),
                trailing: const Icon(Icons.event_repeat_outlined),
                onTap: _pickNextDue,
              ),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
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
            manufacturer: _manufacturer.text,
            batchNumber: _batch.text,
            dose: _dose.text,
            route: _route.text,
            nextDueDate: _nextDue,
            notes: _notes.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
        setState(() => _saving = false);
      }
    }
  }
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
      appBar: AppBar(title: const Text('Daily Farm Record')),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to continue: $error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _EditUnitSheet extends ConsumerStatefulWidget {
  const _EditUnitSheet({required this.farmId, required this.unit});
  final String farmId;
  final FarmUnit unit;

  @override
  ConsumerState<_EditUnitSheet> createState() => _EditUnitSheetState();
}

class _EditUnitSheetState extends ConsumerState<_EditUnitSheet> {
  late final _name = TextEditingController(text: widget.unit.name);
  late final _capacity = TextEditingController(
    text: widget.unit.capacity?.toString() ?? '',
  );
  late final _male = TextEditingController(
    text: widget.unit.maleCount.toString(),
  );
  late final _female = TextEditingController(
    text: widget.unit.femaleCount.toString(),
  );
  late final _unknown = TextEditingController(
    text: widget.unit.unknownCount.toString(),
  );
  late final _notes = TextEditingController(text: widget.unit.notes ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _male.dispose();
    _female.dispose();
    _unknown.dispose();
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
          for (final field in [
            ('Unit name', _name),
            ('Capacity', _capacity),
            ('Male', _male),
            ('Female', _female),
            ('Unknown sex', _unknown),
          ]) ...[
            AveraLabeledFieldCard(
              label: field.$1,
              child: TextField(
                controller: field.$2,
                keyboardType: field.$1 == 'Unit name'
                    ? TextInputType.text
                    : TextInputType.number,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
            const SizedBox(height: AveraSpacing.cardGap),
          ],
          AveraLabeledFieldCard(
            label: 'Notes',
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
    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
      await ref
          .read(clinicRepositoryProvider)
          .updateFarmUnit(
            session: session,
            farmId: widget.farmId,
            unitId: widget.unit.id,
            name: _name.text,
            unitType: widget.unit.unitType,
            speciesId: widget.unit.speciesId,
            breedId: widget.unit.breedId,
            capacity: int.tryParse(_capacity.text),
            maleCount: int.tryParse(_male.text) ?? 0,
            femaleCount: int.tryParse(_female.text) ?? 0,
            unknownCount: int.tryParse(_unknown.text) ?? 0,
            notes: _notes.text,
          );
      if (mounted) Navigator.pop(context, true);
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
  if (id == null) return 'Not recorded';
  for (final item in AnimalCatalogue.breeds) {
    if (item.id == id) return item.displayName;
  }
  return id;
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
