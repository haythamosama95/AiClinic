# Tasks: Sweeps, reversals and the inquiry budget

**Input**: Design documents from `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.4 (subscription and payments responses; CP-C) and P3.7 (void, release, and listing methods; the tombstone rule). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`. That plan artifact is already written. It is not an implement task. `research.md` is not a task: Spikes is none, so the plan phase did not write it. `contracts/` is not a task: Freezes is none. `quickstart.md` is written in Documentation after verification.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id, written to fail before `abo/src/work/sweep.ts`, `abo/src/work/reversal.ts`, and `abo/src/work/inquiry-budget.ts` exist. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase (the `abo/` Worker already exists). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 26. Size L is 32–40 (rule S3). The count is one task per E2E id (12), one task per Files unit that is not already one of those tests and was not written in the plan phase (the Paymob stub, the vitest include, and 10 production files), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than the harness command in §5.1, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — this unit calls `VendorEntrypoint.voidForReversal`. It does not modify `ai-platform/`
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — consumed (`canonicalize`, `sha256Hex`, `signCompactJws`, `verifyCompactJws`, `humanRef`, `paymentId`, `grantIdPaid`, `ulid`, `CHANNEL_VERSIONS`) and not modified
- **Spec Kit artifacts**: `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/`
- Do not edit `abo/src/clinic-api/billing-reads.ts`, `abo/src/work/grant.ts`, `abo/wrangler.toml`, or `data-model.md`. `GET /v1/subscription` stays the P4.4 builder. Crons `* * * * *`, `0 * * * *`, `0 */6 * * *`, and `0 6 * * *` are already declared. No `TEST_CLOCK` var is added to production or staging. No second cap and no config surface.

---

## 3. Tests

