import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/auth_remote_data_source.dart';
import '../../../core/services/biometric_auth_service.dart';
import '../../../core/database/app_database.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

enum CustomRoleEditorOutcome { created, cancelled }

class CustomRoleEditorResult {
  const CustomRoleEditorResult(this.outcome, {this.roleName});

  final CustomRoleEditorOutcome outcome;
  final String? roleName;
}

class ClinicRolesPermissionsScreen extends ConsumerWidget {
  const ClinicRolesPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () => const _AdministrationLoading(),
      error: (_, __) => const _AdministrationDenied(),
      data: (value) {
        if (!_canManageRoles(value)) return const _AdministrationDenied();
        return Scaffold(
          appBar: AppBar(title: const Text('Roles & Permissions')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _createCustomRole(context, ref, value),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Custom Role'),
          ),
          body: StreamBuilder<List<ClinicRoleAccess>>(
            stream: ref.read(clinicRepositoryProvider).watchClinicRoles(value),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.hasError) {
                return const _AdministrationLoadError();
              }
              if (!roleSnapshot.hasData) {
                return const _AdministrationLoading();
              }
              return StreamBuilder<List<AppUser>>(
                stream: ref
                    .read(clinicRepositoryProvider)
                    .watchClinicUsers(value.clinic.clinicId),
                builder: (context, staffSnapshot) {
                  final staff = staffSnapshot.data ?? const <AppUser>[];
                  final roles = roleSnapshot.data!
                      .where((role) => !role.isArchived)
                      .toList(growable: false);
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AveraSpacing.pageHorizontalPadding,
                      AveraSpacing.pageTopPadding,
                      AveraSpacing.pageHorizontalPadding,
                      AveraSpacing.bottomContentClearance,
                    ),
                    itemCount: roles.length + 1,
                    separatorBuilder: (_, index) => SizedBox(
                      height: index == 0
                          ? AveraSpacing.subtitleToContentGap
                          : AveraSpacing.cardGap,
                    ),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const AveraPageHeader(
                          title: 'Roles & Permissions',
                          subtitle:
                              'Control what each clinic role can view and manage.',
                        );
                      }
                      final role = roles[index - 1];
                      final activeStaff = staff
                          .where(
                            (user) =>
                                user.role == role.name &&
                                user.membershipStatus ==
                                    ClinicMembershipStatuses.active,
                          )
                          .length;
                      return AveraAdministrationCard(
                        icon: role.isCustom
                            ? Icons.tune_rounded
                            : Icons.badge_outlined,
                        title: role.name,
                        subtitle:
                            '${role.description}\n$activeStaff active staff | ${role.permissions.length} permissions${role.isCustom ? ' | Custom' : ' | Default'}',
                        onTap: () => context.push(
                          '/administration/roles/${Uri.encodeComponent(role.name)}',
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  static Future<void> _createCustomRole(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    final result = await showDialog<CustomRoleEditorResult>(
      context: context,
      builder: (_) => CustomRoleEditorDialog(session: session),
    );
    if (!context.mounted ||
        result?.outcome != CustomRoleEditorOutcome.created) {
      return;
    }
    final roleName = result?.roleName?.trim();
    if (roleName == null || roleName.isEmpty) return;
    context.push('/administration/roles/${Uri.encodeComponent(roleName)}');
  }
}

class CustomRoleEditorDialog extends ConsumerStatefulWidget {
  const CustomRoleEditorDialog({super.key, required this.session});
  final UserSession session;

  @override
  ConsumerState<CustomRoleEditorDialog> createState() =>
      _CustomRoleEditorDialogState();
}

class _CustomRoleEditorDialogState
    extends ConsumerState<CustomRoleEditorDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  bool _isClosing = false;

  bool get _hasUnsavedChanges =>
      _name.text.trim().isNotEmpty || _description.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _requestCancel() async {
    if (_isClosing || !mounted) return;
    if (_hasUnsavedChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (confirmContext) => AlertDialog(
          title: const Text('Discard custom role?'),
          content: const Text(
            'Your unsaved role name and permission changes will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('Keep Editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(confirmContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return;
    }
    _close(const CustomRoleEditorResult(CustomRoleEditorOutcome.cancelled));
  }

  void _close(CustomRoleEditorResult result) {
    if (_isClosing || !mounted) return;
    setState(() => _isClosing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _create() async {
    if (_saving || _isClosing) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .createClinicCustomRole(
            actingSession: widget.session,
            roleName: _name.text,
            description: _description.text,
            permissions: const <String>{},
          );
      if (!mounted) return;
      _close(
        CustomRoleEditorResult(
          CustomRoleEditorOutcome.created,
          roleName: _name.text.trim(),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    } finally {
      if (mounted && !_isClosing) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<CustomRoleEditorResult>(
    canPop: _isClosing,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _requestCancel();
    },
    child: AlertDialog(
      title: const Text('Create Custom Role'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_saving && !_isClosing,
            decoration: const InputDecoration(labelText: 'Role name'),
          ),
          const SizedBox(height: AveraSpacing.compactRowGap),
          TextField(
            controller: _description,
            maxLines: 2,
            enabled: !_saving && !_isClosing,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving || _isClosing ? null : _requestCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _isClosing ? null : _create,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    ),
  );
}

class ClinicRoleDetailsScreen extends ConsumerStatefulWidget {
  const ClinicRoleDetailsScreen({super.key, required this.roleName});
  final String roleName;

  @override
  ConsumerState<ClinicRoleDetailsScreen> createState() =>
      _ClinicRoleDetailsScreenState();
}

class _ClinicRoleDetailsScreenState
    extends ConsumerState<ClinicRoleDetailsScreen> {
  Set<String>? _draftPermissions;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () => const _AdministrationLoading(),
      error: (_, __) => const _AdministrationDenied(),
      data: (value) {
        if (!_canManageRoles(value)) return const _AdministrationDenied();
        return StreamBuilder<List<ClinicRoleAccess>>(
          stream: ref.read(clinicRepositoryProvider).watchClinicRoles(value),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const _AdministrationLoadError();
            if (!snapshot.hasData) return const _AdministrationLoading();
            ClinicRoleAccess? role;
            for (final item in snapshot.data!) {
              if (item.name == widget.roleName) {
                role = item;
                break;
              }
            }
            if (role == null || role.isArchived) {
              return const _AdministrationNotFound('This role is unavailable.');
            }
            final resolvedRole = role;
            final permissions = _draftPermissions ?? resolvedRole.permissions;
            final groups = <String, List<String>>{};
            for (final permission in clinicPermissionDescriptions.keys) {
              (groups[clinicPermissionGroup(permission)] ??= []).add(
                permission,
              );
            }
            return Scaffold(
              appBar: AppBar(title: const Text('Role Details')),
              body: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AveraSpacing.pageHorizontalPadding,
                  AveraSpacing.pageTopPadding,
                  AveraSpacing.pageHorizontalPadding,
                  AveraSpacing.bottomContentClearance,
                ),
                itemCount: groups.length + 2,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AveraSpacing.cardGap),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return AveraPageHeader(
                      title: resolvedRole.name,
                      subtitle: resolvedRole.description,
                    );
                  }
                  if (index == groups.length + 1) {
                    return AveraPrimaryActionButton(
                      label: 'Save Role Permissions',
                      icon: Icons.save_rounded,
                      loading: _saving,
                      onPressed: () => _save(value, resolvedRole, permissions),
                    );
                  }
                  final entry = groups.entries.elementAt(index - 1);
                  return _PermissionGroupCard(
                    title: entry.key,
                    permissions: entry.value,
                    selected: permissions,
                    onChanged: (permission, enabled) => setState(() {
                      final next = {...permissions};
                      enabled ? next.add(permission) : next.remove(permission);
                      _draftPermissions = next;
                    }),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _save(
    UserSession session,
    ClinicRoleAccess role,
    Set<String> permissions,
  ) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .saveClinicRolePermissions(
            actingSession: session,
            roleName: role.name,
            permissions: permissions,
          );
      ref.invalidate(userSessionProvider);
      if (mounted) {
        setState(() => _draftPermissions = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${role.name} permissions updated.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PermissionGroupCard extends StatefulWidget {
  const _PermissionGroupCard({
    required this.title,
    required this.permissions,
    required this.selected,
    required this.onChanged,
  });
  final String title;
  final List<String> permissions;
  final Set<String> selected;
  final void Function(String permission, bool enabled) onChanged;

  @override
  State<_PermissionGroupCard> createState() => _PermissionGroupCardState();
}

class _PermissionGroupCardState extends State<_PermissionGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(
        horizontal: AveraSpacing.cardPadding,
        vertical: 4,
      ),
      childrenPadding: const EdgeInsets.only(
        left: AveraSpacing.cardPadding,
        right: AveraSpacing.cardPadding,
        bottom: AveraSpacing.cardPadding,
      ),
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
      title: Text(
        widget.title.toUpperCase(),
        style: averaText(context).sectionLabel,
      ),
      subtitle: Text(
        '${widget.permissions.where(widget.selected.contains).length} of ${widget.permissions.length} permissions enabled',
        style: averaText(context).caption,
      ),
      trailing: Icon(
        _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
      ),
      children: [
        for (final permission in widget.permissions)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _permissionTitle(permission),
              style: averaText(context).fieldValue,
            ),
            subtitle: Text(
              clinicPermissionDescriptions[permission] ?? permission,
              style: averaText(context).caption,
            ),
            value: widget.selected.contains(permission),
            onChanged: (enabled) => widget.onChanged(permission, enabled),
          ),
      ],
    ),
  );
}

enum ClinicAuditCategory {
  all,
  users,
  clinical,
  appointments,
  vaccinations,
  inventory,
  billing,
  security,
  clinicSettings,
  subscription;

  String get label => switch (this) {
    ClinicAuditCategory.all => 'All',
    ClinicAuditCategory.users => 'Users',
    ClinicAuditCategory.clinical => 'Clinical',
    ClinicAuditCategory.appointments => 'Appointments',
    ClinicAuditCategory.vaccinations => 'Vaccinations',
    ClinicAuditCategory.inventory => 'Inventory',
    ClinicAuditCategory.billing => 'Billing',
    ClinicAuditCategory.security => 'Security',
    ClinicAuditCategory.clinicSettings => 'Clinic Settings',
    ClinicAuditCategory.subscription => 'Subscription',
  };
}

class ClinicAuditLogsScreen extends ConsumerStatefulWidget {
  const ClinicAuditLogsScreen({
    super.key,
    this.initialCategory = ClinicAuditCategory.all,
  });
  final ClinicAuditCategory initialCategory;

  @override
  ConsumerState<ClinicAuditLogsScreen> createState() =>
      _ClinicAuditLogsScreenState();
}

class _ClinicAuditLogsScreenState extends ConsumerState<ClinicAuditLogsScreen> {
  late ClinicAuditCategory _category = widget.initialCategory;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () => const _AdministrationLoading(),
      error: (_, __) => const _AdministrationDenied(),
      data: (value) {
        if (!value.can(Permissions.auditLogsView)) {
          return const _AdministrationDenied();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Audit Logs')),
          body: StreamBuilder<List<AuditLog>>(
            stream: ref
                .read(clinicRepositoryProvider)
                .watchClinicAuditLogs(value),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const _AdministrationLoadError();
              if (!snapshot.hasData) return const _AdministrationLoading();
              final entries = snapshot.data!
                  .where((log) => _matchesAudit(log, _category, _query))
                  .toList(growable: false);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AveraSpacing.pageHorizontalPadding,
                      AveraSpacing.pageTopPadding,
                      AveraSpacing.pageHorizontalPadding,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AveraPageHeader(
                          title: 'Audit Logs',
                          subtitle:
                              'Review important activity performed within this clinic.',
                        ),
                        const SizedBox(
                          height: AveraSpacing.subtitleToContentGap,
                        ),
                        TextField(
                          onChanged: (value) =>
                              setState(() => _query = value.trim()),
                          decoration: const InputDecoration(
                            hintText: 'Search audit logs',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                        const SizedBox(height: AveraSpacing.compactRowGap),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: ClinicAuditCategory.values.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final category =
                                  ClinicAuditCategory.values[index];
                              return ChoiceChip(
                                label: Text(category.label),
                                selected: category == _category,
                                onSelected: (_) =>
                                    setState(() => _category = category),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(
                            child: Text(
                              'No audit activity found for the selected filters.',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              AveraSpacing.pageHorizontalPadding,
                              AveraSpacing.cardGap,
                              AveraSpacing.pageHorizontalPadding,
                              AveraSpacing.bottomContentClearance,
                            ),
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const SizedBox(
                              height: AveraSpacing.compactRowGap,
                            ),
                            itemBuilder: (context, index) => _AuditRow(
                              log: entries[index],
                              onTap: () => context.push(
                                '/administration/audit/${entries[index].id}',
                                extra: entries[index],
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.log, required this.onTap});
  final AuditLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = _safeAuditDetails(log.details);
    final actor = details['actingUserName']?.toString() ?? 'Clinic activity';
    final subject = _auditSubject(details, log);
    return AveraAdministrationCard(
      icon: _auditIcon(log.action),
      title: _auditTitle(log.action),
      subtitle:
          '$actor${subject == null ? '' : ' | $subject'}\n${_formatDateTime(log.createdAt)}',
      onTap: onTap,
    );
  }
}

class AuditEventDetailsScreen extends StatelessWidget {
  const AuditEventDetailsScreen({super.key, required this.log});
  final AuditLog log;

  @override
  Widget build(BuildContext context) {
    final details = _safeAuditDetails(log.details);
    final visible = details.entries
        .where((entry) => entry.value != null)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Event')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        itemCount: visible.length + 1,
        separatorBuilder: (_, __) =>
            const SizedBox(height: AveraSpacing.cardGap),
        itemBuilder: (context, index) {
          if (index == 0) {
            return AveraPageHeader(
              title: _auditTitle(log.action),
              subtitle:
                  '${_auditCategoryFor(log.action).label} | ${_formatDateTime(log.createdAt)}',
            );
          }
          final entry = visible[index - 1];
          return AveraLabeledFieldCard(
            label: _labelForAuditKey(entry.key),
            child: Text(
              _formatAuditValue(entry.value),
              style: averaText(context).fieldValue,
            ),
          );
        },
      ),
    );
  }
}

class ClinicSecurityScreen extends ConsumerWidget {
  const ClinicSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () => const _AdministrationLoading(),
      error: (_, __) => const _AdministrationDenied(),
      data: (value) {
        if (!value.isClinicAdministrator) return const _AdministrationDenied();
        return Scaffold(
          appBar: AppBar(title: const Text('Security')),
          body: StreamBuilder<List<AppUser>>(
            stream: ref
                .read(clinicRepositoryProvider)
                .watchClinicUsers(value.clinic.clinicId),
            builder: (context, snapshot) {
              final staff = snapshot.data ?? const <AppUser>[];
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AveraSpacing.pageHorizontalPadding,
                  AveraSpacing.pageTopPadding,
                  AveraSpacing.pageHorizontalPadding,
                  AveraSpacing.bottomContentClearance,
                ),
                itemCount: 7,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AveraSpacing.cardGap),
                itemBuilder: (context, index) => switch (index) {
                  0 => const AveraPageHeader(
                    title: 'Security',
                    subtitle:
                        'Manage sessions, password policy and clinic access controls.',
                  ),
                  1 => _SecuritySection(
                    title: 'Active Sessions',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value.user.fullName,
                          style: averaText(context).listItemTitle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This device | Current local session',
                          style: averaText(context).listItemSubtitle,
                        ),
                        const SizedBox(height: AveraSpacing.compactRowGap),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _revokeCurrentLocalSession(context, ref, value),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Revoke Current Local Session'),
                        ),
                      ],
                    ),
                  ),
                  2 => _SecuritySection(
                    title: 'Password Policy',
                    child: Text(
                      'Local password validation is enforced at account activation and reset. Central policy administration and password-history rules require the configured secure backend.',
                      style: averaText(context).listItemSubtitle,
                    ),
                  ),
                  3 => _SecuritySection(
                    title: 'Biometric Login',
                    child: _BiometricSecurityControl(session: value),
                  ),
                  4 => _SecuritySection(
                    title: 'Two-Factor Authentication',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Authenticator app and recovery codes',
                          style: averaText(context).fieldValue,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          BackendConfiguration.isLocalMode
                              ? 'Available when AVERA is connected to its secure backend.'
                              : 'Require a time-based code after password sign-in.',
                          style: averaText(context).caption,
                        ),
                        const SizedBox(height: AveraSpacing.compactRowGap),
                        OutlinedButton.icon(
                          onPressed: value.can(Permissions.twoFactorManageSelf)
                              ? () =>
                                    context.push('/administration/security/2fa')
                              : null,
                          icon: const Icon(Icons.security_rounded),
                          label: const Text('Manage 2FA'),
                        ),
                      ],
                    ),
                  ),
                  5 => _SecuritySection(
                    title: 'Access Controls',
                    child: Text(
                      '${staff.where((user) => user.role == 'Clinic Administrator' && user.membershipStatus == ClinicMembershipStatuses.active).length} active clinic administrators\n${staff.where((user) => user.membershipStatus == ClinicMembershipStatuses.suspended).length} suspended staff accounts',
                      style: averaText(context).listItemSubtitle,
                    ),
                  ),
                  _ => _SecuritySection(
                    title: 'Security Activity',
                    child: TextButton.icon(
                      onPressed: () => context.push(
                        '/administration/audit?category=security',
                      ),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('View All Security Activity'),
                    ),
                  ),
                },
              );
            },
          ),
        );
      },
    );
  }

  static Future<void> _revokeCurrentLocalSession(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke current local session?'),
        content: const Text('You will be returned to sign in on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revoke Session'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(clinicRepositoryProvider)
        .recordClinicSecurityEvent(
          actingSession: session,
          action: 'security.local_session_revoked',
          details: 'Current local session revoked by the signed-in user.',
        );
    await ref.read(localSessionStoreProvider).clear();
    ref.invalidate(userSessionProvider);
    if (context.mounted) context.go('/login');
  }
}

class _BiometricSecurityControl extends ConsumerWidget {
  const _BiometricSecurityControl({required this.session});
  final UserSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<bool>(
    future: ref.read(biometricAuthServiceProvider).isSupported,
    builder: (context, support) {
      final enrollment = ref.watch(biometricEnrollmentProvider);
      final enabled =
          enrollment.valueOrNull?.userId == session.user.userId &&
          enrollment.valueOrNull?.clinicId == session.clinic.clinicId;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            enabled
                ? 'Enabled on this device'
                : 'Use device biometrics to sign in',
            style: averaText(context).fieldValue,
          ),
          const SizedBox(height: 4),
          Text(
            support.data == false
                ? 'No enrolled biometric method is available on this device.'
                : 'AVERA stores no password or biometric template.',
            style: averaText(context).caption,
          ),
          const SizedBox(height: AveraSpacing.compactRowGap),
          OutlinedButton.icon(
            onPressed: support.data != true
                ? null
                : enabled
                ? () async {
                    await ref.read(biometricAuthServiceProvider).clear();
                    ref.invalidate(biometricEnrollmentProvider);
                  }
                : () => _enable(context, ref),
            icon: Icon(
              enabled ? Icons.fingerprint_rounded : Icons.fingerprint_outlined,
            ),
            label: Text(
              enabled ? 'Disable Biometric Login' : 'Enable Biometric Login',
            ),
          ),
        ],
      );
    },
  );

  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final password = await _requestPassword(context);
    if (password == null || !context.mounted) return;
    try {
      if (BackendConfiguration.isLocalMode) {
        final verified = await ref
            .read(clinicRepositoryProvider)
            .authenticateUser(
              username: session.user.email,
              password: password,
              rememberMe: true,
            );
        if (verified?.user.userId != session.user.userId) {
          throw const ApiException(
            'reauthentication_failed',
            'Your password could not be confirmed.',
          );
        }
      } else {
        final platform = Theme.of(context).platform.name;
        final deviceId = await ref
            .read(offlineAuthorizationServiceProvider)
            .deviceId();
        final remote = await ref
            .read(authenticationRepositoryProvider)
            .signIn(
              email: session.user.email,
              password: password,
              deviceId: deviceId,
              platform: platform,
            );
        if (remote.userId != session.user.userId) {
          throw const ApiException(
            'reauthentication_failed',
            'Your password could not be confirmed.',
          );
        }
      }
      final approved = await ref
          .read(biometricAuthServiceProvider)
          .authenticate(reason: 'Confirm biometrics to enable AVERA sign in');
      if (!approved) return;
      await ref
          .read(biometricAuthServiceProvider)
          .enable(
            BiometricEnrollment(
              userId: session.user.userId,
              clinicId: session.clinic.clinicId,
              email: session.user.email,
            ),
          );
      ref.invalidate(biometricEnrollmentProvider);
      await ref
          .read(clinicRepositoryProvider)
          .recordClinicSecurityEvent(
            actingSession: session,
            action: 'security.biometric_enabled',
            details: 'Biometric login enabled on this device.',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric login enabled.')),
        );
      }
    } on MfaRequiredException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete a fresh password and 2FA sign-in before enabling biometrics.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<String?> _requestPassword(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm your password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: averaText(context).sectionLabel),
        const SizedBox(height: AveraSpacing.compactRowGap),
        child,
      ],
    ),
  );
}

