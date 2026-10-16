# Feature Specification: Notification intake, inquiry, work pipeline and payment confirmation

**Feature Branch**: `ai/078-abo-p4-3-notification-intake-inquiry-work-pipeline`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P4.3 — Notification intake, inquiry, work pipeline and payment confirmation

## 1. Unit Contract

**Implements** — Read: 03 §2.5; 03 §2.6; 03 §2.9; 03 §2.11 (rows `paymob_txn`, `paymob_state_seen`); 03 §5.2 (classification bullets); 03 §5.6; 04 §5.1 (rows parseNotification, inquire) + 04 §5.2; 04 §5.3 (rows parseNotification, inquire, order binding, normalisation, `payment_id` input); 05 §6.1 ("HMAC replay fixture" bullet).

- `POST /notify/paymob`: body cap, rate limit, HMAC-SHA512 over the 20 fields in constant time; evidence to R2 `evidence/` + `notification` + `confirm` work row in one D1 batch; invalid-HMAC counter + ≤ 10 samples per hour (30-day prefix); AL-02; state dedupe key [SR-02]. `GET` response callback and `GET /return/paymob` (any `v`) only schedule an inquiry.
- Work-row framework: lease by conditional update, backoff 1 → 15 min, `parked`, inline `waitUntil` + minute cron (≤ 50 rows); AL-01 for rows open > 5 min.
- Confirm step: `inquire` (cached auth token; order inquiry / transaction lookup), `bound` check, normalisation, `payment_id` in the adapter, payment fact (classification `normal`/`likely_duplicate`/`late`, disposition `grant`/`withheld_mismatch`/`reversed_before_grant`), checkout events, `inquiry_result` only on change, `adapter_version` on evidence; AL-05, AL-09; the `grant` work row inserted in the same batch (consumed by P4.4). R-2 spike recorded.
- H-PAY: inquiry endpoints + recorded callback fixture.

**Freezes** — None. The unit section states no Outputs / freezes line.

**Consumes** — checkout API; provider-port interface; H-PAY and H-XW harnesses.

**Open questions relied on** — OQ-3 (rule S6 binds the R-2 spike this unit records; the question states the remaining R-2 items stay with P4.3): yes, provisioned at the start of P4.2. If the staging Supabase project is not available, P5.2 stops at its spike step. If the Paymob test integration is not available, P4.2 does not stop. The R-2 intention-expiry default is already bound for P4.2 (`expiration` = 1800 s; checkout `expires_at` is creation plus 30 minutes). A live Paymob account is not required for P4.2. The remaining R-2 items stay with P4.3.

**Spikes** — R-2 for this unit (rule S6): redelivery, second success, order listing, rate limits. Fallback named for R-2 (05 §10 Spike-dependent items, cited by rule S6): inquiry sweeps. Those sweeps are P4.5. This unit records the spike outcome.

## Clarifications

### Session 2026-10-07

- Q: How should H-PAY script inquiry results for this unit's tests? → A: Extend the existing auxiliary worker at `abo/test/stubs/paymob/` and keep one base URL. Before confirm, the test sets that stub's inquiry script (bound success, unbound order, amount mismatch, reversed, timeout, or rate limit). Recorded callback bodies stay under `abo/test/fixtures/paymob/` and are re-signed with the local HMAC secret. `[implementation choice — no §citation]`
- Q: How should E2E-P4.3-09 and the forced confirm-batch failure in E2E-P4.3-10 inject storage faults? → A: The H-ABO harness makes the intake R2 `put` throw for the R2 failure, and the D1 `batch` throw for ABO D1 unavailable and for the confirm-batch failure. The production routes have no fault flag. `[implementation choice — no §citation]`
- Q: How should a repeated callback body be recognized, and where should the invalid-HMAC counter and samples live? → A: `dedupe_key` and `body_sha256` are the SHA-256 of the raw body. The same `dedupe_key` is disposition `duplicate` and does not insert another `confirm` row. The invalid-HMAC counter and the sampled bodies are R2 objects under the 30-day prefix, with no new D1 table. Each failure is one object and counts toward AL-02; at most 10 objects in an hour store the raw body. `[implementation choice — no §citation]`
- Q: How should the notify body cap and rate limit be verified without a new E2E id? → A: Assert the empty-body HTTP 413 and HTTP 429 refusals inside the existing H-ABO `POST /notify/paymob` intake tests. Do not add an E2E id. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Confirm a paid checkout from a processed callback (Priority: P1)

