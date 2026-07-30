import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

class CloudCacheRepository {
  CloudCacheRepository(this._db);
  final AppDatabase _db;

  Future<void> put({
    required String key,
    required String clinicId,
    required Map<String, dynamic> payload,
  }) => _db
      .into(_db.cloudCacheEntries)
      .insertOnConflictUpdate(
        CloudCacheEntriesCompanion.insert(
          cacheKey: key,
          clinicId: clinicId,
          payload: jsonEncode(payload),
          cachedAt: DateTime.now(),
        ),
      );

  Future<Map<String, dynamic>?> get(
    String key, {
    required String clinicId,
  }) async {
    final entry =
        await (_db.select(_db.cloudCacheEntries)..where(
              (row) => row.cacheKey.equals(key) & row.clinicId.equals(clinicId),
            ))
            .getSingleOrNull();
    if (entry == null) return null;
    return Map<String, dynamic>.from(jsonDecode(entry.payload) as Map);
  }

  Future<void> recordEntity({
    required String entityType,
    required String serverId,
    required String clinicId,
    int? revision,
    DateTime? serverUpdatedAt,
    bool deleted = false,
  }) => _db
      .into(_db.cloudEntitySynchronizations)
      .insertOnConflictUpdate(
        CloudEntitySynchronizationsCompanion.insert(
          entityType: entityType,
          serverId: serverId,
          clinicId: clinicId,
          revision: Value(revision),
          serverUpdatedAt: Value(serverUpdatedAt),
          lastSynchronizedAt: DateTime.now(),
          deleted: Value(deleted),
        ),
      );
}
