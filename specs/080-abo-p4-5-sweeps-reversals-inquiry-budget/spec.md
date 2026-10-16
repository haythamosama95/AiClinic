# Feature Specification: Sweeps, reversals and the inquiry budget

**Feature Branch**: `ai/080-abo-p4-5-sweeps-reversals-inquiry-budget`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P4.5 — Sweeps, reversals and the inquiry budget

## 1. Unit Contract

**Implements** — Read: 03 §2.7; 03 §5.1 (expired/late edges); 03 §5.2 (reversal edges); 03 §5.5; 05 §1 (ABO rows: minute sweeps, hourly, 6-hourly, daily; budget sentence); 04 §1.3 row voidForReversal; 05 §2 rows AL-03, AL-06, AL-08; 05 §8 rows A3, A16, A17, A23.

- Checkout sweeps (+2, +5, +10, +20 min, every 10 min to expiry, a final inquiry → `expired`, widening to 7 days for expired/cancelled); late payment → `paid_late`, classification `late`, AL-08; AL-03 (confirmed with no verified callback); reversals from notifications (parent flags, child transaction) and tiered inquiries (hourly in the first 7 days or while the grant is unapplied; 6-hourly while funding a live, queued or held term; daily one-seventh up to 180 days); `reversal` facts (cumulative, `is_full`), dismissal + finding; effect (`tombstone`, `end_current`, `remove_queued`, `none`, `review_partial`); `reverse` work rows → signed `voidForReversal`; `reversal_outcome`; AL-06 on every reversal; per-minute inquiry budget with confirm/grant first; notices `reversal_recorded`, `terms_held`.

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P4.4: subscription and payments responses. CP-C. P3.7: void, release and listing methods; the tombstone rule.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-07

- Q: How does the daily tier choose its one-seventh and spread those inquiries across the day? → A: At 06:00 UTC, select payments in the daily population whose stable slot (a stable function of `payment_id` modulo 7) equals the UTC date modulo 7. Set each selected inquiry due at a minute in the following 24 hours, also a stable function of `payment_id`, on the existing due-work `next_attempt_at`. The minute runner performs them under the existing per-minute budget and does not drop any. E2E-P4.5-09 uses a 100-day-old payment in today's slot and advances the test clock to that payment's due minute. `[implementation choice — no §citation]`
- Q: How does the harness block the callback in E2E-P4.5-01? → A: The Paymob stub never delivers `POST /notify/paymob` for that checkout. The +2 minute sweep is the first confirmation. The clock's zero is checkout creation. `[implementation choice — no §citation]`
- Q: What integer is the shared per-minute provider-inquiry budget? → A: 2. Sweeps and work rows share that one cap. E2E-P4.5-10 schedules more than 2 due provider inquiries, including confirm and grant work rows; those rows are served first, and every inquiry that does not fit stays due. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Recover a checkout when the callback does not confirm it (Priority: P1)

A clinic admin has an open checkout. The callback is blocked, fails HMAC, or the ABO crashes after receiving it. The minute sweep inquires with the provider, confirms the payment, and the existing grant step runs. An unpaid checkout expires after a final inquiry. A payment found on day 3 is honoured at the checkout snapshot, classified `late`, and raises AL-08.

**Why this priority**: Reversal inquiries, refund effects, and the inquiry budget all run against a payment this sweep can confirm. A blocked or crashed callback still has to become a payment and a grant.

**Independent Test**: E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-03, and E2E-P4.5-12 in harnesses H-XW and H-PAY.

**Acceptance Scenarios**:

