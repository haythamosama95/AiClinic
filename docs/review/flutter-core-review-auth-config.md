# Flutter Core Review — Auth & Config Modules

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/auth/` (4 files), `frontend/lib/core/config/` (10 files)  
**Cross-checked against:** `frontend/lib/app/router.dart`, `frontend/lib/app/providers/`, `frontend/test/`

---

## Summary of What This Sub-Module Does

These modules form the **client-side security and startup foundation** for AiClinic:

| Area | Responsibility |
|------|----------------|
| **Auth — routing** | `AuthRouteGuard` classifies routes (public, protected, feature-specific) and resolves redirects based on `AuthSessionState` (authentication, setup completion, permissions). Feature-specific redirects (`billingRouteRedirect`, `visitRouteRedirect`, etc.) are invoked from `router.dart`, not from `resolveRedirect()` alone. |
| **Auth — permissions** | `PermissionService` evaluates cached session grants for UX gating (`hasPermission`, feature helpers, `requirePermission`). Explicitly documented as UX-only; server RPCs enforce real authorization. |
| **Auth — UX feedback** | `PermissionDeniedHandler` shows snackbars when `requirePermission` fails. |
| **Auth — session lifecycle** | `IdleTimeoutService` tracks pointer/keyboard activity and fires `onIdleTimeout` after configurable inactivity (default 15 min). Wired via `auth_session_provider.dart` and `SessionActivityScope`. |
| **Config — deployment** | `DeploymentProfile` parses/validates local JSON profiles. `DeploymentProfileStore` loads via platform conditional imports (filesystem on IO, HTTP + SharedPreferences cache on web). |
| **Config — Supabase** | `SupabaseConfig` derives connection URLs from profile. `SupabaseBootstrap` singleton-initializes the SDK with `EmptyLocalStorage` + `InMemoryGotrueAsyncStorage` (no cross-restart session persistence). `decodeAccessTokenClaims` decodes JWT payloads for session context loading. |
| **Config — DI** | `SupabaseInitializer` / `FakeSupabaseInitializer` wrap bootstrap for Riverpod test overrides. |

**Data flow (startup → auth):**

```
deployment-profile.json
  → DeploymentProfileStore.load()
  → DeploymentProfile.fromJsonString()
  → SupabaseConfig.fromDeploymentProfile()
  → SupabaseBootstrap.ensureInitialized()
  → auth sign-in → AuthSessionContext (permissions, branches)
  → AuthRouteGuard + PermissionService (route/UI gating)
```

---

## Critical Issues

### C-01 — Patient routes skip router-level permission enforcement

| Field | Detail |
|-------|--------|
| **Severity** | Critical (defense-in-depth; mitigated by server RPC enforcement) |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart`, `frontend/lib/app/router.dart` |
| **Evidence** | `patientRouteRedirect` explicitly returns `null` after auth/setup checks, with comment: *"Permission checks are enforced on each patient page"*. Unlike billing, visits, shifts, and appointments, no permission-based redirect occurs at the router. |
| **Why it's a problem** | Any authenticated user with setup complete can navigate directly to `/patients`, `/patients/new`, `/patients/:id/edit` URLs. If a feature page omits an in-page guard, unauthorized staff see patient UI shells, error states, or transient data before RPC failures. Other feature areas enforce permissions at the router. |
| **Potential impact** | Information disclosure UX leaks; inconsistent security posture; regression risk when new patient routes are added without page-level checks. |
| **Recommended solution** | Align patient routing with billing/visit patterns: map routes to `canAccessPatientList`, `canAccessPatientRegistration`, `canAccessPatientEdit`, etc., and redirect to `AppRoutes.home` (or show in-page denial consistently). Keep server enforcement; add router gate as second layer. |

---

### C-02 — `AuthSessionState` lives in the app layer but is required by core

