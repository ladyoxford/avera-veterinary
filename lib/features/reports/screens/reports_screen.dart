import 'dart:io';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

enum ClinicReportType {
  dailyConsultations('daily-consultations'),
  inventoryValue('inventory-value'),
  vaccination('vaccination');

  const ClinicReportType(this.routeKey);
  final String routeKey;

  static ClinicReportType? fromRoute(String? value) {
    for (final type in values) {
      if (type.routeKey == value) return type;
    }
    return null;
  }
}

enum ReportDatePreset {
  today('Today'),
  yesterday('Yesterday'),
  last7Days('Last 7 Days'),
  last30Days('Last 30 Days'),
  custom('Custom');

  const ReportDatePreset(this.label);
  final String label;
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const reports = [
      (
        type: ClinicReportType.dailyConsultations,
        icon: Icons.medical_information_outlined,
        title: 'Daily Consultations',
        subtitle:
            'Review clinical encounters by date, patient and veterinarian.',
      ),
      (
        type: ClinicReportType.inventoryValue,
        icon: Icons.inventory_2_outlined,
        title: 'Inventory Value',
        subtitle:
            'Inspect cost, retail value, stock level, batch and expiry status.',
      ),
      (
        type: ClinicReportType.vaccination,
        icon: Icons.vaccines_outlined,
        title: 'Vaccination Report',
        subtitle: 'Track administered, upcoming, due and overdue vaccinations.',
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        itemCount: reports.length + 1,
        separatorBuilder: (_, index) => SizedBox(
          height: index == 0
              ? AveraSpacing.subtitleToContentGap
              : AveraSpacing.cardGap,
        ),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              'Generate reports from this clinic\'s saved records.',
              style: averaText(context).pageSubtitle,
            );
          }
          final report = reports[index - 1];
          return AveraAdministrationCard(
            icon: report.icon,
            title: report.title,
            subtitle: report.subtitle,
            onTap: () => context.push('/reports/${report.type.routeKey}'),
          );
        },
      ),
    );
  }
}

class ReportDetailScreen extends ConsumerStatefulWidget {
  const ReportDetailScreen({super.key, required this.type});
  final ClinicReportType type;

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  ReportDatePreset _preset = ReportDatePreset.today;
  late DateTimeRange _range = _rangeForPreset(_preset);
  String _vaccinationFilter = 'All';
  bool _exporting = false;

