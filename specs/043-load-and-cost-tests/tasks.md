# Tasks: Load and cost tests (F5)

**Input**: Design documents from `specs/043-load-and-cost-tests/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — F5 defines no entities (spec Key Entities: not applicable). `contracts/load-and-cost-tests.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T9) is covered by its own task, written to fail before the load helpers and workers-pool wiring exist. Spy cases T2, T3, T6, and T7 are each a separate task from outcome/measurement cases. Layer is **Load** (§13.5 Load and cost tests; delivery plan §3.11.6 row F5). Permanent suite = Vitest workers-pool under `ai-platform/test/load/` plus the dedicated `test:load` checkpoint gate.

**Organization**: One user story (US1, P1) — F5 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; plan Files are created by Tests/Implementation. No Foundational or Polish phase.

**Task count**: 17 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by F5*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by F5*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/043-load-and-cost-tests/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). F5 adds no `ai-platform/src/` module and no `ai-platform/migrations/` edits — suite lives under `ai-platform/test/load/` only. Consumed D7 adapter/fixtures/policy data and exercised B4/C3/D2 modules are imported unchanged.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.6 row F5; §13.5 Load and cost tests). All nine named cases live in `ai-platform/test/load/load-and-cost.test.ts` on the workers-pool Miniflare config (`vitest.workers.config.ts`). Until binding spies, measurement report, happy-path driver, and workers-pool include/`test:load` wiring exist, imports/assertions fail — the intended red state. Order follows plan Sequencing: T1–T5 (p95 / one-R2 / two-DO / measurements) then T6–T9 (inherited prohibitions). Same file → not `[P]` between cases; T001 creates the substrate.

- [ ] T001 [US1] Add named test `guard_p95_within_tens_of_ms_at_target_concurrency` (T1) to `ai-platform/test/load/load-and-cost.test.ts`: create the substrate — imports of binding spies, measurement report, and happy-path driver from `./binding-spies`, `./measurement-report`, `./happy-path` as needed; workers-pool env with real D1/R2/QUOTA_DO. Then the case: drive the full happy path under concurrency fixture `N=20` and assert guard p95 (stages that constitute the guard / §6.1 stages 1–10) is `< 100` ms (Clarification Q3 — suite encoding of "target concurrency" / "tens of milliseconds"). Fails red until happy-path driver + timing harness exist. **Satisfies**: FR-001, FR-003 / SC-001. **Proves**: T1.
- [ ] T002 [US1] Add named test `exactly_one_r2_class_a_per_request_under_load` (T2) to `ai-platform/test/load/load-and-cost.test.ts` (spy): under load, count R2 Class A operations (`PutObject` / equivalent) via binding spies and assert exactly one per request (one payload envelope). Fails red until `binding-spies.ts` and happy-path R2 path exist. **Satisfies**: FR-004, FR-008 / SC-002. **Proves**: T2.
- [ ] T003 [US1] Add named test `exactly_two_durable_object_requests_per_request_under_load` (T3) to `ai-platform/test/load/load-and-cost.test.ts` (spy): under load, count Quota DO fetches via binding spies and assert exactly two per request (admission in the guard + credit at settle). Fails red until DO spies and happy-path admission/credit path exist. **Satisfies**: FR-005, FR-008 / SC-003. **Proves**: T3.
- [ ] T004 [US1] Add named test `d1_write_headroom_measured` (T4) to `ai-platform/test/load/load-and-cost.test.ts`: under load, assert the structured in-test measurement report carries a finite `d1_hot_path_writes_per_request` (one row per request on the hot path, detail afterwards) with **no** invented numeric ceiling (Clarification Q4). Fails red until `measurement-report.ts` and D1 spy metering exist. **Satisfies**: FR-006, FR-009 / SC-004. **Proves**: T4.
- [ ] T005 [US1] Add named test `do_throughput_per_installation_measured` (T5) to `ai-platform/test/load/load-and-cost.test.ts`: under load, assert the structured measurement report carries a finite `do_throughput_per_installation` with **no** invented numeric ceiling (Clarification Q4). Fails red until measurement-report shape and DO metering exist. **Satisfies**: FR-007, FR-009 / SC-005. **Proves**: T5.
- [ ] T006 [US1] Add named test `no_second_r2_object_per_request` (T6) to `ai-platform/test/load/load-and-cost.test.ts` (spy / inherited prohibition): under load, assert there is no second R2 object per request (reinforces T2; delivery plan §6.4 / §7.5, §13.6). Fails red until R2 Class A spy can prove absence of a second object. **Satisfies**: FR-004, FR-008; inherited §6.4 / SC-002. **Proves**: T6.
- [ ] T007 [US1] Add named test `no_second_quota_do_round_trip_beyond_two` (T7) to `ai-platform/test/load/load-and-cost.test.ts` (spy / inherited prohibition): under load, assert no additional Quota DO round trip beyond the two named in §13.6 (reinforces T3; delivery plan §6.4 / §7.5). Fails red until DO spy can prove absence of a third trip. **Satisfies**: FR-005, FR-008; inherited §6.4 / SC-003. **Proves**: T7.
- [ ] T008 [US1] Add named test `load_suite_introduces_no_per_request_server_state` (T8) to `ai-platform/test/load/load-and-cost.test.ts` (inherited prohibition): assert running the load/cost suite introduces no per-request server-side state of any kind (§4.4, §9.7; delivery plan §6.4) — suite remains workers-pool tooling under `test/load/` with no `src/load/` module and no request-path store. Fails red until the structural assertion is wired. **Satisfies**: inherited §4.4 / §9.7 / SC-007. **Proves**: T8.
- [ ] T009 [US1] Add named test `no_prompt_provider_model_in_flutter_from_load_suite` (T9) to `ai-platform/test/load/load-and-cost.test.ts` (inherited prohibition): assert this slice introduces no Flutter client files carrying prompt text, provider name, or model identifier (delivery plan §6.4 / R-12). Fails red until the assertion is wired. **Satisfies**: inherited §6.4 / R-12 / SC-007. **Proves**: T9.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as the Vitest entry: binding spies, structured measurement report, fake-provider happy-path driver under load, Node-pool exclude, workers-pool include, and `test:load` checkpoint script. Consumed D7 modules and exercised B4/C3/D2 modules are imported, not modified (delivery plan §2.3; FR-010). Contracts are already frozen. Tests turn green in matching groups per plan Sequencing: spies + report + happy path unlock T1–T7; prohibitions T8–T9 stay structural; workers-pool wiring + `test:load` complete FR-002 / CP5 gate.

