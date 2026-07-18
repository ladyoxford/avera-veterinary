import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/services/local_session_store.dart';
import '../../shared/widgets/avera_logo.dart';

class AuthenticationScreen extends HookConsumerWidget {
  const AuthenticationScreen({super.key, this.clinicName});

  final String? clinicName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final email = useTextEditingController();
    final password = useTextEditingController();
    final remember = useState(true);
    final obscurePassword = useState(true);
    final signingIn = useState(false);

    Future<void> signIn() async {
      if (!(formKey.currentState?.validate() ?? false)) return;
      signingIn.value = true;
      try {
        if (BackendConfiguration.isLocalMode) {
          await ref.read(seedDataProvider.future);
          final local = await ref
              .read(clinicRepositoryProvider)
              .authenticateUser(
                username: email.text.trim(),
                password: password.text,
                rememberMe: remember.value,
              );
          if (local == null) {
            throw const ApiException(
              'invalid_credentials',
              'Your email or password is incorrect.',
            );
          }
          if (remember.value) {
            await ref
                .read(localSessionStoreProvider)
                .save(
                  LocalSessionReference(
                    userId: local.user.userId,
                    clinicId: local.clinic.clinicId,
                  ),
                );
          } else {
            await ref.read(localSessionStoreProvider).clear();
          }
          ref.invalidate(userSessionProvider);
          final destination = local.isPlatformOwner
              ? '/platform'
              : '/dashboard';
          if (context.mounted) context.go(destination);
          return;
        }

        final platform = Theme.of(context).platform.name;
        final deviceId = await ref
            .read(offlineAuthorizationServiceProvider)
            .deviceId();
        final remote = await ref
            .read(authenticationRepositoryProvider)
            .signIn(
              email: email.text.trim(),
              password: password.text,
              deviceId: deviceId,
              platform: platform,
            );
        await ref.read(clinicRepositoryProvider).cacheRemoteSession(remote);
        final snapshot = await ref
            .read(offlineAuthorizationServiceProvider)
            .recordOnlineAuthorization(remote);
        unawaited(
          ref
              .read(offlineSyncCoordinatorProvider)
              .synchronize(snapshot)
              .then<void>((_) {}, onError: (_, __) {}),
        );
        ref.invalidate(userSessionProvider);
        final destination = remote.accountType == 'PlatformOwner'
            ? '/platform'
            : '/dashboard';
        if (kDebugMode) {
          developer.log(
            'role routing accountType=${remote.accountType} destination=$destination',
            name: 'AVERA.auth',
          );
        }
        if (context.mounted) context.go(destination);
      } on ApiException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      } finally {
        signingIn.value = false;
      }
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final resolvedClinicName = clinicName?.trim().isNotEmpty == true
        ? clinicName!.trim()
        : BackendConfiguration.isLocalMode
        ? 'Avera Veterinary Clinic'
        : 'your veterinary practice';

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 44)
                    .clamp(0.0, double.infinity)
                    .toDouble(),
                maxWidth: 500,
              ),
              child: IntrinsicHeight(
                child: AutofillGroup(
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _AveraBrandRow(),
                        const SizedBox(height: 44),
                        Text(
                          'Welcome back',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to manage $resolvedClinicName',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _FieldLabel('Email address'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          validator: (value) {
                            final normalized = value?.trim() ?? '';
                            if (normalized.isEmpty) {
                              return 'Enter your email address.';
                            }
                            if (!normalized.contains('@')) {
                              return 'Enter a valid email address.';
                            }
                            return null;
                          },
                          decoration: _inputDecoration(
                            context,
                            hintText: 'you@clinic.com',
                            prefixIcon: Iconsax.sms,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _FieldLabel('Password'),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: password,
                          obscureText: obscurePassword.value,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => signIn(),
                          autofillHints: const [AutofillHints.password],
                          validator: (value) => (value?.isEmpty ?? true)
                              ? 'Enter your password.'
                              : null,
                          decoration: _inputDecoration(
                            context,
                            hintText: 'Enter your password',
                            prefixIcon: Iconsax.lock,
                            suffixIcon: IconButton(
                              tooltip: obscurePassword.value
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => obscurePassword.value =
                                  !obscurePassword.value,
                              icon: Icon(
                                obscurePassword.value
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Remember me',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Switch.adaptive(
                              value: remember.value,
                              onChanged: signingIn.value
                                  ? null
                                  : (value) => remember.value = value,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: signingIn.value ? null : signIn,
                            child: signingIn.value
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Sign In'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton(
                            onPressed: signingIn.value
                                ? null
                                : () => context.push('/forgot-password'),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.onSurface,
                              side: BorderSide(color: colors.outline),
                            ),
                            onPressed: signingIn.value
                                ? null
                                : () => context.push('/register-clinic'),
                            child: const Text('Register Your Clinic'),
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        Center(
                          child: Text(
                            'AVERA • Smarter Care. Better Practice.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AveraBrandRow extends StatelessWidget {
  const _AveraBrandRow();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const AveraLogo(size: 40),
      const SizedBox(width: 10),
      Text(
        'AVERA',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

InputDecoration _inputDecoration(
  BuildContext context, {
  required String hintText,
  required IconData prefixIcon,
  Widget? suffixIcon,
}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hintText,
    prefixIcon: Icon(prefixIcon),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: colors.surfaceContainerHighest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colors.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colors.primary, width: 1.5),
    ),
  );
}
