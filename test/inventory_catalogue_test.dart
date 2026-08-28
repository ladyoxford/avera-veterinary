import 'package:flutter_test/flutter_test.dart';

import 'package:avera/core/models/inventory_catalog.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
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
