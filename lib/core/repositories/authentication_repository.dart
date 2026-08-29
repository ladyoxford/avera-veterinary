import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../remote/api_client.dart';
import '../remote/auth_remote_data_source.dart';

class AuthenticationRepository {
  AuthenticationRepository({
    required AuthRemoteDataSource remote,
    required TokenStore tokens,
  }) : _remote = remote,
       _tokens = tokens;

  final AuthRemoteDataSource _remote;
  final TokenStore _tokens;

  Future<RemoteCurrentUser> signIn({
    required String email,
    required String password,
    required String deviceId,
    String? deviceName,
    String? platform,
  }) async {
    final session = await _remote.signIn(
      email: email,
      password: password,
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
    );
    try {
      await _persist(session);
      if (kDebugMode) {
        developer.log('secure token persistence=success', name: 'AVERA.auth');
      }
    } catch (error) {
      if (kDebugMode) {
        developer.log(
          'secure token persistence=failed type=${error.runtimeType}',
          name: 'AVERA.auth',
        );
      }
      throw const ApiException(
        'secure_storage_failed',
        'AVERA could not securely store this session on the device.',
      );
    }
    return session.user;
  }

  Future<RemoteClinicAdministratorActivation>
  inspectClinicAdministratorActivation(String token) =>
      _remote.inspectClinicAdministratorActivation(token);

  Future<RemoteClinicAdministratorActivationResult>
  activateClinicAdministrator({
    required String token,
    required String password,
    required String confirmPassword,
  }) => _remote.activateClinicAdministrator(
    token: token,
    password: password,
    confirmPassword: confirmPassword,
  );

  Future<RemoteStaffActivation> inspectStaffActivation(String token) =>
      _remote.inspectStaffActivation(token);

  Future<RemoteClinicAdministratorActivationResult> activateStaff({
    required String token,
    required String password,
    required String confirmPassword,
  }) => _remote.activateStaff(
    token: token,
    password: password,
    confirmPassword: confirmPassword,
  );

  Future<RemoteCurrentUser> verifyMfa({
    required String challengeToken,
    String? code,
    String? recoveryCode,
  }) async {
    final session = await _remote.verifyMfa(
      challengeToken: challengeToken,
      code: code,
      recoveryCode: recoveryCode,
    );
    await _persist(session);
    return session.user;
  }

  Future<RemoteMfaStatus> mfaStatus() => _remote.mfaStatus();
  Future<RemoteMfaSetup> beginMfaSetup(String password) =>
      _remote.beginMfaSetup(password);
  Future<List<String>> confirmMfaSetup({
    required String setupId,
    required String code,
  }) => _remote.confirmMfaSetup(setupId: setupId, code: code);
  Future<void> disableMfa({
    required String password,
    required String codeOrRecovery,
  }) => _remote.disableMfa(password: password, codeOrRecovery: codeOrRecovery);
  Future<List<String>> regenerateMfaRecoveryCodes({
    required String password,
    required String codeOrRecovery,
  }) => _remote.regenerateMfaRecoveryCodes(
    password: password,
    codeOrRecovery: codeOrRecovery,
  );

  Future<RemoteCurrentUser?> restore() async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken == null) return null;
    try {
      final session = await _remote.refresh(refreshToken);
      await _tokens.save(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      if (kDebugMode) {
        developer.log(
          'session restoration=success accountType=${session.user.accountType}',
          name: 'AVERA.auth',
        );
      }
      return session.user;
    } on ApiException catch (error) {
      final credentialsAreInvalid =
          error.statusCode == 401 ||
          error.code == 'session_expired' ||
          error.code == 'invalid_refresh_token' ||
          error.code == 'invalid_credentials';
      if (!credentialsAreInvalid) rethrow;
      await _tokens.clear();
      if (kDebugMode) {
        developer.log(
          'session restoration=failed credentialsCleared=true',
          name: 'AVERA.auth',
        );
      }
      return null;
    }
  }

  Future<void> signOut() async {
    final accessToken = await _tokens.accessToken;
    if (accessToken != null) {
      try {
        await _remote.signOut(accessToken);
      } on ApiException {
        // Local credentials must still be cleared when the server is offline.
      }
    }
    await _tokens.clear();
  }

  Future<void> signOutAll() async {
    final accessToken = await _tokens.accessToken;
    if (accessToken != null) await _remote.signOutAll(accessToken);
    await _tokens.clear();
  }

  Future<void> _persist(RemoteAuthSession session) => _tokens.save(
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
  );
}
