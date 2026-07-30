import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricEnrollment {
  const BiometricEnrollment({
    required this.userId,
    required this.clinicId,
    required this.email,
  });

  final String userId;
  final String? clinicId;
  final String email;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'clinicId': clinicId,
    'email': email,
  };

  factory BiometricEnrollment.fromJson(Map<String, dynamic> value) =>
      BiometricEnrollment(
        userId: value['userId'] as String,
        clinicId: value['clinicId'] as String?,
        email: value['email'] as String? ?? '',
      );
}

class BiometricAuthService {
  BiometricAuthService({
    LocalAuthentication? localAuthentication,
    FlutterSecureStorage? storage,
  }) : _localAuthentication = localAuthentication ?? LocalAuthentication(),
       _storage = storage ?? const FlutterSecureStorage();

  static const _enrollmentKey = 'avera_biometric_enrollment';
  final LocalAuthentication _localAuthentication;
  final FlutterSecureStorage _storage;

  Future<bool> get isSupported async {
    try {
      return await _localAuthentication.isDeviceSupported() &&
          await _localAuthentication.canCheckBiometrics &&
          (await _localAuthentication.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<BiometricEnrollment?> enrollment() async {
    final value = await _storage.read(key: _enrollmentKey);
    if (value == null) return null;
    try {
      return BiometricEnrollment.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<bool> authenticate({
    String reason = 'Use biometrics to sign in to AVERA',
  }) async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> enable(BiometricEnrollment enrollment) async {
    await _storage.write(
      key: _enrollmentKey,
      value: jsonEncode(enrollment.toJson()),
    );
  }

  Future<void> clear() => _storage.delete(key: _enrollmentKey);
}
