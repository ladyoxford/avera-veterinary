import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/backend_configuration.dart';
import '../../../core/database/app_database.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/services/feature_gate_service.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/avera_ui.dart';
import '../widgets/remote_patient_selector.dart';

enum ClinicalOperationModule {
  surgery,
  prescriptions,
  imaging,
  documents,
  treatmentBoard;

  String get recordType => switch (this) {
    ClinicalOperationModule.surgery => ClinicalOperationTypes.surgery,
    ClinicalOperationModule.prescriptions =>
      ClinicalOperationTypes.prescription,
    ClinicalOperationModule.imaging => ClinicalOperationTypes.imaging,
    ClinicalOperationModule.documents => ClinicalOperationTypes.document,
    ClinicalOperationModule.treatmentBoard => ClinicalOperationTypes.treatment,
  };

  String get backendType => switch (this) {
    ClinicalOperationModule.surgery => 'Surgery',
    ClinicalOperationModule.prescriptions => 'Prescription',
    ClinicalOperationModule.imaging => 'Imaging',
    ClinicalOperationModule.documents => 'Document',
    ClinicalOperationModule.treatmentBoard => 'Treatment',
  };

  String get title => switch (this) {
    ClinicalOperationModule.surgery => 'Surgery',
    ClinicalOperationModule.prescriptions => 'Prescriptions',
    ClinicalOperationModule.imaging => 'Imaging',
    ClinicalOperationModule.documents => 'Medical Documents',
    ClinicalOperationModule.treatmentBoard => 'Treatment Board',
  };

  String get subtitle => switch (this) {
    ClinicalOperationModule.surgery =>
      'Scheduled and completed surgical cases.',
    ClinicalOperationModule.prescriptions =>
      'Active prescriptions ready to dispense.',
    ClinicalOperationModule.imaging =>
      'Diagnostic imaging requests and reports.',
    ClinicalOperationModule.documents =>
      'Clinical documents and patient attachments.',
    ClinicalOperationModule.treatmentBoard =>
      'Treatments due across active patients.',
  };

  String get addLabel => switch (this) {
    ClinicalOperationModule.surgery => 'Schedule Surgery',
    ClinicalOperationModule.prescriptions => 'New Prescription',
    ClinicalOperationModule.imaging => 'Request Imaging',
    ClinicalOperationModule.documents => 'Add Document',
    ClinicalOperationModule.treatmentBoard => 'Add Treatment',
  };

  String get primaryActionLabel => switch (this) {
    ClinicalOperationModule.prescriptions => 'Create Prescription',
    _ => addLabel,
  };

  IconData get icon => switch (this) {
    ClinicalOperationModule.surgery => Icons.medical_services_outlined,
    ClinicalOperationModule.prescriptions => Icons.medication_outlined,
    ClinicalOperationModule.imaging => Icons.image_search_outlined,
    ClinicalOperationModule.documents => Icons.description_outlined,
    ClinicalOperationModule.treatmentBoard => Icons.view_kanban_outlined,
  };

  AveraFeature get feature => switch (this) {
    ClinicalOperationModule.surgery => AveraFeature.surgery,
    ClinicalOperationModule.prescriptions => AveraFeature.prescriptions,
    ClinicalOperationModule.imaging => AveraFeature.imaging,
    ClinicalOperationModule.documents => AveraFeature.documents,
    ClinicalOperationModule.treatmentBoard => AveraFeature.treatmentBoard,
  };

  String get completionLabel => switch (this) {
    ClinicalOperationModule.surgery => 'Mark Completed',
    ClinicalOperationModule.prescriptions => 'Mark Dispensed',
    ClinicalOperationModule.imaging => 'Mark Reported',
    ClinicalOperationModule.documents => 'Mark Reviewed',
    ClinicalOperationModule.treatmentBoard => 'Mark Administered',
  };

  String get completionStatus => switch (this) {
    ClinicalOperationModule.surgery => 'Completed',
    ClinicalOperationModule.prescriptions => 'Dispensed',
    ClinicalOperationModule.imaging => 'Reported',
    ClinicalOperationModule.documents => 'Reviewed',
    ClinicalOperationModule.treatmentBoard => 'Administered',
  };

  String get viewPermission => switch (this) {
    ClinicalOperationModule.surgery => Permissions.surgeryView,
    ClinicalOperationModule.prescriptions => Permissions.prescriptionsView,
    ClinicalOperationModule.imaging => Permissions.imagingView,
    ClinicalOperationModule.documents => Permissions.documentsView,
    ClinicalOperationModule.treatmentBoard => Permissions.treatmentBoardView,
  };

  String get createPermission => switch (this) {
    ClinicalOperationModule.surgery => Permissions.surgeryCreate,
    ClinicalOperationModule.prescriptions => Permissions.prescriptionsCreate,
    ClinicalOperationModule.imaging => Permissions.imagingRequest,
    ClinicalOperationModule.documents => Permissions.documentsUpload,
    ClinicalOperationModule.treatmentBoard => Permissions.treatmentBoardCreate,
  };

  List<String> get dashboardStatuses => switch (this) {
    ClinicalOperationModule.prescriptions => const [
      'Draft',
      'Active',
      'Partially Dispensed',
      'Dispensed',
      'Expired',
      'Cancelled',
    ],
    ClinicalOperationModule.treatmentBoard => const [
      'Due',
      'Administered',
      'Delayed',
      'Withheld',
      'Missed',
      'Cancelled',
    ],
    ClinicalOperationModule.surgery => const [
      'Draft',
      'Scheduled',
      'Pre-operative',
      'In Progress',
      'Recovery',
      'Completed',
      'Cancelled',
    ],
    ClinicalOperationModule.imaging => const [
      'Draft',
      'Requested',
      'Scheduled',
      'In Progress',
      'Awaiting Report',
      'Reported',
      'Completed',
      'Cancelled',
    ],
    ClinicalOperationModule.documents => const [
      'Draft',
      'Available',
      'Reviewed',
      'Archived',
    ],
  };
}

class _ClinicalStatusAction {
  const _ClinicalStatusAction({
    required this.label,
    required this.status,
    required this.permission,
    required this.icon,
    required this.requiresReason,
  });

  final String label;
  final String status;
  final String permission;
  final IconData icon;
  final bool requiresReason;
}

class ClinicalOperationScreen extends ConsumerStatefulWidget {
  const ClinicalOperationScreen({
    super.key,
    required this.module,
    this.initialRecordId,
  });

  final ClinicalOperationModule module;
  final int? initialRecordId;

  @override
  ConsumerState<ClinicalOperationScreen> createState() =>
      _ClinicalOperationScreenState();
}

