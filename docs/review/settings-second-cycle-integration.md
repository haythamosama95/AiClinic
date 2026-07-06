# Settings Feature — Second-Cycle Integration Review

**Scope:** App-layer wiring, cross-feature imports, routing/guards, repository providers, route → notifier → use case → repo flow, integration test gaps.  
**Review date:** 2026-07-05  
**Prior review:** [flutter-settings-feature-code-review.md](./flutter-settings-feature-code-review.md)  
**Architecture reference:** NFR-006/007 in [015-service-catalog plan](../specs/015-service-catalog/plan.md) — features expose only repository + providers as the single cross-feature coupling.

---

## Executive Summary

### Verdict: **Integration Boundaries Are Fragile — Fix Coupling Before Wiring Settings UI**

The settings feature’s **data and RPC layers integrate cleanly with Supabase**, but **presentation is entirely disconnected from the router**, and **cross-feature consumers bypass the published provider surface**. Four first-cycle integration findings remain unfixed; three new medium-severity gaps were found in shell navigation and tab visibility.

| Severity | Count |
|----------|-------|
| **Critical** | 1 |
| **High** | 7 |
| **Medium** | 10 |

### First-Cycle Integration Findings — Status

| ID | Finding | Status |
|----|---------|--------|
| H1 | Domain `settings_use_case_providers` imports data layer (DIP) | **CONFIRMED STILL PRESENT** |
| H2 | settings ↔ app bidirectional cycle via idle-timeout store | **CONFIRMED STILL PRESENT** |
| H3 | Settings domain as undeclared shared kernel (appointments/setup/app) | **CONFIRMED STILL PRESENT** |
| H4 | All `/settings/*` routes are `uiPendingPlaceholder`; notifiers unwired | **CONFIRMED STILL PRESENT** |
| M2 | Inconsistent authorization (role vs permission keys) | **CONFIRMED STILL PRESENT** |
| M10 | Route guards wired; substantive issue is M2 | **CONFIRMED STILL PRESENT** (nuanced: guards work in router; tab/nav models disagree) |
| M5/M6 | Cross-feature reach into settings DI; `repository_providers` bypassed | **CONFIRMED STILL PRESENT** |
| M11 | `clinicSetup*` providers skip client permission gating | **CONFIRMED STILL PRESENT** |
| M14/M16 | Feature layers import `app/`; duplicate idle-timeout loading | **CONFIRMED STILL PRESENT** |
| M4 | Non-reactive `ref.read(authSessionProvider)` in staff/role notifiers | **CONFIRMED STILL PRESENT** |
| Test gaps | No router integration test; no `StaffListNotifier` / `clinicSetup*` / `SettingsTabs` tests | **CONFIRMED STILL PRESENT** |

### Top 3 Integration Risks

1. **Presentation layer is a dead branch** — router placeholders mean route → notifier → use case → repo cannot be exercised in-app (H4).
2. **Appointments (and setup) depend on settings’ internal DI and domain types** — violates NFR-006/007 and transitively pulls in the data layer via H1 (H3 + M5).
3. **Permission matrix save integrates with auth session reload** — a post-save `reloadContext()` failure reverts UI to pre-save state while server data is committed (C2 / INT-C1).

---

## Cross-Feature Import Map

Every **production** `lib/` import of `features/settings` from outside the settings feature:

### `app/` (6 files)

| File | Imports | Layer reached |
|------|---------|---------------|
| `app/app.dart` | `application/idle_timeout_settings_notifier.dart` | application |
| `app/providers/auth_session_provider.dart` | `data/idle_timeout_preferences_store.dart` | **data** |
| `app/providers/repository_providers.dart` | `data/branch_repository.dart`, `data/staff_admin_repository.dart` | **data** (re-export only) |
| `app/shell/dev/dev_clinic_seed_notifier.dart` | `data/branch_repository.dart`, `data/staff_admin_repository.dart` | **data** (bypasses barrel) |
| `app/shell/dev/dev_clinic_seed_service.dart` | `domain/create_branch_input.dart`, `domain/repositories/*`, `domain/update_staff_member_input.dart` | domain |
| `app/shell/dev/dev_clinic_seed_spec.dart` | `domain/branch_working_schedule.dart` | domain |

