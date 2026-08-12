import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/avera_ui.dart';
import '../widgets/remote_patient_selector.dart';

const _appointmentTypes = <String>[
  'Consultation',
  'Vaccination',
  'Follow-up',
  'Laboratory',
  'Hospitalization review',
  'Surgery',
  'Grooming',
  'Other',
];

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (BackendConfiguration.isBackendMode) {
      return const _RemoteAppointmentsScreen();
    }
    final repository = ref.watch(clinicRepositoryProvider);
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      floatingActionButton: session?.can(Permissions.appointmentsCreate) == true
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/appointments/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Appointment'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<Appointment>>(
          stream: repository.watchAppointments(),
          builder: (context, appointmentSnapshot) => StreamBuilder<List<Animal>>(
            stream: repository.watchAnimals(),
            builder: (context, animalSnapshot) {
              final appointments =
                  appointmentSnapshot.data ?? const <Appointment>[];
              final animals = {
                for (final animal in animalSnapshot.data ?? const <Animal>[])
                  animal.id: animal,
              };
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AveraSpacing.pageHorizontalPadding,
                  AveraSpacing.pageTopPadding,
                  AveraSpacing.pageHorizontalPadding,
                  AveraSpacing.bottomContentClearance,
                ),
                children: [
                  const AveraPageHeader(
                    title: 'Schedule',
                    subtitle: 'Scheduled clinic visits',
                  ),
                  const SizedBox(height: AveraSpacing.subtitleToContentGap),
                  if (appointmentSnapshot.hasError)
                    _MessageCard(
                      icon: Icons.error_outline_rounded,
                      title: 'Schedule unavailable',
                      message:
                          'Try again. Your existing clinic data has not been changed.',
                    )
                  else if (appointments.isEmpty)
                    const _MessageCard(
                      icon: Icons.calendar_month_outlined,
                      title: 'No scheduled visits',
                      message:
                          'Create an appointment to begin planning the clinic day.',
                    )
                  else
                    AveraSurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < appointments.length;
                            index++
                          ) ...[
                            _ScheduleRow(
                              appointment: appointments[index],
                              patient: animals[appointments[index].animalId],
                              onTap: () => context.push(
                                '/appointments/${appointments[index].id}',
                              ),
                            ),
                            if (index != appointments.length - 1)
                              const Divider(height: 1, indent: 84),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RemoteAppointmentsScreen extends ConsumerWidget {
  const _RemoteAppointmentsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final schedule = ref.watch(remoteAppointmentScheduleProvider);
    return Scaffold(
      floatingActionButton: session?.can(Permissions.appointmentsCreate) == true
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/appointments/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Appointment'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.refresh(remoteAppointmentScheduleProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
            children: [
              const AveraPageHeader(
                title: 'Schedule',
                subtitle: 'Scheduled clinic visits',
              ),
              const SizedBox(height: 24),
              schedule.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const _MessageCard(
                  icon: Icons.cloud_off_outlined,
                  title: 'Schedule unavailable',
                  message:
                      'Pull down to retry. Cached appointments remain available when present.',
                ),
                data: (page) => page.items.isEmpty
                    ? const _MessageCard(
                        icon: Icons.calendar_month_outlined,
                        title: 'No scheduled visits',
                        message:
                            'Create an appointment to begin planning the clinic day.',
                      )
                    : AveraSurfaceCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < page.items.length;
                              index++
                            ) ...[
                              RemoteAppointmentScheduleRow(
                                appointment: page.items[index],
                                session: session,
                              ),
                              if (index != page.items.length - 1)
                                const Divider(height: 1, indent: 72),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _remoteAppointmentDate(Object? value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  return date == null
      ? 'Date unavailable'
      : DateFormat.yMMMd().add_jm().format(date);
}

@visibleForTesting
class RemoteAppointmentScheduleRow extends ConsumerWidget {
  const RemoteAppointmentScheduleRow({
    super.key,
    required this.appointment,
    required this.session,
  });

  final Map<String, dynamic> appointment;
  final UserSession? session;

  String? get _appointmentId =>
      appointment['schedule_entry_id']?.toString().trim();
  String? get _patientId => appointment['patient_id']?.toString().trim();
  bool get _hasPatient =>
      _patientId?.isNotEmpty == true &&
      appointment['patient_name']?.toString().trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointmentId = _appointmentId;
    return ListTile(
      minTileHeight: 76,
      leading: const Icon(Icons.calendar_month_rounded),
      title: Text(
        _hasPatient
            ? appointment['patient_name'].toString()
            : 'Patient record unavailable',
        style: averaText(context).listItemTitle,
      ),
      subtitle: Text(
        '${appointment['visit_type'] ?? 'Visit'} | ${_remoteAppointmentDate(appointment['scheduled_at'])}',
        style: averaText(context).listItemSubtitle,
      ),
      onTap: appointmentId?.isNotEmpty == true
          ? () => context.push('/appointments/$appointmentId')
          : null,
      onLongPress: appointmentId?.isNotEmpty == true
          ? () async {
              unawaited(HapticFeedback.selectionClick());
              await _showRemoteAppointmentActions(
                context,
                ref,
                appointment: appointment,
                session: session,
              );
            }
          : null,
    );
  }
}

class CloudAppointmentDetailScreen extends ConsumerWidget {
  const CloudAppointmentDetailScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(remoteAppointmentDetailProvider(appointmentId));
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Appointment')),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_busy_outlined, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Appointment unavailable',
                  style: averaText(context).sectionTitle,
                ),
                const SizedBox(height: 6),
                Text(
                  'This appointment could not be loaded for the active clinic.',
                  textAlign: TextAlign.center,
                  style: averaText(context).sectionSubtitle,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(
                    remoteAppointmentDetailProvider(appointmentId),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (detail) =>
            _RemoteAppointmentDetailBody(detail: detail, session: session),
      ),
    );
  }
}

class _RemoteAppointmentDetailBody extends ConsumerWidget {
  const _RemoteAppointmentDetailBody({
    required this.detail,
    required this.session,
  });

  final RemoteAppointmentDetail detail;
  final UserSession? session;

  bool get _isClosed => const {
    'cancelled',
    'completed',
  }.contains(detail.status.trim().toLowerCase());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canStart =
        !_isClosed &&
        detail.hasPatient &&
        session?.can(Permissions.appointmentsStartConsultation) == true;
    final canEdit =
        !_isClosed && session?.can(Permissions.appointmentsEdit) == true;
    final canCancel =
        !_isClosed && session?.can(Permissions.appointmentsCancel) == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AveraSpacing.pageHorizontalPadding,
        AveraSpacing.pageTopPadding,
        AveraSpacing.pageHorizontalPadding,
        AveraSpacing.bottomContentClearance,
      ),
      children: [
        _StatusChip(status: detail.status),
        const SizedBox(height: AveraSpacing.cardGap),
        _RemoteAppointmentPatientCard(detail: detail, session: session),
        const SizedBox(height: AveraSpacing.sectionGap),
        const AveraSectionHeader(title: 'Appointment Details'),
        const SizedBox(height: 12),
        AveraSurfaceCard(
          child: Column(
            children: [
              _KeyValueRow(
                label: 'Date',
                value: DateFormat.yMMMMd().format(detail.scheduledAt.toLocal()),
              ),
              _KeyValueRow(
                label: 'Time',
                value: DateFormat.jm().format(detail.scheduledAt.toLocal()),
              ),
              _KeyValueRow(label: 'Type', value: detail.visitType),
              _KeyValueRow(
                label: 'Assigned vet',
                value: detail.assignedStaffName ?? 'Not assigned',
              ),
              _KeyValueRow(
                label: 'Status',
                value: detail.status,
                showDivider: false,
              ),
            ],
          ),
        ),
        if (detail.notes?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AveraSpacing.sectionGap),
          const AveraSectionHeader(title: 'Notes'),
          const SizedBox(height: 12),
          AveraSurfaceCard(
            child: Text(
              detail.notes!.trim(),
              style: averaText(context).fieldValue,
            ),
          ),
        ],
        const SizedBox(height: AveraSpacing.sectionGap),
        const AveraSectionHeader(
          title: 'Reminders',
          subtitle: 'On-device notifications',
        ),
        const SizedBox(height: 12),
        AveraSurfaceCard(
          child: Center(
            child: Text(
              'No reminders enabled.',
              style: averaText(context).fieldPlaceholder,
            ),
          ),
        ),
        if (canStart || canEdit || canCancel) ...[
          const SizedBox(height: AveraSpacing.sectionGap),
          if (canStart)
            AveraPrimaryActionButton(
              label: 'Start Consultation',
              icon: Icons.medical_services_outlined,
              onPressed: () => _startRemoteConsultation(context, ref, detail),
            ),
          if (canStart && (canEdit || canCancel)) const SizedBox(height: 12),
          if (canEdit)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    _rescheduleRemoteAppointment(context, ref, detail),
                icon: const Icon(Icons.edit_calendar_rounded),
                label: const Text('Reschedule'),
              ),
            ),
          if (canEdit && canCancel) const SizedBox(height: 12),
          if (canCancel)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _cancelRemoteAppointment(context, ref, detail),
                icon: const Icon(Icons.event_busy_rounded),
                label: const Text('Cancel Visit'),
              ),
            ),
        ],
      ],
    );
  }
}

