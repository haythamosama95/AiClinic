# Tasks: Admission and settlement against terms

**Input**: Design documents from `specs/068-abo-p3-4-admission-settlement-against-terms/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged unit in **Consumes Binding**: P3.3 (`grant` paid, `getCoverage`, `listGrants`, `readCoverageEvents`, service-key methods, plan-version methods, DO schema, event shapes, receipt shapes). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/` (`contracts/admission-answer.md`, `contracts/clinic-denial-codes.md`). There is no `research.md`. `quickstart.md` is written in Documentation after verification.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id in the spec Test plan, written to fail before term admission exists. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase. No Polish phase. Task ids follow plan Sequencing, with Sequencing step 31's assertion edits placed at T030 so verification (Sequencing step 30) runs after every code edit. Sections group by user story, so some ids sit under a later heading than a lower id.

**Task count**: 32. Size L is 32–40 (rule S3). The count is twelve E2E tasks (Sequencing steps 1–12), eighteen implementation tasks (steps 13–29 and the assertion edits in step 31), one verification task (the unit harness only), and `quickstart.md` (step 32). It is not padded. `cd ai-platform && npm test && npm run test:e2e` is the review's earlier-suite run (SC-002, rule S2), not a task.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — the Files paths in `plan.md`
- **ABO**: `abo/` — this unit does not change it
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified (rule S7)
- **Spec Kit artifacts**: `specs/068-abo-p3-4-admission-settlement-against-terms/`
- `data-model.md` and `contracts/` stay plan-phase artifacts. `src/vendor/entrypoint.ts`, `src/coverage/calendar.ts`, `src/rate-limit/index.ts`, `src/platform-vocabulary.ts`, and `packages/vendor-contracts/**` stay as they are. `entitleScenario` and `/control/entitle` stay defined until P3.10. Call sites move to `coverClinic()`.

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/admission-settlement.system.test.ts`. The unit command is that file only. Issuer tokens come from `newClinic()`. Clinic calls use `SELF.fetch`. The test clock is `setTestClock`. No `sleep` over 2 s. `coverClinic()` does not exist until T013, so these tests stay red.

### 3.1 User Story 1 - Complete a request charged to a term (Priority: P1)

**Independent Test**: E2E-P3.4-01 in harness H-AP.

- [X] T001 [US1] Add the failing test `E2E-P3.4-01 CP-B paid grant then issuer token lists the plan and completes a request charged to the term` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-004, FR-010, FR-011, FR-013, FR-014, E2E-P3.4-01. `coverClinic()` then `newClinic()` for that org. `GET /v1/capabilities` lists `clinic.visit_summary` from `coverage_mirror`. `POST /v1/requests` completes. `usage_event.term_id` is the active term. `hot.used` increases by the capability `quotaWeight` (`w`). Run:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/admission-settlement.system.test.ts
```

The run fails because `coverClinic` is missing and `POST /v1/requests` is not charged to a term. Do not modify `packages/vendor-contracts`.

**Checkpoint**: E2E-P3.4-01 exists and fails.

### 3.2 User Story 2 - Refuse a request the term does not allow (Priority: P2) (part 1)

**Independent Test**: E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 in harness H-AP.

- [X] T002 [US2] Add the failing test `E2E-P3.4-02 An org that was never granted is coverage_lapsed and writes no journal row` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-005, FR-011, E2E-P3.4-02. Depends on T001 (same file). `newClinic()` and no `coverClinic()`. `POST /v1/requests` is 403, body `code` `coverage_lapsed`, `coverage_reason` `none`. No `usage_event` row and no `ai_request` row for that call. The unit command fails because a never-granted org is not refused `coverage_lapsed`.

- [X] T003 [US2] Add the failing test `E2E-P3.4-03 A capability outside the plan snapshot is forbidden_capability` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-005, E2E-P3.4-03. Depends on T002 (same file). `coverClinic()` publishes a plan whose `capabilities` omit `clinic.visit_summary`. `POST` asking for that capability is 403 `forbidden_capability`. The unit command fails because a capability outside the snapshot is not `forbidden_capability`.

- [X] T004 [US2] Add the failing test `E2E-P3.4-04 The 17th in-flight request is concurrency_limited` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-005, FR-012, E2E-P3.4-04. Depends on T003 (same file). `coverClinic()` with `concurrency_limit` 16. `Promise.all` of 17 `POST /v1/requests`. One response is 429 `concurrency_limited` with `retry_after`, and its `code` is not `rate_limited`. The unit command fails because the 17th in-flight request is not `concurrency_limited`.

**Checkpoint**: E2E-P3.4-02, E2E-P3.4-03, and E2E-P3.4-04 exist and fail.

