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
11. [11. Behavioral verification](#11-behavioral-verification)
   - [11.1 Setup](#111-setup)
   - [11.2 Coverage](#112-coverage)
   - [11.3 Ordered probes](#113-ordered-probes)
     - [11.3.1 Reset to a known platform state](#1131-reset-to-a-known-platform-state)
     - [11.3.2 Lifecycle alternatives (control plane)](#1132-lifecycle-alternatives-control-plane)
     - [11.3.3 Zero quotas after entitle](#1133-zero-quotas-after-entitle)
     - [11.3.4 Missing routing policy](#1134-missing-routing-policy)
     - [11.3.5 JTI replay](#1135-jti-replay)
     - [11.3.6 Grace admission and cron reconciliation](#1136-grace-admission-and-cron-reconciliation)
     - [11.3.7 Client disconnect](#1137-client-disconnect)
     - [11.3.8 Prose guard failures](#1138-prose-guard-failures)
     - [11.3.9 Complete pre-SSE failure matrix](#1139-complete-pre-sse-failure-matrix)
     - [11.3.10 Retention, counters, delete, and purge](#11310-retention-counters-delete-and-purge)

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


## 11. Behavioral verification

Live probes against a local Worker (`npx wrangler dev --env development --test-scheduled`) and a throwaway local clinic Supabase. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§11.3](#113-ordered-probes) top to bottom**. If every probe matches, this failure catalog is working.

Admission records AAT `jti` only after a **successful** Quota DO admit (`EPHEMERAL_HORIZON_MS` = 2 h). Reusing the same token on a later request that reaches stage 8 is [§4](#4-jti-replay) (`unauthenticated`), not a new job. Mint a **fresh** `issue_ai_token()` for every probe that can pass stage 8, except the replay probe itself.

The isolate `ConfigCache` TTL is 30 s (`CACHE_TTL_MS`). After any control-plane or SQL D1 write, wait 31 seconds (or restart `wrangler dev`) before the next `POST /v1/requests`.

Published capability on this Worker is only `clinic.visit_summary@1.0.0` (single-shot). `Access.allowedStaffRoles` is `clinician` / `nurse`; `requiredCapabilityScope` is `ai.visit_summary`; `minimumPlanTier` is `standard` (hardcoded again in `createProductionPreAccept`). Enroll `plan` must be `standard` or higher.

### 11.1 Setup

- Local Worker on `http://127.0.0.1:8787` with `--test-scheduled` so Wrangler exposes `/cdn-cgi/handler/scheduled` (not a production route — it fires `scheduled()`).
- `OPERATOR_BEARER_TOKEN` from `.dev.vars` / `.dev.vars.development` (one secret; `OPERATOR_ID` is `platform-operator` in `wrangler.toml`).
- Throwaway local clinic: owner/admin to enroll a keypair; a staff row with `staff_members.role` in `('clinician', 'nurse')` and RBAC `ai.visit_summary` to mint AATs.
- SQL as `postgres` only to inspect clinic `ai_internal` and mint tokens. D1 inspection via Wrangler:

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
cd ai-platform

d1() {
  npx wrangler d1 execute ai-platform-development --local --env development --command "$1"
}
```

Call clinic RPCs as the named session (same pattern as [Stage 2 §8.1](04-stage-2-clinic-keypair-enrollment.md#81-setup)). Decode an AAT payload with `python3 -c 'import json,sys,base64; p=sys.argv[1].split(".")[1]+"=="; print(json.dumps(json.loads(base64.urlsafe_b64decode(p))))' "$AAT"`. Save `iss` as **I0**, `org`, `branch`, `kid`, `jti`.

Reusable invoke (change idempotency key and AAT each time you expect a fresh admit):

```bash
invoke() {
  local key="$1"
  local body="${2:-$VISIT_BODY}"
  curl -sS -D /tmp/ai-hdr -o /tmp/ai-body \
    -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $AAT" \
    -H "x-idempotency-key: $key" \
    -H "x-capability-version: 1.0.0" \
    -H "Content-Type: application/json" \
    --data "$body"
  echo "HTTP $(awk 'NR==1{print $2}' /tmp/ai-hdr)"
  cat /tmp/ai-body; echo
}
```

`$VISIT_BODY` is the visit-summary object from [Stage 8 §7](10-stage-8-request-ingress.md#7-visit-summary-example-body) with `context.org` / `context.branch` equal to the AAT claims.

### 11.2 Coverage

Every claim in this file maps to a probe, including every [§8](#8-complete-pre-sse-failure-matrix) matrix row. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| One `OPERATOR_BEARER_TOKEN` / `OPERATOR_ID`; `control_audit` cannot distinguish operators | [§11.3.2](#1132-lifecycle-alternatives-control-plane) |
| `POST …/suspend` → `installation.status=suspended` → AAT `installation_suspended` | [§11.3.2](#1132-lifecycle-alternatives-control-plane) |
| `POST …/resume` → `status=active` → restores | [§11.3.2](#1132-lifecycle-alternatives-control-plane) |
| `POST …/rotate` → new key `valid_until` = now + 365 days; prior unrevoked keys `revoked_at=now`; old `kid` fails identity; new `kid` verifies | [§11.3.2](#1132-lifecycle-alternatives-control-plane) |
| `POST …/revoke-key` → `revoked_at` on that key; AAT with that `kid` fails identity | [§11.3.2](#1132-lifecycle-alternatives-control-plane) |
| `POST …/delete` → `status=deleted` → `unauthenticated` | [§11.3.10](#11310-retention-counters-delete-and-purge) |
| `POST …/purge` deletes installation data + R2 envelopes (irreversible) | [§11.3.10](#11310-retention-counters-delete-and-purge) |
| `entitlement.status=active` and `request_quota=0` → admission `quota_exhausted` | [§11.3.3](#1133-zero-quotas-after-entitle) |
| Guard passes → `accepted` → invoke preload miss → `failed` `internal_error` | [§11.3.4](#1134-missing-routing-policy) |
| Target `features` omit/mistype `min_context_window`, `cost_class`, or `languages` → `feature_unsupported` (no throw) | [§11.3.4](#1134-missing-routing-policy) |
| Remaining chain empty → `failed` / `provider_unavailable` (not `internal_error`) | [§11.3.4](#1134-missing-routing-policy) |
| Same `jti` within 2 h → admission `replay` → `unauthenticated` | [§11.3.5](#1135-jti-replay) |
| Quota DO down → D1 `grace_admission_queue` (not isolate memory) | [§11.3.6](#1136-grace-admission-and-cron-reconciliation) |
| Cap `GRACE_ADMISSION_CAP` (5) pending → `rate_limited` + `retry_after`, not `quota_exhausted`; count is durable | [§11.3.6](#1136-grace-admission-and-cron-reconciliation) |
| Journaled `(installation_id, idempotency_key)` → `idempotent` (skips provider) | [§11.3.6](#1136-grace-admission-and-cron-reconciliation) |
| Pending grace row on same key → same `graceRequestId` / `requestReference` | [§11.3.6](#1136-grace-admission-and-cron-reconciliation) |
| Grace `UNIQUE (installation_id, idempotency_key)`; `ai_request` has no such unique | [§11.3.6](#1136-grace-admission-and-cron-reconciliation) |
| Exhausted ledger is not served during an outage (`quota_exhausted`) | [§11.3.3](#1133-zero-quotas-after-entitle), [§11.3.6](#1136-grace-admission-and-cron-reconciliation) |
| `creditUsage` attaches tokens/cost onto the pending D1 row; cron credits **attached** usage | [§11.3.6](#1136-grace-admission-and-cron-reconciliation) |
| Cron `reconcileGraceUsage` re-admits on the recovered DO; TTL / max-attempt drops leave `pending` so they no longer count toward the cap | [§11.3.6](#1136-grace-admission-and-cron-reconciliation) |
| Client disconnect → SSE `cancelled`; Quota DO `credit` `partial: true` even at `{ tokens: 0, cost: 0 }`; idempotency `cancelled` | [§11.3.7](#1137-client-disconnect) |
| Cancel writes `usage_event` always, `ai_attempt` only when invocation recorded attempts, plus one R2 envelope | [§11.3.7](#1137-client-disconnect) |
| Output > 128000 chars → `validation_failed`; credit accrued/zero; `partial: false`; idempotency `failed` | [§11.3.8](#1138-prose-guard-failures) |
| Stop sequence `<\|end\|>` → same | [§11.3.8](#1138-prose-guard-failures) |
| System-prompt leak (opening / interior / ending slice) → same | [§11.3.8](#1138-prose-guard-failures) |
| Refusal prefix (`I'm sorry, I can't help with that` / `I'm sorry, I can't assist`) → same | [§11.3.8](#1138-prose-guard-failures) |
| Injection-echo needle `Ignore previous instructions` → same | [§11.3.8](#1138-prose-guard-failures) |
| Empty output → same | [§11.3.8](#1138-prose-guard-failures) |
| Provider truncation (`finishReason: length`) is never authoritative `completed` | [§11.3.8](#1138-prose-guard-failures) |
| Ingress size → HTTP 413 `request_too_large` (empty `request_reference` / `trace_id`) | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Ingress JSON → HTTP 422, no taxonomy body | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Missing `x-idempotency-key` / `x-capability-version` → HTTP 422, no taxonomy body | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 1 `request_too_large` / `internal_error` | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 2 `unauthenticated` / `installation_suspended` | [§11.3.2](#1132-lifecycle-alternatives-control-plane), [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 3 `forbidden_capability` / `capability_disabled` | [§11.3.1](#1131-reset-to-a-known-platform-state), [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 4 `rate_limited` (`retry_after` from binding, else 60) | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 5 `capability_unknown` / `capability_retired` / `capability_disabled` | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 6 `context_required` / `context_invalid` / `conversation_budget_exhausted` | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 7 `request_too_large` (economics + prompt-scaffold bytes) | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 8 `unauthenticated` / `quota_exhausted` / `rate_limited` / `internal_error` | [§11.3.3](#1133-zero-quotas-after-entitle), [§11.3.5](#1135-jti-replay), [§11.3.6](#1136-grace-admission-and-cron-reconciliation), [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 9 `context_invalid` / `internal_error` | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| Stage 10 `internal_error` (compose failure) | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| `provider:<id>` kill switch is not a pre-SSE 503; after `accepted`, `reason_code: kill_switch`; empty chain → `provider_unavailable` | [§11.3.9](#1139-complete-pre-sse-failure-matrix) |
| `runRetentionPurge` (`0 3 * * *`) nulls `usage_event.request_id` then deletes `ai_request` / `ai_attempt` / R2 envelopes | [§11.3.10](#11310-retention-counters-delete-and-purge) |
| Aged usage loses request-level joinability; `LEFT JOIN usage_event u ON u.request_id = r.request_id` cannot match; money row remains | [§11.3.10](#11310-retention-counters-delete-and-purge) |
| `recordGuardRejection` is isolate-local; cron `flushRejectionCounters` writes only the ticking isolate; `platform_counter.count` is a lower bound | [§11.3.10](#11310-retention-counters-delete-and-purge) |
| Request-end batched flush is not implemented | [§11.3.10](#11310-retention-counters-delete-and-purge) |


### 11.3 Ordered probes

#### 11.3.1 Reset to a known platform state

**Do:** as clinic owner, mint a keypair if none exists (`SELECT public.enroll_installation_keypair();`). Save `installation_id` **I0**, `kid` **K0**, `public_jwk.x`. Start the Worker with `--test-scheduled`. Enroll with `plan: "standard"` (not `starter` for visit-summary minimum tier):

```bash
curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/enroll" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "org_id": "<clinic organizations.id>",
    "display_name": "Verify Clinic",
    "region": "local",
    "plan": "standard",
    "public_key": "<public_jwk.x>",
    "algorithm": "EdDSA",
    "kid": "<K0>"
  }'
```

**Expect:** HTTP 200 `{ "platform_base_url": "http://127.0.0.1:8787" }`. D1 `installation.status=active`, entitlement `status=pending`, quotas `0`. Wrong Bearer on any `/control/*` route → HTTP 401 `{ "error": "unauthorized" }`.

**Do:** mint an AAT as clinician/nurse with `ai.visit_summary`. `POST /v1/requests` with `$VISIT_BODY` (**do not entitle**).

**Expect:** HTTP 403 JSON `code: "forbidden_capability"` (stage 3 path `ai_disabled`). No SSE. This is the pending-entitlement half of the stage 3 matrix row.

**Do:** entitle (one-shot while `pending`):

```bash
curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/entitle" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "period_start": "2026-08-01T00:00:00.000Z",
    "period_end": "2027-08-01T00:00:00.000Z",
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

Wait 31 s.

**Expect:** HTTP 200 `{ "installation_id": "<I0>", "status": "active" }`. D1 `entitlement.status=active`, `request_quota=1000`. Repeat entitle → 409 `not_pending`. Do **not** publish a routing policy yet.

#### 11.3.2 Lifecycle alternatives (control plane)

**Do:** `POST $GATEWAY/control/installations/$INSTALLATION_ID/suspend` with the operator Bearer (empty body). Then `d1 "SELECT status FROM installation WHERE installation_id = '<I0>'"` and `d1 "SELECT action, operator_id FROM control_audit ORDER BY recorded_at DESC LIMIT 5"`. Wait 31 s. Mint a fresh AAT. `invoke`.

**Expect:** suspend HTTP 200 `{}`. `status=suspended`. Every `control_audit.operator_id` is the single `OPERATOR_ID` (`platform-operator` locally) — rotation/revocation of the Bearer is all-or-nothing. Invoke → HTTP 403 `code: "installation_suspended"` (stage 2). Repeat suspend → 409 `illegal_lifecycle_transition`.

**Do:** `POST …/resume`. Wait 31 s. Fresh AAT. `invoke`.

**Expect:** HTTP 200. `status=active`. Invoke is no longer `installation_suspended` (it may still fail later in this sequence because no routing policy is published — identity has been restored). Resume while already active → 409 `illegal_lifecycle_transition`.

**Do:** as clinic admin, `SELECT public.rotate_installation_key();`. Save new `kid` **K1** and `public_jwk.x`.

```bash
curl -sS -X POST "$GATEWAY/control/installations/$INSTALLATION_ID/rotate" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"kid":"<K1>","public_key":"<K1 public_jwk.x>","algorithm":"EdDSA"}'
```

Wait 31 s. Invoke with an AAT whose header `kid` is **K0**, then mint a new AAT (issuer picks the latest active clinic key) and invoke again.

**Expect:** rotate HTTP 200. D1: **K1** row `valid_until` ≈ `valid_from` + 365 days (`INSTALLATION_KEY_TTL_DAYS`); **K0** `revoked_at` is now (same batch — no dual-key overlap). K0 AAT → HTTP 401 `unauthenticated`. New AAT with **K1** verifies at identity.

**Do:** `POST …/revoke-key` with `{"kid":"<K1>"}`. Wait 31 s. Invoke with the K1 AAT. Then as clinic admin, `SELECT public.rotate_installation_key();` — save new `kid` **K2** and `public_jwk.x`. Platform `POST …/rotate` with `{"kid":"<K2>","public_key":"<K2 public_jwk.x>","algorithm":"EdDSA"}`. Wait 31 s.

**Expect:** revoke HTTP 200. K1 `revoked_at` set. K1 AAT → 401 `unauthenticated`. Repeat revoke → 409 `key_already_revoked`. Clinic `rotate_installation_key` → `success = true` with new **K2** (same `installation_id` **I0**). Platform rotate HTTP 200; prior unrevoked D1 keys get `revoked_at` in the same batch. Freshly minted AAT with **K2** verifies. Save **K2** as the live `kid`.

#### 11.3.3 Zero quotas after entitle

Entitle cannot run again (`not_pending`). **Do:**

```bash
d1 "UPDATE entitlement SET request_quota = 0 WHERE installation_id = '<I0>'"
```

Wait 31 s. Fresh AAT. `invoke`.

**Expect:** HTTP 429 JSON `code: "quota_exhausted"` (stage 8). Entitlement is still `active` — this is not stage 3 `forbidden_capability`. Body may include `period_reset` equal to `entitlement.period_end`. No `ai_request` row for this attempt (`recordGuardRejection` tallies `quota_exhausted` in-isolate only until cron flush).

**Do:** `d1 "UPDATE entitlement SET request_quota = 1000 WHERE installation_id = '<I0>'"` and wait 31 s.

**Expect:** later probes can admit again.

#### 11.3.4 Missing routing policy

Guard compose does **not** load the routing document. **Do:** fresh AAT, `invoke` (still no `routing_policy` row with `status=active` / `canary` for `standard`). Read the SSE stream to the terminal event (`curl -N` or `invoke` as-is if it buffers the stream).

**Expect:** HTTP 200 `text/event-stream`. First event `accepted`. Then `event: failed` with `code: "internal_error"` (invoke `preloadRoutingPolicyForInstallation` / `loadConfig("active_routing_policy")` miss). D1 `ai_request` exists (`state` Failed, `terminal_error_code=internal_error`). This is [§3](#3-missing-routing-policy), not a pre-SSE outage.

**Do:** publish and promote a playbook whose only target **omits** `features.min_context_window` (mistype `cost_class` or omit `languages` — same fail-closed path). URL version `1`, `document.policy_id: "standard"`, `document.policy_version: 1`, `features.latency_class: "standard"` (manifest `Routing.latencyClass`). Then wait 31 s. Fresh AAT. `invoke`. Inspect `ai_request.routing_decision`.

```bash
curl -sS -X POST "$GATEWAY/control/routing-policies/standard/versions/1/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"document":{ "schema_version":1, "policy_id":"standard", "policy_version":1, "defaults":{"cost_class":"standard","max_parallel_attempts":1}, "rules":[{ "rule_id":"broken-features", "match":{"capability_ids":["clinic.visit_summary"],"installation_ids":[],"cost_classes":[],"tiers":[],"languages":[],"latency_classes":[]}, "requires":{"structured_output":false,"min_context_window":0,"languages":[]}, "targets":[{ "provider_id":"fake", "model_id":"fake-v1", "features":{"structured_output":false,"languages":["en"],"latency_class":"standard","cost_class":"standard"}, "max_attempts":1, "timeout_ms":5000 }] }], "overrides":[] }}'

curl -sS -X POST "$GATEWAY/control/routing-policies/standard/versions/1/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

**Expect:** publish 200 (possibly `{ "warnings": ["latency_class_mismatch"] }` if a target latency does not match the manifest — this document’s broken target still has `latency_class`). Promote 200. Invoke: HTTP 200 SSE `accepted`, then `failed` `provider_unavailable` — **not** `internal_error`. `routing_decision.excluded[]` contains `reason_code: "feature_unsupported"`; `chain` is empty. `filterTargets` did not throw.

**Do:** publish **version 2** with a complete `fake` target (`min_context_window: 128000`, `languages: ["en"]`, `latency_class: "standard"`, `cost_class: "standard"`) and `POST …/versions/2/promote`. Wait 31 s. Fresh AAT. `invoke`.

**Expect:** SSE `accepted` then `completed` (local `FakeAdapter(["success"])` text `Fake adapter summary.`). Save this `request_reference` if the stream echoes it. This is the working policy for later post-accept probes.

#### 11.3.5 JTI replay

**Do:** mint AAT **T**. `invoke` with idempotency key `jti-a` using **T**. Immediately `invoke` with a **different** key `jti-b` still using **T**.

**Expect:** first call is admitted (SSE opens). Second call is HTTP 401 `code: "unauthenticated"` (DO `outcome: "replay"`, `EPHEMERAL_HORIZON_MS` = 7_200_000 ms). Same `jti` within 2 h cannot start a second job. (Retry of the **same** job uses a **new** AAT and the **same** `x-idempotency-key` — that is idempotent replay, not this probe.)

#### 11.3.6 Grace admission and cron reconciliation

Local Miniflare keeps the Quota DO up, so the Worker does not enter `admitUnderGrace` on a healthy process. The queue, cap, uniqueness, and cron drain are still D1 — force them with SQL and Wrangler’s scheduled injector.

**Do:**

```bash
d1 "SELECT sql FROM sqlite_master WHERE name = 'grace_admission_queue'"
d1 "INSERT INTO grace_admission_queue (grace_request_id, installation_id, idempotency_key, jti, request_reference, entitlement_json, queued_at, reconcile_attempts, status) VALUES ('g-dup-a', '<I0>', 'dup-key', 'jti-a', 'AAAA-AAAA', '{}', datetime('now'), 0, 'pending')"
d1 "INSERT INTO grace_admission_queue (grace_request_id, installation_id, idempotency_key, jti, request_reference, entitlement_json, queued_at, reconcile_attempts, status) VALUES ('g-dup-b', '<I0>', 'dup-key', 'jti-b', 'BBBB-BBBB', '{}', datetime('now'), 0, 'pending')"
```

**Expect:** table has `UNIQUE (installation_id, idempotency_key)`. Second insert fails that unique. `d1 "SELECT sql FROM sqlite_master WHERE name = 'ai_request'"` shows **no** unique on `(installation_id, idempotency_key)`.

**Do:** insert five `status=pending` rows for **I0** with distinct keys `cap-1` … `cap-5`. Then run the same `INSERT … SELECT … WHERE (SELECT COUNT(*) … pending) < 5` shape as `admitUnderGrace` (`GRACE_ADMISSION_CAP`):

```bash
d1 "INSERT INTO grace_admission_queue (grace_request_id, installation_id, idempotency_key, jti, request_reference, entitlement_json, queued_at, reconcile_attempts, status) SELECT 'g-cap-6', '<I0>', 'cap-6', 'jti-6', 'CCCC-CCCC', '{}', datetime('now'), 0, 'pending' WHERE (SELECT COUNT(*) FROM grace_admission_queue WHERE installation_id = '<I0>' AND status = 'pending') < 5"
d1 "SELECT COUNT(*) AS pending FROM grace_admission_queue WHERE installation_id = '<I0>' AND status = 'pending'"
```

**Expect:** `g-cap-6` is absent. Pending count stays 5 — the cap is a durable `COUNT(*)`, not isolate memory. On a live outage the Worker maps this miss to HTTP 429 `rate_limited` with `retry_after` 60 (`DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS`), **not** `quota_exhausted`. That HTTP observation requires Quota DO transport `unavailable` (unprobeable on a healthy local DO). Ledger exhaustion during an outage is the same `isLedgerQuotaExhausted` check already seen in [§11.3.3](#1133-zero-quotas-after-entitle).

**Do:** pick one pending row. `d1 "UPDATE grace_admission_queue SET usage_tokens = 10, usage_cost = 0.01, partial = 0 WHERE grace_request_id = '<that id>'"`. Fire cron (every tick runs `flushRejectionCounters` then `reconcileGraceUsage`; `0 3 * * *` also runs retention):

```bash
curl -sS "$GATEWAY/cdn-cgi/handler/scheduled?cron=0+4+*+*+*"
d1 "SELECT grace_request_id, status, usage_tokens, usage_cost FROM grace_admission_queue WHERE installation_id = '<I0>'"
```

**Expect:** rows the DO can re-admit become `status=reconciled` and no longer count toward the cap. Cron credits **attached** `(10, 0.01)`, not phantom zeros (`reconcileGraceUsage` uses `entry.usage ?? { tokens: 0, cost: 0 }`).

**Do:** seed `status=pending` with `reconcile_attempts = 5` (`GRACE_RECONCILE_MAX_ATTEMPTS`) and another with `reconcile_first_seen_at_ms` older than 7_200_000 (`GRACE_RECONCILE_TTL_MS`). Fire scheduled again.

**Expect:** those rows become `status=dropped` (leave `pending`). `COUNT(*) … status='pending'` no longer includes them.

**Do:** after a **completed** job from [§11.3.4](#1134-missing-routing-policy), mint a **new** AAT (new `jti`) and `invoke` with the **same** `x-idempotency-key` as that completed job.

**Expect:** guard `outcome: "idempotent"` — pipeline skips the provider (SSE replays the prior terminal). That is the journaled-row short-circuit. When the DO is down, `admitUnderGrace` does the same via `SELECT ai_request` / pending grace on `(installation_id, idempotency_key)` and returns the stored `graceRequestId` / `requestReference` for a pending grace hit. Re-selecting that pending key does not insert a second queue row (unique + `selectGraceByKey`).

#### 11.3.7 Client disconnect

**Do:** fresh AAT. Open the stream and abort after `accepted` (before the terminal):

```bash
curl -N --max-time 1 -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "x-idempotency-key: disconnect-1" \
  -H "x-capability-version: 1.0.0" \
  -H "Content-Type: application/json" \
  --data "$VISIT_BODY"
```

Then `d1` the `ai_request` / `usage_event` / `ai_attempt` for that job; confirm R2 `request/{request_id}/envelope`.

**Expect:** if the abort wins, SSE `event: cancelled`. Broker `creditSink` is called with `partial: true` (`cancelled.consumesQuota` is `"Partially, recorded"`, not `"Yes"`) even when usage is `{ tokens: 0, cost: 0 }`, so Quota DO `inFlight` is released and idempotency state is `cancelled`. `usage_event` is present. `ai_attempt` is present only if invocation recorded attempts (abort before the first provider call may have none). One R2 envelope. If local `FakeAdapter` completes first, you will see `completed` instead — the disconnect lost the race on the fast fake path (retry immediately after `accepted`, or use a slow wired provider). That race is the only unprobeable part of this claim on the default local adapter.

#### 11.3.8 Prose guard failures

Production thresholds (`PRODUCTION_GUARD_THRESHOLDS`): `maxLength` 128000; `stopSequences` `["<|end|>"]`; `refusalPrefixes` `I'm sorry, I can't help with that` and `I'm sorry, I can't assist`; `injectionEchoNeedle` `Ignore previous instructions`; leak needles are the composed system-instruction opening / interior / ending slices from the guard. Every hit is SSE `failed` `validation_failed` (HTTP 200 stream, not pre-SSE 422). Settlement: credit accrued or zero usage with `partial: false` (taxonomy `consumesQuota: "Yes"`); idempotency `failed`.

Local `resolveProviderPort("fake")` is `new FakeAdapter(["success"])` — assembled text is always `Fake adapter summary.`, which trips **none** of these. The forcing action is still the assembled stream text:

| Assembled text | Violation |
| -------------- | --------- |
| length > 128000 | `length_ceiling` |
| contains `<\|end\|>` | `stop_sequence` |
| contains any composed-instruction needle | `system_prompt_leak` |
| starts with a refusal prefix (after trim) | `refusal` |
| contains `Ignore previous instructions` | `injection_echo` |
| empty string at completion | `empty_output` |
| provider `finishReason: "length"` (FakeAdapter `createTruncationResult`) | truncated prose — never authoritative `completed` |

**Do:** complete one fake job, then `POST /control/support/lookup?reference=<ref>` (operator Bearer) and read envelope `prompt` for the leak needles.

**Expect:** needles are non-empty slices of the composed instruction.

**Do:** (length) assembled text longer than 128000 characters. **Do:** (stop) assembled text contains `<|end|>`. **Do:** (leak) assembled text contains any of those needles. **Do:** (refusal) assembled text starts with `I'm sorry, I can't help with that` or `I'm sorry, I can't assist`. **Do:** (injection-echo) assembled text contains `Ignore previous instructions`. **Do:** (empty) completion with empty assembled text. **Do:** (truncation) provider `finishReason: "length"`.

**Expect:** each of those assembled texts → SSE `failed` / `validation_failed`, credit `partial: false`, idempotency `failed`, never `completed`. Truncated prose is never authoritative `completed`. Local `FakeAdapter(["success"])` still completes with `Fake adapter summary.` for every `user_intent` — these terminals are observable only when the invoke path actually emits that assembled text.

#### 11.3.9 Complete pre-SSE failure matrix

Every row is a pre-SSE HTTP JSON failure except where noted. Error bodies that have a taxonomy code are `{ code, request_reference, trace_id, retry_safe }` plus `retry_after` / `period_reset` when `supplementaryFieldsForCode` adds them.

**Ingress size.** **Do:** `Content-Length: 1048577` (1 MiB + 1) on `POST /v1/requests` (body may be tiny).

**Expect:** HTTP 413 JSON `code: "request_too_large"` with **empty** `request_reference` and `trace_id` (adapter size gate runs before headers/reference). This is the matrix “Ingress size” row.

**Ingress JSON.** **Do:** body `{` or `[]` with required headers.

**Expect:** HTTP 422, **empty** body, no taxonomy `code` (`adapterParseFailureResponse`). Matrix “Ingress JSON” row.

**Missing headers.** **Do:** valid JSON object, omit `x-idempotency-key`; repeat omitting `x-capability-version`; repeat sending `x-trace-id: ' '` (whitespace-only).

**Expect:** HTTP 422, empty body, no taxonomy code. Matrix “Missing headers” row.

**Stage 1.** **Do:** the same oversize and malformed bodies.

**Expect:** the live Worker answers at the adapter (413 / 422) **before** `runGuard` stage 1. Guard stage 1 `request_too_large` / `internal_error` (non-object JSON) are not a distinct HTTP observation on this path — the forcing actions are the two ingress rows above.

**Stage 2 `unauthenticated`.** **Do:** omit `Authorization`; or send `Bearer not-a-jws`. Fresh valid AAT is not required.

**Expect:** HTTP 401 `code: "unauthenticated"`. Suspended is already [§11.3.2](#1132-lifecycle-alternatives-control-plane) (403 `installation_suspended`). Deleted is [§11.3.10](#11310-retention-counters-delete-and-purge).

**Stage 3 `capability_disabled`.** **Do:**

```bash
d1 "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by) VALUES ('global', 'global', 1, datetime('now'), 'verify')"
```

Wait 31 s. Fresh AAT. `invoke`. Then delete the row and wait 31 s. Repeat with `scope='capability', target='clinic.visit_summary'` and with `scope='installation', target='<I0>'`.

**Expect:** HTTP 503 `code: "capability_disabled"` (stage 3 `evaluateEntitlement` runs these keys first). Same D1 rows would also 503 in stage 5 `evaluateCapabilityKillSwitches` if stage 3 were skipped — on this Worker the live observation is stage 3. `Access.killSwitchFlag` on the bundled manifest is `false` (unprobeable without a rebuild).

**Stage 3 `forbidden_capability` (grants).** **Do:** `d1 "UPDATE entitlement SET allowed_capabilities = '[]' WHERE installation_id = '<I0>'"`. Wait 31 s. `invoke`. Restore `["clinic.visit_summary"]` and wait 31 s.

**Expect:** HTTP 403 `code: "forbidden_capability"`. Pending-entitlement 403 was [§11.3.1](#1131-reset-to-a-known-platform-state).

**Stage 4.** **Do:** 121 `invoke`s in one minute with **fresh AATs** and distinct idempotency keys (actor binding `simple.limit = 120` / `period = 60` in `wrangler.toml`; installation 600, capability 300).

**Expect:** HTTP 429 `code: "rate_limited"` with `retry_after` equal to a positive binding hint or **60**. If local ratelimit bindings fall through to `allowAllRateLimit`, this row is unprobeable on that process.

**Stage 5 `capability_unknown`.** **Do:** keep `allowed_capabilities` including `clinic.visit_summary`. Point the installation grant at a version the registry does not have, then send that version (otherwise stage 3 `version_mismatch` 403s first):

```bash
d1 "UPDATE capability_grant SET capability_version = '9.9.9' WHERE scope = 'installation:<I0>' AND capability_id = 'clinic.visit_summary' AND revoked_at IS NULL"
```

Wait 31 s. `invoke` with `x-capability-version: 9.9.9`. Restore `capability_version = '1.0.0'` and wait 31 s.

**Expect:** HTTP 404 `code: "capability_unknown"` (`clinic.visit_summary@9.9.9` is not in the in-memory registry).

**Stage 5 `capability_retired`.** **Do:**

```bash
curl -sS -X POST "$GATEWAY/control/capabilities/clinic.visit_summary/versions/1.0.0/deprecate" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"successor_id":"clinic.visit_summary"}'
d1 "UPDATE capability_grant SET retire_after = '2020-01-01T00:00:00.000Z' WHERE scope = 'global' AND capability_id = 'clinic.visit_summary' AND lifecycle_state = 'deprecated'"
curl -sS -X POST "$GATEWAY/control/capabilities/clinic.visit_summary/versions/1.0.0/retire" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

Wait 31 s. `invoke`. Then delete those global overlay grant rows and wait 31 s so later probes resolve `active` again. (`OVERLAP_WINDOW_MS` is 90 days — the SQL backdate is the forcing action.)

**Expect:** deprecate 200; retire without backdate → 400 `overlap_window_active`; after backdate, retire 200; invoke HTTP 404 `code: "capability_retired"`.

**Stage 6 `context_required`.** **Do:** `$VISIT_BODY` without `visit.chief_complaint@v1`.

**Expect:** HTTP 422 `code: "context_required"` (`missing_keys` includes that key).

**Stage 6 `context_invalid`.** **Do:** send `context.org` / `context.branch` that do **not** match the AAT. Repeat omitting `context.org`.

**Expect:** HTTP 422 `code: "context_invalid"`.

**Stage 6 `conversation_budget_exhausted`.** **Do:** send `turn_ordinal` / `transcript` on this visit-summary invoke.

**Expect:** visit_summary `interactionMode` is `single_shot` — conversational options are **not** passed (`turn_ordinal` is ignored). The Worker registry has no conversational capability, so the 409 `conversation_budget_exhausted` cell is **unprobeable** here. Stage 6 has no live `internal_error` return from `validateContext` (the matrix HTTP 500 has no code path).

**Stage 7.** **Do:** keep required context; set `user_intent` to ~40_000 `'x'` characters (under 1 MiB). Estimator: `ceil((utf8(serialized) + promptScaffoldByteLength) / 4) * 1.15` vs `maxInputTokens` 8000 / `perRequestTokenCeiling` 9024.

**Expect:** HTTP 413 `code: "request_too_large"`.

**Stage 8 `unauthenticated` (exp).** **Do:** mint AAT; wait until `now > exp + 60` (`ADMISSION_CLOCK_SKEW_SECONDS`; issuer lifetime is minutes, max `exp − iat` 600 s). `invoke`.

**Expect:** HTTP 401 `code: "unauthenticated"` (stage 8 defensive recheck). JTI replay is [§11.3.5](#1135-jti-replay). `quota_exhausted` is [§11.3.3](#1133-zero-quotas-after-entitle). Grace-cap `rate_limited` is [§11.3.6](#1136-grace-admission-and-cron-reconciliation) (DO-down). Stage 8 `internal_error` is DO transport `client_error` or an unknown admission `outcome` — **unprobeable** on a healthy DO.

**Stage 9.** **Do:** visit-summary invoke that has already passed stage 8.

**Expect:** single-shot `createRequestRow` forces `conversation_id` / `turn_ordinal` NULL — stage 9 `context_invalid` (missing conversational grouping) is **unprobeable** on this Worker. Stage 9 `internal_error` is a D1 INSERT failure — **unprobeable** on healthy local D1.

**Stage 10.** **Do:** visit-summary invoke with bound prompt artifacts present.

**Expect:** compose succeeds. `composeRequest` `internal_error` (missing system instruction / rule fragment / omitted `requestReference`) is **unprobeable** without breaking the bundled registry. The post-accept preload miss in [§11.3.4](#1134-missing-routing-policy) is **not** this row — that is after SSE `accepted`.

**Provider kill switch (not pre-SSE).** **Do:** restore visit_summary. Publish/promote a policy whose chain is `deepseek` then `fake` (complete features).

```bash
d1 "INSERT INTO kill_switch (scope, target, active, changed_at, changed_by) VALUES ('provider', 'deepseek', 1, datetime('now'), 'verify')"
```

Wait 31 s. Fresh AAT. `invoke`. Inspect `routing_decision`. Then kill `fake` as well (or publish a one-target `deepseek`-only policy and keep `provider:deepseek` active).

**Expect:** HTTP 200 SSE `accepted` — **not** 503. `excluded[]` has `reason_code: "kill_switch"` for `deepseek`; `fake` still runs → `completed`. When every target is excluded, `failed` / `provider_unavailable`. `provider:fake` **does** 503 at stage 3 because preAccept hardcodes `providerId: "fake"` — that is not this claim; the claim is `provider:<id>` at stage 5 collection.

#### 11.3.10 Retention, counters, delete, and purge

**Retention / joinability.** **Do:** after at least one completed (or failed) job with a `usage_event` row, backdate the journal ticket beyond `JOURNAL_HORIZON_DAYS` (90):

```bash
d1 "UPDATE ai_request SET created_at = '2026-01-01T00:00:00.000Z', completed_at = '2026-01-01T00:00:00.000Z' WHERE request_id = '<rid>'"
curl -sS "$GATEWAY/cdn-cgi/handler/scheduled?cron=0+3+*+*+*"
d1 "SELECT request_id, tokens, cost FROM usage_event WHERE installation_id = '<I0>'"
d1 "SELECT request_id FROM ai_request WHERE request_id = '<rid>'"
d1 "SELECT request_id FROM ai_attempt WHERE request_id = '<rid>'"
```

**Expect:** `runRetentionPurge` runs only on cron `0 3 * * *`. `usage_event.request_id` is **NULL** (money row remains). `ai_request` / `ai_attempt` for that id are gone; R2 `request/<rid>/envelope` is gone. `runReconciliation` (`0 4 * * *`) is request-centric (`LEFT JOIN usage_event u ON u.request_id = r.request_id`) — a nulled `request_id` can never match, so coverage shrinks with age by design.

**Counters are a lower bound.** **Do:** cause a `quota_exhausted` ([§11.3.3](#1133-zero-quotas-after-entitle)). Immediately:

```bash
d1 "SELECT count, dimension_set, time_bucket FROM platform_counter"
```

Then `curl -sS "$GATEWAY/cdn-cgi/handler/scheduled?cron=*+*+*+*+*"` (any cron flushes this isolate) and select again.

**Expect:** before flush, D1 may have **no** new row — `recordGuardRejection` only increments the isolate-local map. After this isolate’s tick, `platform_counter` has `dimension_set` containing `"error_code":"quota_exhausted"` and `count` ≥ 1 (`ON CONFLICT … count = count + excluded.count`). `dashboardQuotaRejectionRate` SUMs those rows — a **lower bound**. Tallies in other isolates are lost on eviction (cannot force a second isolate to die here). There is no request-end D1 write of the tally — grep `flushRejectionCounters` shows only `scheduled()`.

**Delete.** Restore `request_quota` if you still need one last AAT. **Do:** `POST …/delete`. Wait 31 s. Fresh AAT. `invoke`.

**Expect:** HTTP 200. `installation.status=deleted`. Invoke HTTP 401 `unauthenticated` (`status !== "active"` and not the suspended branch). Repeat delete → 409 `illegal_lifecycle_transition`. Resume → 409 (not suspended).

**Purge.** **Do:** `d1 "DELETE FROM grace_admission_queue WHERE installation_id = '<I0>'"` (purge’s D1 batch does not delete that table). Then `POST …/purge`. Inspect D1 and R2.

**Expect:** HTTP 200. `installation`, `installation_key`, `entitlement`, `ai_request`, `ai_attempt`, `usage_event`, matching `platform_counter` / grants for this installation are gone. R2 envelopes under `request/{request_id}/envelope` are gone. Irreversible — re-enroll is a new control-plane enroll, not an undo.
