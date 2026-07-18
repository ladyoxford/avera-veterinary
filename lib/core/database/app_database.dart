import 'package:drift/drift.dart';

import 'database_connection_native.dart'
    if (dart.library.html) 'database_connection_web.dart';

part 'app_database.g.dart';

const defaultClinicId = 'demo-clinic';

class Clinics extends Table {
  TextColumn get clinicId => text()();
  TextColumn get clinicName => text().withLength(min: 2, max: 160)();
  TextColumn get logo => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get state => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get phoneNumber => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();
  TextColumn get veterinaryLicenseNumber => text().nullable()();
  TextColumn get businessRegistrationNumber => text().nullable()();
  TextColumn get clinicType =>
      text().withDefault(const Constant('General Practice'))();
  TextColumn get workingHours => text().nullable()();
  TextColumn get emergencyContact => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('NGN'))();
  TextColumn get timeZone =>
      text().withDefault(const Constant('Africa/Lagos'))();
  TextColumn get preferredLanguage =>
      text().withDefault(const Constant('English'))();
  TextColumn get themeColor => text().withDefault(const Constant('#1B7F5A'))();
  TextColumn get banner => text().nullable()();
  TextColumn get stamp => text().nullable()();
  TextColumn get signature => text().nullable()();
  TextColumn get clinicOwner => text().nullable()();
  DateTimeColumn get dateRegistered => dateTime()();
  TextColumn get subscriptionPlan =>
      text().withDefault(const Constant('Starter'))();
  TextColumn get clinicStatus => text().withDefault(const Constant('Active'))();

  @override
  Set<Column> get primaryKey => {clinicId};
}

class ClinicWorkHours extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get timeZone =>
      text().withDefault(const Constant('Africa/Lagos'))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId},
  ];
}

class ClinicWorkDays extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get weekday => text()();
  BoolColumn get isOpen => boolean().withDefault(const Constant(false))();
  TextColumn get openingTime => text().nullable()();
  TextColumn get closingTime => text().nullable()();
  TextColumn get breakStart => text().nullable()();
  TextColumn get breakEnd => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, weekday},
  ];
}

class AppUsers extends Table {
  TextColumn get userId => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get profilePhoto => text().nullable()();
  TextColumn get fullName => text()();
  TextColumn get username => text()();
  TextColumn get email => text()();
  TextColumn get phoneNumber => text().nullable()();
  TextColumn get passwordHash => text()();
  TextColumn get role => text()();
  TextColumn get roleId => text().nullable()();
  TextColumn get accountType =>
      text().withDefault(const Constant('ClinicStaff'))();
  TextColumn get permissions => text().withDefault(const Constant('[]'))();
  TextColumn get invitationStatus =>
      text().withDefault(const Constant('Active'))();
  DateTimeColumn get invitationSentAt => dateTime().nullable()();
  TextColumn get professionalTitle => text().nullable()();
  TextColumn get veterinaryLicenseNumber => text().nullable()();
  TextColumn get staffNumber => text().nullable()();
  BoolColumn get requiresPasswordChange =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get passwordChangedAt => dateTime().nullable()();
  DateTimeColumn get emailVerifiedAt => dateTime().nullable()();
  DateTimeColumn get suspendedAt => dateTime().nullable()();
  TextColumn get suspendedBy => text().nullable()();
  BoolColumn get twoFactorEnabled =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastLogin => dateTime().nullable()();
  TextColumn get accountStatus =>
      text().withDefault(const Constant('Active'))();
  BoolColumn get rememberMe => boolean().withDefault(const Constant(false))();
  IntColumn get sessionTimeoutMinutes =>
      integer().withDefault(const Constant(30))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get activationTokenHash => text().nullable()();
  DateTimeColumn get activationTokenExpiresAt => dateTime().nullable()();
  DateTimeColumn get activationTokenUsedAt => dateTime().nullable()();
  DateTimeColumn get activatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId};
}

class Owners extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  TextColumn get fullName => text().withLength(min: 2, max: 120)();
  TextColumn get phone => text().withLength(min: 3, max: 32)();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get state => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get occupation => text().nullable()();
}

