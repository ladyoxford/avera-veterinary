import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/services/hospital_numbering.dart';

void main() {
  test('formats and validates clinic hospital numbers without truncation', () {
    expect(
      formatHospitalNumber(
        prefix: 'avr',
        year: 2026,
        sequence: 1,
        sequenceLength: 5,
      ),
      'AVR-2026-00001',
    );
    expect(
      formatHospitalNumber(
        prefix: 'AVR',
        year: 2026,
        sequence: 123456,
        sequenceLength: 5,
      ),
      'AVR-2026-123456',
    );
    expect(validateHospitalNumberPrefix('AVR-'), isNotNull);
    expect(validateHospitalNumberPrefix(' AVERA CLINIC '), isNotNull);
    expect(normalizeHospitalNumberPrefix('pet247'), 'PET247');
  });

  test('local allocation preserves legacy numbers and is idempotent', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );
    expect(session, isNotNull);

    final legacy =
        await (database.select(database.animals)
              ..where((row) => row.hospitalNumber.like('ZEV-%'))
              ..limit(1))
            .getSingle();
    final preview = await repository.previewHospitalNumber();
    expect(preview.prefix, 'AVR');
    expect(preview.sequence, 1);

    final first = await _register(
      repository,
      session: session!,
      submissionId: 'submission-one',
      animalName: 'Clover',
    );
    expect(first.hospitalNumber, 'AVR-${DateTime.now().year}-00001');
    final retry = await _register(
      repository,
      session: session,
      submissionId: 'submission-one',
      animalName: 'Clover duplicate retry',
    );
    expect(retry.patientId, first.patientId);
    expect(retry.hospitalNumber, first.hospitalNumber);
    expect(
      (await (database.select(
        database.animals,
      )..where((row) => row.id.equals(legacy.id))).getSingle()).hospitalNumber,
      legacy.hospitalNumber,
    );
    expect(
      (await database.select(database.animals).get()).where(
        (row) => row.registrationSubmissionId == 'submission-one',
      ),
      hasLength(1),
    );

    final second = await _register(
      repository,
      session: session,
      submissionId: 'submission-two',
      animalName: 'Maple',
    );
    expect(second.hospitalNumber, 'AVR-${DateTime.now().year}-00002');

    final concurrent = await Future.wait([
      _register(
        repository,
        session: session,
        submissionId: 'submission-three',
        animalName: 'River',
      ),
      _register(
        repository,
        session: session,
        submissionId: 'submission-four',
        animalName: 'Willow',
      ),
    ]);
    expect(concurrent.map((item) => item.hospitalNumber).toSet(), {
      'AVR-${DateTime.now().year}-00003',
      'AVR-${DateTime.now().year}-00004',
    });
  });

  test('hospital number uniqueness is scoped to the clinic', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    const otherClinicId = 'crest-clinic';
    final now = DateTime.now();
    await database
        .into(database.clinics)
        .insert(
          ClinicsCompanion.insert(
            clinicId: otherClinicId,
            clinicName: 'Crest Animal Hospital',
            dateRegistered: now,
            patientNumberPrefix: const Value('CREST'),
          ),
        );
    final otherOwner = await database
        .into(database.owners)
        .insert(
          OwnersCompanion.insert(
            clinicId: const Value(otherClinicId),
            fullName: 'Crest Owner',
            phone: '08000000111',
          ),
        );
    await database
        .into(database.animals)
        .insert(
          AnimalsCompanion.insert(
            clinicId: const Value(otherClinicId),
            hospitalNumber: 'ZEV-2026-00001',
            animalName: 'Independent Patient',
            species: 'Dog',
            ownerId: otherOwner,
            dateRegistered: now,
          ),
        );
    expect(
      (await (database.select(
            database.animals,
          )..where((row) => row.hospitalNumber.equals('ZEV-2026-00001'))).get())
          .length,
      greaterThanOrEqualTo(2),
    );
  });

  test(
    'only numbering managers can change future numbering settings',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      await repository.updatePatientNumberingSettings(
        session: session!,
        prefix: 'CREST',
        sequenceLength: 6,
        resetYearly: false,
      );
      expect((await repository.previewHospitalNumber()).prefix, 'CREST');
      expect(
        repository.updatePatientNumberingSettings(
          session: UserSession(
            user: session.user.copyWith(role: 'Veterinarian'),
            clinic: session.clinic,
          ),
          prefix: 'NO',
          sequenceLength: 5,
          resetYearly: true,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'current migration resumes after a partial version 11 upgrade',
    () async {
      final database = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute(
              'CREATE TABLE clinics ('
              'clinic_id TEXT NOT NULL PRIMARY KEY, '
              'patient_number_prefix TEXT, '
              'patient_number_sequence_length INTEGER NOT NULL DEFAULT 5, '
              'patient_number_reset_yearly INTEGER NOT NULL DEFAULT 1, '
              'patient_number_prefix_reviewed INTEGER NOT NULL DEFAULT 0, '
              'patient_number_last_changed_at INTEGER, '
              'patient_number_last_changed_by TEXT)',
            );
            sqlite.execute(
              'CREATE TABLE animals ('
              'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
              'clinic_id TEXT NOT NULL, '
              'hospital_number TEXT NOT NULL)',
            );
            sqlite.execute(
              "INSERT INTO clinics (clinic_id) VALUES ('demo-clinic')",
            );
            sqlite.execute(
              "INSERT INTO animals (clinic_id, hospital_number) "
              "VALUES ('demo-clinic', 'ZEV-2026-00001')",
            );
            sqlite.execute(
              'CREATE TABLE clinic_number_sequences ('
              'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
              'clinic_id TEXT NOT NULL, '
              'sequence_type TEXT NOT NULL, '
              'sequence_key TEXT NOT NULL, '
              'current_value INTEGER NOT NULL DEFAULT 0, '
              'sequence_length INTEGER NOT NULL DEFAULT 5, '
              'created_at INTEGER NOT NULL, '
              'updated_at INTEGER NOT NULL)',
            );
            sqlite.execute('PRAGMA user_version = 11');
          },
        ),
      );
      addTearDown(database.close);

      final columns = await database
          .customSelect('PRAGMA table_info(animals)')
          .get();
      final columnNames = columns
          .map((row) => row.read<String>('name'))
          .toSet();
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final legacyNumber = await database
          .customSelect('SELECT hospital_number FROM animals WHERE id = 1')
          .getSingle();

      expect(version.read<int>('user_version'), database.schemaVersion);
      expect(columnNames, contains('number_assignment_status'));
      expect(columnNames, contains('temporary_hospital_number'));
      expect(columnNames, contains('registration_year'));
      expect(columnNames, contains('registration_submission_id'));
      expect(legacyNumber.read<String>('hospital_number'), 'ZEV-2026-00001');
    },
  );
}

Future<AssignedHospitalNumber> _register(
  ClinicRepository repository, {
  required UserSession session,
  required String submissionId,
  required String animalName,
}) {
  return repository.registerAnimalWithHospitalNumber(
    session: session,
    submissionId: submissionId,
    owner: OwnersCompanion.insert(
      fullName: 'Owner $submissionId',
      phone: '0800$submissionId',
    ),
    animal: AnimalsCompanion(
      animalName: Value(animalName),
      species: const Value('Dog'),
      weight: const Value(12),
      dateOfBirth: Value(DateTime(2025, 1, 1)),
    ),
  );
}
