import 'package:flutter_test/flutter_test.dart';

import 'package:avera/core/models/inventory_catalog.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/features/billing/services/billing_inventory_utils.dart';
import 'package:avera/features/inventory/widgets/inventory_item_dialog.dart';

void main() {
  test(
    'inventory catalogue has 24 unique categories and valid subcategories',
    () {
      expect(InventoryCategories.all, hasLength(24));
      expect(
        InventoryCategories.all.map((category) => category.id).toSet(),
        hasLength(InventoryCategories.all.length),
      );
      for (final category in InventoryCategories.all) {
        final subcategories = category.subcategories;
        expect(
          subcategories.map((subcategory) => subcategory.id).toSet(),
          hasLength(subcategories.length),
          reason: category.id,
        );
        expect(
          subcategories.every(
            (subcategory) => subcategory.categoryId == category.id,
          ),
          isTrue,
          reason: category.id,
        );
      }
    },
  );

  test(
    'category and subcategory aliases are case and punctuation tolerant',
    () {
      expect(
        InventoryCategories.canonicalId('Pet Accessories'),
        'pet_accessories',
      );
      expect(
        InventoryCategories.canonicalId('laboratory reagents'),
        'diagnostic_laboratory',
      );
      expect(
        InventoryCategories.resolveSubcategory('drugs', 'DE-WORMER')?.id,
        'anthelmintics',
      );
      expect(
        InventoryCategories.resolveSubcategory(
          'drugs',
          'anti-inflammatory',
        )?.id,
        'nsaids',
      );
      expect(
        InventoryCategories.resolveSubcategory('drugs', 'tick and flea')?.id,
        'ectoparasiticides',
      );
      expect(
        InventoryCategories.subcategoriesFor(
          'pet_accessories',
        ).map((subcategory) => subcategory.id),
        contains('collars'),
      );
      expect(
        InventoryCategories.subcategoriesFor(
          'drugs',
        ).map((subcategory) => subcategory.id),
        isNot(contains('collars')),
      );
    },
  );

  test('custom category and subcategory labels remain user-visible', () {
    expect(
      InventoryCategories.displayNameFor('other', 'Wildlife Rehabilitation'),
      'Wildlife Rehabilitation',
    );
    expect(
      InventoryCategories.subcategoryDisplayName(
        'other',
        InventoryCategories.customSubcategoryId,
        'Local field kit',
      ),
      'Local field kit',
    );
  });

  test('billing includes base units and optional package units', () {
    final baseOnly = RemoteInventoryItem.fromJson({
      'inventory_product_id': 'base-only',
      'name': 'EDTA TUBE',
      'category_key': 'medical_equipment',
      'category': 'Laboratory Equipment',
      'quantity': 50,
      'reorder_level': 5,
      'purchase_price': 3500,
      'selling_price': 5000,
      'base_unit_label': 'unit',
      'status': 'Active',
      'product_units': const [],
    });
    final packaged = RemoteInventoryItem.fromJson({
      'inventory_product_id': 'packaged',
      'name': 'Tablet medicine',
      'category_key': 'drugs',
      'category': 'Medicines / Drugs',
      'quantity': 100,
      'reorder_level': 5,
      'purchase_price': 100,
      'selling_price': 150,
      'base_unit_label': 'tablet',
      'status': 'Active',
      'product_units': [
        {
          'product_unit_id': 'box',
          'unit_label': 'box',
          'is_base_unit': false,
          'conversion_to_base': 10,
          'selling_price': 1200,
        },
      ],
    });

    final baseOptions = billableUnitsForInventoryProduct(baseOnly);
    final packageOptions = billableUnitsForInventoryProduct(packaged);
    expect(baseOptions, hasLength(1));
    expect(baseOptions.single.productUnitId, isNull);
    expect(baseOptions.single.label, 'unit');
    expect(baseOptions.single.sellingPrice, 5000);
    expect(packageOptions.map((option) => option.label), ['tablet', 'box']);
    expect(packageOptions.last.availableQuantity, 10);

    final fourEligibleProducts = [baseOnly, packaged, baseOnly, packaged];
    expect(
      fourEligibleProducts
          .where(
            (product) =>
                product.quantity > 0 &&
                product.isSellable &&
                !product.isArchived &&
                billableUnitsForInventoryProduct(product).isNotEmpty,
          )
          .length,
      4,
    );
  });

  test('billing search reaches catalogue records beyond the first screen', () {
    final products = [
      for (var index = 0; index < 100; index++)
        RemoteInventoryItem.fromJson({
          'inventory_product_id': 'product-$index',
          'name': index == 99 ? 'BROAD KILLER' : 'Product $index',
          'category_key': index == 99 ? 'other' : 'drugs',
          'category': index == 99 ? 'Other' : 'Medicines / Drugs',
          'subcategory_key': index == 99 ? 'other' : 'anthelmintics',
          'subcategory': index == 99 ? 'Other' : 'Anthelmintics',
          'quantity': 2,
          'reorder_level': 1,
          'purchase_price': 100,
          'selling_price': 5000,
          'brand_name': index == 99 ? 'FarmGuard' : null,
          'sku': index == 99 ? 'BK-99' : null,
          'status': 'Active',
        }),
    ];
    final match = products
        .where((product) => matchesBillingInventorySearch(product, 'bk-99'))
        .toList();
    expect(match.map((product) => product.name), ['BROAD KILLER']);
    expect(
      products
          .where(
            (product) => matchesBillingInventorySearch(product, 'farmguard'),
          )
          .single
          .name,
      'BROAD KILLER',
    );
  });

  test(
    'inventory remote payload preserves category and nullable subcategory',
    () {
      const draft = InventoryItemDraft(
        submissionId: 'submission-1',
        name: 'Albendazole',
        categoryId: 'drugs',
        categoryName: 'Medicines / Drugs',
        subcategoryId: 'anthelmintics',
        subcategoryName: 'Anthelmintics / Dewormers',
        quantity: 4,
        minimumQuantity: 1,
        sellingPrice: 2000,
        buyingPrice: 1000,
      );
      final payload = draft.toRemotePayload();
      expect(payload['categoryId'], 'drugs');
      expect(payload['categoryName'], 'Medicines / Drugs');
      expect(payload['subcategoryId'], 'anthelmintics');
      expect(payload['subcategoryName'], 'Anthelmintics / Dewormers');

      final remote = RemoteInventoryItem.fromJson({
        'inventory_product_id': 'inventory-1',
        'name': 'Albendazole',
        'category_key': 'drugs',
        'category': 'Medicines / Drugs',
        'subcategory_key': 'anthelmintics',
        'subcategory': 'Anthelmintics / Dewormers',
        'quantity': 4,
        'reorder_level': 1,
        'purchase_price': 1000,
        'selling_price': 2000,
        'status': 'Active',
      });
      expect(remote.toJson()['subcategory_key'], 'anthelmintics');
      expect(remote.toJson()['subcategory'], 'Anthelmintics / Dewormers');
    },
  );
}
