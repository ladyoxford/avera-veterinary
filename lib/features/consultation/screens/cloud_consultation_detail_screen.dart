import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/security/access_control.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../shared/widgets/avera_ui.dart';

class CloudConsultationDetailScreen extends ConsumerStatefulWidget {
  const CloudConsultationDetailScreen({
    super.key,
    required this.consultationId,
    required this.patientId,
  });

  final String consultationId;
  final String patientId;

  @override
  ConsumerState<CloudConsultationDetailScreen> createState() =>
      _CloudConsultationDetailScreenState();
}

class _CloudConsultationDetailScreenState
    extends ConsumerState<CloudConsultationDetailScreen> {
  late Future<Map<String, dynamic>> _consultation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _consultation = ref
        .read(clinicalRemoteDataSourceProvider)
        .consultation(widget.consultationId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: ValueKey('cloud-consultation-${widget.consultationId}'),
    appBar: AppBar(
      title: const Text('Consultation'),
      actions: [
        if (ref
                .watch(userSessionProvider)
                .valueOrNull
                ?.can(Permissions.consultationsEdit) ==
            true)
          IconButton(
            tooltip: 'Edit consultation',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () async {
              final updated = await context.push<bool>(
                '/consultations/${widget.consultationId}/edit'
                '?patientId=${Uri.encodeQueryComponent(widget.patientId)}',
              );
              if (updated == true && mounted) setState(_load);
            },
          ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _consultation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to load this consultation.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(_load),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          );
        }
        return _ConsultationDetails(
          value: snapshot.data!,
          expectedPatientId: widget.patientId,
        );
      },
    ),
  );
}

class _ConsultationDetails extends StatelessWidget {
  const _ConsultationDetails({
    required this.value,
    required this.expectedPatientId,
  });

  final Map<String, dynamic> value;
  final String expectedPatientId;

  @override
  Widget build(BuildContext context) {
    final returnedPatientId = value['patient_id']?.toString();
    if (returnedPatientId != expectedPatientId) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This consultation does not belong to this patient.'),
        ),
      );
    }
    final occurredAt = DateTime.tryParse('${value['occurred_at']}')?.toLocal();
    final patientName = _text(value['patient_name']);
    final hospitalNumber = _text(value['hospital_number']);
    final subtitle = occurredAt == null
        ? 'Date unavailable'
        : DateFormat.yMMMMd().add_jm().format(occurredAt);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
      children: [
        AveraPageHeader(
          title: patientName ?? 'Consultation record',
          subtitle: [hospitalNumber, subtitle].whereType<String>().join(' • '),
        ),
        const SizedBox(height: 24),
        _ReadOnlyField(
          label: 'Patient',
          value: patientName ?? 'Patient record unavailable',
        ),
        const SizedBox(height: 16),
        _ReadOnlyField(
          label: 'Complaint',
          value: _text(value['chief_complaint']),
        ),
        const SizedBox(height: 16),
        _ReadOnlyField(label: 'History', value: _text(value['history'])),
        const SizedBox(height: 16),
        _ReadOnlyField(
          label: 'Clinical Signs & Physical Exam',
          value: _text(value['examination']),
        ),
        const SizedBox(height: 16),
        _ReadOnlyField(
          label: 'Diagnosis',
          value: _text(value['final_diagnosis']) ?? _text(value['assessment']),
        ),
        const SizedBox(height: 16),
        _ReadOnlyField(label: 'Treatment', value: _text(value['treatment'])),
        const SizedBox(height: 16),
        _ReadOnlyField(
          label: 'Prescription',
          value: _text(value['prescription_notes']),
        ),
        const SizedBox(height: 16),
        _ReadOnlyField(
          label: 'Veterinarian',
          value: _text(value['clinician_name_snapshot']),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: Text(value ?? 'Not recorded', style: averaText(context).fieldValue),
  );
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