### `features/setup/` (3 files)

| File | Imports | Layer reached |
|------|---------|---------------|
| `presentation/providers/setup_notifier.dart` | `domain/branch_working_schedule.dart` | domain |
| `domain/bootstrap_branch_input.dart` | `domain/branch_working_schedule.dart` | domain |
| `domain/setup_step_readiness.dart` | `domain/branch_working_schedule.dart` | domain |

### `features/appointments/` (11 files)

| File | Imports | Layer reached |
|------|---------|---------------|
| `presentation/providers/appointment_calendar_provider.dart` | `domain/branch_list_*`, `domain/staff_list_*`, `domain/usecases/settings_use_case_providers.dart` | domain + **DI wiring** |
| `presentation/providers/appointment_queue_provider.dart` | `domain/branch_*`, `domain/usecases/settings_use_case_providers.dart` | domain + **DI wiring** |
| `presentation/providers/appointment_queue_shift_provider.dart` | `domain/staff_list_*`, `domain/usecases/settings_use_case_providers.dart` | domain + **DI wiring** |
| `data/doctor_dev_seed_service.dart` | `domain/repositories/staff_admin_repository.dart`, `domain/staff_list_filter.dart` | domain |
| `domain/appointment_working_hours.dart` | `domain/branch_working_schedule.dart` | domain |
| `domain/appointment_settings.dart` | `domain/branch_working_schedule.dart` | domain |
| `domain/appointment_reschedule_validation.dart` | `domain/branch_working_schedule.dart` | domain |
| `domain/appointment_calendar_display.dart` | `domain/branch_working_schedule.dart` | domain |
| `domain/appointment_branch_working_hours.dart` | `domain/branch_working_schedule.dart` | domain |
| `domain/appointment_queue_shift_doctors.dart` | `domain/staff_list_item.dart` | domain |

### `features/shifts/` — **no imports**

### `features/billing/` — **no imports** (billing settings route guarded via `billingRouteRedirect`; correct boundary pattern)

### Transitive coupling note

Any file importing `domain/usecases/settings_use_case_providers.dart` transitively depends on all four settings **data** repository providers (H1).

---

## Route Guard vs Permission Key Matrix

| Route / tab | Guard method | Rule | Permission key / role | Notifier gate | Tab/nav visibility |
|-------------|--------------|------|----------------------|---------------|-------------------|
| `/settings` | `isSettingsRoute` | Auth + setup complete | None | N/A | Footer always visible |
| `/settings/idle-timeout` | `isSettingsRoute` | Auth + setup complete | None | `idleTimeoutSettingsProvider` (no perm check) | `SettingsTabs.general` always visible |
| `/settings/organization` | `adminSettingsRedirect` | `canAccessOrganizationSettings` | **Role == administrator** | `clinicSetupOrganizationProvider` — **no gate** | `SettingsTabs.clinicSetup` gated |
| `/settings/branches`, `/new`, `/:id/edit` | `adminSettingsRedirect` | `canAccessBranchManagement` | `settings.manage_branches` | `clinicSetupBranchesProvider` — **no gate** | via `clinicSetup` tab only |
| `/settings/staff`, `/new`, `/:id/*` | `adminSettingsRedirect` | `canAccessStaffManagement` | `settings.manage_staff` | `staffListProvider` gated | **`SettingsTabs.staff` always visible**; **shell `staff` nav always visible** |
| `/settings/permissions` | `adminSettingsRedirect` | `canAccessPermissionMatrix` | **Role == administrator** | `rolePermissionsProvider` gated | **`SettingsTabs.staffRoles` always visible** |
| `/settings/billing` | `billingRouteRedirect` | `canAccessBillingSettings` | `invoices.view` OR `payments.record` | N/A (billing feature) | Not in `SettingsTabs` |
| `/settings/services/*` | `serviceCatalogRouteRedirect` | Service catalog perms | `services.view` / `services.manage` | N/A (service_catalog feature) | Shell `services` nav (no perm filter) |

