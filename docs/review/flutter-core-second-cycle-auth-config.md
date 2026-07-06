# Flutter Core — Second-Cycle Auth & Config Review

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/auth/` (4 files), `frontend/lib/core/config/` (10 files)  
**Cross-checked:** `frontend/lib/app/router.dart`, `frontend/lib/app/providers/auth_session_provider.dart`, `frontend/test/`  
**Baseline:** [flutter-core-review-auth-config.md](flutter-core-review-auth-config.md), [flutter-core-code-review.md](flutter-core-code-review.md)  
**Method:** Re-read every auth/config file; grep usages of `PermissionDeniedHandler`, route redirects, and billing policy; verify first-cycle Critical/High/Medium against current code.

---

## Summary

| Severity | First-cycle | Fixed | Partially fixed | Still open | New this cycle |
|----------|-------------|-------|-----------------|------------|----------------|
| Critical | 2 | 0 | 0 | 2 | 0 |
| High | 6 | 0 | 0 | 6 | 0 |
| Medium | 10 | 0 | 0 | 10 | 0 |

**Verdict:** No remediation landed in auth/config since the first review. All 18 indexed Critical/High/Medium findings remain open. Patient route permission bypass, core→app dependency inversion, split redirect orchestration, billing policy divergence, missing route-guard tests, stale web profile cache, and dead `PermissionDeniedHandler` are unchanged.

---

## Critical Issues

### C-01 — Patient routes skip router-level permission enforcement

| Field | Detail |
|-------|--------|
| **Severity** | Critical (defense-in-depth; server RPCs still enforce) |
| **Category** | Security / routing |
| **Files** | `frontend/lib/core/auth/auth_route_guard.dart`, `frontend/lib/app/router.dart` |
| **First-cycle status** | **STILL OPEN** |

**Evidence:**

```283:298:frontend/lib/core/auth/auth_route_guard.dart
  static String? patientRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isPatientRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if (auth.context!.setupRequired) {
      return AppRoutes.bootstrap;
    }

    // Permission checks are enforced on each patient page (UI stays visible; denial in-page).
    return null;
  }
```

`canAccessPatientList`, `canAccessPatientRegistration`, and `canAccessPatientEdit` exist (lines 46–76) but are **not** called from `patientRouteRedirect`. Tests in `auth_route_guard_patients_test.dart` assert `isNull` redirect for authenticated users regardless of patient permissions.

**Why:** Billing, visits, shifts, and appointments enforce permissions at the router; patients do not.

**Impact:** Any authenticated user with setup complete can navigate to `/patients`, `/patients/new`, `/patients/:id/edit` via direct URL.

**Solution:** Map patient routes to `canAccessPatient*` helpers; redirect to `AppRoutes.home` when denied.

---

### C-02 — `AuthSessionState` lives in app layer but is required by core

| Field | Detail |
|-------|--------|
| **Severity** | Critical (architecture) |
| **Category** | Clean Architecture |
| **Files** | `frontend/lib/core/auth/auth_route_guard.dart`, `frontend/lib/app/providers/auth_session_provider.dart` |
| **First-cycle status** | **STILL OPEN** |

**Evidence:**

```6:6:frontend/lib/core/auth/auth_route_guard.dart
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
```

```17:44:frontend/lib/app/providers/auth_session_provider.dart
enum AuthSessionStatus { unknown, unauthenticated, loading, authenticated }

class AuthSessionState {
  const AuthSessionState({required this.status, this.context, this.failureMessage});
  // ...
}
```

`AuthSessionContext` correctly lives in `features/auth/domain/`; the session envelope type does not.

**Why:** Core depends on app/presentation wiring (Riverpod notifiers, idle timeout providers).

**Impact:** Core untestable in isolation; circular dependency risk as app layer grows.

**Solution:** Move `AuthSessionState` and `AuthSessionStatus` to `features/auth/domain/` or `core/auth/models/`.

---

## High Priority Issues

### H-01 — Permission redirects split across `resolveRedirect` and `router.dart`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | **STILL OPEN** |
| **Files** | `auth_route_guard.dart`, `router.dart` |

**Evidence:** `_resolveRedirect` handles session/setup only (lines 480–533). Feature permission redirects are invoked separately in `router.dart` lines 274–312, gated on `session.currentView == StartupCurrentView.unauthenticatedEntry`.

**Impact:** New routes easily miss permission gates; `resolveRedirect` in isolation is incomplete.

**Solution:** Consolidate into `AuthRouteGuard.resolveAllRedirects(...)`.

---

### H-02 — Loading/unknown auth status allows protected routes to render

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | **STILL OPEN** |
| **Files** | `auth_route_guard.dart` |

**Evidence:**

```485:487:frontend/lib/core/auth/auth_route_guard.dart
    if (auth.status == AuthSessionStatus.unknown || auth.status == AuthSessionStatus.loading) {
      return null;
    }
```

Test confirms: `auth_route_guard_test.dart` — *"loading session does not redirect"*. Feature permission redirects in `router.dart` only run after startup reaches `unauthenticatedEntry`.

**Impact:** Protected shells may flash during session restoration; permission gates may not run during `startupCheck`.

**Solution:** Redirect to holding route while `status` is `unknown`/`loading` for protected locations.

---

### H-03 — Billing settings permission logic diverges between guard and `PermissionService`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | **STILL OPEN** |
| **Files** | `auth_route_guard.dart`, `permission_service.dart`, `billing_settings_notifier.dart` |

**Evidence:**

```177:183:frontend/lib/core/auth/auth_route_guard.dart
  static bool canAccessBillingSettings(AuthSessionState auth) {
    // ...
    return permissions.canViewInvoices() || permissions.canRecordPayment();
  }
