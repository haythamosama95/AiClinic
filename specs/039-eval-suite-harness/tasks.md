# Tasks: Eval suite harness and first capability eval (F1)

**Input**: Design documents from `specs/039-eval-suite-harness/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — F1 defines no entities (spec Key Entities: not applicable). `contracts/capability-eval-harness.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T8) is covered by its own task, written to fail before the harness exists. Spy case T5 is a separate task from outcome cases. Layer is **CI** / scheduled CI (§13.5 Capability evals (A9); delivery plan §3.11.6 row F1). Permanent suite = Vitest under `ai-platform/test/eval/` plus CI golden gate and scheduled live-smoke workflow.

**Organization**: One user story (US1, P1) — F1 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; plan Files are created by Tests/Implementation. No Foundational or Polish phase.

**Task count**: 19 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by F1*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by F1*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/039-eval-suite-harness/`
- **CI / scheduled**: `.github/workflows/ci.yml`, `.github/workflows/ai-platform-eval-live-smoke.yml`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). F1 adds no `ai-platform/src/` module (Clarification Q1 — harness under `test/eval/` only) and no `ai-platform/migrations/` edits. Consumed D1 prompt artifacts and D5 DeepSeek fixtures/adapters are imported unchanged.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.6 row F1; §13.5 Capability evals (A9)). T1, T2, T3, T5, T6 live in `ai-platform/test/eval/golden.test.ts`; T4 lives in `ai-platform/test/eval/live-smoke.test.ts`; T7, T8 live in `ai-platform/test/eval/prohibitions.test.ts`. Default Node-pool Vitest (`vitest.config.ts`, `include: ["test/**/*.test.ts"]`). Until harness helpers, case assets, and workflows exist, imports/assertions fail — the intended red state. Order follows plan Sequencing within the golden file (current-prompt cluster → regressed prompt), with live-smoke and prohibitions on separate files marked `[P]`.

- [ ] T001 [US1] Add named test `golden_set_passes_on_current_prompt` (T1) to `ai-platform/test/eval/golden.test.ts`: create the substrate — imports of harness/scorer helpers from `./harness` (and score-report types as needed); resolve the first capability `clinic.visit_summary` against the current pinned production prompt (Consumes D1). Then the case: run the golden set against recorded provider fixtures and assert it passes (output quality and schema conformance; Clarification Q5; pass/fail only). Fails red until harness + cases/expectations/fixtures exist. **Satisfies**: FR-001, FR-002, FR-004, FR-005 / SC-001. **Proves**: T1.
- [ ] T002 [US1] Add named test `deliberately_regressed_prompt_fails` (T2) to `ai-platform/test/eval/golden.test.ts`: run the same golden set against the checked-in deliberately-worse prompt artifact under `ai-platform/test/eval/prompts/clinic.visit_summary.worse/` (Clarification Q4) and assert the golden set fails so the change is blocked. Not a soft-fail/warn mode. Fails red until the worse prompt artifact and harness support for alternate builds exist. **Satisfies**: FR-006 / SC-002. **Proves**: T2.
- [ ] T003 [US1] Add named test `scores_recorded_per_run` (T3) to `ai-platform/test/eval/golden.test.ts`: after a golden run, assert a JSON score report is written under `ai-platform/test/eval/reports/` with per-case output-quality and schema-conformance scores (Clarification Q2; no numeric cutoff). Fails red until `score-report.ts` / harness write path exists. **Satisfies**: FR-007 / SC-003. **Proves**: T3.
- [ ] T004 [P] [US1] Add named test `scheduled_live_smoke_against_pinned_models` (T4) to `ai-platform/test/eval/live-smoke.test.ts`: create the live-smoke substrate and assert the smoke set targets pinned `model_id` values from `ai-platform/control/routing-policy/platform-default/1.json` (never floating aliases; Clarification Q3; FR-008). Workflow schedule is proven by `.github/workflows/ai-platform-eval-live-smoke.yml` (Implementation). Fails red until smoke entry + pinned-model assertion exist. **Satisfies**: FR-003, FR-008 / SC-004. **Proves**: T4. `[P]` vs T001–T003/T005–T006 — different test file.
- [ ] T005 [US1] Add named test `golden_cases_use_recorded_fixtures` (T5) to `ai-platform/test/eval/golden.test.ts` (spy): assert golden execution binds to recorded provider fixtures (capability-scoped under `test/eval/clinic.visit_summary/fixtures/` / Consumes D5) and does not use live provider egress as the permanent regression gate. Fails red until fixture bindings and harness fixture path exist. **Satisfies**: FR-009 / SC-005. **Proves**: T5.
- [ ] T006 [US1] Add named test `evals_are_per_capability` (T6) to `ai-platform/test/eval/golden.test.ts`: assert the harness scopes golden cases to the first capability (`clinic.visit_summary`) and does not require a cross-capability aggregate gate (A9; §13.5). Fails red until per-capability case layout exists. **Satisfies**: FR-002, FR-010 / SC-006. **Proves**: T6.
- [ ] T007 [P] [US1] Add named test `no_prompt_text_in_flutter_client` (T7) to `ai-platform/test/eval/prohibitions.test.ts`: create the prohibitions substrate and assert this slice introduces no Flutter client files carrying prompt text, provider name, or model identifier (delivery plan §6.4 / R-12). Fails red until the assertion is wired. **Satisfies**: inherited §6.4 / R-12 / SC-006. **Proves**: T7. `[P]` vs golden/live-smoke files — different test file.
- [ ] T008 [US1] Add named test `harness_holds_no_per_request_server_state` (T8) to `ai-platform/test/eval/prohibitions.test.ts`: assert running evals introduces no per-request server-side state of any kind (§4.4, §9.7; delivery plan §6.4) — harness remains CI/scheduled tooling under `test/eval/` with no `src/eval/` module and no request-path store. Fails red until the assertion is wired. **Satisfies**: inherited §4.4 / §9.7 / SC-006. **Proves**: T8.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Vitest entries: harness/scorer helpers, JSON score-report writer, first-capability cases/fixtures/expectations, deliberately-worse prompt artifact, reports output directory, CI golden gate, and scheduled live-smoke workflow. Consumed D1/D5 modules are imported, not modified (delivery plan §2.3). Contracts are already frozen. Tests turn green in matching groups per plan Sequencing: harness + assets unlock T1/T3/T5/T6; worse prompt unlocks T2; live-smoke workflow unlocks T4's schedule half; CI wiring permanently gates goldens; prohibitions stay structural.

- [ ] T009 [P] [US1] Create `ai-platform/test/eval/score-report.ts` — JSON score-report writer/shape under `test/eval/` (quality + schema scores per case; Clarification Q2; no new D1 table; pass/fail only — no numeric cutoff). **Satisfies**: FR-007. **Proved by**: T3 (`scores_recorded_per_run`).
- [ ] T010 [P] [US1] Create first-capability golden cases under `ai-platform/test/eval/clinic.visit_summary/cases/**` — per-case inputs for `clinic.visit_summary` (Clarification Q5; FR-002). **Satisfies**: FR-002, FR-004, FR-005. **Proved by**: T1, T6.
- [ ] T011 [P] [US1] Create capability-scoped recorded provider fixture bindings under `ai-platform/test/eval/clinic.visit_summary/fixtures/**` — bind goldens to D5 recorded fixtures behind the D2 port without redefining the adapter (Consumes D5; FR-009). **Satisfies**: FR-002, FR-009. **Proved by**: T1, T5.
- [ ] T012 [P] [US1] Create structured quality checks / expected-output fixtures under `ai-platform/test/eval/clinic.visit_summary/expectations/**` — quality + schema validation expectations (Clarification Q5; FR-004). **Satisfies**: FR-004. **Proved by**: T1, T3.
- [ ] T013 [P] [US1] Create `ai-platform/test/eval/reports/` — score-report output directory under `test/eval/` (gitignore runtime outputs as needed; shape frozen by contract / `score-report.ts`). **Satisfies**: FR-007. **Proved by**: T3.
- [ ] T014 [US1] Create `ai-platform/test/eval/harness.ts` — runner/scorer helpers: load per-capability cases, invoke fixture-backed path (Consumes D1 composer/artifacts + D5 fixtures), score quality + schema, write JSON report via `score-report.ts`; support current pinned prompt vs worse-prompt build selection (Clarifications Q1, Q4, Q5). No `src/eval/` module; no §5.4 taxonomy codes; no redefinition of D1/D5 contracts (FR-010). **Satisfies**: FR-001, FR-002, FR-004, FR-005, FR-006, FR-009, FR-010. **Proved by**: T1, T2, T3, T5, T6.
- [ ] T015 [P] [US1] Create deliberately-worse prompt artifact under `ai-platform/test/eval/prompts/clinic.visit_summary.worse/**` — checked-in build separate from production pinned prompts (Clarification Q4; FR-006). **Satisfies**: FR-006. **Proved by**: T2. `[P]` vs T014 — different path once harness API for alternate builds is stubbed.
- [ ] T016 [P] [US1] Create `.github/workflows/ai-platform-eval-live-smoke.yml` — scheduled GitHub Actions workflow invoking the live-smoke Vitest entry against pinned models (Clarification Q3; FR-003, FR-008). **Satisfies**: FR-003, FR-008. **Proved by**: T4.
- [ ] T017 [US1] Modify `.github/workflows/ci.yml` — add ai-platform golden-eval Vitest job/step so the golden set permanently gates CI (FR-001, FR-005, FR-006; delivery plan §3.10). Runs `golden.test.ts` (and prohibitions as part of the permanent eval suite entry as implemented). **Satisfies**: FR-001, FR-005, FR-006. **Proved by**: T1, T2 (permanent CI home for the regression gate).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T018 [US1] From `ai-platform/`, run this slice's suite — `npx vitest run test/eval/golden.test.ts test/eval/live-smoke.test.ts test/eval/prohibitions.test.ts` (live-smoke may skip live egress when credentials are absent, but must still assert pinned-model targeting). Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm F1's eight named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. F1 emits no §5.4 taxonomy codes. **Satisfies**: the §3.10 checkpoint rule (T1–T8 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T019 [US1] Create `specs/039-eval-suite-harness/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.7 row F1; `17-ai-platform.md` §13.5 Capability evals (A9) / A9; what the spec delivered; what the plan scoped. **§2 What was implemented** — `test/eval/` harness; first-capability golden cases; deliberately-worse prompt; JSON score report; CI golden gate; scheduled live-smoke workflow; frozen `contracts/capability-eval-harness.md`. **§3 Files to review** — only this slice's `ai-platform/test/eval/` files, workflow deltas, and frozen contract (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`cd ai-platform && npm install` first time); note live-smoke credentials only if documenting manual smoke inspection. **§5 Run the automated suite** — slice-only `npx vitest run test/eval/golden.test.ts test/eval/live-smoke.test.ts test/eval/prohibitions.test.ts` (no full-suite `npm test`, no combined prior-slice counts). **§6 Inspect the changes** — open harness, golden expectations, score-report path, frozen contract, CI and scheduled workflow entries. **§7 Manual validation** — omit for goldens (CI is the verification path); optional note on inspecting a scheduled workflow run / retained score artifact when live credentials are available, without expanding scope. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T008)** — none beyond already-frozen contracts and Consumes Binding modules (D1, D5); written to fail before the code exists. T001–T003/T005–T006 append to `golden.test.ts` (T001 creates the substrate) — sequential within that file. T004 (`live-smoke.test.ts`) and T007 (`prohibitions.test.ts` substrate + T7) are `[P]` relative to the golden file. T008 appends to `prohibitions.test.ts` after T007.
- **Implementation (T009–T017)** — after tests exist. T009–T013 and T015–T016 are `[P]`-eligible relative to each other (different paths). T014 (`harness.ts`) depends on T009 (score-report) and should land with T010–T013 assets. T017 (`ci.yml`) depends on golden Vitest entry existing. Tests turn green in matching groups per plan Sequencing.
- **Verification (T018)** — depends on T001–T017; runs this slice plus every prior slice per §3.10.
- **Documentation (T019)** — depends on T018 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing: harness + score-report + cases/expectations/fixtures (T009–T014) unlock T1/T3/T5/T6 → worse prompt (T015) unlocks T2 → live-smoke workflow (T016) completes T4's schedule half → prohibitions stay with T7/T8 → CI wiring (T017) → quickstart (T019).
- No `src/` module and no Consumes rewrites (FR-010).

### Parallel Opportunities

- Phase 1: T004 (`live-smoke.test.ts`) and T007 (`prohibitions.test.ts`) are `[P]` relative to `golden.test.ts` tasks — different files. Golden-file tasks (T001–T003, T005–T006) are sequential. T008 follows T007 on the same prohibitions file.
- Phase 2: T009 (`score-report.ts`), T010–T013 (cases/fixtures/expectations/reports), T015 (worse prompt), and T016 (scheduled workflow) are `[P]` relative to each other — different paths. T014 (`harness.ts`) follows T009. T017 (`ci.yml`) follows the golden entry.
- Phase 4 (T019) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T004, T007 (test files); T009–T013, T015–T016 (implementation assets/workflows).
- Every named test T1–T8 from `spec.md` is covered by its own task; spy case T5 is not folded into an outcome case.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name. Clarifications Q1–Q5 guide how (harness under `test/eval/` only; JSON score report; scheduled GHA smoke; checked-in worse prompt; per-case quality expectations), not what.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (D1, D5).
- Vitest entry Files-section rows (`golden.test.ts`, `live-smoke.test.ts`, `prohibitions.test.ts`) are produced by Phase 1 test tasks; they are not repeated as Implementation tasks. Remaining Files units are T009–T017 plus T019 (`quickstart.md`). `contracts/capability-eval-harness.md` is already frozen — no task recreates it.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no Flutter prompt/provider/model strings; no per-request server-side state; no §9.14 mechanism; no second Quota DO / R2 object; no runtime §5.4 codes from this harness.
