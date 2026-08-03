# Settings Feature — Second-Cycle Presentation & Application Review

**Scope:** `frontend/lib/features/settings/presentation/` (providers, models), `frontend/lib/features/settings/application/` (`idle_timeout_settings_notifier`, `settings_rpc_messages`), related notifier/application tests under `frontend/test/**/settings/**`, and settings UI consumer grep across the app.

**Review date:** 2026-07-05  
**Prior review:** [flutter-settings-feature-code-review.md](./flutter-settings-feature-code-review.md)  
**Method:** Re-read every in-scope file; trace notifier lifecycles, async correctness, race conditions, auth integration, and Riverpod provider disposal; re-verify first-cycle presentation/application findings.

---

## Executive Summary

### Verdict: **Presentation layer remains unwired scaffolding with confirmed correctness bugs — do not ship settings UI without fixing reload/save async handling and concurrency guards**

All three first-cycle **Critical** presentation bugs (C1 `StaffListNotifier.reload`, C2 `RolePermissionsNotifier.saveChanges` post-mutation failure handling) remain unfixed. **High** concurrency and unwiring risks (H4, H5) also remain. This pass adds **new** race and authorization-consistency findings in tab visibility, `discardChanges` during save, and duplicated idle-timeout loading.

| Severity | Count (this pass) | New vs re-verified |
|----------|-------------------|--------------------|
| **Critical** | 2 | 2 re-verified (unchanged) |
| **High** | 5 | 3 re-verified + 2 new |
| **Medium** | 11 | 6 re-verified + 5 new |

### Top 3 findings

1. **C1 — `StaffListNotifier.reload()` still resolves before fetch completes** (CONFIRMED): callers cannot await a fresh list.
2. **C2 — `RolePermissionsNotifier.saveChanges()` still reverts a successful save when post-mutation work fails** (CONFIRMED): permissions persist server-side while UI shows failure and the pre-save matrix.
3. **H5 — `IdleTimeoutSettingsNotifier` still has no `isSaving` concurrency guard** (CONFIRMED): overlapping preset/custom saves can race read-modify-write on disk and produce wrong timeout values.

---

## First-Cycle Re-Verification (Presentation & Application)

| First-cycle ID | Finding | Status | Notes |
|----------------|---------|--------|-------|
| **C1** | `StaffListNotifier.reload()` completes before fetch | **CONFIRMED STILL PRESENT** | Unchanged implementation |
| **C2** | `saveChanges` reverts on `reloadContext()` failure | **CONFIRMED STILL PRESENT** | Also applies to post-RPC refetch failure (same `catch` block) |
| **C3** | Batch `updateRolePermissions` not atomic | **CONFIRMED STILL PRESENT** (nuanced) | Root cause is SQL/data layer; presentation **masks** partial server state on `RpcFailure` by refetching and syncing `workingMatrix` to `savedMatrix` |
| **H4** | Settings presentation unwired | **CONFIRMED STILL PRESENT** (nuanced) | `idleTimeoutSettingsProvider` is consumed only by `app.dart` bootstrap; all `/settings/*` routes remain `uiPendingPlaceholder`; no widget reads `staffListProvider`, `rolePermissionsProvider`, `clinicSetup*`, or `SettingsTabs` |
| **H5** | `IdleTimeoutSettingsNotifier` no `isSaving` guard | **CONFIRMED STILL PRESENT** | `_persistAndApply` never checks `current.isSaving` |
| **M4** | Non-reactive `ref.read(authSessionProvider)` | **CONFIRMED STILL PRESENT** | `StaffListNotifier` and `RolePermissionsNotifier` snapshot auth once in `build()` |
| **M9** | `SettingsTabs` unused | **CONFIRMED STILL PRESENT** | `SettingsTabBar` referenced in doc comment does not exist; zero imports |
| **M11** | `clinicSetup*` skip permission gating | **CONFIRMED STILL PRESENT** | No `AuthRouteGuard` checks before fetch |
| **M12** | `discardChanges()` missing `isSaving` guard | **CONFIRMED STILL PRESENT** | `setLocalGrant` blocks during save; `discardChanges` does not |
| **M13** | Dead org/branch/staff RPC mappers | **CONFIRMED STILL PRESENT** | Only `permissionMessageForRpc` is called |
| **M14** | Application/presentation import `app/providers/auth_session_provider.dart` | **CONFIRMED STILL PRESENT** | All notifiers + `SettingsTabs.visibleFor` depend on app composition root |
| **M16** | Idle-timeout loading duplicated | **CONFIRMED STILL PRESENT** | `IdleTimeoutSettingsNotifier.build()` and `AuthSessionNotifier._enableIdleWithPersistedDuration` both load store and call `updateIdleDuration` |

