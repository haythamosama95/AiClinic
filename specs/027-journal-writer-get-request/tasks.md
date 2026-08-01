# Tasks: Journal writer, post-response detail, and get-request endpoint (C3)

**Input**: Design documents from `specs/027-journal-writer-get-request/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced (C3 defines no D1 entities and adds no column — spec `### Key Entities`: "C3 defines no new D1 entities"; the §6.3 amendment confirms the three milestone timestamps suffice). `contracts/` is written in Phase 1 (Setup) and `quickstart.md` in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` is a task, written to fail before the code exists.

**Organization**: One user story (US1, P1) — C3 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/test/`, `ai-platform/migrations/`, `ai-platform/vitest.workers.config.ts`, `ai-platform/vitest.config.ts`, `ai-platform/wrangler.toml`
- **Spec Kit artifacts**: `specs/027-journal-writer-get-request/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; C3 touches neither. No `ai-platform/migrations/` edits — the D1 schema is frozen by A5 and unchanged (the §6.3 amendment confirms the three milestone timestamps suffice; C3 adds no table and no column).

---

## Phase 1: Setup

**Purpose**: The one artifact the plan names that must exist before any test or handler binds to it — the frozen contract shapes later slices' `Consumes` will bind to (plan → Sequencing step 1: "contracts/journal.md is written first alongside the type definitions, so D3/D4/D6/F3 can bind during their own plan phase"). DP-4: a frozen, typed contract is a constraint a weak implementer cannot drift away from; prose in a spec is a suggestion.

