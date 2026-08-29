import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/models/alert_destination.dart';
import '../../../core/models/reminder_event.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/services/clinic_operating_status_service.dart';
import '../../../core/services/dashboard_mode_resolver.dart';
import '../../../core/services/feature_gate_service.dart';
import '../../../core/theme/app_theme.dart';
import '../navigation/clinic_activity_navigation.dart';
import '../navigation/clinic_activity_remote_adapter.dart';
import '../widgets/branded_app_bar.dart';
import '../widgets/avera_ui.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    final stats = BackendConfiguration.isConfigured
        ? ref
              .watch(remoteDashboardProvider)
              .whenData(
                (summary) => dashboardStatsFromRemote(
                  summary,
                  clinicId: session.valueOrNull?.clinic.clinicId ?? '',
                ),
              )
        : ref.watch(dashboardStatsProvider);
    final notifications = BackendConfiguration.isConfigured
        ? null
        : ref.watch(notificationsProvider);
    final reminderFeed = BackendConfiguration.isConfigured
        ? ref.watch(remoteReminderFeedProvider)
        : const AsyncData(ReminderFeed(upcoming: [], alerts: []));
    final showingCachedReminders =
        BackendConfiguration.isConfigured &&
        ref.watch(remoteReminderFeedOfflineProvider);
    final operatingStatus = ref.watch(clinicOperatingStatusProvider);
    final showingCachedDashboard =
        BackendConfiguration.isConfigured &&
        ref.watch(remoteDashboardOfflineProvider);
    return Scaffold(
      appBar: const BrandedAppBar(),
      body: stats.when(
        loading: () => const _DashboardSkeleton(),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The clinic dashboard could not be loaded.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(remoteDashboardProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry dashboard'),
              ),
            ],
          ),
        ),
        data: (data) {
          final sessionData = session.valueOrNull;
          final dashboardMode = sessionData == null
              ? DashboardMode.staff
              : DashboardModeResolver.resolve(sessionData);
          final actions = sessionData == null
              ? const <_QuickAction>[]
              : _dashboardActionsFor(sessionData, dashboardMode);
          final alerts =
              notifications?.valueOrNull
                  ?.where((item) => !item.isRead)
                  .take(4)
                  .toList() ??
              const [];
          return RefreshIndicator(
            onRefresh: () async {
              if (BackendConfiguration.isConfigured) {
                ref.invalidate(remoteDashboardProvider);
              } else {
                ref.invalidate(dashboardStatsProvider);
              }
              ref.invalidate(notificationsProvider);
              if (BackendConfiguration.isConfigured) {
                ref.invalidate(remoteReminderFeedProvider);
                ref.invalidate(remoteNotificationsProvider);
                final refreshed = await ref.read(
                  remoteReminderFeedProvider.future,
                );
                final currentSession = await ref.read(
                  userSessionProvider.future,
                );
                await ref
                    .read(appointmentNotificationServiceProvider)
                    .reconcileEvents(
                      events: refreshed.upcoming,
                      timeZone: currentSession.clinic.timeZone,
                    );
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  AveraSpacing.bottomContentClearance,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showingCachedDashboard) ...[
                            Row(
                              children: [
                                const Icon(Icons.cloud_off_outlined, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Showing saved dashboard data while the server reconnects.',
                                    style: averaText(context).caption,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (dashboardMode == DashboardMode.administrative)
                            const _AdminConsoleHeader()
                          else
                            _StaffGreetingCard(
                              userName:
                                  sessionData?.user.fullName ??
                                  sessionData?.user.role ??
                                  'Team Member',
                              clinicName:
                                  sessionData?.clinic.clinicName ?? 'AVERA',
                              operatingStatus: operatingStatus,
                              canManageHours:
                                  sessionData != null &&
                                  (sessionData.can(
                                        Permissions.clinicWorkHoursManage,
                                      ) ||
                                      sessionData.can(
                                        Permissions.clinicSettingsEdit,
                                      )),
                            ),
                          const SizedBox(height: 24),
                          _DashboardQuickAccess(actions: actions),
                          const SizedBox(height: 36),
                          _AlertsAndActivity(
                            data: data,
                            alerts: alerts,
                            reminderFeed: reminderFeed,
                            showingCachedReminders: showingCachedReminders,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton:
          session.valueOrNull == null ||
              !session.valueOrNull!.can(Permissions.patientsCreate) ||
              !FeatureGateService.canAccess(
                subscriptionPlan: session.valueOrNull!.clinic.subscriptionPlan,
                feature: AveraFeature.patientRecords,
              )
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/animals/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Register Pet'),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

DashboardStats dashboardStatsFromRemote(
  RemoteDashboardSummary summary, {
  required String clinicId,
}) => DashboardStats(
  totalAnimals: summary.registeredPatients,
  todaysConsultations: summary.activeConsultations,
  appointmentsToday: summary.todaysSchedule,
  vaccinationsDue: summary.vaccinationsDue,
  lowStock: summary.lowStock,
  expiredDrugs: summary.expiredProducts,
  monthlyRevenue: summary.currentRevenue.toDouble(),
  recentVisits: const [],
  recentActivity: [
    for (var index = 0; index < summary.recentActivity.length; index++)
      clinicActivityEventFromRemote(
        summary.recentActivity[index],
        clinicId: clinicId,
        index: index,
      ),
  ],
  unreadNotifications: 0,
);

// Legacy layout retained while older dashboard widget tests are migrated.
// ignore: unused_element
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.userName,
    required this.clinicName,
    required this.workingHours,
  });
  final String userName;
  final String clinicName;
  final String? workingHours;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting,',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$clinicName  •  ${workingHours ?? 'Mon–Sat • 08:00–18:00'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.pets_rounded,
                size: 32,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) =>
      AveraSectionHeader(title: title, subtitle: subtitle);
}

// Legacy static action layout retained while older dashboard widget tests are migrated.
// ignore: unused_element
class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid();

  @override
  Widget build(BuildContext context) {
    const actions = [
      _QuickAction(
        'Registered Pets',
        Icons.pets_rounded,
        '/animals',
        _ActionTone.teal,
      ),
      _QuickAction(
        'Consultation',
        Icons.medical_services_rounded,
        '/consultations/new',
        _ActionTone.green,
      ),
      _QuickAction(
        'Vaccine Schedule',
        Icons.vaccines_rounded,
        '/vaccinations',
        _ActionTone.teal,
      ),
      _QuickAction(
        'Revenue',
        Icons.payments_outlined,
        '/billing',
        _ActionTone.violet,
      ),
      _QuickAction(
        'Inventory',
        Icons.inventory_2_outlined,
        '/inventory',
        _ActionTone.amber,
      ),
      _QuickAction(
        'Expired Products',
        Icons.warning_amber_rounded,
        '/inventory?filter=expired',
        _ActionTone.red,
      ),
      _QuickAction(
        'Reports',
        Icons.bar_chart_rounded,
        '/reports',
        _ActionTone.violet,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 640
            ? 4
            : constraints.maxWidth >= 460
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 2 ? 1.05 : .92,
          ),
          itemBuilder: (context, index) =>
              _QuickActionTile(action: actions[index])
                  .animate()
                  .fadeIn(
                    delay: Duration(milliseconds: 25 * index),
                    duration: 180.ms,
                  )
                  .scale(
                    begin: const Offset(.97, .97),
                    end: const Offset(1, 1),
                    duration: 180.ms,
                  ),
        );
      },
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});
  final _QuickAction action;
  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, action.tone);
    return Card(
      key: ValueKey('dashboard-quick-action-${action.label}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(action.path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                key: ValueKey('dashboard-quick-action-icon-${action.label}'),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(action.icon, size: 22, color: color),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: Center(
                  child: Text(
                    action.label,
                    key: ValueKey(
                      'dashboard-quick-action-label-${action.label}',
                    ),
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      letterSpacing: 0,
                    ),
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

class _AlertsAndActivity extends StatelessWidget {
  const _AlertsAndActivity({
    required this.data,
    required this.alerts,
    required this.reminderFeed,
    required this.showingCachedReminders,
  });
  final DashboardStats data;
  final List<dynamic> alerts;
  final AsyncValue<ReminderFeed> reminderFeed;
  final bool showingCachedReminders;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sideBySide = constraints.maxWidth >= 900;
      final alertsPanel = _AlertPanel(
        data: data,
        alerts: alerts,
        reminderFeed: reminderFeed,
        showingCachedReminders: showingCachedReminders,
      );
      final activityPanel = _RecentActivity(data: data);
      if (!sideBySide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [alertsPanel, const SizedBox(height: 24), activityPanel],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: alertsPanel),
          const SizedBox(width: 20),
          Expanded(child: activityPanel),
        ],
      );
    },
  );
}

