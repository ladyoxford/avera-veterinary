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

## Account email and password recovery

AVERA uses one account-email transport for clinic administrator activation,
staff invitations, mutual-deletion confirmation, and password recovery. For a
Hostinger Email mailbox, create the mailbox in hPanel and configure these
secrets on the API service:

```dotenv
EMAIL_TRANSPORT=smtp
EMAIL_FROM=AVERA <accounts@averavet.sbs>
SMTP_HOST=smtp.hostinger.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=accounts@averavet.sbs
SMTP_PASSWORD=<the Hostinger mailbox password>
```

`SMTP_USER` must be the complete mailbox address. If the deployment provider
cannot establish an SSL connection on port 465, use port 587 with
`SMTP_SECURE=false` so Nodemailer upgrades the connection with STARTTLS. Never
commit the mailbox password or place reset and activation links in build logs.

Set the account-link configuration on the same API service:

```dotenv
ACTIVATION_TOKEN_TTL_MINUTES=2880
PASSWORD_RESET_TOKEN_TTL_MINUTES=30
AVERA_ACTIVATION_BASE_URL=https://accounts.averavet.sbs/activate-clinic-admin
AVERA_STAFF_ACTIVATION_BASE_URL=https://accounts.averavet.sbs/activate-staff
AVERA_PASSWORD_RESET_BASE_URL=https://accounts.averavet.sbs/reset-password
```

`EMAIL_TRANSPORT=auto` may be used when SMTP should be preferred with Resend as
a configured fallback. For Resend-only delivery, set `EMAIL_TRANSPORT=resend`,
`RESEND_API_KEY`, and a verified `EMAIL_FROM` sender.

Point the DNS `accounts` CNAME at the Render service hostname and add
`accounts.averavet.sbs` as a custom domain on that service. The same Fastify
service hosts `/.well-known/assetlinks.json` and the token-safe fallback page.

After saving the secrets, restart the API and verify Platform Owner system
health reports the expected provider. Request a reset for a test account and
complete the link once; a second use must be rejected. Administrator approval
and resend retain their temporary manual-delivery fallback when email is not
configured, but password recovery deliberately remains unavailable until a
transport is configured.

After deploying code, run the migration as a Render Shell one-off command:

```sh
cd backend && npm run migrate:container
```

Then restart the web service and verify `/health/ready`. Never run
`seed:development` or enable reset-link previews in production.

Do not run development seeding in staging or production. Do not use the
PostgreSQL owner credential for the API. Retain structured logs and audit logs
according to the clinic's applicable data-retention policy.
