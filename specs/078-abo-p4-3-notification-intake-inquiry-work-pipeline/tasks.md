# Tasks: Notification intake, inquiry, work pipeline and payment confirmation

**Input**: Design documents from `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P4.2 (checkout API, provider port, H-PAY intention stub, H-XW). Plan artifacts from `AVAILABLE_DOCS`: `research.md`, `data-model.md`. Those two plan artifacts are already written. They are not implement tasks. `research.md` already records the R-2 outcome (no live Paymob account; inquiry sweeps stay with P4.5). `quickstart.md` is written in Documentation after verification. No `contracts/` directory.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id, written to fail before the notify routes, the Paymob parse/inquire adapter, and the work runner exist. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase (the `abo/` Worker already exists). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 27. Size L is 32–40 (rule S3). The count is one task per E2E id (12), one task per Files unit that is not already one of those tests and was not written in the plan phase (4 harness files + 9 production files), the unit harness (1), and `quickstart.md` (1). It is not padded. A repository-root `npm test`, and any command other than `npx vitest run --config vitest.workers.config.ts test/system/notify.system.test.ts` from `abo/`, are not tasks.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — this unit does not change it
- **ABO**: `abo/` — the Files paths in `plan.md`
- **Shared package**: `packages/vendor-contracts/` — consumed (`ulid`, `humanRef`, `sha256Hex`, `canonicalize`) and not modified
- **Spec Kit artifacts**: `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/`
- Do not edit `abo/src/clinic-api/checkouts.ts`, `abo/src/provider/registry.ts`, `abo/src/clock.ts`, `abo/src/records/append.ts`, `abo/test/system/cross-worker-harness.ts`, or `abo/vitest.cross-worker.config.ts`. `createPaymobIntention` in `abo/src/provider/paymob/client.ts` stays. Platform and `vendor-contracts` sources stay as they are. Production routes have no fault flag. No `TEST_CLOCK` var is added to production or staging.

---

## 3. Tests

**Purpose**: Sequencing step 1, then step 2. Harness files the red tests use come first. Then one failing test per E2E id, all in `abo/test/system/notify.system.test.ts`. HTTP 413 and HTTP 429 are assertions inside E2E-P4.3-01 and E2E-P4.3-02. There is no thirteenth E2E id. Checkout and `paymob_intention` rows are seeded in D1 by the test. The entry point is the notify or return route. Column lists this file does not spell out are those in `data-model.md`. No scenario sleeps more than 2 s (rule V4). Time moves with `setClock` through the consumed `clockNowMs`.

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system/notify.system.test.ts
```

### 3.1 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — H-PAY stub, fixtures, and harness

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T001 [US1] Extend the H-PAY stub in `abo/test/stubs/paymob/worker.ts` — produces inquiry routes and the inquiry script on the existing worker and the same base URL, FR-013, E2E-P4.3-01. Depends on nothing. Intention routes and `mode` `ok` / `refuse` / `timeout` stay. Add `POST /api/auth/tokens`, `POST /api/ecommerce/orders/transaction_inquiry`, and `GET /api/acceptance/transactions/{id}`. A test sets the inquiry script before confirm. Scripts: `bound_success`, `unbound`, `amount_mismatch`, `reversed`, `pending`, `timeout`, `rate_limit`.

- [ ] T002 [US1] Add recorded callback fixtures under `abo/test/fixtures/paymob/` — produces the HMAC replay bodies, FR-003, FR-004, FR-013, E2E-P4.3-01, E2E-P4.3-03, E2E-P4.3-04, E2E-P4.3-06. Depends on nothing. Create `abo/test/fixtures/paymob/success.json`, `abo/test/fixtures/paymob/decline.json`, `abo/test/fixtures/paymob/refund-parent.json`, `abo/test/fixtures/paymob/refund-child.json`, and `abo/test/fixtures/paymob/bad-hmac.json`. No real card data. Tests re-sign them with the local HMAC secret. The 20 HMAC fields are those in `data-model.md` §7.

- [ ] T003 [US1] Add intake fault and inquiry-script helpers in `abo/test/system/harness.ts` — produces the H-ABO fault injection, FR-009, FR-010, FR-013, E2E-P4.3-09, E2E-P4.3-10. Depends on nothing. `setIntakeR2PutThrows` wraps `env.R2.put` so the next intake put throws. `setD1BatchThrows` wraps `env.DB.batch` so the next batch throws. `scriptPaymobInquiry` POSTs the inquiry script to the stub. Leave the existing helpers, including `setClock`. The production worker does not read these helpers.

