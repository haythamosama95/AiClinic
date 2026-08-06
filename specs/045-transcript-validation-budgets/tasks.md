---

description: "Task list for AI platform slice H2 — Transcript validation, conversation budgets, and composer rendering"
---

# Tasks: Transcript validation, conversation budgets, and composer rendering (H2)

**Input**: Design documents from `/specs/045-transcript-validation-budgets/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is omitted — H2 defines no D1 entity (spec Key Entities; FR-019). The three `contracts/*.md` artifacts are already frozen on disk (written during the plan phase). `quickstart.md` is named in the plan and filled in Phase 4 (Documentation).

**Tests**: Mandatory, not optional (delivery plan §3.10 overrides the template). Every named test in the spec's Test plan — including the five §3.10 coverage additions — must appear in some task's acceptance criteria and be written to fail before the matching implementation exists. Related cases that share one test file are grouped into a single task where noted; grouping does not drop coverage.

**Organization**: One slice, one user story (US1). No multi-story phases, no Setup phase (contracts already frozen; no config/migration must exist first), no Foundational phase (prerequisites are already-merged C2/D1/D6/H1), no Polish phase (R-20).

**Task count**: 19 (≤25). Combined from a naive 28 (22 named-test tasks + 4 impl + verification + docs) by grouping related same-file tests and treating `validate/phases.ts` + `validate/index.ts` as one dual-shape implementation unit (plan Sequencing step 4).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: `US1` — the slice's one user story
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — not touched by this slice
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — not touched by this slice
- **AI platform Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — this slice lives here (no `migrations/` edits — H2 adds no D1 schema)
- **Spec artifacts**: `specs/045-transcript-validation-budgets/`

---

## Phase 1: Tests

**Purpose**: Write every named test from the spec's Test plan into the three files named in `plan.md` → Test Layout / Files, each failing before the matching implementation exists. Order follows plan Sequencing (validator/transcript → composer → response dual-shape). First task in each file creates the substrate plus the first case(s); later tasks in the same file append. Modules under test lack the H2 conversational branches yet, so cases fail to compile or fail assertions — the intended red state. All three files run under the default Node pool (`vitest.config.ts`); no workers-pool registration.

### Transcript validation (`transcript-validation.test.ts`)

- [X] T001 [US1] Add `valid_transcript_passes` to `ai-platform/test/transcript-validation.test.ts` (unit): create the substrate — imports of `validateContext` / conversational `ValidateResult` from `../src/context/validator`; fixtures for a `conversational` manifest (H1 fields: max history turns, max context rounds, permitted key set) and a well-formed `transcript` array with strictly increasing `turn_ordinal` values below the leg's own and the four declared `kind`/payload pairings. Then the case: the transcript passes (§4.3.5; §6.7.1; delivery plan §3.11.7 H2). Satisfies FR-001, FR-003 / SC-001. File fails to compile (branches absent) or assertions fail.
- [X] T002 [US1] Add `out_of_order_turn_ordinal_rejected_context_invalid` to `ai-platform/test/transcript-validation.test.ts` (unit): an out-of-order, duplicate, missing, or non-integer `turn_ordinal`, or one not strictly less than the leg's own, is rejected with `context_invalid` (§4.3.5; §6.7.1; §5.4). Satisfies FR-004, FR-005 / SC-001.
- [X] T003 [US1] Add `malformed_turn_shape_rejected_context_invalid` to `ai-platform/test/transcript-validation.test.ts` (unit): a turn with no payload field, the wrong payload field for its `kind`, or a payload of the wrong type is rejected with `context_invalid` (§4.3.5; §6.7.1; §5.4). Satisfies FR-005 / SC-001.
- [X] T004 [US1] Add `unknown_turn_kind_rejected_context_invalid` to `ai-platform/test/transcript-validation.test.ts` (unit): a `kind` outside `user` / `model` / `context_requested` / `context_resolved` is rejected with `context_invalid` (§6.7.1; §4.3.5; §5.4). Satisfies FR-005 / SC-001.
- [X] T005 [US1] Add `transcript_rejected_whole_not_coerced_or_dropped` and `shape_checked_before_budgets` to `ai-platform/test/transcript-validation.test.ts` (unit): (1) one malformed turn rejects the whole transcript — no turn coerced or silently dropped (§6.7.1); (2) a transcript that is both malformed and over the history-turn limit fails with `context_invalid` and emits no budget code (§6.7.3; §4.3.5). Satisfies FR-006, FR-007 / SC-002, SC-003.
- [X] T006 [US1] Add `history_turn_limit_breached_conversation_budget_exhausted` and `budgets_counted_from_submitted_transcript_alone` to `ai-platform/test/transcript-validation.test.ts` (unit): (1) exceeding max history turns (counted from the submitted transcript) yields `conversation_budget_exhausted` (§6.7.3); (2) max history turns and max context rounds are computed only from the submitted request — no platform-held conversation counter is consulted (§6.7.3; §6.7.1; §3.10). Satisfies FR-008, FR-009, FR-010 / SC-004.
- [X] T007 [US1] Add `context_rounds_at_tail_breached_conversation_budget_exhausted` to `ai-platform/test/transcript-validation.test.ts` (unit): consecutive `context_requested` turns at the transcript tail exceeding max context rounds per turn yields `conversation_budget_exhausted` (§6.7.3). Satisfies FR-008, FR-010 / SC-005.
- [X] T008 [US1] Add `key_outside_permitted_set_dropped` to `ai-platform/test/transcript-validation.test.ts` (unit spy): a key inside a `context_resolved` turn outside the permitted set is dropped (not a rejection) and is absent from the composer input even when requested by the model and supplied by the client (§4.3.5; §6.7.1). Satisfies FR-006, FR-011 / SC-006.
- [X] T009 [US1] Add `oversized_transcript_request_too_large` and `per_turn_cost_ceiling_uses_existing_preflight_no_new_mechanism` to `ai-platform/test/transcript-validation.test.ts` (unit spy): (1) an oversized transcript fails the existing cost pre-flight with `request_too_large` and produces no egress (§6.7.3); (2) transcript growth is priced only by the existing pre-flight — no running conversation total and no §9.14 reservation (§6.7.3; delivery plan §6.4; §3.10). Satisfies FR-012 / SC-007.
- [X] T010 [US1] Add `trimmed_transcript_accepted_bounded_by_admission` to `ai-platform/test/transcript-validation.test.ts` (unit): a trimmed transcript with `turn_ordinal` gaps is legal and accepted for budget counting; containment remains per-leg authentication, rate limiting, cost check, and admission (R-22; §6.7.3). Satisfies FR-013 / SC-008.
- [X] T011 [US1] Add `no_per_request_server_state_from_h2` and `single_shot_unaffected_by_h2` to `ai-platform/test/transcript-validation.test.ts` (unit spy / unit): (1) H2 introduces no conversation store and no per-request Durable Object or session object (§6.7.1; delivery plan §6.4; §3.10); (2) a `single_shot` capability does not acquire transcript validation, budget codes, or the second output shape from this slice's existence (§6.7 conversational preamble; delivery plan §3.8; §3.10). Satisfies FR-019.

### Conversational composer (`conversational-composer.test.ts`)

- [X] T012 [P] [US1] Add `transcript_renders_as_delimited_typed_prior_turns` and `role_tags_user_assistant_data_for_transcript` to `ai-platform/test/conversational-composer.test.ts` (golden): create the substrate — imports of `composeRequest` from `../src/prompt/composer`; fixtures for a validated conversational transcript and filtered context; golden fixtures for composed parts. Then the cases: (1) composed request renders the transcript as delimited typed prior turns on the same footing as context (§4.3.6); (2) `user` turns render as `user` parts, `model` turns as `assistant` parts, `context_resolved` turns as `data` parts, and ordinary context as `data` — no invented role tag (§4.3.6; §6.7.1; §3.10). Satisfies FR-014, FR-015, FR-016 / SC-009. `[P]` vs `transcript-validation.test.ts` (different file).
- [X] T013 [US1] Add `instruction_in_user_turn_does_not_act_as_instruction` and `composer_no_distinction_chat_vs_clinical_free_text` to `ai-platform/test/conversational-composer.test.ts` (unit/golden): (1) an instruction embedded in a user turn does not act as an instruction (R-10; §4.3.6); (2) chat text and clinical free text are rendered equivalently as delimited typed data (§4.3.6). Satisfies FR-015 / SC-009.

### Conversational response validator (`conversational-response-validator.test.ts`)

- [X] T014 [P] [US1] Add `prose_answer_validates`, `context_request_validates`, and `output_neither_prose_nor_context_request_fails` to `ai-platform/test/conversational-response-validator.test.ts` (unit): create the substrate — imports of `validateAndRepair` / `runValidationPhases` from `../src/validate`; fixtures for conversational vs `single_shot` manifests; prose and `{key, arguments}` context-request samples drawn from the permitted set; a neither-shape sample. Then the cases: (1) a valid prose answer passes (§4.3.6; §6.7.2); (2) a conforming context request passes (§6.7.2); (3) output that is neither fails under the existing `validation_failed` path (§4.3.6; §6.7.2). Satisfies FR-017, FR-018 / SC-010. `[P]` vs the other H2 test files (different file).

**Checkpoint**: All three H2 test files exist and every named case fails (red). No implementation has landed yet.

---

## Phase 2: Implementation

**Purpose**: The implementation units named in `plan.md` → Files (source rows). `validate/phases.ts` and `validate/index.ts` are one logical dual-shape change (plan Sequencing step 4). Consumed modules (`preflight.ts`, `registry.ts`, `context-request.ts`, `errors.ts`, `manifest/index.ts`, `contracts/canonical.ts`) are imported, not modified. Tests turn green in matching groups per plan Sequencing.

- [X] T015 [US1] Extend `ai-platform/src/context/validator.ts` — conversational transcript shape/order (whole-transcript accept-or-reject → `context_invalid`), shape-before-budgets, history-turn and context-round budgets → `conversation_budget_exhausted`, permitted-key allowlist drop (including keys inside `context_resolved`), trimmed gaps legal; extend `ValidateResult` with the budget failure branch; leave `single_shot` required/optional path unchanged; oversized path remains callers invoking existing `runCostPreflight` with transcript included in serialized input (no new cost mechanism, no store). **Satisfies**: FR-001–FR-013, FR-019. **Proved by**: T001–T011.
- [X] T016 [P] [US1] Extend `ai-platform/src/prompt/composer.ts` — accept a validated transcript; render prior turns with closed role tags (`user` / `assistant` / `data`); offer H1's context-request schema as a second permitted output shape alongside prose; keep delimited typed opacity so instruction-like user text and clinical free text cannot act as instructions (R-10); leave registry pin checks and `single_shot` composition unchanged. **Satisfies**: FR-014, FR-015, FR-016, FR-018. **Proved by**: T012–T013. `[P]` vs T015 (different file) once Phase 1 is red.
- [X] T017 [P] [US1] Extend dual-shape acceptance in `ai-platform/src/validate/phases.ts` and `ai-platform/src/validate/index.ts` — for conversational legs accept validated prose **or** platform-owned context-request schema via H1 `validateContextRequest` (keys from the manifest permitted set); output that is neither fails via existing `validation_failed`; do not reorder phases, unbound repair, or rewrite structured / `structured_atomic` emission. **Satisfies**: FR-017, FR-018. **Proved by**: T014. `[P]` vs T015–T016 (different files) once Phase 1 is red.

**Checkpoint**: `npx vitest run test/transcript-validation.test.ts test/conversational-composer.test.ts test/conversational-response-validator.test.ts` green.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside this slice's suite, not just the latest.

- [X] T018 [US1] From `ai-platform/`, run this slice's three test files — `npx vitest run test/transcript-validation.test.ts test/conversational-composer.test.ts test/conversational-response-validator.test.ts` — then run every prior suite: `npx vitest run` (default Node-pool) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm H2's named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (transcript shape/order/budgets/allowlist, composer prior-turn rendering + R-10, dual output-shape acceptance, §3.10 coverage prohibitions). Proved by itself.

**Checkpoint**: Full platform suite green. No regressions into C2/D1/D6/H1 or later bands.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that is not yet complete on disk (`quickstart.md`); written only after the suite is green. The three contracts were already frozen during the plan phase — no separate contract tasks. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T019 [US1] Complete `specs/045-transcript-validation-budgets/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.8 row H2; `01-ai-platform.md` §4.3.5, §6.7.1, §6.7.3, §4.3.6, §6.7.2; what the spec delivered; what the plan scoped. **§2 What was implemented** — conversational transcript validation/budgets/allowlist in `src/context/validator.ts`; prior-turn rendering + second output-shape offer in `src/prompt/composer.ts`; dual-shape acceptance in `src/validate/`; frozen `contracts/*.md`. **§3 Files to review** — only this slice's source, test, and contract files (no prior-slice files). **§4 Prerequisites** — omit (`cd ai-platform && npm install` first time only). **§5 Run the automated suite** — `npx vitest run test/transcript-validation.test.ts test/conversational-composer.test.ts test/conversational-response-validator.test.ts`; slice-only (no full-suite `npm test`). **§6 Inspect the changes** — read the three frozen contracts; open the three source surfaces; run the focused test files. **No §7** — CI is the only verification path (plan: Manual validation omitted). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T014)**: No Setup phase. Written to fail before the code exists. Within each file, tasks are sequential (append order). Cross-file first tasks (T001, T012, T014) are `[P]` relative to each other.
- **Implementation (T015–T017)**: Depends on Tests phase existing (red). T016 and T017 are `[P]` relative to T015 and to each other (different files). Matching green groups: T015 ↔ T001–T011; T016 ↔ T012–T013; T017 ↔ T014.
- **Verification (T018)**: Depends on Implementation green; runs this slice plus every prior slice per §3.10.
- **Documentation (T019)**: Depends on Verification green; records a green suite.

### Within the Slice

- Tests are written and confirmed failing before any implementation.
- Plan Sequencing (validator → composer → dual-shape validate) is reflected in test-file order and in which implementation unit turns which cases green.
- The quickstart is written last and cites only this slice's files and commands.
- Contracts are already on disk from the plan phase — Documentation does not re-author them.

### Parallel Opportunities

- Phase 1: T012 (`conversational-composer.test.ts`) and T014 (`conversational-response-validator.test.ts`) are `[P]` relative to T001–T011 (`transcript-validation.test.ts`) and to each other — different files. Within each file, append tasks are sequential.
- Phase 2: T016–T017 may run in parallel with each other and with T015 once Phase 1 is red (three different source surfaces; dual-shape is one task across two validate files).
- Phase 4: single task — no `[P]`.

---

## Parallel Example: User Story 1

```bash
# Launch the three H2 test-file substrates together:
Task: "valid_transcript_passes in ai-platform/test/transcript-validation.test.ts"
Task: "transcript_renders_as_delimited_typed_prior_turns + role_tags in ai-platform/test/conversational-composer.test.ts"
Task: "prose/context_request/neither in ai-platform/test/conversational-response-validator.test.ts"

# Launch the three implementation units together (after tests are red):
Task: "Extend ai-platform/src/context/validator.ts"
Task: "Extend ai-platform/src/prompt/composer.ts"
Task: "Extend dual-shape acceptance in ai-platform/src/validate/phases.ts + index.ts"
```

---

## Notes

- Tests are mandatory (delivery plan §3.10 overrides the template's "Tests are OPTIONAL" note).
- One slice, one story (US1) — the template's multi-story, Foundational, and Polish phases are deleted, not left empty.
- Every named Test plan / §3.10 case appears in some task's acceptance criteria; combining related same-file cases does not drop coverage.
- Every task traces to an `FR-###` from `spec.md` and to named test(s) from its Test plan (or the Documentation/Verification mandate); nothing is added that the spec/plan do not name.
- No new runtime dependency; validation and composition use hand-rolled TS narrowing matching C2/D1/D6 (R-20).
- Consumed modules (`preflight.ts`, `registry.ts`, `context-request.ts`, `errors.ts`, `manifest/index.ts`) are not rewritten (delivery plan §2.3).
- H2 emits no new taxonomy codes — `context_invalid`, `conversation_budget_exhausted`, and `request_too_large` already exist in A2; dual-shape failure uses D6's `validation_failed`.
