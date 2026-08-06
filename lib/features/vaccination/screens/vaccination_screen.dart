import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/backend_configuration.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/animal_catalogue.dart';
import '../../../core/models/animal_search_result.dart';
import '../../../core/models/vaccine_catalogue.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/security/access_control.dart';
import '../../../core/services/animal_age_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/remote_patient_selector.dart';

enum RecordVaccinationMode { general, scheduledDose }

class RecordVaccinationArgs {
  const RecordVaccinationArgs.general()
    : patientId = null,
      vaccinationScheduleId = null,
      vaccineProtocolId = null,
      mode = RecordVaccinationMode.general;

  const RecordVaccinationArgs.scheduledDose({
    required this.patientId,
    required this.vaccinationScheduleId,
    required this.vaccineProtocolId,
  }) : mode = RecordVaccinationMode.scheduledDose;

  final int? patientId;
  final int? vaccinationScheduleId;
  final String? vaccineProtocolId;
  final RecordVaccinationMode mode;

  bool get locksPatientAndVaccine =>
      mode == RecordVaccinationMode.scheduledDose;
}

class VaccineScheduleScreen extends ConsumerStatefulWidget {
  const VaccineScheduleScreen({super.key, this.initialFilter});

  final VaccineScheduleFilter? initialFilter;

  @override
  ConsumerState<VaccineScheduleScreen> createState() =>
      _VaccineScheduleScreenState();
}

