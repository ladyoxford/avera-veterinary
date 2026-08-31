import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../../../core/models/inventory_catalog.dart';

const inventoryImportMaxBytes = 10 * 1024 * 1024;
const inventoryImportMaxRows = 2000;

enum InventoryImportField {
  productName('Product Name'),
  category('Category'),
  subcategory('Subcategory'),
  brandName('Brand'),
  genericName('Generic Name'),
  manufacturer('Manufacturer'),
  sku('SKU'),
  barcode('Barcode'),
  sellingPrice('Selling Price'),
  costPrice('Cost Price'),
  quantity('Quantity in Stock'),
  unit('Unit / Base Unit'),
  packSize('Pack Size'),
  batchNumber('Batch Number'),
  expiryDate('Expiry Date'),
  storageConditions('Storage Conditions'),
  dosageForm('Product Form / Presentation');

  const InventoryImportField(this.label);
  final String label;
}

enum InventoryMappingConfidence { high, manual, ambiguous }

class InventoryImportException implements Exception {
  const InventoryImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class InventoryImportRow {
  const InventoryImportRow({required this.sourceRow, required this.values});
  final int sourceRow;
  final List<String> values;
}

class InventoryColumnMapping {
  const InventoryColumnMapping({
    required this.sourceIndex,
    required this.header,
    required this.target,
    required this.confidence,
  });
  final int sourceIndex;
  final String header;
  final InventoryImportField? target;
  final InventoryMappingConfidence confidence;

  InventoryColumnMapping copyWith({
    InventoryImportField? target,
    bool clearTarget = false,
    InventoryMappingConfidence? confidence,
  }) => InventoryColumnMapping(
    sourceIndex: sourceIndex,
    header: header,
    target: clearTarget ? null : target ?? this.target,
    confidence: confidence ?? this.confidence,
  );
}

class InventoryImportDocument {
  const InventoryImportDocument({
    required this.filename,
    required this.headers,
    required this.rows,
    required this.mapping,
  });
  final String filename;
  final List<String> headers;
  final List<InventoryImportRow> rows;
  final List<InventoryColumnMapping> mapping;

  InventoryImportDocument withMapping(List<InventoryColumnMapping> value) =>
      InventoryImportDocument(
        filename: filename,
        headers: headers,
        rows: rows,
        mapping: value,
      );
}

class InventoryImportCandidate {
  const InventoryImportCandidate({
    required this.sourceRow,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.quantity,
    required this.sellingPrice,
    required this.costPrice,
    required this.baseUnitLabel,
    this.subcategoryId,
    this.subcategoryName,
    this.brandName,
    this.genericName,
    this.manufacturer,
    this.sku,
    this.barcode,
    this.packSize,
    this.batchNumber,
    this.expiryDate,
    this.storageConditions,
    this.dosageForm,
  });

  final int sourceRow;
  final String name;
  final String categoryId;
  final String categoryName;
  final String? subcategoryId;
  final String? subcategoryName;
  final int quantity;
  final double sellingPrice;
  final double? costPrice;
  final String baseUnitLabel;
  final String? brandName;
  final String? genericName;
  final String? manufacturer;
  final String? sku;
  final String? barcode;
  final String? packSize;
  final String? batchNumber;
  final DateTime? expiryDate;
  final String? storageConditions;
  final String? dosageForm;
}

class InventoryRowValidation {
  const InventoryRowValidation({
    required this.sourceRow,
    required this.candidate,
    required this.errors,
    required this.warnings,
  });
  final int sourceRow;
  final InventoryImportCandidate? candidate;
  final List<String> errors;
  final List<String> warnings;
  bool get isValid => errors.isEmpty && candidate != null;
  bool get isMissingCost => candidate?.costPrice == null;
}

class InventoryImportValidationResult {
  const InventoryImportValidationResult(this.rows);
  final List<InventoryRowValidation> rows;
  List<InventoryRowValidation> get validRows =>
      rows.where((row) => row.isValid).toList(growable: false);
  int get invalidCount => rows.where((row) => !row.isValid).length;
  int get warningCount => rows.where((row) => row.warnings.isNotEmpty).length;
  int get missingCostCount => rows.where((row) => row.isMissingCost).length;
}

enum InventoryDuplicateAction { skip, updateExisting, importAsNew }

class InventoryExistingProduct {
  const InventoryExistingProduct({
    required this.id,
    required this.name,
    required this.categoryId,
    this.sku,
    this.barcode,
    this.genericName,
    this.manufacturer,
    this.sellingPrice,
  });
  final Object id;
  final String name;
  final String categoryId;
  final String? sku;
  final String? barcode;
  final String? genericName;
  final String? manufacturer;
  final double? sellingPrice;
}

class InventoryDuplicateMatch {
  const InventoryDuplicateMatch({
    required this.candidate,
    required this.existing,
    required this.reason,
    this.action = InventoryDuplicateAction.skip,
  });
  final InventoryImportCandidate candidate;
  final InventoryExistingProduct existing;
  final String reason;
  final InventoryDuplicateAction action;

