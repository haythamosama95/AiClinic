# Settings Feature — Second-Cycle Data Layer Review

**Scope:** `frontend/lib/features/settings/data/`, settings-related SQL migrations in `backend/supabase/migrations/`, and `frontend/test/**/settings/**` data-layer tests.  
**Review date:** 2026-07-05  
**Prior review:** [flutter-settings-feature-code-review.md](./flutter-settings-feature-code-review.md)  
**Method:** Re-read every in-scope file; re-verified first-cycle data-layer findings against current SQL and Dart; challenged RPC atomicity, tenancy, error semantics, and idle-store platform behavior.

---

## Executive Summary

The settings data layer is **structurally consistent** (shared `SettingsRpcInvoker` + `AppRpcInvoker` pattern, RLS reads, RPC mutations) but retains **one security-critical backend defect** and several **contract landmines** that will surface once settings UI ships partial-update forms.

| Severity | Count | First-cycle status |
|----------|-------|-------------------|
| **Critical** | 1 | 1 confirmed still present |
| **High** | 6 | 4 confirmed still present, 0 fixed, 1 nuanced, 1 new |
| **Medium** | 11 | 8 confirmed still present, 0 fixed, 0 invalidated, 3 new |

### Top 3 findings

1. **C3 (Critical):** `update_role_permissions` SQL still applies early iterations then `RETURN`s `rpc_error` mid-loop — partial permission commits on batch failure. Dart repo has no client-side guard; notifier refetch on failure masks inconsistency.
2. **H7 (High):** `updateBranch` omits `p_code` when `code` is null, but SQL sets `code = NULLIF(trim(p_code), '')` (not `COALESCE`) — partial field updates **wipe branch codes**.
3. **H8 (High, nuanced):** `_loadUsernamesByStaffId` swallows all errors with no logging; combined with SQL returning an empty set on `FORBIDDEN`, missing usernames are indistinguishable from network/permission failures.

### First-cycle data-layer re-verification summary

| ID | Finding | Status |
|----|---------|--------|
| C3 | Batch `updateRolePermissions` not atomic | **CONFIRMED STILL PRESENT** |
| H6 | Validation in data repos, not domain | **CONFIRMED STILL PRESENT** |
| H7 | `updateBranch` clears `code` when omitted | **CONFIRMED STILL PRESENT** |
| H8 | `_loadUsernamesByStaffId` silent catch | **CONFIRMED STILL PRESENT** (see nuance in finding) |
| H9 | `RpcResult` in domain repository interfaces | **CONFIRMED STILL PRESENT** |
| M3 | Tenancy scoping inconsistency (`listBranches` vs `listStaff`) | **CONFIRMED STILL PRESENT** |
| M20 | No `primaryBranchId` ∈ `branchIds` client validation | **CONFIRMED STILL PRESENT** |
| M22 | `StateError` vs `RpcFailure` for local validation | **CONFIRMED STILL PRESENT** |
| M23 | Enrichment includes soft-deleted branches | **CONFIRMED STILL PRESENT** |
| M24 | Stale single migration hint for all settings RPCs | **CONFIRMED STILL PRESENT** |
| M25 | Web idle store catches only `Exception` | **CONFIRMED STILL PRESENT** |
| M26 | IO idle store non-atomic read-modify-write | **CONFIRMED STILL PRESENT** |

Out-of-scope first-cycle items (presentation C1/C2, app-layer H2/H5) were not re-opened here.

---

## Critical Issues

### C3. Batch `update_role_permissions` is not atomic — partial writes commit on mid-loop RPC error

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** Critical
- **Files:**
  - `backend/supabase/migrations/20260614100000_settings_code_review_fixes.sql` (lines 47–143)
  - `frontend/lib/features/settings/data/role_permissions_repository.dart` (lines 57–69)
  - `frontend/test/unit/settings/role_permissions_repository_test.dart` (no batch tests)
- **Evidence:**

SQL loops changes, performs `INSERT … ON CONFLICT DO UPDATE` and audit logging, then `RETURN public.rpc_error(...)` on validation failure **without** `RAISE EXCEPTION`:

