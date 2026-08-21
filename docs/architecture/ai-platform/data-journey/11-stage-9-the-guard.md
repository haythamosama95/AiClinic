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


Extracts: `userIntent`, `suppliedContext`, `conversationId`, `turnOrdinal`, `transcript`. Body keys `routing_tier` / `degraded` / `degraded_notice` are **not** extracted — ingress ignores them via empty `ADAPTER_ROUTING_BODY_FIELDS` (see [Ignored body keys](10-stage-8-request-ingress.md#47-ignored-body-keys)).

## 5. Stage 2 — Identity


| Check                                       | AAT / D1 field                | Failure                               |
| ------------------------------------------- | ----------------------------- | ------------------------------------- |
| 3 JWS segments                              | wire token                    | `unauthenticated`                     |
| `alg === EdDSA`                             | header                        | `unauthenticated`                     |
| `kid` non-empty                             | header                        | `unauthenticated`                     |
| All payload claims present                  | see [§4 JWS structure](08-stage-6-minting-an-aat.md#4-jws-structure) | `unauthenticated`                     |
| `aud === ai-platform`                       | payload `aud`                 | `unauthenticated`                     |
| Clock skew ±60s                             | `iat`, `exp`                  | `unauthenticated`                     |
| `exp − iat ≤ 600s` (`MAX_AAT_LIFETIME_SECONDS`) | payload `iat`, `exp`      | `unauthenticated`                     |
| Installation exists                         | `iss` → D1 `installation`     | `unauthenticated`                     |
| Key exists, not revoked, in validity window | `kid` → D1 `installation_key` | `unauthenticated`                     |
| Key bound to installation                   | `key.installation_id === iss` | `unauthenticated`                     |
| Ed25519 signature valid                     | signature bytes               | `unauthenticated`                     |
| Installation active                         | `installation.status`         | `installation_suspended` if suspended |
| Token contract accepted                     | `ver` → D1 `token_contract`   | `unauthenticated` if missing/retired  |


`installation_key.valid_until` is written at enroll and rotate (`valid_from` + 365 days). Rotate
stamps `revoked_at = now` on every currently unrevoked key for that installation in the same D1
batch as the new-key insert — there is no platform dual-key overlap. Identity already rejects
`now >= valid_until` and non-null `revoked_at`.

Installation, key, and token-contract rows are loaded through the isolate-scoped `ConfigCache`
(30 s TTL). A warm isolate does not re-read D1 for the same keys on the next POST or GET within
that window.

**Principal produced:**

```
installationId, organizationId, branchId, actorId, role, scopes, jti, iat, exp, ver
```



## 6. Stage 3 — Entitlement

See [§4 Runtime entitlement checks](06-stage-4-entitlement-and-capability-grants.md#4-runtime-entitlement-checks-guard-stage-3) table. Uses `capability_id` from request body and hardcoded `providerId: "fake"` for one kill-switch dimension only.

## 7. Stage 4 — Rate limit


| Dimension               | Key                           | Failure                                                                 |
| ----------------------- | ----------------------------- | ----------------------------------------------------------------------- |
| installation            | `installationId`              | `rate_limited`; `retry_after` from the binding hint, else 60            |
| installation+actor      | `installationId:actorId`      | same                                                                    |
| installation+capability | `installationId:capabilityId` | same                                                                    |


The Cloudflare Rate Limit `limit()` outcome is typed `{ success }`. When a
positive `retryAfter` (seconds) is present on that admission result, the guard
copies it onto `GuardFailure.retryAfter` and the pre-SSE HTTP JSON body
(`retry_after`). When the binding supplies no hint, the simple-limiter window
of 60s (`DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS`) is used.
`preAcceptFailureResponse` attaches the field via `supplementaryFieldsForCode`.
This is the only client-visible `rate_limited` — post-accept provider 429s are
retried inside invocation and, if the chain exhausts, surface as
`provider_unavailable`.


Rejections from stages 2–4 (and admission) call `recordGuardRejection`, which increments an
**in-isolate** tally. Cron `flushRejectionCounters` writes only the isolate that happens to run
the tick; other isolates' maps are lost on eviction. `platform_counter` (and therefore
`dashboardQuotaRejectionRate`) is a **lower bound**, not an exact count. An accurate count would
flush tallies to D1 batched with the journal write at request end — not implemented.




## 8. Stage 5 — Capability resolve


| Check                       | Field                                                        | Failure                                        |
| --------------------------- | ------------------------------------------------------------ | ---------------------------------------------- |
| Registry lookup             | `capability_id@x-capability-version`                         | `capability_unknown`                           |
| Lifecycle                   | manifest overlay                                             | `capability_retired`                           |
| Plan allowance              | `entitlement.plan` vs `Access.minimumPlanTier`, grants       | `forbidden_capability`                         |
| Required capability scope   | `Access.requiredCapabilityScope` ∈ `principal.scopes`        | `forbidden_capability` (unset/empty: skip)     |
| Allowed staff roles         | `principal.role` ∈ `Access.allowedStaffRoles`                | `forbidden_capability` (unset/empty: skip)     |
| Manifest kill switch        | `Access.killSwitchFlag === true`                             | `capability_disabled` (false/unset: skip)      |
| D1 kill switches            | `kill_switch` global / capability / installation             | `capability_disabled`                          |
| Provider kill switches      | routing policy providers (if loadable)                       | collected as `killedProviderIds` for the router; not `capability_disabled` |


**Manifest fields consumed (visit summary):**


| Section                | Key fields                                     |
| ---------------------- | ---------------------------------------------- |
| `Identity`             | `capabilityId`, `version`, `lifecycleState`    |
| `Access`               | `minimumPlanTier`, `requiredCapabilityScope`, `allowedStaffRoles`, `killSwitchFlag` |
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

No freshness check: stale context is accepted by design (architecture §6.7.3). `freshnessHint` is not a Context-requirements field.


**Output:** `filteredContext` — only permitted keys copied.

**Conversational mode:**

- Legs must carry `turn_ordinal` on the wire. The pipeline passes conversational options only when `manifest.interactionMode === "conversational"` **and** `turn_ordinal` is present; omitting `turn_ordinal` leaves options undefined and stage 6 fails `context_invalid`.
- Requires `transcript` (omission → `context_invalid`; an explicit empty array is a valid first leg). Other transcript/budget failures → `conversation_budget_exhausted` or `context_invalid`.
- Tenant binding (same comparison as single-shot): `context.org === principal.organizationId` and `context.branch === principal.branchId` on the supplied context **and** every `context_resolved` turn payload. Mismatch or absent `org`/`branch` → `context_invalid`.
- Permitted-key allowlist (`applyPermittedKeyAllowlist`): keys outside `permittedKeySet` are **dropped** (not a rejection) from ordinary supplied context, from `context_resolved` payloads, and from historical `context_requested` `requests` entries. Remaining permitted resolved values still pass shape/size checks. An all-unpermitted `context_requested` turn is kept with an empty `requests` array so the transcript shape is unchanged.

## 10. Stage 7 — Cost pre-flight


| Input                      | Source                                                       | Check                        |
| -------------------------- | ------------------------------------------------------------ | ---------------------------- |
| `filteredContext`          | stage 6                                                      | serialized with `userIntent` |
| `promptArtifactByteLength` | composer `promptScaffoldByteLength(manifest)` — UTF-8 bytes of the bound prompt scaffold (system instruction + rule fragments + template), injected from the worker | counted into the byte estimate |
| `manifest.Economics`       | `maxInputTokens`, `maxOutputTokens`, `perRequestTokenCeiling` |                              |


Estimator (§13.6.2): `ceil((utf8(serializedContext+intent[+transcript]) + promptArtifactByteLength) / 4) * 1.15`. Prompt artifacts bound to the capability count at their known byte length. Units are **tokens throughout** — the preflight never reads the platform price table and never converts to currency. `perRequestTokenCeiling` is the canonical field name for that token comparison; the loader still accepts legacy `perRequestCostCeiling` as a compatibility alias and normalizes it.

Failure: `request_too_large` if `estimatedInputTokens > maxInputTokens` or `estimatedInputTokens + maxOutputTokens > perRequestTokenCeiling`.

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
| `admitted`              | ok + `requestId`; optional `degraded: true` when usage ≥ `soft_threshold` | 9, 10          |
| `idempotent`            | ok, prior state        | **skip 9, 10** |
| `replay` (jti)          | `unauthenticated`      | —              |
| `quota_exhausted`       | fail + `period_reset`  | —              |
| `concurrency_exhausted` | fail `quota_exhausted` | —              |


**Grace admission** (DO unavailable): local UUID `requestId`, `routing_tier=degraded`, queued in D1 `grace_admission_queue` for cron reconciliation. Cap: 5 pending rows per installation (durable across isolates). Exceeding the cap returns `rate_limited` (retryable), not `quota_exhausted`.

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
| `prompt_artifact_hash`     | composer's `promptVersion` (`resolvePromptVersion`: FNV-1a content hash of resolved system instruction + rule fragments + template bytes). Detects silent artifact changes under a pinned ref. The ref itself is implied by capability + version and is not stored in this column. |
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
| `routing_decision`         | `NULL` at INSERT — written at Stage 10 after routing   |


**On D1 insert failure:** Quota DO `release` RPC + `internal_error`.

## 13. Stage 10 — Prompt compose

Builds `CanonicalRequest` (see [Stage 10 CanonicalRequest](12-stage-10-accept-route-invoke-stream.md#12-canonicalrequest-every-field)). Passes `streamFlag: true` and forwards `deadline` when the guard input supplies one. On failure: D1 UPDATE `state=Failed` + guard `internal_error`. `stopConditions` is always `[]` under A4 (no stop-sequences field).

The composer runs the final `userIntent` part through the same `neutralizeText` escaping used for context blocks and transcript turns (`</` → `\u003c/`) before pushing it as the last `user` part. Conversational prior turns are the already-allowlisted `validatedTranscript` from stage 6.

`promptVersion` on the guard success (and the value journaled at stage 9) is `resolvePromptVersion(manifest)` — the content hash of the resolved artifact bytes, not the artifact ref string. The ref stays implied by `capability_id` + `capability_version`; composed artifact text is in the CanonicalRequest (and therefore the R2 envelope `prompt` field).

**Guard success output (**`GuardFreshSuccess`**):**

```
requestId, principal, manifest, filteredContext, composed (CanonicalRequest),
promptVersion, guardLatencyMs, requestReference, idempotencyKey, transcript?,
killedProviderIds?, routingTier (`standard` | `degraded`), degraded?
```

`routingTier` is derived solely from admission (`routingTierFromAdmission`): `grace_admitted` and `admitted` with `degraded: true` both yield `degraded`. The worker passes that same flag into SSE `accepted.degraded_notice` and into `selectCandidateChain`.

---

