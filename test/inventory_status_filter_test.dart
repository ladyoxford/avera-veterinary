import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/models/inventory_catalog.dart';

void main() {
  final now = DateTime(2026, 7, 22);

  bool matches(
    InventoryStatusFilter filter, {
    required int quantity,
    required int minimumQuantity,
    DateTime? expiryDate,
  }) => filter.matches(
    quantity: quantity,
    minimumQuantity: minimumQuantity,
    expiryDate: expiryDate,
    now: now,
  );

  test('all inventory filter includes every permitted item', () {
    expect(
      matches(
        InventoryStatusFilter.all,
        quantity: 0,
        minimumQuantity: 5,
        expiryDate: now.subtract(const Duration(days: 1)),
      ),
      isTrue,
    );
  });

  test('low stock and expired filters are independent', () {
    expect(
      matches(
        InventoryStatusFilter.lowStock,
        quantity: 3,
        minimumQuantity: 5,
        expiryDate: now.subtract(const Duration(days: 1)),
      ),
      isTrue,
    );
    expect(
      matches(
        InventoryStatusFilter.expired,
        quantity: 3,
        minimumQuantity: 5,
        expiryDate: now.subtract(const Duration(days: 1)),
      ),
      isTrue,
    );
  });

  test('expired filter excludes missing and current expiry dates', () {
    expect(
      matches(InventoryStatusFilter.expired, quantity: 10, minimumQuantity: 5),
      isFalse,
    );
    expect(
      matches(
        InventoryStatusFilter.expired,
        quantity: 10,
        minimumQuantity: 5,
        expiryDate: now,
      ),
      isFalse,
    );
  });
}
