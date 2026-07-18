import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/config/app_providers.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ReportTile(
            icon: Iconsax.document_download,
            title: 'Daily Consultations',
            subtitle: 'PDF summary of today’s visits',
            onTap: () => _dailyConsultationPdf(context, ref),
          ),
          _ReportTile(
            icon: Iconsax.chart,
            title: 'Inventory Value',
            subtitle: 'CSV export with stock value and expiry status',
            onTap: () => _inventoryCsv(context, ref),
          ),
          _ReportTile(
            icon: Iconsax.document,
            title: 'Vaccination Report',
            subtitle: 'Excel workbook of due and completed vaccinations',
            onTap: () => _vaccinationExcel(context, ref),
          ),
        ],
      ),
    );
  }

  Future<Directory> _targetDir() async {
    return await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  }

  Future<void> _dailyConsultationPdf(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final visits = (await db.select(db.visits).get())
        .where((visit) => !visit.visitDate.isBefore(startOfDay))
        .toList()
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Daily Consultations', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.Text(DateFormat.yMMMd().format(now)),
            pw.SizedBox(height: 12),
            for (final visit in visits)
              pw.Text('${visit.visitDate}: ${visit.chiefComplaint ?? '-'} • ${visit.diagnosis ?? '-'}'),
          ],
        ),
      ),
    );
    final file = File(p.join((await _targetDir()).path, 'zevora_daily_consultations.pdf'));
    await file.writeAsBytes(await doc.save());
    if (context.mounted) _done(context, file.path);
  }

  Future<void> _inventoryCsv(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final items = await db.select(db.inventoryItems).get();
    final rows = [
      ['Item', 'Category', 'Quantity', 'Minimum', 'Buying Price', 'Selling Price', 'Expiry', 'Value'],
      for (final item in items)
        [
          item.drugName,
          item.category,
          item.quantity,
          item.minimumQuantity,
          item.buyingPrice,
          item.sellingPrice,
          item.expiryDate?.toIso8601String() ?? '',
          item.quantity * item.sellingPrice,
        ],
    ];
    final file = File(p.join((await _targetDir()).path, 'zevora_inventory_value.csv'));
    await file.writeAsString(const ListToCsvConverter().convert(rows));
    if (context.mounted) _done(context, file.path);
  }

  Future<void> _vaccinationExcel(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final vaccinations = await db.select(db.vaccinations).get();
    final excel = Excel.createExcel();
    final sheet = excel['Vaccinations'];
    sheet.appendRow([
      TextCellValue('Vaccine'),
      TextCellValue('Batch'),
      TextCellValue('Date Given'),
      TextCellValue('Next Due'),
      TextCellValue('Administered By'),
    ]);
    for (final vaccine in vaccinations) {
      sheet.appendRow([
        TextCellValue(vaccine.vaccine),
        TextCellValue(vaccine.batchNumber ?? ''),
        TextCellValue(vaccine.dateGiven.toIso8601String()),
        TextCellValue(vaccine.nextDueDate?.toIso8601String() ?? ''),
        TextCellValue(vaccine.administeredBy ?? ''),
      ]);
    }
    final file = File(p.join((await _targetDir()).path, 'zevora_vaccinations.xlsx'));
    await file.writeAsBytes(excel.encode() ?? []);
    if (context.mounted) _done(context, file.path);
  }

  void _done(BuildContext context, String path) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $path')));
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Iconsax.arrow_right_3),
        onTap: onTap,
      ),
    );
  }
}
