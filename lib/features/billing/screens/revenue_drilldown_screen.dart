import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/backend_configuration.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../models/revenue_metric.dart';
import '../models/revenue_period.dart';

class RevenueDrilldownScreen extends ConsumerStatefulWidget {
  const RevenueDrilldownScreen({
    super.key,
    required this.metric,
    required this.period,
    required this.range,
    required this.summary,
    required this.currency,
  });

  final RevenueMetric metric;
  final RevenuePeriod period;
  final RevenueDateRange range;
  final RevenueProfitSummary summary;
  final String currency;

  @override
  ConsumerState<RevenueDrilldownScreen> createState() =>
      _RevenueDrilldownScreenState();
}

class _RevenueDrilldownScreenState
    extends ConsumerState<RevenueDrilldownScreen> {
  final _scrollController = ScrollController();
  final _rows = <RemoteRevenueDrilldownRow>[];
  var _page = 0;
  var _total = 0;
  var _totalValue = 0.0;
  var _hasNext = true;
  var _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadNearEnd);
    if (widget.metric != RevenueMetric.margin) _loadNext();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadNearEnd)
      ..dispose();
    super.dispose();
  }

  void _loadNearEnd() {
    if (_scrollController.position.extentAfter < 320) _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasNext) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!BackendConfiguration.isConfigured) {
        throw StateError(
          'Financial drill-down requires the connected clinic service.',
        );
      }
      final nextPage = _page + 1;
      final result = await ref
          .read(clinicalRemoteDataSourceProvider)
          .revenueDrilldown(
            metric: widget.metric.apiValue,
            period: widget.period.apiValue,
            from: widget.range.start,
            to: widget.range.end,
            page: nextPage,
          );
      if (!mounted) return;
      setState(() {
        _rows.addAll(result.items);
        _page = result.page;
        _total = result.total;
        _totalValue = result.totalValue;
        _hasNext = result.hasNextPage;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.simpleCurrency(
      name: widget.currency,
      decimalDigits: 0,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.metric.label} — ${widget.period.title}'),
      ),
      body: widget.metric == RevenueMetric.margin
          ? _MarginExplanation(summary: widget.summary, money: money)
          : ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.pageTopPadding,
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.bottomContentClearance,
              ),
              children: [
                _DrilldownSummary(
                  metric: widget.metric,
                  totalValue: _totalValue,
                  totalCount: _total,
                  money: money,
                ),
                if (_hasMismatch) ...[
                  const SizedBox(height: AveraSpacing.cardGap),
                  AveraSurfaceCard(
                    color: Theme.of(context)
                        .extension<AppSemanticColors>()!
                        .warning
                        .withValues(alpha: .1),
                    child: const Text(
                      'The financial detail does not match the summary. Reload before relying on this report.',
                    ),
                  ),
                ],
                const SizedBox(height: AveraSpacing.sectionGap),
                if (_rows.isEmpty && _loading)
                  const Center(child: CircularProgressIndicator())
                else if (_rows.isEmpty && _error != null)
                  _LoadError(onRetry: _loadNext)
                else if (_rows.isEmpty)
                  const AveraSurfaceCard(
                    child: Text('No matching financial entries.'),
                  )
                else
                  for (final row in _rows) ...[
                    _FinancialRow(
                      row: row,
                      metric: widget.metric,
                      money: money,
                      onTap: () => _openInvoice(row.invoiceId),
                    ),
                    const SizedBox(height: AveraSpacing.cardGap),
                  ],
                if (_loading && _rows.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_error != null && _rows.isNotEmpty)
                  _LoadError(onRetry: _loadNext),
              ],
            ),
    );
  }

  bool get _hasMismatch {
    if (_loading || _error != null || _page == 0) return false;
    if (widget.metric == RevenueMetric.settledTransactions) {
      return _total != widget.summary.transactionCount;
    }
    return (_totalValue - _expectedValue).abs() > 0.01;
  }

  double get _expectedValue => switch (widget.metric) {
    RevenueMetric.revenue => widget.summary.revenue,
    RevenueMetric.grossProfit => widget.summary.profit,
    RevenueMetric.recordedCost => widget.summary.cost,
    RevenueMetric.clinicRevenue => widget.summary.clinicRevenue,
    RevenueMetric.farmRevenue => widget.summary.farmRevenue,
    RevenueMetric.settledTransactions => widget.summary.revenue,
    RevenueMetric.margin => widget.summary.margin,
  };

  void _openInvoice(String invoiceId) {
    if (invoiceId.isEmpty) return;
    context.push(
      '/billing/history?invoiceId=${Uri.encodeQueryComponent(invoiceId)}',
    );
  }
}