**Router wiring:** `adminSettingsRedirect`, `billingRouteRedirect`, and `serviceCatalogRouteRedirect` are invoked from `router.dart` when `startupSessionProvider.currentView == StartupCurrentView.unauthenticatedEntry` (the normal post-bootstrap shell state). Unit tests in `auth_route_guard_admin_settings_test.dart` cover guard logic but **no GoRouter/widget test** asserts redirects during navigation.

---

## End-to-End Data Flow (Integration Paths)

### Wired path (appointments → settings reads)

```
Appointment*Provider
  → settings_use_case_providers (domain; imports data ⚠)
    → *UseCase.call()
      → domain/repositories/* (interface)
        → data/*_repository.dart (impl)
          → SettingsRpcInvoker / PostgREST
```

Appointments **never** use settings presentation notifiers; they duplicate the read path with their own providers.

### Intended settings UI path (broken at router)

```
GoRouter /settings/*
  → uiPendingPlaceholder('Settings')  ← STOPS HERE
  → (not wired) staffListProvider / rolePermissionsProvider / clinicSetup* / idleTimeoutSettingsProvider
    → settings_use_case_providers
      → use cases → repositories → Supabase
```

### Idle-timeout path (app ↔ settings cycle)

```
app.dart init
  → idleTimeoutSettingsProvider.future (settings/application)
    → idleTimeoutPreferencesStore (settings/data)
    → idleTimeoutServiceProvider (app/auth_session_provider)

auth_session_provider._enableIdleWithPersistedDuration
  → idleTimeoutPreferencesStore (settings/data)  ← duplicate read
  → idleTimeoutServiceProvider
```

---

## 1. Critical Issues

### INT-C1. Permission save → auth `reloadContext()` failure reverts UI after successful persist

- **First-cycle:** C2  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** Critical
- **Files:** `features/settings/presentation/providers/role_permissions_notifier.dart`, `app/providers/auth_session_provider.dart`
- **Evidence:**

```130:169:frontend/lib/features/settings/presentation/providers/role_permissions_notifier.dart
    try {
      await ref.read(updateRolePermissionsUseCaseProvider)(changes);
      // ... state updated to post-save matrix ...
      await ref.read(authSessionProvider.notifier).reloadContext();
      AppLog.info('settings.permissions.save.ok');
      return true;
    } on RpcFailure catch (error) {
      // ... refetch on RPC failure ...
    } catch (error) {
      AppLog.warning('settings.permissions.save.failed reason=${error.runtimeType}');
      state = AsyncData(
        current.copyWith(  // ← reverts to PRE-SAVE snapshot
          isSaving: false,
          errorMessage: 'Unable to save role permissions. Check connectivity and try again.',
        ),
      );
      return false;
    }
```

- **Why:** `reloadContext()` is an app-layer integration call after a successful settings mutation. Any non-`RpcFailure` error (network blip, context loader failure) is treated like a save failure.
- **Impact:** Permissions are committed server-side; UI shows failure and stale matrix; session permissions may be stale until manual reload.
- **Recommended solution:** After RPC + refetch succeed, treat `reloadContext()` failure as a soft warning; keep post-save state and return `true`. Add integration test: mock `reloadContext` throw after successful RPC.

---

## 2. High Priority Issues

### INT-H1. Domain use-case providers import data layer (DIP inversion)

- **First-cycle:** H1 / CA-1 / SOLID-1  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:** `features/settings/domain/usecases/settings_use_case_providers.dart`, all `features/settings/data/*_repository.dart`
- **Evidence:**

```3:6:frontend/lib/features/settings/domain/usecases/settings_use_case_providers.dart
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
```

