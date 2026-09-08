import 'dart:async';
import 'dart:convert';

import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/farm/screens/farm_records_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  test(
    'remote movement history survives offline reload and caches a just-confirmed purchase',
    () async {
      const tokens = TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'test-token',
        refreshToken: 'test-refresh',
      );
      addTearDown(tokens.clear);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final local = ClinicRepository(db);
      await local.seedSampleData();
      final session = (await local.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final farm = await local.createFarm(
        session: session,
        name: 'History Farm',
        speciesIds: ['species_cattle'],
      );
      final unit = await local.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Cattle Pen',
        unitType: 'Pen',
        speciesId: 'species_cattle',
        maleCount: 24,
        femaleCount: 2,
      );
      final group = (await local.getFarmUnitPopulations(
        farmId: farm.id,
        unitId: unit.id,
      )).single;
      final remoteUnit = const Uuid().v5(
        Namespace.url.value,
        'avera:${farm.id}:farm-unit:${unit.id}',
      );
      final remoteGroup = const Uuid().v5(
        Namespace.url.value,
        'avera:${farm.id}:farm-population:${group.id}',
      );
      var offline = false;
      final api = ApiClient(
        baseUrl: 'https://api.avera.test',
        tokens: const TokenStore(FlutterSecureStorage()),
        client: MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'population': {
                  'male_count': 24,
                  'female_count': 5,
                  'unknown_count': 0,
                },
              }),
              201,
            );
          }
          if (offline) return http.Response('{"error":"unavailable"}', 503);
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'farmId': farm.id,
                  'farmUnitId': remoteUnit,
                  'farmUnitPopulationId': remoteGroup,
                  'submissionId': 'previous-purchase',
                  'movementType': 'purchase',
                  'sex': 'female',
                  'quantity': 2,
                  'occurredAt': '2026-09-01T10:00:00Z',
                  'source': 'Recorded seller',
                },
                {'farmId': 'another-farm', 'farmUnitId': remoteUnit},
              ],
            }),
            200,
          );
        }),
      );
      final remote = ClinicRepository(db, apiClient: api);
      await remote.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      final history = await remote.getFarmUnitPopulationHistory(
        farmId: farm.id,
        unitId: unit.id,
      );
      expect(history, hasLength(1));
      expect(history.single.description, contains('Recorded seller'));
      offline = true;
      await remote.recordFarmPopulationMovement(
        session: session,
        input: FarmPopulationMovementInput(
          farmId: farm.id,
          farmUnitId: unit.id,
          populationId: group.id,
          type: FarmPopulationMovementType.purchase,
          sex: FarmPopulationSex.female,
          quantity: 3,
          occurredAt: DateTime(2026, 9, 8),
        ),
      );
      expect(
        await remote.getFarmUnitPopulationHistory(
          farmId: farm.id,
          unitId: unit.id,
        ),
        hasLength(2),
      );
      final reloaded = ClinicRepository(db);
      await reloaded.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      expect(
        await reloaded.getFarmUnitPopulationHistory(
          farmId: farm.id,
          unitId: unit.id,
        ),
        hasLength(2),
      );
    },
  );
  test(
    'live farm totals follow movements and archive without deleting history',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ClinicRepository(db);
      await repo.seedSampleData();
      final session = (await repo.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final farm = await repo.createFarm(
        session: session,
        name: 'Cattle Farm',
        speciesIds: ['species_cattle'],
      );
      final unit = await repo.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Cattle Pen',
        unitType: 'Pen',
        speciesId: 'species_cattle',
        maleCount: 24,
        femaleCount: 2,
        capacity: 29,
      );
      final group = (await repo.getFarmUnitPopulations(
        farmId: farm.id,
        unitId: unit.id,
      )).single;
      final snapshots = <List<FarmDashboardData>>[];
      final subscription = repo.watchFarmDashboards().listen(snapshots.add);
      addTearDown(subscription.cancel);
      Future<void> move(
        FarmPopulationMovementType type,
        FarmPopulationSex sex,
        int quantity,
      ) => repo.recordFarmPopulationMovement(
        session: session,
        input: FarmPopulationMovementInput(
          farmId: farm.id,
          farmUnitId: unit.id,
          populationId: group.id,
          type: type,
          sex: sex,
          quantity: quantity,
          occurredAt: DateTime(2026, 9, 8),
        ),
      );
      await move(
        FarmPopulationMovementType.purchase,
        FarmPopulationSex.female,
        3,
      );
      expect((await repo.getFarmDashboard(farm.id))!.populationBySpecies, {
        'species_cattle': 29,
      });
      await move(
        FarmPopulationMovementType.purchase,
        FarmPopulationSex.female,
        2,
      );
      expect((await repo.getFarmUnit(farm.id, unit.id))!.capacity, 29);
      expect((await repo.getFarmDashboard(farm.id))!.currentPopulation, 31);
      await move(
        FarmPopulationMovementType.mortality,
        FarmPopulationSex.male,
        2,
      );
      expect(
        (await repo.getFarmUnitPopulations(
          farmId: farm.id,
          unitId: unit.id,
        )).single.maleCount,
        22,
      );
      await expectLater(
        move(FarmPopulationMovementType.mortality, FarmPopulationSex.male, 25),
        throwsStateError,
      );
      expect(
        await repo.getFarmUnitPopulationHistory(
          farmId: farm.id,
          unitId: unit.id,
        ),
        hasLength(3),
      );
      await repo.setFarmArchived(
        session: session,
        farmId: farm.id,
        archived: true,
      );
      expect(await repo.watchFarms(status: 'Active').first, isEmpty);
      expect(await repo.watchFarms(status: 'Archived').first, hasLength(1));
      expect((await repo.getFarmDashboard(farm.id))!.currentPopulation, 29);
      expect(
        await repo.getFarmUnitPopulationHistory(
          farmId: farm.id,
          unitId: unit.id,
        ),
        hasLength(3),
      );
      await expectLater(
        move(FarmPopulationMovementType.purchase, FarmPopulationSex.female, 1),
        throwsStateError,
      );
      await repo.setFarmArchived(
        session: session,
        farmId: farm.id,
        archived: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(snapshots.last.single.currentPopulation, 29);
      expect(snapshots.last.single.farm.status, 'Active');
      // An archived unit contributes no live population, but its groups survive.
      await (db.update(db.farmUnits)..where((row) => row.id.equals(unit.id)))
          .write(const FarmUnitsCompanion(status: Value('Archived')));
      expect((await repo.getFarmDashboard(farm.id))!.currentPopulation, 0);
      expect(
        await repo.getFarmUnitPopulations(farmId: farm.id, unitId: unit.id),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'farm list filters, live summary and long-press actions use actual records',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = _WorkspaceRepository(db);
      await repo.seedSampleData();
      final session = (await repo.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final farm = await repo.createFarm(
        session: session,
        name: 'Actual Farm',
        location: 'Ogidi',
        speciesIds: ['species_cattle'],
      );
      await repo.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Cattle Pen',
        unitType: 'Pen',
        speciesId: 'species_cattle',
        maleCount: 24,
        femaleCount: 2,
      );
      final data = (await repo.getFarmDashboard(farm.id))!;
      repo.initial = [data];
      addTearDown(repo.updates.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            clinicRepositoryProvider.overrideWithValue(repo),
            userSessionProvider.overrideWith((ref) async => session),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const FarmRecordsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Archived (0)'), findsOneWidget);
      expect(find.text('26'), findsWidgets);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('Actual Farm'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Ogidi');
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Actual Farm'));
      await tester.pumpAndSettle();
      for (final label in [
        'Edit Farm Details',
        'Add Purchased Animals',
        'Transfer Animals',
        'Record Mortality',
        'Archive Farm',
        'Cancel',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      repo.updates.add([
        FarmDashboardData(
          farm: data.farm.copyWith(status: 'Archived'),
          units: data.units,
          populations: data.populations,
          dailyRecords: data.dailyRecords,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Active (0)'), findsOneWidget);
      expect(find.text('Actual Farm'), findsNothing);
      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Actual Farm'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            clinicRepositoryProvider.overrideWithValue(repo),
            userSessionProvider.overrideWith((ref) async => session),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: FarmDetailScreen(farmId: farm.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Farm Details'), findsOneWidget);
      expect(find.text('ACTIVE UNITS'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      await tester.tap(find.text('Farm Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Farm Details'), findsOneWidget);
      await tester.tap(find.text('Records'));
      await tester.pumpAndSettle();
      expect(find.text('Daily Records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class _WorkspaceRepository extends ClinicRepository {
  _WorkspaceRepository(super.db);
  List<FarmDashboardData> initial = [];
  final updates = StreamController<List<FarmDashboardData>>.broadcast();
  @override
  Stream<List<FarmDashboardData>> watchFarmDashboards() async* {
    yield initial;
    yield* updates.stream;
  }
}