- [ ] T004 [US1] Bind `PAYMOB_STUB` in `abo/vitest.workers.config.ts` — produces the H-PAY auxiliary binding, FR-013, E2E-P4.3-01. Depends on T001. Bind `abo/test/stubs/paymob/worker.ts` as `PAYMOB_STUB`, with `PAYMOB_BASE_URL` `https://paymob.harness.test` and the test Paymob vars (`PAYMOB_HMAC_SECRET`, `PAYMOB_API_KEY`). Keep the `test/system/**/*.system.test.ts` include. `TEST_CLOCK` stays the existing test-only binding.

**Checkpoint**: The stub, the five fixtures, the harness helpers, and the `PAYMOB_STUB` binding exist. `abo/test/system/notify.system.test.ts` does not exist yet.

### 3.2 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — tests

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T005 [US1] Add the failing test `E2E-P4.3-01 replayed success callback opens a PAY payment and a grant row` in `abo/test/system/notify.system.test.ts` — red test, FR-001, E2E-P4.3-01. Depends on T002, T003, and T004. `SELF.fetch` `POST /notify/paymob` on the ABO worker `fetch`, billing hostname. Re-sign `success.json` with the local HMAC secret. Script inquiry `bound_success`. Inline `waitUntil` runs confirm. The notification is stored, the payment reference is `PAY-…`, the checkout event is `paid`, and a `grant` work row is `open`. Also: a body of 1_048_577 bytes answers HTTP 413 with an empty body, and nothing is stored or enqueued. Advance time only with `setClock`. The command fails because that route is not this result.

- [ ] T006 [US1] Add the failing test `E2E-P4.3-04 decline then success is one payment` in `abo/test/system/notify.system.test.ts` — red test, FR-004, E2E-P4.3-04. Depends on T005 (same file). Re-sign `decline.json`, then a success callback, for the same open checkout. Inline `waitUntil` runs confirm. The decline is checkout event `attempt_declined` and the checkout stays `open`. The later success is one payment. The command fails because the decline is not `attempt_declined`.

**Checkpoint**: E2E-P4.3-01 and E2E-P4.3-04 exist and fail.

### 3.3 User Story 2 - Store only authentic callbacks (Priority: P2) — tests

**Independent Test**: E2E-P4.3-02, E2E-P4.3-03, and E2E-P4.3-09 in harnesses H-ABO and H-PAY.

- [ ] T007 [US2] Add the failing test `E2E-P4.3-02 same body is duplicate and the 61st request is 429` in `abo/test/system/notify.system.test.ts` — red test, FR-002, E2E-P4.3-02. Depends on T006 (same file). `SELF.fetch` `POST /notify/paymob` on the billing hostname. Posting the same body again sets notification disposition `duplicate` and leaves one payment. Also: the 61st request in the same 60-second window from one `CF-Connecting-IP` answers HTTP 429 with an empty body, and nothing is stored or enqueued. A missing `CF-Connecting-IP` uses the key `unknown`. Use `setClock` for the window. Do not sleep. The command fails because the second body is not `duplicate`.

- [ ] T008 [US2] Add the failing test `E2E-P4.3-03 bad HMAC stores no evidence and raises AL-02` in `abo/test/system/notify.system.test.ts` — red test, FR-003, E2E-P4.3-03. Depends on T007 (same file). Post `bad-hmac.json`. Nothing is stored under `evidence/`. Three failures within 15 minutes raise AL-02 and keep a sample object under `hmac-invalid/`. An 11th failure in the same hour does not store another raw body. Use `setClock`. The command fails because evidence is stored or AL-02 does not fire.

- [ ] T009 [US2] Add the failing test `E2E-P4.3-09 R2 and D1 intake failures enqueue nothing` in `abo/test/system/notify.system.test.ts` — red test, FR-009, E2E-P4.3-09. Depends on T008 (same file). `setIntakeR2PutThrows`: the callback response is HTTP 500 and nothing is enqueued. `setD1BatchThrows`: the callback response is HTTP 500 and nothing is enqueued. The command fails because the response is not HTTP 500.

**Checkpoint**: E2E-P4.3-02, E2E-P4.3-03, and E2E-P4.3-09 exist and fail.

### 3.4 User Story 3 - Classify the inquiry before any grant row (Priority: P3) — tests