### 3.3 User Story 3 - Exhaust a term and activate the successor (Priority: P3)

**Independent Test**: E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07, and E2E-P3.4-08 in harness H-AP.

- [ ] T005 [US3] Add the failing test `E2E-P3.4-05 Reaching the allowance with nothing queued exhausts the term` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-005, FR-007, E2E-P3.4-05. Depends on T004 (same file). `coverClinic()` once, small allowance. `POST` until `used + reserved` reaches the allowance. The term `state` is `exhausted`. The next `POST` is 403 `allowance_exhausted`. There is no grace term. Test clock (rule V4). The unit command fails because reaching the allowance does not end the term `exhausted`.

- [ ] T006 [US3] Add the failing test `E2E-P3.4-06 Exhaustion activates the queued term at that instant` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-007, E2E-P3.4-06. Depends on T005 (same file). `coverClinic()` twice. The `POST` that reaches the allowance leaves the queued term `active` with a full allowance. `ends_at` is that instant plus 1 month from `addDuration`. Test clock (rule V4). The unit command fails because exhaustion does not activate the queued term.

- [ ] T007 [US3] Add the failing test `E2E-P3.4-07 Two concurrent requests near the allowance exhaust once` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-007, FR-008, E2E-P3.4-07. Depends on T006 (same file). `coverClinic()` twice. Two concurrent `POST`s when one credit remains. One `term_ended` or single exhaustion. Overshoot is at most `w_max - 1`. The other request is charged to the successor or refused. The unit command fails because two concurrent requests do not exhaust once.

- [ ] T008 [US3] Add the failing test `E2E-P3.4-08 Crossing 75 percent and 90 percent emits one band event each` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-009, FR-012, E2E-P3.4-08. Depends on T007 (same file). `coverClinic()` with allowance 10. After the alarm, one `coverage_event` of kind `band_crossed` whose snapshot `term.band` is `75`, and one whose band is `90`. A further `POST` still inside a crossed band adds no second event for that band. The unit command fails because band crossings do not emit one `band_crossed` each.

**Checkpoint**: E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07, and E2E-P3.4-08 exist and fail.

### 3.4 User Story 4 - Settle each request once (Priority: P4)

**Independent Test**: E2E-P3.4-09, E2E-P3.4-10, and E2E-P3.4-11 in harness H-AP. Every H-AP suite that entitles runs through `coverClinic()` and stays green (rule V2, rule S2).

- [ ] T009 [US4] Add the failing test `E2E-P3.4-09 A provider call that consumes nothing releases the reservation` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-004, E2E-P3.4-09. Depends on T008 (same file). `coverClinic()`, then `publishPolicy` / `promote` of `fakePolicyDocument` with an empty target list. `POST` admits, the provider chain is empty, and settlement releases. `hot.used` is unchanged and the reservation is gone. The unit command fails because an empty provider chain still changes `hot.used`.

- [ ] T010 [US4] Add the failing test `E2E-P3.4-10 A reservation older than 15 minutes is charged once` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-003, FR-011, E2E-P3.4-10. Depends on T009 (same file). `coverClinic()`, then `POST` whose first `kind: "credit"` is swallowed by a test wrapper on `GatewayObject.fetch` so the reservation stays. `setTestClock` more than 15 minutes later. The next `POST` charges it. `runDurableObjectAlarm` leaves one `usage_event` for that `request_id`. Replaying the swallowed credit changes neither `hot` nor that row. No `sleep` over 2 s. The unit command fails because a reservation older than 15 minutes is not charged on the next admission.

- [ ] T011 [US4] Add the failing test `E2E-P3.4-11 A replayed jti or idempotency key returns the stored answer` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-002, E2E-P3.4-11. Depends on T010 (same file). Two `POST`s with the same `x-idempotency-key`, and two with the same bearer token. The second response matches the stored answer. `hot` SQL is unchanged across the replay. The unit command fails because a replayed key writes again.

**Checkpoint**: E2E-P3.4-09, E2E-P3.4-10, and E2E-P3.4-11 exist and fail.

### 3.5 User Story 2 - Refuse a request the term does not allow (Priority: P2) (part 2)

**Independent Test**: E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 in harness H-AP.

- [ ] T012 [US2] Add the failing test `E2E-P3.4-12 A DO version rejection is coverage_unknown` in `ai-platform/test/system/admission-settlement.system.test.ts` — red test, FR-006, E2E-P3.4-12. Depends on T011 (same file). For this test, `GatewayObject.fetch` returns the P3.3 refusal `{result: "rejected", code: "contract_version_unsupported"}` for `kind` `admission` and does not touch storage. `POST /v1/requests` is 503 `coverage_unknown` with `retry_after`. The unit command fails because a DO `rejected` version answer is not `coverage_unknown`.

