# P5.2 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Per-tenant refresh clock and status RPC refusals

**Question:** `request_ai_status_refresh` allows at most one call per 10 seconds per tenant and returns `{requested_at}` (04 §3.1). `feed_state` is a singleton and neither it nor `clinic_ai_coverage` stores a per-tenant last-refresh time (03 §4). The cited rows also do not name the throttled result, or the result when a non-administrator calls `get_ai_billing_status` or `request_ai_status_refresh`.

**Assumption:** `ai_internal.status_refresh` stores the per-tenant clock: `organization_id` primary key and `requested_at timestamptz`. `feed_state` stays the singleton pull cursor. `clinic_ai_coverage` stays the coverage snapshot. Neither gains this timestamp, and feed upserts do not touch `status_refresh`. `request_ai_status_refresh` accepts the call when no row exists for `current_org_id()` or `now() - requested_at >= interval '10 seconds'`. On accept it upserts `requested_at = now()`, returns `rpc_result` success with `data = {requested_at}` set to that stored value, and starts an immediate pull. When a row exists and `now() - requested_at < interval '10 seconds'`, the RPC returns `success = false`, `error_code = 'RATE_LIMITED'`, does not start a pull, and does not change `requested_at`. A caller whose membership role is not `administrator`, on `get_ai_billing_status` or `request_ai_status_refresh`, returns `success = false`, `error_code = 'FORBIDDEN_ROLE'`, with no status payload, no pull, and no write to `status_refresh`. Both refusals set `contract_version` to the accepted request version. `get_ai_status` stays available to every member.

**Why:** A timestamp on the singleton `feed_state` would throttle every tenant together. `clinic_ai_coverage` is replaced by feed events and can be absent, so the clock cannot live on the snapshot. `FORBIDDEN_ROLE` and `RATE_LIMITED` are the codes `issue_billing_token` already returns for the same role and throttle failures, and P6.x consumes these status RPC results.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§4 row `ai_internal.status_refresh`); `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§3.1 rows `get_ai_billing_status`, `request_ai_status_refresh`); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P5.2 Read, Implements, E2E-P5.2-02, E2E-P5.2-04; § coverage map row 03 §4).

## 2. Notice record fields

**Question:** `get_ai_status` returns `notices[]` as records, not UI strings (04 §3.2, X-05). X-05 names `audience` and `channel` (only `in_app` at launch). 04 §3.2 names the codes and says `in_grace` carries grace days left, but it does not name the field that holds the code or the field that carries those grace days. P6.x consumes these notice records. Choosing the field names would freeze the status RPC result.

**Assumption:** Each element of `notices[]` is `{code, audience, channel}`, and `in_grace` also includes `grace_days_left`. `code` is one value from the closed vocabulary. `audience` is `member`. `channel` is `in_app`. `grace_days_left` is present only when `code` is `in_grace`: a non-negative integer, the whole 24-hour days from `now` until `grace_ends_at`, floored, so a remaining partial day is `0`. Every other code omits `grace_days_left`. The same records are returned to every member. `get_ai_billing_status` returns this same status view, so its `notices[]` uses the same fields.

**Why:** P6.x renders these records. `code` is the vocabulary column. `grace_days_left` is the grace remainder on that one code, separate from top-level `days_left` and from offer `grace_days`. `audience` and `channel` are the X-05 fields. One `member` / `in_app` record per raised code matches staff and administrators seeing the same notices, with the desktop choosing the form from the caller's role.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§3.2); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P5.2 Implements).

## 3. Term days_left

**Question:** `get_ai_status` returns `days_left`, and `ends_soon` is raised when `days_left` is 7, 3, or 1 or fewer (04 §3.2, 01 I-10). §3.2 defines `grace_days_left` as the whole 24-hour days from `now` until `grace_ends_at`, floored, and treats that as separate from top-level `days_left`. It does not say which timestamp `days_left` counts toward, or how a partial day is rounded. P6.x consumes `days_left`. Choosing that rule would freeze the status result.

**Assumption:** `days_left` counts toward the projection row's `ends_at` (`clinic_ai_coverage.ends_at`), not `grace_ends_at` and not `next_change_at`. It is the whole 24-hour days from `now` until that `ends_at`, floored, so a remaining partial day is `0`. When the projection row is absent, `ends_at` is null, or `now` is at or after `ends_at`, `days_left` is null. A null `days_left` does not raise `ends_soon`. `get_ai_billing_status` returns this same `days_left`. `grace_days_left` stays the floored whole days until `grace_ends_at` and stays off this field.

**Why:** I-10 renewal notices are the term end at 7, 3, and 1 days, and §3.3 already treats `ends_at` as that boundary. `grace_ends_at` is already `grace_days_left`. `next_change_at` can be `grace_ends_at`, so counting toward it would collapse the two numbers during grace. Floor matches `grace_days_left`: the last incomplete day is `0`, which is why `ends_soon` says "1 or fewer". Null once `now` reaches `ends_at` keeps that `0` on the last partial day of the term only, so `ends_soon` does not stay raised through grace and lapse. P6.x consumes the integer or null.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§3.2); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P5.2 Implements).

## 4. Status reason

**Question:** `get_ai_status` returns `reason` (04 §3.2). The snapshot's `reason` for non-available states is `none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, or `transfer_pending` (04 §1.7). `clinic_ai_coverage` has no `reason` column (03 §4), and §3.3 never sets `reason`, including when stored `active` becomes `grace` or `lapsed`, and when the read-time state is `suspended`. P6.x consumes this field. Choosing a stored column or a read-time mapping would change those sections.

