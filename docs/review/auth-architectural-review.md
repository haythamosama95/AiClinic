# Auth Feature Architectural Review

> Scope: `frontend/lib/features/auth/**` and all adjacent auth-related infrastructure in `app/**` and `core/auth/**`.
> Date: 2026-07-11
> Reviewer: opencode (automated architectural review)

---

## 1. Architectural Overview

The auth feature follows a layered Clean Architecture scheme:

```
presentation/   → AuthNotifier (Riverpod Notifier), LoginPage, dialogs, dev widgets
domain/         → AuthSessionContext, StaffProfile, StaffRole, PermissionKeys,
                   use cases (SignIn, SignOut, RefreshSession, ...), repository contracts
data/           → AuthRepositoryImpl (Supabase), PermissionRepositoryImpl (PostgREST)
```

Cross-cutting auth state lives outside the feature in:

| Concern                         | Owner file                                                                  |
| ------------------------------- | --------------------------------------------------------------------------- |
| Session lifecycle / state machine | `app/providers/auth_session_provider.dart` (`AuthSessionNotifier`)         |
| Route guards / RBAC redirects   | `core/auth/auth_route_guard.dart` (`AuthRouteGuard`)                        |
| Permission checks (UX layer)    | `core/auth/permission_service.dart` (`PermissionService`)                   |
| Idle timeout                    | `core/auth/idle_timeout_service.dart` (`IdleTimeoutService`)                |
| Session context decoding        | `app/providers/session_context_loader.dart` (`SessionContextLoader`)        |
| Router redirect logic           | `app/router.dart` (`appRouterProvider`)                                     |
| Startup bootstrap               | `app/providers/startup_session_provider.dart` (`StartupSessionNotifier`)   |
| Activity tracking               | `app/session_activity_scope.dart` (`SessionActivityScope`)                  |

The design choice to split the *core session state* out of the feature folder and into `app/providers/` is defensible (the session state machine is consumed by routing, shell, and other features), but it does create the situation that a thorough review of "auth" requires reading many files outside `features/auth/`.

---

## 2. Critical Findings — Unauthorized Access Risk

### 2.1 `AuthRouteGuard` dereferences `auth.context!` without an `isAuthenticated` guard in several methods

Many `canAccess*` helpers in `core/auth/auth_route_guard.dart` begin with:

```dart
if (!auth.isAuthenticated || needsClinicSetup(auth.context!)) {
  return false;
}
```

The `auth.context!` dereference is technically defended by the `||` short-circuit, **but** `needsClinicSetup` is defined as:

```dart
static bool needsClinicSetup(AuthSessionContext context) => context.needsClinicSetup;
```

This method takes a **non-nullable** `AuthSessionContext`. Every call site that uses `needsClinicSetup(auth.context!)` is relying on the left-hand-side of `||` to prevent the right-hand-side from evaluating. This is *currently* safe, but it is brittle:

- The `||` short-circuit is the *only* thing preventing a null-dereference.
- The `*RouteRedirect` methods (e.g. `visitRouteRedirect`, `billingRouteRedirect`, `shiftRouteRedirect`, `appointmentRouteRedirect`) repeat the pattern:
  ```dart
  if (!auth.isAuthenticated) return AppRoutes.login;
  if (needsClinicSetup(auth.context!)) return clinicSetupRoute;
  ```
  These *do* check `isAuthenticated` first, so they are safe by ordering — but the ordering is mandatory and any future refactor that reorders these checks will introduce a crash / vulnerability.

> **Recommendation:** Make `needsClinicSetup` accept a nullable `AuthSessionContext?` and return `true` when `context == null`. This eliminates the entire class of `!` dereference risk with no behavior change.

### 2.2 Router redirect allows unauthenticated preview in debug mode

`app/router.dart:181`:

```dart
if (!auth.isAuthenticated && ShellDevNav.isEnabled && ShellNavConfig.allowsUnauthenticatedPreview(location)) {
  return null;
}
```

