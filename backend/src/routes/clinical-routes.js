import { z } from 'zod';
import { withTenantTransaction } from '../database/pool.js';
import { authenticate, requirePermission } from '../middleware/auth.js';
import { hasPermission, permissions } from '../security/permissions.js';
import { writeAudit } from '../audit/audit-service.js';
import {
  loadRevenueDrilldown,
  loadRevenueSummary,
  revenueDrilldownMetrics,
} from '../services/revenue-report-service.js';

const pageSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
  search: z.string().trim().max(160).optional(),
  sort: z.string().trim().max(80).optional(),
  direction: z.enum(['asc', 'desc']).default('desc'),
  status: z.string().trim().max(80).optional(),
  module: z.string().trim().max(80).optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
});

const revenuePeriodSchema = z.enum([
  '1d', '3d', '7d', '1w', '1m', '3m', '6m', '1y', '3y', '10y',
  'all_time',
]);

function validateRevenueRange(value, context) {
  if (value.period !== 'all_time' && (!value.from || !value.to)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'A bounded revenue period requires from and to timestamps.',
    });
  }
  if (value.from && value.to && new Date(value.from) >= new Date(value.to)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'The revenue period start must precede its end.',
    });
  }
}

const revenueSummaryQuerySchema = z.object({
  period: revenuePeriodSchema.default('all_time'),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
}).strict().superRefine(validateRevenueRange);

const revenueDrilldownQuerySchema = z.object({
  period: revenuePeriodSchema,
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  metric: z.enum(revenueDrilldownMetrics),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
}).strict().superRefine(validateRevenueRange);

const clinicActivityUnionSql = `
  SELECT 'Consultation' AS type, 'Consultations' AS module,
         'Consultation' AS related_entity_type,
         consultation_id AS record_id, patient_id, occurred_at,
         coalesce(final_diagnosis, chief_complaint, 'Consultation') AS title,
         'Consultation' AS summary
    FROM consultations
   WHERE clinic_id=$1 AND deleted_at IS NULL
  UNION ALL
  SELECT 'Schedule', 'Schedule', 'Schedule', schedule_entry_id, patient_id,
         coalesce(updated_at, created_at), visit_type, status
    FROM schedule_entries
   WHERE clinic_id=$1
  UNION ALL
  SELECT 'ClinicalOperation', operation_type, 'ClinicalOperation', operation_id,
         patient_id, coalesce(updated_at, created_at), title,
         operation_type || ' - ' || status
    FROM clinical_operation_records
   WHERE clinic_id=$1
  UNION ALL
  SELECT 'Vaccination', 'Vaccinations', 'Vaccination', vaccination_id,
         patient_id, administered_at, vaccine_name, status
    FROM vaccinations
   WHERE clinic_id=$1
  UNION ALL
  SELECT 'Patient', 'Patients', 'Patient', patient_id, patient_id,
         registered_at, name || ' registered', hospital_number
    FROM patients
   WHERE clinic_id=$1 AND deleted_at IS NULL
  UNION ALL
  SELECT 'Invoice', 'Billing', 'Invoice', invoice_id, patient_id,
         issued_at, invoice_number, status
    FROM invoices
   WHERE clinic_id=$1`;

const uuidSchema = z.object({ patientId: z.string().uuid() });
const consultationUuidSchema = z.object({ consultationId: z.string().uuid() });
const vaccinationUuidSchema = z.object({ vaccinationId: z.string().uuid() });
const appointmentUuidSchema = z.object({ appointmentId: z.string().uuid() });
const inventoryUuidSchema = z.object({ inventoryProductId: z.string().uuid() });
const clinicalOperationUuidSchema = z.object({ operationId: z.string().uuid() });
const farmUuidSchema = z.object({ farmId: z.string().uuid() });

function normalizedBillingPhone(value) {
  const digits = String(value ?? '').replace(/[^0-9]/g, '');
  return digits.length > 10 ? digits.slice(-10) : digits;
}

export function patientsShareBillingOwner(rows) {
  if (rows.length < 2) return rows.length === 1;
  const ownerIds = new Set(rows.map((row) => row.owner_id));
  if (ownerIds.size === 1) return true;
  const phones = rows.map((row) => normalizedBillingPhone(row.owner_phone));
  if (phones[0]?.length >= 7 && phones.every((value) => value === phones[0])) {
    return true;
  }
  const emails = rows.map((row) => String(row.owner_email ?? '').trim().toLowerCase());
  return emails[0]?.length > 0 && emails.every((value) => value === emails[0]);
}

const patientPhotoSchema = z.object({
  contentType: z.enum(['image/jpeg', 'image/png']),
  data: z.string().min(1),
});
export const createPatientSchema = z.object({
  submissionId: z.string().uuid(),
  name: z.string().trim().min(1).max(160),
  species: z.string().trim().min(1).max(120),
  speciesId: z.string().trim().max(120).nullish(),
  breed: z.string().trim().min(1).max(160),
  breedId: z.string().trim().max(160).nullish(),
  sex: z.string().trim().min(1).max(40),
  dateOfBirth: z.string().date(),
  isDateOfBirthEstimated: z.boolean().default(false),
  originalAgeValue: z.number().int().min(0).max(5000).nullish(),
  originalAgeUnit: z.enum(['days', 'weeks', 'months', 'years']).nullish(),
  weightKg: z.number().min(0).max(100000).nullish(),
  colour: z.string().trim().max(160).nullish(),
  microchipNumber: z.string().trim().max(160).nullish(),
  notes: z.string().trim().max(4000).nullish(),
  owner: z.object({
    fullName: z.string().trim().min(1).max(160),
    phone: z.string().trim().min(1).max(80),
    email: z.string().trim().email().max(254).nullish(),
    address: z.string().trim().max(500).nullish(),
  }),
});

export const patientStatusSchema = z.object({
  status: z.enum(['Active', 'Deceased', 'Relocated']),
  reason: z.string().trim().max(500).nullish(),
});

export const createConsultationSchema = z.object({
  submissionId: z.string().uuid(),
  patientId: z.string().uuid(),
  chiefComplaint: z.string().trim().min(1).max(4000),
  history: z.string().trim().max(8000).nullish(),
  examination: z.string().trim().max(8000).nullish(),
  diagnosis: z.string().trim().max(4000).nullish(),
  treatment: z.string().trim().max(8000).nullish(),
  prescription: z.string().trim().max(8000).nullish(),
  veterinarian: z.string().trim().max(200).nullish(),
});

export const updateConsultationSchema = z.object({
  revision: z.number().int().min(1),
  chiefComplaint: z.string().trim().min(1).max(4000),
  history: z.string().trim().max(8000).nullish(),
  examination: z.string().trim().max(8000).nullish(),
  diagnosis: z.string().trim().max(4000).nullish(),
  treatment: z.string().trim().max(8000).nullish(),
  prescription: z.string().trim().max(8000).nullish(),
}).strict();

export const createVaccinationSchema = z.object({
  submissionId: z.string().uuid(),
  patientId: z.string().uuid(),
  vaccineName: z.string().trim().min(1).max(240),
  administeredAt: z.string().datetime(),
  nextDueAt: z.string().datetime().nullish(),
  route: z.string().trim().max(120).nullish(),
  batchNumber: z.string().trim().max(160).nullish(),
  manufacturer: z.string().trim().max(200).nullish(),
  dose: z.string().trim().max(160).nullish(),
  notes: z.string().trim().max(4000).nullish(),
});

export const createAppointmentSchema = z.object({
  submissionId: z.string().uuid(),
  patientId: z.string().uuid(),
  scheduledAt: z.string().datetime(),
  visitType: z.string().trim().min(1).max(200),
  assignedStaffId: z.string().uuid().nullish(),
  notes: z.string().trim().max(4000).nullish(),
});

export const updateAppointmentSchema = z.object({
  revision: z.number().int().min(1),
  scheduledAt: z.string().datetime(),
  visitType: z.string().trim().min(1).max(200),
  assignedStaffId: z.string().uuid().nullish(),
  notes: z.string().trim().max(4000).nullish(),
}).strict();

export const cancelAppointmentSchema = z.object({
  revision: z.number().int().min(1),
}).strict();

const farmUnitPopulationSchema = z.object({
  farmUnitPopulationId: z.string().uuid(),
  speciesId: z.string().trim().min(1).max(120),
  breedId: z.string().trim().max(160).nullish(),
  maleCount: z.number().int().min(0).max(1000000000).default(0),
  femaleCount: z.number().int().min(0).max(1000000000).default(0),
  unknownCount: z.number().int().min(0).max(1000000000).default(0),
}).strict();

const farmUnitSchema = z.object({
  farmUnitId: z.string().uuid(),
  name: z.string().trim().min(1).max(240),
  unitType: z.string().trim().max(120).nullish(),
  species: z.string().trim().max(120).nullish(),
  breed: z.string().trim().max(160).nullish(),
  populations: z.array(farmUnitPopulationSchema).max(200).default([]),
}).strict();

const farmTreatmentSchema = z.object({
  treatmentRecordId: z.string().uuid(),
  farmUnitId: z.string().uuid().nullable().optional(),
  treatmentType: z.string().trim().min(1).max(200),
  productName: z.string().trim().max(240).nullish(),
  occurredAt: z.string().datetime(),
  animalsCovered: z.number().int().positive().nullable().optional(),
  billableAmount: z.number().min(0).max(1000000000000),
  costSnapshot: z.number().min(0).max(1000000000000).nullable().optional(),
  notes: z.string().trim().max(4000).nullish(),
  targetScope: z.enum(['EntireUnit', 'SelectedGroups']).default('EntireUnit'),
  targetPopulationIds: z.array(z.string().uuid()).max(200).default([]),
}).strict().superRefine((value, ctx) => {
  if (value.targetScope === 'SelectedGroups' && value.targetPopulationIds.length === 0) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['targetPopulationIds'],
      message: 'Select at least one population group.',
    });
  }
  if (value.targetScope === 'EntireUnit' && value.targetPopulationIds.length > 0) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['targetPopulationIds'],
      message: 'Entire-unit treatments cannot contain selected population groups.',
    });
  }
});

export const farmContextSchema = z.object({
  farmId: z.string().uuid(),
  name: z.string().trim().min(1).max(240),
  clientName: z.string().trim().max(240).nullish(),
  clientPhone: z.string().trim().max(80).nullish(),
  units: z.array(farmUnitSchema).max(100).default([]),
  treatments: z.array(farmTreatmentSchema).max(200).default([]),
}).strict();

export const createInvoiceSchema = z.object({
  submissionId: z.string().uuid(),
  contextType: z.enum(['patient', 'farm_visit']).default('patient'),
  patientId: z.string().uuid().nullable().optional(),
  patientIds: z.array(z.string().uuid()).max(100).default([]),
  status: z.enum(['Draft', 'Unpaid', 'Paid']),
  subtotal: z.number().min(0).max(1000000000000),
  total: z.number().min(0).max(1000000000000),
  services: z.array(z.object({
    description: z.string().trim().min(1).max(500),
    amount: z.number().min(0).max(1000000000000),
    patientId: z.string().uuid().nullable().optional(),
    quantity: z.number().positive().max(1000000).default(1),
    unitPrice: z.number().min(0).max(1000000000000).optional(),
    farmUnitId: z.string().uuid().nullable().optional(),
    sourceTreatmentRecordId: z.string().uuid().nullable().optional(),
    costSnapshot: z.number().min(0).max(1000000000000).nullable().optional(),
  })).max(100).default([]),
  products: z.array(z.object({
    inventoryProductId: z.string().uuid(),
    productUnitId: z.string().uuid().nullable().optional(),
    patientId: z.string().uuid().nullable().optional(),
    farmUnitId: z.string().uuid().nullable().optional(),
    quantity: z.number().int().positive().max(1000000),
  })).max(100).default([]),
  farm: farmContextSchema.extend({
    visitDate: z.string().date(),
  }).nullable().optional(),
}).superRefine((input, ctx) => {
  if (input.contextType === 'patient' && !input.patientId) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['patientId'], message: 'A patient is required.' });
  }
  if (input.contextType === 'farm_visit' && !input.farm) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['farm'], message: 'Farm context is required.' });
  }
});

export const recordInvoicePaymentSchema = z.object({
  submissionId: z.string().uuid(),
  amount: z.number().positive().max(1000000000000),
  method: z.enum(['Cash', 'Card', 'Transfer', 'POS', 'Other']),
  paidAt: z.string().datetime(),
  reference: z.string().trim().max(240).nullish(),
}).strict();

const clinicalOperationTypes = ['Surgery', 'Prescription', 'Imaging', 'Document', 'Treatment'];
export const createClinicalOperationSchema = z.object({
  submissionId: z.string().uuid(),
  patientId: z.string().uuid(),
  operationType: z.enum(clinicalOperationTypes),
  title: z.string().trim().min(1).max(500),
  description: z.string().trim().max(8000).nullish(),
  assignedTo: z.string().trim().max(240).nullish(),
  scheduledAt: z.string().datetime(),
  status: z.string().trim().min(1).max(100),
  priority: z.enum(['Routine', 'Urgent', 'Emergency']).default('Routine'),
  estimatedAmount: z.number().min(0).max(1000000000000).nullish(),
  details: z.record(z.unknown()).default({}),
  items: z.array(z.record(z.unknown())).max(100).default([]),
});

const operationPermissions = {
  Surgery: { view: permissions.surgeryView, create: permissions.surgeryCreate },
  Prescription: { view: permissions.prescriptionsView, create: permissions.prescriptionsCreate },
  Imaging: { view: permissions.imagingView, create: permissions.imagingRequest },
  Document: { view: permissions.documentsView, create: permissions.documentsUpload },
  Treatment: { view: permissions.treatmentBoardView, create: permissions.treatmentBoardCreate },
};

export const clinicalOperationTransitions = Object.freeze({
  Surgery: {
    Draft: ['Scheduled', 'Cancelled'], Pending: ['Scheduled', 'Cancelled'],
    Scheduled: ['Pre-operative', 'Cancelled'],
    'Pre-operative': ['Ready for Surgery', 'Cancelled'],
    'Ready for Surgery': ['In Progress', 'Cancelled'],
    'In Progress': ['Recovery', 'Cancelled'], Recovery: ['Completed'],
  },
  Prescription: {
    Draft: ['Active', 'Cancelled'], Pending: ['Active', 'Cancelled'],
    Active: ['Partially Dispensed', 'Dispensed', 'Expired', 'Cancelled'],
    'Partially Dispensed': ['Dispensed', 'Cancelled'],
  },
  Imaging: {
    Draft: ['Requested', 'Cancelled'], Pending: ['Requested', 'Cancelled'],
    Requested: ['Scheduled', 'In Progress', 'Cancelled'],
    Scheduled: ['In Progress', 'Cancelled'],
    'In Progress': ['Awaiting Report', 'Cancelled'],
    'Awaiting Report': ['Reported', 'Completed', 'Cancelled'],
    Reported: ['Completed'],
  },
  Document: {
    Draft: ['Available', 'Archived'], Pending: ['Available', 'Archived'],
    Available: ['Reviewed', 'Archived'], Reviewed: ['Archived'],
    Archived: ['Available'],
  },
  Treatment: {
    Pending: ['Upcoming', 'Due', 'Cancelled'], Upcoming: ['Due', 'Cancelled'],
    Due: ['Administered', 'Delayed', 'Missed', 'Withheld', 'Cancelled'],
    Overdue: ['Administered', 'Delayed', 'Missed', 'Withheld', 'Cancelled'],
    Delayed: ['Due', 'Administered', 'Missed', 'Cancelled'],
  },
});

const updateClinicalOperationStatusSchema = z.object({
  status: z.string().trim().min(1).max(100),
  reason: z.string().trim().max(2000).nullish(),
});

const notificationUuidSchema = z.object({ notificationId: z.string().uuid() });

function reminderSelectSql(request) {
  const selects = [];
  if (hasPermission(request, permissions.appointmentsView)) selects.push(`
    SELECT 'appointment:' || s.schedule_entry_id AS event_id, 'Appointment' AS event_type,
           'Schedule' AS module, 'Schedule' AS related_entity_type,
           s.schedule_entry_id AS related_entity_id, s.patient_id, p.name AS patient_name,
           s.visit_type AS title, coalesce(s.notes, s.status) AS description,
           s.scheduled_at, s.scheduled_at - interval '1 hour' AS reminder_at,
           CASE WHEN s.scheduled_at < now() THEN 'overdue'
                WHEN s.scheduled_at <= now() + interval '1 hour' THEN 'due' ELSE 'upcoming' END AS priority,
           s.status, s.assigned_staff_id
      FROM schedule_entries s JOIN patients p ON p.patient_id=s.patient_id
     WHERE s.clinic_id=$1 AND s.scheduled_at >= now() - interval '1 day'
       AND lower(s.status) NOT IN ('cancelled','completed','missed')
       `);
  if (hasPermission(request, permissions.vaccinationsView)) selects.push(`
    SELECT 'vaccination:' || v.vaccination_id, 'Vaccination', 'Vaccinations', 'Vaccination',
           v.vaccination_id, v.patient_id, p.name, v.vaccine_name,
           'Vaccination due', v.next_due_at, v.next_due_at - interval '1 day',
           CASE WHEN v.next_due_at < now() THEN 'overdue'
                WHEN v.next_due_at < now() + interval '1 day' THEN 'due' ELSE 'upcoming' END,
           v.status, NULL::uuid
      FROM vaccinations v JOIN patients p ON p.patient_id=v.patient_id
     WHERE v.clinic_id=$1 AND v.next_due_at IS NOT NULL
       AND v.next_due_at >= now() - interval '30 days'
       AND lower(v.status) NOT IN ('cancelled','archived')
       AND NOT EXISTS (
         SELECT 1 FROM vaccinations newer
          WHERE newer.clinic_id=v.clinic_id AND newer.patient_id=v.patient_id
            AND lower(newer.vaccine_name)=lower(v.vaccine_name)
            AND newer.administered_at > v.administered_at
       )`);
  for (const [type, permission] of [
    ['Surgery', permissions.surgeryView], ['Treatment', permissions.treatmentBoardView],
  ]) {
    if (!hasPermission(request, permission)) continue;
    selects.push(`
      SELECT lower(r.operation_type) || ':' || r.operation_id, r.operation_type,
             r.operation_type, 'ClinicalOperation', r.operation_id, r.patient_id,
             p.name, r.title, coalesce(r.description, r.status), r.scheduled_at,
             r.scheduled_at - interval '1 hour',
             CASE WHEN r.scheduled_at < now() THEN 'overdue'
                  WHEN r.scheduled_at < now() + interval '1 hour' THEN 'due' ELSE 'upcoming' END,
             r.status, NULL::uuid
        FROM clinical_operation_records r JOIN patients p ON p.patient_id=r.patient_id
       WHERE r.clinic_id=$1 AND r.operation_type='${type}'
         AND r.scheduled_at >= now() - interval '30 days'
         AND lower(r.status) NOT IN ('completed','cancelled','administered','missed','withheld','archived')`);
  }
  if (hasPermission(request, permissions.consultationsView)) selects.push(`
    SELECT 'follow-up:' || c.consultation_id, 'FollowUp', 'Consultations', 'Consultation',
           c.consultation_id, c.patient_id, p.name, 'Consultation follow-up',
           coalesce(c.final_diagnosis, c.chief_complaint), c.follow_up_at,
           c.follow_up_at - interval '1 day',
           CASE WHEN c.follow_up_at < now() THEN 'overdue'
                WHEN c.follow_up_at < now() + interval '1 day' THEN 'due' ELSE 'upcoming' END,
           c.status, NULL::uuid
      FROM consultations c JOIN patients p ON p.patient_id=c.patient_id
     WHERE c.clinic_id=$1 AND c.deleted_at IS NULL AND c.follow_up_at IS NOT NULL
       AND c.follow_up_at >= now() - interval '30 days'`);
  return selects.length === 0 ? null : selects.join('\nUNION ALL\n');
}

async function loadReminderFeed(client, request) {
  const sql = reminderSelectSql(request);
  if (!sql) return { upcoming: [], alerts: [] };
  const rows = await client.query(
    `SELECT * FROM (${sql}) reminders ORDER BY scheduled_at ASC LIMIT 100`,
    [request.auth.clinicId],
  );
  const upcoming = rows.rows.filter((row) => new Date(row.scheduled_at) >= new Date()).slice(0, 30);
  const alerts = rows.rows.filter((row) => ['due', 'overdue'].includes(row.priority));
  return { upcoming, alerts };
}

