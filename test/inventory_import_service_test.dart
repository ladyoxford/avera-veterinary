import 'dart:convert';
import 'dart:typed_data';

import 'package:avera/features/reports/services/inventory_import_service.dart';
import 'package:avera/features/reports/services/inventory_export_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = InventoryImportParser();

  group('inventory import parser', () {
    test('parses CSV, ignores blank rows and maps common aliases', () {
      final document = parser.parse(
        filename: 'stock.csv',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Item,Product Category,Sale Price,Buying Price,Stock Qty,UOM\n'
            'Stethoscope,Medical Equipment,12000,7000,3,pieces\n'
            ',,,,,\n',
          ),
        ),
      );

      expect(document.rows, hasLength(1));
      expect(document.rows.single.sourceRow, 2);
      expect(
        document.mapping.map((item) => item.target),
        containsAll(<InventoryImportField>[
          InventoryImportField.productName,
          InventoryImportField.category,
          InventoryImportField.sellingPrice,
          InventoryImportField.costPrice,
          InventoryImportField.quantity,
          InventoryImportField.unit,
        ]),
      );
      final result = parser.validate(document);
      expect(result.invalidCount, 0);
      expect(result.validRows.single.candidate!.baseUnitLabel, 'piece');
      expect(
        result.validRows.single.candidate!.categoryId,
        'medical_equipment',
      );
    });

    test('parses XLSX native dates and standard headers', () {
      final workbook = Excel.createExcel();
      final sheet = workbook['Stock'];
      sheet.appendRow(
        [
          'Product Name',
          'Category',
          'Selling Price',
          'Cost Price',
          'Quantity',
          'Unit',
          'Batch',
          'Expiry Date',
        ].map(TextCellValue.new).toList(),
      );
      sheet.appendRow([
        TextCellValue('Rabies Vaccine'),
        TextCellValue('Vaccines'),
        const DoubleCellValue(2500),
        const DoubleCellValue(1500),
        const IntCellValue(10),
        TextCellValue('vials'),
        TextCellValue('RV-1'),
        DateCellValue.fromDateTime(DateTime(2027, 5, 3)),
      ]);
      final document = parser.parse(
        filename: 'stock.xlsx',
        bytes: Uint8List.fromList(workbook.encode()!),
      );
      final result = parser.validate(document);

      expect(result.invalidCount, 0);
      expect(
        result.validRows.single.candidate!.expiryDate,
        DateTime(2027, 5, 3),
      );
      expect(result.validRows.single.candidate!.baseUnitLabel, 'vial');
    });

    test('rejects empty, malformed, oversized and over-row-limit files', () {
      expect(
        () => parser.parse(filename: 'empty.csv', bytes: Uint8List(0)),
        throwsA(isA<InventoryImportException>()),
      );
      expect(
        () => parser.parse(
          filename: 'bad.xlsx',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<InventoryImportException>()),
      );
      expect(
        () => parser.parse(
          filename: 'large.csv',
          bytes: Uint8List(inventoryImportMaxBytes + 1),
        ),
        throwsA(
          isA<InventoryImportException>().having(
            (error) => error.message,
            'message',
            contains('larger'),
          ),
        ),
      );
      final rows = List.generate(
        inventoryImportMaxRows + 1,
        (index) => 'Item $index,Accessories,1,1,1,unit',
      );
      expect(
        () => parser.parse(
          filename: 'rows.csv',
          bytes: Uint8List.fromList(
            utf8.encode(
              'Product,Category,Selling Price,Cost,Qty,Unit\n${rows.join('\n')}',
            ),
          ),
        ),
        throwsA(
          isA<InventoryImportException>().having(
            (error) => error.message,
            'message',
            contains('maximum supported'),
          ),
        ),
      );
    });
  });

  group('mapping and validation', () {
    test(
      'duplicate target mapping is ambiguous and manual override resolves it',
      () {
        final document = parser.parse(
          filename: 'stock.csv',
          bytes: Uint8List.fromList(
            utf8.encode(
              'Product,Item,Category,Selling Price,Cost,Qty,Unit\n'
              'Collar,,Accessories,1000,500,2,pcs',
            ),
          ),
        );
        expect(
          document.mapping.where(
            (item) => item.confidence == InventoryMappingConfidence.ambiguous,
          ),
          hasLength(1),
        );
        final mappings = [...document.mapping];
        final ambiguous = mappings.indexWhere(
          (item) => item.confidence == InventoryMappingConfidence.ambiguous,
        );
        mappings[ambiguous] = mappings[ambiguous].copyWith(
          target: InventoryImportField.brandName,
          confidence: InventoryMappingConfidence.manual,
        );
        expect(parser.validate(document.withMapping(mappings)).invalidCount, 0);
      },
    );

    test('unknown category and unit require manual resolution', () {
      final document = parser.parse(
        filename: 'stock.csv',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Product,Category,Selling Price,Cost,Qty,Unit\n'
            'Monitor,Unlisted Thing,25000,15000,1,cratelet',
          ),
        ),
      );
      expect(parser.validate(document).invalidCount, 1);
      final resolved = parser.validate(
        document,
        categoryOverrides: const {2: 'medical_equipment'},
        unitOverrides: const {2: 'piece'},
      );
      expect(resolved.invalidCount, 0);
    });

    test('bad numbers and missing name fail while missing cost only warns', () {
      final bad = parser.parse(
        filename: 'bad.csv',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Product,Category,Selling Price,Cost,Qty,Unit\n'
            ',Accessories,wrong,-3,1.5,unit',
          ),
        ),
      );
      expect(parser.validate(bad).rows.single.errors, hasLength(4));

      final missingCost = parser.parse(
        filename: 'missing.csv',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Product,Category,Selling Price,Cost,Qty,Unit\n'
            'Lead,Accessories,2000,,2,unit',
          ),
        ),
      );
      final result = parser.validate(missingCost);
      expect(result.invalidCount, 0);
      expect(result.missingCostCount, 1);
      expect(
        result.validRows.single.warnings.single,
        contains('Revenue & Profit'),
      );
    });

    test('parses ISO and day/month expiry and rejects unsafe dates', () {
      for (final date in ['2027-12-31', '31/12/2027']) {
        final doc = _drugCsv(date);
        expect(parser.validate(doc).invalidCount, 0);
      }
      expect(parser.validate(_drugCsv('12/31/2027')).invalidCount, 1);
    });
  });

  group('unit and duplicate resolution', () {
    test('normalizes unit aliases and rejects unknown units', () {
      expect(resolveInventoryUnit(' VIALS '), 'vial');
      expect(resolveInventoryUnit('tabs'), 'tablet');
      expect(resolveInventoryUnit('liters'), 'litre');
      expect(resolveInventoryUnit('pcs'), 'piece');
      expect(resolveInventoryUnit('bucket'), isNull);
    });

    test('uses SKU, barcode, then name/category and defaults to skip', () {
      const candidates = [
        InventoryImportCandidate(
          sourceRow: 2,
          name: 'New label',
          categoryId: 'pet_accessories',
          categoryName: 'Pet Accessories',
          quantity: 1,
          sellingPrice: 100,
          costPrice: 50,
          baseUnitLabel: 'unit',
          sku: 'SKU-1',
        ),
        InventoryImportCandidate(
          sourceRow: 3,
          name: 'Dog Collar',
          categoryId: 'pet_accessories',
          categoryName: 'Pet Accessories',
          quantity: 1,
          sellingPrice: 100,
          costPrice: 50,
          baseUnitLabel: 'unit',
        ),
      ];
      const existing = [
        InventoryExistingProduct(
          id: 7,
          name: 'Old label',
          categoryId: 'pet_accessories',
          sku: 'sku-1',
        ),
        InventoryExistingProduct(
          id: 8,
          name: ' dog collar ',
          categoryId: 'pet_accessories',
        ),
      ];
      final matches = parser.findDuplicates(candidates, existing);
      expect(matches, hasLength(2));
      expect(matches.first.reason, 'Exact SKU match');
      expect(
        matches.every((match) => match.action == InventoryDuplicateAction.skip),
        isTrue,
      );
      expect(
        matches.first
            .withAction(InventoryDuplicateAction.updateExisting)
            .action,
        InventoryDuplicateAction.updateExisting,
      );
      expect(
        matches.last.withAction(InventoryDuplicateAction.importAsNew).action,
        InventoryDuplicateAction.importAsNew,
      );
    });

    test('exported XLSX round trip defaults all seven products to skip', () {
      const export = InventoryExportService();
      const records = [
        InventoryExportRecord(
          name: 'Biocan R',
          category: 'Clinical Consumables',
          quantity: 3,
          sellingPrice: 5000,
          costPrice: 2500,
          baseUnit: 'piece',
          status: 'Active',
          sku: 'VAC-001',
          batchNumber: 'B1',
          expiryDate: null,
        ),
        InventoryExportRecord(
          name: 'Digital Scale',
          category: 'Medical Equipment & Instruments',
          quantity: 1,
          sellingPrice: 90000,
          costPrice: 70000,
          baseUnit: 'piece',
          status: 'Active',
          barcode: '123456789',
        ),
        InventoryExportRecord(
          name: ' Dog   Collar ',
          category: 'Pet Accessories & Retail',
          quantity: 4,
          sellingPrice: 2500,
          costPrice: 1000,
          baseUnit: 'piece',
          status: 'Active',
        ),
        InventoryExportRecord(
          name: 'Donated Gloves',
          category: 'Medical Equipment & Instruments',
          quantity: 20,
          sellingPrice: 100,
          costPrice: 0,
          baseUnit: 'piece',
          status: 'Active',
        ),
        InventoryExportRecord(
          name: 'Unknown Cost Syringe',
          category: 'Medical Equipment & Instruments',
          quantity: 10,
          sellingPrice: 300,
          costPrice: null,
          baseUnit: 'piece',
          status: 'Active',
        ),
        InventoryExportRecord(
          name: 'Office Paper',
          category: 'Office & Administrative Supplies',
          quantity: 6,
          sellingPrice: 1500,
          costPrice: 900,
          baseUnit: 'pack',
          status: 'Active',
          sku: 'OFF-1',
        ),
        InventoryExportRecord(
          name: 'Feed Scoop',
          category: 'Farm & Livestock Supplies',
          quantity: 2,
          sellingPrice: 3500,
          costPrice: 1800,
          baseUnit: 'piece',
          status: 'Active',
          barcode: 'SCOOP-7',
        ),
      ];
      final document = parser.parse(
        filename: 'inventory.xlsx',
        bytes: export.excelBytes(records),
      );
      final validation = parser.validate(document);
      expect(validation.validRows, hasLength(7));
      final existing = records
          .map(
            (item) => InventoryExistingProduct(
              id: item.name,
              name: item.name.trim(),
              categoryId: item.category,
              sku: item.sku,
              barcode: item.barcode,
            ),
          )
          .toList();
      final duplicates = parser.findDuplicates(
        validation.validRows.map((row) => row.candidate!),
        existing,
      );
      expect(existing, hasLength(7));
      expect(duplicates, hasLength(7));
      expect(
        duplicates.where(
          (item) => item.action == InventoryDuplicateAction.skip,
        ),
        hasLength(7),
      );
      expect(validation.validRows.length - duplicates.length, 0);
      expect(existing.length, 7);
      final costs = validation.validRows.map((row) => row.candidate!.costPrice);
      expect(costs, contains(null));
      expect(costs, contains(0));
    });
  });
}

InventoryImportDocument _drugCsv(String expiry) =>
    const InventoryImportParser().parse(
      filename: 'drug.csv',
      bytes: Uint8List.fromList(
        utf8.encode(
          'Product,Category,Selling Price,Cost,Qty,Unit,Batch,Expiry\n'
          'Amoxicillin,Medicines & Drugs,1000,500,3,tablets,B-1,$expiry',
        ),
      ),
    );
