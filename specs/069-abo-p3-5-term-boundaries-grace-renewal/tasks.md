# Tasks: Term boundaries, grace and renewal

**Input**: Design documents from `specs/069-abo-p3-5-term-boundaries-grace-renewal/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged unit in **Consumes Binding**: P3.4 (admission answer, clinic denial codes, CP-B). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/` (`contracts/coverage-snapshot-grace-lapse.md`). There is no `research.md`. `quickstart.md` is written in Documentation after verification.

**Organization**: Two user stories, as the spec partitions them (`[US1]`, `[US2]`). Tests are one task per E2E id in the spec Test plan, written to fail before the boundary loop applies these transitions. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase. No Polish phase. Task ids follow plan Sequencing, except Sequencing step 19.

**Task count**: 19. Size M is 20–32 (rule S3). The count is eight E2E tasks (Sequencing steps 1–8), nine implementation tasks (steps 9–17), one verification task (the unit harness, step 18), and `quickstart.md` (step 20). It is not padded. `cd ai-platform && npm test && npm run test:e2e` is the review's earlier-suite run (SC-002, rule S2, Sequencing step 19), not a task.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — the Files paths in `plan.md`
- **ABO**: `abo/` — this unit does not change it. The harness does not start an ABO worker.
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified (rule S7)
- **Spec Kit artifacts**: `specs/069-abo-p3-5-term-boundaries-grace-renewal/`
- `data-model.md` and `contracts/` stay plan-phase artifacts. `ai-platform/src/coverage/calendar.ts`, `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/admission/index.ts`, `ai-platform/src/errors.ts`, `ai-platform/test/system/harness.ts`, and `packages/vendor-contracts/**` stay as they are. `grant_void` is not added (reversals are P3.7). Fallback reads of `hard_stop_at` stay in P3.9. Entitlement tables and `/control/*` stay until P3.10 (rule S9).

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts`. The unit command is that file only. `coverClinic()` is the paid-grant helper in `ai-platform/test/system/harness.ts`. It already sends `grace: { days: 7, cap_rule: "proportional" }` and calls `vendorCall` `grant`, then `runDurableObjectAlarm`. The test sets `setTestClock` before `coverClinic()` so the grant's `nowIso` is the worked instant. Term and `hot` rows are read with `runInDurableObject`. No `sleep` over 2 s. No ABO worker is constructed. Do not modify `packages/vendor-contracts`. Do not edit `coverClinic()`.

### 3.1 User Story 1 - Apply the term boundary (Priority: P1) (part 1)

**Independent Test**: E2E-P3.5-01, E2E-P3.5-02, E2E-P3.5-03, E2E-P3.5-06, E2E-P3.5-07, and E2E-P3.5-08 in harness H-AP, with the test clock and `runDurableObjectAlarm` (rule V4).

- [ ] T001 [US1] Add the failing test `E2E-P3.5-01 A9 renewal paid five days early queues and activates at the old end` in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — red test, FR-001, FR-002, E2E-P3.5-01. Clock at 1 Mar 10:00, `coverClinic()` once. Clock at 27 Mar, `coverClinic()` again. T2 is `queued`. T1 `allowance` and `used` are unchanged. Clock at 1 Apr 10:00, `runDurableObjectAlarm`. T1 is `ended` with `end_reason` `expired`. T2 is `active` with `starts_at` and `calendar_start` 1 Apr 10:00, `ends_at` 1 May 10:00, and a full allowance. Run:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/term-boundaries-grace-renewal.system.test.ts
```

The run fails because the alarm at T1 `ends_at` does not end T1 `expired` and activate T2 from that instant.

- [ ] T002 [US1] Add the failing test `E2E-P3.5-02 A10 unpaid end enters grace then lapses as expired` in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — red test, FR-003, FR-004, E2E-P3.5-02. Depends on T001 (same file). `coverClinic()` once. Clock at `ends_at`, `runDurableObjectAlarm`. State is grace. `POST /v1/requests` inside the grace cap is admitted and `usage_event.term_id` is that same term. Clock at `grace_ends_at`, `runDurableObjectAlarm`, then `POST /v1/requests` is 403 `coverage_lapsed` with `coverage_reason` `expired`. The test file does not start an ABO worker. The unit command fails because an unpaid `ends_at` does not enter grace, and `grace_ends_at` does not lapse with `coverage_lapsed` reason `expired`.

