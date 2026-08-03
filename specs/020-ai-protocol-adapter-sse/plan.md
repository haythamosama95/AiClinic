# Implementation Plan: Protocol adapter and SSE framing (A6)

**Branch**: `ai/020-a6-protocol-adapter-sse` | **Date**: 2026-07-31 | **Spec**: [`spec.md`](spec.md)

**Input**: Feature specification from `/specs/020-ai-protocol-adapter-sse/spec.md`

## Summary

A6 owns the gateway's wire format and nothing else: request parsing, the ingress body-size gate,
header handling (idempotency key, client trace id, capability version pin), SSE event framing
(`accepted`, heartbeat, terminal events), translation of A2's error taxonomy to HTTP on the wire,
and connection-scoped cancellation. It is the last slice of Band A and the subject of review
checkpoint **CP1** ("Do the frozen contracts compose at build time?"). Every later slice that submits
or consumes a stream (D4 the stream broker, E2 the AI Client SDK, H1 the conversational fourth
terminal kind) binds to the framing and header set this slice freezes (Delivery Plan §3.2 row A6).

## Technical Context

**Language/Version**: TypeScript 5.9 on the Cloudflare Workers runtime; Node ≥ 22 for tooling
(`ai-platform/package.json`).

**Primary Dependencies**: `cloudflare:workers` (`DurableObject`, `env`), `@cloudflare/workers-types`
4.x, Vitest ~3.2 with `@cloudflare/vitest-pool-workers` 0.8.

