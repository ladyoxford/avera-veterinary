import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../shared/widgets/avera_ui.dart';

class CloudConsultationEditScreen extends ConsumerStatefulWidget {
  const CloudConsultationEditScreen({
    super.key,
    required this.consultationId,
    required this.patientId,
  });
  final String consultationId;
  final String patientId;

  @override
  ConsumerState<CloudConsultationEditScreen> createState() =>
      _CloudConsultationEditScreenState();
}

class _CloudConsultationEditScreenState
    extends ConsumerState<CloudConsultationEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _complaint = TextEditingController();
  final _history = TextEditingController();
  final _examination = TextEditingController();
  final _diagnosis = TextEditingController();
  final _treatment = TextEditingController();
  final _prescription = TextEditingController();
  int? _revision;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await ref
          .read(clinicalRemoteDataSourceProvider)
          .consultation(widget.consultationId);
      if ('${value['patient_id']}' != widget.patientId) {
        throw const ApiException(
          'patient_mismatch',
          'This consultation does not belong to this patient.',
        );
      }
      _complaint.text = '${value['chief_complaint'] ?? ''}';
      _history.text = '${value['history'] ?? ''}';
      _examination.text = '${value['examination'] ?? ''}';
      _diagnosis.text =
          '${value['final_diagnosis'] ?? value['assessment'] ?? ''}';
      _treatment.text = '${value['treatment'] ?? ''}';
      _prescription.text = '${value['prescription_notes'] ?? ''}';
      _revision = int.tryParse('${value['revision']}');
    } catch (error) {
      _error = error is ApiException
          ? error.message
          : 'The consultation could not be loaded.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _complaint,
      _history,
      _examination,
      _diagnosis,
      _treatment,
      _prescription,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        !(_formKey.currentState?.validate() ?? false) ||
        _revision == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicalRemoteDataSourceProvider)
          .updateConsultation(
            consultationId: widget.consultationId,
            payload: {
              'revision': _revision,
              'chiefComplaint': _complaint.text.trim(),
              'history': _history.text.trim(),
              'examination': _examination.text.trim(),
              'diagnosis': _diagnosis.text.trim(),
              'treatment': _treatment.text.trim(),
              'prescription': _prescription.text.trim(),
            },
          );
      ref
        ..invalidate(remoteDashboardProvider)
        ..invalidate(remotePatientMedicalFileProvider(widget.patientId))
        ..invalidate(
          remotePatientSectionProvider(
            RemotePatientSectionRequest(
              patientId: widget.patientId,
              section: 'consultations',
            ),
          ),
        );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Consultation updated.')));
      context.pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'The consultation could not be updated.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit Consultation')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
              children: [
                _field('Complaint', _complaint, required: true),
                _field('History', _history),
                _field('Clinical Signs & Physical Exam', _examination),
                _field('Diagnosis', _diagnosis),
                _field('Treatment', _treatment),
                _field('Prescription', _prescription),
                const SizedBox(height: 8),
                AveraPrimaryActionButton(
                  label: 'Save Changes',
                  icon: Icons.save_rounded,
                  onPressed: _saving ? null : _save,
                  loading: _saving,
                ),
              ],
            ),
          ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AveraLabeledFieldCard(
      label: label,
      child: TextFormField(
        controller: controller,
        minLines: 2,
        maxLines: null,
        decoration: const InputDecoration.collapsed(hintText: 'Not recorded'),
        validator: (value) => required && (value?.trim().isEmpty ?? true)
            ? 'Complaint is required.'
            : null,
      ),
    ),
  );
}
