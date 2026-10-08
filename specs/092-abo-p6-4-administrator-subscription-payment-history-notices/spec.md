# Feature Specification: Administrator subscription, payment history and commercial notices

**Feature Branch**: `ai/092-abo-p6-4-administrator-subscription-payment-history-notices`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P6.4 — Administrator subscription, payment history and commercial notices

## 1. Unit Contract

**Implements** — Read: 04 §2.2 rows `/v1/subscription`, `/v1/payments`; 04 §3.1 row `get_ai_billing_status`; 04 §3.2 (notice table); 05 §8 rows A6, A15, A16.

- subscription page (`get_ai_billing_status` + `/v1/subscription`: plan, dates, allowance, queued/held counts, subscription ref, commercial notices); payment history with cursor paging, classification and reversals; "contact support" with the subscription reference.

**Freezes** — None. The unit publishes no Outputs / freezes line.

**Consumes** — P6.3 Outputs: CP-E.

**Open questions relied on** — OQ-6: "Default: no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL)."

**Spikes** — None.

## Clarifications

### Session 2026-10-08

- Q: How does the subscription page request the next payment-history page? → A: An explicit next-page control. The first request omits `cursor`. When `has_more` is true, that control requests `GET /v1/payments` with `cursor` set to the previous response's `next_cursor`, and the page appends that page. `[implementation choice — no §citation]`
- Q: How do the H-FL tests on H-FS arrange a duplicate payment, a refund, a late payment, a withheld mismatch, and 30 payments? → A: The Dart fullstack tests arrange that state through the existing H-FS workers and Paymob stub, using fixtures and flows earlier units already ship. The desktop test then only opens the subscription page and reads. It does not insert payment or reversal rows. `TEST_CLOCK` stays unset on the H-FS ABO config. The test does not wait out the 10-checkouts-per-tenant-per-hour limit or the 30-minute `expires_at`. A duplicate, a refund, and a withheld mismatch use the fixture flows earlier units already ship (second payment at the same `opened_with_coverage_through`, a refund fixture, an amount mismatch). A late payment (E2E-P6.4-03) is one open checkout whose `checkout_status.state` the arrange step sets to `cancelled` in the local ABO D1, then the Paymob success fixture. Confirmation classifies that payment `late` because the checkout is `cancelled`. Thirty payments (E2E-P6.4-04) are three batches of 10. Each payment is its own `POST /v1/checkouts` (`client_request_id` unique per checkout) and a Paymob success fixture whose transaction id and order id are that checkout's, so confirmation inserts a new payment. After each batch of 10, and before the next `POST /v1/checkouts`, the arrange step sets `fact_log.created_at` on those checkout facts (`"table" = 'checkout'`, `key` = `checkout_id`) in the local ABO D1 to more than one hour before wall-clock now. The hourly count then sees fewer than 10 checkouts, and the next batch is accepted. `[implementation choice — no §citation]`
- Q: Where do the new desktop widgets and the five E2E tests live? → A: Commercial notices and payment history are widgets under `frontend/lib/features/ai/billing/`, composed by `AdministratorBillingPage`. E2E-P6.4-01 through E2E-P6.4-05 are one `fullstack`-tagged Dart file under `frontend/test/integration/`. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - An administrator reads the subscription and its commercial notices (Priority: P1)

An administrator opens the subscription page from the live desktop shell. The page calls `get_ai_billing_status(p_contract_version)` and `GET /v1/subscription`. It shows the plan, the dates, the allowance, the queued and held counts, the subscription reference, and the commercial notices. It shows "contact support" with that subscription reference.

**Why this priority**: Payment history and the other-clinic check use this page. The duplicate, refund, late, and withheld notices are read here.

**Independent Test**: E2E-P6.4-01, E2E-P6.4-02, and E2E-P6.4-03 in harness H-FL on H-FS.

**Acceptance Scenarios**:

