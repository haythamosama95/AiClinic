# Feature Specification: Grant pipeline to the platform: purchase to AI on

**Feature Branch**: `ai/079-abo-p4-4-grant-pipeline-to-platform-purchase`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P4.4 — Grant pipeline to the platform: purchase to AI on

## 1. Unit Contract

**Implements** — Read: 03 §2.8; 02 §1.5 (first diagram); 04 §1.2; 04 §1.3 rows grant, listServiceKeys; 04 §1.4 (field table only); 04 §1.6; 02 §6 rows K-3, K-4; 05 §2 rows AL-04, AL-07, AL-23; 04 §2.2 rows `GET /v1/subscription`, `GET /v1/payments`.

- Grant step (envelope from the payment and checkout snapshot, `grant_id = H(payment_id)`, signed with the current ABO `kid` on each attempt) → platform `grant`; outcomes: applied/already_applied → `grant_outcome` + receipt checked against the configured platform public keys; `transient` → backoff forever; `conflict`/`rejected` → parked + AL-07; AL-04 after 5 min of transient or unreachable; AL-23 self-check at isolate start and hourly (`listServiceKeys`), pausing grant/reverse work; shown state Active; `GET /v1/subscription` (subscription ref, snapshot, notices closed set `duplicate_payment`, `late_payment_honoured`, `payment_withheld`, `reversal_recorded`, `terms_held`); `GET /v1/payments` (cursor pages).

**Freezes** — Subscription and payments responses. CP-C.

**Consumes** — P3.4: admission answer (reservation, `term_id`, snapshot, band); clinic denial codes of 04 §4.2. CP-B. P4.3: the unit row states no Outputs / freezes line.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Turn a paid checkout into a live term (Priority: P1)

A clinic admin pays for 1, 3, or 12 months. The ABO builds one paid grant from that payment and its checkout snapshot, signs it with the current ABO `kid`, and calls platform `grant`. An applied grant records `grant_outcome` and the platform receipt. An issuer AI token then completes `POST /v1/requests` against that term. The checkout shows Active, and the payment appears on `GET /v1/payments`. While the platform answers `transient`, or the outcome is lost after the call, the grant row retries. A `rejected` result parks the row.

**Why this priority**: The signing-key check and the clinic reads depend on a paid grant that can become one platform term. CP-C is this path.

**Independent Test**: E2E-P4.4-01, E2E-P4.4-02, E2E-P4.4-03, and E2E-P4.4-04 in harnesses H-XW and H-PAY.

**Acceptance Scenarios**:

1. **Given** a checkout paid through the Paymob stub, **When** the grant step runs for a term of 1, 3, or 12 months, **Then** the platform term is active with full allowance, an issuer AI token's `POST /v1/requests` completes, the checkout shows Active, and the payment is listed by `GET /v1/payments`. (E2E-P4.4-01, 02 §1.5 first diagram, 04 §1.3 row grant, 04 §1.4 duration row)
2. **Given** the platform answers `transient` for 4 days on the test clock, **When** the grant row retries, **Then** retries stay at or under 15 minutes, AL-04 repeats hourly, and a later `applied` starts the term at activation. (E2E-P4.4-02, 04 §1.2, 05 §2 row AL-04)
3. **Given** the platform answers `rejected`, **When** the grant step records that result, **Then** the work row is parked, AL-07 fires, and the row is not retried automatically. (E2E-P4.4-03, 04 §1.2, 05 §2 row AL-07)
4. **Given** the grant call succeeded and the outcome was lost before it was stored, **When** the row retries, **Then** the platform answers `already_applied` with the same receipt and there is one term. (E2E-P4.4-04, 04 §1.2, 04 §1.6)

### 2.2 User Story 2 - Pause grants until the ABO key is active, and accept a rotated platform receipt key (Priority: P2)

The ABO asks the platform which service keys are listed. If its signing `kid` is not active, grant and reverse work pause and AL-23 fires. After the `kid` is registered, grant work resumes. When the platform signs receipts with a second `kid` already in the ABO configuration, those receipts still verify and grants continue.

**Why this priority**: User Story 1 signs with the current ABO `kid` and stores a platform receipt. This story is the check that stops a grant the platform cannot accept, and the receipt-key rotation around a grant that does apply.

**Independent Test**: E2E-P4.4-06 and E2E-P4.4-07 in harnesses H-XW and H-PAY.

**Acceptance Scenarios**:

1. **Given** the ABO signing `kid` is not registered on the platform, **When** the isolate starts or the hourly check runs, **Then** grant work is paused and not parked, AL-23 fires, and after the `kid` is registered the grant work resumes. (E2E-P4.4-06, 04 §1.3 row listServiceKeys, 05 §2 row AL-23, 02 §6 row K-4)
2. **Given** the ABO configuration already holds a second platform `kid`, **When** the platform switches receipt signing to that `kid`, **Then** receipts are accepted and grants continue. (E2E-P4.4-07, 02 §6 row K-3, 04 §1.6)

### 2.3 User Story 3 - Read subscription, payments, and Active without polling (Priority: P3)

A second paid grant queues a term on the platform, and `GET /v1/subscription` shows `duplicate_payment`. A clinic that never calls the API after checkout creation is still provisioned; a later `GET /v1/checkouts?open=1` shows Active. `GET /v1/payments` returns cursor pages, and another tenant's token sees none of those payments.

**Why this priority**: User Story 1 has already applied one grant and listed one payment. This story is the subscription notice, the unattended checkout, and payment paging.

**Independent Test**: E2E-P4.4-05, E2E-P4.4-08, and E2E-P4.4-09 in harnesses H-XW and H-PAY. Earlier H-ABO, H-PAY, and H-XW suites stay green, and E2E-P4.4-01 through E2E-P4.4-04, E2E-P4.4-06, and E2E-P4.4-07 still pass.

**Acceptance Scenarios**:

1. **Given** two payments for the same clinic, **When** both grants have run, **Then** the second term is queued on the platform and `GET /v1/subscription` shows `duplicate_payment`. (E2E-P4.4-05, 04 §2.2 row `GET /v1/subscription`, 04 §1.4 placement row)
2. **Given** a checkout that was created and paid, **When** no clinic API call is made after creation, **Then** the clinic is still provisioned, and a later `GET /v1/checkouts?open=1` shows Active. (E2E-P4.4-08, Implements)
3. **Given** tenant A has payments, **When** tenant A calls `GET /v1/payments` with a cursor and tenant B calls the same route, **Then** the pages advance by cursor and tenant B sees none of A's payments. (E2E-P4.4-09, 04 §2.2 row `GET /v1/payments?cursor=`)

### 2.4 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.4-01 | H-XW + H-PAY | `SELF.fetch` `POST /v1/checkouts` and `POST /notify/paymob` on the ABO worker `fetch`, billing hostname; grant step on inline `waitUntil` and `runScheduled` for cron `* * * * *`; `VendorEntrypoint.grant` over the `PLATFORM` service binding; issuer AI token then `POST /v1/requests` on the platform worker `fetch`; `GET /v1/checkouts/{id}` and `GET /v1/payments` | Checkout → callback → confirm → grant → platform term active with full allowance → issuer AI token → `POST /v1/requests` completes; the checkout shows Active; the payment is in `/v1/payments`; run for 1, 3 and 12 months [G1, FR-12] | FR-001 | User Story 1 |
| E2E-P4.4-02 | H-XW + H-PAY | Grant step on inline `waitUntil` and `runScheduled` for crons `* * * * *` and `0 * * * *`, calling `VendorEntrypoint.grant`; ABO test clock | Platform answers `transient` for 4 days (test clock) → retries at ≤ 15 min; AL-04 hourly; then applied; term starts at activation [I-2] | FR-002 | User Story 1 |
| E2E-P4.4-03 | H-XW + H-PAY | Grant step on inline `waitUntil` or `runScheduled` for cron `* * * * *`, calling `VendorEntrypoint.grant` | Platform `rejected` → parked + AL-07; never retried automatically | FR-003 | User Story 1 |
| E2E-P4.4-04 | H-XW + H-PAY | Grant step on inline `waitUntil` or `runScheduled` for cron `* * * * *`, calling `VendorEntrypoint.grant`; the outcome is dropped after the call returns | Outcome lost after the call (crash) → retry answers `already_applied` with the same receipt; one term [FM-13 partial] | FR-004 | User Story 1 |
| E2E-P4.4-05 | H-XW + H-PAY | Grant step for two payments via `VendorEntrypoint.grant`; `SELF.fetch` `GET /v1/subscription` on the ABO worker `fetch`, billing hostname | Two payments → the second term is queued on the platform; `/v1/subscription` shows `duplicate_payment` | FR-005 | User Story 3 |
| E2E-P4.4-06 | H-XW + H-PAY | `VendorEntrypoint.listServiceKeys` over the `PLATFORM` service binding at isolate start and on `runScheduled` for cron `0 * * * *`; grant step while the `kid` is unregistered, then after registration | The ABO `kid` is not registered → grant work paused (not parked) + AL-23; after registration it resumes | FR-006 | User Story 2 |
| E2E-P4.4-07 | H-XW + H-PAY | Grant step calling `VendorEntrypoint.grant`; receipt check against the ABO's configured platform public keys | The platform switches to a second configured `kid` → receipts accepted; grants continue | FR-007 | User Story 2 |
| E2E-P4.4-08 | H-XW + H-PAY | `SELF.fetch` `POST /v1/checkouts` and `POST /notify/paymob`, then the grant step, with no clinic GET until `SELF.fetch` `GET /v1/checkouts?open=1` on the billing hostname | No clinic API call after checkout creation → still provisioned; a later `?open=1` shows Active | FR-008 | User Story 3 |
| E2E-P4.4-09 | H-XW + H-PAY | `SELF.fetch` `GET /v1/payments?cursor=` on the ABO worker `fetch`, billing hostname, with tenant A and tenant B billing tokens | `/v1/payments` cursor pages; tenant B sees none of A's payments [A36 ABO half] | FR-009 | User Story 3 |

