# Flutter App Review — Dev Tooling & Cross-File Validation

**Date:** 2026-07-05  
**Scope:** `frontend/lib/app/` (35 files) — emphasis on `shell/dev/`, router ↔ shell ↔ session ↔ branch ↔ repository wiring, dev seed vs production paths  
**Partial reviews referenced:** None on disk (`flutter-app-review-routing.md`, `flutter-app-review-shell-ui.md`, `flutter-app-review-providers.md` were not found; this document is the primary cross-cutting pass).

---

## Cross-File Validation Summary

| Integration point | Expected contract | Actual behavior | Verdict |
|-------------------|-------------------|-----------------|---------|
| Router ↔ `ShellDevNav` | Dev routes bypass auth only in debug | `allowsOpenAccess` short-circuits redirect before auth (router.dart:195–197) | ⚠️ Debug-only; correct gating |
| Router ↔ `shellDevSuppressAuthRedirect` | Suppress redirects during seed | Suppresses all auth redirects while `devClinicSeedProvider.inProgress` (router.dart:199–201, shell_dev_integration.dart:47–53) | ⚠️ Intentional; risky if session invalidates mid-seed |
| Shell nav ↔ `ShellDevNav.footerItemIds` | Footer exposes dev actions | Sidebar only adds single `dev` item → `foundationDemo` (shell_nav_config.dart:55–62); `footerItemIds` never rendered | ❌ Broken wiring |
| `ShellDevFillDummyClinic` ↔ UI | Nav/dialog triggers seed | `handleNavSelection` / `confirmAndRun` have **zero call sites** outside their definition file | ❌ Critical gap |
| `resetDatabaseId` ↔ handler | Reset action available in dev | Label in `ShellDevNav` only; no route, no handler, no `routeFor` entry | ❌ Dead metadata |
| `branchSelectionProvider` ↔ `authSessionProvider` | Branch switch updates session scope | `selectBranch` → `setActiveBranch` mutates in-memory context only (branch_selection_notifier.dart:18–24, auth_session_provider.dart:226–232) | ⚠️ Client-only; no server persistence |
| `BranchSelectionNotifier.build` ↔ auth refresh | Re-sync after `refreshSessionContext` | `build()` watches `authSessionProvider.context` and returns `activeBranchId` | ✅ Syncs on auth refresh |
| `clearBranch()` | Clears selection on sign-out | Method exists but is **never called**; sign-out clears auth, orphaning notifier until rebuild | ⚠️ Dead / inconsistent API |
| `repository_providers.dart` ↔ dev seed | Central repo access | Barrel exports 3 repos; `DevClinicSeedService` imports 7 feature data layers directly | ⚠️ Incomplete barrel |
| `AppRoutes` ↔ `router.dart` | Single path source | Service edit uses hardcoded `'/settings/services/:serviceId/edit'` (router.dart:135) vs `AppRoutes.settingsServiceEdit` | ⚠️ Drift risk |
| `ShellNavConfig` ↔ `AppRoutes` | All nav items routable | `encounters`, `workspace`, `reports` have no `_routesByItemId` entry → `routeFor` returns null | ❌ Silent no-op clicks |
| `ShellNavConfig.itemIdForLocation` ↔ active highlight | Correct sidebar selection | `/home` matches `home` first; `dashboard` never highlights. `/billing/invoices` highlights `invoices`, not `billing` | ⚠️ UX inconsistency |
| Dev seed ↔ prod auth path | Seed respects admin gate | `kDebugMode` + `isBootstrapAdmin` checks in notifier and service | ✅ Gated |
| Dev seed ↔ `setupNotifierProvider` | Setup wizard state after seed | `markSetupComplete()` sets local wizard step only; does not refresh JWT `setup_required` (dev_clinic_seed_notifier.dart:91) | ⚠️ Local/server divergence possible until `refreshSession` completes |
| `kDebugMode` compile-out | No dev surface in release | `ShellDevShellWrapper`, overlay, nav item, router hooks all guard on `kDebugMode` | ✅ Release-safe structure |
| `AuthRouteGuard` ↔ dev open access | Guard lists `foundationDemo` as auth-required | Debug bypass happens in router **before** guard runs | ⚠️ Guard and router disagree in debug (harmless) |

---

## Dev Tooling Architecture