- [X] T001 [US1] Write `specs/027-journal-writer-get-request/contracts/journal.md` freezing the three `## Slice Contract → Freezes` artifacts: (a) the **R2 payload envelope** — key `request/{id}/envelope`, JSON, the four sections `context` (the C2-filtered context payload), `prompt` (the D1-composed provider-bound prompt), `attempts[]` (raw provider response or error body per attempt), `result` (the D6-validated `CanonicalResult` terminal payload), one object per request (§7.4, §7.4.1); (b) the **get-request response** shape `{ state, terminal_error_code?, result? }` — `state` always present; `terminal_error_code` present only for `failed`; `result` (the validated terminal payload) present only for `completed`; `cancelled` returns state only; unknown reference returns not found (§5.5, §7.6); (c) the **journal write-path contract** — the stage-9 `ai_request` row shape (request id, request reference, installation, actor, branch, capability id+version, the prompt artifact hash pinned by the resolved manifest, idempotency key, trace id, the initial `Accepted` state, nullable `conversation_id`/`turn_ordinal`, null payload pointers), §6.3 transition stamping (`state`+`updated_at` overwritten per transition; the terminal transition also stamps `completed_at` and, for `failed`, `terminal_error_code` — no per-transition history table, per the §6.3 amendment), the stage-15 terminal update, and the stage-16 detail rows (N `ai_attempt` + one `usage_event` + one R2 `PutObject` + `ai_request.payload_pointer` update). D3, D4, D6, and F3 consume this artifact, not prose. **Satisfies**: the plan's `contracts/` requirement for the three Freezes entries that have wire shapes (FR-001..FR-012). Proved by every test below, which constructs inputs/outputs in these shapes.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.3 row C3 = Integration (ordering + spy), the §13.5 "Pipeline tests" layer: "Stage ordering, guard rejection paths"). All 18 run under `vitest.workers.config.ts` — C3 writes to real D1 and R2, so the workers pool (miniflare D1/R2 bindings) is required, unlike C2's CPU-only suite. The first task builds the inline-fixture substrate and is the only task that creates the file; every later test is appended to it. The first task also registers the file in `ai-platform/vitest.workers.config.ts` `test.include` and `ai-platform/vitest.config.ts` `test.exclude` (the B4/C1 precedent for D1/R2-bound tests). All tasks touch the same file (`ai-platform/test/journal.test.ts`), so none is `[P]` relative to another within this phase. The module under test (`../src/journal`) does not exist yet, so the file fails to compile from T002 onward — the intended red state. Spy assertions verify D1 insert/update counts and R2 `PutObject`/`GetObject` counts per the §3.10 coverage rule (several of this slice's invariants are about work *not* done — one R2 object, no row per chunk, no row on rejection, exactly one indexed query).

- [X] T002 [US1] Add `T-C3-01 request_row_exists_before_provider_invoked` to `ai-platform/test/journal.test.ts` (integration, ordering + spy): create the inline-fixture substrate — a `validManifest()` factory (A4's ten §5.1 field groups, including the pinned prompt artifact hash, `Economics.quotaWeight`, `Governance.retentionClass`, `interaction_mode: "single_shot"`), a `buildPrincipal({ installationId, actorId, branchId, organizationId, traceId })` fixture producing a B3 `Principal` (`Object.freeze`d), a `buildAttempt(rawResponseOrError)` fixture, a `CanonicalResult` fixture for the validated terminal payload, a fake provider (`vi.fn()`), a fake `ctx` capturing `waitUntil` promises, and a spy-wrapped D1 (counting `prepare` calls) + real miniflare R2; import `createRequestRow`, `journalTransition`, `recordTerminalState`, `writePostResponseDetail`, `getRequest` from `../src/journal`. Also register `test/journal.test.ts` in `vitest.workers.config.ts` `test.include` and `vitest.config.ts` `test.exclude`. Then the case: drive `createRequestRow` (stage 9) and assert a provider-call spy observes the `ai_request` row already present (one D1 insert) before the fake provider is invoked — stage 9 precedes stage 11 (§4.3.11, §6.1 stage 9). Satisfies FR-001, FR-002 / SC-001.
- [X] T003 [US1] Add `T-C3-02 terminal_state_completed` to `ai-platform/test/journal.test.ts` (integration): a completed request's row is updated to `completed` at stage 15 via `recordTerminalState`; `state`=`completed`, `completed_at` stamped, no `terminal_error_code` (§6.1 stage 15, §6.3). Satisfies FR-004 / SC-001.
- [X] T004 [US1] Add `T-C3-03 terminal_state_failed` to `ai-platform/test/journal.test.ts` (integration): a failed request's row is updated to `failed` at stage 15; `state`=`failed`, `completed_at` + `terminal_error_code` stamped (§6.1 stage 15, §6.3). Satisfies FR-004 / SC-001.
- [X] T005 [US1] Add `T-C3-04 terminal_state_cancelled` to `ai-platform/test/journal.test.ts` (integration): a cancelled request's row is updated to `cancelled` at stage 15; `state`=`cancelled`, `completed_at` stamped, no error code (§6.1 stage 15, §6.3). Satisfies FR-004 / SC-001.
- [X] T006 [US1] Add `T-C3-05 guard_rejected_produces_no_row` to `ai-platform/test/journal.test.ts` (integration, spy): a guard-rejected request produces zero `ai_request` inserts (spy on D1 inserts: 0) and one `platform_counter` increment — the rejection is counted, not journaled (§6.2, §7.5, §7.3). Satisfies FR-005 / SC-002 — *spy case*.
- [X] T007 [US1] Add `T-C3-06 every_state_transition_timestamped` to `ai-platform/test/journal.test.ts` (integration): for each §6.3 transition (Accepted, Composing, Invoking, Streaming, Validating, Repairing, AwaitingContext, Completed, Failed, Cancelled), `journalTransition`/`recordTerminalState` stamps `state`+`updated_at` (terminal also stamps `completed_at`); the milestones + deterministic §6.3 graph recover the timeline (§4.3.11, §6.3, §8.9). Parameterised: one case per transition. Satisfies FR-003 / SC-003.
- [X] T008 [US1] Add `T-C3-07 row_survives_failed_generation` to `ai-platform/test/journal.test.ts` (integration): a failed generation leaves the `ai_request` row present, carrying the failure's terminal state — no delete on failure (§4.3.11). Satisfies FR-006 / SC-001.
- [X] T009 [US1] Add `T-C3-08 exactly_one_r2_putobject_per_request` to `ai-platform/test/journal.test.ts` (integration, spy): drive `writePostResponseDetail` and assert exactly one R2 `PutObject` per request, keyed `request/{id}/envelope` (spy on R2: 1); a second `PutObject` is provably absent (§7.4, §7.4.1). Satisfies FR-007, FR-012 / SC-004 — *spy case*.
- [X] T010 [US1] Add `T-C3-09 envelope_contains_all_four_sections` to `ai-platform/test/journal.test.ts` (integration): the envelope document (JSON) written by `writePostResponseDetail` contains the `context`, `prompt`, `attempts[]`, and `result` sections with the fixture inputs (§7.4). Satisfies FR-007 / SC-004.
- [X] T011 [US1] Add `T-C3-10 one_ai_attempt_row_per_attempt` to `ai-platform/test/journal.test.ts` (integration, spy): N provider attempts produce exactly N `ai_attempt` rows via `writePostResponseDetail` (spy on D1 inserts: N), never one row per stream chunk (§7.3, §6.1 stage 16). Parameterised: N=2 and N=3. Satisfies FR-008 / SC-005 — *spy case*.
- [X] T012 [US1] Add `T-C3-11 exactly_one_usage_event` to `ai-platform/test/journal.test.ts` (integration, spy): exactly one `usage_event` row is written per request via `writePostResponseDetail` (spy on D1 inserts: 1), never more than one (§7.3, §6.1 stage 16). Satisfies FR-008 / SC-005 — *spy case*.
- [X] T013 [US1] Add `T-C3-12 stage16_failure_does_not_fail_request` to `ai-platform/test/journal.test.ts` (integration): an injected R2/D1 failure in stage 16 does not fail the request — `writePostResponseDetail` returns normally (the failure is swallowed inside `ctx.waitUntil`), and the terminal event already emitted stands (§6.1 stage 16, §3.11.3). Satisfies FR-009 / SC-006.
- [X] T014 [US1] Add `T-C3-13 stage16_runs_after_terminal_event` to `ai-platform/test/journal.test.ts` (integration, ordering + spy): the terminal-event spy is called before any stage-16 write — the terminal emit precedes `ctx.waitUntil`'s writes (§6.1 stage 14 precedes stage 16). Satisfies FR-009 / SC-006 — *spy case*.
- [X] T015 [US1] Add `T-C3-14 get_request_completed_returns_state_and_result` to `ai-platform/test/journal.test.ts` (integration): a completed request's reference returns state plus the validated result via `getRequest`, through one indexed D1 lookup + one R2 `GetObject` for the `result` section (§5.5, §7.6, §7.4). Satisfies FR-010 / SC-007.
- [X] T016 [US1] Add `T-C3-15 get_request_failed_returns_state_and_error_no_content` to `ai-platform/test/journal.test.ts` (integration): a failed request's reference returns state plus the terminal error code and no content (no R2 read) (§5.5, §7.6). Satisfies FR-010 / SC-007.
- [X] T017 [US1] Add `T-C3-16 get_request_cancelled_returns_state_only` to `ai-platform/test/journal.test.ts` (integration): a cancelled request's reference returns state only (no R2 read) (§5.5, §7.6). Satisfies FR-010 / SC-007.
- [X] T018 [US1] Add `T-C3-17 get_request_unknown_reference_returns_not_found` to `ai-platform/test/journal.test.ts` (integration): an unknown reference returns not found, via the indexed lookup (§5.5, §7.6). Satisfies FR-010 / SC-007.
- [X] T019 [US1] Add `T-C3-18 get_request_uses_exactly_one_indexed_query` to `ai-platform/test/journal.test.ts` (integration, spy): the get-request path performs exactly one indexed D1 lookup on `request_reference` (spy on D1 queries: 1), with no second lookup or table scan; failed/cancelled perform no R2 read (§7.6). Satisfies FR-011 / SC-007 — *spy case*.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: The two implementation units named in `plan.md` → Files. `ai-platform/src/journal/index.ts` (Created) holds all five exported functions and the inlined envelope builder (Clarification Q2: "a single `journal/` module, with the envelope builder inlined as an internal helper"). `ai-platform/src/worker.ts` (Modified) adds the `GET /v1/requests/{reference}` route. The consumed modules (`identity/`, `manifest/`, `capability/`, `errors.ts`, `reference.ts`, `contracts/canonical.ts`, `adapter.ts`, `quota-do/`) are imported, not modified (delivery plan §2.3). Tests turn green in matching groups per the plan's Sequencing: T-C3-01/05/07 with the stage-9 functions, T-C3-06/02/03/04 with the transition/terminal functions, T-C3-09/08/10/11/13/12 with the stage-16 continuation, T-C3-14..18 with `getRequest` + the route.

- [ ] T020 [US1] Create `ai-platform/src/journal/index.ts` — export the input/result types and the five functions: `RequestRowInput` and `createRequestRow(input, db): {ok:true} | {ok:false, code:"internal_error"}` (stage 9 — synchronous D1 INSERT of the `ai_request` row with request id, request reference, installation, actor, branch, capability id+version, the manifest-pinned prompt artifact hash, idempotency key, trace id, the initial `Accepted` state, nullable `conversation_id`/`turn_ordinal` (null for `single_shot`), null payload pointers; `internal_error` via A2's `buildErrorBody` on D1 insert failure, failing the request before the provider is called); `TransitionState` (the §6.3 states) and `journalTransition(requestId, state, now, db)` (stamps `state`+`updated_at`; terminal also stamps `completed_at`, per the §6.3 amendment — no per-transition history table); `recordTerminalState(requestId, state, terminalErrorCode?, now, db)` (stage 15 — terminal state + `terminal_error_code` when failed; no client error); `AttemptInput`, `PostResponseInput`, `Envelope`, the inlined `buildEnvelope(input): string` JSON helper (four sections `context`/`prompt`/`attempts[]`/`result`), and `writePostResponseDetail(input, {db, r2, ctx})` scheduling the stage-16 writes via `ctx.waitUntil` (N `ai_attempt` inserts + one `usage_event` insert + one R2 `PutObject` keyed `request/{id}/envelope` + `ai_request.payload_pointer` update; failures swallowed inside the continuation, never surfaced to the client); `GetRequestResult` and `getRequest(reference, {db, r2}): GetRequestResult` (one indexed D1 lookup on `request_reference` via A2's `normalizeRequestReference`; `completed`→state+result via one R2 `GetObject` for the `result` section; `failed`→state+terminal_error_code, no R2 read; `cancelled`→state only, no R2 read; unknown→not found). No DO I/O (stage-15 credit is B4's contract); no per-request server-side state (§4.4, §9.7); no second R2 object (§7.4.1). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012; **proved by**: T-C3-01 through T-C3-18.
- [ ] T021 [US1] Modify `ai-platform/src/worker.ts` — add the `GET /v1/requests/{reference}` route: normalise the reference via A2's `normalizeRequestReference`, call `getRequest` from `../src/journal`, and map `GetRequestResult` to a JSON `Response` (`completed`→200 with state+result, `failed`→200 with state+terminal_error_code and no content, `cancelled`→200 with state only, unknown→404). The POST submit stream (A6) and control routes are unchanged (delivery plan §2.3 — extend, never rewrite). **Satisfies**: FR-010, FR-011; **proved by**: T-C3-14 through T-C3-18. Depends on T020.

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest. A checkpoint requires every prior suite green, not only this slice's.

- [ ] T022 [US1] From `ai-platform/`, run `npx vitest run test/journal.test.ts --config vitest.workers.config.ts` (this slice's 18 integration cases, all under the workers pool — C3 writes real D1 + R2), then run the full prior suite — `npx vitest run` (the default Node-pool config covering prior slices' unit tests: `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `context-validator.test.ts` (C2)) and `npx vitest run --config vitest.workers.config.ts` (the workers-pool prior suites: `control.test.ts` (B2), `identity.test.ts`, `entitlement.test.ts`, `rate-limit.test.ts` (B3), `admission-credit.test.ts`, `quota-do.test.ts` (B4), `capability.test.ts` (C1); `context.test.ts`, `config-cache.test.ts`, `migrations.test.ts` (A5); `adapter.test.ts` (A6)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate, not extra work. Assert no test was added to a §13.5 layer the architecture does not name. **Satisfies**: the §3.10 checkpoint rule (every error code C3 emits — `internal_error` on stage-9 insert failure — every branch — completed/failed/cancelled/guard-rejected/stage-16-failure — every named boundary — one R2 object, one `usage_event`, N `ai_attempt`, exactly one indexed query, no R2 read on failed/cancelled). Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. `contracts/journal.md` was written in Phase 1 (Setup), not here — the plan's Sequencing places it first so downstream slices can bind during their own plan phase.

- [ ] T023 [US1] Create `specs/027-journal-writer-get-request/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.4 row C3; the §4.3.11 / §6.1-stages-9-15-16 / §6.3 / §7.4 / §7.4.1 / §7.6 / §5.5 sections; what the spec delivered; what the plan scoped. **§2 What was implemented** — the `src/journal/index.ts` stage-9 `createRequestRow` + §6.3 `journalTransition` + stage-15 `recordTerminalState` + stage-16 `writePostResponseDetail` (inlined `buildEnvelope`) + `getRequest` read function; the `worker.ts` `GET /v1/requests/{reference}` route. **§3 Files to review** — `ai-platform/src/journal/index.ts`, `ai-platform/src/worker.ts`, `ai-platform/test/journal.test.ts`, `specs/027-journal-writer-get-request/contracts/journal.md`. **§4 Prerequisites** — `cd ai-platform && npm install` (first time); the workers-pool tests need the miniflare D1/R2 bindings from `wrangler.toml` (already configured for prior slices). **§5 Run the automated suite** — `cd ai-platform && npx vitest run test/journal.test.ts --config vitest.workers.config.ts`; slice-only (no `npm test` for the full platform suite). **§6 Inspect the changes** — grep `src/journal/index.ts` for the envelope key `request/{id}/envelope`, read the frozen `contracts/journal.md`, run a focused test file, query the `ai_request` row after a fixture run. **No §7** — CI is the only verification path (C3 exposes no user-facing behaviour beyond the suite and the get-request route, which the suite covers end-to-end). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — none; write the frozen contract shapes first so the implementation, the tests, and downstream slices' plans bind to a frozen artifact, not prose (DP-4; plan → Sequencing step 1).
- **Tests (T002–T019)** — depend on T001 (request/response shapes); written to fail before the code exists. T002 also registers `test/journal.test.ts` in `vitest.workers.config.ts` `test.include` and `vitest.config.ts` `test.exclude` (the B4/C1 precedent for D1/R2-bound tests). The module under test is absent, so the file is red until Phase 3 lands.
- **Implementation (T020–T021)** — T020 (`src/journal/index.ts`) first; T021 (`worker.ts` route) depends on T020 exporting `getRequest`. Tests turn green in matching groups per the plan's Sequencing (stage 9 → transitions → stage 16 → get-request).
- **Verification (T022)** — depends on T002–T021; runs the whole suite (this slice + every prior slice) per §3.10.
- **Documentation (T023)** — depends on T022 (the quickstart records a green suite).

### Within the Slice

- Contract (T001) before tests (T002–T019) and implementation (T020).
- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- T021 (worker route) after T020 (the `getRequest` export it calls).

### Parallel Opportunities

- Phase 2 (T002–T019) all touch the same file (`journal.test.ts`) — no `[P]`; sequential, each appending to the substrate T002 created.
- Phase 3 (T020, T021) touch the same logical component and T021 depends on T020 — no `[P]`; sequential.
- Phase 5 (T023) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Within a single-file phase there is no `[P]`; this slice has none — every phase is single-file or ordered by a dependency.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (A2, A3, A4, A5, A6, B3, B4, C1, C2).
- The consumed modules (`identity/`, `manifest/`, `capability/`, `errors.ts`, `reference.ts`, `contracts/canonical.ts`, `adapter.ts`, `quota-do/`) and `worker.ts`'s existing routes are not modified by any task (delivery plan §2.3 — extend, never rewrite); only `worker.ts` is extended with the new GET route.
- Tests land before or alongside their implementation, never after (delivery plan §2.2); the test file plus the diff is the review artifact.
- The seven spy/ordering cases (T-C3-01, T-C3-05, T-C3-08, T-C3-10, T-C3-11, T-C3-13, T-C3-18) are separate named tests that assert call counts/absences/orderings on D1/R2/ctx spies — separate work from asserting an outcome, per the task-out rules.
- Preserve the I/O budget: one D1 insert at stage 9, one R2 object at stage 16, one indexed D1 lookup on the read path — no second R2 object, no DO I/O (stage-15 credit is B4's), no per-request server-side state (§7.4.1, §7.5, §4.4, §9.7).
