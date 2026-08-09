import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/inventory_catalog.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/identity_avatar.dart';

class FormerStaffDetailsDialog extends StatefulWidget {
  const FormerStaffDetailsDialog({super.key});

  @override
  State<FormerStaffDetailsDialog> createState() =>
      _FormerStaffDetailsDialogState();
}

class _FormerStaffDetailsDialogState extends State<FormerStaffDetailsDialog> {
  static const _reasons = [
    'Resigned',
    'Dismissed',
    'Retired',
    'Contract ended',
    'Transferred',
    'Temporary placement completed',
    'Other',
  ];

  final _note = TextEditingController();
  String _reason = _reasons.first;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Former Staff Details',
                style: averaText(context).sectionTitle,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Removal reason'),
                selectedItemBuilder: (context) => _reasons
                    .map(
                      (value) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                items: _reasons
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) =>
                    setState(() => _reason = value ?? _reason),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Optional note',
                  hintText: 'Add context for this staff change',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _FormerStaffRemoval(
                        reason: _reason,
                        note: _note.text.trim().isEmpty
                            ? null
                            : _note.text.trim(),
                      ),
                    ),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

enum StaffManagementTab {
  active,
  suspended,
  formerStaff,
  archived;

  String get membershipStatus => switch (this) {
    StaffManagementTab.active => ClinicMembershipStatuses.active,
    StaffManagementTab.suspended => ClinicMembershipStatuses.suspended,
    StaffManagementTab.formerStaff => ClinicMembershipStatuses.formerStaff,
    StaffManagementTab.archived => ClinicMembershipStatuses.archived,
  };
}

bool staffManagementCanAddUser(UserSession session, StaffManagementTab tab) =>
    tab == StaffManagementTab.active &&
    session.isClinicAdministrator &&
    session.can(Permissions.usersCreate);

