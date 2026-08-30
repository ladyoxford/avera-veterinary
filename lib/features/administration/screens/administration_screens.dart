import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/database/app_database.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/staff/professional_title_catalog.dart';
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
  const AddClinicUserScreen({super.key, this.backendModeOverride});

  @visibleForTesting
  final bool? backendModeOverride;

  bool get isBackendMode =>
      backendModeOverride ?? BackendConfiguration.isBackendMode;

  @override
  ConsumerState<AddClinicUserScreen> createState() =>
      _AddClinicUserScreenState();
}

class _AddClinicUserScreenState extends ConsumerState<AddClinicUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _customTitle = TextEditingController();
  String? _selectedRoleId;
  String? _selectedProfessionalTitle;
  String? _submissionError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _customTitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(assignableClinicRolesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add User')),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.pageTopPadding,
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.bottomContentClearance,
          ),
          children: [
            const AveraPageHeader(
              title: 'Invite Staff Member',
              subtitle:
                  'Assign a clinic role. The staff member will create their password from a secure email link.',
            ),
            const SizedBox(height: AveraSpacing.subtitleToContentGap),
            AveraLabeledTextField(
              label: 'Full Name',
              controller: _name,
              hintText: 'Enter full name',
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            AveraLabeledTextField(
              label: 'Email Address',
              controller: _email,
              hintText: 'Enter email address',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  value != null &&
                      RegExp(r'^\S+@\S+\.\S+$').hasMatch(value.trim())
                  ? null
                  : 'Enter a valid email address',
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            AveraLabeledTextField(
              label: 'Phone Number',
              controller: _phone,
              hintText: 'Enter phone number',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            roles.when(
              loading: () => const AveraLabeledDropdownField<String>(
                label: 'Role',
                hintText: 'Loading clinic roles...',
                items: [],
                onChanged: null,
              ),
              error: (_, __) => AveraLabeledFieldCard(
                label: 'Role',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Clinic roles could not be loaded.',
                        style: averaText(context).fieldPlaceholder,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          ref.invalidate(assignableClinicRolesProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? AveraLabeledFieldCard(
                      label: 'Role',
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'No assignable clinic roles are available.',
                              style: averaText(context).fieldPlaceholder,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                ref.invalidate(assignableClinicRolesProvider),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : AveraLabeledDropdownField<String>(
                      key: const Key('add-user-role'),
                      label: 'Role',
                      hintText: 'Select a clinic role',
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      value: items.any((role) => role.id == _selectedRoleId)
                          ? _selectedRoleId
                          : null,
                      items: items
                          .map(
                            (role) => DropdownMenuItem<String>(
                              value: role.id,
                              child: Text(
                                role.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _selectedRoleId = value;
                              _selectedProfessionalTitle = null;
                              _customTitle.clear();
                              _submissionError = null;
                            }),
                      validator: (value) =>
                          value == null ||
                              !items.any((role) => role.id == value)
                          ? 'Please select a valid staff role.'
                          : null,
                    ),
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _professionalTitleField(roles.valueOrNull ?? const []),
            if (_selectedProfessionalTitle == otherProfessionalTitle) ...[
              const SizedBox(height: AveraSpacing.cardGap),
              AveraLabeledTextField(
                label: 'Specify Professional Title',
                controller: _customTitle,
                hintText: 'Enter professional title',
                textInputAction: TextInputAction.done,
                validator: _required,
              ),
            ],
            const SizedBox(height: AveraSpacing.cardGap),
            AveraLabeledFieldCard(
              label: 'Staff Number',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Auto-assigned', style: averaText(context).fieldValue),
                  const SizedBox(height: AveraSpacing.compactRowGap),
                  Text(
                    'The next clinic staff number is assigned securely when the invitation is created.',
                    style: averaText(context).caption,
                  ),
                ],
              ),
            ),
            if (_submissionError != null) ...[
              const SizedBox(height: AveraSpacing.cardGap),
              AveraSurfaceCard(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: AveraSpacing.compactRowGap),
                    Expanded(
                      child: Text(
                        _submissionError!,
                        style: averaText(context).listItemSubtitle.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AveraSpacing.subtitleToContentGap),
            AveraPrimaryActionButton(
              label: 'Create Invitation',
              icon: Icons.send_outlined,
              loading: _saving,
              onPressed: roles.valueOrNull?.isNotEmpty == true ? _invite : null,
            ),
            if (!widget.isBackendMode) ...[
              const SizedBox(height: AveraSpacing.compactRowGap),
              Text(
                'Development mode creates a local activation link for testing.',
                style: averaText(context).caption,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _professionalTitleField(List<ClinicRoleOption> roles) {
    final selectedRole = roles
        .where((role) => role.id == _selectedRoleId)
        .firstOrNull;
    final titles = selectedRole == null
        ? const <String>[]
        : professionalTitlesForRole(selectedRole);
    return AveraLabeledDropdownField<String>(
      key: const Key('add-user-professional-title'),
      label: 'Professional Title',
      hintText: selectedRole == null
          ? 'Select a role first'
          : 'Select professional title',
      value: titles.contains(_selectedProfessionalTitle)
          ? _selectedProfessionalTitle
          : null,
      items: titles
          .map(
            (title) => DropdownMenuItem<String>(
              value: title,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: selectedRole == null || _saving
          ? null
          : (value) => setState(() {
              _selectedProfessionalTitle = value;
              if (value != otherProfessionalTitle) _customTitle.clear();
              _submissionError = null;
            }),
      validator: (value) => selectedRole == null || !titles.contains(value)
          ? 'Please select a professional title.'
          : null,
    );
  }

  Future<void> _invite() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final session = ref.read(userSessionProvider).valueOrNull;
    if (session == null) return;
    final roles = ref.read(assignableClinicRolesProvider).valueOrNull;
    final selectedRole = roles
        ?.where((role) => role.id == _selectedRoleId)
        .firstOrNull;
    if (selectedRole == null) {
      _formKey.currentState?.validate();
      return;
    }
    setState(() => _saving = true);
    try {
      final professionalTitle =
          _selectedProfessionalTitle == otherProfessionalTitle
          ? _customTitle.text.trim()
          : _selectedProfessionalTitle!;
      final invitation = await ref
          .read(clinicRepositoryProvider)
          .inviteClinicUser(
            actingSession: session,
            fullName: _name.text,
            email: _email.text,
            phoneNumber: _phone.text,
            professionalTitle: professionalTitle,
            role: selectedRole,
          );
      if (mounted) {
        if (widget.isBackendMode) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                invitation.emailSubmitted
                    ? 'Invitation submitted'
                    : 'Invitation created',
              ),
              content: Text(
                invitation.emailSubmitted
                    ? 'Staff number ${invitation.staffNumber} was assigned. The activation email was submitted to the email provider for ${_email.text.trim().toLowerCase()}.'
                    : 'Staff number ${invitation.staffNumber} was assigned, but the activation email could not be submitted. Check the email configuration before resending.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          context.pop();
          return;
        }
        final activationLink = invitation.activationLink;
        if (activationLink != null) {
          await Clipboard.setData(ClipboardData(text: activationLink));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Staff number ${invitation.staffNumber} assigned. Development activation link copied.',
              ),
            ),
          );
          context.push(activationLink);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _submissionError = _invitationError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  String _invitationError(Object error) {
    if (error is! ApiException) {
      return 'The invitation could not be created. Please try again.';
    }
    return switch (error.code) {
      'invalid_clinic_role' =>
        'The selected role is no longer available. Please choose another role.',
      'invitation_pending' =>
        'An invitation is already pending for this email. Use Resend Invitation from Staff Management.',
      'email_in_use' => error.message,
      'staff_invitation_forbidden' =>
        'You do not have permission to invite staff members.',
      _ =>
        error.message.trim().isEmpty
            ? 'The invitation could not be created. Please try again.'
            : error.message,
    };
  }
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