- **Why:** Domain must not depend on data. Cross-feature consumers importing this file inherit the violation transitively.
- **Impact:** Settings domain cannot be tested or reused without Supabase impls; refactoring DI breaks appointments.
- **Recommended solution:** Move `settings_use_case_providers.dart` to `application/` (or `app/providers/`). Domain keeps entities, interfaces, and framework-free use-case classes.

---

### INT-H2. settings ↔ app feature-level dependency cycle via idle-timeout

- **First-cycle:** H2 / CA-2  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:** `app/providers/auth_session_provider.dart`, `features/settings/application/idle_timeout_settings_notifier.dart`, `features/settings/data/idle_timeout_preferences_store.dart`, `app/app.dart`
- **Evidence:**

```13:13:frontend/lib/app/providers/auth_session_provider.dart
import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
```

```3:5:frontend/lib/features/settings/application/idle_timeout_settings_notifier.dart
import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
```

```29:32:frontend/lib/app/app.dart
    Future<void>.microtask(() async {
      await ref.read(idleTimeoutSettingsProvider.future);
      await ref.read(startupSessionProvider.notifier).bootstrap();
```

- **Why:** Idle-timeout persistence lives in settings/data; orchestration split across app bootstrap, auth session, and settings notifier.
- **Impact:** Neither auth session nor settings idle UI can be extracted/tested without the other; three independent load paths can race (see INT-M6).
- **Recommended solution:** Define `IdleTimeoutPreferencesStore` interface + `idleTimeoutServiceProvider` in `core/auth/`; both app and settings depend downward.

---

### INT-H3. Settings domain acts as undeclared shared kernel

- **First-cycle:** H3 / CA-4  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:** 11 appointments files, 3 setup files, 2 app dev-seed files (see import map)
- **Evidence:** `BranchWorkingSchedule` consumed by appointments domain (6 files) and setup readiness; `StaffListItem` consumed by appointments queue/calendar/shift logic.
- **Why:** 015 plan NFR-006/007 requires a single published repository + provider surface per feature. Settings exports scheduling/staff domain types widely.
- **Impact:** Any change to `BranchWorkingSchedule` or `StaffListItem` is a cross-feature breaking change with no ownership contract.
- **Recommended solution:** Promote shared types to `core/clinic/` (or similar neutral module), or expose read-only facades through `repository_providers` with stable DTOs.

---

### INT-H4. Settings presentation entirely unwired from router

- **First-cycle:** H4 / CA-5  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:** `app/router.dart` (lines 147–185), all settings notifiers, `presentation/models/settings_tab.dart`
- **Evidence:**

```147:185:frontend/lib/app/router.dart
          // Settings
          GoRoute(path: AppRoutes.settings, builder: (context, state) => uiPendingPlaceholder('Settings', state)),
          GoRoute(
            path: AppRoutes.settingsIdleTimeout,
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          // ... every admin settings route → uiPendingPlaceholder('Settings', state)
```

No production widget imports `staffListProvider`, `rolePermissionsProvider`, `clinicSetupOrganizationProvider`, `clinicSetupBranchesProvider`, or `SettingsTabs`.

- **Why:** Integration path route → notifier → use case is broken at the first hop.
- **Impact:** Guard/notifier/DI integration cannot be validated in running app; large tested surface is dead code relative to navigation.
- **Recommended solution:** Implement settings shell consuming `SettingsTabs` + notifiers, or feature-flag and quarantine unwired providers until UI lands.

---

### INT-H5. Appointments depend on settings internal DI wiring (transitive data coupling)

- **First-cycle:** M5 (escalated for integration)  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:** `appointment_calendar_provider.dart`, `appointment_queue_provider.dart`, `appointment_queue_shift_provider.dart`
- **Evidence:**

```12:16:frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
```

- **Why:** Appointments reach into settings' composition root instead of `repository_providers` or a published read API.
- **Impact:** Refactoring settings DI (INT-H1 fix) breaks appointments; violates NFR-006/007.
- **Recommended solution:** Add `listBranchesForAppointmentsProvider` / `listStaffForAppointmentsProvider` to `app/providers/repository_providers.dart` (or `core/clinic/`) wrapping the use cases.