class _DrilldownSummary extends StatelessWidget {
  const _DrilldownSummary({
    required this.metric,
    required this.totalValue,
    required this.totalCount,
    required this.money,
  });

  final RevenueMetric metric;
  final double totalValue;
  final int totalCount;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final noun = metric == RevenueMetric.recordedCost
        ? 'cost lines'
        : 'transactions';
    final text = metric == RevenueMetric.settledTransactions
        ? '$totalCount payment ledger entries'
        : '${money.format(totalValue)} across $totalCount $noun';
    return AveraSurfaceCard(
      child: Text(text, style: averaText(context).sectionTitle),
    );
  }
}

class _FinancialRow extends StatelessWidget {
  const _FinancialRow({
    required this.row,
    required this.metric,
    required this.money,
    required this.onTap,
  });

  final RemoteRevenueDrilldownRow row;
  final RevenueMetric metric;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = row.occurredAt == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(row.occurredAt!.toLocal());
    return AveraSurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AveraSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.description ?? row.clientName,
                      style: averaText(context).listItemTitle,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 4),
              Text('${row.invoiceNumber} • ${row.context} • $date'),
              const SizedBox(height: 10),
              ..._amountLines(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _amountLines(BuildContext context) => switch (metric) {
    RevenueMetric.grossProfit => [
      _labelValue('Revenue', money.format(row.saleAmount ?? 0)),
      _labelValue('Recorded cost', money.format(row.recordedCost ?? 0)),
      _labelValue(
        'Gross profit',
        money.format(row.grossProfit ?? 0),
        bold: true,
      ),
      if (row.missingCostLines > 0)
        Text(
          '${row.missingCostLines} line(s) have no historical cost.',
          style: TextStyle(
            color: Theme.of(context).extension<AppSemanticColors>()!.warning,
          ),
        ),
    ],
    RevenueMetric.recordedCost => [
      _labelValue('Quantity', _quantity(row.quantity ?? 0)),
      _labelValue('Historical unit cost', money.format(row.unitCost ?? 0)),
      if ((row.historicalCost ?? 0) != (row.recordedCost ?? 0))
        _labelValue(
          'Full historical cost',
          money.format(row.historicalCost ?? 0),
        ),
      _labelValue(
        'Cost in this period',
        money.format(row.recordedCost ?? 0),
        bold: true,
      ),
    ],
    _ => [
      _labelValue(
        row.method?.isNotEmpty == true ? row.method! : 'Amount',
        money.format(row.amount ?? 0),
        bold: true,
      ),
    ],
  };

  Widget _labelValue(String label, String value, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
            ),
          ],
        ),
      );

  String _quantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(math.min(3, _decimalPlaces(value)));

  int _decimalPlaces(double value) {
    final text = value.toString();
    return text.contains('.') ? text.split('.').last.length : 0;
  }
}

class _MarginExplanation extends StatelessWidget {
  const _MarginExplanation({required this.summary, required this.money});

  final RevenueProfitSummary summary;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AveraSpacing.pageHorizontalPadding,
      AveraSpacing.pageTopPadding,
      AveraSpacing.pageHorizontalPadding,
      AveraSpacing.bottomContentClearance,
    ),
    children: [
      AveraSurfaceCard(
        child: Column(
          children: [
            _formulaRow('Revenue', money.format(summary.revenue)),
            _formulaRow('− Recorded Cost', money.format(summary.cost)),
            const Divider(),
            _formulaRow(
              '= Gross Profit',
              money.format(summary.profit),
              bold: true,
            ),
            const SizedBox(height: 24),
            _formulaRow('Gross Profit', money.format(summary.profit)),
            _formulaRow('÷ Revenue × 100', money.format(summary.revenue)),
            const Divider(),
            _formulaRow(
              '= Margin',
              '${(summary.margin * 100).toStringAsFixed(1)}%',
              bold: true,
            ),
          ],
        ),
      ),
      if (summary.revenue == 0) ...[
        const SizedBox(height: AveraSpacing.cardGap),
        const AveraSurfaceCard(
          child: Text('Margin is shown as 0% because revenue is zero.'),
        ),
      ],
      if (summary.missingCostLines > 0) ...[
        const SizedBox(height: AveraSpacing.cardGap),
        AveraSurfaceCard(
          color: Theme.of(
            context,
          ).extension<AppSemanticColors>()!.warning.withValues(alpha: .1),
          child: Text(
            '${summary.missingCostLines} invoice line(s) have no historical cost. Profit and margin may be overstated.',
          ),
        ),
      ],
    ],
  );

  Widget _formulaRow(String label, String value, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
            ),
          ],
        ),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      children: [
        const Text('Financial details are unavailable.'),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
