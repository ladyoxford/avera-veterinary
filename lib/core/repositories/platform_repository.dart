import 'package:drift/drift.dart';

import '../database/app_database.dart';
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
}

abstract interface class PlatformRepository {
  Future<PlatformOverviewSnapshot> loadOverview(UserSession session);

  Stream<PlatformOverviewSnapshot> watchOverview(UserSession session);
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
