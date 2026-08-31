import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/models/inventory_catalog.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../inventory/widgets/inventory_item_dialog.dart';
import '../../shared/widgets/avera_ui.dart';
import '../services/canonical_inventory_records.dart';
import '../services/inventory_export_service.dart';
import '../services/inventory_import_service.dart';

class ImportInventoryScreen extends ConsumerStatefulWidget {
  const ImportInventoryScreen({super.key});

  @override
  ConsumerState<ImportInventoryScreen> createState() =>
      _ImportInventoryScreenState();
}

class _ImportInventoryScreenState extends ConsumerState<ImportInventoryScreen> {
  static const _parser = InventoryImportParser();
  InventoryImportDocument? _document;
  InventoryImportValidationResult? _validation;
  List<InventoryDuplicateMatch> _duplicates = const [];
  final _categoryOverrides = <int, String>{};
  final _unitOverrides = <int, String>{};
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final validation = _validation;
    return Scaffold(
      appBar: AppBar(title: const Text('Import Inventory')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          Text(
            'Bring your existing stock list into AVERA.',
            style: averaText(context).pageSubtitle,
          ),
          const SizedBox(height: AveraSpacing.sectionGap),
          _SectionLabel(text: '1. Upload Your File'),
          const SizedBox(height: 12),
          _UploadPanel(busy: _busy, onPressed: _pickFile),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('XLSX')),
              Chip(label: Text('CSV')),
              Chip(
                avatar: Icon(Icons.schedule_rounded, size: 16),
                label: Text('PDF - coming later'),
              ),
              Chip(
                avatar: Icon(Icons.schedule_rounded, size: 16),
                label: Text('Photo - coming later'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageCard(message: _error!, isError: true),
          ],
          if (document != null) ...[
            const SizedBox(height: AveraSpacing.sectionGap),
            _SectionLabel(text: '2. Confirm Column Matching'),
            const SizedBox(height: 6),
            Text(
              '${document.filename} - ${document.rows.length} rows detected',
              style: averaText(context).caption,
            ),
            const SizedBox(height: 12),
            AveraSurfaceCard(
              padding: const EdgeInsets.all(0),
              child: Column(
                children: [
                  for (var index = 0; index < document.mapping.length; index++)
                    _MappingRow(
                      mapping: document.mapping[index],
                      usedTargets: document.mapping
                          .where((item) => item.target != null)
                          .map((item) => item.target!)
                          .toSet(),
                      onChanged: (value) => _changeMapping(index, value),
                    ),
                ],
              ),
            ),
          ],
          if (validation != null) ...[
            const SizedBox(height: AveraSpacing.sectionGap),
            _SectionLabel(text: '3. Review Import'),
            const SizedBox(height: 12),
            _ImportSummary(
              validation: validation,
              duplicateCount: _duplicates.length,
              actionCount: _actionCount,
            ),
            if (validation.rows.any((row) => !row.isValid)) ...[
              const SizedBox(height: 12),
              for (final row in validation.rows.where((row) => !row.isValid))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _InvalidRowCard(
                    row: row,
                    categoryValue: _categoryOverrides[row.sourceRow],
                    unitValue: _unitOverrides[row.sourceRow],
                    onCategory: (value) {
                      if (value != null) {
                        _categoryOverrides[row.sourceRow] = value;
                        _revalidate();
                      }
                    },
                    onUnit: (value) {
                      if (value != null) {
                        _unitOverrides[row.sourceRow] = value;
                        _revalidate();
                      }
                    },
                  ),
                ),
            ],
            if (_duplicates.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var index = 0; index < _duplicates.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DuplicateCard(
                    match: _duplicates[index],
                    onChanged: (action) {
                      if (action == null) return;
                      setState(() {
                        _duplicates = [..._duplicates];
                        _duplicates[index] = _duplicates[index].withAction(
                          action,
                        );
                      });
                    },
                  ),
                ),
            ],
            const SizedBox(height: AveraSpacing.sectionGap),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _busy || _actionCount == 0 ? null : _executeImport,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                label: Text('Import $_actionCount Products'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int get _actionCount {
    final valid = _validation?.validRows.length ?? 0;
    final skipped = _duplicates
        .where((item) => item.action == InventoryDuplicateAction.skip)
        .length;
    return (valid - skipped).clamp(0, valid);
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      if (selection == null) return;
      final file = selection.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const InventoryImportException(
          'AVERA could not read the selected file.',
        );
      }
      final document = await compute(_parseInventoryDocument, (
        filename: file.name,
        bytes: bytes,
      ));
      setState(() {
        _document = document;
        _categoryOverrides.clear();
        _unitOverrides.clear();
      });
      await _revalidate();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeMapping(int index, InventoryImportField? target) {
    final document = _document!;
    final mappings = [...document.mapping];
    if (target != null) {
      for (var i = 0; i < mappings.length; i++) {
        if (i != index && mappings[i].target == target) {
          mappings[i] = mappings[i].copyWith(
            clearTarget: true,
            confidence: InventoryMappingConfidence.manual,
          );
        }
      }
    }
    mappings[index] = mappings[index].copyWith(
      target: target,
      clearTarget: target == null,
      confidence: InventoryMappingConfidence.manual,
    );
    setState(() => _document = document.withMapping(mappings));
    _revalidate();
  }

  Future<void> _revalidate() async {
    final document = _document;
    if (document == null) return;
    final validation = _parser.validate(
      document,
      categoryOverrides: _categoryOverrides,
      unitOverrides: _unitOverrides,
    );
    final existing = await _loadExistingProducts();
    final duplicates = _parser.findDuplicates(
      validation.validRows.map((row) => row.candidate!),
      existing,
    );
    if (!mounted) return;
    setState(() {
      _validation = validation;
      _duplicates = duplicates;
    });
  }

  Future<List<InventoryExistingProduct>> _loadExistingProducts() async {
    final session = await ref.read(userSessionProvider.future);
    if (BackendConfiguration.isConfigured) {
      await ref.read(remoteInventoryListProvider.notifier).refresh();
      return ref
          .read(remoteInventoryListProvider)
          .items
          .where((item) => !item.isArchived)
          .map(
            (item) => InventoryExistingProduct(
              id: item.id,
              name: item.name,
              categoryId: InventoryCategories.canonicalId(item.categoryId),
              sku: item.sku,
              barcode: item.barcode,
              genericName: item.genericName,
              manufacturer: item.manufacturer,
              sellingPrice: item.sellingPrice.toDouble(),
            ),
          )
          .toList();
    }
    final db = ref.read(databaseProvider);
    final items =
        await (db.select(db.inventoryItems)..where(
              (row) =>
                  row.clinicId.equals(session.clinic.clinicId) &
                  row.isArchived.equals(false),
            ))
            .get();
    return items
        .map(
          (item) => InventoryExistingProduct(
            id: item.id,
            name: item.drugName,
            categoryId: InventoryCategories.canonicalId(
              item.categoryId ?? item.category,
            ),
            sku: item.sku,
            barcode: item.barcode,
            genericName: item.genericName,
            manufacturer: item.manufacturer,
            sellingPrice: item.sellingPrice,
          ),
        )
        .toList();
  }

  Future<void> _executeImport() async {
    if (_busy || _validation == null) return;
    final session = await ref.read(userSessionProvider.future);
    if (!session.can(Permissions.inventoryCreate)) {
      setState(
        () => _error = 'You do not have permission to import inventory.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var created = 0;
    var updated = 0;
    var skipped = 0;
    try {
      final duplicateByRow = {
        for (final item in _duplicates) item.candidate.sourceRow: item,
      };
      for (final row in _validation!.validRows) {
        final candidate = row.candidate!;
        final duplicate = duplicateByRow[candidate.sourceRow];
        if (duplicate?.action == InventoryDuplicateAction.skip) {
          skipped++;
          continue;
        }
        final draft = _draft(candidate, duplicate);
        if (BackendConfiguration.isConfigured) {
          final controller = ref.read(remoteInventoryListProvider.notifier);
          if (duplicate?.action == InventoryDuplicateAction.updateExisting) {
            await controller.update(
              itemId: duplicate!.existing.id as String,
              payload: draft.toRemotePayload(),
            );
            updated++;
          } else {
            await controller.create(draft.toRemotePayload());
            created++;
          }
        } else {
          await _saveLocal(session, candidate, duplicate);
          if (duplicate?.action == InventoryDuplicateAction.updateExisting) {
            updated++;
          } else {
            created++;
          }
        }
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Imported successfully'),
          content: Text(
            'Created: $created\n'
            'Updated existing: $updated\n'
            'Duplicates skipped: $skipped\n'
            'Invalid/skipped rows: ${_validation!.invalidCount}\n'
            'Missing cost price: ${_validation!.missingCostCount}\n\n'
            'Missing costs remain flagged in Revenue & Profit until corrected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Import Another File'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/inventory');
              },
              child: const Text('View Inventory'),
            ),
          ],
        ),
      );
    } catch (error) {
      setState(() {
        _error =
            'Import stopped after $created created and $updated updated. '
            'No further rows were changed. $error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InventoryItemDraft _draft(
    InventoryImportCandidate item,
    InventoryDuplicateMatch? duplicate,
  ) => InventoryItemDraft(
    submissionId: const Uuid().v4(),
    remoteId:
        duplicate?.action == InventoryDuplicateAction.updateExisting &&
            duplicate!.existing.id is String
        ? duplicate.existing.id as String
        : null,
    name: item.name,
    categoryId: item.categoryId,
    categoryName: item.categoryName,
    subcategoryId: item.subcategoryId,
    subcategoryName: item.subcategoryName,
    quantity: item.quantity,
    minimumQuantity: 5,
    sellingPrice: item.sellingPrice,
    buyingPrice: item.costPrice ?? 0,
    batchNumber: item.batchNumber,
    expiryDate: item.expiryDate,
    genericName: item.genericName,
    brandName: item.brandName,
    manufacturer: item.manufacturer,
    sku: item.sku,
    barcode: item.barcode,
    dosageForm: item.dosageForm,
    packSize: item.packSize,
    baseUnitLabel: item.baseUnitLabel,
    storageConditions: item.storageConditions,
  );

  Future<void> _saveLocal(
    UserSession session,
    InventoryImportCandidate item,
    InventoryDuplicateMatch? duplicate,
  ) async {
    final repository = ref.read(clinicRepositoryProvider);
    final common = (
      buyingPrice: item.costPrice,
      categoryName: item.categoryName,
    );
    if (duplicate?.action == InventoryDuplicateAction.updateExisting) {
      await repository.updateInventoryItem(
        session: session,
        itemId: duplicate!.existing.id as int,
        name: item.name,
        categoryId: item.categoryId,
        categoryName: common.categoryName,
        subcategoryId: item.subcategoryId,
        subcategoryName: item.subcategoryName,
        quantity: item.quantity,
        minimumQuantity: 5,
        batchNumber: item.batchNumber,
        expiryDate: item.expiryDate,
        sellingPrice: item.sellingPrice,
        buyingPrice: common.buyingPrice,
        genericName: item.genericName,
        brandName: item.brandName,
        manufacturer: item.manufacturer,
        sku: item.sku,
        barcode: item.barcode,
        dosageForm: item.dosageForm,
        packSize: item.packSize,
        baseUnitLabel: item.baseUnitLabel,
        storageConditions: item.storageConditions,
      );
    } else {
      await repository.saveInventoryItem(
        session: session,
        name: item.name,
        categoryId: item.categoryId,
        categoryName: common.categoryName,
        subcategoryId: item.subcategoryId,
        subcategoryName: item.subcategoryName,
        quantity: item.quantity,
        minimumQuantity: 5,
        batchNumber: item.batchNumber,
        expiryDate: item.expiryDate,
        sellingPrice: item.sellingPrice,
        buyingPrice: common.buyingPrice,
        genericName: item.genericName,
        brandName: item.brandName,
        manufacturer: item.manufacturer,
        sku: item.sku,
        barcode: item.barcode,
        dosageForm: item.dosageForm,
        packSize: item.packSize,
        baseUnitLabel: item.baseUnitLabel,
        storageConditions: item.storageConditions,
      );
    }
  }
}

InventoryImportDocument _parseInventoryDocument(
  ({String filename, Uint8List bytes}) input,
) => const InventoryImportParser().parse(
  filename: input.filename,
  bytes: input.bytes,
);

class ExportRecordsScreen extends ConsumerStatefulWidget {
  const ExportRecordsScreen({super.key});

  @override
  ConsumerState<ExportRecordsScreen> createState() =>
      _ExportRecordsScreenState();
}

class _ExportRecordsScreenState extends ConsumerState<ExportRecordsScreen> {
  static const _service = InventoryExportService();
  String _format = 'xlsx';
  bool _busy = false;
  String? _message;
  late Future<List<InventoryExportRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _recordsFuture = _loadRecords();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<InventoryExportRecord>>(
    future: _recordsFuture,
    builder: (context, snapshot) {
      final count = snapshot.data?.length;
      return Scaffold(
        appBar: AppBar(title: const Text('Export Records')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.pageTopPadding,
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.bottomContentClearance,
          ),
          children: [
            Text(
              'Download current clinic records for accounting or safekeeping.',
              style: averaText(context).pageSubtitle,
            ),
            const SizedBox(height: AveraSpacing.sectionGap),
            const _SectionLabel(text: 'Export Data'),
            const SizedBox(height: 12),
            AveraLabeledFieldCard(
              label: 'Selected scope',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Inventory'),
                subtitle: Text(
                  snapshot.hasError
                      ? 'Inventory count unavailable'
                      : count == null
                      ? 'Loading current inventory...'
                      : '$count ${count == 1 ? 'product' : 'products'}',
                  key: const Key('inventory-export-count'),
                ),
              ),
            ),
            if (count == 0) ...[
              const SizedBox(height: AveraSpacing.cardGap),
              const _MessageCard(
                message:
                    'No inventory products. Add inventory products before exporting.',
              ),
            ],
            const SizedBox(height: AveraSpacing.cardGap),
            AveraLabeledFieldCard(
              label: 'File format',
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'xlsx',
                    icon: Icon(Icons.grid_on_outlined),
                    label: Text('Excel'),
                  ),
                  ButtonSegment(
                    value: 'pdf',
                    icon: Icon(Icons.picture_as_pdf_outlined),
                    label: Text('PDF'),
                  ),
                ],
                selected: {_format},
                onSelectionChanged: _busy
                    ? null
                    : (values) => setState(() => _format = values.first),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              _MessageCard(message: _message!),
            ],
            const SizedBox(height: AveraSpacing.sectionGap),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _busy || count == null || count == 0
                    ? null
                    : _export,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  count == null
                      ? 'Loading Inventory'
                      : 'Export $count ${count == 1 ? 'Product' : 'Products'} as ${_format.toUpperCase()}',
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _export() async {
    final session = await ref.read(userSessionProvider.future);
    if (!session.can(Permissions.reportsExport)) {
      setState(
        () => _message = 'You do not have permission to export reports.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final records = await _recordsFuture;
      final filename = _service.filename(
        clinicName: session.clinic.clinicName,
        extension: _format,
      );
      final Uint8List bytes;
      if (_format == 'pdf') {
        bytes = await _service.pdfBytes(
          records,
          clinicName: session.clinic.clinicName,
        );
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        bytes = _service.excelBytes(records);
        await FilePicker.saveFile(fileName: filename, bytes: bytes);
      }
      if (mounted) {
        setState(
          () => _message = '${records.length} records exported as $filename.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<InventoryExportRecord>> _loadRecords() async {
    final session = await ref.read(userSessionProvider.future);
    return loadCanonicalInventoryRecords(ref: ref, session: session);
  }
}

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: busy ? null : onPressed,
    borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
    child: Ink(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: .42),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
      ),
      child: Column(
        children: [
          Icon(
            Icons.upload_file_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            busy ? 'Reading file...' : 'Tap to upload a file',
            style: averaText(context).listItemTitle,
          ),
          const SizedBox(height: 4),
          Text(
            'Supports Excel (.xlsx) and CSV',
            style: averaText(context).caption,
          ),
          const SizedBox(height: 8),
          Text(
            'Maximum 10 MB and 2,000 data rows',
            style: averaText(context).caption,
          ),
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: averaText(
      context,
    ).sectionLabel.copyWith(color: Theme.of(context).colorScheme.primary),
  );
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.mapping,
    required this.usedTargets,
    required this.onChanged,
  });
  final InventoryColumnMapping mapping;
  final Set<InventoryImportField> usedTargets;
  final ValueChanged<InventoryImportField?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mapping.header, style: averaText(context).caption),
              Text(
                mapping.target?.label ?? 'Select field or ignore',
                style: averaText(context).listItemTitle,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<InventoryImportField?>(
          value: mapping.target,
          hint: const Text('Ignore'),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<InventoryImportField?>(
              value: null,
              child: Text('Ignore'),
            ),
            for (final field in InventoryImportField.values)
              if (!usedTargets.contains(field) || mapping.target == field)
                DropdownMenuItem(value: field, child: Text(field.label)),
          ],
          onChanged: onChanged,
        ),
        Icon(
          mapping.confidence == InventoryMappingConfidence.high
              ? Icons.check_circle_rounded
              : Icons.warning_amber_rounded,
          color: mapping.confidence == InventoryMappingConfidence.high
              ? Theme.of(context).colorScheme.primary
              : Colors.amber.shade800,
        ),
      ],
    ),
  );
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({
    required this.validation,
    required this.duplicateCount,
    required this.actionCount,
  });
  final InventoryImportValidationResult validation;
  final int duplicateCount;
  final int actionCount;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Wrap(
      spacing: 22,
      runSpacing: 16,
      children: [
        _Metric('Parsed', '${validation.rows.length}'),
        _Metric('Ready', '$actionCount'),
        _Metric('Duplicates', '$duplicateCount'),
        _Metric('Warnings', '${validation.warningCount}'),
        _Metric('Missing cost', '${validation.missingCostCount}'),
        _Metric('Invalid', '${validation.invalidCount}'),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: averaText(context).caption),
      ],
    ),
  );
}