---

## 1. Critical Issues

### C1. `StaffListNotifier.reload()` completes before data is fetched

- **First-cycle status:** CONFIRMED STILL PRESENT
- **Severity:** Critical
- **Files:** `presentation/providers/staff_list_notifier.dart`
- **Evidence:**

```31:34:frontend/lib/features/settings/presentation/providers/staff_list_notifier.dart
  Future<void> reload() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }
```

- **Why:** `ref.invalidateSelf()` schedules an async rebuild but does not await `future`. The returned `Future<void>` from `reload()` completes immediately while `listStaff` is still in flight.
- **Impact:** Pull-to-refresh or post-mutation callers that `await reload()` then read `staffListProvider` can observe `AsyncLoading` transitioning to stale `AsyncData`, or race with concurrent `reload()` calls (see M-new-3). Zero unit tests cover this notifier.
- **Recommended solution:** `ref.invalidateSelf(); await future;` and remove redundant manual `state = const AsyncLoading()` (invalidation already triggers loading). Add a regression test that awaits `reload()` and asserts populated data.

---

### C2. `RolePermissionsNotifier.saveChanges` reverts successful persistence on post-mutation failure

- **First-cycle status:** CONFIRMED STILL PRESENT (scope expanded)
- **Severity:** Critical
- **Files:** `presentation/providers/role_permissions_notifier.dart`
- **Evidence:**

```116:170:frontend/lib/features/settings/presentation/providers/role_permissions_notifier.dart
  Future<bool> saveChanges() async {
    final current = state.value;
    // ...
    try {
      await ref.read(updateRolePermissionsUseCaseProvider)(changes);

      final rows = await ref.read(fetchPermissionMatrixUseCaseProvider)();
      final matrix = PermissionMatrixView.fromRows(rows);
      state = AsyncData(
        RolePermissionsUiState(
          savedMatrix: matrix,
          workingMatrix: matrix,
          editable: true,
          saveMessage: 'Role permissions saved. Your session permissions were refreshed.',
        ),
      );

      await ref.read(authSessionProvider.notifier).reloadContext();
      // ...
      return true;
    } on RpcFailure catch (error) {
      // ...
    } catch (error) {
      AppLog.warning('settings.permissions.save.failed reason=${error.runtimeType}');
      state = AsyncData(
        current.copyWith(
          isSaving: false,
          errorMessage: 'Unable to save role permissions. Check connectivity and try again.',
        ),
      );
      return false;
    }
  }
```

- **Why:** `current` is captured at method entry (pre-save matrix). After RPC **and** refetch succeed, state is updated to the saved matrix. If `reloadContext()` **or** the post-RPC refetch (line 133) throws, the generic `catch` restores `current` — the **pre-save** snapshot — and returns `false`.
- **Impact:** Permissions are committed server-side; UI shows a generic failure, hides `saveMessage`, and displays the old matrix. Administrator may retry duplicate mutations. No test covers `reloadContext()` or refetch failure after successful RPC.
- **Recommended solution:** Split try/catch: (1) mutation + refetch in inner try; on success, commit UI state and return `true`. (2) Wrap `reloadContext()` in separate try/catch — on failure, keep post-save state, set a soft warning (e.g. “Saved; session refresh failed — reload the page”), still return `true`.

---

## 2. High Priority Issues

### H1. Entire settings presentation remains unwired (placeholders)

- **First-cycle status:** CONFIRMED STILL PRESENT (nuanced)
- **Severity:** High
- **Files:** `app/router.dart` (lines 148–184), all presentation providers, `presentation/models/settings_tab.dart`
- **Evidence:** Grep shows `staffListProvider`, `rolePermissionsProvider`, `clinicSetupOrganizationProvider`, `clinicSetupBranchesProvider`, and `SettingsTabs` have **no widget consumers**. Only `idleTimeoutSettingsProvider` is read — from `app.dart` bootstrap:

