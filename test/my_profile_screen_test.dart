import 'dart:convert';
import 'dart:io';

import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/screens/my_profile_screen.dart';
import 'package:avera/features/shared/widgets/branded_app_bar.dart';
import 'package:avera/features/shared/widgets/identity_avatar.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('shared initials preserve established first-two-name behavior', () {
    expect(averaInitials('Chukwu Kenechukwu Chukwu'), 'CK');
    expect(averaInitials('Ada'), 'A');
  });

  test('account sheet uses the one universal profile route', () {
    expect(accountProfileRoute, '/profile');
  });

  test(
    'self profile update preserves role, role id, and staff number',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final previous = session.user;

      await repository.updateOwnProfile(
        session: session,
        fullName: 'Updated Profile Name',
        phoneNumber: '+234 801 234 5678',
        veterinaryLicenseNumber: null,
      );
      final updated = await (database.select(
        database.appUsers,
      )..where((row) => row.userId.equals(previous.userId))).getSingle();

      expect(updated.fullName, 'Updated Profile Name');
      expect(updated.phoneNumber, '+234 801 234 5678');
      expect(updated.role, previous.role);
      expect(updated.roleId, previous.roleId);
      expect(updated.staffNumber, previous.staffNumber);
    },
  );

  testWidgets('My Profile is available to non-administrator clinic staff', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final administrator = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    final pharmacist = UserSession(
      user: administrator.user.copyWith(
        role: 'Pharmacist',
        accountType: 'ClinicStaff',
        professionalTitle: const Value('Veterinary Pharmacist'),
      ),
      clinic: administrator.clinic,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          clinicRepositoryProvider.overrideWithValue(repository),
          userSessionProvider.overrideWith((ref) async => pharmacist),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MyProfileScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Pharmacist'), findsWidgets);
    expect(find.text('Veterinary Pharmacist'), findsOneWidget);
    expect(find.text('LICENSE / REGISTRATION NO.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('profile avatar opens camera and gallery actions', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          clinicRepositoryProvider.overrideWithValue(repository),
          userSessionProvider.overrideWith((ref) async => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MyProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-avatar')));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Upload photo'), findsOneWidget);
    expect(find.text('View photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('removing a local profile photo persists', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final original = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'avera-profile-photo-test',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final photo = File('${temporaryDirectory.path}/profile.png');
    await photo.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await (database.update(database.appUsers)
          ..where((row) => row.userId.equals(original.user.userId)))
        .write(AppUsersCompanion(profilePhoto: Value(photo.path)));

    final sessionWithPhoto = (await repository.restoreUserSession(
      userId: original.user.userId,
      clinicId: original.clinic.clinicId,
    ))!;
    await repository.removeOwnProfilePhoto(sessionWithPhoto);

    final stored = await (database.select(
      database.appUsers,
    )..where((row) => row.userId.equals(original.user.userId))).getSingle();
    final restored = await repository.restoreUserSession(
      userId: original.user.userId,
      clinicId: original.clinic.clinicId,
    );
    expect(stored.profilePhoto, isNull);
    expect(restored?.user.profilePhoto, isNull);
  });

  testWidgets('removing a profile photo requires confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final original = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    final sessionWithPhoto = UserSession(
      user: original.user.copyWith(
        profilePhoto: const Value('profile-photo.jpg'),
      ),
      clinic: original.clinic,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          clinicRepositoryProvider.overrideWithValue(repository),
          userSessionProvider.overrideWith((ref) async => sessionWithPhoto),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MyProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();

    expect(find.text('Remove profile photo?'), findsOneWidget);
    expect(find.text('Keep Photo'), findsOneWidget);
    expect(find.text('Remove Photo'), findsOneWidget);
    await tester.tap(find.text('Keep Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Remove profile photo?'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'direct profile back falls back to Dashboard instead of exiting',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const Scaffold(body: Text('Dashboard')),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const MyProfileScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            clinicRepositoryProvider.overrideWithValue(repository),
            userSessionProvider.overrideWith((ref) async => session),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My Profile'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/dashboard');
      expect(find.text('Dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
