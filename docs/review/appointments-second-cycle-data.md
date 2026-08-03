# Appointments Feature — Second Cycle Review: Data & Application Layers

**Date:** 2026-07-05  
**Scope:** `frontend/lib/features/appointments/data/` (4 files), `frontend/lib/features/appointments/application/` (1 file), related data-layer tests under `frontend/test/**/appointments/**`  
**Methodology:** `docs/review/prompt.md`  
**Prior review:** `docs/review/appointments-feature-code-review.md` (first cycle)

---

## Executive Summary

The data layer is **well-tested for happy-path RPC forwarding** (8 repository test files, strong apply-unit coverage) but has **systemic realtime correctness gaps** that force full list reloads on most postgres events, **no resilience** on channel degradation, and **presentation-coupled infrastructure** (concrete repository, Riverpod providers in data files). The application layer (`appointment_rpc_messages.dart`) is **complete for common codes** but **omits `DOCTOR_REQUIRED`**, is **not wired to any production caller**, and several server error paths still surface as `StateError` or raw RPC text.

| Severity | Count |
|----------|-------|
| Critical | 3 |
| High | 9 |
| Medium | 7 |

---

## 1. Critical Issues

### C-1. Realtime insert path cannot incrementally update queue — always forces full refresh

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `data/appointment_queue_realtime_apply.dart`, `presentation/providers/appointment_queue_provider.dart` (consumer) |
| **Evidence** | Insert events unconditionally return `false`; consumer calls `unawaited(refresh())` which issues 2× `list_appointments` RPCs. |

```29:30:frontend/lib/features/appointments/data/appointment_queue_realtime_apply.dart
    case PostgresChangeEvent.insert:
      return false;
```

```269:279:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
  void _onRealtimeChange(AppointmentQueueRealtimeChange change) {
    // ...
    final applied = applyAppointmentQueueRealtimeChange(items: items, change: change, todayRange: _todayRange);
    if (applied) {
      state = state.copyWith(items: sortAppointmentsByStartTime(items));
      return;
    }
    unawaited(refresh());
  }
```

| **Why** | `AppointmentListItem.fromRow` already exists and list RPC rows include all fields needed for queue display. Insert handler was never implemented despite tests encoding the “requires full refresh” contract. |
| **Impact** | Active booking during clinic hours generates redundant RPC load (2× per insert). Combined with unserialized `refresh()` in the queue provider, overlapping insert events can serve stale queue data. |
| **Recommended solution** | Implement `_applyInsert`: parse `newRecord` via `AppointmentListItem.fromRow`, verify `appointmentStartTimeIsWithinRange`, append if complete; return `false` only when payload is incomplete. Debounce refresh fallback in the provider. |

---

### C-2. No domain repository port — concrete `AppointmentRepository` is the only contract

| Field | Detail |
|-------|--------|
| **Severity** | Critical (Clean Architecture / DIP) |
| **Files** | `data/appointment_repository.dart`; consumers: `appointment_queue_provider.dart`, `appointment_calendar_provider.dart`, `appointment_detail_provider.dart`, `patient_detail_history_provider.dart` |
| **Evidence** | Auth defines `abstract class AuthRepository` in domain; appointments expose only the concrete class. All presentation providers `ref.read(appointmentRepositoryProvider)` on the data type. |

```15:19:frontend/lib/features/appointments/data/appointment_repository.dart
/// Appointment scheduling RPC wrappers (V1-4).
class AppointmentRepository with AppRpcInvoker {
  AppointmentRepository(this._client);

  final SupabaseClient _client;
```

```4:10:frontend/lib/features/auth/domain/repositories/auth_repository.dart
/// Abstract auth operations for staff sign-in lifecycle.
abstract class AuthRepository {
  Stream<AuthState> get authStateChanges;
  Session? get currentSession;
  User? get currentUser;
```