class _AlertPanel extends StatelessWidget {
  const _AlertPanel({
    required this.data,
    required this.alerts,
    required this.reminderFeed,
    required this.showingCachedReminders,
  });
  final DashboardStats data;
  final List<dynamic> alerts;
  final AsyncValue<ReminderFeed> reminderFeed;
  final bool showingCachedReminders;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionHeading(
        title: 'Alerts & Upcoming Activity',
        subtitle: 'Items that need attention',
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (showingCachedReminders)
                const ListTile(
                  leading: Icon(Icons.cloud_off_outlined),
                  title: Text('Showing saved activity'),
                  subtitle: Text('Upcoming activity could not be refreshed.'),
                ),
              ...reminderFeed.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(),
                  ),
                ],
                error: (_, __) => const [
                  Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Upcoming activity could not be loaded.'),
                  ),
                ],
                data: (feed) {
                  final upcoming = feed.upcoming
                      .where(
                        (item) => !feed.alerts.any(
                          (alert) => alert.eventId == item.eventId,
                        ),
                      )
                      .take(4)
                      .toList();
                  return [
                    if (feed.alerts.isNotEmpty)
                      const _ReminderGroupLabel('Requires attention'),
                    for (final event in feed.alerts.take(4))
                      _ReminderTile(event: event, alert: true),
                    if (upcoming.isNotEmpty)
                      const _ReminderGroupLabel('Upcoming'),
                    for (final event in upcoming) _ReminderTile(event: event),
                  ];
                },
              ),
              if (data.expiredDrugs > 0)
                _AlertTile(
                  icon: Icons.warning_amber_rounded,
                  title: '${data.expiredDrugs} expired products',
                  subtitle: 'Remove or quarantine expired inventory',
                  destination: const AlertDestination(
                    type: AlertDestinationType.inventoryFilteredList,
                    entityId: null,
                  ),
                  tone: _ActionTone.red,
                ),
              if (data.lowStock > 0)
                _AlertTile(
                  icon: Icons.inventory_2_outlined,
                  title: '${data.lowStock} low stock items',
                  subtitle: 'Review items below reorder level',
                  destination: const AlertDestination(
                    type: AlertDestinationType.inventoryFilteredList,
                    entityId: null,
                  ),
                  inventoryFilter: 'low',
                  tone: _ActionTone.amber,
                ),
              if (!BackendConfiguration.isConfigured &&
                  data.vaccinationsDue > 0)
                _AlertTile(
                  icon: Icons.vaccines_outlined,
                  title: '${data.vaccinationsDue} vaccines due',
                  subtitle: 'Patients requiring protocol follow-up',
                  destination: const AlertDestination(
                    type: AlertDestinationType.vaccineScheduleFilteredList,
                  ),
                  tone: _ActionTone.teal,
                ),
              for (final alert in alerts)
                _AlertTile(
                  icon: Icons.notifications_none_rounded,
                  title: alert.title,
                  subtitle: alert.message,
                  destination: const AlertDestination(
                    type: AlertDestinationType.notificationCenter,
                  ),
                  tone: _ActionTone.blue,
                ),
              if (!showingCachedReminders &&
                  reminderFeed.hasValue &&
                  reminderFeed.valueOrNull?.upcoming.isEmpty != false &&
                  reminderFeed.valueOrNull?.alerts.isEmpty != false &&
                  data.expiredDrugs == 0 &&
                  data.lowStock == 0 &&
                  (BackendConfiguration.isConfigured ||
                      data.vaccinationsDue == 0) &&
                  alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: _CalmEmpty(
                    icon: Icons.task_alt_rounded,
                    text: 'Everything looks up to date.',
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ReminderGroupLabel extends StatelessWidget {
  const _ReminderGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: averaText(context).caption.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.event, this.alert = false});

  final ReminderEvent event;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final color = alert
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: Icon(
            alert ? Icons.warning_amber_rounded : Icons.event_outlined,
            color: color,
          ),
          title: Text(event.title, style: averaText(context).listItemTitle),
          subtitle: Text(
            '${event.patientName ?? event.module} • ${DateFormat.MMMd().add_jm().format(event.scheduledAt)}',
            style: averaText(context).listItemSubtitle,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            final route = remoteDashboardActivityRoute({
              'related_entity_type': event.relatedEntityType,
              'record_id': event.relatedEntityId,
              'patient_id': event.patientId,
              'module': event.module,
            });
            if (route != null) context.push(route);
          },
        ),
        const Divider(height: 1, indent: 68),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.destination,
    required this.tone,
    this.inventoryFilter,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final AlertDestination destination;
  final _ActionTone tone;
  final String? inventoryFilter;
  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, tone);
    return Column(
      children: [
        ListTile(
          minVerticalPadding: 14,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title, style: averaText(context).listItemTitle),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: averaText(context).listItemSubtitle,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _openDestination(context),
        ),
        const Divider(height: 1, indent: 68),
      ],
    );
  }

  void _openDestination(BuildContext context) {
    switch (destination.type) {
      case AlertDestinationType.inventoryFilteredList:
        context.push('/inventory?filter=${inventoryFilter ?? 'expired'}');
      case AlertDestinationType.vaccineScheduleFilteredList:
        context.push('/vaccinations?filter=due-now');
      case AlertDestinationType.notificationCenter:
        context.push('/notifications');
      default:
        context.push('/notifications');
    }
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.data});
  final DashboardStats data;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: _SectionHeading(
              title: 'Recent Activity',
              subtitle: 'Latest clinic activity',
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/activity-history'),
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: const Text('View All'),
          ),
        ],
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: data.recentActivity.isEmpty && data.recentVisits.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: _CalmEmpty(
                    icon: Icons.history_toggle_off_outlined,
                    text: 'No recent activity yet.',
                  ),
                )
              : Column(
                  children: [
                    for (final event in data.recentActivity.take(5))
                      _OperationalActivityTile(event: event),
                    if (data.recentActivity.isEmpty)
                      for (final visit in data.recentVisits.take(5))
                        _ActivityTile(visit: visit),
                  ],
                ),
        ),
      ),
    ],
  );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.visit});
  final dynamic visit;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        minVerticalPadding: 14,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.medical_information_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          visit.diagnosis ?? visit.chiefComplaint ?? 'Consultation completed',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: averaText(context).listItemTitle,
        ),
        subtitle: Text(
          '${visit.veterinarian ?? 'Clinic team'}  •  ${DateFormat.MMMd().add_jm().format(visit.visitDate)}',
          style: averaText(context).listItemSubtitle,
        ),
        trailing: SizedBox(
          width: 72,
          child: Align(
            alignment: Alignment.centerRight,
            child: _StatusText(status: visit.status),
          ),
        ),
        onTap: () => context.push('/consultations/${visit.id}'),
      ),
      const Divider(height: 1, indent: 68),
    ],
  );
}