| Field | Detail |
|-------|--------|
| **Severity** | Critical (architecture; blocks reuse and testing isolation) |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart`, `frontend/lib/app/providers/auth_session_provider.dart` |
| **Evidence** | `auth_route_guard.dart` imports `package:ai_clinic/app/providers/auth_session_provider.dart` solely for `AuthSessionState` and `AuthSessionStatus`. `AuthSessionContext` correctly lives in `features/auth/domain/`, but the session envelope type does not. |
| **Why it's a problem** | Core layer depends on the app/presentation wiring layer, inverting Clean Architecture dependency rule. Any change to `auth_session_provider.dart` (Riverpod notifiers, idle timeout providers) risks breaking core route logic. Core cannot be tested or reused without pulling in app providers. |
| **Potential impact** | Circular dependency risk as the codebase grows; harder unit testing; violated module boundaries in static analysis. |
| **Recommended solution** | Move `AuthSessionState` and `AuthSessionStatus` to `features/auth/domain/` (or `core/auth/models/`). Keep `AuthSessionNotifier` and Riverpod providers in `app/providers/`. Update imports across tests and router. |

---

## High Priority Issues

### H-01 — Permission redirects are split across `resolveRedirect` and `router.dart`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart`, `frontend/lib/app/router.dart` |
| **Evidence** | `_resolveRedirect` handles session/setup/login redirects only. Feature permission redirects (`adminSettingsRedirect`, `billingRouteRedirect`, `visitRouteRedirect`, etc.) are called separately in `router.dart` lines 274–312, and only when `session.currentView == StartupCurrentView.unauthenticatedEntry`. |
| **Why it's a problem** | Route guard logic is not self-contained. Developers calling `AuthRouteGuard.resolveRedirect` in isolation get incomplete protection. The misleading enum name `unauthenticatedEntry` (actually post-bootstrap steady state) obscures when permission gates run. |
| **Potential impact** | New routes added to `AuthRouteGuard` may be forgotten in `router.dart`; security gaps from orchestration drift. |
| **Recommended solution** | Consolidate into a single `AuthRouteGuard.resolveAllRedirects(...)` that chains session + feature permission checks. Document startup view preconditions or remove the `currentView` gate if permission checks should always apply post-bootstrap. |

---

### H-02 — Loading/unknown auth status allows protected routes to render

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart` |
| **Evidence** | `_resolveRedirect` returns `null` (no redirect) when `auth.status` is `unknown` or `loading`. Test confirms: *"loading session does not redirect"*. Feature permission redirects in `router.dart` still run, but only after startup reaches `unauthenticatedEntry`. |
| **Why it's a problem** | During session restoration or context reload, protected shells may flash before auth resolves. Permission redirects may not run if startup view is still `startupCheck`. |
| **Potential impact** | Brief exposure of protected UI; confusing UX during slow network; race between route render and permission denial. |
| **Recommended solution** | Redirect to a neutral holding route (e.g. `AppRoutes.startupCheck` or splash) while `status` is `unknown`/`loading` and `location` requires authentication. Alternatively, block `GoRouter` navigation at the shell level until auth is resolved. |

---

### H-03 — Billing settings permission logic diverges between `AuthRouteGuard` and `PermissionService`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart`, `frontend/lib/core/auth/permission_service.dart`, `frontend/lib/features/billing/presentation/providers/billing_settings_notifier.dart` |
| **Evidence** | `canAccessBillingSettings` uses `canViewInvoices() \|\| canRecordPayment()`. `PermissionService.canManageBillingSettings()` checks `PermissionKeys.settingsBillingManage`. Administrator seed includes `settingsBillingManage`; receptionist with only `invoices.view` passes route guard but lacks manage permission. |
| **Why it's a problem** | Two authoritative sources for the same feature. UI/route layer and action layer can disagree on who may access billing settings vs. who may mutate them. |
| **Potential impact** | Users reach settings UI but hit RPC `FORBIDDEN` on save; or users with `settings.billing.manage` could be blocked if they lack view/record keys (unlikely for admin seed, but fragile for custom permission matrix changes). |
| **Recommended solution** | Define a single policy function (e.g. `canAccessBillingSettings` delegates to `PermissionService` with explicit documented rules). Separate read vs. write helpers if intentional. Add tests asserting admin, receptionist, and custom-grant scenarios agree across route guard, notifier, and `PermissionService`. |

---

### H-04 — No unit tests for visit, shift, service catalog, or provisioning route redirects

