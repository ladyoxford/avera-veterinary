import 'package:avera/features/reports/services/inventory_export_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = InventoryExportService();
  const records = [
    InventoryExportRecord(
      name: 'Infusion Pump',
      category: 'Medical Equipment',
      subcategory: 'Monitoring Equipment',
      quantity: 2,
      sellingPrice: 150000,
      costPrice: 100000,
      baseUnit: 'piece',
      status: 'Active',
      sku: 'PUMP-01',
      batchNumber: 'B-22',
    ),
  ];

  test('inventory Excel contains canonical values and no secret fields', () {
    final bytes = service.excelBytes(records);
    final workbook = Excel.decodeBytes(bytes);
    final rows = workbook.tables['Inventory']!.rows;
    expect(rows, hasLength(2));
    final header = rows.first.map((cell) => cell?.value.toString()).toList();
    final value = rows.last.map((cell) => cell?.value.toString()).toList();
    expect(
      header,
      containsAll(['Product Name', 'Cost Price', 'Quantity in Stock']),
    );
    expect(
      value,
      containsAll(['Infusion Pump', 'Medical Equipment', 'PUMP-01']),
    );
    expect(header.join(' '), isNot(contains('password')));
    expect(header.join(' '), isNot(contains('token')));
  });

  test('inventory PDF is a real document and filename is readable', () async {
    final bytes = await service.pdfBytes(records, clinicName: 'AVERA Clinic');
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(
      service.filename(
        clinicName: 'Chinonso / Hospital',
        extension: 'xlsx',
        date: DateTime(2026, 8, 31),
      ),
      'AVERA_Chinonso_Hospital_Inventory_2026-08-31.xlsx',
    );
  });

  test('export preserves missing cost, known zero cost, and product names', () {
    const values = [
      InventoryExportRecord(
        name: 'Missing Cost Product',
        category: 'Medical Equipment',
        quantity: 1,
        sellingPrice: 500,
        costPrice: null,
        baseUnit: 'piece',
        status: 'Active',
      ),
      InventoryExportRecord(
        name: 'Donated Product',
        category: 'Medical Equipment',
        quantity: 2,
        sellingPrice: 500,
        costPrice: 0,
        baseUnit: 'piece',
        status: 'Active',
      ),
    ];

    final excelRows = service.rows(values);
    final pdfRows = service.pdfRows(values);

    expect(excelRows[0], containsAll(['Missing Cost Product', '']));
    expect(excelRows[1], containsAll(['Donated Product', '0.00']));
    expect(pdfRows[0], containsAll(['Missing Cost Product', 'Missing']));
    expect(pdfRows[1], containsAll(['Donated Product', '0.00']));
  });
}
