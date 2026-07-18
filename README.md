# AVERA Flutter Application

## Development Data Modes

AVERA has an explicit compile-time data mode. Local mode is the default for
debug development and uses the existing Drift workspace, locally seeded clinic
data, and a securely stored local session reference. Docker and an API URL are
not required.

```powershell
flutter run -d <DEVICE_ID> --dart-define=AVERA_DATA_MODE=local
```

Use the existing local development administrator account to open the populated
Zevora workspace. Local mode is blocked from release builds.

Backend mode preserves the production REST, token, and PostgreSQL path. It is
selected explicitly and requires an API URL:

```powershell
flutter run -d <DEVICE_ID> --dart-define=AVERA_DATA_MODE=backend --dart-define=AVERA_API_BASE_URL=https://api.example.com
```

The default request timeout is 15 seconds and can be adjusted for debug work
with `--dart-define=AVERA_API_TIMEOUT_SECONDS=<seconds>`.

## Subscription Plans

Starter includes core patient, consultation, schedule, vaccination, inventory,
and billing workflows. Professional adds laboratory, prescriptions, imaging,
reports, and Vera. Enterprise adds hospitalization, treatment board, surgery,
and corporate analytics. In local debug mode, the Platform Owner can simulate
each plan from Platform Owner -> Developer Settings without deleting clinic
records.