**Purpose**: Sequencing step 1. The Paymob `partial_refund` script and the vitest include come first. Then one failing test per E2E id, all in `abo/test/system/sweeps.cross-worker.test.ts`. There is no thirteenth E2E id. Shared setup uses the existing H-XW helpers (`setupCrossWorkerHarness`, `billingFetch`, `mintBilling`, `scriptPaymobStub`, `setClock`, `runScheduled`, `platformCall`). Register the test ABO key on `service_key` the same way E2E-P4.4-01 does, so `voidForReversal` and the grant step can sign. No scenario sleeps more than 2 s (rule V4). Time moves with `setClock` through the consumed `clockNowMs`. Clock zero for a checkout sweep is the `opened` checkout event.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/sweeps.cross-worker.test.ts
```

### 3.1 User Story 2 - Record a refund and apply its effect (Priority: P2) — partial refund script

**Independent Test**: E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, and E2E-P4.5-11 in harnesses H-XW and H-PAY.

- [X] T001 [US2] Add inquiry script `partial_refund` in `abo/test/stubs/paymob/worker.ts` — produces the partial-refund inquiry, FR-008, E2E-P4.5-08. Depends on nothing. `partial_refund` returns `is_refunded` true and `refunded_amount_cents` `"400"` while `amount_cents` stays `"800"`. Existing `reversed`, `bound_success`, and `rate_limit` scripts stay. Do not edit `abo/vitest.cross-worker.config.ts` or `abo/test/system/sweeps.cross-worker.test.ts` in this task.

**Checkpoint**: The stub answers `partial_refund`. `abo/test/system/sweeps.cross-worker.test.ts` does not exist yet.

### 3.2 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — vitest include

**Independent Test**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 in harnesses H-XW and H-PAY.

- [X] T002 [US1] Add the sweeps test include in `abo/vitest.cross-worker.config.ts` — produces the H-XW include for this unit, FR-001, E2E-P4.5-01. Depends on nothing. Add `test/system/sweeps.cross-worker.test.ts` to `test.include`. The unit command still names only that file. Do not add `TEST_CLOCK` to `abo/wrangler.toml`. Do not edit `abo/test/stubs/paymob/worker.ts` in this task.

**Checkpoint**: The include lists `test/system/sweeps.cross-worker.test.ts`. That file does not exist yet.

### 3.3 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — tests

**Independent Test**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 in harnesses H-XW and H-PAY.

- [X] T003 [US1] Add the failing test `E2E-P4.5-01 callback blocked, +2 min sweep confirms and grants` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-001, E2E-P4.5-01. Depends on T001 and T002. Create the file and the shared setup, including the `service_key` registration from E2E-P4.4-01. Entry: `runScheduled` `* * * * *` at +2, +5, +10, and +20 minutes from the `opened` event; Paymob stub inquiry; `runDueGrantWork`. The stub delivers no `POST /notify/paymob`. The +2 inquiry confirms one payment and the grant step runs. `AL-03` once. The later three offsets still inquire and do not insert a second payment. Advance time only with `setClock`. The command fails because `abo/src/work/sweep.ts`, `abo/src/work/reversal.ts`, and `abo/src/work/inquiry-budget.ts` are absent.

- [X] T004 [US1] Add the failing test `E2E-P4.5-02 HMAC failures still confirm by sweep` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-002, E2E-P4.5-02. Depends on T003 (same file). `SELF.fetch` `POST /notify/paymob` with `bad-hmac.json`, then `runScheduled` `* * * * *`. Three bad-HMAC callbacks raise `AL-02`. The sweep still confirms the payments by inquiry. The command fails because those modules are absent.

- [X] T005 [US1] Add the failing test `E2E-P4.5-03 expiry then day-3 payment is paid_late` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-003, E2E-P4.5-03. Depends on T004 (same file). `runScheduled` `* * * * *` at `expires_at`, then at `expires_at` + 3 days; stub inquiry; grant step. The unpaid final inquiry sets `expired` and `GET /v1/checkouts/{id}` shows `Abandoned`. The day-3 inquiry sets `paid_late`, classification `late`, grants from the checkout snapshot, shows `Paid` before the grant applies, and raises `AL-08` once. Use `setClock`. The command fails because those modules are absent.

- [X] T006 [US1] Add the failing test `E2E-P4.5-12 crash after callback is inquired within 2–20 minutes` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-012, E2E-P4.5-12. Depends on T005 (same file). `SELF.fetch` `POST /notify/paymob` that answers 5xx or leaves the `confirm` row `open`; `runScheduled` `* * * * *` with the clock between +2 and +20 minutes from `opened`. The sweep inquires in that window and can confirm the payment. The command fails because those modules are absent.

**Checkpoint**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 exist and fail.

### 3.4 User Story 2 - Record a refund and apply its effect (Priority: P2) — tests (part 1)

**Independent Test**: E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, and E2E-P4.5-11 in harnesses H-XW and H-PAY.

- [X] T007 [US2] Add the failing test `E2E-P4.5-04 parent-flag refund ends the active term and holds the queue` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-004, E2E-P4.5-04. Depends on T006 (same file). `SELF.fetch` `POST /notify/paymob` with `refund-parent.json` on the payment that funds the active term, a queued term behind it; `runScheduled` `* * * * *` for the `reverse` row; `PLATFORM.voidForReversal`; `GET /v1/subscription`. One reversal, no new payment, effect `end_current`, term ended, queued term held, `AL-06` once, notice `terms_held`. The command fails because those modules are absent.

- [X] T008 [US2] Add the failing test `E2E-P4.5-05 child refund is the same reversal` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-005, E2E-P4.5-05. Depends on T007 (same file). `SELF.fetch` `POST /notify/paymob` with `refund-child.json` after the parent-flag reversal of the same payment. Same effect as FR-004. The dedupe key leaves a single `reversal` row. The command fails because those modules are absent.

- [X] T009 [US2] Add the failing test `E2E-P4.5-06 ended term reversal is effect none` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-006, E2E-P4.5-06. Depends on T008 (same file). `SELF.fetch` `POST /notify/paymob` refund fixture for a payment whose term is `ended`; `runScheduled` `* * * * *`. Effect `none`. The reversal is recorded, `AL-06` fires once, `voidForReversal` is not called, and the term stays `ended`. The command fails because those modules are absent.

- [X] T010 [US2] Add the failing test `E2E-P4.5-07 full reversal while granting stores a tombstone` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-007, E2E-P4.5-07. Depends on T009 (same file). `SELF.fetch` `POST /notify/paymob` full-refund fixture while the `grant` row is `open` or `parked`; `voidForReversal`; later `runDueGrantWork`. Effect `tombstone`. The platform stores the void before the grant. The later grant is `rejected` with `voided`. That grant work row becomes `done`. The command fails because those modules are absent.

- [X] T011 [US2] Add the failing test `E2E-P4.5-08 partial refund stays in review` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-008, E2E-P4.5-08. Depends on T010 (same file) and T001. `SELF.fetch` `POST /notify/paymob` partial-refund fixture; stub inquiry `partial_refund`; `runScheduled` `* * * * *`. Effect `review_partial`. No `reverse` row, no `voidForReversal`, `AL-06` once. The command fails because those modules are absent.

**Checkpoint**: E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, and E2E-P4.5-08 exist and fail.

### 3.5 User Story 2 - Record a refund and apply its effect (Priority: P2) — tests (part 2)

**Independent Test**: E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, and E2E-P4.5-11 in harnesses H-XW and H-PAY.

- [X] T012 [US2] Add the failing test `E2E-P4.5-11 inquiry that contradicts a refund dismisses it` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-011, E2E-P4.5-11. Depends on T011 (same file). `SELF.fetch` `POST /notify/paymob` refund fixture, then `runScheduled` with the stub on `bound_success` so the inquiry is not a refund. A `finding` with `kind` `inquiry_disagrees` exists for that `reversal_id`. No `voidForReversal`. The command fails because those modules are absent.

**Checkpoint**: E2E-P4.5-11 exists and fails. E2E-P4.5-04 through E2E-P4.5-08 still fail.

### 3.6 User Story 3 - Find a lost refund by tiered inquiry (Priority: P3) — tests

**Independent Test**: E2E-P4.5-09 in harnesses H-XW and H-PAY.

- [X] T013 [US3] Add the failing test `E2E-P4.5-09 hourly, 6-hour, and daily tiers find a lost refund` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-009, E2E-P4.5-09. Depends on T012 (same file). `runScheduled` `0 * * * *` for a 3-day-old payment, `0 */6 * * *` for a payment funding an active term, and `0 6 * * *` for a 100-day-old payment whose `payment_id` slot is today's UTC epoch-day modulo 7; then the minute cron at that daily row's `next_attempt_at`. Stub inquiry `reversed`. Each tier records one reversal with `detected_via` `inquiry` and does not record a payment. Search a parent transaction id until `paymentId("paymob", txnId)` is in today's slot, then age that payment 100 days on the test clock. The daily test advances the clock to the stored due minute. The command fails because those modules are absent.

**Checkpoint**: E2E-P4.5-09 exists and fails.

### 3.7 User Story 4 - Serve confirm and grant inquiries before the rest of the budget (Priority: P4) — tests

**Independent Test**: E2E-P4.5-10 in harnesses H-XW and H-PAY. Earlier suites stay green, and E2E-P4.5-01 through E2E-P4.5-09, E2E-P4.5-11, and E2E-P4.5-12 still pass.

- [X] T014 [US4] Add the failing test `E2E-P4.5-10 confirm and grant take the inquiry budget first` in `abo/test/system/sweeps.cross-worker.test.ts` — red test, FR-010, E2E-P4.5-10. Depends on T013 (same file). `runScheduled` `* * * * *` with more than 2 due provider inquiries, including one due `confirm` row and one due `grant` row. Those two rows are served. The extra sweep row stays `open` and due. `inquiry_spend.spent` for that minute is 2. The command fails because those modules are absent.

**Checkpoint**: E2E-P4.5-10 exists and fails. E2E-P4.5-01 through E2E-P4.5-09, E2E-P4.5-11, and E2E-P4.5-12 still fail.

---

## 4. Implementation

**Purpose**: Sequencing steps 2 and 3. Each step starts after T003–T014 exist and those E2E tests fail. Within a subphase the tasks run in id order. `abo/src/clinic-api/billing-reads.ts` and `ai-platform/` stay unchanged. This unit calls `voidForReversal` and `runDueGrantWork`. It does not change those methods or the grant envelope.

### 4.1 User Story 2 - Record a refund and apply its effect (Priority: P2) — migration

**Independent Test**: E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, and E2E-P4.5-11 in harnesses H-XW and H-PAY.

- [ ] T015 [US2] Add `abo/migrations/0005_reversal.sql` — produces reversal columns, `reversal_outcome`, `finding`, and `inquiry_spend`, FR-004, FR-007, FR-011, FR-013, FR-014, E2E-P4.5-04. Depends on T014. Tables, columns, and constraints are those already written in `data-model.md`. `reversal` and `reversal_outcome` are append-only. Do not rewrite `data-model.md`. Do not edit `abo/src/alert/index.ts` in this task. The harness applies this file before the sweeps tests.

### 4.2 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — alerts

**Independent Test**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 in harnesses H-XW and H-PAY.

- [ ] T016 [US1] Extend alert codes in `abo/src/alert/index.ts` — produces AL-03, AL-06, and AL-08, FR-001, FR-003, FR-004, FR-006, FR-008, FR-013, E2E-P4.5-01, E2E-P4.5-03, E2E-P4.5-04. Depends on T014. Extend `AlertCode` with `AL-03`, `AL-06`, and `AL-08`. `nextSendAtForCode` returns null for those three, the same send-once path as `AL-05` and `AL-09`. Email text stays `{code} {detail_id}`. Do not edit `abo/migrations/0005_reversal.sql` in this task.

### 4.3 User Story 2 - Record a refund and apply its effect (Priority: P2) — reversal recorder and parent rewrite

**Independent Test**: E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, and E2E-P4.5-11 in harnesses H-XW and H-PAY.

- [ ] T017 [US2] Add `abo/src/work/reversal.ts` — produces reversal facts, effects, and signed `voidForReversal`, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-011, FR-013, FR-014, E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, E2E-P4.5-11. Depends on T015 and T016. Do not edit `abo/src/provider/paymob/adapter.ts`, `abo/src/notify/intake.ts`, `abo/src/alert/index.ts`, `abo/src/worker.ts`, or `abo/src/work/runner.ts` in this task.

  A child notification is rewritten onto the parent before the key is formed. The parent transaction reference is `paymob_txn.txn_id` for that order where `parent_txn_id` is null, or `parent_transaction.id` on the inquiry when the callback has `has_parent_transaction` and that row is missing. `payment_id` is `paymentId("paymob", parentRef)`. The callback's own id is never the payment id when it is a child. The dedupe key is `paymob:{parentRef}:reversal:{cumulative_reversed_minor}`. The cumulative is the inquiry's `refunded_amount_cents` (or the full amount when the inquiry shows a void). `reversal_id` is the hex SHA-256 of `reversal:` ‖ that key. `reference` is `humanRef("REV", reversal_id)`. A second insert with the same `dedupe_key` does not write a row and does not raise `AL-06` again. `source` `vendor` is rejected and writes nothing. This unit writes `source` `provider`, `kind` `refund`, `recorded_by` `abo`, and `detected_via` `notification` or `inquiry`. `is_full` is true when `cumulative_reversed_minor` is at least the payment's `amount_minor`.

  Effect, from the grant lineage, using `grantIdPaid(payment_id)` and `getCoverage` (`recent_terms` matched on `grant_outcome.term_ids`): `is_full` false → `review_partial` (no `reverse` row, no `voidForReversal`, `AL-06` once); no `grant_outcome` of `applied` or `already_applied` → `tombstone`; matching `recent_terms` state `active` or `grace` → `end_current`; matching `recent_terms` state `ended` → `none` (no `voidForReversal`, `AL-06` once); applied grant whose term id is not in `recent_terms` → `remove_queued`. `tombstone`, `end_current`, and `remove_queued` insert one `reverse` row, `dedupe_key` `reverse:{reversal_id}`, only after an inquiry agrees. Agree means the inquiry shows a reversal for that parent whose cumulative is at least the recorded cumulative. Disagree means it does not: insert one `finding` (`kind` `inquiry_disagrees`, `subject` the `reversal_id`) and do not insert `reverse`. The reversal row stays. No void.

  The `reverse` row calls `PLATFORM.voidForReversal` with `contract_version` `CHANNEL_VERSIONS.vendorEntrypoint`, `grant_id` `grantIdPaid(payment_id)`, `reversal_id`, `reason` the effect name, `evidence_sha256`, `partial` false, `abo_kid`, and `abo_signature`. The signature is `signCompactJws` over `canonicalize` of `{contract_version, grant_id, reversal_id, reason, evidence_sha256, partial}`, using `ABO_GRANT_KEY`. `applied` or `already_applied` with a receipt that verifies against `PLATFORM_PUBLIC_KEYS` inserts `reversal_outcome` and sets the work row `done`. A receipt that does not verify parks the row. `transient` or a thrown call leaves the row `open` with the confirm backoff (0 when `TEST_CLOCK` is `"1"`). `conflict` or `rejected` parks the row. This unit does not retry a parked row. A sweep or tier inquiry that finds a refund on an existing payment uses this recorder with `detected_via` `inquiry` and does not insert a payment. `AL-06` once uses key `AL-06:{reversal_id}` on insert only.

- [ ] T018 [US2] Rewrite a child callback onto the parent in `abo/src/provider/paymob/adapter.ts` — produces `provider_parent_txn_id` and the parent `payment_id`, FR-005, FR-013, E2E-P4.5-05. Depends on T017. `has_parent_transaction` sets `provider_parent_txn_id` and computes `payment_id` from the parent reference in T017. The port interface is unchanged. Do not edit `abo/src/work/reversal.ts` in this task.

### 4.4 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — checkout sweeps

**Independent Test**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 in harnesses H-XW and H-PAY.

- [ ] T019 [US1] Add `abo/src/work/sweep.ts` — produces checkout sweeps and the reversal-inquiry populations, FR-001, FR-002, FR-003, FR-009, FR-012, E2E-P4.5-01, E2E-P4.5-03, E2E-P4.5-09, E2E-P4.5-12. Depends on T016 and T017. Do not edit `abo/src/worker.ts`, `abo/src/work/inquiry-budget.ts`, or `abo/src/work/runner.ts` in this task.

  Schedule checkout inquiries from the `opened` checkout event's `at`: +2, +5, +10, and +20 minutes; then every 10 minutes while the due time is strictly before `expires_at`; one final inquiry at `expires_at`. Each due offset is one `sweep_checkout` row, `dedupe_key` `sweep_checkout:{checkout_id}:{offset_ms}`, `subject_id` the checkout, `next_attempt_at` that instant. A bound unpaid final inquiry sets `checkout_status.state` to `expired`. After `expired` or `cancelled`, three further rows are due at `expires_at` plus 1 day, 3 days, and 7 days. No sweep inquiry is scheduled after 7 days. A sweep confirmation with no `notification` row of `hmac_valid` 1 for that checkout raises `AL-03` once with key `AL-03:{payment_id}`. The +2, +5, +10, and +20 rows still run after the payment exists; a second success does not insert a second payment. A payment confirmed while the checkout is `expired` or `cancelled` raises `AL-08` once with key `AL-08:{checkout_id}`. The paid_late write itself is T023.

  Export the schedulers the crons call: hourly population (payment `confirmed_at` within 7 days, or `grantIdPaid` has no `applied` / `already_applied` outcome); 6-hour population (term active, grace, queued, or held); daily population at 06:00 UTC (paid, older than the hourly and 6-hour populations, at most 180 days old, whose slot equals the UTC epoch-day modulo 7). Slot is `BigInt("0x" + payment_id) % 7n`. The due minute is that same integer modulo 1440, added to 06:00 UTC, stored on `next_attempt_at`. A found refund uses the T017 recorder with `detected_via` `inquiry`.

### 4.5 User Story 4 - Serve confirm and grant inquiries before the rest of the budget (Priority: P4) — inquiry budget

**Independent Test**: E2E-P4.5-10 in harnesses H-XW and H-PAY. Earlier suites stay green, and E2E-P4.5-01 through E2E-P4.5-09, E2E-P4.5-11, and E2E-P4.5-12 still pass.

- [ ] T020 [US4] Add `abo/src/work/inquiry-budget.ts` — produces the shared cap of 2, FR-010, E2E-P4.5-10. Depends on T019. Do not edit `abo/src/worker.ts` or `abo/src/notify/intake.ts` in this task. Export the minute coordinator those two call.

  One UTC minute, taken from the ABO clock as `YYYY-MM-DDTHH:MM`, has a row in `inquiry_spend`. `spent` starts at 0. The cap is 2. A confirm row that reaches `inquire`, a grant row that is run, and a sweep row that reaches `inquire` each take one slot. Order while `spent` < 2: (1) due `open` `confirm` rows, oldest `next_attempt_at` first, each `inquire` consumes one slot; (2) due `open` `grant` rows, same order, and running a grant row consumes one slot via `runDueGrantWork` for that row only; (3) due `open` `sweep_checkout` and `sweep_payment` rows, same order, each `inquire` consumes one slot. `reverse` rows are not inquiry slots. After the inquiry pass, the same minute run takes due `open` `reverse` rows, still at most 50 due work rows in the whole run, and skips them when `signing_key_gate.paused` is 1. They stay `open`. A row that does not get a slot keeps `state` `open` and its `next_attempt_at`. It is not deleted and not marked `done`.

### 4.6 User Story 2 - Record a refund and apply its effect (Priority: P2) — notify intake

**Independent Test**: E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, and E2E-P4.5-11 in harnesses H-XW and H-PAY.

- [ ] T021 [US2] Record refund callbacks in `abo/src/notify/intake.ts` — produces the refund path through the reversal recorder and the budget coordinator, FR-004, FR-005, FR-011, E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-11. Depends on T017 and T020. An authentic refund callback stores the notification and calls the reversal recorder. It does not insert a payment. The inline `waitUntil` still runs the confirm path for a payment callback, then `runDueGrantWork`, and both inquiry calls go through the budget coordinator. HMAC failure behavior is unchanged. Do not edit `abo/src/worker.ts` or `abo/src/work/inquiry-budget.ts` in this task.

### 4.7 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — cron dispatch

**Independent Test**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 in harnesses H-XW and H-PAY.

- [ ] T022 [US1] Point the crons at sweeps and the inquiry budget in `abo/src/worker.ts` — produces the live `scheduled` chains, FR-001, FR-003, FR-004, FR-009, FR-010, FR-012, E2E-P4.5-01, E2E-P4.5-09, E2E-P4.5-10, E2E-P4.5-12. Depends on T019, T020, and T021. `Env.PLATFORM` also types `voidForReversal`. The minute cron calls the budget coordinator instead of calling `runDueConfirmWork` and `runDueGrantWork` unbounded. Cron `0 * * * *` still runs `refreshSigningKeyCheck`, then enqueues the hourly reversal population from T019. Cron `0 */6 * * *` enqueues the 6-hour population from T019. Cron `0 6 * * *` still runs the R2 lock check and due alerts, and enqueues the daily population from T019. Do not edit `abo/src/work/sweep.ts`, `abo/src/work/inquiry-budget.ts`, `abo/src/work/runner.ts`, or `abo/src/notify/intake.ts` in this task.

### 4.8 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — paid_late and tombstone on confirm

**Independent Test**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 in harnesses H-XW and H-PAY.

- [ ] T023 [US1] Write `paid_late` and the pre-apply tombstone in `abo/src/work/runner.ts` — produces sweep success on an expired checkout and the reversal-before-grant edge, FR-001, FR-003, FR-007, E2E-P4.5-03, E2E-P4.5-07. Depends on T017 and T022. A sweep success for an `expired` or `cancelled` checkout writes classification `late`, disposition `grant`, checkout state `paid_late`, and the `grant` work row `grant:{payment_id}`. An open checkout still writes `paid` and classification `normal` unless the existing duplicate rule applies. The existing first-inquiry `reversed_before_grant` branch still inserts no `grant` row. It also calls the reversal recorder so a full reversal before apply takes the tombstone edge. The pre-payment partial retry (`partial_reversal`) stays as it is. Do not edit `abo/src/clinic-api/checkouts.ts` or `abo/src/work/sweep.ts` in this task.

### 4.9 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — checkout shown state

**Independent Test**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 in harnesses H-XW and H-PAY.

- [ ] T024 [US1] Show Abandoned and Paid from checkout state in `abo/src/clinic-api/checkouts.ts` — produces `shown_state` for expiry and late payment, FR-003, E2E-P4.5-03. Depends on T014. `expired` and `cancelled` with no payment show `Abandoned`. `paid` and `paid_late` show `Paid` while that checkout's grant outcome is not `applied` or `already_applied`, and `Active` when it is. `open` stays `Waiting`. `open_failed` stays `Abandoned`. Do not edit `abo/src/work/runner.ts` in this task.

---

## 5. Verification

**Purpose**: Sequencing step 4, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task. Earlier suites are not part of this command.

### 5.1 Unit harness

**Independent Test**: E2E-P4.5-10 in harnesses H-XW and H-PAY. Earlier suites stay green, and E2E-P4.5-01 through E2E-P4.5-09, E2E-P4.5-11, and E2E-P4.5-12 still pass.

- [ ] T025 [US4] Run `node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/sweeps.cross-worker.test.ts` from `abo/` until E2E-P4.5-01 through E2E-P4.5-12 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, E2E-P4.5-09, E2E-P4.5-10, E2E-P4.5-11, E2E-P4.5-12. Depends on T018, T021, T023, and T024 (and therefore on T001–T017, T019, T020, and T022). This task may edit only files under `abo/test/`.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/sweeps.cross-worker.test.ts
```

