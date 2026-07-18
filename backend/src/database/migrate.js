import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnvironment } from '../config/env.js';
import { createPool } from './pool.js';

const directory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../migrations');
const environment = loadEnvironment();
const pool = createPool(environment.DATABASE_URL);

await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
const applied = new Set((await pool.query('SELECT name FROM schema_migrations')).rows.map((row) => row.name));
for (const file of (await fs.readdir(directory)).filter((name) => name.endsWith('.sql')).sort()) {
  if (applied.has(file)) continue;
  const sql = await fs.readFile(path.join(directory, file), 'utf8');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
    await client.query('COMMIT');
    console.log(`Applied ${file}`);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
await pool.end();
