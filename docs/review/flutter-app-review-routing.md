# App Feature Review — Routing & Navigation

**Review date:** 2026-07-05  
**Scope:** `frontend/lib/app` routing shell and navigation facade  
**Architecture:** Clean Architecture + Riverpod + go_router

---

## Summary

The routing shell is structurally sound: centralized `AppRoutes`, a single `GoRouter` with `refreshListenable` tied to startup/auth/setup, and permission redirects delegated to `AuthRouteGuard`. Most feature routes intentionally render `uiPendingPlaceholder` during UI migration.

There are **two high-severity logic bugs** in `router.dart`:

1. Authenticated, setup-complete users are **always blocked** from `/protected/*` (missing `return null` after access checks).
2. `isBootstrapWizardInProgress` defaults to `true` on every cold start, so `/bootstrap` is not redirected away after setup completes.

There is also a broken navigator API (`showPatientRegister()` always returns `null`), redirect side effects that mutate startup state inside `redirect`, duplicated unauthenticated redirect logic (~80 lines), auth loading gaps that allow brief unauthorized route exposure, and **no integration tests** for `router.dart` redirect composition.

`AuthRouteGuard` has strong unit-test coverage; end-to-end redirect behavior through `appRouterProvider` is unverified. `AppNavigator` is defined but has **zero consumers** in the codebase.

| Category | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 10 |
| Low | 7 |
| Clean Architecture violations | 2 |
| SOLID violations | 2 |
| Code duplication | 5 |
| Performance | 2 |
| Test coverage gaps | 4 |

**Recommended action:** Fix H1–H4 before wiring real feature pages. Add router integration tests before expanding the route table.

---

## Files Reviewed

| File | Role |
|------|------|
| `frontend/lib/app/app.dart` | Root widget: bootstrap ordering, lifecycle context reload, `MaterialApp.router` |
| `frontend/lib/app/router.dart` | `GoRouter` definition, route table, composite redirect |
| `frontend/lib/app/app_routes.dart` | Route constants and path builders |
| `frontend/lib/app/navigation/app_navigator.dart` | Typed navigation facade over `go_router` |
| `frontend/lib/app/presentation/ui_pending_placeholder_page.dart` | Temporary route targets |
| `frontend/lib/core/auth/auth_route_guard.dart` | Auth/permission redirect rules (imported by router) |
| `frontend/lib/app/providers/auth_session_provider.dart` | Auth state consumed by redirects |
| `frontend/lib/app/providers/startup_session_provider.dart` | Startup view machine + `blockProtectedRoute` |
| `frontend/lib/app/session_activity_scope.dart` | Idle-timeout activity tracking wrapper |
| `frontend/lib/app/shell/authenticated_shell.dart` | Shell wrapping all routes |
| `frontend/lib/app/shell/navigation/shell_nav_config.dart` | Sidebar route bindings |
| `frontend/lib/app/shell/dev/shell_dev_integration.dart` | Debug redirect bypass |
| `frontend/lib/features/setup/presentation/providers/setup_notifier.dart` | `isBootstrapWizardInProgress` source |

---

## Findings

### Critical Issues

*(None — highest issues are logic bugs classified High. `/protected/*` prefix appears transitional; impact is contained to placeholder routes today.)*

---

### High Priority

#### H1. Authorized users cannot reach `/protected/*` routes — missing `return null`

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Files** | `router.dart`, `auth_route_guard.dart`, `app_routes.dart` |

**Evidence:**

```209:226:frontend/lib/app/router.dart
      final isProtectedFeatureRoute = AuthRouteGuard.requiresProtectedSetupComplete(location);
      if (isProtectedFeatureRoute) {
        if (session.configurationStatus == StartupConfigurationStatus.valid) {
          final authTarget = resolveAuthRedirect(location);
          if (authTarget != null) {
            return authTarget;
          }

          if (!AuthRouteGuard.canAccessProtectedFeatureRoute(auth)) {
            return auth.isAuthenticated ? AppRoutes.bootstrap : AppRoutes.login;
          }
        }

        if (session.currentView != StartupCurrentView.protectedRouteBlocked) {
          notifier.blockProtectedRoute(location);
        }
        return AppRoutes.protectedBlocked;
      }
```

