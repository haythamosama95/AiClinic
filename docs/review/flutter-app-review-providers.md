# App Feature Review — Providers, Session & Services

## Summary

The provider layer is thoughtfully structured: startup → Supabase init → auth listener is mostly ordered, cold-start session clearing is intentional, idle timeout is wired with disposal, and `SessionContextLoader` extraction improves testability. Under skeptical review, the main risks are **branch selection not surviving context reloads**, **auth bootstrap getting permanently stuck on a defensive early-return**, **unserialized concurrent auth handlers**, and **Clean Architecture leaks** (`SessionContextLoader` querying Supabase from the app layer). Connectivity is a one-shot startup snapshot, not live monitoring. Test coverage is strong for idle/reload and health classification, but thin for bootstrap orchestration, branch selection, and race scenarios.

## Files Reviewed

| File | Lines |
|------|-------|
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/providers/auth_session_provider.dart` | 321 |
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/providers/session_context_loader.dart` | 105 |
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/providers/repository_providers.dart` | 8 |
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/providers/startup_session_provider.dart` | 192 |
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/providers/branch_selection_notifier.dart` | 32 |
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/providers/connectivity_provider.dart` | 23 |
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/providers/theme_provider.dart` | 22 |
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/services/startup_health_service.dart` | 176 |
| `/home/haytham/Desktop/AiClinic/frontend/lib/app/session_activity_scope.dart` | 41 |

---

## Findings

### Critical

*(None — no confirmed data-loss or security bypass in this slice alone.)*

---

### High

#### H1 — Active branch selection lost on token refresh and context reload

| | |
|---|---|
| **Severity** | High |
| **Files** | `auth_session_provider.dart`, `session_context_loader.dart`, `app.dart` |
| **Evidence** | `setActiveBranch` only mutates in-memory context (`auth_session_provider.dart:226-231`). `_loadSessionContext` always recomputes `activeBranchId` from DB primary (`session_context_loader.dart:52-64, 83`). `tokenRefreshed`, `refreshSessionContext`, and app-resume `reloadContext` all call `_loadSessionContext` without preserving prior selection (`auth_session_provider.dart:138-142, 282-294`; `app.dart:48-53`). |
| **Why** | User branch choice is session UI state; reload paths treat JWT/DB primary as sole source of truth. |
| **Impact** | Multi-branch staff silently revert to primary branch after JWT refresh (~hourly) or app resume. Patient lists, billing, appointments scoped to wrong branch. Shell picker shows one branch while features may briefly disagree during races. |
| **Solution** | Before replacing context, capture `previousActiveBranchId`; if still in `branchIds`, pass it into loader or merge after load. Apply in `tokenRefreshed`, `refreshSessionContext`, and generic `_handleAuthState` reload paths. Add unit test: select non-primary → `reloadContext()` → branch unchanged. |

#### H2 — Auth bootstrap can permanently stall at `unknown` if Supabase isn’t ready

| | |
|---|---|
| **Severity** | High |
| **Files** | `auth_session_provider.dart` |
| **Evidence** | `_runEnsureSupabaseReady` returns early when `!SupabaseBootstrap.isReady` without updating state or clearing `_ensureSupabaseReadyTask` (`auth_session_provider.dart:96-99, 85-87`). Initial state is `unknown` (`auth_session_provider.dart:23, 82`). `AuthRouteGuard` allows navigation when `unknown` (`auth_route_guard.dart:485-486`). |
| **Why** | Memoized task completes “successfully” on no-op; no retry path unless startup state changes again. |
| **Impact** | Rare timing/test edge case: auth never transitions to `unauthenticated`/`authenticated`; sign-in may throw `StateError` from `ensureReadyForSignIn` while router treats session as indeterminate. |
| **Solution** | On early return: set `unauthenticated` with actionable failure, or set `_ensureSupabaseReadyTask = null` and schedule retry. Log at error level. Add unit test simulating valid startup + `isReady == false`. |

#### H3 — Concurrent `_handleAuthState` calls are unserialized

| | |
|---|---|
| **Severity** | High |
| **Files** | `auth_session_provider.dart` |
| **Evidence** | Stream listener uses `unawaited(_handleAuthState(...))` (`auth_session_provider.dart:127-128`). `syncAfterSignIn` also calls `_handleAuthState` (`auth_session_provider.dart:268-275`). No mutex/sequence token. |
| **Why** | Supabase can emit `signedIn` while `syncAfterSignIn` runs; overlapping async loads have no “latest wins” guard. |
| **Impact** | Stale context can overwrite fresh context (wrong permissions, branch, `setupRequired`). Duplicate DB/RPC work on every sign-in. |
| **Solution** | Serialize with incrementing generation counter or `Lock`/`Completer` chain; discard results when generation mismatches. Test: overlapping `signedIn` + `syncAfterSignIn`. |

