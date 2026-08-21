import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/models/clinic_work_hours.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/core/theme/theme_controller.dart';
import 'package:avera/features/administration/screens/clinic_work_hours_screen.dart';
import 'package:avera/features/shared/screens/settings_screen.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';
import 'package:avera/features/shared/widgets/branded_app_bar.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase database;
  late ClinicRepository repository;
  late UserSession session;
  late SharedPreferences preferences;
  late List<Override> providerOverrides;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ClinicRepository(database);
    await repository.seedSampleData();
    session = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    session = UserSession(
      user: session.user.copyWith(profilePhoto: const Value(null)),
      clinic: session.clinic,
      backendPermissions: session.backendPermissions,
      rolePolicyPermissions: session.rolePolicyPermissions,
    );
    providerOverrides = [
      databaseProvider.overrideWithValue(database),
      clinicRepositoryProvider.overrideWithValue(repository),
      userSessionProvider.overrideWith((ref) async => session),
      clinicSettingsProvider.overrideWith((ref) async => session.clinic),
      sharedPreferencesProvider.overrideWithValue(preferences),
      notificationsProvider.overrideWith((ref) => Stream.value(const [])),
    ];
  });

  tearDown(() => database.close());

  test('clinic location omits missing punctuation and formats real fields', () {
    expect(formatClinicLocation(session.clinic), isNot(contains('-, -')));
    expect(
      formatClinicLocation(
        session.clinic.copyWith(
          address: const Value(null),
          city: const Value('Lagos'),
          state: const Value(null),
          country: const Value('Nigeria'),
        ),
      ),
      'Lagos, Nigeria',
    );
  });

  testWidgets(
    'settings uses cohesive functional rows in light and dark themes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: providerOverrides,
            child: MaterialApp(theme: theme, home: const SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('Device'), findsOneWidget);
        expect(find.text('Light'), findsOneWidget);
        expect(find.text('Dark'), findsOneWidget);
        expect(find.text('Clinic Logo'), findsOneWidget);
        expect(find.text('Clinic Banner'), findsOneWidget);
        expect(find.text('Theme Color'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Logo'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Banner'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'clinic information uses external AVERA labels on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: providerOverrides,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ClinicInformationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AveraLabeledTextField), findsWidgets);
      expect(find.text('CLINIC NAME'), findsOneWidget);
      expect(find.text('CLINIC EMAIL'), findsOneWidget);
      for (final decorator in tester.widgetList<InputDecorator>(
        find.descendant(
          of: find.byType(ClinicInformationScreen),
          matching: find.byType(InputDecorator),
        ),
      )) {
        expect(decorator.decoration.labelText, isNull);
      }
      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(find.text('TIME ZONE'), findsWidgets);
      for (final decorator in tester.widgetList<InputDecorator>(
        find.descendant(
          of: find.byType(ClinicInformationScreen),
          matching: find.byType(InputDecorator),
        ),
      )) {
        expect(decorator.decoration.labelText, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('work hours uses AVERA cards without narrow-screen overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workHours = ClinicWorkHoursConfig(
      clinicId: session.clinic.clinicId,
      timeZone: 'Africa/Lagos',
      isEnabled: true,
      days: [
        for (final weekday in clinicWeekdays)
          ClinicWorkDayConfig(
            weekday: weekday,
            isOpen: weekday != 'sunday',
            openingTime: weekday == 'sunday' ? null : '08:00',
            closingTime: weekday == 'sunday' ? null : '18:00',
          ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...providerOverrides,
          clinicWorkHoursProvider.overrideWith((ref) async => workHours),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const ClinicWorkHoursScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AveraLabeledSwitchField), findsOneWidget);
    expect(find.byType(AveraLabeledDropdownField<String>), findsOneWidget);
    expect(find.text('AVAILABILITY'), findsOneWidget);
    expect(find.text('TIME ZONE'), findsOneWidget);
    final timeZoneDecorator = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byType(AveraLabeledDropdownField<String>),
        matching: find.byType(InputDecorator),
      ),
    );
    expect(timeZoneDecorator.decoration.labelText, isNull);
    await tester.scrollUntilVisible(find.text('Mon'), 250);
    expect(find.text('OPENS'), findsOneWidget);
    expect(find.text('CLOSES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar sheet contains account actions and no Theme action', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(appBar: BrandedAppBar()),
        ),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const Scaffold()),
        GoRoute(path: '/notifications', builder: (_, __) => const Scaffold()),
        GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: providerOverrides,
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('account-menu-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Account Settings'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Theme'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branded app bar reads the active clinic banner', (tester) async {
    final bannerSession = UserSession(
      user: session.user,
      clinic: session.clinic.copyWith(
        banner: const Value('missing-local-banner.jpg'),
      ),
      backendPermissions: session.backendPermissions,
      rolePolicyPermissions: session.rolePolicyPermissions,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...providerOverrides,
          userSessionProvider.overrideWith((ref) async => bannerSession),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(appBar: BrandedAppBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('clinic-dashboard-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