**Storage**: N/A — A6 writes no D1, no R2, no Durable Object state (spec Key Entities: "Not
applicable"; §4.3.1 owns the wire format only). The ingress body-size limit is a transport
configuration value supplied to the adapter; the adapter reads it, the plan binds it to a
test-injectable constant, and no number is authored here (spec Assumptions; Clarification Q1).

**Testing**: `npx vitest run test/adapter.test.ts` — integration layer (§13.5 "Pipeline tests: stage
ordering, guard rejection paths, cancellation on disconnect — fake provider adapter, deterministic").
A small in-process stub injects canned `accepted`, heartbeat, and terminal sequences directly into
the adapter's event sink — no broker, no provider, no network (Clarification Q2).

**Target Platform**: Cloudflare Workers — `ai-platform/` at the repository root (Delivery Plan §7.1).

**Project Type**: Gateway Worker module — an additive, non-primary, always-optional deployable (§14
acknowledgement).

**Performance Goals**: Stage 1 (ingress and shape) completes in microseconds with no I/O — an
oversized or malformed request is rejected before any header is handled, before the stream opens,
before a reference is generated (§6.1 stage 1; spec FR-002). Worker wall time is unlimited while
the client is connected; the one-terminal-event guard is a state machine, not a timer (§1.4).

**Constraints**: One §4 component (§4.3.1). No per-request server-side state of any kind (§4.4, §9.7);
cancellation is connection-scoped — closing the stream cancels the request, with no separate endpoint
and no cross-invocation state (§5.5 Cancel row; §4.3.10). No second Quota Durable Object round trip, no
second R2 object, no journal row, no D1 row per chunk (§7.5, §13.6). No prompt text, provider name, or
model identifier in the client (R-12) — A6 touches no client code.

**Scale/Scope**: One new source module, one modified source module, one new test file, one
`contracts/` artifact documenting the frozen framing, and this directory's `quickstart.md`. The slice
holds the ingress gate, three parsed headers, the SSE event vocabulary, the one-terminal-event
invariant, and connection-scoped cancellation — well within the 25-task sizing guidance.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified** — the framing is
      provider-independent and identical for one clinic or many; no enterprise-scale assumption is
      introduced (spec Constitution Alignment → Clinic Fit).
- [x] **Design keeps a simple operational model with no microservices, message queues, Kubernetes, or
      custom primary backend service** — one Worker module, synchronous, no queues; out-of-band
      cancellation and stream resume (§9.7) and a WebSocket transport (§4.3.1 future note) are
      deliberately not introduced (spec Out of Scope; R-20).
- [x] **Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend
      capabilities, PostgreSQL owns domain integrity, and AI stays isolated** — A6 touches
      `ai-platform/` only; neither `frontend/` nor `backend/` is modified (spec Layer Placement).
- [x] **Protected writes, validation, permissions, and transactional rules remain enforced through
      PostgreSQL constraints, triggers, RLS, or RPC functions** — A6 writes no database of any kind;
      the gateway holds no domain logic and no business data (§14 acknowledgement).
- [x] **Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable,
      and soft-delete-preserving** — A6 parses non-secret correlation headers only (idempotency key,
      trace id, version pin); provider credentials and prompt text never pass through the adapter
      from the client; structured logs carry no prompts, context, or credentials (§13.1; spec Data
      Integrity & Security). Authentication and scoping are later stages (B3, §4.3.2–§4.3.3), not A6.
- [x] **AI actions remain human-approved, have no direct database/backend access, and the feature
      still works in a degraded manual mode when AI is unavailable** — A6 owns framing only; the
      framing guarantees every stream opens with a support handle (`accepted`) and ends with exactly
      one terminal event, so a dropped connection ends `cancelled` rather than hanging. Runtime
      degradation behaviour belongs to the client (E4) and the guard (B3), not A6.

**§14 acknowledgement (gateway slices):** The Worker A6 extends is an additive, non-primary
deployable component. It holds **no domain logic, no business data, and no write path into
Supabase**, and it is **always optional** — if it vanishes, no business rule is lost (spec
Constitution note). A6 introduces the wire-format module and the SSE framing only, so it stays
squarely inside that boundary.

## Project Structure

### Documentation (this feature)

```text
specs/020-ai-protocol-adapter-sse/
├── spec.md               # /ai-platform-specify output (authoritative)
├── plan.md               # This file (/ai-platform-plan output)
├── contracts/
│   └── sse-framing.md    # The frozen SSE event vocabulary, header set, and terminal-event
│                         #   invariant — D4, E2, and H1 bind to this in their Consumes
└── quickstart.md         # What A6 implemented, files to review, and how to validate in CI
```

No `data-model.md` — A6 defines no D1 entities (spec Key Entities: "Not applicable").
No `research.md` — the research is `17-ai-platform.md` and redoing it is how architecture drift starts
(Delivery Plan §6.1).

`contracts/sse-framing.md` is produced because A6's **Freezes** establish wire shapes a later slice's
**Consumes** must bind to: the SSE event vocabulary (`accepted`, heartbeat, the three `single_shot`
terminal kinds), the header set (`x-idempotency-key`, `x-trace-id`, `x-capability-version`), and the
one-terminal-event invariant. D4 (stream broker) relays events within this framing; E2 (AI Client
SDK) consumes the stream this framing defines; H1 (conversational) extends it with a fourth terminal
kind. A later slice's **Consumes** must bind to a frozen artifact, not to prose.

### Source Code (repository root)

```text
ai-platform/                          # existing — created by A1
├── src/
│   ├── worker.ts                      # MODIFIED: replace the placeholder POST /v1/requests JSON
│   │                                  #   handler with the real SSE adapter; health endpoint unchanged
│   ├── adapter.ts                     # NEW: the §4.3.1 protocol adapter — request parsing, ingress
│   │                                  #   body-size gate, header parsing, SSE event framing,
│   │                                  #   error-to-HTTP translation, one-terminal-event guard,
│   │                                  #   connection-scoped cancellation (FR-001–012)
│   ├── errors.ts                      # existing (A2) — consumed: buildErrorBody, liveHttpStatusForCode
│   ├── reference.ts                   # existing (A2) — consumed: generateRequestReference
│   ├── trace.ts                       # existing (A2) — consumed: resolveTraceId, createStructuredLogger
│   └── contracts/
│       └── canonical.ts               # existing (A3) — consumed: CanonicalChunkKind (content-event kinds
│                                      #   the framing carries; A6 provides framing only, not content)
└── test/
    └── adapter.test.ts                # NEW: T1–T12 (integration, §13.5)
```

**Structure Decision**: The gateway lives in `ai-platform/` at the repository root as a sibling of
`frontend/` and `backend/` (Delivery Plan §7.1). A1 created this directory; A2 added the diagnostic
contract modules (`errors.ts`, `reference.ts`, `trace.ts`) and A3 added the canonical types
(`contracts/canonical.ts`). A6 adds one new source module (`adapter.ts`) and modifies the existing
`worker.ts` fetch path to wire it in. No `frontend/` or `backend/` path is touched. The adapter is a
single module because §4.3.1 is one component and the framing invariants (open/heartbeat/terminal,
exactly-one, abort) are inseparable from the request parsing that gates them; splitting them would
introduce an abstraction the architecture does not name (D-15, R-20). The content-event kind
vocabulary is A3's, imported and framed but not relaid — the relay is D4.

## Consumes Binding

A6 has `Needs: A2` (Delivery Plan §3.2). It consumes the diagnostic contracts A2 froze.

| Consumes entry | Binds to | Status |
| --- | --- | --- |
| A2 — The error taxonomy (§5.4): closed code set, normative HTTP mapping, `internal_error` fallback | `ai-platform/src/errors.ts` — `TaxonomyCode` union, `TAXONOMY` table, `classifyErrorCode`, `getTaxonomyEntry`, `liveHttpStatusForCode` (returns `null` for `cancelled`) | Exists, created by A2 on `ai/016-a2-diagnostic-envelope`. A6 translates these to HTTP on the wire via the adapter; it adds no codes and changes no statuses. |
| A2 — The error-body contract `{"code","request_reference","trace_id","retry_safe"}` | `ai-platform/src/errors.ts` — `buildErrorBody(input: ErrorBodyInput): ErrorBody`, `ErrorBody` interface | Exists. A6's error responses emit this body. A6 does not alter the shape. |
| A2 — The request-reference generator and format `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` | `ai-platform/src/reference.ts` — `generateRequestReference(): string` | Exists. A6's `accepted` event carries the reference this produces. A6 does not redefine the generator. |
| A2 — The trace-id propagation contract: client-generated, gateway-generated ULID when absent, on every log line | `ai-platform/src/trace.ts` — `resolveTraceId(supplied: string \| null \| undefined): string`, `createStructuredLogger(context)` | Exists. A6 parses the `x-trace-id` header (the name A2 established in `worker.ts`), calls `resolveTraceId`, and propagates the result to every emitted event and log line. |

No Consumes entry has a missing implementation (stop condition 2 not triggered).

## Components Touched

A6 touches **one** §4 component: **§4.3.1 Protocol adapter**.

§4.3.1 "owns the wire format and nothing else: request parsing, size limits, header handling
(idempotency key, client trace id, capability version pin), SSE framing for streaming responses, and
translation of the internal error taxonomy to HTTP status codes plus a stable error body." A2 produced
the taxonomy-to-HTTP translation table and the error-body builder; A3 produced the canonical
content-event kinds. A6 is the slice that emits them on the wire: it parses the request, gates the
body size, reads the three headers, frames the SSE events, applies the §5.4 HTTP column via A2's
`liveHttpStatusForCode`, emits A2's `buildErrorBody` in every error response, and guarantees the
one-terminal-event invariant and connection-scoped cancellation from §5.5.

No other §4 component is modified. The stream broker (§4.3.10) relays chunks within the framing A6
freezes but is D4; the journal writer (§4.3.11) persists the terminal state A6 emits but is C3; the
identity/tenant stage (§4.3.2), entitlement/quota (§4.3.3), capability resolver (§4.3.4), context
validator (§4.3.5), and cost pre-flight (§6.1 stage 7) are later guard stages that run after the
adapter's ingress gate. Stop condition 5 is not triggered.

## Files

| Path | Created / Modified | Traced to |
| --- | --- | --- |
| `ai-platform/src/adapter.ts` | Created | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012 |
| `ai-platform/src/worker.ts` | Modified — replace the placeholder `POST /v1/requests` JSON handler with the real SSE adapter; `/health` route and `GatewayObject` DO class unchanged | FR-001, FR-002, FR-007, FR-010, FR-011 |
| `ai-platform/test/adapter.test.ts` | Created | T1–T12 (Test plan) |
| `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md` | Created | Freezes (the SSE event vocabulary, header set, and one-terminal-event invariant, documented for D4/E2/H1's Consumes) |
| `specs/020-ai-protocol-adapter-sse/quickstart.md` | Created (during the Documentation task after implementation and verification) | Documentation |

## Test Layout

Layer: Integration (Delivery Plan §3.11.1 A6; §13.5 "Pipeline tests — fake provider adapter,
deterministic"). All twelve tests live in `ai-platform/test/adapter.test.ts` and are run with
`npx vitest run test/adapter.test.ts`. The adapter is exercised against a small in-process stub event
source that injects canned `accepted`, heartbeat, and terminal sequences directly into the adapter's
event sink — no broker (D4), no provider (D2), no network (Clarification Q2). The oversized-request
fixture (T1) reads the same ingress body-size config value the adapter uses and builds a body one
byte larger, asserting only the relation "body just over the limit" (Clarification Q1).

| Test | Layer (§13.5) | What it asserts | File |
| --- | --- | --- | --- |
| T1 | Integration | A body exceeding the ingress body-size config value is rejected as `request_too_large` (HTTP 413, A2 error body) before any other work — no header handled, no `accepted` event, no reference generated | `ai-platform/test/adapter.test.ts` |
| T2 | Integration | The `x-idempotency-key` header is parsed and made available to later stages | `ai-platform/test/adapter.test.ts` |
| T3 | Integration | The `x-trace-id` header is parsed and propagated; when absent, A2's `resolveTraceId` ULID is used | `ai-platform/test/adapter.test.ts` |
| T4 | Integration | The `x-capability-version` header is parsed and made available to the capability resolver (a later stage) | `ai-platform/test/adapter.test.ts` |
| T5 | Integration | A malformed or missing required header (idempotency key, trace id, or version pin) is rejected by the adapter's own parsing, produces no taxonomy-coded error body, and opens no stream | `ai-platform/test/adapter.test.ts` |
| T6 | Integration | A stream opens with an `accepted` event carrying an A2-format request reference, emitted exactly once and before any content or terminal event | `ai-platform/test/adapter.test.ts` |
| T7 | Integration | A heartbeat event is emitted while the stream is idle and receives no content; the heartbeat is neither content nor a terminal event | `ai-platform/test/adapter.test.ts` |
| T8 | Integration | A stream whose request completes ends with exactly one `completed` terminal event and no second terminal event | `ai-platform/test/adapter.test.ts` |
| T9 | Integration | A stream whose request fails ends with exactly one `failed` terminal event carrying a §5.4 taxonomy code, and no second terminal event | `ai-platform/test/adapter.test.ts` |
| T10 | Integration | A stream whose client closes mid-stream ends with exactly one `cancelled` terminal event, and `cancelled`/`499` is not written to the live socket as an HTTP status | `ai-platform/test/adapter.test.ts` |
| T11 | Integration | A stream that has already emitted a terminal event does not emit a second one under any subsequent path (completion, failure, abort, duplicate close) | `ai-platform/test/adapter.test.ts` |
| T12 | Integration | The `accepted` event's request reference matches A2's `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` format, and the trace id on every emitted event matches the parsed or A2-generated value | `ai-platform/test/adapter.test.ts` |

## Sequencing

Tests land alongside implementation, unit by unit, never after. The order follows the dependency
chain inside the adapter: the ingress gate and header parsing are testable before any stream opens;
the SSE framing and the one-terminal-event guard are testable with the stub once the event sink
exists; cancellation is tested last because it closes the framing loop.

1. **`adapter.ts` — ingress gate + header parsing (T1–T5).** The adapter reads the body, enforces the
   ingress body-size limit (a test-injectable constant), parses the three headers, and rejects
   oversized or malformed requests with A2's error body and §5.4 HTTP mapping before any other work.
   T1–T5 are written alongside this and pass. (FR-001–FR-006)
2. **`adapter.ts` — SSE event framing + `accepted` opening (T6, T12).** The event vocabulary
   (`accepted`, heartbeat, `completed`, `failed`, `cancelled`), the SSE encoding, the event sink, and
   the `accepted` opening carrying A2's reference are implemented. T6 and T12 pass. (FR-007, FR-008)
3. **`adapter.ts` — heartbeat (T7).** The idle-heartbeat emission is implemented against the stub.
   T7 passes. (FR-009)
4. **`adapter.ts` — terminal events + one-terminal-event guard (T8, T9, T11).** The state machine
   that emits exactly one terminal event and refuses a second is implemented. T8, T9, T11 pass.
   (FR-010, FR-012)
5. **`adapter.ts` — connection-scoped cancellation (T10).** The client-disconnect → `cancelled`
   path is implemented; `499` is never written to the live socket. T10 passes. (FR-011)
6. **`worker.ts` wiring.** The placeholder `POST /v1/requests` handler is replaced with a call into
   the adapter; the `/health` route and `GatewayObject` are untouched. T1–T12 still pass against the
   wired adapter. (FR-001, FR-002, FR-007, FR-010, FR-011)
7. **Documentation task.** `contracts/sse-framing.md` documents the frozen event vocabulary, header
   set, and one-terminal-event invariant for D4/E2/H1's Consumes, and `quickstart.md` is filled per
   the `ai-platform-quickstart-template` (files to review, slice-only suite invocation, focused
   inspection). No manual-validation section — CI is the only verification path (the framing is
   exercised by the stub, not by a live deployment).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. All six Constitution Check boxes are ticked. The §14 acknowledgement is recorded above.