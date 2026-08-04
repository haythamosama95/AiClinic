# Implementation Plan: Stream broker, prose streaming, and cancellation

**Branch**: `ai/031-d4-stream-broker` | **Date**: 2026-08-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/031-stream-broker/spec.md`

## Summary

Slice D4 freezes the stream broker: after D3's invocation loop produces normalized chunks against the fake provider, the gateway relays them over A6's SSE framing for `prose` (`text_delta` in order), emits heartbeats during provider silence, applies incremental cheap guards and a completion-time full guard set so `completed` carries the validated payload, and cancels by observing client disconnect — aborting the in-flight provider fetch via its abort signal, terminating as `cancelled`, and crediting partial usage — with no per-request server-side state. D4 sits after A6 and D3 in band D and is the streaming/cancel boundary that D6 (structured modes), E4 (first surface / CP3), and H1 (`context_requested`) consume.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime, `compatibility_date` 2026-05-03). No new language or runtime version is introduced.

**Primary Dependencies**: The Cloudflare Worker in `ai-platform/` (Wrangler bundler, Vitest). No new external package is added. Consumes A6's `adapter.ts` SSE framing and D3's `invocation/` attempt-loop output unchanged. Quota credit (B4) and journal terminal recording (C3) are invoked only through injectable sinks in this slice's tests (Clarification Q4); production modules are not modified.

**Storage**: None. The broker is connection-scoped and creates no per-request Durable Object, request registry, or D1 row per chunk (§4.3.10; §9.7; delivery plan §6.4). D4 adds no D1 migration, no R2 write, and no second Quota DO round trip. Partial-usage credit uses B4's existing credit call shape via an injectable sink; journal completeness is asserted against an injectable terminal sink (Clarification Q4). C3's writer and B4's credit module are not modified.

**Testing**: Vitest (`npx vitest run`). All named tests are Integration (spy) (delivery plan §3.11.4 row D4; §13.5 Pipeline tests with fake provider). No live provider, no Cloudflare resource, and no HTTP path beyond A6 framing helpers used as the client sink. Heartbeat tests inject a controllable ticker (Clarification Q2). Cancel tests close the client stream and assert the broker-owned `AbortSignal` is aborted (Clarification Q3). T10/T11 assert on in-memory credit and journal-terminal sinks (Clarification Q4).

**Target Platform**: Cloudflare Worker (`ai-platform-gateway`). No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway component. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase.

**Performance Goals**: Stream relay is in-isolate CPU plus the open client connection (§4.3.10; §6.1 stage 12). No second Quota DO round trip, no second R2 object, no D1 row per chunk (§7.5, §13.6; FR-012). Cancel credits partial usage through the existing single settle credit shape — it does not add a second credit trip beyond the platform's settle budget.

**Constraints**: Exactly one terminal event ends every broker path — `completed`, `failed`, or `cancelled` (§5.5 rule 4; FR-005). Closing the stream cancels; deliberate Cancel and network drop are the same path (§5.5 rule 5; FR-006). No separate cancel endpoint, no Session Durable Object, no stream resume, no out-of-band cancel (§4.3.10; §6.5; §9.7; FR-007, FR-010). Provisional `text_delta` chunks are not authoritative; only the validated terminal payload is (§6.4 invariants 1–2; FR-013). Structured / `structured_atomic` modes remain D6. Retry/fallback/`regenerating` remain D3 — the broker relays, it does not re-decide. No mechanism from §9.14 added because it looks prudent (R-20).

**Scale/Scope**: One sibling module under `ai-platform/src/` (`stream/` — prose `index.ts` + `prose-guards.ts`; `structured.ts` is D6-owned). One §4 component group touched (§4.3.10 — see Components Touched). Nineteen named integration (spy) tests (T1–T19) plus review-resolution T20–T27. Roughly 18–22 tasks for the original slice.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — connection-scoped cancel (close the stream) matches the only product need without a Session DO or cancel endpoint clinics would have to operate (spec Constitution Alignment → Clinic Fit; §9.7).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — D4 adds one in-isolate `stream/` module to the existing Worker; no new deployable, no store, no per-request state object.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — D4 touches only `ai-platform/`; prompt text, provider names, and model identifiers never enter the Flutter client (R-12; spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — D4 performs no write to Supabase and adds no D1 schema; journal terminal outcomes and Quota credit are fed through injectable sinks for later C3/B4 wiring; A5 schema and C3/B4 contracts are not altered.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — D4 is not inventing auth; cancel credits partial usage so quota cannot be evaded by disconnect (§6.5); the journal row from acceptance survives cancel so support can explain the request (§5.5 rule 6); guard aborts fail terminally with an existing A2 taxonomy code.
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — D4 holds no domain logic and no business data; provisional content is never the committed answer (FR-013); AI remains strictly additive (spec Constitution Alignment → Failure Handling).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. D4 adds no store, no Session DO, no second R2 object, and no per-request state; the broker is connection-scoped and consumes A6 framing and D3 invocation output without rewriting either.

## Project Structure

### Documentation (this feature)

```text
specs/031-stream-broker/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── stream-broker.md # Frozen broker relay, prose guards, heartbeat emission, cancel path, prohibitions
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`: (1) Architecture context — cites delivery plan §3.5 row D4 and `17-ai-platform.md` §4.3.10, §6.4, §5.5, §6.5, §9.7; (2) What was implemented — stream broker, prose incremental + full guards, heartbeat emission, connection-scoped cancel with abort signal and partial-usage credit; (3) Files to review — this slice's source and test files only; (4) Run the automated suite — `npx vitest run test/stream-broker.test.ts` (slice-only, no full-suite `npm test`); (5) Inspect the changes — the frozen contract under `contracts/` and the `stream/` module; (6) Manual validation omitted — CI is the only verification path (no behaviour beyond CI).

`contracts/stream-broker.md` freezes the stream broker's relay/heartbeat/one-terminal duties, the `prose` incremental and completion-time guard path with authoritative terminal payload, the broker-owned connection-scoped cancellation path (abort signal, `cancelled`, partial-usage credit, journal-terminal outcome), and the explicit non-support of out-of-band cancel / Session DO / stream resume. `data-model.md` is not produced — D4 defines no D1 entities (spec Key Entities). `research.md` is not produced — research is `17-ai-platform.md`.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   └── stream/
│       ├── index.ts                    # Prose stream broker: chunk relay, heartbeat ticker (notifyActivity), cancel wiring, terminal emit, createChunkSourceFromInvocationEvents (FR-001, FR-004–FR-013)
│       ├── prose-guards.ts             # Incremental cheap guards + full guard set on assembled text (FR-002, FR-003)
│       └── structured.ts               # D6-owned structured broker (`createStructuredStreamBroker`) — not a D4 deliverable; listed for path clarity only
└── test/
    └── stream-broker.test.ts           # T1–T19 plus review-resolution T20–T27 (integration spy against scripted/invocation-adapter sources + injectable sinks/ticker)
```

