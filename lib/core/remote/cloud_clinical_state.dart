import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_providers.dart';
import '../repositories/clinic_repository.dart';
import '../repositories/cloud_cache_repository.dart';
import '../security/access_control.dart';
import 'clinical_remote_data_source.dart';

class RemotePatientListState {
  const RemotePatientListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasNextPage = false,
    this.fromCache = false,
    this.error,
  });
  final List<RemotePatient> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasNextPage;
  final bool fromCache;
  final Object? error;

  RemotePatientListState copyWith({
    List<RemotePatient>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasNextPage,
    bool? fromCache,
    Object? error,
    bool clearError = false,
  }) => RemotePatientListState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasNextPage: hasNextPage ?? this.hasNextPage,
    fromCache: fromCache ?? this.fromCache,
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

  Future<RemotePatient> updateStatus({
    required String patientId,
    required String status,
    String? reason,
  }) async {
    final session = await _session();
    if (!session.can(Permissions.patientsEdit)) {
      throw StateError('You do not have permission to manage patient status.');
    }
    final patient = await _source.updatePatientStatus(
      patientId: patientId,
      status: status,
      reason: reason,
    );
    await _cache.recordEntity(
      entityType: 'patient',
      serverId: patient.id,
      clinicId: session.clinic.clinicId,
      revision: patient.revision,
      serverUpdatedAt: DateTime.now(),
    );
    if (mounted) await refresh();
    return patient;
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
      if (!mounted) return;
      _apply(page, reset: reset, fromCache: false);
    } catch (error) {
      UserSession? session;
      try {
        session = await _session();
      } catch (_) {
        if (!mounted) return;
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: error,
        );
        return;
      }
      final key = _cacheKey(session.clinic.clinicId, _nextPage);
      final cached = await _cache.get(key, clinicId: session.clinic.clinicId);
      if (!mounted) return;
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
        _apply(page, reset: reset, fromCache: true);
      } else {
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: error,
        );
      }
    }
  }

  void _apply(
    RemotePage<RemotePatient> page, {
    required bool reset,
    required bool fromCache,
  }) {
    final ids = <String>{};
    final items = <RemotePatient>[...(!reset ? state.items : const [])];
    for (final patient in items) {
      ids.add(patient.id);
    }
    for (final patient in page.items) {
      if (ids.add(patient.id)) items.add(patient);
    }
    _nextPage = page.page + 1;
    state = RemotePatientListState(
      items: items,
      hasNextPage: page.hasNextPage,
      fromCache: fromCache,
    );
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

class RemotePatientDirectoryState {
  const RemotePatientDirectoryState({
    this.items = const [],
    this.isLoading = false,
    this.fromCache = false,
    this.error,
  });

  final List<RemotePatient> items;
  final bool isLoading;
  final bool fromCache;
  final Object? error;
}

class RemotePatientDirectoryController
    extends StateNotifier<RemotePatientDirectoryState> {
  RemotePatientDirectoryController(this._source, this._cache, this._session)
    : super(const RemotePatientDirectoryState()) {
    unawaited(refresh());
  }

  final ClinicalRemoteDataSource _source;
  final CloudCacheRepository _cache;
  final Future<UserSession> Function() _session;

  Future<void> refresh() async {
    final previous = state.items;
    state = RemotePatientDirectoryState(
      items: previous,
      isLoading: previous.isEmpty,
      fromCache: state.fromCache,
    );
    UserSession? session;
    try {
      session = await _session();
      final cached = await _readCache(session);
      if (mounted && previous.isEmpty && cached.isNotEmpty) {
        state = RemotePatientDirectoryState(
          items: cached,
          isLoading: true,
          fromCache: true,
        );
      }

      final byId = <String, RemotePatient>{};
      var page = 1;
      var hasNextPage = true;
      while (hasNextPage) {
        final result = await _source.patients(
          page: page,
          pageSize: 100,
          status: 'Active',
        );
        for (final patient in result.items) {
          if (_isActive(patient.status)) byId[patient.id] = patient;
        }
        hasNextPage = result.hasNextPage;
        page += 1;
      }
      final patients = _sorted(byId.values);
      await _cache.put(
        key: _cacheKey(session.clinic.clinicId),
        clinicId: session.clinic.clinicId,
        payload: {'items': patients.map((item) => item.toJson()).toList()},
      );
      if (mounted) state = RemotePatientDirectoryState(items: patients);
    } catch (error) {
      session ??= await _safeSession();
      final cached = session == null
          ? const <RemotePatient>[]
          : await _readCache(session);
      if (!mounted) return;
      state = RemotePatientDirectoryState(
        items: cached.isNotEmpty ? cached : previous,
        fromCache: cached.isNotEmpty || previous.isNotEmpty,
        error: error,
      );
    }
  }

  Future<UserSession?> _safeSession() async {
    try {
      return await _session();
    } catch (_) {
      return null;
    }
  }

  Future<List<RemotePatient>> _readCache(UserSession session) async {
    final cached = await _cache.get(
      _cacheKey(session.clinic.clinicId),
      clinicId: session.clinic.clinicId,
    );
    if (cached == null) return const [];
    return _sorted(
      (cached['items'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                RemotePatient.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .where((patient) => _isActive(patient.status)),
    );
  }

  List<RemotePatient> _sorted(Iterable<RemotePatient> patients) {
    final result = patients.toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0
            ? byName
            : a.hospitalNumber.compareTo(b.hospitalNumber);
      });
    return result;
  }

  bool _isActive(String status) => status.trim().toLowerCase() == 'active';

  String _cacheKey(String clinicId) => 'patient-directory:$clinicId:active';
}

final remotePatientDirectoryProvider =
    StateNotifierProvider.autoDispose<
      RemotePatientDirectoryController,
      RemotePatientDirectoryState
    >(
      (ref) => RemotePatientDirectoryController(
        ref.watch(clinicalRemoteDataSourceProvider),
        ref.watch(cloudCacheRepositoryProvider),
        () => ref.read(userSessionProvider.future),
      ),
    );

class RemoteInventoryListState {
  const RemoteInventoryListState({
    this.items = const [],
    this.isLoading = false,
    this.fromCache = false,
    this.error,
  });

  final List<RemoteInventoryItem> items;
  final bool isLoading;
  final bool fromCache;
  final Object? error;

  RemoteInventoryListState copyWith({
    List<RemoteInventoryItem>? items,
    bool? isLoading,
    bool? fromCache,
    Object? error,
    bool clearError = false,
  }) => RemoteInventoryListState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    fromCache: fromCache ?? this.fromCache,
    error: clearError ? null : error ?? this.error,
  );
}

