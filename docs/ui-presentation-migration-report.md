# UI Presentation Layer Migration Report

**Date:** 2026-06-08
**Scope:** Remove Flutter presentation-layer implementation; preserve domain, data, routing, and DI.

## Summary

| Check                                                      | Status     |
| ---------------------------------------------------------- | ---------- |
| `flutter analyze lib/`                                     | Pass       |
| `flutter build linux --debug`                              | Pass       |
| Unit + integration tests (`test/unit`, `test/integration`) | 900 passed |
| All routes preserved                                       | Yes        |
| Domain & data layers intact                                | Yes        |

## Infrastructure Added

| File                                                                             | Purpose                                                                         |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `frontend/lib/app/presentation/ui_pending_placeholder_page.dart`                 | Shared placeholder showing feature name, route name, and "UI Pending Migration" |
| `frontend/lib/app/providers/auth_notifier.dart`                                  | Auth orchestration (moved from presentation)                                    |
| `frontend/lib/app/providers/staff_assignable_branches_provider.dart`             | Branch list provider (moved from presentation)                                  |
| `frontend/lib/features/settings/application/idle_timeout_settings_notifier.dart` | Idle timeout settings (moved from presentation)                                 |
| `frontend/lib/features/auth/application/bootstrap_notifier.dart`                 | Clinic bootstrap orchestration (moved from presentation)                        |
| `frontend/lib/features/auth/application/provisioning_notifier.dart`              | Staff provisioning orchestration (moved from presentation)                      |
| `frontend/lib/features/*/application/*_rpc_messages.dart`                        | User-facing RPC error copy (moved from presentation)                            |

## Routes Replaced with Placeholders

All 40+ routes in `frontend/lib/app/router.dart` now render `UiPendingPlaceholderPage` with the appropriate feature label:

- **Startup:** `/startup-check`, `/`, `/setup-guidance`, `/protected-blocked`, `/protected/dashboard`
- **Auth:** `/login`, `/forgot-password`, `/bootstrap`, `/staff/create`, `/staff/reset-password`, `/home`
- **Foundation Demo:** `/foundation-demo`
- **Patients:** `/patients`, `/patients/new`, `/patients/:id`, `/patients/:id/edit`
- **Appointments:** `/appointments`, `/appointments/book`, `/appointments/queue`, `/appointments/calendar`, `/appointments/schedule/:doctorId`
- **Visits:** `/visits/:visitId/document`, `/visits/:visitId/detail`
- **Billing:** `/billing/invoices`, `/billing/invoices/:id`, `/billing/invoices/:id/edit`, `/billing/insurance-providers`, `/settings/billing`
- **Shifts:** `/shifts/calendar`, `/shifts/new`, `/shifts/:shiftId`
- **Settings:** `/settings`, `/settings/idle-timeout`, `/settings/organization`, `/settings/branches`, `/settings/branches/new`, `/settings/branches/:id/edit`, `/settings/staff`, `/settings/staff/new`, `/settings/staff/:id`, `/settings/staff/:id/reset-password`, `/settings/permissions`

## Files Deleted (by category)

### Feature presentation layers (entire directories)

- `frontend/lib/features/foundation_demo/` (feature removed)
- `frontend/lib/features/shifts/presentation/`
- `frontend/lib/features/visits/presentation/`
- `frontend/lib/features/billing/presentation/`
- `frontend/lib/features/appointments/presentation/`
- `frontend/lib/features/patients/presentation/`
- `frontend/lib/features/settings/presentation/`
- `frontend/lib/features/auth/presentation/`
- `frontend/lib/features/startup/presentation/`

### Design system & shell UI

- `frontend/lib/core/widgets/` (18 component files)
- `frontend/lib/app/widgets/shell_status_bar.dart`

### UI-specific tests

- `frontend/test/widget/` (entire directory, ~70 files)
- UI-focused integration tests (appointments acceptance, billing flows, shifts, visits, patient management, auth sign-in UI, startup degraded/web bootstrap, settings acceptance)
- Presentation notifier unit tests (calendar/queue providers, invoice editors, visit documentation notifiers, patient list notifiers, role permissions notifier, dev seed services)

**Approximate diff:** ~308 files changed, ~45,000 lines removed.

## Broken References Fixed

| Area                                              | Fix                                                                                     |
| ------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `frontend/lib/app/router.dart`                    | All page imports replaced with `uiPendingPlaceholder()`                                 |
| `frontend/lib/app/app.dart`                       | Updated imports for `auth_notifier`, `idle_timeout_settings_notifier`                   |
| `frontend/lib/app/shell/authenticated_shell.dart` | Simplified to passthrough child (NavigationRail removed)                                |
| Unit test imports                                 | RPC messages → `application/`; auth providers → `app/providers/` or `auth/application/` |
| Integration route tests                           | Assertions updated for placeholder text instead of removed screen copy                  |
| `frontend/pubspec.yaml`                           | Removed unused UI-only deps: `calendar_view`, `file_picker`, `printing`, `pdf`          |

## Preserved Layers

- All `domain/` and `data/` directories per feature
- `frontend/lib/core/auth/`, `frontend/lib/core/rpc/`, `frontend/lib/core/config/`, etc.
- `frontend/lib/app/app_routes.dart`, `frontend/lib/app/navigation/app_navigator.dart`
- `frontend/lib/app/providers/` (session, repository, theme, connectivity)
- `frontend/lib/l10n/`
- `frontend/test/unit/` (domain/data tests)
- `frontend/test/boundary/` (requires live Supabase; unchanged)
- `frontend/test/integration/` (route guard and redirect tests retained and updated)

## Remaining UI Artifacts (intentional minimal shell)

| Artifact                                                         | Reason kept                                             |
| ---------------------------------------------------------------- | ------------------------------------------------------- |
| `frontend/lib/app/presentation/ui_pending_placeholder_page.dart` | Required placeholder per migration spec                 |
| `frontend/lib/app/theme/` (`app_theme.dart`, `app_colors.dart`)  | `MaterialApp` theming for runnable app                  |
| `frontend/lib/app/app.dart`                                      | Root `MaterialApp.router` + Riverpod bootstrap          |
| `frontend/lib/app/session_activity_scope.dart`                   | Idle-timeout pointer/keyboard tracking (infrastructure) |
| `frontend/lib/main.dart`                                         | App entry point                                         |

No feature screens, widgets, design-system components, or presentation providers remain outside the intentional placeholder and app shell.

## Dependencies Removed

- `calendar_view` — calendar UI only
- `file_picker` — visit attachment UI only
- `printing` / `pdf` — receipt print preview UI only

## Verification Commands

```bash
cd frontend
flutter analyze lib/
flutter test test/unit test/integration
flutter build linux --debug
```

## Next Steps for UI Rebuild

1. Reintroduce feature `presentation/` folders one feature at a time.
2. Replace placeholder route builders in `router.dart` with new screens.
3. Restore `AuthenticatedShell` navigation rail or new shell design.
4. Re-add design system under `core/widgets/` or a new design package.
5. Reintroduce widget/integration tests alongside new UI.
