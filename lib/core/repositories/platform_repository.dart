import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../remote/api_client.dart';
import 'clinic_repository.dart';

class PlatformOverviewSnapshot {
  const PlatformOverviewSnapshot({
    required this.totalClinics,
    required this.activeClinics,
    required this.pendingApplications,
    required this.suspendedClinics,
    required this.activeUsers,
    required this.expiredSubscriptions,
    required this.recentClinics,
    this.monthlyRevenue,
    this.currency = 'NGN',
    this.emailDeliveryStatus,
    this.systemHealthStatus,
    this.storageUsedBytes,
    this.storageAvailableBytes,
    this.isOffline = false,
  });

  final int totalClinics;
  final int activeClinics;
  final int pendingApplications;
  final int suspendedClinics;
  final int activeUsers;
  final int expiredSubscriptions;
  final List<Clinic> recentClinics;
  final double? monthlyRevenue;
  final String currency;
  final String? emailDeliveryStatus;
  final String? systemHealthStatus;
  final int? storageUsedBytes;
  final int? storageAvailableBytes;
  final bool isOffline;
}

class PlatformAdministratorActivation {
  const PlatformAdministratorActivation({
    required this.status,
    this.administratorName,
    this.email,
    this.expiresAt,
    this.deliveredAt,
    this.deliveryMethod,
    this.activationUrl,
    this.canResend = false,
  });

  final String status;
  final String? administratorName;
  final String? email;
  final DateTime? expiresAt;
  final DateTime? deliveredAt;
  final String? deliveryMethod;
  final String? activationUrl;
  final bool canResend;
}

class PlatformClinicApprovalResult {
  const PlatformClinicApprovalResult({
    required this.clinic,
    required this.activation,
  });

  final Clinic clinic;
  final PlatformAdministratorActivation activation;
}

class PlatformClinicApplicationPayment {
  const PlatformClinicApplicationPayment({
    required this.applicationReference,
    required this.paymentStatus,
  });

  final String applicationReference;
  final String paymentStatus;
}

abstract interface class PlatformRepository {
  Future<PlatformOverviewSnapshot> loadOverview(UserSession session);

  Stream<PlatformOverviewSnapshot> watchOverview(UserSession session);

  Future<List<Clinic>> loadClinics(UserSession session, {String? status});

  Stream<List<Clinic>> watchClinics(UserSession session, {String? status});

  Future<Clinic?> loadClinic(UserSession session, String clinicId);

  Future<PlatformClinicApplicationPayment?> loadClinicApplicationPayment(
    UserSession session,
    String clinicId,
  );

  Future<Clinic> updateClinicStatus({
    required UserSession session,
    required String clinicId,
    required String status,
  });

  Future<PlatformClinicApprovalResult> approveClinic({
    required UserSession session,
    required String clinicId,
  });

  Future<PlatformAdministratorActivation> loadAdministratorActivation({
    required UserSession session,
    required String clinicId,
  });

  Future<PlatformAdministratorActivation> resendAdministratorActivation({
    required UserSession session,
    required String clinicId,
  });

  Future<Clinic> updateClinicSubscription({
    required UserSession session,
    required String clinicId,
    required String plan,
  });
}

class LocalPlatformRepository implements PlatformRepository {
  LocalPlatformRepository(this.db);

  final AppDatabase db;

  @override
  Future<PlatformOverviewSnapshot> loadOverview(UserSession session) async {
    _ensurePlatformOwner(session);
    return _snapshotFromRow(await _totalsQuery().getSingle());
  }

  @override
  Stream<PlatformOverviewSnapshot> watchOverview(UserSession session) {
    _ensurePlatformOwner(session);
    return _totalsQuery().watchSingle().asyncMap(_snapshotFromRow);
  }

  @override
  Future<List<Clinic>> loadClinics(
    UserSession session, {
    String? status,
  }) async {
    _ensurePlatformOwner(session);
    return _clinicQuery(status).get();
  }

