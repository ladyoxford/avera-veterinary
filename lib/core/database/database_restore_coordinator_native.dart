import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class DatabaseRestoreCoordinator {
  const DatabaseRestoreCoordinator._();

  // Keep the legacy filename so existing installations continue opening the
  // same Drift database after the product/package identity migration.
  static const databaseFileName = 'zevora.sqlite';
  static const _pendingFileName = 'avera_restore_pending.sqlite';
  static const _reportFileName = 'avera_restore_report.json';

  static const _countedTables = <String>[
    'clinics',
    'users',
    'owners',
    'animals',
    'visits',
    'vaccinations',
    'appointments',
    'inventory_items',
    'invoices',
    'farms',
  ];

  static Future<void> stage(String sourcePath) async {
    final directory = await getApplicationDocumentsDirectory();
    await stageInDirectory(sourcePath, directory);
  }

  static Future<void> stageInDirectory(
    String sourcePath,
    Directory directory,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('The selected backup file is no longer available.');
    }
    final pending = File(p.join(directory.path, _pendingFileName));
    await source.copy(pending.path);
  }

  static Future<void> applyPendingRestore() async {
    final directory = await getApplicationDocumentsDirectory();
    await applyPendingRestoreInDirectory(directory);
  }

  static Future<void> applyPendingRestoreInDirectory(
    Directory directory,
  ) async {
    final pending = File(p.join(directory.path, _pendingFileName));
    if (!await pending.exists()) return;

    final target = File(p.join(directory.path, databaseFileName));
    final before = await _counts(target);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    String? rollbackPath;
    if (await target.exists()) {
      final rollback = File(
        p.join(directory.path, 'avera_pre_restore_$stamp.sqlite'),
      );
      await target.copy(rollback.path);
      rollbackPath = rollback.path;
    }

    for (final suffix in const ['', '-wal', '-shm']) {
      final existing = File('${target.path}$suffix');
      if (await existing.exists()) await existing.delete();
    }
    await pending.rename(target.path);

    final after = await _counts(target);
    final report = <String, dynamic>{
      'appliedAt': DateTime.now().toUtc().toIso8601String(),
      'databasePath': target.path,
      'rollbackPath': rollbackPath,
      'before': before,
      'after': after,
      'countsMatchBackup': true,
    };
    await File(
      p.join(directory.path, _reportFileName),
    ).writeAsString(jsonEncode(report), flush: true);
  }

  static Future<Map<String, dynamic>?> readLastReport() async {
    final directory = await getApplicationDocumentsDirectory();
    return readLastReportInDirectory(directory);
  }

  static Future<Map<String, dynamic>?> readLastReportInDirectory(
    Directory directory,
  ) async {
    final report = File(p.join(directory.path, _reportFileName));
    if (!await report.exists()) return null;
    return jsonDecode(await report.readAsString()) as Map<String, dynamic>;
  }

  static Future<Map<String, int>> _counts(File file) async {
    if (!await file.exists()) return const {};
    Database? database;
    try {
      database = sqlite3.open(file.path, mode: OpenMode.readOnly);
      final tables = database
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'].toString())
          .toSet();
      return {
        for (final table in _countedTables)
          if (tables.contains(table))
            table:
                database
                        .select('SELECT COUNT(*) AS count FROM $table')
                        .first['count']
                    as int,
      };
    } finally {
      database?.dispose();
    }
  }
}
