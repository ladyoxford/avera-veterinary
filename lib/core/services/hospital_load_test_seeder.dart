import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/animal_catalogue.dart';
import '../repositories/subscription_repository.dart';
import '../security/access_control.dart';
import 'feature_gate_service.dart';
import 'hospital_numbering.dart';

/// Builds a realistic but compact local workload without packaging data files
/// or patient images in the application. It is deliberately available only in
/// debug builds and always writes to its own clinic tenant.
class HospitalLoadTestSeeder {
  HospitalLoadTestSeeder(this._db);

  static const clinicId = 'development-load-test-hospital';
  static const datasetId = 'avera_large_hospital_v1';
  static const datasetVersion = '1';
  static const administratorEmail = 'loadtest.admin@avera.test';
  static const administratorPassword = 'admin123';
  static const _administratorId = 'development-load-test-administrator';
  static const _year = 2026;

  final AppDatabase _db;

  Future<bool> isLargeHospitalSeeded() async {
    final marker = await (_db.select(
      _db.developmentDatasetMarkers,
    )..where((row) => row.datasetId.equals(datasetId))).getSingleOrNull();
    return marker != null;
  }

  Future<HospitalLoadTestResult> seedLargeHospital() async {
    _requireDebugBuild();
    final existing = await _markerResult();
    if (existing != null) return existing.copyWith(alreadyExisted: true);

    final now = DateTime.now();
    await _db.transaction(() async {
      await _ensureClinicAndAdministrator(now);
      await _seedStaff(now);
      await _seedOwnersAndPatients(now);
      await _seedOperationalRecords(now);
      await _db
          .into(_db.developmentDatasetMarkers)
          .insert(
            DevelopmentDatasetMarkersCompanion.insert(
              datasetId: datasetId,
              clinicId: clinicId,
              version: datasetVersion,
              generatedAt: now,
              settings: Value(
                jsonEncode({
                  'seed': 'avera-metropolitan-v1',
                  'patients': 500,
                  'consultations': 1800,
                  'vaccinations': 1050,
                  'appointments': 600,
                  'inventory': 250,
                  'invoices': 750,
                }),
              ),
            ),
          );
    });
    return (await _markerResult())!;
  }

  /// Removes only rows bearing this generator's stable clinic, email, batch,
  /// reference, and event prefixes. The clinic shell and administrator remain
  /// usable for a subsequent explicit regeneration.
  Future<void> resetLargeHospital() async {
    _requireDebugBuild();
    await _db.transaction(() async {
      const animalPredicate =
          "clinic_id = '$clinicId' AND hospital_number LIKE 'AMV-2026-%'";
      const invoicePredicate =
          "clinic_id = '$clinicId' AND reference LIKE 'AMV-INV-2026-%'";
      const inventoryPredicate =
          "clinic_id = '$clinicId' AND batch_number LIKE 'AMV-LT-%'";
      await _db.customStatement(
        'DELETE FROM appointment_reminders WHERE appointment_id IN '
        '(SELECT id FROM appointments WHERE animal_id IN '
        '(SELECT id FROM animals WHERE $animalPredicate))',
      );
      await _db.customStatement(
        'DELETE FROM invoice_product_lines WHERE invoice_id IN '
        '(SELECT id FROM invoices WHERE $invoicePredicate)',
      );
      await _db.customStatement(
        'DELETE FROM invoice_service_lines WHERE invoice_id IN '
        '(SELECT id FROM invoices WHERE $invoicePredicate)',
      );
      await _db.customStatement(
        'DELETE FROM inventory_stock_movements WHERE invoice_id IN '
        '(SELECT id FROM invoices WHERE $invoicePredicate)',
      );
      await _db.customStatement('DELETE FROM invoices WHERE $invoicePredicate');
      await _db.customStatement(
        'DELETE FROM sales WHERE clinic_id = ? AND drug_id IN '
        '(SELECT id FROM inventory_items WHERE $inventoryPredicate)',
        [clinicId],
      );
      await _db.customStatement(
        'DELETE FROM appointments WHERE animal_id IN '
        '(SELECT id FROM animals WHERE $animalPredicate)',
      );
      await _db.customStatement(
        'DELETE FROM vaccinations WHERE animal_id IN '
        '(SELECT id FROM animals WHERE $animalPredicate)',
      );
      await _db.customStatement(
        'DELETE FROM visits WHERE animal_id IN '
        '(SELECT id FROM animals WHERE $animalPredicate)',
      );
      await _db.customStatement(
        'DELETE FROM clinic_activity_events WHERE clinic_id = ? '
        "AND id LIKE 'loadtest-%'",
        [clinicId],
      );
      await _db.customStatement(
        'DELETE FROM notifications WHERE clinic_id = ? '
        "AND type = 'LoadTest'",
        [clinicId],
      );
      await _db.customStatement(
        'DELETE FROM audit_logs WHERE clinic_id = ? '
        "AND action LIKE 'loadtest.%'",
        [clinicId],
      );
      await _db.customStatement('DELETE FROM animals WHERE $animalPredicate');
      await _db.customStatement(
        "DELETE FROM owners WHERE clinic_id = ? AND email LIKE 'loadtest.owner.%@avera.test'",
        [clinicId],
      );
      await _db.customStatement(
        'DELETE FROM inventory_items WHERE $inventoryPredicate',
      );
      await _db.customStatement(
        "DELETE FROM app_users WHERE clinic_id = ? AND email LIKE 'loadtest.staff.%@avera.test'",
        [clinicId],
      );
      await (_db.delete(
        _db.clinicNumberSequences,
      )..where((row) => row.clinicId.equals(clinicId))).go();
      await (_db.delete(
        _db.developmentDatasetMarkers,
      )..where((row) => row.datasetId.equals(datasetId))).go();
    });
  }

