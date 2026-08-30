import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/auth_remote_data_source.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/services/offline_authorization_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const roleId = '9c169399-c6d6-437c-8c55-74b0521d7600';

  test(
    'remote session stores a role name and repairs cached UUID labels',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      final remote = _administrator(roleId: roleId);

      final session = await repository.cacheRemoteSession(remote);
      expect(session.user.role, 'Clinic Administrator');
      expect(session.user.roleId, roleId);

      await database
          .into(database.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: 'cached-staff',
              clinicId: 'clinic-1',
              fullName: 'Cached Staff',
              username: 'cached@example.test',
              email: 'cached@example.test',
              passwordHash: 'backend-managed',
              role: roleId,
              roleId: const Value(roleId),
              createdAt: DateTime.now(),
            ),
          );

      await repository.cacheRemoteSession(remote);
      final repaired = await (database.select(
        database.appUsers,
      )..where((row) => row.userId.equals('cached-staff'))).getSingle();
      expect(repaired.role, 'Clinic Administrator');
    },
  );

  test(
    'legacy remote session never falls back to displaying a role UUID',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      final session = await repository.cacheRemoteSession(
        _administrator(roleId: roleId, includeRoleMetadata: false),
      );
      expect(session.user.role, 'Clinic Administrator');
      expect(session.user.role, isNot(roleId));
    },
  );

  test('offline authorization preserves role id, code, and display name', () {
    final now = DateTime.now().toUtc();
    final snapshot = OfflineAuthorizationSnapshot(
      userId: 'admin-1',
      clinicId: 'clinic-1',
      membershipId: 'admin-1:clinic-1',
      accountType: AccountTypes.clinicAdministrator,
      permissions: const {Permissions.staffRolesManage},
      fullName: 'Clinic Administrator',
      email: 'admin@example.test',
      clinicName: 'AVERA Clinic',
      clinicStatus: 'Active',
      membershipStatus: 'Active',
      subscriptionPlan: 'Professional',
      deviceId: 'device-1',
      lastOnlineAt: now,
      expiresAt: now.add(const Duration(days: 1)),
      roleId: roleId,
      roleCode: 'clinic_administrator',
      roleName: 'Clinic Administrator',
    );
    final restored = OfflineAuthorizationSnapshot.fromJson(snapshot.toJson());
    expect(restored.roleId, roleId);
    expect(restored.roleCode, 'clinic_administrator');
    expect(restored.roleName, 'Clinic Administrator');
    expect(restored.toRemoteUser().roleName, 'Clinic Administrator');
  });

  test(
    'production role change uses role ID then refreshes the Drift display cache',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final api = _RoleApiClient();
      final repository = ClinicRepository(database, apiClient: api);
      final session = await repository.cacheRemoteSession(
        _administrator(roleId: roleId),
      );

      await repository.refreshClinicUsers(session);
      final roles = await repository.availableClinicRoles(session);
      final veterinarian = roles.singleWhere(
        (role) => role.name == 'Veterinarian',
      );
      await repository.changeClinicUserRole(
        actingSession: session,
        targetUserId: 'staff-1',
        newRole: veterinarian.name,
        newRoleId: veterinarian.id,
      );

      expect(api.patchPath, '/api/v1/users/staff-1/role');
      expect(api.patchBody, {'roleId': 'role-vet'});
      final cached = await (database.select(
        database.appUsers,
      )..where((row) => row.userId.equals('staff-1'))).getSingle();
      expect(cached.role, 'Veterinarian');
      expect(cached.roleId, 'role-vet');
    },
  );

  test(
    'production staff invitation submits the canonical clinic role ID',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final api = _RoleApiClient();
      final repository = ClinicRepository(database, apiClient: api);
      final session = await repository.cacheRemoteSession(
        _administrator(roleId: roleId),
      );
      final roles = await repository.availableClinicRoles(session);
      final veterinarian = roles.singleWhere(
        (role) => role.code == 'veterinarian',
      );

      final result = await repository.inviteClinicUser(
        actingSession: session,
        fullName: 'Jane Vet',
        email: 'jane@example.test',
        role: veterinarian,
      );

      expect(result.emailSubmitted, isTrue);
      expect(result.emailState, 'Submitted');
      expect(result.provider, 'resend');
      expect(result.providerMessageId, 'resend-message-1');
      expect(result.staffNumber, '004');
      expect(api.postPath, '/api/v1/users/invitations');
      expect(api.postBody?['roleId'], 'role-vet');
      expect(api.postBody, isNot(contains('roleName')));
    },
  );

  test('direct role mutation is rejected without staff.roles.manage', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final api = _RoleApiClient();
    final repository = ClinicRepository(database, apiClient: api);
    final authorized = await repository.cacheRemoteSession(
      _administrator(roleId: roleId),
    );
    final restricted = UserSession(
      user: authorized.user,
      clinic: authorized.clinic,
      backendPermissions: const {
        Permissions.usersEdit,
        Permissions.usersSuspend,
        Permissions.usersAssignRoles,
      },
    );
    await expectLater(
      repository.changeClinicUserRole(
        actingSession: restricted,
        targetUserId: 'staff-1',
        newRole: 'Veterinarian',
        newRoleId: 'role-vet',
      ),
      throwsA(isA<StateError>()),
    );
    expect(api.patchPath, equals(null));
  });
}

