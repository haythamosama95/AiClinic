# Flutter Core Review — RPC, Errors, Logging, Data & Utils

**Date:** 2026-07-05  
**Scope:** `frontend/lib/core/{rpc,errors,logging,data,utils}/` (9 files)  
**Cross-check:** Feature integration under `frontend/lib/features/`, tests under `frontend/test/`

---

## Summary

The RPC stack follows a coherent pattern: repositories mix in `AppRpcInvoker`, parse PostgreSQL `rpc_result` composites via `RpcResult.fromDynamic`, and throw `RpcFailure` on business rejection. PostgREST migration/permission errors are normalized to `RPC_NOT_APPLIED` / `RPC_NOT_CONFIGURED`. `AppLog` provides structured, redacted logging used widely across auth, setup, and RPC paths.

However, the error-mapping story is fragmented and partially dead code. `UserErrorMapper` is never imported; four feature-level `*MessageForRpc` mappers (patients, appointments, billing, service catalog) exist but are only exercised in unit tests—not wired into presentation. `PaginatedListNotifier` is similarly unused. Meanwhile, setup/bootstrap/provisioning/shifts duplicate RPC invocation logic instead of reusing `AppRpcInvoker`, and several notifiers fall back to `error.toString()` for user-visible copy.

Logging redacts common secret/PHI *parameter* patterns but still emits raw RPC `error_message` values from the server, which may contain patient-identifying text. `PaginatedListNotifier` (if adopted) has a refresh/loadMore race and an offset calculation bug for partial pages.

**Top risks:** inconsistent user-facing errors, potential PHI in logs, uncaught transport/parse exceptions from `AppRpcInvoker`, and duplicated RPC infrastructure.

---

## Critical Issues

### CR-01 — `PaginatedListNotifier.loadMore` can overwrite an in-flight `refresh`

| Field | Detail |
|-------|--------|
| **Severity** | Critical (design defect; class currently has zero adopters) |
| **Files** | `frontend/lib/core/data/paginated_list_notifier.dart` |
| **Evidence** | `loadMore()` captures `current` then awaits `fetchPage` without a generation token. `refresh()` sets `state = const AsyncLoading()` mid-flight. When the stale `loadMore` completes, it unconditionally assigns `state = AsyncData(...)` (lines 76–82), overwriting the refreshed or loading state. |
| **Why** | No request-generation guard, cancellation, or `mounted`/equivalent check after the async gap. |
| **Impact** | If this base class is adopted for patient/service lists, rapid pull-to-refresh during pagination would show stale merged pages or skip the loading indicator entirely. |
| **Solution** | Add a monotonic `_requestGeneration` incremented in `refresh()`/`build()`; ignore `loadMore` completions when generation changed. Alternatively use `ref.onDispose` cancellation or Riverpod `@riverpod` keepAlive patterns. Add unit tests simulating concurrent `refresh` + `loadMore`. |

---

## High Priority Issues

### HP-01 — `UserErrorMapper` is dead code; feature mappers are not wired to UI

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `frontend/lib/core/utils/user_error_mapper.dart`; `frontend/lib/features/patients/application/patient_rpc_messages.dart`; `frontend/lib/features/appointments/application/appointment_rpc_messages.dart`; `frontend/lib/features/billing/application/billing_rpc_messages.dart`; `frontend/lib/features/service_catalog/application/service_catalog_rpc_messages.dart` |
| **Evidence** | `grep` for `import.*user_error_mapper` and `patientMessageForRpc`/`appointmentMessageForRpc`/`billingMessageForRpc`/`serviceCatalogMessageForRpc` in `frontend/lib/` returns **zero** presentation usages. Only `visitMessageForRpc`, `setupMessageForRpc`, and `provisioningMessageForRpc` are used in notifiers. `service_editor_notifier.dart` rethrows `RpcFailure` without mapping (lines 82–85, 194–196). |
| **Why** | Core utility was introduced as the canonical mapper, but features built parallel domain mappers and never connected them—or connected only visits/setup. |
| **Impact** | Users see raw server `error_message`, generic `"RpcFailure(CODE): …"` strings, or `error.toString()` instead of curated copy for codes like `STALE_PATIENT`, `SCHEDULE_CONFLICT`, `STALE_INVOICE`, `DUPLICATE_NAME`. Inconsistent UX and possible leakage of internal server wording. |
| **Solution** | Pick one strategy: (a) wire `UserErrorMapper` as a thin delegator to feature mappers by domain, or (b) delete `UserErrorMapper` and require each notifier to call its feature `*MessageForRpc`. Wire patients/appointments/billing/service-catalog notifiers and forms. Add integration tests asserting mapped strings reach UI state. |

