# Appointments Feature — Second Cycle Integration Review

**Review date:** 2026-07-05  
**Scope:** Cross-cutting integration — routing, auth guards, permissions, shell, dev seed, auth-feature architecture parity, test execution, status-rule duplication across layers  
**Prior review:** [appointments-feature-code-review.md](./appointments-feature-code-review.md) (cycle 1)

---

## Executive Summary

- **Unit tests pass (300/300)** under `test/unit/appointments/`; **boundary tests fail to load** without a live Supabase harness — integration/CI coverage for live RPC scenarios is blocked in the default `flutter test` run.
- **All six appointment routes remain placeholders** in `router.dart`; `AppointmentDetailRouteExtra` exists but is **not wired** into any route builder — preview hydration is unvalidated end-to-end.
- **Permission model is route-centric only:** `AuthRouteGuard` gates navigation, but **queue/calendar providers and shell warm** use `PermissionService` directly (no `setupRequired` check) and **never verify appointment grants before RPC/realtime**; only `appointmentDetailProvider` mirrors the guard.
- **Architecture still diverges from auth:** no `domain/repositories/appointment_repository.dart`, no use cases, no `appointment_use_case_providers.dart`; dev seed and patient history call the **concrete data repository** directly.
- **Status/lifecycle rules now confirmed in 5+ locations** including `dev_clinic_seed_schedule.dart` `advancementPathTo`, which uses a different advancement path than domain `canTransitionTo` / `forwardStatusTargetFor`.
- **First-cycle critical blockers remain unresolved** (placeholder UI, refresh races, missing CA seams, realtime insert fallback, Syncfusion in domain, dev password in domain).

| Severity | Count (cycle 2) |
|----------|-----------------|
| Critical | 3 |
| High | 7 |
| Medium | 6 |

---

## Critical Issues

### C2-1. All appointment routes remain placeholders — no UI integration

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `frontend/lib/app/router.dart` (lines 76–98) |
| **Evidence** | Six `GoRoute` entries under `/appointments/*` all call `uiPendingPlaceholder('Appointments', state)`. No imports from `features/appointments/presentation/` except providers. `AppointmentDetailRouteExtra` is never referenced in the router. |
| **Why** | Cycle 1 finding §1.1; cycle 2 confirms no progress. Router is the integration seam between shell nav and feature presentation — it is still a stub. |
| **Impact** | Cannot validate navigation extras, permission-denied empty states, error/retry UX, or drag-reschedule in widget tests. Production ship blocker. |
| **Recommended solution** | Implement screens; wire `AppointmentDetailRouteExtra.fromExtra(state.extra)` on detail route; add widget tests per route. |

---

### C2-2. Presentation still bypasses domain — no repository interface or use cases (auth parity gap)

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `appointment_queue_provider.dart`, `appointment_calendar_provider.dart`, `appointment_detail_provider.dart`, `patient_detail_history_provider.dart`, `dev_clinic_seed_notifier.dart`, `dev_clinic_seed_service.dart`; contrast `features/auth/domain/repositories/auth_repository.dart`, `features/auth/domain/usecases/`, `auth_use_case_providers.dart` |
| **Evidence** | All appointment providers `ref.read(appointmentRepositoryProvider)` on the **concrete** `AppointmentRepository` in `data/`. Auth exposes `abstract class AuthRepository` + five use cases wired via `auth_use_case_providers.dart`. Appointments have zero `domain/usecases/` and zero `domain/repositories/`. |
| **Why** | Integration points (shell warm, dev seed, patient timeline) all depend on data-layer concrete types, cementing upward dependencies before UI lands. |
| **Impact** | Mutation orchestration (status RPC → queue patch → calendar invalidate → RPC message) cannot live in use cases; every integration surface couples to Supabase-shaped fakes. |
| **Recommended solution** | Add `domain/repositories/appointment_repository.dart` (abstract port) and use cases mirroring auth; move `appointmentRepositoryProvider` to composition root; refactor providers and dev seed to depend on use-case providers. |

