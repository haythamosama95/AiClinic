# Setup Feature Architectural Review

> Scope: `frontend/lib/features/setup/**` and all adjacent auth/session-routing infrastructure that gates access around clinic setup (`app/router.dart`, `app/providers/auth_session_provider.dart`, `core/auth/auth_route_guard.dart`, `app/shell/**`, `features/auth/presentation/widgets/clinic_setup_welcome_scope.dart`).
> Date: 2026-07-11
> Reviewer: opencode (automated architectural review)

This review focuses on the **clinic setup (bootstrap) feature** — the first-run wizard that creates the organization, branches, staff and services, plus its steady-state "run setup again" re-configuration path. It is the complement to `auth-architectural-review.md`, which covered the `features/auth/**` sign-in/sign-out machinery. The two features are tightly coupled: setup is only reachable while authenticated, and the session's `needsClinicSetup` flag is what forces a user into the wizard. The primary mandate of this review is to find **loopholes where the app could end up accessible while no account is signed in or while setup is incomplete**, plus corner cases, redundant/complex implementations, and state-machine hazards.

---

## 1. Architectural Overview

### 1.1 Layered structure

```
setup/
├── application/      setup_rpc_messages.dart            (shared RPC error → user message mappers)
├── data/             bootstrap_repository.dart           (Supabase RPC: bootstrap_finish_setup, create_org, create_branch, dev_reset)
│                     provisioning_repository.dart        (Supabase RPC: create_staff_account, reset_password, update_username, list staff/branches)
├── domain/           bootstrap_finish_setup_input/result, bootstrap_organization_input, bootstrap_branch_input,
│                     bootstrap_dummy_data, bootstrap_field_options, branch_field_validation, branch_summary,
│                     create_staff_account_input/result, admin_reset_staff_password_result, admin_update_staff_username_result,
│                     provisioning_rules, staff_password_validation, staff_member_summary, staff_username (re-exported),
│                     setup_step_readiness, setup_wizard_draft_ids, clinic_setup_draft_mapper, persist_clinic_setup_draft,
│                     repositories/{bootstrap,provisioning}_repository.dart
│                     usecases/{create_organization, create_bootstrap_branch, finish_bootstrap_setup, create_staff_account,
│                               reset_staff_password, update_staff_username, list_org_staff_members, list_branches_by_ids,
│                               reset_installation, setup_use_case_providers}
├── presentation/
│   ├── pages/        setup_page.dart                     (LEGACY — dead, see §7.1)
│   ├── providers/    clinic_setup_notifier.dart          (god notifier: draft state + bootstrap + steady-state CRUD + hydration + dev reset)
│                     clinic_setup_providers.dart         (org/branch FutureProviders for setup screen)
│                     clinic_setup_hydration_provider.dart(autoDispose hydration trigger)
│                     provisioning_notifier.dart          (create/reset/update staff — used by settings, misplaced here, see §7.5)
│                     staff_assignable_branches_provider.dart
│   ├── setup/        setup_wizard.dart, setup_step_panel.dart, setup_step_rail.dart, setup_validation.dart,
│   │                 setup_draft_models.dart, setup_field_hints.dart, steps/{organization,branch,staff,services}_step.dart,
│   │                 widgets/{collapsed_branch_card, collapsed_staff_card, collapsed_summary_enter_transition,
│   │                          entity_list, maps_location_input, working_hours_editor}
│   ├── widgets/      clinic_setup_dialog.dart, clinic_setup_dialog_content.dart, clinic_setup_complete_dialog.dart
│   └── dev/          setup_dev_widgets.dart              (dead — always SizedBox.shrink(), see §7.2)
```

### 1.2 The dual-mode state machine

`ClinicSetupNotifier` (`clinic_setup_notifier.dart:125`) is the heart of the feature and deliberately merges **two formerly separate notifiers** (per its own doc comment, lines 118–124):

| Mode | Trigger | Backend path |
| ---- | ------- | ------------ |
| **First-run bootstrap** | `session.needsClinicSetup == true` | atomic `bootstrap_finish_setup` RPC |
| **Steady-state re-config** | `session.needsClinicSetup == false` (user clicked "Run setup again") | individual CRUD via `persistSetupDraftToBackend` (settings use cases) |

The mode is selected at runtime inside `completeSetup()` (`clinic_setup_notifier.dart:377`) by reading `authSessionProvider`. This single dual-mode notifier is the source of most of the complexity findings below.

### 1.3 How setup is presented (not routed)

There is **no dedicated setup-wizard route**. `AppRoutes.bootstrap` (`app_routes.dart:13`) exists only as a redirect to `/home` (`router.dart:68`). The wizard is shown **imperatively as a dialog** by `ClinicSetupWelcomeScope` (`clinic_setup_welcome_scope.dart`), which is mounted inside `AuthenticatedShell` (`authenticated_shell.dart:108`) wrapping the routed child. So a `needsClinicSetup` user is force-redirected to `/home` (`auth_route_guard.dart:11` defines `clinicSetupRoute = AppRoutes.home`) and the dialog overlays the home placeholder. This design contract is central to several findings.

### 1.4 Access-gating chain (end to end)

```
App launch → StartupSessionNotifier.bootstrap() → AuthSessionNotifier._ensureSupabaseReady()
  → (cold start clears persisted Supabase session) → unauthenticated
  → Login → sign_in → _applyAuthenticatedContext(context)
  → if context.needsClinicSetup: router redirect forces /home
  → AuthenticatedShell renders; ClinicSetupWelcomeScope shows welcome → ClinicSetupDialog → wizard
  → completeSetup() → bootstrap_finish_setup RPC → refreshSessionContext()
  → needsClinicSetup flips false → router redirect releases /home; shell chrome unlocks
  → ClinicSetupCompleteDialog (celebration)
```

The authoritative gate for "is setup done" is the **backend JWT-derived** `AuthSessionContext.needsClinicSetup` (`auth_session.dart:83`), computed as `setupRequired || organizationId == null || organizationId.trim().isEmpty` (`auth_session.dart:115`). The local `ClinicSetupState.completed` flag only drives the setup **UI** (the "Setup complete / Run setup again" banner), never routing. This is the correct security posture and is confirmed by `isSetupCompleteProvider` (`clinic_setup_notifier.dart:110`), which defers to the session when `needsClinicSetup` is true.

---

## 2. Critical Findings — Unauthorized / Pre-Setup Access Risk

The mandate specifically asks for loopholes where the app is "accessible while no account is signed in." Below they are ranked by severity. Release-build behavior is the baseline; debug-only exposure is called out separately.