**Independent Test**: E2E-P4.3-05, E2E-P4.3-06, and E2E-P4.3-07 in harnesses H-ABO and H-PAY.

- [ ] T010 [US3] Add the failing test `E2E-P4.3-05 unbound order and amount mismatch withhold the grant` in `abo/test/system/notify.system.test.ts` — red test, FR-005, E2E-P4.3-05. Depends on T009 (same file). Confirm runs from `POST /notify/paymob` via inline `waitUntil` or `runScheduled` on cron `* * * * *`. Script inquiry `unbound`, then `amount_mismatch`. A different order id records no payment and raises AL-05. An amount mismatch is disposition `withheld_mismatch`, inserts no `grant` work row, and raises AL-05. The command fails because a payment or a grant row is written for the unbound order.

- [ ] T011 [US3] Add the failing test `E2E-P4.3-06 first inquiry already refunded grants nothing` in `abo/test/system/notify.system.test.ts` — red test, FR-006, E2E-P4.3-06. Depends on T010 (same file). Script inquiry `reversed`. `refund-parent.json` and `refund-child.json`, each re-signed, become disposition `reversed_before_grant` with no `grant` work row. The command fails because a `grant` row is inserted.

- [ ] T012 [US3] Add the failing test `E2E-P4.3-07 second payment at the same coverage through is likely_duplicate` in `abo/test/system/notify.system.test.ts` — red test, FR-007, E2E-P4.3-07. Depends on T011 (same file). A second payment for the same tenant from a checkout with the same `opened_with_coverage_through` is classification `likely_duplicate`, raises AL-09, and disposition stays `grant`. The command fails because classification is not `likely_duplicate`.

**Checkpoint**: E2E-P4.3-05, E2E-P4.3-06, and E2E-P4.3-07 exist and fail.

### 3.5 User Story 4 - Retry work, and schedule inquiry from GET callbacks (Priority: P4) — tests

**Independent Test**: E2E-P4.3-08, E2E-P4.3-10, E2E-P4.3-11, and E2E-P4.3-12 in harnesses H-ABO and H-PAY.

- [ ] T013 [US4] Add the failing test `E2E-P4.3-08 inquiry timeout backs off and an old open row raises AL-01` in `abo/test/system/notify.system.test.ts` — red test, FR-008, E2E-P4.3-08. Depends on T012 (same file). `runScheduled` on cron `* * * * *` and inline `waitUntil`. Script inquiry `timeout` or `rate_limit`. The confirm row stays `open` with backoff, and a later attempt succeeds. `opened_at` more than 5 minutes ago raises AL-01. Use `setClock`. Do not sleep. The command fails because the row does not stay `open` or the later attempt does not succeed.

- [ ] T014 [US4] Add the failing test `E2E-P4.3-10 failed confirm batch retries and one lease wins` in `abo/test/system/notify.system.test.ts` — red test, FR-010, E2E-P4.3-10. Depends on T013 (same file). Runner via inline `waitUntil` and `runScheduled`. `setD1BatchThrows` on the confirm batch writes no payment and the row is retried. Two runners: one lease wins. The command fails because facts are written on the failed batch or both runners take the row.

- [ ] T015 [US4] Add the failing test `E2E-P4.3-11 return v=99 is a neutral page and schedules inquiry` in `abo/test/system/notify.system.test.ts` — red test, FR-011, E2E-P4.3-11. Depends on T014 (same file). `SELF.fetch` `GET /return/paymob?v=99` on the billing hostname. The page is neutral (no paid or failed claim), a `confirm` row is scheduled, and no payment is written. The command fails because the page claims a payment outcome or no inquiry is scheduled.

- [ ] T016 [US4] Add the failing test `E2E-P4.3-12 authentic GET notify schedules inquiry only` in `abo/test/system/notify.system.test.ts` — red test, FR-012, E2E-P4.3-12. Depends on T015 (same file). `SELF.fetch` `GET /notify/paymob` on the billing hostname with an authentic response callback. A `confirm` row is scheduled and the GET does not write a payment. The command fails because the GET writes a payment or schedules nothing.

**Checkpoint**: E2E-P4.3-08, E2E-P4.3-10, E2E-P4.3-11, and E2E-P4.3-12 exist and fail. E2E-P4.3-01 through E2E-P4.3-07 and E2E-P4.3-09 still fail.

---

## 4. Implementation

