# Tasks: Reconciliation, payout import and findings

**Input**: Design documents from `specs/085-abo-p4-10-reconciliation-payout-import-findings/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.8 (none; that unit row states no Outputs / freezes line). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`. `research.md` is not a task: Spikes is none, so the plan phase did not write it. `contracts/` is not a task: Freezes has no wire shape. `data-model.md` is not a task: the plan phase already wrote it. `quickstart.md` is written in Documentation after verification.

**Organization**: Two user stories, as the spec partitions them (`[US1]`, `[US2]`). Tests are one task per E2E id, written to fail before reconciliation exists. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 21. Size M is 20–32 (rule S3). The count is the two H-PAY CSV fixtures (2), the vitest include (1), one task per E2E id (9), one task per remaining Files path (migration, alert code, provider port, Paymob adapter, `runReconciliation`, `scheduled()` hook, ops routes) (7), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than the harness command in §6.1, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/src/vendor/entrypoint.ts` — consumed through the `PLATFORM` binding (`listGrants`, `getCoverage`, `readCoverageEvents`) and not modified
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — `canonicalize` and `CHANNEL_VERSIONS.vendorEntrypoint` are consumed and not modified
- **Spec Kit artifacts**: `specs/085-abo-p4-10-reconciliation-payout-import-findings/`
- Codebase is `abo`. One reconciliation function, `runReconciliation`. No second worker, hostname, or cron. `GET /ops/payout-imports` stays the existing empty response. `abo/src/work/reversal.ts` stays as it is, including `inquiry_disagrees`. `listGrants`, `getCoverage`, `readCoverageEvents`, `paymob_txn`, and `POST /ops/payments/{paymentId}/chargeback` stay unchanged. `capabilities().payouts` stays false

---

## 3. Setup

**Purpose**: Sequencing step 1, the scaffold the failing tests need. The `abo/` Worker already exists. The test file is created in §4.

### 3.1 User Story 2 - Payout import and resolve-finding (Priority: P2) — unrecorded-chargeback fixture

**Independent Test**: E2E-P4.10-05 and E2E-P4.10-06 in harness H-XW + H-PAY. Earlier suites stay green, and E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 still pass.

- [X] T001 [US2] Add the H-PAY payout CSV fixture in `abo/test/fixtures/paymob/payout-unrecorded-chargeback.csv` — produces the committed file for the unrecorded chargeback, FR-010, FR-015, E2E-P4.10-05. Depends on nothing. Header row exactly `transaction_id,type,gross_minor,fee_minor,net_minor,settled_at`. One data row: `transaction_id` `99001` (H-PAY stub transaction id in `abo/test/stubs/paymob/worker.ts`), `type` `chargeback`, integer minor units `gross_minor` `5000`, `fee_minor` `0`, `net_minor` `5000`, `settled_at` `2026-03-15T00:00:00.000Z`. Column mapping stays in the Paymob adapter and is not frozen. Leave `abo/test/system/reconciliation.cross-worker.test.ts` uncreated.

**Checkpoint**: `abo/test/fixtures/paymob/payout-unrecorded-chargeback.csv` exists with that one chargeback line.

### 3.2 User Story 2 - Payout import and resolve-finding (Priority: P2) — amount-mismatch fixture

**Independent Test**: E2E-P4.10-05 and E2E-P4.10-06 in harness H-XW + H-PAY. Earlier suites stay green, and E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 still pass.

- [X] T002 [US2] Add the H-PAY payout CSV fixture in `abo/test/fixtures/paymob/payout-amount-mismatch.csv` — produces the committed file for the amount mismatch and the omitted settled payment, FR-008, FR-009, FR-015, E2E-P4.10-06. Depends on nothing. Same header as T001. One data row: `transaction_id` `99001`, `type` `payment`, `gross_minor` `1`, `fee_minor` `0`, `net_minor` `1`, `settled_at` `2026-01-31T12:00:00.000Z` (last day of a month). The file has no second payment line. Leave the reconciliation test file uncreated.

**Checkpoint**: `abo/test/fixtures/paymob/payout-amount-mismatch.csv` exists with that one payment line.

### 3.3 User Story 1 - Daily reconciliation and findings (Priority: P1) — vitest include

**Independent Test**: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 in harness H-XW.

- [X] T003 [US1] Add the reconciliation test include in `abo/vitest.cross-worker.config.ts` — produces the H-XW include for this unit, FR-001, FR-014, E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-05, E2E-P4.10-06, E2E-P4.10-07, E2E-P4.10-08, E2E-P4.10-09. Depends on nothing. Add `test/system/reconciliation.cross-worker.test.ts` to the H-XW `include` list. The unit command still names only that file. Leave `abo/test/system/reconciliation.cross-worker.test.ts` uncreated. Leave `abo/src/reconciliation/run.ts` uncreated.

**Checkpoint**: The include lists `test/system/reconciliation.cross-worker.test.ts`. That file does not exist yet.

---

## 4. Tests

**Purpose**: Sequencing step 1 continued. One failing test per E2E id, all in `abo/test/system/reconciliation.cross-worker.test.ts`. Titles are prefixed with the E2E id. Harness H-XW (`abo/test/system/`, cross-worker vitest, real platform worker from source). H-PAY for E2E-P4.10-05 and E2E-P4.10-06 is the committed CSV plus the existing Paymob stub where a line's transaction id resolves through `paymob_txn`. The file imports `runReconciliation` from `abo/src/reconciliation/run.ts`. That module is absent, so the command fails. No scenario sleeps (rule V4). The 15-minute park and the 7-day payout window advance on the H-XW test clock. AL-10 is observed by capturing `send_email` (rule V6).

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/reconciliation.cross-worker.test.ts
```

