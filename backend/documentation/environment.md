# Environment configuration

Copy `.env.example` to `.env` for local work and set unique secrets of at least 32 characters. The service validates its environment before listening.

`DATABASE_URL`, `JWT_ACCESS_SECRET`, and `JWT_REFRESH_SECRET` are required. `ALLOWED_ORIGINS` is a comma-separated allow-list. In production, `ENABLE_LOCAL_DEVELOPMENT_AUTH` must be `false`; startup otherwise fails.

Development seed passwords are required only for `npm run seed:development` and must exist only in the local `.env` file. They are not supplied by source control.
