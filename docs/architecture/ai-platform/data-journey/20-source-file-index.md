# AI Platform Data Journey — Source File Index

---

| Area                   | Path                                                                              |
| ---------------------- | --------------------------------------------------------------------------------- |
| Worker entry           | `ai-platform/src/worker.ts`                                                       |
| Ingress adapter        | `ai-platform/src/adapter.ts` (`preAcceptFailureResponse` attaches `retry_after` on `rate_limited`; `ADAPTER_ROUTING_BODY_FIELDS = []` so `routing_tier` / `degraded` / `degraded_notice` are never read from the body) |
| Guard pipeline         | `ai-platform/src/pipeline/index.ts` (`GuardFailure.retryAfter` from stage 4 rate-limit and stage 8 grace-cap) |
| Cost preflight         | `ai-platform/src/context/preflight.ts` (`estimateInputTokens` includes `promptArtifactByteLength`) |
| Context validator      | `ai-platform/src/context/validator.ts` (permitted-key allowlist drops out-of-set keys from supplied context, `context_resolved`, and historical `context_requested`) |
| Prompt composer        | `ai-platform/src/prompt/composer.ts` (`promptScaffoldByteLength` for stage 7; `promptVersion` from registry; `leakNeedlesFromSystemInstruction` opening/interior/ending slices; `neutralizeText`/`neutralizeJson` on context, transcript turns, and the final `userIntent` part; `stopConditionsFromManifest` always `[]` under A4) |
| Prompt registry        | `ai-platform/src/prompt/registry.ts` (`resolvePromptVersion` = content hash of bound artifacts) |
| Identity / AAT         | `ai-platform/src/identity/index.ts`                                               |
| Entitlement            | `ai-platform/src/entitlement/index.ts`                                            |
| Admission              | `ai-platform/src/admission/index.ts` (grace-cap refusal is `rate_limited`, not `quota_exhausted`) |
| Soft-threshold helpers | `ai-platform/src/soft-threshold/index.ts` (`routingTierFromAdmission` / `degradedNoticeFromAdmission`; `CLIENT_ROUTING_INJECTION_KEYS` lists keys the adapter never reads because `ADAPTER_ROUTING_BODY_FIELDS = []`; no production body-scan helper) |
| Rate-limit + rejection counters | `ai-platform/src/rate-limit/index.ts` (prefers binding `retryAfter` hint, else 60s; `platform_counter` is a lower bound: isolate-local tally flushed only by the cron isolate) |
| Journal + R2           | `ai-platform/src/journal/index.ts` (`persistRoutingDecision` writes `ai_request.routing_decision` at Stage 10; `authenticateGetRequest` uses `isolateConfigCache`) |
| Rollup + reconciliation | `ai-platform/src/rollup/index.ts` (expected row profile: Completed/Failed need attempts+usage; Cancelled needs usage; AwaitingContext needs neither; aged `usage_event.request_id` NULLs cannot join) |
| Retention              | `ai-platform/src/retention/index.ts` (nulls `usage_event.request_id` then deletes aged `ai_request`; ledger keeps money, loses request joinability) |
| Dashboards             | `ai-platform/src/dashboards/index.ts` (`dashboardQuotaRejectionRate` SUMs `platform_counter` — lower bound; `dashboardRepairRateByCapability` = `outcome='repair'` attempts ÷ Completed+Failed requests by `capability_id` over the journal window) |
| Router                 | `ai-platform/src/router/index.ts` (`filterTargets` fail-closed: missing/unknown `min_context_window`, `cost_class`, or `languages` → `feature_unsupported`; languages is `Array.isArray`-guarded) |
| Invocation             | `ai-platform/src/invocation/index.ts`                                             |
| Post-response pricing  | `ai-platform/src/pricing/index.ts` (`control/pricing/platform-default/1.json`)    |
| Production sleeper     | `ai-platform/src/wall-clock-sleeper.ts`                                           |
| Stream broker          | `ai-platform/src/stream/index.ts`                                                 |
| Prose guards           | `ai-platform/src/stream/prose-guards.ts` (length, stop, leak needles (opening/interior/ending), refusal prefixes, injection-echo needle → `validation_failed`) |
| Canonical types        | `ai-platform/src/contracts/canonical.ts`                                          |
| Providers              | `ai-platform/src/provider/deepseek.ts`, `gemini.ts`, `fake.ts`                    |
| Provider raw-body capture | `ai-platform/src/provider/raw-body.ts` (16 KB cap for envelope `attempts[]`)   |
| Provider HTTP transport | `ai-platform/src/provider/fetch-transport.ts` (`createFetchTransport` — passes `Response.body` through as a stream) |
| Provider SSE reader    | `ai-platform/src/provider/readable-body.ts` (incremental `data:` payloads)        |
| Quota DO               | `ai-platform/src/quota-do/index.ts`                                               |
| Config cache           | `ai-platform/src/config-cache/index.ts` (`isolateConfigCache` — one instance per Worker isolate, 30 s TTL; tests inject `new ConfigCache()`) |
| Control enroll         | `ai-platform/src/control/lifecycle.ts`                                            |
| Control auth           | `ai-platform/src/control/auth.ts` (`createSecretOperatorAuth`: one shared bearer → one `OPERATOR_ID`; `control_audit` cannot distinguish operators) |
| Control entitle        | `ai-platform/src/control/entitle.ts` (`period_start`/`period_end`: ISO-8601 UTC instants, `start < end`) |
| Routing policy         | `ai-platform/src/control/routing-policy.ts` (duplicate publish: D1 existence check before R2.put) |
| Token contract         | `ai-platform/src/control/token-contract.ts`                                       |
| Errors taxonomy        | `ai-platform/src/errors.ts` (`retryAfterSecondsForRateLimited`: hint else 60) |
| Wrangler config        | `ai-platform/wrangler.toml`                                                       |
| D1 migrations          | `ai-platform/migrations/*.sql` (`idx_entitlement_installation_id` UNIQUE on `entitlement.installation_id`) |
| Visit summary manifest | `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`                 |
| Clinic keypair RPC | `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` |
| AAT issuer RPC | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql` |
| Context provider RPC | `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql` |
| Acceptance recording RPC | `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql` |
| AI availability read RPC | `backend/supabase/migrations/20260802140000_ai_availability_flag.sql` |
| AAT contract spec | `specs/021-installation-keystore-aat-issuer/contracts/aat-token.md` |
| Discovery HTTP | `ai-platform/src/discovery/index.ts` |


---

*This document was derived from runtime code in* `ai-platform/` *and clinic Supabase migrations. When code changes, update the corresponding stage section and column tables.*

## Table of Contents

1. [Behavioral verification](#1-behavioral-verification)
   - [1.1 Setup](#11-setup)
   - [1.2 Coverage](#12-coverage)
   - [1.3 Ordered probes](#13-ordered-probes)
     - [1.3.1 Paths, Worker boot, and HTTP route probe index](#131-paths-worker-boot-and-http-route-probe-index)
     - [1.3.2 Clinic RPCs (all seven public surfaces)](#132-clinic-rpcs-all-seven-public-surfaces)
     - [1.3.3 Control auth, enroll, entitle, uniqueness, token contract](#133-control-auth-enroll-entitle-uniqueness-token-contract)
     - [1.3.4 Duplicate routing publish checks D1 first](#134-duplicate-routing-publish-checks-d1-first)
     - [1.3.5 Identity, entitlement, discovery, and Quota DO](#135-identity-entitlement-discovery-and-quota-do)
     - [1.3.6 Adapter ignores routing injection](#136-adapter-ignores-routing-injection)
     - [1.3.7 Rate-limit retry_after and stage 4](#137-rate-limit-retry_after-and-stage-4)
     - [1.3.8 Grace-cap is rate_limited](#138-grace-cap-is-rate_limited)
     - [1.3.9 Context allowlist drops out-of-set keys](#139-context-allowlist-drops-out-of-set-keys)
     - [1.3.10 Cost preflight includes prompt artifacts](#1310-cost-preflight-includes-prompt-artifacts)
     - [1.3.11 Prompt compose: neutralize, version, leaks, empty stops](#1311-prompt-compose-neutralize-version-leaks-empty-stops)
     - [1.3.12 Journal routing_decision and GET cache](#1312-journal-routing_decision-and-get-cache)
     - [1.3.13 Config cache 30 s isolate singleton](#1313-config-cache-30-s-isolate-singleton)
     - [1.3.14 Router fail-closed feature_unsupported](#1314-router-fail-closed-feature_unsupported)
     - [1.3.15 Invoke, stream, providers, sleeper, transports](#1315-invoke-stream-providers-sleeper-transports)
     - [1.3.16 Prose guards emit validation_failed](#1316-prose-guards-emit-validation_failed)
     - [1.3.17 Envelope raw-body 16 KB cap](#1317-envelope-raw-body-16-kb-cap)
     - [1.3.18 Post-response pricing table](#1318-post-response-pricing-table)
     - [1.3.19 platform_counter lower bound and dashboards](#1319-platform_counter-lower-bound-and-dashboards)
     - [1.3.20 Retention then rollup joinability](#1320-retention-then-rollup-joinability)
     - [1.3.21 Canonical envelope shape](#1321-canonical-envelope-shape)

---

## 1. Behavioral verification

Live probes of the parenthetical claims in the index table — not a “file exists” checklist (the path check in [§1.3.1](#131-paths-worker-boot-and-http-route-probe-index) is only the first Do). Each probe is an operator action against a throwaway local Worker and clinic, and the outcome you should see. Run **[§1.3](#13-ordered-probes) top to bottom**. If every probe matches, the indexed modules are behaving as claimed.

There is no dashboard HTTP route and no first-class Wrangler dump of Quota DO storage. Those claims are probed with `wrangler d1` / `wrangler r2` / scheduled triggers, not invented endpoints.

### 1.1 Setup

- Local clinic Supabase with migrations applied (keypair + AAT issuer RPCs). Prefer a database you can wipe.
- Local Worker: `cd ai-platform && npm run dev` (`wrangler.toml` `[dev]` → `http://127.0.0.1:8787`). For cron probes, restart with `--test-scheduled` added to that `wrangler dev` command.
- `OPERATOR_BEARER_TOKEN` matching the Worker secret; `OPERATOR_ID` is `platform-operator` in `[env.development.vars]`.
- One enrolled installation (clinic `enroll_installation_keypair` → `POST /control/installations/{id}/enroll` → `POST …/entitle` with the visit-summary payload in Stage 4 §6). Save `installation_id` as **I0**.
- Staff session that can `issue_ai_token`. Decode the AAT: payload `iss` = **I0**, `aud` = `ai-platform`, `alg` = `EdDSA`. Visit summary `Access.allowedStaffRoles` is `clinician` / `nurse` — a `doctor` token is a useful entitlement miss.
- D1/R2 inspect as:

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export AAT='…'   # compact JWS from issue_ai_token
export INSTALLATION_ID='<I0>'
cd ai-platform
```

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "<SQL>"
npx wrangler r2 object get ai-platform-development \
  "request/<request_id>/envelope" --file /tmp/envelope.json --local
```