`ShellDevNav.isEnabled` is keyed off `kDebugMode` (or a compile-time flag). This permits the authenticated `ShellRoute` subtree (sidebar, top bar, page builders) to render **without** an authenticated session during development. While acceptable for a dev scaffold preview, **any `ShellRoute` child page that reads `authSessionProvider.context!` will crash in this mode**, and any page that performs an RPC will execute unauthenticated. This is a latent crash/security smell rather than a production loophole, but it should be gated so dev previews render a static placeholder and never reach feature pages that assume a session.

### 2.3 `ShellDevNav.allowsOpenAccess` bypass *before* auth redirect

`app/router.dart:177`:

```dart
if (ShellDevNav.allowsOpenAccess(location)) {
  return null;
}
```

This open-access bypass runs **before** any auth or protected-route check. If a route is ever registered in the open-access set by mistake, it will render fully bypassed. The dev nav set should be audited to ensure no production route paths can be added to it accidentally (e.g. by string-equality drift). The risk is low because it's debug-guarded, but the bypass is unconditional (no `auth.isAuthenticated` check), so it overrides even login-required routes.

### 2.4 `LoginPage` renders an `AuthenticatedShell` subtree in the background

`features/auth/presentation/pages/login_page.dart:190-194`:

```dart
const IgnorePointer(
  child: AuthenticatedShell(
    child: PlaceholderPage(...),
  ),
),
```

This renders the full authenticated shell (sidebar, top bar, command bar) **underneath** the login modal as a backdrop, wrapped in `IgnorePointer`. While `IgnorePointer` blocks input, this widget tree still:

- Calls `ref.watch(permissionServiceProvider)` and `ref.watch(appointmentQueueShellWarmProvider)` inside `AuthenticatedShell.build()`.
- Invokes `GoRouterState.of(context)` which may reference protected route state.
- Builds `ClinicSetupWelcomeScope` as part of the shell's `child`, which reads `authSessionProvider`.

When no session is signed in, `permissionServiceProvider` is constructed with a `null` context (it is `PermissionService(auth.context)`), so permission checks return `false` — which is the safe default. However, this is a **presentation layer that builds authenticated UI while the user is on the login screen**. If any shell component ever introduces an `assert(context != null)` or platform-channel call (e.g. warm an appointment queue) that runs in the background build, it will fire on the login screen.

> **Recommendation:** Replace the live `AuthenticatedShell` backdrop with a static screenshot/placeholder asset. Authenticated UI should never be constructed in the login tree.

---

## 3. State-Machine / State-Consistency Issues

### 3.1 `_waitForPostLoginResolution` polls with 20 ms sleeps for up to 3 seconds

`AuthNotifier._waitForPostLoginResolution` (`auth_notifier.dart:123-146`) loops up to 150 iterations with `await Future.delayed(20ms)` polling `authSessionProvider` for a status change. This is a busy-wait poller that:

- Hardcodes a 3-second timeout (150 × 20 ms).
- Couples presentation-layer state (`AuthUiState`) to the async resolution of the downstream `AuthSessionNotifier`.
- On timeout it sets a *generic* error message ("Sign-in is taking longer than expected...") but **does not sign the user out** — the Supabase session may actually be authenticated, and the session notifier may *later* resolve to `authenticated`, at which point the router redirects to `/home` while the login form still shows an error banner.

This is a real loophole: **the app can transition to the authenticated shell while `AuthNotifier` still holds a stale "timeout" error message.** The user lands on `/home` with no visible error, but if they navigate back to the login form the stale error persists (until `resetSignInForm` fires on dispose).

> **Recommendation:** Replace the poller with a `ref.listen` on `authSessionProvider` that fires exactly once after sign-in, or have `syncAfterSignIn()` return the resolved `AuthSessionState`. Remove presentation-layer timeouts that don't also roll back the auth state.

### 3.2 `AuthSessionNotifier.signIn` flow can set `authenticated` while `AuthNotifier` still shows `isSubmitting: true`

Flow in `AuthNotifier.signIn`:

