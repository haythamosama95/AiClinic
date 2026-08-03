# Contract: SSE Event Framing and Submit-Request Header Set (A6)

**Frozen by:** Slice A6 — Protocol adapter and SSE framing
**Implements:** §4.3.1, §5.5 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (D4, E2, H1) **consume** this contract; the no-rework rule applies
(Delivery Plan §2.3). A later slice may **extend** (e.g. H1 adds a fourth terminal kind) but may
not **rewrite** anything below.

---

## 1. Submit-request headers

Every `POST /v1/requests` AI request carries three parsed, non-secret correlation headers. The
adapter reads them at stage 1 (§6.1 stage 1) before any other work; a malformed or missing required
header is rejected by the adapter's own parsing and never reaches the error taxonomy (§5.4 "no code
maps to a bare `400`").

| Header | Frozen by | Purpose | Source |
| --- | --- | --- | --- |
| `x-idempotency-key` | A6 (this slice) | Stable across transport retries of the same user action | §4.3.1 "idempotency key"; §5.5 Submit-request row |
| `x-trace-id` | A2 (consumed) | Client-generated trace id; A2's `resolveTraceId` generates a ULID when absent | §4.3.1 "client trace id"; §13.1; A2 `trace.ts` |
| `x-capability-version` | A6 (this slice) | The capability version pin the resolver honours (a later stage) | §4.3.1 "capability version pin" |

The trace-id header name (`x-trace-id`) was established by A2's `worker.ts` implementation and is
consumed here unchanged. The idempotency-key and capability-version header spellings are frozen by
A6 — the slice the architecture designates to freeze the Submit-request wire format (§4.3.1), in the
same way A2 froze the request-reference regex the architecture named only as "short human-readable
identifier."

---

## 2. SSE event vocabulary

The stream is server-sent events downstream, single request upstream (§5.5). Every event carries an
explicit `event:` type. The vocabulary:

| Event type | When | Carries | Frozen by |
| --- | --- | --- | --- |
| `accepted` | Opening — the first event on every stream, emitted exactly once before any content or terminal event | The request reference (A2's `generateRequestReference` format) | A6 (§5.5 rule 1) |
| `heartbeat` | While the stream is open and idle (no content events), to keep intermediaries from closing the connection | Nothing — neither content nor terminal | A6 (§5.5 rule 3) |
| Content events | Typed per A3's canonical chunk kinds (`text_delta`, `partial_structured`, `usage`, `provider_note`) | The chunk payload and the explicit type | A3 (kind vocabulary); A6 provides framing only — the relay is D4 (§4.3.10) |
| `completed` | Terminal — the request completed with a validated result | The validated result | A6 (§5.5 rule 4) |
| `failed` | Terminal — the request failed; carries a §5.4 taxonomy code in the event body | A2's error body `{"code","request_reference","trace_id","retry_safe"}` | A6 (§5.5 rule 4) |
| `cancelled` | Terminal — the client closed the stream | Nothing on the live socket | A6 (§5.5 rule 5) |
| `context_requested` | Terminal — conversational capabilities only; **not** a `single_shot` event | The keys the assistant needs | H1 (extends this framing; §5.5 rule 4 fourth kind) |

---

## 3. The one-terminal-event invariant

**Exactly one terminal event ends every stream — `completed`, `failed`, `cancelled`, or (for
conversational capabilities only) `context_requested`.** A terminal event is never inferred from
silence (§5.5 rule 4). The adapter enforces this as a state machine: once a terminal event has been
emitted, no further event of any kind is emitted, under any path — completion, failure, abort, or a
duplicate close arriving afterwards.

---

## 4. Connection-scoped cancellation

Closing the stream cancels the request and ends it as `cancelled` (§5.5 rule 5, Cancel row). There
is no separate cancel endpoint and no cross-invocation state (§4.3.10). `cancelled` / `499` is never
written to the live socket as an HTTP status — a cancellation happens by the client closing the
stream, so nobody is left to receive a response; `499` is the value journaled for the terminal state
and returned in the body of a later "get request" lookup, which is itself a `200` (§5.4; persistence
and lookup are C3).

---

## 5. Ingress body-size gate

The adapter rejects a request whose body exceeds the ingress body-size limit as `request_too_large`
(HTTP 413, A2 error body) at stage 1, before any header is handled, before the stream opens, before a
reference is generated (§6.1 stage 1; §5.4). This is the transport-level ingress gate only; the
per-capability and per-key size bounds declared in the manifest, and the cost pre-flight
`request_too_large` at stage 7, are C2. The limit value is a transport configuration value supplied
to the adapter, not a number this contract authors.

---

## 6. Error-to-HTTP translation

The adapter applies the §5.4 HTTP column — which is normative and is the only translation the adapter
may apply — via A2's `liveHttpStatusForCode` (returns `null` for `cancelled`, directing the adapter
not to emit an HTTP status on the live socket) and emits A2's `buildErrorBody` in every error response
(§4.3.1; §5.4; A2 `errors.ts`). A6 adds no codes and changes no statuses.