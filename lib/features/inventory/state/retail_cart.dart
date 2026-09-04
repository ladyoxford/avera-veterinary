import 'package:flutter_riverpod/flutter_riverpod.dart';

class RetailCartScope {
  const RetailCartScope({
    required this.clinicId,
    required this.userId,
    this.sessionEpoch,
  });

  final String clinicId;
  final String userId;
  final int? sessionEpoch;

  @override
  bool operator ==(Object other) =>
      other is RetailCartScope &&
      other.clinicId == clinicId &&
      other.userId == userId &&
      other.sessionEpoch == sessionEpoch;

  @override
  int get hashCode => Object.hash(clinicId, userId, sessionEpoch);
}

class RetailCartProduct {
  const RetailCartProduct({
    required this.productId,
    required this.name,
    required this.unitLabel,
    required this.unitPrice,
    required this.availableBaseQuantity,
    required this.conversionToBase,
    this.localProductId,
    this.unitId,
    this.imageReference,
  });

  final String productId;
  final int? localProductId;
  final String? unitId;
  final String name;
  final String unitLabel;
  final double unitPrice;
  final int availableBaseQuantity;
  final int conversionToBase;
  final String? imageReference;

  String get key => '$productId:${unitId ?? 'base'}';
  int get availableUnits => availableBaseQuantity ~/ conversionToBase;

  RetailCartProduct copyWith({
    String? name,
    String? unitLabel,
    double? unitPrice,
    int? availableBaseQuantity,
    int? conversionToBase,
    String? imageReference,
  }) => RetailCartProduct(
    productId: productId,
    localProductId: localProductId,
    unitId: unitId,
    name: name ?? this.name,
    unitLabel: unitLabel ?? this.unitLabel,
    unitPrice: unitPrice ?? this.unitPrice,
    availableBaseQuantity: availableBaseQuantity ?? this.availableBaseQuantity,
    conversionToBase: conversionToBase ?? this.conversionToBase,
    imageReference: imageReference ?? this.imageReference,
  );
}

class RetailCartLine {
  const RetailCartLine({required this.product, required this.quantity});

  final RetailCartProduct product;
  final int quantity;

  double get total => product.unitPrice * quantity;

  RetailCartLine copyWith({RetailCartProduct? product, int? quantity}) =>
      RetailCartLine(
        product: product ?? this.product,
        quantity: quantity ?? this.quantity,
      );
}

class RetailCartState {
  const RetailCartState({this.lines = const {}});

  final Map<String, RetailCartLine> lines;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.values.fold(0, (sum, line) => sum + line.quantity);
  double get total => lines.values.fold(0, (sum, line) => sum + line.total);
}

class RetailCartController extends StateNotifier<RetailCartState> {
  RetailCartController() : super(const RetailCartState());

  bool add(RetailCartProduct product) {
    if (product.availableUnits <= 0) return false;
    final current = state.lines[product.key];
    final nextQuantity = (current?.quantity ?? 0) + 1;
    if (nextQuantity > product.availableUnits) return false;
    _setLine(product, nextQuantity);
    return true;
  }

  bool increment(String key) {
    final current = state.lines[key];
    if (current == null || current.quantity >= current.product.availableUnits) {
      return false;
    }
    _setLine(current.product, current.quantity + 1);
    return true;
  }

  void decrement(String key) {
    final current = state.lines[key];
    if (current == null) return;
    if (current.quantity <= 1) {
      final lines = Map<String, RetailCartLine>.from(state.lines)..remove(key);
      state = RetailCartState(lines: lines);
      return;
    }
    _setLine(current.product, current.quantity - 1);
  }

  void remove(String key) {
    if (!state.lines.containsKey(key)) return;
    final lines = Map<String, RetailCartLine>.from(state.lines)..remove(key);
    state = RetailCartState(lines: lines);
  }

  void reconcile(Iterable<RetailCartProduct> products) {
    final canonical = {for (final product in products) product.key: product};
    final lines = <String, RetailCartLine>{};
    for (final entry in state.lines.entries) {
      final product = canonical[entry.key];
      if (product == null || product.availableUnits <= 0) continue;
      final quantity = entry.value.quantity.clamp(1, product.availableUnits);
      lines[entry.key] = RetailCartLine(product: product, quantity: quantity);
    }
    state = RetailCartState(lines: lines);
  }

  void clear() => state = const RetailCartState();

  void _setLine(RetailCartProduct product, int quantity) {
    final lines = Map<String, RetailCartLine>.from(state.lines);
    lines[product.key] = RetailCartLine(product: product, quantity: quantity);
    state = RetailCartState(lines: lines);
  }
}

final retailCartProvider =
    StateNotifierProvider.family<
      RetailCartController,
      RetailCartState,
      RetailCartScope
    >((ref, scope) => RetailCartController());
