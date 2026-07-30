import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/services/hospital_load_test_seeder.dart';

void main() {
  test('seeds an isolated, idempotent 500-patient hospital', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final seeder = HospitalLoadTestSeeder(database);

    final created = await seeder.seedLargeHospital();
    expect(created.alreadyExisted, isFalse);
    expect(created.patients, 500);
    expect(created.consultations, 1800);
    expect(created.vaccinations, 1050);
    expect(created.appointments, 600);
    expect(created.inventoryItems, 250);
    expect(created.invoices, 750);

    final patients =
        await (database.select(database.animals)..where(
              (row) => row.clinicId.equals(HospitalLoadTestSeeder.clinicId),
            ))
            .get();
    expect(patients, hasLength(500));
    expect(patients.map((row) => row.hospitalNumber).toSet(), hasLength(500));
    expect(patients.first.hospitalNumber, startsWith('AMV-2026-'));

    final sequence =
        await (database.select(database.clinicNumberSequences)
              ..where(
                (row) => row.clinicId.equals(HospitalLoadTestSeeder.clinicId),
              )
              ..where((row) => row.sequenceType.equals('patient'))
              ..where((row) => row.sequenceKey.equals('2026')))
            .getSingle();
    expect(sequence.currentValue, 500);

    final repository = ClinicRepository(database);
    final session = await repository.authenticateUser(
      username: HospitalLoadTestSeeder.administratorEmail,
      password: HospitalLoadTestSeeder.administratorPassword,
    );
    expect(session?.clinic.clinicId, HospitalLoadTestSeeder.clinicId);
    expect(
      (await repository.previewHospitalNumber()).hospitalNumber,
      'AMV-2026-00501',
    );

    final repeated = await seeder.seedLargeHospital();
    expect(repeated.alreadyExisted, isTrue);
    expect(repeated.patients, 500);
    expect(
      await (database.select(database.animals)..where(
            (row) => row.clinicId.equals(HospitalLoadTestSeeder.clinicId),
          ))
          .get()
          .then((rows) => rows.length),
      500,
    );

    expect(
      await (database.select(database.animals)
            ..where((row) => row.clinicId.equals(defaultClinicId)))
          .get()
          .then((rows) => rows.length),
      0,
    );

    await seeder.resetLargeHospital();
    expect(await seeder.isLargeHospitalSeeded(), isFalse);
    expect(
      await (database.select(database.animals)..where(
            (row) => row.clinicId.equals(HospitalLoadTestSeeder.clinicId),
          ))
          .get()
          .then((rows) => rows.length),
      0,
    );
  });
}