```

```81:81:frontend/lib/core/auth/permission_service.dart
  bool canManageBillingSettings() => hasPermission(PermissionKeys.settingsBillingManage);
```

`billing_settings_notifier.dart` uses `AuthRouteGuard.canAccessBillingSettings` for gating; save operations need `settingsBillingManage`.

**Impact:** Receptionist with `invoices.view` reaches settings UI but hits RPC `FORBIDDEN` on save.

**Solution:** Single policy function with documented read vs. write rules.

---

### H-04 — No unit tests for visit, shift, service catalog, or provisioning route redirects

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | **STILL OPEN** |
| **Files** | `auth_route_guard.dart`, `frontend/test/` |

**Evidence:** `grep visitRouteRedirect|shiftRouteRedirect|serviceCatalogRouteRedirect|steadyStateProvisioningRedirect frontend/test/` → **0 matches**. Tests exist for billing, admin settings, patients, and appointments only.

**Impact:** ~120 lines of permission routing logic unverified; regressions on V1-5/V1-7 routes undetected.

**Solution:** Add dedicated test files mirroring `auth_route_guard_billing_test.dart`.

---

### H-05 — Web deployment profile can serve stale cached config indefinitely

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **First-cycle status** | **STILL OPEN** |
| **Files** | `deployment_profile_web_source.dart`, `deployment_profile_store_web.dart` |

**Evidence:**

```18:31:frontend/lib/core/config/deployment_profile_web_source.dart
  try {
    final response = await client.get(profileUri).timeout(fetchTimeout);
    if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
      await writeCachedContents(response.body);
      return response.body;
    }
  } on Exception {
    // Fall back to cached browser storage below.
  }

  final cached = await readCachedContents();
```

No TTL, version check, or invalidation on cache fallback.

**Impact:** After Supabase URL/key rotation, offline web deploys connect to stale backend.

**Solution:** Cache metadata with TTL; surface fetch errors in startup UI.

---

### H-06 — `PermissionDeniedHandler` is dead code in production

| Field | Detail |
|-------|--------|
| **Severity** | High (FR-009a compliance) |
| **First-cycle status** | **STILL OPEN** |
| **Files** | `permission_denied_handler.dart` |

**Evidence:** `grep PermissionDeniedHandler frontend/lib/` → only definition file. No feature imports `show` or `runIfPermitted`.

**Impact:** Inconsistent permission-denied UX across features.

**Solution:** Adopt in feature action entry points or remove and document chosen pattern.

---

## Medium Priority Issues

| ID | Issue | First-cycle status | Evidence |
|----|-------|-------------------|----------|
| M-01 | `PermissionDeniedException` in `permission_service.dart` not `core/errors/` | **STILL OPEN** | Lines 105–108 of `permission_service.dart` |
| M-02 | `permission_denied_handler.dart` couples core to Flutter Material | **STILL OPEN** | Imports `material.dart`, uses `ScaffoldMessenger` |
| M-03 | `auth_route_guard.dart` depends on `app/app_routes.dart` | **STILL OPEN** | Line 314 hardcodes `'/settings/services/'` |
| M-04 | `InMemoryGotrueAsyncStorage` process-wide static map | **STILL OPEN** | `static final Map<String, String> _store = {}` |
| M-05 | Web stub cannot detect Flutter test runtime | **STILL OPEN** | `supabase_config_env_stub.dart` always returns `false` |
| M-06 | `SupabaseBootstrap.ensureInitialized` ignores config after first call | **STILL OPEN** | Early return when `isReady` (lines 102–104) |
| M-07 | `decodeAccessTokenClaims` does not verify JWT signature | **STILL OPEN** | Payload decode only; no doc comment warning |
| M-08 | `canAccessAppointmentCancelActions` unused dead API | **STILL OPEN** | Defined lines 97–102; zero references |
| M-09 | `DeploymentProfile` validation lacks dedicated unit tests | **STILL OPEN** | Only `deployment_profile_web_source_test.dart` happy path |
| M-10 | `deployment_profile_store_io.dart` untested | **STILL OPEN** | No IO store tests |

---

## Cross-File Validation Matrix

| From → To | Status | Notes |
|-----------|--------|-------|
| `AuthRouteGuard` → `PermissionService` | OK | Facade used correctly for `canAccess*` |
| `AuthRouteGuard` → `AuthSessionState` | Violation | Core imports app layer (C-02) |
| `router.dart` → feature redirects | Split | Orchestration drift risk (H-01) |
| `patientRouteRedirect` → `canAccessPatient*` | **Broken** | Helpers exist but unused (C-01) |
| `PermissionDeniedHandler` → features | **Dead** | Zero production usages (H-06) |
| `DeploymentProfileStore` web → cache | Risk | Stale fallback (H-05) |
| `SupabaseBootstrap` → `InMemoryGotrueAsyncStorage` | Risk | Static state (M-04) |
| `billing_settings_notifier` → billing policy | Divergent | Guard vs manage permission (H-03) |

---

## Consolidation Summary

**First-cycle findings (all verified):**

- **C-01, C-02** — STILL OPEN
- **H-01 through H-06** — STILL OPEN
- **M-01 through M-10** — STILL OPEN

**New second-cycle findings:** None at Critical/High/Medium severity.

**Fixes since first cycle:** 0

**Recommended priority:** (1) C-01 patient router permissions; (2) C-02 move session types to domain; (3) H-04 route guard tests for visits/shifts/catalog; (4) H-02 loading-state redirect; (5) H-03 unify billing policy.
