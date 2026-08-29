import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/remote/cloud_clinical_state.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/services/clinic_operating_status_service.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/screens/dashboard_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const clinicalLabels = [
    'Registered Pets',
    'Consultation',
    'Vaccine Schedule',
    'Laboratory',
    'Hospitalization',
  ];
  const businessLabels = [
    'Staff & Roles',
    'Reports',
    'Billing',
    'Inventory',
    'Revenue',
  ];
  const allLabels = [...clinicalLabels, ...businessLabels];

  late AppDatabase database;
  late ClinicRepository repository;
  late UserSession session;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ClinicRepository(database);
    await repository.seedSampleData();
    final seeded = await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );
    expect(seeded, isNotNull);
    session = UserSession(
      user: seeded!.user,
      clinic: seeded.clinic.copyWith(subscriptionPlan: 'Enterprise'),
      backendPermissions: allPermissions,
    );
  });

  tearDown(() => database.close());

  testWidgets('admin quick access keeps the requested three-column order', (
    tester,
  ) async {
    await _pumpDashboard(tester, database, repository, session);

    expect(find.text('CLINICAL'), findsOneWidget);
    expect(find.text('BUSINESS & ADMIN'), findsOneWidget);
    for (final label in allLabels) {
      expect(find.text(label), findsOneWidget);
    }

    final clinicalGrid = tester.widget<GridView>(
      find.descendant(
        of: find.byKey(const Key('dashboard-quick-access-clinical-grid')),
        matching: find.byType(GridView),
      ),
    );
    final businessGrid = tester.widget<GridView>(
      find.descendant(
        of: find.byKey(const Key('dashboard-quick-access-business-grid')),
        matching: find.byType(GridView),
      ),
    );
    for (final grid in [clinicalGrid, businessGrid]) {
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
      expect(delegate.mainAxisExtent, 112);
    }

    _expectThreeColumnOrder(tester, clinicalLabels);
    _expectThreeColumnOrder(tester, businessLabels);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'quick-action tiles have equal geometry and consistently wrapped labels',
    (tester) async {
      await _pumpDashboard(tester, database, repository, session);

      final tileSizes = <Size>[];
      final iconSizes = <Size>[];
      TextStyle? labelStyle;
      for (final label in allLabels) {
        tileSizes.add(
          tester.getSize(find.byKey(ValueKey('dashboard-quick-action-$label'))),
        );
        iconSizes.add(
          tester.getSize(
            find.byKey(ValueKey('dashboard-quick-action-icon-$label')),
          ),
        );
        final text = tester.widget<Text>(
          find.byKey(ValueKey('dashboard-quick-action-label-$label')),
        );
        expect(text.data, label);
        expect(text.data, isNot(contains('-')));
        expect(text.data, isNot(contains('\n')));
        expect(text.textAlign, TextAlign.center);
        expect(text.maxLines, 2);
        expect(text.softWrap, isTrue);
        expect(text.overflow, TextOverflow.clip);
        labelStyle ??= text.style;
        expect(text.style, labelStyle);
      }

      for (final size in tileSizes.skip(1)) {
        expect(size, tileSizes.first);
      }
      for (final size in iconSizes) {
        expect(size, const Size(42, 42));
      }
      expect(find.text('Hospitalization'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  AppDatabase database,
  ClinicRepository repository,
  UserSession session,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        clinicRepositoryProvider.overrideWithValue(repository),
        userSessionProvider.overrideWith((ref) async => session),
        dashboardStatsProvider.overrideWith((ref) async => _dashboardStats),
        notificationsProvider.overrideWith((ref) => Stream.value(const [])),
        clinicOperatingStatusProvider.overrideWith(
          (ref) async => _operatingStatus,
        ),
        remoteDashboardProvider.overrideWith(
          (ref) async => _remoteDashboardSummary,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const DashboardScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void _expectThreeColumnOrder(WidgetTester tester, List<String> labels) {
  Offset position(String label) =>
      tester.getTopLeft(find.byKey(ValueKey('dashboard-quick-action-$label')));

  final first = position(labels[0]);
  final second = position(labels[1]);
  final third = position(labels[2]);
  final fourth = position(labels[3]);
  final fifth = position(labels[4]);

  expect(second.dx, greaterThan(first.dx));
  expect(third.dx, greaterThan(second.dx));
  expect(second.dy, closeTo(first.dy, .1));
  expect(third.dy, closeTo(first.dy, .1));
  expect(fourth.dy, greaterThan(first.dy));
  expect(fifth.dy, closeTo(fourth.dy, .1));
  expect(fourth.dx, closeTo(first.dx, .1));
  expect(fifth.dx, closeTo(second.dx, .1));
}

const _dashboardStats = DashboardStats(
  totalAnimals: 0,
  todaysConsultations: 0,
  appointmentsToday: 0,
  vaccinationsDue: 0,
  lowStock: 0,
  expiredDrugs: 0,
  monthlyRevenue: 0,
  recentVisits: [],
  recentActivity: [],
  unreadNotifications: 0,
);

const _operatingStatus = ClinicOperatingStatus(
  kind: ClinicOperatingStatusKind.open,
  label: 'OPEN NOW',
  weeklySummary: 'Mon-Sat 08:00-18:00',
);

const _remoteDashboardSummary = RemoteDashboardSummary(
  registeredPatients: 0,
  todaysSchedule: 0,
  activeConsultations: 0,
  vaccinationsDue: 0,
  lowStock: 0,
  expiredProducts: 0,
  activeHospitalizations: 0,
  pendingLaboratoryReports: 0,
  outstandingInvoices: 0,
  currentRevenue: 0,
  recentActivity: [],
);
