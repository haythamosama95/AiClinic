---

description: "Task list for slice A6 — Protocol adapter and SSE framing"
---

# Tasks: Protocol adapter and SSE framing (A6)

**Input**: Design documents from `/specs/020-ai-protocol-adapter-sse/`

**Prerequisites**: `plan.md` (required), `spec.md` (required). Consumes A2's `ai-platform/src/errors.ts`,
`reference.ts`, `trace.ts` and A3's `ai-platform/src/contracts/canonical.ts` — all exist on `ai/master`.

**Tests**: Tests are mandatory. Every case in the spec's Test plan (T1–T12) is a task. Tests are
written to fail before the code exists (one task writes the failing suite; the implementation tasks
make each group pass). No test is optional.

**Organization**: One slice is one story (delivery plan §6.2). There is one `[US1]` label and no
cross-story parallelism section.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (here, US1 only)
- Include exact file paths in descriptions

## Path Conventions

- **Cloudflare Worker gateway**: `ai-platform/src/`, `ai-platform/test/`, `ai-platform/migrations/`
- **Spec artifacts**: `specs/020-ai-protocol-adapter-sse/`
- The gateway lives in `ai-platform/` at the repository root as a sibling of `frontend/` and
  `backend/` (delivery plan §7.1). No Flutter or Supabase path is touched.

---

## Phase 1: Tests

**Purpose**: Write the failing integration suite before the adapter exists. Per §13.5 (pipeline tests
— fake provider, deterministic) and Clarification Q2, the suite drives the adapter through a small
in-process stub that injects canned `accepted`, heartbeat, and terminal sequences directly into the
adapter's event sink — no broker (D4), no provider (D2), no network.

### Test scaffolding (fail first)

- [X] T001 [US1] Create `ai-platform/test/adapter.test.ts` with the integration harness: an in-process
      stub event source (lives in `test/helpers/adapter-stub.ts`, not `src/adapter.ts`) that injects
      canned `accepted`, heartbeat, and terminal sequences directly into the adapter's event sink; a
      helper that builds a well-formed request (valid JSON body, the three headers
      `x-idempotency-key`, `x-trace-id`, `x-capability-version`); and a test-injectable ingress
      body-size limit constant shared with the adapter (Clarification Q1). All named cases below are
      stubbed with assertions against an `adapter.ts` import that does not yet exist, so
      `npx vitest run test/adapter.test.ts` fails to compile. (Scaffolds T1–T13)

### Ingress gate and header parsing (T1–T5)

- [X] T002 [US1] Case T1: assert a request whose body exceeds the ingress body-size config value (one
      UTF-8 byte larger than the shared limit constant; also Content-Length pre-check, multi-byte
      UTF-8, and oversized+malformed headers → 413 not 422) is rejected as `request_too_large` —
      HTTP 413, A2 error body with empty `request_reference` and empty `trace_id` — before any other
      work: no header handled, no `accepted` event, no reference generated. Proves FR-002 / FR-006
      stage-1 exception; spec Test plan T1. (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T003 [US1] Case T2: assert the `x-idempotency-key` header is parsed from a well-formed request
      and made available to later stages. Proves FR-003; spec Test plan T2.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T004 [US1] Case T3: assert the `x-trace-id` header is parsed and propagated (any non-empty
      client string, including non-ULID); when absent, A2's `resolveTraceId` ULID is used (consumes
      `ai-platform/src/trace.ts`). No ULID-only client constraint. Proves FR-003; spec Test plan T3.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T005 [US1] Case T4: assert the `x-capability-version` header is parsed and made available to the
      capability resolver (a later stage). Proves FR-003; spec Test plan T4.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T006 [US1] Case T5: assert a malformed body (non-JSON / null / non-object) or a
      malformed/missing/empty/whitespace required header (idempotency key, trace id, or version pin —
      one sub-case each) is rejected by the adapter's own parsing with bare HTTP 422, produces no
      taxonomy-coded error body, and opens no stream. Proves FR-004; spec Test plan T5.
      (Lives in `ai-platform/test/adapter.test.ts`)

### SSE framing (T6–T7, T12)