  @override
  Stream<List<Clinic>> watchClinics(UserSession session, {String? status}) {
    _ensurePlatformOwner(session);
    return _clinicQuery(status).watch();
  }

  @override
  Future<Clinic?> loadClinic(UserSession session, String clinicId) async {
    _ensurePlatformOwner(session);
    return (db.select(
      db.clinics,
    )..where((clinic) => clinic.clinicId.equals(clinicId))).getSingleOrNull();
  }

  @override
  Future<PlatformClinicApplicationPayment?> loadClinicApplicationPayment(
    UserSession session,
    String clinicId,
  ) async {
    _ensurePlatformOwner(session);
    return null;
  }

  @override
  Future<Clinic> updateClinicStatus({
    required UserSession session,
    required String clinicId,
    required String status,
  }) async {
    _ensurePlatformOwner(session);
    await ClinicRepository(db).updateClinicStatus(
      actingSession: session,
      clinicId: clinicId,
      status: status,
    );
    return (await loadClinic(session, clinicId))!;
  }

  @override
  Future<PlatformClinicApprovalResult> approveClinic({
    required UserSession session,
    required String clinicId,
  }) async {
    final clinic = await updateClinicStatus(
      session: session,
      clinicId: clinicId,
      status: 'Active',
    );
    return PlatformClinicApprovalResult(
      clinic: clinic,
      activation: const PlatformAdministratorActivation(
        status: 'LocalDevelopment',
      ),
    );
  }

  @override
  Future<PlatformAdministratorActivation> loadAdministratorActivation({
    required UserSession session,
    required String clinicId,
  }) async {
    _ensurePlatformOwner(session);
    return const PlatformAdministratorActivation(status: 'LocalDevelopment');
  }

  @override
  Future<PlatformAdministratorActivation> resendAdministratorActivation({
    required UserSession session,
    required String clinicId,
  }) async {
    _ensurePlatformOwner(session);
    final link = await ClinicRepository(db).createDevelopmentActivationLink(
      actingSession: session,
      clinicId: clinicId,
    );
    return PlatformAdministratorActivation(
      status: 'PendingActivation',
      deliveryMethod: 'manual',
      activationUrl: link,
      canResend: true,
    );
  }

  @override
  Future<Clinic> updateClinicSubscription({
    required UserSession session,
    required String clinicId,
    required String plan,
  }) async {
    _ensurePlatformOwner(session);
    await ClinicRepository(db).updateClinicSubscription(
      actingSession: session,
      clinicId: clinicId,
      plan: plan,
    );
    return (await loadClinic(session, clinicId))!;
  }

  void _ensurePlatformOwner(UserSession session) {
    if (!session.isPlatformOwner) {
      throw StateError('Platform Owner authorization is required.');
    }
  }

  Selectable<QueryRow> _totalsQuery() => db.customSelect(
    '''
      SELECT
        (SELECT COUNT(*) FROM clinics
          WHERE clinic_id <> 'platform-control') AS total_clinics,
        (SELECT COUNT(*) FROM clinics
          WHERE clinic_id <> 'platform-control'
            AND lower(clinic_status) = 'active') AS active_clinics,
        (SELECT COUNT(*) FROM clinics
          WHERE clinic_id <> 'platform-control'
            AND lower(clinic_status) IN ('pending', 'pendingapproval'))
          AS pending_applications,
        (SELECT COUNT(*) FROM clinics
          WHERE clinic_id <> 'platform-control'
            AND lower(clinic_status) = 'suspended') AS suspended_clinics,
        (SELECT COUNT(*) FROM app_users
          WHERE clinic_id <> 'platform-control'
            AND lower(account_status) = 'active'
            AND lower(membership_status) = 'active') AS active_users,
        (SELECT COUNT(*) FROM clinic_subscriptions
          WHERE lower(status) = 'expired') AS expired_subscriptions
      ''',
    readsFrom: {db.clinics, db.appUsers, db.clinicSubscriptions},
  );

