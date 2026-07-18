import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/repositories/clinic_repository.dart';

class PlatformClinicsScreen extends ConsumerWidget {
  const PlatformClinicsScreen({super.key, this.status});

  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PlatformGuard(
      child: Scaffold(
        appBar: AppBar(
          title: Text(status == null ? 'Clinic Management' : '$status Clinics'),
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
                icon: Icons.business_outlined,
                message: 'No clinics match this filter.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: clinics.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final clinic = clinics[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                  onTap: () =>
                      context.push('/platform/clinics/${clinic.clinicId}'),
                );
              },
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
                    if (kDebugMode && clinic.clinicStatus == 'Active')
                      OutlinedButton.icon(
                        onPressed: session == null
                            ? null
                            : () => _copyActivationLink(context, ref, session),
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Copy Development Activation Link'),
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

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    String status,
  ) async {
    try {
      await ref
          .read(clinicRepositoryProvider)
          .updateClinicStatus(
            actingSession: session,
            clinicId: clinicId,
            status: status,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clinic status changed to $status.')),
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

  Future<void> _copyActivationLink(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    try {
      final link = await ref
          .read(clinicRepositoryProvider)
          .createDevelopmentActivationLink(
            actingSession: session,
            clinicId: clinicId,
          );
      await Clipboard.setData(ClipboardData(text: link));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DEVELOPMENT ONLY: activation link copied.'),
          ),
        );
        context.push(link);
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

class PlatformSubscriptionsScreen extends ConsumerWidget {
  const PlatformSubscriptionsScreen({super.key, this.status});
  final String? status;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
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
          .read(clinicRepositoryProvider)
          .updateClinicSubscription(
            actingSession: session,
            clinicId: clinicId,
            plan: plan,
          );
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
      data: (value) => value.isPlatformOwner ? child : const _PlatformDenied(),
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