Paymob posts a processed transaction callback for an open checkout. The ABO verifies the HMAC, stores the body as evidence, and enqueues confirmation. The confirm step inquires, and a bound success becomes one `PAY-…` payment, a checkout `paid` event, and an open `grant` work row. A decline on that checkout is only an `attempt_declined` event; a later success on the same checkout is still one payment.

**Why this priority**: Duplicate handling, withholding, and the work runner all depend on a notification that can become one payment. This is the path those stories use.

**Independent Test**: E2E-P4.3-01 and E2E-P4.3-04 in harnesses H-ABO and H-PAY.

**Acceptance Scenarios**:

1. **Given** an open checkout and a recorded success callback re-signed with the local HMAC secret, **When** Paymob posts it to `POST /notify/paymob` and the confirm step inquires a bound success, **Then** the notification is stored, the payment reference is `PAY-…`, the checkout event is `paid`, and a `grant` work row is open. (E2E-P4.3-01, 03 §2.5, 03 §2.6, 03 §2.9, 04 §5.3 rows parseNotification and inquire)
2. **Given** an open checkout, **When** a decline callback is posted and then a success callback is posted for the same checkout, **Then** the decline is an `attempt_declined` event, the checkout stays open after the decline, and the success is one payment. (E2E-P4.3-04, 04 §5.3 normalisation)

### 2.2 User Story 2 - Store only authentic callbacks (Priority: P2)

The same callback body posted again is a duplicate and does not create a second payment. A bad HMAC stores nothing as evidence. Three HMAC failures within 15 minutes raise AL-02, and a sample of the bad body is kept. If R2 or D1 cannot take the intake batch, the callback receives 5xx and nothing is enqueued.

**Why this priority**: User Story 1 has already shown a valid callback becoming a payment. This story is the intake boundary around that path.

**Independent Test**: E2E-P4.3-02, E2E-P4.3-03, and E2E-P4.3-09 in harnesses H-ABO and H-PAY.

**Acceptance Scenarios**:

1. **Given** a callback body already stored, **When** the same body is posted again, **Then** the notification disposition is `duplicate` and there is still one payment. (E2E-P4.3-02, 03 §2.5)
2. **Given** a callback whose HMAC does not verify, **When** it is posted, **Then** nothing is stored as evidence. **When** 3 such failures occur within 15 minutes, **Then** AL-02 fires and a sample is kept. (E2E-P4.3-03, 03 §2.5, 05 §6.1 HMAC replay fixture)
3. **Given** the evidence write cannot finish, **When** a callback is posted, **Then** the response is 5xx and nothing is enqueued. An R2 write failure is FM-08. ABO D1 unavailable is FM-07 and follows that same pattern. Sweep recovery of FM-07 is P4.5. (E2E-P4.3-09, 03 §2.9, 06 §5 D1 FM-07 note)

### 2.3 User Story 3 - Classify the inquiry before any grant row (Priority: P3)

The confirm step trusts the inquiry, not the callback, for the payment fact. An unbound order records no payment and alerts. An amount mismatch is `withheld_mismatch` with no `grant` row and AL-05. A first inquiry that already shows a refund is `reversed_before_grant` and grants nothing. A second payment from a checkout opened at the same `opened_with_coverage_through` is `likely_duplicate`, raises AL-09, and its disposition is still `grant`.

**Why this priority**: User Story 1 grants only the bound success. This story is every other confirm outcome.

**Independent Test**: E2E-P4.3-05, E2E-P4.3-06, and E2E-P4.3-07 in harnesses H-ABO and H-PAY.

**Acceptance Scenarios**:

