import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../services/feature_gate_service.dart';

class LocalClinicSubscription {
  const LocalClinicSubscription({
    required this.clinicId,
    required this.plan,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.trialEndsAt,
    required this.gracePeriodEndsAt,
  });

  final String clinicId;
  final SubscriptionPlan plan;
  final SubscriptionStatus status;
  final DateTime startedAt;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;
  final DateTime? gracePeriodEndsAt;

  bool get isTrial => status == SubscriptionStatus.trial;
  bool get isInGracePeriod => status == SubscriptionStatus.gracePeriod;
}

class SubscriptionUsageSummary {
  const SubscriptionUsageSummary({
    required this.activePatients,
    required this.activeStaff,
    required this.clinics,
    required this.documents,
    required this.inventoryItems,
  });

  final int activePatients;
  final int activeStaff;
  final int clinics;
  final int documents;
  final int inventoryItems;
}

abstract class SubscriptionRepository {
  Future<void> ensureCatalog();
  Future<LocalClinicSubscription> ensureClinicSubscription(Clinic clinic);
  Future<LocalClinicSubscription?> getClinicSubscription(String clinicId);
  Stream<LocalClinicSubscription?> watchClinicSubscription(String clinicId);
  Future<SubscriptionUsageSummary> usageForClinic(String clinicId);
  Future<FeatureAccessResult> canAccess({
    required String clinicId,
    required AveraFeature feature,
    bool hasPermission = true,
  });
  Future<void> assignPlan({
    required String clinicId,
    required SubscriptionPlan plan,
    String? actingUserId,
    String action,
  });
}

/// Drift implementation for local-first development. It mirrors a future
/// remote repository's contract while keeping every decision on-device.
class LocalSubscriptionRepository implements SubscriptionRepository {
  LocalSubscriptionRepository(this.db);

  final AppDatabase db;
  final _uuid = const Uuid();

