# Phase 0 Research: AI Generation Pipeline + Scheduling Agent (016)

**Branch**: `ai/016-generation-scheduling` | **Date**: 2026-07-18
**Feature spec**: `specs/016-ai-generation-scheduling/spec.md`
**Plan**: `specs/016-ai-generation-scheduling/plan.md`

This file records the technical decisions made before Phase 1 design. The feature spec already
resolved the *functional* ambiguities (in `## Clarifications`); the open questions here are
technical: how the existing Phase 1 Python/FastAPI Gateway absorbs the generation pipeline,
streaming, constrained decoding, queueing/backpressure, retries/cancellation, and PHI-safe
observability. Each section records **Decision**, **Rationale**, and **Alternatives considered**.

> All decisions below are consistent with the Phase 1 stack (Python 3.12 + FastAPI/Uvicorn +
> httpx + pydantic v2 + structlog + prometheus-client; Ollama runner; `pytest` harness) and add
> **no new long-running service** and **no new infrastructure** beyond the Phase 1 baseline.

---

## R-101 — Generation request handling: async FastAPI path handlers

**Decision**: Implement `POST /v1/ai/generate` as a single FastAPI route module (`api/generate.py`)
that branches internally on `options.stream`:

- **Non-streaming** (`options.stream=false`, or `=true` when `streaming_enabled=false` per
  Q2): runs the pipeline to completion and returns a single `JSONResponse` with the validated
  Command Protocol envelope (or a typed error).
- **Streaming** (`options.stream=true` + `streaming_enabled=true`): returns a
  `StreamingResponse` with `media_type="text/event-stream"` that wraps an async generator
  yielding `token`/`summary`/`final`/`error` SSE events.

The route replaces `api/generate_stub.py`. It reuses the Phase 1 auth dependency
(`auth/dependencies.py` — offline JWT + `ai.access` gate) and the routing selector
(`routing/selector.py`), extended to trigger model swaps when no `READY` capability match exists
(R-107).

