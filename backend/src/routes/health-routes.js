export async function healthRoutes(app) {
  app.get('/health/live', async () => ({ status: 'live' }));
  app.get('/health/ready', async (_, reply) => {
    try {
      await app.pool.query('SELECT 1');
      return { status: 'ready' };
    } catch (_) {
      return reply.code(503).send({ status: 'not_ready' });
    }
  });
}
