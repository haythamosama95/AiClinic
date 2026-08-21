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

---

## 1. Plain language

Every terminal outcome credits the Quota DO so `inFlight` is released and the idempotency entry leaves `"admitted"`. Completed, failed, and cancelled terminals then reuse the same post-response journal writers: `ai_attempt` row(s), one `usage_event`, one R2 diagnostic envelope (`request/{request_id}/envelope`), and `ai_request.payload_pointer`. Failed/cancelled credit accrued usage (including `{ tokens: 0, cost: 0 }`). Cost on those rows is computed by one shared helper (`src/pricing`) from the versioned platform price table (`control/pricing/platform-default/1.json`): provider-reported input/output tokens × per-1K model rates. `ai_attempt.cost` and `usage_event.cost` therefore agree. Cancel without provider usage uses the named char-as-output-token estimate (`estimateUsageFromStreamedChars`) through that same helper. Money appears only here — the preflight stays token-only (§13.6.2).

## 2. Metaphor

**Closing the flight log** — stamp the ledger (DO + usage_event), file the full incident report in the warehouse (R2 envelope), update the index card (payload_pointer).

## 3. Quota DO credit (`kind: credit`)


| Field in RPC        | Source |
| ------------------- | ------ |
| `installationId`    | Principal |
| `requestId`         | journal row |
| `jti`               | AAT |
| `idempotencyKey`    | header |
| `usage.tokens`      | Success: `usage.input + usage.output`. Failed/cancelled: accrued partial usage, or `{ tokens: 0, cost: 0 }` when none. |
| `usage.cost`        | Success: `priceUsage` on the provider result (same helper as `ai_attempt.cost`). Zero-usage terminals: `0`. Cancel/fail with accrued usage: that partial-usage cost (provider tokens × rates, or `estimateUsageFromStreamedChars` when usage was not reported). |
| `partial`           | From §5.4 taxonomy `consumesQuota`: `"Yes"` → `false` (full consume); `"Partially, recorded"` → `true`. Success always `false`. |
| `idempotencyState`  | Optional. `"completed"` / `"failed"` / `"cancelled"`. Omitted → `partial ? "cancelled" : "completed"`. |
| `entitlement`       | Optional. Admission-time entitlement snapshot (`period_start` / `period_end` and budgets). Worker always sends it so credit and D1 share the same period. |


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

Non-completed terminals still call `credit` (possibly zero usage) so the DO releases `inFlight` and the idempotency key leaves `"admitted"`. Without that credit, a retry of the same key **while the request is still in-flight** would replay as `"Prior request completed."`. If the Worker crashes and never credits, the 2h abandoned-admission sweep marks that key `failed` (and slides `expiresAt`) so a later retry replays SSE `failed`, not the completed placeholder and not a second charge.


| Terminal | Taxonomy | `partial` | `idempotencyState` |
| -------- | -------- | --------- | ------------------ |
| Success | — | `false` | `completed` (omitted; mapped from `partial`) |
| `provider_rejected`, `validation_failed` | consumes `"Yes"` | `false` | `failed` |
| `provider_unavailable`, `timeout`, `cancelled` | consumes `"Partially, recorded"` | `true` | `failed` or `cancelled` |

Invocation failure credits in the worker with `ignoreBrokerSettlement` so the broker's disconnect-as-cancel does not double-credit. Broker `handleFailed` / `handleCancel` credit via the credit sink (including zero usage); the worker does not credit again when the broker already settled, but still writes the D1/R2 journal (`skipCredit: true`).

Failed requests always persist at least one `ai_attempt` row (collected `attemptRecords`, or a diagnostic row from the routing exclusion list when the chain was empty). Cancelled requests write `usage_event` always; `ai_attempt` only when invocation recorded attempts (abort before the first provider call is expected to have none).

Cron `runReconciliation` uses that expected profile and does **not** flag Cancelled-without-attempts or AwaitingContext. It flags Completed/Failed missing attempts or usage, and Cancelled missing `usage_event`.

---

