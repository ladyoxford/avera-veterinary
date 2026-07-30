import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_restore_coordinator.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/avera_ui.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ref
          .read(clinicRepositoryProvider)
          .exportDatabaseBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup saved: ${file.path}')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The backup could not be created.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectRestore() async {
    if (_busy) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'db'],
      withData: false,
    );
    if (result == null || !mounted) return;
    final selected = result.files.single;
    final validation = await _validate(selected);
    if (!mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(validation.valid ? 'Review backup' : 'Invalid backup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(selected.name, style: averaText(context).listItemTitle),
              const SizedBox(height: 8),
              Text(validation.message),
              if (validation.valid) ...[
                const SizedBox(height: AveraSpacing.compactRowGap),
                const Text(
                  'AVERA will stage this verified backup, close the app, and replace the database safely before Drift opens on the next launch.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          if (validation.valid)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore on Restart'),
            ),
        ],
      ),
    );
    if (restore != true || !mounted || selected.path == null) return;
    setState(() => _busy = true);
    try {
      await DatabaseRestoreCoordinator.stage(selected.path!);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Backup ready to restore'),
          content: const Text(
            'AVERA will now close. Reopen it to apply the backup before the database starts.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                SystemNavigator.pop();
              },
              child: const Text('Close AVERA'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_BackupValidation> _validate(PlatformFile selected) async {
    final lower = selected.name.toLowerCase();
    if (!lower.endsWith('.sqlite') && !lower.endsWith('.db')) {
      return const _BackupValidation(
        false,
        'Select an AVERA SQLite database file.',
      );
    }
    final path = selected.path;
    if (path == null) {
      return const _BackupValidation(
        false,
        'The selected file could not be opened from this device.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      return const _BackupValidation(
        false,
        'The selected file is unavailable.',
      );
    }
    final bytes = await file
        .openRead(0, 16)
        .fold<BytesBuilder>(
          BytesBuilder(),
          (builder, chunk) => builder..add(chunk),
        )
        .then((builder) => builder.takeBytes());
    if (bytes.length < 16) {
      return const _BackupValidation(false, 'The selected file is incomplete.');
    }
    const signature = 'SQLite format 3\u0000';
    final actual = String.fromCharCodes(bytes.take(16));
    if (actual != signature) {
      return const _BackupValidation(
        false,
        'This file does not contain a valid SQLite database header.',
      );
    }

    final clinicId = ref.read(clinicRepositoryProvider).activeClinicId;
    final inspection = await Isolate.run(
      () => _inspectAveraBackup(path, clinicId),
    );
    if (!inspection.valid) return inspection;
    return _BackupValidation(
      true,
      '${inspection.message}\nFile size: ${_formatBytes(selected.size)}',
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & Restore')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AveraSpacing.pageHorizontalPadding,
        AveraSpacing.pageTopPadding,
        AveraSpacing.pageHorizontalPadding,
        AveraSpacing.bottomContentClearance,
      ),
      children: [
        const AveraPageHeader(
          title: 'Backup & Restore',
          subtitle: 'Protect and recover your clinic\u2019s local records.',
        ),
        const SizedBox(height: AveraSpacing.subtitleToContentGap),
        AveraAdministrationCard(
          icon: Icons.storage_rounded,
          title: 'Export SQLite Database',
          subtitle: _busy
              ? 'Creating a consistent timestamped backup...'
              : 'Create a timestamped backup file.',
          onTap: _busy ? null : _export,
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraAdministrationCard(
          icon: Icons.settings_backup_restore_rounded,
          title: 'Restore from Backup',
          subtitle:
              'Select a valid AVERA backup file and review it before restoring.',
          onTap: _busy ? null : _selectRestore,
        ),
      ],
    ),
  );
}

class _BackupValidation {
  const _BackupValidation(this.valid, this.message);
  final bool valid;
  final String message;
}

_BackupValidation _inspectAveraBackup(String path, String activeClinicId) {
  Database? database;
  try {
    database = sqlite3.open(path, mode: OpenMode.readOnly);
    final integrity = database
        .select('PRAGMA integrity_check')
        .first
        .values
        .first
        .toString();
    if (integrity.toLowerCase() != 'ok') {
      return const _BackupValidation(
        false,
        'SQLite integrity verification failed.',
      );
    }

    final tables = database
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .map((row) => row['name'].toString())
        .toSet();
    const requiredTables = {'clinics', 'users', 'animals'};
    final missing = requiredTables.difference(tables);
    if (missing.isNotEmpty) {
      return _BackupValidation(
        false,
        'This is not a compatible AVERA backup. Missing: ${missing.join(', ')}.',
      );
    }

    final version = database.select('PRAGMA user_version').first.values.first;
    if (version is! int ||
        version <= 0 ||
        version > AppDatabase.currentSchemaVersion) {
      return _BackupValidation(
        false,
        'Database version $version is not compatible with this AVERA build.',
      );
    }

    final clinics = database.select(
      'SELECT clinic_id, clinic_name FROM clinics ORDER BY clinic_name',
    );
    if (clinics.isEmpty) {
      return const _BackupValidation(
        false,
        'The backup contains no clinic records.',
      );
    }
    final ownsActiveClinic = clinics.any(
      (row) => row['clinic_id'].toString() == activeClinicId,
    );
    if (!ownsActiveClinic) {
      return const _BackupValidation(
        false,
        'The backup does not contain the active clinic. No data was changed.',
      );
    }

    return _BackupValidation(
      true,
      'Integrity verified\n'
      'Database version: $version\n'
      'Clinics: ${clinics.length}\n'
      'Required AVERA schema: verified',
    );
  } on SqliteException {
    return const _BackupValidation(
      false,
      'The database could not be read or failed schema validation.',
    );
  } finally {
    database?.dispose();
  }
}