**Assumption:** `clinic_ai_coverage.reason` stores the applied snapshot's `reason`. The column is null when that snapshot's `state` is `active` or `grace`. Otherwise it is that snapshot's value: `none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, or `transfer_pending`. Feed upserts replace it with the other projection fields. Status reads do not write it. `get_ai_status` returns `reason` null when the returned state is `active`, `grace`, or `suspended`; `none` when the projection row is absent; `expired` when stored `active` or stored `grace` becomes `lapsed` at read time; otherwise the stored column. Stored `active` that becomes `grace` is null. Read-time `suspended` is null, and that step wins over the clock, so a suspended row does not take `expired`. `get_ai_billing_status` returns this same `reason`.

**Why:** `grace_exhausted` and `expired` are both `lapsed` on the snapshot, and dates alone cannot tell them apart once `grace_ends_at` has passed, so the projection keeps the snapshot value. The §3.3 clock still moves stored `active` or `grace` to `lapsed` before the next event, and that path is calendar expiry (`expired`, A10). Grace remains available, so its reason is null. `suspended` is an overlay and is not a §1.7 reason. P6.x consumes `reason`.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§4 row `ai_internal.clinic_ai_coverage`); `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§3.2, §3.3); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P5.2 Implements).

## 5. Billing status plan, dates, and allowance figures

**Question:** `get_ai_billing_status` returns the §3.2 status view plus plan, dates, allowance figures, `queued_count`, `held_count`, `subscription_ref`, and `abo_base_url` (04 §3.1, FR-60). FR-60 names the current plan, the term end date, and allowance used and remaining. It does not name the JSON fields for plan, dates, or allowance figures, or whether remaining is `allowance - used`. The projection columns are `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, and `used` (03 §4). P6.x consumes this result. Choosing those keys would freeze the billing status result.