| **Why** | Without a domain port, presentation depends upward on Supabase-shaped infrastructure. Use cases cannot be introduced without first extracting an interface from the concrete class. Tests must fake the entire concrete repository or override the Riverpod provider. |
| **Impact** | Blocks use-case layer; couples UI/providers to RPC parameter shapes and `AppRpcInvoker` mixin; violates dependency rule documented in first-cycle review §1.3. Any repository signature change ripples directly into presentation. |
| **Recommended solution** | Add `domain/repositories/appointment_repository.dart` abstract class mirroring the public method surface. Rename current class to `SupabaseAppointmentRepository` (or keep name, implement interface). Register `Provider<AppointmentRepository>` against the interface in a composition module. |

---

### C-3. Realtime apply rejects typical status-only UPDATE payloads (Postgres replica identity)

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `data/appointment_queue_realtime_apply.dart`; `backend/supabase/migrations/` (no `REPLICA IDENTITY FULL` on `appointments`) |
| **Evidence** | `_applyUpdate` returns `false` when `start_time` or `end_time` are absent from `newRecord`. With Postgres default `REPLICA IDENTITY DEFAULT`, UPDATE events include only the primary key plus **changed** columns — status transitions omit unchanged `start_time`/`end_time`. |

```80:83:frontend/lib/features/appointments/data/appointment_queue_realtime_apply.dart
  final existing = items[index];
  if (startTime == null || endTime == null) {
    return false;
  }
```

| **Why** | Unit tests always include `start_time` and `end_time` in synthetic payloads, masking production replica-identity behavior. No migration sets `REPLICA IDENTITY FULL` on `public.appointments`. |
| **Impact** | **Most realtime status changes** (check-in, in-progress, no-show) will not patch in place — they trigger full `refresh()` instead. This is the dominant queue update path during clinic operation and compounds refresh races (first-cycle §1.2). Incremental apply is effectively dead code for status transitions. |
| **Recommended solution** | Fall back to `existing.startTime` / `existing.endTime` when times are omitted from the payload. Only return `false` when the row is unknown or required fields cannot be resolved. Add tests with partial payloads (status + timestamps only). Optionally set `REPLICA IDENTITY FULL` on `appointments` if full-row payloads are preferred server-side. |

---

## 2. High Priority Issues

### H-1. Realtime client: no reconnect, ignored error callback, fire-and-forget channel teardown

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/appointment_queue_realtime.dart` |
| **Evidence** | |

```59:77:frontend/lib/features/appointments/data/appointment_queue_realtime.dart
        .subscribe((status, error) {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              onConnectionChanged(AppointmentQueueRealtimeConnection.live);
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
            case RealtimeSubscribeStatus.closed:
              onConnectionChanged(AppointmentQueueRealtimeConnection.degraded);
          }
        });
  // ...
  void unsubscribe() {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_client.removeChannel(channel));
    }
  }
```

| **Why** | `error` is never logged. `degraded` is terminal — queue provider only resubscribes on branch change or init, not on degradation. `subscribe()` calls `unawaited(removeChannel)` then immediately creates a new channel — overlapping channels possible if removal is slow. |
| **Impact** | After network blip, queue stops receiving live updates until branch switch or app restart. Silent diagnostic loss. Potential duplicate channel subscriptions and memory leaks on rapid branch toggling. |
| **Recommended solution** | Log `error` via `AppLog`. `await removeChannel` before creating a new channel (make `subscribe` async or return a `Future<void>`). Add exponential-backoff resubscribe while the owning provider is alive. Expose degraded → auto-reconnect in the client, not only in the provider. |

---

### H-2. Incremental realtime apply omits doctor and patient display fields

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/appointment_queue_realtime_apply.dart` |
| **Evidence** | `_applyUpdate` patches times, status, type, and wait timestamps only. `doctorId`, `doctorName`, `patientName` are never read from `newRecord`. |

```85:93:frontend/lib/features/appointments/data/appointment_queue_realtime_apply.dart
  items[index] = existing.copyWith(
    startTime: startTime,
    endTime: endTime,
    status: status ?? existing.status,
    type: type ?? existing.type,
    updatedAt: record.containsKey('updated_at') ? updatedAt : existing.updatedAt,
    checkedInAt: record.containsKey('checked_in_at') ? checkedInAt : existing.checkedInAt,
    inProgressAt: record.containsKey('in_progress_at') ? inProgressAt : existing.inProgressAt,
  );
```