1. **Given** two payments, the second `likely_duplicate`, stacking as the next term and raising a `duplicate_payment` notice (05 §8 A6), **When** the administrator opens the subscription page and payment history, **Then** the page shows the `duplicate_payment` notice, history shows both payments, the second is `likely_duplicate`, and the queued count is 1. (E2E-P6.4-01) [A6]
2. **Given** a refund folded into a reversal, never a payment (05 §8 A16), **When** the administrator opens the subscription page and payment history, **Then** the page shows `reversal_recorded` and `terms_held`, history shows the reversal, and status is `ended_reversed`. (E2E-P6.4-02) [A16]
3. **Given** a late payment, and a withheld mismatch, **When** the administrator reads commercial notices, **Then** the late payment shows `late_payment_honoured` and the withheld mismatch shows `payment_withheld`. (E2E-P6.4-03)

### 2.2 User Story 2 - An administrator pages payment history inside one clinic (Priority: P2)

The administrator pages this clinic's payment history with the cursor. Organisation A's administrator never sees organisation B's subscription or payments.

**Why this priority**: This story uses the subscription page from User Story 1. Classification and reversals are already asserted there; this story is the cursor and the clinic boundary.

**Independent Test**: E2E-P6.4-04 and E2E-P6.4-05 in harness H-FL on H-FS. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** this tenant's payment history, **When** the administrator pages it, **Then** paging covers 30 payments. A page holds 20 payments of this tenant, ordered by `paid_at` ascending and then `reference` ascending, and the next page is requested with the cursor. (E2E-P6.4-04) (04 §2.2)
2. **Given** organisations A and B, **When** organisation A's administrator opens the subscription page and payment history, **Then** that administrator never sees B's subscription or payments. (E2E-P6.4-05) [A36]

### 2.3 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P6.4-01 | H-FL on H-FS | Subscription page composed in the app shell on `AdministratorBillingPage` (`frontend/lib/features/ai/billing/administrator_billing_page.dart`), route `AppRoutes.aiAdministratorBilling` (`frontend/lib/app/router.dart`, `frontend/lib/app/app_routes.dart`), opened from the renew action on `AiFeatureHostPage` (key `ai_notice_renew`) and from `AiDegradedView`. Reads `get_ai_billing_status` and `GET /v1/subscription`, and payment history from `GET /v1/payments` | duplicate payment → `duplicate_payment` notice; history shows both, the second `likely_duplicate`; queued count 1 [A6] | FR-001, FR-002, FR-003 | User Story 1 |
| E2E-P6.4-02 | H-FL on H-FS | That same subscription page and its payment history | refund → `reversal_recorded` + `terms_held`; history shows the reversal; status `ended_reversed` [A16] | FR-001, FR-002, FR-003 | User Story 1 |
| E2E-P6.4-03 | H-FL on H-FS | That same subscription page, commercial notices from `GET /v1/subscription` | Late payment → `late_payment_honoured`; withheld mismatch → `payment_withheld` | FR-002 | User Story 1 |
| E2E-P6.4-04 | H-FL on H-FS | Payment history on that page, `GET /v1/payments?cursor=` | Paging over 30 payments | FR-004 | User Story 2 |
| E2E-P6.4-05 | H-FL on H-FS | Organisation A's administrator session of that same page, `get_ai_billing_status`, `GET /v1/subscription`, and `GET /v1/payments` | A36 desktop path: org A's administrator never sees B's subscription or payments [A36] | FR-005 | User Story 2 |

### 2.4 Edge Cases

