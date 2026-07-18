import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/security/access_control.dart';

enum ConsultationScreenMode { create, view, edit }

class ConsultationScreen extends ConsumerStatefulWidget {
  const ConsultationScreen({
    super.key,
    this.mode = ConsultationScreenMode.create,
    this.consultationId,
    this.initialAnimalId,
  }) : assert(
         mode == ConsultationScreenMode.create || consultationId != null,
         'Saved consultation screens require a consultationId.',
       );

  final ConsultationScreenMode mode;
  final int? consultationId;
  final int? initialAnimalId;

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
  bool _loadingRecord = false;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    animalId = widget.initialAnimalId;
    if (widget.isNew) {
      vet.text = 'Dr. Amina Okafor';
    } else {
      _loadingRecord = true;
      unawaited(_loadConsultation());
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
      animalId = visit.animalId;
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
        title: Text(_title),
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
          : _ConsultationForm(
              animalId: animalId,
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
    if (animalId == null) return;
    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ConsultationForm extends ConsumerWidget {
  const _ConsultationForm({
    required this.animalId,
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
        final list = snapshot.data ?? const <Animal>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              value: animalId,
              decoration: const InputDecoration(
                labelText: 'Patient',
                prefixIcon: Icon(Iconsax.search_normal),
              ),
              items: [
                for (final animal in list)
                  DropdownMenuItem(
                    value: animal.id,
                    child: Text(
                      '${animal.animalName} - ${animal.hospitalNumber}',
                    ),
                  ),
              ],
              onChanged: isNew && !isReadOnly ? onAnimalChanged : null,
            ),
            const SizedBox(height: 12),
            _ConsultationField(
              controller: complaint,
              label: 'Complaint',
              readOnly: isReadOnly,
            ),
            _ConsultationField(
              controller: history,
              label: 'History',
              readOnly: isReadOnly,
            ),
            _ConsultationField(
              controller: signs,
              label: 'Clinical Signs and Physical Examination',
              readOnly: isReadOnly,
            ),
            _ConsultationField(
              controller: diagnosis,
              label: 'Diagnosis',
              readOnly: isReadOnly,
            ),
            _ConsultationField(
              controller: treatment,
              label: 'Treatment',
              readOnly: isReadOnly,
            ),
            _ConsultationField(
              controller: prescription,
              label: 'Prescription',
              readOnly: isReadOnly,
            ),
            TextField(
              controller: veterinarian,
              readOnly: isReadOnly,
              decoration: const InputDecoration(labelText: 'Veterinarian'),
            ),
            if (!isReadOnly) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: animalId == null || saving ? null : onSave,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Iconsax.save_2),
                label: Text(saveLabel),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ConsultationField extends StatelessWidget {
  const _ConsultationField({
    required this.controller,
    required this.label,
    required this.readOnly,
  });

  final TextEditingController controller;
  final String label;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      ),
    );
  }
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
