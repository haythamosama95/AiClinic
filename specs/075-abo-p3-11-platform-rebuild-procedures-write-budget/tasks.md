# Tasks: Platform rebuild procedures and the write budget

**Input**: Design documents from `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P3.10: None. Plan artifacts from `AVAILABLE_DOCS`: `research.md`. There is no `data-model.md` and no `contracts/`. `research.md` is the R-7 spike already written in plan; it is not an implement task. `quickstart.md` is written in Documentation after verification.

**Organization**: Two user stories, as the spec partitions them (`[US1]`, `[US2]`). Tests are one task per E2E id in Sequencing steps 1–5, written to fail before the three class-H methods and the write measurement exist. Test Layout names no extra test file. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase. No Polish phase. Task ids follow plan Sequencing. Sequencing step 17 is two tasks: the load harness, then `quickstart.md`.

**Task count**: 18. Size M is 20–32 (rule S3). The count is five E2E tasks (Sequencing steps 1–5), ten implementation steps (6–15), the system harness (step 16), the load harness (step 17), and `quickstart.md`. It is not padded. `npm test`, `npm run test:load`, and other packages are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — the Files paths in `plan.md`
- **ABO**: `abo/` — this unit does not change it
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified
- **Spec Kit artifacts**: `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/`
- Do not edit `packages/vendor-contracts/**`. Do not add a migration, route, cron, alarm, or RPC. Do not call a Time Travel API. `ai-platform/package.json` script `test:load` stays pointed at `test/load/load-and-cost.test.ts`. Do not implement ABO rebuild (P4.11), backend projection rebuild (P5.2), the NFR-08 allowance check (P8.1), outage overshoot (P3.9), the 03 §6.7 events bullet (P3.3), or the 03 §6.7 alarm bullet (P3.5).

---

## 3. Tests

**Purpose**: One failing test per E2E id in Sequencing steps 1–5, under H-AP, in that order. Story sections follow that order. E2E-P3.11-01 through E2E-P3.11-04 are added to `ai-platform/test/system/platform-rebuild.system.test.ts`. E2E-P3.11-05 is added to `ai-platform/test/load/write-budget.load.test.ts`. Both run under `vitest.workers.config.ts`. Class-H calls use `vendorCall(method, args, { accessJwt })` with the harness Access JWT. No assertion object. No `sleep` over 2 s. Time moves with the existing test clock (rule V4). A class-H success is `result` `ok`, `code` empty, `receipt` absent, and `detail` the JSON text named in the task. `invokeClassH` already returns `unauthenticated` when the access JWT is missing. These tests always send the harness JWT.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/platform-rebuild.system.test.ts
```

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/load/write-budget.load.test.ts
```

### 3.1 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1)

**Independent Test**: E2E-P3.11-01, E2E-P3.11-02, E2E-P3.11-03, and E2E-P3.11-04 in harness H-AP.

- [X] T001 [US1] Add the failing test `E2E-P3.11-01 FM-20 wiped DO rebuilds terms positions holds and usage and the compare is clean` in `ai-platform/test/system/platform-rebuild.system.test.ts` — red test, FR-001, E2E-P3.11-01. `newClinic` and `coverClinic` leave a clinic with terms, positions, holds, and settled usage, plus one admitted request that has not settled. Record the DO `term` rows and `hot.used`. Wipe that DO with `runInDurableObject` on that clinic's stub by deleting the DO `hot`, `term`, `grant`, and `outbox` rows. `vendorCall("rebuildClinicDo", { installation_id })`. Afterward each `term` row matches the pre-loss `term_id`, `position`, `state`, hold, allowance, and used; `hot.used` matches; `hot.reservations` is `[]` and `hot.reserved` is 0. `detail` is `{"compare":"clean","installation_id":"<id>"}`. No `platform_alert` row with `alert_key` `do-rebuild:<id>`. The system command fails because `rebuildClinicDo` is not a method.

- [X] T002 [US1] Add the failing test `E2E-P3.11-02 a rebuild that diverges from the mirror alerts` in `ai-platform/test/system/platform-rebuild.system.test.ts` — red test, FR-002, E2E-P3.11-02. Depends on T001 (same file). Same setup as E2E-P3.11-01. Before the wipe, change `coverage_mirror.state` for that installation so it cannot match the rebuilt DO. Wipe and `vendorCall("rebuildClinicDo")`. `platform_alert` has `alert_key` `do-rebuild:<installation_id>`, `code` `do_rebuild_mismatch`, `severity` `high`, `send_state` `unsent`. The platform alert is a `platform_alert` row (rule V6). The system command fails because a divergent rebuild does not write `platform_alert`.

- [X] T003 [US1] Add the failing test `E2E-P3.11-03 grant_ledger truncated rebuilds from R2 identical` in `ai-platform/test/system/platform-rebuild.system.test.ts` — red test, FR-003, E2E-P3.11-03. Depends on T002 (same file). After the grant's R2 object exists (`grant-ledger/<grant_id>.ndjson`, written by the existing grant ship), copy `grant_ledger` and `grant_void` for that clinic. Drop `grant_ledger_no_delete` and `grant_void_no_delete`, delete the rows, and recreate those two triggers. The product method never deletes. `vendorCall("rebuildGrantLedger")`. Reloaded rows match the copy on `grant_id`, `origin_grant_id`, `org_id`, `installation_id`, `kind`, `source_kind`, `operator_credential_id`, `envelope_sha256`, `receipt`, and `applied_at`, and void rows match on `grant_id`, `reason`, `source`, `evidence_sha256`, and `at`. `detail` is `{"grant_ledger":<n>,"grant_void":<m>}` for the objects listed. The system command fails because `rebuildGrantLedger` is not a method.

- [X] T004 [US1] Add the failing test `E2E-P3.11-04 snapshot refresh writes one coverage_event and updates the mirror` in `ai-platform/test/system/platform-rebuild.system.test.ts` — red test, FR-004, E2E-P3.11-04. Depends on T003 (same file). Note the installation's `coverage_event` count and `coverage_mirror.clinic_seq`. `vendorCall("refreshCoverageSnapshot", { installation_id })`. Exactly one new `coverage_event` exists for that installation, `kind` `snapshot`, and `coverage_mirror` for that installation matches the new event's snapshot, `binding_epoch`, and `clinic_seq`. `detail` is `{"event_id":"<id>","installation_id":"<id>"}`. The system command fails because `refreshCoverageSnapshot` is not a method.

**Checkpoint**: E2E-P3.11-01, E2E-P3.11-02, E2E-P3.11-03, and E2E-P3.11-04 exist and fail.

### 3.2 User Story 2 - Measure the write budget across exhaustion (Priority: P2)

**Independent Test**: E2E-P3.11-05 in the H-AP load suite. Every earlier suite stays green (rule S2).

- [X] T005 [US2] Add the failing test `E2E-P3.11-05 A34 100 concurrent requests across exhaustion stay inside the write budget` in `ai-platform/test/load/write-budget.load.test.ts` — red test, FR-005, FR-006, E2E-P3.11-05. Depends on T004. `coverClinic` with an allowance the 100 requests cross, and no queued successor. `w_max` is the published capability quota weight the existing admission tests call `W_MAX`. `Promise.all` of 100 `SELF.fetch` `POST /v1/requests` on `ai-platform/src/worker.ts`. Exactly one term ends `exhausted`. That term's usage beyond its allowance is ≤ `w_max − 1`, charged to the term that exhausted. A later term is not charged. For every request, `hot` writes are ≤ 2. `term`, `grant`, and `outbox` writes are 0 on every request except the one that exhausts the term. Counts come from `total_changes()` inside admission and settlement, read back through `runInDurableObject`. The load command fails because per-request `hot` write counts are not recorded.

**Checkpoint**: E2E-P3.11-05 exists and fails.

---

## 4. Implementation

**Purpose**: Sequencing steps 6–15. Each step starts after T001–T005 exist and fail. Within a subphase the tasks run in id order. The D1 rebuild stays `rebuildGrantLedger`, a class-H method separate from `refreshCoverageSnapshot`. No new route, cron, alarm, or RPC.

### 4.1 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1) (part 1)

**Independent Test**: E2E-P3.11-01, E2E-P3.11-02, E2E-P3.11-03, and E2E-P3.11-04 in harness H-AP.

- [X] T006 [US1] Register `rebuildClinicDo`, `rebuildGrantLedger`, and `refreshCoverageSnapshot` as class H — produces the three methods on `VendorEntrypoint`, FR-001, FR-003, FR-004, E2E-P3.11-01, E2E-P3.11-03, E2E-P3.11-04. Depends on T005. Files: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/test/system/harness.ts`. Add the three names to `METHOD_CLASS` as `"H"` and to the harness `VendorMethod` union. Each method is `invokeClassH` (`verifyHpAccess` on `access_jwt`, vendor-channel `negotiate`). No passkey assertion. `rebuildClinicDo` and `refreshCoverageSnapshot` require `installation_id` and return `rejected` `missing_installation_id` when it is absent. An installation with no `coverage_event` returns `rejected` `not_found`. `rebuildGrantLedger` does not call `refreshCoverageSnapshot`.

- [X] T007 [US1] Add `terms` to `buildCoverageSnapshot` in `ai-platform/src/quota-do/coverage.ts` — produces the snapshot shape the rebuild loads, FR-001, FR-004, E2E-P3.11-01, E2E-P3.11-04. Depends on T006. Keep every key and value that function writes today. Add `terms`: one object per DO `term` row, `{term_id, position, state, end_reason, allowance, used, duration_unit, duration_count, starts_at, ends_at, grace_ends_at, held}`. `held` is true when `state` is `held`. `used` is `hot.used` for the active term and `used_final` otherwise. Do not put in-flight reservations on this object. `suspended`, `binding_epoch`, and `clinic_seq` stay the existing keys. The DO schema stays the §3.2 `hot` row.

- [X] T008 [US1] Load the last `coverage_event` into an empty DO in `rebuildClinicDo` — produces the wiped-DO load, FR-001, E2E-P3.11-01. Depends on T007. File: `ai-platform/src/quota-do/coverage.ts`, called from `VendorEntrypoint.rebuildClinicDo` in `ai-platform/src/vendor/entrypoint.ts`. Delete that clinic's DO `hot`, `term`, `grant`, and `outbox` rows, then load the last `coverage_event` (highest `clinic_seq`) into `hot` and `term` from that snapshot, including `terms`. `hot.reservations` is `[]` and `hot.reserved` is 0. Do not write a new `coverage_event`.

- [X] T009 [US1] Apply later ledger, void, and hold events in `rebuildClinicDo` — produces the post-snapshot replay, FR-001, E2E-P3.11-01. Depends on T008. File: `ai-platform/src/quota-do/coverage.ts`. Apply rows with time after the snapshot `at`, in order: `grant_ledger` (`applied_at`), `grant_void` (`at`), then `coverage_event` kinds `term_held`, `term_released`, `suspension_changed`, and `transfer` (`clinic_seq` greater than the snapshot). Ledger and void application updates DO `term` and `hot` only. It does not insert another `grant_ledger` or `grant_void` row.

- [X] T010 [US1] Re-apply `usage_event` after the snapshot in `rebuildClinicDo` — produces usage without double counting, FR-001, E2E-P3.11-01. Depends on T009. File: `ai-platform/src/quota-do/coverage.ts`. Re-apply `usage_event` rows for those `term_id`s with `recorded_at` after the snapshot `at`, including rows shipped from `usage_adjustment`. Add `quota_weight` to that term's used. A repeated `request_id` is applied once.

**Checkpoint**: E2E-P3.11-01 has its class-H method through usage re-apply. The compare, the D1 rebuild, and the snapshot refresh are still absent. The unit file is not required to pass until verification.

### 4.2 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1) (part 2)

**Independent Test**: E2E-P3.11-01, E2E-P3.11-02, E2E-P3.11-03, and E2E-P3.11-04 in harness H-AP.

- [X] T011 [US1] Compare the rebuilt DO with `coverage_mirror` and alert on mismatch — produces the clean compare and the platform alert, FR-001, FR-002, E2E-P3.11-01, E2E-P3.11-02. Depends on T010. Files: `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/alert/index.ts`. Compare `state`, `suspended`, `binding_epoch`, `clinic_seq`, and the snapshot JSON. A match returns `ok` with `detail` `{"compare":"clean","installation_id":"<id>"}` and writes no alert. A mismatch calls a new export in `src/alert/index.ts` that inserts `platform_alert` (`alert_key` `do-rebuild:<installation_id>`, `code` `do_rebuild_mismatch`, `severity` `high`, `count` 1, `send_state` `unsent`) using the same column list as the existing alert insert. The method still returns `ok`; the alert is the compare outcome.

- [X] T012 [US1] Rebuild `grant_ledger` and `grant_void` from R2 in `rebuildGrantLedger` — produces the D1 rebuild, FR-003, E2E-P3.11-03. Depends on T011. File: `ai-platform/src/quota-do/coverage.ts`, called from `VendorEntrypoint.rebuildGrantLedger` in `ai-platform/src/vendor/entrypoint.ts`. List R2 prefix `grant-ledger/`. An object whose key ends in `.void.ndjson` inserts `grant_void` from that JSON (`grant_id`, `reason`, `source`, `evidence_sha256`, `at`). Any other object under that prefix inserts `grant_ledger` from that JSON (`grant_id`, `origin_grant_id`, `org_id`, `installation_id`, `kind`, `source_kind`, `operator_credential_id`, `envelope_sha256`, `receipt`, `applied_at`). Both inserts are `INSERT OR IGNORE`. `detail` is `{"grant_ledger":<n>,"grant_void":<m>}`. This method does not call `refreshCoverageSnapshot`. It does not delete ledger or void rows. It does not call a Time Travel API.

- [X] T013 [US1] Emit one snapshot `coverage_event` in `refreshCoverageSnapshot` — produces the per-installation snapshot, FR-004, E2E-P3.11-04. Depends on T012. File: `ai-platform/src/quota-do/coverage.ts`, called from `VendorEntrypoint.refreshCoverageSnapshot` in `ai-platform/src/vendor/entrypoint.ts`. Ask that installation's DO to append one outbox `coverage_event` with `kind` `snapshot`, the current snapshot, and `clinic_seq` one higher, then run the existing outbox ship so D1 `coverage_event` gains that row and `coverage_mirror` is replaced from it. One call, one installation. `detail` is `{"event_id":"<id>","installation_id":"<id>"}`.

**Checkpoint**: E2E-P3.11-01 through E2E-P3.11-04 have their class-H methods. The unit file is not required to pass until verification.

### 4.3 User Story 2 - Measure the write budget across exhaustion (Priority: P2)

**Independent Test**: E2E-P3.11-05 in the H-AP load suite.

- [X] T014 [US2] Count `hot` and event writes inside admission and settlement — produces per-request write counts, FR-006, E2E-P3.11-05. Depends on T013. File: `ai-platform/src/quota-do/index.ts`. In `admitOnHotRow` and `settleReservationOnHot`, read `total_changes()` before and after the writes. Count a write to `hot` as a `hot` write. Count a write to `term`, `grant`, or `outbox` as an event write. Keep the sums for that `request_id` in memory on the DO isolate (a module map in `src/quota-do/index.ts` that `runInDurableObject` can read). Do not add a column, a table, or an HTTP field. `ai-platform/src/worker.ts` stays unchanged: do not copy the counts onto the `POST /v1/requests` response. `scheduleOutboxAlarmIfPending` stays outside the count.

**Checkpoint**: E2E-P3.11-05 can read per-request write counts. The load file is not required to pass until verification.

### 4.4 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1) — expected snapshot terms

**Independent Test**: E2E-P3.11-01 and E2E-P3.11-04 in harness H-AP.

- [X] T015 [US1] Add `terms` to expected `buildCoverageSnapshot` objects that fail — produces the same snapshot keys plus `terms`, FR-001, FR-004, E2E-P3.11-01, E2E-P3.11-04. Depends on T014. Where an earlier test fails because `buildCoverageSnapshot` now includes `terms`, add `terms` to that expected object. Leave the previous keys and the admission, settlement, and feed behavior as they are. Edit only those failing expected objects under `ai-platform/test/`. Do not change `ai-platform/test/system/platform-rebuild.system.test.ts` or `ai-platform/test/load/write-budget.load.test.ts` in this task.

**Checkpoint**: Expected snapshot objects that compare `buildCoverageSnapshot` include `terms`. Admission, settlement, and feed behavior stay as they are.

---

## 5. Verification

**Purpose**: The two harness commands in Test Layout pass. These commands are the harnesses for this unit. A repository-root `npm test` is not a task. `npm run test:load` is not a task.

### 5.1 Unit harness — system

- [X] T016 [US1] Run harness H-AP for the system file and confirm E2E-P3.11-01 through E2E-P3.11-04 pass — produces the green system file, FR-001, FR-002, FR-003, FR-004, E2E-P3.11-01, E2E-P3.11-02, E2E-P3.11-03, E2E-P3.11-04. Depends on T006 through T015 (and therefore on T001–T005). This task may edit only `ai-platform/test/system/platform-rebuild.system.test.ts`. `packages/vendor-contracts/**` stays unchanged.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/platform-rebuild.system.test.ts
```

### 5.2 Unit harness — load

- [X] T017 [US2] Run the H-AP load suite file and confirm E2E-P3.11-05 passes — produces the green load file, FR-005, FR-006, E2E-P3.11-05. Depends on T006 through T015 (and therefore on T001–T005). This task may edit only `ai-platform/test/load/write-budget.load.test.ts`.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/load/write-budget.load.test.ts
```

**Checkpoint**: E2E-P3.11-01 through E2E-P3.11-05 pass.

---

## 6. Documentation

**Purpose**: Written after T016 and T017 are green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 6.1 Quickstart

- [ ] T018 Create `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-006, E2E-P3.11-01 through E2E-P3.11-05. Depends on T016 and T017. Sections: (1) what was implemented — `rebuildClinicDo`, `rebuildGrantLedger`, and `refreshCoverageSnapshot` on `VendorEntrypoint`, and the write-budget measurement on `POST /v1/requests`; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) the two harness commands below; (4) the entry point → module chain per E2E id below. `npm test`, `npm run test:load`, and other packages stay out of these commands (rule S8).

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/platform-rebuild.system.test.ts
```

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/load/write-budget.load.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P3.11-01 | `vendorCall("rebuildClinicDo")` → `VendorEntrypoint.rebuildClinicDo` → `src/quota-do/coverage.ts` load of the last `coverage_event`, later `grant_ledger` / `grant_void` / hold events, and `usage_event` → DO `term` and `hot`. |
| E2E-P3.11-02 | `vendorCall("rebuildClinicDo")` → the same rebuild → compare with `coverage_mirror` → `src/alert/index.ts` insert into `platform_alert`. |
| E2E-P3.11-03 | `vendorCall("rebuildGrantLedger")` → `src/quota-do/coverage.ts` list of R2 `grant-ledger/` → `INSERT OR IGNORE` into `grant_ledger` and `grant_void`. |
| E2E-P3.11-04 | `vendorCall("refreshCoverageSnapshot")` → DO outbox `coverage_event` → existing ship into D1 `coverage_event` and `coverage_mirror`. |
| E2E-P3.11-05 | `SELF.fetch` `POST /v1/requests` → `worker.ts` admission and credit on `GatewayObject` → `admitOnHotRow` / `settleReservationOnHot` in `src/quota-do/index.ts`. The test reads the in-memory write counts from inside `runInDurableObject`. |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests**: T001 through T005, in Sequencing steps 1–5. No Setup phase. T001 starts immediately. T002 through T004 append to `ai-platform/test/system/platform-rebuild.system.test.ts`. T005 creates `ai-platform/test/load/write-budget.load.test.ts`.
- **Implementation**: T006 through T015, after those tests exist and fail. T006 is Sequencing step 6. T007 through T010 are steps 7–10. T011 through T013 are steps 11–13. T014 is step 14. T015 is step 15.
- **Verification**: T016 is Sequencing step 16, after T006 through T015. T017 is the load run in Sequencing step 17, after T006 through T015.
- **Documentation**: T018, after T016 and T017 are green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001 through T004 are the first tests. T006 through T013 add `rebuildClinicDo`, `rebuildGrantLedger`, and `refreshCoverageSnapshot`. T006 writes `ai-platform/src/vendor/entrypoint.ts` and `ai-platform/test/system/harness.ts`. T007 through T013 stay in `ai-platform/src/quota-do/coverage.ts`, and T011 also writes `ai-platform/src/alert/index.ts`. T015 adds `terms` to earlier expected snapshot objects after that shape exists. E2E-P3.11-01 through E2E-P3.11-04 are confirmed at T016.
- **User Story 2 (P2)**: T005 follows T004. T014 edits `ai-platform/src/quota-do/index.ts` after T013 and leaves `ai-platform/src/worker.ts` unchanged. E2E-P3.11-05 is confirmed at T017.

### 7.3 Parallel Opportunities

- T001–T004 are not separate launches. They all write `ai-platform/test/system/platform-rebuild.system.test.ts`.
- T006 writes `ai-platform/src/vendor/entrypoint.ts` and `ai-platform/test/system/harness.ts` before T007.
- T007–T013 share `ai-platform/src/quota-do/coverage.ts`. T008 through T013 also share `ai-platform/src/vendor/entrypoint.ts` with T006. They stay in id order.
- T011 also writes `ai-platform/src/alert/index.ts` after T010.
- T014 writes only `ai-platform/src/quota-do/index.ts` and follows T013.
- T015 follows T014 and edits failing expected objects under `ai-platform/test/`, not the two new test files.
- T016 writes only `ai-platform/test/system/platform-rebuild.system.test.ts`. T017 writes only `ai-platform/test/load/write-budget.load.test.ts`. Both follow T015. They do not share a path.
- T018 writes only `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/quickstart.md` and waits until T016 and T017 are green.

---

## 8. Implementation Waves

### Wave 1

- T001–T004 [US1] — subphase: `### 3.1 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1)` — paths: `ai-platform/test/system/platform-rebuild.system.test.ts`

### Wave 2

- T005 [US2] — subphase: `### 3.2 User Story 2 - Measure the write budget across exhaustion (Priority: P2)` — paths: `ai-platform/test/load/write-budget.load.test.ts`

### Wave 3

- T006–T010 [US1] — subphase: `### 4.1 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1) (part 1)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/test/system/harness.ts`, `ai-platform/src/quota-do/coverage.ts`

### Wave 4

- T011–T013 [US1] — subphase: `### 4.2 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1) (part 2)` — paths: `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/alert/index.ts`, `ai-platform/src/vendor/entrypoint.ts`

### Wave 5

- T014 [US2] — subphase: `### 4.3 User Story 2 - Measure the write budget across exhaustion (Priority: P2)` — paths: `ai-platform/src/quota-do/index.ts`

### Wave 6

- T015 [US1] — subphase: `### 4.4 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1) — expected snapshot terms` — paths: `ai-platform/test/`

### Wave 7

- T016 [US1] — subphase: `### 5.1 Unit harness — system` — paths: `ai-platform/test/system/platform-rebuild.system.test.ts`
- T017 [US2] — subphase: `### 5.2 Unit harness — load` — paths: `ai-platform/test/load/write-budget.load.test.ts`

### Wave 8

- T018 — subphase: `### 6.1 Quickstart` — paths: `specs/075-abo-p3-11-platform-rebuild-procedures-write-budget/quickstart.md`