bool staffManagementCanManageUser(UserSession session, String targetUserId) =>
    session.isClinicAdministrator &&
    session.can(Permissions.staffRolesManage) &&
    targetUserId != session.user.userId;

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  StaffManagementTab _selectedTab = StaffManagementTab.active;
  String _search = '';
  String? _refreshedClinicId;
  Future<void>? _staffRefresh;
  bool _roleChangeInProgress = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_syncSelectedTab);
  }

  void _syncSelectedTab() {
    if (_tabs.indexIsChanging) return;
    final nextTab = StaffManagementTab.values[_tabs.index];
    if (nextTab != _selectedTab) {
      setState(() => _selectedTab = nextTab);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_syncSelectedTab);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSession = ref.watch(userSessionProvider);
    return asyncSession.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _StaffAccessDenied(),
      data: (session) {
        if (!session.can(Permissions.usersView)) {
          return const _StaffAccessDenied();
        }
        if (_refreshedClinicId != session.clinic.clinicId) {
          _refreshedClinicId = session.clinic.clinicId;
          _staffRefresh = ref
              .read(clinicRepositoryProvider)
              .refreshClinicUsers(session);
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('User Management'),
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Active'),
                Tab(text: 'Suspended'),
                Tab(text: 'Former Staff'),
                Tab(text: 'Archived'),
              ],
            ),
          ),
          floatingActionButton: staffManagementCanAddUser(session, _selectedTab)
              ? FloatingActionButton.extended(
                  key: const Key('add-user-fab'),
                  onPressed: () => context.push('/administration/users/new'),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add User'),
                )
              : null,
          body: Column(
            children: [
              if (_staffRefresh != null)
                FutureBuilder<void>(
                  future: _staffRefresh,
                  builder: (context, snapshot) => snapshot.hasError
                      ? MaterialBanner(
                          content: const Text(
                            'Unable to refresh staff. Showing saved clinic users.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => setState(() {
                                _staffRefresh = ref
                                    .read(clinicRepositoryProvider)
                                    .refreshClinicUsers(session);
                              }),
                              child: const Text('Retry'),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: TextField(
                  onChanged: (value) => setState(() => _search = value.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Search staff',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _StaffStatusList(
                      status: StaffManagementTab.active.membershipStatus,
                      session: session,
                      search: _search,
                      onManage: _manage,
                    ),
                    _StaffStatusList(
                      status: StaffManagementTab.suspended.membershipStatus,
                      session: session,
                      search: _search,
                      onManage: _manage,
                    ),
                    _StaffStatusList(
                      status: StaffManagementTab.formerStaff.membershipStatus,
                      session: session,
                      search: _search,
                      onManage: _manage,
                    ),
                    _StaffStatusList(
                      status: StaffManagementTab.archived.membershipStatus,
                      session: session,
                      search: _search,
                      onManage: _manage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _manage(AppUser user, UserSession session) async {
    if (!session.isClinicAdministrator ||
        !session.can(Permissions.staffRolesManage)) {
      return;
    }
    if (user.userId == session.user.userId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The primary Clinic Administrator role cannot be changed here.',
            ),
          ),
        );
      }
      return;
    }
    HapticFeedback.selectionClick();
    if (!mounted) return;
    final deletionBlockReason = await ref
        .read(clinicRepositoryProvider)
        .permanentClinicUserDeletionBlockReason(
          actingSession: session,
          targetUserId: user.userId,
        );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _ManageStaffSheet(
        user: user,
        onResendInvitation: user.accountStatus == 'PendingActivation'
            ? () async {
                Navigator.pop(sheetContext);
                await _perform(
                  () => ref
                      .read(clinicRepositoryProvider)
                      .resendClinicUserInvitation(
                        actingSession: session,
                        targetUserId: user.userId,
                      ),
                  'A new activation invitation was sent to ${user.email}.',
                );
              }
            : null,
        onChangeRole: () async {
          Navigator.pop(sheetContext);
          await _changeRole(user, session);
        },
        onConfigureInventoryAccess: () async {
          Navigator.pop(sheetContext);
          await _configureInventoryAccess(user, session);
        },
        onStatus: (status) async {
          Navigator.pop(sheetContext);
          await _confirmStatus(user, session, status);
        },
        onViewHistory: () async {
          Navigator.pop(sheetContext);
          await _viewHistory(user, session);
        },
        onDeletePermanently: deletionBlockReason == null
            ? () async {
                Navigator.pop(sheetContext);
                await _confirmPermanentDeletion(user, session);
              }
            : null,
      ),
    );
  }

  Future<void> _changeRole(AppUser user, UserSession session) async {
    if (_roleChangeInProgress ||
        !staffManagementCanManageUser(session, user.userId)) {
      return;
    }
    final roles = await ref
        .read(clinicRepositoryProvider)
        .availableClinicRoles(session);
    if (roles.isEmpty || !mounted) return;
    var selected = roles.where((role) => role.name == user.role).firstOrNull;
    selected ??= roles.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Role'),
          content: DropdownButtonFormField<ClinicRoleOption>(
            value: selected,
            items: roles
                .map(
                  (role) =>
                      DropdownMenuItem(value: role, child: Text(role.name)),
                )
                .toList(),
            onChanged: (value) =>
                setDialogState(() => selected = value ?? selected),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update Role'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _roleChangeInProgress = true);
    try {
      await _perform(
        () => ref
            .read(clinicRepositoryProvider)
            .changeClinicUserRole(
              actingSession: session,
              targetUserId: user.userId,
              newRole: selected!.name,
              newRoleId: selected!.id,
            ),
        '${user.fullName}\'s role was updated.',
      );
    } finally {
      if (mounted) setState(() => _roleChangeInProgress = false);
    }
  }

  Future<void> _configureInventoryAccess(
    AppUser user,
    UserSession session,
  ) async {
    final repository = ref.read(clinicRepositoryProvider);
    final currentView = repository.inventoryCategoryIdsForUser(user);
    final currentSell = repository.inventorySellCategoryIdsForUser(user);
    final view = {...currentView};
    final sell = {...currentSell};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Inventory Access'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose the categories this staff member may view or sell.',
                  ),
                  const SizedBox(height: 12),
                  for (final category in InventoryCategories.all)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: view.contains(category.id),
                      title: Text(category.name),
                      subtitle: category.isSellable
                          ? Text(
                              sell.contains(category.id)
                                  ? 'Can view and sell'
                                  : 'View only',
                            )
                          : const Text('View only'),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (enabled) => setDialogState(() {
                        if (enabled ?? false) {
                          view.add(category.id);
                          if (category.isSellable) sell.add(category.id);
                        } else {
                          view.remove(category.id);
                          sell.remove(category.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save Access'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(
      () => repository.setClinicUserInventoryAccess(
        actingSession: session,
        targetUserId: user.userId,
        viewCategoryIds: view,
        sellCategoryIds: sell,
      ),
      'Inventory access updated for ${user.fullName}.',
    );
  }

  Future<void> _confirmStatus(
    AppUser user,
    UserSession session,
    String status,
  ) async {
    final removal = status == ClinicMembershipStatuses.formerStaff
        ? await _collectFormerStaffDetails()
        : null;
    if (!mounted ||
        (status == ClinicMembershipStatuses.formerStaff && removal == null)) {
      return;
    }
    final content = switch (status) {
      ClinicMembershipStatuses.suspended => (
        'Suspend this user?',
        'This user will temporarily lose access to the clinic. Existing clinical and business records will remain unchanged.',
        'Suspend',
      ),
      ClinicMembershipStatuses.formerStaff => (
        'Mark as Former Staff?',
        'This user will be removed from the active clinic staff list and will no longer have access to this clinic. Their previous records and activities will remain available.',
        'Mark as Former Staff',
      ),
      ClinicMembershipStatuses.archived => (
        'Archive this user?',
        'This preserves their history while moving them into a deeper clinic archive.',
        'Archive',
      ),
      _ => (
        'Restore to Active Staff?',
        'This user will regain clinic access according to their assigned role.',
        'Restore',
      ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(content.$1),
        content: Text(content.$2),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(content.$3),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _perform(
      () => ref
          .read(clinicRepositoryProvider)
          .updateClinicUserMembership(
            actingSession: session,
            targetUserId: user.userId,
            membershipStatus: status,
            removalReason: removal?.reason,
            removalNote: removal?.note,
          ),
      '${user.fullName} is now $status.',
    );
  }

  Future<_FormerStaffRemoval?> _collectFormerStaffDetails() async {
    return showDialog<_FormerStaffRemoval>(
      context: context,
      builder: (context) => const FormerStaffDetailsDialog(),
    );
  }

  Future<void> _viewHistory(AppUser user, UserSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _StaffHistorySheet(user: user, session: session),
    );
  }

  Future<void> _confirmPermanentDeletion(
    AppUser user,
    UserSession session,
  ) async {
    final nameConfirmation = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete this user permanently?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This action cannot be undone. Previous medical, financial, inventory and audit records must remain preserved.',
              ),
              const SizedBox(height: 16),
              Text('Type ${user.fullName} to confirm.'),
              TextField(
                controller: nameConfirmation,
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: nameConfirmation.text.trim() == user.fullName
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Delete Permanently'),
            ),
          ],
        ),
      ),
    );
    nameConfirmation.dispose();
    if (confirmed != true) return;
    await _perform(
      () => ref
          .read(clinicRepositoryProvider)
          .permanentlyDeleteClinicUser(
            actingSession: session,
            targetUserId: user.userId,
          ),
      '${user.fullName} was permanently deleted.',
    );
  }

  Future<void> _perform(
    Future<void> Function() operation,
    String message,
  ) async {
    try {
      await operation();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.statusCode == 403
                        ? 'You do not have permission to change staff roles.'
                        : error.message
                  : error.toString().replaceFirst('Bad state: ', ''),
            ),
          ),
        );
      }
    }
  }
}

