import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/theme_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    final themeMode = ref.watch(themeControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsGroup(
            title: 'Appearance',
            children: [
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Iconsax.monitor),
                    label: Text('Device'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Iconsax.sun_1),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Iconsax.moon),
                    label: Text('Dark'),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) {
                  ref
                      .read(themeControllerProvider.notifier)
                      .setThemeMode(selection.first);
                },
              ),
              const SizedBox(height: 12),
              const ListTile(
                leading: Icon(Iconsax.text),
                title: Text('Typography'),
                subtitle: Text(
                  'Inter for interface text and Sora for AVERA display headings.',
                ),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Clinic Information',
            children: [
              session.when(
                loading: () => const ListTile(title: Text('Loading clinic')),
                error: (error, _) =>
                    ListTile(title: Text('Unable to load clinic: $error')),
                data: (data) => ListTile(
                  leading: const Icon(Iconsax.hospital),
                  title: Text(data.clinic.clinicName),
                  subtitle: Text(
                    '${data.clinic.phoneNumber ?? '-'} • ${data.clinic.email ?? '-'}\n'
                    '${data.clinic.city ?? '-'}, ${data.clinic.country ?? '-'}',
                  ),
                  isThreeLine: true,
                ),
              ),
              session.maybeWhen(
                data: (data) => _NavTile(
                  icon: Icons.schedule_outlined,
                  title: 'Work Hours',
                  subtitle:
                      data.can(Permissions.clinicWorkHoursManage) ||
                          data.can(Permissions.clinicSettingsEdit)
                      ? 'Opening hours, breaks and clinic time zone'
                      : 'View clinic opening hours',
                  path: '/settings/work-hours',
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        _pickBrandAsset(context, ref, isLogo: true),
                    icon: const Icon(Iconsax.gallery_add),
                    label: const Text('Logo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _pickBrandAsset(context, ref, isLogo: false),
                    icon: const Icon(Iconsax.image),
                    label: const Text('Banner'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Iconsax.color_swatch),
                    label: const Text('Theme Color'),
                  ),
                ],
              ),
              _NavTile(
                icon: Iconsax.archive_book,
                title: 'Archived Animals',
                subtitle: 'Deceased and relocated patients',
                path: '/animals/archived',
              ),
            ],
          ),
          _SettingsGroup(
            title: 'Operations',
            children: [
              _NavTile(
                icon: Iconsax.security_safe,
                title: 'Offline Access',
                subtitle:
                    'Set or replace this device\'s six-digit offline unlock PIN',
                path: '/offline-access',
              ),
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Sync pending changes'),
                subtitle: const Text(
                  'Securely verify access and upload queued offline work',
                ),
                onTap: () => _syncPending(context, ref),
              ),
              _NavTile(
                icon: Iconsax.notification,
                title: 'Notifications',
                subtitle:
                    'Vaccinations, appointments, inventory and billing alerts',
                path: '/notifications',
              ),
              _NavTile(
                icon: Iconsax.archive_book,
                title: 'Backup & Restore',
                subtitle: 'Export or select a SQLite backup',
                path: '/backup',
              ),
              const ListTile(
                leading: Icon(Iconsax.security_safe),
                title: Text('Security'),
                subtitle: Text(
                  'Session timeout, role permissions, password reset and 2FA-ready account model',
                ),
              ),
            ],
          ),
          _SettingsGroup(
            title: 'AVERA',
            children: [
              ListTile(
                leading: Icon(Iconsax.info_circle),
                title: Text('About AVERA'),
                subtitle: Text('Veterinary Practice Management Platform'),
              ),
              ListTile(
                leading: Icon(Iconsax.message_question),
                title: Text('Support'),
                subtitle: Text('Help center and clinic onboarding support'),
              ),
              ListTile(
                leading: Icon(Iconsax.document_text),
                title: Text('Privacy Policy'),
                subtitle: Text('Clinic data isolation and privacy controls'),
              ),
              ListTile(
                leading: Icon(Iconsax.logout),
                title: const Text('Logout'),
                subtitle: Text(
                  BackendConfiguration.isLocalMode
                      ? 'End the current local session'
                      : 'End this secure backend session',
                ),
                onTap: () => _signOut(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _syncPending(BuildContext context, WidgetRef ref) async {
    final snapshot = ref.read(offlineAuthorizationSnapshotProvider);
    if (snapshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect and sign in online before syncing.'),
        ),
      );
      return;
    }
    try {
      final result = await ref
          .read(offlineSyncCoordinatorProvider)
          .synchronize(snapshot);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.synced} queued changes uploaded. ${result.failed} need attention.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'AVERA could not verify online access. Your queued changes remain safe on this device.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickBrandAsset(
    BuildContext context,
    WidgetRef ref, {
    required bool isLogo,
  }) async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    await ref
        .read(clinicRepositoryProvider)
        .updateClinicBranding(
          logo: isLogo ? path : null,
          banner: isLogo ? null : path,
        );
    ref.invalidate(userSessionProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${isLogo ? 'Logo' : 'Banner'} updated')),
      );
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (BackendConfiguration.isLocalMode) {
      await ref.read(localSessionStoreProvider).clear();
    } else {
      await ref.read(authenticationRepositoryProvider).signOut();
    }
    ref.invalidate(userSessionProvider);
    if (context.mounted) context.go('/login');
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Iconsax.arrow_right_3),
      onTap: () => context.go(path),
    );
  }
}