**Checkpoint**: E2E-P3.4-12 exists and fails. User Story 2's four tests are red.

---

## 4. Implementation

**Purpose**: Sequencing steps 13–29, then the assertion edits from Sequencing step 31. Each step starts after T001–T012 exist and fail. Within a subphase the tasks run in id order.

### 4.1 User Story 1 - Complete a request charged to a term (Priority: P1) (part 1)

**Independent Test**: E2E-P3.4-01 in harness H-AP.

- [ ] T013 [US1] Add `coverClinic()` in `ai-platform/test/system/harness.ts` and switch `setupPromotedFakePolicy` in that file, plus the eight system suites, off `entitleScenario` — produces the paid-grant helper and the migrated call sites, FR-014, E2E-P3.4-01. Depends on T012. `coverClinic()` signs with `createAboGrantSigner`, calls consumed `publishPlanVersion`, `registerServiceKey`, and `grant` through `vendorCall`, then `runDurableObjectAlarm` so the consumed ship writes `coverage_mirror`. Suites: `ai-platform/test/system/capability-lifecycle.system.test.ts`, `ai-platform/test/system/entitlement-grant-interplay.system.test.ts`, `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts`, `ai-platform/test/system/golden-journey.system.test.ts`, `ai-platform/test/system/lifecycle-interplay.system.test.ts`, `ai-platform/test/system/quota-admission-interplay.system.test.ts`, `ai-platform/test/system/routing-policy-traffic.system.test.ts`, and `ai-platform/test/system/settlement-integrity.system.test.ts`. `entitleScenario` stays defined. The twelve E2E tests still fail on admission.