### 4.1 User Story 1 - Daily reconciliation and findings (Priority: P1) — tests (part 1)

**Independent Test**: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 in harness H-XW.

- [X] T004 [US1] Add the failing test `E2E-P4.10-01` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-001, FR-014, E2E-P4.10-01. Depends on T003. Create the file and the shared setup. Title prefix `E2E-P4.10-01`. `runScheduled("0 6 * * *")` → `scheduled()` → `runReconciliation`. Grants and the transfer are read through `VendorEntrypoint.listGrants` over `PLATFORM`. A clean month built through the existing payment, complimentary-grant, and transfer paths → zero `finding` rows. The command fails because `abo/src/reconciliation/run.ts` does not exist.

- [X] T005 [US1] Add the failing test `E2E-P4.10-02` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-002, FR-004, FR-016, E2E-P4.10-02. Depends on T004 (same file). Title prefix `E2E-P4.10-02`. A paid grant is applied on the real platform worker with the testkit ABO key and no ABO payment. `runScheduled("0 6 * * *")` → `scheduled()` → `runReconciliation` → `listGrants`. Kind `grant_without_payment`. `send_email` received `AL-10`. Then the same `opsFetch` session `POST /ops/findings/{findingId}/resolve` with JSON `{ "note": "<string>" }`. One `finding_resolution` row for that `finding_id`. Do not assert that AL-10 stops or that a later reconciliation is clean. The command fails because `runReconciliation` and that resolve route are absent.

- [X] T006 [US1] Add the failing test `E2E-P4.10-03` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-005, FR-006, E2E-P4.10-03. Depends on T005 (same file). Title prefix `E2E-P4.10-03`. `runScheduled("0 6 * * *")` → `runReconciliation` → `listGrants`, compared with `operator_action`. Complimentary platform grant and no ABO `operator_action` → `grant_without_operator_action`. Transfer grant with no `beginTransfer` `operator_action` and no `transferOut` `grant_request` → `transfer_without_authorisation`. The command fails because `runReconciliation` is absent.

- [X] T007 [US1] Add the failing test `E2E-P4.10-04` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-003, E2E-P4.10-04. Depends on T006 (same file). Title prefix `E2E-P4.10-04`. The H-XW test clock advances more than 15 minutes, then `runScheduled("0 6 * * *")` → `runReconciliation`. Grant parked more than 15 minutes, payment `disposition` `grant`, no applied outcome → `payment_without_grant`. The harness does not sleep. The command fails because `runReconciliation` is absent.

- [X] T008 [US1] Add the failing test `E2E-P4.10-07` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-011, E2E-P4.10-07. Depends on T007 (same file). Title prefix `E2E-P4.10-07`. `runScheduled("0 6 * * *")` → `runReconciliation`. HMAC-valid success callback and no confirming inquiry → `callback_without_confirmation`. The command fails because `runReconciliation` is absent.

