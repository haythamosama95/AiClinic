# Flutter Shifts Feature Code Review

**Feature path:** `frontend/lib/features/shifts`  
**Review date:** 2026-07-05  
**Architecture:** Partial Clean Architecture (domain + data + thin application; no presentation, no use cases)  
**Review scope:** All 10 feature files, 3 unit test files + test support, app-layer routing/auth integration, appointments cross-feature consumption, dev seed usage

---

## Executive Summary

### Overall Verdict: **Solid Backend/Domain Foundation — Not Ready for Shift Management UI**

The shifts feature delivers a **well-tested repository and domain model** for V1-7 shift scheduling RPCs, with thoughtful error-code mapping, overlap conflict parsing, optimistic-concurrency (`expected_updated_at`) guards, and client-side input validation. Repository tests cover many regression cases (deduped staff IDs, stale-shift mapping, notes clearing, 366-day range guard).

However, the feature is **architecturally incomplete relative to auth and appointments patterns**: there is **no presentation layer** (all `/shifts/*` routes are placeholders), **no repository interface**, **no use-case layer**, and **no dedicated Riverpod controllers**. `shiftMessageForRpc` and `ShiftCalendarMode` are **dead code**. Domain entities **import Flutter** (`foundation.dart`) and **auth types** (`StaffRole`), violating strict Clean Architecture. The primary runtime consumer is **appointments queue integration**, which matches doctors by **display name** (fragile) and has **no request cancellation** on branch/timezone changes.

| Category | Count |
|----------|-------|
| Critical | 2 |
| High | 9 |
| Medium | 14 |
| Low | 8 |
| Clean Architecture violations | 8 |
| SOLID violations | 5 |
| Performance items | 4 |
| Test coverage gaps | 16 |

**Recommended action:** Safe to depend on for **read-path integration** (appointments queue) and **dev seeding**. Do not ship shift management screens until presentation layer, use-case seams, and user-facing error wiring exist. Consolidate doctor resolution to staff IDs before UI work.

---

## Feature Overview

### Purpose

Manages **branch shift scheduling** (create, list, detail, update, cancel, assignment changes) via Supabase RPCs (`list_shifts`, `create_shift`, `get_shift_detail`, `update_shift`, `cancel_shift`, `modify_shift_assignments`). Provides **domain models** for calendar/list views, overlap conflicts, and staff eligibility. Consumed by **appointments queue** to resolve which doctors are on shift at a given time.

### Data Flow

```mermaid
sequenceDiagram
  participant Router as GoRouter (/shifts/*)
  participant Guard as AuthRouteGuard
  participant Appt as appointmentQueueShiftDoctorLookupProvider
  participant Repo as ShiftRepository (data)
  participant SB as Supabase RPC / PostgREST

  Router->>Guard: shiftRouteRedirect
  Guard-->>Router: placeholder or redirect

  Appt->>Repo: listShifts(today)
  Appt->>Repo: listActiveStaffForBranch
  Appt->>Appt: _resolveQueueShiftDoctors (name matching)
  Appt->>Appt: AppointmentQueueShiftDoctorLookup

  Note over Appt,Repo: No use-case layer; presentation in appointments feature

  Repo->>SB: rpc(list_shifts, create_shift, ...)
  Repo->>SB: from(staff_branch_assignments) for staff list
```

**Use cases:** **None.** Auth has `domain/usecases/`; shifts have zero equivalents. Presentation (when built) would likely call `ShiftRepository` directly, matching appointments.

### File Inventory

| Layer | Path | Responsibility |
|-------|------|----------------|
| **Domain** | `domain/shift_status.dart` | `active` / `incomplete` / `cancelled` / `unknown` enum |
| | `domain/shift_list_item.dart` | Calendar/list row + lenient `fromRow` |
| | `domain/shift_detail.dart` | Detail entity, branch summary, `toListItem()` |
| | `domain/shift_assignment.dart` | Assignment row parsing |
| | `domain/shift_assignment_result.dart` | `modify_shift_assignments` result |
| | `domain/shift_overlap_conflict.dart` | Overlap error payload parsing |
| | `domain/shift_branch_staff.dart` | Branch staff for assignment picker |
| | `domain/shift_calendar_mode.dart` | Week/month enum (**unused**) |
| **Application** | `application/shift_rpc_messages.dart` | User-facing RPC error copy (**unused**) |
| **Data** | `data/shift_repository.dart` | RPC wrappers, error mapping, Riverpod provider |
| **Presentation** | — | **Missing** — routes use `uiPendingPlaceholder` |
| **Integration** | `appointments/.../appointment_queue_shift_provider.dart` | Today's shift doctor lookup |
| | `appointments/domain/appointment_queue_shift_doctors.dart` | Time-window doctor resolution |
| | `app/shell/dev/dev_clinic_seed_service.dart` | Dev shift seeding |

---

## 1. Critical Issues

### C-1: No presentation layer — shift routes are non-functional placeholders

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `frontend/lib/app/router.dart`, `frontend/lib/app/app_routes.dart` |
| **Evidence** | All shift routes render `uiPendingPlaceholder('Shifts', state)` for calendar, create, and detail paths. |
| **Why** | The feature cannot be used by end users; routing and auth guards exist but deliver no functionality. |
| **Impact** | Product gap: shift management is backend-ready but UI-absent. Permission and nav wiring may drift before UI lands. |
| **Solution** | Implement presentation layer (calendar, create form, detail/assignment screens) behind existing routes; add controllers that consume repository through use cases. |

### C-2: `shiftMessageForRpc` is never wired — UI will show raw RPC errors