class Animals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  TextColumn get hospitalNumber => text().unique()();
  TextColumn get animalName => text().withLength(min: 1, max: 120)();
  TextColumn get species => text().withLength(min: 1, max: 80)();
  TextColumn get breed => text().nullable()();
  TextColumn get sex => text().nullable()();
  IntColumn get age => integer().nullable()();
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  RealColumn get weight => real().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get microchipNumber => text().nullable()();
  IntColumn get ownerId => integer().references(Owners, #id)();
  TextColumn get photo => text().nullable()();
  DateTimeColumn get dateRegistered => dateTime()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('Active'))();
  DateTimeColumn get statusUpdatedAt => dateTime().nullable()();
  TextColumn get statusUpdatedBy => text().nullable()();
}

class Visits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  IntColumn get animalId => integer().references(Animals, #id)();
  DateTimeColumn get visitDate => dateTime()();
  TextColumn get chiefComplaint => text().nullable()();
  TextColumn get history => text().nullable()();
  TextColumn get physicalExamination => text().nullable()();
  RealColumn get temperature => real().nullable()();
  IntColumn get pulse => integer().nullable()();
  IntColumn get respiration => integer().nullable()();
  TextColumn get mucousMembrane => text().nullable()();
  TextColumn get crt => text().nullable()();
  RealColumn get weight => real().nullable()();
  TextColumn get bodyConditionScore => text().nullable()();
  TextColumn get diagnosis => text().nullable()();
  TextColumn get differentialDiagnosis => text().nullable()();
  TextColumn get treatment => text().nullable()();
  TextColumn get prescription => text().nullable()();
  TextColumn get advice => text().nullable()();
  DateTimeColumn get nextAppointment => dateTime().nullable()();
  TextColumn get veterinarian => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('Completed'))();
}

class Vaccinations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  IntColumn get animalId => integer().references(Animals, #id)();
  TextColumn get vaccine => text()();
  TextColumn get ageAtVaccination => text().nullable()();
  TextColumn get batchNumber => text().nullable()();
  TextColumn get manufacturer => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  TextColumn get route => text().nullable()();
  TextColumn get dose => text().nullable()();
  TextColumn get injectionSite => text().nullable()();
  DateTimeColumn get dateGiven => dateTime()();
  DateTimeColumn get nextDueDate => dateTime().nullable()();
  TextColumn get administeredBy => text().nullable()();
  TextColumn get veterinarian => text().nullable()();
  TextColumn get certificateNumber => text().nullable()();
  TextColumn get certificatePdf => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get reminderStatus =>
      text().withDefault(const Constant('Pending'))();
  TextColumn get status => text().withDefault(const Constant('Completed'))();
}

class InventoryItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  TextColumn get drugName => text()();
  TextColumn get category => text()();
  TextColumn get manufacturer => text().nullable()();
  TextColumn get batchNumber => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  IntColumn get minimumQuantity => integer().withDefault(const Constant(5))();
  RealColumn get buyingPrice => real().withDefault(const Constant(0))();
  RealColumn get sellingPrice => real().withDefault(const Constant(0))();
  TextColumn get supplier => text().nullable()();
  TextColumn get location => text().nullable()();
}

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  IntColumn get drugId => integer().references(InventoryItems, #id)();
  IntColumn get quantity => integer()();
  RealColumn get price => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get customer => text().nullable()();
}

class Appointments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  IntColumn get animalId => integer().references(Animals, #id)();
  DateTimeColumn get appointmentDate => dateTime()();
  TextColumn get purpose => text()();
  TextColumn get status => text().withDefault(const Constant('Scheduled'))();
}