**Checkpoint**: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, and E2E-P4.10-07 exist and fail.

### 4.2 User Story 1 - Daily reconciliation and findings (Priority: P1) — tests (part 2)

**Independent Test**: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 in harness H-XW.

- [ ] T009 [US1] Add the failing test `E2E-P4.10-08` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-007, FR-012, E2E-P4.10-08. Depends on T008 (same file). Title prefix `E2E-P4.10-08`. `runScheduled("0 6 * * *")` → `runReconciliation` compares `coverage_view` with `getCoverage` for clinics with events in the last day, and checks full reversals for a void receipt or tombstone. Tampered `coverage_view` → `feed_divergence`. Full reversal without a void receipt, effect not `none` and not `tombstone` → `reversal_not_applied`. The command fails because `runReconciliation` is absent.

- [ ] T010 [US1] Add the failing test `E2E-P4.10-09` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-002, FR-013, E2E-P4.10-09. Depends on T009 (same file). Title prefix `E2E-P4.10-09`. `runScheduled("0 6 * * *")` → `runReconciliation` → `listGrants`. The test changes `signature` on one ABO `grant_outcome.receipt` whose `result` is `applied` or `already_applied`. The platform receipt stays as `listGrants` returns it. Kind `receipt_mismatch` and AL-10 on `send_email`. The tampered row is not a void receipt and not a transfer receipt. A missing `listGrants` row is the same check and does not get a new E2E id. The command fails because `runReconciliation` is absent.

**Checkpoint**: E2E-P4.10-08 and E2E-P4.10-09 exist and fail. E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, and E2E-P4.10-07 still fail.

### 4.3 User Story 2 - Payout import and resolve-finding (Priority: P2) — tests

**Independent Test**: E2E-P4.10-05 and E2E-P4.10-06 in harness H-XW + H-PAY. Earlier suites stay green, and E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 still pass.

- [ ] T011 [US2] Add the failing test `E2E-P4.10-05` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-001, FR-010, FR-015, E2E-P4.10-05. Depends on T001 and T010 (same test file as T010). Title prefix `E2E-P4.10-05`. `opsFetch` `POST /ops/payout-imports` with the raw bytes of `abo/test/fixtures/paymob/payout-unrecorded-chargeback.csv` → `handleOps` → `payoutLines` → `paymob_txn` → `runReconciliation`. Kind `unrecorded_reversal`. Then `opsFetch` `POST /ops/payments/{paymentId}/chargeback` on the existing chargeback route. Then `runScheduled("0 6 * * *")` → `runReconciliation`. After that chargeback, the grant void count is 1 and the term state is `ended`. The re-run inserts no finding. The command fails because `POST /ops/payout-imports` and `runReconciliation` are absent.

- [ ] T012 [US2] Add the failing test `E2E-P4.10-06` in `abo/test/system/reconciliation.cross-worker.test.ts` — red test, FR-008, FR-009, FR-015, E2E-P4.10-06. Depends on T002 and T011 (same file). Title prefix `E2E-P4.10-06`. `opsFetch` `POST /ops/payout-imports` with the raw bytes of `abo/test/fixtures/paymob/payout-amount-mismatch.csv` → `payoutLines` → `runReconciliation`. The payment created for `paymob_txn` `99001` has `amount_minor` other than `1`. Amount mismatch → `payout_unmatched`. A second payment is settled with `paid_at` more than 7 days before `2026-01-31T23:59:59.999Z` and is absent from that file → `payment_not_in_payout`. Assertions stay the finding kinds and `payout_line` fields. The command fails because `POST /ops/payout-imports` and `runReconciliation` are absent.

**Checkpoint**: E2E-P4.10-05 and E2E-P4.10-06 exist and fail. E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 still fail.

---

## 5. Implementation

**Purpose**: Sequencing steps 2–9. Starts after T004–T012 exist and those E2E tests fail. One reconciliation function. The import handler calls it before the response. Within a subphase the tasks run in id order.

### 5.1 User Story 1 - Daily reconciliation and findings (Priority: P1) — schema and alert

**Independent Test**: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 in harness H-XW.