class _InvalidRowCard extends StatelessWidget {
  const _InvalidRowCard({
    required this.row,
    required this.categoryValue,
    required this.unitValue,
    required this.onCategory,
    required this.onUnit,
  });
  final InventoryRowValidation row;
  final String? categoryValue;
  final String? unitValue;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onUnit;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Source row ${row.sourceRow}',
          style: averaText(context).listItemTitle,
        ),
        for (final error in row.errors)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (row.errors.any((error) => error.startsWith('Category'))) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: categoryValue,
            decoration: const InputDecoration(labelText: 'Resolve category'),
            items: [
              for (final category in InventoryCategories.all)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: onCategory,
          ),
        ],
        if (row.errors.any((error) => error.startsWith('Unit'))) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: unitValue,
            decoration: const InputDecoration(labelText: 'Resolve base unit'),
            items: [
              for (final unit in inventoryCanonicalUnits)
                DropdownMenuItem(value: unit, child: Text(unit)),
            ],
            onChanged: onUnit,
          ),
        ],
      ],
    ),
  );
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({required this.match, required this.onChanged});
  final InventoryDuplicateMatch match;
  final ValueChanged<InventoryDuplicateAction?> onChanged;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(match.candidate.name, style: averaText(context).listItemTitle),
        const SizedBox(height: 3),
        Text(
          '${match.reason}: ${match.existing.name}',
          style: averaText(context).listItemSubtitle,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<InventoryDuplicateAction>(
          value: match.action,
          decoration: const InputDecoration(labelText: 'Duplicate action'),
          items: const [
            DropdownMenuItem(
              value: InventoryDuplicateAction.skip,
              child: Text('Skip (recommended)'),
            ),
            DropdownMenuItem(
              value: InventoryDuplicateAction.updateExisting,
              child: Text('Update existing'),
            ),
            DropdownMenuItem(
              value: InventoryDuplicateAction.importAsNew,
              child: Text('Import as new'),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.isError = false});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          color: isError
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
  );
}
