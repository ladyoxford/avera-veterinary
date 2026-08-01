import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_providers.dart';
import '../repositories/clinic_repository.dart';
import '../repositories/cloud_cache_repository.dart';
import 'clinical_remote_data_source.dart';

class RemotePatientListState {
  const RemotePatientListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasNextPage = false,
    this.error,
  });
  final List<RemotePatient> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasNextPage;
  final Object? error;

  RemotePatientListState copyWith({
    List<RemotePatient>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasNextPage,
    Object? error,
    bool clearError = false,
  }) => RemotePatientListState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasNextPage: hasNextPage ?? this.hasNextPage,
    error: clearError ? null : error ?? this.error,
  );
}

class RemotePatientListController
    extends StateNotifier<RemotePatientListState> {
  RemotePatientListController(this._source, this._cache, this._session)
    : super(const RemotePatientListState()) {
    unawaited(refresh());
  }

  final ClinicalRemoteDataSource _source;
  final CloudCacheRepository _cache;
  final Future<UserSession> Function() _session;
  String _search = '';
  String? _status = 'Active';
  int _nextPage = 1;

  Future<void> refresh({String? search, String? status}) async {
    if (search != null) _search = search;
    if (status != null) _status = status == 'All Animals' ? null : status;
    _nextPage = 1;
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadPage(reset: true);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasNextPage) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _loadPage(reset: false);
  }

  Future<void> _loadPage({required bool reset}) async {
    try {
      final session = await _session();
      final key = _cacheKey(session.clinic.clinicId, _nextPage);
      final page = await _source.patients(
        page: _nextPage,
        search: _search,
        status: _status,
      );
      final payload = <String, dynamic>{
        'items': page.items.map((item) => item.toJson()).toList(),
        'page': page.page,
        'pageSize': page.pageSize,
        'total': page.total,
        'hasNextPage': page.hasNextPage,
      };
      await _cache.put(
        key: key,
        clinicId: session.clinic.clinicId,
        payload: payload,
      );
      for (final patient in page.items) {
        await _cache.recordEntity(
          entityType: 'patient',
          serverId: patient.id,
          clinicId: session.clinic.clinicId,
          revision: patient.revision,
        );
      }
      _apply(page, reset: reset);
    } catch (error) {
      UserSession? session;
      try {
        session = await _session();
      } catch (_) {
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: error,
        );
        return;
      }
      final key = _cacheKey(session.clinic.clinicId, _nextPage);
      final cached = await _cache.get(key, clinicId: session.clinic.clinicId);
      if (cached != null) {
        final page = RemotePage<RemotePatient>(
          items: (cached['items'] as List<dynamic>)
              .map(
                (item) => RemotePatient.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
          page: cached['page'] as int,
          pageSize: cached['pageSize'] as int,
          total: cached['total'] as int,
          hasNextPage: cached['hasNextPage'] == true,
        );
        _apply(page, reset: reset);
      } else {
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: error,
        );
      }
    }
  }

  void _apply(RemotePage<RemotePatient> page, {required bool reset}) {
    final ids = <String>{};
    final items = <RemotePatient>[...(!reset ? state.items : const [])];
    for (final patient in items) {
      ids.add(patient.id);
    }
    for (final patient in page.items) {
      if (ids.add(patient.id)) items.add(patient);
    }
    _nextPage = page.page + 1;
    state = RemotePatientListState(items: items, hasNextPage: page.hasNextPage);
  }

  String _cacheKey(String clinicId, int page) =>
      'patients:$clinicId:$_search:${_status ?? 'all'}:$page';
}

final clinicalRemoteDataSourceProvider = Provider<ClinicalRemoteDataSource>(
  (ref) => ClinicalRemoteDataSource(ref.watch(apiClientProvider)),
);
final cloudCacheRepositoryProvider = Provider<CloudCacheRepository>(
  (ref) => CloudCacheRepository(ref.watch(databaseProvider)),
);

final remotePatientListProvider =
    StateNotifierProvider.autoDispose<
      RemotePatientListController,
      RemotePatientListState
    >(
      (ref) => RemotePatientListController(
        ref.watch(clinicalRemoteDataSourceProvider),
        ref.watch(cloudCacheRepositoryProvider),
        () => ref.read(userSessionProvider.future),
      ),
    );

final remoteHospitalNumberPreviewProvider =
    FutureProvider.autoDispose<RemoteHospitalNumberPreview>((ref) async {
      await ref.watch(userSessionProvider.future);
      return ref.watch(clinicalRemoteDataSourceProvider).patientNumberPreview();
    });

final remotePatientMedicalFileProvider = FutureProvider.autoDispose
    .family<RemotePatientMedicalFile, String>((ref, patientId) async {
      final session = await ref.watch(userSessionProvider.future);
      final cache = ref.watch(cloudCacheRepositoryProvider);
      final key = 'medical-file:${session.clinic.clinicId}:$patientId';
      try {
        final file = await ref
            .watch(clinicalRemoteDataSourceProvider)
            .medicalFile(patientId);
        await cache.put(
          key: key,
          clinicId: session.clinic.clinicId,
          payload: {
            'patient': file.patient.toJson(),
            'summaries': file.summaries,
            'timeline': file.timeline,
          },
        );
        return file;
      } catch (_) {
        final cached = await cache.get(key, clinicId: session.clinic.clinicId);
        if (cached == null) rethrow;
        return RemotePatientMedicalFile(
          patient: RemotePatient.fromJson(
            Map<String, dynamic>.from(cached['patient'] as Map),
          ),
          summaries: Map<String, dynamic>.from(cached['summaries'] as Map).map(
            (key, value) =>
                MapEntry(key, Map<String, dynamic>.from(value as Map)),
          ),
          timeline: (cached['timeline'] as List<dynamic>)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(),
        );
      }
    });

final remoteDashboardProvider =
    FutureProvider.autoDispose<RemoteDashboardSummary>((ref) async {
      final session = await ref.watch(userSessionProvider.future);
      final cache = ref.watch(cloudCacheRepositoryProvider);
      const suffix = 'dashboard-summary';
      final key = '$suffix:${session.clinic.clinicId}';
      try {
        final dashboard = await ref
            .watch(clinicalRemoteDataSourceProvider)
            .dashboard();
        await cache.put(
          key: key,
          clinicId: session.clinic.clinicId,
          payload: dashboard.toJson(),
        );
        return dashboard;
      } catch (_) {
        final cached = await cache.get(key, clinicId: session.clinic.clinicId);
        if (cached == null) rethrow;
        return RemoteDashboardSummary.fromJson(cached);
      }
    });