1. **Given** an open checkout whose callback is blocked, **When** the minute sweep reaches +2 minutes, **Then** that inquiry confirms the payment and the grant step runs, and AL-03 is raised. The sweep also inquires at +5, +10, and +20 minutes. (E2E-P4.5-01, A3, FM-02, 05 §1 minute row, 05 §2 row AL-03)
2. **Given** every callback fails HMAC, **When** AL-02 has fired and the sweeps run, **Then** the sweeps still confirm the payments by inquiry. (E2E-P4.5-02, A23, FM-03, FM-18)
3. **Given** a checkout is still unpaid when it expires, **When** the final inquiry runs, **Then** the checkout is `expired`. **Given** that expired checkout is paid on day 3, **When** the sweep confirms it, **Then** the checkout is `paid_late`, the payment classification is `late`, the grant uses the checkout snapshot, and AL-08 is raised. (E2E-P4.5-03, 03 §5.1, 05 §2 row AL-08)
4. **Given** the ABO crashes after receiving a callback, **When** that callback was answered with 5xx or the work row is open, **Then** the sweep inquires within 2–20 minutes. (E2E-P4.5-12, FM-01, 05 §1 minute row)

### 2.2 User Story 2 - Record a refund and apply its effect (Priority: P2)

A refund arrives as parent flags or as a child transaction. The adapter records a reversal and never a payment. A full refund of the payment that funds the active term ends that term and holds queued terms. A refund of an ended term is recorded only. A full refund while the grant is still granting or parked stores a tombstone. A partial refund stays in review and does not void. An inquiry that contradicts the refund callback dismisses the reversal and raises a finding.

**Why this priority**: User Story 1 can confirm a payment and grant a term. This story is the refund that follows that payment, and the subscription notices the frozen response already returns.

**Independent Test**: E2E-P4.5-04, E2E-P4.5-05, E2E-P4.5-06, E2E-P4.5-07, E2E-P4.5-08, and E2E-P4.5-11 in harnesses H-XW and H-PAY.

**Acceptance Scenarios**:

1. **Given** a payment funding the active term, with a queued term behind it, **When** a parent-flag refund callback is accepted, **Then** the adapter records one reversal and no payment, the effect is `end_current`, signed `voidForReversal` voids the term, the term is reversed, the queued term is held, AL-06 fires, and `GET /v1/subscription` shows `terms_held`. (E2E-P4.5-04, A16, 03 §5.5, 04 §1.3 row voidForReversal, 05 §2 row AL-06)
2. **Given** the same payment, **When** the refund arrives as a child transaction, **Then** the effect matches the parent-flag result, and the dedupe key prevents a second reversal. (E2E-P4.5-05, A16, SR-02)
3. **Given** a payment whose term has ended, **When** a reversal of that payment is confirmed, **Then** the effect is `none`, the reversal is recorded, AL-06 fires, and the service does not change. (E2E-P4.5-06, A17, 03 §5.5)
4. **Given** a full reversal while the grant is granting or parked, **When** the reversal is confirmed, **Then** the platform stores a tombstone, the pending grant is later `rejected` with `voided`, and that grant work row closes. (E2E-P4.5-07, 03 §5.2, 03 §5.5, 04 §1.3 row voidForReversal)
5. **Given** a partial refund, **When** it is confirmed, **Then** the effect is `review_partial`, the reversal stays in review, `voidForReversal` is not sent, there is no void, and an alert fires. (E2E-P4.5-08, 03 §5.5, X-01)
6. **Given** a refund callback, **When** a later inquiry contradicts it, **Then** the reversal is dismissed and a finding is raised. (E2E-P4.5-11, 03 §5.5)

### 2.3 User Story 3 - Find a lost refund by tiered inquiry (Priority: P3)

A refund callback never arrives. The hourly inquiry finds it on day 3, or while the grant is still unapplied. The 6-hour inquiry finds it while the payment funds a live, queued, or held term. The daily inquiry finds it on a 100-day-old payment.

**Why this priority**: User Story 2 applies a refund that the callback delivered. This story is the same reversal when that callback is lost.

**Independent Test**: E2E-P4.5-09 in harnesses H-XW and H-PAY.

**Acceptance Scenarios**:

1. **Given** a refund callback was lost, **When** the hourly tier runs on day 3, the 6-hour tier runs for a payment funding a live term, and the daily tier runs for a 100-day-old payment, **Then** each tier's inquiry finds that refund. (E2E-P4.5-09, A16, 05 §1 hourly, 6-hourly, and daily rows)