`AuthRouteGuard.resolveRedirect` returns `null` for an authenticated, setup-complete user on `/protected/*` (falls through after setup-complete branch). Yet `router.dart` always falls through to `blockProtectedRoute` + `protectedBlocked` when config is valid and `canAccessProtectedFeatureRoute` is true. There is no `return null`.

**Why it is a problem:** `AppRoutes.protectedPlaceholder` (`/protected/dashboard`) is registered with a builder, but no authenticated user can ever reach it. `AuthRouteGuard` and router disagree on the happy path.

**Impact:** Dead route; deep links to `/protected/*` always land on `/protected-blocked` even for fully authorized sessions. Future protected features behind this prefix cannot ship without fixing redirect logic.

**Recommended solution:** After the `canAccessProtectedFeatureRoute` check succeeds, `return null`. Only call `blockProtectedRoute` when config is invalid or auth/setup is insufficient:

```dart
if (!AuthRouteGuard.canAccessProtectedFeatureRoute(auth)) {
  return auth.isAuthenticated ? AppRoutes.bootstrap : AppRoutes.login;
}
return null; // access granted — render the route
```

---

#### H2. `isBootstrapWizardInProgress` defaults `true` on cold start — `/bootstrap` redirect bypass

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Files** | `router.dart`, `setup_notifier.dart`, `auth_route_guard.dart` |

**Evidence:**

```90:91:frontend/lib/features/setup/presentation/providers/setup_notifier.dart
  const SetupUiState({
    this.step = SetupWizardStep.organization,
```

```112:113:frontend/lib/features/setup/presentation/providers/setup_notifier.dart
  bool get isBootstrapWizardInProgress => step != SetupWizardStep.complete;
```

```148:148:frontend/lib/features/setup/presentation/providers/setup_notifier.dart
  SetupUiState build() => const SetupUiState();
```

Default step is `SetupWizardStep.organization` → `isBootstrapWizardInProgress == true` on every cold start. `markSetupComplete()` is only called from dev seed tooling (`dev_clinic_seed_notifier.dart`), not from auth session restore after `finishSetup()` completes in-session.

```509:514:frontend/lib/core/auth/auth_route_guard.dart
      if (location == AppRoutes.login || location == AppRoutes.bootstrap || location == AppRoutes.forgotPassword) {
        if (location == AppRoutes.bootstrap && bootstrapStaffWizardInProgress) {
          return null;
        }
        return AppRoutes.home;
      }
```

**Why it is a problem:** Wizard UI state is used as a proxy for “user may stay on `/bootstrap`”, but it is not restored from `auth.context.setupRequired` on startup.

**Impact:** After cold start, an authenticated user with `setupRequired: false` who lands on `/bootstrap` (bookmark, back stack, manual nav) is **not** redirected to `/home`. Same-session `finishSetup()` works until app restart.

**Recommended solution:** Derive bootstrap allowance from `auth.context!.setupRequired` (and optionally active bootstrap route), not default wizard step. On auth restore when `!setupRequired`, call `markSetupComplete()` or reset wizard state. Change guard to:

```dart
final onBootstrap = location == AppRoutes.bootstrap;
final allowBootstrap = auth.context!.setupRequired || (onBootstrap && setup.isBootstrapWizardInProgress);
```

---

#### H3. `showPatientRegister()` always returns `null`

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Files** | `app_navigator.dart` |

**Evidence:**

```44:48:frontend/lib/app/navigation/app_navigator.dart
  Future<String?> showPatientRegister() async {
    await _context.push<String?>(AppRoutes.patientsNew);
    return null;
  }
```

`push<T>` result is discarded.