---

### INT-H6. `StaffListNotifier.reload()` completes before fetch (blocks reliable UI integration)

- **First-cycle:** C1  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** High (integration readiness)
- **Files:** `features/settings/presentation/providers/staff_list_notifier.dart`
- **Evidence:**

```31:34:frontend/lib/features/settings/presentation/providers/staff_list_notifier.dart
  Future<void> reload() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }
```

- **Why:** `invalidateSelf()` does not await rebuilt `build()`. Any settings page calling `await reload()` then reading state will see stale data.
- **Impact:** Staff management UI integration will ship with race bugs.
- **Recommended solution:** `ref.invalidateSelf(); await future;` — remove manual `AsyncLoading` assignment.

---

### INT-H7. `repository_providers` barrel incomplete and bypassed

- **First-cycle:** M6 / CA-14  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:** `app/providers/repository_providers.dart`, appointments/setup/dev-seed consumers
- **Evidence:**

```1:7:frontend/lib/app/providers/repository_providers.dart
// Re-exports for cross-feature repository provider access.
export 'package:ai_clinic/features/settings/data/branch_repository.dart' show branchRepositoryProvider;
export 'package:ai_clinic/features/settings/data/staff_admin_repository.dart' show staffAdminRepositoryProvider;
```

Missing: `organizationRepositoryProvider`, `rolePermissionsRepositoryProvider`. Appointments import use-case providers directly; `dev_clinic_seed_notifier.dart` imports settings data layer directly.

- **Why:** Documented cross-feature contract is ignored; barrel covers only 2 of 4 settings repos.
- **Impact:** No single integration point for settings access; import lint cannot be enforced.
- **Recommended solution:** Complete barrel exports; add published read providers; forbid deep imports from other features.

---

## 3. Medium Priority Issues

### INT-M1. Dual authorization model: role-based vs permission keys

- **First-cycle:** M2 / M10 / SOLID-3  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `core/auth/auth_route_guard.dart`, `role_permissions_notifier.dart`
- **Evidence:**

```370:403:frontend/lib/core/auth/auth_route_guard.dart
  static bool canAccessOrganizationSettings(AuthSessionState auth) {
    // ...
    return role == StaffRole.administrator;
  }
  static bool canAccessBranchManagement(AuthSessionState auth) {
    return auth.context!.permissions.contains(PermissionKeys.manageBranches);
  }
  static bool canAccessPermissionMatrix(AuthSessionState auth) {
    return role == StaffRole.administrator;
  }
```

```79:80:frontend/lib/features/settings/presentation/providers/role_permissions_notifier.dart
    final role = auth.context?.staffProfile.role ?? StaffRole.receptionist;
    final editable = role == StaffRole.administrator;
```

- **Why:** Org settings and permission matrix use hard-coded administrator role; branch/staff use permission keys. Matrix grants cannot unlock org/permissions tabs.
- **Impact:** Permission matrix edits cannot grant settings access without code changes; double-encoded admin rule drifts.
- **Recommended solution:** Standardize on permission keys for all settings tabs; derive `editable` from one guard call.

---

### INT-M2. `SettingsTabs.visibleFor` misaligned with route guards

- **First-cycle:** extension of M2 (NEW nuance)  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `features/settings/presentation/models/settings_tab.dart`
- **Evidence:**

```43:46:frontend/lib/features/settings/presentation/models/settings_tab.dart
  static List<SettingsTabDefinition> visibleFor(AuthSessionState auth) {
    return [general, if (AuthRouteGuard.canAccessClinicSetup(auth)) clinicSetup, staff, staffRoles];
  }
```

`staff` and `staffRoles` tabs are always included; no `canAccessStaffManagement` or `canAccessPermissionMatrix` checks.

- **Why:** Tab catalog will show sections the router would redirect away from.
- **Impact:** When settings UI ships, users see tabs they cannot access; inconsistent with `adminSettingsRedirect`.
- **Recommended solution:** Gate each tab with the matching `AuthRouteGuard` method; add unit tests for `visibleFor`.