- [ ] T003 [US1] Add the failing test `E2E-P3.5-03 The reservation that takes the last grace credit ends grace_exhausted` in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — red test, FR-005, E2E-P3.5-03. Depends on T002 (same file). `coverClinic()`, then the boundary loop into grace. `POST /v1/requests` until a reservation takes the last of the grace allowance. That term is `ended` with `end_reason` `grace_exhausted`. The next `POST` is 403 `coverage_lapsed` with `coverage_reason` `grace_exhausted`. The unit command fails because taking the last grace credit does not end the term `grace_exhausted`.

**Checkpoint**: E2E-P3.5-01, E2E-P3.5-02, and E2E-P3.5-03 exist and fail.

### 3.2 User Story 2 - Grant during grace or after lapse (Priority: P2)

**Independent Test**: E2E-P3.5-04 and E2E-P3.5-05 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [ ] T004 [US2] Add the failing test `E2E-P3.5-04 A grant on day three of grace keeps the old calendar` in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — red test, FR-006, E2E-P3.5-04. Depends on T003 (same file). T1 `ends_at` is 1 Mar 10:00 and the clinic is in grace. Clock at 4 Mar, `coverClinic()`. The new term is `active` with `calendar_start` 1 Mar 10:00 and `ends_at` 1 Apr 10:00. T1 is `ended` with `end_reason` `renewed` and `used_final` still holding the grace usage. The unit command fails because a second `coverClinic()` during grace does not leave T1's grace usage on T1 with the new `calendar_start` at T1 `ends_at`.

- [ ] T005 [US2] Add the failing test `E2E-P3.5-05 A11 a lapsed clinic paid two months later starts now` in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — red test, FR-007, E2E-P3.5-05. Depends on T004 (same file). T1 ends 1 Mar 10:00, grace runs to 8 Mar 10:00, clinic is `lapsed`. Clock at 1 May 14:00, `coverClinic()`. The new term is `active` from 1 May 14:00 to 1 Jun 14:00. The unit command fails because a grant after lapse does not open a term from the payment instant.

**Checkpoint**: E2E-P3.5-04 and E2E-P3.5-05 exist and fail.

### 3.3 User Story 1 - Apply the term boundary (Priority: P1) (part 2)

**Independent Test**: E2E-P3.5-01, E2E-P3.5-02, E2E-P3.5-03, E2E-P3.5-06, E2E-P3.5-07, and E2E-P3.5-08 in harness H-AP, with the test clock and `runDurableObjectAlarm` (rule V4).

- [ ] T006 [US1] Add the failing test `E2E-P3.5-06 A skipped alarm is applied by the next admission` in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — red test, FR-008, E2E-P3.5-06. Depends on T005 (same file). Clock moves past `grace_ends_at` with no `runDurableObjectAlarm`. The next `POST /v1/requests` is 403 `coverage_lapsed` with `coverage_reason` `expired`. The unit command fails because a `POST` after a skipped alarm still treats the clinic as inside grace.

- [ ] T007 [US1] Add the failing test `E2E-P3.5-07 Staging DURATION_SCALE compresses the month and the grace window` in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — red test, FR-009, E2E-P3.5-07. Depends on T006 (same file). Set `DURATION_SCALE` to `staging` on the worker binding the way `ai-platform/test/system/paid-grant-coverage.system.test.ts` does, and restore it afterwards. A monthly term's `ends_at` is 30 minutes after `calendar_start`. After the end boundary, `grace_ends_at` is 7 minutes after `ends_at`. `runDurableObjectAlarm` and `POST /v1/requests` see those instants. The unit command fails because the staging scale does not place the monthly end at 30 minutes and grace at 7 minutes.