class _OperationalActivityTile extends StatelessWidget {
  const _OperationalActivityTile({required this.event});
  final ClinicActivityTimelineEvent event;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        minVerticalPadding: 14,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            event.type == 'vaccinationRecorded'
                ? Icons.vaccines_outlined
                : Icons.history_rounded,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(event.title, style: averaText(context).listItemTitle),
        subtitle: Text(
          '${_professionalDescription(event)} • ${DateFormat.MMMd().add_jm().format(event.occurredAt)}',
          style: averaText(context).listItemSubtitle,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _openActivity(context, event),
      ),
      const Divider(height: 1, indent: 68),
    ],
  );
}

void _openActivity(BuildContext context, ClinicActivityTimelineEvent event) {
  final route = clinicActivityRoute(event);
  if (route != null) {
    context.push(route);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (_) => _ActivityDetailsSheet(event: event),
  );
}

String _professionalDescription(ClinicActivityTimelineEvent event) {
  final raw = event.description;
  return raw.replaceAllMapped(
    RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?'),
    (match) {
      final date = DateTime.tryParse(match.group(0)!);
      return date == null
          ? match.group(0)!
          : DateFormat.yMMMMd().add_jm().format(date);
    },
  );
}

class _ActivityDetailsSheet extends StatelessWidget {
  const _ActivityDetailsSheet({required this.event});
  final ClinicActivityTimelineEvent event;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Activity Details', style: averaText(context).sectionTitle),
        const SizedBox(height: 16),
        Text(event.title, style: averaText(context).listItemTitle),
        const SizedBox(height: 6),
        Text(
          _professionalDescription(event),
          style: averaText(context).listItemSubtitle,
        ),
        const SizedBox(height: 12),
        Text(
          DateFormat.yMMMMd().add_jm().format(event.occurredAt),
          style: averaText(context).caption,
        ),
        if (event.patientId != null) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.push('/animals/${event.patientId}');
            },
            icon: const Icon(Icons.pets_outlined),
            label: const Text('Open Patient File'),
          ),
        ],
      ],
    ),
  );
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Text(
    status,
    style: averaText(context).caption.copyWith(
      color: Theme.of(context).extension<AppSemanticColors>()!.success,
    ),
  );
}

