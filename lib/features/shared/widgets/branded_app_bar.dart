import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/models/alert_destination.dart';
import '../../../core/remote/api_client.dart';
import 'avera_logo.dart';

class BrandedAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const BrandedAppBar({super.key, this.title});

  final String? title;

  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    final notifications = ref.watch(notificationsProvider);
    final compact = MediaQuery.sizeOf(context).width < 620;
    final unreadCount =
        notifications.valueOrNull
            ?.where(
              (item) =>
                  InAppNotificationStatusStorage.fromStorage(
                    item.status,
                    isRead: item.isRead,
                  ) ==
                  InAppNotificationStatus.unread,
            )
            .length ??
        0;

    return AppBar(
      toolbarHeight: 84,
      titleSpacing: compact ? 16 : 24,
      title: session.when(
        loading: () => const _BrandTitle(clinicName: 'Loading clinic'),
        error: (_, __) => const _BrandTitle(clinicName: 'AVERA'),
        data: (data) => Row(
          children: [
            const AveraCompactLogo(size: 44),
            const SizedBox(width: 12),
            Expanded(child: _BrandTitle(clinicName: data.clinic.clinicName)),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.push('/notifications'),
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text('$unreadCount'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        session.maybeWhen(
          data: (data) => Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: _UserAvatarButton(
              name: data.user.fullName,
              role: data.user.role,
              clinicName: data.clinic.clinicName,
              profilePhoto: data.user.profilePhoto,
              ref: ref,
            ),
          ),
          orElse: () => const SizedBox(width: 16),
        ),
      ],
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle({required this.clinicName});
  final String clinicName;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'AVERA',
        style: Theme.of(context).textTheme.titleLarge,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 2),
      Text(
        clinicName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    ],
  );
}

class _UserAvatarButton extends StatelessWidget {
  const _UserAvatarButton({
    required this.name,
    required this.role,
    required this.clinicName,
    required this.profilePhoto,
    required this.ref,
  });

  final String name;
  final String role;
  final String clinicName;
  final String? profilePhoto;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open account menu for $name',
    child: InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => _showMenu(context),
      child: _UserAvatar(name: name, profilePhoto: profilePhoto),
    ),
  );

  Future<void> _showMenu(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _UserAvatar(name: name, profilePhoto: profilePhoto, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$role  •  $clinicName',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('My Profile'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Account Settings'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/settings');
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Theme'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/settings');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Log out'),
              onTap: () async {
                if (BackendConfiguration.isLocalMode) {
                  await ref.read(localSessionStoreProvider).clear();
                } else {
                  await ref.read(authenticationRepositoryProvider).signOut();
                }
                await ref.read(biometricAuthServiceProvider).clear();
                ref.invalidate(biometricEnrollmentProvider);
                ref.invalidate(userSessionProvider);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.name,
    required this.profilePhoto,
    this.size = 46,
  });
  final String name;
  final String? profilePhoto;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _avatarColors[name.hashCode.abs() % _avatarColors.length];
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    final remotePhoto = profilePhoto?.startsWith('http') ?? false;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .6),
        ),
      ),
      child: ClipOval(
        child: remotePhoto
            ? Image.network(
                profilePhoto!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _Initials(initials: initials, color: color),
              )
            : _Initials(initials: initials, color: color),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials, required this.color});
  final String initials;
  final Color color;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Center(
      child: Text(
        initials,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: Colors.white),
      ),
    ),
  );
}

const _avatarColors = [
  Color(0xFF397D83),
  Color(0xFF4A6FA5),
  Color(0xFF7B6699),
  Color(0xFF7D7050),
  Color(0xFF4B7D62),
];
