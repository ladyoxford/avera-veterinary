import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../widgets/avera_ui.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    final clinic = ref.watch(clinicSettingsProvider);
    final themeMode = ref.watch(themeControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          AveraSettingsSection(
            title: 'Appearance',
            children: [
              Padding(
                padding: const EdgeInsets.all(AveraSpacing.cardPadding),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
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
                        onSelectionChanged: (selection) => ref
                            .read(themeControllerProvider.notifier)
                            .setThemeMode(selection.first),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const AveraSettingsInfoRow(
                      icon: Icons.text_fields_rounded,
                      title: 'Typography',
                      subtitle:
                          'Inter for interface text and Sora for AVERA display headings.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AveraSpacing.sectionGap),
          AveraSettingsSection(
            title: 'Clinic Information',
            children: clinic.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (_, __) => [
                AveraSettingsRow(
                  icon: Iconsax.hospital,
                  title: session.valueOrNull?.clinic.clinicName ?? 'Clinic',
                  subtitle: formatClinicLocation(session.valueOrNull?.clinic),
                  onTap: () => context.push('/settings/clinic-information'),
                ),
              ],
              data: (value) =>
                  _clinicRows(context, ref, session.valueOrNull, value),
            ),
          ),
          const SizedBox(height: AveraSpacing.sectionGap),
          AveraSettingsSection(
            title: 'Operations',
            children: [
              AveraSettingsRow(
                icon: Iconsax.security_safe,
                title: 'Offline Access',
                subtitle:
                    'Set or replace this device\'s six-digit offline unlock PIN',
                onTap: () => context.push('/offline-access'),
              ),
              AveraSettingsRow(
                icon: Icons.sync_rounded,
                title: 'Sync pending changes',
                subtitle:
                    'Securely verify access and upload queued offline work',
                showChevron: false,
                onTap: () => _syncPending(context, ref),
              ),
              AveraSettingsRow(
                icon: Iconsax.notification,
                title: 'Notifications',
                subtitle: 'Appointments, vaccinations and clinical reminders',
                onTap: () => context.push('/notifications'),
              ),
              AveraSettingsRow(
                icon: Iconsax.archive_book,
                title: 'Backup & Restore',
                subtitle: 'Export or select a SQLite backup',
                onTap: () => context.push('/backup'),
              ),
              AveraSettingsRow(
                icon: Iconsax.security_safe,
                title: 'Security',
                subtitle:
                    'Session timeout, role permissions, password reset and two-factor authentication',
                onTap: () => context.push('/administration/security'),
              ),
            ],
          ),
          const SizedBox(height: AveraSpacing.sectionGap),
          AveraSettingsSection(
            title: 'AVERA',
            children: [
              AveraSettingsRow(
                icon: Iconsax.info_circle,
                title: 'About AVERA',
                subtitle: 'Veterinary Practice Management Platform',
                onTap: () => context.push('/settings/about'),
              ),
              AveraSettingsRow(
                icon: Iconsax.message_question,
                title: 'Support',
                subtitle: 'Help centre and clinic onboarding support',
                onTap: () => context.push('/settings/support'),
              ),
              AveraSettingsRow(
                icon: Iconsax.document_text,
                title: 'Privacy Policy',
                subtitle: 'Clinic data isolation and privacy controls',
                onTap: () => context.push('/settings/privacy'),
              ),
              AveraSettingsRow(
                icon: Iconsax.logout,
                title: 'Log out',
                subtitle: BackendConfiguration.isLocalMode
                    ? 'End the current local session'
                    : 'End this secure backend session',
                destructive: true,
                showChevron: false,
                onTap: () => _signOut(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _clinicRows(
    BuildContext context,
    WidgetRef ref,
    UserSession? session,
    Clinic clinic,
  ) {
    final canEdit = session?.can(Permissions.clinicSettingsEdit) ?? false;
    return [
      AveraSettingsRow(
        icon: Iconsax.hospital,
        title: clinic.clinicName,
        subtitle: formatClinicLocation(clinic),
        onTap: () => context.push('/settings/clinic-information'),
      ),
      AveraSettingsRow(
        icon: Icons.schedule_outlined,
        title: 'Work Hours',
        subtitle: 'Opening hours, breaks and clinic time zone',
        onTap: () => context.push('/settings/work-hours'),
      ),
      if (session?.can(Permissions.managePatientNumbering) ?? false)
        AveraSettingsRow(
          icon: Iconsax.hashtag,
          title: 'Patient Numbering',
          subtitle: 'Hospital-number prefix and sequence settings',
          onTap: () => context.push('/settings/patient-numbering'),
        ),
      if (canEdit) ...[
        AveraSettingsRow(
          icon: Iconsax.gallery_add,
          title: 'Clinic Logo',
          subtitle: 'Shown on invoices, reports and the sign-in screen',
          onTap: () => _pickBrandAsset(context, ref, session!, kind: 'logo'),
        ),
        AveraSettingsRow(
          icon: Iconsax.image,
          title: 'Clinic Banner',
          subtitle: 'Cover image for the dashboard header',
          onTap: () => _pickBrandAsset(context, ref, session!, kind: 'banner'),
        ),
        AveraSettingsRow(
          icon: Iconsax.color_swatch,
          title: 'Theme Color',
          subtitle: 'Accent color used across the app',
          trailing: _ColorSwatch(value: clinic.themeColor),
          onTap: () =>
              _chooseThemeColor(context, ref, session!, clinic.themeColor),
        ),
      ],
      AveraSettingsRow(
        icon: Iconsax.archive_book,
        title: 'Records Archive',
        subtitle: 'Review records removed from active clinic operations',
        onTap: () => context.push('/records-archive'),
      ),
    ];
  }
}

String formatClinicLocation(Clinic? clinic) {
  if (clinic == null) return 'Clinic details';
  final parts = <String>[];
  void add(String? value) {
    final normalized = value?.trim();
    if (normalized != null &&
        normalized.isNotEmpty &&
        !parts.contains(normalized)) {
      parts.add(normalized);
    }
  }

  add(clinic.address);
  add(clinic.city);
  add(clinic.state);
  add(clinic.country);
  return parts.isEmpty ? 'Clinic details' : parts.join(', ');
}

Future<void> _pickBrandAsset(
  BuildContext context,
  WidgetRef ref,
  UserSession session, {
  required String kind,
}) async {
  final result = await FilePicker.pickFiles(
    type: FileType.image,
    withData: true,
  );
  final file = result?.files.single;
  if (file == null) return;
  final bytes = file.bytes;
  if (bytes == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selected image could not be read.')),
      );
    }
    return;
  }
  final extension = file.extension?.toLowerCase();
  final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
  try {
    await ref
        .read(clinicRepositoryProvider)
        .updateClinicBrandAsset(
          session: session,
          kind: kind,
          localPath: file.path ?? file.name,
          contentType: contentType,
          base64Data: base64Encode(bytes),
        );
    ref.invalidate(clinicSettingsProvider);
    ref.invalidate(userSessionProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clinic ${kind == 'logo' ? 'logo' : 'banner'} updated.',
          ),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlySettingsError(error))));
    }
  }
}

Future<void> _chooseThemeColor(
  BuildContext context,
  WidgetRef ref,
  UserSession session,
  String current,
) async {
  const colors = [
    '#087F7B',
    '#006D77',
    '#2A6F97',
    '#31572C',
    '#6A4C93',
    '#9C6644',
  ];
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clinic Theme Color',
            style: Theme.of(sheetContext).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Applies to future screens and shared AVERA controls. Existing records are unchanged.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final value in colors)
                Semantics(
                  button: true,
                  selected: value == current.toUpperCase(),
                  label: 'Select color $value',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(sheetContext).pop(value),
                    child: _ColorSwatch(
                      value: value,
                      selected: value == current.toUpperCase(),
                      size: 52,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  try {
    await ref
        .read(clinicRepositoryProvider)
        .updateClinicThemeColor(session: session, color: selected);
    ref.invalidate(clinicSettingsProvider);
    ref.invalidate(userSessionProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlySettingsError(error))));
    }
  }
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
            'AVERA could not verify online access. Queued changes remain safe on this device.',
          ),
        ),
      );
    }
  }
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
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

