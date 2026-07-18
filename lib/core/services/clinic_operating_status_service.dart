import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/clinic_work_hours.dart';

enum ClinicOperatingStatusKind {
  open,
  closedToday,
  opensLater,
  closedForDay,
  onBreak,
  hoursNotConfigured,
}

class ClinicOperatingStatus {
  const ClinicOperatingStatus({
    required this.kind,
    required this.label,
    required this.weeklySummary,
    this.todayOpeningTime,
    this.todayClosingTime,
    this.nextOpeningDateTime,
  });

  final ClinicOperatingStatusKind kind;
  final String label;
  final String weeklySummary;
  final String? todayOpeningTime;
  final String? todayClosingTime;
  final DateTime? nextOpeningDateTime;
}

class ClinicOperatingStatusService {
  ClinicOperatingStatusService._();

  static bool _initialized = false;

  static ClinicOperatingStatus calculate(
    ClinicWorkHoursConfig? config, {
    DateTime? now,
  }) {
    if (config == null || !config.isEnabled || config.days.isEmpty) {
      return const ClinicOperatingStatus(
        kind: ClinicOperatingStatusKind.hoursNotConfigured,
        label: 'WORK HOURS NOT SET',
        weeklySummary: 'Work hours unavailable',
      );
    }
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
    final location = _location(config.timeZone);
    final localNow = now == null
        ? tz.TZDateTime.now(location)
        : tz.TZDateTime.from(now, location);
    final weekday = clinicWeekdays[localNow.weekday - DateTime.monday];
    final today = config.dayForWeekday(weekday);
    final summary = weeklySummary(config);
    final next = _nextOpening(config, localNow);

    if (today == null || !today.isOpen) {
      return ClinicOperatingStatus(
        kind: ClinicOperatingStatusKind.closedToday,
        label: next == null
            ? 'CLOSED TODAY'
            : 'CLOSED • OPENS ${_nextLabel(next)}',
        weeklySummary: summary,
        nextOpeningDateTime: next,
      );
    }
    final opening = _atTime(localNow, today.openingTime!);
    final closing = _atTime(localNow, today.closingTime!);
    if (localNow.isBefore(opening)) {
      return ClinicOperatingStatus(
        kind: ClinicOperatingStatusKind.opensLater,
        label: 'OPENS AT ${_displayTime(today.openingTime!)}',
        weeklySummary: summary,
        todayOpeningTime: today.openingTime,
        todayClosingTime: today.closingTime,
        nextOpeningDateTime: opening,
      );
    }
    if (today.breakStart != null && today.breakEnd != null) {
      final breakStart = _atTime(localNow, today.breakStart!);
      final breakEnd = _atTime(localNow, today.breakEnd!);
      if (!localNow.isBefore(breakStart) && localNow.isBefore(breakEnd)) {
        return ClinicOperatingStatus(
          kind: ClinicOperatingStatusKind.onBreak,
          label: 'ON BREAK • REOPENS ${_displayTime(today.breakEnd!)}',
          weeklySummary: summary,
          todayOpeningTime: today.openingTime,
          todayClosingTime: today.closingTime,
          nextOpeningDateTime: breakEnd,
        );
      }
    }
    if (!localNow.isBefore(closing)) {
      return ClinicOperatingStatus(
        kind: ClinicOperatingStatusKind.closedForDay,
        label: next == null
            ? 'CLOSED FOR THE DAY'
            : 'CLOSED • OPENS ${_nextLabel(next)}',
        weeklySummary: summary,
        todayOpeningTime: today.openingTime,
        todayClosingTime: today.closingTime,
        nextOpeningDateTime: next,
      );
    }
    return ClinicOperatingStatus(
      kind: ClinicOperatingStatusKind.open,
      label: 'OPEN NOW',
      weeklySummary: summary,
      todayOpeningTime: today.openingTime,
      todayClosingTime: today.closingTime,
    );
  }

  static String weeklySummary(ClinicWorkHoursConfig config) {
    final groups = <String>[];
    var start = 0;
    while (start < config.days.length) {
      final current = config.days[start];
      var end = start;
      while (end + 1 < config.days.length &&
          _sameHours(current, config.days[end + 1])) {
        end++;
      }
      final label = start == end
          ? clinicWeekdayLabels[current.weekday]!
          : '${clinicWeekdayLabels[current.weekday]}–${clinicWeekdayLabels[config.days[end].weekday]}';
      groups.add(
        current.isOpen
            ? '$label ${_displayTime(current.openingTime!)}–${_displayTime(current.closingTime!)}'
            : '$label Closed',
      );
      start = end + 1;
    }
    return groups.join(' • ');
  }

  static bool _sameHours(ClinicWorkDayConfig a, ClinicWorkDayConfig b) =>
      a.isOpen == b.isOpen &&
      a.openingTime == b.openingTime &&
      a.closingTime == b.closingTime;

  static tz.Location _location(String name) {
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.UTC;
    }
  }

  static tz.TZDateTime _atTime(tz.TZDateTime date, String storedTime) {
    final parts = storedTime.split(':');
    return tz.TZDateTime(
      date.location,
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  static DateTime? _nextOpening(
    ClinicWorkHoursConfig config,
    tz.TZDateTime localNow,
  ) {
    for (var offset = 0; offset < 8; offset++) {
      final date = localNow.add(Duration(days: offset));
      final weekday = clinicWeekdays[date.weekday - DateTime.monday];
      final day = config.dayForWeekday(weekday);
      if (day == null || !day.isOpen || day.openingTime == null) continue;
      final opening = _atTime(date, day.openingTime!);
      if (opening.isAfter(localNow)) return opening;
    }
    return null;
  }

  static String _nextLabel(DateTime date) {
    final weekday = DateFormat('EEEE').format(date).toUpperCase();
    final stored = DateFormat('HH:mm').format(date);
    return '$weekday ${_displayTime(stored)}';
  }

  static String _displayTime(String stored) {
    final parsed = DateFormat('HH:mm').parseStrict(stored);
    return DateFormat('HH:mm').format(parsed);
  }
}