---

### INT-M3. Shell sidebar exposes Staff nav without permission filter

- **Status:** **NEW**
- **Severity:** Medium
- **Files:** `app/shell/navigation/shell_nav_config.dart`, `app/shell/authenticated_shell.dart`
- **Evidence:**

```17:17:frontend/lib/app/shell/navigation/shell_nav_config.dart
    'staff': AppRoutes.settingsStaff,
```

```52:65:frontend/lib/app/shell/authenticated_shell.dart
        sidebar: AppSidebar(
          groups: ShellNavConfig.groups,
          footerItems: ShellNavConfig.footerItems(),
          // no auth-based filtering of items
```

- **Why:** Operations sidebar always shows Staff → `/settings/staff`; router redirects unauthorized users to `/settings` hub, but nav implies access.
- **Impact:** Confusing UX; doctors click Staff and land on generic settings placeholder.
- **Recommended solution:** Add `ShellNavConfig.visibleItemsFor(auth)` mirroring route guards before settings UI ships.

---

### INT-M4. `clinicSetup*` providers fetch without permission gates

- **First-cycle:** M11  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `features/settings/presentation/providers/clinic_setup_providers.dart`
- **Evidence:**

```8:24:frontend/lib/features/settings/presentation/providers/clinic_setup_providers.dart
final clinicSetupOrganizationProvider = FutureProvider.autoDispose<OrganizationProfile?>((ref) async {
  final organizationId = ref.watch(authSessionProvider.select((session) => session.context?.organizationId));
  // no canAccessOrganizationSettings check
  return ref.read(fetchOrganizationProfileUseCaseProvider)(organizationId: organizationId);
});
```

Contrast `staffListProvider` and `rolePermissionsProvider`, which gate in `build()`.

- **Why:** Inconsistent notifier-level authorization vs route guards.
- **Impact:** Branch managers with only `manage_branches` may trigger org profile fetch (RLS may deny); inconsistent with staff/permissions notifiers.
- **Recommended solution:** Gate org fetch behind `canAccessOrganizationSettings`; branches behind `canAccessBranchManagement`.

---

### INT-M5. Feature presentation/application layers import app composition root

- **First-cycle:** M14  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** All settings notifiers, `settings_tab.dart`, `idle_timeout_settings_notifier.dart`
- **Evidence:** Every notifier imports `package:ai_clinic/app/providers/auth_session_provider.dart`; `settings_tab.dart` imports both `auth_session_provider` and `auth_route_guard`.
- **Why:** Settings feature depends upward on app layer for session and guards.
- **Impact:** Settings cannot be tested or reused as a module without the full app provider tree.
- **Recommended solution:** Define narrow ports (`SettingsAuthContext`, `SettingsSessionReader`) in settings domain; bind in `app/providers/`.

---

### INT-M6. Triple idle-timeout load path and bootstrap hard dependency

- **First-cycle:** M16 / M8  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `app/app.dart`, `auth_session_provider.dart`, `idle_timeout_settings_notifier.dart`
- **Evidence:** Three call sites load from `idleTimeoutPreferencesStoreProvider` (see End-to-End flow). `app.dart` awaits `idleTimeoutSettingsProvider.future` before `bootstrap()`.
- **Why:** Duplicate disk I/O; auth sign-in path can overwrite duration set during app init; bootstrap blocked if store hangs.
- **Impact:** Race on concurrent first-load; startup failure if preferences store errors uncaught at app level.
- **Recommended solution:** Single canonical loader; auth session reads duration from `idleTimeoutSettingsProvider` state instead of re-loading store.

---

### INT-M7. Non-reactive auth reads in staff/role notifiers

