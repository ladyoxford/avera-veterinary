// PostgreSQL stores payments as signed ledger values: receipts are positive and
// refunds, when present, are negative. The local database stores refund
// magnitudes with transaction_type='Refund' and normalizes them to this same
// signed contract before aggregation.
export const reportCte = `
  WITH filtered_payments AS (
    SELECT p.payment_id, p.invoice_id, p.paid_at,
           p.amount AS signed_amount, p.method,
           p.reference, i.invoice_number, i.issued_at, i.total,
           i.context_type,
           coalesce(
             CASE WHEN i.context_type='farm_visit'
                  THEN coalesce(i.client_name_snapshot, f.client_name, f.name)
                  ELSE coalesce(o.full_name, patient_owner.full_name, ptn.name)
             END,
             'Client'
           ) AS client_name
      FROM payments p
      JOIN invoices i
        ON i.clinic_id=p.clinic_id AND i.invoice_id=p.invoice_id
      LEFT JOIN owners o
        ON o.owner_id=i.owner_id AND o.clinic_id=i.clinic_id
      LEFT JOIN patients ptn
        ON ptn.patient_id=i.patient_id AND ptn.clinic_id=i.clinic_id
      LEFT JOIN owners patient_owner
        ON patient_owner.owner_id=ptn.owner_id
       AND patient_owner.clinic_id=i.clinic_id
      LEFT JOIN farms f
        ON f.farm_id=i.farm_id AND f.clinic_id=i.clinic_id
     WHERE p.clinic_id=$1
       AND i.status <> 'Voided'
       AND ($2::timestamptz IS NULL OR p.paid_at >= $2)
       AND ($3::timestamptz IS NULL OR p.paid_at < $3)
  ),
  paid_by_invoice AS (
    SELECT invoice_id, invoice_number, issued_at, total, context_type,
           client_name, sum(signed_amount) AS paid_in_range,
           count(*)::int AS transaction_count,
           max(paid_at) AS latest_payment_at
      FROM filtered_payments
     GROUP BY invoice_id, invoice_number, issued_at, total, context_type,
              client_name
  ),
  invoice_costs AS (
    SELECT pbi.invoice_id,
           coalesce(sum(
             CASE WHEN li.unit_cost_snapshot IS NULL THEN 0
                  ELSE li.unit_cost_snapshot * li.quantity END
           ), 0) AS recorded_cost,
           count(li.invoice_line_item_id) FILTER (
             WHERE li.invoice_line_item_id IS NOT NULL
               AND li.unit_cost_snapshot IS NULL
           )::int AS missing_cost_lines
      FROM paid_by_invoice pbi
      LEFT JOIN invoice_line_items li
        ON li.clinic_id=$1 AND li.invoice_id=pbi.invoice_id
     GROUP BY pbi.invoice_id
  ),
  report_invoices AS (
    SELECT pbi.*,
           CASE WHEN pbi.total > 0 THEN
             costs.recorded_cost * least(pbi.paid_in_range / pbi.total, 1)
           ELSE 0 END AS allocated_cost,
           costs.missing_cost_lines
      FROM paid_by_invoice pbi
      JOIN invoice_costs costs ON costs.invoice_id=pbi.invoice_id
  )`;

const paymentMetricWhere = {
  revenue: '',
  clinic_revenue: "WHERE context_type<>'farm_visit'",
  farm_revenue: "WHERE context_type='farm_visit'",
  settled_transactions: '',
};

export const revenueDrilldownMetrics = [
  'revenue',
  'gross_profit',
  'recorded_cost',
  'clinic_revenue',
  'farm_revenue',
  'settled_transactions',
];

export async function loadRevenueSummary(client, {
  clinicId,
  from = null,
  to = null,
}) {
  const result = await client.query(
    `${reportCte}
     SELECT coalesce(sum(paid_in_range), 0) AS revenue,
            coalesce(sum(
              CASE WHEN context_type='farm_visit'
                   THEN paid_in_range ELSE 0 END
            ), 0) AS farm_revenue,
            coalesce(sum(
              CASE WHEN context_type<>'farm_visit'
                   THEN paid_in_range ELSE 0 END
            ), 0) AS clinic_revenue,
            coalesce(sum(allocated_cost), 0) AS cost,
            coalesce(sum(transaction_count), 0)::int AS transaction_count,
            coalesce(sum(missing_cost_lines), 0)::int AS missing_cost_lines
       FROM report_invoices`,
    [clinicId, from, to],
  );
  return result.rows[0];
}

