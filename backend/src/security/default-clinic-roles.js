const billing = [
  'billing.view',
  'billing.create',
  'billing.history',
  'billing.record_payment',
  'billing.refund',
  'billing.void',
  'billing.print',
  'billing.export',
];

const surgery = [
  'surgery.view',
  'surgery.create',
  'surgery.edit',
  'surgery.cancel',
  'surgery.complete',
  'surgery.manage_preop',
  'surgery.manage_intraop',
  'surgery.manage_recovery',
  'surgery.print',
];

const prescriptions = [
  'prescriptions.view',
  'prescriptions.create',
  'prescriptions.edit',
  'prescriptions.activate',
  'prescriptions.cancel',
  'prescriptions.dispense',
  'prescriptions.print',
];

const imaging = [
  'imaging.view',
  'imaging.request',
  'imaging.schedule',
  'imaging.upload',
  'imaging.report',
  'imaging.complete',
  'imaging.cancel',
];

const documents = [
  'documents.view',
  'documents.upload',
  'documents.edit',
  'documents.download',
  'documents.share',
  'documents.archive',
  'documents.delete',
  'documents.view_sensitive',
];

const treatmentBoard = [
  'treatment_board.view',
  'treatment_board.create',
  'treatment_board.administer',
  'treatment_board.delay',
  'treatment_board.withhold',
  'treatment_board.cancel',
  'treatment_board.reopen',
  'treatment_board.verify_high_risk',
];

export const defaultClinicRoleTemplates = Object.freeze([
  role('veterinarian', 'Veterinarian', 'Clinical care, consultations and patient management.', [
    'patients.view', 'patients.create', 'patients.edit',
    'consultations.view', 'consultations.create', 'consultations.edit',
    'vaccinations.view', 'vaccinations.add',
    'laboratory.view', 'laboratory.add',
    ...surgery, ...prescriptions, ...imaging, ...documents, ...treatmentBoard,
    'billing.view', 'billing.history', 'billing.print',
    'appointments.view', 'appointments.create', 'appointments.edit',
    'appointments.start_consultation',
    'farms.view', 'farms.daily.record', 'farms.mortality.record',
    'farms.reproduction.record', 'farms.health.record', 'farms.reports.view',
  ]),
  role('veterinary_nurse', 'Veterinary Nurse', 'Clinical support, patient care and vaccination support.', [
    'patients.view', 'patients.edit', 'consultations.view',
    'vaccinations.view', 'vaccinations.add', 'laboratory.view',
    'surgery.view', 'surgery.manage_preop', 'surgery.manage_recovery',
    'prescriptions.view', 'imaging.view', 'imaging.upload',
    'documents.view', 'documents.upload',
    'treatment_board.view', 'treatment_board.create',
    'treatment_board.administer', 'treatment_board.delay',
    'treatment_board.withhold', 'appointments.view',
    'farms.view', 'farms.daily.record', 'farms.health.record',
  ]),
  role('receptionist', 'Receptionist', 'Patient registration and schedule coordination.', [
    'patients.view', 'patients.create',
    'appointments.view', 'appointments.create', 'appointments.edit',
  ]),
  role('laboratory_staff', 'Laboratory Staff', 'Laboratory workflows and result entry.', [
    'laboratory.view', 'laboratory.add',
  ]),
  role('pharmacist', 'Pharmacist', 'Pharmacy inventory and dispensing support.', [
    'inventory.view', 'inventory.sell',
    'prescriptions.view', 'prescriptions.dispense', 'prescriptions.print',
    'billing.view', 'billing.history',
  ]),
  role('cashier', 'Cashier', 'Billing and payment collection.', [
    'billing.view', 'billing.create', 'billing.history',
    'billing.record_payment', 'billing.print',
  ]),
  role('practice_manager', 'Practice Manager', 'Daily clinic operations without ownership controls.', [
    'patients.view', 'patients.create', 'patients.edit',
    'consultations.view', 'consultations.create', 'consultations.edit',
    'vaccinations.view', 'vaccinations.add',
    'laboratory.view', 'laboratory.add',
    'inventory.view', 'inventory.edit', 'inventory.create',
    'inventory.adjust', 'inventory.sell',
    ...billing, ...surgery, ...prescriptions, ...imaging, ...documents,
    ...treatmentBoard, 'reports.export',
    'appointments.view', 'appointments.create', 'appointments.edit',
    'appointments.cancel', 'appointments.start_consultation',
    'appointments.assign_clinical_staff',
    'farms.view', 'farms.create', 'farms.edit', 'farms.units.manage',
    'farms.daily.record', 'farms.daily.finalize', 'farms.mortality.record',
    'farms.feed.record', 'farms.reproduction.record', 'farms.health.record',
    'farms.reports.view', 'farms.reports.print',
  ]),
  role('inventory_officer', 'Inventory Officer', 'Inventory, stock and supplier workflows.', [
    'inventory.view', 'inventory.edit', 'inventory.create',
    'inventory.adjust', 'inventory.sell', 'inventory.cost.view',
  ]),
  role('sales_representative', 'Sales Representative', 'Point-of-sale inventory and billing access.', [
    'inventory.view', 'inventory.sell', 'billing.view', 'billing.create',
    'billing.history', 'billing.record_payment', 'billing.print',
  ]),
]);

export async function ensureDefaultClinicRoles(client, { clinicId, actorUserId }) {
  for (const template of defaultClinicRoleTemplates) {
    let existing = (
      await client.query(
        `SELECT role_id
           FROM roles
          WHERE clinic_id = $1
            AND (code = $2 OR lower(name) = lower($3))
            AND deleted_at IS NULL
          ORDER BY CASE WHEN code = $2 THEN 0 ELSE 1 END
          LIMIT 1
          FOR UPDATE`,
        [clinicId, template.code, template.name],
      )
    ).rows[0];
    if (!existing) {
      existing = (
        await client.query(
          `INSERT INTO roles
             (clinic_id, code, name, description, is_system_role, created_by, updated_by)
           VALUES ($1, $2, $3, $4, true, $5, $5)
           ON CONFLICT (clinic_id, name) DO UPDATE SET deleted_at = NULL
           RETURNING role_id`,
          [
            clinicId,
            template.code,
            template.name,
            template.description,
            actorUserId,
          ],
        )
      ).rows[0];
    }
    const permissionRows = await client.query(
      `SELECT permission_id, permission_key
         FROM permissions
        WHERE permission_key = ANY($1::text[])`,
      [template.permissions],
    );
    const found = new Set(permissionRows.rows.map((row) => row.permission_key));
    const missing = template.permissions.filter((key) => !found.has(key));
    if (missing.length > 0) {
      throw new Error(
        `Cannot provision ${template.code}; missing permissions: ${missing.join(', ')}`,
      );
    }
    await client.query(
      `INSERT INTO role_permissions (role_id, permission_id)
       SELECT $1, unnest($2::uuid[])
       ON CONFLICT DO NOTHING`,
      [existing.role_id, permissionRows.rows.map((row) => row.permission_id)],
    );
  }
}

function role(code, name, description, permissions) {
  return Object.freeze({
    code,
    name,
    description,
    permissions: Object.freeze([...new Set(permissions)]),
  });
}