**Checkpoint**: E2E-P4.5-01 through E2E-P4.5-12 pass.

---

## 6. Documentation

**Purpose**: After the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 6.1 Quickstart

- [ ] T026 Create `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, E2E-P4.5-09, E2E-P4.5-10, E2E-P4.5-11, E2E-P4.5-12. Depends on T025. Sections: (1) what was implemented, and the files added or modified; (2) the harness command below; (3) the entry point → module chain per E2E id below. No earlier-unit files, combined counts, or full-suite commands. No manual steps; the harness observes every scenario.

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/sweeps.cross-worker.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.5-01 | `worker.ts` `scheduled` → `work/inquiry-budget.ts` → `work/sweep.ts` → `work/runner.ts` → `work/grant.ts` `runDueGrantWork` → `alert/index.ts` |
| E2E-P4.5-02 | `worker.ts` `fetch` → `notify/intake.ts` → `alert/index.ts`; then `work/sweep.ts` |
| E2E-P4.5-03 | `work/sweep.ts` → `checkout_status` `expired` → `clinic-api/checkouts.ts`; later `paid_late` → `work/grant.ts` |
| E2E-P4.5-04 | `notify/intake.ts` → `provider/paymob/adapter.ts` → `work/reversal.ts` → `PLATFORM.voidForReversal` → `clinic-api/billing-reads.ts` |
| E2E-P4.5-05 | `notify/intake.ts` → `adapter.ts` parent rewrite → `work/reversal.ts` dedupe key |
| E2E-P4.5-06 | `work/reversal.ts` effect `none` |
| E2E-P4.5-07 | `work/reversal.ts` → `PLATFORM.voidForReversal` tombstone → `work/grant.ts` `rejected` `voided` |
| E2E-P4.5-08 | `work/reversal.ts` effect `review_partial` → `alert/index.ts` |
| E2E-P4.5-09 | `worker.ts` `scheduled` hourly, 6-hour, and `0 6 * * *` → `work/sweep.ts` → `work/inquiry-budget.ts` → `work/reversal.ts` |
| E2E-P4.5-10 | `work/inquiry-budget.ts` serves `confirm` and `grant` first |
| E2E-P4.5-11 | `notify/intake.ts` → `work/reversal.ts` → `finding` |
| E2E-P4.5-12 | `notify/intake.ts` 5xx or open `confirm` row → `work/sweep.ts` inside 2–20 minutes |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: T001 writes `abo/test/stubs/paymob/worker.ts`. T002 writes `abo/vitest.cross-worker.config.ts`. Both finish before T003 creates `abo/test/system/sweeps.cross-worker.test.ts`. T003 through T014 stay in id order in that file.
- **Implementation (Phase 4)**: Starts after T014, with E2E-P4.5-01 through E2E-P4.5-12 failing. The migration and the alert codes both follow those failing tests and both finish before the reversal recorder. The adapter follows the recorder. Sweep scheduling follows the recorder and the alert codes. The inquiry budget follows sweep scheduling. Refund intake follows the recorder and the budget coordinator. Cron dispatch follows sweep scheduling, the budget coordinator, and intake. `paid_late` / tombstone on the runner follows cron dispatch and the recorder. Checkout shown state follows the failing tests.
- **Verification (Phase 5)**: Depends on T018, T021, T023, and T024. Runs only the command in §5.1.
- **Documentation (Phase 6)**: Depends on T025 being green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: Tests T003, T004, T005, and T006, after the vitest include. Implementation T016, T019, T022, T023, and T024. E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12.
- **User Story 2 (P2)**: The `partial_refund` script is T001, before the tests. Tests T007 through T012 after T006, in that id order, in the same sweeps file. Implementation T015, T017, T018, and T021. E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, and E2E-P4.5-11.
- **User Story 3 (P3)**: Test T013 after T012. The hourly, 6-hour, and daily populations are T019, and the crons that enqueue them are T022. E2E-P4.5-09.
- **User Story 4 (P4)**: Test T014 after T013. The cap of 2 is T020. Intake and the minute cron call that coordinator from T021 and T022. E2E-P4.5-10, with E2E-P4.5-01 through E2E-P4.5-09, E2E-P4.5-11, and E2E-P4.5-12 still passing once T025 is green.

### 7.3 Within Each Phase

- T001 writes only `abo/test/stubs/paymob/worker.ts`. T002 writes only `abo/vitest.cross-worker.config.ts`. T003 creates `abo/test/system/sweeps.cross-worker.test.ts` after both.
- T003 through T014 all write `abo/test/system/sweeps.cross-worker.test.ts`, in that id order.
- T015 writes `abo/migrations/0005_reversal.sql`. T016 writes only `abo/src/alert/index.ts`. Both follow T014. T017 writes `abo/src/work/reversal.ts` after T015 and T016, and does not write `abo/src/provider/paymob/adapter.ts`. T018 writes `abo/src/provider/paymob/adapter.ts` after T017.
- T019 writes `abo/src/work/sweep.ts` after T016 and T017, and does not write `abo/src/worker.ts`. T020 writes `abo/src/work/inquiry-budget.ts` after T019, and does not write `abo/src/notify/intake.ts`. T021 writes `abo/src/notify/intake.ts` after T017 and T020, and does not write `abo/src/worker.ts`.
- T022 writes `abo/src/worker.ts` after T019, T020, and T021, and does not write `abo/src/work/runner.ts`. T023 writes `abo/src/work/runner.ts` after T017 and T022, and does not write `abo/src/clinic-api/checkouts.ts`. T024 writes `abo/src/clinic-api/checkouts.ts` after T014, and does not write `abo/src/work/runner.ts`.
- T025 runs after T018, T021, T023, and T024 and may edit only `abo/test/`.
- T026 writes only `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/quickstart.md` after T025 is green.

---

## 8. Implementation Waves

### 8.1 Wave 1

- T001 [US2] — subphase: `### 3.1 User Story 2 - Record a refund and apply its effect (Priority: P2) — partial refund script` — paths: `abo/test/stubs/paymob/worker.ts`
- T002 [US1] — subphase: `### 3.2 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — vitest include` — paths: `abo/vitest.cross-worker.config.ts`