| Field | Detail |
|-------|--------|
| **Severity** | Critical (for upcoming UI) |
| **Files** | `application/shift_rpc_messages.dart`, entire codebase (single definition, zero call sites) |
| **Evidence** | `grep shiftMessageForRpc` returns only the definition file. Overlap, stale-shift, and permission errors have user-facing copy defined but unused. |
| **Why** | When UI is built, developers may display `RpcFailure.message` directly (Postgres/PostgREST text) instead of mapped copy. |
| **Impact** | Poor UX; inconsistent with other features that map errors at presentation boundary. |
| **Solution** | Call `shiftMessageForRpc` from shift presentation error handlers; add missing codes (`staff_already_assigned`, `duplicate_staff_assignment`, `shift_not_found`, `invalid_date_range`); add unit tests. |

---

## 2. High Priority Issues

### H-1: No repository interface — untestable swap at domain boundary

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/shift_repository.dart` |
| **Evidence** | `ShiftRepository` is a concrete class; `shiftRepositoryProvider` returns concrete type. No `abstract class ShiftRepository` or port in domain. |
| **Why** | Violates Dependency Inversion; presentation and appointments import data layer directly. |
| **Impact** | Harder to mock at feature boundary; tight coupling to Supabase. |
| **Solution** | Add `domain/repositories/shift_repository.dart` abstract port; move provider to `data/` or `application/`. |

### H-2: No use-case layer

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | Feature root (missing `domain/usecases/`) |
| **Evidence** | Auth has `sign_in.dart`, `load_granted_permissions.dart`, etc.; shifts have none. `appointment_queue_shift_provider.dart` calls `shiftRepository.listShifts` directly. |
| **Why** | Business orchestration (e.g. list + staff + overlap handling) will scatter across widgets/providers. |
| **Impact** | Duplication risk when UI adds create/edit flows; harder to unit-test orchestration without widget tests. |
| **Solution** | Add use cases: `ListShifts`, `GetShiftDetail`, `CreateShift`, `ModifyShiftAssignments`, etc., with `shift_use_case_providers.dart`. |

### H-3: Doctor resolution uses display-name matching — fragile cross-feature coupling

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_shift_provider.dart` (lines 72–100), `appointment_queue_shift_doctors.dart` (lines 162–167, 198–204) |
| **Evidence** | `_resolveQueueShiftDoctors` builds `assigneeKeys` from `shift.assigneeNames` (strings), matches `member.fullName.toLowerCase()`. `AppointmentQueueShiftDoctorLookup._resolveDoctorName` maps assignee strings to doctors via normalized name map. |
| **Why** | `ShiftListItem` carries names, not staff IDs, from `list_shifts`. Renames, typos, or duplicate names break matching. |
| **Impact** | Queue may show "No preferred doctor" or omit on-shift doctors; BUG-005 test shows duplicate names cause empty lookup. |
| **Solution** | Extend `list_shifts` RPC / `ShiftListItem` to include `assignee_staff_ids` or structured assignees; resolve by ID in appointments. |

### H-4: `listShifts` silently drops malformed rows and non-list responses

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_repository.dart` (lines 49–59), `shift_list_item.dart` (`fromRow` returns null) |
| **Evidence** | If RPC returns non-`List`, repository returns `const []`. If row fails `fromRow`, it is filtered out with no log. |
| **Why** | Server schema drift or partial corruption appears as empty calendar with no error. |
| **Impact** | Silent data loss in appointments queue and future calendar UI. |
| **Solution** | Log dropped rows at warning level; consider throwing if >0 rows dropped or response shape is wrong. |

### H-5: Inconsistent empty-input handling in `listActiveStaffForBranch`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_repository.dart` (lines 128–132 vs 28–31) |
| **Evidence** | `listShifts` throws `INVALID_INPUT` for empty `branchId`; `listActiveStaffForBranch` returns `const []`. |
| **Why** | Callers cannot distinguish "no staff" from "invalid branch". |
| **Impact** | `appointmentQueueShiftDoctorLookupProvider` may proceed with empty staff and rely on fallback paths silently. |
| **Solution** | Align validation: throw or return `Result` type; document contract. |

### H-6: Mixed data access — RPC for shifts, direct table for staff

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_repository.dart` (`listActiveStaffForBranch` lines 134–138) |
| **Evidence** | Shift CRUD uses RPC; staff list uses `.from('staff_branch_assignments').select(...)`. |
| **Why** | Different RLS paths, caching, and error shapes; staff query bypasses shift RPC migration hint logic. |
| **Impact** | Permission errors may surface as empty lists vs `RpcFailure`; harder to mock consistently. |
| **Solution** | Add `list_branch_shift_staff` RPC or reuse settings staff use case with explicit contract. |

### H-7: `assigneeCount` can disagree with `assigneeNames` without validation

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_list_item.dart` (lines 76–78) |
| **Evidence** | `assigneeCount` parsed from row with fallback to `assigneeNames.length`; `isUnassigned` from separate `is_unassigned` flag. No cross-check. |
| **Why** | Server inconsistency could show "3 assignees" with 1 name and `isUnassigned: false`. |
| **Impact** | Misleading list UI and wrong queue doctor resolution. |
| **Solution** | Validate consistency in `fromRow` or derive `isUnassigned` from `assigneeCount == 0`. |

### H-8: Race condition in `appointmentQueueShiftDoctorLookupProvider`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_shift_provider.dart` (lines 16–50) |
| **Evidence** | `FutureProvider.autoDispose` watches branch/timezone, then awaits two sequential repository calls plus `listStaffUseCase`. No `ref.onDispose` cancellation; no request token. |
| **Why** | Fast branch switch can complete stale request after newer one. |
| **Impact** | Queue shows wrong branch's shift doctors briefly (same class of bug noted in appointments review). |
| **Solution** | Use `AsyncNotifier` with generation counter, or cancel via `ref.invalidate` + mounted check pattern used elsewhere. |

