import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'avera_theme_mode';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be provided at startup.');
});

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) {
      return ThemeController(ref.watch(sharedPreferencesProvider));
    });

class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(_readThemeMode(_prefs));

  final SharedPreferences _prefs;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_themeModeKey, mode.name);
  }

  static ThemeMode _readThemeMode(SharedPreferences prefs) {
    final saved = prefs.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.system,
    );
  }
}