```29:32:frontend/lib/app/app.dart
    Future<void>.microtask(() async {
      // Load persisted idle timeout before bootstrap can restore an authenticated session.
      await ref.read(idleTimeoutSettingsProvider.future);
```

All `/settings/*` routes resolve to `uiPendingPlaceholder('Settings', state)`.
- **Why:** Four notifiers and a tab catalog ship without UI integration or widget-level tests.
- **Impact:** Latent bugs (C1, C2, H5, races below) cannot be caught in realistic user flows; large dead surface area increases merge risk.
- **Recommended solution:** Implement settings pages consuming existing notifiers, or quarantine behind a feature flag until UI lands. Wire `SettingsTabs.visibleFor` into a real tab bar.

---

### H2. `IdleTimeoutSettingsNotifier` has no concurrency guard on saves

- **First-cycle status:** CONFIRMED STILL PRESENT (H5)
- **Severity:** High
- **Files:** `application/idle_timeout_settings_notifier.dart`, `data/idle_timeout_preferences_store_io.dart`
- **Evidence:**

```77:83:frontend/lib/features/settings/application/idle_timeout_settings_notifier.dart
  Future<void> _persistAndApply(Duration duration) async {
    final current = state.value;
    if (current == null) {
      return;
    }

    state = AsyncData(current.copyWith(isSaving: true, clearError: true, clearSaveMessage: true));
```

No `if (current.isSaving) return;`. `selectPresetMinutes` and `saveCustomMinutes` both call `_persistAndApply` without serialization. IO store uses non-atomic read-merge-write (no file lock).
- **Why:** Rapid preset taps or custom input while a save is in flight produce last-write-wins on `clinic-settings.json`; error handler restores the **stale** `current` snapshot from method start (see M-new-4).
- **Impact:** Security-relevant idle-timeout duration may not match the user's last action; `isSaving` UI can flicker or show misleading errors.
- **Recommended solution:** Early-return when `current.isSaving`; optionally queue or debounce writes. Serialize IO store writes. Add concurrent-save regression test (gap noted in first-cycle review).

---

### H3. `discardChanges()` allowed during in-flight `saveChanges()`

- **First-cycle status:** CONFIRMED STILL PRESENT (M12 elevated)
- **Severity:** High
- **Files:** `presentation/providers/role_permissions_notifier.dart`
- **Evidence:**

```92:99:frontend/lib/features/settings/presentation/providers/role_permissions_notifier.dart
  void discardChanges() {
    final current = state.value;
    if (current == null || current.permissionDenied || !current.hasUnsavedChanges) {
      return;
    }

    state = AsyncData(current.copyWith(workingMatrix: current.savedMatrix, clearError: true, clearSaveMessage: true));
  }
```

Contrast `setLocalGrant` which blocks when `current.isSaving` (line 103). During `saveChanges`, `hasUnsavedChanges` remains `true` until the RPC completes.
- **Why:** User can reset the working matrix to pre-save values while the batch RPC is in flight.
- **Impact:** UI shows “discarded” state; when save completes, server state overwrites — confusing flash. If save subsequently fails, UI may not reflect what the user last edited.
- **Recommended solution:** Add `|| current.isSaving` to the early return in `discardChanges()`. Test discard-during-save is a no-op.

---

### H4. `RolePermissionsNotifier` masks partial batch RPC failure by syncing UI to server

- **First-cycle status:** CONFIRMED STILL PRESENT (C3 presentation aspect)
- **Severity:** High
- **Files:** `presentation/providers/role_permissions_notifier.dart` (RpcFailure handler), `data/role_permissions_repository.dart` (atomicity root cause)
- **Evidence:**

```147:159:frontend/lib/features/settings/presentation/providers/role_permissions_notifier.dart
    } on RpcFailure catch (error) {
      AppLog.warning('settings.permissions.save.rpc_failed code=${error.code}');
      final rows = await ref.read(fetchPermissionMatrixUseCaseProvider)();
      final matrix = PermissionMatrixView.fromRows(rows);
      state = AsyncData(
        RolePermissionsUiState(
          savedMatrix: matrix,
          workingMatrix: matrix,
          editable: true,
          isSaving: false,
          errorMessage: permissionMessageForRpc(error),
        ),
      );
      return false;
```

