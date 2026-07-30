import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/auth_remote_data_source.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

class MfaChallengeArgs {
  const MfaChallengeArgs({
    required this.challengeToken,
    required this.expiresIn,
  });
  final String challengeToken;
  final int expiresIn;
}

class MfaChallengeScreen extends ConsumerStatefulWidget {
  const MfaChallengeScreen({super.key, required this.args});
  final MfaChallengeArgs args;

  @override
  ConsumerState<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends ConsumerState<MfaChallengeScreen> {
  final _code = TextEditingController();
  bool _recoveryMode = false;
  bool _submitting = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_submitting || _code.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final remote = await ref
          .read(authenticationRepositoryProvider)
          .verifyMfa(
            challengeToken: widget.args.challengeToken,
            code: _recoveryMode ? null : _code.text.trim(),
            recoveryCode: _recoveryMode ? _code.text.trim() : null,
          );
      await ref.read(clinicRepositoryProvider).cacheRemoteSession(remote);
      await ref
          .read(offlineAuthorizationServiceProvider)
          .recordOnlineAuthorization(remote);
      ref.invalidate(userSessionProvider);
      if (!mounted) return;
      final platform =
          remote.accountType == 'PlatformOwner' ||
          remote.accountType == 'PlatformAdministrator';
      context.go(platform ? '/platform' : '/dashboard');
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify sign in')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AveraSpacing.pageHorizontalPadding,
        AveraSpacing.pageTopPadding,
        AveraSpacing.pageHorizontalPadding,
        AveraSpacing.bottomContentClearance,
      ),
      children: [
        const AveraPageHeader(
          title: 'Two-factor verification',
          subtitle: 'Enter the code from your authenticator app.',
        ),
        const SizedBox(height: AveraSpacing.subtitleToContentGap),
        AveraLabeledFieldCard(
          label: _recoveryMode ? 'Recovery code' : 'Six-digit code',
          child: TextField(
            controller: _code,
            autofocus: true,
            keyboardType: _recoveryMode
                ? TextInputType.text
                : TextInputType.number,
            maxLength: _recoveryMode ? 19 : 6,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _verify(),
            decoration: InputDecoration(
              hintText: _recoveryMode ? 'XXXX-XXXX-XXXX-XXXX' : '000000',
              counterText: '',
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraPrimaryActionButton(
          label: 'Verify',
          icon: Icons.verified_user_outlined,
          loading: _submitting,
          onPressed: _verify,
        ),
        TextButton(
          onPressed: _submitting
              ? null
              : () => setState(() {
                  _recoveryMode = !_recoveryMode;
                  _code.clear();
                }),
          child: Text(
            _recoveryMode
                ? 'Use authenticator code'
                : 'Use a recovery code instead',
          ),
        ),
        TextButton(
          onPressed: _submitting ? null : () => context.go('/login'),
          child: const Text('Use password instead'),
        ),
      ],
    ),
  );
}

class TwoFactorAuthenticationScreen extends ConsumerStatefulWidget {
  const TwoFactorAuthenticationScreen({super.key});

