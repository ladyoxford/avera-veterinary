import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/farm/screens/farm_detail_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('farm summary keeps long breed and counts separated on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _subject(
        FarmUnitSummaryCard(
          unit: _unit(
            speciesId: 'species_goat',
            breedId: 'breed_goat_red_sokoto_maradi',
            maleCount: 3,
            femaleCount: 10,
          ),
        ),
      ),
    );

    expect(find.text('Goat'), findsOneWidget);
    expect(find.text('Red Sokoto / Maradi'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm summary uses the same layout for sheep', (tester) async {
    await tester.pumpWidget(
      _subject(
        FarmUnitSummaryCard(
          unit: _unit(
            speciesId: 'species_sheep',
            breedId: 'breed_sheep_yankasa',
            maleCount: 3,
            femaleCount: 5,
          ),
        ),
      ),
    );

    expect(find.text('Sheep'), findsOneWidget);
    expect(find.text('Yankasa'), findsOneWidget);
    expect(find.text('3 / 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets('treatment cards show complete last and next values', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _subject(
          FarmTreatmentOverviewGrid(
            treatments: [
              _treatment(
                eventType: 'Deworming',
                occurredAt: DateTime(2026, 8, 22),
                nextDueDate: DateTime(2026, 9, 22),
              ),
              _treatment(
                eventType: 'Antitrypanocide',
                occurredAt: DateTime(2026, 8, 22),
              ),
            ],
          ),
          theme: theme,
        ),
      );

      expect(find.text('LAST'), findsNWidgets(4));
      expect(find.text('NEXT'), findsNWidgets(4));
      expect(find.text('Aug 22, 2026'), findsNWidgets(2));
      expect(find.text('Sep 22, 2026'), findsOneWidget);
      expect(find.text('Not scheduled'), findsOneWidget);
      expect(find.text('Not recorded'), findsNWidgets(4));
      expect(find.textContaining('...'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _subject(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

FarmUnit _unit({
  required String speciesId,
  required String breedId,
  required int maleCount,
  required int femaleCount,
}) => FarmUnit(
  id: 1,
  clinicId: 'clinic-1',
  farmId: 'farm-1',
  name: 'Unit',
  unitType: 'Pen',
  speciesId: speciesId,
  breedId: breedId,
  capacity: maleCount + femaleCount,
  maleCount: maleCount,
  femaleCount: femaleCount,
  unknownCount: 0,
  status: 'Active',
  createdAt: DateTime(2026),
  createdByUserId: 'user-1',
  updatedAt: DateTime(2026),
);

FarmHealthRecord _treatment({
  required String eventType,
  required DateTime occurredAt,
  DateTime? nextDueDate,
}) => FarmHealthRecord(
  id: eventType.hashCode,
  clinicId: 'clinic-1',
  farmId: 'farm-1',
  farmUnitId: 1,
  occurredAt: occurredAt,
  eventType: eventType,
  product: 'A treatment product with a long name',
  animalsCovered: 13,
  nextDueDate: nextDueDate,
  createdByUserId: 'user-1',
);