  @override
  Future<void> ensureCatalog() async {
    final now = DateTime.now();
    await db.transaction(() async {
      for (final definition in FeatureGateService.planDefinitions.values) {
        await db
            .into(db.subscriptionPlanRecords)
            .insertOnConflictUpdate(
              SubscriptionPlanRecordsCompanion.insert(
                planKey: definition.plan.label,
                displayName: definition.plan.label,
                positioning: definition.positioning,
                targetCustomer: definition.targetCustomer,
                monthlyPriceLabel: Value(definition.monthlyPriceLabel),
                annualPriceLabel: Value(definition.annualPriceLabel),
                isMostPopular: Value(definition.isMostPopular),
                isContactSales: Value(definition.isContactSales),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (final entitlement in FeatureGateService.all) {
        await db
            .into(db.subscriptionFeatures)
            .insertOnConflictUpdate(
              SubscriptionFeaturesCompanion.insert(
                featureKey: entitlement.key,
                displayName: entitlement.label,
                description: entitlement.reason,
                category: entitlement.category,
              ),
            );
      }
      for (final plan in SubscriptionPlan.values) {
        for (final entitlement in FeatureGateService.all) {
          final existing =
              await (db.select(db.planCapabilities)..where(
                    (capability) =>
                        capability.planKey.equals(plan.label) &
                        capability.featureKey.equals(entitlement.key),
                  ))
                  .getSingleOrNull();
          final enabled = plan.index >= entitlement.minimumPlan.index;
          if (existing == null) {
            await db
                .into(db.planCapabilities)
                .insert(
                  PlanCapabilitiesCompanion.insert(
                    planKey: plan.label,
                    featureKey: entitlement.key,
                    enabled: Value(enabled),
                    implementationStatus: Value(
                      entitlement.implementationStatus.name,
                    ),
                    releaseStage: Value(entitlement.implementationStatus.name),
                    numericLimit: Value(_defaultLimit(plan, entitlement)),
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
          }
        }
      }
    });
  }

  int? _defaultLimit(SubscriptionPlan plan, FeatureEntitlement entitlement) {
    final definition = FeatureGateService.plan(plan);
    if (entitlement.feature == AveraFeature.patientRecords) {
      return definition.patientLimit;
    }
    if (entitlement.feature == AveraFeature.staffAnalytics) {
      return definition.staffLimit;
    }
    return entitlement.numericLimit;
  }

  @override
  Future<LocalClinicSubscription> ensureClinicSubscription(
    Clinic clinic,
  ) async {
    await ensureCatalog();
    final existing =
        await (db.select(db.clinicSubscriptions)..where(
              (subscription) => subscription.clinicId.equals(clinic.clinicId),
            ))
            .getSingleOrNull();
    if (existing != null) return _map(existing);
    final now = DateTime.now();
    final plan = SubscriptionPlan.fromStorage(clinic.subscriptionPlan);
    await db
        .into(db.clinicSubscriptions)
        .insert(
          ClinicSubscriptionsCompanion.insert(
            id: _uuid.v4(),
            clinicId: clinic.clinicId,
            planKey: plan.label,
            status: const Value('active'),
            startedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _audit(
      clinicId: clinic.clinicId,
      action: 'subscription.migrated',
      newValue: plan.label,
      details: 'Created a local subscription record from the clinic plan.',
    );
    return (await getClinicSubscription(clinic.clinicId))!;
  }

  @override
  Future<LocalClinicSubscription?> getClinicSubscription(
    String clinicId,
  ) async {
    final row =
        await (db.select(db.clinicSubscriptions)
              ..where((subscription) => subscription.clinicId.equals(clinicId)))
            .getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Stream<LocalClinicSubscription?> watchClinicSubscription(String clinicId) {
    return (db.select(db.clinicSubscriptions)
          ..where((subscription) => subscription.clinicId.equals(clinicId)))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _map(row));
  }

  LocalClinicSubscription _map(ClinicSubscription row) =>
      LocalClinicSubscription(
        clinicId: row.clinicId,
        plan: SubscriptionPlan.fromStorage(row.planKey),
        status: SubscriptionStatus.fromStorage(row.status),
        startedAt: row.startedAt,
        expiresAt: row.expiresAt,
        trialEndsAt: row.trialEndsAt,
        gracePeriodEndsAt: row.gracePeriodEndsAt,
      );

  @override
  Future<SubscriptionUsageSummary> usageForClinic(String clinicId) async {
    final activePatients =
        await (db.select(db.animals)..where(
              (animal) =>
                  animal.clinicId.equals(clinicId) &
                  animal.status.equals('Active'),
            ))
            .get()
            .then((records) => records.length);
    final activeStaff =
        await (db.select(db.appUsers)..where(
              (user) =>
                  user.clinicId.equals(clinicId) &
                  user.accountStatus.equals('Active'),
            ))
            .get()
            .then((records) => records.length);
    final clinics = await db
        .select(db.clinics)
        .get()
        .then((records) => records.length);
    final documents =
        await (db.select(
          db.vaccinations,
        )..where((record) => record.clinicId.equals(clinicId))).get().then(
          (records) =>
              records.where((record) => record.certificatePdf != null).length,
        );
    final inventory =
        await (db.select(db.inventoryItems)
              ..where((item) => item.clinicId.equals(clinicId)))
            .get()
            .then((records) => records.length);
    final summary = SubscriptionUsageSummary(
      activePatients: activePatients,
      activeStaff: activeStaff,
      clinics: clinics,
      documents: documents,
      inventoryItems: inventory,
    );
    await _storeUsage(clinicId, summary);
    return summary;
  }

  @override
  Future<FeatureAccessResult> canAccess({
    required String clinicId,
    required AveraFeature feature,
    bool hasPermission = true,
  }) async {
    final subscription = await getClinicSubscription(clinicId);
    final clinic = await (db.select(
      db.clinics,
    )..where((item) => item.clinicId.equals(clinicId))).getSingle();
    final effective = subscription ?? await ensureClinicSubscription(clinic);
    final entitlement = FeatureGateService.entitlement(feature);
    final override =
        await (db.select(db.subscriptionOverrides)
              ..where(
                (row) =>
                    row.clinicId.equals(clinicId) &
                    row.featureKey.equals(entitlement.key),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
            .getSingleOrNull();
    final usage = await usageForClinic(clinicId);
    final limit = _usageLimit(effective.plan, feature);
    final currentUsage = _usageValue(usage, feature);
    return FeatureGateService.evaluate(
      subscriptionPlan: effective.plan.label,
      feature: feature,
      subscriptionStatus: effective.status.name,
      hasPermission: hasPermission,
      usage: currentUsage,
      limit: override?.numericLimit ?? limit,
      overrideEnabled: override?.enabled,
    );
  }

  int? _usageLimit(SubscriptionPlan plan, AveraFeature feature) {
    final definition = FeatureGateService.plan(plan);
    return switch (feature) {
      AveraFeature.patientRecords => definition.patientLimit,
      AveraFeature.staffAnalytics => definition.staffLimit,
      _ => null,
    };
  }

  int? _usageValue(SubscriptionUsageSummary usage, AveraFeature feature) {
    return switch (feature) {
      AveraFeature.patientRecords => usage.activePatients,
      AveraFeature.staffAnalytics => usage.activeStaff,
      _ => null,
    };
  }

  @override
  Future<void> assignPlan({
    required String clinicId,
    required SubscriptionPlan plan,
    String? actingUserId,
    String action = 'subscription.updated',
  }) async {
    await ensureCatalog();
    final existing = await getClinicSubscription(clinicId);
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.clinics)
            ..where((clinic) => clinic.clinicId.equals(clinicId)))
          .write(ClinicsCompanion(subscriptionPlan: Value(plan.label)));
      if (existing == null) {
        await db
            .into(db.clinicSubscriptions)
            .insert(
              ClinicSubscriptionsCompanion.insert(
                id: _uuid.v4(),
                clinicId: clinicId,
                planKey: plan.label,
                status: const Value('active'),
                startedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (db.update(db.clinicSubscriptions)
              ..where((subscription) => subscription.clinicId.equals(clinicId)))
            .write(
              ClinicSubscriptionsCompanion(
                planKey: Value(plan.label),
                status: const Value('active'),
                updatedAt: Value(now),
              ),
            );
      }
      await _audit(
        clinicId: clinicId,
        actingUserId: actingUserId,
        action: action,
        previousValue: existing?.plan.label,
        newValue: plan.label,
        details:
            'Local subscription plan changed without deleting clinic data.',
      );
      await _notify(
        clinicId: clinicId,
        type: 'Subscription',
        title: existing == null || plan.index >= existing.plan.index
            ? 'Plan upgraded'
            : 'Plan downgraded',
        message:
            'Your clinic is now on the ${plan.label} plan. Clinic data has been preserved.',
      );
    });
  }

  Future<void> startProfessionalTrial({
    required String clinicId,
    String? actingUserId,
    int days = 14,
  }) async {
    await assignPlan(
      clinicId: clinicId,
      plan: SubscriptionPlan.professional,
      actingUserId: actingUserId,
      action: 'subscription.trial_started',
    );
    final now = DateTime.now();
    final endsAt = now.add(Duration(days: days));
    await db.transaction(() async {
      await (db.update(
        db.clinicSubscriptions,
      )..where((subscription) => subscription.clinicId.equals(clinicId))).write(
        ClinicSubscriptionsCompanion(
          status: const Value('trial'),
          trialStartsAt: Value(now),
          trialEndsAt: Value(endsAt),
          updatedAt: Value(now),
        ),
      );
      await db
          .into(db.subscriptionTrials)
          .insert(
            SubscriptionTrialsCompanion.insert(
              id: _uuid.v4(),
              clinicId: clinicId,
              planKey: SubscriptionPlan.professional.label,
              startsAt: now,
              endsAt: endsAt,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _notify(
        clinicId: clinicId,
        type: 'Subscription',
        title: 'Professional trial started',
        message:
            'Your Professional trial ends on ${endsAt.toLocal().toString().split(' ').first}.',
      );
    });
  }

  Future<void> applyGracePeriod({
    required String clinicId,
    String? actingUserId,
    int days = 7,
  }) async {
    final now = DateTime.now();
    final endsAt = now.add(Duration(days: days));
    await db.transaction(() async {
      await (db.update(
        db.clinicSubscriptions,
      )..where((subscription) => subscription.clinicId.equals(clinicId))).write(
        ClinicSubscriptionsCompanion(
          status: const Value('gracePeriod'),
          gracePeriodEndsAt: Value(endsAt),
          updatedAt: Value(now),
        ),
      );
      await db
          .into(db.subscriptionGracePeriods)
          .insert(
            SubscriptionGracePeriodsCompanion.insert(
              id: _uuid.v4(),
              clinicId: clinicId,
              startsAt: now,
              endsAt: endsAt,
              reason: const Value('Local development grace period'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _audit(
        clinicId: clinicId,
        actingUserId: actingUserId,
        action: 'subscription.grace_period_started',
        newValue: 'Grace period until $endsAt',
      );
      await _notify(
        clinicId: clinicId,
        type: 'Subscription',
        title: 'Subscription grace period',
        message:
            'Your grace period ends on ${endsAt.toLocal().toString().split(' ').first}.',
      );
    });
  }

  Future<void> setOverride({
    required String clinicId,
    required AveraFeature feature,
    required bool enabled,
    int? numericLimit,
    String? actingUserId,
  }) async {
    final now = DateTime.now();
    await db
        .into(db.subscriptionOverrides)
        .insert(
          SubscriptionOverridesCompanion.insert(
            id: _uuid.v4(),
            clinicId: clinicId,
            featureKey: FeatureGateService.entitlement(feature).key,
            enabled: enabled,
            numericLimit: Value(numericLimit),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _audit(
      clinicId: clinicId,
      actingUserId: actingUserId,
      action: 'subscription.override_updated',
      newValue: '${FeatureGateService.entitlement(feature).key}=$enabled',
    );
  }

  Future<void> _audit({
    required String clinicId,
    required String action,
    String? actingUserId,
    String? previousValue,
    String? newValue,
    String? details,
  }) async {
    await db
        .into(db.subscriptionAuditLogs)
        .insert(
          SubscriptionAuditLogsCompanion.insert(
            clinicId: clinicId,
            actingUserId: Value(actingUserId),
            action: action,
            previousValue: Value(previousValue),
            newValue: Value(newValue),
            details: Value(details),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> _storeUsage(
    String clinicId,
    SubscriptionUsageSummary summary,
  ) async {
    final values = <String, int>{
      'patients.active': summary.activePatients,
      'staff.active': summary.activeStaff,
      'clinics.active': summary.clinics,
      'documents.total': summary.documents,
      'inventory.items': summary.inventoryItems,
    };
    final now = DateTime.now();
    for (final entry in values.entries) {
      final existing =
          await (db.select(db.subscriptionUsages)..where(
                (usage) =>
                    usage.clinicId.equals(clinicId) &
                    usage.usageKey.equals(entry.key),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.subscriptionUsages)
            .insert(
              SubscriptionUsagesCompanion.insert(
                clinicId: clinicId,
                usageKey: entry.key,
                currentValue: Value(entry.value),
                updatedAt: now,
              ),
            );
      } else {
        await (db.update(
          db.subscriptionUsages,
        )..where((usage) => usage.id.equals(existing.id))).write(
          SubscriptionUsagesCompanion(
            currentValue: Value(entry.value),
            updatedAt: Value(now),
          ),
        );
      }
    }
  }

  Future<void> _notify({
    required String clinicId,
    required String type,
    required String title,
    required String message,
  }) async {
    await db
        .into(db.notifications)
        .insert(
          NotificationsCompanion.insert(
            clinicId: Value(clinicId),
            type: type,
            title: title,
            message: message,
            createdAt: DateTime.now(),
          ),
        );
  }
}

/// Placeholder only. A future secure backend implementation can conform to
/// [SubscriptionRepository] without requiring feature-gate or UI changes.
abstract class RemoteSubscriptionRepository implements SubscriptionRepository {}
