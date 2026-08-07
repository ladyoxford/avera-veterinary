import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';

const defaultMedicalFileQuickAccessIds = <String>[
  'signalment',
  'owner',
  'medical_history',
  'consultations',
  'vaccinations',
  'laboratory',
  'surgery',
  'hospitalization',
];

class MedicalFileQuickAccessScope {
  const MedicalFileQuickAccessScope({
    required this.clinicId,
    required this.userId,
  });

  final String clinicId;
  final String userId;

  String get preferenceKey =>
      'avera_medical_file_quick_access_v1_${clinicId}_$userId';

  @override
  bool operator ==(Object other) =>
      other is MedicalFileQuickAccessScope &&
      other.clinicId == clinicId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(clinicId, userId);
}

final medicalFileQuickAccessProvider = StateNotifierProvider.autoDispose
    .family<
      MedicalFileQuickAccessController,
      AsyncValue<List<String>>,
      MedicalFileQuickAccessScope
    >((ref, scope) {
      return MedicalFileQuickAccessController(
        ref.read(sharedPreferencesProvider),
        scope,
      );
    });

class MedicalFileQuickAccessController
    extends StateNotifier<AsyncValue<List<String>>> {
  MedicalFileQuickAccessController(this._preferences, this._scope)
    : super(const AsyncValue.loading()) {
    _load();
  }

  final SharedPreferences _preferences;
  final MedicalFileQuickAccessScope _scope;

  Future<void> _load() async {
    try {
      final saved = _preferences.getStringList(_scope.preferenceKey);
      final selection = _sanitize(saved);
      if (saved != null && !_sameSelection(saved, selection)) {
        await _preferences.setStringList(_scope.preferenceKey, selection);
      }
      state = AsyncValue.data(selection);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<bool> save(List<String> recordIds) async {
    final selection = _sanitize(recordIds);
    if (selection.isEmpty) return false;

    final previous = state.valueOrNull ?? defaultMedicalFileQuickAccessIds;
    state = AsyncValue.data(selection);
    try {
      final saved = await _preferences.setStringList(
        _scope.preferenceKey,
        selection,
      );
      if (!saved) state = AsyncValue.data(previous);
      return saved;
    } catch (_) {
      state = AsyncValue.data(previous);
      return false;
    }
  }

  List<String> _sanitize(List<String>? values) {
    final unique = <String>[];
    final removedOverview = values?.contains('overview') == true;
    for (final value in values ?? defaultMedicalFileQuickAccessIds) {
      if (_supportedRecordIds.contains(value)) {
        if (!unique.contains(value) && unique.length < 8) unique.add(value);
      }
    }
    if (removedOverview) {
      for (final value in defaultMedicalFileQuickAccessIds) {
        if (unique.length == 8) break;
        if (!unique.contains(value)) unique.add(value);
      }
    }
    return unique.isEmpty ? List.of(defaultMedicalFileQuickAccessIds) : unique;
  }

  bool _sameSelection(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

const _supportedRecordIds = <String>{
  'signalment',
  'owner',
  'medical_history',
  'consultations',
  'vaccinations',
  'laboratory',
  'hospitalization',
  'surgery',
  'medications',
  'billing',
  'appointments',
  'documents',
  'images',
  'timeline',
};
