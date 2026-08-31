import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InventoryExportRecord {
  const InventoryExportRecord({
    required this.name,
    required this.category,
    required this.quantity,
    required this.sellingPrice,
    required this.costPrice,
    required this.baseUnit,
    required this.status,
    this.subcategory,
    this.brand,
    this.genericName,
    this.manufacturer,
    this.sku,
    this.barcode,
    this.packSize,
    this.batchNumber,
    this.expiryDate,
    this.storageConditions,
  });

  final String name;
  final String category;
  final String? subcategory;
  final String? brand;
  final String? genericName;
  final String? manufacturer;
  final String? sku;
  final String? barcode;
  final double sellingPrice;
  final double? costPrice;
  final int quantity;
  final String baseUnit;
  final String? packSize;
  final String? batchNumber;
  final DateTime? expiryDate;
  final String? storageConditions;
  final String status;
}

class InventoryExportFilter {
  const InventoryExportFilter({this.search = '', this.categoryId});
  final String search;
  final String? categoryId;
}

class InventoryExportService {
  const InventoryExportService();

  static const headers = <String>[
    'Product Name',
    'Category',
    'Subcategory',
    'Brand',
    'Generic Name',
    'Manufacturer',
    'SKU',
    'Barcode',
    'Selling Price',
    'Cost Price',
    'Quantity in Stock',
    'Base Unit',
    'Pack Size',
    'Batch Number',
    'Expiry Date',
    'Storage Conditions',
    'Status',
  ];

  List<List<String>> rows(Iterable<InventoryExportRecord> records) => records
      .map(
        (item) => <String>[
          item.name,
          item.category,
          item.subcategory ?? '',
          item.brand ?? '',
          item.genericName ?? '',
          item.manufacturer ?? '',
          item.sku ?? '',
          item.barcode ?? '',
          item.sellingPrice.toStringAsFixed(2),
          item.costPrice?.toStringAsFixed(2) ?? '',
          '${item.quantity}',
          item.baseUnit,
          item.packSize ?? '',
          item.batchNumber ?? '',
          item.expiryDate == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(item.expiryDate!),
          item.storageConditions ?? '',
          item.status,
        ],
      )
      .toList(growable: false);

  Uint8List excelBytes(Iterable<InventoryExportRecord> records) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Inventory'];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in rows(records)) {
      sheet.appendRow(row.map(TextCellValue.new).toList());
    }
    if (workbook.sheets.containsKey('Sheet1')) workbook.delete('Sheet1');
    return Uint8List.fromList(workbook.encode() ?? const []);
  }

  Future<Uint8List> pdfBytes(
    Iterable<InventoryExportRecord> records, {
    required String clinicName,
  }) async {
    final document = pw.Document();
    final values = rows(records);
    final compactHeaders = <String>[
      'Product',
      'Category',
      'Qty',
      'Unit',
      'Cost',
      'Selling',
      'Batch',
      'Expiry',
      'Status',
    ];
    final compactRows = records
        .map(
          (item) => <String>[
            item.name,
            item.category,
            '${item.quantity}',
            item.baseUnit,
            item.costPrice?.toStringAsFixed(2) ?? 'Missing',
            item.sellingPrice.toStringAsFixed(2),
            item.batchNumber ?? '-',
            item.expiryDate == null
                ? '-'
                : DateFormat('yyyy-MM-dd').format(item.expiryDate!),
            item.status,
          ],
        )
        .toList(growable: false);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'AVERA Inventory Export',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(clinicName),
            pw.Text(
              'Generated ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => [
          pw.Text('${values.length} inventory record(s)'),
          pw.SizedBox(height: 10),
          if (compactRows.isEmpty)
            pw.Text('No inventory records matched this export scope.')
          else
            pw.TableHelper.fromTextArray(
              headers: compactHeaders,
              data: compactRows,
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey100,
              ),
              cellPadding: const pw.EdgeInsets.all(4),
            ),
        ],
      ),
    );
    return document.save();
  }

  String filename({
    required String clinicName,
    required String extension,
    DateTime? date,
  }) {
    final safeClinic = clinicName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final stamp = DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());
    return 'AVERA_${safeClinic.isEmpty ? 'Clinic' : safeClinic}_Inventory_$stamp.$extension';
  }
}
