# AVERA Production Backend Foundation

The backend is a Node.js 20+ Fastify API with PostgreSQL. This is the single
backend stack for AVERA. It deliberately keeps
authentication, authorization, tenant context, tokens, audit logs, and secrets
server-side. Flutter only receives safe user/session data and stores access and
refresh credentials through platform secure storage.

## Local setup

1. Copy `.env.example` to `.env` and replace every secret.
2. Start PostgreSQL 16 locally, or run `docker compose up postgres`.
3. Run `npm install`.
4. Run `npm run migrate`.
5. Optionally set the two `DEVELOPMENT_*_PASSWORD` values and run `npm run seed:development`.
6. Run `npm run dev`.

For a containerised local API, use the container-safe scripts. Compose injects
the environment variables into the container; it does not copy `.env` into the
image.

```powershell
docker compose build --no-cache api
docker compose up -d postgres
docker compose run --rm api npm run migrate:container
docker compose run --rm api npm run seed:development:container
docker compose up -d api
docker compose exec api npm run diagnose:development-auth
docker compose exec api npm run test:auth:integration
```

## Development identities

Development-only seeds use `owner@avera.test` for the Platform Owner and
`admin@avera.test` for the Zevora Clinic Administrator. Their passwords are
the values of `DEVELOPMENT_PLATFORM_OWNER_PASSWORD` and
`DEVELOPMENT_CLINIC_ADMIN_PASSWORD`; neither is committed to source control.
The seed migrates the legacy `.local` identities in place, preserving user IDs,
roles, memberships, clinic data, and audit history. Every development seed run
refreshes the two password hashes from the current environment, resets their
development lock state, creates or repairs the administrator membership, and
revokes existing sessions because the credentials changed. No production user
is selected by this operation, and production mode rejects the seed entirely.

`npm run diagnose:development-auth` is safe to run inside the API container. It
reports identity, membership, clinic, environment-presence, bcrypt-match, and
endpoint status booleans without printing passwords, hashes, database
credentials, access tokens, or refresh tokens.

## Architecture

Flutter communicates only with versioned HTTPS API endpoints. The API owns
password verification, session rotation, audit logs, effective permissions,
and tenant context. PostgreSQL Row Level Security is enabled for tenant tables,
and service queries set `avera.clinic_id` only from the verified session. A
Platform Owner receives platform permissions but no automatic access to patient
records.

Users are global identities. `clinic_memberships` associates them with clinics,
roles, branch access, and membership status. The existing `users.clinic_id`
field remains during the local-to-cloud migration for backwards compatibility;
the membership table is the production migration path.

The backend uses a project-local npm cache (`.npm-cache`) so it does not depend
on a locked Windows user cache. The machine running installation still needs
outbound HTTPS access to `https://registry.npmjs.org/`. Configure an approved
corporate proxy in the environment before running `npm install` when required.

The API exposes `/health/live` and `/health/ready`, plus versioned endpoints
under `/api/v1`. See `documentation/api.md` for the initial endpoint list.

## Production safety

- `ENABLE_LOCAL_DEVELOPMENT_AUTH` must be `false` in production.
- Use a dedicated, non-owner PostgreSQL application role so RLS policies apply.
- Terminate TLS at the edge or run HTTPS directly.
- Store `.env` only in the deployment secret manager.
- Apply migrations through CI/CD, never by hand against production.

See `documentation/environment.md`, `documentation/migrations.md`, and
`documentation/deployment.md` for operating guidance.

## Deterministic demo data

The demo generator is disabled by default. It can run only in development or
approved staging when `ENABLE_DEMO_DATA_GENERATOR=true`; production refuses to
start if that flag is enabled. Set a non-committed
`DEVELOPMENT_DEMO_ADMIN_PASSWORD` to create `demo.admin@avera.test` in the
first generated clinic.

```powershell
npm run demo:small
npm run demo:generate -- --size=large --seed=2026 --reset=true
npm run demo:enterprise
npm run demo:validate -- --dataset=<dataset-id>
npm run demo:benchmark -- --dataset=<dataset-id>
npm run demo:reset
```

Every generated row carries `is_demo` and `demo_dataset_id`; reset removes only
demo data. Use Large and Enterprise modes only against isolated development or
approved staging databases.