| **Why** | `update_appointment` RPC can reassign doctor; realtime payload includes `doctor_id`/`doctor_name` when those columns change. Apply returns `true` with stale doctor labels. |
| **Impact** | Queue shows wrong doctor after reassignment until a full refresh succeeds — refresh may itself race or fail silently. Conflicts with `patchAppointmentStatus` which **does** update doctor fields optimistically. |
| **Recommended solution** | Patch `doctorId`, `doctorName`, `patientName` when keys are present. If `doctor_id` changed in DB but is missing from payload, return `false` to force refresh. Add apply tests for doctor reassignment. |

---

### H-3. `StateError` on malformed RPC success responses bypasses structured error UX

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/appointment_repository.dart` (8 throw sites) |
| **Evidence** | |

```39:42:frontend/lib/features/appointments/data/appointment_repository.dart
    final settings = AppointmentSettings.fromRpcData(result.data);
    if (settings == null) {
      throw StateError('Appointment settings were returned in an unexpected shape.');
    }
```

Same pattern at lines 57, 114, 126, 192, 244, 278, 306 for all mutation/read parse failures.

| **Why** | `RpcFailure` + `appointmentMessageForRpc` only handle server-rejected RPCs. Contract drift (migration partial apply, parser mismatch) surfaces as programmer `StateError`. Presentation `catch` blocks use generic strings. |
| **Impact** | Users see “Unable to load today's queue” instead of actionable guidance; ops cannot distinguish parse bugs from permission issues. Tests explicitly expect `StateError` (e.g. `appointment_repository_test.dart` lines 68–80), encoding the wrong contract. |
| **Recommended solution** | Throw `RpcFailure(RpcResult(success: false, errorCode: 'INVALID_RESPONSE', errorMessage: '…'))` or a domain `AppointmentParseFailure`. Log raw `result.data` at warning level. Update tests to expect structured failures. |

---

### H-4. `DoctorDevSeedService` — hardcoded credentials, no debug gate, partial-failure misreporting

| Field | Detail |
|-------|--------|
| **Severity** | High (security + data integrity) |
| **Files** | `data/doctor_dev_seed_service.dart`, `domain/doctor_dev_seed_data.dart` |
| **Evidence** | |

```13:13:frontend/lib/features/appointments/domain/doctor_dev_seed_data.dart
  static const String defaultPassword = 'DevDoctor123!';
```

```51:72:frontend/lib/features/appointments/data/doctor_dev_seed_service.dart
      var created = 0;
      for (final spec in DoctorDevSeedData.doctors) {
        await _provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: spec.username,
            password: DoctorDevSeedData.defaultPassword,
            // ...
          ),
        );
        created++;
      }
      // ...
    } on RpcFailure catch (error) {
      // ...
      return DoctorDevSeedOutcome(
        created: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: error.result.errorMessage ?? 'Doctor seed failed (${error.code}).',
      );
```

| **Why** | Service provisions real Supabase staff accounts with a known password. No `kDebugMode` guard. Idempotency checks display-name prefix only, not `username`. On mid-loop `RpcFailure`, `created` resets to `0` despite earlier successes. Service is in `lib/` (not `tool/`) though currently unwired. |
| **Impact** | Risk of accidental production account creation if wired without guards. Retry after partial seed hits username conflicts. Operator sees “0 created” while DB was mutated. **Zero tests** for this service (TG-18). |
| **Recommended solution** | Gate with `assert(kDebugMode)` or move to `tool/` / dev shell only. Track `createdSoFar` in `catch`. Check idempotency by `username`. Move password + specs out of domain. Add unit tests for partial failure and skip paths. |

---

### H-5. `updateAppointment` lacks dedicated test coverage; notes semantics differ from `createAppointment`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/appointment_repository.dart`; `test/unit/appointments/appointment_queue_doctor_rollback_test.dart` (only consumer) |
| **Evidence** | `createAppointment` omits `p_notes` when null or blank; `updateAppointment` sends `p_notes: notes.trim()` whenever `notes != null`, including `""` which clears server notes via `NULLIF(trim(COALESCE(p_notes, '')), '')`. |

```108:108:frontend/lib/features/appointments/data/appointment_repository.dart
      ...?(notes != null && notes.trim().isNotEmpty) ? {'p_notes': notes.trim()} : null,
```

```235:235:frontend/lib/features/appointments/data/appointment_repository.dart
      ...?(notes != null) ? {'p_notes': notes.trim()} : null,
```

| **Why** | BUG-004 rollback test exercises happy path only. No tests for param forwarding, notes clear vs omit, `p_end_time`, or malformed response. Method is unwired in presentation. |
| **Impact** | Regressions in calendar/detail edit flows will go unnoticed until UI lands. Callers passing `notes: ''` unintentionally wipe server notes. |
| **Recommended solution** | Add `appointment_repository_update_test.dart` mirroring create/reschedule suites. Align notes contract: document and test `null` = omit, `''` = clear (or omit empty on both paths). |

---

### H-6. Client duration validation ignores settings-driven bounds

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/appointment_repository.dart`, `domain/appointment_settings.dart` |
| **Evidence** | `_assertDurationMinutes` hardcodes minimum 5; no maximum check. `getSettings` parses `min_duration_minutes` but repository never uses it. Server enforces 5–240 via `assert_appointment_duration_bounds`. |

```333:342:frontend/lib/features/appointments/data/appointment_repository.dart
  void _assertDurationMinutes(int minutes) {
    if (minutes < 5) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'Duration must be at least 5 minutes.',
        ),
      );
    }
  }
