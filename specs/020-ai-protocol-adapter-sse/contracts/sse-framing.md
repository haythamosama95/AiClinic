# Contract: SSE Event Framing and Submit-Request Header Set (A6)

**Frozen by:** Slice A6 — Protocol adapter and SSE framing
**Implements:** §4.3.1, §5.5 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices (D4, E2, H1, I1) **consume** this contract; the no-rework rule
applies (Delivery Plan §2.3). A later slice may **extend** (e.g. H1 adds a fourth terminal kind;
I1 adds the pre-stream accept gate in §8) but may **not rewrite** anything below except as that
documented extension requires.

---

## 1. Submit-request headers

Every `POST /v1/requests` AI request carries three parsed, non-secret correlation headers. The
adapter reads them at stage 1 (§6.1 stage 1) after the ingress body-size gate and body parse, before
the stream opens or a reference is generated. A malformed or missing required header — including
empty or whitespace-only `x-idempotency-key`, `x-capability-version`, or a present-but-empty
`x-trace-id` — is rejected by the adapter's own parsing with a bare HTTP 422 (no taxonomy body) and
never reaches the error taxonomy (§5.4 "no code maps to a bare `400`").

| Header | Frozen by | Purpose | Source |
| --- | --- | --- | --- |
| `x-idempotency-key` | A6 (this slice) | Stable across transport retries of the same user action | §4.3.1 "idempotency key"; §5.5 Submit-request row |
| `x-trace-id` | A2 (consumed) | Client-generated trace id; any non-empty client string is accepted; A2's `resolveTraceId` generates a ULID only when the header is absent | §4.3.1 "client trace id"; §13.1; A2 `trace.ts` |
| `x-capability-version` | A6 (this slice) | The capability version pin the resolver honours (a later stage) | §4.3.1 "capability version pin" |

The trace-id header name (`x-trace-id`) was established by A2's `worker.ts` implementation and is
consumed here unchanged. There is **no ULID-only constraint** on a client-supplied trace id — any
non-empty string is accepted (A2 `resolveTraceId`); the ULID is the gateway-generated fallback when
absent. The idempotency-key and capability-version header spellings are frozen by A6 — the slice the
architecture designates to freeze the Submit-request wire format (§4.3.1), in the same way A2 froze
the request-reference regex the architecture named only as "short human-readable identifier."

---

## 2. SSE event vocabulary

The stream is server-sent events downstream, single request upstream (§5.5). Every event carries an
explicit `event:` type. The vocabulary:

| Event type | When | Carries | Frozen by |
| --- | --- | --- | --- |
| `accepted` | Opening — the first event on every **accepted** stream, emitted exactly once before any content or terminal event, and **only after** the pre-stream accept gate succeeds (§8) | The request reference (A2's `generateRequestReference` format) | A6 (§5.5 rule 1); deferred until accept by I1 composition (§8) |
| `heartbeat` | While the stream is open and idle (no content events), to keep intermediaries from closing the connection | Nothing — neither content nor terminal | A6 owns framing (§5.5 rule 3); autonomous idle emission is D4's broker |
| Content events | Typed per A3's canonical chunk kinds (`text_delta`, `partial_structured`, `usage`, `provider_note`) | The chunk payload and the explicit type | A3 (kind vocabulary); A6 provides framing only — the relay is D4 (§4.3.10) |
| `completed` | Terminal — the request completed with a validated result | The validated result | A6 (§5.5 rule 4) |
| `failed` | Terminal — the request failed; carries a §5.4 taxonomy code in the event body | A2's error body `{"code","request_reference","trace_id","retry_safe"}` | A6 (§5.5 rule 4) |
| `cancelled` | Terminal — the client closed the stream | Nothing on the live socket — never enqueued after disconnect | A6 (§5.5 rule 5) |
| `context_requested` | Terminal — conversational capabilities only; **not** a `single_shot` event | The keys the assistant needs | H1 (extends this framing; §5.5 rule 4 fourth kind) |

Heartbeat **framing** (the `event: heartbeat` wire shape and "neither content nor terminal" semantics) is
A6's. Autonomous heartbeat **emission** while idle is owned by D4's stream broker; A6's adapter frames
injected heartbeats and does not tick them itself.

---

## 3. The one-terminal-event invariant

**Exactly one terminal event ends every stream — `completed`, `failed`, `cancelled`, or (for
conversational capabilities only) `context_requested`.** A terminal event is never inferred from
silence (§5.5 rule 4). The adapter enforces this as a connection-scoped state machine
(`terminalEmitted`): once a terminal event has been emitted — or cancellation has marked the flag
without enqueueing — no further event of any kind is emitted, under any path — completion, failure,
abort, or a duplicate close arriving afterwards.

---

## 4. Connection-scoped cancellation

Closing the stream cancels the request and ends it as `cancelled` (§5.5 rule 5, Cancel row). There
is no separate cancel endpoint and no cross-invocation state (§4.3.10). `cancelled` / `499` is never
written to the live socket as an HTTP status — a cancellation happens by the client closing the
stream, so nobody is left to receive a response; `499` is the value journaled for the terminal state
and returned in the body of a later "get request" lookup, which is itself a `200` (§5.4; persistence
and lookup are C3).

On every real disconnect path — `ReadableStream` `cancel()`, `request.signal` abort mid-stream, and
already-aborted at handler entry — the adapter MUST mark `terminalEmitted` only and MUST NEVER
enqueue a `cancelled` event onto the dead socket. Enqueueing after cancel throws at runtime and
violates "carries nothing on the live socket."

---

## 5. Ingress body-size gate

The adapter rejects a request whose body exceeds the ingress body-size limit as `request_too_large`
(HTTP 413, A2 error body) at stage 1, before any header is handled, before the stream opens, before a
reference is generated (§6.1 stage 1; §5.4). Measurement is **UTF-8 byte-accurate** (not UTF-16 code
units). When `Content-Length` is present and exceeds the limit, the adapter rejects before consuming
the body; otherwise it stream-reads and aborts at the first chunk that would cross the cap — it never
buffers past the limit. An oversized body with malformed headers still yields 413 (size gate before
parse), not 422.

The 413 error body carries **empty** `request_reference` and **empty** `trace_id` by design — a
stage-1 FR-006 exception, because the gate runs before headers are handled and before a reference is
generated. This is the transport-level ingress gate only; the per-capability and per-key size bounds
declared in the manifest, and the cost pre-flight `request_too_large` at stage 7, are C2. The limit
value is a transport configuration value supplied to the adapter, not a number this contract authors.

---

## 6. Error-to-HTTP translation

The adapter applies the §5.4 HTTP column — which is normative and is the only translation the adapter
may apply — via A2's `liveHttpStatusForCode` (returns `null` for `cancelled`, directing the adapter
not to emit an HTTP status on the live socket) and emits A2's `buildErrorBody` in every
taxonomy-coded error response (§4.3.1; §5.4; A2 `errors.ts`). A6 adds no codes and changes no
statuses.

