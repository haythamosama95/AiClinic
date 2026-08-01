# Tasks: Client architecture guard in CI (E1)

**Input**: Design documents from `specs/035-client-arch-guard-ci/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — E1 defines no entities (spec Key Entities: not applicable). `contracts/` is not produced — Freezes have no wire shape (plan Project Structure → Documentation). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T5) is covered by its own task, written to fail before the guard script exists. Layer is **CI lint** (§13.5 Architecture guard (R-12); delivery plan §3.11.5 row E1). No `flutter test`, no Vitest, no SQL tests (plan Technical Context → Testing). Permanent suite = dedicated `dart` invocations (expect-fail against fixtures; expect-success against clean client scan roots including coverage).

**Organization**: One user story (US1, P1) — E1 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — plan Files are created by Tests/Implementation; no prerequisite tree beyond existing `frontend/` and `.github/workflows/ci.yml`. No Foundational or Polish phase.

**Task count**: 9 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`, `frontend/tool/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by E1*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — *not touched by E1*
- **Spec Kit artifacts**: `specs/035-client-arch-guard-ci/`
- **CI**: `.github/workflows/ci.yml`
- E1 is a client-side architectural CI component under `frontend/tool/architecture_guard/` (Clarification Q1–Q2). Clean scan roots are Flutter application sources under `frontend/` that ship in or build the desktop client (primarily `frontend/lib/`); fixtures live outside those roots under the guard's tool/fixture directory. No `ai-platform/` or `backend/` path is touched.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.5 row E1; §13.5 Architecture guard (R-12)). T1–T3 live as deliberately failing fixtures under `frontend/tool/architecture_guard/fixtures/` (outside clean scan roots — Clarification Q2); the permanent proof is an expect-fail `dart` invocation of `architecture_guard.dart` against each fixture. T4 lives as the expect-success clean-tree invocation against real client scan roots. T5 lives as the coverage assertion inside `architecture_guard.dart` during the clean-tree run (plan Test Layout). Until `architecture_guard.dart` exists and detects the three forbidden categories / asserts full path coverage, every local `dart` invocation and every CI step that depends on it is red — the intended state. Order follows plan Sequencing: fixtures (T1–T3) first, then clean-tree and coverage cases (T4–T5).

- [X] T001 [P] [US1] Add named test `guard_prompt_like_string_fails_build` (T1): create `frontend/tool/architecture_guard/fixtures/prompt_like_string/forbidden.dart` containing a representative prompt-like string (spec Assumptions — concrete string chosen in implementation; not an exhaustive catalogue). Outside clean scan roots (Clarification Q2). The permanent proof is an expect-fail `dart` run of `frontend/tool/architecture_guard/architecture_guard.dart` against this fixture directory — must exit non-zero; CI must fail the job if the script exits zero (plan Test Layout). Fails red until the guard script detects prompt-like strings. **Satisfies**: FR-001, FR-005 / SC-001. **Proves**: T1.
- [X] T002 [P] [US1] Add named test `guard_provider_name_fails_build` (T2): create `frontend/tool/architecture_guard/fixtures/provider_name/forbidden.dart` containing a representative provider name. Outside clean scan roots. Same expect-fail `dart` / CI pattern as T001 for this fixture path. Fails red until the guard script detects provider names. **Satisfies**: FR-002, FR-005 / SC-002. **Proves**: T2.
- [X] T003 [P] [US1] Add named test `guard_model_identifier_fails_build` (T3): create `frontend/tool/architecture_guard/fixtures/model_identifier/forbidden.dart` containing a representative model identifier. Outside clean scan roots. Same expect-fail `dart` / CI pattern as T001 for this fixture path. Fails red until the guard script detects model identifiers. **Satisfies**: FR-003, FR-005 / SC-003. **Proves**: T3.
- [X] T004 [US1] Add named test `guard_clean_tree_passes` (T4): establish the permanent expect-success clean-tree gate — a `dart` invocation of `architecture_guard.dart` against the configured clean client scan roots (e.g. `frontend/lib/`) that must exit zero when none of the three forbidden categories are present (plan Test Layout; Done when). Record the invocation as the clean-tree step that `.github/workflows/ci.yml` will run permanently (step may be stubbed here and completed in T007). Fixtures from T001–T003 must not remain in the clean-tree scan roots (FR-005; Clarification Q2). Fails red until the guard script exists and exits zero on the clean tree. **Satisfies**: FR-005 / SC-004. **Proves**: T4.
- [X] T005 [US1] Add named test `guard_covers_every_client_source_path` (T5): establish the permanent coverage assertion that runs during the clean-tree gate — omitting any client source path from configured scan roots must fail the assertion (non-zero exit) (plan Test Layout; FR-004; Done when "anywhere in client code"). Lives inside `architecture_guard.dart`'s clean-tree mode (assertion path stubbed/required here; implemented in T006). Fails red until the script asserts full client-source coverage. **Satisfies**: FR-004 / SC-005. **Proves**: T5.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as test substrates: the standalone Dart guard script and the dedicated CI workflow step(s). Fixtures (T001–T003) are the Files-section fixture rows and are not repeated here. Tests turn green when the script detects all three forbidden categories (T1–T3), exits zero on the clean tree (T4), and asserts full path coverage (T5); CI joins those invocations permanently (FR-006; delivery plan §3.10).

- [X] T006 [US1] Create `frontend/tool/architecture_guard/architecture_guard.dart` — standalone Dart CI lint script (Clarification Q1). Scans configured client source roots for prompt-like strings, provider names, and model identifiers; exits non-zero on any match; default mode is the clean-tree gate; during the clean-tree run asserts configured scan roots cover every client source path (T5). Representative detection patterns for the three forbidden categories are chosen in implementation (spec Assumptions / Out of Scope — not an exhaustive catalogue). Tool and fixtures remain outside clean scan roots (Clarification Q2). No new pub packages; no `frontend/lib/` application source; no client AI feature code (DP-6); no `ai-platform/` or `backend/` touch. **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-006. **Proved by**: T1–T5 (`guard_prompt_like_string_fails_build`, `guard_provider_name_fails_build`, `guard_model_identifier_fails_build`, `guard_clean_tree_passes`, `guard_covers_every_client_source_path`).
- [X] T007 [US1] Modify `.github/workflows/ci.yml` — add a dedicated architecture-guard CI step (Clarification Q1) on the existing `frontend-quality` job (`windows-latest`) that (1) runs the script against each fixture under `frontend/tool/architecture_guard/fixtures/` expecting non-zero exit (T1–T3), and (2) runs the script against the clean client scan roots expecting zero exit including full path coverage (T4–T5). Joins CI permanently (delivery plan §3.10; FR-006). Failing fixture runs are separate expect-fail invocations; fixtures never remain in the clean-tree gate (FR-005; Clarification Q2). **Satisfies**: FR-005, FR-006. **Proved by**: T1–T5 (permanent CI home for all five named cases).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T008 [US1] Run this slice's permanent CI-lint suite locally from `frontend/` — expect-fail `dart` invocations against `tool/architecture_guard/fixtures/prompt_like_string/`, `tool/architecture_guard/fixtures/provider_name/`, and `tool/architecture_guard/fixtures/model_identifier/` (must exit non-zero), then expect-success `dart` invocation of `tool/architecture_guard/architecture_guard.dart` against the clean client scan roots (must exit zero, including coverage). Then run every prior slice's suite from `ai-platform/`: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm E1's five named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. E1 emits no §5.4 platform error codes. **Satisfies**: the §3.10 checkpoint rule (T1–T5 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T009 [US1] Create `specs/035-client-arch-guard-ci/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.6 row E1; `17-ai-platform.md` §13.5 / §3.4.1 / R-12; what the spec delivered; what the plan scoped. **§2 What was implemented** — standalone Dart guard script; three deliberately failing fixtures; dedicated CI step; clean-tree + coverage gate. **§3 Files to review** — only this slice's `frontend/tool/architecture_guard/` files and the `.github/workflows/ci.yml` delta (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`dart` from SDK declared in `frontend/pubspec.yaml`). **§5 Run the automated suite** — slice-only `dart` invocations against fixtures (expect-fail) and clean roots (expect-success); no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open the script, the fixtures, and the CI step; grep the workflow for the guard step name. **No §7 Manual validation** — CI is the only verification path (E1 exposes no runtime behaviour). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T005)** — none beyond existing `frontend/` and `.github/workflows/ci.yml`. Written to fail before `architecture_guard.dart` exists. T001–T003 are `[P]` (different fixture files). T004–T005 follow fixtures (clean-tree and coverage gates assume fixtures are outside scan roots) and are sequential relative to each other if both touch the CI workflow stub.
- **Implementation (T006–T007)** — after tests exist. T006 (`architecture_guard.dart`) makes T1–T5 turn green under local `dart` invocations. T007 (`.github/workflows/ci.yml`) wires those invocations permanently and depends on T006 (and on T001–T005 substrates/gates).
- **Verification (T008)** — depends on T001–T007; runs this slice's CI-lint suite plus every prior slice's suite per §3.10.
- **Documentation (T009)** — depends on T008 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing: fixtures (T001–T003) → guard script (T006) → CI wiring (T007) → documentation (T009). T004–T005 establish clean-tree and coverage cases alongside fixtures, before or with T006.
- No consumed modules (Consumes: —). No §4 component touched.

### Parallel Opportunities

- Phase 1: T001–T003 are `[P]` — three different fixture files under `frontend/tool/architecture_guard/fixtures/`. T004 and T005 are not `[P]` relative to each other if they share the CI workflow stub or the script's assertion surface.
- Phase 2: T006 and T007 are sequential — CI steps invoke the script produced by T006.
- Phase 4 (T009) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T001–T003 (three fixture paths).
- Every named test T1–T5 from `spec.md` is covered by its own task.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name. Clarifications Q1–Q2 guide how (standalone Dart script; fixtures outside clean scan roots; separate expect-fail vs clean-tree runs), not what.
- No Polish phase and no Foundational phase — E1 has `Needs: —`; no prior frozen contract to consume.
- Fixtures Files-section rows are produced by T001–T003 (test substrates); they are not repeated as Implementation tasks. Remaining Files units are T006 (`architecture_guard.dart`), T007 (`ci.yml`), and T009 (`quickstart.md`).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve R-12: no prompt text, provider name, or model identifier anywhere in the clean Flutter client tree; E1 exists to make that fail the build (§6.4). No warn-and-continue mode. No client AI code (DP-6).
