# Tasks: Staged rollout and canary cohorts (J3)

**Input**: Design documents from `specs/050-staged-rollout-canary/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — J3 defines no new D1 entity (spec Key Entities). `contracts/staged-rollout-canary.md` is already frozen on disk (written during the plan phase per DP-4; `AVAILABLE_DOCS` includes `contracts/`). `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T-J3-01 .. T-J3-05) is covered by its own task, written to fail before control handlers and cohort-aware reads exist. Layer is **Integration** / Pipeline tests (delivery plan §3.11.8 row J3; §13.5 Pipeline tests). Per Clarification Q3, cases split across `ai-platform/test/cohort-activate-promote.test.ts` (prompt / capability-build activate / promote / rollback-by-deploy + journal version) and `ai-platform/test/routing-policy-canary.test.ts` (routing-policy publish / canary / roll back + `control_audit`). Optional shared `ai-platform/test/helpers/control-audit-assert.ts` is produced as Tests-phase substrate with T-J3-04, not repeated in Implementation. Permanent suites join CI via both Vitest harness configs (delivery plan §3.10).

**Organization**: One user story (US1, P1) — J3 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — the workers-pool include / Node-pool exclude pair for both new test files must land before any named test. No Foundational or Polish phase — prerequisites are already-merged Needs (B2, D1, D2, F1) in the plan's Consumes Binding.

**Task count**: 13 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by J3*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by J3*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/050-staged-rollout-canary/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). J3 extends B2 `src/control/`, D2 `src/router/`, and C1 `src/capability/` in place (Clarifications Q1–Q2), adds one optional forward-only additive migration on `routing_policy`, and does not edit consumed frozen contracts (`control-plane.md`, `composer-output.md`, `routing-decision.md`, `capability-eval-harness.md`).

---

## Phase 1: Setup (Test harness)

**Purpose**: Route both new Pipeline test files to the workers pool that provides real Miniflare D1 (+ R2 for policy documents) (plan → Testing / Files). Both config edits must land before any named test is written, so the cases run under the D1-backed config and the default Node pool's `test/**/*.test.ts` glob does not load Miniflare-D1 tests (B2/C1/J1 precedent).

- [X] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/cohort-activate-promote.test.ts"` and `"test/routing-policy-canary.test.ts"` to `include`. Modify `ai-platform/vitest.config.ts` — add both paths to `exclude`, so the workers-pool-only cases do not double-run in the default Node pool (plan → Files). No FR — harness; required by every named test. Prepares the Phase 2 substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.8 row J3; §13.5 Pipeline tests). Clarification Q3: prompt / capability-build cases live in `cohort-activate-promote.test.ts`; routing-policy publish / canary / roll back + primary `control_audit` cases live in `routing-policy-canary.test.ts`. Optional shared `test/helpers/control-audit-assert.ts` is created with T005 (plan Files optional helper; Clarification Q3) and not repeated in Implementation. Additional FR-004 / FR-011 routing canary coverage implied by the plan Test Layout lands in the routing suite file alongside T-J3-04 (same file, not extra named Test plan rows). Until migration, control handlers, and cohort-aware router / capability reads exist, imports/assertions fail — the intended red state.