### 2.5 Edge Cases

- `transient` leaves the grant row open and retries with backoff forever. The interval stays at or under 15 minutes. AL-04 fires after 5 minutes of `transient` or of the platform being unreachable, and repeats hourly while that holds. The term starts at activation. The harness advances the ABO test clock. (E2E-P4.4-02, 04 §1.2, 05 §2 row AL-04, Implements)
- `conflict` and `rejected` park the work row and raise AL-07. The row is not retried automatically. AL-07 repeats hourly while the row stays parked. (E2E-P4.4-03, 04 §1.2, 05 §2 row AL-07, Implements)
- A crash after `grant` returns drops the outcome. The retry is `already_applied` and returns the original receipt. One term exists. (E2E-P4.4-04, 04 §1.2, 04 §1.6)
- The ABO signing `kid` is missing, not `active`, or expired on `listServiceKeys`: grant and reverse work pause, the rows are not parked, and AL-23 repeats hourly until the check passes. An unknown `kid` on a grant the platform does receive answers `transient`. A revoked `kid` makes those envelopes `rejected`. (E2E-P4.4-06, 04 §1.3 row listServiceKeys, 02 §6 row K-4, 05 §2 row AL-23)
- Receipt verification uses the platform public keys in the ABO configuration. The next platform `kid` is added to that configuration before the platform switches signing. (E2E-P4.4-07, 02 §6 row K-3, 04 §1.6)
- A paid `evidence.approvals` list shorter than one element is `rejected` with code `approvals_required`. The paid purchase path sends the one operation-object element from the amended 04 §1.4 evidence row, so the grant is not refused for that code. (04 §1.4 evidence row, E2E-P4.4-01)
- Tenant B's billing token does not receive tenant A's payment pages. (E2E-P4.4-09, 04 §2.2 row `GET /v1/payments?cursor=`)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The grant step builds one paid envelope from the payment and the checkout snapshot and calls platform `grant` over the service binding. `grant_id` is `H(payment_id)` and is the hex SHA-256 the envelope field requires. The call sends `abo_kid` and `abo_signature`, and each attempt signs with the ABO's current `kid`. The paid envelope uses `kind` `term`, `placement` `queue`, `source.kind` `paid`, and `source.ref` equal to the ABO `payment_id` (not a provider id). `operator_email` and `reason` are omitted for `paid`. `duration` is `month` with count 1, 3, or 12. `paid_at` is the provider's payment time. `plan` is `{plan_id, plan_version}` from the checkout snapshot. `allowance_credits` is an integer ≥ 1 from that snapshot, and the applied term is active with that full allowance. `grace` for `paid` has `days` ≤ `max_paid_grace_days` (7) and `cap_rule` `proportional`. `org_id` is the tenant UUID. `evidence.content_sha256` is the hash of the ABO payment fact and its evidence. `evidence.approvals` is a one-element list. That element is the §1.5 operation object `{op, params, actor_email, issued_at, nonce, contract_version}`: `op` is `grant`, `params` is that same envelope with `evidence.approvals` omitted, `actor_email` is `""`, `issued_at` is `paid_at`, `nonce` is `grant_id`, and `contract_version` is the envelope's `contract_version`. The platform counts that element toward the minimum of one and does not apply the §1.5 WebAuthn checks; the ABO signature is still verified. A shorter list is `rejected` with code `approvals_required` and an empty `detail`. On `applied`, the ABO records `grant_outcome` only after the receipt verifies against the configured platform public keys. The receipt is the §1.6 object, signed by the platform key, and both sides store it. The checkout shown state is Active. The payment is returned by `GET /v1/payments`. An issuer AI token's `POST /v1/requests` then completes against the admitted term. The same path runs for 1, 3, and 12 months. (03 §2.8, 02 §1.5 first diagram, 04 §1.2, 04 §1.3 row grant, 04 §1.4 field table, 04 §1.6, Implements, E2E-P4.4-01)
- **FR-002**: `transient` changes nothing on the platform and the grant row backs off forever. Retries stay at or under 15 minutes. AL-04 fires when `transient` or an unreachable platform has lasted 5 minutes, and repeats hourly while that continues. A later `applied` starts the term at activation. (04 §1.2, 05 §2 row AL-04, Implements, E2E-P4.4-02)
- **FR-003**: `conflict` and `rejected` park the grant work row and raise AL-07. The row is not retried automatically. AL-07 repeats hourly while the condition holds. (04 §1.2, 05 §2 row AL-07, Implements, E2E-P4.4-03)
- **FR-004**: If the outcome is lost after `grant` returns, the retry is `already_applied` for the same `grant_id` and the same content hash, and the original receipt is returned. The ABO records that outcome. One term exists. (04 §1.2, 04 §1.3 row grant, 04 §1.6, E2E-P4.4-04)
- **FR-005**: `GET /v1/subscription` returns `subscription_ref`, the snapshot (§1.7), and commercial notices. `notices` is an array of code strings from this closed set: `duplicate_payment` when a payment of this tenant is classified `likely_duplicate`; `late_payment_honoured` when one is `late`; `payment_withheld` when a payment disposition is `withheld_mismatch`; `reversal_recorded` when a reversal is recorded for this tenant; `terms_held` when `snapshot.held_count` > 0. Two payments leave the second term queued on the platform, and the response shows `duplicate_payment`. Returning `reversal_recorded` and `terms_held` does not implement reversal processing. (04 §2.2 row `GET /v1/subscription`, 04 §1.4 placement row, Implements, E2E-P4.4-05)
- **FR-006**: At isolate start and on the hourly cron, the ABO calls `listServiceKeys`. A successful call is `ok`, and `detail` is the JSON text of `{kid, status, not_before, not_after}` for every `service_key` row. The ABO requires its signing `kid` to be listed with `status` `active` and not expired. Otherwise it pauses `grant` and `reverse` work, does not park those rows, and raises AL-23, which repeats hourly while the pause holds. After the `kid` is registered and the check passes, paused grant work resumes. Each resumed attempt signs with the current ABO `kid`. (04 §1.2, 04 §1.3 row listServiceKeys, 02 §6 row K-4, 05 §2 row AL-23, Implements, E2E-P4.4-06)
- **FR-007**: The ABO checks each platform receipt against the platform public keys in its configuration. Routine rotation adds the next platform `kid` to that configuration first; the platform then switches signing. After the switch, receipts verify and grants continue. (02 §6 row K-3, 04 §1.6, Implements, E2E-P4.4-07)
- **FR-008**: Provisioning does not wait for a clinic API call after checkout creation. The grant step still runs. A later `GET /v1/checkouts?open=1` shows that checkout as Active. (Implements, E2E-P4.4-08)
- **FR-009**: `GET /v1/payments?cursor=` returns pages of `reference`, `paid_at`, `amount_minor`, `currency`, offer name and version, term covered, `classification`, and reversals. The cursor walks those pages. A token for another tenant sees none of this tenant's payments. (04 §2.2 row `GET /v1/payments?cursor=`, Implements, E2E-P4.4-09)
- **FR-010**: Every payment with disposition `grant` has exactly one `grant_request`. The paid request stores `source_kind` `paid`, `source_ref` the payment, the canonical envelope, and `envelope_sha256`. `grant_outcome` records `applied`, `already_applied`, `conflict`, or `rejected`, and for an accepted paid attempt stores the `abo_kid` and `abo_signature` used, the receipt, `term_ids`, and `at`. `transient` is not a `grant_outcome` result. (03 §2.8, 04 §1.2, FR-001, FR-003, FR-004)