```
AuthenticatedShell
  └── ShellDevShellWrapper (kDebugMode → DevClinicSeedOverlay)
        └── AppShell / sidebar / topBar / child

appRouterProvider.redirect
  ├── ShellDevNav.allowsOpenAccess(location)     → null (skip all guards)
  ├── shellDevSuppressAuthRedirect(ref, auth)    → null during seed
  └── AuthRouteGuard + startup session machine

ShellNavConfig.footerItems()
  └── [settings] + [dev → /foundation-demo]   (only when kDebugMode)

ShellDevNav.footerItemIds (UNUSED in UI)
  ├── theme-showcase → /foundation-demo
  ├── fill-dummy-clinic  (NO handler wired)
  └── reset-database     (NO handler at all)

ShellDevFillDummyClinic.confirmAndRun
  └── devClinicSeedProvider.fillDummyClinic()
        └── DevClinicSeedService.run()
              ├── resetInstallationForDevelopment()
              ├── finishSetup / createBranch / provisioning RPCs
              ├── Egyptian catalog assets
              └── shifts + appointments + visits seed
```

**Production removal path** (documented in `shell_dev_integration.dart:13–17`): delete `shell/dev/`, remove three integration hooks in `AuthenticatedShell`, `router.dart`, and `ShellNavConfig`. Structure is sound; wiring is incomplete.

---

## 1. Critical Issues

### C-01 — Fill Dummy Clinic is implemented but not reachable from the shell

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `shell/dev/shell_dev_fill_dummy_clinic.dart`, `shell/dev/shell_dev_nav.dart`, `shell/navigation/shell_nav_config.dart`, `features/design_system/presentation/design_system_page.dart` |
| **Evidence** | `ShellDevFillDummyClinic.handleNavSelection` and `confirmAndRun` are defined (shell_dev_fill_dummy_clinic.dart:28–57) but ripgrep shows **no call sites** in `lib/`. Sidebar footer only navigates to `AppRoutes.foundationDemo` via item id `dev` (shell_nav_config.dart:58–60, 20). `ShellDevNav.footerItemIds` lists `fill-dummy-clinic` (shell_dev_nav.dart:23–27) but nothing renders or handles those ids. |
| **Why** | Dev tooling metadata and service layer exist without a presentation entry point. |
| **Impact** | Developers cannot run the primary dev seed workflow from the app; ~600 lines of seed logic and overlay/router integration are effectively dead in manual QA. |
| **Solution** | Wire dev actions in `AuthenticatedShell.onNavigate` or a `DesignSystemPage` dev panel: if `itemId == ShellDevFillDummyClinic.itemId` call `handleNavSelection`; add a visible dev-options sub-nav using `ShellDevNav.footerItemIds`. Add a widget test asserting the handler is invoked. |

### C-02 — “Reset Database” dev nav label with no implementation

| Field | Detail |
|-------|--------|
| **Severity** | Critical (functional completeness) |
| **Files** | `shell/dev/shell_dev_nav.dart` |
| **Evidence** | `resetDatabaseId = 'reset-database'` and label `'Reset Database'` (shell_dev_nav.dart:12–13, 43) appear in `footerItemIds` and `labelFor`, but `routeFor` has no entry, no handler exists, and `setup_notifier.resetInstallationForDevelopment()` is not referenced from app shell. |
| **Why** | Partial dev nav API was added without action wiring. |
| **Impact** | Misleading dev surface; future UI that reads `footerItemIds` will expose a broken action. Tests assert item presence (shell_dev_security_test.dart:35–36) but not executability. |
| **Solution** | Either implement reset (confirm dialog → `setupNotifier.resetInstallationForDevelopment()` + session refresh) or remove `resetDatabaseId` from `footerItemIds`/`labelFor` until implemented. |

---

## 2. High Priority Issues

### H-01 — Sidebar nav items silently do nothing

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shell/navigation/shell_nav_config.dart`, `shell/authenticated_shell.dart` |
| **Evidence** | Nav items `encounters`, `workspace`, `reports` in `groups` (shell_nav_config.dart:37–38, 50) are absent from `_routesByItemId`. `onNavigate` calls `ShellNavConfig.routeFor(itemId)` and only navigates when non-null (authenticated_shell.dart:60–64). |
| **Why** | UI presents features that do not exist in routing. |
| **Impact** | Users click nav items with no feedback; appears broken. |
| **Solution** | Remove until routes exist, disable with tooltip “Coming soon”, or route to placeholders with explicit labels. |

### H-02 — Nav active-state mismatch for duplicate route mappings

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shell/navigation/shell_nav_config.dart` |
| **Evidence** | `home` and `dashboard` both map to `AppRoutes.home` (lines 10–11). `itemIdForLocation` iterates map insertion order and returns first match → always `home` (lines 89–94). `billing` and `invoices` both map to `AppRoutes.billingInvoices` but prefix matcher returns `invoices` only (lines 105–106). |
| **Why** | Multiple labels, one route; resolution is first-wins. |
| **Impact** | Wrong sidebar highlight; undermines wayfinding during migration. |
| **Solution** | Collapse duplicate items or add `preferredActiveId` resolution; prefer longest-prefix / explicit priority list. |

