import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/inventory/screens/inventory_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  testWidgets(
    'inventory cart action shows badge and summary without breaking details',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final item = (await repository.readPermittedInventory(session))
          .firstWhere(
            (candidate) => candidate.quantity > 0 && candidate.isSellable,
          );
      final uiRepository = _InventoryUiRepository(database, [item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clinicRepositoryProvider.overrideWithValue(uiRepository),
            userSessionProvider.overrideWith((ref) async => session),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const InventoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cartButton = find.byKey(Key('inventory-cart-${item.id}'));
      expect(cartButton, findsOneWidget);
      await tester.tap(cartButton);
      await tester.pump();
      expect(find.byKey(const Key('inventory-view-cart')), findsOneWidget);
      expect(find.text('1 item in cart'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      await tester.tap(find.text(item.drugName).first);
      await tester.pumpAndSettle();
      expect(find.text('Product Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('out-of-stock inventory cannot be added to retail cart', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    final item = (await repository.readPermittedInventory(session)).first;
    final unavailable = item.copyWith(quantity: 0);
    final uiRepository = _InventoryUiRepository(database, [unavailable]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicRepositoryProvider.overrideWithValue(uiRepository),
          userSessionProvider.overrideWith((ref) async => session),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const InventoryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<IconButton>(
      find.byKey(Key('inventory-cart-${item.id}')),
    );
    expect(button.onPressed, equals(null));
    expect(find.byKey(const Key('inventory-view-cart')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _InventoryUiRepository extends ClinicRepository {
  _InventoryUiRepository(super.database, this.items);

  final List<InventoryItem> items;

  @override
  Stream<List<InventoryItem>> watchPermittedInventory(
    UserSession session, {
    String? categoryId,
    String query = '',
  }) => Stream.value(items);

  @override
  Stream<List<ProductUnit>> watchProductUnits({
    required UserSession session,
    required int inventoryItemId,
  }) => Stream.value(const []);
}