  InventoryDuplicateMatch withAction(InventoryDuplicateAction value) =>
      InventoryDuplicateMatch(
        candidate: candidate,
        existing: existing,
        reason: reason,
        action: value,
      );
}

class InventoryImportParser {
  const InventoryImportParser();

  InventoryImportDocument parse({
    required String filename,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty) {
      throw const InventoryImportException('The selected file is empty.');
    }
    if (bytes.length > inventoryImportMaxBytes) {
      throw const InventoryImportException(
        'The selected file is larger than the allowed import size.',
      );
    }
    final extension = filename.split('.').last.toLowerCase();
    final matrix = switch (extension) {
      'csv' => _parseCsv(bytes),
      'xlsx' => _parseXlsx(bytes),
      _ => throw const InventoryImportException(
        'Choose an Excel (.xlsx) or CSV file.',
      ),
    };
    return _document(filename, matrix);
  }

  List<List<String>> _parseCsv(Uint8List bytes) {
    try {
      final text = utf8
          .decode(bytes, allowMalformed: false)
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      return const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
          .convert(text)
          .map((row) => row.map((value) => '$value'.trim()).toList())
          .toList();
    } catch (_) {
      throw const InventoryImportException(
        'AVERA could not read this CSV file.',
      );
    }
  }

  List<List<String>> _parseXlsx(Uint8List bytes) {
    try {
      final workbook = Excel.decodeBytes(bytes);
      final sheetName = workbook.tables.keys.firstWhere(
        (name) => workbook.tables[name]!.rows.any(
          (row) => row.any((cell) => _cellText(cell?.value).isNotEmpty),
        ),
      );
      final sheet = workbook.tables[sheetName]!;
      return sheet.rows
          .map((row) => row.map((cell) => _cellText(cell?.value)).toList())
          .toList();
    } catch (_) {
      throw const InventoryImportException(
        'AVERA could not read this spreadsheet.',
      );
    }
  }

  String _cellText(CellValue? value) {
    if (value == null) return '';
    if (value is DateCellValue) {
      return _isoDate(value.asDateTimeLocal());
    }
    if (value is DateTimeCellValue) {
      return _isoDate(value.asDateTimeLocal());
    }
    return value.toString().trim();
  }

  InventoryImportDocument _document(
    String filename,
    List<List<String>> matrix,
  ) {
    final nonBlank = <({int sourceRow, List<String> values})>[];
    for (var i = 0; i < matrix.length; i++) {
      final row = matrix[i].map((value) => value.trim()).toList();
      if (row.any((value) => value.isNotEmpty)) {
        nonBlank.add((sourceRow: i + 1, values: row));
      }
    }
    if (nonBlank.length < 2) {
      throw const InventoryImportException(
        'The file must contain a header row and at least one product row.',
      );
    }
    final headers = nonBlank.first.values;
    if (headers.every((header) => header.isEmpty)) {
      throw const InventoryImportException('The file has no column headers.');
    }
    final dataRows = nonBlank.skip(1).toList();
    if (dataRows.length > inventoryImportMaxRows) {
      throw const InventoryImportException(
        'This file contains more than the maximum supported number of rows.',
      );
    }
    final rows = dataRows
        .map(
          (row) => InventoryImportRow(
            sourceRow: row.sourceRow,
            values: List.generate(
              headers.length,
              (index) => index < row.values.length ? row.values[index] : '',
            ),
          ),
        )
        .toList(growable: false);
    return InventoryImportDocument(
      filename: filename,
      headers: headers,
      rows: rows,
      mapping: autoMap(headers),
    );
  }

  List<InventoryColumnMapping> autoMap(List<String> headers) {
    final used = <InventoryImportField>{};
    return [
      for (var i = 0; i < headers.length; i++)
        () {
          final target = _fieldForHeader(headers[i]);
          final duplicate = target != null && !used.add(target);
          return InventoryColumnMapping(
            sourceIndex: i,
            header: headers[i].isEmpty ? 'Column ${i + 1}' : headers[i],
            target: duplicate ? null : target,
            confidence: duplicate
                ? InventoryMappingConfidence.ambiguous
                : target == null
                ? InventoryMappingConfidence.manual
                : InventoryMappingConfidence.high,
          );
        }(),
    ];
  }

  InventoryImportField? _fieldForHeader(String header) {
    final value = _normal(header);
    for (final entry in _aliases.entries) {
      if (entry.value.contains(value)) return entry.key;
    }
    return null;
  }

