import { z } from 'zod';
import { withTenantTransaction } from '../database/pool.js';
import { authenticate, requirePermission } from '../middleware/auth.js';
import { hasPermission, permissions } from '../security/permissions.js';
import { writeAudit } from '../audit/audit-service.js';

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

export const createInvoiceSchema = z.object({
  submissionId: z.string().uuid(),
  patientId: z.string().uuid(),
  status: z.enum(['Draft', 'Paid']),
  subtotal: z.number().min(0).max(1000000000000),
  total: z.number().min(0).max(1000000000000),
  services: z.array(z.object({
    description: z.string().trim().min(1).max(500),
    amount: z.number().min(0).max(1000000000000),
  })).max(100).default([]),
});

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
  categoryId: z.string().trim().regex(/^[a-z0-9_]{2,80}$/),
  categoryName: z.string().trim().min(1).max(160),
  quantity: z.number().int().min(0).max(100000000),
  reorderLevel: z.number().int().min(0).max(100000000),
  batchNumber: z.string().trim().max(160).nullish(),
  expiryDate: z.string().date().nullish(),
  purchasePrice: z.number().min(0).max(1000000000000),
  sellingPrice: z.number().min(0).max(1000000000000),
};

export const createInventoryItemSchema = z.object({
  submissionId: z.string().uuid(),
  ...inventoryFields,
});

export const updateInventoryItemSchema = z.object({
  ...inventoryFields,
  revision: z.number().int().min(1).optional(),
});

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