class VaccinationProtocols extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  TextColumn get species => text()();
  TextColumn get vaccine => text()();
  TextColumn get diseasesProtectedAgainst => text().nullable()();
  TextColumn get recommendedAge => text()();
  IntColumn get recommendedAgeWeeks => integer().nullable()();
  TextColumn get dose => text().nullable()();
  TextColumn get route => text().nullable()();
  TextColumn get storageRequirements => text().nullable()();
  TextColumn get manufacturer => text().nullable()();
  TextColumn get boosterSchedule => text().nullable()();
  TextColumn get contraindications => text().nullable()();
  TextColumn get possibleAdverseEffects => text().nullable()();
  TextColumn get precautions => text().nullable()();
  TextColumn get certificateTemplate => text().nullable()();
  TextColumn get references => text().nullable()();
  BoolColumn get isCore => boolean().withDefault(const Constant(true))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class Notifications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get message => text()();
  IntColumn get animalId => integer().nullable().references(Animals, #id)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  TextColumn get userId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get details => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Durable, tenant-scoped journal for clinical work completed while the device
/// cannot contact the authoritative backend. Payloads are never authentication
/// secrets; authentication state remains in secure platform storage.
class SyncOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get userId => text()();
  TextColumn get deviceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operationType => text()();
  DateTimeColumn get localTimestamp => dateTime()();
  IntColumn get baseVersion => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();
  TextColumn get syncStatus => text().withDefault(const Constant('Pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {operationId};
}

/// JSON pages and aggregates received from the authoritative backend.  This is
/// intentionally separate from the legacy local clinical tables: server UUIDs
/// and revisions remain stable without changing existing local record IDs.
class CloudCacheEntries extends Table {
  TextColumn get cacheKey => text()();
  TextColumn get clinicId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

class CloudEntitySynchronizations extends Table {
  TextColumn get entityType => text()();
  TextColumn get serverId => text()();
  TextColumn get clinicId => text()();
  IntColumn get revision => integer().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  DateTimeColumn get lastSynchronizedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {entityType, serverId, clinicId};
}

/// Local subscription catalogue. The plan key is stable so a future remote
/// repository can map these records to a server-owned plan without changing UI
/// or feature-gate contracts.
class SubscriptionPlanRecords extends Table {
  TextColumn get planKey => text()();
  TextColumn get displayName => text()();
  TextColumn get positioning => text()();
  TextColumn get targetCustomer => text()();
  TextColumn get monthlyPriceLabel => text().nullable()();
  TextColumn get annualPriceLabel => text().nullable()();
  BoolColumn get isMostPopular =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isContactSales =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {planKey};
}

class SubscriptionFeatures extends Table {
  TextColumn get featureKey => text()();
  TextColumn get displayName => text()();
  TextColumn get description => text()();
  TextColumn get category => text()();

  @override
  Set<Column> get primaryKey => {featureKey};
}

class PlanCapabilities extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get planKey =>
      text().references(SubscriptionPlanRecords, #planKey)();
  TextColumn get featureKey =>
      text().references(SubscriptionFeatures, #featureKey)();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  TextColumn get implementationStatus =>
      text().withDefault(const Constant('available'))();
  TextColumn get releaseStage =>
      text().withDefault(const Constant('available'))();
  IntColumn get numericLimit => integer().nullable()();
  TextColumn get textValue => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {planKey, featureKey},
  ];
}

class ClinicSubscriptions extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get planKey =>
      text().references(SubscriptionPlanRecords, #planKey)();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get trialStartsAt => dateTime().nullable()();
  DateTimeColumn get trialEndsAt => dateTime().nullable()();
  DateTimeColumn get gracePeriodEndsAt => dateTime().nullable()();
  BoolColumn get autoRenew => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId},
  ];
}

class SubscriptionUsages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get usageKey => text()();
  IntColumn get currentValue => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, usageKey},
  ];
}