### H-03 — Branch switcher displays raw branch IDs

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shell/authenticated_shell.dart`, `shell/navigation/app_branch_switcher.dart` |
| **Evidence** | Branches built as `ShellBranch(id: id, name: id, ...)` (authenticated_shell.dart:39–42). Sidebar header shows `session?.activeBranchId ?? 'Branch'` (line 58). |
| **Why** | No branch name lookup wired despite `branchRepositoryProvider` export. |
| **Impact** | Unusable branch UX for real clinics; switcher shows UUIDs. |
| **Solution** | Load branch summaries (cached provider) and map `id → name`; fall back to code, then id. |

### H-04 — Auth redirect suppression during dev seed can mask session loss

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shell/dev/shell_dev_integration.dart`, `router.dart` |
| **Evidence** | `shellDevSuppressAuthRedirect` returns true when seed `inProgress` (shell_dev_integration.dart:47–53). Router returns `null` before any auth guard (router.dart:199–201). Seed can run many minutes (patients × appointments × visits). |
| **Why** | Global redirect bypass during long async operation. |
| **Impact** | If JWT expires or staff deactivated mid-seed, user remains on protected routes with stale UI until seed ends. |
| **Solution** | Scope suppression to seed overlay routes only; or re-validate auth between seed phases; surface hard failure if `refreshSession` fails. |

### H-05 — Debug open access to design system bypasses entire auth stack

| Field | Detail |
|-------|--------|
| **Severity** | High (security hygiene) |
| **Files** | `shell/dev/shell_dev_nav.dart`, `router.dart`, `core/auth/auth_route_guard.dart` |
| **Evidence** | `allowsOpenAccess` → `kDebugMode && location == foundationDemo` (shell_dev_nav.dart:21). Router early-returns before startup/auth checks (router.dart:195–197). `AuthRouteGuard.requiresAuthentication` still lists `foundationDemo` (auth_route_guard.dart:24). |
| **Why** | Intentional dev shortcut. |
| **Impact** | Debug builds expose authenticated shell chrome and design tokens without login; acceptable locally but must never ship with `kDebugMode` true (profile/release OK). |
| **Solution** | Document in README; add CI assertion that release/profile builds redirect `foundationDemo` to login; consider `assert(kDebugMode)` in `allowsOpenAccess` call path tests. |

### H-06 — All feature routes render placeholder pages except design system

| Field | Detail |
|-------|--------|
| **Severity** | High (product readiness) |
| **Files** | `router.dart`, `presentation/ui_pending_placeholder_page.dart` |
| **Evidence** | ~40 `GoRoute` builders call `uiPendingPlaceholder(...)`; only `foundationDemo` uses `DesignSystemPage` (router.dart:60–61 vs 42–186). |
| **Why** | Migration-in-progress shell. |
| **Impact** | Router, guards, and nav complexity without user-facing features; false confidence from “routable” URLs. |
| **Solution** | Track migration status per route; remove guards for unimplemented features or gate behind feature flags. |

### H-07 — `markSetupComplete()` after dev seed may race JWT claims

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shell/dev/dev_clinic_seed_notifier.dart`, `features/setup/presentation/providers/setup_notifier.dart` |
| **Evidence** | After seed, notifier calls `markSetupComplete()` (dev_clinic_seed_notifier.dart:91) which only sets `SetupWizardStep.complete` locally (setup_notifier.dart:180–182). `refreshSession` runs inside service before return, but setup notifier is not driven by JWT. |
| **Why** | Two sources of “setup complete” truth. |
| **Impact** | Wizard UI may show complete while `auth.context.setupRequired` still true briefly; route guards may still redirect to bootstrap. |
| **Solution** | Derive setup completion from `authSessionProvider.context.setupRequired` only; remove local `markSetupComplete` from seed path or call after verified `refreshSessionContext`. |

---

## 3. Medium Priority Issues

### M-01 — Dev seed overlay ignores `progressMessage`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shell/dev/dev_clinic_seed_overlay.dart`, `shell/dev/dev_clinic_seed_notifier.dart` |
| **Evidence** | Notifier updates `progressMessage` throughout seed (e.g. dev_clinic_seed_notifier.dart:87). Overlay shows only `CircularProgressIndicator` (dev_clinic_seed_overlay.dart:23–26). |
| **Why** | Minimal overlay implementation. |
| **Impact** | Long seeds appear hung; harder to debug failures. |
| **Solution** | Display `seed.progressMessage` under spinner; show `errorMessage` on failure. |

