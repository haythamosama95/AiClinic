# Tasks: Conversation evals (H4)

**Input**: Design documents from `specs/047-conversation-evals/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced — H4 defines no entities (spec Key Entities: not applicable). `contracts/conversation-evals.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T9) is covered by its own task, written to fail before the conversation harness exists. Layer is **Evals** / Conversation evals (§13.5 Conversation evals (A14); delivery plan §3.11.7 row H4). Permanent suite = Vitest under `ai-platform/test/eval/` plus the existing CI golden-eval gate extended to include conversation cases.

**Organization**: One user story (US1, P1) — H4 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; plan Files are created by Tests/Implementation. No Foundational or Polish phase.

**Task count**: 19 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by H4*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by H4*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/047-conversation-evals/`
- **CI**: `.github/workflows/ci.yml`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). H4 adds no `ai-platform/src/` module and no `ai-platform/migrations/` edits. Conversation cases and scoring are a sibling under the existing `ai-platform/test/eval/` tree (Clarification Q3). Consumed F1 harness/score-report/golden/live-smoke modules and H2 runtime modules are imported unchanged.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.7 row H4; §13.5 Conversation evals). T1–T7 live in `ai-platform/test/eval/conversation.test.ts`; T8–T9 extend `ai-platform/test/eval/prohibitions.test.ts`. Default Node-pool Vitest (`vitest.config.ts`, `include: ["test/**/*.test.ts"]`). Until conversation harness, score-report, fixture capability, cases, and fixtures exist, imports/assertions fail — the intended red state. Order follows plan Sequencing within the conversation file (converge → correct key → outside permitted → per-conversation scoring → multi-leg fixtures → F1 non-redefinition → score recording), with prohibitions on a separate file marked `[P]`.

- [X] T001 [US1] Add named test `scripted_conversation_converges_within_round_budget` (T1) to `ai-platform/test/eval/conversation.test.ts`: create the substrate — imports of conversation harness / score-report helpers; resolve the one fixture conversational capability `clinic.chat_assistant` (Clarification Q2; Consumes H2/H1 declared budget). Then the case: run the scripted multi-leg conversation against recorded fixtures and assert the per-conversation score records convergence within the capability's declared round budget (Done when; §13.5). Fails red until harness + capability + case + fixtures exist. **Satisfies**: FR-001, FR-002, FR-005, FR-007 / SC-001. **Proves**: T1.
- [X] T002 [US1] Add named test `assistant_must_request_correct_key` (T2) to `ai-platform/test/eval/conversation.test.ts`: run the scripted conversation whose correct next step is requesting a specific permitted context key and assert the per-conversation score requires that *correct* key (not merely any permitted key; §13.5; Edge Cases). Fails red until the T2 case asset and harness scoring for right-keys exist. **Satisfies**: FR-003, FR-008 / SC-002. **Proves**: T2.
- [X] T003 [US1] Add named test `cannot_obtain_key_outside_permitted_set` (T3) to `ai-platform/test/eval/conversation.test.ts`: run the scripted conversation that would obtain a key outside the fixture capability's permitted set and assert the per-conversation permitted-set criterion fails if that key is obtained (Consumes H2 allowlist; §13.5). Fails red until the T3 case asset and permitted-set scoring exist. **Satisfies**: FR-004, FR-009 / SC-003. **Proves**: T3.
- [X] T004 [US1] Add named test `scoring_is_per_conversation_not_per_turn` (T4) to `ai-platform/test/eval/conversation.test.ts`: assert the acceptance unit is the whole conversation's three criteria, not turn-level pass/fail aggregation — a conversation that fails a criterion on one leg fails as a conversation (§13.5; §3.11.7 H4). Fails red until per-conversation score-report shape exists. **Satisfies**: FR-006 / SC-004. **Proves**: T4.
- [X] T005 [US1] Add named test `scripted_multi_leg_against_fixtures` (T5) to `ai-platform/test/eval/conversation.test.ts`: assert the active harness loop advances scripted multi-leg conversations against recorded fixtures (append scripted user/context turns per Clarification Q1; A9 fixture discipline via Consumes F1) and does not open an unbounded live conversation matrix. Fails red until harness loop + per-leg fixtures exist. **Satisfies**: FR-002 / SC-005. **Proves**: T5.
- [X] T006 [US1] Add named test `extends_f1_harness_without_redefining_capability_evals` (T6) to `ai-platform/test/eval/conversation.test.ts`: assert conversation evals are a sibling under `test/eval/` invoked by the same CI gate, and that F1 capability golden/smoke entries and `score-report.ts` quality/schema fields remain unchanged (Consumes F1; FR-010; Clarification Q3). Fails red until the sibling module layout and non-redefinition assertions exist. **Satisfies**: FR-010 / SC-005. **Proves**: T6.
- [X] T007 [US1] Add named test `conversation_eval_scores_recorded_per_conversation` (T7) to `ai-platform/test/eval/conversation.test.ts`: after a conversation-eval run, assert a JSON score report records per-conversation scores for the three criteria (right keys, permitted set, round-budget convergence; extends F1 per-run recording without redefining capability quality/schema fields; no numeric cutoff). Fails red until `conversation-score-report.ts` write path exists. **Satisfies**: FR-003, FR-004, FR-005, FR-006 / SC-005. **Proves**: T7.
- [X] T008 [P] [US1] Add named test `no_prompt_text_in_flutter_client` (T8) to `ai-platform/test/eval/prohibitions.test.ts`: extend the existing F1 prohibitions entry to assert this slice's conversation module files introduce no Flutter client files carrying prompt text, provider name, or model identifier (delivery plan §6.4 / R-12). Fails red until the conversation-module coverage assertion is wired. **Satisfies**: inherited §6.4 / R-12 / SC-006. **Proves**: T8. `[P]` vs `conversation.test.ts` — different test file.
- [X] T009 [US1] Add named test `harness_holds_no_per_request_server_state` (T9) to `ai-platform/test/eval/prohibitions.test.ts`: assert running conversation evals introduces no per-request server-side state of any kind (§4.4, §9.7; delivery plan §6.4) — conversation harness remains CI tooling under `test/eval/` with no `src/eval/` module and no request-path store. Fails red until the assertion covers conversation module files. **Satisfies**: inherited §4.4 / §9.7 / SC-006. **Proves**: T9.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Vitest entries: conversation score-report helper, one fixture conversational capability, three scripted cases, per-leg fixtures, active multi-leg harness, and CI golden-eval wiring. Consumed F1 capability-eval and H2 runtime modules are imported, not modified (delivery plan §2.3). Contracts are already frozen. Tests turn green in matching groups per plan Sequencing: score-report unlocks T4/T7; capability + cases + fixtures unlock T1–T3/T5; harness unlocks the multi-leg loop; CI wiring permanently gates conversation cases; prohibitions stay structural.

- [X] T010 [P] [US1] Create `ai-platform/test/eval/conversation-score-report.ts` — per-conversation JSON score-report writer/shape for the three criteria (right keys, permitted set, round-budget convergence; Clarification Q1 score-at-end; Freezes; no new D1 table; pass/fail only — no numeric cutoff; does not redefine F1 `score-report.ts` quality/schema fields). **Satisfies**: FR-003, FR-004, FR-005, FR-006. **Proved by**: T4, T7.
- [X] T011 [P] [US1] Create `ai-platform/test/eval/clinic.chat_assistant/capability.json` — fixture conversational capability declaring round budget and permitted key set via Consumes H2/H1 manifest fields (Clarification Q2; does not invent numeric defaults). **Satisfies**: FR-005, FR-007. **Proved by**: T1, T2, T3.
- [X] T012 [P] [US1] Create `ai-platform/test/eval/clinic.chat_assistant/cases/converges_within_round_budget.json` — scripted multi-leg case that converges within the declared round budget (FR-007; T1). **Satisfies**: FR-007. **Proved by**: T1.
- [X] T013 [P] [US1] Create `ai-platform/test/eval/clinic.chat_assistant/cases/assistant_must_request_correct_key.json` — scripted multi-leg case requiring the *correct* permitted key (FR-008; T2; Edge Cases). **Satisfies**: FR-008. **Proved by**: T2.
- [X] T014 [P] [US1] Create `ai-platform/test/eval/clinic.chat_assistant/cases/cannot_obtain_key_outside_permitted_set.json` — scripted multi-leg case proving a key outside the permitted set cannot be obtained (FR-009; T3; Consumes H2). **Satisfies**: FR-009. **Proved by**: T3.
- [X] T015 [P] [US1] Create per-leg recorded provider/assistant fixtures under `ai-platform/test/eval/clinic.chat_assistant/fixtures/**` — bind the three scripted cases to recorded fixtures under A9/F1 discipline without live unbounded chat (FR-002; Consumes F1). **Satisfies**: FR-002. **Proved by**: T1, T5.
- [X] T016 [US1] Create `ai-platform/test/eval/conversation-harness.ts` — active multi-leg loop: each leg against recorded fixtures, append scripted user/context turns, score the whole conversation at the end via `conversation-score-report.ts` (Clarifications Q1, Q3; sibling of F1 `harness.ts`; no `src/eval/` module; no §5.4 taxonomy codes; does not redefine F1 golden/smoke gating). **Satisfies**: FR-001, FR-002, FR-010. **Proved by**: T1, T2, T3, T5, T6, T7.
- [X] T017 [US1] Modify `.github/workflows/ci.yml` — include `conversation.test.ts` in the existing `ai-platform-eval-golden` job so conversation evals join the same CI gate as F1 goldens (Clarification Q3; FR-001, FR-010; delivery plan §3.10). **Satisfies**: FR-001, FR-010. **Proved by**: T1, T6 (permanent CI home for the conversation regression gate).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T018 [US1] From `ai-platform/`, run this slice's suite — `npx vitest run test/eval/conversation.test.ts test/eval/prohibitions.test.ts`. Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm H4's nine named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. H4 emits no §5.4 taxonomy codes. **Satisfies**: the §3.10 checkpoint rule (T1–T9 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T019 [US1] Create `specs/047-conversation-evals/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.8 row H4; `01-ai-platform.md` §13.5 Conversation evals / A9; what the spec delivered; what the plan scoped. **§2 What was implemented** — sibling conversation harness + scoring; one fixture conversational capability with three scripted multi-leg cases; per-conversation JSON scores; same CI gate as F1; frozen `contracts/conversation-evals.md`. **§3 Files to review** — only this slice's `ai-platform/test/eval/` conversation files, CI delta, and frozen contract (no prior-slice files). **§4 Prerequisites** — omit (`cd ai-platform && npm install` first time only). **§5 Run the automated suite** — slice-only `npx vitest run test/eval/conversation.test.ts test/eval/prohibitions.test.ts` (no full-suite `npm test`, no combined prior-slice counts). **§6 Inspect the changes** — open conversation harness, three cases, score-report shape, frozen contract, CI golden-eval entry. **§7 Manual validation** — omit; CI/`vitest` is the only verification path (plan). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T009)** — none beyond already-frozen contracts and Consumes Binding modules (F1, H2); written to fail before the code exists. T001–T007 append to `conversation.test.ts` (T001 creates the substrate) — sequential within that file. T008 (`prohibitions.test.ts`) is `[P]` relative to the conversation file. T009 appends to `prohibitions.test.ts` after T008.
- **Implementation (T010–T017)** — after tests exist. T010–T015 are `[P]`-eligible relative to each other (different paths). T016 (`conversation-harness.ts`) depends on T010 (score-report) and should land with T011–T015 assets. T017 (`ci.yml`) depends on the conversation Vitest entry existing. Tests turn green in matching groups per plan Sequencing.
- **Verification (T018)** — depends on T001–T017; runs this slice plus every prior slice per §3.10.
- **Documentation (T019)** — depends on T018 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing: score-report (T010) unlocks T4/T7 → capability + three cases + fixtures (T011–T015) unlock T1–T3/T5 → harness (T016) unlocks the multi-leg loop → prohibitions stay with T8/T9 → CI wiring (T017) → quickstart (T019).
- No `src/` module and no Consumes rewrites (FR-010; Consumes H2).

### Parallel Opportunities

- Phase 1: T008 (`prohibitions.test.ts`) is `[P]` relative to `conversation.test.ts` tasks — different file. Conversation-file tasks (T001–T007) are sequential. T009 follows T008 on the same prohibitions file.
- Phase 2: T010 (`conversation-score-report.ts`), T011 (`capability.json`), T012–T014 (three cases), and T015 (fixtures) are `[P]` relative to each other — different paths. T016 (`conversation-harness.ts`) follows T010. T017 (`ci.yml`) follows the conversation Vitest entry.
- Phase 4 (T019) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T008 (test file); T010–T015 (implementation assets).
- Every named test T1–T9 from `spec.md` is covered by its own task; no test is folded into another.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name. Clarifications Q1–Q3 guide how (active multi-leg harness loop; one fixture conversational capability with three cases; sibling module under `test/eval/` on the same CI gate), not what.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (F1, H2).
- Vitest entry Files-section rows (`conversation.test.ts`, `prohibitions.test.ts`) are produced/extended by Phase 1 test tasks; they are not repeated as Implementation tasks. Remaining Files units are T010–T017 plus T019 (`quickstart.md`). `contracts/conversation-evals.md` is already frozen — no task recreates it.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- T018 resolution (Consumes F1): the fixture capability directory required by Clarification Q3 sits as a sibling under `test/eval/`, so F1's `listEvalCapabilities()` directory scan needed a layout discriminator to keep returning only golden-layout capabilities. The one-predicate extension (directory must own `expectations/`, which the golden runner already requires to load expectations) preserves F1 golden/smoke gating byte-for-byte in behaviour — `golden.test.ts` T6 still asserts `[clinic.visit_summary]` — and adds no second gate, so FR-010 holds. Conversation-capability discovery lives in H4's own `conversation-harness.ts`.
- Preserve §6.4: no Flutter prompt/provider/model strings; no per-request server-side state; no §9.14 mechanism; no second Quota DO / R2 object; no runtime §5.4 codes from this harness.
