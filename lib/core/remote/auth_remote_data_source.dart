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
  Future<RemoteClinicAdministratorActivation>
  inspectClinicAdministratorActivation(String token);
  Future<RemoteClinicAdministratorActivationResult>
  activateClinicAdministrator({
    required String token,
    required String password,
    required String confirmPassword,
  });
  Future<RemoteAuthSession> verifyMfa({
    required String challengeToken,
    String? code,
    String? recoveryCode,
  });
  Future<RemoteMfaStatus> mfaStatus();
  Future<RemoteMfaSetup> beginMfaSetup(String password);
  Future<List<String>> confirmMfaSetup({
    required String setupId,
    required String code,
  });
  Future<void> disableMfa({
    required String password,
    required String codeOrRecovery,
  });
  Future<List<String>> regenerateMfaRecoveryCodes({
    required String password,
    required String codeOrRecovery,
  });
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

class RemoteClinicAdministratorActivation {
  const RemoteClinicAdministratorActivation({
    required this.clinicName,
    required this.administratorName,
    required this.email,
    required this.expiresAt,
  });

  final String clinicName;
  final String administratorName;
  final String email;
  final DateTime expiresAt;
}

class RemoteClinicAdministratorActivationResult {
  const RemoteClinicAdministratorActivationResult({
    required this.email,
    required this.mfaEnrollmentRecommended,
  });

  final String email;
  final bool mfaEnrollmentRecommended;
}

class MfaRequiredException implements Exception {
  const MfaRequiredException({
    required this.challengeToken,
    required this.expiresIn,
  });
  final String challengeToken;
  final int expiresIn;
}

class RemoteMfaStatus {
  const RemoteMfaStatus({required this.enabled, this.verifiedAt});
  final bool enabled;
  final DateTime? verifiedAt;
}

class RemoteMfaSetup {
  const RemoteMfaSetup({
    required this.setupId,
    required this.manualKey,
    required this.otpauthUri,
  });
  final String setupId;
  final String manualKey;
  final String otpauthUri;
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
