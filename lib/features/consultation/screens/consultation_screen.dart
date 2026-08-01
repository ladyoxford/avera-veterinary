import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/security/access_control.dart';
import '../../../core/services/animal_age_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

enum ConsultationScreenMode { create, view, edit }

class ConsultationScreen extends ConsumerStatefulWidget {
  const ConsultationScreen({
    super.key,
    this.mode = ConsultationScreenMode.create,
    this.consultationId,
    this.initialAnimalId,
    this.initialRemotePatientId,
    this.initialAppointmentId,
    this.initialComplaint,
    this.initialVeterinarian,
  }) : assert(
         mode == ConsultationScreenMode.create || consultationId != null,
         'Saved consultation screens require a consultationId.',
       );

  final ConsultationScreenMode mode;
  final int? consultationId;
  final int? initialAnimalId;
  final String? initialRemotePatientId;
  final int? initialAppointmentId;
  final String? initialComplaint;
  final String? initialVeterinarian;

  bool get isNew => mode == ConsultationScreenMode.create;
  bool get isView => mode == ConsultationScreenMode.view;
  bool get isEdit => mode == ConsultationScreenMode.edit;

  @override
  ConsumerState<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends ConsumerState<ConsultationScreen> {
  final complaint = TextEditingController();
  final history = TextEditingController();
  final signs = TextEditingController();
  final diagnosis = TextEditingController();
  final treatment = TextEditingController();
  final prescription = TextEditingController();
  final vet = TextEditingController();

  int? animalId;
  RemotePatient? remotePatient;
  bool _loadingRecord = false;
  bool _saving = false;
  String? _loadError;
  DateTime? _consultationDate;
  late final String _submissionId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    animalId = widget.initialAnimalId;
    if (widget.isNew) {
      complaint.text = widget.initialComplaint?.trim() ?? '';
      vet.text = widget.initialVeterinarian?.trim().isNotEmpty == true
          ? widget.initialVeterinarian!.trim()
          : '';
      unawaited(_loadDefaultVeterinarian());
      if (BackendConfiguration.isConfigured &&
          widget.initialRemotePatientId?.isNotEmpty == true) {
        unawaited(_loadInitialRemotePatient());
      }
    } else {
      _loadingRecord = true;
      unawaited(_loadConsultation());
    }
  }

  Future<void> _loadInitialRemotePatient() async {
    try {
      final patient = await ref
          .read(clinicalRemoteDataSourceProvider)
          .patient(widget.initialRemotePatientId!);
      if (mounted) setState(() => remotePatient = patient);
    } catch (_) {
      // The selector remains available when a stale route parameter is used.
    }
  }

  Future<void> _loadDefaultVeterinarian() async {
    if (vet.text.trim().isNotEmpty) return;
    try {
      final session = await ref.read(userSessionProvider.future);
      if (mounted && vet.text.trim().isEmpty) {
        setState(() => vet.text = session.user.fullName);
      }
    } catch (_) {
      // The session-level error state remains responsible for sign-in recovery.
    }
  }

  @override
  void dispose() {
    complaint.dispose();
    history.dispose();
    signs.dispose();
    diagnosis.dispose();
    treatment.dispose();
    prescription.dispose();
    vet.dispose();
    super.dispose();
  }

  Future<void> _loadConsultation() async {
    try {
      final visit = await ref
          .read(clinicRepositoryProvider)
          .getVisit(widget.consultationId!);
      if (visit == null) {
        _loadError = 'This consultation is unavailable in the current clinic.';
        return;
      }
      if (kDebugMode) {
        unawaited(_logPatientDiagnostic(visit));
      }
      animalId = visit.animalId;
      _consultationDate = visit.visitDate;
      complaint.text = visit.chiefComplaint ?? '';
      history.text = visit.history ?? '';
      signs.text = visit.physicalExamination ?? '';
      diagnosis.text = visit.diagnosis ?? '';
      treatment.text = visit.treatment ?? '';
      prescription.text = visit.prescription ?? '';
      vet.text = visit.veterinarian ?? '';
    } catch (_) {
      _loadError = 'The consultation could not be loaded.';
    } finally {
      if (mounted) setState(() => _loadingRecord = false);
    }
  }