  String get _title => switch (widget.type) {
    ClinicReportType.dailyConsultations => 'Daily Consultations',
    ClinicReportType.inventoryValue => 'Inventory Value',
    ClinicReportType.vaccination => 'Vaccination Report',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: FutureBuilder<_ReportData>(
        future: _load(),
        builder: (context, snapshot) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              Text(_subtitle, style: averaText(context).pageSubtitle),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              if (widget.type != ClinicReportType.inventoryValue)
                _DateFilter(
                  preset: _preset,
                  range: _range,
                  onChanged: _setPreset,
                  onCustomRange: _selectCustomRange,
                ),
              if (widget.type == ClinicReportType.vaccination) ...[
                const SizedBox(height: AveraSpacing.cardGap),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'All', label: Text('All')),
                      ButtonSegment(value: 'Due', label: Text('Due')),
                      ButtonSegment(value: 'Upcoming', label: Text('Upcoming')),
                      ButtonSegment(value: 'Overdue', label: Text('Overdue')),
                      ButtonSegment(
                        value: 'Completed',
                        label: Text('Completed'),
                      ),
                    ],
                    selected: {_vaccinationFilter},
                    onSelectionChanged: (values) =>
                        setState(() => _vaccinationFilter = values.first),
                  ),
                ),
              ],
              const SizedBox(height: AveraSpacing.cardGap),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                AveraSurfaceCard(
                  child: Column(
                    children: [
                      Text(
                        'This report could not be loaded.',
                        style: averaText(context).listItemTitle,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              else
                _ReportPreview(data: snapshot.data!),
              const SizedBox(height: AveraSpacing.sectionGap),
              if (snapshot.hasData)
                _ExportActions(
                  type: widget.type,
                  exporting: _exporting,
                  onPdf: () => _exportPdf(snapshot.data!, share: false),
                  onPrint: () => _print(snapshot.data!),
                  onShare: () => _exportPdf(snapshot.data!, share: true),
                  onCsv: widget.type == ClinicReportType.inventoryValue
                      ? () => _exportCsv(snapshot.data!)
                      : null,
                  onExcel: widget.type != ClinicReportType.dailyConsultations
                      ? () => _exportExcel(snapshot.data!)
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }

  String get _subtitle => switch (widget.type) {
    ClinicReportType.dailyConsultations =>
      'Patient, owner and consultation activity for the selected date range.',
    ClinicReportType.inventoryValue =>
      'Current clinic inventory values and stock conditions.',
    ClinicReportType.vaccination =>
      'Vaccination history and due-date status for this clinic.',
  };

  Future<_ReportData> _load() async {
    final session = await ref.read(userSessionProvider.future);
    final db = ref.read(databaseProvider);
    final clinicId = session.clinic.clinicId;
    final animals = await (db.select(
      db.animals,
    )..where((row) => row.clinicId.equals(clinicId))).get();
    final owners = await (db.select(
      db.owners,
    )..where((row) => row.clinicId.equals(clinicId))).get();
    final animalById = {for (final item in animals) item.id: item};
    final ownerById = {for (final item in owners) item.id: item};
    final rows = <List<String>>[];
    final headers = <String>[];

    switch (widget.type) {
      case ClinicReportType.dailyConsultations:
        headers.addAll([
          'Date',
          'Patient',
          'Hospital No.',
          'Owner',
          'Veterinarian',
          'Complaint',
          'Diagnosis',
          'Treatment',
          'Status',
        ]);
        final visits =
            await (db.select(db.visits)
                  ..where(
                    (row) =>
                        row.clinicId.equals(clinicId) &
                        row.visitDate.isBiggerOrEqualValue(_range.start) &
                        row.visitDate.isSmallerThanValue(
                          _range.end.add(const Duration(days: 1)),
                        ),
                  )
                  ..orderBy([(row) => OrderingTerm.desc(row.visitDate)]))
                .get();
        for (final visit in visits) {
          final animal = animalById[visit.animalId];
          final owner = animal == null ? null : ownerById[animal.ownerId];
          rows.add([
            DateFormat.yMMMd().add_jm().format(visit.visitDate),
            animal?.animalName ?? 'Patient unavailable',
            animal?.hospitalNumber ?? '-',
            owner?.fullName ?? '-',
            visit.veterinarian ?? '-',
            visit.chiefComplaint ?? '-',
            visit.diagnosis ?? '-',
            visit.treatment ?? '-',
            visit.status,
          ]);
        }
      case ClinicReportType.inventoryValue:
        headers.addAll([
          'Product',
          'Category',
          'Quantity',
          'Unit Cost',
          'Selling Price',
          'Cost Value',
          'Retail Value',
          'Stock',
          'Expiry',
          'Batch',
        ]);
        final items =
            await (db.select(db.inventoryItems)
                  ..where((row) => row.clinicId.equals(clinicId))
                  ..orderBy([(row) => OrderingTerm.asc(row.drugName)]))
                .get();
        final now = DateTime.now();
        for (final item in items) {
          final expired =
              item.expiryDate != null && item.expiryDate!.isBefore(now);
          rows.add([
            item.drugName,
            item.category,
            '${item.quantity}',
            _money(item.buyingPrice),
            _money(item.sellingPrice),
            _money(item.quantity * item.buyingPrice),
            _money(item.quantity * item.sellingPrice),
            item.quantity <= item.minimumQuantity ? 'Low' : 'Normal',
            expired
                ? 'Expired'
                : item.expiryDate == null
                ? '-'
                : DateFormat.yMMMd().format(item.expiryDate!),
            item.batchNumber ?? '-',
          ]);
        }
      case ClinicReportType.vaccination:
        headers.addAll([
          'Patient',
          'Hospital No.',
          'Species',
          'Breed',
          'Vaccine',
          'Date Given',
          'Due Date',
          'Status',
          'Batch',
          'Manufacturer',
          'Veterinarian',
        ]);
        final vaccinations =
            await (db.select(db.vaccinations)
                  ..where(
                    (row) =>
                        row.clinicId.equals(clinicId) &
                        row.dateGiven.isBiggerOrEqualValue(_range.start) &
                        row.dateGiven.isSmallerThanValue(
                          _range.end.add(const Duration(days: 1)),
                        ),
                  )
                  ..orderBy([(row) => OrderingTerm.desc(row.dateGiven)]))
                .get();
        for (final vaccination in vaccinations) {
          final status = _vaccinationStatus(vaccination);
          if (_vaccinationFilter != 'All' &&
              !_matchesVaccinationFilter(status, _vaccinationFilter)) {
            continue;
          }
          final animal = animalById[vaccination.animalId];
          rows.add([
            animal?.animalName ?? 'Patient unavailable',
            animal?.hospitalNumber ?? '-',
            animal?.species ?? '-',
            animal?.breed ?? '-',
            vaccination.vaccine,
            DateFormat.yMMMd().format(vaccination.dateGiven),
            vaccination.nextDueDate == null
                ? '-'
                : DateFormat.yMMMd().format(vaccination.nextDueDate!),
            status,
            vaccination.batchNumber ?? '-',
            vaccination.manufacturer ?? '-',
            vaccination.veterinarian ?? vaccination.administeredBy ?? '-',
          ]);
        }
    }
    return _ReportData(
      clinicName: session.clinic.clinicName,
      title: _title,
      rangeLabel: widget.type == ClinicReportType.inventoryValue
          ? 'Current inventory'
          : '${DateFormat.yMMMd().format(_range.start)} - ${DateFormat.yMMMd().format(_range.end)}',
      headers: headers,
      rows: rows,
    );
  }

  void _setPreset(ReportDatePreset preset) {
    if (preset == ReportDatePreset.custom) {
      _selectCustomRange();
      return;
    }
    setState(() {
      _preset = preset;
      _range = _rangeForPreset(preset);
    });
  }

  Future<void> _selectCustomRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (result != null && mounted) {
      setState(() {
        _preset = ReportDatePreset.custom;
        _range = result;
      });
    }
  }

  Future<Directory> _targetDir() async =>
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();

  Future<Uint8List> _pdfBytes(_ReportData data) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              data.clinicName,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Text(
              data.title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(data.rangeLabel),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (_) => [
          pw.Text('${data.rows.length} record(s)'),
          pw.SizedBox(height: 10),
          if (data.rows.isEmpty)
            pw.Text('No clinic records matched the selected filters.')
          else
            pw.TableHelper.fromTextArray(
              headers: data.headers,
              data: data.rows,
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey100,
              ),
              cellAlignment: pw.Alignment.topLeft,
              cellPadding: const pw.EdgeInsets.all(4),
            ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> _exportPdf(_ReportData data, {required bool share}) async {
    await _guardExport(() async {
      final bytes = await _pdfBytes(data);
      final filename = '${widget.type.routeKey}-${_stamp()}.pdf';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        final file = File(p.join((await _targetDir()).path, filename));
        await file.writeAsBytes(bytes);
        _showSaved(file.path);
      }
    });
  }

  Future<void> _print(_ReportData data) async {
    await _guardExport(
      () => Printing.layoutPdf(name: _title, onLayout: (_) => _pdfBytes(data)),
    );
  }

  Future<void> _exportCsv(_ReportData data) async {
    await _guardExport(() async {
      final file = File(
        p.join(
          (await _targetDir()).path,
          '${widget.type.routeKey}-${_stamp()}.csv',
        ),
      );
      await file.writeAsString(
        const ListToCsvConverter().convert([data.headers, ...data.rows]),
      );
      _showSaved(file.path);
    });
  }

  Future<void> _exportExcel(_ReportData data) async {
    await _guardExport(() async {
      final workbook = Excel.createExcel();
      final sheet = workbook[_title];
      sheet.appendRow(data.headers.map(TextCellValue.new).toList());
      for (final row in data.rows) {
        sheet.appendRow(row.map(TextCellValue.new).toList());
      }
      final file = File(
        p.join(
          (await _targetDir()).path,
          '${widget.type.routeKey}-${_stamp()}.xlsx',
        ),
      );
      await file.writeAsBytes(workbook.encode() ?? []);
      _showSaved(file.path);
    });
  }

  Future<void> _guardExport(Future<void> Function() action) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSaved(String path) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved to $path')));
  }
}

class _ReportData {
  const _ReportData({
    required this.clinicName,
    required this.title,
    required this.rangeLabel,
    required this.headers,
    required this.rows,
  });
  final String clinicName;
  final String title;
  final String rangeLabel;
  final List<String> headers;
  final List<List<String>> rows;
}

class _ReportPreview extends StatelessWidget {
  const _ReportPreview({required this.data});
  final _ReportData data;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${data.rows.length} record(s)',
          style: averaText(context).listItemTitle,
        ),
        const SizedBox(height: 4),
        Text(data.rangeLabel, style: averaText(context).caption),
        const Divider(height: 28),
        if (data.rows.isEmpty)
          Text(
            'No clinic records matched the selected filters.',
            style: averaText(context).listItemSubtitle,
          )
        else
          for (final row in data.rows.take(10)) ...[
            Text(
              row.length > 1 ? row[1] : row.first,
              style: averaText(context).listItemTitle,
            ),
            const SizedBox(height: 2),
            Text(
              row.take(5).join(' | '),
              style: averaText(context).listItemSubtitle,
            ),
            if (row != data.rows.take(10).last) const Divider(height: 24),
          ],
        if (data.rows.length > 10) ...[
          const Divider(height: 24),
          Text(
            '${data.rows.length - 10} more records will be included in the export.',
            style: averaText(context).caption,
          ),
        ],
      ],
    ),
  );
}

