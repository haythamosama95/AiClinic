# Flutter App Feature — Second Cycle Routing Review

**Review date:** 2026-07-05  
**Scope:** `router.dart`, `app_routes.dart`, `app.dart`, `app_navigator.dart`, `auth_route_guard.dart` (+ tests)  
**Methodology:** `/home/haytham/Desktop/AiClinic/docs/review/prompt.md`  
**First-cycle source:** `flutter-app-review-routing.md`, consolidated IDs from `flutter-app-feature-review.md`  
**Method:** Re-read all scoped routing files, cross-validated redirect composition, dev bypass hooks, startup FSM, and test coverage.

---

## Executive Summary

Second-cycle verification confirms the routing shell **structure remains sound** (centralized `AppRoutes`, single `GoRouter`, `refreshListenable` tied to startup/auth/setup/dev-seed). **None of the 18 first-cycle routing findings were fixed.**

Two original high-severity redirect logic bugs (H1, H2) and the auth-loading gap (H3) remain. A newly analyzed consequence of the protected-route FSM (C2-R-01) is **more severe in practice** than H1 alone: visiting any `/protected/*` path permanently locks navigation until process restart because `acknowledgeProtectedRouteBlock()` has zero call sites.

| Category | First-cycle | Fixed | Still open | New this cycle |
|----------|-------------|-------|------------|----------------|
| Critical | 0 | 0 | 0 | 0 |
| High | 6 | 0 | 6 | 4 |
| Medium | 12 | 0 | 12 | 2 |
| Test gaps (routing scope) | 3 | 0 | 3 | 3 |

**Totals open:** 0 Critical, **10 High** (6 confirmed + 4 new), **14 Medium** (12 confirmed + 2 new).

**Verdict:** Do not wire real feature pages or expand the route table until Phase 1 redirect fixes land and router integration tests exist.

---

## First-Cycle Triage

Re-verified on 2026-07-05. Every item below remains unfixed.

### High

| ID | Title | Status | Evidence (second pass) |
|----|-------|--------|------------------------|
| **H1** | Authorized users cannot reach `/protected/*` — missing `return null` | **STILL OPEN** | After `canAccessProtectedFeatureRoute(auth)` succeeds, router still falls through to `blockProtectedRoute` + `return AppRoutes.protectedBlocked` with no `return null`. See ```209:226:frontend/lib/app/router.dart```. |
| **H2** | `isBootstrapWizardInProgress` defaults `true` on cold start | **STILL OPEN** | `SetupUiState` defaults to `SetupWizardStep.organization` → wizard always "in progress" on cold start. `markSetupComplete()` not called on session restore. Guard allows `/bootstrap` when wizard in progress (```509:513:frontend/lib/core/auth/auth_route_guard.dart```). |
| **H3** | Auth `loading`/`unknown` skips redirects — brief unauthorized exposure | **STILL OPEN** | `AuthRouteGuard._resolveRedirect` returns `null` for `unknown`/`loading` (```485:487:frontend/lib/core/auth/auth_route_guard.dart```). Router has no global loading gate; `initialLocation` is `/home`; bootstrap runs in microtask after first frame (`app.dart` lines 29–33). |
| **H7** | All routes wrapped in `AuthenticatedShell` — including login/bootstrap | **STILL OPEN** | `ShellRoute` builder always returns `AuthenticatedShell` (```38:39:frontend/lib/app/router.dart```). Pre-auth flows show full clinic chrome. |
| **H9** | `showPatientRegister()` always returns `null` | **STILL OPEN** | ```45:48:frontend/lib/app/navigation/app_navigator.dart``` — push result discarded. |
| **H16** | Router hardcodes service catalog edit path | **STILL OPEN** | Router uses literal `path: '/settings/services/:serviceId/edit'` (```134:137:frontend/lib/app/router.dart```) while `AppRoutes.settingsServiceEdit(serviceId)` exists separately. |

#### H1 — Evidence detail

When configuration is valid and the user passes auth + permission checks for a protected route, the router **never** returns `null` to allow rendering:

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

`AuthRouteGuard.resolveRedirect` returns `null` for authenticated, setup-complete users on `/protected/*`, but the router always reaches `return AppRoutes.protectedBlocked`.

---

#### H2 — Evidence detail

```36:36:frontend/lib/features/setup/presentation/providers/setup_notifier.dart
enum SetupWizardStep { organization, branch, staff, complete }
```