**Why it is a problem:** Documented contract (“returns when the route is popped”) implies a `String?` result (e.g. new patient ID). Callers cannot receive registration outcomes.

**Impact:** Silent data loss for any caller awaiting a created patient ID; hard-to-debug integration failures when registration UI is wired.

**Recommended solution:**

```dart
Future<String?> showPatientRegister() => _context.push<String?>(AppRoutes.patientsNew);
```

Ensure the registration route pops with `context.pop(newPatientId)`.

---

#### H4. Auth loading/unknown allows protected routes to render briefly

| Field | Value |
|-------|-------|
| **Severity** | High (security/UX) |
| **Files** | `auth_route_guard.dart`, `router.dart`, `app.dart` |

**Evidence:**

```485:487:frontend/lib/core/auth/auth_route_guard.dart
    if (auth.status == AuthSessionStatus.unknown || auth.status == AuthSessionStatus.loading) {
      return null;
    }
```

Router has no loading gate; `initialLocation` is `/home`. Bootstrap runs in a microtask after first frame:

```28:33:frontend/lib/app/app.dart
    Future<void>.microtask(() async {
      await ref.read(idleTimeoutSettingsProvider.future);
      await ref.read(startupSessionProvider.notifier).bootstrap();
    });
```

While `currentView == startupCheck`, redirect only forces `/home` — it does not block rendering. Permission redirects in the second `unauthenticatedEntry` block are skipped when `resolveAuthRedirect` returns `null` for unknown auth.

**Why it is a problem:** While auth is `unknown`/`loading`, feature routes can briefly render inside `AuthenticatedShell` before permission redirects apply.

**Impact:** Brief exposure of route shell/labels for unauthorized users; confusing flash on cold start; possible timing window on fast navigation before auth resolves.

**Recommended solution:** Add a startup/auth loading route or global redirect:

```dart
if (auth.status == AuthSessionStatus.unknown || auth.status == AuthSessionStatus.loading) {
  return AppRoutes.startupCheck;
}
```

Or hold `MaterialApp.router` until bootstrap + initial auth sync complete.

---

### Medium Priority

#### M1. Side effect inside `GoRouter.redirect` — `blockProtectedRoute` mutates provider state

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `router.dart`, `startup_session_provider.dart` |

**Evidence:**

```222:225:frontend/lib/app/router.dart
        if (session.currentView != StartupCurrentView.protectedRouteBlocked) {
          notifier.blockProtectedRoute(location);
        }
        return AppRoutes.protectedBlocked;
```

```157:163:frontend/lib/app/providers/startup_session_provider.dart
  void blockProtectedRoute(String attemptedLocation) {
    state = state.copyWith(
      currentView: StartupCurrentView.protectedRouteBlocked,
      blockedReason: 'Protected route `$attemptedLocation` is unavailable until authenticated workflows exist.',
    );
  }
```

`startupSessionProvider` changes trigger `refreshSignal++` (lines 20–22), re-running redirect during navigation.

**Why it is a problem:** Redirect callbacks should be pure. Mutating state inside redirect is fragile and can cause double evaluations or hard-to-reason ordering.

**Impact:** Extra rebuilds; risk of redirect loops in future edits; `blockedReason` may reflect a stale attempted location.

**Recommended solution:** Compute redirect target from session + location only. Move `blockProtectedRoute` to an explicit navigation handler or derive blocked state without mutating inside redirect.

---

#### M2. Duplicated unauthenticated-entry redirect logic (~80 lines)

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `router.dart` |

**Evidence:** Lines 233–257 (`StartupCurrentView.unauthenticatedEntry` switch branch) partially overlap lines 264–314 (second `unauthenticatedEntry` block): `resolveAuthRedirect`, `adminSettingsRedirect`, `patientRouteRedirect`, etc.

The switch branch handles coarse gating (home, login, pre-auth allowlist); the second block handles fine-grained permission redirects. However, `resolveAuthRedirect` is invoked in both paths for overlapping conditions.

