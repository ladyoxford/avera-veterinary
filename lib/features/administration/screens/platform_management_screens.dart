import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/platform_support_session.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/repositories/platform_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';

class PlatformClinicsScreen extends ConsumerWidget {
  const PlatformClinicsScreen({super.key, this.status});

  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinics = ref.watch(platformClinicsProvider(status));
    final offline = ref.watch(platformDataOfflineProvider);
    return _PlatformGuard(
      child: Scaffold(
        appBar: AppBar(
          title: Text(status == null ? 'Clinic Management' : '$status Clinics'),
        ),
        body: clinics.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _PlatformLoadError(
            message: error is ApiException
                ? error.message
                : 'Clinic data could not be loaded.',
            onRetry: () => ref.invalidate(platformClinicsProvider(status)),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const _EmptyState(
                icon: Icons.business_outlined,
                message: 'No clinics match this filter.',
              );
            }
            return Column(
              children: [
                if (offline)
                  const MaterialBanner(
                    content: Text(
                      'Offline: showing the latest clinics cached on this device.',
                    ),
                    actions: [SizedBox.shrink()],
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(platformClinicsProvider(status));
                      await ref.read(platformClinicsProvider(status).future);
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final clinic = items[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            child: Text(
                              clinic.clinicName.substring(0, 1).toUpperCase(),
                            ),
                          ),
                          title: Text(clinic.clinicName),
                          subtitle: Text(
                            '${clinic.subscriptionPlan} • ${clinic.clinicStatus}\n${clinic.city ?? 'Location not recorded'}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.push(
                            '/platform/clinics/${clinic.clinicId}',
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class PlatformClinicDetailScreen extends ConsumerWidget {
  const PlatformClinicDetailScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final supportSession = ref.watch(platformSupportSessionProvider);
    final activation = ref.watch(
      platformAdministratorActivationProvider(clinicId),
    );
    ref.watch(platformClinicProvider(clinicId));
    return _PlatformGuard(
      child: StreamBuilder<List<Clinic>>(
        stream: ref.read(clinicRepositoryProvider).watchPlatformClinics(),
        builder: (context, snapshot) {
          final clinic = snapshot.data?.cast<Clinic?>().firstWhere(
            (item) => item?.clinicId == clinicId,
            orElse: () => null,
          );
          if (clinic == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Clinic Details')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (supportSession?.clinicId == clinic.clinicId)
                  Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.support_agent_rounded),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Platform Support Mode is active. Actions are recorded and no clinic user is being impersonated.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Text(
                  clinic.clinicName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${clinic.city ?? 'Location not recorded'} • ${clinic.email ?? 'No email'}',
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      _DetailRow('Status', clinic.clinicStatus),
                      _DetailRow('Subscription', clinic.subscriptionPlan),
                      _DetailRow(
                        'Registered',
                        clinic.dateRegistered
                            .toLocal()
                            .toString()
                            .split(' ')
                            .first,
                      ),
                    ],
                  ),
                ),
                if (clinic.clinicStatus == 'Active') ...[
                  const SizedBox(height: 16),
                  activation.when(
                    loading: () => const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: LinearProgressIndicator(),
                      ),
                    ),
                    error: (_, __) => const Card(
                      child: ListTile(
                        leading: Icon(Icons.warning_amber_rounded),
                        title: Text('Administrator activation unavailable'),
                        subtitle: Text('Pull to refresh or try again shortly.'),
                      ),
                    ),
                    data: (value) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Clinic Administrator Activation',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(_activationStatusText(value)),
                            if (value.email != null) ...[
                              const SizedBox(height: 4),
                              Text(value.email!),
                            ],
                            if (value.expiresAt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Link expires ${value.expiresAt!.toLocal()}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (value.canResend && session != null) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _resendActivation(context, ref, session),
                                icon: const Icon(
                                  Icons.mark_email_unread_outlined,
                                ),
                                label: const Text('Resend Activation'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: session == null
                          ? null
                          : () => _setStatus(context, ref, session, 'Active'),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Approve / Reactivate'),
                    ),
                    OutlinedButton.icon(
                      onPressed: session == null
                          ? null
                          : () =>
                                _setStatus(context, ref, session, 'Suspended'),
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Suspend'),
                    ),
                    OutlinedButton.icon(
                      onPressed: session == null
                          ? null
                          : () => _setStatus(context, ref, session, 'Pending'),
                      icon: const Icon(Icons.mark_email_unread_outlined),
                      label: const Text('Request Information'),
                    ),
                    if (session != null &&
                        session.canManagePlatform(
                          Permissions.platformSupportAccess,
                        ))
                      OutlinedButton.icon(
                        onPressed: () =>
                            _toggleSupportMode(context, ref, session, clinic),
                        icon: Icon(
                          supportSession?.clinicId == clinic.clinicId
                              ? Icons.logout_rounded
                              : Icons.support_agent_rounded,
                        ),
                        label: Text(
                          supportSession?.clinicId == clinic.clinicId
                              ? 'Exit Support Mode'
                              : 'Open Support Mode',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Support access is intentionally read-only and requires a server-side support session in production.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleSupportMode(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    Clinic clinic,
  ) async {
    final active = ref.read(platformSupportSessionProvider);
    final starting = active?.clinicId != clinic.clinicId;
    try {
      await ref
          .read(clinicRepositoryProvider)
          .recordPlatformSupportAccess(
            actingSession: session,
            clinicId: clinic.clinicId,
            started: starting,
          );
      ref.read(platformSupportSessionProvider.notifier).state = starting
          ? PlatformSupportSession(
              clinicId: clinic.clinicId,
              clinicName: clinic.clinicName,
              startedAt: DateTime.now(),
              startedBy: session.user.userId,
            )
          : null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              starting
                  ? 'Platform Support Mode opened for ${clinic.clinicName}.'
                  : 'Platform Support Mode closed.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    String status,
  ) async {
    try {
      PlatformAdministratorActivation? activation;
      if (status == 'Active') {
        final result = await ref
            .read(platformRepositoryProvider)
            .approveClinic(session: session, clinicId: clinicId);
        activation = result.activation;
      } else {
        await ref
            .read(platformRepositoryProvider)
            .updateClinicStatus(
              session: session,
              clinicId: clinicId,
              status: status,
            );
      }
      ref.invalidate(platformClinicProvider(clinicId));
      ref.invalidate(platformAdministratorActivationProvider(clinicId));
      ref.invalidate(platformClinicsProvider);
      ref.invalidate(platformOverviewProvider);
      if (context.mounted) {
        if (activation?.activationUrl != null) {
          await _showOneTimeActivationLink(context, activation!);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              activation?.deliveryMethod == 'email'
                  ? 'Clinic approved. The activation email was sent.'
                  : 'Clinic status changed to $status.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _resendActivation(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    try {
      final activation = await ref
          .read(platformRepositoryProvider)
          .resendAdministratorActivation(session: session, clinicId: clinicId);
      ref.invalidate(platformAdministratorActivationProvider(clinicId));
      if (context.mounted) {
        if (activation.activationUrl != null) {
          await _showOneTimeActivationLink(context, activation);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              activation.deliveryMethod == 'email'
                  ? 'A new activation email was sent.'
                  : 'Activation delivery could not be completed.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  String _activationStatusText(PlatformAdministratorActivation activation) {
    return switch (activation.status) {
      'Active' => 'Activated',
      'PendingActivation' =>
        activation.deliveryMethod == 'email'
            ? 'Pending activation - email sent'
            : 'Pending activation - manual delivery required',
      'LinkExpired' => 'Activation link expired',
      'LinkRevoked' => 'Activation link revoked',
      'NotProvisioned' => 'Administrator not provisioned',
      'LocalDevelopment' => 'Local development activation',
      _ => activation.status,
    };
  }

  Future<void> _showOneTimeActivationLink(
    BuildContext context,
    PlatformAdministratorActivation activation,
  ) async {
    final link = activation.activationUrl!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Temporary activation-link delivery'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Email delivery is not configured. This secure, single-use link is shown only now. Deliver it privately to the clinic applicant.',
              ),
              const SizedBox(height: 12),
              SelectableText(link),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Activation link copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy activation link'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class PlatformSubscriptionsScreen extends ConsumerWidget {
  const PlatformSubscriptionsScreen({super.key, this.status});
  final String? status;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    ref.watch(platformClinicsProvider(status));
    return _PlatformGuard(
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Subscriptions & Plans',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: StreamBuilder<List<Clinic>>(
          stream: ref
              .read(clinicRepositoryProvider)
              .watchPlatformClinics(status: status),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final clinics = snapshot.data!;
            if (clinics.isEmpty) {
              return const _EmptyState(
                icon: Icons.workspace_premium_outlined,
                message: 'No subscription records match this filter.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: clinics.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => ListTile(
                title: Text(clinics[index].clinicName),
                subtitle: Text(
                  '${clinics[index].subscriptionPlan} • ${clinics[index].clinicStatus}',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Change subscription',
                  onSelected: session == null
                      ? null
                      : (plan) => _changePlan(
                          context,
                          ref,
                          session,
                          clinics[index].clinicId,
                          plan,
                        ),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'Starter', child: Text('Starter')),
                    PopupMenuItem(
                      value: 'Professional',
                      child: Text('Professional'),
                    ),
                    PopupMenuItem(
                      value: 'Enterprise',
                      child: Text('Enterprise'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _changePlan(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    String clinicId,
    String plan,
  ) async {
    try {
      await ref
          .read(platformRepositoryProvider)
          .updateClinicSubscription(
            session: session,
            clinicId: clinicId,
            plan: plan,
          );
      ref.invalidate(platformClinicsProvider);
      ref.invalidate(platformOverviewProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription changed to $plan.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class PlatformUsersScreen extends ConsumerWidget {
  const PlatformUsersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Platform Users')),
      body: StreamBuilder<List<AppUser>>(
        stream: ref.read(clinicRepositoryProvider).watchPlatformUsers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const _EmptyState(
              icon: Icons.people_outline,
              message: 'No user accounts found.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = snapshot.data![index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(user.fullName.substring(0, 1).toUpperCase()),
                ),
                title: Text(user.fullName),
                subtitle: Text(
                  '${user.role} • ${user.accountStatus}\n${user.email}',
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    ),
  );
}

class PlatformAuditLogsScreen extends ConsumerWidget {
  const PlatformAuditLogsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Global Audit Logs')),
      body: StreamBuilder<List<AuditLog>>(
        stream: ref.read(clinicRepositoryProvider).watchPlatformAuditLogs(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const _EmptyState(
              icon: Icons.history_outlined,
              message: 'No administrative activity recorded yet.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final log = snapshot.data![index];
              return ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(log.action),
                subtitle: Text(
                  '${log.details ?? 'No details'}\n${log.createdAt.toLocal()}',
                ),
                isThreeLine: true,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(log.action),
                    content: Text(log.details ?? 'No additional details.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class PlatformOperationsScreen extends StatelessWidget {
  const PlatformOperationsScreen({super.key});

  @override
  Widget build(BuildContext context) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Platform Operations')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          _PlatformRouteCard(
            icon: Icons.business_center_outlined,
            title: 'Clinics',
            subtitle: 'Review, approve, suspend, and support clinics',
            route: '/platform/clinics',
          ),
          _PlatformRouteCard(
            icon: Icons.workspace_premium_outlined,
            title: 'Subscriptions',
            subtitle: 'Manage plans, billing status, payments, and renewals',
            route: '/platform/subscriptions',
          ),
          _PlatformRouteCard(
            icon: Icons.campaign_outlined,
            title: 'Announcements',
            subtitle: 'Create and publish platform notices',
            route: '/platform/notifications',
          ),
          _PlatformRouteCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Platform Administrators',
            subtitle: 'Manage appointed platform accounts',
            route: '/platform/users',
          ),
          if (BackendConfiguration.isLocalMode && kDebugMode)
            _PlatformRouteCard(
              icon: Icons.science_outlined,
              title: 'Developer Settings',
              subtitle: 'Local development and feature-gate tools',
              route: '/platform/developer-settings',
            ),
          _PlatformRouteCard(
            icon: Icons.policy_outlined,
            title: 'Audit & Security',
            subtitle: 'Review immutable platform audit logs',
            route: '/platform/audit',
          ),
          _PlatformRouteCard(
            icon: Icons.settings_outlined,
            title: 'Platform Settings',
            subtitle: 'Security, integrations, email, and configuration',
            route: '/platform/settings',
          ),
        ],
      ),
    ),
  );
}

class PlatformAccountScreen extends ConsumerWidget {
  const PlatformAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Platform Owner Account')),
      body: ref
          .watch(userSessionProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const _EmptyState(
              icon: Icons.error_outline,
              message: 'Account information is unavailable.',
            ),
            data: (session) => ListView(
              padding: const EdgeInsets.fromLTRB(
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.pageTopPadding,
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.bottomContentClearance,
              ),
              children: [
                CircleAvatar(
                  radius: 34,
                  child: Text(
                    session.user.fullName
                        .trim()
                        .split(RegExp(r'\s+'))
                        .take(2)
                        .map((part) => part.isEmpty ? '' : part[0])
                        .join()
                        .toUpperCase(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  session.user.fullName,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).extension<AveraTextStyles>()!.pageTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  'Platform Owner',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).extension<AveraTextStyles>()!.pageSubtitle,
                ),
                const SizedBox(height: 24),
                _PlatformRouteCard(
                  icon: Icons.lock_outline_rounded,
                  title: 'Change Password',
                  subtitle: 'Update your protected Platform Owner credentials',
                  route: '/platform/password',
                ),
                _PlatformRouteCard(
                  icon: Icons.security_outlined,
                  title: 'Security Settings',
                  subtitle: 'Review authentication and platform security',
                  route: '/platform/settings',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _logout(context, ref),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
              ],
            ),
          ),
    ),
  );

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (BackendConfiguration.isLocalMode) {
      await ref.read(localSessionStoreProvider).clear();
    } else {
      await ref.read(authenticationRepositoryProvider).signOut();
    }
    await ref.read(biometricAuthServiceProvider).clear();
    ref.invalidate(biometricEnrollmentProvider);
    ref.invalidate(userSessionProvider);
    if (context.mounted) context.go('/login');
  }
}

class _PlatformRouteCard extends StatelessWidget {
  const _PlatformRouteCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: AveraSpacing.compactRowGap),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      minVerticalPadding: 14,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(route),
    ),
  );
}

class PlatformUtilityScreen extends StatelessWidget {
  const PlatformUtilityScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _EmptyState(icon: icon, message: message),
    ),
  );
}

class PlatformPasswordScreen extends ConsumerStatefulWidget {
  const PlatformPasswordScreen({super.key});
  @override
  ConsumerState<PlatformPasswordScreen> createState() =>
      _PlatformPasswordScreenState();
}

class _PlatformPasswordScreenState
    extends ConsumerState<PlatformPasswordScreen> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  bool saving = false;
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Saving...' : 'Update Password'),
          ),
        ],
      ),
    ),
  );
  Future<void> _save() async {
    if (next.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The new passwords do not match.')),
      );
      return;
    }
    final session = ref.read(userSessionProvider).valueOrNull;
    if (session == null) return;
    setState(() => saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .changeOwnPassword(
            session: session,
            currentPassword: current.text,
            newPassword: next.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password updated.')));
        context.pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _PlatformGuard extends ConsumerWidget {
  const _PlatformGuard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _PlatformDenied(),
      data: (value) =>
          value.isPlatformAccount ? child : const _PlatformDenied(),
    );
  }
}

class _PlatformDenied extends StatelessWidget {
  const _PlatformDenied();
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

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(label), trailing: Text(value));
}

class _PlatformLoadError extends StatelessWidget {
  const _PlatformLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