- [ ] T008 [US1] Add the failing test `E2E-P3.5-08 Activate, end, and grace start ship events and hard_stop_at` in `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts` — red test, FR-001, FR-010, E2E-P3.5-08. Depends on T007 (same file). After `runDurableObjectAlarm` on a grant that activates, on an end with a successor, and on a grace start, `coverage_event` has `term_activated`, `term_ended`, and `grace_started`. `coverage_mirror.hard_stop_at` equals `ends_at` while active and `grace_ends_at` while in grace. The unit command fails because `grace_started` is absent and `coverage_mirror.hard_stop_at` is null.

**Checkpoint**: E2E-P3.5-06, E2E-P3.5-07, and E2E-P3.5-08 exist and fail. User Story 1's six tests are red.

---

## 4. Implementation

**Purpose**: Sequencing steps 9–17. Each step starts after T001–T008 exist and fail. Within a subphase the tasks run in id order. Dates use the existing `addDuration` in `ai-platform/src/coverage/calendar.ts`. Do not edit that file. The boundary compares stored instants to `clockNowIso`, not to the alarm's scheduled timestamp. `term.grace_cap` stays the rule text `proportional`. Do not edit `VendorEntrypoint.grant` or `coverClinic()`. Do not add a denial code. Do not rewrite the admission answer (reservation, `term_id`, snapshot, band).

### 4.1 User Story 1 - Apply the term boundary (Priority: P1) (part 1)

**Independent Test**: E2E-P3.5-01, E2E-P3.5-02, E2E-P3.5-03, E2E-P3.5-06, E2E-P3.5-07, and E2E-P3.5-08 in harness H-AP, with the test clock and `runDurableObjectAlarm` (rule V4).

- [ ] T009 [US1] Add `applyDueBoundaries` in `ai-platform/src/quota-do/coverage.ts` and call it from admission step 3 in `ai-platform/src/quota-do/index.ts` in place of the P3.5 no-op, inside the existing `blockConcurrencyWhile`, before the refusal order — produces successor activation on admission, FR-002, FR-008, E2E-P3.5-01. Depends on T008. When the active term's `ends_at` is due and a `queued` term exists, end the active term `expired` and activate the successor with `starts_at` and `calendar_start` equal to that `ends_at`, `ends_at` from `addDuration`, and `hot.used` reset to 0. Emit `term_ended` then `term_activated` through the existing `coverage_event` outbox. Repeat until no transition applies. The alarm path still skips this, so E2E-P3.5-01 still fails when only the alarm runs.

- [ ] T010 [US1] Call `applyDueBoundaries` at the start of `shipCoverageOutboxAlarm` in `ai-platform/src/quota-do/coverage.ts`, before outbox rows are read, then ship as today — produces the alarm boundary, FR-001, E2E-P3.5-01. Depends on T009 (same file). `GatewayObject.alarm` in `ai-platform/src/worker.ts` already calls that function, so one `runDurableObjectAlarm` both applies the boundary and ships the events. Do not edit `ai-platform/src/worker.ts` in this task. `setAlarm` is still unchanged.

- [ ] T011 [US1] In `applyDueBoundaries` in `ai-platform/src/quota-do/coverage.ts`, when `ends_at` is due and no `queued` term exists, enter grace — produces the grace row, FR-003, E2E-P3.5-02. Depends on T010 (same file). Set the term `state` to `grace`, set `grace_ends_at` to `addDuration(ends_at, "day", grace_days, scale)`, set `hot.grace_base_used` to `hot.used`, and emit `grace_started`. Leave `term.grace_cap` as `proportional`. The numeric ceiling is `ceil(allowance × grace_days ÷ unscaled term days)` and the grace allowance is `min(allowance − grace_base_used, ceiling)`, fixed at this moment. A later admission inside that allowance reserves against this same `term_id`. An `exhausted` term does not enter grace.

- [ ] T012 [US1] In `applyDueBoundaries` in `ai-platform/src/quota-do/coverage.ts`, when the grace term's `grace_ends_at` is due, lapse it — produces lapse at `grace_ends_at`, FR-004, FR-008, E2E-P3.5-02, E2E-P3.5-06. Depends on T011 (same file). Set the term `ended` / `expired`, clear `hot.active_term_id`, and let step 4 return the existing `coverage_lapsed` outcome with reason `expired`. The same loop lapses immediately if the clock is already past both `ends_at` and `grace_ends_at`. Do not add a denial code.