- [ ] T014 [US1] Add `ai-platform/migrations/20261006120000_usage_term.sql` as `specs/068-abo-p3-4-admission-settlement-against-terms/data-model.md` describes, replace `ai-platform/schema.snap.sql` with the post-migration dump, and append that SQL after `20261003140000_plan_version_paid_grant_coverage.sql` — produces `usage_event.term_id` and the unique `request_id`, FR-011, E2E-P3.4-01. Depends on T013. Apply it in `ai-platform/test/system/harness.ts`, `ai-platform/test/e2e/harness/d1.ts`, `ai-platform/test/usage-summary.test.ts`, `ai-platform/test/identity.test.ts`, `ai-platform/test/plan-catalogue.test.ts`, `ai-platform/test/control.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `ai-platform/test/entitle-grant.test.ts`, `ai-platform/test/config-readers.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/discovery-http.test.ts`, and `ai-platform/test/retention.test.ts`. The twelve E2E tests still fail.

**Checkpoint**: E2E-P3.4-01 still fails.

### 4.2 User Story 4 - Settle each request once (Priority: P4) (part 1)

**Independent Test**: E2E-P3.4-09, E2E-P3.4-10, and E2E-P3.4-11 in harness H-AP. Every H-AP suite that entitles runs through `coverClinic()` and stays green (rule V2, rule S2).

- [ ] T015 [US4] In `admissionRPC` in `ai-platform/src/quota-do/index.ts`, step 1 reads `hot.replay` and `hot.idempotency` and returns the stored answer without writing — produces the replay read, FR-002, E2E-P3.4-11. Depends on T014. Sweep those maps on each write that does happen, keeping entries for at least `EPHEMERAL_HORIZON_MS`. Pass `now` from `clockNowMs`. E2E-P3.4-11 still fails until the HTTP path stores the answer.

- [ ] T016 [US4] In `ai-platform/src/quota-do/index.ts`, step 2 charges reservations whose `admitted_at` is more than 15 minutes before `now` — produces the late charge and the outbox row, FR-003, E2E-P3.4-10. Depends on T015 (same file). Append outbox kind `usage_adjustment` with the payload in `specs/068-abo-p3-4-admission-settlement-against-terms/data-model.md`. Do not insert `usage_event` inside the DO.

- [ ] T017 [US4] In `shipCoverageOutboxAlarm` in `ai-platform/src/quota-do/coverage.ts`, ship `usage_adjustment` with `INSERT OR IGNORE` on `usage_event.request_id`, then delete the outbox row — produces the journal ship, FR-003, E2E-P3.4-10. Depends on T016. Leave `coverage_event`, `grant_ledger`, and `alert` as they are. E2E-P3.4-10 still fails until the next admission charges.

**Checkpoint**: E2E-P3.4-11 still fails until T022. E2E-P3.4-10 still fails until the next admission charges.

### 4.3 User Story 2 - Refuse a request the term does not allow (Priority: P2) (part 1)

**Independent Test**: E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 in harness H-AP.

- [ ] T018 [US2] In `ai-platform/src/quota-do/index.ts`, step 4 refuses in the order in `specs/068-abo-p3-4-admission-settlement-against-terms/contracts/clinic-denial-codes.md` — produces the DO refusals, FR-005, E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, E2E-P3.4-05. Depends on T017. A refusal writes nothing unless step 2 changed state. Step 3 runs and applies no expiry or grace transition. `hot.suspended` maps to `suspended`; this unit does not set the flag. Capabilities and `concurrency_limit` come from `term.plan_snapshot`.

**Checkpoint**: E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 still need the worker mapper.

### 4.4 User Story 3 - Exhaust a term and activate the successor (Priority: P3) (part 1)

**Independent Test**: E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07, and E2E-P3.4-08 in harness H-AP.

- [ ] T019 [US3] In `ai-platform/src/quota-do/index.ts`, steps 5–7 reserve `w`, end an active term `exhausted` in that same transaction when `used + reserved >= allowance`, activate the next unheld queued term with `addDuration`, emit one `band_crossed` per band, and return `specs/068-abo-p3-4-admission-settlement-against-terms/contracts/admission-answer.md` — produces the reservation, the exhaustion, and the band, FR-004, FR-007, FR-008, FR-009, E2E-P3.4-01, E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07, E2E-P3.4-08. Depends on T018 (same file). E2E-P3.4-01 and E2E-P3.4-05 through E2E-P3.4-08 still need the worker path.

**Checkpoint**: E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07, and E2E-P3.4-08 still need the worker path.

### 4.5 User Story 4 - Settle each request once (Priority: P4) (part 2)

**Independent Test**: E2E-P3.4-09, E2E-P3.4-10, and E2E-P3.4-11 in harness H-AP. Every H-AP suite that entitles runs through `coverClinic()` and stays green (rule V2, rule S2).

- [ ] T020 [US4] Settle `credit` by `reservation_id` in `ai-platform/src/credit/index.ts` and in the credit handler in `ai-platform/src/quota-do/index.ts` — produces settlement, FR-004, E2E-P3.4-09. Depends on T019. Provider capacity adds `w` to `used`. Nothing consumed releases the reservation. The reservation keeps its `term_id` after the term has ended. A credit after the step-2 charge changes nothing.

**Checkpoint**: E2E-P3.4-09 still needs the worker path. E2E-P3.4-10 still needs the next admission to run that charge.

### 4.6 User Story 1 - Complete a request charged to a term (Priority: P1) (part 2)

**Independent Test**: E2E-P3.4-01 in harness H-AP.

- [ ] T021 [US1] In `ai-platform/src/quota-do/index.ts`, remove the `state` blob, `maybeResetPeriod`, and `isQuotaExhausted` — produces term admission without the blob, FR-001, E2E-P3.4-01. Depends on T020 (same file). Denial and replay do not call the blob writer.

**Checkpoint**: E2E-P3.4-01 still needs the worker path.

### 4.7 User Story 2 - Refuse a request the term does not allow (Priority: P2) (part 2)

**Independent Test**: E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 in harness H-AP.

- [ ] T022 [US2] In `ai-platform/src/admission/index.ts`, map DO outcomes through `specs/068-abo-p3-4-admission-settlement-against-terms/contracts/clinic-denial-codes.md`, including `result: "rejected"` to `coverage_unknown` — produces the client denial mapping, FR-005, FR-006, FR-010, FR-013, E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, E2E-P3.4-12. Depends on T021. Remove `mapEntitlementSnapshot`. Send `contract_version` and `now` from `clockNowMs`. Store the admission answer for the replay key on this path so E2E-P3.4-11 can return it. E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 pass once the worker uses this mapper.

- [ ] T023 [US2] In `ai-platform/src/errors.ts` and `ai-platform/src/adapter.ts`, carry `retry_after` and `coverage_reason` and drop `quota_exhausted` and `period_reset` — produces the denial body fields, FR-005, FR-012, E2E-P3.4-02, E2E-P3.4-04, E2E-P3.4-05. Depends on T022. Rename `installation_suspended` to `suspended` in `ai-platform/src/identity/index.ts`, `ai-platform/src/usage-summary/index.ts`, and the journal union in `ai-platform/src/journal/index.ts`. Token verification stays.

**Checkpoint**: E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 pass once the worker uses the T022 mapper. E2E-P3.4-11 passes at T022.

### 4.8 User Story 1 - Complete a request charged to a term (Priority: P1) (part 3)

**Independent Test**: E2E-P3.4-01 in harness H-AP.

- [ ] T024 [US1] In `ai-platform/src/pipeline/index.ts`, stage 3 reads `coverage_mirror` by `installation_id` and does not read `entitlement` — produces the pre-check and the carried admission fields, FR-010, E2E-P3.4-01. Depends on T023. Stage 8 keeps `term_id`, `reservation_id`, and the snapshot from the DO. Stage 15 passes them to `creditUsage`.

- [ ] T025 [US1] In `ai-platform/src/worker.ts`, replace `periodFromIso` and `SELECT period_start FROM entitlement` on the handoff settlement with the admission `term_id` — produces settlement by term, FR-010, E2E-P3.4-01. Depends on T024. Take the cost class from the snapshot `max_cost_class`. Drop the `minimumPlanTier: "standard"` argument. `ai-platform/src/manifest/index.ts` no longer requires `minimumPlanTier` and ignores it when present.

- [ ] T026 [US1] In `ai-platform/src/journal/index.ts`, insert `term_id` with `INSERT OR IGNORE` on `request_id` — produces the journal row, FR-011, E2E-P3.4-01, E2E-P3.4-10. Depends on T025. `authenticateGetRequest` keeps `IssuerTokenVerifier`.

**Checkpoint**: E2E-P3.4-01 still needs `GET /v1/capabilities` from the mirror. E2E-P3.4-10 passes at T026.

### 4.9 User Story 1 - Complete a request charged to a term (Priority: P1) (part 4)

**Independent Test**: E2E-P3.4-01 in harness H-AP.

- [ ] T027 [US1] In `ai-platform/src/rollup/index.ts`, aggregate by `{installation_id, term_id}` — produces the rollup dimensions, FR-011, E2E-P3.4-01. Depends on T026. Does not edit `ai-platform/src/journal/index.ts`.

**Checkpoint**: E2E-P3.4-01 still needs capability discovery from the mirror.

### 4.10 User Story 1 - Complete a request charged to a term (Priority: P1) (part 5)

**Independent Test**: E2E-P3.4-01 in harness H-AP.

- [ ] T028 [US1] `discover` reads `coverage_mirror` by primary key — produces the immediate capability list, FR-013, E2E-P3.4-01. Depends on T026. `ai-platform/src/discovery/index.ts` passes `env.DB`. Remove tier checks and the `plan:` grant fallback in `ai-platform/src/capability/index.ts`. `ai-platform/src/entitlement/index.ts` drops tier and status checks and keeps kill switches. The capability check reads the plan snapshot. The `installation_suspended` branch in `ai-platform/src/discovery/index.ts` becomes `suspended`. E2E-P3.4-01 passes at T028.

**Checkpoint**: E2E-P3.4-01 passes at T028.

### 4.11 User Story 3 - Exhaust a term and activate the successor (Priority: P3) (part 2)

**Independent Test**: E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07, and E2E-P3.4-08 in harness H-AP.

- [ ] T029 [US3] `dashboardQuotaRejectionRate` in `ai-platform/src/dashboards/index.ts` counts the codes in `specs/068-abo-p3-4-admission-settlement-against-terms/contracts/clinic-denial-codes.md`, and `degradedNoticeFromAdmission` in `ai-platform/src/soft-threshold/index.ts` is true for band `75`, `90`, or `exhausted` — produces the dashboard counts and the band notice, FR-009, FR-012, E2E-P3.4-04, E2E-P3.4-08. Depends on T028. Admission in `ai-platform/src/admission/index.ts` records those codes through the existing `recordGuardRejection`. Do not edit `ai-platform/src/rate-limit/index.ts`.

**Checkpoint**: E2E-P3.4-08's band events are the DO events from T019. This task is the dashboard and soft-threshold half of FR-012.

### 4.12 User Story 4 - Settle each request once (Priority: P4) (part 3)

**Independent Test**: E2E-P3.4-09, E2E-P3.4-10, and E2E-P3.4-11 in harness H-AP. Every H-AP suite that entitles runs through `coverClinic()` and stays green (rule V2, rule S2).

- [ ] T030 [US4] Update assertions that still expect `quota_exhausted`, `period_reset`, `installation_suspended`, or `usage_event.period`, and `discover` call sites that omit `db` — produces suites that match the new codes and `term_id`, FR-005, FR-011, FR-012, FR-013, E2E-P3.4-01. Depends on T029. Files: `ai-platform/test/system/capability-lifecycle.system.test.ts`, `ai-platform/test/system/entitlement-grant-interplay.system.test.ts`, `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts`, `ai-platform/test/system/golden-journey.system.test.ts`, `ai-platform/test/system/lifecycle-interplay.system.test.ts`, `ai-platform/test/system/quota-admission-interplay.system.test.ts`, `ai-platform/test/system/routing-policy-traffic.system.test.ts`, `ai-platform/test/system/settlement-integrity.system.test.ts`, `ai-platform/test/usage-summary.test.ts`, `ai-platform/test/identity.test.ts`, `ai-platform/test/plan-catalogue.test.ts`, `ai-platform/test/control.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `ai-platform/test/entitle-grant.test.ts`, `ai-platform/test/config-readers.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/discovery-http.test.ts`, and `ai-platform/test/retention.test.ts`. The review's `npm test` and `npm run test:e2e` are not this task.

