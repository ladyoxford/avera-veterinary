enum RevenuePeriod {
  oneDay('1d', '1D', 'Today'),
  threeDays('3d', '3D', '3 Days'),
  sevenDays('7d', '7D', '7 Days'),
  oneWeek('1w', '1W', 'This Week'),
  oneMonth('1m', '1M', 'Last 30 Days'),
  threeMonths('3m', '3M', '3 Months'),
  sixMonths('6m', '6M', '6 Months'),
  oneYear('1y', '1Y', 'This Year'),
  threeYears('3y', '3Y', '3 Years'),
  tenYears('10y', '10Y', '10 Years'),
  allTime('all_time', 'All Time', 'All Time');

  const RevenuePeriod(this.apiValue, this.label, this.title);

  final String apiValue;
  final String label;
  final String title;

  RevenueDateRange rangeAt(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1));
    final start = switch (this) {
      RevenuePeriod.oneDay => today,
      RevenuePeriod.threeDays => today.subtract(const Duration(days: 2)),
      RevenuePeriod.sevenDays => today.subtract(const Duration(days: 6)),
      RevenuePeriod.oneWeek => DateTime(
        now.year,
        now.month,
        now.day - (now.weekday - DateTime.monday),
      ),
      RevenuePeriod.oneMonth => today.subtract(const Duration(days: 29)),
      RevenuePeriod.threeMonths => DateTime(now.year, now.month - 2),
      RevenuePeriod.sixMonths => DateTime(now.year, now.month - 5),
      RevenuePeriod.oneYear => DateTime(now.year),
      RevenuePeriod.threeYears => DateTime(now.year - 2),
      RevenuePeriod.tenYears => DateTime(now.year - 9),
      RevenuePeriod.allTime => null,
    };
    return RevenueDateRange(start: start, end: end);
  }
}

const quickRevenuePeriods = [
  RevenuePeriod.oneDay,
  RevenuePeriod.threeDays,
  RevenuePeriod.sevenDays,
  RevenuePeriod.oneMonth,
];

class RevenueDateRange {
  const RevenueDateRange({required this.start, required this.end});

  final DateTime? start;
  final DateTime end;
}
