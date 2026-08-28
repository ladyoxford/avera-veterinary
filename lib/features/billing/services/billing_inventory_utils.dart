import '../../../core/remote/clinical_remote_data_source.dart';

class BillingProductUnitOption {
  const BillingProductUnitOption({
    required this.productUnitId,
    required this.label,
    required this.conversionToBase,
    required this.sellingPrice,
    required this.availableBaseQuantity,
  });

  final String? productUnitId;
  final String label;
  final int conversionToBase;
  final double sellingPrice;
  final int availableBaseQuantity;

  int get availableQuantity =>
      conversionToBase <= 0 ? 0 : availableBaseQuantity ~/ conversionToBase;
}

List<BillingProductUnitOption> billableUnitsForInventoryProduct(
  RemoteInventoryItem product,
) {
  final configured = product.productUnits
      .map(
        (unit) => BillingProductUnitOption(
          productUnitId: unit.id,
          label: unit.label,
          conversionToBase: unit.conversionToBase,
          sellingPrice: unit.sellingPrice.toDouble(),
          availableBaseQuantity: product.quantity,
        ),
      )
      .where((unit) => unit.availableQuantity > 0)
      .toList();

  final hasConfiguredBaseUnit = product.productUnits.any(
    (unit) => unit.isBaseUnit,
  );
  if (product.quantity > 0 && !hasConfiguredBaseUnit) {
    configured.insert(
      0,
      BillingProductUnitOption(
        productUnitId: null,
        label: product.baseUnitLabel,
        conversionToBase: 1,
        sellingPrice: product.sellingPrice.toDouble(),
        availableBaseQuantity: product.quantity,
      ),
    );
  }
  return configured;
}

bool matchesBillingInventorySearch(RemoteInventoryItem product, String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  if (terms.isEmpty) return true;
  final searchable = <String?>[
    product.name,
    product.genericName,
    product.brandName,
    product.categoryId,
    product.categoryName,
    product.subcategoryId,
    product.subcategoryName,
    product.sku,
    product.barcode,
  ].whereType<String>().join(' ').toLowerCase();
  return terms.every(searchable.contains);
}

bool matchesBillingText(String query, Iterable<String?> fields) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  if (terms.isEmpty) return true;
  final searchable = fields.whereType<String>().join(' ').toLowerCase();
  return terms.every(searchable.contains);
}
