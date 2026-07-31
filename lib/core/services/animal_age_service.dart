enum AnimalAgeUnit {
  days('Day', 'Days', 'days'),
  weeks('Week', 'Weeks', 'weeks'),
  months('Month', 'Months', 'months'),
  years('Year', 'Years', 'years');

  const AnimalAgeUnit(this.singularLabel, this.pluralLabel, this.storageValue);

  final String singularLabel;
  final String pluralLabel;
  final String storageValue;

  String labelFor(int value) => value == 1 ? singularLabel : pluralLabel;

  static AnimalAgeUnit? fromStorage(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final unit in AnimalAgeUnit.values) {
      if (unit.storageValue == normalized ||
          unit.singularLabel.toLowerCase() == normalized ||
          unit.pluralLabel.toLowerCase() == normalized) {
        return unit;
      }
    }
    return null;
  }
}

enum AnimalAgeInputMode { dateOfBirth, currentAge }

class AnimalAgeBreakdown {
  const AnimalAgeBreakdown({
    required this.years,
    required this.months,
    required this.weeks,
    required this.days,
    required this.totalDays,
  });

  final int years;
  final int months;
  final int weeks;
  final int days;
  final int totalDays;
}

class AnimalAgeService {
  const AnimalAgeService._();

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool isFutureBirthDate(DateTime birthDate, DateTime referenceDate) =>
      dateOnly(birthDate).isAfter(dateOnly(referenceDate));

  static AnimalAgeBreakdown calculateAgeBreakdown(
    DateTime birthDate,
    DateTime referenceDate,
  ) {
    final birth = dateOnly(birthDate);
    final reference = dateOnly(referenceDate);
    if (birth.isAfter(reference)) {
      throw ArgumentError.value(
        birthDate,
        'birthDate',
        'Date of birth cannot be in the future.',
      );
    }

    var years = reference.year - birth.year;
    var cursor = _addYearsClamped(birth, years);
    if (cursor.isAfter(reference)) {
      years--;
      cursor = _addYearsClamped(birth, years);
    }

    var months =
        (reference.year - cursor.year) * 12 + reference.month - cursor.month;
    var monthCursor = _addMonthsClamped(cursor, months);
    if (monthCursor.isAfter(reference)) {
      months--;
      monthCursor = _addMonthsClamped(cursor, months);
    }

    final remainingDays = reference.difference(monthCursor).inDays;
    return AnimalAgeBreakdown(
      years: years,
      months: months,
      weeks: remainingDays ~/ 7,
      days: remainingDays % 7,
      totalDays: reference.difference(birth).inDays,
    );
  }

  static DateTime estimateDateOfBirth({
    required int value,
    required AnimalAgeUnit unit,
    required DateTime referenceDate,
  }) {
    if (value < 0 || (value == 0 && unit != AnimalAgeUnit.days)) {
      throw ArgumentError.value(value, 'value', 'Age is not valid.');
    }
    final reference = dateOnly(referenceDate);
    return switch (unit) {
      AnimalAgeUnit.days => reference.subtract(Duration(days: value)),
      AnimalAgeUnit.weeks => reference.subtract(Duration(days: value * 7)),
      AnimalAgeUnit.months => _addMonthsClamped(reference, -value),
      AnimalAgeUnit.years => _addYearsClamped(reference, -value),
    };
  }

  static String formatDetailedAge(DateTime birthDate, DateTime referenceDate) {
    final age = calculateAgeBreakdown(birthDate, referenceDate);
    if (age.totalDays < 7) return _part(age.totalDays, 'day');
    // Young patients are clinically clearer in weeks through 16 weeks.
    if (age.totalDays < 112) {
      final weeks = age.totalDays ~/ 7;
      final days = age.totalDays % 7;
      return _join([_part(weeks, 'week'), if (days > 0) _part(days, 'day')]);
    }
    if (age.years == 0) {
      return _join([
        _part(age.months, 'month'),
        if (age.weeks > 0) _part(age.weeks, 'week'),
        if (age.months == 0 && age.weeks == 0) _part(age.days, 'day'),
      ]);
    }
    return _join([
      _part(age.years, 'year'),
      if (age.months > 0) _part(age.months, 'month'),
    ]);
  }

  static String formatCompactAge(DateTime birthDate, DateTime referenceDate) {
    final age = calculateAgeBreakdown(birthDate, referenceDate);
    if (age.totalDays < 7) return '${age.totalDays} d';
    if (age.totalDays < 112) return '${age.totalDays ~/ 7} wk';
    if (age.years == 0) return '${age.months} mo';
    return age.months == 0
        ? '${age.years} yr'
        : '${age.years} yr ${age.months} mo';
  }

  static String formatMedicalProfileAge(
    DateTime birthDate,
    DateTime referenceDate,
  ) {
    final age = calculateAgeBreakdown(birthDate, referenceDate);
    if (age.totalDays < 7) return _part(age.totalDays, 'day');
    if (age.totalDays < 56) {
      final weeks = age.totalDays ~/ 7;
      final days = age.totalDays % 7;
      return _join([_part(weeks, 'week'), if (days > 0) _part(days, 'day')]);
    }
    if (age.years == 0) {
      return _join([
        _part(age.months, 'month'),
        if (age.weeks > 0) _part(age.weeks, 'week'),
        if (age.days > 0) _part(age.days, 'day'),
      ]);
    }
    return _join([
      _part(age.years, 'year'),
      if (age.months > 0) _part(age.months, 'month'),
    ]);
  }

  static String displayAge({
    required DateTime birthDate,
    required DateTime referenceDate,
    required bool estimated,
    bool compact = false,
  }) {
    final age = compact
        ? formatCompactAge(birthDate, referenceDate)
        : formatDetailedAge(birthDate, referenceDate);
    return estimated ? '$age (estimated)' : age;
  }

  static DateTime _addYearsClamped(DateTime value, int years) {
    final year = value.year + years;
    final day = value.day.clamp(1, _daysInMonth(year, value.month));
    return DateTime(year, value.month, day);
  }

  static DateTime _addMonthsClamped(DateTime value, int months) {
    final zeroBased = value.year * 12 + value.month - 1 + months;
    final year = zeroBased ~/ 12;
    final month = zeroBased % 12 + 1;
    final day = value.day.clamp(1, _daysInMonth(year, month));
    return DateTime(year, month, day);
  }

  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  static String _part(int value, String unit) =>
      '$value $unit${value == 1 ? '' : 's'}';

  static String _join(List<String> parts) => parts.join(', ');
}
