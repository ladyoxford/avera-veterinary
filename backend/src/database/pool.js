import pg from 'pg';

export function createPool(connectionString) {
  return new pg.Pool({ connectionString, max: 20, idleTimeoutMillis: 30_000 });
}

export async function withTenantTransaction(pool, context, action) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('avera.clinic_id', $1, true)", [context.clinicId ?? '']);
    await client.query("SELECT set_config('avera.is_platform_owner', $1, true)", [String(context.isPlatformOwner === true)]);
    const value = await action(client);
    await client.query('COMMIT');
    return value;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