class _DateFilter extends StatelessWidget {
  const _DateFilter({
    required this.preset,
    required this.range,
    required this.onChanged,
    required this.onCustomRange,
  });
  final ReportDatePreset preset;
  final DateTimeRange range;
  final ValueChanged<ReportDatePreset> onChanged;
  final VoidCallback onCustomRange;

  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: 'Date Range',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<ReportDatePreset>(
            isExpanded: true,
            value: preset,
            items: [
              for (final value in ReportDatePreset.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
        if (preset == ReportDatePreset.custom)
          TextButton.icon(
            onPressed: onCustomRange,
            icon: const Icon(Icons.date_range_rounded),
            label: Text(
              '${DateFormat.yMMMd().format(range.start)} - ${DateFormat.yMMMd().format(range.end)}',
            ),
          ),
      ],
    ),
  );
}

class _ExportActions extends StatelessWidget {
  const _ExportActions({
    required this.type,
    required this.exporting,
    required this.onPdf,
    required this.onPrint,
    required this.onShare,
    this.onCsv,
    this.onExcel,
  });
  final ClinicReportType type;
  final bool exporting;
  final VoidCallback onPdf;
  final VoidCallback onPrint;
  final VoidCallback onShare;
  final VoidCallback? onCsv;
  final VoidCallback? onExcel;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      FilledButton.icon(
        onPressed: exporting ? null : onPdf,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Save PDF'),
      ),
      OutlinedButton.icon(
        onPressed: exporting ? null : onPrint,
        icon: const Icon(Icons.print_outlined),
        label: const Text('Print'),
      ),
      OutlinedButton.icon(
        onPressed: exporting ? null : onShare,
        icon: const Icon(Icons.share_outlined),
        label: const Text('Share'),
      ),
      if (onCsv != null)
        OutlinedButton.icon(
          onPressed: exporting ? null : onCsv,
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('CSV'),
        ),
      if (onExcel != null)
        OutlinedButton.icon(
          onPressed: exporting ? null : onExcel,
          icon: const Icon(Icons.grid_on_outlined),
          label: const Text('Excel'),
        ),
    ],
  );
}

