import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Password-reset tokens are intentionally backend-only. The email delivery
/// endpoint is introduced in the next backend phase; no local password state
/// may be changed from this screen.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reset Your Password',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              if (_submitted)
                const Text(
                  'Password reset is managed by the secure AVERA backend. Contact your clinic administrator or AVERA support until email recovery is enabled.',
                  textAlign: TextAlign.center,
                )
              else ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => _submitted = true),
                  child: const Text('Send Reset Link'),
                ),
              ],
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Back to Sign In'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({super.key, required this.token});
  final String token;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Password Reset',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'This reset link cannot be processed until the production password-recovery endpoint is enabled.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('Return to Sign In'),
            ),
          ],
        ),
      ),
    ),
  );
}
