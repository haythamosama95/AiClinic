# Flutter App Second-Cycle Review — Providers & Session

**Review date:** 2026-07-05  
**Scope:** `frontend/lib/app/providers/`, `startup_health_service.dart`, `session_activity_scope.dart`, core auth integration, `frontend/test/` (provider-related)  
**Methodology:** `/home/haytham/Desktop/AiClinic/docs/review/prompt.md`  
**First-cycle sources:** `flutter-app-feature-review.md` (H4, H10, H11, M19–M22, CA1–CA2, S2, S6, D2, D9, P1–P2, T2–T3, T7–T8), `flutter-app-review-providers.md`

---

## Executive Summary

Direct re-verification of all seven provider files, `startup_health_service.dart`, `session_activity_scope.dart`, `app.dart` resume hook, and `auth_notifier.dart` integration shows **no material fixes** since the first cycle for the three High-priority provider/session defects: branch selection still resets on every context reload, auth bootstrap can remain stuck at `unknown`, and `_handleAuthState` is still unserialized.

The only observable change in the stuck-bootstrap path is a warning log (`auth.session.supabase_not_ready_after_startup`); behavior is unchanged.

Three **new High** findings sharpen the bootstrap-retry story: the memoized `_ensureSupabaseReadyTask` prevents recovery after a no-op early return or `retryStartup()`, `refreshSessionContext()` can race with the `tokenRefreshed` stream handler, and the auth stream subscription is bound once and never rebound.

Clean Architecture violations (CA1, CA2), duplication (D2, D9), performance issues (P1, P2), and listed test gaps (T2, T3, T7, T8) all remain open. Idle-timeout integration (`SessionActivityScope` + `IdleTimeoutService`) is correctly wired. Connectivity and theme providers remain thin delegates over startup state with no runtime connectivity monitoring.

**Verdict:** Provider/session layer is still **not production-ready for multi-branch clinical workflows** until H4 and H11 are fixed and bootstrap retry coordination (H10 + M20 + new H2-P-01/03) is addressed.

---

## First-Cycle Triage

| ID | First-cycle finding | Status | Evidence |
|----|---------------------|--------|----------|
| **H4** | Active branch lost on token refresh / `reloadContext` | **STILL OPEN** | `SessionContextLoader.load` always sets `activeBranchId: primaryBranchId` from DB (`session_context_loader.dart:52-64, 83`). `tokenRefreshed` (`auth_session_provider.dart:138-142`), `refreshSessionContext` (`282-294`), and app-resume `reloadContext` (`app.dart:53`) all call `_loadSessionContext` with no prior-selection merge. `setActiveBranch` only mutates in-memory context (`226-231`). |
| **H10** | Auth bootstrap stuck at `unknown` when Supabase not ready | **STILL OPEN** | `_runEnsureSupabaseReady` still returns early when `!SupabaseBootstrap.isReady` without updating state or clearing task (`96-99`). Initial state remains `unknown` (`82`). Warning log added at line 97; no retry or state transition. |
| **H11** | Concurrent `_handleAuthState` unserialized | **STILL OPEN** | Stream listener still uses `unawaited(_handleAuthState(...))` (`127-128`). `syncAfterSignIn` also awaits `_handleAuthState` (`268-275`). No generation token, lock, or discard logic. |
| **M19** | `repository_providers.dart` unused/incomplete | **STILL OPEN** | File exports 3 providers (`repository_providers.dart:5-7`). Zero imports of `repository_providers` anywhere in `frontend/`. |
| **M20** | Startup `bootstrap()` / `retryStartup()` does not coordinate auth | **STILL OPEN** | `bootstrap()` resets only `StartupSessionState` (`startup_session_provider.dart:104-106`). `AuthSessionNotifier` has no listener for retry; `_authSubscription` bound once (`121-124`); `_ensureSupabaseReadyTask` not invalidated on retry (only on catch at `115`). |
| **M21** | Auth health retry only on HTTP 502 | **STILL OPEN** | Retry gated on `statusCode == 502` (`startup_health_service.dart:102-109`). `TimeoutException` and `ClientException` return unreachable with no retry (`162-170`). |
| **M22** | Dev seed 8-feature coupling | **OUT OF SCOPE** | `dev_clinic_seed_notifier.dart` — not in providers/session scope. Status unchanged if tracked elsewhere. |
| **CA1** | `auth_route_guard.dart` imports app-layer `auth_session_provider` | **STILL OPEN** | `auth_route_guard.dart:6` imports `auth_session_provider.dart`; guard methods take `AuthSessionState` throughout. |
| **CA2** | App layer data access in `SessionContextLoader` | **STILL OPEN** | Direct PostgREST queries to `staff_members`, `staff_branch_assignments`, `organizations` (`session_context_loader.dart:26-70`). Still instantiated from app notifier (`auth_session_provider.dart:221-222`). |
| **S2** | `AuthSessionNotifier` multiple responsibilities | **STILL OPEN** | Single class: bootstrap gate, auth stream, context load, idle monitoring, branch mutation, sign-out (`59-315`). |
| **S6** | `permissionServiceProvider` broad watch | **DOWNGRADED → Low** | Still `ref.watch(authSessionProvider).context` (`318-320`). `PermissionService` is a lightweight value object; extra rebuilds are cosmetic, not a correctness risk. |
| **D2** | Branch selection API duplicated | **STILL OPEN** | `setActiveBranch` on auth (`226-231`), `selectBranch` on branch notifier (`branch_selection_notifier.dart:18-23`), shell reads `branchSelectionProvider ?? session?.activeBranchId` (`authenticated_shell.dart:70`). |
| **D9** | Session failure string matching duplicated | **STILL OPEN** | `SessionContextLoader.contextFailureReason` (`session_context_loader.dart:91-102`) vs `AuthNotifier._unexpectedErrorCategory` (`auth_notifier.dart:85-93`) — same substring approach, no shared typed failure. |
| **P1** | Redundant context loads on sign-in | **STILL OPEN** | `syncAfterSignIn` + stream `signedIn` both invoke `_handleAuthState`. `AuthNotifier._waitForPostLoginResolution` still polls 150×20ms (`118-133`). |
| **P2** | `SessionContextLoader.load` sequential | **STILL OPEN** | staff → permissions → primary branch → org timezone run sequentially (`session_context_loader.dart:26-71`). |
| **T2** | No branch-survives-reload test | **STILL OPEN** | `auth_session_reload_context_test.dart` tests permissions reload, not branch preservation. |
| **T3** | No concurrent auth event test | **STILL OPEN** | No test file covers overlapping `signedIn` + `syncAfterSignIn`. |
| **T7** | No `StartupSessionNotifier.bootstrap()` unit test | **STILL OPEN** | Only `_InvalidStartupNotifier` used for `ensureReadyForSignIn` in `auth_repository_test.dart:65-74`; no bootstrap orchestration test. |
| **T8** | Bootstrap stuck path untested | **STILL OPEN** | No test simulating valid startup + `isReady == false` after `_runEnsureSupabaseReady`. |

