-- Production permission catalogue. Development seeders must never be required
-- for an approved clinic administrator to receive operational access.
WITH catalog(permission_key) AS (
  SELECT unnest(ARRAY[
    'dashboard.view',
    'patients.view', 'patients.create', 'patients.edit', 'patients.numbering.manage',
    'consultations.view', 'consultations.create', 'consultations.edit',
    'vaccinations.view', 'vaccinations.add',
    'laboratory.view', 'laboratory.add',
    'hospitalization.view', 'hospitalization.add',
    'surgery.view', 'surgery.add', 'surgery.create', 'surgery.edit',
    'surgery.cancel', 'surgery.complete', 'surgery.manage_preop',
    'surgery.manage_intraop', 'surgery.manage_recovery', 'surgery.print',
    'prescriptions.view', 'prescriptions.create', 'prescriptions.edit',
    'prescriptions.activate', 'prescriptions.cancel',
    'prescriptions.dispense', 'prescriptions.print',
    'inventory.view', 'inventory.manage', 'inventory.edit', 'inventory.create',
    'inventory.adjust', 'inventory.sell', 'inventory.cost.view',
    'inventory.access.manage',
    'appointments.view', 'appointments.create', 'appointments.edit',
    'appointments.cancel', 'appointments.start_consultation',
    'appointments.assign_clinical_staff',
    'billing.view', 'billing.manage', 'billing.create', 'billing.history',
    'billing.record_payment', 'billing.refund', 'billing.void',
    'billing.print', 'billing.export',
    'media.view',
    'imaging.view', 'imaging.request', 'imaging.schedule', 'imaging.upload',
    'imaging.report', 'imaging.complete', 'imaging.cancel',
    'documents.view', 'documents.upload', 'documents.edit',
    'documents.download', 'documents.share', 'documents.archive',
    'documents.delete', 'documents.view_sensitive',
    'treatment_board.view', 'treatment_board.create',
    'treatment_board.administer', 'treatment_board.delay',
    'treatment_board.withhold', 'treatment_board.cancel',
    'treatment_board.reopen', 'treatment_board.verify_high_risk',
    'farms.view', 'farms.create', 'farms.edit', 'farms.archive',
    'farms.units.manage', 'farms.daily.record', 'farms.daily.finalize',
    'farms.mortality.record', 'farms.feed.record',
    'farms.reproduction.record', 'farms.health.record',
    'farms.reports.view', 'farms.reports.print',
    'users.view', 'users.create', 'users.edit', 'users.suspend',
    'users.assign_roles', 'users.assign_permissions',
    'clinic_settings.view', 'clinic_settings.edit',
    'clinic.work_hours.manage', 'audit_logs.view', 'reports.export',
    'clinics.view', 'subscriptions.manage', 'security.twoFactor.manageSelf'
  ]::text[])
)
INSERT INTO permissions (permission_key, description)
SELECT permission_key,
       initcap(replace(replace(permission_key, '.', ' '), '_', ' '))
FROM catalog
ON CONFLICT (permission_key) DO UPDATE
SET description = EXCLUDED.description;

-- Backfill every tenant's protected administrator role. Platform-only keys are
-- intentionally absent from this list.
WITH clinic_permissions(permission_key) AS (
  SELECT unnest(ARRAY[
    'dashboard.view',
    'patients.view', 'patients.create', 'patients.edit', 'patients.numbering.manage',
    'consultations.view', 'consultations.create', 'consultations.edit',
    'vaccinations.view', 'vaccinations.add',
    'laboratory.view', 'laboratory.add',
    'hospitalization.view', 'hospitalization.add',
    'surgery.view', 'surgery.add', 'surgery.create', 'surgery.edit',
    'surgery.cancel', 'surgery.complete', 'surgery.manage_preop',
    'surgery.manage_intraop', 'surgery.manage_recovery', 'surgery.print',
    'prescriptions.view', 'prescriptions.create', 'prescriptions.edit',
    'prescriptions.activate', 'prescriptions.cancel',
    'prescriptions.dispense', 'prescriptions.print',
    'inventory.view', 'inventory.manage', 'inventory.edit', 'inventory.create',
    'inventory.adjust', 'inventory.sell', 'inventory.cost.view',
    'inventory.access.manage',
    'appointments.view', 'appointments.create', 'appointments.edit',
    'appointments.cancel', 'appointments.start_consultation',
    'appointments.assign_clinical_staff',
    'billing.view', 'billing.manage', 'billing.create', 'billing.history',
    'billing.record_payment', 'billing.refund', 'billing.void',
    'billing.print', 'billing.export', 'media.view',
    'imaging.view', 'imaging.request', 'imaging.schedule', 'imaging.upload',
    'imaging.report', 'imaging.complete', 'imaging.cancel',
    'documents.view', 'documents.upload', 'documents.edit',
    'documents.download', 'documents.share', 'documents.archive',
    'documents.delete', 'documents.view_sensitive',
    'treatment_board.view', 'treatment_board.create',
    'treatment_board.administer', 'treatment_board.delay',
    'treatment_board.withhold', 'treatment_board.cancel',
    'treatment_board.reopen', 'treatment_board.verify_high_risk',
    'farms.view', 'farms.create', 'farms.edit', 'farms.archive',
    'farms.units.manage', 'farms.daily.record', 'farms.daily.finalize',
    'farms.mortality.record', 'farms.feed.record',
    'farms.reproduction.record', 'farms.health.record',
    'farms.reports.view', 'farms.reports.print',
    'users.view', 'users.create', 'users.edit', 'users.suspend',
    'users.assign_roles', 'users.assign_permissions',
    'clinic_settings.view', 'clinic_settings.edit',
    'clinic.work_hours.manage', 'audit_logs.view', 'reports.export',
    'clinics.view', 'subscriptions.manage', 'security.twoFactor.manageSelf'
  ]::text[])
)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r
JOIN clinic_permissions cp ON true
JOIN permissions p ON p.permission_key = cp.permission_key
WHERE r.clinic_id IS NOT NULL
  AND r.name = 'Clinic Administrator'
  AND r.deleted_at IS NULL
ON CONFLICT DO NOTHING;