- [ ] T010 [P] [US1] Create `ai-platform/test/load/binding-spies.ts` — counting spies wrapping D1 / R2 / Quota DO bindings under workers-pool Miniflare (Clarification Q1): R2 Class A (`PutObject` / equivalent), DO fetch (admission + credit), and D1 hot-path writes. No new package; no rewrite of B4/C3 bindings. **Satisfies**: FR-004, FR-005, FR-006, FR-008. **Proved by**: T2, T3, T4, T6, T7.
- [ ] T011 [P] [US1] Create `ai-platform/test/load/measurement-report.ts` — structured in-test measurement report shape with finite values for guard p95, `d1_hot_path_writes_per_request`, and `do_throughput_per_installation`; **no** numeric ceilings for D1 headroom or DO throughput (Clarification Q4; FR-006, FR-007, FR-009). **Satisfies**: FR-001, FR-006, FR-007, FR-009. **Proved by**: T1, T4, T5.
- [ ] T012 [US1] Create `ai-platform/test/load/happy-path.ts` — drive the full happy path under load with D2 `FakeAdapter`: admission + credit + one R2 envelope on real Miniflare D1/R2/QUOTA_DO bindings (Clarification Q2); concurrency fixture `N=20` (Clarification Q3). Does not invent a second provider or live egress; does not rewrite D7 adapter/fixtures/policy (FR-010). **Satisfies**: FR-001, FR-003, FR-008, FR-010. **Proved by**: T1–T7. Depends on T010 (spies) and should land with T011 (report) available for measurement attachment.
- [ ] T013 [P] [US1] Modify `ai-platform/package.json` — add `"test:load"` workers-pool script as the delivery-checkpoint gate invoking the load suite (Clarification Q4; FR-002, FR-009; §13.5 How). **Satisfies**: FR-002, FR-009. **Proved by**: T1–T9 via the checkpoint gate (suite invocation home).
- [ ] T014 [P] [US1] Modify `ai-platform/vitest.workers.config.ts` — include `test/load/load-and-cost.test.ts` so the Load layer joins the workers-pool suite permanently (delivery plan §3.10; FR-001, FR-002). **Satisfies**: FR-001, FR-002. **Proved by**: T1–T9 (permanent workers-pool home).
- [ ] T015 [P] [US1] Modify `ai-platform/vitest.config.ts` — exclude `test/load/**` from the Node-pool include so load tests run only where real D1/R2/DO bindings exist (Clarification Q1; FR-001). **Satisfies**: FR-001. **Proved by**: T1–T9 (workers-pool-only placement).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T016 [US1] From `ai-platform/`, run this slice's load suite — `npm run test:load` (or `npx vitest run --config vitest.workers.config.ts test/load/load-and-cost.test.ts`). Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, now including F5). Confirm F5's nine named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Completing the measured/asserted outcomes is what satisfies CP5 (FR-009 / SC-006). F5 emits no §5.4 taxonomy codes. **Satisfies**: the §3.10 checkpoint rule (T1–T9 + prior suites); FR-009 / SC-006. Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T017 [US1] Create `specs/043-load-and-cost-tests/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.7 row F5; `17-ai-platform.md` §13.5 Load and cost tests / §13.6 / §13.6.1; what the spec delivered; what the plan scoped. **§2 What was implemented** — workers-pool load suite; binding spies; fake-provider happy path under concurrency; structured measurement report; `test:load` checkpoint gate; frozen `contracts/load-and-cost-tests.md`. **§3 Files to review** — only this slice's `ai-platform/test/load/` files, `package.json` / vitest config deltas, and frozen contract (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`cd ai-platform && npm install` first time). **§5 Run the automated suite** — slice-only `npm run test:load` / `npx vitest run --config vitest.workers.config.ts test/load/load-and-cost.test.ts` (no full-suite `npm test`, no combined prior-slice counts). **§6 Inspect the changes** — open the load entry, measurement-report shape, binding spies, happy-path driver, and frozen contract. **No §7 Manual validation** — CI / `test:load` is the only verification path (F5 exposes no behaviour beyond the automated suite). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T009)** — none beyond already-frozen contracts and Consumes Binding / exercised modules (D7 present; B4/C3/D2 imported unchanged); written to fail before the code exists. All append to `load-and-cost.test.ts` (T001 creates the substrate) — sequential within that file.
- **Implementation (T010–T015)** — after tests exist. T010 (`binding-spies.ts`) and T011 (`measurement-report.ts`) are `[P]` relative to each other. T012 (`happy-path.ts`) depends on T010 and should land with T011. T013–T015 (`package.json`, `vitest.workers.config.ts`, `vitest.config.ts`) are `[P]` relative to each other and may land after the Vitest entry exists. Tests turn green in matching groups per plan Sequencing.
- **Verification (T016)** — depends on T001–T015; runs this slice plus every prior slice per §3.10.
- **Documentation (T017)** — depends on T016 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing: binding spies + measurement report (T010–T011) → happy-path driver (T012) unlocks T1–T7 → prohibitions T8–T9 stay structural → workers-pool wiring + `test:load` (T013–T015) → verification (T016) → quickstart (T017).
- No `src/` module and no Consumes rewrites (FR-010).

### Parallel Opportunities

- Phase 1: no `[P]` — all nine named tests share `load-and-cost.test.ts` (T001 creates the substrate; T002–T009 append sequentially).
- Phase 2: T010 and T011 are `[P]` — different helper files. T013, T014, and T015 are `[P]` relative to each other — different config/package paths. T012 follows T010.
- Phase 4 (T017) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T010–T011 (helpers); T013–T015 (package/config wiring).
- Every named test T1–T9 from `spec.md` is covered by its own task; spy cases T2, T3, T6, and T7 are not folded into outcome cases.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name. Clarifications Q1–Q4 guide how (workers-pool Miniflare + binding spies; fake-provider happy path; `N=20` / `p95 < 100` ms; structured measurement report + `test:load`), not what.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (D7) plus earlier pipeline slices exercised unchanged (B4, C3, D2).
- Vitest entry Files-section row (`load-and-cost.test.ts`) is produced by Phase 1 test tasks; it is not repeated as an Implementation task. Remaining Files units are T010–T015 plus T017 (`quickstart.md`). `contracts/load-and-cost-tests.md` is already frozen — no task recreates it.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no Flutter prompt/provider/model strings; no per-request server-side state; no §9.14 mechanism; no second Quota DO / R2 object; no runtime §5.4 codes from this suite; D1 headroom and DO throughput measured without invented ceilings.
