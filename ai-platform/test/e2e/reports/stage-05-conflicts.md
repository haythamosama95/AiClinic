# Stage 05 catalog-vs-code conflicts

## S05-050, S05-051, S05-052, S05-053, S05-054, S05-055, S05-056, S05-057, S05-058, S05-062

- **Catalog claim:** `POST /v1/requests` accept is HTTP 202 with `text/event-stream` and SSE `accepted` (Stage 10 accepted-request behavior; catalog Conventions and each invoke scenario).
- **Code behavior:** `openSseResponse` returns the SSE stream with `status: 200`. Harness `postRequest` reports `response.status` faithfully. Stream still opens with `sse_accepted` / SSE `accepted`. Tests follow code (200) and keep `text/event-stream` plus SSE `accepted`.
- **File:line:** `ai-platform/src/adapter.ts:573-580` (`new Response(stream, { status: 200, … "content-type": "text/event-stream" })`).

## S05-051, S05-052, S05-054-b, S05-058, S05-062

- **Catalog claim:** After HTTP accept, the invoke journey reaches SSE `completed` (and S05-054-b / S05-051 sibling serve the active/canary chain to completion).
- **Code behavior:** Routing resolves and `persistRoutingDecision` runs before provider invocation. Live DeepSeek/Gemini in this pool then fail (`provider_rejected`); the stream terminals `failed`. Stage 05 surface is `routing_decision` persistence (policy_version, rule_id, chain, excluded), not invocation success. Tests require SSE `accepted` plus D1 `routing_decision` matching catalog; they do not require SSE `completed`. (S05-050 / S05-053 / S05-054-a / S05-055 / S05-056 / S05-057 remain SSE `failed` / `data.code = "internal_error"` and D1 `Failed` / `internal_error` — routing never resolved.)
- **File:line:** `ai-platform/src/worker.ts:954-991` (`preloadRoutingPolicyForInstallation` + `selectCandidateChain` + `persistRoutingDecision`); `ai-platform/src/worker.ts:1104-1106` (`runInvocation` after persist); `ai-platform/src/provider/deepseek.ts` / `ai-platform/src/provider/gemini.ts` (`provider_rejected`); Register 5 #33 (no live provider stub in this pool).

## S05-059

- **Catalog claim:** After warming the installation cache on active v2, rollback v2 so D1 has v1 active; the next invoke within 30 s (`DEFAULT_CONFIG_CACHE_TTL_MS = 30_000`) still persists `routing_decision.policy_version: 2`. After TTL expiry / isolate cache clear, a third invoke serves `policy_version: 1`.
- **Code behavior:** E2E pool binds `CONFIG_CACHE_TTL_MS: "100"` (`vitest.e2e.config.ts`; README §6). TTL `"0"` is unsafe: `preloadRoutingPolicyForInstallation` `remember(now+0)` then `selectCandidateChain` `consult` throws `ConfigCacheMissError` in the same request. `postRequest` drains the SSE stream (~400 ms of guard + live-provider `provider_rejected`) so the warm v2 entry is already expired before rollback + the next invoke. Catalog’s “stale still v2” window is not observable without extending the harness. After rollback the next invoke reads D1 (v1); `clearConfigCache()` still yields v1. Aborting via documented `clinicFetch` `signal` cannot preserve the split: cache remember runs after guards, and the following invoke’s guards also exceed 100 ms before `consult`.
- **File:line:** `ai-platform/src/config-cache/index.ts:26-28` (`DEFAULT_CONFIG_CACHE_TTL_MS = 30_000`); `ai-platform/src/config-cache/index.ts:89-115` (`consult` expiry / `remember`); `ai-platform/vitest.e2e.config.ts:42` (`CONFIG_CACHE_TTL_MS: "100"`); `ai-platform/test/e2e/harness/clinic.ts:83-143` (`postRequest` SSE drain); `ai-platform/src/worker.ts:954-991` (preload remember before consult).

## S05-063, S05-064, S05-065, S05-066, S05-067, S05-068, S05-069, S05-070, S05-071, S05-072, S05-073, S05-074, S05-075, S05-076, S05-077, S05-079, S05-080, S05-081, S05-083

- **Catalog claim:** `POST /v1/requests` accept is HTTP 202 with `text/event-stream` and SSE `accepted` (Stage 10 accepted-request behavior; catalog Conventions and each invoke scenario).
- **Code behavior:** `openSseResponse` returns the SSE stream with `status: 200`. Harness `postRequest` reports `response.status` faithfully. Stream still opens with `sse_accepted` / SSE `accepted`. Tests follow code (200) and keep `text/event-stream` plus SSE `accepted`. Empty-chain journeys (S05-070, S05-071, S05-074) still require SSE `failed` / `provider_unavailable` (not `internal_error`) after that 200 accept.
- **File:line:** `ai-platform/src/adapter.ts:573-580` (`new Response(stream, { status: 200, … "content-type": "text/event-stream" })`); `ai-platform/src/invocation/index.ts:452-456` (empty chain → `provider_unavailable`); `ai-platform/src/worker.ts:1147-1211` (failed settlement + SSE `failed`).

## S05-063, S05-064, S05-065, S05-066, S05-067, S05-068, S05-069, S05-072, S05-073, S05-075, S05-076, S05-077, S05-079, S05-080, S05-081, S05-083

- **Catalog claim:** After HTTP accept, non-empty chains reach SSE `completed` (S05-069 failover to gemini; S05-083 fixture two-target chain; other filter journeys imply a completed invoke while inspecting `routing_decision`).
- **Code behavior:** Routing resolves and `persistRoutingDecision` runs before provider invocation. Live DeepSeek/Gemini in this pool then fail (`provider_rejected`); the stream terminals `failed`. Stage 05 surface is `routing_decision` (excluded reason_codes, chain ordinals, `effective_cost_class`, `rule_id`, `routing_tier`), not invocation success. Tests require SSE `accepted` plus D1 `routing_decision` matching catalog; they do not require SSE `completed`. Empty-chain IDs S05-070 / S05-071 / S05-074 are unchanged: SSE `failed` / `provider_unavailable`.
- **File:line:** `ai-platform/src/worker.ts:954-991` (`preloadRoutingPolicyForInstallation` + `selectCandidateChain` + `persistRoutingDecision`); `ai-platform/src/worker.ts:1104-1106` (`runInvocation` after persist); Register 5 #33 (no live provider stub in this pool).