### 2.4 User Story 4 - Serve confirm and grant inquiries before the rest of the budget (Priority: P4)

The minute runner has more provider inquiries due than the per-minute budget of 2. Confirmation and grant work rows run first. Inquiries that do not fit in that minute stay due.

**Why this priority**: User Stories 1 and 3 inquire on the same budget as confirmation and grant work. This story is the order of that budget.

**Independent Test**: E2E-P4.5-10 in harnesses H-XW and H-PAY. Earlier suites stay green, and E2E-P4.5-01 through E2E-P4.5-09, E2E-P4.5-11, and E2E-P4.5-12 still pass.

**Acceptance Scenarios**:

1. **Given** more than 2 provider inquiries are due, **When** the minute runner spends the per-minute budget of 2, **Then** confirm and grant rows are served first and no due inquiry is dropped. (E2E-P4.5-10, 05 §1 budget sentence)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.5-01 | H-XW + H-PAY | ABO worker `scheduled` for cron `* * * * *`, test clock at +2, +5, +10, and +20 minutes; Paymob stub order inquiry; grant step on the existing confirm/grant path over `VendorEntrypoint.grant` | Callback blocked → the +2 min sweep inquires → payment → grant; AL-03 [A3, FM-02] | FR-001 | User Story 1 |
| E2E-P4.5-02 | H-XW + H-PAY | `SELF.fetch` `POST /notify/paymob` on the billing hostname with the bad-HMAC fixture; ABO worker `scheduled` for cron `* * * * *` | Every callback fails HMAC → AL-02, and sweeps still confirm the payments [A23, FM-03, FM-18] | FR-002 | User Story 1 |
| E2E-P4.5-03 | H-XW + H-PAY | ABO worker `scheduled` for cron `* * * * *`; test clock past expiry, then day 3; Paymob stub inquiry; grant step uses the checkout snapshot | Unpaid past expiry → final inquiry → `expired`; payment on day 3 → `paid_late`, `late`, granted at the snapshot, AL-08 [G3] | FR-003 | User Story 1 |
| E2E-P4.5-04 | H-XW + H-PAY | `SELF.fetch` `POST /notify/paymob` parent-flag refund fixture; `reverse` work on ABO worker `scheduled` for cron `* * * * *`; `VendorEntrypoint.voidForReversal` over the `PLATFORM` binding; `SELF.fetch` `GET /v1/subscription` on the billing hostname | Parent-flag refund on the payment funding the active term → a reversal (never a payment), `end_current` → platform void → term reversed, queued held; AL-06; notice `terms_held` [A16, FR-43] | FR-004 | User Story 2 |
| E2E-P4.5-05 | H-XW + H-PAY | `SELF.fetch` `POST /notify/paymob` child-refund fixture, after the parent-flag reversal of the same payment; `VendorEntrypoint.voidForReversal` over the `PLATFORM` binding | Child-transaction refund → same result; the dedupe key prevents a double reversal [A16, SR-02] | FR-005 | User Story 2 |
| E2E-P4.5-06 | H-XW + H-PAY | `SELF.fetch` `POST /notify/paymob` refund fixture for a payment whose term has ended; ABO worker `scheduled` for cron `* * * * *` | Reversal of a payment whose term ended → effect `none`; recorded + AL-06 [A17] | FR-006 | User Story 2 |
| E2E-P4.5-07 | H-XW + H-PAY | `SELF.fetch` `POST /notify/paymob` full-refund fixture while the grant work row is granting or parked; `VendorEntrypoint.voidForReversal` over the `PLATFORM` binding; later grant step | Full reversal while the grant is granting or parked → tombstone; the pending grant is later `rejected voided`; its work row closes | FR-007 | User Story 2 |
| E2E-P4.5-08 | H-XW + H-PAY | `SELF.fetch` `POST /notify/paymob` partial-refund fixture; ABO worker `scheduled` for cron `* * * * *` | Partial refund → `review_partial`; no void; alert [X-01] | FR-008 | User Story 2 |
| E2E-P4.5-09 | H-XW + H-PAY | ABO worker `scheduled` for crons `0 * * * *` (day 3), `0 */6 * * *` (live term), and `0 6 * * *` (100-day-old payment); Paymob stub inquiry shows the refund | Lost refund callback found by the hourly tier (day 3), the 6-hour tier (live term) and the daily tier (100-day-old payment) [FR-82] | FR-009 | User Story 3 |
| E2E-P4.5-10 | H-XW + H-PAY | ABO worker `scheduled` for cron `* * * * *` with more than 2 due provider inquiries, including confirm and grant work rows | More than 2 due inquiries → confirm and grant rows served first; none dropped | FR-010 | User Story 4 |
| E2E-P4.5-11 | H-XW + H-PAY | `SELF.fetch` `POST /notify/paymob` refund fixture, then a provider inquiry on ABO worker `scheduled` that contradicts that callback | Inquiry contradicts a refund callback → reversal dismissed + finding | FR-011 | User Story 2 |
| E2E-P4.5-12 | H-XW + H-PAY | `SELF.fetch` `POST /notify/paymob` then a crash that answers 5xx or leaves the work row open; ABO worker `scheduled` for cron `* * * * *` with the test clock inside 2–20 minutes | ABO crashes after receiving a callback → the callback was answered with 5xx or the work row is open; the sweep inquires within 2–20 minutes [FM-01] | FR-012 | User Story 1 |