### H-9: Domain imports auth feature type — inward boundary violation

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_branch_staff.dart` (line 1: `auth_session.dart` for `StaffRole`) |
| **Evidence** | Shifts domain depends on auth domain for `StaffRole.tryParse`. |
| **Why** | Feature domains should not depend on each other; shifts should own or share a core staff-role type. |
| **Impact** | Circular dependency risk if auth ever imports shifts; harder to extract feature module. |
| **Solution** | Move `StaffRole` to `core/domain` or duplicate minimal enum in shifts with mapper at data boundary. |

---

## 3. Medium Priority Issues

### M-1: Domain layer imports Flutter `foundation.dart`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_list_item.dart`, `shift_detail.dart`, `shift_assignment.dart`, `shift_assignment_result.dart`, `shift_overlap_conflict.dart`, `shift_branch_staff.dart` |
| **Evidence** | `@immutable` from `package:flutter/foundation.dart`. |
| **Why** | Pure Dart domain should not depend on Flutter SDK. |
| **Impact** | Cannot reuse domain in CLI/server; couples to Flutter version. |
| **Solution** | Use `meta` package `@immutable` or plain Dart classes. |

### M-2: `ShiftCalendarMode` is dead code

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/shift_calendar_mode.dart` |
| **Evidence** | Zero references outside defining file. |
| **Why** | Placeholder for UI never built; adds maintenance noise. |
| **Impact** | Confusion about intended calendar modes. |
| **Solution** | Remove until UI implementation, or wire into route query params. |

### M-3: `ShiftDetail.fromRpcData` reuses `ShiftListItem.fromRow` for date-only hack

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_detail.dart` (lines 99–103) |
| **Evidence** | Constructs dummy row with empty assignee fields to extract `shiftDate` via `ShiftListItem.fromRow`. |
| **Why** | Awkward coupling; `_parseDate` is private on `ShiftListItem`. |
| **Impact** | Fragile if `fromRow` validation tightens. |
| **Solution** | Extract shared `ShiftDateParser` or make `_parseDate` a public static on a shared util. |

### M-4: `toListItem()` ignores server `assigneeCount` and `isUnassigned` flags

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_detail.dart` (lines 71–83) |
| **Evidence** | `assigneeCount: assignments.length`; `isUnassigned` passed through from detail, not recomputed. |
| **Why** | Detail assignments list may be incomplete while flags say otherwise. |
| **Impact** | Inconsistent list item when detail used as list source. |
| **Solution** | Derive counts from `assignments` consistently or validate against flags. |

### M-5: Overnight shifts not handled in time-window logic

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_queue_shift_doctors.dart` (lines 154–160) |
| **Evidence** | `appointmentMinutes >= shiftEnd` excludes coverage; no handling when `shiftEnd < shiftStart` (overnight). |
| **Why** | Backend may allow or disallow overnight; client assumes same-day window. |
| **Impact** | Night shifts (e.g. 22:00–06:00) never match appointments. |
| **Solution** | Confirm backend rules; extend `_parseClockMinutes` logic for overnight intervals. |

### M-6: `ShiftStatus.unknown` included in staffed shifts for queue sidebar

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_queue_shift_doctors.dart` (`_isStaffedShift` lines 105–107), test at `appointment_queue_shift_doctors_test.dart` line 52 |
| **Evidence** | Only excludes `cancelled` and unassigned; `unknown` status shifts are included. |
| **Why** | Unknown may mean parse failure of future status values. |
| **Impact** | Queue may show doctors from malformed/deprecated shifts. |
| **Solution** | Treat `unknown` as non-staffed unless explicitly documented. |

### M-7: Error code `staff_already_assigned` mapped in repository but not in user messages

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_repository.dart` (line 293), `shift_rpc_messages.dart` |
| **Evidence** | `_extractShiftErrorCode` knows `staff_already_assigned`; `shiftMessageForRpc` has no case. |
| **Why** | Falls through to raw `failure.message`. |
| **Impact** | Poor UX on duplicate assignment attempts. |
| **Solution** | Add message case. |

### M-8: `createShift` throws `StateError` instead of `RpcFailure` on missing ID

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_repository.dart` (lines 93–95) |
| **Evidence** | `throw StateError('Shift was created but no shift id was returned.')` |
| **Why** | Inconsistent with `_clientInputFailure` / `RpcFailure` pattern. |
| **Impact** | Presentation must catch two exception types. |
| **Solution** | Throw `RpcFailure` with code `UNEXPECTED_RESPONSE`. |

### M-9: No logging on RPC success path for mutations

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_repository.dart` (`_invokeJsonRpc` line 244) |
| **Evidence** | Only `AppLog.fine` on invoke; no result logging; errors not logged before rethrow. |
| **Why** | Harder to diagnose production issues. |
| **Impact** | Support/debug friction. |
| **Solution** | Log `RpcFailure` at warning with code; fine-level success for mutations. |

### M-10: `listShifts` does not validate `dateFrom`/`dateTo` for equal requirement beyond `to.isBefore(from)`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_repository.dart` (lines 33–40) |
| **Evidence** | Allows same-day range; 366-day max enforced. No explicit guard for far-future dates. |
| **Why** | May be intentional; undocumented. |
| **Impact** | Unbounded future queries within 366 days. |
| **Solution** | Document contract; align with backend if limits exist. |