class _CalmEmpty extends StatelessWidget {
  const _CalmEmpty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 10),
      Text(text, textAlign: TextAlign.center),
    ],
  );
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      for (final height in [150.0, 220.0, 180.0, 250.0])
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _SkeletonBlock(height: height),
        ),
    ],
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) =>
      Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(20),
            ),
          )
          .animate(onPlay: (controller) => controller.repeat())
          .shimmer(duration: 1200.ms);
}

class _QuickAction {
  const _QuickAction(
    this.label,
    this.icon,
    this.path,
    this.tone, {
    this.group = _QuickActionGroup.clinical,
  });
  final String label;
  final IconData icon;
  final String path;
  final _ActionTone tone;
  final _QuickActionGroup group;
}

enum _ActionTone { teal, blue, green, amber, red, violet }

enum _QuickActionGroup { clinical, business }

Color _toneColor(BuildContext context, _ActionTone tone) {
  final semantic = Theme.of(context).extension<AppSemanticColors>()!;
  return switch (tone) {
    _ActionTone.teal => semantic.success,
    _ActionTone.green => semantic.success,
    _ActionTone.blue => Theme.of(context).colorScheme.primary,
    _ActionTone.amber => semantic.warning,
    _ActionTone.red => semantic.danger,
    _ActionTone.violet => const Color(0xFF8264B5),
  };
}

