import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../remote/auth_remote_data_source.dart';

/// A locally encrypted authorization snapshot. It is created only after a
/// successful backend login and contains no password, token, or credential.
class OfflineAuthorizationSnapshot {
  const OfflineAuthorizationSnapshot({
    required this.userId,
    required this.clinicId,
    required this.membershipId,
    required this.accountType,
    required this.permissions,
    required this.fullName,
    required this.email,
    required this.clinicName,
    required this.clinicStatus,
    required this.membershipStatus,
    required this.subscriptionPlan,
    required this.deviceId,
    required this.lastOnlineAt,
    required this.expiresAt,
    this.roleId,
  });

  final String userId;
  final String? clinicId;
  final String membershipId;
  final String accountType;
  final Set<String> permissions;
  final String fullName;
  final String email;
  final String clinicName;
  final String clinicStatus;
  final String membershipStatus;
  final String subscriptionPlan;
  final String deviceId;
  final DateTime lastOnlineAt;
  final DateTime expiresAt;
  final String? roleId;

  bool get isValid =>
      expiresAt.isAfter(DateTime.now()) &&
      clinicStatus == 'Active' &&
      membershipStatus == 'Active';

  RemoteCurrentUser toRemoteUser() => RemoteCurrentUser(
        userId: userId,
        clinicId: clinicId,
        accountType: accountType,
        permissions: permissions,
        fullName: fullName,
        email: email,
        roleId: roleId,
        clinicName: clinicName,
        clinicStatus: clinicStatus,
        subscriptionPlan: subscriptionPlan,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'clinicId': clinicId,
        'membershipId': membershipId,
        'accountType': accountType,
        'permissions': permissions.toList(),
        'fullName': fullName,
        'email': email,
        'clinicName': clinicName,
        'clinicStatus': clinicStatus,
        'membershipStatus': membershipStatus,
        'subscriptionPlan': subscriptionPlan,
        'deviceId': deviceId,
        'lastOnlineAt': lastOnlineAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'roleId': roleId,
      };

  factory OfflineAuthorizationSnapshot.fromJson(Map<String, dynamic> json) =>
      OfflineAuthorizationSnapshot(
        userId: json['userId'] as String,
        clinicId: json['clinicId'] as String?,
        membershipId: json['membershipId'] as String,
        accountType: json['accountType'] as String,
        permissions: Set<String>.from(json['permissions'] as List<dynamic>),
        fullName: json['fullName'] as String,
        email: json['email'] as String,
        clinicName: json['clinicName'] as String,
        clinicStatus: json['clinicStatus'] as String,
        membershipStatus: json['membershipStatus'] as String,
        subscriptionPlan: json['subscriptionPlan'] as String,
        deviceId: json['deviceId'] as String,
        lastOnlineAt: DateTime.parse(json['lastOnlineAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        roleId: json['roleId'] as String?,
      );
}

class OfflineAuthorizationService {
  OfflineAuthorizationService(this._storage);

  final FlutterSecureStorage _storage;
  static const _snapshotKey = 'avera_offline_authorization_v1';
  static const _deviceIdKey = 'avera_device_id_v1';
  static const _pinSaltKey = 'avera_offline_pin_salt_v1';
  static const _pinHashKey = 'avera_offline_pin_hash_v1';
  static const _pinFailuresKey = 'avera_offline_pin_failures_v1';
  static const _pinLockedUntilKey = 'avera_offline_pin_locked_until_v1';
  static const Duration offlineValidity = Duration(days: 7);

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: created);
    return created;
  }

  Future<OfflineAuthorizationSnapshot> recordOnlineAuthorization(
    RemoteCurrentUser user,
  ) async {
    final now = DateTime.now().toUtc();
    final clinicId = user.clinicId;
    final snapshot = OfflineAuthorizationSnapshot(
      userId: user.userId,
      clinicId: clinicId,
      membershipId: '${user.userId}:${clinicId ?? 'platform'}',
      accountType: user.accountType,
      permissions: user.permissions,
      fullName: user.fullName,
      email: user.email,
      clinicName: user.clinicName ?? 'AVERA',
      clinicStatus: user.clinicStatus ?? 'Active',
      membershipStatus: 'Active',
      subscriptionPlan: user.subscriptionPlan ?? 'Starter',
      deviceId: await deviceId(),
      lastOnlineAt: now,
      expiresAt: now.add(offlineValidity),
      roleId: user.roleId,
    );
    await _storage.write(key: _snapshotKey, value: jsonEncode(snapshot.toJson()));
    return snapshot;
  }

  Future<OfflineAuthorizationSnapshot?> validSnapshot() async {
    final raw = await _storage.read(key: _snapshotKey);
    if (raw == null) return null;
    try {
      final snapshot = OfflineAuthorizationSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (!snapshot.isValid || snapshot.deviceId != await deviceId()) return null;
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  Future<bool> get hasPin async =>
      (await _storage.read(key: _pinHashKey)) != null &&
      (await _storage.read(key: _pinSaltKey)) != null;

  Future<void> setPin(String pin) async {
    _validatePin(pin);
    final salt = _randomBytes(16);
    final hash = _derivePin(pin, salt);
    await _storage.write(key: _pinSaltKey, value: base64UrlEncode(salt));
    await _storage.write(key: _pinHashKey, value: base64UrlEncode(hash));
    await _storage.delete(key: _pinFailuresKey);
    await _storage.delete(key: _pinLockedUntilKey);
  }

  Future<OfflineAuthorizationSnapshot?> unlockWithPin(String pin) async {
    _validatePin(pin);
    final snapshot = await validSnapshot();
    if (snapshot == null) return null;
    final lockedUntil = await _storage.read(key: _pinLockedUntilKey);
    if (lockedUntil != null && DateTime.parse(lockedUntil).isAfter(DateTime.now())) {
      throw StateError('Offline access is temporarily locked. Try again later.');
    }
    final saltText = await _storage.read(key: _pinSaltKey);
    final hashText = await _storage.read(key: _pinHashKey);
    if (saltText == null || hashText == null) return null;
    final verified = _constantTimeEquals(
      _derivePin(pin, base64Url.decode(saltText)),
      base64Url.decode(hashText),
    );
    if (verified) {
      await _storage.delete(key: _pinFailuresKey);
      await _storage.delete(key: _pinLockedUntilKey);
      return snapshot;
    }
    final failures = (int.tryParse(await _storage.read(key: _pinFailuresKey) ?? '') ?? 0) + 1;
    await _storage.write(key: _pinFailuresKey, value: '$failures');
    if (failures >= 5) {
      await _storage.write(
        key: _pinLockedUntilKey,
        value: DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      );
      await _storage.write(key: _pinFailuresKey, value: '0');
    }
    return null;
  }

  Future<void> clearOfflineAccess() async {
    await _storage.delete(key: _snapshotKey);
    await _storage.delete(key: _pinSaltKey);
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _pinFailuresKey);
    await _storage.delete(key: _pinLockedUntilKey);
  }

  void _validatePin(String pin) {
    if (!RegExp(r'^\\d{6}$').hasMatch(pin)) {
      throw ArgumentError('Choose a six-digit offline PIN.');
    }
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => Random.secure().nextInt(256));

  List<int> _derivePin(String pin, List<int> salt) {
    final password = utf8.encode(pin);
    final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = Hmac(sha256, password).convert(block).bytes;
    final output = List<int>.from(u);
    for (var iteration = 1; iteration < 120000; iteration++) {
      u = Hmac(sha256, password).convert(u).bytes;
      for (var index = 0; index < output.length; index++) {
        output[index] ^= u[index];
      }
    }
    return output;
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