---

### HP-02 — `AppRpcInvoker` leaves transport/parse errors unmapped

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `frontend/lib/core/rpc/app_rpc_invoker.dart`; all 14 `AppRpcInvoker` repositories |
| **Evidence** | `invokeRpc` catches only `AuthException` and `PostgrestException`. `RpcResult.fromDynamic(raw)` can throw `FormatException` (unrecognized payload). Network failures (`SocketException`, `TimeoutException`, `ClientException`) propagate uncaught. No final `catch` maps to `RpcFailure` or a transport failure type. |
| **Why** | Happy-path and PostgREST mapping were implemented; transport/serialization edge cases were deferred. |
| **Impact** | UI layers that catch `RpcFailure` miss these errors and fall through to generic `catch (error)` branches using `error.toString()`—e.g. `visit_documentation_notifier.dart:455`, `paginated_list_notifier.dart:85`. Users may see `"FormatException: Unrecognized rpc_result payload: …"` including raw server data. |
| **Solution** | Wrap `fromDynamic` in try/catch → `RpcFailure` with code `UNEXPECTED_RESPONSE`. Add catch-all for `SocketException`/`TimeoutException` → code `NETWORK_ERROR`. Mirror handling already present in `UserErrorMapper`. Add unit tests in `frontend/test/unit/core/`. |

---

### HP-03 — RPC rejection messages logged without PHI redaction

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `frontend/lib/core/rpc/app_rpc_invoker.dart` (lines 33–36); `frontend/lib/core/logging/app_log.dart`; `frontend/lib/features/setup/data/bootstrap_repository.dart` (lines 172–174); `frontend/lib/features/setup/data/provisioning_repository.dart` (lines 152–154) |
| **Evidence** | On `!result.success`, `AppLog.warning` logs `message=${result.errorMessage}`. Redaction patterns in `AppLog` target *request parameter* shapes (`p_full_name=…`, `p_phone=…`) but not free-text server messages like `"Patient Ahmed Hassan already exists"`. Bootstrap/provisioning also log `detail=$error` for caught exceptions. |
| **Why** | Redaction was designed for client-side log construction, not server-returned error text. |
| **Impact** | Profile/release logs via `developer.log` may contain patient names, phone fragments, or clinical details returned in RPC validation messages—HIPAA/privacy risk on shared developer machines or crash reporting pipelines. |
| **Solution** | Log only `code=${result.errorCode}` at warning level; move full message to `AppLog.fine` in debug builds with expanded redaction (names, phone patterns in free text). Never log `detail=$error` for unknown exceptions—log `reason=${error.runtimeType}` only (pattern already used in auth providers). Extend `_redactionPatterns` for common validation message shapes. |

---

### HP-04 — `PaginatedListNotifier` uses `offset + limit` instead of `offset + items.length`

| Field | Detail |
|-------|--------|
| **Severity** | High (latent; no current adopters) |
| **Files** | `frontend/lib/core/data/paginated_list_notifier.dart` (lines 31, 74–75) |
| **Evidence** | `hasMore` uses `offset + items.length < totalCount` but `loadMore` computes `nextOffset = current.offset + current.limit`. If a page returns fewer than `limit` items (partial last page mid-sequence, soft deletes, race), the next fetch skips records. |
| **Why** | Assumes every page is full except the last; `hasMore` and `nextOffset` use inconsistent formulas. |
| **Impact** | Missing rows in paginated lists when the backend returns short pages. |
| **Solution** | Use `nextOffset = current.offset + current.items.length` consistently. Document contract: `fetchPage` must return the requested `offset`/`limit` echo. Add tests for partial-page scenarios. |