```112:113:frontend/lib/features/setup/presentation/providers/setup_notifier.dart
  bool get isBootstrapWizardInProgress => step != SetupWizardStep.complete;
```

Default `build()` returns `const SetupUiState()` with step `organization`. On cold start, `/bootstrap` is allowed even when `auth.context.setupRequired == false` because the guard checks wizard UI state, not session setup flag.

---

#### H3 — Evidence detail

```485:487:frontend/lib/core/auth/auth_route_guard.dart
    if (auth.status == AuthSessionStatus.unknown || auth.status == AuthSessionStatus.loading) {
      return null;
    }
```

While auth is resolving, feature routes can render inside `AuthenticatedShell` before permission redirects in the second `unauthenticatedEntry` block apply — and when auth is `unknown`, the first switch branch sends non-pre-auth paths to `/home` instead of a loading route (see C2-R-03).

---

#### H7 — Evidence detail

Login, forgot-password, bootstrap, startup, and all feature routes share one `ShellRoute` with `AuthenticatedShell` — sidebar, top bar, branch switcher, and appointment queue warm all run on auth pages.

---

#### H9 — Evidence detail

```44:48:frontend/lib/app/navigation/app_navigator.dart
  /// Navigates to patient registration; returns when the route is popped.
  Future<String?> showPatientRegister() async {
    await _context.push<String?>(AppRoutes.patientsNew);
    return null;
  }
```

Documented contract promises a return value; implementation always yields `null`.

---

#### H16 — Evidence detail

Path duplication between router registration and `AppRoutes` builder risks drift on refactor; `AuthRouteGuard.isServiceCatalogRoute` uses prefix matching today but deep links depend on exact path consistency.

---

### Medium

| ID | Title | Status | Evidence (second pass) |
|----|-------|--------|------------------------|
| **M1** | Side effect inside `GoRouter.redirect` — `blockProtectedRoute` | **STILL OPEN** | Redirect mutates `startupSessionProvider` (```222:225:frontend/lib/app/router.dart```), triggering `refreshSignal++` and re-evaluation. |
| **M2** | Duplicated unauthenticated-entry redirect logic (~80 lines) | **STILL OPEN** | Switch branch (```233:257:frontend/lib/app/router.dart```) overlaps second block (```264:314:frontend/lib/app/router.dart```). |
| **M3** | `AppNavigator` missing navigation for registered routes | **STILL OPEN** | No methods for service catalog edit, shifts, billing insurance, settings billing, etc. |
| **M4** | `AppNavigator` has zero consumers | **STILL OPEN** | No imports of `app_navigator.dart` outside its definition; shell uses raw `context.go`. |
| **M5** | `startupCheck` / `startupEntry` routes effectively unreachable | **STILL OPEN** | `startupCheck` view only allows `/home`; `initialLocation` is `/home`. |
| **M6** | Route `extra` payloads lost on placeholder pages | **STILL OPEN** | `uiPendingPlaceholderPage` ignores `state.extra`. |
| **M7** | No `GoRouter.onException` / fallback for unknown paths | **STILL OPEN** | No `errorBuilder` or catch-all route registered. |
| **M20** | Startup `bootstrap()` reset does not coordinate auth session | **STILL OPEN** | `retryStartup()` resets startup state without invalidating auth listener / Supabase ready task. |

### Test Coverage (first cycle)

| ID | Gap | Status |
|----|-----|--------|
| **T1** | No tests for `appRouterProvider` / redirect composition | **STILL OPEN** — no matches for `appRouterProvider` or `router.dart` in `frontend/test/` |
| **T5** | No test for `blockProtectedRoute` side effect during redirect | **STILL OPEN** |
| **T6** | No test for `showPatientRegister` return value | **STILL OPEN** |

### Code Duplication

| ID | Description | Status |
|----|-------------|--------|
| **D1** | Unauthenticated entry redirect duplicated | **STILL OPEN** — same two-path structure in `router.dart` |
| **D7** | Forgot-password URL in router + navigator | **STILL OPEN** — redirect vs `goForgotPassword()` query string |
| **D8** | Service edit path literal vs builder | **STILL OPEN** — same as H16 |

---

## New Findings — Full Detail

