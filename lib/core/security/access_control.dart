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

class Permissions {
  const Permissions._();

  static const patientsView = 'patients.view';
  static const patientsCreate = 'patients.create';
  static const patientsEdit = 'patients.edit';
  static const consultationsView = 'consultations.view';
  static const consultationsCreate = 'consultations.create';
  static const consultationsEdit = 'consultations.edit';
  static const vaccinationsView = 'vaccinations.view';
  static const vaccinationsAdd = 'vaccinations.add';
  static const laboratoryView = 'laboratory.view';
  static const laboratoryAdd = 'laboratory.add';
  static const inventoryView = 'inventory.view';
  static const inventoryEdit = 'inventory.edit';
  static const billingView = 'billing.view';
  static const billingCreate = 'billing.create';
  static const reportsExport = 'reports.export';
  static const appointmentsView = 'appointments.view';
  static const appointmentsCreate = 'appointments.create';
  static const usersView = 'users.view';
  static const usersCreate = 'users.create';
  static const usersEdit = 'users.edit';
  static const usersSuspend = 'users.suspend';
  static const usersAssignRoles = 'users.assign_roles';
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
}

const allPermissions = <String>{
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
  Permissions.billingView,
  Permissions.billingCreate,
  Permissions.reportsExport,
  Permissions.appointmentsView,
  Permissions.appointmentsCreate,
  Permissions.usersView,
  Permissions.usersCreate,
  Permissions.usersEdit,
  Permissions.usersSuspend,
  Permissions.usersAssignRoles,
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
};

const rolePermissions = <String, Set<String>>{
  'Receptionist': {
    Permissions.patientsView,
    Permissions.patientsCreate,
    Permissions.appointmentsView,
    Permissions.appointmentsCreate,
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
    Permissions.appointmentsView,
  },
  'Laboratory Staff': {Permissions.laboratoryView, Permissions.laboratoryAdd},
  'Cashier': {Permissions.billingView, Permissions.billingCreate},
  'Inventory Officer': {Permissions.inventoryView, Permissions.inventoryEdit},
  'Clinic Administrator': {
    Permissions.patientsView,
    Permissions.patientsCreate,
    Permissions.patientsEdit,
    Permissions.consultationsView,
    Permissions.consultationsCreate,
    Permissions.consultationsEdit,
    Permissions.usersView,
    Permissions.usersCreate,
    Permissions.usersEdit,
    Permissions.usersSuspend,
    Permissions.usersAssignRoles,
    Permissions.usersAssignPermissions,
    Permissions.clinicSettingsView,
    Permissions.clinicSettingsEdit,
    Permissions.clinicWorkHoursManage,
    Permissions.auditLogsView,
    Permissions.reportsExport,
    Permissions.appointmentsView,
    Permissions.appointmentsCreate,
    Permissions.vaccinationsView,
    Permissions.vaccinationsAdd,
    Permissions.laboratoryView,
    Permissions.laboratoryAdd,
    Permissions.inventoryView,
    Permissions.inventoryEdit,
    Permissions.billingView,
    Permissions.billingCreate,
  },
  'Platform Owner': allPermissions,
};