### 2.1 ⚠️ HIGH — Cold-start `unknown`/`loading` window allows a deep link into `AuthenticatedShell`

`AuthRouteGuard.resolveRedirect` returns `null` (no redirect) when `auth.status` is `unknown` or `loading` (`auth_route_guard.dart:529–531`). At cold start the auth state begins as `unknown` (`AuthSessionState.initial()`, `auth_session_provider.dart:33`) and stays there until `StartupSessionNotifier.bootstrap()` completes and `_runEnsureSupabaseReady` transitions to `loading` then `authenticated`/`unauthenticated`.

During that window:
- The router's `unauthenticatedEntry` switch (`router.dart:212–243`) handles `startupCheck` by redirecting non-`/login`/non-`/home` locations to `/login` — **but `/home` itself is explicitly allowed through** (`router.dart:214` condition only redirects when `location != login && location != home`).
- `/home`'s builder is `shellPlaceholderPage` (`router.dart:78`) inside the `ShellRoute` → `AuthenticatedShell` renders with the sidebar/topbar chrome.
- `AuthenticatedShell` computes `setupLocked = auth.context?.needsClinicSetup ?? false` (`authenticated_shell.dart:42`). With a null context (the `unknown` state), **`setupLocked` defaults to `false`**, so the command bar, sidebar navigation, and topbar actions are all **enabled** during this window.

Net effect: on a cold start with a deep link to `/home` (or any shell route that survives the `startupCheck` redirect), the user briefly sees the fully-enabled authenticated shell chrome before auth resolves. The routed child is a placeholder today so no real data leaks, but the chrome is interactive (a sidebar `onNavigate` tap would `context.go` and then be bounced on the next redirect cycle). The window is short, but it is a real pre-auth access surface.

**Fix:** (a) In `auth_route_guard.dart`, treat `unknown`/`loading` like `unauthenticated` for non-public routes (redirect to `/login`) instead of returning `null`. (b) Independently, change the `setupLocked` default in `authenticated_shell.dart:42` to `?? true` (see §2.3) so a null context always locks the chrome.

### 2.2 ⚠️ MEDIUM — Setup dialog is dismissible; dismissed state leaves user on `/home` with `needsClinicSetup == true`

`ClinicSetupWelcomeDialog` is `barrierDismissible: true` (`clinic_setup_welcome_dialog.dart:21`) and `ClinicSetupDialog.show` is awaited (`clinic_setup_welcome_scope.dart:81`). If the user dismisses the setup dialog (`completed == false`, scope line 82), the scope returns **without** completing setup. The session remains `isAuthenticated && needsClinicSetup`. The user now sits on `/home` inside `AuthenticatedShell`.

The shell chrome is soft-locked (`setupLocked == true` disables command bar / sidebar nav / topbar actions, `authenticated_shell.dart:50–97`), and the routed child is `shellPlaceholderPage`. But:

- The welcome scope does **not** re-trigger `_maybeStartSetupFlow` after dismissal. `ref.listen<AuthSessionState>` (`clinic_setup_welcome_scope.dart:95–147`) only fires on **auth state changes**, and dismissal does not change auth state. The single-flight `_clinicSetupFlowRunning` flag is cleared in `finally` (line 89), but nothing schedules another attempt.
- The only ways back into the wizard are: (i) an auth state transition (sign out/in), or (ii) remounting `ClinicSetupWelcomeScope` (navigating away and back, which is blocked by the soft-locked chrome).

So a user who accidentally dismisses the setup dialog is **stranded on a locked home screen with no visible path back to setup** except signing out and back in. This is a dead-end state — not a security leak (chrome is locked and child is a placeholder), but a UX trap and an architectural smell: the gating relies on an imperative dialog that can be dismissed, with no re-entry path.

**Fix:** Make `ClinicSetupDialog` non-dismissible while `needsClinicSetup` is true (`barrierDismissible: false`, `showCloseButton: false` — note `ClinicSetupDialog` already sets these, but the **welcome** dialog does not; and the user can still dismiss via Android back-button on the setup dialog unless `PopScope` guards it). Alternatively, re-arm `_maybeStartSetupFlow` on a timer or on focus regain when `needsClinicSetup` is still true. Add a `PopScope(canPop: false)` around the setup dialog while setup is required.

### 2.3 ⚠️ MEDIUM — `setupLocked` defaults to `false` on null context (defence-in-depth gap)

`authenticated_shell.dart:42`:
```dart
final setupLocked = auth.context?.needsClinicSetup ?? false;
```
This contradicts the safer default used everywhere in `auth_route_guard.dart`, where null context is treated as setup-locked (`auth.context?.needsClinicSetup ?? true`, e.g. `auth_route_guard.dart:51`). When the context is null (cold-start `unknown` window, debug unauthenticated preview, or any transient state), the shell chrome is **enabled** rather than locked. Combined with §2.1, this is what makes the cold-start window materially unsafe rather than merely cosmetic.

**Fix:** Change to `?? true`. Locking the chrome when context is unknown is the safe default; it unlocks once an authenticated, setup-complete context arrives.

### 2.4 ⚠️ LOW (debug-only) — Unauthenticated shell preview exposes the whole shell route tree

`router.dart:179–181` returns `null` (no redirect) when `!auth.isAuthenticated` and dev nav is enabled and `ShellNavConfig.allowsUnauthenticatedPreview(location)` is true (`shell_nav_config.dart:62–69` — true for any shell nav item with a non-`dev` itemId). This lets an unauthenticated user match into `AuthenticatedShell`. Today every such route wires `shellPlaceholderPage`, so only a placeholder renders — but the **shell chrome** still renders, and with §2.3's `false` default the chrome is interactive. This is debug-only (`kDebugMode` gated upstream), but it is a structural smell: the only thing preventing authenticated content from leaking is the choice of `shellPlaceholderPage` as the builder, not a guard.

**Fix:** Either gate `AuthenticatedShell`'s chrome rendering on `auth.isAuthenticated` (return a bare `SizedBox` for the chrome when unauthenticated in debug preview), or keep §2.3's `?? true` so the chrome is inert during preview.

### 2.5 ✅ Confirmed safe — `canAccessX` helpers default null context to setup-locked