Existing test `'saveChanges refetches matrix on partial RPC failure'` asserts `workingMatrix == savedMatrix` and `hasUnsavedChanges == false` — encoding the masking behavior.
- **Why:** When the batch RPC fails mid-loop server-side (non-atomic SQL), some permission changes may have committed. Refetch + sync clears dirty state and shows an error, implying a clean rollback.
- **Impact:** Security-relevant grants may change while the administrator believes nothing was applied; they will not retry corrections.
- **Recommended solution:** Fix SQL atomicity (data layer). Until then, on batch failure keep `workingMatrix` as user intent, set `savedMatrix` from refetch, and show “Some changes may have been applied — review the matrix.”

---

### H5. Staff and role-permissions notifiers use non-reactive auth snapshots

- **First-cycle status:** CONFIRMED STILL PRESENT (M4 elevated)
- **Severity:** High
- **Files:** `presentation/providers/staff_list_notifier.dart`, `presentation/providers/role_permissions_notifier.dart` vs `presentation/providers/clinic_setup_providers.dart`
- **Evidence:**

```21:22:frontend/lib/features/settings/presentation/providers/staff_list_notifier.dart
  Future<StaffListUiState> build() async {
    final auth = ref.read(authSessionProvider);
```

```8:9:frontend/lib/features/settings/presentation/providers/clinic_setup_providers.dart
final clinicSetupOrganizationProvider = FutureProvider.autoDispose<OrganizationProfile?>((ref) async {
  final organizationId = ref.watch(authSessionProvider.select((session) => session.context?.organizationId));
```

- **Why:** `ref.read` snapshots auth once at provider creation. `clinicSetup*` correctly `watch`es `organizationId` and auto-dispose on scope exit.
- **Impact:** After `reloadContext()` (e.g. permission grant/revoke, branch switch, app resume in `app.dart` line 53), staff list and permission matrix retain stale data until manual `invalidate`/`reload`. Role change from admin → non-admin may still show editable matrix until rebuild.
- **Recommended solution:** `ref.watch(authSessionProvider.select(...))` on fields that gate fetch and `editable`. Align `autoDispose` policy across settings notifiers.

---

## 3. Medium Priority Issues

### M1. `clinicSetup*` providers fetch without permission gating

- **First-cycle status:** CONFIRMED STILL PRESENT (M11)
- **Severity:** Medium
- **Files:** `presentation/providers/clinic_setup_providers.dart`
- **Evidence:** Providers fetch when `organizationId != null` with no `AuthRouteGuard.canAccessOrganizationSettings` / `canAccessBranchManagement` check. Sibling notifiers gate in `build()`.
- **Impact:** Users with org context but without clinic-setup permissions may trigger RLS errors or see data other tabs would hide once UI ships.
- **Recommended solution:** Gate each provider behind the matching `AuthRouteGuard` check; return `null` / `[]` when denied.

---

### M2. `SettingsTabs.visibleFor` omits auth checks for Staff and Staff Roles tabs

- **First-cycle status:** NEW (extends first-cycle M2/M9)
- **Severity:** Medium
- **Files:** `presentation/models/settings_tab.dart`, `core/auth/auth_route_guard.dart`
- **Evidence:**

```44:46:frontend/lib/features/settings/presentation/models/settings_tab.dart
  static List<SettingsTabDefinition> visibleFor(AuthSessionState auth) {
    return [general, if (AuthRouteGuard.canAccessClinicSetup(auth)) clinicSetup, staff, staffRoles];
  }
```

`staff` and `staffRoles` are always included. Route guard uses `canAccessStaffManagement` and `canAccessPermissionMatrix` for sub-routes.
- **Impact:** Future tab bar will show tabs that redirect or error on navigation — inconsistent with clinic-setup gating pattern.
- **Recommended solution:** `if (AuthRouteGuard.canAccessStaffManagement(auth)) staff`, `if (AuthRouteGuard.canAccessPermissionMatrix(auth)) staffRoles`.

