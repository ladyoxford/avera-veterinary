import 'dart:convert';

import '../remote/api_client.dart';
import '../repositories/offline_sync_repository.dart';
import 'offline_authorization_service.dart';

class OfflineSyncResult {
  const OfflineSyncResult({required this.synced, required this.failed, required this.conflicts});
  final int synced;
  final int failed;
  final int conflicts;
}

/// Uploads the local operation journal only after the normal bearer-session
/// validation succeeds. The server currently journals accepted operations;
/// applying clinical payloads awaits the dedicated clinical data APIs.
class OfflineSyncCoordinator {
  OfflineSyncCoordinator({required ApiClient apiClient, required OfflineSyncRepository queue})
      : _apiClient = apiClient,
        _queue = queue;

  final ApiClient _apiClient;
  final OfflineSyncRepository _queue;

  Future<OfflineSyncResult> synchronize(OfflineAuthorizationSnapshot snapshot) async {
    if (snapshot.clinicId == null) return const OfflineSyncResult(synced: 0, failed: 0, conflicts: 0);
    await _apiClient.get('/api/v1/auth/me');
    var synced = 0;
    var failed = 0;
    var conflicts = 0;
    for (final operation in await _queue.pending(snapshot.clinicId!)) {
      await _queue.markSyncing(operation.operationId);
      try {
        await _apiClient.post('/api/v1/sync/operations', authenticated: true, body: {
          'operationId': operation.operationId,
          'clinicId': operation.clinicId,
          'userId': operation.userId,
          'deviceId': operation.deviceId,
          'entityType': operation.entityType,
          'entityId': operation.entityId,
          'operationType': operation.operationType,
          'localTimestamp': operation.localTimestamp.toUtc().toIso8601String(),
          'baseVersion': operation.baseVersion,
          'payload': jsonDecode(operation.payload),
        });
        await _queue.markSynced(operation.operationId);
        synced++;
      } on ApiException catch (error) {
        if (error.code == 'conflict') conflicts++;
        await _queue.markFailed(operation.operationId, error.message);
        failed++;
      }
    }
    return OfflineSyncResult(synced: synced, failed: failed, conflicts: conflicts);
  }
}
