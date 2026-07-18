class ClinicWorkDayConfig {
  const ClinicWorkDayConfig({
    required this.weekday,
    required this.isOpen,
    this.openingTime,
    this.closingTime,
    this.breakStart,
    this.breakEnd,
  });

  final String weekday;
  final bool isOpen;
  final String? openingTime;
  final String? closingTime;
  final String? breakStart;
  final String? breakEnd;

  ClinicWorkDayConfig copyWith({
    bool? isOpen,
    String? openingTime,
    String? closingTime,
    String? breakStart,
    String? breakEnd,
  }) => ClinicWorkDayConfig(
    weekday: weekday,
    isOpen: isOpen ?? this.isOpen,
    openingTime: openingTime ?? this.openingTime,
    closingTime: closingTime ?? this.closingTime,
    breakStart: breakStart ?? this.breakStart,
    breakEnd: breakEnd ?? this.breakEnd,
  );

  Map<String, Object?> toJson() => {
    'weekday': weekday,
    'isOpen': isOpen,
    'openingTime': openingTime,
    'closingTime': closingTime,
    'breakStart': breakStart,
    'breakEnd': breakEnd,
  };
}

class ClinicWorkHoursConfig {
  const ClinicWorkHoursConfig({
    required this.clinicId,
    required this.timeZone,
    required this.isEnabled,
    required this.days,
  });

  final String clinicId;
  final String timeZone;
  final bool isEnabled;
  final List<ClinicWorkDayConfig> days;

  ClinicWorkDayConfig? dayForWeekday(String weekday) {
    for (final day in days) {
      if (day.weekday == weekday) return day;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'clinicId': clinicId,
    'timeZone': timeZone,
    'isEnabled': isEnabled,
    'days': days.map((day) => day.toJson()).toList(),
  };
}

const clinicWeekdays = <String>[
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

const clinicWeekdayLabels = <String, String>{
  'monday': 'Mon',
  'tuesday': 'Tue',
  'wednesday': 'Wed',
  'thursday': 'Thu',
  'friday': 'Fri',
  'saturday': 'Sat',
  'sunday': 'Sun',
};