DateTimeRange _rangeForPreset(ReportDatePreset preset) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return switch (preset) {
    ReportDatePreset.today => DateTimeRange(start: today, end: today),
    ReportDatePreset.yesterday => DateTimeRange(
      start: today.subtract(const Duration(days: 1)),
      end: today.subtract(const Duration(days: 1)),
    ),
    ReportDatePreset.last7Days => DateTimeRange(
      start: today.subtract(const Duration(days: 6)),
      end: today,
    ),
    ReportDatePreset.last30Days => DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    ),
    ReportDatePreset.custom => DateTimeRange(start: today, end: today),
  };
}

String _vaccinationStatus(Vaccination vaccination) {
  if (vaccination.status.toLowerCase() == 'scheduled dose recorded') {
    return 'Completed';
  }
  final due = vaccination.nextDueDate;
  if (due == null) return 'Completed';
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  if (due.isBefore(start)) return 'Overdue';
  if (due.isBefore(start.add(const Duration(days: 1)))) return 'Due';
  return 'Upcoming';
}

bool _matchesVaccinationFilter(String status, String filter) {
  if (filter == 'Completed') return status == 'Completed';
  if (filter == 'Due') return status == 'Due' || status == 'Overdue';
  return status == filter;
}

String _money(num value) => 'NGN ${value.toStringAsFixed(2)}';
String _stamp() => DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