All `AuthRouteGuard.canAccess*FeatureRoute` helpers (e.g. `canAccessPatientList` `auth_route_guard.dart:49–54`) use `(auth.context?.needsClinicSetup ?? true)` and return `false` when not authenticated. This is the correct fail-closed default. The eight `auth.context!` dereferences in `auth_route_guard.dart` (lines 409, 417, 429, 436) are safe **only** because of the invariant `isAuthenticated ⇒ context != null` (`auth_session_provider.dart:39`). This invariant is fragile — see §4.1.

### 2.6 ✅ Confirmed safe — Backend is authoritative for the gate

Routing and the shell derive "is setup done" from `auth.context.needsClinicSetup` (JWT-backed), not from `ClinicSetupState.completed` (local SharedPreferences). The local flag cannot unlock the app. `isSetupCompleteProvider` (`clinic_setup_notifier.dart:110`) explicitly defers to the session when `needsClinicSetup` is true. After `completeSetup()` the notifier calls `refreshSessionContext()` (`clinic_setup_notifier.dart:395`) before marking `completed`, so the JWT is refreshed before the UI advances. Good.

### 2.7 ✅ Confirmed safe — `canPerformBootstrapSetup` is guarded in the wizard body

A non-bootstrap-admin who somehow has `needsClinicSetup == true` lands on `/home` with the welcome scope, which shows `ClinicSetupWelcomeDialog` then `ClinicSetupDialog`. `ClinicSetupDialogContent` (`clinic_setup_dialog_content.dart:29`) computes `canRunBootstrapSetup = !setupRequired || (session?.canPerformBootstrapSetup ?? false)` and, when false, renders an "Administrator sign-in required" alert **instead of** the `SetupWizard` (lines 218–229). Additionally `completeSetup()` re-checks `session.canPerformBootstrapSetup` server-side (`clinic_setup_notifier.dart:383`) and refuses with an error. So a non-bootstrap user cannot execute bootstrap RPCs. (Minor UX wart: the welcome dialog still pops for them before they see the "sign in as admin" alert.)

---

## 3. Critical Findings — Data Loss & Correctness in the Bootstrap Path

### 3.1 ⚠️ HIGH — First-run bootstrap silently discards services, extra branches, and staff branch assignments

This is the most significant functional defect in the feature. The wizard presents a 4-step flow:

1. Organization
2. Branches (user can add **multiple** branches)
3. Staff (user assigns each staff member to **one or more branches** via `AppMultiSelect`, `staff_step.dart:583–591`)
4. Services (user adds **multiple** services with prices)

But the atomic first-run backend path uses `bootstrap_finish_setup`, whose input is `BootstrapFinishSetupInput` (`bootstrap_finish_setup_input.dart`) containing **only**: `organization`, a **single** `branch`, and `staffAccounts`. The mapper `toBootstrapFinishSetupInput` (`clinic_setup_draft_mapper.dart:169`) confirms this:

- `final primaryBranch = draft.branches.first;` (line 178) — **all branches after the first are dropped**.
- `staffAccounts.add(CreateStaffAccountInput(... branchIds: const [], ...))` (line 193) — **every staff member's branch assignment is hardcoded to empty**, even though the wizard's validation (`setup_validation.dart:124–126`) *requires* the user to select at least one branch per staff member. The user's selection is collected, validated, then silently ignored.
- `draft.services` is **never referenced** — services are not part of `BootstrapFinishSetupInput` at all. Every service entered in step 4 is discarded in first-run mode.

The `finishSetup` RPC payload (`bootstrap_repository.dart:89–112`) confirms no `p_services` parameter exists.