### 2.6 Edge Cases

- A blocked callback is found by the +2 minute inquiry. The payment is confirmed, the grant step runs, and AL-03 fires once. The sweep's early offsets are +2, +5, +10, and +20 minutes, then every 10 minutes until expiry. (E2E-P4.5-01, A3, 05 §1 minute row, 05 §2 row AL-03)
- Every callback fails HMAC. AL-02 fires. Sweeps still confirm the payments by inquiry. (E2E-P4.5-02, A23, FM-03, FM-18)
- The ABO crashes after receiving a callback. The callback was answered with 5xx, or the work row is open. The sweep inquires within 2–20 minutes. (E2E-P4.5-12, FM-01)
- An unpaid checkout past expiry gets a final inquiry and becomes `expired`. Expired and cancelled checkouts keep being inquired for 7 days. A payment in that window is `paid_late`, classification `late`, granted at the snapshot, and AL-08 fires once. With no payment, the shown state is Abandoned. `paid` or `paid_late` with the grant not yet applied shows Paid. (E2E-P4.5-03, 03 §5.1, 05 §2 row AL-08)
- A parent-flag refund and a child-transaction refund of the same payment are one reversal. The dedupe key blocks the second. The adapter does not record a payment. (E2E-P4.5-04, E2E-P4.5-05, A16, SR-02)
- A full reversal of the payment that funds the active or grace term uses effect `end_current`: the term ends with no grace, and queued terms become held. A full reversal of the payment that funds a queued or held term uses effect `remove_queued`: that term is removed and other terms stay. A full reversal of an ended term uses effect `none` and changes nothing else. (E2E-P4.5-04, E2E-P4.5-06, 03 §5.5, A17)
- A full reversal while the grant is granting or parked sends `voidForReversal` at once. The platform stores a tombstone. The pending grant is later `rejected` with `voided`, and the ABO closes that work row. (E2E-P4.5-07, 03 §5.2, 03 §5.5)
- A partial reversal uses effect `review_partial` and stays in review. This unit does not send `voidForReversal`. The platform would answer `partial` true with `rejected` and code `partial_void`, writing no `grant_void` row, no R2 void object, no coverage event, and no tombstone. The operator is alerted. There is no void. (E2E-P4.5-08, 03 §5.5, 04 §1.3 row voidForReversal, X-01)
- An inquiry that disagrees with a refund callback dismisses the reversal and raises a finding. No void is applied. (E2E-P4.5-11, 03 §5.5)
- A reversal can be recorded against a withheld payment, and against a granted payment. A full reversal recorded before apply follows the tombstone edge. (03 §5.2)
- `source` `vendor` is rejected at launch. (03 §2.7, X-01)
- A transient answer on `voidForReversal` leaves the reversal `applying` and the `reverse` row retries. `conflict` or `rejected` parks that row. Operator retry of a parked row is not this unit. (03 §5.5)
- More than 2 due inquiries still leave every inquiry due. Confirm and grant work rows are served first. The shared per-minute budget is 2. (E2E-P4.5-10, 05 §1 budget sentence)
- A lost refund callback is found within an hour during the payment's first 7 days or while its grant is unapplied, within 6 hours while it funds an active, grace, queued, or held term, and within a week otherwise, up to 180 days. (E2E-P4.5-09, A16, 05 §1)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The minute cron runs checkout sweeps at +2, +5, +10, and +20 minutes, then every 10 minutes until expiry. A blocked callback is found by the +2 minute inquiry. That inquiry confirms the payment, the grant step runs, and AL-03 fires once because the payment was confirmed with no verified callback. (05 §1 minute row, 05 §2 row AL-03, 05 §8 row A3, Implements, E2E-P4.5-01)
- **FR-002**: When every callback fails HMAC, AL-02 fires within 15 minutes, and the sweeps still confirm the payments by inquiry. (05 §8 row A23, Implements, E2E-P4.5-02)
- **FR-003**: An open checkout that is unpaid after expiry gets a final inquiry and becomes `expired`. Expired and cancelled checkouts are inquired for 7 days. A payment confirmed in that window moves the checkout to `paid_late`, sets classification `late`, is granted at the checkout snapshot, and raises AL-08 once. AL-08 is the late payment on an expired or cancelled checkout. With no payment, `expired` shows Abandoned. `paid_late` shows Paid while the grant is not yet applied. (03 §5.1, 03 §5.2 classification `late`, 05 §1 minute row, 05 §2 row AL-08, Implements, E2E-P4.5-03)
- **FR-004**: A parent-flag refund on the payment that funds the active term is recorded as a reversal and not as a payment. The effect is `end_current`. A `reverse` work row calls signed `voidForReversal` with `partial` false. The platform voids the term with no grace and holds queued terms. AL-06 fires once. The frozen `GET /v1/subscription` shows notice `terms_held`. The same call names the paid `grant_id`; the platform follows `origin_grant_id` to the term that now carries that value. (03 §5.5, 04 §1.3 row voidForReversal, 05 §2 row AL-06, 05 §8 row A16, Implements, E2E-P4.5-04)
- **FR-005**: A child-transaction refund of that same payment has the same result as FR-004. The dedupe key prevents a second reversal. (05 §8 row A16, Implements, E2E-P4.5-05)
- **FR-006**: A reversal of a payment whose term has ended has effect `none`. It is recorded, AL-06 fires once, and nothing in the service changes. `voidForReversal` is not sent for effect `none`. (03 §5.5, 05 §2 row AL-06, 05 §8 row A17, Implements, E2E-P4.5-06)
- **FR-007**: A full reversal that arrives while the grant is `granting` or `parked` has effect `tombstone` and sends `voidForReversal` at once with `partial` false. The platform stores the void as a tombstone. The pending grant is later `rejected` with `voided`, and the ABO closes that grant work row. The same edge is the payment lifecycle move from `granting` to `reversed` before apply. (03 §5.2, 03 §5.5, 04 §1.3 row voidForReversal, Implements, E2E-P4.5-07)
- **FR-008**: A partial refund has effect `review_partial` and moves to review, not to applying. This unit does not send `voidForReversal`. Platform action at launch is none. A call with required boolean `partial` true would be `rejected` with code `partial_void` and would write no `grant_void` row, no R2 void object, no coverage event, and no tombstone. The operator is alerted. There is no void. (03 §5.5, 04 §1.3 row voidForReversal, Implements, E2E-P4.5-08)
- **FR-009**: A lost refund callback is found by reversal inquiry: hourly for every payment in its first 7 days or whose grant is not yet applied (covered on day 3); every 6 hours for every payment that funds an active, grace, queued, or held term (covered for a live term); daily for all other paid transactions up to 180 days old, one seventh each day, spread across the day (covered for a 100-day-old payment). A found refund is recorded as a reversal with `detected_via` `inquiry`, not as a payment. (05 §1 hourly, 6-hourly, and daily rows, 05 §8 row A16, Implements, E2E-P4.5-09)
- **FR-010**: Sweeps and work rows share one per-minute provider-inquiry budget of 2. When more than 2 inquiries are due, confirmation and grant work rows are served first. No due inquiry is dropped. (05 §1 budget sentence, Implements, E2E-P4.5-10)
- **FR-011**: When an inquiry disagrees with a refund callback, the reversal moves from detected to dismissed and a finding is raised. It is not confirmed and no void is applied. (03 §5.5, Implements, E2E-P4.5-11)
- **FR-012**: If the ABO crashes after receiving a callback, and the callback was answered with 5xx or the work row is open, the sweep inquires within 2–20 minutes. (05 §1 minute row, Implements, E2E-P4.5-12)
- **FR-013**: Each reversal is an append-only `reversal` fact: `reversal_id`, `reference`, `payment_id`, `source`, `kind`, `amount_minor`, `cumulative_reversed_minor`, `is_full`, `detected_via`, `recorded_by`, `evidence_sha256`, and `effect`. `source` is `provider` for a notification or inquiry refund. `source` `vendor` is rejected at launch. `detected_via` is `notification` or `inquiry` for this unit. `kind` for these refunds is `refund`. `is_full` is set on the cumulative amount. A `reversal_outcome` row records `reversal_id`, `result`, `receipt`, and `at` when a void returns a receipt. AL-06 fires once on every reversal detected or recorded. Recording a reversal makes the frozen subscription response include `reversal_recorded`. Effect `remove_queued` applies when a full reversal's payment funds a queued or held term: `voidForReversal` removes that term and leaves other terms unchanged. A withheld payment can have a reversal recorded. A granted payment can have a reversal recorded. (03 §2.7, 03 §5.2, 03 §5.5, 05 §2 row AL-06, Implements)
- **FR-014**: `voidForReversal` is the consumed platform method. This unit sends `contract_version`, the paid `grant_id`, `reversal_id`, `reason`, `evidence_sha256`, boolean `partial`, `abo_kid`, and `abo_signature`, signed with the current ABO `kid`. `partial` false is a full void and returns a receipt, or `already_applied` with the original receipt when the same `reversal_id` repeats with the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false. A difference in those four is `conflict` and changes nothing. A missing or non-boolean `partial` is `rejected` with `partial_invalid` and writes nothing. A transient answer leaves the reversal `applying` and retries the `reverse` row. `conflict` or `rejected` parks that row. The tombstone rule stays the platform's: a void stored before the grant is applied makes the later grant `rejected` with `voided`. (04 §1.3 row voidForReversal, 03 §5.5, Consumes P3.7)