**Checkpoint**: Assertion edits for the earlier suites are in the files above. SC-002 stays the review's run.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes. Earlier suites are the review's run (rule S2). This task does not name that run.

### 5.1 Unit harness

- [ ] T031 Run harness H-AP for this unit and confirm E2E-P3.4-01 through E2E-P3.4-12 pass together — produces the green run, FR-001 through FR-014, E2E-P3.4-01 through E2E-P3.4-12. Depends on T013 through T030 (and therefore on T001–T012). `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/coverage/calendar.ts`, `ai-platform/src/rate-limit/index.ts`, `ai-platform/src/platform-vocabulary.ts`, and `packages/vendor-contracts/**` stay unchanged. `entitleScenario` and `/control/entitle` stay defined (rule S9). SC-002 is the review's run of earlier suites, not this command.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/admission-settlement.system.test.ts
```

---

## 6. Documentation

**Purpose**: Written after T031 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` and `contracts/` stay plan-phase artifacts. No other doc task.

### 6.1 Quickstart

- [ ] T032 Create `specs/068-abo-p3-4-admission-settlement-against-terms/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-014, E2E-P3.4-01 through E2E-P3.4-12. Depends on T031. Sections: (1) what was implemented — term admission and settlement, the denial codes, exhaustion and bands, `usage_event.term_id`, and `coverClinic()`; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) harness command for this unit's tests only — the command below; (4) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/admission-settlement.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

| ID | Chain |
| --- | --- |
| E2E-P3.4-01 | `coverClinic()` → `vendorCall` `grant` → `runDurableObjectAlarm` → `GET /v1/capabilities` → `src/discovery/index.ts` → `discover` reads `coverage_mirror` → `POST /v1/requests` → `src/pipeline/index.ts` stage 8 → `admissionRPC` → stage 15 `creditUsage` → `usage_event.term_id` |
| E2E-P3.4-02 | `newClinic()` → `POST /v1/requests` → `admissionRPC` step 4 → 403 `coverage_lapsed` |
| E2E-P3.4-03 | `coverClinic()` with a snapshot that omits the capability → `POST /v1/requests` → step 4 `forbidden_capability` |
| E2E-P3.4-04 | `coverClinic()` with `concurrency_limit` 16 → 17 concurrent `POST /v1/requests` → step 4 `concurrency_limited` |
| E2E-P3.4-05 | `coverClinic()` → `POST /v1/requests` until allowance → step 6 → next `POST` → `allowance_exhausted` |
| E2E-P3.4-06 | `coverClinic()` twice → `POST` that reaches the allowance → queued term `ends_at` |
| E2E-P3.4-07 | `coverClinic()` twice → two concurrent `POST`s near the allowance → one exhaustion |
| E2E-P3.4-08 | `coverClinic()` → `POST`s that cross 75% and 90% → one `band_crossed` each → a later `POST` emits nothing |
| E2E-P3.4-09 | `coverClinic()` → empty provider chain → `creditUsage` releases the reservation |
| E2E-P3.4-10 | `coverClinic()` → `POST` left unsettled → `setTestClock` past 15 minutes → next `POST` step 2 → `runDurableObjectAlarm` → late credit |
| E2E-P3.4-11 | `POST /v1/requests` twice with the same `x-idempotency-key` or the same token `jti` → step 1 |
| E2E-P3.4-12 | `POST /v1/requests` while the DO fetch returns `result` `rejected` → `coverage_unknown` |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T012)**: No Setup phase. T001 starts immediately. The other tests append in Sequencing order and are observed failing before T013: T001, T002, T003, T004, T005, T006, T007, T008, T009, T010, T011, T012.
- **Implementation (T013–T030)**: Starts after T001–T012 exist and fail. Order is T013 through T030. T027 and T028 both wait on T026. T030 is Sequencing step 31's assertion edits, placed before the harness run.
- **Verification (T031)**: After every implementation task. This is Sequencing step 30's unit command.
- **Documentation (T032)**: After T031 is green. This is Sequencing step 32.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001 starts immediately and does not wait on another story's implementation. T013 waits until T012 has added the last failing test. T014 waits on T013 because both edit `ai-platform/test/system/harness.ts`. T021 waits on T020 because both edit `ai-platform/src/quota-do/index.ts`. T024 waits on T023. T025 waits on T024. T026 waits on T025 because the handoff settlement and the journal insert meet on `term_id`. T027 and T028 both wait on T026. E2E-P3.4-01 passes at T028.
- **User Story 2 (P2)**: T002 waits on T001, T003 on T002, and T004 on T003, because they append to one file. T012 waits on T011 for the same reason. Those tests do not wait on another story's implementation. T018 waits on T017 because both follow the DO admission steps in `ai-platform/src/quota-do/index.ts`. T022 waits on T021. T023 waits on T022 and edits `ai-platform/src/journal/index.ts` before T026. E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 pass once the worker uses the T022 mapper. E2E-P3.4-11 passes at T022.
- **User Story 3 (P3)**: T005 waits on T004, T006 on T005, T007 on T006, and T008 on T007, because they append to one file. Those tests do not wait on another story's modules. T019 waits on T018 (same DO file). T029 waits on T028 and edits `ai-platform/src/admission/index.ts` after T022. E2E-P3.4-05 through E2E-P3.4-08 still need the worker path after T019. E2E-P3.4-10 passes at T026.
- **User Story 4 (P4)**: T009 waits on T008, T010 on T009, and T011 on T010, because they append to one file. Those tests do not wait on another story's modules. T015 waits on T014. T016 waits on T015 (same file). T017 waits on T016. T020 waits on T019 because settlement converts the reservation steps 5–7 stored. T030 waits on T029 and edits the test files T013 and T014 already touched. The "every earlier suite stays green" sentence is the review's run, not T031.

### 7.3 Parallel Opportunities

- T001–T012 are not marked `[P]`. They all write `ai-platform/test/system/admission-settlement.system.test.ts`.
- T013 and T014 both write `ai-platform/test/system/harness.ts`. T014 waits until T013 has finished.
- T015, T016, T018, T019, T020, and T021 share `ai-platform/src/quota-do/index.ts`. They stay in id order.
- T022 and T029 share `ai-platform/src/admission/index.ts`. T029 waits until T022 has finished.
- T023 and T026 share `ai-platform/src/journal/index.ts`. T026 waits until T023 has finished.
- T027 writes `ai-platform/src/rollup/index.ts`. T028 writes `ai-platform/src/capability/index.ts`, `ai-platform/src/discovery/index.ts`, and `ai-platform/src/entitlement/index.ts`. Both wait on T026. Neither edits the other's files.
- T031 and T032 are single tasks. T032 waits until T031 is green.
- No task line is marked `[P]`.

---

## 8. Implementation Waves

### Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Complete a request charged to a term (Priority: P1)` — paths: `ai-platform/test/system/admission-settlement.system.test.ts`