### M-02 — `repository_providers.dart` is an incomplete facade

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `providers/repository_providers.dart`, `shell/dev/dev_clinic_seed_notifier.dart` |
| **Evidence** | Barrel exports 3 providers (repository_providers.dart:5–7). Dev seed notifier imports 7 feature repositories directly (dev_clinic_seed_notifier.dart:8–15). |
| **Why** | Partial migration to central exports. |
| **Impact** | Cross-feature imports bypass intended boundary; inconsistent DI discovery. |
| **Solution** | Expand barrel for repos used cross-feature, or document that app/dev may import feature data directly. |

### M-03 — Side-effect provider watch inside `AuthenticatedShell.build`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shell/authenticated_shell.dart`, `features/appointments/.../appointment_queue_provider.dart` |
| **Evidence** | `if (canAccessAppointments()) { ref.watch(appointmentQueueShellWarmProvider); }` in build (authenticated_shell.dart:25–27). Warm provider watches queue count (appointment_queue_provider.dart:295–297). |
| **Why** | Eager load for nav badge that is not wired to sidebar `count`. |
| **Impact** | Extra network/realtime subscription on every authenticated screen; pattern triggers work during build. |
| **Solution** | Move warm-up to `initState` of a dedicated shell listener widget; wire `ShellNavItem.count` if badge is desired. |

### M-04 — Theme mode coupled to startup session state machine

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `providers/theme_provider.dart`, `providers/startup_session_provider.dart` |
| **Evidence** | `themeModeProvider` reads `startupSessionProvider.themeMode` (theme_provider.dart:7–8). `bootstrap()` resets most state but preserves theme (startup_session_provider.dart:105–106). |
| **Why** | Pre-auth theme choice stored in bootstrap notifier. |
| **Impact** | Conceptual coupling; theme changes require startup notifier for pre-auth and `setAppThemeMode` post-auth. |
| **Solution** | Extract `ThemeModeNotifier` with persistence; startup reads initial value once. |

### M-05 — Service catalog edit route path not using `AppRoutes` helper

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `router.dart`, `app_routes.dart` |
| **Evidence** | `path: '/settings/services/:serviceId/edit'` (router.dart:135) vs `AppRoutes.settingsServiceEdit(serviceId)` (app_routes.dart:109). |
| **Why** | Copy-paste during route registration. |
| **Impact** | Path drift if constant changes; `AppNavigator` has no service-catalog methods at all. |
| **Solution** | Use parameterized route builder from `AppRoutes`; extend `AppNavigator`. |

### M-06 — `BranchSelectionNotifier.clearBranch()` is dead code

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `providers/branch_selection_notifier.dart` |
| **Evidence** | `clearBranch` sets `state = null` without updating auth (lines 26–28). No references in codebase. |
| **Why** | Incomplete sign-out integration. |
| **Impact** | Misleading API; future callers could desync branch state from auth context. |
| **Solution** | Remove or call from `signOut` path; prefer deriving branch solely from auth context. |

### M-07 — Stale integration comment references non-existent `ShellDevNavFooter`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shell/dev/shell_dev_integration.dart` |
| **Evidence** | Removal instructions cite `[ShellDevNavFooter] call site in [ShellNav]` (line 16); no such symbol exists. |
| **Why** | Renamed/refactored without updating docs. |
| **Impact** | Incorrect removal checklist. |
| **Solution** | Update comment to `ShellNavConfig.footerItems` and actual handler locations. |

