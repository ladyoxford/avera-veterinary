import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../shared/widgets/avera_logo.dart';

class ClinicAdministratorActivationScreen extends ConsumerStatefulWidget {
  const ClinicAdministratorActivationScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<ClinicAdministratorActivationScreen> createState() => _ClinicAdministratorActivationScreenState();
}

class _ClinicAdministratorActivationScreenState extends ConsumerState<ClinicAdministratorActivationScreen> {
  late Future<ClinicAdministratorActivation?> _activation;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _accepted = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _activation = ref.read(clinicRepositoryProvider).validateClinicAdministratorActivation(widget.token);
  }

  @override
  void dispose() { _password.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _activate() async {
    if (!_accepted) { _notice('Accept the Terms of Service and Privacy Policy to continue.'); return; }
    if (_password.text != _confirm.text) { _notice('Passwords do not match.'); return; }
    setState(() => _submitting = true);
    try {
      await ref.read(clinicRepositoryProvider).activateClinicAdministrator(token: widget.token, password: _password.text);
      if (mounted) await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Account activated'), content: const Text('Your AVERA administrator account is active. You can now sign in with your approved email and new password.'), actions: [FilledButton(onPressed: () { Navigator.pop(dialogContext); context.go('/login'); }, child: const Text('Go to Sign In'))]));
    } catch (error) { _notice(error.toString().replaceFirst('Bad state: ', '')); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<ClinicAdministratorActivation?>(
          future: _activation,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final activation = snapshot.data;
            if (activation == null) return _InvalidActivation(onSignIn: () => context.go('/login'));
            return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Column(mainAxisSize: MainAxisSize.min, children: [
              AveraLogo(size: 132, showWordmark: true, wordmarkColor: theme.colorScheme.onSurface),
              const SizedBox(height: 28), Text(activation.user.accountType == 'ClinicStaff' ? 'Activate Your AVERA Staff Account' : 'Activate Your AVERA Account', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8), Text(activation.clinic.clinicName, style: theme.textTheme.titleMedium),
              const SizedBox(height: 24), Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _detail('Administrator', activation.user.fullName), _detail('Email', activation.user.email), _detail('Role', activation.user.role), _detail('Plan', activation.clinic.subscriptionPlan),
                const SizedBox(height: 18),
                TextField(controller: _password, obscureText: true, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Create Password')),
                const SizedBox(height: 12), TextField(controller: _confirm, obscureText: true, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Confirm Password')),
                const SizedBox(height: 12), Text('At least 12 characters with uppercase, lowercase, a number, and a symbol.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8), LinearProgressIndicator(value: _strength(_password.text), borderRadius: BorderRadius.circular(8)),
                CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, value: _accepted, onChanged: (value) => setState(() => _accepted = value ?? false), title: const Text('I accept the Terms of Service and Privacy Policy.')),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: _submitting || !_ready ? null : _activate, child: _submitting ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Activate Account'))),
              ]))),
              TextButton(onPressed: () => _notice('Contact Support is available through your AVERA support channel.'), child: const Text('Contact Support')),
            ]))));
          },
        ),
      ),
    );
  }

  bool get _ready => _accepted && _password.text == _confirm.text && _strength(_password.text) >= 1;
  double _strength(String value) { var checks = 0; if (value.length >= 12) checks++; if (RegExp(r'[A-Z]').hasMatch(value)) checks++; if (RegExp(r'[a-z]').hasMatch(value)) checks++; if (RegExp(r'\d').hasMatch(value)) checks++; if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) checks++; return checks / 5; }
  Widget _detail(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [SizedBox(width: 108, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))), Expanded(child: Text(value))]));
}

class _InvalidActivation extends StatelessWidget {
  const _InvalidActivation({required this.onSignIn});
  final VoidCallback onSignIn;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_rounded, size: 52),
                const SizedBox(height: 16),
                Text('Activation link unavailable', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('This activation link is invalid, expired, already used, or the clinic is no longer approved.', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: onSignIn, child: const Text('Go to Sign In')),
              ],
            ),
          ),
        ),
      );
}