**Why it is a problem:** Drift risk — one path updated, the other not.

**Impact:** Subtle redirect bugs when auth rules change.

**Recommended solution:** Extract `_resolveUnauthenticatedEntryRedirect(location, auth, session)` with a single ordered pipeline used once after the startup-view switch.

---

#### M3. All routes wrapped in `AuthenticatedShell` — including login/bootstrap

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `router.dart`, `authenticated_shell.dart` |

**Evidence:**

```37:39:frontend/lib/app/router.dart
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
```

Login, forgot-password, bootstrap, and startup routes are siblings under the same shell. `AuthenticatedShell` always renders sidebar, top bar, branch selector, and may warm appointment queue providers.

**Why it is a problem:** Pre-auth flows should not show full clinic chrome.

**Impact:** Login/setup show full clinic sidebar; confusing UX; unnecessary provider work on auth pages; sign-out button visible on login page when `auth.isAuthenticated` is false (`onSignOut: null` but chrome remains).

**Recommended solution:** Split `ShellRoute` — auth routes outside shell, or branch shell builder on `auth.isAuthenticated && !auth.context!.setupRequired`.

---

#### M4. `AppNavigator` missing navigation for registered routes

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `app_navigator.dart`, `app_routes.dart`, `router.dart` |

**Evidence:** Router registers service catalog (`settingsServices`, `settingsServicesNew`, edit), shifts (`shiftsCalendar`, `shiftsNew`, `shifts/:id`), `billingInsuranceProviders`, `settingsBilling`, visit routes with `?edit=1`. `AppNavigator` has no `goSettingsServices`, `goShifts`, `goBillingInsurance`, `goSettingsBilling`, etc.

**Why it is a problem:** Centralized navigation is incomplete; features will scatter raw `context.go()` calls.

**Impact:** Inconsistent navigation, lost `extra` payloads, harder refactors.

**Recommended solution:** Add methods mirroring `AppRoutes` builders for every registered route.

---

#### M5. Hardcoded service-edit path in router vs `AppRoutes` builder

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `router.dart`, `app_routes.dart` |

**Evidence:**

```134:137:frontend/lib/app/router.dart
          GoRoute(
            path: '/settings/services/:serviceId/edit',
            builder: (context, state) => uiPendingPlaceholder('Service Catalog', state),
          ),
```

```108:109:frontend/lib/app/app_routes.dart
  static String settingsServiceEdit(String serviceId) => '/settings/services/$serviceId/edit';
```

**Why it is a problem:** Path defined in two places; rename drift breaks deep links or guards.

**Impact:** `AuthRouteGuard.isServiceCatalogRoute` uses `startsWith('/settings/services/')` — works today, fragile on refactor.

**Recommended solution:** Use a shared path pattern constant or derive `GoRoute` path from `AppRoutes.settingsServices` + `/:serviceId/edit`.

---

#### M6. `startupCheck` / `startupEntry` routes are effectively unreachable

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `router.dart`, `startup_session_provider.dart` |

**Evidence:**

```228:229:frontend/lib/app/router.dart
        StartupCurrentView.startupCheck => location == AppRoutes.home ? null : AppRoutes.home,
```

While `currentView == startupCheck`, only `/home` is allowed; `/startup-check` and `/` redirect to `/home`. `initialLocation` is `/home`, not those paths.

**Why it is a problem:** Dead route registrations and misleading `AppRoutes` surface.

**Impact:** Confusion for deep links and tests; placeholder pages never shown for startup paths.

**Recommended solution:** Redirect to dedicated startup splash during `startupCheck`, or remove unused routes until UI exists.

---

#### M7. Route `extra` payloads passed by navigator are lost on placeholder pages

| Field | Value |
|-------|-------|
| **Severity** | Medium (during migration) |
| **Files** | `app_navigator.dart`, `ui_pending_placeholder_page.dart` |

