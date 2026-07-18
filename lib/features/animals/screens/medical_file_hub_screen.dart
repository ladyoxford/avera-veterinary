import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/medical_file_quick_access_provider.dart';
import '../../../core/repositories/clinic_repository.dart';
import 'animal_profile_screen.dart';

class MedicalFileHubScreen extends ConsumerWidget {
  const MedicalFileHubScreen({super.key, required this.animalId});

  final int animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(animalProfileProvider(animalId));
    final session = ref.watch(userSessionProvider).valueOrNull;

    return profile.when(
      loading: () => const _MedicalFileHubLoading(),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Medical File')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Unable to open medical file.\n$error', textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (data) => _MedicalFileHubContent(
        animalId: animalId,
        profile: data,
        session: session,
      ),
    );
  }
}

class _MedicalFileHubContent extends ConsumerWidget {
  const _MedicalFileHubContent({
    required this.animalId,
    required this.profile,
    required this.session,
  });

  final int animalId;
  final AnimalProfile profile;
  final UserSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = session == null
        ? null
        : MedicalFileQuickAccessScope(
            clinicId: session!.clinic.clinicId,
            userId: session!.user.userId,
          );
    final pinned = scope == null
        ? const AsyncValue<List<String>>.data(defaultMedicalFileQuickAccessIds)
        : ref.watch(medicalFileQuickAccessProvider(scope));
    final theme = Theme.of(context);
    final selectedRecords = pinned.valueOrNull ?? defaultMedicalFileQuickAccessIds;
    final records = selectedRecords
        .map(_MedicalFileRecord.fromId)
        .whereType<_MedicalFileRecord>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Medical File', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 3),
            Text(
              '${profile.animal.animalName} • ${profile.animal.hospitalNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ask Vera about this patient',
            icon: const Icon(Icons.auto_awesome_rounded),
            onPressed: () => context.push(
              '/vera?patientId=$animalId&patientName=${Uri.encodeComponent(profile.animal.animalName)}',
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Quick Access', style: theme.textTheme.titleLarge),
              ),
              Semantics(
                button: true,
                label: 'Customize Quick Access records',
                child: TextButton.icon(
                  onPressed: scope == null
                      ? null
                      : () => _openAllRecords(context, scope),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (pinned.isLoading)
            const _QuickAccessSkeleton()
          else
            _QuickAccessGrid(
              records: records,
              onSelected: (record) => _openRecord(context, record),
            ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: scope == null ? null : () => _openAllRecords(context, scope),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.apps_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('More Records', style: theme.textTheme.titleSmall),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
          if (scope != null) ...[
            const SizedBox(height: 14),
            Text(
              "Tap 'More Records' to see all record types and choose which eight stay pinned here.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openRecord(BuildContext context, _MedicalFileRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnimalProfileScreen(
          animalId: animalId,
          initialTab: record.tabIndex,
        ),
      ),
    );
  }

  Future<void> _openAllRecords(
    BuildContext context,
    MedicalFileQuickAccessScope scope,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AllMedicalRecordsScreen(scope: scope),
      ),
    );
  }
}

class AllMedicalRecordsScreen extends ConsumerStatefulWidget {
  const AllMedicalRecordsScreen({super.key, required this.scope});

  final MedicalFileQuickAccessScope scope;

  @override
  ConsumerState<AllMedicalRecordsScreen> createState() =>
      _AllMedicalRecordsScreenState();
}

