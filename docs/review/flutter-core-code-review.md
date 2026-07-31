# Flutter Core Module — Code Review

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/` (41 files across auth, config, rpc, errors, logging, data, utils, ui)  
**Method:** Four parallel skeptical reviews; findings consolidated here.  
**Detail reports:** [auth & config](flutter-core-review-auth-config.md) · [RPC/errors/data](flutter-core-review-rpc-errors-data.md) · [UI theme](flutter-core-review-ui-theme.md) · [UI components](flutter-core-review-ui-components.md)

---

## Executive Summary

`frontend/lib/core` is the shared foundation every feature depends on: Supabase bootstrap, route/permission gating, RPC invocation, structured logging, design tokens, and shell primitives. The **RPC invoker pattern** (`AppRpcInvoker` + `RpcResult`) is sound and widely adopted. **PermissionService** correctly documents UX-only gating with server enforcement. The **three-tier theme architecture** (primitives → semantic extensions → `ThemeData`) is the right shape.

The module's main weaknesses cluster into four themes:

1. **Layer boundary violations** — Core imports app-layer types (`AuthSessionState`, `AppRoutes`); domain code hardcodes presentation colors; `AppBadgeTone` lives in appointments domain without a presentation counterpart.
2. **Defense-in-depth gaps** — Patient routes skip router-level permission checks; auth loading state allows protected routes to flash; unwired error mappers leave users seeing raw RPC strings.
3. **Dead or duplicated infrastructure** — `UserErrorMapper`, `PaginatedListNotifier`, `date_format_utils`, and `PermissionDeniedHandler` are unused; bootstrap/provisioning/shifts duplicate RPC logic; auth guard boilerplate is copy-pasted ~20×.
4. **Design-system immaturity** — Semantic tokens cover ~40% of spec; UI primitives implement ~5% of component spec; almost no automated tests for theme or shell widgets.

**Verdict:** Usable foundation with clear patterns, but security orchestration is inconsistent, error UX is fragmented, and the design system needs completion plus CI guardrails before feature screens proliferate ad-hoc copies.

| Area | Critical | High | Medium | Low |
|------|----------|------|--------|-----|
| Auth & config | 2 | 6 | 10 | 6 |
| RPC/errors/data | 1* | 5 | — | — |
| UI theme | 0 | 7 | 11 | 6 |
| UI components | 2 | 9 | 11 | 8 |
| **Total (indexed)** | **5** | **27** | **32** | **20** |

\*`PaginatedListNotifier` race is critical **if adopted**; zero adopters today.

---

## 1. Critical Issues

### C-01 — Patient routes skip router-level permission enforcement

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `core/auth/auth_route_guard.dart`, `app/router.dart` |
| **Evidence** | `patientRouteRedirect` returns `null` after auth/setup for any authenticated user. Billing, visits, shifts, and appointments enforce permissions at the router. |
| **Why** | Direct URL navigation (`/patients`, `/patients/new`, `/patients/:id/edit`) bypasses permission gates. In-page guards may be missing on new routes. |
| **Impact** | Unauthorized staff see patient UI shells; inconsistent security posture; regression risk. |
| **Solution** | Map patient routes to `canAccessPatientList`, `canAccessPatientRegistration`, `canAccessPatientEdit`; redirect to home when denied. Keep server RPC enforcement. |

### C-02 — `AuthSessionState` in app layer forces core → app dependency

| Field | Detail |
|-------|--------|
| **Severity** | Critical (architecture) |
| **Files** | `core/auth/auth_route_guard.dart`, `app/providers/auth_session_provider.dart` |
| **Evidence** | `auth_route_guard.dart` imports `auth_session_provider.dart` for `AuthSessionState` / `AuthSessionStatus`. |
| **Why** | Inverts Clean Architecture: core must not depend on app/presentation wiring. |
| **Impact** | Core untestable in isolation; circular dependency risk; static analysis violations. |
| **Solution** | Move `AuthSessionState` and `AuthSessionStatus` to `features/auth/domain/` (or `core/auth/models/`). Keep Riverpod notifiers in app layer. |

### C-03 — `AppBadgeTone` domain enum has no widget counterpart

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `features/appointments/domain/appointment_queue_display.dart`, `core/ui/components/app_badge.dart` |
| **Evidence** | Domain defines `AppBadgeTone { neutral, info, success, warning, destructive, muted }` and status→tone mapping. `AppBadge` accepts only `label` with fixed neutral styling. |
| **Why** | Presentation contract is defined in domain; widget cannot express it. |
| **Impact** | Queue UI will bypass `AppBadge` or duplicate inline styling (precedent exists in `app_top_bar.dart`). |
| **Solution** | Add tone/variant API to `AppBadge` per design spec D7; move tone enum to core/presentation; map domain status → tone in presentation only. |

### C-04 — Zero automated tests for shell-critical UI primitives

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `core/ui/components/*`, `app/shell/navigation/*` |
| **Evidence** | No widget/golden tests for `AppIconButton`, `AppSignal`, `AppBadge`, `AppAvatar`, `AppTooltip` despite shell usage on every route. |
| **Why** | Nav indicator, avatar initials, AI pulse lifecycle, and a11y labels are unguarded in CI. |
| **Impact** | Silent regressions in shell affect entire app; animation controller leaks undetected. |
| **Solution** | Add `test/widget/core/ui/` suite with theme variants, `AppSignal` dispose, avatar edge cases, semantics checks. |

### C-05 — `PaginatedListNotifier` refresh/loadMore race (latent)

| Field | Detail |
|-------|--------|
| **Severity** | Critical if adopted |
| **Files** | `core/data/paginated_list_notifier.dart` |
| **Evidence** | `loadMore()` has no generation token; stale completion overwrites state after `refresh()` sets `AsyncLoading`. `nextOffset` uses `offset + limit` not `offset + items.length`. |
| **Why** | No request cancellation or post-async guard. |
| **Impact** | Stale merged pages or skipped data when adopted for patient/service lists. |
| **Solution** | Add monotonic `_requestGeneration`; fix offset calculation; add unit tests before first adoption. |

---

## 2. High Priority Issues

### Security & auth

| ID | Issue | Files | Impact |
|----|-------|-------|--------|
| H-A1 | Permission redirects split across `resolveRedirect()` and `router.dart` | `auth_route_guard.dart`, `router.dart` | New routes easily miss permission gates |
| H-A2 | Loading/unknown auth status allows protected routes to render | `auth_route_guard.dart` | Protected UI flashes before auth resolves |
| H-A3 | Billing settings policy diverges between guard and `PermissionService` | `auth_route_guard.dart`, `permission_service.dart` | Inconsistent access to billing settings |
| H-A4 | No tests for visit/shift/service-catalog/provisioning route redirects | `auth_route_guard.dart`, `frontend/test/` | Security regressions undetected |
| H-A5 | Web deployment profile stale cache (no TTL/invalidation) | `deployment_profile_store_web.dart` | Wrong Supabase URL after server profile change |

### RPC & errors

| ID | Issue | Files | Impact |
|----|-------|-------|--------|
| H-R1 | `UserErrorMapper` dead; 4 feature `*MessageForRpc` mappers tested but unwired | `user_error_mapper.dart`, feature `application/*_rpc_messages.dart` | Users see raw server errors |
| H-R2 | `AppRpcInvoker` misses transport/parse errors | `app_rpc_invoker.dart` | `FormatException`, `SocketException` reach UI as raw strings |
| H-R3 | RPC `error_message` logged without PHI redaction | `app_rpc_invoker.dart`, `app_log.dart` | Patient names in logs |
| H-R4 | Duplicate RPC invoker in bootstrap/provisioning/shifts | `bootstrap_repository.dart`, `provisioning_repository.dart`, `shift_repository.dart` | Behavioral drift, missing `AuthException` handling |

### UI theme & components

| ID | Issue | Files | Impact |
|----|-------|-------|--------|
| H-U1 | No automated theme/token/contrast tests | `core/ui/theme/*`, `frontend/test/` | WCAG claims unenforced in CI |
| H-U2 | `AppSemanticColors` ~40% of spec | `app_semantic_colors.dart`, `02-tokens.md` | Features hardcode missing tokens |
| H-U3 | Domain hardcodes `Color(0xFF…)` for calendar | `appointment_calendar_display.dart` | CA violation; dark mode breakage |
| H-U4 | `AppTheme.light()/dark()` rebuilt every `build` | `app_theme.dart`, `AiClinicApp` | Unnecessary Google Fonts work |
| H-U5 | `ThemeData` under-specified (no component themes) | `app_theme.dart` | Material widgets diverge from design system |
| H-U6 | Typography diverges from spec (Inter vs Geist/IBM Plex) | `app_typography.dart` | Brand inconsistency |
| H-U7 | `AppBadge` ~5% of D7 spec | `app_badge.dart` | Status chips won't match design |
| H-U8 | `AppIconButton` missing variants/states/motion | `app_icon_button.dart` | Shell-only ghost buttons |
| H-U9 | `AppAvatar` missing image, sizes, semantics | `app_avatar.dart`, `app_user_menu.dart` | A11y gaps on menu trigger |
| H-U10 | `widgets.dart` barrel documented but never imported | `widgets.dart`, `forui-wrappers.md` | Convention drift; Forui wrappers don't exist |

### Dead code

| ID | Issue | Files |
|----|-------|-------|
| H-D1 | `PermissionDeniedHandler` never called | `permission_denied_handler.dart` |
| H-D2 | `date_format_utils.dart` unused | `date_format_utils.dart` |

---

## 3. Medium Priority Issues

Consolidated highlights (full detail in area reports):

**Auth/config:** `PermissionDeniedException` in wrong file; Flutter Material in core (`permission_denied_handler.dart`); core depends on `app_routes.dart`; `InMemoryGotrueAsyncStorage` static mutable state; `SupabaseBootstrap` ignores config after first init; JWT decode without signature verify (acceptable for UX claims, document risk); `DeploymentProfile` validation undertested.

**RPC/data:** `RpcFailure` in `rpc_result.dart` not `errors/`; `exceptions.dart`/`failures.dart` serve startup only; `_coerceData` swallows JSON parse errors; `AppFailure.recoverable` flag unused.

**UI theme:** Motion re-export naming confusion; `AppShellTokens.collapseDuration` not aligned with motion tokens; light-only elevation aliases; force-unwrap theme extensions; incomplete motion presets; silent fallback on typo'd token names; `AppContrast` not enforced; palette duplication in `foundation_constants.dart`.

**UI components:** `AppTooltip` passthrough; `AppSignal` active=false still full opacity; pulse runs when inactive+thinking; avatar initials diverge from web; unsafe grapheme indexing; dual motion import paths; missing status surface tokens for badges.

---

## 4. Low Priority Issues

Auth guard boilerplate duplication (~20 identical checks); `IdleTimeoutService.updateIdleDuration` untested; `canViewShifts` uses branch assignment not permission key; JWT `exp` without clock injection; theme `lerp` step function; magic spacing numbers; shell density variants not implemented; `AppMotionEasing.emphasized` identical to `standard`; missing `const` on some shell widgets.

---

## 5. Clean Architecture Violations

| ID | Violation | Direction | Files | Fix |
|----|-----------|-----------|-------|-----|
| CA-01 | Core imports app layer | core → app ❌ | `auth_route_guard.dart` | Move session types to domain |
| CA-02 | Core imports app routes | core → app ❌ | `auth_route_guard.dart` | Extract route path registry to core or domain |
| CA-03 | Flutter UI in core | presentation in infrastructure | `permission_denied_handler.dart` | Move to `app/` or `features/` presentation |
| CA-04 | Domain hardcodes colors | domain → Flutter | `appointment_calendar_display.dart` | Use semantic tokens via presentation mapper |
| CA-05 | `AppBadgeTone` in domain | domain owns presentation enum | `appointment_queue_display.dart` | Move tone to core/ui; map in presentation |
| CA-06 | Presentation imports RPC types directly | acceptable for Riverpod notifiers | various notifiers | Introduce domain error types at boundary |
| CA-07 | JWT decode in config used for auth | mixed concerns | `supabase_config.dart` | Move to `core/auth/jwt.dart` |
| CA-08 | `exceptions.dart`/`failures.dart` startup-only | runtime RPC bypasses both | `errors/*` | Unify presentation error model |

**Dependency rule summary:** Feature → core is correct. Core → feature (auth domain) is acceptable for `AuthSessionContext`. Core → app is the primary violation. Domain → Flutter `Color` is a secondary violation.

---

## 6. SOLID Violations

| Principle | Violation | Files | Recommendation |
|-----------|-----------|-------|----------------|
| **SRP** | `AuthRouteGuard` (~540 lines): taxonomy + policy + redirects + logging | `auth_route_guard.dart` | Split `RouteClassifier`, `FeatureAccessPolicy`, `AuthRedirectResolver` |
| **SRP** | `supabase_config.dart`: config + bootstrap singleton + provider + JWT decode | `supabase_config.dart` | Split into separate files |
| **SRP** | `AppTooltip` adds no behavior | `app_tooltip.dart` | Implement themed defaults or remove |
| **OCP** | New feature area requires edits in guard + router + new `canAccess*` + `*RouteRedirect` | `auth_route_guard.dart`, `router.dart` | Registry/map-driven route policies |
| **LSP** | `AppBadge` name implies full badge; implements count chip only | `app_badge.dart` | Rename or complete API |
| **ISP** | `PermissionService` exposes many methods | `permission_service.dart` | Acceptable facade; split if it grows |
| **DIP** | `AuthRouteGuard` statically uses concrete `PermissionService` | `auth_route_guard.dart` | Optional `PermissionEvaluator` interface |

---

## 7. Code Duplication & Redundancy

| Duplication | Where | Should consolidate? |
|-------------|-------|---------------------|
| Auth guard boilerplate | 20+ `isAuthenticated && !setupRequired` checks | Yes — extract `_guardAuthenticated()` helper or policy object |
| Redirect preamble | Each `*RouteRedirect` duplicates login/bootstrap checks | Yes — chain in single resolver |
| RPC invoke pattern | Bootstrap, provisioning, shifts vs `AppRpcInvoker` | Yes — migrate to mixin |
| Notification badge | `app_top_bar.dart` inline vs `AppBadge` | Yes — extend `AppBadge` or add `AppNotificationBadge` |
| Error mappers | `UserErrorMapper` + 6 feature `*MessageForRpc` | Yes — one strategy: delegate or delete dead code |
| Palette hex values | `app_color_primitives.dart` + `foundation_constants.dart` | Yes — single source |
| Motion import paths | `ui/motion/` and `ui/theme/app_motion.dart` re-export | Document one canonical path |
| Dead APIs | `PermissionDeniedHandler`, `canAccessAppointmentCancelActions`, `date_format_utils`, `UserErrorMapper`, `PaginatedListNotifier` | Adopt or delete |

Motion files are **not** duplicated — `theme/app_motion.dart` is a one-line re-export.

---

## 8. Performance Issues

| Issue | Severity | Files | Notes |
|-------|----------|-------|-------|
| `AppTheme` rebuilt every `AiClinicApp.build` | Medium | `app_theme.dart` | Cache `ThemeData` as `static final` or provider |
| Google Fonts resolved 3× per theme build | Medium | `app_typography.dart` | Preload or cache text themes |
| `AppSignal` LayoutBuilder + AnimatedBuilder per instance | Low | `app_signal.dart` | Acceptable at shell scale |
| `PermissionService` instantiated per redirect check | Low | `auth_route_guard.dart` | Negligible at clinic scale |
| Web profile fetch blocks startup up to 5s | Low | `deployment_profile_web_source.dart` | Cache fallback mitigates |

No critical performance defects for desktop clinic scale.

---

## 9. Test Coverage Gaps

| Module | Covered | Missing |
|--------|---------|---------|
| `AuthRouteGuard` session redirects | ✅ | Loading + feature redirect interaction |
| Feature route redirects (visits/shifts/catalog/provisioning) | ❌ | All four |
| `PermissionService` | ✅ | — |
| `PermissionDeniedHandler` | ❌ | Widget test |
| `IdleTimeoutService` | ✅ strong | `updateIdleDuration` |
| `DeploymentProfile` | partial | Validation errors, URI edge cases |
| `DeploymentProfileStore` IO | ❌ | Path override, missing file |
| `SupabaseBootstrap` | minimal | Concurrent init, config change |
| `InMemoryGotrueAsyncStorage` | ❌ | Instance isolation |
| `RpcResult` parsing | ✅ strong | JSON string edge cases |
| `AppRpcInvoker` | minimal | All catch branches |
| `UserErrorMapper` | ❌ | All branches |
| `PaginatedListNotifier` | ❌ | Race, offset, partial page |
| Theme tokens / contrast | ❌ | Entire design system |
| UI primitives (badge, signal, avatar, icon button) | ❌ | Shell-critical widgets |
| Feature `*MessageForRpc` | ✅ unit tests | UI wiring (tests don't protect unwired mappers) |

---

## 10. Recommended Refactoring

### Phase 1 — Security & boundaries (1–2 sprints)

1. Add router-level patient permission redirects (**C-01**).
2. Move `AuthSessionState` to domain (**C-02**).
3. Consolidate redirect orchestration into single `resolveAllRedirects()` (**H-A1**).
4. Unify billing settings permission policy (**H-A3**).
5. Add missing route guard tests (**H-A4**).
6. Fix auth loading-state redirect policy (**H-A2**).

### Phase 2 — Error & RPC consistency (1 sprint)

7. Wire `*MessageForRpc` into all notifiers or delete dead `UserErrorMapper` (**H-R1**).
8. Add catch-all to `AppRpcInvoker` for transport/parse errors (**H-R2**).
9. Log RPC error codes only; expand `AppLog` redaction (**H-R3**).
10. Migrate bootstrap/provisioning/shifts to `AppRpcInvoker` (**H-R4**).
11. Move `RpcFailure` to `core/errors/`; add `app_rpc_invoker_test.dart`.

### Phase 3 — Design system completion (1–2 sprints)

12. Extend `AppBadge` with tone/variant API; move `AppBadgeTone` to presentation (**C-03**).
13. Add widget tests for shell primitives (**C-04**).
14. Expand `AppSemanticColors` toward spec; add contrast enforcement tests (**H-U1**, **H-U2**).
15. Cache `ThemeData`; add component themes (**H-U4**, **H-U5**).
16. Remove domain hardcoded colors (**H-U3**).
17. Adopt or remove `widgets.dart` barrel; update docs (**H-U10**).

### Phase 4 — Hardening (ongoing)

18. Fix or delete `PaginatedListNotifier` before adoption (**C-05**).
19. Web profile cache invalidation (**H-A5**).
20. Split `AuthRouteGuard` and `supabase_config.dart` by SRP.
21. Adopt or delete `PermissionDeniedHandler` (**H-D1**).
22. Deduplicate auth guard boilerplate.

---

## Module Map

```
frontend/lib/core/
├── auth/          Route guard, permissions, idle timeout, denial handler
├── config/        Deployment profile, Supabase bootstrap, JWT decode
├── rpc/           AppRpcInvoker mixin, RpcResult parsing
├── errors/        Startup exceptions & failures
├── logging/       AppLog with redaction
├── data/          PaginatedListNotifier (unused)
├── utils/         Error mapper, date format, copyWith sentinel
└── ui/
    ├── theme/     Design tokens, ThemeData, semantic extensions
    ├── motion/    Durations, easings, presets, reduced motion
    ├── components/ Shell primitives (badge, avatar, signal, icon button, tooltip)
    └── widgets/   Barrel export (unused in production)
```

---

## Conclusion

The core module establishes the right **patterns** (RPC mixin, permission facade, theme extensions) but is mid-migration: several utilities were scaffolded and never wired, security gating is inconsistent across features, and the design system is early-stage with minimal test coverage. **Highest ROI fixes:** patient route permissions, session type relocation, error mapper wiring, `AppRpcInvoker` hardening, and `AppBadge` API completion before appointments queue UI ships.

For file-level evidence and additional medium/low findings, see the four area reports linked at the top.

---

## Second Cycle Review (2026-07-05)

**Method:** Four parallel skeptical re-reviews of `frontend/lib/core/` against first-cycle baselines. Every file re-read; cross-file grep validation; first-cycle Critical/High/Medium status verified with code evidence.

**Area reports:** [auth & config](flutter-core-second-cycle-auth-config.md) · [RPC/errors/data](flutter-core-second-cycle-rpc-errors-data.md) · [UI theme](flutter-core-second-cycle-ui-theme.md) · [UI components](flutter-core-second-cycle-ui-components.md)

### Executive Summary

**Fixes since first cycle:** **0** findings fully resolved. **2** partial improvements:

- `permissionMessageForRpc` wired in `role_permissions_notifier.dart` (RPC HP-01 / H-R1)
- `forui: ^0.22.3` added to `pubspec.yaml` without wrappers or imports (components H-09)

**Overall verdict:** The core foundation patterns remain sound (RPC mixin, permission facade, theme extensions), but **no material remediation** landed. Security orchestration gaps (patient routes, auth loading flash), error UX fragmentation (8 unwired mapper families), and design-system immaturity (zero theme/component CI tests, `AppBadge` without tone API) are **unchanged or widened** — domain `AppBadgeTone` now exists while the widget layer does not.

### Finding Counts (second cycle)

| Area | Critical | High | Medium | Notes |
|------|----------|------|--------|-------|
| Auth & config | 2 | 6 | 10 | 0 fixes |
| RPC/errors/data | 1 | 6 | 11 | 1 partial (mapper wiring); 1 new High |
| UI theme | 0 | 10 | 13 | 3 new High; 3 new Medium |
| UI components | 2 | 9 | 13 | 1 partial (forui dep); 2 new Medium |
| **Total** | **5** | **31** | **47** | Deduplicated IDs below |

\*RPC Critical (`PaginatedListNotifier` race) = consolidated **C-05** (latent — zero adopters).

### First-Cycle Critical Status Tracker

| ID | Issue | Second-cycle status |
|----|-------|---------------------|
| **C-01** | Patient routes skip router-level permission enforcement | **STILL OPEN** — `patientRouteRedirect` returns `null` after auth/setup |
| **C-02** | `AuthSessionState` in app layer forces core → app dependency | **STILL OPEN** — `auth_route_guard.dart` still imports `auth_session_provider.dart` |
| **C-03** | `AppBadgeTone` domain enum has no widget counterpart | **STILL OPEN** — domain mapper added; `AppBadge` still label-only |
| **C-04** | Zero automated tests for shell-critical UI primitives | **STILL OPEN** — no `test/widget/` tree; calendar tests lock bad hex |
| **C-05** | `PaginatedListNotifier` refresh/loadMore race (latent) | **STILL OPEN** — no generation token; offset formula unchanged |

---

## Critical Issues (deduplicated)

### SC2-C01 — Patient routes skip router-level permission enforcement

*Consolidates C-01 · [auth second-cycle](flutter-core-second-cycle-auth-config.md#c-01--patient-routes-skip-router-level-permission-enforcement)*

Authenticated users with setup complete can navigate to `/patients/*` without permission checks at the router. `canAccessPatient*` helpers exist but are unused in `patientRouteRedirect`.

### SC2-C02 — `AuthSessionState` in app layer forces core → app dependency

*Consolidates C-02 · [auth second-cycle](flutter-core-second-cycle-auth-config.md#c-02--authsessionstate-lives-in-app-layer-but-is-required-by-core)*

Core `AuthRouteGuard` imports `app/providers/auth_session_provider.dart` for session envelope types.

### SC2-C03 — `AppBadgeTone` without widget API

*Consolidates C-03 · [components second-cycle](flutter-core-second-cycle-ui-components.md#c-01--appbadgetone-without-widget-api)*

Domain defines `AppBadgeTone` + `scheduleBadgeTone()`; `AppBadge` accepts only `label` with fixed neutral styling. Gap is **wider** than first cycle.

### SC2-C04 — Zero automated tests for shell-critical UI primitives

*Consolidates C-04 · spans [components](flutter-core-second-cycle-ui-components.md#c-02--zero-component-widgetgolden-tests) + [theme](flutter-core-second-cycle-ui-theme.md#h-01--no-automated-theme-or-token-tests-first-cycle-still-open)*

No widget/golden tests for `AppIconButton`, `AppSignal`, `AppBadge`, `AppAvatar`, `AppTooltip`, or theme/contrast/motion APIs. Calendar unit tests **actively lock** non-spec hardcoded colors (theme NH-02).

### SC2-C05 — `PaginatedListNotifier` race and offset defects (latent)

*Consolidates C-05 · [RPC second-cycle](flutter-core-second-cycle-rpc-errors-data.md#cr-01--paginatedlistnotifierloadmore-can-overwrite-an-in-flight-refresh)*

No generation token; `nextOffset` uses `offset + limit` not `offset + items.length`. Zero adopters today.

---

## High Priority Issues

### Security & auth

| ID | Issue | Status | Area report |
|----|-------|--------|-------------|
| SC2-H01 | Permission redirects split across `resolveRedirect()` and `router.dart` | STILL OPEN | [auth](flutter-core-second-cycle-auth-config.md#h-01--permission-redirects-split-across-resolveredirect-and-routerdart) |
| SC2-H02 | Loading/unknown auth status allows protected routes to render | STILL OPEN | [auth](flutter-core-second-cycle-auth-config.md#h-02--loadingunknown-auth-status-allows-protected-routes-to-render) |
| SC2-H03 | Billing settings policy diverges between guard and `PermissionService` | STILL OPEN | [auth](flutter-core-second-cycle-auth-config.md#h-03--billing-settings-permission-logic-diverges-between-guard-and-permissionservice) |
| SC2-H04 | No tests for visit/shift/service-catalog/provisioning route redirects | STILL OPEN | [auth](flutter-core-second-cycle-auth-config.md#h-04--no-unit-tests-for-visit-shift-service-catalog-or-provisioning-route-redirects) |
| SC2-H05 | Web deployment profile stale cache (no TTL/invalidation) | STILL OPEN | [auth](flutter-core-second-cycle-auth-config.md#h-05--web-deployment-profile-can-serve-stale-cached-config-indefinitely) |
| SC2-H06 | `PermissionDeniedHandler` never called | STILL OPEN | [auth](flutter-core-second-cycle-auth-config.md#h-06--permissiondeniedhandler-is-dead-code-in-production) |

### RPC & errors

| ID | Issue | Status | Area report |
|----|-------|--------|-------------|
| SC2-H07 | Feature `*MessageForRpc` mappers mostly unwired; `UserErrorMapper` dead | **PARTIALLY FIXED** | [RPC](flutter-core-second-cycle-rpc-errors-data.md#hp-01--feature-messageforrpc-mappers-mostly-unwired-usererrormapper-dead) |
| SC2-H08 | `AppRpcInvoker` misses transport/parse errors | STILL OPEN | [RPC](flutter-core-second-cycle-rpc-errors-data.md#hp-02--apprpcinvoker-leaves-transportparse-errors-unmapped) |
| SC2-H09 | RPC `error_message` logged without PHI redaction | STILL OPEN | [RPC](flutter-core-second-cycle-rpc-errors-data.md#hp-03--rpc-rejection-messages-logged-without-phi-redaction) |
| SC2-H10 | Duplicate RPC invoker in bootstrap/provisioning/shifts | STILL OPEN | [RPC](flutter-core-second-cycle-rpc-errors-data.md#hp-05--duplicate-rpc-invoker-implementations-diverge-from-apprpcinvoker) |
| SC2-H11 | `PaginatedListNotifier` offset formula inconsistent | STILL OPEN | [RPC](flutter-core-second-cycle-rpc-errors-data.md#hp-04--paginatedlistnotifier-uses-offset--limit-instead-of-offset--itemslength) |

*Deduplication:* SC2-H07 subsumes first-cycle **H-R1** and RPC **SC2-H01** (expanded unwired mapper inventory for settings org/branch/staff + shifts).

### UI theme

| ID | Issue | Status | Area report |
|----|-------|--------|-------------|
| SC2-H12 | No automated theme/token/contrast/motion tests | STILL OPEN | [theme](flutter-core-second-cycle-ui-theme.md#h-01--no-automated-theme-or-token-tests-first-cycle-still-open) |
| SC2-H13 | `AppSemanticColors` ~40% of spec | STILL OPEN | [theme](flutter-core-second-cycle-ui-theme.md#h-02--appsemanticcolors-covers-40-of-documented-semantic-tokens-still-open) |
| SC2-H14 | Domain hardcodes `Color(0xFF…)` for calendar | STILL OPEN | [theme](flutter-core-second-cycle-ui-theme.md#h-03--domain-layer-hardcodes-flutter-color-values-still-open) |
| SC2-H15 | `AppTheme` rebuilt every `build` | STILL OPEN | [theme](flutter-core-second-cycle-ui-theme.md#h-04--appthemelightdark-rebuilt-on-every-aiclinicappbuild-still-open) |
| SC2-H16 | `ThemeData` under-specified | STILL OPEN | [theme](flutter-core-second-cycle-ui-theme.md#h-05--themedata-under-specified-still-open) |
| SC2-H17 | Typography diverges from spec | STILL OPEN | [theme](flutter-core-second-cycle-ui-theme.md#h-06--typography-diverges-from-02-tokensmd-4-still-open) |
| SC2-H18 | Calendar status mapping contradicts spec domain-status mapping | **NEW** | [theme](flutter-core-second-cycle-ui-theme.md#nh-01--calendar-status-mapping-contradicts-spec-domain-status-mapping-new) |
| SC2-H19 | Calendar unit tests lock hardcoded hex as contract | **NEW** | [theme](flutter-core-second-cycle-ui-theme.md#nh-02--calendar-unit-tests-lock-hardcoded-hex-as-contract-new) |
| SC2-H20 | Design-system contrast showcase validates duplicate constants, not runtime semantics | **NEW** | [theme](flutter-core-second-cycle-ui-theme.md#nh-03--design-system-contrast-showcase-validates-duplicate-constants-not-runtime-semantics-new) |

*Deduplication:* SC2-H14 + SC2-H18 + SC2-H19 form one **calendar color cluster** (wrong mapping, domain leak, tests block migration).

### UI components

| ID | Issue | Status | Area report |
|----|-------|--------|-------------|
| SC2-H21 | `AppBadge` ~5% of D7 spec | STILL OPEN | [components](flutter-core-second-cycle-ui-components.md) |
| SC2-H22 | Notification count reimplements badge inline | STILL OPEN | [components](flutter-core-second-cycle-ui-components.md#h-02--inline-notification-badge-duplicate-styling) |
| SC2-H23 | `AppIconButton` missing variants/states/motion | STILL OPEN | [components](flutter-core-second-cycle-ui-components.md) |
| SC2-H24 | Split tooltip implementations | STILL OPEN | [components](flutter-core-second-cycle-ui-components.md#h-04--split-tooltip-implementations) |
| SC2-H25 | `AppAvatar` incomplete; user menu a11y gap | STILL OPEN | [components](flutter-core-second-cycle-ui-components.md#h-06--user-menu-a11y) |
| SC2-H26 | `AppSignal` not marked decorative | STILL OPEN | [components](flutter-core-second-cycle-ui-components.md) |
| SC2-H27 | `widgets.dart` barrel unused | STILL OPEN | [components](flutter-core-second-cycle-ui-components.md) |
| SC2-H28 | Stale Forui docs / missing wrappers | **PARTIALLY FIXED** | [components](flutter-core-second-cycle-ui-components.md#h-09--forui-docs-vs-reality) |

*Deduplication:* SC2-H21 overlaps **SC2-C03** (badge tone API); SC2-H12 overlaps **SC2-C04** (theme test slice).

### Dead code (High)

| ID | Issue | Status |
|----|-------|--------|
| SC2-H29 | `date_format_utils.dart` unused | STILL OPEN — [RPC](flutter-core-second-cycle-rpc-errors-data.md#mp-06--date_format_utilsdart-unused-features-duplicate-date-formatting) |

---

## Medium Priority Issues (highlights)

Consolidated second-cycle Medium count: **47** (10 auth + 11 RPC + 13 theme + 13 components). Full detail in area reports. Key clusters:

**Auth/config (all STILL OPEN):** `PermissionDeniedException` in wrong file; Flutter Material in core handler; core depends on `app_routes.dart`; `InMemoryGotrueAsyncStorage` static state; web test-runtime stub; `SupabaseBootstrap` single-config assumption; JWT decode undocumented; unused `canAccessAppointmentCancelActions`; `DeploymentProfile` / IO store undertested.

**RPC/data (7 STILL OPEN + 4 NEW):** `RpcFailure` co-located with DTO; parallel failure models; `mapExceptionToFailure` raw strings; `AppLog` RPC redaction untested; `_readSuccess` numeric `1` edge case; `loadMoreError` uses `toString()`. **New:** `AsyncValue.guard` list notifiers surface unmapped errors; `UserErrorMapper` fallback would log raw errors; dev seed notifier prefers server message; `_coerceData` silent JSON failure.

**UI theme (10 STILL OPEN + 3 NEW):** Dead motion re-export; collapse duration off-spec; light-only elevation aliases; extension force-unwraps; `statusDangerFg` token drift; incomplete motion presets; silent spacing/radius fallbacks; incomplete primitive palette; `AppContrast` not enforced; showcase palette duplication. **New:** `widgets.dart` exports primitives; `AppTypography.forToken` silent fallback; no bundled fonts (runtime `google_fonts` only).

**UI components (11 STILL OPEN + 2 NEW):** Tooltip passthrough; `AppSignal` active/thinking semantics; avatar grapheme edge cases; icon size contract undefined; missing status surface tokens; dual motion paths. **New:** `scheduleBadgeTone` untested; orphaned `forui` dependency.

---

## Recommended Priority Order (next sprint)

1. **Security orchestration** — SC2-C01 patient router permissions; SC2-H02 auth loading-state redirect; SC2-H04 route-guard tests for visits/shifts/catalog
2. **RPC error hardening** — SC2-H08 `AppRpcInvoker` catch-all; SC2-H09 PHI-safe logging; SC2-H07 wire existing `*MessageForRpc` mappers
3. **Appointments queue readiness** — SC2-C03 `AppBadge` tone API; SC2-C04 widget test suite; SC2-H18/H19 calendar color cluster (fix mapping + rewrite tests before UI ships)
4. **Architecture debt** — SC2-C02 move `AuthSessionState` to domain; SC2-H01 consolidate redirect orchestration
5. **Design-system CI** — SC2-H12 theme/contrast tests; SC2-H20 drive showcase from live `AppSemanticColors`

---

## Second-Cycle Conclusion

Zero Critical or High findings were fully fixed. The highest-risk regressions are **security inconsistency** (patients vs other features), **error UX fragmentation** (8 unwired mapper families), and **design-system debt accelerating** (domain `AppBadgeTone` ahead of widget layer; tests cementing wrong colors). Address items 1–3 before shipping appointments queue UI or expanding patient/service-catalog screens.