1. **Given** an inquiry whose order id is not the stored order, **When** confirm runs, **Then** no payment is recorded and an alert fires. **Given** an amount mismatch, **When** confirm runs, **Then** the disposition is `withheld_mismatch`, there is no `grant` work row, and AL-05 fires. (E2E-P4.3-05, 03 §2.6, 04 §5.2, 04 §5.3 order binding)
2. **Given** the first inquiry already shows a refund, **When** confirm runs, **Then** the disposition is `reversed_before_grant` and there is no `grant` work row. (E2E-P4.3-06, 03 §2.6)
3. **Given** an earlier confirmed payment for the same tenant from a checkout with the same `opened_with_coverage_through`, **When** a second payment is confirmed, **Then** the classification is `likely_duplicate`, AL-09 fires, and the disposition is still `grant`. (E2E-P4.3-07, 03 §5.2 classification bullets)

### 2.4 User Story 4 - Retry work, and schedule inquiry from GET callbacks (Priority: P4)

A confirm row that hits an inquiry timeout or rate limit stays open, backs off, and succeeds on a later attempt. A row open more than 5 minutes raises AL-01. A failed confirm batch writes no facts and the row is retried. Two runners take one lease. `GET /return/paymob?v=99` shows a neutral page and schedules an inquiry. An authentic response callback (GET) schedules an inquiry only.

**Why this priority**: The earlier stories use one successful inline confirm. This story is the runner, the lease, and the GET entries that do not themselves confirm a payment. E2E-P4.3-01 through E2E-P4.3-07 and E2E-P4.3-09 still pass.

**Independent Test**: E2E-P4.3-08, E2E-P4.3-10, E2E-P4.3-11, and E2E-P4.3-12 in harnesses H-ABO and H-PAY.

**Acceptance Scenarios**:

1. **Given** an open confirm row and an inquiry that times out or is rate limited, **When** the runner attempts it, **Then** the row stays open with backoff and a later attempt succeeds. **When** a row has been open more than 5 minutes, **Then** AL-01 fires. (E2E-P4.3-08, 03 §5.6)
2. **Given** a confirm step whose D1 batch fails, **When** the runner finishes the step, **Then** no facts are written and the row is retried. **Given** two runners, **When** both try the same row, **Then** one lease wins. (E2E-P4.3-10, 03 §2.9, 03 §5.6)
3. **Given** a browser return with `v=99`, **When** `GET /return/paymob?v=99` is requested, **Then** the page is neutral and an inquiry is scheduled. (E2E-P4.3-11, 04 §7.1 return channel)
4. **Given** an authentic response callback, **When** that GET is requested, **Then** an inquiry is scheduled and the GET does not itself confirm a payment. (E2E-P4.3-12, 04 §5.3 row parseNotification)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.3-01 | H-ABO + H-PAY | `SELF.fetch` `POST /notify/paymob` on the ABO worker `fetch`, billing hostname; inline `waitUntil` confirm; H-PAY inquiry scripted bound success | Replayed success callback re-signed → notification stored; inquiry bound success → `PAY-…` payment; checkout `paid`; `grant` row open [FR-12, SR-01] | FR-001 | User Story 1 |
| E2E-P4.3-02 | H-ABO + H-PAY | `SELF.fetch` `POST /notify/paymob` on the ABO worker `fetch`, billing hostname | Same body again → disposition `duplicate`; still one payment [NFR-02] | FR-002 | User Story 2 |
| E2E-P4.3-03 | H-ABO + H-PAY | `SELF.fetch` `POST /notify/paymob` on the ABO worker `fetch`, billing hostname; HMAC replay fixture bad-HMAC body | Bad HMAC → nothing stored as evidence; 3 within 15 min → AL-02; a sample kept [TB-1, A23] | FR-003 | User Story 2 |
| E2E-P4.3-04 | H-ABO + H-PAY | `SELF.fetch` `POST /notify/paymob` on the ABO worker `fetch`, billing hostname; inline `waitUntil` confirm | A5: decline callback, then a success on the same checkout → `attempt_declined`, checkout still open, then one payment | FR-004 | User Story 1 |
| E2E-P4.3-05 | H-ABO + H-PAY | Confirm step reached from `POST /notify/paymob` via inline `waitUntil` or `runScheduled` on cron `* * * * *`; H-PAY inquiry scripted unbound, then amount mismatch | Unbound order (different order id) → no payment + alert; amount mismatch → `withheld_mismatch`, no grant row, AL-05 [FR-13, FR-16, A7] | FR-005 | User Story 3 |
| E2E-P4.3-06 | H-ABO + H-PAY | Confirm step reached from `POST /notify/paymob` via inline `waitUntil` or `runScheduled` on cron `* * * * *`; H-PAY inquiry scripted reversed | First inquiry already shows a refund → `reversed_before_grant`; no grant [FR-42] | FR-006 | User Story 3 |
| E2E-P4.3-07 | H-ABO + H-PAY | Confirm step reached from `POST /notify/paymob` via inline `waitUntil` or `runScheduled` on cron `* * * * *` | A6: second payment from a checkout opened at the same `opened_with_coverage_through` → `likely_duplicate` + AL-09; disposition still `grant` [FR-41] | FR-007 | User Story 3 |
| E2E-P4.3-08 | H-ABO + H-PAY | `runScheduled` on the ABO worker `scheduled` for cron `* * * * *`, and inline `waitUntil`; H-PAY inquiry scripted timeout or rate limit; ABO test clock | Inquiry timeout or rate limit → row stays open with backoff, succeeds later; open > 5 min → AL-01 [NFR-01] | FR-008 | User Story 4 |
| E2E-P4.3-09 | H-ABO + H-PAY | `SELF.fetch` `POST /notify/paymob` on the ABO worker `fetch`, billing hostname; R2 write fault and D1 unavailable fault | FM-08: R2 write fails → 5xx to the callback; nothing enqueued. FM-07: ABO D1 unavailable → 5xx to the callback; nothing enqueued (sweep recovery is P4.5) | FR-009 | User Story 2 |
| E2E-P4.3-10 | H-ABO + H-PAY | Confirm runner via inline `waitUntil` and `runScheduled` on cron `* * * * *`; two runners | FM-21: forced batch failure → no facts, row retried; FM-15: two runners → one lease wins | FR-010 | User Story 4 |
| E2E-P4.3-11 | H-ABO + H-PAY | `SELF.fetch` `GET /return/paymob?v=99` on the ABO worker `fetch`, billing hostname | `GET /return/paymob?v=99` → neutral page, inquiry scheduled [04 §7.1] | FR-011 | User Story 4 |
| E2E-P4.3-12 | H-ABO + H-PAY | `SELF.fetch` `GET /notify/paymob` response callback on the ABO worker `fetch`, billing hostname | Authentic response callback (GET) → schedules an inquiry only | FR-012 | User Story 4 |