async function syncReminderNotifications(client, request, alerts) {
  const notificationIds = new Map();
  for (const alert of alerts) {
    const dedupeKey = alert.event_id;
    const result = await client.query(
      `INSERT INTO clinic_notifications
         (clinic_id,user_id,dedupe_key,notification_type,title,body,priority,
          related_entity_type,related_entity_id,patient_id,scheduled_at,reminder_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       ON CONFLICT (clinic_id,user_id,dedupe_key) DO UPDATE SET
         title=excluded.title, body=excluded.body, priority=excluded.priority,
         scheduled_at=excluded.scheduled_at, reminder_at=excluded.reminder_at
       RETURNING notification_id,dismissed_at`,
      [request.auth.clinicId, request.auth.userId, dedupeKey, alert.event_type,
        alert.title, `${alert.patient_name}: ${alert.description}`, alert.priority,
        alert.related_entity_type, alert.related_entity_id, alert.patient_id,
        alert.scheduled_at, alert.reminder_at],
    );
    notificationIds.set(dedupeKey, result.rows[0]);
  }
  return notificationIds;
}

async function dismissObsoleteReminderNotifications(client, request, activeKeys) {
  await client.query(
    `UPDATE clinic_notifications
        SET dismissed_at=coalesce(dismissed_at,now())
      WHERE clinic_id=$1 AND user_id=$2 AND dismissed_at IS NULL
        AND NOT (dedupe_key = ANY($3::text[]))`,
    [request.auth.clinicId, request.auth.userId, activeKeys],
  );
}

function clinicalOperationStatusPermission(type, status, fromStatus) {
  if (type === 'Surgery') {
    if (status === 'Cancelled') return permissions.surgeryCancel;
    if (status === 'Completed') return permissions.surgeryComplete;
    if (['Pre-operative', 'Ready for Surgery'].includes(status)) return permissions.surgeryManagePreop;
    if (status === 'In Progress') return permissions.surgeryManageIntraop;
    if (status === 'Recovery') return permissions.surgeryManageRecovery;
    return permissions.surgeryEdit;
  }
  if (type === 'Prescription') {
    if (status === 'Active') return permissions.prescriptionsActivate;
    if (status === 'Cancelled') return permissions.prescriptionsCancel;
    if (['Dispensed', 'Partially Dispensed'].includes(status)) return permissions.prescriptionsDispense;
    return permissions.prescriptionsEdit;
  }
  if (type === 'Imaging') {
    if (status === 'Scheduled') return permissions.imagingSchedule;
    if (status === 'In Progress') return permissions.imagingUpload;
    if (['Awaiting Report', 'Reported'].includes(status)) return permissions.imagingReport;
    if (status === 'Completed') return permissions.imagingComplete;
    if (status === 'Cancelled') return permissions.imagingCancel;
    return permissions.imagingRequest;
  }
  if (type === 'Document') {
    if (status === 'Available' && fromStatus === 'Archived') return permissions.documentsArchive;
    return status === 'Archived' ? permissions.documentsArchive : permissions.documentsEdit;
  }
  if (status === 'Administered') return permissions.treatmentBoardAdminister;
  if (status === 'Delayed') return permissions.treatmentBoardDelay;
  if (status === 'Withheld') return permissions.treatmentBoardWithhold;
  if (status === 'Cancelled') return permissions.treatmentBoardCancel;
  if (status === 'Due') {
    return fromStatus === 'Delayed'
      ? permissions.treatmentBoardReopen
      : permissions.treatmentBoardCreate;
  }
  return permissions.treatmentBoardCreate;
}

const inventoryFields = {
  name: z.string().trim().min(1).max(200),
  genericName: z.string().trim().max(200).nullish(),
  brandName: z.string().trim().max(200).nullish(),
  manufacturer: z.string().trim().max(200).nullish(),
  supplier: z.string().trim().max(200).nullish(),
  sku: z.string().trim().max(120).nullish(),
  barcode: z.string().trim().max(120).nullish(),
  shortDescription: z.string().trim().max(500).nullish(),
  detailedDescription: z.string().trim().max(6000).nullish(),
  dosageForm: z.string().trim().max(120).nullish(),
  packSize: z.string().trim().max(160).nullish(),
  categoryId: z.string().trim().regex(/^[a-z0-9_]{2,80}$/),
  categoryName: z.string().trim().min(1).max(160),
  subcategoryId: z.string().trim().regex(/^[a-z0-9_]{2,80}$/).nullish(),
  subcategoryName: z.string().trim().max(160).nullish(),
  quantity: z.number().int().min(0).max(100000000),
  reorderLevel: z.number().int().min(0).max(100000000),
  batchNumber: z.string().trim().max(160).nullish(),
  expiryDate: z.string().date().nullish(),
  purchasePrice: z.number().min(0).max(1000000000000),
  sellingPrice: z.number().min(0).max(1000000000000),
  baseUnitLabel: z.string().trim().min(1).max(80).optional(),
  activeIngredient: z.string().trim().max(2000).nullish(),
  dosageAndRoute: z.string().trim().max(4000).nullish(),
  withdrawalMeat: z.string().trim().max(240).nullish(),
  withdrawalMilk: z.string().trim().max(240).nullish(),
  withdrawalEggs: z.string().trim().max(240).nullish(),
  withdrawalOther: z.string().trim().max(1000).nullish(),
  warnings: z.string().trim().max(4000).nullish(),
  contraindications: z.string().trim().max(4000).nullish(),
  adverseEffects: z.string().trim().max(4000).nullish(),
  storageConditions: z.string().trim().max(2000).nullish(),
  publicDisplayName: z.string().trim().max(200).nullish(),
  availableToPublic: z.boolean().optional(),
  isSellable: z.boolean().optional(),
  isArchived: z.boolean().optional(),
};

export const createInventoryItemSchema = z.object({
  submissionId: z.string().uuid(),
  ...inventoryFields,
});

export const updateInventoryItemSchema = z.object({
  ...inventoryFields,
  revision: z.number().int().min(1).optional(),
});

const inventoryPhotoSchema = z.object({
  contentType: z.enum(['image/jpeg', 'image/png']),
  data: z.string().min(4).max(1400000),
}).strict();

export const addInventoryStockSchema = z.object({
  quantityToAdd: z.number().int().min(1).max(100000000),
  batchNumber: z.string().trim().max(160).nullish(),
  expiryDate: z.string().date().nullish(),
  purchasePrice: z.number().min(0).max(1000000000000).nullish(),
}).strict();

const productUnitSchema = z.object({
  productUnitId: z.string().uuid().optional(),
  unitLabel: z.string().trim().min(1).max(80),
  isBaseUnit: z.boolean(),
  conversionToBase: z.number().int().positive().max(100000000),
  sellingPrice: z.number().min(0).max(1000000000000),
});

export const replaceProductUnitsSchema = z.object({
  units: z.array(productUnitSchema).min(1).max(100),
}).superRefine((input, ctx) => {
  if (input.units.filter((unit) => unit.isBaseUnit).length !== 1) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['units'], message: 'Exactly one base unit is required.' });
  }
  if (input.units.some((unit) => unit.isBaseUnit && unit.conversionToBase !== 1)) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['units'], message: 'The base unit conversion must be one.' });
  }
  const labels = input.units.map((unit) => unit.unitLabel.trim().toLowerCase());
  if (new Set(labels).size !== labels.length) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['units'], message: 'Unit labels must be unique.' });
  }
});

export const createReorderRequestSchema = z.object({
  productUnitId: z.string().uuid().nullable().optional(),
  requestedQuantity: z.number().int().positive().max(100000000),
}).strict();

const patientNumberStopWords = new Set(['VETERINARY', 'VET', 'CLINIC', 'HOSPITAL', 'ANIMAL', 'PET', 'CARE', 'SERVICES']);

export function suggestedPatientPrefix(clinicName) {
  const words = clinicName.toUpperCase().match(/[A-Z0-9]+/g) ?? [];
  const meaningful = words.filter((word) => !patientNumberStopWords.has(word));
  const candidates = meaningful.length > 0 ? meaningful : words;
  let prefix = candidates.length > 1
    ? candidates.map((word) => word[0]).join('')
    : candidates[0] ?? 'AVERA';
  prefix = prefix.replace(/[^A-Z0-9]/g, '').slice(0, 8);
  if (prefix.length < 2) prefix = 'AVR';
  return prefix;
}

export function formatPatientHospitalNumber(prefix, year, sequence, length) {
  if (!/^[A-Z0-9]{2,8}$/.test(prefix)) throw new Error('Invalid patient number prefix.');
  return `${prefix}-${year}-${String(sequence).padStart(length, '0')}`;
}

async function clinicNumbering(client, clinicId, userId) {
  const result = await client.query(
    `SELECT clinic_id, name, time_zone, patient_number_prefix,
            patient_number_sequence_length, patient_number_reset_yearly,
            patient_number_prefix_reviewed,
            EXTRACT(YEAR FROM timezone(time_zone, now()))::int AS registration_year
       FROM clinics
      WHERE clinic_id = $1 AND deleted_at IS NULL
      FOR UPDATE`,
    [clinicId],
  );
  const clinic = result.rows[0];
  if (!clinic) return null;
  if (!clinic.patient_number_prefix) {
    clinic.patient_number_prefix = suggestedPatientPrefix(clinic.name);
    await client.query(
      `UPDATE clinics
          SET patient_number_prefix = $1, patient_number_prefix_reviewed = false,
              patient_number_last_changed_at = now(), patient_number_last_changed_by = $2,
              updated_at = now(), revision = revision + 1
        WHERE clinic_id = $3`,
      [clinic.patient_number_prefix, userId, clinicId],
    );
  }
  return clinic;
}

function patientResponse(row, profilePhotoUrl = null) {
  return {
    patient_id: row.patient_id,
    hospital_number: row.hospital_number,
    name: row.name,
    species: row.species,
    breed: row.breed,
    sex: row.sex,
    status: row.status,
    date_of_birth: row.date_of_birth,
    is_date_of_birth_estimated: row.is_date_of_birth_estimated,
    original_age_value: row.original_age_value,
    original_age_unit: row.original_age_unit,
    age_recorded_at: row.age_recorded_at,
    current_weight_kg: row.current_weight_kg,
    image_placeholder: row.image_placeholder,
    profile_photo_url: profilePhotoUrl,
    registered_at: row.registered_at,
    revision: row.revision,
    owner_id: row.owner_id,
    owner_name: row.owner_name,
    owner_phone: row.owner_phone,
    owner_email: row.owner_email,
    owner_address: row.owner_address,
    owner_city: row.owner_city,
    owner_state: row.owner_state,
  };
}

function inventoryResponse(row) {
  return {
    inventory_product_id: row.inventory_product_id,
    name: row.name,
    category: row.category,
    category_key: row.category_key,
    subcategory: row.subcategory,
    subcategory_key: row.subcategory_key,
    generic_name: row.generic_name,
    brand_name: row.brand_name,
    manufacturer: row.manufacturer,
    supplier: row.supplier,
    sku: row.sku,
    barcode: row.barcode,
    short_description: row.short_description,
    detailed_description: row.detailed_description,
    dosage_form: row.dosage_form,
    pack_size: row.pack_size,
    base_unit_label: row.base_unit_label,
    active_ingredient: row.active_ingredient,
    dosage_and_route: row.dosage_and_route,
    withdrawal_meat: row.withdrawal_meat,
    withdrawal_milk: row.withdrawal_milk,
    withdrawal_eggs: row.withdrawal_eggs,
    withdrawal_other: row.withdrawal_other,
    warnings: row.warnings,
    contraindications: row.contraindications,
    adverse_effects: row.adverse_effects,
    storage_conditions: row.storage_conditions,
    public_display_name: row.public_display_name,
    available_to_public: row.available_to_public,
    is_sellable: row.is_sellable,
    is_archived: row.is_archived,
    batch_number: row.batch_number,
    expiry_date: row.expiry_date,
    purchase_price: row.purchase_price,
    selling_price: row.selling_price,
    quantity: row.quantity,
    reorder_level: row.reorder_level,
    status: row.status,
    created_at: row.created_at,
    updated_at: row.updated_at,
    revision: row.revision,
    product_units: row.product_units ?? [],
  };
}

async function inventoryResponseWithPhoto(app, row) {
  return {
    ...inventoryResponse(row),
    image_url: await app.profilePhotoStorage.signedUrl(row.image_path),
  };
}

async function inventoryProductWithUnits(client, clinicId, inventoryProductId) {
  const result = await client.query(
    `SELECT ${inventoryList.select}
       FROM inventory_products i
      WHERE i.clinic_id=$1 AND i.inventory_product_id=$2
        AND i.deleted_at IS NULL`,
    [clinicId, inventoryProductId],
  );
  return result.rows[0] ?? null;
}

function requireClinic(request, reply) {
  if (request.auth.clinicId) return true;
  reply.code(400).send({ error: 'clinic_context_required', message: 'Select a clinic workspace first.' });
  return false;
}

function parsePage(request, reply) {
  const parsed = pageSchema.safeParse(request.query);
  if (parsed.success) return parsed.data;
  reply.code(400).send({ error: 'validation_error', message: 'One or more list parameters are invalid.' });
  return null;
}

function orderBy(sort, direction, supported, fallback) {
  const column = supported[sort] ?? fallback;
  return `${column} ${direction === 'asc' ? 'ASC' : 'DESC'}`;
}

async function paged(app, request, config, query) {
  const { page, pageSize } = query;
  const offset = (page - 1) * pageSize;
  return withTenantTransaction(app.pool, request.auth, async (client) => {
    const count = await client.query(`SELECT count(*)::int AS total FROM ${config.from} WHERE ${config.where}`, config.values(query, request.auth));
    const values = [...config.values(query, request.auth), pageSize, offset];
    const result = await client.query(
      `SELECT ${config.select} FROM ${config.from} WHERE ${config.where} ORDER BY ${config.order(query)} LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values,
    );
    const total = count.rows[0].total;
    return { items: result.rows, page, pageSize, total, hasNextPage: offset + result.rows.length < total };
  });
}

function tenantList(config) {
  return async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const query = parsePage(request, reply);
    if (!query) return undefined;
    return paged(request.server, request, config, query);
  };
}

const patientList = {
  from: 'patients p JOIN owners o ON o.owner_id = p.owner_id',
  select: `p.patient_id, p.hospital_number, p.name, p.species, p.breed, p.sex, p.status, p.date_of_birth,
           p.is_date_of_birth_estimated, p.original_age_value, p.original_age_unit, p.age_recorded_at,
           p.current_weight_kg, p.image_placeholder, p.profile_photo_path,
           p.registered_at, p.updated_at, p.revision,
           o.owner_id, o.full_name AS owner_name, o.phone AS owner_phone,
           o.email AS owner_email, o.address AS owner_address,
           o.city AS owner_city, o.state AS owner_state`,
  where: `p.clinic_id = $1 AND p.deleted_at IS NULL AND o.deleted_at IS NULL
          AND ($2::text IS NULL OR p.name ILIKE $3 OR p.hospital_number ILIKE $3 OR o.full_name ILIKE $3 OR o.phone ILIKE $3)
          AND ($4::text IS NULL OR p.status = $4)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`, query.status ?? null],
  order: (query) => orderBy(query.sort, query.direction, { name: 'p.name', hospitalNumber: 'p.hospital_number', registeredAt: 'p.registered_at', updatedAt: 'p.updated_at' }, 'p.registered_at'),
};

async function patientResponseWithPhoto(app, row) {
  return patientResponse(
    row,
    await app.profilePhotoStorage.signedUrl(row.profile_photo_path),
  );
}

async function patientPage(app, request, query) {
  const offset = (query.page - 1) * query.pageSize;
  return withTenantTransaction(app.pool, request.auth, async (client) => {
    const filterValues = patientList.values(query, request.auth);
    const count = await client.query(
      `SELECT count(*)::int AS total FROM ${patientList.from} WHERE ${patientList.where}`,
      filterValues,
    );
    const values = [...filterValues, query.pageSize, offset];
    const result = await client.query(
      `SELECT ${patientList.select} FROM ${patientList.from}
        WHERE ${patientList.where} ORDER BY ${patientList.order(query)}
        LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values,
    );
    const items = await Promise.all(
      result.rows.map((row) => patientResponseWithPhoto(app, row)),
    );
    const total = count.rows[0].total;
    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      hasNextPage: offset + items.length < total,
    };
  });
}

const ownerList = {
  from: 'owners o',
  select: 'o.owner_id, o.full_name, o.phone, o.email, o.address, o.city, o.state, o.registered_at, o.updated_at, o.revision',
  where: `o.clinic_id = $1 AND o.deleted_at IS NULL AND ($2::text IS NULL OR o.full_name ILIKE $3 OR o.phone ILIKE $3 OR o.email ILIKE $3)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`],
  order: (query) => orderBy(query.sort, query.direction, { name: 'o.full_name', registeredAt: 'o.registered_at', updatedAt: 'o.updated_at' }, 'o.registered_at'),
};

