import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../database/app_database.dart';
import '../models/animal_search_result.dart';
import '../models/clinic_work_hours.dart';
import '../models/platform_support_session.dart';
import '../repositories/clinic_repository.dart';
import '../repositories/authentication_repository.dart';
import '../remote/api_client.dart';
import '../remote/auth_remote_data_source.dart';
import '../remote/backend_auth_remote_data_source.dart';
import '../services/offline_authorization_service.dart';
import '../repositories/offline_sync_repository.dart';
import '../repositories/platform_repository.dart';
import '../repositories/subscription_repository.dart';
import '../security/access_control.dart';
import '../services/offline_sync_coordinator.dart';
import '../services/local_session_store.dart';
import '../services/clinic_operating_status_service.dart';
import '../services/hospital_numbering.dart';
import '../services/appointment_notification_service.dart';
import '../services/hospital_load_test_seeder.dart';
import '../services/bioqarah_receipt_importer.dart';
import '../services/biometric_auth_service.dart';
import '../subscription/subscription_payment_gateway.dart';

enum AnimalStatusFilter {
  active('Active'),
  all('All Animals'),
  deceased('Deceased'),
  relocated('Relocated');

  const AnimalStatusFilter(this.label);

  final String label;
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final appClockProvider = Provider<AppClock>((ref) => const LocalAppClock());

/// Replaced in tests to make age previews and current-age displays deterministic.
final animalAgeReferenceDateProvider = Provider<DateTime>(
  (ref) => DateTime.now(),
);

final clinicRepositoryProvider = Provider<ClinicRepository>((ref) {
  return ClinicRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(appClockProvider),
  );
});

final platformRepositoryProvider = Provider<PlatformRepository>((ref) {
  return LocalPlatformRepository(ref.watch(databaseProvider));
});

final platformOverviewProvider = StreamProvider<PlatformOverviewSnapshot>((
  ref,
) async* {
  final session = await ref.watch(userSessionProvider.future);
  final repository = ref.watch(platformRepositoryProvider);
  yield await repository.loadOverview(session);
  yield* repository.watchOverview(session);
});

/// Development-only generator. The service itself also checks [kDebugMode],
/// so exposing this provider cannot enable it in a production build.
final hospitalLoadTestSeederProvider = Provider<HospitalLoadTestSeeder>((ref) {
  return HospitalLoadTestSeeder(ref.watch(databaseProvider));
});

final bioqarahReceiptImporterProvider = Provider<BioqarahReceiptImporter>((
  ref,
) {
  return BioqarahReceiptImporter(ref.watch(databaseProvider));
});

final appointmentNotificationServiceProvider =
    Provider<AppointmentNotificationService>(
      (ref) => LocalAppointmentNotificationService(),
    );

final appointmentDetailProvider =
    FutureProvider.family<AppointmentDetail?, int>((ref, appointmentId) async {
      await ref.watch(seedDataProvider.future);
      return ref
          .watch(clinicRepositoryProvider)
          .getAppointmentDetail(appointmentId);
    });

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return LocalSubscriptionRepository(ref.watch(databaseProvider));
});

final activeClinicSubscriptionProvider =
    FutureProvider<LocalClinicSubscription?>((ref) async {
      final session = await ref.watch(userSessionProvider.future);
      final repository = ref.watch(subscriptionRepositoryProvider);
      return repository.ensureClinicSubscription(session.clinic);
    });

final subscriptionUsageProvider = FutureProvider<SubscriptionUsageSummary>((
  ref,
) async {
  final session = await ref.watch(userSessionProvider.future);
  return ref
      .watch(subscriptionRepositoryProvider)
      .usageForClinic(session.clinic.clinicId);
});

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => const TokenStore(FlutterSecureStorage()),
);

final biometricAuthServiceProvider = Provider<BiometricAuthService>(
  (ref) => BiometricAuthService(),
);

final biometricEnrollmentProvider = FutureProvider<BiometricEnrollment?>(
  (ref) => ref.watch(biometricAuthServiceProvider).enrollment(),
);

final localSessionStoreProvider = Provider<LocalSessionStore>(
  (ref) => const LocalSessionStore(FlutterSecureStorage()),
);

final offlineAuthorizationServiceProvider =
    Provider<OfflineAuthorizationService>(
      (ref) => OfflineAuthorizationService(const FlutterSecureStorage()),
    );

