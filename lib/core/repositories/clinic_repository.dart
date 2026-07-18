import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/clinic_work_hours.dart';
import '../models/animal_search_result.dart';
import '../remote/auth_remote_data_source.dart';
import '../security/access_control.dart';
import '../remote/api_client.dart';
import '../services/feature_gate_service.dart';
import 'subscription_repository.dart';

class DashboardStats {
  const DashboardStats({
    required this.totalAnimals,
    required this.todaysConsultations,
    required this.appointmentsToday,
    required this.vaccinationsDue,
    required this.lowStock,
    required this.expiredDrugs,
    required this.monthlyRevenue,
    required this.recentVisits,
    required this.unreadNotifications,
  });

  final int totalAnimals;
  final int todaysConsultations;
  final int appointmentsToday;
  final int vaccinationsDue;
  final int lowStock;
  final int expiredDrugs;
  final double monthlyRevenue;
  final List<Visit> recentVisits;
  final int unreadNotifications;
}

class AnimalProfile {
  const AnimalProfile({
    required this.animal,
    required this.owner,
    required this.visits,
    required this.vaccinations,
    required this.appointments,
    required this.sales,
  });

  final Animal animal;
  final Owner owner;
  final List<Visit> visits;
  final List<Vaccination> vaccinations;
  final List<Appointment> appointments;
  final List<Sale> sales;
}

class ClinicVaccinationRecord {
  const ClinicVaccinationRecord({
    required this.vaccination,
    required this.animal,
    required this.owner,
  });

  final Vaccination vaccination;
  final Animal animal;
  final Owner owner;
}

class UserSession {
  const UserSession({
    required this.user,
    required this.clinic,
    this.backendPermissions,
  });

  final AppUser user;
  final Clinic clinic;
  final Set<String>? backendPermissions;

  bool get isPlatformOwner => user.accountType == AccountTypes.platformOwner;
  bool get isClinicAdministrator =>
      user.accountType == AccountTypes.clinicAdministrator ||
      user.role == 'Clinic Administrator';

  bool can(String permission) {
    if (backendPermissions != null) {
      return backendPermissions!.contains('*') ||
          backendPermissions!.contains(permission);
    }
    if (isPlatformOwner) {
      return true;
    }
    final overrides = _permissionsFromJson(user.permissions);
    final defaults = rolePermissions[user.role] ?? const <String>{};
    if (overrides.contains(permission) || defaults.contains(permission)) {
      return true;
    }
    return _legacyPermissionMatch(permission, overrides, defaults);
  }

  Set<String> get effectivePermissions =>
      backendPermissions ??
      {
        ...rolePermissions[user.role] ?? const <String>{},
        ..._permissionsFromJson(user.permissions),
      };
}

class ClinicApplication {
  const ClinicApplication({
    required this.clinicName,
    required this.clinicEmail,
    required this.phoneNumber,
    required this.address,
    required this.city,
    required this.country,
    required this.administratorName,
    required this.administratorEmail,
    required this.administratorPhone,
    required this.professionalTitle,
    required this.subscriptionPlan,
    this.timeZone = 'Africa/Lagos',
    this.reference,
  });

  final String clinicName;
  final String clinicEmail;
  final String phoneNumber;
  final String address;
  final String city;
  final String country;
  final String administratorName;
  final String administratorEmail;
  final String administratorPhone;
  final String professionalTitle;
  final String subscriptionPlan;
  final String timeZone;
  final String? reference;
}

class ClinicAdministratorActivation {
  const ClinicAdministratorActivation({
    required this.clinic,
    required this.user,
  });

  final Clinic clinic;
  final AppUser user;
}

const _defaultClinicWorkDays = <ClinicWorkDayConfig>[
  ClinicWorkDayConfig(
    weekday: 'monday',
    isOpen: true,
    openingTime: '08:00',
    closingTime: '18:00',
  ),
  ClinicWorkDayConfig(
    weekday: 'tuesday',
    isOpen: true,
    openingTime: '08:00',
    closingTime: '18:00',
  ),
  ClinicWorkDayConfig(
    weekday: 'wednesday',
    isOpen: true,
    openingTime: '08:00',
    closingTime: '18:00',
  ),
  ClinicWorkDayConfig(
    weekday: 'thursday',
    isOpen: true,
    openingTime: '08:00',
    closingTime: '18:00',
  ),
  ClinicWorkDayConfig(
    weekday: 'friday',
    isOpen: true,
    openingTime: '08:00',
    closingTime: '18:00',
  ),
  ClinicWorkDayConfig(
    weekday: 'saturday',
    isOpen: true,
    openingTime: '08:00',
    closingTime: '18:00',
  ),
  ClinicWorkDayConfig(weekday: 'sunday', isOpen: false),
];

Set<String> _permissionsFromJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded.whereType<String>().toSet();
  } catch (_) {}
  return const <String>{};
}

bool _legacyPermissionMatch(
  String permission,
  Set<String> overrides,
  Set<String> defaults,
) {
  final all = {...overrides, ...defaults};
  final normalized = permission.toLowerCase();
  if (normalized == 'create consultation') {
    return all.contains(Permissions.consultationsCreate);
  }
  if (normalized == 'edit consultation') {
    return all.contains(Permissions.consultationsEdit);
  }
  if (normalized == 'manage vaccinations') {
    return all.contains(Permissions.vaccinationsAdd);
  }
  if (normalized == 'manage billing') {
    return all.contains(Permissions.billingCreate);
  }
  if (normalized == 'manage appointments') {
    return all.contains(Permissions.appointmentsCreate);
  }
  if (normalized == 'edit animal') {
    return all.contains(Permissions.patientsEdit);
  }
  if (normalized == 'manage animal status') {
    return all.contains(Permissions.patientsEdit);
  }
  return false;
}

class AnimalStatuses {
  const AnimalStatuses._();

  static const active = 'Active';
  static const deceased = 'Deceased';
  static const relocated = 'Relocated';
}

class ClinicRepository {
  ClinicRepository(this.db);

  final AppDatabase db;
  final _uuid = const Uuid();
  String _activeClinicId = defaultClinicId;
  String get activeClinicId => _activeClinicId;

  Future<void> _requireActiveFeature(AveraFeature feature) async {
    final access = await LocalSubscriptionRepository(
      db,
    ).canAccess(clinicId: activeClinicId, feature: feature);
    if (!access.allowed) throw FeatureAccessDenied(access);
  }

  Future<UserSession> bootstrapClinicWorkspace() async {
    _activeClinicId = defaultClinicId;
    final clinic = await _ensureDefaultClinic();
    await LocalSubscriptionRepository(db).ensureClinicSubscription(clinic);
    await _ensureClinicWorkHours(clinic.clinicId, timeZone: clinic.timeZone);
    await _ensureDefaultAdmin(clinic.clinicId);
    await _ensurePlatformOwner();
    await _ensureDefaultProtocols(clinic.clinicId);
    await _generateNotifications(clinic.clinicId);
    final user =
        await (db.select(db.appUsers)
              ..where((u) => u.clinicId.equals(clinic.clinicId))
              ..limit(1))
            .getSingle();
    return UserSession(user: user, clinic: clinic);
  }