### 2.6 Edge Cases

- The same callback body again has notification disposition `duplicate` and leaves a single payment. (E2E-P4.3-02, 03 §2.5)
- A body that fails HMAC is not stored as evidence. A counter is kept. At most 10 bodies per hour are sampled under a 30-day R2 prefix. Three failures within 15 minutes raise AL-02. (E2E-P4.3-03, 03 §2.5)
- An unbound inquiry (order id different from the stored `intention_order_id`) records no payment and alerts. `merchant_order_id` is not HMAC-covered and is never trusted from a callback. (E2E-P4.3-05, 04 §5.3 order binding, 04 §5.2)
- A confirmed success whose amount or currency does not equal the checkout snapshot is `withheld_mismatch`: the payment is recorded, no `grant` work row is inserted, and AL-05 fires. 03 §2.6 names a wrong order in that same withheld recording. The unit scenario for a different order id is the unbound outcome above: no payment. (E2E-P4.3-05, 03 §2.6, 04 §5.2)
- The first inquiry already shows the success fully refunded or voided: disposition `reversed_before_grant`, reversal attached, no grant. (E2E-P4.3-06, 03 §2.6)
- `likely_duplicate` is granted like any other payment. The owner and operator are told. AL-09 fires. Disposition stays `grant`. (E2E-P4.3-07, 03 §5.2)
- Classification `late` is set when the checkout was `expired` or `cancelled`. `normal` is every other confirmation. Classification is set once, at confirmation. Expiry and cancel sweeps are P4.5 and P4.6. (03 §5.2 classification bullets)
- Inquiry timeout or rate limit leaves the confirm row open. Backoff starts at 1 minute and doubles to 15 minutes. A later attempt can succeed. An `open` row older than 5 minutes raises AL-01. The harness advances the ABO test clock. A local scenario spends at most 2 seconds of real time. (E2E-P4.3-08, 03 §5.6, 06 §3 V4)
- R2 write failure (FM-08) or ABO D1 unavailable (FM-07) answers 5xx and enqueues nothing. A failed confirm batch writes no facts and retries the row (FM-21). Two runners: the conditional lease update admits one (FM-15). (E2E-P4.3-09, E2E-P4.3-10, 03 §2.9)
- `GET /return/paymob` for any `v`, including `v=99`, shows a neutral page and schedules an inquiry. This channel has no contract-version refusal. The page does not grant service. (E2E-P4.3-11, 04 §7.1)
- An authentic response callback (GET `/notify/paymob`) only schedules an inquiry. (E2E-P4.3-12, 04 §5.3 row parseNotification)
- `pending` normalises to `payment_pending` on inquiry only. There is no pending callback. (04 §5.3 normalisation)
- `is_refunded`, `is_voided`, or a child with `has_parent_transaction` normalises to a `reversal` against the parent. The cumulative amount is taken from the inquiry because `refunded_amount_cents` is not HMAC-covered. (04 §5.3 normalisation, 05 §6.1 HMAC replay fixture)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `POST /notify/paymob` on the billing host applies a body cap and a rate limit. The Paymob adapter `parseNotification` verifies a processed callback (`POST`, `type = TRANSACTION`) with HMAC-SHA512 over the 20 documented fields in order, compared in constant time. A valid body is stored under the R2 prefix `evidence/`. The same D1 batch inserts the `notification` row and its `confirm` work row. The adapter records `adapter_version` on the evidence row. A bound inquiry success then inserts one payment whose reference is `PAY-…`, a checkout `paid` event, and a `grant` work row in the confirm batch. The domain never sees a provider id. (03 §2.5, 03 §2.6, 03 §2.9, 04 §5.1 row parseNotification, 04 §5.3 rows parseNotification and `payment_id` input, Implements, E2E-P4.3-01)
- **FR-002**: Posting the same body again sets notification disposition `duplicate` and does not create a second payment. (03 §2.5, E2E-P4.3-02)
- **FR-003**: Bodies that fail HMAC are not stored as evidence. A counter is kept, plus a sample of at most 10 bodies per hour under a 30-day R2 prefix. Three HMAC failures within 15 minutes raise AL-02, and a sample is kept. The state dedupe key is the `paymob_state_seen` key: transaction, normalized state, and cumulative reversed amount. (03 §2.5, 03 §2.11 row `paymob_state_seen`, E2E-P4.3-03)
- **FR-004**: A decline callback writes checkout event `attempt_declined` and leaves the checkout open. A later success on that checkout is one payment. Not `success` and not `pending` normalises to `payment_failed`. `success` and not `pending`, not refunded, and not voided normalises to `payment_succeeded`. (04 §5.3 normalisation, E2E-P4.3-04)
- **FR-005**: `inquire` accepts `{checkout_id}` or `{payment_id}` and returns `{bound, transactions[]}`. `bound` is true only when the inquiry's `order.id` equals the stored `intention_order_id`. An unbound order (different order id) records no payment and alerts. A confirmed success whose `amount_minor` or `currency` does not equal the checkout snapshot is recorded as `withheld_mismatch` with `mismatch_detail`, no `grant` work row, and AL-05. `merchant_order_id` is never trusted from a callback. (03 §2.6, 04 §5.1 row inquire, 04 §5.2, 04 §5.3 order binding, E2E-P4.3-05)
- **FR-006**: A success that the first inquiry already shows as fully refunded or voided is recorded as `reversed_before_grant`, with its reversal attached, and no `grant` work row is inserted. (03 §2.6, E2E-P4.3-06)
- **FR-007**: Classification is set once, at confirmation. `likely_duplicate` means an earlier confirmed payment of the same tenant came from a checkout with the same `opened_with_coverage_through`. It is granted like any other payment. AL-09 fires. Disposition stays `grant`, and the `grant` work row is inserted in that same batch. `late` means the checkout was `expired` or `cancelled`. `normal` is everything else. (03 §5.2 classification bullets, 03 §2.6, Implements, E2E-P4.3-07)
- **FR-008**: The work-row runner takes a row with a conditional update on `lease_until`. Transient failure leaves the row `open` and backs off from 1 minute, doubling to 15 minutes. An `open` row older than 5 minutes raises AL-01. Inquiry timeout or rate limit keeps the row open; a later attempt can succeed. The inline attempt uses `waitUntil`. The minute cron `* * * * *` runs the same runner for at most 50 rows. The index is `(state, next_attempt_at)`. (03 §2.9, 03 §5.6, Implements, E2E-P4.3-08)
- **FR-009**: If the R2 evidence write fails, the callback response is 5xx and nothing is enqueued (FM-08). If ABO D1 is unavailable, the callback response is 5xx and nothing is enqueued (FM-07). Sweep recovery of that D1 failure is P4.5. (03 §2.9, 06 §5 D1 note on FM-07, E2E-P4.3-09)
- **FR-010**: A runner finishes a step with one D1 batch that inserts the step's facts (with their `fact_log` rows), inserts the next step's work row, and sets its own row to `done`, conditional on still holding the lease. If that batch fails, nothing is written and the row is retried (FM-21). Two runners: the lease update admits one (FM-15). `parked` is the state for conflict, rejected, or invariant failure. (03 §2.9, 03 §5.6, E2E-P4.3-10)
- **FR-011**: `GET /return/paymob` with any `v`, including `v=99`, schedules an inquiry and shows a neutral page. Unknown `v` is not a contract-version refusal and does not by itself write a payment. (04 §7.1 return channel, Implements, E2E-P4.3-11)
- **FR-012**: The response callback is `GET /notify/paymob`. `parseNotification` authentic-checks it the same way as the processed callback and only schedules an inquiry. It does not itself confirm a payment. (04 §5.3 row parseNotification, Implements, E2E-P4.3-12)
- **FR-013**: H-PAY gains the order-inquiry and transaction endpoints, scripted per test for bound or unbound order, amount mismatch, pending, reversed, timeout, and rate limit. The HMAC replay fixture is recorded callback bodies with no real card data, re-signed with a local HMAC secret, and posted to `/notify/paymob`. It covers success, decline, refund as parent flags, refund as a child transaction, a bad HMAC, and a replayed body. `inquire` takes an auth token from `POST /api/auth/tokens` with the API key, cached for its life; `POST /api/ecommerce/orders/transaction_inquiry` by the stored `order_id`; and `GET /api/acceptance/transactions/{id}` for a known transaction. Whether order retrieval lists every transaction is the R-2 order-listing item. `payment_id` input is the successful transaction's `id`, mapped in the adapter onto `paymob_txn`. `inquiry_result` is written only when the result differs from the previous one. (03 §2.5, 03 §2.11 row `paymob_txn`, 04 §5.3 rows inquire and `payment_id` input, 05 §6.1 HMAC replay fixture, 06 §3 V1 H-PAY, Implements)

