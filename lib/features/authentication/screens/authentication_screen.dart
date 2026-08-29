import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/auth_remote_data_source.dart';
import '../../../core/services/local_session_store.dart';
import '../../shared/widgets/avera_auth_ui.dart';
import 'security_auth_screens.dart';

class AuthenticationScreen extends HookConsumerWidget {
  const AuthenticationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final email = useTextEditingController();
    final password = useTextEditingController();
    final remember = useState(true);
    final obscurePassword = useState(true);
    final signingIn = useState(false);
    final biometricEnrollment = ref
        .watch(biometricEnrollmentProvider)
        .valueOrNull;
    final working = signingIn.value;

    Future<void> completeRemoteSignIn(RemoteCurrentUser remote) async {
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
      final destination =
          remote.accountType == 'PlatformOwner' ||
              remote.accountType == 'PlatformAdministrator'
          ? '/platform'
          : '/dashboard';
      if (kDebugMode) {
        developer.log(
          'role routing accountType=${remote.accountType} destination=$destination',
          name: 'AVERA.auth',
        );
      }
      if (context.mounted) context.go(destination);
    }

    Future<void> signIn() async {
      if (!(formKey.currentState?.validate() ?? false)) return;
      final platform = Theme.of(context).platform.name;
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
          final destination = local.isPlatformAccount
              ? '/platform'
              : '/dashboard';
          if (context.mounted) context.go(destination);
          return;
        }

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
        await completeRemoteSignIn(remote);
      } on MfaRequiredException catch (challenge) {
        if (context.mounted) {
          context.push(
            '/mfa-challenge',
            extra: MfaChallengeArgs(
              challengeToken: challenge.challengeToken,
              expiresIn: challenge.expiresIn,
            ),
          );
        }
      } on ApiException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      } catch (error, stackTrace) {
        if (kDebugMode) {
          developer.log(
            'Sign-in failed: $error',
            name: 'AVERA.auth',
            stackTrace: stackTrace,
          );
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to sign in right now. Please try again.'),
            ),
          );
        }
      } finally {
        signingIn.value = false;
      }
    }

    Future<void> signInWithBiometrics() async {
      if (working || biometricEnrollment == null) return;
      signingIn.value = true;
      try {
        final approved = await ref
            .read(biometricAuthServiceProvider)
            .authenticate();
        if (!approved) return;
        if (BackendConfiguration.isLocalMode) {
          ref.invalidate(userSessionProvider);
          final local = await ref.read(userSessionProvider.future);
          if (!context.mounted) return;
          context.go(local.isPlatformAccount ? '/platform' : '/dashboard');
          return;
        }
        final remote = await ref
            .read(authenticationRepositoryProvider)
            .restore();
        if (remote == null) {
          await ref.read(biometricAuthServiceProvider).clear();
          ref.invalidate(biometricEnrollmentProvider);
          throw const ApiException(
            'biometric_session_expired',
            'Biometric sign-in expired. Use your password to sign in again.',
          );
        }
        await completeRemoteSignIn(remote);
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

    return AveraAuthScaffold(
      footer: const Text('AVERA | Smarter Care. Better Practice.'),
      child: AveraAuthCard(
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to manage your veterinary clinic.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                AveraAuthField(
                  key: const Key('sign-in-email'),
                  label: 'Email Address',
                  controller: email,
                  hintText: 'you@clinic.com',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.isEmpty) return 'Enter your email address.';
                    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(normalized)) {
                      return 'Enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                AveraAuthField(
                  key: const Key('sign-in-password'),
                  label: 'Password',
                  controller: password,
                  hintText: 'Enter your password',
                  icon: Icons.lock_outline_rounded,
                  obscureText: obscurePassword.value,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => signIn(),
                  validator: (value) =>
                      (value?.isEmpty ?? true) ? 'Enter your password.' : null,
                  suffixIcon: IconButton(
                    tooltip: obscurePassword.value
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        obscurePassword.value = !obscurePassword.value,
                    icon: Icon(
                      obscurePassword.value
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Remember me',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: remember.value,
                      onChanged: working
                          ? null
                          : (value) => remember.value = value,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('sign-in-button'),
                    onPressed: working ? null : signIn,
                    child: signingIn.value
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                if (biometricEnrollment != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: working ? null : signInWithBiometrics,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Sign in with biometrics'),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: working
                        ? null
                        : () => context.push('/forgot-password'),
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const Key('register-clinic-button'),
                    onPressed: working
                        ? null
                        : () => context.push('/register-clinic'),
                    child: const Text('Register Your Clinic'),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        "Your clinic's data is encrypted and isolated from every other practice on AVERA.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
}