class _VaccineScheduleScreenState extends ConsumerState<VaccineScheduleScreen> {
  VaccineScheduleFilter _filter = VaccineScheduleFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? VaccineScheduleFilter.all;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.can(Permissions.vaccinationsView)) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have access to the vaccine schedule.'),
        ),
      );
    }
    final repository = ref.watch(clinicRepositoryProvider);
    return Scaffold(
      floatingActionButton: session.can(Permissions.vaccinationsAdd)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RecordVaccinationScreen(),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Record Vaccination'),
            )
          : null,
      body: SafeArea(
        child: StreamBuilder<List<ClinicVaccinationRecord>>(
          stream: repository.watchClinicVaccinations(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final today = DateTime.now();
            final records = snapshot.data!
                .where((record) {
                  final matchesFilter = _matchesFilter(
                    record.vaccination,
                    _filter,
                    today,
                  );
                  final search =
                      '${record.animal.animalName} ${record.animal.hospitalNumber} ${record.owner.fullName} ${record.owner.phone} ${record.vaccination.vaccine}'
                          .toLowerCase();
                  return matchesFilter &&
                      search.contains(_query.trim().toLowerCase());
                })
                .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                AveraSpacing.bottomContentClearance,
              ),
              children: [
                const AveraPageHeader(
                  title: 'Vaccine Schedule',
                  subtitle: 'Track due, upcoming and completed vaccinations.',
                ),
                const SizedBox(height: 24),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search patients or vaccines',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      for (final filter in VaccineScheduleFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_filterLabel(filter)),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (records.isEmpty)
                  _ScheduleEmpty(
                    filter: _filter,
                    hasSearch: _query.trim().isNotEmpty,
                  )
                else
                  for (final record in records) ...[
                    _VaccineScheduleCard(record: record, today: today),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class VaccinationDetailScreen extends ConsumerWidget {
  const VaccinationDetailScreen({super.key, required this.vaccinationId});

  final int vaccinationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null || !session.can(Permissions.vaccinationsView)) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have access to this vaccination.'),
        ),
      );
    }
    final record = ref
        .watch(clinicRepositoryProvider)
        .getClinicVaccinationRecord(vaccinationId);
    return Scaffold(
      appBar: AppBar(title: const Text('Vaccination')),
      body: FutureBuilder<ClinicVaccinationRecord?>(
        future: record,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final item = snapshot.data;
          if (item == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.vaccines_outlined, size: 36),
                    const SizedBox(height: 12),
                    const Text(
                      'This vaccination schedule entry is no longer available.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Return to Notifications'),
                    ),
                  ],
                ),
              ),
            );
          }
          final vaccination = item.vaccination;
          final date = DateFormat.yMMMd();
          final protocol = VaccineCatalogue.protocols
              .where((candidate) => candidate.name == vaccination.vaccine)
              .firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              AveraPageHeader(
                title: vaccination.vaccine,
                subtitle:
                    '${item.animal.animalName} - ${item.animal.hospitalNumber}',
              ),
              const SizedBox(height: 24),
              AveraLabeledFieldCard(
                label: 'Patient',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.animal.animalName,
                      style: averaText(context).fieldValue,
                    ),
                    Text(
                      '${item.animal.species}${item.animal.breed == null ? '' : ' - ${item.animal.breed}'}',
                      style: averaText(context).caption,
                    ),
                    if (item.animal.dateOfBirth != null)
                      Text(
                        'Age at vaccination: '
                        '${AnimalAgeService.displayAge(birthDate: item.animal.dateOfBirth!, referenceDate: vaccination.dateGiven, estimated: item.animal.isDateOfBirthEstimated)}',
                        style: averaText(context).caption,
                      ),
                    Text(
                      'Owner: ${item.owner.fullName}',
                      style: averaText(context).caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AveraLabeledFieldCard(
                label: 'Schedule',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last given: ${date.format(vaccination.dateGiven)}',
                      style: averaText(context).fieldValue,
                    ),
                    Text(
                      vaccination.nextDueDate == null
                          ? 'No follow-up date recorded'
                          : 'Due: ${date.format(vaccination.nextDueDate!)}',
                      style: averaText(context).listItemSubtitle,
                    ),
                    Text(
                      'Status: ${_statusFor(vaccination, DateTime.now())}',
                      style: averaText(context).caption,
                    ),
                  ],
                ),
              ),
              if (protocol != null) ...[
                const SizedBox(height: 16),
                AveraLabeledFieldCard(
                  label: 'Protocol Guidance',
                  child: Text(
                    protocol.education,
                    style: averaText(context).listItemSubtitle,
                  ),
                ),
              ],
              if ((vaccination.batchNumber ?? '').isNotEmpty ||
                  (vaccination.manufacturer ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                AveraLabeledFieldCard(
                  label: 'Administration',
                  child: Text(
                    'Batch: ${vaccination.batchNumber ?? 'Not recorded'}\nManufacturer: ${vaccination.manufacturer ?? 'Not recorded'}',
                    style: averaText(context).listItemSubtitle,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _openVaccinationPatientFile(
                  context,
                  ref,
                  item.animal.id,
                  item.animal.hospitalNumber,
                ),
                icon: const Icon(Icons.pets_outlined),
                label: const Text('Open Patient File'),
              ),
              if (session.can(Permissions.vaccinationsAdd)) ...[
                const SizedBox(height: 12),
                FutureBuilder<ClinicVaccinationRecord?>(
                  future: ref
                      .read(clinicRepositoryProvider)
                      .getRecordedDoseForSchedule(vaccination.id),
                  builder: (context, doseSnapshot) {
                    final recordedDose = doseSnapshot.data;
                    return FilledButton.icon(
                      onPressed: () {
                        if (recordedDose != null) {
                          context.push(
                            '/vaccinations/${recordedDose.vaccination.id}',
                          );
                          return;
                        }
                        if (protocol == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'This vaccination protocol is unavailable.',
                              ),
                            ),
                          );
                          return;
                        }
                        context.push(
                          '/vaccinations/record?patientId=${item.animal.id}&scheduleId=${vaccination.id}&protocolId=${Uri.encodeQueryComponent(protocol.id)}',
                        );
                      },
                      icon: Icon(
                        recordedDose == null
                            ? Icons.vaccines_rounded
                            : Icons.visibility_outlined,
                      ),
                      label: Text(
                        recordedDose == null
                            ? 'Record Dose'
                            : 'View Vaccination Record',
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class RecordVaccinationScreen extends ConsumerStatefulWidget {
  const RecordVaccinationScreen({
    super.key,
    this.args = const RecordVaccinationArgs.general(),
  });

  final RecordVaccinationArgs args;

  @override
  ConsumerState<RecordVaccinationScreen> createState() =>
      _RecordVaccinationScreenState();
}

class _RecordVaccinationScreenState
    extends ConsumerState<RecordVaccinationScreen> {
  AnimalProfile? _patient;
  RemotePatient? _remotePatient;
  late final String _submissionId = const Uuid().v4();
  VaccineProtocolDefinition? _protocol;
  late DateTime _dateGiven;
  DateTime? _dueDate;
  VaccineRoute? _route;
  final _batch = TextEditingController();
  final _manufacturer = TextEditingController();
  final _dose = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  bool _initializing = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    _dateGiven = DateTime.now();
    if (widget.args.locksPatientAndVaccine) {
      _initializeScheduledDose();
    }
  }

  @override
  void dispose() {
    _batch.dispose();
    _manufacturer.dispose();
    _dose.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _useProtocol(VaccineProtocolDefinition protocol) {
    setState(() {
      _protocol = protocol;
      _route = protocol.defaultRoute;
      _dueDate = protocol.suggestedDueDate(_dateGiven);
    });
  }

  Future<void> _initializeScheduledDose() async {
    setState(() => _initializing = true);
    try {
      final patientId = widget.args.patientId;
      final scheduleId = widget.args.vaccinationScheduleId;
      final protocolId = widget.args.vaccineProtocolId;
      if (patientId == null || scheduleId == null || protocolId == null) {
        throw StateError('Scheduled vaccination context is incomplete.');
      }
      final repository = ref.read(clinicRepositoryProvider);
      final schedule = await repository.getClinicVaccinationRecord(scheduleId);
      final profile = await repository.getAnimalProfile(patientId);
      final protocol = VaccineCatalogue.byId(protocolId);
      if (!mounted) return;
      if (schedule == null || schedule.animal.id != patientId) {
        throw StateError('This scheduled vaccination is no longer available.');
      }
      final species = AnimalCatalogue.speciesForDisplayName(
        profile.animal.species,
      );
      if (protocol == null ||
          species == null ||
          protocol.speciesId != species.id ||
          schedule.vaccination.vaccine != protocol.name) {
        throw StateError(
          'This vaccine protocol is not compatible with the patient.',
        );
      }
      final existing = await repository.getRecordedDoseForSchedule(scheduleId);
      if (!mounted) return;
      if (existing != null) {
        throw StateError(
          'This scheduled vaccination has already been recorded.',
        );
      }
      setState(() {
        _patient = profile;
        _protocol = protocol;
        _route = protocol.defaultRoute;
        _dueDate =
            schedule.vaccination.nextDueDate ??
            protocol.suggestedDueDate(_dateGiven);
      });
    } catch (error) {
      if (mounted) setState(() => _initializationError = '$error');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_initializationError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Vaccination')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 40),
                const SizedBox(height: 12),
                Text(_initializationError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Return to Vaccination'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final patientSpecies = _remotePatient?.species ?? _patient?.animal.species;
    final species = AnimalCatalogue.speciesForDisplayName(patientSpecies);
    return Scaffold(
      appBar: AppBar(title: const Text('Record Vaccination')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          Text(
            'Record a compatible vaccine dose for this patient.',
            style: averaText(context).pageSubtitle,
          ),
          const SizedBox(height: 24),
          AveraLabeledFieldCard(
            label: 'Patient',
            child: InkWell(
              onTap: widget.args.locksPatientAndVaccine ? null : _selectPatient,
              child: _patient == null && _remotePatient == null
                  ? Row(
                      children: [
                        const Icon(Icons.search_rounded),
                        const SizedBox(width: 12),
                        Text(
                          'Select Patient',
                          style: averaText(context).fieldPlaceholder,
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    )
                  : _remotePatient != null
                  ? _RemotePatientSummary(patient: _remotePatient!)
                  : _PatientSummary(
                      profile: _patient!,
                      readOnly: widget.args.locksPatientAndVaccine,
                    ),
            ),
          ),
          if ((_patient != null || _remotePatient != null) &&
              species == null) ...[
            const SizedBox(height: 12),
            const _LegacySpeciesWarning(),
          ],
          const SizedBox(height: 16),
          AveraLabeledFieldCard(
            label: 'Vaccine Type',
            child: InkWell(
              onTap: widget.args.locksPatientAndVaccine || species == null
                  ? null
                  : _selectProtocol,
              child: Row(
                children: [
                  const Icon(Icons.vaccines_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _protocol?.name ??
                          (species == null
                              ? 'Select a patient first'
                              : 'Select Vaccine'),
                      style: _protocol == null
                          ? averaText(context).fieldPlaceholder
                          : averaText(context).fieldValue,
                    ),
                  ),
                  Icon(
                    widget.args.locksPatientAndVaccine
                        ? Icons.lock_outline_rounded
                        : Icons.expand_more_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (_protocol != null) ...[
            const SizedBox(height: 16),
            AveraLabeledFieldCard(
              label: 'Protocol Guidance',
              child: Text(
                _protocol!.education,
                style: averaText(context).listItemSubtitle,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _DateCard(
            label: 'Date Given',
            value: _dateGiven,
            onTap: _selectDateGiven,
          ),
          const SizedBox(height: 16),
          _DateCard(
            label: 'Suggested Due Date',
            value: _dueDate,
            onTap: _selectDueDate,
            placeholder: 'Select a vaccine first',
          ),
          const SizedBox(height: 16),
          AveraLabeledFieldCard(
            label: 'Route',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<VaccineRoute>(
                isExpanded: true,
                value: _route,
                hint: Text(
                  'Select vaccine first',
                  style: averaText(context).fieldPlaceholder,
                ),
                items: [
                  for (final route
                      in _protocol?.routes ?? const <VaccineRoute>[])
                    DropdownMenuItem(value: route, child: Text(route.label)),
                ],
                onChanged: _protocol == null
                    ? null
                    : (value) => setState(() => _route = value),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _TextFieldCard(
            label: 'Batch Number',
            controller: _batch,
            hint: 'Enter batch number',
          ),
          const SizedBox(height: 16),
          _TextFieldCard(
            label: 'Manufacturer',
            controller: _manufacturer,
            hint: 'Enter manufacturer',
          ),
          const SizedBox(height: 16),
          _TextFieldCard(
            label: 'Dose',
            controller: _dose,
            hint: 'Enter dose administered',
          ),
          const SizedBox(height: 16),
          AveraLabeledFieldCard(
            label: 'Administered By',
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    session.user.fullName,
                    style: averaText(context).fieldValue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _TextFieldCard(
            label: 'Notes',
            controller: _notes,
            hint: 'Optional notes',
            maxLines: 4,
          ),
          const SizedBox(height: 24),
          AveraPrimaryActionButton(
            label: 'Record Vaccination',
            icon: Icons.vaccines_rounded,
            loading: _saving,
            onPressed: _saving ? null : () => _save(session),
          ),
        ],
      ),
    );
  }

  Future<void> _selectPatient() async {
    if (BackendConfiguration.isConfigured) {
      final selected = await showModalBottomSheet<RemotePatient>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.86,
          child: RemotePatientSelectorSheet(selectedId: _remotePatient?.id),
        ),
      );
      if (selected == null || !mounted) return;
      setState(() {
        _remotePatient = selected;
        _patient = null;
        _protocol = null;
        _route = null;
        _dueDate = null;
      });
      return;
    }
    final selected = await showModalBottomSheet<AnimalSearchResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _VaccinationPatientPicker(),
    );
    if (selected == null || !mounted) return;
    final profile = await ref
        .read(clinicRepositoryProvider)
        .getAnimalProfile(selected.animalId);
    if (!mounted) return;
    setState(() {
      _patient = profile;
      _protocol = null;
      _route = null;
      _dueDate = null;
    });
  }

  Future<void> _selectProtocol() async {
    final species = AnimalCatalogue.speciesForDisplayName(
      _remotePatient?.species ?? _patient?.animal.species,
    );
    if (species == null) return;
    final selected = await showModalBottomSheet<VaccineProtocolDefinition>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _VaccineProtocolPicker(species: species),
    );
    if (selected != null && mounted) _useProtocol(selected);
  }

  Future<void> _selectDateGiven() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _dateGiven,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (value == null) return;
    setState(() {
      _dateGiven = value;
      if (_protocol != null) _dueDate = _protocol!.suggestedDueDate(value);
    });
  }

  Future<void> _selectDueDate() async {
    final initial = _dueDate ?? _dateGiven;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _dateGiven,
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _dueDate = value);
  }

  Future<void> _save(UserSession session) async {
    if ((_patient == null && _remotePatient == null) ||
        _protocol == null ||
        _route == null ||
        _dueDate == null) {
      _message('Select a patient and a compatible vaccine first.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (BackendConfiguration.isConfigured) {
        await ref.read(clinicalRemoteDataSourceProvider).createVaccination({
          'submissionId': _submissionId,
          'patientId': _remotePatient!.id,
          'vaccineName': _protocol!.name,
          'administeredAt': _dateGiven.toUtc().toIso8601String(),
          'nextDueAt': _dueDate!.toUtc().toIso8601String(),
          'route': _route!.label,
          'batchNumber': _batch.text.trim(),
          'manufacturer': _manufacturer.text.trim(),
          'dose': _dose.text.trim(),
          'notes': _notes.text.trim(),
        });
        ref
          ..invalidate(remotePatientMedicalFileProvider(_remotePatient!.id))
          ..invalidate(remoteDashboardProvider);
        if (!mounted) return;
        _message('Vaccination recorded successfully.');
        Navigator.pop(context);
        return;
      }
      await ref
          .read(clinicRepositoryProvider)
          .recordVaccination(
            session: session,
            animalId: _patient!.animal.id,
            protocolId: _protocol!.id,
            dateGiven: _dateGiven,
            nextDueDate: _dueDate!,
            route: _route!,
            batchNumber: _batch.text,
            manufacturer: _manufacturer.text,
            dose: _dose.text,
            notes: _notes.text,
            scheduledVaccinationId: widget.args.vaccinationScheduleId,
          );
      if (!mounted) return;
      _message('Vaccination recorded successfully.');
      Navigator.pop(context);
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _VaccinationPatientPicker extends ConsumerStatefulWidget {
  const _VaccinationPatientPicker();
  @override
  ConsumerState<_VaccinationPatientPicker> createState() =>
      _VaccinationPatientPickerState();
}

class _VaccinationPatientPickerState
    extends ConsumerState<_VaccinationPatientPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(clinicRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        children: [
          Text('Select Patient', style: averaText(context).sectionTitle),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search patient, hospital number or owner',
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<AnimalSearchResult>>(
              stream: repository.watchAnimalSearch(
                _query,
                status: AnimalStatuses.active,
              ),
              builder: (context, snapshot) {
                final patients = snapshot.data ?? const <AnimalSearchResult>[];
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (patients.isEmpty) {
                  return const Center(
                    child: Text('No active patients match this search.'),
                  );
                }
                return ListView.separated(
                  itemCount: patients.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final patient = patients[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          patient.animalName.substring(0, 1).toUpperCase(),
                        ),
                      ),
                      title: Text(
                        patient.animalName,
                        style: averaText(context).listItemTitle,
                      ),
                      subtitle: Text(
                        '${patient.hospitalNumber} • ${patient.species}${patient.breed == null ? '' : ' • ${patient.breed}'}\nOwner: ${patient.ownerName}',
                        style: averaText(context).listItemSubtitle,
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, patient),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VaccineProtocolPicker extends StatefulWidget {
  const _VaccineProtocolPicker({required this.species});
  final AnimalSpeciesOption species;
  @override
  State<_VaccineProtocolPicker> createState() => _VaccineProtocolPickerState();
}

class _VaccineProtocolPickerState extends State<_VaccineProtocolPicker> {
  String _query = '';
  String? _expanded;
  @override
  Widget build(BuildContext context) {
    final protocols = VaccineCatalogue.forSpecies(widget.species.id)
        .where(
          (protocol) =>
              '${protocol.name} ${protocol.subtitle ?? ''} ${protocol.aliases.join(' ')}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        children: [
          Text('Vaccine Type', style: averaText(context).sectionTitle),
          const SizedBox(height: 2),
          Text(
            widget.species.displayName,
            style: averaText(context).sectionSubtitle,
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search vaccines',
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: protocols.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final protocol = protocols[index];
                final expanded = _expanded == protocol.id;
                return AveraSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.vaccines_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          protocol.name,
                          style: averaText(context).listItemTitle,
                        ),
                        subtitle: Text(
                          '${protocol.subtitle ?? 'Protocol guidance'} • ${protocol.defaultRoute.label}',
                          style: averaText(context).listItemSubtitle,
                        ),
                        trailing: Icon(
                          expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        onTap: () => setState(
                          () => _expanded = expanded ? null : protocol.id,
                        ),
                      ),
                      if (expanded)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiaryContainer
                                .withValues(alpha: .5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ABOUT THIS VACCINE',
                                style: averaText(context).sectionLabel,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                protocol.education,
                                style: averaText(context).listItemSubtitle,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Suggested follow-up: ${protocol.intervalDays} days',
                                style: averaText(context).caption,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(context, protocol),
                                child: const Text('Use This Vaccine'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openVaccinationPatientFile(
  BuildContext context,
  WidgetRef ref,
  int localAnimalId,
  String hospitalNumber,
) async {
  if (!BackendConfiguration.isConfigured) {
    context.push('/animals/$localAnimalId');
    return;
  }

  try {
    final page = await ref
        .read(clinicalRemoteDataSourceProvider)
        .patients(search: hospitalNumber, pageSize: 25);
    String? patientId;
    for (final patient in page.items) {
      if (patient.hospitalNumber == hospitalNumber) {
        patientId = patient.id;
        break;
      }
    }
    if (!context.mounted) return;
    if (patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This patient has not synchronized yet. Please try again shortly.',
          ),
        ),
      );
      return;
    }
    context.push('/animals/${Uri.encodeComponent(patientId)}');
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Unable to open this patient medical file. Please retry.',
        ),
      ),
    );
  }
}

class _VaccineScheduleCard extends StatelessWidget {
  const _VaccineScheduleCard({required this.record, required this.today});
  final ClinicVaccinationRecord record;
  final DateTime today;
  @override
  Widget build(BuildContext context) {
    final status = _statusFor(record.vaccination, today);
    final species = VaccineCatalogue.speciesForLegacyPatient(
      record.animal.species,
    );
    final compatible =
        species != null &&
        VaccineCatalogue.isCompatible(
          speciesId: species.id,
          vaccineName: record.vaccination.vaccine,
        );
    final format = DateFormat.yMMMd();
    return AveraSurfaceCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
        onTap: () => context.push('/vaccinations/${record.vaccination.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    record.animal.animalName.substring(0, 1).toUpperCase(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.animal.animalName,
                        style: averaText(context).listItemTitle,
                      ),
                      Text(
                        '${record.animal.hospitalNumber} • ${record.animal.species}${record.animal.breed == null ? '' : ' • ${record.animal.breed}'}',
                        style: averaText(context).listItemSubtitle,
                      ),
                    ],
                  ),
                ),
                _StatusPill(status: status),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              record.vaccination.vaccine,
              style: averaText(context).fieldValue,
            ),
            Text(
              'Owner: ${record.owner.fullName} • ${record.owner.phone}',
              style: averaText(context).listItemSubtitle,
            ),
            const SizedBox(height: 8),
            Text(
              'Last given: ${format.format(record.vaccination.dateGiven)}',
              style: averaText(context).caption,
            ),
            Text(
              record.vaccination.nextDueDate == null
                  ? 'No due date recorded'
                  : 'Due: ${format.format(record.vaccination.nextDueDate!)}',
              style: averaText(context).caption,
            ),
            if ((record.vaccination.batchNumber ?? '').isNotEmpty)
              Text(
                'Batch: ${record.vaccination.batchNumber} • ${record.vaccination.manufacturer ?? 'Manufacturer not recorded'}',
                style: averaText(context).caption,
              ),
            if (!compatible) ...[
              const SizedBox(height: 10),
              const _CompatibilityWarning(),
            ],
          ],
        ),
      ),
    );
  }
}

class _PatientSummary extends StatelessWidget {
  const _PatientSummary({required this.profile, this.readOnly = false});
  final AnimalProfile profile;
  final bool readOnly;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        child: Text(profile.animal.animalName.substring(0, 1).toUpperCase()),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.animal.animalName,
              style: averaText(context).fieldValue,
            ),
            Text(
              '${profile.animal.hospitalNumber} • ${profile.animal.species}${profile.animal.breed == null ? '' : ' • ${profile.animal.breed}'}',
              style: averaText(context).caption,
            ),
            Text(
              'Owner: ${profile.owner.fullName}',
              style: averaText(context).caption,
            ),
          ],
        ),
      ),
      Icon(readOnly ? Icons.lock_outline_rounded : Icons.chevron_right_rounded),
    ],
  );
}

class _RemotePatientSummary extends StatelessWidget {
  const _RemotePatientSummary({required this.patient});

  final RemotePatient patient;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(child: Text(patient.name.trim()[0].toUpperCase())),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(patient.name, style: averaText(context).fieldValue),
            Text(
              '${patient.hospitalNumber} | ${patient.species}${patient.breed == null ? '' : ' | ${patient.breed}'}',
              style: averaText(context).caption,
            ),
            Text(
              'Owner: ${patient.ownerName}',
              style: averaText(context).caption,
            ),
          ],
        ),
      ),
      const Icon(Icons.chevron_right_rounded),
    ],
  );
}

