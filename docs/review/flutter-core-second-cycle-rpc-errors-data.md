# Flutter Core Second-Cycle Review — RPC, Errors, Logging, Data & Utils

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/{rpc,errors,logging,data,utils}/` (9 files) + cross-file integration  
**Baseline:** [flutter-core-review-rpc-errors-data.md](flutter-core-review-rpc-errors-data.md), [flutter-core-code-review.md](flutter-core-code-review.md)  
**Method:** Re-read all 9 core files; grep usages of `AppRpcInvoker`, `UserErrorMapper`, `PaginatedListNotifier`, `RpcResult`, `*MessageForRpc`, bootstrap/provisioning/shifts repositories; verify first-cycle findings against current code.

---

## Summary

| Severity | First-cycle | Status | New this cycle |
|----------|-------------|--------|----------------|
| Critical | 1 | 0 fixed, 1 still open | 0 |
| High | 5 | 0 fixed, 4 still open, 1 partially fixed | 1 |
| Medium | 7 | 0 fixed, 7 still open | 4 |

**Verdict:** No material fixes landed since the first cycle. The RPC invoker pattern remains sound and is adopted by 12 repositories, but error UX is still fragmented (10+ feature mappers exist; most are unwired), transport/parse failures still bypass `RpcFailure`, PHI may appear in warning-level logs, and `PaginatedListNotifier` retains both race and offset defects with zero adopters.

---

## Critical Issues

### CR-01 — `PaginatedListNotifier.loadMore` can overwrite an in-flight `refresh`

| Field | Detail |
|-------|--------|
| **Severity** | Critical (latent — zero adopters) |
| **Category** | Race condition / async correctness |
| **Files** | `/home/haytham/Desktop/AiClinic/frontend/lib/core/data/paginated_list_notifier.dart` |
| **First-cycle status** | **STILL OPEN** — no generation token, no post-await guard |

**Evidence:**

```67:92:frontend/lib/core/data/paginated_list_notifier.dart
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true, clearLoadMoreError: true));

    try {
      final nextOffset = current.offset + current.limit;
      final page = await fetchPage(nextOffset, pageSize);
      state = AsyncData(
        PaginatedList<T>(
          items: [...current.items, ...page.items],
          ...
        ),
      );
    } catch (error) {
      state = AsyncData(current.copyWith(isLoadingMore: false, loadMoreError: error.toString()));
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
```

`grep` confirms no class `extends PaginatedListNotifier` outside the definition file.

**Why:** `loadMore` captures `current`, awaits `fetchPage`, then unconditionally assigns `AsyncData` with no monotonic generation check. A concurrent `refresh()` sets `AsyncLoading` mid-flight; stale `loadMore` completion overwrites it.

**Impact:** Stale merged pages or skipped loading indicator if adopted for patient/service catalog infinite scroll.

**Solution:** Add `_requestGeneration` incremented in `refresh()`/`build()`; ignore stale completions. Add unit tests simulating concurrent `refresh` + `loadMore`.

---

## High Priority Issues

### HP-01 — Feature `*MessageForRpc` mappers mostly unwired; `UserErrorMapper` dead

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Error UX / dead code |
| **Files** | `core/utils/user_error_mapper.dart`; `features/*/application/*_rpc_messages.dart`; presentation notifiers |
| **First-cycle status** | **PARTIALLY FIXED** — `permissionMessageForRpc` now wired in settings; core `UserErrorMapper` still dead; patients/appointments/billing/service-catalog/shifts/settings-org-branch-staff still unwired |

**Evidence — `UserErrorMapper` has zero imports:**

```
grep "import.*user_error_mapper" frontend/ → 0 matches (only self-reference in user_error_mapper.dart)
```

**Wired in production (`frontend/lib/`):**

| Mapper | Used in |
|--------|---------|
| `visitMessageForRpc` | `visit_documentation_notifier.dart` |
| `setupMessageForRpc` | `setup_notifier.dart` |
| `provisioningMessageForRpc` | `provisioning_notifier.dart` |
| `permissionMessageForRpc` | `role_permissions_notifier.dart` |

**Unwired (defined + tested, never imported in `lib/`):**

| Mapper | File |
|--------|------|
| `patientMessageForRpc` | `features/patients/application/patient_rpc_messages.dart` |
| `appointmentMessageForRpc` | `features/appointments/application/appointment_rpc_messages.dart` |
| `billingMessageForRpc` | `features/billing/application/billing_rpc_messages.dart` |
| `serviceCatalogMessageForRpc` | `features/service_catalog/application/service_catalog_rpc_messages.dart` |
| `organizationMessageForRpc` | `features/settings/application/settings_rpc_messages.dart` |
| `branchMessageForRpc` | same |
| `staffMessageForRpc` | same |
| `shiftMessageForRpc` | `features/shifts/application/shift_rpc_messages.dart` |

**Service editor rethrows without mapping:**

```188:193:frontend/lib/features/service_catalog/presentation/providers/service_editor_notifier.dart
    } on RpcFailure catch (error) {
      if (error.code == 'STALE_SERVICE_BRANCH') {
        await reloadDetail();
      }
      state = AsyncData(current.copyWith(isSaving: false));
      rethrow;
```

**Invoice editor maps only stale, rethrows rest:**

```85:90:frontend/lib/features/billing/presentation/providers/invoice_editor_notifier.dart
    } on RpcFailure catch (error) {
      state = AsyncData(current);
      if (error.code == 'STALE_INVOICE') {
        throw const InvoiceStaleException();
      }
      rethrow;
```

**Why:** Parallel mapper strategy built per feature; only setup/visits/provisioning/settings-permissions connected them to UI.

**Impact:** Users see `RpcFailure(CODE): raw server message`, `error.result.errorMessage`, or `error.toString()` for codes like `STALE_PATIENT`, `DUPLICATE_NAME`, `SCHEDULE_CONFLICT`, `shift_overlap`.

**Solution:** Wire each feature notifier/form to its `*MessageForRpc`, or delete `UserErrorMapper` and add a thin delegating registry. Add integration tests asserting mapped strings reach UI state.

---

### HP-02 — `AppRpcInvoker` leaves transport/parse errors unmapped

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Error handling |
| **Files** | `core/rpc/app_rpc_invoker.dart`; all 12 `AppRpcInvoker` repositories |
| **First-cycle status** | **STILL OPEN** |

**Evidence:**

```19:74:frontend/lib/core/rpc/app_rpc_invoker.dart
  Future<RpcResult> invokeRpc(...) async {
    try {
      ...
      final result = RpcResult.fromDynamic(raw);  // can throw FormatException
      ...
    } on AuthException catch (error) { ... }
    on PostgrestException catch (error) { ... }
  }  // no catch-all
```

`RpcResult.fromDynamic` throws on unrecognized payloads:

```35:35:frontend/lib/core/rpc/rpc_result.dart
    throw FormatException('Unrecognized rpc_result payload: $raw');
```

Visit documentation still falls through to `error.toString()` for non-`RpcFailure`:

```452:456:frontend/lib/features/visits/presentation/providers/visit_documentation_notifier.dart
    } catch (error) {
      ...
      errorMessage: error.toString(),
```

**Impact:** `FormatException`, `SocketException`, `TimeoutException`, `ClientException` reach UI as developer strings, potentially including raw server payload text.

**Solution:** Wrap `fromDynamic` → `RpcFailure(UNEXPECTED_RESPONSE)`. Catch-all for network errors → `NETWORK_ERROR`. Add `app_rpc_invoker_test.dart`.

---

### HP-03 — RPC rejection messages logged without PHI redaction

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Logging / privacy |
| **Files** | `core/rpc/app_rpc_invoker.dart`; `features/setup/data/bootstrap_repository.dart`; `features/setup/data/provisioning_repository.dart` |
| **First-cycle status** | **STILL OPEN** |

**Evidence — AppRpcInvoker logs full server message at warning:**

```33:36:frontend/lib/core/rpc/app_rpc_invoker.dart
        AppLog.warning(
          '$rpcLogDomain.rpc.rejected fn=$functionName code=${result.errorCode} '
          'message=${result.errorMessage}',
        );
```

**Bootstrap logs PostgREST message + details + catch-all detail:**

```172:193:frontend/lib/features/setup/data/bootstrap_repository.dart
        AppLog.warning(
          'bootstrap.rpc.rejected fn=$functionName code=${result.errorCode} '
          'message=${result.errorMessage}',
        );
      ...
      AppLog.warning(
        'bootstrap.rpc.postgrest_error fn=$functionName code=${error.code} '
        'message=${error.message} details=${error.details}',
      );
      ...
      AppLog.warning('bootstrap.rpc.error fn=$functionName reason=${error.runtimeType} detail=$error');
```

`AppLog._redactionPatterns` target param shapes (`p_full_name=…`) but not free-text server messages like `"Patient Ahmed Hassan already exists"`.

**Impact:** Warning-level logs in profile/release builds may contain patient-identifying validation text.

**Solution:** Log `code=` only at warning; full message at `fine` in debug with expanded free-text redaction. Bootstrap/provisioning: log `reason=${error.runtimeType}` only in catch-all.

---

### HP-04 — `PaginatedListNotifier` uses `offset + limit` instead of `offset + items.length`

| Field | Detail |
|-------|--------|
| **Severity** | High (latent) |
| **Category** | Pagination correctness |
| **Files** | `core/data/paginated_list_notifier.dart` |
| **First-cycle status** | **STILL OPEN** |

**Evidence:**

```31:31:frontend/lib/core/data/paginated_list_notifier.dart
  bool get hasMore => offset + items.length < totalCount;
```

```74:74:frontend/lib/core/data/paginated_list_notifier.dart
      final nextOffset = current.offset + current.limit;
```

`hasMore` and `nextOffset` use inconsistent formulas.

**Impact:** Skipped rows when backend returns short pages (soft deletes, races).

**Solution:** `nextOffset = current.offset + current.items.length` everywhere.

---

### HP-05 — Duplicate RPC invoker implementations diverge from `AppRpcInvoker`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Duplication / behavioral drift |
| **Files** | `core/rpc/app_rpc_invoker.dart`; `features/setup/data/bootstrap_repository.dart`; `features/setup/data/provisioning_repository.dart`; `features/shifts/data/shift_repository.dart` |
| **First-cycle status** | **STILL OPEN** |

**Evidence:** Bootstrap `_invoke` (~lines 157–194), provisioning `_invoke` (~143–173), shift `_invokeJsonRpc` (~243–277) reimplement log → call → parse/error-map.

| Concern | AppRpcInvoker | Bootstrap | Provisioning | Shifts |
|---------|---------------|-----------|--------------|--------|
| `AuthException` → `AUTH_ERROR` | Yes | No | No | Yes |
| `RpcResult` composite parsing | Yes | Yes | Yes | No (raw JSON) |
| Missing-function code | `RPC_NOT_APPLIED` | `RESET_NOT_APPLIED` | via helper | `RPC_NOT_APPLIED` |
| PostgREST catch-all → `RpcFailure` | Yes | Rethrows | Rethrows | Custom code extraction |
| Logs raw `error_message` | Yes | Yes | Yes | N/A (different path) |

**Impact:** Security/logging fixes must be applied in 4 places; drift already visible.

**Solution:** Migrate bootstrap/provisioning to `AppRpcInvoker` with feature hooks. Document shifts as deliberate JSON-RPC exception or add shared transport helper.

---

### SC2-H01 — Expanded unwired mapper inventory (settings + shifts)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Category** | Error UX (new finding) |
| **Files** | `features/settings/application/settings_rpc_messages.dart`; `features/shifts/application/shift_rpc_messages.dart` |
| **First-cycle status** | **NEW** — first cycle listed 4 unwired feature mappers; second cycle confirms 3 additional settings mappers + `shiftMessageForRpc` also unwired with zero unit tests |

**Evidence:** `grep organizationMessageForRpc|branchMessageForRpc|staffMessageForRpc|shiftMessageForRpc frontend/lib/` returns only definition files.

**Impact:** When settings org/branch/staff UI and shift management UI ship, they will inherit raw RPC strings unless wired proactively.

**Solution:** Wire mappers as settings/shift notifiers are built; add unit tests mirroring patients/billing pattern.

---

## Medium Priority Issues

### MP-01 — `RpcFailure` lives in `rpc_result.dart`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Architecture |
| **Files** | `core/rpc/rpc_result.dart` (lines 80–93) |
| **First-cycle status** | **STILL OPEN** — `RpcFailure` still co-located with DTO parsing |

**Solution:** Move to `core/errors/rpc_failure.dart`.

---

### MP-02 — Parallel failure models: `AppFailure` vs `RpcFailure` vs raw strings

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Architecture |
| **Files** | `core/errors/failures.dart`; `core/rpc/rpc_result.dart`; feature mappers |
| **First-cycle status** | **STILL OPEN** — `AppFailure.recoverable` still unused in consumers |

**Solution:** Introduce sealed `UserFacingError` mapped from both startup and runtime failures.

---

### MP-03 — `mapExceptionToFailure` exposes raw exception strings

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Startup error UX |
| **Files** | `core/errors/failures.dart` (lines 32–42) |
| **First-cycle status** | **STILL OPEN** |

```32:41:frontend/lib/core/errors/failures.dart
AppFailure mapExceptionToFailure(Object error) {
  ...
  return UnexpectedFailure(error.toString());
}
```

**Solution:** Fixed copy for unknown types; log details separately via `AppLog.warning`.

---

### MP-04 — `AppLog` redaction lacks RPC-path tests

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Test coverage |
| **Files** | `core/logging/app_log.dart`; `test/unit/core/app_log_test.dart` |
| **First-cycle status** | **STILL OPEN** — tests cover password/email/JWT only; no PHI param or RPC message policy tests |

**Solution:** Test each `_redactionPatterns` entry; add RPC logging policy tests.

---

### MP-05 — `_readSuccess` treats numeric `1` as failure

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Parsing correctness |
| **Files** | `core/rpc/rpc_result.dart` (lines 38–46) |
| **First-cycle status** | **STILL OPEN** |

Test confirms `0` → false but not `1` → true:

```79:81:frontend/test/unit/patients/rpc_result_extended_test.dart
    test('success 0 or other values parse as false', () {
      expect(RpcResult.fromDynamic({'success': 0}).success, isFalse);
```

**Solution:** Extend `_readSuccess` for `1`/`0` or document wire format contract.

---

### MP-06 — `date_format_utils.dart` unused; features duplicate date formatting

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Duplication / dead code |
| **Files** | `core/utils/date_format_utils.dart`; `shifts/data/shift_repository.dart`; `service_catalog/data/service_catalog_repository.dart` |
| **First-cycle status** | **STILL OPEN** |

**Evidence:** Zero imports of `date_format_utils.dart` in `frontend/lib/`.

Shift formats without `.toLocal()`:

```330:334:frontend/lib/features/shifts/data/shift_repository.dart
  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
```

Service catalog uses `.toLocal()`:

```546:551:frontend/lib/features/service_catalog/data/service_catalog_repository.dart
  String _formatDate(DateTime date) {
    final local = date.toLocal();
```

**Solution:** Consolidate on `formatRpcDate(DateTime)` with explicit local/UTC policy.

---

### MP-07 — `PaginatedListNotifier.loadMoreError` uses `error.toString()`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Error UX |
| **Files** | `core/data/paginated_list_notifier.dart` (line 85) |
| **First-cycle status** | **STILL OPEN** |

**Solution:** Map through feature delegate or `UserErrorMapper` before storing.

---

### SC2-M01 — `AsyncValue.guard` list notifiers surface unmapped errors

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Error UX (new) |
| **Files** | `patient_list_notifier.dart`; `invoice_list_notifier.dart`; `service_catalog_list_notifier.dart`; `billing_settings_notifier.dart` |
| **First-cycle status** | **NEW** |

All use `AsyncValue.guard` without mapping `RpcFailure` to user copy. When UI binds `AsyncError`, users see `error.toString()` (e.g. `RpcFailure(INVALID_INPUT): …`).

**Solution:** Map in notifier catch or use `.guard` with custom error transformer.

---

### SC2-M02 — `UserErrorMapper` fallback would log raw error at warning

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Logging (latent — mapper dead) |
| **Files** | `core/utils/user_error_mapper.dart` (line 26) |
| **First-cycle status** | **NEW** |

```26:27:frontend/lib/core/utils/user_error_mapper.dart
    AppLog.warning('unhandled_error type=${error.runtimeType} error=$error');
```

If wired, unhandled errors log full object at warning — contradicts HP-03 policy.

**Solution:** Log `reason=${error.runtimeType}` only; remove or fix before wiring.

---

### SC2-M03 — `dev_clinic_seed_notifier` prefers raw server message over mapper

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Error UX (new) |
| **Files** | `app/shell/dev/dev_clinic_seed_notifier.dart` (lines 96–101) |
| **First-cycle status** | **NEW** |

```96:101:frontend/lib/app/shell/dev/dev_clinic_seed_notifier.dart
    } on RpcFailure catch (error) {
      ...
      errorMessage: error.result.errorMessage ?? setupMessageForRpc(error),
```

Prefers unmapped server text when present.

**Solution:** Always use `setupMessageForRpc(error)`; fall back to server message only for unknown codes in mapper default branch.

---

### SC2-M04 — `_coerceData` silently swallows invalid JSON string data

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Category** | Parsing / silent failure (new — noted in first-cycle file notes, not indexed) |
| **Files** | `core/rpc/rpc_result.dart` (lines 64–74) |
| **First-cycle status** | **NEW** (elevated from file notes) |

```64:74:frontend/lib/core/rpc/rpc_result.dart
      try {
        final decoded = jsonDecode(trimmed);
        ...
      } on FormatException {
        return null;
      }
```

**Impact:** Malformed JSON in `data` column returns `success=true` with `data=null`, masking server bugs.

**Solution:** Log at `fine` or throw `RpcFailure(UNEXPECTED_RESPONSE)` when JSON string decode fails on non-empty input.

---

## Cross-File Validation Matrix (second cycle)

| From → To | Status | Notes |
|-----------|--------|-------|
| `RpcResult` → `RpcFailure` | OK | Thrown when `success == false` |
| `AppRpcInvoker` → `UserErrorMapper` | Not connected | Transport errors bypass both |
| `RpcFailure` → feature mappers | Partial | 5/13 mapper families wired |
| `UserErrorMapper` | Dead | Zero imports |
| `PaginatedListNotifier` → error mapping | Missing | Uses `toString()` |
| `AppLog` → RPC errors | Risk | Server messages logged verbatim at warning |
| Bootstrap/provisioning → `AppRpcInvoker` | Divergent | Duplicate invoke logic |
| `copyWithSentinel` → domain models | OK | 10 models, consistent usage |
| `date_format_utils` → features | Dead | Shifts/catalog use private `_formatDate` |

---

## Consolidation Summary

**First-cycle findings (all verified against current code):**

- **CR-01** — STILL OPEN
- **HP-01** — PARTIALLY FIXED (`permissionMessageForRpc` wired; 8 mapper families still unwired; `UserErrorMapper` dead)
- **HP-02** — STILL OPEN
- **HP-03** — STILL OPEN
- **HP-04** — STILL OPEN
- **HP-05** — STILL OPEN
- **MP-01** — STILL OPEN
- **MP-02** — STILL OPEN
- **MP-03** — STILL OPEN
- **MP-04** — STILL OPEN
- **MP-05** — STILL OPEN
- **MP-06** — STILL OPEN
- **MP-07** — STILL OPEN

**New second-cycle findings:**

- **SC2-H01** — Expanded unwired mapper inventory (settings org/branch/staff + shifts)
- **SC2-M01** — `AsyncValue.guard` list notifiers surface unmapped errors
- **SC2-M02** — `UserErrorMapper` fallback logs raw error (latent)
- **SC2-M03** — Dev seed notifier prefers raw server message
- **SC2-M04** — `_coerceData` silent JSON parse failure

**Recommended priority:** (1) Fix `AppRpcInvoker` catch-all + logging policy (HP-02, HP-03), (2) Wire existing mappers into presentation (HP-01, SC2-H01), (3) Fix or delete `PaginatedListNotifier` before adoption (CR-01, HP-04, MP-07), (4) Consolidate duplicate RPC invokers (HP-05).

[REDACTED]