### M-08 — Dev seed has no cancellation

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shell/dev/dev_clinic_seed_service.dart`, `shell/dev/dev_clinic_seed_overlay.dart` |
| **Evidence** | `run()` is one long `async` sequence with `resetInstallationForDevelopment` at start (line 90). Overlay uses `AbsorbPointer` with no cancel button. |
| **Why** | Simplicity for dev tool. |
| **Impact** | Accidental trigger cannot be aborted; partial seed after wipe leaves empty/partial DB. |
| **Solution** | Confirm dialog is present (good); add cancel between phases; disable trigger while in progress (overlay partially does this). |

---

## 4. Low Priority Issues

### L-01 — Hardcoded app version in user menu

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `shell/navigation/app_user_menu.dart` |
| **Evidence** | `appVersion = '1.0.0'` default (line 12). |
| **Impact** | Incorrect version in support scenarios. |
| **Solution** | Read from `package_info_plus` or build metadata. |

### L-02 — Duplicate theme toggle in top bar and user menu

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `shell/navigation/app_top_bar.dart`, `shell/navigation/app_user_menu.dart` |
| **Evidence** | Top bar toggle when `width >= 480` (app_top_bar.dart:121–127); menu also has “Toggle theme” (app_user_menu.dart:63–67). |
| **Solution** | Keep one surface per breakpoint. |

### L-03 — `AppNavigator.showPatientRegister` always returns null

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `navigation/app_navigator.dart` |
| **Evidence** | `push<String?>` then `return null` (lines 45–47). |
| **Solution** | Return `pop` result or remove method until registration returns an id. |

### L-04 — Sidebar collapsed state flashes expanded on cold start

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `shell/providers/shell_sidebar_collapsed_provider.dart` |
| **Evidence** | `build()` returns `false`, loads prefs in microtask (lines 9–19). |
| **Solution** | AsyncNotifier with loading state or synchronous cache. |

### L-05 — `DemoPass1` default staff password in source

| Field | Detail |
|-------|--------|
| **Severity** | Low (dev-only) |
| **Files** | `shell/dev/dev_clinic_seed_spec.dart` |
| **Evidence** | `defaultStaffPassword = 'DemoPass1'` (line 9). |
| **Impact** | Predictable dev credentials; never used in release if seed unreachable. |
| **Solution** | Generate random password per seed run; log once to console. |

---

## 5. Clean Architecture Violations

| ID | Severity | Files | Evidence | Why | Impact | Solution |
|----|----------|-------|----------|-----|--------|----------|
| CA-01 | High | `shell/dev/dev_clinic_seed_service.dart` | 600+ line orchestrator in `app/shell/dev` calling bootstrap, settings, patients, appointments, visits, shifts repositories | Application shell should not own multi-domain write workflows | Dev logic entangled with production shell; hard to test in isolation | Move to `features/dev/` or `features/setup/application/dev_seed_use_case.dart` |
| CA-02 | Medium | `router.dart`, `shell/navigation/shell_nav_config.dart`, `core/auth/auth_route_guard.dart` | Route policy split across three modules | Policy duplication and ordering dependencies | Redirect bugs when one layer updates without others | Single `RoutePolicy` module consumed by router |
| CA-03 | Medium | `providers/auth_session_provider.dart` | Notifier handles Supabase init, auth stream, idle timeout, context load, branch mutation | God notifier at app root | Hard to test; changes ripple everywhere | Split `IdleSessionController`, `SupabaseAuthBinder`, keep thin facade |

---

## 6. SOLID Violations

| ID | Severity | Files | Evidence | Why | Impact | Solution |
|----|----------|-------|----------|-----|--------|----------|
| SOLID-01 | High | `DevClinicSeedService` | Single class: wipe DB, org setup, staff, patients, shifts, appointments, visits, catalogs | SRP violation | Change to appointment seeding risks breaking org setup | Phase classes or private extension modules per domain |
| SOLID-02 | Medium | `ShellNavConfig` | Routes, labels, titles, dev delegation, prefix matching | SRP / OCP | Every new route touches multiple methods | `ShellNavRegistry` with registered `ShellNavEntry` objects |
| SOLID-03 | Medium | `AuthSessionNotifier` | Multiple reasons to change: network, auth events, idle, branch | SRP | Regression risk on unrelated features | Extract collaborators injected via ref |

---

## 7. Code Duplication & Redundancy

| ID | Severity | Files | Evidence | Why | Impact | Solution |
|----|----------|-------|----------|-----|--------|----------|
| DUP-01 | Medium | `dev_egyptian_medications_asset.dart`, `dev_egyptian_investigations_asset.dart` | Identical `loadNames` / `batchesFor` structure | Copy-paste | Fix bugs twice | Generic `DevJsonNameListAsset` with path + batch size |
| DUP-02 | Medium | `router.dart` | `unauthenticatedEntry` redirect block duplicated (lines 233–257 and 264–314) | Incremental edits | Divergent redirect behavior | Extract `_resolveUnauthenticatedRedirect` |
| DUP-03 | Low | `app_navigator.dart` | `goDesignSystem` and `goFoundationDemo` identical (lines 29–31) | Alias redundancy | Noise | Keep one method |

---

## 8. Performance Issues

| ID | Severity | Files | Evidence | Why | Impact | Solution |
|----|----------|-------|----------|-----|--------|----------|
| PERF-01 | High | `dev_clinic_seed_service.dart` | Sequential awaits for 48 patients × 8 day offsets × 3 branches ≈ 1152 appointments plus visits | No batching | Dev seed may take 10+ minutes; timeouts | Batch RPCs where backend supports; parallelize independent branches |
| PERF-02 | Medium | `router.dart` | `refreshListenable` increments on auth, startup, setup, dev seed | Full redirect re-evaluation | Frequent rebuilds during seed progress | Narrow listenable to auth/session fields only for redirect |
| PERF-03 | Medium | `authenticated_shell.dart` | Queue warm provider on every shell build | Eager fetch | Background load on all pages | Opt-in listener widget |

---

## 9. Test Coverage Gaps

| ID | Severity | Files | Evidence | Why | Impact | Solution |
|----|----------|-------|----------|-----|--------|----------|
| TEST-01 | Critical | `shell_dev_fill_dummy_clinic.dart` | No test asserts UI wiring | Would have caught C-01 | Dev seed unreachable undetected | Widget test: tap dev action → dialog → notifier invoked |
| TEST-02 | High | `shell/navigation/shell_nav_config.dart` | No tests for `itemIdForLocation` / `routeFor` | Duplicate route edge cases | Wrong nav highlights | Unit tests for home/dashboard, billing/invoices |
| TEST-03 | High | `router.dart` | No integration tests | Complex redirect ordering | Regressions in auth flow | `GoRouter` test harness with provider overrides |
| TEST-04 | Medium | `providers/branch_selection_notifier.dart` | Untested | Branch/auth sync | Silent failures on select | Unit test with mock auth notifier |
| TEST-05 | Medium | `providers/session_context_loader.dart` | No dedicated tests in app | JWT edge cases | Auth failures in production | Unit tests with fake Supabase client |
| TEST-06 | Low | Existing | `shell_dev_security_test.dart` covers kDebugMode gates | Good baseline | — | Extend with reset-database and wiring tests |

**Existing dev tests (positive):** `dev_clinic_seed_schedule_test.dart`, `dev_clinic_seed_spec_test.dart`, Egyptian asset tests, `shell_dev_security_test.dart`.

---

## 10. Recommended Refactoring (Dev & Cross-Cutting)

1. **Dev options panel** — Add `DevOptionsSection` to `DesignSystemPage` (or shell footer submenu) listing `ShellDevNav.footerItemIds` with handlers for fill-dummy and reset.
2. **Navigate dispatch** — Centralize `onNavigate` in `AuthenticatedShell`:
   ```dart
   if (itemId == ShellDevFillDummyClinic.itemId) {
     ShellDevFillDummyClinic.handleNavSelection(context, ref);
     return;
   }
   ```
3. **Remove or implement reset-database** — Wire to `setupNotifier.resetInstallationForDevelopment()` with strong confirmation.
4. **Branch display** — `branchListProvider` → `List<ShellBranch>` with names from `branchRepositoryProvider`.
5. **Dev module extraction** — Move `shell/dev/*` to `features/dev/` with `kDebugMode` barrel export; keep `shell_dev_integration.dart` as thin facade.
6. **Route registry** — Generate or consolidate `AppRoutes` + `GoRoute` list to eliminate hardcoded service edit path.
7. **Overlay UX** — Show progress text; optional cancel after wipe phase.

---

## Dev vs Production Path Matrix

| Capability | Debug | Profile/Release |
|------------|-------|-----------------|
| `ShellDevNav.isEnabled` | true | false |
| Sidebar “Dev” footer item | shown | hidden |
| `foundationDemo` without login | allowed | blocked (redirect to login) |
| `DevClinicSeedOverlay` | active when seeding | passthrough child |
| Auth redirect suppression during seed | active | disabled |
| `fillDummyClinic()` RPC entry | callable if wired | returns false immediately |
| `resetInstallationForDevelopment` | available via setup notifier, not shell | same |

---

*End of dev & cross-cutting review.*