class _AdministrationLoading extends StatelessWidget {
  const _AdministrationLoading();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AdministrationLoadError extends StatelessWidget {
  const _AdministrationLoadError();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Text('Administration information could not be loaded.'),
    ),
  );
}

class _AdministrationDenied extends StatelessWidget {
  const _AdministrationDenied();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(AveraSpacing.largeCardPadding),
        child: Text(
          'You do not have permission to access this administration area.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class _AdministrationNotFound extends StatelessWidget {
  const _AdministrationNotFound(this.message);
  final String message;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(message)));
}

bool _canManageRoles(UserSession session) =>
    session.isClinicAdministrator &&
    session.can(Permissions.usersAssignPermissions);

bool _matchesAudit(AuditLog log, ClinicAuditCategory category, String query) {
  if (category != ClinicAuditCategory.all &&
      _auditCategoryFor(log.action) != category) {
    return false;
  }
  if (query.isEmpty) {
    return true;
  }
  final haystack =
      '${log.action} ${log.entityType ?? ''} ${log.entityId ?? ''} ${log.details ?? ''}'
          .toLowerCase();
  return haystack.contains(query.toLowerCase());
}

ClinicAuditCategory _auditCategoryFor(String action) {
  if (action.startsWith('staff.') ||
      action.startsWith('role.') ||
      action.contains('user')) {
    return ClinicAuditCategory.users;
  }
  if (action.startsWith('security') ||
      action == 'login' ||
      action.contains('password')) {
    return ClinicAuditCategory.security;
  }
  if (action.startsWith('subscription.')) {
    return ClinicAuditCategory.subscription;
  }
  if (action.contains('inventory') || action.contains('stock')) {
    return ClinicAuditCategory.inventory;
  }
  if (action.contains('invoice') ||
      action.contains('billing') ||
      action.contains('payment')) {
    return ClinicAuditCategory.billing;
  }
  if (action.contains('appointment')) {
    return ClinicAuditCategory.appointments;
  }
  if (action.contains('vaccination')) {
    return ClinicAuditCategory.vaccinations;
  }
  if (action.startsWith('clinic.') || action.contains('numbering')) {
    return ClinicAuditCategory.clinicSettings;
  }
  return ClinicAuditCategory.clinical;
}

