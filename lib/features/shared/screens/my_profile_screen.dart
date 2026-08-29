import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/avera_ui.dart';
import '../widgets/identity_avatar.dart';
import '../widgets/avera_photo_actions.dart';
import '../widgets/safe_back_navigation.dart';

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _license = TextEditingController();
  String? _loadedUserId;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _license.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSession = ref.watch(userSessionProvider);
    return SafeBackNavigationScope(
      fallbackPath: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const SafeBackButton(
            buttonKey: Key('profile-safe-back-button'),
            fallbackPath: '/dashboard',
          ),
          title: const Text('My Profile'),
        ),
        body: asyncSession.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
            child: Text('Your profile could not be loaded. Please try again.'),
          ),
          data: (session) {
            if (_loadedUserId != session.user.userId) {
              _loadedUserId = session.user.userId;
              _name.text = session.user.fullName;
              _phone.text = session.user.phoneNumber ?? '';
              _license.text = session.user.veterinaryLicenseNumber ?? '';
            }
            final showLicense = session.user.role.toLowerCase().contains(
              'veterinarian',
            );
            return SafeArea(
              top: false,
              child: Form(
                key: _formKey,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AveraSpacing.pageHorizontalPadding,
                    12,
                    AveraSpacing.pageHorizontalPadding,
                    32,
                  ),
                  children: [
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AveraIdentityAvatar(
                            key: const Key('profile-avatar'),
                            name: session.user.fullName,
                            photoReference: session.user.profilePhoto,
                            size: 120,
                            onTap: _saving
                                ? null
                                : () => _showPhotoActions(session),
                          ),
                          Positioned(
                            right: -2,
                            bottom: 2,
                            child: CircleAvatar(
                              radius: 19,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              child: const Icon(
                                Icons.photo_camera_outlined,
                                size: 21,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(child: Text('Tap to change photo')),
                    const SizedBox(height: 14),
                    Text(
                      session.user.fullName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session.user.role}  |  ${session.clinic.clinicName}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),
                    _editableField(
                      label: 'FULL NAME',
                      controller: _name,
                      validator: (value) => value?.trim().isEmpty == true
                          ? 'Enter your full name.'
                          : null,
                    ),
                    _gap,
                    _readOnlyField('ROLE', session.user.role),
                    _gap,
                    _readOnlyField(
                      'PROFESSIONAL TITLE',
                      session.user.professionalTitle ?? 'Not set',
                    ),
                    _gap,
                    _readOnlyField('CLINIC', session.clinic.clinicName),
                    _gap,
                    _readOnlyField('EMAIL ADDRESS', session.user.email),
                    _gap,
                    _editableField(
                      label: 'PHONE NUMBER',
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        final phone = value?.trim() ?? '';
                        if (phone.isEmpty) return null;
                        return RegExp(r'^\+?[0-9 ()-]{7,24}$').hasMatch(phone)
                            ? null
                            : 'Enter a valid phone number.';
                      },
                    ),
                    if (showLicense) ...[
                      _gap,
                      _editableField(
                        label: 'LICENSE / REGISTRATION NO.',
                        controller: _license,
                      ),
                    ],
                    const SizedBox(height: 24),
                    AveraPrimaryActionButton(
                      key: const Key('save-profile-button'),
                      label: _saving ? 'Saving...' : 'Save Changes',
                      icon: Icons.save_outlined,
                      onPressed: _saving ? null : () => _save(session),
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

  Widget get _gap => const SizedBox(height: AveraSpacing.cardGap);

  Widget _editableField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => AveraLabeledFieldCard(
    label: label,
    child: TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: const InputDecoration.collapsed(hintText: ''),
    ),
  );

  Widget _readOnlyField(String label, String value) => AveraLabeledFieldCard(
    label: label,
    child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
  );

  Future<void> _save(UserSession session) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .updateOwnProfile(
            session: session,
            fullName: _name.text,
            phoneNumber: _phone.text,
            veterinaryLicenseNumber: _license.text,
          );
      ref.invalidate(userSessionProvider);
      await ref.read(userSessionProvider.future);
      if (mounted) _message('Profile updated.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Your profile could not be updated.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showPhotoActions(UserSession session) async {
    final action = await showAveraPhotoActionSheet(
      context: context,
      subjectName: session.user.fullName,
      hasPhoto: session.user.profilePhoto?.trim().isNotEmpty == true,
      canRemovePhoto: true,
    );
    if (!mounted || action == null) return;
    if (action == AveraPhotoAction.viewPhoto) {
      await showAveraPhotoViewer(
        context: context,
        subjectName: session.user.fullName,
        photoReference: session.user.profilePhoto!,
      );
    } else if (action == AveraPhotoAction.removePhoto) {
      await _removePhoto(session);
    } else {
      await _pickPhoto(session, action);
    }
  }

  Future<void> _pickPhoto(UserSession session, AveraPhotoAction action) async {
    try {
      final cropped = await pickAndCropAveraPhoto(action);
      if (cropped == null || !mounted) return;
      final bytes = await cropped.readAsBytes();
      if (bytes.length > 1024 * 1024) {
        _message('Choose a profile photo smaller than 1 MB.');
        return;
      }
      setState(() => _saving = true);
      await ref
          .read(clinicRepositoryProvider)
          .updateOwnProfilePhoto(
            session: session,
            localPath: cropped.path,
            contentType: 'image/jpeg',
            base64Data: base64Encode(bytes),
          );
      ref.invalidate(userSessionProvider);
      await ref.read(userSessionProvider.future);
      if (mounted) _message('Profile photo updated.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('The photo could not be changed. Check photo permissions.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removePhoto(UserSession session) async {
    setState(() => _saving = true);
    try {
      await ref.read(clinicRepositoryProvider).removeOwnProfilePhoto(session);
      ref.invalidate(userSessionProvider);
      await ref.read(userSessionProvider.future);
      if (mounted) _message('Profile photo removed.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
}