**Purpose**: Sequencing steps 3–8. Each step starts after T005–T016 exist and those E2E tests fail. Within a subphase the tasks run in id order. `abo/src/clinic-api/checkouts.ts`, `abo/src/provider/registry.ts`, `createPaymobIntention`, `abo/src/clock.ts`, and `abo/src/records/append.ts` stay unchanged. Confirm reads `checkout` and `checkout_status` and inserts `checkout_event` / updates `checkout_status` from `abo/src/work/runner.ts`. Fact inserts use the consumed `fact_log` shape in `abo/src/records/append.ts`.

### 4.1 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — migration

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T017 [US1] Add `abo/migrations/0003_notify_work.sql` — produces the notify and work tables, FR-001, FR-002, FR-004, FR-005, FR-006, FR-007, FR-008, FR-010, E2E-P4.3-01. Depends on T016. Tables `notification`, `inquiry_result`, `payment`, `work`, `paymob_txn`, `paymob_state_seen`, and `notify_rate`. Spec columns are the Key Entities in `spec.md`. `notify_rate` is the table plan Storage names for the notify limit; its columns are in `data-model.md`. `work.dedupe_key` is unique. The index on `work` is `(state, next_attempt_at)`. `notification`, `inquiry_result`, and `payment` are append-only (abort updates and deletes, same trigger form as `abo/migrations/0001_records.sql`). `work`, `paymob_txn`, `paymob_state_seen`, and `notify_rate` are mutable. This unit does not create `payment_release`. The harness applies this file before the notify tests.

### 4.2 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — provider port

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T018 [US1] Add `parseNotification` and `inquire` on `abo/src/provider/port.ts` — produces the port methods, FR-001, FR-005, FR-012, FR-013, E2E-P4.3-01, E2E-P4.3-05, E2E-P4.3-12. Depends on T017. `capabilities`, `createCheckout`, and `cancelCheckout` stay. `parseNotification` returns `{authentic, events[]}`. Events are `ProviderTxn` values. `inquire` accepts `{checkout_id}` or `{payment_id}` and returns `{bound, transactions[]}`. This file imports neither `client.ts` nor `adapter.ts`.

### 4.3 User Story 3 - Classify the inquiry before any grant row (Priority: P3) — Paymob inquiry client

**Independent Test**: E2E-P4.3-05, E2E-P4.3-06, and E2E-P4.3-07 in harnesses H-ABO and H-PAY.

- [ ] T019 [US3] Add Paymob inquiry HTTP in `abo/src/provider/paymob/client.ts` — produces the inquiry calls, FR-005, FR-008, FR-013, E2E-P4.3-05, E2E-P4.3-08. Depends on T017. `createPaymobIntention` stays. This file remains the only provider HTTP module. Take an auth token from `POST /api/auth/tokens` with `PAYMOB_API_KEY`. `POST /api/ecommerce/orders/transaction_inquiry` by the stored `order_id`. `GET /api/acceptance/transactions/{id}` for a known transaction. Abort matches the existing intention abort: 500 ms when `TEST_CLOCK` is `"1"`, otherwise 10 seconds. Inquiry timeout and HTTP 429 are returned to the caller as the timeout and rate-limit outcomes. The domain does not import this file.

### 4.4 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — Paymob adapter

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T020 [US1] Add `parseNotification` and `inquire` on `abo/src/provider/paymob/adapter.ts` — produces HMAC, normalisation, and inquiry mapping, FR-001, FR-003, FR-004, FR-005, FR-006, FR-012, FR-013, E2E-P4.3-01, E2E-P4.3-03, E2E-P4.3-04, E2E-P4.3-05, E2E-P4.3-06, E2E-P4.3-12. Depends on T018 and T019. `parseNotification` verifies a processed callback (`POST`, `type = TRANSACTION`) with HMAC-SHA512 over the 20 fields in `data-model.md` §7, compared in constant time, and authentic-checks `GET /notify/paymob` the same way. Events are `ProviderTxn` values from the HMAC-covered fields. `success` and not pending, not refunded, not voided → `payment_succeeded`. Not success and not pending → `payment_failed`. `pending` → `payment_pending` on inquiry only. `is_refunded`, `is_voided`, or a child with `has_parent_transaction` → `reversal` on the `ProviderTxn`. The cumulative amount comes from the inquiry. `bound` is true only when the inquiry `order.id` equals `paymob_intention.order_id`. `merchant_order_id` is ignored. `payment_id` on `paymob_txn` is filled from the domain payment id after confirm; the Paymob transaction id stays in `txn_id`. The state dedupe key on `paymob_state_seen` is transaction, normalized state, and cumulative reversed amount. Record `adapter_version` on the evidence row. Cache the auth token in the isolate until an inquiry responds 401. Only this file imports `client.ts`.