1. `state = AuthUiState(isSubmitting: true)`
2. `await ensureReadyForSignIn()` 
3. `await signInUseCase(...)`  ← Supabase emits `signedIn` event
4. `await syncAfterSignIn()`   ← synchronously changes `authSessionProvider` to `authenticated`
5. `await _waitForPostLoginResolution()` ← waits for step 4 effect

Between step 3 and 4, the Supabase `onAuthStateChange` stream may also fire `_handleAuthState(signedIn)`. So there are **two concurrent paths** racing to process the `signedIn` event:

- `_handleAuthState` (via the stream subscription bound in `_bindAuthListener`)
- `syncAfterSignIn` which calls `_handleAuthState(signedIn, session)` directly

Both call `_loadSessionContext` and `_applyAuthenticatedContext`. The second call is idempotent (it just re-sets the same context), but it does **two redundant DB round-trips** (staff profile + permissions + branch + org). In the token-refresh path there's protection (`if (state.isAuthenticated)` early return), but in the initial `signedIn` path there is **no guard against the duplicate `signedIn` event** from the stream arriving while `syncAfterSignIn` is in flight.

> **Recommendation:** Add an in-flight guard (`Future<AuthSessionContext>? _pendingContextLoad`) in `AuthSessionNotifier` keyed by session access token, and join the pending future when a duplicate event arrives.

### 3.3 `_hadProperClinicSetup` side-effect: `signOut()` can be called from inside `_applyAuthenticatedContext`

`auth_session_provider.dart:300-309`:

```dart
Future<void> _applyAuthenticatedContext(AuthSessionContext context) async {
  final hadSetup = _hadProperClinicSetup;
  final hasSetup = context.hasProperClinicSetup;
  _hadProperClinicSetup = hasSetup;

  if (hadSetup == true && !hasSetup) {
    AppLog.info('auth.session.clinic_setup_lost');
    await signOut();
    return;
  }
  ...
}
```

This is correct intent (if a previously set-up clinic is reverted to setup-required, sign out), but `_hadProperClinicSetup` is a mutable instance field on the notifier that is only reset in `signOut()` and `signOutDueToInactivity()`. If the notifier is disposed and rebuilt (Riverpod auto-dispose), `_hadProperClinicSetup` resets to `null`, so a re-login after a clinic teardown would *not* trigger the "setup lost" sign-out — it would instead land the user on the setup wizard, which may be correct, but the state machine is implicit.

Also: `_applyAuthenticatedContext` is `async` and can interleave with `_handleAuthState` events. If a `tokenRefreshed` and an `initialSession` arrive near-simultaneously, the `await signOut()` mid-flight can race with a subsequent `_handleAuthState` that re-authenticates.

### 3.4 `clinic_setup_welcome_scope.dart` uses a **global mutable** for shown-state

`features/auth/presentation/widgets/clinic_setup_welcome_scope.dart:12`:

```dart
bool _clinicSetupWelcomeShown = false;
```

This is a *library-level* (global) mutable. It persists across `ClinicSetupWelcomeScope` instances, across hot reloads, and is shared by both the login backdrop (`LoginPage` constructs `AuthenticatedShell` which contains `ClinicSetupWelcomeScope`) and the routed authenticated shell. Consequences:

- After hot-reload during development, the dialog may never show again until a sign-out/sign-in cycle resets it.
- If the clinic setup welcome scope is built twice in the same frame (login backdrop + routed shell), the first one wins and the second silently no-ops.
- There is no tie to the actual authenticated user identity — switching users without a full sign-out (e.g. re-login flow) would not reset the flag.

> **Recommendation:** Move the "shown" state into a Riverpod provider keyed by `staffMemberId`, or store it as a field on a single responsible widget (the routed `AuthenticatedShell`), not the login backdrop.

---

## 4. Redundant / Over-Complex Implementations

### 4.1 Use-case classes are trivial pass-throughs with no orchestration logic

