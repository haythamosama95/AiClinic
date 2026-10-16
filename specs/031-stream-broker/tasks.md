# Tasks: Stream broker, prose streaming, and cancellation (D4)

**Input**: Design documents from `specs/031-stream-broker/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced — D4 defines no D1 entities. `contracts/stream-broker.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T19) is covered by its own task, written to fail before the code exists. Spy cases (T2 ticker, T6 full-guard spy, T8 AbortSignal, T10/T11 sinks, T12/T15/T17/T19 absences) each get their own task (skill rule). No same-file merges are required — 19 tests + 2 implementation + 1 verification + 1 documentation = 23 tasks (≤25).

**Organization**: One user story (US1, P1) — D4 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — the frozen contract is already on disk; no migrations or `wrangler.toml` edits. No Foundational or Polish phase.

**Task count**: 23 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/test/`, `ai-platform/migrations/`, `ai-platform/vitest.config.ts`, `ai-platform/vitest.workers.config.ts`, `ai-platform/wrangler.toml`
- **Spec Kit artifacts**: `specs/031-stream-broker/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; D4 touches neither. No `ai-platform/migrations/` edits — A5 schema, B4 credit, and C3 write-path are unchanged (Consumes Binding / Clarification Q4 sinks only).

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task covering each named test in the spec's `### Test plan` (§3.11.4 row D4 = "Integration (spy)"; §13.5 Pipeline tests with fake provider). All 19 cases are CPU-only against D3 invocation output / scripted chunks with an A6-shaped event sink, injectable heartbeat ticker (Clarification Q2), broker-owned `AbortSignal` (Clarification Q3), and in-memory credit + journal-terminal sinks (Clarification Q4) — no DO/D1/R2 I/O — so the default Node-pool config (`vitest.config.ts`, `include: ["test/**/*.test.ts"]`) covers them; no workers-pool registration is needed. T001 creates `test/stream-broker.test.ts` and its substrate; T002–T019 append to it. The modules under test (`../src/stream`) do not exist yet, so the file fails to compile from the first importing task onward — the intended red state. Order follows the plan's Sequencing (prose guards → broker skeleton → heartbeat → cancel → credit/journal → prohibitions).

