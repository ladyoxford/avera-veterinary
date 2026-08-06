class AccountTypes {
  const AccountTypes._();

  static const platformOwner = 'PlatformOwner';
  static const platformAdministrator = 'PlatformAdministrator';
  static const clinicAdministrator = 'ClinicAdministrator';
  static const clinicStaff = 'ClinicStaff';
}

class AccountStatuses {
  const AccountStatuses._();

  static const invited = 'Invited';
  static const active = 'Active';
  static const suspended = 'Suspended';
  static const locked = 'Locked';
  static const deactivated = 'Deactivated';
}

/// Clinic-scoped employment state. It is deliberately separate from the
/// account status because one identity can have a valid role elsewhere.
class ClinicMembershipStatuses {
  const ClinicMembershipStatuses._();

  static const active = 'Active';
  static const suspended = 'Suspended';
  static const formerStaff = 'Former Staff';
  static const archived = 'Archived';
}

class Permissions {
  const Permissions._();

  static const patientsView = 'patients.view';
  static const patientsCreate = 'patients.create';
  static const patientsEdit = 'patients.edit';
  static const managePatientNumbering = 'patients.numbering.manage';
  static const consultationsView = 'consultations.view';
  static const consultationsCreate = 'consultations.create';
  static const consultationsEdit = 'consultations.edit';
  static const vaccinationsView = 'vaccinations.view';
  static const vaccinationsAdd = 'vaccinations.add';
  static const laboratoryView = 'laboratory.view';
  static const laboratoryAdd = 'laboratory.add';
  static const inventoryView = 'inventory.view';
  static const inventoryEdit = 'inventory.edit';
  static const inventoryCreate = 'inventory.create';
  static const inventoryAdjust = 'inventory.adjust';
  static const inventorySell = 'inventory.sell';
  static const inventoryCostView = 'inventory.cost.view';
  static const inventoryAccessManage = 'inventory.access.manage';
  static const billingView = 'billing.view';
  static const billingCreate = 'billing.create';
  static const billingHistory = 'billing.history';
  static const billingRecordPayment = 'billing.record_payment';
  static const billingRefund = 'billing.refund';
  static const billingVoid = 'billing.void';
  static const billingPrint = 'billing.print';
  static const billingExport = 'billing.export';
  static const surgeryView = 'surgery.view';
  static const surgeryCreate = 'surgery.create';
  static const surgeryEdit = 'surgery.edit';
  static const surgeryCancel = 'surgery.cancel';
  static const surgeryComplete = 'surgery.complete';
  static const surgeryManagePreop = 'surgery.manage_preop';
  static const surgeryManageIntraop = 'surgery.manage_intraop';
  static const surgeryManageRecovery = 'surgery.manage_recovery';
  static const surgeryPrint = 'surgery.print';
  static const prescriptionsView = 'prescriptions.view';
  static const prescriptionsCreate = 'prescriptions.create';
  static const prescriptionsEdit = 'prescriptions.edit';
  static const prescriptionsActivate = 'prescriptions.activate';
  static const prescriptionsCancel = 'prescriptions.cancel';
  static const prescriptionsDispense = 'prescriptions.dispense';
  static const prescriptionsPrint = 'prescriptions.print';
  static const imagingView = 'imaging.view';
  static const imagingRequest = 'imaging.request';
  static const imagingSchedule = 'imaging.schedule';
  static const imagingUpload = 'imaging.upload';
  static const imagingReport = 'imaging.report';
  static const imagingComplete = 'imaging.complete';
  static const imagingCancel = 'imaging.cancel';
  static const documentsView = 'documents.view';
  static const documentsUpload = 'documents.upload';
  static const documentsEdit = 'documents.edit';
  static const documentsDownload = 'documents.download';
  static const documentsShare = 'documents.share';
  static const documentsArchive = 'documents.archive';
  static const documentsDelete = 'documents.delete';
  static const documentsViewSensitive = 'documents.view_sensitive';
  static const treatmentBoardView = 'treatment_board.view';
  static const treatmentBoardCreate = 'treatment_board.create';
  static const treatmentBoardAdminister = 'treatment_board.administer';
  static const treatmentBoardDelay = 'treatment_board.delay';
  static const treatmentBoardWithhold = 'treatment_board.withhold';
  static const treatmentBoardCancel = 'treatment_board.cancel';
  static const treatmentBoardReopen = 'treatment_board.reopen';
  static const treatmentBoardVerifyHighRisk =
      'treatment_board.verify_high_risk';
  static const reportsExport = 'reports.export';
  static const appointmentsView = 'appointments.view';
  static const appointmentsCreate = 'appointments.create';
  static const appointmentsEdit = 'appointments.edit';
  static const appointmentsCancel = 'appointments.cancel';
  static const appointmentsStartConsultation =
      'appointments.start_consultation';
  static const appointmentsAssignClinicalStaff =
      'appointments.assign_clinical_staff';
  static const farmsView = 'farms.view';
  static const farmsCreate = 'farms.create';
  static const farmsEdit = 'farms.edit';
  static const farmsArchive = 'farms.archive';
  static const farmUnitsManage = 'farms.units.manage';
  static const farmDailyRecord = 'farms.daily.record';
  static const farmDailyFinalize = 'farms.daily.finalize';
  static const farmMortalityRecord = 'farms.mortality.record';
  static const farmFeedRecord = 'farms.feed.record';
  static const farmReproductionRecord = 'farms.reproduction.record';
  static const farmHealthRecord = 'farms.health.record';
  static const farmReportsView = 'farms.reports.view';
  static const farmReportsPrint = 'farms.reports.print';
  static const usersView = 'users.view';
  static const usersCreate = 'users.create';
  static const usersEdit = 'users.edit';
  static const usersSuspend = 'users.suspend';
  static const usersAssignRoles = 'users.assign_roles';
  static const staffRolesManage = 'staff.roles.manage';
  static const usersAssignPermissions = 'users.assign_permissions';
  static const clinicSettingsView = 'clinic_settings.view';
  static const clinicSettingsEdit = 'clinic_settings.edit';
  static const clinicWorkHoursManage = 'clinic.work_hours.manage';
  static const auditLogsView = 'audit_logs.view';
  static const clinicsView = 'clinics.view';
  static const clinicsApprove = 'clinics.approve';
  static const clinicsSuspend = 'clinics.suspend';
  static const subscriptionsManage = 'subscriptions.manage';
  static const platformUsersManage = 'platform_users.manage';
  static const platformAuditView = 'platform_audit.view';
  static const platformPlansManage = 'platform_plans.manage';
  static const platformSupportAccess = 'platform_support.access';
  static const platformAnnouncementsManage = 'platform_announcements.manage';
  static const platformVeraManage = 'platform_vera.manage';
  static const twoFactorManageSelf = 'security.twoFactor.manageSelf';
}

