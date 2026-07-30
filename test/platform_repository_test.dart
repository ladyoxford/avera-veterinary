import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/repositories/platform_repository.dart';

void main() {
  test('platform overview uses live platform-scoped database values', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final clinics = ClinicRepository(database);
    await clinics.seedSampleData();
    final owner = await clinics.authenticateUser(
      username: 'owner@avera.test',
      password: 'change-me-locally',
    );
    expect(owner, isNotNull);

    final initial = await LocalPlatformRepository(
      database,
    ).loadOverview(owner!);
    expect(initial.totalClinics, 1);
    expect(initial.activeClinics, 1);
    expect(initial.activeUsers, greaterThan(0));
    expect(initial.monthlyRevenue, isNull);
    expect(initial.systemHealthStatus, isNull);

    await (database.update(database.clinics)
          ..where((clinic) => clinic.clinicId.equals(defaultClinicId)))
        .write(const ClinicsCompanion(clinicStatus: Value('Suspended')));

    final updated = await LocalPlatformRepository(database).loadOverview(owner);
    expect(updated.activeClinics, 0);
    expect(updated.suspendedClinics, 1);
    expect(updated.recentClinics.single.clinicId, defaultClinicId);
  });

  test('clinic users cannot open a platform overview stream', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final clinics = ClinicRepository(database);
    await clinics.seedSampleData();
    final administrator = await clinics.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );
    expect(administrator, isNotNull);

    expect(
      () => LocalPlatformRepository(database).watchOverview(administrator!),
      throwsA(isA<StateError>()),
    );
  });
}