---

### HP-05 — Duplicate RPC invoker implementations diverge from `AppRpcInvoker`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `frontend/lib/core/rpc/app_rpc_invoker.dart`; `frontend/lib/features/setup/data/bootstrap_repository.dart`; `frontend/lib/features/setup/data/provisioning_repository.dart`; `frontend/lib/features/shifts/data/shift_repository.dart` |
| **Evidence** | Bootstrap `_invoke` (lines 157–194), provisioning `_invoke` (lines 143–173), and shift `_invokeJsonRpc` (lines 243–277) reimplement log → call → parse/error-map. Shift repo uses raw JSON RPC (no `RpcResult` composite). Bootstrap uses different error codes (`RESET_NOT_APPLIED` vs `RPC_NOT_APPLIED`). Provisioning rethrows unmapped PostgREST errors; `AppRpcInvoker` wraps them in `RpcFailure`. |
| **Why** | Features predating or bypassing the shared mixin; shift backend API shape differs. |
| **Impact** | Bug fixes (AuthException mapping, migration hints, logging policy) must be applied in 4 places. Behavioral drift already visible: provisioning lacks `AuthException` handling; shift has custom `_extractShiftErrorCode`. |
| **Solution** | Migrate bootstrap/provisioning to `AppRpcInvoker` with feature-specific `migrationHint` and optional `onPostgrestException` hook for bootstrap-only codes. For shifts, either migrate DB to `rpc_result` composites or document shift as a deliberate exception with a shared lower-level `RpcTransport` helper. |

---

## Medium Priority Issues

### MP-01 — `RpcFailure` lives in `rpc_result.dart` (data + exception conflation)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/rpc/rpc_result.dart` (lines 80–93); `frontend/lib/core/errors/exceptions.dart` |
| **Evidence** | `RpcResult` is a parsed DTO; `RpcFailure implements Exception` is in the same file. Startup errors use `AppException` hierarchy in `exceptions.dart`; RPC errors use a separate type in the RPC module. |
| **Why** | Convenience at introduction time; `RpcFailure` wraps `RpcResult`. |
| **Impact** | Clean Architecture boundary blur—presentation/data both import `rpc_result.dart` for exception types. Harder to evolve error taxonomy without pulling in parsing code. |
| **Solution** | Move `RpcFailure` to `core/errors/rpc_failure.dart`. Keep `RpcResult` as pure data. Optionally extend `AppException` or introduce `DomainFailure` sealed class. |

---

### MP-02 — Parallel failure models: `AppFailure` vs `RpcFailure` vs raw strings

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/errors/failures.dart`; `frontend/lib/core/rpc/rpc_result.dart`; `frontend/lib/core/utils/user_error_mapper.dart`; feature `*MessageForRpc` files |
| **Evidence** | Startup uses `AppFailure` + `mapExceptionToFailure`. Runtime RPC uses `RpcFailure` thrown from repositories. Presentation variously uses feature mappers, `failure.message`, or `error.toString()`. `UserErrorMapper` returns bare `String`, not `AppFailure`. |
| **Why** | Startup shell and feature modules evolved independently. |
| **Impact** | No single presentation contract for error rendering (title, recoverable flag, message). `mapExceptionToFailure` uses `error.toString()` which includes exception type prefixes for unknown errors. |
| **Solution** | Define a sealed `UserFacingError { title, message, recoverable, code? }` mapped from both `AppFailure` and `RpcFailure`. Deprecate stringly-typed `errorMessage` fields where feasible. |

---

### MP-03 — `mapExceptionToFailure` exposes raw exception strings to UI

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/errors/failures.dart` (lines 32–42); `frontend/lib/app/providers/startup_session_provider.dart` |
| **Evidence** | `ConfigurationFailure(error.toString())`, `UnexpectedFailure(error.toString())`. `MissingDeploymentProfileException.toString()` returns message only, but generic errors expose `"Exception: …"` or file paths from underlying I/O exceptions. |
| **Why** | Quick mapping without user-facing copy layer. |
| **Impact** | Startup error screen may show implementation details (paths, stack-adjacent text) for unexpected failures. |
| **Solution** | Map known exceptions to fixed copy; use generic message for unknown types. Log details via `AppLog.warning` separately. |

