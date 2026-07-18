# Security Checklist

- bcrypt cost 12 hashes passwords; plaintext passwords are never persisted.
- Access tokens are short lived; refresh tokens are random and stored only as SHA-256 hashes.
- Session revocation is checked server-side for every protected request.
- Account status and effective permissions are re-evaluated on every protected request.
- Tenant context is derived from the session and applied through transaction-scoped PostgreSQL settings.
- Sensitive events are written to immutable audit logs without passwords or tokens.
- Production rejects local development authentication.
- Invitations, password-reset delivery, payments, and synchronization are intentionally deferred to later phases.