### 3.2 Key Entities

- **`reversal`**: Append-only fact this unit writes. Fields are `reversal_id`, `reference`, `payment_id`, `source` (`provider`, `operator`, `vendor`; `vendor` is rejected at launch), `kind` (`refund`, `void`, `chargeback`, `unknown`), `amount_minor`, `cumulative_reversed_minor`, `is_full`, `detected_via` (`notification`, `inquiry`, `payout`, `manual`), `recorded_by`, `evidence_sha256`, and `effect` from 03 §5.5. This unit writes `source` `provider` and `detected_via` `notification` or `inquiry`. (03 §2.7, 03 §5.5)
- **`reversal_outcome`**: Append-only. `reversal_id`, `result`, `receipt`, `at`. Written when a void returns a receipt. (03 §2.7)
- **`reverse` work row**: The work row this unit inserts when a confirmed reversal's effect needs `voidForReversal` (`tombstone`, `end_current`, or `remove_queued`). The minute cron runs that due row. It is not inserted for effect `none`, for a dismissed reversal, or for a partial reversal left in review. (Implements, 03 §5.5, 05 §1 minute row)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: A clinic whose Paymob callback is blocked, rejected, or interrupted still gets the paid term from the sweep. A refund of that payment reverses or records the term under the effect rules, and the clinic's subscription read shows the frozen notices. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. Live entries are the ABO worker `scheduled` handler (crons `* * * * *`, `0 * * * *`, `0 */6 * * *`, and `0 6 * * *`), `SELF.fetch` `POST /notify/paymob` and `GET /v1/subscription` on the billing hostname, and `VendorEntrypoint.voidForReversal` over the real platform service binding. The grant step reached by a sweep is the consumed P4.4 path. H-XW runs that platform worker from source. H-PAY stands in for Paymob, including the parent-flag refund, child refund, and bad-HMAC fixtures. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: `reversal` and `reversal_outcome` are append-only. One refund does not become two reversals. `voidForReversal` stays idempotent by `reversal_id` on the platform. The subscription and payments responses stay the frozen P4.4 responses. AL-03, AL-06, and AL-08 go out through the existing alert path. (03 §2.7, 04 §1.3 row voidForReversal, 05 §2 rows AL-03, AL-06, AL-08)
- **Failure Handling**: A blocked callback, an HMAC failure on every callback, and a crash after the callback are recovered by the sweep (FM-02, FM-03, FM-18, FM-01). A partial refund does not void. An inquiry that contradicts a callback dismisses the reversal and raises a finding. A transient void retries; `conflict` or `rejected` parks the `reverse` row. Over-budget inquiries stay due, with confirm and grant rows first. (E2E-P4.5-01, E2E-P4.5-02, E2E-P4.5-08, E2E-P4.5-10, E2E-P4.5-11, E2E-P4.5-12, 03 §5.5)

