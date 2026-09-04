import 'package:avera/features/inventory/state/retail_cart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const product = RetailCartProduct(
    productId: 'product-1',
    localProductId: 1,
    name: 'Balance Chicken Dinner',
    unitLabel: 'Can',
    unitPrice: 2000,
    availableBaseQuantity: 2,
    conversionToBase: 1,
  );

  test(
    'cart adds, increments, caps stock, decrements, and removes at zero',
    () {
      final controller = RetailCartController();
      expect(controller.add(product), isTrue);
      expect(controller.add(product), isTrue);
      expect(controller.add(product), isFalse);
      expect(controller.state.itemCount, 2);
      expect(controller.state.total, 4000);

      controller.decrement(product.key);
      expect(controller.state.itemCount, 1);
      expect(controller.state.total, 2000);
      controller.decrement(product.key);
      expect(controller.state.isEmpty, isTrue);
    },
  );

  test('reconcile applies canonical price and stock before checkout', () {
    final controller = RetailCartController();
    controller.add(product);
    controller.add(product);
    controller.reconcile([
      product.copyWith(unitPrice: 2500, availableBaseQuantity: 1),
    ]);
    expect(controller.state.itemCount, 1);
    expect(controller.state.total, 2500);
  });

  test(
    'cart survives provider reads and remains scoped by clinic and user',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const first = RetailCartScope(clinicId: 'clinic-1', userId: 'user-1');
      const secondUser = RetailCartScope(
        clinicId: 'clinic-1',
        userId: 'user-2',
      );
      const secondClinic = RetailCartScope(
        clinicId: 'clinic-2',
        userId: 'user-1',
      );

      container.read(retailCartProvider(first).notifier).add(product);
      expect(container.read(retailCartProvider(first)).itemCount, 1);
      expect(container.read(retailCartProvider(first)).itemCount, 1);
      expect(container.read(retailCartProvider(secondUser)).isEmpty, isTrue);
      expect(container.read(retailCartProvider(secondClinic)).isEmpty, isTrue);
    },
  );
}