  Future<void> _logPatientDiagnostic(Visit visit) async {
    final repository = ref.read(clinicRepositoryProvider);
    final patients =
        await (repository.db.select(repository.db.animals)..where(
              (animal) => animal.clinicId.equals(repository.activeClinicId),
            ))
            .get();
    final matching = patients
        .where((animal) => animal.id == visit.animalId)
        .toList(growable: false);
    final canonical = <int, Animal>{
      for (final animal in patients) animal.id: animal,
    };
    debugPrint(
      'AVERA consultation diagnostic: id=${visit.id}, '
      'diagnosis=${visit.diagnosis ?? visit.chiefComplaint ?? 'none'}, '
      'patientId=${visit.animalId}, patientRows=${matching.length}, '
      'hospitalNumbers=${matching.map((animal) => animal.hospitalNumber).join(',')}, '
      'dropdownItems=${canonical.length}, clinicId=${repository.activeClinicId}, '
      'mergedLocalRemote=false',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final requiredPermission = widget.isNew
        ? Permissions.consultationsCreate
        : widget.isEdit
        ? Permissions.consultationsEdit
        : Permissions.consultationsView;
    final allowed = session?.can(requiredPermission) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isView ? 'Consultation' : _title),
        actions: [
          if (widget.isView &&
              session?.can(Permissions.consultationsEdit) == true)
            IconButton(
              tooltip: 'Edit consultation',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  context.push('/consultations/${widget.consultationId}/edit'),
            ),
        ],
      ),
      body: _loadingRecord
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _ConsultationMessage(
              icon: Icons.find_in_page_outlined,
              title: 'Consultation unavailable',
              message: _loadError!,
            )
          : !allowed
          ? const _ConsultationMessage(
              icon: Icons.lock_outline_rounded,
              title: 'Permission required',
              message: 'You do not have permission to perform this action.',
            )
          : BackendConfiguration.isConfigured && widget.isNew
          ? _RemoteConsultationForm(
              patient: remotePatient,
              saving: _saving,
              complaint: complaint,
              history: history,
              signs: signs,
              diagnosis: diagnosis,
              treatment: treatment,
              prescription: prescription,
              veterinarian: vet,
              onPatientChanged: (value) =>
                  setState(() => remotePatient = value),
              onSave: _saving ? null : _save,
            )
          : _ConsultationForm(
              animalId: animalId,
              consultationDate: _consultationDate,
              isNew: widget.isNew,
              isReadOnly: widget.isView,
              saving: _saving,
              complaint: complaint,
              history: history,
              signs: signs,
              diagnosis: diagnosis,
              treatment: treatment,
              prescription: prescription,
              veterinarian: vet,
              onAnimalChanged: (value) => setState(() => animalId = value),
              onSave: _saving ? null : _save,
              saveLabel: widget.isEdit ? 'Save Changes' : 'Save Consultation',
            ),
    );
  }

  String get _title => switch (widget.mode) {
    ConsultationScreenMode.create => 'New Consultation',
    ConsultationScreenMode.view => 'Consultation Detail',
    ConsultationScreenMode.edit => 'Edit Consultation',
  };

  Future<void> _save() async {
    if (BackendConfiguration.isConfigured && widget.isNew) {
      if (remotePatient == null) return;
    } else if (animalId == null) {
      return;
    }
    if (complaint.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the main complaint.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
      if (BackendConfiguration.isConfigured && widget.isNew) {
        await ref.read(remoteConsultationServiceProvider).create({
          'submissionId': _submissionId,
          'patientId': remotePatient!.id,
          'chiefComplaint': complaint.text.trim(),
          'history': history.text.trim(),
          'examination': signs.text.trim(),
          'diagnosis': diagnosis.text.trim(),
          'treatment': treatment.text.trim(),
          'prescription': prescription.text.trim(),
          'veterinarian': vet.text.trim(),
        });
        ref
          ..invalidate(remoteDashboardProvider)
          ..invalidate(remotePatientMedicalFileProvider(remotePatient!.id));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consultation saved to the medical file.'),
          ),
        );
        context.pop();
        return;
      }
      final values = VisitsCompanion(
        animalId: Value(animalId!),
        chiefComplaint: Value(complaint.text.trim()),
        history: Value(history.text.trim()),
        physicalExamination: Value(signs.text.trim()),
        diagnosis: Value(diagnosis.text.trim()),
        treatment: Value(treatment.text.trim()),
        prescription: Value(prescription.text.trim()),
        veterinarian: Value(vet.text.trim()),
      );
      final repository = ref.read(clinicRepositoryProvider);
      final visitId = widget.isEdit
          ? widget.consultationId!
          : await repository.saveVisit(
              session: session,
              visit: VisitsCompanion.insert(
                animalId: animalId!,
                visitDate: DateTime.now(),
                chiefComplaint: Value(complaint.text.trim()),
                history: Value(history.text.trim()),
                physicalExamination: Value(signs.text.trim()),
                diagnosis: Value(diagnosis.text.trim()),
                treatment: Value(treatment.text.trim()),
                prescription: Value(prescription.text.trim()),
                veterinarian: Value(vet.text.trim()),
              ),
            );

      if (widget.isEdit) {
        await repository.updateVisit(
          visitId: visitId,
          visit: values,
          session: session,
        );
      }
      if (widget.isNew && widget.initialAppointmentId != null) {
        await repository.linkAppointmentConsultation(
          session: session,
          appointmentId: widget.initialAppointmentId!,
          consultationId: visitId,
        );
        ref.invalidate(appointmentDetailProvider(widget.initialAppointmentId!));
      }

      final offline = ref.read(offlineAuthorizationSnapshotProvider);
      if (offline != null && offline.clinicId != null) {
        await ref
            .read(offlineSyncRepositoryProvider)
            .enqueue(
              clinicId: offline.clinicId!,
              userId: offline.userId,
              deviceId: await ref
                  .read(offlineAuthorizationServiceProvider)
                  .deviceId(),
              entityType: 'consultation',
              entityId: visitId.toString(),
              operationType: widget.isEdit ? 'update' : 'create',
              payload: {
                'localVisitId': visitId,
                'localAnimalId': animalId,
                'chiefComplaint': complaint.text.trim(),
                'diagnosis': diagnosis.text.trim(),
                'treatment': treatment.text.trim(),
              },
            );
      }

      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(animalProfileProvider(animalId!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? 'Consultation updated.'
                : 'Consultation saved to the medical file.',
          ),
        ),
      );
      context.pop();
    } catch (error) {
      if (mounted) {
        final message = error is ApiException
            ? error.message
            : 'The consultation could not be saved. Your entries are still available.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _RemoteConsultationForm extends ConsumerWidget {
  const _RemoteConsultationForm({
    required this.patient,
    required this.saving,
    required this.complaint,
    required this.history,
    required this.signs,
    required this.diagnosis,
    required this.treatment,
    required this.prescription,
    required this.veterinarian,
    required this.onPatientChanged,
    required this.onSave,
  });

  final RemotePatient? patient;
  final bool saving;
  final TextEditingController complaint;
  final TextEditingController history;
  final TextEditingController signs;
  final TextEditingController diagnosis;
  final TextEditingController treatment;
  final TextEditingController prescription;
  final TextEditingController veterinarian;
  final ValueChanged<RemotePatient?> onPatientChanged;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(
      AveraSpacing.pageHorizontalPadding,
      AveraSpacing.pageTopPadding,
      AveraSpacing.pageHorizontalPadding,
      AveraSpacing.bottomContentClearance,
    ),
    children: [
      Text(
        '${veterinarian.text.isEmpty ? 'Clinic team' : veterinarian.text} | Select patient context',
        style: averaText(context).pageSubtitle,
      ),
      const SizedBox(height: AveraSpacing.subtitleToContentGap),
      AveraLabeledFieldCard(
        label: 'Patient',
        child: InkWell(
          onTap: saving ? null : () => _selectPatient(context),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  patient == null
                      ? 'Select a patient'
                      : '${patient!.name} | ${patient!.hospitalNumber}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: patient == null
                      ? averaText(context).fieldPlaceholder
                      : averaText(context).fieldValue,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      _ConsultationFieldCard(
        controller: complaint,
        label: 'Complaint',
        readOnly: false,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      _ConsultationFieldCard(
        controller: history,
        label: 'History',
        readOnly: false,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      _ConsultationFieldCard(
        controller: signs,
        label: 'Clinical Signs & Physical Exam',
        readOnly: false,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      _ConsultationFieldCard(
        controller: diagnosis,
        label: 'Diagnosis',
        readOnly: false,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      _ConsultationFieldCard(
        controller: treatment,
        label: 'Treatment',
        readOnly: false,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      _ConsultationFieldCard(
        controller: prescription,
        label: 'Prescription',
        readOnly: false,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      _ConsultationFieldCard(
        controller: veterinarian,
        label: 'Veterinarian',
        readOnly: false,
        multiline: false,
      ),
      const SizedBox(height: AveraSpacing.subtitleToContentGap),
      AveraPrimaryActionButton(
        label: 'Save Consultation',
        icon: Iconsax.save_2,
        loading: saving,
        onPressed: patient == null ? null : onSave,
      ),
    ],
  );

  Future<void> _selectPatient(BuildContext context) async {
    final selected = await showModalBottomSheet<RemotePatient>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.86,
        child: _RemotePatientSelectorSheet(selectedId: patient?.id),
      ),
    );
    if (context.mounted && selected != null) onPatientChanged(selected);
  }
}

class _RemotePatientSelectorSheet extends ConsumerStatefulWidget {
  const _RemotePatientSelectorSheet({this.selectedId});
  final String? selectedId;

  @override
  ConsumerState<_RemotePatientSelectorSheet> createState() =>
      _RemotePatientSelectorSheetState();
}

class _RemotePatientSelectorSheetState
    extends ConsumerState<_RemotePatientSelectorSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  late Future<List<RemotePatient>> _patients;

  @override
  void initState() {
    super.initState();
    _patients = _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<List<RemotePatient>> _load(String query) async {
    final source = ref.read(clinicalRemoteDataSourceProvider);
    final patients = <String, RemotePatient>{};
    var page = 1;
    var hasNext = true;
    while (hasNext) {
      final result = await source.patients(
        page: page,
        pageSize: 100,
        search: query,
        status: 'Active',
      );
      for (final patient in result.items) {
        patients[patient.id] = patient;
      }
      hasNext = result.hasNextPage;
      page += 1;
    }
    final result = patients.values.toList()
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName != 0
            ? byName
            : a.hospitalNumber.compareTo(b.hospitalNumber);
      });
    return result;
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _patients = _load(value.trim()));
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Patient', style: averaText(context).sectionTitle),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search name, hospital number, owner or phone',
          ),
          onChanged: _searchChanged,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<List<RemotePatient>>(
            future: _patients,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Patient records could not be loaded.'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => setState(
                          () => _patients = _load(_search.text.trim()),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final items = snapshot.data ?? const <RemotePatient>[];
              if (items.isEmpty) {
                return const Center(child: Text('No active patients found.'));
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final patient = items[index];
                  return ListTile(
                    title: Text(patient.name),
                    subtitle: Text(
                      '${patient.hospitalNumber} | ${patient.species}${patient.breed == null ? '' : ' | ${patient.breed}'}',
                    ),
                    trailing: patient.id == widget.selectedId
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.of(context).pop(patient),
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

class _ConsultationForm extends ConsumerWidget {
  const _ConsultationForm({
    required this.animalId,
    required this.consultationDate,
    required this.isNew,
    required this.isReadOnly,
    required this.saving,
    required this.complaint,
    required this.history,
    required this.signs,
    required this.diagnosis,
    required this.treatment,
    required this.prescription,
    required this.veterinarian,
    required this.onAnimalChanged,
    required this.onSave,
    required this.saveLabel,
  });

  final int? animalId;
  final DateTime? consultationDate;
  final bool isNew;
  final bool isReadOnly;
  final bool saving;
  final TextEditingController complaint;
  final TextEditingController history;
  final TextEditingController signs;
  final TextEditingController diagnosis;
  final TextEditingController treatment;
  final TextEditingController prescription;
  final TextEditingController veterinarian;
  final ValueChanged<int?> onAnimalChanged;
  final VoidCallback? onSave;
  final String saveLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animals = ref.watch(clinicRepositoryProvider).watchAnimals();
    return StreamBuilder<List<Animal>>(
      stream: animals,
      builder: (context, snapshot) {
        final canonicalById = <int, Animal>{};
        for (final animal in snapshot.data ?? const <Animal>[]) {
          canonicalById.putIfAbsent(animal.id, () => animal);
        }
        final list = canonicalById.values.toList()
          ..sort((a, b) {
            final hospital = a.hospitalNumber.compareTo(b.hospitalNumber);
            return hospital != 0 ? hospital : a.id.compareTo(b.id);
          });
        final matchingItems = list
            .where((animal) => animal.id == animalId)
            .toList();
        final safeSelectedPatientId = matchingItems.length == 1
            ? animalId
            : null;
        final selectedPatient = safeSelectedPatientId == null
            ? null
            : canonicalById[safeSelectedPatientId];
        final DateTime ageReferenceDate =
            consultationDate ?? ref.watch(animalAgeReferenceDateProvider);
        final subtitle = isNew
            ? '${veterinarian.text.isEmpty ? 'Veterinarian' : veterinarian.text} • Select patient context'
            : '${veterinarian.text.isEmpty ? 'Clinic team' : veterinarian.text} • Saved consultation';
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.pageTopPadding,
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.bottomContentClearance,
          ),
          children: [
            Text(subtitle, style: averaText(context).pageSubtitle),
            const SizedBox(height: AveraSpacing.subtitleToContentGap),
            if (isReadOnly)
              _ReadOnlyFieldCard(
                label: 'Patient',
                value: selectedPatient == null
                    ? 'Patient record unavailable'
                    : '${selectedPatient.animalName} • ${selectedPatient.hospitalNumber}',
              )
            else
              AveraLabeledFieldCard(
                label: 'Patient',
                child: DropdownButtonFormField<int>(
                  value: safeSelectedPatientId,
                  isExpanded: true,
                  hint: Text(
                    'Select a patient',
                    style: averaText(context).fieldPlaceholder,
                  ),
                  style: averaText(context).fieldValue,
                  decoration: const InputDecoration.collapsed(hintText: ''),
                  items: [
                    for (final animal in list)
                      DropdownMenuItem<int>(
                        value: animal.id,
                        child: Text(
                          '${animal.animalName} • ${animal.hospitalNumber}',
                        ),
                      ),
                  ],
                  onChanged: snapshot.hasData ? onAnimalChanged : null,
                ),
              ),
            if (selectedPatient?.dateOfBirth != null) ...[
              const SizedBox(height: AveraSpacing.cardGap),
              _ReadOnlyFieldCard(
                label: isReadOnly
                    ? 'Age at Consultation'
                    : 'Current Patient Age',
                value: AnimalAgeService.displayAge(
                  birthDate: selectedPatient!.dateOfBirth!,
                  referenceDate: ageReferenceDate,
                  estimated: selectedPatient.isDateOfBirthEstimated,
                ),
              ),
            ],
            const SizedBox(height: AveraSpacing.cardGap),
            _ConsultationFieldCard(
              controller: complaint,
              label: 'Complaint',
              readOnly: isReadOnly,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _ConsultationFieldCard(
              controller: history,
              label: 'History',
              readOnly: isReadOnly,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _ConsultationFieldCard(
              controller: signs,
              label: 'Clinical Signs & Physical Exam',
              readOnly: isReadOnly,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _ConsultationFieldCard(
              controller: diagnosis,
              label: 'Diagnosis',
              readOnly: isReadOnly,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _ConsultationFieldCard(
              controller: treatment,
              label: 'Treatment',
              readOnly: isReadOnly,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _ConsultationFieldCard(
              controller: prescription,
              label: 'Prescription',
              readOnly: isReadOnly,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _ConsultationFieldCard(
              controller: veterinarian,
              label: 'Veterinarian',
              readOnly: isReadOnly,
              multiline: false,
            ),
            if (!isReadOnly) ...[
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              AveraPrimaryActionButton(
                label: saveLabel,
                icon: Iconsax.save_2,
                loading: saving,
                onPressed: safeSelectedPatientId == null ? null : onSave,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ConsultationFieldCard extends StatelessWidget {
  const _ConsultationFieldCard({
    required this.controller,
    required this.label,
    required this.readOnly,
    this.multiline = true,
  });

  final TextEditingController controller;
  final String label;
  final bool readOnly;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    if (readOnly) {
      return _ReadOnlyFieldCard(
        label: label,
        value: controller.text.trim().isEmpty
            ? 'Not recorded'
            : controller.text.trim(),
      );
    }
    return AveraLabeledFieldCard(
      label: label,
      child: TextField(
        controller: controller,
        minLines: multiline ? 2 : 1,
        maxLines: multiline ? 6 : 1,
        style: averaText(context).fieldValue,
        decoration: InputDecoration.collapsed(
          hintText: multiline ? 'Enter $label' : 'Enter $label',
          hintStyle: averaText(context).fieldPlaceholder,
        ),
      ),
    );
  }
}

class _ReadOnlyFieldCard extends StatelessWidget {
  const _ReadOnlyFieldCard({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: Text(value, style: averaText(context).fieldValue),
  );
}

class _ConsultationMessage extends StatelessWidget {
  const _ConsultationMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
