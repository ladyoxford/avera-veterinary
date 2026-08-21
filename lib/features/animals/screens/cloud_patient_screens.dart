import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/identity_avatar.dart';

class CloudPatientListScreen extends ConsumerStatefulWidget {
  const CloudPatientListScreen({super.key});

  @override
  ConsumerState<CloudPatientListScreen> createState() =>
      _CloudPatientListScreenState();
}

class _CloudPatientListScreenState
    extends ConsumerState<CloudPatientListScreen> {
  final _scrollController = ScrollController();
  Timer? _debounce;
  String _filter = 'Active';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 360) {
        ref.read(remotePatientListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remotePatientListProvider);
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      floatingActionButton: session?.can(Permissions.patientsCreate) == true
          ? FloatingActionButton.extended(
              tooltip: 'Register Pet',
              icon: const Icon(Icons.add_rounded),
              label: const Text('Register Pet'),
              onPressed: () => context.push('/animals/new'),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref
              .read(remotePatientListProvider.notifier)
              .refresh(status: _filter),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registered Pets',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Live clinic records',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SearchBar(
                        leading: const Icon(Icons.search_rounded),
                        hintText:
                            'Search name, hospital number, owner or phone',
                        onChanged: (value) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 350),
                            () => ref
                                .read(remotePatientListProvider.notifier)
                                .refresh(search: value, status: _filter),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      if (state.fromCache) ...[
                        const _OfflineRecordsNotice(),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children:
                              ['Active', 'All Animals', 'Deceased', 'Relocated']
                                  .map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(item),
                                        selected: item == _filter,
                                        onSelected: (_) {
                                          setState(() => _filter = item);
                                          ref
                                              .read(
                                                remotePatientListProvider
                                                    .notifier,
                                              )
                                              .refresh(status: item);
                                        },
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.isLoading && state.items.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!state.isLoading && state.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.error == null
                              ? 'No patients found.'
                              : 'Unable to load patient records.',
                        ),
                        if (state.error != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => ref
                                .read(remotePatientListProvider.notifier)
                                .refresh(status: _filter),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                sliver: SliverList.separated(
                  itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => index >= state.items.length
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : CloudPatientCard(patient: state.items[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CloudPatientCard extends ConsumerWidget {
  const CloudPatientCard({super.key, required this.patient});
  final RemotePatient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final canManageStatus = session?.can(Permissions.patientsEdit) == true;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('patient-card-${patient.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/animals/${patient.id}'),
        onLongPress: canManageStatus
            ? () async {
                await HapticFeedback.selectionClick();
                if (context.mounted) await _showStatusSheet(context, ref);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              AveraIdentityAvatar(
                key: Key('patient-avatar-${patient.id}'),
                name: patient.name,
                photoReference: patient.photoUrl,
                size: 48,
              ),
              const SizedBox(width: AveraSpacing.compactRowGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            patient.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: averaText(context).listItemTitle,
                          ),
                        ),
                        if (patient.status != 'Active') ...[
                          const SizedBox(width: 8),
                          _CloudPatientStatusBadge(status: patient.status),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      patient.hospitalNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: averaText(context).caption,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [patient.species, patient.breed, patient.sex]
                          .whereType<String>()
                          .where((item) => item.isNotEmpty)
                          .join(' | '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: averaText(context).listItemSubtitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${patient.ownerName} | ${patient.ownerPhone}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: averaText(context).caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showStatusSheet(BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Manage ${patient.name}',
                style: averaText(sheetContext).sectionTitle,
              ),
            ),
            for (final status in const ['Active', 'Deceased', 'Relocated'])
              if (status != patient.status)
                ListTile(
                  leading: Icon(
                    _statusIcon(status),
                    color: _patientStatusColor(sheetContext, status),
                  ),
                  title: Text(
                    _statusAction(status),
                    style: TextStyle(
                      color: _patientStatusColor(sheetContext, status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(_statusDescription(status)),
                  onTap: () => Navigator.of(sheetContext).pop(status),
                ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await _confirmStatus(context, ref, selected);
  }

  Future<void> _confirmStatus(
    BuildContext context,
    WidgetRef ref,
    String status,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_statusAction(status)}?'),
        content: Text(
          status == 'Active'
              ? '${patient.name} will return to the active patient list.'
              : 'The complete medical, billing, vaccination, and consultation history for ${patient.name} will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(remotePatientListProvider.notifier)
          .updateStatus(
            patientId: patient.id,
            status: status,
            reason: 'Changed from Registered Pets.',
          );
      await ref.read(remotePatientDirectoryProvider.notifier).refresh();
      ref
        ..invalidate(remotePatientMedicalFileProvider(patient.id))
        ..invalidate(remoteDashboardProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${patient.name} is now $status.')),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      final message = error is ApiException
          ? error.message
          : 'The patient status could not be updated. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  static String _statusAction(String status) => switch (status) {
    'Active' => 'Restore to Active',
    'Deceased' => 'Mark as Deceased',
    'Relocated' => 'Mark as Relocated',
    _ => 'Change status',
  };

  static String _statusDescription(String status) => switch (status) {
    'Active' => 'Return this patient to the active clinic list.',
    'Deceased' => 'Preserve the record in the Deceased folder.',
    'Relocated' => 'Preserve the record in the Relocated folder.',
    _ => 'Update the patient status.',
  };

  static IconData _statusIcon(String status) => switch (status) {
    'Active' => Icons.restore_rounded,
    'Deceased' => Icons.heart_broken_outlined,
    'Relocated' => Icons.location_on_outlined,
    _ => Icons.edit_outlined,
  };
}

class _CloudPatientStatusBadge extends StatelessWidget {
  const _CloudPatientStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _patientStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Text(
        status,
        style: averaText(
          context,
        ).caption.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

Color _patientStatusColor(BuildContext context, String status) {
  final semantic = Theme.of(context).extension<AppSemanticColors>()!;
  return switch (status.trim().toLowerCase()) {
    'active' => semantic.success,
    'deceased' => semantic.danger,
    'relocated' => semantic.warning,
    _ => semantic.info,
  };
}

class _OfflineRecordsNotice extends StatelessWidget {
  const _OfflineRecordsNotice();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.cloud_off_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Showing saved clinic records while the server reconnects.',
          style: averaText(context).caption,
        ),
      ),
    ],
  );
}