### C2-R-01 — `protectedRouteBlocked` FSM locks all navigation after `/protected/*` visit

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `router.dart`, `startup_session_provider.dart` |
| **Evidence** | Visiting any `/protected/*` route calls `notifier.blockProtectedRoute(location)` (```222:225:frontend/lib/app/router.dart```), setting `currentView: StartupCurrentView.protectedRouteBlocked`. The startup switch then forces **all** locations to `/protected-blocked` (```231:232:frontend/lib/app/router.dart```). Recovery method `acknowledgeProtectedRouteBlock()` exists (```166:173:frontend/lib/app/providers/startup_session_provider.dart```) but has **zero call sites** in the codebase — no UI button, no redirect path, no test invokes it. |
| **Why** | FSM transition into `protectedRouteBlocked` is one-way from redirect side effects; no escape hatch is wired. Compounds H1: even after H1 is fixed, any accidental protected visit before fix permanently traps the session in blocked view until app restart. |
| **Impact** | User deep-links or navigates to `/protected/dashboard` once → stuck on blocked screen; cannot reach `/home`, patients, or settings without killing the app. Startup view remains `protectedRouteBlocked` across all subsequent navigations. |
| **Solution** | (1) Fix H1 — `return null` when access granted. (2) Do not mutate FSM inside redirect; compute blocked target purely. (3) Wire `acknowledgeProtectedRouteBlock()` to blocked placeholder UI action, or auto-acknowledge when leaving protected prefix. (4) Add T-C2-01 regression test. |

**Core redirect block (citation requested):**

```217:232:frontend/lib/app/router.dart
          if (!AuthRouteGuard.canAccessProtectedFeatureRoute(auth)) {
            return auth.isAuthenticated ? AppRoutes.bootstrap : AppRoutes.login;
          }
        }

        if (session.currentView != StartupCurrentView.protectedRouteBlocked) {
          notifier.blockProtectedRoute(location);
        }
        return AppRoutes.protectedBlocked;
      }

      final startupRedirect = switch (session.currentView) {
        StartupCurrentView.startupCheck => location == AppRoutes.home ? null : AppRoutes.home,
        StartupCurrentView.setupGuidance => location == AppRoutes.setupGuidance ? null : AppRoutes.setupGuidance,
        StartupCurrentView.protectedRouteBlocked =>
          location == AppRoutes.protectedBlocked ? null : AppRoutes.protectedBlocked,
```

---

### C2-R-02 — Dev seed suppresses all auth redirects

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `router.dart`, `shell_dev_integration.dart`, `dev_clinic_seed_notifier.dart` |
| **Evidence** | ```199:201:frontend/lib/app/router.dart``` — when `shellDevSuppressAuthRedirect(ref, auth)` is true, redirect returns `null` immediately, **before** startup FSM, protected-route block, and all permission guards. Suppression predicate (```47:53:frontend/lib/app/shell/dev/shell_dev_integration.dart```): `kDebugMode && auth.isAuthenticated && devClinicSeedProvider.inProgress`. |
| **Why** | Intended to keep seed on current page during multi-minute dev operation, but bypasses the entire auth stack. |
| **Impact** | During seed, expired JWT, permission loss, or setup-state changes do not redirect; user interacts with stale protected UI under `AbsorbPointer` overlay. Masks real session problems during the highest-risk dev operation. |
| **Solution** | Suppress only bootstrap/setup redirects, not auth-failure or permission redirects. Abort seed on sign-out or auth error. Narrow suppression to routes required for seed progress display. |

---

### C2-R-03 — Unknown auth on protected routes redirects to `/home` not login/loading

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `router.dart`, `auth_route_guard.dart` |
| **Evidence** | When `auth.status == unknown`, `resolveAuthRedirect` returns `null` (guard lines 485–487). In `unauthenticatedEntry` switch branch, for unauthenticated users (including `unknown` where `isAuthenticated == false`): after `resolveAuthRedirect` returns null, non-pre-auth paths fall through to ```255:256:frontend/lib/app/router.dart```: `return preAuthShellRoutes.contains(location) ? null : AppRoutes.home`. A user on `/patients` or `/billing/invoices` with unknown auth is sent to **`/home`**, not `/login` or a loading splash. |
| **Why** | First switch branch treats "no redirect from guard" as "send to home" rather than "hold on loading route". Unknown auth is neither authenticated nor explicitly unauthenticated. |
| **Impact** | Cold start briefly lands unauthorized users on `/home` inside full shell instead of login or loading gate; compounds H3 flash of feature chrome. Wrong mental model for security reviewers expecting `/login`. |
| **Solution** | When `auth.status` is `unknown` or `loading`, redirect globally to `AppRoutes.startupCheck` (or dedicated splash) before unauthenticated fallthrough. Never use `/home` as implicit loading route. |

