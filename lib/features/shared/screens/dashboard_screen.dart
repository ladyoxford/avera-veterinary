import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/services/clinic_operating_status_service.dart';
import '../../../core/services/dashboard_mode_resolver.dart';
import '../../../core/services/feature_gate_service.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/branded_app_bar.dart';
import 'cloud_dashboard_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (BackendConfiguration.isConfigured) return const CloudDashboardScreen();
    final stats = ref.watch(dashboardStatsProvider);
    final session = ref.watch(userSessionProvider);
    final notifications = ref.watch(notificationsProvider);
    final operatingStatus = ref.watch(clinicOperatingStatusProvider);

    return Scaffold(
      appBar: const BrandedAppBar(),
      body: stats.when(
        loading: () => const _DashboardSkeleton(),
        error: (error, _) =>
            Center(child: Text('Unable to load dashboard: $error')),
        data: (data) {
          final sessionData = session.valueOrNull;
          final dashboardMode = sessionData == null
              ? DashboardMode.staff
              : DashboardModeResolver.resolve(sessionData);
          final actions = sessionData == null
              ? const <_QuickAction>[]
              : _dashboardActionsFor(sessionData, dashboardMode);
          final alerts =
              notifications.valueOrNull
                  ?.where((item) => !item.isRead)
                  .take(4)
                  .toList() ??
              const [];
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dashboardStatsProvider);
              ref.invalidate(notificationsProvider);
            },
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 124),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          _DashboardQuickActionGrid(actions: actions),
                          const SizedBox(height: 36),
                          _AlertsAndActivity(data: data, alerts: alerts),
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
              label: const Text('Register patient'),
            ),
    );
  }
}

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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ],
  );
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
        'Schedule',
        Icons.calendar_month_rounded,
        '/appointments',
        _ActionTone.blue,
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(action.path),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(action.icon, color: color),
              ),
              const SizedBox(height: 10),
              Text(
                action.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
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
  const _AlertsAndActivity({required this.data, required this.alerts});
  final DashboardStats data;
  final List<dynamic> alerts;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sideBySide = constraints.maxWidth >= 900;
      final alertsPanel = _AlertPanel(data: data, alerts: alerts);
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
  const _AlertPanel({required this.data, required this.alerts});
  final DashboardStats data;
  final List<dynamic> alerts;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionHeading(
        title: 'Alerts & Upcoming Activity',
        subtitle: 'Items that need attention',
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (data.expiredDrugs > 0)
                _AlertTile(
                  icon: Icons.warning_amber_rounded,
                  title: '${data.expiredDrugs} expired products',
                  subtitle: 'Remove or quarantine expired inventory',
                  path: '/inventory?filter=expired',
                  tone: _ActionTone.red,
                ),
              if (data.lowStock > 0)
                _AlertTile(
                  icon: Icons.inventory_2_outlined,
                  title: '${data.lowStock} low stock items',
                  subtitle: 'Review items below reorder level',
                  path: '/inventory?filter=low',
                  tone: _ActionTone.amber,
                ),
              if (data.vaccinationsDue > 0)
                _AlertTile(
                  icon: Icons.vaccines_outlined,
                  title: '${data.vaccinationsDue} vaccines due',
                  subtitle: 'Patients requiring protocol follow-up',
                  path: '/vaccinations',
                  tone: _ActionTone.teal,
                ),
              for (final alert in alerts)
                _AlertTile(
                  icon: Icons.notifications_none_rounded,
                  title: alert.title,
                  subtitle: alert.message,
                  path: '/notifications',
                  tone: _ActionTone.blue,
                ),
              if (data.expiredDrugs == 0 &&
                  data.lowStock == 0 &&
                  data.vaccinationsDue == 0 &&
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

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.tone,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String path;
  final _ActionTone tone;
  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, tone);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(path),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.data});
  final DashboardStats data;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionHeading(
        title: 'Recent Activity',
        subtitle: 'Latest consultation records',
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: data.recentVisits.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: _CalmEmpty(
                    icon: Icons.history_toggle_off_outlined,
                    text: 'No recent activity yet.',
                  ),
                )
              : Column(
                  children: [
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
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    leading: CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(
        Icons.medical_information_outlined,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
    title: Text(
      visit.diagnosis ?? visit.chiefComplaint ?? 'Consultation completed',
    ),
    subtitle: Text(
      '${visit.veterinarian ?? 'Clinic team'}  •  ${DateFormat.MMMd().add_jm().format(visit.visitDate)}',
    ),
    trailing: _StatusText(status: visit.status),
    onTap: () => context.push('/consultations/${visit.id}'),
  );
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Text(
    status,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
  const _QuickAction(this.label, this.icon, this.path, this.tone);
  final String label;
  final IconData icon;
  final String path;
  final _ActionTone tone;
}

enum _ActionTone { teal, blue, green, amber, red, violet }

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

class _DashboardQuickActionGrid extends StatelessWidget {
  const _DashboardQuickActionGrid({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const _CalmEmpty(
        icon: Icons.lock_outline_rounded,
        text: 'No dashboard actions are available for this account.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640
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
              _QuickActionTile(action: actions[index]).animate().fadeIn(
                delay: Duration(milliseconds: 25 * index),
                duration: 180.ms,
              ),
        );
      },
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
  }) {
    if (session.can(permission) &&
        FeatureGateService.canAccess(
          subscriptionPlan: session.clinic.subscriptionPlan,
          feature: feature,
        )) {
      actions.add(_QuickAction(label, icon, path, tone));
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
        ),
      );
    }
    if (session.can(Permissions.usersAssignPermissions) ||
        session.can(Permissions.usersAssignRoles)) {
      actions.add(
        const _QuickAction(
          'Permissions',
          Icons.admin_panel_settings_outlined,
          '/administration',
          _ActionTone.violet,
        ),
      );
    }
    if (session.can(Permissions.clinicSettingsView)) {
      actions.add(
        const _QuickAction(
          'Clinic Settings',
          Icons.settings_outlined,
          '/settings',
          _ActionTone.teal,
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
    label: 'Schedule',
    icon: Icons.calendar_month_rounded,
    path: '/appointments',
    tone: _ActionTone.blue,
    permission: Permissions.appointmentsView,
    feature: AveraFeature.schedule,
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
  );
  add(
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    path: '/inventory',
    tone: _ActionTone.amber,
    permission: Permissions.inventoryView,
    feature: AveraFeature.inventory,
  );
  return actions;
}
