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
    this.storageStatus,
    this.storageProvider,
    this.storageObjectCount,
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
  final String? storageStatus;
  final String? storageProvider;
  final int? storageObjectCount;
  final int? storageUsedBytes;
  final int? storageAvailableBytes;
  final bool isOffline;
}

class PlatformSubscriptionRecord {
  const PlatformSubscriptionRecord({
    required this.clinicId,
    required this.clinicName,
    required this.plan,
    required this.status,
    required this.billingCycle,
    this.email,
    this.currentPeriodEnd,
  });
  final String clinicId;
  final String clinicName;
  final String? email;
  final String plan;
  final String status;
  final String billingCycle;
  final DateTime? currentPeriodEnd;
}

class PlatformPaymentRecord {
  const PlatformPaymentRecord({
    required this.reference,
    required this.clinicName,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.mode,
    this.paidAt,
  });
  final String reference;
  final String clinicName;
  final int amountMinor;
  final String currency;
  final String status;
  final String mode;
  final DateTime? paidAt;
}

class PlatformSubscriptionsSnapshot {
  const PlatformSubscriptionsSnapshot({
    required this.items,
    required this.payments,
    required this.total,
    required this.active,
    required this.expiring,
    required this.expired,
    required this.paymentIssues,
    required this.monthlyRevenueMinor,
    required this.page,
    required this.pageSize,
    required this.hasNextPage,
  });
  final List<PlatformSubscriptionRecord> items;
  final List<PlatformPaymentRecord> payments;
  final int total;
  final int active;
  final int expiring;
  final int expired;
  final int paymentIssues;
  final int monthlyRevenueMinor;
  final int page;
  final int pageSize;
  final bool hasNextPage;
}

class PlatformUserRecord {
  const PlatformUserRecord({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.accountType,
    required this.status,
    this.lastLoginAt,
  });
  final String userId;
  final String fullName;
  final String email;
  final String accountType;
  final String status;
  final DateTime? lastLoginAt;
}

class PlatformUserPage {
  const PlatformUserPage({required this.items, required this.total});
  final List<PlatformUserRecord> items;
  final int total;
}

class PlatformAuditRecord {
  const PlatformAuditRecord({
    required this.auditId,
    required this.action,
    required this.targetType,
    required this.createdAt,
    required this.success,
    this.actorName,
    this.clinicName,
    this.reason,
    this.targetId,
    this.previousSummary,
    this.newSummary,
  });
  final String auditId;
  final String action;
  final String targetType;
  final DateTime createdAt;
  final bool success;
  final String? actorName;
  final String? clinicName;
  final String? reason;
  final String? targetId;
  final Map<String, dynamic>? previousSummary;
  final Map<String, dynamic>? newSummary;
}

class PlatformAuditPage {
  const PlatformAuditPage({required this.items, required this.total});
  final List<PlatformAuditRecord> items;
  final int total;
}

class PlatformNotificationRecord {
  const PlatformNotificationRecord({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.route,
    required this.createdAt,
  });
  final String id;
  final String title;
  final String message;
  final String severity;
  final String route;
  final DateTime createdAt;
}

class PlatformNotificationSnapshot {
  const PlatformNotificationSnapshot({
    required this.items,
    required this.supportsReadState,
  });
  final List<PlatformNotificationRecord> items;
  final bool supportsReadState;
}

class PlatformOperationsSnapshot {
  const PlatformOperationsSnapshot({
    required this.systemStatus,
    required this.databaseStatus,
    required this.emailStatus,
    required this.storageStatus,
    required this.emailProvider,
    required this.storageProvider,
    required this.objectCount,
    required this.lastAttemptAt,
    required this.isUnavailable,
    required this.paymentProvider,
    required this.paymentMode,
    required this.paymentStatus,
  });
  final String systemStatus;
  final String databaseStatus;
  final String emailStatus;
  final String storageStatus;
  final String emailProvider;
  final String storageProvider;
  final int? objectCount;
  final DateTime? lastAttemptAt;
  final bool isUnavailable;
  final String paymentProvider;
  final String paymentMode;
  final String paymentStatus;
}

