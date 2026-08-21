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
| Clinic keypair RPC     | `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` |
| AAT issuer RPC         | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql`              |
| AAT contract spec      | `specs/021-installation-keystore-aat-issuer/contracts/aat-token.md`               |


---

*This document was derived from runtime code in* `ai-platform/` *and clinic Supabase migrations. When code changes, update the corresponding stage section and column tables.*