class _AdminConsoleHeader extends StatelessWidget {
  const _AdminConsoleHeader();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Admin Console', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(
        'Full access - Manage staff, roles & clinic settings',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  ).animate().fadeIn(duration: 240.ms).slideY(begin: .025, end: 0);
}

class _StaffGreetingCard extends StatelessWidget {
  const _StaffGreetingCard({
    required this.userName,
    required this.clinicName,
    required this.operatingStatus,
    required this.canManageHours,
  });

  final String userName;
  final String clinicName;
  final AsyncValue<ClinicOperatingStatus> operatingStatus;
  final bool canManageHours;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final status = operatingStatus.valueOrNull;
    final statusColor = _statusColor(context, status?.kind);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, ${_firstName(userName)}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    clinicName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (operatingStatus.isLoading)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (status != null) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            status.label,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        Text(
                          status.weeklySummary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (status.kind ==
                        ClinicOperatingStatusKind.hoursNotConfigured)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          canManageHours
                              ? 'Configure clinic work hours in Clinic Settings.'
                              : 'Contact your clinic administrator.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ] else
                    Text(
                      'Work hours unavailable',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.pets_rounded,
                size: 28,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: .025, end: 0);
  }
}

class _DashboardQuickAccess extends StatelessWidget {
  const _DashboardQuickAccess({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const _CalmEmpty(
        icon: Icons.lock_outline_rounded,
        text: 'No dashboard actions are available for this account.',
      );
    }
    final clinical = actions
        .where((action) => action.group == _QuickActionGroup.clinical)
        .toList(growable: false);
    final business = actions
        .where((action) => action.group == _QuickActionGroup.business)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (clinical.isNotEmpty) ...[
          const _QuickActionSectionHeading(title: 'CLINICAL'),
          const SizedBox(height: 12),
          _DashboardQuickActionGrid(
            key: const Key('dashboard-quick-access-clinical-grid'),
            actions: clinical,
          ),
        ],
        if (business.isNotEmpty) ...[
          if (clinical.isNotEmpty) const SizedBox(height: 28),
          const _QuickActionSectionHeading(title: 'BUSINESS & ADMIN'),
          const SizedBox(height: 12),
          _DashboardQuickActionGrid(
            key: const Key('dashboard-quick-access-business-grid'),
            actions: business,
          ),
        ],
      ],
    );
  }
}

class _QuickActionSectionHeading extends StatelessWidget {
  const _QuickActionSectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
  );
}

