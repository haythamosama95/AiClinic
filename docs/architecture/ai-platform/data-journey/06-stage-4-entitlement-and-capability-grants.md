# AI Platform Data Journey — Stage 4 — Entitlement and capability grants

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [API: `POST /control/installations/{installation_id}/entitle`](#3-api-post-controlinstallationsinstallation_identitle)
   - [Request body — every field](#request-body-every-field)
   - [Success response (200)](#success-response-200)
   - [D1 writes](#d1-writes)
4. [Runtime entitlement checks (guard stage 3)](#4-runtime-entitlement-checks-guard-stage-3)
5. [Failure paths (entitle)](#5-failure-paths-entitle)
6. [Example entitle payload (visit summary)](#6-example-entitle-payload-visit-summary)
7. [API: `POST /control/capabilities/{capability_id}/versions/{version}/activate`](#7-api-post-controlcapabilitiescapability_idversionsversionactivate)
   - [Request body](#request-body)
   - [Success response (200)](#success-response-200-1)
   - [D1 writes](#d1-writes-1)
   - [Failure paths](#failure-paths)
8. [API: `POST /control/capabilities/{capability_id}/versions/{version}/promote`](#8-api-post-controlcapabilitiescapability_idversionsversionpromote)
   - [Request body](#request-body-1)
   - [Success response (200)](#success-response-200-2)
   - [D1 writes](#d1-writes-2)
   - [Failure paths](#failure-paths-1)
9. [API: `POST /control/capabilities/{capability_id}/versions/{version}/deprecate`](#9-api-post-controlcapabilitiescapability_idversionsversiondeprecate)
   - [Request body](#request-body-2)
   - [Success response (200)](#success-response-200-3)
   - [D1 writes](#d1-writes-3)
   - [Overlap window](#overlap-window)
   - [Failure paths](#failure-paths-2)
10. [API: `POST /control/capabilities/{capability_id}/versions/{version}/retire`](#10-api-post-controlcapabilitiescapability_idversionsversionretire)
   - [Request body](#request-body-3)
   - [Success response (200)](#success-response-200-4)
   - [D1 writes](#d1-writes-4)
   - [Failure paths](#failure-paths-3)
11. [Behavioral verification](#11-behavioral-verification)
   - [11.1 Setup](#111-setup)
   - [11.2 Coverage](#112-coverage)
   - [11.3 Ordered probes](#113-ordered-probes)
     - [11.3.1 Confirm Stage 3 pending sentinel](#1131-confirm-stage-3-pending-sentinel)
     - [11.3.2 Who may not call entitle](#1132-who-may-not-call-entitle)
     - [11.3.3 Entitle failure paths](#1133-entitle-failure-paths)
     - [11.3.4 Runtime while pending](#1134-runtime-while-pending)
     - [11.3.5 First entitle (visit-summary payload)](#1135-first-entitle-visit-summary-payload)
     - [11.3.6 Re-entitle is not pending](#1136-re-entitle-is-not-pending)
     - [11.3.7 Independent runtime switches](#1137-independent-runtime-switches)
     - [11.3.8 Access role and scope](#1138-access-role-and-scope)
     - [11.3.9 Kill-switch row](#1139-kill-switch-row)
     - [11.3.10 What entitle does not do](#11310-what-entitle-does-not-do)
     - [11.3.11 Unique entitlement per installation](#11311-unique-entitlement-per-installation)
     - [11.3.12 Cohort activate](#11312-cohort-activate)
     - [11.3.13 Cohort promote](#11313-cohort-promote)
     - [11.3.14 Deprecate with successor](#11314-deprecate-with-successor)
     - [11.3.15 Retire after overlap window](#11315-retire-after-overlap-window)

---




## 1. Plain language

The **control-plane caller** runs four kinds of grant work after [Stage 3 enroll](05-stage-3-platform-installation-enrollment.md):

1. **Entitle** (`POST …/entitle`) — turn on spend rights: billing period, quotas, allowed capabilities, and grant rows. One-shot: only works when entitlement is `pending`.
2. **Activate** (`POST …/activate`) — move a **named cohort** (list of installation ids) onto a specific capability build version. Everyone else keeps the old version until promote.
3. **Promote** (`POST …/promote`) — move **all entitled** installations onto that version and end the split.
4. **Deprecate / retire** (`POST …/deprecate`, `POST …/retire`) — mark a capability version deprecated with a announced successor, then retire it after a fixed overlap window.

## 2. Metaphor

The **ticket office opens** (entitle) — prepaid card and permission slips. **Canary boarding** (activate) lets some gates use a new aircraft type while others keep the old one. **Fleet-wide upgrade** (promote) puts every entitled airline on the new type. **Phase-out** (deprecate → retire) announces the replacement, keeps the old type flyable for a grace period, then grounds it.

## 3. API: `POST /control/installations/{installation_id}/entitle`

**Auth:** `Authorization: Bearer <OPERATOR_BEARER_TOKEN>` (`requireOperator` in `control/http.ts`).

**Handler:** `control/entitle.ts`.



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
time (`requestsUsed += 1`, `tokensUsed += provider tokens`, `costUsed += platform cost units`).


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



## 5. Failure paths (entitle)


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

## 7. API: `POST /control/capabilities/{capability_id}/versions/{version}/activate`

**Auth:** operator bearer (same as entitle).

**Handler:** `control/cohort.ts` → `handleCohortActivate`.

**Purpose:** Give a **named cohort** (explicit installation ids) a specific capability build version. Installations **not** in the list keep whatever version their grant row already has.

#### Request body


| Field               | Required | Meaning                                                                 |
| ------------------- | -------- | ----------------------------------------------------------------------- |
| `installation_ids`  | yes      | Non-empty array of installation ids that receive `{version}`            |
| `cohort_name`       | no       | Operator label for audit `target` (appended after `:` when present)     |


**Example:**

```json
{
  "installation_ids": ["<I0>"],
  "cohort_name": "pilot-clinics"
}
```

#### Success response (200)

Empty JSON object:

```json
{}
```

#### D1 writes

For each `installation_id` in the body:

1. If a live grant exists (`scope = installation:{id}`, same `capability_id`, `revoked_at IS NULL`) → **UPDATE** `capability_version`, `changed_at`, `changed_by`.
2. Otherwise → **INSERT** a new `capability_grant` row at `installation:{id}` with `{version}`.

Then **INSERT** `control_audit`:

| Column           | Value                                                                 |
| ---------------- | --------------------------------------------------------------------- |
| `action`         | `cohort_activate`                                                     |
| `target`         | `{capability_id}@{version}` or `{capability_id}@{version}:{cohort_name}` |
| `before_pointer` | JSON map `{ "<installation_id>": "<prior_version>" \| null, … }` when any prior version existed; otherwise `NULL` |
| `after_pointer`  | `{version}` (string)                                                  |

**Not updated:** `entitlement`, `routing_policy`, manifest bytes, clinic Postgres.

#### Failure paths


| HTTP | `error`                    | Trigger                                              |
| ---- | -------------------------- | ---------------------------------------------------- |
| 401  | `unauthorized`             | Missing / wrong operator bearer                      |
| 400  | `invalid_json`             | Body is not valid JSON                               |
| 400  | `missing_installation_ids` | `installation_ids` missing, not an array, or empty   |
| 404  | `capability_not_found`     | `{capability_id}@{version}` not in Worker registry   |
| 404  | `installation_not_found`   | Any listed installation id has no `installation` row |
| 500  | `storage_error`            | D1 batch failure                                     |

## 8. API: `POST /control/capabilities/{capability_id}/versions/{version}/promote`

**Auth:** operator bearer.

**Handler:** `control/cohort.ts` → `handleCohortPromote`.

**Purpose:** End a staged split. Every **entitled** installation (`entitlement.status = 'active'` and `allowed_capabilities` contains the capability id) receives `{version}`. Plan-scoped grants are updated or created for each distinct `plan` on those entitlements. Installations that had no live grant get a new installation-scoped grant.

#### Request body

No body required. Send `{}` or an empty body.

#### Success response (200)

```json
{}
```

#### D1 writes

1. **UPDATE** every live `capability_grant` for this `capability_id` where `scope` is `installation:*` or `plan:*` and `revoked_at IS NULL` → set `capability_version = {version}`.
2. For each active entitlement that allows this capability: upsert `plan:{plan}` grant if missing; upsert `installation:{id}` grant if the installation had no live installation grant.
3. **INSERT** `control_audit`:

| Column           | Value                                                                 |
| ---------------- | --------------------------------------------------------------------- |
| `action`         | `cohort_promote`                                                      |
| `target`         | `{capability_id}@{version}`                                           |
| `before_pointer` | JSON `{ "installation": [{scope, version}, …], "plan": [{scope, version}, …] }` snapshot before the batch |
| `after_pointer`  | `{version}`                                                           |

#### Failure paths


| HTTP | `error`                | Trigger                                        |
| ---- | ---------------------- | ---------------------------------------------- |
| 401  | `unauthorized`         | Missing / wrong operator bearer                |
| 404  | `capability_not_found` | `{capability_id}@{version}` not in registry    |
| 500  | `storage_error`        | D1 batch failure                               |

## 9. API: `POST /control/capabilities/{capability_id}/versions/{version}/deprecate`

**Auth:** operator bearer.

**Handler:** `control/capability-lifecycle.ts` → `handleDeprecate`.

**Purpose:** Mark a capability **version** deprecated and announce a **successor**. The version stays servable until an operator retires it after the overlap window. Lifecycle is stored as a **global overlay** on `capability_grant` — manifests are never edited.

#### Request body


| Field          | Required | Meaning                                                                 |
| -------------- | -------- | ----------------------------------------------------------------------- |
| `successor_id` | yes      | Successor capability id (e.g. `clinic.visit_summary` or `id@version`)   |


**Example:**

```json
{
  "successor_id": "clinic.visit_summary"
}
```

`successor_id` must be known to the in-memory registry: either `capabilityId@version` or a `capabilityId` that has at least one registered version.

#### Success response (200)

```json
{}
```

When the version is **already** deprecated with the **same** `successor_id`, the handler returns `200 {}` without inserting a new overlay (idempotent).

#### D1 writes

1. **INSERT** `capability_grant` overlay row:

| Column            | Value                                      |
| ----------------- | ------------------------------------------ |
| `scope`           | `global`                                   |
| `capability_id`   | path `capability_id`                       |
| `capability_version` | path `version`                          |
| `lifecycle_state` | `deprecated`                               |
| `successor_id`    | body `successor_id`                        |
| `deprecated_at`   | mutation instant (ISO-8601)                |
| `retire_after`    | `deprecated_at + 90 days` (see below)      |
| `revoked_at`      | same as `changed_at` (overlay, not a live grant) |
| `granted_at`      | same as `changed_at` (A5 `NOT NULL`)       |

2. **INSERT** `control_audit` — `action='deprecate'`, `target='{capability_id}@{version}'`, `after_pointer=successor_id`.

#### Overlap window

| Constant              | Value   | Code reference                          |
| --------------------- | ------- | --------------------------------------- |
| `OVERLAP_WINDOW_MS`   | 90 days | `capability/index.ts`                   |

On deprecate, `retire_after = deprecated_at + 90 days`. The request path does **not** auto-retire when the clock passes `retire_after`; only `POST …/retire` enforces retirement.

While deprecated and inside the window, `resolve()` still serves the manifest; `discover()` includes it with `lifecycleState: deprecated` and the successor id.

#### Failure paths


| HTTP | `error`              | Trigger                                                                 |
| ---- | -------------------- | ----------------------------------------------------------------------- |
| 401  | `unauthorized`       | Missing / wrong operator bearer                                         |
| 400  | `invalid_json`       | Body is not valid JSON                                                  |
| 400  | `missing_successor_id` | Empty / missing `successor_id`                                        |
| 400  | `unknown_successor`  | `successor_id` not in registry                                          |
| 404  | `capability_not_found` | `{capability_id}@{version}` not in registry                           |
| 409  | `already_retired`    | Latest global overlay is `retired`                                      |
| 409  | `already_deprecated` | Already deprecated with a **different** `successor_id`                  |
| 500  | `storage_error`      | D1 batch failure                                                        |

## 10. API: `POST /control/capabilities/{capability_id}/versions/{version}/retire`

**Auth:** operator bearer.

**Handler:** `control/capability-lifecycle.ts` → `handleRetire`.

**Purpose:** After deprecation and the overlap window, permanently retire a capability version. `resolve()` then returns `capability_retired`; `discover()` omits the version.

#### Request body

Empty JSON `{}`. No fields.

#### Success response (200)

```json
{}
```

#### D1 writes

1. **INSERT** global overlay with `lifecycle_state = 'retired'`, carrying `successor_id`, `deprecated_at`, and `retire_after` from the prior deprecate overlay. `revoked_at = changed_at` (overlay row).
2. **INSERT** `control_audit` — `action='retire'`, `target='{capability_id}@{version}'`, `after_pointer=successor_id`.

#### Failure paths


| HTTP | `error`                  | Trigger                                                                 |
| ---- | ------------------------ | ----------------------------------------------------------------------- |
| 401  | `unauthorized`           | Missing / wrong operator bearer                                         |
| 400  | `invalid_json`           | Body is not valid JSON (if body sent)                                   |
| 400  | `not_deprecated`         | No prior global overlay with `lifecycle_state = deprecated` and successor |
| 400  | `overlap_window_active`  | Current time `< retire_after`, or `retire_after` unparseable            |
| 404  | `capability_not_found`   | `{capability_id}@{version}` not in registry                             |
| 500  | `storage_error`          | D1 batch failure                                                        |

After a successful retire, `POST …/deprecate` on the same pin returns `409 already_retired`.

## 11. Behavioral verification

Live probes against a local Worker and an installation that already completed [Stage 3 enroll](05-stage-3-platform-installation-enrollment.md). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§11.3](#113-ordered-probes) top to bottom** on a throwaway local D1. If every probe matches, this stage is working.

Control-plane JSON uses `{ "error": "<code>" }`. Runtime `POST /v1/requests` JSON uses taxonomy `{ "code": "<code>", "request_reference": "…", "trace_id": "…", "retry_safe": <bool> }` (`control/http.ts` `reject` / `unauthorized` vs `errors.ts` `buildErrorBody`). The rejection **path** (`ai_disabled`, `plan_tier`, `capability_not_granted`, `kill_switch_*`) is Worker-log only — confirm it with D1 state, not the HTTP body.

The isolate `ConfigCache` TTL is 30 s. After any **D1 SQL** mutation (and after [§11.3.4](#1134-runtime-while-pending) has cached a `pending` row), restart `npm run dev` or wait 30 s before the next `/v1` probe.

### 11.1 Setup

- Local Worker (`cd ai-platform && npm run dev`) at `http://127.0.0.1:8787`. `OPERATOR_BEARER_TOKEN` from `.dev.vars.development`. `OPERATOR_ID` is `platform-operator` (`wrangler.toml` `[env.development.vars]`).
- One **already-enrolled** installation from Stage 3: D1 `installation` row, `installation_key`, entitlement **`pending`** with zero quotas and `allowed_capabilities = '[]'`. Save that id as **I0**.
- Entitlement `plan` must be a closed-set tier (`starter` / `standard` / `professional` / `enterprise`). Unknown strings (for example Stage 2’s sample `"verify"`) fail closed at runtime (`plan_tier`). For visit-summary probes that must pass guard stage 3, set `plan` to `professional` (or `standard` / `enterprise`) **before** entitle — entitle does not write `plan`.
- Clinic Supabase with the Stage 2 keypair whose `installation_id` is **I0**. A **doctor** session that can `issue_ai_token` (RBAC `ai.access` is enough to mint; visit-summary Access fields are a later probe).
- SQL as `postgres` only to mint AATs and inspect clinic tables. D1 inspection via wrangler.
- **Registry note:** local development ships one visit-summary build — `clinic.visit_summary@1.0.0`. Probes that need a **second** registered version (cohort split onto `2.0.0`) are marked **Unprobeable** until a second manifest is deployed to the Worker.

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export INSTALLATION_ID='<I0>'
export CAP='clinic.visit_summary'
export VER='1.0.0'
export AAT='<compact JWS from issue_ai_token>'

d1() {
  npx wrangler d1 execute ai-platform-development --local --env development --command "$1"
}

entitle() {
  curl -sS -w '\nHTTP %{http_code}\n' -X POST \
    "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
    -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$1"
}

cohort_activate() {
  local ver="${1:-$VER}"
  local body="${2:-{\"installation_ids\":[\"$INSTALLATION_ID\"]}}"
  curl -sS -w '\nHTTP %{http_code}\n' -X POST \
    "$GATEWAY/control/capabilities/$CAP/versions/$ver/activate" \
    -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$body"
}

cohort_promote() {
  local ver="${1:-$VER}"
  curl -sS -w '\nHTTP %{http_code}\n' -X POST \
    "$GATEWAY/control/capabilities/$CAP/versions/$ver/promote" \
    -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}'
}

deprecate() {
  local ver="${1:-$VER}"
  local successor="${2:-clinic.visit_summary}"
  curl -sS -w '\nHTTP %{http_code}\n' -X POST \
    "$GATEWAY/control/capabilities/$CAP/versions/$ver/deprecate" \
    -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"successor_id\":\"$successor\"}"
}

retire() {
  local ver="${1:-$VER}"
  curl -sS -w '\nHTTP %{http_code}\n' -X POST \
    "$GATEWAY/control/capabilities/$CAP/versions/$ver/retire" \
    -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}'
}

# Guard failures return HTTP JSON (pre-accept). SSE Accept is not required.
visit_post() {
  local ver="${1:-1.0.0}"
  local cap="${2:-clinic.visit_summary}"
  curl -sS -w '\nHTTP %{http_code}\n' -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $AAT" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $(python3 -c 'import uuid; print(uuid.uuid4())')" \
    -H "x-capability-version: $ver" \
    -d "{
      \"capability_id\": \"$cap\",
      \"user_intent\": \"Summarize today's visit for the chart.\",
      \"context\": {
        \"org\": \"probe\",
        \"branch\": \"probe\",
        \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\"
      }
    }"
}
```

Mint `AAT` as doctor:

```sql
SELECT set_config('role', 'authenticated', true);
SELECT set_config(
  'request.jwt.claims',
  json_build_object('sub', '<doctor auth_user_id>'::text, 'role', 'authenticated')::text,
  true
);
SELECT public.issue_ai_token();
```

Reset `role` to `postgres` before inspecting `ai_internal`. Decode the JWS payload: `iss` must equal **I0**; `role` is `doctor`; `scopes` includes `ai.access` (seeded) and does **not** include `ai.visit_summary`.

### 11.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Stage 3 enroll leaves entitlement `pending`, quotas `0`, `allowed_capabilities = []`, `soft_threshold = 0` | [§11.3.1](#1131-confirm-stage-3-pending-sentinel) |
| `plan` is stored at enroll; entitle does not change it | [§11.3.1](#1131-confirm-stage-3-pending-sentinel), [§11.3.5](#1135-first-entitle-visit-summary-payload) |
| Closed plan ranks: unknown / `starter` fail `minimumPlanTier: "standard"` even after entitle | [§11.3.1](#1131-confirm-stage-3-pending-sentinel), [§11.3.7](#1137-independent-runtime-switches) |
| Only `OPERATOR_BEARER_TOKEN` may call entitle; missing/wrong/AAT bearer → HTTP 401 `{ "error": "unauthorized" }` | [§11.3.2](#1132-who-may-not-call-entitle) |
| Clinic staff / Flutter / `issue_ai_token` cannot entitle | [§11.3.2](#1132-who-may-not-call-entitle) |
| No `installation` row → HTTP 404 `installation_not_found` | [§11.3.3](#1133-entitle-failure-paths) |
| No `entitlement` row → HTTP 404 `entitlement_not_found` | [§11.3.3](#1133-entitle-failure-paths) |
| `status !== 'pending'` → HTTP 409 `not_pending` | [§11.3.6](#1136-re-entitle-is-not-pending) |
| Bad numbers, empty `grants`, bad `scope`, non-ISO period, `period_start >= period_end` → HTTP 400 `invalid_payload`; row unchanged | [§11.3.3](#1133-entitle-failure-paths) |
| HTTP 500 `storage_error` (D1 batch failure) | **Unprobeable** — requires a live D1 `batch` exception |
| Pending runtime → HTTP 403 `forbidden_capability` (`ai_disabled`); no spend rights yet | [§11.3.4](#1134-runtime-while-pending) |
| [§6](#6-example-entitle-payload-visit-summary) body: every request field; HTTP 200 `{ installation_id, status: "active" }` | [§11.3.5](#1135-first-entitle-visit-summary-payload) |
| D1 `UPDATE entitlement` writes every budget column + `allowed_capabilities` JSON + `status='active'` | [§11.3.5](#1135-first-entitle-visit-summary-payload) |
| D1 `INSERT capability_grant` per grant: `scope = installation:{id}`, version, `revoked_at` NULL, `changed_by = OPERATOR_ID` | [§11.3.5](#1135-first-entitle-visit-summary-payload) |
| D1 `INSERT control_audit` `action='entitle'`, `after_pointer` = allowed-capabilities JSON | [§11.3.5](#1135-first-entitle-visit-summary-payload) |
| Not updated: `entitlement.plan`, `installation.status` | [§11.3.5](#1135-first-entitle-visit-summary-payload) |
| One-shot: second entitle is not idempotent → 409 `not_pending` | [§11.3.6](#1136-re-entitle-is-not-pending) |
| Independent switch: `allowed_capabilities` omits id → `forbidden_capability` (`capability_not_granted`) | [§11.3.7](#1137-independent-runtime-switches) |
| Independent switch: matching grant missing / wrong version → same code | [§11.3.7](#1137-independent-runtime-switches) |
| Independent switch: `plan` below `standard` (or unknown) → `forbidden_capability` (`plan_tier`) | [§11.3.7](#1137-independent-runtime-switches) |
| Independent switch: `status` `suspended` (or any non-`active`) → `forbidden_capability` (`ai_disabled`) | [§11.3.7](#1137-independent-runtime-switches) |
| Grant at `plan:{plan}` satisfies check 4 when installation-scope grant is absent | [§11.3.7](#1137-independent-runtime-switches) |
| Three gates must align before guard stage 3 returns ok | [§11.3.7](#1137-independent-runtime-switches) |
| `evaluateEntitlement` does not receive Access; wrong `principal.scopes` → HTTP 403 `forbidden_capability` | [§11.3.8](#1138-access-role-and-scope) |
| Wrong `principal.role` vs `Access.allowedStaffRoles` → HTTP 403 `forbidden_capability` | [§11.3.8](#1138-access-role-and-scope) |
| Unset/empty `requiredCapabilityScope` or `allowedStaffRoles` skip those checks | **Unprobeable** with published visit-summary — both Access fields are non-empty; [§11.3.8](#1138-access-role-and-scope) exercises the reject path only |
| D1 `kill_switch` active → HTTP 503 `capability_disabled` | [§11.3.9](#1139-kill-switch-row) |
| Manifest `Access.killSwitchFlag === true` | **Unprobeable** — visit-summary bundle has `false`; flipping it needs a Worker redeploy |
| Manifest `killSwitchFlag` `false` / omitted does not disable | **Unprobeable** as a positive — visit-summary is `false`, but clinic AATs never pass Access to prove the skip |
| Entitle does not publish routing policy, mint AATs, enroll, or write clinic Postgres | [§11.3.10](#11310-what-entitle-does-not-do) |
| `UNIQUE (installation_id)` — a second entitlement row cannot be inserted | [§11.3.11](#11311-unique-entitlement-per-installation) |
| Three period ceilings → `quota_exhausted` when any counter is already at its limit | **Unprobeable** with clinic-minted AATs — admission is guard stage 8; visit-summary `Access.allowedStaffRoles` is `clinician`/`nurse`, which are not `public.staff_role` values, so `issue_ai_token` never reaches the Quota DO |
| `soft_threshold` admits but marks `degraded` / `routing_tier = degraded` / `degraded_notice` | **Unprobeable** — same stage-5 Access block |
| Activate: non-operator → 401, no D1 writes | [§11.3.12](#11312-cohort-activate) |
| Activate: empty `installation_ids` → 400 `missing_installation_ids` | [§11.3.12](#11312-cohort-activate) |
| Activate: unknown installation → 404 `installation_not_found` | [§11.3.12](#11312-cohort-activate) |
| Activate: unregistered version → 404 `capability_not_found` | [§11.3.12](#11312-cohort-activate) |
| Activate: upserts grant + `cohort_activate` audit with `before_pointer` / `after_pointer` | [§11.3.12](#11312-cohort-activate) |
| Activate: optional `cohort_name` on audit `target` | [§11.3.12](#11312-cohort-activate) |
| Cohort split (cohort on new build, others on old) | **Unprobeable** — local registry has only `clinic.visit_summary@1.0.0` |
| Promote: non-operator → 401; unknown version → 404 | [§11.3.13](#11313-cohort-promote) |
| Promote: updates all live grants + entitled missing grants + `cohort_promote` audit | [§11.3.13](#11313-cohort-promote) |
| Deprecate: missing / unknown successor → 400; unregistered pin → 404 | [§11.3.14](#11314-deprecate-with-successor) |
| Deprecate: global overlay `deprecated`, `retire_after = deprecated_at + 90d`, audit `after_pointer` = successor | [§11.3.14](#11314-deprecate-with-successor) |
| Deprecate: same successor idempotent 200; different successor → 409 `already_deprecated` | [§11.3.14](#11314-deprecate-with-successor) |
| Deprecate after retire → 409 `already_retired` | [§11.3.15](#11315-retire-after-overlap-window) |
| Retire without deprecate → 400 `not_deprecated` | [§11.3.15](#11315-retire-after-overlap-window) |
| Retire inside overlap window → 400 `overlap_window_active` | [§11.3.15](#11315-retire-after-overlap-window) |
| Retire after window → overlay `retired`, audit `action='retire'` | [§11.3.15](#11315-retire-after-overlap-window) |
| Deprecated version still servable inside window (no auto-retire) | **Unprobeable** — same Access role block as [§11.3.8](#1138-access-role-and-scope) for `/v1` |
| Retired version omitted from discovery | **Unprobeable** — same Access block; confirm overlay + audit in [§11.3.15](#11315-retire-after-overlap-window) |

### 11.3 Ordered probes

#### 11.3.1 Confirm Stage 3 pending sentinel

**Do:**

```bash
cd ai-platform
d1 "SELECT installation_id, status FROM installation WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT plan, status, period_start, period_end, request_quota, token_budget, cost_budget,
           allowed_capabilities, soft_threshold
    FROM entitlement WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT COUNT(*) AS grants FROM capability_grant
    WHERE scope = 'installation:$INSTALLATION_ID'"
```

**Expect:** one `installation` row, `status = 'active'`. One entitlement row, `status = 'pending'`, `request_quota = 0`, `token_budget = 0`, `cost_budget = 0`, `allowed_capabilities = '[]'`, `soft_threshold = 0`. Zero grant rows. `period_start` equals `period_end` (enroll placeholders).

If `plan` is not `standard`, `professional`, or `enterprise`, **do**:

```bash
d1 "UPDATE entitlement SET plan = 'professional' WHERE installation_id = '$INSTALLATION_ID'"
```

**Expect:** later runtime checks use that stored plan. Entitle will not overwrite it.

#### 11.3.2 Who may not call entitle

**Do:** POST entitle with [§6](#6-example-entitle-payload-visit-summary) JSON and **no** `Authorization` header.

**Expect:** HTTP 401, `{ "error": "unauthorized" }`. Entitlement still `pending`; grant count still 0 (`requireOperator` in `control/auth.ts`).

**Do:** same POST with `Authorization: Bearer definitely-wrong`.

**Expect:** HTTP 401, `{ "error": "unauthorized" }`. Timing-safe compare against `OPERATOR_BEARER_TOKEN` failed.

**Do:** same POST with `Authorization: Bearer $AAT` (clinic staff token from `issue_ai_token`).

**Expect:** HTTP 401, `{ "error": "unauthorized" }`. An AAT is not the operator secret. Clinic staff / Flutter cannot call this route.

#### 11.3.3 Entitle failure paths

Use a valid operator bearer. After each probe, entitlement must still be `pending` with zero grants.

**Do:** path installation id that does not exist:

```bash
curl -sS -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/installations/00000000-0000-0000-0000-000000000000/entitle" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @- <<'EOF'
{ "period_start": "2026-08-01T00:00:00.000Z", "period_end": "2026-09-01T00:00:00.000Z",
  "request_quota": 1000, "token_budget": 500000, "cost_budget": 50.0, "soft_threshold": 0.8,
  "allowed_capabilities": ["clinic.visit_summary"],
  "grants": [{ "capability_id": "clinic.visit_summary", "capability_version": "1.0.0", "scope": "installation" }] }
EOF
```

**Expect:** HTTP 404, `{ "error": "installation_not_found" }`.

**Do:** save the pending entitlement row, delete it, entitle **I0**, then restore:

```bash
d1 "SELECT * FROM entitlement WHERE installation_id = '$INSTALLATION_ID'"
d1 "DELETE FROM entitlement WHERE installation_id = '$INSTALLATION_ID'"
entitle "$(cat <<'EOF'
{ "period_start": "2026-08-01T00:00:00.000Z", "period_end": "2026-09-01T00:00:00.000Z",
  "request_quota": 1000, "token_budget": 500000, "cost_budget": 50.0, "soft_threshold": 0.8,
  "allowed_capabilities": ["clinic.visit_summary"],
  "grants": [{ "capability_id": "clinic.visit_summary", "capability_version": "1.0.0", "scope": "installation" }] }
EOF
)"
```

**Expect:** HTTP 404, `{ "error": "entitlement_not_found" }` (installation exists; entitlement does not). Re-insert the saved row before continuing (same `entitlement_id`, `plan`, pending zeros).

**Do:** each of these bodies against **I0** (operator bearer). Expect HTTP 400 `{ "error": "invalid_payload" }` and an unchanged pending row after every attempt:

| Variant | Body change |
| ------- | ----------- |
| Non-ISO `period_start` | `"period_start": "not-an-iso-instant"` |
| Date-only `period_start` | `"period_start": "2026-08-01"` |
| Non-ISO `period_end` | `"period_end": "tomorrow"` |
| `period_start == period_end` | both `"2026-08-01T00:00:00.000Z"` |
| `period_start > period_end` | start `"2026-09-01T00:00:00.000Z"`, end `"2026-08-01T00:00:00.000Z"` |
| `request_quota` not an integer ≥ 0 | `"request_quota": -1` or `1.5` |
| `token_budget` not an integer ≥ 0 | `"token_budget": -1` |
| `cost_budget` not finite ≥ 0 | `"cost_budget": -1` |
| `soft_threshold` not ∈ [0, 1] | `"soft_threshold": 1.5` |
| `allowed_capabilities` not string[] | `"allowed_capabilities": [1]` |
| Empty `grants` | `"grants": []` |
| Missing `capability_id` / empty string | `"grants": [{ "capability_version": "1.0.0" }]` |
| Bad `scope` | `"scope": "global"` (only `installation` / `plan` / omitted are legal) |

Copy the [§6](#6-example-entitle-payload-visit-summary) JSON and change one field at a time. `grants` must stay a non-empty array except for the empty-`grants` row.

#### 11.3.4 Runtime while pending

Do **not** entitle yet. Restart the Worker if you already POSTed `/v1` during earlier setup.

**Do:** `visit_post`

**Expect:** HTTP 403, `"code": "forbidden_capability"`, `"retry_safe": false`. Guard stage 3: `entitlement.status !== 'active'` → path `ai_disabled`. Identity can pass (Stage 3 registered the key). This stage has not granted quotas or capabilities.

#### 11.3.5 First entitle (visit-summary payload)

**Do:** POST the **exact** [§6](#6-example-entitle-payload-visit-summary) body:

```bash
entitle "$(cat <<'EOF'
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
EOF
)"
```

**Expect:** HTTP 200:

```json
{ "installation_id": "<I0>", "status": "active" }
```

Every request field from the [§3](#3-api-post-controlinstallationsinstallation_identitle) table is in that body. Success body has only `installation_id` and `status`.

**Do:**

```bash
d1 "SELECT plan, period_start, period_end, request_quota, token_budget, cost_budget,
           allowed_capabilities, soft_threshold, status
    FROM entitlement WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT status FROM installation WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT scope, capability_id, capability_version, revoked_at, changed_by
    FROM capability_grant WHERE scope = 'installation:$INSTALLATION_ID'"
d1 "SELECT operator_id, action, target, after_pointer
    FROM control_audit WHERE action = 'entitle' AND target = '$INSTALLATION_ID'"
```

**Expect:**

| Store | Value |
| ----- | ----- |
| `entitlement.period_start` | `2026-08-01T00:00:00.000Z` |
| `entitlement.period_end` | `2026-09-01T00:00:00.000Z` |
| `entitlement.request_quota` | `1000` |
| `entitlement.token_budget` | `500000` |
| `entitlement.cost_budget` | `50` |
| `entitlement.soft_threshold` | `0.8` |
| `entitlement.allowed_capabilities` | `["clinic.visit_summary"]` (JSON string) |
| `entitlement.status` | `active` |
| `entitlement.plan` | **unchanged** from [§11.3.1](#1131-confirm-stage-3-pending-sentinel) (still `professional` if you set it) |
| `installation.status` | `active` (unchanged) |
| `capability_grant.scope` | `installation:<I0>` |
| `capability_grant.capability_id` | `clinic.visit_summary` |
| `capability_grant.capability_version` | `1.0.0` |
| `capability_grant.revoked_at` | `NULL` |
| `capability_grant.changed_by` | `platform-operator` |
| `control_audit.action` | `entitle` |
| `control_audit.target` | **I0** |
| `control_audit.operator_id` | `platform-operator` |
| `control_audit.after_pointer` | `["clinic.visit_summary"]` |

Omitting `grants[].scope` uses the same D1 scope (`installation:{id}`); [§6](#6-example-entitle-payload-visit-summary) sends it explicitly.

Restart the Worker (or wait 30 s) so `/v1` does not keep the cached `pending` snapshot from [§11.3.4](#1134-runtime-while-pending).

#### 11.3.6 Re-entitle is not pending

**Do:** repeat the exact [§11.3.5](#1135-first-entitle-visit-summary-payload) POST.

**Expect:** HTTP 409, `{ "error": "not_pending" }`. One-shot: reuse is **not** idempotent. Grant row count unchanged (no second insert). `status` stays `active`.

#### 11.3.7 Independent runtime switches

Each flip is a D1 write, then Worker restart (or 30 s), then `visit_post`, then restore before the next flip. HTTP is always 403 `forbidden_capability` unless noted. Confirm which check fired from D1, not from the JSON `code`.

**Do:** omit the capability from the allow-list (grant row left in place):

```bash
d1 "UPDATE entitlement SET allowed_capabilities = '[]' WHERE installation_id = '$INSTALLATION_ID'"
```

**Expect:** HTTP 403 `forbidden_capability` (check 3, path `capability_not_granted`). Restore `allowed_capabilities` to `["clinic.visit_summary"]`.

**Do:** restore allow-list, delete the grant:

```bash
d1 "DELETE FROM capability_grant WHERE scope = 'installation:$INSTALLATION_ID'"
```

**Expect:** HTTP 403 `forbidden_capability` (check 4, path `capability_not_granted`). Allow-list alone is not enough.

**Do:** while the installation grant is still missing, insert a **plan-scope** grant (use the live `plan` value, e.g. `professional`):

```bash
d1 "INSERT INTO capability_grant (
      grant_id, scope, capability_id, capability_version,
      granted_at, revoked_at, changed_at, changed_by
    ) VALUES (
      'probe-plan-grant', 'plan:professional', 'clinic.visit_summary', '1.0.0',
      datetime('now'), NULL, datetime('now'), 'probe'
    )"
```

**Expect:** guard stage 3 now finds a grant (`plan:{plan}`). The HTTP 403 you still see is Access role/scope at guard stage 5 ([§11.3.8](#1138-access-role-and-scope)) — **not** `capability_not_granted`. Delete `probe-plan-grant` and re-insert the installation-scope grant from [§11.3.5](#1135-first-entitle-visit-summary-payload) (`scope = installation:<I0>`, same capability/version) before continuing.

**Do:** installation grant present, POST with `visit_post 9.9.9` (`x-capability-version: 9.9.9`).

**Expect:** HTTP 403 `forbidden_capability` at **stage 3** (grant `version_mismatch` → `capability_not_granted`), not `404 capability_unknown` (registry is stage 5).

**Do:** `visit_post 1.0.0 clinic.chat_assistant` (allow-list and grant are visit-summary only).

**Expect:** HTTP 403 `forbidden_capability` (check 3, `capability_not_granted`) before capability resolve.

**Do:** `UPDATE entitlement SET plan = 'starter' WHERE installation_id = '$INSTALLATION_ID'` (allow-list + grant restored). Restart. `visit_post`.

**Expect:** HTTP 403 `forbidden_capability` (check 2, `plan_tier`). Worker `preAccept` hardcodes `minimumPlanTier: "standard"`; `starter < standard`. Repeat with `plan = 'verify'` (unknown) — same 403 `plan_tier` (fail closed). Restore `plan = 'professional'`.

**Do:** `UPDATE entitlement SET status = 'suspended' WHERE installation_id = '$INSTALLATION_ID'`. Restart. `visit_post`.

**Expect:** HTTP 403 `forbidden_capability` (check 1, `ai_disabled`). This is **entitlement** status, not `POST …/suspend` (that sets `installation.status` and fails identity as `installation_suspended` before this table). Restore `status = 'active'`.

These four switches (allow-list, grant, plan, status) fail independently. All three gates in [§4](#4-runtime-entitlement-checks-guard-stage-3) must align for stage 3 to return ok.

#### 11.3.8 Access role and scope

Leave entitlement **active** with allow-list + installation grant + `plan` ≥ `standard` (stage 3 ok). Clinic-minted AATs still fail guard stage 5. `evaluateEntitlement` does not receive Access fields.

**Do:** `visit_post` with the doctor AAT (`scopes` has `ai.access`, not `ai.visit_summary`; `role` is `doctor`).

**Expect:** HTTP 403 `forbidden_capability`. Manifest `Access.requiredCapabilityScope` is `ai.visit_summary` (non-empty → required in `principal.scopes`). Capability resolve runs **after** entitlement; this 403 is not `ai_disabled` / `capability_not_granted` — D1 entitlement is already active.

**Do:** as `postgres`, grant the missing scope on the doctor role, mint a **new** AAT, then `visit_post`:

```sql
INSERT INTO public.roles_permissions (role, permission_key, is_granted)
VALUES ('doctor', 'ai.visit_summary', true)
ON CONFLICT (role, permission_key) DO NOTHING;
```

**Expect:** HTTP 403 `forbidden_capability` still. Scope now matches; `Access.allowedStaffRoles` is `["clinician", "nurse"]` and `principal.role` is `doctor`. Unset/empty `allowedStaffRoles` would skip this check; visit-summary’s array is non-empty. `public.staff_role` has no `clinician` / `nurse` value, so `issue_ai_token` cannot mint a passing role.

Delete the extra `roles_permissions` row when finished. Empty `requiredCapabilityScope` / empty `allowedStaffRoles` “do not reject” is the inverse of these two failures; visit-summary’s published manifest is non-empty on both, so the skip path is not exercised by this capability.

#### 11.3.9 Kill-switch row

Entitlement active; allow-list + grant + plan restored. Kill-switch evaluation is checks 5–8 of [§4](#4-runtime-entitlement-checks-guard-stage-3) (`evaluateEntitlement` runs **before** capability resolve).

**Do:**

```bash
d1 "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
    VALUES ('installation', '$INSTALLATION_ID', 1, datetime('now'), 'probe')"
```

Restart. `visit_post`.

**Expect:** HTTP 503, `"code": "capability_disabled"`, `"retry_safe": true`. Path `kill_switch_installation`. One D1 row is enough; do not enumerate global / capability / provider here (same code, different `target`).

**Do:** `DELETE FROM kill_switch WHERE scope = 'installation' AND target = '$INSTALLATION_ID'`. Restart.

**Expect:** kill-switch miss is fail-open (`{ active: false }`). HTTP returns to 403 `forbidden_capability` from Access ([§11.3.8](#1138-access-role-and-scope)), not 503.

`providerId` in `preAccept` is hardcoded `"fake"`; a `provider:fake` row would also be `capability_disabled` at stage 3. Skip inserting it.

#### 11.3.10 What entitle does not do

**Do:** after [§11.3.5](#1135-first-entitle-visit-summary-payload):

```bash
d1 "SELECT COUNT(*) AS n FROM routing_policy"
```

**Expect:** the count is whatever Stage 5 (or seed) already had — entitle’s D1 batch is entitlement `UPDATE` + `capability_grant` `INSERT` + `control_audit` `INSERT` only. No routing-policy publish / canary / promote.

**Do:** as doctor, `SELECT public.issue_ai_token();`

**Expect:** a new JWS. Entitle does not mint AATs (Stage 6). The 200 body has no token.

**Do:** as doctor, `SELECT public.get_ai_availability();`

**Expect:** clinic `ai.availability` unchanged. Entitle does not write clinic Postgres and does not enroll (Stage 3 already did).

**Do:** `d1 "SELECT status FROM installation WHERE installation_id = '$INSTALLATION_ID'"`

**Expect:** still `active`. Entitle does not suspend, resume, or delete the installation.

#### 11.3.11 Unique entitlement per installation

**Do:**

```bash
d1 "INSERT INTO entitlement (
      entitlement_id, installation_id, plan, period_start, period_end,
      request_quota, token_budget, cost_budget, allowed_capabilities,
      soft_threshold, status
    ) VALUES (
      'probe-dup-entitlement', '$INSTALLATION_ID', 'professional',
      '2026-08-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z',
      0, 0, 0, '[]', 0, 'pending'
    )"
```

**Expect:** unique-index failure on `idx_entitlement_installation_id`. Still exactly one entitlement row for **I0**. Entitle’s `UPDATE … WHERE installation_id = ?` cannot silently multi-update a duplicate set.

#### 11.3.12 Cohort activate

Requires [§11.3.5](#1135-first-entitle-visit-summary-payload) complete (**I0** entitled, grant at `1.0.0`).

**Do:** `cohort_activate` with no `Authorization` header (edit the helper or use curl without the header).

**Expect:** HTTP 401 `{ "error": "unauthorized" }`. No new `control_audit` row for `cohort_activate`.

**Do:**

```bash
cohort_activate "$VER" '{"installation_ids":[]}'
```

**Expect:** HTTP 400 `{ "error": "missing_installation_ids" }`.

**Do:**

```bash
cohort_activate "$VER" '{"installation_ids":["00000000-0000-0000-0000-000000000000"]}'
```

**Expect:** HTTP 404 `{ "error": "installation_not_found" }`.

**Do:** `cohort_activate 9.9.9`

**Expect:** HTTP 404 `{ "error": "capability_not_found" }`.

**Do:** activate with cohort label (re-upserts same version — validates audit shape):

```bash
cohort_activate "$VER" "{\"installation_ids\":[\"$INSTALLATION_ID\"],\"cohort_name\":\"probe-cohort\"}"
```

**Expect:** HTTP 200 `{}`. Grant still `capability_version = 1.0.0`, `revoked_at` NULL.

**Do:**

```bash
d1 "SELECT action, target, before_pointer, after_pointer FROM control_audit
    WHERE action = 'cohort_activate' ORDER BY recorded_at DESC LIMIT 1"
d1 "SELECT capability_version, changed_by FROM capability_grant
    WHERE scope = 'installation:$INSTALLATION_ID' AND capability_id = '$CAP'"
```

**Expect:**

| Store | Value |
| ----- | ----- |
| `control_audit.action` | `cohort_activate` |
| `control_audit.target` | `clinic.visit_summary@1.0.0:probe-cohort` |
| `control_audit.before_pointer` | JSON map with **I0** → `1.0.0` |
| `control_audit.after_pointer` | `1.0.0` |
| `capability_grant.changed_by` | `platform-operator` |

**Do:** delete the installation grant, activate again without `cohort_name`:

```bash
d1 "DELETE FROM capability_grant WHERE scope = 'installation:$INSTALLATION_ID'"
cohort_activate "$VER" "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"
```

**Expect:** HTTP 200 `{}`. New **INSERT** grant row (`before_pointer` on the new audit row is `NULL` because no prior live grant existed).

#### 11.3.13 Cohort promote

**Do:** `cohort_promote` with wrong bearer.

**Expect:** HTTP 401. No `cohort_promote` audit row.

**Do:** `cohort_promote 9.9.9`

**Expect:** HTTP 404 `{ "error": "capability_not_found" }`.

**Do:** `cohort_promote` (version `1.0.0`).

**Expect:** HTTP 200 `{}`.

**Do:**

```bash
d1 "SELECT action, target, before_pointer, after_pointer FROM control_audit
    WHERE action = 'cohort_promote' ORDER BY recorded_at DESC LIMIT 1"
d1 "SELECT scope, capability_version FROM capability_grant
    WHERE capability_id = '$CAP' AND revoked_at IS NULL
    ORDER BY scope"
```

**Expect:** `cohort_promote` audit with `target = clinic.visit_summary@1.0.0`, non-null `before_pointer` (installation + plan snapshots), `after_pointer = 1.0.0`. Installation grant for **I0** at `1.0.0`. If a `plan:professional` grant exists from earlier probes, it is also `1.0.0`.

#### 11.3.14 Deprecate with successor

Uses global overlay on `capability_grant` — does not change installation grants from entitle.

**Do:** `deprecate` with `successor_id` missing:

```bash
curl -sS -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/capabilities/$CAP/versions/$VER/deprecate" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Expect:** HTTP 400 `{ "error": "missing_successor_id" }`.

**Do:** `deprecate` with `successor_id: "clinic.not_in_registry"`.

**Expect:** HTTP 400 `{ "error": "unknown_successor" }`.

**Do:** `deprecate 9.9.9`

**Expect:** HTTP 404 `{ "error": "capability_not_found" }`.

**Do:** `deprecate` (default successor `clinic.visit_summary`).

**Expect:** HTTP 200 `{}`.

**Do:**

```bash
d1 "SELECT lifecycle_state, successor_id, deprecated_at, retire_after, scope, revoked_at
    FROM capability_grant WHERE scope = 'global' AND capability_id = '$CAP'"
d1 "SELECT action, target, after_pointer FROM control_audit
    WHERE action = 'deprecate' ORDER BY recorded_at DESC LIMIT 1"
```

**Expect:** one global overlay row: `lifecycle_state = deprecated`, `successor_id = clinic.visit_summary`, `deprecated_at` set, `retire_after` ≈ `deprecated_at + 90 days`, `revoked_at` not null (overlay stamp). Audit `target = clinic.visit_summary@1.0.0`, `after_pointer = clinic.visit_summary`.

**Do:** repeat the same `deprecate` call.

**Expect:** HTTP 200 `{}` idempotent — still one global overlay row; `deprecated_at` / `retire_after` unchanged.

**Do:** `deprecate` with a different successor (any other registered id string won't work unless you add a manifest; use SQL to simulate intent):

```bash
# Only if you registered another capability in the Worker; otherwise skip.
deprecate "$VER" "clinic.other_capability"
```

**Expect:** if a different successor string is sent after the first deprecate, HTTP 409 `{ "error": "already_deprecated" }`.

#### 11.3.15 Retire after overlap window

**Do:** `retire` before any deprecate (delete global overlay if present from [§11.3.14](#11314-deprecate-with-successor)):

```bash
d1 "DELETE FROM capability_grant WHERE scope = 'global' AND capability_id = '$CAP'"
retire
```

**Expect:** HTTP 400 `{ "error": "not_deprecated" }`.

**Do:** run `deprecate` from [§11.3.14](#11314-deprecate-with-successor) if overlay missing, then `retire` immediately.

**Expect:** HTTP 400 `{ "error": "overlap_window_active" }` — 90-day window has not elapsed.

**Do:** move `retire_after` into the past, then retire:

```bash
d1 "UPDATE capability_grant SET retire_after = '2020-01-01T00:00:00.000Z'
    WHERE scope = 'global' AND capability_id = '$CAP' AND lifecycle_state = 'deprecated'"
retire
```

**Expect:** HTTP 200 `{}`.

**Do:**

```bash
d1 "SELECT lifecycle_state, successor_id FROM capability_grant
    WHERE scope = 'global' AND capability_id = '$CAP'
    ORDER BY changed_at DESC LIMIT 1"
d1 "SELECT action, after_pointer FROM control_audit
    WHERE action = 'retire' ORDER BY recorded_at DESC LIMIT 1"
```

**Expect:** latest global overlay `lifecycle_state = retired`. Audit `action = retire`, `after_pointer = clinic.visit_summary`.

**Do:** `deprecate` again on the same pin.

**Expect:** HTTP 409 `{ "error": "already_retired" }`. Retirement is terminal.

**Cleanup:** delete global overlay rows for `$CAP` if you need a clean D1 for later stages:

```bash
d1 "DELETE FROM capability_grant WHERE scope = 'global' AND capability_id = '$CAP'"
```
