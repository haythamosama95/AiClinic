# P6.3 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Checkout read JSON fields

**Question:** What are the JSON field names and shapes for the shown state and the offer summary on `GET /v1/checkouts/{id}`, and for the body of `GET /v1/checkouts?open=1`, including which field identifies a checkout so another desktop can resume it?

**Assumption:** `GET /v1/checkouts/{id}` returns `{contract_version, reference, shown_state, offer, payment_reference, term_ref, updated_at}`. `shown_state` is `Waiting`, `Failed`, `Paid`, `Active`, or `Abandoned` (03 §5.1). `offer` is `{offer_id, version, term_unit, term_count, charged_price_minor, currency}`, with `version` the checkout's `offer_version`. `payment_reference` and `term_ref` are JSON null. `updated_at` is `checkout_status.last_event_at`. The path `{id}` is the POST `checkout_id` ULID and is not a field of this body. `GET /v1/checkouts?open=1` returns `{contract_version, checkouts}`: the same object for each checkout whose `checkout_status.state` is `open`, `paid`, or `paid_late`. Another desktop resumes by `reference`.

**Why:** The §2.2 rows named a shown state and an offer summary and left the list body unnamed. The frozen checkout read already uses `shown_state`, `offer` with those six snapshot fields, JSON null for `payment_reference` and `term_ref`, and `updated_at` from `last_event_at`. The list is that object under `checkouts`, limited to `open`, `paid`, and `paid_late`. `reference` is the `CK-` field on each element; the list does not carry `checkout_id`.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§2.2 rows `GET /v1/checkouts/{id}` and `GET /v1/checkouts?open=1`); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P6.3 Implements).
