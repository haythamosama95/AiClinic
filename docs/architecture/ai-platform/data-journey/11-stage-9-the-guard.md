# AI Platform Data Journey — Stage 9 — The guard (stages 1–10)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [Guard flow diagram](#3-guard-flow-diagram)
4. [Stage 1 — Ingress size + JSON](#4-stage-1-ingress-size-json)
5. [Stage 2 — Identity](#5-stage-2-identity)
6. [Stage 3 — Entitlement](#6-stage-3-entitlement)
7. [Stage 4 — Rate limit](#7-stage-4-rate-limit)
8. [Stage 5 — Capability resolve](#8-stage-5-capability-resolve)
9. [Stage 6 — Context validate](#9-stage-6-context-validate)
10. [Stage 7 — Cost pre-flight](#10-stage-7-cost-pre-flight)
11. [Stage 8 — Admission (Quota DO)](#11-stage-8-admission-quota-do)
12. [Stage 9 — Journal INSERT](#12-stage-9-journal-insert)
13. [Stage 10 — Prompt compose](#13-stage-10-prompt-compose)

---

## 1. Plain language

Ten sequential checks run **before** the SSE stream opens. If any fails, the client gets HTTP JSON error — never `accepted`.

## 2. Metaphor

**Ten security checkpoints** from parking lot to boarding gate. Fail at checkpoint 3 and you never reach the plane.

## 3. Guard flow diagram

```
Stage 1  Ingress size + JSON
Stage 2  Identity (AAT)
Stage 3  Entitlement + kill switches
Stage 4  Rate limits (3 dimensions)
Stage 5  Capability resolve (manifest registry)
Stage 6  Context validate
Stage 7  Cost pre-flight (token estimate)
Stage 8  Admission (Quota DO)
Stage 9  Journal INSERT (D1 ai_request)     ← skipped on idempotent replay
Stage 10 Prompt compose (CanonicalRequest)  ← skipped on idempotent replay
```



## 4. Stage 1 — Ingress size + JSON


| Input      | Check             | Success       | Failure             |
| ---------- | ----------------- | ------------- | ------------------- |
| `bodyText` | ≤ 1 MiB UTF-8     | parsed `body` | `request_too_large` |
| `bodyText` | plain object JSON | continues     | `internal_error`    |


Extracts: `userIntent`, `suppliedContext`, `conversationId`, `turnOrdinal`, `transcript`.

## 5. Stage 2 — Identity


| Check                                       | AAT / D1 field                | Failure                               |
| ------------------------------------------- | ----------------------------- | ------------------------------------- |
| 3 JWS segments                              | wire token                    | `unauthenticated`                     |
| `alg === EdDSA`                             | header                        | `unauthenticated`                     |
| `kid` non-empty                             | header                        | `unauthenticated`                     |
| All payload claims present                  | see [§4 JWS structure](08-stage-6-minting-an-aat.md#4-jws-structure) | `unauthenticated`                     |
| `aud === ai-platform`                       | payload `aud`                 | `unauthenticated`                     |
| Clock skew ±60s                             | `iat`, `exp`                  | `unauthenticated`                     |
| Installation exists                         | `iss` → D1 `installation`     | `unauthenticated`                     |
| Key exists, not revoked, in validity window | `kid` → D1 `installation_key` | `unauthenticated`                     |
| Key bound to installation                   | `key.installation_id === iss` | `unauthenticated`                     |
| Ed25519 signature valid                     | signature bytes               | `unauthenticated`                     |
| Installation active                         | `installation.status`         | `installation_suspended` if suspended |
| Token contract accepted                     | `ver` → D1 `token_contract`   | `unauthenticated` if missing/retired  |


**Principal produced:**

```
installationId, organizationId, branchId, actorId, role, scopes, jti, iat, exp, ver
```



## 6. Stage 3 — Entitlement

See [§4 Runtime entitlement checks](06-stage-4-entitlement-and-capability-grants.md#4-runtime-entitlement-checks-guard-stage-3) table. Uses `capability_id` from request body and hardcoded `providerId: "fake"` for one kill-switch dimension only.

## 7. Stage 4 — Rate limit


| Dimension               | Key                           | Failure                        |
| ----------------------- | ----------------------------- | ------------------------------ |
| installation            | `installationId`              | `rate_limited`, retry_after 60 |
| installation+actor      | `installationId:actorId`      | same                           |
| installation+capability | `installationId:capabilityId` | same                           |




## 8. Stage 5 — Capability resolve


| Check                  | Field                                  | Failure                                        |
| ---------------------- | -------------------------------------- | ---------------------------------------------- |
| Registry lookup        | `capability_id@x-capability-version`   | `capability_unknown`                           |
| Lifecycle              | manifest overlay                       | `capability_retired`                           |
| Plan allowance         | `entitlement.plan` vs manifest         | `forbidden_capability` / `capability_disabled` |
| Provider kill switches | routing policy providers (if loadable) | `capability_disabled`                          |


**Manifest fields consumed (visit summary):**


| Section                | Key fields                                     |
| ---------------------- | ---------------------------------------------- |
| `Identity`             | `capabilityId`, `version`, `lifecycleState`    |
| `Access`               | `minimumPlanTier`, `requiredCapabilityScope`   |
| `Interaction`          | `interactionMode` (`single_shot`)              |
| `Context requirements` | required keys, shapes, maxSize                 |
| `Prompt binding`       | artifact refs for compose                      |
| `Routing`              | `routingPolicyRef`, `requiredProviderFeatures` |
| `Economics`            | quotas for preflight and usage weight          |




## 9. Stage 6 — Context validate

**Single-shot checks:**


| Check                                      | Fields                          | Failure                             |
| ------------------------------------------ | ------------------------------- | ----------------------------------- |
| Required keys present                      | `context` vs manifest           | `context_required` + `missing_keys` |
| `context.org === principal.organizationId` | body + AAT                      | `context_invalid`                   |
| `context.branch === principal.branchId`    | body + AAT                      | `context_invalid`                   |
| Shape + maxSize per key                    | manifest `Context requirements` | `context_invalid`                   |


**Output:** `filteredContext` — only permitted keys copied.

**Conversational mode:** requires `turn_ordinal` + `transcript`; failures → `conversation_budget_exhausted` or `context_invalid`.

## 10. Stage 7 — Cost pre-flight


| Input                      | Source                                                       | Check                        |
| -------------------------- | ------------------------------------------------------------ | ---------------------------- |
| `filteredContext`          | stage 6                                                      | serialized with `userIntent` |
| `promptArtifactByteLength` | manifest artifact size                                       |                              |
| `manifest.Economics`       | `maxInputTokens`, `maxOutputTokens`, `perRequestCostCeiling` |                              |


Estimator: `ceil(utf8Bytes / 4) * 1.15` + prompt artifact bytes.

Failure: `request_too_large` if estimate exceeds ceilings.

## 11. Stage 8 — Admission (Quota DO)

**Pre-DO:**


| Check              | Field            | Failure           |
| ------------------ | ---------------- | ----------------- |
| Token not expired  | `principal.exp`  | `unauthenticated` |
| Entitlement config | D1 `entitlement` | `quota_exhausted` |


**DO RPC payload (**`kind: admission`**):**


| Field              | Source                      |
| ------------------ | --------------------------- |
| `jti`              | AAT                         |
| `installationId`   | Principal                   |
| `idempotencyKey`   | header `x-idempotency-key`  |
| `requestReference` | adapter-generated           |
| `entitlement`      | EntitlementSnapshot from D1 |


**EntitlementSnapshot fields:**

```
plan, period_bounds.{period_start, period_end}, request_quota,
token_cost_budget.{token_budget, cost_budget}, allowed_capabilities[],
soft_threshold, status
```

**DO outcomes:**


| outcome                 | Guard result           | Next stages    |
| ----------------------- | ---------------------- | -------------- |
| `admitted`              | ok + `requestId`       | 9, 10          |
| `idempotent`            | ok, prior state        | **skip 9, 10** |
| `replay` (jti)          | `unauthenticated`      | —              |
| `quota_exhausted`       | fail + `period_reset`  | —              |
| `concurrency_exhausted` | fail `quota_exhausted` | —              |


**Grace admission** (DO unavailable): local UUID `requestId`, `routing_tier=degraded`, queued for cron reconciliation. Cap: 5 grace per installation.

**Routing tier after admission:**


| Admission outcome                   | `routing_tier` |
| ----------------------------------- | -------------- |
| `grace_admitted`                    | `degraded`     |
| `admitted` + soft threshold crossed | `degraded`     |
| otherwise                           | `standard`     |




## 12. Stage 9 — Journal INSERT

**D1** `ai_request` **INSERT — every column on fresh path:**


| Column                     | Value source                                           |
| -------------------------- | ------------------------------------------------------ |
| `request_id`               | Quota DO `requestId` (or grace UUID)                   |
| `request_reference`        | adapter-generated                                      |
| `installation_id`          | `principal.installationId`                             |
| `actor_id`                 | `principal.actorId`                                    |
| `branch_id`                | `principal.branchId`                                   |
| `capability_id`            | manifest `Identity.capabilityId`                       |
| `capability_version`       | manifest `Identity.version`                            |
| `prompt_artifact_hash`     | manifest `Prompt binding.systemInstructionArtifactRef` |
| `idempotency_key`          | header                                                 |
| `trace_id`                 | header or generated                                    |
| `state`                    | `Accepted`                                             |
| `created_at`, `updated_at` | ISO now                                                |
| `completed_at`             | `NULL`                                                 |
| `terminal_error_code`      | `NULL`                                                 |
| `payload_pointer`          | `NULL` (set later)                                     |
| `routing_tier`             | from admission                                         |
| `conversation_id`          | `NULL` (single_shot) or wire                           |
| `turn_ordinal`             | `NULL` (single_shot) or wire                           |
| `routing_decision`         | **not written by current code**                        |


**On D1 insert failure:** Quota DO `release` RPC + `internal_error`.

## 13. Stage 10 — Prompt compose

Builds `CanonicalRequest` (see [§3 CanonicalRequest](12-stage-10-accept-route-invoke-stream.md#3-canonicalrequest-every-field)). On failure: D1 UPDATE `state=Failed` + guard `internal_error`.

**Guard success output (**`GuardFreshSuccess`**):**

```
requestId, principal, manifest, filteredContext, composed (CanonicalRequest),
promptVersion, guardLatencyMs, requestReference, idempotencyKey, transcript?
```

---