String _friendlySettingsError(Object error) {
  if (error is ApiException) return error.message;
  if (error is ArgumentError || error is StateError) {
    return error.toString().replaceFirst(
      RegExp(r'^(Invalid argument|Bad state):\s*'),
      '',
    );
  }
  return 'The setting could not be saved. Please try again.';
}

class AveraSettingsSection extends StatelessWidget {
  const AveraSettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).extension<AveraTextStyles>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style:
                styles?.sectionTitle ?? Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1)
                  const Divider(height: 1, indent: 64, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class AveraSettingsRow extends StatelessWidget {
  const AveraSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.showChevron = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.primary;
    return Semantics(
      button: onTap != null,
      child: ListTile(
        minTileHeight: 70,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: color, size: 24),
        title: Text(title, style: destructive ? TextStyle(color: color) : null),
        subtitle: Text(subtitle),
        trailing:
            trailing ??
            (showChevron ? const Icon(Iconsax.arrow_right_3, size: 20) : null),
        onTap: onTap,
      ),
    );
  }
}

class AveraSettingsInfoRow extends StatelessWidget {
  const AveraSettingsInfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 3),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.value,
    this.selected = false,
    this.size = 30,
  });
  final String value;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalized = value.replaceFirst('#', '');
    final color = RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)
        ? Color(int.parse('FF$normalized', radix: 16))
        : AppTheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.onSurface
              : Colors.transparent,
          width: 3,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
          : null,
    );
  }
}

class ClinicInformationScreen extends ConsumerStatefulWidget {
  const ClinicInformationScreen({super.key});