| Field | Detail |
|-------|--------|
| **Severity** | High (test coverage gap with security implications) |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart`, `frontend/test/` |
| **Evidence** | Tests exist for billing, admin settings, patients (redirect only), and appointments. Grep finds **zero** tests for `visitRouteRedirect`, `shiftRouteRedirect`, `serviceCatalogRouteRedirect`, or `steadyStateProvisioningRedirect`. |
| **Why it's a problem** | ~120 lines of permission routing logic are unverified. Regressions (e.g. lab staff visit detail access via `canUploadVisitAttachments`) would go unnoticed. |
| **Potential impact** | Silent authorization bugs on release; especially risky for newer V1-5/V1-7 routes. |
| **Recommended solution** | Add `auth_route_guard_visits_test.dart`, `auth_route_guard_shifts_test.dart`, `auth_route_guard_service_catalog_test.dart`, and provisioning redirect tests mirroring billing test structure. |

---

### H-05 — Web deployment profile can serve stale cached config indefinitely

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `frontend/lib/core/config/deployment_profile_web_source.dart`, `frontend/lib/core/config/deployment_profile_store_web.dart` |
| **Evidence** | `resolveDeploymentProfileContents` fetches from origin; on any `Exception` or non-200, falls back to SharedPreferences cache with no TTL, version check, or invalidation. |
| **Why it's a problem** | After a clinic migrates Supabase URL or rotates anon key, offline or misconfigured web deploys continue using old cached endpoints. Silent catch `on Exception` hides fetch failures. |
| **Potential impact** | App connects to wrong/stale backend; auth failures; difficult ops debugging. |
| **Recommended solution** | Cache metadata (ETag, fetched-at timestamp). Reject cache older than N days or when `deployment_mode`/URL differs from last successful fetch. Surface fetch errors in startup UI instead of silent fallback. |

---

### H-06 — `PermissionDeniedHandler` is dead code in production

| Field | Detail |
|-------|--------|
| **Severity** | High (FR-009a compliance risk) |
| **Files involved** | `frontend/lib/core/auth/permission_denied_handler.dart` |
| **Evidence** | `PermissionDeniedHandler` is defined with `show` and `runIfPermitted`, but grep shows **no usages** in `frontend/lib/` outside its own file. Feature modules call `requirePermission` or inline checks without this handler. |
| **Why it's a problem** | Spec references FR-009a for consistent permission-denied feedback. The centralized handler exists but is unused, so UX is likely inconsistent across features. |
| **Potential impact** | Some actions fail silently or with generic errors; others may show snackbars ad hoc. |
| **Recommended solution** | Adopt `PermissionDeniedHandler.runIfPermitted` (or `show`) in feature action entry points, or remove the handler and document the chosen pattern. Add widget tests for snackbar display. |

---

## Medium Priority Issues

### M-01 — `PermissionDeniedException` defined in `permission_service.dart` instead of `core/errors/`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/auth/permission_service.dart`, `frontend/lib/core/errors/exceptions.dart` |
| **Evidence** | `PermissionDeniedException extends AppException` is declared at the bottom of `permission_service.dart`. Other domain exceptions (`MissingDeploymentProfileException`, etc.) live in `exceptions.dart`. |
| **Why it's a problem** | Exception taxonomy is fragmented. Consumers must import `permission_service.dart` to catch permission errors. |
| **Potential impact** | Import coupling; harder to discover exception types. |
| **Recommended solution** | Move `PermissionDeniedException` to `core/errors/exceptions.dart`. Re-export from `permission_service.dart` if needed for backward compatibility. |

---