---

### MP-04 — `AppLog.info` / `AppLog.warning` run in release without redaction tests for RPC paths

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/logging/app_log.dart`; `frontend/test/unit/core/app_log_test.dart` |
| **Evidence** | `_format` redaction applies to all levels, but tests cover only password/email/JWT (lines 8–16). No tests for PHI param patterns (`p_full_name=…`) or RPC error message redaction. `fine` is debug-only; `warning` is not. |
| **Why** | Redaction patterns added for auth; RPC logging path not tested. |
| **Impact** | Regressions in redaction regex could silently leak secrets in production profile builds. |
| **Solution** | Add tests for each `_redactionPatterns` entry. Consider running redaction in unit tests without `kDebugMode` guard by testing `_format` via `@visibleForTesting` export. |

---

### MP-05 — `RpcResult._readSuccess` treats PostgreSQL `'f'` and numeric truthy values inconsistently

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/rpc/rpc_result.dart` (lines 38–46) |
| **Evidence** | `'t'`/`'true'` → success; `'f'`/`'false'` → false (default). Integer `1` → false (test line 80 in `rpc_result_extended_test.dart`). Some PostgreSQL drivers return `1`/`0` for boolean composites. |
| **Why** | Defensive parsing handles strings; numeric booleans not considered. |
| **Impact** | If PostgREST ever returns `(1, data, null, null)` for success, RPC would be treated as failure and throw `RpcFailure` incorrectly. |
| **Solution** | Extend `_readSuccess` for `1`/`0` or document assumed wire format and add integration test against live Supabase composite. |

---

### MP-06 — `date_format_utils.dart` is unused; features duplicate date formatting

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/utils/date_format_utils.dart`; `frontend/lib/features/shifts/data/shift_repository.dart` (`_formatDate`); `frontend/lib/features/service_catalog/data/service_catalog_repository.dart` (`_formatDate`); `frontend/lib/features/billing/presentation/utils/billing_formatting.dart` |
| **Evidence** | No imports of `date_format_utils.dart` in `frontend/lib/`. Shifts and service catalog define private `_formatDate` with `.toLocal()`; core util has no `.toLocal()` on `formatDate(DateTime?)`. Billing uses `intl` `DateFormat`. |
| **Why** | Core util extracted but never adopted; features chose local-time handling independently. |
| **Impact** | Date strings may differ if UTC vs local conversion diverges across features (RPC params vs display). Dead code misleads contributors. |
| **Solution** | Consolidate on one module: `formatRpcDate(DateTime)` (local, `YYYY-MM-DD`) and `formatDisplayDate`. Remove duplicates or delete unused core util. |

---

### MP-07 — `PaginatedListNotifier.loadMoreError` uses `error.toString()`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/data/paginated_list_notifier.dart` (line 85); `frontend/lib/core/utils/user_error_mapper.dart` |
| **Evidence** | `loadMoreError: error.toString()` bypasses any user-message mapping layer. |
| **Why** | `UserErrorMapper` not integrated. |
| **Impact** | Load-more footer shows developer-oriented text for `RpcFailure`, `FormatException`, etc. |
| **Solution** | Map through `UserErrorMapper.mapToUserMessage(error)` or feature delegate before storing. |

---

## Low Priority Issues