- [X] T001 [US1] Add `T-D4-03 incremental_guard_length_ceiling_aborts` to `ai-platform/test/stream-broker.test.ts` (integration): create the substrate — an A6-shaped event sink collecting `AdapterSseEvent`-like events (`text_delta`, `heartbeat`, `completed`, `failed`, `cancelled`), a controllable heartbeat ticker (Clarification Q2), a broker-owned `AbortController` / `AbortSignal` for the in-flight fetch (Clarification Q3), in-memory partial-usage credit and journal-terminal sinks (Clarification Q4), a scripted chunk source for `prose` (D3-shaped stream text / normalized chunks; production D2 fake and D3 loop unchanged), injectable prose-guard thresholds (length ceiling / stop-sequence / leak needle as parameters — no invented constants), and import of the stream entry points from `../src/stream`. Then the case: stream whose incremental length-ceiling guard trips; assert the stream aborts and exactly one `failed` terminal (taxonomy `validation_failed`) (§6.4; §3.11.4 D4). Satisfies FR-002 / SC-003.
- [X] T002 [US1] Add `T-D4-04 incremental_guard_stop_sequence_aborts` to `ai-platform/test/stream-broker.test.ts` (integration): stream that produces a stop-sequence violation under the incremental guard; assert abort and exactly one `failed` terminal (§6.4; §3.11.4 D4). Satisfies FR-002 / SC-003.
- [X] T003 [US1] Add `T-D4-05 incremental_guard_system_prompt_leak_aborts` to `ai-platform/test/stream-broker.test.ts` (integration): stream that produces a system-prompt-leak under the incremental guard; assert abort and exactly one `failed` terminal (§6.4; §3.11.4 D4). Satisfies FR-002 / SC-003.
- [X] T004 [US1] Add `T-D4-06 full_guard_set_runs_on_assembled_text` to `ai-platform/test/stream-broker.test.ts` (integration, spy): stream that completes without an incremental abort; spy that the full guard set is invoked on the assembled text before the terminal event (§6.4; §3.11.4 D4). Satisfies FR-003 / SC-004.
- [X] T005 [US1] Add `T-D4-01 chunks_relayed_in_order` to `ai-platform/test/stream-broker.test.ts` (integration): fake provider / scripted source emits a sequence of normalized text chunks; assert they arrive at the client sink in order as `text_delta` events (§4.3.10; §6.4; §3.11.4 D4). Satisfies FR-001 / SC-001.
- [X] T006 [US1] Add `T-D4-07 terminal_completed_carries_validated_payload` to `ai-platform/test/stream-broker.test.ts` (integration): after full guard set passes, assert exactly one `completed` terminal carries the validated payload (self-contained; not client-assembled from chunks) (§6.4 invariant 1; §3.11.4 D4). Satisfies FR-004 / SC-005.
- [X] T007 [US1] Add `T-D4-18 provisional_chunks_not_authoritative` to `ai-platform/test/stream-broker.test.ts` (integration): assert relayed `text_delta` chunks are provisional for responsiveness and only the terminal validated payload is authoritative (§6.4 invariant 1; §3.10). Satisfies FR-013 / SC-012.
- [X] T008 [US1] Add `T-D4-02 heartbeat_during_provider_silence` to `ai-platform/test/stream-broker.test.ts` (integration): force a silent gap via the controllable heartbeat ticker (Clarification Q2); assert ≥1 `heartbeat` event while the stream remains open without content (§4.3.10; §5.5 rule 3; §3.11.4 D4). Satisfies FR-001 / SC-002.
- [X] T009 [US1] Add `T-D4-08 disconnect_aborts_provider_fetch_via_abort_signal` to `ai-platform/test/stream-broker.test.ts` (integration, spy): close the client stream; assert the broker-held `AbortSignal` for the in-flight fetch is aborted (Clarification Q3; §4.3.10; §6.5). Satisfies FR-006 / SC-006.
- [X] T010 [US1] Add `T-D4-09 disconnect_terminates_as_cancelled` to `ai-platform/test/stream-broker.test.ts` (integration): on client disconnect, assert the request terminal state / event is `cancelled` (§5.5 rule 5; §6.5; §3.11.4 D4). Satisfies FR-006 / SC-007.
- [X] T011 [US1] Add `T-D4-13 cancel_before_first_token` to `ai-platform/test/stream-broker.test.ts` (integration): disconnect before any content token is relayed; assert abort via abort signal, terminal `cancelled`, and partial-usage credit when any exists (§6.5; §3.11.4 D4). Satisfies FR-011 / SC-011.
- [X] T012 [US1] Add `T-D4-14 cancel_mid_stream` to `ai-platform/test/stream-broker.test.ts` (integration): disconnect after one or more `text_delta` events; assert abort via abort signal, terminal `cancelled`, and partial-usage credit (§6.5; §3.11.4 D4). Satisfies FR-011 / SC-011.
- [X] T013 [US1] Add `T-D4-16 network_drop_indistinguishable_from_cancel` to `ai-platform/test/stream-broker.test.ts` (integration): drive a network-drop-equivalent disconnect; assert the same abort → `cancelled` → credit path as deliberate Cancel (§5.5 rule 5; §6.5; §3.10). Satisfies FR-006 / SC-012.
- [X] T014 [US1] Add `T-D4-10 partial_usage_credited_on_cancel` to `ai-platform/test/stream-broker.test.ts` (integration, spy): on cancel after partial provider usage, assert the credit sink is called with partial usage (Clarification Q4; §6.5; Done when). Satisfies FR-008 / SC-008.
- [X] T015 [US1] Add `T-D4-11 journal_row_complete_on_cancel` to `ai-platform/test/stream-broker.test.ts` (integration, spy): on cancel, assert the journal-terminal sink receives a complete terminal `cancelled` record (Clarification Q4; §5.5 rule 6; §6.5). Satisfies FR-009 / SC-009.
- [X] T016 [US1] Add `T-D4-12 no_per_request_state_object_created` to `ai-platform/test/stream-broker.test.ts` (integration, spy): assert absence of any per-request server-side state object (no Session DO / request registry) across streaming and cancel paths (§4.3.10; §9.7; §3.11.4 D4). Satisfies FR-007, FR-012 / SC-010.
- [X] T017 [US1] Add `T-D4-15 one_terminal_event_under_guard_abort_and_cancel` to `ai-platform/test/stream-broker.test.ts` (integration, spy): under incremental-guard abort and under disconnect, assert exactly one terminal event each — no duplicate (§5.5 rule 4; A6 Consumes; §3.10). Satisfies FR-005 / SC-012.
- [X] T018 [US1] Add `T-D4-17 no_out_of_band_cancel_endpoint_or_session_do` to `ai-platform/test/stream-broker.test.ts` (integration, spy): assert absence of a separate cancel endpoint and of a per-request Session Durable Object (§4.3.10; §6.5; §9.7; R-20). Satisfies FR-010 / SC-012.
- [X] T019 [US1] Add `T-D4-19 no_d1_row_per_stream_chunk` to `ai-platform/test/stream-broker.test.ts` (integration, spy): during chunk relay, assert zero D1 writes per stream chunk (§7.5 / delivery plan §6.4; §3.10). Satisfies FR-012 / SC-012.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: The two implementation units named in `plan.md` → Files: `ai-platform/src/stream/prose-guards.ts` and `ai-platform/src/stream/index.ts`. Consumed modules (`adapter.ts`, `invocation/index.ts`) are imported, not modified (delivery plan §2.3). B4 credit and C3 journal are reached only via injectable sinks (Clarification Q4) — those modules are not modified. The frozen contract `contracts/stream-broker.md` constrains the surface. Order follows plan Sequencing: guards first, then broker (relay, heartbeat, cancel, sinks).