Shared invoke (fresh `x-idempotency-key` every new job):

```bash
curl -sN -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(uuidgen)" \
  -H "x-capability-version: 1.0.0" \
  -d '{
    "capability_id": "clinic.visit_summary",
    "user_intent": "Summarize today'\''s visit for the chart.",
    "context": {
      "org": "<AAT org>",
      "branch": "<AAT branch>",
      "visit.chief_complaint@v1": "Patient reports headache for 3 days."
    }
  }'
```

Pre-accept failures are HTTP JSON (`code`, `request_reference`, `trace_id`). After accept, the body is SSE.

### 1.2 Coverage

Every index row and parenthetical claim maps to a probe. Carry them all out.


| Area / claim | Probe |
| ------------ | ----- |
| Worker entry (`worker.ts` routes + scheduled) | [§1.3.1](#131-paths-worker-boot-and-http-route-probe-index) |
| Ingress: `preAcceptFailureResponse` attaches `retry_after` on `rate_limited` | [§1.3.7](#137-rate-limit-retry_after-and-stage-4) |
| Ingress: `ADAPTER_ROUTING_BODY_FIELDS = []` — never reads `routing_tier` / `degraded` / `degraded_notice` from the body | [§1.3.6](#136-adapter-ignores-routing-injection) |
| Guard: `GuardFailure.retryAfter` from stage 4 rate-limit | [§1.3.7](#137-rate-limit-retry_after-and-stage-4) |
| Guard: `GuardFailure.retryAfter` from stage 8 grace-cap | [§1.3.8](#138-grace-cap-is-rate_limited) |
| Cost preflight: `estimateInputTokens` includes `promptArtifactByteLength` | [§1.3.10](#1310-cost-preflight-includes-prompt-artifacts) |
| Context validator: allowlist drops out-of-set keys from supplied context | [§1.3.9](#139-context-allowlist-drops-out-of-set-keys) |
| Context validator: same drop on `context_resolved` / historical `context_requested` | [§1.3.9](#139-context-allowlist-drops-out-of-set-keys) (conversational; see unprobeable note) |
| Composer: `promptScaffoldByteLength` for stage 7 | [§1.3.10](#1310-cost-preflight-includes-prompt-artifacts) |
| Composer: `promptVersion` from registry | [§1.3.11](#1311-prompt-compose-neutralize-version-leaks-empty-stops) |
| Composer: `leakNeedlesFromSystemInstruction` opening / interior / ending slices | [§1.3.11](#1311-prompt-compose-neutralize-version-leaks-empty-stops), [§1.3.16](#1316-prose-guards-emit-validation_failed) |
| Composer: `neutralizeText` / `neutralizeJson` on context, transcript turns, `userIntent` | [§1.3.11](#1311-prompt-compose-neutralize-version-leaks-empty-stops) |
| Composer: `stopConditionsFromManifest` always `[]` under A4 | [§1.3.11](#1311-prompt-compose-neutralize-version-leaks-empty-stops) |
| Registry: `resolvePromptVersion` = content hash of bound artifacts | [§1.3.11](#1311-prompt-compose-neutralize-version-leaks-empty-stops) |
| Identity / AAT | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces), [§1.3.5](#135-identity-entitlement-discovery-and-quota-do) |
| Entitlement | [§1.3.5](#135-identity-entitlement-discovery-and-quota-do) |
| Admission: grace-cap refusal is `rate_limited`, not `quota_exhausted` | [§1.3.8](#138-grace-cap-is-rate_limited) |
| Soft-threshold: `routingTierFromAdmission` / `degradedNoticeFromAdmission` | [§1.3.6](#136-adapter-ignores-routing-injection) |
| Soft-threshold: `CLIENT_ROUTING_INJECTION_KEYS` never read; no production body-scan helper | [§1.3.6](#136-adapter-ignores-routing-injection) |
| Rate-limit: prefers binding `retryAfter` hint, else 60s | [§1.3.7](#137-rate-limit-retry_after-and-stage-4) |
| Rate-limit: `platform_counter` is a lower bound (cron-isolate flush only) | [§1.3.19](#1319-platform_counter-lower-bound-and-dashboards) |
| Journal: `persistRoutingDecision` writes `ai_request.routing_decision` at Stage 10 | [§1.3.12](#1312-journal-routing_decision-and-get-cache) |
| Journal: `authenticateGetRequest` uses `isolateConfigCache` | [§1.3.12](#1312-journal-routing_decision-and-get-cache), [§1.3.13](#1313-config-cache-30-s-isolate-singleton) |
| Rollup: Completed/Failed need attempts+usage; Cancelled needs usage; AwaitingContext needs neither | [§1.3.20](#1320-retention-then-rollup-joinability) |
| Rollup: aged `usage_event.request_id` NULLs cannot join | [§1.3.20](#1320-retention-then-rollup-joinability) |
| Retention: nulls `usage_event.request_id` then deletes aged `ai_request`; ledger keeps money | [§1.3.20](#1320-retention-then-rollup-joinability) |
| Dashboards: `dashboardQuotaRejectionRate` SUMs `platform_counter` (lower bound) | [§1.3.19](#1319-platform_counter-lower-bound-and-dashboards) |
| Dashboards: `dashboardRepairRateByCapability` = `outcome='repair'` ÷ Completed+Failed by `capability_id` over the journal window | [§1.3.19](#1319-platform_counter-lower-bound-and-dashboards) |
| Router: `filterTargets` fail-closed missing/unknown `min_context_window`, `cost_class`, or `languages` → `feature_unsupported`; languages `Array.isArray`-guarded | [§1.3.14](#1314-router-fail-closed-feature_unsupported) |
| Invocation | [§1.3.15](#1315-invoke-stream-providers-sleeper-transports) |
| Post-response pricing: `control/pricing/platform-default/1.json` | [§1.3.18](#1318-post-response-pricing-table) |
| Production sleeper | [§1.3.15](#1315-invoke-stream-providers-sleeper-transports) |
| Stream broker | [§1.3.15](#1315-invoke-stream-providers-sleeper-transports) |
| Prose guards → `validation_failed` | [§1.3.16](#1316-prose-guards-emit-validation_failed) |
| Canonical types | [§1.3.21](#1321-canonical-envelope-shape) |
| Providers (`deepseek`, `gemini`, `fake`) | [§1.3.15](#1315-invoke-stream-providers-sleeper-transports) |
| Provider raw-body: 16 KB cap for envelope `attempts[]` | [§1.3.17](#1317-envelope-raw-body-16-kb-cap) |
| Fetch transport: `Response.body` passed through as a stream | [§1.3.15](#1315-invoke-stream-providers-sleeper-transports) |
| Provider SSE reader: incremental `data:` payloads | [§1.3.15](#1315-invoke-stream-providers-sleeper-transports) |
| Quota DO | [§1.3.5](#135-identity-entitlement-discovery-and-quota-do), [§1.3.6](#136-adapter-ignores-routing-injection) |
| Config cache: `isolateConfigCache` — one instance per isolate, 30 s TTL | [§1.3.13](#1313-config-cache-30-s-isolate-singleton) |
| Config cache: tests inject `new ConfigCache()` | Unprobeable live (test-only); production singleton is [§1.3.13](#1313-config-cache-30-s-isolate-singleton) |
| Control enroll | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| Control auth: one shared bearer → one `OPERATOR_ID`; `control_audit` cannot distinguish operators | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| Control entitle: `period_start` / `period_end` ISO-8601 UTC instants, `start < end` | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| Routing policy: duplicate publish D1 existence check before `R2.put` | [§1.3.4](#134-duplicate-routing-publish-checks-d1-first) |
| Token contract | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| Errors: `retryAfterSecondsForRateLimited` — hint else 60 | [§1.3.7](#137-rate-limit-retry_after-and-stage-4) |
| Wrangler config | [§1.3.1](#131-paths-worker-boot-and-http-route-probe-index), [§1.3.7](#137-rate-limit-retry_after-and-stage-4) |
| D1: `idx_entitlement_installation_id` UNIQUE on `entitlement.installation_id` | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| Visit summary manifest | [§1.3.1](#131-paths-worker-boot-and-http-route-probe-index), [§1.3.5](#135-identity-entitlement-discovery-and-quota-do) |
| Clinic keypair RPC | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) |
| AAT issuer RPC | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) |
| AAT contract spec | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) |
| Context provider RPC | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) |
| Acceptance recording RPC | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) |
| AI availability RPC | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) |
| Worker HTTP routes (probe index) | [§1.3.1](#131-paths-worker-boot-and-http-route-probe-index) |
| Discovery HTTP (`GET /v1/capabilities`, 304) | [§1.3.1](#131-paths-worker-boot-and-http-route-probe-index), [§1.3.5](#135-identity-entitlement-discovery-and-quota-do) |


**Unprobeable live on the default local stack** (still have a coverage pointer):

- Tests constructing `new ConfigCache()` — no production HTTP surface.
- Conversational `context_resolved` / historical `context_requested` allowlist, and `neutralizeText` on transcript turns — the published catalog is single-shot `clinic.visit_summary`. Supplied-context drop and `userIntent` / context JSON neutralization are still live.
- Multi-isolate lost `platform_counter` tallies — local Wrangler is one isolate. Cron-only flush is still live.
- Grace-cap **HTTP** `rate_limited` — needs Quota DO `fetch` throw/5xx. The D1 `COUNT(*) < 5` cap is still live SQL.
- Incremental provider SSE, `Response.body` streaming, wall-clock retry sleep, and prose-guard trips — need a live provider that streams / 429s / echoes. Missing `DEEPSEEK_API_KEY` is terminal `provider_rejected` before any wire body.

### 1.3 Ordered probes

#### 1.3.1 Paths, Worker boot, and HTTP route probe index

**Do:** from the repo root, confirm every index path exists:

```bash
for p in \
  ai-platform/src/worker.ts \
  ai-platform/src/adapter.ts \
  ai-platform/src/pipeline/index.ts \
  ai-platform/src/context/preflight.ts \
  ai-platform/src/context/validator.ts \
  ai-platform/src/prompt/composer.ts \
  ai-platform/src/prompt/registry.ts \
  ai-platform/src/identity/index.ts \
  ai-platform/src/entitlement/index.ts \
  ai-platform/src/admission/index.ts \
  ai-platform/src/soft-threshold/index.ts \
  ai-platform/src/rate-limit/index.ts \
  ai-platform/src/journal/index.ts \
  ai-platform/src/rollup/index.ts \
  ai-platform/src/retention/index.ts \
  ai-platform/src/dashboards/index.ts \
  ai-platform/src/router/index.ts \
  ai-platform/src/invocation/index.ts \
  ai-platform/src/pricing/index.ts \
  ai-platform/src/wall-clock-sleeper.ts \
  ai-platform/src/stream/index.ts \
  ai-platform/src/stream/prose-guards.ts \
  ai-platform/src/contracts/canonical.ts \
  ai-platform/src/provider/deepseek.ts \
  ai-platform/src/provider/gemini.ts \
  ai-platform/src/provider/fake.ts \
  ai-platform/src/provider/raw-body.ts \
  ai-platform/src/provider/fetch-transport.ts \
  ai-platform/src/provider/readable-body.ts \
  ai-platform/src/quota-do/index.ts \
  ai-platform/src/config-cache/index.ts \
  ai-platform/src/control/lifecycle.ts \
  ai-platform/src/control/auth.ts \
  ai-platform/src/control/entitle.ts \
  ai-platform/src/control/routing-policy.ts \
  ai-platform/src/control/token-contract.ts \
  ai-platform/src/errors.ts \
  ai-platform/wrangler.toml \
  ai-platform/manifests/published/clinic.visit_summary@1.0.0.json \
  ai-platform/src/discovery/index.ts \
  backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql \
  backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql \
  backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql \
  backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql \
  specs/021-installation-keystore-aat-issuer/contracts/aat-token.md
 do test -f "$p" || echo "MISSING $p"; done
ls ai-platform/migrations/*.sql >/dev/null
```

**Expect:** no `MISSING` lines. `ai-platform/migrations/` contains `20260821130000_entitlement_installation_unique.sql`.

**Do:** `curl -s "$GATEWAY/health"`

**Expect:** JSON `{ "build": "local", "environment": "development" }` from `wrangler.toml` `[env.development.vars]`. `GET /v1/no-such-route` → `404 Not Found`. `POST /v1/requests` without headers → adapter `422` (not a taxonomy JSON).

**HTTP route probe index** — live Worker routes exercised across this index and the stage docs:


| Route | Method | Auth | Probe in this file / stage |
| ----- | ------ | ---- | -------------------------- |
| `/health` | GET | none | [§1.3.1](#131-paths-worker-boot-and-http-route-probe-index) (above) |
| `/v1/capabilities` | GET | Bearer AAT | [§1.3.5](#135-identity-entitlement-discovery-and-quota-do); [Stage 7 §6.3.5](09-stage-7-discovery.md#635-entitled-happy-path-every-response-field) |
| `/v1/capabilities` | GET + `If-None-Match` | Bearer AAT | [§1.3.5](#135-identity-entitlement-discovery-and-quota-do) (304); [Stage 7 §6.3.6](09-stage-7-discovery.md#636-conditional-get-304-not-modified) |
| `/v1/requests` | POST | Bearer AAT + idempotency headers | [§1.3.5](#135-identity-entitlement-discovery-and-quota-do), [§1.3.15](#1315-invoke-stream-providers-sleeper-transports) |
| `/v1/requests/{ref}` | GET | Bearer AAT | [§1.3.12](#1312-journal-routing_decision-and-get-cache); [Stage 12 §5.3.2](14-stage-12-lookup-and-support.md#532-get-happy-path-every-field) |
| `/control/installations/{id}/enroll` | POST | operator bearer | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| `/control/installations/{id}/entitle` | POST | operator bearer | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| `/control/installations/{id}/rotate` | POST | operator bearer | [Stage 3 §7](05-stage-3-platform-installation-enrollment.md#7-api-post-controlinstallationsinstallation_idrotate) |
| `/control/installations/{id}/revoke-key` | POST | operator bearer | [Stage 3 §7.1](05-stage-3-platform-installation-enrollment.md#71-api-post-controlinstallationsinstallation_idrevoke-key) |
| `/control/installations/{id}/suspend` | POST | operator bearer | [§1.3.5](#135-identity-entitlement-discovery-and-quota-do); [Stage 3 §7.2](05-stage-3-platform-installation-enrollment.md#72-api-post-controlinstallationsinstallation_idsuspend) |
| `/control/installations/{id}/resume` | POST | operator bearer | [§1.3.5](#135-identity-entitlement-discovery-and-quota-do); [Stage 3 §7.3](05-stage-3-platform-installation-enrollment.md#73-api-post-controlinstallationsinstallation_idresume) |
| `/control/installations/{id}/delete` | POST | operator bearer | [Stage 3 §7.4](05-stage-3-platform-installation-enrollment.md#74-api-post-controlinstallationsinstallation_iddelete) |
| `/control/installations/{id}/purge` | POST | operator bearer | [Stage 3 §7.5](05-stage-3-platform-installation-enrollment.md#75-api-post-controlinstallationsinstallation_idpurge) |
| `/control/capabilities/{id}/versions/{v}/activate` | POST | operator bearer | [Stage 4 §7](06-stage-4-entitlement-and-capability-grants.md#7-api-post-controlcapabilitiescapability_idversionsversionactivate) |
| `/control/capabilities/{id}/versions/{v}/promote` | POST | operator bearer | [Stage 4 §8](06-stage-4-entitlement-and-capability-grants.md#8-api-post-controlcapabilitiescapability_idversionsversionpromote) |
| `/control/capabilities/{id}/versions/{v}/deprecate` | POST | operator bearer | [Stage 4 §9](06-stage-4-entitlement-and-capability-grants.md#9-api-post-controlcapabilitiescapability_idversionsversiondeprecate) |
| `/control/capabilities/{id}/versions/{v}/retire` | POST | operator bearer | [Stage 4 §10](06-stage-4-entitlement-and-capability-grants.md#10-api-post-controlcapabilitiescapability_idversionsversionretire) |
| `/control/routing-policies/publish` | POST | operator bearer | [§1.3.4](#134-duplicate-routing-publish-checks-d1-first) |
| `/control/routing-policies/{id}/versions/{v}/promote` | POST | operator bearer | [§1.3.4](#134-duplicate-routing-publish-checks-d1-first) |
| `/control/routing-policies/{id}/versions/{v}/canary` | POST | operator bearer | [Stage 5 §6.2](07-stage-5-routing-policy.md#62-api-post-controlrouting-policiespolicy_idversionsversioncanary) |
| `/control/routing-policies/{id}/versions/{v}/rollback` | POST | operator bearer | [Stage 5 §6.4](07-stage-5-routing-policy.md#64-api-post-controlrouting-policiespolicy_idversionsversionrollback) |
| `/control/support/lookup` | POST | operator bearer | [§1.3.12](#1312-journal-routing_decision-and-get-cache) (GET poll); [Stage 12 §5.3.3](14-stage-12-lookup-and-support.md#533-support-lookup-happy-path-every-field) |
| `/control/token-contract/begin-rotation` | POST | operator bearer | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| `/control/token-contract/retire` | POST | operator bearer | [§1.3.3](#133-control-auth-enroll-entitle-uniqueness-token-contract) |
| `/cdn-cgi/handler/scheduled` | GET | dev `--test-scheduled` only | [§1.3.19](#1319-platform_counter-lower-bound-and-dashboards), [§1.3.20](#1320-retention-then-rollup-joinability) |

No dashboard HTTP route exists (`src/dashboards/index.ts` is SQL-only). Quota DO state has no Wrangler dump — admit/idempotency is probed via [§1.3.5](#135-identity-entitlement-discovery-and-quota-do).

**Do:** `grep -n 'crons\|RATE_LIMITER_INSTALLATION_ACTOR' ai-platform/wrangler.toml`

**Expect:** crons `0 3 * * *` and `0 4 * * *`; development actor limiter `simple = { limit = 120, period = 60 }`. Those are the numbers [§1.3.7](#137-rate-limit-retry_after-and-stage-4) and [§1.3.20](#1320-retention-then-rollup-joinability) burn.

**Do:** `jq -r '.Identity.capabilityId, .Identity.version, .Routing.routingPolicyRef, .Economics.maxInputTokens, ."Context requirements"[0].key' ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`

**Expect:** `clinic.visit_summary`, `1.0.0`, `routing/standard@v1`, `8000`, `visit.chief_complaint@v1`.

#### 1.3.2 Clinic RPCs (all seven public surfaces)

Every `public.*` clinic RPC granted to `authenticated` for the AI journey. Keystore and acceptance RPCs return `public.rpc_result` (`success`, `data`, `error_code`, `error_message`). `issue_ai_token` returns a compact JWS `text`. `get_ai_availability` returns plain `jsonb`.


| RPC | Returns | Role | Probe |
| --- | ------- | ---- | ----- |
| `public.enroll_installation_keypair()` | `rpc_result` | Owner/admin mints installation id + Ed25519 keypair | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) (below) |
| `public.rotate_installation_key()` | `rpc_result` | Owner/admin rotates clinic signing key (same `installation_id`) | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) (below); [Stage 15 §11.3.2](15-alternative-and-failure-journeys.md#1132-lifecycle-alternatives-control-plane) |
| `public.revoke_installation_key(p_kid text)` | `rpc_result` | Owner/admin revokes a `kid` in clinic keystore | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) (below) |
| `public.issue_ai_token(p_scopes text[] DEFAULT NULL)` | **text** (compact JWS) | Staff with `ai.*` mints an AAT | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) (below) |
| `public.get_ai_availability()` | **`jsonb`** (not `rpc_result`) | Any staff reads `{ enrolled, platform_base_url }` flag | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) (below); [Stage 2 §3.3](04-stage-2-clinic-keypair-enrollment.md#33-api-publicget_ai_availability) |
| `public.get_visit_chief_complaint(p_visit_id uuid)` | `rpc_result` | Visit clinical read → `visit.chief_complaint@v1` shape | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) (below); [Stage 8 §7.1](10-stage-8-request-ingress.md#71-api-publicget_visit_chief_complaint) |
| `public.record_ai_acceptance(p_request_reference, p_target_key, p_target_args)` | `rpc_result` | Human accept → delegated domain write + provenance | [§1.3.2](#132-clinic-rpcs-all-seven-public-surfaces) (below); [Stage 12 §3](14-stage-12-lookup-and-support.md#3-publicrecord_ai_acceptance) |


**Do:** as administrator, `SELECT public.enroll_installation_keypair();`

**Expect:** `success = true`. `data.installation_id` UUID text, `data.kid`, `data.public_jwk.kty = "OKP"`, `crv = "Ed25519"`, `x` non-empty. No `secret_key` in `data`.

**Do:** as administrator, `SELECT public.rotate_installation_key();`

**Expect:** `success = true`. New `data.kid` ≠ prior kid. **Same** `data.installation_id`. Two rows in `ai_internal.installation_keys` for that installation.

**Do:** as administrator, `SELECT public.revoke_installation_key('<kid>');` for a live kid when at least one other active key remains (or for any already-revoked kid).

**Expect:** `success = true`. `data.kid` and `data.revoked_at` set. Repeat on same kid → idempotent success with existing `revoked_at`. Revoking the sole remaining active key → `CANNOT_REVOKE_LAST_ACTIVE_KEY` (rotate first).

**Do:** as staff with `ai.*`, `SELECT public.issue_ai_token();` Decode the three JWS segments (base64url, no padding).

**Expect:** header exactly `alg = "EdDSA"` and `kid` matching a live keystore row. Payload has `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver` — no patient ids, no quota, no `routing_tier`. `aud` is `ai-platform`. `exp - iat` is minutes-scale (platform cap 600s). This is the issuer RPC plus the AAT contract spec (`specs/021-installation-keystore-aat-issuer/contracts/aat-token.md`).

**Do:** as any authenticated staff, `SELECT public.get_ai_availability();`

**Expect:** plain JSON object `{ "enrolled": boolean, "platform_base_url": string | null }` — not an `rpc_result` envelope. No write RPC exists — flag is manual or future Flutter.

**Do:** as clinician with visit clinical access, `SELECT public.get_visit_chief_complaint('<visit_id>'::uuid);`

**Expect:** `success = true`. `data.visit_id` echoed; optional `complaint` and `recorded_at`. Unknown visit → `NOT_FOUND`. Staff without clinical read → `FORBIDDEN`.

**Do:** with a valid Crockford request reference and `visits.edit_soap`, `SELECT public.record_ai_acceptance('<REF>', 'visit_clinical_notes', jsonb_build_object('p_visit_id', '<visit_id>', 'p_complaint', 'text'));`

**Expect:** `success = true` with `acceptance_id`, `table_name`, `record_id`, `audit_log_id` merged into `data`. Malformed ref → `INVALID_INPUT`. Unregistered target → `INVALID_INPUT`. Delegated domain failure → pass-through `error_code`. Duplicate ref → `INVALID_INPUT` before write.

**Do:** `POST /v1/requests` with `Authorization: Bearer <clinic session JWT>` (not the AAT).

**Expect:** `401` `unauthenticated`. Clinic session JWT is not substitutable for an AAT (`aud` bind).

#### 1.3.3 Control auth, enroll, entitle, uniqueness, token contract

**Do:** `POST $GATEWAY/control/installations/$INSTALLATION_ID/enroll` with no `Authorization`.

**Expect:** `401` `{ "error": "unauthorized" }`. Same for a wrong bearer.

**Do:** enroll with the real operator bearer (body: `org_id`, `display_name`, `region`, `plan`, `public_key` = clinic `public_jwk.x`, `algorithm` = `EdDSA`, `kid`). Then immediately `SELECT operator_id, action FROM control_audit ORDER BY recorded_at DESC LIMIT 5`. Repeat `POST …/enroll`. Then `POST /control/token-contract/begin-rotation` with `{ "ver": "verify-2" }` using the **same** bearer.

**Expect:** first enroll `200` `{ "platform_base_url": "http://127.0.0.1:8787" }`. Re-enroll `409` `already_enrolled`. Every audit row `operator_id = platform-operator` — enroll and token-contract rotation are indistinguishable as people. There is no per-operator token. This is `createSecretOperatorAuth`.

**Do:** as D1:

```sql
INSERT INTO entitlement (
  entitlement_id, installation_id, plan, period_start, period_end,
  request_quota, token_budget, cost_budget, allowed_capabilities,
  soft_threshold, status
)
SELECT 'dup-' || entitlement_id, installation_id, plan, period_start, period_end,
       request_quota, token_budget, cost_budget, allowed_capabilities,
       soft_threshold, status
FROM entitlement WHERE installation_id = '<I0>' LIMIT 1;
```

**Expect:** UNIQUE constraint on `idx_entitlement_installation_id`. Still one entitlement row for **I0**.

**Do:** `POST …/entitle` while still `pending`, with `period_start` / `period_end` as date-only `"2026-08-01"` (no `T…Z`). Retry with valid instants but `period_start` ≥ `period_end`. Retry with Stage 4 §6 payload (ISO-8601 UTC, `start < end`).

**Expect:** first two → `400` `{ "error": "invalid_payload" }`. Third → `200`. D1 `entitlement.status = active`, `period_start` / `period_end` stored as sent. Second entitle → `409` `not_pending`.

**Do:** `SELECT ver, retired_at, changed_by FROM token_contract ORDER BY added_at;`

**Expect:** seed `ver = 1` still live (`retired_at` NULL). `verify-2` present, `changed_by = platform-operator`. `POST /v1/requests` with the existing AAT (`ver = 1`) still passes identity. After `POST /control/token-contract/retire` `{ "ver": "1" }`, a newly minted `ver=1` token (or the old one) fails identity `unauthenticated`. Mint after begin-rotation only if the clinic issuer already emits `ver=2` — if the issuer still stamps `ver=1`, retiring `1` is the live “booklet edition” check. Restore `ver=1` before later probes (re-insert or do not retire on a throwaway you still need).

#### 1.3.4 Duplicate routing publish checks D1 first

**Do:** publish the checked-in fixture (document `policy_id` / `policy_version` must match the URL):

```bash
curl -s -X POST "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"document\": $(cat ai-platform/control/routing-policy/platform-default/1.json)}"
```

Save the R2 object:

```bash
npx wrangler r2 object get ai-platform-development \
  "control/routing-policy/standard/1.json" --file /tmp/policy-v1.json --local
cp /tmp/policy-v1.json /tmp/policy-v1.before.json
```

**Do:** POST the same publish again (optionally with a mutated `document.rules` so a blind `R2.put` would change bytes). Then `r2 object get` to `/tmp/policy-v1.after.json` and `cmp /tmp/policy-v1.before.json /tmp/policy-v1.after.json`. D1: `SELECT status FROM routing_policy WHERE policy_id = 'standard' AND version = '1';`

**Expect:** second POST `409` `{ "error": "already_published" }`. `cmp` silent (R2 bytes unchanged). D1 still one row. That is the D1 existence check **before** `R2.put` — a put-first implementation would rewrite the object.

**Do:** `POST …/canary` then `POST …/promote` for `standard@1` so invoke has an active chain.

**Expect:** `200`. Later routing probes see `policy_id = standard`.

#### 1.3.5 Identity, entitlement, discovery, and Quota DO

**Do:** `GET $GATEWAY/v1/capabilities` with a truncated/forged AAT.

**Expect:** `401` `unauthenticated`. Identity never reaches discovery.

**Do:** with a valid AAT whose `role` is **not** `clinician` or `nurse` (typically clinic `doctor`), `GET /v1/capabilities` then `POST /v1/requests` (visit summary).

**Expect:** discovery may list the grant; invoke returns `403` `forbidden_capability` (manifest `allowedStaffRoles`). Entitlement/access is not “any authenticated staff”.

**Do:** mint or use an AAT whose `role` is `clinician` or `nurse` and whose `scopes` include `ai.visit_summary`. `GET /v1/capabilities`. Then `POST /v1/requests` **omitting** `visit.chief_complaint@v1`.

**Expect:** discovery includes `clinic.visit_summary` `1.0.0`. Missing key → `422` `context_required` with `missing_keys` containing `visit.chief_complaint@v1`. Manifest required key is enforced.

**Do:** entitled `GET /v1/capabilities` — save `ETag` header, then:

```bash
curl -sS -D /tmp/cap-304-hdr -o /tmp/cap-304-body \
  -H "Authorization: Bearer $AAT" \
  -H "If-None-Match: <ETag from first response>" \
  "$GATEWAY/v1/capabilities"
wc -c /tmp/cap-304-body
```

**Expect:** HTTP **304**, empty body, same `ETag` and `Cache-Control: private, must-revalidate` (`buildDiscoveryResponse` in `src/discovery/index.ts` → `src/capability/index.ts`). See [Stage 7 §4.2](09-stage-7-discovery.md#42-conditional-get--http-304-not-modified).

**Do:** full POST from [§1.1](#11-setup). Then D1:

```sql
SELECT state, request_id, request_reference FROM ai_request
ORDER BY created_at DESC LIMIT 1;
```

**Expect:** a journal row. SSE starts with `accepted` (or pre-accept JSON if a guard stage failed). Quota DO admitted the request: a second POST with a **new** idempotency key is not stuck on `inFlight`. Same idempotency key while in-flight/terminal replays (no second provider charge). There is no Wrangler dump of DO `state`; this is the live admit/idempotency/credit loop.

**Do:** `POST /control/installations/$INSTALLATION_ID/suspend` then `POST /v1/requests` with a still-valid AAT. Then `POST …/resume`.

**Expect:** suspend → `403` `installation_suspended`. Resume restores identity.

#### 1.3.6 Adapter ignores routing injection

**Do:** POST the [§1.1](#11-setup) body **plus** `"routing_tier": "degraded", "degraded": true, "degraded_notice": true` at the top level (and again nested under `context` if you like). Watch SSE `accepted`. Then D1 `SELECT routing_tier, routing_decision FROM ai_request WHERE request_reference = '<ref>';`

**Expect:** while spend is under `soft_threshold`, SSE `accepted` does **not** set `degraded_notice: true`. `routing_tier` on the row / in `routing_decision` is `standard`, not the client string. Ingress parsed JSON but never consulted those keys (`ADAPTER_ROUTING_BODY_FIELDS = []`, `CLIENT_ROUTING_INJECTION_KEYS`). There is no production helper that scans the body for them — if there were, this injection would be an explicit reject rather than a silent ignore.

**Do:** entitle (or re-provision on a fresh install) with `soft_threshold` `0.01` and a tiny `request_quota`, then POST until the Quota DO crosses the fraction.

**Expect:** a later `accepted` event includes `degraded_notice: true`, and `routing_decision.routing_tier` is `degraded`. That flag came from `degradedNoticeFromAdmission` / `routingTierFromAdmission`, not from the body.

#### 1.3.7 Rate-limit retry_after and stage 4

**Do:** from one actor + capability, fire **121** `POST /v1/requests` inside 60s (development `RATE_LIMITER_INSTALLATION_ACTOR` limit 120 / period 60). Capture the first non-2xx JSON.

**Expect:** HTTP `429`, `"code": "rate_limited"`, and **`retry_after` present** (integer). That field is attached by `preAcceptFailureResponse` via `supplementaryFieldsForCode` — it is not SSE. `retry_after` is the binding’s positive `retryAfter` hint when `limit()` supplies one; otherwise **60** (`retryAfterSecondsForRateLimited` / `DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS`). On Wrangler’s simple limiter the value is typically 60. Guard stage 4 forwarded `GuardFailure.retryAfter`; quota was not consumed for this refusal.

**Do:** confirm the JSON is **not** `"code": "quota_exhausted"` and has no `period_reset`.

**Expect:** rate-limit and quota are distinct 429s. Wait for the window (or use a new actor) before later probes.

#### 1.3.8 Grace-cap is rate_limited

**Do:** D1, five pending grace rows (cap is `GRACE_ADMISSION_CAP = 5`), then a sixth insert using the same predicate the Worker uses:

```sql
-- five times with distinct idempotency_key values
INSERT INTO grace_admission_queue (
  grace_request_id, installation_id, idempotency_key, jti, request_reference,
  entitlement_json, queued_at, reconcile_attempts, status
) VALUES (
  '<uuid>', '<I0>', '<key-n>', 'probe-jti', 'AAAA-AAAA',
  '{}', datetime('now'), 0, 'pending'
);

INSERT INTO grace_admission_queue (
  grace_request_id, installation_id, idempotency_key, jti, request_reference,
  entitlement_json, queued_at, reconcile_attempts, status
)
SELECT '<uuid6>', '<I0>', 'key-6', 'probe-jti', 'AAAA-AAAB',
       '{}', datetime('now'), 0, 'pending'
WHERE (
  SELECT COUNT(*) FROM grace_admission_queue
  WHERE installation_id = '<I0>' AND status = 'pending'
) < 5;
```

**Expect:** sixth `SELECT … WHERE COUNT(*) < 5` inserts **0** rows. Still five pending. The cap lives in D1, not in isolate memory.

**Do:** contrast — on a **fresh** pending install (or after reset), entitle with `request_quota: 0` (valid periods, real grants), then `POST /v1/requests`.

**Expect:** `429` `"code": "quota_exhausted"` (budget is gone). This is **not** the grace cap.

**Do:** (only if you can make Quota DO `fetch` throw or return ≥500 — there is no control route for that.) Seed five pending rows for **I0**, then POST a sixth distinct job.

**Expect:** `429` `"code": "rate_limited"` with `retry_after: 60` (grace path hard-codes the 60s default). **Not** `quota_exhausted`. Guard stage 8 carried `retryAfter`. If the local DO stays healthy, this HTTP mapping is unprobeable; keep the SQL cap result.

Delete the probe grace rows before continuing.

#### 1.3.9 Context allowlist drops out-of-set keys

**Do:** POST visit summary with required keys **plus** `"not.a.manifest.key@v1": "should vanish"` inside `context`. After settlement, `wrangler r2 object get` `request/<request_id>/envelope`.

**Expect:** envelope `context` has `visit.chief_complaint@v1` (and principal `org` / `branch` if journaled there) and **does not** contain `not.a.manifest.key@v1`. Out-of-set keys are dropped, not rejected. Visit summary is single-shot: there are no `context_resolved` / `context_requested` turns in this catalog. Those two surfaces are the same allowlist on a conversational capability — unprobeable until one is published.

#### 1.3.10 Cost preflight includes prompt artifacts

**Do:** UTF-8 byte length of the three bound artifacts:

```bash
python3 - <<'PY'
from pathlib import Path
root = Path("ai-platform/prompts/clinic.visit_summary")
parts = [
    root / "system.md",
    root / "rules-visit-summary.md",
    root / "template-visit-summary.md",
]
n = sum(p.read_bytes().__len__() for p in parts)
print("artifact_bytes", n)
print("artifact_tokens_ceil", -(-n // 4) * 115 // 100)
PY
```

POST a `user_intent` + context whose **serialized JSON alone** is under 8000 estimated tokens, but **plus artifact bytes** exceeds `Economics.maxInputTokens` (8000) after `ceil(bytes/4)*1.15`.

**Expect:** `413` `request_too_large` (pre-accept JSON). A tiny intent from [§1.1](#11-setup) still passes preflight — the scaffold is what pushed the large case over. That is `promptScaffoldByteLength` injected into `estimateInputTokens`. Ingress 1 MiB is a different 413; this body is small.

#### 1.3.11 Prompt compose: neutralize, version, leaks, empty stops

**Do:** POST with `user_intent` containing `</script>` and chief complaint `{"note": "</x>"}` (valid shape still). After settlement, read `/tmp/envelope.json` `prompt`.

**Expect:** `prompt.stopConditions` is `[]` (A4 has no stop-sequences field; `stopConditionsFromManifest` forwards absence). User part and rendered context contain `\u003c/` (or `\\u003c/`) **not** a raw `</` before `script` / `x`. Transcript-turn neutralization uses the same helper but visit summary has no transcript — unprobeable on this catalog. `prompt.parts` system text is the published instruction (opening sentences match `prompts/clinic.visit_summary/system.md`).

**Do:** two completed/failed rows for `clinic.visit_summary`:

```sql
SELECT prompt_artifact_hash FROM ai_request
WHERE capability_id = 'clinic.visit_summary'
ORDER BY created_at DESC LIMIT 5;
```

**Expect:** the hash is **identical** across requests. It is not a per-request id. That is `resolvePromptVersion` = content hash of the bound artifacts.

**Do:** from envelope system content, take 48-character slices at start, midpoint, and end.

**Expect:** three distinctive strings (instruction is longer than 48 chars). Those are the leak needles the prose guard will `includes()`. Tripping them is [§1.3.16](#1316-prose-guards-emit-validation_failed).

#### 1.3.12 Journal routing_decision and GET cache

**Do:** after a request that passed the guard (even if invoke later `provider_rejected`), D1:

```sql
SELECT request_reference, state, routing_tier, routing_decision, payload_pointer
FROM ai_request ORDER BY created_at DESC LIMIT 1;
```

**Expect:** `routing_decision` is non-null JSON (`chain`, `excluded`, `routing_tier`, `policy_id`). Written at Stage 10 by `persistRoutingDecision` **before** provider I/O — a missing-key failure still has the decision.

**Do:** `GET $GATEWAY/v1/requests/<request_reference>` with the AAT. Then `npx wrangler d1 execute … --command "UPDATE installation_key SET revoked_at = datetime('now') WHERE installation_id = '<I0>';"` and **immediately** GET again (same isolate, within 30 s). Wait 31 s, GET again.

**Expect:** first GET authenticates (Completed returns envelope `result`; Failed returns `terminal_error_code`). Immediate GET after revoke still authenticates — `authenticateGetRequest` used `isolateConfigCache` (stale key row). After TTL, `401` `unauthenticated`. Restore `revoked_at = NULL` and wait 30 s (or restart the Worker) before continuing.

#### 1.3.13 Config cache 30 s isolate singleton

**Do:** `GET /v1/capabilities` (warms entitlements/grants). D1 `UPDATE entitlement SET allowed_capabilities = '[]' WHERE installation_id = '<I0>';` Immediately GET capabilities, then wait 31 s and GET again. Restore the JSON list after.

**Expect:** within 30 s, discovery still lists visit summary (POST pre-accept and GET share the **same** isolate instance). After 30 s, the grant list is empty / capability gone. Restarting `wrangler dev` drops the isolate map immediately (TTL is not a D1 table). Tests injecting `new ConfigCache()` cannot be shown over HTTP.

#### 1.3.14 Router fail-closed feature_unsupported

**Do:** publish `standard` version `2` whose single target sets `"languages": "en"` (a string), omits `min_context_window`, or sets `"cost_class": "not-a-class"`. `policy_id` / `policy_version` must match the URL. Canary **I0** (or promote), then POST visit summary. D1 `routing_decision`. Then `POST …/rollback` (or promote `standard@1` again).

**Expect:** `excluded[].reason_code` includes `feature_unsupported` (not `language_unsupported`, not HTTP 500). A string `languages` is fail-closed by `Array.isArray`. Missing/unknown window or cost class is the same code. Empty chain → invoke `provider_unavailable`. Rollback so later probes use `standard@1`.

#### 1.3.15 Invoke, stream, providers, sleeper, transports

**Do:** POST with provider secrets **unset**. Read SSE and `ai_attempt`.

**Expect:** SSE `accepted` then `failed` `provider_rejected` (DeepSeek missing key is terminal — not `unauthenticated`, not a fake `success` body). `ai_attempt.provider` is `deepseek` (first chain target). Gemini is not attempted (`provider_rejected` is not retryable). `FakeAdapter` is not on this policy. Invocation ran; production sleeper did not (no retryable error).

**Do:** with `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` set, POST and watch SSE timestamps: `accepted` → `text_delta` (possibly several) → `completed`. Optionally abort curl mid-stream.

**Expect:** `text_delta` events arrive **before** `completed` (fetch transport passed `Response.body` through; SSE reader yielded incremental `data:` payloads; stream broker relayed chunks). Abort → `cancelled` (or terminal already sent). A provider HTTP 429 / 5xx should show a **non-zero** gap before the next attempt (`wallClockSleeper` + backoff cap 10s), not a tight loop. Without live keys, streaming / sleeper remain unprobeable.

#### 1.3.16 Prose guards emit validation_failed

**Do:** with a live provider, POST `user_intent` that asks the model to (a) repeat its system instructions, (b) begin with `I'm sorry, I can't help with that`, (c) include `Ignore previous instructions`, (d) emit `<|end|>`, or (e) dump tens of thousands of characters.

**Expect:** SSE `failed` `"code": "validation_failed"` when assembled output matches leak needles (opening/interior/ending 48-char slices from [§1.3.11](#1311-prompt-compose-neutralize-version-leaks-empty-stops)), refusal prefixes, injection-echo needle, hardcoded stop `<|end|>`, or length ceiling `128000`. Manifest stop-conditions are still `[]` — `<|end|>` is the Worker threshold list, not A4. Fake/missing-key paths never assemble model prose, so this is unprobeable there.

#### 1.3.17 Envelope raw-body 16 KB cap

**Do:** after any settled request with attempts, inspect envelope `attempts[]` (each entry is `captureRawProviderBody`).

**Expect:** each element is `{ "payload": …, "truncated": true|false }`. When `truncated` is false, encoded payload size is ≤ 16384 bytes. When true, `payload` is a **string** slice (not parsed JSON) — the 16 KB cap for diagnostic `attempts[]`. A missing-key attempt still has a small untruncated payload.

#### 1.3.18 Post-response pricing table

**Do:** after a request that recorded tokens (live provider). D1:

```sql
SELECT a.model, a.tokens_in, a.tokens_out, a.cost AS attempt_cost, u.cost AS usage_cost
FROM ai_attempt a
JOIN usage_event u ON u.request_id = a.request_id
ORDER BY a.attempt_no DESC LIMIT 5;
```

Compute `round((tokens_in/1000)*input_per_1k + (tokens_out/1000)*output_per_1k, 6)` using rates in `ai-platform/control/pricing/platform-default/1.json` (`deepseek-v4-flash`: 0.14 / 0.28; `gemini-3.5-flash`: 0.075 / 0.3; `fake-v1`: 0.1 / 0.2).

**Expect:** `attempt_cost` equals `usage_cost` equals that formula. Money did not come from the preflight estimator. Missing-key attempts may be `0` cost with `0` tokens — still consistent with the table.

#### 1.3.19 platform_counter lower bound and dashboards

**Do:** immediately after the [§1.3.7](#137-rate-limit-retry_after-and-stage-4) burst (before any cron):

```sql
SELECT dimension_set, time_bucket, count FROM platform_counter
WHERE dimension_set LIKE '%rate_limited%' OR dimension_set LIKE '%quota_exhausted%';
```

Then fire Wrangler’s scheduled handler (dev must have `--test-scheduled`):

```bash
curl -s "http://127.0.0.1:8787/cdn-cgi/handler/scheduled?cron=0+4+*+*+*"
```

Re-run the SELECT. Then run the dashboard SQL (there is **no** `/control/dashboards` route):

```sql
-- dashboardQuotaRejectionRate (journal window = 90d)
SELECT
  CAST(
    (SELECT COALESCE(SUM(count), 0) FROM platform_counter
     WHERE dimension_set LIKE '%quota_exhausted%'
       AND time_bucket >= datetime('now', '-90 days')) AS REAL
  )
  / NULLIF((SELECT COUNT(*) FROM ai_request WHERE created_at >= datetime('now', '-90 days')), 0)
  AS quota_rejection_rate;

-- dashboardRepairRateByCapability
SELECT r.capability_id,
       CAST(SUM(CASE WHEN a.outcome = 'repair' THEN 1 ELSE 0 END) AS REAL)
         / COUNT(DISTINCT r.request_id) AS rate
FROM ai_request r
LEFT JOIN ai_attempt a ON a.request_id = r.request_id
WHERE r.state IN ('Completed', 'Failed')
  AND r.created_at >= datetime('now', '-90 days')
GROUP BY r.capability_id;
```

**Expect:** before cron, `platform_counter` may be **empty** even though you just received `rate_limited` HTTP — the tally is isolate-local until the **cron isolate** flushes. After scheduled, rows appear (`ON CONFLICT` adds counts). That is the lower bound: other isolates never flush; a crash before cron loses the map. Quota-rejection rate uses `SUM(platform_counter)` in the numerator — same lower bound. Repair rate is `outcome = 'repair'` attempts ÷ **Completed+Failed** requests by `capability_id` (Cancelled excluded). Visit summary `repairPolicy.allowed` is false, so the rate is `0` unless you insert a synthetic `repair` attempt.

#### 1.3.20 Retention then rollup joinability

**Do:** pick one completed/failed `request_id` **R** that has `ai_attempt` and `usage_event`. Backdate it past the journal horizon and run the 03:00 job:

```sql
UPDATE ai_request SET created_at = datetime('now', '-91 days'),
                      completed_at = datetime('now', '-91 days')
WHERE request_id = '<R>';
UPDATE usage_event SET recorded_at = datetime('now', '-91 days')
WHERE request_id = '<R>';
```

```bash
curl -s "http://127.0.0.1:8787/cdn-cgi/handler/scheduled?cron=0+3+*+*+*"
```

```sql
SELECT request_id FROM ai_request WHERE request_id = '<R>';
SELECT usage_event_id, request_id, tokens, cost FROM usage_event
WHERE usage_event_id IN (SELECT usage_event_id FROM usage_event LIMIT 20);
-- join that retention would break:
SELECT r.request_id FROM ai_request r
LEFT JOIN usage_event u ON u.request_id = r.request_id
WHERE r.request_id = '<R>';
```

Then fire `0 4 * * *` and read wrangler logs `usage_rollup_reconciliation`.

**Expect:** after 03:00, `ai_request` **R** is gone; `usage_event` for that spend **remains** with `request_id` **NULL** (ledger money kept, joinability lost). The LEFT JOIN cannot match. Reconciliation’s missing-usage query is `Completed`/`Failed`/`Cancelled` without a `usage_event.request_id`; Completed/Failed without `ai_attempt` are `missingAttemptRows`. `AwaitingContext` is not in those predicates (needs neither). Aged NULLs never appear as missing-usage for the deleted request — coverage shrinks with age by design. `GET /v1/requests/{ref}` and `POST /control/support/lookup` for that reference find nothing.

#### 1.3.21 Canonical envelope shape

**Do:** `jq 'keys, .prompt | keys' /tmp/envelope.json` (and `.prompt.parts[0] | keys`).

**Expect:** envelope keys `context`, `prompt`, `attempts`, `result`. Prompt keys are canonical (`parts`, `formatDirective`, `samplingConstraints`, `maxOutputTokens`, `stopConditions`, `toolDeclarations`, `stream`, `deadline`, `correlationIds`) — **not** provider-shaped `messages` / `top_p` / `frequency_penalty`. Part `role` is one of `system` / `user` / `assistant` / `data`.
