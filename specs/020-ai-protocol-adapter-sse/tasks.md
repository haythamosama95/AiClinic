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

- [ ] T001 [US1] Create `ai-platform/test/adapter.test.ts` with the integration harness: an in-process
      stub event source that injects canned `accepted`, heartbeat, and terminal sequences directly
      into the adapter's event sink; a helper that builds a well-formed request (valid JSON body, the
      three headers `x-idempotency-key`, `x-trace-id`, `x-capability-version`); and a
      test-injectable ingress body-size limit constant shared with the adapter (Clarification Q1). All
      twelve cases below are stubbed with assertions against an `adapter.ts` import that does not yet
      exist, so `npx vitest run test/adapter.test.ts` fails to compile. (Scaffolds T1–T12)

### Ingress gate and header parsing (T1–T5)

- [ ] T002 [US1] Case T1: assert a request whose body exceeds the ingress body-size config value (one
      byte larger than the shared limit constant) is rejected as `request_too_large` — HTTP 413, A2
      error body — before any other work: no header handled, no `accepted` event, no reference
      generated. Proves FR-002; spec Test plan T1. (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T003 [US1] Case T2: assert the `x-idempotency-key` header is parsed from a well-formed request
      and made available to later stages. Proves FR-003; spec Test plan T2.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T004 [US1] Case T3: assert the `x-trace-id` header is parsed and propagated; when absent, A2's
      `resolveTraceId` ULID is used (consumes `ai-platform/src/trace.ts`). Proves FR-003; spec Test
      plan T3. (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T005 [US1] Case T4: assert the `x-capability-version` header is parsed and made available to the
      capability resolver (a later stage). Proves FR-003; spec Test plan T4.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T006 [US1] Case T5: assert a malformed or missing required header (idempotency key, trace id,
      or version pin — one sub-case each) is rejected by the adapter's own parsing, produces no
      taxonomy-coded error body, and opens no stream. Proves FR-004; spec Test plan T5.
      (Lives in `ai-platform/test/adapter.test.ts`)

### SSE framing (T6–T7, T12)

- [ ] T007 [US1] Case T6: assert a stream opens with an `accepted` event carrying the request
      reference, emitted exactly once and before any content or terminal event. Proves FR-007; spec
      Test plan T6. (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T008 [US1] Case T7: assert a heartbeat event is emitted while the stream is idle and receives no
      content, and that the heartbeat is neither a content nor a terminal event. Proves FR-009; spec
      Test plan T7. (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T009 [US1] Case T12: assert the `accepted` event's request reference matches A2's
      `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` format (consumes
      `ai-platform/src/reference.ts`), and the trace id on every emitted event matches the parsed or
      A2-generated value. Proves FR-007, FR-006; spec Test plan T12.
      (Lives in `ai-platform/test/adapter.test.ts`)

### Terminal events and cancellation (T8–T11)

- [ ] T010 [US1] Case T8: assert a stream whose request completes ends with exactly one `completed`
      terminal event and no second terminal event. Proves FR-010, FR-012; spec Test plan T8.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T011 [US1] Case T9: assert a stream whose request fails ends with exactly one `failed` terminal
      event carrying a §5.4 taxonomy code (consumes `ai-platform/src/errors.ts`), and no second
      terminal event. Proves FR-005, FR-006, FR-010, FR-012; spec Test plan T9.
      (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T012 [US1] Case T10: assert a stream whose client closes mid-stream ends with exactly one
      `cancelled` terminal event, and that `cancelled` / `499` is not written to the live socket as
      an HTTP status (uses A2's `liveHttpStatusForCode` returning null). Proves FR-011, FR-010, FR-012;
      spec Test plan T10. (Lives in `ai-platform/test/adapter.test.ts`)
- [ ] T013 [US1] Case T11: assert a stream that has already emitted a terminal event does not emit a
      second one under any subsequent path (completion, failure, abort, duplicate close arriving
      afterwards). Proves FR-012; spec Test plan T11. (Lives in `ai-platform/test/adapter.test.ts`)

---

## Phase 2: Implementation

**Purpose**: Make the failing suite pass, one implementation unit at a time, in the plan's sequencing
order. Each unit is one file under `ai-platform/src/`.

### Ingress gate and header parsing

- [ ] T014 [US1] Create `ai-platform/src/adapter.ts`: the §4.3.1 protocol adapter's request parsing
      and ingress body-size gate. Read the request body, enforce the ingress body-size limit (the
      test-injectable constant T001 shares), and reject an oversized body as `request_too_large`
      (HTTP 413) via A2's `liveHttpStatusForCode` and `buildErrorBody` before any other work (§6.1
      stage 1; §5.4). Proves FR-002. Proven by T002 (T1).
- [ ] T015 [US1] In `ai-platform/src/adapter.ts`, parse the three headers `x-idempotency-key`,
      `x-trace-id` (via A2's `resolveTraceId`), and `x-capability-version` from a well-formed request.
      Reject a malformed or missing required header by the adapter's own parsing, producing no
      taxonomy-coded body and opening no stream (§5.4 "no bare `400`"). Proves FR-003, FR-004. Proven
      by T003–T006 (T2–T5).

### SSE event framing and accepted opening

- [ ] T016 [US1] In `ai-platform/src/adapter.ts`, implement the SSE event sink and framing: the
      `event:`/`data:` SSE encoding, the event vocabulary (`accepted`, heartbeat, `completed`,
      `failed`, `cancelled`), and the `accepted` opening event carrying A2's
      `generateRequestReference` value, emitted exactly once and before any content or terminal event
      (§5.5 rules 1–2). Content-event kinds are A3's `CanonicalChunkKind` (`text_delta`,
      `partial_structured`, `usage`, `provider_note`); the framing carries them, the relay is D4.
      Proves FR-007, FR-008. Proven by T007 (T6), T009 (T12).

### Heartbeat

- [ ] T017 [US1] In `ai-platform/src/adapter.ts`, emit a heartbeat event while the stream is open and
      idle (no content events), so intermediaries do not close the connection (§5.5 rule 3). The
      heartbeat carries no content and is neither a content nor a terminal event. Proves FR-009. Proven
      by T008 (T7).

### Terminal events and one-terminal-event guard

- [ ] T018 [US1] In `ai-platform/src/adapter.ts`, implement the terminal-event state machine: emit
      exactly one terminal event per stream (`completed` with the validated result, or `failed`
      carrying a §5.4 taxonomy code in A2's error body), never inferred from silence (§5.5 rule 4).
      Once a terminal event has been emitted, refuse to emit any further event under any path
      (completion, failure, abort, duplicate close). Proves FR-005, FR-006, FR-010, FR-012. Proven by
      T010 (T8), T011 (T9), T013 (T11).

### Connection-scoped cancellation

- [ ] T019 [US1] In `ai-platform/src/adapter.ts`, implement connection-scoped cancellation: a client
      closing the stream cancels the request and ends it as `cancelled`, with no separate endpoint and
      no per-request state. `cancelled` / `499` is never written to the live socket as an HTTP status
      (A2's `liveHttpStatusForCode` returns null for `cancelled`); `499` is the journaled terminal
      value, returned later by C3's get-request lookup, which is itself a `200` (§5.5 rule 5, Cancel
      row; §4.3.10; §9.7). Proves FR-011. Proven by T012 (T10).

### Wire the adapter into the Worker

- [ ] T020 [US1] Modify `ai-platform/src/worker.ts`: replace the placeholder `POST /v1/requests` JSON
      handler with a call into the adapter from T014–T019. The `/health` route and `GatewayObject`
      Durable Object class are unchanged (§4.3.1 owns the wire format; §13.4 the environment topology
      is A1's). Proves FR-001, FR-002, FR-007, FR-010, FR-011 (live wiring of the adapter into the
      fetch path). Proven by the full suite T1–T12 still passing against the wired adapter.

---

## Phase 3: Verification

- [ ] T021 [US1] Run `npx vitest run` from `ai-platform/` to execute the **whole** suite — this
      slice's `test/adapter.test.ts` plus every prior slice's suite
      (`canonical.test.ts`, `config-cache.test.ts`, `context.test.ts`, `env-deps.test.ts`,
      `error-body.test.ts`, `health.test.ts`, `log-redaction.test.ts`, `manifest.test.ts`,
      `migrations.test.ts`, `reference.test.ts`, `taxonomy.test.ts`, `trace.test.ts`) — and confirm
      all are green, per delivery plan §3.10 ("a checkpoint requires every prior suite green, not just
      the latest"). This is the CP1 gating check this slice's own plan's summary names. Proves no
      prior frozen contract was disturbed (stop condition 2 prevention) and the A6 cases T1–T12 hold
      against the wired adapter.

---

## Phase 4: Documentation

- [ ] T022 [US1] [P] Create `specs/020-ai-protocol-adapter-sse/quickstart.md` filled per
      `.specify/templates/ai-platform-quickstart-template.md`: Architecture context (row A6; §4.3.1,
      §5.5), What was implemented (the adapter module + Worker wiring), Files to review table
      (`ai-platform/src/adapter.ts`, `ai-platform/src/worker.ts`, `ai-platform/test/adapter.test.ts`
      — this slice's files only), Run the automated suite (`npx vitest run test/adapter.test.ts`,
      expected **12 passing tests** for this slice only), and Inspect the changes. **Slice-only
      scope**: no prior-slice files in the review table, no combined test counts, no prior-slice
      regression commands. No Manual validation section — CI is the only verification path (the
      framing is exercised by the stub, not by a live deployment). No Prerequisites section
      (`npx vitest run` against this slice's test files suffices).

> The plan's other Documentation artifact, `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md`,
> already exists (created during the plan phase) and needs no task here.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Tests)**: No dependencies — the harness in T001 imports an `adapter.ts` that does not
  yet exist, so the suite fails to compile (its intended state before implementation).
- **Phase 2 (Implementation)**: Depends on Phase 1. T014–T015 (ingress + headers) make T002–T006
  pass; T016 makes T007/T009 pass; T017 makes T008 pass; T018 makes T010/T011/T013 pass; T019 makes
  T012 pass; T020 wires the adapter into the Worker and the full suite must still pass.
- **Phase 3 (Verification)**: Depends on Phase 2 complete. Runs the whole platform suite, not just
  this slice's.
- **Phase 4 (Documentation)**: T022 is `[P]` and depends only on Phase 1 (the test file existing) —
  it can run alongside the implementation phase, but its "Files to review" content is final only once
  the implementation lands.

### Within Each Unit

- Tests must exist and fail before the implementation unit that makes them pass.
- The ingress gate (T014) is testable before any stream opens; the SSE framing (T016) and heartbeat
  (T017) are testable once the event sink exists; terminal events (T018) build on the framing;
  cancellation (T019) closes the framing loop.

### Parallel Opportunities

- T022 (documentation) is `[P]` and can run alongside Phase 2.
- No other `[P]` marks: the single test file (T001–T013) and the single source file (T014–T019) are
  each one file; within-file tasks are sequential by dependency.

---

## Notes

- [P] tasks = different files, no dependencies. Here only T022 qualifies.
- Each implementation task lists the `FR-###` it satisfies and the named test(s) that prove it.
- Spy/absence assertions in the spec ("no `accepted` event", "no reference generated", "no second
  terminal event") are part of the same test task that asserts the outcome — they assert an absence
  within the stub, and the plan's Test Layout places them in the single integration file.
- The five A6 prohibitions (delivery plan §6.4) are enforced by what the tasks do **not** do: no
  out-of-band cancel/resume (§9.7), no WebSocket transport, no D1/R2 writes, no per-request state, no
  client-side chunk assembly, no prompt text in any client path.
- Verify the whole suite is green at T021 before declaring the slice done.

---

## Summary

**Total tasks**: 22 (within the 25-task cap).
- Tests (Phase 1): 13 (T001 harness + T002–T013, one per named Test plan case).
- Implementation (Phase 2): 7 (T014–T020, one per implementation unit in the plan's Files section).
- Verification (Phase 3): 1 (T021, whole-suite run including every prior slice).
- Documentation (Phase 4): 1 (T022, `quickstart.md`).

**Stop-condition check**: every task traces to both the spec (an `FR-###` or a named Test plan case)
and the plan (an implementation unit in the Files section or a Documentation artifact). No task would
be needed that neither names. Every named test (T1–T12) has an implementation unit to attach to
(T014–T019). The count is under the cap.