# AI Platform Data Journey — Stage 11 — Terminal settlement (D1, R2, Quota DO)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [Quota DO credit (`kind: credit`)](#3-quota-do-credit-kind-credit)
4. [D1 `ai_request` UPDATE (terminal)](#4-d1-ai_request-update-terminal)
5. [D1 `ai_attempt` INSERT (per attempt)](#5-d1-ai_attempt-insert-per-attempt)
6. [D1 `usage_event` INSERT](#6-d1-usage_event-insert)
7. [R2 envelope — every field](#7-r2-envelope-every-field)
8. [Happy path settlement diagram](#8-happy-path-settlement-diagram)
9. [Failed and cancelled credit](#9-failed-and-cancelled-credit)
10. [Acceptance recording](#10-acceptance-recording-record_ai_acceptance)
11. [Behavioral verification](#11-behavioral-verification)
   - [11.1 Setup](#111-setup)
   - [11.2 Coverage](#112-coverage)
   - [11.3 Ordered probes](#113-ordered-probes)
     - [11.3.1 Complete a request then inspect](#1131-complete-a-request-then-inspect)
     - [11.3.2 D1 ai_request terminal UPDATE](#1132-d1-ai_request-terminal-update)
     - [11.3.3 D1 ai_attempt INSERT every column](#1133-d1-ai_attempt-insert-every-column)
     - [11.3.4 D1 usage_event INSERT every column](#1134-d1-usage_event-insert-every-column)
     - [11.3.5 R2 envelope every field](#1135-r2-envelope-every-field)
     - [11.3.6 Quota DO credit (kind credit)](#1136-quota-do-credit-kind-credit)
     - [11.3.7 Failed credit](#1137-failed-credit)
     - [11.3.8 Cancelled credit](#1138-cancelled-credit)
     - [11.3.9 What this stage does not do](#1139-what-this-stage-does-not-do)
     - [11.3.10 Clients cannot read control tables](#11310-clients-cannot-read-control-tables)

---

## 1. Plain language

Every terminal outcome credits the Quota DO so `inFlight` is released and the idempotency entry leaves `"admitted"`. Completed, failed, and cancelled terminals then reuse the same post-response journal writers: `ai_attempt` row(s), one `usage_event`, one R2 diagnostic envelope (`request/{request_id}/envelope`), and `ai_request.payload_pointer`. Failed/cancelled credit accrued usage (including `{ tokens: 0, cost: 0 }`). Cost on those rows is computed by one shared helper (`src/pricing`) from the versioned platform price table (`control/pricing/platform-default/1.json`): provider-reported input/output tokens × per-1K model rates. `ai_attempt.cost` and `usage_event.cost` therefore agree. Cancel without provider usage uses the named char-as-output-token estimate (`estimateUsageFromStreamedChars`) through that same helper. Money appears only here — the preflight stays token-only (§13.6.2).

**Journal vs Quota DO:** `usage_event` (and `ai_attempt`, R2 envelope, `payload_pointer`) are written only by the journal path (`persistPostResponseDetail` in `src/journal/index.ts`) — **never** by the Quota DO, which mutates only its own storage.

## 2. Metaphor

**Closing the flight log** — stamp the ledger (DO + usage_event), file the full incident report in the warehouse (R2 envelope), update the index card (payload_pointer).

## 3. Quota DO credit (`kind: credit`)


| Field in RPC        | Source |
| ------------------- | ------ |
| `installationId`    | Principal |
| `requestId`         | journal row |
| `requestReference`  | Crockford ref from admission |
| `usage.tokens`      | Success: `usage.input + usage.output`. Failed/cancelled: accrued partial usage, or `{ tokens: 0, cost: 0 }` when none. |
| `usage.cost`        | Success: `priceUsage` on the provider result (same helper as `ai_attempt.cost`). Zero-usage terminals: `0`. Cancel/fail with accrued usage: that partial-usage cost (provider tokens × rates, or `estimateUsageFromStreamedChars` when usage was not reported). |
| `partial`           | From §5.4 taxonomy `consumesQuota`: `"Yes"` → `false` (full consume); `"Partially, recorded"` → `true`. Success always `false`. |
| `idempotencyState`  | Optional. `"completed"` / `"failed"` / `"cancelled"`. Omitted → `partial ? "cancelled" : "completed"`. |
| `terminalErrorCode` | Optional taxonomy code stored on the idempotency entry when `idempotencyState` is `"failed"` — replayed on idempotent retry (C-11) |
| `entitlement`       | Optional. Admission-time entitlement snapshot (`period_start` / `period_end` and budgets). Worker always sends it so credit and D1 share the same period. |

`jti` and `x-idempotency-key` are consumed at **`kind: admission`** only; credit finds the reservation by `requestId` and slides the matching idempotency `expiresAt`.


**DO state changes on credit:**

- Re-run `maybeResetPeriod` against the credit RPC's entitlement (or the snapshot stored on `admittedRequests[requestId]` at admit) **before** applying usage, so a period boundary between admit and credit does not land the tokens in a different period than D1
- `tokensUsed += usage.tokens`
- `costUsed += usage.cost`
- `requestsUsed += 1`
- `inFlight -= 1`
- Delete `admittedRequests[requestId]`
- Set `creditedRequests[requestId]` (`expiresAt = now + 2h`)
- Update idempotency state → `completed`, `failed`, or `cancelled` (never left `"admitted"`)
- Slide the matching idempotency `expiresAt` to `now + EPHEMERAL_HORIZON_MS` so a later retry of the same key still dedupes for another 2h



## 4. D1 `ai_request` UPDATE (terminal)


| State       | `completed_at` | `terminal_error_code` |
| ----------- | -------------- | --------------------- |
| `Completed` | now            | unchanged             |
| `Failed`    | now            | taxonomy code         |
| `Cancelled` | now            | unchanged             |


Only updates if current state not already terminal.

## 5. D1 `ai_attempt` INSERT (per attempt)


| Column                    | Source                        |
| ------------------------- | ----------------------------- |
| `attempt_id`              | new ULID                      |
| `request_id`              | journal                       |
| `attempt_no`              | sequence                      |
| `provider`                | e.g. `deepseek`               |
| `model`                   | e.g. `deepseek-v4-flash`      |
| `outcome`                 | `success`, `truncation`, `retryable_failure`, `terminal_failure`, `timeout`, or `repair`. Truncation is **not** a Completed request — the attempt row stays `truncation` while `ai_request` settles `Failed` / `validation_failed`. `repair` is the numerator for `dashboardRepairRateByCapability` (repair attempts ÷ Completed+Failed requests by capability over the journal window; Cancelled excluded). |
| `latency_ms`              | measured                      |
| `tokens_in`, `tokens_out` | from provider                 |
| `cost`                    | Shared helper: `priceUsage({ modelId, inputTokens, outputTokens })` from the bundled price table. Zero when the attempt had no tokens. |
| `provider_request_id`     | provider id                   |
| `error_code`              | if failed attempt             |




## 6. D1 `usage_event` INSERT


| Column            | Source                               |
| ----------------- | ------------------------------------ |
| `usage_event_id`  | new ULID                             |
| `installation_id` | principal                            |
| `period`          | `YYYY-MM` from the admission-time entitlement `period_start` (`periodFromIso(period_start)`), **not** wall-clock at credit |
| `request_id`      | journal (`ai_request.request_id` at insert; later SET NULL by retention) |
| `quota_weight`    | manifest `Economics.quotaWeight` (1) |
| `tokens`          | total tokens (zero allowed on fail/cancel) |
| `cost`            | Completed: same `priceUsage` value as the successful attempt. Fail/cancel: partial-usage cost from the same helper (or `0` when none). |
| `recorded_at`     | ISO now                              |


`usage_event.request_id` is nullable so journal retention can keep the money row after deleting
aged `ai_request` rows (`UPDATE usage_event SET request_id = NULL` then `DELETE` the journal).
That permanently severs request-level joinability for aged usage. `runReconciliation`'s
`LEFT JOIN usage_event u ON u.request_id = r.request_id` can never match those rows, so
reconciliation coverage shrinks with age by design.




## 7. R2 envelope — every field

**Key:** `request/{request_id}/envelope`

```json
{
  "context": { /* filteredContext from guard stage 6 */ },
  "prompt": { /* CanonicalRequest — composed artifact text lives here; the artifact *ref* is implied by D1 capability_id+version. D1 `prompt_artifact_hash` is the content hash of those bound artifact bytes, not the ref. */ },
  "attempts": [ /* size-capped raw provider bodies per attempt (`payload` + `truncated`); 16 KB cap */ ],
  "result": { /* CanonicalResult; fail/cancel use a placeholder with finishReason = taxonomy code */ }
}
```

Written once per request (§7.4.1) on **every** terminal that reaches settlement: `Completed`, `Failed`, and `Cancelled`. Not a second object on failure.

Each `attempts[]` entry is `AttemptRecord.rawBody` from the adapter/transport (`captureRawProviderBody` in `src/provider/raw-body.ts`), not an empty `{}`. Truncation sets `truncated: true` and keeps the first 16 KB. Empty-chain `provider_unavailable` (no adapter invoke) stores a diagnostic payload `{ reason: "no_provider_attempt", excluded }` so the Failed row still has evidence.

**Write order:**

1. D1 batch: `ai_attempt` + `usage_event`
2. `R2.put(envelope)`
3. D1 UPDATE `ai_request.payload_pointer = key`



## 8. Happy path settlement diagram

```
Provider success
  → broker emits completed SSE
  → recordTerminalState(Completed)
  → creditUsage(DO, partial=false, entitlement=admission snapshot)
  → writePostResponseDetail(D1 attempts + usage_event + R2 envelope + payload_pointer)

Invocation failure or cancel (including zero usage)
  → creditUsage(DO, partial per §5.4, entitlement=admission snapshot) unless the broker already credited
  → writePostResponseDetail(same writers — attempts + usage_event + one R2 envelope)
  → recordTerminalState(Failed | Cancelled)
```

Healthy path: one Quota DO `credit` (`partial: false`) after admit — two DO round trips total. Failed/cancelled do **not** add a third call on this path.

If the request was **grace-admitted** (Quota DO was down at stage 8), the same `creditUsage` call also UPDATEs the pending D1 `grace_admission_queue` row with `usage_tokens` / `usage_cost` / `partial`. That attach is what cron reconciliation credits later; the DO `credit` itself is ignored while the DO is still down.

## 9. Failed and cancelled credit

Non-completed terminals still call `credit` (possibly zero usage) so the DO releases `inFlight` and the idempotency key leaves `"admitted"`. Without that credit, a retry of the same key while still in-flight would replay as **`accepted` only** (no fabricated completion — C-04). If the Worker crashes and never credits, the 2h abandoned-admission sweep marks that key `failed` (and slides `expiresAt`) so a later retry replays SSE `failed` with the stored `terminalErrorCode` (fallback `internal_error`), not the completed placeholder and not a second charge.


| Terminal | Taxonomy | `partial` | `idempotencyState` |
| -------- | -------- | --------- | ------------------ |
| Success | — | `false` | `completed` (omitted; mapped from `partial`) |
| `provider_rejected`, `validation_failed` | consumes `"Yes"` | `false` | `failed` |
| `provider_unavailable`, `timeout`, `cancelled` | consumes `"Partially, recorded"` | `true` | `failed` or `cancelled` |

Invocation failure credits in the worker with `ignoreBrokerSettlement` so the broker's disconnect-as-cancel does not double-credit. Broker `handleFailed` / `handleCancel` credit via the credit sink (including zero usage); the worker does not credit again when the broker already settled, but still writes the D1/R2 journal (`skipCredit: true`).

Failed requests always persist at least one `ai_attempt` row (collected `attemptRecords`, or a diagnostic row from the routing exclusion list when the chain was empty). Cancelled requests write `usage_event` always; `ai_attempt` only when invocation recorded attempts (abort before the first provider call is expected to have none).

**Caller-abort during an in-flight invoke:** when the client signal aborts while `port.invoke` is running, `processInvokeResult` terminal-classifies the error as `cancelled` and records one `ai_attempt` row with `outcome 'terminal_failure'`, `error_code 'cancelled'` (tokens/cost 0 on the attempt row — partial usage flows to credit/`usage_event` separately). A **pre-attempt** abort (signal already set before the first `recordAttempt`) yields zero `ai_attempt` rows but still journals `usage_event`.

**Client drop:** on a true disconnect the broker emits `cancelled` into a dead stream (`markCancelledWithoutEnqueue` in `src/adapter.ts`) — the dropped connection shows no terminal frame, but settlement (credit + journal) still runs. Observe `cancelled` on the wire only via idempotent replay ([Stage 10 §11.7](12-stage-10-accept-route-invoke-stream.md#117-cancelled)).

Cron `runReconciliation` uses that expected profile and does **not** flag Cancelled-without-attempts or AwaitingContext. It flags Completed/Failed missing attempts or usage, and Cancelled missing `usage_event`.

## 10. Acceptance recording (`record_ai_acceptance`)

After settlement, the clinic may persist AI output into domain tables via Supabase `public.record_ai_acceptance(request_reference, target_key, target_args)` (delegates to `auth_internal.record_ai_acceptance`).

**Duplicate guard (broader than the UNIQUE constraint):** before any domain write, the RPC rejects when `(ai_request_reference, table_name)` already exists in `ai_accepted_output` — even if `record_id` differs. The table UNIQUE is `(table_name, record_id, ai_request_reference)`; the pre-check prevents accepting the same reference into a second row of the same table.

**Visit-summary provenance:** for target `save_visit_documentation`, `table_name` is `'visit_clinical_notes'` but `record_id` stored in `ai_accepted_output` is the **visit uuid** (`data->>'visit_id'` from the domain RPC), not the clinical-note row id. Joining `ai_accepted_output.record_id` to `visit_clinical_notes.id` will miss — resolve via `visit_clinical_notes.visit_id`.

## 11. Behavioral verification

Live probes against a local Worker after Stage 10 has produced an `ai_request` row. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§11.3](#113-ordered-probes) top to bottom**. If every probe matches, this stage is working.

Stage 10 opens the SSE stream and invokes the provider. This stage is everything after the terminal event: Quota DO `kind: credit`, D1 `ai_request` UPDATE, `ai_attempt` / `usage_event` INSERT, one R2 envelope, `payload_pointer`. Inspect D1 and R2 as **wrangler** (privileged). The AAT is only an HTTP client.

### 11.1 Setup

- Local Worker: `cd ai-platform && npm run dev` (`http://127.0.0.1:8787`). D1 database and R2 bucket `ai-platform-development`, `--local --env development`.
- Clinic already enrolled, entitled, and granted `clinic.visit_summary` (Stages 3–6). Stage 10 must be able to pass the guard and emit SSE `accepted`.
- Staff AAT from `issue_ai_token` with `ai.visit_summary`. Visit-summary body from [Stage 8 §7](10-stage-8-request-ingress.md#7-visit-summary-example-body): `context.org` / `context.branch` match the token.
- Happy-path probes need a reachable provider (DeepSeek or Gemini on the local Worker). Failed and cancelled probes do not.
- Distinct `x-idempotency-key` values: **K0** (complete), **KF** (fail), **KC** (cancel). Reusing a key inside the 2h DO window replays; it does not settle a second job.
- After each stream, save SSE `request_reference` as **REF**. D1 `request_id` is **RID** — the SSE `accepted` event does not include it.
- Wrangler is the only way to `SELECT` journal tables and `GET` the envelope object. There is no first-class dump of Quota DO storage; observe credit through replay and D1.

```bash
export GATEWAY='http://127.0.0.1:8787'
export AAT='…'
export IDEM0="verify-settle-$(date +%s)-0"
```

```bash
post_request() {
  local key="$1"
  curl -sN -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $AAT" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $key" \
    -H "x-capability-version: 1.0.0" \
    -d '{
      "capability_id": "clinic.visit_summary",
      "user_intent": "Summarize today'"'"'s visit for the chart.",
      "context": {
        "org": "<must match AAT org>",
        "branch": "<must match AAT branch>",
        "visit.chief_complaint@v1": "Patient reports headache for 3 days."
      }
    }'
}
```

Read D1 / R2 from `ai-platform`:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT 1"
```

### 11.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| [§8](#8-happy-path-settlement-diagram) happy path: SSE `completed` → `recordTerminalState(Completed)` → `creditUsage` (`partial: false`) → post-response writers | [§11.3.1](#1131-complete-a-request-then-inspect) |
| [§4](#4-d1-ai_request-update-terminal) Completed: `state = Completed`, `completed_at` set, `terminal_error_code` unchanged (null) | [§11.3.2](#1132-d1-ai_request-terminal-update) |
| Terminal UPDATE is a no-op once already terminal | [§11.3.2](#1132-d1-ai_request-terminal-update) |
| [§5](#5-d1-ai_attempt-insert-per-attempt) INSERT every column: `attempt_id` (ULID), `request_id`, `attempt_no`, `provider`, `model`, `outcome`, `latency_ms`, `tokens_in`, `tokens_out`, `cost`, `provider_request_id`, `error_code` | [§11.3.3](#1133-d1-ai_attempt-insert-every-column) |
| Happy `outcome = success`; `cost` from `priceUsage` (`control/pricing/platform-default/1.json`); tokens from the provider | [§11.3.3](#1133-d1-ai_attempt-insert-every-column) |
| Truncation is **not** a Completed request (`outcome` stays `truncation`; `ai_request` is Failed / `validation_failed`) | [§11.3.3](#1133-d1-ai_attempt-insert-every-column) if that outcome appears; not forceable on a healthy provider — see unprobeable |
| `repair` rows are the dashboard repair-rate numerator (Cancelled excluded) | This stage only **writes** `outcome`; it does not compute the rate. Inspect if a repair row exists; see unprobeable |
| [§6](#6-d1-usage_event-insert) INSERT every column: `usage_event_id` (ULID), `installation_id`, `period`, `request_id`, `quota_weight`, `tokens`, `cost`, `recorded_at` | [§11.3.4](#1134-d1-usage_event-insert-every-column) |
| `period` is `YYYY-MM` from admission-time `period_start`, not wall-clock at credit; `quota_weight = 1` | [§11.3.4](#1134-d1-usage_event-insert-every-column) |
| `ai_attempt.cost` and `usage_event.cost` agree; `usage_event.tokens = tokens_in + tokens_out` on success | [§11.3.3](#1133-d1-ai_attempt-insert-every-column), [§11.3.4](#1134-d1-usage_event-insert-every-column) |
| Money appears only here — preflight stays token-only | [§11.3.9](#1139-what-this-stage-does-not-do) |
| This stage does **not** `SET NULL` `usage_event.request_id` (retention is later) | [§11.3.4](#1134-d1-usage_event-insert-every-column), [§11.3.9](#1139-what-this-stage-does-not-do) |
| [§7](#7-r2-envelope-every-field) key `request/{request_id}/envelope`; fields `context`, `prompt`, `attempts`, `result` | [§11.3.5](#1135-r2-envelope-every-field) |
| `attempts[]` is captured raw body (`payload` + `truncated`, 16 KB cap), not `{}` | [§11.3.5](#1135-r2-envelope-every-field) |
| One envelope per request on **every** terminal — not a second object on failure | [§11.3.5](#1135-r2-envelope-every-field), [§11.3.7](#1137-failed-credit) |
| Write order: D1 `ai_attempt` + `usage_event` → `R2.put` → `payload_pointer` | [§11.3.5](#1135-r2-envelope-every-field) |
| Empty-chain `provider_unavailable` stores `{ reason: "no_provider_attempt", excluded }` | [§11.3.7](#1137-failed-credit) |
| [§3](#3-quota-do-credit-kind-credit) `kind: credit`: `installationId`, `requestId`, `requestReference`, usage, `partial: false` on success, optional `terminalErrorCode` on failed, entitlement snapshot, `idempotencyState` completed (or omitted → completed) | [§11.3.6](#1136-quota-do-credit-kind-credit) |
| `usage_event` written by journal (`persistPostResponseDetail`), never by the Quota DO | [§1](#1-plain-language), [§11.3.4](#1134-d1-usage_event-insert-every-column) |
| Caller-abort during in-flight invoke → `ai_attempt` `terminal_failure` / `error_code cancelled` | [§9](#9-failed-and-cancelled-credit) |
| `record_ai_acceptance` duplicate pre-check on `(reference, table_name)`; visit id under `visit_clinical_notes` | [§10](#10-acceptance-recording-record_ai_acceptance) |
| Credit RPC is internal (`quota-do.internal`); not a public HTTP route — observe effects via replay of the same `x-idempotency-key` | [§11.3.6](#1136-quota-do-credit-kind-credit), [§11.3.10](#11310-clients-cannot-read-control-tables) |
| DO: `tokensUsed` / `costUsed` / `requestsUsed` increment; `inFlight -= 1`; `admittedRequests[requestId]` deleted; idempotency leaves `"admitted"` | [§11.3.6](#1136-quota-do-credit-kind-credit) |
| Healthy path: one credit after admit (two DO round trips); failed/cancelled do not add a third | [§11.3.6](#1136-quota-do-credit-kind-credit), [§11.3.7](#1137-failed-credit), [§11.3.8](#1138-cancelled-credit) |
| [§9](#9-failed-and-cancelled-credit) Failed: `partial` from taxonomy; `idempotencyState = failed`; `completed_at` set; `terminal_error_code` = taxonomy; ≥1 `ai_attempt`; `usage_event` (zeros allowed) | [§11.3.7](#1137-failed-credit) |
| `provider_unavailable` / `timeout` / `cancelled` → `partial: true`; `provider_rejected` / `validation_failed` → `partial: false` | [§11.3.7](#1137-failed-credit) for unavailable; Yes-consume codes are not forceable live — see unprobeable |
| Invocation failure still one `usage_event` / one envelope (`ignoreBrokerSettlement`; no double-credit) | [§11.3.7](#1137-failed-credit) |
| [§9](#9-failed-and-cancelled-credit) Cancelled: `partial: true`; `idempotencyState = cancelled`; `terminal_error_code` unchanged; `usage_event` always; `ai_attempt` only if invocation recorded attempts | [§11.3.8](#1138-cancelled-credit) |
| Cancel without provider usage → `{ tokens: 0, cost: 0 }`; cancel after `text_delta` uses `estimateUsageFromStreamedChars` | [§11.3.8](#1138-cancelled-credit) |
| Retry after credit does **not** emit `"Prior request completed."` for failed/cancelled; completed retry **does** (idempotent replay) | [§11.3.6](#1136-quota-do-credit-kind-credit), [§11.3.7](#1137-failed-credit), [§11.3.8](#1138-cancelled-credit) |
| Cron `runReconciliation` profile: Completed/Failed need attempts **and** usage; Cancelled needs usage; Cancelled-without-attempts and AwaitingContext are not flagged | [§11.3.9](#1139-what-this-stage-does-not-do) |
| Grace-admitted attach to `grace_admission_queue` (`usage_tokens` / `usage_cost` / `partial`) | Healthy path: table unused ([§11.3.9](#1139-what-this-stage-does-not-do)). DO-down attach is not live-probeable |
| What this stage does not do (Stage 12 APIs, retention NULL, second R2 object, preflight cost, public `kind: credit`) | [§11.3.9](#1139-what-this-stage-does-not-do) |
| Stage 12 handoff this doc asserts: `GET /v1/requests/{REF}` returns envelope `result` for Completed — not control tables | [§11.3.10](#11310-clients-cannot-read-control-tables) |
| Clients / AAT cannot `SELECT` `ai_request` / `ai_attempt` / `usage_event`; wrangler can | [§11.3.10](#11310-clients-cannot-read-control-tables) |


**Not live-probeable** (do not wait 2h, crash the Worker, or take the Quota DO down): period-boundary `maybeResetPeriod` between admit and credit; 2h abandoned-admission sweep → idempotency `failed`; retry while still `"admitted"` emits **`accepted` only** (no fabricated completion — C-04); grace-queue attach while the DO is down; forcing `truncation` / `repair` / `timeout` / `retryable_failure` / `provider_rejected` / output-guard `validation_failed`; dumping DO `creditedRequests` / slid `expiresAt`; a raw provider body larger than 16 KB; counting DO RPCs with wrangler.

### 11.3 Ordered probes

#### 11.3.1 Complete a request then inspect

**Do:** capture the admission-time period, then run a fresh visit-summary to completion:

```bash
cd ai-platform
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT installation_id, period_start, period_end, request_quota, token_budget, cost_budget
   FROM entitlement WHERE status = 'active' LIMIT 1"
```

Save `period_start` as **PS** (ISO). `usage_event.period` must be the first seven characters (`YYYY-MM`), not today's month if they differ.

**Do:** `post_request "$IDEM0"` and wait until the stream ends.

**Expect:** SSE `accepted` (with `request_reference`) then a terminal `completed` (not `failed` / `cancelled`). Save that reference as **REF0**. This is the [§8](#8-happy-path-settlement-diagram) happy path: broker `completed` → terminal Completed → one Quota DO credit → the same post-response writers as fail/cancel.

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, request_reference, state, completed_at, terminal_error_code, payload_pointer
   FROM ai_request WHERE request_reference = '<REF0>'"
```

**Expect:** one row. Save `request_id` as **RID0**. `state = 'Completed'`. Settlement has run; the next probes inspect that row’s attempt, usage, envelope, and credit.

#### 11.3.2 D1 ai_request terminal UPDATE

**Do:** as wrangler, read every column this stage stamps on the Completed row:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, state, completed_at, terminal_error_code, payload_pointer, updated_at
   FROM ai_request WHERE request_id = '<RID0>'"
```

**Expect:** `state = 'Completed'`. `completed_at` is an ISO timestamp (now relative to the stream). `terminal_error_code` is **NULL** — Completed does not write a taxonomy code ([§4](#4-d1-ai_request-update-terminal)). `payload_pointer = 'request/<RID0>/envelope'`.

**Do:** POST the **same** `x-idempotency-key` **K0** again (`post_request "$IDEM0"`).

**Expect:** idempotent replay (Stage 10 — no new D1 INSERT). Re-read **RID0**: `state`, `completed_at`, and `terminal_error_code` are unchanged. The UPDATE is a no-op once the row is already terminal. Replay may emit placeholder `"Prior request completed."` — that is DO idempotency after credit, not a second settlement.

#### 11.3.3 D1 ai_attempt INSERT every column

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT attempt_id, request_id, attempt_no, provider, model, outcome,
          latency_ms, tokens_in, tokens_out, cost, provider_request_id, error_code
   FROM ai_attempt WHERE request_id = '<RID0>' ORDER BY attempt_no"
```

**Expect:** at least one row. Every [§5](#5-d1-ai_attempt-insert-per-attempt) column is present:

- `attempt_id` — non-empty ULID text
- `request_id` = **RID0**
- `attempt_no` — 1-based sequence (`1` on a single-attempt success)
- `provider` — `deepseek` or `gemini` (the chain entry that succeeded)
- `model` — e.g. `deepseek-v4-flash` or `gemini-3.5-flash`
- `outcome` — `success` on this happy path. Legal values are `success`, `truncation`, `retryable_failure`, `terminal_failure`, `timeout`, `repair`. If you ever see `truncation`, **RID0 would not be Completed** — the attempt stays `truncation` and `ai_request` settles Failed / `validation_failed`.
- `latency_ms` — measured, ≥ 0
- `tokens_in`, `tokens_out` — provider-reported (not both stuck at a dummy 0.001 cost)
- `cost` — `priceUsage({ modelId, inputTokens: tokens_in, outputTokens: tokens_out })` from `control/pricing/platform-default/1.json` (per-1K rates; 6 decimal places). Zero only if that attempt had no tokens.
- `provider_request_id` — provider id when the adapter returned one (nullable)
- `error_code` — NULL on success

Rates in that table today: `deepseek-v4-flash` 0.14 / 0.28; `gemini-3.5-flash` 0.075 / 0.3 (input / output per 1K). Check `cost ≈ (tokens_in/1000)*input_per_1k + (tokens_out/1000)*output_per_1k`.

`selection_reason` is **not** a D1 column on this table (Stage 10 documents it as invoke metadata). Do not expect it in this `SELECT`.

#### 11.3.4 D1 usage_event INSERT every column

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT usage_event_id, installation_id, period, request_id,
          quota_weight, tokens, cost, recorded_at
   FROM usage_event WHERE request_id = '<RID0>'"
```

**Expect:** exactly **one** row. Every [§6](#6-d1-usage_event-insert) column:

- `usage_event_id` — new ULID
- `installation_id` — the principal (same as `ai_request.installation_id`)
- `period` — `YYYY-MM` of **PS**, e.g. `2026-08` from `2026-08-01T00:00:00.000Z`, **not** wall-clock month at credit if they differ
- `request_id` = **RID0** (not NULL — this stage does not run retention)
- `quota_weight` — `1` (`Economics.quotaWeight` on `clinic.visit_summary`)
- `tokens` — total; on success equals `tokens_in + tokens_out` of the successful attempt
- `cost` — **same number** as that attempt’s `cost` (shared `priceUsage` helper)
- `recorded_at` — ISO now

**Do:** compare the two cost columns:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT a.cost AS attempt_cost, u.cost AS usage_cost, a.tokens_in, a.tokens_out, u.tokens
   FROM ai_attempt a
   JOIN usage_event u ON u.request_id = a.request_id
   WHERE a.request_id = '<RID0>' AND a.outcome = 'success'"
```

**Expect:** `attempt_cost = usage_cost`. `u.tokens = tokens_in + tokens_out`. Preflight did not write this row — it appears only after the terminal.

#### 11.3.5 R2 envelope every field

**Do:** fetch the object the pointer names (privileged R2, not the AAT):

```bash
npx wrangler r2 object get ai-platform-development \
  "request/<RID0>/envelope" --file /tmp/envelope-rid0.json --local
python3 -m json.tool /tmp/envelope-rid0.json | head
```

**Expect:** the get succeeds. Top-level keys are exactly [§7](#7-r2-envelope-every-field):

| Field | Expect |
| ----- | ------ |
| `context` | Object — filtered context from the guard (includes the visit-summary keys that passed). Not the raw unfiltered body dump. |
| `prompt` | CanonicalRequest object (composed artifact text lives here). Non-empty `parts` (or equivalent). D1 `prompt_artifact_hash` is the content hash of bound artifact bytes, not this ref. |
| `attempts` | Array, one entry per `ai_attempt`. Each entry is captured raw body: `payload` plus `truncated` (boolean). Not `{}`. `truncated: true` only if the raw body exceeded 16 KB (first 16 KB kept). |
| `result` | CanonicalResult: `finalContent`, `usage` (`input` / `output` / `cached`), `providerModel` (`provider` / `model`), `finishReason`, `providerRequestId`, `timing` (`queue_ms` / `provider_ms` / `total_ms`). Completed uses the provider result, not a taxonomy placeholder. |

**Do:** confirm write order completed:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT payload_pointer FROM ai_request WHERE request_id = '<RID0>'"
```

**Expect:** `payload_pointer` equals `request/<RID0>/envelope`. Attempts and usage rows already exist ([§11.3.3](#1133-d1-ai_attempt-insert-every-column)–[§11.3.4](#1134-d1-usage_event-insert-every-column)) **and** the object is in R2 **and** the pointer matches — the three steps in [§7](#7-r2-envelope-every-field) write order. There is still only **one** object for this `request_id` (no `envelope-2`, no failure sidecar).

#### 11.3.6 Quota DO credit (kind credit)

There is no wrangler dump of DO storage. The credit RPC is `POST https://quota-do.internal/rpc` with `kind: "credit"` inside the Worker ([§3](#3-quota-do-credit-kind-credit)). Observe the **effects**.

**Do:** POST a **new** idempotency key (not K0) with the same AAT (`post_request` a fresh key) and let it complete or at least pass `accepted`.

**Expect:** admission succeeds (`inFlight` was released by the prior credit). If `inFlight` were still held at the concurrency cap, this would be `concurrency_exhausted`. One successful follow-up job is enough to show the slot is free.

**Do:** retry **K0** again (already done in [§11.3.2](#1132-d1-ai_request-terminal-update); repeat if needed).

**Expect:** SSE terminal `completed` with placeholder `"Prior request completed."` — idempotency state is `completed`, **not** `"admitted"`. A still-admitted retry would be the same placeholder for the wrong reason ([§9](#9-failed-and-cancelled-credit)); after this credit, D1 **RID0** stays Completed with usage already written, and the retry does **not** INSERT a second `usage_event` for **RID0**.

**Do:** count ledger rows for **RID0**:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT
     (SELECT COUNT(*) FROM usage_event WHERE request_id = '<RID0>') AS usage_rows,
     (SELECT COUNT(*) FROM ai_attempt WHERE request_id = '<RID0>') AS attempt_rows"
```

**Expect:** `usage_rows = 1`. Retry did not credit again. Healthy path is **one** `kind: credit` after the original admit (two DO round trips total). `partial` was `false`; `usage.tokens` / `usage.cost` match the usage_event; Worker always sends the admission entitlement snapshot so `period` in D1 matches **PS**.

**Do:** `curl -s -X POST "$GATEWAY/quota-do.internal/rpc"` (or any path with body `{"kind":"credit"}`) with the AAT.

**Expect:** not a credit RPC. That URL is Durable Object internal. The AAT cannot invoke `kind: credit`. Credit finds the reservation by `requestId` and slides the matching idempotency `expiresAt` (2h). Do not wait 2h to prove the slide — immediate replay already shows the key is still remembered.

#### 11.3.7 Failed credit

Force an empty provider chain so settlement is Failed / `provider_unavailable` without depending on a live model.

**Do:** as wrangler, exclude both named providers, then restart the local Worker (or wait 30 s) so ConfigCache is cold:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "INSERT OR REPLACE INTO kill_switch (scope, target, active, changed_at, changed_by)
   VALUES
     ('provider', 'deepseek', 1, datetime('now'), 'verify-settle'),
     ('provider', 'gemini', 1, datetime('now'), 'verify-settle')"
```

Restart `npm run dev`. Then `export IDEMF="verify-settle-fail-$(date +%s)"` and `post_request "$IDEMF"`.

**Expect:** SSE `accepted`, then `failed` with `provider_unavailable`. Save **REFF** / **RIDF**.

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT state, completed_at, terminal_error_code, payload_pointer
   FROM ai_request WHERE request_id = '<RIDF>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT attempt_id, attempt_no, provider, model, outcome, latency_ms,
          tokens_in, tokens_out, cost, provider_request_id, error_code
   FROM ai_attempt WHERE request_id = '<RIDF>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT usage_event_id, period, quota_weight, tokens, cost, request_id
   FROM usage_event WHERE request_id = '<RIDF>'"
```

**Expect:**

- `ai_request.state = 'Failed'`, `completed_at` set, `terminal_error_code = 'provider_unavailable'` ([§4](#4-d1-ai_request-update-terminal) Failed row).
- **At least one** `ai_attempt` ([§9](#9-failed-and-cancelled-credit)). Empty-chain diagnostic: `outcome = 'terminal_failure'`, `latency_ms = 0`, `tokens_in = 0`, `tokens_out = 0`, `cost = 0`, `error_code = 'provider_unavailable'`.
- Exactly one `usage_event`: `tokens = 0`, `cost = 0` allowed; `period` still from **PS**; `quota_weight = 1`; `request_id = RIDF`. One row — invocation failure sets `ignoreBrokerSettlement` so broker cancel does not double-credit.

**Do:**

```bash
npx wrangler r2 object get ai-platform-development \
  "request/<RIDF>/envelope" --file /tmp/envelope-ridf.json --local
python3 -c 'import json; e=json.load(open("/tmp/envelope-ridf.json")); print(sorted(e.keys())); print(e["attempts"][0]); print(e["result"].get("finishReason"))'
```

**Expect:** the **same four** envelope fields as Completed. Not a second key. `attempts[0].payload` contains `reason: "no_provider_attempt"` and `excluded` (the killed targets). `attempts[0].truncated` is `false`. `result.finishReason` is the taxonomy code (`provider_unavailable`) — fail/cancel placeholder ([§7](#7-r2-envelope-every-field)). `payload_pointer` on **RIDF** is `request/<RIDF>/envelope`.

**Do:** `post_request "$IDEMF"` again (same **KF**).

**Expect:** SSE `failed` (Stage 10 replays DO `failed` with the stored **`terminalErrorCode`** — `provider_unavailable` for this probe, not a generic `internal_error`). **Not** `"Prior request completed."`. No second `usage_event` for **RIDF**. Idempotency left `"admitted"`; `partial: true` (`consumesQuota` = `"Partially, recorded"`); Worker sent `idempotencyState: "failed"` with `terminalErrorCode: "provider_unavailable"`. Failed/cancelled did **not** add a third DO kind on this path — still admit + one credit.

**Do:** clear the kills before the next probe:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM kill_switch WHERE changed_by = 'verify-settle'"
```

Restart the Worker (or wait 30 s).

#### 11.3.8 Cancelled credit

**Do:** open a stream and abort after `accepted`, before a terminal event:

```bash
export IDEMC="verify-settle-cancel-$(date +%s)"
timeout 3s curl -sN -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $IDEMC" \
  -H "x-capability-version: 1.0.0" \
  -d '{
    "capability_id": "clinic.visit_summary",
    "user_intent": "Summarize today'"'"'s visit for the chart.",
    "context": {
      "org": "<must match AAT org>",
      "branch": "<must match AAT branch>",
      "visit.chief_complaint@v1": "Patient reports headache for 3 days."
    }
  }' || true
```

If 3 s is enough for the provider to `completed`, shorten the timeout or Ctrl+C after the `accepted` frame. Save **REFC** / **RIDC** from D1 (`idempotency_key =` **KC**).

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT state, completed_at, terminal_error_code, payload_pointer
   FROM ai_request WHERE request_id = '<RIDC>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT COUNT(*) AS attempt_n FROM ai_attempt WHERE request_id = '<RIDC>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT tokens, cost, period, quota_weight, request_id
   FROM usage_event WHERE request_id = '<RIDC>'"
```

**Expect:** `state = 'Cancelled'`, `completed_at` set, `terminal_error_code` **NULL** (unchanged — Cancelled does not stamp a taxonomy code). `usage_event` **always** exists (one row). `ai_attempt` count is 0 if abort happened before the first provider call; ≥1 only if invocation had already recorded attempts ([§9](#9-failed-and-cancelled-credit)).

Usage: `{ tokens: 0, cost: 0 }` when nothing accrued. If any `text_delta` arrived before abort, tokens/cost follow `estimateUsageFromStreamedChars` (streamed chars as **output** tokens through the same `priceUsage` helper — not a third 0.001 formula) and `ai_attempt.cost` agrees when an attempt row exists.

**Do:** `npx wrangler r2 object get … "request/<RIDC>/envelope"` and retry `post_request "$IDEMC"`.

**Expect:** one envelope (placeholder `result.finishReason` related to cancel). Replay is SSE `cancelled`, **not** `"Prior request completed."`. `partial: true`; `idempotencyState: "cancelled"`. If the broker already credited, the worker still writes D1/R2 with `skipCredit: true` — still **one** `usage_event`, not two.

#### 11.3.9 What this stage does not do

**Do:** on the healthy Completed **RID0**:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT status, usage_tokens, usage_cost, partial
   FROM grace_admission_queue
   WHERE request_reference = '<REF0>' OR grace_request_id = '<RID0>'"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id FROM usage_event WHERE request_id IS NULL LIMIT 5"
```

**Expect:** no pending grace row for this job (`grace_admission_queue` is unused while the Quota DO is up). `usage_event.request_id` for **RID0** is still **RID0** — this stage does not run journal retention and does not `SET NULL` for Stage 12 / cron purge.

**Do:** list R2 keys for this request (or get the known key only — a second get of `request/<RID0>/envelope-2` / `…/envelope-failed` must fail):

```bash
npx wrangler r2 object get ai-platform-development \
  "request/<RID0>/envelope-failed" --file /tmp/nope.json --local
```

**Expect:** object missing. Failure writes the **same** key, not a sibling.

**Do:** inspect the reconciliation **profile** as wrangler SQL (this stage does not invoke the cron):

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT r.request_id, r.state
   FROM ai_request r
   LEFT JOIN ai_attempt a ON a.request_id = r.request_id
   WHERE r.state IN ('Completed','Failed')
     AND r.request_id IN ('<RID0>','<RIDF>')
     AND a.attempt_id IS NULL"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT r.request_id, r.state
   FROM ai_request r
   LEFT JOIN usage_event u ON u.request_id = r.request_id
   WHERE r.state IN ('Completed','Failed','Cancelled')
     AND r.request_id IN ('<RID0>','<RIDF>','<RIDC>')
     AND u.usage_event_id IS NULL"
```

**Expect:** both result sets empty for these ids. Completed/Failed have attempts **and** usage; Cancelled has usage. A Cancelled row with `attempt_n = 0` ([§11.3.8](#1138-cancelled-credit)) is **not** in the missing-attempts query (that query only considers Completed/Failed). AwaitingContext is not flagged. Settlement does not call `runReconciliation`; it only writes the rows that job later reads.

**Do:** confirm this stage is not Stage 10 and not Stage 12: there is no new routing policy write, no second provider call on replay, and no new `/control/support/lookup` route introduced here. `GET /v1/requests/{reference}` already exists; the next probe only checks the **handoff** this file asserts (`payload_pointer` → envelope `result`).

**Expect:** preflight did not INSERT `usage_event` (the row appears only after the terminal). Cost is absent from admit. `kind: credit` is not a public `/v1` or `/control` route. Quota DO storage is not in D1 — wrangler `d1 execute` cannot `SELECT` `inFlight`.

#### 11.3.10 Clients cannot read control tables

**Do:** as the staff AAT (not wrangler):

```bash
curl -sS -D - -o /tmp/get-rid0.json \
  "$GATEWAY/v1/requests/<REF0>" \
  -H "Authorization: Bearer $AAT"
```

**Expect:** HTTP 200, JSON `{ "state": "Completed", "result": { … } }`. `result` is envelope `result` (the Stage 12 **handoff** this document asserts). The body does **not** include `ai_attempt` rows, `usage_event`, `context`, `prompt`, or `attempts[]`. Failed **REFF** returns `{ "state": "Failed", "terminal_error_code": "provider_unavailable" }` without the diagnostic payload. Cancelled **REFC** returns `{ "state": "Cancelled" }`.

**Do:** `curl -sS "$GATEWAY/v1/requests/<REF0>"` with **no** Bearer, and `curl -sS "$GATEWAY/v1/attempts"`.

**Expect:** unauthenticated GET → 401. There is no `/v1/attempts` (or `/v1/usage`) catalog of control tables. AAT cannot `SELECT` D1.

**Do:** the same `SELECT` as [§11.3.3](#1133-d1-ai_attempt-insert-every-column) / [§11.3.4](#1134-d1-usage_event-insert-every-column) via wrangler.

**Expect:** rows return. Journal control tables are wrangler-privileged (Worker binding). Clients never get a SQL session.

**Do:** `POST /control/support/lookup` is Stage 12 (operator bearer). Do not treat it as a settlement API. This stage’s job ended when `payload_pointer` and the envelope existed.