```69:94:backend/supabase/migrations/20260614100000_settings_code_review_fixes.sql
  FOR v_change IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
    ...
    IF NOT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.permission_key = v_key
        AND rp.is_deleted = false
    ) THEN
      RETURN public.rpc_error('INVALID_PERMISSION', 'Permission key is not in the catalog.');
    END IF;
```

Earlier loop iterations have already executed `INSERT`/`UPDATE` and audit rows. PostgreSQL commits the outer transaction when the function returns successfully (even with `success: false` in the JSON payload).

Dart sends the full batch with no pre-validation or rollback compensation:

```57:69:frontend/lib/features/settings/data/role_permissions_repository.dart
  Future<void> updateRolePermissions(Iterable<PermissionMatrixChange> changes) async {
    final payload = [
      for (final change in changes)
        {'role': change.role.wireValue, 'permission_key': change.permissionKey.trim(), 'is_granted': change.isGranted},
    ];
    ...
    await invokeSettingsRpc('update_role_permissions', {'p_changes': payload});
  }
```

Migration comment claims “atomic batch” (`-- Finding 3: atomic batch role permission updates`) but implementation uses early `RETURN`, not transactional rollback. Backend test `settings_code_review_fixes.sql` only asserts batch **success**, not partial-failure rollback.

- **Why it is a problem:** Client and notifier treat batch save as all-or-nothing. Server can persist a subset of permission grants/revokes while returning failure.
- **Impact:** Security-relevant permission matrix may diverge from what the administrator believes they saved; retry can double-apply or fight partial state.
- **Recommended solution:** Pre-validate entire `p_changes` array before any writes, or replace mid-loop `RETURN public.rpc_error(...)` with `RAISE EXCEPTION` so the transaction rolls back. Add a backend test that asserts zero row changes when the Nth item fails. Add Dart repository tests for batch payload shape and failure semantics.

---

## High Priority Issues

### H7. `updateBranch` silently clears `code` when field is omitted

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:**
  - `frontend/lib/features/settings/data/branch_repository.dart` (lines 87–95)
  - `backend/supabase/migrations/20260528141000_branch_working_schedule_required.sql` (lines 229–232)
  - `frontend/test/unit/settings/branch_repository_test.dart` (tests empty string, not null omission)
- **Evidence:**

Dart omits `p_code` when `input.code` is null:

```87:95:frontend/lib/features/settings/data/branch_repository.dart
    final result = await invokeSettingsRpc('update_branch', {
      'p_branch_id': input.branchId,
      'p_name': name,
      'p_working_schedule': input.workingSchedule.toJson(),
      if (input.code != null) 'p_code': input.code!.trim(),
      ...
    });
```

SQL does **not** preserve existing `code` when `p_code` is null — unlike `address`/`phone`/`maps_url`:

```229:235:backend/supabase/migrations/20260528141000_branch_working_schedule_required.sql
  UPDATE public.branches b
  SET
    name = trim(p_name),
    code = NULLIF(trim(p_code), ''),
    address = COALESCE(NULLIF(trim(p_address), ''), b.address),
    phone = COALESCE(NULLIF(trim(p_phone), ''), b.phone),
    maps_url = COALESCE(NULLIF(trim(p_maps_url), ''), b.maps_url),
```

When `p_code` is omitted, `NULLIF(trim(NULL), '')` evaluates to `NULL`, clearing the column.

- **Why it is a problem:** `UpdateBranchInput` models `code` as optional for partial updates, but the backend contract treats omitted `p_code` as “set to NULL”.
- **Impact:** Any settings UI that updates name/schedule without re-sending `code` will wipe branch codes; duplicate-code constraints may break downstream flows.
- **Recommended solution:** Align SQL: `code = COALESCE(NULLIF(trim(p_code), ''), b.code)` when preserving omitted fields is intended, **or** require `p_code` on every update from Dart. Add boundary test: update name-only and assert `code` unchanged.

---

### H8. `_loadUsernamesByStaffId` swallows all exceptions with zero logging

- **First-cycle status:** **CONFIRMED STILL PRESENT** (with nuance below)
- **Severity:** High
- **Files:** `frontend/lib/features/settings/data/staff_admin_repository.dart` (lines 138–164)
- **Evidence:**

