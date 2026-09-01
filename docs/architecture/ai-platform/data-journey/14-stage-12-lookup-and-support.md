# AI Platform Data Journey — Stage 12 — Lookup and support

## Table of Contents

1. [`GET /v1/requests/{request_reference}`](#1-get-v1requestsrequest_reference)
2. [`POST /control/support/lookup`](#2-post-controlsupportlookup)
3. [Journal retention vs lookup and reconciliation](#3-journal-retention-vs-lookup-and-reconciliation)
4. [Behavioral verification](#4-behavioral-verification)
   - [4.1 Setup](#41-setup)
   - [4.2 Coverage](#42-coverage)
   - [4.3 Ordered probes](#43-ordered-probes)
     - [4.3.1 Capture a completed journal row](#431-capture-a-completed-journal-row)
     - [4.3.2 GET happy path every field](#432-get-happy-path-every-field)
     - [4.3.3 Support lookup happy path every field](#433-support-lookup-happy-path-every-field)
     - [4.3.4 Who may vs may not call each](#434-who-may-vs-may-not-call-each)
     - [4.3.5 Missing and invalid references](#435-missing-and-invalid-references)
     - [4.3.6 Installation scope vs cross-installation lookup](#436-installation-scope-vs-cross-installation-lookup)
     - [4.3.7 Joinability before retention](#437-joinability-before-retention)
     - [4.3.8 Force aged rows and run retention](#438-force-aged-rows-and-run-retention)
     - [4.3.9 After purge: lookup, money row, reconciliation](#439-after-purge-lookup-money-row-reconciliation)
     - [4.3.10 What this stage does not do](#4310-what-this-stage-does-not-do)

---

## 1. `GET /v1/requests/{request_reference}`


| Item  | Value                                  |
| ----- | -------------------------------------- |
| Auth  | Bearer AAT — `authenticateGetRequest` uses the isolate-scoped `ConfigCache` (same instance as `POST /v1/requests`) |

| Scope | Must match installation on journal row |


**D1 read:** `ai_request` by `request_reference`.

**If** `state === Completed` **and** `payload_pointer` **set:** R2 fetch envelope → return `result` from envelope.

## 2. `POST /control/support/lookup`

`OPERATOR_BEARER_TOKEN` required (`requireOperator`). Looks up by `request_reference` across
installations (`control/support-lookup.ts`). Same single shared bearer + `OPERATOR_ID` as every
other `/control/*` route: the audit trail cannot distinguish operators.

## 3. Journal retention vs lookup and reconciliation

After the journal horizon, `runRetentionPurge` nulls `usage_event.request_id` and deletes the
`ai_request` row. Support lookup by `request_reference` then finds nothing: the ticket is gone.
The usage money row remains, but it cannot be joined back to a request. `runReconciliation`'s
`LEFT JOIN usage_event u ON u.request_id = r.request_id` likewise cannot match those aged rows,
so reconciliation coverage shrinks with age. See [§9 in Alternative journeys](15-alternative-and-failure-journeys.md#9-journal-retention-and-aged-usage-joinability).

## 4. Behavioral verification

Live probes against a local Worker. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§4.3](#43-ordered-probes) top to bottom** on a throwaway local D1. If every probe matches, this stage is working.

Clinic poll is `authenticateGetRequest` + `getRequest` scoped to the AAT's `installationId`. Support dump is `requireOperator` + `supportLookup` with **no** installation filter. Journal purge is cron `0 3 * * *` (`runRetentionPurge`), not either HTTP route.

### 4.1 Setup

- Local Worker. For [§4.3.8](#438-force-aged-rows-and-run-retention) the process must expose the scheduled handler:

```bash
cd ai-platform
npx wrangler dev --env development --test-scheduled
```

`npm run dev` is the same origin without `--test-scheduled`; restart with the flag before the retention probes.

- Enrolled, entitled installation **I0** and a staff AAT whose `iss` is **I0** ([Stage 6](08-stage-6-minting-an-aat.md)). Same token that can `POST /v1/requests`.
- `OPERATOR_BEARER_TOKEN` (Workers secret) and `OPERATOR_ID` (`platform-operator` in `wrangler.toml` `[env.development.vars]`). One shared bearer for every `/control/*` route.
- Clinic `org` / `branch` that match the AAT, for the optional live `POST /v1/requests` in [§4.3.1](#431-capture-a-completed-journal-row).
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

Prefer a database you can wipe: [§4.3.8](#438-force-aged-rows-and-run-retention) backdates `created_at` and the cron **deletes** that journal row.

### 4.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| `GET /v1/requests/{ref}` auth is Bearer AAT (`authenticateGetRequest`) | [§4.3.2](#432-get-happy-path-every-field), [§4.3.4](#434-who-may-vs-may-not-call-each) |
| GET uses isolate-scoped `ConfigCache` (same instance as `POST /v1/requests`) | [§4.3.2](#432-get-happy-path-every-field) (same AAT verifies both). Singleton identity is **unprobeable** from HTTP — see note below |
| GET scope must match `ai_request.installation_id` | [§4.3.6](#436-installation-scope-vs-cross-installation-lookup) |
| D1 read is `ai_request` by `request_reference` | [§4.3.1](#431-capture-a-completed-journal-row), [§4.3.2](#432-get-happy-path-every-field) |
| `Completed` + `payload_pointer` set → R2 envelope → HTTP `result` | [§4.3.2](#432-get-happy-path-every-field) |
| `Completed` with no envelope payload → `{ "state": "Completed" }` and no `result` | [§4.3.2](#432-get-happy-path-every-field) |
| GET happy-path JSON is only `state` + `result` (every `CanonicalResult` field) | [§4.3.2](#432-get-happy-path-every-field) |
| Operator bearer / missing / empty Bearer cannot GET | [§4.3.4](#434-who-may-vs-may-not-call-each) |
| Suspended installation → GET `403` `installation_suspended` | [§4.3.4](#434-who-may-vs-may-not-call-each) |
| Unknown or mismatched GET reference → empty `404` body | [§4.3.5](#435-missing-and-invalid-references), [§4.3.6](#436-installation-scope-vs-cross-installation-lookup) |
| `POST /control/support/lookup` requires `OPERATOR_BEARER_TOKEN` (`requireOperator`) | [§4.3.4](#434-who-may-vs-may-not-call-each) |
| Support lookup is by `request_reference` across installations | [§4.3.3](#433-support-lookup-happy-path-every-field), [§4.3.6](#436-installation-scope-vs-cross-installation-lookup) |
| Lookup happy path returns every `request`, `attempts[]`, and `envelope` field | [§4.3.3](#433-support-lookup-happy-path-every-field) |
| Same shared bearer + `OPERATOR_ID` as every other `/control/*`; audit cannot distinguish operators | [§4.3.4](#434-who-may-vs-may-not-call-each) |
| Lookup writes no `control_audit` row | [§4.3.3](#433-support-lookup-happy-path-every-field) |
| AAT cannot call support lookup; GET method does not reach the control dispatcher | [§4.3.4](#434-who-may-vs-may-not-call-each) |
| Missing / blank lookup `reference` → `400` `missing_reference` | [§4.3.5](#435-missing-and-invalid-references) |
| Invalid lookup `reference` → `400` `invalid_reference` | [§4.3.5](#435-missing-and-invalid-references) |
| Unknown but well-formed lookup `reference` → `404` `not_found` | [§4.3.5](#435-missing-and-invalid-references) |
| Before journal horizon, `usage_event.request_id` joins to `ai_request` | [§4.3.7](#437-joinability-before-retention) |
| After journal horizon, `runRetentionPurge` nulls `usage_event.request_id` and deletes `ai_request` | [§4.3.8](#438-force-aged-rows-and-run-retention), [§4.3.9](#439-after-purge-lookup-money-row-reconciliation) |
| Support lookup (and GET) then find nothing; money row remains | [§4.3.9](#439-after-purge-lookup-money-row-reconciliation) |
| `LEFT JOIN usage_event u ON u.request_id = r.request_id` cannot match aged rows; coverage shrinks | [§4.3.9](#439-after-purge-lookup-money-row-reconciliation) |
| This stage does not admit, settle, entitle, or restore joinability | [§4.3.10](#4310-what-this-stage-does-not-do) |


**Unprobeable from HTTP / local wrangler:** that `authenticateGetRequest` and `POST /v1/requests` share the *same module-scope* `isolateConfigCache` object (code identity; the probes only show the same AAT verifies both). `500` `missing_r2_binding` (R2 is bound in `wrangler.toml`). Ledger deletion of `usage_event` at `LEDGER_HORIZON_DAYS` (2555) — not this stage's journal-horizon claim.

### 4.3 Ordered probes

#### 4.3.1 Capture a completed journal row

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

**Expect:** at least one money row. Save `usage_event_id` as **UEID**. `request_id = RID`. This is the join [§3](#3-journal-retention-vs-lookup-and-reconciliation) will later sever.

#### 4.3.2 GET happy path every field

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

#### 4.3.3 Support lookup happy path every field

**Do:** count audit rows, then lookup. Query string, not JSON body. Live Worker accepts **POST** only on `/control/*`.

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

`control_audit` count is **unchanged**. Lookup does not insert an audit row. The shared-`OPERATOR_ID` claim is visible on routes that *do* audit ([§4.3.4](#434-who-may-vs-may-not-call-each)).

#### 4.3.4 Who may vs may not call each

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

**Expect:** both POSTs without the operator secret → HTTP 401 `{ "error": "unauthorized" }` (`requireOperator`; not a taxonomy body). The GET → HTTP 404 `Not Found` text: `worker.ts` dispatches `/control/*` only on **POST**, so the lookup handler never runs. Clinic AAT is not the operator bearer.

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

**Expect:** suspend HTTP 200. GET → HTTP 403 `{ "code": "installation_suspended", …, "retry_safe": false }`. `control_audit.operator_id` is `platform-operator` (the configured `OPERATOR_ID`), `action` is `suspend`, `target` is **I0**. A second operator cannot appear: there is one bearer and one id for every `/control/*` route, including lookup. Resume HTTP 200. GET with the AAT again returns [§4.3.2](#432-get-happy-path-every-field).

#### 4.3.5 Missing and invalid references

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

#### 4.3.6 Installation scope vs cross-installation lookup

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

**Expect:** GET → HTTP 404, empty body (`installation_id` mismatch is indistinguishable from missing). Lookup → HTTP 200, `request.installationId` = `verify-other-installation` — support reads `WHERE request_reference = ?` with no installation predicate. After restore, GET returns [§4.3.2](#432-get-happy-path-every-field) again.

#### 4.3.7 Joinability before retention

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

#### 4.3.8 Force aged rows and run retention

Do **not** wait 90 days. Journal purge keys off `ai_request.created_at < now − JOURNAL_HORIZON_DAYS` (`90`). Leave `usage_event.recorded_at` alone so ledger purge (`LEDGER_HORIZON_DAYS` = 2555) does not delete the money row.

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE ai_request
   SET created_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-91 days')
   WHERE request_reference = '<REF>'"
```

Confirm the Worker was started with `--test-scheduled` ([§4.1](#41-setup)). **Do** fire the retention cron (`wrangler.toml` `[triggers] crons` includes `0 3 * * *`):

```bash
curl -sS "$GATEWAY/cdn-cgi/handler/scheduled?cron=0+3+*+*+*&format=json"
```

**Expect:** `{ "outcome": "ok", "noRetry": false }`. `scheduled()` runs `runRetentionPurge` on that cron (after rejection-counter flush and grace reconcile). Inside the purge, for this row: R2 envelope delete, `UPDATE usage_event SET request_id = NULL WHERE request_id IN (SELECT request_id FROM ai_request WHERE created_at < ?)`, then `DELETE` `ai_attempt` and `ai_request`.

#### 4.3.9 After purge: lookup, money row, reconciliation

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

#### 4.3.10 What this stage does not do

**Do:** GET the (now-missing) **REF** and inspect the JSON you stored from [§4.3.2](#432-get-happy-path-every-field). **Do** lookup **REF** again. **Do** compare `control_audit` after a lookup-only POST (use any still-live reference if you kept a second row; otherwise this is the 404 lookup you just ran).

**Expect:**

- GET never returned `attempts` or `envelope` and never wrote D1/R2. It does not admit (`POST /v1/requests`), entitle, or settle.
- Lookup does not mint AATs, enroll, invoke a provider, or run retention. Cron `0 3 * * *` purged; `POST /control/installations/{id}/purge` is a different route.
- Neither route restored `usage_event.request_id`. Re-running lookup/GET cannot rebuild the journal ticket.
- Lookup still does not distinguish operators: one bearer, one `OPERATOR_ID`, and this route writes no audit row of its own.