### Wave 2

- T002–T004 [US2] — subphase: `### 3.2 User Story 2 - Refuse a request the term does not allow (Priority: P2) (part 1)` — paths: `ai-platform/test/system/admission-settlement.system.test.ts`

### Wave 3

- T005–T008 [US3] — subphase: `### 3.3 User Story 3 - Exhaust a term and activate the successor (Priority: P3)` — paths: `ai-platform/test/system/admission-settlement.system.test.ts`

### Wave 4

- T009–T011 [US4] — subphase: `### 3.4 User Story 4 - Settle each request once (Priority: P4)` — paths: `ai-platform/test/system/admission-settlement.system.test.ts`

### Wave 5

- T012 [US2] — subphase: `### 3.5 User Story 2 - Refuse a request the term does not allow (Priority: P2) (part 2)` — paths: `ai-platform/test/system/admission-settlement.system.test.ts`

### Wave 6

- T013–T014 [US1] — subphase: `### 4.1 User Story 1 - Complete a request charged to a term (Priority: P1) (part 1)` — paths: `ai-platform/test/system/harness.ts`, `ai-platform/test/system/capability-lifecycle.system.test.ts`, `ai-platform/test/system/entitlement-grant-interplay.system.test.ts`, `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts`, `ai-platform/test/system/golden-journey.system.test.ts`, `ai-platform/test/system/lifecycle-interplay.system.test.ts`, `ai-platform/test/system/quota-admission-interplay.system.test.ts`, `ai-platform/test/system/routing-policy-traffic.system.test.ts`, `ai-platform/test/system/settlement-integrity.system.test.ts`, `ai-platform/migrations/20261006120000_usage_term.sql`, `ai-platform/schema.snap.sql`, `ai-platform/test/e2e/harness/d1.ts`, `ai-platform/test/usage-summary.test.ts`, `ai-platform/test/identity.test.ts`, `ai-platform/test/plan-catalogue.test.ts`, `ai-platform/test/control.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `ai-platform/test/entitle-grant.test.ts`, `ai-platform/test/config-readers.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/discovery-http.test.ts`, `ai-platform/test/retention.test.ts`

### Wave 7

- T015–T017 [US4] — subphase: `### 4.2 User Story 4 - Settle each request once (Priority: P4) (part 1)` — paths: `ai-platform/src/quota-do/index.ts`, `ai-platform/src/quota-do/coverage.ts`