**Rationale**: FastAPI natively supports both JSON and SSE responses with one route definition;
splitting into two routes would duplicate auth + validation. Branching on `options.stream` keeps
the client contract a single endpoint (per spec §10.1). The non-streaming path is a degenerate
case of streaming (consume the runner's token stream internally and emit one envelope at the
end), so the pipeline is the same code path with a different sink — maximizing test equivalence
(Q5's "both paths return identical `final` envelopes" becomes a near-tautology).

**Alternatives considered**:
- *Two separate routes* (`/generate` and `/generate-stream`): rejected — splits the client
  contract, diverges from spec §10.1 which uses `options.stream` on one route, and forces
  clients to choose a route rather than a per-request mode.
- *WebSockets* instead of SSE: rejected — spec §4.2/§10.2 explicitly mandate SSE
  (`text/event-stream`); WebSockets would over-engineer a one-way server→client token channel and
  complicate the cancellation contract (HTTP abort already propagates via request cancellation).
- *gRPC streaming*: rejected — adds infrastructure, a new contract surface, and a non-HTTP
  dependency; the Phase 1 Gateway is already HTTP/JSON.

---

## R-102 — Streaming protocol: SSE event shape and terminal-event discipline

**Decision**: Stream events are JSON-encoded payloads serialized as SSE `event: <type>\n` +
`data: <json>\n\n` blocks. Event types per spec §10.2:

| Event    | Payload                                                | When emitted                                            |
| -------- | ------------------------------------------------------ | ------------------------------------------------------- |
| `token`  | `{"delta": "..."}`                                    | Each token delta for `text`/`clinical_note`-style tasks. NOT emitted for `command` tasks (see R-103). |
| `summary`| `{"delta": "..."}`                                    | Optional human-readable "thinking"/summary channel; MAY interleave with the buffered command body for `command` tasks. |
| `final`  | The complete validated Command Protocol envelope JSON | Exactly once, when the full envelope validates. Terminal-success event. |
| `error`  | Typed error body `{"error": {code, message, request_id}}` | Exactly once, on failure. Terminal-error event.   |

Exactly one terminal event (`final` or `error`) per stream. The streaming generator catches
client disconnects (FastAPI `Request` cancellation / `asyncio.CancelledError`) and propagates
cancellation into the runner call (R-106). No retry after a partial stream has been sent (R-105).

**Rationale**: SSE's `event`/`data` framing matches the spec contract exactly. One terminal
event is testable as a single assertion per stream. Keeping `token` for free-text and forbidding
it for `command` tasks (R-103) is the cleanest way to enforce "commands never stream as partial
actionable JSON."

**Alternatives considered**:
- *Single `message` event type with a `kind` field inside the payload*: rejected — slightly
  simpler parser, but loses SSE's native `event` routing and complicates client subscription
  patterns.
- *Heartbeat/keep-alive events*: deferred — the first-token timeout (R-104) bounds the silent
  window; if heartbeat events become operationally necessary they will be additive (a new
  optional event type) without breaking the contract.

---

## R-103 — Command-task streaming: buffer the body, optionally stream the summary

**Decision**: For `task:"command"` (the only in-scope task this phase — scheduling), the
Gateway forwards the **grammar-constrained runner request** and **buffers** the full response
internally while optionally streaming an interim `summary` event series derived from a separate
"text" channel the model produces (the scheduling agent's system prompt instructs the model to
emit a short human-readable thought before the JSON; that thought is routed to the `summary`
channel, the JSON is buffered for validation). The `final` event carries the validated envelope
only.

If the model produces output that cannot be cleanly split (no summary prefix), the Gateway emits
no `summary` events and waits for the buffered `final`. **No partial `command_type` or `params`
is ever emitted as a `token` delta for command tasks.**

**Rationale**: Spec FR-004 mandates command tasks never stream partial actionable JSON. The
summary channel is a usability addition (so users see feedback during generation) that does not
weaken the guarantee — it is human-readable text the model produces explicitly as "thinking," not
the command body. The grammar is configured so the model's JSON output is buffered separately.

**Alternatives considered**:
- *No `summary` channel for commands; emit only `final`*: acceptable but loses live feedback in
  the future chat UI. We implement the channel; whether the agent emits a summary prefix is a
  system-prompt detail (it MAY omit it; in that case no `summary` events appear and the client
  waits for `final` — both behaviors are contract-compliant).
- *Stream the JSON as it grows and validate at the end*: rejected — explicitly violates FR-004
  and creates the risk that a client renders a half-formed actionable command.

---

## R-104 — Resilience envelope: in-process bounded queue, timeouts, retry, cancel

**Decision**: A new `pipeline/` module owns a per-capability-class **in-process** bounded FIFO
queue (default depth 16, max wait 20s) with overflow → `503 ai_busy`+`Retry-After`, and a
per-caller in-flight cap (default 2) tracking live `asyncio.Task`s by `caller_staff_id`. The
queue is **not** an external broker — it is an `asyncio.Semaphore`-gated deque of awaiting
coroutines owned by the Gateway process.

Timeouts are orchestrated with `asyncio.timeout`:
- first-token timeout (default 15s): from runner-request start to first decoded token (or
  `STARTING`/model-swap window end);
- total inference timeout (default 45s): from runner-request start to runner completion;
- model-swap first-token timeout (default 60s): active when the chosen runner is in `STARTING`
  due to a swap triggered by R-107.

Each timeout breach cancels the in-flight runner call (R-106) and either triggers a single retry
(R-105) or returns `504 ai_timeout`.

**Rationale**: This is the spec's §7.1/§7.4 design mapped onto Python's async primitives. The
queue bounds memory by rejecting overflow (no unbounded coroutine growth); per-caller in-flight
guards fairness; timeouts bound tail latency. Using `asyncio` directly keeps the implementation
in the single Gateway process with no new infrastructure, satisfying the constitution's
"no message queues / no Kubernetes" rule (the queue is a bounded in-process bookkeeping
primitive, not a broker).

**Alternatives considered**:
- *External queue (Redis / RabbitMQ / NATS)*: explicitly rejected — violates constitution's
  "no message queues" rule and the simplicity budget; the Gateway is the only AI service.
- *Per-runner queue instead of per-capability-class*: rejected — couples Gateway backpressure
  to runner topology and complicates capability routing; per-capability-class matches the
  spec's §7.1 wording.
- *`anyio` task groups instead of `asyncio`*: a stylistic choice; we use `asyncio` directly to
  match Phase 1's dependency footprint (no new framework), but the design is anyio-compatible.

---

## R-105 — Retry policy: single idempotent retry, never after partial stream or `422`

**Decision**: Exactly one retry per request when the runner returns a connection error, a 5xx,
or breaches the first-token timeout. The retry prefers a **different healthy runner** with the
required capability (using the existing Phase 1 selector); if no different runner is available,
the retry MAY go to the same runner. **No retry** is attempted:

- after a partial stream has been sent to the client (would duplicate output tokens — would
  require expensive reconciliation logic);
- when semantic or schema validation rejects the output (`422 ai_unusable`, per Q3 — a
  deterministic model-output problem, not transient);
- when the runner exceeds the **total** timeout (the request was already serviceable; the
  runner is presumed stuck);
- when the queue is full (caller already received `503 ai_busy`).

Retries are logged with `outcome="retry_then_ok"` or `outcome="retry_then_error"` plus the
original error class.

**Rationale**: Spec §7.5 + Q3 settled this. Generation is side-effect-free in the AI layer so a
retry is safe; partial-stream handling is forbidden because duplicating visible output
corrupts the UX. `422 ai_unusable` is deterministic. "Different healthy runner" preference keeps
the retry from hammering a stalled node.

**Alternatives considered**:
- *Jittered exponential backoff with multiple retries*: rejected — adds latency to a synchronous
  staff-facing flow; one retry is the spec's design and matches clinic scale.
- *Retry on `422 ai_unusable` with `temperature>0`*: rejected per Q3 (Option B chosen);
  deterministic rejections are not transient.

---

## R-106 — Cancellation propagation

**Decision**: FastAPI cancels the request handler coroutine when the client disconnects (HTTP
abort). The handler wraps the runner HTTP call (`httpx.AsyncClient` with streaming) and the
queue slot acquisition in a single `try/finally` that: (a) aborts the runner HTTP request
(`httpx` close → underlying TCP RST / Ollama request cancellation), (b) releases the queue slot,
(c) emits a structured log record with `outcome="cancelled"` (NOT `error`). The `pipeline/cancel`
module centralizes this so non-streaming and streaming paths share it.

**Rationale**: Spec §7.6 requires end-to-end cancellation. `asyncio` cancellation + `httpx`
stream-close maps directly. Logging `cancelled` separately keeps `/metrics` error-rate honest
(SAT-exit-vs-error s-coded).

**Alternatives considered**:
- *HTTP/2 client cancellation only*: rejected — FastAPI's request cancellation is the upstream
  trigger and must drive the cascade; relying on the client alone would leave the runner request
  running and waste the queue slot.
- *Cooperative cancellation token*: unnecessary — `asyncio` task cancellation is the natural
  primitive here; a custom token adds abstraction with no benefit.

---

## R-107 — Model-swap auto-trigger when no READY capability match

**Decision**: Extend `routing/selector.py` to handle the "no `READY` runner advertises the
required capability **but a candidate runner is configured with the capable model `UNLOADED`**"
case: the selector emits a "swap request" instead of `503 ai_no_capacity`, picks the least-busy
candidate runner, calls the runner's model-load endpoint (Ollama's `/api/load`), waits within
the extended `model_swap_first_token_timeout_s` (default 60s) for the runner to reach `READY`,
then proceeds with normal routing. The in-process runner state machine (Phase 1's
`routing/lifecycle.py`) already supports `STARTING → READY`; the swap-trigger path uses it.