  Future<void> _ensureClinicAndAdministrator(DateTime now) async {
    await _db
        .into(_db.clinics)
        .insertOnConflictUpdate(
          ClinicsCompanion.insert(
            clinicId: clinicId,
            clinicName: 'AVERA Metropolitan Veterinary Hospital',
            address: const Value('18 Metropolitan Veterinary Way'),
            city: const Value('Awka'),
            state: const Value('Anambra'),
            country: const Value('Nigeria'),
            phoneNumber: const Value('+234 803 555 2026'),
            email: const Value('metropolitan@avera.test'),
            clinicType: const Value(
              'Large Multi-Department Veterinary Hospital',
            ),
            timeZone: const Value('Africa/Lagos'),
            currency: const Value('NGN'),
            clinicOwner: const Value('AVERA Development'),
            dateRegistered: now,
            subscriptionPlan: const Value('Enterprise'),
            clinicStatus: const Value('Active'),
            patientNumberPrefix: const Value('AMV'),
            patientNumberSequenceLength: const Value(5),
            patientNumberPrefixReviewed: const Value(true),
          ),
        );
    await _db
        .into(_db.appUsers)
        .insertOnConflictUpdate(
          AppUsersCompanion.insert(
            userId: _administratorId,
            clinicId: clinicId,
            fullName: 'Metropolitan Clinic Administrator',
            username: administratorEmail,
            email: administratorEmail,
            passwordHash: _localHash(administratorPassword),
            role: 'Clinic Administrator',
            roleId: const Value('Clinic Administrator'),
            accountType: const Value(AccountTypes.clinicAdministrator),
            accountStatus: const Value(AccountStatuses.active),
            membershipStatus: const Value(ClinicMembershipStatuses.active),
            permissions: Value(jsonEncode(allPermissions.toList())),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    await LocalSubscriptionRepository(_db).assignPlan(
      clinicId: clinicId,
      plan: SubscriptionPlan.enterprise,
      actingUserId: _administratorId,
      action: 'loadtest.subscription_seeded',
    );
  }

  Future<void> _seedStaff(DateTime now) async {
    final activeRoles = <String>[
      ...List.filled(8, 'Veterinarian'),
      ...List.filled(5, 'Veterinary Nurse'),
      ...List.filled(2, 'Receptionist'),
      ...List.filled(2, 'Laboratory Staff'),
      ...List.filled(2, 'Pharmacist'),
      'Cashier',
      'Practice Manager',
      ...List.filled(2, 'Inventory Officer'),
      'Sales Representative',
    ];
    final rows = <AppUsersCompanion>[];
    for (var index = 0; index < activeRoles.length; index++) {
      rows.add(_staffRow(index, activeRoles[index], now));
    }
    for (var index = 0; index < 2; index++) {
      rows.add(
        _staffRow(
          100 + index,
          'Veterinary Nurse',
          now,
          accountStatus: AccountStatuses.suspended,
          membershipStatus: ClinicMembershipStatuses.suspended,
        ),
      );
    }
    for (var index = 0; index < 3; index++) {
      rows.add(
        _staffRow(
          200 + index,
          'Veterinarian',
          now,
          accountStatus: AccountStatuses.deactivated,
          membershipStatus: ClinicMembershipStatuses.formerStaff,
        ),
      );
    }
    for (var index = 0; index < 2; index++) {
      rows.add(
        _staffRow(
          300 + index,
          'Receptionist',
          now,
          accountStatus: AccountStatuses.deactivated,
          membershipStatus: ClinicMembershipStatuses.archived,
        ),
      );
    }
    await _db.batch((batch) => batch.insertAll(_db.appUsers, rows));
  }

  AppUsersCompanion _staffRow(
    int index,
    String role,
    DateTime now, {
    String accountStatus = AccountStatuses.active,
    String membershipStatus = ClinicMembershipStatuses.active,
  }) => AppUsersCompanion.insert(
    userId: 'loadtest-staff-$index',
    clinicId: clinicId,
    fullName:
        '${_firstNames[index % _firstNames.length]} ${_lastNames[index % _lastNames.length]}',
    username: 'loadtest.staff.$index@avera.test',
    email: 'loadtest.staff.$index@avera.test',
    passwordHash: _localHash('not-a-login-$index'),
    role: role,
    roleId: Value(role),
    accountType: const Value(AccountTypes.clinicStaff),
    accountStatus: Value(accountStatus),
    membershipStatus: Value(membershipStatus),
    permissions: const Value('[]'),
    createdAt: now,
    updatedAt: Value(now),
    suspendedAt: accountStatus == AccountStatuses.suspended
        ? Value(now)
        : const Value.absent(),
    formerStaffAt: membershipStatus == ClinicMembershipStatuses.formerStaff
        ? Value(now.subtract(const Duration(days: 30)))
        : const Value.absent(),
    archivedAt: membershipStatus == ClinicMembershipStatuses.archived
        ? Value(now.subtract(const Duration(days: 90)))
        : const Value.absent(),
  );

  Future<void> _seedOwnersAndPatients(DateTime now) async {
    final owners = List.generate(
      325,
      (index) => OwnersCompanion.insert(
        clinicId: const Value(clinicId),
        fullName:
            '${_firstNames[index % _firstNames.length]} ${_lastNames[(index * 3) % _lastNames.length]}',
        phone: '080${(31000000 + index).toString().padLeft(8, '0')}',
        email: Value('loadtest.owner.$index@avera.test'),
        address: Value('${index + 1} Metropolitan Road'),
        city: const Value('Awka'),
        state: const Value('Anambra'),
        country: const Value('Nigeria'),
      ),
    );
    await _db.batch((batch) => batch.insertAll(_db.owners, owners));
    final savedOwners =
        await (_db.select(_db.owners)
              ..where((row) => row.clinicId.equals(clinicId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    final speciesIds = _patientSpeciesIds();
    final patients = <AnimalsCompanion>[];
    for (var index = 0; index < 500; index++) {
      final species = AnimalCatalogue.speciesById(speciesIds[index])!;
      final breed = AnimalCatalogue.breedsFor(
        species.id,
      ).firstWhere((row) => !row.allowsCustomBreed && !row.isUnknownOption);
      final status = index < 470
          ? 'Active'
          : index < 485
          ? 'Relocated'
          : index < 495
          ? 'Deceased'
          : 'Archived';
      patients.add(
        AnimalsCompanion.insert(
          clinicId: const Value(clinicId),
          hospitalNumber: formatHospitalNumber(
            prefix: 'AMV',
            year: _year,
            sequence: index + 1,
            sequenceLength: 5,
          ),
          animalName:
              '${_animalNames[index % _animalNames.length]} ${index + 1}',
          species: species.displayName,
          breed: Value(breed.displayName),
          sex: Value(index.isEven ? 'Female' : 'Male'),
          age: Value(1 + (index % 12)),
          dateOfBirth: Value(
            now.subtract(Duration(days: 365 * (1 + index % 12))),
          ),
          weight: Value(_weightForSpecies(species.displayName, index)),
          color: Value(_colours[index % _colours.length]),
          microchipNumber:
              species.displayName == 'Dog' || species.displayName == 'Cat'
              ? Value('AMV${(index + 1).toString().padLeft(12, '0')}')
              : const Value.absent(),
          ownerId: savedOwners[index % savedOwners.length].id,
          dateRegistered: now.subtract(Duration(days: index % 1450)),
          notes: const Value('Synthetic development-load-test patient.'),
          status: Value(status),
          statusUpdatedAt: status == 'Active'
              ? const Value.absent()
              : Value(now),
          numberAssignmentStatus: const Value('Assigned'),
          registrationYear: const Value(_year),
          registrationSubmissionId: Value('loadtest-registration-$index'),
        ),
      );
    }
    await _db.batch((batch) => batch.insertAll(_db.animals, patients));
    await _db
        .into(_db.clinicNumberSequences)
        .insert(
          ClinicNumberSequencesCompanion.insert(
            clinicId: clinicId,
            sequenceType: 'patient',
            sequenceKey: '$_year',
            currentValue: const Value(500),
            sequenceLength: const Value(5),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> _seedOperationalRecords(DateTime now) async {
    final animals =
        await (_db.select(_db.animals)
              ..where((row) => row.clinicId.equals(clinicId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    final activeAnimals = animals
        .where((row) => row.status == 'Active')
        .toList();
    final visits = List.generate(
      1800,
      (index) => VisitsCompanion.insert(
        clinicId: const Value(clinicId),
        animalId: animals[index % animals.length].id,
        visitDate: now.subtract(Duration(days: index % 1800)),
        chiefComplaint: Value(_complaints[index % _complaints.length]),
        history: const Value(
          'Synthetic concise clinical history for local performance testing.',
        ),
        physicalExamination: const Value(
          'Bright, alert, responsive; no emergency findings.',
        ),
        diagnosis: Value(_diagnoses[index % _diagnoses.length]),
        treatment: const Value('Supportive care and review as indicated.'),
        prescription: const Value(
          'Synthetic record. Not a clinical recommendation.',
        ),
        veterinarian: Value(
          'Dr. ${_firstNames[index % 8]} ${_lastNames[index % _lastNames.length]}',
        ),
        status: Value(index % 9 == 0 ? 'Draft' : 'Completed'),
      ),
    );
    await _db.batch((batch) => batch.insertAll(_db.visits, visits));

    final vaccinationRows = <VaccinationsCompanion>[];
    for (var index = 0; index < 1050; index++) {
      final animal = activeAnimals[index % activeAnimals.length];
      final dateGiven = now.subtract(Duration(days: 30 + index % 700));
      vaccinationRows.add(
        VaccinationsCompanion.insert(
          clinicId: const Value(clinicId),
          animalId: animal.id,
          vaccine: _vaccineForSpecies(animal.species),
          batchNumber: Value('AMV-VAC-${1000 + index}'),
          manufacturer: const Value('AVERA Demo Biologics'),
          route: const Value('Subcutaneous'),
          dose: const Value('1 ml'),
          dateGiven: dateGiven,
          nextDueDate: Value(
            index % 5 == 0
                ? now.subtract(Duration(days: index % 14))
                : now.add(Duration(days: index % 365 + 1)),
          ),
          administeredBy: const Value('Load Test Vaccination Team'),
          veterinarian: const Value('Dr. Amina Okafor'),
          certificateNumber: Value(
            'AMV-CERT-${(index + 1).toString().padLeft(5, '0')}',
          ),
          reminderStatus: Value(index % 7 == 0 ? 'Overdue' : 'Pending'),
          status: const Value('Completed'),
        ),
      );
    }
    await _db.batch(
      (batch) => batch.insertAll(_db.vaccinations, vaccinationRows),
    );

    final appointments = List.generate(
      600,
      (index) => AppointmentsCompanion.insert(
        clinicId: const Value(clinicId),
        animalId: activeAnimals[index % activeAnimals.length].id,
        appointmentDate: now.add(
          Duration(days: index % 90 - 45, hours: 8 + index % 8),
        ),
        purpose: _appointmentPurposes[index % _appointmentPurposes.length],
        status: Value(
          _appointmentStatuses[index % _appointmentStatuses.length],
        ),
        assignedStaffId: Value('loadtest-staff-${index % 8}'),
        notes: const Value('Synthetic appointment for large-list testing.'),
        reference: Value('AMV-APT-${(index + 1).toString().padLeft(5, '0')}'),
        createdAt: Value(now.subtract(Duration(days: index % 300))),
        updatedAt: Value(now),
      ),
    );
    await _db.batch((batch) => batch.insertAll(_db.appointments, appointments));

    final inventory = List.generate(
      250,
      (index) => InventoryItemsCompanion.insert(
        clinicId: const Value(clinicId),
        drugName:
            '${_inventoryNames[index % _inventoryNames.length]} ${index + 1}',
        category: _inventoryCategories[index % _inventoryCategories.length],
        categoryId: Value(
          _inventoryCategories[index % _inventoryCategories.length]
              .toLowerCase()
              .replaceAll(' ', '_'),
        ),
        manufacturer: const Value('Metropolitan Veterinary Supply'),
        batchNumber: Value('AMV-LT-${(index + 1).toString().padLeft(4, '0')}'),
        expiryDate: Value(
          index % 23 == 0
              ? now.subtract(Duration(days: index % 120 + 1))
              : now.add(Duration(days: 20 + index % 800)),
        ),
        quantity: Value(
          index % 29 == 0
              ? 0
              : index % 17 == 0
              ? 3
              : 80 + index % 120,
        ),
        minimumQuantity: const Value(8),
        buyingPrice: Value(500 + (index % 20) * 125),
        sellingPrice: Value(800 + (index % 20) * 180),
        supplier: const Value('AVERA Development Supplies'),
        location: Value('Department ${String.fromCharCode(65 + index % 6)}'),
        createdAt: Value(now.subtract(Duration(days: index % 200))),
        updatedAt: Value(now),
      ),
    );
    await _db.batch((batch) => batch.insertAll(_db.inventoryItems, inventory));
    await _seedInvoicesAndHistory(now, animals);
  }

  Future<void> _seedInvoicesAndHistory(
    DateTime now,
    List<Animal> animals,
  ) async {
    final inventory =
        await (_db.select(_db.inventoryItems)
              ..where((row) => row.clinicId.equals(clinicId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    for (var index = 0; index < 750; index++) {
      final item = inventory[index % inventory.length];
      final status = switch (index % 10) {
        0 => 'Draft',
        1 => 'Voided',
        2 || 3 => 'Pending',
        _ => 'Paid',
      };
      final productTotal = status == 'Draft' ? 0.0 : item.sellingPrice;
      final serviceTotal = 2500.0 + (index % 5) * 500;
      final invoiceId = await _db
          .into(_db.invoices)
          .insert(
            InvoicesCompanion.insert(
              clinicId: clinicId,
              animalId: animals[index % animals.length].id,
              reference:
                  'AMV-INV-$_year-${(index + 1).toString().padLeft(5, '0')}',
              status: Value(status),
              productsSubtotal: Value(productTotal),
              servicesSubtotal: Value(serviceTotal),
              consultationFee: const Value(3500),
              total: Value(productTotal + serviceTotal + 3500),
              paymentMethod: status == 'Paid'
                  ? const Value('Card')
                  : const Value.absent(),
              paidAt: status == 'Paid'
                  ? Value(now.subtract(Duration(days: index % 300)))
                  : const Value.absent(),
              voidedAt: status == 'Voided'
                  ? Value(now.subtract(Duration(days: index % 300)))
                  : const Value.absent(),
              voidReason: status == 'Voided'
                  ? const Value('Synthetic voided invoice.')
                  : const Value.absent(),
              clinicNameSnapshot: 'AVERA Metropolitan Veterinary Hospital',
              clinicAddressSnapshot: const Value(
                '18 Metropolitan Veterinary Way, Awka',
              ),
              clinicPhoneSnapshot: const Value('+234 803 555 2026'),
              clinicEmailSnapshot: const Value('metropolitan@avera.test'),
              createdByUserId: _administratorId,
              createdAt: now.subtract(Duration(days: index % 365)),
              updatedAt: Value(now),
            ),
          );
      if (productTotal > 0) {
        await _db
            .into(_db.invoiceProductLines)
            .insert(
              InvoiceProductLinesCompanion.insert(
                invoiceId: invoiceId,
                inventoryItemId: item.id,
                productNameSnapshot: item.drugName,
                categoryNameSnapshot: item.category,
                batchNumberSnapshot: Value(item.batchNumber),
                quantity: 1,
                unitPrice: item.sellingPrice,
                lineTotal: item.sellingPrice,
              ),
            );
      }
      await _db
          .into(_db.invoiceServiceLines)
          .insert(
            InvoiceServiceLinesCompanion.insert(
              invoiceId: invoiceId,
              description: 'Synthetic clinical service',
              amount: serviceTotal,
            ),
          );
      if (status == 'Paid' && item.quantity > 0) {
        await _db
            .into(_db.inventoryStockMovements)
            .insert(
              InventoryStockMovementsCompanion.insert(
                clinicId: clinicId,
                inventoryItemId: item.id,
                movementType: 'Sale',
                quantityChange: -1,
                quantityBefore: item.quantity,
                quantityAfter: item.quantity - 1,
                invoiceId: Value(invoiceId),
                performedByUserId: _administratorId,
                reason: const Value('Synthetic paid invoice'),
                createdAt: now.subtract(Duration(days: index % 300)),
              ),
            );
      }
    }
    final activities = List.generate(
      2500,
      (index) => ClinicActivityEventsCompanion.insert(
        id: 'loadtest-activity-${index.toString().padLeft(5, '0')}',
        clinicId: clinicId,
        type: _activityTypes[index % _activityTypes.length],
        title: _activityTitles[index % _activityTitles.length],
        description: 'Synthetic operational history for performance testing.',
        occurredAt: now.subtract(Duration(minutes: index * 11)),
        performedByUserId: Value(_administratorId),
        relatedEntityType: const Value('LoadTest'),
        relatedEntityId: Value((index % 750 + 1).toString()),
        patientId: Value(animals[index % animals.length].id),
        module: Value(_activityTypes[index % _activityTypes.length]),
      ),
    );
    final audits = List.generate(
      3500,
      (index) => AuditLogsCompanion.insert(
        clinicId: const Value(clinicId),
        userId: const Value(_administratorId),
        action: 'loadtest.${_activityTypes[index % _activityTypes.length]}',
        entityType: const Value('LoadTest'),
        entityId: Value((index % 750 + 1).toString()),
        details: const Value(
          'Synthetic structured development-load-test audit event.',
        ),
        createdAt: now.subtract(Duration(minutes: index * 7)),
      ),
    );
    await _db.batch((batch) {
      batch.insertAll(_db.clinicActivityEvents, activities);
      batch.insertAll(_db.auditLogs, audits);
    });
  }

  Future<HospitalLoadTestResult?> _markerResult() async {
    final marker = await (_db.select(
      _db.developmentDatasetMarkers,
    )..where((row) => row.datasetId.equals(datasetId))).getSingleOrNull();
    if (marker == null) return null;
    final counts = await Future.wait<int>([
      (_db.select(_db.animals)..where((row) => row.clinicId.equals(clinicId)))
          .get()
          .then((rows) => rows.length),
      (_db.select(_db.visits)..where((row) => row.clinicId.equals(clinicId)))
          .get()
          .then((rows) => rows.length),
      (_db.select(_db.vaccinations)
            ..where((row) => row.clinicId.equals(clinicId)))
          .get()
          .then((rows) => rows.length),
      (_db.select(_db.appointments)
            ..where((row) => row.clinicId.equals(clinicId)))
          .get()
          .then((rows) => rows.length),
      (_db.select(_db.inventoryItems)
            ..where((row) => row.clinicId.equals(clinicId)))
          .get()
          .then((rows) => rows.length),
      (_db.select(_db.invoices)..where((row) => row.clinicId.equals(clinicId)))
          .get()
          .then((rows) => rows.length),
    ]);
    return HospitalLoadTestResult(
      patients: counts[0],
      consultations: counts[1],
      vaccinations: counts[2],
      appointments: counts[3],
      inventoryItems: counts[4],
      invoices: counts[5],
      generatedAt: marker.generatedAt,
    );
  }

  static String _localHash(String password) =>
      sha256.convert('$password:zevora-local-salt'.codeUnits).toString();

  static void _requireDebugBuild() {
    if (!kDebugMode) {
      throw StateError(
        'The load-test generator is available only in debug builds.',
      );
    }
  }

  static List<String> _patientSpeciesIds() {
    const distribution = <String, int>{
      'species_dog': 210,
      'species_cat': 100,
      'species_cattle': 50,
      'species_goat': 35,
      'species_sheep': 20,
      'species_pig': 20,
      'species_rabbit': 20,
      'species_chicken': 15,
      'species_turkey': 5,
      'species_duck': 5,
      'species_horse': 5,
      'species_parrot': 10,
      'species_guinea_pig': 5,
    };
    return [
      for (final entry in distribution.entries)
        ...List.filled(entry.value, entry.key),
    ];
  }

  static double _weightForSpecies(String species, int index) =>
      switch (species) {
        'Cattle' => 180 + index % 250,
        'Horse' => 250 + index % 300,
        'Pig' => 35 + index % 90,
        'Goat' || 'Sheep' => 18 + index % 45,
        'Dog' => 5 + index % 45,
        'Cat' => 2.5 + index % 5,
        'Rabbit' => 1.2 + index % 3,
        _ => 0.2 + index % 4,
      };

  static String _vaccineForSpecies(String species) => switch (species) {
    'Dog' => 'DHLPP',
    'Cat' => 'FVRCP',
    'Cattle' => 'CBPP',
    'Goat' || 'Sheep' => 'PPR',
    'Pig' => 'Porcine parvovirus',
    'Rabbit' => 'Rabbit Haemorrhagic Disease',
    'Chicken' || 'Turkey' || 'Duck' => 'Newcastle disease',
    'Horse' => 'Tetanus toxoid',
    'Parrot' => 'Avian polyomavirus',
    _ => 'Species-appropriate preventive care',
  };
}

class HospitalLoadTestResult {
  const HospitalLoadTestResult({
    required this.patients,
    required this.consultations,
    required this.vaccinations,
    required this.appointments,
    required this.inventoryItems,
    required this.invoices,
    required this.generatedAt,
    this.alreadyExisted = false,
  });

  final int patients;
  final int consultations;
  final int vaccinations;
  final int appointments;
  final int inventoryItems;
  final int invoices;
  final DateTime generatedAt;
  final bool alreadyExisted;

  HospitalLoadTestResult copyWith({bool? alreadyExisted}) =>
      HospitalLoadTestResult(
        patients: patients,
        consultations: consultations,
        vaccinations: vaccinations,
        appointments: appointments,
        inventoryItems: inventoryItems,
        invoices: invoices,
        generatedAt: generatedAt,
        alreadyExisted: alreadyExisted ?? this.alreadyExisted,
      );
}

const _firstNames = [
  'Amina',
  'Chiamaka',
  'Ifeanyi',
  'Tomiwa',
  'Zainab',
  'Emeka',
  'Ada',
  'Ibrahim',
];
const _lastNames = [
  'Okafor',
  'Adeyemi',
  'Bello',
  'Eze',
  'Okoro',
  'Ibrahim',
  'Nwosu',
  'Umeh',
];
const _animalNames = [
  'Bella',
  'Max',
  'Luna',
  'Charlie',
  'Rocky',
  'Milo',
  'Ruby',
  'Zara',
  'Simba',
  'Pepper',
];
const _colours = ['Black', 'Brown', 'White', 'Golden', 'Ginger', 'Spotted'];
const _complaints = [
  'Routine wellness review',
  'Vaccination follow-up',
  'Reduced appetite',
  'Skin irritation',
  'Lameness',
];
const _diagnoses = [
  'Wellness examination',
  'Preventive care',
  'Dermatitis',
  'Gastroenteritis',
  'Musculoskeletal strain',
];
const _appointmentPurposes = [
  'Vaccination',
  'Follow-up',
  'Wellness visit',
  'Laboratory review',
  'Medication review',
];
const _appointmentStatuses = [
  'Confirmed',
  'Pending',
  'Completed',
  'Cancelled',
  'Rescheduled',
];
const _inventoryCategories = [
  'Drugs',
  'Vaccines',
  'Supplements',
  'Clinical Consumables',
  'Surgical Supplies',
  'Laboratory Reagents',
  'Diagnostic Test Kits',
  'Equipment',
  'Pet Food',
];
const _inventoryNames = [
  'Amoxicillin',
  'Rabies Vaccine',
  'Vitamin Supplement',
  'Surgical Gloves',
  'Suture Pack',
  'CBC Reagent',
  'Rapid Test Kit',
  'Infusion Pump',
  'Canine Diet',
];
const _activityTypes = [
  'patient',
  'consultation',
  'vaccination',
  'appointment',
  'inventory',
  'billing',
];
const _activityTitles = [
  'Patient registered',
  'Consultation completed',
  'Vaccination recorded',
  'Appointment updated',
  'Stock adjusted',
  'Invoice paid',
];