- [ ] T013 [US1] In `admitOnHotRow` in `ai-platform/src/quota-do/index.ts`, after a grace reservation, if `used + reserved − grace_base_used` reaches the grace allowance from T011, end that term `grace_exhausted` in the same admission — produces exhaustion of the grace cap, FR-005, E2E-P3.5-03. Depends on T012. Clear `hot.active_term_id` and emit `term_ended`. The next admission returns `coverage_lapsed` with reason `grace_exhausted`. There is no grace after exhaustion.

**Checkpoint**: E2E-P3.5-01 still needs the alarm path from T010 to be covered by the unit command. E2E-P3.5-02 and E2E-P3.5-06 still need the snapshot and the admission scale. E2E-P3.5-03 still needs the unit command after T013.

### 4.2 User Story 1 - Apply the term boundary (Priority: P1) (part 2)

**Independent Test**: E2E-P3.5-01, E2E-P3.5-02, E2E-P3.5-03, E2E-P3.5-06, E2E-P3.5-07, and E2E-P3.5-08 in harness H-AP, with the test clock and `runDurableObjectAlarm` (rule V4).

- [ ] T014 [US1] In `ai-platform/src/quota-do/coverage.ts`, `buildCoverageSnapshot` sets `state` `grace` with `reason` `none` and the grace term in `term` while grace is running, and `state` `lapsed` with `reason` `expired` or `grace_exhausted` and `term` null after those ends — produces the frozen snapshot slice and `hard_stop_at`, FR-003, FR-004, FR-010, E2E-P3.5-02, E2E-P3.5-08. Depends on T013. `mirrorFromSnapshot` writes `hard_stop_at` from `term.ends_at` when `state` is `active` and from `term.grace_ends_at` when `state` is `grace`. A lapsed replace keeps the `hard_stop_at` already stored on that mirror row. `coverage_mirror` is replaced only by a higher `(binding_epoch, clinic_seq)`.

- [ ] T015 [US1] In `ai-platform/src/quota-do/coverage.ts`, `computeNextAlarmAt` takes the grace term's `grace_ends_at` as well as the active term's `ends_at`, and the pending-outbox instant when the outbox is non-empty — produces `setAlarm` only when the next instant moves, FR-001, E2E-P3.5-08. Depends on T014 (same file). `syncAlarm` calls `setAlarm` only when that instant differs from `hot.next_alarm_at`. Drop the `immediate` bypass that calls `setAlarm` when the instant is unchanged.

**Checkpoint**: E2E-P3.5-08 still needs activate, end, and grace-start events to ship with `hard_stop_at`. E2E-P3.5-04 and E2E-P3.5-05 still fail. E2E-P3.5-07 still needs the staging scale on admission and the alarm.

### 4.3 User Story 2 - Grant during grace or after lapse (Priority: P2)

**Independent Test**: E2E-P3.5-04 and E2E-P3.5-05 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [ ] T016 [US2] On the existing grace branch of `applyGrantRPC` in `ai-platform/src/quota-do/coverage.ts`, set the grace term's `used_final` to `hot.used` and set `hot.grace_base_used` to 0 before `hot.used` resets to 0 — produces renewal during grace and the unchanged lapse start, FR-006, FR-007, E2E-P3.5-04, E2E-P3.5-05. Depends on T015 (same file). Leave `calendar_start` and `starts_at` at the grace term's `ends_at`. Leave the no-coverage branch that starts a term at `nowIso`. Do not edit `VendorEntrypoint.grant` or `coverClinic()`.

**Checkpoint**: E2E-P3.5-04 and E2E-P3.5-05 pass once the unit command runs after T016. E2E-P3.5-07 still needs the staging scale.

### 4.4 User Story 1 - Apply the term boundary (Priority: P1) (part 3)