class _ClinicalOperationScreenState
    extends ConsumerState<ClinicalOperationScreen> {
  String _query = '';
  String _filter = 'All';
  bool _openedInitialRecord = false;
  Future<RemotePage<Map<String, dynamic>>>? _remoteRecords;

  @override
  void initState() {
    super.initState();
    if (BackendConfiguration.isBackendMode) {
      _reloadRemote();
    } else {
      Future<void>.microtask(
        () =>
            ref.read(clinicRepositoryProvider).seedClinicalOperationDemoData(),
      );
    }
  }

  void _reloadRemote() {
    _remoteRecords = ref
        .read(clinicalRemoteDataSourceProvider)
        .clinicalOperations(operationType: widget.module.backendType);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final canCreate = session?.can(widget.module.createPermission) == true;
    if (session != null && !session.can(widget.module.viewPermission)) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.module.title)),
        body: const _OperationState(
          icon: Icons.lock_outline_rounded,
          title: 'Clinical module unavailable',
          message: 'Your role does not permit access to this module.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.module.title)),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateSheet(session!),
              icon: const Icon(Icons.add_rounded),
              label: Text(widget.module.addLabel),
            )
          : null,
      body: BackendConfiguration.isBackendMode
          ? _remoteBody(canCreate)
          : StreamBuilder<List<ClinicOperationRecord>>(
              stream: ref
                  .read(clinicRepositoryProvider)
                  .watchClinicalOperationRecords(widget.module.recordType),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _OperationState(
                    icon: Icons.error_outline_rounded,
                    title:
                        'Unable to load ${widget.module.title.toLowerCase()}',
                    message: 'Please try again.',
                    action: FilledButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                _openInitialRecord(snapshot.data!, session);
                final records = snapshot.data!.where(_matches).toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AveraSpacing.pageHorizontalPadding,
                    AveraSpacing.pageTopPadding,
                    AveraSpacing.pageHorizontalPadding,
                    AveraSpacing.bottomContentClearance,
                  ),
                  children: [
                    Text(
                      widget.module.subtitle,
                      style: Theme.of(
                        context,
                      ).extension<AveraTextStyles>()!.pageSubtitle,
                    ),
                    const SizedBox(height: AveraSpacing.subtitleToContentGap),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search patient, owner, or record',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: AveraSpacing.compactRowGap),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', ...widget.module.dashboardStatuses]
                            .map(
                              (status) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(status),
                                  selected: _filter == status,
                                  onSelected: (_) =>
                                      setState(() => _filter = status),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: AveraSpacing.cardGap),
                    if (records.isEmpty)
                      _OperationState(
                        icon: widget.module.icon,
                        title: 'No matching records',
                        message: canCreate
                            ? 'Create a patient-linked ${widget.module.title.toLowerCase()} record to begin.'
                            : 'No records match the selected filters.',
                      ),
                    for (final record in records) ...[
                      _OperationRecordCard(
                        record: record,
                        module: widget.module,
                        onTap: () => _openDetails(record, session),
                      ),
                      const SizedBox(height: AveraSpacing.cardGap),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _remoteBody(
    bool canCreate,
  ) => FutureBuilder<RemotePage<Map<String, dynamic>>>(
    future: _remoteRecords,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _OperationState(
          icon: Icons.error_outline_rounded,
          title: 'Unable to load ${widget.module.title.toLowerCase()}',
          message: 'The clinic records could not be loaded.',
          action: FilledButton(
            onPressed: () => setState(_reloadRemote),
            child: const Text('Retry'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final query = _query.trim().toLowerCase();
      final records = snapshot.data!.items
          .where((record) {
            if (_filter != 'All' && record['status'] != _filter) return false;
            if (query.isEmpty) return true;
            return [
              record['title'],
              record['description'],
              record['patient_name'],
              record['hospital_number'],
              record['owner_name'],
            ].whereType<Object>().join(' ').toLowerCase().contains(query);
          })
          .toList(growable: false);
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          Text(widget.module.subtitle, style: averaText(context).pageSubtitle),
          const SizedBox(height: AveraSpacing.subtitleToContentGap),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search patient, owner, or record',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: AveraSpacing.compactRowGap),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', ...widget.module.dashboardStatuses]
                  .map(
                    (status) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(status),
                        selected: _filter == status,
                        onSelected: (_) => setState(() => _filter = status),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          if (records.isEmpty)
            _OperationState(
              icon: widget.module.icon,
              title: 'No matching records',
              message: canCreate
                  ? 'Create a patient-linked ${widget.module.title.toLowerCase()} record to begin.'
                  : 'No records match the selected filters.',
            ),
          for (final record in records) ...[
            AveraSurfaceCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(widget.module.icon),
                title: Text(
                  '${record['title']}',
                  style: averaText(context).listItemTitle,
                ),
                subtitle: Text(
                  '${record['patient_name']} - ${record['hospital_number']}\n${record['owner_name'] ?? ''}',
                  style: averaText(context).listItemSubtitle,
                ),
                isThreeLine: true,
                trailing: _StatusPill('${record['status']}'),
                onTap: () => _showRemoteDetails(record),
              ),
            ),
            const SizedBox(height: AveraSpacing.cardGap),
          ],
        ],
      );
    },
  );

  Future<void> _showRemoteDetails(Map<String, dynamic> record) =>
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(AveraSpacing.largeCardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record['title']}',
                style: averaText(context).sectionTitle,
              ),
              const SizedBox(height: 6),
              Text(
                '${record['patient_name']} - ${record['hospital_number']}',
                style: averaText(context).listItemSubtitle,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              Text(
                '${record['description'] ?? 'No additional clinical notes.'}',
                style: averaText(context).fieldValue,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              _StatusPill('${record['status']}'),
            ],
          ),
        ),
      );

  void _openInitialRecord(
    List<ClinicOperationRecord> records,
    UserSession? session,
  ) {
    if (_openedInitialRecord || widget.initialRecordId == null) return;
    _openedInitialRecord = true;
    final record = records
        .where((item) => item.operation.id == widget.initialRecordId)
        .firstOrNull;
    if (record != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openDetails(record, session),
      );
    }
  }

  bool _matches(ClinicOperationRecord record) {
    if (_filter != 'All' && record.operation.status != _filter) return false;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      record.operation.title,
      record.operation.description,
      record.operation.status,
      record.animal.animalName,
      record.animal.hospitalNumber,
      record.owner.fullName,
    ].whereType<String>().join(' ').toLowerCase().contains(query);
  }

  Future<void> _openDetails(
    ClinicOperationRecord record,
    UserSession? session,
  ) async {
    if (session == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _ClinicalOperationDetailSheet(
        operationId: record.operation.id,
        module: widget.module,
        session: session,
      ),
    );
  }

  Future<void> _openCreateSheet(UserSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AveraSpacing.cardRadius),
        ),
      ),
      builder: (sheetContext) =>
          ClinicalOperationFormSheet(module: widget.module, session: session),
    );
    if (mounted && BackendConfiguration.isBackendMode) {
      setState(_reloadRemote);
    }
  }
}

class _ClinicalOperationDetailSheet extends ConsumerStatefulWidget {
  const _ClinicalOperationDetailSheet({
    required this.operationId,
    required this.module,
    required this.session,
  });

  final int operationId;
  final ClinicalOperationModule module;
  final UserSession session;

  @override
  ConsumerState<_ClinicalOperationDetailSheet> createState() =>
      _ClinicalOperationDetailSheetState();
}

