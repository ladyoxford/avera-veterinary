import 'dart:async';

import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/inventory/widgets/inventory_item_dialog.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets(
      'shared clinical fields render at narrow width in ${theme.brightness.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final title = TextEditingController();
        addTearDown(title.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(
                  AveraSpacing.pageHorizontalPadding,
                ),
                children: [
                  AveraLabeledTextField(
                    label: 'Clinical notes',
                    controller: title,
                    hintText: 'Enter relevant clinical notes',
                    minLines: 3,
                    maxLines: 6,
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                  AveraLabeledDropdownField<String>(
                    label: 'Priority',
                    hintText: 'Select priority',
                    value: 'Routine',
                    items: const [
                      DropdownMenuItem(
                        value: 'Routine',
                        child: Text('Routine'),
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                  const AveraPrimaryActionButton(label: 'Create Prescription'),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('CLINICAL NOTES'), findsOneWidget);
        expect(find.text('PRIORITY'), findsOneWidget);
        expect(find.text('Create Prescription'), findsOneWidget);
        expect(theme.colorScheme.onPrimary, Colors.white);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('inventory dialog is scroll-safe at narrow phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    InventoryItemDraft? submitted;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showInventoryItemDialog(
                  context: context,
                  allowedCategoryIds: const {'drugs', 'vaccines'},
                  canSeeCost: true,
                  initial: InventoryItemDraft(
                    submissionId: 'test-submission',
                    remoteId: 'item-1',
                    name: 'Amoxicillin 250 mg',
                    categoryId: 'drugs',
                    quantity: 12,
                    minimumQuantity: 5,
                    batchNumber: 'AMX-2026-01',
                    expiryDate: DateTime(2027, 6, 30),
                    sellingPrice: 1800,
                    buyingPrice: 1200,
                    revision: 1,
                  ),
                  onSubmit: (draft) async => submitted = draft,
                ),
                child: const Text('Open inventory form'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open inventory form'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Inventory Item'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('PRODUCT IMAGE'), findsOneWidget);
    expect(find.text('Add product image'), findsOneWidget);
    expect(find.text('ITEM NAME'), findsOneWidget);
    expect(find.text('CATEGORY'), findsOneWidget);
    expect(find.text('QUANTITY'), findsOneWidget);
    expect(find.text('MINIMUM QUANTITY'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final itemNameField = find.widgetWithText(
      TextFormField,
      'Amoxicillin 250 mg',
    );
    await tester.ensureVisible(itemNameField);
    await tester.tap(itemNameField);
    await tester.pump();
    expect(find.text('Edit Inventory Item'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(submitted?.name, 'Amoxicillin 250 mg');
    expect(find.text('Edit Inventory Item'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory dialog prevents repeated save submissions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completion = Completer<void>();
    var submissions = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showInventoryItemDialog(
                context: context,
                allowedCategoryIds: const {'drugs'},
                canSeeCost: true,
                initial: InventoryItemDraft(
                  submissionId: 'test-submission',
                  name: 'Doxycycline',
                  categoryId: 'drugs',
                  quantity: 8,
                  minimumQuantity: 3,
                  batchNumber: 'DOX-2026-01',
                  expiryDate: DateTime(2027, 6, 30),
                  sellingPrice: 900,
                  buyingPrice: 600,
                ),
                onSubmit: (_) {
                  submissions += 1;
                  return completion.future;
                },
              ),
              child: const Text('Open inventory form'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open inventory form'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Saving'));
    await tester.pump();
    expect(submissions, 1);

    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('New Inventory Item'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drug inventory requires batch and expiry details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var submissions = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showInventoryItemDialog(
                context: context,
                allowedCategoryIds: const {'drugs'},
                canSeeCost: true,
                initial: const InventoryItemDraft(
                  submissionId: 'test-submission',
                  name: 'Doxycycline',
                  categoryId: 'drugs',
                  quantity: 8,
                  minimumQuantity: 3,
                  sellingPrice: 900,
                  buyingPrice: 600,
                ),
                onSubmit: (_) async => submissions += 1,
              ),
              child: const Text('Open inventory form'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open inventory form'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Enter the manufacturer batch number.'), findsOneWidget);
    expect(submissions, 0);
    expect(find.text('Edit Inventory Item'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Enter batch number'),
      'DOX-2026-01',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.text('Choose an expiry date for drugs and vaccine products.'),
      findsOneWidget,
    );
    expect(submissions, 0);
    expect(tester.takeException(), isNull);
  });
}