### LP-01 — `RpcFailure.details` field is sparsely used

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `frontend/lib/core/rpc/rpc_result.dart`; `frontend/lib/features/shifts/data/shift_repository.dart` (line 274) |
| **Evidence** | `details` optional parameter set only in shift repo PostgREST mapping. Never read in presentation. |
| **Why** | Reserved for debugging; not propagated by `AppRpcInvoker`. |
| **Impact** | Dead field or inconsistent diagnostic data. |
| **Solution** | Remove or document as debug-only; log via `AppLog.fine` at throw site if needed. |

---

### LP-02 — `copyWithSentinel` requires verbose `identical()` checks at every call site

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `frontend/lib/core/utils/copy_with_sentinel.dart`; 8+ domain model files |
| **Evidence** | Pattern repeated identically across `patient_detail.dart`, `visit_detail.dart`, `auth_session.dart`, etc. |
| **Why** | Dart lacks built-in nullable field sentinel in `copyWith`. |
| **Impact** | Boilerplate; easy to forget sentinel on new nullable fields. |
| **Why acceptable** | Works correctly; widespread Dart pattern. |
| **Solution** | Optional: migrate to code-gen (`freezed`) or a small macro/codegen helper. Not urgent. |

---

### LP-03 — `formatDate` returns em dash `'—'` for null; billing uses different conventions

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `frontend/lib/core/utils/date_format_utils.dart` |
| **Evidence** | `formatDate(null)` → `'—'` (Unicode em dash). Billing/patients may use `'–'` or empty string in tables. |
| **Impact** | Minor visual inconsistency if util is adopted without audit. |
| **Solution** | Align with design system placeholder glyph when consolidating formatting. |

---

### LP-04 — `AppRpcInvoker` logs param keys but not values (good) — inconsistent with shift repo

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `frontend/lib/core/rpc/app_rpc_invoker.dart` (line 21); `frontend/lib/features/shifts/data/shift_repository.dart` (line 244) |
| **Evidence** | Both log only param key names at fine level—consistent and safe. |
| **Impact** | None currently; note for future logging additions. |
| **Solution** | Enforce "keys only" rule in code review checklist. |

---

## Clean Architecture Violations

### CA-01 — Presentation imports RPC infrastructure types directly

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | Multiple notifiers import `package:ai_clinic/core/rpc/rpc_result.dart` for `RpcFailure` (e.g. `service_editor_notifier.dart`, `visit_documentation_notifier.dart`, `invoice_editor_notifier.dart`) |
| **Evidence** | Presentation catches `RpcFailure` and inspects `.code` (e.g. `STALE_INVOICE`, `STALE_SERVICE_BRANCH`). |
| **Why** | No domain-level failure abstraction between repository and UI. |
| **Impact** | UI coupled to RPC wire format; swapping transport requires touching presentation. |
| **Solution** | Repositories/use cases throw domain exceptions (`StaleEntityException`, `DuplicatePatientException`). Map from `RpcFailure` in data layer only. |

---

### CA-02 — `PatientRpcFailure` extension in data layer encodes domain rules

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/features/patients/data/patient_rpc_failure.dart` |
| **Evidence** | `isDuplicateWarning`, `duplicateCandidates` parse RPC payload shape in data layer—acceptable—but consumed from `dev_clinic_seed_service.dart` and tests with no application-layer facade. |
| **Impact** | Domain/application boundary for duplicate-flow semantics is thin. |
| **Solution** | Move extension to `application/` or expose via use case returning sealed `PatientMutationResult`. |

---

### CA-03 — `exceptions.dart` and `failures.dart` serve only startup; runtime RPC errors bypass both

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/errors/exceptions.dart`; `frontend/lib/core/errors/failures.dart` |
| **Evidence** | `AppException` hierarchy covers deployment/startup only. Feature runtime errors never become `AppFailure`. |
| **Impact** | Two parallel error universes; core `errors/` module name implies completeness but covers ~10% of failures. |
| **Solution** | Rename to `startup_exceptions.dart` / `startup_failures.dart` or extend module to include RPC domain failures. |

