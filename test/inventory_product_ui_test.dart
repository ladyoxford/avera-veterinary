import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/inventory/screens/inventory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('product placeholder remains stable at narrow phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: InventoryProductImage(
              name: 'Long veterinary pharmaceutical product name',
              width: 76,
              height: 92,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.medication_liquid_outlined), findsOneWidget);
    expect(
      tester.getSize(find.byType(InventoryProductImage)),
      const Size(76, 92),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('broken product image falls back without a layout exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: InventoryProductImage(
            name: 'Unavailable image',
            imageReference: 'C:/missing/inventory-photo.jpg',
            width: 160,
            height: 220,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.medication_liquid_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