All five use-case classes (`SignIn`, `SignOut`, `RefreshSession`, `ClearPersistedSession`, `LoadGrantedPermissions`) are thin one-liner forwards to their repository:

```dart
class SignIn {
  const SignIn(this._repository);
  final AuthRepository _repository;
  Future<void> call({required ...}) => _repository.signIn(...);
}
```

None of them perform validation, multi-step orchestration, or caching. They exist purely to satisfy the Clean Architecture "use case layer" convention, but they add:

- 5 extra files + 1 provider wiring file (`auth_use_case_providers.dart`).
- One extra indirection on every call (provider → use case → repository).
- No testability benefit (the repository is already mockable; the use cases have no logic to test).

In contrast, the *real* sign-in orchestration lives in `AuthNotifier.signIn` (presentation layer) and `AuthSessionNotifier.syncAfterSignIn` (app/provider layer) — which bypass the use cases entirely for context loading.

> **Recommendation:** Either (a) move the multi-step sign-in / post-login resolution logic *into* `SignIn` so it earns its existence as an orchestrator, or (b) delete the use-case layer and have `AuthNotifier` call the repository providers directly. The current shape is the worst of both worlds: ceremony without responsibility.

### 4.2 `RolePermissionSeed` is duplicated spec data

`domain/permission_keys.dart:33-94` hardcodes the expected V1-1 permission grants per role. This duplicates the backend `roles_permissions` seed data and is kept in sync only by convention ("for tests and RBAC demo verification"). It is not used by any runtime permission check (those read from `AuthSessionContext.permissions` loaded from the DB). If the seed changes on the backend, this client-side copy silently drifts. 

> **Recommendation:** Scope this to test-only (`test/` or a `dev/` target). If runtime reference is needed for a permission-matrix editor, fetch it from the same source the runtime uses.

### 4.3 `AuthUiState.copyWith` `clearError` sentinel fights with the `errorMessage ??` pattern

```dart
AuthUiState copyWith({..., bool clearError = false}) {
  return AuthUiState(
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    ...
  );
}
```

The `errorMessage ?? this.errorMessage` means that passing `errorMessage: null` does **not** clear the error — you must pass `clearError: true`. This is a non-obvious API: a caller writing `state.copyWith(errorMessage: null)` would expect the error to clear, but it won't. The same issue affects `isInfoMessage`. Combined with the fact that some call sites pass both `clearError: true` *and* a new `errorMessage` (e.g. `showForgotPasswordMessage`), the precedence is easy to get wrong.

> **Recommendation:** Use the `copyWithSentinel` pattern already used in `AuthSessionContext` for nullable fields, so `copyWith(errorMessage: null)` clears the message unambiguously.

### 4.4 Two parallel notions of "success reset" in `AuthNotifier`

- On success: `state = const AuthUiState()` (line 128)
- On dispose: `Future(() => authNotifier.resetSignInForm())` which sets `state = const AuthUiState()`
- On leaving form (also dispose-driven)

The dispose path schedules `resetSignInForm` in a `Future`, which runs **after** the widget is disposed. The notifier is global (`NotifierProvider`), so it is *not* disposed with the widget — the `Future` will still fire. But since the notifier is alive across the app's lifetime, scheduling the reset on a post-dispose `Future` is unnecessary indirection; the notifier survives long enough that calling `resetSignInForm()` synchronously in `dispose` would also be safe. The `Future` wrapping may have been added to avoid "setState after dispose" — but the notifier doesn't own a widget, so that concern doesn't apply.

### 4.5 `_LoginBackdrop` blur is computed but `LoginPage` already wraps with `Scaffold(backgroundColor: transparent)` over an `AuthenticatedShell` backdrop

The login page stacks: `AuthenticatedShell` (live authenticated UI) → `_LoginBackdrop` (blur+color) → login panel. The blur is meant to obscure the backdrop. But since the backdrop is an *authenticated shell* rendering protected pages, the blur is doing security theater: the authenticated widget tree is fully built and its data (org name, branch list, user name) is in memory. The blur only visually hides it. This is a redundancy: the backdrop shouldn't exist at all (see 2.4).