### 4.5 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — notify intake

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T021 [US1] Add `abo/src/notify/intake.ts` — produces the notify and return handlers, FR-001, FR-002, FR-003, FR-009, FR-011, FR-012, E2E-P4.3-01, E2E-P4.3-02, E2E-P4.3-03, E2E-P4.3-09, E2E-P4.3-11, E2E-P4.3-12. Depends on T017 and T020. Do not edit `abo/src/worker.ts` in this task. `POST /notify/paymob`, in order: body cap, then `notify_rate`, then `parseNotification`. A body over 1_048_576 bytes answers HTTP 413 with an empty body and stops. The 61st request in 60 seconds for one `CF-Connecting-IP` answers HTTP 429 with an empty body and stops. A missing `CF-Connecting-IP` uses the key `unknown`. Either refusal stores nothing and enqueues nothing. This route does not use the clinic API version, auth, or per-token rate gates. An HMAC mismatch is HTTP 401 with an empty body, an R2 object under `hmac-invalid/`, and AL-02 when 3 failures fall inside 15 minutes. `dedupe_key` and `body_sha256` are the SHA-256 of the raw body. Invalid HMAC stores nothing under `evidence/` and no new D1 table. Each failure is one object under the 30-day prefix and counts toward AL-02; at most 10 objects in an hour store the raw body. A valid new body: R2 `evidence/` put, then one D1 batch inserting `notification` (`enqueued`) and the `confirm` work row. The same `dedupe_key` inserts disposition `duplicate` and no `confirm` row. A valid body with no stored intention is `unmatched`, evidence stored, no `confirm` row. If the R2 put throws, the response is HTTP 500 and nothing is enqueued. If `DB.batch` throws, the response is HTTP 500 and nothing is enqueued. `GET /return/paymob` for any `v`, including `99`, returns a neutral HTML page and inserts one open `confirm` row per checkout whose status is `open`, using `dedupe_key` `confirm-schedule:{checkout_id}`, when that key is not already present. It does not write a payment. `GET /notify/paymob` authentic-checks with the same HMAC list and only inserts that schedule for the resolved checkout. It does not confirm a payment.

### 4.6 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — worker dispatch

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T022 [US1] Dispatch notify routes and the minute confirm runner in `abo/src/worker.ts` — produces the live entry chains, FR-001, FR-008, FR-011, FR-012, E2E-P4.3-01, E2E-P4.3-08, E2E-P4.3-11, E2E-P4.3-12. Depends on T021. `fetch` gains an `ExecutionContext`. On the billing host, `POST /notify/paymob`, `GET /notify/paymob`, and `GET /return/paymob` go to `notify/intake.ts` before the `/v1/` clinic gates. A processed callback that enqueued `confirm` calls `ctx.waitUntil` on the runner for that row. GET notify and GET return do not. The minute branch of `scheduled` keeps export, heartbeat, alerts, and coverage refresh, and calls the runner for at most 50 due `confirm` rows. A single row failure does not throw out of the cron. Do not edit `abo/src/work/runner.ts` in this task.