**Evidence:** `pushPatientDetail` passes `PatientDetailRouteExtra`; placeholders ignore `state.extra`.

**Why it is a problem:** Hero transitions and list previews depend on `extra`; placeholders drop them.

**Impact:** Broken animations/previews when mixing real list UI with placeholder detail routes.

**Recommended solution:** Temporary no-op, or read `extra` in placeholders for dev validation. Ensure real pages use `PatientDetailRouteExtra.fromExtra(state.extra)`.

---

#### M8. No `GoRouter.onException` / fallback for unknown paths

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `router.dart` |

**Evidence:** `GoRouter` has no `errorBuilder`, `onException`, or catch-all route.

**Why it is a problem:** Typos or removed routes yield blank/error screens depending on platform.

**Impact:** Poor deep-link and web URL handling.

**Recommended solution:** Add `errorBuilder` redirecting to `/home` or a dedicated 404 page.

---

#### M9. Sidebar nav items without route bindings — silent no-op

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `shell_nav_config.dart`, `authenticated_shell.dart` |

**Evidence:**

```37:38:frontend/lib/app/shell/navigation/shell_nav_config.dart
        ShellNavItem(id: 'encounters', label: 'Encounters', icon: Icons.medical_services_outlined),
        ShellNavItem(id: 'workspace', label: 'Workspace', icon: Icons.assignment_outlined),
```

```50:50:frontend/lib/app/shell/navigation/shell_nav_config.dart
        ShellNavItem(id: 'reports', label: 'Reports', icon: Icons.bar_chart_outlined),
```

These item IDs are absent from `_routesByItemId`. `AuthenticatedShell` calls `ShellNavConfig.routeFor(itemId)` and only navigates when non-null:

```60:64:frontend/lib/app/shell/authenticated_shell.dart
          onNavigate: (itemId) {
            final route = ShellNavConfig.routeFor(itemId);
            if (route != null) {
              context.go(route);
            }
          },
```

**Why it is a problem:** Clickable sidebar entries with no navigation behavior.

**Impact:** Broken UX; users perceive the app as non-functional for Encounters, Workspace, and Reports.

**Recommended solution:** Disable/hide unimplemented items, or wire to placeholder routes until features ship.

---

#### M10. `AppNavigator` has zero consumers — navigation facade unused

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `app_navigator.dart`, `authenticated_shell.dart` |

**Evidence:** No file in `frontend/` imports `app_navigator.dart`. `AuthenticatedShell` uses raw `context.go(route)` instead of `context.nav`.

**Why it is a problem:** The stated goal (“avoid scattered `context.go()` calls”) is not enforced. Two parallel navigation APIs exist; only the raw one is used.

**Impact:** `AppNavigator` will drift from actual navigation patterns; H3 bug goes unnoticed; feature teams will not adopt the facade.

**Recommended solution:** Migrate `AuthenticatedShell` and first feature pages to `context.nav`; add lint rule or CI check discouraging direct `context.go` outside `app/navigation/`.

---

### Low Priority

#### L1. Duplicate methods `goDesignSystem()` and `goFoundationDemo()`

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `app_navigator.dart` |

Both call `AppRoutes.foundationDemo`. Remove one alias.

---

#### L2. `GoRouter` instance not disposed on provider teardown

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `router.dart` |

`ref.onDispose(refreshSignal.dispose)` but not `router.dispose()`. Minor if provider lives for app lifetime.

---

#### L3. `forgot-password` route is redirect-only

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `router.dart` |

```53:53:frontend/lib/app/router.dart
          GoRoute(path: AppRoutes.forgotPassword, redirect: (context, state) => '${AppRoutes.login}?forgot=1'),
```

Works if login page reads `?forgot=1` query param. `preAuthShellRoutes` uses path without query — verify login UI handles `state.uri.queryParameters`.

---

#### L4. `protectedPlaceholder` route registered but unreachable (symptom of H1)

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `router.dart`, `app_routes.dart` |

