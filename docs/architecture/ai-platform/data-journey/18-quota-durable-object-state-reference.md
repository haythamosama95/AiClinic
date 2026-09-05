# AI Platform Data Journey — Quota Durable Object State Reference

## Table of Contents

1. [`QuotaDoState` — every field](#1-quotadostate-every-field)
2. [Constants](#2-constants)
3. [RPC kinds](#3-rpc-kinds)
4. [Ephemeral sweep and idempotency TTL](#4-ephemeral-sweep-and-idempotency-ttl)
5. [Live state inspection (operator GET)](#5-live-state-inspection-operator-get)
   - [5.1 Route and auth](#51-route-and-auth)
   - [5.2 Example request and response](#52-example-request-and-response)
   - [5.3 Response → DO field mapping](#53-response--do-field-mapping)
   - [5.4 Verbose mode](#54-verbose-mode)
   - [5.5 Read-only sweep caveat](#55-read-only-sweep-caveat)
6. [Behavioral verification](#6-behavioral-verification)
   - [6.1 Setup](#61-setup)
   - [6.2 Coverage](#62-coverage)
   - [6.3 Ordered probes](#63-ordered-probes)
     - [6.3.1 Reset to a known Quota DO](#631-reset-to-a-known-quota-do)
     - [6.3.2 Entitle with known ceilings](#632-entitle-with-known-ceilings)
     - [6.3.3 First admit and credit](#633-first-admit-and-credit)
     - [6.3.4 JTI replay](#634-jti-replay)
     - [6.3.5 Idempotent replay after credit](#635-idempotent-replay-after-credit)
     - [6.3.6 Soft threshold and request-quota exhaustion](#636-soft-threshold-and-request-quota-exhaustion)
     - [6.3.7 Token and cost ceilings](#637-token-and-cost-ceilings)
     - [6.3.8 Period reset](#638-period-reset)
     - [6.3.9 Cancel and zero-usage credit](#639-cancel-and-zero-usage-credit)
     - [6.3.10 Abandoned admission sweep](#6310-abandoned-admission-sweep)
     - [6.3.11 Release on journal-insert failure](#6311-release-on-journal-insert-failure)
     - [6.3.12 Grace admission and the D1 cap](#6312-grace-admission-and-the-d1-cap)
     - [6.3.13 Concurrency limit](#6313-concurrency-limit)
     - [6.3.14 Ephemeral sweep and idempotency TTL](#6314-ephemeral-sweep-and-idempotency-ttl)

---


**Storage key:** `"state"` in DO persistent storage.

## 1. `QuotaDoState` — every field


| Field                         | Type   | Meaning                                             |
| ----------------------------- | ------ | --------------------------------------------------- |
| `periodCounters.requestsUsed` | number | Requests credited this period                       |
| `periodCounters.tokensUsed`   | number | Tokens credited                                     |
| `periodCounters.costUsed`     | number | Cost credited                                       |
| `periodCounters.inFlight`     | number | Admitted not yet credited/released                  |
| `periodBounds.period_start`   | string | From entitlement snapshot                           |
| `periodBounds.period_end`     | string | From entitlement snapshot                           |
| `jtiReplay[jti].expiresAt`    | number | Replay window (2h). Already ≥ the 10-minute max AAT lifetime (`MAX_AAT_LIFETIME_SECONDS = 600`); a token cannot outlive its JTI entry. |
| `idempotency[key]`            | object | `{ expiresAt, requestReference, state, requestId, terminalErrorCode? }` — `state` is `admitted` \| `completed` \| `failed` \| `cancelled` only (not `in_progress` / `awaiting_context`; those are not DO states). `terminalErrorCode` is set on `failed` credit (C-11) and replayed on idempotent failure responses. `admitted` at admit; credit may set `completed`, `failed`, or `cancelled`; abandoned sweep may set `failed`. |
| `creditedRequests[requestId]` | object | `{ expiresAt }`                                     |
| `admittedRequests[requestId]` | object | `{ requestReference, admittedAt, entitlement }` — `entitlement` is the admission-time snapshot so `creditRPC` can re-run `maybeResetPeriod` before applying usage |
| `boundInstallationId`         | string | Installation binding                                |



## 2. Constants


| Constant               | Value          | Meaning                                  |
| ---------------------- | -------------- | ---------------------------------------- |
| `EPHEMERAL_HORIZON_MS` | 7_200_000 (2h) | Ephemeral entry TTL. Already ≥ 10-minute max AAT lifetime — the "JTI window ≥ max lifetime" requirement is met; do not shrink or enlarge this constant for that bound. |
| `CONCURRENCY_LIMIT`    | 16             | Max in-flight per installation           |
| `GRACE_ADMISSION_CAP`  | 5              | Max **pending** D1 `grace_admission_queue` rows per installation while the DO is unavailable. Enforced in `src/admission/` against D1, not stored in this DO. |




## 3. RPC kinds


| kind        | Purpose                                     |
| ----------- | ------------------------------------------- |
| `admission` | Admit or idempotent replay at guard stage 8 |
| `credit`    | Settle usage on completion, failure, or cancel. Re-runs `maybeResetPeriod` from the credit RPC entitlement (or the snapshot stored at admit) before applying usage. Idempotency becomes `completed`, `failed`, or `cancelled` (`idempotencyState` when present; otherwise `partial` → `cancelled`, else `completed`). Credit also slides `expiresAt` to `now + EPHEMERAL_HORIZON_MS`. Zero usage is a valid credit and still releases `inFlight`. |
| `release`   | Compensate on journal insert failure        |
| `inspect`   | Operator GET `/control/installations/{id}/quota` — read-only snapshot; runs `sweepEphemeral` in memory without persisting |


## 4. Ephemeral sweep and idempotency TTL

No `alarm()` handler — sweeps are **lazy**, run at the start of mutating RPCs (`admission`, `credit`, `release`) and on read-only `inspectRPC` (in memory only — no `storage.put`).

`sweepEphemeral` order (`quota-do/index.ts`):

1. Delete expired `jtiReplay` entries (`expiresAt <= now`)
2. **`sweepAbandonedAdmissions`** — drop stale in-flight admissions; decrement `inFlight`; mark matching idempotency `failed` with slid expiry
3. Delete expired `idempotency` entries
4. Delete expired `creditedRequests` entries

Abandoned-admission handling runs **after** jti expiry deletion and **before** idempotency expiry — not first overall.

Admission sets `idempotency.expiresAt` and `admittedAt` to the same timestamp plus the 2h horizon. On every later RPC, `sweepEphemeral` runs the order above. JTI replay uses the same 2h horizon, which already covers the 10-minute maximum AAT lifetime (`MAX_AAT_LIFETIME_SECONDS`); a still-valid token cannot be replayed after its JTI entry expires.

When an `admittedRequests` row is older than the horizon (crashed / never credited):

1. Drop the admitted row and decrement `inFlight`.
2. If the matching idempotency entry is still `"admitted"`, set `state: "failed"` and **slide** `expiresAt` to `now + EPHEMERAL_HORIZON_MS` so a retry can replay as `failed` for another 2h (not as a completed placeholder, and not as a fresh admit).

Credit (and that sweep mark) slide `expiresAt`; it is not frozen at admission. A retry of the same key after the original admission horizon but still inside the slid credit window remains idempotent. After the slid window elapses, the entry is deleted and the key may admit fresh.

## 5. Live state inspection (operator GET)

Primary operator recipe for reading live Quota DO state joined with D1 entitlement limits. See also [Operator runbook §6.4](../04-ai-platform-operator-runbook.md#64-durable-objects-quota--admission).

### 5.1 Route and auth

| Item | Value |
| ---- | ----- |
| Method | `GET` |
| Path | `/control/installations/{installation_id}/quota` |
| Query | `?verbose=true` (optional) |
| Auth | `Authorization: Bearer $OPERATOR_BEARER_TOKEN` (same as all `/control/*` routes; no AAT) |

The control handler resolves `DO.idFromName(installation_id)` — same binding as live admission/credit — and POSTs RPC `kind: "inspect"` on the `GatewayObject`. Read-only: never writes DO storage. D1 `usage_event` remains the audit ledger; this endpoint is a diagnostic snapshot only.

### 5.2 Example request and response

```bash
export GATEWAY='http://127.0.0.1:8787'
export INSTALLATION_ID='e7def24a-d92b-4109-8d24-c2cff3af50d5'

curl -s -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  "$GATEWAY/control/installations/$INSTALLATION_ID/quota" | jq .
```

```json
{
  "installation_id": "e7def24a-d92b-4109-8d24-c2cff3af50d5",
  "bound_installation_id": "e7def24a-d92b-4109-8d24-c2cff3af50d5",
  "period_bounds": { "period_start": "2026-08-01T00:00:00.000Z", "period_end": "2026-09-01T00:00:00.000Z" },
  "period_counters": { "requests_used": 2, "tokens_used": 60, "cost_used": 0.01, "in_flight": 0 },
  "entitlement": {
    "plan": "standard",
    "status": "active",
    "period_start": "2026-08-01T00:00:00.000Z",
    "period_end": "2026-09-01T00:00:00.000Z",
    "request_quota": 4000,
    "token_budget": 4000000,
    "cost_budget": 100
  },
  "remaining": { "requests": 3998, "tokens": 3999940, "cost": 99.99 },
  "idempotency_keys": 2,
  "jti_replay_entries": 2,
  "admitted_requests": 0,
  "credited_requests": 2
}
```

| HTTP | Code | Meaning |
| ---- | ---- | ------- |
| 401 | `unauthorized` | Missing or invalid operator Bearer |
| 404 | `installation_not_found` | No D1 `installation` row |
| 405 | `method_not_allowed` | Non-GET |
| 503 | `quota_do_unavailable` | DO binding missing or DO unreachable — same transport failure that triggers grace admission on `POST /v1/requests` |

`400 invalid_route` exists in the handler but is **unreachable via HTTP** (dispatch pre-filters with identical regex; direct handler invocation only).

### 5.3 Response → DO field mapping

Budget **limits** come from D1 `entitlement`; **counters** and map sizes come from the DO after in-memory sweep. `remaining` is plain subtraction (`requests`, `tokens`, `cost`); `null` when no entitlement row exists.

| Response field | DO / D1 source |
| -------------- | -------------- |
| `installation_id` | route param |
| `bound_installation_id` | `state.boundInstallationId` (`null` if unbound) |
| `period_bounds` | `state.periodBounds` (`null` before first admission) |
| `period_counters.requests_used` | `state.periodCounters.requestsUsed` |
| `period_counters.tokens_used` | `state.periodCounters.tokensUsed` |
| `period_counters.cost_used` | `state.periodCounters.costUsed` |
| `period_counters.in_flight` | `state.periodCounters.inFlight` |
| `entitlement.plan` | D1 `entitlement.plan` |
| `entitlement.status` | D1 `entitlement.status` |
| `entitlement.period_start` | D1 `entitlement.period_start` |
| `entitlement.period_end` | D1 `entitlement.period_end` |
| `entitlement.request_quota` | D1 `entitlement.request_quota` |
| `entitlement.token_budget` | D1 `entitlement.token_budget` |
| `entitlement.cost_budget` | D1 `entitlement.cost_budget` |
| `remaining.requests` | `request_quota − requestsUsed` |
| `remaining.tokens` | `token_budget − tokensUsed` |
| `remaining.cost` | `cost_budget − costUsed` |
| `idempotency_keys` | `Object.keys(state.idempotency).length` (post-sweep) |
| `jti_replay_entries` | `Object.keys(state.jtiReplay).length` |
| `admitted_requests` | `Object.keys(state.admittedRequests).length` |
| `credited_requests` | `Object.keys(state.creditedRequests).length` |

### 5.4 Verbose mode

Append `?verbose=true` to include `maps`:

| Map key | DO source |
| ------- | --------- |
| `maps.idempotency` | full `state.idempotency` |
| `maps.jti_replay` | full `state.jtiReplay` |
| `maps.admitted_requests` | full `state.admittedRequests` |
| `maps.credited_requests` | full `state.creditedRequests` |

Each map is capped at **500** entries. When any map is truncated, `maps.truncated` is `true`.

### 5.5 Read-only sweep caveat

The `inspect` RPC loads persisted `"state"`, runs the same `sweepEphemeral` logic as `admission` / `credit` / `release` ([§4](#4-ephemeral-sweep-and-idempotency-ttl)) **in memory only**, then returns the swept view. Expired jti/idempotency/credited entries and abandoned admissions are excluded from counts and verbose maps; nothing is written back to DO storage.

## 6. Behavioral verification

Live probes against a running local Worker Quota DO (`GatewayObject`, `idFromName(installationId)`). For a direct JSON snapshot of DO counters and map sizes, use [§5](#5-live-state-inspection-operator-get) (`GET /control/installations/{id}/quota`). The probes below infer behaviour through **observable effects**: D1 `ai_request` / `usage_event` / `grace_admission_queue`, HTTP/SSE outcomes (`quota_exhausted`, JTI `unauthenticated`, idempotent replay), and Worker logs on `npm run dev`. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§6.3](#63-ordered-probes) top to bottom** on a throwaway installation. If every probe matches, this DO is working.

The guard talks to the DO only as `kind: admission` | `credit` | `release` on `https://quota-do.internal/rpc` (not a public URL). You never POST that RPC yourself.

### 6.1 Setup

- Local Worker (`cd ai-platform && npm run dev`) with `OPERATOR_BEARER_TOKEN`. Migrations applied:

```bash
npx wrangler d1 migrations apply ai-platform-development --local --env development
```

- Throwaway clinic installation that has **never** been admitted on this Worker (Quota DO identity is `idFromName(installation_id)`; wiping D1 does **not** zero DO counters). Follow [Stage 2](04-stage-2-clinic-keypair-enrollment.md#839-stage-3-enroll-using-this-rpcs-output-happy-path-6) → [Stage 3 enroll](05-stage-3-platform-installation-enrollment.md#3-api-post-controlinstallationsinstallation_idenroll) until D1 `entitlement.status = pending`. Call this `installation_id` **I0**.
- Staff who can `SELECT public.issue_ai_token();`. Decode the AAT payload for `org` and `branch` (they must match the invoke `context`). Mint a **new** AAT whenever a probe needs a fresh `jti` — admission checks JTI **before** the idempotency key.
- Control-plane entitle in [§6.3.2](#632-entitle-with-known-ceilings) (one-shot while pending). Publish a routing policy so `clinic.visit_summary@1.0.0` can invoke ([Stage 5](07-stage-5-routing-policy.md#6-control-endpoints)). If invoke still fails after SSE `accepted`, Quota DO **credit still ran** — use the D1 terminal you actually got (`Completed` / `Failed` / `Cancelled`) when reading later replays.
- After any **direct D1 `UPDATE` of `entitlement`**, wait **> 30 s** (isolate `ConfigCache` TTL) or restart `npm run dev` before the next POST.
- Local fake adapter finishes in milliseconds. Overlapping in-flight slots, mid-flight entitlement edits, and client-cancel windows are accordingly tight; probes that need those windows say so.

Invoke template (replace `AAT`, `KEY`, org/branch):

```bash
export GATEWAY='http://127.0.0.1:8787'

curl -sN -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "x-idempotency-key: $KEY" \
  -H "x-capability-version: 1.0.0" \
  -H "Content-Type: application/json" \
  -d '{
    "capability_id": "clinic.visit_summary",
    "user_intent": "Summarize today'\''s visit for the chart.",
    "context": {
      "org": "<AAT org>",
      "branch": "<AAT branch>",
      "visit.chief_complaint@v1": "Patient reports headache for 3 days."
    }
  }'
```

Inspect D1 (always `--local --env development`):

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, request_reference, idempotency_key, state, routing_tier,
          terminal_error_code, created_at, completed_at
   FROM ai_request WHERE installation_id = '<I0>' ORDER BY created_at"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, period, tokens, cost, recorded_at
   FROM usage_event WHERE installation_id = '<I0>' ORDER BY recorded_at"
```

### 6.2 Coverage

Every field, constant, RPC kind, and sweep/TTL claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Live DO snapshot via operator GET `/control/installations/{id}/quota` | [§5](#5-live-state-inspection-operator-get) |
| Behavioral verification via D1 / HTTP / SSE / logs | [§6.1](#61-setup), [§6.3.1](#631-reset-to-a-known-quota-do) |
| `periodCounters.requestsUsed` +1 per credit; exhausts when ≥ `request_quota` | [§6.3.3](#633-first-admit-and-credit), [§6.3.6](#636-soft-threshold-and-request-quota-exhaustion) |
| `periodCounters.tokensUsed` += credited tokens | [§6.3.3](#633-first-admit-and-credit), [§6.3.7](#637-token-and-cost-ceilings) |
| `periodCounters.costUsed` += credited cost | [§6.3.3](#633-first-admit-and-credit), [§6.3.7](#637-token-and-cost-ceilings) |
| `periodCounters.inFlight` +1 at admit, −1 at credit/release/abandoned sweep | [§6.3.3](#633-first-admit-and-credit), [§6.3.9](#639-cancel-and-zero-usage-credit), [§6.3.10](#6310-abandoned-admission-sweep), [§6.3.11](#6311-release-on-journal-insert-failure) |
| `periodBounds.period_start` from entitlement snapshot | [§6.3.3](#633-first-admit-and-credit) (`usage_event.period`) |
| `periodBounds.period_end` from entitlement snapshot | [§6.3.6](#636-soft-threshold-and-request-quota-exhaustion) (`period_reset`) |
| `maybeResetPeriod` on admit and credit when bounds change | [§6.3.8](#638-period-reset) |
| `jtiReplay[jti].expiresAt` — same AAT cannot admit twice | [§6.3.4](#634-jti-replay) |
| JTI window 2h already ≥ 10-minute max AAT lifetime | [§6.3.4](#634-jti-replay), [§6.3.14](#6314-ephemeral-sweep-and-idempotency-ttl) |
| `idempotency[key]` `{ expiresAt, requestReference, state, requestId, terminalErrorCode? }` | [§6.3.3](#633-first-admit-and-credit), [§6.3.5](#635-idempotent-replay-after-credit) |
| Idempotency states are `admitted` \| `completed` \| `failed` \| `cancelled` only | [§6.3.5](#635-idempotent-replay-after-credit), [§6.3.9](#639-cancel-and-zero-usage-credit), [§6.3.10](#6310-abandoned-admission-sweep) |
| `admitted` at admit; credit may set `completed` / `failed` / `cancelled` | [§6.3.3](#633-first-admit-and-credit), [§6.3.9](#639-cancel-and-zero-usage-credit), [§6.3.10](#6310-abandoned-admission-sweep) |
| Abandoned sweep may set `failed` (not a completed placeholder) | [§6.3.10](#6310-abandoned-admission-sweep) |
| `creditedRequests[requestId].{ expiresAt }` — second credit does not double-count | [§6.3.5](#635-idempotent-replay-after-credit), [§6.3.14](#6314-ephemeral-sweep-and-idempotency-ttl) |
| `admittedRequests[requestId]` `{ requestReference, admittedAt, entitlement }` | [§6.3.3](#633-first-admit-and-credit), [§6.3.8](#638-period-reset), [§6.3.10](#6310-abandoned-admission-sweep) |
| `boundInstallationId` set on first admit | [§6.3.3](#633-first-admit-and-credit) |
| `EPHEMERAL_HORIZON_MS` = 2h | [§6.3.14](#6314-ephemeral-sweep-and-idempotency-ttl) |
| `CONCURRENCY_LIMIT` = 16 | [§6.3.13](#6313-concurrency-limit) |
| `GRACE_ADMISSION_CAP` = 5, D1 not this DO | [§6.3.12](#6312-grace-admission-and-the-d1-cap) |
| RPC `admission` — `admitted` | [§6.3.3](#633-first-admit-and-credit) |
| RPC `admission` — `replay` (JTI) | [§6.3.4](#634-jti-replay) |
| RPC `admission` — `idempotent` | [§6.3.5](#635-idempotent-replay-after-credit) |
| RPC `admission` — `quota_exhausted` | [§6.3.6](#636-soft-threshold-and-request-quota-exhaustion), [§6.3.7](#637-token-and-cost-ceilings) |
| RPC `admission` — `concurrency_exhausted` | [§6.3.13](#6313-concurrency-limit) |
| RPC `credit` — settle usage; `inFlight` released; zero usage valid | [§6.3.3](#633-first-admit-and-credit), [§6.3.9](#639-cancel-and-zero-usage-credit) |
| Credit `idempotencyState` `completed` / `failed` / `cancelled` (`partial` → `cancelled`) | [§6.3.3](#633-first-admit-and-credit), [§6.3.9](#639-cancel-and-zero-usage-credit), [§6.3.10](#6310-abandoned-admission-sweep) |
| Credit re-runs `maybeResetPeriod`; slides `expiresAt` | [§6.3.8](#638-period-reset), [§6.3.14](#6314-ephemeral-sweep-and-idempotency-ttl) |
| RPC `release` — compensate when stage-9 journal INSERT fails | [§6.3.11](#6311-release-on-journal-insert-failure) |
| Admission sets `idempotency.expiresAt` and `admittedAt` to the same now+2h | [§6.3.14](#6314-ephemeral-sweep-and-idempotency-ttl) |
| `sweepEphemeral`: jti expiry → abandoned admissions → idempotency expiry → creditedRequests expiry | [§6.3.10](#6310-abandoned-admission-sweep), [§6.3.14](#6314-ephemeral-sweep-and-idempotency-ttl) |
| Abandoned: drop admitted row, `inFlight` −1, mark matching idempotency `failed`, slide `expiresAt` | [§6.3.10](#6310-abandoned-admission-sweep) |
| Retry after original horizon but inside slid window stays idempotent; after slid window the key admits fresh | [§6.3.14](#6314-ephemeral-sweep-and-idempotency-ttl) |


### 6.3 Ordered probes

#### 6.3.1 Reset to a known Quota DO

**Do:** enroll **I0** on this Worker if you have not already. Confirm D1 has no prior spend for **I0**:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT COUNT(*) AS n FROM usage_event WHERE installation_id = '<I0>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT COUNT(*) AS n FROM grace_admission_queue WHERE installation_id = '<I0>'"
```

**Expect:** both counts `0`. `entitlement.status = pending`. Before first admit, `GET /control/installations/{I0}/quota` shows null `period_bounds` and zero counters ([§5](#5-live-state-inspection-operator-get)). If this `installation_id` was used on this machine before, mint a **new** Stage 2 id and re-enroll — leftover `requestsUsed` will fail later ceilings.

#### 6.3.2 Entitle with known ceilings

**Do:** while entitlement is still `pending`:

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "period_start": "2026-08-01T00:00:00.000Z",
    "period_end": "2026-09-01T00:00:00.000Z",
    "request_quota": 2,
    "token_budget": 500000,
    "cost_budget": 50.0,
    "soft_threshold": 0.5,
    "allowed_capabilities": ["clinic.visit_summary"],
    "grants": [
      {
        "capability_id": "clinic.visit_summary",
        "capability_version": "1.0.0",
        "scope": "installation"
      }
    ]
  }'
```

**Expect:** HTTP 200, `status: active`. D1 `entitlement` for **I0** has those bounds and `request_quota = 2`, `soft_threshold = 0.5`. This is the snapshot admission will copy into `admittedRequests[].entitlement` and `periodBounds`.

#### 6.3.3 First admit and credit

**Do:** mint AAT **T0**. POST with `x-idempotency-key` **KEY0** (the template in [§6.1](#61-setup)). Watch Worker logs.

**Expect:** SSE `accepted` then a terminal (`completed` on a wired fake/success path). Logs include `Admission granted` then `Credit applied` (`partial` false on success). D1: exactly one `ai_request` for **KEY0**, `request_id` **REQ0** (DO-issued UUID), `request_reference` **R0**, `state` terminal, `routing_tier = standard` (usage was still 0 at admit, so soft threshold did not fire). One `usage_event` for **REQ0**: `tokens` and `cost` ≥ 0, `period = 2026-08` (from `period_start`, not wall-clock month-of-credit). That row is the operator-visible `requestsUsed` / `tokensUsed` / `costUsed` increment and the `periodBounds.period_start` snapshot. `inFlight` is 0 again — the next **new** key in [§6.3.6](#636-soft-threshold-and-request-quota-exhaustion) can admit. `boundInstallationId` is now **I0** (same installation keeps working; a mismatch is not reachable because each installation has its own DO).

#### 6.3.4 JTI replay

**Do:** reuse **T0** (same `jti`) with a **new** idempotency key **KEY_JTI**.

**Expect:** HTTP 401 `unauthenticated`. No new `ai_request` row. Worker log `Admission replay detected`. Admission checks `jtiReplay` **before** the idempotency map, so this is not an idempotent replay. A still-valid AAT (max 10 minutes) cannot outlive a missing JTI entry because the JTI horizon is 2h — you will always hit this replay while **T0** is still acceptable to identity. You cannot read `jtiReplay[jti].expiresAt` directly.

#### 6.3.5 Idempotent replay after credit

**Do:** mint a **new** AAT **T1**. POST with the same **KEY0**.

**Expect:** admission `idempotent` with `priorState.state` matching the terminal from [§6.3.3](#633-first-admit-and-credit) (`completed` on the success path, or `failed` / `cancelled` if that is what D1 stored). Guard skips a second journal INSERT. SSE replays that prior state (`completed` placeholder text `"Prior request completed."` when the DO state is `completed` or still `admitted`). Still **one** `usage_event` for **REQ0** — `creditedRequests[REQ0]` blocked a second credit. `idempotency[KEY0]` still carries `requestId = REQ0` and `requestReference = R0` (the replay names them). D1 conversational `awaiting_context` is not a DO state; you will not see `in_progress` / `awaiting_context` on this replay.

#### 6.3.6 Soft threshold and request-quota exhaustion

**Do:** mint **T2**. POST with new key **KEY1**.

**Expect:** admitted. `requestsUsed / 2 = 0.5` after [§6.3.3](#633-first-admit-and-credit), so soft threshold fires: SSE `accepted` includes `degraded_notice: true`, D1 `routing_tier = degraded`. Credit runs. Two `usage_event` rows for **I0**.

**Do:** mint **T3**. POST with new key **KEY2**.

**Expect:** HTTP 429 `quota_exhausted`. Body `period_reset` equals entitlement `period_end` (`2026-09-01T00:00:00.000Z`) — that is `periodBounds.period_end` leaving the DO. No third `ai_request`. Worker log `Admission quota exhausted`. `requestsUsed >= request_quota`. Guard-stage entitlement-missing also uses this code; here the row is `active` and the DO counters are the cause.

#### 6.3.7 Token and cost ceilings

**Do:** as D1 operator, raise the request ceiling and drop the token ceiling below already-credited tokens (wait > 30 s or restart the Worker):

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE entitlement
   SET request_quota = 1000,
       token_budget = 1
   WHERE installation_id = '<I0>'"
```

Mint **T4**. POST with new key **KEY3**.

**Expect:** 429 `quota_exhausted` again (now `tokensUsed >= token_budget`). Still no extra journal row. `period_reset` still `period_end`.

**Do:** restore a large `token_budget`. Set `cost_budget` below `SUM(usage_event.cost)` for **I0**. If that sum is `0` on the fake adapter, set `cost_budget = 0` so `costUsed >= cost_budget` trips at `0 >= 0`. Wait cache. POST **KEY4**.

**Expect:** 429 `quota_exhausted` from the cost ceiling. Any one of the three counters is enough ([§2](#2-constants) does not store these ceilings in the DO — they arrive on the entitlement snapshot).

#### 6.3.8 Period reset

**Do:** move the billing window and restore healthy budgets:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE entitlement
   SET period_start = '2026-09-01T00:00:00.000Z',
       period_end = '2026-10-01T00:00:00.000Z',
       request_quota = 100,
       token_budget = 500000,
       cost_budget = 50.0,
       soft_threshold = 0.5
   WHERE installation_id = '<I0>'"
```

Wait cache. Mint **T5**. POST **KEY5**.

**Expect:** admitted and credited. New `usage_event.period = 2026-09`. `requestsUsed` is 1 in the **new** period (`request_quota = 100` leaves headroom for [§6.3.9](#639-cancel-and-zero-usage-credit)–[§6.3.13](#6313-concurrency-limit)). Credit re-ran `maybeResetPeriod` from the snapshot (Worker sends admission-time entitlement on credit; after cache refresh that snapshot is the new bounds). You cannot inspect `admittedRequests[].entitlement` on the wire; the new `period` column is the effect. Mid-flight mutation of D1 between admit and credit is not operator-holdable on the fake adapter.

#### 6.3.9 Cancel and zero-usage credit

**Do:** mint **T6**. Start POST **KEY6** with `curl -N` and abort the client as soon as SSE `accepted` appears (Ctrl+C / close the socket).

**Expect:** if you closed before the fake adapter finished: D1 `state = Cancelled`, `usage_event` for that `request_id` with tokens/cost allowed to be `0`, Worker `Credit applied` with `partial: true`, idempotency `cancelled`. A remint + same **KEY6** replays SSE `cancelled`, not a second charge. Zero usage still released `inFlight` (another **new** key can admit while `request_quota` remains). If the fake path already completed, D1 is `Completed` instead — the cancel window is milliseconds; do not invent a hang endpoint. Retry this after [§6.3.8](#638-period-reset) while a request slot remains.

#### 6.3.10 Abandoned admission sweep

**Do:** mint **T7**. POST **KEY7** with `curl -N`. In another terminal poll `ai_request` until `state = Accepted` for **KEY7**, then **kill the Worker process** (`npm run dev`) before `completed_at` is set. Restart the Worker.

**Expect:** if you caught the window: D1 stays non-terminal (`Accepted`). `inFlight` is still reserved in the DO (not in D1). Remint immediately and POST **KEY7** → idempotent `admitted`, which the Worker replays as the completed placeholder (`"Prior request completed."`). That is why [§4](#4-ephemeral-sweep-and-idempotency-ttl) does not leave the key there.

**Do:** leave **KEY7** unrestored. After **more than 2 hours**, remint and POST **KEY7** again (any other RPC on this DO also runs `sweepEphemeral`).

**Expect:** abandoned handling runs **before** deleting expired idempotency: admitted row dropped, `inFlight` decremented, matching idempotency `state = failed` with `expiresAt` slid to now+2h. Replay is SSE `failed` (`internal_error` placeholder), **not** a fresh admit and **not** the completed placeholder. No extra `usage_event` for **KEY7**. If you never caught `Accepted` without a terminal (fake is fast), this sweep is **unprobeable on that run** — do not wait 2h for a key that already credited.

#### 6.3.11 Release on journal-insert failure

There is no operator knob on a healthy local D1 that fails the stage-9 `ai_request` INSERT after admission. Do not POST `kind: release` yourself.

**Expect (if stage 9 ever fails):** HTTP `internal_error`, **no** `ai_request` row for that attempt, Worker log `Admission reservation released`. A later POST with a **new** key still admits (`inFlight` was returned). `release` with an unknown `requestId` is not a public HTTP; you will not see `unknown_request` on `/v1/requests`.

#### 6.3.12 Grace admission and the D1 cap

**Do:** after the happy-path credits above:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT grace_request_id, status FROM grace_admission_queue
   WHERE installation_id = '<I0>'"
```

**Expect:** no pending rows. The healthy Worker does not write this table. `GRACE_ADMISSION_CAP` (5) lives in `src/admission/` against D1, **not** in this DO ([§2](#2-constants)).

`wrangler dev` keeps `GatewayObject` in-process with the Worker. There is no documented operator action that takes the Quota DO down independently, so you cannot live-force `admitUnderGrace`, the cap-5 `rate_limited` (not `quota_exhausted`) refusal, or `routing_tier = degraded` from grace on this stack. Do not invent a DO-kill debug route.

#### 6.3.13 Concurrency limit

**Do:** from a period with remaining request quota, fire **17** parallel POSTs (17 new AATs, 17 new keys) without waiting for SSE terminals.

**Expect:** on the local fake adapter they almost always all admit-and-credit before `inFlight` can reach 16 — you will **not** reliably see `concurrency_exhausted` (mapped to HTTP 429 `quota_exhausted` with `period_reset` from the entitlement snapshot, Worker log `Admission concurrency exhausted`). That mapping is indistinguishable from budget exhaustion by HTTP code alone. **`CONCURRENCY_LIMIT = 16` is not live-probeable on the default fake success path.** Overlapping in-flight requires 16 streams that have been admitted and not yet credited; this file does not add a hang RPC.

#### 6.3.14 Ephemeral sweep and idempotency TTL

JTI, idempotency, `creditedRequests`, and abandoned `expiresAt` all use `EPHEMERAL_HORIZON_MS = 7_200_000` (2h). Identity already rejects `exp − iat > 600` (`MAX_AAT_LIFETIME_SECONDS`), so a still-valid AAT cannot be presented after its JTI entry would have expired — [§6.3.4](#634-jti-replay) is the live half of that bound; the counterfactual (valid token, expired JTI) cannot happen.

**Do:** more than 2 hours after the **credit** of **KEY0** (credit slides `expiresAt` to now+2h; on the fake path that is essentially 2h after [§6.3.3](#633-first-admit-and-credit)). Mint a new AAT. POST **KEY0** again.

**Expect:** idempotency row gone (`expiresAt <= now` deleted after abandoned sweep). This is a **fresh admit**: new `request_id`, new `usage_event`. The key is not stuck as a completed placeholder. You cannot read the timestamp fields (`expiresAt`, `admittedAt`) directly.

On this adapter, credit follows admit immediately, so you cannot show “retry after the original admission horizon but still inside the slid credit window” as a distinct interval — holding a reservation for ~2h then crediting it is the missing window. The slid **failed** window in [§6.3.10](#6310-abandoned-admission-sweep) is the operator-visible slide: after the sweep mark, a retry inside the next 2h still replays `failed`; after that 2h the key admits fresh.