- [ ] T013 [US1] Add migration `abo/migrations/0008_reconciliation.sql` — produces `finding_resolution`, `payout_import`, and `payout_line` with append-only abort triggers, FR-002, FR-015, FR-016, E2E-P4.10-02, E2E-P4.10-05, E2E-P4.10-06. Depends on T012. `finding` already exists; do not recreate it. `finding_resolution` columns: `finding_id`, `resolved_by`, `note`, `at`. `payout_import` columns: `import_id`, `provider_id`, `file_sha256`, `r2_key`, `imported_by`, `period`. `payout_line` columns: `import_id`, `line_no`, `kind` (`payment`, `refund`, `chargeback`, `fee`, `other`), `gross_minor`, `fee_minor`, `net_minor`, `settled_at`, `payment_id` (null if unmatched). Leave `abo/src/reconciliation/run.ts` uncreated.

**Checkpoint**: The three tables exist and reject updates and deletes. E2E-P4.10-01 through E2E-P4.10-09 still fail.

- [ ] T014 [US1] Add `AL-10` in `abo/src/alert/index.ts` — produces the reconciliation alert code and its daily repeat, FR-002, E2E-P4.10-02, E2E-P4.10-09. Depends on T013. Add `AL-10` to `AlertCode`. Daily `next_send_at`, same interval as `AL-16`. Callers use `raiseAlert(env, "AL-10", "AL-10:" + finding_id, finding_id)`. `active` stays 1. A later run that still fails does not insert a second finding row; the daily `next_send_at` repeats the email while that alert stands. Leave the ops routes and `runReconciliation` uncreated.

**Checkpoint**: `AlertCode` includes `AL-10`. E2E-P4.10-01 through E2E-P4.10-09 still fail.

### 5.2 User Story 2 - Payout import and resolve-finding (Priority: P2) — payout parse

**Independent Test**: E2E-P4.10-05 and E2E-P4.10-06 in harness H-XW + H-PAY. Earlier suites stay green, and E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 still pass.

- [ ] T015 [US2] Add `PayoutLine` and `payoutLines` on `ProviderPort` in `abo/src/provider/port.ts` — produces the port the Paymob adapter implements, FR-015, E2E-P4.10-05, E2E-P4.10-06. Depends on T014. `PayoutLine` is `{ kind, payment_id, gross_minor, fee_minor, net_minor, settled_at }`. `payoutLines` takes the uploaded report file and returns `PayoutLine[]`. `capabilities().payouts` stays false. Leave `abo/src/provider/paymob/adapter.ts` without `payoutLines` in this task.

**Checkpoint**: `ProviderPort` names `payoutLines`. E2E-P4.10-01 through E2E-P4.10-09 still fail.

- [ ] T016 [US2] Implement `payoutLines` in `abo/src/provider/paymob/adapter.ts` — produces CSV parsing and the `paymob_txn` lookup, FR-008, FR-009, FR-010, FR-015, E2E-P4.10-05, E2E-P4.10-06. Depends on T015. The adapter owns the header `transaction_id,type,gross_minor,fee_minor,net_minor,settled_at`. `type` is `payment`, `refund`, `chargeback`, `fee`, or `other`. Amounts are integers in minor units. `settled_at` is ISO-8601. `transaction_id` is looked up as `paymob_txn.txn_id`. The line's `payment_id` is that row's `payment_id`, or null when no row exists. Reached through `providerForId`. `capabilities().payouts` stays false. Leave `runReconciliation` and the import route uncreated.

**Checkpoint**: `payoutLines` parses T001 and T002. E2E-P4.10-01 through E2E-P4.10-09 still fail.

### 5.3 User Story 1 - Daily reconciliation and findings (Priority: P1) — eleven checks

**Independent Test**: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 in harness H-XW.

