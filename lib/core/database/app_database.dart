import 'package:drift/drift.dart';

import '../services/animal_age_service.dart';
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
  TextColumn get patientNumberPrefix => text().nullable()();
  IntColumn get patientNumberSequenceLength =>
      integer().withDefault(const Constant(5))();
  BoolColumn get patientNumberResetYearly =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get patientNumberPrefixReviewed =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get patientNumberLastChangedAt => dateTime().nullable()();
  TextColumn get patientNumberLastChangedBy => text().nullable()();

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
  TextColumn get membershipStatus =>
      text().withDefault(const Constant('Active'))();
  DateTimeColumn get formerStaffAt => dateTime().nullable()();
  TextColumn get formerStaffBy => text().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  TextColumn get archivedBy => text().nullable()();
  TextColumn get removalReason => text().nullable()();
  TextColumn get removalNote => text().nullable()();
  TextColumn get previousRole => text().nullable()();
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
  TextColumn get hospitalNumber => text()();
  TextColumn get animalName => text().withLength(min: 1, max: 120)();
  TextColumn get species => text().withLength(min: 1, max: 80)();
  TextColumn get breed => text().nullable()();
  TextColumn get sex => text().nullable()();
  IntColumn get age => integer().nullable()();
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  BoolColumn get isDateOfBirthEstimated =>
      boolean().withDefault(const Constant(false))();
  IntColumn get originalAgeValue => integer().nullable()();
  TextColumn get originalAgeUnit => text().nullable()();
  DateTimeColumn get ageRecordedAt => dateTime().nullable()();
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
  TextColumn get numberAssignmentStatus =>
      text().withDefault(const Constant('Legacy'))();
  TextColumn get temporaryHospitalNumber => text().nullable()();
  IntColumn get registrationYear => integer().nullable()();
  TextColumn get registrationSubmissionId => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, hospitalNumber},
    {clinicId, registrationSubmissionId},
  ];
}

class ClinicNumberSequences extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get sequenceType => text()();
  TextColumn get sequenceKey => text()();
  IntColumn get currentValue => integer().withDefault(const Constant(0))();
  IntColumn get sequenceLength => integer().withDefault(const Constant(5))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, sequenceType, sequenceKey},
  ];
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

