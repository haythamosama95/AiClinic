# AI Platform Data Journey — Stage 4 — Entitlement and capability grants

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [API: `POST /control/installations/{installation_id}/entitle`](#3-api-post-controlinstallationsinstallation_identitle)
   - [Request body — every field](#request-body-every-field)
   - [Success response (200)](#success-response-200)
   - [D1 writes](#d1-writes)
4. [Runtime entitlement checks (guard stage 3)](#4-runtime-entitlement-checks-guard-stage-3)
5. [Failure paths](#5-failure-paths)
6. [Example entitle payload (visit summary)](#6-example-entitle-payload-visit-summary)

---




## 1. Plain language

The **control-plane caller** activates spend rights via `POST /control/installations/{installation_id}/entitle`
(`control/entitle.ts`): billing period, quotas, allowed capabilities, and explicit grant rows.
**One-shot:** only works when entitlement is `pending`.

## 2. Metaphor

The **ticket office opens** — the airline gets a prepaid card (quotas) and permission slips (grants) for specific flight types (capabilities).

## 3. API: `POST /control/installations/{installation_id}/entitle`



#### Request body — every field


| Field                  | Type     | Validation    | D1 destination                                                       |
| ---------------------- | -------- | ------------- | -------------------------------------------------------------------- |
| `period_start`         | string   | ISO-8601 UTC instant (`YYYY-MM-DDTHH:mm:ss[.sss]Z`); must parse; must be `< period_end` | `entitlement.period_start`                                           |
| `period_end`           | string   | ISO-8601 UTC instant; must parse; must be `> period_start` | `entitlement.period_end`                                             |
| `request_quota`        | integer  | ≥ 0           | `entitlement.request_quota`                                          |
| `token_budget`         | integer  | ≥ 0           | `entitlement.token_budget`                                           |
| `cost_budget`          | number   | finite ≥ 0    | `entitlement.cost_budget`                                            |
| `soft_threshold`       | number   | ∈ [0, 1]      | `entitlement.soft_threshold` — fraction at which routing may degrade |
| `allowed_capabilities` | string[] | each string   | `entitlement.allowed_capabilities` (JSON string)                     |
| `grants`               | array    | non-empty     | → `capability_grant` rows                                            |


**Note — three period ceilings (any one can block):** The Quota Durable Object tracks usage for the
billing period (`period_start`–`period_end`). Admission fails with `quota_exhausted` when **any**
counter has already reached its limit; after each completed request, all three increment at credit
time (`requestsUsed += 1`, `tokensUsed += provider tokens`, `costUsed += platform cost units).


| Field           | What it caps                       | Counted as                                     |
| --------------- | ---------------------------------- | ---------------------------------------------- |
| `request_quota` | Number of AI requests (inferences) | +1 per admitted request at settlement          |
| `token_budget`  | Total tokens consumed              | Sum of provider-reported input + output tokens |
| `cost_budget`   | Total spend in platform currency   | Sum of per-request cost from provider usage    |


**Example** (same numbers as [§6 Example entitle payload](#6-example-entitle-payload-visit-summary)): `request_quota: 1000`, `token_budget: 500000`, `cost_budget: 50.0`
for one month. A clinic could hit the wall three different ways: 1000 visit summaries even if tokens
and cost are still under budget; one month of heavy summaries burning 500k tokens before the 1000th
call; or a run of expensive model usage reaching $50 while requests and tokens remain. Whichever
ceiling is reached first blocks further admission until the period resets or entitlement is updated.

**Note —** `soft_threshold` **(early degrade, not a hard stop):** A fraction in `[0, 1]` of **any** of the
three period budgets. At admission the Quota DO compares `requestsUsed / request_quota`,
`tokensUsed / token_budget`, and `costUsed / cost_budget`; if **any** ratio ≥ `soft_threshold`, the
next request is still **admitted** but marked `degraded: true` (`routing_tier = degraded` on the
journal row). Hard exhaustion at 100% of a ceiling is separate — that returns `quota_exhausted` and
blocks admission. `soft_threshold = 0` disables soft degrade (enroll’s pending sentinel uses `0` so a
not-yet-entitled row never downgrades routing).

**Example:** `request_quota: 1000`, `soft_threshold: 0.8` (as in [§6 Example entitle payload](#6-example-entitle-payload-visit-summary)). After **800** requests have
been credited in the period (`requestsUsed / 1000 ≥ 0.8`), the 801st request is still allowed but
admission crosses the soft threshold — the live path journals `routing_tier = degraded`, routes
`match.tiers` degraded rules, and emits `degraded_notice: true` on SSE `accepted`. The same threshold
can fire on tokens or cost instead: e.g. 400k of 500k tokens used (80%) triggers degrade even if only
600 requests were credited. Below the threshold, routing stays on the standard tier.

**Grant object (**`grants[]`**):**


| Field                | Required | Default        | D1 `capability_grant`                          |
| -------------------- | -------- | -------------- | ---------------------------------------------- |
| `capability_id`      | yes      | —              | `capability_id`                                |
| `capability_version` | yes      | —              | `capability_version`                           |
| `scope`              | no       | `installation` | `scope` = `installation:{id}` or `plan:{plan}` |




#### Success response (200)

```json
{
  "installation_id": "<id>",
  "status": "active"
}
```



#### D1 writes

1. **UPDATE** `entitlement` — all budget fields + `status='active'` (`WHERE installation_id = ?`). `UNIQUE (installation_id)` guarantees this touches exactly one row; a duplicate row set cannot silently multi-update.
2. **INSERT** `capability_grant` per grant item
3. **INSERT** `control_audit` — `action='entitle'`, `after_pointer` = JSON of `allowed_capabilities`

**Not updated:** `entitlement.plan`, `installation.status`.

## 4. Runtime entitlement checks (guard stage 3)

For each request, `evaluateEntitlement` reads cached D1 rows:


| Check order | Field(s) examined                                    | Failure code           | path                     |
| ----------- | ---------------------------------------------------- | ---------------------- | ------------------------ |
| 1           | `entitlement.status`                                 | `forbidden_capability` | `ai_disabled`            |
| 2           | `entitlement.plan` vs `minimumPlanTier`              | `forbidden_capability` | `plan_tier`              |
| 3           | `allowed_capabilities` JSON includes `capability_id` | `forbidden_capability` | `capability_not_granted` |
| 4           | Grant at `installation:{id}` or `plan:{plan}`        | `forbidden_capability` | `capability_not_granted` |
| 5–8         | `kill_switch` rows                                   | `capability_disabled`  | `kill_switch_*`          |


**Plan tier ranks:** `starter` < `standard` < `professional` < `enterprise`.

Worker hardcodes `minimumPlanTier: "standard"` in preAccept — enroll with `plan: starter` fails even after entitle.

**Three gates must align at entitle time:**

1. `allowed_capabilities` contains the capability id
2. A matching `capability_grant` row exists
3. `plan` tier meets manifest minimum

**AAT scope, staff role, and manifest `killSwitchFlag` are not this table.** Guard stage 3 (`evaluateEntitlement`) does not receive Access fields. When the resolved manifest's `Access.requiredCapabilityScope` is a non-empty string, capability resolve (guard stage 5) requires it in `principal.scopes` or returns `forbidden_capability`. Unset or empty `requiredCapabilityScope` is not rejected on scope. When `Access.allowedStaffRoles` is a non-empty array, capability resolve requires `principal.role` membership or returns `forbidden_capability`. Unset or empty `allowedStaffRoles` is not rejected on role. When `Access.killSwitchFlag === true`, capability resolve returns `capability_disabled` alongside the D1 `kill_switch` table; `false` or omitted does not disable.



## 5. Failure paths


| HTTP | `error`                  | Trigger                                  |
| ---- | ------------------------ | ---------------------------------------- |
| 404  | `installation_not_found` | No `installation` row                    |
| 404  | `entitlement_not_found`  | No `entitlement` row                     |
| 409  | `not_pending`            | `status !== 'pending'`                   |
| 400  | `invalid_payload`        | Bad numbers, empty `grants`, bad `scope`, non-ISO `period_start`/`period_end`, or `period_start >= period_end` |
| 500  | `storage_error`          | D1 batch failure                         |




## 6. Example entitle payload (visit summary)

```json
{
  "period_start": "2026-08-01T00:00:00.000Z",
  "period_end": "2026-09-01T00:00:00.000Z",
  "request_quota": 1000,
  "token_budget": 500000,
  "cost_budget": 50.0,
  "soft_threshold": 0.8,
  "allowed_capabilities": ["clinic.visit_summary"],
  "grants": [
    {
      "capability_id": "clinic.visit_summary",
      "capability_version": "1.0.0",
      "scope": "installation"
    }
  ]
}
```