Per Phase 1's invariant: a load MUST unload the previous model first; the runner ensures this
(Ollama + our config pinning to **one** model tag at a time means a swap is the only operation;
concurrent requests during `STARTING` queue or receive `503 ai_busy`).

**Rationale**: Q5 of `/clarify` chose auto-trigger (Option A) over returning `503` prematurely.
Source spec §6.4 mandates the swap; §7.7 reserves `503 ai_no_capacity` for "no healthy runner
and no swap candidate." The implementation uses the existing lifecycle, so the one-model-in-RAM
invariant is preserved structurally.

**Alternatives considered**:
- *Return `503 ai_no_capacity` immediately, let a subsequent request trigger the swap*: rejected
  per Q5; breaks the patient-care workflow with a manual retry.
- *Background swap daemon pre-warming all configured models*: rejected — would violate the
  one-model-in-RAM invariant (pre-warming concurrently) and is unnecessary at clinic scale.

---

## R-108 — Constrained decoding: Ollama `format: <json_schema>` primary, GBNF documented

**Decision**: For command tasks the runner request includes Ollama's `format` parameter set to a
JSON-schema object derived from the target scheduling command's schema. Ollama enforces
grammar-constrained decoding natively (its `format` field accepts a JSON schema and constrains
the sampler). Defense-in-depth: after the runner returns, `validation/schema_check.py` runs
`jsonschema` validation anyway (grammar makes structurally invalid JSON impossible, but
field-level mismatches on the model side — missing required, wrong enum — are still catchable).

For `llama-server` (the alternative runtime documented in Phase 1's runbook), the same JSON
schema is translated to GBNF; this is documented in `contracts/scheduling-schema.md` but not
implemented in code, since the default runtime is Ollama.

**Rationale**: Ollama's native `format: <json_schema>` is the simplest path (no extra library,
no out-of-process grammar compiler). Source spec §7.3 mandates grammar-constrained decoding as
the structural guarantee and schema validation as defense-in-depth. Q in /clarify (no open
question) settled the approach is grammar+schema, not schema-only.

