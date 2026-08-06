import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/medical_file_quick_access_provider.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
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
            child: Text(
              'Unable to open medical file.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (data) => _MedicalFileHubContent(
        patientName: data.animal.animalName,
        hospitalNumber: data.animal.hospitalNumber,
        scope: _quickAccessScope(session),
        onRecordSelected: (record) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AnimalProfileScreen(
              animalId: animalId,
              initialTab: record.tabIndex,
            ),
          ),
        ),
        onVeraPressed: () => context.push(
          '/vera?patientId=$animalId&patientName=${Uri.encodeComponent(data.animal.animalName)}',
        ),
      ),
    );
  }
}

class CloudMedicalFileHubScreen extends ConsumerWidget {
  const CloudMedicalFileHubScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(remotePatientMedicalFileProvider(patientId));
    final session = ref.watch(userSessionProvider).valueOrNull;

    return file.when(
      loading: () => const _MedicalFileHubLoading(),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Medical File')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off_outlined, size: 42),
                const SizedBox(height: 16),
                const Text(
                  'Unable to open this patient medical file.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(
                    remotePatientMedicalFileProvider(patientId),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (value) => _MedicalFileHubContent(
        patientName: value.patient.name,
        hospitalNumber: value.patient.hospitalNumber,
        scope: _quickAccessScope(session),
        summary: _CloudPatientSummary(patient: value.patient),
        onRecordSelected: (record) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _CloudMedicalRecordScreen(
              patientId: patientId,
              file: value,
              record: record,
            ),
          ),
        ),
        onVeraPressed: () => context.push(
          '/vera?patientId=${Uri.encodeQueryComponent(patientId)}&patientName=${Uri.encodeComponent(value.patient.name)}',
        ),
      ),
    );
  }
}

MedicalFileQuickAccessScope? _quickAccessScope(UserSession? session) {
  if (session == null) return null;
  return MedicalFileQuickAccessScope(
    clinicId: session.clinic.clinicId,
    userId: session.user.userId,
  );
}

class _MedicalFileHubContent extends ConsumerStatefulWidget {
  const _MedicalFileHubContent({
    required this.patientName,
    required this.hospitalNumber,
    required this.scope,
    required this.onRecordSelected,
    required this.onVeraPressed,
    this.summary,
  });

  final String patientName;
  final String hospitalNumber;
  final MedicalFileQuickAccessScope? scope;
  final ValueChanged<_MedicalFileRecord> onRecordSelected;
  final VoidCallback onVeraPressed;
  final Widget? summary;

  @override
  ConsumerState<_MedicalFileHubContent> createState() =>
      _MedicalFileHubContentState();
}

