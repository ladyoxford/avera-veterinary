import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/repositories/subscription_repository.dart';
import 'package:avera/core/services/feature_gate_service.dart';

void main() {
  late AppDatabase database;
  late ClinicRepository clinics;
  late LocalSubscriptionRepository subscriptions;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    clinics = ClinicRepository(database);
    subscriptions = LocalSubscriptionRepository(database);
    await clinics.seedSampleData();
  });

  tearDown(() => database.close());

  test(
    'migrates the existing clinic plan to a local subscription record',
    () async {
      final subscription = await subscriptions.getClinicSubscription(
        defaultClinicId,
      );

      expect(subscription, isNotNull);
      expect(subscription!.plan, SubscriptionPlan.professional);
      expect(
        await database.select(database.subscriptionPlanRecords).get(),
        hasLength(3),
      );
      expect(
        await database.select(database.planCapabilities).get(),
        isNotEmpty,
      );
    },
  );

  test('plan changes preserve existing records and audit the change', () async {
    final patientCount = (await database.select(database.animals).get()).length;

    await subscriptions.assignPlan(
      clinicId: defaultClinicId,
      plan: SubscriptionPlan.starter,
      action: 'subscription.test_downgrade',
    );

    final subscription = await subscriptions.getClinicSubscription(
      defaultClinicId,
    );
    final audit =
        await (database.select(
              database.subscriptionAuditLogs,
            )..where((row) => row.action.equals('subscription.test_downgrade')))
            .getSingle();
    expect(subscription!.plan, SubscriptionPlan.starter);
    expect(
      (await database.select(database.animals).get()).length,
      patientCount,
    );
    expect(audit.newValue, 'Starter');
  });

  test('capabilities remain layered by plan and local override', () async {
    await subscriptions.assignPlan(
      clinicId: defaultClinicId,
      plan: SubscriptionPlan.starter,
      action: 'subscription.test',
    );
    expect(
      (await subscriptions.canAccess(
        clinicId: defaultClinicId,
        feature: AveraFeature.hospitalization,
      )).allowed,
      isFalse,
    );

    await subscriptions.assignPlan(
      clinicId: defaultClinicId,
      plan: SubscriptionPlan.professional,
      action: 'subscription.test',
    );
    expect(
      (await subscriptions.canAccess(
        clinicId: defaultClinicId,
        feature: AveraFeature.hospitalization,
      )).allowed,
      isTrue,
    );
    expect(
      (await subscriptions.canAccess(
        clinicId: defaultClinicId,
        feature: AveraFeature.corporateAnalytics,
      )).allowed,
      isFalse,
    );

    await subscriptions.setOverride(
      clinicId: defaultClinicId,
      feature: AveraFeature.corporateAnalytics,
      enabled: true,
    );
    expect(
      (await subscriptions.canAccess(
        clinicId: defaultClinicId,
        feature: AveraFeature.corporateAnalytics,
      )).allowed,
      isTrue,
    );
  });

  test('trial and grace period state persist locally', () async {
    await subscriptions.startProfessionalTrial(clinicId: defaultClinicId);
    var subscription = await subscriptions.getClinicSubscription(
      defaultClinicId,
    );
    expect(subscription!.status, SubscriptionStatus.trial);
    expect(subscription.trialEndsAt, isNotNull);

    await subscriptions.applyGracePeriod(clinicId: defaultClinicId);
    subscription = await subscriptions.getClinicSubscription(defaultClinicId);
    expect(subscription!.status, SubscriptionStatus.gracePeriod);
    expect(subscription.gracePeriodEndsAt, isNotNull);
  });
}
