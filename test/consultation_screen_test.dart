import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/consultation/screens/consultation_screen.dart';

void main() {
  testWidgets(
    'saved Parvoviral consultation for patient ID 21 opens read-only without a dropdown',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      expect(session, isNot(equals(null)));

      final owner = (await database.select(database.owners).get()).first;
      var patient = await (database.select(
        database.animals,
      )..where((animal) => animal.id.equals(21))).getSingleOrNull();
      if (patient == null) {
        await database
            .into(database.animals)
            .insert(
              AnimalsCompanion(
                id: const Value(21),
                clinicId: const Value(defaultClinicId),
                hospitalNumber: const Value('TEST-021'),
                animalName: const Value('Regression patient'),
                species: const Value('Dog'),
                ownerId: Value(owner.id),
                dateRegistered: Value(DateTime.now()),
              ),
            );
        patient = await (database.select(
          database.animals,
        )..where((animal) => animal.id.equals(21))).getSingle();
      }
      final patient21 = patient;
      expect(patient21.id, 21);
      final consultationId = await database
          .into(database.visits)
          .insert(
            VisitsCompanion.insert(
              clinicId: const Value(defaultClinicId),
              animalId: patient21.id,
              visitDate: DateTime.now(),
              diagnosis: const Value('Tentatively Parvoviral Enteritis'),
              veterinarian: const Value('Dr. Amina Okafor'),
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            userSessionProvider.overrideWith((ref) async => session!),
            seedDataProvider.overrideWith((ref) => Future<void>.value()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: ConsultationScreen(
              mode: ConsultationScreenMode.view,
              consultationId: consultationId,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(find.text('Tentatively Parvoviral Enteritis'), findsOneWidget);
      expect(find.textContaining('Regression patient'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      // Detach Riverpod/database listeners before the in-memory database
      // tear-down. Leaving the consultation route mounted keeps its streams
      // alive and causes flutter_test to wait indefinitely.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await database.close();
    },
  );
}
