import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/models/animal_catalogue.dart';
import '../../../core/repositories/clinic_repository.dart';

class FarmReportService {
  const FarmReportService();

  Future<Uint8List> buildDailyRecordPdf({
    required FarmDailyRecordDetail detail,
    required String preparedBy,
    String? clinicName,
  }) async {
    final document = pw.Document();
    final record = detail.record;
    final generatedAt = DateTime.now();
    final movementRows = detail.speciesMovements.isEmpty
        ? [
            [
              'Legacy combined population',
              '${record.openingPopulation}',
              '${record.births + record.purchases + record.transfersIn}',
              '${record.mortality}',
              '${record.sales + record.transfersOut}',
              '${record.closingPopulation}',
            ],
          ]
        : [
            for (final movement in detail.speciesMovements)
              [
                _speciesName(movement.speciesId),
                '${movement.openingPopulation}',
                '${movement.births + movement.purchases + movement.transfersIn}',
                '${movement.mortality}',
                '${movement.sales + movement.transfersOut}',
                '${movement.closingPopulation}',
              ],
          ];
    final unitRows = [
      for (final unit in detail.units)
        [
          unit.name,
          _speciesName(unit.speciesId),
          _breedName(unit.breedId),
          '${unit.maleCount}',
          '${unit.femaleCount}',
          '${unit.unknownCount}',
          '${unit.maleCount + unit.femaleCount + unit.unknownCount}',
        ],
    ];
    final speciesMortality = detail.speciesMovements
        .where((movement) => movement.mortality > 0)
        .toList();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 40),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (clinicName?.trim().isNotEmpty == true)
              pw.Text(
                clinicName!,
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            pw.Text(
              detail.farm.name,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            if (detail.farm.location?.trim().isNotEmpty == true)
              pw.Text(detail.farm.location!),
            pw.SizedBox(height: 4),
            pw.Text(
              'Daily Farm Record - ${DateFormat.yMMMMd().format(record.recordDate)}',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey800,
              ),
            ),
            pw.SizedBox(height: 14),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Prepared by $preparedBy - ${DateFormat.yMMMd().add_jm().format(generatedAt)}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        build: (_) => [
          _sectionTitle('Population by species'),
          _table([
            'Species',
            'Opening',
            'Additions',
            'Deaths',
            'Removals',
            'Closing',
          ], movementRows),
          pw.SizedBox(height: 16),
          _sectionTitle('Farm units'),
          if (unitRows.isEmpty)
            pw.Text('No unit records were attached to this farm.')
          else
            _table([
              'Unit',
              'Species',
              'Breed',
              'Male',
              'Female',
              'Unknown',
              'Total',
            ], unitRows),
          pw.SizedBox(height: 16),
          _sectionTitle('Feed'),
          if (detail.feedRecords.isEmpty)
            pw.Text(
              '${record.feedSuppliedKg.toStringAsFixed(1)} kg total feed supplied.',
            )
          else
            _table(
              ['Feed', 'Mixed kg', 'Supplied kg', 'Remaining kg', 'Notes'],
              [
                for (final feed in detail.feedRecords)
                  [
                    feed.rationName,
                    feed.totalMixedKg.toStringAsFixed(1),
                    feed.totalSuppliedKg.toStringAsFixed(1),
                    feed.remainingKg.toStringAsFixed(1),
                    feed.notes ?? '-',
                  ],
              ],
            ),
          pw.SizedBox(height: 16),
          _sectionTitle('Mortality'),
          if (detail.mortalityRecords.isEmpty && speciesMortality.isEmpty)
            pw.Text(
              record.mortality == 0
                  ? 'No mortality recorded.'
                  : '${record.mortality} mortality recorded in the legacy combined total.',
            )
          else if (detail.mortalityRecords.isEmpty)
            _table(
              ['Species', 'Number', 'Cause', 'Notes'],
              [
                for (final movement in speciesMortality)
                  [
                    _speciesName(movement.speciesId),
                    '${movement.mortality}',
                    'Not recorded',
                    '-',
                  ],
              ],
            )
          else
            _table(
              ['Species', 'Number', 'Cause', 'Notes'],
              [
                for (final item in detail.mortalityRecords)
                  [
                    _speciesName(item.speciesId),
                    '${item.numberDead}',
                    item.suspectedCause,
                    item.notes ?? '-',
                  ],
              ],
            ),
          pw.SizedBox(height: 16),
          _sectionTitle('Reproduction'),
          if (detail.reproductionRecords.isEmpty)
            pw.Text('No reproductive events recorded.')
          else
            _table(
              ['Animal', 'Species', 'Live births', 'Stillbirths', 'Notes'],
              [
                for (final item in detail.reproductionRecords)
                  [
                    item.animalIdentifier,
                    _speciesName(item.speciesId),
                    '${item.bornAlive}',
                    '${item.stillborn}',
                    item.notes ?? '-',
                  ],
              ],
            ),
          pw.SizedBox(height: 16),
          _sectionTitle('Health and management events'),
          if (detail.healthRecords.isEmpty && detail.events.isEmpty)
            pw.Text('No health or management events recorded.')
          else ...[
            if (detail.healthRecords.isNotEmpty)
              _table(
                ['Event', 'Product', 'Purpose', 'Dose', 'Notes'],
                [
                  for (final item in detail.healthRecords)
                    [
                      item.eventType,
                      item.product ?? '-',
                      item.purpose ?? '-',
                      item.dose ?? '-',
                      item.notes ?? '-',
                    ],
                ],
              ),
            if (detail.events.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              _table(
                ['Event', 'Description', 'Time'],
                [
                  for (final item in detail.events)
                    [
                      item.eventType,
                      item.description ?? '-',
                      DateFormat.yMMMd().add_jm().format(item.occurredAt),
                    ],
                ],
              ),
            ],
          ],
          pw.SizedBox(height: 16),
          _sectionTitle('Daily notes'),
          pw.Text(record.dailyNote ?? 'No daily note recorded.'),
          if (record.tasksForTomorrow?.trim().isNotEmpty == true) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Tasks for tomorrow',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(record.tasksForTomorrow!),
          ],
          if (record.correctionReason?.trim().isNotEmpty == true) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.amber50,
                border: pw.Border.all(color: PdfColors.amber700),
              ),
              child: pw.Text('Correction reason: ${record.correctionReason}'),
            ),
          ],
          pw.SizedBox(height: 28),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Divider()),
              pw.SizedBox(width: 24),
              pw.Expanded(child: pw.Divider()),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [pw.Text('Prepared by'), pw.Text('Signature / date')],
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<String> saveDailyRecordPdf({
    required FarmDailyRecordDetail detail,
    required String preparedBy,
    String? clinicName,
  }) async {
    final bytes = await buildDailyRecordPdf(
      detail: detail,
      preparedBy: preparedBy,
      clinicName: clinicName,
    );
    final directory =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final safeFarm = detail.farm.name
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final file = File(
      p.join(
        directory.path,
        '$safeFarm-daily-${DateFormat('yyyy-MM-dd').format(detail.record.recordDate)}.pdf',
      ),
    );
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> printDailyRecord({
    required FarmDailyRecordDetail detail,
    required String preparedBy,
    String? clinicName,
  }) {
    return Printing.layoutPdf(
      name: '${detail.farm.name} Daily Farm Record',
      onLayout: (_) => buildDailyRecordPdf(
        detail: detail,
        preparedBy: preparedBy,
        clinicName: clinicName,
      ),
    );
  }

  Future<void> shareDailyRecord({
    required FarmDailyRecordDetail detail,
    required String preparedBy,
    String? clinicName,
  }) async {
    final bytes = await buildDailyRecordPdf(
      detail: detail,
      preparedBy: preparedBy,
      clinicName: clinicName,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'farm-daily-${DateFormat('yyyy-MM-dd').format(detail.record.recordDate)}.pdf',
    );
  }

  static pw.Widget _sectionTitle(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      value,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _table(List<String> headers, List<List<String>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
      border: pw.TableBorder.all(color: PdfColors.blueGrey300, width: .5),
      cellPadding: const pw.EdgeInsets.all(5),
      cellAlignment: pw.Alignment.topLeft,
    );
  }

  static String _speciesName(String? id) =>
      AnimalCatalogue.speciesById(id)?.displayName ?? (id ?? 'Not assigned');

  static String _breedName(String? id) {
    if (id == null) return '-';
    for (final breed in AnimalCatalogue.breeds) {
      if (breed.id == id) return breed.displayName;
    }
    return id;
  }
}
