# P6.4 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. H-FS late payment and thirty payments

**Question:** E2E-P6.4-04 needs 30 payments of one tenant, and E2E-P6.4-03 needs a payment classified `late`. The clarification says the H-FL tests arrange a duplicate, a refund, a late payment, a withheld mismatch, and 30 payments through the existing H-FS workers and Paymob stub, and that the desktop test does not insert payment or reversal rows. The shipped clinic API stops at 10 checkouts per tenant per hour, so that checkout flow cannot record 30 payments in one test. A payment is classified `late` only when its checkout is `expired` or `cancelled`, and `expires_at` is creation plus 30 minutes. The H-FS ABO config does not set `TEST_CLOCK`. How does the test arrange 30 payments and a late payment on H-FS without inserting payment or reversal rows, and without waiting out the hourly checkout limit and the 30-minute expiry?

**Assumption:** The arrange step still uses the existing checkout and Paymob success fixture. It does not insert `payment` or `reversal` rows. `TEST_CLOCK` stays unset. It does not sleep for the hourly window or for `expires_at`. For E2E-P6.4-03, after the checkout is `open`, the arrange step sets that checkout's `checkout_status.state` to `cancelled` in the local ABO D1, then replays the success fixture. Confirmation classifies the payment `late` because the checkout is `cancelled`. For E2E-P6.4-04, thirty payments are three batches of 10. Each payment is its own `POST /v1/checkouts` with a new `client_request_id` and a success fixture whose transaction id and order id are that checkout's. After each batch of 10, and before the next checkout, the arrange step sets `fact_log.created_at` for those checkout facts (`"table" = 'checkout'`, `key` = `checkout_id`) to more than one hour before wall-clock now, so the hourly count is under 10.

**Why:** The hourly count is checkout `fact_log` rows newer than one hour, and `late` is the checkout state `expired` or `cancelled` at confirmation. Backdating those checkout facts reopens the existing window. Setting `cancelled` is the state the operator-cancel path already stores, so confirmation records `late` with no expiry sweep and no test clock. Payment rows still come only from the confirmation worker.

**Amended:** `specs/092-abo-p6-4-administrator-subscription-payment-history-notices/spec.md` (Clarifications, Session 2026-10-08; §7 Assumptions).