---

## High Priority Issues

### H2-P-01 — Memoized `_ensureSupabaseReadyTask` prevents recovery after failed bootstrap or `retryStartup()`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `auth_session_provider.dart`, `startup_session_provider.dart` |
| **Evidence** | Task memoized: `_ensureSupabaseReadyTask ??= _runEnsureSupabaseReady(startup)` (`85-87`). Early return on `!isReady` completes the future without clearing the task (`96-99`). Task only nulled in `catch` (`115`). `retryStartup()` → `bootstrap()` re-inits Supabase (`startup_session_provider.dart:111`) but auth's `_ensureSupabaseReady` returns the cached completed future. |
| **Why** | First-cycle H10 identified the early return; this finding shows the memoization makes it **permanent** even after a successful retry. |
| **Impact** | User taps "Refresh startup checks" after Supabase comes up — auth may remain `unknown` forever; sign-in throws `StateError` from `ensureReadyForSignIn` (`312-314`) while router allows `unknown` navigation (`auth_route_guard.dart:485-486`). |
| **Solution** | Null `_ensureSupabaseReadyTask` on early return; re-run on each valid startup transition; or key task to `deploymentProfile` hash / bootstrap generation. |

### H2-P-02 — `refreshSessionContext()` races with `tokenRefreshed` stream handler

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `auth_session_provider.dart`, `app.dart` |
| **Evidence** | `refreshSessionContext` calls `refreshSession()` (`283`) which triggers Supabase `onAuthStateChange` with `tokenRefreshed`. Stream handler also loads context when `state.isAuthenticated` (`138-142`). Caller then independently awaits `_loadSessionContext` (`293`). Both paths lack serialization (H11). App resume fires `reloadContext()` unawaited (`app.dart:53`). |
| **Why** | Two independent loaders for the same refresh event. |
| **Impact** | Duplicate DB/RPC work; stale context from slower path can overwrite fresher context (permissions, `setupRequired`, branch). Amplifies H4 and H11 on every app resume and permission-matrix save. |
| **Solution** | Serialize via generation token; or skip manual load in `refreshSessionContext` and await stream handler completion; or ignore `tokenRefreshed` when refresh was initiated internally. |