class PlatformAdministratorActivation {
  const PlatformAdministratorActivation({
    required this.status,
    this.administratorName,
    this.email,
    this.expiresAt,
    this.submittedAt,
    this.deliveredAt,
    this.deliveryMethod,
    this.emailState,
    this.provider,
    this.providerMessageId,
    this.failureCode,
    this.activationUrl,
    this.reason,
    this.canResend = false,
  });

  final String status;
  final String? administratorName;
  final String? email;
  final DateTime? expiresAt;
  final DateTime? submittedAt;
  final DateTime? deliveredAt;
  final String? deliveryMethod;
  final String? emailState;
  final String? provider;
  final String? providerMessageId;
  final String? failureCode;
  final String? activationUrl;
  final String? reason;
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
    this.applicationStatus,
    this.transactionStatus,
    this.accountEmail,
    this.administratorName,
    this.administratorPhone,
    this.professionalTitle,
    this.paymentReference,
    this.amountMinor,
    this.currency,
    this.billingCycle,
    this.paidAt,
    this.requiresIdentityReview = false,
  });

  final String applicationReference;
  final String paymentStatus;
  final String? applicationStatus;
  final String? transactionStatus;
  final String? accountEmail;
  final String? administratorName;
  final String? administratorPhone;
  final String? professionalTitle;
  final String? paymentReference;
  final int? amountMinor;
  final String? currency;
  final String? billingCycle;
  final DateTime? paidAt;
  final bool requiresIdentityReview;
}

class PlatformPaymentReconciliation {
  const PlatformPaymentReconciliation({
    required this.verified,
    required this.applicationApproved,
    this.message,
    this.issueCode,
  });

  final bool verified;
  final bool applicationApproved;
  final String? message;
  final String? issueCode;
}

class PlatformClinicDeletionChallenge {
  const PlatformClinicDeletionChallenge({
    required this.requestId,
    required this.recipientEmail,
    required this.expiresAt,
    required this.attemptsRemaining,
  });

  final String requestId;
  final String recipientEmail;
  final DateTime expiresAt;
  final int attemptsRemaining;
}

abstract interface class PlatformRepository {
  Future<PlatformOverviewSnapshot> loadOverview(UserSession session);

  Stream<PlatformOverviewSnapshot> watchOverview(UserSession session);

  Future<List<Clinic>> loadClinics(
    UserSession session, {
    String? status,
    String? search,
  });

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

  Future<PlatformAdministratorActivation> repairAdministratorActivation({
    required UserSession session,
    required String clinicId,
  });

  Future<PlatformPaymentReconciliation> reconcileClinicPayment({
    required UserSession session,
    required String clinicId,
  });

  Future<PlatformClinicDeletionChallenge> requestClinicDeletion({
    required UserSession session,
    required String clinicId,
    required String reason,
  });

  Future<void> confirmClinicDeletion({
    required UserSession session,
    required String clinicId,
    required String requestId,
    required String code,
  });

  Future<Clinic> updateClinicSubscription({
    required UserSession session,
    required String clinicId,
    required String plan,
  });

  Future<PlatformSubscriptionsSnapshot> loadSubscriptions(
    UserSession session, {
    String? status,
    String? search,
    int page = 1,
    int pageSize = 25,
  });

  Future<PlatformUserPage> loadPlatformUsers(
    UserSession session, {
    String? status,
  });

  Future<void> updatePlatformUserStatus({
    required UserSession session,
    required String userId,
    required String status,
    String? reason,
  });

  Future<PlatformAuditPage> loadPlatformAuditLogs(UserSession session);

  Future<PlatformNotificationSnapshot> loadPlatformNotifications(
    UserSession session,
  );

