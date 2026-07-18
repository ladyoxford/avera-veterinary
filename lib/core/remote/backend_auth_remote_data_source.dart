import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'auth_remote_data_source.dart';
import 'api_client.dart';

class BackendAuthRemoteDataSource implements AuthRemoteDataSource {
  BackendAuthRemoteDataSource(this._client) {
    _client.refreshTokens = _refreshTokens;
  }

  final ApiClient _client;

  @override
  Future<RemoteAuthSession> signIn({required String email, required String password, required String deviceId, String? deviceName, String? platform}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedDeviceName = deviceName?.trim();
    final requestDeviceName = normalizedDeviceName == null || normalizedDeviceName.isEmpty
        ? (deviceId.trim().isEmpty ? 'Flutter device' : deviceId.trim())
        : normalizedDeviceName;
    final body = <String, dynamic>{
      'email': normalizedEmail,
      'password': password,
      'deviceName': requestDeviceName,
      if (platform != null && platform.trim().isNotEmpty) 'platform': platform.trim().toLowerCase(),
    };
    if (kDebugMode) {
      developer.log(
        'endpoint=/api/v1/auth/sign-in email=$normalizedEmail passwordLength=${password.length} deviceNameLength=${requestDeviceName.length} platform=${body['platform'] ?? 'omitted'}',
        name: 'AVERA.auth',
      );
    }
    try {
      final response = await _client.post('/api/v1/auth/sign-in', body: body);
      if (kDebugMode) developer.log('sign-in response=2xx fields=${response.keys.toList()}', name: 'AVERA.auth');
      final session = _session(response);
      if (kDebugMode) developer.log('sign-in response parsing=success accountType=${session.user.accountType}', name: 'AVERA.auth');
      return session;
    } on ApiException catch (error) {
      if (kDebugMode) developer.log('sign-in response=failed backendCode=${error.code}', name: 'AVERA.auth');
      rethrow;
    } catch (error) {
      if (kDebugMode) developer.log('sign-in response parsing=failed type=${error.runtimeType}', name: 'AVERA.auth');
      throw const ApiException('invalid_response', 'The AVERA server returned an unexpected authentication response.');
    }
  }

  @override
  Future<RemoteAuthSession> refresh(String refreshToken) async {
    final response = await _client.post('/api/v1/auth/refresh', body: {'refreshToken': refreshToken});
    return _session(response);
  }

  Future<({String accessToken, String refreshToken})> _refreshTokens(String refreshToken) async {
    final session = await refresh(refreshToken);
    return (accessToken: session.accessToken, refreshToken: session.refreshToken);
  }

  @override
  Future<RemoteCurrentUser> currentUser(String accessToken) async {
    final response = await _client.get('/api/v1/auth/me');
    return _user(response['user'] as Map<String, dynamic>);
  }

  @override
  Future<void> signOut(String accessToken) async {
    await _client.post('/api/v1/auth/sign-out', authenticated: true);
  }

  @override
  Future<void> signOutAll(String accessToken) async {
    await _client.post('/api/v1/auth/sign-out-all', authenticated: true);
  }

  @override
  Future<List<RemoteSession>> sessions(String accessToken) async {
    final response = await _client.get('/api/v1/auth/sessions');
    return (response['sessions'] as List<dynamic>).map((item) {
      final value = item as Map<String, dynamic>;
      return RemoteSession(
        sessionId: value['session_id'] as String,
        createdAt: DateTime.parse(value['created_at'] as String),
        expiresAt: DateTime.parse(value['expires_at'] as String),
        deviceName: value['device_name'] as String?,
      );
    }).toList();
  }

  @override
  Future<void> revokeSession(String accessToken, String sessionId) async {
    await _client.delete('/api/v1/auth/sessions/$sessionId', authenticated: true);
  }

  @override
  Future<void> changePassword({required String accessToken, required String currentPassword, required String newPassword}) async {
    await _client.post('/api/v1/auth/change-password', authenticated: true, body: {'currentPassword': currentPassword, 'newPassword': newPassword});
  }

  RemoteAuthSession _session(Map<String, dynamic> value) => RemoteAuthSession(
        accessToken: value['accessToken'] as String,
        refreshToken: value['refreshToken'] as String,
        expiresIn: value['expiresIn'] as int,
        user: _user(value['user'] as Map<String, dynamic>),
      );

  RemoteCurrentUser _user(Map<String, dynamic> value) => RemoteCurrentUser(
        userId: value['userId'] as String,
        clinicId: value['clinicId'] as String?,
        accountType: value['accountType'] as String,
        permissions: Set<String>.from(value['permissions'] as List<dynamic>),
        fullName: value['fullName'] as String? ?? 'AVERA User',
        email: value['email'] as String? ?? '',
        roleId: value['roleId'] as String?,
        clinicName: value['clinicName'] as String?,
        clinicStatus: value['clinicStatus'] as String?,
        subscriptionPlan: value['subscriptionPlan'] as String?,
      );
}
