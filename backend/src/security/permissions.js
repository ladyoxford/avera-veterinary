export const permissions = {
  clinicsView: 'clinics.view', clinicsApprove: 'clinics.approve', clinicsSuspend: 'clinics.suspend',
  usersView: 'users.view', usersCreate: 'users.create', usersAssignRoles: 'users.assign_roles', staffRolesManage: 'staff.roles.manage',
  auditLogsView: 'audit_logs.view', subscriptionsManage: 'subscriptions.manage',
  dashboardView: 'dashboard.view',
  patientsView: 'patients.view', patientsCreate: 'patients.create', patientsEdit: 'patients.edit',
  consultationsView: 'consultations.view', consultationsCreate: 'consultations.create', consultationsEdit: 'consultations.edit',
  vaccinationsView: 'vaccinations.view', vaccinationsAdd: 'vaccinations.add',
  laboratoryView: 'laboratory.view', laboratoryAdd: 'laboratory.add',
  hospitalizationView: 'hospitalization.view', hospitalizationAdd: 'hospitalization.add',
  surgeryView: 'surgery.view', surgeryAdd: 'surgery.add', surgeryCreate: 'surgery.create',
  prescriptionsView: 'prescriptions.view', prescriptionsCreate: 'prescriptions.create',
  imagingView: 'imaging.view', imagingRequest: 'imaging.request',
  documentsView: 'documents.view', documentsUpload: 'documents.upload',
  treatmentBoardView: 'treatment_board.view', treatmentBoardCreate: 'treatment_board.create',
  inventoryView: 'inventory.view', inventoryCreate: 'inventory.create', inventoryEdit: 'inventory.edit', inventoryManage: 'inventory.manage',
  appointmentsView: 'appointments.view', appointmentsCreate: 'appointments.create',
  appointmentsEdit: 'appointments.edit', appointmentsCancel: 'appointments.cancel',
  appointmentsStartConsultation: 'appointments.start_consultation',
  billingView: 'billing.view', billingCreate: 'billing.create', billingManage: 'billing.manage',
  mediaView: 'media.view',
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