  @override
  ConsumerState<ClinicInformationScreen> createState() =>
      _ClinicInformationScreenState();
}

class _ClinicInformationScreenState
    extends ConsumerState<ClinicInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _timeZone = TextEditingController();
  String? _loadedId;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _address,
      _city,
      _country,
      _timeZone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _hydrate(Clinic clinic) {
    if (_loadedId == clinic.clinicId) return;
    _loadedId = clinic.clinicId;
    _name.text = clinic.clinicName;
    _email.text = clinic.email ?? '';
    _phone.text = clinic.phoneNumber ?? '';
    _address.text = clinic.address ?? '';
    _city.text = clinic.city ?? '';
    _country.text = clinic.country ?? '';
    _timeZone.text = clinic.timeZone;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(clinicSettingsProvider);
    final session = ref.watch(userSessionProvider).valueOrNull;
    final canEdit = session?.can(Permissions.clinicSettingsEdit) ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Clinic Information')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _SettingsLoadError(
          onRetry: () => ref.invalidate(clinicSettingsProvider),
        ),
        data: (clinic) {
          _hydrate(clinic);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
              children: [
                Text(
                  canEdit
                      ? 'Keep public clinic details accurate.'
                      : 'Clinic details are managed by an administrator.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _field(_name, 'Clinic Name', enabled: canEdit, required: true),
                _field(
                  _email,
                  'Clinic Email',
                  enabled: canEdit,
                  keyboardType: TextInputType.emailAddress,
                ),
                _field(
                  _phone,
                  'Phone Number',
                  enabled: canEdit,
                  keyboardType: TextInputType.phone,
                ),
                _field(_address, 'Address', enabled: canEdit, maxLines: 2),
                _field(_city, 'City', enabled: canEdit),
                _field(_country, 'Country', enabled: canEdit),
                _field(
                  _timeZone,
                  'Time Zone',
                  enabled: canEdit,
                  required: true,
                ),
                if (canEdit) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving || session == null
                          ? null
                          : () => _save(session),
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Clinic Information'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    required bool enabled,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AveraSpacing.cardGap),
    child: AveraLabeledTextField(
      label: label,
      controller: controller,
      hintText: 'Enter $label',
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: required
          ? (value) => value == null || value.trim().isEmpty
                ? '$label is required.'
                : null
          : null,
    ),
  );

  Future<void> _save(UserSession session) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .updateClinicInformation(
            session: session,
            name: _name.text,
            email: _email.text,
            phone: _phone.text,
            address: _address.text,
            city: _city.text,
            country: _country.text,
            timeZone: _timeZone.text.trim(),
          );
      ref.invalidate(clinicSettingsProvider);
      ref.invalidate(userSessionProvider);
      ref.invalidate(clinicWorkHoursProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clinic information updated.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlySettingsError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class AboutAveraScreen extends StatelessWidget {
  const AboutAveraScreen({super.key});
  @override
  Widget build(BuildContext context) => const _InformationScreen(
    title: 'About AVERA',
    icon: Icons.pets_rounded,
    heading: 'Veterinary Practice Management Platform',
    body:
        'AVERA brings patient records, clinical workflows, appointments, inventory, billing and clinic administration into one secure clinic workspace.',
  );
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});
  @override
  Widget build(BuildContext context) => _InformationScreen(
    title: 'Support',
    icon: Iconsax.message_question,
    heading: 'How can we help?',
    body:
        'Contact AVERA support for clinic onboarding, account access and product assistance.',
    actions: [
      FilledButton.icon(
        onPressed: () => launchUrl(
          Uri.parse('mailto:support@averavet.sbs?subject=AVERA%20Support'),
        ),
        icon: const Icon(Icons.mail_outline_rounded),
        label: const Text('Email Support'),
      ),
      OutlinedButton.icon(
        onPressed: () => launchUrl(
          Uri.parse('https://averavet.sbs'),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Open Help Website'),
      ),
    ],
  );
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});
  @override
  Widget build(BuildContext context) => _InformationScreen(
    title: 'Privacy Policy',
    icon: Iconsax.document_text,
    heading: 'Your clinic data stays clinic scoped',
    body:
        'AVERA uses authenticated access, role permissions and tenant isolation to protect clinical and business records. Offline data remains on the authorized device and synchronizes through the configured secure service.',
    actions: [
      OutlinedButton.icon(
        onPressed: () => launchUrl(
          Uri.parse('https://averavet.sbs/privacy'),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Read Online Policy'),
      ),
    ],
  );
}

class _InformationScreen extends StatelessWidget {
  const _InformationScreen({
    required this.title,
    required this.icon,
    required this.heading,
    required this.body,
    this.actions = const [],
  });
  final String title;
  final IconData icon;
  final String heading;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          heading,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 28),
          for (final action in actions) ...[action, const SizedBox(height: 12)],
        ],
      ],
    ),
  );
}

class _SettingsLoadError extends StatelessWidget {
  const _SettingsLoadError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          const Text('Clinic settings are unavailable.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