function clinicalList({ table, alias, id, permission, select, dateColumn, searchColumns = [], statusColumn = 'status', extraWhere = '' }) {
  const search = searchColumns.length ? `($2::text IS NULL OR ${searchColumns.map((column) => `${column} ILIKE $3`).join(' OR ')})` : 'true';
  const status = statusColumn ? `AND ($4::text IS NULL OR ${alias}.${statusColumn} = $4)` : '';
  const dates = dateColumn ? `AND ($5::timestamptz IS NULL OR ${alias}.${dateColumn} >= $5) AND ($6::timestamptz IS NULL OR ${alias}.${dateColumn} <= $6)` : '';
  return {
    permission,
    config: {
      from: `${table} ${alias} LEFT JOIN patients p ON p.patient_id = ${alias}.patient_id LEFT JOIN owners o ON o.owner_id = p.owner_id`,
      select: `${alias}.${id}, ${alias}.clinic_id, ${alias}.patient_id, ${select}, p.name AS patient_name, p.hospital_number, o.full_name AS owner_name`,
      where: `${alias}.clinic_id = $1 AND ${search} ${status} ${dates} ${extraWhere}`,
      values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`, query.status ?? null, query.from ?? null, query.to ?? null],
      order: (query) => orderBy(query.sort, query.direction, { date: `${alias}.${dateColumn}`, patient: 'p.name', status: `${alias}.${statusColumn}` }, `${alias}.${dateColumn}`),
    },
  };
}

const lists = {
  consultations: clinicalList({ table: 'consultations', alias: 'c', id: 'consultation_id', permission: permissions.consultationsView, dateColumn: 'occurred_at', select: 'c.occurred_at, c.status, c.chief_complaint, c.final_diagnosis, c.charge, c.revision', searchColumns: ['p.name', 'c.final_diagnosis', 'c.chief_complaint'] }),
  vaccinations: clinicalList({ table: 'vaccinations', alias: 'v', id: 'vaccination_id', permission: permissions.vaccinationsView, dateColumn: 'administered_at', select: 'v.vaccine_name, v.status, v.administered_at, v.next_due_at, v.manufacturer, v.batch_number, v.certificate_number', searchColumns: ['p.name', 'v.vaccine_name'] }),
  laboratory: clinicalList({ table: 'laboratory_reports', alias: 'l', id: 'laboratory_report_id', permission: permissions.laboratoryView, dateColumn: 'requested_at', select: 'l.test_type, l.status, l.requested_at, l.reported_at, l.result_summary, l.result_values, l.cost', searchColumns: ['p.name', 'l.test_type', 'l.result_summary'] }),
  hospitalizations: clinicalList({ table: 'hospitalizations', alias: 'h', id: 'hospitalization_id', permission: permissions.hospitalizationView, dateColumn: 'admitted_at', select: 'h.admitted_at, h.discharged_at, h.ward, h.cage_or_pen, h.reason, h.diagnosis, h.outcome, h.cost', searchColumns: ['p.name', 'h.diagnosis', 'h.reason'], statusColumn: 'outcome' }),
  surgeries: clinicalList({ table: 'surgeries', alias: 's', id: 'surgery_id', permission: permissions.surgeryView, dateColumn: 'performed_at', select: 's.performed_at, s.procedure_name, s.anaesthesia_protocol, s.complication_notes, s.recovery_notes, s.follow_up_at, s.cost', searchColumns: ['p.name', 's.procedure_name'], statusColumn: null }),
  prescriptions: clinicalList({ table: 'prescriptions', alias: 'r', id: 'prescription_id', permission: permissions.prescriptionsView, dateColumn: 'prescribed_at', select: 'r.prescribed_at, r.drug_name, r.concentration, r.dose, r.route, r.frequency, r.duration_days, r.quantity, r.refill_status', searchColumns: ['p.name', 'r.drug_name'], statusColumn: 'refill_status' }),
  schedule: clinicalList({ table: 'schedule_entries', alias: 's', id: 'schedule_entry_id', permission: permissions.appointmentsView, dateColumn: 'scheduled_at', select: 's.scheduled_at, s.visit_type, s.status, s.notes, s.assigned_staff_id, s.revision, s.updated_at', searchColumns: ['p.name', 's.visit_type', 'o.full_name'], extraWhere: "AND lower(s.status) <> 'cancelled'" }),
};

const inventoryList = {
  from: 'inventory_products i',
  select: `i.inventory_product_id, i.name, i.generic_name, i.brand_name,
           i.category, i.category_key, i.subcategory, i.subcategory_key,
           i.manufacturer, i.supplier, i.sku,
           i.barcode, i.short_description, i.detailed_description,
           i.dosage_form, i.pack_size, i.batch_number,
           i.expiry_date, i.purchase_price, i.selling_price, i.quantity,
           i.reorder_level, i.status, i.created_at, i.updated_at, i.revision,
           i.base_unit_label, i.active_ingredient, i.dosage_and_route,
           i.withdrawal_meat, i.withdrawal_milk, i.withdrawal_eggs,
           i.withdrawal_other, i.warnings, i.contraindications,
           i.adverse_effects, i.storage_conditions, i.public_display_name,
           i.available_to_public, i.is_sellable, i.is_archived, i.image_path,
           COALESCE((
             SELECT jsonb_agg(jsonb_build_object(
               'product_unit_id', u.product_unit_id,
               'unit_label', u.unit_label,
               'is_base_unit', u.is_base_unit,
               'conversion_to_base', u.conversion_to_base,
               'selling_price', u.selling_price,
               'revision', u.revision
             ) ORDER BY u.is_base_unit DESC, lower(u.unit_label))
             FROM inventory_product_units u
             WHERE u.clinic_id=i.clinic_id
               AND u.inventory_product_id=i.inventory_product_id
           ), '[]'::jsonb) AS product_units`,
  where: `i.clinic_id = $1 AND i.deleted_at IS NULL AND i.is_archived = false AND ($2::text IS NULL OR i.name ILIKE $3 OR i.generic_name ILIKE $3 OR i.brand_name ILIKE $3 OR i.sku ILIKE $3 OR i.barcode ILIKE $3 OR i.active_ingredient ILIKE $3 OR i.batch_number ILIKE $3 OR i.category ILIKE $3 OR i.subcategory ILIKE $3)
          AND ($4::text IS NULL OR i.status = $4)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`, query.status ?? null],
  order: (query) => orderBy(query.sort, query.direction, { name: 'i.name', expiry: 'i.expiry_date', quantity: 'i.quantity' }, 'i.name'),
};

const movementsList = {
  from: 'stock_movements s JOIN inventory_products i ON i.inventory_product_id = s.inventory_product_id',
  select: 's.stock_movement_id, s.inventory_product_id, s.consultation_id, s.occurred_at, s.movement_type, s.quantity_delta, s.reference, i.name AS product_name',
  where: `s.clinic_id = $1 AND ($2::text IS NULL OR i.name ILIKE $3 OR s.reference ILIKE $3) AND ($4::timestamptz IS NULL OR s.occurred_at >= $4) AND ($5::timestamptz IS NULL OR s.occurred_at <= $5)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`, query.from ?? null, query.to ?? null],
  order: (query) => orderBy(query.sort, query.direction, { date: 's.occurred_at', product: 'i.name' }, 's.occurred_at'),
};

const invoiceList = {
  from: `invoices i
         LEFT JOIN patients p ON p.patient_id = i.patient_id
         LEFT JOIN owners o ON o.owner_id = i.owner_id
         LEFT JOIN farms f ON f.farm_id = i.farm_id AND f.clinic_id = i.clinic_id`,
  select: `i.invoice_id, i.invoice_number, i.status, i.subtotal, i.tax,
           i.discount, i.total, i.amount_paid, i.balance, i.issued_at, i.due_at,
            i.context_type, i.farm_id, i.farm_visit_date,
            COALESCE(i.client_name_snapshot, f.client_name) AS farm_client_name,
            COALESCE(i.client_phone_snapshot, f.client_phone) AS farm_client_phone,
            f.name AS farm_name,
            p.name AS patient_name, o.full_name AS owner_name, o.phone AS owner_phone,
           (SELECT string_agg(DISTINCT linked_patient.name, ', ' ORDER BY linked_patient.name)
              FROM invoice_line_items linked_names
              JOIN patients linked_patient ON linked_patient.patient_id=linked_names.patient_id
             WHERE linked_names.clinic_id=i.clinic_id AND linked_names.invoice_id=i.invoice_id) AS patient_names,
           (SELECT count(DISTINCT linked.patient_id)::int
              FROM invoice_line_items linked
             WHERE linked.clinic_id=i.clinic_id AND linked.invoice_id=i.invoice_id
               AND linked.patient_id IS NOT NULL) AS patient_count`,
  where: `i.clinic_id = $1 AND ($2::text IS NULL OR i.invoice_number ILIKE $3 OR p.name ILIKE $3 OR o.full_name ILIKE $3 OR f.name ILIKE $3 OR i.client_name_snapshot ILIKE $3 OR EXISTS (
            SELECT 1 FROM invoice_line_items linked_search
            JOIN patients linked_patient ON linked_patient.patient_id=linked_search.patient_id
            WHERE linked_search.clinic_id=i.clinic_id AND linked_search.invoice_id=i.invoice_id
              AND linked_patient.name ILIKE $3
          )) AND ($4::text IS NULL OR i.status = $4) AND ($5::timestamptz IS NULL OR i.issued_at >= $5) AND ($6::timestamptz IS NULL OR i.issued_at <= $6)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`, query.status ?? null, query.from ?? null, query.to ?? null],
  order: (query) => orderBy(query.sort, query.direction, { date: 'i.issued_at', number: 'i.invoice_number', balance: 'i.balance' }, 'i.issued_at'),
};

export async function upsertFarmInvoiceContext(client, clinicId, userId, farm) {
  await client.query(
    `INSERT INTO farms (farm_id, clinic_id, name, client_name, client_phone)
     VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (farm_id) DO UPDATE
       SET name=EXCLUDED.name, client_name=EXCLUDED.client_name,
           client_phone=EXCLUDED.client_phone, updated_at=now()
       WHERE farms.clinic_id=EXCLUDED.clinic_id`,
    [farm.farmId, clinicId, farm.name, farm.clientName ?? null, farm.clientPhone ?? null],
  );
  const ownedFarm = await client.query(
    'SELECT farm_id FROM farms WHERE clinic_id=$1 AND farm_id=$2',
    [clinicId, farm.farmId],
  );
  if (!ownedFarm.rows[0]) return false;
  for (const unit of farm.units) {
    await client.query(
      `INSERT INTO farm_units
         (farm_unit_id, clinic_id, farm_id, name, unit_type, species, breed)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (farm_unit_id) DO UPDATE
         SET name=EXCLUDED.name, unit_type=EXCLUDED.unit_type,
             species=EXCLUDED.species, breed=EXCLUDED.breed, updated_at=now()
         WHERE farm_units.clinic_id=EXCLUDED.clinic_id
           AND farm_units.farm_id=EXCLUDED.farm_id`,
      [unit.farmUnitId, clinicId, farm.farmId, unit.name,
        unit.unitType ?? null, unit.species ?? null, unit.breed ?? null],
    );
    for (const population of unit.populations) {
      await client.query(
        `INSERT INTO farm_unit_populations
           (farm_unit_population_id, clinic_id, farm_id, farm_unit_id,
            species_id, breed_id, male_count, female_count, unknown_count)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (farm_unit_population_id) DO UPDATE
           SET species_id=EXCLUDED.species_id, breed_id=EXCLUDED.breed_id,
               male_count=EXCLUDED.male_count, female_count=EXCLUDED.female_count,
               unknown_count=EXCLUDED.unknown_count, updated_at=now()
           WHERE farm_unit_populations.clinic_id=EXCLUDED.clinic_id
             AND farm_unit_populations.farm_id=EXCLUDED.farm_id
             AND farm_unit_populations.farm_unit_id=EXCLUDED.farm_unit_id`,
        [population.farmUnitPopulationId, clinicId, farm.farmId, unit.farmUnitId,
          population.speciesId, population.breedId ?? null,
          population.maleCount, population.femaleCount, population.unknownCount],
      );
    }
    const populationIds = unit.populations.map((item) => item.farmUnitPopulationId);
    await client.query(
      `DELETE FROM farm_unit_populations
        WHERE clinic_id=$1 AND farm_id=$2 AND farm_unit_id=$3
          AND NOT (farm_unit_population_id=ANY($4::uuid[]))`,
      [clinicId, farm.farmId, unit.farmUnitId, populationIds],
    );
  }
  for (const treatment of farm.treatments) {
    if (treatment.farmUnitId) {
      const ownedUnit = await client.query(
        `SELECT farm_unit_id FROM farm_units
          WHERE clinic_id=$1 AND farm_id=$2 AND farm_unit_id=$3`,
        [clinicId, farm.farmId, treatment.farmUnitId],
      );
      if (!ownedUnit.rows[0]) {
        const error = new Error('The treatment unit is not available in this clinic.');
        error.code = 'farm_unit_mismatch';
        throw error;
      }
    }
    if (treatment.targetScope === 'SelectedGroups') {
      if (!treatment.farmUnitId) {
        const error = new Error('Selected population groups require a farm unit.');
        error.code = 'farm_population_mismatch';
        throw error;
      }
      const ownedPopulations = await client.query(
        `SELECT farm_unit_population_id FROM farm_unit_populations
          WHERE clinic_id=$1 AND farm_id=$2 AND farm_unit_id=$3
            AND farm_unit_population_id=ANY($4::uuid[])`,
        [clinicId, farm.farmId, treatment.farmUnitId,
          treatment.targetPopulationIds],
      );
      if (ownedPopulations.rows.length !== treatment.targetPopulationIds.length) {
        const error = new Error(
          'One or more selected population groups are not part of this farm unit.',
        );
        error.code = 'farm_population_mismatch';
        throw error;
      }
    }
    await client.query(
      `INSERT INTO farm_treatment_records
         (farm_treatment_record_id, clinic_id, farm_id, farm_unit_id,
          treatment_type, product_name, occurred_at, animals_covered,
          billable_amount, cost_snapshot, notes, target_scope,
          target_population_ids, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
       ON CONFLICT (farm_treatment_record_id) DO UPDATE
         SET treatment_type=EXCLUDED.treatment_type,
             product_name=EXCLUDED.product_name,
             animals_covered=EXCLUDED.animals_covered,
             billable_amount=EXCLUDED.billable_amount,
             cost_snapshot=EXCLUDED.cost_snapshot,
             notes=EXCLUDED.notes, target_scope=EXCLUDED.target_scope,
             target_population_ids=EXCLUDED.target_population_ids,
             updated_at=now()
         WHERE farm_treatment_records.clinic_id=EXCLUDED.clinic_id
           AND farm_treatment_records.farm_id=EXCLUDED.farm_id`,
      [treatment.treatmentRecordId, clinicId, farm.farmId,
        treatment.farmUnitId ?? null, treatment.treatmentType,
        treatment.productName ?? null, treatment.occurredAt,
        treatment.animalsCovered ?? null, treatment.billableAmount,
        treatment.costSnapshot ?? null, treatment.notes ?? null,
        treatment.targetScope, treatment.targetPopulationIds, userId],
    );
  }
  const treatmentIds = farm.treatments.map((item) => item.treatmentRecordId);
  if (treatmentIds.length > 0) {
    const owned = await client.query(
      `SELECT farm_treatment_record_id FROM farm_treatment_records
        WHERE clinic_id=$1 AND farm_id=$2
          AND farm_treatment_record_id=ANY($3::uuid[])`,
      [clinicId, farm.farmId, treatmentIds],
    );
    if (owned.rows.length !== treatmentIds.length) return false;
  }
  return true;
}

export async function readFarmContext(client, clinicId, farmId) {
  const farm = (
    await client.query(
      `SELECT farm_id, name, client_name, client_phone, status, created_at, updated_at
         FROM farms WHERE clinic_id=$1 AND farm_id=$2`,
      [clinicId, farmId],
    )
  ).rows[0];
  if (!farm) return null;
  const units = (
    await client.query(
      `SELECT farm_unit_id, name, unit_type, species, breed, status,
              created_at, updated_at
         FROM farm_units
        WHERE clinic_id=$1 AND farm_id=$2
        ORDER BY name, farm_unit_id`,
      [clinicId, farmId],
    )
  ).rows;
  const populations = (
    await client.query(
      `SELECT farm_unit_population_id, farm_unit_id, species_id, breed_id,
              male_count, female_count, unknown_count, created_at, updated_at
         FROM farm_unit_populations
        WHERE clinic_id=$1 AND farm_id=$2
        ORDER BY farm_unit_id, species_id, breed_id`,
      [clinicId, farmId],
    )
  ).rows;
  const populationsByUnit = new Map();
  for (const population of populations) {
    const values = populationsByUnit.get(population.farm_unit_id) ?? [];
    values.push(population);
    populationsByUnit.set(population.farm_unit_id, values);
  }
  const treatments = (
    await client.query(
      `SELECT farm_treatment_record_id, farm_unit_id, treatment_type,
              product_name, occurred_at, animals_covered, billable_amount,
              cost_snapshot, notes, target_scope, target_population_ids,
              created_at, updated_at
         FROM farm_treatment_records
        WHERE clinic_id=$1 AND farm_id=$2
        ORDER BY occurred_at DESC, farm_treatment_record_id`,
      [clinicId, farmId],
    )
  ).rows;
  return {
    farm,
    units: units.map((unit) => ({
      ...unit,
      populations: populationsByUnit.get(unit.farm_unit_id) ?? [],
    })),
    treatments,
  };
}

async function prepareProductLines(client, clinicId, products) {
  const lines = [];
  for (const requested of products) {
    const result = await client.query(
      `SELECT p.inventory_product_id, p.name, p.batch_number, p.expiry_date,
              p.purchase_price, p.selling_price, p.quantity, p.base_unit_label,
              p.is_sellable, p.is_archived,
              u.product_unit_id,
              COALESCE(u.unit_label, NULLIF(btrim(p.base_unit_label), ''), 'unit') AS unit_label,
              COALESCE(u.conversion_to_base, 1) AS conversion_to_base,
              COALESCE(u.selling_price, p.selling_price) AS unit_selling_price
         FROM inventory_products p
         LEFT JOIN inventory_product_units u
           ON u.clinic_id=p.clinic_id AND u.inventory_product_id=p.inventory_product_id
          AND (($3::uuid IS NOT NULL AND u.product_unit_id=$3)
            OR ($3::uuid IS NULL AND u.is_base_unit=true))
        WHERE p.clinic_id=$1 AND p.inventory_product_id=$2
          AND p.deleted_at IS NULL
        FOR UPDATE OF p`,
      [clinicId, requested.inventoryProductId, requested.productUnitId ?? null],
    );
    const row = result.rows[0];
    if (!row ||
        (requested.productUnitId != null && !row.product_unit_id) ||
        !row.is_sellable || row.is_archived) {
      return { error: 'inventory_product_unavailable' };
    }
    if (row.expiry_date && new Date(row.expiry_date) < new Date(new Date().toISOString().slice(0, 10))) {
      return { error: 'inventory_product_expired' };
    }
    const conversion = Number(row.conversion_to_base);
    const quantity = Number(requested.quantity);
    const baseQuantity = quantity * conversion;
    const unitPrice = Number(row.unit_selling_price);
    lines.push({
      patientId: requested.patientId ?? null,
      farmUnitId: requested.farmUnitId ?? null,
      inventoryProductId: row.inventory_product_id,
      productUnitId: row.product_unit_id,
      description: row.name,
      quantity,
      unitPrice,
      lineTotal: Number((quantity * unitPrice).toFixed(2)),
      displayUnit: row.unit_label,
      conversion,
      baseQuantity,
      unitCost: row.purchase_price == null ? null : Number(row.purchase_price) * conversion,
      productName: row.name,
      batchNumber: row.batch_number,
      expiryDate: row.expiry_date,
    });
  }
  return { lines };
}

async function deductInvoiceInventory(client, clinicId, invoiceId) {
  const invoice = await client.query(
    `SELECT inventory_deducted_at FROM invoices
      WHERE clinic_id=$1 AND invoice_id=$2 FOR UPDATE`,
    [clinicId, invoiceId],
  );
  if (!invoice.rows[0] || invoice.rows[0].inventory_deducted_at) return;
  const quantities = await client.query(
    `SELECT l.inventory_product_id,
            sum(l.base_quantity_snapshot)::int AS base_quantity
       FROM invoice_line_items l
      WHERE l.clinic_id=$1 AND l.invoice_id=$2
        AND l.inventory_product_id IS NOT NULL
      GROUP BY l.inventory_product_id
      ORDER BY l.inventory_product_id`,
    [clinicId, invoiceId],
  );
  const rows = [];
  for (const quantity of quantities.rows) {
    const product = await client.query(
      `SELECT inventory_product_id, quantity, name
         FROM inventory_products
        WHERE clinic_id=$1 AND inventory_product_id=$2
        FOR UPDATE`,
      [clinicId, quantity.inventory_product_id],
    );
    if (!product.rows[0]) {
      const error = new Error('An invoiced inventory product is unavailable.');
      error.code = 'inventory_product_unavailable';
      throw error;
    }
    rows.push({ ...product.rows[0], base_quantity: quantity.base_quantity });
  }
  for (const row of rows) {
    if (Number(row.quantity) < Number(row.base_quantity)) {
      const error = new Error(`Insufficient stock for ${row.name}.`);
      error.code = 'insufficient_stock';
      throw error;
    }
  }
  for (const row of rows) {
    await client.query(
      `UPDATE inventory_products
          SET quantity=quantity-$3, revision=revision+1, updated_at=now()
        WHERE clinic_id=$1 AND inventory_product_id=$2`,
      [clinicId, row.inventory_product_id, Number(row.base_quantity)],
    );
    await client.query(
      `INSERT INTO stock_movements
         (clinic_id, inventory_product_id, occurred_at, movement_type,
          quantity_delta, reference)
       VALUES ($1,$2,now(),'Invoice Sale',$3,$4)`,
      [clinicId, row.inventory_product_id, -Number(row.base_quantity), `Invoice ${invoiceId}`],
    );
  }
  await client.query(
    'UPDATE invoices SET inventory_deducted_at=now() WHERE clinic_id=$1 AND invoice_id=$2',
    [clinicId, invoiceId],
  );
}

const paymentList = {
  from: 'payments p JOIN invoices i ON i.invoice_id = p.invoice_id',
  select: 'p.payment_id, p.invoice_id, p.paid_at, p.amount, p.method, i.invoice_number, i.status AS invoice_status',
  where: `p.clinic_id = $1 AND ($2::text IS NULL OR i.invoice_number ILIKE $3 OR p.method ILIKE $3) AND ($4::timestamptz IS NULL OR p.paid_at >= $4) AND ($5::timestamptz IS NULL OR p.paid_at <= $5)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`, query.from ?? null, query.to ?? null],
  order: (query) => orderBy(query.sort, query.direction, { date: 'p.paid_at', amount: 'p.amount' }, 'p.paid_at'),
};

const mediaList = {
  from: 'media_assets m LEFT JOIN patients p ON p.patient_id = m.patient_id',
  select: 'm.media_asset_id, m.patient_id, m.category, m.file_type, m.file_size_bytes, m.placeholder_key, m.created_at, p.name AS patient_name',
  where: `m.clinic_id = $1 AND ($2::text IS NULL OR m.category ILIKE $3 OR p.name ILIKE $3)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`],
  order: (query) => orderBy(query.sort, query.direction, { date: 'm.created_at', category: 'm.category' }, 'm.created_at'),
};

async function patientExists(client, clinicId, patientId) {
  return (await client.query('SELECT patient_id FROM patients WHERE patient_id = $1 AND clinic_id = $2 AND deleted_at IS NULL', [patientId, clinicId])).rowCount > 0;
}

async function patientSection(request, reply, table, id, permission, orderColumn) {
  if (!requireClinic(request, reply)) return undefined;
  const params = uuidSchema.safeParse(request.params);
  const query = parsePage(request, reply);
  if (!params.success || !query) return reply.code(400).send({ error: 'validation_error', message: 'Patient or list parameters are invalid.' });
  return withTenantTransaction(request.server.pool, request.auth, async (client) => {
    if (!await patientExists(client, request.auth.clinicId, params.data.patientId)) return reply.code(404).send({ error: 'not_found', message: 'The patient was not found in this clinic.' });
    const count = await client.query(`SELECT count(*)::int AS total FROM ${table} WHERE clinic_id = $1 AND patient_id = $2`, [request.auth.clinicId, params.data.patientId]);
    const offset = (query.page - 1) * query.pageSize;
    const rows = await client.query(`SELECT * FROM ${table} WHERE clinic_id = $1 AND patient_id = $2 ORDER BY ${orderColumn} DESC LIMIT $3 OFFSET $4`, [request.auth.clinicId, params.data.patientId, query.pageSize, offset]);
    const total = count.rows[0].total;
    return { items: rows.rows, page: query.page, pageSize: query.pageSize, total, hasNextPage: offset + rows.rows.length < total };
  });
}

export async function clinicalRoutes(app) {
  app.get('/api/v1/clinics/current', { preHandler: [authenticate, requirePermission(permissions.clinicsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    return withTenantTransaction(app.pool, request.auth, async (client) => ({ clinic: (await client.query('SELECT clinic_id, name, status, subscription_plan, created_at FROM clinics WHERE clinic_id = $1 AND deleted_at IS NULL', [request.auth.clinicId])).rows[0] }));
  });

  app.get('/api/v1/staff', { preHandler: [authenticate, requirePermission(permissions.usersView)] }, tenantList({
    from: 'users u', select: 'u.user_id, u.full_name, u.email, u.phone, u.account_type, u.status, u.role_id, u.last_login_at, u.created_at',
    where: `u.clinic_id = $1 AND u.deleted_at IS NULL AND ($2::text IS NULL OR u.full_name ILIKE $3 OR u.email ILIKE $3)`,
    values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`], order: (query) => orderBy(query.sort, query.direction, { name: 'u.full_name', lastLogin: 'u.last_login_at' }, 'u.full_name'),
  }));
  app.get('/api/v1/owners', { preHandler: [authenticate, requirePermission(permissions.patientsView)] }, tenantList(ownerList));
  app.get('/api/v1/patients', { preHandler: [authenticate, requirePermission(permissions.patientsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const query = parsePage(request, reply);
    if (!query) return undefined;
    return patientPage(app, request, query);
  });

  app.get('/api/v1/patients/number-preview', { preHandler: [authenticate, requirePermission(permissions.patientsCreate)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const clinic = await clinicNumbering(client, request.auth.clinicId, request.auth.userId);
      if (!clinic) return reply.code(404).send({ error: 'clinic_not_found', message: 'The active clinic was not found.' });
      const sequenceKey = clinic.patient_number_reset_yearly ? String(clinic.registration_year) : '0';
      const sequence = await client.query(
        `SELECT current_value FROM clinic_number_sequences
          WHERE clinic_id = $1 AND sequence_type = 'patient' AND sequence_key = $2`,
        [request.auth.clinicId, sequenceKey],
      );
      const nextSequence = Number(sequence.rows[0]?.current_value ?? 0) + 1;
      return {
        clinicId: request.auth.clinicId,
        prefix: clinic.patient_number_prefix,
        year: clinic.registration_year,
        sequence: nextSequence,
        sequenceLength: clinic.patient_number_sequence_length,
        prefixRequiresReview: !clinic.patient_number_prefix_reviewed,
        hospitalNumber: formatPatientHospitalNumber(clinic.patient_number_prefix, clinic.registration_year, nextSequence, clinic.patient_number_sequence_length),
      };
    });
  });

  app.post('/api/v1/patients', { preHandler: [authenticate, requirePermission(permissions.patientsCreate)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = createPatientSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Please review the patient and owner information.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const input = parsed.data;
      const existing = await client.query(
        `SELECT ${patientList.select}
           FROM ${patientList.from}
          WHERE p.clinic_id = $1 AND p.registration_submission_id = $2
            AND p.deleted_at IS NULL AND o.deleted_at IS NULL`,
        [request.auth.clinicId, input.submissionId],
      );
      if (existing.rows[0]) {
        return { patient: await patientResponseWithPhoto(app, existing.rows[0]), submissionId: input.submissionId, duplicateSubmission: true };
      }

      const clinic = await clinicNumbering(client, request.auth.clinicId, request.auth.userId);
      if (!clinic) return reply.code(404).send({ error: 'clinic_not_found', message: 'The active clinic was not found.' });
      const sequenceKey = clinic.patient_number_reset_yearly ? String(clinic.registration_year) : '0';
      const sequence = await client.query(
        `INSERT INTO clinic_number_sequences
           (clinic_id, sequence_type, sequence_key, current_value, sequence_length)
         VALUES ($1, 'patient', $2, 1, $3)
         ON CONFLICT (clinic_id, sequence_type, sequence_key)
         DO UPDATE SET current_value = clinic_number_sequences.current_value + 1,
                       sequence_length = EXCLUDED.sequence_length, updated_at = now()
         RETURNING current_value`,
        [request.auth.clinicId, sequenceKey, clinic.patient_number_sequence_length],
      );
      const hospitalNumber = formatPatientHospitalNumber(
        clinic.patient_number_prefix,
        clinic.registration_year,
        Number(sequence.rows[0].current_value),
        clinic.patient_number_sequence_length,
      );
      const owner = await client.query(
        `INSERT INTO owners (clinic_id, full_name, phone, email, address, registered_at)
         VALUES ($1,$2,$3,$4,$5,now()) RETURNING owner_id`,
        [request.auth.clinicId, input.owner.fullName, input.owner.phone, input.owner.email ?? null, input.owner.address ?? null],
      );
      const inserted = await client.query(
        `INSERT INTO patients
           (clinic_id, owner_id, hospital_number, name, species, species_id, breed, breed_id,
            sex, date_of_birth, is_date_of_birth_estimated, original_age_value,
            original_age_unit, age_recorded_at, colour, current_weight_kg,
            microchip_number, notes, status, registered_at, registration_submission_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,now(),$14,$15,$16,$17,'Active',now(),$18)
         RETURNING patient_id, hospital_number, name, species, breed, sex, status,
                   date_of_birth, is_date_of_birth_estimated, original_age_value,
                   original_age_unit, age_recorded_at, current_weight_kg,
                   image_placeholder, registered_at, revision, owner_id`,
        [request.auth.clinicId, owner.rows[0].owner_id, hospitalNumber, input.name, input.species,
          input.speciesId ?? null, input.breed, input.breedId ?? null, input.sex, input.dateOfBirth,
          input.isDateOfBirthEstimated, input.originalAgeValue ?? null, input.originalAgeUnit ?? null,
          input.colour ?? null, input.weightKg ?? null, input.microchipNumber ?? null,
          input.notes ?? null, input.submissionId],
      );
      const row = { ...inserted.rows[0], owner_name: input.owner.fullName, owner_phone: input.owner.phone };
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Patient',
        targetId: row.patient_id,
        action: 'patient.registered',
        newSummary: { hospitalNumber, patientName: input.name, species: input.species },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { patient: await patientResponseWithPhoto(app, row), submissionId: input.submissionId, duplicateSubmission: false };
    });
  });

  app.patch('/api/v1/patients/:patientId/status', { preHandler: [authenticate, requirePermission(permissions.patientsEdit)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = uuidSchema.safeParse(request.params);
    const parsed = patientStatusSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Choose a valid patient status.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const current = await client.query(
        `SELECT patient_id, status
           FROM patients
          WHERE clinic_id = $1 AND patient_id = $2 AND deleted_at IS NULL
          FOR UPDATE`,
        [request.auth.clinicId, params.data.patientId],
      );
      if (!current.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The patient was not found in this clinic.' });
      }
      const previousStatus = current.rows[0].status;
      const nextStatus = parsed.data.status;
      await client.query(
        `UPDATE patients
            SET status = $1,
                deceased_at = CASE WHEN $1 = 'Deceased' THEN coalesce(deceased_at, now()) ELSE NULL END,
                updated_at = now(), revision = revision + 1
          WHERE clinic_id = $2 AND patient_id = $3`,
        [nextStatus, request.auth.clinicId, params.data.patientId],
      );
      const patient = await client.query(
        `SELECT ${patientList.select}
           FROM ${patientList.from}
          WHERE p.clinic_id = $1 AND p.patient_id = $2
            AND p.deleted_at IS NULL AND o.deleted_at IS NULL`,
        [request.auth.clinicId, params.data.patientId],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Patient',
        targetId: params.data.patientId,
        action: 'patient.status_changed',
        previousSummary: { status: previousStatus },
        newSummary: { status: nextStatus },
        reason: parsed.data.reason ?? null,
        sessionId: request.auth.sessionId,
      });
      return { patient: await patientResponseWithPhoto(app, patient.rows[0]) };
    });
  });

  app.post('/api/v1/consultations', { preHandler: [authenticate, requirePermission(permissions.consultationsCreate)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = createConsultationSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the consultation information.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const input = parsed.data;
      const existing = await client.query(
        `SELECT consultation_id, patient_id, occurred_at, status, chief_complaint,
                final_diagnosis, treatment, prescription_notes, clinician_name_snapshot, revision
           FROM consultations
          WHERE clinic_id = $1 AND submission_id = $2 AND deleted_at IS NULL`,
        [request.auth.clinicId, input.submissionId],
      );
      if (existing.rows[0]) {
        return { consultation: existing.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
      }
      const patient = await client.query(
        `SELECT patient_id, status
           FROM patients
          WHERE clinic_id = $1 AND patient_id = $2 AND deleted_at IS NULL`,
        [request.auth.clinicId, input.patientId],
      );
      if (!patient.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The selected patient was not found in this clinic.' });
      }
      if (patient.rows[0].status !== 'Active') {
        return reply.code(409).send({ error: 'patient_inactive', message: 'Restore this patient to Active before creating a consultation.' });
      }
      const inserted = await client.query(
        `INSERT INTO consultations
           (clinic_id, patient_id, clinician_id, occurred_at, chief_complaint,
            history, examination, assessment, final_diagnosis, treatment,
            prescription_notes, clinician_name_snapshot, status, submission_id,
            created_at, updated_at)
         VALUES ($1,$2,$3,now(),$4,$5,$6,$7,$7,$8,$9,$10,'Completed',$11,now(),now())
         ON CONFLICT (clinic_id, submission_id)
           WHERE submission_id IS NOT NULL
         DO NOTHING
         RETURNING consultation_id, patient_id, occurred_at, status, chief_complaint,
                   final_diagnosis, treatment, prescription_notes,
                   clinician_name_snapshot, revision`,
        [request.auth.clinicId, input.patientId, request.auth.userId,
          input.chiefComplaint, input.history ?? null, input.examination ?? null,
          input.diagnosis ?? null, input.treatment ?? null,
          input.prescription ?? null, input.veterinarian ?? null, input.submissionId],
      );
      if (!inserted.rows[0]) {
        const duplicate = await client.query(
          `SELECT consultation_id, patient_id, occurred_at, status, chief_complaint,
                  final_diagnosis, treatment, prescription_notes,
                  clinician_name_snapshot, revision
             FROM consultations
            WHERE clinic_id = $1 AND submission_id = $2`,
          [request.auth.clinicId, input.submissionId],
        );
        return {
          consultation: duplicate.rows[0],
          submissionId: input.submissionId,
          duplicateSubmission: true,
        };
      }
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Consultation',
        targetId: inserted.rows[0].consultation_id,
        action: 'consultation.created',
        newSummary: { patientId: input.patientId, chiefComplaint: input.chiefComplaint },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { consultation: inserted.rows[0], submissionId: input.submissionId, duplicateSubmission: false };
    });
  });

  app.get('/api/v1/consultations/:consultationId', { preHandler: [authenticate, requirePermission(permissions.consultationsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = consultationUuidSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'validation_error', message: 'The consultation identifier is invalid.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const result = await client.query(
        `SELECT c.consultation_id, c.patient_id, c.occurred_at,
                c.chief_complaint, c.history, c.examination, c.assessment,
                c.final_diagnosis, c.treatment, c.prescription_notes,
                c.clinician_name_snapshot, c.status, c.revision,
                p.name AS patient_name, p.hospital_number
           FROM consultations c
           JOIN patients p ON p.patient_id = c.patient_id AND p.clinic_id = c.clinic_id
          WHERE c.clinic_id = $1 AND c.consultation_id = $2
            AND c.deleted_at IS NULL AND p.deleted_at IS NULL`,
        [request.auth.clinicId, params.data.consultationId],
      );
      if (!result.rows[0]) return reply.code(404).send({ error: 'not_found', message: 'The consultation was not found in this clinic.' });
      return { consultation: result.rows[0] };
    });
  });

  app.patch('/api/v1/consultations/:consultationId', { preHandler: [authenticate, requirePermission(permissions.consultationsEdit)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = consultationUuidSchema.safeParse(request.params);
    const parsed = updateConsultationSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the consultation information.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const current = await client.query(
        `SELECT consultation_id, patient_id, revision
           FROM consultations
          WHERE clinic_id=$1 AND consultation_id=$2 AND deleted_at IS NULL
          FOR UPDATE`,
        [request.auth.clinicId, params.data.consultationId],
      );
      if (!current.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The consultation was not found in this clinic.' });
      }
      if (Number(current.rows[0].revision) !== parsed.data.revision) {
        return reply.code(409).send({ error: 'revision_conflict', message: 'This consultation was updated elsewhere. Reload it before saving.' });
      }
      const input = parsed.data;
      const updated = await client.query(
        `UPDATE consultations
            SET chief_complaint=$3, history=$4, examination=$5,
                assessment=$6, final_diagnosis=$6, treatment=$7,
                prescription_notes=$8, updated_at=now(), revision=revision+1
          WHERE clinic_id=$1 AND consultation_id=$2
          RETURNING consultation_id, patient_id, occurred_at, status,
                    chief_complaint, history, examination, assessment,
                    final_diagnosis, treatment, prescription_notes,
                    clinician_name_snapshot, revision`,
        [request.auth.clinicId, params.data.consultationId,
          input.chiefComplaint, input.history ?? null, input.examination ?? null,
          input.diagnosis ?? null, input.treatment ?? null,
          input.prescription ?? null],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Consultation',
        targetId: params.data.consultationId,
        action: 'consultation.updated',
        previousSummary: { revision: current.rows[0].revision },
        newSummary: { revision: updated.rows[0].revision, changedFields: ['chiefComplaint', 'history', 'examination', 'diagnosis', 'treatment', 'prescription'] },
        sessionId: request.auth.sessionId,
      });
      return { consultation: updated.rows[0] };
    });
  });

  app.get('/api/v1/patients/:patientId', { preHandler: [authenticate, requirePermission(permissions.patientsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = uuidSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'validation_error', message: 'The patient identifier is invalid.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const patient = await client.query(`SELECT ${patientList.select} FROM ${patientList.from} WHERE p.clinic_id = $1 AND p.patient_id = $2 AND p.deleted_at IS NULL AND o.deleted_at IS NULL`, [request.auth.clinicId, params.data.patientId]);
      if (!patient.rows[0]) return reply.code(404).send({ error: 'not_found', message: 'The patient was not found in this clinic.' });
      return { patient: await patientResponseWithPhoto(app, patient.rows[0]) };
    });
  });

  app.post('/api/v1/patients/:patientId/profile-photo', { preHandler: [authenticate, requirePermission(permissions.patientsEdit)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = uuidSchema.safeParse(request.params);
    const parsed = patientPhotoSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'invalid_patient_photo', message: 'Choose a JPEG or PNG image.' });
    }
    let bytes;
    try {
      bytes = Buffer.from(parsed.data.data, 'base64');
    } catch (_) {
      return reply.code(400).send({ error: 'invalid_patient_photo', message: 'The selected image could not be read.' });
    }
    try {
      return await withTenantTransaction(app.pool, request.auth, async (client) => {
        const current = await client.query(
          `SELECT profile_photo_path
             FROM patients
            WHERE clinic_id = $1 AND patient_id = $2 AND deleted_at IS NULL
            FOR UPDATE`,
          [request.auth.clinicId, params.data.patientId],
        );
        if (!current.rows[0]) {
          return reply.code(404).send({ error: 'not_found', message: 'The patient was not found in this clinic.' });
        }
        const path = await app.profilePhotoStorage.uploadPatientPhoto({
          clinicId: request.auth.clinicId,
          patientId: params.data.patientId,
          contentType: parsed.data.contentType,
          bytes,
        });
        await client.query(
          `UPDATE patients
              SET profile_photo_path = $1, updated_at = now(), revision = revision + 1
            WHERE clinic_id = $2 AND patient_id = $3`,
          [path, request.auth.clinicId, params.data.patientId],
        );
        const patient = await client.query(
          `SELECT ${patientList.select} FROM ${patientList.from}
            WHERE p.clinic_id = $1 AND p.patient_id = $2
              AND p.deleted_at IS NULL AND o.deleted_at IS NULL`,
          [request.auth.clinicId, params.data.patientId],
        );
        await writeAudit(client, {
          clinicId: request.auth.clinicId,
          actingUserId: request.auth.userId,
          targetType: 'Patient',
          targetId: params.data.patientId,
          action: 'patient.photo_updated',
          newSummary: { photoUpdated: true },
          sessionId: request.auth.sessionId,
        });
        const previousPath = current.rows[0].profile_photo_path;
        if (previousPath && previousPath !== path) {
          await app.profilePhotoStorage.remove(previousPath);
        }
        return { patient: await patientResponseWithPhoto(app, patient.rows[0]) };
      });
    } catch (error) {
      return reply.code(error.statusCode ?? 500).send({
        error: error.code ?? 'patient_photo_upload_failed',
        message: error.statusCode
          ? error.message
          : 'The patient photo could not be uploaded.',
      });
    }
  });

  app.get('/api/v1/patients/:patientId/medical-file', { preHandler: [authenticate, requirePermission(permissions.patientsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = uuidSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'validation_error', message: 'The patient identifier is invalid.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const patient = await client.query(`SELECT ${patientList.select} FROM ${patientList.from} WHERE p.clinic_id = $1 AND p.patient_id = $2 AND p.deleted_at IS NULL AND o.deleted_at IS NULL`, [request.auth.clinicId, params.data.patientId]);
      if (!patient.rows[0]) return reply.code(404).send({ error: 'not_found', message: 'The patient was not found in this clinic.' });
      const patientId = params.data.patientId; const clinicId = request.auth.clinicId;
      const [consultations, vaccinations, laboratory, hospitalizations, surgeries, prescriptions, invoices, media, timeline] = await Promise.all([
        client.query('SELECT count(*)::int AS count, max(occurred_at) AS latest_at FROM consultations WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query('SELECT count(*)::int AS count, max(administered_at) AS latest_at FROM vaccinations WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query('SELECT count(*)::int AS count, max(requested_at) AS latest_at FROM laboratory_reports WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query('SELECT count(*)::int AS count, max(admitted_at) AS latest_at FROM hospitalizations WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query('SELECT count(*)::int AS count, max(performed_at) AS latest_at FROM surgeries WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query('SELECT count(*)::int AS count, max(prescribed_at) AS latest_at FROM prescriptions WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query(`SELECT count(*)::int AS count,
                             coalesce(sum(i.balance), 0) AS outstanding_balance
                        FROM invoices i
                       WHERE i.clinic_id=$1
                         AND (i.patient_id=$2 OR EXISTS (
                           SELECT 1 FROM invoice_line_items l
                            WHERE l.clinic_id=i.clinic_id
                              AND l.invoice_id=i.invoice_id
                              AND l.patient_id=$2
                         ))`, [clinicId, patientId]),
        client.query('SELECT count(*)::int AS count FROM media_assets WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query(`SELECT type, occurred_at, summary FROM (
          SELECT 'Consultation' AS type, occurred_at, coalesce(final_diagnosis, chief_complaint) AS summary FROM consultations WHERE clinic_id=$1 AND patient_id=$2
          UNION ALL SELECT 'Vaccination', administered_at, vaccine_name FROM vaccinations WHERE clinic_id=$1 AND patient_id=$2
          UNION ALL SELECT 'Laboratory', requested_at, test_type FROM laboratory_reports WHERE clinic_id=$1 AND patient_id=$2
        ) events ORDER BY occurred_at DESC LIMIT 10`, [clinicId, patientId]),
      ]);
      return { patient: await patientResponseWithPhoto(app, patient.rows[0]), summaries: { consultations: consultations.rows[0], vaccinations: vaccinations.rows[0], laboratory: laboratory.rows[0], hospitalizations: hospitalizations.rows[0], surgeries: surgeries.rows[0], prescriptions: prescriptions.rows[0], billing: invoices.rows[0], media: media.rows[0] }, timeline: timeline.rows };
    });
  });

  for (const [path, table, id, permission, order] of [
    ['consultations', 'consultations', 'consultation_id', permissions.consultationsView, 'occurred_at'], ['vaccinations', 'vaccinations', 'vaccination_id', permissions.vaccinationsView, 'administered_at'], ['laboratory', 'laboratory_reports', 'laboratory_report_id', permissions.laboratoryView, 'requested_at'], ['hospitalizations', 'hospitalizations', 'hospitalization_id', permissions.hospitalizationView, 'admitted_at'], ['surgeries', 'surgeries', 'surgery_id', permissions.surgeryView, 'performed_at'], ['prescriptions', 'prescriptions', 'prescription_id', permissions.prescriptionsView, 'prescribed_at'],
    ['appointments', 'schedule_entries', 'schedule_entry_id', permissions.appointmentsView, 'scheduled_at'], ['documents', 'media_assets', 'media_asset_id', permissions.mediaView, 'created_at'], ['images', 'media_assets', 'media_asset_id', permissions.mediaView, 'created_at'],
  ]) app.get(`/api/v1/patients/:patientId/${path}`, { preHandler: [authenticate, requirePermission(permission)] }, (request, reply) => patientSection(request, reply, table, id, permission, order));

  app.get('/api/v1/patients/:patientId/billing', { preHandler: [authenticate, requirePermission(permissions.billingView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = uuidSchema.safeParse(request.params);
    const query = parsePage(request, reply);
    if (!params.success || !query) return reply.code(400).send({ error: 'validation_error', message: 'Patient or billing parameters are invalid.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      if (!await patientExists(client, request.auth.clinicId, params.data.patientId)) {
        return reply.code(404).send({ error: 'not_found', message: 'The patient was not found in this clinic.' });
      }
      const offset = (query.page - 1) * query.pageSize;
      const values = [request.auth.clinicId, params.data.patientId];
      const predicate = `i.clinic_id=$1 AND (i.patient_id=$2 OR EXISTS (
        SELECT 1 FROM invoice_line_items linked
         WHERE linked.clinic_id=i.clinic_id AND linked.invoice_id=i.invoice_id
           AND linked.patient_id=$2))`;
      const [count, rows] = await Promise.all([
        client.query(`SELECT count(*)::int AS total FROM invoices i WHERE ${predicate}`, values),
        client.query(
          `SELECT i.*,
                  coalesce((SELECT sum(l.line_total) FROM invoice_line_items l
                             WHERE l.clinic_id=i.clinic_id AND l.invoice_id=i.invoice_id
                               AND l.patient_id=$2), 0) AS patient_attributed_total
             FROM invoices i WHERE ${predicate}
            ORDER BY i.issued_at DESC LIMIT $3 OFFSET $4`,
          [...values, query.pageSize, offset],
        ),
      ]);
      const total = count.rows[0].total;
      return { items: rows.rows, page: query.page, pageSize: query.pageSize, total, hasNextPage: offset + rows.rows.length < total };
    });
  });

  app.get('/api/v1/patients/:patientId/clinical-operations', { preHandler: [authenticate] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = uuidSchema.safeParse(request.params);
    const query = parsePage(request, reply);
    const operationType = typeof request.query?.operationType === 'string'
      ? request.query.operationType
      : null;
    if (!params.success || !query || !clinicalOperationTypes.includes(operationType)) {
      return reply.code(400).send({ error: 'validation_error', message: 'Patient or clinical operation parameters are invalid.' });
    }
    if (!hasPermission(request, operationPermissions[operationType].view)) {
      return reply.code(403).send({ error: 'permission_denied', message: 'Permission required for this clinical operation.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      if (!await patientExists(client, request.auth.clinicId, params.data.patientId)) {
        return reply.code(404).send({ error: 'not_found', message: 'The patient was not found in this clinic.' });
      }
      const offset = (query.page - 1) * query.pageSize;
      const values = [request.auth.clinicId, params.data.patientId, operationType];
      const [rows, count] = await Promise.all([
        client.query(
          `SELECT operation_id, patient_id, operation_type, title, description,
                  assigned_to, scheduled_at, status, priority, estimated_amount,
                  details, items, created_at, updated_at
             FROM clinical_operation_records
            WHERE clinic_id=$1 AND patient_id=$2 AND operation_type=$3
            ORDER BY scheduled_at DESC, created_at DESC
            LIMIT $4 OFFSET $5`,
          [...values, query.pageSize, offset],
        ),
        client.query(
          `SELECT count(*)::int AS total FROM clinical_operation_records
            WHERE clinic_id=$1 AND patient_id=$2 AND operation_type=$3`,
          values,
        ),
      ]);
      const total = count.rows[0].total;
      return {
        items: rows.rows,
        page: query.page,
        pageSize: query.pageSize,
        total,
        hasNextPage: offset + rows.rowCount < total,
      };
    });
  });

  for (const [path, list] of Object.entries(lists)) app.get(`/api/v1/${path === 'laboratory' ? 'laboratory-reports' : path}`, { preHandler: [authenticate, requirePermission(list.permission)] }, tenantList(list.config));

  app.get('/api/v1/schedule/:appointmentId', { preHandler: [authenticate, requirePermission(permissions.appointmentsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = appointmentUuidSchema.safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'The appointment identifier is invalid.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const result = await client.query(
        `SELECT s.schedule_entry_id, s.patient_id, s.scheduled_at,
                s.visit_type, s.status, s.notes, s.assigned_staff_id,
                s.created_at, s.updated_at, s.revision,
                p.name AS patient_name, p.hospital_number, p.species,
                p.breed, p.sex, p.status AS patient_status,
                p.date_of_birth, p.is_date_of_birth_estimated,
                p.original_age_value, p.original_age_unit, p.age_recorded_at,
                p.current_weight_kg, p.image_placeholder, p.registered_at,
                o.full_name AS owner_name, o.phone AS owner_phone,
                o.email AS owner_email, o.address AS owner_address,
                o.city AS owner_city, o.state AS owner_state,
                u.full_name AS assigned_staff_name,
                sp.professional_title AS assigned_staff_title
           FROM schedule_entries s
           LEFT JOIN patients p
             ON p.patient_id = s.patient_id
            AND p.clinic_id = s.clinic_id
            AND p.deleted_at IS NULL
           LEFT JOIN owners o
             ON o.owner_id = s.owner_id
            AND o.clinic_id = s.clinic_id
            AND o.deleted_at IS NULL
           LEFT JOIN users u
             ON u.user_id = s.assigned_staff_id
            AND u.deleted_at IS NULL
           LEFT JOIN staff_profiles sp ON sp.user_id = u.user_id
          WHERE s.clinic_id = $1 AND s.schedule_entry_id = $2`,
        [request.auth.clinicId, params.data.appointmentId],
      );
      if (!result.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The appointment was not found in this clinic.' });
      }
      return { appointment: result.rows[0] };
    });
  });

  app.patch('/api/v1/schedule/:appointmentId', { preHandler: [authenticate, requirePermission(permissions.appointmentsEdit)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = appointmentUuidSchema.safeParse(request.params);
    const parsed = updateAppointmentSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the appointment information.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const current = await client.query(
        `SELECT schedule_entry_id, patient_id, scheduled_at, visit_type,
                status, notes, assigned_staff_id, revision
           FROM schedule_entries
          WHERE clinic_id = $1 AND schedule_entry_id = $2
          FOR UPDATE`,
        [request.auth.clinicId, params.data.appointmentId],
      );
      if (!current.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The appointment was not found in this clinic.' });
      }
      if (Number(current.rows[0].revision) !== parsed.data.revision) {
        return reply.code(409).send({ error: 'revision_conflict', message: 'This appointment was updated elsewhere. Reload it before saving.' });
      }
      if (['cancelled', 'completed'].includes(String(current.rows[0].status).toLowerCase())) {
        return reply.code(409).send({ error: 'appointment_closed', message: 'A completed or cancelled appointment cannot be rescheduled.' });
      }
      const input = parsed.data;
      if (input.assignedStaffId) {
        const staff = await client.query(
          `SELECT 1 FROM clinic_memberships
            WHERE clinic_id = $1 AND user_id = $2
              AND membership_status = 'Active' AND deleted_at IS NULL`,
          [request.auth.clinicId, input.assignedStaffId],
        );
        if (!staff.rows[0]) {
          return reply.code(400).send({ error: 'invalid_staff', message: 'The selected staff member is not active in this clinic.' });
        }
      }
      const updated = await client.query(
        `UPDATE schedule_entries
            SET scheduled_at = $3, visit_type = $4, assigned_staff_id = $5,
                notes = $6, updated_at = now(), revision = revision + 1
          WHERE clinic_id = $1 AND schedule_entry_id = $2
          RETURNING schedule_entry_id, patient_id, scheduled_at, visit_type,
                    status, notes, assigned_staff_id, revision, updated_at`,
        [request.auth.clinicId, params.data.appointmentId, input.scheduledAt,
          input.visitType, input.assignedStaffId ?? null, input.notes ?? null],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Appointment',
        targetId: params.data.appointmentId,
        action: 'appointment.rescheduled',
        previousSummary: {
          scheduledAt: current.rows[0].scheduled_at,
          visitType: current.rows[0].visit_type,
          assignedStaffId: current.rows[0].assigned_staff_id,
          revision: current.rows[0].revision,
        },
        newSummary: {
          scheduledAt: updated.rows[0].scheduled_at,
          visitType: updated.rows[0].visit_type,
          assignedStaffId: updated.rows[0].assigned_staff_id,
          revision: updated.rows[0].revision,
        },
        sessionId: request.auth.sessionId,
      });
      return { appointment: updated.rows[0] };
    });
  });

  app.post('/api/v1/schedule/:appointmentId/cancel', { preHandler: [authenticate, requirePermission(permissions.appointmentsCancel)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = appointmentUuidSchema.safeParse(request.params);
    const parsed = cancelAppointmentSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'The appointment cancellation request is invalid.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const current = await client.query(
        `SELECT schedule_entry_id, patient_id, scheduled_at, visit_type,
                status, revision
           FROM schedule_entries
          WHERE clinic_id = $1 AND schedule_entry_id = $2
          FOR UPDATE`,
        [request.auth.clinicId, params.data.appointmentId],
      );
      if (!current.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The appointment was not found in this clinic.' });
      }
      if (Number(current.rows[0].revision) !== parsed.data.revision) {
        return reply.code(409).send({ error: 'revision_conflict', message: 'This appointment was updated elsewhere. Reload it before cancelling.' });
      }
      if (String(current.rows[0].status).toLowerCase() === 'cancelled') {
        return { appointment: current.rows[0], alreadyCancelled: true };
      }
      if (String(current.rows[0].status).toLowerCase() === 'completed') {
        return reply.code(409).send({ error: 'appointment_completed', message: 'A completed appointment cannot be cancelled.' });
      }
      const updated = await client.query(
        `UPDATE schedule_entries
            SET status = 'Cancelled', updated_at = now(), revision = revision + 1
          WHERE clinic_id = $1 AND schedule_entry_id = $2
          RETURNING schedule_entry_id, patient_id, scheduled_at, visit_type,
                    status, notes, assigned_staff_id, revision, updated_at`,
        [request.auth.clinicId, params.data.appointmentId],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Appointment',
        targetId: params.data.appointmentId,
        action: 'appointment.cancelled',
        previousSummary: { status: current.rows[0].status, revision: current.rows[0].revision },
        newSummary: { status: updated.rows[0].status, revision: updated.rows[0].revision },
        sessionId: request.auth.sessionId,
      });
      return { appointment: updated.rows[0], alreadyCancelled: false };
    });
  });

  app.get('/api/v1/clinical-operations', { preHandler: [authenticate] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const query = parsePage(request, reply);
    const operationType = typeof request.query?.operationType === 'string'
      ? request.query.operationType
      : null;
    if (!query || !clinicalOperationTypes.includes(operationType)) {
      return reply.code(400).send({ error: 'validation_error', message: 'A valid clinical operation type is required.' });
    }
    if (!hasPermission(request, operationPermissions[operationType].view)) {
      return reply.code(403).send({ error: 'permission_denied', message: 'Permission required for this clinical operation.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const offset = (query.page - 1) * query.pageSize;
      const search = `%${query.search ?? ''}%`;
      const values = [request.auth.clinicId, operationType, query.search ?? null, search, query.status ?? null];
      const where = `r.clinic_id=$1 AND r.operation_type=$2
        AND ($3::text IS NULL OR r.title ILIKE $4 OR r.description ILIKE $4 OR p.name ILIKE $4 OR o.full_name ILIKE $4)
        AND ($5::text IS NULL OR r.status=$5)`;
      const [rows, count] = await Promise.all([
        client.query(
          `SELECT r.operation_id, r.patient_id, r.operation_type, r.title,
                  r.description, r.assigned_to, r.scheduled_at, r.status,
                  r.priority, r.estimated_amount, r.details, r.items,
                  r.created_at, p.name AS patient_name, p.hospital_number,
                  o.full_name AS owner_name
             FROM clinical_operation_records r
             JOIN patients p ON p.patient_id=r.patient_id
             JOIN owners o ON o.owner_id=p.owner_id
            WHERE ${where}
            ORDER BY r.scheduled_at DESC, r.created_at DESC
            LIMIT $6 OFFSET $7`,
          [...values, query.pageSize, offset],
        ),
        client.query(`SELECT count(*)::int AS total FROM clinical_operation_records r JOIN patients p ON p.patient_id=r.patient_id JOIN owners o ON o.owner_id=p.owner_id WHERE ${where}`, values),
      ]);
      const total = count.rows[0].total;
      return { items: rows.rows, page: query.page, pageSize: query.pageSize, total, hasNextPage: offset + rows.rowCount < total };
    });
  });

  app.get('/api/v1/clinical-operations/:operationId', { preHandler: [authenticate] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = clinicalOperationUuidSchema.safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'The clinical record identifier is invalid.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const result = await client.query(
        `SELECT r.operation_id, r.patient_id, r.operation_type, r.title,
                r.description, r.assigned_to, r.scheduled_at, r.status,
                r.priority, r.estimated_amount, r.details, r.items,
                r.created_at, r.updated_at, p.name AS patient_name,
                p.hospital_number, p.species, p.breed, p.sex,
                o.full_name AS owner_name, o.phone AS owner_phone,
                creator.full_name AS created_by_name
           FROM clinical_operation_records r
           JOIN patients p ON p.patient_id=r.patient_id AND p.clinic_id=r.clinic_id
           JOIN owners o ON o.owner_id=p.owner_id AND o.clinic_id=r.clinic_id
           LEFT JOIN users creator ON creator.user_id=r.created_by
          WHERE r.clinic_id=$1 AND r.operation_id=$2`,
        [request.auth.clinicId, params.data.operationId],
      );
      const operation = result.rows[0];
      if (!operation) {
        return reply.code(404).send({ error: 'not_found', message: 'The clinical record was not found in this clinic.' });
      }
      if (!hasPermission(request, operationPermissions[operation.operation_type].view)) {
        return reply.code(403).send({ error: 'permission_denied', message: 'Permission required for this clinical record.' });
      }
      const activity = await client.query(
        `SELECT a.action, a.previous_summary, a.new_summary, a.reason,
                a.created_at, u.full_name AS actor_name
           FROM audit_logs a
           LEFT JOIN users u ON u.user_id=a.acting_user_id
          WHERE a.clinic_id=$1 AND a.target_id=$2
            AND a.action IN ('clinical_operation.created', 'clinical_operation.status_changed')
          ORDER BY a.created_at DESC`,
        [request.auth.clinicId, params.data.operationId],
      );
      return {
        operation,
        allowedNextStatuses: clinicalOperationTransitions[operation.operation_type]?.[operation.status] ?? [],
        activity: activity.rows,
      };
    });
  });

  app.patch('/api/v1/clinical-operations/:operationId/status', { preHandler: [authenticate] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = clinicalOperationUuidSchema.safeParse(request.params);
    const parsed = updateClinicalOperationStatusSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the requested status change.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const currentResult = await client.query(
        `SELECT operation_id, operation_type, status
           FROM clinical_operation_records
          WHERE clinic_id=$1 AND operation_id=$2
          FOR UPDATE`,
        [request.auth.clinicId, params.data.operationId],
      );
      const current = currentResult.rows[0];
      if (!current) {
        return reply.code(404).send({ error: 'not_found', message: 'The clinical record was not found in this clinic.' });
      }
      const permission = clinicalOperationStatusPermission(
        current.operation_type,
        parsed.data.status,
        current.status,
      );
      if (!hasPermission(request, permission)) {
        await writeAudit(client, {
          clinicId: request.auth.clinicId, actingUserId: request.auth.userId,
          targetType: current.operation_type, targetId: current.operation_id,
          action: 'clinical_operation.status_blocked',
          previousSummary: { status: current.status },
          newSummary: { requestedStatus: parsed.data.status },
          sessionId: request.auth.sessionId, success: false,
          reason: 'permission_denied',
        });
        return reply.code(403).send({ error: 'permission_denied', message: 'You do not have permission to perform this clinical action.' });
      }
      const allowed = clinicalOperationTransitions[current.operation_type]?.[current.status] ?? [];
      if (!allowed.includes(parsed.data.status)) {
        return reply.code(409).send({
          error: 'invalid_status_transition',
          message: `This ${current.operation_type.toLowerCase()} cannot move from ${current.status} to ${parsed.data.status}.`,
        });
      }
      if (['Cancelled', 'Missed', 'Delayed', 'Withheld'].includes(parsed.data.status)
          && !parsed.data.reason?.trim()) {
        return reply.code(400).send({ error: 'reason_required', message: 'Enter a reason for this status change.' });
      }
      const updated = await client.query(
        `UPDATE clinical_operation_records
            SET status=$3, updated_at=now()
          WHERE clinic_id=$1 AND operation_id=$2
          RETURNING operation_id, patient_id, operation_type, title, status,
                    scheduled_at, updated_at`,
        [request.auth.clinicId, params.data.operationId, parsed.data.status],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId, actingUserId: request.auth.userId,
        targetType: current.operation_type, targetId: current.operation_id,
        action: 'clinical_operation.status_changed',
        previousSummary: { status: current.status },
        newSummary: { status: parsed.data.status },
        sessionId: request.auth.sessionId, reason: parsed.data.reason ?? null,
      });
      return { operation: updated.rows[0] };
    });
  });

  app.post('/api/v1/clinical-operations', { preHandler: [authenticate] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = createClinicalOperationSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the clinical operation information.' });
    }
    const input = parsed.data;
    if (!hasPermission(request, operationPermissions[input.operationType].create)) {
      return reply.code(403).send({ error: 'permission_denied', message: 'Permission required to create this clinical operation.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const existing = await client.query(
        `SELECT operation_id, patient_id, operation_type, title, status, scheduled_at
           FROM clinical_operation_records WHERE clinic_id=$1 AND submission_id=$2`,
        [request.auth.clinicId, input.submissionId],
      );
      if (existing.rows[0]) return { operation: existing.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
      if (!await patientExists(client, request.auth.clinicId, input.patientId)) {
        return reply.code(404).send({ error: 'patient_not_found', message: 'The selected active patient was not found in this clinic.' });
      }
      const inserted = await client.query(
        `INSERT INTO clinical_operation_records
           (clinic_id, patient_id, operation_type, title, description,
            assigned_to, scheduled_at, status, priority, estimated_amount,
            details, items, created_by, submission_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
         RETURNING operation_id, patient_id, operation_type, title, status, scheduled_at`,
        [request.auth.clinicId, input.patientId, input.operationType, input.title,
          input.description ?? null, input.assignedTo ?? null, input.scheduledAt,
          input.status, input.priority, input.estimatedAmount ?? null,
          input.details, input.items, request.auth.userId, input.submissionId],
      );
      const operation = inserted.rows[0];

      if (input.operationType === 'Surgery') {
        await client.query(
          `INSERT INTO surgeries (clinic_id, patient_id, performed_at, procedure_name,
             surgeon_id, anaesthesia_protocol, complication_notes, recovery_notes, cost)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
          [request.auth.clinicId, input.patientId, input.scheduledAt, input.title,
            request.auth.userId, input.details.anaesthetist || null,
            input.description ?? null, input.details.instructions || null,
            input.estimatedAmount ?? 0],
        );
      } else if (input.operationType === 'Prescription' && input.items.length > 0) {
        const item = input.items[0];
        await client.query(
          `INSERT INTO prescriptions (clinic_id, patient_id, prescribed_at, drug_name,
             concentration, dose, route, frequency, duration_days, quantity,
             instructions, prescriber_id, refill_status)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`,
          [request.auth.clinicId, input.patientId, input.scheduledAt,
            item.name || input.title, item.strength || null, item.dose || null,
            item.route || null, item.frequency || null,
            Number.parseInt(item.duration, 10) || null, Number(item.quantity) || null,
            item.instructions || input.description || null, request.auth.userId, input.status],
        );
      } else if (input.operationType === 'Document' || input.operationType === 'Imaging') {
        await client.query(
          `INSERT INTO media_assets (clinic_id, patient_id, category, file_type,
             file_size_bytes, placeholder_key, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,now())`,
          [request.auth.clinicId, input.patientId, input.operationType,
            input.details.mimeType || 'metadata', Number(input.details.fileSize) || 0,
            input.details.fileName || operation.operation_id],
        );
      }

      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: input.operationType,
        targetId: operation.operation_id,
        action: 'clinical_operation.created',
        newSummary: { patientId: input.patientId, operationType: input.operationType, title: input.title },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { operation, submissionId: input.submissionId, duplicateSubmission: false };
    });
  });

  app.get('/api/v1/vaccinations/:vaccinationId', { preHandler: [authenticate, requirePermission(permissions.vaccinationsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = vaccinationUuidSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'validation_error', message: 'The vaccination identifier is invalid.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const record = await client.query(
        `SELECT v.vaccination_id, v.patient_id, v.vaccine_name, v.manufacturer,
                v.batch_number, v.route, v.dose, v.administered_at,
                v.next_due_at, v.status, v.notes, v.revision,
                p.name AS patient_name, p.hospital_number, p.species, p.breed,
                p.date_of_birth, p.is_date_of_birth_estimated,
                o.full_name AS owner_name, o.phone AS owner_phone,
                u.full_name AS administered_by_name
           FROM vaccinations v
           JOIN patients p ON p.patient_id=v.patient_id AND p.clinic_id=v.clinic_id
           JOIN owners o ON o.owner_id=p.owner_id AND o.clinic_id=v.clinic_id
           LEFT JOIN users u ON u.user_id=v.administered_by
          WHERE v.clinic_id=$1 AND v.vaccination_id=$2`,
        [request.auth.clinicId, params.data.vaccinationId],
      );
      if (!record.rows[0]) return reply.code(404).send({ error: 'not_found', message: 'The vaccination was not found in this clinic.' });
      const item = record.rows[0];
      const history = await client.query(
        `SELECT v.vaccination_id, v.patient_id, v.vaccine_name, v.manufacturer,
                v.batch_number, v.route, v.dose, v.administered_at,
                v.next_due_at, v.status, u.full_name AS administered_by_name
           FROM vaccinations v
           LEFT JOIN users u ON u.user_id=v.administered_by
          WHERE v.clinic_id=$1 AND v.patient_id=$2
            AND lower(v.vaccine_name)=lower($3)
          ORDER BY v.administered_at DESC, v.vaccination_id DESC`,
        [request.auth.clinicId, item.patient_id, item.vaccine_name],
      );
      return { vaccination: item, history: history.rows };
    });
  });

  app.post('/api/v1/vaccinations', { preHandler: [authenticate, requirePermission(permissions.vaccinationsAdd)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = createVaccinationSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Please review the vaccination information.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const input = parsed.data;
      const existing = await client.query(
        `SELECT vaccination_id, patient_id, vaccine_name, administered_at,
                next_due_at, route, manufacturer, batch_number, status
           FROM vaccinations
          WHERE clinic_id=$1 AND submission_id=$2`,
        [request.auth.clinicId, input.submissionId],
      );
      if (existing.rows[0]) return { vaccination: existing.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
      const patient = await client.query(
        'SELECT patient_id FROM patients WHERE clinic_id=$1 AND patient_id=$2 AND status ILIKE $3 AND deleted_at IS NULL',
        [request.auth.clinicId, input.patientId, 'active'],
      );
      if (!patient.rows[0]) return reply.code(404).send({ error: 'patient_not_found', message: 'The selected active patient was not found in this clinic.' });
      const inserted = await client.query(
        `INSERT INTO vaccinations
           (clinic_id, patient_id, vaccine_name, manufacturer, batch_number,
            route, dose, administered_at, next_due_at, administered_by,
            notes, reminder_status, status, submission_id, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'Pending','Completed',$12,now(),now())
         ON CONFLICT (clinic_id, submission_id) WHERE submission_id IS NOT NULL
         DO NOTHING
         RETURNING vaccination_id, patient_id, vaccine_name, administered_at,
                   next_due_at, route, manufacturer, batch_number, status`,
        [request.auth.clinicId, input.patientId, input.vaccineName,
          input.manufacturer || null, input.batchNumber || null,
          input.route || null, input.dose || null, input.administeredAt,
          input.nextDueAt || null, request.auth.userId, input.notes || null,
          input.submissionId],
      );
      if (!inserted.rows[0]) {
        const duplicate = await client.query(
          `SELECT vaccination_id, patient_id, vaccine_name, administered_at,
                  next_due_at, route, manufacturer, batch_number, status
             FROM vaccinations WHERE clinic_id=$1 AND submission_id=$2`,
          [request.auth.clinicId, input.submissionId],
        );
        return { vaccination: duplicate.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
      }
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Vaccination',
        targetId: inserted.rows[0].vaccination_id,
        action: 'vaccination.recorded',
        newSummary: { patientId: input.patientId, vaccineName: input.vaccineName },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { vaccination: inserted.rows[0], submissionId: input.submissionId, duplicateSubmission: false };
    });
  });

  app.post('/api/v1/schedule', { preHandler: [authenticate, requirePermission(permissions.appointmentsCreate)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = createAppointmentSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Please review the appointment information.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const input = parsed.data;
      const existing = await client.query(
        `SELECT schedule_entry_id, patient_id, scheduled_at, visit_type,
                status, notes, assigned_staff_id, revision
           FROM schedule_entries
          WHERE clinic_id=$1 AND submission_id=$2`,
        [request.auth.clinicId, input.submissionId],
      );
      if (existing.rows[0]) return { appointment: existing.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
      const patient = await client.query(
        'SELECT patient_id, owner_id FROM patients WHERE clinic_id=$1 AND patient_id=$2 AND status ILIKE $3 AND deleted_at IS NULL',
        [request.auth.clinicId, input.patientId, 'active'],
      );
      if (!patient.rows[0]) return reply.code(404).send({ error: 'patient_not_found', message: 'The selected active patient was not found in this clinic.' });
      if (input.assignedStaffId) {
        const staff = await client.query(
          `SELECT 1 FROM clinic_memberships
            WHERE clinic_id=$1 AND user_id=$2
              AND membership_status='Active' AND deleted_at IS NULL`,
          [request.auth.clinicId, input.assignedStaffId],
        );
        if (!staff.rows[0]) return reply.code(400).send({ error: 'invalid_staff', message: 'The selected staff member is not active in this clinic.' });
      }
      const inserted = await client.query(
        `INSERT INTO schedule_entries
           (clinic_id, patient_id, owner_id, assigned_staff_id, scheduled_at,
            visit_type, status, notes, submission_id, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,'Confirmed',$7,$8,now(),now())
         ON CONFLICT (clinic_id, submission_id) WHERE submission_id IS NOT NULL
         DO NOTHING
         RETURNING schedule_entry_id, patient_id, scheduled_at, visit_type,
                   status, notes, assigned_staff_id, revision`,
        [request.auth.clinicId, input.patientId, patient.rows[0].owner_id,
          input.assignedStaffId || null, input.scheduledAt, input.visitType,
          input.notes || null, input.submissionId],
      );
      if (!inserted.rows[0]) {
        const duplicate = await client.query(
          `SELECT schedule_entry_id, patient_id, scheduled_at, visit_type,
                  status, notes, assigned_staff_id, revision
             FROM schedule_entries WHERE clinic_id=$1 AND submission_id=$2`,
          [request.auth.clinicId, input.submissionId],
        );
        return { appointment: duplicate.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
      }
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Appointment',
        targetId: inserted.rows[0].schedule_entry_id,
        action: 'appointment.created',
        newSummary: { patientId: input.patientId, scheduledAt: input.scheduledAt, visitType: input.visitType },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { appointment: inserted.rows[0], submissionId: input.submissionId, duplicateSubmission: false };
    });
  });

  app.get('/api/v1/farms/:farmId/context', {
    preHandler: [authenticate, requirePermission(permissions.farmsView)],
  }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = farmUuidSchema.safeParse(request.params);
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'validation_error',
        message: 'The farm identifier is invalid.',
      });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const context = await readFarmContext(
        client,
        request.auth.clinicId,
        parsed.data.farmId,
      );
      if (!context) {
        return reply.code(404).send({
          error: 'farm_not_found',
          message: 'The selected farm is not available in this clinic.',
        });
      }
      return { farmContext: context };
    });
  });

  app.put('/api/v1/farms/:farmId/context', {
    preHandler: [authenticate, requirePermission(permissions.farmUnitsManage)],
  }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = farmUuidSchema.safeParse(request.params);
    const body = farmContextSchema.safeParse(request.body);
    if (!params.success || !body.success || params.data.farmId !== body.data.farmId) {
      return reply.code(400).send({
        error: 'validation_error',
        message: 'Please review the farm information.',
      });
    }
    if (body.data.treatments.length > 0
        && !hasPermission(request, permissions.farmHealthRecord)) {
      return reply.code(403).send({
        error: 'permission_required',
        message: 'You do not have permission to record farm treatments.',
      });
    }
    try {
      return await withTenantTransaction(app.pool, request.auth, async (client) => {
        const saved = await upsertFarmInvoiceContext(
          client,
          request.auth.clinicId,
          request.auth.userId,
          body.data,
        );
        if (!saved) {
          return reply.code(404).send({
            error: 'farm_not_found',
            message: 'The selected farm is not available in this clinic.',
          });
        }
        await writeAudit(client, {
          clinicId: request.auth.clinicId,
          actingUserId: request.auth.userId,
          targetType: 'Farm',
          targetId: body.data.farmId,
          action: 'farm.context_updated',
          newSummary: {
            unitCount: body.data.units.length,
            treatmentCount: body.data.treatments.length,
          },
          sessionId: request.auth.sessionId,
        });
        return {
          farmContext: await readFarmContext(
            client,
            request.auth.clinicId,
            body.data.farmId,
          ),
        };
      });
    } catch (error) {
      if (error.code === 'farm_unit_mismatch'
          || error.code === 'farm_population_mismatch') {
        return reply.code(409).send({ error: error.code, message: error.message });
      }
      throw error;
    }
  });

  app.post('/api/v1/invoices', { preHandler: [authenticate, requirePermission(permissions.billingCreate)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = createInvoiceSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Please review the invoice information.' });
    try {
      return await withTenantTransaction(app.pool, request.auth, async (client) => {
      const input = parsed.data;
      const duplicate = await client.query(
        `SELECT invoice_id, invoice_number, patient_id, status, subtotal,
                total, amount_paid, balance, issued_at
           FROM invoices
          WHERE clinic_id=$1 AND submission_id=$2`,
        [request.auth.clinicId, input.submissionId],
      );
      if (duplicate.rows[0]) {
        const existing = duplicate.rows[0];
        if (existing.status === 'Draft' && input.status === 'Unpaid') {
          await deductInvoiceInventory(client, request.auth.clinicId, existing.invoice_id);
          const issued = await client.query(
            `UPDATE invoices
                SET status='Unpaid', balance=total
              WHERE clinic_id=$1 AND invoice_id=$2 AND status='Draft'
              RETURNING invoice_id, invoice_number, patient_id, status, subtotal,
                        total, amount_paid, balance, issued_at`,
            [request.auth.clinicId, existing.invoice_id],
          );
          if (issued.rows[0]) {
            await writeAudit(client, {
              clinicId: request.auth.clinicId,
              actingUserId: request.auth.userId,
              targetType: 'Invoice',
              targetId: existing.invoice_id,
              action: 'billing.invoice_issued',
              previousSummary: { status: 'Draft' },
              newSummary: { status: 'Unpaid', total: Number(issued.rows[0].total) },
              sessionId: request.auth.sessionId,
            });
            return { ...issued.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
          }
        }
        if (existing.status === 'Draft' && input.status === 'Paid') {
          await deductInvoiceInventory(client, request.auth.clinicId, existing.invoice_id);
          const promoted = await client.query(
            `UPDATE invoices
                SET status='Paid', amount_paid=total, balance=0
              WHERE clinic_id=$1 AND invoice_id=$2 AND status='Draft'
              RETURNING invoice_id, invoice_number, patient_id, status, subtotal,
                        total, amount_paid, balance, issued_at`,
            [request.auth.clinicId, existing.invoice_id],
          );
          if (promoted.rows[0]) {
            const total = Number(promoted.rows[0].total);
            if (total > 0) {
              await client.query(
                `INSERT INTO payments (clinic_id, invoice_id, paid_at, amount, method)
                 VALUES ($1,$2,now(),$3,'Clinic Billing')`,
                [request.auth.clinicId, existing.invoice_id, total],
              );
            }
            await writeAudit(client, {
              clinicId: request.auth.clinicId,
              actingUserId: request.auth.userId,
              targetType: 'Invoice',
              targetId: existing.invoice_id,
              action: 'billing.sale_recorded',
              previousSummary: { status: 'Draft' },
              newSummary: { status: 'Paid', total },
              sessionId: request.auth.sessionId,
            });
            return { ...promoted.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
          }
          const current = await client.query(
            `SELECT invoice_id, invoice_number, patient_id, status, subtotal,
                    total, amount_paid, balance, issued_at
               FROM invoices
              WHERE clinic_id=$1 AND invoice_id=$2`,
            [request.auth.clinicId, existing.invoice_id],
          );
          return { ...current.rows[0], submissionId: input.submissionId, duplicateSubmission: true };
        }
        return { ...existing, submissionId: input.submissionId, duplicateSubmission: true };
      }
      const patientIds = [...new Set([
        ...(input.patientId ? [input.patientId] : []),
        ...(input.patientIds ?? []),
        ...input.services.map((line) => line.patientId).filter(Boolean),
        ...input.products.map((line) => line.patientId).filter(Boolean),
      ])];
      let patients = { rows: [] };
      let ownerId = null;
      if (input.contextType === 'patient') {
        patients = await client.query(
          `SELECT p.patient_id, p.owner_id, o.phone AS owner_phone,
                  o.email AS owner_email
             FROM patients p
             JOIN owners o ON o.owner_id=p.owner_id AND o.clinic_id=p.clinic_id
            WHERE p.clinic_id=$1 AND p.patient_id = ANY($2::uuid[])
              AND p.status ILIKE $3 AND p.deleted_at IS NULL
              AND o.deleted_at IS NULL`,
          [request.auth.clinicId, patientIds, 'active'],
        );
        if (patients.rows.length !== patientIds.length) {
          return reply.code(404).send({ error: 'patient_not_found', message: 'One or more selected active patients were not found in this clinic.' });
        }
        if (!patientsShareBillingOwner(patients.rows)) {
          return reply.code(409).send({ error: 'invoice_owner_mismatch', message: 'All animals on one invoice must belong to the same client.' });
        }
        ownerId = patients.rows.find((row) => row.patient_id === input.patientId)?.owner_id ?? null;
      } else {
        const validFarm = await upsertFarmInvoiceContext(
          client,
          request.auth.clinicId,
          request.auth.userId,
          input.farm,
        );
        if (!validFarm) {
          return reply.code(404).send({ error: 'farm_not_found', message: 'The selected farm records are not available in this clinic.' });
        }
      }
      const allowedPatients = new Set(patients.rows.map((row) => row.patient_id));
      if (input.contextType === 'patient'
          && [...input.services, ...input.products].some((line) => line.patientId && !allowedPatients.has(line.patientId))) {
        return reply.code(409).send({ error: 'invoice_patient_mismatch', message: 'An invoice item references an animal outside this invoice.' });
      }
      const farmTreatments = new Map(
        (input.farm?.treatments ?? []).map((item) => [item.treatmentRecordId, item]),
      );
      const serviceLines = input.services.map((line) => {
        const treatment = line.sourceTreatmentRecordId
          ? farmTreatments.get(line.sourceTreatmentRecordId)
          : null;
        if (line.sourceTreatmentRecordId && !treatment) {
          const error = new Error('A selected farm treatment is not part of this visit.');
          error.code = 'farm_treatment_mismatch';
          throw error;
        }
        const quantity = Number(line.quantity);
        const unitPrice = treatment
          ? Number(treatment.billableAmount)
          : line.unitPrice == null
            ? Number(line.amount) / quantity
            : Number(line.unitPrice);
        const lineTotal = Number((quantity * unitPrice).toFixed(2));
        return {
          ...line,
          quantity,
          unitPrice,
          lineTotal,
          farmUnitId: treatment?.farmUnitId ?? line.farmUnitId ?? null,
          costSnapshot: treatment?.costSnapshot ?? line.costSnapshot ?? null,
          lineType: 'Service',
        };
      });
      const preparedProducts = await prepareProductLines(client, request.auth.clinicId, input.products);
      if (preparedProducts.error) {
        const error = new Error('A selected inventory product is unavailable for billing.');
        error.code = preparedProducts.error;
        throw error;
      }
      if (input.contextType === 'farm_visit') {
        const referencedFarmUnitIds = [...new Set([
          ...serviceLines.map((line) => line.farmUnitId).filter(Boolean),
          ...preparedProducts.lines.map((line) => line.farmUnitId).filter(Boolean),
        ])];
        if (referencedFarmUnitIds.length > 0) {
          const matchingUnits = await client.query(
            `SELECT farm_unit_id
               FROM farm_units
              WHERE clinic_id=$1 AND farm_id=$2
                AND farm_unit_id = ANY($3::uuid[])`,
            [request.auth.clinicId, input.farm.farmId, referencedFarmUnitIds],
          );
          if (matchingUnits.rows.length !== referencedFarmUnitIds.length) {
            return reply.code(409).send({
              error: 'farm_unit_mismatch',
              message: 'An invoice item references a unit outside the selected farm.',
            });
          }
        }
      }
      const lines = [
        ...serviceLines,
        ...preparedProducts.lines.map((line) => ({ ...line, lineType: 'Product' })),
      ];
      const itemizedTotal = Number(lines.reduce((sum, line) => sum + line.lineTotal, 0).toFixed(2));
      if (itemizedTotal > input.total + 0.01) {
        return reply.code(400).send({ error: 'invoice_total_mismatch', message: 'Invoice items exceed the submitted total.' });
      }
      // Older app releases submitted consultation/home fees only in the total.
      // Preserve that compatibility as one general line while new clients send
      // every charge explicitly.
      if (input.total - itemizedTotal > 0.01) {
        lines.push({
          description: 'General clinic services', patientId: null,
          quantity: 1, unitPrice: Number((input.total - itemizedTotal).toFixed(2)),
          lineTotal: Number((input.total - itemizedTotal).toFixed(2)),
          lineType: 'Service',
        });
      }
      const authoritativeTotal = Number(lines.reduce((sum, line) => sum + line.lineTotal, 0).toFixed(2));
      const invoiceNumber =
        `INV-${Date.now()}-${input.submissionId.slice(0, 8).toUpperCase()}`;
      const paid = input.status === 'Paid' ? authoritativeTotal : 0;
      const inserted = await client.query(
        `INSERT INTO invoices
           (clinic_id, owner_id, patient_id, invoice_number, status, subtotal,
             tax, discount, total, amount_paid, balance, issued_at, submission_id,
             context_type, farm_id, farm_visit_date, client_name_snapshot,
             client_phone_snapshot)
          VALUES ($1,$2,$3,$4,$5,$6,0,0,$7,$8,$9,now(),$10,$11,$12,$13,$14,$15)
          RETURNING invoice_id, invoice_number, patient_id, status, subtotal,
                    total, amount_paid, balance, issued_at, context_type, farm_id`,
         [request.auth.clinicId,
          ownerId,
          input.patientId ?? null,
          invoiceNumber, input.status, authoritativeTotal, authoritativeTotal, paid,
          authoritativeTotal - paid, input.submissionId, input.contextType,
          input.farm?.farmId ?? null, input.farm?.visitDate ?? null,
          input.farm?.clientName ?? null, input.farm?.clientPhone ?? null],
      );
      for (const line of lines) {
        await client.query(
          `INSERT INTO invoice_line_items
             (clinic_id, invoice_id, patient_id, line_type, description,
              quantity, unit_price, line_total, farm_unit_id,
              source_treatment_record_id, inventory_product_id, product_unit_id,
              display_unit_snapshot, conversion_to_base_snapshot,
              base_quantity_snapshot, unit_cost_snapshot, product_name_snapshot,
              batch_number_snapshot, expiry_date_snapshot)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)`,
          [request.auth.clinicId, inserted.rows[0].invoice_id,
            line.patientId ?? null, line.lineType, line.description, line.quantity,
            line.unitPrice, line.lineTotal, line.farmUnitId ?? null,
            line.sourceTreatmentRecordId ?? null, line.inventoryProductId ?? null,
            line.productUnitId ?? null, line.displayUnit ?? null,
            line.conversion ?? null, line.baseQuantity ?? null,
            line.unitCost ?? line.costSnapshot ?? null, line.productName ?? null,
            line.batchNumber ?? null, line.expiryDate ?? null],
        );
      }
      if (input.status !== 'Draft') {
        await deductInvoiceInventory(client, request.auth.clinicId, inserted.rows[0].invoice_id);
      }
      if (input.status === 'Paid' && authoritativeTotal > 0) {
        await client.query(
          `INSERT INTO payments (clinic_id, invoice_id, paid_at, amount, method)
           VALUES ($1,$2,now(),$3,'Clinic Billing')`,
          [request.auth.clinicId, inserted.rows[0].invoice_id, authoritativeTotal],
        );
      }
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Invoice',
        targetId: inserted.rows[0].invoice_id,
        action: input.status === 'Paid'
          ? 'billing.sale_recorded'
          : input.status === 'Unpaid'
            ? 'billing.invoice_issued'
            : 'billing.draft_created',
        newSummary: {
          contextType: input.contextType,
          patientId: input.patientId ?? null,
          patientIds,
          farmId: input.farm?.farmId ?? null,
          total: authoritativeTotal,
          lineCount: lines.length,
        },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { ...inserted.rows[0], submissionId: input.submissionId, duplicateSubmission: false, patientIds };
      });
    } catch (error) {
      if (error.code === 'insufficient_stock') {
        return reply.code(409).send({ error: error.code, message: error.message });
      }
      if (error.code === 'inventory_product_expired') {
        return reply.code(409).send({ error: error.code, message: 'An expired inventory product cannot be sold.' });
      }
      if (error.code === 'inventory_product_unavailable') {
        return reply.code(409).send({ error: error.code, message: 'A selected inventory product is unavailable.' });
      }
      if (error.code === 'farm_treatment_mismatch'
          || error.code === 'farm_unit_mismatch'
          || error.code === 'farm_population_mismatch') {
        return reply.code(409).send({ error: error.code, message: error.message });
      }
      if (error.code === '23505') {
        return reply.code(409).send({
          error: 'duplicate_invoice_source',
          message: 'This treatment or submission has already been invoiced.',
        });
      }
      throw error;
    }
  });

  app.get('/api/v1/invoices/:invoiceId', { preHandler: [authenticate, requirePermission(permissions.billingView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = z.object({ invoiceId: z.string().uuid() }).safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'The invoice identifier is invalid.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const invoice = await client.query(
        `SELECT i.*, o.full_name AS owner_name, o.phone AS owner_phone,
                o.email AS owner_email, f.name AS farm_name,
                COALESCE(i.client_name_snapshot, f.client_name) AS farm_client_name,
                COALESCE(i.client_phone_snapshot, f.client_phone) AS farm_client_phone
           FROM invoices i
           LEFT JOIN owners o ON o.owner_id=i.owner_id
           LEFT JOIN farms f ON f.farm_id=i.farm_id AND f.clinic_id=i.clinic_id
          WHERE i.clinic_id=$1 AND i.invoice_id=$2`,
        [request.auth.clinicId, parsed.data.invoiceId],
      );
      if (!invoice.rows[0]) return reply.code(404).send({ error: 'not_found', message: 'The invoice was not found in this clinic.' });
      const lines = await client.query(
        `SELECT l.invoice_line_item_id, l.patient_id, l.line_type,
                 l.description, l.quantity, l.unit_price, l.line_total,
                 l.farm_unit_id, l.source_treatment_record_id,
                 l.inventory_product_id, l.product_unit_id,
                 l.display_unit_snapshot, l.conversion_to_base_snapshot,
                 l.base_quantity_snapshot, l.unit_cost_snapshot,
                 l.product_name_snapshot, l.batch_number_snapshot,
                 l.expiry_date_snapshot, u.name AS farm_unit_name,
                 p.name AS patient_name, p.hospital_number
           FROM invoice_line_items l
           LEFT JOIN patients p ON p.patient_id=l.patient_id AND p.clinic_id=l.clinic_id
           LEFT JOIN farm_units u ON u.farm_unit_id=l.farm_unit_id AND u.clinic_id=l.clinic_id
          WHERE l.clinic_id=$1 AND l.invoice_id=$2
          ORDER BY p.name NULLS LAST, l.created_at, l.invoice_line_item_id`,
        [request.auth.clinicId, parsed.data.invoiceId],
      );
      const payments = await client.query(
        `SELECT payment_id, amount, method, paid_at, reference
           FROM payments
          WHERE clinic_id=$1 AND invoice_id=$2
          ORDER BY paid_at DESC, payment_id DESC`,
        [request.auth.clinicId, parsed.data.invoiceId],
      );
      return { invoice: invoice.rows[0], lineItems: lines.rows, payments: payments.rows };
    });
  });

  app.post('/api/v1/invoices/:invoiceId/payments', { preHandler: [authenticate, requirePermission(permissions.billingRecordPayment)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = z.object({ invoiceId: z.string().uuid() }).safeParse(request.params);
    const parsed = recordInvoicePaymentSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the payment information.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const input = parsed.data;
      const duplicate = await client.query(
        `SELECT p.payment_id, p.invoice_id, p.amount, p.method, p.paid_at, p.reference,
                i.status AS invoice_status, i.amount_paid, i.balance
           FROM payments p JOIN invoices i ON i.invoice_id=p.invoice_id AND i.clinic_id=p.clinic_id
          WHERE p.clinic_id=$1 AND p.invoice_id=$2 AND p.submission_id=$3`,
        [request.auth.clinicId, params.data.invoiceId, input.submissionId],
      );
      if (duplicate.rows[0]) return { payment: duplicate.rows[0], duplicateSubmission: true };
      const invoice = await client.query(
        `SELECT invoice_id, invoice_number, status, total, amount_paid, balance
           FROM invoices WHERE clinic_id=$1 AND invoice_id=$2 FOR UPDATE`,
        [request.auth.clinicId, params.data.invoiceId],
      );
      if (!invoice.rows[0]) return reply.code(404).send({ error: 'not_found', message: 'The invoice was not found in this clinic.' });
      if (['Cancelled', 'Voided', 'Refunded'].includes(invoice.rows[0].status)) {
        return reply.code(409).send({ error: 'invoice_not_payable', message: 'This invoice cannot accept a payment.' });
      }
      const outstanding = Number(invoice.rows[0].balance);
      if (input.amount > outstanding + 0.001) {
        return reply.code(409).send({ error: 'payment_exceeds_balance', message: 'The payment exceeds the outstanding invoice balance.' });
      }
      const payment = await client.query(
        `INSERT INTO payments
           (clinic_id, invoice_id, paid_at, amount, method, reference,
            recorded_by, submission_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         RETURNING payment_id, invoice_id, amount, method, paid_at, reference`,
        [request.auth.clinicId, params.data.invoiceId, input.paidAt, input.amount,
          input.method, input.reference || null, request.auth.userId, input.submissionId],
      );
      const amountPaid = Number(invoice.rows[0].amount_paid) + input.amount;
      const balance = Math.max(0, Number(invoice.rows[0].total) - amountPaid);
      const status = balance <= 0.001 ? 'Paid' : 'Partially paid';
      const updated = await client.query(
        `UPDATE invoices SET status=$3, amount_paid=$4, balance=$5
          WHERE clinic_id=$1 AND invoice_id=$2
          RETURNING invoice_id, invoice_number, status, total, amount_paid, balance, issued_at`,
        [request.auth.clinicId, params.data.invoiceId, status, amountPaid, balance],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Invoice',
        targetId: params.data.invoiceId,
        action: 'billing.payment_recorded',
        previousSummary: { status: invoice.rows[0].status, amountPaid: Number(invoice.rows[0].amount_paid), balance: outstanding },
        newSummary: { status, amountPaid, balance, method: input.method },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { payment: payment.rows[0], invoice: updated.rows[0], duplicateSubmission: false };
    });
  });

  app.post('/api/v1/inventory/products', { preHandler: [authenticate, requirePermission(permissions.inventoryCreate)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = createInventoryItemSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the inventory item information.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const input = parsed.data;
      const baseUnitLabel = input.baseUnitLabel ?? 'unit';
      const existing = await client.query(
        `SELECT ${inventoryList.select}
           FROM inventory_products i
          WHERE i.clinic_id = $1 AND i.submission_id = $2 AND i.deleted_at IS NULL`,
        [request.auth.clinicId, input.submissionId],
      );
      if (existing.rows[0]) {
        return { item: await inventoryResponseWithPhoto(app, existing.rows[0]), submissionId: input.submissionId, duplicateSubmission: true };
      }
       const inserted = await client.query(
         `INSERT INTO inventory_products
            (clinic_id, name, generic_name, brand_name, manufacturer, supplier,
             sku, barcode, short_description, detailed_description, dosage_form,
             pack_size, category, category_key, subcategory, subcategory_key,
             batch_number, expiry_date,
             purchase_price, selling_price, quantity, reorder_level, status,
             submission_id, base_unit_label, active_ingredient, dosage_and_route,
             withdrawal_meat, withdrawal_milk, withdrawal_eggs, withdrawal_other,
             warnings, contraindications, adverse_effects, storage_conditions,
             public_display_name, available_to_public, is_sellable, is_archived,
             created_at, updated_at)
          VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,
                  $17,$18,$19,$20,$21,$22,'Active',$23,$24,$25,$26,$27,$28,
                  $29,$30,$31,$32,$33,$34,$35,$36,$37,$38,now(),now())
         ON CONFLICT (clinic_id, submission_id)
           WHERE submission_id IS NOT NULL
         DO NOTHING
          RETURNING *`,
        [request.auth.clinicId, input.name, input.genericName ?? null,
          input.brandName ?? null, input.manufacturer ?? null,
          input.supplier ?? null, input.sku ?? null, input.barcode ?? null,
          input.shortDescription ?? null, input.detailedDescription ?? null,
          input.dosageForm ?? null, input.packSize ?? null, input.categoryName,
          input.categoryId, input.subcategoryName ?? null,
          input.subcategoryId ?? null, input.batchNumber ?? null,
          input.expiryDate ?? null, input.purchasePrice, input.sellingPrice,
          input.quantity, input.reorderLevel, input.submissionId, baseUnitLabel,
          input.activeIngredient ?? null, input.dosageAndRoute ?? null,
          input.withdrawalMeat ?? null, input.withdrawalMilk ?? null,
          input.withdrawalEggs ?? null, input.withdrawalOther ?? null,
          input.warnings ?? null, input.contraindications ?? null,
          input.adverseEffects ?? null, input.storageConditions ?? null,
          input.publicDisplayName ?? null, input.availableToPublic ?? false,
          input.isSellable ?? true, input.isArchived ?? false],
       );
      if (!inserted.rows[0]) {
        const duplicate = await client.query(
          `SELECT ${inventoryList.select}
             FROM inventory_products i
            WHERE i.clinic_id = $1 AND i.submission_id = $2`,
          [request.auth.clinicId, input.submissionId],
        );
        return {
          item: await inventoryResponseWithPhoto(app, duplicate.rows[0]),
          submissionId: input.submissionId,
          duplicateSubmission: true,
        };
      }
       if (input.quantity > 0) {
        await client.query(
          `INSERT INTO stock_movements
             (clinic_id, inventory_product_id, occurred_at, movement_type,
              quantity_delta, reference)
           VALUES ($1,$2,now(),'Opening Balance',$3,'Inventory item created')`,
          [request.auth.clinicId, inserted.rows[0].inventory_product_id, input.quantity],
        );
       }
       await client.query(
         `INSERT INTO inventory_product_units
            (clinic_id, inventory_product_id, unit_label, is_base_unit,
             conversion_to_base, selling_price)
          VALUES ($1,$2,$3,true,1,$4)`,
         [request.auth.clinicId, inserted.rows[0].inventory_product_id,
           baseUnitLabel, input.sellingPrice],
       );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'InventoryProduct',
        targetId: inserted.rows[0].inventory_product_id,
        action: 'inventory.item_created',
        newSummary: { name: input.name, categoryId: input.categoryId, quantity: input.quantity },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      const item = await inventoryProductWithUnits(
        client,
        request.auth.clinicId,
        inserted.rows[0].inventory_product_id,
      );
      return { item: await inventoryResponseWithPhoto(app, item), submissionId: input.submissionId, duplicateSubmission: false };
    });
  });

  app.patch('/api/v1/inventory/products/:inventoryProductId', { preHandler: [authenticate, requirePermission(permissions.inventoryEdit)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = inventoryUuidSchema.safeParse(request.params);
    const parsed = updateInventoryItemSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the inventory item information.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const current = await client.query(
        `SELECT *
           FROM inventory_products
          WHERE clinic_id = $1 AND inventory_product_id = $2 AND deleted_at IS NULL
          FOR UPDATE`,
        [request.auth.clinicId, params.data.inventoryProductId],
      );
      if (!current.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The inventory item was not found in this clinic.' });
      }
      const input = parsed.data;
      const previous = current.rows[0];
      if (input.revision != null && Number(previous.revision) !== input.revision) {
        return reply.code(409).send({ error: 'revision_conflict', message: 'This inventory item changed on another device. Refresh and try again.' });
      }
      const keep = (inputKey, column) => Object.hasOwn(input, inputKey)
        ? input[inputKey]
        : previous[column];
      const baseUnitLabel = input.baseUnitLabel ?? previous.base_unit_label ?? 'unit';
      const updates = [
        ['name', input.name],
        ['generic_name', keep('genericName', 'generic_name')],
        ['brand_name', keep('brandName', 'brand_name')],
        ['manufacturer', keep('manufacturer', 'manufacturer')],
        ['supplier', keep('supplier', 'supplier')],
        ['sku', keep('sku', 'sku')],
        ['barcode', keep('barcode', 'barcode')],
        ['short_description', keep('shortDescription', 'short_description')],
        ['detailed_description', keep('detailedDescription', 'detailed_description')],
        ['dosage_form', keep('dosageForm', 'dosage_form')],
        ['pack_size', keep('packSize', 'pack_size')],
        ['category', input.categoryName],
        ['category_key', input.categoryId],
        ['subcategory', keep('subcategoryName', 'subcategory')],
        ['subcategory_key', keep('subcategoryId', 'subcategory_key')],
        ['batch_number', input.batchNumber ?? null],
        ['expiry_date', input.expiryDate ?? null],
        ['purchase_price', input.purchasePrice],
        ['selling_price', input.sellingPrice],
        ['quantity', input.quantity],
        ['reorder_level', input.reorderLevel],
        ['base_unit_label', baseUnitLabel],
        ['active_ingredient', keep('activeIngredient', 'active_ingredient')],
        ['dosage_and_route', keep('dosageAndRoute', 'dosage_and_route')],
        ['withdrawal_meat', keep('withdrawalMeat', 'withdrawal_meat')],
        ['withdrawal_milk', keep('withdrawalMilk', 'withdrawal_milk')],
        ['withdrawal_eggs', keep('withdrawalEggs', 'withdrawal_eggs')],
        ['withdrawal_other', keep('withdrawalOther', 'withdrawal_other')],
        ['warnings', keep('warnings', 'warnings')],
        ['contraindications', keep('contraindications', 'contraindications')],
        ['adverse_effects', keep('adverseEffects', 'adverse_effects')],
        ['storage_conditions', keep('storageConditions', 'storage_conditions')],
        ['public_display_name', keep('publicDisplayName', 'public_display_name')],
        ['available_to_public', keep('availableToPublic', 'available_to_public')],
        ['is_sellable', keep('isSellable', 'is_sellable')],
        ['is_archived', keep('isArchived', 'is_archived')],
      ];
      const updateAssignments = updates
        .map(([column], index) => `${column} = $${index + 1}`)
        .join(', ');
      const updated = await client.query(
        `UPDATE inventory_products
            SET ${updateAssignments}, updated_at = now(),
                revision = revision + 1
          WHERE clinic_id = $${updates.length + 1}
            AND inventory_product_id = $${updates.length + 2}
          RETURNING *`,
        [
          ...updates.map(([, value]) => value),
          request.auth.clinicId,
          params.data.inventoryProductId,
        ],
       );
       await client.query(
         `UPDATE inventory_product_units
             SET unit_label=$1, selling_price=$2, updated_at=now(), revision=revision+1
           WHERE clinic_id=$3 AND inventory_product_id=$4 AND is_base_unit=true`,
         [baseUnitLabel, input.sellingPrice, request.auth.clinicId,
           params.data.inventoryProductId],
       );
      const quantityDelta = input.quantity - Number(previous.quantity);
      if (quantityDelta !== 0) {
        await client.query(
          `INSERT INTO stock_movements
             (clinic_id, inventory_product_id, occurred_at, movement_type,
              quantity_delta, reference)
           VALUES ($1,$2,now(),'Manual Adjustment',$3,'Inventory item edited')`,
          [request.auth.clinicId, params.data.inventoryProductId, quantityDelta],
        );
      }
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'InventoryProduct',
        targetId: params.data.inventoryProductId,
        action: 'inventory.item_updated',
        previousSummary: { name: previous.name, categoryId: previous.category_key, quantity: Number(previous.quantity), revision: Number(previous.revision) },
        newSummary: { name: input.name, categoryId: input.categoryId, quantity: input.quantity, revision: Number(updated.rows[0].revision) },
        sessionId: request.auth.sessionId,
      });
      const item = await inventoryProductWithUnits(
        client,
        request.auth.clinicId,
        params.data.inventoryProductId,
      );
      return { item: await inventoryResponseWithPhoto(app, item) };
    });
  });

  app.post('/api/v1/inventory/products/:inventoryProductId/add-stock', { preHandler: [authenticate, requirePermission(permissions.inventoryAdjust)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = inventoryUuidSchema.safeParse(request.params);
    const parsed = addInventoryStockSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Enter a valid quantity to add.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const current = await client.query(
        `SELECT inventory_product_id, name, quantity, batch_number, expiry_date,
                purchase_price
           FROM inventory_products
          WHERE clinic_id=$1 AND inventory_product_id=$2
            AND deleted_at IS NULL AND is_archived=false
          FOR UPDATE`,
        [request.auth.clinicId, params.data.inventoryProductId],
      );
      if (!current.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The inventory item was not found in this clinic.' });
      }
      const input = parsed.data;
      const before = Number(current.rows[0].quantity);
      const after = before + input.quantityToAdd;
      await client.query(
        `UPDATE inventory_products
            SET quantity=$3,
                batch_number=COALESCE($4, batch_number),
                expiry_date=COALESCE($5, expiry_date),
                purchase_price=COALESCE($6, purchase_price),
                updated_at=now(), revision=revision+1
          WHERE clinic_id=$1 AND inventory_product_id=$2`,
        [request.auth.clinicId, params.data.inventoryProductId, after,
          input.batchNumber ?? null, input.expiryDate ?? null,
          input.purchasePrice ?? null],
      );
      await client.query(
        `INSERT INTO stock_movements
           (clinic_id, inventory_product_id, occurred_at, movement_type,
            quantity_delta, reference)
         VALUES ($1,$2,now(),'Stock Added',$3,'Add Stock')`,
        [request.auth.clinicId, params.data.inventoryProductId, input.quantityToAdd],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'InventoryProduct',
        targetId: params.data.inventoryProductId,
        action: 'inventory.stock_added',
        previousSummary: { quantity: before },
        newSummary: { quantity: after, quantityAdded: input.quantityToAdd },
        sessionId: request.auth.sessionId,
      });
      const item = await inventoryProductWithUnits(
        client,
        request.auth.clinicId,
        params.data.inventoryProductId,
      );
      return {
        item: await inventoryResponseWithPhoto(app, item),
        quantityBefore: before,
        quantityAdded: input.quantityToAdd,
        quantityAfter: after,
      };
    });
  });

  app.post('/api/v1/inventory/products/:inventoryProductId/photo', { preHandler: [authenticate, requirePermission(permissions.inventoryEdit)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = inventoryUuidSchema.safeParse(request.params);
    const parsed = inventoryPhotoSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'invalid_inventory_photo', message: 'Choose a JPEG or PNG image.' });
    }
    const bytes = Buffer.from(parsed.data.data, 'base64');
    try {
      return await withTenantTransaction(app.pool, request.auth, async (client) => {
        const current = await client.query(
          `SELECT image_path
             FROM inventory_products
            WHERE clinic_id=$1 AND inventory_product_id=$2
              AND deleted_at IS NULL
            FOR UPDATE`,
          [request.auth.clinicId, params.data.inventoryProductId],
        );
        if (!current.rows[0]) {
          return reply.code(404).send({ error: 'not_found', message: 'The inventory item was not found in this clinic.' });
        }
        const path = await app.profilePhotoStorage.uploadInventoryPhoto({
          clinicId: request.auth.clinicId,
          inventoryProductId: params.data.inventoryProductId,
          contentType: parsed.data.contentType,
          bytes,
        });
        await client.query(
          `UPDATE inventory_products
              SET image_path=$1, updated_at=now(), revision=revision+1
            WHERE clinic_id=$2 AND inventory_product_id=$3`,
          [path, request.auth.clinicId, params.data.inventoryProductId],
        );
        const item = await inventoryProductWithUnits(
          client,
          request.auth.clinicId,
          params.data.inventoryProductId,
        );
        await writeAudit(client, {
          clinicId: request.auth.clinicId,
          actingUserId: request.auth.userId,
          targetType: 'InventoryProduct',
          targetId: params.data.inventoryProductId,
          action: 'inventory.photo_updated',
          newSummary: { photoUpdated: true },
          sessionId: request.auth.sessionId,
        });
        const previousPath = current.rows[0].image_path;
        if (previousPath && previousPath !== path) {
          await app.profilePhotoStorage.remove(previousPath);
        }
        return { item: await inventoryResponseWithPhoto(app, item) };
      });
    } catch (error) {
      return reply.code(error.statusCode ?? 500).send({
        error: error.code ?? 'inventory_photo_upload_failed',
        message: error.statusCode
          ? error.message
          : 'The inventory image could not be uploaded.',
      });
    }
  });

  app.get('/api/v1/inventory/products/:inventoryProductId/units', { preHandler: [authenticate, requirePermission(permissions.inventoryView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = inventoryUuidSchema.safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'The inventory item identifier is invalid.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const product = await inventoryProductWithUnits(
        client,
        request.auth.clinicId,
        params.data.inventoryProductId,
      );
      if (!product) {
        return reply.code(404).send({ error: 'not_found', message: 'The inventory item was not found in this clinic.' });
      }
      return { productUnits: product.product_units ?? [] };
    });
  });

  app.put('/api/v1/inventory/products/:inventoryProductId/units', { preHandler: [authenticate, requirePermission(permissions.inventoryEdit)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = inventoryUuidSchema.safeParse(request.params);
    const parsed = replaceProductUnitsSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the product unit configuration.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const product = await client.query(
        `SELECT inventory_product_id, name
           FROM inventory_products
          WHERE clinic_id=$1 AND inventory_product_id=$2
            AND deleted_at IS NULL
          FOR UPDATE`,
        [request.auth.clinicId, params.data.inventoryProductId],
      );
      if (!product.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The inventory item was not found in this clinic.' });
      }

      const suppliedIds = parsed.data.units
        .map((unit) => unit.productUnitId)
        .filter(Boolean);
      if (suppliedIds.length > 0) {
        const owned = await client.query(
          `SELECT product_unit_id
             FROM inventory_product_units
            WHERE clinic_id=$1 AND inventory_product_id=$2
              AND product_unit_id = ANY($3::uuid[])`,
          [request.auth.clinicId, params.data.inventoryProductId, suppliedIds],
        );
        if (owned.rowCount !== suppliedIds.length) {
          return reply.code(409).send({
            error: 'product_unit_conflict',
            message: 'One or more product units are stale or belong to another inventory item.',
          });
        }
      }

      await client.query(
        `DELETE FROM inventory_product_units
          WHERE clinic_id=$1 AND inventory_product_id=$2
            AND NOT (product_unit_id = ANY($3::uuid[]))`,
        [request.auth.clinicId, params.data.inventoryProductId, suppliedIds],
      );
      await client.query(
        `UPDATE inventory_product_units
            SET is_base_unit=false
          WHERE clinic_id=$1 AND inventory_product_id=$2 AND is_base_unit=true`,
        [request.auth.clinicId, params.data.inventoryProductId],
      );
      for (const unit of parsed.data.units) {
        if (unit.productUnitId) {
          await client.query(
            `UPDATE inventory_product_units
                SET unit_label=$1, is_base_unit=$2, conversion_to_base=$3,
                    selling_price=$4, updated_at=now(), revision=revision+1
              WHERE clinic_id=$5 AND inventory_product_id=$6 AND product_unit_id=$7`,
            [unit.unitLabel, unit.isBaseUnit, unit.conversionToBase, unit.sellingPrice,
              request.auth.clinicId, params.data.inventoryProductId, unit.productUnitId],
          );
        } else {
          await client.query(
            `INSERT INTO inventory_product_units
               (clinic_id, inventory_product_id, unit_label, is_base_unit,
                conversion_to_base, selling_price)
             VALUES ($1,$2,$3,$4,$5,$6)`,
            [request.auth.clinicId, params.data.inventoryProductId, unit.unitLabel,
              unit.isBaseUnit, unit.conversionToBase, unit.sellingPrice],
          );
        }
      }
      const baseUnit = parsed.data.units.find((unit) => unit.isBaseUnit);
      await client.query(
        `UPDATE inventory_products
            SET base_unit_label=$1, selling_price=$2,
                updated_at=now(), revision=revision+1
          WHERE clinic_id=$3 AND inventory_product_id=$4`,
        [baseUnit.unitLabel, baseUnit.sellingPrice, request.auth.clinicId,
          params.data.inventoryProductId],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'InventoryProduct',
        targetId: params.data.inventoryProductId,
        action: 'inventory.product_units_replaced',
        newSummary: { unitCount: parsed.data.units.length, baseUnit: baseUnit.unitLabel },
        sessionId: request.auth.sessionId,
      });
      const refreshed = await inventoryProductWithUnits(
        client,
        request.auth.clinicId,
        params.data.inventoryProductId,
      );
      return { item: await inventoryResponseWithPhoto(app, refreshed) };
    });
  });

  app.post('/api/v1/inventory/products/:inventoryProductId/reorder-requests', { preHandler: [authenticate, requirePermission(permissions.inventoryAdjust)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = inventoryUuidSchema.safeParse(request.params);
    const parsed = createReorderRequestSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'Please review the reorder request.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const product = await client.query(
        `SELECT inventory_product_id, name, supplier, base_unit_label
           FROM inventory_products
          WHERE clinic_id=$1 AND inventory_product_id=$2
            AND deleted_at IS NULL AND is_archived=false`,
        [request.auth.clinicId, params.data.inventoryProductId],
      );
      if (!product.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The inventory item was not found in this clinic.' });
      }
      if (!product.rows[0].supplier?.trim()) {
        return reply.code(409).send({ error: 'supplier_required', message: 'Add a supplier to this item before requesting a reorder.' });
      }
      let requestedUnit = product.rows[0].base_unit_label;
      if (parsed.data.productUnitId) {
        const unit = await client.query(
          `SELECT unit_label
             FROM inventory_product_units
            WHERE clinic_id=$1 AND inventory_product_id=$2 AND product_unit_id=$3`,
          [request.auth.clinicId, params.data.inventoryProductId,
            parsed.data.productUnitId],
        );
        if (!unit.rows[0]) {
          return reply.code(409).send({ error: 'product_unit_conflict', message: 'The selected product unit is unavailable.' });
        }
        requestedUnit = unit.rows[0].unit_label;
      }
      const inserted = await client.query(
        `INSERT INTO inventory_reorder_requests
           (clinic_id, inventory_product_id, product_unit_id, supplier_snapshot,
            requested_quantity, requested_unit_snapshot, requested_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         RETURNING *`,
        [request.auth.clinicId, params.data.inventoryProductId,
          parsed.data.productUnitId ?? null, product.rows[0].supplier,
          parsed.data.requestedQuantity, requestedUnit, request.auth.userId],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'InventoryReorderRequest',
        targetId: inserted.rows[0].reorder_request_id,
        action: 'inventory.reorder_requested',
        newSummary: {
          product: product.rows[0].name,
          quantity: parsed.data.requestedQuantity,
          unit: requestedUnit,
          supplier: product.rows[0].supplier,
        },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { reorderRequest: inserted.rows[0] };
    });
  });

  app.get('/api/v1/inventory/products/:inventoryProductId/related', { preHandler: [authenticate, requirePermission(permissions.inventoryView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = inventoryUuidSchema.safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: 'validation_error', message: 'The inventory item identifier is invalid.' });
    }
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const current = await client.query(
        `SELECT supplier, manufacturer, category_key
           FROM inventory_products
          WHERE clinic_id=$1 AND inventory_product_id=$2 AND deleted_at IS NULL`,
        [request.auth.clinicId, params.data.inventoryProductId],
      );
      if (!current.rows[0]) {
        return reply.code(404).send({ error: 'not_found', message: 'The inventory item was not found in this clinic.' });
      }
      const row = current.rows[0];
      const related = await client.query(
        `SELECT ${inventoryList.select}
           FROM inventory_products i
          WHERE i.clinic_id=$1 AND i.inventory_product_id<>$2
            AND i.deleted_at IS NULL AND i.is_archived=false
            AND (
              ($3::text IS NOT NULL AND lower(i.supplier)=lower($3)) OR
              ($4::text IS NOT NULL AND lower(i.manufacturer)=lower($4)) OR
              i.category_key=$5
            )
          ORDER BY
            CASE WHEN $3::text IS NOT NULL AND lower(i.supplier)=lower($3) THEN 0 ELSE 1 END,
            lower(i.name)
          LIMIT 20`,
        [request.auth.clinicId, params.data.inventoryProductId,
          row.supplier ?? null, row.manufacturer ?? null, row.category_key],
      );
      return {
        items: await Promise.all(
          related.rows.map((item) => inventoryResponseWithPhoto(app, item)),
        ),
      };
    });
  });

  app.get('/api/v1/inventory/products', { preHandler: [authenticate, requirePermission(permissions.inventoryView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const query = parsePage(request, reply);
    if (!query) return undefined;
    const result = await paged(app, request, inventoryList, query);
    return {
      ...result,
      items: await Promise.all(
        result.items.map((item) => inventoryResponseWithPhoto(app, item)),
      ),
    };
  });
  app.get('/api/v1/inventory/movements', { preHandler: [authenticate, requirePermission(permissions.inventoryView)] }, tenantList(movementsList));
  app.get('/api/v1/billing/revenue-summary', {
    preHandler: [authenticate, requirePermission(permissions.billingHistory)],
  }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = revenueSummaryQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'validation_error',
        message: 'The revenue date range is invalid.',
      });
    }
    return withTenantTransaction(app.pool, request.auth, (client) =>
      loadRevenueSummary(client, {
        clinicId: request.auth.clinicId,
        from: parsed.data.from ?? null,
        to: parsed.data.to ?? null,
      }));
  });
  app.get('/api/v1/billing/revenue-drilldown', {
    preHandler: [authenticate, requirePermission(permissions.billingHistory)],
  }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = revenueDrilldownQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'validation_error',
        message: 'The revenue drill-down request is invalid.',
      });
    }
    return withTenantTransaction(app.pool, request.auth, (client) =>
      loadRevenueDrilldown(client, {
        clinicId: request.auth.clinicId,
        from: parsed.data.from ?? null,
        to: parsed.data.to ?? null,
        metric: parsed.data.metric,
        page: parsed.data.page,
        pageSize: parsed.data.pageSize,
      }));
  });
  app.get('/api/v1/invoices', { preHandler: [authenticate, requirePermission(permissions.billingView)] }, tenantList(invoiceList));
  app.get('/api/v1/payments', { preHandler: [authenticate, requirePermission(permissions.billingView)] }, tenantList(paymentList));
  app.get('/api/v1/media', { preHandler: [authenticate, requirePermission(permissions.mediaView)] }, tenantList(mediaList));

  app.get('/api/v1/activity', { preHandler: [authenticate, requirePermission(permissions.dashboardView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const query = parsePage(request, reply);
    if (!query) return undefined;
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const offset = (query.page - 1) * query.pageSize;
      const values = [
        request.auth.clinicId,
        query.search ?? null,
        `%${query.search ?? ''}%`,
        query.module ?? null,
        query.from ?? null,
        query.to ?? null,
      ];
      const where = `($2::text IS NULL OR activity.title ILIKE $3 OR activity.summary ILIKE $3)
        AND ($4::text IS NULL OR lower(activity.module) = lower($4))
        AND ($5::timestamptz IS NULL OR activity.occurred_at >= $5)
        AND ($6::timestamptz IS NULL OR activity.occurred_at < $6)`;
      const [rows, count] = await Promise.all([
        client.query(
          `SELECT * FROM (${clinicActivityUnionSql}) activity
            WHERE ${where}
            ORDER BY activity.occurred_at DESC
            LIMIT $7 OFFSET $8`,
          [...values, query.pageSize, offset],
        ),
        client.query(
          `SELECT count(*)::int AS total FROM (${clinicActivityUnionSql}) activity
            WHERE ${where}`,
          values,
        ),
      ]);
      const total = count.rows[0].total;
      return {
        items: rows.rows,
        page: query.page,
        pageSize: query.pageSize,
        total,
        hasNextPage: offset + rows.rowCount < total,
      };
    });
  });

  app.get('/api/v1/reminders', { preHandler: [authenticate, requirePermission(permissions.dashboardView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const feed = await loadReminderFeed(client, request);
      const notificationIds = await syncReminderNotifications(client, request, [
        ...new Map([...feed.upcoming, ...feed.alerts].map((item) => [item.event_id, item])).values(),
      ]);
      await dismissObsoleteReminderNotifications(
        client, request, [...notificationIds.keys()],
      );
      return {
        upcoming: feed.upcoming.map((item) => ({
          ...item,
          notification_id: notificationIds.get(item.event_id)?.notification_id,
          notification_dismissed: notificationIds.get(item.event_id)?.dismissed_at != null,
        })),
        alerts: feed.alerts.map((item) => ({
          ...item,
          notification_id: notificationIds.get(item.event_id)?.notification_id,
          notification_dismissed: notificationIds.get(item.event_id)?.dismissed_at != null,
        })),
      };
    });
  });

  app.get('/api/v1/notifications', { preHandler: [authenticate, requirePermission(permissions.dashboardView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const query = parsePage(request, reply);
    if (!query) return undefined;
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const feed = await loadReminderFeed(client, request);
      const notificationIds = await syncReminderNotifications(client, request, [
        ...new Map([...feed.upcoming, ...feed.alerts].map((item) => [item.event_id, item])).values(),
      ]);
      await dismissObsoleteReminderNotifications(
        client, request, [...notificationIds.keys()],
      );
      const offset = (query.page - 1) * query.pageSize;
      const [rows, count] = await Promise.all([
        client.query(
          `SELECT notification_id,dedupe_key AS event_id,notification_type,title,body,priority,
                  related_entity_type,related_entity_id,patient_id,scheduled_at,
                  reminder_at,created_at,read_at
             FROM clinic_notifications
            WHERE clinic_id=$1 AND user_id=$2 AND dismissed_at IS NULL
            ORDER BY created_at DESC LIMIT $3 OFFSET $4`,
          [request.auth.clinicId, request.auth.userId, query.pageSize, offset],
        ),
        client.query(
          `SELECT count(*)::int AS total FROM clinic_notifications
            WHERE clinic_id=$1 AND user_id=$2 AND dismissed_at IS NULL`,
          [request.auth.clinicId, request.auth.userId],
        ),
      ]);
      return {
        items: rows.rows, page: query.page, pageSize: query.pageSize,
        total: count.rows[0].total,
        hasNextPage: offset + rows.rowCount < count.rows[0].total,
      };
    });
  });

  app.patch('/api/v1/notifications/:notificationId/read', { preHandler: [authenticate, requirePermission(permissions.dashboardView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = notificationUuidSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_failed' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const result = await client.query(
        `UPDATE clinic_notifications SET read_at=coalesce(read_at,now())
          WHERE notification_id=$1 AND clinic_id=$2 AND user_id=$3
          RETURNING notification_id,read_at`,
        [parsed.data.notificationId, request.auth.clinicId, request.auth.userId],
      );
      if (!result.rows[0]) return reply.code(404).send({ error: 'not_found' });
      return { notification: result.rows[0] };
    });
  });

  app.patch('/api/v1/notifications/:notificationId/dismiss', { preHandler: [authenticate, requirePermission(permissions.dashboardView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = notificationUuidSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_failed' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const result = await client.query(
        `UPDATE clinic_notifications SET dismissed_at=coalesce(dismissed_at,now())
          WHERE notification_id=$1 AND clinic_id=$2 AND user_id=$3
          RETURNING notification_id`,
        [parsed.data.notificationId, request.auth.clinicId, request.auth.userId],
      );
      if (!result.rows[0]) return reply.code(404).send({ error: 'not_found' });
      return { notification: result.rows[0] };
    });
  });

  app.get('/api/v1/dashboard/summary', { preHandler: [authenticate, requirePermission(permissions.dashboardView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const clinicId = request.auth.clinicId;
      const result = await client.query(`SELECT
        (SELECT count(*)::int FROM patients WHERE clinic_id=$1 AND deleted_at IS NULL) AS registered_patients,
        (SELECT count(*)::int FROM schedule_entries WHERE clinic_id=$1 AND scheduled_at >= date_trunc('day', now()) AND scheduled_at < date_trunc('day', now()) + interval '1 day') AS todays_schedule,
        (SELECT count(*)::int FROM consultations WHERE clinic_id=$1 AND status IN ('In Progress','Open')) AS active_consultations,
        (SELECT count(*)::int FROM vaccinations WHERE clinic_id=$1 AND next_due_at <= now() AND status <> 'Completed') AS vaccinations_due,
        (SELECT coalesce(sum(amount),0) FROM payments WHERE clinic_id=$1 AND paid_at >= date_trunc('month', now())) AS current_revenue,
        (SELECT count(*)::int FROM inventory_products WHERE clinic_id=$1 AND quantity <= reorder_level) AS low_stock,
        (SELECT count(*)::int FROM inventory_products WHERE clinic_id=$1 AND expiry_date < current_date) AS expired_products,
        (SELECT count(*)::int FROM hospitalizations WHERE clinic_id=$1 AND discharged_at IS NULL) AS active_hospitalizations,
        (SELECT count(*)::int FROM laboratory_reports WHERE clinic_id=$1 AND status NOT IN ('Reviewed','Cancelled')) AS pending_laboratory_reports,
        (SELECT coalesce(sum(balance),0) FROM invoices WHERE clinic_id=$1 AND balance > 0) AS outstanding_invoices`, [clinicId]);
      const [species, revenue, activity] = await Promise.all([
        client.query('SELECT species, count(*)::int AS count FROM patients WHERE clinic_id=$1 AND deleted_at IS NULL GROUP BY species ORDER BY count DESC LIMIT 8', [clinicId]),
        client.query(`SELECT to_char(date_trunc('month', paid_at), 'YYYY-MM') AS month, coalesce(sum(amount),0) AS revenue FROM payments WHERE clinic_id=$1 AND paid_at >= now() - interval '6 months' GROUP BY 1 ORDER BY 1`, [clinicId]),
        client.query(
          `SELECT type, module, related_entity_type, record_id, patient_id,
                  occurred_at, title, summary
             FROM (${clinicActivityUnionSql}) activity
            ORDER BY occurred_at DESC LIMIT 10`,
          [clinicId],
        ),
      ]);
      return { ...result.rows[0], speciesDistribution: species.rows, revenueTrend: revenue.rows, recentActivity: activity.rows };
    });
  });
}