---

### C2-3. Unserialized concurrent `refresh()` — integration-triggered races still present

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `appointment_queue_provider.dart` (`refresh`, `_onRealtimeChange`), `appointment_calendar_provider.dart` (`refresh`), `authenticated_shell.dart` (eager warm) |
| **Evidence** | Shell `appointmentQueueShellWarmProvider` always watches `appointmentQueueCheckedInCountProvider`, which drives `appointmentQueueProvider.build()` → `Future.microtask(refresh)` + realtime subscribe. Realtime apply returning `false` calls `unawaited(refresh())`. No generation token or single-flight guard in either controller. |
| **Why** | Cycle 1 §1.2; cycle 2 confirms shell integration **amplifies** the race surface by keeping the queue hot for the entire session. |
| **Impact** | Stale queue/calendar data under concurrent realtime events, branch switches, and auth scope updates — worse because shell warm prevents provider disposal. |
| **Recommended solution** | Single-flight `refresh()` with monotonic generation; debounce realtime-triggered refresh; gate shell warm (see H2-1). |

---

## High Priority Issues

### H2-1. Shell warm uses `PermissionService` without `setupRequired` — diverges from `AuthRouteGuard`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `authenticated_shell.dart` (lines 25–27), `permission_service.dart` (`canAccessAppointments`), `auth_route_guard.dart` (`canAccessAppointmentHub`, lines 83–87) |
| **Evidence** | Shell: `ref.watch(permissionServiceProvider).canAccessAppointments()` — checks only `appointments.create|cancel|read` grants + branch assignment. `AuthRouteGuard.canAccessAppointmentHub` additionally requires `!auth.context!.setupRequired`. During bootstrap (`setupRequired: true`), a user with appointment grants still triggers queue warm, 2× `list_appointments`, and Supabase realtime subscription. |
| **Why** | Two different “can access appointments” definitions in the same app layer; route guard blocks navigation but shell side-effects proceed. |
| **Impact** | Wasted RPC/realtime during clinic setup; potential errors against incomplete backend state; inconsistent with route redirect to `/bootstrap`. |
| **Recommended solution** | Shell warm should call `AuthRouteGuard.canAccessAppointmentHub(auth)` (or shared helper) and also require `activeBranchId != null`. |

---