Worse, the success path (`clinic_setup_notifier.dart:392–407`) does **not** call `hydrateFromBackend()` — it sets `completed: true` and persists the draft (still containing the dropped services/branches) to SharedPreferences. So the local draft *looks* complete, but the backend only has 1 branch + staff (unassigned to the user's chosen branches) + 0 services. The discrepancy only surfaces if the user clicks "Run setup again" (which calls `resetSetup()` + `hydrateFromBackend()`, reloading the true sparse backend state — at which point the extra data is gone with no warning).

**Impact:** A clinic admin completing first-run setup with >1 branch, services, or specific staff-branch assignments believes their clinic is configured as entered. It is not. This is silent data loss in the flagship onboarding flow.

**Fix (choose one):**
- **(A) Make the wizard match the backend.** In first-run mode, restrict the wizard to exactly 1 branch and skip the services step (or clearly mark services as "added after setup"). Stop collecting staff branch assignments in bootstrap mode (or auto-assign to the single branch and tell the user).
- **(B) Make the backend match the wizard.** Extend `bootstrap_finish_setup` to accept `p_branches` (array) and `p_services` (array), and pass `staff.branchIds` through. This is the better long-term fix and preserves the atomic transaction.
- Either way, after a successful bootstrap, call `hydrateFromBackend()` so the local draft reflects backend truth instead of retaining phantom entries.

### 3.2 ⚠️ MEDIUM — Plaintext staff passwords persisted to SharedPreferences

`StaffDraft.toJson()` serializes `'password': password` (`setup_draft_models.dart:211`). `ClinicSetupNotifier.persistDraft()` (`clinic_setup_notifier.dart:194`) writes `jsonEncode(state.draft.toJson())` to `SharedPreferences` under `aiclinic:setup-draft`. Every staff password typed into the wizard is therefore stored **in plaintext** in platform shared preferences, surviving across app restarts until `resetSetup()`/`syncWithSession()` clears the key.

This includes the bootstrap admin's own first staff accounts. On Android, SharedPreferences are readable on rooted devices and via backup extraction. This is a credential-handling concern, not a routing loophole.

(Note: `hydrateFromBackend` in `kDebugMode` additionally injects `DevClinicSeedSpec.knownPasswordForDevSeedStaff` into hydrated staff drafts (`clinic_setup_notifier.dart:613–623`), which is debug-only and acceptable, but it compounds the "passwords live in the draft model" pattern.)

**Fix:** Do not store passwords in the draft model at all — collect them transiently and discard after the RPC returns the created account. If draft persistence of staff is required, persist everything *except* `password` (mask it as `null` in `toJson`), and re-prompt on hydration. At minimum, never write `password` to SharedPreferences.

### 3.3 ⚠️ MEDIUM — `loadDraft` and the `syncWithSession` listener race on cold start

`ClinicSetupNotifier`'s constructor schedules `loadDraft` via `Future<void>.microtask(loadDraft)` (`clinic_setup_notifier.dart:127`). Separately, the provider wires `ref.listen<AuthSessionState>(authSessionProvider, ...)` to call `syncWithSession(next.context)` on every auth change (`clinic_setup_notifier.dart:99–101`).

`loadDraft()` does:
1. `await SharedPreferences.getInstance()` (an await — yields the event loop)
2. reads `raw`, `completed`, `completedSteps`
3. builds a `ClinicSetupState` from the persisted draft
4. `state = ClinicSetupState(draft: draft, completed: completed, ...)` (line 149)
5. `await syncWithSession(...)` (line 150)

If, during step 1's await, the auth session changes (e.g. the cold-start `unknown → unauthenticated` transition fires the listener), `syncWithSession` runs and — if the new session has `needsClinicSetup` — **resets state and deletes the prefs keys** (`clinic_setup_notifier.dart:170–178`). When `loadDraft` resumes at step 4, it **overwrites** the reset with the stale draft it already read into memory, resurrecting a draft that was supposed to be wiped.

This is a low-probability but real race. The inverse (loadDraft completing, then a needsClinicSetup session arriving) is handled because `loadDraft` itself calls `syncWithSession` at the end. But the mid-await listener path is not.

**Fix:** Guard with a load token / `bool _loaded` flag, or skip the listener's `syncWithSession` until `loadDraft` has completed (`if (!_loaded) return;` early in the listener), or have `loadDraft` re-read prefs after its await rather than holding `raw` across the yield.

### 3.4 ⚠️ LOW — `completeSetup()` has no re-entrancy guard at the notifier layer

`completeSetup()` sets `isSubmitting = true` at the start (`clinic_setup_notifier.dart:378`) and the wizard disables the button on `isSubmitting` (`setup_wizard.dart:128`). But the notifier itself does not check `state.isSubmitting` before re-entering. A programmatic double-invocation (e.g. a test, a keyboard shortcut, or a future caller) could fire `bootstrap_finish_setup` twice. The backend RPC is idempotent-ish (it would reject the second with `ORG_SETUP_INCOMPLETE`/`FORBIDDEN` once the first commits), but the local state would be corrupted (two success paths each setting `completed` and calling `refreshSessionContext`).

**Fix:** Early-return if `state.isSubmitting` at the top of `completeSetup()` (and `resetInstallationForDevelopment`).

### 3.5 ⚠️ LOW — Steady-state `completeSetup` is not transactional

The steady-state path (`clinic_setup_notifier.dart:431–511`) calls `persistSetupDraftToBackend`, which performs a sequence of independent CRUD RPCs: `updateOrganization`, then create/update/delete for each branch, each staff member, each service (`persist_clinic_setup_draft.dart`). These are **not atomic**. If the network fails midway (e.g. after creating 2 branches but before creating staff), the clinic is left in a partially-updated state, and `hydrateFromBackend()` (called at line 484) will load that partial state. The notifier surfaces a generic "Unable to save clinic setup" error, but the draft is now out of sync with the backend and the user may not know which entities were committed.

This is inherent to using steady-state CRUD for a wizard that implies atomicity, and contrasts sharply with the atomic `bootstrap_finish_setup` first-run path.

**Fix:** Either wrap the steady-state persistence in a backend transaction RPC (`update_clinic_setup`), or clearly communicate partial-success to the user (list which entities were saved vs. failed). At minimum, always call `hydrateFromBackend()` in the error path too, so the draft re-syncs to backend truth.

---

## 4. State-Machine & Invariant Hazards

### 4.1 Fragile `auth.context!` invariant

`AuthSessionState.isAuthenticated` is defined as `status == authenticated && context != null` (`auth_session_provider.dart:39`). Four `auth.context!` dereferences in `auth_route_guard.dart` (lines 409, 417, 429, 436) rely on this: each is textually preceded by `if (!auth.isAuthenticated || ...) return false;`, so reaching the `!` guarantees `context != null`. This is **safe today** but is a load-bearing invariant with no compile-time enforcement. If anyone ever relaxes `isAuthenticated` (e.g. to allow `authenticated` status with a null context during a reload), all four become null-derefs.

**Fix:** Add a unit test asserting `status == authenticated ⇒ context != null` is preserved by every `AuthSessionState` transition, or replace the `!` derefs with `auth.context` (nullable) + an explicit `return false` on null.

### 4.2 `refreshSessionContext` keeps stale context authorizing routes during refresh

`auth_session_provider.dart:279–298` refreshes the JWT and reloads context, but intentionally **keeps `isAuthenticated == true` with the previous context** while the new context loads (comment at lines 287–288: "Keep `isAuthenticated` true during refresh so route guards do not redirect away from deep-linked settings pages"). If the org setup was just torn down (e.g. dev reset), the stale context's `needsClinicSetup == false` continues to authorize routes until the new context arrives, at which point `_applyAuthenticatedContext` detects the regression and force-signs-out (`auth_session_provider.dart:305–309`).

For the setup feature specifically: after `completeSetup()` calls `refreshSessionContext()` (`clinic_setup_notifier.dart:395`), there is a brief window where the old `needsClinicSetup == true` context is still active even though the RPC has committed. This is benign (the wizard is still showing), but worth documenting. Low risk.

### 4.3 `_clinicSetupFlowRunning` and `_clinicSetupCelebrationShown` are module-level globals

`clinic_setup_welcome_scope.dart:14–17` declares these as top-level `bool`s, not instance fields. Because there is exactly one `ClinicSetupWelcomeScope` mounted (inside the single `AuthenticatedShell`), this works, but it is fragile:

- If the shell is ever re-created (e.g. hot reload, a future multi-window scenario), the globals persist with stale values.
- The single-flight `_clinicSetupFlowRunning` is shared across all instances — a second scope mount would see `true` and never start.
- They are reset on sign-out (`clinic_setup_welcome_scope.dart:100–106`) but not on scope dispose.

**Fix:** Move them to instance fields of `_ClinicSetupWelcomeScopeState`, or to a dedicated `Provider<bool>` state. Module-level mutable globals are a smell in a Riverpod app.

### 4.4 `syncWithSession` wipes state without preserving the in-progress draft

`syncWithSession` (`clinic_setup_notifier.dart:157–179`), when it detects `needsClinicSetup`, unconditionally replaces state with `createDefaultSetup()` and deletes prefs. If a user was mid-editing in steady-state "Run setup again" and the session flips to `needsClinicSetup` (e.g. another admin reset the installation), their unsaved draft is lost with no warning. This is an edge case (requires a concurrent reset) but the lack of any confirm/discard hook is a hazard.

---

## 5. Corner Cases & Edge Conditions

### 5.1 `staffRoleOptions` vs. `StaffRole` enum mismatch

`staffRoleOptions` (`setup_draft_models.dart:51–57`) exposes five values: `owner`, `administrator`, `doctor`, `receptionist`, `nurse`. But the domain `StaffRole` enum (`auth_session.dart:5–9`) is `administrator, doctor, receptionist, labStaff`. The mapper `staffRoleFromDraft` (`clinic_setup_draft_mapper.dart:153–162`) papers over this: `'owner' → administrator`, `'nurse' → labStaff`. So:

- The wizard offers an "Owner" role that silently becomes "Administrator".
- The wizard offers a "Nurse" role that silently becomes "Lab staff".
- The backend wire value for lab staff is `lab_staff` (`auth_session.dart:30`), so a "Nurse" selection becomes `lab_staff` in the RPC — a label/identity mismatch that will confuse admins reviewing staff later.

This is carried over from web parity (the file header notes "Web parity: settings.ts"). It is a latent correctness issue and a UX inconsistency (the displayed role won't match what's stored/shown elsewhere).

**Fix:** Align the option list with `StaffRole` exactly (`administrator, doctor, receptionist, labStaff` with correct labels), or make the mapping explicit and visible to the user. Drop `owner` (no such role) and rename `nurse` to `lab_staff`/"Lab staff".

### 5.2 Staff branch assignment validation is meaningless in bootstrap mode

`validateSingleStaff` (`setup_validation.dart:124–126`) requires `member.branchIds` non-empty whenever `branchCount > 0`. The wizard enforces this (`staff_step.dart`). But per §3.1, in bootstrap mode `branchIds` is hardcoded to `const []` in the RPC payload. So the user is forced to make a selection that is then thrown away. This is both a data-loss issue (§3.1) and a validation honesty issue: the validator asserts something the backend will ignore.

### 5.3 Service price precision validation uses floating point

`_validateServicePrice` (`setup_validation.dart:185–197`) does `(price * 100).round()` and compares `cents / 100 - price`. Floating-point multiplication of `double` prices is a known source of rounding error (e.g. `0.1 + 0.2`). For prices entered as decimals this is usually fine, but the validation rejects prices where `(price * 100)` is not integral within `0.001` tolerance — binary floating point can make legitimately-entered two-decimal prices fail this check spuriously (e.g. `19.99 * 100 = 1998.9999...`). The mapper later uses `price.toStringAsFixed(2)` (`persist_clinic_setup_draft.dart:198`), which would normalize it. The validation is stricter than the serialization.

**Fix:** Parse the user-entered price string as integer cents directly (don't round-trip through `double`), or validate on the string form (regex for ≤2 decimal places).

### 5.4 `normalizeSetupNationalPhone` silently truncates to last 10 digits

`clinic_setup_draft_mapper.dart:49–64` normalizes backend phone numbers to "10-digit national format." If a stored phone has >10 digits and doesn't start with `20`, it takes `digits.substring(digits.length - 10)` — silently dropping leading digits (country codes other than Egypt's `20`). For the non-Egypt currencies/timezones offered (USD, EUR, GBP, New York, London, Berlin), this is wrong: a US `+1...` number would be mangled. The setup wizard is Egypt-centric in its phone handling while offering international org settings — an inconsistency.

### 5.5 `isSetupDraftEntityId` heuristic

`setup_draft_models.dart:341–347` distinguishes "locally-created, unsaved" draft entities (id `<microseconds>_<counter>`) from hydrated backend UUIDs by regex `^\d+_`. This is a stringly-typed discriminator. If a backend ever returns an ID matching that pattern (unlikely for UUIDs but possible for other schemes), the entity would be misclassified as "new" and re-created on save, producing a duplicate. The branch/staff/service diff logic in `persistSetupDraftToBackend` (`persist_clinic_setup_draft.dart:82, 127, 165`) depends on this heuristic to decide create-vs-update. Brittle but low-risk given UUID backends.

### 5.6 Cold start always signs the user out

`_runEnsureSupabaseReady` calls `clearPersistedSessionOnColdStart` once per process (`auth_session_provider.dart:117–122`) when a session exists. This is a deliberate security choice (no silent workstation session restore), but it means: after completing setup, closing and reopening the app forces a fresh sign-in. The freshly-created staff accounts (whose passwords were shown once in the success dialog) must be re-entered. For a first-run admin who just created their own account and hasn't memorized the password, this is a friction point. Worth a UX note (the admin should be told to save credentials before closing).

### 5.7 `ProvisioningNotifier.resetStaffPassword` uses a hardcoded `< 6` length check

`provisioning_notifier.dart:250–253` validates the reset password with `trimmedPassword.length < 6`, while staff *creation* (in the setup wizard and `createStaffAccount`) uses `StaffPasswordValidation.validateInitialPassword` requiring `>= 8` chars + a letter (`staff_password_validation.dart:13–18`). So a password reset can produce a **weaker** password than initial creation allows (6 chars, no letter requirement). This is an inconsistency that weakens the password policy on the reset path.

**Fix:** Use `StaffPasswordValidation.validateInitialPassword` (or a shared `validatePassword` policy) in both paths.

### 5.8 `ProvisioningNotifier.updateStaffUsername` reuses `canResetStaffPassword` for authorization

`provisioning_notifier.dart:297` checks `ProvisioningRules.canResetStaffPassword(session.staffProfile)` to authorize a **username update**, then surfaces "Only clinic administrators can update staff usernames." This works because `canResetStaffPassword` checks `role == administrator` (`provisioning_rules.dart:11–13`), but the rule is semantically misnamed for the username path. A future change to password-reset authorization (e.g. allowing doctors to reset) would silently broaden username updates. There should be a distinct `canUpdateStaffUsername` rule, or a shared `canManageStaffAccount` rule.

---

## 6. Redundant / Unnecessary / Over-Complex Implementations

### 6.1 `ClinicSetupNotifier` is a 739-line god notifier

It owns: draft state, step navigation, per-entity CRUD methods (addBranch/updateBranch/removeBranch/confirmBranch/unconfirmBranch ×3 entity types), persist/hydrate, the dual-mode `completeSetup`, `resetSetup`, `markSetupComplete`, `resetInstallationForDevelopment`, validation-error reveal (×3), and session sync. The doc comment (lines 118–124) explicitly says it merged two formerly-separate notifiers (`SetupNotifier` + `ClinicSetupNotifier`). The merger produced a class with two distinct responsibilities (first-run atomic bootstrap vs. steady-state CRUD re-config) branching on `needsClinicSetup` at runtime.

**Recommendation:** Split back into a `BootstrapSetupNotifier` (first-run atomic path, owns `bootstrap_finish_setup` + draft) and a `ClinicReconfigNotifier` (steady-state CRUD via `persistSetupDraftToBackend`). The shared draft model can stay common. This removes the dual-mode branching in `completeSetup` and makes each mode independently testable.

### 6.2 Cross-feature layering violations

`clinic_setup_notifier.dart` imports from **five other features**:
- `features/settings/...` (branch_list_item, staff_list_item, staff_list_filter, organization_profile, create/update branch/staff/organization inputs, settings use case providers) — for the steady-state CRUD path.
- `features/service_catalog/...` (service_catalog_repository, service_list_item, global_status) — for service create/update/delete.
- `features/appointments/...` (appointment_surface_invalidation) — `invalidateAppointmentSurfaceProviders(_ref)` is called after both bootstrap and steady-state completion (lines 396, 485).
- `features/auth/...` (auth_session) — legitimate.
- `app/shell/dev/dev_clinic_seed_spec.dart` — for the debug password injection in `hydrateFromBackend`.

The setup feature is effectively a **god orchestrator** over settings + service_catalog + appointments. In Clean Architecture, a feature should not reach into another feature's use cases; cross-feature coordination belongs in an application/use-case layer or an event bus. The appointment invalidation call is especially leaky — setup knows about appointment surface providers.

**Recommendation:** Introduce a `ClinicSetupOrchestrator` use case in an `app/`-level application layer that depends on settings + service_catalog use cases, and have the notifier call only that. Replace `invalidateAppointmentSurfaceProviders` with a provider-invalidation event or a shared `clinicDataChangedProvider` that appointments listen to.

### 6.3 `setup_page.dart` is dead code

`SetupPage` (`setup_page.dart`) is labeled "Legacy routed setup page." It is **not referenced by the router** — `router.dart` imports only `clinicSetupProvider` from the setup feature, and `/bootstrap` is a redirect to `/home` (`router.dart:68`), not a `SetupPage` builder. No other file imports `SetupPage`. It contains its own `ref.listen<AuthSessionState>` redirect-to-home logic (`setup_page.dart:15–28`) that duplicates the welcome scope's logic. It is unreachable dead code that still must be maintained/compiled.

**Recommendation:** Delete `setup_page.dart`. The dialog-based flow (`ClinicSetupDialog` + `ClinicSetupWelcomeScope`) is the live path.

### 6.4 `setup_dev_widgets.dart` is dead code

`SetupDevWidgets.panel` (`setup_dev_widgets.dart`) returns `SizedBox.shrink()` unconditionally — even before the `if (!kDebugMode)` guard, the body is `return const SizedBox.shrink();` (line 15). It is a no-op API with no callers (the dev reset is wired separately via `shell_dev_reset_clinic.dart`). It exists only as a placeholder for an unimplemented dev panel.

**Recommendation:** Delete it, or implement it. Carrying an always-empty "dev widgets" stub adds noise.

### 6.5 `provisioning_notifier.dart` is misplaced in the setup feature

`ProvisioningNotifier` (`provisioning_notifier.dart`) handles `createStaffAccount`, `resetStaffPassword`, and `updateStaffUsername` — these are **steady-state staff management** operations (used by settings/admin staff screens), not setup-wizard concerns. It lives in `features/setup/presentation/providers/` purely for historical reasons (the setup wizard originally did per-staff provisioning). The wizard's first-run path no longer uses it (it uses `bootstrap_finish_setup` atomically); the steady-state wizard path uses `persistSetupDraftToBackend` directly, not `ProvisioningNotifier`.

**Recommendation:** Move `provisioning_notifier.dart` (and its `provisioning_rules.dart`, `staff_password_validation.dart`, the reset/update use cases and repository methods) into `features/settings/` (or a new `features/staff/` feature), since staff account lifecycle management is a settings concern. The setup feature should retain only the atomic bootstrap path.

### 6.6 Duplicate `clinicSetupOrganizationProvider` / `clinicSetupBranchesProvider` vs. `hydrateFromBackend`

`clinic_setup_providers.dart` defines `clinicSetupOrganizationProvider` and `clinicSetupBranchesProvider` (FutureProviders that fetch org/branches by organizationId). But `ClinicSetupNotifier.hydrateFromBackend()` (`clinic_setup_notifier.dart:588–636`) fetches the same organization, branches, staff, and services directly via use cases. These two data-fetch paths duplicate each other — the FutureProviders are not consumed by the notifier's hydration. A grep confirms they exist for the setup screen's own use, but having both the notifier's imperative fetch and the FutureProvider fetch is redundant and can produce inconsistent views.

**Recommendation:** Pick one fetch path. Either have the notifier's hydration read from the FutureProviders (so there's a single cached source), or remove the FutureProviders if the dialog content only uses `clinicSetupProvider`.

