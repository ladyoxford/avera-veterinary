import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/widgets/catalogue_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('multi catalogue picker is responsive and applies selections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const _CataloguePickerHarness(),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(find.text('Select Farm Species'), findsOneWidget);
    expect(find.byKey(const Key('catalogue-apply-selection')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('catalogue-option-species_cattle')));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalogue-clear-selection')));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalogue-option-species_goat')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('catalogue-apply-selection')));
    await tester.pumpAndSettle();

    expect(find.text('Applied: species_goat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel preserves the previous saved catalogue selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const _CataloguePickerHarness(),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalogue-option-species_cattle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('catalogue-cancel-selection')));
    await tester.pumpAndSettle();

    expect(find.text('Applied: none'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _CataloguePickerHarness extends StatefulWidget {
  const _CataloguePickerHarness();

  @override
  State<_CataloguePickerHarness> createState() =>
      _CataloguePickerHarnessState();
}

class _CataloguePickerHarnessState extends State<_CataloguePickerHarness> {
  Set<String> _applied = {};

  Future<void> _openPicker() async {
    final selected = await showMultiSearchableCatalogueSelector(
      context: context,
      title: 'Select Farm Species',
      selectedIds: _applied,
      options: const [
        CataloguePickerOption(
          id: 'species_cattle',
          title: 'Cattle',
          category: 'Livestock',
        ),
        CataloguePickerOption(
          id: 'species_goat',
          title: 'Goat',
          category: 'Livestock',
        ),
        CataloguePickerOption(
          id: 'species_sheep',
          title: 'Sheep',
          category: 'Livestock',
        ),
      ],
    );
    if (!mounted || selected == null) return;
    setState(() => _applied = selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _applied.isEmpty
                ? 'Applied: none'
                : 'Applied: ${_applied.toList()..sort()}'
                      .replaceAll('[', '')
                      .replaceAll(']', ''),
          ),
          FilledButton(
            onPressed: _openPicker,
            child: const Text('Open picker'),
          ),
        ],
      ),
    ),
  );
}
