# API v1

| Endpoint | Purpose |
| --- | --- |
| `POST /api/v1/auth/sign-in` | Authenticate and issue token pair |
| `POST /api/v1/auth/refresh` | Rotate refresh session and issue a new access token |
| `GET /api/v1/auth/me` | Current user and effective permissions |
| `POST /api/v1/auth/sign-out` | Revoke current session |
| `POST /api/v1/auth/sign-out-all` | Revoke every user session |
| `GET /api/v1/auth/sessions` | List account sessions |
| `DELETE /api/v1/auth/sessions/:sessionId` | Revoke one session |
| `POST /api/v1/auth/change-password` | Change password and revoke other sessions |
| `GET /api/v1/clinics` | Platform Owner clinic list |
| `PATCH /api/v1/clinics/:clinicId/status` | Platform Owner status control |
| `GET /api/v1/audit-logs` | Platform audit logs |
| `GET /api/v1/users` | Current clinic users; requires `users.view` |
| `GET /api/v1/roles` | Current clinic roles; requires `users.view` |
| `GET /api/v1/permissions` | Permission identifiers available to the signed-in user |

All protected endpoints require an access token. Tenant context comes from the
verified session, never from a clinic identifier supplied by Flutter.

`sign-in`, `refresh`, and `me` return a safe user profile with effective
permissions and active workspace metadata (`clinicId`, `clinicName`, clinic
status, and subscription plan). Passwords, raw tokens, and database credentials
are never returned.