class _StaffStatusList extends ConsumerWidget {
  const _StaffStatusList({
    required this.status,
    required this.session,
    required this.search,
    required this.onManage,
  });

  final String status;
  final UserSession session;
  final String search;
  final Future<void> Function(AppUser user, UserSession session) onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<AppUser>>(
      stream: ref
          .read(clinicRepositoryProvider)
          .watchClinicUsers(session.clinic.clinicId, membershipStatus: status),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load clinic staff.'));
        }
        final query = search.toLowerCase();
        final users = (snapshot.data ?? const <AppUser>[])
            .where(
              (user) =>
                  query.isEmpty ||
                  user.fullName.toLowerCase().contains(query) ||
                  user.email.toLowerCase().contains(query) ||
                  user.role.toLowerCase().contains(query),
            )
            .toList();
        if (users.isEmpty) {
          return Center(
            child: Text(
              status == ClinicMembershipStatuses.formerStaff
                  ? 'No former staff members.'
                  : status == ClinicMembershipStatuses.archived
                  ? 'No archived staff members.'
                  : 'No $status staff members.',
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AveraSpacing.pageHorizontalPadding),
          itemCount: users.length + 1,
          separatorBuilder: (_, index) =>
              SizedBox(height: index == 0 ? 8 : AveraSpacing.compactRowGap),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Text(
                '${users.length} ${_staffStatusLabel(status)}',
                style: averaText(context).sectionSubtitle,
              );
            }
            final user = users[index - 1];
            return _StaffRow(
              user: user,
              canManage: staffManagementCanManageUser(session, user.userId),
              onManage: () => onManage(user, session),
            );
          },
        );
      },
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.user,
    required this.canManage,
    required this.onManage,
  });

  final AppUser user;
  final bool canManage;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _StaffDetails(user: user)),
      ),
      onLongPress: canManage ? onManage : null,
      child: Padding(
        padding: const EdgeInsets.all(AveraSpacing.cardPadding),
        child: Row(
          children: [
            AveraIdentityAvatar(
              name: user.fullName,
              photoReference: user.profilePhoto,
            ),
            const SizedBox(width: AveraSpacing.compactRowGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName, style: averaText(context).listItemTitle),
                  const SizedBox(height: 3),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: averaText(context).listItemSubtitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _staffRowStatus(user),
                    style: averaText(context).caption,
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

class _ManageStaffSheet extends StatelessWidget {
  const _ManageStaffSheet({
    required this.user,
    required this.onChangeRole,
    required this.onConfigureInventoryAccess,
    required this.onStatus,
    required this.onViewHistory,
    this.onResendInvitation,
    this.onDeletePermanently,
  });
  final AppUser user;
  final Future<void> Function() onChangeRole;
  final Future<void> Function() onConfigureInventoryAccess;
  final Future<void> Function(String status) onStatus;
  final Future<void> Function() onViewHistory;
  final Future<void> Function()? onResendInvitation;
  final Future<void> Function()? onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final status = user.membershipStatus;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage User', style: averaText(context).sectionTitle),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AveraIdentityAvatar(
                name: user.fullName,
                photoReference: user.profilePhoto,
                size: 52,
              ),
              title: Text(
                user.fullName,
                style: averaText(context).listItemTitle,
              ),
              subtitle: Text(
                '${user.email}\n${user.role} | ${user.accountStatus == 'PendingActivation' ? 'Pending Activation' : status}',
                style: averaText(context).listItemSubtitle,
              ),
            ),
            const Divider(),
            if (onResendInvitation != null)
              _ManagementAction(
                icon: Icons.mark_email_unread_outlined,
                title: 'Resend Invitation',
                subtitle:
                    'Revoke the previous link and send a new activation email.',
                onTap: onResendInvitation!,
              ),
            if (status == ClinicMembershipStatuses.active) ...[
              _ManagementAction(
                icon: Icons.swap_horiz_rounded,
                title: 'Change Role',
                subtitle:
                    'Assign a different clinic role and update permissions.',
                onTap: onChangeRole,
              ),
              _ManagementAction(
                icon: Icons.inventory_2_outlined,
                title: 'Inventory Access',
                subtitle:
                    'Choose the Inventory categories this staff member can access.',
                onTap: onConfigureInventoryAccess,
              ),
              _ManagementAction(
                icon: Icons.pause_circle_outline_rounded,
                title: 'Suspend User',
                subtitle:
                    'Temporarily block clinic access without removing records.',
                onTap: () => onStatus(ClinicMembershipStatuses.suspended),
              ),
              _ManagementAction(
                icon: Icons.person_remove_outlined,
                title: 'Mark as Former Staff',
                subtitle:
                    'Remove this user from active clinic staff while preserving records.',
                onTap: () => onStatus(ClinicMembershipStatuses.formerStaff),
              ),
            ] else if (status == ClinicMembershipStatuses.suspended) ...[
              _ManagementAction(
                icon: Icons.play_circle_outline_rounded,
                title: 'Reactivate User',
                subtitle: 'Restore this user\'s access to the clinic.',
                onTap: () => onStatus(ClinicMembershipStatuses.active),
              ),
              _ManagementAction(
                icon: Icons.person_remove_outlined,
                title: 'Mark as Former Staff',
                subtitle:
                    'Remove this user from active clinic staff while preserving records.',
                onTap: () => onStatus(ClinicMembershipStatuses.formerStaff),
              ),
            ] else if (status == ClinicMembershipStatuses.formerStaff) ...[
              _ManagementAction(
                icon: Icons.restore_rounded,
                title: 'Restore to Active Staff',
                subtitle: 'Restore clinic membership and role-based access.',
                onTap: () => onStatus(ClinicMembershipStatuses.active),
              ),
              _ManagementAction(
                icon: Icons.history_rounded,
                title: 'View Staff History',
                subtitle: 'Review role, status and archive activity.',
                onTap: onViewHistory,
              ),
              _ManagementAction(
                icon: Icons.archive_outlined,
                title: 'Archive User',
                subtitle: 'Keep history in a deeper staff archive.',
                onTap: () => onStatus(ClinicMembershipStatuses.archived),
              ),
            ] else ...[
              _ManagementAction(
                icon: Icons.restore_rounded,
                title: 'Restore to Active Staff',
                subtitle: 'Restore clinic membership and role-based access.',
                onTap: () => onStatus(ClinicMembershipStatuses.active),
              ),
              _ManagementAction(
                icon: Icons.history_rounded,
                title: 'View Staff History',
                subtitle: 'Review role, status and archive activity.',
                onTap: onViewHistory,
              ),
              if (onDeletePermanently != null)
                _ManagementAction(
                  icon: Icons.delete_forever_rounded,
                  title: 'Delete Permanently',
                  subtitle: 'Remove an unreferenced archived account.',
                  destructive: true,
                  onTap: onDeletePermanently!,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManagementAction extends StatelessWidget {
  const _ManagementAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final bool destructive;
  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      minVerticalPadding: 12,
      leading: Icon(icon, color: destructive ? error : null),
      title: Text(
        title,
        style: averaText(
          context,
        ).listItemTitle.copyWith(color: destructive ? error : null),
      ),
      subtitle: Text(subtitle, style: averaText(context).listItemSubtitle),
      onTap: onTap,
    );
  }
}

class _StaffHistorySheet extends ConsumerWidget {
  const _StaffHistorySheet({required this.user, required this.session});

  final AppUser user;
  final UserSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: FutureBuilder<List<AuditLog>>(
          future: ref
              .read(clinicRepositoryProvider)
              .clinicUserHistory(
                actingSession: session,
                targetUserId: user.userId,
              ),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final history = snapshot.data ?? const <AuditLog>[];
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Staff History', style: averaText(context).sectionTitle),
                  const SizedBox(height: 4),
                  Text(
                    user.fullName,
                    style: averaText(context).sectionSubtitle,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: history.isEmpty
                        ? const Center(
                            child: Text('No staff-management history yet.'),
                          )
                        : ListView.separated(
                            itemCount: history.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = history[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.history_rounded),
                                title: Text(
                                  _historyLabel(item.action),
                                  style: averaText(context).listItemTitle,
                                ),
                                subtitle: Text(
                                  '${item.createdAt.toLocal()}\n${item.details ?? ''}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: averaText(context).listItemSubtitle,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FormerStaffRemoval {
  const _FormerStaffRemoval({required this.reason, this.note});

  final String reason;
  final String? note;
}

String _historyLabel(String action) => switch (action) {
  'staff.role_changed' => 'Role changed',
  'staff.suspended' => 'User suspended',
  'staff.reactivated' => 'Restored to active staff',
  'staff.marked_former' => 'Marked as former staff',
  'staff.archived' => 'Archived',
  'staff.permanent_deletion_attempted' => 'Permanent deletion attempted',
  'staff.permanent_deletion_completed' => 'Permanently deleted',
  'staff.action_blocked' => 'Action blocked',
  _ => action,
};

class _StaffDetails extends StatelessWidget {
  const _StaffDetails({required this.user});
  final AppUser user;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff Profile')),
    body: ListView(
      padding: const EdgeInsets.all(AveraSpacing.pageHorizontalPadding),
      children: [
        AveraPageHeader(
          title: user.fullName,
          subtitle: '${user.role} | ${user.membershipStatus}',
        ),
        const SizedBox(height: AveraSpacing.subtitleToContentGap),
        AveraLabeledFieldCard(
          label: 'EMAIL',
          child: Text(user.email, style: averaText(context).fieldValue),
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraLabeledFieldCard(
          label: 'ROLE',
          child: Text(user.role, style: averaText(context).fieldValue),
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraLabeledFieldCard(
          label: 'STATUS',
          child: Text(
            user.membershipStatus,
            style: averaText(context).fieldValue,
          ),
        ),
      ],
    ),
  );
}

class _StaffAccessDenied extends StatelessWidget {
  const _StaffAccessDenied();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Text('You do not have permission to view clinic users.'),
    ),
  );
}

String _staffStatusLabel(String status) => switch (status) {
  ClinicMembershipStatuses.active => 'active staff members',
  ClinicMembershipStatuses.suspended => 'suspended staff members',
  ClinicMembershipStatuses.formerStaff => 'former staff members',
  ClinicMembershipStatuses.archived => 'archived staff members',
  _ => 'staff members',
};

String _staffRowStatus(AppUser user) {
  final date = switch (user.membershipStatus) {
    ClinicMembershipStatuses.formerStaff => user.formerStaffAt,
    ClinicMembershipStatuses.archived => user.archivedAt,
    _ => null,
  };
  final parts = <String>[
    user.role,
    user.accountStatus == 'PendingActivation'
        ? 'Pending Activation'
        : user.membershipStatus,
  ];
  if (date != null) {
    parts.add(date.toLocal().toIso8601String().split('T').first);
  }
  if (user.removalReason != null && user.removalReason!.isNotEmpty) {
    parts.add(user.removalReason!);
  }
  return parts.join(' | ');
}
