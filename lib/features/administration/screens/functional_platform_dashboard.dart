import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/remote/api_client.dart';

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
            title: const Text('Platform Owner'),
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
              PopupMenuButton<String>(
                tooltip: 'Account menu',
                onSelected: (value) => _menu(context, ref, value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'profile', child: Text('My Profile')),
                  PopupMenuItem(value: 'security', child: Text('Security')),
                  PopupMenuItem(
                    value: 'password',
                    child: Text('Change Password'),
                  ),
                  PopupMenuItem(value: 'theme', child: Text('Theme')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'logout', child: Text('Logout')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: CircleAvatar(
                    child: Text(_initials(data.user.fullName)),
                  ),
                ),
              ),
            ],
          ),
          body: StreamBuilder<List<Clinic>>(
            stream: ref.read(clinicRepositoryProvider).watchPlatformClinics(),
            builder: (context, clinicsSnapshot) {
              if (!clinicsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<List<AppUser>>(
                stream: ref.read(clinicRepositoryProvider).watchPlatformUsers(),
                builder: (context, usersSnapshot) {
                  final clinics = clinicsSnapshot.data!;
                  final users = usersSnapshot.data ?? const <AppUser>[];
                  int count(String status) => clinics
                      .where((clinic) => clinic.clinicStatus == status)
                      .length;
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'AVERA Platform Control',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Global clinic oversight and platform operations',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _Metric(
                            'Total Clinics',
                            '${clinics.length}',
                            Icons.business_outlined,
                            () => context.push('/platform/clinics'),
                          ),
                          _Metric(
                            'Pending Applications',
                            '${count('Pending')}',
                            Icons.pending_actions_outlined,
                            () => context.push(
                              '/platform/clinics?status=Pending',
                            ),
                          ),
                          _Metric(
                            'Active Clinics',
                            '${count('Active')}',
                            Icons.verified_outlined,
                            () =>
                                context.push('/platform/clinics?status=Active'),
                          ),
                          _Metric(
                            'Suspended Clinics',
                            '${count('Suspended')}',
                            Icons.block_outlined,
                            () => context.push(
                              '/platform/clinics?status=Suspended',
                            ),
                          ),
                          _Metric(
                            'Expired Subscriptions',
                            '0',
                            Icons.event_busy_outlined,
                            () => context.push(
                              '/platform/subscriptions?status=Expired',
                            ),
                          ),
                          _Metric(
                            'Monthly Platform Revenue',
                            '—',
                            Icons.account_balance_wallet_outlined,
                            () => context.push('/platform/revenue'),
                          ),
                          _Metric(
                            'Active Users',
                            '${users.where((user) => user.accountStatus == 'Active').length}',
                            Icons.groups_outlined,
                            () => context.push('/platform/users'),
                          ),
                          _Metric(
                            'Email Delivery',
                            'Ready',
                            Icons.email_outlined,
                            () => context.push('/platform/email'),
                          ),
                          _Metric(
                            'Storage Usage',
                            '—',
                            Icons.storage_outlined,
                            () => context.push('/platform/storage'),
                          ),
                          _Metric(
                            'System Health',
                            'Ready',
                            Icons.monitor_heart_outlined,
                            () => context.push('/platform/settings'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Recent Clinic Registrations',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (clinics.isEmpty)
                        const _InlineEmpty('No clinics have registered yet.'),
                      for (final clinic in clinics.take(3))
                        _RouteRow(
                          icon: Icons.business_outlined,
                          title: clinic.clinicName,
                          subtitle:
                              '${clinic.subscriptionPlan} • ${clinic.clinicStatus}',
                          onTap: () => context.push(
                            '/platform/clinics/${clinic.clinicId}',
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Platform Operations',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      _RouteRow(
                        icon: Icons.business_center_outlined,
                        title: 'Clinic Directory',
                        subtitle:
                            'Review, approve, suspend, and support clinics',
                        onTap: () => context.push('/platform/clinics'),
                      ),
                      _RouteRow(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Subscriptions',
                        subtitle: 'Manage plans and billing status',
                        onTap: () => context.push('/platform/subscriptions'),
                      ),
                      if (BackendConfiguration.isLocalMode)
                        _RouteRow(
                          icon: Icons.science_outlined,
                          title: 'Developer Settings',
                          subtitle:
                              'Simulate plans for local feature-gate testing',
                          onTap: () =>
                              context.push('/platform/developer-settings'),
                        ),
                      _RouteRow(
                        icon: Icons.groups_outlined,
                        title: 'Platform User Management',
                        subtitle: 'View platform-wide account activity',
                        onTap: () => context.push('/platform/users'),
                      ),
                      _RouteRow(
                        icon: Icons.history_outlined,
                        title: 'Recent Administrative Activity',
                        subtitle: 'Open global audit logs',
                        onTap: () => context.push('/platform/audit'),
                      ),
                      _RouteRow(
                        icon: Icons.notifications_none_rounded,
                        title: 'Platform Notifications',
                        subtitle: 'Review platform alerts',
                        onTap: () => context.push('/platform/notifications'),
                      ),
                      _RouteRow(
                        icon: Icons.email_outlined,
                        title: 'Email Delivery Status',
                        subtitle: 'Provider configuration and delivery logs',
                        onTap: () => context.push('/platform/email'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, String value) async {
    if (value == 'logout') {
      if (BackendConfiguration.isLocalMode) {
        await ref.read(localSessionStoreProvider).clear();
      } else {
        await ref.read(authenticationRepositoryProvider).signOut();
      }
      ref.invalidate(userSessionProvider);
      if (context.mounted) context.go('/login');
      return;
    }
    context.push(
      value == 'theme' ? '/platform/settings' : '/platform/password',
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.onTap);
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 16),
              Text(label),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
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

String _initials(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((part) => part.isEmpty ? '' : part[0])
    .join()
    .toUpperCase();