class _AllMedicalRecordsScreenState extends ConsumerState<AllMedicalRecordsScreen> {
  List<String>? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(medicalFileQuickAccessProvider(widget.scope));
    final pinned = _draft ?? selection.valueOrNull ?? defaultMedicalFileQuickAccessIds;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Records'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(pinned),
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: _medicalFileRecords.length + 1,
        separatorBuilder: (_, index) => index == 0
            ? const SizedBox(height: 12)
            : Divider(height: 1, color: theme.colorScheme.outlineVariant),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              'Tap the pin to add or remove from your top 8 on the Medical File overview.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }
          final record = _medicalFileRecords[index - 1];
          final isPinned = pinned.contains(record.id);
          return Semantics(
            button: true,
            label: isPinned
                ? 'Remove ${record.title} from Quick Access'
                : 'Pin ${record.title} to Quick Access',
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              leading: _RecordIcon(record: record, compact: true),
              title: Text(record.title, style: theme.textTheme.titleMedium),
              subtitle: isPinned
                  ? Text(
                      'PINNED',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    )
                  : null,
              trailing: IconButton(
                tooltip: isPinned
                    ? 'Remove ${record.title} from Quick Access'
                    : 'Pin ${record.title} to Quick Access',
                icon: Icon(
                  isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: isPinned ? theme.colorScheme.primary : null,
                ),
                onPressed: () => _toggle(record.id, pinned),
              ),
              onTap: () => _toggle(record.id, pinned),
            ),
          );
        },
      ),
    );
  }

  void _toggle(String recordId, List<String> pinned) {
    final next = List<String>.of(pinned);
    if (next.contains(recordId)) {
      if (next.length == 1) {
        _message('Keep at least one record pinned.');
        return;
      }
      next.remove(recordId);
    } else {
      if (next.length >= 8) {
        _message('You can pin up to 8 records.');
        return;
      }
      next.add(recordId);
    }
    setState(() => _draft = next);
  }

  Future<void> _save(List<String> pinned) async {
    setState(() => _saving = true);
    final saved = await ref
        .read(medicalFileQuickAccessProvider(widget.scope).notifier)
        .save(pinned);
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      Navigator.of(context).pop();
    } else {
      _message('Unable to save Quick Access changes. Please try again.');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({required this.records, required this.onSelected});

  final List<_MedicalFileRecord> records;
  final ValueChanged<_MedicalFileRecord> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 5
            : constraints.maxWidth >= 490
                ? 4
                : constraints.maxWidth >= 360
                    ? 3
                    : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: records.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 16,
            childAspectRatio: columns >= 4 ? 0.95 : 1.08,
          ),
          itemBuilder: (context, index) {
            final record = records[index];
            return _QuickAccessTile(record: record, onTap: () => onSelected(record));
          },
        );
      },
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({required this.record, required this.onTap});

  final _MedicalFileRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Open ${record.title}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RecordIcon(record: record),
                const SizedBox(height: 10),
                Text(
                  record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordIcon extends StatelessWidget {
  const _RecordIcon({required this.record, this.compact = false});

  final _MedicalFileRecord record;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = compact ? 48.0 : 72.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(compact ? 14 : 20),
      ),
      child: Icon(
        record.icon,
        color: scheme.onPrimaryContainer,
        size: compact ? 24 : 31,
      ),
    );
  }
}

class _QuickAccessSkeleton extends StatelessWidget {
  const _QuickAccessSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
        childAspectRatio: 1.08,
      ),
      itemBuilder: (_, __) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          ),
          const SizedBox(height: 10),
          Container(width: 70, height: 14, color: color),
        ],
      ),
    );
  }
}

class _MedicalFileHubLoading extends StatelessWidget {
  const _MedicalFileHubLoading();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Scaffold(
      appBar: AppBar(title: const Text('Medical File')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(width: 180, height: 28, color: color),
          const SizedBox(height: 8),
          Container(width: 220, height: 16, color: color),
          const SizedBox(height: 34),
          Container(width: 140, height: 22, color: color),
          const SizedBox(height: 18),
          const _QuickAccessSkeleton(),
        ],
      ),
    );
  }
}

class _MedicalFileRecord {
  const _MedicalFileRecord(this.id, this.title, this.icon, this.tabIndex);

  final String id;
  final String title;
  final IconData icon;
  final int tabIndex;

  static _MedicalFileRecord? fromId(String id) {
    for (final record in _medicalFileRecords) {
      if (record.id == id) return record;
    }
    return null;
  }
}

const _medicalFileRecords = <_MedicalFileRecord>[
  _MedicalFileRecord('overview', 'Overview', Icons.dashboard_outlined, 0),
  _MedicalFileRecord('signalment', 'Signalment', Icons.pets_outlined, 1),
  _MedicalFileRecord('owner', 'Owner', Icons.person_outline_rounded, 2),
  _MedicalFileRecord('medical_history', 'Medical History', Icons.history_rounded, 3),
  _MedicalFileRecord('consultations', 'Consultations', Icons.medical_services_outlined, 4),
  _MedicalFileRecord('vaccinations', 'Vaccinations', Icons.vaccines_outlined, 5),
  _MedicalFileRecord('laboratory', 'Laboratory', Icons.science_outlined, 6),
  _MedicalFileRecord('hospitalization', 'Hospitalization', Icons.local_hospital_outlined, 7),
  _MedicalFileRecord('surgery', 'Surgery', Icons.medical_services_outlined, 8),
  _MedicalFileRecord('medications', 'Medications', Icons.medication_outlined, 9),
  _MedicalFileRecord('billing', 'Billing', Icons.receipt_long_outlined, 10),
  _MedicalFileRecord('appointments', 'Schedule', Icons.calendar_month_outlined, 11),
  _MedicalFileRecord('documents', 'Documents', Icons.description_outlined, 12),
  _MedicalFileRecord('images', 'Images & AI Recognition', Icons.photo_library_outlined, 13),
  _MedicalFileRecord('timeline', 'Timeline', Icons.timeline_rounded, 14),
];
