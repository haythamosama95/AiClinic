# Feature Specification: Protocol adapter and SSE framing (A6)

**Feature Branch**: `ai/020-a6-protocol-adapter-sse`

**Created**: 2026-07-31

**Status**: Draft

**Input**: Slice `A6` — *Protocol adapter and SSE framing* (Delivery Plan §3.2, row A6).

> Constitution note: This slice provisions no new deployable component. It lives entirely inside the
> Cloudflare AI Gateway Worker (`ai-platform/`), the additive, non-primary component registered by A1.
> Per §14 acknowledgement of `17-ai-platform.md`, the gateway holds no domain logic, no business data,
> and has no write path into Supabase. This slice stays inside that boundary: it owns the wire format
> and the SSE framing, and nothing else.

## Slice Contract

### Implements

§4.3.1, §5.5 of `docs/architecture/17-ai-platform.md` (copied verbatim from the A6 `Canonical` cell,
Delivery Plan §3.2).

### Freezes

This slice establishes, for the first time:

- **The Submit-request wire format at the protocol adapter**: request parsing, the ingress body-size
  gate (stage 1 — before the manifest is resolved), and the header set every AI request carries — the
  idempotency key, the client trace id, and the capability version pin (§4.3.1, §6.1 stage 1, §5.5
  Submit-request row).
- **The SSE event framing for streaming responses**: the event envelope; the `accepted` opening event
  carrying the request reference; the heartbeat event; the terminal event kinds `completed`, `failed`,
  and `cancelled` (the three that exist for `single_shot` capabilities); and the **one-terminal-event
  invariant** — exactly one terminal event ends every stream, never inferred from silence (§5.5 rules
  1, 3, 4). The fourth terminal kind, `context_requested`, is added by H1; A6 freezes a framing that
  H1 extends, not one it must rewrite.
- **Connection-scoped cancellation at the framing level**: closing the stream ends the request as
  `cancelled`; there is no separate cancel endpoint and no cross-invocation state (§5.5 Cancel row,
  rule 5).
- **On-the-wire HTTP error emission**: the adapter applies the §5.4 HTTP column and the A2 error body
  to actual HTTP responses. The HTTP column is normative and is the only translation the adapter may
  apply (§4.3.1, §5.4); A6 emits on the wire what A2 froze.

Later slices may extend these and may not rewrite them (Delivery Plan §2.3).

### Consumes

Contracts frozen by **A2** (the slice in `Needs`); changing any of them is out of scope by definition:

- **The error taxonomy** (§5.4): the closed, stable set of codes, their normative HTTP mapping, and
  the prohibition that an unrecognised code is treated as `internal_error` and never surfaced raw. A6
  translates these to HTTP on the wire; it adds no codes and changes no statuses.
- **The error-body contract** `{"code","request_reference","trace_id","retry_safe"}`: every error
  response A6 emits carries these fields (§5.4; A2).
- **The request-reference generator and format** (`^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`,
  CSPRNG-sourced): A6's `accepted` event carries the reference A2 produces (§8.9; A2).
- **The trace-id propagation contract**: the trace id is client-generated; A6 parses the client trace
  id header (any non-empty client string is accepted — no ULID-only client constraint), propagates it
  to every event and log line for the request, and relies on A2's `resolveTraceId` gateway-generated
  ULID when the caller omits one (§13.1; A2).

### Open decisions relied on

None. A6 does not depend on any of the fourteen §15 decisions. The wire format, the header set, and
the streaming protocol rules are fully specified by §4.3.1 and §5.5; the error mapping and reference
it emits are A2's.

## Clarifications

### Session 2026-07-31

- Q: How should the T1 oversized-request fixture build a body that exceeds the ingress limit
  deterministically, given the limit itself is a supplied transport config value the spec does not
  author? → A: The test binds to the same ingress body-size config value the adapter reads and builds a
  body one byte larger, asserting only the relation "body just over the limit" so the branch stays under
  test if the limit changes. `[implementation choice — no §citation]`
- Q: What stub drives T6–T11 given A6 owns no broker and no provider? → A: A small in-process stub
  that injects canned `accepted`, heartbeat, and terminal sequences directly into the adapter's event
  sink — no broker, no provider, no network. The stub lives in the test harness
  (`test/adapter.test.ts` + `test/helpers/adapter-stub.ts`), not in `src/adapter.ts`.
  `[implementation choice — no §citation]`