### H2-2. Queue and calendar providers lack permission guards before data fetch

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_provider.dart`, `appointment_calendar_provider.dart`; contrast `appointment_detail_provider.dart` (lines 13–16), `visit_detail_provider.dart` (permission-aware view state) |
| **Evidence** | Queue/calendar controllers call `listAppointments` on build/refresh with no permission check. Only `appointmentDetailProvider` uses `AuthRouteGuard.canAccessAppointmentHub`. `patchAppointmentStatus` mutates cached state with no permission gate. Visits feature exposes `VisitDetailViewState` with `canEditDocumentation` flags derived from `permissionServiceProvider`. |
| **Why** | Route redirects protect navigation, not provider reads. Shell warm, cross-feature invalidation, or future deep links can invoke providers outside guarded navigation. |
| **Impact** | Staff without appointment grants could trigger RPCs if a provider is watched; when UI lands, optimistic `patchAppointmentStatus` is callable without client-side permission enforcement. |
| **Recommended solution** | Early-return empty state in queue/calendar `build()` when hub access denied; add `canMutateQueue` / `canBook` flags on state objects mirroring visits pattern; gate `patchAppointmentStatus` on appropriate grants. |

---

### H2-3. `canAccessAppointmentCancelActions` defined but never integrated

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `auth_route_guard.dart` (lines 97–102); no call sites in `lib/` outside the definition |
| **Evidence** | `AuthRouteGuard.canAccessAppointmentCancelActions` wraps `PermissionService.canCancelAppointments()` but is **never** used in `appointmentRouteRedirect`, providers, or shell. No permission key exists for status progression (check-in, start visit) or reschedule — only `appointments.create`, `appointments.cancel`, `appointments.read`. |
| **Why** | Cancel-only staff can access queue/calendar routes (hub = any of three grants) but product will need differentiated action visibility; the guard hook exists but is orphaned. |
| **Impact** | When UI ships, cancel/no-show vs check-in/start buttons have no client permission seam; read-only users may see mutation affordances until server RPC rejects with `FORBIDDEN`. |
| **Recommended solution** | Wire cancel guard into future action buttons; document server-side permission matrix; consider `appointments.manage` or reuse `create` for status transitions; expose flags on queue/calendar state. |

---

### H2-4. `patientUpcomingAppointmentsProvider` fetches appointments without appointment permission check

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `features/patients/presentation/providers/patient_detail_history_provider.dart` (lines 65–84) |
| **Evidence** | `patientUpcomingAppointmentsProvider` calls `appointmentRepositoryProvider.listAppointments` with a 365-day window and four active statuses. No `AuthRouteGuard`, `PermissionService`, or `appointments.read` check. Patient routes allow in-page permission denial for list access, but this provider always fetches when watched. |
| **Why** | Cross-feature integration bypasses appointment permission model entirely. |
| **Impact** | Staff with `patients.read` but no appointment grants still invoke `list_appointments` on patient detail; server may return `FORBIDDEN` as unhandled `AsyncError`, or leak data if server is permissive. |
| **Recommended solution** | Guard provider with `canAccessAppointmentHub` or `appointments.read`; return empty list when denied; add test in patients or appointments test suite. |

---

### H2-5. Shell navigation shows Appointments to all authenticated users

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shell_nav_config.dart` (lines 36, 102–103), `authenticated_shell.dart`, `app_sidebar.dart` (via static `ShellNavConfig.groups`) |
| **Evidence** | `ShellNavConfig.groups` always includes `{id: 'appointments', label: 'Appointments'}`. No permission filtering in shell nav (grep: zero `canAccess` in `app/shell/navigation/`). Users without appointment grants see the nav item; `appointmentRouteRedirect` sends them to `/home` on click. |
| **Why** | Integration UX inconsistency — billing/shift routes have route-level guards but nav is not permission-aware for appointments. |
| **Impact** | Confusing UX (visible link → home redirect); differs from visits detail pattern where permissions shape view state in-page. |
| **Recommended solution** | Filter clinical nav items using `AuthRouteGuard.canAccessAppointmentHub` (or hide queue badge sub-link separately). |

---

### H2-6. Cross-surface invalidation incomplete; setup/dev-seed integration untested

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_surface_invalidation.dart`, `setup_notifier.dart`, `dev_clinic_seed_notifier.dart`; `test/unit/setup/setup_notifier_test.dart` (no `invalidateAppointment` references) |
| **Evidence** | `invalidateAppointmentSurfaceProviders` invalidates queue, calendar, shift lookup only — not `appointmentDetailProvider`, `patientUpcomingAppointmentsProvider`, `appointmentCalendarBranchesProvider`, `appointmentCalendarDoctorsProvider`. Called from setup notifier and dev seed notifier. No test asserts invalidation after setup complete or dev seed. |
| **Why** | Cycle 1 §3.13; cycle 2 confirms both integration call sites exist but test coverage gap remains. |
| **Impact** | After clinic wipe/re-seed or setup completion, stale appointment detail, patient upcoming list, and calendar filter dropdowns may persist in memory. |
| **Recommended solution** | Extend invalidation helper; add setup_notifier and dev_clinic_seed_notifier integration tests asserting provider invalidation. |

---

### H2-7. Boundary tests cannot run in default test suite (Supabase harness required)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `test/boundary/appointments/appointment_repository_boundary_test.dart`, `test/boundary/harness/live_supabase_harness.dart` |
| **Evidence** | `flutter test test/unit/appointments/ test/boundary/appointments/` → **300 passed, 1 failed to load**: `You must initialize the supabase instance before calling Supabase.instance`. Boundary manifest documents create/cancel/reschedule scenarios that only run with live harness. |
| **Why** | Integration test infrastructure is disconnected from standard CI `flutter test` invocation. |
| **Impact** | Documented boundary scenarios (create, cancel, reschedule, FORBIDDEN) provide false confidence if CI only runs unit folder; regressions in live RPC contracts may slip through. |
| **Recommended solution** | Separate CI job with harness init, or skip boundary tests with `@Tags(['integration'])` and document required command; ensure manifest scenarios run in nightly pipeline. |

---

## Medium Priority Issues

### M2-1. `AppointmentDetailRouteExtra` unwired — navigation integration gap

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_detail_route_extra.dart`, `router.dart` |
| **Evidence** | Route extra parser supports `AppointmentListItem` preview for calendar→detail navigation. Detail `GoRoute` builder ignores `state.extra` and renders placeholder. Zero tests for `fromExtra`. |
| **Why** | Presentation navigation shim exists without router consumer. |
| **Impact** | Calendar→detail flow will flash loading or lose preview data when UI is implemented. |
| **Recommended solution** | Pass extra into detail page; add unit test for `fromExtra` legacy path. |