```138:164:frontend/lib/features/settings/data/staff_admin_repository.dart
  Future<Map<String, String>> _loadUsernamesByStaffId(List<String> staffIds) async {
    ...
    try {
      final rows = await _client.rpc('staff_login_usernames', params: {'p_staff_ids': staffIds});
      if (rows is! List) {
        return const {};
      }
      ...
      return map;
    } catch (_) {
      return const {};
    }
  }
```

No `AppLog` call — unlike every `AppRpcInvoker` RPC path.

**Nuance:** SQL `staff_login_usernames` intentionally returns an empty result set (not an error) when the caller lacks `settings.manage_staff`:

```12:19:backend/supabase/migrations/20260614100000_settings_code_review_fixes.sql
  BEGIN
    PERFORM auth_internal.assert_permission('settings.manage_staff');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE = 'P0003' OR SQLERRM = 'FORBIDDEN' THEN
        RETURN;
      END IF;
```

So permission denial is **by design** indistinguishable from “no usernames” at the repo layer. The Dart `catch (_)` still hides true failures (network, timeout, malformed response).

- **Why it is a problem:** Cross-feature consumers (e.g. appointments calling `listStaff`) get staff rows without usernames and no signal whether enrichment failed vs. was denied.
- **Impact:** Silent degradation; debugging production “missing usernames” requires backend logs; unit tests cannot detect regression in enrichment.
- **Recommended solution:** Log at `AppLog.warning` before fallback; narrow `catch` to transport errors. Consider returning a sealed enrichment result (`success` / `denied` / `failed`) so presentation can differentiate. Add repository test asserting log on RPC throw.

---

### H6. Business-rule validation lives in the data layer, not domain

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:**
  - `frontend/lib/features/settings/data/branch_repository.dart` (lines 54–60, 80–85)
  - `frontend/lib/features/settings/data/organization_repository.dart` (lines 42–47)
  - `frontend/lib/features/settings/data/staff_admin_repository.dart` (lines 167–182)
  - `frontend/lib/features/settings/domain/usecases/*.dart` (one-line pass-throughs)
- **Evidence:** Repos throw `RpcFailure(INVALID_INPUT)` for empty name/branch lists; use cases delegate without validation. Domain use-case directory has **zero** unit tests; validation is only exercised via data-layer tests (`branch_repository_test.dart`, `staff_admin_repository_test.dart`, `organization_repository_test.dart`).
- **Why it is a problem:** Domain invariants are coupled to Supabase implementations; alternate repository impls or direct interface mocks skip rules.
- **Impact:** Rules drift across call sites; cannot unit-test business rules without pulling in data layer.
- **Recommended solution:** Move validation into domain input types or use-case `call()` methods; keep repos as thin wire adapters.

---

### H9. `RpcResult` / `RpcFailure` leak through domain repository interfaces into data implementations

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** High
- **Files:**
  - `frontend/lib/features/settings/domain/repositories/branch_repository.dart` (lines 15–16)
  - `frontend/lib/features/settings/domain/repositories/staff_admin_repository.dart` (lines 12–13)
  - `frontend/lib/features/settings/data/branch_repository.dart` (lines 101–108)
  - `frontend/lib/features/settings/data/staff_admin_repository.dart` (lines 197–205)
- **Evidence:**

Domain interfaces expose `Future<RpcResult>` for lifecycle mutations. Implementations call `invokeSettingsRpc`, which **throws** `RpcFailure` on `success: false` — the returned `RpcResult` is always successful when not thrown:

```101:108:frontend/lib/features/settings/data/branch_repository.dart
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) {
    return invokeSettingsRpc('set_branch_active', {'p_branch_id': branchId, 'p_is_active': isActive});
  }
```

Boundary tests only assert `.success` on happy paths (`branch_repository_boundary_test.dart` line 157–158).
- **Why it is a problem:** Callers cannot rely on return value for error detection; domain layer depends on `core/rpc` transport types.
- **Impact:** Misleading API contract; new callers may check `.success` and miss failures that were thrown, or catch inconsistently.
- **Recommended solution:** Domain interfaces return `Future<void>`; map `RpcFailure` to a domain failure type at the data boundary only.

---

### H10 (NEW). `updateRolePermissions` batch lacks empty-key pre-validation present on singular path

- **First-cycle status:** **NEW** (related to C3)
- **Severity:** High
- **Files:** `frontend/lib/features/settings/data/role_permissions_repository.dart` (lines 40–48 vs 57–69)
- **Evidence:**

