# Tasks: Complimentary grants, ceilings, term adjustments and suspension

**Input**: Design documents from `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged unit in **Consumes Binding**: P3.5 (clinic states `grace` / `lapsed` and reasons `expired` / `grace_exhausted` in the snapshot). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/` (`contracts/complimentary-and-adjustment-grant.md`, `contracts/ceiling-policy.md`, `contracts/suspend-resume-inspect.md`). There is no `research.md`. `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id in the spec Test plan, written to fail before complimentary grants, ceilings, adjustments, and suspension exist. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase. No Polish phase. Task ids follow plan Sequencing, except Sequencing step 22.

**Task count**: 22. Size M is 20–32 (rule S3). The count is nine E2E tasks (Sequencing steps 1–9), eleven implementation tasks (steps 10–20), one verification task (the unit harness, step 21), and `quickstart.md` (step 23). It is not padded. `cd ai-platform && npm test && npm run test:e2e` is the review's earlier-suite run (SC-002, rule S2, Sequencing step 22), not a task.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — the Files paths in `plan.md`
- **ABO**: `abo/` — this unit does not change it. The harness does not start an ABO worker.
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified (rule S7)
- **Spec Kit artifacts**: `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/`
- `data-model.md` and `contracts/` stay plan-phase artifacts. `ai-platform/src/quota-do/index.ts`, `ai-platform/src/admission/index.ts`, `ai-platform/src/errors.ts`, `ai-platform/src/capability/index.ts`, `ai-platform/src/coverage/calendar.ts`, and `packages/vendor-contracts/**` stay as they are. `coverClinic()`'s paid envelope and its grant call stay unchanged. The existing DO kind `inspect` stays the quota inspect. `grant_void` is not added (reversals are P3.7). Entitlement, plan, and invoice tables and `/control/*` stay until P3.10 (rule S9). Paid AL-11 email bodies stay the object E2E-P3.3-08 already asserts, without an `attention` field.

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`. The unit command is that file only, under `vitest.workers.config.ts`. `coverClinic()` is the paid-grant helper in `ai-platform/test/system/harness.ts`. Do not edit `coverClinic()`'s paid envelope or its grant call. T001 exports `coverClinicSigner()` from that harness so a complimentary `vendorCall("grant")` can sign; the four `VendorMethod` names stay until T020. A complimentary or adjustment `vendorCall("grant")` passes `accessJwt`, `signer_credential_id`, `operation`, and `assertion` from `coverClinicSigner()`, using `encodeVendorAssertion` the way `coverClinic()` signs `publishPlanVersion`. `operation.op` is `grant`. `operation.params` is `{ contract_version, access_jwt, envelope }`. `actor_email` is `VENDOR_OPERATOR_EMAIL`. The envelope `source` is `{ kind: "complimentary", ref, operator_email, reason }` with `operator_email` equal to that actor. `placement` is `queue`. `grace` is `{ days: 7, cap_rule: "proportional" }`. `evidence.approvals` is one stub `{ credential_id, assertion: "stub" }` unless `ceiling_override` is present, in which case the package requires two stubs. `allowance_credits` is the cover plan's `max_allowance_per_month` except where a task says otherwise. After `coverClinic()`, do not move the clock backward of the credential's `activates_at`. `mintAat` is reminted after any `setTestClock` that passes its `exp`. No `sleep` over 2 s. No ABO worker is constructed. Do not modify `packages/vendor-contracts`. Alerts are the captured `send_email` bodies from `getCapturedVendorEmails` (rule V6).

### 3.1 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 1)

**Independent Test**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-07, and E2E-P3.6-09 in harness H-AP.

- [X] T001 [US1] Add the failing test `E2E-P3.6-01 `E2E-P3.6-01 A20 14-day complimentary grant to a paying clinic queues after current coverage` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`, and export `coverClinicSigner()` from `ai-platform/test/system/harness.ts` — red test, FR-001, FR-002, E2E-P3.6-01. `coverClinicSigner()` returns the `{ signerCredentialId, signerAuthenticator }` the cover-clinic bootstrap already stores. Do not change `coverClinic()`. Do not add `setCeilingPolicy`, `suspend`, `resume`, or `inspectCoverage` to `VendorMethod`. `coverClinic()` once. HP complimentary grant, unit `day`, count 14, with `operator_email` and `reason`. Result `applied`. The new `term` is `queued` and the paid term stays `active`. `runDurableObjectAlarm`. One captured email has `code` `AL-11`, `attention` true, and `operation.params.envelope.source` carrying that operator and reason. A second alarm does not send another AL-11 for that `grant_id`. Run:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/complimentary-grants-ceilings.system.test.ts
```

The run fails because a complimentary grant is `rejected` with `unit_not_allowed` and no queued term or attention AL-11 is produced.

- [X] T002 [US1] Add the failing test `E2E-P3.6-02 A27 365-day complimentary grant is exceeds_ceiling unless a second assertion overrides it` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` — red test, FR-003, FR-004, E2E-P3.6-02. Depends on T001 (same file). A 365-day complimentary grant is `rejected` with `code` `exceeds_ceiling`. The same envelope plus `ceiling_override` set to a second assertion, and two approval stubs, is `applied`, and the alarm email list contains one AL-12. A third call that puts the grant assertion in `ceiling_override` is `rejected`. The unit command fails because a 365-day grant is not `exceeds_ceiling` and a second assertion does not apply it.

- [X] T003 [US1] Add the failing test `E2E-P3.6-03 90-day window accepts 31 plus 31 days and rejects a further day` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` — red test, FR-003, FR-005, E2E-P3.6-03. Depends on T002 (same file). On one org, two 31-day complimentary grants are `applied`. A further 1-day grant is `rejected` with `exceeds_ceiling`. On a second org, a 31-day complimentary grant is `applied`, then `term_adjustment` `extend_days` 31 is `applied`, then a 1-day grant with `allowance_credits` 1 is `rejected` with `exceeds_ceiling`. The unit command fails because the third day-grant is not `exceeds_ceiling` from a 62-day window.

- [X] T004 [US1] Add the failing test `E2E-P3.6-04 Missing reason or operator_email is rejected` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` — red test, FR-006, E2E-P3.6-04. Depends on T003 (same file). One complimentary envelope omits `reason`. Another omits `operator_email`. Each result is `rejected` with `code` `bad_request`. The unit command fails because a missing `reason` or `operator_email` is `unit_not_allowed`, not `bad_request`.

- [X] T005 [US1] Add the failing test `E2E-P3.6-05 term_adjustment moves ends_at later, rejects a shortening, and shows a plan change` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` — red test, FR-007, E2E-P3.6-05. Depends on T004 (same file). `coverClinic()` plus `newClinic()`. `extend_days` 7 makes `ends_at` seven days later. A negative `extend_days` is `rejected`. `publishPlanVersion` writes `live-monthly` version 2 with capabilities `["clinic.plan_changed"]`. The adjustment `plan` selects that version. After `runDurableObjectAlarm` and `clearConfigCache`, `getCapabilities` no longer lists `clinic.visit_summary`. The unit command fails because `extend_days` 7 does not move `ends_at` and `/v1/capabilities` still lists `clinic.visit_summary`.

**Checkpoint**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, and E2E-P3.6-05 exist and fail.

### 3.2 User Story 2 - Suspend and resume a clinic (Priority: P2)

**Independent Test**: E2E-P3.6-06 in harness H-AP.

- [X] T006 [US2] Add the failing test `E2E-P3.6-06 Suspend returns 403 suspended before any other refusal and resume admits` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` — red test, FR-008, E2E-P3.6-06. Depends on T005 (same file). `setupPromotedFakePolicy`. `suspend` then `invoke` is 403 `suspended`. `setTestClock` to the active term's `ends_at` and `runDurableObjectAlarm`. The term has entered grace, and `invoke` is still 403 `suspended`. `resume`, then `invoke` is 200. The alarm emails include one AL-19 for suspend and one AL-19 for resume. Do not add `suspend` or `resume` to `VendorMethod` in this task. The unit command fails because `vendorCall("suspend")` is not a method, so the POST is not 403 `suspended`.

**Checkpoint**: E2E-P3.6-06 exists and fails.

### 3.3 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 2)

**Independent Test**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-07, and E2E-P3.6-09 in harness H-AP.

- [X] T007 [US1] Add the failing test `E2E-P3.6-07 A19 a 14-day trial then a paid grant queues the paid term` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` — red test, FR-009, E2E-P3.6-07. Depends on T006 (same file). No `coverClinic()` before the trial. Complimentary 14-day grant is `applied` and the term is `active` with `ends_at` 14 days after `calendar_start`. The following paid `vendorCall("grant")` is `applied` and that term is `queued`. The active term's interval does not overlap the queued term. The unit command fails because the trial grant is not `applied` and the paid term is not queued after it.

**Checkpoint**: E2E-P3.6-07 exists and fails.

### 3.4 User Story 3 - Inspect a clinic's coverage ledger (Priority: P3)

**Independent Test**: E2E-P3.6-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [X] T008 [US3] Add the failing test `E2E-P3.6-08 inspectCoverage returns the ledger and rejects a missing Access JWT` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` — red test, FR-010, E2E-P3.6-08. Depends on T007 (same file). After `coverClinic()`, `inspectCoverage` with an Access JWT returns `ok` and `detail` JSON whose `terms`, `grants`, and `reservations` match the DO rows for that org. The same call with no `access_jwt` is `rejected`. Do not add `inspectCoverage` to `VendorMethod` in this task. The unit command fails because `inspectCoverage` is not a method.

**Checkpoint**: E2E-P3.6-08 exists and fails.

### 3.5 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 3)

**Independent Test**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-07, and E2E-P3.6-09 in harness H-AP.

- [X] T009 [US1] Add the failing test `E2E-P3.6-09 Pilot grant of 30 days is accepted under the default policy` in `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` — red test, FR-003, FR-011, E2E-P3.6-09. Depends on T008 (same file). `setCeilingPolicy` with the launch ceilings and one assertion returns `ok` and `detail.version` 2. The same assertion again returns `ok` with that same version and does not insert a row. A complimentary grant, unit `day`, count 30, is `applied`. Do not add `setCeilingPolicy` to `VendorMethod` in this task. The unit command fails because `setCeilingPolicy` is not a method and a 30-day complimentary grant is not `applied`.

**Checkpoint**: E2E-P3.6-09 exists and fails. User Story 1's seven tests are red.

---

## 4. Implementation

**Purpose**: Sequencing steps 10–20. Each step starts after T001–T009 exist and fail. Within a subphase the tasks run in id order. Dates use the existing `addDuration` in `ai-platform/src/coverage/calendar.ts`. Do not edit that file. A complimentary `month` counts as `count × 31` days toward both day ceilings; `ends_at` still uses `addDuration`. A queued complimentary term has no `calendar_start` at validation. Do not edit `ai-platform/src/quota-do/index.ts`. Admission already refuses `suspended` before later refusal codes, and `applyDueBoundaries` already runs first. Do not change the existing DO kind `inspect`. Do not modify `packages/vendor-contracts`. The binding ceiling row stores `version`, `per_grant_max_days`, `per_grant_max_allowance_months`, `window_days`, `window_max_days`, `window_max_allowance_months`, `max_paid_grace_days`, `paid_cap_rule`, `set_by`, and `assertion_sha256`. Launch values are 31, 1, 90, 62, 2, 7, and `proportional`.

### 4.1 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 1)

**Independent Test**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-07, and E2E-P3.6-09 in harness H-AP.

- [X] T010 [US1] Add `ai-platform/migrations/20261006130000_ceiling_policy.sql` and `readCurrentCeilingPolicy` in `ai-platform/src/vendor/entrypoint.ts` — produces the versioned policy row, FR-003, FR-011, E2E-P3.6-09. Depends on T009. The migration creates `ceiling_policy` and inserts version 1 with the launch numbers, `set_by` `''`, and `assertion_sha256` `''`. `version` is an integer primary key: 1 for that seed, then one greater for each later row. The reader returns the greatest `version`.

- [X] T011 [US1] On the paid `grant` path in `ai-platform/src/vendor/entrypoint.ts`, compare `grace.days` and `grace.cap_rule` to `max_paid_grace_days` and `paid_cap_rule` from the current `ceiling_policy` row — produces the paid ceiling check, FR-003, E2E-P3.6-01. Depends on T010 (same file). The launch row is 7 and `proportional`, so a paid grant that passes today still passes and `exceeds_plan_bound` still fires for the same illegal grace. Do not change `coverClinic()`'s paid envelope.

- [X] T012 [US1] Add `setCeilingPolicy` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts` — produces the next policy version, FR-003, E2E-P3.6-09. Depends on T011 (same file). Class HP. It takes the ceiling fields (`per_grant_max_days`, `per_grant_max_allowance_months`, `window_days`, `window_max_days`, `window_max_allowance_months`, `max_paid_grace_days`, `paid_cap_rule`); HP already supplies `access_jwt` and `assertion`. On `ok`, insert the next version (2 after the seed), set `set_by` to the Access email and `assertion_sha256` to the assertion challenge hash, and return `detail` as the JSON text of that row. `code` is empty and `receipt` is absent. `detail.version` is the returned policy version. When that challenge hash is already stored on a row, return `ok` with that row and do not insert. This lookup happens when `assertion_used` would otherwise reject the replay. Do not add the name to `VendorMethod` in this task.

- [X] T013 [US1] On `grant` in `ai-platform/src/vendor/entrypoint.ts`, when `source.kind` is `complimentary` or the kind is `term_adjustment`, require the Access JWT and the HP assertion over `{ contract_version, access_jwt, envelope }` — produces the complimentary and adjustment gate, FR-001, FR-006, FR-007, E2E-P3.6-01, E2E-P3.6-04, E2E-P3.6-05. Depends on T012 (same file). A missing `operator_email` or `reason` on a non-paid source is `rejected` with `bad_request` and empty `detail`. `placement` `immediate` stays `placement_not_supported`. A paid source on `term_adjustment` is `rejected` with `bad_request`. Leave the paid `abo_kid` path as it is.

**Checkpoint**: E2E-P3.6-04 still needs the unit command after T013. E2E-P3.6-01, E2E-P3.6-05, E2E-P3.6-07, and E2E-P3.6-09 still need the apply path. E2E-P3.6-09 still needs `setCeilingPolicy` on `VendorMethod`.

### 4.2 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 2)

**Independent Test**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-07, and E2E-P3.6-09 in harness H-AP.

- [X] T014 [US1] In `applyGrantRPC` in `ai-platform/src/quota-do/coverage.ts`, apply a complimentary `term` from the envelope duration and source — produces the queued or active complimentary term and the attention AL-11 body, FR-001, FR-002, FR-009, E2E-P3.6-01, E2E-P3.6-07. Depends on T013. It becomes `active` when no active, grace, or queued term exists, and `queued` otherwise. Idempotent replay by `grant_id` plus `envelope_sha256` returns the stored receipt before `assertion_used` rejects the replay. The AL-11 outbox body is the paid shape plus `attention: true`. `source_kind` and `kind` are stored from the envelope. A `day` count uses `addDuration` of exact days. Paid AL-11 bodies stay without `attention`.

- [X] T015 [US1] In that same apply transaction in `ai-platform/src/quota-do/coverage.ts`, enforce the current policy numbers passed on the request, and map the DO `exceeds_ceiling` result to `rejected` in `ai-platform/src/vendor/entrypoint.ts` — produces the per-grant and 90-day window check, FR-003, FR-004, FR-005, E2E-P3.6-02, E2E-P3.6-03. Depends on T014. A complimentary `day` contributes `count` days. A `month` contributes `count × 31` days. Per grant, days must be ≤ `per_grant_max_days` and `allowance_credits` must be ≤ `per_grant_max_allowance_months × plan.max_allowance_per_month`. The window is `window_days × 24` hours ending at this grant's `applied_at`. Sum earlier DO `grant` rows for this clinic whose `applied_at` is greater than this `applied_at` minus that span and less than or equal to this `applied_at`, plus this grant. Complimentary rows contribute their day figure and their `allowance_credits`. `term_adjustment` rows contribute `extend_days` and `add_allowance`. Days must be ≤ `window_max_days`. Credits must be ≤ `window_max_allowance_months ×` the grant's plan max. Otherwise the DO returns `exceeds_ceiling` and writes nothing.

- [X] T016 [US1] When `ceiling_override` is present, verify a second assertion in `ai-platform/src/vendor/entrypoint.ts` and, on a valid override, skip the ceiling check in `ai-platform/src/quota-do/coverage.ts` — produces the override apply and the AL-12 outbox, FR-004, E2E-P3.6-02. Depends on T015. The override operation is `{ op: "ceiling_override", params: { contract_version, access_jwt, envelope } }` and its envelope omits `ceiling_override`. The same challenge hash as the grant assertion, or a hash already in `assertion_used`, is `rejected` with `assertion_used`. A valid override skips the ceiling check, applies the grant, and writes an AL-12 outbox body `{ code: "AL-12", org_id, operation: { op: "grant", params: envelope } }` with `alert_key` `AL-12:<grant_id>`.

- [X] T017 [US1] In `applyGrantRPC` in `ai-platform/src/quota-do/coverage.ts`, apply `term_adjustment` to the active term only — produces the later end, the rejected shortening, and the plan change on the next capabilities read, FR-007, E2E-P3.6-05. Depends on T016 (same file). `extend_days` greater than 0 sets `ends_at` to `addDuration(ends_at, "day", extend_days, scale)`. A value that would move `ends_at` earlier is `rejected` with `bad_request` and writes nothing. `add_allowance` adds to `allowance` when present. `plan` replaces `plan_snapshot` from the published `plan_version` row, including `capabilities`. Queued terms are not updated. Idempotent by `grant_id`: the same id returns the first receipt. The apply emits the existing `grant_applied` outbox event so the alarm's mirror write stores the new `term.capabilities`. AL-11 is raised with `attention: true`.

**Checkpoint**: E2E-P3.6-01, E2E-P3.6-03, E2E-P3.6-05, and E2E-P3.6-07 still need the unit command after T017. E2E-P3.6-02 still needs the AL-12 email raiser. E2E-P3.6-06 and E2E-P3.6-08 still fail.

### 4.3 User Story 2 - Suspend and resume a clinic (Priority: P2)

**Independent Test**: E2E-P3.6-06 in harness H-AP.

- [X] T018 [US2] Add class-H `suspend` and `resume` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`, and set `hot.suspended` from `ai-platform/src/quota-do/coverage.ts` — produces the suspension flag and the AL-19 outbox, FR-008, E2E-P3.6-06. Depends on T017. Each takes `access_jwt`, `org_id`, and `reason`. Suspend sets `hot.suspended` to 1. Resume sets it to 0. Both return `ok` with `detail` the JSON from `buildCoverageSnapshot`. A second call in the same target state returns `ok` and does not emit another alert. The first transition emits AL-19 with `alert_key` `AL-19:suspend:<org_id>` or `AL-19:resume:<org_id>`. Do not edit `ai-platform/src/quota-do/index.ts`. Do not add the names to `VendorMethod` in this task. `GatewayObject.fetch` dispatch stays until T020.

**Checkpoint**: E2E-P3.6-06 still needs the harness method names, the fetch dispatch, and the AL-19 raiser.

### 4.4 User Story 3 - Inspect a clinic's coverage ledger (Priority: P3)

**Independent Test**: E2E-P3.6-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [X] T019 [US3] Add class-H `inspectCoverage` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`, and add the DO handler for kind `inspect_coverage` in `ai-platform/src/quota-do/coverage.ts` — produces the ledger read, FR-010, E2E-P3.6-08. Depends on T018. With an Access JWT it calls DO kind `inspect_coverage` and returns `ok` with `detail` JSON `{ terms, grants, reservations }` from the DO `term` rows, `grant` rows, and parsed `hot.reservations`. A missing Access JWT is `rejected` with `unauthenticated`. Do not change the existing DO kind `inspect`. Do not add the name to `VendorMethod` in this task. `GatewayObject.fetch` dispatch stays until T020.

**Checkpoint**: E2E-P3.6-08 still needs the harness method name and the fetch dispatch.

### 4.5 Dispatch, alerts, and harness methods

**Independent Test**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-07, and E2E-P3.6-09 in harness H-AP. E2E-P3.6-06 in harness H-AP. E2E-P3.6-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [ ] T020 [US1][US2][US3] In `GatewayObject.fetch` in `ai-platform/src/worker.ts`, dispatch `suspend`, `resume`, and `inspect_coverage`; in `GatewayObject.alarm`, send AL-12 and AL-19 the way AL-11 is sent, through new raisers in `ai-platform/src/alert/index.ts`; add `setCeilingPolicy`, `suspend`, `resume`, and `inspectCoverage` to `VendorMethod` in `ai-platform/test/system/harness.ts` — produces the live entry points and the two alert codes, FR-002, FR-004, FR-008, FR-010, E2E-P3.6-02, E2E-P3.6-06, E2E-P3.6-08, E2E-P3.6-09. Depends on T019. Leave the `coverClinicSigner()` export from T001 in place. Do not change `coverClinic()`. Paid AL-11 bodies stay without `attention`.

**Checkpoint**: E2E-P3.6-01 through E2E-P3.6-09 are ready for the unit command.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes. Earlier suites are the review's run (rule S2, Sequencing step 22). This task does not name that run.

### 5.1 Unit harness

- [ ] T021 Run harness H-AP for this unit and confirm E2E-P3.6-01 through E2E-P3.6-09 pass together — produces the green run, FR-001 through FR-011, E2E-P3.6-01 through E2E-P3.6-09. Depends on T010 through T020 (and therefore on T001–T009). This task may edit only `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`. `ai-platform/src/quota-do/index.ts`, `ai-platform/src/admission/index.ts`, `ai-platform/src/errors.ts`, `ai-platform/src/capability/index.ts`, `ai-platform/src/coverage/calendar.ts`, and `packages/vendor-contracts/**` stay unchanged. Do not edit `coverClinic()`. SC-002 is the review's run of earlier suites, not this command. The paid AL-11 body must stay without `attention`.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/complimentary-grants-ceilings.system.test.ts
```

---

## 6. Documentation

**Purpose**: Written after T021 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` and `contracts/` stay plan-phase artifacts. No other doc task.

### 6.1 Quickstart

- [ ] T022 Create `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-011, E2E-P3.6-01 through E2E-P3.6-09. Depends on T021. Sections: (1) what was implemented — complimentary grants, ceiling policy and the 90-day window, ceiling override, term adjustment, suspend and resume, and inspectCoverage; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) harness command for this unit's tests only — the command below; (4) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/complimentary-grants-ceilings.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

| ID | Chain |
| --- | --- |
| E2E-P3.6-01 | `coverClinic()` → `vendorCall("grant")` complimentary 14-day HP → `applyGrantRPC` queues the term → `runDurableObjectAlarm` → `raiseAl11GrantFromOutbox` → `getCapturedVendorEmails` |
| E2E-P3.6-02 | `vendorCall("grant")` 365-day → DO ceiling check `exceeds_ceiling` → same grant with `ceiling_override` and a second assertion → `applied` + AL-12 → same assertion reused as the override → `rejected` |
| E2E-P3.6-03 | two `vendorCall("grant")` 31-day calls, then a 1-day grant → `exceeds_ceiling`; a second org's `term_adjustment` `extend_days` is inside the same day sum |
| E2E-P3.6-04 | `vendorCall("grant")` with `reason` omitted, then with `operator_email` omitted → `rejected` `bad_request` |
| E2E-P3.6-05 | `vendorCall("grant")` `term_adjustment` +7 days, then a negative `extend_days`, then `adjustment.plan` → `runDurableObjectAlarm` → `getCapabilities` |
| E2E-P3.6-06 | `vendorCall("suspend")` → `invoke` `POST /v1/requests` 403 `suspended` → `setTestClock` to `ends_at` → `runDurableObjectAlarm` still 403 `suspended` → `vendorCall("resume")` → `invoke` 200 |
| E2E-P3.6-07 | complimentary 14-day `vendorCall("grant")` on an uncovered org → paid `vendorCall("grant")` queues |
| E2E-P3.6-08 | `vendorCall("inspectCoverage")` with an Access JWT → DO terms, grants, reservations → same call without the JWT → `rejected` |
| E2E-P3.6-09 | `vendorCall("setCeilingPolicy")` twice with one assertion → `vendorCall("grant")` 30-day `day` → `applied` |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T009)**: No Setup phase. T001 starts immediately. The other tests append in Sequencing order and are observed failing before T010: T001, T002, T003, T004, T005, T006, T007, T008, T009.
- **Implementation (T010–T020)**: Starts after T001–T009 exist and fail. Order is T010 through T020.
- **Verification (T021)**: After every implementation task. This is Sequencing step 21's unit command.
- **Documentation (T022)**: After T021 is green. This is Sequencing step 23.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001 starts immediately and does not wait on another story's implementation. T002 waits on T001, T003 on T002, T004 on T003, and T005 on T004, because they append to one file. T007 waits on T006, and T009 on T008, for the same reason. Those tests do not wait on another story's modules. T010 waits until T009 has added the last failing test. T011 waits on T010, T012 on T011, and T013 on T012, because they edit `ai-platform/src/vendor/entrypoint.ts`. T014 waits on T013 and edits `ai-platform/src/quota-do/coverage.ts`. T015 waits on T014 and edits that file and `ai-platform/src/vendor/entrypoint.ts`. T016 waits on T015, and T017 on T016, for those files. E2E-P3.6-01 and E2E-P3.6-07 are the complimentary apply from T014. E2E-P3.6-02 is T015 and T016, plus the AL-12 raiser in T020. E2E-P3.6-03 is T015. E2E-P3.6-04 is T013. E2E-P3.6-05 is T017. E2E-P3.6-09 is T010 and T012, plus the harness method name in T020.
- **User Story 2 (P2)**: T006 waits on T005 because it appends to one file. That test does not wait on another story's modules. T018 waits on T017 because both edit `ai-platform/src/quota-do/coverage.ts` and T018 also edits `ai-platform/src/vendor/entrypoint.ts`. E2E-P3.6-06 passes once T018, T020, and the unit command have run. The "every earlier suite stays green" sentence is the review's run, not T021.
- **User Story 3 (P3)**: T008 waits on T007 because it appends to one file. That test does not wait on another story's modules. T019 waits on T018 because both edit `ai-platform/src/vendor/entrypoint.ts` and `ai-platform/src/quota-do/coverage.ts`. E2E-P3.6-08 passes once T019, T020, and the unit command have run.
- **T020**: Waits on T019. It edits `ai-platform/src/worker.ts`, `ai-platform/src/alert/index.ts`, and `ai-platform/test/system/harness.ts`. It is the dispatch and alert path for E2E-P3.6-02, E2E-P3.6-06, E2E-P3.6-08, and E2E-P3.6-09.

### 7.3 Parallel Opportunities

- T001–T009 are not marked `[P]`. They all write `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`. T001 also writes `ai-platform/test/system/harness.ts`.
- T010 through T013 share `ai-platform/src/vendor/entrypoint.ts`. They stay in id order.
- T014 through T019 share `ai-platform/src/quota-do/coverage.ts`. T015, T016, T018, and T019 also edit `ai-platform/src/vendor/entrypoint.ts`. They stay in id order.
- T020 writes `ai-platform/src/worker.ts`, `ai-platform/src/alert/index.ts`, and `ai-platform/test/system/harness.ts` only after T019, because Sequencing places dispatch after the suspend, resume, and inspect handlers.
- T021 and T022 are single tasks. T022 waits until T021 is green.
- No two subphases have disjoint paths that Sequencing allows in the same wave. No task line is marked `[P]`.

---

## 8. Implementation Waves

### Wave 1

- T001–T005 [US1] — subphase: `### 3.1 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 1)` — paths: `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`, `ai-platform/test/system/harness.ts`

### Wave 2

- T006 [US2] — subphase: `### 3.2 User Story 2 - Suspend and resume a clinic (Priority: P2)` — paths: `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`

### Wave 3

- T007 [US1] — subphase: `### 3.3 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 2)` — paths: `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`

### Wave 4

- T008 [US3] — subphase: `### 3.4 User Story 3 - Inspect a clinic's coverage ledger (Priority: P3)` — paths: `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`

### Wave 5

- T009 [US1] — subphase: `### 3.5 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 3)` — paths: `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`

### Wave 6

- T010–T013 [US1] — subphase: `### 4.1 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 1)` — paths: `ai-platform/migrations/20261006130000_ceiling_policy.sql`, `ai-platform/src/vendor/entrypoint.ts`

### Wave 7

- T014–T017 [US1] — subphase: `### 4.2 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1) (part 2)` — paths: `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/vendor/entrypoint.ts`

### Wave 8

- T018 [US2] — subphase: `### 4.3 User Story 2 - Suspend and resume a clinic (Priority: P2)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/quota-do/coverage.ts`

### Wave 9

- T019 [US3] — subphase: `### 4.4 User Story 3 - Inspect a clinic's coverage ledger (Priority: P3)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/quota-do/coverage.ts`

### Wave 10

- T020 [US1][US2][US3] — subphase: `### 4.5 Dispatch, alerts, and harness methods` — paths: `ai-platform/src/worker.ts`, `ai-platform/src/alert/index.ts`, `ai-platform/test/system/harness.ts`

### Wave 11

- T021 — subphase: `### 5.1 Unit harness` — paths: `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts`

### Wave 12

- T022 — subphase: `### 6.1 Quickstart` — paths: `specs/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension/quickstart.md`
