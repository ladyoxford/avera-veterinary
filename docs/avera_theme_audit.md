# AVERA Theme Audit

Audit date: 2026-07-27

Canonical design system:

- `AppTheme`, `AveraTextStyles`, `AppSemanticColors`, and `AveraSpacing`
- `AveraPageHeader`, `AveraSectionHeader`, `AveraSurfaceCard`,
  `AveraAdministrationCard`, `AveraLabeledFieldCard`, and
  `AveraPrimaryActionButton`

No second theme extension or V2 component family is present. Specialized logo,
chart, receipt, status-badge, QR-code, and platform metric styling is allowed
to retain local values when it conveys data rather than general page styling.

## Reachable Route Audit

| Area | Routes / screens | Status | Notes |
| --- | --- | --- | --- |
| Authentication | Splash, Sign In, Password Reset, Clinic Activation | Partially migrated | ThemeData is authoritative; sign-in retains its deliberately compact branded composition. |
| Authentication | Clinic Registration, Subscription Comparison | Fully migrated | Shared page headers, cards, spacing, responsive form fields, and subscription components. |
| Authentication | Offline Unlock, Offline Access | Partially migrated | Functional and themed; form composition predates `AveraLabeledFieldCard`. |
| Authentication | MFA Challenge, Account Restricted | Fully migrated | Shared headers, surfaces, labels, actions, and responsive constraints. |
| Main navigation | Dashboard, More, bottom navigation, branded header | Fully migrated | Shared typography, cards, FAB clearance, and semantic colors. |
| Patients | Registered Pets, Archived Pets, Register Animal | Fully migrated | Current visual baseline. |
| Patients | Medical File and patient section editors | Partially migrated | Hub uses shared structure; several section-specific clinical editors retain specialized cards. |
| Consultations | New, Detail, Edit | Fully migrated | One explicit mode-aware implementation using shared fields and safe patient selection. |
| Schedule | Schedule, New Visit, Visit Detail, Reschedule | Fully migrated | Shared cards and responsive form/list patterns. |
| Vaccination | Vaccine Schedule, Record, Detail, Protocols | Fully migrated | Shared surfaces and filter/list patterns. |
| Operations | Inventory and Billing | Fully migrated | Shared surfaces, permission-aware controls, and responsive rows. |
| Operations | Laboratory, Hospitalization, Treatment Board, Surgery, Prescriptions, Imaging, Documents | Requires consolidation | Current clinic-wide routes intentionally expose honest capability-gated empty states while record schemas are incomplete. They are not duplicate screens. |
| Farm | Farm Records, Profile Editor, Overview, Unit Detail, Daily Record | Fully migrated | Shared headers, spacing, surfaces, and responsive detail forms. |
| Reporting | Reports and report details | Fully migrated | Shared hierarchy and report-specific metric styling. |
| Activity | Notification Centre, Activity History, Audit Logs and detail | Fully migrated | Shared rows/cards and actionable destinations. |
| Clinic administration | Administration, Users, Roles, Custom Role, Security, Work Hours, Patient Numbering | Fully migrated | Shared administration surfaces, guarded routes, and responsive dialogs. |
| Clinic administration | Backup & Restore | Fully migrated | Independent `AveraAdministrationCard` surfaces with canonical spacing. |
| Subscription | Plans, billing history, comparison, payment callback | Fully migrated | Shared subscription source and AVERA components. |
| Platform | Owner dashboard, clinics, subscriptions, users, audit | Partially migrated | Main consoles are functional; utility routes intentionally retain a shared unavailable-state screen until backend modules exist. |
| Vera | Vera screen | Partially migrated | Feature-specific assistant composition retains custom conversational styling. |

## Modals and States

| Category | Status | Notes |
| --- | --- | --- |
| Confirmation dialogs | Fully migrated | Material dialog theme is supplied centrally; destructive actions use semantic danger color. |
| Search and selector sheets | Fully migrated | Shared catalogue selector, safe area, search, keyboard handling, and responsive lists. |
| Long-press staff/patient sheets | Fully migrated | Theme-aware surfaces with bounded scrolling and responsive actions. |
| Loading and empty states | Partially migrated | All are theme-aware; some feature screens use local centered compositions because no canonical empty-state widget exists yet. |
| Date/time pickers | Fully migrated | Inherit global `ThemeData`. |
| Snackbars | Fully migrated | Inherit global `SnackBarThemeData`; copy remains feature-specific. |
| PDF/receipt content | Intentionally specialized | Print output uses fixed document typography and clinic branding rather than screen typography. |

## Static Findings

Hardcoded values remain most concentrated in:

- branded authentication and splash animation;
- printable PDF/receipt documents;
- charts, metrics, status badges, and QR presentation;
- legacy medical-file subsection editors;
- platform utility/empty states.

These values should not be mechanically replaced. The next theme-only pass
should consolidate empty/error states and the remaining medical-file editors.
It must not disturb the clinical and platform work already in progress.

## Backup & Restore Correction

The previous screen used two adjacent raw `Card`/`ListTile` widgets with the
default card margin, which made them read as one joined surface. It now uses
two independent `AveraAdministrationCard` instances separated by
`AveraSpacing.cardGap`, plus the canonical page header and bottom clearance.

The export path checkpoints SQLite's write-ahead log before copying committed
data. Restore selection validates the extension and SQLite signature, opens
the selected file read-only, runs `PRAGMA integrity_check`, verifies required
AVERA tables and schema-version compatibility, and confirms that the active
clinic is present before showing the review dialog. It deliberately does not
replace the live database; final replacement still requires a controlled
database shutdown, rollback copy, and restart path.