const surgeryPermissions = <String>{
  Permissions.surgeryView,
  Permissions.surgeryCreate,
  Permissions.surgeryEdit,
  Permissions.surgeryCancel,
  Permissions.surgeryComplete,
  Permissions.surgeryManagePreop,
  Permissions.surgeryManageIntraop,
  Permissions.surgeryManageRecovery,
  Permissions.surgeryPrint,
};

const prescriptionPermissions = <String>{
  Permissions.prescriptionsView,
  Permissions.prescriptionsCreate,
  Permissions.prescriptionsEdit,
  Permissions.prescriptionsActivate,
  Permissions.prescriptionsCancel,
  Permissions.prescriptionsDispense,
  Permissions.prescriptionsPrint,
};

const imagingPermissions = <String>{
  Permissions.imagingView,
  Permissions.imagingRequest,
  Permissions.imagingSchedule,
  Permissions.imagingUpload,
  Permissions.imagingReport,
  Permissions.imagingComplete,
  Permissions.imagingCancel,
};

const documentPermissions = <String>{
  Permissions.documentsView,
  Permissions.documentsUpload,
  Permissions.documentsEdit,
  Permissions.documentsDownload,
  Permissions.documentsShare,
  Permissions.documentsArchive,
  Permissions.documentsDelete,
  Permissions.documentsViewSensitive,
};

