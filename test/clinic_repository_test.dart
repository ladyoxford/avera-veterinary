import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/models/alert_destination.dart';
import 'package:avera/core/models/animal_catalogue.dart';
import 'package:avera/core/models/vaccine_catalogue.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';

void main() {
  test(
    'appointments stay clinic-scoped with persisted reminder settings',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      final patient = (await database.select(database.animals).get()).first;
      final scheduledAt = DateTime.now().add(const Duration(days: 10));

      final appointment = await repository.createAppointment(
        session: session!,
        animalId: patient.id,
        scheduledAt: scheduledAt,
        appointmentType: 'Vaccination',
        enabledReminderDays: const {7, 1},
      );
      final detail = await repository.getAppointmentDetail(appointment.id);

      expect(detail, isNot(equals(null)));
      expect(detail!.appointment.clinicId, defaultClinicId);
      expect(detail.appointment.reference, startsWith('APT-'));
      expect(
        detail.reminders.map((item) => item.daysBefore),
        containsAll([7, 3, 1]),
      );
      expect(
        detail.reminders.singleWhere((item) => item.daysBefore == 3).enabled,
        isFalse,
      );

      final newTime = scheduledAt.add(const Duration(days: 2));
      final rescheduled = await repository.rescheduleAppointment(
        session: session,
        appointmentId: appointment.id,
        scheduledAt: newTime,
        appointmentType: 'Follow-up',
        notes: 'Client requested another date.',
        reason: 'Client requested another date',
        enabledReminderDays: const {3, 1},
      );
      expect(rescheduled.id, appointment.id);
      expect(rescheduled.animalId, appointment.animalId);
      expect(
        rescheduled.appointmentDate,
        DateTime(
          newTime.year,
          newTime.month,
          newTime.day,
          newTime.hour,
          newTime.minute,
          newTime.second,
        ),
      );
      expect(rescheduled.purpose, 'Follow-up');
      final rescheduledDetail = await repository.getAppointmentDetail(
        appointment.id,
      );
      expect(
        rescheduledDetail!.reminders
            .singleWhere((item) => item.daysBefore == 7)
            .enabled,
        isFalse,
      );
      expect(
        (await repository.watchClinicAuditLogs(session).first).any(
          (entry) => entry.action == 'appointment.rescheduled',
        ),
        isTrue,
      );
      final activity = await repository.getClinicActivityPage(
        search: 'Appointment rescheduled',
      );
      final appointmentActivity = activity.singleWhere(
        (event) => event.type == 'appointmentRescheduled',
      );
      expect(appointmentActivity.relatedEntityType, 'Appointment');
      expect(appointmentActivity.relatedEntityId, appointment.id.toString());
      expect(appointmentActivity.description, contains('to '));
      expect(appointmentActivity.description, isNot(contains('T')));
      final history = await repository.getAppointmentRescheduleHistory(
        appointment.id,
      );
      expect(history, hasLength(1));
      expect(
        DateTime(
          history.single.newDate.year,
          history.single.newDate.month,
          history.single.newDate.day,
          history.single.newDate.hour,
          history.single.newDate.minute,
          history.single.newDate.second,
        ),
        rescheduled.appointmentDate,
      );

      await repository.cancelAppointment(
        session: session,
        appointmentId: appointment.id,
      );
      final cancelled = await repository.getAppointmentDetail(appointment.id);
      expect(
        AppointmentStatuses.normalize(cancelled!.appointment.status),
        AppointmentStatuses.cancelled,
      );
      expect(
        cancelled.reminders.every((item) => item.scheduledFor == null),
        isTrue,
      );
      final schedule = await repository.watchAppointments().first;
      expect(
        AppointmentStatuses.normalize(
          schedule.singleWhere((item) => item.id == appointment.id).status,
        ),
        AppointmentStatuses.cancelled,
      );
    },
  );

  test(
    'farm daily records reconcile population and remain clinic scoped',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );

      final farm = await repository.createFarm(
        session: session!,
        name: 'Udeogalanya Livestock Farm',
        location: 'Ogidi, Anambra State',
        speciesIds: const ['species_cattle', 'species_goat'],
        breedIds: const [
          'breed_cattle_white_fulani',
          'breed_goat_west_african_dwarf',
        ],
      );
      await repository.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Sector A',
        unitType: 'Sector',
        capacity: 12,
        maleCount: 4,
        femaleCount: 6,
      );
      final record = await repository.saveFarmDailyRecord(
        session: session,
        farmId: farm.id,
        recordDate: DateTime(2026, 7, 26),
        openingPopulation: 10,
        births: 2,
        mortality: 1,
        feedSuppliedKg: 145,
        finalize: true,
      );
      expect(record.closingPopulation, 11);
      expect(record.status, 'Finalized');

      final dashboard = await repository.getFarmDashboard(farm.id);
      expect(dashboard?.farm.clinicId, session.clinic.clinicId);
      expect(dashboard?.units, hasLength(1));
      expect(dashboard?.dailyRecords.single.id, record.id);
      expect(
        await repository.getClinicActivityPage(search: 'Daily farm record'),
        isNotEmpty,
      );
    },
  );

  test(
    'farm species movements reconcile independently and corrections preserve history',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      expect(session, isNot(equals(null)));

      final farm = await repository.createFarm(
        session: session!,
        name: 'Species Reconciliation Farm',
        speciesIds: const ['species_cattle', 'species_goat'],
        breedIds: const [],
      );
      await repository.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Cattle Paddock',
        unitType: 'Paddock',
        speciesId: 'species_cattle',
        maleCount: 2,
        femaleCount: 8,
      );
      await repository.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Goat Pen',
        unitType: 'Pen',
        speciesId: 'species_goat',
        maleCount: 1,
        femaleCount: 3,
      );

      final recordDate = DateTime(2026, 7, 26);
      final original = await repository.saveFarmDailyRecord(
        session: session,
        farmId: farm.id,
        recordDate: recordDate,
        openingPopulation: 14,
        mortality: 1,
        speciesMovements: const [
          FarmSpeciesMovementInput(
            speciesId: 'species_cattle',
            openingPopulation: 10,
            births: 1,
          ),
          FarmSpeciesMovementInput(
            speciesId: 'species_goat',
            openingPopulation: 4,
            mortality: 1,
          ),
        ],
        finalize: true,
      );
      expect(original.closingPopulation, 14);
      final movements = await repository.getFarmSpeciesMovementsForRecord(
        original.id,
      );
      expect(
        movements
            .singleWhere((item) => item.speciesId == 'species_cattle')
            .closingPopulation,
        11,
      );
      expect(
        movements
            .singleWhere((item) => item.speciesId == 'species_goat')
            .closingPopulation,
        3,
      );

      await expectLater(
        repository.saveFarmDailyRecord(
          session: session,
          farmId: farm.id,
          recordDate: recordDate,
          openingPopulation: 14,
          speciesMovements: const [
            FarmSpeciesMovementInput(
              speciesId: 'species_cattle',
              openingPopulation: 10,
            ),
            FarmSpeciesMovementInput(
              speciesId: 'species_goat',
              openingPopulation: 4,
            ),
          ],
          finalize: true,
        ),
        throwsA(isA<StateError>()),
      );

      final corrected = await repository.saveFarmDailyRecord(
        session: session,
        farmId: farm.id,
        recordDate: recordDate,
        openingPopulation: 14,
        mortality: 1,
        speciesMovements: const [
          FarmSpeciesMovementInput(
            speciesId: 'species_cattle',
            openingPopulation: 10,
            births: 2,
          ),
          FarmSpeciesMovementInput(
            speciesId: 'species_goat',
            openingPopulation: 4,
            mortality: 1,
          ),
        ],
        correctionReason: 'Corrected one omitted cattle birth.',
        finalize: true,
      );
      expect(corrected.id, original.id);
      expect(corrected.closingPopulation, 15);
      expect(corrected.originalSnapshotJson, contains('"births":1'));
      expect(
        await (database.select(database.farmDailyRecords)..where(
              (row) =>
                  row.farmId.equals(farm.id) &
                  row.recordDate.equals(recordDate),
            ))
            .get(),
        hasLength(1),
      );

      final dashboard = await repository.getFarmDashboard(farm.id);
      expect(dashboard?.populationBySpecies, {
        'species_cattle': 10,
        'species_goat': 4,
      });
    },
  );

  test(
    'farm unit treatments persist clinical details and enforce population',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;

      final farm = await repository.createFarm(
        session: session,
        name: 'Treatment Test Farm',
        speciesIds: const ['species_goat'],
        breedIds: const ['breed_goat_red_sokoto'],
      );
      final unit = await repository.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Goat Pen',
        unitType: 'Pen',
        speciesId: 'species_goat',
        breedId: 'breed_goat_red_sokoto',
        capacity: 13,
        maleCount: 3,
        femaleCount: 10,
      );
      final administeredAt = DateTime(2026, 8, 1);
      final nextDueAt = DateTime(2026, 12, 1);

      final treatment = await repository.recordFarmUnitTreatment(
        session: session,
        farmId: farm.id,
        unitId: unit.id,
        treatmentType: 'Vaccination',
        product: 'CDT',
        administeredAt: administeredAt,
        animalsCovered: 13,
        manufacturer: 'Veterinary Biologics',
        batchNumber: 'CDT-2608',
        dose: '2 ml',
        route: 'Subcutaneous',
        nextDueDate: nextDueAt,
        notes: 'Whole-pen vaccination.',
      );

      expect(treatment.clinicId, session.clinic.clinicId);
      expect(treatment.farmId, farm.id);
      expect(treatment.farmUnitId, unit.id);
      expect(treatment.eventType, 'Vaccination');
      expect(treatment.product, 'CDT');
      expect(treatment.animalsCovered, 13);
      expect(treatment.administeredBy, session.user.fullName);
      expect(treatment.manufacturer, 'Veterinary Biologics');
      expect(treatment.batchNumber, 'CDT-2608');
      expect(treatment.nextDueDate, nextDueAt);
      expect(
        await repository.getFarmUnitTreatments(
          farmId: farm.id,
          unitId: unit.id,
        ),
        hasLength(1),
      );
      expect(
        await (database.select(database.auditLogs)..where(
              (row) => row.action.equals('farm.unit_treatment_recorded'),
            ))
            .get(),
        hasLength(1),
      );

      await expectLater(
        repository.recordFarmUnitTreatment(
          session: session,
          farmId: farm.id,
          unitId: unit.id,
          treatmentType: 'Deworming',
          product: 'Albendazole',
          administeredAt: administeredAt,
          animalsCovered: 14,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'mixed farm unit populations aggregate and treatments target selected groups',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final farm = await repository.createFarm(
        session: session,
        name: 'Mixed Population Farm',
        speciesIds: const ['species_goat', 'species_sheep'],
      );

      final unit = await repository.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Mixed Small Ruminants',
        unitType: 'Pen',
        capacity: 20,
        populations: const [
          FarmUnitPopulationInput(
            speciesId: 'species_goat',
            breedId: 'breed_goat_red_sokoto',
            maleCount: 2,
            femaleCount: 6,
          ),
          FarmUnitPopulationInput(
            speciesId: 'species_sheep',
            breedId: 'breed_sheep_yankasa',
            maleCount: 1,
            femaleCount: 4,
          ),
        ],
      );

      expect(unit.speciesId, equals(null));
      expect(unit.maleCount, 3);
      expect(unit.femaleCount, 10);
      final populations = await repository.getFarmUnitPopulations(
        farmId: farm.id,
        unitId: unit.id,
      );
      expect(populations, hasLength(2));
      expect(populations.fold<int>(0, (sum, item) => sum + item.total), 13);
      final goatGroup = populations.singleWhere(
        (item) => item.speciesId == 'species_goat',
      );

      final treatment = await repository.recordFarmUnitTreatment(
        session: session,
        farmId: farm.id,
        unitId: unit.id,
        treatmentType: 'Deworming',
        product: 'Albendazole',
        administeredAt: DateTime(2026, 8, 1),
        animalsCovered: 8,
        targetScope: 'SelectedGroups',
        targetPopulationIds: {goatGroup.id},
      );
      expect(treatment.targetScope, 'SelectedGroups');
      expect(treatment.targetPopulationIdsJson, '[${goatGroup.id}]');

      await expectLater(
        repository.recordFarmUnitTreatment(
          session: session,
          farmId: farm.id,
          unitId: unit.id,
          treatmentType: 'Deworming',
          product: 'Albendazole',
          administeredAt: DateTime(2026, 8, 1),
          animalsCovered: 9,
          targetScope: 'SelectedGroups',
          targetPopulationIds: {goatGroup.id},
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'farm invoices preserve unselected treatments and prevent duplicate billing',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final farm = await repository.createFarm(
        session: session,
        name: 'Invoice Test Farm',
        ownerOrganization: 'Invoice Test Client',
        contactNumber: '08030000000',
        speciesIds: const ['species_goat', 'species_sheep'],
      );
      final goatUnit = await repository.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Goat Pen',
        unitType: 'Pen',
        speciesId: 'species_goat',
        capacity: 13,
        maleCount: 3,
        femaleCount: 10,
      );
      final sheepUnit = await repository.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Sheep Pen',
        unitType: 'Pen',
        speciesId: 'species_sheep',
        capacity: 8,
        maleCount: 3,
        femaleCount: 5,
      );
      final visitDate = DateTime.now().subtract(const Duration(days: 1));
      final goatTreatment = await repository.recordFarmUnitTreatment(
        session: session,
        farmId: farm.id,
        unitId: goatUnit.id,
        treatmentType: 'Deworming',
        product: 'Albendazole',
        administeredAt: visitDate,
        animalsCovered: 13,
        billableAmount: 26000,
      );
      final sheepTreatment = await repository.recordFarmUnitTreatment(
        session: session,
        farmId: farm.id,
        unitId: sheepUnit.id,
        treatmentType: 'Pour-On',
        product: 'Ivermectin',
        administeredAt: visitDate,
        animalsCovered: 8,
        billableAmount: 16000,
      );

      final treatmentActivities =
          await (database.select(database.clinicActivityEvents)..where(
                (event) =>
                    event.clinicId.equals(session.clinic.clinicId) &
                    event.type.equals('farmTreatmentRecorded') &
                    event.relatedEntityId.equals(farm.id),
              ))
              .get();
      expect(treatmentActivities, hasLength(2));
      expect(
        treatmentActivities.map((activity) => activity.id).toSet(),
        hasLength(2),
      );

      expect(
        await repository.getFarmInvoiceCandidates(
          session: session,
          farmId: farm.id,
          visitDate: visitDate,
        ),
        hasLength(2),
      );
      final invoice = await repository.saveFarmInvoiceDraft(
        session: session,
        farmId: farm.id,
        visitDate: visitDate,
        treatmentRecordIds: {goatTreatment.id},
        sharedFarmFee: 5000,
        sharedFeeDescription: 'Farm call-out fee',
      );
      expect(invoice.invoice.contextType, 'farm_visit');
      expect(invoice.invoice.farmId, farm.id);
      expect(invoice.invoice.animalId, equals(null));
      expect(invoice.invoice.total, 31000);
      expect(invoice.services, hasLength(2));
      expect(
        invoice.services
            .singleWhere((line) => line.sourceTreatmentRecordId != null)
            .sourceTreatmentRecordId,
        goatTreatment.id,
      );
      expect(
        invoice.services
            .singleWhere((line) => line.sourceTreatmentRecordId == null)
            .description,
        'Farm call-out fee',
      );

      final remaining = await repository.getFarmInvoiceCandidates(
        session: session,
        farmId: farm.id,
        visitDate: visitDate,
      );
      expect(remaining.map((candidate) => candidate.record.id), [
        sheepTreatment.id,
      ]);
      expect(
        await repository.getFarmUnitTreatments(
          farmId: farm.id,
          unitId: sheepUnit.id,
        ),
        hasLength(1),
      );
      await expectLater(
        repository.saveFarmInvoiceDraft(
          session: session,
          farmId: farm.id,
          visitDate: visitDate,
          treatmentRecordIds: {goatTreatment.id},
        ),
        throwsA(isA<StateError>()),
      );

      await repository.issueInvoice(
        session: session,
        invoiceId: invoice.invoice.id,
      );
      await repository.recordInvoicePayment(
        session: session,
        invoiceId: invoice.invoice.id,
        amount: invoice.invoice.total,
        paymentMethod: 'Cash',
        paidAt: visitDate,
      );
      final history = await repository.watchBillingHistory(session).first;
      final historyEntry = history.singleWhere(
        (entry) => entry.invoice.id == invoice.invoice.id,
      );
      expect(historyEntry.farm?.id, farm.id);
      expect(historyEntry.animal, equals(null));
      final revenue = await repository.getRevenueProfitSummary(
        session: session,
      );
      expect(revenue.farmRevenue, 31000);
      expect(revenue.clinicRevenue, 0);
    },
  );

  test(
    'farm invoice supports unlimited manual services and unit-targeted products',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final farm = await repository.createFarm(
        session: session,
        name: 'Manual Services Farm',
        ownerOrganization: 'Manual Services Client',
        speciesIds: const ['species_cattle'],
      );
      final unit = await repository.createFarmUnit(
        session: session,
        farmId: farm.id,
        name: 'Cattle Pen',
        unitType: 'Pen',
        speciesId: 'species_cattle',
        capacity: 12,
        femaleCount: 12,
      );
      final item = (await database.select(database.inventoryItems).get()).first;
      await (database.update(
        database.inventoryItems,
      )..where((row) => row.id.equals(item.id))).write(
        const InventoryItemsCompanion(
          quantity: Value(20),
          sellingPrice: Value(4000),
          isSellable: Value(true),
          isArchived: Value(false),
        ),
      );

      final invoice = await repository.saveFarmInvoiceDraft(
        session: session,
        farmId: farm.id,
        visitDate: DateTime(2026, 8, 24),
        treatmentRecordIds: const {},
        products: [
          InvoiceProductDraft(
            inventoryItemId: item.id,
            quantity: 2,
            farmUnitId: unit.id,
          ),
        ],
        services: [
          for (var index = 1; index <= 5; index++)
            FarmInvoiceServiceDraft(
              description: 'Professional service $index',
              amount: index * 1000,
              farmUnitId: index.isEven ? unit.id : null,
            ),
        ],
      );

      expect(invoice.invoice.contextType, 'farm_visit');
      expect(invoice.invoice.farmId, farm.id);
      expect(invoice.services, hasLength(5));
      expect(invoice.products, hasLength(1));
      expect(invoice.products.single.farmUnitId, unit.id);
      expect(invoice.farmUnits.map((value) => value.id), contains(unit.id));
      expect(invoice.invoice.servicesSubtotal, 15000);
      expect(invoice.invoice.productsSubtotal, 8000);
      expect(invoice.invoice.total, 23000);

      await repository.issueInvoice(
        session: session,
        invoiceId: invoice.invoice.id,
      );
      await repository.recordInvoicePayment(
        session: session,
        invoiceId: invoice.invoice.id,
        amount: 5000,
        paymentMethod: 'Transfer',
        paidAt: DateTime(2026, 8, 24),
      );
      final history = await repository.watchBillingHistory(session).first;
      final entry = history.singleWhere(
        (value) => value.invoice.id == invoice.invoice.id,
      );
      expect(entry.farm?.id, farm.id);
      expect(entry.invoice.status, 'Partially paid');
      expect(entry.invoice.balance, 18000);
      final revenue = await repository.getRevenueProfitSummary(
        session: session,
      );
      expect(revenue.farmRevenue, 5000);
      expect(revenue.clinicRevenue, 0);
    },
  );

  test(
    'product units derive every package count from one base stock',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final item = (await database.select(database.inventoryItems).get()).first;
      await (database.update(database.inventoryItems)
            ..where((row) => row.id.equals(item.id)))
          .write(const InventoryItemsCompanion(quantity: Value(84)));

      await repository.replaceProductUnits(
        session: session,
        inventoryItemId: item.id,
        units: const [
          (
            label: 'Vial',
            conversionToBase: 1,
            sellingPrice: 3200.0,
            isBase: true,
          ),
          (
            label: 'Box',
            conversionToBase: 10,
            sellingPrice: 30000.0,
            isBase: false,
          ),
          (
            label: 'Carton',
            conversionToBase: 100,
            sellingPrice: 280000.0,
            isBase: false,
          ),
        ],
      );
      final units = await repository
          .watchProductUnits(session: session, inventoryItemId: item.id)
          .first;
      expect(units, hasLength(3));
      expect(units.where((unit) => unit.isBaseUnit), hasLength(1));
      expect(
        ClinicRepository.displayedStockForUnit(
          baseStock: 84,
          conversionToBase: 1,
        ),
        84,
      );
      expect(
        ClinicRepository.displayedStockForUnit(
          baseStock: 84,
          conversionToBase: 10,
        ),
        8,
      );
      expect(
        ClinicRepository.displayedStockForUnit(
          baseStock: 84,
          conversionToBase: 100,
        ),
        0,
      );
      expect(
        ClinicRepository.displayedStockForUnit(
          baseStock: 74,
          conversionToBase: 10,
        ),
        7,
      );
      await expectLater(
        repository.replaceProductUnits(
          session: session,
          inventoryItemId: item.id,
          units: const [
            (
              label: 'Box',
              conversionToBase: 10,
              sellingPrice: 30000.0,
              isBase: true,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'Add Stock increases the current total and records one ledger entry',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final item = (await database.select(database.inventoryItems).get()).first;
      await (database.update(database.inventoryItems)
            ..where((row) => row.id.equals(item.id)))
          .write(const InventoryItemsCompanion(quantity: Value(2)));
      final unitsBefore = await repository
          .watchProductUnits(session: session, inventoryItemId: item.id)
          .first;

      final updated = await repository.addInventoryStock(
        session: session,
        itemId: item.id,
        quantityToAdd: 10,
        batchNumber: 'TOP-UP-10',
        expiryDate: DateTime(2028, 8, 1),
        buyingPrice: 1250,
      );

      expect(updated.quantity, 12);
      expect(updated.batchNumber, 'TOP-UP-10');
      expect(updated.buyingPrice, 1250);
      final movement =
          (await database.select(database.inventoryStockMovements).get())
              .singleWhere((entry) => entry.movementType == 'Stock Added');
      expect(movement.quantityBefore, 2);
      expect(movement.quantityChange, 10);
      expect(movement.quantityAfter, 12);
      final unitsAfter = await repository
          .watchProductUnits(session: session, inventoryItemId: item.id)
          .first;
      expect(unitsAfter.length, unitsBefore.length);
    },
  );

  test('paid invoice deducts stock once and void restores it once', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );
    final patient = (await database.select(database.animals).get()).first;
    final item = (await database.select(database.inventoryItems).get()).first;
    final originalQuantity = item.quantity;
    final draft = await repository.saveInvoiceDraft(
      session: session!,
      animalId: patient.id,
      products: [InvoiceProductDraft(inventoryItemId: item.id, quantity: 1)],
      services: const [],
      consultationFee: 0,
      homeServiceFee: 0,
    );
    expect(
      (await database.select(database.inventoryItems).get()).first.quantity,
      originalQuantity,
    );
    await repository.payInvoice(session: session, invoiceId: draft.invoice.id);
    final paidItem = await (database.select(
      database.inventoryItems,
    )..where((row) => row.id.equals(item.id))).getSingle();
    expect(paidItem.quantity, originalQuantity - 1);
    expect(
      (await database.select(database.inventoryStockMovements).get())
          .single
          .movementType,
      'Sale',
    );
    await repository.voidInvoice(
      session: session,
      invoiceId: draft.invoice.id,
      reason: 'Payment reversed for test',
    );
    final restoredItem = await (database.select(
      database.inventoryItems,
    )..where((row) => row.id.equals(item.id))).getSingle();
    expect(restoredItem.quantity, originalQuantity);
  });

  test('billing history reconciles partial payments and refunds', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    final patient = (await database.select(database.animals).get()).first;
    final draft = await repository.saveInvoiceDraft(
      session: session,
      animalId: patient.id,
      products: const [],
      services: const [
        InvoiceServiceDraft(description: 'Imaging report', amount: 100),
      ],
      consultationFee: 0,
      homeServiceFee: 0,
    );
    expect(draft.invoice.status, 'Draft');

    final issued = await repository.issueInvoice(
      session: session,
      invoiceId: draft.invoice.id,
    );
    expect(issued.invoice.status, 'Unpaid');
    expect(issued.invoice.balance, 100);

    var detail = await repository.recordInvoicePayment(
      session: session,
      invoiceId: draft.invoice.id,
      amount: 40,
      paymentMethod: 'Transfer',
      paidAt: DateTime(2026, 8, 21, 9, 30),
      reference: 'TRX-LOCAL-1',
    );
    expect(detail.invoice.status, 'Partially paid');
    expect(detail.invoice.amountPaid, 40);
    expect(detail.invoice.balance, 60);
    expect(detail.payments.single.transactionType, 'Payment');
    expect(detail.payments.single.paymentMethod, 'Transfer');
    expect(detail.payments.single.reason, 'TRX-LOCAL-1');

    detail = await repository.refundInvoicePayment(
      session: session,
      invoiceId: draft.invoice.id,
      amount: 10,
      reason: 'Duplicate service charge',
    );
    expect(detail.invoice.refundTotal, 10);
    expect(detail.invoice.balance, 70);
    expect(detail.payments.length, 2);
    expect(
      detail.payments.map((payment) => payment.transactionType),
      containsAll(['Payment', 'Refund']),
    );

    final history = await repository.watchBillingHistory(session).first;
    expect(
      history.where((entry) => entry.invoice.id == draft.invoice.id),
      hasLength(1),
    );
  });

  test('revenue summary uses paid ledger and immutable product cost', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    final patient = (await database.select(database.animals).get()).first;
    final item = (await database.select(database.inventoryItems).get()).first;
    await (database.update(
      database.inventoryItems,
    )..where((row) => row.id.equals(item.id))).write(
      const InventoryItemsCompanion(
        buyingPrice: Value(2500),
        sellingPrice: Value(5000),
      ),
    );

    final draft = await repository.saveInvoiceDraft(
      session: session,
      animalId: patient.id,
      products: [InvoiceProductDraft(inventoryItemId: item.id, quantity: 2)],
      services: const [],
      consultationFee: 0,
      homeServiceFee: 0,
    );
    await repository.issueInvoice(
      session: session,
      invoiceId: draft.invoice.id,
    );
    await repository.recordInvoicePayment(
      session: session,
      invoiceId: draft.invoice.id,
      amount: 10000,
      paymentMethod: 'Cash',
      paidAt: DateTime(2026, 8, 21),
    );
    await (database.update(database.inventoryItems)
          ..where((row) => row.id.equals(item.id)))
        .write(const InventoryItemsCompanion(buyingPrice: Value(4000)));

    final summary = await repository.getRevenueProfitSummary(session: session);
    expect(summary.revenue, 10000);
    expect(summary.clinicRevenue, 10000);
    expect(summary.farmRevenue, 0);
    expect(summary.cost, 5000);
    expect(summary.profit, 5000);
    expect(summary.margin, 0.5);
    expect(summary.transactionCount, 1);
    expect(summary.missingCostLines, 0);
  });

  test('one invoice supports same-owner animals and shared charges', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = (await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    ))!;
    final primary = (await database.select(database.animals).get()).first;
    final secondId = await database
        .into(database.animals)
        .insert(
          AnimalsCompanion.insert(
            clinicId: Value(primary.clinicId),
            hospitalNumber: '${primary.hospitalNumber}-SIBLING',
            animalName: 'Same Owner Animal',
            species: primary.species,
            ownerId: primary.ownerId,
            dateRegistered: DateTime(2026, 8, 20),
          ),
        );
    final draft = await repository.saveInvoiceDraft(
      session: session,
      animalId: primary.id,
      additionalAnimalIds: [secondId],
      products: const [],
      services: [
        InvoiceServiceDraft(
          description: 'Consultation',
          amount: 5000,
          animalId: primary.id,
        ),
        InvoiceServiceDraft(
          description: 'Treatment',
          amount: 7000,
          animalId: secondId,
        ),
        const InvoiceServiceDraft(
          description: 'Farm call',
          amount: 10000,
          isGeneral: true,
        ),
      ],
      consultationFee: 0,
      homeServiceFee: 0,
    );
    expect(draft.invoice.total, 22000);
    expect(
      draft.animals.map((animal) => animal.id),
      containsAll([primary.id, secondId]),
    );
    expect(
      draft.services.map((line) => line.animalId),
      containsAll([primary.id, secondId, null]),
    );
    expect(
      await (database.select(
        database.invoices,
      )..where((invoice) => invoice.id.equals(draft.invoice.id))).get(),
      hasLength(1),
    );
  });

  test(
    'combined invoice rejects animals belonging to different owners',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final animals = await database.select(database.animals).get();
      final primary = animals.first;
      final other = animals.firstWhere(
        (animal) => animal.ownerId != primary.ownerId,
      );
      await expectLater(
        repository.saveInvoiceDraft(
          session: session,
          animalId: primary.id,
          additionalAnimalIds: [other.id],
          products: const [],
          services: const [],
          consultationFee: 0,
          homeServiceFee: 0,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'configured inventory category access is tenant-scoped and persistent',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final administrator = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      final clinic = administrator!.clinic;
      await database
          .into(database.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: 'inventory-pharmacist',
              clinicId: clinic.clinicId,
              fullName: 'Inventory Pharmacist',
              username: 'inventory.pharmacist',
              email: 'inventory.pharmacist@avera.test',
              passwordHash: 'local-test-hash',
              role: 'Pharmacist',
              permissions: const Value('[]'),
              createdAt: DateTime.now(),
            ),
          );

      await repository.setClinicUserInventoryAccess(
        actingSession: administrator,
        targetUserId: 'inventory-pharmacist',
        viewCategoryIds: const {'drugs', 'vaccines'},
        sellCategoryIds: const {'drugs'},
      );
      final pharmacist =
          await (database.select(database.appUsers)
                ..where((user) => user.userId.equals('inventory-pharmacist')))
              .getSingle();

      final pharmacistSession = UserSession(user: pharmacist, clinic: clinic);
      expect(repository.inventoryCategoryIdsForUser(pharmacist), {
        'drugs',
        'vaccines',
      });
      expect(repository.inventorySellCategoryIdsForUser(pharmacist), {'drugs'});
      expect(
        repository.canSellInventoryCategory(pharmacistSession, 'drugs'),
        isTrue,
      );
      expect(
        repository.canSellInventoryCategory(pharmacistSession, 'vaccines'),
        isFalse,
      );
    },
  );

  test(
    'local login tolerates duplicate legacy Platform Owner seed rows',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);

      await repository.seedSampleData();
      await database
          .into(database.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: 'legacy-platform-owner',
              clinicId: 'platform-control',
              fullName: 'Legacy Platform Owner',
              username: 'legacy.owner',
              email: 'legacy.owner@avera.test',
              passwordHash: 'legacy-development-hash',
              role: 'Platform Owner',
              accountType: const Value(AccountTypes.platformOwner),
              permissions: const Value('[]'),
              createdAt: DateTime.now(),
            ),
          );

      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );

      expect(session, isNot(equals(null)));
      expect(session!.user.email, 'admin@avera.test');
      expect(session.clinic.clinicId, defaultClinicId);
    },
  );

  test(
    'platform accounts stay outside clinic staff lists and support is audited',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();

      final owner = await repository.authenticateUser(
        username: 'owner@avera.test',
        password: 'change-me-locally',
      );
      expect(owner, isNot(equals(null)));
      expect(owner!.isPlatformOwner, isTrue);
      expect(owner.isPlatformAccount, isTrue);

      final clinicUsers = await repository
          .watchClinicUsers(defaultClinicId)
          .first;
      expect(
        clinicUsers.any(
          (user) => user.accountType == AccountTypes.platformOwner,
        ),
        isFalse,
      );
      final platformUsers = await repository.watchPlatformUsers().first;
      expect(platformUsers, hasLength(1));
      expect(platformUsers.single.email, 'owner@avera.test');

      await repository.recordPlatformSupportAccess(
        actingSession: owner,
        clinicId: defaultClinicId,
        started: true,
      );
      final supportAudit =
          await (database.select(database.auditLogs)..where(
                (log) => log.action.equals('platform.support_mode_started'),
              ))
              .getSingle();
      expect(supportAudit.clinicId, defaultClinicId);
    },
  );

  test('reserved local Platform Owner credentials migrate in place', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final original = await (database.select(
      database.appUsers,
    )..where((user) => user.email.equals('owner@avera.test'))).getSingle();

    await (database.update(
      database.appUsers,
    )..where((user) => user.userId.equals(original.userId))).write(
      const AppUsersCompanion(
        email: Value('owner@avera.local'),
        passwordHash: Value('outdated-development-password'),
      ),
    );

    final owner = await repository.authenticateUser(
      username: 'owner@avera.test',
      password: 'change-me-locally',
    );
    expect(owner, isNot(equals(null)));
    expect(owner!.user.userId, original.userId);
    expect(owner.user.email, 'owner@avera.test');
  });

  test(
    'duplicate legacy development owners do not block local sign-in',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      await database
          .into(database.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: 'legacy-local-owner',
              clinicId: 'platform-control',
              fullName: 'Legacy Owner',
              username: 'legacy.owner',
              email: 'owner@avera.local',
              passwordHash: 'obsolete-hash',
              role: 'Platform Owner',
              accountType: const Value(AccountTypes.platformOwner),
              permissions: const Value('[]'),
              createdAt: DateTime.now(),
            ),
          );

      final owner = await repository.authenticateUser(
        username: 'owner@avera.test',
        password: 'change-me-locally',
      );
      expect(owner, isNot(equals(null)));
      expect(
        (await repository.watchPlatformUsers().first).where(
          (user) => user.accountStatus == AccountStatuses.active,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'consultations are loaded and updated by their saved record ID',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      final animal = (await database.select(database.animals).get()).first;

      final consultationId = await repository.saveVisit(
        session: session!,
        visit: VisitsCompanion.insert(
          animalId: animal.id,
          visitDate: DateTime.now(),
          chiefComplaint: const Value('Reduced appetite'),
          diagnosis: const Value('Initial assessment'),
        ),
      );

      final saved = await repository.getVisit(consultationId);
      expect(saved?.chiefComplaint, 'Reduced appetite');

      await repository.updateVisit(
        visitId: consultationId,
        session: session,
        visit: const VisitsCompanion(diagnosis: Value('Updated assessment')),
      );

      final updated = await repository.getVisit(consultationId);
      expect(updated?.diagnosis, 'Updated assessment');
      expect(updated?.chiefComplaint, 'Reduced appetite');

      final readOnlySession = UserSession(
        user: session.user,
        clinic: session.clinic,
        backendPermissions: const {Permissions.consultationsView},
      );
      await expectLater(
        repository.updateVisit(
          visitId: consultationId,
          session: readOnlySession,
          visit: const VisitsCompanion(
            diagnosis: Value('This must not be saved'),
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await repository.getVisit(consultationId))?.diagnosis,
        'Updated assessment',
      );
    },
  );

  test(
    'clinic administrator manages staff lifecycle without losing history',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final administrator = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      expect(administrator, isNot(equals(null)));

      await database
          .into(database.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: 'staff-lifecycle-user',
              clinicId: defaultClinicId,
              fullName: 'Jamie Reception',
              username: 'jamie@avera.test',
              email: 'jamie@avera.test',
              passwordHash: 'test-password-hash',
              role: 'Receptionist',
              accountType: const Value(AccountTypes.clinicStaff),
              accountStatus: const Value(AccountStatuses.active),
              createdAt: DateTime.now(),
            ),
          );

      await repository.changeClinicUserRole(
        actingSession: administrator!,
        targetUserId: 'staff-lifecycle-user',
        newRole: 'Veterinary Nurse',
      );
      var user = await (database.select(
        database.appUsers,
      )..where((row) => row.userId.equals('staff-lifecycle-user'))).getSingle();
      expect(user.role, 'Veterinary Nurse');

      await repository.updateClinicUserMembership(
        actingSession: administrator,
        targetUserId: user.userId,
        membershipStatus: ClinicMembershipStatuses.formerStaff,
        removalReason: 'Resigned',
        removalNote: 'Moved abroad.',
      );
      user = await (database.select(
        database.appUsers,
      )..where((row) => row.userId.equals('staff-lifecycle-user'))).getSingle();
      expect(user.membershipStatus, ClinicMembershipStatuses.formerStaff);
      expect(user.accountStatus, AccountStatuses.deactivated);
      expect(user.removalReason, 'Resigned');
      expect(user.removalNote, 'Moved abroad.');
      expect(
        (await repository
                .watchClinicUsers(
                  defaultClinicId,
                  membershipStatus: ClinicMembershipStatuses.active,
                )
                .first)
            .any((row) => row.userId == user.userId),
        isFalse,
      );

      await repository.updateClinicUserMembership(
        actingSession: administrator,
        targetUserId: user.userId,
        membershipStatus: ClinicMembershipStatuses.archived,
      );
      expect(
        await repository.permanentClinicUserDeletionBlockReason(
          actingSession: administrator,
          targetUserId: user.userId,
        ),
        isNot(equals(null)),
      );
      await repository.updateClinicUserMembership(
        actingSession: administrator,
        targetUserId: user.userId,
        membershipStatus: ClinicMembershipStatuses.active,
      );
      user = await (database.select(
        database.appUsers,
      )..where((row) => row.userId.equals('staff-lifecycle-user'))).getSingle();
      expect(user.membershipStatus, ClinicMembershipStatuses.active);
      expect(user.accountStatus, AccountStatuses.active);
      expect(
        await repository.clinicUserHistory(
          actingSession: administrator,
          targetUserId: user.userId,
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'staff management enforces clinic administrator and last-admin rules',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final administrator = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      expect(administrator, isNot(equals(null)));

      final veterinarian = UserSession(
        user: administrator!.user.copyWith(
          role: 'Veterinarian',
          accountType: AccountTypes.clinicStaff,
        ),
        clinic: administrator.clinic,
      );
      await expectLater(
        repository.updateClinicUserMembership(
          actingSession: veterinarian,
          targetUserId: administrator.user.userId,
          membershipStatus: ClinicMembershipStatuses.suspended,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        repository.updateClinicUserMembership(
          actingSession: administrator,
          targetUserId: administrator.user.userId,
          membershipStatus: ClinicMembershipStatuses.formerStaff,
        ),
        throwsA(isA<StateError>()),
      );
      final current =
          await (database.select(database.appUsers)
                ..where((row) => row.userId.equals(administrator.user.userId)))
              .getSingle();
      expect(current.membershipStatus, ClinicMembershipStatuses.active);

      await database
          .into(database.clinics)
          .insert(
            ClinicsCompanion.insert(
              clinicId: 'other-clinic',
              clinicName: 'Other Veterinary Clinic',
              dateRegistered: DateTime.now(),
            ),
          );
      await database
          .into(database.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: 'other-clinic-user',
              clinicId: 'other-clinic',
              fullName: 'Other Clinic Staff',
              username: 'other.staff',
              email: 'other.staff@avera.test',
              passwordHash: 'test-password-hash',
              role: 'Receptionist',
              accountType: const Value(AccountTypes.clinicStaff),
              accountStatus: const Value(AccountStatuses.active),
              createdAt: DateTime.now(),
            ),
          );
      await expectLater(
        repository.updateClinicUserMembership(
          actingSession: administrator,
          targetUserId: 'other-clinic-user',
          membershipStatus: ClinicMembershipStatuses.suspended,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'clinic role policies persist by clinic and write a safe audit event',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final administrator = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      expect(administrator, isNot(equals(null)));

      await repository.saveClinicRolePermissions(
        actingSession: administrator!,
        roleName: 'Pharmacist',
        permissions: {Permissions.inventoryView, Permissions.inventorySell},
      );

      final roles = await repository.watchClinicRoles(administrator).first;
      final pharmacist = roles.singleWhere((role) => role.name == 'Pharmacist');
      expect(pharmacist.permissions, {
        Permissions.inventoryView,
        Permissions.inventorySell,
      });
      final audit = await repository.watchClinicAuditLogs(administrator).first;
      expect(
        audit.any((item) => item.action == 'role.permissions_updated'),
        isTrue,
      );

      await expectLater(
        repository.saveClinicRolePermissions(
          actingSession: administrator,
          roleName: 'Clinic Administrator',
          permissions: {Permissions.usersView},
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'notification lifecycle is clinic-scoped and does not alter patient data',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      expect(session, isNot(equals(null)));
      final administrator = session!;
      final patient = (await database.select(database.animals).get()).first;
      final notificationId = await database
          .into(database.notifications)
          .insert(
            NotificationsCompanion.insert(
              clinicId: const Value(defaultClinicId),
              type: 'Vaccination Due',
              title: 'Exact vaccination reminder',
              message: 'This is an inbox lifecycle test.',
              animalId: Value(patient.id),
              destinationType: const Value('vaccinationRecord'),
              destinationEntityId: const Value(1),
              createdAt: DateTime.now(),
            ),
          );

      await repository.markNotificationRead(
        session: administrator,
        notificationId: notificationId,
      );
      var item = await (database.select(
        database.notifications,
      )..where((row) => row.id.equals(notificationId))).getSingle();
      expect(item.status, InAppNotificationStatus.read.storageValue);
      expect(item.readAt, isNot(equals(null)));

      await repository.markNotificationReviewed(
        session: administrator,
        notificationId: notificationId,
      );
      item = await (database.select(
        database.notifications,
      )..where((row) => row.id.equals(notificationId))).getSingle();
      expect(item.status, InAppNotificationStatus.reviewed.storageValue);
      expect(item.reviewedAt, isNot(equals(null)));

      await repository.dismissNotification(
        session: administrator,
        notificationId: notificationId,
      );
      expect(item.animalId, patient.id);
      expect(
        (await repository.watchNotifications().first).any(
          (notification) => notification.id == notificationId,
        ),
        isFalse,
      );
      expect(
        await (database.select(
          database.animals,
        )..where((row) => row.id.equals(patient.id))).getSingle(),
        isNot(equals(null)),
      );
    },
  );

  test(
    'a scheduled vaccination creates one linked recorded dose only',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      );
      expect(session, isNot(equals(null)));

      Vaccination? schedule;
      VaccineProtocolDefinition? protocol;
      for (final candidate
          in await database.select(database.vaccinations).get()) {
        final animal = await (database.select(
          database.animals,
        )..where((row) => row.id.equals(candidate.animalId))).getSingle();
        final species = AnimalCatalogue.speciesForDisplayName(animal.species);
        final match = VaccineCatalogue.protocols.where(
          (item) =>
              item.name == candidate.vaccine && item.speciesId == species?.id,
        );
        if (match.isNotEmpty) {
          schedule = candidate;
          protocol = match.first;
          break;
        }
      }
      expect(schedule, isNot(equals(null)));
      expect(protocol, isNot(equals(null)));
      final scheduledVaccination = schedule!;
      final matchedProtocol = protocol!;

      final dateGiven = DateTime.now().subtract(const Duration(minutes: 1));
      final recordedDoseId = await repository.recordVaccination(
        session: session!,
        animalId: scheduledVaccination.animalId,
        protocolId: matchedProtocol.id,
        dateGiven: dateGiven,
        nextDueDate: matchedProtocol.suggestedDueDate(dateGiven),
        route: matchedProtocol.defaultRoute,
        dose: '1 ml',
        scheduledVaccinationId: scheduledVaccination.id,
      );

      final recorded = await repository.getRecordedDoseForSchedule(
        scheduledVaccination.id,
      );
      expect(recorded, isNot(equals(null)));
      expect(recorded!.vaccination.id, recordedDoseId);
      expect(recorded.vaccination.sourceVaccinationId, scheduledVaccination.id);
      final updatedSchedule = await (database.select(
        database.vaccinations,
      )..where((row) => row.id.equals(scheduledVaccination.id))).getSingle();
      expect(updatedSchedule.status, 'Scheduled Dose Recorded');

      await expectLater(
        repository.recordVaccination(
          session: session,
          animalId: scheduledVaccination.animalId,
          protocolId: matchedProtocol.id,
          dateGiven: dateGiven,
          nextDueDate: matchedProtocol.suggestedDueDate(dateGiven),
          route: matchedProtocol.defaultRoute,
          scheduledVaccinationId: scheduledVaccination.id,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
