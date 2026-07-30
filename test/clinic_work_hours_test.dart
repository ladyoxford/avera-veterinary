import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/models/clinic_work_hours.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/services/clinic_operating_status_service.dart';
import 'package:avera/core/services/dashboard_mode_resolver.dart';

void main() {
  const defaultDays = [
    ClinicWorkDayConfig(
      weekday: 'monday',
      isOpen: true,
      openingTime: '08:00',
      closingTime: '18:00',
    ),
    ClinicWorkDayConfig(
      weekday: 'tuesday',
      isOpen: true,
      openingTime: '08:00',
      closingTime: '18:00',
    ),
    ClinicWorkDayConfig(
      weekday: 'wednesday',
      isOpen: true,
      openingTime: '08:00',
      closingTime: '18:00',
    ),
    ClinicWorkDayConfig(
      weekday: 'thursday',
      isOpen: true,
      openingTime: '08:00',
      closingTime: '18:00',
    ),
    ClinicWorkDayConfig(
      weekday: 'friday',
      isOpen: true,
      openingTime: '08:00',
      closingTime: '18:00',
    ),
    ClinicWorkDayConfig(
      weekday: 'saturday',
      isOpen: true,
      openingTime: '09:00',
      closingTime: '14:00',
    ),
    ClinicWorkDayConfig(weekday: 'sunday', isOpen: false),
  ];

  test('clinic work hours are provisioned, persisted, and audited', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );

    final initial = await repository.clinicWorkHours();
    expect(initial, isNot(equals(null)));
    expect(initial!.dayForWeekday('sunday')!.isOpen, isFalse);

    await repository.updateClinicWorkHours(
      session: session!,
      timeZone: 'Africa/Lagos',
      isEnabled: true,
      days: defaultDays,
    );

    final saved = await repository.clinicWorkHours();
    expect(saved!.dayForWeekday('saturday')!.openingTime, '09:00');
    expect(
      (await database.select(database.auditLogs).get()).any(
        (entry) => entry.action == 'clinic.work_hours_updated',
      ),
      isTrue,
    );
  });

  test('new clinic applications receive isolated default work hours', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();

    await repository.submitClinicApplication(
      const ClinicApplication(
        clinicName: 'Independent Avera Clinic',
        clinicEmail: 'care@independent.test',
        phoneNumber: '08000000000',
        address: '1 Example Street',
        city: 'Lagos',
        country: 'Nigeria',
        administratorName: 'Independent Admin',
        administratorEmail: 'independent.admin@avera.test',
        administratorPhone: '08000000001',
        professionalTitle: 'Veterinarian',
        subscriptionPlan: 'Starter',
      ),
    );

    final clinic =
        await (database.select(database.clinics)..where(
              (row) => row.clinicName.equals('Independent Avera Clinic'),
            ))
            .getSingle();
    final hours = await repository.clinicWorkHours(clinicId: clinic.clinicId);
    expect(hours, isNot(equals(null)));
    expect(hours!.clinicId, clinic.clinicId);
    expect(hours.dayForWeekday('monday')!.openingTime, '08:00');
  });

  test('operating status honours the clinic timezone and closed Sunday', () {
    final config = ClinicWorkHoursConfig(
      clinicId: 'clinic-a',
      timeZone: 'Africa/Lagos',
      isEnabled: true,
      days: defaultDays,
    );

    final open = ClinicOperatingStatusService.calculate(
      config,
      now: DateTime.utc(2026, 7, 13, 9),
    );
    final closed = ClinicOperatingStatusService.calculate(
      config,
      now: DateTime.utc(2026, 7, 12, 10),
    );

    expect(open.kind, ClinicOperatingStatusKind.open);
    expect(closed.kind, ClinicOperatingStatusKind.closedToday);
  });

  test(
    'dashboard mode resolves from capabilities rather than role labels',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final admin = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );

      final staff = UserSession(
        user: admin!.user.copyWith(
          role: 'Custom Clinician',
          accountType: 'ClinicStaff',
          permissions: '["consultations.view"]',
        ),
        clinic: admin.clinic,
        backendPermissions: const {'consultations.view'},
      );

      expect(
        DashboardModeResolver.resolve(admin),
        DashboardMode.administrative,
      );
      expect(DashboardModeResolver.resolve(staff), DashboardMode.staff);
    },
  );
}