**Independent Test**: E2E-P3.5-01, E2E-P3.5-02, E2E-P3.5-03, E2E-P3.5-06, E2E-P3.5-07, and E2E-P3.5-08 in harness H-AP, with the test clock and `runDurableObjectAlarm` (rule V4).

- [ ] T017 [US1] In `GatewayObject.fetch` in `ai-platform/src/worker.ts`, set admission `durationScale` from `env.DURATION_SCALE === "staging"` before `admissionRPC`, and pass that same scale into `shipCoverageOutboxAlarm` from `alarm()` — produces scaled boundaries, FR-008, FR-009, E2E-P3.5-07. Depends on T016. Do not edit `durationScaleFromEnv` or `VendorEntrypoint.grant`. Production has no scale.

**Checkpoint**: E2E-P3.5-07 passes once the unit command runs after T017.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes. Earlier suites are the review's run (rule S2, Sequencing step 19). This task does not name that run.

### 5.1 Unit harness

- [ ] T018 Run harness H-AP for this unit and confirm E2E-P3.5-01 through E2E-P3.5-08 pass together — produces the green run, FR-001 through FR-010, E2E-P3.5-01 through E2E-P3.5-08. Depends on T009 through T017 (and therefore on T001–T008). `ai-platform/src/coverage/calendar.ts`, `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/admission/index.ts`, `ai-platform/src/errors.ts`, `ai-platform/test/system/harness.ts`, and `packages/vendor-contracts/**` stay unchanged. SC-002 is the review's run of earlier suites, not this command.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/term-boundaries-grace-renewal.system.test.ts
```

---

## 6. Documentation

**Purpose**: Written after T018 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` and `contracts/` stay plan-phase artifacts. No other doc task.

### 6.1 Quickstart

