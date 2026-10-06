# Research: P4.3 notification intake and payment confirmation

## 1. R-2 redelivery, second success, order listing, and rate limits

**Decision:** No live Paymob call was made. The environment has no Paymob credential (`PAYMOB_API_KEY`, `PAYMOB_SECRET_KEY`, and `PAYMOB_HMAC` are unset). This unit does not stop. Inquiry sweeps stay with P4.5. Confirm in this unit follows the cited inquire paths and does not assume an order listing is complete.

**Rationale:** OQ-3 leaves these four R-2 items with P4.3. Rule S6 says the spike records its outcome and, on failure, uses the fallback named in 05 §10: inquiry sweeps. Those sweeps are P4.5 (unit Out of scope). The spike command only checked that no Paymob credential is present.

What this unit does with each item:

- **Redelivery.** Not observed. A repeated raw body is `dedupe_key` = SHA-256 of that body and disposition `duplicate`, with no second `confirm` row. Storage failure still answers 5xx and enqueues nothing, so a later delivery of the same body can be stored once.
- **Second success on one intention.** Not observed. `paymob_state_seen` dedupes transaction, normalized state, and cumulative reversed amount. A decline then a success on the same checkout is still one payment (E2E-P4.3-04). No extra “second success” rule is added.
- **Order listing.** Not observed. `inquire` calls `POST /api/ecommerce/orders/transaction_inquiry` for the stored order id and `GET /api/acceptance/transactions/{id}` when the verified callback carried a transaction id. The GET is the source for that transaction. The unit does not treat the order inquiry body as a complete list of every transaction.
- **Rate limits.** Paymob’s numeric inquiry limit was not observed. A scripted inquiry timeout or HTTP 429 leaves the `confirm` row open and backs off. The notify route’s own limit is the bound one: 60 requests per 60 seconds per `CF-Connecting-IP`.

**Named fallback:** 05 §10 inquiry sweeps, owned by P4.5. This unit records the spike and does not implement those sweeps.
