import { loadEnvironment } from '../config/env.js';
import { createPool } from '../database/pool.js';
import { parseDemoOptions } from './demo-config.js';
import { generateDemoDataset, resetDemoData } from './demo-generator.js';
import { validateDemoDataset } from './validation.js';

const [command = 'generate', ...argv] = process.argv.slice(2);
const environment = loadEnvironment();
if (environment.NODE_ENV === 'production' || !environment.demoDataGeneratorEnabled) {
  throw new Error('Demo tooling is disabled. Enable it only in development or approved staging.');
}
const pool = createPool(environment.DATABASE_URL);
const client = await pool.connect();
try {
  if (command === 'reset') { await resetDemoData(client, argv.find((value) => value.startsWith('--dataset='))?.split('=')[1]); console.log('Demo data reset completed.'); }
  else if (command === 'validate') { const datasetId = argv.find((value) => value.startsWith('--dataset='))?.split('=')[1]; if (!datasetId) throw new Error('Validation requires --dataset=<dataset-id>.'); console.log(JSON.stringify(await validateDemoDataset(client, datasetId), null, 2)); }
  else console.log(JSON.stringify(await generateDemoDataset({ client, environment, options: parseDemoOptions(argv) }), null, 2));
} finally { client.release(); await pool.end(); }