---

### C2-R-04 — Auth can remain `unknown` if Supabase not ready after startup

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `auth_session_provider.dart`, `auth_route_guard.dart`, `app.dart` |
| **Evidence** | ```96:98:frontend/lib/app/providers/auth_session_provider.dart``` — when `!SupabaseBootstrap.isReady`, `_runEnsureSupabaseReady` logs a warning and **returns early** without transitioning state from `unknown` or clearing `_ensureSupabaseReadyTask` for retry. Initial state is `AuthSessionStatus.unknown` (line 23). Guard allows navigation when unknown (C2-R-03 path). No scheduled retry unless startup state changes again. |
| **Why** | Memoized `_ensureSupabaseReadyTask` completes on no-op; rare race after startup init failure leaves auth indeterminate permanently. |
| **Impact** | Session stuck at `unknown`; sign-in may fail while router treats user as neither authenticated nor cleanly unauthenticated; redirects behave unpredictably (home fallthrough). |
| **Solution** | On Supabase-not-ready: set `unauthenticated` with actionable failure, or null task and schedule retry. Add T-C2-02 simulating valid startup + `isReady == false`. |

---

### C2-R-05 — Router refreshes on every `SetupUiState` change

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `router.dart`, `setup_notifier.dart` |
| **Evidence** | ```26:28:frontend/lib/app/router.dart``` — `ref.listen<SetupUiState>(setupNotifierProvider, (_, _) { refreshSignal.value++; })` fires on **any** wizard draft field change, not only `isBootstrapWizardInProgress`. |
| **Why** | Broad listen couples unrelated wizard edits to global redirect re-evaluation. |
| **Impact** | Extra rebuilds during bootstrap data entry; redirect closure re-run on every keystroke in setup forms; harder to debug redirect ordering. |
| **Solution** | Listen with `select((s) => s.isBootstrapWizardInProgress)` or decouple wizard drafts from router refresh entirely (H2 fix reduces reliance on wizard state). |

---

### C2-R-06 — Debug design-system open access bypasses all redirects

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `router.dart`, `shell_dev_nav.dart` |
| **Evidence** | ```195:197:frontend/lib/app/router.dart``` — `if (ShellDevNav.allowsOpenAccess(location)) return null;` runs **before** startup FSM and auth checks. ```21:21:frontend/lib/app/shell/dev/shell_dev_nav.dart``` — `allowsOpenAccess` returns true for foundation demo in `kDebugMode` regardless of auth or startup view. |
| **Why** | Debug convenience to inspect design system without login. |
| **Impact** | In debug builds, `/foundation-demo` reachable without authentication while startup view is `startupCheck` or `setupGuidance`; bypasses permission model entirely on that route. Acceptable for local dev but undocumented escape hatch; release builds still register route (M24). |
| **Solution** | Document explicitly; optionally require bootstrap-admin auth even in debug. Register design-system route only in debug builds. Add test asserting release profile denies open access (partially covered in `shell_dev_security_test.dart`). |

---

## Test Coverage Gaps

| ID | Gap | Status | Risk | Recommended test |
|----|-----|--------|------|------------------|
| **T1** | No `appRouterProvider` redirect composition tests | **STILL OPEN** | H1, H2, C2-R-01 undetected | Matrix: startup view × auth × path → expected redirect |
| **T5** | No test for `blockProtectedRoute` side effect | **STILL OPEN** | M1, C2-R-01 regressions | Assert provider mutation only when intentional; FSM escape wired |
| **T6** | No test for `showPatientRegister` return value | **STILL OPEN** | H9 silent failure | Mock `push` returning patient id; assert propagated |
| **T-C2-01** | No test for permanent `protectedRouteBlocked` lock | **NEW** | C2-R-01 | Visit `/protected/dashboard` → navigate to `/home` → assert not stuck on blocked view after ack/fix |
| **T-C2-02** | No test for auth stuck at `unknown` when Supabase not ready | **NEW** | C2-R-04 | Simulate `isReady == false` after bootstrap; assert state transitions or retries |
| **T-C2-03** | No test for unknown-auth fallthrough to `/home` | **NEW** | C2-R-03 | `unknown` auth + `/patients` → expect loading/login route, not `/home` |

