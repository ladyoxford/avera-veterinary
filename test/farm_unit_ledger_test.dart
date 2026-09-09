import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/farm/screens/farm_detail_screens.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'ledger updates canonical sex, farm, species, daily records and stream; retries do not duplicate',
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
        name: 'Ledger Farm',
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
      final sub = repo.watchFarmDashboards().listen(snapshots.add);
      addTearDown(sub.cancel);
      Future<void> move(
        FarmPopulationMovementType type,
        FarmPopulationSex sex,
        int quantity,
        String id,
      ) => repo.recordFarmPopulationMovement(
        session: session,
        input: FarmPopulationMovementInput(
          farmId: farm.id,
          farmUnitId: unit.id,
          populationId: group.id,
          type: type,
          sex: sex,
          quantity: quantity,
          occurredAt: DateTime(2026, 9, 9),
          submissionId: id,
        ),
      );
      await move(
        FarmPopulationMovementType.purchase,
        FarmPopulationSex.male,
        5,
        'purchase',
      );
      expect((await repo.getFarmDashboard(farm.id))!.currentPopulation, 31);
      // Simulate history created before structured movement caching existed.
      await (db.delete(db.cloudCacheEntries)..where(
            (row) => row.cacheKey.equals(
              'farm-movements:${session.clinic.clinicId}:${farm.id}',
            ),
          ))
          .go();
      await move(
        FarmPopulationMovementType.sale,
        FarmPopulationSex.male,
        3,
        'sale',
      );
      expect((await repo.getFarmDashboard(farm.id))!.currentPopulation, 28);
      await move(
        FarmPopulationMovementType.sale,
        FarmPopulationSex.male,
        3,
        'sale',
      );
      expect((await repo.getFarmDashboard(farm.id))!.currentPopulation, 28);
      await expectLater(
        move(
          FarmPopulationMovementType.sale,
          FarmPopulationSex.male,
          27,
          'oversale',
        ),
        throwsStateError,
      );
      await expectLater(
        move(
          FarmPopulationMovementType.mortality,
          FarmPopulationSex.female,
          3,
          'overdeath',
        ),
        throwsStateError,
      );
      await move(
        FarmPopulationMovementType.mortality,
        FarmPopulationSex.female,
        1,
        'death',
      );
      final updated = (await repo.getFarmUnit(farm.id, unit.id))!;
      expect(
        [
          updated.maleCount,
          updated.femaleCount,
          updated.unknownCount,
          updated.capacity,
        ],
        [26, 1, 0, 29],
      );
      final history = await repo.getFarmUnitPopulationHistory(
        farmId: farm.id,
        unitId: unit.id,
      );
      expect(history.length, 3);
      expect(history.map((h) => h.type).toSet(), {
        'purchase',
        'sale',
        'mortality',
      });
      final daily = (await repo.getFarmDailyRecordForDate(
        farm.id,
        DateTime(2026, 9, 9),
      ))!;
      expect(
        [
          daily.purchases,
          daily.sales,
          daily.mortality,
          daily.closingPopulation,
        ],
        [5, 3, 1, 27],
      );
      await repo.updateFarmUnitMetadata(
        session: session,
        farmId: farm.id,
        unitId: unit.id,
        name: 'Updated Pen',
        unitType: 'Pen',
        capacity: 20,
      );
      expect((await repo.getFarmUnit(farm.id, unit.id))!.maleCount, 26);
      expect(
        (await repo.getFarmUnitPopulations(
          farmId: farm.id,
          unitId: unit.id,
        )).single.id,
        group.id,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(snapshots.last.single.populationBySpecies, {'species_cattle': 27});
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'Farm Unit workspace tabs and transaction forms at phone width dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        late AppDatabase db;
        late ClinicRepository repo;
        late Widget subject;
        await tester.runAsync(() async {
          db = AppDatabase.forTesting(NativeDatabase.memory());
          repo = _FailOnceRepository(db);
          await repo.seedSampleData();
          final session = (await repo.authenticateUser(
            username: 'admin@avera.test',
            password: 'admin123',
          ))!;
          final farm = await repo.createFarm(
            session: session,
            name: 'Real Farm',
            speciesIds: ['species_cattle'],
          );
          final unit = await repo.createFarmUnit(
            session: session,
            farmId: farm.id,
            name: 'Real Pen',
            unitType: 'Pen',
            speciesId: 'species_cattle',
            maleCount: 24,
            femaleCount: 2,
            capacity: 29,
          );
          subject = ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              clinicRepositoryProvider.overrideWithValue(repo),
              userSessionProvider.overrideWith((ref) async => session),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: FarmUnitDetailScreen(farmId: farm.id, unitId: unit.id),
            ),
          );
        });
        addTearDown(() => db.close());
        await tester.pumpWidget(subject);
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Farm Unit'), findsOneWidget);
        expect(find.text('Farm Unit Details'), findsNothing);
        expect(find.text('26 / 29'), findsOneWidget);
        expect(find.text('Males'), findsOneWidget);
        expect(find.text('Females'), findsOneWidget);
        expect(find.text('Unknown'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        for (final type in ['Purchase', 'Sale', 'Mortality']) {
          final action = find.widgetWithText(FilledButton, type);
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(find.text('Record $type'), findsOneWidget);
          expect(find.text('Current population'), findsOneWidget);
          expect(find.text('New population'), findsOneWidget);
          final quantity = type == 'Purchase'
              ? '5'
              : type == 'Sale'
              ? '3'
              : '1';
          await tester.enterText(find.byType(TextFormField).first, quantity);
          await tester.pumpAndSettle();
          if (type == 'Purchase') {
            expect(
              find.textContaining('Population will exceed'),
              findsOneWidget,
            );
          }
          final sex = find.byType(DropdownButtonFormField<FarmPopulationSex>);
          await tester.ensureVisible(sex);
          await tester.tap(sex);
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(type == 'Mortality' ? 'Female' : 'Male').last,
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Save $type'));
          await tester.tap(find.text('Save $type'));
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          await tester.pumpAndSettle();
          if (type == 'Purchase') {
            expect(
              find.text('Purchase could not be saved. Please try again.'),
              findsOneWidget,
            );
            expect(find.text("Instance of 'ApiException'"), findsNothing);
            expect(find.textContaining('SQL failure'), findsNothing);
            await tester.tap(find.text('Save Purchase'));
            await tester.runAsync(
              () async =>
                  Future<void>.delayed(const Duration(milliseconds: 500)),
            );
            await tester.pumpAndSettle();
          }
          expect(
            find.text(
              type == 'Purchase'
                  ? '31 / 29'
                  : type == 'Sale'
                  ? '28 / 29'
                  : '27 / 29',
            ),
            findsOneWidget,
          );
        }
        for (final label in [
          'Animals',
          'Transactions',
          'Records',
          'Settings',
          'Overview',
        ]) {
          final tab = find.widgetWithText(ChoiceChip, label);
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await tester.pumpAndSettle();
        }
        expect(find.text('Health & Management'), findsOneWidget);
        expect(find.text('Unit Information'), findsOneWidget);
        expect(find.text('Recent Transactions'), findsOneWidget);
        expect(find.text("Instance of 'ApiException'"), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _FailOnceRepository extends ClinicRepository {
  _FailOnceRepository(super.db);
  bool failNext = true;
  @override
  Future<void> recordFarmPopulationMovement({
    required UserSession session,
    required FarmPopulationMovementInput input,
  }) async {
    if (failNext) {
      failNext = false;
      throw const ApiException(
        'database_error',
        'SQL failure with private server details',
      );
    }
    return super.recordFarmPopulationMovement(session: session, input: input);
  }
}