- [ ] T017 [US1] Implement `runReconciliation` in `abo/src/reconciliation/run.ts` — produces the eleven checks, one `finding` per failing kind and subject, and AL-10, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-05, E2E-P4.10-06, E2E-P4.10-07, E2E-P4.10-08, E2E-P4.10-09. Depends on T016. `runReconciliation(env)` reads the ABO clock. A failing check inserts one `finding` when no row with that `kind` and `subject` exists. `finding_id` is a ULID from the existing `ulid` helper. `detected_at` is the clock. The insert also writes `fact_log` for that row. A later run that still fails does not insert a second row. A later run that passes does not delete the row. AL-10 is `raiseAlert(env, "AL-10", "AL-10:" + finding_id, finding_id)` when the row is inserted. `detail` is the short identifier of the other side (`grant_id`, `payment_id`, `period`, `checkout_id`, or `effect`), or an empty string when there is no other side. `listGrants` and `getCoverage` use `contract_version` from `CHANNEL_VERSIONS.vendorEntrypoint`. `listGrants` is called with no filter. Clinics for `feed_divergence` are the `org_id` values on `readCoverageEvents` pages, starting at `after = 0`, whose event `at` is within 24 hours before the ABO clock. Snapshot comparison uses `canonicalize` from `vendor-contracts`.

  Pass rules, one `finding` when the pass rule fails:

  - `payment_without_grant`, subject `payment_id`: payment `disposition = grant` has `grant_outcome.result` `applied` or `already_applied` for `grantIdPaid(payment_id)` within 15 minutes of `payment.confirmed_at`. No outcome yet, and `confirmed_at` is not yet 15 minutes old, also passes.
  - `grant_without_payment`, subject `grant_id`: `listGrants` row with `source_kind` `paid` has `grant_id = grantIdPaid(payment_id)` of an ABO `payment`.
  - `grant_without_operator_action`, subject `grant_id`: `listGrants` row with `source_kind` `complimentary` has some `operator_action.action_id` with `grantIdComp(action_id) = grant_id`.
  - `transfer_without_authorisation`, subject `grant_id`: `listGrants` row with `source_kind` `transfer` has `grant_request.source_kind = transfer` for that `grant_id`, and `operator_action.action = beginTransfer` whose `subject` is that grant's `org_id`.
  - `reversal_not_applied`, subject `reversal_id`: full reversal (`is_full = 1`) passes when `effect` is `none` or `tombstone`, or `reversal_outcome` exists.
  - `payout_unmatched`, subject `import_id` + `:` + `line_no`: payout line `kind = payment` has `payment_id` set and `gross_minor = payment.amount_minor`.
  - `payment_not_in_payout`, subject `payment_id`: runs only for periods that have an import. `payout_import.period` is `YYYY-MM`. The period end is `23:59:59.999` UTC on the last day of that month. `paid_at` is the settled time. Passes when a `payout_line` with `kind = payment` and that `payment_id` exists on an import of that `period`, or `paid_at` is not more than 7 days before the period end.
  - `unrecorded_reversal`, subject `import_id` + `:` + `line_no`: payout line `kind` `refund` or `chargeback` has a `reversal` row for that `payment_id`.
  - `callback_without_confirmation`, subject `notification_id`: loads the notification body from R2 and parses it with the existing `parseNotification` on the Paymob port. Passes when `notification.hmac_valid = 1`, the parsed event kind is `payment_succeeded`, and a `payment` for that `checkout_id` has `confirmation_inquiry_id`. A decline or a reversal callback is not this check.
  - `feed_divergence`, subject `org_id`: for clinics with a coverage event `at` in the last 24 hours, canonical JSON of `coverage_view.snapshot` equals canonical JSON of `getCoverage` `detail.snapshot`.
  - `receipt_mismatch`, subject `grant_id`: each `grant_outcome` receipt for `result` `applied` or `already_applied` equals the `listGrants` receipt for that `grant_id`, canonical JSON field for field, including `signature`, and the `listGrants` row exists. Reads `grant_outcome` joined to `grant_request`. Skips `source_kind = transfer`. Does not read `reversal_outcome`. A missing `listGrants` row fails. Void receipts and transfer receipts are outside this check.

  Leave `abo/src/worker.ts` without the `runReconciliation` call in this task. Leave both new ops routes uncreated.

**Checkpoint**: `runReconciliation` implements the eleven checks. `scheduled()` does not call it yet. E2E-P4.10-01 through E2E-P4.10-09 still fail.

### 5.4 User Story 1 - Daily reconciliation and findings (Priority: P1) — scheduled hook

**Independent Test**: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 in harness H-XW.

- [ ] T018 [US1] Call `runReconciliation` from `scheduled()` in `abo/src/worker.ts` — produces the daily entry, FR-001, FR-002, FR-014, E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-05, E2E-P4.10-07, E2E-P4.10-08, E2E-P4.10-09. Depends on T017. On cron `0 6 * * *`, call `runReconciliation` after `checkR2BucketLock` and before the existing `sendDueAlerts`, so the new AL-10 is handed to `send_email` in that same run. No second cron. Leave the ops routes uncreated.

