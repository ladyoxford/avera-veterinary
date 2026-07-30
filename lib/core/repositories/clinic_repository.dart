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
import '../models/animal_catalogue.dart';
import '../models/alert_destination.dart';
import '../models/inventory_catalog.dart';
import '../models/vaccine_catalogue.dart';
import '../remote/auth_remote_data_source.dart';
import '../security/access_control.dart';
import '../remote/api_client.dart';
import '../services/feature_gate_service.dart';
import '../services/hospital_numbering.dart';
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
    required this.recentActivity,
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
  final List<ClinicActivityTimelineEvent> recentActivity;
  final int unreadNotifications;
}

class ClinicActivityTimelineEvent {
  const ClinicActivityTimelineEvent({
    required this.id,
    required this.clinicId,
    required this.type,
    required this.title,
    required this.description,
    required this.occurredAt,
    this.performedByUserId,
    this.relatedEntityType,
    this.relatedEntityId,
    this.patientId,
    this.module,
    this.metadata,
  });

  final String id;
  final String clinicId;
  final String type;
  final String title;
  final String description;
  final DateTime occurredAt;
  final String? performedByUserId;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final int? patientId;
  final String? module;
  final String? metadata;
}

class AppointmentRescheduleRecord {
  const AppointmentRescheduleRecord({
    required this.previousDate,
    required this.newDate,
    required this.changedAt,
    this.changedByName,
    this.reason,
  });

  final DateTime previousDate;
  final DateTime newDate;
  final DateTime changedAt;
  final String? changedByName;
  final String? reason;
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

class ClinicOperationRecord {
  const ClinicOperationRecord({
    required this.operation,
    required this.animal,
    required this.owner,
  });

  final ClinicalOperationRecord operation;
  final Animal animal;
  final Owner owner;
}

class ClinicalOperationTypes {
  const ClinicalOperationTypes._();

  static const surgery = 'surgery';
  static const prescription = 'prescription';
  static const imaging = 'imaging';
  static const document = 'document';
  static const treatment = 'treatment';
}

class AppointmentStatuses {
  const AppointmentStatuses._();

  static const pending = 'Pending';
  static const confirmed = 'Confirmed';
  static const completed = 'Completed';
  static const cancelled = 'Cancelled';
  static const noShow = 'No Show';

  static String normalize(String status) =>
      status == 'Scheduled' ? confirmed : status;
}

class AppointmentDetail {
  const AppointmentDetail({
    required this.appointment,
    required this.animal,
    required this.owner,
    required this.reminders,
    this.assignedStaff,
  });

  final Appointment appointment;
  final Animal animal;
  final Owner owner;
  final AppUser? assignedStaff;
  final List<AppointmentReminder> reminders;
}

class FarmDashboardData {
  const FarmDashboardData({
    required this.farm,
    required this.units,
    required this.dailyRecords,
  });

  final Farm farm;
  final List<FarmUnit> units;
  final List<FarmDailyRecord> dailyRecords;

  int get currentPopulation => units.fold(
    0,
    (total, unit) =>
        total + unit.maleCount + unit.femaleCount + unit.unknownCount,
  );

  Map<String, int> get populationBySpecies {
    final result = <String, int>{};
    for (final unit in units) {
      final speciesId = unit.speciesId ?? 'unassigned';
      result.update(
        speciesId,
        (value) =>
            value + unit.maleCount + unit.femaleCount + unit.unknownCount,
        ifAbsent: () => unit.maleCount + unit.femaleCount + unit.unknownCount,
      );
    }
    return result;
  }
}

class FarmSpeciesMovementInput {
  const FarmSpeciesMovementInput({
    required this.speciesId,
    required this.openingPopulation,
    this.births = 0,
    this.purchases = 0,
    this.transfersIn = 0,
    this.mortality = 0,
    this.sales = 0,
    this.transfersOut = 0,
  });

  final String speciesId;
  final int openingPopulation;
  final int births;
  final int purchases;
  final int transfersIn;
  final int mortality;
  final int sales;
  final int transfersOut;

  int get closingPopulation =>
      openingPopulation +
      births +
      purchases +
      transfersIn -
      mortality -
      sales -
      transfersOut;

  Map<String, Object> toJson() => {
    'speciesId': speciesId,
    'openingPopulation': openingPopulation,
    'births': births,
    'purchases': purchases,
    'transfersIn': transfersIn,
    'mortality': mortality,
    'sales': sales,
    'transfersOut': transfersOut,
    'closingPopulation': closingPopulation,
  };
}

class FarmDailyRecordDetail {
  const FarmDailyRecordDetail({
    required this.farm,
    required this.record,
    required this.units,
    required this.speciesMovements,
    required this.mortalityRecords,
    required this.feedRecords,
    required this.events,
    required this.reproductionRecords,
    required this.healthRecords,
  });

  final Farm farm;
  final FarmDailyRecord record;
  final List<FarmUnit> units;
  final List<FarmSpeciesPopulationMovement> speciesMovements;
  final List<FarmMortalityRecord> mortalityRecords;
  final List<FarmFeedRecord> feedRecords;
  final List<FarmEvent> events;
  final List<FarmReproductionRecord> reproductionRecords;
  final List<FarmHealthRecord> healthRecords;
}

class InvoiceProductDraft {
  const InvoiceProductDraft({
    required this.inventoryItemId,
    required this.quantity,
  });

  final int inventoryItemId;
  final int quantity;
}

class InvoiceServiceDraft {
  const InvoiceServiceDraft({required this.description, required this.amount});

  final String description;
  final double amount;
}

class InvoiceDetail {
  const InvoiceDetail({
    required this.invoice,
    required this.products,
    required this.services,
    this.payments = const [],
  });

  final Invoice invoice;
  final List<InvoiceProductLine> products;
  final List<InvoiceServiceLine> services;
  final List<InvoicePayment> payments;
}

class BillingHistoryEntry {
  const BillingHistoryEntry({
    required this.invoice,
    required this.animal,
    required this.owner,
    required this.processedBy,
  });

  final Invoice invoice;
  final Animal animal;
  final Owner owner;
  final AppUser? processedBy;
}

class ClinicalOperationDetail {
  const ClinicalOperationDetail({
    required this.record,
    required this.items,
    required this.actions,
    required this.documents,
  });

  final ClinicOperationRecord record;
  final List<ClinicalOperationItem> items;
  final List<ClinicalOperationAction> actions;
  final List<ClinicalDocumentVersion> documents;
}

class ClinicalMedicationDraft {
  const ClinicalMedicationDraft({
    required this.name,
    this.inventoryItemId,
    this.strength,
    this.quantity,
    this.unit,
    this.dose,
    this.doseUnit,
    this.route,
    this.frequency,
    this.duration,
    this.instructions,
    this.isHighRisk = false,
  });

  final String name;
  final int? inventoryItemId;
  final String? strength;
  final double? quantity;
  final String? unit;
  final String? dose;
  final String? doseUnit;
  final String? route;
  final String? frequency;
  final String? duration;
  final String? instructions;
  final bool isHighRisk;
}

class UserSession {
  const UserSession({
    required this.user,
    required this.clinic,
    this.backendPermissions,
    this.rolePolicyPermissions,
  });

  final AppUser user;
  final Clinic clinic;
  final Set<String>? backendPermissions;
  final Set<String>? rolePolicyPermissions;

  bool get isPlatformOwner => user.accountType == AccountTypes.platformOwner;
  bool get isPlatformAdministrator =>
      user.accountType == AccountTypes.platformAdministrator;
  bool get isPlatformAccount => isPlatformOwner || isPlatformAdministrator;
  bool get isClinicAccount => !isPlatformAccount;
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
    final defaults =
        rolePolicyPermissions ?? rolePermissions[user.role] ?? const <String>{};
    if (overrides.contains(permission) || defaults.contains(permission)) {
      return true;
    }
    return _legacyPermissionMatch(permission, overrides, defaults);
  }

  Set<String> get effectivePermissions =>
      backendPermissions ??
      {
        ...rolePolicyPermissions ??
            rolePermissions[user.role] ??
            const <String>{},
        ..._permissionsFromJson(user.permissions),
      };

  bool canManagePlatform(String permission) =>
      isPlatformOwner || (isPlatformAdministrator && can(permission));
}

class ClinicRoleAccess {
  const ClinicRoleAccess({
    required this.name,
    required this.description,
    required this.permissions,
    required this.isCustom,
    required this.isArchived,
  });

  final String name;
  final String description;
  final Set<String> permissions;
  final bool isCustom;
  final bool isArchived;
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
  ClinicRepository(this.db, {AppClock clock = const LocalAppClock()})
    : _clock = clock;

  final AppDatabase db;
  final AppClock _clock;
  final _uuid = const Uuid();
  String _activeClinicId = defaultClinicId;
  String get activeClinicId => _activeClinicId;