- `GET /v1/subscription` returns `{contract_version, subscription_ref, snapshot, notices}`. `snapshot` is the §1.7 object from a live `getCoverage` (`detail.snapshot`). When that call fails, `snapshot` is this tenant's `coverage_view.snapshot`. When that call fails and this tenant has no `coverage_view` row, `snapshot` is null and the response is still that object. (04 §2.2)
- `terms_held` stays out of `notices` unless `snapshot.held_count` > 0. A refund that shows `terms_held` is that case. (04 §2.2, E2E-P6.4-02)
- `notices` is only this closed set of code strings: `duplicate_payment` when a payment of this tenant is classified `likely_duplicate`; `late_payment_honoured` when one is `late`; `payment_withheld` when a payment disposition is `withheld_mismatch`; `reversal_recorded` when a reversal is recorded for this tenant; `terms_held` when `snapshot.held_count` > 0. (04 §2.2, E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03)
- Status `ended_reversed` is the notice raised when the state is `reversed`. (04 §3.2, E2E-P6.4-02)
- A manual chargeback (HP), effect `end_current`, voids the grant, ends the term `reversed` with no grace, and holds queued terms (05 §8 A15). The desktop scenario for that reversed status and for held terms is the refund path: `reversal_recorded`, `terms_held`, the reversal in history, and status `ended_reversed` (E2E-P6.4-02, A16).
- A caller whose membership role is not `administrator` receives `rpc_result` with `success = false`, `error_code = 'FORBIDDEN_ROLE'`, and no status payload from `get_ai_billing_status`. (04 §3.1)
- When the projection row is absent, or a copied column is null, that JSON value is null. There is no `remaining` field. Remaining is `allowance - used` when both are non-null, including when `used` exceeds `allowance`; it is null when either is null. (04 §3.1)
- A page holds 20 payments of this tenant, ordered by `paid_at` ascending and then `reference` ascending. The `cursor` query is omitted or empty for the first page; otherwise it is the `reference` of the last payment on the previous page, that string unchanged (the `PAY-` human reference). `next_cursor` is the `reference` of the last payment on this page, or empty when `payments` is empty. `has_more` is true when another payment of this tenant follows the page. A `cursor` that is not a `reference` of this tenant is `invalid_request`. (04 §2.2, E2E-P6.4-04)
- Organisation A's administrator never sees B's subscription or payments. (E2E-P6.4-05)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The desktop MUST show an administrator subscription page composed in the live app shell on `AdministratorBillingPage`, and MUST show "contact support" with the subscription reference. The page reads `get_ai_billing_status(p_contract_version)` and `GET /v1/subscription`. Plan is `plan_display_name`. Dates are `starts_at`, `ends_at` (the term end date), and `grace_ends_at`. Allowance figures are `allowance` and `used`, copied from `clinic_ai_coverage`. Queued and held counts are `queued_count` and `held_count`. `subscription_ref` on `GET /v1/subscription` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ the token's `org`), computed with no lookup. The RPC returns that same `subscription_ref` among its flat `data` fields, with `abo_base_url`. When the projection row is absent, or a copied column is null, that JSON value is null. (04 §2.2, 04 §3.1, Implements)
- **FR-002**: The subscription page MUST show commercial notices from `GET /v1/subscription`: `duplicate_payment` when a payment of this tenant is classified `likely_duplicate`; `late_payment_honoured` when one is `late`; `payment_withheld` when a payment disposition is `withheld_mismatch`; `reversal_recorded` when a reversal is recorded for this tenant; `terms_held` only when `snapshot.held_count` > 0. A duplicate payment shows `duplicate_payment` and queued count 1. A late payment shows `late_payment_honoured`. A withheld mismatch shows `payment_withheld`. A refund shows `reversal_recorded` and `terms_held`, and status `ended_reversed` (raised when the state is `reversed`). (04 §2.2, 04 §3.2, 05 §8 A6, A16, E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03)
- **FR-003**: Payment history MUST list this tenant's payments from `GET /v1/payments?cursor=`. Each payment is `{reference, paid_at, amount_minor, currency, plan_display_name, offer_version, term_unit, term_count, classification, reversals}`. `plan_display_name` is the name `GET /v1/offers` returns for that offer. `offer_version` is the payment's `offer_version`. `term_unit` and `term_count` are the term covered, copied from the checkout snapshot. `classification` is `normal`, `likely_duplicate`, or `late`. `reversals` is an array of `{reference, amount_minor, kind, is_full}`; `kind` is `refund`, `void`, `chargeback`, or `unknown`. On a duplicate payment, history shows both payments and the second is `likely_duplicate`. On a refund, history shows the reversal. (04 §2.2, 05 §8 A6, A16, E2E-P6.4-01, E2E-P6.4-02)
- **FR-004**: The desktop MUST page payment history with the cursor. A page holds 20 payments of this tenant, ordered by `paid_at` ascending and then `reference` ascending. The `cursor` query is omitted or empty for the first page; otherwise it is the `reference` of the last payment on the previous page, that string unchanged (the `PAY-` human reference). `next_cursor` is the `reference` of the last payment on this page, or empty when `payments` is empty. `has_more` is true when another payment of this tenant follows the page. Paging over 30 payments uses that cursor. A `cursor` that is not a `reference` of this tenant is `invalid_request`. (04 §2.2, E2E-P6.4-04)
- **FR-005**: Organisation A's administrator MUST never see B's subscription or payments. (E2E-P6.4-05)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: frontend. The unit row names no wiring exception. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic administrator reads this clinic's subscription, commercial notices, and payment history, including a duplicate payment, a refund, a late payment, and a withheld mismatch, and can contact support with the subscription reference. Another clinic's subscription and payments are not shown.
- **Layer Placement**: Flutter owns the subscription page, payment history, and "contact support" with the subscription reference. Supabase exposes `get_ai_billing_status`. The ABO exposes `GET /v1/subscription` and `GET /v1/payments`. This unit does not record payments, reversals, or grants.
- **Data Integrity & Security**: This unit defines no tables. `get_ai_billing_status` is `administrator` only and returns `FORBIDDEN_ROLE` with no status payload for any other membership role. Subscription and payment reads are for this tenant. Organisation A's administrator never sees B's subscription or payments.
- **Failure Handling**: When live coverage fails, `GET /v1/subscription` uses this tenant's `coverage_view.snapshot`; when that row is also absent, `snapshot` is null and the response is still returned. A cursor that is not a reference of this tenant is `invalid_request`. Null copied columns stay null. `terms_held` is omitted unless `snapshot.held_count` > 0.

