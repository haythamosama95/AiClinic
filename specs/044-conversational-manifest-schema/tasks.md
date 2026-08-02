---

description: "Task list for AI platform slice H1 — Conversational manifest fields and context-request schema"
---

# Tasks: Conversational manifest fields and context-request schema (H1)

**Input**: Design documents from `/specs/044-conversational-manifest-schema/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is omitted — H1 defines no D1 entity (spec Key Entities; FR-011). The three `contracts/*.md` artifacts are already frozen on disk (written during the plan phase). `quickstart.md` is a plan-phase skeleton completed in Phase 4 (Documentation).

**Tests**: Mandatory, not optional (delivery plan §3.10 overrides the template). Every named test in the spec's Test plan — including the four §3.10 coverage additions — is a task, written to fail before the implementation exists. The parameterized name `shared_context_request_schema_rejects_malformed_<form>` is one task covering the four malformed forms named in the plan's Test Layout (same file, same FR-007 cluster).

**Organization**: One slice, one user story (US1). No multi-story phases, no Setup phase (no config/migration must exist first), no Foundational phase (prerequisites are already-merged A2/A4/A6), no Polish phase (R-20).

**Task count**: 24 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: `US1` — the slice's one user story
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — not touched by this slice
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — not touched by this slice
- **AI platform Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — this slice lives here (no `migrations/` edits — H1 adds no D1 schema)
- **Spec artifacts**: `specs/044-conversational-manifest-schema/`

---

## Phase 1: Tests

**Purpose**: Write every named test from the spec's Test plan into the four files named in `plan.md` → Test Layout / Files, each failing before the matching implementation exists. Order follows plan Sequencing (context-request → manifest → AwaitingContext → terminal kinds). First task in each file creates the substrate plus the first case; later tasks in the same file append. Modules under test lack the H1 branches yet, so cases fail to compile or fail assertions — the intended red state. All four files run under the default Node pool (`vitest.config.ts`); no workers-pool registration.

### Context-request schema (`context-request.test.ts`)

- [X] T001 [US1] Add `shared_context_request_schema_accepts_conforming` to `ai-platform/test/context-request.test.ts` (contract): create the substrate — imports of `validateContextRequest` (and related types) from `../src/context/context-request`; fixtures for a conforming list of `{key, arguments}`. Then the case: a well-formed list validates successfully (§6.7.2; delivery plan §3.11.7 H1). Satisfies FR-007 / SC-006. File fails to compile (module absent) or assertions fail.
- [X] T002 [US1] Add `shared_context_request_schema_rejects_malformed_<form>` to `ai-platform/test/context-request.test.ts` (contract): one rejection subcase per malformed form — (1) not a list; (2) element missing `key`; (3) element missing `arguments`; (4) element that is not a `{key, arguments}` object — each rejected by the shared schema (§6.7.2). Satisfies FR-007 / SC-006.
- [X] T003 [US1] Add `context_request_schema_is_platform_owned_not_per_capability` to `ai-platform/test/context-request.test.ts` (contract): assert every conversational capability shares the same `{key, arguments}` list schema; the validator does not accept a per-capability alternate shape (§6.7.2; §3.10). Satisfies FR-007.
- [X] T004 [US1] Add `no_new_pipeline_stage_from_conversational_mode` to `ai-platform/test/context-request.test.ts` (contract): assert declaring `conversational` does not introduce a new §6.1 stage — stage 13 gains a second valid output shape and stage 14 a fourth terminal event kind only (§6.7.4; §3.10). Satisfies FR-011.
- [X] T005 [US1] Add `no_per_request_server_state_from_h1` to `ai-platform/test/context-request.test.ts` (contract): assert H1 introduces no conversation table and no per-request Durable Object or session store (§6.7.4; delivery plan §6.4; §3.10). Satisfies FR-011.

### Conversational manifest (`conversational-manifest.test.ts`)

- [X] T006 [P] [US1] Add `conversational_manifest_loads_all_four_extra_fields` to `ai-platform/test/conversational-manifest.test.ts` (contract/build): create the substrate — imports of `load`, `hashManifest`, `verifyPublishedRegistry`, and `Manifest` from `../src/manifest`; a `validConversationalManifest()` factory declaring `interactionMode: "conversational"` plus max history turns, max context rounds per turn, transcript size limit, and permitted key set (keys from A5's published vocabulary); helpers to omit each conversational extra and to attach conversational fields onto a `single_shot` fixture. Then the case: `load(validConversationalManifest())` returns a typed `Manifest` with all four extras present and well-formed (§5.1; delivery plan §3.11.7 H1). Satisfies FR-001, FR-002 / SC-001. `[P]` vs `context-request.test.ts` (different file).
- [X] T007 [US1] Add `conversational_manifest_omits_max_history_turns_fails` to `ai-platform/test/conversational-manifest.test.ts` (contract/build): a `conversational` manifest omitting max history turns fails `load()`, naming that omission (§5.1 Interaction row). Satisfies FR-001 / SC-002.
- [X] T008 [US1] Add `conversational_manifest_omits_max_context_rounds_fails` to `ai-platform/test/conversational-manifest.test.ts` (contract/build): a `conversational` manifest omitting max context rounds per turn fails `load()`, naming that omission (§5.1 Interaction row). Satisfies FR-001 / SC-002.
- [X] T009 [US1] Add `conversational_manifest_omits_transcript_size_limit_fails` to `ai-platform/test/conversational-manifest.test.ts` (contract/build): a `conversational` manifest omitting transcript size limit fails `load()`, naming that omission (§5.1 Interaction row). Satisfies FR-001 / SC-002.
- [X] T010 [US1] Add `conversational_manifest_omits_permitted_key_set_fails` to `ai-platform/test/conversational-manifest.test.ts` (contract/build): a `conversational` manifest omitting the permitted key set fails `load()`, naming that omission (§5.1 Context requirements row). Satisfies FR-002 / SC-002.
- [X] T011 [US1] Add `conversational_fields_rejected_on_single_shot` to `ai-platform/test/conversational-manifest.test.ts` (contract/build): a `single_shot` manifest carrying any conversational-only field (max history turns, max context rounds per turn, transcript size limit, or permitted key set) fails `load()` (§5.1; A14). Satisfies FR-003 / SC-003.
- [X] T012 [US1] Add `interaction_mode_in_place_change_fails_build` to `ai-platform/test/conversational-manifest.test.ts` (build): changing `interactionMode` in place on a published version (registry hash vs on-disk edit between `single_shot` and `conversational`) fails `verifyPublishedRegistry` rather than accepting the edit (§5.7). Satisfies FR-004 / SC-004.
- [X] T013 [US1] Add `permitted_key_set_unknown_key_fails` to `ai-platform/test/conversational-manifest.test.ts` (contract/build): a `conversational` manifest whose permitted key set names a key unknown to A5's published vocabulary fails `load()` via `validateKey` (§5.1; A14). Satisfies FR-006 / SC-005.
- [X] T014 [US1] Add `interaction_mode_fixed_for_life_of_version` to `ai-platform/test/conversational-manifest.test.ts` (contract): a loaded manifest's `interactionMode` is immutable for that version — readonly / no in-place mutation; changing it requires a new version (§5.7; §3.10). Satisfies FR-004.

### AwaitingContext (`awaiting-context.test.ts`)

- [X] T015 [P] [US1] Add `awaiting_context_is_terminal_and_immutable` to `ai-platform/test/awaiting-context.test.ts` (contract/integration): create the substrate — imports of journal terminal-state / reachability helpers from `../src/journal`; fixtures distinguishing `conversational` vs `single_shot` manifests. Then the case: when a conversational leg reaches `AwaitingContext`, that state is terminal and no further state transition out of it is allowed; reachability is conversational-only (§6.3; §6.7.2). Satisfies FR-010 / SC-008. `[P]` vs the other H1 test files (different file).

### Fourth terminal kind (`context-requested-terminal.test.ts`)

- [X] T016 [P] [US1] Add `context_requested_absent_from_error_taxonomy` to `ai-platform/test/context-requested-terminal.test.ts` (contract): create the substrate — imports of A2 taxonomy/`isTaxonomyCode`/`buildErrorBody` from `../src/errors` and adapter terminal helpers from `../src/adapter`; stub/fake stream helpers gated on `interactionMode` (Clarification Q2). Then the case: `context_requested` is absent from the §5.4 taxonomy and is not buildable as an error-body code (§5.4). Satisfies FR-008 / SC-007. `[P]` vs the other H1 test files (different file).
- [X] T017 [US1] Add `single_shot_never_emits_context_requested` to `ai-platform/test/context-requested-terminal.test.ts` (integration): drive A6 stub/terminal helpers with `interactionMode: "single_shot"`; assert the stream's terminal event is one of `completed` / `failed` / `cancelled` and never `context_requested` (§5.5 rule 4; §6.7.4; Clarification Q2). Satisfies FR-009 / SC-009.
- [X] T018 [US1] Add `conversational_leg_still_one_terminal_event` to `ai-platform/test/context-requested-terminal.test.ts` (integration): drive stub helpers with `interactionMode: "conversational"` ending in `context_requested`; assert exactly one terminal event is emitted for that leg (A6 one-terminal-event invariant preserved) (§5.5 rule 4; Clarification Q2). Satisfies FR-009 / SC-009.

**Checkpoint**: All four H1 test files exist and every named case fails (red). No implementation has landed yet.

---

## Phase 2: Implementation

**Purpose**: The four implementation units named in `plan.md` → Files (source rows). Consumed modules (`errors.ts` A2, `context/index.ts` A5 `validateKey`) are imported, not modified. Tests turn green in matching groups per plan Sequencing. All four touch different files and are `[P]` relative to each other once Phase 1 is red.

- [X] T019 [P] [US1] Create `ai-platform/src/context/context-request.ts` — platform-owned list-of-`{key, arguments}` schema and `validateContextRequest()` (hand-rolled TS narrowing, no schema-validation library — R-20). Shared by every conversational capability; rejects each malformed form; does not accept a per-capability alternate shape; introduces no pipeline stage and no per-request store. **Satisfies**: FR-007, FR-011. **Proved by**: T001–T005.
- [X] T020 [P] [US1] Extend `ai-platform/src/manifest/index.ts` — when `interactionMode` is `conversational`, require max history turns, max context rounds per turn, and transcript size limit on Interaction; require permitted key set as the Context-requirements form; reject unknown permitted keys via A5 `validateKey`; widen `single_shot` rejection to include the permitted key set; keep omitted-mode default `single_shot`, the ten-group schema, and published-version hash check intact (extend, never rewrite A4). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006. **Proved by**: T006–T014.
- [X] T021 [P] [US1] Extend `ai-platform/src/journal/index.ts` — export / enforce `AwaitingContext` as a terminal immutable §6.3 state (peer of `Completed` / `Failed` / `Cancelled`); conversational-only reachability helper for entering `AwaitingContext`; no new table, no per-request store. **Satisfies**: FR-010. **Proved by**: T015.
- [X] T022 [P] [US1] Extend `ai-platform/src/adapter.ts` — add `context_requested` to `TERMINAL_EVENT_KINDS`; extend stub/terminal helpers to accept `interactionMode` and allow emission only for `conversational` (deny for `single_shot`); preserve the three existing terminal kinds and the one-terminal-event invariant (Clarification Q2). Do not modify `errors.ts`. **Satisfies**: FR-008, FR-009. **Proved by**: T016–T018.

**Checkpoint**: `npx vitest run test/context-request.test.ts test/conversational-manifest.test.ts test/awaiting-context.test.ts test/context-requested-terminal.test.ts` green.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside this slice's suite, not just the latest.

- [ ] T023 [US1] From `ai-platform/`, run this slice's four test files — `npx vitest run test/context-request.test.ts test/conversational-manifest.test.ts test/awaiting-context.test.ts test/context-requested-terminal.test.ts` — then run every prior suite: `npx vitest run` (default Node-pool) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm H1's named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (manifest load/omit/reject/unknown-key, shared schema accept/reject, taxonomy absence, `AwaitingContext` terminal, `single_shot` never emits fourth kind, one-terminal invariant, §3.10 coverage prohibitions). Proved by itself.

**Checkpoint**: Full platform suite green. No regressions into A2/A4/A6 or later bands.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that is not yet complete on disk (`quickstart.md` skeleton → filled); written only after the suite is green. The three contracts were already frozen during the plan phase — no separate contract tasks. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T024 [US1] Complete `specs/044-conversational-manifest-schema/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.8 row H1; `17-ai-platform.md` §5.1, §5.7, §6.7.4, §6.7.2, §5.5, §5.4, §6.3, A14; what the spec delivered; what the plan scoped. **§2 What was implemented** — conversational Interaction + permitted key set load rules in `src/manifest/`; shared `{key, arguments}` schema in `src/context/context-request.ts`; `AwaitingContext` terminal helpers in `src/journal/`; `context_requested` terminal kind in `src/adapter.ts`; frozen `contracts/*.md`. **§3 Files to review** — only this slice's source, test, and contract files (no prior-slice files). **§4 Prerequisites** — omit (`cd ai-platform && npm install` first time only). **§5 Run the automated suite** — `npx vitest run test/context-request.test.ts test/conversational-manifest.test.ts test/awaiting-context.test.ts test/context-requested-terminal.test.ts`; slice-only (no full-suite `npm test`). **§6 Inspect the changes** — read the three frozen contracts; open the four source modules; run the focused test files. **No §7** — CI is the only verification path (plan: Manual validation omitted). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T018)**: No Setup phase. Written to fail before the code exists. Within each file, tasks are sequential (append order). Cross-file first tasks (T001, T006, T015, T016) are `[P]` relative to each other.
- **Implementation (T019–T022)**: Depends on Tests phase existing (red). All four are `[P]` relative to each other (different files). Matching green groups: T019 ↔ T001–T005; T020 ↔ T006–T014; T021 ↔ T015; T022 ↔ T016–T018.
- **Verification (T023)**: Depends on Implementation green; runs this slice plus every prior slice per §3.10.
- **Documentation (T024)**: Depends on Verification green; records a green suite.

### Within the Slice

- Tests are written and confirmed failing before any implementation.
- Plan Sequencing (context-request → manifest → journal → adapter) is reflected in test-file order and in which implementation unit turns which cases green.
- The quickstart is written last and cites only this slice's files and commands.
- Contracts are already on disk from the plan phase — Documentation does not re-author them.

### Parallel Opportunities

- Phase 1: T006 (`conversational-manifest.test.ts`), T015 (`awaiting-context.test.ts`), and T016 (`context-requested-terminal.test.ts`) are `[P]` relative to T001–T005 (`context-request.test.ts`) and to each other — different files. Within each file, append tasks are sequential.
- Phase 2: T019–T022 touch four different source files and may run in parallel once Phase 1 is red.
- Phase 4: single task — no `[P]`.

---

## Parallel Example: User Story 1

```bash
# Launch the four H1 test-file substrates together:
Task: "shared_context_request_schema_accepts_conforming in ai-platform/test/context-request.test.ts"
Task: "conversational_manifest_loads_all_four_extra_fields in ai-platform/test/conversational-manifest.test.ts"
Task: "awaiting_context_is_terminal_and_immutable in ai-platform/test/awaiting-context.test.ts"
Task: "context_requested_absent_from_error_taxonomy in ai-platform/test/context-requested-terminal.test.ts"

# Launch the four implementation units together (after tests are red):
Task: "Create ai-platform/src/context/context-request.ts"
Task: "Extend ai-platform/src/manifest/index.ts"
Task: "Extend ai-platform/src/journal/index.ts"
Task: "Extend ai-platform/src/adapter.ts"
```

---

## Notes

- Tests are mandatory (delivery plan §3.10 overrides the template's "Tests are OPTIONAL" note).
- One slice, one story (US1) — the template's multi-story, Foundational, and Polish phases are deleted, not left empty.
- Every task traces to an `FR-###` from `spec.md` and to a named test from its Test plan (or the Documentation/Verification mandate); nothing is added that the spec/plan do not name.
- Clarifications Q1–Q2 guide placement (`src/manifest/`, `src/context/context-request.ts`, `src/adapter.ts`) and integration-test construction (A6 stub helpers gated on `interactionMode`) — implementation choices, not new requirements.
- No new runtime dependency; schemas are hand-rolled TS narrowing (R-20).
- Consumed modules (`errors.ts`, A5 `validateKey` in `context/index.ts`) are not rewritten (delivery plan §2.3).
- FR-005 (omitted mode defaults to `single_shot`) remains A4's frozen default — H1 does not rewrite it; FR-012 (capability always named) is restated A14 policy with no separate H1 named test.