**Alternatives considered**:
- *Outlines / XGrammar as an out-of-process grammar compiler*: rejected — adds infrastructure
  and an external compiled-grammar artifact; Ollama's `format` is sufficient at the target model
  size (Qwen3-4B) and quality.
- *Schema validation only, no grammar*: rejected — explicitly violates FR-008 ("structurally
  invalid JSON is impossible, not merely unlikely"); schema-only fails open on the structural
  guarantee.

---

## R-109 — Scheduling agent system prompt: delimited untrusted regions, immutable by clients

**Decision**: The scheduling agent's system prompt (`agents/scheduling/agent.py`) is a
server-side constant ViewHolder loaded at Gateway startup from `agents/scheduling/`. It contains
the instruction region (role, objective, the command catalog, output format spec, no-PHI-as-fact
guardrails). Client-supplied `prompt` and `context` fields are concatenated into clearly
delimited *user* and *context* regions with explicit boundary tokens, placed after the system
prompt. Clients cannot substitute or augment the system prompt — the request body has no field
for it (FR-007).

The agent targets the four scheduling command types and produces a single-command envelope
(`command_type`, `params`, `requires_resolution`, `display_summary`) plus an optional
human-readable "summary" prefix (see R-103) that lives in a separate region the model is
instructed to emit before the JSON.

**Rationale**: Spec §7.2 + §11.4 mandate (a) the Gateway owns the system prompt, (b) all
caller-supplied text is untrusted data in delimited regions, (c) the model "thinks before it
commits" (reasoning/`display_summary` before decision fields — FR advises placing reasoning fields
first in schemas); the summary-prefix channel satisfies that. Prompt-injection mitigations
(Q4 in /clarify, FR-013) rely on this immutability.

**Alternatives considered**:
- *Client-supplied per-task prompt prefixes*: rejected — creates a prompt-injection vector and
  violates FR-007.
- *No summary prefix (silent buffering)*: functionally acceptable; we implement the channel and
  the agent MAY emit or omit a summary prefix (contract: zero or more `summary` events allowed
  before `final`).

---

## R-110 — Command Protocol envelope: `needs_clarification` field and confidence-threshold logic

**Decision**: The envelope (`validation/envelope.py`) assembles a pydantic-validated object
matching the Command Protocol with these fields per Q1 of /clarify: `schema_version`,
`task="command"`, `command_type`, `confidence: float[0,1]`, `display_summary: str`,
`params: dict`, `requires_resolution: dict[str, str]` (bare-string form only this phase),
`warnings: list[Warning]`, and `needs_clarification: bool`. The boolean is set by the Gateway
from `ai.confidence_threshold` (`true` when `confidence < threshold`) and destructively forced
`true` for destructive commands (`cancel_appointment`, `reschedule_appointment`) when any
resolved field is ambiguous (per FR-012 clarification). `confidence` is the raw model output and
is always emitted.

**Rationale**: Q1 of /clarify chose Option B — an explicit flag — so clients test the flag, not
the threshold they may not know. The destructive-command override implements §9.4's
"destructive commands SHOULD require above-threshold confidence AND explicit confirmation" at the
Gateway's coarse gate; authoritative per-command enforcement still happens at the RPC in Phase 3.

**Alternatives considered**:
- *No flag; client compares `confidence` to threshold*: rejected per Q1 (Option A rejected);
  clients shouldn't be coupled to the Gateway's configured threshold.
- *`warnings` array carries a typed `low_confidence` code only*: rejected per Q1 (Option C
  rejected); makes the "clarification vs actionable" check a search-through-warnings rather than
  a single boolean test.

---

## R-111 — PHI-redacted structured logs and metrics

**Decision**: Extend Phase 1's `obs/logging.py` `structlog` pipeline with a redacting processor
that hashes or drops the `prompt`, `context`, and `params`/`display_summary` text by default
(when `log_verbatim=false`), making the log record carry only operational fields: `request_id`,
`caller_staff_id`, `task`, `agent`, `runner`, `model`, `digest`, queue/first-token/total
latencies, token counts, `outcome` (`ok`/`error`/`timeout`/`cancelled`), error class on failure.
When `log_verbatim=true`, the processor emits verbatim payloads but file rotation enforces the
`log_verbatim_retention_hours` (default 24h, per Q4 of /clarify) and a startup warning is logged
by a non-production profile.