### 8.2 Wave 2

- T003–T006 [US1] — subphase: `### 3.3 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — tests` — paths: `abo/test/system/sweeps.cross-worker.test.ts`

### 8.3 Wave 3

- T007–T011 [US2] — subphase: `### 3.4 User Story 2 - Record a refund and apply its effect (Priority: P2) — tests (part 1)` — paths: `abo/test/system/sweeps.cross-worker.test.ts`

### 8.4 Wave 4

- T012 [US2] — subphase: `### 3.5 User Story 2 - Record a refund and apply its effect (Priority: P2) — tests (part 2)` — paths: `abo/test/system/sweeps.cross-worker.test.ts`

### 8.5 Wave 5

- T013 [US3] — subphase: `### 3.6 User Story 3 - Find a lost refund by tiered inquiry (Priority: P3) — tests` — paths: `abo/test/system/sweeps.cross-worker.test.ts`

### 8.6 Wave 6

- T014 [US4] — subphase: `### 3.7 User Story 4 - Serve confirm and grant inquiries before the rest of the budget (Priority: P4) — tests` — paths: `abo/test/system/sweeps.cross-worker.test.ts`

### 8.7 Wave 7

- T015 [US2] — subphase: `### 4.1 User Story 2 - Record a refund and apply its effect (Priority: P2) — migration` — paths: `abo/migrations/0005_reversal.sql`
- T016 [US1] — subphase: `### 4.2 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — alerts` — paths: `abo/src/alert/index.ts`