/// Clinic-scoped operational work that sits alongside a patient's clinical
/// history. One table keeps these related workflows locally durable while the
/// individual modules retain their own views and status vocabulary.
class ClinicalOperationRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  IntColumn get animalId => integer().references(Animals, #id)();
  IntColumn get visitId => integer().nullable().references(Visits, #id)();
  IntColumn get hospitalizationId => integer().nullable()();
  IntColumn get sourceOperationId =>
      integer().nullable().references(ClinicalOperationRecords, #id)();
  TextColumn get operationType => text()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('Pending'))();
  TextColumn get priority => text().withDefault(const Constant('Routine'))();
  TextColumn get assignedTo => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  RealColumn get estimatedAmount => real().nullable()();
  TextColumn get detailsJson => text().nullable()();
  TextColumn get createdByUserId =>
      text().nullable().references(AppUsers, #userId)();
  TextColumn get updatedByUserId =>
      text().nullable().references(AppUsers, #userId)();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  IntColumn get recordVersion => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('Synced'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, referenceNumber},
  ];
}

/// Medication, consumable, imaging-view, checklist, or treatment line attached
/// to a clinical operation. Module-specific attributes remain in [detailsJson]
/// while stock and dose fields stay queryable and transaction-safe.
class ClinicalOperationItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  IntColumn get operationId =>
      integer().references(ClinicalOperationRecords, #id)();
  IntColumn get inventoryItemId =>
      integer().nullable().references(InventoryItems, #id)();
  TextColumn get itemType => text()();
  TextColumn get name => text()();
  TextColumn get strength => text().nullable()();
  RealColumn get prescribedQuantity => real().nullable()();
  RealColumn get completedQuantity => real().withDefault(const Constant(0))();
  TextColumn get unit => text().nullable()();
  TextColumn get dose => text().nullable()();
  TextColumn get doseUnit => text().nullable()();
  TextColumn get route => text().nullable()();
  TextColumn get frequency => text().nullable()();
  TextColumn get duration => text().nullable()();
  TextColumn get instructions => text().nullable()();
  BoolColumn get isHighRisk => boolean().withDefault(const Constant(false))();
  TextColumn get status => text().withDefault(const Constant('Pending'))();
  TextColumn get detailsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Immutable action history for dispensing, administering, verification,
/// clinical status changes, uploads, and document lifecycle events.
class ClinicalOperationActions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  IntColumn get operationId =>
      integer().references(ClinicalOperationRecords, #id)();
  IntColumn get operationItemId =>
      integer().nullable().references(ClinicalOperationItems, #id)();
  TextColumn get action => text()();
  TextColumn get previousStatus => text().nullable()();
  TextColumn get newStatus => text().nullable()();
  RealColumn get quantity => real().nullable()();
  TextColumn get unit => text().nullable()();
  IntColumn get inventoryItemId =>
      integer().nullable().references(InventoryItems, #id)();
  TextColumn get batchNumber => text().nullable()();
  DateTimeColumn get batchExpiryDate => dateTime().nullable()();
  TextColumn get performedByUserId => text().references(AppUsers, #userId)();
  TextColumn get verifiedByUserId =>
      text().nullable().references(AppUsers, #userId)();
  TextColumn get reason => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get detailsJson => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
}

/// Versioned file metadata. Large file bytes remain in the existing file
/// storage layer and only a storage reference is persisted here.
class ClinicalDocumentVersions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  IntColumn get operationId =>
      integer().references(ClinicalOperationRecords, #id)();
  IntColumn get parentVersionId =>
      integer().nullable().references(ClinicalDocumentVersions, #id)();
  TextColumn get category => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get storagePath => text()();
  IntColumn get versionNumber => integer().withDefault(const Constant(1))();
  BoolColumn get isSensitive => boolean().withDefault(const Constant(false))();
  TextColumn get replacementReason => text().nullable()();
  TextColumn get uploadedByUserId => text().references(AppUsers, #userId)();
  DateTimeColumn get uploadedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
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
  IntColumn get sourceVaccinationId =>
      integer().nullable().references(Vaccinations, #id)();
}

class InventoryItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()
      .references(Clinics, #clinicId)
      .withDefault(const Constant(defaultClinicId))();
  TextColumn get drugName => text()();
  TextColumn get category => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get manufacturer => text().nullable()();
  TextColumn get batchNumber => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  IntColumn get minimumQuantity => integer().withDefault(const Constant(5))();
  RealColumn get buyingPrice => real().withDefault(const Constant(0))();
  RealColumn get sellingPrice => real().withDefault(const Constant(0))();
  TextColumn get supplier => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get baseUnitLabel => text().withDefault(const Constant('unit'))();
  TextColumn get activeIngredient => text().nullable()();
  TextColumn get dosageAndRoute => text().nullable()();
  TextColumn get withdrawalMeat => text().nullable()();
  TextColumn get withdrawalMilk => text().nullable()();
  TextColumn get withdrawalEggs => text().nullable()();
  TextColumn get warnings => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  BoolColumn get isSellable => boolean().withDefault(const Constant(true))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Sellable pack sizes derive from the single authoritative base quantity on
/// [InventoryItems]. A box/carton is never maintained as separate stock.
class ProductUnits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  IntColumn get inventoryItemId => integer().references(InventoryItems, #id)();
  TextColumn get unitLabel => text()();
  BoolColumn get isBaseUnit => boolean().withDefault(const Constant(false))();
  IntColumn get conversionToBase => integer()();
  RealColumn get sellingPrice => real()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {inventoryItemId, unitLabel},
  ];
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

class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  IntColumn get animalId => integer().nullable().references(Animals, #id)();
  TextColumn get farmId => text().nullable().references(Farms, #id)();
  DateTimeColumn get farmVisitDate => dateTime().nullable()();
  TextColumn get clientNameSnapshot => text().nullable()();
  TextColumn get clientPhoneSnapshot => text().nullable()();
  IntColumn get appointmentId =>
      integer().nullable().references(Appointments, #id)();
  IntColumn get consultationId =>
      integer().nullable().references(Visits, #id)();
  TextColumn get reference => text()();
  TextColumn get status => text().withDefault(const Constant('Pending'))();
  TextColumn get contextType =>
      text().withDefault(const Constant('clinic_visit'))();
  RealColumn get productsSubtotal => real().withDefault(const Constant(0))();
  RealColumn get servicesSubtotal => real().withDefault(const Constant(0))();
  RealColumn get consultationFee => real().withDefault(const Constant(0))();
  RealColumn get homeServiceFee => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  RealColumn get refundTotal => real().withDefault(const Constant(0))();
  RealColumn get balance => real().withDefault(const Constant(0))();
  TextColumn get paymentMethod => text().nullable()();
  IntColumn get linkedClinicalOperationId =>
      integer().nullable().references(ClinicalOperationRecords, #id)();
  DateTimeColumn get paidAt => dateTime().nullable()();
  TextColumn get paidByUserId =>
      text().nullable().references(AppUsers, #userId)();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidedByUserId =>
      text().nullable().references(AppUsers, #userId)();
  TextColumn get voidReason => text().nullable()();
  TextColumn get clinicNameSnapshot => text()();
  TextColumn get clinicAddressSnapshot => text().nullable()();
  TextColumn get clinicPhoneSnapshot => text().nullable()();
  TextColumn get clinicEmailSnapshot => text().nullable()();
  TextColumn get createdByUserId => text().references(AppUsers, #userId)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, reference},
  ];
}

/// Payment and refund ledger. Original transactions are never overwritten;
/// invoice totals are cached for fast list rendering and reconciled from this
/// ledger inside the same database transaction.
class InvoicePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  IntColumn get invoiceId => integer().references(Invoices, #id)();
  TextColumn get receiptNumber => text()();
  TextColumn get transactionType =>
      text().withDefault(const Constant('Payment'))();
  RealColumn get amount => real()();
  TextColumn get paymentMethod => text()();
  TextColumn get processedByUserId => text().references(AppUsers, #userId)();
  IntColumn get originalPaymentId =>
      integer().nullable().references(InvoicePayments, #id)();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, receiptNumber},
  ];
}

class InvoiceProductLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(Invoices, #id)();
  IntColumn get inventoryItemId => integer().references(InventoryItems, #id)();
  IntColumn get animalId => integer().nullable().references(Animals, #id)();
  TextColumn get productNameSnapshot => text()();
  TextColumn get categoryNameSnapshot => text()();
  TextColumn get batchNumberSnapshot => text().nullable()();
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get unitCostSnapshot => real().nullable()();
  RealColumn get lineTotal => real()();
}

class InvoiceServiceLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(Invoices, #id)();
  IntColumn get animalId => integer().nullable().references(Animals, #id)();
  IntColumn get farmUnitId => integer().nullable().references(FarmUnits, #id)();
  IntColumn get sourceTreatmentRecordId =>
      integer().nullable().references(FarmHealthRecords, #id)();
  TextColumn get description => text()();
  RealColumn get amount => real()();
  RealColumn get costSnapshot => real().nullable()();
}

class InventoryStockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  IntColumn get inventoryItemId => integer().references(InventoryItems, #id)();
  TextColumn get movementType => text()();
  IntColumn get quantityChange => integer()();
  IntColumn get quantityBefore => integer()();
  IntColumn get quantityAfter => integer()();
  IntColumn get invoiceId => integer().nullable().references(Invoices, #id)();
  TextColumn get performedByUserId => text().references(AppUsers, #userId)();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
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
  TextColumn get assignedStaffId =>
      text().nullable().references(AppUsers, #userId)();
  TextColumn get notes => text().nullable()();
  IntColumn get consultationId =>
      integer().nullable().references(Visits, #id)();
  TextColumn get reference => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class AppointmentReminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get appointmentId => integer().references(Appointments, #id)();
  IntColumn get daysBefore => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get notificationId => integer()();
  DateTimeColumn get scheduledFor => dateTime().nullable()();
  DateTimeColumn get lastScheduledAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {appointmentId, daysBefore},
    {notificationId},
  ];
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
  TextColumn get status => text().withDefault(const Constant('unread'))();
  TextColumn get destinationType => text().nullable()();
  IntColumn get destinationEntityId => integer().nullable()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  DateTimeColumn get dismissedAt => dateTime().nullable()();
  IntColumn get systemNotificationId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Clinic-owned role policies supplement the built-in role templates. A row is
/// created only when a clinic customizes a default role or adds a custom role;
/// this keeps existing staff and their permissions intact during migration.
class ClinicRolePolicies extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get roleName => text()();
  TextColumn get description => text().nullable()();
  TextColumn get permissions => text().withDefault(const Constant('[]'))();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, roleName},
  ];
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

/// Concise operational timeline. Unlike audit logs, these events describe
/// completed clinic work suitable for dashboards and daily reports.
class ClinicActivityEvents extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get performedByUserId => text().nullable()();
  TextColumn get relatedEntityType => text().nullable()();
  TextColumn get relatedEntityId => text().nullable()();
  IntColumn get patientId => integer().nullable().references(Animals, #id)();
  TextColumn get module => text().nullable()();
  TextColumn get metadata => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Marks explicitly generated, development-only datasets. Keeping the marker
/// separate from clinic records makes a reset precise and prevents generated
/// data from being mistaken for ordinary clinic work.
class DevelopmentDatasetMarkers extends Table {
  TextColumn get datasetId => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get version => text()();
  DateTimeColumn get generatedAt => dateTime()();
  TextColumn get settings => text().nullable()();

  @override
  Set<Column> get primaryKey => {datasetId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, version},
  ];
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

/// Farm data stays inside the existing clinic database.  Stable string IDs make
/// later cloud synchronization possible without replacing local relationships.
class Farms extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get name => text().withLength(min: 2, max: 160)();
  TextColumn get location => text().nullable()();
  TextColumn get speciesJson => text().withDefault(const Constant('[]'))();
  TextColumn get breedJson => text().withDefault(const Constant('[]'))();
  TextColumn get ownerOrganization => text().nullable()();
  TextColumn get contactNumber => text().nullable()();
  TextColumn get farmType => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('Active'))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get createdByUserId => text().references(AppUsers, #userId)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, name},
  ];
}

class FarmUnits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get unitType => text().withDefault(const Constant('Pen'))();
  TextColumn get speciesId => text().nullable()();
  TextColumn get breedId => text().nullable()();
  IntColumn get capacity => integer().nullable()();
  IntColumn get maleCount => integer().withDefault(const Constant(0))();
  IntColumn get femaleCount => integer().withDefault(const Constant(0))();
  IntColumn get unknownCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('Active'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get createdByUserId => text().references(AppUsers, #userId)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {farmId, name},
  ];
}

class FarmDailyRecords extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  DateTimeColumn get recordDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('Draft'))();
  IntColumn get openingPopulation => integer().withDefault(const Constant(0))();
  IntColumn get births => integer().withDefault(const Constant(0))();
  IntColumn get purchases => integer().withDefault(const Constant(0))();
  IntColumn get transfersIn => integer().withDefault(const Constant(0))();
  IntColumn get mortality => integer().withDefault(const Constant(0))();
  IntColumn get sales => integer().withDefault(const Constant(0))();
  IntColumn get transfersOut => integer().withDefault(const Constant(0))();
  IntColumn get closingPopulation => integer().withDefault(const Constant(0))();
  RealColumn get feedSuppliedKg => real().withDefault(const Constant(0))();
  TextColumn get dailyNote => text().nullable()();
  TextColumn get tasksForTomorrow => text().nullable()();
  TextColumn get correctionReason => text().nullable()();
  TextColumn get originalSnapshotJson => text().nullable()();
  TextColumn get lastEditedByUserId => text().nullable()();
  DateTimeColumn get finalizedAt => dateTime().nullable()();
  TextColumn get finalizedByUserId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get createdByUserId => text().references(AppUsers, #userId)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {farmId, recordDate},
  ];
}

class FarmSpeciesPopulationMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  TextColumn get dailyRecordId => text().references(FarmDailyRecords, #id)();
  TextColumn get speciesId => text()();
  IntColumn get openingPopulation => integer().withDefault(const Constant(0))();
  IntColumn get births => integer().withDefault(const Constant(0))();
  IntColumn get purchases => integer().withDefault(const Constant(0))();
  IntColumn get transfersIn => integer().withDefault(const Constant(0))();
  IntColumn get mortality => integer().withDefault(const Constant(0))();
  IntColumn get sales => integer().withDefault(const Constant(0))();
  IntColumn get transfersOut => integer().withDefault(const Constant(0))();
  IntColumn get closingPopulation => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {dailyRecordId, speciesId},
  ];
}

class FarmMortalityRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  TextColumn get dailyRecordId => text().references(FarmDailyRecords, #id)();
  IntColumn get farmUnitId => integer().nullable().references(FarmUnits, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get speciesId => text().nullable()();
  IntColumn get numberDead => integer()();
  TextColumn get suspectedCause =>
      text().withDefault(const Constant('Unknown'))();
  TextColumn get notes => text().nullable()();
  TextColumn get recordedByUserId => text().references(AppUsers, #userId)();
}

class FarmFeedRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  TextColumn get dailyRecordId => text().references(FarmDailyRecords, #id)();
  IntColumn get farmUnitId => integer().nullable().references(FarmUnits, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get rationName => text()();
  TextColumn get preparationType =>
      text().withDefault(const Constant('Mixed'))();
  RealColumn get totalMixedKg => real().withDefault(const Constant(0))();
  RealColumn get totalSuppliedKg => real().withDefault(const Constant(0))();
  RealColumn get remainingKg => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get recordedByUserId => text().references(AppUsers, #userId)();
}

class FarmEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  TextColumn get dailyRecordId => text().references(FarmDailyRecords, #id)();
  IntColumn get farmUnitId => integer().nullable().references(FarmUnits, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get eventType => text()();
  TextColumn get description => text().nullable()();
  TextColumn get responsibleUserId => text().nullable()();
  TextColumn get createdByUserId => text().references(AppUsers, #userId)();
}

class FarmReproductionRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  IntColumn get farmUnitId => integer().nullable().references(FarmUnits, #id)();
  TextColumn get animalIdentifier => text()();
  TextColumn get speciesId => text().nullable()();
  DateTimeColumn get heatDetectedAt => dateTime().nullable()();
  DateTimeColumn get serviceAt => dateTime().nullable()();
  TextColumn get serviceType => text().nullable()();
  DateTimeColumn get expectedDeliveryAt => dateTime().nullable()();
  DateTimeColumn get deliveryAt => dateTime().nullable()();
  IntColumn get bornAlive => integer().withDefault(const Constant(0))();
  IntColumn get stillborn => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdByUserId => text().references(AppUsers, #userId)();
  DateTimeColumn get createdAt => dateTime()();
}

class FarmHealthRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  TextColumn get dailyRecordId =>
      text().nullable().references(FarmDailyRecords, #id)();
  IntColumn get farmUnitId => integer().nullable().references(FarmUnits, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get eventType => text()();
  TextColumn get product => text().nullable()();
  TextColumn get manufacturer => text().nullable()();
  TextColumn get batchNumber => text().nullable()();
  TextColumn get purpose => text().nullable()();
  TextColumn get dose => text().nullable()();
  TextColumn get route => text().nullable()();
  IntColumn get animalsCovered => integer().nullable()();
  TextColumn get administeredBy => text().nullable()();
  DateTimeColumn get nextDueDate => dateTime().nullable()();
  RealColumn get billableAmount => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdByUserId => text().references(AppUsers, #userId)();
}

class FarmReportSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get clinicId => text().references(Clinics, #clinicId)();
  TextColumn get farmId => text().references(Farms, #id)();
  TextColumn get dailyRecordId => text().references(FarmDailyRecords, #id)();
  TextColumn get filePath => text().nullable()();
  TextColumn get snapshotJson => text()();
  BoolColumn get isAmended => boolean().withDefault(const Constant(false))();
  DateTimeColumn get generatedAt => dateTime()();
  TextColumn get generatedByUserId => text().references(AppUsers, #userId)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Clinics,
    ClinicWorkHours,
    ClinicWorkDays,
    AppUsers,
    Owners,
    Animals,
    ClinicNumberSequences,
    Visits,
    ClinicalOperationRecords,
    ClinicalOperationItems,
    ClinicalOperationActions,
    ClinicalDocumentVersions,
    Vaccinations,
    InventoryItems,
    ProductUnits,
    Sales,
    Invoices,
    InvoicePayments,
    InvoiceProductLines,
    InvoiceServiceLines,
    InventoryStockMovements,
    Appointments,
    AppointmentReminders,
    VaccinationProtocols,
    Notifications,
    ClinicRolePolicies,
    AuditLogs,
    ClinicActivityEvents,
    DevelopmentDatasetMarkers,
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
    Farms,
    FarmUnits,
    FarmDailyRecords,
    FarmSpeciesPopulationMovements,
    FarmMortalityRecords,
    FarmFeedRecords,
    FarmEvents,
    FarmReproductionRecords,
    FarmHealthRecords,
    FarmReportSnapshots,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openDatabaseConnection());

  AppDatabase.forTesting(super.executor);

  static const currentSchemaVersion = 28;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Debug builds from the early local-first migrations could be left with
      // an advanced user_version but only a subset of the expected tables.
      // Resume those upgrades by adding missing tables without touching any
      // table or record that already exists.
      if (from >= 11) {
        for (final table in allTables) {
          if (!await _hasTable(table.actualTableName)) {
            await m.createTable(table);
          }
        }
      }
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
      if (from < 11) {
        await m.addColumn(appUsers, appUsers.membershipStatus);
        await m.addColumn(appUsers, appUsers.formerStaffAt);
        await m.addColumn(appUsers, appUsers.formerStaffBy);
        await m.addColumn(appUsers, appUsers.archivedAt);
        await m.addColumn(appUsers, appUsers.archivedBy);
        await m.addColumn(appUsers, appUsers.removalReason);
        await m.addColumn(appUsers, appUsers.removalNote);
        await m.addColumn(appUsers, appUsers.previousRole);
      }
      if (from < 12) {
        // A previous debug build could stop after adding some version-12
        // objects but before SQLite recorded the new user_version. Check each
        // object so the upgrade resumes safely instead of failing on a
        // duplicate-column error at sign-in.
        if (!await _hasColumn('clinics', 'patient_number_prefix')) {
          await m.addColumn(clinics, clinics.patientNumberPrefix);
        }
        if (!await _hasColumn('clinics', 'patient_number_sequence_length')) {
          await m.addColumn(clinics, clinics.patientNumberSequenceLength);
        }
        if (!await _hasColumn('clinics', 'patient_number_reset_yearly')) {
          await m.addColumn(clinics, clinics.patientNumberResetYearly);
        }
        if (!await _hasColumn('clinics', 'patient_number_prefix_reviewed')) {
          await m.addColumn(clinics, clinics.patientNumberPrefixReviewed);
        }
        if (!await _hasColumn('clinics', 'patient_number_last_changed_at')) {
          await m.addColumn(clinics, clinics.patientNumberLastChangedAt);
        }
        if (!await _hasColumn('clinics', 'patient_number_last_changed_by')) {
          await m.addColumn(clinics, clinics.patientNumberLastChangedBy);
        }
        if (!await _hasTable('clinic_number_sequences')) {
          await m.createTable(clinicNumberSequences);
        }
        // Add patient-numbering columns in place. Rebuilding `animals` with
        // TableMigration is unsafe here because existing clinical tables hold
        // foreign keys to patient rows, and an interrupted rebuild leaves the
        // database at version 11 even after earlier version-12 objects exist.
        if (!await _hasColumn('animals', 'number_assignment_status')) {
          await m.addColumn(animals, animals.numberAssignmentStatus);
        }
        if (!await _hasColumn('animals', 'temporary_hospital_number')) {
          await m.addColumn(animals, animals.temporaryHospitalNumber);
        }
        if (!await _hasColumn('animals', 'registration_year')) {
          await m.addColumn(animals, animals.registrationYear);
        }
        if (!await _hasColumn('animals', 'registration_submission_id')) {
          await m.addColumn(animals, animals.registrationSubmissionId);
        }
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'animals_clinic_hospital_number_unique '
          'ON animals (clinic_id, hospital_number)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'animals_clinic_submission_id_unique '
          'ON animals (clinic_id, registration_submission_id)',
        );
      }
      if (from < 13) {
        if (!await _hasColumn('appointments', 'assigned_staff_id')) {
          await m.addColumn(appointments, appointments.assignedStaffId);
        }
        if (!await _hasColumn('appointments', 'notes')) {
          await m.addColumn(appointments, appointments.notes);
        }
        if (!await _hasColumn('appointments', 'consultation_id')) {
          await m.addColumn(appointments, appointments.consultationId);
        }
        if (!await _hasColumn('appointments', 'reference')) {
          await m.addColumn(appointments, appointments.reference);
        }
        if (!await _hasColumn('appointments', 'created_at')) {
          await m.addColumn(appointments, appointments.createdAt);
        }
        if (!await _hasColumn('appointments', 'updated_at')) {
          await m.addColumn(appointments, appointments.updatedAt);
        }
        if (!await _hasTable('appointment_reminders')) {
          await m.createTable(appointmentReminders);
        }
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'appointment_reminders_appointment_days_unique '
          'ON appointment_reminders (appointment_id, days_before)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'appointment_reminders_notification_unique '
          'ON appointment_reminders (notification_id)',
        );
      }
      if (from < 14) {
        if (!await _hasColumn('inventory_items', 'category_id')) {
          await m.addColumn(inventoryItems, inventoryItems.categoryId);
        }
        if (!await _hasColumn('inventory_items', 'is_sellable')) {
          await m.addColumn(inventoryItems, inventoryItems.isSellable);
        }
        if (!await _hasColumn('inventory_items', 'is_archived')) {
          await m.addColumn(inventoryItems, inventoryItems.isArchived);
        }
        if (!await _hasColumn('inventory_items', 'created_at')) {
          await m.addColumn(inventoryItems, inventoryItems.createdAt);
        }
        if (!await _hasColumn('inventory_items', 'updated_at')) {
          await m.addColumn(inventoryItems, inventoryItems.updatedAt);
        }
        if (!await _hasTable('invoices')) await m.createTable(invoices);
        if (!await _hasTable('invoice_product_lines')) {
          await m.createTable(invoiceProductLines);
        }
        if (!await _hasTable('invoice_service_lines')) {
          await m.createTable(invoiceServiceLines);
        }
        if (!await _hasTable('inventory_stock_movements')) {
          await m.createTable(inventoryStockMovements);
        }
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS invoices_clinic_reference_unique '
          'ON invoices (clinic_id, reference)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS inventory_stock_movements_item_index '
          'ON inventory_stock_movements (clinic_id, inventory_item_id)',
        );
      }
      if (from < 15) {
        if (!await _hasTable('clinic_role_policies')) {
          await m.createTable(clinicRolePolicies);
        }
      }
      if (from < 16) {
        if (!await _hasColumn('notifications', 'status')) {
          await m.addColumn(notifications, notifications.status);
        }
        if (!await _hasColumn('notifications', 'destination_type')) {
          await m.addColumn(notifications, notifications.destinationType);
        }
        if (!await _hasColumn('notifications', 'destination_entity_id')) {
          await m.addColumn(notifications, notifications.destinationEntityId);
        }
        if (!await _hasColumn('notifications', 'delivered_at')) {
          await m.addColumn(notifications, notifications.deliveredAt);
        }
        if (!await _hasColumn('notifications', 'read_at')) {
          await m.addColumn(notifications, notifications.readAt);
        }
        if (!await _hasColumn('notifications', 'reviewed_at')) {
          await m.addColumn(notifications, notifications.reviewedAt);
        }
        if (!await _hasColumn('notifications', 'dismissed_at')) {
          await m.addColumn(notifications, notifications.dismissedAt);
        }
        if (!await _hasColumn('notifications', 'system_notification_id')) {
          await m.addColumn(notifications, notifications.systemNotificationId);
        }
        await customStatement(
          "UPDATE notifications SET status = CASE WHEN is_read = 1 THEN 'read' ELSE 'unread' END "
          "WHERE status IS NULL OR status = '' OR status = 'unread'",
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS notifications_clinic_status_index '
          'ON notifications (clinic_id, status, created_at)',
        );
      }
      if (from < 17) {
        if (!await _hasTable('clinic_activity_events')) {
          await m.createTable(clinicActivityEvents);
        }
        await customStatement(
          'CREATE INDEX IF NOT EXISTS clinic_activity_events_timeline_index '
          'ON clinic_activity_events (clinic_id, occurred_at)',
        );
      }
      if (from < 18) {
        if (!await _hasTable('development_dataset_markers')) {
          await m.createTable(developmentDatasetMarkers);
        }
      }
      if (from < 19) {
        if (!await _hasTable('farms')) await m.createTable(farms);
        if (!await _hasTable('farm_units')) await m.createTable(farmUnits);
        if (!await _hasTable('farm_daily_records')) {
          await m.createTable(farmDailyRecords);
        }
        if (!await _hasTable('farm_mortality_records')) {
          await m.createTable(farmMortalityRecords);
        }
        if (!await _hasTable('farm_feed_records')) {
          await m.createTable(farmFeedRecords);
        }
        if (!await _hasTable('farm_events')) await m.createTable(farmEvents);
        if (!await _hasTable('farm_reproduction_records')) {
          await m.createTable(farmReproductionRecords);
        }
        if (!await _hasTable('farm_health_records')) {
          await m.createTable(farmHealthRecords);
        }
        if (!await _hasTable('farm_report_snapshots')) {
          await m.createTable(farmReportSnapshots);
        }
        await customStatement(
          'CREATE INDEX IF NOT EXISTS farms_clinic_status_index '
          'ON farms (clinic_id, status, name)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS farm_daily_records_timeline_index '
          'ON farm_daily_records (clinic_id, farm_id, record_date)',
        );
      }
      if (from < 20) {
        if (!await _hasColumn('vaccinations', 'source_vaccination_id')) {
          await m.addColumn(vaccinations, vaccinations.sourceVaccinationId);
        }
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS vaccinations_source_schedule_unique '
          'ON vaccinations (source_vaccination_id) '
          'WHERE source_vaccination_id IS NOT NULL',
        );
      }
      if (from < 21) {
        if (!await _hasColumn('farms', 'owner_organization')) {
          await m.addColumn(farms, farms.ownerOrganization);
        }
        if (!await _hasColumn('farms', 'contact_number')) {
          await m.addColumn(farms, farms.contactNumber);
        }
        if (!await _hasColumn('farms', 'farm_type')) {
          await m.addColumn(farms, farms.farmType);
        }
        if (!await _hasColumn('farms', 'notes')) {
          await m.addColumn(farms, farms.notes);
        }
        if (!await _hasColumn('farm_units', 'species_id')) {
          await m.addColumn(farmUnits, farmUnits.speciesId);
        }
        if (!await _hasColumn('farm_units', 'breed_id')) {
          await m.addColumn(farmUnits, farmUnits.breedId);
        }
        if (!await _hasColumn('farm_units', 'notes')) {
          await m.addColumn(farmUnits, farmUnits.notes);
        }
        if (!await _hasColumn('farm_daily_records', 'correction_reason')) {
          await m.addColumn(
            farmDailyRecords,
            farmDailyRecords.correctionReason,
          );
        }
        if (!await _hasColumn('farm_daily_records', 'original_snapshot_json')) {
          await m.addColumn(
            farmDailyRecords,
            farmDailyRecords.originalSnapshotJson,
          );
        }
        if (!await _hasColumn('farm_daily_records', 'last_edited_by_user_id')) {
          await m.addColumn(
            farmDailyRecords,
            farmDailyRecords.lastEditedByUserId,
          );
        }
        if (!await _hasTable('farm_species_population_movements')) {
          await m.createTable(farmSpeciesPopulationMovements);
        }
        await customStatement(
          'CREATE INDEX IF NOT EXISTS farm_species_population_timeline_index '
          'ON farm_species_population_movements '
          '(clinic_id, farm_id, daily_record_id, species_id)',
        );
      }
      if (from < 22) {
        if (!await _hasTable('clinical_operation_records')) {
          await m.createTable(clinicalOperationRecords);
        }
        await customStatement(
          'CREATE INDEX IF NOT EXISTS clinical_operation_records_clinic_type_index '
          'ON clinical_operation_records (clinic_id, operation_type, status, scheduled_at)',
        );
      }
      if (from < 23) {
        final operationColumns = <String, GeneratedColumn>{
          'hospitalization_id': clinicalOperationRecords.hospitalizationId,
          'source_operation_id': clinicalOperationRecords.sourceOperationId,
          'reference_number': clinicalOperationRecords.referenceNumber,
          'priority': clinicalOperationRecords.priority,
          'estimated_amount': clinicalOperationRecords.estimatedAmount,
          'created_by_user_id': clinicalOperationRecords.createdByUserId,
          'updated_by_user_id': clinicalOperationRecords.updatedByUserId,
          'archived_at': clinicalOperationRecords.archivedAt,
          'record_version': clinicalOperationRecords.recordVersion,
          'sync_status': clinicalOperationRecords.syncStatus,
        };
        for (final entry in operationColumns.entries) {
          if (!await _hasColumn('clinical_operation_records', entry.key)) {
            await m.addColumn(clinicalOperationRecords, entry.value);
          }
        }
        final invoiceColumns = <String, GeneratedColumn>{
          'amount_paid': invoices.amountPaid,
          'refund_total': invoices.refundTotal,
          'balance': invoices.balance,
          'linked_clinical_operation_id': invoices.linkedClinicalOperationId,
        };
        for (final entry in invoiceColumns.entries) {
          if (!await _hasColumn('invoices', entry.key)) {
            await m.addColumn(invoices, entry.value);
          }
        }
        if (!await _hasTable(clinicalOperationItems.actualTableName)) {
          await m.createTable(clinicalOperationItems);
        }
        if (!await _hasTable(clinicalOperationActions.actualTableName)) {
          await m.createTable(clinicalOperationActions);
        }
        if (!await _hasTable(clinicalDocumentVersions.actualTableName)) {
          await m.createTable(clinicalDocumentVersions);
        }
        if (!await _hasTable(invoicePayments.actualTableName)) {
          await m.createTable(invoicePayments);
        }
        await customStatement(
          "UPDATE invoices SET amount_paid = CASE WHEN status = 'Paid' THEN total ELSE 0 END, "
          "balance = CASE WHEN status = 'Paid' THEN 0 ELSE total END "
          'WHERE amount_paid = 0 AND balance = 0',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS clinical_operations_patient_status_index '
          'ON clinical_operation_records (clinic_id, animal_id, operation_type, status, created_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS clinical_operation_items_operation_index '
          'ON clinical_operation_items (clinic_id, operation_id, status)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS clinical_operation_actions_timeline_index '
          'ON clinical_operation_actions (clinic_id, operation_id, occurred_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS clinical_document_versions_operation_index '
          'ON clinical_document_versions (clinic_id, operation_id, version_number)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS invoice_payments_invoice_index '
          'ON invoice_payments (clinic_id, invoice_id, created_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS invoices_history_index '
          'ON invoices (clinic_id, status, created_at)',
        );
      }
      if (from < 24) {
        if (!await _hasColumn('animals', 'date_of_birth')) {
          await m.addColumn(animals, animals.dateOfBirth);
        }
        final ageColumns = <String, GeneratedColumn>{
          'is_date_of_birth_estimated': animals.isDateOfBirthEstimated,
          'original_age_value': animals.originalAgeValue,
          'original_age_unit': animals.originalAgeUnit,
          'age_recorded_at': animals.ageRecordedAt,
        };
        for (final entry in ageColumns.entries) {
          if (!await _hasColumn('animals', entry.key)) {
            await m.addColumn(animals, entry.value);
          }
        }

        final canMigrateLegacyAge =
            await _hasColumn('animals', 'age') &&
            await _hasColumn('animals', 'date_registered');
        if (canMigrateLegacyAge) {
          final query = selectOnly(animals)
            ..addColumns([animals.id, animals.age, animals.dateRegistered])
            ..where(animals.dateOfBirth.isNull() & animals.age.isNotNull());
          final legacyAnimals = await query.get();
          for (final row in legacyAnimals) {
            final animalId = row.read(animals.id);
            final legacyAge = row.read(animals.age);
            final referenceDate = row.read(animals.dateRegistered);
            if (animalId == null ||
                legacyAge == null ||
                legacyAge < 0 ||
                referenceDate == null) {
              continue;
            }
            final estimatedBirthDate = AnimalAgeService.estimateDateOfBirth(
              value: legacyAge,
              unit: AnimalAgeUnit.years,
              referenceDate: referenceDate,
            );
            await (update(
              animals,
            )..where((animal) => animal.id.equals(animalId))).write(
              AnimalsCompanion(
                dateOfBirth: Value(estimatedBirthDate),
                isDateOfBirthEstimated: const Value(true),
                originalAgeValue: Value(legacyAge),
                originalAgeUnit: const Value('years'),
                ageRecordedAt: Value(referenceDate),
              ),
            );
          }
        }
        await customStatement(
          'CREATE INDEX IF NOT EXISTS animals_clinic_birth_date_index '
          'ON animals (clinic_id, date_of_birth)',
        );
      }
      if (from < 25) {
        if (!await _hasColumn('invoice_product_lines', 'animal_id')) {
          await m.addColumn(invoiceProductLines, invoiceProductLines.animalId);
        }
        if (!await _hasColumn('invoice_service_lines', 'animal_id')) {
          await m.addColumn(invoiceServiceLines, invoiceServiceLines.animalId);
        }
        await customStatement(
          'UPDATE invoice_product_lines SET animal_id = '
          '(SELECT animal_id FROM invoices WHERE invoices.id = invoice_product_lines.invoice_id) '
          'WHERE animal_id IS NULL',
        );
        await customStatement(
          'UPDATE invoice_service_lines SET animal_id = '
          '(SELECT animal_id FROM invoices WHERE invoices.id = invoice_service_lines.invoice_id) '
          'WHERE animal_id IS NULL',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS invoice_product_lines_animal_index '
          'ON invoice_product_lines (invoice_id, animal_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS invoice_service_lines_animal_index '
          'ON invoice_service_lines (invoice_id, animal_id)',
        );
      }
      if (from < 26) {
        if (!await _hasColumn('invoices', 'context_type')) {
          await m.addColumn(invoices, invoices.contextType);
        }
        if (!await _hasColumn('invoice_product_lines', 'unit_cost_snapshot')) {
          await m.addColumn(
            invoiceProductLines,
            invoiceProductLines.unitCostSnapshot,
          );
        }
        if (!await _hasColumn('invoice_service_lines', 'cost_snapshot')) {
          await m.addColumn(
            invoiceServiceLines,
            invoiceServiceLines.costSnapshot,
          );
        }
        if (!await _hasColumn('farm_health_records', 'manufacturer')) {
          await m.addColumn(farmHealthRecords, farmHealthRecords.manufacturer);
        }
        if (!await _hasColumn('farm_health_records', 'batch_number')) {
          await m.addColumn(farmHealthRecords, farmHealthRecords.batchNumber);
        }
        if (!await _hasColumn('farm_health_records', 'animals_covered')) {
          await m.addColumn(
            farmHealthRecords,
            farmHealthRecords.animalsCovered,
          );
        }
        if (!await _hasColumn('farm_health_records', 'administered_by')) {
          await m.addColumn(
            farmHealthRecords,
            farmHealthRecords.administeredBy,
          );
        }
      }
      if (from < 27) {
        final inventoryColumns = <String, GeneratedColumn>{
          'base_unit_label': inventoryItems.baseUnitLabel,
          'active_ingredient': inventoryItems.activeIngredient,
          'dosage_and_route': inventoryItems.dosageAndRoute,
          'withdrawal_meat': inventoryItems.withdrawalMeat,
          'withdrawal_milk': inventoryItems.withdrawalMilk,
          'withdrawal_eggs': inventoryItems.withdrawalEggs,
          'warnings': inventoryItems.warnings,
          'image_path': inventoryItems.imagePath,
        };
        for (final entry in inventoryColumns.entries) {
          if (!await _hasColumn('inventory_items', entry.key)) {
            await m.addColumn(inventoryItems, entry.value);
          }
        }
        if (!await _hasTable(productUnits.actualTableName)) {
          await m.createTable(productUnits);
        }
        await customStatement(
          'INSERT OR IGNORE INTO product_units '
          '(clinic_id, inventory_item_id, unit_label, is_base_unit, '
          'conversion_to_base, selling_price, created_at) '
          "SELECT clinic_id, id, base_unit_label, 1, 1, selling_price, "
          "COALESCE(created_at, CURRENT_TIMESTAMP) FROM inventory_items",
        );

        // Farm invoices have no patient. Rebuild this one table so the legacy
        // animal foreign key becomes nullable while every existing row and
        // relationship remains intact.
        await m.alterTable(
          TableMigration(
            invoices,
            newColumns: [
              invoices.farmId,
              invoices.farmVisitDate,
              invoices.clientNameSnapshot,
              invoices.clientPhoneSnapshot,
            ],
          ),
        );
        if (!await _hasColumn('invoice_service_lines', 'farm_unit_id')) {
          await m.addColumn(
            invoiceServiceLines,
            invoiceServiceLines.farmUnitId,
          );
        }
        if (!await _hasColumn(
          'invoice_service_lines',
          'source_treatment_record_id',
        )) {
          await m.addColumn(
            invoiceServiceLines,
            invoiceServiceLines.sourceTreatmentRecordId,
          );
        }
        if (!await _hasColumn('farm_health_records', 'billable_amount')) {
          await m.addColumn(
            farmHealthRecords,
            farmHealthRecords.billableAmount,
          );
        }
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'invoice_service_treatment_source_unique '
          'ON invoice_service_lines (source_treatment_record_id) '
          'WHERE source_treatment_record_id IS NOT NULL',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS invoices_farm_visit_index '
          'ON invoices (clinic_id, farm_id, farm_visit_date, status)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS product_units_item_index '
          'ON product_units (clinic_id, inventory_item_id)',
        );
      }
      if (from < 28) {
        // Repair clients that already ran v27 before the invoice columns were
        // declared as new columns in the Drift table migration.
        await customStatement(
          "UPDATE invoices SET farm_id = NULL WHERE farm_id = 'farm_id'",
        );
        await customStatement(
          "UPDATE invoices SET farm_visit_date = NULL "
          "WHERE farm_visit_date = 'farm_visit_date'",
        );
        await customStatement(
          "UPDATE invoices SET client_name_snapshot = NULL "
          "WHERE client_name_snapshot = 'client_name_snapshot'",
        );
        await customStatement(
          "UPDATE invoices SET client_phone_snapshot = NULL "
          "WHERE client_phone_snapshot = 'client_phone_snapshot'",
        );
      }
    },
  );

  Future<bool> _hasTable(String tableName) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(tableName)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _hasColumn(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName)').get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }
}