  SimpleSelectStatement<$ClinicsTable, Clinic> _clinicQuery(String? status) {
    final query = db.select(db.clinics)
      ..where((clinic) => clinic.clinicId.equals('platform-control').not());
    if (status != null) {
      if (status.toLowerCase() == 'pending') {
        query.where(
          (clinic) =>
              clinic.clinicStatus.equals('Pending') |
              clinic.clinicStatus.equals('PendingApproval') |
              clinic.clinicStatus.equals('Awaiting Payment') |
              clinic.clinicStatus.equals('RegistrationDraft'),
        );
      } else {
        query.where((clinic) => clinic.clinicStatus.equals(status));
      }
    }
    query.orderBy([(clinic) => OrderingTerm.desc(clinic.dateRegistered)]);
    return query;
  }

  Future<PlatformOverviewSnapshot> _snapshotFromRow(QueryRow row) async {
    final recent =
        await (db.select(db.clinics)
              ..where(
                (clinic) => clinic.clinicId.equals('platform-control').not(),
              )
              ..orderBy([(clinic) => OrderingTerm.desc(clinic.dateRegistered)])
              ..limit(3))
            .get();
    final currencies = recent
        .map((clinic) => clinic.currency.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    return PlatformOverviewSnapshot(
      totalClinics: row.read<int>('total_clinics'),
      activeClinics: row.read<int>('active_clinics'),
      pendingApplications: row.read<int>('pending_applications'),
      suspendedClinics: row.read<int>('suspended_clinics'),
      activeUsers: row.read<int>('active_users'),
      expiredSubscriptions: row.read<int>('expired_subscriptions'),
      recentClinics: recent,
      currency: currencies.isEmpty ? 'NGN' : currencies.first,
      // Local mode has no verified platform payment or infrastructure feed.
      // Null deliberately means unavailable, rather than a misleading zero.
      monthlyRevenue: null,
      emailDeliveryStatus: null,
      systemHealthStatus: null,
      storageUsedBytes: null,
      storageAvailableBytes: null,
    );
  }
}

class RemotePlatformRepository implements PlatformRepository {
  RemotePlatformRepository({
    required this.db,
    required ApiClient apiClient,
    this.onOfflineChanged,
  }) : _apiClient = apiClient,
       _local = LocalPlatformRepository(db);

  final AppDatabase db;
  final ApiClient _apiClient;
  final LocalPlatformRepository _local;
  final void Function(bool offline)? onOfflineChanged;

  @override
  Future<PlatformOverviewSnapshot> loadOverview(UserSession session) async {
    _ensurePlatformAccount(session);
    try {
      final response = await _apiClient.get('/api/v1/platform/overview');
      final recent = _clinicList(response['recentClinics']);
      await _cacheClinics(recent);
      onOfflineChanged?.call(false);
      return PlatformOverviewSnapshot(
        totalClinics: _integer(response['totalClinics']),
        activeClinics: _integer(response['activeClinics']),
        pendingApplications: _integer(response['pendingApplications']),
        suspendedClinics: _integer(response['suspendedClinics']),
        activeUsers: _integer(response['activeUsers']),
        expiredSubscriptions: _integer(response['expiredSubscriptions']),
        recentClinics: recent,
        monthlyRevenue: _integer(response['monthlyRevenueMinor']) / 100,
        currency: response['currency'] as String? ?? 'NGN',
      );
    } on ApiException {
      onOfflineChanged?.call(true);
      final cached = await _local.loadOverview(session);
      return PlatformOverviewSnapshot(
        totalClinics: cached.totalClinics,
        activeClinics: cached.activeClinics,
        pendingApplications: cached.pendingApplications,
        suspendedClinics: cached.suspendedClinics,
        activeUsers: cached.activeUsers,
        expiredSubscriptions: cached.expiredSubscriptions,
        recentClinics: cached.recentClinics,
        monthlyRevenue: cached.monthlyRevenue,
        currency: cached.currency,
        emailDeliveryStatus: cached.emailDeliveryStatus,
        systemHealthStatus: cached.systemHealthStatus,
        storageUsedBytes: cached.storageUsedBytes,
        storageAvailableBytes: cached.storageAvailableBytes,
        isOffline: true,
      );
    }
  }