---

### M2-2. No go_router integration tests for appointment redirect chain

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `router.dart`, `auth_route_guard.dart`; tests: `auth_route_guard_appointments_test.dart`, `app_routes_appointments_test.dart` only |
| **Evidence** | Guard methods tested in isolation. No test drives `appRouterProvider` redirect with `StartupSessionState` + `AuthSessionState` combinations for appointment paths (unauthenticated → login, setupRequired → bootstrap, no grant → home, book without create → home). |
| **Why** | Router redirect logic spans startup, setup, and auth — unit guard tests do not prove end-to-end redirect composition. |
| **Impact** | Regressions in redirect ordering (e.g. protected-route block vs appointment redirect) may go unnoticed. |
| **Recommended solution** | Add `appointment_router_redirect_test.dart` using `GoRouter` test helper with provider overrides. |

---

### M2-3. Dev seed duplicates status advancement rules (5th lifecycle location)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `dev_clinic_seed_schedule.dart` (`advancementPathTo`, lines 361–378), `dev_clinic_seed_service.dart` (`_applyAppointmentTarget`); domain: `appointment_status.dart`, `appointment_status_transitions.dart`, `appointment_status_day_rules.dart` |
| **Evidence** | `advancementPathTo` builds paths like `[confirmed, checkedIn, inProgress]` skipping `scheduled`, and uses `confirmed` as first step for most targets. Domain `forwardStatusTargetFor` and `canTransitionTo` matrix differ. Dev seed calls `updateAppointmentStatus` in a loop without day-gate or doctor-busy checks. |
| **Why** | Cycle 1 counted 4+ domain/data locations; dev tooling adds a 5th independent encoding. |
| **Impact** | Seeded data may not reflect real client transition rules; false QA confidence from demo data. |
| **Recommended solution** | Reuse domain `forwardStatusTargetFor` / lifecycle policy in dev seed; or document dev-only divergence explicitly. |

---

### M2-4. Dev seed and composition root mirror auth anti-pattern at scale

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `dev_clinic_seed_notifier.dart` (imports 7 concrete `data/*_repository.dart` files), `dev_clinic_seed_service.dart` |
| **Evidence** | `DevClinicSeedService` constructor takes concrete `AppointmentRepository`, not a port. Notifier wires repositories from data-layer providers. Auth dev tooling is lighter; auth use cases are the intended seam. |
| **Why** | Largest cross-feature integration script bypasses the (missing) appointment use-case layer. |
| **Impact** | Dev seed becomes second composition root; changes to repository signature require dev seed updates without use-case buffering. |
| **Recommended solution** | After use cases exist, inject `CreateAppointment`, `UpdateAppointmentStatus`, etc. into dev seed service. |

---