IconData _auditIcon(String action) => switch (_auditCategoryFor(action)) {
  ClinicAuditCategory.users => Icons.people_alt_outlined,
  ClinicAuditCategory.security => Icons.security_outlined,
  ClinicAuditCategory.subscription => Icons.workspace_premium_outlined,
  ClinicAuditCategory.inventory => Icons.inventory_2_outlined,
  ClinicAuditCategory.billing => Icons.receipt_long_outlined,
  ClinicAuditCategory.appointments => Icons.calendar_month_outlined,
  ClinicAuditCategory.vaccinations => Icons.vaccines_outlined,
  ClinicAuditCategory.clinicSettings => Icons.business_outlined,
  _ => Icons.medical_information_outlined,
};

String _auditTitle(String action) => action
    .split('.')
    .map((part) => part.replaceAll('_', ' '))
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

Map<String, Object?> _safeAuditDetails(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <String, Object?>{};
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, Object?>.fromEntries(
        decoded.entries
            .where((entry) => !_isSecretAuditKey(entry.key.toString()))
            .map(
              (entry) => MapEntry(
                entry.key.toString(),
                _redactAuditValue(entry.value),
              ),
            ),
      );
    }
  } catch (_) {}
  return _isSecretAuditValue(raw)
      ? const <String, Object?>{}
      : {'details': raw};
}