---

### Medium

#### M1 — Connectivity is startup-only; no runtime re-check

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `connectivity_provider.dart`, `startup_session_provider.dart`, `startup_health_service.dart` |
| **Evidence** | `connectivityStatusProvider` reads `startupSessionProvider.connectivityStatus` (`connectivity_provider.dart:7-8`). Health probe runs only inside `bootstrap()` (`startup_session_provider.dart:112`). `retryStartup()` re-runs full bootstrap (`startup_session_provider.dart:150`). |
| **Why** | Design treats connectivity as bootstrap gate, not ongoing signal. |
| **Impact** | After startup, network loss is invisible to these providers. Sign-in failures surface only via auth errors; degraded API at startup may be stale for entire session. |
| **Solution** | Document assumption, or add periodic/on-resume health re-probe that updates `connectivityStatus` without full bootstrap reset. |

#### M2 — Raw `error.toString()` exposed in session failure UI

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `auth_session_provider.dart` |
| **Evidence** | Bootstrap catch: `failureMessage: error.toString()` (`auth_session_provider.dart:117`). Context load failure: same (`auth_session_provider.dart:165`). Contrast: token refresh uses `kSessionEndedMessage` (`auth_session_provider.dart:146`). |
| **Why** | Inconsistent error sanitization between paths. |
| **Impact** | Internal exception text (PostgREST, JWT parse details) may appear on login/session banners. |
| **Solution** | Map to user-safe messages; log details via `AppLog` only. |

#### M3 — `clearBranch()` desyncs from auth session (dead code today)

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `branch_selection_notifier.dart`, `authenticated_shell.dart` |
| **Evidence** | `clearBranch` sets local `state = null` only (`branch_selection_notifier.dart:26-28`). `selectBranch` updates auth via `setActiveBranch` (`branch_selection_notifier.dart:23`). Shell masks with `branchSelectionProvider ?? session?.activeBranchId` (`authenticated_shell.dart:70`). `clearBranch` has zero call sites. |
| **Why** | Dual state: notifier state vs `AuthSessionState.context.activeBranchId`. |
| **Impact** | If used later, picker shows fallback branch while notifier reads `null` — confusing, hard-to-debug UI. |
| **Solution** | Remove `clearBranch`, or route through `AuthSessionNotifier` and sign-out. |

#### M4 — `repository_providers.dart` is unused and incomplete

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `repository_providers.dart` |
| **Evidence** | Re-exports only 3 providers; grep shows no imports of `repository_providers` in the codebase. Features import `features/*/data/*_repository.dart` directly. |
| **Why** | Partial DI facade started but not adopted. |
| **Impact** | Documented cross-feature import path is misleading; dependency graph stays scattered. |
| **Solution** | Expand barrel to all shared repos and migrate imports, or delete file and update docs. |

#### M5 — Startup `bootstrap()` reset does not coordinate auth session

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `startup_session_provider.dart`, `auth_session_provider.dart` |
| **Evidence** | `bootstrap()` resets `StartupSessionState` (`startup_session_provider.dart:105-106`). `authSessionProvider` listens for valid config but is not reset on retry (`auth_session_provider.dart:71-75`). |
| **Why** | Independent state machines. |
| **Impact** | `retryStartup()` after profile change (dev) may leave auth listener bound to old Supabase client while startup re-inits. |
| **Solution** | On bootstrap restart, notify auth to re-bind or invalidate `_ensureSupabaseReadyTask` and cancel `_authSubscription`. |

#### M6 — Auth health retry only on HTTP 502

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `startup_health_service.dart` |
| **Evidence** | Retry conditioned on `statusCode == 502` (`startup_health_service.dart:102-109`). Timeouts and connection refused get no retry (`startup_health_service.dart:162-168`). |
| **Why** | Tailored for Supabase CLI cold-start race. |
| **Impact** | Transient auth timeout → `unreachable` → user must manual retry despite comment that auth is “required for sign-in.” |
| **Solution** | Retry on timeout/`ClientException` once, or extend delay-retry beyond 502. |

---

### Low

#### L1 — `BranchSelectionNotifier` largely redundant