class _DashboardQuickActionGrid extends StatelessWidget {
  const _DashboardQuickActionGrid({super.key, required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 112,
      ),
      itemBuilder: (context, index) =>
          _QuickActionTile(action: actions[index]).animate().fadeIn(
            delay: Duration(milliseconds: 25 * index),
            duration: 180.ms,
          ),
    );
  }
}

String _firstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.isEmpty || parts.first.isEmpty ? 'Team Member' : parts.first;
}

Color _statusColor(BuildContext context, ClinicOperatingStatusKind? kind) {
  final semantic = Theme.of(context).extension<AppSemanticColors>()!;
  return switch (kind) {
    ClinicOperatingStatusKind.open => semantic.success,
    ClinicOperatingStatusKind.onBreak => semantic.warning,
    ClinicOperatingStatusKind.opensLater => Theme.of(
      context,
    ).colorScheme.primary,
    ClinicOperatingStatusKind.closedToday ||
    ClinicOperatingStatusKind.closedForDay => Theme.of(
      context,
    ).colorScheme.onSurfaceVariant,
    ClinicOperatingStatusKind.hoursNotConfigured ||
    null => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

List<_QuickAction> _dashboardActionsFor(
  UserSession session,
  DashboardMode mode,
) {
  final actions = <_QuickAction>[];

  void add({
    required String label,
    required IconData icon,
    required String path,
    required _ActionTone tone,
    required String permission,
    required AveraFeature feature,
    _QuickActionGroup group = _QuickActionGroup.clinical,
  }) {
    if (session.can(permission) &&
        FeatureGateService.canAccess(
          subscriptionPlan: session.clinic.subscriptionPlan,
          feature: feature,
        )) {
      actions.add(_QuickAction(label, icon, path, tone, group: group));
    }
  }

  if (mode == DashboardMode.administrative) {
    if (session.can(Permissions.usersView)) {
      actions.add(
        const _QuickAction(
          'Staff & Roles',
          Icons.groups_rounded,
          '/administration/users',
          _ActionTone.blue,
          group: _QuickActionGroup.business,
        ),
      );
    }
    add(
      label: 'Reports',
      icon: Icons.bar_chart_rounded,
      path: '/reports',
      tone: _ActionTone.violet,
      permission: Permissions.reportsExport,
      feature: AveraFeature.reports,
      group: _QuickActionGroup.business,
    );
  }

  add(
    label: 'Registered Pets',
    icon: Icons.pets_rounded,
    path: '/animals',
    tone: _ActionTone.teal,
    permission: Permissions.patientsView,
    feature: AveraFeature.patientRecords,
  );
  add(
    label: 'Consultation',
    icon: Icons.medical_services_rounded,
    path: '/consultations/new',
    tone: _ActionTone.green,
    permission: Permissions.consultationsCreate,
    feature: AveraFeature.consultations,
  );
  add(
    label: 'Vaccine Schedule',
    icon: Icons.vaccines_rounded,
    path: '/vaccinations',
    tone: _ActionTone.teal,
    permission: Permissions.vaccinationsView,
    feature: AveraFeature.vaccinations,
  );
  add(
    label: 'Laboratory',
    icon: Icons.science_outlined,
    path: '/operations/laboratory',
    tone: _ActionTone.blue,
    permission: Permissions.laboratoryView,
    feature: AveraFeature.laboratory,
  );
  add(
    label: 'Hospitalization',
    icon: Icons.local_hospital_outlined,
    path: '/operations/hospitalization',
    tone: _ActionTone.green,
    permission: Permissions.consultationsView,
    feature: AveraFeature.hospitalization,
  );
  add(
    label: 'Billing',
    icon: Icons.payments_outlined,
    path: '/billing',
    tone: _ActionTone.violet,
    permission: Permissions.billingView,
    feature: AveraFeature.billing,
    group: _QuickActionGroup.business,
  );
  add(
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    path: '/inventory',
    tone: _ActionTone.amber,
    permission: Permissions.inventoryView,
    feature: AveraFeature.inventory,
    group: _QuickActionGroup.business,
  );
  add(
    label: 'Revenue',
    icon: Icons.trending_up_rounded,
    path: '/revenue',
    tone: _ActionTone.green,
    permission: Permissions.billingHistory,
    feature: AveraFeature.billing,
    group: _QuickActionGroup.business,
  );
  return actions;
}