  @override
  ConsumerState<TwoFactorAuthenticationScreen> createState() =>
      _TwoFactorAuthenticationScreenState();
}

class _TwoFactorAuthenticationScreenState
    extends ConsumerState<TwoFactorAuthenticationScreen> {
  RemoteMfaSetup? _setup;
  List<String>? _recoveryCodes;
  Future<RemoteMfaStatus>? _statusFuture;
  bool _busy = false;

  Future<void> _begin() async {
    final password = await _requestSecret(
      title: 'Confirm your password',
      label: 'Current password',
      obscure: true,
    );
    if (password == null) return;
    setState(() => _busy = true);
    try {
      final setup = await ref
          .read(authenticationRepositoryProvider)
          .beginMfaSetup(password);
      if (mounted) setState(() => _setup = setup);
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final setup = _setup;
    if (setup == null) return;
    final code = await _requestSecret(
      title: 'Verify authenticator',
      label: 'Six-digit code',
      keyboardType: TextInputType.number,
    );
    if (code == null) return;
    setState(() => _busy = true);
    try {
      final codes = await ref
          .read(authenticationRepositoryProvider)
          .confirmMfaSetup(setupId: setup.setupId, code: code);
      if (mounted) setState(() => _recoveryCodes = codes);
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({String password, String factor})?> _requestReauthentication() async {
    final password = await _requestSecret(
      title: 'Confirm your password',
      label: 'Current password',
      obscure: true,
    );
    if (password == null || !mounted) return null;
    final factor = await _requestSecret(
      title: 'Verify your identity',
      label: 'Authenticator or recovery code',
    );
    if (factor == null) return null;
    return (password: password, factor: factor);
  }

  Future<void> _regenerateRecoveryCodes() async {
    final values = await _requestReauthentication();
    if (values == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final codes = await ref
          .read(authenticationRepositoryProvider)
          .regenerateMfaRecoveryCodes(
            password: values.password,
            codeOrRecovery: values.factor,
          );
      if (mounted) setState(() => _recoveryCodes = codes);
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disable two-factor authentication?'),
        content: const Text(
          'You will need to sign in again. All recovery codes and other active sessions will be revoked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final values = await _requestReauthentication();
    if (values == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authenticationRepositoryProvider)
          .disableMfa(password: values.password, codeOrRecovery: values.factor);
      await ref.read(tokenStoreProvider).clear();
      await ref.read(biometricAuthServiceProvider).clear();
      await ref.read(localSessionStoreProvider).clear();
      ref.invalidate(userSessionProvider);
      ref.invalidate(biometricEnrollmentProvider);
      if (mounted) context.go('/login');
    } on ApiException catch (error) {
      _message(error.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finishRecoveryCodeReview() {
    setState(() {
      _recoveryCodes = null;
      _setup = null;
      _statusFuture = ref.read(authenticationRepositoryProvider).mfaStatus();
    });
  }

  Future<String?> _requestSecret({
    required String title,
    required String label,
    bool obscure = false,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.isEmpty == true ? null : result;
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _TwoFactorDenied(),
      data: (value) {
        if (!value.isClinicAdministrator ||
            !value.can('security.twoFactor.manageSelf')) {
          return const _TwoFactorDenied();
        }
        if (BackendConfiguration.isLocalMode) {
          return const _TwoFactorUnavailable();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Two-Factor Authentication')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              const AveraPageHeader(
                title: 'Two-Factor Authentication',
                subtitle:
                    'Protect your administrator account with an authenticator app.',
              ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              if (_recoveryCodes != null)
                _RecoveryCodesCard(
                  codes: _recoveryCodes!,
                  onConfirmedSaved: _finishRecoveryCodeReview,
                )
              else if (_setup != null)
                _MfaSetupCard(setup: _setup!, busy: _busy, onConfirm: _confirm)
              else
                FutureBuilder<RemoteMfaStatus>(
                  future: _statusFuture ??= ref
                      .read(authenticationRepositoryProvider)
                      .mfaStatus(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const AveraSurfaceCard(
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final enabled = snapshot.data!.enabled;
                    return AveraSurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            enabled ? '2FA is enabled' : '2FA is not enabled',
                            style: averaText(context).listItemTitle,
                          ),
                          const SizedBox(height: AveraSpacing.compactRowGap),
                          Text(
                            enabled
                                ? 'Your password and authenticator code are required for new sign-ins.'
                                : 'Set up a time-based one-time password with your preferred authenticator app.',
                            style: averaText(context).listItemSubtitle,
                          ),
                          const SizedBox(height: AveraSpacing.cardGap),
                          if (!enabled)
                            AveraPrimaryActionButton(
                              label: 'Set Up 2FA',
                              icon: Icons.security_rounded,
                              loading: _busy,
                              onPressed: _begin,
                            ),
                          if (enabled) ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : _regenerateRecoveryCodes,
                                icon: const Icon(Icons.password_rounded),
                                label: const Text('Regenerate Recovery Codes'),
                              ),
                            ),
                            const SizedBox(height: AveraSpacing.compactRowGap),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _disable,
                                icon: const Icon(Icons.no_encryption_rounded),
                                label: const Text('Disable 2FA'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MfaSetupCard extends StatelessWidget {
  const _MfaSetupCard({
    required this.setup,
    required this.busy,
    required this.onConfirm,
  });
  final RemoteMfaSetup setup;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scan this code', style: averaText(context).listItemTitle),
        const SizedBox(height: AveraSpacing.cardGap),
        Center(
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: setup.otpauthUri, size: 210),
            ),
          ),
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        Text('Manual setup key', style: averaText(context).sectionLabel),
        const SizedBox(height: 8),
        SelectableText(setup.manualKey, style: averaText(context).fieldValue),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraPrimaryActionButton(
          label: 'Verify Setup',
          loading: busy,
          onPressed: onConfirm,
        ),
      ],
    ),
  );
}

class _RecoveryCodesCard extends StatelessWidget {
  const _RecoveryCodesCard({
    required this.codes,
    required this.onConfirmedSaved,
  });
  final List<String> codes;
  final VoidCallback onConfirmedSaved;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Save your recovery codes',
          style: averaText(context).listItemTitle,
        ),
        const SizedBox(height: 8),
        Text(
          'Each code works once. Store them somewhere private; AVERA will not show them again.',
          style: averaText(context).listItemSubtitle,
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        for (final code in codes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(code, style: averaText(context).fieldValue),
          ),
        const SizedBox(height: AveraSpacing.compactRowGap),
        AveraPrimaryActionButton(
          label: 'I Have Saved These Codes',
          icon: Icons.check_rounded,
          onPressed: onConfirmedSaved,
        ),
      ],
    ),
  );
}

class AccountAccessRestrictedScreen extends ConsumerWidget {
  const AccountAccessRestrictedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AveraSpacing.pageHorizontalPadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AveraSurfaceCard(
              child: Column(
                children: [
                  Icon(
                    Icons.lock_person_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                  Text(
                    'Account access restricted',
                    textAlign: TextAlign.center,
                    style: averaText(context).pageTitle,
                  ),
                  const SizedBox(height: AveraSpacing.compactRowGap),
                  Text(
                    'Your AVERA account is currently suspended.\nContact your clinic administrator or AVERA support for assistance.',
                    textAlign: TextAlign.center,
                    style: averaText(context).pageSubtitle,
                  ),
                  const SizedBox(height: AveraSpacing.sectionGap),
                  AveraPrimaryActionButton(
                    label: 'Return to Sign In',
                    icon: Icons.login_rounded,
                    onPressed: () async {
                      await ref.read(tokenStoreProvider).clear();
                      await ref.read(biometricAuthServiceProvider).clear();
                      await ref.read(localSessionStoreProvider).clear();
                      ref.invalidate(userSessionProvider);
                      ref.invalidate(biometricEnrollmentProvider);
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TwoFactorDenied extends StatelessWidget {
  const _TwoFactorDenied();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('You do not have permission to manage 2FA.')),
  );
}

class _TwoFactorUnavailable extends StatelessWidget {
  const _TwoFactorUnavailable();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Two-factor authentication requires AVERA backend mode so the secret never enters local clinic storage.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
