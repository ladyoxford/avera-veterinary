import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../database/app_database.dart';
import '../models/animal_search_result.dart';
import '../models/clinic_work_hours.dart';
import '../repositories/clinic_repository.dart';
import '../repositories/authentication_repository.dart';
import '../remote/api_client.dart';
import '../remote/auth_remote_data_source.dart';
import '../remote/backend_auth_remote_data_source.dart';
import '../services/offline_authorization_service.dart';
import '../repositories/offline_sync_repository.dart';
import '../repositories/subscription_repository.dart';
import '../services/offline_sync_coordinator.dart';
import '../services/local_session_store.dart';
import '../services/clinic_operating_status_service.dart';

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

final clinicRepositoryProvider = Provider<ClinicRepository>((ref) {
  return ClinicRepository(ref.watch(databaseProvider));
});

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return LocalSubscriptionRepository(ref.watch(databaseProvider));
});

final activeClinicSubscriptionProvider =
    FutureProvider<LocalClinicSubscription?>((ref) async {
      final session = await ref.watch(userSessionProvider.future);
      final repository = ref.watch(subscriptionRepositoryProvider);
      await repository.ensureCatalog();
      return repository.getClinicSubscription(session.clinic.clinicId);
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

final localSessionStoreProvider = Provider<LocalSessionStore>(
  (ref) => const LocalSessionStore(FlutterSecureStorage()),
);

final offlineAuthorizationServiceProvider =
    Provider<OfflineAuthorizationService>(
      (ref) => OfflineAuthorizationService(const FlutterSecureStorage()),
    );

final offlineAuthorizationSnapshotProvider =
    StateProvider<OfflineAuthorizationSnapshot?>((ref) => null);

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
  return ref.watch(clinicRepositoryProvider).cacheRemoteSession(remote);
});

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
