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
9. [9. Journal retention and aged usage joinability](#9-journal-retention-and-aged-usage-joinability)
10. [10. Guard-rejection counters are a lower bound](#10-guard-rejection-counters-are-a-lower-bound)

---

## 1. Lifecycle alternatives (control plane)

All of these routes share one `OPERATOR_BEARER_TOKEN` mapped to one `OPERATOR_ID`.
`control_audit` cannot distinguish operators; rotation and revocation are all-or-nothing
(see [Stage 3 enroll auth](05-stage-3-platform-installation-enrollment.md#3-api-post-controlinstallationsinstallation_idenroll)).


| Endpoint            | D1 effect                                                                                                                       | Runtime effect                                               |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `POST …/suspend`    | `installation.status=suspended`                                                                                                 | AAT → `installation_suspended`                               |
| `POST …/resume`     | `status=active`                                                                                                                 | Restores                                                     |
| `POST …/delete`     | `status=deleted`                                                                                                                | `unauthenticated`                                            |
| `POST …/rotate`     | New `installation_key` (`valid_until` = now + 365 days); `revoked_at = now` on prior unrevoked keys in the same batch           | Old `kid` fails identity immediately; new `kid` verifies     |
| `POST …/revoke-key` | `revoked_at` on key                                                                                                             | AAT with that `kid` fails                                    |
| `POST …/purge`      | Deletes installation data + R2 envelopes                                                                                        | Irreversible cleanup                                         |




## 2. Zero quotas after entitle

`entitlement.status=active` but `request_quota=0` → admission `quota_exhausted`.

## 3. Missing routing policy

Guard passes → `accepted` → invoke preload miss → `failed` `internal_error`.

A loaded document whose target `features` omit or mistype `min_context_window`, `cost_class`, or `languages` is different: `filterTargets` excludes those targets with `reason_code: feature_unsupported` (fail closed) and does not throw. If the remaining chain is empty, Stage 10 ends `failed` / `provider_unavailable` — the same terminal as any other all-targets-excluded case, not `internal_error`.

## 4. JTI replay

Same `jti` within 2h window → admission `replay` → `unauthenticated`.

## 5. Grace admission + cron reconciliation

Quota DO down at stage 8 → Worker admits under a **D1-backed** grace queue (`grace_admission_queue`), not isolate memory.

1. **Cap:** `COUNT(*)` of `status=pending` rows for the installation. At `GRACE_ADMISSION_CAP` (5), further grace admits return `rate_limited` with `retry_after` (budget is not exhausted — that remains `quota_exhausted`). The count is durable across isolates.
2. **Idempotency:** before insert, SELECT `ai_request` and the grace queue on `(installation_id, idempotency_key)`. A journaled row returns `idempotent` (pipeline skips the provider). A pending grace row returns the same `graceRequestId` / `requestReference`. The grace table has `UNIQUE (installation_id, idempotency_key)`; `ai_request` does not.
3. **Quota:** last-known usage vs the entitlement snapshot already loaded from D1 — in-period `ai_request` count vs `request_quota`, plus `usage_event` token/cost sums vs budgets. Exhausted installations are not served during the outage.
4. **Usage:** production settlement (`creditUsage` with `DB`) attaches tokens/cost onto the pending D1 row. Cron `reconcileGraceUsage` SELECTs pending rows from D1 (every isolate's work), re-admits on the recovered DO, and credits **attached** usage (not phantom zeros). TTL and max-attempt drops remain; dropped/reconciled rows leave `pending` so they no longer count toward the cap.

## 6. Client disconnect

Stream `cancelled` → Quota DO `credit` with `partial: true` even when no tokens accrued (`{ tokens: 0, cost: 0 }`) so `inFlight` is released → idempotency state `cancelled`. The same settlement writers as completed then insert `usage_event` (always) and `ai_attempt` (when invocation recorded attempts), plus one R2 envelope.

## 7. Prose guard failures (post-accept)


| Trigger               | Terminal code       | Quota |
| --------------------- | ------------------- | ----- |
| Output > 128000 chars | `validation_failed` | Credits accrued (or zero) usage; `partial: false` (consumes `"Yes"`); idempotency `failed` |
| Stop sequence         | `validation_failed` | same |
| System-prompt leak    | `validation_failed` | same — assembled text contains any of the composed-instruction needles (opening, interior, or ending slice) |
| Refusal prefix        | `validation_failed` | same — assembled text starts with a production refusal prefix |
| Injection-echo needle | `validation_failed` | same — assembled text contains `Ignore previous instructions` |
| Empty output          | `validation_failed` | same |
| Provider truncation   | `validation_failed` | same — truncated prose is never authoritative `completed` |




## 8. Complete pre-SSE failure matrix


| Stage           | HTTP        | Code                                                                     | Triggering field(s)                         |
| --------------- | ----------- | ------------------------------------------------------------------------ | ------------------------------------------- |
| Ingress size    | 413         | `request_too_large`                                                      | body bytes                                  |
| Ingress JSON    | 422         | —                                                                        | malformed JSON                              |
| Missing headers | 422         | —                                                                        | `x-idempotency-key`, `x-capability-version` |
| 1               | 413/500     | `request_too_large` / `internal_error`                                   | body                                        |
| 2               | 401/403     | `unauthenticated` / `installation_suspended`                             | AAT fields, `installation.status`           |
| 3               | 403/503     | `forbidden_capability` / `capability_disabled`                           | entitlement, grants, kill_switch            |
| 4               | 429         | `rate_limited` (+ `retry_after`: binding hint, else 60)                  | rate limit bindings                         |
| 5               | 404/503     | `capability_unknown` / `capability_retired` / `capability_disabled`      | capability id/version; capability-level kill switches (manifest flag, D1 `global` / `capability:` / `installation:`). A `provider:<id>` kill switch does **not** 503 here — it is collected for the router so remaining providers can fail over |
| 6               | 422/409/500 | `context_required` / `context_invalid` / `conversation_budget_exhausted` | `context`, `org`, `branch` (single-shot and conversational supplied context plus conversational `context_resolved` turns); conversational `turn_ordinal`, `transcript` |
| 7               | 413         | `request_too_large`                                                      | Economics limits plus prompt-scaffold bytes (`promptArtifactByteLength`) |
| 8               | 401/429/500 | `unauthenticated` / `quota_exhausted` / `rate_limited` / `internal_error` | `jti`, `exp`, quotas, DO; grace cap is `rate_limited` |
| 9               | 422/500     | `context_invalid` / `internal_error`                                     | conversation fields, D1                     |
| 10              | 500         | `internal_error`                                                         | compose failure                             |


Provider kill switches are **not** a pre-SSE outage. Guard stage 5 returns the resolved manifest plus `killedProviderIds`; after `accepted`, routing excludes those providers (`reason_code: kill_switch`) and walks the remaining chain. If every target is excluded, the stream ends `failed` / `provider_unavailable`.

## 9. Journal retention and aged usage joinability

Scheduled `runRetentionPurge` (`0 3 * * *`) keeps ledger money rows while the journal is purged:

1. `UPDATE usage_event SET request_id = NULL` for aged `ai_request` rows — this is why `usage_event.request_id` is nullable.
2. Then `DELETE` those `ai_request` / `ai_attempt` rows (and their R2 envelopes).

Aged usage therefore **loses request-level joinability by design**. `runReconciliation`
(`src/rollup/index.ts`) is request-centric: `LEFT JOIN usage_event u ON u.request_id = r.request_id`.
Nulled `request_id` can never match, so reconciliation coverage shrinks with age. The money
row remains as commercial evidence; it is no longer joinable to a journal ticket.

## 10. Guard-rejection counters are a lower bound

`recordGuardRejection` increments an isolate-local map. Cron `flushRejectionCounters` writes
only the isolate that happens to run the tick. Tallies in other isolates are lost on eviction.
`platform_counter.count` (and `dashboardQuotaRejectionRate`, which SUMs it) is therefore a
**lower bound**, not an exact rejection count. If an accurate count is ever needed, flush
tallies to D1 batched with the existing journal write at request end rather than only from the
cron isolate — not implemented.


---
