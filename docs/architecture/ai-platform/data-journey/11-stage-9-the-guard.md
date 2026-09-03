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
14. [Behavioral verification](#14-behavioral-verification)
   - [14.1 Setup](#141-setup)
   - [14.2 Coverage](#142-coverage)
   - [14.3 Ordered probes](#143-ordered-probes)
     - [14.3.1 Reset to a known clinic and platform state](#1431-reset-to-a-known-clinic-and-platform-state)
     - [14.3.2 Stage 1 ingress size and JSON](#1432-stage-1-ingress-size-and-json)
     - [14.3.3 Stage 2 wire-token identity failures](#1433-stage-2-wire-token-identity-failures)
     - [14.3.4 Stage 2 D1 identity suspend and token contract](#1434-stage-2-d1-identity-suspend-and-token-contract)
     - [14.3.5 Stage 3 entitlement plan grants and kill switches](#1435-stage-3-entitlement-plan-grants-and-kill-switches)
     - [14.3.6 Stage 5 capability resolve](#1436-stage-5-capability-resolve)
     - [14.3.7 Stage 6 context validate](#1437-stage-6-context-validate)
     - [14.3.8 Stage 7 cost pre-flight](#1438-stage-7-cost-pre-flight)
     - [14.3.9 Stage 8 admission refusals](#1439-stage-8-admission-refusals)
     - [14.3.10 Happy path through prompt compose](#14310-happy-path-through-prompt-compose)
     - [14.3.11 Idempotent replay skips journal and compose](#14311-idempotent-replay-skips-journal-and-compose)
     - [14.3.12 Soft-threshold degraded routing_tier](#14312-soft-threshold-degraded-routing-tier)
     - [14.3.13 Journal INSERT columns and independent switches](#14313-journal-insert-columns-and-independent-switches)
     - [14.3.14 ConfigCache rotate and rejection counters](#14314-configcache-rotate-and-rejection-counters)
     - [14.3.15 Stage 4 rate limit](#14315-stage-4-rate-limit)

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
is **additive**: it INSERTs the replacement key and leaves prior unrevoked keys' `revoked_at`
NULL until an explicit `POST …/revoke-key` — dual-key overlap is intended (stage 3 §8.3). Identity
already rejects `now >= valid_until` and non-null `revoked_at`.

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

## 14. Behavioral verification

Live probes against a local Worker (`POST /v1/requests`) and local D1. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§14.3](#143-ordered-probes) top to bottom** on a throwaway local clinic plus the local gateway. If every probe matches, guard stages 1–10 are working.

The HTTP caller for this stage is a **clinic AAT** (`Authorization: Bearer <AAT>`). The adapter does not reject a missing Authorization header; identity (stage 2) does. Control-plane Bearer `OPERATOR_BEARER_TOKEN` is only for forcing actions (enroll, entitle, suspend, rotate, token-contract). SQL as `postgres` / `wrangler d1` is for inspect, reset, and failures that have no HTTP force.

State is cumulative. [§14.3.1](#1431-reset-to-a-known-clinic-and-platform-state) is the reset. Do not skip it. After any D1 write that identity/entitlement/capability will re-read, wait **31 seconds** (`ConfigCache` 30 s TTL) or restart `npm run dev` before the next POST.

### 14.1 Setup

- Local Worker: `cd ai-platform && npm run dev` → `http://127.0.0.1:8787`. D1 migrations applied (`npx wrangler d1 migrations apply ai-platform-development --local --env development`).
- Clinic Supabase with an enrolled keypair ([Stage 2](04-stage-2-clinic-keypair-enrollment.md)). You need:
  - **Doctor** — `role = 'doctor'` with at least one `ai.*` permission (seed is `ai.access`)
  - `organizations.id`, primary branch id, and the Stage 2 `installation_id` / `kid` / `public_jwk.x`
- `OPERATOR_BEARER_TOKEN` matching the Worker secret.
- `python3` for unsigned JWS construction. `psql` as `postgres` to mint signed verification AATs (clinic `staff_role` has no `clinician` / `nurse`, and seed scopes are `ai.access` not `ai.visit_summary` — a stock `issue_ai_token()` cannot pass visit-summary Access checks).
- Prefer restarting `npm run dev` at [§14.3.1](#1431-reset-to-a-known-clinic-and-platform-state) so Quota DO ephemeral maps and the isolate `ConfigCache` start empty.

Shell (reuse in every probe):

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export INSTALLATION_ID='<I0 from Stage 2>'
export KID='<K0 from Stage 2>'
export ORG_ID='<clinic organizations.id>'
export BRANCH_ID='<doctor primary branch uuid>'
export ACTOR_ID='<doctor staff_members.id>'
export CAP='clinic.visit_summary'
export CAP_VER='1.0.0'

d1() {
  npx wrangler d1 execute ai-platform-development --local --env development --command "$1"
}

# Unsigned compact JWS (no valid signature). Usage:
#   UNSIGNED=$(python3 - <<'PY'
#   ... see unsigned_jws in §14.3.3 ...
#   PY
#   )
```

Signed verification AAT as `postgres` (clinic keystore). Override `role`, `scopes`, `aud`, `ver`, `iss`, `iat`/`exp` as each probe says. Default below is the **happy-path principal**: `role=clinician`, `scopes=["ai.visit_summary"]`, `aud=ai-platform`, `ver=1`, lifetime 300 s (`< MAX_AAT_LIFETIME_SECONDS`).

```sql
SELECT set_config('role', 'postgres', true);

WITH k AS (
  SELECT kid, installation_id, secret_key
  FROM ai_internal.installation_keys
  WHERE is_deleted = false
  ORDER BY valid_from DESC
  LIMIT 1
), claims AS (
  SELECT
    k.kid,
    k.installation_id::text AS iss,
    extract(epoch FROM now())::bigint AS iat,
    k.secret_key
  FROM k
)
SELECT
  h.b64 || '.' || p.b64 || '.' ||
  auth_internal.base64url_encode(
    pgsodium.crypto_sign_detached(
      convert_to(h.b64 || '.' || p.b64, 'utf8'),
      claims.secret_key
    )
  ) AS aat
FROM claims,
LATERAL (
  SELECT auth_internal.base64url_encode(
    convert_to(jsonb_build_object('alg','EdDSA','kid', claims.kid)::text, 'utf8')
  ) AS b64
) h,
LATERAL (
  SELECT auth_internal.base64url_encode(
    convert_to(jsonb_build_object(
      'iss', claims.iss,
      'aud', 'ai-platform',
      'sub', :'ACTOR_ID',          -- paste staff uuid
      'org', :'ORG_ID',
      'branch', :'BRANCH_ID',
      'role', 'clinician',
      'scopes', jsonb_build_array('ai.visit_summary'),
      'jti', gen_random_uuid()::text,
      'iat', claims.iat,
      'exp', claims.iat + 300,
      'ver', '1'
    )::text, 'utf8')
  ) AS b64
) p;
```

Call the result `CLINICIAN_AAT`. Mint a fresh token (new `jti`) whenever a probe has already admitted that jti.

Stock doctor token (Access failures): as **doctor**, `SELECT public.issue_ai_token();` → `DOCTOR_AAT`. Decode payload: `role=doctor`, `scopes` includes `ai.access` and does not include `ai.visit_summary`.

Happy-path body (visit summary). Copy `org` / `branch` from the AAT payload:

```json
{
  "capability_id": "clinic.visit_summary",
  "user_intent": "Summarize today's visit for the chart.",
  "context": {
    "org": "<AAT org>",
    "branch": "<AAT branch>",
    "visit.chief_complaint@v1": {
      "visit_id": "11111111-1111-4111-8111-111111111111",
      "complaint": "Patient reports headache for 3 days."
    }
  }
}
```

`invoke` helper (required ingress headers; body on stdin or `-d`):

```bash
invoke() {
  local token="$1" idem="${2:-$(python3 -c 'import uuid; print(uuid.uuid4())')}"
  shift 2 || true
  curl -sS -D /tmp/guard.hdr -o /tmp/guard.body \
    -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $idem" \
    -H "x-capability-version: $CAP_VER" \
    -H "x-trace-id: verify-$(date +%s)" \
    "$@"
  echo "--- headers ---"; cat /tmp/guard.hdr
  echo "--- body ---"; cat /tmp/guard.body; echo
}
```

Taxonomy HTTP mapping used below: `unauthenticated` 401, `installation_suspended` 403, `forbidden_capability` 403, `rate_limited` 429, `quota_exhausted` 429, `request_too_large` 413, `context_required` / `context_invalid` 422, `conversation_budget_exhausted` 409, `capability_unknown` / `capability_retired` 404, `capability_disabled` 503, `internal_error` 500. Pre-SSE JSON: `code`, `request_reference`, `trace_id`, `retry_safe`, plus `retry_after` on `rate_limited`.

### 14.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Ten sequential checks run before SSE; any failure is HTTP JSON, never `accepted` | [§14.3.2](#1432-stage-1-ingress-size-and-json)–[§14.3.10](#14310-happy-path-through-prompt-compose) |
| Caller is clinic AAT on `POST /v1/requests`; adapter does not reject missing `Authorization` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Control-plane Bearer is not this stage’s caller | [§14.3.1](#1431-reset-to-a-known-clinic-and-platform-state) |
| Stage 1: body `≤ 1 MiB` UTF-8 else `request_too_large` | [§14.3.2](#1432-stage-1-ingress-size-and-json) |
| Stage 1: non-object JSON else `internal_error` — live adapter returns 422 first | [§14.3.2](#1432-stage-1-ingress-size-and-json) |
| Ingress extracts `user_intent` / `context` / `conversation_id` / `turn_ordinal` / `transcript` | [§14.3.10](#14310-happy-path-through-prompt-compose), [§14.3.13](#14313-journal-insert-columns-and-independent-switches) |
| Body keys `routing_tier` / `degraded` / `degraded_notice` are ignored (`ADAPTER_ROUTING_BODY_FIELDS = []`) | [§14.3.13](#14313-journal-insert-columns-and-independent-switches) |
| Identity: not 3 JWS segments → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Identity: `alg !== EdDSA` → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Identity: empty `kid` → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Identity: missing payload claim → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Identity: `aud !== ai-platform` → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Identity: clock skew `±60s` → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Identity: `exp − iat > 600` → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Identity: installation missing → `unauthenticated` | [§14.3.4](#1434-stage-2-d1-identity-suspend-and-token-contract) |
| Identity: key missing / revoked / outside validity window → `unauthenticated` | [§14.3.4](#1434-stage-2-d1-identity-suspend-and-token-contract) |
| Identity: key not bound to `iss` → `unauthenticated` | [§14.3.4](#1434-stage-2-d1-identity-suspend-and-token-contract) |
| Identity: bad Ed25519 signature → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) |
| Identity: `installation.status = suspended` → `installation_suspended` | [§14.3.4](#1434-stage-2-d1-identity-suspend-and-token-contract) |
| Identity: non-active non-suspended status → `unauthenticated` | [§14.3.4](#1434-stage-2-d1-identity-suspend-and-token-contract) |
| Identity: token contract missing or `retired_at` set → `unauthenticated` | [§14.3.4](#1434-stage-2-d1-identity-suspend-and-token-contract) |
| `valid_until` = `valid_from` + 365 days at enroll/rotate | [§14.3.1](#1431-reset-to-a-known-clinic-and-platform-state), [§14.3.14](#14314-configcache-rotate-and-rejection-counters) |
| Rotate INSERTs replacement key; prior keys stay live until `revoke-key` (dual-key overlap) | [§14.3.14](#14314-configcache-rotate-and-rejection-counters) |
| `ConfigCache` 30 s TTL; warm isolate does not re-read D1 | [§14.3.14](#14314-configcache-rotate-and-rejection-counters) |
| Principal fields: `installationId`, `organizationId`, `branchId`, `actorId`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver` | [§14.3.10](#14310-happy-path-through-prompt-compose) |
| Stage 3: `entitlement.status !== active` → `forbidden_capability` (`ai_disabled`) | [§14.3.5](#1435-stage-3-entitlement-plan-grants-and-kill-switches) |
| Stage 3: plan vs hardcoded `minimumPlanTier: "standard"` → `forbidden_capability` (`plan_tier`) | [§14.3.5](#1435-stage-3-entitlement-plan-grants-and-kill-switches) |
| Stage 3: `allowed_capabilities` missing id → `forbidden_capability` | [§14.3.5](#1435-stage-3-entitlement-plan-grants-and-kill-switches) |
| Stage 3: grant missing / revoked / version mismatch → `forbidden_capability` | [§14.3.5](#1435-stage-3-entitlement-plan-grants-and-kill-switches) |
| Stage 3: D1 kill switch global / capability / installation → `capability_disabled` | [§14.3.5](#1435-stage-3-entitlement-plan-grants-and-kill-switches) |
| Stage 3: hardcoded `providerId: "fake"` kill switch → `capability_disabled` | [§14.3.5](#1435-stage-3-entitlement-plan-grants-and-kill-switches) |
| Stage 4: three dimensions; `rate_limited` + `retry_after` (hint or 60) | [§14.3.15](#14315-stage-4-rate-limit) |
| Only pre-SSE `rate_limited`; post-accept provider 429s are not this code | [§14.3.15](#14315-stage-4-rate-limit), [§14.3.13](#14313-journal-insert-columns-and-independent-switches) |
| `recordGuardRejection` is in-isolate; `platform_counter` is a lower bound | [§14.3.14](#14314-configcache-rotate-and-rejection-counters) |
| Stage 5: unknown `capability_id@version` → `capability_unknown` | [§14.3.6](#1436-stage-5-capability-resolve) |
| Stage 5: lifecycle retired → `capability_retired` | [§14.3.6](#1436-stage-5-capability-resolve) |
| Stage 5: plan / grants / `requiredCapabilityScope` / `allowedStaffRoles` → `forbidden_capability` | [§14.3.6](#1436-stage-5-capability-resolve) |
| Stage 5: unset/empty scope or roles skip those checks | [§14.3.6](#1436-stage-5-capability-resolve) |
| Stage 5: `Access.killSwitchFlag === true` → `capability_disabled` | unprobeable (see [§14.3.6](#1436-stage-5-capability-resolve)) |
| Stage 5: D1 kill switches → `capability_disabled` | [§14.3.5](#1435-stage-3-entitlement-plan-grants-and-kill-switches) (stage 3 fires first on the same rows) |
| Stage 5: provider kill switches → `killedProviderIds`, not `capability_disabled` | [§14.3.13](#14313-journal-insert-columns-and-independent-switches) |
| Manifest groups consumed on the visit-summary happy path | [§14.3.10](#14310-happy-path-through-prompt-compose) |
| Stage 6: missing required keys → `context_required` (`missing_keys` not on live HTTP) | [§14.3.7](#1437-stage-6-context-validate) |
| Stage 6: `context.org` / `context.branch` mismatch → `context_invalid` | [§14.3.7](#1437-stage-6-context-validate) |
| Stage 6: shape / `maxSize` → `context_invalid` | [§14.3.7](#1437-stage-6-context-validate) |
| No freshness check; extra keys dropped from `filteredContext` | [§14.3.7](#1437-stage-6-context-validate), [§14.3.10](#14310-happy-path-through-prompt-compose) |
| Conversational stage-6 failures (`turn_ordinal`, transcript, budgets, allowlist) | unprobeable (see [§14.3.7](#1437-stage-6-context-validate)) |
| Stage 7: estimator counts context + intent + prompt scaffold bytes; units are tokens | [§14.3.8](#1438-stage-7-cost-pre-flight) |
| Stage 7: never reads the price table / never converts to currency | [§14.3.8](#1438-stage-7-cost-pre-flight) |
| Stage 7: over `maxInputTokens` or `perRequestTokenCeiling` → `request_too_large` | [§14.3.8](#1438-stage-7-cost-pre-flight) |
| Stage 8 pre-DO: expired `exp` → `unauthenticated` | [§14.3.3](#1433-stage-2-wire-token-identity-failures) (identity fires first on live POST) |
| Stage 8: entitlement row miss → `quota_exhausted` | unprobeable on live ordered pipeline (see [§14.3.9](#1439-stage-8-admission-refusals)) |
| Stage 8 DO payload: `jti`, `installationId`, `idempotencyKey`, `requestReference`, `entitlement` | [§14.3.10](#14310-happy-path-through-prompt-compose) |
| `admitted` → journal + compose; optional `degraded` when usage ≥ `soft_threshold` | [§14.3.10](#14310-happy-path-through-prompt-compose), [§14.3.12](#14312-soft-threshold-degraded-routing-tier) |
| `idempotent` → skip stages 9 and 10 | [§14.3.11](#14311-idempotent-replay-skips-journal-and-compose) |
| JTI `replay` → `unauthenticated` | [§14.3.9](#1439-stage-8-admission-refusals) |
| `quota_exhausted` (and concurrency mapped to that code), not grace-cap `rate_limited` | [§14.3.9](#1439-stage-8-admission-refusals) |
| Grace admit: local UUID, `routing_tier=degraded`, D1 queue, cap 5 → `rate_limited` | unprobeable while Quota DO is up (see [§14.3.9](#1439-stage-8-admission-refusals)) |
| `routing_tier` from admission only: grace/soft → `degraded`, else `standard` | [§14.3.10](#14310-happy-path-through-prompt-compose), [§14.3.12](#14312-soft-threshold-degraded-routing-tier) |
| Stage 9: every `ai_request` column on the fresh path | [§14.3.10](#14310-happy-path-through-prompt-compose), [§14.3.13](#14313-journal-insert-columns-and-independent-switches) |
| Stage 9 insert failure → Quota DO `release` + `internal_error` | unprobeable on live D1 (see [§14.3.13](#14313-journal-insert-columns-and-independent-switches)) |
| Stage 10 compose: `streamFlag: true`; `stopConditions` always `[]`; `neutralizeText` on `userIntent` | [§14.3.10](#14310-happy-path-through-prompt-compose) |
| Compose failure → D1 `state=Failed` + `internal_error` | unprobeable on published artifacts (see [§14.3.10](#14310-happy-path-through-prompt-compose)) |
| `promptVersion` / `prompt_artifact_hash` is content hash, not the artifact ref | [§14.3.10](#14310-happy-path-through-prompt-compose) |
| Guard success fields; SSE `accepted` is the Stage 10 boundary; no provider call / no settle in the guard | [§14.3.10](#14310-happy-path-through-prompt-compose), [§14.3.13](#14313-journal-insert-columns-and-independent-switches) |


### 14.3 Ordered probes

#### 14.3.1 Reset to a known clinic and platform state

Restart the local Worker so Quota DO maps and `ConfigCache` are empty.

**Do:** `curl -s "$GATEWAY/health"`

**Expect:** JSON with `environment`. Control-plane auth is **not** used on `/health`.

**Do:** as `postgres`, confirm the Stage 2 key exists (`installation_keys` non-empty). Save `I0`, `K0`, `ORG_ID`, `BRANCH_ID`, `ACTOR_ID`.

**Do:** enroll the platform if D1 has no row (plan **must** be `standard` or higher so stage 3 plan-tier can pass):

```bash
cd ai-platform
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"org_id\": \"$ORG_ID\",
    \"display_name\": \"Guard Verify Clinic\",
    \"region\": \"local\",
    \"plan\": \"standard\",
    \"public_key\": \"<public_jwk.x>\",
    \"algorithm\": \"EdDSA\",
    \"kid\": \"$KID\"
  }"
```

**Expect:** HTTP 200, or 409 `already_enrolled`. A clinic AAT is the later `/v1/requests` caller; this Bearer is operator-only.

**Do:**

```bash
d1 "SELECT installation_id, status FROM installation WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT key_id, algorithm, revoked_at IS NULL AS live,
         valid_from, valid_until
    FROM installation_key WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT status, plan, request_quota, allowed_capabilities
    FROM entitlement WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT ver, retired_at FROM token_contract"
```

**Expect:** `installation.status = active`. One live key `K0`, `algorithm = EdDSA`, `valid_until` ≈ `valid_from` + 365 days. `token_contract.ver = 1` with `retired_at` NULL.

**Do:** if entitlement is `pending`, entitle (one-shot). Period window must include now:

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "period_start": "2026-01-01T00:00:00.000Z",
    "period_end": "2027-01-01T00:00:00.000Z",
    "request_quota": 1000,
    "token_budget": 500000,
    "cost_budget": 50.0,
    "soft_threshold": 0.8,
    "allowed_capabilities": ["clinic.visit_summary"],
    "grants": [{
      "capability_id": "clinic.visit_summary",
      "capability_version": "1.0.0",
      "scope": "installation"
    }]
  }'
```

If already `active`, skip entitle and instead:

```bash
d1 "UPDATE entitlement SET status='active', plan='standard',
      request_quota=1000, token_budget=500000, cost_budget=50.0,
      soft_threshold=0.8,
      allowed_capabilities='[\"clinic.visit_summary\"]',
      period_start='2026-01-01T00:00:00.000Z',
      period_end='2027-01-01T00:00:00.000Z'
    WHERE installation_id = '$INSTALLATION_ID'"
```

**Do:** clear leftover guard state:

```bash
d1 "DELETE FROM kill_switch"
d1 "DELETE FROM grace_admission_queue WHERE installation_id = '$INSTALLATION_ID'"
d1 "DELETE FROM ai_request WHERE installation_id = '$INSTALLATION_ID'"
d1 "UPDATE installation SET status='active' WHERE installation_id = '$INSTALLATION_ID'"
d1 "UPDATE installation_key SET revoked_at=NULL
    WHERE key_id = '$KID'"
d1 "UPDATE token_contract SET retired_at=NULL WHERE ver='1'"
```

**Expect:** empty `kill_switch` and `grace_admission_queue` for `I0`. No `ai_request` rows for `I0`.

Mint `CLINICIAN_AAT` ([§14.1](#141-setup) SQL) and `DOCTOR_AAT` (`issue_ai_token` as doctor). Decode both; save `org` / `branch` / `sub` / `jti`.

#### 14.3.2 Stage 1 ingress size and JSON

**Do:** POST with a declared oversize (adapter Content-Length gate, same 1 MiB cap as guard stage 1):

```bash
curl -sS -D - -o /tmp/guard.body -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $CLINICIAN_AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: size-1" \
  -H "x-capability-version: $CAP_VER" \
  -H "Content-Length: 1048577" \
  -d '{"capability_id":"clinic.visit_summary"}'
```

**Expect:** HTTP 413, JSON `code = request_too_large`. No SSE `accepted`. `request_reference` / `trace_id` may be empty (adapter size gate runs before header parse).

**Do:**

```bash
d1 "SELECT COUNT(*) AS n FROM ai_request WHERE installation_id = '$INSTALLATION_ID'"
```

**Expect:** `n = 0`. Size failure never reaches admission or journal.

**Do:** `invoke "$CLINICIAN_AAT" json-1 -d 'not-json'`

**Do:** `invoke "$CLINICIAN_AAT" json-2 -d '[]'`

**Do:** `invoke "$CLINICIAN_AAT" json-3 -d 'null'`

**Expect:** HTTP 422, **empty** body (`content-type: text/plain`). The live adapter rejects non-object JSON **before** the guard, so stage 1’s `internal_error` is not reachable on `POST /v1/requests`. Still never `accepted`. D1 `ai_request` still empty.

#### 14.3.3 Stage 2 wire-token identity failures

Unsigned JWS helper (payload claims complete unless a probe omits one):

```bash
unsigned_jws() {
  python3 - "$@" <<'PY'
import json, base64, sys
def b64(o):
    raw = json.dumps(o, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()
header = json.loads(sys.argv[1])
payload = json.loads(sys.argv[2])
sig = sys.argv[3] if len(sys.argv) > 3 else "c2ln"
print(f"{b64(header)}.{b64(payload)}.{sig}")
PY
}

export NOW=$(date +%s)
BASE_PAY=$(python3 -c "import json,os; print(json.dumps({
  'iss': os.environ['INSTALLATION_ID'],
  'aud': 'ai-platform',
  'sub': os.environ['ACTOR_ID'],
  'org': os.environ['ORG_ID'],
  'branch': os.environ['BRANCH_ID'],
  'role': 'clinician',
  'scopes': ['ai.visit_summary'],
  'jti': '00000000-0000-4000-8000-000000000001',
  'iat': int(os.environ['NOW']),
  'exp': int(os.environ['NOW'])+300,
  'ver': '1'}))")
```

**Do:** `invoke` with no `Authorization` header (omit `-H Authorization`).

**Expect:** HTTP 401, `code = unauthenticated`. Adapter did not 422 the missing header. No SSE.

**Do:** `invoke "not-a-jwt" wire-seg -d '{"capability_id":"'"$CAP"'"}'`

**Expect:** 401 `unauthenticated` (not 3 JWS segments).

**Do:** `ALG=$(unsigned_jws '{"alg":"HS256","kid":"'"$KID"'"}' "$BASE_PAY")` then `invoke "$ALG" …`

**Expect:** 401 `unauthenticated` (`alg !== EdDSA`).

**Do:** header `{"alg":"EdDSA","kid":""}` unsigned.

**Expect:** 401 `unauthenticated`.

**Do:** unsigned payload **without** `org` (other claims present).

**Expect:** 401 `unauthenticated`.

**Do:** mint signed AAT ([§14.1](#141-setup)) with `'aud', 'other-audience'`.

**Expect:** 401 `unauthenticated`. Cheap claim check; D1 is not required for this reject.

**Do:** signed AAT with `'exp', iat + 601`.

**Expect:** 401 `unauthenticated` (`MAX_AAT_LIFETIME_SECONDS = 600`).

**Do:** signed AAT with `iat` / `exp` both more than 60 s in the past (`exp = now - 120`).

**Expect:** 401 `unauthenticated` (clock skew). Same code as a token that is expired at stage 8’s defensive `exp` recheck — on live POST, identity runs first and never reaches stage 8.

**Do:** `invoke "${CLINICIAN_AAT%?}x" sig-1` (flip last signature character) with a valid JSON body.

**Expect:** 401 `unauthenticated` (Ed25519 verify failed). Claims and `kid` are otherwise fine.

**Do:** after each of the above:

```bash
d1 "SELECT COUNT(*) AS n FROM ai_request WHERE installation_id = '$INSTALLATION_ID'"
```

**Expect:** still `0`. Stages 2–4 rejections do not journal.

#### 14.3.4 Stage 2 D1 identity suspend and token contract

Use a **fresh** `CLINICIAN_AAT` (valid signature). Body may be `{}` plus `capability_id` — identity runs before entitlement.

**Do:** unsigned JWS with real `iss` / claims but `"kid":"no-such-key"` and `alg=EdDSA`.

**Expect:** 401 `unauthenticated` (key missing). Claim checks pass; `keys` cache miss.

**Do:** signed AAT with `'iss', gen_random_uuid()` (unknown installation). `kid` still `K0`.

**Expect:** 401 `unauthenticated` (installation missing).

**Do:**

```bash
d1 "UPDATE installation_key SET revoked_at = '2026-01-01T00:00:00.000Z' WHERE key_id = '$KID'"
sleep 31
invoke "$CLINICIAN_AAT" rev-1 -d "{\"capability_id\":\"$CAP\"}"
d1 "UPDATE installation_key SET revoked_at = NULL WHERE key_id = '$KID'"
sleep 31
```

**Expect:** 401 `unauthenticated` while `revoked_at` is set. Restore before continuing.

**Do:** `valid_until` in the past, wait 31 s, POST, restore `valid_until` to the enroll value (or `datetime(valid_from, '+365 days')`).

**Expect:** 401 `unauthenticated` (`now >= valid_until`). Repeat with `valid_from` in the future if you want the other window edge.

**Do:** bind failure — dummy installation, then point `K0` at it:

```bash
d1 "INSERT INTO installation (installation_id, org_id, display_name, status, region, enrolled_at)
    VALUES ('00000000-0000-4000-8000-000000000099','dummy','dummy','active','local','2026-01-01T00:00:00.000Z')"
d1 "UPDATE installation_key SET installation_id = '00000000-0000-4000-8000-000000000099'
    WHERE key_id = '$KID'"
sleep 31
invoke "$CLINICIAN_AAT" bind-1 -d "{\"capability_id\":\"$CAP\"}"
d1 "UPDATE installation_key SET installation_id = '$INSTALLATION_ID' WHERE key_id = '$KID'"
d1 "DELETE FROM installation WHERE installation_id = '00000000-0000-4000-8000-000000000099'"
sleep 31
```

**Expect:** 401 `unauthenticated` (`key.installation_id !== iss`).

**Do:**

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/suspend" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
sleep 31
invoke "$CLINICIAN_AAT" sus-1 -d "{\"capability_id\":\"$CAP\"}"
```

**Expect:** HTTP 403, `code = installation_suspended` (not `unauthenticated`). No journal row.

**Do:** resume, then mark deleted:

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/resume" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
d1 "UPDATE installation SET status='deleted' WHERE installation_id = '$INSTALLATION_ID'"
sleep 31
invoke "$CLINICIAN_AAT" del-1 -d "{\"capability_id\":\"$CAP\"}"
d1 "UPDATE installation SET status='active' WHERE installation_id = '$INSTALLATION_ID'"
sleep 31
```

**Expect:** 401 `unauthenticated` while `status` is `deleted` (fail closed: only `active` authenticates).

**Do:** signed AAT with `'ver', '999'` (no `token_contract` row).

**Expect:** 401 `unauthenticated`.

**Do:** retire `ver=1` (must open a rotation first), then POST a `ver=1` AAT, then restore:

```bash
curl -s -X POST "$GATEWAY/control/token-contract/begin-rotation" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ver":"2"}'
curl -s -X POST "$GATEWAY/control/token-contract/retire" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ver":"1"}'
sleep 31
invoke "$CLINICIAN_AAT" tc-1 -d "{\"capability_id\":\"$CAP\"}"
d1 "UPDATE token_contract SET retired_at = NULL WHERE ver = '1'"
d1 "DELETE FROM token_contract WHERE ver = '2'"
sleep 31
```

**Expect:** 401 `unauthenticated` while `retired_at` is set.

#### 14.3.5 Stage 3 entitlement plan grants and kill switches

Identity must pass. Use `CLINICIAN_AAT`. After each D1 mutation, `sleep 31`.

**Do:**

```bash
d1 "UPDATE entitlement SET status='pending' WHERE installation_id = '$INSTALLATION_ID'"
sleep 31
invoke "$CLINICIAN_AAT" ent-pending -d "{\"capability_id\":\"$CAP\"}"
d1 "UPDATE entitlement SET status='active' WHERE installation_id = '$INSTALLATION_ID'"
sleep 31
```

**Expect:** HTTP 403, `code = forbidden_capability` (`ai_disabled`). No `ai_request` row. Same code for any non-`active` status.

**Do:** `d1 "UPDATE entitlement SET plan='starter' WHERE installation_id = '$INSTALLATION_ID'"` then POST, restore `plan='standard'`.

**Expect:** 403 `forbidden_capability` (`plan_tier`). Worker preAccept hardcodes `minimumPlanTier: "standard"`. Unknown plans (`verify`) fail closed the same way.

**Do:** `d1 "UPDATE entitlement SET allowed_capabilities='[]' WHERE …"` then POST, restore `'[\"clinic.visit_summary\"]'`.

**Expect:** 403 `forbidden_capability` (`capability_not_granted`).

**Do:** grant revoked / version mismatch / missing:

```bash
d1 "UPDATE capability_grant SET revoked_at = '2026-01-01T00:00:00.000Z'
    WHERE scope = 'installation:$INSTALLATION_ID' AND capability_id = '$CAP'"
sleep 31
invoke "$CLINICIAN_AAT" grant-rev -d "{\"capability_id\":\"$CAP\"}"
d1 "UPDATE capability_grant SET revoked_at = NULL, capability_version = '9.9.9'
    WHERE scope = 'installation:$INSTALLATION_ID' AND capability_id = '$CAP'"
sleep 31
invoke "$CLINICIAN_AAT" grant-ver -d "{\"capability_id\":\"$CAP\"}"
d1 "UPDATE capability_grant SET capability_version = '1.0.0'
    WHERE scope = 'installation:$INSTALLATION_ID' AND capability_id = '$CAP'"
sleep 31
```

**Expect:** both POSTs 403 `forbidden_capability`. Restore version `1.0.0` and `revoked_at` NULL.

**Do:** kill switches (stage 3 evaluates these **before** stage 5). Insert, POST, delete, wait:

```bash
d1 "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
    VALUES ('global','global',1,datetime('now'),'verify')"
```

Repeat separately for `('capability','clinic.visit_summary',1,…)`, `('installation','$INSTALLATION_ID',1,…)`, and `('provider','fake',1,…)` (hardcoded stage-3 `providerId`).

**Expect:** each active row → HTTP 503 `capability_disabled`. Delete the row before the next dimension. `provider:fake` is **this** stage’s provider kill-switch dimension; it is not routing exclusion.

**Do:** after restores, `d1 "SELECT COUNT(*) FROM ai_request WHERE installation_id = '$INSTALLATION_ID'"`

**Expect:** still `0`.

#### 14.3.6 Stage 5 capability resolve

Entitlement must be active with `clinic.visit_summary` granted. Identity must pass. Use missing/invalid capability **after** stage 3 would allow it, or use Access fields on the published visit-summary manifest.

**Do:** `invoke "$CLINICIAN_AAT" cap-unk` with `"capability_id": "clinic.does_not_exist"` (not in `allowed_capabilities`).

**Expect:** 403 `forbidden_capability` at **stage 3**, not `capability_unknown`. Stage 5 registry lookup is only reached when stage 3 already allowed the id.

**Do:** force stage 5 unknown — allow + grant a bogus id:

```bash
d1 "UPDATE entitlement SET allowed_capabilities='[\"clinic.visit_summary\",\"clinic.does_not_exist\"]'
    WHERE installation_id = '$INSTALLATION_ID'"
d1 "INSERT INTO capability_grant (
      grant_id, scope, capability_id, capability_version, granted_at, revoked_at, changed_at, changed_by
    ) VALUES (
      'grant-bogus','installation:$INSTALLATION_ID','clinic.does_not_exist','1.0.0',
      datetime('now'), NULL, datetime('now'), 'verify'
    )"
sleep 31
invoke "$CLINICIAN_AAT" cap-unk2 -d '{"capability_id":"clinic.does_not_exist"}'
```

**Expect:** HTTP 404, `code = capability_unknown`. Restore `allowed_capabilities` and `DELETE` the bogus grant.

**Do:** retire overlay (lifecycle):

```bash
d1 "INSERT INTO capability_grant (
      grant_id, scope, capability_id, capability_version, granted_at, revoked_at,
      changed_at, changed_by, lifecycle_state
    ) VALUES (
      'grant-retired','global','clinic.visit_summary','1.0.0',
      datetime('now'), NULL, datetime('now'), 'verify', 'retired'
    )"
sleep 31
invoke "$CLINICIAN_AAT" cap-ret --data-binary @- <<EOF
{"capability_id":"$CAP","user_intent":"x","context":{"org":"$ORG_ID","branch":"$BRANCH_ID","visit.chief_complaint@v1":{"visit_id":"11111111-1111-4111-8111-111111111111","complaint":"x"}}}
EOF
d1 "DELETE FROM capability_grant WHERE grant_id = 'grant-retired'"
sleep 31
```

**Expect:** HTTP 404, `code = capability_retired`. Control `POST /control/capabilities/…/retire` also writes this overlay after the overlap window; the D1 row is the forcing action that identity/resolve actually reads.

**Do:** `invoke "$DOCTOR_AAT"` with the happy-path body.

**Expect:** 403 `forbidden_capability`. Published `Access.requiredCapabilityScope` is `ai.visit_summary`; doctor scopes are `ai.access`. Scope check runs before roles.

**Do:** signed AAT with `scopes=["ai.visit_summary"]` but `'role', 'doctor'` (clinic enum value, not in `["clinician","nurse"]`).

**Expect:** 403 `forbidden_capability` (`allowedStaffRoles`). Unset/empty Access arrays would skip; visit summary’s arrays are **non-empty**, so they do not skip.

`Access.killSwitchFlag` on the published manifest is `false`. There is no second registered capability with `true`, so that skip/fail pair is **not** forceable on this Worker without editing the manifest (out of scope). `false`/unset skip is the live visit-summary behaviour: a passing request in [§14.3.10](#14310-happy-path-through-prompt-compose) is the skip.

#### 14.3.7 Stage 6 context validate

Use `CLINICIAN_AAT`. Visit summary is `single_shot` with required key `visit.chief_complaint@v1` (`maxSize` 4096).

**Do:** body with matching `org`/`branch` and **no** `visit.chief_complaint@v1`:

```bash
invoke "$CLINICIAN_AAT" ctx-req -d "{
  \"capability_id\":\"$CAP\",
  \"user_intent\":\"sum\",
  \"context\":{\"org\":\"$ORG_ID\",\"branch\":\"$BRANCH_ID\"}
}"
```

**Expect:** HTTP 422, `code = context_required`. Live `preAcceptFailureResponse` does **not** attach `missing_keys` (that helper is unused on the Worker). No journal row. No SSE.

**Do:** required key present, `"org":"other-org"`, correct `branch` and complaint object.

**Expect:** 422 `context_invalid`.

**Do:** correct `org`, `"branch":"other-branch"`.

**Expect:** 422 `context_invalid`.

**Do:** complaint value a **string** (shape requires `visit_id` + `complaint` fields):

```json
"visit.chief_complaint@v1": "not-an-object"
```

**Expect:** 422 `context_invalid`.

**Do:** valid object whose JSON byte length exceeds 4096 (pad `complaint`).

**Expect:** 422 `context_invalid` (`maxSize`).

**Do:** include an extra context key `unpermitted.extra@v1` alongside a valid required key, on the **happy path** later — extra keys are dropped, not rejected. Freshness: send `recorded_at` in the past; stale context is accepted by design (`freshnessHint` is not a Context-requirements field).

Conversational checks (`turn_ordinal` omitted → `context_invalid`; omitted `transcript` → `context_invalid`; empty `transcript` [] valid first leg; budget → `conversation_budget_exhausted`; tenant bind on `context_resolved`; allowlist drop from resolved / `context_requested`) apply only when `manifest.interactionMode === "conversational"`. The published registry has **only** `clinic.visit_summary@1.0.0` (`single_shot`). Those failures are **not** reachable on this Worker. Sending `transcript` / `turn_ordinal` on visit summary is ignored at stage 6; journal still forces NULL grouping columns ([§14.3.13](#14313-journal-insert-columns-and-independent-switches)).

#### 14.3.8 Stage 7 cost pre-flight

Stage 6 must pass. Visit-summary Economics: `maxInputTokens=8000`, `maxOutputTokens=1024`, `perRequestTokenCeiling=9024`. Estimator: `ceil((utf8(serialized context+intent) + promptScaffoldByteLength) / 4) * 1.15`. Units are **tokens**; the preflight does not read `pricing` / D1 price tables.

**Do:** happy-path JSON but `user_intent` ≈ 40 KiB of `x` (still under 1 MiB):

```bash
python3 - <<'PY' > /tmp/big-intent.json
import json, os
intent = "x" * 40000
print(json.dumps({
  "capability_id": os.environ["CAP"],
  "user_intent": intent,
  "context": {
    "org": os.environ["ORG_ID"],
    "branch": os.environ["BRANCH_ID"],
    "visit.chief_complaint@v1": {
      "visit_id": "11111111-1111-4111-8111-111111111111",
      "complaint": "headache"
    }
  }
}))
PY
invoke "$CLINICIAN_AAT" pre-1 --data-binary @/tmp/big-intent.json
```

**Expect:** HTTP 413, `code = request_too_large` (estimated input over `maxInputTokens`, and/or input+`maxOutputTokens` over `perRequestTokenCeiling`). No journal. This is the **same taxonomy** as stage 1 size, after identity — distinguish by using a small `Content-Length` with a large intent.

`perRequestTokenCeiling` is the live field on the published manifest; the loader’s legacy alias `perRequestCostCeiling` is not on this file and is not a POST-time switch.

#### 14.3.9 Stage 8 admission refusals

Need a body that would pass stages 1–7 (`CLINICIAN_AAT` + happy-path JSON). Mint a **new** clinician AAT per POST that should admit (unique `jti`).

**Do:** quota vs rate-limit distinction — zero request quota (budget exhausted, not the 120/min limiter):

```bash
d1 "UPDATE entitlement SET request_quota = 0 WHERE installation_id = '$INSTALLATION_ID'"
sleep 31
invoke "$CLINICIAN_AAT" q-ex --data-binary @/tmp/happy.json   # save happy-path JSON to /tmp/happy.json
d1 "UPDATE entitlement SET request_quota = 1000 WHERE installation_id = '$INSTALLATION_ID'"
sleep 31
```

**Expect:** HTTP 429, `code = quota_exhausted`. **Not** `rate_limited`. Live pre-SSE JSON typically **omits** `period_reset`: `runGuard` only forwards `retryAfter`, and `preAcceptFailureResponse` does not pass admission’s `periodReset`. No `ai_request` row.

**Do:** JTI replay — mint one clinician AAT, POST happy path with idempotency key `jti-a` (this **admits**; see [§14.3.10](#14310-happy-path-through-prompt-compose) if you have not yet done a fresh admit). Then POST **again** with the **same** AAT (same `jti`) and a **new** idempotency key `jti-b`.

**Expect:** second POST HTTP 401 `unauthenticated` (Quota DO `replay`). First journal row remains; no second `request_id` for `jti-b`.

`concurrency_exhausted` maps to the same `quota_exhausted` code (`CONCURRENCY_LIMIT = 16` in-flight). Holding 16 unfinished admissions on a local Worker whose invoke path settles immediately is not a reliable curl force — treat as **unprobeable** here.

Grace path (DO unavailable → local UUID, `grace_admission_queue`, cap 5, 6th = `rate_limited` not `quota_exhausted`) requires the Quota DO fetch to fail. Local `wrangler` binds `GatewayObject`; there is no operator switch to take the DO down. **Unprobeable** on a healthy local Worker. Distinction still stands vs [§14.3.15](#14315-stage-4-rate-limit) (binding limiter) and vs `quota_exhausted` above.

Stage 8 entitlement **miss** (`quota_exhausted`): live `evaluateEntitlement` loads the same row first and does not catch a cache miss, so deleting `entitlement` yields `internal_error` at stage 3, not stage-8 `quota_exhausted`. **Unprobeable** as specified on the ordered pipeline. Do not leave the row deleted.

#### 14.3.10 Happy path through prompt compose

Mint a **fresh** `CLINICIAN_AAT`. Save happy-path JSON (valid complaint object, matching org/branch, short intent). New idempotency key `happy-1`.

**Do:**

```bash
curl -sN --max-time 8 -D /tmp/happy.hdr \
  -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $CLINICIAN_AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: happy-1" \
  -H "x-capability-version: $CAP_VER" \
  -H "x-trace-id: happy-trace-1" \
  --data-binary @/tmp/happy.json
```

**Expect:** HTTP 200, `content-type` SSE. First event `event: accepted` with `request_reference` (`XXXX-XXXX`) and `trace_id` (`happy-trace-1`). This is the Stage 10 boundary this document describes. Do **not** require `text_delta` / `completed` — those are after the guard (provider invoke). Guard success means `accepted`, not a provider token.

**Do:**

```bash
d1 "SELECT request_id, request_reference, installation_id, actor_id, branch_id,
           capability_id, capability_version, prompt_artifact_hash, idempotency_key,
           trace_id, state, created_at, updated_at, completed_at, terminal_error_code,
           payload_pointer, routing_tier, conversation_id, turn_ordinal, routing_decision
    FROM ai_request
    WHERE installation_id = '$INSTALLATION_ID'
    ORDER BY created_at DESC LIMIT 1"
```

**Expect:** one fresh row, every column:

| Column | Expect |
| ------ | ------ |
| `request_id` | UUID (Quota DO, not the idempotency key) |
| `request_reference` | same `XXXX-XXXX` as SSE `accepted` |
| `installation_id` | `I0` (AAT `iss`) |
| `actor_id` | AAT `sub` |
| `branch_id` | AAT `branch` |
| `capability_id` | `clinic.visit_summary` (manifest Identity, not a client alias) |
| `capability_version` | `1.0.0` |
| `prompt_artifact_hash` | 8-char hex content hash — **not** `clinic.visit_summary/system@v1` |
| `idempotency_key` | `happy-1` |
| `trace_id` | `happy-trace-1` |
| `state` | `Accepted` (may already have moved if invoke was fast; it was `Accepted` at INSERT) |
| `completed_at` | `NULL` at INSERT |
| `terminal_error_code` | `NULL` at INSERT |
| `payload_pointer` | `NULL` at INSERT |
| `routing_tier` | `standard` (usage still below `soft_threshold` 0.8) |
| `conversation_id` | `NULL` (single_shot) |
| `turn_ordinal` | `NULL` (single_shot) |
| `routing_decision` | `NULL` at INSERT — Stage 10 routing writes it later |

Principal handoff: journal `installation_id` / `actor_id` / `branch_id` match AAT `iss` / `sub` / `branch`. Role and scopes are not journaled; they were enforced at stage 5 (`clinician` + `ai.visit_summary`).

Compose: `streamFlag: true` is why the response is SSE rather than a JSON body. `stopConditions` is always `[]` (no HTTP field). Production `createProductionPreAccept` does not forward a client `deadline` (always `null` on the CanonicalRequest). `neutralizeText` (`</` → `\u003c/`) lives on the composed user part; it is **not** a D1 column. If Stage 11 later writes `request/<request_id>/envelope`, the `prompt` field shows the escaped intent — that read is settlement, not the guard.

Compose `internal_error` (missing prompt artifact) cannot be forced without breaking published pins. **Unprobeable** on this Worker.

#### 14.3.11 Idempotent replay skips journal and compose

**Do:** immediately reuse **`happy-1`** (same installation, same idempotency key) with a **new** clinician AAT (new `jti` so this is not JTI replay) and the same body.

```bash
d1 "SELECT COUNT(*) AS n FROM ai_request WHERE installation_id = '$INSTALLATION_ID'"
# POST again with x-idempotency-key: happy-1
d1 "SELECT COUNT(*) AS n FROM ai_request WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT request_id, idempotency_key FROM ai_request
    WHERE idempotency_key = 'happy-1'"
```

**Expect:** row count **unchanged**. Same `request_id`. Guard outcome `idempotent`: stages 9 and 10 skipped (no second INSERT, prompt not recomposed). SSE replays the prior terminal outcome (Stage 10 boundary). This is **not** `quota_exhausted` and **not** `rate_limited`.

#### 14.3.12 Soft-threshold degraded routing_tier

Need usage ≥ `soft_threshold` of a budget while still under 100%. After [§14.3.10](#14310-happy-path-through-prompt-compose) at least one request has been credited (or wait until `usage_event` shows it).

**Do:**

```bash
d1 "UPDATE entitlement SET request_quota = 1000, soft_threshold = 0.001
    WHERE installation_id = '$INSTALLATION_ID'"
sleep 31
# mint fresh CLINICIAN_AAT; new idempotency key happy-deg
curl -sN --max-time 8 … --data-binary @/tmp/happy.json
d1 "SELECT routing_tier FROM ai_request
    WHERE idempotency_key = 'happy-deg'"
```

**Expect:** `routing_tier = degraded`. SSE `accepted` includes `degraded_notice: true`. Request still **admitted** (not `quota_exhausted`). Restore `soft_threshold = 0.8` afterwards.

`soft_threshold = 0` disables degrade (enroll pending sentinel). A POST after setting `0` journals `standard` even if counters are high.

#### 14.3.13 Journal INSERT columns and independent switches

**Do:** POST happy-path body **plus** `"routing_tier":"degraded","degraded":true,"degraded_notice":true,"conversation_id":"should-be-ignored","turn_ordinal":3,"transcript":[]` with a new idempotency key.

**Expect:** `accepted`. Journal `routing_tier` still from admission (`standard` unless [§14.3.12](#14312-soft-threshold-degraded-routing-tier) still applies). `conversation_id` / `turn_ordinal` **NULL** (single_shot forces NULL regardless of wire). Client keys did not select the tier.

**Do:** provider kill switch that is **not** `fake`:

```bash
d1 "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by)
    VALUES ('provider','deepseek',1,datetime('now'),'verify')"
sleep 31
# POST happy path (fresh jti + idempotency)
d1 "DELETE FROM kill_switch WHERE scope='provider' AND target='deepseek'"
```

**Expect:** guard **passes** (`accepted`), **not** 503 `capability_disabled`. Stage 5 collects routing-policy provider ids as `killedProviderIds` for the router. (What the chain does after `accepted` is Stage 10 invoke — do not treat a later `provider_unavailable` as a guard failure.)

**Do:** while the happy-path row is still `Accepted` (or inspect immediately after INSERT via a second terminal): `routing_decision` is NULL; `payload_pointer` NULL; no `usage_event` yet from the **guard**. The guard does not call DeepSeek/Gemini and does not `credit` / settle.

Stage 9 D1 insert failure (Quota DO `release` + `internal_error`) needs a failing `INSERT`. Live D1 will not collide the DO-issued `request_id`. **Unprobeable** with curl/SQL without injecting a broken database.

#### 14.3.14 ConfigCache rotate and rejection counters

**Do:** with the Worker **left running** (warm isolate), suspend:

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/suspend" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
# POST immediately (no sleep) with CLINICIAN_AAT
sleep 31
# POST again
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/resume" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
sleep 31
```

**Expect:** the immediate POST may still **pass identity** (cached `status=active`, 30 s TTL). The POST after 31 s is 403 `installation_suspended`. Warm isolate does not re-read D1 for the same key inside the window.

**Do:** rotate (throwaway key), prove dual-key overlap, then `revoke-key` cuts the old kid, restore `K0`:

```bash
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/rotate" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"kid\":\"rotate-temp-kid\",\"public_key\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"algorithm\":\"EdDSA\"}"
d1 "SELECT key_id, revoked_at, valid_from, valid_until FROM installation_key
    WHERE installation_id = '$INSTALLATION_ID'"
invoke "$CLINICIAN_AAT" rot-1 -d "{\"capability_id\":\"$CAP\"}"
curl -s -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/revoke-key" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"kid\":\"$KID\"}"
sleep 31
invoke "$CLINICIAN_AAT" rot-2 -d "{\"capability_id\":\"$CAP\"}"
d1 "UPDATE installation_key SET revoked_at = NULL WHERE key_id = '$KID'"
d1 "DELETE FROM installation_key WHERE key_id = 'rotate-temp-kid'"
sleep 31
```

**Expect:** after rotate, **two** rows with `revoked_at` NULL (`K0` and `rotate-temp-kid`); `K0.revoked_at` stays NULL. `valid_until` on the new row ≈ `valid_from` + 365 days. Old `CLINICIAN_AAT` (header `kid=K0`) still invokes successfully (dual-key overlap). After `revoke-key` on `K0`, that AAT → 401 `unauthenticated` regardless of `exp`. Restore `K0` before continuing.

**Do:**

```bash
d1 "SELECT counter_id, dimension_set, time_bucket, count FROM platform_counter LIMIT 20"
```

**Expect:** may be **empty** after many [§14.3.3](#1433-stage-2-wire-token-identity-failures) rejects. `recordGuardRejection` tallies in-isolate; `flushRejectionCounters` runs from cron on whichever isolate ticks. `platform_counter` is a **lower bound**, not an exact count. Do not treat a zero as “no rejects happened.”

#### 14.3.15 Stage 4 rate limit

Run last so the 60 s window does not block earlier POSTs. Stage 4 runs after entitlement and **before** context validate. Use `CLINICIAN_AAT` and a body that fails stage 6 (missing complaint) so admits/journals do not pile up.

Wrangler `simple` limits (development): installation 600/60 s, installation+actor **120/60 s**, installation+capability 300/60 s. Tightest is actor.

**Do:**

```bash
for i in $(seq 1 121); do
  invoke "$CLINICIAN_AAT" "rl-$i" -d "{
    \"capability_id\":\"$CAP\",
    \"user_intent\":\"x\",
    \"context\":{\"org\":\"$ORG_ID\",\"branch\":\"$BRANCH_ID\"}
  }" | tail -n 1
done
```

**Expect:** early responses 422 `context_required` (passed stages 1–5). Some later response HTTP 429, `code = rate_limited`, JSON includes `retry_after` (positive seconds from the binding hint, else **60**). **Not** `quota_exhausted` (budget still 1000). **Not** grace-cap `rate_limited` (DO is up; no `grace_admission_queue` insert). No `ai_request` row for the limited calls.

This is the only client-visible `rate_limited` the guard emits. A provider HTTP 429 after `accepted` is retried in invocation and, if the chain exhausts, surfaces as `provider_unavailable` — that is **not** this stage; do not look for it here.

Wait 60 s (or restart the Worker) before any further `/v1/requests` smoke.


