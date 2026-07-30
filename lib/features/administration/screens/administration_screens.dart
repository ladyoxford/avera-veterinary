import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

class ClinicAdministrationScreen extends ConsumerWidget {
  const ClinicAdministrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () => const _LoadingScreen(),
      error: (_, __) => const _AccessDeniedScreen(),
      data: (data) {
        if (!data.isClinicAdministrator) {
          return const _AccessDeniedScreen();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Clinic Administration')),
          body: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.bottomContentClearance,
            ),
            itemCount: 7,
            separatorBuilder: (_, index) => SizedBox(
              height: index == 0
                  ? AveraSpacing.subtitleToContentGap
                  : AveraSpacing.cardGap,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return AveraPageHeader(
                  title: data.clinic.clinicName,
                  subtitle: 'Administration is scoped to this clinic only.',
                );
              }
              final item = <Widget>[
                AveraAdministrationCard(
                  icon: Icons.people_alt_outlined,
                  title: 'Users',
                  subtitle: 'Invite staff, manage roles, status and access.',
                  onTap: () => context.push('/administration/users'),
                ),
                AveraAdministrationCard(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Roles & Permissions',
                  subtitle:
                      'Configure role defaults and effective permissions.',
                  onTap: () => context.push('/administration/roles'),
                ),
                AveraAdministrationCard(
                  icon: Icons.history_outlined,
                  title: 'Audit Logs',
                  subtitle: 'Review sensitive administrative activity.',
                  onTap: () => context.push('/administration/audit'),
                ),
                AveraAdministrationCard(
                  icon: Icons.business_outlined,
                  title: 'Clinic Information',
                  subtitle:
                      'Manage branding, contact details and working hours.',
                  onTap: () => context.push('/settings'),
                ),
                AveraAdministrationCard(
                  icon: Icons.security_outlined,
                  title: 'Security',
                  subtitle:
                      'Manage sessions, password policy and access controls.',
                  onTap: () => context.push('/administration/security'),
                ),
                AveraAdministrationCard(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Subscription',
                  subtitle: 'Review plan, billing and available features.',
                  onTap: () => context.push('/subscription'),
                ),
              ];
              return item[index - 1];
            },
          ),
        );
      },
    );
  }
}

class ClinicUserManagementScreen extends ConsumerWidget {
  const ClinicUserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () => const _LoadingScreen(),
      error: (_, __) => const _AccessDeniedScreen(),
      data: (data) {
        if (!data.can(Permissions.usersView)) {
          return const _AccessDeniedScreen();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('User Management')),
          floatingActionButton: data.can(Permissions.usersCreate)
              ? FloatingActionButton.extended(
                  onPressed: () => context.push('/administration/users/new'),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add User'),
                )
              : null,
          body: StreamBuilder<List<AppUser>>(
            stream: ref
                .read(clinicRepositoryProvider)
                .watchClinicUsers(data.clinic.clinicId),
            builder: (context, snapshot) {
              final users = snapshot.data ?? const <AppUser>[];
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: users.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search users',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    );
                  }
                  final user = users[index - 1];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    leading: CircleAvatar(
                      child: Text(_initials(user.fullName)),
                    ),
                    title: Text(user.fullName),
                    subtitle: Text(
                      '${user.email}\n${user.role} • ${user.accountStatus}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right_rounded),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class AddClinicUserScreen extends ConsumerStatefulWidget {
  const AddClinicUserScreen({super.key});

  @override
  ConsumerState<AddClinicUserScreen> createState() =>
      _AddClinicUserScreenState();
}

class _AddClinicUserScreenState extends ConsumerState<AddClinicUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _title = TextEditingController();
  final _staffNumber = TextEditingController();
  String _role = 'Veterinarian';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _title.dispose();
    _staffNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add User')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full Name'),
              validator: _required,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email Address'),
              validator: (value) =>
                  value != null &&
                      RegExp(r'^\S+@\S+\.\S+$').hasMatch(value.trim())
                  ? null
                  : 'Enter a valid email address',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Professional Title',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items:
                  const [
                        'Veterinarian',
                        'Veterinary Nurse',
                        'Receptionist',
                        'Laboratory Staff',
                        'Pharmacist',
                        'Cashier',
                        'Practice Manager',
                        'Inventory Officer',
                        'Sales Representative',
                        'Custom Role',
                      ]
                      .map(
                        (role) =>
                            DropdownMenuItem(value: role, child: Text(role)),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _role = value ?? _role),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _staffNumber,
              decoration: const InputDecoration(
                labelText: 'Staff Number (optional)',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _invite,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Create Invitation'),
            ),
            const SizedBox(height: 12),
            Text(
              'Invitations are recorded locally for development. Production activation links and email delivery require the configured secure backend.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _invite() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final session = ref.read(userSessionProvider).valueOrNull;
    if (session == null) return;
    setState(() => _saving = true);
    try {
      final link = await ref
          .read(clinicRepositoryProvider)
          .inviteClinicUser(
            actingSession: session,
            fullName: _name.text,
            email: _email.text,
            phoneNumber: _phone.text,
            professionalTitle: _title.text,
            staffNumber: _staffNumber.text,
            role: _role,
          );
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: link));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DEVELOPMENT ONLY: staff activation link copied.'),
          ),
        );
        context.push(link);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
}

class PlatformOwnerDashboardScreen extends ConsumerWidget {
  const PlatformOwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () => const _LoadingScreen(),
      error: (_, __) => const _AccessDeniedScreen(),
      data: (data) {
        if (!data.isPlatformOwner) return const _AccessDeniedScreen();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Platform Owner'),
            actions: [
              IconButton(
                onPressed: () => context.go('/dashboard'),
                icon: const Icon(Icons.logout_rounded),
                tooltip: 'Exit platform administration',
              ),
            ],
          ),
          body: ListView(
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
              const Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _PlatformMetric(
                    'Total Clinics',
                    '1',
                    Icons.business_outlined,
                  ),
                  _PlatformMetric(
                    'Pending Applications',
                    '0',
                    Icons.pending_actions_outlined,
                  ),
                  _PlatformMetric(
                    'Active Clinics',
                    '1',
                    Icons.verified_outlined,
                  ),
                  _PlatformMetric(
                    'Suspended Clinics',
                    '0',
                    Icons.block_outlined,
                  ),
                  _PlatformMetric(
                    'Platform Revenue',
                    '—',
                    Icons.account_balance_wallet_outlined,
                  ),
                  _PlatformMetric(
                    'System Health',
                    'Ready',
                    Icons.monitor_heart_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const AveraAdministrationCard(
                icon: Icons.business_center_outlined,
                title: 'Clinic Directory',
                subtitle: 'Review, approve, suspend, and support clinics',
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              const AveraAdministrationCard(
                icon: Icons.groups_outlined,
                title: 'Platform Administrators',
                subtitle: 'Manage global administration access',
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              const AveraAdministrationCard(
                icon: Icons.history_outlined,
                title: 'Global Audit Logs',
                subtitle: 'Platform-level security and activity history',
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              const AveraAdministrationCard(
                icon: Icons.email_outlined,
                title: 'Email Delivery',
                subtitle: 'Provider status and template configuration',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlatformMetric extends StatelessWidget {
  const _PlatformMetric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Card(
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
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AccessDeniedScreen extends StatelessWidget {
  const _AccessDeniedScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(
              'Access restricted',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'You do not have permission to perform this action.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Return to workspace'),
            ),
          ],
        ),
      ),
    ),
  );
}

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((part) => part.isEmpty ? '' : part[0])
    .join()
    .toUpperCase();