const treatmentBoardPermissions = <String>{
  Permissions.treatmentBoardView,
  Permissions.treatmentBoardCreate,
  Permissions.treatmentBoardAdminister,
  Permissions.treatmentBoardDelay,
  Permissions.treatmentBoardWithhold,
  Permissions.treatmentBoardCancel,
  Permissions.treatmentBoardReopen,
  Permissions.treatmentBoardVerifyHighRisk,
};

const billingPermissions = <String>{
  Permissions.billingView,
  Permissions.billingCreate,
  Permissions.billingHistory,
  Permissions.billingRecordPayment,
  Permissions.billingRefund,
  Permissions.billingVoid,
  Permissions.billingPrint,
  Permissions.billingExport,
};

const allPermissions = <String>{
  Permissions.patientsView,
  Permissions.patientsCreate,
  Permissions.patientsEdit,
  Permissions.managePatientNumbering,
  Permissions.consultationsView,
  Permissions.consultationsCreate,
  Permissions.consultationsEdit,
  Permissions.vaccinationsView,
  Permissions.vaccinationsAdd,
  Permissions.laboratoryView,
  Permissions.laboratoryAdd,
  Permissions.inventoryView,
  Permissions.inventoryEdit,
  Permissions.inventoryCreate,
  Permissions.inventoryAdjust,
  Permissions.inventorySell,
  Permissions.inventoryCostView,
  Permissions.inventoryAccessManage,
  ...billingPermissions,
  ...surgeryPermissions,
  ...prescriptionPermissions,
  ...imagingPermissions,
  ...documentPermissions,
  ...treatmentBoardPermissions,
  Permissions.reportsExport,
  Permissions.appointmentsView,
  Permissions.appointmentsCreate,
  Permissions.appointmentsEdit,
  Permissions.appointmentsCancel,
  Permissions.appointmentsStartConsultation,
  Permissions.appointmentsAssignClinicalStaff,
  Permissions.farmsView,
  Permissions.farmsCreate,
  Permissions.farmsEdit,
  Permissions.farmsArchive,
  Permissions.farmUnitsManage,
  Permissions.farmDailyRecord,
  Permissions.farmDailyFinalize,
  Permissions.farmMortalityRecord,
  Permissions.farmFeedRecord,
  Permissions.farmReproductionRecord,
  Permissions.farmHealthRecord,
  Permissions.farmReportsView,
  Permissions.farmReportsPrint,
  Permissions.usersView,
  Permissions.usersCreate,
  Permissions.usersEdit,
  Permissions.usersSuspend,
  Permissions.usersAssignRoles,
  Permissions.staffRolesManage,
  Permissions.usersAssignPermissions,
  Permissions.clinicSettingsView,
  Permissions.clinicSettingsEdit,
  Permissions.clinicWorkHoursManage,
  Permissions.auditLogsView,
  Permissions.clinicsView,
  Permissions.clinicsApprove,
  Permissions.clinicsSuspend,
  Permissions.subscriptionsManage,
  Permissions.platformUsersManage,
  Permissions.platformAuditView,
  Permissions.platformPlansManage,
  Permissions.platformSupportAccess,
  Permissions.twoFactorManageSelf,
  Permissions.platformAnnouncementsManage,
  Permissions.platformVeraManage,
};

const platformAdministratorPermissions = <String>{
  Permissions.clinicsView,
  Permissions.clinicsApprove,
  Permissions.clinicsSuspend,
  Permissions.subscriptionsManage,
  Permissions.platformAuditView,
  Permissions.platformSupportAccess,
};

