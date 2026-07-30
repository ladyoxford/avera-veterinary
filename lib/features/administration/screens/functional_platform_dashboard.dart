import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/platform_repository.dart';
import '../../../core/theme/app_theme.dart';

class FunctionalPlatformOwnerDashboardScreen extends ConsumerWidget {
  const FunctionalPlatformOwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _OwnerDenied(),
      data: (data) {
        if (!data.isPlatformOwner) return const _OwnerDenied();
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Platform Owner Console',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).extension<AveraTextStyles>()!.listItemTitle,
            ),
            actions: [
              IconButton(
                onPressed: () => context.push('/platform/notifications'),
                icon: const Icon(Icons.notifications_none_rounded),
                tooltip: 'Platform notifications',
              ),
              IconButton(
                onPressed: () => context.push('/platform/settings'),
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Platform settings',
              ),
              Semantics(
                label: 'Platform Owner account',
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => context.go('/platform/account'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: CircleAvatar(child: Text('PO')),
                  ),
                ),
              ),
            ],
          ),
          body: ref
              .watch(platformOverviewProvider)
              .when(
                loading: () => const _OverviewLoading(),
                error: (error, _) => _OverviewError(
                  onRetry: () => ref.invalidate(platformOverviewProvider),
                ),
                data: (overview) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(platformOverviewProvider);
                    await ref.read(platformOverviewProvider.future);
                  },
                  child: _OverviewBody(overview: overview),
                ),
              ),
        );
      },
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({required this.overview});

  final PlatformOverviewSnapshot overview;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth >= 1100 ? 1040.0 : 760.0;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.pageTopPadding,
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.bottomContentClearance,
          ),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: constraints.maxWidth < contentWidth
                    ? constraints.maxWidth
                    : contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionLabel('Overview'),
                    _StatGrid(
                      children: [
                        _StatCard(
                          label: 'Total Clinics',
                          value: '${overview.totalClinics}',
                          icon: Icons.business_outlined,
                          color: scheme.primary,
                          onTap: () => context.go('/platform/clinics'),
                        ),
                        _StatCard(
                          label: 'Active Clinics',
                          value: '${overview.activeClinics}',
                          icon: Icons.check_circle_outline_rounded,
                          color: semantic.success,
                          badge: 'LIVE',
                          onTap: () =>
                              context.go('/platform/clinics?status=Active'),
                        ),
                        _StatCard(
                          label: 'Pending Applications',
                          value: '${overview.pendingApplications}',
                          icon: Icons.pending_actions_outlined,
                          color: semantic.warning,
                          badge: '${overview.pendingApplications} NEW',
                          onTap: () =>
                              context.go('/platform/clinics?status=Pending'),
                        ),
                        _StatCard(
                          label: 'Suspended Clinics',
                          value: '${overview.suspendedClinics}',
                          icon: Icons.block_outlined,
                          color: semantic.danger,
                          onTap: () =>
                              context.go('/platform/clinics?status=Suspended'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AveraSpacing.sectionGap),
                    const _SectionLabel('Business Health'),
                    _StatGrid(
                      children: [
                        _StatCard(
                          label: 'Active Users',
                          value: '${overview.activeUsers}',
                          icon: Icons.groups_outlined,
                          color: scheme.primary,
                          onTap: () =>
                              context.go('/platform/users?status=Active'),
                        ),
                        _StatCard(
                          label: 'Expired Subscriptions',
                          value: '${overview.expiredSubscriptions}',
                          icon: Icons.event_busy_outlined,
                          color: semantic.warning,
                          onTap: () => context.go(
                            '/platform/subscriptions?status=Expired',
                          ),
                        ),
                        _StatCard(
                          fullWidth: true,
                          label: 'Monthly Platform Revenue',
                          value: overview.monthlyRevenue == null
                              ? 'No revenue data yet'
                              : _money(
                                  overview.monthlyRevenue!,
                                  overview.currency,
                                ),
                          icon: Icons.payments_outlined,
                          color: semantic.success,
                          compactValue: true,
                          onTap: () => context.go('/platform/revenue'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AveraSpacing.sectionGap),
                    const _SectionLabel('System Status'),
                    _StatGrid(
                      children: [
                        _StatCard(
                          label: 'Email Delivery',
                          value:
                              overview.emailDeliveryStatus ??
                              'Health data unavailable',
                          icon: Icons.mail_outline_rounded,
                          color: scheme.onSurfaceVariant,
                          compactValue: true,
                          onTap: () => context.go('/platform/email'),
                        ),
                        _StatCard(
                          label: 'System Health',
                          value:
                              overview.systemHealthStatus ??
                              'Health data unavailable',
                          icon: Icons.monitor_heart_outlined,
                          color: scheme.onSurfaceVariant,
                          compactValue: true,
                          onTap: () => context.go('/platform/settings'),
                        ),
                        _StatCard(
                          fullWidth: true,
                          label: 'Storage Usage',
                          value: _storageLabel(overview),
                          icon: Icons.storage_outlined,
                          color: scheme.primary,
                          compactValue: true,
                          onTap: () => context.go('/platform/storage'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AveraSpacing.sectionGap),
                    const _SectionLabel('Recent Clinic Registrations'),
                    if (overview.recentClinics.isEmpty)
                      const _InlineEmpty(
                        icon: Icons.business_outlined,
                        message: 'No clinics have registered yet.',
                      )
                    else
                      for (final clinic in overview.recentClinics) ...[
                        _ClinicCard(clinic: clinic),
                        const SizedBox(height: AveraSpacing.compactRowGap),
                      ],
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => context.go('/platform/clinics'),
                        child: const Text('View all clinics'),
                      ),
                    ),
                    const SizedBox(height: AveraSpacing.sectionGap),
                    const _SectionLabel('Platform Operations'),
                    _OperationGroup(
                      label: 'Manage',
                      operations: [
                        _Operation(
                          icon: Icons.business_center_outlined,
                          title: 'Clinics',
                          description:
                              'Review, approve, suspend, and support clinics',
                          route: '/platform/clinics',
                        ),
                        _Operation(
                          icon: Icons.workspace_premium_outlined,
                          title: 'Subscriptions',
                          description:
                              'Manage plans, billing status, payments, and renewals',
                          route: '/platform/subscriptions',
                        ),
                        _Operation(
                          icon: Icons.campaign_outlined,
                          title: 'Announcements',
                          description: 'Create and publish platform notices',
                          route: '/platform/notifications',
                        ),
                      ],
                    ),
                    const SizedBox(height: AveraSpacing.cardGap),
                    _OperationGroup(
                      label: 'Admin',
                      operations: [
                        _Operation(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Platform Administrators',
                          description: 'Manage appointed platform accounts',
                          route: '/platform/users',
                        ),
                        if (BackendConfiguration.isLocalMode && kDebugMode)
                          _Operation(
                            icon: Icons.science_outlined,
                            title: 'Developer Settings',
                            description:
                                'Manage local development and feature-gate tools',
                            route: '/platform/developer-settings',
                          ),
                      ],
                    ),
                    const SizedBox(height: AveraSpacing.cardGap),
                    _OperationGroup(
                      label: 'Security',
                      operations: const [
                        _Operation(
                          icon: Icons.policy_outlined,
                          title: 'Audit & Security',
                          description:
                              'Review immutable platform audit logs and security events',
                          route: '/platform/audit',
                        ),
                        _Operation(
                          icon: Icons.settings_outlined,
                          title: 'Platform Settings',
                          description:
                              'Manage security, integrations, email delivery, and configuration',
                          route: '/platform/settings',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).extension<AveraTextStyles>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AveraSpacing.compactRowGap),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: text.sectionLabel),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});
  final List<_StatCard> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720 ? 4 : 2;
      final width =
          (constraints.maxWidth -
              (AveraSpacing.compactRowGap * (columns - 1))) /
          columns;
      return Wrap(
        spacing: AveraSpacing.compactRowGap,
        runSpacing: AveraSpacing.compactRowGap,
        children: [
          for (final child in children)
            SizedBox(
              width: child.fullWidth ? constraints.maxWidth : width,
              child: child,
            ),
        ],
      );
    },
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge,
    this.fullWidth = false,
    this.compactValue = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? badge;
  final bool fullWidth;
  final bool compactValue;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).extension<AveraTextStyles>()!;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 136),
          child: Padding(
            padding: const EdgeInsets.all(AveraSpacing.cardPadding),
            child: fullWidth
                ? Row(
                    children: [
                      Expanded(child: _content(text, scheme)),
                      _icon(),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _icon(),
                          if (badge != null)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  badge!,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.caption.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _content(text, scheme),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _content(AveraTextStyles text, ColorScheme scheme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: text.caption.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      Text(
        value,
        maxLines: compactValue ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: compactValue
            ? text.listItemTitle
            : text.pageTitle.copyWith(fontSize: 26),
      ),
    ],
  );

  Widget _icon() => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, size: 19, color: color),
  );
}

class _ClinicCard extends StatelessWidget {
  const _ClinicCard({required this.clinic});
  final Clinic clinic;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).extension<AveraTextStyles>()!;
    final color = _statusColor(context, clinic.clinicStatus);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/platform/clinics/${clinic.clinicId}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_hospital_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clinic.clinicName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.listItemTitle,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(clinic.subscriptionPlan, style: text.caption),
                        _StatusPill(label: clinic.clinicStatus, color: color),
                        Text(_date(clinic.dateRegistered), style: text.caption),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationGroup extends StatelessWidget {
  const _OperationGroup({required this.label, required this.operations});
  final String label;
  final List<_Operation> operations;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).extension<AveraTextStyles>()!;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(label.toUpperCase(), style: text.sectionLabel),
          ),
          for (var index = 0; index < operations.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 64,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            _OperationRow(operation: operations[index]),
          ],
        ],
      ),
    );
  }
}

