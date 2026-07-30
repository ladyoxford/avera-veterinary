import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

enum AveraDataMode { local, backend }

class AccountRestrictionDispatcher {
  AccountRestrictionDispatcher._();
  static final _controller = StreamController<void>.broadcast();
  static Stream<void> get events => _controller.stream;
  static void notify() => _controller.add(null);
}

class BackendConfiguration {
  const BackendConfiguration._();

  static const _dataMode = String.fromEnvironment(
    'AVERA_DATA_MODE',
    defaultValue: 'local',
  );
  static const apiBaseUrl = String.fromEnvironment(
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

  static AveraDataMode get dataMode => _dataMode.toLowerCase() == 'backend'
      ? AveraDataMode.backend
      : AveraDataMode.local;
  static bool get isLocalMode => dataMode == AveraDataMode.local;
  static bool get isBackendMode => dataMode == AveraDataMode.backend;
  static bool get isConfigured => isBackendMode && apiBaseUrl.trim().isNotEmpty;

  static void validate() {
    if (isBackendMode && apiBaseUrl.trim().isEmpty) {
      throw StateError(
        'AVERA_API_BASE_URL is required when AVERA_DATA_MODE=backend.',
      );
    }
    if (kReleaseMode && isLocalMode) {
      throw StateError('Local data mode is unavailable in release builds.');
    }
    if (kReleaseMode && enableLocalDevelopmentAuth) {
      throw StateError(
        'Local development authentication is unavailable in release builds.',
      );
    }
    final uri = Uri.tryParse(apiBaseUrl.trim());
    if (kReleaseMode &&
        isBackendMode &&
        (uri == null || uri.scheme != 'https' || uri.host.isEmpty)) {
      throw StateError('Release builds require an HTTPS AVERA_API_BASE_URL.');
    }
  }

  static Duration get requestTimeout {
    final seconds = requestTimeoutSeconds.clamp(10, 60).toInt();
    return Duration(seconds: seconds);
  }
}

class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.statusCode});
  final String code;
  final String message;
  final int? statusCode;
}

class TokenStore {
  const TokenStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'avera_access_token';
  static const _refreshTokenKey = 'avera_refresh_token';
  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// Authentication expiry must not erase the separately protected offline
  /// authorization snapshot. Explicit sign-out clears that snapshot through
  /// OfflineAuthorizationService after the user has chosen the policy.
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}

typedef RefreshTokens =
    Future<({String accessToken, String refreshToken})> Function(
      String refreshToken,
    );

class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _client;
  RefreshTokens? refreshTokens;

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    bool retry = true,
  }) => _request(
    'POST',
    path,
    body: body,
    authenticated: authenticated,
    retry: retry,
  );
  Future<Map<String, dynamic>> get(
    String path, {
    bool authenticated = true,
    bool retry = true,
  }) => _request('GET', path, authenticated: authenticated, retry: retry);
  Future<Map<String, dynamic>> delete(
    String path, {
    bool authenticated = true,
    bool retry = true,
  }) => _request('DELETE', path, authenticated: authenticated, retry: retry);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
    bool retry = true,
  }) async {
    if (baseUrl.trim().isEmpty) {
      throw const ApiException(
        'backend_not_configured',
        'The AVERA server address has not been configured.',
      );
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) {
      final token = await tokens.accessToken;
      if (token == null) {
        throw const ApiException(
          'session_expired',
          'Your session has expired. Please sign in again.',
        );
      }
      headers['Authorization'] = 'Bearer $token';
    }
    final uri = _requestUri(path);
    final stopwatch = Stopwatch()..start();
    _debugLog('request method=$method url=$uri authenticated=$authenticated');
    try {
      final request = method == 'GET'
          ? _client.get(uri, headers: headers)
          : method == 'DELETE'
          ? _client.delete(uri, headers: headers)
          : _client.post(
              uri,
              headers: headers,
              body: jsonEncode(body ?? const {}),
            );
      final response = await request.timeout(
        BackendConfiguration.requestTimeout,
      );
      _debugLog(
        'response method=$method url=$uri status=${response.statusCode} '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      final responseCode = decoded['error'] as String?;
      if (responseCode == 'ACCOUNT_SUSPENDED' ||
          responseCode == 'account_suspended') {
        await tokens.clear();
        AccountRestrictionDispatcher.notify();
        throw ApiException(
          'ACCOUNT_SUSPENDED',
          'Your AVERA account is currently suspended.',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 401 &&
          authenticated &&
          retry &&
          refreshTokens != null) {
        final refresh = await tokens.refreshToken;
        if (refresh != null) {
          try {
            final pair = await refreshTokens!(refresh);
            await tokens.save(
              accessToken: pair.accessToken,
              refreshToken: pair.refreshToken,
            );
            return _request(
              method,
              path,
              body: body,
              authenticated: authenticated,
              retry: false,
            );
          } on ApiException {
            await tokens.clear();
          }
        }
        throw const ApiException(
          'session_expired',
          'Your session has expired. Please sign in again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          decoded['error'] as String? ?? 'request_failed',
          _friendlyMessage(response.statusCode, decoded['message'] as String?),
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on TimeoutException {
      _debugLog(
        'failure method=$method url=$uri category=timeout elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      throw const ApiException(
        'request_timeout',
        'The AVERA server took too long to respond. Please try again.',
      );
    } on SocketException {
      _debugLog(
        'failure method=$method url=$uri category=socket elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      throw const ApiException(
        'network_unavailable',
        'Check your internet connection and try again.',
      );
    } on http.ClientException catch (error) {
      final category = _clientFailureCategory(error);
      _debugLog(
        'failure method=$method url=$uri category=$category elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      throw ApiException(category, _clientFailureMessage(category));
    } on FormatException {
      _debugLog(
        'failure method=$method url=$uri category=invalid_response elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      throw const ApiException(
        'invalid_response',
        'The AVERA server returned an unexpected response.',
      );
    }
  }

  Uri _requestUri(String path) {
    final normalizedBase = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  String _clientFailureCategory(http.ClientException error) {
    final message = error.message.toLowerCase();
    if (message.contains('connection refused')) return 'connection_refused';
    if (message.contains('failed host lookup') ||
        message.contains('network is unreachable')) {
      return 'network_unavailable';
    }
    return 'server_unavailable';
  }

  String _clientFailureMessage(String category) {
    switch (category) {
      case 'connection_refused':
        return 'The AVERA server refused the connection. Check that the server is running.';
      case 'network_unavailable':
        return 'Check your internet connection and try again.';
      default:
        return 'The AVERA server is unavailable. Please try again shortly.';
    }
  }

  String _friendlyMessage(int status, String? serverMessage) {
    if (status == 400) {
      return serverMessage ?? 'Check the information provided and try again.';
    }
    if (status == 401) {
      return 'Your email or password is incorrect.';
    }
    if (status == 403) {
      return serverMessage ??
          'You do not have permission to perform this action.';
    }
    if (status == 408 || status == 504) {
      return 'The AVERA server took too long to respond. Please try again.';
    }
    if (status >= 500) {
      return 'The AVERA server is unavailable. Please try again shortly.';
    }
    return serverMessage ?? 'Your request could not be completed.';
  }

  void _debugLog(String message) {
    if (!kDebugMode) return;
    developer.log(message, name: 'AVERA.network');
    debugPrint('[AVERA.network] $message');
  }
}