**Checkpoint**: `runScheduled("0 6 * * *")` reaches `runReconciliation` before `sendDueAlerts`. E2E-P4.10-02 still fails on resolve. E2E-P4.10-05 and E2E-P4.10-06 still fail on import.

### 5.5 User Story 2 - Payout import and resolve-finding (Priority: P2) — ops routes

**Independent Test**: E2E-P4.10-05 and E2E-P4.10-06 in harness H-XW + H-PAY. Earlier suites stay green, and E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 still pass.

- [ ] T019 [US2] Add payout import and resolve-finding in `abo/src/ops/index.ts` — produces `POST /ops/payout-imports` and `POST /ops/findings/{findingId}/resolve` on the existing `handleOps` path, FR-001, FR-010, FR-015, FR-016, E2E-P4.10-02, E2E-P4.10-05, E2E-P4.10-06. Depends on T018. Both use the existing `opsFetch` Access session, the same class-H verification as `POST /ops/payments/{paymentId}/chargeback`. `GET /ops/payout-imports` stays the existing empty response.

  `POST /ops/payout-imports` reads the raw body. `file_sha256` is hex SHA-256 of those bytes. `r2_key` is `payouts/` plus that hex. The object is `env.R2.put(r2_key, bytes)`. `provider_id` is `paymob`. `imported_by` is the Access email. `period` is the UTC `YYYY-MM` of the first line's `settled_at`, or the clock month when the file has no lines. Lines come from `payoutLines` through `providerForId` and are inserted with `line_no` starting at 1. `payout_import`, `payout_line`, and their `fact_log` rows are written, then `operator_action` with action `Import a payout CSV` and subject `import_id`, then `recordOperatorAction`, then `runReconciliation`, then the JSON response `{ contract_version, import_id, action_id }`. The handler calls `runReconciliation` before it responds.

  `POST /ops/findings/{findingId}/resolve` takes JSON `{ "note": "<string>" }`. Unknown `finding_id` returns the existing `not_found`. A missing string `note` returns the existing `invalid_request`. One `finding_resolution` row: `resolved_by` is the Access email, `at` is the clock. A second resolve of the same `finding_id` does not insert another row. The handler writes `operator_action` with action `Resolve a finding` and subject `finding_id`, then `recordOperatorAction`. It does not clear the alert and does not run reconciliation.

**Checkpoint**: E2E-P4.10-02 resolves one `finding_resolution`. E2E-P4.10-05 and E2E-P4.10-06 import a CSV and re-run reconciliation.

---

## 6. Verification

**Purpose**: After T013 through T019, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task. Earlier suites are not part of this command (rule S2).

### 6.1 Unit harness

**Independent Test**: E2E-P4.10-05 and E2E-P4.10-06 in harness H-XW + H-PAY. Earlier suites stay green, and E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 still pass.

