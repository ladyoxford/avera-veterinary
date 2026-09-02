import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../shared/widgets/avera_auth_ui.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _submitted = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref
          .read(authenticationRepositoryProvider)
          .requestPasswordReset(_email.text);
      if (mounted) setState(() => _submitted = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Password recovery is temporarily unavailable. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => AveraAuthScaffold(
    backTitle: 'Reset Your Password',
    onBack: () => context.go('/login'),
    footer: TextButton(
      onPressed: () => context.go('/login'),
      child: const Text('Back to Sign In'),
    ),
    child: AveraAuthCard(
      child: _submitted
          ? Column(
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 46,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Check your email',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'If this email is registered, a password reset link has been sent.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () => setState(() {
                    _submitted = false;
                    _error = null;
                  }),
                  child: const Text('Send Again'),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the email used for registering your clinic.',
                  ),
                  const SizedBox(height: 22),
                  const AveraFormLabel('Email Address'),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('forgot-password-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      hintText: 'you@clinic.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      return RegExp(
                            r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                          ).hasMatch(email)
                          ? null
                          : 'Enter a valid email address.';
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('send-password-reset-link'),
                      onPressed: _working ? null : _submit,
                      icon: _working
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: const Text('Send Reset Link'),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _working = false;
  bool _completed = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working || widget.token.trim().isEmpty) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref
          .read(authenticationRepositoryProvider)
          .resetPassword(
            token: widget.token,
            password: _password.text,
            confirmPassword: _confirm.text,
          );
      if (mounted) setState(() => _completed = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The password could not be reset right now.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => AveraAuthScaffold(
    backTitle: 'Create New Password',
    onBack: () => context.go('/login'),
    child: AveraAuthCard(
      child: widget.token.trim().isEmpty
          ? _ResetMessage(
              icon: Icons.link_off_rounded,
              title: 'Reset link unavailable',
              message:
                  'This link is incomplete. Request a new password reset email.',
              actionLabel: 'Request New Link',
              onAction: () => context.go('/forgot-password'),
            )
          : _completed
          ? _ResetMessage(
              icon: Icons.check_circle_outline_rounded,
              title: 'Password reset',
              message: 'Your new password is ready to use on AVERA.',
              actionLabel: 'Go to Sign In',
              onAction: () => context.go('/login'),
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Use at least 12 characters with upper-case and lower-case letters, a number, and a symbol.',
                  ),
                  const SizedBox(height: 22),
                  const AveraFormLabel('New Password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('reset-password-new'),
                    controller: _password,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: _passwordIssue,
                  ),
                  const SizedBox(height: 16),
                  const AveraFormLabel('Confirm Password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('reset-password-confirm'),
                    controller: _confirm,
                    obscureText: _obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirm
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == _password.text
                        ? null
                        : 'The passwords do not match.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('submit-password-reset'),
                      onPressed: _working ? null : _submit,
                      icon: _working
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.password_rounded),
                      label: const Text('Reset Password'),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

class _ResetMessage extends StatelessWidget {
  const _ResetMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 16),
      Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ),
    ],
  );
}

String? _passwordIssue(String? value) {
  final password = value ?? '';
  if (password.length < 12 ||
      !RegExp('[A-Z]').hasMatch(password) ||
      !RegExp('[a-z]').hasMatch(password) ||
      !RegExp(r'\d').hasMatch(password) ||
      !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    return 'Use 12+ characters with upper, lower, number, and symbol.';
  }
  return null;
}
