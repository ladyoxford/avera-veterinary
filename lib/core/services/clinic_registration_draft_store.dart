import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../repositories/clinic_repository.dart';

class ClinicRegistrationDraftStore {
  const ClinicRegistrationDraftStore(this._storage);

  static const _key = 'avera.clinic-registration-draft';

  final FlutterSecureStorage _storage;

  Future<void> save(ClinicApplication application) => _storage.write(
    key: _key,
    value: jsonEncode({
      'clinicName': application.clinicName,
      'accountEmail': application.accountEmail,
      'phoneNumber': application.phoneNumber,
      'address': application.address,
      'city': application.city,
      'country': application.country,
      'administratorName': application.administratorName,
      'administratorPhone': application.administratorPhone,
      'professionalTitle': application.professionalTitle,
      'subscriptionPlan': application.subscriptionPlan,
      'timeZone': application.timeZone,
      'reference': application.reference,
      'applicationId': application.applicationId,
      'clinicId': application.clinicId,
      'paymentStatus': application.paymentStatus,
      'paymentAccessToken': application.paymentAccessToken,
      'draftAccessToken': application.draftAccessToken,
      'status': application.status,
    }),
  );

  Future<ClinicApplication?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final requiredValues = [
        value['clinicName'],
        value['accountEmail'],
        value['phoneNumber'],
        value['address'],
        value['city'],
        value['country'],
        value['administratorName'],
        value['administratorPhone'],
        value['professionalTitle'],
        value['subscriptionPlan'],
        value['timeZone'],
      ];
      if (requiredValues.any((item) => item is! String)) return null;
      return ClinicApplication(
        clinicName: value['clinicName'] as String,
        accountEmail: value['accountEmail'] as String,
        phoneNumber: value['phoneNumber'] as String,
        address: value['address'] as String,
        city: value['city'] as String,
        country: value['country'] as String,
        administratorName: value['administratorName'] as String,
        administratorPhone: value['administratorPhone'] as String,
        professionalTitle: value['professionalTitle'] as String,
        subscriptionPlan: value['subscriptionPlan'] as String,
        timeZone: value['timeZone'] as String,
        reference: value['reference'] as String?,
        applicationId: value['applicationId'] as String?,
        clinicId: value['clinicId'] as String?,
        paymentStatus: value['paymentStatus'] as String?,
        paymentAccessToken: value['paymentAccessToken'] as String?,
        draftAccessToken: value['draftAccessToken'] as String?,
        status: value['status'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _key);
}
