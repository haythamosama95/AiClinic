# P4.4 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Paid grant approvals element

**Question:** A paid grant envelope must include `evidence.approvals` with at least one operator assertion, or the platform returns `rejected` / `approvals_required` (04 §1.4 field table). The frozen `grant` method already enforces that minimum. The purchase path (02 §1.5 first diagram) and E2E-P4.4-01 / E2E-P4.4-08 grant automatically after payment, with no operator ceremony. Nothing in this unit’s Read spans says what the ABO places in `approvals` on that path, or the element shape.

**Assumption:** For a paid grant the ABO sets `evidence.approvals` to a one-element list whose element is the §1.5 operation object `{op, params, actor_email, issued_at, nonce, contract_version}` with `op` `grant`, `params` equal to that same envelope with `evidence.approvals` omitted, `actor_email` `""`, `issued_at` the envelope `paid_at`, `nonce` the envelope `grant_id`, and `contract_version` the envelope `contract_version`, and the platform counts that element toward the minimum of one and does not apply the §1.5 WebAuthn checks.

**Why:** The purchase diagram (steps 4–5) and E2E-P4.4-01 / E2E-P4.4-08 grant after a verified payment with no operator ceremony, while §1.4 step 1 still rejects a paid envelope whose `approvals` list is empty. Step 2 verifies the ABO signature for `paid` and runs §1.5 only for a complimentary assertion, so the required element keeps the operation-object shape and adds no WebAuthn ceremony. `params` omits `evidence.approvals` so the element does not contain itself. The other fields are envelope values already fixed before the ABO signature, so a retry signs the same envelope. `actor_email` is empty because a paid `source` does not carry `operator_email`.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.4 evidence row).

## 2. Subscription and payments response shape

**Question:** This unit freezes `GET /v1/subscription` and `GET /v1/payments` (04 §2.2). Those rows name `subscription_ref`, commercial notices, the §1.7 snapshot, and payment page fields, but they do not say what `subscription_ref` is, how notices are shaped, where the snapshot is read from, the JSON keys for offer name and version, term covered, and reversals, or the payments cursor page size and encoding. What are those values?

**Assumption:** `GET /v1/subscription` returns `{contract_version, subscription_ref, snapshot, notices}`. `subscription_ref` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ the token's `org`), computed with no lookup. `snapshot` is the §1.7 object from a live `getCoverage` (`detail.snapshot`), and this tenant's `coverage_view.snapshot` when that call fails. `notices` is an array of code strings: `duplicate_payment` when a payment of this tenant is `likely_duplicate`; `late_payment_honoured` when one is `late`; `payment_withheld` when a disposition is `withheld_mismatch`; `reversal_recorded` when a reversal is recorded for this tenant; `terms_held` when `snapshot.held_count` > 0. `GET /v1/payments` returns `{contract_version, payments, next_cursor, has_more}`. Each payment is `{reference, paid_at, amount_minor, currency, plan_display_name, offer_version, term_unit, term_count, classification, reversals}`. `plan_display_name` and `offer_version` are the offer name and version. `term_unit` and `term_count` are the term covered, from the checkout snapshot. `classification` is `normal`, `likely_duplicate`, or `late`. `reversals` is an array of `{reference, amount_minor, kind, is_full}` with `kind` one of `refund`, `void`, `chargeback`, `unknown`. A page holds 20 payments, ordered by `paid_at` ascending then `reference` ascending. The `cursor` query is omitted or empty on the first page; otherwise it is the previous page's last `reference`, that `PAY-` string unchanged. `next_cursor` is this page's last `reference`, or empty when `payments` is empty. `has_more` is true when another payment of this tenant follows the page. A `cursor` that is not a `reference` of this tenant is the existing `invalid_request`.

