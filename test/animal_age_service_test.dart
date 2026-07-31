import 'package:avera/core/services/animal_age_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registrationDate = DateTime(2026, 7, 30);

  test('six week estimate advances dynamically with the reference date', () {
    final birthDate = AnimalAgeService.estimateDateOfBirth(
      value: 6,
      unit: AnimalAgeUnit.weeks,
      referenceDate: registrationDate,
    );

    expect(birthDate, DateTime(2026, 6, 18));
    expect(
      AnimalAgeService.formatDetailedAge(birthDate, registrationDate),
      '6 weeks',
    );
    expect(
      AnimalAgeService.formatDetailedAge(birthDate, DateTime(2026, 8, 13)),
      '8 weeks',
    );
    expect(
      AnimalAgeService.formatDetailedAge(birthDate, DateTime(2026, 9, 10)),
      '12 weeks',
    );
    expect(
      AnimalAgeService.calculateAgeBreakdown(
        birthDate,
        DateTime(2026, 9, 10),
      ).totalDays,
      84,
    );
    expect(
      AnimalAgeService.formatMedicalProfileAge(
        birthDate,
        DateTime(2026, 9, 10),
      ),
      '2 months, 3 weeks, 2 days',
    );
  });

  test('calendar-aware month and year estimates preserve valid month ends', () {
    expect(
      AnimalAgeService.estimateDateOfBirth(
        value: 8,
        unit: AnimalAgeUnit.months,
        referenceDate: registrationDate,
      ),
      DateTime(2025, 11, 30),
    );
    expect(
      AnimalAgeService.estimateDateOfBirth(
        value: 3,
        unit: AnimalAgeUnit.years,
        referenceDate: registrationDate,
      ),
      DateTime(2023, 7, 30),
    );

    final endOfMonth = AnimalAgeService.calculateAgeBreakdown(
      DateTime(2025, 1, 31),
      DateTime(2025, 2, 28),
    );
    expect(endOfMonth.months, 1);
    expect(endOfMonth.days, 0);
  });

  test('leap-year, year boundary, newborn, and future dates are safe', () {
    final leapAge = AnimalAgeService.calculateAgeBreakdown(
      DateTime(2024, 2, 29),
      DateTime(2025, 2, 28),
    );
    expect(leapAge.years, 1);

    final boundary = AnimalAgeService.calculateAgeBreakdown(
      DateTime(2025, 12, 31),
      DateTime(2026, 1, 1),
    );
    expect(boundary.totalDays, 1);
    expect(
      AnimalAgeService.formatDetailedAge(registrationDate, registrationDate),
      '0 days',
    );
    expect(
      () => AnimalAgeService.calculateAgeBreakdown(
        DateTime(2026, 7, 31),
        registrationDate,
      ),
      throwsArgumentError,
    );
  });

  test('compact, detailed, estimated, singular, and unit parsing work', () {
    expect(
      AnimalAgeService.formatDetailedAge(
        DateTime(2026, 7, 29),
        registrationDate,
      ),
      '1 day',
    );
    expect(
      AnimalAgeService.formatCompactAge(
        DateTime(2023, 3, 30),
        registrationDate,
      ),
      '3 yr 4 mo',
    );
    expect(
      AnimalAgeService.displayAge(
        birthDate: DateTime(2026, 1, 30),
        referenceDate: registrationDate,
        estimated: true,
      ),
      '6 months (estimated)',
    );
    expect(AnimalAgeUnit.fromStorage('Weeks'), AnimalAgeUnit.weeks);
    expect(AnimalAgeUnit.days.labelFor(1), 'Day');
    expect(AnimalAgeUnit.days.labelFor(2), 'Days');
  });
}