function patientResponse(row) {
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
  };
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
           p.current_weight_kg, p.image_placeholder, p.registered_at, p.updated_at, p.revision,
           o.owner_id, o.full_name AS owner_name, o.phone AS owner_phone,
           o.email AS owner_email, o.address AS owner_address,
           o.city AS owner_city, o.state AS owner_state`,
  where: `p.clinic_id = $1 AND p.deleted_at IS NULL AND o.deleted_at IS NULL
          AND ($2::text IS NULL OR p.name ILIKE $3 OR p.hospital_number ILIKE $3 OR o.full_name ILIKE $3 OR o.phone ILIKE $3)
          AND ($4::text IS NULL OR p.status = $4)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`, query.status ?? null],
  order: (query) => orderBy(query.sort, query.direction, { name: 'p.name', hospitalNumber: 'p.hospital_number', registeredAt: 'p.registered_at', updatedAt: 'p.updated_at' }, 'p.registered_at'),
};

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
  select: 'i.inventory_product_id, i.name, i.generic_name, i.category, i.category_key, i.manufacturer, i.supplier, i.batch_number, i.expiry_date, i.purchase_price, i.selling_price, i.quantity, i.reorder_level, i.status, i.created_at, i.updated_at, i.revision',
  where: `i.clinic_id = $1 AND i.deleted_at IS NULL AND ($2::text IS NULL OR i.name ILIKE $3 OR i.generic_name ILIKE $3 OR i.batch_number ILIKE $3 OR i.category ILIKE $3)
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
  from: 'invoices i LEFT JOIN patients p ON p.patient_id = i.patient_id LEFT JOIN owners o ON o.owner_id = i.owner_id',
  select: 'i.invoice_id, i.invoice_number, i.status, i.subtotal, i.tax, i.discount, i.total, i.amount_paid, i.balance, i.issued_at, i.due_at, p.name AS patient_name, o.full_name AS owner_name',
  where: `i.clinic_id = $1 AND ($2::text IS NULL OR i.invoice_number ILIKE $3 OR p.name ILIKE $3 OR o.full_name ILIKE $3) AND ($4::text IS NULL OR i.status = $4) AND ($5::timestamptz IS NULL OR i.issued_at >= $5) AND ($6::timestamptz IS NULL OR i.issued_at <= $6)`,
  values: (query, auth) => [auth.clinicId, query.search ?? null, `%${query.search ?? ''}%`, query.status ?? null, query.from ?? null, query.to ?? null],
  order: (query) => orderBy(query.sort, query.direction, { date: 'i.issued_at', number: 'i.invoice_number', balance: 'i.balance' }, 'i.issued_at'),
};

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
  app.get('/api/v1/patients', { preHandler: [authenticate, requirePermission(permissions.patientsView)] }, tenantList(patientList));

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
        return { patient: patientResponse(existing.rows[0]), submissionId: input.submissionId, duplicateSubmission: true };
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
      return { patient: patientResponse(row), submissionId: input.submissionId, duplicateSubmission: false };
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
      return { patient: patientResponse(patient.rows[0]) };
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
      return { patient: patient.rows[0] };
    });
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
        client.query('SELECT count(*)::int AS count, coalesce(sum(balance), 0) AS outstanding_balance FROM invoices WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query('SELECT count(*)::int AS count FROM media_assets WHERE clinic_id=$1 AND patient_id=$2', [clinicId, patientId]),
        client.query(`SELECT type, occurred_at, summary FROM (
          SELECT 'Consultation' AS type, occurred_at, coalesce(final_diagnosis, chief_complaint) AS summary FROM consultations WHERE clinic_id=$1 AND patient_id=$2
          UNION ALL SELECT 'Vaccination', administered_at, vaccine_name FROM vaccinations WHERE clinic_id=$1 AND patient_id=$2
          UNION ALL SELECT 'Laboratory', requested_at, test_type FROM laboratory_reports WHERE clinic_id=$1 AND patient_id=$2
        ) events ORDER BY occurred_at DESC LIMIT 10`, [clinicId, patientId]),
      ]);
      return { patient: patient.rows[0], summaries: { consultations: consultations.rows[0], vaccinations: vaccinations.rows[0], laboratory: laboratory.rows[0], hospitalizations: hospitalizations.rows[0], surgeries: surgeries.rows[0], prescriptions: prescriptions.rows[0], billing: invoices.rows[0], media: media.rows[0] }, timeline: timeline.rows };
    });
  });

  for (const [path, table, id, permission, order] of [
    ['consultations', 'consultations', 'consultation_id', permissions.consultationsView, 'occurred_at'], ['vaccinations', 'vaccinations', 'vaccination_id', permissions.vaccinationsView, 'administered_at'], ['laboratory', 'laboratory_reports', 'laboratory_report_id', permissions.laboratoryView, 'requested_at'], ['hospitalizations', 'hospitalizations', 'hospitalization_id', permissions.hospitalizationView, 'admitted_at'], ['surgeries', 'surgeries', 'surgery_id', permissions.surgeryView, 'performed_at'], ['prescriptions', 'prescriptions', 'prescription_id', permissions.prescriptionsView, 'prescribed_at'],
    ['billing', 'invoices', 'invoice_id', permissions.billingView, 'issued_at'], ['appointments', 'schedule_entries', 'schedule_entry_id', permissions.appointmentsView, 'scheduled_at'], ['documents', 'media_assets', 'media_asset_id', permissions.mediaView, 'created_at'], ['images', 'media_assets', 'media_asset_id', permissions.mediaView, 'created_at'],
  ]) app.get(`/api/v1/patients/:patientId/${path}`, { preHandler: [authenticate, requirePermission(permission)] }, (request, reply) => patientSection(request, reply, table, id, permission, order));

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

  app.post('/api/v1/invoices', { preHandler: [authenticate, requirePermission(permissions.billingCreate)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const parsed = createInvoiceSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Please review the invoice information.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const input = parsed.data;
      const patient = await client.query(
        'SELECT patient_id, owner_id FROM patients WHERE clinic_id=$1 AND patient_id=$2 AND status ILIKE $3 AND deleted_at IS NULL',
        [request.auth.clinicId, input.patientId, 'active'],
      );
      if (!patient.rows[0]) return reply.code(404).send({ error: 'patient_not_found', message: 'The selected active patient was not found in this clinic.' });
      const invoiceNumber = `INV-${Date.now()}-${input.submissionId.slice(0, 8).toUpperCase()}`;
      const paid = input.status === 'Paid' ? input.total : 0;
      const inserted = await client.query(
        `INSERT INTO invoices
           (clinic_id, owner_id, patient_id, invoice_number, status, subtotal,
            tax, discount, total, amount_paid, balance, issued_at)
         VALUES ($1,$2,$3,$4,$5,$6,0,0,$7,$8,$9,now())
         RETURNING invoice_id, invoice_number, patient_id, status, subtotal,
                   total, amount_paid, balance, issued_at`,
        [request.auth.clinicId, patient.rows[0].owner_id, input.patientId,
          invoiceNumber, input.status, input.subtotal, input.total, paid,
          input.total - paid],
      );
      if (input.status === 'Paid' && input.total > 0) {
        await client.query(
          `INSERT INTO payments (clinic_id, invoice_id, paid_at, amount, method)
           VALUES ($1,$2,now(),$3,'Clinic Billing')`,
          [request.auth.clinicId, inserted.rows[0].invoice_id, input.total],
        );
      }
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'Invoice',
        targetId: inserted.rows[0].invoice_id,
        action: input.status === 'Paid' ? 'billing.sale_recorded' : 'billing.draft_created',
        newSummary: { patientId: input.patientId, total: input.total, serviceCount: input.services.length },
        sessionId: request.auth.sessionId,
      });
      reply.code(201);
      return { ...inserted.rows[0], submissionId: input.submissionId };
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
      const existing = await client.query(
        `SELECT ${inventoryList.select}
           FROM inventory_products i
          WHERE i.clinic_id = $1 AND i.submission_id = $2 AND i.deleted_at IS NULL`,
        [request.auth.clinicId, input.submissionId],
      );
      if (existing.rows[0]) {
        return { item: inventoryResponse(existing.rows[0]), submissionId: input.submissionId, duplicateSubmission: true };
      }
      const inserted = await client.query(
        `INSERT INTO inventory_products
           (clinic_id, name, category, category_key, batch_number, expiry_date,
            purchase_price, selling_price, quantity, reorder_level, status,
            submission_id, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'Active',$11,now(),now())
         ON CONFLICT (clinic_id, submission_id)
           WHERE submission_id IS NOT NULL
         DO NOTHING
         RETURNING inventory_product_id, name, category, category_key,
                   batch_number, expiry_date, purchase_price, selling_price,
                   quantity, reorder_level, status, created_at, updated_at, revision`,
        [request.auth.clinicId, input.name, input.categoryName, input.categoryId,
          input.batchNumber ?? null, input.expiryDate ?? null, input.purchasePrice,
          input.sellingPrice, input.quantity, input.reorderLevel, input.submissionId],
      );
      if (!inserted.rows[0]) {
        const duplicate = await client.query(
          `SELECT ${inventoryList.select}
             FROM inventory_products i
            WHERE i.clinic_id = $1 AND i.submission_id = $2`,
          [request.auth.clinicId, input.submissionId],
        );
        return {
          item: inventoryResponse(duplicate.rows[0]),
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
      return { item: inventoryResponse(inserted.rows[0]), submissionId: input.submissionId, duplicateSubmission: false };
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
        `SELECT inventory_product_id, name, category_key, quantity, revision
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
      const updated = await client.query(
        `UPDATE inventory_products
            SET name = $1, category = $2, category_key = $3, batch_number = $4,
                expiry_date = $5, purchase_price = $6, selling_price = $7,
                quantity = $8, reorder_level = $9, updated_at = now(),
                revision = revision + 1
          WHERE clinic_id = $10 AND inventory_product_id = $11
          RETURNING inventory_product_id, name, category, category_key,
                    batch_number, expiry_date, purchase_price, selling_price,
                    quantity, reorder_level, status, created_at, updated_at, revision`,
        [input.name, input.categoryName, input.categoryId, input.batchNumber ?? null,
          input.expiryDate ?? null, input.purchasePrice, input.sellingPrice,
          input.quantity, input.reorderLevel, request.auth.clinicId,
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
      return { item: inventoryResponse(updated.rows[0]) };
    });
  });

  app.get('/api/v1/inventory/products', { preHandler: [authenticate, requirePermission(permissions.inventoryView)] }, tenantList(inventoryList));
  app.get('/api/v1/inventory/movements', { preHandler: [authenticate, requirePermission(permissions.inventoryView)] }, tenantList(movementsList));
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
