# AI Platform Data Journey — Alternative and Failure Journeys

## Table of Contents

1. [1. Lifecycle alternatives (control plane)](#1-lifecycle-alternatives-control-plane)
2. [2. Zero quotas after entitle](#2-zero-quotas-after-entitle)
3. [3. Missing routing policy](#3-missing-routing-policy)
4. [4. JTI replay](#4-jti-replay)
5. [5. Grace admission + cron reconciliation](#5-grace-admission-cron-reconciliation)
6. [6. Client disconnect](#6-client-disconnect)
7. [7. Prose guard failures (post-accept)](#7-prose-guard-failures-post-accept)
8. [8. Complete pre-SSE failure matrix](#8-complete-pre-sse-failure-matrix)

---

## 1. Lifecycle alternatives (control plane)


| Endpoint            | D1 effect                                | Runtime effect                     |
| ------------------- | ---------------------------------------- | ---------------------------------- |
| `POST …/suspend`    | `installation.status=suspended`          | AAT → `installation_suspended`     |
| `POST …/resume`     | `status=active`                          | Restores                           |
| `POST …/delete`     | `status=deleted`                         | `unauthenticated`                  |
| `POST …/rotate`     | New `installation_key` row               | Old + new keys verify until revoke |
| `POST …/revoke-key` | `revoked_at` on key                      | AAT with that `kid` fails          |
| `POST …/purge`      | Deletes installation data + R2 envelopes | Irreversible cleanup               |




## 2. Zero quotas after entitle

`entitlement.status=active` but `request_quota=0` → admission `quota_exhausted`.

## 3. Missing routing policy

Guard passes → `accepted` → invoke preload miss → `failed` `internal_error`.

## 4. JTI replay

Same `jti` within 2h window → admission `replay` → `unauthenticated`.

## 5. Grace admission + cron reconciliation

DO down at stage 8 → grace UUID journaled → cron re-admits and credits or drops after TTL.

## 6. Client disconnect

Stream `cancelled` → partial credit if usage available → idempotency state `cancelled`.

## 7. Prose guard failures (post-accept)


| Trigger               | Terminal code       |
| --------------------- | ------------------- |
| Output > 128000 chars | `validation_failed` |
| Stop sequence leak    | `validation_failed` |
| Empty output          | `validation_failed` |
| Provider truncation   | `validation_failed` |




## 8. Complete pre-SSE failure matrix


| Stage           | HTTP        | Code                                                                     | Triggering field(s)                         |
| --------------- | ----------- | ------------------------------------------------------------------------ | ------------------------------------------- |
| Ingress size    | 413         | `request_too_large`                                                      | body bytes                                  |
| Ingress JSON    | 422         | —                                                                        | malformed JSON                              |
| Missing headers | 422         | —                                                                        | `x-idempotency-key`, `x-capability-version` |
| 1               | 413/500     | `request_too_large` / `internal_error`                                   | body                                        |
| 2               | 401/403     | `unauthenticated` / `installation_suspended`                             | AAT fields, `installation.status`           |
| 3               | 403/503     | `forbidden_capability` / `capability_disabled`                           | entitlement, grants, kill_switch            |
| 4               | 429         | `rate_limited`                                                           | rate limit bindings                         |
| 5               | 404/503     | `capability_unknown` / `capability_retired` / `capability_disabled`      | capability id/version                       |
| 6               | 422/409/500 | `context_required` / `context_invalid` / `conversation_budget_exhausted` | `context`, `org`, `branch`                  |
| 7               | 413         | `request_too_large`                                                      | Economics limits                            |
| 8               | 401/429/500 | `unauthenticated` / `quota_exhausted` / `internal_error`                 | `jti`, `exp`, quotas, DO                    |
| 9               | 422/500     | `context_invalid` / `internal_error`                                     | conversation fields, D1                     |
| 10              | 500         | `internal_error`                                                         | compose failure                             |


---