final offlineAuthorizationSnapshotProvider =
    StateProvider<OfflineAuthorizationSnapshot?>((ref) => null);

/// This state is intentionally separate from a clinic user's session. Platform
/// support is visible and auditable; it never silently impersonates staff.
final platformSupportSessionProvider = StateProvider<PlatformSupportSession?>(
  (ref) => null,
);

final offlineSyncRepositoryProvider = Provider<OfflineSyncRepository>(
  (ref) => OfflineSyncRepository(ref.watch(databaseProvider)),
);

final offlineSyncCoordinatorProvider = Provider<OfflineSyncCoordinator>(
  (ref) => OfflineSyncCoordinator(
    apiClient: ref.watch(apiClientProvider),
    queue: ref.watch(offlineSyncRepositoryProvider),
  ),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl: BackendConfiguration.apiBaseUrl,
    tokens: ref.watch(tokenStoreProvider),
  ),
);

final subscriptionPaymentGatewayProvider = Provider<SubscriptionPaymentGateway>(
  (ref) {
    if (!BackendConfiguration.isConfigured) {
      return const UnconfiguredSubscriptionPaymentGateway();
    }
    return PaystackSubscriptionGateway(ref.watch(apiClientProvider));
  },
);

final subscriptionBillingProvider = FutureProvider<SubscriptionBillingSnapshot>(
  (ref) async {
    final session = await ref.watch(userSessionProvider.future);
    final gateway = ref.watch(subscriptionPaymentGatewayProvider);
    final plans = await gateway.loadPlans();
    if (!BackendConfiguration.isConfigured) {
      return SubscriptionBillingSnapshot(
        plans: plans,
        subscription: null,
        payments: const [],
        isServerAuthoritative: false,
      );
    }
    final subscription = await gateway.loadSubscription(
      session.clinic.clinicId,
    );
    if (subscription != null &&
        const {
          'Active',
          'Trial',
          'Past Due',
          'Non-renewing',
          'Cancelled',
          'Expired',
        }.contains(subscription.status)) {
      await ref
          .read(subscriptionRepositoryProvider)
          .cacheServerEntitlement(
            clinicId: session.clinic.clinicId,
            plan: subscription.plan,
            status: subscription.status,
            validUntil: subscription.currentPeriodEnd,
            serverUpdatedAt: subscription.updatedAt,
          );
    }
    final payments = session.can(Permissions.subscriptionsManage)
        ? await gateway.loadPayments(session.clinic.clinicId)
        : const <SubscriptionPaymentRecord>[];
    return SubscriptionBillingSnapshot(
      plans: plans,
      subscription: subscription,
      payments: payments,
      isServerAuthoritative: true,
    );
  },
);

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>(
  (ref) => BackendAuthRemoteDataSource(ref.watch(apiClientProvider)),
);

final authenticationRepositoryProvider = Provider<AuthenticationRepository>(
  (ref) => AuthenticationRepository(
    remote: ref.watch(authRemoteDataSourceProvider),
    tokens: ref.watch(tokenStoreProvider),
  ),
);

final seedDataProvider = FutureProvider<void>((ref) {
  if (BackendConfiguration.isBackendMode) return Future.value();
  if (!kDebugMode) {
    return Future.error(
      StateError('Development seed data is unavailable in release builds.'),
    );
  }
  return ref.watch(clinicRepositoryProvider).seedSampleData();
});

final userSessionProvider = FutureProvider<UserSession>((ref) async {
  if (BackendConfiguration.isLocalMode) {
    final stored = await ref.watch(localSessionStoreProvider).read();
    if (stored == null) {
      throw StateError('No active local development session.');
    }
    await ref.watch(seedDataProvider.future);
    final local = await ref
        .watch(clinicRepositoryProvider)
        .restoreUserSession(userId: stored.userId, clinicId: stored.clinicId);
    if (local == null) {
      await ref.read(localSessionStoreProvider).clear();
      throw StateError('The local development session is no longer active.');
    }
    unawaited(_reconcileAppointmentReminders(ref, local));
    return local;
  }
  if (!BackendConfiguration.isConfigured) {
    throw StateError(
      'AVERA_API_BASE_URL must be configured for backend authentication.',
    );
  }
  final offline = ref.watch(offlineAuthorizationSnapshotProvider);
  if (offline != null) {
    return ref
        .watch(clinicRepositoryProvider)
        .cacheRemoteSession(offline.toRemoteUser());
  }
  final remote = await ref.watch(authenticationRepositoryProvider).restore();
  if (remote == null) throw StateError('No active backend session.');
  final snapshot = await ref
      .watch(offlineAuthorizationServiceProvider)
      .recordOnlineAuthorization(remote);
  unawaited(
    ref
        .read(offlineSyncCoordinatorProvider)
        .synchronize(snapshot)
        .then<void>((_) {}, onError: (_, __) {}),
  );
  final cached = await ref
      .watch(clinicRepositoryProvider)
      .cacheRemoteSession(remote);
  unawaited(_reconcileAppointmentReminders(ref, cached));
  return cached;
});

