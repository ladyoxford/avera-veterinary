import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/inventory/screens/retail_cart_screen.dart';
import 'package:avera/features/inventory/state/retail_cart.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retail Cart renders product-only checkout and updates quantity', (
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
    final scope = RetailCartScope(
      clinicId: session.clinic.clinicId,
      userId: session.user.userId,
      sessionEpoch: session.user.lastLogin?.microsecondsSinceEpoch,
    );
    final container = ProviderContainer(
      overrides: [
        clinicRepositoryProvider.overrideWithValue(repository),
        userSessionProvider.overrideWith((ref) async => session),
      ],
    );
    addTearDown(container.dispose);
    const product = RetailCartProduct(
      productId: 'local:4',
      localProductId: 4,
      name: 'Retail Test Product',
      unitLabel: 'Can',
      unitPrice: 2000,
      availableBaseQuantity: 4,
      conversionToBase: 1,
    );
    container.read(retailCartProvider(scope).notifier).add(product);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RetailCartScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Retail sale - not linked to any patient'),
      findsOneWidget,
    );
    expect(find.text('Retail Test Product'), findsOneWidget);
    await tester.tap(find.byKey(Key('retail-plus-${product.key}')));
    await tester.pump();
    expect(container.read(retailCartProvider(scope)).itemCount, 2);
    await tester.tap(find.byKey(Key('retail-minus-${product.key}')));
    await tester.pump();
    await tester.tap(find.byKey(Key('retail-minus-${product.key}')));
    await tester.pump();
    expect(find.text('Your retail cart is empty'), findsOneWidget);

    container.read(retailCartProvider(scope).notifier).add(product);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Customer name (optional)'), findsOneWidget);
    expect(find.text('Phone number (optional)'), findsOneWidget);
    expect(find.byKey(const Key('retail-generate-invoice')), findsOneWidget);
    expect(
      find.text(
        'Customer name and phone can be added on the invoice, or left blank for a walk-in sale.',
      ),
      findsOneWidget,
    );
  });
}
