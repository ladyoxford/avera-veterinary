import { loadEnvironment } from '../config/env.js';
import { createPool } from '../database/pool.js';

const environment = loadEnvironment();
if (environment.NODE_ENV === 'production' || !environment.demoDataGeneratorEnabled) throw new Error('Demo benchmarks are disabled.');
const datasetId = process.argv.slice(2).find((value) => value.startsWith('--dataset='))?.split('=')[1];
if (!datasetId) throw new Error('Benchmark requires --dataset=<dataset-id>.');
const pool = createPool(environment.DATABASE_URL);
try {
  const clinic = (await pool.query('SELECT clinic_id FROM clinics WHERE demo_dataset_id = $1 ORDER BY name LIMIT 1', [datasetId])).rows[0];
  if (!clinic) throw new Error('Demo dataset was not found.');
  const queries = {
    patientFirstPage: [`SELECT patient_id, hospital_number, name, species FROM patients WHERE clinic_id = $1 AND demo_dataset_id = $2 ORDER BY hospital_number LIMIT 50`, [clinic.clinic_id, datasetId]],
    patientSearch: [`SELECT patient_id, hospital_number, name FROM patients WHERE clinic_id = $1 AND demo_dataset_id = $2 AND name ILIKE $3 ORDER BY name LIMIT 50`, [clinic.clinic_id, datasetId, '%Bella%']],
    consultationPage: [`SELECT consultation_id, occurred_at, final_diagnosis FROM consultations WHERE clinic_id = $1 AND demo_dataset_id = $2 ORDER BY occurred_at DESC, consultation_id LIMIT 50`, [clinic.clinic_id, datasetId]],
    invoiceSearch: [`SELECT invoice_id, invoice_number, total, balance FROM invoices WHERE clinic_id = $1 AND demo_dataset_id = $2 ORDER BY invoice_number LIMIT 50`, [clinic.clinic_id, datasetId]],
    inventoryFilter: [`SELECT inventory_product_id, name, quantity FROM inventory_products WHERE clinic_id = $1 AND demo_dataset_id = $2 AND quantity <= reorder_level ORDER BY name LIMIT 50`, [clinic.clinic_id, datasetId]],
    dashboardAggregation: [`SELECT (SELECT count(*) FROM patients WHERE clinic_id = $1 AND demo_dataset_id = $2) AS patients, (SELECT count(*) FROM consultations WHERE clinic_id = $1 AND demo_dataset_id = $2) AS consultations, (SELECT coalesce(sum(total), 0) FROM invoices WHERE clinic_id = $1 AND demo_dataset_id = $2) AS revenue`, [clinic.clinic_id, datasetId]],
  };
  const results = {};
  for (const [name, [sql, values]] of Object.entries(queries)) {
    const started = performance.now(); const query = await pool.query(sql, values);
    results[name] = { milliseconds: Number((performance.now() - started).toFixed(2)), rows: query.rowCount };
  }
  const databaseSize = (await pool.query('SELECT pg_database_size(current_database())::bigint AS bytes')).rows[0].bytes;
  console.log(JSON.stringify({ datasetId, databaseBytes: Number(databaseSize), results }, null, 2));
} finally { await pool.end(); }