### M2-5. `authenticated_shell` appointment warm has no widget/integration test

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `authenticated_shell.dart`, `appointment_queue_provider_test.dart` (shell warm provider tested in isolation only) |
| **Evidence** | Queue test reads `appointmentQueueShellWarmProvider` directly. No test builds `AuthenticatedShell` with permission on/off and asserts warm behavior or absence. |
| **Why** | Integration between shell permission check and queue provider is untested at widget level. |
| **Impact** | Regressions in shell gating (H2-1) won't be caught. |
| **Recommended solution** | Widget test with `ProviderScope` overrides: user with/without grants, `setupRequired` true/false. |

---

### M2-6. Status filter and calendar visibility rules still split across provider vs domain

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_calendar_provider.dart` (`refresh` never passes `statuses`), `appointment_calendar_display.dart` (`filterVisibleAppointments`, `isHiddenOnCalendar`), `appointment_queue_realtime_apply.dart` (cancel removes, no-show keeps) |
| **Evidence** | Cross-layer table from cycle 1 re-validated: calendar provider stores unfiltered `items`; domain filter must be applied by UI; realtime apply encodes queue-specific visibility (cancelled → remove) independent of calendar hide rules. |
| **Why** | Integration contract between provider state and domain display helpers is implicit. |
| **Impact** | Future calendar widgets binding `state.items` show cancelled/no-show rows; queue and calendar disagree on terminal status visibility. |
| **Recommended solution** | Expose `filteredItems` on `AppointmentCalendarState`; document queue vs calendar terminal-status policy in one lifecycle module. |

---

## Test Execution Summary

| Suite | Command | Result |
|-------|---------|--------|
| Unit appointments | `flutter test test/unit/appointments/` | **300 passed** |
| Boundary appointments | `flutter test test/boundary/appointments/` | **Failed to load** (Supabase not initialized) |
| Combined (as instructed) | `flutter test test/features/appointments/` | Path does not exist; correct path is `test/unit/appointments/` |

**Provider test coverage (re-validated):**

| Provider | Test file | Critical paths untested |
|----------|-----------|-------------------------|
| `appointmentQueueProvider` | Yes | Branch change + resubscribe, concurrent refresh race, permission deny |
| `appointmentCalendarProvider` | Yes | Branches/doctors providers, error catch, doctor RPC param |
| `appointmentDetailProvider` | **No** | Permission deny, success fetch |
| `appointmentQueueShiftDoctorLookupProvider` | **No** | Full shift resolution flow |
| `appointmentQueueShellWarmProvider` | Partial (isolation only) | Shell integration, setupRequired gate |
| `invalidateAppointmentSurfaceProviders` | **No** | — |
| `patientUpcomingAppointmentsProvider` | Patients tests only | Appointment permission deny |

---

## Architecture vs Auth — Re-validation

| Seam | Auth (reference) | Appointments (current) | Status |
|------|------------------|------------------------|--------|
| Repository interface | `domain/repositories/auth_repository.dart` | Missing | **Open** |
| Use cases | 5 in `domain/usecases/` | None | **Open** |
| Use-case providers | `auth_use_case_providers.dart` | None | **Open** |
| Presentation → domain | Via use cases | Direct to `appointmentRepositoryProvider` | **Open** |
| Permission-aware detail | N/A (auth is login) | Partial — detail only; visits has richer pattern | **Gap** |
| Route guards | `AuthRouteGuard` | Appointments covered + tested | **OK** |
| Shell integration | N/A | Warm + nav; permission gaps (H2-1, H2-5) | **Gap** |

---

## First-Cycle Issue Triage

| Disposition | Count | Notes |
|-------------|-------|-------|
| **New in cycle 2** | 9 | H2-1, H2-2, H2-3, H2-4, H2-5, H2-7, M2-1, M2-2, M2-5 (+ dev seed lifecycle M2-3) |
| **Confirmed still open** | 28 | All 6 critical + majority of high/medium from cycle 1 re-validated unchanged |
| **Resolved since cycle 1** | 0 | No code changes detected in integration paths reviewed |

---

*Second cycle integration review — 2026-07-05.*