### M-11: `modifyAssignments` requires at least one add/remove — no "touch" for refresh

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_repository.dart` (lines 163–165) |
| **Evidence** | Throws if both lists empty. |
| **Why** | Correct for RPC semantics; UI may need refresh-only path via `getShiftDetail`. |
| **Impact** | None if documented. |
| **Solution** | Document; ensure UI uses `getShiftDetail` for reload. |

### M-12: Permission model: view uses branch assignment, manage uses `shifts.manage`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `permission_service.dart` (lines 89–96), `auth_route_guard.dart` (lines 193–208) |
| **Evidence** | `canViewShifts()` → `hasBranchAssignment` only; create requires `canManageShifts()`. |
| **Why** | RPC may still enforce `permission_denied` for users with branch but without manage on mutations. |
| **Impact** | UI must gate edit actions separately from calendar view (not yet implemented). |
| **Solution** | Mirror permissions in presentation; expose `canManageShifts` on shift screens. |

### M-13: `ShiftOverlapConflict.parseFromRpcMessage` fragile prefix parsing

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_overlap_conflict.dart` (lines 68–81) |
| **Evidence** | Finds first `shift_overlap:` substring and JSON-decodes remainder. |
| **Why** | Breaks if message contains prefix in unrelated text or JSON is truncated. |
| **Impact** | Empty conflict list → generic overlap message without staff details. |
| **Solution** | Prefer `details` channel (already prioritized); add test for malformed JSON. |