class _ClinicalOperationDetailSheetState
    extends ConsumerState<_ClinicalOperationDetailSheet> {
  late Future<ClinicalOperationDetail?> _detail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _detail = ref
        .read(clinicRepositoryProvider)
        .getClinicalOperationDetail(widget.session, widget.operationId);
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.88,
    minChildSize: 0.55,
    maxChildSize: 0.97,
    builder: (context, controller) => FutureBuilder<ClinicalOperationDetail?>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _OperationState(
            icon: Icons.error_outline_rounded,
            title: 'Unable to open this record',
            message: '${snapshot.error}'.replaceFirst('Bad state: ', ''),
            action: FilledButton(
              onPressed: () => setState(_reload),
              child: const Text('Retry'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final detail = snapshot.data;
        if (detail == null) {
          return const _OperationState(
            icon: Icons.search_off_rounded,
            title: 'Clinical record unavailable',
            message:
                'It may belong to another clinic or no longer be available.',
          );
        }
        final record = detail.record;
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    record.operation.title,
                    style: averaText(context).sectionTitle,
                  ),
                ),
                const SizedBox(width: 12),
                _StatusPill(record.operation.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${record.animal.animalName} - '
              '${record.animal.hospitalNumber}',
              style: averaText(context).listItemSubtitle,
            ),
            if (record.operation.referenceNumber != null)
              Text(
                record.operation.referenceNumber!,
                style: averaText(context).caption,
              ),
            const SizedBox(height: 20),
            AveraSurfaceCard(
              child: Column(
                children: [
                  _DetailLine('Owner', record.owner.fullName),
                  _DetailLine(
                    'Assigned to',
                    record.operation.assignedTo ?? 'Not assigned',
                  ),
                  _DetailLine('Priority', record.operation.priority),
                  _DetailLine(
                    'Scheduled',
                    record.operation.scheduledAt == null
                        ? 'Not scheduled'
                        : DateFormat.yMMMd().add_jm().format(
                            record.operation.scheduledAt!,
                          ),
                  ),
                  if (record.operation.estimatedAmount != null)
                    _DetailLine(
                      'Estimated',
                      '${widget.session.clinic.currency} '
                          '${record.operation.estimatedAmount!.toStringAsFixed(2)}',
                    ),
                ],
              ),
            ),
            if (record.operation.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 20),
              Text('Clinical Notes', style: averaText(context).sectionLabel),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                child: Text(
                  record.operation.description!,
                  style: averaText(context).fieldValue,
                ),
              ),
            ],
            if (detail.items.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                widget.module == ClinicalOperationModule.treatmentBoard
                    ? 'Treatment Items'
                    : 'Medication Items',
                style: averaText(context).sectionLabel,
              ),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < detail.items.length;
                      index++
                    ) ...[
                      _ClinicalItemRow(item: detail.items[index]),
                      if (index != detail.items.length - 1)
                        const Divider(height: 24),
                    ],
                  ],
                ),
              ),
            ],
            if (detail.documents.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Documents', style: averaText(context).sectionLabel),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                child: Column(
                  children: [
                    for (final document in detail.documents)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(document.fileName),
                        subtitle: Text(
                          '${document.category} - Version '
                          '${document.versionNumber}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (detail.actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Activity', style: averaText(context).sectionLabel),
              const SizedBox(height: 8),
              AveraSurfaceCard(
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < detail.actions.length;
                      index++
                    ) ...[
                      _ClinicalActionRow(action: detail.actions[index]),
                      if (index != detail.actions.length - 1)
                        const Divider(height: 24),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildActions(detail),
          ],
        );
      },
    ),
  );

  Widget _buildActions(ClinicalOperationDetail detail) {
    final record = detail.record.operation;
    final actions = _nextActions(
      record.status,
    ).where((action) => widget.session.can(action.permission)).toList();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (widget.module == ClinicalOperationModule.prescriptions &&
            detail.items.isNotEmpty &&
            widget.session.can(Permissions.prescriptionsDispense) &&
            !{'Dispensed', 'Cancelled', 'Expired'}.contains(record.status))
          FilledButton.icon(
            onPressed: _busy ? null : () => _dispense(detail),
            icon: const Icon(Icons.medication_liquid_outlined),
            label: const Text('Dispense'),
          ),
        if (widget.module == ClinicalOperationModule.treatmentBoard &&
            widget.session.can(Permissions.treatmentBoardAdminister) &&
            !{
              'Administered',
              'Cancelled',
              'Missed',
              'Withheld',
            }.contains(record.status))
          FilledButton.icon(
            onPressed: _busy ? null : () => _recordTreatment(detail),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Record Action'),
          ),
        if ({
              ClinicalOperationModule.documents,
              ClinicalOperationModule.imaging,
              ClinicalOperationModule.surgery,
            }.contains(widget.module) &&
            widget.session.can(Permissions.documentsUpload))
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _addDocument(detail),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Add Document'),
          ),
        for (final action in actions)
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _changeStatus(
                    status: action.status,
                    requiresReason: action.requiresReason,
                  ),
            icon: Icon(action.icon),
            label: Text(action.label),
          ),
      ],
    );
  }

  List<_ClinicalStatusAction> _nextActions(String status) {
    _ClinicalStatusAction action(
      String label,
      String next,
      String permission,
      IconData icon, {
      bool reason = false,
    }) => _ClinicalStatusAction(
      label: label,
      status: next,
      permission: permission,
      icon: icon,
      requiresReason: reason,
    );
    return switch (widget.module) {
      ClinicalOperationModule.prescriptions => switch (status) {
        'Draft' || 'Pending' => [
          action(
            'Activate',
            'Active',
            Permissions.prescriptionsActivate,
            Icons.play_circle_outline_rounded,
          ),
          action(
            'Cancel',
            'Cancelled',
            Permissions.prescriptionsCancel,
            Icons.cancel_outlined,
            reason: true,
          ),
        ],
        'Active' || 'Partially Dispensed' => [
          action(
            'Cancel',
            'Cancelled',
            Permissions.prescriptionsCancel,
            Icons.cancel_outlined,
            reason: true,
          ),
        ],
        _ => const [],
      },
      ClinicalOperationModule.treatmentBoard => switch (status) {
        'Pending' => [
          action(
            'Mark Due',
            'Due',
            Permissions.treatmentBoardCreate,
            Icons.schedule_rounded,
          ),
        ],
        'Delayed' => [
          action(
            'Return to Due',
            'Due',
            Permissions.treatmentBoardReopen,
            Icons.restore_rounded,
          ),
        ],
        _ => const [],
      },
      ClinicalOperationModule.surgery => switch (status) {
        'Draft' || 'Pending' => [
          action(
            'Schedule',
            'Scheduled',
            Permissions.surgeryEdit,
            Icons.event_available_outlined,
          ),
        ],
        'Scheduled' => [
          action(
            'Start Pre-operative',
            'Pre-operative',
            Permissions.surgeryManagePreop,
            Icons.fact_check_outlined,
          ),
        ],
        'Pre-operative' => [
          action(
            'Ready for Surgery',
            'Ready for Surgery',
            Permissions.surgeryManagePreop,
            Icons.check_circle_outline_rounded,
          ),
        ],
        'Ready for Surgery' => [
          action(
            'Begin Surgery',
            'In Progress',
            Permissions.surgeryManageIntraop,
            Icons.medical_services_outlined,
          ),
        ],
        'In Progress' => [
          action(
            'Move to Recovery',
            'Recovery',
            Permissions.surgeryManageRecovery,
            Icons.monitor_heart_outlined,
          ),
        ],
        'Recovery' => [
          action(
            'Complete',
            'Completed',
            Permissions.surgeryComplete,
            Icons.task_alt_rounded,
          ),
        ],
        _ => const [],
      },
      ClinicalOperationModule.imaging => switch (status) {
        'Draft' || 'Pending' => [
          action(
            'Submit Request',
            'Requested',
            Permissions.imagingRequest,
            Icons.send_outlined,
          ),
        ],
        'Requested' => [
          action(
            'Schedule',
            'Scheduled',
            Permissions.imagingSchedule,
            Icons.event_available_outlined,
          ),
          action(
            'Start Study',
            'In Progress',
            Permissions.imagingUpload,
            Icons.play_circle_outline_rounded,
          ),
        ],
        'Scheduled' => [
          action(
            'Start Study',
            'In Progress',
            Permissions.imagingUpload,
            Icons.play_circle_outline_rounded,
          ),
        ],
        'In Progress' => [
          action(
            'Await Report',
            'Awaiting Report',
            Permissions.imagingReport,
            Icons.rate_review_outlined,
          ),
        ],
        'Awaiting Report' => [
          action(
            'Mark Reported',
            'Reported',
            Permissions.imagingReport,
            Icons.description_outlined,
          ),
        ],
        'Reported' => [
          action(
            'Complete',
            'Completed',
            Permissions.imagingComplete,
            Icons.task_alt_rounded,
          ),
        ],
        _ => const [],
      },
      ClinicalOperationModule.documents => switch (status) {
        'Draft' || 'Pending' => [
          action(
            'Make Available',
            'Available',
            Permissions.documentsEdit,
            Icons.visibility_outlined,
          ),
        ],
        'Available' => [
          action(
            'Mark Reviewed',
            'Reviewed',
            Permissions.documentsEdit,
            Icons.task_alt_rounded,
          ),
          action(
            'Archive',
            'Archived',
            Permissions.documentsArchive,
            Icons.archive_outlined,
          ),
        ],
        'Reviewed' => [
          action(
            'Archive',
            'Archived',
            Permissions.documentsArchive,
            Icons.archive_outlined,
          ),
        ],
        'Archived' => [
          action(
            'Restore',
            'Available',
            Permissions.documentsArchive,
            Icons.restore_rounded,
          ),
        ],
        _ => const [],
      },
    };
  }

  Future<void> _changeStatus({
    required String status,
    required bool requiresReason,
  }) async {
    String? reason;
    if (requiresReason) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Mark as $status?'),
          content: AveraLabeledTextField(
            label: 'Reason',
            controller: controller,
            hintText: 'Enter the reason for this status change',
            minLines: 2,
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    }
    await _run(
      () => ref
          .read(clinicRepositoryProvider)
          .updateClinicalOperationStatus(
            session: widget.session,
            operationId: widget.operationId,
            status: status,
            reason: reason,
          ),
      '$status recorded.',
    );
  }

  Future<void> _dispense(ClinicalOperationDetail detail) async {
    final available = detail.items
        .where(
          (item) => (item.prescribedQuantity ?? 0) > item.completedQuantity,
        )
        .toList();
    if (available.isEmpty) {
      _message('All prescription items have been dispensed.');
      return;
    }
    var selected = available.first;
    final quantity = TextEditingController(
      text: ((selected.prescribedQuantity ?? 0) - selected.completedQuantity)
          .toStringAsFixed(0),
    );
    final result = await showDialog<(int, double)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dispense Medication'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AveraLabeledDropdownField<int>(
                label: 'Medication',
                hintText: 'Select medication',
                value: selected.id,
                items: [
                  for (final item in available)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  setDialogState(() {
                    selected = available.firstWhere((item) => item.id == id);
                    quantity.text =
                        ((selected.prescribedQuantity ?? 0) -
                                selected.completedQuantity)
                            .toStringAsFixed(0);
                  });
                },
              ),
              const SizedBox(height: 16),
              AveraLabeledTextField(
                label: 'Quantity (${selected.unit ?? 'units'})',
                controller: quantity,
                hintText: 'Enter quantity dispensed',
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(quantity.text);
                if (parsed != null && parsed > 0) {
                  Navigator.pop(dialogContext, (selected.id, parsed));
                }
              },
              child: const Text('Dispense'),
            ),
          ],
        ),
      ),
    );
    quantity.dispose();
    if (result == null) return;
    await _run(
      () => ref
          .read(clinicRepositoryProvider)
          .dispensePrescriptionItem(
            session: widget.session,
            operationId: widget.operationId,
            operationItemId: result.$1,
            quantity: result.$2,
          ),
      'Dispensing recorded. Inventory and billing were updated.',
    );
  }

  Future<void> _recordTreatment(ClinicalOperationDetail detail) async {
    var status = 'Administered';
    final reason = TextEditingController();
    final dose = TextEditingController(text: '1');
    final response = TextEditingController();
    ClinicalOperationItem? selected = detail.items.isEmpty
        ? null
        : detail.items.first;
    final result =
        await showDialog<
          ({
            String status,
            String reason,
            double dose,
            String response,
            int? itemId,
          })
        >(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Record Treatment Action'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AveraLabeledDropdownField<String>(
                      label: 'Action',
                      hintText: 'Select treatment action',
                      value: status,
                      items: const [
                        DropdownMenuItem(
                          value: 'Administered',
                          child: Text('Administered'),
                        ),
                        DropdownMenuItem(
                          value: 'Delayed',
                          child: Text('Delayed'),
                        ),
                        DropdownMenuItem(
                          value: 'Withheld',
                          child: Text('Withheld'),
                        ),
                        DropdownMenuItem(
                          value: 'Missed',
                          child: Text('Missed'),
                        ),
                        DropdownMenuItem(
                          value: 'Cancelled',
                          child: Text('Cancelled'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => status = value ?? status),
                    ),
                    if (detail.items.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      AveraLabeledDropdownField<int>(
                        label: 'Treatment Item',
                        hintText: 'Select treatment item',
                        value: selected?.id,
                        items: [
                          for (final item in detail.items)
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) => setDialogState(
                          () => selected = detail.items
                              .where((item) => item.id == id)
                              .firstOrNull,
                        ),
                      ),
                    ],
                    if (status == 'Administered') ...[
                      const SizedBox(height: 16),
                      AveraLabeledTextField(
                        label: 'Actual Quantity Used',
                        controller: dose,
                        hintText: 'Enter quantity administered',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AveraLabeledTextField(
                        label: 'Patient Response',
                        controller: response,
                        hintText: 'Record the patient response',
                        minLines: 2,
                        maxLines: 4,
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      AveraLabeledTextField(
                        label: 'Reason',
                        controller: reason,
                        hintText: 'Enter the reason for this action',
                        minLines: 2,
                        maxLines: 4,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final parsed = double.tryParse(dose.text) ?? 1;
                    if (status != 'Administered' &&
                        reason.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.pop(dialogContext, (
                      status: status,
                      reason: reason.text.trim(),
                      dose: parsed,
                      response: response.text.trim(),
                      itemId: selected?.id,
                    ));
                  },
                  child: const Text('Record'),
                ),
              ],
            ),
          ),
        );
    reason.dispose();
    dose.dispose();
    response.dispose();
    if (result == null) return;
    await _run(
      () => ref
          .read(clinicRepositoryProvider)
          .recordTreatmentAction(
            session: widget.session,
            operationId: widget.operationId,
            operationItemId: result.itemId,
            status: result.status,
            actualDose: result.dose,
            reason: result.reason,
            patientResponse: result.response,
          ),
      'Treatment action recorded.',
    );
  }

  Future<void> _addDocument(ClinicalOperationDetail detail) async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    final file = picked?.files.singleOrNull;
    if (file == null || file.path == null) return;
    await _run(
      () => ref
          .read(clinicRepositoryProvider)
          .addClinicalDocumentVersion(
            session: widget.session,
            operationId: widget.operationId,
            category: widget.module.title,
            fileName: file.name,
            storagePath: file.path!,
            fileSize: file.size,
            mimeType: file.extension,
          ),
      'Document attached to the clinical record.',
    );
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reload();
      });
      _message(message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _message('$error');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value.replaceFirst('Bad state: ', ''))),
    );
  }
}