- [ ] T020 [US2] Run `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/reconciliation.cross-worker.test.ts` from `abo/` until E2E-P4.10-01 through E2E-P4.10-09 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, FR-015, FR-016, E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-05, E2E-P4.10-06, E2E-P4.10-07, E2E-P4.10-08, E2E-P4.10-09. Depends on T019 (and therefore on T001–T018). This task may edit only `abo/test/system/reconciliation.cross-worker.test.ts`. It does not add an E2E id and does not change `abo/src/reconciliation/run.ts` or `abo/src/ops/index.ts`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/reconciliation.cross-worker.test.ts
```

**Checkpoint**: E2E-P4.10-01 through E2E-P4.10-09 pass.

---

## 7. Documentation

**Purpose**: After the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 7.1 Quickstart

- [ ] T021 [US2] Create `specs/085-abo-p4-10-reconciliation-payout-import-findings/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, FR-015, FR-016, E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-05, E2E-P4.10-06, E2E-P4.10-07, E2E-P4.10-08, E2E-P4.10-09. Depends on T020. Sections: (1) what was implemented, and the files added or modified; (2) the harness command below; (3) the entry point → module chain per E2E id below. Manual steps: none. The harness can see every behaviour in the test plan.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/reconciliation.cross-worker.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.10-01 | `runScheduled("0 6 * * *")` → `scheduled()` → `runReconciliation`. Grants and the transfer are read through `VendorEntrypoint.listGrants` over `PLATFORM`. A clean month built through the existing payment, complimentary-grant, and transfer paths → zero `finding` rows |
| E2E-P4.10-02 | A paid grant is applied on the real platform worker with the testkit ABO key and no ABO payment. `runScheduled("0 6 * * *")` → `scheduled()` → `runReconciliation` → `listGrants`. AL-10 is `send_email`. Then `opsFetch` `POST /ops/findings/{findingId}/resolve`. Kind `grant_without_payment`. `send_email` received `AL-10`. One `finding_resolution` for that `finding_id` |
| E2E-P4.10-03 | `runScheduled("0 6 * * *")` → `runReconciliation` → `listGrants`, compared with `operator_action`. Complimentary platform grant and no ABO `operator_action` → `grant_without_operator_action`. Transfer grant with no `beginTransfer` `operator_action` and no `transferOut` `grant_request` → `transfer_without_authorisation` |
| E2E-P4.10-04 | The H-XW test clock advances more than 15 minutes, then `runScheduled("0 6 * * *")` → `runReconciliation`. Grant parked more than 15 minutes, payment `disposition` `grant`, no applied outcome → `payment_without_grant` |
| E2E-P4.10-05 | `opsFetch` `POST /ops/payout-imports` with `payout-unrecorded-chargeback.csv` → `handleOps` → `payoutLines` → `paymob_txn` → `runReconciliation`. Then `opsFetch` `POST /ops/payments/{paymentId}/chargeback`. Then `runScheduled("0 6 * * *")` → `runReconciliation`. Kind `unrecorded_reversal`. After the existing chargeback, the grant void count is 1 and the term state is `ended`. The re-run inserts no finding |
| E2E-P4.10-06 | `opsFetch` `POST /ops/payout-imports` with `payout-amount-mismatch.csv` → `payoutLines` → `runReconciliation`. Amount mismatch → `payout_unmatched`. The omitted payment → `payment_not_in_payout` |
| E2E-P4.10-07 | `runScheduled("0 6 * * *")` → `runReconciliation`. HMAC-valid success callback and no confirming inquiry → `callback_without_confirmation` |
| E2E-P4.10-08 | `runScheduled("0 6 * * *")` → `runReconciliation` compares `coverage_view` with `getCoverage` for clinics with events in the last day, and checks full reversals for a void receipt or tombstone. Tampered `coverage_view` → `feed_divergence`. Full reversal without a void receipt, effect not `none` and not `tombstone` → `reversal_not_applied` |
| E2E-P4.10-09 | `runScheduled("0 6 * * *")` → `runReconciliation` → `listGrants`. The test changes `signature` on one ABO `grant_outcome.receipt` whose `result` is `applied` or `already_applied`. The platform receipt stays as `listGrants` returns it. Kind `receipt_mismatch` and AL-10. The tampered row is not a void receipt and not a transfer receipt |

**Checkpoint**: `quickstart.md` names the files, the harness command, and the nine chains.

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (§3)**: No dependencies. The two CSV fixtures, then the vitest include. Both fixtures are sequencing step 1 and edit different files.
- **Tests (§4)**: Depend on the vitest include. The payout tests also depend on their CSV fixture. One failing test per E2E id, User Story 1 then User Story 2: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, then E2E-P4.10-08, E2E-P4.10-09, then E2E-P4.10-05, E2E-P4.10-06. All of them fail before reconciliation is implemented.
- **Implementation (§5)**: Depends on the nine failing tests. Order is the plan Sequencing: migration, `AL-10`, `PayoutLine` on the port, `payoutLines` on the Paymob adapter, `runReconciliation`, the `scheduled()` call, then both ops routes.
- **Verification (§6)**: Depends on T019. The unit harness command only.
- **Documentation (§7)**: Depends on the harness being green.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: Daily reconciliation and findings. E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09. Resolve-finding is reached inside E2E-P4.10-02 and adds no E2E id. `receipt_mismatch` is the eleventh check, decided in `escalations.md`, and is E2E-P4.10-09.
- **User Story 2 (P2)**: Payout import and resolve-finding. E2E-P4.10-05 and E2E-P4.10-06. Starts after the User Story 1 tests exist in the same file. The import route calls the same `runReconciliation`.

### 8.3 Within Each Phase

