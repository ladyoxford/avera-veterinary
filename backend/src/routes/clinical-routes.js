import { z } from 'zod';
import { withTenantTransaction } from '../database/pool.js';
import { authenticate, requirePermission } from '../middleware/auth.js';
import { permissions } from '../security/permissions.js';

const pageSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
  search: z.string().trim().max(160).optional(),
  sort: z.string().trim().max(80).optional(),
  direction: z.enum(['asc', 'desc']).default('desc'),
  status: z.string().trim().max(80).optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
});

const uuidSchema = z.object({ patientId: z.string().uuid() });

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
           p.current_weight_kg, p.image_placeholder, p.registered_at, p.updated_at, p.revision,
           o.owner_id, o.full_name AS owner_name, o.phone AS owner_phone`,
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

function clinicalList({ table, alias, id, permission, select, dateColumn, searchColumns = [], statusColumn = 'status' }) {
  const search = searchColumns.length ? `($2::text IS NULL OR ${searchColumns.map((column) => `${column} ILIKE $3`).join(' OR ')})` : 'true';
  const status = statusColumn ? `AND ($4::text IS NULL OR ${alias}.${statusColumn} = $4)` : '';
  const dates = dateColumn ? `AND ($5::timestamptz IS NULL OR ${alias}.${dateColumn} >= $5) AND ($6::timestamptz IS NULL OR ${alias}.${dateColumn} <= $6)` : '';
  return {
    permission,
    config: {
      from: `${table} ${alias} LEFT JOIN patients p ON p.patient_id = ${alias}.patient_id LEFT JOIN owners o ON o.owner_id = p.owner_id`,
      select: `${alias}.${id}, ${alias}.clinic_id, ${alias}.patient_id, ${select}, p.name AS patient_name, p.hospital_number, o.full_name AS owner_name`,
      where: `${alias}.clinic_id = $1 AND ${search} ${status} ${dates}`,
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
  schedule: clinicalList({ table: 'schedule_entries', alias: 's', id: 'schedule_entry_id', permission: permissions.appointmentsView, dateColumn: 'scheduled_at', select: 's.scheduled_at, s.visit_type, s.status, s.notes, s.assigned_staff_id', searchColumns: ['p.name', 's.visit_type', 'o.full_name'] }),
};

const inventoryList = {
  from: 'inventory_products i',
  select: 'i.inventory_product_id, i.name, i.generic_name, i.category, i.manufacturer, i.supplier, i.batch_number, i.expiry_date, i.purchase_price, i.selling_price, i.quantity, i.reorder_level, i.status',
  where: `i.clinic_id = $1 AND ($2::text IS NULL OR i.name ILIKE $3 OR i.generic_name ILIKE $3 OR i.batch_number ILIKE $3 OR i.category ILIKE $3)
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

  app.get('/api/v1/patients/:patientId', { preHandler: [authenticate, requirePermission(permissions.patientsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = uuidSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'validation_error', message: 'The patient identifier is invalid.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const patient = await client.query(`${patientList.select} FROM ${patientList.from} WHERE p.clinic_id = $1 AND p.patient_id = $2 AND p.deleted_at IS NULL AND o.deleted_at IS NULL`, [request.auth.clinicId, params.data.patientId]);
      if (!patient.rows[0]) return reply.code(404).send({ error: 'not_found', message: 'The patient was not found in this clinic.' });
      return { patient: patient.rows[0] };
    });
  });

  app.get('/api/v1/patients/:patientId/medical-file', { preHandler: [authenticate, requirePermission(permissions.patientsView)] }, async (request, reply) => {
    if (!requireClinic(request, reply)) return undefined;
    const params = uuidSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'validation_error', message: 'The patient identifier is invalid.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const patient = await client.query(`${patientList.select} FROM ${patientList.from} WHERE p.clinic_id = $1 AND p.patient_id = $2 AND p.deleted_at IS NULL AND o.deleted_at IS NULL`, [request.auth.clinicId, params.data.patientId]);
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
  ]) app.get(`/api/v1/patients/:patientId/${path}`, { preHandler: [authenticate, requirePermission(permission)] }, (request, reply) => patientSection(request, reply, table, id, permission, order));

  for (const [path, list] of Object.entries(lists)) app.get(`/api/v1/${path === 'laboratory' ? 'laboratory-reports' : path}`, { preHandler: [authenticate, requirePermission(list.permission)] }, tenantList(list.config));
  app.get('/api/v1/inventory/products', { preHandler: [authenticate, requirePermission(permissions.inventoryView)] }, tenantList(inventoryList));
  app.get('/api/v1/inventory/movements', { preHandler: [authenticate, requirePermission(permissions.inventoryView)] }, tenantList(movementsList));
  app.get('/api/v1/invoices', { preHandler: [authenticate, requirePermission(permissions.billingView)] }, tenantList(invoiceList));
  app.get('/api/v1/payments', { preHandler: [authenticate, requirePermission(permissions.billingView)] }, tenantList(paymentList));
  app.get('/api/v1/media', { preHandler: [authenticate, requirePermission(permissions.mediaView)] }, tenantList(mediaList));

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
        client.query(`SELECT 'Consultation' AS type, occurred_at AS occurred_at, coalesce(final_diagnosis, chief_complaint) AS summary FROM consultations WHERE clinic_id=$1 UNION ALL SELECT 'Schedule', scheduled_at, visit_type FROM schedule_entries WHERE clinic_id=$1 ORDER BY occurred_at DESC LIMIT 10`, [clinicId]),
      ]);
      return { ...result.rows[0], speciesDistribution: species.rows, revenueTrend: revenue.rows, recentActivity: activity.rows };
    });
  });
}
