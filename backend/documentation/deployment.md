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

## Clinic Administrator activation

Set `ACTIVATION_TOKEN_TTL_MINUTES` and `AVERA_ACTIVATION_BASE_URL` in Render.
Use the verified Android App Link:
`https://accounts.averavet.sbs/activate-clinic-admin`. For email delivery, also
set `RESEND_API_KEY` and a verified `ACTIVATION_EMAIL_FROM` sender. Secrets and
activation links must not be placed in build logs.

Point the DNS `accounts` CNAME at the Render service hostname and add
`accounts.averavet.sbs` as a custom domain on that service. The same Fastify
service hosts `/.well-known/assetlinks.json` and the token-safe fallback page.

If the email variables are absent, approval and resend return the plaintext
activation link once to the authenticated Platform Owner response. The
Platform Owner Console labels this as temporary manual delivery and never
loads that link again from activation status. Configure email delivery before
removing the temporary UI path.

After deploying code, run the migration as a Render Shell one-off command:

```sh
cd backend && npm run migrate:container
```

Then restart the web service and verify `/health/ready`. Never run
`seed:development` or enable reset-link previews in production.

Do not run development seeding in staging or production. Do not use the
PostgreSQL owner credential for the API. Retain structured logs and audit logs
according to the clinic's applicable data-retention policy.