## 5. Out of Scope

- Manual chargeback (→ P4.7); `unrecorded_reversal` from payouts (→ P4.10).
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P4.4's subscription and payments responses stay as frozen, including notices `reversal_recorded` and `terms_held` when their conditions hold. CP-C stays the P4.4 purchase path. P3.7's void, release, and listing methods and the tombstone rule stay as frozen. This unit calls `voidForReversal`; it does not change that method, `releaseHeld`, or `listGrantsForVoid`.
- No module that no test-plan row reaches (rule S8). The minute sweep is reached by E2E-P4.5-01, E2E-P4.5-03, E2E-P4.5-10, and E2E-P4.5-12. HMAC-failed callbacks plus sweeps are reached by E2E-P4.5-02. Parent-flag and child refunds, `voidForReversal`, and `GET /v1/subscription` are reached by E2E-P4.5-04 and E2E-P4.5-05. Effect `none` is reached by E2E-P4.5-06. The tombstone path is reached by E2E-P4.5-07. Partial review is reached by E2E-P4.5-08. The hourly, 6-hour, and daily tiers are reached by E2E-P4.5-09. Dismissal is reached by E2E-P4.5-11.
- No S9 path owned by a later unit. Enrollment removal stays with P3.2. `/control/entitle` is not the admission path. Entitlement, plan, and invoice tables and `/control/*` removal stay with P3.10. Operator cancel of an open checkout stays with P4.6. Operator retry of a parked `reverse` row stays with P4.6. Manual chargeback stays with P4.7. `detected_via` `payout` and `unrecorded_reversal` stay with P4.10. The other jobs on these crons stay with their owners: coverage-event read and fact export (P4.2, P4.1), alert send (P4.1), signing-key check (P4.4), issuer-key and credential comparison (P4.11), reconciliation, digest, R2 lock check, and key-expiry check (P4.10, P4.11).
- No second codebase. The Codebase cell is `abo`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.5-01 through E2E-P4.5-12 pass in H-XW + H-PAY.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 default is named by this unit's Read or Implements.
- No S9 transitional path is named for this unit. Enrollment removal stays with P3.2. `/control/*` removal stays with P3.10 (rule S9).
- The shared per-minute provider-inquiry budget is 2. Paymob's numeric inquiry limit was not observed (P4.3 R-2). This unit does not add a spike, a config surface, or a second cap. E2E-P4.5-10 schedules more than 2 due provider inquiries.