### 6.7 Two parallel "setup complete" celebration paths

The completion celebration can be triggered in two ways:
1. `ClinicSetupWelcomeScope._maybeStartSetupFlow` awaits `ClinicSetupDialog.show`, and on `completed == true` shows `ClinicSetupCompleteDialog` directly (`clinic_setup_welcome_scope.dart:81–87`).
2. `ClinicSetupWelcomeScope`'s `ref.listen` watches for `needsClinicSetup: true → false` transitions and calls `_presentCelebration` (`clinic_setup_welcome_scope.dart:106–115, 119–126`).

These overlap: a successful in-dialog `completeSetup()` both returns `completed == true` from the dialog (path 1) **and** fires the auth-state transition (path 2). The `_clinicSetupCelebrationShown` flag deduplicates, but the two paths exist because completion can happen outside the dialog (e.g. dev seed via `markSetupComplete` + `refreshSessionContext`). This is defensible but complex; the flag-based dedup is easy to break.

### 6.8 `resetInstallationForDevelopment` lives in the production notifier

`ClinicSetupNotifier.resetInstallationForDevelopment()` (`clinic_setup_notifier.dart:551–583`) is a dev-only operation (calls `dev_reset_clinic_installation`) but is a public method on the production notifier, with no `kDebugMode` guard at the notifier layer (the guard is only at the calling shell widget, `shell_dev_reset_clinic.dart`). The method is reachable from any Riverpod scope in any build. This is the same concern flagged in prior reviews (`flutter-app-review-dev-crosscutting.md`) and remains true: dev-only destructive operations should be isolated.