| | |
|---|---|
| **Severity** | Low |
| **Files** | `branch_selection_notifier.dart`, feature providers |
| **Evidence** | Notifier mirrors `authSessionProvider.context.activeBranchId` (`branch_selection_notifier.dart:13-14`). Features read `authSessionProvider` directly (`invoice_list_notifier.dart:39`, `patient_list_notifier.dart:40`). |
| **Why** | Thin wrapper added for shell only. |
| **Impact** | Two APIs for same concept; future branch logic may diverge. |
| **Solution** | Consolidate on `authSessionProvider.select((s) => s.context?.activeBranchId)` or make branch notifier the single write path. |

#### L2 — `SessionContextLoader` instantiated per load

| | |
|---|---|
| **Severity** | Low |
| **Files** | `auth_session_provider.dart` |
| **Evidence** | Getter creates new instance each call (`auth_session_provider.dart:221-222`). |
| **Why** | Stateless const class — harmless but noisy. |
| **Impact** | Negligible allocation; minor readability cost. |
| **Solution** | Cache as `late final` in notifier `build()`, or inject via provider. |

#### L3 — `probeEndpointForTest` may leak `http.Client`

| | |
|---|---|
| **Severity** | Low |
| **Files** | `startup_health_service.dart` |
| **Evidence** | `probeEndpointForTest` creates client when `client == null` but never closes (`startup_health_service.dart:134-140`). `check()` closes in `finally` (`startup_health_service.dart:125-128`). |
| **Why** | Test helper asymmetry. |
| **Impact** | Test-only socket leak if used without injected client. |
| **Solution** | Document inject client in tests, or close in test helper. |

#### L4 — Theme coupled to startup session state

| | |
|---|---|
| **Severity** | Low |
| **Files** | `theme_provider.dart`, `startup_session_provider.dart` |
| **Evidence** | `themeMode` lives on `StartupSessionState` (`startup_session_provider.dart:49`). `themeModeProvider` watches startup (`theme_provider.dart:7-8`). |
| **Why** | Pre-auth screens need theme before auth exists. |
| **Impact** | Theming conceptually mixed with bootstrap; persists across bootstrap reset via `preservedThemeMode` (`startup_session_provider.dart:105`). |
| **Solution** | Acceptable for V1; optional split `themePreferencesProvider` later. |

---

### Clean Architecture Violations

#### CA1 — App layer performs data access in `SessionContextLoader`

| | |
|---|---|
| **Severity** | Clean Architecture Violation |
| **Files** | `session_context_loader.dart`, `auth_session_provider.dart` |
| **Evidence** | Direct queries: `staff_members`, `staff_branch_assignments`, `organizations` (`session_context_loader.dart:26-70`). Wired with `SupabaseClient` from `supabaseClientProvider` (`auth_session_provider.dart:221-222`). |
| **Why** | Session assembly is infrastructure concern, not app orchestration. |
| **Impact** | App layer depends on PostgREST schema; harder to swap data sources; duplicates staff/branch knowledge also in `staff_admin_repository.dart`. |
| **Solution** | Move to `features/auth/data/session_context_repository.dart` implementing domain port; app notifier calls use case. |

#### CA2 — App providers import feature data implementations

| | |
|---|---|
| **Severity** | Clean Architecture Violation |
| **Files** | `auth_session_provider.dart` |
| **Evidence** | Imports `auth_repository.dart`, `permission_repository.dart` from `features/auth/data/` (`auth_session_provider.dart:10-11`). |
| **Why** | Composition root typically wires interfaces; features own implementations. |
| **Impact** | App module transitively coupled to Supabase data layer. |
| **Solution** | Define providers in `features/auth/di/` or core DI module; app imports only domain abstractions. |

---

### SOLID Violations

#### S1 — `AuthSessionNotifier` has multiple responsibilities

| | |
|---|---|
| **Severity** | SOLID Violation (SRP) |
| **Files** | `auth_session_provider.dart` |
| **Evidence** | Single class: Supabase bootstrap gate, auth stream, context load, idle monitoring, branch mutation, sign-out semantics (`auth_session_provider.dart:59-315`). |
| **Why** | Historical growth; partial extract to `SessionContextLoader`. |
| **Impact** | Hard to test orchestration in isolation; changes to idle logic risk auth regressions. |
| **Solution** | Extract `AuthSessionCoordinator` + `IdleSessionLifecycle` services. |

#### S2 — `permissionServiceProvider` rebuilds on any auth field change

