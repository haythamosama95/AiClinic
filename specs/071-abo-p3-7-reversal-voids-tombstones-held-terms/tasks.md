# Tasks: Reversal voids, tombstones, held terms and operator voids

**Input**: Design documents from `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged unit in **Consumes Binding**: P3.6 (complimentary and adjustment grant semantics, ceiling policy, `suspend` / `resume` / `inspectCoverage`). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/` (`contracts/void-for-reversal.md`, `contracts/release-held-and-void-grant.md`, `contracts/list-grants-for-void.md`). There is no `research.md`. `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id in the spec Test plan, written to fail before reversal voids, tombstones, held release, and operator voids exist. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase. No Polish phase. Task ids follow plan Sequencing. Sequencing step 22's `cd ai-platform && npm test && npm run test:e2e` is the review's earlier-suite run (SC-002, rule S2), not a task. That step's `quickstart.md` write is T022.

**Task count**: 22. Size M is 20–32 (rule S3). The count is nine E2E tasks (Sequencing steps 1–9), eleven implementation tasks (steps 10–20), one verification task (the unit harness, step 21), and `quickstart.md` (the write named in step 22). It is not padded.

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
- **Spec Kit artifacts**: `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/`
- `data-model.md` and `contracts/` stay plan-phase artifacts. `ai-platform/src/quota-do/index.ts`, `ai-platform/src/admission/index.ts`, `ai-platform/src/coverage/calendar.ts`, and `packages/vendor-contracts/**` stay as they are. `coverClinic()`'s paid envelope and its grant call stay unchanged. Do not rewrite complimentary or adjustment grant application, ceiling policy, or `suspend` / `resume` / `inspectCoverage` (rule S7). Do not follow `origin_grant_id` onto another installation (P3.8). Do not decide the ABO reversal effect, retry a transient void, or raise the ABO reversal alert (P4.5). `/control/*` stays until P3.10 (rule S9). Revoking a credential, revoking Access sessions, and rotating a machine key are not methods this unit adds.

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`. The unit command is that file only, under `vitest.workers.config.ts`. `coverClinic()` remains the paid-grant helper in `ai-platform/test/system/harness.ts`. Do not edit `coverClinic()`'s paid envelope or its grant call. T001 exports `signCoverAbo(body)` from that harness. The four `VendorMethod` names stay until the implementation task that adds each method. A `voidForReversal` call sends `contract_version`, `grant_id`, `reversal_id`, `reason`, `evidence_sha256`, `partial`, `abo_kid`, and `abo_signature`. `reversal_id` and `evidence_sha256` are 64 lowercase hex characters. `abo_signature` is `signCoverAbo` over `{contract_version, grant_id, reversal_id, reason, evidence_sha256, partial}` (no `abo_kid`, no `abo_signature`). `abo_kid` is the cover-clinic ABO kid. HP calls use `coverClinicSigner()` the way a complimentary grant does: `operation.op` is `releaseHeld` or `voidGrant`, and `operation.params` is `{contract_version, access_jwt, grant_id, reason}`. `actor_email` is `VENDOR_OPERATOR_EMAIL`. After `coverClinic()`, do not move the clock backward of the credential's `activates_at`. `mintAat` is reminted after any `setTestClock` that passes its `exp`. No `sleep` over 2 s. No ABO worker is constructed. `runDurableObjectAlarm` runs before a clinic void's D1, R2, or replay assertion. Tombstone assertions do not wait for an alarm. Do not modify `packages/vendor-contracts`.

### 3.1 User Story 1 - Void a paid term for a reversal (Priority: P1) (part 1)

**Independent Test**: E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, E2E-P3.7-04, E2E-P3.7-08, and E2E-P3.7-09 in harness H-AP.

- [X] T001 [US1] Add the failing test `E2E-P3.7-01 A15 void of the active term holds T2 and refuses coverage_lapsed reversed` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`, and export `signCoverAbo(body)` from `ai-platform/test/system/harness.ts` — red test, FR-001, FR-002, E2E-P3.7-01. `signCoverAbo` uses the ABO key `coverClinic()` already registers. Do not change `coverClinic()`. Do not add `voidForReversal`, `releaseHeld`, `voidGrant`, or `listGrantsForVoid` to `VendorMethod`. `coverClinic()` once, then a second paid grant so T2 is `queued`. `voidForReversal` for T1's `grant_id` with `partial` false is `applied`. `inspectCoverage` shows T1 `ended` with `end_reason` `reversed` and T2 `held`. `invoke` `POST /v1/requests` is `coverage_lapsed` with reason `reversed`. Run:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/reversal-voids-held-terms.system.test.ts
```

The run fails because `voidForReversal` is not a method, so T2 is not `held` and the clinic request is not `coverage_lapsed` with reason `reversed`.

- [X] T002 [US1] Add the failing test `E2E-P3.7-02 void of a queued term removes that term and leaves the active term` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` — red test, FR-001, FR-003, E2E-P3.7-02. Depends on T001 (same file). `coverClinic()` plus a queued paid grant. `voidForReversal` for the queued grant removes that term (`ended`, `end_reason` `reversed`). The active term stays `active`. Do not add `voidForReversal` to `VendorMethod`. The unit command fails because a void of the queued grant does not remove that term.

- [X] T003 [US1] Add the failing test `E2E-P3.7-03 A17 void of an ended term is recorded only` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` — red test, FR-001, FR-004, E2E-P3.7-03. Depends on T002 (same file). `coverClinic()`, advance to `ends_at`, `runDurableObjectAlarm`, so the term has ended `expired`. `voidForReversal` for that grant does not change `end_reason` or any other term. After `runDurableObjectAlarm`, a `grant_void` row exists for that `grant_id`. Do not add `voidForReversal` to `VendorMethod`. The unit command fails because a void of the ended grant is not recorded as `grant_void`.

- [X] T004 [US1] Add the failing test `E2E-P3.7-04 void before the grant stores a tombstone and the later grant is voided` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` — red test, FR-001, FR-005, E2E-P3.7-04. Depends on T003 (same file). `voidForReversal` for a paid `grant_id` that has no `grant_ledger` row is `applied`. The receipt has `installation_id` and `org_id` `00000000-0000-0000-0000-000000000000`, `ledger_seq` 0, and `term_ids` `[]`. A `grant_void` row and `grant-ledger/<grant_id>.void.ndjson` exist. No `coverage_event` was inserted for that call. A later paid `vendorCall("grant")` with that `grant_id` is `rejected` with `code` `voided`. Tombstone assertions do not wait for an alarm. Do not add `voidForReversal` to `VendorMethod`. The unit command fails because the pre-grant void does not store a tombstone and the later grant is not `rejected` with `voided`.

**Checkpoint**: E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, and E2E-P3.7-04 exist and fail.

### 3.2 User Story 2 - Release a held term or void a grant (Priority: P2)

**Independent Test**: E2E-P3.7-05 and E2E-P3.7-06 in harness H-AP.

- [X] T005 [US2] Add the failing test `E2E-P3.7-05 releaseHeld re-queues a held term and activates it when nothing is active` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` — red test, FR-008, E2E-P3.7-05. Depends on T004 (same file). Void the active grant while two terms are queued, so both become `held`. `releaseHeld` on the first held grant makes that term `active`. `releaseHeld` on the second makes that term `queued` at the end, and the first stays `active`. HP `operation.op` is `releaseHeld`. Do not add `releaseHeld` to `VendorMethod`. The unit command fails because `releaseHeld` is not a method.

- [X] T006 [US2] Add the failing test `E2E-P3.7-06 voidGrant ends an active complimentary term and activates the successor` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` — red test, FR-009, FR-007, E2E-P3.7-06. Depends on T005 (same file). A complimentary grant is `active` and a later grant is `queued`. `voidGrant` ends the complimentary term with `end_reason` `voided` and the successor becomes `active`. After `runDurableObjectAlarm`, `grant_void.source` is `operator`, `evidence_sha256` is that call's assertion challenge, and `grant-ledger/<grant_id>.void.ndjson` exists. HP `operation.op` is `voidGrant`. Do not add `voidGrant` to `VendorMethod`. Do not change the complimentary grant branch. The unit command fails because `voidGrant` is not a method.

**Checkpoint**: E2E-P3.7-05 and E2E-P3.7-06 exist and fail.

### 3.3 User Story 3 - List grants made with one credential (Priority: P3)

**Independent Test**: E2E-P3.7-07 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [X] T007 [US3] Add the failing test `E2E-P3.7-07 listGrantsForVoid lists that credential inside the window` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` — red test, FR-010, E2E-P3.7-07. Depends on T006 (same file). Two paid grants share `operator_credential_id` `cred-001`, which is not an active operator credential. `listGrantsForVoid` with that id and a window that covers both `applied_at` values is `ok`, `code` empty, envelope `receipt` absent, and `detail` is those rows ordered by `applied_at` then `grant_id`. A window that matches nothing is `ok` with `[]`. A missing bound, a non-timestamp, or `applied_from` greater than `applied_to` is `rejected` with `code` `window_invalid` and empty `detail`. Do not add `listGrantsForVoid` to `VendorMethod`. Do not change `listGrants`. The unit command fails because `listGrantsForVoid` is not a method.

**Checkpoint**: E2E-P3.7-07 exists and fails.

### 3.4 User Story 1 - Void a paid term for a reversal (Priority: P1) (part 2)

**Independent Test**: E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, E2E-P3.7-04, E2E-P3.7-08, and E2E-P3.7-09 in harness H-AP.

- [X] T008 [US1] Add the failing test `E2E-P3.7-08 reversal replay is already_applied, a changed body is conflict, and a rejected call does not consume reversal_id` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` — red test, FR-001, FR-006, E2E-P3.7-08. Depends on T007 (same file). After an applied `partial` false void and `runDurableObjectAlarm`, the same `reversal_id`, `grant_id`, `reason`, `evidence_sha256`, and `partial` false is `already_applied` with the original receipt. Changing any one of those four is `conflict` and leaves the stored void unchanged. A bad ABO signature is `rejected` with `code` `bad_signature` and writes nothing. A new `reversal_id` with `partial` true is `rejected` with `code` `partial_void` and writes no row, no R2 object, and no coverage event. A missing or non-boolean `partial` is `rejected` with `code` `partial_invalid` and writes nothing. That unused `reversal_id` then applies with `partial` false. Do not add `voidForReversal` to `VendorMethod`. The unit command fails because a replay is not `already_applied` and `partial` true is not `partial_void`.

- [X] T009 [US1] Add the failing test `E2E-P3.7-09 an applied void writes grant_void, the R2 object, and coverage events` in `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` — red test, FR-007, E2E-P3.7-09. Depends on T008 (same file). `coverClinic()`, then `voidForReversal` with `partial` false. After `runDurableObjectAlarm`, D1 has the `grant_void` row (`source` `reversal`, the call's `reason` and `evidence_sha256`), R2 `grant-ledger/<grant_id>.void.ndjson` is one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}`, a `coverage_event` exists, and the receipt's `installation_id` and `org_id` equal that `grant_ledger` row. Do not add `voidForReversal` to `VendorMethod`. The unit command fails because the applied void does not write the D1 row, the R2 object, and a coverage event.

**Checkpoint**: E2E-P3.7-08 and E2E-P3.7-09 exist and fail. User Story 1's six tests are red.

---

## 4. Implementation

**Purpose**: Sequencing steps 10–20. Each step starts after T001–T009 exist and fail. Within a subphase the tasks run in id order. Do not edit `ai-platform/src/quota-do/index.ts`, `ai-platform/src/admission/index.ts`, or `ai-platform/src/coverage/calendar.ts`. Admission already refuses `coverage_lapsed` with `coverage_reason` `reversed` when the last ended term has `end_reason` `reversed`. Do not modify `packages/vendor-contracts`. Do not change `coverClinic()`. A `partial` true call writes nothing and raises no platform alert. Leave the `signCoverAbo` export from T001 in place.

### 4.1 User Story 1 - Void a paid term for a reversal (Priority: P1) (part 1)

**Independent Test**: E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, E2E-P3.7-04, E2E-P3.7-08, and E2E-P3.7-09 in harness H-AP.

- [X] T010 [US1] Add `ai-platform/migrations/20261006140000_grant_void.sql` — produces the append-only `grant_void` table, FR-005, FR-007, E2E-P3.7-04, E2E-P3.7-09. Depends on T009. Columns `grant_id` (primary key), `reason`, `source`, `evidence_sha256`, `at`. `source` is `reversal` or `operator`. Append-only triggers reject update and delete, matching `grant_ledger`.

- [X] T011 [US1] Add `voidForReversal` on `VendorEntrypoint` (class M) in `ai-platform/src/vendor/entrypoint.ts`, and add `voidForReversal` to `VendorMethod` in `ai-platform/test/system/harness.ts` — produces the signature gate, FR-001, FR-006, E2E-P3.7-08. Depends on T010. `signCoverAbo` is already exported by T001. The signed body is `{contract_version, grant_id, reversal_id, reason, evidence_sha256, partial}`. Verify it with `verifyGrantSignature` and the same `service_key` rules as a paid grant. A bad signature is `rejected` with `bad_signature` and writes nothing. A missing or non-boolean `partial` is `rejected` with `partial_invalid` and empty `detail`, before the signature check, and writes nothing. This task does not apply a void. Do not add `releaseHeld`, `voidGrant`, or `listGrantsForVoid` to `VendorMethod`.

- [X] T012 [US1] On `voidForReversal` in `ai-platform/src/vendor/entrypoint.ts`, replay a stored void and reject `partial` true when none is stored — produces `already_applied`, `conflict`, and `partial_void`, FR-006, E2E-P3.7-08. Depends on T011 (same file). When the signature is valid and a `grant_void` row already exists whose R2 receipt `reversal_id` matches, the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false returns `already_applied` and that receipt. Any difference in those four, including `partial` true, returns `conflict` and writes nothing. When no void is stored, `partial` true returns `rejected` with `partial_void` and empty `detail`, and writes no `grant_void` row, no R2 object, no coverage event, and no tombstone. The platform raises no alert for that rejection. A rejected call does not insert a row, so that `reversal_id` can still be applied with `partial` false.

- [X] T013 [US1] When `partial` is false and no void is stored, and `grant_ledger` has no row for `grant_id`, write the tombstone from `voidForReversal` in `ai-platform/src/vendor/entrypoint.ts` — produces the tombstone receipt, the D1 row, and the R2 object, FR-005, FR-007, E2E-P3.7-04. Depends on T012 (same file). The receipt uses `reversal_id`, nil UUID `00000000-0000-0000-0000-000000000000` for `installation_id` and `org_id`, `ledger_seq` 0, and `term_ids` `[]`. `envelope_sha256` is `sha256Hex` of the canonical signed body. `result` is `applied`. Insert `grant_void` with `source` `reversal` and the call's `reason` and `evidence_sha256`. Put R2 `grant-ledger/<grant_id>.void.ndjson` as one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}` plus a trailing newline. Do not insert `coverage_event` and do not call the DO.

- [X] T014 [US1] On both the paid and complimentary `grant` paths in `ai-platform/src/vendor/entrypoint.ts`, after the existing validation steps and before `callCoverageDo`, select `grant_void` by `grant_id` — produces `rejected` `voided`, FR-005, E2E-P3.7-04. Depends on T013 (same file). A row means `rejected` with `code` `voided` and empty `detail`. Do not change ceiling checks or complimentary apply.

**Checkpoint**: E2E-P3.7-04 and E2E-P3.7-08 still need the unit command after T014. E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, and E2E-P3.7-09 still need the clinic void path.

### 4.2 User Story 1 - Void a paid term for a reversal (Priority: P1) (part 2)

**Independent Test**: E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, E2E-P3.7-04, E2E-P3.7-08, and E2E-P3.7-09 in harness H-AP.

- [ ] T015 [US1] When `grant_ledger` has a row, call DO kind `void_for_reversal` from `voidForReversal` in `ai-platform/src/vendor/entrypoint.ts`, apply the term effect in `ai-platform/src/quota-do/coverage.ts`, and dispatch that kind from `GatewayObject.fetch` in `ai-platform/src/worker.ts` — produces `end_current`, `remove_queued`, and `none`, FR-002, FR-003, FR-004, E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03. Depends on T014. Call the DO on that row's `installation_id` only. Resolve the term with `origin_grant_id` or `grant_id` equal to the paid `grant_id`. Do not look at another installation. `active` or `grace` is `end_current`: that term becomes `ended` with `end_reason` `reversed` and no grace, and every `queued` term becomes `held`. `queued` or `held` is `remove_queued`: that term becomes `ended` with `end_reason` `reversed` and leaves the queue; other terms stay. `ended` or `exhausted` is `none`: the term row stays as it is.

- [ ] T016 [US1] In `buildCoverageSnapshot` in `ai-platform/src/quota-do/coverage.ts`, count `held` terms as `held_count` and set `reversed` when the last ended term ended `reversed` — produces the reversed clinic state, FR-002, E2E-P3.7-01. Depends on T015 (same file). `queued_count` stays the `queued` count. When no term is `active` or `grace` and the last ended term has `end_reason` `reversed`, set `state` and `reason` to `reversed`. Leave `expired`, `grace_exhausted`, and `exhausted` as they are. A clinic with no held terms still has `held_count` 0. Do not edit `ai-platform/src/admission/index.ts`.

- [ ] T017 [US1] Emit the clinic-void coverage events and ship `grant_void` plus the R2 void object from the alarm in `ai-platform/src/quota-do/coverage.ts`, and return that receipt as `applied` from `voidForReversal` in `ai-platform/src/vendor/entrypoint.ts` — produces the D1 row, the R2 object, and the coverage event, FR-007, E2E-P3.7-03, E2E-P3.7-09. Depends on T016. `end_current` emits `term_ended`, then `term_held` for each held term, then `grant_voided`. `remove_queued` emits `term_ended`, then `grant_voided`. `none` emits `grant_voided` only. `ledger_seq` is the `clinic_seq` on `grant_voided`. The receipt's `installation_id` and `org_id` are the `grant_ledger` row's ids. `term_ids` contains the ended term for `end_current` and `remove_queued`, and is empty for `none`. The alarm ship writes the `grant_void` row and the R2 void object the same way it writes `grant_ledger`, using `INSERT OR IGNORE` and skipping the R2 put when the object already exists. The R2 object is `grant-ledger/<grant_id>.void.ndjson`, one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}` plus a trailing newline, `source` `reversal`, and the call's `reason` and `evidence_sha256`. The DO keeps the receipt by `reversal_id` and returns it on a same-installation replay. `signReceipt` gains a `reversal_id` form. A tombstone still emits no coverage event.

**Checkpoint**: E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, E2E-P3.7-04, E2E-P3.7-08, and E2E-P3.7-09 still need the unit command after T017. E2E-P3.7-05, E2E-P3.7-06, and E2E-P3.7-07 still fail.

### 4.3 User Story 2 - Release a held term or void a grant (Priority: P2)

**Independent Test**: E2E-P3.7-05 and E2E-P3.7-06 in harness H-AP.

- [ ] T018 [US2] Add class-HP `releaseHeld` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`, apply `release_held` in `ai-platform/src/quota-do/coverage.ts`, dispatch that kind from `GatewayObject.fetch` in `ai-platform/src/worker.ts`, and add `releaseHeld` to `VendorMethod` in `ai-platform/test/system/harness.ts` — produces the re-queued or activated held term, FR-008, E2E-P3.7-05. Depends on T017. `operationParamsMatch` expects `{contract_version, access_jwt, grant_id, reason}`. The held term for that `grant_id` becomes `queued` at the next position. If no term is `active`, it becomes `active` with `starts_at` and `calendar_start` set to now. If a term is `active`, it stays `queued`. Emit `term_released`, and `term_activated` when it activates. The receipt uses `grant_id` and the `term_released` event's `clinic_seq` as `ledger_seq`. The same assertion challenge returns that receipt as `already_applied` before `assertion_used` would reject the replay. `releaseHeld` does not write `grant_void`.

- [ ] T019 [US2] Add class-HP `voidGrant` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`, apply `void_grant` in `ai-platform/src/quota-do/coverage.ts`, dispatch that kind from `GatewayObject.fetch` in `ai-platform/src/worker.ts`, and add `voidGrant` to `VendorMethod` in `ai-platform/test/system/harness.ts` — produces the operator void and the successor activation, FR-009, FR-007, E2E-P3.7-06. Depends on T018. The same params shape and the same challenge replay as `releaseHeld`. It takes no `evidence_sha256` input. The term that has not ended becomes `ended` with `end_reason` `voided`. If it was `active`, the first `queued` term by `position` becomes `active` with `starts_at` and `calendar_start` set to now. `grant_void.source` is `operator` and `evidence_sha256` is the assertion challenge from `runHpAssertionChecks`. The R2 object and the receipt (`grant_id`, `ledger_seq` of `grant_voided`) ship the same way as a reversal void. Do not change the complimentary apply branch.

**Checkpoint**: E2E-P3.7-05 and E2E-P3.7-06 still need the unit command after T019. E2E-P3.7-07 still fails.

### 4.4 User Story 3 - List grants made with one credential (Priority: P3)

**Independent Test**: E2E-P3.7-07 in harness H-AP. Earlier H-AP suites stay green (rule S2).

- [ ] T020 [US3] Add class-H `listGrantsForVoid` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts`, and add `listGrantsForVoid` to `VendorMethod` in `ai-platform/test/system/harness.ts` — produces the credential window list, FR-010, E2E-P3.7-07. Depends on T019. Use the same Access JWT check as `inspectCoverage`. Both `window.applied_from` and `window.applied_to` are required. Each must be a UTC ISO-8601 string ending in `Z` that `Date.parse` accepts, and the parsed `applied_from` must be less than or equal to `applied_to`. Otherwise `rejected` with `window_invalid` and empty `detail`. On success, select `grant_ledger` where `operator_credential_id` equals `credential_id` and `applied_at` is inside the inclusive bounds, ordered by `applied_at` then `grant_id`. Return `ok` with `detail` the JSON array of `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, receipt, applied_at}`, each `receipt` parsed as the stored receipt object. `code` is empty and the envelope `receipt` is absent. An empty array is `ok`. Do not read `operator_credential.status`. Do not change `listGrants`. The span has no maximum.

**Checkpoint**: E2E-P3.7-01 through E2E-P3.7-09 are ready for the unit command.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes. Earlier suites are the review's run (rule S2, Sequencing step 22). This task does not name that run. The review may change an assertion only when this unit's snapshot `held_count` or `reversed` state made that older expectation wrong. A clinic with no held terms still has `held_count` 0.

### 5.1 Unit harness

- [ ] T021 Run harness H-AP for this unit and confirm E2E-P3.7-01 through E2E-P3.7-09 pass together — produces the green run, FR-001 through FR-010, E2E-P3.7-01 through E2E-P3.7-09. Depends on T010 through T020 (and therefore on T001–T009). This task may edit only `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`. `ai-platform/src/quota-do/index.ts`, `ai-platform/src/admission/index.ts`, `ai-platform/src/coverage/calendar.ts`, and `packages/vendor-contracts/**` stay unchanged. Do not edit `coverClinic()`. SC-002 is the review's run of earlier suites, not this command.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/reversal-voids-held-terms.system.test.ts
```

---

## 6. Documentation

**Purpose**: Written after T021 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` and `contracts/` stay plan-phase artifacts. No other doc task.

### 6.1 Quickstart

- [ ] T022 Create `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-010, E2E-P3.7-01 through E2E-P3.7-09. Depends on T021. Sections: (1) what was implemented — `voidForReversal` (effects, tombstone, partial rejection, replay), `releaseHeld`, `voidGrant`, and `listGrantsForVoid`; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) harness command for this unit's tests only — the command below; (4) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/reversal-voids-held-terms.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

| ID | Chain |
| --- | --- |
| E2E-P3.7-01 | `coverClinic()` → second paid `vendorCall("grant")` → `vendorCall("voidForReversal")` for the active term → `voidForReversal` on `VendorEntrypoint` → DO `void_for_reversal` `end_current` → `inspectCoverage` → `invoke` `POST /v1/requests` |
| E2E-P3.7-02 | `coverClinic()` → queued paid `vendorCall("grant")` → `vendorCall("voidForReversal")` for the queued grant → DO `remove_queued` → `inspectCoverage` |
| E2E-P3.7-03 | `coverClinic()` → `setTestClock` to `ends_at` → `runDurableObjectAlarm` → `vendorCall("voidForReversal")` → DO effect `none` → `runDurableObjectAlarm` → `inspectCoverage` and D1 `grant_void` |
| E2E-P3.7-04 | `vendorCall("voidForReversal")` before any grant → D1 `grant_void` and R2 void object, no `coverage_event` → `vendorCall("grant")` with that id → `rejected` `voided` |
| E2E-P3.7-05 | `end_current` so two terms are `held` → `vendorCall("releaseHeld")` → DO `release_held` activates the first → `vendorCall("releaseHeld")` on the remaining held term re-queues it → `inspectCoverage` |
| E2E-P3.7-06 | complimentary `vendorCall("grant")` then a queued successor → `vendorCall("voidGrant")` → DO `void_grant` → `runDurableObjectAlarm` → `inspectCoverage`, D1 `grant_void`, R2 void object |
| E2E-P3.7-07 | paid grants on `grant_ledger` → `vendorCall("listGrantsForVoid")` |
| E2E-P3.7-08 | `vendorCall("voidForReversal")` → `runDurableObjectAlarm` → replay, conflict, bad signature, `partial` true, `partial` invalid, then the unconsumed `reversal_id` with `partial` false |
| E2E-P3.7-09 | `coverClinic()` → `vendorCall("voidForReversal")` `partial` false → `runDurableObjectAlarm` → D1 `grant_void`, R2 object, `coverage_event` |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T009)**: No Setup phase. T001 starts immediately. The other tests append in Sequencing order and are observed failing before T010: T001, T002, T003, T004, T005, T006, T007, T008, T009.
- **Implementation (T010–T020)**: Starts after T001–T009 exist and fail. Order is T010 through T020.
- **Verification (T021)**: After every implementation task. This is Sequencing step 21's unit command.
- **Documentation (T022)**: After T021 is green. This is the `quickstart.md` write in Sequencing step 22.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001 starts immediately and does not wait on another story's implementation. T002 waits on T001, T003 on T002, and T004 on T003, because they append to one file. T008 waits on T007, and T009 on T008, for the same reason. Those tests do not wait on another story's modules. T010 waits until T009 has added the last failing test. T011 waits on T010. T012 waits on T011, T013 on T012, and T014 on T013, because they edit `ai-platform/src/vendor/entrypoint.ts`. T015 waits on T014 and edits `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/worker.ts`, and `ai-platform/src/vendor/entrypoint.ts`. T016 waits on T015, and T017 on T016, because they edit `ai-platform/src/quota-do/coverage.ts`. E2E-P3.7-01 is T015 and T016, plus the ship in T017. E2E-P3.7-02 is T015. E2E-P3.7-03 is T015 and the `grant_void` ship in T017. E2E-P3.7-04 is T013 and T014. E2E-P3.7-08 is T011 and T012. E2E-P3.7-09 is T017.
- **User Story 2 (P2)**: T005 waits on T004 because it appends to one file. T006 waits on T005 for the same reason. Those tests do not wait on another story's modules. T018 waits on T017 because both edit `ai-platform/src/quota-do/coverage.ts` and `ai-platform/src/vendor/entrypoint.ts`. T019 waits on T018 for those files and `ai-platform/src/worker.ts`. E2E-P3.7-05 passes once T018 and the unit command have run. E2E-P3.7-06 passes once T019 and the unit command have run. The "every earlier suite stays green" sentence is the review's run, not T021.
- **User Story 3 (P3)**: T007 waits on T006 because it appends to one file. That test does not wait on another story's modules. T020 waits on T019 because both edit `ai-platform/src/vendor/entrypoint.ts`. E2E-P3.7-07 passes once T020 and the unit command have run.

### 7.3 Parallel Opportunities

- T001–T009 are not marked `[P]`. They all write `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`. T001 also writes `ai-platform/test/system/harness.ts`.
- T010 writes only `ai-platform/migrations/20261006140000_grant_void.sql`. T011 through T014 share `ai-platform/src/vendor/entrypoint.ts`. T011 also writes `ai-platform/test/system/harness.ts`. They stay in id order.
- T015 through T017 share `ai-platform/src/quota-do/coverage.ts`. T015 also edits `ai-platform/src/worker.ts` and `ai-platform/src/vendor/entrypoint.ts`. T017 also edits `ai-platform/src/vendor/entrypoint.ts`. They stay in id order.
- T018 and T019 share `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/worker.ts`, and `ai-platform/test/system/harness.ts`. They stay in id order.
- T020 writes `ai-platform/src/vendor/entrypoint.ts` and `ai-platform/test/system/harness.ts` only after T019, because Sequencing places the list after `voidGrant`.
- T021 and T022 are single tasks. T022 waits until T021 is green.
- No two subphases have disjoint paths that Sequencing allows in the same wave. No task line is marked `[P]`.

---

## 8. Implementation Waves

### Wave 1

- T001–T004 [US1] — subphase: `### 3.1 User Story 1 - Void a paid term for a reversal (Priority: P1) (part 1)` — paths: `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`, `ai-platform/test/system/harness.ts`

### Wave 2

- T005–T006 [US2] — subphase: `### 3.2 User Story 2 - Release a held term or void a grant (Priority: P2)` — paths: `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`

### Wave 3

- T007 [US3] — subphase: `### 3.3 User Story 3 - List grants made with one credential (Priority: P3)` — paths: `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`

### Wave 4

- T008–T009 [US1] — subphase: `### 3.4 User Story 1 - Void a paid term for a reversal (Priority: P1) (part 2)` — paths: `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`

### Wave 5

- T010–T014 [US1] — subphase: `### 4.1 User Story 1 - Void a paid term for a reversal (Priority: P1) (part 1)` — paths: `ai-platform/migrations/20261006140000_grant_void.sql`, `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/test/system/harness.ts`

### Wave 6

- T015–T017 [US1] — subphase: `### 4.2 User Story 1 - Void a paid term for a reversal (Priority: P1) (part 2)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/worker.ts`

### Wave 7

- T018–T019 [US2] — subphase: `### 4.3 User Story 2 - Release a held term or void a grant (Priority: P2)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/quota-do/coverage.ts`, `ai-platform/src/worker.ts`, `ai-platform/test/system/harness.ts`

### Wave 8

- T020 [US3] — subphase: `### 4.4 User Story 3 - List grants made with one credential (Priority: P3)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/test/system/harness.ts`

### Wave 9

- T021 — subphase: `### 5.1 Unit harness` — paths: `ai-platform/test/system/reversal-voids-held-terms.system.test.ts`

### Wave 10

- T022 — subphase: `### 6.1 Quickstart` — paths: `specs/071-abo-p3-7-reversal-voids-tombstones-held-terms/quickstart.md`
