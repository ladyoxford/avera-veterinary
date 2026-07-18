import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/subscription_repository.dart';
import '../../../core/services/feature_gate_service.dart';

class SubscriptionPlansScreen extends ConsumerWidget {
  const SubscriptionPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final subscription = ref
        .watch(activeClinicSubscriptionProvider)
        .valueOrNull;
    final usage = ref.watch(subscriptionUsageProvider).valueOrNull;
    final currentPlan =
        subscription?.plan ??
        SubscriptionPlan.fromStorage(
          session?.clinic.subscriptionPlan ?? SubscriptionPlan.starter.label,
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions & Plans', maxLines: 1),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/subscription/compare'),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('Compare'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(
            'Subscriptions & Plans',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose the clinical intelligence and operational depth that fits your clinic.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _CurrentPlanBanner(
            plan: currentPlan,
            status: subscription?.status ?? SubscriptionStatus.active,
          ),
          if (usage != null) ...[
            const SizedBox(height: 16),
            _UsagePanel(plan: currentPlan, usage: usage),
          ],
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 3
                  : constraints.maxWidth >= 690
                  ? 2
                  : 1;
              if (columns == 1) {
                return Column(
                  children: [
                    for (final plan in SubscriptionPlan.values) ...[
                      _PlanCard(plan: plan, currentPlan: currentPlan),
                      if (plan != SubscriptionPlan.enterprise)
                        const SizedBox(height: 14),
                    ],
                  ],
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: SubscriptionPlan.values.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: columns == 3 ? .66 : .73,
                ),
                itemBuilder: (context, index) => _PlanCard(
                  plan: SubscriptionPlan.values[index],
                  currentPlan: currentPlan,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _VeraComparison(currentPlan: currentPlan),
        ],
      ),
    );
  }
}

