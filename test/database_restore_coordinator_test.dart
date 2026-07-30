import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:avera/core/database/database_restore_coordinator_native.dart';

void main() {
  test('staged restore preserves rollback and reports record counts', () async {
    final directory = await Directory.systemTemp.createTemp('avera-restore-');
    addTearDown(() => directory.delete(recursive: true));

    final current = File(
      p.join(directory.path, DatabaseRestoreCoordinator.databaseFileName),
    );
    final backup = File(p.join(directory.path, 'exported.sqlite'));
    _createDatabase(current.path, patientCount: 1);
    _createDatabase(backup.path, patientCount: 3);

    await DatabaseRestoreCoordinator.stageInDirectory(backup.path, directory);
    await DatabaseRestoreCoordinator.applyPendingRestoreInDirectory(directory);

    final restored = sqlite3.open(current.path, mode: OpenMode.readOnly);
    addTearDown(restored.dispose);
    expect(
      restored.select('SELECT COUNT(*) AS count FROM animals').first['count'],
      3,
    );

    final report = await DatabaseRestoreCoordinator.readLastReportInDirectory(
      directory,
    );
    expect(report?['before'], containsPair('animals', 1));
    expect(report?['after'], containsPair('animals', 3));
    expect(
      directory.listSync().whereType<File>().any(
        (file) => p.basename(file.path).startsWith('avera_pre_restore_'),
      ),
      isTrue,
    );
  });
}

void _createDatabase(String path, {required int patientCount}) {
  final database = sqlite3.open(path);
  try {
    database.execute('CREATE TABLE clinics (clinic_id TEXT, clinic_name TEXT)');
    database.execute('CREATE TABLE users (user_id TEXT)');
    database.execute('CREATE TABLE animals (id INTEGER)');
    database.execute("INSERT INTO clinics VALUES ('clinic-a', 'Clinic A')");
    database.execute("INSERT INTO users VALUES ('user-a')");
    for (var index = 0; index < patientCount; index++) {
      database.execute('INSERT INTO animals VALUES (?)', [index + 1]);
    }
    database.execute('PRAGMA user_version = 15');
  } finally {
    database.dispose();
  }
}