bool _isSecretAuditKey(String value) {
  final key = value.toLowerCase();
  return key.contains('password') ||
      key.contains('token') ||
      key.contains('secret') ||
      key.contains('otp') ||
      key.contains('hash');
}

bool _isSecretAuditValue(String value) {
  final text = value.toLowerCase();
  return text.contains('password=') ||
      text.contains('token=') ||
      text.contains('refresh token');
}

Object? _redactAuditValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.fromEntries(
      value.entries
          .where((entry) => !_isSecretAuditKey(entry.key.toString()))
          .map(
            (entry) =>
                MapEntry(entry.key.toString(), _redactAuditValue(entry.value)),
          ),
    );
  }
  if (value is List) {
    return value.map(_redactAuditValue).toList(growable: false);
  }
  return value;
}

String? _auditSubject(Map<String, Object?> details, AuditLog log) =>
    details['targetUserName']?.toString() ??
    details['roleName']?.toString() ??
    log.entityId;

String _formatAuditValue(Object? value) => value is List
    ? value.join(', ')
    : value is Map
    ? value.entries
          .map((entry) => '${entry.key}: ${_formatAuditValue(entry.value)}')
          .join('\n')
    : value?.toString() ?? 'Not recorded';

String _labelForAuditKey(String key) => key
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    )
    .replaceAll('_', ' ')
    .split(' ')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

String _permissionTitle(String permission) =>
    _labelForAuditKey(permission.replaceAll('.', ' '));

String _friendlyError(Object error) =>
    error.toString().replaceFirst('Bad state: ', '');

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day}/${local.month}/${local.year} | $hour:$minute $period';
}
