import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RegistrationPaymentSession {
  const RegistrationPaymentSession({
    required this.applicationId,
    required this.clinicId,
    required this.applicationReference,
    required this.plan,
    required this.accessToken,
    required this.paymentReference,
  });

  final String applicationId;
  final String clinicId;
  final String applicationReference;
  final String plan;
  final String accessToken;
  final String paymentReference;

  Map<String, dynamic> toJson() => {
    'applicationId': applicationId,
    'clinicId': clinicId,
    'applicationReference': applicationReference,
    'plan': plan,
    'accessToken': accessToken,
    'paymentReference': paymentReference,
  };

  static RegistrationPaymentSession? fromJson(Map<String, dynamic> json) {
    final applicationId = json['applicationId'];
    final clinicId = json['clinicId'];
    final applicationReference = json['applicationReference'];
    final plan = json['plan'];
    final accessToken = json['accessToken'];
    final paymentReference = json['paymentReference'];
    if (applicationId is! String ||
        clinicId is! String ||
        applicationReference is! String ||
        plan is! String ||
        accessToken is! String ||
        paymentReference is! String) {
      return null;
    }
    return RegistrationPaymentSession(
      applicationId: applicationId,
      clinicId: clinicId,
      applicationReference: applicationReference,
      plan: plan,
      accessToken: accessToken,
      paymentReference: paymentReference,
    );
  }
}

class RegistrationPaymentSessionStore {
  const RegistrationPaymentSessionStore(this._storage);

  static const _key = 'avera.registration-payment-session';

  final FlutterSecureStorage _storage;

  Future<void> save(RegistrationPaymentSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<RegistrationPaymentSession?> loadActive() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return RegistrationPaymentSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<RegistrationPaymentSession?> loadForReference(String reference) async {
    final session = await loadActive();
    return session?.paymentReference == reference ? session : null;
  }

  Future<void> clear() => _storage.delete(key: _key);
}