### 4.7 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — work runner

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T023 [US1] Add `abo/src/work/runner.ts` — produces lease, backoff, and the confirm batch, FR-001, FR-004, FR-005, FR-006, FR-007, FR-008, FR-010, E2E-P4.3-01, E2E-P4.3-04, E2E-P4.3-05, E2E-P4.3-06, E2E-P4.3-07, E2E-P4.3-08, E2E-P4.3-10. Depends on T020 and T022. A take sets `lease_until` 60 seconds ahead and succeeds only when `lease_until` is null or already past. The conditional update admits one runner. The minute cron takes at most 50 due `confirm` rows. The index used is `(state, next_attempt_at)`. Confirm calls `inquire`. A bound inquiry success inserts one payment whose reference is `PAY-…` (consumed `humanRef`), a checkout `paid` event, and a `grant` work row in the confirm batch. The domain never sees a provider id. A decline writes checkout event `attempt_declined` and leaves the checkout `open`. `pending` writes no payment row and leaves confirm `open` with backoff. Unbound (inquiry order id differs): no payment row, `raiseAlert` AL-05, confirm `done`. Amount or currency differs from the checkout snapshot: payment `withheld_mismatch` with `mismatch_detail`, no `grant` row, AL-05. A first inquiry that already shows a full refund or void writes the payment as `reversed_before_grant` with its reversal attached, and no `grant` row. `likely_duplicate` when an earlier payment for the same `org_id` came from a checkout with the same `opened_with_coverage_through`: AL-09, disposition `grant`, `grant` work row in that batch. `late` when `checkout_status.state` is `expired` or `cancelled`. Otherwise `normal`. Classification is set once. `inquiry_result` is written only when the result differs from the previous one. The confirm batch inserts the step’s facts and their `fact_log` rows, inserts the `grant` work row when disposition is `grant`, and sets the `confirm` row to `done`, conditional on the held `lease_until`. If that batch throws, no fact is written and the row is retried (`last_error` `batch_failed`). Inquiry timeout or HTTP 429: row stays `open`, `attempts` increases, `next_attempt_at` backs off from 1 minute doubling to 15 minutes, `lease_until` cleared. An `open` row older than 5 minutes raises AL-01. `parked` is the state for conflict, rejected, or invariant failure. This unit does not run the grant call or the sweep kinds. Do not edit `abo/src/alert/index.ts` in this task. `raiseAlert` is the function T024 adds.

### 4.8 User Story 2 - Store only authentic callbacks (Priority: P2) — alerts

**Independent Test**: E2E-P4.3-02, E2E-P4.3-03, and E2E-P4.3-09 in harnesses H-ABO and H-PAY.

- [ ] T024 [US2] Add `raiseAlert` and code text in `abo/src/alert/index.ts` — produces AL-01, AL-02, AL-05, and AL-09, FR-003, FR-005, FR-007, FR-008, E2E-P4.3-03, E2E-P4.3-05, E2E-P4.3-07, E2E-P4.3-08. Depends on T023. `sendAlertRow` uses `row.code` in the subject and the text (`{code} {detail_id}`). AL-16 still sets `next_send_at` one day ahead. AL-01 and AL-02 set it one hour ahead. AL-05 and AL-09 set it null so they send once. `raiseAlert(env, code, alertKey, detailId)` inserts the consumed `alert` row with `unsent = 1`. Do not edit `abo/src/work/runner.ts` or `abo/src/notify/intake.ts` in this task.

### 4.9 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — wrangler secrets

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

- [ ] T025 [US1] Add Paymob notify secrets in `abo/wrangler.toml` — produces `PAYMOB_HMAC_SECRET` and `PAYMOB_API_KEY`, FR-001, FR-013, E2E-P4.3-01. Depends on T024. On development, staging, and production, add `PAYMOB_HMAC_SECRET` and `PAYMOB_API_KEY`, placeholders `paymob-hmac-unconfigured` and `paymob-api-unconfigured`. Add no `TEST_CLOCK` var. Add no production fault binding.

---

## 5. Verification

**Purpose**: Sequencing step 9, before `quickstart.md`. The harness is this command from `abo/`. A repository-root `npm test` is not a task.

### 5.1 Unit harness

**Independent Test**: E2E-P4.3-08, E2E-P4.3-10, E2E-P4.3-11, and E2E-P4.3-12 in harnesses H-ABO and H-PAY.

- [ ] T026 [US4] Run `npx vitest run --config vitest.workers.config.ts test/system/notify.system.test.ts` from `abo/` until E2E-P4.3-01 through E2E-P4.3-12 pass — produces the green unit harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, E2E-P4.3-01, E2E-P4.3-02, E2E-P4.3-03, E2E-P4.3-04, E2E-P4.3-05, E2E-P4.3-06, E2E-P4.3-07, E2E-P4.3-08, E2E-P4.3-09, E2E-P4.3-10, E2E-P4.3-11, E2E-P4.3-12. Depends on T025 (and therefore on T001–T024). This task may edit only files under `abo/test/`.

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system/notify.system.test.ts
```

**Checkpoint**: E2E-P4.3-01 through E2E-P4.3-12 pass.

---

## 6. Documentation

**Purpose**: Sequencing step 9, after the harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md` or `data-model.md` task.

### 6.1 Quickstart