const rolePermissions = <String, Set<String>>{
  'Receptionist': {
    Permissions.patientsView,
    Permissions.patientsCreate,
    Permissions.appointmentsView,
    Permissions.appointmentsCreate,
    Permissions.appointmentsEdit,
  },
  'Veterinarian': {
    Permissions.patientsView,
    Permissions.patientsCreate,
    Permissions.patientsEdit,
    Permissions.consultationsView,
    Permissions.consultationsCreate,
    Permissions.consultationsEdit,
    Permissions.vaccinationsView,
    Permissions.vaccinationsAdd,
    Permissions.laboratoryView,
    Permissions.laboratoryAdd,
    ...surgeryPermissions,
    ...prescriptionPermissions,
    ...imagingPermissions,
    ...documentPermissions,
    ...treatmentBoardPermissions,
    Permissions.billingView,
    Permissions.billingHistory,
    Permissions.billingPrint,
    Permissions.appointmentsView,
    Permissions.appointmentsCreate,
    Permissions.appointmentsEdit,
    Permissions.appointmentsStartConsultation,
    Permissions.farmsView,
    Permissions.farmDailyRecord,
    Permissions.farmMortalityRecord,
    Permissions.farmReproductionRecord,
    Permissions.farmHealthRecord,
    Permissions.farmReportsView,
  },
  'Veterinary Nurse': {
    Permissions.patientsView,
    Permissions.patientsEdit,
    Permissions.consultationsView,
    Permissions.vaccinationsView,
    Permissions.vaccinationsAdd,
    Permissions.laboratoryView,
    Permissions.surgeryView,
    Permissions.surgeryManagePreop,
    Permissions.surgeryManageRecovery,
    Permissions.prescriptionsView,
    Permissions.imagingView,
    Permissions.imagingUpload,
    Permissions.documentsView,
    Permissions.documentsUpload,
    Permissions.treatmentBoardView,
    Permissions.treatmentBoardCreate,
    Permissions.treatmentBoardAdminister,
    Permissions.treatmentBoardDelay,
    Permissions.treatmentBoardWithhold,
    Permissions.appointmentsView,
    Permissions.farmsView,
    Permissions.farmDailyRecord,
    Permissions.farmHealthRecord,
  },
  'Laboratory Staff': {Permissions.laboratoryView, Permissions.laboratoryAdd},
  'Pharmacist': {
    Permissions.inventoryView,
    Permissions.inventorySell,
    Permissions.prescriptionsView,
    Permissions.prescriptionsDispense,
    Permissions.prescriptionsPrint,
    Permissions.billingView,
    Permissions.billingHistory,
  },
  'Sales Representative': {
    Permissions.inventoryView,
    Permissions.inventorySell,
    Permissions.billingView,
    Permissions.billingCreate,
    Permissions.billingHistory,
    Permissions.billingRecordPayment,
    Permissions.billingPrint,
  },
  'Cashier': {
    Permissions.billingView,
    Permissions.billingCreate,
    Permissions.billingHistory,
    Permissions.billingRecordPayment,
    Permissions.billingPrint,
  },
  'Inventory Officer': {
    Permissions.inventoryView,
    Permissions.inventoryEdit,
    Permissions.inventoryCreate,
    Permissions.inventoryAdjust,
    Permissions.inventorySell,
    Permissions.inventoryCostView,
  },
  'Clinic Administrator': {
    Permissions.patientsView,
    Permissions.patientsCreate,
    Permissions.patientsEdit,
    Permissions.managePatientNumbering,
    Permissions.consultationsView,
    Permissions.consultationsCreate,
    Permissions.consultationsEdit,
    Permissions.usersView,
    Permissions.usersCreate,
    Permissions.usersEdit,
    Permissions.usersSuspend,
    Permissions.usersAssignRoles,
    Permissions.staffRolesManage,
    Permissions.usersAssignPermissions,
    Permissions.clinicSettingsView,
    Permissions.clinicSettingsEdit,
    Permissions.clinicWorkHoursManage,
    Permissions.auditLogsView,
    Permissions.reportsExport,
    Permissions.appointmentsView,
    Permissions.appointmentsCreate,
    Permissions.appointmentsEdit,
    Permissions.appointmentsCancel,
    Permissions.appointmentsStartConsultation,
    Permissions.appointmentsAssignClinicalStaff,
    Permissions.vaccinationsView,
    Permissions.vaccinationsAdd,
    Permissions.laboratoryView,
    Permissions.laboratoryAdd,
    Permissions.inventoryView,
    Permissions.inventoryEdit,
    Permissions.inventoryCreate,
    Permissions.inventoryAdjust,
    Permissions.inventorySell,
    Permissions.inventoryCostView,
    Permissions.inventoryAccessManage,
    ...billingPermissions,
    ...surgeryPermissions,
    ...prescriptionPermissions,
    ...imagingPermissions,
    ...documentPermissions,
    ...treatmentBoardPermissions,
    Permissions.farmsView,
    Permissions.farmsCreate,
    Permissions.farmsEdit,
    Permissions.farmsArchive,
    Permissions.farmUnitsManage,
    Permissions.farmDailyRecord,
    Permissions.farmDailyFinalize,
    Permissions.farmMortalityRecord,
    Permissions.farmFeedRecord,
    Permissions.farmReproductionRecord,
    Permissions.farmHealthRecord,
    Permissions.farmReportsView,
    Permissions.farmReportsPrint,
    Permissions.twoFactorManageSelf,
  },
  'Practice Manager': {
    Permissions.patientsView,
    Permissions.patientsCreate,
    Permissions.patientsEdit,
    Permissions.consultationsView,
    Permissions.consultationsCreate,
    Permissions.consultationsEdit,
    Permissions.vaccinationsView,
    Permissions.vaccinationsAdd,
    Permissions.laboratoryView,
    Permissions.laboratoryAdd,
    Permissions.inventoryView,
    Permissions.inventoryEdit,
    Permissions.inventoryCreate,
    Permissions.inventoryAdjust,
    Permissions.inventorySell,
    ...billingPermissions,
    ...surgeryPermissions,
    ...prescriptionPermissions,
    ...imagingPermissions,
    ...documentPermissions,
    ...treatmentBoardPermissions,
    Permissions.reportsExport,
    Permissions.appointmentsView,
    Permissions.appointmentsCreate,
    Permissions.appointmentsEdit,
    Permissions.appointmentsCancel,
    Permissions.appointmentsStartConsultation,
    Permissions.appointmentsAssignClinicalStaff,
    Permissions.farmsView,
    Permissions.farmsCreate,
    Permissions.farmsEdit,
    Permissions.farmUnitsManage,
    Permissions.farmDailyRecord,
    Permissions.farmDailyFinalize,
    Permissions.farmMortalityRecord,
    Permissions.farmFeedRecord,
    Permissions.farmReproductionRecord,
    Permissions.farmHealthRecord,
    Permissions.farmReportsView,
    Permissions.farmReportsPrint,
  },
  'Platform Administrator': platformAdministratorPermissions,
  'Platform Owner': allPermissions,
};