Future<void> _reconcileAppointmentReminders(
  Ref ref,
  UserSession session,
) async {
  try {
    final notifications = ref.read(appointmentNotificationServiceProvider);
    await notifications.initialize();
    final appointments = await ref
        .read(clinicRepositoryProvider)
        .upcomingAppointmentDetails();
    for (final detail in appointments) {
      for (final reminder in detail.reminders.where((item) => item.enabled)) {
        await notifications.scheduleReminder(
          detail: detail,
          reminder: reminder,
          timeZone: session.clinic.timeZone,
        );
      }
    }
  } catch (_) {
    // An unavailable platform notification channel must never block sign-in.
  }
}

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  await ref.watch(seedDataProvider.future);
  return ref.watch(clinicRepositoryProvider).dashboardStats();
});

final clinicWorkHoursProvider = FutureProvider<ClinicWorkHoursConfig?>((
  ref,
) async {
  await ref.watch(seedDataProvider.future);
  return ref.watch(clinicRepositoryProvider).clinicWorkHours();
});

final clinicOperatingStatusProvider = FutureProvider<ClinicOperatingStatus>((
  ref,
) async {
  final workHours = await ref.watch(clinicWorkHoursProvider.future);
  return ClinicOperatingStatusService.calculate(workHours);
});

/// A non-reserving preview for the active clinic. The repository assigns the
/// final number inside the registration transaction, so this value can change.
final hospitalNumberPreviewProvider = FutureProvider<HospitalNumberPreview>((
  ref,
) async {
  await ref.watch(seedDataProvider.future);
  final session = await ref.watch(userSessionProvider.future);
  return ref
      .watch(clinicRepositoryProvider)
      .previewHospitalNumber(clinicId: session.clinic.clinicId);
});

final animalSearchQueryProvider = StateProvider<String>((ref) => '');
final animalStatusFilterProvider = StateProvider<AnimalStatusFilter>(
  (ref) => AnimalStatusFilter.active,
);

final animalSearchProvider = StreamProvider((ref) async* {
  await ref.watch(seedDataProvider.future);
  final query = ref.watch(animalSearchQueryProvider);
  final filter = ref.watch(animalStatusFilterProvider);
  yield* ref
      .watch(clinicRepositoryProvider)
      .watchAnimalSearch(
        query,
        status: filter == AnimalStatusFilter.all ? null : filter.label,
      );
});

final archivedAnimalsProvider =
    StreamProvider.family<List<AnimalSearchResult>, String>((
      ref,
      status,
    ) async* {
      await ref.watch(seedDataProvider.future);
      yield* ref
          .watch(clinicRepositoryProvider)
          .watchAnimalSearch('', status: status);
    });

final animalProfileProvider = FutureProvider.family<AnimalProfile, int>((
  ref,
  animalId,
) async {
  await ref.watch(seedDataProvider.future);
  return ref.watch(clinicRepositoryProvider).getAnimalProfile(animalId);
});

final inventoryProvider = StreamProvider((ref) async* {
  await ref.watch(seedDataProvider.future);
  yield* ref.watch(clinicRepositoryProvider).watchInventory();
});

final vaccinationProtocolsProvider = StreamProvider((ref) async* {
  await ref.watch(seedDataProvider.future);
  yield* ref.watch(clinicRepositoryProvider).watchVaccinationProtocols();
});

final notificationsProvider = StreamProvider((ref) async* {
  await ref.watch(seedDataProvider.future);
  yield* ref.watch(clinicRepositoryProvider).watchNotifications();
});
