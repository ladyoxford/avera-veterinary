import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

enum OfflineSyncStatus { pending, syncing, synced, conflict, failed, cancelled }

extension OfflineSyncStatusValue on OfflineSyncStatus {
  String get value => switch (this) {
        OfflineSyncStatus.pending => 'Pending',
        OfflineSyncStatus.syncing => 'Syncing',
        OfflineSyncStatus.synced => 'Synced',
        OfflineSyncStatus.conflict => 'Conflict',
        OfflineSyncStatus.failed => 'Failed',
        OfflineSyncStatus.cancelled => 'Cancelled',
      };
}

/// The sync journal never applies remote changes without an authenticated
/// server acknowledgement. This prevents offline writes being treated as
/// synced merely because connectivity changed.
class OfflineSyncRepository {
  OfflineSyncRepository(this._db);
  final AppDatabase _db;
  final _uuid = const Uuid();

  Future<void> enqueue({
    required String clinicId,
    required String userId,
    required String deviceId,
    required String entityType,
    required String entityId,
    required String operationType,
    required Map<String, dynamic> payload,
    int baseVersion = 0,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.into(_db.syncOperations).insert(
          SyncOperationsCompanion.insert(
            operationId: _uuid.v4(),
            clinicId: clinicId,
            userId: userId,
            deviceId: deviceId,
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            localTimestamp: now,
            baseVersion: Value(baseVersion),
            payload: jsonEncode(payload),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Stream<List<SyncOperation>> watchPending(String clinicId) =>
      (_db.select(_db.syncOperations)
            ..where((row) =>
                row.clinicId.equals(clinicId) &
                row.syncStatus.equals(OfflineSyncStatus.pending.value))
            ..orderBy([(row) => OrderingTerm.asc(row.localTimestamp)]))
          .watch();

  Future<int> pendingCount(String clinicId) async =>
      (_db.select(_db.syncOperations)
            ..where((row) =>
                row.clinicId.equals(clinicId) &
                row.syncStatus.equals(OfflineSyncStatus.pending.value)))
          .get()
          .then((rows) => rows.length);

  Future<void> markFailed(String operationId, String message) =>
      (_db.update(_db.syncOperations)..where((row) => row.operationId.equals(operationId)))
          .write(SyncOperationsCompanion(
        syncStatus: Value(OfflineSyncStatus.failed.value),
        lastError: Value(message),
        updatedAt: Value(DateTime.now().toUtc()),
      ));

  Future<void> markSyncing(String operationId) =>
      (_db.update(_db.syncOperations)..where((row) => row.operationId.equals(operationId)))
          .write(SyncOperationsCompanion(
        syncStatus: Value(OfflineSyncStatus.syncing.value),
        updatedAt: Value(DateTime.now().toUtc()),
      ));

  Future<void> markSynced(String operationId) =>
      (_db.update(_db.syncOperations)..where((row) => row.operationId.equals(operationId)))
          .write(SyncOperationsCompanion(
        syncStatus: Value(OfflineSyncStatus.synced.value),
        lastError: const Value(null),
        updatedAt: Value(DateTime.now().toUtc()),
      ));

  Future<List<SyncOperation>> pending(String clinicId) =>
      (_db.select(_db.syncOperations)
            ..where((row) =>
                row.clinicId.equals(clinicId) &
                row.syncStatus.equals(OfflineSyncStatus.pending.value))
            ..orderBy([(row) => OrderingTerm.asc(row.localTimestamp)]))
          .get();
}