Singular `updateRolePermission` rejects blank keys with `StateError` before RPC:

```45:48:frontend/lib/features/settings/data/role_permissions_repository.dart
    final key = permissionKey.trim();
    if (key.isEmpty) {
      throw StateError('Permission key is required.');
    }
```

Batch path trims but never rejects empty keys — they are sent to the server:

```59:62:frontend/lib/features/settings/data/role_permissions_repository.dart
    final payload = [
      for (final change in changes)
        {'role': change.role.wireValue, 'permission_key': change.permissionKey.trim(), 'is_granted': change.isGranted},
    ];
```

Combined with C3, valid changes earlier in the array commit before the server returns `INVALID_INPUT` for a later empty key.
- **Why it is a problem:** Inconsistent validation between singular and batch APIs; batch path enables partial server commits for preventable client errors.
- **Impact:** Same as C3 for malformed batch payloads; harder to diagnose because failure code is `INVALID_INPUT` not a local exception.
- **Recommended solution:** Reject empty keys in `updateRolePermissions` before RPC (prefer `RpcFailure(INVALID_INPUT)` per M22). Add repository unit test.

---

### H11 (NEW). Username enrichment failure is indistinguishable from permission denial for cross-feature callers

- **First-cycle status:** **NEW** (extends H8 nuance)
- **Severity:** High
- **Files:**
  - `backend/supabase/migrations/20260614100000_settings_code_review_fixes.sql` (lines 3–40)
  - `frontend/lib/features/settings/data/staff_admin_repository.dart` (`listStaff` enrichment, lines 48–56)
- **Evidence:** `listStaff` always calls `_loadUsernamesByStaffId` after the base query. Without `settings.manage_staff`, SQL returns `[]`; repo maps to `{}`. Appointments and other features import `listStaff` via settings use-case providers without guaranteeing that permission.
- **Why it is a problem:** Data layer presents a unified `StaffListItem` shape whether or not enrichment succeeded or was allowed.
- **Impact:** Queue/calendar UIs show staff without searchable usernames; no hook for UI to explain “insufficient permission to view logins”.
- **Recommended solution:** Gate enrichment on permission in use case or return optional `username` with explicit `UsernameAvailability` enum; document that `listStaff` enrichment requires `settings.manage_staff`.

---

## Medium Priority Issues

### M3. Repository scoping inconsistency (explicit org filter vs RLS-only)

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:**
  - `frontend/lib/features/settings/data/branch_repository.dart` (lines 28–32) — explicit `.eq('organization_id', organizationId)`
  - `frontend/lib/features/settings/data/staff_admin_repository.dart` (lines 24–25) — no org parameter; relies on `staff_members_select` RLS
  - `frontend/lib/features/settings/data/organization_repository.dart` (lines 29–30) — explicit org id
- **Evidence:** Sibling repositories use divergent tenancy strategies. RLS on `staff_members` is org-scoped via branch joins (`20260516100200_auth_rbac_rls.sql` lines 196–213), so correctness holds today, but the convention is undocumented in `SettingsRpcInvoker`.
- **Impact:** Future repo call with wrong mental model (passing org id to staff list) or RLS gap on a new table would not be caught by symmetry with branches.
- **Recommended solution:** Standardize: either always pass `organizationId` and filter explicitly, or document “RLS-scoped reads” in `SettingsRpcInvoker` and drop redundant org param from branches for consistency.

---

### M20. No cross-field validation: `primaryBranchId` vs `branchIds`

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `frontend/lib/features/settings/data/staff_admin_repository.dart` (lines 184–192)
- **Evidence:** `updateStaffMember` validates non-empty `branchIds` and non-empty `fullName` but never checks `primaryBranchId ∈ branchIds` when non-null. Server validates (`20260614100000_settings_code_review_fixes.sql` lines 228–231) but client sends invalid combinations over the wire.
- **Impact:** Extra round-trip; poorer error messages once UI ships.
- **Recommended solution:** Validate in `UpdateStaffMemberInput` or use case before RPC.

---