  @override
  Stream<PlatformOverviewSnapshot> watchOverview(UserSession session) async* {
    yield await loadOverview(session);
  }

  @override
  Future<List<Clinic>> loadClinics(
    UserSession session, {
    String? status,
  }) async {
    _ensurePlatformAccount(session);
    try {
      final query = status == null
          ? '?pageSize=100'
          : '?status=${Uri.encodeQueryComponent(status)}&pageSize=100';
      final response = await _apiClient.get('/api/v1/platform/clinics$query');
      final clinics = _clinicList(response['items'] ?? response['clinics']);
      await _cacheClinics(clinics);
      onOfflineChanged?.call(false);
      return clinics;
    } on ApiException {
      onOfflineChanged?.call(true);
      return _local.loadClinics(session, status: status);
    }
  }

  @override
  Stream<List<Clinic>> watchClinics(
    UserSession session, {
    String? status,
  }) async* {
    await loadClinics(session, status: status);
    yield* _local.watchClinics(session, status: status);
  }

  @override
  Future<Clinic?> loadClinic(UserSession session, String clinicId) async {
    _ensurePlatformAccount(session);
    try {
      final response = await _apiClient.get(
        '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}',
      );
      final value = response['clinic'];
      if (value is! Map<String, dynamic>) return null;
      final clinic = _clinicFromJson(value);
      await _cacheClinics([clinic]);
      onOfflineChanged?.call(false);
      return clinic;
    } on ApiException {
      onOfflineChanged?.call(true);
      return _local.loadClinic(session, clinicId);
    }
  }

