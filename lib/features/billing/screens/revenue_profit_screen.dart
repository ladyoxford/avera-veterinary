import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/backend_configuration.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

enum RevenuePeriod { today, sevenDays, month, year, twoYears, allTime }

class RevenueProfitScreen extends ConsumerStatefulWidget {
  const RevenueProfitScreen({super.key});

  @override
  ConsumerState<RevenueProfitScreen> createState() =>
      _RevenueProfitScreenState();
}

class _RevenueProfitScreenState extends ConsumerState<RevenueProfitScreen> {
  RevenuePeriod _period = RevenuePeriod.month;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final range = _range(_period, DateTime.now());
    final future = _loadSummary(session, range.$1, range.$2);
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
          const AveraPageHeader(
            title: 'Revenue & Profit',
            subtitle: 'Verified payments, costs, and operating margin.',
          ),
          const SizedBox(height: AveraSpacing.subtitleToContentGap),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<RevenuePeriod>(
              segments: const [
                ButtonSegment(value: RevenuePeriod.today, label: Text('Today')),
                ButtonSegment(
                  value: RevenuePeriod.sevenDays,
                  label: Text('7 Days'),
                ),
                ButtonSegment(value: RevenuePeriod.month, label: Text('Month')),
                ButtonSegment(value: RevenuePeriod.year, label: Text('Year')),
                ButtonSegment(
                  value: RevenuePeriod.twoYears,
                  label: Text('2 Years'),
                ),
                ButtonSegment(
                  value: RevenuePeriod.allTime,
                  label: Text('All Time'),
                ),
              ],
              selected: {_period},
              onSelectionChanged: (value) =>
                  setState(() => _period = value.first),
            ),
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      _MetricCard(
                        label: 'Revenue',
                        value: money.format(summary.revenue),
                        icon: Icons.payments_outlined,
                      ),
                      _MetricCard(
                        label: 'Gross profit',
                        value: money.format(summary.profit),
                        icon: Icons.trending_up_rounded,
                      ),
                      _MetricCard(
                        label: 'Recorded cost',
                        value: money.format(summary.cost),
                        icon: Icons.receipt_long_outlined,
                      ),
                      _MetricCard(
                        label: 'Margin',
                        value: '${(summary.margin * 100).toStringAsFixed(1)}%',
                        icon: Icons.analytics_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: AveraSpacing.sectionGap),
                  const AveraSectionHeader(title: 'Revenue Sources'),
                  const SizedBox(height: AveraSpacing.cardGap),
                  AveraSurfaceCard(
                    child: Column(
                      children: [
                        _SourceRow(
                          label: 'Clinic operations',
                          value: money.format(summary.clinicRevenue),
                        ),
                        const Divider(height: 24),
                        _SourceRow(
                          label: 'Farm operations',
                          value: money.format(summary.farmRevenue),
                        ),
                        const Divider(height: 24),
                        _SourceRow(
                          label: 'Settled transactions',
                          value: '${summary.transactionCount}',
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
                      child: Text(
                        '${summary.missingCostLines} invoice line(s) have no historical cost. Profit excludes those unknown costs.',
                      ),
                    ),
                  ],
                  if (summary.transactionCount == 0) ...[
                    const SizedBox(height: AveraSpacing.cardGap),
                    const AveraSurfaceCard(
                      child: Text(
                        'No settled payment or refund transactions exist for this period.',
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

  Future<RevenueProfitSummary> _loadSummary(
    UserSession session,
    DateTime? from,
    DateTime? to,
  ) async {
    final repository = ref.read(clinicRepositoryProvider);
    if (!BackendConfiguration.isConfigured) {
      return repository.getRevenueProfitSummary(
        session: session,
        from: from,
        to: to,
      );
    }
    try {
      final remote = await ref
          .read(clinicalRemoteDataSourceProvider)
          .revenueProfitSummary(from: from, to: to);
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
        from: from,
        to: to,
      );
      if (cached.transactionCount > 0) return cached;
      rethrow;
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        Text(value, style: averaText(context).sectionTitle),
        Text(label, style: averaText(context).listItemSubtitle),
      ],
    ),
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(value, style: averaText(context).listItemTitle),
    ],
  );
}

(DateTime?, DateTime?) _range(RevenuePeriod period, DateTime now) {
  final end = now.add(const Duration(microseconds: 1));
  return switch (period) {
    RevenuePeriod.today => (DateTime(now.year, now.month, now.day), end),
    RevenuePeriod.sevenDays => (now.subtract(const Duration(days: 7)), end),
    RevenuePeriod.month => (DateTime(now.year, now.month), end),
    RevenuePeriod.year => (DateTime(now.year), end),
    RevenuePeriod.twoYears => (DateTime(now.year - 1), end),
    RevenuePeriod.allTime => (null, end),
  };
}