  Future<PlatformOperationsSnapshot> loadOperations(UserSession session);
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
    String? search,
  }) async {
    _ensurePlatformOwner(session);
    return _clinicQuery(status, search: search).get();
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
  Future<PlatformAdministratorActivation> repairAdministratorActivation({
    required UserSession session,
    required String clinicId,
  }) => resendAdministratorActivation(session: session, clinicId: clinicId);

  @override
  Future<PlatformPaymentReconciliation> reconcileClinicPayment({
    required UserSession session,
    required String clinicId,
  }) async {
    _ensurePlatformOwner(session);
    throw StateError('Paystack reconciliation requires the AVERA backend.');
  }

  @override
  Future<PlatformClinicDeletionChallenge> requestClinicDeletion({
    required UserSession session,
    required String clinicId,
    required String reason,
  }) async {
    _ensurePlatformOwner(session);
    throw StateError('Mutual clinic deletion requires the AVERA backend.');
  }

  @override
  Future<void> confirmClinicDeletion({
    required UserSession session,
    required String clinicId,
    required String requestId,
    required String code,
  }) async {
    _ensurePlatformOwner(session);
    throw StateError('Mutual clinic deletion requires the AVERA backend.');
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

  @override
  Future<PlatformSubscriptionsSnapshot> loadSubscriptions(
    UserSession session, {
    String? status,
    String? search,
    int page = 1,
    int pageSize = 25,
  }) async {
    _ensurePlatformOwner(session);
    return PlatformSubscriptionsSnapshot(
      items: [],
      payments: [],
      total: 0,
      active: 0,
      expiring: 0,
      expired: 0,
      paymentIssues: 0,
      monthlyRevenueMinor: 0,
      page: page,
      pageSize: pageSize,
      hasNextPage: false,
    );
  }

  @override
  Future<PlatformUserPage> loadPlatformUsers(
    UserSession session, {
    String? status,
  }) async {
    _ensurePlatformOwner(session);
    return const PlatformUserPage(items: [], total: 0);
  }

  @override
  Future<void> updatePlatformUserStatus({
    required UserSession session,
    required String userId,
    required String status,
    String? reason,
  }) async {
    _ensurePlatformOwner(session);
    throw StateError('Platform account management requires the AVERA backend.');
  }

  @override
  Future<PlatformAuditPage> loadPlatformAuditLogs(UserSession session) async {
    _ensurePlatformOwner(session);
    return const PlatformAuditPage(items: [], total: 0);
  }

  @override
  Future<PlatformNotificationSnapshot> loadPlatformNotifications(
    UserSession session,
  ) async {
    _ensurePlatformOwner(session);
    return const PlatformNotificationSnapshot(
      items: [],
      supportsReadState: false,
    );
  }

  @override
  Future<PlatformOperationsSnapshot> loadOperations(UserSession session) async {
    _ensurePlatformOwner(session);
    return const PlatformOperationsSnapshot(
      systemStatus: 'Unavailable',
      databaseStatus: 'Local development',
      emailStatus: 'Unavailable',
      storageStatus: 'Unavailable',
      emailProvider: 'Not configured',
      storageProvider: 'Supabase Storage',
      objectCount: null,
      lastAttemptAt: null,
      isUnavailable: true,
      paymentProvider: 'Paystack',
      paymentMode: 'Unavailable',
      paymentStatus: 'Unavailable',
    );
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

  SimpleSelectStatement<$ClinicsTable, Clinic> _clinicQuery(
    String? status, {
    String? search,
  }) {
    final query = db.select(db.clinics)
      ..where(
        (clinic) =>
            clinic.clinicId.equals('platform-control').not() &
            clinic.clinicStatus.equals('Deleted').not(),
      );
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
    final normalizedSearch = search?.trim().toLowerCase();
    if (normalizedSearch?.isNotEmpty == true) {
      query.where(
        (clinic) =>
            clinic.clinicName.lower().contains(normalizedSearch!) |
            clinic.email.lower().contains(normalizedSearch) |
            clinic.city.lower().contains(normalizedSearch),
      );
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
        emailDeliveryStatus: response['emailDeliveryStatus'] as String?,
        systemHealthStatus: response['systemHealthStatus'] as String?,
        storageStatus: response['storageStatus'] as String?,
        storageProvider: response['storageProvider'] as String?,
        storageObjectCount: _nullableInteger(response['storageObjectCount']),
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
        storageStatus: cached.storageStatus,
        storageProvider: cached.storageProvider,
        storageObjectCount: cached.storageObjectCount,
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
    String? search,
  }) async {
    _ensurePlatformAccount(session);
    try {
      final queryParameters = <String, String>{'pageSize': '100'};
      if (status != null) queryParameters['status'] = status;
      if (search?.trim().isNotEmpty == true) {
        queryParameters['search'] = search!.trim();
      }
      final query = '?${Uri(queryParameters: queryParameters).query}';
      final response = await _apiClient.get('/api/v1/platform/clinics$query');
      final clinics = _clinicList(response['items'] ?? response['clinics']);
      await _cacheClinics(clinics);
      onOfflineChanged?.call(false);
      return clinics;
    } on ApiException {
      onOfflineChanged?.call(true);
      return _local.loadClinics(session, status: status, search: search);
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
      applicationStatus: value['applicationStatus'] as String?,
      transactionStatus: value['transactionStatus'] as String?,
      accountEmail: value['accountEmail'] as String?,
      administratorName: value['administratorName'] as String?,
      administratorPhone: value['administratorPhone'] as String?,
      professionalTitle: value['professionalTitle'] as String?,
      paymentReference: value['paymentReference'] as String?,
      amountMinor: _nullableInteger(value['paymentAmountMinor']),
      currency: value['paymentCurrency'] as String?,
      billingCycle: value['paymentBillingCycle'] as String?,
      paidAt: _date(value['paymentPaidAt']),
      requiresIdentityReview:
          (value['paymentSummary']
              as Map<String, dynamic>?)?['registrationIdentityChanged'] ==
          true,
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
  Future<PlatformAdministratorActivation> repairAdministratorActivation({
    required UserSession session,
    required String clinicId,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.post(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/administrator-activation/repair',
      authenticated: true,
    );
    return _activation(response['activation']);
  }

  @override
  Future<PlatformPaymentReconciliation> reconcileClinicPayment({
    required UserSession session,
    required String clinicId,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.post(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/payment/reconcile',
      authenticated: true,
    );
    final issue = response['approvalIssue'] is Map<String, dynamic>
        ? response['approvalIssue'] as Map<String, dynamic>
        : null;
    return PlatformPaymentReconciliation(
      verified: response['verified'] == true,
      applicationApproved: response['applicationApproved'] == true,
      message: issue?['message'] as String?,
      issueCode: issue?['code'] as String?,
    );
  }

  @override
  Future<PlatformClinicDeletionChallenge> requestClinicDeletion({
    required UserSession session,
    required String clinicId,
    required String reason,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.post(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/deletion-requests',
      body: {'reason': reason},
      authenticated: true,
    );
    final value = response['deletionRequest'] as Map<String, dynamic>;
    return PlatformClinicDeletionChallenge(
      requestId: value['requestId'] as String,
      recipientEmail: value['recipientEmail'] as String,
      expiresAt: _date(value['expiresAt'])!,
      attemptsRemaining: _integer(value['attemptsRemaining']),
    );
  }

  @override
  Future<void> confirmClinicDeletion({
    required UserSession session,
    required String clinicId,
    required String requestId,
    required String code,
  }) async {
    _ensurePlatformAccount(session);
    await _apiClient.post(
      '/api/v1/platform/clinics/${Uri.encodeComponent(clinicId)}/deletion-requests/${Uri.encodeComponent(requestId)}/confirm',
      body: {'code': code},
      authenticated: true,
    );
    await (db.update(db.clinics)
          ..where((clinic) => clinic.clinicId.equals(clinicId)))
        .write(const ClinicsCompanion(clinicStatus: Value('Deleted')));
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

  @override
  Future<PlatformSubscriptionsSnapshot> loadSubscriptions(
    UserSession session, {
    String? status,
    String? search,
    int page = 1,
    int pageSize = 25,
  }) async {
    _ensurePlatformAccount(session);
    final query = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      if (status?.trim().isNotEmpty == true) 'status': status!.trim(),
      if (search?.trim().isNotEmpty == true) 'search': search!.trim(),
    };
    final response = await _apiClient.get(
      Uri(
        path: '/api/v1/platform/subscriptions',
        queryParameters: query,
      ).toString(),
    );
    final summary = response['summary'] as Map<String, dynamic>? ?? const {};
    return PlatformSubscriptionsSnapshot(
      items: _maps(response['items'])
          .map(
            (json) => PlatformSubscriptionRecord(
              clinicId: json['clinicId'] as String,
              clinicName: json['clinicName'] as String? ?? 'Unnamed Clinic',
              email: json['email'] as String?,
              plan: json['plan'] as String? ?? 'Unknown',
              status: json['status'] as String? ?? 'Pending',
              billingCycle: json['billingCycle'] as String? ?? 'monthly',
              currentPeriodEnd: _date(json['currentPeriodEnd']),
            ),
          )
          .toList(growable: false),
      payments: _maps(response['payments'])
          .map(
            (json) => PlatformPaymentRecord(
              reference: json['reference'] as String? ?? 'Unknown reference',
              clinicName: json['clinicName'] as String? ?? 'Unknown clinic',
              amountMinor: _integer(json['amountMinor']),
              currency: json['currency'] as String? ?? 'NGN',
              status: json['status'] as String? ?? 'Pending',
              mode: json['mode'] as String? ?? 'unknown',
              paidAt: _date(json['paidAt']),
            ),
          )
          .toList(growable: false),
      total: _integer(response['total']),
      active: _integer(summary['active']),
      expiring: _integer(summary['expiring']),
      expired: _integer(summary['expired']),
      paymentIssues: _integer(summary['paymentIssues']),
      monthlyRevenueMinor: _integer(summary['monthlyRevenueMinor']),
      page: _integer(response['page']) == 0 ? page : _integer(response['page']),
      pageSize: _integer(response['pageSize']) == 0
          ? pageSize
          : _integer(response['pageSize']),
      hasNextPage: response['hasNextPage'] as bool? ?? false,
    );
  }

  @override
  Future<PlatformUserPage> loadPlatformUsers(
    UserSession session, {
    String? status,
  }) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.get(
      Uri(
        path: '/api/v1/platform/users',
        queryParameters: {
          'pageSize': '100',
          if (status?.trim().isNotEmpty == true) 'status': status!.trim(),
        },
      ).toString(),
    );
    return PlatformUserPage(
      total: _integer(response['total']),
      items: _maps(response['items'])
          .map(
            (json) => PlatformUserRecord(
              userId: json['userId'] as String,
              fullName: json['fullName'] as String? ?? 'Unnamed user',
              email: json['email'] as String? ?? '',
              accountType:
                  json['accountType'] as String? ?? 'PlatformAdministrator',
              status: json['status'] as String? ?? 'Unknown',
              lastLoginAt: _date(json['lastLoginAt']),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> updatePlatformUserStatus({
    required UserSession session,
    required String userId,
    required String status,
    String? reason,
  }) async {
    _ensurePlatformAccount(session);
    await _apiClient.patch(
      '/api/v1/platform/users/${Uri.encodeComponent(userId)}/status',
      body: {
        'status': status,
        if (reason?.trim().isNotEmpty == true) 'reason': reason!.trim(),
      },
    );
  }

  @override
  Future<PlatformAuditPage> loadPlatformAuditLogs(UserSession session) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.get(
      '/api/v1/platform/audit-logs?pageSize=100',
    );
    return PlatformAuditPage(
      total: _integer(response['total']),
      items: _maps(response['items'])
          .map(
            (json) => PlatformAuditRecord(
              auditId: json['auditId'] as String,
              action: json['action'] as String? ?? 'Unknown action',
              targetType: json['targetType'] as String? ?? 'Unknown target',
              createdAt:
                  _date(json['createdAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              success: json['success'] as bool? ?? true,
              actorName: json['actorName'] as String?,
              clinicName: json['clinicName'] as String?,
              reason: json['reason'] as String?,
              targetId: json['targetId'] as String?,
              previousSummary: json['previousSummary'] is Map
                  ? Map<String, dynamic>.from(json['previousSummary'] as Map)
                  : null,
              newSummary: json['newSummary'] is Map
                  ? Map<String, dynamic>.from(json['newSummary'] as Map)
                  : null,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<PlatformNotificationSnapshot> loadPlatformNotifications(
    UserSession session,
  ) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.get('/api/v1/platform/notifications');
    return PlatformNotificationSnapshot(
      supportsReadState: response['supportsReadState'] as bool? ?? false,
      items: _maps(response['items'])
          .map(
            (json) => PlatformNotificationRecord(
              id: json['id'] as String,
              title: json['title'] as String? ?? 'Platform notification',
              message: json['message'] as String? ?? '',
              severity: json['severity'] as String? ?? 'info',
              route: json['route'] as String? ?? '/platform',
              createdAt:
                  _date(json['createdAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<PlatformOperationsSnapshot> loadOperations(UserSession session) async {
    _ensurePlatformAccount(session);
    final response = await _apiClient.get('/api/v1/platform/operations/status');
    final system = response['system'] as Map<String, dynamic>? ?? const {};
    final email = response['email'] as Map<String, dynamic>? ?? const {};
    final storage = response['storage'] as Map<String, dynamic>? ?? const {};
    final payments = response['payments'] as Map<String, dynamic>? ?? const {};
    return PlatformOperationsSnapshot(
      systemStatus: system['status'] as String? ?? 'Unknown',
      databaseStatus: system['database'] as String? ?? 'Unknown',
      emailStatus: email['status'] as String? ?? 'Unknown',
      storageStatus: storage['status'] as String? ?? 'Unknown',
      emailProvider: email['provider'] as String? ?? 'Unknown',
      storageProvider: storage['provider'] as String? ?? 'Supabase Storage',
      objectCount: _nullableInteger(storage['objectCount']),
      lastAttemptAt: _date(email['lastAttemptAt']),
      isUnavailable: false,
      paymentProvider: payments['provider'] as String? ?? 'Paystack',
      paymentMode: payments['mode'] as String? ?? 'Not configured',
      paymentStatus: payments['status'] as String? ?? 'Not configured',
    );
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
      submittedAt: _date(json['submittedAt']),
      deliveredAt: _date(json['deliveredAt']),
      deliveryMethod: json['deliveryMethod'] as String?,
      emailState: json['emailState'] as String?,
      provider: json['provider'] as String?,
      providerMessageId: json['providerMessageId'] as String?,
      failureCode: json['failureCode'] as String?,
      activationUrl: json['activationUrl'] as String?,
      reason: json['reason'] as String? ?? json['failureReason'] as String?,
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

int? _nullableInteger(Object? value) => (value as num?)?.toInt();

List<Map<String, dynamic>> _maps(Object? value) =>
    (value as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

String _normalizeStatus(String? value) {
  final normalized = value?.toLowerCase();
  if (normalized == 'registrationdraft' || normalized == 'awaitingpayment') {
    return 'Awaiting Payment';
  }
  return normalized == 'pendingapproval' ? 'Pending' : value ?? 'Pending';
}