class _RemoteAppointmentPatientCard extends StatelessWidget {
  const _RemoteAppointmentPatientCard({
    required this.detail,
    required this.session,
  });

  final RemoteAppointmentDetail detail;
  final UserSession? session;

  @override
  Widget build(BuildContext context) {
    final patient = detail.patient;
    if (patient == null) {
      return const _MessageCard(
        icon: Icons.person_off_outlined,
        title: 'Patient record unavailable',
        message:
            'Appointment details remain available, but patient actions are disabled.',
      );
    }
    return AveraSurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: session?.can(Permissions.patientsView) == true
            ? () => context.push('/animals/${patient.id}')
            : null,
        child: Padding(
          padding: const EdgeInsets.all(AveraSpacing.cardPadding),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(patient.name.characters.first.toUpperCase()),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient.name, style: averaText(context).listItemTitle),
                    Text(
                      '${patient.species}${patient.breed?.trim().isNotEmpty == true ? ' / ${patient.breed}' : ''}${patient.sex?.trim().isNotEmpty == true ? ' / ${patient.sex}' : ''}',
                      style: averaText(context).listItemSubtitle,
                    ),
                    Text(
                      'Owner: ${patient.ownerName}',
                      style: averaText(context).listItemSubtitle,
                    ),
                    if (patient.ownerPhone.trim().isNotEmpty)
                      Text(
                        patient.ownerPhone,
                        style: averaText(context).caption,
                      ),
                    if (patient.hospitalNumber.trim().isNotEmpty)
                      Text(
                        patient.hospitalNumber,
                        style: averaText(context).caption,
                      ),
                  ],
                ),
              ),
              if (session?.can(Permissions.patientsView) == true)
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showRemoteAppointmentActions(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> appointment,
  required UserSession? session,
}) async {
  final appointmentId = appointment['schedule_entry_id']?.toString().trim();
  if (appointmentId == null || appointmentId.isEmpty) return;
  final patientAvailable =
      appointment['patient_id']?.toString().trim().isNotEmpty == true &&
      appointment['patient_name']?.toString().trim().isNotEmpty == true;
  final status = appointment['status']?.toString().trim().toLowerCase() ?? '';
  final open = status != 'cancelled' && status != 'completed';
  final canStart =
      open &&
      patientAvailable &&
      session?.can(Permissions.appointmentsStartConsultation) == true;
  final canEdit = open && session?.can(Permissions.appointmentsEdit) == true;
  final canCancel =
      open && session?.can(Permissions.appointmentsCancel) == true;
  final parentContext = context;

  Future<void> run(
    BuildContext sheetContext,
    Future<void> Function(RemoteAppointmentDetail) action,
  ) async {
    Navigator.of(sheetContext).pop();
    await Future<void>.delayed(Duration.zero);
    if (!parentContext.mounted) return;
    final detail = await _loadRemoteAppointment(
      parentContext,
      ref,
      appointmentId,
    );
    if (detail != null && parentContext.mounted) await action(detail);
  }

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appointment['patient_name']?.toString().trim().isNotEmpty == true
                ? appointment['patient_name'].toString()
                : 'Patient record unavailable',
            style: averaText(sheetContext).sectionTitle,
          ),
          const SizedBox(height: 4),
          Text(
            '${appointment['visit_type'] ?? 'Visit'} • ${_remoteAppointmentDate(appointment['scheduled_at'])}',
            style: averaText(sheetContext).sectionSubtitle,
          ),
          const SizedBox(height: 16),
          if (!patientAvailable)
            const _MessageCard(
              icon: Icons.person_off_outlined,
              title: 'Patient record unavailable',
              message: 'Patient-specific consultation actions are disabled.',
            ),
          if (canStart)
            ListTile(
              leading: const Icon(Icons.medical_services_outlined),
              title: const Text('Start New Consultation'),
              subtitle: const Text('Open a consultation for this patient.'),
              onTap: () => run(
                sheetContext,
                (detail) =>
                    _startRemoteConsultation(parentContext, ref, detail),
              ),
            ),
          if (canEdit)
            ListTile(
              leading: const Icon(Icons.edit_calendar_rounded),
              title: const Text('Reschedule'),
              subtitle: const Text('Update this appointment date or details.'),
              onTap: () => run(
                sheetContext,
                (detail) =>
                    _rescheduleRemoteAppointment(parentContext, ref, detail),
              ),
            ),
          if (canCancel)
            ListTile(
              iconColor: Theme.of(sheetContext).colorScheme.error,
              textColor: Theme.of(sheetContext).colorScheme.error,
              leading: const Icon(Icons.event_busy_rounded),
              title: const Text('Cancel Visit'),
              subtitle: const Text(
                'Cancel this appointment after confirmation.',
              ),
              onTap: () => run(
                sheetContext,
                (detail) =>
                    _cancelRemoteAppointment(parentContext, ref, detail),
              ),
            ),
          if (!canStart && !canEdit && !canCancel && patientAvailable)
            const _MessageCard(
              icon: Icons.lock_outline_rounded,
              title: 'No appointment actions available',
              message: 'Your clinic role does not allow changes to this visit.',
            ),
        ],
      ),
    ),
  );
}