class SubscriptionTrials extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get planKey =>
      text().references(SubscriptionPlanRecords, #planKey)();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SubscriptionGracePeriods extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get reason => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SubscriptionOverrides extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get featureKey => text()();
  BoolColumn get enabled => boolean()();
  IntColumn get numericLimit => integer().nullable()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SubscriptionAuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get actingUserId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get previousValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  TextColumn get details => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(
  tables: [
    Clinics,
    ClinicWorkHours,
    ClinicWorkDays,
    AppUsers,
    Owners,
    Animals,
    Visits,
    Vaccinations,
    InventoryItems,
    Sales,
    Appointments,
    VaccinationProtocols,
    Notifications,
    AuditLogs,
    SyncOperations,
    CloudCacheEntries,
    CloudEntitySynchronizations,
    SubscriptionPlanRecords,
    SubscriptionFeatures,
    PlanCapabilities,
    ClinicSubscriptions,
    SubscriptionUsages,
    SubscriptionTrials,
    SubscriptionGracePeriods,
    SubscriptionOverrides,
    SubscriptionAuditLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openDatabaseConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(clinics);
        await m.createTable(appUsers);
        await m.createTable(vaccinationProtocols);
        await m.createTable(notifications);
        await m.createTable(auditLogs);
        await m.addColumn(owners, owners.clinicId);
        await m.addColumn(animals, animals.clinicId);
        await m.addColumn(visits, visits.clinicId);
        await m.addColumn(vaccinations, vaccinations.clinicId);
        await m.addColumn(vaccinations, vaccinations.ageAtVaccination);
        await m.addColumn(vaccinations, vaccinations.expiryDate);
        await m.addColumn(vaccinations, vaccinations.route);
        await m.addColumn(vaccinations, vaccinations.dose);
        await m.addColumn(vaccinations, vaccinations.injectionSite);
        await m.addColumn(vaccinations, vaccinations.veterinarian);
        await m.addColumn(vaccinations, vaccinations.certificateNumber);
        await m.addColumn(vaccinations, vaccinations.certificatePdf);
        await m.addColumn(vaccinations, vaccinations.notes);
        await m.addColumn(vaccinations, vaccinations.reminderStatus);
        await m.addColumn(vaccinations, vaccinations.status);
        await m.addColumn(inventoryItems, inventoryItems.clinicId);
        await m.addColumn(sales, sales.clinicId);
        await m.addColumn(appointments, appointments.clinicId);
      }
      if (from < 3) {
        await m.addColumn(animals, animals.status);
        await m.addColumn(animals, animals.statusUpdatedAt);
        await m.addColumn(animals, animals.statusUpdatedBy);
      }
      if (from < 4) {
        await m.addColumn(appUsers, appUsers.roleId);
        await m.addColumn(appUsers, appUsers.accountType);
        await m.addColumn(appUsers, appUsers.invitationStatus);
        await m.addColumn(appUsers, appUsers.invitationSentAt);
        await m.addColumn(appUsers, appUsers.professionalTitle);
        await m.addColumn(appUsers, appUsers.veterinaryLicenseNumber);
        await m.addColumn(appUsers, appUsers.staffNumber);
        await m.addColumn(appUsers, appUsers.requiresPasswordChange);
        await m.addColumn(appUsers, appUsers.passwordChangedAt);
        await m.addColumn(appUsers, appUsers.emailVerifiedAt);
        await m.addColumn(appUsers, appUsers.suspendedAt);
        await m.addColumn(appUsers, appUsers.suspendedBy);
        await m.addColumn(appUsers, appUsers.updatedAt);
        await m.addColumn(appUsers, appUsers.createdBy);
      }
      if (from < 5) {
        await m.addColumn(appUsers, appUsers.activationTokenHash);
        await m.addColumn(appUsers, appUsers.activationTokenExpiresAt);
        await m.addColumn(appUsers, appUsers.activationTokenUsedAt);
        await m.addColumn(appUsers, appUsers.activatedAt);
      }
      if (from < 6) {
        await m.createTable(syncOperations);
      }
      if (from < 7) {
        await m.createTable(cloudCacheEntries);
        await m.createTable(cloudEntitySynchronizations);
      }
      if (from < 8) {
        await m.createTable(clinicWorkHours);
        await m.createTable(clinicWorkDays);
      }
      if (from < 9) {
        await m.createTable(subscriptionPlanRecords);
        await m.createTable(subscriptionFeatures);
        await m.createTable(planCapabilities);
        await m.createTable(clinicSubscriptions);
        await m.createTable(subscriptionUsages);
        await m.createTable(subscriptionTrials);
        await m.createTable(subscriptionGracePeriods);
        await m.createTable(subscriptionOverrides);
        await m.createTable(subscriptionAuditLogs);
      }
    },
  );
}
