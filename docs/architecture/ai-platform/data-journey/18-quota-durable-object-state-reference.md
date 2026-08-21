# AI Platform Data Journey — Quota Durable Object State Reference

## Table of Contents

1. [`QuotaDoState` — every field](#1-quotadostate-every-field)
2. [Constants](#2-constants)
3. [RPC kinds](#3-rpc-kinds)

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
| `jtiReplay[jti].expiresAt`    | number | Replay window (2h)                                  |
| `idempotency[key]`            | object | `{ expiresAt, requestReference, state, requestId }` |
| `creditedRequests[requestId]` | object | `{ expiresAt }`                                     |
| `admittedRequests[requestId]` | object | `{ requestReference, admittedAt }`                  |
| `boundInstallationId`         | string | Installation binding                                |




## 2. Constants


| Constant               | Value          | Meaning                                  |
| ---------------------- | -------------- | ---------------------------------------- |
| `EPHEMERAL_HORIZON_MS` | 7_200_000 (2h) | Ephemeral entry TTL                      |
| `CONCURRENCY_LIMIT`    | 16             | Max in-flight per installation           |
| `GRACE_ADMISSION_CAP`  | 5              | Max grace admissions when DO unavailable |




## 3. RPC kinds


| kind        | Purpose                                     |
| ----------- | ------------------------------------------- |
| `admission` | Admit or idempotent replay at guard stage 8 |
| `credit`    | Settle usage on completion/cancel           |
| `release`   | Compensate on journal insert failure        |