- [X] T002 [US1] Create `ai-platform/test/cohort-activate-promote.test.ts` with the workers-pool substrate and named test `T-J3-01 cohort_receives_new_build_others_previous`: `beforeAll` applies A5 (+ J1 if present) migrations plus the J3 additive migration to `env.DB`; B2-style fake `OperatorAuth`; imports of capability resolve / discover and control activate surface. Then the case: after cohort activate of a capability / prompt-backed build, cohort installations resolve the new build; non-cohort installations resolve the previous one (FR-001, FR-008, FR-010 / SC-001; §12.4; §13.4 Promotion). Fails red until installation-scoped grants, activate handler, and cohort-aware capability reads exist. **Satisfies**: FR-001, FR-008, FR-010 / SC-001. **Proves**: T-J3-01.
- [X] T003 [US1] Add named test `T-J3-02 promotion_moves_all_cohorts` to `ai-platform/test/cohort-activate-promote.test.ts`: after promote, all installations receive the activated build; no residual canary split (FR-002, FR-007 / SC-002; §12.4; delivery plan §3.11.8 J3). Fails red until promote handler ends the split. **Satisfies**: FR-002, FR-007 / SC-002. **Proves**: T-J3-02.
- [X] T004 [US1] Add named test `T-J3-03 rollback_by_deploy_restores_previous_build` to `ai-platform/test/cohort-activate-promote.test.ts`: rollback **by deploy** of the previous build restores prior serving for affected cohorts; assert no runtime prompt activation pointer module / path exists (FR-003 / SC-003; §12.4; R-20). Staged prompt fixtures assume the F1 golden gate has already passed — no bypass path; do not redefine `ai-platform/test/eval/` (FR-009; F1 Freezes). Fails red until deploy-simulation rollback restores prior grants / build. **Satisfies**: FR-003, FR-009 / SC-003. **Proves**: T-J3-03.
- [X] T005 [P] [US1] Create `ai-platform/test/routing-policy-canary.test.ts` with workers-pool substrate, optional shared helper `ai-platform/test/helpers/control-audit-assert.ts` (Clarification Q3; plan Files), and named test `T-J3-04 every_activation_writes_control_audit_with_operator_identity`: activate / promote / routing-policy canary / roll back each write a `control_audit` row with that operator id (FR-005 / SC-004; §4.5; B2 Freezes). Include FR-004 / FR-011 mutation cases in this file (publish → canary cohort receives new policy version; others keep previous; promote ends split; roll back restores previous; non-operator credentials rejected under B2) so audit asserts have real mutations — same file, not extra Test plan rows. Fails red until routing-policy publish / canary / roll back handlers and audit writes exist. **Satisfies**: FR-004, FR-005, FR-011 / SC-004. **Proves**: T-J3-04.
- [X] T006 [US1] Add named test `T-J3-05 journal_records_serving_version_under_cohort_split` to `ai-platform/test/cohort-activate-promote.test.ts`: under a cohort split, journaled `prompt_artifact_hash` / capability version match the build each cohort received (FR-006 / SC-005; §12.4; D1 Freezes). Routing-suite `policy_version` measurability under canary remains covered in `routing-policy-canary.test.ts` alongside T005's FR-004 cases (plan Test Layout). Fails red until journal continues to record serving versions under split. **Satisfies**: FR-006 / SC-005. **Proves**: T-J3-05.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Vitest entries, harness config, test substrates, or Documentation. Migration + `schema.snap.sql` are one FR-004/FR-008 schema unit (A5/J1 precedent: snapshot reflects post-migration shape). Optional `control-audit-assert.ts` is produced by T005 — not repeated here. `contracts/staged-rollout-canary.md` is already frozen — no task recreates it. Consumed B2/D1/D2/F1 modules are extended or imported, not rewritten (delivery plan §2.3). Order follows plan Sequencing: migration → control handlers → cohort-aware router + capability reads → worker routes.