`/metrics` (Phase 1's `prometheus_client`) is extended with: `ai_requests_total{task,outcome}`,
`ai_errors_total{code}`, `ai_queue_depth{capability}`, `ai_first_token_seconds{runner}` /
`ai_total_seconds{runner}` histograms, `ai_inflight{capability}`, `ai_tokens_per_sec`.

**Rationale**: Spec §8.4 + FR-022/FR-023 + SC-009. The redacting processor reuses structlog's
chain pattern (no new infra). Retention via rotated file handler matches the Q4 default.

**Alternatives considered**:
- *Verbatim-logging always on with redaction opt-in*: rejected — inverts the PHI-safe default
  (spec is unambiguous that redaction is the default).
- *OpenTelemetry tracing*: deferred — adds a runtime dependency and a collector; Phase 1 already
  has structured file logs + Prometheus; the spec calls for local files + `/metrics` only.

---

## R-112 — Graceful shutdown: extend lifespan with SIGTERM drain

**Decision**: Extend the Phase 1 `main.py` lifespan with a SIGTERM (and SIGINT) handler that:
(a) stops accepting new requests (FastAPI lifespan gate — the ASGI server stops the listener),
(b) waits up to a configured grace period (default 10s) for in-flight requests to complete,
(c) rejects queued-but-not-started requests with `503 ai_busy`, (d) cancels any request still
running after the grace period and logs each as `cancelled`.

**Rationale**: Spec §8.3 mandates graceful SIGTERM drain. FastAPI lifespans support startup /
shutdown hooks; combining with a SIGTERM signal handler + `asyncio.wait_for(shutdown_event)`
gives the documented behavior using only the existing stack.

**Alternatives considered**:
- *Uvicorn's `timeout_graceful_shutdown`* alone: insufficient — it does not differentiate
  queued-but-not-started from in-flight; we add per-request awareness via the pipeline.

---

## R-113 — Test harness extension: scripted streaming fake runner

**Decision**: Extend the Phase 1 `tests/fixtures/fake_runner.py` to support: (a) scripted token
streams as JSON events the fake runner emits as SSE; (b) scripted first-token delays; (c)
scripted validation responses (valid envelope, invalid JSON, semantic violations like a past
date); (d) scripted `STARTING` mid-stream swaps; (e) connection-refused / 5xx / network-error
injections. The in-process `httpx.ASGITransport` client already supports SSE consumption; the
contract test suite uses `httpx.AsyncClient(event_hooks=...)` to parse SSE events.

**Rationale**: Spec mandates a heavy test suite (§15, Phase 2 🧪 block, all SC-001..SC-012).
Scripted streaming is the only way to deterministically test "no partial actionable JSON streams,"
"identical final in both modes," and "cancel frees the slot before runner completes."

**Alternatives considered**:
- *Record-and-replay real Ollama responses*: rejected — couples tests to model non-determinism
  and to a running Ollama in CI; the fake runner is the deterministic boundary.
- *Spin a real Ollama in CI*: kept as a separate smoke path (Phase 5 covers that), not the
  contract test suite that gates Phase 2 exit.

---

## Summary of NEEDS CLARIFICATION resolution

All NEEDS CLARIFICATION markers in `plan.md` Technical Context are resolved by the spec's
Clarifications section + this `research.md`:

- Gateway language/runtime — **no new NEEDS CLARIFICATION** (reuses Phase 1 R-001 decision:
  Python 3.12 + FastAPI/Uvicorn).
- Streaming protocol and command-stream buffering — **no new NEEDS CLARIFICATION** (resolved by
  R-102, R-103, R-109; spec Q5 settled "both paths ship together").
- Retry/cancellation/model-swap behavior — **no new NEEDS CLARIFICATION** (resolved by
  R-104/R-105/R-106/R-107; clarifications Q2-Q5 settled).
- Constrained decoding mechanism — **no new NEEDS CLARIFICATION** (resolved by R-108; Ollama
  `format:` chosen, GBNF documented for the alternative runtime).
- Envelope `needs_clarification` field — **no new NEEDS CLARIFICATION** (resolved by R-110;
  clarification Q1 settled).

Open items *intentionally deferred to the Phase 3 / Phase 5 plans* (not blocking this feature):

- Flutter chat panel / approval card / `lookup_required` resolution UI (Phase 3 / V2-2).
- Cloud models and remote runners (Phase 5 production-readiness; off by default this phase).
- Push-based runner registration and multi-runner failover at scale (Phase 4 / V2-3; config-gated
  off this phase, validated only with fake runners).
- TLS configuration and off-LAN operation (Phase 5 production-readiness).
- Multi-command `task:"plan"` emission (later phase behind `enable_multi_command_plans`;
  single command is the length-1 plan this phase).