export async function loadRevenueDrilldown(client, {
  clinicId,
  from = null,
  to = null,
  metric,
  page,
  pageSize,
}) {
  const offset = (page - 1) * pageSize;
  const parameters = [clinicId, from, to, pageSize, offset];
  let rowsSql;
  let totalsSql;

  if (metric in paymentMetricWhere) {
    const where = paymentMetricWhere[metric];
    rowsSql = `${reportCte}
      SELECT payment_id AS id, 'payment' AS row_type, invoice_id,
             invoice_number, paid_at AS occurred_at, client_name,
             CASE WHEN context_type='farm_visit' THEN 'Farm'
                  ELSE 'Clinic' END AS context,
             signed_amount AS amount, method
        FROM filtered_payments
        ${where}
       ORDER BY paid_at DESC, payment_id DESC
       LIMIT $4 OFFSET $5`;
    totalsSql = `${reportCte}
      SELECT coalesce(sum(signed_amount), 0) AS total_value,
             count(*)::int AS total_count
        FROM filtered_payments
        ${where}`;
  } else if (metric === 'gross_profit') {
    rowsSql = `${reportCte}
      SELECT invoice_id AS id, 'invoice_profit' AS row_type, invoice_id,
             invoice_number, latest_payment_at AS occurred_at, client_name,
             CASE WHEN context_type='farm_visit' THEN 'Farm'
                  ELSE 'Clinic' END AS context,
             paid_in_range AS sale_amount,
             allocated_cost AS recorded_cost,
             paid_in_range - allocated_cost AS gross_profit,
             missing_cost_lines
        FROM report_invoices
       ORDER BY latest_payment_at DESC, invoice_id DESC
       LIMIT $4 OFFSET $5`;
    totalsSql = `${reportCte}
      SELECT coalesce(sum(paid_in_range - allocated_cost), 0) AS total_value,
             count(*)::int AS total_count
        FROM report_invoices`;
  } else {
    rowsSql = `${reportCte},
      known_cost_lines AS (
        SELECT li.invoice_line_item_id, ri.invoice_id, ri.invoice_number,
               ri.latest_payment_at, ri.client_name, ri.context_type,
               coalesce(li.product_name_snapshot, li.description) AS description,
               li.quantity, li.unit_cost_snapshot,
               li.unit_cost_snapshot * li.quantity AS historical_cost,
               CASE WHEN ri.total > 0 THEN
                 li.unit_cost_snapshot * li.quantity
                   * least(ri.paid_in_range / ri.total, 1)
               ELSE 0 END AS allocated_cost
          FROM report_invoices ri
          JOIN invoice_line_items li
            ON li.clinic_id=$1 AND li.invoice_id=ri.invoice_id
         WHERE li.unit_cost_snapshot IS NOT NULL
      )
      SELECT invoice_line_item_id AS id, 'cost_line' AS row_type, invoice_id,
             invoice_number, latest_payment_at AS occurred_at, client_name,
             CASE WHEN context_type='farm_visit' THEN 'Farm'
                  ELSE 'Clinic' END AS context,
             description, quantity, unit_cost_snapshot AS unit_cost,
             historical_cost, allocated_cost AS recorded_cost
        FROM known_cost_lines
       ORDER BY latest_payment_at DESC, invoice_line_item_id DESC
       LIMIT $4 OFFSET $5`;
    totalsSql = `${reportCte},
      known_cost_lines AS (
        SELECT CASE WHEN ri.total > 0 THEN
                 li.unit_cost_snapshot * li.quantity
                   * least(ri.paid_in_range / ri.total, 1)
               ELSE 0 END AS allocated_cost
          FROM report_invoices ri
          JOIN invoice_line_items li
            ON li.clinic_id=$1 AND li.invoice_id=ri.invoice_id
         WHERE li.unit_cost_snapshot IS NOT NULL
      )
      SELECT coalesce(sum(allocated_cost), 0) AS total_value,
             count(*)::int AS total_count
        FROM known_cost_lines`;
  }

  const [rows, totals] = await Promise.all([
    client.query(rowsSql, parameters),
    client.query(totalsSql, parameters.slice(0, 3)),
  ]);
  const total = totals.rows[0].total_count;
  return {
    items: rows.rows,
    page,
    pageSize,
    total,
    hasNextPage: offset + rows.rows.length < total,
    totalValue: totals.rows[0].total_value,
  };
}

export function signedLedgerAmount({ amount, transactionType = 'Payment' }) {
  const numericAmount = Number(amount);
  if (!Number.isFinite(numericAmount)) {
    throw new TypeError('Ledger amount must be numeric.');
  }
  return transactionType === 'Refund'
    ? -Math.abs(numericAmount)
    : numericAmount;
}

export function allocateSignedLedgerCost({
  recordedCost,
  netSignedAmount,
  invoiceTotal,
}) {
  const total = Number(invoiceTotal);
  if (!(total > 0)) return 0;
  return Number(recordedCost) * Math.min(Number(netSignedAmount) / total, 1);
}
