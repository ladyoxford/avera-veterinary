import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/billing/models/revenue_period.dart';
import 'package:avera/features/billing/screens/revenue_profit_screen.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quick selector is exactly 1D, 3D, 7D, 1M, More on one row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RevenueQuickPeriodSelector(
            selected: RevenuePeriod.oneMonth,
            onSelected: (_) {},
            onMore: () {},
          ),
        ),
      ),
    );

    expect(find.text('1D'), findsOneWidget);
    expect(find.text('3D'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.byKey(const Key('revenue-quick-period-row')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More uses AveraActionSheet and applies only after Apply', (
    tester,
  ) async {
    RevenuePeriod? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showRevenuePeriodPicker(
                  context,
                  RevenuePeriod.oneMonth,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(AveraActionSheet), findsOneWidget);
    expect(find.text('Select Timeframe'), findsOneWidget);

    await tester.tap(find.byKey(const Key('revenue-period-3m')));
    await tester.pump();
    expect(result, isNull);

    await tester.tap(find.byKey(const Key('apply-revenue-period')));
    await tester.pumpAndSettle();
    expect(result, RevenuePeriod.threeMonths);
  });

  testWidgets('metric and source surfaces expose working tap targets', (
    tester,
  ) async {
    var metricTaps = 0;
    var sourceTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 142,
                child: RevenueMetricCard(
                  label: 'Revenue',
                  value: 'NGN 100',
                  icon: Icons.payments_outlined,
                  onTap: () => metricTaps++,
                ),
              ),
              RevenueSourceRow(
                label: 'Clinic operations',
                value: 'NGN 100',
                onTap: () => sourceTaps++,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Revenue'));
    await tester.tap(find.text('Clinic operations'));
    expect(metricTaps, 1);
    expect(sourceTaps, 1);
  });
}