class _MedicalFileHubContentState
    extends ConsumerState<_MedicalFileHubContent> {
  @override
  Widget build(BuildContext context) {
    final quickAccessScope = widget.scope;
    final pinned = quickAccessScope == null
        ? const AsyncValue<List<String>>.data(defaultMedicalFileQuickAccessIds)
        : ref.watch(medicalFileQuickAccessProvider(quickAccessScope));
    final theme = Theme.of(context);
    final selectedRecords =
        pinned.valueOrNull ?? defaultMedicalFileQuickAccessIds;
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
              '${widget.patientName} \u2022 ${widget.hospitalNumber}',
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
            onPressed: widget.onVeraPressed,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 112),
        children: [
          if (widget.summary != null) ...[
            widget.summary!,
            const SizedBox(height: 28),
          ],
          Row(
            children: [
              Expanded(
                child: Text('Quick Access', style: theme.textTheme.titleLarge),
              ),
              Semantics(
                button: true,
                label: 'Customize Quick Access records',
                child: TextButton.icon(
                  onPressed: quickAccessScope == null
                      ? null
                      : () => _openAllRecords(context, quickAccessScope),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
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
              onSelected: widget.onRecordSelected,
            ),
          const SizedBox(height: 24),
          SizedBox(
            key: const Key('medical-file-more-records'),
            height: 54,
            child: OutlinedButton(
              onPressed: quickAccessScope == null
                  ? null
                  : () => _openAllRecords(context, quickAccessScope),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.apps_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'More Records',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
          if (quickAccessScope != null) ...[
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

class _AllMedicalRecordsScreenState
    extends ConsumerState<AllMedicalRecordsScreen> {
  List<String>? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(medicalFileQuickAccessProvider(widget.scope));
    final pinned =
        _draft ?? selection.valueOrNull ?? defaultMedicalFileQuickAccessIds;
    final theme = Theme.of(context);

    return Scaffold(
      key: const Key('medical-file-all-records-screen'),
      appBar: AppBar(
        title: const Text('All Records'),
        actions: [
          TextButton(
            key: const Key('medical-file-all-records-done'),
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPinned)
                    PopupMenuButton<int>(
                      key: Key('medical-file-reorder-${record.id}'),
                      tooltip: 'Reorder ${record.title}',
                      icon: const Icon(Icons.drag_handle_rounded),
                      onSelected: (offset) => _move(record.id, pinned, offset),
                      itemBuilder: (_) {
                        final position = pinned.indexOf(record.id);
                        return [
                          PopupMenuItem(
                            value: -1,
                            enabled: position > 0,
                            child: const Text('Move up'),
                          ),
                          PopupMenuItem(
                            value: 1,
                            enabled: position < pinned.length - 1,
                            child: const Text('Move down'),
                          ),
                        ];
                      },
                    ),
                  IconButton(
                    key: Key('medical-file-pin-${record.id}'),
                    tooltip: isPinned
                        ? 'Remove ${record.title} from Quick Access'
                        : 'Pin ${record.title} to Quick Access',
                    icon: Icon(
                      isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      color: isPinned ? theme.colorScheme.primary : null,
                    ),
                    onPressed: () => _toggle(record.id, pinned),
                  ),
                ],
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

  void _move(String recordId, List<String> pinned, int offset) {
    final next = List<String>.of(pinned);
    final current = next.indexOf(recordId);
    final target = current + offset;
    if (current < 0 || target < 0 || target >= next.length) return;
    next
      ..removeAt(current)
      ..insert(target, recordId);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CloudMedicalRecordContent extends ConsumerStatefulWidget {
  const _CloudMedicalRecordContent({
    required this.patientId,
    required this.file,
    required this.record,
  });

  final String patientId;
  final RemotePatientMedicalFile file;
  final _MedicalFileRecord record;

  @override
  ConsumerState<_CloudMedicalRecordContent> createState() =>
      _CloudMedicalRecordContentState();
}

class _CloudMedicalRecordContentState
    extends ConsumerState<_CloudMedicalRecordContent> {
  Future<RemotePage<Map<String, dynamic>>>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CloudMedicalRecordContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.id != widget.record.id ||
        oldWidget.patientId != widget.patientId) {
      _load();
    }
  }

  void _load() {
    final path = _remoteSectionPath(widget.record.id);
    _records = path == null
        ? null
        : ref
              .read(clinicalRemoteDataSourceProvider)
              .patientSection(widget.patientId, path);
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.record.id) {
      case 'overview':
        return _CloudOverviewRecord(file: widget.file);
      case 'signalment':
        return _CloudSignalmentRecord(patient: widget.file.patient);
      case 'owner':
        return _CloudOwnerRecord(patient: widget.file.patient);
      case 'medical_history':
      case 'timeline':
        return _CloudTimelineRecord(file: widget.file);
      default:
        final future = _records;
        if (future == null) {
          return _RecordUnavailableState(record: widget.record);
        }
        return FutureBuilder<RemotePage<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _RecordLoadError(
                title: widget.record.title,
                onRetry: () => setState(_load),
              );
            }
            final items = snapshot.data?.items ?? const [];
            if (items.isEmpty) {
              return _RecordEmptyState(record: widget.record);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _CloudRecordCard(
                patientId: widget.patientId,
                record: widget.record,
                value: items[index],
              ),
            );
          },
        );
    }
  }
}

class _CloudMedicalRecordScreen extends ConsumerStatefulWidget {
  const _CloudMedicalRecordScreen({
    required this.patientId,
    required this.file,
    required this.record,
  });

  final String patientId;
  final RemotePatientMedicalFile file;
  final _MedicalFileRecord record;

  @override
  ConsumerState<_CloudMedicalRecordScreen> createState() =>
      _CloudMedicalRecordScreenState();
}

class _CloudMedicalRecordScreenState
    extends ConsumerState<_CloudMedicalRecordScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      key: ValueKey(
        'remote-medical-record-${widget.record.id}-${widget.patientId}',
      ),
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.record.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 3),
            Text(
              'Medical File \u2022 ${widget.file.patient.name} \u2022 ${widget.file.patient.hospitalNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: _body(),
      floatingActionButton:
          widget.record.id == 'consultations' &&
              session?.can(Permissions.consultationsCreate) == true
          ? FloatingActionButton.extended(
              onPressed: () => context.push(
                '/consultations/new?patientId=${Uri.encodeQueryComponent(widget.patientId)}',
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Consultation'),
            )
          : null,
    );
  }

  Widget _body() {
    switch (widget.record.id) {
      case 'overview':
        return _CloudOverviewRecord(file: widget.file);
      case 'signalment':
        return _CloudSignalmentRecord(patient: widget.file.patient);
      case 'owner':
        return _CloudOwnerRecord(patient: widget.file.patient);
      case 'medical_history':
      case 'timeline':
        return _CloudTimelineRecord(file: widget.file);
      default:
        final path = _remoteSectionPath(widget.record.id);
        if (path == null) {
          return _RecordUnavailableState(record: widget.record);
        }
        final request = RemotePatientSectionRequest(
          patientId: widget.patientId,
          section: path,
        );
        final section = ref.watch(remotePatientSectionProvider(request));
        return section.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _RecordLoadError(
            title: widget.record.title,
            onRetry: () =>
                ref.invalidate(remotePatientSectionProvider(request)),
          ),
          data: (page) {
            if (page.items.isEmpty) {
              return _RecordEmptyState(record: widget.record);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _CloudRecordCard(
                patientId: widget.patientId,
                record: widget.record,
                value: page.items[index],
              ),
            );
          },
        );
    }
  }
}

class _CloudPatientSummary extends StatelessWidget {
  const _CloudPatientSummary({required this.patient});

  final RemotePatient patient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = patient.dateOfBirth == null
        ? 'Not recorded'
        : _compactAge(patient.dateOfBirth!);
    return Semantics(
      container: true,
      label: '${patient.name} patient summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  patient.name.trim().isEmpty
                      ? '?'
                      : patient.name.trim()[0].toUpperCase(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient.name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      [
                        patient.species,
                        patient.breed,
                        patient.sex,
                        age,
                      ].whereType<String>().join(' \u2022 '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(patient.status),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          _CompactDetailGrid(
            values: [
              ('Hospital number', patient.hospitalNumber),
              ('Species', patient.species),
              ('Breed', patient.breed ?? 'Not recorded'),
              ('Sex', patient.sex ?? 'Not recorded'),
              ('Age', age),
              (
                'Weight',
                patient.currentWeightKg == null
                    ? 'Not recorded'
                    : '${patient.currentWeightKg} kg',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloudOverviewRecord extends StatelessWidget {
  const _CloudOverviewRecord({required this.file});

  final RemotePatientMedicalFile file;

  @override
  Widget build(BuildContext context) {
    final patient = file.patient;
    final theme = Theme.of(context);
    final age = patient.dateOfBirth == null
        ? 'Not recorded'
        : _compactAge(patient.dateOfBirth!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Card(
          key: const Key('medical-file-compact-overview'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        patient.name.trim().isEmpty
                            ? '?'
                            : patient.name.trim()[0].toUpperCase(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(patient.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                            [
                              patient.species,
                              patient.breed,
                              patient.sex,
                              age,
                            ].whereType<String>().join(' • '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(patient.status),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                _CompactDetailGrid(
                  values: [
                    ('Hospital number', patient.hospitalNumber),
                    ('Species', patient.species),
                    ('Breed', patient.breed ?? 'Not recorded'),
                    ('Sex', patient.sex ?? 'Not recorded'),
                    ('Age', age),
                    (
                      'Weight',
                      patient.currentWeightKg == null
                          ? 'Not recorded'
                          : '${patient.currentWeightKg} kg',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactDetailGrid extends StatelessWidget {
  const _CompactDetailGrid({required this.values});

  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 14,
        children: [
          for (final value in values)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.$1,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(value.$2, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
        ],
      );
    },
  );
}

String _compactAge(DateTime birthDate) {
  final now = DateTime.now();
  var years = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    years--;
  }
  if (years > 0) return '$years ${years == 1 ? 'year' : 'years'}';
  final months = (now.year - birthDate.year) * 12 + now.month - birthDate.month;
  if (months > 0) return '$months ${months == 1 ? 'month' : 'months'}';
  final days = now.difference(birthDate).inDays.clamp(0, 365);
  return '$days ${days == 1 ? 'day' : 'days'}';
}

class _CloudSignalmentRecord extends StatelessWidget {
  const _CloudSignalmentRecord({required this.patient});

  final RemotePatient patient;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
    children: [
      _RemoteDetailCard(
        title: 'Signalment',
        children: [
          _RemoteDetailRow('Patient', patient.name),
          _RemoteDetailRow('Species', patient.species),
          _RemoteDetailRow('Breed', patient.breed ?? 'Not specified'),
          _RemoteDetailRow('Sex', patient.sex ?? 'Not specified'),
        ],
      ),
    ],
  );
}

class _CloudOwnerRecord extends StatelessWidget {
  const _CloudOwnerRecord({required this.patient});

  final RemotePatient patient;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
    children: [
      _RemoteDetailCard(
        title: 'Owner',
        children: [
          _RemoteDetailRow('Full Name', patient.ownerName),
          _RemoteDetailRow(
            'Phone',
            patient.ownerPhone.isEmpty ? 'Not provided' : patient.ownerPhone,
          ),
          _RemoteDetailRow('Email', patient.ownerEmail ?? 'Not provided'),
          _RemoteDetailRow('Address', patient.ownerAddress ?? 'Not provided'),
        ],
      ),
    ],
  );
}

class _CloudTimelineRecord extends StatelessWidget {
  const _CloudTimelineRecord({required this.file});

  final RemotePatientMedicalFile file;

  @override
  Widget build(BuildContext context) {
    if (file.timeline.isEmpty) {
      return const _RecordMessageState(
        icon: Icons.history_rounded,
        title: 'No medical history yet',
        message: 'Clinical activity for this patient will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: file.timeline.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = file.timeline[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(event['summary'] as String? ?? 'Clinical record'),
            subtitle: Text(event['type'] as String? ?? 'Record'),
          ),
        );
      },
    );
  }
}

class _RemoteDetailCard extends StatelessWidget {
  const _RemoteDetailCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}

class _RemoteDetailRow extends StatelessWidget {
  const _RemoteDetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _CloudRecordCard extends StatelessWidget {
  const _CloudRecordCard({
    required this.patientId,
    required this.record,
    required this.value,
  });

  final String patientId;
  final _MedicalFileRecord record;
  final Map<String, dynamic> value;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: _RecordIcon(record: record, compact: true),
      title: Text(_remoteRecordTitle(value)),
      subtitle: Text(_remoteRecordDate(value) ?? 'Date unavailable'),
      trailing: record.id == 'consultations'
          ? const Icon(Icons.chevron_right_rounded)
          : null,
      onTap: record.id == 'consultations'
          ? () {
              final consultationId = value['consultation_id']?.toString();
              if (consultationId == null || consultationId.isEmpty) return;
              context.push(
                '/consultations/$consultationId?patientId=${Uri.encodeQueryComponent(patientId)}',
              );
            }
          : null,
    ),
  );
}

class _RecordEmptyState extends StatelessWidget {
  const _RecordEmptyState({required this.record});

  final _MedicalFileRecord record;

  @override
  Widget build(BuildContext context) => _RecordMessageState(
    icon: record.icon,
    title: 'No ${record.title.toLowerCase()} yet',
    message: 'Records added for this patient will appear here.',
  );
}

class _RecordUnavailableState extends StatelessWidget {
  const _RecordUnavailableState({required this.record});

  final _MedicalFileRecord record;

  @override
  Widget build(BuildContext context) => _RecordMessageState(
    icon: record.icon,
    title: '${record.title} unavailable',
    message:
        'This record category is not yet available from the production service.',
  );
}

class _RecordLoadError extends StatelessWidget {
  const _RecordLoadError({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42),
          const SizedBox(height: 16),
          Text('Unable to load $title', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
}

class _RecordMessageState extends StatelessWidget {
  const _RecordMessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

String? _remoteSectionPath(String recordId) => switch (recordId) {
  'consultations' => 'consultations',
  'vaccinations' => 'vaccinations',
  'laboratory' => 'laboratory',
  'hospitalization' => 'hospitalizations',
  'surgery' => 'surgeries',
  'medications' => 'prescriptions',
  'billing' => 'billing',
  'appointments' => 'appointments',
  'documents' => 'documents',
  'images' => 'images',
  _ => null,
};

String _remoteRecordTitle(Map<String, dynamic> value) =>
    (value['final_diagnosis'] ??
            value['vaccine_name'] ??
            value['test_type'] ??
            value['diagnosis'] ??
            value['procedure_name'] ??
            value['drug_name'] ??
            value['invoice_number'] ??
            value['visit_type'] ??
            value['category'] ??
            'Clinical record')
        as String;

String? _remoteRecordDate(Map<String, dynamic> value) =>
    (value['occurred_at'] ??
            value['administered_at'] ??
            value['requested_at'] ??
            value['admitted_at'] ??
            value['performed_at'] ??
            value['prescribed_at'] ??
            value['issued_at'] ??
            value['scheduled_at'] ??
            value['created_at'])
        as String?;

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({required this.records, required this.onSelected});

  final List<_MedicalFileRecord> records;
  final ValueChanged<_MedicalFileRecord> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _quickAccessColumns(constraints.maxWidth);
        return GridView.builder(
          key: const Key('medical-file-quick-access-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: records.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 16,
            mainAxisExtent: columns == 2 ? 174 : 150,
          ),
          itemBuilder: (context, index) {
            final record = records[index];
            return _QuickAccessTile(
              record: record,
              onTap: () => onSelected(record),
            );
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
        key: Key('medical-file-tile-${record.id}'),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _quickAccessColumns(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 8,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 16,
            mainAxisExtent: columns == 2 ? 174 : 150,
          ),
          itemBuilder: (_, __) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 10),
              Container(width: 70, height: 14, color: color),
            ],
          ),
        );
      },
    );
  }
}

int _quickAccessColumns(double width) => width >= 700
    ? 5
    : width >= 490
    ? 4
    : width >= 360
    ? 3
    : 2;

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
  _MedicalFileRecord(
    'medical_history',
    'Medical History',
    Icons.history_rounded,
    3,
  ),
  _MedicalFileRecord(
    'consultations',
    'Consultations',
    Icons.medical_services_outlined,
    4,
  ),
  _MedicalFileRecord(
    'vaccinations',
    'Vaccinations',
    Icons.vaccines_outlined,
    5,
  ),
  _MedicalFileRecord('laboratory', 'Laboratory', Icons.science_outlined, 6),
  _MedicalFileRecord(
    'hospitalization',
    'Hospitalization',
    Icons.local_hospital_outlined,
    7,
  ),
  _MedicalFileRecord('surgery', 'Surgery', Icons.medical_services_outlined, 8),
  _MedicalFileRecord(
    'medications',
    'Medications',
    Icons.medication_outlined,
    9,
  ),
  _MedicalFileRecord('billing', 'Billing', Icons.receipt_long_outlined, 10),
  _MedicalFileRecord(
    'appointments',
    'Schedule',
    Icons.calendar_month_outlined,
    11,
  ),
  _MedicalFileRecord('documents', 'Documents', Icons.description_outlined, 12),
  _MedicalFileRecord(
    'images',
    'Images & AI Recognition',
    Icons.photo_library_outlined,
    13,
  ),
  _MedicalFileRecord('timeline', 'Timeline', Icons.timeline_rounded, 14),
];
