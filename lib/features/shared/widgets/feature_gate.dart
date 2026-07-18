import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/services/feature_gate_service.dart';

class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.requiredPermission,
  });

  final AveraFeature feature;
  final Widget child;
  final String? requiredPermission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    final subscription = ref
        .watch(activeClinicSubscriptionProvider)
        .valueOrNull;
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _FeatureUnavailable(),
      data: (value) {
        final result = FeatureGateService.evaluate(
          subscriptionPlan:
              subscription?.plan.label ?? value.clinic.subscriptionPlan,
          subscriptionStatus: subscription?.status.name ?? 'active',
          feature: feature,
          hasPermission:
              requiredPermission == null || value.can(requiredPermission!),
        );
        return result.allowed ? child : LockedFeatureCard(result: result);
      },
    );
  }
}

class FeatureGateBuilder extends ConsumerWidget {
  const FeatureGateBuilder({
    super.key,
    required this.feature,
    required this.builder,
    this.requiredPermission,
  });

  final AveraFeature feature;
  final String? requiredPermission;
  final Widget Function(BuildContext context, FeatureAccessResult result)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) return const _FeatureUnavailable();
    final subscription = ref
        .watch(activeClinicSubscriptionProvider)
        .valueOrNull;
    final result = FeatureGateService.evaluate(
      subscriptionPlan:
          subscription?.plan.label ?? session.clinic.subscriptionPlan,
      subscriptionStatus: subscription?.status.name ?? 'active',
      feature: feature,
      hasPermission:
          requiredPermission == null || session.can(requiredPermission!),
    );
    return builder(context, result);
  }
}

class LockedFeatureCard extends StatelessWidget {
  const LockedFeatureCard({super.key, required this.result});

  final FeatureAccessResult result;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(result.entitlement.label)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    result.reason == FeatureAccessReason.permissionDenied
                        ? 'You do not have permission to use this feature.'
                        : '${result.entitlement.label} requires ${result.requiredPlan.label}',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(result.entitlement.reason, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: () => context.push('/subscription'),
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label: const Text('Upgrade'),
                      ),
                      OutlinedButton(
                        onPressed: () => context.push('/subscription/compare'),
                        child: const Text('Compare Plans'),
                      ),
                    ],
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

class _FeatureUnavailable extends StatelessWidget {
  const _FeatureUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feature unavailable')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This feature is unavailable.',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your clinic plan needs to be verified.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => context.push('/subscription'),
                          icon: const Icon(Icons.workspace_premium_outlined),
                          label: const Text('Upgrade'),
                        ),
                        OutlinedButton(
                          onPressed: () => context.push('/subscription'),
                          child: const Text('Compare Plans'),
                        ),
                      ],
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
}
