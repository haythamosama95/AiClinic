# Error Contract (Phase 2 / feature 016 — extends Phase 1)

**Spec**: `specs/016-ai-generation-scheduling/spec.md` (§10.4)
**Extends**: `specs/015-ai-layer-foundation/contracts/error-contract.md`

All errors share one body shape:

```json
{ "error": { "code": "<stable-code>", "message": "<human-readable>", "request_id": "<uuid>" } }
```

For SSE streams, errors are emitted as a terminal `error` event with the same payload as the
event's `data` field (see `command-protocol.md` / R-102 of `research.md`).

## HTTP status → code → meaning (Phase 1 + Phase 2 additions in **bold**)

| HTTP | code                  | Meaning                                                                                      | Phase 2 added? |
| ---- | --------------------- | -------------------------------------------------------------------------------------------- | -------------- |
| 400  | `bad_request`         | Malformed/oversized input (≤ 8 KB default; unknown fields ignored, not errored).            | no             |
| 401  | `unauthenticated`     | Missing, tampered, expired, or not-yet-valid JWT.                                            | no             |
| 403  | `forbidden`           | Authenticated caller whose role lacks `ai.access`.                                          | no             |
| **422** | **`ai_unusable`**   | Output failed schema or semantic validation (e.g., past-dated appointment, illegal enum, inconsistent `display_summary`). **Not retried** (per /clarify Q3). | **yes**        |
| 429  | `rate_limited`        | Per-caller in-flight cap exceeded (`max_inflight_per_caller`, default 2).                    | **added scope** |
| **503** | **`ai_busy`**       | Capability-class queue full (`queue_max_depth` default 16) or `queue_max_wait_s` (default 20s) breached. MUST include `Retry-After` header. | **yes**        |
| **503** | **`ai_no_capacity`**| No `READY` capability match **after** auto-swap attempt (per R-107 / /clarify Q5), or no candidate runner able to serve the capability. | **yes**        |
| **504** | **`ai_timeout`**    | Inference exceeded first-token (default 15s), total (default 45s), or model-swap first-token (default 60s) timeout. | **yes**        |

## Behavior rules (Phase 2)

- **Single terminal event on streams**: a streaming request emits exactly one terminal SSE
  event (`final` or `error`), never both, never duplicate.
- **Retry discipline** (per /clarify Q3, R-105):
  - Retried once: runner connection error, runner 5xx, first-token timeout. Prefers a different
    healthy runner.
  - Not retried: `422 ai_unusable`, total timeout, partial stream sent, queue-full (`503 ai_busy`).
- **Cancellation**: a client-aborted HTTP request frees the queue slot, aborts the runner call,
  and is logged with `outcome="cancelled"` (not `error`). Cancellation is NOT a terminal SSE
  event because the client is no longer listening; the in-process log records it.
- **Backpressure**: `503 ai_busy` MUST include a `Retry-After` header (seconds). The Gateway
  does NOT auto-retry on behalf of the client for queue-full (the client backs off and retries
  once, optionally).
- **`ai_no_capacity` vs `ai_busy`**: `ai_busy` = saturated but capacity exists (queue will
  drain); `ai_no_capacity` = no runner can serve this capability even after a swap attempt.
- **Disable streaming mid-flight**: if `streaming_enabled=false` and the client requested
  `options.stream=true`, the Gateway silently serves the non-streaming path (per /clarify Q2,
  R-101) — NOT an error.
- **Validation rejection is terminal**: `422 ai_unusable` is final; the client surfaces a
  "rephrase" UX. No partial actionable command is streamed.

## Edge cases

- **Token expires mid-request**: the offline validator only checks signature/expiry at receipt;
  a request whose token was valid at receipt is processed to completion. Mid-request expiry does
  not invalidate an in-flight request this phase (the validator is not re-run mid-flight).
- **Malformed/oversized body**: exceeds the 8 KB prompt cap or carries a malformed
  `context` field → `400 bad_request`.
- **Unknown request fields**: ignored (forward-compat, §10.5); not an error.
- **Reserved but ignored options this phase**: `options.plan_mode="multi"` → accepted,
  single-command envelope emitted; `conversation_id`/`turn` → accepted, ignored.