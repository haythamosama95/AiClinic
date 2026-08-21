# AI Platform Data Journey — Quota Durable Object State Reference

## Table of Contents

1. [`QuotaDoState` — every field](#1-quotadostate-every-field)
2. [Constants](#2-constants)
3. [RPC kinds](#3-rpc-kinds)
4. [Ephemeral sweep and idempotency TTL](#4-ephemeral-sweep-and-idempotency-ttl)

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
| `idempotency[key]`            | object | `{ expiresAt, requestReference, state, requestId }` — `state` is `admitted` \| `completed` \| `failed` \| `cancelled` only (not `in_progress` / `awaiting_context`; those are not DO states). `admitted` at admit; credit may set `completed`, `failed`, or `cancelled`; abandoned sweep may set `failed`. |
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


## 4. Ephemeral sweep and idempotency TTL

Admission sets `idempotency.expiresAt` and `admittedAt` to the same timestamp plus the 2h horizon. On every later RPC, `sweepEphemeral` runs **abandoned-admission handling first**, then deletes idempotency entries whose `expiresAt <= now`. JTI replay uses the same 2h horizon, which already covers the 10-minute maximum AAT lifetime (`MAX_AAT_LIFETIME_SECONDS`); a still-valid token cannot be replayed after its JTI entry expires.

When an `admittedRequests` row is older than the horizon (crashed / never credited):

1. Drop the admitted row and decrement `inFlight`.
2. If the matching idempotency entry is still `"admitted"`, set `state: "failed"` and **slide** `expiresAt` to `now + EPHEMERAL_HORIZON_MS` so a retry can replay as `failed` for another 2h (not as a completed placeholder, and not as a fresh admit).

Credit (and that sweep mark) slide `expiresAt`; it is not frozen at admission. A retry of the same key after the original admission horizon but still inside the slid credit window remains idempotent. After the slid window elapses, the entry is deleted and the key may admit fresh.
