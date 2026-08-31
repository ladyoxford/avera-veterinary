import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/backend_configuration.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/avera_timeframe_selector.dart';
import '../models/revenue_metric.dart';
import '../models/revenue_period.dart';
import 'revenue_drilldown_screen.dart';

String missingHistoricalCostWarning(int count) =>
    '$count invoice line(s) have no historical cost. '
    'Profit may be overstated until historical cost is added.';

Future<RevenuePeriod?> showRevenuePeriodPicker(
  BuildContext context,
  RevenuePeriod current,
) => showAveraTimeframePicker(
  context,
  current,
  description: 'Choose the exact period to view revenue and profit for.',
  keyPrefix: 'revenue',
);

class RevenueProfitScreen extends ConsumerStatefulWidget {
  const RevenueProfitScreen({super.key});

  @override
  ConsumerState<RevenueProfitScreen> createState() =>
      _RevenueProfitScreenState();
}

class _RevenueProfitScreenState extends ConsumerState<RevenueProfitScreen> {
  RevenuePeriod _period = RevenuePeriod.oneMonth;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final range = _period.rangeAt(DateTime.now());
    final future = _loadSummary(session, range);
    final money = NumberFormat.simpleCurrency(
      name: session.clinic.currency,
      decimalDigits: 0,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Revenue & Profit')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          Text(
            'Verified payments, costs, and operating margin.',
            style: averaText(context).pageSubtitle,
          ),
          const SizedBox(height: AveraSpacing.subtitleToContentGap),
          RevenueQuickPeriodSelector(
            selected: _period,
            onSelected: (period) => setState(() => _period = period),
            onMore: _selectMorePeriod,
          ),
          const SizedBox(height: AveraSpacing.sectionGap),
          FutureBuilder<RevenueProfitSummary>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return AveraSurfaceCard(
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 36),
                      const SizedBox(height: 12),
                      const Text('Revenue data is unavailable.'),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => setState(() {}),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final summary = snapshot.data!;
              void open(RevenueMetric metric) => _openDrilldown(
                metric: metric,
                period: _period,
                range: range,
                summary: summary,
                currency: session.clinic.currency,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.builder(
                    itemCount: 4,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 142,
                        ),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) => [
                      RevenueMetricCard(
                        label: 'Revenue',
                        value: money.format(summary.revenue),
                        icon: Icons.payments_outlined,
                        onTap: () => open(RevenueMetric.revenue),
                      ),
                      RevenueMetricCard(
                        label: 'Gross profit',
                        value: money.format(summary.profit),
                        icon: Icons.trending_up_rounded,
                        onTap: () => open(RevenueMetric.grossProfit),
                      ),
                      RevenueMetricCard(
                        label: 'Recorded cost',
                        value: money.format(summary.cost),
                        icon: Icons.receipt_long_outlined,
                        onTap: () => open(RevenueMetric.recordedCost),
                      ),
                      RevenueMetricCard(
                        label: 'Margin',
                        value: '${(summary.margin * 100).toStringAsFixed(1)}%',
                        icon: Icons.analytics_outlined,
                        onTap: () => open(RevenueMetric.margin),
                      ),
                    ][index],
                  ),
                  const SizedBox(height: AveraSpacing.sectionGap),
                  const AveraSectionHeader(title: 'Revenue Sources'),
                  const SizedBox(height: AveraSpacing.cardGap),
                  AveraSurfaceCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        RevenueSourceRow(
                          label: 'Clinic operations',
                          value: money.format(summary.clinicRevenue),
                          onTap: () => open(RevenueMetric.clinicRevenue),
                        ),
                        const Divider(height: 1),
                        RevenueSourceRow(
                          label: 'Farm operations',
                          value: money.format(summary.farmRevenue),
                          onTap: () => open(RevenueMetric.farmRevenue),
                        ),
                        const Divider(height: 1),
                        RevenueSourceRow(
                          label: 'Settled transactions',
                          value: '${summary.transactionCount}',
                          onTap: () => open(RevenueMetric.settledTransactions),
                        ),
                      ],
                    ),
                  ),
                  if (summary.missingCostLines > 0) ...[
                    const SizedBox(height: AveraSpacing.cardGap),
                    AveraSurfaceCard(
                      color: Theme.of(context)
                          .extension<AppSemanticColors>()!
                          .warning
                          .withValues(alpha: .1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(
                              context,
                            ).extension<AppSemanticColors>()!.warning,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              missingHistoricalCostWarning(
                                summary.missingCostLines,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (summary.transactionCount == 0) ...[
                    const SizedBox(height: AveraSpacing.cardGap),
                    const AveraSurfaceCard(
                      child: Text(
                        'No payment or refund ledger entries exist for this period.',
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _selectMorePeriod() async {
    final selected = await showRevenuePeriodPicker(context, _period);
    if (selected != null && mounted) {
      setState(() => _period = selected);
    }
  }

  Future<void> _openDrilldown({
    required RevenueMetric metric,
    required RevenuePeriod period,
    required RevenueDateRange range,
    required RevenueProfitSummary summary,
    required String currency,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RevenueDrilldownScreen(
        metric: metric,
        period: period,
        range: range,
        summary: summary,
        currency: currency,
      ),
    ),
  );

  Future<RevenueProfitSummary> _loadSummary(
    UserSession session,
    RevenueDateRange range,
  ) async {
    final repository = ref.read(clinicRepositoryProvider);
    if (!BackendConfiguration.isConfigured) {
      return repository.getRevenueProfitSummary(
        session: session,
        from: range.start,
        to: range.end,
      );
    }
    try {
      final remote = await ref
          .read(clinicalRemoteDataSourceProvider)
          .revenueProfitSummary(
            period: _period.apiValue,
            from: range.start,
            to: range.end,
          );
      return RevenueProfitSummary(
        revenue: remote.revenue,
        cost: remote.cost,
        clinicRevenue: remote.clinicRevenue,
        farmRevenue: remote.farmRevenue,
        transactionCount: remote.transactionCount,
        missingCostLines: remote.missingCostLines,
      );
    } catch (_) {
      final cached = await repository.getRevenueProfitSummary(
        session: session,
        from: range.start,
        to: range.end,
      );
      if (cached.transactionCount > 0) return cached;
      rethrow;
    }
  }
}

class RevenueQuickPeriodSelector extends StatelessWidget {
  const RevenueQuickPeriodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onMore,
  });

  final RevenuePeriod selected;
  final ValueChanged<RevenuePeriod> onSelected;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => AveraTimeframeSelector(
    selected: selected,
    onSelected: onSelected,
    onMore: onMore,
    keyPrefix: 'revenue',
  );
}

class RevenueMetricCard extends StatelessWidget {
  const RevenueMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    padding: EdgeInsets.zero,
    child: Semantics(
      button: true,
      label: '$label, $value. Open details.',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AveraSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              Text(value, style: averaText(context).sectionTitle),
              Text(label, style: averaText(context).listItemSubtitle),
            ],
          ),
        ),
      ),
    ),
  );
}

class RevenueSourceRow extends StatelessWidget {
  const RevenueSourceRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label, $value. Open details.',
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AveraSpacing.cardPadding),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: averaText(context).listItemTitle),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}
