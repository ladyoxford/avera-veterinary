import 'package:avera/features/billing/models/revenue_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 30, 8, 50);

  test('revenue periods expose the canonical supported API values', () {
    expect(RevenuePeriod.values.map((period) => period.apiValue), [
      '1d',
      '3d',
      '7d',
      '1w',
      '1m',
      '3m',
      '6m',
      '1y',
      '3y',
      '10y',
      'all_time',
    ]);
  });

  test('calendar period boundaries remain centralized and deterministic', () {
    expect(RevenuePeriod.oneDay.rangeAt(now).start!.isUtc, isFalse);
    expect(RevenuePeriod.oneDay.rangeAt(now).start, DateTime(2026, 8, 30));
    expect(RevenuePeriod.oneDay.rangeAt(now).end, DateTime(2026, 8, 31));
    expect(RevenuePeriod.oneWeek.rangeAt(now).start, DateTime(2026, 8, 24));
    expect(RevenuePeriod.oneMonth.rangeAt(now).start, DateTime(2026, 8, 1));
    expect(RevenuePeriod.threeMonths.rangeAt(now).start, DateTime(2026, 6));
    expect(RevenuePeriod.sixMonths.rangeAt(now).start, DateTime(2026, 3));
    expect(RevenuePeriod.oneYear.rangeAt(now).start, DateTime(2026));
    expect(RevenuePeriod.threeYears.rangeAt(now).start, DateTime(2024));
    expect(RevenuePeriod.tenYears.rangeAt(now).start, DateTime(2017));
    expect(RevenuePeriod.allTime.rangeAt(now).start, isNull);
  });

  test('quick periods use inclusive local calendar days', () {
    expect(RevenuePeriod.threeDays.rangeAt(now).start, DateTime(2026, 8, 28));
    expect(RevenuePeriod.sevenDays.rangeAt(now).start, DateTime(2026, 8, 24));
  });

  test('1M remains a rolling 30-day range across a month boundary', () {
    final septemberFirst = DateTime(2026, 9, 1, 8, 22);
    final range = RevenuePeriod.oneMonth.rangeAt(septemberFirst);

    expect(RevenuePeriod.oneMonth.title, 'Last 30 Days');
    expect(range.start, DateTime(2026, 8, 3));
    expect(range.end, DateTime(2026, 9, 2));
    expect(range.start!.isUtc, isFalse);
    expect(range.end.isUtc, isFalse);
  });
}
