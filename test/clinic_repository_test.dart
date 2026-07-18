import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zevora/core/database/app_database.dart';
import 'package:zevora/core/repositories/clinic_repository.dart';
import 'package:zevora/core/security/access_control.dart';

void main() {
  test(
    'local login tolerates duplicate legacy Platform Owner seed rows',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);

      await repository.seedSampleData();
      await database
          .into(database.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: 'legacy-platform-owner',
              clinicId: 'platform-control',
              fullName: 'Legacy Platform Owner',
              username: 'legacy.owner',
              email: 'legacy.owner@avera.test',
              passwordHash: 'legacy-development-hash',
              role: 'Platform Owner',
              accountType: const Value(AccountTypes.platformOwner),
              permissions: const Value('[]'),
              createdAt: DateTime.now(),
            ),
          );

      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );

      expect(session, isNot(equals(null)));
      expect(session!.user.email, 'admin@avera.test');
      expect(session.clinic.clinicId, defaultClinicId);
    },
  );

  test(
    'consultations are loaded and updated by their saved record ID',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      final animal = (await database.select(database.animals).get()).first;

      final consultationId = await repository.saveVisit(
        session: session!,
        visit: VisitsCompanion.insert(
          animalId: animal.id,
          visitDate: DateTime.now(),
          chiefComplaint: const Value('Reduced appetite'),
          diagnosis: const Value('Initial assessment'),
        ),
      );

      final saved = await repository.getVisit(consultationId);
      expect(saved?.chiefComplaint, 'Reduced appetite');

      await repository.updateVisit(
        visitId: consultationId,
        session: session,
        visit: const VisitsCompanion(diagnosis: Value('Updated assessment')),
      );

      final updated = await repository.getVisit(consultationId);
      expect(updated?.diagnosis, 'Updated assessment');
      expect(updated?.chiefComplaint, 'Reduced appetite');

      final readOnlySession = UserSession(
        user: session.user,
        clinic: session.clinic,
        backendPermissions: const {Permissions.consultationsView},
      );
      await expectLater(
        repository.updateVisit(
          visitId: consultationId,
          session: readOnlySession,
          visit: const VisitsCompanion(
            diagnosis: Value('This must not be saved'),
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await repository.getVisit(consultationId))?.diagnosis,
        'Updated assessment',
      );
    },
  );
}