class RemoteInventoryListController
    extends StateNotifier<RemoteInventoryListState> {
  RemoteInventoryListController(this._source, this._cache, this._session)
    : super(const RemoteInventoryListState()) {
    unawaited(refresh());
  }

  final ClinicalRemoteDataSource _source;
  final CloudCacheRepository _cache;
  final Future<UserSession> Function() _session;
  String _search = '';

  Future<void> refresh({String? search}) async {
    if (search != null) _search = search;
    state = state.copyWith(isLoading: true, clearError: true);
    UserSession? session;
    try {
      session = await _session();
      final items = <RemoteInventoryItem>[];
      var page = 1;
      var hasNext = true;
      while (hasNext) {
        final result = await _source.inventoryProducts(
          page: page,
          pageSize: 100,
          search: _search,
        );
        items.addAll(result.items);
        hasNext = result.hasNextPage;
        page += 1;
      }
      final unique = <String, RemoteInventoryItem>{
        for (final item in items) item.id: item,
      }.values.toList()..sort((a, b) => a.name.compareTo(b.name));
      await _writeCache(session, unique);
      for (final item in unique) {
        await _cache.recordEntity(
          entityType: 'inventory_product',
          serverId: item.id,
          clinicId: session.clinic.clinicId,
          revision: item.revision,
          serverUpdatedAt: item.updatedAt,
        );
      }
      if (!mounted) return;
      state = RemoteInventoryListState(items: unique);
    } catch (error) {
      session ??= await _safeSession();
      final cached = session == null
          ? null
          : await _cache.get(
              _cacheKey(session.clinic.clinicId),
              clinicId: session.clinic.clinicId,
            );
      if (!mounted) return;
      if (cached != null) {
        state = RemoteInventoryListState(
          items: (cached['items'] as List<dynamic>? ?? const [])
              .map(
                (item) => RemoteInventoryItem.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
          fromCache: true,
          error: error,
        );
      } else {
        state = RemoteInventoryListState(error: error);
      }
    }
  }

  Future<RemoteInventoryItem> create(Map<String, dynamic> payload) async {
    final currentItems = [...state.items];
    final session = await _session();
    if (!session.can(Permissions.inventoryCreate)) {
      throw StateError('You do not have permission to create inventory items.');
    }
    final item = await _source.createInventoryItem(payload);
    await _upsertAndCache(session, item, currentItems);
    if (mounted) unawaited(refresh());
    return item;
  }

  Future<RemoteInventoryItem> update({
    required String itemId,
    required Map<String, dynamic> payload,
  }) async {
    final currentItems = [...state.items];
    final session = await _session();
    if (!session.can(Permissions.inventoryEdit)) {
      throw StateError('You do not have permission to edit inventory items.');
    }
    final item = await _source.updateInventoryItem(
      inventoryProductId: itemId,
      payload: payload,
    );
    await _upsertAndCache(session, item, currentItems);
    if (mounted) unawaited(refresh());
    return item;
  }

  Future<void> _upsertAndCache(
    UserSession session,
    RemoteInventoryItem item,
    List<RemoteInventoryItem> currentItems,
  ) async {
    final items = [...currentItems];
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index == -1) {
      items.add(item);
    } else {
      items[index] = item;
    }
    items.sort((a, b) => a.name.compareTo(b.name));
    if (mounted) state = RemoteInventoryListState(items: items);
    await _writeCache(session, items);
    await _cache.recordEntity(
      entityType: 'inventory_product',
      serverId: item.id,
      clinicId: session.clinic.clinicId,
      revision: item.revision,
      serverUpdatedAt: item.updatedAt,
    );
  }

  Future<void> _writeCache(
    UserSession session,
    List<RemoteInventoryItem> items,
  ) => _cache.put(
    key: _cacheKey(session.clinic.clinicId),
    clinicId: session.clinic.clinicId,
    payload: {'items': items.map((item) => item.toJson()).toList()},
  );

  Future<UserSession?> _safeSession() async {
    try {
      return await _session();
    } catch (_) {
      return null;
    }
  }

  String _cacheKey(String clinicId) => 'inventory:$clinicId:$_search';
}