Future<RemoteAppointmentDetail?> _loadRemoteAppointment(
  BuildContext context,
  WidgetRef ref,
  String appointmentId,
) async {
  try {
    return await ref.read(
      remoteAppointmentDetailProvider(appointmentId).future,
    );
  } catch (error) {
    if (context.mounted) {
      _showMessage(context, _appointmentActionErrorMessage(error));
    }
    return null;
  }
}

Future<void> _startRemoteConsultation(
  BuildContext context,
  WidgetRef ref,
  RemoteAppointmentDetail detail,
) async {
  final patient = detail.patient;
  if (patient == null) {
    _showMessage(
      context,
      'The patient record is unavailable, so a consultation cannot be started.',
    );
    return;
  }
  await context.push(
    '/consultations/new?patientId=${Uri.encodeQueryComponent(patient.id)}&appointmentId=${Uri.encodeQueryComponent(detail.id)}&complaint=${Uri.encodeQueryComponent(detail.visitType)}&veterinarian=${Uri.encodeQueryComponent(detail.assignedStaffName ?? '')}',
  );
  ref
    ..invalidate(remoteAppointmentDetailProvider(detail.id))
    ..invalidate(remoteAppointmentScheduleProvider)
    ..invalidate(remotePatientMedicalFileProvider(patient.id))
    ..invalidate(remoteDashboardProvider)
    ..invalidate(remoteReminderFeedProvider)
    ..invalidate(remoteNotificationsProvider);
}

Future<void> _rescheduleRemoteAppointment(
  BuildContext context,
  WidgetRef ref,
  RemoteAppointmentDetail detail,
) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RemoteRescheduleAppointmentSheet(detail: detail),
  );
  if (changed != true) return;
  ref
    ..invalidate(remoteAppointmentDetailProvider(detail.id))
    ..invalidate(remoteAppointmentScheduleProvider)
    ..invalidate(remotePatientMedicalFileProvider(detail.patientId))
    ..invalidate(remoteDashboardProvider)
    ..invalidate(remoteReminderFeedProvider)
    ..invalidate(remoteNotificationsProvider);
  if (context.mounted) {
    _showMessage(context, 'Appointment rescheduled successfully.');
  }
}

Future<void> _cancelRemoteAppointment(
  BuildContext context,
  WidgetRef ref,
  RemoteAppointmentDetail detail,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cancel Visit?'),
      content: const Text('Are you sure you want to cancel this appointment?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep Appointment'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Cancel Visit'),
        ),
      ],
    ),
  );
  if (confirm != true) return;
  try {
    await ref
        .read(clinicalRemoteDataSourceProvider)
        .cancelAppointment(appointmentId: detail.id, revision: detail.revision);
    ref
      ..invalidate(remoteAppointmentDetailProvider(detail.id))
      ..invalidate(remoteAppointmentScheduleProvider)
      ..invalidate(remotePatientMedicalFileProvider(detail.patientId))
      ..invalidate(remoteDashboardProvider)
      ..invalidate(remoteReminderFeedProvider)
      ..invalidate(remoteNotificationsProvider);
    if (context.mounted) _showMessage(context, 'Visit cancelled.');
  } catch (error) {
    if (context.mounted) {
      _showMessage(context, _appointmentActionErrorMessage(error));
    }
  }
}

class _RemoteRescheduleAppointmentSheet extends ConsumerStatefulWidget {
  const _RemoteRescheduleAppointmentSheet({required this.detail});

  final RemoteAppointmentDetail detail;

  @override
  ConsumerState<_RemoteRescheduleAppointmentSheet> createState() =>
      _RemoteRescheduleAppointmentSheetState();
}