No `frontend/` or `backend/` tree is shown — D4 touches neither. No migration, no `wrangler.toml` change, and no prompt/asset tree — D4 is a pure TypeScript module plus integration tests. A6's `adapter.ts` and D3's `invocation/` are consumed unchanged and are not listed as this slice's source tree. Production wiring of `createStreamBroker` into the Worker pipeline remains deferred (B4/C3 sinks / E4).

**Structure Decision**: D4 extends the `ai-platform/` tree (delivery plan §7.1) with sibling module `src/stream/` (Clarification Q1), sibling to existing `src/invocation/` and `src/adapter.ts` it consumes. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule. Prose API surface on `index.ts`: `createStreamBroker`, `createChunkSourceFromInvocationEvents`, `ChunkSource.getPartialUsage()`, `HeartbeatScheduleHandle.notifyActivity()`, journal-terminal on all three states.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From A6 — SSE event framing; `accepted` opening event; heartbeat event shape; terminal kinds `completed` / `failed` / `cancelled`; one-terminal-event invariant; connection-scoped cancellation at the framing level | `ai-platform/src/adapter.ts` (`AdapterSseEvent`, `AdapterEventSink`, `TerminalEventKind`, `handleAdapterRequest` stream `cancel` → `cancelled`, one-terminal guard); frozen in `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md`. D4 emits content/heartbeat/terminal events through that framing and does not redefine wire vocabulary or the one-terminal rule |
| From D3 — platform-internal attempt loop; normalized stream chunks; per-attempt journal feed; `regenerating` / discard-on-fallback / no-splice | `ai-platform/src/invocation/index.ts` (`runInvocation`, `InvocationSink.emitStreamText` / `emitRegenerating`, `AttemptRecord`); frozen in `specs/030-invocation-retry-fallback/contracts/invocation-attempt-loop.md`. D4 bridges InvocationSink-shaped events via `createChunkSourceFromInvocationEvents` and relays what invocation emits (including `regenerating` when present); it does not own retry, fallback, or the regenerating decision |