  /// The production API has no patient-number allocator yet. Until it does,
  /// the single local Drift database is the authority for local registrations.
  static const hospitalNumberAuthorityMode =
      HospitalNumberAuthorityMode.localOnly;

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
            patientNumberPrefix: const Value('AVR'),
            patientNumberPrefixReviewed: const Value(false),
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
    if (existingAdmins.isNotEmpty) {
      // Keep the existing identity, password, permissions, and clinic records.
      // Only retire the former ambiguous display name.
      await (db.update(db.appUsers)..where(
            (u) =>
                u.clinicId.equals(clinicId) &
                u.email.lower().equals('admin@avera.test') &
                u.fullName.equals('System Administrator'),
          ))
          .write(
            const AppUsersCompanion(fullName: Value('Clinic Administrator')),
          );
      return;
    }
    await db
        .into(db.appUsers)
        .insert(
          AppUsersCompanion.insert(
            userId: _uuid.v4(),
            clinicId: clinicId,
            fullName: 'Clinic Administrator',
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
    // The local browser and each installed Android build have independent
    // Drift databases. Migrate only this reserved development identity in
    // place so the documented local credentials remain consistent everywhere.
    final developmentOwners =
        await (db.select(db.appUsers)..where(
              (u) =>
                  u.email.lower().equals('owner@avera.test') |
                  u.email.lower().equals('owner@avera.local'),
            ))
            .get();
    if (developmentOwners.isNotEmpty) {
      final primary = developmentOwners.firstWhere(
        (user) => user.email.toLowerCase() == 'owner@avera.test',
        orElse: () => developmentOwners.first,
      );
      final now = DateTime.now();
      await db.transaction(() async {
        await (db.update(
          db.appUsers,
        )..where((u) => u.userId.equals(primary.userId))).write(
          AppUsersCompanion(
            clinicId: const Value(platformClinicId),
            fullName: const Value('Platform Owner'),
            username: const Value('platform.owner'),
            email: const Value('owner@avera.test'),
            passwordHash: Value(_hashPassword('change-me-locally')),
            role: const Value('Platform Owner'),
            accountType: const Value(AccountTypes.platformOwner),
            accountStatus: const Value(AccountStatuses.active),
            permissions: Value(jsonEncode(allPermissions.toList())),
            updatedAt: Value(now),
          ),
        );
        for (final duplicate in developmentOwners) {
          if (duplicate.userId == primary.userId) continue;
          // Preserve the legacy row and its audit references, but prevent it
          // from remaining a second active Platform Owner identity.
          await (db.update(
            db.appUsers,
          )..where((u) => u.userId.equals(duplicate.userId))).write(
            AppUsersCompanion(
              username: Value('archived.platform.${duplicate.userId}'),
              email: Value(
                'archived.platform.${duplicate.userId}@local.invalid',
              ),
              role: const Value('Archived Development Account'),
              accountType: const Value(AccountTypes.clinicStaff),
              accountStatus: const Value(AccountStatuses.deactivated),
              permissions: const Value('[]'),
              updatedAt: Value(now),
            ),
          );
        }
      });
      return;
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
    final currentUser = user.copyWith(lastLogin: Value(DateTime.now()));
    return UserSession(
      user: currentUser,
      clinic: clinic,
      rolePolicyPermissions: await _rolePolicyPermissionsFor(currentUser),
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
    return UserSession(
      user: user,
      clinic: clinic,
      rolePolicyPermissions: await _rolePolicyPermissionsFor(user),
    );
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

  Stream<List<AppUser>> watchClinicUsers(
    String clinicId, {
    String? membershipStatus,
  }) {
    final query = db.select(db.appUsers)
      ..where(
        (user) =>
            user.clinicId.equals(clinicId) &
            user.accountType.equals(AccountTypes.platformOwner).not() &
            user.accountType.equals(AccountTypes.platformAdministrator).not(),
      );
    if (membershipStatus == null) {
      query.where(
        (user) =>
            user.membershipStatus.equals(ClinicMembershipStatuses.active) |
            user.membershipStatus.equals(ClinicMembershipStatuses.suspended),
      );
    } else {
      query.where((user) => user.membershipStatus.equals(membershipStatus));
    }
    return (query..orderBy([(user) => OrderingTerm.asc(user.fullName)]))
        .watch();
  }

  /// Role templates are scoped to one clinic. Built-in roles retain their
  /// shipped defaults until a clinic administrator explicitly customizes one.
  Stream<List<ClinicRoleAccess>> watchClinicRoles(UserSession session) {
    _requireRolePolicyAccess(session);
    return (db.select(db.clinicRolePolicies)
          ..where((row) => row.clinicId.equals(session.clinic.clinicId))
          ..orderBy([(row) => OrderingTerm.asc(row.roleName)]))
        .watch()
        .map((rows) => _mergeClinicRoles(rows));
  }

  Stream<List<AuditLog>> watchClinicAuditLogs(UserSession session) {
    if (!session.can(Permissions.auditLogsView)) {
      return Stream<List<AuditLog>>.error(
        StateError(
          'You do not have permission to access this administration area.',
        ),
      );
    }
    return (db.select(db.auditLogs)
          ..where((log) => log.clinicId.equals(session.clinic.clinicId))
          ..orderBy([(log) => OrderingTerm.desc(log.createdAt)]))
        .watch();
  }

  Future<void> recordClinicSecurityEvent({
    required UserSession actingSession,
    required String action,
    required String details,
  }) async {
    _requireClinicAdministrator(actingSession);
    await _writeClinicAudit(
      actingSession: actingSession,
      action: action,
      entityType: 'security',
      entityId: actingSession.user.userId,
      details: {'message': details},
    );
  }

  Future<void> saveClinicRolePermissions({
    required UserSession actingSession,
    required String roleName,
    required Set<String> permissions,
  }) async {
    _requireRolePolicyAccess(actingSession);
    final existing = await _clinicRolePolicy(
      actingSession.clinic.clinicId,
      roleName,
    );
    if (!rolePermissions.containsKey(roleName) && existing == null) {
      throw StateError('This clinic role is unavailable.');
    }
    final allowed = permissions.intersection(allPermissions);
    const essentialAdministratorPermissions = <String>{
      Permissions.usersView,
      Permissions.usersEdit,
      Permissions.usersSuspend,
      Permissions.usersAssignRoles,
      Permissions.usersAssignPermissions,
      Permissions.clinicSettingsEdit,
      Permissions.auditLogsView,
    };
    if (roleName == 'Clinic Administrator' &&
        !allowed.containsAll(essentialAdministratorPermissions)) {
      throw StateError(
        'Clinic Administrator must retain essential clinic administration access.',
      );
    }
    final previous = existing == null
        ? (rolePermissions[roleName] ?? const <String>{})
        : _permissionsFromJson(existing.permissions);
    final now = DateTime.now();
    await db.transaction(() async {
      await db
          .into(db.clinicRolePolicies)
          .insertOnConflictUpdate(
            ClinicRolePoliciesCompanion.insert(
              id: existing?.id ?? _uuid.v4(),
              clinicId: actingSession.clinic.clinicId,
              roleName: roleName,
              description: Value(existing?.description),
              permissions: Value(jsonEncode(allowed.toList()..sort())),
              isCustom: Value(existing?.isCustom ?? false),
              isArchived: Value(existing?.isArchived ?? false),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _writeClinicAudit(
        actingSession: actingSession,
        action: 'role.permissions_updated',
        entityType: 'clinic_role',
        entityId: roleName,
        details: {
          'roleName': roleName,
          'previousPermissions': previous.toList()..sort(),
          'newPermissions': allowed.toList()..sort(),
        },
      );
    });
  }

  Future<void> createClinicCustomRole({
    required UserSession actingSession,
    required String roleName,
    required String description,
    required Set<String> permissions,
  }) async {
    _requireRolePolicyAccess(actingSession);
    final normalized = roleName.trim();
    if (normalized.length < 2 || normalized.length > 80) {
      throw StateError('Enter a role name between 2 and 80 characters.');
    }
    if (rolePermissions.containsKey(normalized) ||
        await _clinicRolePolicy(actingSession.clinic.clinicId, normalized) !=
            null) {
      throw StateError('A role with this name already exists in this clinic.');
    }
    final now = DateTime.now();
    final allowed = permissions.intersection(allPermissions);
    await db.transaction(() async {
      await db
          .into(db.clinicRolePolicies)
          .insert(
            ClinicRolePoliciesCompanion.insert(
              id: _uuid.v4(),
              clinicId: actingSession.clinic.clinicId,
              roleName: normalized,
              description: Value(
                description.trim().isEmpty ? null : description.trim(),
              ),
              permissions: Value(jsonEncode(allowed.toList()..sort())),
              isCustom: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _writeClinicAudit(
        actingSession: actingSession,
        action: 'role.created',
        entityType: 'clinic_role',
        entityId: normalized,
        details: {'roleName': normalized, 'permissions': allowed.toList()},
      );
    });
  }

  Future<void> archiveClinicRole({
    required UserSession actingSession,
    required String roleName,
  }) async {
    _requireRolePolicyAccess(actingSession);
    final role = await _clinicRolePolicy(
      actingSession.clinic.clinicId,
      roleName,
    );
    if (role == null || !role.isCustom) {
      throw StateError('Only unused custom clinic roles can be archived.');
    }
    final assigned =
        await (db.select(db.appUsers)..where(
              (user) =>
                  user.clinicId.equals(actingSession.clinic.clinicId) &
                  user.role.equals(roleName),
            ))
            .get();
    if (assigned.isNotEmpty) {
      throw StateError('Reassign staff before archiving this custom role.');
    }
    await (db.update(
      db.clinicRolePolicies,
    )..where((row) => row.id.equals(role.id))).write(
      ClinicRolePoliciesCompanion(
        isArchived: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _writeClinicAudit(
      actingSession: actingSession,
      action: 'role.archived',
      entityType: 'clinic_role',
      entityId: roleName,
      details: {'roleName': roleName},
    );
  }

  Future<Set<String>?> _rolePolicyPermissionsFor(AppUser user) async {
    final policy = await _clinicRolePolicy(user.clinicId, user.role);
    if (policy == null || policy.isArchived) return null;
    return _permissionsFromJson(policy.permissions);
  }

  Future<ClinicRolePolicy?> _clinicRolePolicy(
    String clinicId,
    String roleName,
  ) =>
      (db.select(db.clinicRolePolicies)..where(
            (row) =>
                row.clinicId.equals(clinicId) & row.roleName.equals(roleName),
          ))
          .getSingleOrNull();

  List<ClinicRoleAccess> _mergeClinicRoles(List<ClinicRolePolicy> policies) {
    final byName = {for (final policy in policies) policy.roleName: policy};
    final names = <String>{
      ...clinicRoleDescriptions.keys,
      ...policies
          .where((policy) => policy.isCustom)
          .map((policy) => policy.roleName),
    }.toList()..sort();
    return names
        .map((name) {
          final policy = byName[name];
          return ClinicRoleAccess(
            name: name,
            description:
                policy?.description ??
                clinicRoleDescriptions[name] ??
                'Custom clinic role.',
            permissions: policy == null
                ? rolePermissions[name] ?? const <String>{}
                : _permissionsFromJson(policy.permissions),
            isCustom: policy?.isCustom ?? false,
            isArchived: policy?.isArchived ?? false,
          );
        })
        .toList(growable: false);
  }

  void _requireRolePolicyAccess(UserSession session) {
    _requireClinicAdministrator(session, requiresRoleAssignment: true);
    if (!session.can(Permissions.usersAssignPermissions)) {
      throw StateError('You do not have permission to manage clinic roles.');
    }
  }

  Future<void> changeClinicUserRole({
    required UserSession actingSession,
    required String targetUserId,
    required String newRole,
  }) async {
    _requireClinicAdministrator(actingSession, requiresRoleAssignment: true);
    final customRole = await _clinicRolePolicy(
      actingSession.clinic.clinicId,
      newRole,
    );
    if (!rolePermissions.containsKey(newRole) &&
        newRole != 'Custom Role' &&
        (customRole == null || customRole.isArchived)) {
      throw StateError('The selected clinic role is unavailable.');
    }
    await db.transaction(() async {
      final target = await _clinicUserForManagement(
        actingSession: actingSession,
        targetUserId: targetUserId,
      );
      if (target.role == newRole) return;
      await _protectLastClinicAdministrator(
        actingSession: actingSession,
        target: target,
        removingAdministrator:
            target.role == 'Clinic Administrator' &&
            newRole != 'Clinic Administrator',
      );
      await (db.update(
        db.appUsers,
      )..where((user) => user.userId.equals(target.userId))).write(
        AppUsersCompanion(
          role: Value(newRole),
          accountType: Value(
            newRole == 'Clinic Administrator'
                ? AccountTypes.clinicAdministrator
                : AccountTypes.clinicStaff,
          ),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _writeStaffAudit(
        actingSession: actingSession,
        target: target,
        action: 'staff.role_changed',
        details: {
          'previousRole': target.role,
          'newRole': newRole,
          'previousStatus': target.membershipStatus,
          'newStatus': target.membershipStatus,
        },
      );
    });
  }

  Future<void> updateClinicUserMembership({
    required UserSession actingSession,
    required String targetUserId,
    required String membershipStatus,
    String? removalReason,
    String? removalNote,
  }) async {
    _requireClinicAdministrator(actingSession);
    const allowed = {
      ClinicMembershipStatuses.active,
      ClinicMembershipStatuses.suspended,
      ClinicMembershipStatuses.formerStaff,
      ClinicMembershipStatuses.archived,
    };
    if (!allowed.contains(membershipStatus)) {
      throw ArgumentError.value(membershipStatus, 'membershipStatus');
    }
    await db.transaction(() async {
      final target = await _clinicUserForManagement(
        actingSession: actingSession,
        targetUserId: targetUserId,
      );
      final removesAccess = membershipStatus != ClinicMembershipStatuses.active;
      await _protectLastClinicAdministrator(
        actingSession: actingSession,
        target: target,
        removingAdministrator:
            removesAccess && target.role == 'Clinic Administrator',
      );
      final now = DateTime.now();
      final isSuspended =
          membershipStatus == ClinicMembershipStatuses.suspended;
      final isFormer = membershipStatus == ClinicMembershipStatuses.formerStaff;
      final isArchived = membershipStatus == ClinicMembershipStatuses.archived;
      await (db.update(
        db.appUsers,
      )..where((user) => user.userId.equals(target.userId))).write(
        AppUsersCompanion(
          membershipStatus: Value(membershipStatus),
          accountStatus: Value(
            membershipStatus == ClinicMembershipStatuses.active
                ? AccountStatuses.active
                : isSuspended
                ? AccountStatuses.suspended
                : AccountStatuses.deactivated,
          ),
          suspendedAt: isSuspended ? Value(now) : const Value(null),
          suspendedBy: isSuspended
              ? Value(actingSession.user.userId)
              : const Value(null),
          formerStaffAt: isFormer ? Value(now) : const Value(null),
          formerStaffBy: isFormer
              ? Value(actingSession.user.userId)
              : const Value(null),
          archivedAt: isArchived ? Value(now) : const Value(null),
          archivedBy: isArchived
              ? Value(actingSession.user.userId)
              : const Value(null),
          removalReason: isFormer ? Value(removalReason) : const Value(null),
          removalNote: isFormer ? Value(removalNote) : const Value(null),
          previousRole: removesAccess ? Value(target.role) : const Value(null),
          updatedAt: Value(now),
        ),
      );
      await _writeStaffAudit(
        actingSession: actingSession,
        target: target,
        action: switch (membershipStatus) {
          ClinicMembershipStatuses.active => 'staff.reactivated',
          ClinicMembershipStatuses.suspended => 'staff.suspended',
          ClinicMembershipStatuses.formerStaff => 'staff.marked_former',
          ClinicMembershipStatuses.archived => 'staff.archived',
          _ => 'staff.membership_changed',
        },
        details: {
          'previousRole': target.role,
          'newRole': target.role,
          'previousStatus': target.membershipStatus,
          'newStatus': membershipStatus,
          if (removalReason != null) 'reason': removalReason,
          if (removalNote != null && removalNote.trim().isNotEmpty)
            'note': removalNote.trim(),
        },
      );
    });
  }

  /// Staff history is tenant-scoped and remains available after a staff member
  /// leaves. It is intentionally sourced from the immutable audit journal.
  Future<List<AuditLog>> clinicUserHistory({
    required UserSession actingSession,
    required String targetUserId,
  }) async {
    _requireClinicAdministrator(actingSession);
    await _clinicUserForManagement(
      actingSession: actingSession,
      targetUserId: targetUserId,
    );
    return (db.select(db.auditLogs)
          ..where(
            (log) =>
                log.clinicId.equals(actingSession.clinic.clinicId) &
                log.entityType.equals('clinic_staff') &
                log.entityId.equals(targetUserId),
          )
          ..orderBy([(log) => OrderingTerm.desc(log.createdAt)]))
        .get();
  }

  /// Returns a user-facing reason when removing the identity would risk
  /// historical attribution. Deletion is deliberately exceptional; archived
  /// staff is the normal retention state.
  Future<String?> permanentClinicUserDeletionBlockReason({
    required UserSession actingSession,
    required String targetUserId,
  }) async {
    _requireClinicAdministrator(actingSession);
    final target = await _clinicUserForManagement(
      actingSession: actingSession,
      targetUserId: targetUserId,
    );
    if (target.membershipStatus != ClinicMembershipStatuses.archived) {
      return 'Archive this user before considering permanent deletion.';
    }
    if (target.role == 'Clinic Administrator') {
      return 'Clinic Administrator identities are retained for administration and audit history.';
    }
    final history =
        await (db.select(db.auditLogs)..where(
              (log) =>
                  log.clinicId.equals(actingSession.clinic.clinicId) &
                  (log.userId.equals(target.userId) |
                      log.entityId.equals(target.userId)),
            ))
            .get();
    if (history.isNotEmpty) {
      return 'This account is required for clinic audit history and cannot be permanently deleted.';
    }
    return null;
  }

  Future<void> permanentlyDeleteClinicUser({
    required UserSession actingSession,
    required String targetUserId,
  }) async {
    _requireClinicAdministrator(actingSession);
    await db.transaction(() async {
      final target = await _clinicUserForManagement(
        actingSession: actingSession,
        targetUserId: targetUserId,
      );
      final reason = await permanentClinicUserDeletionBlockReason(
        actingSession: actingSession,
        targetUserId: targetUserId,
      );
      if (reason != null) {
        await _writeStaffAudit(
          actingSession: actingSession,
          target: target,
          action: 'staff.permanent_deletion_attempted',
          details: {'blocked': true, 'reason': reason},
        );
        throw StateError(reason);
      }
      await _writeStaffAudit(
        actingSession: actingSession,
        target: target,
        action: 'staff.permanent_deletion_completed',
        details: const {'blocked': false},
      );
      await (db.delete(
        db.appUsers,
      )..where((user) => user.userId.equals(target.userId))).go();
    });
  }

  void _requireClinicAdministrator(
    UserSession session, {
    bool requiresRoleAssignment = false,
  }) {
    if (!session.isClinicAdministrator ||
        !session.can(Permissions.usersEdit) ||
        !session.can(Permissions.usersSuspend)) {
      throw StateError('Only a Clinic Administrator can manage staff access.');
    }
    if (requiresRoleAssignment && !session.can(Permissions.usersAssignRoles)) {
      throw StateError('You do not have permission to assign clinic roles.');
    }
  }

  Future<AppUser> _clinicUserForManagement({
    required UserSession actingSession,
    required String targetUserId,
  }) async {
    final target =
        await (db.select(db.appUsers)..where(
              (user) =>
                  user.userId.equals(targetUserId) &
                  user.clinicId.equals(actingSession.clinic.clinicId) &
                  user.accountType.equals(AccountTypes.platformOwner).not() &
                  user.accountType
                      .equals(AccountTypes.platformAdministrator)
                      .not(),
            ))
            .getSingleOrNull();
    if (target == null) {
      throw StateError(
        'This staff member is unavailable in the active clinic.',
      );
    }
    return target;
  }

  Future<void> _protectLastClinicAdministrator({
    required UserSession actingSession,
    required AppUser target,
    required bool removingAdministrator,
  }) async {
    if (!removingAdministrator) return;
    final activeAdmins =
        await (db.select(db.appUsers)..where(
              (user) =>
                  user.clinicId.equals(actingSession.clinic.clinicId) &
                  user.role.equals('Clinic Administrator') &
                  user.membershipStatus.equals(ClinicMembershipStatuses.active),
            ))
            .get();
    if (activeAdmins.length <= 1 &&
        activeAdmins.any((admin) => admin.userId == target.userId)) {
      await _writeStaffAudit(
        actingSession: actingSession,
        target: target,
        action: 'staff.action_blocked',
        details: const {'reason': 'last_active_clinic_administrator'},
      );
      throw StateError(
        'Assign another active Clinic Administrator before removing this user.',
      );
    }
  }

  Future<void> _writeStaffAudit({
    required UserSession actingSession,
    required AppUser target,
    required String action,
    required Map<String, Object?> details,
  }) {
    return db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: Value(actingSession.clinic.clinicId),
            userId: Value(actingSession.user.userId),
            action: action,
            entityType: const Value('clinic_staff'),
            entityId: Value(target.userId),
            details: Value(
              jsonEncode({
                'actingUserId': actingSession.user.userId,
                'actingUserName': actingSession.user.fullName,
                'targetUserId': target.userId,
                'targetUserName': target.fullName,
                'clinicId': actingSession.clinic.clinicId,
                ...details,
              }),
            ),
            createdAt: DateTime.now(),
          ),
        )
        .then((_) {});
  }

  Future<void> _writeClinicAudit({
    required UserSession actingSession,
    required String action,
    required String entityType,
    required String entityId,
    required Map<String, Object?> details,
  }) => db
      .into(db.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          clinicId: Value(actingSession.clinic.clinicId),
          userId: Value(actingSession.user.userId),
          action: action,
          entityType: Value(entityType),
          entityId: Value(entityId),
          details: Value(
            jsonEncode({
              'actingUserId': actingSession.user.userId,
              'actingUserName': actingSession.user.fullName,
              'clinicId': actingSession.clinic.clinicId,
              ...details,
            }),
          ),
          createdAt: DateTime.now(),
        ),
      )
      .then((_) {});

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
    return (db.select(db.appUsers)
          ..where(
            (user) =>
                user.accountType.equals(AccountTypes.platformOwner) |
                user.accountType.equals(AccountTypes.platformAdministrator),
          )
          ..orderBy([(user) => OrderingTerm.asc(user.fullName)]))
        .watch();
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
    if (!actingSession.isPlatformAccount ||
        !(actingSession.canManagePlatform(Permissions.clinicsApprove) ||
            actingSession.canManagePlatform(Permissions.clinicsSuspend))) {
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

  Future<void> recordPlatformSupportAccess({
    required UserSession actingSession,
    required String clinicId,
    required bool started,
  }) async {
    if (!actingSession.isPlatformAccount ||
        !actingSession.canManagePlatform(Permissions.platformSupportAccess)) {
      throw StateError(
        'You do not have permission to access clinic support mode.',
      );
    }
    if (clinicId == 'platform-control') {
      throw StateError(
        'Platform support mode is only available for clinic tenants.',
      );
    }
    final clinic = await (db.select(
      db.clinics,
    )..where((item) => item.clinicId.equals(clinicId))).getSingleOrNull();
    if (clinic == null) throw StateError('The requested clinic was not found.');
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: Value(clinicId),
            userId: Value(actingSession.user.userId),
            action: started
                ? 'platform.support_mode_started'
                : 'platform.support_mode_ended',
            entityType: const Value('Clinic'),
            entityId: Value(clinicId),
            details: Value(
              started
                  ? 'Platform support mode opened for ${clinic.clinicName}.'
                  : 'Platform support mode closed for ${clinic.clinicName}.',
            ),
            createdAt: DateTime.now(),
          ),
        );
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
    if (!actingSession.isPlatformAccount ||
        !actingSession.canManagePlatform(Permissions.subscriptionsManage)) {
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

  Stream<List<ClinicOperationRecord>> watchClinicalOperationRecords(
    String operationType,
  ) {
    final joined = db.select(db.clinicalOperationRecords).join([
      innerJoin(
        db.animals,
        db.animals.id.equalsExp(db.clinicalOperationRecords.animalId),
      ),
      innerJoin(db.owners, db.owners.id.equalsExp(db.animals.ownerId)),
    ]);
    joined.where(
      db.clinicalOperationRecords.clinicId.equals(activeClinicId) &
          db.clinicalOperationRecords.operationType.equals(operationType),
    );
    joined.orderBy([
      OrderingTerm.desc(db.clinicalOperationRecords.updatedAt),
      OrderingTerm.asc(db.animals.animalName),
    ]);
    return joined.watch().map(
      (rows) => rows
          .map(
            (row) => ClinicOperationRecord(
              operation: row.readTable(db.clinicalOperationRecords),
              animal: row.readTable(db.animals),
              owner: row.readTable(db.owners),
            ),
          )
          .toList(),
    );
  }

  /// Development records are intentionally clinic-scoped and are created only
  /// when the module has no data. They use real locally registered patients.
  Future<void> seedClinicalOperationDemoData() async {
    if (kReleaseMode) return;
    final existing = await (db.select(
      db.clinicalOperationRecords,
    )..where((row) => row.clinicId.equals(activeClinicId))).get();
    if (existing.isNotEmpty) {
      await _backfillClinicalOperationDemoDetails(existing);
      return;
    }
    final animals =
        await (db.select(db.animals)
              ..where((row) => row.clinicId.equals(activeClinicId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    if (animals.isEmpty) return;
    final visits =
        await (db.select(db.visits)
              ..where((row) => row.clinicId.equals(activeClinicId))
              ..orderBy([(row) => OrderingTerm.desc(row.visitDate)]))
            .get();
    final now = _clock.nowForClinic(await _clinicForNumbering(activeClinicId));
    const samples =
        <
          ({
            String type,
            String title,
            String description,
            String status,
            String clinician,
            int offset,
          })
        >[
          (
            type: ClinicalOperationTypes.surgery,
            title: 'Ovariohysterectomy',
            description:
                'Pre-operative assessment complete. Fast from midnight.',
            status: 'Scheduled',
            clinician: 'Dr. Amina Okafor',
            offset: 1,
          ),
          (
            type: ClinicalOperationTypes.prescription,
            title: 'Amoxicillin-clavulanate 250 mg',
            description: 'Give one tablet by mouth twice daily for 7 days.',
            status: 'Active',
            clinician: 'Dr. Amina Okafor',
            offset: 0,
          ),
          (
            type: ClinicalOperationTypes.imaging,
            title: 'Thoracic radiographs',
            description: 'Three-view study requested for persistent cough.',
            status: 'Requested',
            clinician: 'Dr. Chinedu Emmanuel',
            offset: 0,
          ),
          (
            type: ClinicalOperationTypes.document,
            title: 'Consent for anaesthesia',
            description: 'Signed owner consent attached to the clinical file.',
            status: 'Available',
            clinician: 'Clinic Administrator',
            offset: -1,
          ),
          (
            type: ClinicalOperationTypes.treatment,
            title: 'IV fluid therapy',
            description:
                'Lactated Ringer\'s solution. Reassess hydration after treatment.',
            status: 'Due',
            clinician: 'Nurse Ada',
            offset: 0,
          ),
        ];
    await db.transaction(() async {
      for (var index = 0; index < samples.length; index++) {
        final sample = samples[index];
        final animal = animals[index % animals.length];
        final visit = visits
            .where((item) => item.animalId == animal.id)
            .firstOrNull;
        final operationId = await db
            .into(db.clinicalOperationRecords)
            .insert(
              ClinicalOperationRecordsCompanion.insert(
                clinicId: activeClinicId,
                animalId: animal.id,
                visitId: Value(visit?.id),
                operationType: sample.type,
                title: sample.title,
                description: Value(sample.description),
                status: Value(sample.status),
                assignedTo: Value(sample.clinician),
                scheduledAt: Value(now.add(Duration(days: sample.offset))),
                detailsJson: Value(jsonEncode({'demo': true})),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await (db.update(
          db.clinicalOperationRecords,
        )..where((row) => row.id.equals(operationId))).write(
          ClinicalOperationRecordsCompanion(
            referenceNumber: Value(
              _clinicalReference(sample.type, now.year, operationId),
            ),
          ),
        );
      }
    });
    final created = await (db.select(
      db.clinicalOperationRecords,
    )..where((row) => row.clinicId.equals(activeClinicId))).get();
    await _backfillClinicalOperationDemoDetails(created);
  }

  Future<void> _backfillClinicalOperationDemoDetails(
    List<ClinicalOperationRecord> operations,
  ) async {
    if (kReleaseMode || operations.isEmpty) return;
    final clinic = await _clinicForNumbering(activeClinicId);
    final now = _clock.nowForClinic(clinic);
    final inventory =
        await (db.select(db.inventoryItems)
              ..where(
                (row) =>
                    row.clinicId.equals(activeClinicId) &
                    row.isArchived.equals(false) &
                    row.isSellable.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.quantity)])
              ..limit(1))
            .getSingleOrNull();
    final uploader =
        await (db.select(db.appUsers)
              ..where((row) => row.clinicId.equals(activeClinicId))
              ..limit(1))
            .getSingleOrNull();
    await db.transaction(() async {
      for (final operation in operations) {
        final existingItems =
            await (db.select(db.clinicalOperationItems)..where(
                  (row) =>
                      row.clinicId.equals(activeClinicId) &
                      row.operationId.equals(operation.id),
                ))
                .get();
        if (existingItems.isEmpty &&
            {
              ClinicalOperationTypes.prescription,
              ClinicalOperationTypes.treatment,
            }.contains(operation.operationType)) {
          await _insertClinicalOperationItem(
            operationId: operation.id,
            itemType:
                operation.operationType == ClinicalOperationTypes.prescription
                ? 'Medication'
                : 'Treatment',
            draft: ClinicalMedicationDraft(
              name: inventory?.drugName ?? operation.title,
              inventoryItemId: inventory?.id,
              strength:
                  operation.operationType == ClinicalOperationTypes.prescription
                  ? '250 mg'
                  : null,
              quantity:
                  operation.operationType == ClinicalOperationTypes.prescription
                  ? 14
                  : 1,
              unit:
                  operation.operationType == ClinicalOperationTypes.prescription
                  ? 'tablets'
                  : 'dose',
              dose:
                  operation.operationType == ClinicalOperationTypes.prescription
                  ? '1 tablet'
                  : '1',
              route:
                  operation.operationType == ClinicalOperationTypes.prescription
                  ? 'Oral'
                  : 'IV',
              frequency:
                  operation.operationType == ClinicalOperationTypes.prescription
                  ? 'Twice daily'
                  : 'Once',
              duration:
                  operation.operationType == ClinicalOperationTypes.prescription
                  ? '7 days'
                  : 'Today',
              instructions: operation.description,
            ),
            now: now,
          );
        }
        if ({
          ClinicalOperationTypes.document,
          ClinicalOperationTypes.imaging,
        }.contains(operation.operationType)) {
          final existingDocuments =
              await (db.select(db.clinicalDocumentVersions)..where(
                    (row) =>
                        row.clinicId.equals(activeClinicId) &
                        row.operationId.equals(operation.id),
                  ))
                  .get();
          if (existingDocuments.isEmpty && uploader != null) {
            await db
                .into(db.clinicalDocumentVersions)
                .insert(
                  ClinicalDocumentVersionsCompanion.insert(
                    clinicId: activeClinicId,
                    operationId: operation.id,
                    category:
                        operation.operationType ==
                            ClinicalOperationTypes.imaging
                        ? 'Imaging report'
                        : 'Clinical document',
                    fileName:
                        operation.operationType ==
                            ClinicalOperationTypes.imaging
                        ? 'thoracic-radiograph-report.pdf'
                        : 'anaesthesia-consent.pdf',
                    mimeType: const Value('application/pdf'),
                    storagePath:
                        'demo://${operation.operationType}/${operation.id}',
                    uploadedByUserId: uploader.userId,
                    uploadedAt: now,
                  ),
                );
          }
        }
        if (operation.referenceNumber == null) {
          await (db.update(
            db.clinicalOperationRecords,
          )..where((row) => row.id.equals(operation.id))).write(
            ClinicalOperationRecordsCompanion(
              referenceNumber: Value(
                _clinicalReference(
                  operation.operationType,
                  operation.createdAt.year,
                  operation.id,
                ),
              ),
            ),
          );
        }
      }
    });
  }

  Future<int> createClinicalOperation({
    required UserSession session,
    required int animalId,
    required String operationType,
    required String title,
    String? description,
    String? assignedTo,
    DateTime? scheduledAt,
    int? consultationId,
    int? hospitalizationId,
    int? sourceOperationId,
    String status = 'Draft',
    String priority = 'Routine',
    double? estimatedAmount,
    Map<String, Object?> details = const {},
    List<ClinicalMedicationDraft> items = const [],
  }) async {
    _requireClinicalOperationPermission(
      session,
      operationType: operationType,
      action: 'create',
    );
    await _requireActiveFeature(_featureForClinicalOperation(operationType));
    final animal =
        await (db.select(db.animals)..where(
              (row) =>
                  row.id.equals(animalId) & row.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (animal == null) {
      throw StateError('Patient was not found in this clinic.');
    }
    final now = _clock.nowForClinic(session.clinic);
    if (title.trim().isEmpty) {
      throw StateError('Enter a clinical record title.');
    }
    return db.transaction(() async {
      final id = await db
          .into(db.clinicalOperationRecords)
          .insert(
            ClinicalOperationRecordsCompanion.insert(
              clinicId: activeClinicId,
              animalId: animalId,
              visitId: Value(consultationId),
              hospitalizationId: Value(hospitalizationId),
              sourceOperationId: Value(sourceOperationId),
              operationType: operationType,
              title: title.trim(),
              description: Value(description?.trim()),
              status: Value(status),
              priority: Value(priority),
              assignedTo: Value(assignedTo?.trim()),
              scheduledAt: Value(scheduledAt),
              estimatedAmount: Value(estimatedAmount),
              detailsJson: Value(details.isEmpty ? null : jsonEncode(details)),
              createdByUserId: Value(session.user.userId),
              updatedByUserId: Value(session.user.userId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (db.update(
        db.clinicalOperationRecords,
      )..where((row) => row.id.equals(id))).write(
        ClinicalOperationRecordsCompanion(
          referenceNumber: Value(
            _clinicalReference(operationType, now.year, id),
          ),
        ),
      );
      for (final item in items) {
        await _insertClinicalOperationItem(
          operationId: id,
          itemType: operationType == ClinicalOperationTypes.prescription
              ? 'Medication'
              : 'Treatment',
          draft: item,
          now: now,
        );
      }
      await _writeClinicalOperationAudit(
        session: session,
        action: '${operationType}_created',
        operationId: id,
        details: {
          'type': operationType,
          'title': title.trim(),
          'animalId': animalId,
          'status': status,
          'itemCount': items.length,
        },
      );
      await _writeClinicalOperationActivity(
        session: session,
        operationId: id,
        animalId: animalId,
        operationType: operationType,
        action: 'created',
        title:
            '${_operationLabel(operationType)} created for ${animal.animalName}',
        description: title.trim(),
        occurredAt: now,
      );
      return id;
    });
  }

  Future<void> updateClinicalOperationStatus({
    required UserSession session,
    required int operationId,
    required String status,
    String? reason,
    Map<String, Object?> details = const {},
  }) async {
    final record =
        await (db.select(db.clinicalOperationRecords)..where(
              (row) =>
                  row.id.equals(operationId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (record == null) {
      throw StateError('Clinical operation was not found in this clinic.');
    }
    _requireClinicalOperationPermission(
      session,
      operationType: record.operationType,
      action: _statusPermissionAction(status),
    );
    await _requireActiveFeature(
      _featureForClinicalOperation(record.operationType),
    );
    _validateClinicalStatusTransition(
      type: record.operationType,
      from: record.status,
      to: status,
      reason: reason,
    );
    final now = _clock.nowForClinic(session.clinic);
    await db.transaction(() async {
      await (db.update(
        db.clinicalOperationRecords,
      )..where((row) => row.id.equals(operationId))).write(
        ClinicalOperationRecordsCompanion(
          status: Value(status),
          completedAt: Value(
            _isTerminalClinicalStatus(status) ? now : record.completedAt,
          ),
          updatedByUserId: Value(session.user.userId),
          recordVersion: Value(record.recordVersion + 1),
          updatedAt: Value(now),
        ),
      );
      await db
          .into(db.clinicalOperationActions)
          .insert(
            ClinicalOperationActionsCompanion.insert(
              clinicId: activeClinicId,
              operationId: operationId,
              action: 'statusChanged',
              previousStatus: Value(record.status),
              newStatus: Value(status),
              performedByUserId: session.user.userId,
              reason: Value(_nullIfBlank(reason)),
              detailsJson: Value(details.isEmpty ? null : jsonEncode(details)),
              occurredAt: now,
            ),
          );
      await _writeClinicalOperationAudit(
        session: session,
        action: '${record.operationType}_status_changed',
        operationId: operationId,
        details: {
          'type': record.operationType,
          'from': record.status,
          'to': status,
          'reason': reason,
          ...details,
        },
      );
      await _writeClinicalOperationActivity(
        session: session,
        operationId: operationId,
        animalId: record.animalId,
        operationType: record.operationType,
        action: _activityActionForStatus(status),
        title:
            '${_operationLabel(record.operationType)} ${status.toLowerCase()}',
        description: record.title,
        occurredAt: now,
      );
    });
  }

  void _requireClinicalOperationPermission(
    UserSession session, {
    required String operationType,
    required String action,
  }) {
    final permission = _clinicalPermission(operationType, action);
    if (session.clinic.clinicId != activeClinicId || !session.can(permission)) {
      throw StateError(
        'You do not have permission to perform this clinical action.',
      );
    }
  }

  String _clinicalPermission(String type, String action) => switch (type) {
    ClinicalOperationTypes.prescription => switch (action) {
      'view' => Permissions.prescriptionsView,
      'create' => Permissions.prescriptionsCreate,
      'activate' => Permissions.prescriptionsActivate,
      'cancel' => Permissions.prescriptionsCancel,
      'dispense' => Permissions.prescriptionsDispense,
      'print' => Permissions.prescriptionsPrint,
      _ => Permissions.prescriptionsEdit,
    },
    ClinicalOperationTypes.treatment => switch (action) {
      'view' => Permissions.treatmentBoardView,
      'create' => Permissions.treatmentBoardCreate,
      'administer' => Permissions.treatmentBoardAdminister,
      'delay' => Permissions.treatmentBoardDelay,
      'withhold' => Permissions.treatmentBoardWithhold,
      'cancel' => Permissions.treatmentBoardCancel,
      'reopen' => Permissions.treatmentBoardReopen,
      _ => Permissions.treatmentBoardCreate,
    },
    ClinicalOperationTypes.surgery => switch (action) {
      'view' => Permissions.surgeryView,
      'create' => Permissions.surgeryCreate,
      'cancel' => Permissions.surgeryCancel,
      'complete' => Permissions.surgeryComplete,
      'preop' => Permissions.surgeryManagePreop,
      'intraop' => Permissions.surgeryManageIntraop,
      'recovery' => Permissions.surgeryManageRecovery,
      'print' => Permissions.surgeryPrint,
      _ => Permissions.surgeryEdit,
    },
    ClinicalOperationTypes.imaging => switch (action) {
      'view' => Permissions.imagingView,
      'create' => Permissions.imagingRequest,
      'schedule' => Permissions.imagingSchedule,
      'upload' => Permissions.imagingUpload,
      'report' => Permissions.imagingReport,
      'complete' => Permissions.imagingComplete,
      'cancel' => Permissions.imagingCancel,
      _ => Permissions.imagingReport,
    },
    ClinicalOperationTypes.document => switch (action) {
      'view' => Permissions.documentsView,
      'create' || 'upload' => Permissions.documentsUpload,
      'archive' => Permissions.documentsArchive,
      'delete' => Permissions.documentsDelete,
      'share' => Permissions.documentsShare,
      'download' => Permissions.documentsDownload,
      _ => Permissions.documentsEdit,
    },
    _ => throw ArgumentError.value(type, 'type'),
  };

  Future<ClinicalOperationDetail?> getClinicalOperationDetail(
    UserSession session,
    int operationId,
  ) async {
    final record =
        await (db.select(db.clinicalOperationRecords).join([
              innerJoin(
                db.animals,
                db.animals.id.equalsExp(db.clinicalOperationRecords.animalId),
              ),
              innerJoin(db.owners, db.owners.id.equalsExp(db.animals.ownerId)),
            ])..where(
              db.clinicalOperationRecords.id.equals(operationId) &
                  db.clinicalOperationRecords.clinicId.equals(
                    session.clinic.clinicId,
                  ),
            ))
            .getSingleOrNull();
    if (record == null) return null;
    final operation = record.readTable(db.clinicalOperationRecords);
    _requireClinicalOperationPermission(
      session,
      operationType: operation.operationType,
      action: 'view',
    );
    final items =
        await (db.select(db.clinicalOperationItems)
              ..where(
                (row) =>
                    row.clinicId.equals(session.clinic.clinicId) &
                    row.operationId.equals(operationId),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    final actions =
        await (db.select(db.clinicalOperationActions)
              ..where(
                (row) =>
                    row.clinicId.equals(session.clinic.clinicId) &
                    row.operationId.equals(operationId),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.occurredAt)]))
            .get();
    final documents =
        await (db.select(db.clinicalDocumentVersions)
              ..where(
                (row) =>
                    row.clinicId.equals(session.clinic.clinicId) &
                    row.operationId.equals(operationId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.versionNumber)]))
            .get();
    return ClinicalOperationDetail(
      record: ClinicOperationRecord(
        operation: operation,
        animal: record.readTable(db.animals),
        owner: record.readTable(db.owners),
      ),
      items: items,
      actions: actions,
      documents: documents,
    );
  }

  Future<int> addClinicalOperationItem({
    required UserSession session,
    required int operationId,
    required ClinicalMedicationDraft item,
  }) async {
    final operation = await _clinicalOperationForSession(operationId, session);
    _requireClinicalOperationPermission(
      session,
      operationType: operation.operationType,
      action: 'edit',
    );
    if (item.name.trim().isEmpty) {
      throw StateError('Enter a medication or treatment name.');
    }
    final now = _clock.nowForClinic(session.clinic);
    return _insertClinicalOperationItem(
      operationId: operationId,
      itemType: operation.operationType == ClinicalOperationTypes.prescription
          ? 'Medication'
          : 'Treatment',
      draft: item,
      now: now,
    );
  }

  Future<void> dispensePrescriptionItem({
    required UserSession session,
    required int operationId,
    required int operationItemId,
    required double quantity,
    String notes = '',
  }) async {
    final operation = await _clinicalOperationForSession(operationId, session);
    if (operation.operationType != ClinicalOperationTypes.prescription) {
      throw StateError('This record is not a prescription.');
    }
    _requireClinicalOperationPermission(
      session,
      operationType: operation.operationType,
      action: 'dispense',
    );
    if (quantity <= 0 || quantity != quantity.roundToDouble()) {
      throw StateError('Enter a whole dispensing quantity greater than zero.');
    }
    await db.transaction(() async {
      final item = await _clinicalOperationItemForSession(
        operationItemId,
        operationId,
        session,
      );
      final prescribed = item.prescribedQuantity ?? 0;
      final remaining = prescribed - item.completedQuantity;
      if (quantity > remaining) {
        throw StateError(
          'Only ${remaining.toStringAsFixed(0)} ${item.unit ?? 'units'} remain to dispense.',
        );
      }
      if (item.inventoryItemId == null) {
        throw StateError(
          'Link this medication to an inventory product before dispensing.',
        );
      }
      final now = _clock.nowForClinic(session.clinic);
      final inventory = await _inventoryItemForSession(
        item.inventoryItemId!,
        session,
      );
      if (inventory.isArchived || !inventory.isSellable) {
        throw StateError(
          '${inventory.drugName} is unavailable for dispensing.',
        );
      }
      if (inventory.expiryDate?.isBefore(now) == true) {
        throw StateError('Expired stock cannot be dispensed.');
      }
      final wholeQuantity = quantity.toInt();
      if (inventory.quantity < wholeQuantity) {
        throw StateError(
          'Insufficient stock. ${inventory.quantity} available; $wholeQuantity requested.',
        );
      }
      final after = inventory.quantity - wholeQuantity;
      await (db.update(
        db.inventoryItems,
      )..where((row) => row.id.equals(inventory.id))).write(
        InventoryItemsCompanion(quantity: Value(after), updatedAt: Value(now)),
      );
      await db
          .into(db.inventoryStockMovements)
          .insert(
            InventoryStockMovementsCompanion.insert(
              clinicId: activeClinicId,
              inventoryItemId: inventory.id,
              movementType: 'Prescription dispense',
              quantityChange: -wholeQuantity,
              quantityBefore: inventory.quantity,
              quantityAfter: after,
              performedByUserId: session.user.userId,
              reason: Value(
                '${operation.referenceNumber ?? operation.id}: ${item.name}',
              ),
              createdAt: now,
            ),
          );
      final completed = item.completedQuantity + quantity;
      final itemComplete = completed >= prescribed;
      await (db.update(
        db.clinicalOperationItems,
      )..where((row) => row.id.equals(item.id))).write(
        ClinicalOperationItemsCompanion(
          completedQuantity: Value(completed),
          status: Value(itemComplete ? 'Dispensed' : 'Partially Dispensed'),
          updatedAt: Value(now),
        ),
      );
      final allItems =
          await (db.select(db.clinicalOperationItems)..where(
                (row) =>
                    row.operationId.equals(operationId) &
                    row.clinicId.equals(activeClinicId),
              ))
              .get();
      final allComplete = allItems.every(
        (row) => row.id == item.id
            ? itemComplete
            : row.prescribedQuantity != null &&
                  row.completedQuantity >= row.prescribedQuantity!,
      );
      final nextStatus = allComplete ? 'Dispensed' : 'Partially Dispensed';
      await _updateOperationWithinTransaction(
        operation: operation,
        status: nextStatus,
        session: session,
        now: now,
      );
      await db
          .into(db.clinicalOperationActions)
          .insert(
            ClinicalOperationActionsCompanion.insert(
              clinicId: activeClinicId,
              operationId: operationId,
              operationItemId: Value(item.id),
              action: allComplete ? 'fullyDispensed' : 'partiallyDispensed',
              previousStatus: Value(operation.status),
              newStatus: Value(nextStatus),
              quantity: Value(quantity),
              unit: Value(item.unit),
              inventoryItemId: Value(inventory.id),
              batchNumber: Value(inventory.batchNumber),
              batchExpiryDate: Value(inventory.expiryDate),
              performedByUserId: session.user.userId,
              notes: Value(_nullIfBlank(notes)),
              occurredAt: now,
            ),
          );
      final charge = inventory.sellingPrice * wholeQuantity;
      final invoiceId = await _appendClinicalCharge(
        session: session,
        operation: operation,
        description:
            '${item.name} (${quantity.toStringAsFixed(0)} ${item.unit ?? 'units'})',
        amount: charge,
        now: now,
      );
      await _writeClinicalOperationAudit(
        session: session,
        action: allComplete
            ? 'prescription_fully_dispensed'
            : 'prescription_partially_dispensed',
        operationId: operationId,
        details: {
          'itemId': item.id,
          'quantity': quantity,
          'inventoryItemId': inventory.id,
          'batchNumber': inventory.batchNumber,
          'invoiceId': invoiceId,
        },
      );
      await _writeClinicalOperationActivity(
        session: session,
        operationId: operationId,
        animalId: operation.animalId,
        operationType: operation.operationType,
        action: allComplete ? 'dispensed' : 'partiallyDispensed',
        title:
            '${item.name} ${allComplete ? 'dispensed' : 'partially dispensed'}',
        description: operation.referenceNumber ?? operation.title,
        occurredAt: now,
      );
    });
  }

  Future<void> recordTreatmentAction({
    required UserSession session,
    required int operationId,
    required String status,
    int? operationItemId,
    double? actualDose,
    String? doseUnit,
    String? route,
    String? verifiedByUserId,
    String? reason,
    String? patientResponse,
    String? notes,
  }) async {
    final operation = await _clinicalOperationForSession(operationId, session);
    if (operation.operationType != ClinicalOperationTypes.treatment) {
      throw StateError('This record is not a treatment task.');
    }
    final action = switch (status) {
      'Administered' => 'administer',
      'Delayed' => 'delay',
      'Withheld' => 'withhold',
      'Cancelled' => 'cancel',
      _ => 'edit',
    };
    _requireClinicalOperationPermission(
      session,
      operationType: operation.operationType,
      action: action,
    );
    if (status != 'Administered' && (reason?.trim().isEmpty ?? true)) {
      throw StateError('Enter a reason for $status treatment.');
    }
    await db.transaction(() async {
      final priorAdministration =
          await (db.select(db.clinicalOperationActions)..where(
                (row) =>
                    row.clinicId.equals(activeClinicId) &
                    row.operationId.equals(operationId) &
                    row.action.equals('administered'),
              ))
              .getSingleOrNull();
      if (status == 'Administered' && priorAdministration != null) {
        throw StateError(
          'This treatment was already administered. Reopen it with authorization before recording another dose.',
        );
      }
      final now = _clock.nowForClinic(session.clinic);
      ClinicalOperationItem? item;
      InventoryItem? inventory;
      if (operationItemId != null) {
        item = await _clinicalOperationItemForSession(
          operationItemId,
          operationId,
          session,
        );
        if (status == 'Administered' &&
            item.isHighRisk &&
            (verifiedByUserId?.trim().isEmpty ?? true)) {
          throw StateError(
            'A second checker is required for this high-risk treatment.',
          );
        }
        if (status == 'Administered' && item.inventoryItemId != null) {
          inventory = await _inventoryItemForSession(
            item.inventoryItemId!,
            session,
          );
          if (inventory.expiryDate?.isBefore(now) == true) {
            throw StateError('Expired stock cannot be administered.');
          }
          final stockQuantity = (actualDose ?? 1).ceil();
          if (inventory.quantity < stockQuantity) {
            throw StateError('Insufficient stock for this administration.');
          }
          final after = inventory.quantity - stockQuantity;
          await (db.update(
            db.inventoryItems,
          )..where((row) => row.id.equals(inventory!.id))).write(
            InventoryItemsCompanion(
              quantity: Value(after),
              updatedAt: Value(now),
            ),
          );
          await db
              .into(db.inventoryStockMovements)
              .insert(
                InventoryStockMovementsCompanion.insert(
                  clinicId: activeClinicId,
                  inventoryItemId: inventory.id,
                  movementType: 'Treatment administration',
                  quantityChange: -stockQuantity,
                  quantityBefore: inventory.quantity,
                  quantityAfter: after,
                  performedByUserId: session.user.userId,
                  reason: Value(operation.referenceNumber),
                  createdAt: now,
                ),
              );
        }
      }
      await _updateOperationWithinTransaction(
        operation: operation,
        status: status,
        session: session,
        now: now,
      );
      await db
          .into(db.clinicalOperationActions)
          .insert(
            ClinicalOperationActionsCompanion.insert(
              clinicId: activeClinicId,
              operationId: operationId,
              operationItemId: Value(item?.id),
              action: status.toLowerCase(),
              previousStatus: Value(operation.status),
              newStatus: Value(status),
              quantity: Value(actualDose),
              unit: Value(doseUnit),
              inventoryItemId: Value(inventory?.id),
              batchNumber: Value(inventory?.batchNumber),
              batchExpiryDate: Value(inventory?.expiryDate),
              performedByUserId: session.user.userId,
              verifiedByUserId: Value(_nullIfBlank(verifiedByUserId)),
              reason: Value(_nullIfBlank(reason)),
              notes: Value(_nullIfBlank(notes)),
              detailsJson: Value(
                jsonEncode({
                  'route': route,
                  'patientResponse': patientResponse,
                }),
              ),
              occurredAt: now,
            ),
          );
      if (status == 'Administered' && inventory != null) {
        await _appendClinicalCharge(
          session: session,
          operation: operation,
          description: item?.name ?? operation.title,
          amount: inventory.sellingPrice * (actualDose ?? 1).ceil(),
          now: now,
        );
      }
      await _writeClinicalOperationAudit(
        session: session,
        action: 'treatment_${status.toLowerCase()}',
        operationId: operationId,
        details: {'reason': reason, 'verifiedByUserId': verifiedByUserId},
      );
      await _writeClinicalOperationActivity(
        session: session,
        operationId: operationId,
        animalId: operation.animalId,
        operationType: operation.operationType,
        action: status.toLowerCase(),
        title: '${operation.title} ${status.toLowerCase()}',
        description: patientResponse ?? reason ?? 'Treatment updated.',
        occurredAt: now,
      );
    });
  }

  Future<int> addClinicalDocumentVersion({
    required UserSession session,
    required int operationId,
    required String category,
    required String fileName,
    required String storagePath,
    String? mimeType,
    int? fileSize,
    bool isSensitive = false,
    int? parentVersionId,
    String? replacementReason,
  }) async {
    final operation = await _clinicalOperationForSession(operationId, session);
    _requireClinicalOperationPermission(
      session,
      operationType: ClinicalOperationTypes.document,
      action: 'upload',
    );
    if (operation.operationType != ClinicalOperationTypes.document &&
        operation.operationType != ClinicalOperationTypes.imaging &&
        operation.operationType != ClinicalOperationTypes.surgery &&
        operation.operationType != ClinicalOperationTypes.prescription) {
      throw StateError('This record does not support clinical documents.');
    }
    if (fileName.trim().isEmpty || storagePath.trim().isEmpty) {
      throw StateError('Select a valid document file.');
    }
    return db.transaction(() async {
      var version = 1;
      if (parentVersionId != null) {
        final parent =
            await (db.select(db.clinicalDocumentVersions)..where(
                  (row) =>
                      row.id.equals(parentVersionId) &
                      row.clinicId.equals(activeClinicId),
                ))
                .getSingleOrNull();
        if (parent == null || parent.operationId != operationId) {
          throw StateError('The previous document version was not found.');
        }
        if (replacementReason?.trim().isEmpty ?? true) {
          throw StateError('Enter a reason for replacing this document.');
        }
        version = parent.versionNumber + 1;
      }
      final now = _clock.nowForClinic(session.clinic);
      final id = await db
          .into(db.clinicalDocumentVersions)
          .insert(
            ClinicalDocumentVersionsCompanion.insert(
              clinicId: activeClinicId,
              operationId: operationId,
              parentVersionId: Value(parentVersionId),
              category: category,
              fileName: fileName.trim(),
              mimeType: Value(mimeType),
              fileSize: Value(fileSize),
              storagePath: storagePath.trim(),
              versionNumber: Value(version),
              isSensitive: Value(isSensitive),
              replacementReason: Value(_nullIfBlank(replacementReason)),
              uploadedByUserId: session.user.userId,
              uploadedAt: now,
            ),
          );
      await _writeClinicalOperationAudit(
        session: session,
        action: parentVersionId == null
            ? 'document_uploaded'
            : 'document_replaced',
        operationId: operationId,
        details: {
          'documentVersionId': id,
          'version': version,
          'fileName': fileName.trim(),
          'replacementReason': replacementReason,
        },
      );
      return id;
    });
  }

  Future<ClinicalOperationRecord> _clinicalOperationForSession(
    int operationId,
    UserSession session,
  ) async {
    final record =
        await (db.select(db.clinicalOperationRecords)..where(
              (row) =>
                  row.id.equals(operationId) &
                  row.clinicId.equals(session.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (record == null) {
      throw StateError('Clinical record not found in the active clinic.');
    }
    return record;
  }

  Future<ClinicalOperationItem> _clinicalOperationItemForSession(
    int itemId,
    int operationId,
    UserSession session,
  ) async {
    final item =
        await (db.select(db.clinicalOperationItems)..where(
              (row) =>
                  row.id.equals(itemId) &
                  row.operationId.equals(operationId) &
                  row.clinicId.equals(session.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (item == null) {
      throw StateError('Medication or treatment item was not found.');
    }
    return item;
  }

  Future<int> _insertClinicalOperationItem({
    required int operationId,
    required String itemType,
    required ClinicalMedicationDraft draft,
    required DateTime now,
  }) => db
      .into(db.clinicalOperationItems)
      .insert(
        ClinicalOperationItemsCompanion.insert(
          clinicId: activeClinicId,
          operationId: operationId,
          inventoryItemId: Value(draft.inventoryItemId),
          itemType: itemType,
          name: draft.name.trim(),
          strength: Value(_nullIfBlank(draft.strength)),
          prescribedQuantity: Value(draft.quantity),
          unit: Value(_nullIfBlank(draft.unit)),
          dose: Value(_nullIfBlank(draft.dose)),
          doseUnit: Value(_nullIfBlank(draft.doseUnit)),
          route: Value(_nullIfBlank(draft.route)),
          frequency: Value(_nullIfBlank(draft.frequency)),
          duration: Value(_nullIfBlank(draft.duration)),
          instructions: Value(_nullIfBlank(draft.instructions)),
          isHighRisk: Value(draft.isHighRisk),
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<void> _updateOperationWithinTransaction({
    required ClinicalOperationRecord operation,
    required String status,
    required UserSession session,
    required DateTime now,
  }) =>
      (db.update(
        db.clinicalOperationRecords,
      )..where((row) => row.id.equals(operation.id))).write(
        ClinicalOperationRecordsCompanion(
          status: Value(status),
          completedAt: Value(_isTerminalClinicalStatus(status) ? now : null),
          updatedByUserId: Value(session.user.userId),
          recordVersion: Value(operation.recordVersion + 1),
          updatedAt: Value(now),
        ),
      );

  Future<int> _appendClinicalCharge({
    required UserSession session,
    required ClinicalOperationRecord operation,
    required String description,
    required double amount,
    required DateTime now,
  }) async {
    var invoice =
        await (db.select(db.invoices)..where(
              (row) =>
                  row.clinicId.equals(activeClinicId) &
                  row.linkedClinicalOperationId.equals(operation.id) &
                  row.status.equals('Voided').not(),
            ))
            .getSingleOrNull();
    if (invoice == null) {
      final id = await db
          .into(db.invoices)
          .insert(
            InvoicesCompanion.insert(
              clinicId: activeClinicId,
              animalId: operation.animalId,
              reference: 'PENDING-${_uuid.v4()}',
              linkedClinicalOperationId: Value(operation.id),
              clinicNameSnapshot: session.clinic.clinicName,
              clinicAddressSnapshot: Value(session.clinic.address),
              clinicPhoneSnapshot: Value(session.clinic.phoneNumber),
              clinicEmailSnapshot: Value(session.clinic.email),
              createdByUserId: session.user.userId,
              createdAt: now,
              updatedAt: Value(now),
            ),
          );
      await (db.update(db.invoices)..where((row) => row.id.equals(id))).write(
        InvoicesCompanion(
          reference: Value('INV-${now.year}-${id.toString().padLeft(5, '0')}'),
        ),
      );
      invoice = await _invoiceForSession(id, session);
    }
    await db
        .into(db.invoiceServiceLines)
        .insert(
          InvoiceServiceLinesCompanion.insert(
            invoiceId: invoice.id,
            description: description,
            amount: amount,
          ),
        );
    final services = invoice.servicesSubtotal + amount;
    final total = invoice.total + amount;
    await (db.update(
      db.invoices,
    )..where((row) => row.id.equals(invoice!.id))).write(
      InvoicesCompanion(
        servicesSubtotal: Value(services),
        total: Value(total),
        balance: Value(invoice.balance + amount),
        updatedAt: Value(now),
      ),
    );
    return invoice.id;
  }

  String _clinicalReference(String type, int year, int id) {
    final prefix = switch (type) {
      ClinicalOperationTypes.prescription => 'RX',
      ClinicalOperationTypes.treatment => 'TRT',
      ClinicalOperationTypes.surgery => 'SUR',
      ClinicalOperationTypes.imaging => 'IMG',
      ClinicalOperationTypes.document => 'DOC',
      _ => 'CLN',
    };
    return '$prefix-$year-${id.toString().padLeft(5, '0')}';
  }

  String _operationLabel(String type) => switch (type) {
    ClinicalOperationTypes.prescription => 'Prescription',
    ClinicalOperationTypes.treatment => 'Treatment',
    ClinicalOperationTypes.surgery => 'Surgery',
    ClinicalOperationTypes.imaging => 'Imaging request',
    ClinicalOperationTypes.document => 'Medical document',
    _ => 'Clinical record',
  };

  String _statusPermissionAction(String status) => switch (status) {
    'Active' => 'activate',
    'Cancelled' => 'cancel',
    'Dispensed' || 'Partially Dispensed' => 'dispense',
    'Administered' => 'administer',
    'Delayed' => 'delay',
    'Withheld' => 'withhold',
    'Ready for Surgery' || 'Pre-operative' => 'preop',
    'In Progress' => 'intraop',
    'Recovery' => 'recovery',
    'Completed' => 'complete',
    'Scheduled' => 'schedule',
    'Awaiting Report' || 'Reported' => 'report',
    'Archived' => 'archive',
    _ => 'edit',
  };

  void _validateClinicalStatusTransition({
    required String type,
    required String from,
    required String to,
    String? reason,
  }) {
    if (from == to) return;
    final allowed = switch (type) {
      ClinicalOperationTypes.prescription => <String, Set<String>>{
        'Draft': {'Active', 'Cancelled'},
        'Pending': {'Active', 'Cancelled'},
        'Active': {'Partially Dispensed', 'Dispensed', 'Expired', 'Cancelled'},
        'Partially Dispensed': {'Dispensed', 'Cancelled'},
      },
      ClinicalOperationTypes.treatment => <String, Set<String>>{
        'Pending': {'Upcoming', 'Due', 'Cancelled'},
        'Upcoming': {'Due', 'Cancelled'},
        'Due': {'Administered', 'Delayed', 'Missed', 'Withheld', 'Cancelled'},
        'Overdue': {
          'Administered',
          'Delayed',
          'Missed',
          'Withheld',
          'Cancelled',
        },
        'Delayed': {'Due', 'Administered', 'Missed', 'Cancelled'},
      },
      ClinicalOperationTypes.surgery => <String, Set<String>>{
        'Draft': {'Scheduled', 'Cancelled'},
        'Pending': {'Scheduled', 'Cancelled'},
        'Scheduled': {'Pre-operative', 'Cancelled'},
        'Pre-operative': {'Ready for Surgery', 'Cancelled'},
        'Ready for Surgery': {'In Progress', 'Cancelled'},
        'In Progress': {'Recovery', 'Cancelled'},
        'Recovery': {'Completed'},
      },
      ClinicalOperationTypes.imaging => <String, Set<String>>{
        'Draft': {'Requested', 'Cancelled'},
        'Pending': {'Requested', 'Cancelled'},
        'Requested': {'Scheduled', 'In Progress', 'Cancelled'},
        'Scheduled': {'In Progress', 'Cancelled'},
        'In Progress': {'Awaiting Report', 'Cancelled'},
        'Awaiting Report': {'Reported', 'Completed', 'Cancelled'},
        'Reported': {'Completed'},
      },
      ClinicalOperationTypes.document => <String, Set<String>>{
        'Draft': {'Available', 'Archived'},
        'Pending': {'Available', 'Archived'},
        'Available': {'Reviewed', 'Archived'},
        'Reviewed': {'Archived'},
        'Archived': {'Available'},
      },
      _ => const <String, Set<String>>{},
    };
    if (!(allowed[from]?.contains(to) ?? false)) {
      throw StateError('Cannot change $type from $from to $to.');
    }
    if ({'Cancelled', 'Missed', 'Delayed', 'Withheld'}.contains(to) &&
        (reason?.trim().isEmpty ?? true)) {
      throw StateError('Enter a reason before marking this record $to.');
    }
  }

  bool _isTerminalClinicalStatus(String status) => {
    'Completed',
    'Dispensed',
    'Reported',
    'Reviewed',
    'Administered',
    'Cancelled',
    'Missed',
    'Withheld',
    'Archived',
  }.contains(status);

  String _activityActionForStatus(String status) => status
      .replaceAll(' ', '')
      .replaceFirstMapped(RegExp(r'^.'), (match) => match[0]!.toLowerCase());

  Future<void> _writeClinicalOperationActivity({
    required UserSession session,
    required int operationId,
    required int animalId,
    required String operationType,
    required String action,
    required String title,
    required String description,
    required DateTime occurredAt,
  }) => db
      .into(db.clinicActivityEvents)
      .insert(
        ClinicActivityEventsCompanion.insert(
          id: '$operationType:$action:$operationId:${occurredAt.microsecondsSinceEpoch}',
          clinicId: activeClinicId,
          type: '$operationType.$action',
          title: title,
          description: description,
          occurredAt: occurredAt,
          performedByUserId: Value(session.user.userId),
          relatedEntityType: const Value('ClinicalOperation'),
          relatedEntityId: Value(operationId.toString()),
          patientId: Value(animalId),
          module: Value(operationType),
          metadata: Value(
            jsonEncode({
              'route': '/operations/$operationType',
              'operationId': operationId,
            }),
          ),
        ),
      )
      .then((_) {});

  AveraFeature _featureForClinicalOperation(String type) => switch (type) {
    ClinicalOperationTypes.surgery => AveraFeature.surgery,
    ClinicalOperationTypes.prescription => AveraFeature.prescriptions,
    ClinicalOperationTypes.imaging => AveraFeature.imaging,
    ClinicalOperationTypes.document => AveraFeature.documents,
    ClinicalOperationTypes.treatment => AveraFeature.treatmentBoard,
    _ => throw ArgumentError.value(
      type,
      'type',
      'Unsupported clinical operation.',
    ),
  };

  Future<void> _writeClinicalOperationAudit({
    required UserSession session,
    required String action,
    required int operationId,
    required Map<String, Object?> details,
  }) => db
      .into(db.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          clinicId: Value(activeClinicId),
          userId: Value(session.user.userId),
          action: action,
          entityType: const Value('ClinicalOperation'),
          entityId: Value(operationId.toString()),
          details: Value(jsonEncode(details)),
          createdAt: _clock.nowForClinic(session.clinic),
        ),
      )
      .then((_) {});

  Stream<List<Appointment>> watchAppointments() =>
      (db.select(db.appointments)
            ..where((a) => a.clinicId.equals(activeClinicId))
            ..orderBy([(a) => OrderingTerm.asc(a.appointmentDate)]))
          .watch();

  Future<List<AppointmentDetail>> upcomingAppointmentDetails() async {
    final appointments =
        await (db.select(db.appointments)
              ..where(
                (item) =>
                    item.clinicId.equals(activeClinicId) &
                    item.appointmentDate.isBiggerThanValue(DateTime.now()) &
                    item.status.equals(AppointmentStatuses.cancelled).not(),
              )
              ..orderBy([(item) => OrderingTerm.asc(item.appointmentDate)]))
            .get();
    final details = <AppointmentDetail>[];
    for (final appointment in appointments) {
      final detail = await getAppointmentDetail(appointment.id);
      if (detail != null) details.add(detail);
    }
    return details;
  }

  Future<AppointmentDetail?> getAppointmentDetail(int appointmentId) async {
    final appointment =
        await (db.select(db.appointments)..where(
              (item) =>
                  item.id.equals(appointmentId) &
                  item.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (appointment == null) return null;
    final animal =
        await (db.select(db.animals)..where(
              (item) =>
                  item.id.equals(appointment.animalId) &
                  item.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (animal == null) return null;
    final owner = await (db.select(
      db.owners,
    )..where((item) => item.id.equals(animal.ownerId))).getSingleOrNull();
    if (owner == null) return null;
    final assignedStaff = appointment.assignedStaffId == null
        ? null
        : await (db.select(db.appUsers)..where(
                (item) =>
                    item.userId.equals(appointment.assignedStaffId!) &
                    item.clinicId.equals(activeClinicId),
              ))
              .getSingleOrNull();
    final reminders = await (db.select(
      db.appointmentReminders,
    )..where((item) => item.appointmentId.equals(appointment.id))).get();
    return AppointmentDetail(
      appointment: appointment,
      animal: animal,
      owner: owner,
      assignedStaff: assignedStaff,
      reminders: reminders
        ..sort((a, b) => b.daysBefore.compareTo(a.daysBefore)),
    );
  }

  Stream<List<AppointmentReminder>> watchAppointmentReminders(
    int appointmentId,
  ) =>
      (db.select(db.appointmentReminders)
            ..where((item) => item.appointmentId.equals(appointmentId))
            ..orderBy([(item) => OrderingTerm.desc(item.daysBefore)]))
          .watch();

  Future<List<AppUser>> eligibleAppointmentStaff() async {
    final staff =
        await (db.select(db.appUsers)..where(
              (user) =>
                  user.clinicId.equals(activeClinicId) &
                  user.membershipStatus.equals(
                    ClinicMembershipStatuses.active,
                  ) &
                  user.accountStatus.equals(AccountStatuses.active),
            ))
            .get();
    return staff
        .where(
          (user) =>
              user.role == 'Veterinarian' ||
              (user.role == 'Clinic Administrator' &&
                  (user.professionalTitle ?? '').toLowerCase().contains(
                    'vet',
                  )) ||
              (rolePermissions[user.role] ?? const <String>{}).contains(
                Permissions.consultationsCreate,
              ) ||
              _permissionsFromJson(
                user.permissions,
              ).contains(Permissions.consultationsCreate),
        )
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  Future<Appointment> createAppointment({
    required UserSession session,
    required int animalId,
    required DateTime scheduledAt,
    required String appointmentType,
    String? assignedStaffId,
    String? notes,
    Set<int> enabledReminderDays = const {7, 3, 1},
  }) async {
    _requireAppointmentPermission(session, Permissions.appointmentsCreate);
    await _requireActiveFeature(AveraFeature.schedule);
    if (scheduledAt.isBefore(_clock.nowForClinic(session.clinic))) {
      throw StateError('Choose an appointment time in the future.');
    }
    if (appointmentType.trim().isEmpty) {
      throw StateError('Select an appointment type.');
    }
    final animal =
        await (db.select(db.animals)..where(
              (item) =>
                  item.id.equals(animalId) &
                  item.clinicId.equals(session.clinic.clinicId) &
                  item.status.equals(AnimalStatuses.active),
            ))
            .getSingleOrNull();
    if (animal == null) {
      throw StateError('Select an active patient from this clinic.');
    }
    if (assignedStaffId != null) {
      final eligible = await eligibleAppointmentStaff();
      if (!eligible.any((staff) => staff.userId == assignedStaffId)) {
        throw StateError('The assigned veterinarian is no longer active.');
      }
    }
    final now = _clock.nowForClinic(session.clinic);
    return db.transaction(() async {
      final appointmentId = await db
          .into(db.appointments)
          .insert(
            AppointmentsCompanion.insert(
              clinicId: Value(session.clinic.clinicId),
              animalId: animalId,
              appointmentDate: scheduledAt,
              purpose: appointmentType.trim(),
              status: const Value(AppointmentStatuses.confirmed),
              assignedStaffId: Value(assignedStaffId),
              notes: Value(_nullIfBlank(notes)),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      final reference =
          'APT-${scheduledAt.year}-${appointmentId.toString().padLeft(5, '0')}';
      await (db.update(db.appointments)
            ..where((item) => item.id.equals(appointmentId)))
          .write(AppointmentsCompanion(reference: Value(reference)));
      for (final days in const [7, 3, 1]) {
        final scheduledFor = scheduledAt.subtract(Duration(days: days));
        await db
            .into(db.appointmentReminders)
            .insert(
              AppointmentRemindersCompanion.insert(
                appointmentId: appointmentId,
                daysBefore: days,
                enabled: Value(enabledReminderDays.contains(days)),
                notificationId: appointmentId * 10 + days,
                scheduledFor: Value(
                  scheduledFor.isAfter(now) ? scheduledFor : null,
                ),
              ),
            );
      }
      await _writeAppointmentAudit(
        session: session,
        appointmentId: appointmentId,
        action: 'appointment.created',
        details: {
          'scheduledAt': scheduledAt.toIso8601String(),
          'type': appointmentType,
        },
        createdAt: now,
      );
      return (db.select(
        db.appointments,
      )..where((item) => item.id.equals(appointmentId))).getSingle();
    });
  }

  Future<Appointment> rescheduleAppointment({
    required UserSession session,
    required int appointmentId,
    required DateTime scheduledAt,
    String? assignedStaffId,
    String? appointmentType,
    String? notes,
    String? reason,
    Set<int>? enabledReminderDays,
  }) async {
    _requireAppointmentPermission(session, Permissions.appointmentsEdit);
    if (scheduledAt.isBefore(_clock.nowForClinic(session.clinic))) {
      throw StateError('Choose an appointment time in the future.');
    }
    final now = _clock.nowForClinic(session.clinic);
    return db.transaction(() async {
      final appointment = await _appointmentForSession(appointmentId, session);
      final currentStatus = AppointmentStatuses.normalize(appointment.status);
      if (currentStatus == AppointmentStatuses.cancelled ||
          currentStatus == AppointmentStatuses.completed) {
        throw StateError('$currentStatus appointments cannot be rescheduled.');
      }
      if (appointment.appointmentDate.isAtSameMomentAs(scheduledAt)) {
        throw StateError(
          'Choose a different date or time to reschedule this appointment.',
        );
      }
      if (assignedStaffId != null) {
        final eligible = await eligibleAppointmentStaff();
        if (!eligible.any((staff) => staff.userId == assignedStaffId)) {
          throw StateError('The assigned veterinarian is no longer active.');
        }
      }
      await (db.update(
        db.appointments,
      )..where((item) => item.id.equals(appointmentId))).write(
        AppointmentsCompanion(
          appointmentDate: Value(scheduledAt),
          assignedStaffId: Value(
            assignedStaffId ?? appointment.assignedStaffId,
          ),
          purpose: Value(
            appointmentType?.trim().isNotEmpty == true
                ? appointmentType!.trim()
                : appointment.purpose,
          ),
          notes: Value(notes == null ? appointment.notes : _nullIfBlank(notes)),
          updatedAt: Value(now),
        ),
      );
      final reminders = await (db.select(
        db.appointmentReminders,
      )..where((item) => item.appointmentId.equals(appointmentId))).get();
      for (final reminder in reminders) {
        final target = scheduledAt.subtract(
          Duration(days: reminder.daysBefore),
        );
        await (db.update(
          db.appointmentReminders,
        )..where((item) => item.id.equals(reminder.id))).write(
          AppointmentRemindersCompanion(
            enabled: Value(
              enabledReminderDays?.contains(reminder.daysBefore) ??
                  reminder.enabled,
            ),
            scheduledFor: Value(
              target.isAfter(now) &&
                      (enabledReminderDays?.contains(reminder.daysBefore) ??
                          reminder.enabled)
                  ? target
                  : null,
            ),
            lastScheduledAt: const Value(null),
          ),
        );
      }
      await _writeAppointmentAudit(
        session: session,
        appointmentId: appointmentId,
        action: 'appointment.rescheduled',
        details: {
          'previous': appointment.appointmentDate.toIso8601String(),
          'next': scheduledAt.toIso8601String(),
          'reason': _nullIfBlank(reason),
          'assignedStaffId': assignedStaffId ?? appointment.assignedStaffId,
          'type': appointmentType ?? appointment.purpose,
        },
        createdAt: now,
      );
      final animal =
          await (db.select(db.animals)
                ..where((item) => item.id.equals(appointment.animalId)))
              .getSingleOrNull();
      await db
          .into(db.clinicActivityEvents)
          .insert(
            ClinicActivityEventsCompanion.insert(
              id: 'appointment-rescheduled:$appointmentId:${now.microsecondsSinceEpoch}',
              clinicId: session.clinic.clinicId,
              type: 'appointmentRescheduled',
              title:
                  'Appointment rescheduled${animal == null ? '' : ' for ${animal.animalName}'}',
              description:
                  '${session.user.fullName} moved the visit from ${DateFormat.yMMMMd().add_jm().format(appointment.appointmentDate)} to ${DateFormat.yMMMMd().add_jm().format(scheduledAt)}.',
              occurredAt: now,
              performedByUserId: Value(session.user.userId),
              relatedEntityType: const Value('Appointment'),
              relatedEntityId: Value(appointmentId.toString()),
              patientId: Value(appointment.animalId),
              module: const Value('Schedule'),
              metadata: Value(
                jsonEncode({
                  'previous': appointment.appointmentDate.toIso8601String(),
                  'next': scheduledAt.toIso8601String(),
                  'changedByName': session.user.fullName,
                  'reason': _nullIfBlank(reason),
                }),
              ),
            ),
          );
      return (db.select(
        db.appointments,
      )..where((item) => item.id.equals(appointmentId))).getSingle();
    });
  }

  Future<void> setAppointmentReminder({
    required UserSession session,
    required int appointmentId,
    required int daysBefore,
    required bool enabled,
  }) async {
    _requireAppointmentPermission(session, Permissions.appointmentsEdit);
    final appointment = await _appointmentForSession(appointmentId, session);
    final now = _clock.nowForClinic(session.clinic);
    final reminder =
        await (db.select(db.appointmentReminders)..where(
              (item) =>
                  item.appointmentId.equals(appointmentId) &
                  item.daysBefore.equals(daysBefore),
            ))
            .getSingleOrNull();
    if (reminder == null) throw StateError('Reminder setting was not found.');
    final target = appointment.appointmentDate.subtract(
      Duration(days: daysBefore),
    );
    await (db.update(
      db.appointmentReminders,
    )..where((item) => item.id.equals(reminder.id))).write(
      AppointmentRemindersCompanion(
        enabled: Value(enabled),
        scheduledFor: Value(enabled && target.isAfter(now) ? target : null),
        lastScheduledAt: const Value(null),
      ),
    );
    await _writeAppointmentAudit(
      session: session,
      appointmentId: appointmentId,
      action: enabled
          ? 'appointment.reminder_enabled'
          : 'appointment.reminder_disabled',
      details: {'daysBefore': daysBefore},
      createdAt: now,
    );
  }

  Future<void> cancelAppointment({
    required UserSession session,
    required int appointmentId,
  }) async {
    _requireAppointmentPermission(session, Permissions.appointmentsCancel);
    final now = _clock.nowForClinic(session.clinic);
    await db.transaction(() async {
      final appointment = await _appointmentForSession(appointmentId, session);
      await (db.update(
        db.appointments,
      )..where((item) => item.id.equals(appointmentId))).write(
        AppointmentsCompanion(
          status: const Value(AppointmentStatuses.cancelled),
          updatedAt: Value(now),
        ),
      );
      await (db.update(
        db.appointmentReminders,
      )..where((item) => item.appointmentId.equals(appointmentId))).write(
        const AppointmentRemindersCompanion(scheduledFor: Value(null)),
      );
      await _writeAppointmentAudit(
        session: session,
        appointmentId: appointmentId,
        action: 'appointment.cancelled',
        details: const {},
        createdAt: now,
      );
      final animal =
          await (db.select(db.animals)
                ..where((item) => item.id.equals(appointment.animalId)))
              .getSingleOrNull();
      await db
          .into(db.clinicActivityEvents)
          .insert(
            ClinicActivityEventsCompanion.insert(
              id: 'appointment-cancelled:$appointmentId:${now.microsecondsSinceEpoch}',
              clinicId: session.clinic.clinicId,
              type: 'appointmentCancelled',
              title:
                  'Visit cancelled${animal == null ? '' : ' for ${animal.animalName}'}',
              description: 'The ${appointment.purpose} visit was cancelled.',
              occurredAt: now,
              performedByUserId: Value(session.user.userId),
              relatedEntityType: const Value('Appointment'),
              relatedEntityId: Value(appointmentId.toString()),
              patientId: Value(appointment.animalId),
              module: const Value('Schedule'),
              metadata: const Value('{}'),
            ),
          );
    });
  }

  Future<void> linkAppointmentConsultation({
    required UserSession session,
    required int appointmentId,
    required int consultationId,
  }) async {
    _requireAppointmentPermission(
      session,
      Permissions.appointmentsStartConsultation,
    );
    final now = _clock.nowForClinic(session.clinic);
    await db.transaction(() async {
      final appointment = await _appointmentForSession(appointmentId, session);
      if (appointment.animalId <= 0) {
        throw StateError('Appointment patient is unavailable.');
      }
      await (db.update(db.appointments)..where(
            (item) =>
                item.id.equals(appointmentId) &
                item.clinicId.equals(session.clinic.clinicId),
          ))
          .write(
            AppointmentsCompanion(
              consultationId: Value(consultationId),
              status: const Value(AppointmentStatuses.completed),
              updatedAt: Value(now),
            ),
          );
      await _writeAppointmentAudit(
        session: session,
        appointmentId: appointmentId,
        action: 'appointment.consultation_linked',
        details: {'consultationId': consultationId},
        createdAt: now,
      );
    });
  }

  Stream<List<Farm>> watchFarms({String? status}) {
    final query = db.select(db.farms)
      ..where((farm) => farm.clinicId.equals(activeClinicId));
    if (status != null) query.where((farm) => farm.status.equals(status));
    query.orderBy([(farm) => OrderingTerm.asc(farm.name)]);
    return query.watch();
  }

  Future<FarmDashboardData?> getFarmDashboard(String farmId) async {
    final farm =
        await (db.select(db.farms)..where(
              (row) =>
                  row.id.equals(farmId) & row.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (farm == null) return null;
    final units =
        await (db.select(db.farmUnits)
              ..where(
                (row) =>
                    row.clinicId.equals(activeClinicId) &
                    row.farmId.equals(farmId),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    final dailyRecords =
        await (db.select(db.farmDailyRecords)
              ..where(
                (row) =>
                    row.clinicId.equals(activeClinicId) &
                    row.farmId.equals(farmId),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.recordDate)]))
            .get();
    return FarmDashboardData(
      farm: farm,
      units: units,
      dailyRecords: dailyRecords,
    );
  }

  Future<Farm> createFarm({
    required UserSession session,
    required String name,
    String? location,
    String? ownerOrganization,
    String? contactNumber,
    String? farmType,
    String? notes,
    required List<String> speciesIds,
    List<String> breedIds = const [],
  }) async {
    _requireFarmPermission(session, Permissions.farmsCreate);
    final normalizedName = name.trim();
    if (normalizedName.length < 2) {
      throw StateError('Enter a farm name with at least two characters.');
    }
    if (speciesIds.isEmpty) {
      throw StateError('Select at least one species kept on this farm.');
    }
    final now = _clock.nowForClinic(session.clinic);
    final farm = FarmsCompanion.insert(
      id: _uuid.v4(),
      clinicId: session.clinic.clinicId,
      name: normalizedName,
      location: Value(_nullIfBlank(location)),
      speciesJson: Value(jsonEncode(speciesIds.toSet().toList()..sort())),
      breedJson: Value(jsonEncode(breedIds.toSet().toList()..sort())),
      ownerOrganization: Value(_nullIfBlank(ownerOrganization)),
      contactNumber: Value(_nullIfBlank(contactNumber)),
      farmType: Value(_nullIfBlank(farmType)),
      notes: Value(_nullIfBlank(notes)),
      createdAt: now,
      createdByUserId: session.user.userId,
      updatedAt: now,
    );
    return db.transaction(() async {
      await db.into(db.farms).insert(farm);
      await _writeFarmAudit(
        session: session,
        action: 'farm.created',
        farmId: farm.id.value,
        details: {'name': normalizedName, 'speciesIds': speciesIds},
        createdAt: now,
      );
      await _writeFarmActivity(
        session: session,
        type: 'farmCreated',
        title: 'Farm created: $normalizedName',
        description:
            'A farm record was created for ${speciesIds.length} species.',
        farmId: farm.id.value,
        occurredAt: now,
      );
      return (db.select(
        db.farms,
      )..where((row) => row.id.equals(farm.id.value))).getSingle();
    });
  }

  Future<Farm> updateFarm({
    required UserSession session,
    required String farmId,
    required String name,
    String? location,
    String? ownerOrganization,
    String? contactNumber,
    String? farmType,
    String? notes,
    required List<String> speciesIds,
    List<String> breedIds = const [],
  }) async {
    _requireFarmPermission(session, Permissions.farmsCreate);
    final farm = await _farmForSession(farmId, session);
    if (name.trim().length < 2 || speciesIds.isEmpty) {
      throw StateError('Enter a farm name and select at least one species.');
    }
    final now = _clock.nowForClinic(session.clinic);
    await (db.update(db.farms)..where((row) => row.id.equals(farm.id))).write(
      FarmsCompanion(
        name: Value(name.trim()),
        location: Value(_nullIfBlank(location)),
        ownerOrganization: Value(_nullIfBlank(ownerOrganization)),
        contactNumber: Value(_nullIfBlank(contactNumber)),
        farmType: Value(_nullIfBlank(farmType)),
        notes: Value(_nullIfBlank(notes)),
        speciesJson: Value(jsonEncode(speciesIds.toSet().toList()..sort())),
        breedJson: Value(jsonEncode(breedIds.toSet().toList()..sort())),
        updatedAt: Value(now),
      ),
    );
    await _writeFarmAudit(
      session: session,
      action: 'farm.updated',
      farmId: farm.id,
      details: {'speciesIds': speciesIds, 'breedIds': breedIds},
      createdAt: now,
    );
    return (db.select(
      db.farms,
    )..where((row) => row.id.equals(farm.id))).getSingle();
  }

  Future<FarmUnit> createFarmUnit({
    required UserSession session,
    required String farmId,
    required String name,
    required String unitType,
    String? speciesId,
    String? breedId,
    String? notes,
    int? capacity,
    int maleCount = 0,
    int femaleCount = 0,
    int unknownCount = 0,
  }) async {
    _requireFarmPermission(session, Permissions.farmUnitsManage);
    if ([maleCount, femaleCount, unknownCount].any((value) => value < 0)) {
      throw StateError('Population counts cannot be negative.');
    }
    final farm = await _farmForSession(farmId, session);
    final population = maleCount + femaleCount + unknownCount;
    if (capacity != null && capacity >= 0 && population > capacity) {
      throw StateError('This population exceeds the unit capacity.');
    }
    final now = _clock.nowForClinic(session.clinic);
    final id = await db
        .into(db.farmUnits)
        .insert(
          FarmUnitsCompanion.insert(
            clinicId: session.clinic.clinicId,
            farmId: farm.id,
            name: name.trim(),
            unitType: Value(_nullIfBlank(unitType) ?? 'Pen'),
            speciesId: Value(_nullIfBlank(speciesId)),
            breedId: Value(_nullIfBlank(breedId)),
            capacity: Value(capacity),
            maleCount: Value(maleCount),
            femaleCount: Value(femaleCount),
            unknownCount: Value(unknownCount),
            notes: Value(_nullIfBlank(notes)),
            createdAt: now,
            createdByUserId: session.user.userId,
            updatedAt: now,
          ),
        );
    await _writeFarmAudit(
      session: session,
      action: 'farm.unit_created',
      farmId: farm.id,
      details: {'unitId': id, 'name': name.trim(), 'unitType': unitType},
      createdAt: now,
    );
    return (db.select(
      db.farmUnits,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<FarmUnit?> getFarmUnit(String farmId, int unitId) {
    return (db.select(db.farmUnits)..where(
          (row) =>
              row.id.equals(unitId) &
              row.farmId.equals(farmId) &
              row.clinicId.equals(activeClinicId),
        ))
        .getSingleOrNull();
  }

  Future<FarmUnit> updateFarmUnit({
    required UserSession session,
    required String farmId,
    required int unitId,
    required String name,
    required String unitType,
    String? speciesId,
    String? breedId,
    int? capacity,
    int maleCount = 0,
    int femaleCount = 0,
    int unknownCount = 0,
    String? notes,
  }) async {
    _requireFarmPermission(session, Permissions.farmUnitsManage);
    await _farmForSession(farmId, session);
    final existing = await getFarmUnit(farmId, unitId);
    if (existing == null) {
      throw StateError('This farm unit is not available in the active clinic.');
    }
    if ([maleCount, femaleCount, unknownCount].any((value) => value < 0)) {
      throw StateError('Population counts cannot be negative.');
    }
    final total = maleCount + femaleCount + unknownCount;
    if (capacity != null && capacity >= 0 && total > capacity) {
      throw StateError('This population exceeds the unit capacity.');
    }
    final now = _clock.nowForClinic(session.clinic);
    await (db.update(
      db.farmUnits,
    )..where((row) => row.id.equals(unitId))).write(
      FarmUnitsCompanion(
        name: Value(name.trim()),
        unitType: Value(_nullIfBlank(unitType) ?? 'Pen'),
        speciesId: Value(_nullIfBlank(speciesId)),
        breedId: Value(_nullIfBlank(breedId)),
        capacity: Value(capacity),
        maleCount: Value(maleCount),
        femaleCount: Value(femaleCount),
        unknownCount: Value(unknownCount),
        notes: Value(_nullIfBlank(notes)),
        updatedAt: Value(now),
      ),
    );
    await _writeFarmAudit(
      session: session,
      action: 'farm.unit_updated',
      farmId: farmId,
      details: {'unitId': unitId, 'population': total},
      createdAt: now,
    );
    return (db.select(
      db.farmUnits,
    )..where((row) => row.id.equals(unitId))).getSingle();
  }

  Future<FarmDailyRecord> saveFarmDailyRecord({
    required UserSession session,
    required String farmId,
    required DateTime recordDate,
    required int openingPopulation,
    int births = 0,
    int purchases = 0,
    int transfersIn = 0,
    int mortality = 0,
    int sales = 0,
    int transfersOut = 0,
    double feedSuppliedKg = 0,
    String? dailyNote,
    String? tasksForTomorrow,
    List<FarmSpeciesMovementInput> speciesMovements = const [],
    String? correctionReason,
    bool finalize = false,
  }) async {
    _requireFarmPermission(
      session,
      finalize ? Permissions.farmDailyFinalize : Permissions.farmDailyRecord,
    );
    final farm = await _farmForSession(farmId, session);
    final values = [
      openingPopulation,
      births,
      purchases,
      transfersIn,
      mortality,
      sales,
      transfersOut,
    ];
    if (values.any((value) => value < 0) || feedSuppliedKg < 0) {
      throw StateError('Daily population and feed values cannot be negative.');
    }
    final speciesIds = <String>{};
    for (final movement in speciesMovements) {
      if (!speciesIds.add(movement.speciesId)) {
        throw StateError(
          'Each species can appear only once in a daily record.',
        );
      }
      if (movement.speciesId.trim().isEmpty ||
          [
            movement.openingPopulation,
            movement.births,
            movement.purchases,
            movement.transfersIn,
            movement.mortality,
            movement.sales,
            movement.transfersOut,
          ].any((value) => value < 0) ||
          movement.closingPopulation < 0) {
        throw StateError(
          'Each species population must reconcile to zero or more animals.',
        );
      }
    }
    final available = openingPopulation + births + purchases + transfersIn;
    final removed = mortality + sales + transfersOut;
    if (removed > available) {
      throw StateError(
        'Mortality, sales and transfers cannot exceed population.',
      );
    }
    final localDate = DateTime(
      recordDate.year,
      recordDate.month,
      recordDate.day,
    );
    final now = _clock.nowForClinic(session.clinic);
    return db.transaction(() async {
      final existing =
          await (db.select(db.farmDailyRecords)..where(
                (row) =>
                    row.clinicId.equals(session.clinic.clinicId) &
                    row.farmId.equals(farm.id) &
                    row.recordDate.equals(localDate),
              ))
              .getSingleOrNull();
      final isCorrection = existing?.status == 'Finalized';
      if (isCorrection && _nullIfBlank(correctionReason) == null) {
        throw StateError('Enter a reason to correct this finalized record.');
      }
      final effectiveMovements = speciesMovements;
      final closing = effectiveMovements.isEmpty
          ? available - removed
          : effectiveMovements.fold<int>(
              0,
              (total, item) => total + item.closingPopulation,
            );
      final effectiveOpening = effectiveMovements.isEmpty
          ? openingPopulation
          : effectiveMovements.fold<int>(
              0,
              (total, item) => total + item.openingPopulation,
            );
      final effectiveBirths = effectiveMovements.isEmpty
          ? births
          : effectiveMovements.fold<int>(
              0,
              (total, item) => total + item.births,
            );
      final effectivePurchases = effectiveMovements.isEmpty
          ? purchases
          : effectiveMovements.fold<int>(
              0,
              (total, item) => total + item.purchases,
            );
      final effectiveTransfersIn = effectiveMovements.isEmpty
          ? transfersIn
          : effectiveMovements.fold<int>(
              0,
              (total, item) => total + item.transfersIn,
            );
      final effectiveMortality = effectiveMovements.isEmpty
          ? mortality
          : effectiveMovements.fold<int>(
              0,
              (total, item) => total + item.mortality,
            );
      final effectiveSales = effectiveMovements.isEmpty
          ? sales
          : effectiveMovements.fold<int>(
              0,
              (total, item) => total + item.sales,
            );
      final effectiveTransfersOut = effectiveMovements.isEmpty
          ? transfersOut
          : effectiveMovements.fold<int>(
              0,
              (total, item) => total + item.transfersOut,
            );
      final recordId = existing?.id ?? _uuid.v4();
      final originalSnapshot = isCorrection
          ? jsonEncode({
              'record': {
                'openingPopulation': existing!.openingPopulation,
                'births': existing.births,
                'purchases': existing.purchases,
                'transfersIn': existing.transfersIn,
                'mortality': existing.mortality,
                'sales': existing.sales,
                'transfersOut': existing.transfersOut,
                'closingPopulation': existing.closingPopulation,
                'feedSuppliedKg': existing.feedSuppliedKg,
                'dailyNote': existing.dailyNote,
              },
              'preservedAt': now.toIso8601String(),
            })
          : existing?.originalSnapshotJson;
      final entry = FarmDailyRecordsCompanion(
        id: Value(recordId),
        clinicId: Value(session.clinic.clinicId),
        farmId: Value(farm.id),
        recordDate: Value(localDate),
        status: Value(finalize ? 'Finalized' : 'Draft'),
        openingPopulation: Value(effectiveOpening),
        births: Value(effectiveBirths),
        purchases: Value(effectivePurchases),
        transfersIn: Value(effectiveTransfersIn),
        mortality: Value(effectiveMortality),
        sales: Value(effectiveSales),
        transfersOut: Value(effectiveTransfersOut),
        closingPopulation: Value(closing),
        feedSuppliedKg: Value(feedSuppliedKg),
        dailyNote: Value(_nullIfBlank(dailyNote)),
        tasksForTomorrow: Value(_nullIfBlank(tasksForTomorrow)),
        correctionReason: Value(_nullIfBlank(correctionReason)),
        originalSnapshotJson: Value(originalSnapshot),
        lastEditedByUserId: Value(session.user.userId),
        finalizedAt: Value(finalize ? now : null),
        finalizedByUserId: Value(finalize ? session.user.userId : null),
        createdAt: Value(existing?.createdAt ?? now),
        createdByUserId: Value(
          existing?.createdByUserId ?? session.user.userId,
        ),
        updatedAt: Value(now),
      );
      if (existing == null) {
        await db.into(db.farmDailyRecords).insert(entry);
      } else {
        await (db.update(
          db.farmDailyRecords,
        )..where((row) => row.id.equals(recordId))).write(entry);
      }
      if (effectiveMovements.isNotEmpty) {
        await (db.delete(
          db.farmSpeciesPopulationMovements,
        )..where((row) => row.dailyRecordId.equals(recordId))).go();
        for (final movement in effectiveMovements) {
          await db
              .into(db.farmSpeciesPopulationMovements)
              .insert(
                FarmSpeciesPopulationMovementsCompanion.insert(
                  clinicId: session.clinic.clinicId,
                  farmId: farm.id,
                  dailyRecordId: recordId,
                  speciesId: movement.speciesId,
                  openingPopulation: Value(movement.openingPopulation),
                  births: Value(movement.births),
                  purchases: Value(movement.purchases),
                  transfersIn: Value(movement.transfersIn),
                  mortality: Value(movement.mortality),
                  sales: Value(movement.sales),
                  transfersOut: Value(movement.transfersOut),
                  closingPopulation: Value(movement.closingPopulation),
                ),
              );
        }
      }
      await _writeFarmAudit(
        session: session,
        action: isCorrection
            ? 'farm.daily_record_corrected'
            : finalize
            ? 'farm.daily_record_finalized'
            : 'farm.daily_record_saved',
        farmId: farm.id,
        details: {
          'dailyRecordId': recordId,
          'recordDate': localDate.toIso8601String(),
          'closingPopulation': closing,
          if (isCorrection) 'correctionReason': correctionReason,
        },
        createdAt: now,
      );
      if (finalize) {
        await _writeFarmActivity(
          session: session,
          type: 'farmDailyRecordFinalized',
          title: 'Daily farm record completed for ${farm.name}',
          description:
              '$closing animals - $mortality mortality - ${feedSuppliedKg.toStringAsFixed(1)} kg feed supplied.',
          farmId: farm.id,
          occurredAt: now,
          relatedDailyRecordId: recordId,
        );
      }
      return (db.select(
        db.farmDailyRecords,
      )..where((row) => row.id.equals(recordId))).getSingle();
    });
  }

  Future<FarmDailyRecordDetail?> getFarmDailyRecordDetail({
    required String farmId,
    required String recordId,
  }) async {
    final farm =
        await (db.select(db.farms)..where(
              (row) =>
                  row.id.equals(farmId) & row.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (farm == null) return null;
    final record =
        await (db.select(db.farmDailyRecords)..where(
              (row) =>
                  row.id.equals(recordId) &
                  row.farmId.equals(farmId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (record == null) return null;
    final units =
        await (db.select(db.farmUnits)..where(
              (row) =>
                  row.farmId.equals(farmId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .get();
    final speciesMovements =
        await (db.select(db.farmSpeciesPopulationMovements)..where(
              (row) =>
                  row.dailyRecordId.equals(recordId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .get();
    final mortalityRecords =
        await (db.select(db.farmMortalityRecords)..where(
              (row) =>
                  row.dailyRecordId.equals(recordId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .get();
    final feedRecords =
        await (db.select(db.farmFeedRecords)..where(
              (row) =>
                  row.dailyRecordId.equals(recordId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .get();
    final events =
        await (db.select(db.farmEvents)..where(
              (row) =>
                  row.dailyRecordId.equals(recordId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .get();
    final reproductionRecords =
        await (db.select(db.farmReproductionRecords)..where(
              (row) =>
                  row.farmId.equals(farmId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .get();
    final healthRecords =
        await (db.select(db.farmHealthRecords)..where(
              (row) =>
                  row.dailyRecordId.equals(recordId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .get();
    return FarmDailyRecordDetail(
      farm: farm,
      record: record,
      units: units,
      speciesMovements: speciesMovements,
      mortalityRecords: mortalityRecords,
      feedRecords: feedRecords,
      events: events,
      reproductionRecords: reproductionRecords,
      healthRecords: healthRecords,
    );
  }

  Future<FarmDailyRecord?> getFarmDailyRecordForDate(
    String farmId,
    DateTime date,
  ) {
    final localDate = DateTime(date.year, date.month, date.day);
    return (db.select(db.farmDailyRecords)..where(
          (row) =>
              row.farmId.equals(farmId) &
              row.clinicId.equals(activeClinicId) &
              row.recordDate.equals(localDate),
        ))
        .getSingleOrNull();
  }

  Future<List<FarmSpeciesPopulationMovement>> getFarmSpeciesMovementsForRecord(
    String recordId,
  ) {
    return (db.select(db.farmSpeciesPopulationMovements)
          ..where(
            (row) =>
                row.dailyRecordId.equals(recordId) &
                row.clinicId.equals(activeClinicId),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.speciesId)]))
        .get();
  }

  Future<void> recordFarmMortality({
    required UserSession session,
    required String farmId,
    required String dailyRecordId,
    required int numberDead,
    String? speciesId,
    int? farmUnitId,
    String suspectedCause = 'Unknown',
    String? notes,
  }) async {
    _requireFarmPermission(session, Permissions.farmMortalityRecord);
    if (numberDead <= 0) throw StateError('Enter at least one mortality.');
    final farm = await _farmForSession(farmId, session);
    final record = await _farmDailyRecordForSession(
      dailyRecordId,
      session,
      farm.id,
    );
    if (record.status == 'Finalized') {
      throw StateError(
        'Amend the finalized daily record before adding mortality.',
      );
    }
    if (record.openingPopulation +
            record.births +
            record.purchases +
            record.transfersIn -
            record.mortality -
            record.sales -
            record.transfersOut <
        numberDead) {
      throw StateError('Mortality cannot exceed available animals.');
    }
    final now = _clock.nowForClinic(session.clinic);
    await db.transaction(() async {
      await db
          .into(db.farmMortalityRecords)
          .insert(
            FarmMortalityRecordsCompanion.insert(
              clinicId: session.clinic.clinicId,
              farmId: farm.id,
              dailyRecordId: record.id,
              farmUnitId: Value(farmUnitId),
              occurredAt: now,
              speciesId: Value(_nullIfBlank(speciesId)),
              numberDead: numberDead,
              suspectedCause: Value(_nullIfBlank(suspectedCause) ?? 'Unknown'),
              notes: Value(_nullIfBlank(notes)),
              recordedByUserId: session.user.userId,
            ),
          );
      final updatedMortality = record.mortality + numberDead;
      final closing =
          record.openingPopulation +
          record.births +
          record.purchases +
          record.transfersIn -
          updatedMortality -
          record.sales -
          record.transfersOut;
      await (db.update(
        db.farmDailyRecords,
      )..where((row) => row.id.equals(record.id))).write(
        FarmDailyRecordsCompanion(
          mortality: Value(updatedMortality),
          closingPopulation: Value(closing),
          updatedAt: Value(now),
        ),
      );
      await _writeFarmAudit(
        session: session,
        action: 'farm.mortality_recorded',
        farmId: farm.id,
        details: {
          'dailyRecordId': record.id,
          'numberDead': numberDead,
          'cause': suspectedCause,
        },
        createdAt: now,
      );
    });
  }

  Future<Farm> _farmForSession(String farmId, UserSession session) async {
    _ensureFarmSession(session);
    final farm =
        await (db.select(db.farms)..where(
              (row) =>
                  row.id.equals(farmId) &
                  row.clinicId.equals(session.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (farm == null) {
      throw StateError('Farm record not found in the active clinic.');
    }
    return farm;
  }

  Future<FarmDailyRecord> _farmDailyRecordForSession(
    String recordId,
    UserSession session,
    String farmId,
  ) async {
    final record =
        await (db.select(db.farmDailyRecords)..where(
              (row) =>
                  row.id.equals(recordId) &
                  row.farmId.equals(farmId) &
                  row.clinicId.equals(session.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (record == null) throw StateError('Daily farm record not found.');
    return record;
  }

  void _ensureFarmSession(UserSession session) {
    if (session.clinic.clinicId != activeClinicId) {
      throw StateError('The active clinic changed. Reopen Farm Records.');
    }
  }

  void _requireFarmPermission(UserSession session, String permission) {
    _ensureFarmSession(session);
    if (!session.can(permission)) {
      throw StateError('You do not have permission to manage Farm Records.');
    }
  }

  Future<void> _writeFarmAudit({
    required UserSession session,
    required String action,
    required String farmId,
    required Map<String, Object?> details,
    required DateTime createdAt,
  }) => _writeAudit(
    clinicId: session.clinic.clinicId,
    userId: session.user.userId,
    action: action,
    entityType: 'Farm',
    entityId: farmId,
    details: details,
    createdAt: createdAt,
  );

  Future<void> _writeFarmActivity({
    required UserSession session,
    required String type,
    required String title,
    required String description,
    required String farmId,
    required DateTime occurredAt,
    String? relatedDailyRecordId,
  }) => db
      .into(db.clinicActivityEvents)
      .insert(
        ClinicActivityEventsCompanion.insert(
          id: 'farm:$type:$farmId:${occurredAt.microsecondsSinceEpoch}',
          clinicId: session.clinic.clinicId,
          type: type,
          title: title,
          description: description,
          occurredAt: occurredAt,
          performedByUserId: Value(session.user.userId),
          relatedEntityType: const Value('Farm'),
          relatedEntityId: Value(farmId),
          module: const Value('Farm Records'),
          metadata: Value(jsonEncode({'dailyRecordId': relatedDailyRecordId})),
        ),
      );

  Future<Appointment> _appointmentForSession(
    int appointmentId,
    UserSession session,
  ) async {
    if (session.clinic.clinicId != activeClinicId) {
      throw StateError('The active clinic changed. Reopen the appointment.');
    }
    final appointment =
        await (db.select(db.appointments)..where(
              (item) =>
                  item.id.equals(appointmentId) &
                  item.clinicId.equals(session.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (appointment == null) throw StateError('Appointment record not found.');
    return appointment;
  }

  void _requireAppointmentPermission(UserSession session, String permission) {
    if (session.clinic.clinicId != activeClinicId || !session.can(permission)) {
      throw StateError('You do not have permission to manage appointments.');
    }
  }

  Future<void> _writeAppointmentAudit({
    required UserSession session,
    required int appointmentId,
    required String action,
    required Map<String, Object?> details,
    required DateTime createdAt,
  }) => db
      .into(db.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          clinicId: Value(session.clinic.clinicId),
          userId: Value(session.user.userId),
          action: action,
          entityType: const Value('Appointment'),
          entityId: Value(appointmentId.toString()),
          details: Value(jsonEncode(details)),
          createdAt: createdAt,
        ),
      );

  String? _nullIfBlank(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _writeAudit({
    required String clinicId,
    required String? userId,
    required String action,
    required String entityType,
    String? entityId,
    required Map<String, Object?> details,
    required DateTime createdAt,
  }) => db
      .into(db.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          clinicId: Value(clinicId),
          userId: Value(userId),
          action: action,
          entityType: Value(entityType),
          entityId: Value(entityId),
          details: Value(jsonEncode(details)),
          createdAt: createdAt,
        ),
      );

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

  Future<int> recordVaccination({
    required UserSession session,
    required int animalId,
    required String protocolId,
    required DateTime dateGiven,
    required DateTime nextDueDate,
    required VaccineRoute route,
    String? batchNumber,
    String? manufacturer,
    String? dose,
    String? notes,
    int? scheduledVaccinationId,
  }) async {
    if (!session.can(Permissions.vaccinationsAdd)) {
      throw StateError('You do not have permission to record vaccinations.');
    }
    await _requireActiveFeature(AveraFeature.vaccinations);
    if (session.clinic.clinicId != activeClinicId) {
      throw StateError('Your selected clinic changed. Please try again.');
    }
    final animal =
        await (db.select(db.animals)..where(
              (row) =>
                  row.id.equals(animalId) &
                  row.clinicId.equals(session.clinic.clinicId) &
                  row.status.equals(AnimalStatuses.active),
            ))
            .getSingleOrNull();
    if (animal == null) {
      throw StateError('Select an active patient from the current clinic.');
    }
    final species = VaccineCatalogue.speciesForLegacyPatient(animal.species);
    final protocol = VaccineCatalogue.byId(protocolId);
    if (species == null) {
      throw StateError(
        'Map this patient\'s legacy species before recording a vaccination.',
      );
    }
    if (protocol == null || protocol.speciesId != species.id) {
      throw StateError(
        'This vaccine is not compatible with ${animal.species}.',
      );
    }
    if (!protocol.routes.contains(route)) {
      throw StateError('Select a route approved for this vaccine protocol.');
    }
    final now = _clock.nowForClinic(session.clinic);
    if (dateGiven.isAfter(now.add(const Duration(days: 1)))) {
      throw StateError('Date given cannot be in the future.');
    }
    if (nextDueDate.isBefore(dateGiven)) {
      throw StateError('Suggested due date cannot be before the date given.');
    }
    return db.transaction(() async {
      if (scheduledVaccinationId != null) {
        final scheduled =
            await (db.select(db.vaccinations)..where(
                  (row) =>
                      row.id.equals(scheduledVaccinationId) &
                      row.clinicId.equals(session.clinic.clinicId) &
                      row.animalId.equals(animalId),
                ))
                .getSingleOrNull();
        if (scheduled == null || scheduled.vaccine != protocol.name) {
          throw StateError(
            'This scheduled vaccination is no longer available.',
          );
        }
        final existingDose =
            await (db.select(db.vaccinations)..where(
                  (row) =>
                      row.sourceVaccinationId.equals(scheduledVaccinationId),
                ))
                .getSingleOrNull();
        if (existingDose != null) {
          throw StateError(
            'This scheduled vaccination has already been recorded.',
          );
        }
      }
      final id = await db
          .into(db.vaccinations)
          .insert(
            VaccinationsCompanion.insert(
              clinicId: Value(session.clinic.clinicId),
              animalId: animalId,
              vaccine: protocol.name,
              batchNumber: Value(_nullIfBlank(batchNumber)),
              manufacturer: Value(_nullIfBlank(manufacturer)),
              dose: Value(_nullIfBlank(dose)),
              route: Value(route.label),
              dateGiven: dateGiven,
              nextDueDate: Value(nextDueDate),
              administeredBy: Value(session.user.fullName),
              veterinarian: Value(session.user.fullName),
              notes: Value(_nullIfBlank(notes)),
              reminderStatus: const Value('Pending'),
              status: const Value('Completed'),
              sourceVaccinationId: Value(scheduledVaccinationId),
            ),
          );
      if (scheduledVaccinationId != null) {
        await (db.update(
          db.vaccinations,
        )..where((row) => row.id.equals(scheduledVaccinationId))).write(
          const VaccinationsCompanion(status: Value('Scheduled Dose Recorded')),
        );
      }
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(session.clinic.clinicId),
              userId: Value(session.user.userId),
              action: 'vaccination.recorded',
              entityType: const Value('Vaccination'),
              entityId: Value(id.toString()),
              details: Value(
                jsonEncode({
                  'animalId': animalId,
                  'protocolId': protocol.id,
                  'speciesId': species.id,
                  'route': route.label,
                  'nextDueDate': nextDueDate.toIso8601String(),
                  'scheduledVaccinationId': scheduledVaccinationId,
                }),
              ),
              createdAt: now,
            ),
          );
      await db
          .into(db.clinicActivityEvents)
          .insert(
            ClinicActivityEventsCompanion.insert(
              id: 'vaccination-recorded:$id',
              clinicId: session.clinic.clinicId,
              type: 'vaccinationRecorded',
              title: '${protocol.name} recorded for ${animal.animalName}',
              description: scheduledVaccinationId == null
                  ? '${session.user.fullName} recorded ${protocol.name}.'
                  : '${session.user.fullName} administered the scheduled dose.',
              occurredAt: now,
              performedByUserId: Value(session.user.userId),
              relatedEntityType: const Value('Vaccination'),
              relatedEntityId: Value(id.toString()),
              patientId: Value(animalId),
              module: const Value('Vaccinations'),
              metadata: Value(
                jsonEncode({
                  'vaccine': protocol.name,
                  'scheduledVaccinationId': scheduledVaccinationId,
                }),
              ),
            ),
          );
      return id;
    });
  }

  Stream<List<Notification>> watchNotifications() =>
      (db.select(db.notifications)
            ..where(
              (n) =>
                  n.clinicId.equals(activeClinicId) &
                  n.status.isNotValue(InAppNotificationStatus.dismissed.name),
            )
            ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
          .watch();

  Stream<List<ClinicActivityTimelineEvent>> watchClinicActivity({
    int limit = 50,
  }) =>
      (db.select(db.clinicActivityEvents)
            ..where((event) => event.clinicId.equals(activeClinicId))
            ..orderBy([(event) => OrderingTerm.desc(event.occurredAt)])
            ..limit(limit))
          .watch()
          .map(
            (events) => events
                .map(
                  (event) => ClinicActivityTimelineEvent(
                    id: event.id,
                    clinicId: event.clinicId,
                    type: event.type,
                    title: event.title,
                    description: event.description,
                    occurredAt: event.occurredAt,
                    performedByUserId: event.performedByUserId,
                    relatedEntityType: event.relatedEntityType,
                    relatedEntityId: event.relatedEntityId,
                    patientId: event.patientId,
                    module: event.module,
                    metadata: event.metadata,
                  ),
                )
                .toList(growable: false),
          );

  Future<List<ClinicActivityTimelineEvent>> getClinicActivityPage({
    int limit = 50,
    int offset = 0,
    DateTime? from,
    DateTime? until,
    String? module,
    String? performedByUserId,
    String? search,
  }) async {
    final normalizedSearch = search?.trim().toLowerCase() ?? '';
    final query = db.select(db.clinicActivityEvents)
      ..where((event) {
        var expression = event.clinicId.equals(activeClinicId);
        if (from != null) {
          expression &= event.occurredAt.isBiggerOrEqualValue(from);
        }
        if (until != null) {
          expression &= event.occurredAt.isSmallerThanValue(until);
        }
        if (module != null && module.isNotEmpty) {
          expression &= event.module.equals(module);
        }
        if (performedByUserId != null && performedByUserId.isNotEmpty) {
          expression &= event.performedByUserId.equals(performedByUserId);
        }
        if (normalizedSearch.isNotEmpty) {
          final pattern = '%$normalizedSearch%';
          expression &=
              event.title.like(pattern) | event.description.like(pattern);
        }
        return expression;
      })
      ..orderBy([(event) => OrderingTerm.desc(event.occurredAt)])
      ..limit(limit, offset: offset);
    final events = await query.get();
    return events.map(_toTimelineEvent).toList(growable: false);
  }

  Future<List<AppointmentRescheduleRecord>> getAppointmentRescheduleHistory(
    int appointmentId,
  ) async {
    final appointment =
        await (db.select(db.appointments)..where(
              (row) =>
                  row.id.equals(appointmentId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (appointment == null) return const [];
    final logs =
        await (db.select(db.auditLogs)
              ..where(
                (row) =>
                    row.clinicId.equals(activeClinicId) &
                    row.entityType.equals('Appointment') &
                    row.entityId.equals(appointmentId.toString()) &
                    row.action.equals('appointment.rescheduled'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    final history = <AppointmentRescheduleRecord>[];
    for (final log in logs) {
      try {
        final data = jsonDecode(log.details ?? '{}') as Map<String, dynamic>;
        final previous = DateTime.tryParse(data['previous'] as String? ?? '');
        final next = DateTime.tryParse(data['next'] as String? ?? '');
        if (previous == null || next == null) continue;
        final user = log.userId == null
            ? null
            : await (db.select(db.appUsers)..where(
                    (row) =>
                        row.userId.equals(log.userId!) &
                        row.clinicId.equals(activeClinicId),
                  ))
                  .getSingleOrNull();
        history.add(
          AppointmentRescheduleRecord(
            previousDate: previous,
            newDate: next,
            changedAt: log.createdAt,
            changedByName: user?.fullName ?? data['changedByName'] as String?,
            reason: data['reason'] as String?,
          ),
        );
      } on FormatException {
        // Old audit rows can be incomplete; keep their appointment usable.
      }
    }
    return history;
  }

  ClinicActivityTimelineEvent _toTimelineEvent(ClinicActivityEvent event) =>
      ClinicActivityTimelineEvent(
        id: event.id,
        clinicId: event.clinicId,
        type: event.type,
        title: event.title,
        description: event.description,
        occurredAt: event.occurredAt,
        performedByUserId: event.performedByUserId,
        relatedEntityType: event.relatedEntityType,
        relatedEntityId: event.relatedEntityId,
        patientId: event.patientId,
        module: event.module,
        metadata: event.metadata,
      );

  Future<ClinicVaccinationRecord?> getClinicVaccinationRecord(
    int vaccinationId,
  ) async {
    final query =
        db.select(db.vaccinations).join([
          innerJoin(
            db.animals,
            db.animals.id.equalsExp(db.vaccinations.animalId),
          ),
          innerJoin(db.owners, db.owners.id.equalsExp(db.animals.ownerId)),
        ])..where(
          db.vaccinations.id.equals(vaccinationId) &
              db.vaccinations.clinicId.equals(activeClinicId),
        );
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return ClinicVaccinationRecord(
      vaccination: row.readTable(db.vaccinations),
      animal: row.readTable(db.animals),
      owner: row.readTable(db.owners),
    );
  }

  Future<ClinicVaccinationRecord?> getRecordedDoseForSchedule(
    int scheduleVaccinationId,
  ) async {
    final dose =
        await (db.select(db.vaccinations)..where(
              (row) =>
                  row.sourceVaccinationId.equals(scheduleVaccinationId) &
                  row.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    return dose == null ? null : getClinicVaccinationRecord(dose.id);
  }

  Future<void> markNotificationRead({
    required UserSession session,
    required int notificationId,
  }) => _changeNotificationStatus(
    session: session,
    notificationId: notificationId,
    status: InAppNotificationStatus.read,
  );

  Future<void> markNotificationReviewed({
    required UserSession session,
    required int notificationId,
  }) => _changeNotificationStatus(
    session: session,
    notificationId: notificationId,
    status: InAppNotificationStatus.reviewed,
  );

  Future<void> markNotificationUnread({
    required UserSession session,
    required int notificationId,
  }) => _changeNotificationStatus(
    session: session,
    notificationId: notificationId,
    status: InAppNotificationStatus.unread,
  );

  Future<void> dismissNotification({
    required UserSession session,
    required int notificationId,
  }) => _changeNotificationStatus(
    session: session,
    notificationId: notificationId,
    status: InAppNotificationStatus.dismissed,
  );

  Future<void> dismissAllNotifications({required UserSession session}) async {
    if (session.clinic.clinicId != activeClinicId) {
      throw StateError('Your selected clinic changed. Please try again.');
    }
    final now = _clock.nowForClinic(session.clinic);
    await db.transaction(() async {
      await (db.update(db.notifications)..where(
            (n) =>
                n.clinicId.equals(activeClinicId) &
                n.status.isNotValue(InAppNotificationStatus.dismissed.name),
          ))
          .write(
            NotificationsCompanion(
              status: const Value('dismissed'),
              dismissedAt: Value(now),
            ),
          );
      await _writeAudit(
        clinicId: activeClinicId,
        userId: session.user.userId,
        action: 'notification.clear_all',
        entityType: 'Notification',
        details: const {'scope': 'inbox'},
        createdAt: now,
      );
    });
  }

  Future<void> _changeNotificationStatus({
    required UserSession session,
    required int notificationId,
    required InAppNotificationStatus status,
  }) async {
    if (session.clinic.clinicId != activeClinicId) {
      throw StateError('Your selected clinic changed. Please try again.');
    }
    final item =
        await (db.select(db.notifications)..where(
              (n) =>
                  n.id.equals(notificationId) &
                  n.clinicId.equals(activeClinicId),
            ))
            .getSingleOrNull();
    if (item == null) {
      throw StateError('This notification is no longer available.');
    }
    final now = _clock.nowForClinic(session.clinic);
    await db.transaction(() async {
      await (db.update(
        db.notifications,
      )..where((n) => n.id.equals(item.id))).write(
        NotificationsCompanion(
          isRead: Value(status != InAppNotificationStatus.unread),
          status: Value(status.storageValue),
          readAt: status == InAppNotificationStatus.read
              ? Value(now)
              : const Value.absent(),
          reviewedAt: status == InAppNotificationStatus.reviewed
              ? Value(now)
              : const Value.absent(),
          dismissedAt: status == InAppNotificationStatus.dismissed
              ? Value(now)
              : const Value.absent(),
        ),
      );
      // Reading an inbox item is routine UI state. Keep audit history focused
      // on reviewed or dismissed notifications and their grouped clear action.
      if (status != InAppNotificationStatus.read) {
        await _writeAudit(
          clinicId: activeClinicId,
          userId: session.user.userId,
          action: 'notification.${status.storageValue}',
          entityType: 'Notification',
          entityId: item.id.toString(),
          details: {'type': item.type, 'title': item.title},
          createdAt: now,
        );
      }
    });
  }

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
                  v.nextDueDate.isSmallerThanValue(endOfDay),
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
    final recentActivityRows =
        await (db.select(db.clinicActivityEvents)
              ..where((event) => event.clinicId.equals(activeClinicId))
              ..orderBy([(event) => OrderingTerm.desc(event.occurredAt)])
              ..limit(6))
            .get();
    final unreadNotifications =
        await (db.select(db.notifications)..where(
              (n) =>
                  n.clinicId.equals(activeClinicId) &
                  n.status.equals(InAppNotificationStatus.unread.name),
            ))
            .get();

    return DashboardStats(
      totalAnimals: animalsCount,
      todaysConsultations: todaysVisits.length,
      appointmentsToday: appointmentsToday.length,
      vaccinationsDue: vaccinationsDue
          .where(
            (item) =>
                isVaccinationActionRequired(item.status, item.nextDueDate, now),
          )
          .length,
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
      recentActivity: recentActivityRows
          .map(
            (event) => ClinicActivityTimelineEvent(
              id: event.id,
              clinicId: event.clinicId,
              type: event.type,
              title: event.title,
              description: event.description,
              occurredAt: event.occurredAt,
              performedByUserId: event.performedByUserId,
              relatedEntityType: event.relatedEntityType,
              relatedEntityId: event.relatedEntityId,
              patientId: event.patientId,
              module: event.module,
              metadata: event.metadata,
            ),
          )
          .toList(growable: false),
      unreadNotifications: unreadNotifications.length,
    );
  }

  /// Returns an informational preview. It never reserves or consumes a value.
  Future<HospitalNumberPreview> previewHospitalNumber({
    String? clinicId,
  }) async {
    final targetClinicId = clinicId ?? activeClinicId;
    return db.transaction(() async {
      final clinic = await _clinicForNumbering(targetClinicId);
      final configuredClinic = await _ensurePatientNumberingConfiguration(
        clinic,
      );
      final now = _clock.nowForClinic(configuredClinic);
      final year = now.year;
      final key = configuredClinic.patientNumberResetYearly
          ? year.toString()
          : '0';
      final sequence =
          await (db.select(db.clinicNumberSequences)..where(
                (item) =>
                    item.clinicId.equals(targetClinicId) &
                    item.sequenceType.equals('patient') &
                    item.sequenceKey.equals(key),
              ))
              .getSingleOrNull();
      final current =
          sequence?.currentValue ??
          await _legacyPatientSequenceFloor(
            clinicId: targetClinicId,
            prefix: configuredClinic.patientNumberPrefix!,
            registrationYear: configuredClinic.patientNumberResetYearly
                ? year
                : null,
          );
      return HospitalNumberPreview(
        clinicId: targetClinicId,
        prefix: configuredClinic.patientNumberPrefix!,
        year: year,
        sequence: current + 1,
        sequenceLength: configuredClinic.patientNumberSequenceLength,
        prefixRequiresReview: !configuredClinic.patientNumberPrefixReviewed,
      );
    });
  }

  /// Compatibility for callers that only need the preview string. New patient
  /// registrations must call [registerAnimalWithHospitalNumber] instead.
  Future<String> nextHospitalNumber() async =>
      (await previewHospitalNumber()).hospitalNumber;

  /// Assigns a clinic-scoped number and inserts the owner and patient in one
  /// transaction. Reusing a successful submission id returns its first result.
  Future<AssignedHospitalNumber> registerAnimalWithHospitalNumber({
    required UserSession session,
    required OwnersCompanion owner,
    required AnimalsCompanion animal,
    required String submissionId,
    String? speciesId,
    String? breedId,
  }) async {
    await _requireActiveFeature(AveraFeature.patientRecords);
    if (!session.can(Permissions.patientsCreate)) {
      throw StateError('You do not have permission to register patients.');
    }
    if (session.clinic.clinicId != activeClinicId) {
      throw StateError('Your selected clinic changed. Please try again.');
    }
    if (submissionId.trim().isEmpty) {
      throw ArgumentError.value(submissionId, 'submissionId');
    }
    if (!animal.animalName.present ||
        !animal.species.present ||
        (animal.weight.present && (animal.weight.value ?? 0) < 0) ||
        animal.animalName.value.trim().isEmpty ||
        animal.species.value.trim().isEmpty) {
      throw ArgumentError(
        'Patient name, species and a valid weight are required.',
      );
    }
    _validateCataloguedSpeciesBreed(
      animal: animal,
      speciesId: speciesId,
      breedId: breedId,
    );

    return db.transaction(() async {
      final existing =
          await (db.select(db.animals)..where(
                (item) =>
                    item.clinicId.equals(activeClinicId) &
                    item.registrationSubmissionId.equals(submissionId),
              ))
              .getSingleOrNull();
      if (existing != null) {
        return AssignedHospitalNumber(
          patientId: existing.id,
          hospitalNumber: existing.hospitalNumber,
          submissionId: submissionId,
        );
      }

      final clinic = await _ensurePatientNumberingConfiguration(
        await _clinicForNumbering(activeClinicId),
      );
      final now = _clock.nowForClinic(clinic);
      final year = now.year;
      final sequenceKey = clinic.patientNumberResetYearly ? '$year' : '0';
      final sequence =
          await (db.select(db.clinicNumberSequences)..where(
                (item) =>
                    item.clinicId.equals(activeClinicId) &
                    item.sequenceType.equals('patient') &
                    item.sequenceKey.equals(sequenceKey),
              ))
              .getSingleOrNull();
      final nextValue =
          (sequence?.currentValue ??
              await _legacyPatientSequenceFloor(
                clinicId: activeClinicId,
                prefix: clinic.patientNumberPrefix!,
                registrationYear: clinic.patientNumberResetYearly ? year : null,
              )) +
          1;

      if (sequence == null) {
        await db
            .into(db.clinicNumberSequences)
            .insert(
              ClinicNumberSequencesCompanion.insert(
                clinicId: activeClinicId,
                sequenceType: 'patient',
                sequenceKey: sequenceKey,
                currentValue: Value(nextValue),
                sequenceLength: Value(clinic.patientNumberSequenceLength),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (db.update(
          db.clinicNumberSequences,
        )..where((item) => item.id.equals(sequence.id))).write(
          ClinicNumberSequencesCompanion(
            currentValue: Value(nextValue),
            sequenceLength: Value(clinic.patientNumberSequenceLength),
            updatedAt: Value(now),
          ),
        );
      }

      final hospitalNumber = formatHospitalNumber(
        prefix: clinic.patientNumberPrefix!,
        year: year,
        sequence: nextValue,
        sequenceLength: clinic.patientNumberSequenceLength,
      );
      final ownerId = await db
          .into(db.owners)
          .insert(owner.copyWith(clinicId: Value(activeClinicId)));
      final patientId = await db
          .into(db.animals)
          .insert(
            animal.copyWith(
              clinicId: Value(activeClinicId),
              hospitalNumber: Value(hospitalNumber),
              ownerId: Value(ownerId),
              dateRegistered: Value(now),
              numberAssignmentStatus: Value(
                NumberAssignmentStatus.assigned.databaseValue,
              ),
              registrationYear: Value(year),
              registrationSubmissionId: Value(submissionId),
            ),
          );
      await _writeNumberingAudit(
        clinicId: activeClinicId,
        userId: session.user.userId,
        action: 'hospital_number.assigned',
        entityId: patientId.toString(),
        details: {
          'hospitalNumber': hospitalNumber,
          'submissionId': submissionId,
          'sequence': nextValue,
          'year': year,
        },
        createdAt: now,
      );
      return AssignedHospitalNumber(
        patientId: patientId,
        hospitalNumber: hospitalNumber,
        submissionId: submissionId,
      );
    });
  }

  void _validateCataloguedSpeciesBreed({
    required AnimalsCompanion animal,
    required String? speciesId,
    required String? breedId,
  }) {
    if (speciesId == null && breedId == null) return;
    final species = AnimalCatalogue.speciesById(speciesId);
    final breed = AnimalCatalogue.breedById(breedId);
    if (species == null || breed == null || breed.speciesId != species.id) {
      throw ArgumentError(
        'The selected breed does not belong to the selected species.',
      );
    }
    final savedSpecies = animal.species.value.trim();
    final savedBreed = animal.breed.present
        ? animal.breed.value?.trim() ?? ''
        : '';
    if ((!species.allowsCustomSpecies && savedSpecies != species.displayName) ||
        (species.allowsCustomSpecies && savedSpecies.isEmpty) ||
        (!breed.allowsCustomBreed && savedBreed != breed.displayName) ||
        (breed.allowsCustomBreed && savedBreed.isEmpty)) {
      throw ArgumentError('Species and breed selection is inconsistent.');
    }
  }

  Future<void> updatePatientNumberingSettings({
    required UserSession session,
    required String prefix,
    required int sequenceLength,
    required bool resetYearly,
  }) async {
    await _requireActiveFeature(AveraFeature.patientRecords);
    if (!session.can(Permissions.managePatientNumbering)) {
      throw StateError(
        'You do not have permission to manage patient numbering.',
      );
    }
    if (session.clinic.clinicId != activeClinicId) {
      throw StateError('Your selected clinic changed. Please try again.');
    }
    if (sequenceLength < 4 || sequenceLength > 10) {
      throw ArgumentError.value(sequenceLength, 'sequenceLength');
    }
    final normalizedPrefix = normalizeHospitalNumberPrefix(prefix);
    final current = await _clinicForNumbering(activeClinicId);
    final now = _clock.nowForClinic(current);
    await (db.update(
      db.clinics,
    )..where((clinic) => clinic.clinicId.equals(activeClinicId))).write(
      ClinicsCompanion(
        patientNumberPrefix: Value(normalizedPrefix),
        patientNumberSequenceLength: Value(sequenceLength),
        patientNumberResetYearly: Value(resetYearly),
        patientNumberPrefixReviewed: const Value(true),
        patientNumberLastChangedAt: Value(now),
        patientNumberLastChangedBy: Value(session.user.userId),
      ),
    );
    await _writeNumberingAudit(
      clinicId: activeClinicId,
      userId: session.user.userId,
      action: 'hospital_number.settings_changed',
      entityId: activeClinicId,
      details: {
        'previousPrefix': current.patientNumberPrefix,
        'newPrefix': normalizedPrefix,
        'previousSequenceLength': current.patientNumberSequenceLength,
        'newSequenceLength': sequenceLength,
        'previousResetYearly': current.patientNumberResetYearly,
        'newResetYearly': resetYearly,
      },
      createdAt: now,
    );
  }

  Future<Clinic> activeClinicNumberingConfiguration() =>
      _clinicForNumbering(activeClinicId);

  Future<Clinic> _clinicForNumbering(String clinicId) async {
    final clinic = await (db.select(
      db.clinics,
    )..where((item) => item.clinicId.equals(clinicId))).getSingleOrNull();
    if (clinic == null) {
      throw StateError('The selected clinic is no longer available.');
    }
    return clinic;
  }

  Future<Clinic> _ensurePatientNumberingConfiguration(Clinic clinic) async {
    if (clinic.patientNumberPrefix?.trim().isNotEmpty ?? false) return clinic;
    final prefix = suggestHospitalNumberPrefix(clinic);
    final now = _clock.nowForClinic(clinic);
    await (db.update(
      db.clinics,
    )..where((item) => item.clinicId.equals(clinic.clinicId))).write(
      ClinicsCompanion(
        patientNumberPrefix: Value(prefix),
        patientNumberPrefixReviewed: const Value(false),
        patientNumberLastChangedAt: Value(now),
      ),
    );
    await _writeNumberingAudit(
      clinicId: clinic.clinicId,
      userId: null,
      action: 'hospital_number.prefix_created',
      entityId: clinic.clinicId,
      details: {'prefix': prefix, 'requiresReview': true},
      createdAt: now,
    );
    return _clinicForNumbering(clinic.clinicId);
  }

  Future<int> _legacyPatientSequenceFloor({
    required String clinicId,
    required String prefix,
    required int? registrationYear,
  }) async {
    final numberLike = registrationYear == null
        ? '$prefix-%'
        : '$prefix-$registrationYear-%';
    final records =
        await (db.selectOnly(db.animals)
              ..addColumns([db.animals.hospitalNumber])
              ..where(
                db.animals.clinicId.equals(clinicId) &
                    db.animals.hospitalNumber.like(numberLike),
              ))
            .get();
    final yearPattern = registrationYear?.toString() ?? r'\d{4}';
    final matcher = RegExp(
      '^${RegExp.escape(prefix)}-$yearPattern-([0-9]+)${r'$'}',
    );
    var highest = 0;
    for (final record in records) {
      final value = record.read(db.animals.hospitalNumber);
      final match = value == null ? null : matcher.firstMatch(value);
      final number = match == null ? null : int.tryParse(match.group(1)!);
      if (number != null && number > highest) highest = number;
    }
    return highest;
  }

  Future<void> _writeNumberingAudit({
    required String clinicId,
    required String? userId,
    required String action,
    required String entityId,
    required Map<String, Object?> details,
    required DateTime createdAt,
  }) async {
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            clinicId: Value(clinicId),
            userId: Value(userId),
            action: action,
            entityType: const Value('hospital_number'),
            entityId: Value(entityId),
            details: Value(jsonEncode(details)),
            createdAt: createdAt,
          ),
        );
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

  Set<String> permittedInventoryCategoryIds(UserSession session) {
    _requireInventoryPermission(session, Permissions.inventoryView);
    return inventoryCategoryIdsForUser(session.user);
  }

  Set<String> inventoryCategoryIdsForUser(AppUser user) {
    if (user.accountType == AccountTypes.platformOwner ||
        user.accountType == AccountTypes.clinicAdministrator ||
        user.role == 'Clinic Administrator' ||
        user.role == 'Practice Manager' ||
        user.role == 'Inventory Officer') {
      return {for (final category in InventoryCategories.all) category.id};
    }
    final configured = InventoryAccess.configuredViewCategories(
      _permissionsFromJson(user.permissions),
    );
    if (configured.isNotEmpty) return configured;
    return InventoryAccess.defaultCategoriesForRole(user.role);
  }

  bool canSellInventoryCategory(UserSession session, String categoryId) {
    if (!session.can(Permissions.inventorySell)) return false;
    final category = InventoryCategories.byId(categoryId);
    return category != null &&
        category.isSellable &&
        inventoryCategoryIdsForUser(session.user).contains(categoryId) &&
        inventorySellCategoryIdsForUser(session.user).contains(categoryId);
  }

  Set<String> inventorySellCategoryIdsForUser(AppUser user) {
    final hasSellPermission =
        user.accountType == AccountTypes.platformOwner ||
        (rolePermissions[user.role] ?? const <String>{}).contains(
          Permissions.inventorySell,
        ) ||
        _permissionsFromJson(
          user.permissions,
        ).contains(Permissions.inventorySell);
    if (!hasSellPermission) return const <String>{};
    final configuredSell = InventoryAccess.configuredSellCategories(
      _permissionsFromJson(user.permissions),
    );
    if (configuredSell.isNotEmpty) return configuredSell;
    return {
      for (final category in InventoryCategories.all)
        if (category.isSellable &&
            inventoryCategoryIdsForUser(user).contains(category.id))
          category.id,
    };
  }

  Future<void> setClinicUserInventoryAccess({
    required UserSession actingSession,
    required String targetUserId,
    required Set<String> viewCategoryIds,
    required Set<String> sellCategoryIds,
  }) async {
    _requireInventoryPermission(
      actingSession,
      Permissions.inventoryAccessManage,
    );
    final valid = {for (final category in InventoryCategories.all) category.id};
    if (!valid.containsAll(viewCategoryIds) ||
        !valid.containsAll(sellCategoryIds) ||
        !viewCategoryIds.containsAll(sellCategoryIds)) {
      throw StateError('Inventory category access is invalid.');
    }
    final target =
        await (db.select(db.appUsers)..where(
              (user) =>
                  user.userId.equals(targetUserId) &
                  user.clinicId.equals(actingSession.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (target == null) {
      throw StateError('This staff member is not in the active clinic.');
    }
    final permissions = _permissionsFromJson(target.permissions)
      ..removeWhere(
        (permission) => permission.startsWith('inventory.category.'),
      )
      ..addAll(viewCategoryIds.map(InventoryAccess.viewPermission))
      ..addAll(sellCategoryIds.map(InventoryAccess.sellPermission));
    await db.transaction(() async {
      await (db.update(
        db.appUsers,
      )..where((user) => user.userId.equals(targetUserId))).write(
        AppUsersCompanion(
          permissions: Value(jsonEncode(permissions.toList())),
          updatedAt: Value(_clock.nowForClinic(actingSession.clinic)),
        ),
      );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              clinicId: Value(actingSession.clinic.clinicId),
              userId: Value(actingSession.user.userId),
              action: 'inventory.category_access_changed',
              entityType: const Value('AppUser'),
              entityId: Value(targetUserId),
              details: Value(
                jsonEncode({
                  'viewCategoryIds': viewCategoryIds.toList()..sort(),
                  'sellCategoryIds': sellCategoryIds.toList()..sort(),
                }),
              ),
              createdAt: _clock.nowForClinic(actingSession.clinic),
            ),
          );
    });
  }

  Stream<List<InventoryItem>> watchPermittedInventory(
    UserSession session, {
    String? categoryId,
    String query = '',
  }) {
    final allowed = permittedInventoryCategoryIds(session);
    final normalizedQuery = query.trim().toLowerCase();
    return (db.select(db.inventoryItems)
          ..where(
            (item) =>
                item.clinicId.equals(session.clinic.clinicId) &
                item.isArchived.equals(false),
          )
          ..orderBy([(item) => OrderingTerm.asc(item.drugName)]))
        .watch()
        .map(
          (items) => items
              .where((item) {
                final canonical =
                    item.categoryId ??
                    InventoryCategories.canonicalId(item.category);
                if (!allowed.contains(canonical)) return false;
                if (categoryId != null && canonical != categoryId) return false;
                if (normalizedQuery.isEmpty) return true;
                return '${item.drugName} ${item.category} ${item.batchNumber ?? ''}'
                    .toLowerCase()
                    .contains(normalizedQuery);
              })
              .toList(growable: false),
        );
  }

  Future<int> saveInventoryItem({
    required UserSession session,
    required String name,
    required String categoryId,
    required int quantity,
    required int minimumQuantity,
    String? batchNumber,
    DateTime? expiryDate,
    required double sellingPrice,
    double? buyingPrice,
  }) async {
    _requireInventoryPermission(session, Permissions.inventoryCreate);
    await _requireActiveFeature(AveraFeature.inventory);
    final category = InventoryCategories.byId(categoryId);
    if (category == null ||
        !permittedInventoryCategoryIds(session).contains(categoryId)) {
      throw StateError('You cannot add Inventory in this category.');
    }
    if (name.trim().isEmpty ||
        quantity < 0 ||
        minimumQuantity < 0 ||
        sellingPrice < 0) {
      throw StateError('Enter valid Inventory details.');
    }
    if ((categoryId == 'drugs' || categoryId == 'vaccines') &&
        ((batchNumber?.trim().isEmpty ?? true) || expiryDate == null)) {
      throw StateError(
        'Drugs and Vaccines require a batch number and expiry date.',
      );
    }
    final now = _clock.nowForClinic(session.clinic);
    final id = await db
        .into(db.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            clinicId: Value(session.clinic.clinicId),
            drugName: name.trim(),
            category: category.name,
            categoryId: Value(categoryId),
            quantity: Value(quantity),
            minimumQuantity: Value(minimumQuantity),
            batchNumber: Value(_nullIfBlank(batchNumber)),
            expiryDate: Value(expiryDate),
            sellingPrice: Value(sellingPrice),
            buyingPrice: Value(buyingPrice ?? 0),
            isSellable: Value(category.isSellable),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await _writeInventoryAudit(
      session: session,
      action: 'inventory.item_created',
      itemId: id,
      details: {'categoryId': categoryId, 'quantity': quantity},
    );
    return id;
  }

  Future<void> archiveInventoryItem({
    required UserSession session,
    required int itemId,
  }) async {
    _requireInventoryPermission(session, Permissions.inventoryEdit);
    final item = await _inventoryItemForSession(itemId, session);
    await (db.update(db.inventoryItems)..where((i) => i.id.equals(item.id)))
        .write(InventoryItemsCompanion(isArchived: const Value(true)));
    await _writeInventoryAudit(
      session: session,
      action: 'inventory.item_archived',
      itemId: itemId,
      details: const {},
    );
  }

  Future<InvoiceDetail> saveInvoiceDraft({
    required UserSession session,
    int? invoiceId,
    required int animalId,
    required List<InvoiceProductDraft> products,
    required List<InvoiceServiceDraft> services,
    required double consultationFee,
    required double homeServiceFee,
  }) async {
    _requireInventoryPermission(session, Permissions.billingCreate);
    await _requireActiveFeature(AveraFeature.billing);
    if (consultationFee < 0 || homeServiceFee < 0) {
      throw StateError('Fees cannot be negative.');
    }
    final animal =
        await (db.select(db.animals)..where(
              (row) =>
                  row.id.equals(animalId) &
                  row.clinicId.equals(session.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (animal == null) {
      throw StateError('Select a patient from the active clinic.');
    }
    final seen = <int>{};
    for (final product in products) {
      if (product.quantity <= 0 || !seen.add(product.inventoryItemId)) {
        throw StateError(
          'Each product must appear once with a valid quantity.',
        );
      }
    }
    final now = _clock.nowForClinic(session.clinic);
    return db.transaction(() async {
      final clinic = session.clinic;
      final isNewInvoice = invoiceId == null;
      final targetId =
          invoiceId ??
          await db
              .into(db.invoices)
              .insert(
                InvoicesCompanion.insert(
                  clinicId: clinic.clinicId,
                  animalId: animalId,
                  // A UUID keeps the required unique value safe until the
                  // auto-incremented invoice id is available below.
                  reference: 'PENDING-${_uuid.v4()}',
                  clinicNameSnapshot: clinic.clinicName,
                  clinicAddressSnapshot: Value(clinic.address),
                  clinicPhoneSnapshot: Value(clinic.phoneNumber),
                  clinicEmailSnapshot: Value(clinic.email),
                  createdByUserId: session.user.userId,
                  createdAt: now,
                  updatedAt: Value(now),
                ),
              );
      if (isNewInvoice) {
        await (db.update(
          db.invoices,
        )..where((row) => row.id.equals(targetId))).write(
          InvoicesCompanion(
            reference: Value(
              'INV-${now.year}-${targetId.toString().padLeft(5, '0')}',
            ),
          ),
        );
      }
      final existing = await _invoiceForSession(targetId, session);
      if (existing.status == 'Paid' || existing.status == 'Voided') {
        throw StateError('Paid or voided invoices cannot be edited.');
      }
      await (db.delete(
        db.invoiceProductLines,
      )..where((line) => line.invoiceId.equals(targetId))).go();
      await (db.delete(
        db.invoiceServiceLines,
      )..where((line) => line.invoiceId.equals(targetId))).go();
      var productsTotal = 0.0;
      for (final product in products) {
        final item = await _inventoryItemForSession(
          product.inventoryItemId,
          session,
        );
        final categoryId =
            item.categoryId ?? InventoryCategories.canonicalId(item.category);
        if (!canSellInventoryCategory(session, categoryId) ||
            !item.isSellable ||
            item.isArchived) {
          throw StateError('${item.drugName} is not available for billing.');
        }
        final lineTotal = item.sellingPrice * product.quantity;
        productsTotal += lineTotal;
        await db
            .into(db.invoiceProductLines)
            .insert(
              InvoiceProductLinesCompanion.insert(
                invoiceId: targetId,
                inventoryItemId: item.id,
                productNameSnapshot: item.drugName,
                categoryNameSnapshot: item.category,
                batchNumberSnapshot: Value(item.batchNumber),
                quantity: product.quantity,
                unitPrice: item.sellingPrice,
                lineTotal: lineTotal,
              ),
            );
      }
      var servicesTotal = 0.0;
      for (final service in services) {
        if (service.description.trim().isEmpty || service.amount < 0) {
          throw StateError('Enter a valid service and amount.');
        }
        servicesTotal += service.amount;
        await db
            .into(db.invoiceServiceLines)
            .insert(
              InvoiceServiceLinesCompanion.insert(
                invoiceId: targetId,
                description: service.description.trim(),
                amount: service.amount,
              ),
            );
      }
      final total =
          productsTotal + servicesTotal + consultationFee + homeServiceFee;
      await (db.update(
        db.invoices,
      )..where((row) => row.id.equals(targetId))).write(
        InvoicesCompanion(
          productsSubtotal: Value(productsTotal),
          servicesSubtotal: Value(servicesTotal),
          consultationFee: Value(consultationFee),
          homeServiceFee: Value(homeServiceFee),
          total: Value(total),
          balance: Value(total - existing.amountPaid + existing.refundTotal),
          updatedAt: Value(now),
        ),
      );
      await _writeInvoiceAudit(
        session: session,
        invoiceId: targetId,
        action: 'invoice.draft_saved',
        details: {'total': total},
      );
      return _invoiceDetailForSession(targetId, session);
    });
  }

  Future<InvoiceDetail> payInvoice({
    required UserSession session,
    required int invoiceId,
    String paymentMethod = 'Cash',
  }) async {
    _requireInventoryPermission(session, Permissions.inventorySell);
    await _requireActiveFeature(AveraFeature.billing);
    return db.transaction(() async {
      final invoice = await _invoiceForSession(invoiceId, session);
      if (invoice.status != 'Pending') {
        throw StateError('Only a pending invoice can be paid.');
      }
      final products = await (db.select(
        db.invoiceProductLines,
      )..where((line) => line.invoiceId.equals(invoiceId))).get();
      final now = _clock.nowForClinic(session.clinic);
      for (final line in products) {
        final item = await _inventoryItemForSession(
          line.inventoryItemId,
          session,
        );
        final categoryId =
            item.categoryId ?? InventoryCategories.canonicalId(item.category);
        if (!canSellInventoryCategory(session, categoryId) ||
            !item.isSellable) {
          throw StateError('${item.drugName} is not permitted for sale.');
        }
        if (item.expiryDate != null && item.expiryDate!.isBefore(now)) {
          await _writeInventoryAudit(
            session: session,
            action: 'inventory.expired_blocked',
            itemId: item.id,
            details: {'invoiceId': invoiceId},
          );
          throw StateError('${item.drugName} is expired and cannot be sold.');
        }
        if (line.quantity > item.quantity) {
          await _writeInventoryAudit(
            session: session,
            action: 'inventory.insufficient_stock_blocked',
            itemId: item.id,
            details: {
              'invoiceId': invoiceId,
              'available': item.quantity,
              'requested': line.quantity,
            },
          );
          throw StateError(
            'Insufficient stock for ${item.drugName}. Available: ${item.quantity}; requested: ${line.quantity}.',
          );
        }
        final after = item.quantity - line.quantity;
        await (db.update(
          db.inventoryItems,
        )..where((row) => row.id.equals(item.id))).write(
          InventoryItemsCompanion(
            quantity: Value(after),
            updatedAt: Value(now),
          ),
        );
        await db
            .into(db.inventoryStockMovements)
            .insert(
              InventoryStockMovementsCompanion.insert(
                clinicId: session.clinic.clinicId,
                inventoryItemId: item.id,
                movementType: 'Sale',
                quantityChange: -line.quantity,
                quantityBefore: item.quantity,
                quantityAfter: after,
                invoiceId: Value(invoiceId),
                performedByUserId: session.user.userId,
                createdAt: now,
              ),
            );
        // Existing sales and reporting screens remain meaningful while the
        // invoice ledger becomes the authoritative stock audit trail.
        await db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                clinicId: Value(session.clinic.clinicId),
                drugId: item.id,
                quantity: line.quantity,
                price: line.lineTotal,
                date: now,
              ),
            );
      }
      await (db.update(
        db.invoices,
      )..where((row) => row.id.equals(invoiceId))).write(
        InvoicesCompanion(
          status: const Value('Paid'),
          amountPaid: Value(invoice.total),
          balance: const Value(0),
          paymentMethod: Value(paymentMethod),
          paidAt: Value(now),
          paidByUserId: Value(session.user.userId),
          updatedAt: Value(now),
        ),
      );
      final paymentId = await db
          .into(db.invoicePayments)
          .insert(
            InvoicePaymentsCompanion.insert(
              clinicId: activeClinicId,
              invoiceId: invoiceId,
              receiptNumber:
                  'RCT-${now.year}-${invoiceId.toString().padLeft(5, '0')}-1',
              amount: invoice.total,
              paymentMethod: paymentMethod,
              processedByUserId: session.user.userId,
              createdAt: now,
            ),
          );
      await _writeInvoiceAudit(
        session: session,
        invoiceId: invoiceId,
        action: 'invoice.paid',
        details: {
          'paymentMethod': paymentMethod,
          'amount': invoice.total,
          'paymentId': paymentId,
        },
      );
      await _writeInvoiceActivity(
        session: session,
        invoice: invoice,
        action: 'paymentRecorded',
        title: 'Payment recorded for ${invoice.reference}',
        description:
            '${session.clinic.currency} ${invoice.total.toStringAsFixed(2)} via $paymentMethod',
        now: now,
      );
      return _invoiceDetailForSession(invoiceId, session);
    });
  }

  Stream<List<BillingHistoryEntry>> watchBillingHistory(UserSession session) {
    if (session.clinic.clinicId != activeClinicId ||
        !session.can(Permissions.billingHistory)) {
      throw StateError('You do not have permission to view billing history.');
    }
    final query = db.select(db.invoices).join([
      innerJoin(db.animals, db.animals.id.equalsExp(db.invoices.animalId)),
      innerJoin(db.owners, db.owners.id.equalsExp(db.animals.ownerId)),
      leftOuterJoin(
        db.appUsers,
        db.appUsers.userId.equalsExp(db.invoices.paidByUserId),
      ),
    ]);
    query.where(db.invoices.clinicId.equals(activeClinicId));
    query.orderBy([OrderingTerm.desc(db.invoices.createdAt)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => BillingHistoryEntry(
              invoice: row.readTable(db.invoices),
              animal: row.readTable(db.animals),
              owner: row.readTable(db.owners),
              processedBy: row.readTableOrNull(db.appUsers),
            ),
          )
          .toList(),
    );
  }

  Future<InvoiceDetail> recordInvoicePayment({
    required UserSession session,
    required int invoiceId,
    required double amount,
    required String paymentMethod,
  }) async {
    _requireBillingPermission(session, Permissions.billingRecordPayment);
    if (amount <= 0) throw StateError('Enter a payment greater than zero.');
    return db.transaction(() async {
      final invoice = await _invoiceForSession(invoiceId, session);
      if ({'Voided', 'Cancelled', 'Refunded'}.contains(invoice.status)) {
        throw StateError('This invoice cannot accept a payment.');
      }
      final outstanding =
          (invoice.total - invoice.amountPaid + invoice.refundTotal).clamp(
            0,
            double.infinity,
          );
      if (amount > outstanding + 0.001) {
        throw StateError(
          'Payment exceeds the outstanding balance of ${outstanding.toStringAsFixed(2)}.',
        );
      }
      final now = _clock.nowForClinic(session.clinic);
      if (invoice.amountPaid == 0) {
        await _deductInvoiceStock(invoice: invoice, session: session, now: now);
      }
      final count =
          await (db.selectOnly(db.invoicePayments)
                ..addColumns([db.invoicePayments.id.count()])
                ..where(
                  db.invoicePayments.clinicId.equals(activeClinicId) &
                      db.invoicePayments.invoiceId.equals(invoiceId),
                ))
              .map((row) => row.read(db.invoicePayments.id.count()) ?? 0)
              .getSingle();
      final paymentId = await db
          .into(db.invoicePayments)
          .insert(
            InvoicePaymentsCompanion.insert(
              clinicId: activeClinicId,
              invoiceId: invoiceId,
              receiptNumber:
                  'RCT-${now.year}-${invoiceId.toString().padLeft(5, '0')}-${count + 1}',
              amount: amount,
              paymentMethod: paymentMethod,
              processedByUserId: session.user.userId,
              createdAt: now,
            ),
          );
      final newPaid = invoice.amountPaid + amount;
      final balance = (invoice.total - newPaid + invoice.refundTotal)
          .clamp(0, double.infinity)
          .toDouble();
      final status = balance <= 0.001 ? 'Paid' : 'Partially paid';
      await (db.update(
        db.invoices,
      )..where((row) => row.id.equals(invoiceId))).write(
        InvoicesCompanion(
          status: Value(status),
          amountPaid: Value(newPaid),
          balance: Value(balance),
          paymentMethod: Value(paymentMethod),
          paidAt: Value(status == 'Paid' ? now : invoice.paidAt),
          paidByUserId: Value(session.user.userId),
          updatedAt: Value(now),
        ),
      );
      await _writeInvoiceAudit(
        session: session,
        invoiceId: invoiceId,
        action: 'invoice.payment_recorded',
        details: {
          'paymentId': paymentId,
          'amount': amount,
          'method': paymentMethod,
          'balance': balance,
        },
      );
      await _writeInvoiceActivity(
        session: session,
        invoice: invoice,
        action: 'paymentRecorded',
        title: 'Payment recorded for ${invoice.reference}',
        description:
            '${session.clinic.currency} ${amount.toStringAsFixed(2)} received; balance ${balance.toStringAsFixed(2)}.',
        now: now,
      );
      return _invoiceDetailForSession(invoiceId, session);
    });
  }

  Future<InvoiceDetail> refundInvoicePayment({
    required UserSession session,
    required int invoiceId,
    required double amount,
    required String reason,
    String paymentMethod = 'Original method',
  }) async {
    _requireBillingPermission(session, Permissions.billingRefund);
    if (amount <= 0) throw StateError('Enter a refund greater than zero.');
    if (reason.trim().isEmpty) {
      throw StateError('Enter a reason for this refund.');
    }
    return db.transaction(() async {
      final invoice = await _invoiceForSession(invoiceId, session);
      final refundable = invoice.amountPaid - invoice.refundTotal;
      if (amount > refundable + 0.001) {
        throw StateError(
          'Refund exceeds the refundable amount of ${refundable.toStringAsFixed(2)}.',
        );
      }
      final now = _clock.nowForClinic(session.clinic);
      final count =
          await (db.selectOnly(db.invoicePayments)
                ..addColumns([db.invoicePayments.id.count()])
                ..where(
                  db.invoicePayments.clinicId.equals(activeClinicId) &
                      db.invoicePayments.invoiceId.equals(invoiceId),
                ))
              .map((row) => row.read(db.invoicePayments.id.count()) ?? 0)
              .getSingle();
      final refundId = await db
          .into(db.invoicePayments)
          .insert(
            InvoicePaymentsCompanion.insert(
              clinicId: activeClinicId,
              invoiceId: invoiceId,
              receiptNumber:
                  'RFN-${now.year}-${invoiceId.toString().padLeft(5, '0')}-${count + 1}',
              transactionType: const Value('Refund'),
              amount: amount,
              paymentMethod: paymentMethod,
              processedByUserId: session.user.userId,
              reason: Value(reason.trim()),
              createdAt: now,
            ),
          );
      final refunds = invoice.refundTotal + amount;
      final balance = (invoice.total - invoice.amountPaid + refunds)
          .clamp(0, double.infinity)
          .toDouble();
      final status = refunds >= invoice.amountPaid
          ? 'Refunded'
          : 'Partially refunded';
      await (db.update(
        db.invoices,
      )..where((row) => row.id.equals(invoiceId))).write(
        InvoicesCompanion(
          status: Value(status),
          refundTotal: Value(refunds),
          balance: Value(balance),
          updatedAt: Value(now),
        ),
      );
      await _writeInvoiceAudit(
        session: session,
        invoiceId: invoiceId,
        action: 'invoice.refund_processed',
        details: {
          'refundId': refundId,
          'amount': amount,
          'reason': reason.trim(),
        },
      );
      await _writeInvoiceActivity(
        session: session,
        invoice: invoice,
        action: 'refundProcessed',
        title: 'Refund processed for ${invoice.reference}',
        description:
            '${session.clinic.currency} ${amount.toStringAsFixed(2)} refunded.',
        now: now,
      );
      return _invoiceDetailForSession(invoiceId, session);
    });
  }

  Future<void> voidInvoice({
    required UserSession session,
    required int invoiceId,
    required String reason,
  }) async {
    _requireBillingPermission(session, Permissions.billingVoid);
    if (reason.trim().isEmpty) {
      throw StateError('Enter a reason before voiding an invoice.');
    }
    await db.transaction(() async {
      final invoice = await _invoiceForSession(invoiceId, session);
      if (invoice.status == 'Voided') {
        throw StateError('This invoice is already voided.');
      }
      final now = _clock.nowForClinic(session.clinic);
      final products = await (db.select(
        db.invoiceProductLines,
      )..where((line) => line.invoiceId.equals(invoiceId))).get();
      for (final line
          in invoice.amountPaid > 0 ? products : const <InvoiceProductLine>[]) {
        final item = await _inventoryItemForSession(
          line.inventoryItemId,
          session,
        );
        final after = item.quantity + line.quantity;
        await (db.update(
          db.inventoryItems,
        )..where((row) => row.id.equals(item.id))).write(
          InventoryItemsCompanion(
            quantity: Value(after),
            updatedAt: Value(now),
          ),
        );
        await db
            .into(db.inventoryStockMovements)
            .insert(
              InventoryStockMovementsCompanion.insert(
                clinicId: session.clinic.clinicId,
                inventoryItemId: item.id,
                movementType: 'Sale reversal',
                quantityChange: line.quantity,
                quantityBefore: item.quantity,
                quantityAfter: after,
                invoiceId: Value(invoiceId),
                performedByUserId: session.user.userId,
                reason: Value(reason.trim()),
                createdAt: now,
              ),
            );
      }
      await (db.update(
        db.invoices,
      )..where((row) => row.id.equals(invoiceId))).write(
        InvoicesCompanion(
          status: const Value('Voided'),
          voidedAt: Value(now),
          voidedByUserId: Value(session.user.userId),
          voidReason: Value(reason.trim()),
          updatedAt: Value(now),
        ),
      );
      await _writeInvoiceAudit(
        session: session,
        invoiceId: invoiceId,
        action: 'invoice.voided',
        details: {'reason': reason.trim()},
      );
      await _writeInvoiceActivity(
        session: session,
        invoice: invoice,
        action: 'billVoided',
        title: '${invoice.reference} voided',
        description: reason.trim(),
        now: now,
      );
    });
  }

  Future<InvoiceDetail?> getInvoiceDetail(
    UserSession session,
    int invoiceId,
  ) async {
    try {
      return await _invoiceDetailForSession(invoiceId, session);
    } on StateError {
      return null;
    }
  }

  Future<InvoiceDetail> _invoiceDetailForSession(
    int invoiceId,
    UserSession session,
  ) async {
    final invoice = await _invoiceForSession(invoiceId, session);
    final products = await (db.select(
      db.invoiceProductLines,
    )..where((line) => line.invoiceId.equals(invoiceId))).get();
    final services = await (db.select(
      db.invoiceServiceLines,
    )..where((line) => line.invoiceId.equals(invoiceId))).get();
    final payments =
        await (db.select(db.invoicePayments)
              ..where(
                (payment) =>
                    payment.clinicId.equals(session.clinic.clinicId) &
                    payment.invoiceId.equals(invoiceId),
              )
              ..orderBy([(payment) => OrderingTerm.desc(payment.createdAt)]))
            .get();
    return InvoiceDetail(
      invoice: invoice,
      products: products,
      services: services,
      payments: payments,
    );
  }

  Future<Invoice> _invoiceForSession(int invoiceId, UserSession session) async {
    final invoice =
        await (db.select(db.invoices)..where(
              (row) =>
                  row.id.equals(invoiceId) &
                  row.clinicId.equals(session.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (invoice == null) {
      throw StateError('Invoice not found in the active clinic.');
    }
    return invoice;
  }

  Future<InventoryItem> _inventoryItemForSession(
    int itemId,
    UserSession session,
  ) async {
    final item =
        await (db.select(db.inventoryItems)..where(
              (row) =>
                  row.id.equals(itemId) &
                  row.clinicId.equals(session.clinic.clinicId),
            ))
            .getSingleOrNull();
    if (item == null) {
      throw StateError('Inventory item not found in the active clinic.');
    }
    return item;
  }

  void _requireInventoryPermission(UserSession session, String permission) {
    if (session.clinic.clinicId != activeClinicId || !session.can(permission)) {
      throw StateError('You do not have permission for this Inventory action.');
    }
  }

  void _requireBillingPermission(UserSession session, String permission) {
    if (session.clinic.clinicId != activeClinicId || !session.can(permission)) {
      throw StateError('You do not have permission for this Billing action.');
    }
  }

  Future<void> _deductInvoiceStock({
    required Invoice invoice,
    required UserSession session,
    required DateTime now,
  }) async {
    final lines = await (db.select(
      db.invoiceProductLines,
    )..where((line) => line.invoiceId.equals(invoice.id))).get();
    final resolved = <(InvoiceProductLine, InventoryItem)>[];
    for (final line in lines) {
      final item = await _inventoryItemForSession(
        line.inventoryItemId,
        session,
      );
      if (item.isArchived || !item.isSellable) {
        throw StateError('${item.drugName} is not available for sale.');
      }
      if (item.expiryDate != null && !item.expiryDate!.isAfter(now)) {
        throw StateError('${item.drugName} is expired and cannot be sold.');
      }
      if (item.quantity < line.quantity) {
        await _writeInventoryAudit(
          session: session,
          action: 'inventory.insufficient_stock_blocked',
          itemId: item.id,
          details: {
            'invoiceId': invoice.id,
            'available': item.quantity,
            'requested': line.quantity,
          },
        );
        throw StateError(
          'Insufficient stock for ${item.drugName}. '
          'Available: ${item.quantity}; requested: ${line.quantity}.',
        );
      }
      resolved.add((line, item));
    }
    for (final entry in resolved) {
      final line = entry.$1;
      final item = entry.$2;
      final after = item.quantity - line.quantity;
      await (db.update(
        db.inventoryItems,
      )..where((row) => row.id.equals(item.id))).write(
        InventoryItemsCompanion(quantity: Value(after), updatedAt: Value(now)),
      );
      await db
          .into(db.inventoryStockMovements)
          .insert(
            InventoryStockMovementsCompanion.insert(
              clinicId: session.clinic.clinicId,
              inventoryItemId: item.id,
              movementType: 'Sale',
              quantityChange: -line.quantity,
              quantityBefore: item.quantity,
              quantityAfter: after,
              invoiceId: Value(invoice.id),
              performedByUserId: session.user.userId,
              createdAt: now,
            ),
          );
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              clinicId: Value(session.clinic.clinicId),
              drugId: item.id,
              quantity: line.quantity,
              price: line.lineTotal,
              date: now,
            ),
          );
    }
  }

  Future<void> _writeInvoiceActivity({
    required UserSession session,
    required Invoice invoice,
    required String action,
    required String title,
    required String description,
    required DateTime now,
  }) => db
      .into(db.clinicActivityEvents)
      .insert(
        ClinicActivityEventsCompanion.insert(
          id: 'billing:$action:${invoice.id}:${now.microsecondsSinceEpoch}',
          clinicId: session.clinic.clinicId,
          type: 'billing.$action',
          title: title,
          description: description,
          occurredAt: now,
          performedByUserId: Value(session.user.userId),
          relatedEntityType: const Value('Invoice'),
          relatedEntityId: Value(invoice.id.toString()),
          patientId: Value(invoice.animalId),
          module: const Value('Billing'),
          metadata: Value(
            jsonEncode({'route': '/billing/history', 'invoiceId': invoice.id}),
          ),
        ),
      )
      .then((_) {});

  Future<void> _writeInventoryAudit({
    required UserSession session,
    required String action,
    required int itemId,
    required Map<String, Object?> details,
  }) => db
      .into(db.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          clinicId: Value(session.clinic.clinicId),
          userId: Value(session.user.userId),
          action: action,
          entityType: const Value('InventoryItem'),
          entityId: Value(itemId.toString()),
          details: Value(jsonEncode(details)),
          createdAt: _clock.nowForClinic(session.clinic),
        ),
      )
      .then((_) {});

  Future<void> _writeInvoiceAudit({
    required UserSession session,
    required int invoiceId,
    required String action,
    required Map<String, Object?> details,
  }) => db
      .into(db.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          clinicId: Value(session.clinic.clinicId),
          userId: Value(session.user.userId),
          action: action,
          entityType: const Value('Invoice'),
          entityId: Value(invoiceId.toString()),
          details: Value(jsonEncode(details)),
          createdAt: _clock.nowForClinic(session.clinic),
        ),
      )
      .then((_) {});

  Future<void> seedSampleData() async {
    await bootstrapClinicWorkspace();
    final hasAnimals =
        await (db.select(db.animals)
              ..where((a) => a.clinicId.equals(activeClinicId)))
            .get()
            .then((v) => v.isNotEmpty);
    if (hasAnimals) return;

    final species = ['Dog', 'Cat', 'Goat', 'Rabbit', 'Parrot'];
    const vaccineBySpecies = <String, String>{
      'Dog': 'DHLPP',
      'Cat': 'FVRCP',
      'Goat': 'PPR',
      'Rabbit': 'Rabbit Haemorrhagic Disease',
      'Parrot': 'Avian Polyomavirus',
    };
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
                vaccine: vaccineBySpecies[species[i % species.length]]!,
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
              destinationType: const Value('vaccinationRecord'),
              destinationEntityId: Value(vaccine.id),
              dueDate: Value(vaccine.nextDueDate),
              deliveredAt: Value(DateTime.now()),
              createdAt: DateTime.now(),
            ),
          );
    }
  }

  Future<File> exportDatabaseBackup() async {
    // Flush the write-ahead log before copying the database file so the
    // exported snapshot includes committed local changes.
    await db.customStatement('PRAGMA wal_checkpoint(FULL)');
    final dir = await getApplicationDocumentsDirectory();
    final source = File(p.join(dir.path, 'zevora.sqlite'));
    final backupDir = await getDownloadsDirectory() ?? dir;
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final target = File(p.join(backupDir.path, 'avera_backup_$stamp.sqlite'));
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