  InventoryImportValidationResult validate(
    InventoryImportDocument document, {
    Map<int, String> categoryOverrides = const {},
    Map<int, String> unitOverrides = const {},
  }) {
    final fieldIndexes = <InventoryImportField, int>{};
    for (final mapping in document.mapping) {
      if (mapping.target != null) {
        fieldIndexes[mapping.target!] = mapping.sourceIndex;
      }
    }
    final results = <InventoryRowValidation>[];
    for (final row in document.rows) {
      String cell(InventoryImportField field) {
        final index = fieldIndexes[field];
        return index == null || index >= row.values.length
            ? ''
            : row.values[index].trim();
      }

      final errors = <String>[];
      final warnings = <String>[];
      final name = cell(InventoryImportField.productName);
      if (name.isEmpty) errors.add('Product Name is required.');
      final rawCategory =
          categoryOverrides[row.sourceRow]?.trim().isNotEmpty == true
          ? categoryOverrides[row.sourceRow]!
          : cell(InventoryImportField.category);
      final category = InventoryCategories.byValue(rawCategory);
      if (category == null) {
        errors.add('Category not found - select manually.');
      }
      final rawUnit = unitOverrides[row.sourceRow]?.trim().isNotEmpty == true
          ? unitOverrides[row.sourceRow]!
          : cell(InventoryImportField.unit);
      final unit = resolveInventoryUnit(rawUnit);
      if (unit == null) errors.add('Unit not found - select manually.');
      final quantity = _integer(
        cell(InventoryImportField.quantity),
        'Quantity in Stock',
        errors,
        fallback: 0,
      );
      final selling = _number(
        cell(InventoryImportField.sellingPrice),
        'Selling Price',
        errors,
        fallback: 0,
      );
      final rawCost = cell(InventoryImportField.costPrice);
      final cost = rawCost.isEmpty
          ? null
          : _number(rawCost, 'Cost Price', errors);
      if (cost == null && rawCost.isEmpty) {
        warnings.add(
          'Cost Price is missing; Revenue & Profit will flag missing cost.',
        );
      }
      final expiry = _date(cell(InventoryImportField.expiryDate), errors);
      final batch = _blankToNull(cell(InventoryImportField.batchNumber));
      if (category != null &&
          (category.id == 'drugs' || category.id == 'vaccines')) {
        if (batch == null) {
          errors.add('Batch Number is required for this category.');
        }
        if (expiry == null) {
          errors.add('Expiry Date is required for this category.');
        }
      }
      final rawSubcategory = cell(InventoryImportField.subcategory);
      final subcategory = category == null || rawSubcategory.isEmpty
          ? null
          : InventoryCategories.resolveSubcategory(category.id, rawSubcategory);
      if (rawSubcategory.isNotEmpty && subcategory == null) {
        warnings.add('Subcategory was not matched and will be omitted.');
      }
      final candidate = errors.isNotEmpty || category == null || unit == null
          ? null
          : InventoryImportCandidate(
              sourceRow: row.sourceRow,
              name: name,
              categoryId: category.id,
              categoryName: category.name,
              subcategoryId: subcategory?.id,
              subcategoryName: subcategory?.name,
              quantity: quantity!,
              sellingPrice: selling!,
              costPrice: cost,
              baseUnitLabel: unit,
              brandName: _blankToNull(cell(InventoryImportField.brandName)),
              genericName: _blankToNull(cell(InventoryImportField.genericName)),
              manufacturer: _blankToNull(
                cell(InventoryImportField.manufacturer),
              ),
              sku: _blankToNull(cell(InventoryImportField.sku)),
              barcode: _blankToNull(cell(InventoryImportField.barcode)),
              packSize: _blankToNull(cell(InventoryImportField.packSize)),
              batchNumber: batch,
              expiryDate: expiry,
              storageConditions: _blankToNull(
                cell(InventoryImportField.storageConditions),
              ),
              dosageForm: _blankToNull(cell(InventoryImportField.dosageForm)),
            );
      results.add(
        InventoryRowValidation(
          sourceRow: row.sourceRow,
          candidate: candidate,
          errors: errors,
          warnings: warnings,
        ),
      );
    }
    return InventoryImportValidationResult(results);
  }