class _ClinicalItemRow extends StatelessWidget {
  const _ClinicalItemRow({required this.item});

  final ClinicalOperationItem item;

  @override
  Widget build(BuildContext context) {
    final prescribed = item.prescribedQuantity;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.medication_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: averaText(context).listItemTitle),
              if (item.strength != null)
                Text(item.strength!, style: averaText(context).caption),
              Text(
                [
                      item.dose,
                      item.doseUnit,
                      item.route,
                      item.frequency,
                      item.duration,
                    ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' - '),
                style: averaText(context).listItemSubtitle,
              ),
              if (prescribed != null)
                Text(
                  '${item.completedQuantity.toStringAsFixed(0)} of '
                  '${prescribed.toStringAsFixed(0)} '
                  '${item.unit ?? 'units'} completed',
                  style: averaText(context).caption,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _StatusPill(item.status),
      ],
    );
  }
}

class _ClinicalActionRow extends StatelessWidget {
  const _ClinicalActionRow({required this.action});

  final ClinicalOperationAction action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.history_rounded),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.newStatus ?? action.action,
              style: averaText(
                context,
              ).fieldValue.copyWith(fontWeight: FontWeight.w700),
            ),
            if (action.reason != null)
              Text(action.reason!, style: averaText(context).listItemSubtitle),
            Text(
              DateFormat.yMMMd().add_jm().format(action.occurredAt),
              style: averaText(context).caption,
            ),
          ],
        ),
      ),
    ],
  );
}

