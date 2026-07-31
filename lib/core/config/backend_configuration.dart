import 'package:flutter/foundation.dart';

enum AveraDataMode { local, backend }

class BackendConfiguration {
  const BackendConfiguration._();

  static const productionApiBaseUrl = 'https://avera-api-8akc.onrender.com';

  static const _definedDataMode = String.fromEnvironment(
    'AVERA_DATA_MODE',
    defaultValue: '',
  );
  static const _definedApiBaseUrl = String.fromEnvironment(
    'AVERA_API_BASE_URL',
    defaultValue: '',
  );
  static const requestTimeoutSeconds = int.fromEnvironment(
    'AVERA_API_TIMEOUT_SECONDS',
    defaultValue: 15,
  );
  static const enableLocalDevelopmentAuth = bool.fromEnvironment(
    'ENABLE_LOCAL_DEVELOPMENT_AUTH',
    defaultValue: false,
  );

  static AveraDataMode get dataMode => resolveDataMode(
    isRelease: kReleaseMode,
    definedMode: _definedDataMode,
    definedApiBaseUrl: _definedApiBaseUrl,
  );

  static String get apiBaseUrl => resolveApiBaseUrl(
    isRelease: kReleaseMode,
    definedApiBaseUrl: _definedApiBaseUrl,
  );

  static bool get isLocalMode => dataMode == AveraDataMode.local;
  static bool get isBackendMode => dataMode == AveraDataMode.backend;
  static bool get isConfigured => isBackendMode && apiBaseUrl.isNotEmpty;
  static bool get isRemoteBackendConfigured => isConfigured;

  static Duration get requestTimeout {
    final seconds = requestTimeoutSeconds.clamp(10, 60).toInt();
    return Duration(seconds: seconds);
  }

  static AveraDataMode resolveDataMode({
    required bool isRelease,
    String definedMode = '',
    String definedApiBaseUrl = '',
  }) {
    final normalizedMode = definedMode.trim().toLowerCase();
    if (normalizedMode == 'local') return AveraDataMode.local;
    if (normalizedMode == 'backend') return AveraDataMode.backend;
    if (definedApiBaseUrl.trim().isNotEmpty) return AveraDataMode.backend;
    return isRelease ? AveraDataMode.backend : AveraDataMode.local;
  }

  static String resolveApiBaseUrl({
    required bool isRelease,
    String definedApiBaseUrl = '',
  }) {
    final configured = normalizeBaseUrl(definedApiBaseUrl);
    if (configured.isNotEmpty) return configured;
    return isRelease ? productionApiBaseUrl : '';
  }

  static String normalizeBaseUrl(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  static Uri resolveEndpoint(String baseUrl, String path) {
    final normalizedBase = normalizeBaseUrl(baseUrl);
    if (normalizedBase.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Base URL is empty.');
    }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  static void validate() => validateResolved(
    isRelease: kReleaseMode,
    mode: dataMode,
    apiBaseUrl: apiBaseUrl,
    localDevelopmentAuthEnabled: enableLocalDevelopmentAuth,
  );

  static void validateResolved({
    required bool isRelease,
    required AveraDataMode mode,
    required String apiBaseUrl,
    required bool localDevelopmentAuthEnabled,
  }) {
    if (mode == AveraDataMode.backend && apiBaseUrl.trim().isEmpty) {
      throw StateError(
        'AVERA_API_BASE_URL is required when AVERA_DATA_MODE=backend.',
      );
    }
    if (isRelease && mode == AveraDataMode.local) {
      throw StateError('Local data mode is unavailable in release builds.');
    }
    if (isRelease && localDevelopmentAuthEnabled) {
      throw StateError(
        'Local development authentication is unavailable in release builds.',
      );
    }
    final uri = Uri.tryParse(normalizeBaseUrl(apiBaseUrl));
    if (isRelease &&
        mode == AveraDataMode.backend &&
        (uri == null || uri.scheme != 'https' || uri.host.isEmpty)) {
      throw StateError('Release builds require an HTTPS AVERA_API_BASE_URL.');
    }
    if (isRelease &&
        mode == AveraDataMode.backend &&
        _isDevelopmentHost(uri!.host)) {
      throw StateError(
        'Release builds cannot use localhost, emulator, or private LAN APIs.',
      );
    }
  }

  static bool _isDevelopmentHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '10.0.2.2') {
      return true;
    }
    final ipv4 = normalized.split('.').map(int.tryParse).toList();
    if (ipv4.length != 4 || ipv4.any((part) => part == null)) return false;
    final first = ipv4[0]!;
    final second = ipv4[1]!;
    return first == 10 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }
}
