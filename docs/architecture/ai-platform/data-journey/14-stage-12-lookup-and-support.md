# AI Platform Data Journey — Stage 12 — Lookup and support

## Table of Contents

1. [`GET /v1/requests/{request_reference}`](#1-get-v1requestsrequest_reference)
2. [`POST /control/support/lookup`](#2-post-controlsupportlookup)
3. [Control-plane route dispatch](#3-control-plane-route-dispatch)
4. [`GET /control/installations/{id}/quota`](#4-get-controlinstallationsidquota)
5. [Dashboard SQL functions (no HTTP route)](#5-dashboard-sql-functions-no-http-route)
6. [`public.record_ai_acceptance()`](#6-publicrecord_ai_acceptance)
7. [Journal retention vs lookup and reconciliation](#7-journal-retention-vs-lookup-and-reconciliation)
8. [Behavioral verification](#8-behavioral-verification)
   - [8.1 Setup](#81-setup)
   - [8.2 Coverage](#82-coverage)
   - [8.3 Ordered probes](#83-ordered-probes)
     - [8.3.1 Capture a completed journal row](#831-capture-a-completed-journal-row)
     - [8.3.2 GET happy path every field](#832-get-happy-path-every-field)
     - [8.3.3 Support lookup happy path every field](#833-support-lookup-happy-path-every-field)
     - [8.3.4 Who may vs may not call each](#834-who-may-vs-may-not-call-each)
     - [8.3.5 Missing and invalid references](#835-missing-and-invalid-references)
     - [8.3.6 Installation scope vs cross-installation lookup](#836-installation-scope-vs-cross-installation-lookup)
     - [8.3.7 Joinability before retention](#837-joinability-before-retention)
     - [8.3.8 Force aged rows and run retention](#838-force-aged-rows-and-run-retention)
     - [8.3.9 After purge: lookup, money row, reconciliation](#839-after-purge-lookup-money-row-reconciliation)
     - [8.3.10 Record AI acceptance RPC](#8310-record-ai-acceptance-rpc)
     - [8.3.11 What this stage does not do](#8311-what-this-stage-does-not-do)

---

## 1. `GET /v1/requests/{request_reference}`

Poll the journal for a request you already submitted. Use this after SSE `completed` (or when you missed the stream) to fetch the validated `result` object.


| Item         | Value                                                       |
| ------------ | ----------------------------------------------------------- |
| Method       | `GET`                                                       |
| Path param   | `request_reference` — Crockford `XXXX-XXXX` (normalized)    |
| Auth         | `Authorization: Bearer <AAT>`                               |
| Request body | **None**                                                    |


**Auth behavior:** `authenticateGetRequest` verifies the AAT (same enrolled-key verifier as `POST /v1/requests`). The journal row must belong to the token's `installation_id`; otherwise the handler returns **404** (same as unknown reference — no cross-tenant leak).

**Success responses (200)** — shape depends on D1 `ai_request.state`:


| `state`            | JSON body                                                                 | When |
| ------------------ | ------------------------------------------------------------------------- | ---- |
| `Completed`        | `{ "state": "Completed", "result": <CanonicalResult> }`                   | Terminal success; R2 envelope loaded via `payload_pointer` |
| `Completed`        | `{ "state": "Completed" }` (no `result` key)                            | Row is `Completed` but envelope missing or corrupt (`resultMissing`) |
| `Failed`           | `{ "state": "Failed", "terminal_error_code": "<taxonomy code>" }`       | Terminal failure |
| `Cancelled`        | `{ "state": "Cancelled" }`                                              | Client or pipeline cancelled |
| `AwaitingContext`  | `{ "state": "AwaitingContext" }`                                        | Conversational capability waiting for more context |
| In-flight          | `{ "state": "<state>", "pending": true }`                                 | e.g. `Accepted`, `Invoking` — not terminal yet |


**Failure responses:**


| HTTP | Body | When |
| ---- | ---- | ---- |
| 401  | Taxonomy JSON `{ "code": "unauthenticated", …, "retry_safe": true }` | Missing/invalid AAT (`getRequestAuthErrorBody` mints a **new** reference, never the path reference) |
| 403  | Taxonomy JSON `{ "code": "installation_suspended", …, "retry_safe": false }` | Suspended installation — `liveHttpStatusForCode("installation_suspended")` = **403**, not 401 |
| 404  | **Empty body** | Unknown/malformed/cross-installation reference, empty path segment, or unrecognized `ai_request.state` string |

Non-GET methods on `/v1/requests/{ref}` and `/v1/requests` (no trailing slash) return plain-text **`Not Found`** — the catch-all route, not the empty-body GET 404.

### 1.1 Reference normalization (clinic GET)

The path param is the raw pathname slice — **no whitespace trim**. `normalizeRequestReference` uppercases and maps ambiguous Crockford chars (`I`/`L`→`1`, `O`→`0`) only. A padded reference 404s on GET.

### 1.2 Code-only GET branches

| Branch | HTTP outcome |
| ------ | ------------ |
| `Failed` with NULL `terminal_error_code` | 200 `{ "state": "Failed", "terminal_error_code": "internal_error" }` |
| Unrecognized `state` string | 404 empty body |
| `Completed` with corrupt/missing R2 envelope | 200 `{ "state": "Completed" }` (no `result`) |

**D1 read:** `ai_request` by `request_reference`. **R2 read:** only when `state = Completed` and `payload_pointer` is set — fetches `request/{request_id}/envelope` and returns `envelope.result`.

## 2. `POST /control/support/lookup`

Operator diagnostic dump for a single request ticket — across **all** installations (no AAT installation scope).


| Item         | Value                                                       |
| ------------ | ----------------------------------------------------------- |
| Method       | `POST`                                                      |
| Auth         | `Authorization: Bearer <OPERATOR_BEARER_TOKEN>`             |
| Query param  | `reference` (required) — same `XXXX-XXXX` ticket            |
| Request body | **None**                                                    |


**Success response (200):**

```json
{
  "request": { /* SupportLookupRequestTrace — journal row fields */ },
  "attempts": [ /* SupportLookupAttemptTrace[] */ ],
  "envelope": { /* full R2 envelope or null if purged / missing */ }
}
```


| Field       | Meaning |
| ----------- | ------- |
| `request`   | D1 `ai_request` trace (installation, capability, state, timestamps, routing, etc.) |
| `attempts`  | Provider attempt rows linked to the request |
| `envelope`  | R2 diagnostic package when still within retention; `null` after purge or missing pointer |


**Failure responses:**


| HTTP | `error`              | When |
| ---- | -------------------- | ---- |
| 401  | `unauthorized`       | Missing or wrong operator bearer |
| 400  | `missing_reference`  | Query param absent |
| 400  | `invalid_reference`  | Not valid `XXXX-XXXX` |
| 404  | `not_found`          | No journal row for that reference |
| 500  | `missing_r2_binding` | Worker misconfiguration |

### 2.1 Reference normalization (support lookup)

Query param `reference` is **trimmed**, then normalized and validated (`support-purge.ts`). Whitespace-padded references succeed on lookup but 404 on the clinic GET — **intentional**: machine clients send exact references; operator tooling is forgiving.

### 2.2 Support lookup envelope fallback (code-only)

When `payload_pointer` is NULL, support lookup still reads R2 at the derived key `request/{request_id}/envelope` (`support/index.ts`). The clinic GET returns `{ "state": "Completed" }` without `result` for the same row.

Lookup writes **no** `control_audit` row (read-only).

Same single shared bearer + `OPERATOR_ID` as every other `/control/*` route: the audit trail cannot distinguish operators.

## 3. Control-plane route dispatch

`worker.ts` admits control routes when `isControlRoute(pathname)` and **either** `method === "POST"` **or** (`method === "GET"` **and** `isQuotaInspectRoute(pathname)`). Every other `/control/*` path on GET returns plain-text `Not Found` before auth. The claim that "`/control/*` is POST-only" is accurate for support lookup but **overbroad** — quota inspect is GET-only inside the dispatcher (`quota-inspect.ts` rejects non-GET with 405).

## 4. `GET /control/installations/{id}/quota` (quota inspect)

Operator read of D1 entitlement + Quota DO state. `verbose=true` adds `maps` (idempotency, jti_replay, admitted_requests, credited_requests) capped at **500 entries per map** (`capMap`); counts in the top-level body are never truncated.

### 4.1 Success response (200)

Top-level keys: `installation_id`, `bound_installation_id`, `period_bounds`, `period_counters` (`requests_used`, `tokens_used`, `cost_used`, `in_flight`), `entitlement` (D1 row or **null** when installation exists but entitlement row is missing), `remaining` (null when entitlement null), `idempotency_keys`, `jti_replay_entries`, `admitted_requests`, `credited_requests`. Optional `maps` when `verbose=true`.

`inspectRPC` runs ephemeral sweeps **in memory only** — no DO `storage.put`.

### 4.2 Failure responses

Dispatch pre-filters with the same regex as the handler (`QUOTA_INSPECT_PATTERN`), so **`400 invalid_route` is unreachable via HTTP** (direct handler invocation only). Reachable failures:

| HTTP | `error` | When |
| ---- | ------- | ---- |
| 401 | `unauthorized` | Missing/wrong operator bearer (runs before method check) |
| 405 | `method_not_allowed` | POST to this path |
| 404 | `installation_not_found` | No `installation` row — DO never contacted |
| 503 | `quota_do_unavailable` | DO binding missing or stub fetch failed/non-OK |

## 5. Dashboard SQL functions (no HTTP route)

Exported from `dashboards/index.ts`; call them directly against migrated D1 — there is no HTTP route.

| Function | Reads | Contract |
| -------- | ----- | -------- |
| `dashboardQuotaRejectionRate(db, now?)` | `platform_counter` (LIKE `%quota_exhausted%`) ÷ in-window `ai_request` count | Numerator is a **lower bound** — only cron-flushed tallies appear; 90-day window matches `JOURNAL_HORIZON_DAYS` |
| `dashboardRepairRateByCapability(db, now?)` | `ai_attempt` LEFT JOIN `ai_request` | Repair attempts ÷ Completed+Failed requests per `capability_id`; Cancelled/in-flight excluded |

Other exports (`dashboardAvgAttemptLatencyByProvider`, `dashboardValidationFailureByPromptVersion`, `dashboardFallbackRateByProvider`, `dashboardCostPerCapabilityPerInstallation`, `runAllDashboardQueries`) follow the same SQL-contract pattern.

## 6. `public.record_ai_acceptance()`

Clinic-side acceptance recording — **not** an HTTP route on the AI platform. After a terminal SSE `completed`, staff may persist AI-generated clinical content through this RPC; the gateway is not involved and D1 is not written.

**Source:** `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql` (F2); contract `specs/040-acceptance-recording/contracts/acceptance-recording.md`.


| Item         | Value                                                                 |
| ------------ | --------------------------------------------------------------------- |
| Method       | RPC (PostgREST `POST /rest/v1/rpc/record_ai_acceptance`)               |
| Auth         | Authenticated staff session (`GRANT … TO authenticated`)              |
| Wrapper      | `public.record_ai_acceptance` — `SECURITY DEFINER` → `auth_internal.record_ai_acceptance` |
| Request body | `{ "p_request_reference": "…", "p_target_key": "…", "p_target_args": { … } }` |


**Parameters:**


| Parameter              | Type   | Meaning                                                                 |
| ---------------------- | ------ | ----------------------------------------------------------------------- |
| `p_request_reference`  | text   | Terminal SSE / journal ticket — Crockford `XXXX-XXXX` (§8.9 format)     |
| `p_target_key`         | text   | Allow-listed key from `ai_internal.acceptance_targets` (e.g. `visit_clinical_notes`) |
| `p_target_args`        | jsonb  | Named arguments for the registered domain RPC (never a raw function name) |


**`rpc_result` envelope:**


| Field           | Type    | Meaning                                      |
| --------------- | ------- | -------------------------------------------- |
| `success`       | boolean | `true` when domain write + provenance committed |
| `data`          | object  | Merged domain + acceptance fields (below)    |
| `error_code`    | text    | Machine code when `success = false`          |
| `error_message` | text    | Human-readable detail when `success = false` |


**Success `data` — minimum keys** (merged with delegated domain RPC `data`):


| Field            | Type   | Meaning                                                |
| ---------------- | ------ | ------------------------------------------------------ |
| `acceptance_id`  | uuid   | New `ai_accepted_output.id`                            |
| `table_name`     | text   | Domain table written (registry vocabulary)               |
| `record_id`      | uuid   | Domain row id (`visit_id` / `record_id` / `id` from domain) |
| `audit_log_id`   | uuid   | `audit_log` row with `action = 'ai.acceptance_record'` |


Plus any keys returned by the delegated domain RPC (demonstration target: `save_visit_documentation`).

**Failure paths (acceptance layer):**


| Condition | `error_code` | When |
| --------- | ------------ | ---- |
| Malformed `p_request_reference` (not `XXXX-XXXX` Crockford) | `INVALID_INPUT` | Before any write |
| Unregistered `p_target_key` | `INVALID_INPUT` | Before any write |
| Duplicate `(table_name, record_id, ai_request_reference)` | `INVALID_INPUT` | Before delegated domain call |
| Missing JWT organization | `FORBIDDEN` | Before any write |
| Registry / catalog misconfiguration | `INTERNAL_ERROR` | Domain function not in registry or not `rpc_result` |
| Domain write did not return a record id | *(transaction abort)* | Post-delegation exception — not a soft `rpc_result` |

**Delegated errors:** when `auth_internal.invoke_acceptance_domain_rpc` calls the registered domain function (e.g. `save_visit_documentation`) and that RPC returns `success = false`, `record_ai_acceptance` returns **that** `error_code` and `error_message` unchanged — no `ai_accepted_output` row, no acceptance audit. Acceptance adds no new error vocabulary beyond existing clinic codes.

**Registry (demonstration target):** `visit_clinical_notes` → `save_visit_documentation` → table `visit_clinical_notes`.

## 7. Journal retention vs lookup and reconciliation

After the journal horizon, `runRetentionPurge` nulls `usage_event.request_id` and deletes the
`ai_request` row. Support lookup by `request_reference` then finds nothing: the ticket is gone.
The usage money row remains, but it cannot be joined back to a request. `runReconciliation`'s
`LEFT JOIN usage_event u ON u.request_id = r.request_id` likewise cannot match those aged rows,
so reconciliation coverage shrinks with age. See [§9 in Alternative journeys](15-alternative-and-failure-journeys.md#9-journal-retention-and-aged-usage-joinability).

## 8. Behavioral verification

Live probes against a local Worker. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§8.3](#83-ordered-probes) top to bottom** on a throwaway local D1. If every probe matches, this stage is working.

Clinic poll is `authenticateGetRequest` + `getRequest` scoped to the AAT's `installationId`. Support dump is `requireOperator` + `supportLookup` with **no** installation filter. Journal purge is cron `0 3 * * *` (`runRetentionPurge`), not either HTTP route.

### 8.1 Setup

- Local Worker. For [§8.3.8](#838-force-aged-rows-and-run-retention) the process must expose the scheduled handler:

```bash
cd ai-platform
npx wrangler dev --env development --test-scheduled
```

`npm run dev` is the same origin without `--test-scheduled`; restart with the flag before the retention probes.

- Enrolled, entitled installation **I0** and a staff AAT whose `iss` is **I0** ([Stage 6](08-stage-6-minting-an-aat.md)). Same token that can `POST /v1/requests`.
- `OPERATOR_BEARER_TOKEN` (Workers secret) and `OPERATOR_ID` (`platform-operator` in `wrangler.toml` `[env.development.vars]`). One shared bearer for every `/control/*` route.
- Clinic `org` / `branch` that match the AAT, for the optional live `POST /v1/requests` in [§8.3.1](#831-capture-a-completed-journal-row).
- D1 inspect as:

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export AAT='…'
export INSTALLATION_ID='<I0>'

cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT 1"
```

Prefer a database you can wipe: [§8.3.8](#838-force-aged-rows-and-run-retention) backdates `created_at` and the cron **deletes** that journal row.

### 8.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| `GET /v1/requests/{ref}` auth is Bearer AAT (`authenticateGetRequest`) | [§8.3.2](#832-get-happy-path-every-field), [§8.3.4](#834-who-may-vs-may-not-call-each) |
| GET uses isolate-scoped `ConfigCache` (same instance as `POST /v1/requests`) | [§8.3.2](#832-get-happy-path-every-field) (same AAT verifies both). Singleton identity is **unprobeable** from HTTP — see note below |
| GET scope must match `ai_request.installation_id` | [§8.3.6](#836-installation-scope-vs-cross-installation-lookup) |
| D1 read is `ai_request` by `request_reference` | [§8.3.1](#831-capture-a-completed-journal-row), [§8.3.2](#832-get-happy-path-every-field) |
| `Completed` + `payload_pointer` set → R2 envelope → HTTP `result` | [§8.3.2](#832-get-happy-path-every-field) |
| `Completed` with no envelope payload → `{ "state": "Completed" }` and no `result` | [§8.3.2](#832-get-happy-path-every-field) |
| GET happy-path JSON is only `state` + `result` (every `CanonicalResult` field) | [§8.3.2](#832-get-happy-path-every-field) |
| Operator bearer / missing / empty Bearer cannot GET | [§8.3.4](#834-who-may-vs-may-not-call-each) |
| Suspended installation → GET `403` `installation_suspended` | [§8.3.4](#834-who-may-vs-may-not-call-each) |
| Unknown or mismatched GET reference → empty `404` body | [§8.3.5](#835-missing-and-invalid-references), [§8.3.6](#836-installation-scope-vs-cross-installation-lookup) |
| `POST /control/support/lookup` requires `OPERATOR_BEARER_TOKEN` (`requireOperator`) | [§8.3.4](#834-who-may-vs-may-not-call-each) |
| Support lookup is by `request_reference` across installations | [§8.3.3](#833-support-lookup-happy-path-every-field), [§8.3.6](#836-installation-scope-vs-cross-installation-lookup) |
| Lookup happy path returns every `request`, `attempts[]`, and `envelope` field | [§8.3.3](#833-support-lookup-happy-path-every-field) |
| Same shared bearer + `OPERATOR_ID` as every other `/control/*`; audit cannot distinguish operators | [§8.3.4](#834-who-may-vs-may-not-call-each) |
| Lookup writes no `control_audit` row | [§8.3.3](#833-support-lookup-happy-path-every-field) |
| Quota inspect GET; `400 invalid_route` unreachable via HTTP | [§4](#4-get-controlinstallationsidquota) |
| Dashboard SQL functions have no HTTP route | [§5](#5-dashboard-sql-functions-no-http-route) |
| Reference trim asymmetry (support trims; clinic GET does not) | [§1.1](#11-reference-normalization-clinic-get), [§2.1](#21-reference-normalization-support-lookup) |
| AAT cannot call support lookup; GET on support lookup does not reach the handler (quota inspect is the only GET `/control/*` route) | [§8.3.4](#834-who-may-vs-may-not-call-each) |
| Missing / blank lookup `reference` → `400` `missing_reference` | [§8.3.5](#835-missing-and-invalid-references) |
| Invalid lookup `reference` → `400` `invalid_reference` | [§8.3.5](#835-missing-and-invalid-references) |
| Unknown but well-formed lookup `reference` → `404` `not_found` | [§8.3.5](#835-missing-and-invalid-references) |
| Before journal horizon, `usage_event.request_id` joins to `ai_request` | [§8.3.7](#837-joinability-before-retention) |
| After journal horizon, `runRetentionPurge` nulls `usage_event.request_id` and deletes `ai_request` | [§8.3.8](#838-force-aged-rows-and-run-retention), [§8.3.9](#839-after-purge-lookup-money-row-reconciliation) |
| Support lookup (and GET) then find nothing; money row remains | [§8.3.9](#839-after-purge-lookup-money-row-reconciliation) |
| `LEFT JOIN usage_event u ON u.request_id = r.request_id` cannot match aged rows; coverage shrinks | [§8.3.9](#839-after-purge-lookup-money-row-reconciliation) |
| `public.record_ai_acceptance` — `rpc_result`, success merge, `INVALID_INPUT` / `FORBIDDEN` / `INTERNAL_ERROR`, delegated pass-through ([§6](#6-publicrecord_ai_acceptance)) | [§8.3.10](#8310-record-ai-acceptance-rpc) |
| This stage does not admit, settle, entitle, or restore joinability | [§8.3.11](#8311-what-this-stage-does-not-do) |


**Unprobeable from HTTP / local wrangler:** that `authenticateGetRequest` and `POST /v1/requests` share the *same module-scope* `isolateConfigCache` object (code identity; the probes only show the same AAT verifies both). `500` `missing_r2_binding` (R2 is bound in `wrangler.toml`). Ledger deletion of `usage_event` at `LEDGER_HORIZON_DAYS` (2555) — not this stage's journal-horizon claim.

### 8.3 Ordered probes

#### 8.3.1 Capture a completed journal row

**Do:** find a `Completed` row that still has an R2 pointer (settlement from Stages 10–11):

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, request_reference, installation_id, state, payload_pointer
   FROM ai_request
   WHERE installation_id = '$INSTALLATION_ID'
     AND state = 'Completed'
     AND payload_pointer IS NOT NULL
   ORDER BY completed_at DESC
   LIMIT 1"
```

If that is empty, **do** one live visit-summary (new idempotency key). Capture `request_reference` from the SSE `accepted` event, then poll GET until `state` is `Completed` and `result` is present (`writePostResponseDetail` runs on `waitUntil`):

```bash
curl -sN -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(uuidgen)" \
  -H "x-capability-version: 1.0.0" \
  -d '{
    "capability_id": "clinic.visit_summary",
    "user_intent": "Summarize the visit for the chart.",
    "context": {
      "org": "<must match AAT org>",
      "branch": "<must match AAT branch>",
      "visit.chief_complaint@v1": "Patient reports headache for 3 days."
    }
  }'
```

**Expect:** one row. Save `request_reference` as **REF**, `request_id` as **RID**, `installation_id` as **I0**, `payload_pointer` as **PTR**.

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT usage_event_id, request_id, tokens, cost, recorded_at
   FROM usage_event WHERE request_id = '<RID>'"
```

**Expect:** at least one money row. Save `usage_event_id` as **UEID**. `request_id = RID`. This is the join [§7](#7-journal-retention-vs-lookup-and-reconciliation) will later sever.

#### 8.3.2 GET happy path every field

**Do:**

```bash
curl -sS -D - "$GATEWAY/v1/requests/$REF" \
  -H "Authorization: Bearer $AAT"
```

**Expect:** HTTP 200. Body has **exactly** these top-level keys:

- `state` = `"Completed"`
- `result` — the envelope `result` (`CanonicalResult`), **every** field:
  - `finalContent`
  - `usage.input`, `usage.output`, `usage.cached`
  - `providerModel.provider`, `providerModel.model`
  - `finishReason`
  - `providerRequestId`
  - `timing.queue_ms`, `timing.provider_ms`, `timing.total_ms`

No `attempts`, no `envelope`, no `request_id`, no `installation_id`. The clinic poll is not the support dump. The same AAT that admitted `POST /v1/requests` verifies here (`authenticateGetRequest` default cache is `isolateConfigCache`, the same singleton POST uses).

**Do:** force the documented “pointer set” branch’s inverse, then restore:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE ai_request SET payload_pointer = NULL WHERE request_reference = '<REF>'"

curl -sS "$GATEWAY/v1/requests/$REF" \
  -H "Authorization: Bearer $AAT"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE ai_request SET payload_pointer = '<PTR>' WHERE request_reference = '<REF>'"
```

**Expect:** while the pointer is null, HTTP 200 `{ "state": "Completed" }` with **no** `result` (`resultMissing`). After restore, GET again returns `result` as before. [§1](#1-get-v1requestsrequest_reference) fetches R2 only when `payload_pointer` is set.

#### 8.3.3 Support lookup happy path every field

**Do:** count audit rows, then lookup. Query string, not JSON body. Support lookup is POST-only; quota inspect is the sole GET `/control/*` route ([§3](#3-control-plane-route-dispatch)).

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT COUNT(*) AS c FROM control_audit"

curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=$REF" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT COUNT(*) AS c FROM control_audit"
```

**Expect:** HTTP 200. Body keys are `request`, `attempts`, `envelope`. **Every** field:

`request`:

- `requestId` = **RID**
- `requestReference` = **REF** (normalized Crockford; lookup trims then `normalizeRequestReference`)
- `installationId` = **I0**
- `actorId`, `branchId` (branch may be JSON `null`)
- `capabilityId`, `capabilityVersion`
- `promptArtifactHash`
- `state` = `"Completed"`
- `createdAt`, `updatedAt`, `completedAt`
- `terminalErrorCode` (`null` on this happy path)
- `traceId`
- `payloadPointer` = **PTR**

`attempts[]` (one row per `ai_attempt`; settlement writes at least one):

- `attemptNo`, `provider`, `model`, `outcome`
- `latencyMs`, `tokensIn`, `tokensOut`, `cost`
- `providerRequestId`, `errorCode`

`envelope` is the R2 JSON (not `null` while `clinic.visit_summary` is inside `diagnostic_30d`): `context`, `prompt`, `attempts`, `result`. `envelope.result` matches GET `result`.

`control_audit` count is **unchanged**. Lookup does not insert an audit row. The shared-`OPERATOR_ID` claim is visible on routes that *do* audit ([§8.3.4](#834-who-may-vs-may-not-call-each)).

#### 8.3.4 Who may vs may not call each

**Do:** GET with no `Authorization`, with `Authorization: Bearer ` (empty token), and with the operator secret:

```bash
curl -sS -D - "$GATEWAY/v1/requests/$REF"

curl -sS -D - "$GATEWAY/v1/requests/$REF" \
  -H "Authorization: Bearer "

curl -sS -D - "$GATEWAY/v1/requests/$REF" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

**Expect:** HTTP 401 each time. JSON taxonomy body `{ "code": "unauthenticated", "request_reference", "trace_id", "retry_safe": true }` — `getRequestAuthErrorBody` mints a **new** `request_reference`; it is not **REF**. Empty body is not used here. Operator bearer is not an AAT; `EnrolledKeyVerifier` rejects it. `getRequest` is not reached.

**Do:** GET with a well-formed path and no reference segment (auth not required on this branch):

```bash
curl -sS -D - "$GATEWAY/v1/requests/"
```

**Expect:** HTTP 404, **empty** body (`new Response(null, { status: 404 })` before `authenticateGetRequest`).

**Do:** lookup with no bearer, with the clinic AAT, and GET (wrong method) on the control path:

```bash
curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=$REF"

curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=$REF" \
  -H "Authorization: Bearer $AAT"

curl -sS -D - "$GATEWAY/control/support/lookup?reference=$REF" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

**Expect:** both POSTs without the operator secret → HTTP 401 `{ "error": "unauthorized" }` (`requireOperator`; not a taxonomy body). GET on the support-lookup path → HTTP 404 `Not Found` text: support lookup is POST-only; quota inspect is the only GET `/control/*` route ([§3](#3-control-plane-route-dispatch)). Clinic AAT is not the operator bearer.

**Do:** suspend **I0** with the **same** operator token, GET with the AAT, then resume:

```bash
curl -sS -D - -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/suspend" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

curl -sS -D - "$GATEWAY/v1/requests/$REF" \
  -H "Authorization: Bearer $AAT"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT operator_id, action, target FROM control_audit ORDER BY recorded_at DESC LIMIT 3"

curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/resume" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

**Expect:** suspend HTTP 200. GET → HTTP 403 `{ "code": "installation_suspended", …, "retry_safe": false }`. `control_audit.operator_id` is `platform-operator` (the configured `OPERATOR_ID`), `action` is `suspend`, `target` is **I0**. A second operator cannot appear: there is one bearer and one id for every `/control/*` route, including lookup. Resume HTTP 200. GET with the AAT again returns [§8.3.2](#832-get-happy-path-every-field).

#### 8.3.5 Missing and invalid references

**Do:** GET a Crockford-shaped ticket that does not exist (still send the AAT — auth runs first):

```bash
curl -sS -D - "$GATEWAY/v1/requests/AAAA-BBBB" \
  -H "Authorization: Bearer $AAT"
```

**Expect:** HTTP 404, **empty** body. `getRequest` returns `found: false`; the Worker does not send `{ "error": "not_found" }`. A malformed path such as `SHORT` is the same empty 404 (GET does not run `isValidRequestReference`).

**Do:** lookup missing, blank, invalid, and unknown-but-valid references (operator token required or you will see 401 first):

```bash
curl -sS -D - -X POST "$GATEWAY/control/support/lookup" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=%20%20" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=SHORT" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=AAAA-BBBB" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

**Expect:** no / empty / whitespace `reference` → HTTP 400 `{ "error": "missing_reference" }`. `SHORT` (fails `isValidRequestReference` after normalize) → HTTP 400 `{ "error": "invalid_reference" }`. `AAAA-BBBB` (valid shape, no row) → HTTP 404 `{ "error": "not_found" }`.

#### 8.3.6 Installation scope vs cross-installation lookup

GET scopes to the AAT’s installation; lookup does not. **Do** insert a second installation row (not a full enroll) and point **REF** at it, then restore:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
   VALUES ('verify-other-installation', 'verify-other-org', 'Other', 'active', 'local', datetime('now'))"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE ai_request SET installation_id = 'verify-other-installation'
   WHERE request_reference = '<REF>'"

curl -sS -D - "$GATEWAY/v1/requests/$REF" \
  -H "Authorization: Bearer $AAT"

curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=$REF" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE ai_request SET installation_id = '<I0>'
   WHERE request_reference = '<REF>'"
```

**Expect:** GET → HTTP 404, empty body (`installation_id` mismatch is indistinguishable from missing). Lookup → HTTP 200, `request.installationId` = `verify-other-installation` — support reads `WHERE request_reference = ?` with no installation predicate. After restore, GET returns [§8.3.2](#832-get-happy-path-every-field) again.

#### 8.3.7 Joinability before retention

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT u.usage_event_id, u.request_id AS usage_request_id, r.request_id AS journal_id,
          r.request_reference
   FROM usage_event u
   LEFT JOIN ai_request r ON r.request_id = u.request_id
   WHERE u.usage_event_id = '<UEID>'"
```

**Expect:** `usage_request_id` = `journal_id` = **RID**, `request_reference` = **REF**. The money row still joins. This is the `LEFT JOIN usage_event u ON u.request_id = r.request_id` that `runReconciliation` uses, in the direction that still matches.

#### 8.3.8 Force aged rows and run retention

Do **not** wait 90 days. Journal purge keys off `ai_request.created_at < now − JOURNAL_HORIZON_DAYS` (`90`). Leave `usage_event.recorded_at` alone so ledger purge (`LEDGER_HORIZON_DAYS` = 2555) does not delete the money row.

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE ai_request
   SET created_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-91 days')
   WHERE request_reference = '<REF>'"
```

Confirm the Worker was started with `--test-scheduled` ([§8.1](#81-setup)). **Do** fire the retention cron (`wrangler.toml` `[triggers] crons` includes `0 3 * * *`):

```bash
curl -sS "$GATEWAY/cdn-cgi/handler/scheduled?cron=0+3+*+*+*&format=json"
```

**Expect:** `{ "outcome": "ok", "noRetry": false }`. `scheduled()` runs `runRetentionPurge` on that cron (after rejection-counter flush and grace reconcile). Inside the purge, for this row: R2 envelope delete, `UPDATE usage_event SET request_id = NULL WHERE request_id IN (SELECT request_id FROM ai_request WHERE created_at < ?)`, then `DELETE` `ai_attempt` and `ai_request`.

#### 8.3.9 After purge: lookup, money row, reconciliation

**Do:**

```bash
curl -sS -D - "$GATEWAY/v1/requests/$REF" \
  -H "Authorization: Bearer $AAT"

curl -sS -D - -X POST "$GATEWAY/control/support/lookup?reference=$REF" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id FROM ai_request WHERE request_reference = '<REF>'
   UNION ALL
   SELECT request_id FROM ai_request WHERE request_id = '<RID>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT usage_event_id, request_id, tokens, cost, recorded_at
   FROM usage_event WHERE usage_event_id = '<UEID>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT u.usage_event_id, u.request_id AS usage_request_id, r.request_id AS journal_id
   FROM usage_event u
   LEFT JOIN ai_request r ON r.request_id = u.request_id
   WHERE u.usage_event_id = '<UEID>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT r.request_id, r.request_reference
   FROM ai_request r
   LEFT JOIN usage_event u ON u.request_id = r.request_id
   WHERE r.state IN ('Completed', 'Failed', 'Cancelled')
     AND u.usage_event_id IS NULL
     AND r.request_id = '<RID>'"
```

**Expect:** GET → empty HTTP 404. Lookup → HTTP 404 `{ "error": "not_found" }`. The ticket is gone. **UEID** still exists; `request_id` is **NULL**; `tokens` / `cost` unchanged. `journal_id` is NULL — the money row cannot be joined back to a request. The request-centric reconciliation query (same `LEFT JOIN` as `runReconciliation`) returns **no row** for **RID**: coverage shrank because the journal side of the join was deleted, and a nulled `usage_event.request_id` can never match a remaining `ai_request`. The leftover usage is commercial evidence only.

#### 8.3.10 Record AI acceptance RPC

Clinic Postgres probe for [§6](#6-publicrecord_ai_acceptance) — not the Worker HTTP surface.

**Do:** with a completed visit-summary job, save **REF** from SSE `accepted`. As clinician with `visits.edit_soap`, call with a bogus reference:

```sql
SELECT public.record_ai_acceptance(
  'NOT-VALID',
  'visit_clinical_notes',
  '{"p_visit_id": "<visit uuid>", "p_complaint": "AI draft text"}'::jsonb
);
```

**Expect:** `success = false`, `error_code = 'INVALID_INPUT'`, message about standard request-reference format. No `ai_accepted_output` row.

**Do:** well-formed Crockford **REF** but unregistered target:

```sql
SELECT public.record_ai_acceptance(
  '<REF>',
  'not_a_registered_target',
  '{}'::jsonb
);
```

**Expect:** `success = false`, `error_code = 'INVALID_INPUT'`, `Acceptance target is not registered.`

**Do:** registered target with domain args that fail the delegated RPC (e.g. missing required `p_visit_id`):

```sql
SELECT public.record_ai_acceptance(
  '<REF>',
  'visit_clinical_notes',
  '{}'::jsonb
);
```

**Expect:** `success = false` with the **delegated** domain `error_code` / `error_message` unchanged (not rewritten to acceptance vocabulary). No `ai_accepted_output` row.

**Do:** happy path with valid visit id **V0**, matching `p_target_args` for `save_visit_documentation`, and a **new** Crockford reference **REF2** (never accepted before):

```sql
SELECT public.record_ai_acceptance(
  '<REF2>',
  'visit_clinical_notes',
  jsonb_build_object(
    'p_visit_id', '<V0>',
    'p_complaint', 'Accepted AI summary text'
  )
);
```

**Expect:** `success = true`. `data` includes `acceptance_id`, `table_name = 'visit_clinical_notes'`, `record_id`, `audit_log_id`, plus domain fields from `save_visit_documentation`. One `ai_accepted_output` row with `ai_request_reference = REF2`. `audit_log` has `action = 'ai.acceptance_record'`.

**Do:** repeat the same **REF2** for the same record:

```sql
SELECT public.record_ai_acceptance(
  '<REF2>',
  'visit_clinical_notes',
  jsonb_build_object('p_visit_id', '<V0>', 'p_complaint', 'duplicate attempt')
);
```

**Expect:** `success = false`, `error_code = 'INVALID_INPUT'`, duplicate acceptance message — rejected **before** the delegated write.

#### 8.3.11 What this stage does not do

**Do:** GET the (now-missing) **REF** and inspect the JSON you stored from [§8.3.2](#832-get-happy-path-every-field). **Do** lookup **REF** again. **Do** compare `control_audit` after a lookup-only POST (use any still-live reference if you kept a second row; otherwise this is the 404 lookup you just ran).

**Expect:**

- GET never returned `attempts` or `envelope` and never wrote D1/R2. It does not admit (`POST /v1/requests`), entitle, or settle.
- Lookup does not mint AATs, enroll, invoke a provider, or run retention. Cron `0 3 * * *` purged; `POST /control/installations/{id}/purge` is a different route.
- Neither route restored `usage_event.request_id`. Re-running lookup/GET cannot rebuild the journal ticket.
- Lookup still does not distinguish operators: one bearer, one `OPERATOR_ID`, and this route writes no audit row of its own.
- `record_ai_acceptance` is clinic-side only — this stage documents it for the acceptance journey but does not expose it over the AI gateway.