- [X] T020 [US1] Create `ai-platform/src/stream/prose-guards.ts` — `prose` incremental cheap guards and completion-time full guard set. Export functions that: apply length-ceiling, stop-sequence, and system-prompt-leak checks incrementally on streamed text (thresholds as parameters — capability/manifest or platform config, not invented constants); on violation signal abort + terminal failure with existing A2 taxonomy code `validation_failed` (no new/renamed codes); and run the full guard set on the assembled text at completion. No D1/R2/DO I/O. Structured modes out of scope (D6). **Satisfies**: FR-002, FR-003; **proved by**: T-D4-03..T-D4-06.
- [X] T021 [US1] Create `ai-platform/src/stream/index.ts` — stream broker. Export the broker entry that: relays normalized chunks in order as A6 `text_delta` events through an event sink; emits A6 `heartbeat` events during provider silence via an injectable ticker (Clarification Q2); applies `prose-guards` incrementally and at completion; on success emits exactly one `completed` carrying the validated payload (authoritative; provisional chunks are not); on guard abort emits exactly one `failed`; on client disconnect / network-drop-equivalent aborts the in-flight provider fetch through a broker-owned `AbortSignal` (Clarification Q3), emits exactly one `cancelled`, credits partial usage via the credit sink, and records a complete terminal `cancelled` outcome via the journal-terminal sink (Clarification Q4); supports cancel-before-first-token and cancel-mid-stream; creates no per-request server-side state, no Session DO, no separate cancel endpoint, and no D1 row per chunk; relays D3 `regenerating` when present without owning retry/fallback. No modification of A6 framing or D3 invocation. **Satisfies**: FR-001, FR-004–FR-013; **proved by**: T-D4-01, T-D4-02, T-D4-07..T-D4-19.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T022 [US1] From `ai-platform/`, run `npx vitest run test/stream-broker.test.ts` (this slice's named cases, all under the default Node pool — D4 is CPU-only with injectable sinks), then run the full prior suite — `npx vitest run` (default Node-pool prior suites including `stream-broker.test.ts` (D4), `invocation.test.ts` (D3), `provider-port.test.ts`, `router.test.ts` (D2), `prompt-registry.test.ts`, `prompt-composer.test.ts` (D1), `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `context-validator.test.ts` (C2)) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites: `control.test.ts` (B2), `identity.test.ts`, `entitlement.test.ts`, `rate-limit.test.ts` (B3), `admission-credit.test.ts`, `quota-do.test.ts` (B4), `capability.test.ts` (C1), `journal.test.ts` (C3); `context.test.ts`, `config-cache.test.ts`, `migrations.test.ts` (A5); `adapter.test.ts` (A6)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (every branch and named boundary this slice covers — ordered relay, heartbeat, incremental guards, full guard set, validated terminal payload, disconnect abort/`cancelled`/credit/journal, no per-request state, cancel-before-first and mid-stream, one-terminal, network-drop≡cancel, no OOB cancel/Session DO, provisional non-authoritative, no D1-per-chunk). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. The contract was already frozen during the plan phase.

- [X] T023 [US1] Create `specs/031-stream-broker/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.5 row D4; `01-ai-platform.md` §4.3.10, §6.4, §5.5, §6.5, §9.7; what the spec delivered; what the plan scoped. **§2 What was implemented** — `src/stream/index.ts`, `src/stream/prose-guards.ts`; frozen `contracts/stream-broker.md`. **§3 Files to review** — only this slice's source, test, and contract files (`ai-platform/src/stream/`, `ai-platform/test/stream-broker.test.ts`, `specs/031-stream-broker/contracts/`). **§4 Prerequisites** — `cd ai-platform && npm install` (first time); CPU-only tests, no miniflare bindings required for this slice. **§5 Run the automated suite** — `cd ai-platform && npx vitest run test/stream-broker.test.ts`; slice-only (no full-suite `npm test`). **§6 Inspect the changes** — read the frozen contract; grep `src/stream` for `text_delta` / `heartbeat` / `cancelled` / guard kinds; run the focused test file. **No §7** — CI is the only verification path. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Review resolution (completion evidence)

Review resolution (2026-08-04) added T-D4-20..T-D4-27 (error containment, zero-usage cancel, disconnect-after-completion, journal on completed/failed, sink-throw isolation, signal-ignoring disconnect, D3 invocation adapter) and moved structured streaming to the D6-owned module `src/stream/structured.ts`. Architecture docs untouched. Original T001–T023 remain complete (unchecked tasks must not be unmarked).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T019)** — none beyond already-frozen contracts and Consumes Binding modules; written to fail before the code exists. All touch `stream-broker.test.ts` (sequential — each appends to the substrate T001 created). No `[P]` within Phase 1 (same file).
- **Implementation (T020–T021)** — depends on T001–T019 existing (red). T020 (`prose-guards.ts`) lands first; T021 (`index.ts`) depends on T020 and turns the remaining cases green. Consumed A6/D3 modules are not modified.
- **Verification (T022)** — depends on T001–T021; runs the whole suite (this slice + every prior slice) per §3.10.
- **Documentation (T023)** — depends on T022 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Within Phase 1, order follows plan Sequencing: prose-guard cases (T3–T6) → broker skeleton (T1, T7, T18) → heartbeat (T2) → cancel (T8, T9, T13, T14, T16) → credit/journal (T10, T11) → prohibitions (T12, T15, T17, T19).
- Two implementation units: guards (FR-002–FR-003) then broker (FR-001, FR-004–FR-013).

### Parallel Opportunities

- Phase 1: no `[P]` — all tests share `ai-platform/test/stream-broker.test.ts`.
- Phase 2: no `[P]` — `index.ts` imports `prose-guards.ts` (sequential).
- Phase 4 (T023) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. This slice has no `[P]` tasks — one test file and two sequential implementation files.
- Every named test T1–T19 from `spec.md` is covered by its own task (including all spy cases); no cases dropped; task list is 23 (under the 25-task cap).
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name. Clarifications Q1–Q4 guide how (module path, ticker, AbortSignal, sinks), not what.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (A6, D3).
- Consumed modules are imported, not modified (delivery plan §2.3 — extend, never rewrite).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve the I/O budget: no second Quota DO round trip, no second R2 object, no D1 row per chunk; cancel uses the existing credit shape via an injectable sink (§6.1, §7.5, §13.6).
- **Review resolution (2026-08-04):** added T-D4-20..T-D4-27 (error containment, cumulative length, live usage, journal-all-terminals, sink isolation, D3 adapter, prohibition surface); moved structured streaming to D6-owned `src/stream/structured.ts`.
