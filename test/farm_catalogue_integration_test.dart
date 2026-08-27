import 'dart:io';

import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/farm/screens/farm_profile_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'farm profile uses the global searchable catalogue and custom breeds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const FarmProfileEditorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('farm-species-selector')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('catalogue-search-field')),
        'horse',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalogue-option-species_horse')));
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('catalogue-apply-selection')),
      );
      await tester.tap(find.byKey(const Key('catalogue-apply-selection')));
      await tester.pumpAndSettle();

      final horseBreedSelector = find.byKey(
        const Key('farm-breed-selector-species_horse'),
      );
      await tester.scrollUntilVisible(
        horseBreedSelector,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(horseBreedSelector);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('catalogue-search-field')),
        'argentine',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key(
            'catalogue-option-breed_horse_argentine_criollo_criollo_argentino',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('catalogue-option-breed_horse_argentine_polo_pony'),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('catalogue-search-field')),
        'Other Breed',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('catalogue-option-breed_horse_other_breed')),
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('catalogue-apply-selection')),
      );
      await tester.tap(find.byKey(const Key('catalogue-apply-selection')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('custom-breed-name-field')),
        'Pampas Working Horse',
      );
      await tester.tap(find.byKey(const Key('save-custom-breed')));
      await tester.pumpAndSettle();

      expect(find.text('Pampas Working Horse'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('farm unit and mixed population selectors share catalogue fields', () {
    final source = File(
      'lib/features/farm/screens/farm_records_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('FilterChip(')));
    expect(source, contains("Key('farm-unit-species-selector')"));
    expect(source, contains("Key('farm-unit-breed-selector')"));
    expect(source, contains("Key('mixed-population-species-selector')"));
    expect(source, contains("Key('mixed-population-breed-selector')"));
    expect(source, contains('animalSpeciesPickerOptions'));
    expect(source, contains('animalBreedPickerOptions'));
  });
}