Every **Consumes** entry binds to an existing implementation. None requires modification (stop condition 2 not triggered). B4's `creditUsage` (`ai-platform/src/credit/index.ts`) and C3's `recordTerminalState` (`ai-platform/src/journal/index.ts`) are Assumptions used via injectable sinks (Clarification Q4), not Consumes — they are not modified.

## Components Touched

One §4 component group: **§4.3.10 Stream broker** — relay of normalized chunks, provisional-versus-committed emission rules, heartbeat emission during provider silence, one-terminal-event guarantee on broker paths, and connection-scoped cancellation without per-request state.

§6.4 (`prose` row and invariants 1–2 as applied to broker emission), §5.5 (streaming protocol rules 3–6 as broker behaviour using A6 framing), §6.5 (cancellation semantics), and §9.7 (connection-scoped recommendation / Session DO rejection) are cited in Implements as the streaming and cancel contracts this component realises; they are not additional §4 components modified by this slice. A6's §4.3.1 framing and D3's §4.3.7 attempt loop are **consumed**, not modified.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/src/stream/index.ts` | FR-001, FR-004–FR-013 (ordered relay + heartbeats with `notifyActivity`; terminal `completed` with validated payload; one-terminal-event; disconnect → abort → `cancelled`; live `getPartialUsage` credit; journal-terminal on completed/failed/cancelled; D3 invocation adapter; source-error containment; no OOB cancel/Session DO; no D1-per-chunk / no per-request state; provisional chunks non-authoritative) |
| `ai-platform/src/stream/prose-guards.ts` | FR-002, FR-003 (incremental assembled length ceiling / stop-sequence / system-prompt-leak; abort + fail terminally; full guard set returns violation — assembled length + deferred `empty_output`) |
| `ai-platform/test/stream-broker.test.ts` | T1–T19 (FR-001–FR-013) plus review-resolution T20–T27; controllable heartbeat ticker per Clarification Q2; AbortSignal disconnect harness per Clarification Q3; in-memory credit + journal-terminal sinks per Clarification Q4 |
| `specs/031-stream-broker/contracts/stream-broker.md` | Freezes → broker relay/heartbeat/one-terminal; prose path; connection-scoped cancel; no OOB cancel / Session DO / resume |
| `specs/031-stream-broker/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced. `structured.ts` is D6-owned and is not a D4 Files row.

## Test Layout