### Session 2026-08-03 (A6 review resolution)

- Q: On real disconnect, may the adapter enqueue a `cancelled` SSE event? → A: No. On
  `ReadableStream` `cancel()`, `request.signal` abort, and already-aborted at entry, mark
  `terminalEmitted` only; never enqueue `cancelled` onto the dead socket.
  `[implementation choice — review resolution A6]`
- Q: How is the ingress body-size gate measured and ordered? → A: UTF-8 byte-accurate;
  `Content-Length` pre-check when present; otherwise stream-read and abort at the first oversize
  chunk; never buffer past the cap. Oversized + malformed headers still yield 413. The 413 body
  carries empty `request_reference` and empty `trace_id` (FR-006 stage-1 exception).
  `[implementation choice — review resolution A6]`
- Q: How is a malformed body rejected? → A: JSON parse must succeed and yield a non-null plain
  object; otherwise bare HTTP 422 with no taxonomy body. Empty/whitespace required headers use the
  same bare 422. `[implementation choice — review resolution A6]`
- Q: May the adapter require a ULID for client-supplied `x-trace-id`? → A: No. Any non-empty client
  string is accepted via A2 `resolveTraceId`; ULID is generated only when the header is absent.
  `[implementation choice — review resolution A6]`
- Q: Where do event-source stubs live, and what happens without an injected source? → A: Stubs are
  test-harness only. The adapter requires injected `eventSource`; missing → HTTP 503. The Worker live
  route fails fast until D4. Heartbeat framing is A6; autonomous idle emission is D4's broker.
  `[implementation choice — review resolution A6]`
- Q: Why bare 422 for adapter-local parse failures? → A: Intentional — §5.4 forbids a taxonomy code
  mapping to bare `400`; clients branch on taxonomy code when present. Bare 422 is safe despite
  numeric collision with some taxonomy 422s. `[implementation choice — review resolution A6]`

## User Scenarios & Testing

### User Story 1 — A6: Protocol adapter and SSE framing (Priority: P1)

As the platform reviewer, I want the gateway to own the request wire format and the SSE event framing
— to parse the request and its three headers, to reject an oversized or malformed request before any
work, to open every stream with an `accepted` event carrying the request reference, to emit heartbeats
while idle, and to guarantee exactly one terminal event under every path including abort — so that every
later slice that submits or consumes a stream (D4 the stream broker, E2 the AI Client SDK) is constrained
by a framing and a header contract that already exist and cannot drift.

**Why this priority**: A6 sits last in Band A (Delivery Plan §3.2). It has `Needs: A2`: it presumes the
diagnostic envelope — the error taxonomy, the error body, the request-reference generator, and the
trace-id contract — already exists, and nothing else. A6 is the slice review checkpoint **CP1** examines
("Do the frozen contracts compose at build time? Manifest, context key shapes, canonical representation,
and error taxonomy are mutually consistent"). Every later slice that opens or reads a stream presumes
the SSE framing, the header set, and the one-terminal-event invariant are already frozen; without A6
those slices would each invent an event shape or a header, and the no-rework rule (Delivery Plan §2.3)
would make the resulting drift unfixable inside a slice.

**Independent Test**: Provable by an automated integration test against a deterministic stub event
source in the test harness — size limits (UTF-8 byte-accurate) and the idempotency key, trace id
(any non-empty), and version pin headers are parsed; a stream opens with `accepted` carrying the
request reference; injected heartbeats are framed correctly; the stream ends with exactly one
terminal event for each of `completed`, `failed`, `cancelled`; real disconnect marks
`terminalEmitted` without dead-socket enqueue; and no duplicate terminal event appears under any
path (Delivery Plan §3.2 A6 `Done when`, §3.11.1 A6). Suite: 33 tests in `adapter.test.ts`. No
user-facing behaviour is demonstrated (DP-3).

**Acceptance Scenarios**:

1. **Given** a request whose body exceeds the ingress body-size limit (UTF-8 bytes), **When** the
   adapter parses it, **Then** it is rejected as `request_too_large` (HTTP 413, A2 error body with
   empty `request_reference` and empty `trace_id` — FR-006 stage-1 exception) before any other work —
   no header is handled, no stream is opened, no reference is generated. An oversized body with
   malformed headers still yields 413, not 422.
2. **Given** a well-formed request, **When** the adapter parses the idempotency-key header, **Then** the
   key is parsed from the request and available to later stages.
3. **Given** a well-formed request, **When** the adapter parses the client-trace-id header, **Then** the
   trace id is parsed and propagated (any non-empty client string accepted; per A2, generated as a
   ULID when absent — no ULID-only client constraint).
4. **Given** a well-formed request, **When** the adapter parses the capability-version-pin header,
   **Then** the pin is parsed and available to the capability resolver (a later stage).
5. **Given** a request with a malformed body (non-JSON, null, or non-object), or a malformed, missing,
   empty, or whitespace-only required header (idempotency key, trace id, or version pin), **When** the
   adapter parses it, **Then** it is rejected by the adapter's own parsing with bare HTTP 422 (no
   taxonomy body) and does not reach the taxonomy or open a stream.