Dead builder under current redirect logic.

---

#### L5. App resume reloads context without in-flight guard

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `app.dart` |

```53:53:frontend/lib/app/app.dart
    unawaited(ref.read(authSessionProvider.notifier).reloadContext());
```

Rapid resume could overlap `refreshSessionContext()` calls. `auth_session_provider` does not serialize reloads.

---

#### L6. `goPatientRegister` vs `showPatientRegister` overlap

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `app_navigator.dart` |

Both push `patientsNew`; one returns `Future`, one `void`. Consolidate API.

---

#### L7. Bootstrap microtask lacks `mounted` guard

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `app.dart` |

```29:33:frontend/lib/app/app.dart
    Future<void>.microtask(() async {
      await ref.read(idleTimeoutSettingsProvider.future);
      await ref.read(startupSessionProvider.notifier).bootstrap();
    });
```

If the widget is disposed before the microtask completes, `ref` usage after `await` may be unsafe depending on Riverpod version/scope.

**Recommended solution:** Check `if (!mounted) return;` after each `await`, or move bootstrap to a dedicated `Provider`/`Notifier` without widget lifecycle coupling.

---

### Clean Architecture Violations

#### CA1. `core/auth/auth_route_guard.dart` imports `app/providers/auth_session_provider.dart`

| Field | Value |
|-------|-------|
| **Severity** | Medium (architectural) |
| **Files** | `auth_route_guard.dart` |

```6:6:frontend/lib/core/auth/auth_route_guard.dart
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
```

Core depends on app-layer `AuthSessionState`. Domain auth types live in `features/auth/domain`, but the guard is tied to app presentation state.

**Recommended solution:** Move `AuthSessionState` to `features/auth/application` or define a routing DTO in `core/auth` that the app provider maps to.

---

#### CA2. `AppNavigator` imports feature domain and presentation types

| Field | Value |
|-------|-------|
| **Severity** | Medium (architectural) |
| **Files** | `app_navigator.dart` |

```5:8:frontend/lib/app/navigation/app_navigator.dart
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
```

App shell navigation depends on feature domain + presentation types.

**Recommended solution:** Define route extras in `app/navigation/` or a shared `routing` module; features map to them at the presentation boundary.

---

#### CA3. `router.dart` imports feature presentation directly

| Field | Value |
|-------|-------|
| **Severity** | Low (architectural) |
| **Files** | `router.dart` |

```7:8:frontend/lib/app/router.dart
import 'package:ai_clinic/features/design_system/presentation/design_system_page.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
```

Composition root importing features is common, but couples routing to setup wizard state and design-system page. Acceptable short-term; consider route modules per feature as the table grows.

---

### SOLID Violations

#### S1. `router.dart` redirect closure violates SRP

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Files** | `router.dart` |

Single ~130-line `redirect` handles dev bypass, protected blocking, startup FSM, auth, and eight permission domains.

**Recommended solution:** `StartupRouteRedirect`, `ProtectedRouteRedirect`, compose in order.

---

#### S2. `AppNavigator` grows without interface segregation

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `app_navigator.dart` |

One class owns auth, patients, appointments, billing, visits, settings. No feature-scoped navigators.

**Recommended solution:** `PatientNavigator`, `SettingsNavigator`, or extension parts per feature.

---

### Code Duplication & Redundancy

| ID | Description | Files | Recommendation |
|----|-------------|-------|----------------|
| D1 | Unauthenticated entry redirect duplicated | `router.dart` 233–314 | Extract single pipeline function |
| D2 | `goDesignSystem` / `goFoundationDemo` | `app_navigator.dart` | Remove one alias |
| D3 | Forgot-password URL in router + navigator | `router.dart`, `app_navigator.dart` | Centralize in `AppRoutes.forgotPasswordQuery` |
| D4 | Service edit path literal vs builder | `router.dart`, `app_routes.dart` | Single source of truth |
| D5 | Parallel navigation APIs (`context.go` vs `AppNavigator`) | `authenticated_shell.dart`, `app_navigator.dart` | Enforce one API |