- [X] T007 [US1] Case T6: assert a stream opens with an `accepted` event carrying the request
      reference, emitted exactly once and before any content or terminal event. Proves FR-007; spec
      Test plan T6. (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T008 [US1] Case T7: assert an injected heartbeat event is framed while the stream is idle and
      receives no content, and that the heartbeat is neither a content nor a terminal event
      (autonomous idle emission is D4). Proves FR-009; spec Test plan T7.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T009 [US1] Case T12: assert the `accepted` event's request reference matches A2's
      `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` format (consumes
      `ai-platform/src/reference.ts`), and the trace id on every emitted event matches the parsed or
      A2-generated value. Proves FR-007, FR-006; spec Test plan T12.
      (Lives in `ai-platform/test/adapter.test.ts`)

### Terminal events and cancellation (T8–T11)

- [X] T010 [US1] Case T8: assert a stream whose request completes ends with exactly one `completed`
      terminal event and no second terminal event. Proves FR-010, FR-012; spec Test plan T8.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T011 [US1] Case T9: assert a stream whose request fails ends with exactly one `failed` terminal
      event carrying a §5.4 taxonomy code (consumes `ai-platform/src/errors.ts`), and no second
      terminal event. Proves FR-005, FR-006, FR-010, FR-012; spec Test plan T9.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T012 [US1] Case T10: assert real disconnect paths (`reader.cancel()`, already-aborted signal,
      `request.signal` abort mid-stream) mark `terminalEmitted` without enqueueing `cancelled` on the
      dead socket; stub abort still yields exactly one `cancelled` terminal; `cancelled` / `499` is
      not written to the live socket as an HTTP status (uses A2's `liveHttpStatusForCode` returning
      null). Proves FR-011, FR-010, FR-012; spec Test plan T10.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T013 [US1] Case T11: assert a stream that has already emitted a terminal event does not emit a
      second one under any subsequent path (completion, failure, abort, duplicate close arriving
      afterwards); assert `terminalEmitted` is connection-scoped with no per-request state object.
      Proves FR-012; spec Test plan T11. (Lives in `ai-platform/test/adapter.test.ts`)
- [X] T013a [US1] Case T13: assert missing injected `eventSource` returns HTTP 503 and opens no
      stream. Proves FR-001; spec Test plan T13. (Lives in `ai-platform/test/adapter.test.ts`)

---

## Phase 2: Implementation

**Purpose**: Make the failing suite pass, one implementation unit at a time, in the plan's sequencing
order. Each unit is one file under `ai-platform/src/`.

### Ingress gate and header parsing

- [X] T014 [US1] Create `ai-platform/src/adapter.ts`: the §4.3.1 protocol adapter's request parsing
      and ingress body-size gate. UTF-8 byte-accurate measurement; `Content-Length` pre-check when
      present; otherwise stream-read and abort at first oversize chunk (never buffer past the cap).
      Reject an oversized body as `request_too_large` (HTTP 413) via A2's `liveHttpStatusForCode` and
      `buildErrorBody` with empty `request_reference` / `trace_id` before any other work (§6.1 stage
      1; §5.4; FR-006 stage-1 exception). Parse body as JSON non-null plain object. Proves FR-002,
      FR-004, FR-006. Proven by T002 (T1), T006 (T5 body cases).
- [X] T015 [US1] In `ai-platform/src/adapter.ts`, parse the three headers `x-idempotency-key`,
      `x-trace-id` (via A2's `resolveTraceId` — any non-empty client string; ULID only when absent),
      and `x-capability-version` from a well-formed request. Reject a malformed, missing, empty, or
      whitespace-only required header by the adapter's own parsing with bare HTTP 422, producing no
      taxonomy-coded body and opening no stream (§5.4 "no bare `400`"). Proves FR-003, FR-004. Proven
      by T003–T006 (T2–T5).

### SSE event framing and accepted opening

- [X] T016 [US1] In `ai-platform/src/adapter.ts`, implement the SSE event sink and framing: the
      `event:`/`data:` SSE encoding, the event vocabulary (`accepted`, heartbeat, `completed`,
      `failed`, `cancelled`), and the `accepted` opening event carrying A2's
      `generateRequestReference` value, emitted exactly once and before any content or terminal event
      (§5.5 rules 1–2). Content-event kinds are A3's `CanonicalChunkKind` (`text_delta`,
      `partial_structured`, `usage`, `provider_note`); the framing carries them, the relay is D4.
      Proves FR-007, FR-008. Proven by T007 (T6), T009 (T12).

### Heartbeat

- [X] T017 [US1] In `ai-platform/src/adapter.ts`, frame a heartbeat event as neither content nor
      terminal (§5.5 rule 3). Autonomous idle emission is D4's; A6 proves framing against an injected
      heartbeat. Proves FR-009. Proven by T008 (T7).

### Terminal events and one-terminal-event guard

- [X] T018 [US1] In `ai-platform/src/adapter.ts`, implement the terminal-event state machine: emit
      exactly one terminal event per stream (`completed` with the validated result, or `failed`
      carrying a §5.4 taxonomy code in A2's error body), never inferred from silence (§5.5 rule 4).
      Once a terminal event has been emitted, refuse to emit any further event under any path
      (completion, failure, abort, duplicate close). Proves FR-005, FR-006, FR-010, FR-012. Proven by
      T010 (T8), T011 (T9), T013 (T11).

### Connection-scoped cancellation

- [X] T019 [US1] In `ai-platform/src/adapter.ts`, implement connection-scoped cancellation: on
      `ReadableStream` `cancel()`, `request.signal` abort, and already-aborted at entry, mark
      `terminalEmitted` only and NEVER enqueue `cancelled` on the dead socket; no separate endpoint
      and no per-request state. `cancelled` / `499` is never written to the live socket as an HTTP
      status (A2's `liveHttpStatusForCode` returns null for `cancelled`); `499` is the journaled
      terminal value, returned later by C3's get-request lookup, which is itself a `200` (§5.5 rule 5,
      Cancel row; §4.3.10; §9.7). Proves FR-011. Proven by T012 (T10).
- [X] T019a [US1] In `ai-platform/src/adapter.ts`, require injected `eventSource`; when missing,
      return HTTP 503 and open no stream. Keep all stub machinery in
      `ai-platform/test/helpers/adapter-stub.ts` (and `adapter.test.ts`) — none in `src/adapter.ts`.
      Proves FR-001. Proven by T013a (T13).

### Wire the adapter into the Worker

- [X] T020 [US1] Modify `ai-platform/src/worker.ts`: replace the placeholder `POST /v1/requests` JSON
      handler with a call into the adapter from T014–T019a. Without an injected event source the live
      route fails fast (503) until D4. The `/health` route and `GatewayObject` Durable Object class
      are unchanged (§4.3.1 owns the wire format; §13.4 the environment topology is A1's). Proves
      FR-001, FR-002, FR-007, FR-010, FR-011 (live wiring of the adapter into the fetch path). Proven
      by the full suite T1–T13 still passing against the wired adapter.

---

## Phase 3: Verification

- [X] T021 [US1] Run `npx vitest run` from `ai-platform/` to execute the **whole** suite — this
      slice's `test/adapter.test.ts` plus every prior slice's suite
      (`canonical.test.ts`, `config-cache.test.ts`, `context.test.ts`, `env-deps.test.ts`,
      `error-body.test.ts`, `health.test.ts`, `log-redaction.test.ts`, `manifest.test.ts`,
      `migrations.test.ts`, `reference.test.ts`, `taxonomy.test.ts`, `trace.test.ts`) — and confirm
      all are green, per delivery plan §3.10 ("a checkpoint requires every prior suite green, not just
      the latest"). This is the CP1 gating check this slice's own plan's summary names. Proves no
      prior frozen contract was disturbed (stop condition 2 prevention) and the A6 cases T1–T13 hold
      against the wired adapter (33 tests in `adapter.test.ts`).

---

## Phase 4: Documentation

- [X] T022 [US1] [P] Create `specs/020-ai-protocol-adapter-sse/quickstart.md` filled per
      `.specify/templates/ai-platform-quickstart-template.md`: Architecture context (row A6; §4.3.1,
      §5.5), What was implemented (the adapter module + Worker wiring + test-harness stubs), Files to
      review table (`ai-platform/src/adapter.ts`, `ai-platform/src/worker.ts`,
      `ai-platform/test/adapter.test.ts`, `ai-platform/test/helpers/adapter-stub.ts` — this slice's
      files only), Run the automated suite (`npx vitest run test/adapter.test.ts`, expected
      **33 passing tests** for this slice only), and Inspect the changes. **Slice-only scope**: no
      prior-slice files in the review table, no combined test counts, no prior-slice regression
      commands. No Manual validation section — CI is the only verification path (the framing is
      exercised by the stub, not by a live deployment). No Prerequisites section
      (`npx vitest run` against this slice's test files suffices).

> The plan's other Documentation artifact, `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md`,
> already exists (created during the plan phase) and needs no task here.

---

## Phase 5: Review resolution documentation (A6)

**Purpose**: Encode the A6 review-resolution decisions into Spec Kit artifacts (implementation already
landed). Documentation-only; no production code or tests edited in this phase.

- [X] T023 [US1] [P] Update `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md`: cancel marks
      `terminalEmitted` only (never enqueue on dead socket); UTF-8 / Content-Length body gate;
      FR-006 stage-1 empty correlation fields on 413; bare 422 for adapter-local parse failures;
      any non-empty client trace id; required `eventSource` → 503; heartbeat framing vs D4 emission.
- [X] T024 [US1] [P] Update `specs/020-ai-protocol-adapter-sse/spec.md`: Session 2026-08-03
      clarifications; FR-001–012 / acceptance / edge / test plan / SC-006 aligned to review resolution.
- [X] T025 [US1] [P] Update `specs/020-ai-protocol-adapter-sse/plan.md`, `tasks.md`, and
      `quickstart.md` for stub location, 33-test suite, fail-fast live route, and sequencing notes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Tests)**: No dependencies — the harness in T001 imports an `adapter.ts` that does not
  yet exist, so the suite fails to compile (its intended state before implementation).
- **Phase 2 (Implementation)**: Depends on Phase 1. T014–T015 (ingress + headers) make T002–T006
  pass; T016 makes T007/T009 pass; T017 makes T008 pass; T018 makes T010/T011/T013 pass; T019 makes
  T012 pass; T019a makes T013a pass; T020 wires the adapter into the Worker and the full suite must
  still pass.
- **Phase 3 (Verification)**: Depends on Phase 2 complete. Runs the whole platform suite, not just
  this slice's.
- **Phase 4 (Documentation)**: T022 is `[P]` and depends only on Phase 1 (the test file existing) —
  it can run alongside the implementation phase, but its "Files to review" content is final only once
  the implementation lands.
- **Phase 5 (Review resolution docs)**: T023–T025 are `[P]` documentation updates after the A6 review
  resolution landed in code; they depend on Phases 2–4 being complete.

### Within Each Unit

- Tests must exist and fail before the implementation unit that makes them pass.
- The ingress gate (T014) is testable before any stream opens; the SSE framing (T016) and heartbeat
  framing (T017) are testable once the event sink exists; terminal events (T018) build on the framing;
  cancellation (T019) and required `eventSource` (T019a) close the framing loop.

### Parallel Opportunities

- T022 (documentation) is `[P]` and can run alongside Phase 2.
- T023–T025 (review-resolution docs) are `[P]` among themselves.
- No other `[P]` marks: the single test file (T001–T013a) and the single source file (T014–T019a) are
  each one file; within-file tasks are sequential by dependency.

---

## Notes

- [P] tasks = different files, no dependencies. Here T022 and T023–T025 qualify.
- Each implementation task lists the `FR-###` it satisfies and the named test(s) that prove it.
- Spy/absence assertions in the spec ("no `accepted` event", "no reference generated", "no second
  terminal event", "no dead-socket enqueue") are part of the same test task that asserts the outcome —
  they assert an absence within the stub, and the plan's Test Layout places them in the single
  integration file.
- The five A6 prohibitions (delivery plan §6.4) are enforced by what the tasks do **not** do: no
  out-of-band cancel/resume (§9.7), no WebSocket transport, no D1/R2 writes, no per-request state, no
  client-side chunk assembly, no prompt text in any client path.
- Verify the whole suite is green at T021 before declaring the slice done.

---

## Summary

**Total tasks**: 26 (within the 25-task guidance; Phase 5 adds three documentation-only review-
resolution tasks after the original 22).
- Tests (Phase 1): 14 (T001 harness + T002–T013 + T013a).
- Implementation (Phase 2): 8 (T014–T020 including T019a).
- Verification (Phase 3): 1 (T021, whole-suite run including every prior slice).
- Documentation (Phase 4): 1 (T022, `quickstart.md`).
- Review resolution docs (Phase 5): 3 (T023–T025).

**Stop-condition check**: every task traces to both the spec (an `FR-###` or a named Test plan case)
and the plan (an implementation unit in the Files section or a Documentation artifact). No task would
be needed that neither names. Every named test (T1–T13) has an implementation unit to attach to
(T014–T019a). Phase 5 is documentation-only alignment after review resolution.
