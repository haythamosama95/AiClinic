# Stage 10 catalog-vs-code conflicts

## S10-005

- **Catalog claim:** Unknown `provider_id` uses one `FakeAdapter(["retryable:provider_unavailable"])` whose script queue exhausts on retry, so attempt 2 is `retryable_failure` / `internal_error` (empty-queue branch).
- **Code behavior:** `resolveProviderPort` constructs a new adapter on every attempt. Unknown ids always get a fresh `new FakeAdapter(["retryable:provider_unavailable"])`, so both attempts are `retryable_failure` / `provider_unavailable`. Terminal SSE remains `failed` `provider_unavailable`.
- **File:line:** `ai-platform/src/worker.ts:351-366` (`resolveProviderPort`); `ai-platform/src/provider/fake.ts:92-99` (empty-queue `internal_error`, unreachable here); catalog S10-005; `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts` S10-005.

## S10-008

- **Catalog claim:** Two bogus-primary attempts then fake success: attempt 2 is empty-queue `internal_error` on the shared unknown-id adapter.
- **Code behavior:** Same per-attempt constructor as S10-005. Both bogus attempts are `provider_unavailable`; the third attempt on `fake` succeeds. Happy-path SSE is unchanged.
- **File:line:** `ai-platform/src/worker.ts:351-366`; catalog S10-008; `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts` S10-008.

## S10-015

- **Catalog claim:** `SELF.fetch` with an already-aborted signal hits adapter `abortedAtEntry`: event-source factory never runs; D1 `ai_request` exists from the guard INSERT and stays `Accepted` with `routing_decision NULL`; no attempts, usage, envelope, or credit.
- **Code behavior:** workerd rejects constructing `Request` with an aborted signal, and a `Proxy`/`defineProperty` on `Request.signal` does not cross `SELF.fetch`. Documented barrel seam `handleAdapterRequest` (Register 5 #39) does see `request.signal.aborted`: `eventSource` is never invoked, SSE is `accepted` only (no terminal), stub `preAccept` does not INSERT, so there is no `ai_request` row.
- **File:line:** `ai-platform/src/adapter.ts:482` (`abortedAtEntry`); `ai-platform/src/adapter.ts:527-532` (abort-at-entry short-circuit); catalog S10-015; `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts` S10-015.

## S10-028

- **Catalog claim:** SSE `accepted` → `text_delta("Partial output…", sequence 0)` → `failed` `validation_failed` (`retry_safe: true`). Truncation prose is relayed before the worker terminal.
- **Code behavior:** With `max_attempts: 1`, `exhaustedViaTruncation` returns `createValidationFailedError()`. The worker arms `ignoreBrokerSettlement = true` and `pushFailedTerminal` after `runInvocation` returns, then `broker.disconnect("client_close")` — the truncation-exhausted path closes the stream before the broker can emit the buffered truncation chunk. Actual SSE: `accepted` → `failed` (no `text_delta`). S10-029 still emits `text_delta` because same-target retry backoff keeps the broker open. Credit-once, attempt `outcome "truncation"`, `Failed`/`validation_failed`, usage 30 / 0.005 are unchanged.
- **File:line:** `ai-platform/src/invocation/index.ts:749-754` (truncation-exhausted → `validation_failed`); `ai-platform/src/worker.ts:1121-1192` (`ignoreBrokerSettlement` then `pushFailedTerminal`); `ai-platform/src/worker.ts:770-781` (`pushFailedTerminal`); `ai-platform/src/stream/index.ts:441-444` (`wasTruncated` fail, suppressed when ignore is armed); catalog `docs/testing/catalog/stage-10-accept-route-invoke-stream.md` S10-028 expected outcome; `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` S10-028.

## S10-034

- **Catalog claim:** Missing accept-context miss journals a synthetic `ai_attempt` (`terminal_failure`/`internal_error`), Quota DO `credit` once (`partial: true`), one `usage_event`, and one R2 envelope via `settleMissingHandoffInternalError` → `settlePostAcceptInternalError`.
- **Code behavior:** After `event_source_missing_accept_context` and SSE `accepted` → `failed` `internal_error`, `settleMissingHandoffInternalError` rebuilds `Principal` with `organizationId: ""`, `role: ""`, `scopes: []` (`worker.ts:534-545`). `resolveCapability` then fails `forbidden_capability` (`requiredCapabilityScope` `"ai.visit_summary"` and `allowedStaffRoles`). The function logs `missing_handoff_settle_capability_unresolved` and `recordTerminalState(Failed, internal_error)` only — no synthetic attempt, credit, usage, or envelope. A Map.prototype.get spy narrowed to the accept-context store (`this` identity / accept-context values, request-reference key, miss once) still hits this principal reconstruction; capability registry lookup succeeds (not `capability_unknown`).
- **File:line:** `ai-platform/src/worker.ts:504-566` (`settleMissingHandoffInternalError`); `ai-platform/src/worker.ts:534-545` (empty `scopes` / `role` principal); `ai-platform/src/worker.ts:839-861` (missing-accept-context branch); `ai-platform/src/capability/index.ts:256-272` (scope/role → `forbidden_capability`); `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json:10-16`; catalog `docs/testing/catalog/stage-10-accept-route-invoke-stream.md` S10-034 side effects; `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` S10-034.