**Assumption:** On success, `data` is the §3.2 status view plus these flat fields, copied from `clinic_ai_coverage`: `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, and `used`, together with the already named `queued_count`, `held_count`, `subscription_ref`, and `abo_base_url`. Plan is `plan_display_name`. Dates are `starts_at`, `ends_at` (the term end date), and `grace_ends_at`. Allowance figures are `allowance` and `used`. There is no `remaining` field and no nested `term` object. Remaining is `allowance - used` when both are non-null, including when `used` exceeds `allowance`. Remaining is null when either is null. When the projection row is absent, or a copied column is null, that JSON value is null. Notices, `days_left`, `reason`, and `FORBIDDEN_ROLE` stay as in §1–§4.

**Why:** Those names are the projection columns and the snapshot `term` fields (04 §1.7). FR-60's current plan is `plan_display_name`, and its term end date is `ends_at`. `allowance` and `used` are the stored figures; remaining is their difference, so the result does not add a third number that can drift. P6.x consumes this object. Live allowance stays on `/v1/coverage`.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§3.1 row `get_ai_billing_status`); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P5.2 Implements).

## 6. Snapshot contract_version on the projection

**Question:** 04 §1.7 says the backend projection keeps the snapshot `contract_version` so old rows are read by the rules they were written with. 03 §4's `clinic_ai_coverage` columns do not include `contract_version`. The status RPC `contract_version` is the version the request used (04 §3.1), not this stored snapshot field. Choosing whether the projection stores the snapshot version would change that column list.

**Assumption:** `clinic_ai_coverage` does not store the snapshot `contract_version`. The column is absent. This table is the stated exception to the record-level `contract_version` that otherwise exists on every record. `coverage_mirror` and `coverage_view` still keep the snapshot version. Feed upserts map the accepted snapshot into the columns in 03 §4 and do not write a version. `get_ai_status` and `get_ai_billing_status` do not read a stored snapshot version. Their `rpc_result.contract_version` stays the version the request used.

**Why:** The projection stores flattened columns, and §3.2 and §3.3 already read those columns. It does not store the snapshot payload, so there is no snapshot shape to reinterpret from a stored version. `coverage_view` stores that payload and keeps the version. Status results already answer in the request version (§3.1, §1). A stored snapshot version would not be that RPC field, and reading old rows by it would change the notice, `days_left`, and `reason` rules already fixed in §2–§5.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§4 row `ai_internal.clinic_ai_coverage`); `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.7 row `contract_version`).

## 7. Task-cap split into P5.2a and P5.2b

**Question:** Which user stories should become P5.2a and P5.2b, keeping the same E2E ids?

**Assumption:** P5.2a is User Story 1 (Coverage pull and projection) and User Story 4 (Administrator status refresh): E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10. P5.2b is User Story 2 (Read-time status and notices) and User Story 3 (Administrator billing status): E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11. The ids stay `E2E-P5.2-*`. This branch `ai/088-abo-p5-2-coverage-feed-puller-status-projection` and spec 088 continue as P5.2a. P5.2b is spec 088b and is not created by this amendment. P5.2a is size M and owns the pull, the projection (including `reason` on upsert), `status_refresh`, `request_ai_status_refresh`, available/active and `stale` on `get_ai_status`, the availability drop, cursor rebuild, and the R-4 spike. P5.2b is size S, depends on P5.2a, and owns grace, lapse, notices, `days_left`, the `reason` read mapping, and `get_ai_billing_status`. P6.1 depends on P5.2b. CP-D stays on P5.2a.

**Why:** The tasks pass counted 42 tasks. Size L stops at 40 (rule S3). Plan sequencing is 38 steps; the four extra tasks are the catalog file splits and `quickstart.md`. Stories 1 and 4 take the pull, projection, refresh, availability-drop, and minimal status tasks, about 31, inside M (20–32) and under 40. Stories 2 and 3 take the remaining read-time and billing tasks, about 14, inside S (12–20) and under 40. Story 4 starts the pull, so it stays with story 1. Stories 2 and 3 only read the projection story 1 writes. Each half has two stories, one codebase, and a Read list inside its size row (7 and 4).

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (unit index; rule S4 table and the unit total; S6 R-4; S10; S11 CP-D; H-FS; P5.1 scope; P5.2 replaced by P5.2a and P5.2b; P6.1 depends; coverage map; OQ-3).