class _RemoteRescheduleAppointmentSheetState
    extends ConsumerState<_RemoteRescheduleAppointmentSheet> {
  late DateTime _scheduledAt;
  late String _type;
  late String? _assignedStaffId;
  late String? _assignedStaffName;
  late final TextEditingController _notes;
  late Future<List<AppUser>> _eligibleStaff;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scheduledAt = widget.detail.scheduledAt.toLocal();
    _type = widget.detail.visitType;
    _assignedStaffId = widget.detail.assignedStaffId;
    _assignedStaffName = widget.detail.assignedStaffName;
    _notes = TextEditingController(text: widget.detail.notes ?? '');
    _eligibleStaff = ref
        .read(clinicRepositoryProvider)
        .eligibleAppointmentStaff();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .86,
      minChildSize: .55,
      maxChildSize: .96,
      builder: (context, controller) => ListView(
        controller: controller,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Reschedule Appointment', style: averaText(context).pageTitle),
          const SizedBox(height: 20),
          AveraLabeledFieldCard(
            label: 'Patient',
            child: Text(
              widget.detail.patient?.name ?? 'Patient record unavailable',
              style: averaText(context).fieldValue,
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          _DateTimeCard(
            label: 'New date',
            value: DateFormat.yMMMMd().format(_scheduledAt),
            onTap: _selectDate,
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          _DateTimeCard(
            label: 'New time',
            value: DateFormat.jm().format(_scheduledAt),
            onTap: _selectTime,
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          FutureBuilder<List<AppUser>>(
            future: _eligibleStaff,
            builder: (context, snapshot) => _ChoiceCard(
              label: 'Assigned veterinarian',
              value: _assignedStaffName ?? 'Not assigned',
              onTap: snapshot.hasData ? () => _selectVet(snapshot.data!) : null,
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          _ChoiceCard(
            label: 'Appointment type',
            value: _type,
            onTap: _selectType,
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          AveraLabeledFieldCard(
            label: 'Notes',
            child: TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Appointment notes',
              ),
            ),
          ),
          const SizedBox(height: 24),
          AveraPrimaryActionButton(
            label: 'Save New Schedule',
            icon: Icons.save_outlined,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    ),
  );

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt.isBefore(DateTime.now())
          ? DateTime.now()
          : _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && mounted) {
      setState(
        () => _scheduledAt = DateTime(
          date.year,
          date.month,
          date.day,
          _scheduledAt.hour,
          _scheduledAt.minute,
        ),
      );
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time != null && mounted) {
      setState(
        () => _scheduledAt = DateTime(
          _scheduledAt.year,
          _scheduledAt.month,
          _scheduledAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _selectVet(List<AppUser> staff) async {
    final selected = await showModalBottomSheet<AppUser>(
      context: context,
      useSafeArea: true,
      builder: (_) => _SimpleSelectionSheet<AppUser>(
        title: 'Assign veterinarian',
        items: staff,
        label: (user) => user.fullName,
        isSelected: (user) => user.userId == _assignedStaffId,
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _assignedStaffId = selected.userId;
        _assignedStaffName = selected.fullName;
      });
    }
  }

  Future<void> _selectType() async {
    final selected = await _choiceSheet(
      context,
      title: 'Appointment type',
      values: _appointmentTypes,
      current: _type,
    );
    if (selected != null && mounted) setState(() => _type = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicalRemoteDataSourceProvider)
          .updateAppointment(
            appointmentId: widget.detail.id,
            payload: {
              'revision': widget.detail.revision,
              'scheduledAt': _scheduledAt.toUtc().toIso8601String(),
              'visitType': _type,
              'assignedStaffId': _assignedStaffId,
              'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            },
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        _showMessage(context, _appointmentActionErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _appointmentActionErrorMessage(Object error) {
  if (error is! ApiException) {
    return 'The appointment could not be updated right now.';
  }
  return switch (error.code) {
    'revision_conflict' =>
      'This appointment changed elsewhere. Reload it and try again.',
    'appointment_closed' ||
    'appointment_completed' => 'This appointment can no longer be changed.',
    'permission_denied' ||
    'forbidden' => 'You do not have permission to change this appointment.',
    'not_found' => 'This appointment could not be found.',
    'invalid_staff' => 'The assigned staff member is no longer available.',
    'network_unavailable' || 'request_timeout' =>
      'The appointment could not be updated. Please check your connection.',
    _ =>
      error.statusCode != null && error.statusCode! >= 500
          ? 'The appointment could not be updated right now.'
          : error.message,
  };
}

class AppointmentDetailScreen extends ConsumerWidget {
  const AppointmentDetailScreen({super.key, required this.appointmentId});

  final int appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(appointmentDetailProvider(appointmentId));
    final session = ref.watch(userSessionProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Appointment')),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _FullPageMessage(
          title: 'Appointment unavailable',
          message:
              'This appointment could not be loaded for the active clinic.',
        ),
        data: (detail) {
          if (detail == null) {
            return const _FullPageMessage(
              title: 'Appointment unavailable',
              message:
                  'It may belong to another clinic or no longer be available.',
            );
          }
          return _AppointmentDetailBody(detail: detail, session: session);
        },
      ),
    );
  }
}

class _AppointmentDetailBody extends ConsumerWidget {
  const _AppointmentDetailBody({required this.detail, required this.session});

  final AppointmentDetail detail;
  final UserSession? session;

  bool get _isCancelled =>
      AppointmentStatuses.normalize(detail.appointment.status) ==
      AppointmentStatuses.cancelled;

  bool get _isCompleted =>
      AppointmentStatuses.normalize(detail.appointment.status) ==
      AppointmentStatuses.completed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit =
        session?.can(Permissions.appointmentsEdit) == true &&
        !_isCancelled &&
        !_isCompleted;
    final canCancel =
        session?.can(Permissions.appointmentsCancel) == true &&
        !_isCancelled &&
        !_isCompleted;
    final canStart =
        session?.can(Permissions.appointmentsStartConsultation) == true &&
        !_isCancelled &&
        !_isCompleted &&
        detail.appointment.consultationId == null;
    final formattedDate = DateFormat.yMMMMd().format(
      detail.appointment.appointmentDate,
    );
    final formattedTime = DateFormat.jm().format(
      detail.appointment.appointmentDate,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        20,
        20,
        AveraSpacing.bottomContentClearance,
      ),
      children: [
        _StatusChip(
          status: AppointmentStatuses.normalize(detail.appointment.status),
        ),
        const SizedBox(height: 12),
        Text(
          detail.appointment.reference ?? 'Appointment',
          style: averaText(context).caption,
        ),
        const SizedBox(height: 12),
        _PatientCard(detail: detail),
        const SizedBox(height: AveraSpacing.sectionGap),
        const AveraSectionHeader(title: 'Appointment Details'),
        const SizedBox(height: 12),
        AveraSurfaceCard(
          child: Column(
            children: [
              _KeyValueRow(label: 'Date', value: formattedDate),
              _KeyValueRow(label: 'Time', value: formattedTime),
              _KeyValueRow(label: 'Type', value: detail.appointment.purpose),
              _KeyValueRow(
                label: 'Assigned vet',
                value: detail.assignedStaff?.fullName ?? 'Not assigned',
                showDivider: false,
              ),
            ],
          ),
        ),
        if (_isCancelled) ...[
          const SizedBox(height: AveraSpacing.cardGap),
          const AveraSectionHeader(title: 'Cancellation'),
          const SizedBox(height: 12),
          AveraSurfaceCard(
            child: Column(
              children: [
                _KeyValueRow(
                  label: 'Cancelled on',
                  value: detail.appointment.updatedAt == null
                      ? 'Not recorded'
                      : DateFormat.yMMMMd().add_jm().format(
                          detail.appointment.updatedAt!,
                        ),
                ),
                const _KeyValueRow(
                  label: 'Reason',
                  value: 'No cancellation reason was recorded.',
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
        FutureBuilder<List<AppointmentRescheduleRecord>>(
          future: ref
              .read(clinicRepositoryProvider)
              .getAppointmentRescheduleHistory(detail.appointment.id),
          builder: (context, snapshot) {
            final history =
                snapshot.data ?? const <AppointmentRescheduleRecord>[];
            if (history.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AveraSpacing.sectionGap),
                const AveraSectionHeader(title: 'Reschedule History'),
                const SizedBox(height: 12),
                AveraSurfaceCard(
                  child: Column(
                    children: [
                      for (final item in history) ...[
                        _KeyValueRow(
                          label: 'Previous',
                          value: DateFormat.yMMMMd().add_jm().format(
                            item.previousDate,
                          ),
                        ),
                        _KeyValueRow(
                          label: 'New',
                          value: DateFormat.yMMMMd().add_jm().format(
                            item.newDate,
                          ),
                        ),
                        _KeyValueRow(
                          label: 'Changed by',
                          value: item.changedByName ?? 'Clinic team',
                        ),
                        _KeyValueRow(
                          label: 'Changed on',
                          value: DateFormat.yMMMMd().add_jm().format(
                            item.changedAt,
                          ),
                          showDivider: item != history.last,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        if ((detail.appointment.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AveraSpacing.cardGap),
          const AveraSectionHeader(title: 'Notes'),
          const SizedBox(height: 12),
          AveraSurfaceCard(
            child: Text(
              detail.appointment.notes!,
              style: averaText(context).fieldValue,
            ),
          ),
        ],
        const SizedBox(height: AveraSpacing.sectionGap),
        const AveraSectionHeader(
          title: 'Reminders',
          subtitle: 'On-device notifications',
        ),
        const SizedBox(height: 12),
        AveraSurfaceCard(
          child: Column(
            children: [
              if (detail.reminders.isEmpty)
                Text(
                  'No reminders enabled.',
                  style: averaText(context).fieldPlaceholder,
                )
              else
                for (final reminder in detail.reminders)
                  _ReminderSwitch(
                    detail: detail,
                    reminder: reminder,
                    enabled: canEdit,
                  ),
            ],
          ),
        ),
        const SizedBox(height: AveraSpacing.sectionGap),
        if (canStart)
          AveraPrimaryActionButton(
            label: 'Start Consultation',
            icon: Icons.medical_services_outlined,
            onPressed: () => context.push(
              '/consultations/new?animalId=${detail.animal.id}&appointmentId=${detail.appointment.id}&complaint=${Uri.encodeQueryComponent(detail.appointment.purpose)}&veterinarian=${Uri.encodeQueryComponent(detail.assignedStaff?.fullName ?? '')}',
            ),
          )
        else if (detail.appointment.consultationId != null)
          AveraPrimaryActionButton(
            label: 'View Consultation',
            icon: Icons.visibility_outlined,
            onPressed: () => context.push(
              '/consultations/${detail.appointment.consultationId}',
            ),
          ),
        if (_isCancelled) ...[
          if (session?.can(Permissions.appointmentsCreate) == true)
            AveraPrimaryActionButton(
              label: 'Create New Appointment',
              icon: Icons.add_circle_outline_rounded,
              onPressed: () => context.push(
                '/appointments/new?animalId=${detail.animal.id}',
              ),
            ),
          if (session?.can(Permissions.patientsView) == true) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/animals/${detail.animal.id}'),
                icon: const Icon(Icons.pets_outlined),
                label: const Text('Open Patient File'),
              ),
            ),
          ],
        ],
        if (canEdit || canCancel) ...[
          const SizedBox(height: 12),
          if (canEdit)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _reschedule(context, ref, detail),
                icon: const Icon(Icons.edit_calendar_rounded),
                label: const Text('Reschedule'),
              ),
            ),
          if (canEdit && canCancel) const SizedBox(height: 12),
          if (canCancel)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _cancel(context, ref, detail),
                icon: const Icon(Icons.event_busy_rounded),
                label: const Text('Cancel Visit'),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _reschedule(
    BuildContext context,
    WidgetRef ref,
    AppointmentDetail current,
  ) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RescheduleAppointmentSheet(detail: current),
    );
    if (changed == true) {
      ref.invalidate(appointmentDetailProvider(current.appointment.id));
      if (context.mounted) {
        _showMessage(context, 'Appointment rescheduled successfully.');
      }
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    AppointmentDetail current,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this visit?'),
        content: const Text('The appointment will be marked as cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Appointment'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Visit'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final session = await ref.read(userSessionProvider.future);
      await ref
          .read(clinicRepositoryProvider)
          .cancelAppointment(
            session: session,
            appointmentId: current.appointment.id,
          );
      await ref
          .read(appointmentNotificationServiceProvider)
          .cancelReminders(current.reminders);
      ref.invalidate(appointmentDetailProvider(current.appointment.id));
      if (context.mounted) _showMessage(context, 'Visit cancelled.');
    } catch (error) {
      if (context.mounted) _showMessage(context, '$error');
    }
  }
}

class _RescheduleAppointmentSheet extends ConsumerStatefulWidget {
  const _RescheduleAppointmentSheet({required this.detail});

  final AppointmentDetail detail;

  @override
  ConsumerState<_RescheduleAppointmentSheet> createState() =>
      _RescheduleAppointmentSheetState();
}

class _RescheduleAppointmentSheetState
    extends ConsumerState<_RescheduleAppointmentSheet> {
  late DateTime _scheduledAt;
  late String _type;
  AppUser? _vet;
  late Set<int> _reminders;
  late final TextEditingController _notes;
  final _reason = TextEditingController();
  late Future<List<AppUser>> _eligibleStaff;
  bool _saving = false;

  AppointmentDetail get _detail => widget.detail;

  @override
  void initState() {
    super.initState();
    _scheduledAt = _detail.appointment.appointmentDate;
    _type = _detail.appointment.purpose;
    _vet = _detail.assignedStaff;
    _reminders = _detail.reminders
        .where((reminder) => reminder.enabled)
        .map((reminder) => reminder.daysBefore)
        .toSet();
    _notes = TextEditingController(text: _detail.appointment.notes ?? '');
    _eligibleStaff = ref
        .read(clinicRepositoryProvider)
        .eligibleAppointmentStaff();
  }

  @override
  void dispose() {
    _notes.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, controller) => ListView(
        controller: controller,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Reschedule Appointment', style: averaText(context).pageTitle),
          const SizedBox(height: 20),
          AveraLabeledFieldCard(
            label: 'Patient',
            surfaceColor: Theme.of(context).colorScheme.surfaceContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _detail.animal.animalName,
                  style: averaText(context).fieldValue,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_detail.animal.hospitalNumber} • ${_detail.animal.breed ?? _detail.animal.species} • ${_detail.animal.sex ?? 'Sex not recorded'}',
                  style: averaText(context).caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          AveraLabeledFieldCard(
            label: 'Current appointment',
            surfaceColor: Theme.of(context).colorScheme.surfaceContainer,
            child: Text(
              '${DateFormat.yMMMMd().format(_detail.appointment.appointmentDate)} • ${DateFormat.jm().format(_detail.appointment.appointmentDate)}',
              style: averaText(context).fieldValue,
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          _DateTimeCard(
            label: 'New date',
            value: DateFormat.yMMMMd().format(_scheduledAt),
            onTap: _selectDate,
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          _DateTimeCard(
            label: 'New time',
            value: DateFormat.jm().format(_scheduledAt),
            onTap: _selectTime,
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          FutureBuilder<List<AppUser>>(
            future: _eligibleStaff,
            builder: (context, snapshot) => _ChoiceCard(
              label: 'Assigned veterinarian',
              value: _vet?.fullName ?? 'Select veterinarian',
              onTap: snapshot.hasData && snapshot.data!.isNotEmpty
                  ? _selectVet
                  : null,
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          _ChoiceCard(
            label: 'Appointment type',
            value: _type,
            onTap: _selectType,
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          AveraLabeledFieldCard(
            label: 'Reminders',
            child: Column(
              children: [
                for (final days in const [7, 3, 1])
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '$days day${days == 1 ? '' : 's'} before',
                      style: averaText(context).fieldValue,
                    ),
                    value: _reminders.contains(days),
                    onChanged: (value) => setState(() {
                      value ? _reminders.add(days) : _reminders.remove(days);
                    }),
                  ),
                Text(
                  'On-device notifications',
                  style: averaText(context).caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          AveraLabeledFieldCard(
            label: 'Notes',
            child: TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Appointment notes',
              ),
            ),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          AveraLabeledFieldCard(
            label: 'Reason for rescheduling (optional)',
            child: TextFormField(
              controller: _reason,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Client requested another date',
              ),
            ),
          ),
          const SizedBox(height: 24),
          AveraPrimaryActionButton(
            label: 'Save New Schedule',
            icon: Icons.save_outlined,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    ),
  );

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt.isBefore(DateTime.now())
          ? DateTime.now()
          : _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && mounted) {
      setState(
        () => _scheduledAt = DateTime(
          date.year,
          date.month,
          date.day,
          _scheduledAt.hour,
          _scheduledAt.minute,
        ),
      );
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time != null && mounted) {
      setState(
        () => _scheduledAt = DateTime(
          _scheduledAt.year,
          _scheduledAt.month,
          _scheduledAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _selectVet() async {
    final staff = await _eligibleStaff;
    if (!mounted) return;
    final selected = await showModalBottomSheet<AppUser>(
      context: context,
      useSafeArea: true,
      builder: (_) => _SimpleSelectionSheet<AppUser>(
        title: 'Assign veterinarian',
        items: staff,
        label: (user) => user.fullName,
        isSelected: (user) => user.userId == _vet?.userId,
      ),
    );
    if (selected != null && mounted) setState(() => _vet = selected);
  }

  Future<void> _selectType() async {
    final selected = await _choiceSheet(
      context,
      title: 'Appointment type',
      values: _appointmentTypes,
      current: _type,
    );
    if (selected != null && mounted) setState(() => _type = selected);
  }

  Future<void> _save() async {
    if (_scheduledAt.isAtSameMomentAs(_detail.appointment.appointmentDate)) {
      _showMessage(
        context,
        'Choose a different date or time to reschedule this appointment.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
      final notifications = ref.read(appointmentNotificationServiceProvider);
      await notifications.cancelReminders(_detail.reminders);
      await ref
          .read(clinicRepositoryProvider)
          .rescheduleAppointment(
            session: session,
            appointmentId: _detail.appointment.id,
            scheduledAt: _scheduledAt,
            assignedStaffId: _vet?.userId,
            appointmentType: _type,
            notes: _notes.text,
            reason: _reason.text,
            enabledReminderDays: _reminders,
          );
      final refreshed = await ref
          .read(clinicRepositoryProvider)
          .getAppointmentDetail(_detail.appointment.id);
      if (refreshed != null) {
        await _scheduleEnabledReminders(
          ref,
          refreshed,
          session.clinic.timeZone,
        );
      }
      ref.invalidate(appointmentDetailProvider(_detail.appointment.id));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) _showMessage(context, '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class NewAppointmentScreen extends ConsumerStatefulWidget {
  const NewAppointmentScreen({super.key});

  @override
  ConsumerState<NewAppointmentScreen> createState() =>
      _NewAppointmentScreenState();
}

class _NewAppointmentScreenState extends ConsumerState<NewAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();
  Animal? _patient;
  RemotePatient? _remotePatient;
  late final String _submissionId = const Uuid().v4();
  AppUser? _vet;
  String _type = _appointmentTypes.first;
  DateTime _dateTime = DateTime.now().add(const Duration(days: 1));
  final Set<int> _reminders = {7, 3, 1};
  bool _saving = false;
  late Future<List<AppUser>> _eligibleStaff;

  @override
  void initState() {
    super.initState();
    _eligibleStaff = ref
        .read(clinicRepositoryProvider)
        .eligibleAppointmentStaff();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Appointment')),
    body: Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          AveraLabeledFieldCard(
            label: 'Patient',
            child: InkWell(
              onTap: _selectPatient,
              borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _patient == null && _remotePatient == null
                          ? 'Search an existing patient or add new'
                          : _remotePatient != null
                          ? '${_remotePatient!.name} / ${_remotePatient!.hospitalNumber}'
                          : '${_patient!.animalName} / ${_patient!.hospitalNumber}',
                      style: _patient == null && _remotePatient == null
                          ? averaText(context).fieldPlaceholder
                          : averaText(context).fieldValue,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DateTimeCard(
                  label: 'Date',
                  value: DateFormat.yMMMd().format(_dateTime),
                  onTap: _selectDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateTimeCard(
                  label: 'Time',
                  value: DateFormat.jm().format(_dateTime),
                  onTap: _selectTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ChoiceCard(
            label: 'Appointment type',
            value: _type,
            onTap: _selectType,
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<AppUser>>(
            future: _eligibleStaff,
            builder: (context, snapshot) => _ChoiceCard(
              label: 'Assigned vet',
              value:
                  _vet?.fullName ??
                  (snapshot.hasData && snapshot.data!.isEmpty
                      ? 'No eligible veterinarian'
                      : 'Select veterinarian'),
              onTap: snapshot.hasData && snapshot.data!.isNotEmpty
                  ? _selectVet
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          AveraLabeledFieldCard(
            label: 'Notes (optional)',
            child: TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Add reason for visit or preparation notes',
              ),
            ),
          ),
          const SizedBox(height: 16),
          AveraLabeledFieldCard(
            label: 'Set reminders',
            child: Column(
              children: [
                for (final days in const [7, 3, 1])
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '$days day${days == 1 ? '' : 's'} before',
                      style: averaText(context).fieldValue,
                    ),
                    value: _reminders.contains(days),
                    onChanged: (value) => setState(() {
                      value ? _reminders.add(days) : _reminders.remove(days);
                    }),
                  ),
                Text(
                  'Notifications appear on this device only.',
                  style: averaText(context).caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AveraPrimaryActionButton(
            label: 'Save Appointment',
            icon: Icons.calendar_month_outlined,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    ),
  );

  Future<void> _selectPatient() async {
    if (BackendConfiguration.isConfigured) {
      final result = await showModalBottomSheet<RemotePatient>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.86,
          child: RemotePatientSelectorSheet(selectedId: _remotePatient?.id),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _remotePatient = result;
          _patient = null;
        });
      }
      return;
    }
    final result = await showModalBottomSheet<Animal>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _PatientPickerSheet(),
    );
    if (result != null && mounted) setState(() => _patient = result);
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && mounted) {
      setState(
        () => _dateTime = DateTime(
          date.year,
          date.month,
          date.day,
          _dateTime.hour,
          _dateTime.minute,
        ),
      );
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (time != null && mounted) {
      setState(
        () => _dateTime = DateTime(
          _dateTime.year,
          _dateTime.month,
          _dateTime.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _selectType() async {
    final selected = await _choiceSheet(
      context,
      title: 'Appointment type',
      values: _appointmentTypes,
      current: _type,
    );
    if (selected != null && mounted) setState(() => _type = selected);
  }

  Future<void> _selectVet() async {
    final staff = await _eligibleStaff;
    if (!mounted) return;
    final selected = await showModalBottomSheet<AppUser>(
      context: context,
      useSafeArea: true,
      builder: (context) => _SimpleSelectionSheet<AppUser>(
        title: 'Assign veterinarian',
        items: staff,
        label: (user) => user.fullName,
        isSelected: (user) => user.userId == _vet?.userId,
      ),
    );
    if (selected != null && mounted) setState(() => _vet = selected);
  }

  Future<void> _save() async {
    if (_patient == null && _remotePatient == null) {
      _showMessage(context, 'Select a patient before saving.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final session = await ref.read(userSessionProvider.future);
      if (BackendConfiguration.isConfigured) {
        await ref.read(clinicalRemoteDataSourceProvider).createAppointment({
          'submissionId': _submissionId,
          'patientId': _remotePatient!.id,
          'scheduledAt': _dateTime.toUtc().toIso8601String(),
          'visitType': _type,
          'assignedStaffId': _vet?.userId,
          'notes': _notes.text.trim(),
        });
        ref
          ..invalidate(remotePatientMedicalFileProvider(_remotePatient!.id))
          ..invalidate(remoteDashboardProvider)
          ..invalidate(remoteReminderFeedProvider)
          ..invalidate(remoteNotificationsProvider)
          ..invalidate(remoteAppointmentScheduleProvider);
        if (mounted) {
          _showMessage(context, 'Appointment saved.');
          context.pop();
        }
        return;
      }
      final appointment = await ref
          .read(clinicRepositoryProvider)
          .createAppointment(
            session: session,
            animalId: _patient!.id,
            scheduledAt: _dateTime,
            appointmentType: _type,
            assignedStaffId: _vet?.userId,
            notes: _notes.text,
            enabledReminderDays: _reminders,
          );
      final detail = await ref
          .read(clinicRepositoryProvider)
          .getAppointmentDetail(appointment.id);
      if (detail != null) {
        await _scheduleEnabledReminders(ref, detail, session.clinic.timeZone);
      }
      ref.invalidate(appointmentDetailProvider(appointment.id));
      if (mounted) context.replace('/appointments/${appointment.id}');
    } catch (error) {
      if (mounted) _showMessage(context, _appointmentErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _appointmentErrorMessage(Object error) {
  if (error is! ApiException) {
    return 'The appointment could not be saved right now.';
  }
  return switch (error.code) {
    'validation_error' => 'Please check the appointment details.',
    'session_expired' ||
    'invalid_session' => 'Your session has expired. Please sign in again.',
    'permission_denied' ||
    'forbidden' => 'You do not have permission to create appointments.',
    'patient_not_found' => 'The selected patient could not be found.',
    'invalid_staff' ||
    'staff_not_found' => 'The assigned staff member could not be found.',
    'conflict' ||
    'duplicate' => 'This appointment conflicts with an existing record.',
    'network_unavailable' || 'request_timeout' =>
      'The appointment could not be sent. Your entries are still available.',
    _ =>
      error.statusCode != null && error.statusCode! >= 500
          ? 'The appointment could not be saved right now.'
          : error.message,
  };
}

class _PatientPickerSheet extends ConsumerStatefulWidget {
  const _PatientPickerSheet();

  @override
  ConsumerState<_PatientPickerSheet> createState() =>
      _PatientPickerSheetState();
}

class _PatientPickerSheetState extends ConsumerState<_PatientPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final animals = ref.watch(clinicRepositoryProvider).watchAnimals();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('Select Patient', style: averaText(context).sectionTitle),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search name or hospital number',
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final result = await context.push<int>(
                  '/animals/new?returnResult=true',
                );
                if (result == null || !mounted) return;
                final patient =
                    await (ref
                            .read(clinicRepositoryProvider)
                            .db
                            .select(
                              ref.read(clinicRepositoryProvider).db.animals,
                            )
                          ..where((row) => row.id.equals(result)))
                        .getSingleOrNull();
                if (patient != null && context.mounted) {
                  Navigator.pop(context, patient);
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Register New Patient'),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Animal>>(
              stream: animals,
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <Animal>[];
                final filtered = all
                    .where(
                      (animal) =>
                          _query.isEmpty ||
                          '${animal.animalName} ${animal.hospitalNumber}'
                              .toLowerCase()
                              .contains(_query),
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No matching active patients.'),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final animal = filtered[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.pets_outlined),
                      ),
                      title: Text(
                        animal.animalName,
                        style: averaText(context).listItemTitle,
                      ),
                      subtitle: Text(
                        animal.hospitalNumber,
                        style: averaText(context).listItemSubtitle,
                      ),
                      onTap: () => Navigator.pop(context, animal),
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

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.appointment,
    required this.patient,
    required this.onTap,
  });
  final Appointment appointment;
  final Animal? patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
            ),
            child: Icon(
              Icons.calendar_month_outlined,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        patient?.animalName ?? 'Patient record unavailable',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: averaText(context).listItemTitle,
                      ),
                    ),
                    if (AppointmentStatuses.normalize(appointment.status) !=
                        AppointmentStatuses.confirmed) ...[
                      const SizedBox(width: 8),
                      _AppointmentStatusBadge(status: appointment.status),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${patient?.hospitalNumber ?? 'No hospital number'} / ${DateFormat.yMMMd().add_jm().format(appointment.appointmentDate)}',
                  style: averaText(context).listItemSubtitle,
                ),
                const SizedBox(height: 3),
                Text(
                  appointment.purpose,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: averaText(context).caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

class _AppointmentStatusBadge extends StatelessWidget {
  const _AppointmentStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = AppointmentStatuses.normalize(status);
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final color = switch (normalized) {
      AppointmentStatuses.cancelled ||
      AppointmentStatuses.noShow => semantic.danger,
      AppointmentStatuses.completed => semantic.info,
      AppointmentStatuses.pending => semantic.warning,
      _ => semantic.success,
    };
    return Semantics(
      label: 'Appointment status: $normalized',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .6)),
        ),
        child: Text(
          normalized,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: averaText(
            context,
          ).caption.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.detail});
  final AppointmentDetail detail;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Row(
      children: [
        CircleAvatar(
          radius: 28,
          child: Text(detail.animal.animalName.characters.first.toUpperCase()),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.animal.animalName,
                style: averaText(context).listItemTitle,
              ),
              Text(
                '${detail.animal.breed ?? detail.animal.species} / ${detail.animal.sex ?? 'Sex not recorded'}',
                style: averaText(context).listItemSubtitle,
              ),
              Text(
                'Owner: ${detail.owner.fullName}',
                style: averaText(context).listItemSubtitle,
              ),
              Text(detail.owner.phone, style: averaText(context).caption),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Call owner',
          icon: const Icon(Icons.call_outlined),
          onPressed: () => _callOwner(context, detail.owner.phone),
        ),
      ],
    ),
  );
}

class _ReminderSwitch extends ConsumerWidget {
  const _ReminderSwitch({
    required this.detail,
    required this.reminder,
    required this.enabled,
  });
  final AppointmentDetail detail;
  final AppointmentReminder reminder;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(
      '${reminder.daysBefore} day${reminder.daysBefore == 1 ? '' : 's'} before',
      style: averaText(context).fieldValue,
    ),
    value: reminder.enabled,
    onChanged: !enabled
        ? null
        : (value) async {
            try {
              final service = ref.read(appointmentNotificationServiceProvider);
              if (value && !await service.requestPermission()) {
                if (context.mounted) {
                  _showMessage(
                    context,
                    'Notification permission is needed for reminders.',
                  );
                }
                return;
              }
              final session = await ref.read(userSessionProvider.future);
              await ref
                  .read(clinicRepositoryProvider)
                  .setAppointmentReminder(
                    session: session,
                    appointmentId: detail.appointment.id,
                    daysBefore: reminder.daysBefore,
                    enabled: value,
                  );
              if (!value) await service.cancelReminder(reminder.notificationId);
              final refreshed = await ref
                  .read(clinicRepositoryProvider)
                  .getAppointmentDetail(detail.appointment.id);
              if (refreshed != null && value) {
                await _scheduleEnabledReminders(
                  ref,
                  refreshed,
                  session.clinic.timeZone,
                );
              }
              ref.invalidate(appointmentDetailProvider(detail.appointment.id));
            } catch (error) {
              if (context.mounted) _showMessage(context, '$error');
            }
          },
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    final color = switch (status) {
      AppointmentStatuses.confirmed => colors.success,
      AppointmentStatuses.completed => colors.info,
      AppointmentStatuses.cancelled ||
      AppointmentStatuses.noShow => colors.danger,
      _ => colors.warning,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: Icon(Icons.circle, size: 10, color: color),
        label: Text(status),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });
  final String label;
  final String value;
  final bool showDivider;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: Text(label, style: averaText(context).caption),
            ),
            Expanded(child: Text(value, style: averaText(context).fieldValue)),
          ],
        ),
      ),
      if (showDivider) const Divider(height: 1),
    ],
  );
}

class _DateTimeCard extends StatelessWidget {
  const _DateTimeCard({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: Text(value, style: averaText(context).fieldValue)),
          const Icon(Icons.keyboard_arrow_down_rounded),
        ],
      ),
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              style: onTap == null
                  ? averaText(context).fieldPlaceholder
                  : averaText(context).fieldValue,
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded),
        ],
      ),
    ),
  );
}

class _SimpleSelectionSheet<T> extends StatelessWidget {
  const _SimpleSelectionSheet({
    required this.title,
    required this.items,
    required this.label,
    required this.isSelected,
  });
  final String title;
  final List<T> items;
  final String Function(T) label;
  final bool Function(T) isSelected;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: averaText(context).sectionTitle),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  title: Text(label(item)),
                  trailing: isSelected(item)
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: averaText(context).listItemTitle),
              Text(message, style: averaText(context).listItemSubtitle),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FullPageMessage extends StatelessWidget {
  const _FullPageMessage({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_busy_outlined, size: 40),
          const SizedBox(height: 12),
          Text(title, style: averaText(context).sectionTitle),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: averaText(context).sectionSubtitle,
          ),
        ],
      ),
    ),
  );
}

Future<String?> _choiceSheet(
  BuildContext context, {
  required String title,
  required List<String> values,
  required String current,
}) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  builder: (context) => _SimpleSelectionSheet<String>(
    title: title,
    items: values,
    label: (value) => value,
    isSelected: (value) => value == current,
  ),
);

Future<void> _callOwner(BuildContext context, String phone) async {
  final target = Uri(
    scheme: 'tel',
    path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
  );
  if (!await canLaunchUrl(target) || !await launchUrl(target)) {
    if (context.mounted) {
      _showMessage(context, 'A phone app is not available on this device.');
    }
  }
}

Future<void> _scheduleEnabledReminders(
  WidgetRef ref,
  AppointmentDetail detail,
  String timeZone,
) async {
  final service = ref.read(appointmentNotificationServiceProvider);
  for (final reminder in detail.reminders.where((item) => item.enabled)) {
    await service.scheduleReminder(
      detail: detail,
      reminder: reminder,
      timeZone: timeZone,
    );
  }
}

void _showMessage(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