## 5. Out of Scope

- The unit row states no Out of scope list.
- No Do-not-read material. The unit row names none. The cited 04 §2.2 span is the rows `GET /v1/subscription` and `GET /v1/payments`. The cited 04 §3.1 span is the row `get_ai_billing_status`. The cited 04 §3.2 span is the notice table. The cited 05 §8 span is rows A6, A15, and A16.
- No Consumes rewrite. P6.3 freezes CP-E: one thread from the admin desktop client to checkout, payment, grant, status, and an AI request.
- No module this unit's E2E scenarios do not reach (rule S8). The P2.2 and package-half P2.1 exception does not apply. The subscription page, commercial notices, "contact support", and payment history are reached from `AdministratorBillingPage` in the app shell.
- No S9 path owned by a later unit. This unit names no transitional path.
- No second codebase beyond frontend. H-FL is Dart client tests against H-FS plus widget scenario tests (`frontend/test/integration/`, `frontend/test/widget/`), extended here and not forked.
- Offers, billing contact, checkout, and polling stay with P6.3. This unit reads subscription and payments after that flow.
- Recording a duplicate payment, a refund, a late payment, or a withheld mismatch stays with the units that already verify A6 and A16 locally (section 5, D2). This unit shows the subscription, the notices, and the history.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P6.4-01, E2E-P6.4-02, E2E-P6.4-03, E2E-P6.4-04, and E2E-P6.4-05 are green in harness H-FL on H-FS.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-6 default: no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL).
- Rule S9: this unit names no transitional path.
- E2E-P6.4-03 arranges `late` by setting the open checkout's `checkout_status.state` to `cancelled` in the local ABO D1, then replaying the Paymob success fixture. E2E-P6.4-04 arranges 30 payments as three batches of 10 through checkout and that fixture, and after each batch sets those checkout `fact_log.created_at` values to more than one hour before wall-clock now. `TEST_CLOCK` stays unset. The arrange step does not insert payment or reversal rows.