class SubscriptionCompareScreen extends StatelessWidget {
  const SubscriptionCompareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<FeatureEntitlement>>{};
    for (final detail in FeatureGateService.all) {
      (groups[detail.category] ??= []).add(detail);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Compare Plans')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(
            'Compare Plans',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Included capabilities, limits, and future releases at a glance.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          for (final group in groups.entries) ...[
            Text(group.key, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(
                      label: SizedBox(width: 190, child: Text('Capability')),
                    ),
                    DataColumn(label: Text('Starter')),
                    DataColumn(label: Text('Professional')),
                    DataColumn(label: Text('Enterprise')),
                  ],
                  rows: group.value
                      .map(
                        (detail) => DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 190,
                                child: Text(
                                  detail.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            for (final plan in SubscriptionPlan.values)
                              DataCell(
                                _CapabilityState(detail: detail, plan: plan),
                              ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

class PlatformDeveloperSettingsScreen extends ConsumerWidget {
  const PlatformDeveloperSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _DeveloperDenied(),
      data: (value) {
        if (!value.isPlatformOwner ||
            !BackendConfiguration.isLocalMode ||
            !kDebugMode) {
          return const _DeveloperDenied();
        }
        final current = SubscriptionPlan.fromStorage(
          value.clinic.subscriptionPlan,
        );
        return Scaffold(
          appBar: AppBar(title: const Text('Developer Settings')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Local Development',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Plan simulation updates local capabilities without deleting clinic data.',
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.science_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Simulate Subscription Plan',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Starter, Professional, and Enterprise capability gates refresh immediately.',
                      ),
                      const SizedBox(height: 18),
                      SegmentedButton<SubscriptionPlan>(
                        segments: [
                          for (final plan in SubscriptionPlan.values)
                            ButtonSegment(value: plan, label: Text(plan.label)),
                        ],
                        selected: {current},
                        onSelectionChanged: (selection) async {
                          await ref
                              .read(clinicRepositoryProvider)
                              .simulateSubscriptionPlan(
                                actingSession: value,
                                plan: selection.first,
                              );
                          ref.invalidate(userSessionProvider);
                          ref.invalidate(activeClinicSubscriptionProvider);
                          ref.invalidate(subscriptionUsageProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Local plan simulated as ${selection.first.label}.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CurrentPlanBanner extends StatelessWidget {
  const _CurrentPlanBanner({required this.plan, required this.status});
  final SubscriptionPlan plan;
  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final definition = FeatureGateService.plan(plan);
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            color: colors.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT PLAN',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${plan.label} • ${definition.veraLevel}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          Chip(
            label: Text(
              status.name == 'gracePeriod' ? 'Grace period' : status.name,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _UsagePanel extends StatelessWidget {
  const _UsagePanel({required this.plan, required this.usage});
  final SubscriptionPlan plan;
  final SubscriptionUsageSummary usage;

  @override
  Widget build(BuildContext context) {
    final definition = FeatureGateService.plan(plan);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usage', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            _UsageLine(
              label: 'Active patients',
              used: usage.activePatients,
              limit: definition.patientLimit,
            ),
            const SizedBox(height: 12),
            _UsageLine(
              label: 'Active staff',
              used: usage.activeStaff,
              limit: definition.staffLimit,
            ),
            const SizedBox(height: 12),
            _UsageLine(
              label: 'Clinic workspaces',
              used: usage.clinics,
              limit: definition.clinicLimit,
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageLine extends StatelessWidget {
  const _UsageLine({
    required this.label,
    required this.used,
    required this.limit,
  });
  final String label;
  final int used;
  final int? limit;
  @override
  Widget build(BuildContext context) {
    final ratio = limit == null ? 0.0 : (used / limit!).clamp(0.0, 1.0);
    final warning = ratio >= .95
        ? Theme.of(context).colorScheme.error
        : ratio >= .8
        ? Colors.orange
        : Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(limit == null ? '$used • Unlimited' : '$used / $limit'),
          ],
        ),
        if (limit != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: ratio, color: warning),
        ],
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.currentPlan});
  final SubscriptionPlan plan;
  final SubscriptionPlan currentPlan;

  @override
  Widget build(BuildContext context) {
    final definition = FeatureGateService.plan(plan);
    final colors = Theme.of(context).colorScheme;
    final isCurrent = plan == currentPlan;
    final isProfessional = definition.isMostPopular;
    final isEnterprise = definition.isContactSales;
    final borderColor = isProfessional
        ? colors.primary
        : isEnterprise
        ? colors.tertiary
        : colors.outlineVariant;
    final highlights = _highlights(plan);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: isProfessional ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
        color: isEnterprise
            ? colors.tertiaryContainer.withValues(alpha: .32)
            : colors.surface,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isCurrent)
                const Chip(
                  label: Text('CURRENT PLAN'),
                  visualDensity: VisualDensity.compact,
                ),
              if (isProfessional)
                const Chip(
                  label: Text('MOST POPULAR'),
                  visualDensity: VisualDensity.compact,
                ),
              if (isEnterprise)
                const Chip(
                  label: Text('CONTACT SALES'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(plan.label, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 7),
          Text(
            definition.positioning,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text(
            definition.monthlyPriceLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 3),
          Text(
            definition.annualPriceLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text('Best for', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            definition.targetCustomer,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Includes', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final item in highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          const Spacer(),
          const Divider(height: 28),
          Text('Vera AI', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            definition.veraLevel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(_veraDetail(plan), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Current Plan'),
                  )
                : isEnterprise
                ? FilledButton.icon(
                    onPressed: () => _contactSales(context),
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('Contact Sales'),
                  )
                : OutlinedButton.icon(
                    onPressed: () => _contactSales(context),
                    icon: const Icon(Icons.upgrade_rounded),
                    label: Text('Upgrade to ${plan.label}'),
                  ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => context.push('/subscription/compare'),
              child: const Text('Compare Plans'),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _highlights(SubscriptionPlan plan) => switch (plan) {
    SubscriptionPlan.starter => const [
      'Patients, owners, consultations and Medical Files',
      'Vaccinations, prescriptions, billing, schedule and local backup',
      'Basic laboratory, inventory and essential reports',
    ],
    SubscriptionPlan.professional => const [
      'Everything in Starter',
      'Hospitalization, Treatment Board, surgery and advanced clinical workflows',
      'Advanced reporting, inventory operations and client automation placeholders',
    ],
    SubscriptionPlan.enterprise => const [
      'Everything in Professional',
      'Cross-clinic intelligence, central inventory and corporate controls',
      'Enterprise automation, integrations and governance placeholders',
    ],
  };

  String _veraDetail(SubscriptionPlan plan) => switch (plan) {
    SubscriptionPlan.starter =>
      'General veterinary information without patient context. Coming Soon.',
    SubscriptionPlan.professional =>
      'Patient-aware clinical support, with veterinarian review. Coming Soon.',
    SubscriptionPlan.enterprise =>
      'Organisation-wide clinical and predictive intelligence. Planned.',
  };

  Future<void> _contactSales(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contact AVERA Sales'),
        content: const Text(
          'For local plan testing, use Platform Owner Developer Settings. For a commercial plan, contact sales@avera.vet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: 'sales@avera.vet'),
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sales email copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Email'),
          ),
        ],
      ),
    );
  }
}

class _CapabilityState extends StatelessWidget {
  const _CapabilityState({required this.detail, required this.plan});
  final FeatureEntitlement detail;
  final SubscriptionPlan plan;
  @override
  Widget build(BuildContext context) {
    final included = plan.index >= detail.minimumPlan.index;
    if (!included) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove_rounded, size: 18),
          SizedBox(width: 5),
          Text('Not included'),
        ],
      );
    }
    final status = detail.implementationStatus;
    if (status != FeatureImplementationStatus.available &&
        status != FeatureImplementationStatus.limited) {
      return Text(
        status.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_rounded, size: 18),
        SizedBox(width: 5),
        Text('Included'),
      ],
    );
  }
}

class _VeraComparison extends StatelessWidget {
  const _VeraComparison({required this.currentPlan});
  final SubscriptionPlan currentPlan;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Vera AI progression',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Vera is AVERA’s clinical intelligence upgrade path. AI recommendations support, not replace, professional veterinary judgement.',
          ),
          const SizedBox(height: 16),
          for (final plan in SubscriptionPlan.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                plan == currentPlan
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              title: Text(
                '${plan.label} • ${FeatureGateService.plan(plan).veraLevel}',
              ),
              subtitle: Text(switch (plan) {
                SubscriptionPlan.starter =>
                  'General veterinary assistance without patient context • Coming Soon',
                SubscriptionPlan.professional =>
                  'Patient-aware clinical support and case-level history • Coming Soon',
                SubscriptionPlan.enterprise =>
                  'Longitudinal organisation-wide intelligence • Planned',
              }),
            ),
        ],
      ),
    ),
  );
}

class _DeveloperDenied extends StatelessWidget {
  const _DeveloperDenied();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Developer plan simulation is available only to the local Platform Owner.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