---

### Performance Issues

#### P1. Router refresh on every `SetupUiState` change

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `router.dart` |

```26:28:frontend/lib/app/router.dart
  ref.listen<SetupUiState>(setupNotifierProvider, (_, _) {
    refreshSignal.value++;
  });
```

Every wizard draft/step change re-evaluates all redirects globally.

**Recommended solution:** Narrow listen to `isBootstrapWizardInProgress` only, or decouple from wizard drafts.

---

#### P2. `AuthenticatedShell` warms appointment queue on all routes

| Field | Value |
|-------|-------|
| **Severity** | Low |
| **Files** | `authenticated_shell.dart` |

```25:27:frontend/lib/app/shell/authenticated_shell.dart
    if (ref.watch(permissionServiceProvider).canAccessAppointments()) {
      ref.watch(appointmentQueueShellWarmProvider);
    }
```

Runs on login/bootstrap placeholders too because of M3.

---

### Test Coverage Gaps

| ID | Gap | Risk |
|----|-----|------|
| T1 | **No tests for `appRouterProvider` / `router.dart` redirect composition** | H1, H2, startup FSM bugs undetected |
| T2 | **No test for `blockProtectedRoute` side effect during redirect** | M1 regressions |
| T3 | **No test for `showPatientRegister` return value** | H3 silent failure |
| T4 | **No test that sidebar dead items are hidden or disabled** | M9 UX regressions |

**Existing coverage:** `frontend/test/unit/core/auth_route_guard_*.dart`, `frontend/test/integration/auth/auth_route_guard_test.dart`, `frontend/test/unit/*/app_routes_*_test.dart` — guard and route constants only, not router wiring.

**Recommended test matrix for `test/router/app_router_redirect_test.dart`:**

| Startup view | Auth state | Path | Expected redirect |
|--------------|------------|------|-------------------|
| `startupCheck` | any | `/patients` | `/home` |
| `unauthenticatedEntry` | unauthenticated | `/patients` | `/login` |
| `unauthenticatedEntry` | authenticated, setup complete | `/protected/dashboard` | `null` (after H1 fix) |
| `unauthenticatedEntry` | authenticated, setup complete | `/bootstrap` | `/home` (after H2 fix) |
| `unauthenticatedEntry` | authenticated, no invoice perm | `/billing/invoices` | `/home` |
| `setupGuidance` | any | `/home` | `/setup-guidance` |

---

### Recommended Refactoring

1. **Fix H1 immediately** — add `return null` when protected access is granted.
2. **Fix H2** — tie bootstrap allowance to `auth.context.setupRequired`, sync wizard state on session restore.
3. **Fix H3** — return `push` result from `showPatientRegister`.
4. **Fix H4** — add auth-loading gate or splash route.
5. **Extract redirect pipeline** — ordered pure functions; no state mutation in redirect.
6. **Split shell routes** — auth vs authenticated chrome.
7. **Add `test/router/app_router_redirect_test.dart`** — matrix from Test Coverage Gaps.
8. **Complete and enforce `AppNavigator`** — all `AppRoutes` with correct `go` vs `push`; migrate shell navigation.
9. **Hide or wire dead sidebar items** — encounters, workspace, reports.
10. **Invert CA1** — move `AuthSessionState` out of app layer or introduce routing DTO in core.

---

## Brief Summary — Critical / High

| ID | Issue | Severity |
|----|-------|----------|
| H1 | `/protected/*` always redirects to `protectedBlocked` even when auth + setup are complete | **High** |
| H2 | `isBootstrapWizardInProgress` defaults `true` on cold start → `/bootstrap` not redirected after setup | **High** |
| H3 | `showPatientRegister()` discards `push` result, always returns `null` | **High** |
| H4 | Auth `loading`/`unknown` skips all redirects → brief unauthorized route exposure | **High** |