- [ ] T019 Create `specs/069-abo-p3-5-term-boundaries-grace-renewal/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-010, E2E-P3.5-01 through E2E-P3.5-08. Depends on T018. Sections: (1) what was implemented — the boundary loop on the alarm and on admission, grace and lapse, renewal during grace and after lapse, scaled windows, and mirror `hard_stop_at`; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) harness command for this unit's tests only — the command below; (4) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/term-boundaries-grace-renewal.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

| ID | Chain |
| --- | --- |
| E2E-P3.5-01 | `coverClinic()` → `vendorCall` `grant` while T1 is active → `setTestClock` to T1 `ends_at` → `runDurableObjectAlarm` → `GatewayObject.alarm` → `applyDueBoundaries` → successor `term` row |
| E2E-P3.5-02 | `coverClinic()` once → `setTestClock` to `ends_at` → `runDurableObjectAlarm` → `POST /v1/requests` → `admissionRPC` step 3 then step 5 → `setTestClock` to `grace_ends_at` → `runDurableObjectAlarm` → `POST /v1/requests` → `coverage_lapsed` |
| E2E-P3.5-03 | `coverClinic()` → boundary into grace → `POST /v1/requests` until the grace allowance is taken → next `POST` → `coverage_lapsed` reason `grace_exhausted` |
| E2E-P3.5-04 | `coverClinic()` into grace → `setTestClock` to day 3 → `coverClinic()` → `applyGrantRPC` grace branch → new `term.calendar_start` |
| E2E-P3.5-05 | `coverClinic()` → clock through grace to lapse → `setTestClock` two months later → `coverClinic()` → `applyGrantRPC` no-coverage branch |
| E2E-P3.5-06 | `setTestClock` past `grace_ends_at` with no `runDurableObjectAlarm` → `POST /v1/requests` → `admissionRPC` step 3 → `coverage_lapsed` |
| E2E-P3.5-07 | `DURATION_SCALE=staging` on the worker binding → `coverClinic()` → `setTestClock` to the scaled `ends_at` and `grace_ends_at` → `runDurableObjectAlarm` and `POST /v1/requests` |
| E2E-P3.5-08 | `runDurableObjectAlarm` on activate, end, and grace start → D1 `coverage_event` → `coverage_mirror.hard_stop_at` |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T008)**: No Setup phase. T001 starts immediately. The other tests append in Sequencing order and are observed failing before T009: T001, T002, T003, T004, T005, T006, T007, T008.
- **Implementation (T009–T017)**: Starts after T001–T008 exist and fail. Order is T009 through T017.
- **Verification (T018)**: After every implementation task. This is Sequencing step 18's unit command.
- **Documentation (T019)**: After T018 is green. This is Sequencing step 20.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001 starts immediately and does not wait on another story's implementation. T002 waits on T001, and T003 on T002, because they append to one file. T006 waits on T005, T007 on T006, and T008 on T007, for the same reason. Those tests do not wait on another story's modules. T009 waits until T008 has added the last failing test. T010 waits on T009 because both edit `ai-platform/src/quota-do/coverage.ts`. T011 waits on T010, and T012 on T011, for the same file. T013 waits on T012 and edits `ai-platform/src/quota-do/index.ts` after T009. T014 waits on T013 and returns to `ai-platform/src/quota-do/coverage.ts`. T015 waits on T014 (same file). T017 waits on T016 and edits `ai-platform/src/worker.ts`. E2E-P3.5-01 is the alarm path from T010. E2E-P3.5-02 and E2E-P3.5-06 are the grace and lapse path from T011 and T012. E2E-P3.5-03 is T013. E2E-P3.5-07 is T017. E2E-P3.5-08 is T014 and T015 together with the events T009 through T011 emit.
- **User Story 2 (P2)**: T004 waits on T003, and T005 on T004, because they append to one file. Those tests do not wait on another story's modules. T016 waits on T015 because both edit `ai-platform/src/quota-do/coverage.ts`. E2E-P3.5-04 and E2E-P3.5-05 pass at T016. The "every earlier suite stays green" sentence is the review's run, not T018.

### 7.3 Parallel Opportunities

- T001–T008 are not marked `[P]`. They all write `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts`.
- T009 and T013 share `ai-platform/src/quota-do/index.ts`. T013 waits until T009 has finished.
- T009 through T012, T014, T015, and T016 share `ai-platform/src/quota-do/coverage.ts`. They stay in id order.
- T017 writes `ai-platform/src/worker.ts` only after T016, because Sequencing places the staging scale after the grant branch.
- T018 and T019 are single tasks. T019 waits until T018 is green.
- No two subphases have disjoint paths that Sequencing allows in the same wave. No task line is marked `[P]`.

---

## 8. Implementation Waves

### Wave 1

- T001–T003 [US1] — subphase: `### 3.1 User Story 1 - Apply the term boundary (Priority: P1) (part 1)` — paths: `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts`

### Wave 2

- T004–T005 [US2] — subphase: `### 3.2 User Story 2 - Grant during grace or after lapse (Priority: P2)` — paths: `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts`

### Wave 3

- T006–T008 [US1] — subphase: `### 3.3 User Story 1 - Apply the term boundary (Priority: P1) (part 2)` — paths: `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts`

### Wave 4

- T009–T013 [US1] — subphase: `### 4.1 User Story 1 - Apply the term boundary (Priority: P1) (part 1)` — paths: `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/quota-do/index.ts`

### Wave 5

- T014–T015 [US1] — subphase: `### 4.2 User Story 1 - Apply the term boundary (Priority: P1) (part 2)` — paths: `ai-platform/src/quota-do/coverage.ts`

### Wave 6

- T016 [US2] — subphase: `### 4.3 User Story 2 - Grant during grace or after lapse (Priority: P2)` — paths: `ai-platform/src/quota-do/coverage.ts`

### Wave 7

- T017 [US1] — subphase: `### 4.4 User Story 1 - Apply the term boundary (Priority: P1) (part 3)` — paths: `ai-platform/src/worker.ts`

### Wave 8

- T018 — subphase: `### 5.1 Unit harness` — paths: `ai-platform/test/system/term-boundaries-grace-renewal.system.test.ts`

### Wave 9

- T019 — subphase: `### 6.1 Quickstart` — paths: `specs/069-abo-p3-5-term-boundaries-grace-renewal/quickstart.md`
