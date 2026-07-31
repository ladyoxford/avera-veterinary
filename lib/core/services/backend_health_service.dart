import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/backend_configuration.dart';

enum CloudConnectivityStatus {
  checking,
  online,
  waking,
  offline,
  failedTemporarily,
}

class CloudConnectivityResult {
  const CloudConnectivityResult({
    required this.status,
    required this.checkedAt,
    this.endpoint,
    this.serverStatus,
  });

  final CloudConnectivityStatus status;
  final DateTime checkedAt;
  final Uri? endpoint;
  final String? serverStatus;

  bool get isOnline => status == CloudConnectivityStatus.online;
}

class BackendHealthService {
  BackendHealthService({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : baseUrl = BackendConfiguration.normalizeBaseUrl(baseUrl),
       _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// `/health` is the public contract requested by the mobile app. The
  /// versioned Render deployment currently exposes live and ready probes, so
  /// those are accepted as compatible fallbacks until `/health` is deployed.
  static const probePaths = ['/health', '/health/live', '/health/ready'];

  Future<CloudConnectivityResult> check() async {
    if (baseUrl.isEmpty) {
      return CloudConnectivityResult(
        status: CloudConnectivityStatus.offline,
        checkedAt: DateTime.now(),
      );
    }
    try {
      return await _checkCompatibleProbes().timeout(timeout);
    } on TimeoutException {
      return CloudConnectivityResult(
        status: CloudConnectivityStatus.waking,
        checkedAt: DateTime.now(),
      );
    } on SocketException {
      return CloudConnectivityResult(
        status: CloudConnectivityStatus.offline,
        checkedAt: DateTime.now(),
      );
    } on http.ClientException {
      return CloudConnectivityResult(
        status: CloudConnectivityStatus.offline,
        checkedAt: DateTime.now(),
      );
    } on FormatException {
      return CloudConnectivityResult(
        status: CloudConnectivityStatus.failedTemporarily,
        checkedAt: DateTime.now(),
      );
    }
  }

  Future<CloudConnectivityResult> _checkCompatibleProbes() async {
    for (final path in probePaths) {
      final endpoint = BackendConfiguration.resolveEndpoint(baseUrl, path);
      final response = await _client.get(
        endpoint,
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode == 404) continue;
      if (response.statusCode == 503) {
        return CloudConnectivityResult(
          status: CloudConnectivityStatus.waking,
          checkedAt: DateTime.now(),
          endpoint: endpoint,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudConnectivityResult(
          status: CloudConnectivityStatus.failedTemporarily,
          checkedAt: DateTime.now(),
          endpoint: endpoint,
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final serverStatus = '${body['status'] ?? ''}'.toLowerCase();
      if (serverStatus == 'live' || serverStatus == 'ready') {
        return CloudConnectivityResult(
          status: CloudConnectivityStatus.online,
          checkedAt: DateTime.now(),
          endpoint: endpoint,
          serverStatus: serverStatus,
        );
      }
      if (serverStatus == 'starting' ||
          serverStatus == 'waking' ||
          serverStatus == 'not_ready') {
        return CloudConnectivityResult(
          status: CloudConnectivityStatus.waking,
          checkedAt: DateTime.now(),
          endpoint: endpoint,
          serverStatus: serverStatus,
        );
      }
      return CloudConnectivityResult(
        status: CloudConnectivityStatus.failedTemporarily,
        checkedAt: DateTime.now(),
        endpoint: endpoint,
        serverStatus: serverStatus,
      );
    }
    return CloudConnectivityResult(
      status: CloudConnectivityStatus.failedTemporarily,
      checkedAt: DateTime.now(),
    );
  }
}
