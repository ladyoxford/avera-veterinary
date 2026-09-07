export const permissions = {
  clinicsView: 'clinics.view', clinicsApprove: 'clinics.approve', clinicsSuspend: 'clinics.suspend',
  usersView: 'users.view', usersCreate: 'users.create', usersAssignRoles: 'users.assign_roles', staffRolesManage: 'staff.roles.manage',
  auditLogsView: 'audit_logs.view', subscriptionsManage: 'subscriptions.manage',
  dashboardView: 'dashboard.view',
  patientsView: 'patients.view', patientsCreate: 'patients.create', patientsEdit: 'patients.edit',
  patientsNumberingManage: 'patients.numbering.manage',
  consultationsView: 'consultations.view', consultationsCreate: 'consultations.create', consultationsEdit: 'consultations.edit',
  vaccinationsView: 'vaccinations.view', vaccinationsAdd: 'vaccinations.add',
  laboratoryView: 'laboratory.view', laboratoryAdd: 'laboratory.add',
  hospitalizationView: 'hospitalization.view', hospitalizationAdd: 'hospitalization.add',
  surgeryView: 'surgery.view', surgeryAdd: 'surgery.add', surgeryCreate: 'surgery.create',
  surgeryEdit: 'surgery.edit', surgeryCancel: 'surgery.cancel', surgeryComplete: 'surgery.complete',
  surgeryManagePreop: 'surgery.manage_preop', surgeryManageIntraop: 'surgery.manage_intraop',
  surgeryManageRecovery: 'surgery.manage_recovery',
  prescriptionsView: 'prescriptions.view', prescriptionsCreate: 'prescriptions.create',
  prescriptionsEdit: 'prescriptions.edit', prescriptionsActivate: 'prescriptions.activate',
  prescriptionsCancel: 'prescriptions.cancel', prescriptionsDispense: 'prescriptions.dispense',
  imagingView: 'imaging.view', imagingRequest: 'imaging.request', imagingSchedule: 'imaging.schedule',
  imagingUpload: 'imaging.upload', imagingReport: 'imaging.report',
  imagingComplete: 'imaging.complete', imagingCancel: 'imaging.cancel',
  documentsView: 'documents.view', documentsUpload: 'documents.upload',
  documentsEdit: 'documents.edit', documentsArchive: 'documents.archive',
  treatmentBoardView: 'treatment_board.view', treatmentBoardCreate: 'treatment_board.create',
  treatmentBoardAdminister: 'treatment_board.administer', treatmentBoardDelay: 'treatment_board.delay',
  treatmentBoardWithhold: 'treatment_board.withhold', treatmentBoardCancel: 'treatment_board.cancel',
  treatmentBoardReopen: 'treatment_board.reopen',
  inventoryView: 'inventory.view', inventoryCreate: 'inventory.create', inventoryEdit: 'inventory.edit', inventoryAdjust: 'inventory.adjust',
  inventorySell: 'inventory.sell',
  appointmentsView: 'appointments.view', appointmentsCreate: 'appointments.create',
  appointmentsEdit: 'appointments.edit', appointmentsCancel: 'appointments.cancel',
  appointmentsStartConsultation: 'appointments.start_consultation',
  billingView: 'billing.view', billingCreate: 'billing.create', billingManage: 'billing.manage',
  billingHistory: 'billing.history',
  billingRecordPayment: 'billing.record_payment',
  billingVoid: 'billing.void',
  mediaView: 'media.view',
  clinicSettingsView: 'clinic_settings.view', clinicSettingsEdit: 'clinic_settings.edit',
  clinicWorkHoursManage: 'clinic.work_hours.manage',
  farmsView: 'farms.view', farmUnitsManage: 'farms.units.manage',
  farmDailyRecord: 'farms.daily.record', farmMortalityRecord: 'farms.mortality.record',
  farmHealthRecord: 'farms.health.record',
  twoFactorManageSelf: 'security.twoFactor.manageSelf',
};

export async function effectivePermissions(client, user) {
  if (user.account_type === 'PlatformOwner') return ['*'];
  const result = await client.query(
    `SELECT DISTINCT permission_key
       FROM role_permissions rp
       JOIN permissions p ON p.permission_id = rp.permission_id
      WHERE rp.role_id = $1
      UNION
     SELECT DISTINCT p.permission_key
       FROM user_permission_overrides upo
       JOIN permissions p ON p.permission_id = upo.permission_id
      WHERE upo.user_id = $2 AND upo.effect = 'grant'`,
    [user.role_id, user.user_id],
  );
  const restricted = await client.query(
    `SELECT p.permission_key FROM user_permission_overrides upo
       JOIN permissions p ON p.permission_id = upo.permission_id
      WHERE upo.user_id = $1 AND upo.effect = 'restrict'`, [user.user_id]);
  const blocked = new Set(restricted.rows.map((row) => row.permission_key));
  return result.rows.map((row) => row.permission_key).filter((permission) => !blocked.has(permission));
}

export function hasPermission(request, permission) {
  return request.auth.permissions.includes('*') || request.auth.permissions.includes(permission);
}
