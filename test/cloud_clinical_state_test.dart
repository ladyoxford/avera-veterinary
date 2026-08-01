import 'dart:async';

import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/remote/cloud_clinical_state.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/repositories/cloud_cache_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late CloudCacheRepository cache;
  late _FakeClinicalRemoteDataSource source;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    cache = CloudCacheRepository(database);
    source = _FakeClinicalRemoteDataSource();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'patient status updates require permission before the remote call',
    () async {
      source.patientsValue = [_patient()];
      final controller = RemotePatientListController(
        source,
        cache,
        () async => _session(const {Permissions.patientsView}),
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      await expectLater(
        controller.updateStatus(patientId: _patientId, status: 'Deceased'),
        throwsA(isA<StateError>()),
      );

      expect(source.patientStatusCalls, 0);
      expect(controller.state.items.single.status, 'Active');
    },
  );

  test('confirmed patient status is cached and refreshes the list', () async {
    source.patientsValue = [_patient()];
    final controller = RemotePatientListController(
      source,
      cache,
      () async =>
          _session(const {Permissions.patientsView, Permissions.patientsEdit}),
    );
    addTearDown(controller.dispose);
    await controller.refresh();

    final updated = await controller.updateStatus(
      patientId: _patientId,
      status: 'Relocated',
      reason: 'Owner moved clinic',
    );

    expect(source.patientStatusCalls, 1);
    expect(updated.status, 'Relocated');
    final synchronization = await (database.select(
      database.cloudEntitySynchronizations,
    )..where((row) => row.serverId.equals(_patientId))).getSingle();
    expect(synchronization.entityType, 'patient');
    expect(synchronization.clinicId, _clinicId);
    expect(synchronization.revision, 2);
  });

  test('inventory falls back to clinic-scoped Drift cache', () async {
    source.inventoryValue = [_inventoryItem()];
    final controller = RemoteInventoryListController(
      source,
      cache,
      () async => _session(const {Permissions.inventoryView}),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.state.fromCache, isFalse);
    expect(controller.state.items.single.name, 'Amoxicillin 250 mg');

    source.failInventory = true;
    await controller.refresh();

    expect(controller.state.fromCache, isTrue);
    expect(controller.state.items.single.id, _inventoryId);
    expect(controller.state.error, isNotNull);
  });

  test(
    'inventory creation requires permission and caches confirmed writes',
    () async {
      final unauthorized = RemoteInventoryListController(
        source,
        cache,
        () async => _session(const {Permissions.inventoryView}),
      );
      addTearDown(unauthorized.dispose);
      await unauthorized.refresh();
      await expectLater(
        unauthorized.create(const {'name': 'Blocked'}),
        throwsA(isA<StateError>()),
      );
      expect(source.inventoryCreateCalls, 0);

      final authorized = RemoteInventoryListController(
        source,
        cache,
        () async => _session(const {
          Permissions.inventoryView,
          Permissions.inventoryCreate,
        }),
      );
      addTearDown(authorized.dispose);
      await authorized.refresh();
      final created = await authorized.create(const {
        'submissionId': '561a66a4-baff-493c-916f-73cf36e36a19',
        'name': 'Amoxicillin 250 mg',
      });

      expect(source.inventoryCreateCalls, 1);
      expect(created.id, _inventoryId);
      expect(authorized.state.items.single.id, _inventoryId);
      final cached = await cache.get(
        'inventory:$_clinicId:',
        clinicId: _clinicId,
      );
      expect(cached?['items'], hasLength(1));
    },
  );

  test('confirmed inventory write survives controller disposal', () async {
    final completion = Completer<RemoteInventoryItem>();
    source.inventoryCreateCompletion = completion;
    final controller = RemoteInventoryListController(
      source,
      cache,
      () async => _session(const {
        Permissions.inventoryView,
        Permissions.inventoryCreate,
      }),
    );
    await controller.refresh();

    final creation = controller.create(const {
      'submissionId': 'bd49810f-cd21-4748-9c2b-2047083ef2e0',
      'name': 'Amoxicillin 250 mg',
    });
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    completion.complete(_inventoryItem());

    await expectLater(creation, completes);
    final cached = await cache.get(
      'inventory:$_clinicId:',
      clinicId: _clinicId,
    );
    expect(cached?['items'], hasLength(1));
  });

  test('consultation creation remains permission guarded', () async {
    final unauthorized = RemoteConsultationService(
      source,
      cache,
      () async => _session(const {Permissions.consultationsView}),
    );
    await expectLater(
      unauthorized.create(const {'chiefComplaint': 'Blocked'}),
      throwsA(isA<StateError>()),
    );
    expect(source.consultationCreateCalls, 0);

    final authorized = RemoteConsultationService(
      source,
      cache,
      () async => _session(const {
        Permissions.consultationsView,
        Permissions.consultationsCreate,
      }),
    );
    final created = await authorized.create(const {
      'submissionId': 'c0205ff9-bc94-4bfa-aa05-a3527760f488',
      'patientId': _patientId,
      'chiefComplaint': 'Reduced appetite',
    });

    expect(source.consultationCreateCalls, 1);
    expect(created.patientId, _patientId);
    final synchronization = await (database.select(
      database.cloudEntitySynchronizations,
    )..where((row) => row.serverId.equals(created.id))).getSingle();
    expect(synchronization.entityType, 'consultation');
  });
}

