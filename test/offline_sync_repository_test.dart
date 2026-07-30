import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/offline_sync_repository.dart';

void main() {
  test(
    'offline operations are tenant-scoped and remain pending until acknowledged',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database
          .into(database.clinics)
          .insert(
            ClinicsCompanion.insert(
              clinicId: 'clinic-a',
              clinicName: 'Clinic A',
              dateRegistered: DateTime.now(),
            ),
          );
      await database
          .into(database.clinics)
          .insert(
            ClinicsCompanion.insert(
              clinicId: 'clinic-b',
              clinicName: 'Clinic B',
              dateRegistered: DateTime.now(),
            ),
          );
      final queue = OfflineSyncRepository(database);
      await queue.enqueue(
        clinicId: 'clinic-a',
        userId: 'user-a',
        deviceId: 'device-a',
        entityType: 'patient',
        entityId: 'local-1',
        operationType: 'create',
        payload: const {'name': 'Bella'},
      );

      expect(await queue.pendingCount('clinic-a'), 1);
      expect(await queue.pendingCount('clinic-b'), 0);
      final operation = (await queue.pending('clinic-a')).single;
      await queue.markSynced(operation.operationId);
      expect(await queue.pendingCount('clinic-a'), 0);
    },
  );
}