### 3.2 Key Entities

- **`notification`**: Append-only. `notification_id`, `provider_id`, `channel` (`processed`, `response`), `hmac_valid`, `body_r2_key`, `body_sha256`, `dedupe_key`, `checkout_id`, `disposition` (`enqueued`, `duplicate`, `unmatched`). Raw verified bodies live under R2 `evidence/`. (03 §2.5)
- **`inquiry_result`**: Append-only. `inquiry_id`, `subject` (checkout or payment), `normalized_state`, `cumulative_reversed_minor`, `raw_r2_key`, `raw_sha256`, `at`. Written only when the result differs from the previous one. (03 §2.5)
- **`payment`**: Append-only. `payment_id`, `reference` (`PAY-…`), `org_id`, `checkout_id`, `provider_id`, `amount_minor`, `currency`, `paid_at`, `confirmed_at`, `confirmation_inquiry_id`, `offer_id`, `offer_version`, `billing_contact_version`, `classification` (`normal`, `likely_duplicate`, `late`), `disposition` (`grant`, `withheld_mismatch`, `reversed_before_grant`), `mismatch_detail`, `evidence_sha256`. A payment exists only after the authenticated inquiry confirms it. This unit does not write `payment_release`. (03 §2.6, E2E-P4.3-01)
- **`work`**: Mutable. `work_id`, `kind` (`confirm`, `grant`, `reverse`, `sweep_checkout`, `sweep_payment`, `transfer_step`), `subject_id`, `dedupe_key` (unique), `state` (`open`, `done`, `parked`), `attempts`, `next_attempt_at`, `lease_until`, `last_error`. This unit inserts `confirm` at intake and `grant` when the payment disposition is `grant`. It does not run the grant call or the sweep kinds. (03 §2.9, 03 §5.6, Implements)
- **`paymob_txn`**: Adapter table. `txn_id`, `order_id`, `checkout_id`, `payment_id`, `parent_txn_id`, `last_state_key`. Only the adapter reads or writes it. (03 §2.11)
- **`paymob_state_seen`**: Adapter table. `dedupe_key` (unique: txn, normalized state, cumulative reversed amount), `source`, `first_seen_at`. Only the adapter reads or writes it. (03 §2.11)
- **`ProviderTxn`**: `kind` (`payment_succeeded`, `payment_failed`, `payment_pending`, `reversal`), `checkout_id`, `payment_id`, `amount_minor`, `currency`, `occurred_at`, `dedupe_key`, optional `reversal` `{kind: refund, void, chargeback or unknown; amount_minor; cumulative_reversed_minor; is_full}`. (04 §5.2)
- **Provider port extensions**: `parseNotification` and `inquire`, on the consumed port that already has `capabilities`, `createCheckout`, and `cancelCheckout`. (04 §5.1)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: A clinic's card payment is confirmed only after Paymob's authenticated inquiry matches the checkout that clinic opened. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. Live entries are `SELF.fetch` on the ABO worker `fetch` (billing hostname: `POST /notify/paymob`, `GET /notify/paymob`, `GET /return/paymob`) and the work runner on inline `waitUntil` plus `runScheduled` for cron `* * * * *`. Paymob is behind the consumed provider port. H-PAY stands in for inquiry and for the recorded callback fixture. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: HMAC-valid bodies are the only callback evidence. Nothing is granted from the callback alone. `bound`, amount, and currency are checked against the checkout snapshot. Provider identifiers stay on `paymob_txn` and `paymob_state_seen`. The confirm facts and the next work row commit in one D1 batch. The consumed alert engine raises AL-01, AL-02, AL-05, and AL-09. (03 §2.5, 03 §2.6, 03 §2.9, 03 §2.11, 04 §5.2)
- **Failure Handling**: Bad HMAC stores no evidence. Inquiry timeout or rate limit retries with backoff. R2 or D1 failure on intake returns 5xx and enqueues nothing. A failed confirm batch writes no facts. Two runners cannot both hold the lease. `GET /return/paymob` does not grant service. (E2E-P4.3-03, E2E-P4.3-08, E2E-P4.3-09, E2E-P4.3-10, E2E-P4.3-11)

