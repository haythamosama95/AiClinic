# Administrator subscription, payment history and commercial notices

**Unit**: P6.4 · **Branch**: `ai/092-abo-p6-4-administrator-subscription-payment-history-notices` · **Harness**: H-FL · **Verification**: T020 (five E2E ids)

## 1. What was implemented

The Flutter desktop administrator billing page now shows this clinic's subscription summary, commercial notices, and payment history alongside the existing P6.3 offers, contact, and checkout flow. Reads use the signed-in session only; no widget takes an organisation id.

- **ABO client** (`abo_client.dart`) — Parses `GET /v1/subscription` and `GET /v1/payments`; the first payments call omits `cursor`; later calls pass the previous `next_cursor` unchanged and surface `invalid_request` (FR-001, FR-003, FR-004).
- **Subscription summary** (`subscription_summary.dart`) — Calls `get_ai_billing_status` and `GET /v1/subscription`; shows plan, dates, allowance, used, queued and held counts, subscription reference, "contact support", and `ended_reversed` when present; null fields stay null; no organisation argument (FR-001, FR-002, FR-005).
- **Commercial notices** (`commercial_notices.dart`) — Shows notice code strings from `GET /v1/subscription`, including `duplicate_payment`, `late_payment_honoured`, `payment_withheld`, `reversal_recorded`, and `terms_held` only when the array contains them (FR-002).
- **Payment history** (`payment_history.dart`) — Shows payment fields, classification, and reversals in response order; an explicit next-page control appears when `has_more` is true, requests the next page with `cursor` set to `next_cursor`, and appends results; no organisation argument (FR-003, FR-004, FR-005).
- **Administrator billing page** (`administrator_billing_page.dart`) — Composes the summary, notices, and history on the existing page; leaves offers, contact, checkout, the token client, and open-checkout resume unchanged (FR-001, FR-002, FR-003, FR-004, FR-005).
- **H-FL harness** (`administrator_subscription_fullstack_test.dart`) — Five tests tagged `fullstack`, titles prefixed `E2E-P6.4-01` through `E2E-P6.4-05` (FR-001, FR-002, FR-003, FR-004, FR-005).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `frontend/lib/features/ai/billing/abo_client.dart` | FR-001, FR-003, FR-004 |
| `frontend/lib/features/ai/billing/subscription_summary.dart` | FR-001, FR-002, FR-005 |
| `frontend/lib/features/ai/billing/commercial_notices.dart` | FR-002 |
| `frontend/lib/features/ai/billing/payment_history.dart` | FR-003, FR-004, FR-005 |
| `frontend/lib/features/ai/billing/administrator_billing_page.dart` | FR-001, FR-002, FR-003, FR-004, FR-005 |
| `frontend/test/integration/administrator_subscription_fullstack_test.dart` | FR-001, FR-002, FR-003, FR-004, FR-005 |
| `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/quickstart.md` | FR-001, FR-003, FR-004 |

## 3. Harness command for this unit's tests only

From `frontend/`:

```bash
flutter test test/integration/administrator_subscription_fullstack_test.dart --tags fullstack
```

This delivery did not execute that command because the H-FS stack was not running and this workflow does not start wrangler.

## 4. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P6.4-01 | Renew action on `AiFeatureHostPage` (`ai_notice_renew`) → `router.dart` billing route → `AdministratorBillingPage` → `SubscriptionSummary` + `CommercialNotices` + `PaymentHistory` → duplicate payment notice; history shows both payments with second `likely_duplicate`; queued count 1 |
| E2E-P6.4-02 | Paid checkout → refund fixture → same page → `reversal_recorded` and `terms_held` notices; reversal in history; status `ended_reversed` |
| E2E-P6.4-03 | Cancelled checkout + late success; amount-mismatch inquiry + withheld success → same page → `late_payment_honoured` and `payment_withheld` notices |
| E2E-P6.4-04 | Three batches of 10 paid checkouts with aged facts → same page → `PaymentHistory` first page of 20; next-page control requests `GET /v1/payments?cursor=<next_cursor>` and appends the remaining 10 |
| E2E-P6.4-05 | Organisation A administrator session after A and B each have a subscription and payment → same page → A sees only A's `subscription_ref` and payment references; B's never appear |