### M22. Inconsistent local-validation exception types (`StateError` vs `RpcFailure`)

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `frontend/lib/features/settings/data/role_permissions_repository.dart` (line 47) vs `branch_repository.dart` (lines 57–59)
- **Evidence:** `updateRolePermission` throws `StateError` for empty key; branch/org/staff repos throw `RpcFailure(INVALID_INPUT)`.
- **Impact:** Presentation/error mappers must handle multiple local failure types; boundary test expects `StateError` for empty key (`role_permissions_repository_boundary_test.dart` line 90–93).
- **Recommended solution:** Standardize on `RpcFailure` with `INVALID_INPUT` across all settings repos.

---

### M23. Staff-branch enrichment does not filter soft-deleted branches

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `frontend/lib/features/settings/data/staff_admin_repository.dart` (lines 99–103)
- **Evidence:**

```99:103:frontend/lib/features/settings/data/staff_admin_repository.dart
    final rows = await _client
        .from('staff_branch_assignments')
        .select('staff_member_id, branch_id, is_primary, branches(name)')
        .inFilter('staff_member_id', staffIds)
        .eq('is_deleted', false);
```

Assignment row `is_deleted` is filtered; joined `branches` row is not checked for `is_deleted`. Contrast `listBranches` which uses `.eq('is_deleted', false)`.
- **Impact:** Staff list may show labels for deleted branches if assignments were not cleaned up.
- **Recommended solution:** Use `branches!inner` with `.eq('branches.is_deleted', false)` or filter in Dart after fetch.

---

### M24. Stale migration hint for settings RPCs spanning six+ migrations

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `frontend/lib/features/settings/data/settings_rpc_repository.dart` (line 20)
- **Evidence:** Single hint `20260522100000_org_branch_management.sql` used for `delete_branch`, `update_role_permissions`, `staff_login_usernames`, etc., defined in later migrations (`20260613130000`, `20260614100000`, …).
- **Impact:** Misleading ops/debug messages when newer RPCs are missing.
- **Recommended solution:** Per-function hint map or generic “apply settings migrations through `<latest>`”.

---

### M25. Web idle-timeout store only catches `Exception`, not `Error`

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `frontend/lib/features/settings/data/idle_timeout_preferences_store_web.dart` (lines 16–18)
- **Evidence:**

```16:18:frontend/lib/features/settings/data/idle_timeout_preferences_store_web.dart
  } on Exception catch (error) {
    AppLog.warning('settings.idle_timeout.load_failed reason=${error.runtimeType}');
    return IdleTimeoutConfig.defaultDuration;
```

IO loader catches `IOException` and `FormatException` but not `Error` either; web is narrower than typical defensive parsing.
- **Impact:** Corrupt `SharedPreferences` state can throw `TypeError` and crash auth bootstrap instead of falling back to default.
- **Recommended solution:** Widen to `catch (error, stack)` on load paths for both platforms; log and return default.

---

### M26. Non-atomic read-modify-write race in IO idle-timeout store

- **First-cycle status:** **CONFIRMED STILL PRESENT**
- **Severity:** Medium
- **Files:** `frontend/lib/features/settings/data/idle_timeout_preferences_store_io.dart` (lines 38–56)
- **Evidence:** `saveIdleDuration` reads full JSON, merges one key, writes entire file with no lock or atomic rename. Concurrent saves (see first-cycle H5 in application layer) can interleave.
- **Impact:** Lost updates to `clinic-settings.json` if other keys are added later; last writer wins on `idle_timeout_minutes`.
- **Recommended solution:** Serialize writes (mutex/isolated provider); write to temp file + rename; or use platform key-value store on desktop.

---

### M27 (NEW). IO `saveIdleDuration` has no error handling or logging

- **First-cycle status:** **NEW**
- **Severity:** Medium
- **Files:** `frontend/lib/features/settings/data/idle_timeout_preferences_store_io.dart` (lines 38–56)
- **Evidence:** `loadIdleDuration` catches `IOException`/`FormatException` and logs; `saveIdleDuration` propagates write failures raw with only a success `AppLog.fine`.
- **Impact:** Disk-full or permission errors bubble to notifiers unlogged; asymmetric with load path.
- **Recommended solution:** Catch `IOException`, log `AppLog.warning`, rethrow or return `Result` for notifier to surface.

---

### M28 (NEW). Invalid PostgREST rows silently dropped in all list/fetch parsers