**Adapter-local parse failures** (malformed JSON body, body that is not a non-null plain object,
malformed/missing/empty/whitespace required headers) use a **bare HTTP 422** with no taxonomy body.
This is intentional: §5.4 prohibits mapping a taxonomy code to a bare `400`; clients branch on the
taxonomy code when present, not on status alone. Bare 422 collides numerically with some taxonomy
codes that map to 422, but is safe because those responses carry a taxonomy body and parse failures
do not.

**Stage-1 oversized body** uses taxonomy `request_too_large` / HTTP 413 with empty correlation fields
(§5 FR-006 exception above).

---

## 7. Injected event source requirement

The adapter requires an injected `eventSource` (broker / stub). When missing, it fails fast with
HTTP 503 and opens no stream — the Worker live `POST /v1/requests` route therefore fails fast until
D4 wires the broker. Production stubs (`StubEventSourceController`, mode-gated defaults,
`attemptDuplicateTerminal`) do **not** live in `src/adapter.ts`; they live in the test harness
(`test/adapter.test.ts` and `test/helpers/adapter-stub.ts`).

`eventSource` is invoked **only after** the stream has been accepted: the SSE response is open and
the `accepted` event has been enqueued (§8). It drives content, heartbeats, and terminal events; it
MUST NOT be the path that returns pre-accept guard rejections as HTTP.

---

## 8. Pre-stream accept gate (composition extension — I1)

**Why this section exists.** Architecture requires: (1) guard rejection before acceptance is a
taxonomy **HTTP** response with **no** SSE stream and **no** `ai_request` row (§6.1 stages 1–8 vs 9;
§4.3.11; §6.2); (2) the journal row is written synchronously **before the stream opens**
(§4.3.11); (3) `accepted` is the opening event of an *accepted* stream (§5.5 rule 1) — not a signal
that the guard is about to run. A6's original injectable shell emitted `accepted` and then called
`eventSource`, which is sufficient for harness stubs that never run the guard, but is incomplete
for Band I live composition. This section is the **minimal A6 surface extension** that makes
§4.3.1 / §5.5 / §6.1 composable without inventing a parallel HTTP path that bypasses the adapter.

**Rule.** After ingress size / body parse / required headers succeed and a request reference is
allocated, and **before** any `text/event-stream` response is returned and **before** `accepted` is
emitted, the adapter MUST invoke an optional injected **pre-stream accept gate**
(`preAccept` / equivalent name on `HandleAdapterRequestOptions`).

| Gate result | Adapter wire behaviour |
| --- | --- |
| Omitted (A6 harness default) | Behave as the original shell: open SSE, emit `accepted`, then call `eventSource`. Preserves A6 unit/integration suites. |
| `{ ok: true }` (or equivalent success) | Open SSE (`200` + `text/event-stream`), emit exactly one `accepted` carrying the allocated request reference (and optional `degraded_notice`), then call `eventSource`. |
| `{ ok: false, code: <taxonomy> }` (pre-accept failure) | Return taxonomy HTTP via A2 `buildErrorBody` + `liveHttpStatusForCode` for that code; **open no stream**; **emit no `accepted`**; do **not** call `eventSource`. Journal insert remains C3 / stage 9 — a pre-accept failure MUST NOT leave an `ai_request` row. |

**Composition binding (I1).** Live `POST /v1/requests` supplies `preAccept` that runs the existing
`runGuard` path through acceptance (stage 9 journal on success) and supplies `eventSource` that
drives post-accept work (prompt / route / invoke / broker / validate / terminal / settle). I1 may
**modify `ai-platform/src/adapter.ts` framing** to implement this deferred-`accepted` gate as
in-scope composition work; that is an extension of this frozen surface, not a new platform contract
and not a rewrite of §§1–7 above.

**Non-goals of this extension.** No new taxonomy codes, no new SSE event types, no change to the
one-terminal-event invariant, no change to connection-scoped cancel, and no second HTTP error
envelope beyond A2's existing body.
