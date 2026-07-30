import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';

class PatientNumberingScreen extends ConsumerStatefulWidget {
  const PatientNumberingScreen({super.key});

  @override
  ConsumerState<PatientNumberingScreen> createState() =>
      _PatientNumberingScreenState();
}

class _PatientNumberingScreenState
    extends ConsumerState<PatientNumberingScreen> {
  final _prefix = TextEditingController();
  var _sequenceLength = 5;
  var _resetYearly = true;
  var _saving = false;
  String? _loadedClinicId;

  @override
  void dispose() {
    _prefix.dispose();
    super.dispose();
  }

  void _hydrate(Clinic clinic) {
    if (_loadedClinicId == clinic.clinicId) return;
    _loadedClinicId = clinic.clinicId;
    _prefix.text = clinic.patientNumberPrefix ?? '';
    _sequenceLength = clinic.patientNumberSequenceLength;
    _resetYearly = clinic.patientNumberResetYearly;
  }

  Future<void> _save(UserSession session) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .updatePatientNumberingSettings(
            session: session,
            prefix: _prefix.text,
            sequenceLength: _sequenceLength,
            resetYearly: _resetYearly,
          );
      ref
        ..invalidate(hospitalNumberPreviewProvider)
        ..invalidate(userSessionProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient numbering settings saved.')),
        );
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider);
    final preview = ref.watch(hospitalNumberPreviewProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Numbering')),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Sign in again to manage patient numbering.'),
        ),
        data: (currentSession) {
          _hydrate(currentSession.clinic);
          final canManage = currentSession.can(
            Permissions.managePatientNumbering,
          );
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Hospital Number', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Changes apply to future registrations only. Existing patient numbers remain unchanged.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _prefix,
                enabled: canManage && !_saving,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Prefix',
                  hintText: 'AVR',
                  helperText: '2-8 letters or numbers. No spaces or symbols.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _sequenceLength,
                decoration: const InputDecoration(labelText: 'Sequence length'),
                items: [
                  for (var value = 4; value <= 10; value++)
                    DropdownMenuItem(
                      value: value,
                      child: Text('$value digits'),
                    ),
                ],
                onChanged: canManage && !_saving
                    ? (value) => setState(() => _sequenceLength = value ?? 5)
                    : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reset sequence yearly'),
                subtitle: const Text(
                  'A new yearly sequence begins on January 1.',
                ),
                value: _resetYearly,
                onChanged: canManage && !_saving
                    ? (value) => setState(() => _resetYearly = value)
                    : null,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: preview.when(
                    loading: () => const Text('Loading next-number preview...'),
                    error: (_, __) =>
                        const Text('Next-number preview unavailable.'),
                    data: (value) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Next-number preview'),
                        const SizedBox(height: 6),
                        Text(
                          value.hospitalNumber,
                          style: theme.textTheme.titleLarge,
                        ),
                        if (value.prefixRequiresReview) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Review this suggested prefix before clinic use.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (canManage)
                FilledButton(
                  onPressed: _saving ? null : () => _save(currentSession),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Numbering Settings'),
                )
              else
                const Text(
                  'Contact a clinic administrator to change patient numbering.',
                ),
            ],
          );
        },
      ),
    );
  }
}