```

| **Why** | Settings RPC returns org-specific `min_duration_minutes`; client validation is decoupled from fetched settings. |
| **Impact** | If org sets min 15, client accepts 10 until server rejects with generic `INVALID_INPUT` passthrough — confusing UX when `appointmentMessageForRpc` is wired. |
| **Recommended solution** | Accept `AppointmentSettings` (or min/max ints) in create/update/reschedule methods, or fetch settings inside repository before validating. Add max 240 client guard matching server. |

---

### H-7. Riverpod providers defined inside data layer files

| Field | Detail |
|-------|--------|
| **Severity** | High (layering; mirrors auth smell) |
| **Files** | `data/appointment_repository.dart` (346–348), `data/appointment_queue_realtime.dart` (81–83) |
| **Evidence** | `import 'package:flutter_riverpod/flutter_riverpod.dart'` and `Provider<>` at file bottom of both data files. |
| **Why** | Composition root mixed with infrastructure. Data layer depends on Flutter framework. Auth has the same pattern but at least uses domain interfaces. |
| **Impact** | Data code cannot be reused headlessly; circular import risk as feature grows; reinforces presentation → concrete data coupling. |
| **Recommended solution** | Move providers to `app/di/appointments_di.dart` or `features/appointments/di/`. Keep data files free of Riverpod. |

---

### H-8. `markAppointmentNoShow` discards server wait timestamps

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/appointment_repository.dart` |
| **Evidence** | Delegates to `updateAppointmentStatus` but returns only `update.status`, dropping `updatedAt`, `checkedInAt`, `inProgressAt` from `AppointmentStatusUpdateResult`. |

```312:314:frontend/lib/features/appointments/data/appointment_repository.dart
  Future<AppointmentStatus> markAppointmentNoShow({required String appointmentId}) async {
    final update = await updateAppointmentStatus(appointmentId: appointmentId, newStatus: AppointmentStatus.noShow);
    return update.status;
  }
```

| **Why** | Queue `patchAppointmentStatus` needs server timestamps for wait-tier display. Callers of `markAppointmentNoShow` cannot patch queue without a second parse or re-fetch. |
| **Impact** | When UI wires no-show action through this convenience method, queue wait stats will be stale unless callers switch to `updateAppointmentStatus` directly. |
| **Recommended solution** | Return `AppointmentStatusUpdateResult` (or deprecate method in favor of status update use case). |

---