---

## 5. Corner Cases & Edge Conditions

### 5.1 `clearPersistedSessionOnColdStart` calls `signOut()` which emits `signedOut`, racing with initial `_syncFromCurrentSession`

`AuthRepositoryImpl.clearPersistedSessionOnColdStart()` calls `_client.auth.signOut()`. If there *was* a persisted session (there shouldn't be, since `EmptyLocalStorage` is used), this fires `onAuthStateChange(signedOut)`. The `AuthSessionNotifier._handleAuthState` handles `signedOut` by setting the state to unauthenticated. This is fine, but it means cold-start is doing: `signOut()` → stream event → `unauthenticated` state, then `_syncFromCurrentSession()` reads `currentSession == null` → `unauthenticated` again. Two redundant state writes. With `EmptyLocalStorage` as the `localStorage`, `currentSession` should already be `null`, so `clearPersistedSessionOnColdStart()` is effectively a no-op network call that may add latency to boot.

> **Recommendation:** Since `EmptyLocalStorage` already prevents session persistence, `clearPersistedSessionOnColdStart()` is vestigial. Either remove it, or keep it only as a defensive belt-and-suspenders but skip the network round-trip when `currentSession == null`.

### 5.2 `SessionContextLoader.load` does **4 sequential awaits**, no timeout, no retry

For each `signedIn` / `initialSession` / `tokenRefreshed` event:
1. Decode JWT claims (local, fast)
2. `staff_members` query
3. `staff_branch_assignments` query (only if branch IDs present)
4. `roles_permissions` query (via `PermissionRepository`)
5. `organizations` query (only if org present)

These run sequentially with **no per-call timeout and no retry**. If the network is degraded (the startup probe allows `degraded` connectivity), a slow query will hang the auth state machine in `AuthSessionStatus.loading` indefinitely. The `_waitForPostLoginResolution` poller in `AuthNotifier` has a 3 s timeout, but that only updates the *UI* — the `AuthSessionNotifier` itself has no timeout and will remain in `loading` until the query resolves or fails.

> **Recommendation:** Add per-query timeouts and a single retry with backoff in `SessionContextLoader`, and have `AuthSessionNotifier` expose a `loadingTimeout` that transitions to `unauthenticated` with a failure message if context loading exceeds e.g. 10 s.

### 5.3 `StaffRole.tryParse` accepts `claims['staff_role']` as a fallback, but JWT claim may use `'lab_staff'` or `'labStaff'`

`session_context_loader.dart:40-44`:

```dart
final role = StaffRole.tryParse(staffRow['role']?.toString()) ?? StaffRole.tryParse(claims['staff_role']?.toString());
```

`StaffRole.tryParse` normalizes to lowercase and matches `'lab_staff'`. If the JWT custom-claims function ever emits `'lab_staff'` with different casing (e.g. `'Lab_Staff'`) the lowercase normalization handles it. But if the claims function emits the Dart enum name `'labStaff'` (camelCase), `tryParse` will return `null` and the loader will throw `StateError('...missing a valid staff role')`. This is fragile because the client is trusting the JWT claim shape with no documentation of the contract.

> **Recommendation:** Document the JWT `staff_role` contract in `session_context_loader.dart` and add a test that parses all four wire values.

### 5.4 `decodeAccessTokenClaims` returns empty map on expiry — `staff_member_id` will be `null` → `StateError` rather than a clean sign-out

`supabase_config.dart:160-167` — if the JWT is expired, the decoder returns `{}`. The loader then sees `staff_memberId == null` and throws `StateError('Authenticated session is missing staff claims.')`. The `AuthSessionNotifier` catch block classifies this as `missing_staff_claims` and calls `signOut()`. End result is correct (sign out), but the **log message is misleading** — it says "missing staff claims" when the real cause is "expired JWT". Since `tokenRefreshed` is handled separately and refresh failure also signs out, this path is reachable only if the initial session has a token that's already expired (e.g. clock skew, or a paused app resumed after expiry). 

> **Recommendation:** Distinguish `exp` expiry from missing claims in `decodeAccessTokenClaims` (return a typed result or log the expiry reason) so the sign-out flow logs an accurate category.

### 5.5 `branchIds` parsing splits a comma-separated string claim

```dart
final branchIdsRaw = claims['branch_ids']?.toString() ?? '';
final branchIds = branchIdsRaw.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
```

JWT custom claims are a single comma-joined string. If a branch UUID contains a comma (impossible for UUIDv4, but a sanitization concern for future IDs), this breaks. More importantly, if `branch_ids` claim is the string `"null"` or `"undefined"` (some JS-based claim generators emit this), it will be parsed as a single branch id `null`. The `.where((v) => v.isNotEmpty)` filters empty strings but not `"null"` string literals.

### 5.6 `setActiveBranch` silently no-ops on invalid branch

`AuthSessionNotifier.setActiveBranch`:

```dart
void setActiveBranch(String branchId) {
  final context = state.context;
  if (context == null || !context.branchIds.contains(branchId)) {
    return;
  }
  state = state.copyWith(context: context.copyWith(activeBranchId: branchId));
}
```

The `copyWith(activeBranchId: branchId)` uses the sentinel approach to set the branch — fine. But the silent no-op is a UX issue: if a stale branchId is selected (e.g. the user's branch was removed), the `BranchSelectionNotifier.selectBranch` also silently no-ops. The user sees no feedback. Consider surfacing a toast or clearing the selection.

### 5.7 `reloadContext` on `AppLifecycleState.resumed` can race with an in-flight token refresh

`app.dart:44-55`:

```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state != AppLifecycleState.resumed) return;
  final auth = ref.read(authSessionProvider);
  if (!auth.isAuthenticated || auth.context!.needsClinicSetup) return;
  unawaited(ref.read(authSessionProvider.notifier).reloadContext());
}
```

`reloadContext` → `refreshSessionContext` → `refreshSession()` (Supabase) then re-loads context. If the OS resumed the app *because* Supabase just fired a `tokenRefreshed` event (common on web where the tab regain focus triggers a refresh), there will be **two concurrent context loads** for the same session. See 3.2 for the missing in-flight guard.

### 5.8 `AuthRouteGuard.patientRouteRedirect` deliberately skips permission checks

```dart
// Permission checks are enforced on each patient page (UI stays visible; denial in-page).
return null;
```

This means the router allows any authenticated user to *navigate* to `/patients`, `/patients/new`, `/patients/:id`, `/patients/:id/edit`. Permission denial is in-page. This is a documented design decision, but it means a `labStaff` user (no `patients.create`) can route to `/patients/new` and the page loads before showing a denial. If any patient page performs an unauthenticated-friendly query (e.g. a `count(*)`) on build, it will execute with the *user's* JWT — which is RLS-protected, so it's safe at the DB layer, but the page still builds. The inconsistency with other route families (appointments, billing, shifts, visits all redirect on denial) is a smell.

---

## 6. Architectural Smells

### 6.1 `AuthSessionNotifier` has too many responsibilities (God notifier)

It owns:
- Supabase readiness observation
- Stream subscription lifecycle
- Cold-start persisted-session clearing
- Auth state event handling (signedIn, signedOut, tokenRefreshed, initialSession)
- Session context loading (delegated but coordinated)
- Clinic setup state tracking (`_hadProperClinicSetup`)
- Idle timeout sync
- Sign-out / idle-timeout sign-out
- Post-sign-in sync
- Post-bootstrap / post-resume context refresh
- Active branch mutation

This is 11 responsibilities in a single ~330-line notifier. The split between this file and `AuthNotifier` (presentation) is correct, but `AuthSessionNotifier` itself should be decomposed — e.g. idle-timeout sync could live in its own notifier that watches `authSessionProvider`; the "supabase ready" guarantee could be a separate `SupabaseReadinessNotifier`.

### 6.2 `permissionServiceProvider` is derived but not reactive

```dart
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService(ref.watch(authSessionProvider).context);
});
```

`ref.watch` correctly rebuilds the `PermissionService` when `authSessionProvider` emits. However, consumers that call `ref.watch(permissionServiceProvider).canViewPatients()` get a snapshot at build time. If the session context refreshes (e.g. after a permission matrix save) while a page is on screen, the page's `PermissionService` instance is replaced — but any imperative call paths that captured `ref.read(permissionServiceProvider)` before the refresh will use the stale instance. This is the standard Riverpod "read vs watch" hazard, but it's particularly sharp here because permission grants *do* change at runtime (after admin edits the matrix and `reloadContext` fires).

### 6.3 Error classification via string-contains heuristics

`AuthNotifier._authExceptionCategory`, `_unexpectedErrorCategory`, `_messageForAuthException`, `_messageForUnexpectedSignInError` all classify errors by `.toLowerCase().contains('invalid')`, `.contains('postgrest')`, `.contains('jwt')`, etc. This is brittle:

- Supabase error message wording can change across SDK versions.
- Localization of error messages would break the classifiers (they match English substrings).
- The `AuthException.code` field is checked but only via string-contains on `${error.code ?? ''} ${error.message}` — it is not compared against documented GoTrue error codes (`invalid_credentials`, `email_not_confirmed`, etc.).

> **Recommendation:** Switch to matching `AuthException.code` against the documented GoTrue error code constants. Fall back to message-contains only when `code` is absent.

### 6.4 `kGenericSignInFailureMessage` comment says "must not reveal whether the username exists" — but `_messageForUnexpectedSignInError` does reveal it

```dart
if (details.contains('staff claims') || details.contains('staff profile')) {
  return 'This account is missing clinic staff permissions. Contact your clinic administrator.';
}
```

This message reveals that the *account exists* (it authenticated successfully but has no staff profile). The generic sign-in failure message is bypassed for this case. This is a minor info-leak: an attacker who submits a valid password but sees "missing clinic staff permissions" learns that the username+password are correct but the account isn't provisioned. Whether this is acceptable depends on threat model, but it contradicts the stated principle at line 10.

### 6.5 `InMemoryGotrueAsyncStorage` store is a **static** map

```dart
static final Map<String, String> _store = {};
```

This static map persists for the entire isolate lifetime and is shared across all `InMemoryGotrueAsyncStorage` instances. In tests that run sequentially in the same process, stale PKCE values from a previous test leak into the next. This is a test-isolation hazard. The class is `const`-constructible, so each "instance" is the same static store.

> **Recommendation:** Make the store an instance field, or add a `reset()` testing hook and call it in `setUp`.

### 6.6 `EmptyLocalStorage` for `localStorage` + `InMemoryGotrueAsyncStorage` for `pkceAsyncStorage`

```dart
authOptions: const FlutterAuthClientOptions(
  localStorage: EmptyLocalStorage(),
  pkceAsyncStorage: InMemoryGotrueAsyncStorage(),
),
```

`localStorage` is empty (no persistence — correct for workstation model), but `pkceAsyncStorage` is in-memory. PKCE is used for OAuth flows, not password sign-in. For password-only auth this is fine, but if magic-link / OAuth is ever added, the PKCE verifier will live in the static map and survive across "cold starts" within the same process (e.g. web hot restart) — undermining the "no cross-restart persistence" guarantee. Document that OAuth flows are unsupported in the workstation model, or clear the PKCE store on sign-out.

---

## 7. Minor Issues & Observations

| # | Location | Issue |
|---|----------|-------|
| 1 | `auth_notifier.dart:125-138` | Poll loop uses `const attempts = 150` magic number; extract as named constant with documentation. |
| 2 | `login_page.dart:125` | `Future(() => authNotifier.resetSignInForm())` on dispose — if the page is disposed because the user navigated to `/home` post-login, this resets the form state of a now-hidden page. Harmless, but the notifier is global; the reset is more meaningful on explicit "leave login" intent. |
| 3 | `auth_route_guard.dart:49` | `needsClinicSetup(AuthSessionContext context)` is a one-liner instance method on a static-only class — could be a getter on `AuthSessionContext` itself (`context.needsClinicSetup` already exists on the model). The static wrapper is redundant. |
| 4 | `auth_session.dart:85` | `needsClinicSetup` getter recomputes `setupRequired || organizationId == null || organizationId!.trim().isEmpty` on every access — trivial cost, but since `AuthSessionContext` is `@immutable`, this could be a `final` computed in the constructor. |
| 5 | `permission_service.dart:17-19` | `hasPermission` returns `false` if `!context.hasBranchAssignment`. This means a user with permissions but no branch assignment has **zero** permissions. This is by design (branch-scoped RBAC), but it means an `administrator` with no branch assignment cannot do anything — including setting up branches. Verify the bootstrap admin always has a branch assignment, or make branch-management exempt from the branch-assignment gate. |
| 6 | `auth_dev_widgets.dart:11-14` | `AuthDevBootstrapCredentials` exposes `admin`/`admin` credentials in a Dart source file. `kDebugMode` guards rendering, but the strings are in the binary. For a clinic-local deployment this is acceptable; for any public build it's a credential leak. |
| 7 | `clinic_setup_welcome_dialog.dart:36` | `AppColorPrimitives.teal50.withValues(alpha: 0.45)` — `withValues` is the Flutter 3.27+ API. Ensure min SDK version is pinned; otherwise a downgrade breaks compilation. (Project-wide concern, not auth-specific.) |
| 8 | `auth_session_provider.dart:236-246` | `signOut()` sets state to `unauthenticated` after `await signOut()` resolves. If the Supabase `signOut()` network call hangs, the user is stuck in `authenticated` with an in-flight sign-out and no UI feedback. Add a timeout / optimistic state update. |
| 9 | `auth_notifier.dart:45-51` | `validateCredentials` is public but never called externally — it duplicates the inline validation in `signIn` (lines 54-58). Dead or redundant. |
| 10 | `login_page.dart:49` | `forgotPassword` route redirects to `${AppRoutes.login}?forgot=1`, but no code in `LoginPage` reads the `forgot` query param to auto-trigger `showForgotPasswordMessage`. The redirect is a dead path. |

---

## 8. Summary of Top Recommendations

**Security / access consistency (do first):**

1. Make `AuthRouteGuard.needsClinicSetup` accept a nullable context (§2.1).
2. Replace the live `AuthenticatedShell` backdrop in `LoginPage` with a static placeholder (§2.4, §4.5).
3. Switch `AuthNotifier` error classification to documented GoTrue error codes (§6.3).
4. Reconcile the "must not reveal username existence" principle with the "missing staff permissions" message (§6.4).

**State machine robustness:**

5. Add an in-flight context-load guard in `AuthSessionNotifier` (§3.2, §5.7).
6. Replace the `_waitForPostLoginResolution` poller with a single listen/listener (§3.1).
7. Add timeouts to `SessionContextLoader` queries and a `loadingTimeout` to the auth state machine (§5.2).
8. Move the welcome-dialog "shown" flag into a provider keyed by `staffMemberId` (§3.4).

**Simplification:**

9. Either delete the use-case layer or make `SignIn` own the full post-login orchestration (§4.1).
10. Move `RolePermissionSeed` to test-only scope (§4.2).
11. Adopt the `copyWithSentinel` pattern in `AuthUiState.copyWith` (§4.4).
12. Evaluate removing `clearPersistedSessionOnColdStart` now that `EmptyLocalStorage` is in place (§5.1).

**Cleanup:**

13. Decompose `AuthSessionNotifier` (idle-timeout sync, supabase readiness) into separate notifiers (§6.1).
14. Make `InMemoryGotrueAsyncStorage._store` instance-scoped or add a test reset hook (§6.5).
15. Remove the dead `forgot=1` redirect or implement its consumer (item 10 above).

---

*End of review.*