const clinicRoleDescriptions = <String, String>{
  'Clinic Administrator': 'Full clinic administration and operational access.',
  'Veterinarian': 'Clinical care, consultations and patient management.',
  'Veterinary Nurse': 'Clinical support, patient care and vaccination support.',
  'Receptionist': 'Patient registration and schedule coordination.',
  'Laboratory Staff': 'Laboratory workflows and result entry.',
  'Pharmacist': 'Pharmacy inventory and dispensing support.',
  'Cashier': 'Billing and payment collection.',
  'Practice Manager': 'Daily clinic operations without ownership controls.',
  'Inventory Officer': 'Inventory, stock and supplier workflows.',
  'Sales Representative': 'Point-of-sale inventory and billing access.',
};

const clinicPermissionDescriptions = <String, String>{
  Permissions.patientsView: 'View registered pets and their records.',
  Permissions.patientsCreate: 'Register new pets for this clinic.',
  Permissions.patientsEdit: 'Edit patient demographic and clinical details.',
  Permissions.managePatientNumbering: 'Manage hospital-number settings.',
  Permissions.consultationsView: 'View consultation records.',
  Permissions.consultationsCreate: 'Create new consultations.',
  Permissions.consultationsEdit: 'Edit saved consultations.',
  Permissions.vaccinationsView: 'View vaccination schedules and history.',
  Permissions.vaccinationsAdd: 'Record vaccinations.',
  Permissions.laboratoryView: 'View laboratory records.',
  Permissions.laboratoryAdd: 'Add laboratory results.',
  Permissions.inventoryView: 'View permitted inventory items.',
  Permissions.inventoryEdit: 'Edit inventory item details.',
  Permissions.inventoryCreate: 'Create inventory items.',
  Permissions.inventoryAdjust: 'Receive and adjust stock.',
  Permissions.inventorySell: 'Sell inventory through billing.',
  Permissions.inventoryCostView: 'View inventory cost prices.',
  Permissions.inventoryAccessManage: 'Configure inventory category access.',
  Permissions.billingView: 'View invoices and payments.',
  Permissions.billingCreate: 'Create invoices and record payments.',
  Permissions.billingHistory: 'Review clinic billing and payment history.',
  Permissions.billingRecordPayment: 'Record full or partial invoice payments.',
  Permissions.billingRefund: 'Issue audited invoice refunds.',
  Permissions.billingVoid: 'Void processed invoices with a reason.',
  Permissions.billingPrint: 'Print invoices and receipts.',
  Permissions.billingExport: 'Export billing history.',
  Permissions.surgeryView: 'View clinic surgical cases.',
  Permissions.surgeryCreate: 'Schedule surgical cases.',
  Permissions.surgeryEdit: 'Edit active surgical cases.',
  Permissions.surgeryCancel: 'Cancel surgery with a reason.',
  Permissions.surgeryComplete: 'Complete surgical cases.',
  Permissions.surgeryManagePreop: 'Manage pre-operative assessments.',
  Permissions.surgeryManageIntraop: 'Manage intraoperative records.',
  Permissions.surgeryManageRecovery: 'Manage recovery and discharge.',
  Permissions.surgeryPrint: 'Print surgical documents.',
  Permissions.prescriptionsView: 'View patient prescriptions.',
  Permissions.prescriptionsCreate: 'Create prescriptions.',
  Permissions.prescriptionsEdit: 'Edit draft prescriptions.',
  Permissions.prescriptionsActivate: 'Activate prescriptions.',
  Permissions.prescriptionsCancel: 'Cancel prescriptions with a reason.',
  Permissions.prescriptionsDispense: 'Dispense prescribed medication.',
  Permissions.prescriptionsPrint: 'Print prescriptions.',
  Permissions.imagingView: 'View diagnostic imaging requests.',
  Permissions.imagingRequest: 'Create imaging requests.',
  Permissions.imagingSchedule: 'Schedule imaging studies.',
  Permissions.imagingUpload: 'Upload imaging files.',
  Permissions.imagingReport: 'Record imaging findings and reports.',
  Permissions.imagingComplete: 'Complete imaging studies.',
  Permissions.imagingCancel: 'Cancel imaging requests.',
  Permissions.documentsView: 'View clinical documents.',
  Permissions.documentsUpload: 'Upload clinical documents.',
  Permissions.documentsEdit: 'Edit clinical document metadata.',
  Permissions.documentsDownload: 'Download clinical documents.',
  Permissions.documentsShare: 'Share permitted clinical documents.',
  Permissions.documentsArchive: 'Archive and restore clinical documents.',
  Permissions.documentsDelete: 'Soft-delete clinical documents.',
  Permissions.documentsViewSensitive: 'View sensitive clinical documents.',
  Permissions.treatmentBoardView: 'View treatment tasks.',
  Permissions.treatmentBoardCreate: 'Create treatment tasks.',
  Permissions.treatmentBoardAdminister: 'Record treatment administration.',
  Permissions.treatmentBoardDelay: 'Delay treatment tasks with a reason.',
  Permissions.treatmentBoardWithhold: 'Withhold treatments with a reason.',
  Permissions.treatmentBoardCancel: 'Cancel treatment tasks with a reason.',
  Permissions.treatmentBoardReopen: 'Reopen completed treatment tasks.',
  Permissions.treatmentBoardVerifyHighRisk:
      'Verify high-risk treatment administration.',
  Permissions.reportsExport: 'Access and export clinic reports.',
  Permissions.appointmentsView: 'View clinic schedule.',
  Permissions.appointmentsCreate: 'Create schedule entries.',
  Permissions.appointmentsEdit: 'Edit schedule entries.',
  Permissions.appointmentsCancel: 'Cancel schedule entries.',
  Permissions.appointmentsStartConsultation:
      'Start consultations from schedule.',
  Permissions.appointmentsAssignClinicalStaff:
      'Assign clinical staff to schedule entries.',
  Permissions.farmsView: 'View clinic-scoped farm records.',
  Permissions.farmsCreate: 'Create farm records for this clinic.',
  Permissions.farmsEdit: 'Edit farm profiles and operational details.',
  Permissions.farmsArchive: 'Archive farm records while preserving history.',
  Permissions.farmUnitsManage: 'Manage farm sectors, pens and units.',
  Permissions.farmDailyRecord: 'Create and edit draft daily farm records.',
  Permissions.farmDailyFinalize: 'Finalize daily farm records.',
  Permissions.farmMortalityRecord: 'Record farm mortality events.',
  Permissions.farmFeedRecord: 'Record daily feed preparation and supply.',
  Permissions.farmReproductionRecord:
      'Record breeding and reproductive events.',
  Permissions.farmHealthRecord: 'Record farm health interventions.',
  Permissions.farmReportsView: 'View farm population and daily reports.',
  Permissions.farmReportsPrint: 'Generate and print farm reports.',
  Permissions.usersView: 'View clinic staff.',
  Permissions.twoFactorManageSelf:
      'Manage two-factor authentication for your administrator account.',
  Permissions.usersCreate: 'Invite clinic staff.',
  Permissions.usersEdit: 'Edit clinic staff profiles.',
  Permissions.usersSuspend: 'Suspend and restore clinic staff.',
  Permissions.usersAssignRoles: 'Assign clinic roles.',
  Permissions.usersAssignPermissions: 'Configure role and user permissions.',
  Permissions.clinicSettingsView: 'View clinic settings.',
  Permissions.clinicSettingsEdit: 'Edit clinic settings.',
  Permissions.clinicWorkHoursManage: 'Manage clinic working hours.',
  Permissions.auditLogsView: 'Review clinic audit activity.',
};

String clinicPermissionGroup(String permission) {
  if (permission.startsWith('patients.')) return 'Patient Management';
  if (permission.startsWith('consultations.')) return 'Consultations';
  if (permission.startsWith('vaccinations.')) return 'Vaccination';
  if (permission.startsWith('laboratory.')) return 'Laboratory';
  if (permission.startsWith('inventory.')) return 'Inventory';
  if (permission.startsWith('billing.')) return 'Billing';
  if (permission.startsWith('surgery.')) return 'Surgery';
  if (permission.startsWith('prescriptions.')) return 'Prescriptions';
  if (permission.startsWith('imaging.')) return 'Imaging';
  if (permission.startsWith('documents.')) return 'Medical Documents';
  if (permission.startsWith('treatment_board.')) return 'Treatment Board';
  if (permission.startsWith('appointments.')) return 'Appointments';
  if (permission.startsWith('farms.')) return 'Farm Records';
  if (permission.startsWith('users.')) return 'User Management';
  if (permission.startsWith('clinic') ||
      permission.startsWith('patients.numbering')) {
    return 'Clinic Administration';
  }
  if (permission.startsWith('audit')) return 'Security';
  if (permission.startsWith('reports.')) return 'Reports';
  return 'Other';
}
