# Database migrations

Run `npm run migrate` after configuring PostgreSQL and before starting the API. Applied files are recorded in `schema_migrations`; never edit a migration that has been applied to an environment.

Create a new numbered SQL file for every schema change. Test it against a database copy before staging and production. Rollbacks should be a separate, reviewed migration where a direct reversal is safe. Production migrations must run through CI/CD using a restricted application database role.
