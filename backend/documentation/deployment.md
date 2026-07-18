# Deployment checklist

Deploy the Fastify container and PostgreSQL separately. A practical first
production route is Render, Railway, Fly.io, or an equivalent managed container
service paired with managed PostgreSQL. Terminate TLS at the load balancer and
run the API as a non-owner PostgreSQL role so Row Level Security applies.

1. Create a managed PostgreSQL 16 database with encrypted backups.
2. Store every `.env` value in the hosting provider's secret manager.
3. Set `NODE_ENV=staging` first, `ENABLE_LOCAL_DEVELOPMENT_AUTH=false`, strict
   `ALLOWED_ORIGINS`, and distinct 32+ character JWT secrets.
4. Deploy the image from `backend/Dockerfile`.
5. Run `npm run migrate` as a one-off release command using the same database.
6. Confirm `/health/live` and `/health/ready` before enabling traffic.
7. Repeat for production only after staging authentication, RLS, and audit-log
   tests pass.

Do not run development seeding in staging or production. Do not use the
PostgreSQL owner credential for the API. Retain structured logs and audit logs
according to the clinic's applicable data-retention policy.