### M-02 — `permission_denied_handler.dart` couples core to Flutter Material

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/auth/permission_denied_handler.dart` |
| **Evidence** | Core module imports `package:flutter/material.dart` and uses `ScaffoldMessenger`, `SnackBar`. |
| **Why it's a problem** | Core layer should not depend on UI framework. Prevents using permission logic in non-UI contexts (CLI, tests without widget tree). |
| **Potential impact** | Violates Clean Architecture; complicates headless testing of permission flows. |
| **Recommended solution** | Move handler to `app/` or `features/*/presentation/`. Keep `PermissionService` in core. Inject a `PermissionDeniedFeedback` interface if multiple surfaces need it. |

---

### M-03 — `auth_route_guard.dart` depends on `app/app_routes.dart`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart`, `frontend/lib/app/app_routes.dart` |
| **Evidence** | All route constants come from `AppRoutes` in the app layer. Service catalog uses a hardcoded `'/settings/services/'` prefix in one place while other routes use `AppRoutes` constants. |
| **Why it's a problem** | Core auth logic is bound to app routing definitions. Hardcoded path at line 314 can drift from `AppRoutes`. |
| **Potential impact** | Route renames break guards silently; module boundary violation. |
| **Recommended solution** | Introduce `core/routing/route_paths.dart` (or generate from a single source). Replace hardcoded `/settings/services/` with `AppRoutes` constant. |

---

### M-04 — `InMemoryGotrueAsyncStorage` uses process-wide static mutable state

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/config/in_memory_gotrue_async_storage.dart` |
| **Evidence** | `static final Map<String, String> _store = {}` shared across all instances. No `clear()` or test teardown hook. |
| **Why it's a problem** | PKCE/state from one test or bootstrap can leak into another within the same VM test run. |
| **Potential impact** | Flaky tests; hard-to-reproduce auth state pollution in boundary suites. |
| **Recommended solution** | Instance-level map per `InMemoryGotrueAsyncStorage`, or add `@visibleForTesting static void clear()` called from `SupabaseBootstrap.debugResetForTests()`. |

---

### M-05 — `supabase_config_env_stub.dart` cannot detect Flutter test runtime on web

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/config/supabase_config_env_stub.dart`, `frontend/lib/core/config/supabase_config.dart` |
| **Evidence** | Stub returns `isFlutterTestRuntimeFromEnvironment() => false` always. IO implementation checks `Platform.environment['FLUTTER_TEST']`. |
| **Why it's a problem** | Web-targeted `flutter test` runs may attempt real `Supabase.initialize` instead of `debugMarkReadyForTests()` stub path. |
| **Potential impact** | Web test failures, plugin missing errors, or unintended network calls in CI if web tests are enabled. |
| **Recommended solution** | Use `kIsWeb` + `const bool.fromEnvironment('FLUTTER_TEST')` or inject test detection via `SupabaseInitializer` override for web tests. |

---

### M-06 — `SupabaseBootstrap.ensureInitialized` ignores config changes after first call

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/config/supabase_config.dart` |
| **Evidence** | `ensureInitialized` returns early when `isReady` is true. `_pendingInitialization ??= _initialize(config)` coalesces concurrent calls but only the first `config` is used. |
| **Why it's a problem** | Profile hot-reload, test profile switching, or multi-tenant scenarios cannot re-initialize with a different URL/key without process restart. |
| **Potential impact** | Wrong Supabase project after profile change in dev; boundary tests sharing VM state. |
| **Recommended solution** | Document single-config assumption. For tests, always call `debugResetForTests()` between cases. Consider asserting `config.url` matches initialized instance if re-call attempted. |

---

### M-07 — `decodeAccessTokenClaims` does not verify JWT signature

| Field | Detail |
|-------|--------|
| **Severity** | Medium (expected for client UX, but risky if misused) |
| **Files involved** | `frontend/lib/core/config/supabase_config.dart`, `frontend/lib/app/providers/session_context_loader.dart` |
| **Evidence** | Function base64-decodes payload only. No HMAC/signature check. Expired tokens return `{}`. |
| **Why it's a problem** | Client-side claims are hints for routing only — acceptable if documented. Any future use for authorization decisions without server round-trip would be unsafe. |
| **Potential impact** | Forged JWT payload could influence client routing if an attacker controls token content (unlikely with Supabase-issued tokens, but defense-in-depth matters). |
| **Recommended solution** | Add doc comment: *"UX/routing only — never use for authorization."* Ensure `SessionContextLoader` always validates against server-loaded permissions. Add expired-token test (missing from `decode_access_token_claims_test.dart`). |

---

### M-08 — `canAccessAppointmentCancelActions` is unused dead API

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart` |
| **Evidence** | Method defined at lines 97–102; no references in `frontend/lib/` or tests. Appointment routing uses `canAccessAppointmentHub` and `canAccessAppointmentBooking` only. |
| **Why it's a problem** | Suggests incomplete appointment cancel gating. Cancel permission may be unchecked at route level. |
| **Potential impact** | Users without `appointments.cancel` may reach cancel UI (if page omits check). |
| **Recommended solution** | Wire into `appointmentRouteRedirect` for cancel-specific paths, or remove and document that cancel is page-gated only. |

---

### M-09 — `DeploymentProfile` validation lacks dedicated unit tests

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/config/deployment_profile.dart`, `frontend/test/` |
| **Evidence** | `fromJsonString`/`fromMap` validation (missing fields, invalid URLs, unsupported `deployment_mode`, bad `source_device_role`) is only indirectly tested via `deployment_profile_web_source_test.dart` happy path. No negative cases. |
| **Why it's a problem** | Startup error messages and edge cases (malformed URLs, empty anon key) are unverified. |
| **Potential impact** | Regressions in validation UX; unclear error messages for operators. |
| **Recommended solution** | Add `deployment_profile_test.dart` with table-driven invalid JSON cases and `toJson` round-trip. |

---

### M-10 — `deployment_profile_store_io.dart` untested

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files involved** | `frontend/lib/core/config/deployment_profile_store_io.dart` |
| **Evidence** | No unit tests for `AICLINIC_DEPLOYMENT_PROFILE_PATH` override, missing file exception, or default path resolution. |
| **Why it's a problem** | Desktop startup is the primary deployment target; file resolution is critical path. |
| **Potential impact** | Environment override bugs undetected until manual QA. |
| **Recommended solution** | Test with temporary directory and env var override using `fake_async`/`Directory.systemTemp`. |

---

## Low Priority Issues

### L-01 — Massive duplication of auth guard boilerplate

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/auth/auth_route_guard.dart` |
| **Evidence** | Pattern `if (!auth.isAuthenticated \|\| auth.context!.setupRequired) return false;` repeated 20+ times across `canAccess*` methods. Each `*RouteRedirect` repeats unauthenticated → login, setup → bootstrap blocks. |
| **Why it's a problem** | Maintenance burden; easy to omit a check when adding new routes. |
| **Potential impact** | Inconsistent guards on new features. |
| **Recommended solution** | Private helpers: `_requireAuthenticatedSetupComplete(AuthSessionState)` and `_baseFeatureRedirect(...)`. |

---

### L-02 — `IdleTimeoutService.updateIdleDuration` lacks unit test

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/auth/idle_timeout_service.dart`, `frontend/test/unit/auth/idle_timeout_service_test.dart` |
| **Evidence** | `updateIdleDuration` reschedules timer when enabled (lines 27–31). Test file covers enable/disable/recordActivity/dispose but not duration updates. |
| **Why it's a problem** | Settings feature changes idle duration at runtime; behavior unverified. |
| **Potential impact** | Minor: timer may not reschedule correctly after settings save. |
| **Recommended solution** | Add `fake_async` test: enable, elapse partial duration, `updateIdleDuration`, assert new deadline. |

---

### L-03 — `PermissionDeniedHandler.show` swallows all exceptions silently

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/auth/permission_denied_handler.dart` |
| **Evidence** | `catch (_) { // fail silently }` with no logging. |
| **Why it's a problem** | Legitimate errors (e.g. disposed widget) are indistinguishable from missing `ScaffoldMessenger`. |
| **Potential impact** | Hard to debug missing feedback in production. |
| **Recommended solution** | Log at `fine`/`warning` via `AppLog` in catch block. |

---

### L-04 — `canViewShifts` uses branch assignment only, not a permission key

| Field | Detail |
|-------|--------|
| **Severity** | Low (may be intentional) |
| **Files involved** | `frontend/lib/core/auth/permission_service.dart` |
| **Evidence** | `canViewShifts()` returns `context.hasBranchAssignment` only. `shifts.manage` is separate in `canManageShifts()`. No `shifts.view` key exists in `PermissionKeys`. |
| **Why it's a problem** | Any staff with a branch assignment can view shift calendar, regardless of role permissions matrix. |
| **Potential impact** | Broader shift visibility than RBAC matrix suggests. |
| **Recommended solution** | Confirm against spec. If intentional, document. If not, add `shifts.view` permission and seed grants. |

---

### L-05 — `SupabaseInitializer` adds thin wrapper with minimal test coverage

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/config/supabase_initializer.dart`, `frontend/test/unit/config/supabase_bootstrap_test.dart` |
| **Evidence** | Tests call `SupabaseBootstrap` directly, not `SupabaseInitializer` or `FakeSupabaseInitializer`. |
| **Why it's a problem** | DI wrapper is untested; overrides in tests may drift from production path. |
| **Potential impact** | Low; wrapper is trivial. |
| **Recommended solution** | Single test verifying `FakeSupabaseInitializer.initialize` is no-op and `isReady` is true. |

---

### L-06 — JWT `exp` check uses wall clock without test injection

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files involved** | `frontend/lib/core/config/supabase_config.dart` |
| **Evidence** | `DateTime.now().toUtc()` compared to claim expiry. No test for expired tokens in `decode_access_token_claims_test.dart`. |
| **Why it's a problem** | Expiry logic is unverified; clock skew untested. |
| **Potential impact** | Stale claims might be used near expiry boundary. |
| **Recommended solution** | Add test with `exp` in past. Optional: inject `Clock` for deterministic tests. |

---

## Clean Architecture Violations

| ID | Violation | Files | Recommended Fix |
|----|-----------|-------|-----------------|
| CA-01 | Core imports app layer (`auth_session_provider`, `app_routes`) | `auth_route_guard.dart` | Move shared types/paths to domain/core |
| CA-02 | Core contains Flutter UI (`permission_denied_handler.dart`) | `permission_denied_handler.dart` | Relocate to presentation layer |
| CA-03 | `PermissionService` correctly in core, but route guard mixes policy with app routes | `auth_route_guard.dart` | Extract route policy interface; inject route registry |
| CA-04 | `decodeAccessTokenClaims` in config module used for auth domain concerns | `supabase_config.dart` | Move to `features/auth/data/` or `core/auth/jwt.dart` |
| CA-05 | `IdleTimeoutConfig` in features imports core constant — acceptable direction | `idle_timeout_config.dart` | No change needed (feature → core is valid) |

---

## SOLID Violations

| ID | Principle | Violation | Files | Fix |
|----|-----------|-----------|-------|-----|
| S-01 | SRP | `AuthRouteGuard` (~540 lines) handles route taxonomy, permission policy, redirects, and logging | `auth_route_guard.dart` | Split: `RouteClassifier`, `FeatureAccessPolicy`, `AuthRedirectResolver` |
| S-02 | SRP | `supabase_config.dart` mixes config model, bootstrap singleton, Riverpod provider, and JWT decoding | `supabase_config.dart` | Split into separate files |
| O-01 | OCP | Adding a feature area requires editing `requiresAuthentication`, new `is*Route`, `canAccess*`, `*RouteRedirect`, and `router.dart` | `auth_route_guard.dart`, `router.dart` | Registry/map-driven route policies |
| D-01 | DIP | `AuthRouteGuard` statically depends on concrete `PermissionService` | `auth_route_guard.dart` | Accept `PermissionEvaluator` interface (optional; low ROI for static guards) |
| I-01 | ISP | `PermissionService` exposes many feature methods; consumers need subset | `permission_service.dart` | Acceptable for facade pattern; could split by feature if it grows |

---

## Code Duplication & Redundancy

1. **Auth guard boilerplate** — 20+ identical `isAuthenticated && !setupRequired` checks (`auth_route_guard.dart`).
2. **Redirect preamble** — Each `*RouteRedirect` duplicates unauthenticated → login and setup → bootstrap logic.
3. **Billing settings policy** — `canAccessBillingSettings` vs `canManageBillingSettings` overlap without shared naming.
4. **Environment detection** — `supabase_config_env_io.dart` vs stub duplicate function signatures (acceptable for conditional import pattern).
5. **Dead APIs** — `canAccessAppointmentCancelActions`, `PermissionDeniedHandler` (unused), `canManageBillingSettings` partially superseded by route guard logic.

---

## Performance Issues

| ID | Issue | Severity | Evidence | Impact |
|----|-------|----------|----------|--------|
| P-01 | `PermissionService` instantiated per `canAccess*` call | Low | `PermissionService(auth.context)` created repeatedly in same redirect chain | Minor allocations on navigation; negligible at current scale |
| P-02 | Web profile fetch blocks startup up to 5s | Low | `fetchTimeout = Duration(seconds: 5)` in `deployment_profile_web_source.dart` | Slow first paint on poor networks before cache fallback |
| P-03 | `authSessionProvider.select` in `SessionActivityScope` rebuilds on any auth change | Low | `ref.watch(authSessionProvider.select(...))` | Acceptable; only wraps authenticated keyboard tracking |

No significant performance defects identified for clinic desktop scale.

---

## Test Coverage Gaps

| Module | Covered | Gaps |
|--------|---------|------|
| `AuthRouteGuard.resolveRedirect` | Yes (unit + integration) | Loading-state interaction with feature redirects |
| `AuthRouteGuard` billing/admin/patients/appointments | Yes | **Visits, shifts, service catalog, provisioning** |
| `PermissionService` | Yes (core + per-feature) | — |
| `PermissionDeniedHandler` | **None** | Widget test for snackbar |
| `IdleTimeoutService` | Strong | `updateIdleDuration` |
| `DeploymentProfile` | Partial (happy path) | Validation errors, `toJson`, URI edge cases |
| `DeploymentProfileStore` IO | **None** | Path override, missing file |
| `DeploymentProfileStore` web | Partial | Full integration with SharedPreferences |
| `deployment_profile_web_source` | Yes | Timeout, empty body, non-JSON 200 |
| `SupabaseBootstrap` | Minimal | `ensureInitialized` failure/retry, concurrent calls |
| `SupabaseInitializer` | **None** | Fake initializer |
| `InMemoryGotrueAsyncStorage` | **None** | Isolation between instances |
| `decodeAccessTokenClaims` | Partial | Expired `exp`, clock edge cases |
| `supabaseClientProvider` | **None** | Throws when not ready |

---

## Recommended Refactoring

### Phase 1 — Security & architecture (1–2 sprints)

1. Move `AuthSessionState` / `AuthSessionStatus` to domain layer (**C-02**).
2. Add router-level patient permission redirects (**C-01**).
3. Consolidate redirect orchestration into single entry point (**H-01**).
4. Unify billing settings permission policy (**H-03**).
5. Add missing route guard tests (**H-04**).

### Phase 2 — Reliability (1 sprint)

6. Web profile cache invalidation strategy (**H-05**).
7. Loading-state redirect policy (**H-02**).
8. `InMemoryGotrueAsyncStorage` test isolation (**M-04**).
9. Adopt or remove `PermissionDeniedHandler` (**H-06**).

### Phase 3 — Maintainability (ongoing)

10. Extract route paths to core (**M-03**).
11. Deduplicate guard boilerplate (**L-01**).
12. Split `AuthRouteGuard` and `supabase_config.dart` by SRP (**S-01**, **S-02**).
13. Complete config validation test suite (**M-09**, **M-10**).

---

## Appendix — File Inventory

| File | Lines | Role |
|------|-------|------|
| `auth_route_guard.dart` | 539 | Route classification, permission checks, redirects |
| `permission_service.dart` | 109 | Cached permission evaluation |
| `permission_denied_handler.dart` | 46 | Snackbar UX for denials |
| `idle_timeout_service.dart` | 79 | Inactivity timer |
| `supabase_config.dart` | 176 | Config model, bootstrap, JWT decode, provider |
| `supabase_config_env_io.dart` | 8 | VM test env detection |
| `supabase_config_env_stub.dart` | 6 | Web/non-IO stub |
| `supabase_initializer.dart` | 27 | DI wrapper |
| `deployment_profile.dart` | 162 | Profile model + validation |
| `deployment_profile_store.dart` | 22 | Platform-agnostic facade |
| `deployment_profile_store_io.dart` | 41 | Desktop file loading |
| `deployment_profile_store_web.dart` | 37 | Web HTTP + cache loading |
| `deployment_profile_web_source.dart` | 35 | Web fetch/cache logic |
| `in_memory_gotrue_async_storage.dart` | 22 | PKCE in-memory store |
