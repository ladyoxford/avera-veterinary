import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/subscription_repository.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/services/feature_gate_service.dart';
import '../../../core/services/subscription_receipt_service.dart';
import '../../../core/subscription/subscription_plan_config.dart'
    show SubscriptionPlanCatalogue;
import '../../../core/subscription/subscription_payment_gateway.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/security/access_control.dart';
import '../../shared/widgets/avera_ui.dart';

class SubscriptionPlansScreen extends ConsumerStatefulWidget {
  const SubscriptionPlansScreen({super.key});

  @override
  ConsumerState<SubscriptionPlansScreen> createState() =>
      _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState
    extends ConsumerState<SubscriptionPlansScreen> {
  SubscriptionBillingCycle _cycle = SubscriptionBillingCycle.monthly;
  SubscriptionPlan? _selectedPlan;
  String? _pendingReference;
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(userSessionProvider);
    if (sessionState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = sessionState.valueOrNull;
    if (session == null) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You do not have permission to access this administration area.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final subscriptionState = ref.watch(activeClinicSubscriptionProvider);
    final billingState = ref.watch(subscriptionBillingProvider);
    final canManage = session.can(Permissions.subscriptionsManage);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription', maxLines: 1),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/subscription/compare'),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('Compare'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: billingState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _SubscriptionLoadError(
          onRetry: () {
            ref.invalidate(subscriptionBillingProvider);
            ref.invalidate(activeClinicSubscriptionProvider);
          },
        ),
        data: (billing) {
          final localSubscription = subscriptionState.valueOrNull;
          final currentPlan =
              billing.subscription?.plan ?? localSubscription?.plan;
          _selectedPlan ??= currentPlan ?? SubscriptionPlan.starter;
          final selected = billing.plans
              .where((item) => item.plan == _selectedPlan)
              .firstOrNull;
          final checkoutConfigured =
              selected?.checkoutConfiguredFor(_cycle) == true;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              const AveraPageHeader(
                title: 'Subscription',
                subtitle: 'Review your clinic plan, billing and renewal.',
              ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              const Text('CURRENT SUBSCRIPTION'),
              const SizedBox(height: AveraSpacing.compactRowGap),
              _SubscriptionSummaryCard(
                plan: currentPlan,
                localSubscription: localSubscription,
                serverSubscription: billing.subscription,
              ),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(
                title: 'Billing Cycle',
                subtitle: 'Choose monthly or annual billing.',
              ),
              const SizedBox(height: AveraSpacing.compactRowGap),
              SegmentedButton<SubscriptionBillingCycle>(
                segments: [
                  const ButtonSegment(
                    value: SubscriptionBillingCycle.monthly,
                    label: Text('Monthly'),
                  ),
                  ButtonSegment(
                    value: SubscriptionBillingCycle.annual,
                    label: const Text('Annually'),
                    enabled: billing.plans.any(
                      (plan) => plan.annualAmountMinor != null,
                    ),
                  ),
                ],
                selected: {_cycle},
                onSelectionChanged: (value) =>
                    setState(() => _cycle = value.first),
              ),
              if (!billing.plans.any(
                (plan) => plan.annualAmountMinor != null,
              )) ...[
                const SizedBox(height: 8),
                Text(
                  'Annual billing has not been configured.',
                  style: averaText(context).caption,
                ),
              ],
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(
                title: 'Plans',
                subtitle: 'Select a plan to review its billing action.',
              ),
              const SizedBox(height: AveraSpacing.compactRowGap),
              for (var index = 0; index < billing.plans.length; index++) ...[
                _BillingPlanCard(
                  plan: billing.plans[index],
                  cycle: _cycle,
                  selected: billing.plans[index].plan == _selectedPlan,
                  current: billing.plans[index].plan == currentPlan,
                  onTap: () =>
                      setState(() => _selectedPlan = billing.plans[index].plan),
                ),
                if (index != billing.plans.length - 1)
                  const SizedBox(height: AveraSpacing.cardGap),
              ],
              if (billing.plans.isEmpty) ...[
                const AveraSurfaceCard(
                  child: Text(
                    'Billing plans have not been configured. Retry after the server plan catalogue is available.',
                  ),
                ),
              ],
              const SizedBox(height: AveraSpacing.cardGap),
              if (canManage)
                AveraPrimaryActionButton(
                  label: _ctaLabel(
                    selected: _selectedPlan,
                    current: currentPlan,
                    status:
                        billing.subscription?.status ??
                        localSubscription?.status.name,
                  ),
                  icon: Icons.open_in_browser_rounded,
                  loading: _working,
                  onPressed:
                      checkoutConfigured &&
                          _selectedPlan != currentPlan &&
                          _selectedPlan != null
                      ? () => _startCheckout(
                          clinicId: session.clinic.clinicId,
                          plan: _selectedPlan!,
                        )
                      : null,
                )
              else
                const AveraSurfaceCard(
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You can view the current plan. Payment controls require subscription management permission.',
                        ),
                      ),
                    ],
                  ),
                ),
              if (!checkoutConfigured && _selectedPlan != currentPlan) ...[
                const SizedBox(height: 8),
                Text(
                  'This plan and billing cycle are not configured for online payment.',
                  textAlign: TextAlign.center,
                  style: averaText(context).caption,
                ),
              ],
              if (_pendingReference != null) ...[
                const SizedBox(height: AveraSpacing.cardGap),
                _PendingPaymentCard(
                  reference: _pendingReference!,
                  checking: _working,
                  onCheck: _checkPayment,
                  onCancel: () {
                    setState(() => _pendingReference = null);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment cancelled.')),
                    );
                  },
                ),
              ],
              if (canManage) ...[
                const SizedBox(height: AveraSpacing.sectionGap),
                AveraSectionHeader(
                  title: 'Billing History',
                  subtitle: billing.payments.isEmpty
                      ? 'No server payment transactions are available.'
                      : 'Verified and pending subscription payments.',
                ),
                const SizedBox(height: AveraSpacing.compactRowGap),
                if (billing.payments.isEmpty)
                  const AveraSurfaceCard(child: Text('No billing history yet.'))
                else
                  for (
                    var index = 0;
                    index < billing.payments.length;
                    index++
                  ) ...[
                    _PaymentHistoryCard(
                      payment: billing.payments[index],
                      clinicName: session.clinic.clinicName,
                    ),
                    if (index != billing.payments.length - 1)
                      const SizedBox(height: AveraSpacing.cardGap),
                  ],
                if (billing.subscription != null) ...[
                  const SizedBox(height: AveraSpacing.sectionGap),
                  AveraSectionHeader(
                    title: 'Subscription Management',
                    subtitle: billing.subscription!.cancelAtPeriodEnd
                        ? 'Access remains active through the paid period.'
                        : 'Automatic renewal is currently enabled.',
                  ),
                  const SizedBox(height: AveraSpacing.compactRowGap),
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () => _toggleRenewal(
                            session.clinic.clinicId,
                            reactivate: billing.subscription!.cancelAtPeriodEnd,
                          ),
                    icon: Icon(
                      billing.subscription!.cancelAtPeriodEnd
                          ? Icons.restart_alt_rounded
                          : Icons.pause_circle_outline_rounded,
                    ),
                    label: Text(
                      billing.subscription!.cancelAtPeriodEnd
                          ? 'Reactivate Renewal'
                          : 'Turn Off Automatic Renewal',
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _startCheckout({
    required String clinicId,
    required SubscriptionPlan plan,
  }) async {
    setState(() => _working = true);
    try {
      final checkout = await ref
          .read(subscriptionPaymentGatewayProvider)
          .initializeCheckout(
            clinicId: clinicId,
            plan: plan,
            billingCycle: _cycle,
          );
      if (!mounted) return;
      setState(() => _pendingReference = checkout.reference);
      final opened = await launchUrl(
        checkout.authorizationUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const ApiException(
          'checkout_unavailable',
          'The secure payment page could not be opened.',
        );
      }
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _checkPayment() async {
    final reference = _pendingReference;
    if (reference == null) return;
    setState(() => _working = true);
    try {
      final subscription = await ref
          .read(subscriptionPaymentGatewayProvider)
          .verifyPayment(reference);
      if (subscription == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment is still pending.')),
          );
        }
        return;
      }
      ref.invalidate(subscriptionBillingProvider);
      ref.invalidate(activeClinicSubscriptionProvider);
      if (mounted) {
        setState(() => _pendingReference = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment confirmed securely.')),
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'payment_pending') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment is still pending.')),
        );
      } else {
        _showError(
          error.code == 'payment_not_successful'
              ? 'Payment verification failed.'
              : error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleRenewal(
    String clinicId, {
    required bool reactivate,
  }) async {
    setState(() => _working = true);
    try {
      final gateway = ref.read(subscriptionPaymentGatewayProvider);
      if (reactivate) {
        await gateway.reactivateSubscription(clinicId);
      } else {
        await gateway.cancelRenewal(clinicId);
      }
      ref.invalidate(subscriptionBillingProvider);
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class SubscriptionPaymentCallbackScreen extends ConsumerStatefulWidget {
  const SubscriptionPaymentCallbackScreen({super.key, this.reference});

  final String? reference;

  @override
  ConsumerState<SubscriptionPaymentCallbackScreen> createState() =>
      _SubscriptionPaymentCallbackScreenState();
}

class _SubscriptionPaymentCallbackScreenState
    extends ConsumerState<SubscriptionPaymentCallbackScreen> {
  String? _error;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  Future<void> _verify() async {
    final reference = widget.reference?.trim();
    if (reference == null || reference.isEmpty) {
      setState(() => _error = 'The payment reference is missing.');
      return;
    }
    try {
      await ref
          .read(subscriptionPaymentGatewayProvider)
          .verifyPayment(reference);
      ref.invalidate(subscriptionBillingProvider);
      ref.invalidate(activeClinicSubscriptionProvider);
      if (mounted) setState(() => _confirmed = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Confirming Payment')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _confirmed
                  ? Icons.check_circle_rounded
                  : _error != null
                  ? Icons.error_outline_rounded
                  : Icons.sync_rounded,
              size: 48,
              color: _confirmed
                  ? Theme.of(context).extension<AppSemanticColors>()!.success
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              _confirmed
                  ? 'Payment confirmed'
                  : _error ?? 'Confirming payment securely...',
              textAlign: TextAlign.center,
              style: averaText(context).sectionTitle,
            ),
            const SizedBox(height: 20),
            if (_error != null)
              FilledButton.icon(
                onPressed: () {
                  setState(() => _error = null);
                  _verify();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              )
            else if (_confirmed)
              FilledButton(
                onPressed: () => context.go('/subscription'),
                child: const Text('View Subscription'),
              )
            else
              const CircularProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}

class _SubscriptionSummaryCard extends StatelessWidget {
  const _SubscriptionSummaryCard({
    required this.plan,
    required this.localSubscription,
    required this.serverSubscription,
  });

  final SubscriptionPlan? plan;
  final LocalClinicSubscription? localSubscription;
  final ServerClinicSubscription? serverSubscription;

  @override
  Widget build(BuildContext context) {
    final status =
        serverSubscription?.status ??
        localSubscription?.status.name ??
        'Unconfigured';
    final periodStart =
        serverSubscription?.currentPeriodStart ?? localSubscription?.startedAt;
    final periodEnd =
        serverSubscription?.currentPeriodEnd ?? localSubscription?.expiresAt;
    final format = DateFormat.yMMMd();
    return AveraSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan?.label ?? 'No plan',
                  style: averaText(context).sectionTitle,
                ),
              ),
              _SubscriptionStatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryLine(
            label: 'Billing cycle',
            value: serverSubscription?.billingCycle.name ?? 'Local plan',
          ),
          const Divider(height: 24),
          _SummaryLine(
            label: 'Paid period',
            value: periodStart == null
                ? 'Not configured'
                : periodEnd == null
                ? 'From ${format.format(periodStart)}'
                : '${format.format(periodStart)} - ${format.format(periodEnd)}',
          ),
          const Divider(height: 24),
          _SummaryLine(
            label: 'Next payment',
            value: serverSubscription?.nextBillingDate == null
                ? 'Not configured'
                : format.format(serverSubscription!.nextBillingDate!),
          ),
          const Divider(height: 24),
          _SummaryLine(
            label: 'Automatic renewal',
            value: serverSubscription == null
                ? 'Not configured'
                : serverSubscription!.cancelAtPeriodEnd
                ? 'Off'
                : 'On',
          ),
          const Divider(height: 24),
          _SummaryLine(
            label: 'Payment gateway',
            value: serverSubscription?.gateway ?? 'Not configured',
          ),
          const Divider(height: 24),
          _SummaryLine(
            label: 'Reference',
            value: serverSubscription?.id ?? 'Local subscription',
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label, style: averaText(context).listItemSubtitle)),
      const SizedBox(width: 16),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: averaText(context).fieldValue,
        ),
      ),
    ],
  );
}

class _SubscriptionStatusBadge extends StatelessWidget {
  const _SubscriptionStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = status.toLowerCase();
    final color = normalized == 'active'
        ? Theme.of(context).extension<AppSemanticColors>()!.success
        : normalized.contains('past') ||
              normalized.contains('failed') ||
              normalized.contains('expired')
        ? scheme.error
        : normalized.contains('pending') || normalized.contains('trial')
        ? Theme.of(context).extension<AppSemanticColors>()!.warning
        : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: averaText(
          context,
        ).caption.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BillingPlanCard extends StatelessWidget {
  const _BillingPlanCard({
    required this.plan,
    required this.cycle,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final SubscriptionBillingPlan plan;
  final SubscriptionBillingCycle cycle;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final config = SubscriptionPlanCatalogue.plan(plan.plan);
    final scheme = Theme.of(context).colorScheme;
    final accent = plan.plan == SubscriptionPlan.enterprise
        ? scheme.tertiary
        : plan.plan == SubscriptionPlan.professional
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final amount = plan.amountFor(cycle);
    final price = amount == null
        ? 'Not configured'
        : '${NumberFormat.simpleCurrency(name: plan.currency, decimalDigits: 0).format(amount / 100)} / ${cycle == SubscriptionBillingCycle.monthly ? 'month' : 'year'}';
    return Semantics(
      button: true,
      selected: selected,
      label: '${plan.name}. $price',
      child: Material(
        color: selected
            ? accent.withValues(alpha: .08)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
          side: BorderSide(
            color: selected ? accent : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AveraSpacing.largeCardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            plan.name,
                            style: averaText(context).sectionTitle,
                          ),
                          if (config.isRecommended)
                            const Chip(
                              label: Text('RECOMMENDED'),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (current)
                            const Chip(
                              label: Text('CURRENT PLAN'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected ? accent : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(plan.tagline, style: averaText(context).fieldValue),
                const SizedBox(height: 12),
                Text(
                  price,
                  style: averaText(
                    context,
                  ).listItemTitle.copyWith(color: accent),
                ),
                const SizedBox(height: 16),
                for (final benefit in config.highlightBenefits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_rounded, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            benefit,
                            style: averaText(context).listItemSubtitle,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingPaymentCard extends StatelessWidget {
  const _PendingPaymentCard({
    required this.reference,
    required this.checking,
    required this.onCheck,
    required this.onCancel,
  });

  final String reference;
  final bool checking;
  final VoidCallback onCheck;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    outlined: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Pending', style: averaText(context).listItemTitle),
        const SizedBox(height: 6),
        Text(
          'Reference: $reference',
          style: averaText(context).listItemSubtitle,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: checking ? null : onCheck,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Check Payment Status'),
            ),
            TextButton(
              onPressed: checking ? null : onCancel,
              child: const Text('Cancel Payment'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PaymentHistoryCard extends StatelessWidget {
  const _PaymentHistoryCard({required this.payment, required this.clinicName});

  final SubscriptionPaymentRecord payment;
  final String clinicName;

  @override
  Widget build(BuildContext context) {
    final date = payment.paidAt ?? payment.createdAt;
    final amount = NumberFormat.simpleCurrency(
      name: payment.currency,
      decimalDigits: 0,
    ).format(payment.amountMinor / 100);
    return AveraSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.receipt_long_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${payment.plan.label} - $amount',
                  style: averaText(context).listItemTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  '${payment.billingCycle.name} - ${DateFormat.yMMMd().format(date)}\n${payment.reference}',
                  style: averaText(context).listItemSubtitle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _SubscriptionStatusBadge(status: payment.status),
              if (payment.status.toLowerCase() == 'successful')
                IconButton(
                  tooltip: 'Receipt',
                  onPressed: () => const SubscriptionReceiptService()
                      .printReceipt(clinicName: clinicName, payment: payment),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _ctaLabel({
  required SubscriptionPlan? selected,
  required SubscriptionPlan? current,
  required String? status,
}) {
  if (selected == null) return 'Select a Plan';
  if (selected == current) {
    if (status?.toLowerCase().contains('pending') == true) {
      return 'Complete Payment';
    }
    if (status?.toLowerCase().contains('expired') == true) {
      return 'Renew ${selected.label}';
    }
    return 'Current Plan';
  }
  if (current == null) return 'Subscribe to ${selected.label}';
  return selected.index > current.index
      ? 'Upgrade to ${selected.label}'
      : 'Switch to ${selected.label}';
}

class _SubscriptionLoadError extends StatelessWidget {
  const _SubscriptionLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40),
          const SizedBox(height: 12),
          Text(
            'We could not load this clinic\'s subscription.',
            textAlign: TextAlign.center,
            style: averaText(context).listItemTitle,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
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
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bioqarah Supplier Receipt',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Receive invoice 300519 into the active clinic once. Unpriced products are received but cannot be sold.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () =>
                            _importBioqarahReceipt(context, ref, value),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Receive Invoice 300519'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.dataset_linked_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Load Test Dataset',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Creates an isolated 500-patient Metropolitan Hospital for local performance testing. It never changes Avera Veterinary Clinic.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: () =>
                                _runLoadTestAction(context, ref, reset: false),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Generate 500-Patient Hospital'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _runLoadTestAction(context, ref, reset: true),
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset Stress-Test Hospital'),
                          ),
                        ],
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

  static Future<void> _runLoadTestAction(
    BuildContext context,
    WidgetRef ref, {
    required bool reset,
  }) async {
    final seeder = ref.read(hospitalLoadTestSeederProvider);
    if (reset) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reset stress-test hospital?'),
          content: const Text(
            'Only records generated for AVERA Metropolitan Veterinary Hospital will be removed. The separate clinic administrator remains available.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reset'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Preparing the local stress-test dataset...')),
          ],
        ),
      ),
    );
    try {
      if (reset) {
        await seeder.resetLargeHospital();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stress-test hospital data was reset.')),
        );
      } else {
        final result = await seeder.seedLargeHospital();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.alreadyExisted
                  ? 'Dataset already exists: ${result.patients} patients.'
                  : 'Dataset created: ${result.patients} patients, ${result.consultations} consultations, ${result.vaccinations} vaccinations.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load-test action failed: $error')),
      );
    }
  }

  static Future<void> _importBioqarahReceipt(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    try {
      await ref.read(bioqarahReceiptImporterProvider).importFor(session);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice 300519 received into inventory.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

// Legacy private widget retained temporarily for developer-screen compatibility.
// ignore: unused_element
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

// ignore: unused_element
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

// ignore: unused_element
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.currentPlan});
  final SubscriptionPlan plan;
  final SubscriptionPlan currentPlan;

  @override
  Widget build(BuildContext context) {
    final definition = FeatureGateService.plan(plan);
    final display = SubscriptionPlanCatalogue.plan(plan);
    final colors = Theme.of(context).colorScheme;
    final isCurrent = plan == currentPlan;
    final isProfessional = definition.isMostPopular;
    final isEnterprise = definition.isContactSales;
    final borderColor = isProfessional
        ? colors.primary
        : isEnterprise
        ? colors.tertiary
        : colors.outlineVariant;
    final highlights = display.highlightBenefits;
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
          Text(display.tagline, style: Theme.of(context).textTheme.bodyLarge),
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
          Text(display.bestFor, style: Theme.of(context).textTheme.bodyMedium),
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

// ignore: unused_element
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