### H-9. Supabase realtime client has zero unit tests

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/appointment_queue_realtime.dart`; tests use fakes only (`appointment_queue_provider_test.dart`) |
| **Evidence** | Grep shows no test imports `SupabaseAppointmentQueueRealtimeClient`. Channel naming, filter column, status callback mapping, and unsubscribe sequencing are unverified. |
| **Impact** | Regressions in channel lifecycle (filter typo, wrong table, missing unsubscribe) will only surface in manual QA or production. |
| **Recommended solution** | Add unit tests with a mock `SupabaseClient` verifying channel name `appointments-queue-$branchId`, filter on `branch_id`, and that `unsubscribe` clears `_channel` before resubscribe. |

---

## 3. Medium Priority Issues

### M-1. `listAppointments` silently returns empty list when `items` is not a `List`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/appointment_repository.dart` |
| **Evidence** | |

```162:165:frontend/lib/features/appointments/data/appointment_repository.dart
    final rawItems = result.data?['items'];
    if (rawItems is! List) {
      return const [];
    }
```

| **Why** | RPC migration bugs or envelope drift manifest as an empty queue/calendar with no error. No log, no `RpcFailure`. Not covered by tests (list tests cover malformed **rows**, not missing `items` key). |
| **Impact** | Operators see blank schedule during contract drift; hard to diagnose without network inspection. |
| **Recommended solution** | Log warning with `rawItems.runtimeType`. Consider `RpcFailure(INVALID_RESPONSE)` when `success: true` but `items` is absent. Add repository test. |

---

### M-2. `appointmentMessageForRpc` missing `DOCTOR_REQUIRED` and not wired to production

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `application/appointment_rpc_messages.dart` |
| **Evidence** | Server returns `DOCTOR_REQUIRED` when starting in-progress without assigned doctor (`20260627120000_appointment_wait_timestamps.sql` lines 106, 242). Mapper has no arm — falls through to `failure.message`. Grep shows **no** `lib/` imports of `appointmentMessageForRpc` outside the application file itself. |
| **Impact** | Raw server text shown when UI wires error toasts. Application layer provides no value until integrated. |
| **Recommended solution** | Add `'DOCTOR_REQUIRED' => 'Select a doctor before starting this visit.'`. Wire mapper in queue/calendar/detail providers' `catch (RpcFailure)`. Complete test matrix (9/15+ codes tested). |

---

### M-3. `invokeRpc` does not catch `FormatException` from `RpcResult.fromDynamic`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `core/rpc/app_rpc_invoker.dart` (affects all repository methods) |
| **Evidence** | `RpcResult.fromDynamic` throws `FormatException` on unrecognized payload shape (line 35 of `rpc_result.dart`). `invokeRpc` catches `AuthException` and `PostgrestException` only. |
| **Impact** | Completely malformed RPC envelope crashes or escapes as uncaught exception instead of `RpcFailure(INVALID_RESPONSE)`. |
| **Recommended solution** | Catch `FormatException` in `AppRpcInvoker.invokeRpc` → `RpcFailure(INVALID_RESPONSE)`. Add repository test with non-map RPC response. |

---

### M-4. Realtime apply: `is_deleted` soft-delete on DELETE event not handled

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/appointment_queue_realtime_apply.dart` |
| **Evidence** | `is_deleted` checked on UPDATE path only (line 58). DELETE path uses `_removeByRecord` on `oldRecord` — works if delete event fires. Soft-delete via UPDATE sets `is_deleted=true` and is handled. Hard DELETE vs soft-delete depends on backend; no test for `is_deleted` update. |
| **Impact** | If backend soft-deletes without setting `cancelled` status, row removal depends on `is_deleted` branch — covered. Gap is **untested**; out-of-range reschedule removal also untested (TG-20). |
| **Recommended solution** | Add apply tests for `is_deleted`, out-of-range reschedule, and unknown-id update. |

---

### M-5. `appointment_queue_realtime_apply` depends on Supabase enum in data layer

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/appointment_queue_realtime_apply.dart` |
| **Evidence** | Imports `package:supabase_flutter/supabase_flutter.dart` for `PostgresChangeEvent` on `AppointmentQueueRealtimeChange`. Pure apply logic otherwise uses only domain types. |
| **Impact** | Apply logic cannot live in domain without adapter; tests depend on Supabase package. |
| **Recommended solution** | Introduce domain `RealtimeChangeKind` enum; map Supabase event in `appointment_queue_realtime.dart` adapter. Move apply to domain. |