class _DateCard extends StatelessWidget {
  const _DateCard({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? placeholder;
  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: InkWell(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value == null
                  ? (placeholder ?? 'Select date')
                  : DateFormat.yMMMd().format(value!),
              style: value == null
                  ? averaText(context).fieldPlaceholder
                  : averaText(context).fieldValue,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TextFieldCard extends StatelessWidget {
  const _TextFieldCard({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: averaText(context).fieldPlaceholder,
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Chip(label: Text(status));
}

class _CompatibilityWarning extends StatelessWidget {
  const _CompatibilityWarning();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(width: 8),
      const Expanded(child: Text('Species/Vaccine Review Required')),
    ],
  );
}

class _LegacySpeciesWarning extends StatelessWidget {
  const _LegacySpeciesWarning();
  @override
  Widget build(BuildContext context) => const AveraSurfaceCard(
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'This legacy patient species needs review before a compatible vaccine can be selected.',
          ),
        ),
      ],
    ),
  );
}

class _ScheduleEmpty extends StatelessWidget {
  const _ScheduleEmpty({required this.filter, required this.hasSearch});
  final VaccineScheduleFilter filter;
  final bool hasSearch;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: ListTile(
      leading: const Icon(Icons.vaccines_outlined),
      title: Text(
        hasSearch ? 'No matching patients or vaccines' : _emptyLabel(filter),
      ),
    ),
  );
}