- T001 writes only `abo/test/fixtures/paymob/payout-unrecorded-chargeback.csv`.
- T002 writes only `abo/test/fixtures/paymob/payout-amount-mismatch.csv`.
- T003 writes only `abo/vitest.cross-worker.config.ts` and leaves the test file uncreated.
- T004 creates `abo/test/system/reconciliation.cross-worker.test.ts` after T003. T005 through T012 all write that same file, in that id order. T011 also depends on T001. T012 also depends on T002.
- T013 writes only `abo/migrations/0008_reconciliation.sql` after T012.
- T014 writes only `abo/src/alert/index.ts` after T013.
- T015 writes only `abo/src/provider/port.ts` after T014.
- T016 writes only `abo/src/provider/paymob/adapter.ts` after T015.
- T017 writes only `abo/src/reconciliation/run.ts` after T016.
- T018 writes only the `0 6 * * *` call in `abo/src/worker.ts` after T017.
- T019 writes only the two new routes in `abo/src/ops/index.ts` after T018.
- T020 runs after T019 and may edit only `abo/test/system/reconciliation.cross-worker.test.ts`.
- T021 writes only `specs/085-abo-p4-10-reconciliation-payout-import-findings/quickstart.md` after T020 is green.

---

## 9. Implementation Waves

### 9.1 Wave 1

- T001 [US2] — subphase: `### 3.1 User Story 2 - Payout import and resolve-finding (Priority: P2) — unrecorded-chargeback fixture` — paths: `abo/test/fixtures/paymob/payout-unrecorded-chargeback.csv`
- T002 [US2] — subphase: `### 3.2 User Story 2 - Payout import and resolve-finding (Priority: P2) — amount-mismatch fixture` — paths: `abo/test/fixtures/paymob/payout-amount-mismatch.csv`

### 9.2 Wave 2

- T003 [US1] — subphase: `### 3.3 User Story 1 - Daily reconciliation and findings (Priority: P1) — vitest include` — paths: `abo/vitest.cross-worker.config.ts`

### 9.3 Wave 3

- T004–T008 [US1] — subphase: `### 4.1 User Story 1 - Daily reconciliation and findings (Priority: P1) — tests (part 1)` — paths: `abo/test/system/reconciliation.cross-worker.test.ts`

### 9.4 Wave 4

- T009–T010 [US1] — subphase: `### 4.2 User Story 1 - Daily reconciliation and findings (Priority: P1) — tests (part 2)` — paths: `abo/test/system/reconciliation.cross-worker.test.ts`

### 9.5 Wave 5

- T011–T012 [US2] — subphase: `### 4.3 User Story 2 - Payout import and resolve-finding (Priority: P2) — tests` — paths: `abo/test/system/reconciliation.cross-worker.test.ts`

### 9.6 Wave 6

- T013–T014 [US1] — subphase: `### 5.1 User Story 1 - Daily reconciliation and findings (Priority: P1) — schema and alert` — paths: `abo/migrations/0008_reconciliation.sql`, `abo/src/alert/index.ts`

### 9.7 Wave 7

- T015–T016 [US2] — subphase: `### 5.2 User Story 2 - Payout import and resolve-finding (Priority: P2) — payout parse` — paths: `abo/src/provider/port.ts`, `abo/src/provider/paymob/adapter.ts`

### 9.8 Wave 8

- T017 [US1] — subphase: `### 5.3 User Story 1 - Daily reconciliation and findings (Priority: P1) — eleven checks` — paths: `abo/src/reconciliation/run.ts`

### 9.9 Wave 9

- T018 [US1] — subphase: `### 5.4 User Story 1 - Daily reconciliation and findings (Priority: P1) — scheduled hook` — paths: `abo/src/worker.ts`

### 9.10 Wave 10

- T019 [US2] — subphase: `### 5.5 User Story 2 - Payout import and resolve-finding (Priority: P2) — ops routes` — paths: `abo/src/ops/index.ts`

### 9.11 Wave 11

- T020 [US2] — subphase: `### 6.1 Unit harness` — paths: `abo/test/system/reconciliation.cross-worker.test.ts`

### 9.12 Wave 12

- T021 [US2] — subphase: `### 7.1 Quickstart` — paths: `specs/085-abo-p4-10-reconciliation-payout-import-findings/quickstart.md`