final remoteInventoryListProvider =
    StateNotifierProvider.autoDispose<
      RemoteInventoryListController,
      RemoteInventoryListState
    >(
      (ref) => RemoteInventoryListController(
        ref.watch(clinicalRemoteDataSourceProvider),
        ref.watch(cloudCacheRepositoryProvider),
        () => ref.read(userSessionProvider.future),
      ),
    );

class RemoteConsultationService {
  const RemoteConsultationService(this._source, this._cache, this._session);

  final ClinicalRemoteDataSource _source;
  final CloudCacheRepository _cache;
  final Future<UserSession> Function() _session;

  Future<RemoteConsultationCreation> create(
    Map<String, dynamic> payload,
  ) async {
    final session = await _session();
    if (!session.can(Permissions.consultationsCreate)) {
      throw StateError('You do not have permission to create consultations.');
    }
    final consultation = await _source.createConsultation(payload);
    unawaited(
      _cache
          .recordEntity(
            entityType: 'consultation',
            serverId: consultation.id,
            clinicId: session.clinic.clinicId,
            serverUpdatedAt: DateTime.now(),
          )
          .catchError((Object _) {
            // The backend commit is authoritative. Cache bookkeeping must never
            // turn a confirmed consultation into a false save failure.
          }),
    );
    return consultation;
  }
}