### Wave 8

- T018 [US2] — subphase: `### 4.3 User Story 2 - Refuse a request the term does not allow (Priority: P2) (part 1)` — paths: `ai-platform/src/quota-do/index.ts`

### Wave 9

- T019 [US3] — subphase: `### 4.4 User Story 3 - Exhaust a term and activate the successor (Priority: P3) (part 1)` — paths: `ai-platform/src/quota-do/index.ts`

### Wave 10

- T020 [US4] — subphase: `### 4.5 User Story 4 - Settle each request once (Priority: P4) (part 2)` — paths: `ai-platform/src/credit/index.ts`, `ai-platform/src/quota-do/index.ts`

### Wave 11

- T021 [US1] — subphase: `### 4.6 User Story 1 - Complete a request charged to a term (Priority: P1) (part 2)` — paths: `ai-platform/src/quota-do/index.ts`

### Wave 12

- T022–T023 [US2] — subphase: `### 4.7 User Story 2 - Refuse a request the term does not allow (Priority: P2) (part 2)` — paths: `ai-platform/src/admission/index.ts`, `ai-platform/src/errors.ts`, `ai-platform/src/adapter.ts`, `ai-platform/src/identity/index.ts`, `ai-platform/src/usage-summary/index.ts`, `ai-platform/src/journal/index.ts`

