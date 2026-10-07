# P5.2b escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Status view as_of

**Question:** What does `as_of` mean on the status view that `get_ai_status` and `get_ai_billing_status` return? 04 §3.2 names `as_of` and this unit freezes that view for P6.x, but 04 §3.2, 04 §3.3, the `clinic_ai_coverage` row, and the P5.2b unit row never say whether it is read-time `now`, `event_at`, `applied_at`, or `feed_state.last_success_at`.

**Assumption:** `as_of` is the read-time `now` of the status computation: PostgreSQL `now()` for that call. It is not `clinic_ai_coverage.event_at`, not `applied_at`, and not `feed_state.last_success_at`. The field is present when the projection row is absent. `get_ai_status` and `get_ai_billing_status` return this same `as_of`. The read does not store it.

**Why:** §3.3 computes the view against the current time `now`, and `days_left` and `grace_days_left` are measured from that instant. The view is still returned when the projection row is absent, so `event_at` and `applied_at` are not there to copy. `feed_state.last_success_at` is already the input to `stale`. P6.x consumes `as_of` as the clock the returned state was evaluated at.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§3.2); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P5.2b Implements).