const _clinicId = '4fe1dc83-56af-4a36-b3c9-34c93029a537';
const _patientId = '1d919db7-68c4-4c73-a6c9-04c04b4f3795';
const _inventoryId = 'db681307-05a9-47ca-b6f6-8a8ba86037da';

UserSession _session(Set<String> permissions) => UserSession(
  clinic: Clinic(
    clinicId: _clinicId,
    clinicName: 'Avera Veterinary Clinic',
    clinicType: 'General Practice',
    currency: 'NGN',
    timeZone: 'Africa/Lagos',
    preferredLanguage: 'English',
    themeColor: '#087F7B',
    dateRegistered: DateTime(2026),
    subscriptionPlan: 'Professional',
    clinicStatus: 'Active',
    patientNumberSequenceLength: 5,
    patientNumberResetYearly: true,
    patientNumberPrefixReviewed: true,
  ),
  user: AppUser(
    userId: 'admin-user',
    clinicId: _clinicId,
    fullName: 'Clinic Administrator',
    username: 'admin@avera.test',
    email: 'admin@avera.test',
    passwordHash: 'not-used-in-this-test',
    role: 'Clinic Administrator',
    accountType: 'ClinicAdministrator',
    permissions: '[]',
    invitationStatus: 'Accepted',
    requiresPasswordChange: false,
    twoFactorEnabled: false,
    accountStatus: 'Active',
    membershipStatus: 'Active',
    rememberMe: false,
    sessionTimeoutMinutes: 30,
    createdAt: DateTime(2026),
  ),
  backendPermissions: permissions,
);

RemotePatient _patient({String status = 'Active', int revision = 1}) =>
    RemotePatient(
      id: _patientId,
      hospitalNumber: 'AVR-2026-00001',
      name: 'Luna',
      species: 'Cat',
      status: status,
      ownerName: 'Luna Owner',
      ownerPhone: '08000000000',
      breed: 'Domestic Shorthair',
      revision: revision,
    );

RemoteInventoryItem _inventoryItem() => RemoteInventoryItem(
  id: _inventoryId,
  name: 'Amoxicillin 250 mg',
  categoryId: 'drugs',
  categoryName: 'Drugs',
  quantity: 12,
  reorderLevel: 5,
  purchasePrice: 1200,
  sellingPrice: 1800,
  status: 'Active',
  revision: 1,
  updatedAt: DateTime(2026, 8, 1),
);

class _FakeClinicalRemoteDataSource extends ClinicalRemoteDataSource {
  _FakeClinicalRemoteDataSource()
    : super(
        ApiClient(
          baseUrl: 'https://example.invalid',
          tokens: const TokenStore(FlutterSecureStorage()),
        ),
      );

  List<RemotePatient> patientsValue = const [];
  List<RemoteInventoryItem> inventoryValue = const [];
  bool failInventory = false;
  int patientStatusCalls = 0;
  int inventoryCreateCalls = 0;
  int consultationCreateCalls = 0;
  Completer<RemoteInventoryItem>? inventoryCreateCompletion;

  @override
  Future<RemotePage<RemotePatient>> patients({
    int page = 1,
    int pageSize = 25,
    String? search,
    String? status,
  }) async {
    final filtered = status == null
        ? patientsValue
        : patientsValue.where((item) => item.status == status).toList();
    return RemotePage(
      items: filtered,
      page: page,
      pageSize: pageSize,
      total: filtered.length,
      hasNextPage: false,
    );
  }

  @override
  Future<RemotePatient> updatePatientStatus({
    required String patientId,
    required String status,
    String? reason,
  }) async {
    patientStatusCalls += 1;
    final updated = _patient(status: status, revision: 2);
    patientsValue = [updated];
    return updated;
  }

  @override
  Future<RemotePage<RemoteInventoryItem>> inventoryProducts({
    int page = 1,
    int pageSize = 100,
    String? search,
  }) async {
    if (failInventory) throw StateError('Network unavailable');
    return RemotePage(
      items: inventoryValue,
      page: page,
      pageSize: pageSize,
      total: inventoryValue.length,
      hasNextPage: false,
    );
  }

  @override
  Future<RemoteInventoryItem> createInventoryItem(
    Map<String, dynamic> payload,
  ) async {
    inventoryCreateCalls += 1;
    if (inventoryCreateCompletion case final completion?) {
      return completion.future;
    }
    final created = _inventoryItem();
    inventoryValue = [created];
    return created;
  }

  @override
  Future<RemoteConsultationCreation> createConsultation(
    Map<String, dynamic> payload,
  ) async {
    consultationCreateCalls += 1;
    return const RemoteConsultationCreation(
      id: 'dfb47924-a7dd-4300-9543-5be19fd80f41',
      patientId: _patientId,
      submissionId: 'c0205ff9-bc94-4bfa-aa05-a3527760f488',
      duplicateSubmission: false,
    );
  }
}
