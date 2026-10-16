# P3.9 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Fields of queued terms and the last 12 terms on `GET /v1/coverage`

**Question:** What are the fields of `GET /v1/coverage` for queued terms (plan and duration) and for each of the last 12 terms with usage? Cited 04 §4.2 names `subscription_ref`, the live DO snapshot, queued terms (plan and duration), and the last 12 terms with usage, and this unit freezes that response. Those term lists have no field list in the cited spans. Choosing the fields would bind a later consumer (P6.2).

**Assumption:** `GET /v1/coverage` uses the two companion lists already fixed for `getCoverage` in 04 §1.7. `queued_terms` is the unheld terms in state `queued`, in ascending `position`. Each object is `{plan_id, plan_version, plan_display_name, duration_unit, duration_count}`. A queued term stores a duration and has no dates. `recent_terms` is at most the last 12 terms whose state is `active`, `grace`, or `ended`, highest `position` first. Each object is `{term_id, state, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used}`. `used` is the `hot` row's `used` when the term is `hot.active_term_id`, and `used_final` otherwise.

**Why:** 04 §1.7 already names those objects and says they are the same lists `GET /v1/coverage` describes as queued terms (plan and duration) and the last 12 terms with usage. 04 §1.3 already returns them as `queued_terms` and `recent_terms` on `getCoverage`. The P3.9 Read list omitted §1.7, so the clarify agent could not use that shape. Putting those two bullets in the Read list binds P6.2 to the existing lists and adds no new field.

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P3.9 Read line).

## 2. Form of `subscription_ref` on `GET /v1/coverage`

**Question:** What value does `GET /v1/coverage` put in `subscription_ref`? FR-008 and 04 §4.2 name the field next to the live snapshot, `queued_terms`, and `recent_terms`. Those two lists are already fixed by the resolved escalation. The form of `subscription_ref` is not in this unit’s Implements or Read spans. 03 §7 defines a subscription reference as `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`), computed with no lookup, and that section is not cited. Freezing the response needs that value, or an explicit statement that 03 §7 is in scope.

**Assumption:** `GET /v1/coverage` sets `subscription_ref` to the 03 §7 subscription reference: `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`). The platform computes it from `org_id` with no lookup. Only that row of 03 §7 is in scope.

**Why:** 03 §7 already defines that form and says each system computes it with no lookup. The P3.9 Implements and Read spans named the field and omitted the form, so the plan could not freeze the response. Naming the Subscription reference row and writing that form into the spec binds the frozen response to the existing reference.

**Amended:** `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/spec.md` (Implements Read line, coverage sentence, user story 3, FR-008, Assumptions); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P3.9 Read line).