- [ ] T027 Create `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, E2E-P4.3-01, E2E-P4.3-02, E2E-P4.3-03, E2E-P4.3-04, E2E-P4.3-05, E2E-P4.3-06, E2E-P4.3-07, E2E-P4.3-08, E2E-P4.3-09, E2E-P4.3-10, E2E-P4.3-11, E2E-P4.3-12. Depends on T026. Sections: (1) what was implemented, and the files added or modified; (2) the harness command below; (3) the entry point → module chain per E2E id below. No earlier-unit files, combined counts, or full-suite commands. No manual steps; the harness observes every scenario.

```bash
cd abo && npx vitest run --config vitest.workers.config.ts test/system/notify.system.test.ts
```

| ID | Chain |
| --- | --- |
| E2E-P4.3-01 | `worker.ts` → `notify/intake.ts` → `adapter.ts` `parseNotification` → R2 and D1 → `waitUntil` → `work/runner.ts` → `adapter.ts` `inquire` → `client.ts` → H-PAY |
| E2E-P4.3-02 | `worker.ts` → `notify/intake.ts` → `adapter.ts` `parseNotification` → R2 and D1 → `waitUntil` → `work/runner.ts` → `adapter.ts` `inquire` → `client.ts` → H-PAY |
| E2E-P4.3-03 | `worker.ts` → `notify/intake.ts` → `adapter.ts` → R2 `hmac-invalid/` → `alert/index.ts` |
| E2E-P4.3-04 | `worker.ts` → `notify/intake.ts` → `adapter.ts` `parseNotification` → R2 and D1 → `waitUntil` → `work/runner.ts` → `adapter.ts` `inquire` → `client.ts` → H-PAY |
| E2E-P4.3-05 | the 01 chain, with the scripted inquiry result |
| E2E-P4.3-06 | the 01 chain, with the scripted inquiry result |
| E2E-P4.3-07 | the 01 chain, with the scripted inquiry result |
| E2E-P4.3-08 | `worker.ts` `scheduled` and `waitUntil` → `work/runner.ts` |
| E2E-P4.3-09 | `worker.ts` → `notify/intake.ts` with the harness wrappers |
| E2E-P4.3-10 | `worker.ts` `scheduled` and `waitUntil` → `work/runner.ts` |
| E2E-P4.3-11 | `worker.ts` → `notify/intake.ts` (no `waitUntil`) |
| E2E-P4.3-12 | `worker.ts` → `notify/intake.ts` (no `waitUntil`) |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: No production notify module exists yet. T001 writes `abo/test/stubs/paymob/worker.ts`. T002 writes the five fixture files. T003 writes `abo/test/system/harness.ts`. T004 writes `abo/vitest.workers.config.ts` after T001. T005 through T016 stay in id order in `abo/test/system/notify.system.test.ts`.
- **Implementation (Phase 4)**: Starts after T016, with E2E-P4.3-01 through E2E-P4.3-12 failing. Migration, then the port and the Paymob inquiry client (different files, both before the adapter), then the adapter, then intake, then `worker.ts` dispatch, then the runner, then alerts, then wrangler secrets.
- **Verification (Phase 5)**: Depends on T025. Runs only the command in §5.1.
- **Documentation (Phase 6)**: Depends on T026 being green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: Tests T005 and T006, after the stub, fixtures, harness helpers, and vitest binding. Implementation T017, T018, T020, T021, T022, T023, and T025. E2E-P4.3-01 and E2E-P4.3-04.
- **User Story 2 (P2)**: Tests T007, T008, and T009 after T006, because they write the same notify test file. Intake behavior for duplicate, HMAC, and 5xx is T021. Alerts are T024. E2E-P4.3-02, E2E-P4.3-03, and E2E-P4.3-09.
- **User Story 3 (P3)**: Tests T010, T011, and T012 after T009. Implementation T019 writes the inquiry client and does not write the adapter. T020 and T023 apply binding, mismatch, reversal, and `likely_duplicate`. E2E-P4.3-05, E2E-P4.3-06, and E2E-P4.3-07.
- **User Story 4 (P4)**: Tests T013, T014, T015, and T016 after T012. T022 calls the runner from `waitUntil` and the minute cron. T023 is the lease, backoff, and confirm batch. E2E-P4.3-08, E2E-P4.3-10, E2E-P4.3-11, and E2E-P4.3-12, with E2E-P4.3-01 through E2E-P4.3-07 and E2E-P4.3-09 still passing once T026 is green.

### 7.3 Within Each Phase

- T001 writes `abo/test/stubs/paymob/worker.ts`. T002 writes `abo/test/fixtures/paymob/success.json`, `abo/test/fixtures/paymob/decline.json`, `abo/test/fixtures/paymob/refund-parent.json`, `abo/test/fixtures/paymob/refund-child.json`, and `abo/test/fixtures/paymob/bad-hmac.json`. T003 writes `abo/test/system/harness.ts`. T004 writes `abo/vitest.workers.config.ts` after T001.
- T005 through T016 all write `abo/test/system/notify.system.test.ts`, in that id order.
- T017 writes `abo/migrations/0003_notify_work.sql` before T018, T019, T021, and T023.
- T018 writes `abo/src/provider/port.ts`. T019 writes `abo/src/provider/paymob/client.ts`. Both follow T017 and both finish before T020. T020 writes `abo/src/provider/paymob/adapter.ts`.
- T021 writes `abo/src/notify/intake.ts` and does not write `abo/src/worker.ts`. T022 writes `abo/src/worker.ts` after T021 and does not write `abo/src/work/runner.ts`. T023 writes `abo/src/work/runner.ts` after T022 and does not write `abo/src/alert/index.ts`.
- T024 writes only `abo/src/alert/index.ts` after T023. T025 writes only `abo/wrangler.toml` after T024.
- T026 runs after T025 and may edit only `abo/test/`.
- T027 writes only `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/quickstart.md` after T026 is green.

---

## 8. Implementation Waves

### 8.1 Wave 1

- T001–T004 [US1] — subphase: `### 3.1 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — H-PAY stub, fixtures, and harness` — paths: `abo/test/stubs/paymob/worker.ts`, `abo/test/fixtures/paymob/success.json`, `abo/test/fixtures/paymob/decline.json`, `abo/test/fixtures/paymob/refund-parent.json`, `abo/test/fixtures/paymob/refund-child.json`, `abo/test/fixtures/paymob/bad-hmac.json`, `abo/test/system/harness.ts`, `abo/vitest.workers.config.ts`

