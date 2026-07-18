const checks = [
  ['cross-clinic patient owner', `SELECT count(*)::int AS count FROM patients p JOIN owners o ON o.owner_id = p.owner_id WHERE p.is_demo AND p.clinic_id <> o.clinic_id`],
  ['cross-clinic consultation patient', `SELECT count(*)::int AS count FROM consultations c JOIN patients p ON p.patient_id = c.patient_id WHERE c.is_demo AND c.clinic_id <> p.clinic_id`],
  ['cross-clinic invoice owner', `SELECT count(*)::int AS count FROM invoices i JOIN owners o ON o.owner_id = i.owner_id WHERE i.is_demo AND i.clinic_id <> o.clinic_id`],
  ['invalid clinical dates', `SELECT count(*)::int AS count FROM consultations c JOIN patients p ON p.patient_id = c.patient_id WHERE c.is_demo AND (c.occurred_at::date < p.date_of_birth OR (p.deceased_at IS NOT NULL AND c.occurred_at > p.deceased_at))`],
  ['invoice reconciliation', `SELECT count(*)::int AS count FROM invoices i LEFT JOIN (SELECT invoice_id, sum(amount) paid FROM payments WHERE is_demo GROUP BY invoice_id) p ON p.invoice_id = i.invoice_id WHERE i.is_demo AND abs(i.total - coalesce(p.paid, 0) - i.balance) > 0.01`],
  ['wrong vaccine species', `SELECT count(*)::int AS count FROM vaccinations v JOIN patients p ON p.patient_id = v.patient_id WHERE v.is_demo AND ((p.species IN ('Dog','Cat') AND v.vaccine_name LIKE 'Clostridial%') OR (p.species NOT IN ('Dog','Cat') AND v.vaccine_name IN ('DHPP','FVRCP')))`],
];

export async function validateDemoDataset(client, datasetId) {
  const results = {};
  for (const [name, sql] of checks) results[name] = (await client.query(sql)).rows[0].count;
  const counts = {};
  for (const table of ['clinics','owners','patients','consultations','vaccinations','laboratory_reports','hospitalizations','surgeries','inventory_products','stock_movements','prescriptions','schedule_entries','invoices','payments','media_assets']) {
    const column = table === 'clinics' ? 'demo_dataset_id' : 'demo_dataset_id';
    counts[table] = (await client.query(`SELECT count(*)::int AS count FROM ${table} WHERE ${column} = $1`, [datasetId])).rows[0].count;
  }
  const failures = Object.entries(results).filter(([, value]) => value > 0);
  return { ok: failures.length === 0, checks: results, counts, failures };
}