---

### M-6. No RPC cancellation or in-flight deduplication in repository

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/appointment_repository.dart`, `core/rpc/app_rpc_invoker.dart` |
| **Evidence** | All methods `await invokeRpc(...)` with no generation token, `CancelableOperation`, or request coalescing. Branch switch during `listAppointments` cannot abort the in-flight call. |
| **Impact** | Stale list results are applied by presentation (first-cycle §1.2). Data layer provides no hook for callers to ignore superseded responses. |
| **Recommended solution** | At minimum, document that callers must guard with generation tokens. Optionally expose `listAppointments` with an optional `CancelToken` (Dio-style) or return a cancellable future from a thin wrapper. |

---

### M-7. `DoctorDevSeedService` idempotency check is name-prefix only

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/doctor_dev_seed_service.dart` |
| **Evidence** | Skip when any doctor's `fullName` starts with `[Dev] ` — does not check `spec.username` list. |
| **Impact** | Renamed dev doctors or partial manual seeds allow duplicate username creation on retry → `RpcFailure` on conflict. |
| **Recommended solution** | Match on `DoctorDevSeedData.doctors.map((d) => d.username)` against existing staff usernames. |

---

## 4. Test Coverage Assessment (Data Layer)

| Component | Test files | Gaps |
|-----------|------------|------|
| `AppointmentRepository` | 8 unit + 1 boundary | `updateAppointment` suite missing; `listAppointments` missing `items` shape failure; malformed success → `StateError` encoded as expected |
| `applyAppointmentQueueRealtimeChange` | 1 unit (6 cases) | Partial payload (no times), doctor reassignment, `is_deleted`, out-of-range, insert-with-full-row |
| `SupabaseAppointmentQueueRealtimeClient` | **0** | Entire client untested |
| `DoctorDevSeedService` | **0** | Entire service untested |
| `appointmentMessageForRpc` | 1 unit (8 cases) | `DOCTOR_REQUIRED`, `DOCTOR_ALREADY_IN_PROGRESS`, `FORBIDDEN`, `INVALID_TRANSITION` generic, `RPC_NOT_APPLIED`, `INVALID_INPUT` passthrough |

---

## 5. Cross-Layer Consistency (Data ↔ Domain ↔ Server)

| Concern | Repository | Realtime apply | Server RPC | Verdict |
|---------|------------|----------------|------------|---------|
| Cancelled row in queue | `cancel_appointment` | Removes on `cancelled` status / delete | Sets `cancelled` | Consistent |
| No-show in queue | `update_appointment_status` | Keeps row, updates status | Sets `no_show` | Consistent |
| Doctor reassignment | `update_appointment` sends `p_doctor_id` | **Does not patch doctor fields** | Updates `doctor_id` | **Inconsistent** |
| Status transition timestamps | `updateAppointmentStatus` returns full result | Patches when keys present | Sets `checked_in_at`, etc. | Consistent when apply runs |
| Status-only realtime UPDATE | N/A | **Returns false** (missing times) | Replica DEFAULT | **Broken incremental path** |
| Duration min | Hardcoded 5 | N/A | `min_duration_minutes` from settings | **Inconsistent** |
| Notes on update | Sends empty string when `notes: ''` | N/A | Clears notes | Documented risk |

---

## 6. Recommended Fix Order (Data + Application)

1. **Fix realtime apply partial payloads** (C-3) — unlocks incremental status patches.
2. **Implement insert handler** (C-1) — reduces RPC storm on booking.
3. **Realtime client resilience** (H-1) — reconnect + await channel teardown.
4. **Patch doctor/patient in apply** (H-2).
5. **Add domain repository port** (C-2) — unblocks use cases.
6. **Replace `StateError` with `RpcFailure(INVALID_RESPONSE)`** (H-3).
7. **Harden dev seed service** (H-4) — before wiring to dev shell.
8. **`updateAppointment` test suite + notes alignment** (H-5).
9. **Wire `appointmentMessageForRpc` + add `DOCTOR_REQUIRED`** (M-2).
10. **Move providers out of data layer** (H-7).

---

*Second-cycle data & application review — 2026-07-05.*
