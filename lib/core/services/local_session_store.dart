import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalSessionReference {
  const LocalSessionReference({required this.userId, required this.clinicId});

  final String userId;
  final String clinicId;
}

/// Local development mode persists identity selection only. Password hashes and
/// plaintext passwords remain exclusively in the local development database.
class LocalSessionStore {
  const LocalSessionStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _userIdKey = 'avera_local_session_user_id';
  static const _clinicIdKey = 'avera_local_session_clinic_id';

  Future<void> save(LocalSessionReference session) async {
    await _storage.write(key: _userIdKey, value: session.userId);
    await _storage.write(key: _clinicIdKey, value: session.clinicId);
  }

  Future<LocalSessionReference?> read() async {
    final userId = await _storage.read(key: _userIdKey);
    final clinicId = await _storage.read(key: _clinicIdKey);
    if (userId == null || clinicId == null) {
      await clear();
      return null;
    }
    return LocalSessionReference(userId: userId, clinicId: clinicId);
  }

  Future<void> clear() async {
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _clinicIdKey);
  }
}
