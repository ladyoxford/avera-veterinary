import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../shared/widgets/avera_logo.dart';

class OfflinePinSetupScreen extends HookConsumerWidget {
  const OfflinePinSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin = useTextEditingController();
    final confirm = useTextEditingController();
    final saving = useState(false);
    Future<void> save() async {
      if (pin.text != confirm.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The offline PINs do not match.')),
        );
        return;
      }
      saving.value = true;
      try {
        await ref.read(offlineAuthorizationServiceProvider).setPin(pin.text);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Offline workspace unlock is ready for this device.',
              ),
            ),
          );
          context.pop();
        }
      } on ArgumentError catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message.toString())));
        }
      } finally {
        saving.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Offline Access')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const AveraLogo(size: 96),
              const SizedBox(height: 24),
              Text(
                'Secure offline workspace',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Create a six-digit PIN for this device. It is separate from your AVERA password and works only after an online sign-in.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Offline PIN'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                onSubmitted: (_) => save(),
                decoration: const InputDecoration(
                  labelText: 'Confirm offline PIN',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: saving.value ? null : save,
                child: saving.value
                    ? const CircularProgressIndicator()
                    : const Text('Enable Offline Access'),
              ),
              const SizedBox(height: 16),
              Text(
                'Biometric unlock will be offered when supported by the device and enabled by the installed platform security module.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OfflineUnlockScreen extends HookConsumerWidget {
  const OfflineUnlockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(offlineAuthorizationServiceProvider);
    final snapshot = useFuture(
      useMemoized(() => service.validSnapshot(), [service]),
    ).data;
    final pin = useTextEditingController();
    final unlocking = useState(false);

    Future<void> unlock() async {
      unlocking.value = true;
      try {
        final authorized = await service.unlockWithPin(pin.text);
        if (authorized == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('That offline PIN is not correct.')),
            );
          }
          return;
        }
        ref.read(offlineAuthorizationSnapshotProvider.notifier).state =
            authorized;
        ref.invalidate(userSessionProvider);
        if (context.mounted) {
          final isPlatformAccount =
              authorized.accountType == 'PlatformOwner' ||
              authorized.accountType == 'PlatformAdministrator';
          context.go(isPlatformAccount ? '/platform' : '/dashboard');
        }
      } on StateError catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      } finally {
        unlocking.value = false;
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 48),
                const AveraLogo(size: 124),
                const SizedBox(height: 28),
                Text(
                  'Unlock Offline Workspace',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot == null
                      ? 'Offline access is unavailable on this device.'
                      : '${snapshot.fullName}\n${snapshot.clinicName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (snapshot != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last verified ${_formatDate(snapshot.lastOnlineAt)}\nExpires ${_formatDate(snapshot.expiresAt)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    onSubmitted: (_) => unlock(),
                    decoration: const InputDecoration(labelText: 'Offline PIN'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: unlocking.value ? null : unlock,
                    child: unlocking.value
                        ? const CircularProgressIndicator()
                        : const Text('Unlock Offline Workspace'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Retry Online Connection'),
                ),
                const SizedBox(height: 20),
                Text(
                  'OFFLINE\nChanges are saved on this device and will sync only after AVERA securely verifies your access online.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.toLocal().day}/${value.toLocal().month}/${value.toLocal().year}';
}
