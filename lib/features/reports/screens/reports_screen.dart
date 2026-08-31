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
import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/services/clinic_document_branding.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/models/revenue_period.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/avera_timeframe_selector.dart';
import '../services/canonical_inventory_records.dart';

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
        title: 'Inventory Stock & Valuation',
        subtitle:
            'Review stock levels, cost value, retail value, batches and expiry status.',
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          Text(
            'Generate reports from this clinic\'s saved records.',
            style: averaText(context).pageSubtitle,
          ),
          const SizedBox(height: AveraSpacing.subtitleToContentGap),
          for (var index = 0; index < reports.length; index++) ...[
            if (index > 0) const SizedBox(height: AveraSpacing.cardGap),
            AveraAdministrationCard(
              icon: reports[index].icon,
              title: reports[index].title,
              subtitle: reports[index].subtitle,
              onTap: () =>
                  context.push('/reports/${reports[index].type.routeKey}'),
            ),
          ],
          const SizedBox(height: AveraSpacing.sectionGap),
          Text(
            'DATA IMPORT & EXPORT',
            style: averaText(context).sectionLabel.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Bring in existing records, or back up what\'s here.',
            style: averaText(context).caption,
          ),
          const SizedBox(height: 12),
          AveraAdministrationCard(
            icon: Icons.upload_file_rounded,
            title: 'Import Inventory',
            subtitle:
                'Bring in products from Excel, CSV, or supported scanned documents.',
            onTap: () => context.push('/reports/import-inventory'),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          AveraAdministrationCard(
            icon: Icons.download_rounded,
            title: 'Export Records',
            subtitle:
                'Download clinic data as Excel or PDF for backup or accounting.',
            onTap: () => context.push('/reports/export-records'),
          ),
        ],
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
  RevenuePeriod _period = RevenuePeriod.oneDay;
  String _vaccinationFilter = 'All';
  bool _exporting = false;
  late Future<_ReportData> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = _load();
  }

  String get _title => switch (widget.type) {
    ClinicReportType.dailyConsultations => 'Daily Consultations',
    ClinicReportType.inventoryValue => 'Inventory Stock & Valuation',
    ClinicReportType.vaccination => 'Vaccination Report',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: FutureBuilder<_ReportData>(
        future: _reportFuture,
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
              if (widget.type != ClinicReportType.inventoryValue) ...[
                Text(
                  'TIMEFRAME',
                  style: averaText(context).sectionLabel.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                AveraTimeframeSelector(
                  selected: _period,
                  onSelected: (period) => _reloadReport(() => _period = period),
                  onMore: _selectMorePeriod,
                  keyPrefix: widget.type.routeKey,
                ),
              ],
              if (widget.type == ClinicReportType.vaccination) ...[
                const SizedBox(height: AveraSpacing.sectionGap),
                Text(
                  'STATUS',
                  style: averaText(context).sectionLabel.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
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
                        _reloadReport(() => _vaccinationFilter = values.first),
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
                        onPressed: () => _reloadReport(() {}),
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

  void _reloadReport(VoidCallback update) {
    setState(() {
      update();
      _reportFuture = _load();
    });
  }

  String get _subtitle => switch (widget.type) {
    ClinicReportType.dailyConsultations =>
      'Patient, owner and consultation activity for the selected period.',
    ClinicReportType.inventoryValue =>
      'Review stock levels, cost value, retail value, batches and expiry status.',
    ClinicReportType.vaccination =>
      'Vaccination history and due-date status for this clinic.',
  };

  Future<_ReportData> _load() async {
    final session = await ref.read(userSessionProvider.future);
    if (widget.type == ClinicReportType.inventoryValue) {
      return _loadInventory(session);
    }
    final range = _period.rangeAt(DateTime.now());
    if (BackendConfiguration.isConfigured) {
      return _loadRemote(session, range);
    }
    return _loadLocal(session, range);
  }

  Future<_ReportData> _loadLocal(
    UserSession session,
    RevenueDateRange range,
  ) async {
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
        final query = db.select(db.visits)
          ..where((row) => row.clinicId.equals(clinicId))
          ..where((row) => row.visitDate.isSmallerThanValue(range.end))
          ..orderBy([(row) => OrderingTerm.desc(row.visitDate)]);
        if (range.start != null) {
          query.where(
            (row) => row.visitDate.isBiggerOrEqualValue(range.start!),
          );
        }
        final visits = await query.get();
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
        throw StateError('Inventory uses the canonical inventory loader.');
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
        final query = db.select(db.vaccinations)
          ..where((row) => row.clinicId.equals(clinicId))
          ..where((row) => row.dateGiven.isSmallerThanValue(range.end))
          ..orderBy([(row) => OrderingTerm.desc(row.dateGiven)]);
        if (range.start != null) {
          query.where(
            (row) => row.dateGiven.isBiggerOrEqualValue(range.start!),
          );
        }
        final vaccinations = await query.get();
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
      branding: ClinicDocumentBranding.fromSession(session),
      title: _title,
      rangeLabel: _rangeLabel(range),
      headers: headers,
      rows: rows,
      summaryLabel: widget.type == ClinicReportType.dailyConsultations
          ? 'Consultations'
          : 'Vaccinations',
      primaryColumnIndex: widget.type == ClinicReportType.dailyConsultations
          ? 1
          : 0,
      emptyTitle: widget.type == ClinicReportType.dailyConsultations
          ? 'No consultations found'
          : 'No vaccinations found',
      emptyMessage: widget.type == ClinicReportType.dailyConsultations
          ? 'No consultation records matched this timeframe.'
          : 'No vaccination records matched this timeframe and status.',
    );
  }

  Future<_ReportData> _loadRemote(
    UserSession session,
    RevenueDateRange range,
  ) async {
    final rows = <List<String>>[];
    final headers = <String>[];
    final source = ref.read(clinicalRemoteDataSourceProvider);

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
        final records = await source.reportConsultations(
          from: range.start,
          to: range.end,
        );
        for (final item in records) {
          final occurredAt = DateTime.tryParse('${item['occurred_at']}');
          rows.add([
            occurredAt == null
                ? '-'
                : DateFormat.yMMMd().add_jm().format(occurredAt.toLocal()),
            '${item['patient_name'] ?? 'Patient unavailable'}',
            '${item['hospital_number'] ?? '-'}',
            '${item['owner_name'] ?? '-'}',
            '${item['clinician_name_snapshot'] ?? '-'}',
            '${item['chief_complaint'] ?? '-'}',
            '${item['final_diagnosis'] ?? '-'}',
            '${item['treatment'] ?? '-'}',
            '${item['status'] ?? '-'}',
          ]);
        }
      case ClinicReportType.inventoryValue:
        throw StateError('Inventory uses the canonical inventory loader.');
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
        final records = await source.reportVaccinations(
          from: range.start,
          to: range.end,
        );
        for (final item in records) {
          final administered = DateTime.tryParse('${item['administered_at']}');
          final due = item['next_due_at'] == null
              ? null
              : DateTime.tryParse('${item['next_due_at']}');
          final status = _vaccinationStatusFromValues(
            '${item['status'] ?? ''}',
            due,
          );
          if (_vaccinationFilter != 'All' &&
              !_matchesVaccinationFilter(status, _vaccinationFilter)) {
            continue;
          }
          rows.add([
            '${item['patient_name'] ?? 'Patient unavailable'}',
            '${item['hospital_number'] ?? '-'}',
            '${item['species'] ?? '-'}',
            '${item['breed'] ?? '-'}',
            '${item['vaccine_name'] ?? '-'}',
            administered == null
                ? '-'
                : DateFormat.yMMMd().format(administered.toLocal()),
            due == null ? '-' : DateFormat.yMMMd().format(due.toLocal()),
            status,
            '${item['batch_number'] ?? '-'}',
            '${item['manufacturer'] ?? '-'}',
            '-',
          ]);
        }
    }
    return _ReportData(
      branding: ClinicDocumentBranding.fromSession(session),
      title: _title,
      rangeLabel: _rangeLabel(range),
      headers: headers,
      rows: rows,
      summaryLabel: widget.type == ClinicReportType.dailyConsultations
          ? 'Consultations'
          : 'Vaccinations',
      primaryColumnIndex: widget.type == ClinicReportType.dailyConsultations
          ? 1
          : 0,
      emptyTitle: widget.type == ClinicReportType.dailyConsultations
          ? 'No consultations found'
          : 'No vaccinations found',
      emptyMessage: widget.type == ClinicReportType.dailyConsultations
          ? 'No consultation records matched this timeframe.'
          : 'No vaccination records matched this timeframe and status.',
    );
  }

  Future<_ReportData> _loadInventory(UserSession session) async {
    final items = await loadCanonicalInventoryRecords(
      ref: ref,
      session: session,
    );
    final now = DateTime.now();
    final rows = <List<String>>[];
    var recordedCostValue = 0.0;
    var retailValue = 0.0;
    var missingCosts = 0;
    for (final item in items) {
      final cost = item.costPrice;
      final expired = item.expiryDate?.isBefore(now) == true;
      if (cost == null) {
        missingCosts += 1;
      } else {
        recordedCostValue += cost * item.quantity;
      }
      retailValue += item.sellingPrice * item.quantity;
      rows.add([
        item.name,
        item.category,
        '${item.quantity}',
        item.baseUnit,
        cost == null ? 'Missing Cost' : _money(cost),
        _money(item.sellingPrice),
        cost == null ? 'Missing Cost' : _money(cost * item.quantity),
        _money(item.sellingPrice * item.quantity),
        item.batchNumber ?? '-',
        item.expiryDate == null
            ? '-'
            : DateFormat.yMMMd().format(item.expiryDate!),
        expired ? 'Expired' : item.status,
      ]);
    }
    final units = items
        .map((item) => item.baseUnit.trim().toLowerCase())
        .where((unit) => unit.isNotEmpty)
        .toSet();
    final metrics = <_ReportMetric>[
      _ReportMetric(label: 'Products', value: '${items.length}'),
      _ReportMetric(
        label: 'Recorded Cost Value',
        value: _money(recordedCostValue),
      ),
      _ReportMetric(label: 'Retail Stock Value', value: _money(retailValue)),
      if (units.length == 1)
        _ReportMetric(
          label: 'Units in Stock (${units.first})',
          value:
              '${items.fold<int>(0, (total, item) => total + item.quantity)}',
        ),
      if (missingCosts > 0)
        _ReportMetric(label: 'Missing Cost', value: '$missingCosts'),
    ];
    return _ReportData(
      branding: ClinicDocumentBranding.fromSession(session),
      title: _title,
      rangeLabel: 'Current inventory',
      headers: const [
        'Product',
        'Category',
        'Stock',
        'Unit',
        'Cost Price',
        'Selling Price',
        'Cost Value',
        'Retail Value',
        'Batch',
        'Expiry',
        'Status',
      ],
      rows: rows,
      summaryLabel: 'Products',
      primaryColumnIndex: 0,
      emptyTitle: 'No inventory products',
      emptyMessage:
          'Add inventory products to include them in stock reports and exports.',
      metrics: metrics,
    );
  }

  Future<void> _selectMorePeriod() async {
    final selected = await showAveraTimeframePicker(
      context,
      _period,
      description: 'Choose the exact period to include in this report.',
      keyPrefix: widget.type.routeKey,
    );
    if (selected != null && mounted) {
      _reloadReport(() => _period = selected);
    }
  }

  String _rangeLabel(RevenueDateRange range) {
    if (range.start == null) return 'All available records';
    final start = range.start!.toLocal();
    final end = range.end.subtract(const Duration(microseconds: 1)).toLocal();
    return '${DateFormat.yMMMd().format(start)} - ${DateFormat.yMMMd().format(end)}';
  }

  Future<Directory> _targetDir() async =>
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();

  Future<Uint8List> _pdfBytes(_ReportData data) async {
    final brandingService = const ClinicDocumentBrandingService();
    final logo = await brandingService.loadLogo(data.branding.logoReference);
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            brandingService.identity(branding: data.branding, logo: logo),
            pw.SizedBox(height: 8),
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
    required this.branding,
    required this.title,
    required this.rangeLabel,
    required this.headers,
    required this.rows,
    required this.summaryLabel,
    required this.primaryColumnIndex,
    required this.emptyTitle,
    required this.emptyMessage,
    this.metrics = const [],
  });
  final ClinicDocumentBranding branding;
  final String title;
  final String rangeLabel;
  final List<String> headers;
  final List<List<String>> rows;
  final String summaryLabel;
  final int primaryColumnIndex;
  final String emptyTitle;
  final String emptyMessage;
  final List<_ReportMetric> metrics;
}

class _ReportMetric {
  const _ReportMetric({required this.label, required this.value});
  final String label;
  final String value;
}

class _ReportPreview extends StatelessWidget {
  const _ReportPreview({required this.data});
  final _ReportData data;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.summaryLabel, style: averaText(context).listItemTitle),
        const SizedBox(height: 2),
        Text(
          '${data.rows.length}',
          style: averaText(context).pageTitle.copyWith(fontSize: 30),
        ),
        const SizedBox(height: 2),
        Text(data.rangeLabel, style: averaText(context).caption),
        if (data.metrics.isNotEmpty) ...[
          const Divider(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final metric in data.metrics)
                Container(
                  width: 156,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.value,
                        style: averaText(context).sectionTitle,
                      ),
                      const SizedBox(height: 3),
                      Text(metric.label, style: averaText(context).caption),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const Divider(height: 24),
        if (data.rows.isEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.inbox_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.emptyTitle,
                      style: averaText(context).listItemTitle,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.emptyMessage,
                      style: averaText(context).listItemSubtitle,
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          for (final row in data.rows.take(10)) ...[
            Text(
              row[data.primaryColumnIndex],
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
  Widget build(BuildContext context) {
    final actions = <Widget>[
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
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final action in actions) SizedBox(height: 46, child: action),
      ],
    );
  }
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

String _vaccinationStatusFromValues(String storedStatus, DateTime? due) {
  if (storedStatus.toLowerCase().contains('completed') || due == null) {
    return 'Completed';
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final localDue = due.toLocal();
  final dueDay = DateTime(localDue.year, localDue.month, localDue.day);
  if (dueDay.isBefore(today)) return 'Overdue';
  if (dueDay == today) return 'Due';
  return 'Upcoming';
}

bool _matchesVaccinationFilter(String status, String filter) {
  if (filter == 'Completed') return status == 'Completed';
  if (filter == 'Due') return status == 'Due' || status == 'Overdue';
  return status == filter;
}

String _money(num value) => 'NGN ${value.toStringAsFixed(2)}';
String _stamp() => DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