### 8.8 Wave 8

- T017–T018 [US2] — subphase: `### 4.3 User Story 2 - Record a refund and apply its effect (Priority: P2) — reversal recorder and parent rewrite` — paths: `abo/src/work/reversal.ts`, `abo/src/provider/paymob/adapter.ts`

### 8.9 Wave 9

- T019 [US1] — subphase: `### 4.4 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — checkout sweeps` — paths: `abo/src/work/sweep.ts`

### 8.10 Wave 10

- T020 [US4] — subphase: `### 4.5 User Story 4 - Serve confirm and grant inquiries before the rest of the budget (Priority: P4) — inquiry budget` — paths: `abo/src/work/inquiry-budget.ts`

### 8.11 Wave 11

- T021 [US2] — subphase: `### 4.6 User Story 2 - Record a refund and apply its effect (Priority: P2) — notify intake` — paths: `abo/src/notify/intake.ts`

### 8.12 Wave 12

- T022 [US1] — subphase: `### 4.7 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — cron dispatch` — paths: `abo/src/worker.ts`

### 8.13 Wave 13

- T023 [US1] — subphase: `### 4.8 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — paid_late and tombstone on confirm` — paths: `abo/src/work/runner.ts`
- T024 [US1] — subphase: `### 4.9 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1) — checkout shown state` — paths: `abo/src/clinic-api/checkouts.ts`

### 8.14 Wave 14

- T025 [US4] — subphase: `### 5.1 Unit harness` — paths: `abo/test/`

### 8.15 Wave 15

- T026 — subphase: `### 6.1 Quickstart` — paths: `specs/080-abo-p4-5-sweeps-reversals-inquiry-budget/quickstart.md`