**Recommendation:** Move dev reset into a dedicated `DevClinicSetupNotifier` (debug-gated), or assert `kDebugMode` at the top of the method.

---

## 7. Routing & Shell Interaction (Setup-Specific)

### 7.1 The setup wizard is not a route — by design, but with consequences

`auth_route_guard.dart:11` sets `clinicSetupRoute = AppRoutes.home`. A `needsClinicSetup` user is forced to `/home`, and the wizard is a dialog over `/home`. Consequences:

- The router **cannot** structurally prevent a `needsClinicSetup` user from "being on home" — that's the intended state. The gate is the dialog + soft-locked chrome, not the route.
- Because `/home`'s builder is `shellPlaceholderPage`, no real home content leaks today. But if a real home page is ever wired to `/home`, it would render behind the dialog (and after dismissal per §2.2). The architecture does not structurally protect a future home page.
- The `bootstrap` route (`AppRoutes.bootstrap`) is a dead redirect to `/home` (`router.dart:68`) — it exists only for the `isStaffProvisioningRoute`/`bootstrapStaffWizardInProgress` guard logic in `auth_route_guard.dart`. This is confusing indirection.

**Recommendation (forward-looking):** If a real home page is planned, either (a) introduce a real `/setup` route that renders the wizard as a page (not a dialog) while `needsClinicSetup`, and have the router force that route; or (b) keep the dialog model but make `AuthenticatedShell` render a blank/loading body (not the routed child) while `setupLocked` is true, so the dialog always sits over inert content. Today's placeholder hides this; the design should not rely on placeholders.