  @override
  Future<PlatformClinicApplicationPayment?> loadClinicApplicationPayment(
    UserSession session,
    String clinicId,
  ) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.get(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}',
    );
    final value = response['clinic'];
    if (value is! Map<String, dynamic>) return null;
    final applicationReference = value['applicationReference'] as String?;
    final paymentStatus = value['paymentStatus'] as String?;
    if (applicationReference == null || applicationReference.trim().isEmpty) {
      return null;
    }
    return PlatformClinicApplicationPayment(
      applicationReference: applicationReference,
      paymentStatus: paymentStatus?.trim().isNotEmpty == true
          ? paymentStatus!
          : 'Pending',
    );
  }

  @override
  Future<Clinic> updateClinicStatus({
    required UserSession session,
    required String clinicId,
    required String status,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.patch(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/status',
      body: {'status': status},
    );
    final clinic = _clinicFromJson(response['clinic'] as Map<String, dynamic>);
    await _cacheClinics([clinic]);
    onOfflineChanged?.call(false);
    return clinic;
  }

  @override
  Future<PlatformClinicApprovalResult> approveClinic({
    required UserSession session,
    required String clinicId,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.patch(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/status',
      body: const {'status': 'Active'},
    );
    final clinic = _clinicFromJson(response['clinic'] as Map<String, dynamic>);
    await _cacheClinics([clinic]);
    onOfflineChanged?.call(false);
    return PlatformClinicApprovalResult(
      clinic: clinic,
      activation: _activation(response['activation']),
    );
  }

  @override
  Future<PlatformAdministratorActivation> loadAdministratorActivation({
    required UserSession session,
    required String clinicId,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.get(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/administrator-activation',
    );
    return _activation(response['activation']);
  }

  @override
  Future<PlatformAdministratorActivation> resendAdministratorActivation({
    required UserSession session,
    required String clinicId,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.post(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/administrator-activation/resend',
      authenticated: true,
    );
    return _activation(response['activation']);
  }

  @override
  Future<Clinic> updateClinicSubscription({
    required UserSession session,
    required String clinicId,
    required String plan,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.patch(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/subscription',
      body: {'plan': plan},
    );
    final clinic = _clinicFromJson(response['clinic'] as Map<String, dynamic>);
    await _cacheClinics([clinic]);
    onOfflineChanged?.call(false);
    return clinic;
  }

  void _ensurePlatformAccount(UserSession session) {
    if (!session.isPlatformAccount) {
      throw StateError('Platform administration authorization is required.');
    }
  }

  List<Clinic> _clinicList(Object? value) {
    return (value as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_clinicFromJson)
        .toList(growable: false);
  }

  PlatformAdministratorActivation _activation(Object? value) {
    final json = value is Map<String, dynamic>
        ? value
        : const <String, dynamic>{};
    return PlatformAdministratorActivation(
      status: json['status'] as String? ?? 'NotProvisioned',
      administratorName: json['administratorName'] as String?,
      email: json['email'] as String?,
      expiresAt: _date(json['expiresAt']),
      deliveredAt: _date(json['deliveredAt']),
      deliveryMethod: json['deliveryMethod'] as String?,
      activationUrl: json['activationUrl'] as String?,
      canResend:
          json['canResend'] as bool? ?? json['status'] == 'PendingActivation',
    );
  }

  DateTime? _date(Object? value) => value is String
      ? DateTime.tryParse(value)
      : value is DateTime
      ? value
      : null;

  Clinic _clinicFromJson(Map<String, dynamic> json) {
    return Clinic(
      clinicId: json['clinicId'] as String,
      clinicName: json['clinicName'] as String? ?? 'Unnamed Clinic',
      logo: null,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: null,
      country: json['country'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      email: json['email'] as String?,
      website: null,
      veterinaryLicenseNumber: null,
      businessRegistrationNumber: null,
      clinicType: 'General Practice',
      workingHours: null,
      emergencyContact: null,
      currency: 'NGN',
      timeZone: json['timeZone'] as String? ?? 'Africa/Lagos',
      preferredLanguage: 'English',
      themeColor: '#087F7B',
      banner: null,
      stamp: null,
      signature: null,
      clinicOwner: null,
      dateRegistered:
          DateTime.tryParse(json['registrationDate'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      subscriptionPlan: json['subscriptionPlan'] as String? ?? 'Starter',
      clinicStatus: _normalizeStatus(json['status'] as String?),
      patientNumberPrefix: null,
      patientNumberSequenceLength: 5,
      patientNumberResetYearly: true,
      patientNumberPrefixReviewed: false,
      patientNumberLastChangedAt: null,
      patientNumberLastChangedBy: null,
    );
  }

  Future<void> _cacheClinics(List<Clinic> clinics) async {
    if (clinics.isEmpty) return;
    await db.batch((batch) {
      for (final clinic in clinics) {
        batch.insert(
          db.clinics,
          ClinicsCompanion.insert(
            clinicId: clinic.clinicId,
            clinicName: clinic.clinicName,
            logo: Value(clinic.logo),
            address: Value(clinic.address),
            city: Value(clinic.city),
            state: Value(clinic.state),
            country: Value(clinic.country),
            phoneNumber: Value(clinic.phoneNumber),
            email: Value(clinic.email),
            currency: Value(clinic.currency),
            timeZone: Value(clinic.timeZone),
            clinicOwner: Value(clinic.clinicOwner),
            dateRegistered: clinic.dateRegistered,
            subscriptionPlan: Value(clinic.subscriptionPlan),
            clinicStatus: Value(clinic.clinicStatus),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }
}

int _integer(Object? value) => (value as num?)?.toInt() ?? 0;

String _normalizeStatus(String? value) {
  final normalized = value?.toLowerCase();
  if (normalized == 'registrationdraft' || normalized == 'awaitingpayment') {
    return 'Awaiting Payment';
  }
  return normalized == 'pendingapproval' ? 'Pending' : value ?? 'Pending';
}