### Wave 13

- T024–T026 [US1] — subphase: `### 4.8 User Story 1 - Complete a request charged to a term (Priority: P1) (part 3)` — paths: `ai-platform/src/pipeline/index.ts`, `ai-platform/src/worker.ts`, `ai-platform/src/manifest/index.ts`, `ai-platform/src/journal/index.ts`

### Wave 14

- T027 [US1] — subphase: `### 4.9 User Story 1 - Complete a request charged to a term (Priority: P1) (part 4)` — paths: `ai-platform/src/rollup/index.ts`
- T028 [US1] — subphase: `### 4.10 User Story 1 - Complete a request charged to a term (Priority: P1) (part 5)` — paths: `ai-platform/src/capability/index.ts`, `ai-platform/src/discovery/index.ts`, `ai-platform/src/entitlement/index.ts`

### Wave 15

- T029 [US3] — subphase: `### 4.11 User Story 3 - Exhaust a term and activate the successor (Priority: P3) (part 2)` — paths: `ai-platform/src/dashboards/index.ts`, `ai-platform/src/soft-threshold/index.ts`, `ai-platform/src/admission/index.ts`

### Wave 16

- T030 [US4] — subphase: `### 4.12 User Story 4 - Settle each request once (Priority: P4) (part 3)` — paths: `ai-platform/test/system/capability-lifecycle.system.test.ts`, `ai-platform/test/system/entitlement-grant-interplay.system.test.ts`, `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts`, `ai-platform/test/system/golden-journey.system.test.ts`, `ai-platform/test/system/lifecycle-interplay.system.test.ts`, `ai-platform/test/system/quota-admission-interplay.system.test.ts`, `ai-platform/test/system/routing-policy-traffic.system.test.ts`, `ai-platform/test/system/settlement-integrity.system.test.ts`, `ai-platform/test/usage-summary.test.ts`, `ai-platform/test/identity.test.ts`, `ai-platform/test/plan-catalogue.test.ts`, `ai-platform/test/control.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `ai-platform/test/entitle-grant.test.ts`, `ai-platform/test/config-readers.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/discovery-http.test.ts`, `ai-platform/test/retention.test.ts`

### Wave 17

- T031 — subphase: `### 5.1 Unit harness` — paths: `ai-platform/test/system/admission-settlement.system.test.ts`

### Wave 18

- T032 — subphase: `### 6.1 Quickstart` — paths: `specs/068-abo-p3-4-admission-settlement-against-terms/quickstart.md`