class _OperationRecordCard extends StatelessWidget {
  const _OperationRecordCard({
    required this.record,
    required this.module,
    required this.onTap,
  });
  final ClinicOperationRecord record;
  final ClinicalOperationModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(AveraSpacing.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(module.icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.operation.title,
                      style: averaText(context).listItemTitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.animal.animalName} - ${record.animal.hospitalNumber}',
                      style: averaText(context).listItemSubtitle,
                    ),
                    if (record.operation.description?.trim().isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 8),
                      Text(
                        record.operation.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: averaText(context).caption,
                      ),
                    ],
                    if (record.operation.scheduledAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        DateFormat.yMMMd().add_jm().format(
                          record.operation.scheduledAt!,
                        ),
                        style: averaText(context).caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusPill(record.operation.status),
                  const SizedBox(height: 12),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final success = {
      'Completed',
      'Dispensed',
      'Reported',
      'Reviewed',
      'Administered',
      'Available',
    };
    final color = success.contains(status)
        ? semantic.success
        : status == 'Due'
        ? semantic.warning
        : Theme.of(context).colorScheme.primary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 102),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: averaText(
          context,
        ).caption.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class ClinicalOperationFormSheet extends ConsumerStatefulWidget {
  const ClinicalOperationFormSheet({
    super.key,
    required this.module,
    required this.session,
  });
  final ClinicalOperationModule module;
  final UserSession session;

  @override
  ConsumerState<ClinicalOperationFormSheet> createState() =>
      _CreateClinicalOperationSheetState();
}

