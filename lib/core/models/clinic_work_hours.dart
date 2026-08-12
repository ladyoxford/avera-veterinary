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

  factory ClinicWorkDayConfig.fromJson(Map<String, dynamic> json) =>
      ClinicWorkDayConfig(
        weekday: json['weekday'] as String,
        isOpen: json['isOpen'] as bool? ?? false,
        openingTime: json['openingTime'] as String?,
        closingTime: json['closingTime'] as String?,
        breakStart: json['breakStart'] as String?,
        breakEnd: json['breakEnd'] as String?,
      );
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

  factory ClinicWorkHoursConfig.fromJson(Map<String, dynamic> json) =>
      ClinicWorkHoursConfig(
        clinicId: json['clinicId'] as String,
        timeZone: json['timeZone'] as String? ?? 'Africa/Lagos',
        isEnabled: json['isEnabled'] as bool? ?? true,
        days: (json['days'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClinicWorkDayConfig.fromJson)
            .toList(growable: false),
      );
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
