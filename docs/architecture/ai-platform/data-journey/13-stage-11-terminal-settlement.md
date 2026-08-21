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

---

## 1. Plain language

When the stream ends successfully, the platform credits the Quota DO, writes billing ledger rows, stores a diagnostic envelope in R2, and points D1 at it.

## 2. Metaphor

**Closing the flight log** — stamp the ledger (DO + usage_event), file the full incident report in the warehouse (R2 envelope), update the index card (payload_pointer).

## 3. Quota DO credit (`kind: credit`)


| Field in RPC     | Source                                                  |
| ---------------- | ------------------------------------------------------- |
| `installationId` | Principal                                               |
| `requestId`      | journal row                                             |
| `jti`            | AAT                                                     |
| `idempotencyKey` | header                                                  |
| `usage.tokens`   | `usage.input + usage.output`                            |
| `usage.cost`     | hardcoded `0.001` in worker today                       |
| `partial`        | `false` on success; `true` on cancel with partial usage |


**DO state changes on credit:**

- `tokensUsed += usage.tokens`
- `costUsed += usage.cost`
- `requestsUsed += 1`
- `inFlight -= 1`
- Delete `admittedRequests[requestId]`
- Set `creditedRequests[requestId]`
- Update idempotency state → `completed` or `cancelled`



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
| `outcome`                 | `success`, `truncation`, etc. |
| `latency_ms`              | measured                      |
| `tokens_in`, `tokens_out` | from provider                 |
| `cost`                    | `0.001` hardcoded             |
| `provider_request_id`     | provider id                   |
| `error_code`              | if failed attempt             |




## 6. D1 `usage_event` INSERT


| Column            | Source                               |
| ----------------- | ------------------------------------ |
| `usage_event_id`  | new ULID                             |
| `installation_id` | principal                            |
| `period`          | `YYYY-MM` from `recorded_at`         |
| `request_id`      | journal                              |
| `quota_weight`    | manifest `Economics.quotaWeight` (1) |
| `tokens`          | total tokens                         |
| `cost`            | `0.001`                              |
| `recorded_at`     | ISO now                              |




## 7. R2 envelope — every field

**Key:** `request/{request_id}/envelope`

```json
{
  "context": { /* filteredContext from guard stage 6 */ },
  "prompt": { /* CanonicalRequest */ },
  "attempts": [ /* raw provider bodies per attempt */ ],
  "result": { /* CanonicalResult */ }
}
```

**Write order:**

1. D1 batch: `ai_attempt` + `usage_event`
2. `R2.put(envelope)`
3. D1 UPDATE `ai_request.payload_pointer = key`



## 8. Happy path settlement diagram

```
Provider success
  → broker emits completed SSE
  → recordTerminalState(Completed)
  → creditUsage(DO, partial=false)
  → writePostResponseDetail(D1 attempts + usage_event + R2 envelope + payload_pointer)
```

---

