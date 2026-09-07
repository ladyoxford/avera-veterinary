import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/billing/screens/billing_screen.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('modern Add Service form returns the unchanged billing values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ServiceDraftResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAveraActionSheet<ServiceDraftResult>(
                  context: context,
                  title: 'Add Service',
                  builder: (_) => const AddServiceSheet(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('SERVICE NAME'), findsOneWidget);
    expect(find.text('QUANTITY'), findsOneWidget);
    expect(find.text('CHARGE APPLIES TO'), findsOneWidget);
    expect(find.text('PRICE PER UNIT (NGN)'), findsOneWidget);
    expect(find.text('NOTES (OPTIONAL)'), findsOneWidget);
    expect(find.text('Service / description'), findsNothing);
    expect(find.text('Unit / basis (animal, visit, whole farm)'), findsNothing);

    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    await tester.enterText(find.byWidget(fields[0]), 'Farm consultation');
    await tester.enterText(find.byWidget(fields[1]), '2');
    await tester.enterText(find.byWidget(fields[2]), '3500');
    await tester.enterText(find.byWidget(fields[3]), 'Routine review');
    await tester.tap(find.byKey(const Key('add-service-submit')));
    await tester.pumpAndSettle();

    expect(result?.description, 'Farm consultation');
    expect(result?.quantity, 2);
    expect(result?.unitLabel, 'service');
    expect(result?.unitPrice, 3500);
    expect(result?.notes, 'Routine review');
    expect(result?.lineTotal, 7000);
  });
}
