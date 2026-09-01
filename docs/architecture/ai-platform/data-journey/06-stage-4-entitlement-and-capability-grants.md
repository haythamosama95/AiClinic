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
7. [Behavioral verification](#7-behavioral-verification)
   - [7.1 Setup](#71-setup)
   - [7.2 Coverage](#72-coverage)
   - [7.3 Ordered probes](#73-ordered-probes)
     - [7.3.1 Confirm Stage 3 pending sentinel](#731-confirm-stage-3-pending-sentinel)
     - [7.3.2 Who may not call](#732-who-may-not-call)
     - [7.3.3 Entitle failure paths](#733-entitle-failure-paths)
     - [7.3.4 Runtime while pending](#734-runtime-while-pending)
     - [7.3.5 First entitle (visit-summary payload)](#735-first-entitle-visit-summary-payload)
     - [7.3.6 Re-entitle is not pending](#736-re-entitle-is-not-pending)
     - [7.3.7 Independent runtime switches](#737-independent-runtime-switches)
     - [7.3.8 Access role and scope](#738-access-role-and-scope)
     - [7.3.9 Kill-switch row](#739-kill-switch-row)
     - [7.3.10 What this stage does not do](#7310-what-this-stage-does-not-do)
     - [7.3.11 Unique entitlement per installation](#7311-unique-entitlement-per-installation)

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

## 7. Behavioral verification

Live probes against a local Worker and an installation that already completed [Stage 3 enroll](05-stage-3-platform-installation-enrollment.md). Each probe is an operator action and the outcome you should see — not a unit test. Run **[§7.3](#73-ordered-probes) top to bottom** on a throwaway local D1. If every probe matches, this stage is working.

Control-plane JSON uses `{ "error": "<code>" }`. Runtime `POST /v1/requests` JSON uses taxonomy `{ "code": "<code>", "request_reference": "…", "trace_id": "…", "retry_safe": <bool> }` (`control/http.ts` `reject` / `unauthorized` vs `errors.ts` `buildErrorBody`). The rejection **path** (`ai_disabled`, `plan_tier`, `capability_not_granted`, `kill_switch_*`) is Worker-log only — confirm it with D1 state, not the HTTP body.

The isolate `ConfigCache` TTL is 30 s. After any **D1 SQL** mutation (and after [§7.3.4](#734-runtime-while-pending) has cached a `pending` row), restart `npm run dev` or wait 30 s before the next `/v1` probe.

### 7.1 Setup

- Local Worker (`cd ai-platform && npm run dev`) at `http://127.0.0.1:8787`. `OPERATOR_BEARER_TOKEN` from `.dev.vars.development`. `OPERATOR_ID` is `platform-operator` (`wrangler.toml` `[env.development.vars]`).
- One **already-enrolled** installation from Stage 3: D1 `installation` row, `installation_key`, entitlement **`pending`** with zero quotas and `allowed_capabilities = '[]'`. Save that id as **I0**.
- Entitlement `plan` must be a closed-set tier (`starter` / `standard` / `professional` / `enterprise`). Unknown strings (for example Stage 2’s sample `"verify"`) fail closed at runtime (`plan_tier`). For visit-summary probes that must pass guard stage 3, set `plan` to `professional` (or `standard` / `enterprise`) **before** entitle — entitle does not write `plan`.
- Clinic Supabase with the Stage 2 keypair whose `installation_id` is **I0**. A **doctor** session that can `issue_ai_token` (RBAC `ai.access` is enough to mint; visit-summary Access fields are a later probe).
- SQL as `postgres` only to mint AATs and inspect clinic tables. D1 inspection via wrangler.

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export INSTALLATION_ID='<I0>'
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

### 7.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Stage 3 enroll leaves entitlement `pending`, quotas `0`, `allowed_capabilities = []`, `soft_threshold = 0` | [§7.3.1](#731-confirm-stage-3-pending-sentinel) |
| `plan` is stored at enroll; entitle does not change it | [§7.3.1](#731-confirm-stage-3-pending-sentinel), [§7.3.5](#735-first-entitle-visit-summary-payload) |
| Closed plan ranks: unknown / `starter` fail `minimumPlanTier: "standard"` even after entitle | [§7.3.1](#731-confirm-stage-3-pending-sentinel), [§7.3.7](#737-independent-runtime-switches) |
| Only `OPERATOR_BEARER_TOKEN` may call; missing/wrong/AAT bearer → HTTP 401 `{ "error": "unauthorized" }` | [§7.3.2](#732-who-may-not-call) |
| Clinic staff / Flutter / `issue_ai_token` cannot entitle | [§7.3.2](#732-who-may-not-call) |
| No `installation` row → HTTP 404 `installation_not_found` | [§7.3.3](#733-entitle-failure-paths) |
| No `entitlement` row → HTTP 404 `entitlement_not_found` | [§7.3.3](#733-entitle-failure-paths) |
| `status !== 'pending'` → HTTP 409 `not_pending` | [§7.3.6](#736-re-entitle-is-not-pending) |
| Bad numbers, empty `grants`, bad `scope`, non-ISO period, `period_start >= period_end` → HTTP 400 `invalid_payload`; row unchanged | [§7.3.3](#733-entitle-failure-paths) |
| HTTP 500 `storage_error` (D1 batch failure) | **Unprobeable** — requires a live D1 `batch` exception |
| Pending runtime → HTTP 403 `forbidden_capability` (`ai_disabled`); no spend rights yet | [§7.3.4](#734-runtime-while-pending) |
| [§6](#6-example-entitle-payload-visit-summary) body: every request field; HTTP 200 `{ installation_id, status: "active" }` | [§7.3.5](#735-first-entitle-visit-summary-payload) |
| D1 `UPDATE entitlement` writes every budget column + `allowed_capabilities` JSON + `status='active'` | [§7.3.5](#735-first-entitle-visit-summary-payload) |
| D1 `INSERT capability_grant` per grant: `scope = installation:{id}`, version, `revoked_at` NULL, `changed_by = OPERATOR_ID` | [§7.3.5](#735-first-entitle-visit-summary-payload) |
| D1 `INSERT control_audit` `action='entitle'`, `after_pointer` = allowed-capabilities JSON | [§7.3.5](#735-first-entitle-visit-summary-payload) |
| Not updated: `entitlement.plan`, `installation.status` | [§7.3.5](#735-first-entitle-visit-summary-payload) |
| One-shot: second entitle is not idempotent → 409 `not_pending` | [§7.3.6](#736-re-entitle-is-not-pending) |
| Independent switch: `allowed_capabilities` omits id → `forbidden_capability` (`capability_not_granted`) | [§7.3.7](#737-independent-runtime-switches) |
| Independent switch: matching grant missing / wrong version → same code | [§7.3.7](#737-independent-runtime-switches) |
| Independent switch: `plan` below `standard` (or unknown) → `forbidden_capability` (`plan_tier`) | [§7.3.7](#737-independent-runtime-switches) |
| Independent switch: `status` `suspended` (or any non-`active`) → `forbidden_capability` (`ai_disabled`) | [§7.3.7](#737-independent-runtime-switches) |
| Grant at `plan:{plan}` satisfies check 4 when installation-scope grant is absent | [§7.3.7](#737-independent-runtime-switches) |
| Three gates must align before guard stage 3 returns ok | [§7.3.7](#737-independent-runtime-switches) |
| `evaluateEntitlement` does not receive Access; wrong `principal.scopes` → HTTP 403 `forbidden_capability` | [§7.3.8](#738-access-role-and-scope) |
| Wrong `principal.role` vs `Access.allowedStaffRoles` → HTTP 403 `forbidden_capability` | [§7.3.8](#738-access-role-and-scope) |
| Unset/empty `requiredCapabilityScope` or `allowedStaffRoles` skip those checks | **Unprobeable** with published visit-summary — both Access fields are non-empty; [§7.3.8](#738-access-role-and-scope) exercises the reject path only |
| D1 `kill_switch` active → HTTP 503 `capability_disabled` | [§7.3.9](#739-kill-switch-row) |
| Manifest `Access.killSwitchFlag === true` | **Unprobeable** — visit-summary bundle has `false`; flipping it needs a Worker redeploy |
| Manifest `killSwitchFlag` `false` / omitted does not disable | **Unprobeable** as a positive — visit-summary is `false`, but clinic AATs never pass Access to prove the skip |
| Entitle does not publish routing policy, mint AATs, enroll, or write clinic Postgres | [§7.3.10](#7310-what-this-stage-does-not-do) |
| `UNIQUE (installation_id)` — a second entitlement row cannot be inserted | [§7.3.11](#7311-unique-entitlement-per-installation) |
| Three period ceilings → `quota_exhausted` when any counter is already at its limit | **Unprobeable** with clinic-minted AATs — admission is guard stage 8; visit-summary `Access.allowedStaffRoles` is `clinician`/`nurse`, which are not `public.staff_role` values, so `issue_ai_token` never reaches the Quota DO |
| `soft_threshold` admits but marks `degraded` / `routing_tier = degraded` / `degraded_notice` | **Unprobeable** — same stage-5 Access block |

### 7.3 Ordered probes

#### 7.3.1 Confirm Stage 3 pending sentinel

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

#### 7.3.2 Who may not call

**Do:** POST entitle with [§6](#6-example-entitle-payload-visit-summary) JSON and **no** `Authorization` header.

**Expect:** HTTP 401, `{ "error": "unauthorized" }`. Entitlement still `pending`; grant count still 0 (`requireOperator` in `control/auth.ts`).

**Do:** same POST with `Authorization: Bearer definitely-wrong`.

**Expect:** HTTP 401, `{ "error": "unauthorized" }`. Timing-safe compare against `OPERATOR_BEARER_TOKEN` failed.

**Do:** same POST with `Authorization: Bearer $AAT` (clinic staff token from `issue_ai_token`).

**Expect:** HTTP 401, `{ "error": "unauthorized" }`. An AAT is not the operator secret. Clinic staff / Flutter cannot call this route.

#### 7.3.3 Entitle failure paths

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

#### 7.3.4 Runtime while pending

Do **not** entitle yet. Restart the Worker if you already POSTed `/v1` during earlier setup.

**Do:** `visit_post`

**Expect:** HTTP 403, `"code": "forbidden_capability"`, `"retry_safe": false`. Guard stage 3: `entitlement.status !== 'active'` → path `ai_disabled`. Identity can pass (Stage 3 registered the key). This stage has not granted quotas or capabilities.

#### 7.3.5 First entitle (visit-summary payload)

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
| `entitlement.plan` | **unchanged** from [§7.3.1](#731-confirm-stage-3-pending-sentinel) (still `professional` if you set it) |
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

Restart the Worker (or wait 30 s) so `/v1` does not keep the cached `pending` snapshot from [§7.3.4](#734-runtime-while-pending).

#### 7.3.6 Re-entitle is not pending

**Do:** repeat the exact [§7.3.5](#735-first-entitle-visit-summary-payload) POST.

**Expect:** HTTP 409, `{ "error": "not_pending" }`. One-shot: reuse is **not** idempotent. Grant row count unchanged (no second insert). `status` stays `active`.

#### 7.3.7 Independent runtime switches

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

**Expect:** guard stage 3 now finds a grant (`plan:{plan}`). The HTTP 403 you still see is Access role/scope at guard stage 5 ([§7.3.8](#738-access-role-and-scope)) — **not** `capability_not_granted`. Delete `probe-plan-grant` and re-insert the installation-scope grant from [§7.3.5](#735-first-entitle-visit-summary-payload) (`scope = installation:<I0>`, same capability/version) before continuing.

**Do:** installation grant present, POST with `visit_post 9.9.9` (`x-capability-version: 9.9.9`).

**Expect:** HTTP 403 `forbidden_capability` at **stage 3** (grant `version_mismatch` → `capability_not_granted`), not `404 capability_unknown` (registry is stage 5).

**Do:** `visit_post 1.0.0 clinic.chat_assistant` (allow-list and grant are visit-summary only).

**Expect:** HTTP 403 `forbidden_capability` (check 3, `capability_not_granted`) before capability resolve.

**Do:** `UPDATE entitlement SET plan = 'starter' WHERE installation_id = '$INSTALLATION_ID'` (allow-list + grant restored). Restart. `visit_post`.

**Expect:** HTTP 403 `forbidden_capability` (check 2, `plan_tier`). Worker `preAccept` hardcodes `minimumPlanTier: "standard"`; `starter < standard`. Repeat with `plan = 'verify'` (unknown) — same 403 `plan_tier` (fail closed). Restore `plan = 'professional'`.

**Do:** `UPDATE entitlement SET status = 'suspended' WHERE installation_id = '$INSTALLATION_ID'`. Restart. `visit_post`.

**Expect:** HTTP 403 `forbidden_capability` (check 1, `ai_disabled`). This is **entitlement** status, not `POST …/suspend` (that sets `installation.status` and fails identity as `installation_suspended` before this table). Restore `status = 'active'`.

These four switches (allow-list, grant, plan, status) fail independently. All three gates in [§4](#4-runtime-entitlement-checks-guard-stage-3) must align for stage 3 to return ok.

#### 7.3.8 Access role and scope

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

#### 7.3.9 Kill-switch row

Entitlement active; allow-list + grant + plan restored. Kill-switch evaluation is checks 5–8 of [§4](#4-runtime-entitlement-checks-guard-stage-3) (`evaluateEntitlement` runs **before** capability resolve).

**Do:**

```bash
d1 "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
    VALUES ('installation', '$INSTALLATION_ID', 1, datetime('now'), 'probe')"
```

Restart. `visit_post`.

**Expect:** HTTP 503, `"code": "capability_disabled"`, `"retry_safe": true`. Path `kill_switch_installation`. One D1 row is enough; do not enumerate global / capability / provider here (same code, different `target`).

**Do:** `DELETE FROM kill_switch WHERE scope = 'installation' AND target = '$INSTALLATION_ID'`. Restart.

**Expect:** kill-switch miss is fail-open (`{ active: false }`). HTTP returns to 403 `forbidden_capability` from Access ([§7.3.8](#738-access-role-and-scope)), not 503.

`providerId` in `preAccept` is hardcoded `"fake"`; a `provider:fake` row would also be `capability_disabled` at stage 3. Skip inserting it.

#### 7.3.10 What this stage does not do

**Do:** after [§7.3.5](#735-first-entitle-visit-summary-payload):

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

#### 7.3.11 Unique entitlement per installation

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