Per the architecture's testing strategy (§13.5 Pipeline tests with fake provider) and delivery plan §3.11.4 row D4 ("Integration (spy)"):

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `chunks_relayed_in_order` | Integration (Pipeline with fake; spy on sink order) | `ai-platform/test/stream-broker.test.ts` |
| T2 `heartbeat_during_provider_silence` | Integration (Pipeline with fake; controllable heartbeat ticker) | `ai-platform/test/stream-broker.test.ts` |
| T3 `incremental_guard_length_ceiling_aborts` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T4 `incremental_guard_stop_sequence_aborts` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T5 `incremental_guard_system_prompt_leak_aborts` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T6 `full_guard_set_runs_on_assembled_text` | Integration (Pipeline with fake; spy on full-guard invocation) | `ai-platform/test/stream-broker.test.ts` |
| T7 `terminal_completed_carries_validated_payload` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T8 `disconnect_aborts_provider_fetch_via_abort_signal` | Integration (Pipeline with fake; AbortSignal spy) | `ai-platform/test/stream-broker.test.ts` |
| T9 `disconnect_terminates_as_cancelled` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T10 `partial_usage_credited_on_cancel` | Integration (Pipeline with fake; in-memory credit sink) | `ai-platform/test/stream-broker.test.ts` |
| T11 `journal_row_complete_on_cancel` | Integration (Pipeline with fake; in-memory journal-terminal sink) | `ai-platform/test/stream-broker.test.ts` |
| T12 `no_per_request_state_object_created` | Integration (Pipeline with fake; spy — absence of per-request state) | `ai-platform/test/stream-broker.test.ts` |
| T13 `cancel_before_first_token` | Integration (Pipeline with fake; AbortSignal + credit) | `ai-platform/test/stream-broker.test.ts` |
| T14 `cancel_mid_stream` | Integration (Pipeline with fake; AbortSignal + credit) | `ai-platform/test/stream-broker.test.ts` |
| T15 `one_terminal_event_under_guard_abort_and_cancel` | Integration (Pipeline with fake; spy on terminal count) | `ai-platform/test/stream-broker.test.ts` |
| T16 `network_drop_indistinguishable_from_cancel` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T17 `no_out_of_band_cancel_endpoint_or_session_do` | Integration (Pipeline with fake; spy — absence of cancel endpoint / Session DO) | `ai-platform/test/stream-broker.test.ts` |
| T18 `provisional_chunks_not_authoritative` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T19 `no_d1_row_per_stream_chunk` | Integration (Pipeline with fake; spy — absence of per-chunk D1 writes) | `ai-platform/test/stream-broker.test.ts` |
| T20 `abort_rejecting_source_still_cancels` | Integration (Pipeline with fake; AbortError-throwing source) | `ai-platform/test/stream-broker.test.ts` |
| T21 `mid_stream_source_throw_fails_terminally` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T22 `zero_usage_cancel_skips_credit` | Integration (Pipeline with fake; credit-sink spy) | `ai-platform/test/stream-broker.test.ts` |
| T23 `disconnect_after_completion_noop` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T24 `journal_on_completed_and_failed` | Integration (Pipeline with fake; journal-terminal spy) | `ai-platform/test/stream-broker.test.ts` |
| T25 `sink_throw_does_not_suppress_terminal` | Integration (Pipeline with fake; throwing sinks) | `ai-platform/test/stream-broker.test.ts` |
| T26 `signal_ignoring_source_disconnect_emits_cancelled` | Integration (Pipeline with fake) | `ai-platform/test/stream-broker.test.ts` |
| T27 `invocation_adapter_relays_regenerating` | Integration (Pipeline with fake; `createChunkSourceFromInvocationEvents`) | `ai-platform/test/stream-broker.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). T20–T27 were added by the 2026-08-04 review resolution (assembled-length / empty_output / live usage / notifyActivity / error containment / D3 adapter). T2 forces a silent gap via an injectable heartbeat ticker and asserts ≥1 heartbeat; activity reset is covered via `notifyActivity` (Clarification Q2 + review resolution). T8/T13/T14 close the client stream and assert the broker-held `AbortSignal` is aborted (Clarification Q3). T10/T11 assert `credit(partial)` and a complete terminal `cancelled` record on injectable sinks (Clarification Q4). Incremental-guard aborts emit exactly one `failed` terminal using an existing A2 taxonomy code (`validation_failed`); this slice does not add or rename codes (spec Assumptions / Edge Cases).

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/stream-broker.md` constrains the module; later slices bind to this artifact, not to prose (delivery plan DP-4).
2. **Prose guards + T3–T5, T6.** Incremental length / stop-sequence / system-prompt-leak abort and fail terminally; full guard set callable on assembled text. Thresholds are supplied as parameters (capability/manifest or platform config), not invented constants (spec Assumptions).
3. **Broker skeleton + T1, T7, T18.** Ordered `text_delta` relay through A6 framing; terminal `completed` carries validated payload; provisional chunks are not treated as authoritative.
4. **Heartbeat ticker + T2.** Injectable ticker; silent gap → ≥1 heartbeat (Clarification Q2).
5. **Cancel path + T8, T9, T13, T14, T16.** Broker-owned `AbortSignal`; stream close / network-drop-equivalent abort the fetch, terminate as `cancelled` (Clarification Q3).
6. **Credit + journal-terminal sinks + T10, T11.** In-memory sinks assert partial-usage credit and complete `cancelled` terminal record (Clarification Q4).
7. **Prohibitions + T12, T15, T17, T19.** No per-request state; one terminal under guard abort and cancel; no OOB cancel endpoint / Session DO; no D1 row per chunk.
8. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