RemoteCurrentUser _administrator({
  required String roleId,
  bool includeRoleMetadata = true,
}) => RemoteCurrentUser(
  userId: 'admin-1',
  clinicId: 'clinic-1',
  accountType: AccountTypes.clinicAdministrator,
  permissions: const {
    Permissions.usersView,
    Permissions.usersCreate,
    Permissions.usersEdit,
    Permissions.usersSuspend,
    Permissions.usersAssignRoles,
    Permissions.staffRolesManage,
  },
  fullName: 'Clinic Administrator',
  email: 'admin@example.test',
  roleId: roleId,
  roleCode: includeRoleMetadata ? 'clinic_administrator' : null,
  roleName: includeRoleMetadata ? 'Clinic Administrator' : null,
  clinicName: 'AVERA Clinic',
  clinicStatus: 'Active',
  subscriptionPlan: 'Professional',
);

class _RoleApiClient extends ApiClient {
  _RoleApiClient()
    : super(
        baseUrl: 'https://api.avera.test',
        tokens: const TokenStore(FlutterSecureStorage()),
      );

  String? patchPath;
  Map<String, dynamic>? patchBody;
  String? postPath;
  Map<String, dynamic>? postBody;
  bool roleChanged = false;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    bool authenticated = true,
    bool retry = true,
  }) async {
    if (path == '/api/v1/roles') {
      return {
        'roles': [
          {
            'roleId': 'role-vet',
            'roleCode': 'veterinarian',
            'roleName': 'Veterinarian',
          },
        ],
      };
    }
    if (path == '/api/v1/users') {
      return {
        'users': [
          {
            'userId': 'staff-1',
            'fullName': 'Ada Vet',
            'email': 'ada@example.test',
            'accountType': AccountTypes.clinicStaff,
            'status': AccountStatuses.active,
            'membershipStatus': ClinicMembershipStatuses.active,
            'roleId': roleChanged ? 'role-vet' : 'role-reception',
            'roleCode': roleChanged ? 'veterinarian' : 'receptionist',
            'roleName': roleChanged ? 'Veterinarian' : 'Receptionist',
          },
        ],
      };
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retry = true,
  }) async {
    patchPath = path;
    patchBody = body;
    roleChanged = true;
    return {
      'user': {
        'userId': 'staff-1',
        'accountType': AccountTypes.clinicStaff,
        'roleId': 'role-vet',
        'roleCode': 'veterinarian',
        'roleName': 'Veterinarian',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retry = true,
  }) async {
    postPath = path;
    postBody = body;
    if (path == '/api/v1/users/invitations') {
      return {
        'invitation': {
          'userId': 'staff-invited',
          'status': 'PendingActivation',
          'staffNumber': '004',
          'delivery': {
            'status': 'Submitted',
            'emailState': 'Submitted',
            'provider': 'resend',
            'providerMessageId': 'resend-message-1',
            'submittedAt': '2026-08-30T08:05:57.938Z',
          },
        },
      };
    }
    throw StateError('Unexpected POST $path');
  }
}