class _Operation {
  const _Operation({
    required this.icon,
    required this.title,
    required this.description,
    required this.route,
  });
  final IconData icon;
  final String title;
  final String description;
  final String route;
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({required this.operation});
  final _Operation operation;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).extension<AveraTextStyles>()!;
    return InkWell(
      onTap: () => context.go(operation.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(operation.icon, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(operation.title, style: text.listItemTitle),
                  const SizedBox(height: 2),
                  Text(operation.description, style: text.listItemSubtitle),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(context).extension<AveraTextStyles>()!.caption.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AveraSpacing.largeCardPadding),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _OverviewLoading extends StatelessWidget {
  const _OverviewLoading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AveraSpacing.pageHorizontalPadding),
    children: [
      Container(
        height: 28,
        width: 220,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      const SizedBox(height: 24),
      for (var index = 0; index < 6; index++) ...[
        Card(
          child: SizedBox(
            height: 112,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: index == 0 ? 3 : 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );
}

class _OverviewError extends StatelessWidget {
  const _OverviewError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AveraSpacing.largeCardPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42),
          const SizedBox(height: 12),
          const Text('Platform data is unavailable.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _OwnerDenied extends StatelessWidget {
  const _OwnerDenied();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => context.go('/login'),
        child: const Text('Return to Sign In'),
      ),
    ),
  );
}

Color _statusColor(BuildContext context, String status) {
  final semantic = Theme.of(context).extension<AppSemanticColors>()!;
  return switch (status.toLowerCase()) {
    'active' => semantic.success,
    'pending' || 'pendingapproval' || 'expired' => semantic.warning,
    'suspended' || 'rejected' => semantic.danger,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _money(double amount, String currency) =>
    '$currency ${amount.toStringAsFixed(2)}';

String _storageLabel(PlatformOverviewSnapshot overview) {
  final used = overview.storageUsedBytes;
  final available = overview.storageAvailableBytes;
  if (used == null || available == null) return 'Health data unavailable';
  final total = used + available;
  if (total <= 0) return 'No storage data yet';
  return '${(used / total * 100).toStringAsFixed(1)}% used';
}