final remoteConsultationServiceProvider = Provider<RemoteConsultationService>(
  (ref) => RemoteConsultationService(
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

class RemotePatientSectionRequest {
  const RemotePatientSectionRequest({
    required this.patientId,
    required this.section,
    this.operationType,
  });

  final String patientId;
  final String section;
  final String? operationType;

  @override
  bool operator ==(Object other) =>
      other is RemotePatientSectionRequest &&
      other.patientId == patientId &&
      other.section == section &&
      other.operationType == operationType;

  @override
  int get hashCode => Object.hash(patientId, section, operationType);
}

final remotePatientSectionProvider = FutureProvider.autoDispose
    .family<RemotePage<Map<String, dynamic>>, RemotePatientSectionRequest>((
      ref,
      request,
    ) async {
      final session = await ref.watch(userSessionProvider.future);
      final cache = ref.watch(cloudCacheRepositoryProvider);
      final key =
          'medical-file-section:${session.clinic.clinicId}:${request.patientId}:${request.section}:${request.operationType ?? ''}';
      try {
        final source = ref.watch(clinicalRemoteDataSourceProvider);
        final page = request.operationType == null
            ? await source.patientSection(request.patientId, request.section)
            : await source.patientClinicalOperations(
                request.patientId,
                operationType: request.operationType!,
              );
        await cache.put(
          key: key,
          clinicId: session.clinic.clinicId,
          payload: {
            'items': page.items,
            'page': page.page,
            'pageSize': page.pageSize,
            'total': page.total,
            'hasNextPage': page.hasNextPage,
          },
        );
        return page;
      } catch (_) {
        final cached = await cache.get(key, clinicId: session.clinic.clinicId);
        if (cached == null) rethrow;
        return RemotePage<Map<String, dynamic>>(
          items: (cached['items'] as List<dynamic>? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(),
          page: cached['page'] as int? ?? 1,
          pageSize: cached['pageSize'] as int? ?? 25,
          total: cached['total'] as int? ?? 0,
          hasNextPage: cached['hasNextPage'] == true,
        );
      }
    });

final remoteVaccinationScheduleProvider =
    FutureProvider.autoDispose<RemotePage<RemoteVaccinationRecord>>((
      ref,
    ) async {
      final session = await ref.watch(userSessionProvider.future);
      final cache = ref.watch(cloudCacheRepositoryProvider);
      final key = 'vaccination-schedule:${session.clinic.clinicId}';
      try {
        final page = await ref
            .watch(clinicalRemoteDataSourceProvider)
            .vaccinationSchedule();
        unawaited(
          cache
              .put(
                key: key,
                clinicId: session.clinic.clinicId,
                payload: {
                  'items': page.items.map((item) => item.toJson()).toList(),
                  'page': page.page,
                  'pageSize': page.pageSize,
                  'total': page.total,
                  'hasNextPage': page.hasNextPage,
                },
              )
              .catchError((Object _) {}),
        );
        return page;
      } catch (_) {
        final cached = await cache.get(key, clinicId: session.clinic.clinicId);
        if (cached == null) rethrow;
        return RemotePage<RemoteVaccinationRecord>(
          items: (cached['items'] as List<dynamic>? ?? const [])
              .map(
                (item) => RemoteVaccinationRecord.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
          page: cached['page'] as int? ?? 1,
          pageSize: cached['pageSize'] as int? ?? 100,
          total: cached['total'] as int? ?? 0,
          hasNextPage: cached['hasNextPage'] == true,
        );
      }
    });

final remoteAppointmentScheduleProvider =
    FutureProvider.autoDispose<RemotePage<Map<String, dynamic>>>((ref) async {
      final session = await ref.watch(userSessionProvider.future);
      final cache = ref.watch(cloudCacheRepositoryProvider);
      final key = 'appointment-schedule:${session.clinic.clinicId}';
      try {
        final page = await ref
            .watch(clinicalRemoteDataSourceProvider)
            .schedule();
        unawaited(
          cache
              .put(
                key: key,
                clinicId: session.clinic.clinicId,
                payload: {
                  'items': page.items,
                  'page': page.page,
                  'pageSize': page.pageSize,
                  'total': page.total,
                  'hasNextPage': page.hasNextPage,
                },
              )
              .catchError((Object _) {}),
        );
        return page;
      } catch (_) {
        final cached = await cache.get(key, clinicId: session.clinic.clinicId);
        if (cached == null) rethrow;
        return RemotePage<Map<String, dynamic>>(
          items: (cached['items'] as List<dynamic>? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(),
          page: cached['page'] as int? ?? 1,
          pageSize: cached['pageSize'] as int? ?? 25,
          total: cached['total'] as int? ?? 0,
          hasNextPage: cached['hasNextPage'] == true,
        );
      }
    });

final remoteAppointmentDetailProvider = FutureProvider.autoDispose
    .family<RemoteAppointmentDetail, String>((ref, appointmentId) async {
      final session = await ref.watch(userSessionProvider.future);
      final cache = ref.watch(cloudCacheRepositoryProvider);
      final key =
          'appointment-detail:${session.clinic.clinicId}:$appointmentId';
      try {
        final detail = await ref
            .watch(clinicalRemoteDataSourceProvider)
            .appointment(appointmentId);
        unawaited(
          cache
              .put(
                key: key,
                clinicId: session.clinic.clinicId,
                payload: detail.toJson(),
              )
              .catchError((Object _) {}),
        );
        return detail;
      } catch (_) {
        final cached = await cache.get(key, clinicId: session.clinic.clinicId);
        if (cached == null) rethrow;
        return RemoteAppointmentDetail.fromJson(cached);
      }
    });

final remoteDashboardOfflineProvider = StateProvider<bool>((ref) => false);

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
        ref.read(remoteDashboardOfflineProvider.notifier).state = false;
        await cache.put(
          key: key,
          clinicId: session.clinic.clinicId,
          payload: dashboard.toJson(),
        );
        return dashboard;
      } catch (_) {
        final cached = await cache.get(key, clinicId: session.clinic.clinicId);
        if (cached == null) rethrow;
        ref.read(remoteDashboardOfflineProvider.notifier).state = true;
        return RemoteDashboardSummary.fromJson(cached);
      }
    });