## 5. Out of Scope

- Grant call (→ P4.4); sweeps, expiry, reversals (→ P4.5).
- No Do-not-read material: 03 §2.7 and 03 §5.5 stay with P4.5. This unit records `reversed_before_grant` and attaches the reversal named in 03 §2.6. It does not implement the reversal lifecycle.
- No rewrite of the consumed contracts: checkout API; provider-port interface (`capabilities`, `createCheckout`, `cancelCheckout`); H-PAY and H-XW harnesses (rule S7). This unit adds `parseNotification` and `inquire` and extends H-PAY with inquiry endpoints and the callback fixture.
- No module that no test-plan row reaches (rule S8). `POST /notify/paymob` is reached by E2E-P4.3-01. `GET /notify/paymob` is reached by E2E-P4.3-12. `GET /return/paymob` is reached by E2E-P4.3-11. The confirm runner is reached by inline `waitUntil` and by `runScheduled` in E2E-P4.3-08 and E2E-P4.3-10.
- No S9 path owned by a later unit. The grant call stays with P4.4. Sweeps, expiry, and reversals stay with P4.5.
- No second codebase. The Codebase cell is `abo`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.3-01 through E2E-P4.3-12 pass in H-ABO + H-PAY.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-3 default: staging accounts are provisioned at the start of P4.2. If the Paymob test integration is not available, P4.2 does not stop. A live Paymob account is not required for P4.2. The remaining R-2 items (redelivery, second success, order listing, rate limits) stay with P4.3. The R-2 fallback is inquiry sweeps, owned by P4.5.
- The grant call stays with P4.4. Sweeps, expiry, and reversals stay with P4.5 (unit Out of scope, rule S9).