6. **Given** a request accepted for streaming, **When** the stream opens, **Then** the first event is an
   `accepted` event carrying the request reference, emitted exactly once and before any content or
   terminal event.
7. **Given** a stream that is open but receiving no content events, **When** a heartbeat is pushed into
   the framing, **Then** it is framed as neither content nor terminal. (A6 owns heartbeat framing;
   autonomous idle emission is D4's broker.)
8. **Given** a stream whose request completes, **When** it ends, **Then** it ends with exactly one
   `completed` terminal event carrying the validated result, and no second terminal event.
9. **Given** a stream whose request fails, **When** it ends, **Then** it ends with exactly one `failed`
   terminal event carrying a §5.4 taxonomy code, and no second terminal event.
10. **Given** a stream whose client closes mid-stream (`reader.cancel()`, `request.signal` abort, or
    already-aborted at entry), **When** the request is aborted, **Then** `terminalEmitted` is marked
    and no `cancelled` event is enqueued onto the dead socket; the one-terminal-event invariant still
    holds against later sink pushes.
11. **Given** a stream that has already emitted a terminal event, **When** any further completion,
    failure, or abort path is taken, **Then** no additional terminal event is emitted — the
    one-terminal-event invariant holds under every path.
12. **Given** a call into the adapter with no injected `eventSource`, **When** the handler runs,
    **Then** it fails fast with HTTP 503 and opens no stream (Worker live route fails fast until D4).

### Edge Cases

- **An oversized body is rejected before any other work.** A request whose body exceeds the ingress
  body-size limit (UTF-8 bytes; `Content-Length` pre-check when present; otherwise stream-read abort
  at first oversize chunk; never buffer past the cap) is rejected as `request_too_large` (HTTP 413)
  at stage 1, before headers are handled, before a stream opens, and before a reference is generated
  (§6.1 stage 1; §5.4). The 413 body carries empty `request_reference` and empty `trace_id` (FR-006
  stage-1 exception). Oversized + malformed headers still yield 413. A test asserts no later stage
  runs and no `accepted` event is emitted for an oversized body. This is the transport-level ingress
  gate; the per-capability and per-key size bounds declared in the manifest, and the cost
  pre-flight `request_too_large` at stage 7, belong to C2 and are out of scope here.
- **A malformed request never reaches the taxonomy.** A malformed body (JSON parse failure, or parsed
  value that is not a non-null plain object), or a malformed, missing, empty, or whitespace-only
  required header, is rejected by the adapter's own parsing with bare HTTP 422; it never produces a
  taxonomy-coded error body, and no taxonomy code maps to a bare `400` (§5.4). A test asserts a
  malformed request yields no taxonomy-coded body and does not open a stream.
- **`cancelled` / `499` is never written to a live socket.** A cancellation happens by the client
  closing the stream, so there is nobody left to receive a response; on `ReadableStream` `cancel()`,
  `request.signal` abort, and already-aborted at entry the adapter marks `terminalEmitted` only and
  never enqueues `cancelled`. `499` is the value journaled for the terminal state and returned in the
  body of a later "get request" lookup (which is itself a `200`), not an HTTP status emitted on the
  stream (§5.4, §5.5 rule 5). A test asserts `cancelled` is not emitted as an HTTP status on the
  stream and that real disconnect paths do not write to the dead socket. The journaled `499` and the
  `200` lookup are C3's contract, referenced here, not run at A6.
- **No duplicate terminal event under any path.** A stream that has already emitted a terminal event
  must not emit a second one — whether completion, failure, abort, or a duplicate close arrives
  afterwards (§5.5 rule 4). A test asserts each path produces exactly one terminal event.
- **`accepted` is emitted exactly once and first.** The opening event carries the request reference so
  the user has a support handle even if everything after this fails; it precedes any content or
  terminal event and is not repeated (§5.5 rule 1). A test asserts the first event is `accepted`,
  carried exactly once.
- **Heartbeats are neither content nor terminal.** Heartbeat framing is A6's; autonomous idle emission
  is D4's. Heartbeats carry no content and are not a terminal event (§5.5 rule 3). A test asserts an
  injected heartbeat is framed correctly and does not satisfy the one-terminal-event invariant.
- **The `accepted` reference and the trace id come from A2.** A6 emits the reference A2 generates and
  the trace id A2 propagates (any non-empty client string via `resolveTraceId`; ULID only when
  absent); it does not redefine either. A test asserts the `accepted` event's reference matches A2's
  format and the trace id on every emitted event matches the parsed (or A2-generated) value.
- **No per-request state.** Cancellation is connection-scoped: the request is cancelled by closing the
  stream, with no separate endpoint and no cross-invocation state (§5.5 Cancel row; §4.3.10). The
  `terminalEmitted` flag is connection-scoped only. Out-of-band cancellation is deliberately not
  supported (§9.7). A test asserts closing the stream cancels the request with no state object created.
- **Missing `eventSource` fails fast.** Without an injected event source the adapter returns HTTP 503
  and opens no stream; production stubs do not ship in `src/adapter.ts`.

### Test plan

Layer: Integration (Delivery Plan §3.11.1 A6). Per §13.5, pipeline-stage and cancellation behaviour is
exercised deterministically against a fake/stub event source; no real provider is involved. The suite
in `ai-platform/test/adapter.test.ts` has **33 tests** covering real `reader.cancel()`, already-aborted
and signal abort, `Content-Length`, multi-byte UTF-8, malformed body, empty/whitespace headers,
non-ULID trace, 503 without `eventSource`, and connection-scoped terminal flag.

| #  | Test | Layer | Source |
| -- | --- | --- | --- |
| T1 | A request body exceeding the ingress body-size limit (UTF-8 bytes; Content-Length and streaming paths) is rejected as `request_too_large` (HTTP 413, A2 error body with empty correlation fields) before any other work — including when headers are also malformed (413 not 422); no header handled, no stream opened, no reference generated | Integration | §4.3.1; §6.1 stage 1; §5.4; §3.11.1 A6 |
| T2 | The idempotency-key header is parsed from a well-formed request and made available to later stages | Integration | §4.3.1; §3.11.1 A6 |
| T3 | The client-trace-id header is parsed and propagated (any non-empty string, including non-ULID); when absent, A2's gateway-generated ULID trace id is used | Integration | §4.3.1; §13.1; §3.11.1 A6 |
| T4 | The capability-version-pin header is parsed and made available to the capability resolver (a later stage) | Integration | §4.3.1; §3.11.1 A6 |
| T5 | A malformed body, or a malformed/missing/empty/whitespace required header (idempotency key, trace id, or version pin), is rejected by the adapter's own parsing with bare HTTP 422, produces no taxonomy-coded error body, and opens no stream | Integration | §4.3.1; §5.4; §3.11.1 A6 |
| T6 | A stream opens with an `accepted` event carrying the request reference, emitted exactly once and before any content or terminal event | Integration | §5.5 rule 1; §3.11.1 A6 |
| T7 | An injected heartbeat event is framed while the stream is idle and receives no content; the heartbeat is neither content nor a terminal event (autonomous emission is D4) | Integration | §5.5 rule 3; §3.11.1 A6 |
| T8 | A stream whose request completes ends with exactly one `completed` terminal event and no second terminal event | Integration | §5.5 rule 4; §3.11.1 A6 |
| T9 | A stream whose request fails ends with exactly one `failed` terminal event carrying a §5.4 taxonomy code, and no second terminal event | Integration | §5.5 rule 4; §3.11.1 A6 |
| T10 | Real disconnect paths (`reader.cancel()`, already-aborted, signal abort) mark `terminalEmitted` without enqueueing `cancelled` on the dead socket; stub abort still yields exactly one `cancelled` terminal without writing `cancelled`/`499` as an HTTP status | Integration | §5.5 rules 4–5; §5.4; §3.11.1 A6 |
| T11 | A stream that has already emitted a terminal event does not emit a second one under any subsequent path (completion, failure, abort, duplicate close); `terminalEmitted` is connection-scoped with no per-request state object | Integration | §5.5 rule 4; §3.11.1 A6 |
| T12 | The `accepted` event's request reference matches A2's `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` format, and the trace id on every emitted event matches the parsed or A2-generated value | Integration | §8.9; §13.1; §5.5 rule 1; A2 |
| T13 | Missing injected `eventSource` returns HTTP 503 and opens no stream | Integration | review resolution A6 |

## Requirements

### Functional Requirements

- **FR-001**: The protocol adapter MUST own the wire format and nothing else — request parsing, size
  limits, header handling (idempotency key, client trace id, capability version pin), SSE framing for
  streaming responses, and translation of the internal error taxonomy to HTTP status codes plus a
  stable error body (§4.3.1). The adapter MUST require an injected `eventSource`; when missing it
  MUST fail fast with HTTP 503 and open no stream. Production stubs MUST NOT live in `src/adapter.ts`.
- **FR-002**: The adapter MUST parse the request and enforce the ingress size limit at stage 1, before
  the manifest is resolved; measurement MUST be UTF-8 byte-accurate. When `Content-Length` exceeds the
  limit the adapter MUST reject before consuming the body; otherwise it MUST stream-read and abort at
  the first oversize chunk and MUST NOT buffer past the cap. A request whose body exceeds the ingress
  body-size limit MUST be rejected as `request_too_large` (HTTP 413) before any other work — before
  header handling, before any stream is opened, before any reference is generated — including when
  headers are also malformed (§4.3.1; §6.1 stage 1; §5.4).
- **FR-003**: The adapter MUST parse the idempotency key, the client trace id, and the capability
  version pin from the request headers. Any non-empty client-supplied trace id MUST be accepted via
  A2 `resolveTraceId`; a ULID MUST be generated only when the header is absent — there is no
  ULID-only client constraint (§4.3.1; §13.1; A2).
- **FR-004**: A malformed request body (JSON parse failure, or a value that is not a non-null plain
  object), or a malformed, missing, empty, or whitespace-only required header, MUST be rejected by
  the adapter's own parsing with bare HTTP 422 and MUST NOT reach the taxonomy; it MUST NOT produce a
  taxonomy-coded error body, and no taxonomy code maps to a bare `400` (§4.3.1; §5.4). Bare 422 for
  adapter-local parse failures is intentional.
- **FR-005**: The adapter MUST translate the internal error taxonomy to HTTP status codes using the
  §5.4 HTTP column, which is normative and is the only translation it may apply; the taxonomy code
  carried in the error body — not the HTTP status — is what clients branch on (§4.3.1; §5.4).
- **FR-006**: Every taxonomy-coded error response the adapter emits MUST carry the request reference,
  the trace id, and whether a retry is safe, in A2's error-body contract
  `{"code","request_reference","trace_id","retry_safe"}` (§5.4; A2). **Stage-1 exception:** the
  ingress oversized-body 413 response carries empty `request_reference` and empty `trace_id` because
  the gate runs before headers are handled and before a reference is generated.
- **FR-007**: A stream MUST open with an `accepted` event carrying the request reference, so the user
  has a support handle even if everything after this fails; the `accepted` event is emitted exactly
  once and before any content or terminal event (§5.5 rule 1).
- **FR-008**: The SSE framing MUST carry an explicit event type on every content event (§5.5 rule 2).
  The content-event kind vocabulary is owned by the canonical inference representation (A3) and is
  relayed by the stream broker (D4); A6 provides the framing only and does not define content kinds.
- **FR-009**: Heartbeat framing MUST treat a heartbeat as neither a content event nor a terminal
  event (§5.5 rule 3). A6 owns the wire framing; autonomous idle heartbeat emission is owned by D4's
  stream broker.
- **FR-010**: Exactly one terminal event MUST end every stream: `completed` with the validated result,
  `failed` with a §5.4 taxonomy code, or `cancelled`. A terminal event MUST NOT be inferred from
  silence, and the framing MUST guarantee exactly one terminal event per stream under every path,
  including abort (§5.5 rule 4).
- **FR-011**: Closing the stream MUST cancel the request and end it as `cancelled`; cancellation is
  connection-scoped, with no separate endpoint and no cross-invocation state. On `ReadableStream`
  `cancel()`, `request.signal` abort, and already-aborted at entry, the adapter MUST mark
  `terminalEmitted` only and MUST NEVER enqueue a `cancelled` event onto the dead socket.
  `cancelled` / `499` MUST NOT be written to a live socket as an HTTP status; `499` is the value
  journaled for the terminal state and returned in the body of a later "get request" lookup
  (§5.5 rule 5, Cancel row; §5.4).
- **FR-012**: The adapter MUST NOT emit a second terminal event after one has been emitted (or after
  cancellation has marked `terminalEmitted` without enqueueing), under any path (§5.5 rule 4).

### Key Entities

Not applicable — this slice defines no D1 entities and no contract types. The canonical
request/stream-chunk/result/error types are A3's; the error body and request-reference format are
A2's. A6 consumes those contracts and emits them on the wire.

## Constitution Alignment

### Architecture & Operations Impact

- **Clinic Fit**: This slice serves small-to-mid-size multi-branch clinics by giving every AI request a
  single, provider-independent wire shape and a streaming protocol that a thin client can consume. No
  enterprise-scale assumption is introduced; the framing is the same for one clinic or many.
- **Layer Placement**: This slice touches `ai-platform/` (the Cloudflare Worker) only — specifically the
  protocol adapter (`§4.3.1`) and the streaming protocol (`§5.5`). It touches neither `backend/`
  (Supabase) nor `frontend/` (Flutter). Per the §14 acknowledgement, the gateway is a non-primary,
  additive component: it holds no domain logic, no business data, and has no write path into Supabase;
  this slice stays inside that boundary — it owns the wire format and the SSE framing, and nothing
  else.
- **Data Integrity & Security**: A6 writes no business data and no D1. The headers it parses
  (idempotency key, trace id, version pin) are non-secret corrosion handles; provider credentials and
  prompt text never pass through the adapter from the client. Structured logs the adapter emits MUST
  NOT carry prompts, context, or credentials (§13.1); the trace id and request reference are the only
  correlation it adds.
- **Failure Handling**: The framing itself is the failure contract for the stream: every stream opens
  with a support handle (`accepted`) and ends with exactly one terminal event, so a later client can
  always tell success from failure from cancellation, and a dropped connection ends `cancelled` rather
  than hanging. A6 introduces no runtime degradation behaviour of its own — that belongs to the client
  (E4) and the guard (B3).

## Out of Scope

- **Neighbouring slices this one touches:**
  - **A2** (consumed): the error taxonomy, the error body, the request-reference generator, and the
    trace-id contract. A6 applies and emits them; it does not alter them. Changing any is out of scope
    by definition.
  - **A3 / D2 / D4** — content event chunk kinds (`text_delta`, `partial_structured`, `usage`,
    `provider_note`) and the stream broker that relays normalized chunks, enforces provisional
    semantics, wires the in-flight provider-fetch abort signal, credits partial usage on cancel, and
    autonomously emits idle heartbeats. A6 provides the SSE framing (including heartbeat wire shape)
    and the one-terminal-event invariant; the broker behaviour that operates within that framing is
    D4.
  - **C3** — Journal writer and get-request endpoint: the `cancelled` / `499` journaled terminal
    state and the `200` get-request lookup that returns `cancelled` in its body are C3's contract.
    A6 emits the terminal event kind; persistence and lookup are C3.
  - **C2** — Context validator and cost pre-flight: the per-capability and per-key size bounds declared
    in the manifest, and the cost pre-flight `request_too_large` at stage 7. A6 owns only the
    transport-level ingress body-size gate at stage 1; the manifest-derived bounds and the stage 7
    rejection are C2.
  - **H1** — Conversational manifest fields and the `context_requested` fourth terminal event kind.
    A6 realises the three `single_shot` terminal kinds (`completed`, `failed`, `cancelled`); the
    fourth kind is added by H1, which extends a framing A6 freezes rather than rewriting it.
  - **E2** — AI Client SDK: transport retries of the submit, AAT acquisition, and consuming the event
    stream are the client's job. A6 defines the wire the SDK consumes; it does not implement the SDK.

- **Prohibitions (Delivery Plan §6.4) — none are added here, and all are observed:**
  - No mechanism from §9.14 is added because it looks prudent (R-20). In particular, out-of-band
    cancellation and stream resume (§9.7) are deliberately not supported, and a WebSocket transport
    (§4.3.1 notes a future transport) is not introduced.
  - No prompt text, provider name, or model identifier is placed in the Flutter client (R-12) — A6
    touches no client code.
  - No second Quota Durable Object round trip and no second R2 object per request is introduced
    (§7.5, §13.6) — A6 does neither.
  - No guard rejection is journaled as a request, and no D1 row per stream chunk is written (§7.5) —
    A6 writes no D1 and emits no per-chunk row.
  - No per-request server-side state of any kind is introduced (§4.4, §9.7) — cancellation is
    connection-scoped (§5.5 Cancel row; §4.3.10); no per-request state object is created.
  - No client-side assembly of a final result from chunks, and no committable provisional content
    (§6.4, A5) — A6 defines framing only; provisional semantics belong to the broker (D4).

- **No additional error handling, retries, caching, abstraction, or configurability** beyond the cited
  sections is introduced (R-20). In particular: no transport-level retry of the submit (retry is the
  SDK's, E2); no stream-resume or reconnect (§9.7, deferred); no content-event kind vocabulary beyond
  the framing (kinds are A3, relay is D4); and the ingress body-size limit is a transport
  configuration value supplied to the adapter, not a number this spec authors — the per-capability
  bounds are C2's.

## Success Criteria

- **SC-001**: A request whose body exceeds the ingress body-size limit (UTF-8 bytes) is rejected as
  `request_too_large` (HTTP 413, empty correlation fields) before any other work — including when
  headers are also malformed — no header handled, no stream opened, no reference generated —
  provable by T1.
- **SC-002**: The idempotency key, client trace id (any non-empty string), and capability version pin
  headers are each parsed from a well-formed request, and a malformed body or
  malformed/missing/empty/whitespace required header is rejected with bare 422 without reaching the
  taxonomy — provable by T2–T5.
- **SC-003**: Every stream opens with exactly one `accepted` event carrying an A2-format request
  reference, before any content or terminal event — provable by T6 and T12.
- **SC-004**: An injected heartbeat is framed as neither a content nor a terminal event — provable by
  T7. (Autonomous idle emission is D4.)
- **SC-005**: Every stream ends with exactly one terminal event for each of `completed`, `failed`, and
  `cancelled` (stub path); real disconnect marks `terminalEmitted` without dead-socket enqueue; abort
  mid-stream still yields exactly one terminal semantic; and no duplicate terminal event appears under
  any path — provable by T8–T11.
- **SC-006**: Missing injected `eventSource` fails fast with HTTP 503 — provable by T13.

## Assumptions

- The Worker skeleton, its three environments, and its bindings already exist from A1, and the
  diagnostic envelope (error taxonomy, error body, request-reference generator, trace-id contract)
  already exists from A2; A6 adds the adapter and SSE framing to that Worker and provisions no
  infrastructure.
- A6 is exercised against a deterministic stub event source in the test harness
  (`test/adapter.test.ts` + `test/helpers/adapter-stub.ts`); no real provider is involved. The
  adapter requires injected `eventSource` and fails fast (503) without one — the Worker live route
  fails fast until D4. The broker behaviours that consume this framing — chunk relay, provisional
  semantics, provider-fetch abort on disconnect, partial-usage credit, and autonomous heartbeat
  emission — are D4 and are not implemented here.
- The ingress body-size limit is a transport configuration value supplied to the adapter; the specific
  number is a deployed-config value, not authored by this spec. The per-capability and per-key size
  bounds declared in the manifest, and the stage 7 cost pre-flight `request_too_large`, are C2's.
- The platform does not ship until the whole product does (DP-1); "independently testable" means
  provable by an automated test, not demonstrable to a user (DP-3).