**Why:** `subscription_ref` is the subscription reference already fixed in 03 §7, which both systems compute from `org_id` and which this row and `GET /v1/coverage` already return. The snapshot fallback is the one this section already uses for checkout `starts`: live `getCoverage`, then `coverage_view`. Notice values are the five codes already named on the row, carried as strings the way §3.2 carries notice codes, and each code is tied to a classification, disposition, reversal row, or `held_count` already named beside it. Offer name and version use `plan_display_name` from `GET /v1/offers` and `offer_version` from the payment. Term covered uses `term_unit` and `term_count` from the checkout snapshot. Reversals use the quotable `reference`, `amount_minor`, `kind`, and `is_full` from the reversal record. The route names only `cursor`, so the page size stays fixed at 20 and the cursor is the existing `reference` string with no second encoding. `invalid_request` is the field-validation code already in §2.3. No new error code, endpoint, or operator step.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§2.2 rows `GET /v1/subscription` and `GET /v1/payments`).

## 3. Subscription notice closed set

**Question:** FR-005 says this unit's notice codes are only `duplicate_payment`, `late_payment_honoured`, and `payment_withheld`, and Out of Scope sends reversal notices to P4.5. The amended 04 §2.2 `GET /v1/subscription` row makes `notices` a closed set that also includes `reversal_recorded` and `terms_held` under the conditions in that row. The spec should follow that row. How should FR-005 and the reversal-notices out-of-scope line be aligned to it?

**Assumption:** `spec.md` follows the amended 04 §2.2 `GET /v1/subscription` row. `notices` is an array of code strings from that closed set: `duplicate_payment` when a payment of this tenant is classified `likely_duplicate`; `late_payment_honoured` when one is `late`; `payment_withheld` when a payment disposition is `withheld_mismatch`; `reversal_recorded` when a reversal is recorded for this tenant; `terms_held` when `snapshot.held_count` > 0. The out-of-scope reversal-notices lines no longer exclude `reversal_recorded` and `terms_held` from this unit's subscription response. P4.5 still owns reversal processing; this unit only returns those notice codes.

**Why:** Entry 2 already binds `notices` to the five codes and conditions on the amended §2.2 row. FR-005 and the out-of-scope lines named only the first three and sent reversal notices to P4.5, which contradicted that row. Returning `reversal_recorded` and `terms_held` is the response the row already names. It does not move reversal workflows into P4.4.

**Amended:** `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/spec.md` (Implements notice list, FR-005, and the reversal-notices out-of-scope lines).

## 4. Unverified grant receipt

**Question:** When platform `grant` returns `applied` or `already_applied` but the receipt signature does not verify against the configured platform public keys, what happens to the grant work row? The cited outcome rules name `grant_outcome` only after a receipt checks, and they name park, backoff, and AL-04/AL-07 for other results. They do not name this failure.

**Assumption:** When platform `grant` returns `applied` or `already_applied` and the receipt signature does not verify against the configured platform public keys, the ABO does not record `grant_outcome`. The grant work row is parked and AL-07 is raised, the same outcome already named for `conflict` and `rejected`.

**Why:** A receipt is stored only after its platform signature verifies. This call returned a result, so it is not `transient` and the platform was not unreachable; AL-04 stays on those two conditions. A retry of the same `grant_id` returns that original receipt, so backoff cannot make the signature verify. `conflict` and `rejected` already park the grant work row and raise AL-07, and no other alert code names an unverified receipt.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.6).

## 5. Subscription snapshot when the view row is missing

**Question:** `GET /v1/subscription` takes `snapshot` from live `getCoverage`, then from this tenant's `coverage_view.snapshot` when that call fails. What is the response when the call fails and this tenant has no `coverage_view` row?

**Assumption:** When `getCoverage` fails and this tenant has no `coverage_view` row, `GET /v1/subscription` still returns `{contract_version, subscription_ref, snapshot, notices}` and `snapshot` is null. `terms_held` is absent because it is included only when `snapshot.held_count` > 0. The other notice codes are unchanged.

**Why:** Entry 2 already takes the snapshot from live `getCoverage` and then from this tenant's `coverage_view.snapshot`. A missing view row is not an unknown id, so `not_found` does not apply, and `provider_unavailable` applies only when the provider refuses or times out while creating a checkout. The row already returns a success object whose `snapshot` member can be null, and `subscription_ref` is still computed with no lookup. A null snapshot does not satisfy `snapshot.held_count` > 0, so `terms_held` stays out. No new error code.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§2.2 row `GET /v1/subscription`).