---

### M3. `StaffListUiState` conflates “permission denied” with “empty clinic”

- **First-cycle status:** NEW
- **Severity:** Medium
- **Files:** `presentation/providers/staff_list_notifier.dart`
- **Evidence:**

```22:25:frontend/lib/features/settings/presentation/providers/staff_list_notifier.dart
    if (!AuthRouteGuard.canAccessStaffManagement(auth)) {
      return const StaffListUiState(staff: []);
    }
```

`RolePermissionsNotifier` exposes `permissionDenied: true` for the analogous case (line 74).
- **Impact:** Future staff list UI cannot show “you don’t have access” vs “no staff yet” without duplicating guard logic.
- **Recommended solution:** Add `permissionDenied` (or `accessDenied`) to `StaffListUiState`, mirroring `RolePermissionsUiState`.

---

### M4. Concurrent `StaffListNotifier.reload()` calls are unguarded

- **First-cycle status:** NEW
- **Severity:** Medium
- **Files:** `presentation/providers/staff_list_notifier.dart`
- **Evidence:** No in-flight guard; each call sets `AsyncLoading` and calls `invalidateSelf()`.
- **Impact:** Double pull-to-refresh or overlapping post-mutation reloads can reorder completions; combined with C1, callers cannot reliably synchronize on the latest fetch.
- **Recommended solution:** Track `_reloadGeneration` or skip if `state.isLoading`; await `future` after invalidation (fixes C1).

---

### M5. `IdleTimeoutSettingsNotifier` error path restores stale pre-save snapshot

- **First-cycle status:** NEW (related to H2/H5)
- **Severity:** Medium
- **Files:** `application/idle_timeout_settings_notifier.dart`
- **Evidence:**

```94:100:frontend/lib/features/settings/application/idle_timeout_settings_notifier.dart
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isSaving: false,
          errorMessage: 'Could not save settings. Check disk permissions and try again.',
        ),
      );
    }
```

`current` is captured before `isSaving: true` and before a concurrent save may have updated `duration`.
- **Impact:** A failed save can revert the displayed duration to an older value even though disk/service hold a newer successful write from a overlapping call.
- **Recommended solution:** On failure, re-read from store or use latest `state.value` before applying error; guard concurrent saves (H2).

---

### M6. `saveCustomMinutes` invalid-input path ignores `isSaving`

- **First-cycle status:** NEW
- **Severity:** Medium
- **Files:** `application/idle_timeout_settings_notifier.dart`
- **Evidence:** Validation branch (lines 59–71) updates state without checking `current.isSaving`.
- **Impact:** Typing invalid custom minutes during an in-flight preset save can overwrite `isSaving`/message state.
- **Recommended solution:** `if (current.isSaving) return;` before validation branch.

---

### M7. Provider lifecycle inconsistency (`autoDispose` split)

- **First-cycle status:** CONFIRMED STILL PRESENT (first-cycle L2/L6)
- **Severity:** Medium
- **Files:** `presentation/providers/clinic_setup_providers.dart` vs `staff_list_notifier.dart`, `role_permissions_notifier.dart`, `application/idle_timeout_settings_notifier.dart`
- **Evidence:** `clinicSetup*` use `FutureProvider.autoDispose`; `staffListProvider`, `rolePermissionsProvider`, and `idleTimeoutSettingsProvider` use non-autoDispose `AsyncNotifierProvider`.
- **Impact:** Once UI wires settings into a shell, staff/permissions providers may retain subscriptions and cached fetches after leaving settings routes; clinic setup will not — inconsistent cache behavior.
- **Recommended solution:** Standardize on `autoDispose` for route-scoped settings providers; keep `idleTimeoutSettingsProvider` app-scoped (used at bootstrap).

---

### M8. Duplicated idle-timeout load at bootstrap

- **First-cycle status:** CONFIRMED STILL PRESENT (M16)
- **Severity:** Medium
- **Files:** `application/idle_timeout_settings_notifier.dart`, `app/providers/auth_session_provider.dart`, `app/app.dart`
- **Evidence:** `IdleTimeoutSettingsNotifier.build()` loads store and calls `updateIdleDuration`. `AuthSessionNotifier._enableIdleWithPersistedDuration` independently loads store and calls `updateIdleDuration` on auth enable.
- **Impact:** Race on cold start: whichever load completes last wins; brief wrong timeout window before convergence. Redundant disk I/O every sign-in.
- **Recommended solution:** Single canonical loader — auth session reads duration from `idleTimeoutSettingsProvider` (already preloaded in `app.dart`) instead of re-reading store.