class _CreateClinicalOperationSheetState
    extends ConsumerState<ClinicalOperationFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _submissionId = const Uuid().v4();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _assignee = TextEditingController();
  final _amount = TextEditingController();
  final _indication = TextEditingController();
  final _assistant = TextEditingController();
  final _anaesthetist = TextEditingController();
  final _instructions = TextEditingController();
  final _clinicalHistory = TextEditingController();
  final _anatomicalArea = TextEditingController();
  final _suspectedDiagnosis = TextEditingController();
  final _provider = TextEditingController();
  final _relatedRecord = TextEditingController();
  final _orderedBy = TextEditingController();
  final _ward = TextEditingController();
  final _medicationName = TextEditingController();
  final _strength = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _dose = TextEditingController();
  final _doseUnit = TextEditingController();
  final _route = TextEditingController();
  final _frequency = TextEditingController();
  final _duration = TextEditingController();
  final _refills = TextEditingController(text: '0');
  int? _animalId;
  RemotePatient? _remotePatient;
  int? _inventoryItemId;
  String _priority = 'Routine';
  String _surgeryType = 'Elective';
  String _imagingType = 'Radiography';
  String _providerType = 'Internal';
  String _documentCategory = 'Clinical report';
  DateTime _scheduledAt = DateTime.now();
  String? _documentPath;
  String? _documentFileName;
  int? _documentFileSize;
  String? _documentMimeType;
  bool _sedationRequired = false;
  bool _sensitiveDocument = false;
  bool _highRisk = false;
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _assignee.dispose();
    _amount.dispose();
    _indication.dispose();
    _assistant.dispose();
    _anaesthetist.dispose();
    _instructions.dispose();
    _clinicalHistory.dispose();
    _anatomicalArea.dispose();
    _suspectedDiagnosis.dispose();
    _provider.dispose();
    _relatedRecord.dispose();
    _orderedBy.dispose();
    _ward.dispose();
    _medicationName.dispose();
    _strength.dispose();
    _quantity.dispose();
    _dose.dispose();
    _doseUnit.dispose();
    _route.dispose();
    _frequency.dispose();
    _duration.dispose();
    _refills.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty || _saving,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _saving) return;
      if (await _confirmDiscard() && context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .92,
        child: StreamBuilder<List<Animal>>(
          stream: ref.read(clinicRepositoryProvider).watchAnimals(),
          builder: (context, snapshot) {
            final animals = <int, Animal>{};
            for (final animal in snapshot.data ?? const <Animal>[]) {
              animals.putIfAbsent(animal.id, () => animal);
            }
            final orderedAnimals = animals.values.toList()
              ..sort((a, b) => a.hospitalNumber.compareTo(b.hospitalNumber));
            return StreamBuilder<List<InventoryItem>>(
              stream: ref
                  .read(clinicRepositoryProvider)
                  .watchPermittedInventory(widget.session),
              builder: (context, inventorySnapshot) {
                final inventory =
                    inventorySnapshot.data ?? const <InventoryItem>[];
                return Form(
                  key: _formKey,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      AveraSpacing.pageHorizontalPadding,
                      8,
                      AveraSpacing.pageHorizontalPadding,
                      AveraSpacing.subtitleToContentGap +
                          MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: AveraSpacing.cardGap),
                      AveraPageHeader(
                        title: widget.module.addLabel,
                        subtitle: _formSubtitle,
                      ),
                      const SizedBox(height: AveraSpacing.subtitleToContentGap),
                      if (BackendConfiguration.isBackendMode)
                        _remotePatientField()
                      else
                        AveraLabeledDropdownField<int>(
                          label: 'Patient',
                          hintText: 'Select a patient',
                          value: animals.containsKey(_animalId)
                              ? _animalId
                              : null,
                          items: [
                            for (final animal in orderedAnimals)
                              DropdownMenuItem(
                                value: animal.id,
                                child: Text(
                                  '${animal.animalName} - ${animal.hospitalNumber}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => _update(() => _animalId = value),
                          validator: (value) =>
                              value == null ? 'Select a patient.' : null,
                        ),
                      const SizedBox(height: AveraSpacing.cardGap),
                      ..._moduleFields(inventory),
                      const SizedBox(height: AveraSpacing.subtitleToContentGap),
                      AveraPrimaryActionButton(
                        label: widget.module.primaryActionLabel,
                        icon: _primaryIcon,
                        loading: _saving,
                        onPressed:
                            _saving ||
                                (widget.module ==
                                        ClinicalOperationModule.documents &&
                                    !_documentReady)
                            ? null
                            : () => _save(context),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
  );

  String get _formSubtitle => switch (widget.module) {
    ClinicalOperationModule.surgery =>
      'Plan the procedure, clinical team, and theatre timing.',
    ClinicalOperationModule.prescriptions =>
      'Create a safe, inventory-linked medication order.',
    ClinicalOperationModule.imaging =>
      'Request a diagnostic study with complete clinical context.',
    ClinicalOperationModule.documents =>
      'Attach a versioned document to the patient medical file.',
    ClinicalOperationModule.treatmentBoard =>
      'Add a due treatment task for the clinical team.',
  };

  IconData get _primaryIcon => switch (widget.module) {
    ClinicalOperationModule.surgery => Icons.event_available_rounded,
    ClinicalOperationModule.prescriptions => Icons.medication_rounded,
    ClinicalOperationModule.imaging => Icons.image_search_rounded,
    ClinicalOperationModule.documents => Icons.upload_file_rounded,
    ClinicalOperationModule.treatmentBoard => Icons.add_task_rounded,
  };

  bool get _documentReady =>
      (BackendConfiguration.isBackendMode
          ? _remotePatient != null
          : _animalId != null) &&
      _title.text.trim().isNotEmpty &&
      _documentCategory.isNotEmpty &&
      _documentPath != null;

  Widget _remotePatientField() => FormField<String>(
    initialValue: _remotePatient?.id,
    validator: (_) => _remotePatient == null ? 'Select a patient.' : null,
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AveraLabeledFieldCard(
          label: 'Patient',
          child: InkWell(
            onTap: _saving ? null : () => _selectRemotePatient(field),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AveraSpacing.minimumTapTarget,
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded),
                  const SizedBox(width: AveraSpacing.compactRowGap),
                  Expanded(
                    child: Text(
                      _remotePatient == null
                          ? 'Select a registered patient'
                          : '${_remotePatient!.name} - ${_remotePatient!.hospitalNumber}',
                      style: _remotePatient == null
                          ? averaText(context).fieldPlaceholder
                          : averaText(context).fieldValue,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
        if (field.errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            field.errorText!,
            style: averaText(
              context,
            ).caption.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );

  Future<void> _selectRemotePatient(FormFieldState<String> field) async {
    final selected = await showModalBottomSheet<RemotePatient>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: RemotePatientSelectorSheet(selectedId: _remotePatient?.id),
      ),
    );
    if (selected == null || !mounted) return;
    _update(() => _remotePatient = selected);
    field.didChange(selected.id);
  }

  List<Widget> _moduleFields(List<InventoryItem> inventory) =>
      switch (widget.module) {
        ClinicalOperationModule.surgery => _surgeryFields(),
        ClinicalOperationModule.prescriptions => _prescriptionFields(inventory),
        ClinicalOperationModule.imaging => _imagingFields(),
        ClinicalOperationModule.documents => _documentFields(),
        ClinicalOperationModule.treatmentBoard => _treatmentFields(inventory),
      };

  List<Widget> _surgeryFields() => _spaced([
    _text(
      label: 'Procedure',
      controller: _title,
      hint: 'Enter the planned surgical procedure',
      requiredMessage: 'Enter a procedure.',
    ),
    _text(
      label: 'Indication or diagnosis',
      controller: _indication,
      hint: 'Enter the clinical indication',
      requiredMessage: 'Enter the indication or diagnosis.',
    ),
    _text(
      label: 'Clinical notes',
      controller: _description,
      hint: 'Enter relevant clinical notes',
      multiline: true,
    ),
    _text(
      label: 'Assigned surgeon',
      controller: _assignee,
      hint: 'Enter or select the surgeon',
      requiredMessage: 'Enter the assigned surgeon.',
    ),
    _text(
      label: 'Assistant (optional)',
      controller: _assistant,
      hint: 'Enter the surgical assistant',
    ),
    _text(
      label: 'Anaesthetist (optional)',
      controller: _anaesthetist,
      hint: 'Enter the anaesthetist',
    ),
    _dateField('Surgery date'),
    _timeField('Surgery time'),
    _choice(
      label: 'Surgery type',
      value: _surgeryType,
      values: const ['Elective', 'Emergency'],
      onChanged: (value) => _update(() => _surgeryType = value!),
    ),
    _priorityField(),
    _amountField(),
    _text(
      label: 'Pre-operative instructions',
      controller: _instructions,
      hint: 'Enter fasting, medication, or preparation instructions',
      multiline: true,
    ),
  ]);

  List<Widget> _prescriptionFields(List<InventoryItem> inventory) => _spaced([
    _text(
      label: 'Clinical indication',
      controller: _title,
      hint: 'Enter the diagnosis or reason for prescribing',
      requiredMessage: 'Enter the clinical indication.',
    ),
    _text(
      label: 'Clinical notes',
      controller: _description,
      hint: 'Enter relevant clinical notes',
      multiline: true,
    ),
    _text(
      label: 'Prescribing clinician',
      controller: _assignee,
      hint: 'Enter the prescribing clinician',
      requiredMessage: 'Enter the prescribing clinician.',
    ),
    _inventoryField(inventory),
    _medicationNameField(),
    _responsivePair(
      _text(label: 'Strength', controller: _strength, hint: 'e.g. 250 mg'),
      _quantityField(),
    ),
    _text(label: 'Dose', controller: _dose, hint: 'e.g. 1 tablet'),
    _text(label: 'Route', controller: _route, hint: 'e.g. Oral'),
    _text(label: 'Frequency', controller: _frequency, hint: 'e.g. Twice daily'),
    _text(label: 'Duration', controller: _duration, hint: 'e.g. 7 days'),
    _text(
      label: 'Instructions',
      controller: _instructions,
      hint: 'Enter dispensing and administration instructions',
      multiline: true,
    ),
    _dateField('Start date'),
    _text(
      label: 'Refill allowance',
      controller: _refills,
      hint: 'Number of refills',
      number: true,
    ),
  ]);

  List<Widget> _imagingFields() => _spaced([
    _choice(
      label: 'Imaging type',
      value: _imagingType,
      values: const [
        'Radiography',
        'Ultrasound',
        'CT',
        'MRI',
        'Endoscopy',
        'Other',
      ],
      onChanged: (value) => _update(() => _imagingType = value!),
    ),
    _text(
      label: 'Study requested',
      controller: _title,
      hint: 'Enter the requested study',
      requiredMessage: 'Enter the requested study.',
    ),
    _text(
      label: 'Anatomical area',
      controller: _anatomicalArea,
      hint: 'Enter the body region or view',
      requiredMessage: 'Enter the anatomical area.',
    ),
    _text(
      label: 'Clinical history',
      controller: _clinicalHistory,
      hint: 'Enter the relevant patient history',
      multiline: true,
    ),
    _text(
      label: 'Suspected diagnosis',
      controller: _suspectedDiagnosis,
      hint: 'Enter the suspected diagnosis',
    ),
    _text(
      label: 'Clinical notes',
      controller: _description,
      hint: 'Enter additional clinical notes',
      multiline: true,
    ),
    _text(
      label: 'Requesting clinician',
      controller: _assignee,
      hint: 'Enter the requesting clinician',
      requiredMessage: 'Enter the requesting clinician.',
    ),
    _choice(
      label: 'Provider type',
      value: _providerType,
      values: const ['Internal', 'External'],
      onChanged: (value) => _update(() => _providerType = value!),
    ),
    _text(
      label: 'Imaging provider',
      controller: _provider,
      hint: 'Enter the department or external provider',
    ),
    AveraLabeledSwitchField(
      label: 'Sedation',
      title: 'Sedation required',
      subtitle: 'Flag the request for sedation planning.',
      value: _sedationRequired,
      onChanged: _saving
          ? null
          : (value) => _update(() => _sedationRequired = value),
    ),
    _priorityField(),
    _dateField('Scheduled date'),
    _amountField(),
  ]);

  List<Widget> _documentFields() => _spaced([
    _text(
      label: 'Document title',
      controller: _title,
      hint: 'Enter a clear document title',
      requiredMessage: 'Enter the document title.',
    ),
    _choice(
      label: 'Document category',
      value: _documentCategory,
      values: const [
        'Clinical report',
        'Consent form',
        'Laboratory attachment',
        'Referral letter',
        'Discharge instruction',
        'Other',
      ],
      onChanged: (value) => _update(() => _documentCategory = value!),
    ),
    _text(
      label: 'Description',
      controller: _description,
      hint: 'Describe the document',
      multiline: true,
    ),
    _text(
      label: 'Related clinical record (optional)',
      controller: _relatedRecord,
      hint: 'Consultation, surgery, imaging, or invoice reference',
    ),
    _dateField('Document date'),
    AveraLabeledFieldCard(
      label: 'Document file',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _documentFileName ?? 'No document selected',
            style: _documentFileName == null
                ? averaText(context).fieldPlaceholder
                : averaText(context).fieldValue,
          ),
          const SizedBox(height: AveraSpacing.compactRowGap),
          Wrap(
            spacing: AveraSpacing.compactRowGap,
            runSpacing: AveraSpacing.compactRowGap,
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _pickDocument(false),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Upload File'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _pickDocument(true),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan Camera'),
              ),
            ],
          ),
        ],
      ),
    ),
    AveraLabeledSwitchField(
      label: 'Privacy',
      title: 'Sensitive document',
      subtitle: 'Restrict this attachment to authorised clinical users.',
      value: _sensitiveDocument,
      onChanged: _saving
          ? null
          : (value) => _update(() => _sensitiveDocument = value),
    ),
    _text(
      label: 'Clinical notes (optional)',
      controller: _instructions,
      hint: 'Add context for the clinical team',
      multiline: true,
    ),
  ]);

  List<Widget> _treatmentFields(List<InventoryItem> inventory) => _spaced([
    _text(
      label: 'Treatment task',
      controller: _title,
      hint: 'Enter the treatment task',
      requiredMessage: 'Enter the treatment task.',
    ),
    _text(
      label: 'Clinical notes',
      controller: _description,
      hint: 'Enter relevant clinical notes',
      multiline: true,
    ),
    _text(
      label: 'Ordered by',
      controller: _orderedBy,
      hint: 'Enter the ordering clinician',
      requiredMessage: 'Enter the ordering clinician.',
    ),
    _text(
      label: 'Assigned staff',
      controller: _assignee,
      hint: 'Enter the assigned team member',
    ),
    _inventoryField(inventory),
    _medicationNameField(),
    _responsivePair(
      _text(label: 'Strength', controller: _strength, hint: 'e.g. 50 mg/ml'),
      _quantityField(),
    ),
    _responsivePair(
      _text(label: 'Dose', controller: _dose, hint: 'Enter dose'),
      _text(label: 'Dose unit', controller: _doseUnit, hint: 'mg, ml, tablet'),
    ),
    _text(label: 'Route', controller: _route, hint: 'e.g. IV or Oral'),
    _text(
      label: 'Frequency',
      controller: _frequency,
      hint: 'e.g. Every 12 hours',
    ),
    _dateField('Start date'),
    _timeField('Start time'),
    _text(label: 'Duration', controller: _duration, hint: 'e.g. 5 days'),
    _text(
      label: 'Ward or location',
      controller: _ward,
      hint: 'Enter the treatment location',
    ),
    _priorityField(),
    AveraLabeledSwitchField(
      label: 'Medication safety',
      title: 'High-risk medication',
      subtitle: 'Requires an independent second check before use.',
      value: _highRisk,
      onChanged: _saving ? null : (value) => _update(() => _highRisk = value),
    ),
    _text(
      label: 'Instructions',
      controller: _instructions,
      hint: 'Enter administration instructions',
      multiline: true,
    ),
  ]);

  List<Widget> _spaced(List<Widget> fields) => [
    for (var index = 0; index < fields.length; index++) ...[
      fields[index],
      if (index != fields.length - 1)
        const SizedBox(height: AveraSpacing.cardGap),
    ],
  ];

  Widget _text({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? requiredMessage,
    bool multiline = false,
    bool number = false,
  }) => AveraLabeledTextField(
    label: label,
    controller: controller,
    hintText: hint,
    enabled: !_saving,
    minLines: multiline ? 3 : 1,
    maxLines: multiline ? 6 : 1,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : multiline
        ? TextInputType.multiline
        : TextInputType.text,
    textInputAction: multiline ? TextInputAction.newline : TextInputAction.next,
    onChanged: (_) => _markDirty(),
    validator: requiredMessage == null
        ? null
        : (value) =>
              value == null || value.trim().isEmpty ? requiredMessage : null,
  );

  Widget _choice({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) => AveraLabeledDropdownField<String>(
    label: label,
    hintText: 'Select $label',
    value: value,
    items: [
      for (final option in values)
        DropdownMenuItem(value: option, child: Text(option)),
    ],
    onChanged: _saving ? null : onChanged,
  );

  Widget _inventoryField(List<InventoryItem> inventory) =>
      AveraLabeledDropdownField<int>(
        label: 'Inventory medication',
        hintText: 'Select an inventory medication',
        value: inventory.any((item) => item.id == _inventoryItemId)
            ? _inventoryItemId
            : null,
        helperText: 'Required for stock deduction and billing.',
        items: [
          for (final item in inventory.where(
            (item) => !item.isArchived && item.isSellable,
          ))
            DropdownMenuItem(
              value: item.id,
              child: Text(
                '${item.drugName} (${item.quantity} available)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _saving
            ? null
            : (value) {
                _update(() {
                  _inventoryItemId = value;
                  final item = inventory
                      .where((row) => row.id == value)
                      .firstOrNull;
                  if (item != null) _medicationName.text = item.drugName;
                });
              },
      );

  Widget _medicationNameField() => _text(
    label: 'Medication or treatment name',
    controller: _medicationName,
    hint: 'Enter the medication or treatment',
    requiredMessage: 'Enter a medication or treatment.',
  );

  Widget _quantityField() => _text(
    label: 'Quantity',
    controller: _quantity,
    hint: 'Enter quantity',
    number: true,
    requiredMessage: 'Enter quantity.',
  );

  Widget _priorityField() => _choice(
    label: 'Priority',
    value: _priority,
    values: const ['Routine', 'Urgent', 'Emergency'],
    onChanged: (value) => _update(() => _priority = value!),
  );

  Widget _amountField() => _text(
    label: 'Estimated amount (${widget.session.clinic.currency})',
    controller: _amount,
    hint: 'Enter estimated amount',
    number: true,
  );

  Widget _responsivePair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 520) {
        return Column(
          children: [
            first,
            const SizedBox(height: AveraSpacing.cardGap),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: AveraSpacing.cardGap),
          Expanded(child: second),
        ],
      );
    },
  );

  Widget _dateField(String label) => _pickerField(
    label: label,
    value: DateFormat.yMMMd().format(_scheduledAt),
    icon: Icons.calendar_today_outlined,
    onTap: _pickDate,
  );

  Widget _timeField(String label) => _pickerField(
    label: label,
    value: DateFormat.jm().format(_scheduledAt),
    icon: Icons.schedule_outlined,
    onTap: _pickTime,
  );

  Widget _pickerField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) => AveraLabeledFieldCard(
    label: label,
    child: InkWell(
      onTap: _saving ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AveraSpacing.minimumTapTarget,
        ),
        child: Row(
          children: [
            Expanded(child: Text(value, style: averaText(context).fieldValue)),
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    ),
  );

  void _update(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
    });
  }

  void _markDirty() {
    if (mounted) setState(() => _dirty = true);
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    _update(
      () => _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        _scheduledAt.hour,
        _scheduledAt.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null || !mounted) return;
    _update(
      () => _scheduledAt = DateTime(
        _scheduledAt.year,
        _scheduledAt.month,
        _scheduledAt.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _pickDocument(bool useCamera) async {
    if (useCamera) {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (image == null || !mounted) return;
      _update(() {
        _documentPath = image.path;
        _documentFileName = image.name;
        _documentMimeType = image.mimeType ?? 'image/jpeg';
      });
      _documentFileSize = await image.length();
      if (mounted) setState(() {});
      return;
    }
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    final file = result?.files.singleOrNull;
    if (file == null || file.path == null || !mounted) return;
    _update(() {
      _documentPath = file.path;
      _documentFileName = file.name;
      _documentFileSize = file.size;
      _documentMimeType = file.extension;
    });
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this form?'),
        content: const Text(
          'Your unsaved clinical operation details will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _save(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.module == ClinicalOperationModule.documents && !_documentReady) {
      return;
    }
    setState(() => _saving = true);
    try {
      if (BackendConfiguration.isBackendMode) {
        final patient = _remotePatient!;
        await ref
            .read(clinicalRemoteDataSourceProvider)
            .createClinicalOperation({
              'submissionId': _submissionId,
              'patientId': patient.id,
              'operationType': widget.module.backendType,
              'title': _title.text.trim(),
              'description': _description.text.trim(),
              'assignedTo': _assignee.text.trim(),
              'scheduledAt': _scheduledAt.toUtc().toIso8601String(),
              'status': switch (widget.module) {
                ClinicalOperationModule.prescriptions => 'Draft',
                ClinicalOperationModule.treatmentBoard => 'Due',
                ClinicalOperationModule.surgery => 'Scheduled',
                ClinicalOperationModule.imaging => 'Requested',
                ClinicalOperationModule.documents => 'Available',
              },
              'priority': _priority,
              'estimatedAmount': double.tryParse(_amount.text.trim()),
              'details': {
                'indication': _indication.text.trim(),
                'assistant': _assistant.text.trim(),
                'anaesthetist': _anaesthetist.text.trim(),
                'instructions': _instructions.text.trim(),
                'clinicalHistory': _clinicalHistory.text.trim(),
                'anatomicalArea': _anatomicalArea.text.trim(),
                'suspectedDiagnosis': _suspectedDiagnosis.text.trim(),
                'providerType': _providerType,
                'provider': _provider.text.trim(),
                'sedationRequired': _sedationRequired,
                'surgeryType': _surgeryType,
                'imagingType': _imagingType,
                'documentCategory': _documentCategory,
                'relatedClinicalRecord': _relatedRecord.text.trim(),
                'sensitiveDocument': _sensitiveDocument,
                'orderedBy': _orderedBy.text.trim(),
                'ward': _ward.text.trim(),
                'refillAllowance': int.tryParse(_refills.text.trim()) ?? 0,
                if (_documentFileName != null) 'fileName': _documentFileName,
                if (_documentFileSize != null) 'fileSize': _documentFileSize,
                if (_documentMimeType != null) 'mimeType': _documentMimeType,
              },
              'items':
                  {
                    ClinicalOperationModule.prescriptions,
                    ClinicalOperationModule.treatmentBoard,
                  }.contains(widget.module)
                  ? [
                      {
                        'name': _medicationName.text.trim(),
                        'strength': _strength.text.trim(),
                        'quantity': double.tryParse(_quantity.text.trim()),
                        'dose': _dose.text.trim(),
                        'doseUnit': _doseUnit.text.trim(),
                        'route': _route.text.trim(),
                        'frequency': _frequency.text.trim(),
                        'duration': _duration.text.trim(),
                        'instructions': _instructions.text.trim(),
                        'isHighRisk': _highRisk,
                      },
                    ]
                  : const <Map<String, dynamic>>[],
            });
        ref.invalidate(remotePatientMedicalFileProvider(patient.id));
        for (final section in _affectedRemoteSections) {
          ref.invalidate(
            remotePatientSectionProvider(
              RemotePatientSectionRequest(
                patientId: patient.id,
                section: section,
              ),
            ),
          );
        }
        if (!context.mounted) return;
        _dirty = false;
        Navigator.of(context).pop();
        return;
      }
      final operationId = await ref
          .read(clinicRepositoryProvider)
          .createClinicalOperation(
            session: widget.session,
            animalId: _animalId!,
            operationType: widget.module.recordType,
            title: _title.text,
            description: _description.text,
            assignedTo: _assignee.text,
            scheduledAt: _scheduledAt,
            status: switch (widget.module) {
              ClinicalOperationModule.prescriptions => 'Draft',
              ClinicalOperationModule.treatmentBoard => 'Due',
              ClinicalOperationModule.surgery => 'Scheduled',
              ClinicalOperationModule.imaging => 'Requested',
              ClinicalOperationModule.documents => 'Available',
            },
            priority: _priority,
            estimatedAmount: double.tryParse(_amount.text.trim()),
            details: {
              'createdFrom': widget.module.title,
              'structuredWorkflow': true,
              'indication': _indication.text.trim(),
              'assistant': _assistant.text.trim(),
              'anaesthetist': _anaesthetist.text.trim(),
              'instructions': _instructions.text.trim(),
              'clinicalHistory': _clinicalHistory.text.trim(),
              'anatomicalArea': _anatomicalArea.text.trim(),
              'suspectedDiagnosis': _suspectedDiagnosis.text.trim(),
              'providerType': _providerType,
              'provider': _provider.text.trim(),
              'sedationRequired': _sedationRequired,
              'surgeryType': _surgeryType,
              'imagingType': _imagingType,
              'documentCategory': _documentCategory,
              'relatedClinicalRecord': _relatedRecord.text.trim(),
              'documentDate': _scheduledAt.toIso8601String(),
              'sensitiveDocument': _sensitiveDocument,
              'orderedBy': _orderedBy.text.trim(),
              'ward': _ward.text.trim(),
              'refillAllowance': int.tryParse(_refills.text.trim()) ?? 0,
            },
            items:
                {
                  ClinicalOperationModule.prescriptions,
                  ClinicalOperationModule.treatmentBoard,
                }.contains(widget.module)
                ? [
                    ClinicalMedicationDraft(
                      name: _medicationName.text,
                      inventoryItemId: _inventoryItemId,
                      strength: _strength.text,
                      quantity: double.tryParse(_quantity.text),
                      unit: 'units',
                      dose: _dose.text,
                      doseUnit: _doseUnit.text,
                      route: _route.text,
                      frequency: _frequency.text,
                      duration: _duration.text,
                      instructions: _description.text,
                      isHighRisk: _highRisk,
                    ),
                  ]
                : const [],
          );
      if (widget.module == ClinicalOperationModule.documents) {
        await ref
            .read(clinicRepositoryProvider)
            .addClinicalDocumentVersion(
              session: widget.session,
              operationId: operationId,
              category: _documentCategory,
              fileName: _documentFileName!,
              storagePath: _documentPath!,
              fileSize: _documentFileSize,
              mimeType: _documentMimeType,
              isSensitive: _sensitiveDocument,
            );
      }
      if (!context.mounted) return;
      _dirty = false;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to save this clinical operation. Review the form and try again.',
          ),
        ),
      );
    }
  }

  List<String> get _affectedRemoteSections => switch (widget.module) {
    ClinicalOperationModule.surgery => const ['surgeries'],
    ClinicalOperationModule.prescriptions => const ['prescriptions'],
    ClinicalOperationModule.imaging => const ['images'],
    ClinicalOperationModule.documents => const ['documents'],
    ClinicalOperationModule.treatmentBoard => const <String>[],
  };
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: averaText(context).caption),
        ),
        Expanded(child: Text(value, style: averaText(context).fieldValue)),
      ],
    ),
  );
}

class _OperationState extends StatelessWidget {
  const _OperationState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        Text(
          title,
          style: averaText(context).sectionTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: averaText(context).sectionSubtitle,
          textAlign: TextAlign.center,
        ),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    ),
  );
}