### 3.2 Key Entities

- **`grant_request`**: Append-only. `grant_id` (§7), `org_id`, `source_kind` (`paid` for this unit), `source_ref` (the payment), `envelope` (canonical JSON, 04 §1.4), `envelope_sha256`. `assertion` is complimentary only and is not written for a paid purchase. One row for each payment whose disposition is `grant`. (03 §2.8)
- **`grant_outcome`**: Append-only. `grant_id`, `result` (`applied`, `already_applied`, `conflict`, `rejected`), `abo_kid` and `abo_signature` of the accepted paid attempt, `receipt` (platform-signed), `term_ids`, `at`. Each attempt signs with the current ABO key, so a key rotation does not create another request. (03 §2.8, 04 §1.6)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: A clinic that pays receives one platform term and can complete an AI request on that term. Subscription and payment reads are for that clinic's administrators. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. Live entries are the ABO worker `fetch` on the billing hostname (`POST /v1/checkouts`, `POST /notify/paymob`, `GET /v1/checkouts/{id}`, `GET /v1/checkouts?open=1`, `GET /v1/subscription`, `GET /v1/payments`), the ABO worker `scheduled` handler (crons `* * * * *` and `0 * * * *`), `VendorEntrypoint.grant` and `VendorEntrypoint.listServiceKeys` over the real platform service binding, and `POST /v1/requests` on the platform worker. H-XW runs that platform worker from source. H-PAY stands in for Paymob. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: Paid grants are one `grant_request` per payment, signed with the current ABO `kid`, and accepted only with a receipt that verifies against the configured platform public keys. `grant_outcome` stores that receipt. Subscription and payment reads use the billing token's tenant. AL-04, AL-07, and AL-23 go out through the existing alert path. (03 §2.8, 04 §1.6, 05 §2 rows AL-04, AL-07, AL-23)
- **Failure Handling**: `transient` or an unreachable platform retries with backoff and raises AL-04 after 5 minutes. `conflict` and `rejected` park the row and raise AL-07. A lost outcome retries as `already_applied`. A signing `kid` that is not active pauses grant and reverse work and raises AL-23. (E2E-P4.4-02, E2E-P4.4-03, E2E-P4.4-04, E2E-P4.4-06)