---

### M9. Dead RPC message mappers for org/branch/staff mutations

- **First-cycle status:** CONFIRMED STILL PRESENT (M13)
- **Severity:** Medium
- **Files:** `application/settings_rpc_messages.dart`
- **Evidence:** `organizationMessageForRpc`, `branchMessageForRpc`, `staffMessageForRpc` have zero call sites; write-side notifiers were never built.
- **Impact:** When org/branch/staff edit UI is implemented, error mapping will be duplicated or forgotten.
- **Recommended solution:** Wire into forthcoming write notifiers or remove until needed.

---

### M10. Feature layers import app composition root for session

- **First-cycle status:** CONFIRMED STILL PRESENT (M14)
- **Severity:** Medium
- **Files:** All notifiers in presentation/application; `presentation/models/settings_tab.dart`
- **Evidence:** Direct `import 'package:ai_clinic/app/providers/auth_session_provider.dart'`.
- **Impact:** Settings feature cannot be tested or extracted without the full app provider graph; reinforces settings↔app coupling (first-cycle H2).
- **Recommended solution:** Narrow port interface in settings domain; bind in `app/` composition.

---

### M11. `StaffListNotifier` has zero unit tests

- **First-cycle status:** CONFIRMED STILL PRESENT (test gap)
- **Severity:** Medium
- **Files:** `presentation/providers/staff_list_notifier.dart`; missing `staff_list_notifier_test.dart`
- **Evidence:** Grep under `frontend/test` finds no `staffListProvider` / `StaffListNotifier` tests. C1 and auth-gating behavior are untested.
- **Impact:** Critical reload bug ships undetected; regression likely when UI wires pull-to-refresh.
- **Recommended solution:** Add tests for: permission-denied build, successful load, `reload()` await semantics, auth snapshot staleness after context change.

---

## Files Reviewed (Complete In-Scope Inventory)

| File | Role |
|------|------|
| `presentation/providers/staff_list_notifier.dart` | Staff list `AsyncNotifier` |
| `presentation/providers/role_permissions_notifier.dart` | Permission matrix editor notifier |
| `presentation/providers/clinic_setup_providers.dart` | Org profile + branch list `FutureProvider`s |
| `presentation/models/settings_tab.dart` | Tab catalog (unwired) |
| `application/idle_timeout_settings_notifier.dart` | Idle timeout preference notifier |
| `application/settings_rpc_messages.dart` | RPC → user message mappers |
| `test/unit/settings/role_permissions_notifier_test.dart` | Notifier tests (no reloadContext-failure case) |
| `test/unit/settings/idle_timeout_settings_notifier_test.dart` | Notifier tests (no concurrency case) |
| `test/unit/auth/auth_session_idle_duration_test.dart` | Cross-layer idle duration tests |
| `test/integration/settings/idle_timeout_integration_test.dart` | Service-level idle timeout (not notifier concurrency) |

**Cross-app consumers grep:** `idleTimeoutSettingsProvider` → `app/app.dart` only. No widget imports for other settings providers. All settings routes → `uiPendingPlaceholder` in `app/router.dart`.

---

## Recommended Fix Order (Presentation/Application)

1. **C1** — Await `future` after `invalidateSelf()` in `StaffListNotifier.reload()`.
2. **C2** — Decouple post-save UI commit from `reloadContext()` / refetch failure handling.
3. **H2** — Add `isSaving` guard and serialize idle-timeout writes.
4. **H3** — Block `discardChanges()` while `isSaving`.
5. **H5** — Reactive auth `watch` + aligned `autoDispose` for route-scoped providers.
6. **H1** — Wire UI or quarantine dead presentation code before GA.

---

*Second-cycle review: presentation & application layers only. Data/domain findings from the first review (H1 DIP, H3 shared kernel, H6 validation, H7 branch code, etc.) are out of scope here but remain open.*