### 8.2 Wave 2

- T005–T006 [US1] — subphase: `### 3.2 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — tests` — paths: `abo/test/system/notify.system.test.ts`

### 8.3 Wave 3

- T007–T009 [US2] — subphase: `### 3.3 User Story 2 - Store only authentic callbacks (Priority: P2) — tests` — paths: `abo/test/system/notify.system.test.ts`

### 8.4 Wave 4

- T010–T012 [US3] — subphase: `### 3.4 User Story 3 - Classify the inquiry before any grant row (Priority: P3) — tests` — paths: `abo/test/system/notify.system.test.ts`

### 8.5 Wave 5

- T013–T016 [US4] — subphase: `### 3.5 User Story 4 - Retry work, and schedule inquiry from GET callbacks (Priority: P4) — tests` — paths: `abo/test/system/notify.system.test.ts`

### 8.6 Wave 6

- T017 [US1] — subphase: `### 4.1 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — migration` — paths: `abo/migrations/0003_notify_work.sql`

### 8.7 Wave 7

- T018 [US1] — subphase: `### 4.2 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — provider port` — paths: `abo/src/provider/port.ts`
- T019 [US3] — subphase: `### 4.3 User Story 3 - Classify the inquiry before any grant row (Priority: P3) — Paymob inquiry client` — paths: `abo/src/provider/paymob/client.ts`

### 8.8 Wave 8

- T020 [US1] — subphase: `### 4.4 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — Paymob adapter` — paths: `abo/src/provider/paymob/adapter.ts`

### 8.9 Wave 9

- T021 [US1] — subphase: `### 4.5 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — notify intake` — paths: `abo/src/notify/intake.ts`

### 8.10 Wave 10

- T022 [US1] — subphase: `### 4.6 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — worker dispatch` — paths: `abo/src/worker.ts`

### 8.11 Wave 11

- T023 [US1] — subphase: `### 4.7 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — work runner` — paths: `abo/src/work/runner.ts`

### 8.12 Wave 12

- T024 [US2] — subphase: `### 4.8 User Story 2 - Store only authentic callbacks (Priority: P2) — alerts` — paths: `abo/src/alert/index.ts`

### 8.13 Wave 13

- T025 [US1] — subphase: `### 4.9 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1) — wrangler secrets` — paths: `abo/wrangler.toml`

### 8.14 Wave 14

- T026 [US4] — subphase: `### 5.1 Unit harness` — paths: `abo/test/`

### 8.15 Wave 15

- T027 — subphase: `### 6.1 Quickstart` — paths: `specs/078-abo-p4-3-notification-intake-inquiry-work-pipeline/quickstart.md`