- [X] T007 [US1] Create `ai-platform/migrations/20260803100000_routing_policy_canary.sql` — forward-only `ALTER TABLE routing_policy ADD` nullable `canary_installation_ids` TEXT (JSON array of installation ids for an in-canary version; `NULL` = not canary-scoped / promoted global active). Update `ai-platform/schema.snap.sql` so the snapshot matches the post-migration `routing_policy` shape (FR-004, FR-008; §13.4 Configuration). No new table / cohort entity. **Satisfies**: FR-004, FR-008. **Proved by**: T-J3-04 (and every routing canary case that seeds/reads the split); cold-isolate reconstructability of the canary split.
- [X] T008 [US1] Modify `ai-platform/src/control/index.ts` — handlers for routing-policy publish / canary / roll back and capability / prompt-backed cohort activate / promote; installation-scoped `capability_grant` writes for named cohorts; R2 policy object write on publish (`control/routing-policy/{policy_id}/{version}.json`); `control_audit` actions with operator identity; `dispatchControlRequest` / `isControlRoute` extensions (FR-001..005, FR-007, FR-010, FR-011; Clarification Q1). Does not redefine enroll / rotate / suspend / resume / delete or the `control_audit` row shape. No runtime prompt activation pointer (FR-003; R-20). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-010, FR-011. **Proved by**: T-J3-01, T-J3-02, T-J3-03, T-J3-04.
- [X] T009 [P] [US1] Modify `ai-platform/src/router/index.ts` — cohort-aware resolution of which `active_routing_policy` document applies to `RouterContext.installationId` under a canary split; `selectCandidateChain` / filtering / selection-reason shape unchanged (FR-001, FR-004, FR-006, FR-011; Clarification Q2; D2 Freezes). No new pipeline stage. **Satisfies**: FR-001, FR-004, FR-006, FR-011. **Proved by**: T-J3-04 (routing canary split) and T-J3-05 (`policy_version` measurability under split).
- [X] T010 [P] [US1] Modify `ai-platform/src/capability/index.ts` — cohort-aware granted build for the installation via installation-scoped `grants` under a split; resolve / discover continue to return the granted active build; no new taxonomy codes (FR-001, FR-002, FR-006, FR-007, FR-010; Clarification Q2). No new pipeline stage. **Satisfies**: FR-001, FR-002, FR-006, FR-007, FR-010. **Proved by**: T-J3-01, T-J3-02, T-J3-05.
- [X] T011 [US1] Modify `ai-platform/src/worker.ts` — dispatch new `/control/...` paths for routing-policy publish / canary / roll back and cohort activate / promote to the control handlers (same `/control` boundary B2 froze; FR-004, FR-005). **Satisfies**: FR-004, FR-005. **Proved by**: T-J3-01, T-J3-04 (mutation path through the Worker control boundary).

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T012 [US1] From `ai-platform/`, run this slice's suite — `npx vitest run --config vitest.workers.config.ts test/cohort-activate-promote.test.ts test/routing-policy-canary.test.ts`. Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm J3's five named cases (T-J3-01 .. T-J3-05) are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. J3 emits no new request-path taxonomy codes; non-operator control rejections remain B2's. Confirm inherited prohibitions hold: no runtime prompt activation pointer; no per-request server-side canary session; no second Quota DO / R2 on the request path (§6.4). **Satisfies**: the §3.10 checkpoint rule (T-J3-01 .. T-J3-05 + prior suites). Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T013 [US1] Create `specs/050-staged-rollout-canary/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.9 row J3; Implements §12.4, §4.5, §13.4; what the spec delivered; what the plan scoped. **§2 What was implemented** — control-plane Routing policy publish / canary / roll back + cohort activate / promote; cohort-aware D2/C1 reads; optional additive `routing_policy.canary_installation_ids`; rollback-by-deploy for prompts; `control_audit` on every activation; frozen `contracts/staged-rollout-canary.md`. **§3 Files to review** — only this slice's migration (if any), `src/control/index.ts` diff, `src/router/index.ts` diff, `src/capability/index.ts` diff, `src/worker.ts` diff, the two pipeline test files, optional audit helper, and the frozen contract (no prior-slice files). **§4 Prerequisites** — Miniflare D1 (+ R2) workers pool (`vitest.workers.config.ts`); one-time `npm install` in `ai-platform/`. **§5 Run the automated suite** — slice-only `npx vitest run --config vitest.workers.config.ts test/cohort-activate-promote.test.ts test/routing-policy-canary.test.ts` (no full-suite `npm test`, no combined prior-slice counts). **§6 Inspect the changes** — grep new `control_audit.action` values / canary handlers; read the frozen contract; confirm no runtime prompt activation pointer and no prompt text in D1. **§7 Manual validation** — omit; CI is the only verification path (plan). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — no dependencies; blocks the Tests phase (workers include / Node exclude must be wired before any test runs in the right pool).
- **Tests (T002–T006)** — depends on Setup; every test is written against control / cohort-aware behaviour that is absent or incomplete, so the files are red until the Implementation phase lands. T002–T004 and T006 append to `cohort-activate-promote.test.ts` (sequential; T002 creates the substrate). T005 creates the routing suite (+ optional audit helper) and is `[P]` with T002 (different files).
- **Implementation (T007–T011)** — after tests exist (red). Order follows plan Sequencing: migration + snapshot (T007) → control handlers (T008) → cohort-aware router (T009) and capability (T010) in parallel → worker routes (T011). Tests turn green in matching groups: T-J3-01/02/05 against grants + capability reads with T008/T010; T-J3-03 with deploy-simulation rollback; T-J3-04 through routing mutations + audit with T007–T009/T011.
- **Verification (T012)** — depends on T001–T011; runs this slice plus every prior slice per §3.10.
- **Documentation (T013)** — depends on T012 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing: migration (T007) → control (T008) → router + capability (T009–T010) → worker (T011) → quickstart (T013).
- Vitest entry Files-section rows (`cohort-activate-promote.test.ts`, `routing-policy-canary.test.ts`) and optional `control-audit-assert.ts` are produced by Phase 2; vitest config pair by Phase 1. Remaining Files units are T007–T011 plus T013 (`quickstart.md`). `contracts/staged-rollout-canary.md` is already frozen — no task recreates it.

### Parallel Opportunities

- Phase 1 (T001) is a single task — no internal parallelism.
- Phase 2: T005 `[P]` with T002 (different test files). T003, T004, T006 append to the same cohort file as T002 — sequential, not `[P]`.
- Phase 3: T009 and T010 are `[P]` with each other after T007–T008 (different files; both depend on migration + control writes). T007 → T008 → T011 are sequential (migration before handlers; worker after control routes).
- Phase 5 (T013) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Within each same-file test append chain there is no `[P]`.
- Every named test T-J3-01 .. T-J3-05 from `spec.md` is covered by its own task; no test is folded into another. Additional FR-004 / FR-011 routing cases live in the T005 file as plan Test Layout “same two files” coverage, not as extra named Test plan rows.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name. Clarifications Q1–Q3 guide how (extend B2 control; cohort-aware D2/C1 reads; separate pipeline suites + optional audit helper), not what.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (B2, D1, D2, F1).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism (including a runtime prompt activation pointer); no prompt text / provider name / model identifier in the Flutter client (R-12 — J3 does not touch Flutter); no second Quota DO / R2 object per request; no per-request server-side canary session; prompts remain deployed artifacts (FR-008).
