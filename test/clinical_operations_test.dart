import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';

void main() {
  late AppDatabase database;
  late ClinicRepository repository;
  late UserSession session;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ClinicRepository(database);
    await repository.seedSampleData();
    session = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
  });

  tearDown(() => database.close());

  test('development samples cover every clinical operation module', () async {
    await repository.seedClinicalOperationDemoData();

    for (final type in const [
      ClinicalOperationTypes.surgery,
      ClinicalOperationTypes.prescription,
      ClinicalOperationTypes.imaging,
      ClinicalOperationTypes.document,
      ClinicalOperationTypes.treatment,
    ]) {
      final records = await repository
          .watchClinicalOperationRecords(type)
          .first;
      expect(records, isNotEmpty, reason: 'Missing sample for $type');
      expect(records.single.operation.clinicId, defaultClinicId);
      expect(records.single.animal.id, records.single.operation.animalId);
      final detail = await repository.getClinicalOperationDetail(
        session,
        records.single.operation.id,
      );
      expect(detail, isNotNull);
      if ({
        ClinicalOperationTypes.prescription,
        ClinicalOperationTypes.treatment,
      }.contains(type)) {
        expect(detail!.items, isNotEmpty);
      }
    }
  });

  test('surgery follows its guarded status workflow and audits it', () async {
    final animal = (await database.select(database.animals).get()).first;
    final id = await repository.createClinicalOperation(
      session: session,
      animalId: animal.id,
      operationType: ClinicalOperationTypes.surgery,
      title: 'Wound debridement',
      description: 'Prepare the surgical site and obtain owner consent.',
      assignedTo: 'Dr. Amina Okafor',
      scheduledAt: DateTime(2026, 8, 1, 9),
    );

    for (final status in const [
      'Scheduled',
      'Pre-operative',
      'Ready for Surgery',
      'In Progress',
      'Recovery',
      'Completed',
    ]) {
      await repository.updateClinicalOperationStatus(
        session: session,
        operationId: id,
        status: status,
      );
    }

    final stored = await (database.select(
      database.clinicalOperationRecords,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(stored.status, 'Completed');
    expect(stored.completedAt, isNotNull);
    final audit = await repository.watchClinicAuditLogs(session).first;
    expect(
      audit
          .where((entry) => entry.entityId == '$id')
          .map((entry) => entry.action),
      containsAll(['surgery_created', 'surgery_status_changed']),
    );
  });

  test(
    'prescription dispensing is partial then complete and updates stock billing',
    () async {
      final animal = (await database.select(database.animals).get()).first;
      final inventory = (await database.select(database.inventoryItems).get())
          .firstWhere(
            (item) =>
                item.quantity >= 4 &&
                item.isSellable &&
                (item.expiryDate == null ||
                    item.expiryDate!.isAfter(DateTime.now())),
          );
      final before = inventory.quantity;
      final id = await repository.createClinicalOperation(
        session: session,
        animalId: animal.id,
        operationType: ClinicalOperationTypes.prescription,
        title: 'Post-operative analgesia',
        status: 'Active',
        items: [
          ClinicalMedicationDraft(
            name: inventory.drugName,
            inventoryItemId: inventory.id,
            quantity: 4,
            unit: 'tablets',
            dose: '1 tablet',
            route: 'Oral',
            frequency: 'Twice daily',
            duration: '2 days',
          ),
        ],
      );
      final detail = await repository.getClinicalOperationDetail(session, id);
      final item = detail!.items.single;

      await repository.dispensePrescriptionItem(
        session: session,
        operationId: id,
        operationItemId: item.id,
        quantity: 2,
      );
      var stored = await (database.select(
        database.clinicalOperationRecords,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(stored.status, 'Partially Dispensed');

      await repository.dispensePrescriptionItem(
        session: session,
        operationId: id,
        operationItemId: item.id,
        quantity: 2,
      );
      stored = await (database.select(
        database.clinicalOperationRecords,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(stored.status, 'Dispensed');
      expect(
        (await (database.select(
          database.inventoryItems,
        )..where((row) => row.id.equals(inventory.id))).getSingle()).quantity,
        before - 4,
      );
      expect(
        await (database.select(database.invoices)
              ..where((row) => row.linkedClinicalOperationId.equals(id)))
            .getSingleOrNull(),
        isNotNull,
      );
      expect(
        () => repository.dispensePrescriptionItem(
          session: session,
          operationId: id,
          operationItemId: item.id,
          quantity: 1,
        ),
        throwsStateError,
      );
    },
  );

  test('treatment cannot be administered twice', () async {
    final animal = (await database.select(database.animals).get()).first;
    final id = await repository.createClinicalOperation(
      session: session,
      animalId: animal.id,
      operationType: ClinicalOperationTypes.treatment,
      title: 'Wound cleaning',
      status: 'Due',
      items: const [
        ClinicalMedicationDraft(
          name: 'Sterile saline',
          quantity: 1,
          unit: 'bottle',
        ),
      ],
    );
    final item = (await repository.getClinicalOperationDetail(
      session,
      id,
    ))!.items.single;
    await repository.recordTreatmentAction(
      session: session,
      operationId: id,
      operationItemId: item.id,
      status: 'Administered',
      patientResponse: 'Tolerated well.',
    );
    expect(
      () => repository.recordTreatmentAction(
        session: session,
        operationId: id,
        operationItemId: item.id,
        status: 'Administered',
      ),
      throwsStateError,
    );
  });
}