- **First-cycle:** M4  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `staff_list_notifier.dart`, `role_permissions_notifier.dart` vs `clinic_setup_providers.dart`
- **Evidence:** Staff/role use `ref.read(authSessionProvider)` in `build()`; clinic setup uses `ref.watch(...select(...))`.
- **Why:** Staff list and permission matrix won't auto-rebuild after `reloadContext()` unless manually invalidated.
- **Impact:** Stale authorization UI after permission save or branch switch.
- **Recommended solution:** `ref.watch(authSessionProvider.select(...))` on consumed fields; invalidate on `reloadContext` success.

---

### INT-M8. Dev clinic seed bypasses `repository_providers` barrel

- **Status:** **NEW**
- **Severity:** Medium
- **Files:** `app/shell/dev/dev_clinic_seed_notifier.dart`
- **Evidence:**

```10:11:frontend/lib/app/shell/dev/dev_clinic_seed_notifier.dart
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
```

- **Why:** App-layer dev tooling reaches into settings data layer, same anti-pattern as appointments.
- **Impact:** Seed tooling couples to settings data implementation details.
- **Recommended solution:** Import from `repository_providers.dart` only.

---

### INT-M9. Integration test coverage gaps

- **First-cycle:** test gaps (integration subset)  
- **Status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `frontend/test/**`
- **Evidence:**

| Gap | Existing coverage |
|-----|-------------------|
| GoRouter redirect for settings admin routes | None — only `auth_route_guard_admin_settings_test.dart` (unit) |
| `StaffListNotifier` / `reload()` race | None |
| `clinicSetup*` permission gating | None |
| `SettingsTabs.visibleFor` vs guards | None |
| Route → notifier → use case widget test | None (all routes placeholders) |
| INT-C1 `reloadContext` failure after save | None |

Positive: `idle_timeout_integration_test.dart`, `auth_session_idle_duration_test.dart`, `app_routes_settings_test.dart`.

- **Impact:** Integration regressions ship undetected.
- **Recommended solution:** Add `go_router` redirect tests for settings paths; notifier tests before wiring UI.

---

### INT-M10. `SettingsTabDefinition` references non-existent `SettingsTabBar`

- **Status:** **NEW** (maturity signal)
- **Severity:** Medium
- **Files:** `presentation/models/settings_tab.dart`
- **Evidence:** Doc comment references `[SettingsTabBar]`; no such widget exists in codebase.
- **Why:** Tab model prepared for UI that was never built; reinforces H4 unwired state.
- **Impact:** Implementers lack the consuming widget; tab routing integration undefined.
- **Recommended solution:** Implement settings shell with tab bar, or remove catalog until UI sprint.

---

## Recommended Integration Refactoring (Ordered)

### Phase 0 — Before settings UI wiring

1. Fix INT-C1 (`reloadContext` soft-fail) and INT-H6 (`reload()` await).
2. Unify authorization model (INT-M1) and align `SettingsTabs` + shell nav (INT-M2, INT-M3).
3. Gate `clinicSetup*` providers (INT-M4).

### Phase 1 — Boundary cleanup (blocks further cross-feature coupling)

4. Move use-case providers out of domain (INT-H1).
5. Break idle-timeout cycle via `core/auth/` (INT-H2, INT-M6).
6. Extract shared types or published read API (INT-H3, INT-H5, INT-H7).
7. Complete `repository_providers` barrel; add import lint.

### Phase 2 — Wire presentation

8. Replace router placeholders with settings shell (INT-H4, INT-M10).
9. Add integration tests (INT-M9).

---

## Appendix: Billing / Service Catalog — Positive Boundary Examples

- **Billing** does not import `features/settings`; `/settings/billing` is guarded via `billingRouteRedirect` using billing permission keys.
- **Service catalog** (015) is a separate feature module with its own guards (`serviceCatalogRouteRedirect`) — matches NFR-006/007 intent.

Settings administration should follow the same pattern: published providers only, no deep domain imports from sibling features.

---

*Second-cycle integration review. Sources: prior [flutter-settings-feature-code-review.md](./flutter-settings-feature-code-review.md), live codebase grep and file reads, [015-service-catalog plan](../specs/015-service-catalog/plan.md) NFR-006/007.*
