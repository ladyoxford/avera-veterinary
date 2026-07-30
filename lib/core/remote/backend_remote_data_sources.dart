/// Production remote boundaries. Implementations belong in the infrastructure
/// layer; Riverpod repositories select these only when backend mode is enabled.
abstract class UserRemoteDataSource {
  Future<List<RemoteUserSummary>> listClinicUsers(String accessToken);
}

abstract class ClinicRemoteDataSource {
  Future<List<RemoteClinicSummary>> listPlatformClinics(String accessToken);
  Future<void> changeClinicStatus({
    required String accessToken,
    required String clinicId,
    required String status,
  });
}

abstract class PermissionRemoteDataSource {
  Future<List<String>> availablePermissions(String accessToken);
  Future<List<RemoteRoleSummary>> listClinicRoles(String accessToken);
}

abstract class SessionRemoteDataSource {
  Future<void> revokeSession({
    required String accessToken,
    required String sessionId,
  });
}

abstract class AuditRemoteDataSource {
  Future<List<RemoteAuditEntry>> listAuditEntries(String accessToken);
}

class RemoteUserSummary {
  const RemoteUserSummary({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.status,
    required this.roleId,
  });
  final String userId;
  final String fullName;
  final String email;
  final String status;
  final String? roleId;
}

class RemoteClinicSummary {
  const RemoteClinicSummary({
    required this.clinicId,
    required this.name,
    required this.status,
    required this.subscriptionPlan,
  });
  final String clinicId;
  final String name;
  final String status;
  final String subscriptionPlan;
}

class RemoteRoleSummary {
  const RemoteRoleSummary({
    required this.roleId,
    required this.name,
    this.description,
  });
  final String roleId;
  final String name;
  final String? description;
}

class RemoteAuditEntry {
  const RemoteAuditEntry({
    required this.auditId,
    required this.action,
    required this.timestamp,
    required this.success,
  });
  final String auditId;
  final String action;
  final DateTime timestamp;
  final bool success;
}