| | |
|---|---|
| **Severity** | SOLID Violation (minor ISP/DIP) |
| **Files** | `auth_session_provider.dart` |
| **Evidence** | `ref.watch(authSessionProvider).context` (`auth_session_provider.dart:318-320`) — full auth state watch. |
| **Why** | Simplicity. |
| **Impact** | Extra rebuilds when only `failureMessage` changes; low cost for `PermissionService`. |
| **Solution** | `ref.watch(authSessionProvider.select((s) => s.context))`. |

---

### Duplication

#### D1 — Branch selection API duplicated

| | |
|---|---|
| **Severity** | Duplication |
| **Files** | `auth_session_provider.dart`, `branch_selection_notifier.dart`, feature notifiers |
| **Evidence** | `setActiveBranch` on auth notifier (`auth_session_provider.dart:226-231`); `selectBranch` on branch notifier (`branch_selection_notifier.dart:18-24`); features bypass branch notifier. |
| **Solution** | Single write API; document canonical read path. |

#### D2 — Session context failure classification duplicates string matching

| | |
|---|---|
| **Severity** | Duplication |
| **Files** | `session_context_loader.dart`, `auth_notifier.dart` |
| **Evidence** | `contextFailureReason` matches substrings (`session_context_loader.dart:91-102`). `AuthNotifier._unexpectedErrorCategory` matches similar strings (`auth_notifier.dart:85-93`). |
| **Solution** | Shared `SessionContextFailure` typed exceptions. |

---

### Performance

#### P1 — Redundant session context loads on sign-in

| | |
|---|---|
| **Severity** | Performance |
| **Files** | `auth_session_provider.dart`, `auth_notifier.dart` |
| **Evidence** | `syncAfterSignIn` + stream `signedIn` both trigger `_handleAuthState` (`auth_session_provider.dart:268-275, 127-128`). `AuthNotifier` polls up to 150×20ms waiting for resolution (`auth_notifier.dart:118-133`). |
| **Impact** | 3–6 DB round-trips per sign-in; up to 3s poll timeout path. |
| **Solution** | Serialize handlers (H3); have `syncAfterSignIn` return `AuthSessionContext` so UI need not poll. |

#### P2 — `SessionContextLoader.load` is sequential (4+ network calls)

| | |
|---|---|
| **Severity** | Performance |
| **Files** | `session_context_loader.dart` |
| **Evidence** | Sequential: staff row → permissions → primary branch → org timezone (`session_context_loader.dart:26-71`). |
| **Impact** | Every auth event adds latency to `loading` state. |
| **Solution** | `Future.wait` for independent queries (permissions + staff + org). |

---

### Test Gaps

| Gap | Risk |
|-----|------|
| No unit tests for `StartupSessionNotifier.bootstrap()` orchestration | Bootstrap failure/regression undetected |
| No tests for `BranchSelectionNotifier` / `setActiveBranch` | Branch bugs ship silently |
| No test that branch survives `reloadContext` / `tokenRefreshed` | H1 would be caught |
| No test for concurrent auth events (H3) | Race regressions |
| `auth_session_provider` bootstrap path largely untested (only `ensureReadyForSignIn` invalid startup) | H2 undetected |
| `connectivity_provider` / `theme_provider` untested | Low risk (pure delegates) |

**Existing coverage (positive):** idle sign-out, reload context permissions, health classification, `SessionContextLoader` boundary suite, `clearPersistedSessionOnColdStart`.

---

### Refactoring

| Priority | Refactor |
|----------|----------|
| 1 | Preserve `activeBranchId` across context reloads (H1) |
| 2 | Serialize `_handleAuthState` (H3) |
| 3 | Move `SessionContextLoader` to auth data layer behind repository port (CA1) |
| 4 | Fix or remove `_ensureSupabaseReady` early-return stuck state (H2) |
| 5 | Adopt or delete `repository_providers.dart` (M4) |
| 6 | Split theme from startup state when pre-auth shell stabilizes (L4) |

---

## Brief Summary — Critical / High

| ID | Finding |
|----|---------|
| **H1** | User-selected branch resets to JWT/DB primary on token refresh and `reloadContext()` (app resume) — multi-branch workflows hit wrong data. |
| **H2** | If `SupabaseBootstrap.isReady` is false when `_ensureSupabaseReady` runs, auth stays `unknown` forever with no retry. |
| **H3** | Overlapping `_handleAuthState` invocations (stream + `syncAfterSignIn`) are unserialized — stale session context can win. |

No **Critical** severity issues were identified in this slice; the three **High** items above are the priority fixes.

[REDACTED]