### 7.2 `isBootstrapWizardInProgress` feeds the route guard

`router.dart:199` passes `setup.isBootstrapWizardInProgress` (= `!completed`, `clinic_setup_notifier.dart:63`) into `AuthRouteGuard.resolveRedirect` as `bootstrapStaffWizardInProgress`. This is used to allow `/bootstrap` to stay open during wizard progress (`auth_route_guard.dart` bootstrap handling). But `isBootstrapWizardInProgress` defaults to `true` on every cold start (because `completed` defaults false), even when the backend says setup is done. Prior reviews (`flutter-app-review-routing.md:137`, `flutter-app-second-cycle-routing.md:39`) flagged this as open issue H2. The current `isSetupCompleteProvider` partially mitigates it by deferring to the session, but the `isBootstrapWizardInProgress` flag itself is still locally-derived and can diverge from JWT `setup_required` until `loadDraft`/`syncWithSession` reconcile.

**Recommendation:** Derive `isBootstrapWizardInProgress` from `auth.context.needsClinicSetup` (the authoritative source) rather than from the local `completed` flag, or remove the flag from the guard input entirely if the session-driven redirect already handles `/bootstrap`.

---

## 8. Summary of Findings by Severity

| # | Severity | Category | Finding | Location |
| --- | --- | --- | --- | --- |
| 3.1 | **HIGH** | Data loss | First-run bootstrap silently discards services, extra branches, and staff branch assignments | `clinic_setup_draft_mapper.dart:178,193`; `bootstrap_finish_setup_input.dart` |
| 2.1 | **HIGH** | Access risk | Cold-start `unknown`/`loading` window lets a deep link render `AuthenticatedShell` with enabled chrome | `auth_route_guard.dart:529–531`; `router.dart:212–214`; `authenticated_shell.dart:42` |
| 3.2 | **MEDIUM** | Security | Plaintext staff passwords persisted to SharedPreferences via `StaffDraft.toJson` | `setup_draft_models.dart:211`; `clinic_setup_notifier.dart:194` |
| 2.2 | **MEDIUM** | UX/State trap | Setup dialog dismissible; dismissed state strands user on locked home with no re-entry to setup | `clinic_setup_welcome_dialog.dart:21`; `clinic_setup_welcome_scope.dart:82,95–147` |
| 2.3 | **MEDIUM** | Defence-in-depth | `setupLocked` defaults to `false` on null context (should be `true`) | `authenticated_shell.dart:42` |
| 3.3 | **MEDIUM** | Race | `loadDraft` mid-await listener can resurrect a wiped draft after reset | `clinic_setup_notifier.dart:127,149–150,99–101` |
| 3.5 | **MEDIUM** | Correctness | Steady-state `completeSetup` is non-transactional; partial failure leaves inconsistent state | `clinic_setup_notifier.dart:431–511`; `persist_clinic_setup_draft.dart` |
| 2.4 | **LOW** (debug) | Access risk | Debug unauthenticated preview exposes whole shell route tree (mitigated by placeholder builder) | `router.dart:179–181`; `shell_nav_config.dart:62–69` |
| 5.1 | **MEDIUM** | Correctness/UX | `staffRoleOptions` (owner/nurse) mismatched to `StaffRole` enum (administrator/labStaff) | `setup_draft_models.dart:51–57`; `clinic_setup_draft_mapper.dart:153–162` |
| 5.7 | **MEDIUM** | Policy | Password reset allows weaker passwords (≥6, no letter) than creation (≥8 + letter) | `provisioning_notifier.dart:250–253`; `staff_password_validation.dart:13–18` |
| 4.1 | **LOW** | Invariant | `auth.context!` derefs rely on undocumented `isAuthenticated ⇒ context != null` invariant | `auth_route_guard.dart:409,417,429,436` |
| 3.4 | **LOW** | Re-entrancy | `completeSetup` has no notifier-level re-entrancy guard | `clinic_setup_notifier.dart:377` |
| 5.3 | **LOW** | Validation | Service price precision check uses floating-point multiplication | `setup_validation.dart:185–197` |
| 5.4 | **LOW** | i18n | `normalizeSetupNationalPhone` truncates to last 10 digits (Egypt-centric) while org settings are international | `clinic_setup_draft_mapper.dart:49–64` |
| 5.5 | **LOW** | Robustness | `isSetupDraftEntityId` stringly-typed heuristic for create-vs-update diffing | `setup_draft_models.dart:341–347` |
| 5.6 | **LOW** | UX | Cold start always signs out; admin may lose access to just-created accounts | `auth_session_provider.dart:117–122` |
| 5.8 | **LOW** | Semantics | `updateStaffUsername` reuses `canResetStaffPassword` for authorization | `provisioning_notifier.dart:297` |
| 4.3 | **LOW** | State | `_clinicSetupFlowRunning`/`_clinicSetupCelebrationShown` are module-level globals | `clinic_setup_welcome_scope.dart:14–17` |
| 4.2 | **LOW** | State | `refreshSessionContext` keeps stale context authorizing routes during refresh | `auth_session_provider.dart:279–298` |
| 4.4 | **LOW** | State | `syncWithSession` wipes in-progress draft without confirm | `clinic_setup_notifier.dart:157–179` |
| 6.1 | **Design** | Complexity | `ClinicSetupNotifier` 739-line god notifier merging two modes | `clinic_setup_notifier.dart` |
| 6.2 | **Design** | Layering | Setup notifier orchestrates settings/service_catalog/appointments features | `clinic_setup_notifier.dart` imports |
| 6.3 | **Design** | Dead code | `setup_page.dart` (legacy, unrouted, unreferenced) | `setup_page.dart` |
| 6.4 | **Design** | Dead code | `setup_dev_widgets.dart` (always returns `SizedBox.shrink()`) | `setup_dev_widgets.dart` |
| 6.5 | **Design** | Misplacement | `provisioning_notifier.dart` is steady-state staff management, not setup | `provisioning_notifier.dart` |
| 6.6 | **Design** | Redundancy | Duplicate org/branch fetch via FutureProviders vs. `hydrateFromBackend` | `clinic_setup_providers.dart`; `clinic_setup_notifier.dart:588` |
| 6.7 | **Design** | Redundancy | Two overlapping completion-celebration trigger paths | `clinic_setup_welcome_scope.dart:81–87,106–126` |
| 6.8 | **Design** | Dev/prod mix | `resetInstallationForDevelopment` is a public method on the production notifier | `clinic_setup_notifier.dart:551` |
| 7.1 | **Design** | Routing | Setup wizard is not a route; relies on placeholder home page + soft chrome lock | `auth_route_guard.dart:11`; `router.dart:68,78` |
| 7.2 | **Design** | Routing | `isBootstrapWizardInProgress` locally-derived, can diverge from JWT `setup_required` | `clinic_setup_notifier.dart:63`; `router.dart:199` |