- **First-cycle status:** **NEW**
- **Severity:** Medium
- **Files:**
  - `frontend/lib/features/settings/data/branch_repository.dart` (lines 44–48)
  - `frontend/lib/features/settings/data/staff_admin_repository.dart` (lines 37–41)
  - `frontend/lib/features/settings/data/role_permissions_repository.dart` (lines 30–35)
- **Evidence:** `fromRow` returning null causes silent skip (`if (item != null) items.add(item)`). Tests assert skipped bad rows (`branch_repository_test.dart` line 125–137) — behavior is intentional but hides schema drift.
- **Impact:** Partial lists without error signal if DB schema and domain parsers diverge.
- **Recommended solution:** Log skipped row count at warning level; optional strict mode for debug builds.

---

### M29 (NEW). `update_role_permissions` batch has zero repository-level tests

- **First-cycle status:** **NEW** (test gap tied to C3)
- **Severity:** Medium
- **Files:**
  - `frontend/test/unit/settings/role_permissions_repository_test.dart` — covers singular `updateRolePermission` only
  - `frontend/test/unit/settings/role_permissions_notifier_test.dart` — batch via notifier mock, not repo
  - No `idle_timeout_preferences_store_io` unit tests (web store tested in `idle_timeout_preferences_store_web_test.dart`)
- **Evidence:** `role_permissions_repository_test.dart` has no `updateRolePermissions` cases. `SettingsRpcTestClient` default payload for unknown RPCs is `{'success': true}` — batch path is unverified at repo boundary.
- **Impact:** C3/H10 regressions ship undetected; IO idle persistence untested on desktop.
- **Recommended solution:** Add repo tests for batch payload trimming, empty list no-op, empty-key rejection, and RPC error propagation. Add IO store tests mirroring web suite.

---

### M30. `createBranch` / `updateOrganization` throw `StateError` on missing IDs in success payload

- **First-cycle status:** **NEW** (related to M22)
- **Severity:** Medium
- **Files:**
  - `frontend/lib/features/settings/data/branch_repository.dart` (lines 71–74)
  - `frontend/lib/features/settings/data/organization_repository.dart` (lines 57–60)
- **Evidence:** RPC success with empty `data` throws `StateError` instead of `RpcFailure`/`ServerContractException`. Tested only for org (`organization_repository_test.dart` line 96–98).
- **Impact:** Callers expecting `RpcFailure` for all remote failures get unhandled `StateError`; inconsistent with other mutation paths.
- **Recommended solution:** Map to `RpcFailure('INVALID_RESPONSE', …)` at data boundary.

---

## RPC Error Handling & Platform Idle Store — Verification Notes

| Area | Finding |
|------|---------|
| **RPC success path** | `AppRpcInvoker.invokeRpc` parses `RpcResult`, throws `RpcFailure` on `success: false`, maps `PGRST202`/`42501` to `RPC_NOT_APPLIED`/`RPC_NOT_CONFIGURED` with migration hint. Verified in `settings_rpc_repository_test.dart`. |
| **RPC partial commit** | Only `update_role_permissions` identified as non-atomic; other settings RPCs use single-statement updates or fail before writes. |
| **Tenancy** | Mutations scope via JWT in SQL (`jwt_organization_id()`). Reads: branches/org explicit; staff/matrix rely on RLS. |
| **Idle store conditional import** | `idle_timeout_preferences_store.dart` correctly switches IO vs web via `dart.library.html`. Web has unit tests; IO has none. |
| **Caching** | No in-memory cache in data repos; each notifier read hits network/disk. |

---

## Recommended Fix Order (Data Layer)

1. **C3** — Fix SQL atomicity for `update_role_permissions`; add backend partial-failure test.
2. **H7** — Align `update_branch` code preservation (SQL or always send `p_code` from Dart).
3. **H10** — Batch empty-key validation in `role_permissions_repository.dart`.
4. **H8 / H11** — Logging + enrichment result semantics for `staff_login_usernames`.
5. **M26 / M27 / M25** — Harden idle-timeout stores (IO tests, save error handling, widen catch).
6. **H6 / H9 / M22** — Move validation inward; normalize error types at domain boundary.

---

*Second-cycle review: all 8 data-layer Dart files, 10+ settings SQL migrations, and 21 settings test files read. No first-cycle data-layer findings were fixed since the prior review.*
