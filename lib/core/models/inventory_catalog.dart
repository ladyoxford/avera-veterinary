class InventoryCategoryDefinition {
  const InventoryCategoryDefinition({
    required this.id,
    required this.name,
    required this.isSellable,
    this.isClinical = false,
    this.isPharmacy = false,
    this.isLaboratory = false,
  });

  final String id;
  final String name;
  final bool isSellable;
  final bool isClinical;
  final bool isPharmacy;
  final bool isLaboratory;
}

enum InventoryStatusFilter {
  all,
  lowStock,
  expired;

  bool matches({
    required int quantity,
    required int minimumQuantity,
    required DateTime? expiryDate,
    required DateTime now,
  }) => switch (this) {
    InventoryStatusFilter.all => true,
    InventoryStatusFilter.lowStock => quantity <= minimumQuantity,
    InventoryStatusFilter.expired =>
      expiryDate != null && expiryDate.isBefore(now),
  };

  String get label => switch (this) {
    InventoryStatusFilter.all => 'Items',
    InventoryStatusFilter.lowStock => 'Low stock',
    InventoryStatusFilter.expired => 'Expired',
  };
}

class InventoryCategories {
  const InventoryCategories._();

  static const all = <InventoryCategoryDefinition>[
    InventoryCategoryDefinition(
      id: 'drugs',
      name: 'Drugs',
      isSellable: true,
      isClinical: true,
      isPharmacy: true,
    ),
    InventoryCategoryDefinition(
      id: 'vaccines',
      name: 'Vaccines',
      isSellable: true,
      isClinical: true,
      isPharmacy: true,
    ),
    InventoryCategoryDefinition(
      id: 'supplements',
      name: 'Supplements',
      isSellable: true,
      isClinical: true,
      isPharmacy: true,
    ),
    InventoryCategoryDefinition(
      id: 'clinical_consumables',
      name: 'Clinical Consumables',
      isSellable: true,
      isClinical: true,
    ),
    InventoryCategoryDefinition(
      id: 'surgical_supplies',
      name: 'Surgical Supplies',
      isSellable: true,
      isClinical: true,
    ),
    InventoryCategoryDefinition(
      id: 'laboratory_reagents',
      name: 'Laboratory Reagents',
      isSellable: true,
      isLaboratory: true,
    ),
    InventoryCategoryDefinition(
      id: 'diagnostic_test_kits',
      name: 'Diagnostic and Test Kits',
      isSellable: true,
      isLaboratory: true,
    ),
    InventoryCategoryDefinition(
      id: 'laboratory_consumables',
      name: 'Laboratory Consumables',
      isSellable: true,
      isLaboratory: true,
    ),
    InventoryCategoryDefinition(
      id: 'laboratory_equipment',
      name: 'Laboratory Equipment',
      isSellable: false,
      isLaboratory: true,
    ),
    InventoryCategoryDefinition(
      id: 'general_equipment',
      name: 'General Equipment',
      isSellable: false,
    ),
    InventoryCategoryDefinition(
      id: 'pet_food',
      name: 'Pet Food',
      isSellable: true,
    ),
    InventoryCategoryDefinition(
      id: 'pet_accessories',
      name: 'Pet Accessories',
      isSellable: true,
    ),
    InventoryCategoryDefinition(
      id: 'grooming_supplies',
      name: 'Grooming Supplies',
      isSellable: true,
    ),
    InventoryCategoryDefinition(
      id: 'office_supplies',
      name: 'Office Supplies',
      isSellable: false,
    ),
    InventoryCategoryDefinition(id: 'other', name: 'Other', isSellable: false),
  ];

  static InventoryCategoryDefinition? byId(String? id) {
    for (final category in all) {
      if (category.id == id) return category;
    }
    return null;
  }

  static String canonicalId(String legacyValue) {
    final value = legacyValue.trim().toLowerCase();
    if (value.contains('vaccine')) return 'vaccines';
    if (value.contains('drug') || value.contains('pharmacy')) return 'drugs';
    if (value.contains('supplement')) return 'supplements';
    if (value.contains('reagent')) return 'laboratory_reagents';
    if (value.contains('test') || value.contains('diagnostic')) {
      return 'diagnostic_test_kits';
    }
    if (value.contains('laboratory') && value.contains('consumable')) {
      return 'laboratory_consumables';
    }
    if (value.contains('laboratory') && value.contains('equipment')) {
      return 'laboratory_equipment';
    }
    if (value.contains('consumable')) return 'clinical_consumables';
    if (value.contains('surg')) return 'surgical_supplies';
    if (value.contains('food')) return 'pet_food';
    if (value.contains('accessor')) return 'pet_accessories';
    if (value.contains('groom')) return 'grooming_supplies';
    if (value.contains('office')) return 'office_supplies';
    if (value.contains('equipment')) return 'general_equipment';
    return 'other';
  }
}

class InventoryAccess {
  const InventoryAccess._();

  static String viewPermission(String categoryId) =>
      'inventory.category.$categoryId.view';

  static String sellPermission(String categoryId) =>
      'inventory.category.$categoryId.sell';

  static Set<String> configuredViewCategories(Set<String> permissions) => {
    for (final category in InventoryCategories.all)
      if (permissions.contains(viewPermission(category.id))) category.id,
  };

  static Set<String> configuredSellCategories(Set<String> permissions) => {
    for (final category in InventoryCategories.all)
      if (permissions.contains(sellPermission(category.id))) category.id,
  };

  static Set<String> defaultCategoriesForRole(String role) => switch (role) {
    'Pharmacist' => {'drugs', 'vaccines', 'supplements'},
    'Laboratory Staff' => {
      'laboratory_reagents',
      'diagnostic_test_kits',
      'laboratory_consumables',
      'laboratory_equipment',
    },
    'Veterinary Nurse' => {'vaccines', 'clinical_consumables'},
    'Veterinarian' => {
      'drugs',
      'vaccines',
      'clinical_consumables',
      'surgical_supplies',
    },
    'Cashier' || 'Sales Representative' => {
      for (final category in InventoryCategories.all)
        if (category.isSellable) category.id,
    },
    _ => const <String>{},
  };
}

String formatNaira(num amount) =>
    'NGN ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(?<=\\d)(?=(\\d{3})+(?!\\d))'), (match) => ',')}';