  /// Creates an isolated tenant application. It deliberately creates no
  /// patients, stock, staff, or operational data until approval and activation.
  Future<ClinicApplication> submitClinicApplication(
    ClinicApplication application,
  ) async {
    final normalizedEmail = application.administratorEmail.trim().toLowerCase();
    final duplicate =
        await (db.select(db.appUsers)
              ..where((user) => user.email.lower().equals(normalizedEmail)))
            .getSingleOrNull();
    if (duplicate != null) {
      throw StateError(
        'An account already exists for this administrator email.',
      );
    }
    final clinicId = _uuid.v4();
    final reference =
        'AVR-${DateFormat('yyyyMMdd').format(DateTime.now())}-${clinicId.substring(0, 6).toUpperCase()}';
    final now = DateTime.now();
    await db.transaction(() async {
      await db
          .into(db.clinics)
          .insert(
            ClinicsCompanion.insert(
              clinicId: clinicId,
              clinicName: application.clinicName.trim(),
              address: Value(application.address.trim()),
              city: Value(application.city.trim()),
              country: Value(application.country.trim()),
              phoneNumber: Value(application.phoneNumber.trim()),
              email: Value(application.clinicEmail.trim().toLowerCase()),
              clinicOwner: Value(application.administratorName.trim()),
              timeZone: Value(application.timeZone),
              subscriptionPlan: Value(application.subscriptionPlan),
              clinicStatus: const Value('PendingApproval'),
              dateRegistered: now,
            ),
          );
      await db
          .into(db.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: _uuid.v4(),
              clinicId: clinicId,
              fullName: application.administratorName.trim(),
              username: normalizedEmail,
              email: normalizedEmail,
              phoneNumber: Value(application.administratorPhone.trim()),
              passwordHash: _hashPassword(_uuid.v4()),
              role: 'Clinic Administrator',
              accountType: const Value(AccountTypes.clinicAdministrator),
              accountStatus: const Value('PendingApproval'),
              invitationStatus: const Value('PendingApproval'),
              professionalTitle: Value(
                application.professionalTitle.trim().isEmpty
                    ? null
                    : application.professionalTitle.trim(),
              ),
              createdAt: now,
            ),
          );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(clinicId),
              action: 'clinic.application_submitted',
              entityType: const Value('Clinic'),
              entityId: Value(clinicId),
              details: Value(
                'Clinic application $reference submitted for review.',
              ),
              createdAt: now,
            ),
          );
      await _ensureClinicWorkHours(clinicId, timeZone: application.timeZone);
    });
    final createdClinic = await (db.select(
      db.clinics,
    )..where((clinic) => clinic.clinicId.equals(clinicId))).getSingle();
    await LocalSubscriptionRepository(
      db,
    ).ensureClinicSubscription(createdClinic);
    return ClinicApplication(
      clinicName: application.clinicName,
      clinicEmail: application.clinicEmail,
      phoneNumber: application.phoneNumber,
      address: application.address,
      city: application.city,
      country: application.country,
      administratorName: application.administratorName,
      administratorEmail: application.administratorEmail,
      administratorPhone: application.administratorPhone,
      professionalTitle: application.professionalTitle,
      subscriptionPlan: application.subscriptionPlan,
      timeZone: application.timeZone,
      reference: reference,
    );
  }

  Future<Clinic> _ensureDefaultClinic() async {
    final existing = await (db.select(
      db.clinics,
    )..where((c) => c.clinicId.equals(activeClinicId))).getSingleOrNull();
    if (existing != null) {
      if (existing.clinicName == 'Zevora Veterinary Clinic') {
        await (db.update(
          db.clinics,
        )..where((clinic) => clinic.clinicId.equals(existing.clinicId))).write(
          const ClinicsCompanion(clinicName: Value('Avera Veterinary Clinic')),
        );
        return (db.select(db.clinics)
              ..where((clinic) => clinic.clinicId.equals(existing.clinicId)))
            .getSingle();
      }
      return existing;
    }
    await db
        .into(db.clinics)
        .insert(
          ClinicsCompanion.insert(
            clinicId: activeClinicId,
            clinicName: 'Avera Veterinary Clinic',
            address: const Value('12 Wellness Street'),
            city: const Value('Lagos'),
            state: const Value('Lagos'),
            country: const Value('Nigeria'),
            phoneNumber: const Value('+234 800 000 0000'),
            email: const Value('care@avera.test'),
            website: const Value('https://avera.test'),
            veterinaryLicenseNumber: const Value('VET-DEMO-001'),
            clinicType: const Value('Small Animal and Mixed Practice'),
            workingHours: const Value('Mon-Sat 08:00-18:00'),
            emergencyContact: const Value('+234 800 000 0001'),
            currency: const Value('NGN'),
            timeZone: const Value('Africa/Lagos'),
            preferredLanguage: const Value('English'),
            clinicOwner: const Value('System Administrator'),
            dateRegistered: DateTime.now(),
            subscriptionPlan: const Value('Professional'),
          ),
        );
    return (db.select(
      db.clinics,
    )..where((c) => c.clinicId.equals(activeClinicId))).getSingle();
  }

  Future<void> _ensureClinicWorkHours(
    String clinicId, {
    required String timeZone,
  }) async {
    final now = DateTime.now();
    final header = await (db.select(
      db.clinicWorkHours,
    )..where((item) => item.clinicId.equals(clinicId))).getSingleOrNull();
    if (header == null) {
      await db
          .into(db.clinicWorkHours)
          .insert(
            ClinicWorkHoursCompanion.insert(
              clinicId: clinicId,
              timeZone: Value(timeZone),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    for (final day in _defaultClinicWorkDays) {
      final existing =
          await (db.select(db.clinicWorkDays)..where(
                (item) =>
                    item.clinicId.equals(clinicId) &
                    item.weekday.equals(day.weekday),
              ))
              .getSingleOrNull();
      if (existing != null) continue;
      await db
          .into(db.clinicWorkDays)
          .insert(
            ClinicWorkDaysCompanion.insert(
              clinicId: clinicId,
              weekday: day.weekday,
              isOpen: Value(day.isOpen),
              openingTime: Value(day.openingTime),
              closingTime: Value(day.closingTime),
              breakStart: Value(day.breakStart),
              breakEnd: Value(day.breakEnd),
              updatedAt: now,
            ),
          );
    }
  }

  Future<ClinicWorkHoursConfig?> clinicWorkHours({String? clinicId}) async {
    final targetClinicId = clinicId ?? activeClinicId;
    final header = await (db.select(
      db.clinicWorkHours,
    )..where((item) => item.clinicId.equals(targetClinicId))).getSingleOrNull();
    if (header == null) return null;
    final rows = await (db.select(
      db.clinicWorkDays,
    )..where((item) => item.clinicId.equals(targetClinicId))).get();
    final byWeekday = {for (final row in rows) row.weekday: row};
    return ClinicWorkHoursConfig(
      clinicId: targetClinicId,
      timeZone: header.timeZone,
      isEnabled: header.isEnabled,
      days: [
        for (final weekday in clinicWeekdays)
          ClinicWorkDayConfig(
            weekday: weekday,
            isOpen: byWeekday[weekday]?.isOpen ?? false,
            openingTime: byWeekday[weekday]?.openingTime,
            closingTime: byWeekday[weekday]?.closingTime,
            breakStart: byWeekday[weekday]?.breakStart,
            breakEnd: byWeekday[weekday]?.breakEnd,
          ),
      ],
    );
  }

  Future<void> updateClinicWorkHours({
    required UserSession session,
    required String timeZone,
    required bool isEnabled,
    required List<ClinicWorkDayConfig> days,
  }) async {
    if (!session.can(Permissions.clinicWorkHoursManage) &&
        !session.can(Permissions.clinicSettingsEdit)) {
      throw StateError(
        'You do not have permission to update clinic work hours.',
      );
    }
    if (session.clinic.clinicId != activeClinicId) {
      throw StateError('Clinic work hours can only be changed in this clinic.');
    }
    _validateClinicWorkHours(days);
    final previous = await clinicWorkHours();
    final now = DateTime.now();
    await db.transaction(() async {
      await _ensureClinicWorkHours(activeClinicId, timeZone: timeZone);
      await (db.update(
        db.clinicWorkHours,
      )..where((item) => item.clinicId.equals(activeClinicId))).write(
        ClinicWorkHoursCompanion(
          timeZone: Value(timeZone),
          isEnabled: Value(isEnabled),
          updatedAt: Value(now),
        ),
      );
      await (db.update(db.clinics)
            ..where((item) => item.clinicId.equals(activeClinicId)))
          .write(ClinicsCompanion(timeZone: Value(timeZone)));
      for (final day in days) {
        await (db.update(db.clinicWorkDays)..where(
              (item) =>
                  item.clinicId.equals(activeClinicId) &
                  item.weekday.equals(day.weekday),
            ))
            .write(
              ClinicWorkDaysCompanion(
                isOpen: Value(day.isOpen),
                openingTime: Value(day.openingTime),
                closingTime: Value(day.closingTime),
                breakStart: Value(day.breakStart),
                breakEnd: Value(day.breakEnd),
                updatedAt: Value(now),
              ),
            );
      }
      final updated = ClinicWorkHoursConfig(
        clinicId: activeClinicId,
        timeZone: timeZone,
        isEnabled: isEnabled,
        days: days,
      );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(activeClinicId),
              userId: Value(session.user.userId),
              action: 'clinic.work_hours_updated',
              entityType: const Value('ClinicWorkHours'),
              entityId: Value(activeClinicId),
              details: Value(
                jsonEncode({
                  'previous': previous?.toJson(),
                  'new': updated.toJson(),
                }),
              ),
              createdAt: now,
            ),
          );
    });
  }

  void _validateClinicWorkHours(List<ClinicWorkDayConfig> days) {
    if (days.length != clinicWeekdays.length ||
        {for (final day in days) day.weekday}.length != clinicWeekdays.length) {
      throw StateError('Provide one work-hours entry for each weekday.');
    }
    for (final day in days) {
      if (!day.isOpen) continue;
      if (day.openingTime == null || day.closingTime == null) {
        throw StateError('${day.weekday} needs opening and closing times.');
      }
      final opening = _minutes(day.openingTime!);
      final closing = _minutes(day.closingTime!);
      if (opening >= closing) {
        throw StateError('Opening time must be before closing time.');
      }
      final hasBreak = day.breakStart != null || day.breakEnd != null;
      if (!hasBreak) continue;
      if (day.breakStart == null || day.breakEnd == null) {
        throw StateError('Enter both break start and break end times.');
      }
      final breakStart = _minutes(day.breakStart!);
      final breakEnd = _minutes(day.breakEnd!);
      if (breakStart <= opening ||
          breakEnd >= closing ||
          breakStart >= breakEnd) {
        throw StateError('Break times must fall within the working day.');
      }
    }
  }

  int _minutes(String value) {
    final pieces = value.split(':');
    if (pieces.length != 2) throw StateError('Use a valid 24-hour time.');
    final hour = int.tryParse(pieces[0]);
    final minute = int.tryParse(pieces[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw StateError('Use a valid 24-hour time.');
    }
    return hour * 60 + minute;
  }

  Future<void> _ensureDefaultAdmin(String clinicId) async {
    // A clinic can legitimately have many users. Only the development admin
    // identity is relevant to this idempotent local bootstrap.
    final existingAdmins =
        await (db.select(db.appUsers)..where(
              (u) =>
                  u.clinicId.equals(clinicId) &
                  u.email.lower().equals('admin@avera.test'),
            ))
            .get();
    if (existingAdmins.isNotEmpty) return;
    await db
        .into(db.appUsers)
        .insert(
          AppUsersCompanion.insert(
            userId: _uuid.v4(),
            clinicId: clinicId,
            fullName: 'System Administrator',
            username: 'admin',
            email: 'admin@avera.test',
            passwordHash: _hashPassword('admin123'),
            role: 'Clinic Administrator',
            accountType: const Value(AccountTypes.clinicAdministrator),
            permissions: const Value(
              '["patients.view","patients.create","patients.edit","consultations.view","consultations.create","consultations.edit","vaccinations.view","vaccinations.add","inventory.view","inventory.edit","billing.view","billing.create","appointments.view","appointments.create","users.view","users.create","users.edit","users.suspend","users.assign_roles","users.assign_permissions","clinic_settings.view","clinic_settings.edit","audit_logs.view","reports.export"]',
            ),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> _ensurePlatformOwner() async {
    const platformClinicId = 'platform-control';
    final platformClinic = await (db.select(
      db.clinics,
    )..where((c) => c.clinicId.equals(platformClinicId))).getSingleOrNull();
    if (platformClinic == null) {
      await db
          .into(db.clinics)
          .insert(
            ClinicsCompanion.insert(
              clinicId: platformClinicId,
              clinicName: 'AVERA Platform Control',
              dateRegistered: DateTime.now(),
              clinicStatus: const Value('Active'),
            ),
          );
    }
    // Older development builds could leave more than one Platform Owner row
    // behind. Keep those records intact, but never let them prevent the local
    // application from bootstrapping or authenticating a clinic user.
    final owners = await (db.select(
      db.appUsers,
    )..where((u) => u.accountType.equals(AccountTypes.platformOwner))).get();
    if (owners.isNotEmpty) return;
    await db
        .into(db.appUsers)
        .insert(
          AppUsersCompanion.insert(
            userId: _uuid.v4(),
            clinicId: platformClinicId,
            fullName: 'Platform Owner (Development)',
            username: 'platform.owner',
            email: 'owner@avera.test',
            passwordHash: _hashPassword('change-me-locally'),
            role: 'Platform Owner',
            accountType: const Value(AccountTypes.platformOwner),
            permissions: Value(jsonEncode(allPermissions.toList())),
            createdAt: DateTime.now(),
          ),
        );
  }

  String _hashPassword(String password) {
    return sha256.convert('$password:zevora-local-salt'.codeUnits).toString();
  }

  String _hashActivationToken(String token) =>
      sha256.convert('activation:$token'.codeUnits).toString();

  String _newActivationToken() => _uuid.v4() + _uuid.v4();

  Future<UserSession?> authenticateUser({
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    await _ensureDefaultClinic();
    await _ensurePlatformOwner();
    final identifier = username.trim().toLowerCase();
    final user =
        await (db.select(db.appUsers)..where(
              (u) =>
                  (u.username.lower().equals(identifier) |
                      u.email.lower().equals(identifier)) &
                  u.passwordHash.equals(_hashPassword(password)),
            ))
            .getSingleOrNull();
    if (user == null || user.accountStatus != 'Active') return null;
    final clinic = await (db.select(
      db.clinics,
    )..where((c) => c.clinicId.equals(user.clinicId))).getSingle();
    await (db.update(
      db.appUsers,
    )..where((u) => u.userId.equals(user.userId))).write(
      AppUsersCompanion(
        lastLogin: Value(DateTime.now()),
        rememberMe: Value(rememberMe),
      ),
    );
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: Value(clinic.clinicId),
            userId: Value(user.userId),
            action: 'login',
            entityType: const Value('AppUser'),
            entityId: Value(user.userId),
            details: Value('User ${user.username} authenticated locally.'),
            createdAt: DateTime.now(),
          ),
        );
    _activeClinicId = clinic.clinicId;
    return UserSession(
      user: user.copyWith(lastLogin: Value(DateTime.now())),
      clinic: clinic,
    );
  }

  Future<UserSession?> restoreUserSession({
    required String userId,
    required String clinicId,
  }) async {
    await _ensureDefaultClinic();
    await _ensurePlatformOwner();
    final user =
        await (db.select(db.appUsers)..where(
              (u) => u.userId.equals(userId) & u.clinicId.equals(clinicId),
            ))
            .getSingleOrNull();
    if (user == null || user.accountStatus != AccountStatuses.active) {
      return null;
    }
    final clinic = await (db.select(
      db.clinics,
    )..where((c) => c.clinicId.equals(clinicId))).getSingleOrNull();
    if (clinic == null || clinic.clinicStatus != 'Active') return null;
    _activeClinicId = clinic.clinicId;
    return UserSession(user: user, clinic: clinic);
  }

  /// Caches only backend-provided profile data so existing offline UI can read a
  /// session. Passwords and permission defaults never enter Drift here.
  Future<UserSession> cacheRemoteSession(RemoteCurrentUser remote) async {
    final clinicId = remote.clinicId ?? 'platform-control';
    final clinicName =
        remote.clinicName ??
        (remote.accountType == AccountTypes.platformOwner
            ? 'AVERA Platform'
            : 'AVERA Clinic');
    final clinicStatus = remote.clinicStatus ?? 'Active';
    final role = remote.roleId ?? remote.accountType;
    final now = DateTime.now();
    await db.transaction(() async {
      await db
          .into(db.clinics)
          .insertOnConflictUpdate(
            ClinicsCompanion.insert(
              clinicId: clinicId,
              clinicName: clinicName,
              dateRegistered: now,
              clinicStatus: Value(clinicStatus),
              subscriptionPlan: Value(remote.subscriptionPlan ?? 'Starter'),
            ),
          );
      await db
          .into(db.appUsers)
          .insertOnConflictUpdate(
            AppUsersCompanion.insert(
              userId: remote.userId,
              clinicId: clinicId,
              fullName: remote.fullName,
              username: remote.email,
              email: remote.email,
              passwordHash: 'backend-managed',
              role: role,
              roleId: Value(remote.roleId),
              accountType: Value(remote.accountType),
              accountStatus: const Value(AccountStatuses.active),
              permissions: Value(jsonEncode(remote.permissions.toList())),
              createdAt: now,
              updatedAt: Value(now),
            ),
          );
    });
    final user = await (db.select(
      db.appUsers,
    )..where((item) => item.userId.equals(remote.userId))).getSingle();
    final clinic = await (db.select(
      db.clinics,
    )..where((item) => item.clinicId.equals(clinicId))).getSingle();
    _activeClinicId = clinicId;
    return UserSession(
      user: user,
      clinic: clinic,
      backendPermissions: remote.permissions,
    );
  }

  Stream<List<AppUser>> watchClinicUsers(String clinicId) {
    return (db.select(db.appUsers)
          ..where((user) => user.clinicId.equals(clinicId))
          ..orderBy([(user) => OrderingTerm.asc(user.fullName)]))
        .watch();
  }

  Stream<List<Clinic>> watchPlatformClinics({String? status}) {
    final query = db.select(db.clinics)
      ..where((clinic) => clinic.clinicId.equals('platform-control').not());
    if (status != null) {
      query.where((clinic) => clinic.clinicStatus.equals(status));
    }
    query.orderBy([(clinic) => OrderingTerm.desc(clinic.dateRegistered)]);
    return query.watch();
  }

  Stream<List<AppUser>> watchPlatformUsers() {
    return (db.select(
      db.appUsers,
    )..orderBy([(user) => OrderingTerm.asc(user.fullName)])).watch();
  }

  Stream<List<AuditLog>> watchPlatformAuditLogs() {
    return (db.select(
      db.auditLogs,
    )..orderBy([(log) => OrderingTerm.desc(log.createdAt)])).watch();
  }

  Future<void> updateClinicStatus({
    required UserSession actingSession,
    required String clinicId,
    required String status,
  }) async {
    if (!actingSession.isPlatformOwner ||
        !(actingSession.can(Permissions.clinicsApprove) ||
            actingSession.can(Permissions.clinicsSuspend))) {
      throw StateError('You do not have permission to manage clinics.');
    }
    if (clinicId == 'platform-control') {
      throw StateError('The Platform Owner control account cannot be changed.');
    }
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.clinics)
            ..where((clinic) => clinic.clinicId.equals(clinicId)))
          .write(ClinicsCompanion(clinicStatus: Value(status)));
      if (status == 'Active') {
        await (db.update(db.appUsers)..where(
              (user) =>
                  user.clinicId.equals(clinicId) &
                  user.accountType.equals(AccountTypes.clinicAdministrator) &
                  user.accountStatus.equals('PendingApproval'),
            ))
            .write(
              AppUsersCompanion(
                accountStatus: const Value('Invited'),
                invitationStatus: const Value('Invited'),
                invitationSentAt: Value(now),
              ),
            );
      }
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(actingSession.clinic.clinicId),
              userId: Value(actingSession.user.userId),
              action: 'clinic.status_changed',
              entityType: const Value('Clinic'),
              entityId: Value(clinicId),
              details: Value('Clinic status changed to $status.'),
              createdAt: now,
            ),
          );
    });
  }

  /// Generates an expiring, single-use local-development activation route.
  /// Only the token hash is persisted; production will deliver this URL by email.
  Future<String> createDevelopmentActivationLink({
    required UserSession actingSession,
    required String clinicId,
  }) async {
    if (!actingSession.isPlatformOwner) {
      throw StateError(
        'You do not have permission to create activation links.',
      );
    }
    final token = _newActivationToken();
    final tokenHash = _hashActivationToken(token);
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));
    await db.transaction(() async {
      final clinic = await (db.select(
        db.clinics,
      )..where((c) => c.clinicId.equals(clinicId))).getSingleOrNull();
      if (clinic == null || clinic.clinicStatus != 'Active') {
        throw StateError('This clinic is not approved for activation.');
      }
      final administrator =
          await (db.select(db.appUsers)..where(
                (user) =>
                    user.clinicId.equals(clinicId) &
                    user.accountType.equals(AccountTypes.clinicAdministrator) &
                    user.accountStatus.equals('Active').not(),
              ))
              .getSingleOrNull();
      if (administrator == null) {
        throw StateError(
          'No invited clinic administrator is available for activation.',
        );
      }
      await (db.update(
        db.appUsers,
      )..where((user) => user.userId.equals(administrator.userId))).write(
        AppUsersCompanion(
          activationTokenHash: Value(tokenHash),
          activationTokenExpiresAt: Value(expiresAt),
          activationTokenUsedAt: const Value(null),
          invitationSentAt: Value(now),
          accountStatus: const Value('Invited'),
          invitationStatus: const Value('Invited'),
        ),
      );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(clinicId),
              userId: Value(actingSession.user.userId),
              action: 'administrator.activation_link_generated',
              entityType: const Value('AppUser'),
              entityId: Value(administrator.userId),
              details: const Value(
                'A development activation link was generated.',
              ),
              createdAt: now,
            ),
          );
    });
    return '/activate-clinic-admin?token=$token';
  }

  Future<ClinicAdministratorActivation?> validateClinicAdministratorActivation(
    String token,
  ) async {
    if (token.trim().isEmpty) return null;
    final user =
        await (db.select(db.appUsers)..where(
              (u) => u.activationTokenHash.equals(_hashActivationToken(token)),
            ))
            .getSingleOrNull();
    if (user == null ||
        user.accountStatus != 'Invited' ||
        user.activationTokenUsedAt != null ||
        user.activationTokenExpiresAt == null ||
        user.activationTokenExpiresAt!.isBefore(DateTime.now())) {
      return null;
    }
    final clinic = await (db.select(
      db.clinics,
    )..where((c) => c.clinicId.equals(user.clinicId))).getSingleOrNull();
    if (clinic == null || clinic.clinicStatus != 'Active') return null;
    return ClinicAdministratorActivation(clinic: clinic, user: user);
  }

  Future<void> activateClinicAdministrator({
    required String token,
    required String password,
  }) async {
    final error = _firstPasswordError(password: password);
    if (error != null) throw StateError(error);
    final activation = await validateClinicAdministratorActivation(token);
    if (activation == null) {
      throw StateError(
        'This activation link is invalid, expired, or already used.',
      );
    }
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(
        db.appUsers,
      )..where((user) => user.userId.equals(activation.user.userId))).write(
        AppUsersCompanion(
          passwordHash: Value(_hashPassword(password)),
          accountStatus: const Value('Active'),
          invitationStatus: const Value('Active'),
          emailVerifiedAt: Value(now),
          passwordChangedAt: Value(now),
          activatedAt: Value(now),
          activationTokenHash: const Value(null),
          activationTokenExpiresAt: const Value(null),
          activationTokenUsedAt: Value(now),
          requiresPasswordChange: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(activation.clinic.clinicId),
              userId: Value(activation.user.userId),
              action: 'administrator.activated',
              entityType: const Value('AppUser'),
              entityId: Value(activation.user.userId),
              details: const Value(
                'Clinic administrator activated their account.',
              ),
              createdAt: now,
            ),
          );
    });
  }

  String? _firstPasswordError({required String password}) {
    if (password.length < 12) return 'Use at least 12 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Include uppercase, lowercase, a number, and a symbol.';
    }
    const blocked = {
      'admin123',
      'change-me-locally',
      'password123',
      'avery123',
    };
    if (blocked.contains(password.toLowerCase())) {
      return 'Choose a password that is not a development default.';
    }
    return null;
  }

  Future<String?> requestPasswordReset(String email) async {
    final user =
        await (db.select(db.appUsers)..where(
              (u) =>
                  u.email.lower().equals(email.trim().toLowerCase()) &
                  u.accountStatus.equals('Active'),
            ))
            .getSingleOrNull();
    if (user == null) return null;
    final token = _newActivationToken();
    final now = DateTime.now();
    await (db.update(
      db.appUsers,
    )..where((u) => u.userId.equals(user.userId))).write(
      AppUsersCompanion(
        activationTokenHash: Value(_hashActivationToken(token)),
        activationTokenExpiresAt: Value(now.add(const Duration(minutes: 20))),
        activationTokenUsedAt: const Value(null),
        updatedAt: Value(now),
      ),
    );
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: Value(user.clinicId),
            userId: Value(user.userId),
            action: 'password_reset_requested',
            entityType: const Value('AppUser'),
            entityId: Value(user.userId),
            details: const Value('Password reset requested.'),
            createdAt: now,
          ),
        );
    return '/reset-password?token=$token';
  }

  Future<AppUser?> validatePasswordReset(String token) async {
    final user =
        await (db.select(db.appUsers)..where(
              (u) =>
                  u.activationTokenHash.equals(_hashActivationToken(token)) &
                  u.accountStatus.equals('Active'),
            ))
            .getSingleOrNull();
    if (user == null ||
        user.activationTokenUsedAt != null ||
        user.activationTokenExpiresAt == null ||
        user.activationTokenExpiresAt!.isBefore(DateTime.now())) {
      return null;
    }
    return user;
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    final user = await validatePasswordReset(token);
    if (user == null) {
      throw StateError(
        'This password-reset link is invalid or no longer available.',
      );
    }
    final error = _firstPasswordError(password: password);
    if (error != null) throw StateError(error);
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(
        db.appUsers,
      )..where((u) => u.userId.equals(user.userId))).write(
        AppUsersCompanion(
          passwordHash: Value(_hashPassword(password)),
          passwordChangedAt: Value(now),
          activationTokenHash: const Value(null),
          activationTokenExpiresAt: const Value(null),
          activationTokenUsedAt: Value(now),
          rememberMe: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(user.clinicId),
              userId: Value(user.userId),
              action: 'password_reset_completed',
              entityType: const Value('AppUser'),
              entityId: Value(user.userId),
              details: const Value(
                'Password reset completed; local sessions revoked.',
              ),
              createdAt: now,
            ),
          );
    });
  }

  Future<void> updateClinicSubscription({
    required UserSession actingSession,
    required String clinicId,
    required String plan,
  }) async {
    if (!actingSession.isPlatformOwner ||
        !actingSession.can(Permissions.subscriptionsManage)) {
      throw StateError('You do not have permission to manage subscriptions.');
    }
    final selected = SubscriptionPlan.fromStorage(plan);
    await LocalSubscriptionRepository(db).assignPlan(
      clinicId: clinicId,
      plan: selected,
      actingUserId: actingSession.user.userId,
      action: 'subscription.updated',
    );
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: Value(actingSession.clinic.clinicId),
            userId: Value(actingSession.user.userId),
            action: 'subscription.updated',
            entityType: const Value('Clinic'),
            entityId: Value(clinicId),
            details: Value('Subscription plan changed to ${selected.label}.'),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> simulateSubscriptionPlan({
    required UserSession actingSession,
    required SubscriptionPlan plan,
  }) async {
    if (!BackendConfiguration.isLocalMode || kReleaseMode) {
      throw StateError(
        'Subscription simulation is available only in local debug mode.',
      );
    }
    if (!actingSession.isPlatformOwner ||
        !actingSession.can(Permissions.subscriptionsManage)) {
      throw StateError('You do not have permission to simulate subscriptions.');
    }
    await LocalSubscriptionRepository(db).assignPlan(
      clinicId: defaultClinicId,
      plan: plan,
      actingUserId: actingSession.user.userId,
      action: 'subscription.simulated',
    );
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: const Value(defaultClinicId),
            userId: Value(actingSession.user.userId),
            action: 'subscription.simulated',
            entityType: const Value('Clinic'),
            entityId: const Value(defaultClinicId),
            details: Value(
              'Local development plan simulation changed to ${plan.label}.',
            ),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> changeOwnPassword({
    required UserSession session,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 12 ||
        !RegExp(r'[A-Z]').hasMatch(newPassword) ||
        !RegExp(r'[a-z]').hasMatch(newPassword) ||
        !RegExp(r'\d').hasMatch(newPassword)) {
      throw StateError(
        'Use at least 12 characters with upper-case, lower-case, and a number.',
      );
    }
    final current = await (db.select(
      db.appUsers,
    )..where((user) => user.userId.equals(session.user.userId))).getSingle();
    if (current.passwordHash != _hashPassword(currentPassword)) {
      throw StateError('Your current password is incorrect.');
    }
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(
        db.appUsers,
      )..where((user) => user.userId.equals(current.userId))).write(
        AppUsersCompanion(
          passwordHash: Value(_hashPassword(newPassword)),
          passwordChangedAt: Value(now),
          requiresPasswordChange: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(session.clinic.clinicId),
              userId: Value(session.user.userId),
              action: 'password.changed',
              entityType: const Value('AppUser'),
              entityId: Value(session.user.userId),
              details: const Value('Password changed by account owner.'),
              createdAt: now,
            ),
          );
    });
  }

  Future<String> inviteClinicUser({
    required UserSession actingSession,
    required String fullName,
    required String email,
    required String role,
    String? phoneNumber,
    String? professionalTitle,
    String? staffNumber,
    Set<String> permissionOverrides = const {},
  }) async {
    if (!actingSession.can(Permissions.usersCreate)) {
      throw StateError('You do not have permission to invite users.');
    }
    final normalizedEmail = email.trim().toLowerCase();
    final duplicate =
        await (db.select(db.appUsers)
              ..where((user) => user.email.lower().equals(normalizedEmail)))
            .getSingleOrNull();
    if (duplicate != null) {
      throw StateError('An account already uses this email address.');
    }
    final now = DateTime.now();
    final userId = _uuid.v4();
    final token = _newActivationToken();
    await db.transaction(() async {
      await db
          .into(db.appUsers)
          .insert(
            AppUsersCompanion.insert(
              userId: userId,
              clinicId: actingSession.clinic.clinicId,
              fullName: fullName.trim(),
              username: normalizedEmail,
              email: normalizedEmail,
              passwordHash: _hashPassword(_uuid.v4()),
              role: role,
              roleId: Value(role),
              accountType: const Value(AccountTypes.clinicStaff),
              accountStatus: const Value(AccountStatuses.invited),
              invitationStatus: const Value(AccountStatuses.invited),
              invitationSentAt: Value(now),
              activationTokenHash: Value(_hashActivationToken(token)),
              activationTokenExpiresAt: Value(
                now.add(const Duration(hours: 72)),
              ),
              phoneNumber: Value(
                phoneNumber?.trim().isEmpty ?? true
                    ? null
                    : phoneNumber!.trim(),
              ),
              professionalTitle: Value(
                professionalTitle?.trim().isEmpty ?? true
                    ? null
                    : professionalTitle!.trim(),
              ),
              staffNumber: Value(
                staffNumber?.trim().isEmpty ?? true
                    ? null
                    : staffNumber!.trim(),
              ),
              permissions: Value(jsonEncode(permissionOverrides.toList())),
              createdBy: Value(actingSession.user.userId),
              createdAt: now,
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(actingSession.clinic.clinicId),
              userId: Value(actingSession.user.userId),
              action: 'user.invited',
              entityType: const Value('AppUser'),
              entityId: Value(userId),
              details: Value('Invited $normalizedEmail as $role.'),
              createdAt: now,
            ),
          );
    });
    return '/activate-clinic-admin?token=$token';
  }

  Future<void> updateClinicBranding({
    String? logo,
    String? banner,
    String? themeColor,
  }) async {
    await _ensureDefaultClinic();
    await (db.update(
      db.clinics,
    )..where((clinic) => clinic.clinicId.equals(activeClinicId))).write(
      ClinicsCompanion(
        logo: logo == null ? const Value.absent() : Value(logo),
        banner: banner == null ? const Value.absent() : Value(banner),
        themeColor: themeColor == null
            ? const Value.absent()
            : Value(themeColor),
      ),
    );
  }

  Future<void> _ensureDefaultProtocols(String clinicId) async {
    final exists = await (db.select(
      db.vaccinationProtocols,
    )..where((p) => p.clinicId.equals(clinicId))).get();
    if (exists.isNotEmpty) return;

    final protocols = [
      _ProtocolSeed(
        'Dog',
        'DHLPP',
        'Distemper, hepatitis, leptospirosis, parainfluenza, parvovirus',
        '6-8 weeks',
        7,
        '1 ml',
        'Subcutaneous',
        'Refrigerate 2-8 C',
        'Boost every 3-4 weeks until about 16 weeks; then annual or triennial per product label.',
      ),
      _ProtocolSeed(
        'Dog',
        'Rabies',
        'Rabies virus',
        '12-16 weeks or per local law',
        14,
        '1 ml',
        'Subcutaneous or intramuscular',
        'Refrigerate 2-8 C',
        'Booster according to local regulations and label.',
      ),
      _ProtocolSeed(
        'Dog',
        'Bordetella',
        'Canine infectious respiratory disease complex',
        '8 weeks when at risk',
        8,
        'Label dose',
        'Intranasal/oral/subcutaneous',
        'Per manufacturer label',
        'Annual or risk-based boosters.',
      ),
      _ProtocolSeed(
        'Dog',
        'Leptospirosis',
        'Leptospira serovars',
        '8-12 weeks where risk exists',
        10,
        '1 ml',
        'Subcutaneous',
        'Refrigerate 2-8 C',
        'Initial two-dose series then annual booster.',
      ),
      _ProtocolSeed(
        'Cat',
        'FVRCP',
        'Feline viral rhinotracheitis, calicivirus, panleukopenia',
        '6-8 weeks',
        7,
        '1 ml',
        'Subcutaneous',
        'Refrigerate 2-8 C',
        'Boost every 3-4 weeks until about 16 weeks; then booster per guidelines.',
      ),
      _ProtocolSeed(
        'Cat',
        'Rabies',
        'Rabies virus',
        '12-16 weeks or per local law',
        14,
        '1 ml',
        'Subcutaneous',
        'Refrigerate 2-8 C',
        'Booster according to local regulations and label.',
      ),
      _ProtocolSeed(
        'Cat',
        'FeLV',
        'Feline leukemia virus',
        '8 weeks for at-risk cats',
        8,
        '1 ml',
        'Subcutaneous',
        'Refrigerate 2-8 C',
        'Two-dose initial series then risk-based booster.',
      ),
    ];

    for (final protocol in protocols) {
      await db
          .into(db.vaccinationProtocols)
          .insert(
            VaccinationProtocolsCompanion.insert(
              clinicId: Value(clinicId),
              species: protocol.species,
              vaccine: protocol.vaccine,
              diseasesProtectedAgainst: Value(protocol.diseases),
              recommendedAge: protocol.age,
              recommendedAgeWeeks: Value(protocol.ageWeeks),
              dose: Value(protocol.dose),
              route: Value(protocol.route),
              storageRequirements: Value(protocol.storage),
              manufacturer: const Value('Editable by clinic administrator'),
              boosterSchedule: Value(protocol.booster),
              contraindications: const Value(
                'Defer during severe illness; follow product label.',
              ),
              possibleAdverseEffects: const Value(
                'Transient soreness, fever, lethargy, hypersensitivity reactions.',
              ),
              precautions: const Value(
                'Verify health status, product expiry, route, and local regulations before use.',
              ),
              certificateTemplate: const Value(
                'AVERA branded vaccination certificate',
              ),
              references: const Value(
                'AAHA/WSAVA-style guideline defaults; adapt to local law and product label.',
              ),
            ),
          );
    }
  }

  Stream<List<AnimalSearchResult>> watchAnimalSearch(
    String query, {
    String? status = AnimalStatuses.active,
  }) {
    final normalized = '%${query.trim().toLowerCase()}%';
    final joined = db.select(db.animals).join([
      innerJoin(db.owners, db.owners.id.equalsExp(db.animals.ownerId)),
    ]);

    joined.where(db.animals.clinicId.equals(activeClinicId));
    if (status != null) {
      joined.where(db.animals.status.equals(status));
    }

    if (query.trim().isNotEmpty) {
      joined.where(
        db.animals.animalName.lower().like(normalized) |
            db.animals.hospitalNumber.lower().like(normalized) |
            db.animals.species.lower().like(normalized) |
            db.animals.breed.lower().like(normalized) |
            db.animals.microchipNumber.lower().like(normalized) |
            db.owners.fullName.lower().like(normalized) |
            db.owners.phone.lower().like(normalized),
      );
    }

    joined.orderBy([
      OrderingTerm.asc(db.animals.animalName),
      OrderingTerm.asc(db.owners.fullName),
    ]);

    return joined.watch().map(
      (rows) => rows.map((row) {
        final animal = row.readTable(db.animals);
        final owner = row.readTable(db.owners);
        return AnimalSearchResult(
          animalId: animal.id,
          hospitalNumber: animal.hospitalNumber,
          animalName: animal.animalName,
          species: animal.species,
          breed: animal.breed,
          sex: animal.sex,
          dateRegistered: animal.dateRegistered,
          ownerName: owner.fullName,
          ownerPhone: owner.phone,
          photo: animal.photo,
          status: animal.status,
          statusUpdatedAt: animal.statusUpdatedAt,
        );
      }).toList(),
    );
  }

  Stream<List<Animal>> watchAnimals() =>
      (db.select(db.animals)
            ..where(
              (a) =>
                  a.clinicId.equals(activeClinicId) &
                  a.status.equals(AnimalStatuses.active),
            )
            ..orderBy([(a) => OrderingTerm.asc(a.animalName)]))
          .watch();

  Stream<List<InventoryItem>> watchInventory() =>
      (db.select(db.inventoryItems)
            ..where((i) => i.clinicId.equals(activeClinicId))
            ..orderBy([(i) => OrderingTerm.asc(i.drugName)]))
          .watch();

  Stream<List<VaccinationProtocol>> watchVaccinationProtocols() =>
      (db.select(db.vaccinationProtocols)
            ..where((p) => p.clinicId.equals(activeClinicId))
            ..orderBy([
              (p) => OrderingTerm.asc(p.species),
              (p) => OrderingTerm.asc(p.recommendedAgeWeeks),
            ]))
          .watch();

  Stream<List<ClinicVaccinationRecord>> watchClinicVaccinations() {
    final query =
        db.select(db.vaccinations).join([
            innerJoin(
              db.animals,
              db.animals.id.equalsExp(db.vaccinations.animalId),
            ),
            innerJoin(db.owners, db.owners.id.equalsExp(db.animals.ownerId)),
          ])
          ..where(db.vaccinations.clinicId.equals(activeClinicId))
          ..orderBy([OrderingTerm.desc(db.vaccinations.nextDueDate)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ClinicVaccinationRecord(
              vaccination: row.readTable(db.vaccinations),
              animal: row.readTable(db.animals),
              owner: row.readTable(db.owners),
            ),
          )
          .toList(),
    );
  }

  Stream<List<Notification>> watchNotifications() =>
      (db.select(db.notifications)
            ..where((n) => n.clinicId.equals(activeClinicId))
            ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
          .watch();

  Future<AnimalProfile> getAnimalProfile(int animalId) async {
    final animal =
        await (db.select(db.animals)..where(
              (a) => a.id.equals(animalId) & a.clinicId.equals(activeClinicId),
            ))
            .getSingle();
    final owner = await (db.select(
      db.owners,
    )..where((o) => o.id.equals(animal.ownerId))).getSingle();
    final visits =
        await (db.select(db.visits)
              ..where(
                (v) =>
                    v.animalId.equals(animalId) &
                    v.clinicId.equals(activeClinicId),
              )
              ..orderBy([(v) => OrderingTerm.desc(v.visitDate)]))
            .get();
    final vaccinations =
        await (db.select(db.vaccinations)
              ..where(
                (v) =>
                    v.animalId.equals(animalId) &
                    v.clinicId.equals(activeClinicId),
              )
              ..orderBy([(v) => OrderingTerm.desc(v.dateGiven)]))
            .get();
    final appointments =
        await (db.select(db.appointments)
              ..where(
                (a) =>
                    a.animalId.equals(animalId) &
                    a.clinicId.equals(activeClinicId),
              )
              ..orderBy([(a) => OrderingTerm.desc(a.appointmentDate)]))
            .get();
    final sales =
        await (db.select(db.sales)
              ..where((s) => s.clinicId.equals(activeClinicId))
              ..orderBy([(s) => OrderingTerm.desc(s.date)]))
            .get();

    return AnimalProfile(
      animal: animal,
      owner: owner,
      visits: visits,
      vaccinations: vaccinations,
      appointments: appointments,
      sales: sales,
    );
  }

  Future<DashboardStats> dashboardStats() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startOfMonth = DateTime(now.year, now.month);

    final animalsCount =
        await (db.select(db.animals)..where(
              (a) =>
                  a.clinicId.equals(activeClinicId) &
                  a.status.equals(AnimalStatuses.active),
            ))
            .get()
            .then((v) => v.length);
    final todaysVisits =
        await (db.select(db.visits)..where(
              (v) =>
                  v.clinicId.equals(activeClinicId) &
                  v.visitDate.isBiggerOrEqualValue(startOfDay) &
                  v.visitDate.isSmallerThanValue(endOfDay),
            ))
            .get();
    final appointmentsToday =
        await (db.select(db.appointments)..where(
              (a) =>
                  a.clinicId.equals(activeClinicId) &
                  a.appointmentDate.isBiggerOrEqualValue(startOfDay) &
                  a.appointmentDate.isSmallerThanValue(endOfDay),
            ))
            .get();
    final vaccinationsDue =
        await (db.select(db.vaccinations)..where(
              (v) =>
                  v.clinicId.equals(activeClinicId) &
                  v.nextDueDate.isSmallerOrEqualValue(
                    now.add(const Duration(days: 14)),
                  ),
            ))
            .get();
    final inventory = await (db.select(
      db.inventoryItems,
    )..where((i) => i.clinicId.equals(activeClinicId))).get();
    final sales =
        await (db.select(db.sales)..where(
              (s) =>
                  s.clinicId.equals(activeClinicId) &
                  s.date.isBiggerOrEqualValue(startOfMonth),
            ))
            .get();
    final recentVisits =
        await (db.select(db.visits)
              ..where((v) => v.clinicId.equals(activeClinicId))
              ..orderBy([(v) => OrderingTerm.desc(v.visitDate)])
              ..limit(6))
            .get();
    final unreadNotifications =
        await (db.select(db.notifications)..where(
              (n) => n.clinicId.equals(activeClinicId) & n.isRead.equals(false),
            ))
            .get();

    return DashboardStats(
      totalAnimals: animalsCount,
      todaysConsultations: todaysVisits.length,
      appointmentsToday: appointmentsToday.length,
      vaccinationsDue: vaccinationsDue.length,
      lowStock: inventory
          .where((item) => item.quantity <= item.minimumQuantity)
          .length,
      expiredDrugs: inventory
          .where((item) => item.expiryDate?.isBefore(now) ?? false)
          .length,
      monthlyRevenue: sales.fold<double>(
        0,
        (total, sale) => total + (sale.price * sale.quantity),
      ),
      recentVisits: recentVisits,
      unreadNotifications: unreadNotifications.length,
    );
  }

  Future<String> nextHospitalNumber() async {
    final year = DateTime.now().year;
    final count =
        await (db.select(db.animals)
              ..where((a) => a.clinicId.equals(activeClinicId)))
            .get()
            .then((v) => v.length + 1);
    return 'ZEV-$year-${count.toString().padLeft(5, '0')}';
  }

  Future<int> saveOwner(OwnersCompanion owner) async {
    await _requireActiveFeature(AveraFeature.patientRecords);
    return db.into(db.owners).insert(owner);
  }

  Future<int> saveAnimal(AnimalsCompanion animal) async {
    await _requireActiveFeature(AveraFeature.patientRecords);
    if ((animal.weight.present && (animal.weight.value ?? 0) < 0) ||
        !animal.ownerId.present) {
      throw ArgumentError('Animal requires an owner and a valid weight.');
    }
    final duplicate =
        await (db.select(db.animals)..where(
              (a) =>
                  a.hospitalNumber.equals(animal.hospitalNumber.value) &
                  a.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (duplicate != null) {
      throw StateError('Hospital number already exists.');
    }
    return db.into(db.animals).insert(animal);
  }

  Future<String> cacheAnimalPhoto(String sourcePath) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'animal_photos'));
    if (!await directory.exists()) await directory.create(recursive: true);
    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final destination = p.join(directory.path, '${_uuid.v4()}$extension');
    return (await File(sourcePath).copy(destination)).path;
  }

  Future<void> updateAnimalPhoto({
    required int animalId,
    required String? photoPath,
    required UserSession session,
  }) async {
    if (!session.can('Edit Animal')) {
      throw StateError('You do not have permission to edit patient details.');
    }
    await (db.update(db.animals)..where(
          (a) => a.id.equals(animalId) & a.clinicId.equals(activeClinicId),
        ))
        .write(AnimalsCompanion(photo: Value(photoPath)));
  }

  Future<void> updateAnimalStatus({
    required int animalId,
    required String newStatus,
    required UserSession session,
    String? notes,
  }) async {
    if (!session.can('Manage Animal Status')) {
      throw StateError('You do not have permission to manage animal status.');
    }
    final animal =
        await (db.select(db.animals)..where(
              (a) => a.id.equals(animalId) & a.clinicId.equals(activeClinicId),
            ))
            .getSingle();
    final previousStatus = animal.status;
    if (previousStatus == newStatus) return;
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.animals)..where((a) => a.id.equals(animalId))).write(
        AnimalsCompanion(
          status: Value(newStatus),
          statusUpdatedAt: Value(now),
          statusUpdatedBy: Value(session.user.userId),
        ),
      );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(activeClinicId),
              userId: Value(session.user.userId),
              action: 'animal_status_changed',
              entityType: const Value('Animal'),
              entityId: Value(animalId.toString()),
              details: Value(
                'Animal: ${animal.animalName}; Previous Status: $previousStatus; New Status: $newStatus; User: ${session.user.fullName}; Notes: ${notes ?? '-'}; Device: local',
              ),
              createdAt: now,
            ),
          );
    });
  }

  Future<void> restoreAnimal({
    required int animalId,
    required UserSession session,
  }) {
    return updateAnimalStatus(
      animalId: animalId,
      newStatus: AnimalStatuses.active,
      session: session,
      notes: 'Restored from archived animals.',
    );
  }

  Future<Visit?> getVisit(int visitId) {
    return (db.select(db.visits)..where(
          (visit) =>
              visit.id.equals(visitId) & visit.clinicId.equals(activeClinicId),
        ))
        .getSingleOrNull();
  }

  Future<int> saveVisit({
    required VisitsCompanion visit,
    required UserSession session,
  }) async {
    if (!session.can(Permissions.consultationsCreate)) {
      throw StateError('You do not have permission to create consultations.');
    }
    await _requireActiveFeature(AveraFeature.consultations);
    final visitId = await db
        .into(db.visits)
        .insert(visit.copyWith(clinicId: Value(activeClinicId)));
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: Value(activeClinicId),
            userId: Value(session.user.userId),
            action: 'consultation_created',
            entityType: const Value('Consultation'),
            entityId: Value(visitId.toString()),
            details: const Value('Consultation created locally.'),
            createdAt: DateTime.now(),
          ),
        );
    return visitId;
  }

  Future<void> updateVisit({
    required int visitId,
    required VisitsCompanion visit,
    required UserSession session,
  }) async {
    if (!session.can(Permissions.consultationsEdit)) {
      throw StateError('You do not have permission to edit consultations.');
    }
    await _requireActiveFeature(AveraFeature.consultations);
    final updated =
        await (db.update(db.visits)..where(
              (record) =>
                  record.id.equals(visitId) &
                  record.clinicId.equals(activeClinicId),
            ))
            .write(visit.copyWith(clinicId: const Value.absent()));
    if (updated == 0) {
      throw StateError('Consultation record was not found in this clinic.');
    }
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: Value(activeClinicId),
            userId: Value(session.user.userId),
            action: 'consultation_updated',
            entityType: const Value('Consultation'),
            entityId: Value(visitId.toString()),
            details: const Value('Consultation updated locally.'),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<int> saveInventoryItem(InventoryItemsCompanion item) async {
    await _requireActiveFeature(AveraFeature.inventory);
    return db.into(db.inventoryItems).insert(item);
  }

  Future<void> deleteInventoryItem(int id) async {
    await _requireActiveFeature(AveraFeature.inventory);
    await (db.delete(db.inventoryItems)..where((i) => i.id.equals(id))).go();
  }

  Future<int> recordSale({
    required int drugId,
    required int quantity,
    required double price,
    String? customer,
  }) async {
    await _requireActiveFeature(AveraFeature.billing);
    final item =
        await (db.select(db.inventoryItems)..where(
              (i) => i.id.equals(drugId) & i.clinicId.equals(activeClinicId),
            ))
            .getSingle();
    if (quantity <= 0 || item.quantity < quantity) {
      throw StateError('Quantity is invalid or exceeds stock.');
    }
    return db.transaction(() async {
      await (db.update(
        db.inventoryItems,
      )..where((i) => i.id.equals(drugId))).write(
        InventoryItemsCompanion(quantity: Value(item.quantity - quantity)),
      );
      return db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              drugId: drugId,
              clinicId: Value(activeClinicId),
              quantity: quantity,
              price: price,
              date: DateTime.now(),
              customer: Value(customer),
            ),
          );
    });
  }

  Future<void> seedSampleData() async {
    await bootstrapClinicWorkspace();
    final hasAnimals =
        await (db.select(db.animals)
              ..where((a) => a.clinicId.equals(activeClinicId)))
            .get()
            .then((v) => v.isNotEmpty);
    if (hasAnimals) return;

    final species = ['Dog', 'Cat', 'Goat', 'Rabbit', 'Parrot'];
    final names = [
      'Bella',
      'Max',
      'Luna',
      'Charlie',
      'Coco',
      'Rocky',
      'Milo',
      'Nala',
      'Daisy',
      'Oscar',
      'Ruby',
      'Simba',
      'Leo',
      'Molly',
      'Jack',
      'Zara',
      'Toby',
      'Kiki',
      'Rex',
      'Pepper',
    ];

    await db.transaction(() async {
      for (var i = 0; i < names.length; i++) {
        final ownerId = await db
            .into(db.owners)
            .insert(
              OwnersCompanion.insert(
                clinicId: const Value(defaultClinicId),
                fullName:
                    'Owner ${i + 1} ${['Adams', 'Bello', 'Chen', 'Diaz'][i % 4]}',
                phone: '080${(10000000 + i * 27183).toString()}',
                email: Value('owner${i + 1}@example.com'),
                address: Value('${12 + i} Wellness Street'),
                city: const Value('Lagos'),
                state: const Value('Lagos'),
                country: const Value('Nigeria'),
                occupation: Value(
                  ['Teacher', 'Engineer', 'Trader', 'Doctor'][i % 4],
                ),
              ),
            );
        final animalId = await db
            .into(db.animals)
            .insert(
              AnimalsCompanion.insert(
                clinicId: const Value(defaultClinicId),
                hospitalNumber:
                    'ZEV-${DateTime.now().year}-${(i + 1).toString().padLeft(5, '0')}',
                animalName: names[i],
                species: species[i % species.length],
                breed: Value(
                  ['Mixed', 'Persian', 'Boer', 'Dutch', 'African Grey'][i % 5],
                ),
                sex: Value(i.isEven ? 'Female' : 'Male'),
                age: Value(1 + (i % 9)),
                dateOfBirth: Value(
                  DateTime.now().subtract(Duration(days: 365 * (1 + (i % 9)))),
                ),
                weight: Value(3.5 + i),
                color: Value(['Brown', 'Black', 'White', 'Grey'][i % 4]),
                microchipNumber: Value(
                  _uuid.v4().substring(0, 8).toUpperCase(),
                ),
                ownerId: ownerId,
                dateRegistered: DateTime.now().subtract(Duration(days: i * 3)),
                notes: const Value(
                  'Sample patient generated for clinic testing.',
                ),
              ),
            );
        await db
            .into(db.visits)
            .insert(
              VisitsCompanion.insert(
                clinicId: const Value(defaultClinicId),
                animalId: animalId,
                visitDate: DateTime.now().subtract(Duration(days: i)),
                chiefComplaint: Value(
                  ['Vomiting', 'Lameness', 'Routine check', 'Cough'][i % 4],
                ),
                history: const Value(
                  'Stable appetite and normal activity reported.',
                ),
                physicalExamination: const Value(
                  'Bright, alert, responsive. No emergency signs.',
                ),
                temperature: Value(38.2 + (i % 4) / 10),
                pulse: Value(82 + i),
                respiration: Value(22 + (i % 5)),
                diagnosis: Value(
                  [
                    'Gastroenteritis',
                    'Soft tissue strain',
                    'Wellness',
                    'URI',
                  ][i % 4],
                ),
                treatment: const Value('Supportive care and monitoring.'),
                prescription: const Value('Medication dispensed as indicated.'),
                veterinarian: const Value('Dr. Amina Okafor'),
              ),
            );
        await db
            .into(db.vaccinations)
            .insert(
              VaccinationsCompanion.insert(
                clinicId: const Value(defaultClinicId),
                animalId: animalId,
                vaccine: ['Rabies', 'DHPP', 'FVRCP'][i % 3],
                batchNumber: Value('VAC-${1000 + i}'),
                manufacturer: const Value('VetBio'),
                dateGiven: DateTime.now().subtract(Duration(days: 40 + i)),
                nextDueDate: Value(DateTime.now().add(Duration(days: 20 + i))),
                administeredBy: const Value('Nurse Ada'),
                veterinarian: const Value('Dr. Amina Okafor'),
                certificateNumber: Value(
                  'CERT-${DateTime.now().year}-${(i + 1).toString().padLeft(5, '0')}',
                ),
                route: const Value('Subcutaneous'),
                dose: const Value('1 ml'),
                injectionSite: const Value('Left shoulder'),
                status: const Value('Completed'),
              ),
            );
        await db
            .into(db.appointments)
            .insert(
              AppointmentsCompanion.insert(
                clinicId: const Value(defaultClinicId),
                animalId: animalId,
                appointmentDate: DateTime.now().add(Duration(days: i % 5)),
                purpose: ['Follow up', 'Vaccination', 'Deworming'][i % 3],
              ),
            );
      }

      for (var i = 0; i < 16; i++) {
        await db
            .into(db.inventoryItems)
            .insert(
              InventoryItemsCompanion.insert(
                clinicId: const Value(defaultClinicId),
                drugName: 'Vet Item ${i + 1}',
                category: [
                  'Drugs',
                  'Vaccines',
                  'Consumables',
                  'Equipment',
                ][i % 4],
                manufacturer: const Value('AVERA Supply'),
                batchNumber: Value('B-${2000 + i}'),
                expiryDate: Value(
                  DateTime.now().add(Duration(days: i.isEven ? 90 : -10)),
                ),
                quantity: Value(3 + i * 2),
                minimumQuantity: const Value(8),
                buyingPrice: Value(800 + i * 120),
                sellingPrice: Value(1200 + i * 180),
                supplier: const Value('Prime Veterinary Suppliers'),
                location: Value('Shelf ${String.fromCharCode(65 + (i % 4))}'),
              ),
            );
      }
    });
    await _generateNotifications(activeClinicId);
  }

  Future<void> _generateNotifications(String clinicId) async {
    final existing = await (db.select(
      db.notifications,
    )..where((n) => n.clinicId.equals(clinicId))).get();
    if (existing.isNotEmpty) return;

    final now = DateTime.now();
    final dueVaccines =
        await (db.select(db.vaccinations)..where(
              (v) =>
                  v.clinicId.equals(clinicId) &
                  v.nextDueDate.isSmallerOrEqualValue(
                    now.add(const Duration(days: 14)),
                  ),
            ))
            .get();
    for (final vaccine in dueVaccines.take(12)) {
      await db
          .into(db.notifications)
          .insert(
            NotificationsCompanion.insert(
              clinicId: Value(clinicId),
              type: 'Vaccination Due',
              title: '${vaccine.vaccine} due',
              message: 'Vaccination reminder is due or upcoming.',
              animalId: Value(vaccine.animalId),
              dueDate: Value(vaccine.nextDueDate),
              createdAt: DateTime.now(),
            ),
          );
    }
  }

  Future<File> exportDatabaseBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    final source = File(p.join(dir.path, 'zevora.sqlite'));
    final backupDir = await getDownloadsDirectory() ?? dir;
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final target = File(p.join(backupDir.path, 'zevora_backup_$stamp.sqlite'));
    return source.copy(target.path);
  }
}

class _ProtocolSeed {
  const _ProtocolSeed(
    this.species,
    this.vaccine,
    this.diseases,
    this.age,
    this.ageWeeks,
    this.dose,
    this.route,
    this.storage,
    this.booster,
  );

  final String species;
  final String vaccine;
  final String diseases;
  final String age;
  final int ageWeeks;
  final String dose;
  final String route;
  final String storage;
  final String booster;
}