  List<InventoryDuplicateMatch> findDuplicates(
    Iterable<InventoryImportCandidate> candidates,
    Iterable<InventoryExistingProduct> existing,
  ) {
    final matches = <InventoryDuplicateMatch>[];
    for (final candidate in candidates) {
      InventoryExistingProduct? match;
      String? reason;
      final sku = _normal(candidate.sku ?? '');
      final barcode = _normal(candidate.barcode ?? '');
      for (final item in existing) {
        if (sku.isNotEmpty && sku == _normal(item.sku ?? '')) {
          match = item;
          reason = 'Exact SKU match';
          break;
        }
        if (barcode.isNotEmpty && barcode == _normal(item.barcode ?? '')) {
          match = item;
          reason = 'Exact barcode match';
          break;
        }
        if (_normal(candidate.name) == _normal(item.name) &&
            candidate.categoryId == item.categoryId) {
          match = item;
          reason = 'Same product name and category';
          break;
        }
      }
      if (match != null) {
        matches.add(
          InventoryDuplicateMatch(
            candidate: candidate,
            existing: match,
            reason: reason!,
          ),
        );
      }
    }
    return matches;
  }
}

const _aliases = <InventoryImportField, Set<String>>{
  InventoryImportField.productName: {
    'product',
    'product name',
    'item',
    'item name',
    'name',
  },
  InventoryImportField.category: {'category', 'product category', 'type'},
  InventoryImportField.subcategory: {'subcategory', 'sub category'},
  InventoryImportField.brandName: {'brand', 'brand name'},
  InventoryImportField.genericName: {'generic', 'generic name'},
  InventoryImportField.manufacturer: {'manufacturer', 'maker'},
  InventoryImportField.sku: {'sku', 'stock keeping unit'},
  InventoryImportField.barcode: {'barcode', 'bar code'},
  InventoryImportField.sellingPrice: {
    'selling price',
    'sale price',
    'retail price',
    'price',
  },
  InventoryImportField.costPrice: {
    'cost',
    'cost price',
    'purchase price',
    'buying price',
    'unit cost',
  },
  InventoryImportField.quantity: {
    'qty',
    'quantity',
    'quantity in stock',
    'stock',
    'stock qty',
  },
  InventoryImportField.unit: {'unit', 'base unit', 'uom', 'unit of measure'},
  InventoryImportField.packSize: {'pack size', 'packsize'},
  InventoryImportField.batchNumber: {
    'batch',
    'batch number',
    'lot',
    'lot number',
  },
  InventoryImportField.expiryDate: {
    'expiry',
    'expiry date',
    'expiration',
    'expiration date',
  },
  InventoryImportField.storageConditions: {'storage', 'storage conditions'},
  InventoryImportField.dosageForm: {
    'form',
    'product form',
    'presentation',
    'dosage form',
  },
};

const inventoryCanonicalUnits = <String>[
  'unit',
  'vial',
  'bottle',
  'box',
  'tablet',
  'capsule',
  'sachet',
  'ampoule',
  'ml',
  'litre',
  'kg',
  'g',
  'piece',
  'pack',
  'carton',
];

String? resolveInventoryUnit(String? raw) {
  final value = _normal(raw ?? '');
  if (value.isEmpty) return null;
  const aliases = <String, String>{
    'units': 'unit',
    'vials': 'vial',
    'bottles': 'bottle',
    'boxes': 'box',
    'tablets': 'tablet',
    'tab': 'tablet',
    'tabs': 'tablet',
    'capsules': 'capsule',
    'sachets': 'sachet',
    'ampoules': 'ampoule',
    'millilitre': 'ml',
    'milliliter': 'ml',
    'millilitres': 'ml',
    'milliliters': 'ml',
    'liter': 'litre',
    'liters': 'litre',
    'litres': 'litre',
    'kilogram': 'kg',
    'kilograms': 'kg',
    'gram': 'g',
    'grams': 'g',
    'pieces': 'piece',
    'pcs': 'piece',
    'packs': 'pack',
    'cartons': 'carton',
  };
  final canonical = aliases[value] ?? value;
  return inventoryCanonicalUnits.contains(canonical) ? canonical : null;
}

String _normal(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[_-]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

String? _blankToNull(String value) =>
    value.trim().isEmpty ? null : value.trim();

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

double? _number(
  String raw,
  String label,
  List<String> errors, {
  double? fallback,
}) {
  if (raw.trim().isEmpty) return fallback;
  final normalized = raw
      .replaceAll(',', '')
      .replaceAll(RegExp(r'[^0-9.\-]'), '');
  final value = double.tryParse(normalized);
  if (value == null || value < 0) {
    errors.add('$label must be a non-negative number.');
    return null;
  }
  return value;
}

int? _integer(String raw, String label, List<String> errors, {int? fallback}) {
  if (raw.trim().isEmpty) return fallback;
  final value = num.tryParse(raw.replaceAll(',', '').trim());
  if (value == null || value < 0 || value != value.roundToDouble()) {
    errors.add('$label must be a non-negative whole number.');
    return null;
  }
  return value.toInt();
}

DateTime? _date(String raw, List<String> errors) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final iso = DateTime.tryParse(value);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final match = RegExp(
    r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
  ).firstMatch(value);
  if (match != null) {
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year == year && parsed.month == month && parsed.day == day) {
      return parsed;
    }
  }
  errors.add('Expiry Date must use YYYY-MM-DD or DD/MM/YYYY.');
  return null;
}
