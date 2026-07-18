/// Boundary for production authentication. UI widgets and clinical repositories
/// depend on this contract rather than issuing HTTP requests themselves.
abstract class AuthRemoteDataSource {
  Future<RemoteAuthSession> signIn({
    required String email,
    required String password,
    required String deviceId,
    String? deviceName,
    String? platform,
  });

  Future<RemoteAuthSession> refresh(String refreshToken);
  Future<RemoteCurrentUser> currentUser(String accessToken);
  Future<void> signOut(String accessToken);
  Future<void> signOutAll(String accessToken);
  Future<List<RemoteSession>> sessions(String accessToken);
  Future<void> revokeSession(String accessToken, String sessionId);
  Future<void> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  });
}

class RemoteAuthSession {
  const RemoteAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final RemoteCurrentUser user;
}

class RemoteCurrentUser {
  const RemoteCurrentUser({
    required this.userId,
    required this.clinicId,
    required this.accountType,
    required this.permissions,
    required this.fullName,
    required this.email,
    this.roleId,
    this.clinicName,
    this.clinicStatus,
    this.subscriptionPlan,
  });

  final String userId;
  final String? clinicId;
  final String accountType;
  final Set<String> permissions;
  final String fullName;
  final String email;
  final String? roleId;
  final String? clinicName;
  final String? clinicStatus;
  final String? subscriptionPlan;
}

class RemoteSession {
  const RemoteSession({
    required this.sessionId,
    required this.createdAt,
    required this.expiresAt,
    this.deviceName,
  });

  final String sessionId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? deviceName;
}
