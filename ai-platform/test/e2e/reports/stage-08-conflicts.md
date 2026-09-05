# Stage 08 catalog-vs-code conflicts

## S08-034

- **Catalog claim:** With both `capability_id: "clinic.not_a_capability"` and alias `capability: "clinic.visit_summary"` present, HTTP 404 `capability_unknown` (`retry_safe: false`) because the primary key drives Stage 9 stage-5 manifest resolution and the alias is ignored. No SSE; no Quota DO admission.
- **Code behavior:** `extractCapabilityId` still prefers the string primary key (`clinic.not_a_capability`), so precedence holds. Guard stage 3 (`evaluateEntitlement`) then runs before stage 5 (`resolve`). The unknown id is not in `allowed_capabilities` / grants (`clinic.visit_summary` only) → `capability_not_granted` → HTTP 403 `forbidden_capability` (`retry_safe: false`). Registry miss (`capability_unknown` 404) is unreachable unless stage 3 passes. Same entitlement-before-registry order as Stage 00 S00-008.
- **File:line:** `ai-platform/src/worker.ts:259-264` (`capability_id` before `capability`); `ai-platform/src/pipeline/index.ts:359-398` (stage 3 then stage 5); `ai-platform/src/entitlement/index.ts:191-197` (`capability_not_granted` → `forbidden_capability`); `ai-platform/src/errors.ts:41-45` (HTTP 403, retryable `"No"`); `ai-platform/src/capability/index.ts:566-577` (`capability_unknown` only on stage-5 registry miss).

## S08-042

- **Catalog claim:** Non-empty unpublished `x-capability-version: not-a-published-version` is accepted by ingress and misses registry key `{capability_id}@{version}` (stage 5) → HTTP 404 `capability_unknown` (`retry_safe: false`). No SSE.
- **Code behavior:** Guard stage 3 (`evaluateEntitlement`) runs before stage 5. Grant lookup for `clinic.visit_summary@not-a-published-version` is `version_mismatch` → `capability_not_granted` → HTTP 403 `forbidden_capability` (`retry_safe: false`). Registry miss never runs. Same entitlement-before-registry order as Stage 00 S00-008 / S08-034.
- **File:line:** `ai-platform/src/pipeline/index.ts:359-398` (stage 3 then stage 5); `ai-platform/src/entitlement/index.ts:206-207` (`version_mismatch` → `capability_not_granted`); `ai-platform/src/entitlement/index.ts:65-79` (`forbidden_capability`); `ai-platform/src/errors.ts:41-45` (HTTP 403, retryable `"No"`).

## S08-043

- **Catalog claim:** Non-empty unknown `capability_id: clinic.not_a_capability` reaches the guard and misses the registry → HTTP 404 `capability_unknown` (`retry_safe: false`). Distinct from S08-029 missing/empty 500. No SSE.
- **Code behavior:** Stage 3 rejects because `allowed_capabilities` / grants are only `clinic.visit_summary` → `capability_not_granted` → HTTP 403 `forbidden_capability` (`retry_safe: false`). Stage 5 `capability_unknown` is unreachable unless stage 3 passes. Same order as S00-008 / S08-034 / S08-042.
- **File:line:** `ai-platform/src/pipeline/index.ts:359-398` (stage 3 then stage 5); `ai-platform/src/entitlement/index.ts:191-197` (`capability_not_granted`); `ai-platform/src/errors.ts:41-45` (HTTP 403, retryable `"No"`); `ai-platform/src/capability/index.ts:566-577` (`capability_unknown` only on stage-5 registry miss).

## S08-045

- **Catalog claim:** After quota 1 is consumed, the next POST is HTTP 429 `quota_exhausted` (`retry_safe: true`) with **no** `retry_after` and **no** `period_reset`, because `createProductionPreAccept` forwards only `retryAfter` and `supplementaryFieldsForCode("quota_exhausted")` omits an empty `periodReset`.
- **Code behavior:** No `retry_after` is correct (`supplementaryFieldsForCode` only adds it for `rate_limited`). Admission `quota_exhausted` **does** set `periodReset: body.period_end`; `createProductionPreAccept` forwards `guard.periodReset`; the adapter emits `period_reset` when that string is non-empty. Live body includes `period_reset: "2027-01-01T00:00:00.000Z"` (entitle `period_end`).
- **File:line:** `ai-platform/src/admission/index.ts:460-468` (`periodReset: body.period_end`); `ai-platform/src/worker.ts:1321-1323` (forwards `periodReset`); `ai-platform/src/adapter.ts:223-237` (`preAcceptFailureResponse` passes `periodReset`); `ai-platform/src/errors.ts:193-199` (emit `period_reset` when non-empty).

## S08-053

- **Catalog claim:** Idempotent replay SSE `completed` has `data.result.finalContent.text = "Prior request completed."` and `authoritative: true` (implied on the event data root in the Stage 08 orientation assertion).
- **Code behavior:** Canned text matches. `replayIdempotentTerminal` puts `authoritative: true` on `result.finalContent`, and `pushTerminalEvent` copies that object into `data.result` with `trace_id` only — `completed.data.authoritative` is absent.
- **File:line:** `ai-platform/src/worker.ts:801-806` (`finalContent: { text, authoritative: true }`); `ai-platform/src/adapter.ts:142-147` (`data: { result, trace_id }`).

## S08-057

- **Catalog claim:** `Request` constructed with an already-aborted `AbortSignal` still returns HTTP 200 SSE; `accepted` is enqueued unconditionally in `start()`, then the stream closes with no terminal (`abortedAtEntry` guard). Register 5 #38: implement steady-state, do not skip.
- **Code behavior:** Adapter would honor `request.signal.aborted` at stream start (`abortedAtEntry` / close without terminal). workerd throws `AbortError: The operation was aborted` while constructing `new Request(..., { signal: AbortSignal.abort() })` (and equivalently if the controller is aborted before `new Request`). `SELF.fetch` never runs, so the adapter branch is unreachable in this pool. Harness gap — do not extend harness; test left failing (not skipped).
- **File:line:** `ai-platform/src/adapter.ts:482` (`abortedAtEntry = request.signal.aborted`); `ai-platform/src/adapter.ts:539-543` (enqueue `accepted` then close, no terminal); `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts` (Request init with `AbortSignal.abort()` throws in workerd).

## S08-057 (resolution)

- **Catalog claim:** Same as above — already-aborted `request.signal` still returns HTTP 200 SSE; `accepted` then close, no terminal; event-source fresh path not invoked.
- **Code behavior:** `SELF.fetch` / `new Request(..., { signal: AbortSignal.abort() })` still throws in workerd. The scenario is now driven like S08-058/S08-060: construct a normal `Request`, inject `AbortSignal.abort()` onto `.signal` after construction (`Object.defineProperty`, Proxy fallback), then call barrel `handleAdapterRequest` with `{ ok: true }` preAccept and a terminal-pushing `eventSource` stub. Assertions: HTTP 200 SSE, `accepted` first, Crockford `request_reference`, stub not called, no `cancelled`, empty `terminalEventTypes`.
- **File:line:** `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts` (`requestAbortedAtEntry` + `handleAdapterRequest`); `ai-platform/src/adapter.ts:482`, `ai-platform/src/adapter.ts:539-543`.