String _emptyLabel(VaccineScheduleFilter filter) => switch (filter) {
  VaccineScheduleFilter.dueNow => 'No vaccinations require action today',
  VaccineScheduleFilter.dueToday => 'No vaccinations due today',
  VaccineScheduleFilter.upcoming => 'No upcoming vaccinations',
  VaccineScheduleFilter.overdue => 'No overdue vaccinations',
  VaccineScheduleFilter.followUp => 'No vaccination follow-ups pending',
  VaccineScheduleFilter.completed => 'No completed vaccinations found',
  VaccineScheduleFilter.all => 'No vaccination records found',
};

String _filterLabel(VaccineScheduleFilter filter) => switch (filter) {
  VaccineScheduleFilter.all => 'All',
  VaccineScheduleFilter.dueNow => 'Due Now',
  VaccineScheduleFilter.dueToday => 'Due Today',
  VaccineScheduleFilter.upcoming => 'Upcoming',
  VaccineScheduleFilter.overdue => 'Overdue',
  VaccineScheduleFilter.followUp => 'Follow-up',
  VaccineScheduleFilter.completed => 'Completed',
};

String _statusFor(Vaccination vaccination, DateTime now) {
  if (vaccination.status.toLowerCase() == 'scheduled dose recorded') {
    return 'Completed';
  }
  if (vaccination.status.toLowerCase() == 'completed' &&
      vaccination.nextDueDate == null) {
    return 'Completed';
  }
  final due = vaccination.nextDueDate;
  final start = DateTime(now.year, now.month, now.day);
  if (due == null) return 'Completed';
  if (due.isBefore(start)) return 'Overdue';
  if (due.isBefore(start.add(const Duration(days: 1)))) return 'Due Today';
  return 'Upcoming';
}

bool _matchesFilter(
  Vaccination vaccination,
  VaccineScheduleFilter filter,
  DateTime now,
) {
  final status = _statusFor(vaccination, now);
  return switch (filter) {
    VaccineScheduleFilter.all => true,
    VaccineScheduleFilter.dueNow => isVaccinationActionRequired(
      vaccination.status,
      vaccination.nextDueDate,
      now,
    ),
    VaccineScheduleFilter.dueToday => status == 'Due Today',
    VaccineScheduleFilter.upcoming => status == 'Upcoming',
    VaccineScheduleFilter.overdue => status == 'Overdue',
    VaccineScheduleFilter.followUp =>
      vaccination.nextDueDate != null &&
          status != 'Overdue' &&
          status != 'Completed',
    VaccineScheduleFilter.completed => status == 'Completed',
  };
}
