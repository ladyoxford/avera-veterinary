import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/models/alert_destination.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/models/vaccine_catalogue.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/vaccination/screens/vaccination_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  final now = DateTime(2026, 7, 23, 11);

  test('only pending reminders can remain actionable', () {
    expect(
      isVaccinationActionRequired('Pending', DateTime(2026, 7, 23, 18), now),
      isTrue,
    );
    expect(
      isVaccinationActionRequired('Pending', DateTime(2026, 7, 24), now),
      isFalse,
    );
    expect(
      isVaccinationActionRequired('Cancelled', DateTime(2026, 7, 20), now),
      isFalse,
    );
    expect(isVaccinationActionRequired('Deferred', null, now), isFalse);
    expect(
      isVaccinationActionRequired('Completed', DateTime(2026, 7, 20), now),
      isFalse,
    );
  });

  test('completed reminders never render as overdue', () {
    expect(
      vaccinationReminderDisplayStatus(
        reminderStatus: 'Completed',
        dueDate: DateTime(2026, 7, 20),
        now: now,
      ),
      'Completed',
    );
    expect(
      vaccinationReminderDisplayStatus(
        reminderStatus: 'Pending',
        dueDate: DateTime(2026, 7, 20),
        now: now,
      ),
      'Overdue',
    );
  });

  testWidgets(
    'manual completion closes a reminder without fabricating a vaccine dose',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final animal =
          await (database.select(database.animals)
                ..where((row) => row.clinicId.equals(session.clinic.clinicId))
                ..limit(1))
              .getSingle();
      final reminderId = await database
          .into(database.vaccinations)
          .insert(
            VaccinationsCompanion.insert(
              clinicId: Value(session.clinic.clinicId),
              animalId: animal.id,
              vaccine: 'Lifecycle Test Vaccine',
              dateGiven: DateTime.now().subtract(const Duration(days: 30)),
              nextDueDate: Value(
                DateTime.now().subtract(const Duration(days: 1)),
              ),
              reminderStatus: const Value('Pending'),
              status: const Value('Completed'),
            ),
          );
      final notificationId = await database
          .into(database.notifications)
          .insert(
            NotificationsCompanion.insert(
              clinicId: Value(session.clinic.clinicId),
              type: 'Vaccination Due',
              title: 'Lifecycle Test Vaccine due',
              message: 'This reminder should close with its vaccination.',
              animalId: Value(animal.id),
              dueDate: Value(DateTime.now().subtract(const Duration(days: 1))),
              destinationType: const Value('vaccinationRecord'),
              destinationEntityId: Value(reminderId),
              createdAt: DateTime.now(),
            ),
          );
      final countBefore =
          (await database.select(database.vaccinations).get()).length;
      final dueBefore = (await repository.dashboardStats()).vaccinationsDue;
      final unreadBefore =
          (await repository.dashboardStats()).unreadNotifications;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            clinicRepositoryProvider.overrideWithValue(repository),
            userSessionProvider.overrideWith((ref) async => session),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const VaccineScheduleScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Lifecycle Test Vaccine',
      );
      await tester.pump();
      await tester.longPress(find.text('Lifecycle Test Vaccine').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Completed'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Reschedule'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Cancel Reminder'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Close'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.widgetWithText(ListTile, 'Completed'),
                matching: find.text('Completed'),
              ),
            )
            .style
            ?.color,
        AppTheme.success,
      );

      await tester.tap(find.widgetWithText(ListTile, 'Completed'));
      await tester.pumpAndSettle();

      final stored = await (database.select(
        database.vaccinations,
      )..where((row) => row.id.equals(reminderId))).getSingle();
      expect(stored.reminderStatus, 'Completed');
      expect(
        (await database.select(database.vaccinations).get()).length,
        countBefore,
      );
      expect(
        (await repository.dashboardStats()).vaccinationsDue,
        dueBefore - 1,
      );
      final notification = await (database.select(
        database.notifications,
      )..where((row) => row.id.equals(notificationId))).getSingle();
      expect(
        notification.status,
        InAppNotificationStatus.dismissed.storageValue,
      );
      expect(notification.isRead, isTrue);
      expect(notification.dismissedAt, isNotNull);
      expect(
        (await repository.dashboardStats()).unreadNotifications,
        unreadBefore - 1,
      );
      expect(find.text('Vaccination reminder updated.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