**Existing positive coverage:** `frontend/test/unit/core/auth_route_guard_*.dart`, `frontend/test/integration/auth/auth_route_guard_test.dart`, `frontend/test/unit/*/app_routes_*_test.dart` — guard rules and route constants only, **not** router wiring.

**Recommended integration matrix (`test/router/app_router_redirect_test.dart`):**

| Startup view | Auth state | Path | Expected redirect |
|--------------|------------|------|-------------------|
| `startupCheck` | any | `/patients` | loading or `/home` (until H3/C2-R-03 fix) |
| `unauthenticatedEntry` | unauthenticated | `/patients` | `/login` |
| `unauthenticatedEntry` | unknown | `/patients` | loading route (**not** `/home` — C2-R-03) |
| `unauthenticatedEntry` | authenticated, setup complete | `/protected/dashboard` | `null` (after H1 fix) |
| `unauthenticatedEntry` | authenticated, setup complete | `/bootstrap` | `/home` (after H2 fix) |
| `unauthenticatedEntry` | authenticated, no invoice perm | `/billing/invoices` | `/home` |
| `protectedRouteBlocked` | any | `/home` | `/protected-blocked` until ack (C2-R-01) |
| `setupGuidance` | any | `/home` | `/setup-guidance` |

---

## Recommended Fix Order (13 items)

1. **C2-R-01 + H1 + M1** — Fix protected-route happy path (`return null`); stop mutating FSM inside redirect; wire `acknowledgeProtectedRouteBlock()` or remove blocked view.
2. **H3 + C2-R-03 + C2-R-04** — Global auth loading gate for `unknown`/`loading`; never fall through to `/home`; fix Supabase-not-ready stuck path.
3. **H2 + C2-R-05** — Sync bootstrap allowance with `auth.context.setupRequired`; narrow router listen to wizard completion flag.
4. **H9 + T6** — Return `push` result from `showPatientRegister`.
5. **C2-R-02** — Narrow dev seed redirect suppression to setup routes only.
6. **M2 + D1** — Extract single `_resolveUnauthenticatedEntryRedirect` pipeline.
7. **H7** — Split auth routes from authenticated shell chrome.
8. **H16 + D8** — Single source of truth for service edit path.
9. **M3 + M4 + D5** — Complete and adopt `AppNavigator`; migrate shell navigation.
10. **M5 + M7** — Startup splash or remove dead routes; add `errorBuilder`.
11. **M20** — Coordinate `retryStartup()` with auth listener reset.
12. **C2-R-06 + M24** — Document or restrict debug open-access bypass.
13. **T1 + T5 + T-C2-01 + T-C2-02 + T-C2-03** — Router integration test suite before expanding route table.

---

## Files Reviewed

| File | Role |
|------|------|
| `frontend/lib/app/router.dart` | `GoRouter` definition, route table, composite redirect |
| `frontend/lib/app/app_routes.dart` | Route constants and path builders |
| `frontend/lib/app/app.dart` | Root widget, bootstrap ordering, lifecycle reload |
| `frontend/lib/app/navigation/app_navigator.dart` | Typed navigation facade |
| `frontend/lib/core/auth/auth_route_guard.dart` | Auth/permission redirect rules |
| `frontend/lib/app/providers/startup_session_provider.dart` | Startup FSM + `blockProtectedRoute` |
| `frontend/lib/app/providers/auth_session_provider.dart` | Auth state consumed by redirects |
| `frontend/lib/app/shell/dev/shell_dev_integration.dart` | Dev redirect suppression |
| `frontend/lib/app/shell/dev/shell_dev_nav.dart` | Debug open-access bypass |
| `frontend/lib/features/setup/presentation/providers/setup_notifier.dart` | Bootstrap wizard state |
| `frontend/lib/app/presentation/ui_pending_placeholder_page.dart` | Route targets during migration |
| `frontend/test/**/auth_route_guard*.dart` | Guard unit/integration tests |
| `frontend/test/unit/shell/shell_dev_security_test.dart` | Dev bypass gating tests |

---

*Verified by re-reading all scoped files on 2026-07-05. No first-cycle routing finding was fixed.*