## 5. Out of Scope

- Reversal processing (→ P4.5). `GET /v1/subscription` still returns `reversal_recorded` and `terms_held` when the amended 04 §2.2 row's conditions hold. Operator retry (→ P4.6).
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P3.4's admission answer (reservation, `term_id`, snapshot, band) and clinic denial codes of 04 §4.2 stay as frozen. P4.3 publishes no Outputs / freezes line. This unit calls `grant` and `listServiceKeys`; it does not change those methods. The paid `approvals` element is the amended 04 §1.4 evidence row.
- No module that no test-plan row reaches (rule S8). `VendorEntrypoint.grant` is reached by E2E-P4.4-01. `listServiceKeys` is reached by E2E-P4.4-06. `GET /v1/subscription` is reached by E2E-P4.4-05. `GET /v1/payments` is reached by E2E-P4.4-01 and E2E-P4.4-09. `GET /v1/checkouts?open=1` is reached by E2E-P4.4-08. `POST /v1/requests` is reached by E2E-P4.4-01.
- No S9 path owned by a later unit. Enrollment removal stays with P3.2. `/control/entitle` is not the admission path. Entitlement, plan, and invoice tables and `/control/*` removal stay with P3.10. Complimentary and transfer grants stay with P4.8. The `grant_request` for a released withheld payment stays with P4.7. Reversal processing, sweeps, expiry, and reversals stay with P4.5. This unit still returns the subscription notice codes `reversal_recorded` and `terms_held` when the amended 04 §2.2 row's conditions hold. Operator retry of parked rows stays with P4.6.
- No second codebase. The Codebase cell is `abo`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.4-01 through E2E-P4.4-09 pass in H-XW + H-PAY.
- **SC-002**: Every earlier suite stays green (rule S2).
- **SC-003**: CP-C holds: purchase → callback → inquiry → grant → AI on runs across the real ABO and platform workers with the Paymob stub (local A1).

## 7. Assumptions

- No §6 default is named by this unit's Read or Implements.
- Enrollment removal stays with P3.2. This unit admits through the frozen `grant` entrypoint rather than `/control/entitle` (P3.4). Entitlement, plan, and invoice tables and `/control/*` removal stay with P3.10 (rule S9).