### H2-P-03 — Auth stream subscription never rebound after startup retry

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `auth_session_provider.dart`, `startup_session_provider.dart` |
| **Evidence** | `_bindAuthListener` returns immediately if `_authSubscription != null` (`122-124`). `retryStartup()` re-initializes Supabase (`startup_session_provider.dart:111`) but auth notifier is not reset. `_authSubscription` only cancelled on provider dispose (`67-68`). |
| **Why** | M20 identified missing coordination; this is the concrete subscription leak/rebind gap. |
| **Impact** | After dev profile switch or startup retry, auth events may not reach the notifier; session state diverges from Supabase client state. |
| **Solution** | On bootstrap restart: cancel `_authSubscription`, null it, null `_ensureSupabaseReadyTask`, reset auth to `unknown`, re-bind listener. |

*First-cycle H4, H10, H11 remain **STILL OPEN** — see triage table.*

---

## Medium Priority Issues

### M2-P-01 — App-resume `reloadContext()` has no in-flight guard

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app.dart`, `auth_session_provider.dart` |
| **Evidence** | `didChangeAppLifecycleState` fires `unawaited(reloadContext())` on every resume (`app.dart:48-53`). No mutex, debounce, or "already refreshing" flag in `refreshSessionContext` (`282-302`). |
| **Impact** | Overlapping refresh + context loads; wasted network; race window widened. |
| **Solution** | Coalesce with `Future` chain or ignore if refresh in progress. |

### M2-P-02 — `connectivityStatusProvider` name implies live status; value is bootstrap snapshot

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `connectivity_provider.dart`, `startup_session_provider.dart` |
| **Evidence** | Comment says "latest startup probe" (`connectivity_provider.dart:6`). Value set once in `bootstrap()` (`startup_session_provider.dart:117`) and never updated until full `retryStartup()`. |
| **Impact** | Feature code watching `connectivityStatusProvider` after startup will show stale "Healthy" after network loss. |
| **Solution** | Rename to `startupConnectivityStatusProvider`; document snapshot semantics; or add on-resume re-probe. |

### M2-P-03 — `permissionServiceProvider` rebuilds on any `AuthSessionState` field change

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `auth_session_provider.dart` |
| **Evidence** | `ref.watch(authSessionProvider).context` (`318-320`) — watches entire auth state, not `select((s) => s.context)`. |
| **Impact** | New `PermissionService` instance when only `failureMessage` changes; downstream `ref.watch(permissionServiceProvider)` rebuilds unnecessarily. |
| **Solution** | Use `.select((s) => s.context)`. |

---

## Test Gaps

| ID | Gap | Status | Risk |
|----|-----|--------|------|
| **T2** | Branch survives `reloadContext` / `tokenRefreshed` | **STILL OPEN** | H4 undetected |
| **T3** | Concurrent `signedIn` + `syncAfterSignIn` | **STILL OPEN** | H11/H2-P-02 regressions |
| **T7** | `StartupSessionNotifier.bootstrap()` orchestration | **STILL OPEN** | Bootstrap state machine regressions |
| **T8** | Bootstrap stuck at `unknown` when `!isReady` | **STILL OPEN** | H10/H2-P-01 undetected |
| **T2-P-01** | `_ensureSupabaseReadyTask` not re-run after `retryStartup()` | **NEW** | H2-P-01 undetected |
| **T2-P-02** | `refreshSessionContext` + stream `tokenRefreshed` interaction | **NEW** | H2-P-02 undetected |
| **T2-P-03** | `BranchSelectionNotifier` / `setActiveBranch` integration | **NEW** | Branch write path untested |
| **T2-P-04** | `StartupSessionNotifier` + `AuthSessionNotifier` retry coordination | **NEW** | H2-P-03/M20 undetected |

---

## Recommended Fix Order

1. **H4** — Preserve `previousActiveBranchId` across `_loadSessionContext`.
2. **H11 + P1** — Serialize `_handleAuthState` with generation token.
3. **H2-P-02** — Deduplicate `refreshSessionContext` vs stream `tokenRefreshed` path.
4. **H10 + H2-P-01** — On `!isReady` early return: null task, set `unauthenticated` or schedule retry.
5. **M20 + H2-P-03** — On `retryStartup()`: cancel auth subscription, null ready-task, reset auth listener.
6. **T2, T3, T2-P-02, T8, T2-P-01, T2-P-04** — Regression tests.

---

## Finding Count Summary

| Category | First-cycle open | New (C/H/M) | Total open |
|----------|------------------|-------------|------------|
| Critical | 0 | 0 | 0 |
| High | 3 | 3 | 6 |
| Medium | 8+ | 3 | 11+ |

*Second-cycle providers review — 2026-07-05.*