---

## SOLID Violations

### SOLID-01 — Single Responsibility: `rpc_result.dart` parses, validates, and defines exception type

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `frontend/lib/core/rpc/rpc_result.dart` |
| **Evidence** | DTO parsing (`fromDynamic`, `_coerceData`) + `RpcFailure` exception in one file. |
| **Solution** | Split parse model from failure type (see MP-01). |

---

### SOLID-02 — Open/Closed: adding a new PostgREST error class requires editing multiple invokers

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_rpc_invoker.dart`, `bootstrap_repository.dart`, `shift_repository.dart`, etc. |
| **Evidence** | Bootstrap adds `RESET_SAFE_DELETE`, `RESET_DEPENDENCY_BLOCKED` by editing `_invoke`. Shifts add `_extractShiftErrorCode` list. |
| **Solution** | Strategy registry: `PostgrestErrorMapper` chain injected per feature. |

---

### SOLID-03 — Dependency Inversion: notifiers depend on concrete `RpcFailure` codes

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `service_editor_notifier.dart`, `invoice_editor_notifier.dart` |
| **Evidence** | `if (error.code == 'STALE_SERVICE_BRANCH')` and `if (error.code == 'STALE_INVOICE')` in presentation. |
| **Solution** | Use cases return `Result<T, DomainError>`; presentation reacts to domain error variants. |

---

## Code Duplication & Redundancy

| ID | Severity | Files | Evidence | Solution |
|----|----------|-------|----------|----------|
| DUP-01 | High | `app_rpc_invoker.dart`, `bootstrap_repository.dart`, `provisioning_repository.dart` | ~40 lines duplicated log/parse/throw | Single mixin + optional hooks |
| DUP-02 | Medium | `shift_repository.dart`, `service_catalog_repository.dart` | `_formatDate` / `_clientInputFailure` / `_assertNonEmpty` patterns | Shared `core/utils/rpc_params.dart` |
| DUP-03 | High | Feature `*MessageForRpc` × 6 + `UserErrorMapper` | Overlapping `FORBIDDEN`, `INVALID_INPUT`, `RPC_NOT_APPLIED` strings | Central registry with feature extensions |
| DUP-04 | Low | `rpc_result_test.dart`, `rpc_result_extended_test.dart` | Overlapping parse tests | Merge into one test file |

**Dead code candidates (zero production imports):**
- `user_error_mapper.dart`
- `date_format_utils.dart`
- `paginated_list_notifier.dart` (no `extends PaginatedListNotifier`)

---

## Performance Issues

| ID | Severity | Files | Evidence | Impact | Solution |
|----|----------|-------|----------|--------|----------|
| PERF-01 | Low | `app_log.dart` | `_format` runs 7 regexes on every log line | Negligible at clinic scale; could matter in tight loops | Short-circuit if no `=`, `@`, `Bearer`, `eyJ` |
| PERF-02 | Low | `paginated_list_notifier.dart` | `loadMore` spreads `[...current.items, ...page.items]` | O(n²) copies if user loads many pages | Mutate list in place or use `ListBuilder`/pagination window cap |

---

## Test Coverage Gaps

| Area | Existing tests | Missing |
|------|----------------|---------|
| `RpcResult` / `RpcFailure` | `rpc_result_test.dart`, `rpc_result_extended_test.dart` (good) | JSON string data edge cases (invalid JSON string silently → null data) |
| `AppRpcInvoker` | Migration hint only (`settings_rpc_repository_test.dart`) | Success path, `success=false`, `AuthException`, `FormatException`, generic PostgREST, empty params |
| `AppLog` | Redaction smoke test | PHI param patterns, RPC message policy |
| `UserErrorMapper` | **None** | All branches, `RpcFailure` passthrough |
| `mapExceptionToFailure` | **None** | Each exception type, unknown error |
| `PaginatedListNotifier` | **None** | loadMore, refresh race, partial page, hasMore edge cases |
| `date_format_utils` | **None** | UTC/local, null |
| `copy_with_sentinel` | Indirect via domain models | Optional sentinel behavior test |
| Integration | Repository PostgREST tests (patients) | AppRpcInvoker-level tests shared across features |

**Positive note:** Feature repositories have extensive RpcFailure propagation tests (patients, visits, settings, shifts). Feature `*MessageForRpc` functions have thorough unit tests—but those tests don't protect UI wiring that doesn't exist yet.

---

## Recommended Refactoring

### Phase 1 — Safety & consistency (1–2 days)
1. Fix `AppRpcInvoker` catch-all: map `FormatException`, `SocketException`, `TimeoutException` to typed `RpcFailure`.
2. Stop logging raw `error_message` at warning level; code-only in production logs.
3. Wire existing `*MessageForRpc` into presentation notifiers OR delete dead mappers and consolidate on `UserErrorMapper`.

### Phase 2 — Consolidate RPC infrastructure (2–3 days)
4. Migrate `bootstrap_repository` and `provisioning_repository` to `AppRpcInvoker`.
5. Extract shared `_formatRpcDate` and input validation helpers.
6. Add comprehensive `app_rpc_invoker_test.dart`.

### Phase 3 — Architecture cleanup (3–5 days)
7. Move `RpcFailure` to `core/errors/`; introduce domain error types consumed by presentation.
8. Fix or delete `PaginatedListNotifier` before first adoption (generation token, offset fix, error mapper).
9. Unify `AppFailure` and runtime errors under one presentation model.

### Phase 4 — Hardening
10. Expand `AppLog` redaction tests and patterns.
11. Merge duplicate RPC parse tests; add contract test against live Supabase composite shape.

---

## Cross-File Validation Matrix

| From → To | Status | Notes |
|-----------|--------|-------|
| `RpcResult` → `RpcFailure` | ✅ Consistent | Thrown when `success == false` |
| `AppRpcInvoker` → `UserErrorMapper` | ❌ Not connected | Transport errors bypass both |
| `RpcFailure` → feature mappers | ⚠️ Partial | Visits/setup only |
| `RpcFailure` → `UserErrorMapper` | ❌ Dead | Mapper unused |
| `AppException` → `AppFailure` | ✅ Startup only | `mapExceptionToFailure` |
| `PaginatedListNotifier` → `UserErrorMapper` | ❌ Uses `toString()` | |
| `AppLog` → RPC errors | ⚠️ Risk | Messages logged verbatim |
| `copyWithSentinel` → domain models | ✅ Consistent | 8 models, correct usage |

---

## File-by-File Notes

### `app_rpc_invoker.dart`
Solid baseline mixin used by 14 repositories. Missing catch-all, logs server messages. Settings sub-mixin (`SettingsRpcInvoker`) correctly delegates.

### `rpc_result.dart`
Robust parsing (map, list, camelCase aliases, JSON string data). `RpcFailure` should move out. `_coerceData` swallows JSON parse errors silently → null data (could hide bugs).

### `exceptions.dart`
Focused startup exceptions; well-structured hierarchy. `PermissionDeniedException` in `permission_service.dart` extends `AppException` but isn't in this file.

### `failures.dart`
Minimal UI model for startup shell. `recoverable` flag unused in many consumers.

### `app_log.dart`
Good security-conscious design; test hook via `debugRecords`. Redaction incomplete for server-side messages.

### `paginated_list_notifier.dart`
Reasonable API shape but unsafe for production without race/offset fixes. Currently orphan code.

### `date_format_utils.dart`
Simple, untested, unused.

### `copy_with_sentinel.dart`
Correct idiom; adequate documentation.

### `user_error_mapper.dart`
Well-structured but orphaned; overlaps with feature mappers and duplicates visit/setup logic partially.

---

*Review performed by static analysis and integration grep across `frontend/lib/` and `frontend/test/`.*