---

## 9. Prioritized Recommendations

### 9.1 Must-fix (correctness & access safety)

1. **Bootstrap data loss (§3.1):** Extend `bootstrap_finish_setup` to accept all branches + services + staff branch assignments, OR restrict the first-run wizard UI to match the atomic RPC's actual capability. Always `hydrateFromBackend()` after success so the draft reflects truth.
2. **Cold-start access window (§2.1 + §2.3):** Redirect to `/login` while `auth.status` is `unknown`/`loading` for non-public routes; change `setupLocked` default to `?? true`.
3. **Plaintext passwords (§3.2):** Stop serializing `password` in `StaffDraft.toJson` / stop persisting it to SharedPreferences.
4. **Setup dialog dismissal dead-end (§2.2):** Make the setup dialog non-dismissible (and `PopScope`-guarded) while `needsClinicSetup` is true, or add a re-entry path after dismissal.
5. **Password policy consistency (§5.7):** Use the same validation for reset as for creation.

### 9.2 Should-fix (robustness & honesty)

6. **`loadDraft`/`syncWithSession` race (§3.3):** Guard the listener until initial load completes.
7. **Steady-state partial-failure handling (§3.5):** Hydrate from backend in the error path; communicate partial success.
8. **Role option alignment (§5.1):** Match `staffRoleOptions` to `StaffRole`.
9. **`completeSetup` re-entrancy guard (§3.4):** Early-return if `isSubmitting`.
10. **`auth.context!` invariant test (§4.1):** Add a test pinning `authenticated ⇒ context != null`.

### 9.3 Should-refactor (architecture)

11. **Split `ClinicSetupNotifier` (§6.1):** Separate bootstrap vs. steady-state notifiers.
12. **Extract a `ClinicSetupOrchestrator` (§6.2):** Remove cross-feature imports from the notifier; replace `invalidateAppointmentSurfaceProviders` with a shared invalidation event.
13. **Relocate `ProvisioningNotifier` (§6.5):** Move staff-account CRUD to settings/staff.
14. **Delete dead code (§6.3, §6.4):** Remove `setup_page.dart` and `setup_dev_widgets.dart`.
15. **Isolate dev reset (§6.8):** Move `resetInstallationForDevelopment` behind a debug-gated notifier.

### 9.4 Nice-to-have (polish)

16. **Service price validation on string form (§5.3).**
17. **Internationalize phone normalization (§5.4).**
18. **Replace `isSetupDraftEntityId` heuristic with an explicit `isDraft` flag on the model (§5.5).**
19. **Document the cold-sign-out behavior to the admin post-setup (§5.6).**
20. **Move flow-running/celebration flags to instance state or providers (§4.3).**

---

## 10. What Is Working Well

To keep the review balanced, the following aspects of the setup feature are architecturally sound and should be preserved:

- **Backend-authoritative gating.** Routing and the shell derive setup status from the JWT-backed `needsClinicSetup`, not local flags. The local `completed` flag cannot unlock the app. (`clinic_setup_notifier.dart:110–116`; `auth_session.dart:115–117`)
- **Fail-closed route guards.** `AuthRouteGuard.canAccess*` helpers default null context to setup-locked (`?? true`). (`auth_route_guard.dart`)
- **`canPerformBootstrapSetup` enforcement.** The wizard body refuses to render for non-bootstrap-admin accounts and the notifier re-checks before the RPC. (`clinic_setup_dialog_content.dart:29`; `clinic_setup_notifier.dart:383`)
- **Setup regression detection.** `_applyAuthenticatedContext` force-signs-out if a previously-setup-complete session regresses to `needsClinicSetup`, treating it as a consistency/security failure. (`auth_session_provider.dart:305–309`)
- **Atomic first-run RPC.** `bootstrap_finish_setup` creates org + first branch + staff in a single backend transaction (when the input mismatch in §3.1 is fixed, this is the right primitive).
- **Single-flight dialog presentation.** `_clinicSetupFlowRunning` prevents overlapping setup dialogs. (`clinic_setup_welcome_scope.dart:47,64,89`)
- **Draft persistence with safe defaults.** `fromJson` falls back to sensible defaults (Cairo timezone, EGP currency, default working days) so a corrupted prefs entry never crashes the wizard. (`setup_draft_models.dart`)
- **Refresh-listenable router wiring.** `refreshSignal` bumps on every `authSession`/`startupSession`/`clinicSetup` change, so redirects re-evaluate promptly. (`router.dart:27–39`)

---

*End of review. This document covers the `frontend/lib/features/setup/**` feature and its auth/session/shell integration surface as of 2026-07-11.*