### M-14: `getShiftDetail` and `modifyAssignments` success paths undertested

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shift_repository_test.dart` |
| **Evidence** | `getShiftDetail` has one read-only flag test; no happy-path parse test against default fake payload. `modifyAssignments` only tests dedupe. |
| **Why** | Regression risk on response parsing. |
| **Impact** | Broken assignments UI may ship unnoticed. |
| **Solution** | Add tests for default fake detail shape and successful modify response. |

---

## 4. Low Priority Issues

### L-1: `ShiftListItem.assigneeSummary` duplicates presentation logic in domain

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `shift_list_item.dart` (lines 31–38) |
| **Evidence** | Formats "Unassigned", join, "+N" suffix. |
| **Why** | View formatting in domain entity. |
| **Impact** | i18n harder; acceptable for small app. |
| **Solution** | Move to presentation mapper when UI ships. |

### L-2: `ShiftStatus.wireValue` returns `'unknown'` for unknown enum

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `shift_status.dart` (lines 22–27) |
| **Evidence** | `ShiftStatus.unknown => 'unknown'` |
| **Why** | May not be valid server enum for writes. |
| **Impact** | Low if unknown is never sent to RPC. |
| **Solution** | Make `wireValue` throw for unknown or use `String?`. |

### L-3: `_parseShiftId` fallback `toString()` on unexpected types

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `shift_repository.dart` (lines 117–121) |
| **Evidence** | Falls back to `raw.toString().trim()` for non-map/list/string. |
| **Why** | Could accept garbage IDs. |
| **Impact** | Unlikely with PostgREST. |
| **Solution** | Return null instead of stringifying. |

### L-4: `notes` on `updateShift` sends empty string to clear — create omits empty notes

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `shift_repository.dart` create (line 88) vs update (line 209) |
| **Evidence** | Asymmetric: create skips empty notes; update sends `''` to clear (tested #17). |
| **Why** | Matches RPC contract difference. |
| **Impact** | Document for UI forms. |
| **Solution** | Document in repository doc comments. |

### L-5: Dev seed bypasses use cases

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `dev_clinic_seed_service.dart` |
| **Evidence** | Calls `_shiftRepository.createShift` directly. |
| **Why** | Acceptable for dev tooling. |
| **Impact** | None for production. |
| **Solution** | None required. |

### L-6: `ShiftAssignmentResult.fromRpcData` rejects float `assignee_count`

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `shift_assignment_result.dart` (line 29) |
| **Evidence** | `assigneeCount is! num` then `.toInt()`. |
| **Why** | JSON may decode as int only in practice. |
| **Impact** | None if server returns integer. |
| **Solution** | None. |

### L-7: No `equatable` / value equality on domain types

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | All domain entities |
| **Evidence** | `@immutable` classes without `==` override. |
| **Why** | Riverpod/widget rebuilds compare by reference. |
| **Impact** | Extra rebuilds possible. |
| **Solution** | Add `Equatable` when UI state diffing matters. |

### L-8: `shift_static_paths` omits detail pattern

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `app_routes.dart` (line 133) |
| **Evidence** | `shiftStaticPaths` = calendar + new only; detail matched by prefix in guard. |
| **Why** | Intentional for parameterized route. |
| **Impact** | None. |
| **Solution** | None. |

---

## 5. Clean Architecture Violations

| ID | Violation | Files | Evidence |
|----|-----------|-------|----------|
| CA-1 | No presentation layer | `router.dart` | Placeholder routes only |
| CA-2 | Presentation in other feature calls data layer | `appointment_queue_shift_provider.dart` | Imports `shift_repository.dart` directly |
| CA-3 | No repository port in domain | `shift_repository.dart` | Concrete class in data |
| CA-4 | No use-case layer | Feature root | Missing `domain/usecases/` |
| CA-5 | Domain imports Flutter | All domain entities | `flutter/foundation.dart` |
| CA-6 | Domain imports auth feature | `shift_branch_staff.dart` | `StaffRole` from auth |
| CA-7 | Application message helper unused | `shift_rpc_messages.dart` | No presentation to consume it |
| CA-8 | Data layer contains presentation-adjacent dedupe/validation | `shift_repository.dart` | Client validation belongs in use case or domain service |

**Dependency direction today:** Appointments presentation → Shifts data → Supabase. Domain is mostly pure but polluted by Flutter/auth imports.

---

## 6. SOLID Violations

| ID | Principle | Issue | Files |
|----|-----------|-------|-------|
| S-1 | **SRP** | `ShiftRepository` handles RPC, error code extraction, staff table query, ID parsing, date formatting | `shift_repository.dart` |
| S-2 | **OCP** | New RPC error codes require editing `_extractShiftErrorCode` list and `shiftMessageForRpc` separately | `shift_repository.dart`, `shift_rpc_messages.dart` |
| S-3 | **LSP** | N/A — no abstraction to substitute | — |
| S-4 | **ISP** | Future consumers forced to depend on full repository surface | `shift_repository.dart` |
| S-5 | **DIP** | High-level appointments provider depends on low-level concrete repository | `appointment_queue_shift_provider.dart` |

---

## 7. Code Duplication & Redundancy

| Item | Why duplication exists | Recommendation |
|------|------------------------|----------------|
| Date parsing | `ShiftListItem._parseDate` private; `ShiftDetail` hacks via `fromRow` | Extract `parseShiftDate(dynamic)` in domain util |
| Staff/doctor resolution | Branch staff query in shifts repo + `listStaffUseCase` fallback in appointments provider | Single `ResolveBranchDoctors` use case |
| Error code lists | `_extractShiftErrorCode` known codes vs `shiftMessageForRpc` switch | Single `ShiftRpcErrorCodes` map to message + code |
| Assignee display | `assigneeSummary` on list item + appointments name matching | ID-based assignees eliminate name duplication |
| `ShiftCalendarMode` | Premature enum for unbuilt UI | Remove or implement |
| `shiftMessageForRpc` | Written for UI not yet built | Wire when presentation lands |

---

## 8. Performance Issues

| ID | Issue | Files | Impact | Mitigation |
|----|-------|-------|--------|------------|
| P-1 | Sequential awaits in queue provider | `appointment_queue_shift_provider.dart` | 3 round-trips (shifts, branch staff, org staff) | `Future.wait` where independent |
| P-2 | No caching of today's shifts | Same | Repeated queue rebuilds refetch | Short TTL cache keyed by branch+day |
| P-3 | `listShifts` up to 366-day range | `shift_repository.dart` | Large payloads on calendar month view | Paginate or month-scoped queries in UI |
| P-4 | Staff list re-fetched per provider watch | Same | Redundant PostgREST query | Share `branchStaffProvider` |

---

## 9. Test Coverage Gaps

| Gap | Priority | Notes |
|-----|----------|-------|
| `ShiftListItem.fromRow` unit tests | High | No direct tests; only indirect via appointments |
| `listShifts` happy path + row filtering | High | Only 366-day rejection tested |
| `listShifts` non-list RPC response | Medium | Silent empty list |
| `getShiftDetail` default payload parsing | Medium | One override test only |
| `modifyAssignments` success + stale | Medium | Dedupe only |
| `cancelShift` success | Low | Stale mapping untested |
| `shiftMessageForRpc` all codes | Medium | Zero tests |
| `ShiftBranchStaffMember.fromAssignmentRow` | Medium | Inactive staff, missing role |
| `ShiftStatus.tryParse` edge cases | Low | Unknown/default paths |
| `appointment_queue_shift_provider` widget/provider test | High | Logic only tested via domain helper |
| Overnight shift time windows | Medium | No test |
| `ShiftDetail.toListItem` empty assignments | Low | Partial via notes tests |
| Integration test: repo + real Supabase | Low | Fake client only |
| Presentation/widget tests | Critical (when UI exists) | None |
| Race/stale response for queue provider | High | Fake supports `listShiftsDelayedResponses` but no test uses it for shifts |
| `createShift` with staff IDs happy path | Medium | Dedupe only |
| Error logging assertions | Low | None |

**Existing strength:** Repository overlap parsing, duplicate key mapping, notes null/empty, staff dedupe, and appointments doctor lookup tests are solid.

---

## 10. Recommended Refactoring

### Phase 1 — Before UI (blocking)

1. Add `ShiftRepository` abstract port + use cases (`ListShiftsForRange`, `GetShiftDetail`, `CreateShift`, `UpdateShift`, `CancelShift`, `ModifyShiftAssignments`, `ListBranchStaffForShifts`).
2. Wire `shiftMessageForRpc` into a shared `ShiftRpcErrorPresenter`; complete error code coverage.
3. Extend `ShiftListItem` / RPC to carry staff IDs for assignees; refactor appointments lookup to ID-based resolution.
4. Add `listShifts` parsing tests and malformed-row logging.
5. Fix `appointmentQueueShiftDoctorLookupProvider` stale-response guard.

### Phase 2 — Presentation

1. Implement calendar (`ShiftCalendarMode`), create, and detail screens behind existing routes.
2. Riverpod `AsyncNotifier` controllers with optimistic concurrency (`expectedUpdatedAt`).
3. Overlap conflict UI using `ShiftOverlapConflict` list from `RpcFailure.details`.
4. Gate mutations with `canManageShifts()`; view with `canViewShifts()`.

### Phase 3 — Architecture hygiene

1. Remove Flutter from domain (`meta` package).
2. Decouple `StaffRole` from auth (core shared type).
3. Consolidate staff fetching to one path (RPC or settings use case).
4. Remove dead `ShiftCalendarMode` or implement it.

### Phase 4 — Hardening

1. Overnight shift time logic aligned with backend.
2. Cache today's shifts per branch.
3. Equatable on frequently compared entities.

---

## Cross-Feature Consistency Comparison

| Aspect | Auth | Appointments | Shifts |
|--------|------|--------------|--------|
| Use cases | Yes | No | No |
| Repository interface | Yes | No | No |
| Presentation | Yes | Placeholder | Placeholder |
| Domain purity | Mostly | Violated (Flutter) | Violated (Flutter + auth) |
| Test depth | High | High (domain) | Medium (repository) |
| Error message mapping | Yes | Partial | Defined but unused |

Shifts most closely resembles **appointments backend slice**: strong repository tests, no UI, consumed as a dependency by other features.

---

## Second Cycle Review

**Review date:** 2026-07-05 (second pass)  
**Method:** Four parallel skeptical reviews — domain/application, data/repository, cross-feature integration, test coverage/reliability  
**Reviewers:** [Domain & architecture](52998629-694a-4232-92ef-05cfa386c57d), [Data & repository](1827d031-0fa0-4889-bd95-258b7b7d4476), [Integration](10305ddd-6748-4c1e-9c1c-28798ba87eb9), [Tests & reliability](95921fd0-42c4-42fe-a68d-a8a0e8504e2b)

### Second-Cycle Verdict: **Backend Sound — Integration Partially Wired and Inert at Runtime**

Cycle 1 correctly identified architectural gaps and fragile name-based doctor resolution. Cycle 2 **confirms all first-cycle Critical/High findings** and surfaces one **new Critical integration defect**: `appointmentQueueShiftDoctorLookupProvider` is fetched and invalidated but **never watched** by any caller — queue start/block logic always uses `AppointmentQueueShiftDoctorLookup.empty`. The shifts repository remains the strongest layer; the appointments integration is a **partial wire** that creates false confidence.

| Category | Cycle 1 | Cycle 2 (consolidated) |
|----------|---------|------------------------|
| Critical | 2 | **3** |
| High | 9 | **12** |
| Medium | 14 | **18** |

**Recommended action (updated):** Do not treat appointments queue shift logic as functional until provider lookup is wired into domain call sites. Fix silent `listShifts` data loss before any UI work. Extend `list_shifts` with assignee staff IDs before doctor-resolution refactors.

---

### Second Cycle — Critical Issues

#### C2-1: Shift doctor lookup provider is never consumed — queue rules always run with empty lookup

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `appointment_queue_shift_provider.dart`; `appointment_queue_display.dart`, `appointment_status_transitions.dart`, `appointment_queue_start_doctor.dart` |
| **Evidence** | `appointmentQueueShiftDoctorLookupProvider` is defined and invalidated in `appointment_surface_invalidation.dart`, but zero `ref.watch(appointmentQueueShiftDoctorLookupProvider)` call sites exist. Domain APIs default `shiftLookup` to `AppointmentQueueShiftDoctorLookup.empty`. |
| **Why** | Fetch/orchestration exists; presentation never passes results into domain rules. |
| **Impact** | `doctorInProgressBlockReason`, `forwardStatusTargetFor`, and `requiresDoctorPicker` behave as if no doctors are on shift even when shifts exist. Start transitions and doctor picker logic are inert. |
| **Solution** | Add composed provider that watches async lookup; thread resolved lookup into all queue action/display call sites; add provider tests with delayed RPC responses. |
| **Cycle 1** | **NEW** (worse than H-2/H-8 implied) |

#### C2-2: `listShifts` silently returns empty list on RPC shape drift or malformed rows

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `shift_repository.dart` (49–59), `shift_list_item.dart` (69–106) |
| **Evidence** | Non-`List` RPC payloads return `const []` with no throw/log. Rows failing `ShiftListItem.fromRow` filtered via `.whereType<ShiftListItem>()` with no telemetry. |
| **Why** | Callers cannot distinguish “no shifts” from parse/contract failure. |
| **Impact** | Queue doctor lookup and future calendar show empty data with no error surface. |
| **Solution** | Throw `RpcFailure(UNEXPECTED_RESPONSE)` on non-list payloads; log dropped rows; add tests for non-list response and partial row rejection. |
| **Cycle 1** | **CONFIRMED** (H-4) |

#### C2-3: No shift UI and `shiftMessageForRpc` unwired/incomplete

| Field | Detail |
|-------|--------|
| **Severity** | Critical (product readiness) |
| **Files** | `router.dart`, `app_routes.dart`, `application/shift_rpc_messages.dart` |
| **Evidence** | All `/shifts/*` routes render `uiPendingPlaceholder`. `shiftMessageForRpc` has zero call sites; switch omits `staff_already_assigned`, `shift_not_found`, `duplicate_staff_assignment`, `invalid_date_range`, `POSTGREST_ERROR`. |
| **Why** | Routes, guards, and nav ship ahead of presentation; error copy layer exists but is unused and incomplete. |
| **Impact** | Users with access land on placeholders; future UI will show raw PostgREST errors for common failures. |
| **Solution** | Implement screens behind existing routes; wire `shiftMessageForRpc` at error boundary; add missing cases and unit tests. |
| **Cycle 1** | **CONFIRMED** (C-1, C-2, M-7) |

---

### Second Cycle — High Priority Issues

#### H2-1: No repository port and no use-case layer

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_repository.dart`; `appointment_queue_shift_provider.dart`; `dev_clinic_seed_service.dart` |
| **Evidence** | Concrete `ShiftRepository` wired via `shiftRepositoryProvider`. Appointments and dev seed import `data/shift_repository.dart` directly. Auth uses `domain/repositories/*` + use cases; shifts have neither. |
| **Solution** | Add `domain/repositories/shift_repository.dart` port; add use cases (`ListShifts`, `ResolveQueueShiftDoctors`, etc.); type provider as port. |
| **Cycle 1** | **CONFIRMED** (H-1, H-2) |

#### H2-2: List RPC exposes assignee names only — no staff IDs (domain root cause of fragile doctor resolution)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_list_item.dart`, `shift_repository.dart`; backend `list_shifts` contract |
| **Evidence** | `ShiftListItem` has `assigneeNames` only; `get_shift_detail` returns `staff_member_id`. Appointments resolves via normalized `fullName` matching. |
| **Solution** | Extend backend `list_shifts` + `ShiftListItem` with `assignee_staff_ids`; resolve by ID in appointments. |
| **Cycle 1** | **CONFIRMED** (H-3); reframed as domain/RPC root cause |

#### H2-3: Assignee invariants unvalidated; detail parsing silently drops assignments

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_list_item.dart`, `shift_detail.dart` |
| **Evidence** | `isUnassigned`, `assigneeCount`, and `assigneeNames` parsed independently with no cross-check; `assigneeSummary` uses names length not count. `ShiftDetail.fromRpcData` drops bad assignments silently; `toListItem()` passes through `isUnassigned` while setting `assigneeCount` from assignments length. |
| **Solution** | Derive flags from parsed data; reconcile in `toListItem()`; add invariant tests. |
| **Cycle 1** | **CONFIRMED** (H-7); M-4 **UPGRADED** |

#### H2-4: Provider race — stale branch shift data can win on fast branch/timezone switch

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_shift_provider.dart` (16–50) |
| **Evidence** | `FutureProvider.autoDispose` awaits three sequential calls with no generation token or `ref.mounted` checks. Contrast: `appointment_queue_provider` clears items immediately on branch change. `listShiftsDelayedResponses` test infra exists but unused. |
| **Solution** | `AsyncNotifier` with monotonic generation counter; clear to loading/empty synchronously on branch change. |
| **Cycle 1** | **CONFIRMED** (H-8) |

#### H2-5: `listActiveStaffForBranch` inconsistent validation and unmapped table errors

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_repository.dart` (28–31 vs 128–149) |
| **Evidence** | `listShifts` throws on empty `branchId`; `listActiveStaffForBranch` returns `[]`. Table query bypasses `_invokeJsonRpc` — `PostgrestException` propagates raw, not `RpcFailure`. |
| **Solution** | Align empty-ID handling; wrap table reads with shared PostgREST→`RpcFailure` mapper; add error-path tests. |
| **Cycle 1** | **CONFIRMED** (H-5, H-6) |

#### H2-6: Sidebar exposes Shifts unconditionally; route guard denies without branch assignment

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shell_nav_config.dart`, `app_sidebar.dart`, `permission_service.dart`, `auth_route_guard.dart` |
| **Evidence** | Shifts nav item unconditional. `canViewShifts()` requires `hasBranchAssignment`. Denied users navigate then bounce to home. |
| **Solution** | Filter nav with `canViewShifts()`; gate mutations with `canManageShifts()` when UI ships. |
| **Cycle 1** | **NEW** (related to M-12) |

#### H2-7: Domain depends on auth feature (`StaffRole`)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_branch_staff.dart` |
| **Evidence** | `import '.../auth_session.dart'`; `ShiftBranchStaffMember.role` is `StaffRole`. |
| **Solution** | Move `StaffRole` to `core/domain` or shifts-local enum with mapper. |
| **Cycle 1** | **CONFIRMED** (H-9) |

#### H2-8: Production integration path has zero provider tests; domain tests give false confidence

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | No `appointment_queue_shift_provider_test.dart`; `appointment_queue_shift_doctors_test.dart` |
| **Evidence** | Domain tests build lookup manually; never exercise `_resolveQueueShiftDoctors` fallback path, branch-staff name keys, or org-wide staff fallback. |
| **Solution** | Add provider tests mirroring `appointment_calendar_provider_test.dart`; test fallback and race scenarios. |
| **Cycle 1** | **CONFIRMED** (TC-10, TC-15) |

#### H2-9: PostgREST infrastructure error mapping untested (unlike peer features)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_repository.dart`; compare `patient_repository_postgrest_error_test.dart` |
| **Evidence** | No tests for `PGRST202`→`RPC_NOT_APPLIED`, `42501`→`RPC_NOT_CONFIGURED`, `permission_denied`, `shift_overlap` with `details` preserved. |
| **Solution** | Add `shift_repository_postgrest_error_test.dart`. |
| **Cycle 1** | **CONFIRMED** (§9 gaps) |

#### H2-10: Core read/mutation repository paths undertested

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `shift_repository_test.dart` |
| **Evidence** | Missing: `listShifts` happy path, `getShiftDetail` default parse, `modifyAssignments` success/stale, `cancelShift` stale, `ShiftListItem.fromRow`, `shiftMessageForRpc`. `listShiftsPayload` and delayed-response hooks in fake client unused. |
| **Solution** | Fill gaps using `ShiftRpcTestClient` defaults. |
| **Cycle 1** | **CONFIRMED** (TC-01–TC-08, M-14) |

#### H2-11: Org-wide staff fallback can cross-contaminate branch doctor resolution

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_shift_provider.dart` (43, 90–99) |
| **Evidence** | `listStaffUseCase` returns org-wide active staff. Fallback matches by `fullName`; duplicate names across branches removed entirely (BUG-005). |
| **Solution** | Scope fallback to branch staff IDs once list RPC carries IDs. |
| **Cycle 1** | **NEW** |

#### H2-12: `_resolveQueueShiftDoctors` orchestration trapped in provider — 80 lines untestable without Riverpod

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_shift_provider.dart` |
| **Evidence** | Triple-fetch on every rebuild; logic duplicates concerns of `AppointmentQueueShiftDoctorLookup`. |
| **Solution** | Extract `ResolveQueueShiftDoctorsUseCase`; thin provider; cache by `(branchId, orgLocalDate)`. |
| **Cycle 1** | **CONFIRMED** (H-1, H-2, S-5) |

---

### Second Cycle — Medium Priority Issues

| ID | Issue | Files | Cycle 1 |
|----|-------|-------|---------|
| M2-1 | Domain entities import Flutter `foundation.dart` for `@immutable` | All domain entity files | CONFIRMED (M-1) |
| M2-2 | `ShiftCalendarMode` dead code | `shift_calendar_mode.dart` | CONFIRMED (M-2) |
| M2-3 | `ShiftDetail.fromRpcData` hacks date parsing via dummy `ShiftListItem.fromRow` | `shift_detail.dart` | CONFIRMED (M-3) |
| M2-4 | Staffed-shift business rule lives in appointments, not shifts domain | `appointment_queue_shift_doctors.dart` | NEW (domain gap) |
| M2-5 | `ShiftStatus.unknown` accepted with no domain contract; queue treats as staffed | `shift_status.dart`, `appointment_queue_shift_doctors.dart` | CONFIRMED (M-6) |
| M2-6 | No clock-time format validation in domain parsers | Domain time fields | NEW |
| M2-7 | Success-path shape failures throw `StateError`, not `RpcFailure` | `shift_repository.dart` | CONFIRMED (M-8) |
| M2-8 | Backend `invalid_input` not mapped in `_extractShiftErrorCode` | `shift_repository.dart` | NEW |
| M2-9 | RPC errors not logged before rethrow | `shift_repository.dart` | CONFIRMED (M-9) |
| M2-10 | Overlap message fallback fragile when DETAIL channel empty | `shift_overlap_conflict.dart` | CONFIRMED (M-13) |
| M2-11 | `ShiftBranchStaffMember` silently drops inactive/malformed rows | `shift_branch_staff.dart` | CONFIRMED (test gap) |
| M2-12 | Shift lookup never invalidated after shift mutations (only seed/reset) | `appointment_surface_invalidation.dart` | NEW |
| M2-13 | Overnight shifts not handled in appointment time-window matching | `appointment_queue_shift_doctors.dart` | CONFIRMED (M-5) |
| M2-14 | Provider RPC failures surface as `AsyncError` — no degraded-empty policy | `appointment_queue_shift_provider.dart` | NEW |
| M2-15 | Shift detail route uses view permission only — no manage gate for future mutations | `auth_route_guard.dart` | CONFIRMED (M-12) |
| M2-16 | No shift route-guard or boundary tests (unlike peer features) | `auth_route_guard.dart`, `test/boundary/` | CONFIRMED |
| M2-17 | Riverpod provider typed to concrete `ShiftRepository` | `shift_repository.dart` | Extension of H-1 |
| M2-18 | No shift cubits/controllers — architectural debt, not current runtime risk | `features/shifts/` | Deferred (C-1 product gap) |

---

### Second Cycle — First-Cycle Disposition

| Cycle 1 ID | Second-Cycle Status |
|------------|---------------------|
| C-1 No presentation | **CONFIRMED** → C2-3 |
| C-2 `shiftMessageForRpc` unused | **CONFIRMED** → C2-3 |
| H-1 No repository port | **CONFIRMED** → H2-1 |
| H-2 No use cases | **CONFIRMED** → H2-1, H2-12 |
| H-3 Name-based resolution | **CONFIRMED** → H2-2 (root cause identified) |
| H-4 Silent `listShifts` drops | **CONFIRMED** → C2-2 |
| H-5 Empty branch staff | **CONFIRMED** → H2-5 |
| H-6 Mixed RPC/table access | **CONFIRMED** → H2-5 |
| H-7 Assignee count mismatch | **CONFIRMED** → H2-3 |
| H-8 Provider race | **CONFIRMED** → H2-4 |
| H-9 Domain imports auth | **CONFIRMED** → H2-7 |
| M-1–M-14 | **CONFIRMED** or reframed in M2-* table |
| L-6 Rejects float `assignee_count` | **INVALIDATED** — `num` accepts double; `toInt()` works |
| TC-01–TC-16 | **Still open** except TC-12/TC-16 partial |

**New in cycle 2:** C2-1 (orphaned provider wire), H2-6 (nav/permission drift), H2-11 (org-wide fallback contamination), M2-4/M2-6/M2-12/M2-14.

---

### Second Cycle — Test Coverage Summary

Per [tests & reliability review](95921fd0-42c4-42fe-a68d-a8a0e8504e2b): **16 of 16 first-cycle test gaps (TC-01–TC-16) remain open or partial.** No flaky shift tests observed (suite is small and synchronous), but **false confidence is high** — overlap parsing, notes clearing, and dedupe tests are solid while the production integration path (`appointmentQueueShiftDoctorLookupProvider`) has zero tests.

`shift_rpc_test_client.dart` exposes unused hooks (`listShiftsPayload`, `listShiftsDenied`, `listShiftsDelayedResponses`, `modifyAssignmentsException`, `cancelShiftException`) that suggest planned coverage never written. Missing shift cubits remain architectural debt (T2-8), not a current runtime test risk while UI is placeholder-only.

| Repository method | Cycle-2 test status |
|-------------------|---------------------|
| `listShifts` | 366-day guard only |
| `createShift` | Dedupe, duplicate key, list-wrapped ID |
| `getShiftDetail` | Read-only override only |
| `modifyAssignments` | Dedupe params only |
| `cancelShift` | Params only (no stale) |
| `listActiveStaffForBranch` | One happy path |
| Provider integration | **None** |

---

### Second Cycle — Prioritized Actions

1. **Wire** `appointmentQueueShiftDoctorLookupProvider` into queue domain call sites (C2-1).
2. **Fail loudly** on `listShifts` parse/shape errors (C2-2).
3. **Add** `appointment_queue_shift_provider_test.dart` with race and fallback scenarios (H2-8).
4. **Extend** `list_shifts` RPC with assignee staff IDs (H2-2).
5. **Add** repository port + `ResolveQueueShiftDoctorsUseCase` (H2-1, H2-12).
6. **Filter** sidebar Shifts nav with `canViewShifts()` (H2-6).
7. **Implement** shift UI + wire `shiftMessageForRpc` when screens land (C2-3).

---

*Review performed by static analysis of source and tests. Backend RPC contracts referenced via `backend/tests/shift_management_*.sql`. Second cycle: four parallel agent reviews consolidated 2026-07-05.*
