# Tasks: Capability deprecation and the overlap window (J1)

**Input**: Design documents from `specs/048-capability-deprecation/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — J1 defines no new D1 entity (spec Key Entities). `contracts/capability-deprecation.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T-J1-01 .. T-J1-05) is covered by its own task, written to fail before the overlay / control / resolve behaviour exists. Layer is **Integration** / Pipeline tests (delivery plan §3.11.8 row J1; §13.5 Pipeline tests). Permanent suite = Vitest workers pool under `ai-platform/test/capability-deprecation.test.ts`.

**Organization**: One user story (US1, P1) — J1 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — the workers-pool include / Node-pool exclude pair must land before any named test. No Foundational or Polish phase — prerequisites are already-merged Needs (C1, B2) in the plan's Consumes Binding.

**Task count**: 12 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by J1*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by J1*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/048-capability-deprecation/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). J1 extends C1 `src/capability/` and B2 `src/control/` in place, adds one forward-only additive migration on `capability_grant`, and does not edit consumed frozen contracts (`capability-registry.md`, `control-plane.md`).

---

## Phase 1: Setup (Test harness)

**Purpose**: Route the new test file to the workers pool that provides real Miniflare D1 (plan → Testing / Files). Both config edits must land before any named test is written, so the Pipeline cases run under the D1-backed config and the default Node pool's `test/**/*.test.ts` glob does not load a Miniflare-D1 test (C1/C3/B2/H3 precedent).

- [ ] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/capability-deprecation.test.ts"` to `include`. Modify `ai-platform/vitest.config.ts` — add `"test/capability-deprecation.test.ts"` to `exclude`, so the workers-pool-only cases do not double-run in the default Node pool (plan → Files). No FR — harness; required by every named test. Prepares the Phase 2 substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.8 row J1; §13.5 Pipeline tests). All five live in `ai-platform/test/capability-deprecation.test.ts` under `vitest.workers.config.ts` (real D1 + control mutations + resolve/discover). The first task creates the file and substrate; every later test appends to it. All tasks touch the same file, so none is `[P]` relative to another within this phase. Until the migration, overlay reads, and control handlers exist, imports/assertions fail — the intended red state.

- [ ] T002 [US1] Create `ai-platform/test/capability-deprecation.test.ts` with the workers-pool substrate and named test `T-J1-01 discovery_marks_deprecated_with_successor`: `beforeAll` applies A5 migration plus the J1 additive migration to `env.DB`; C1 registry fixtures; B2-style fake `OperatorAuth`; imports of `resolve` / `discover` / control deprecate-retire surface. Then the case: after `deprecate` with a named successor, `discover()` for an entitled installation includes that version with effective `deprecated` and the successor id (FR-002, FR-003 / SC-001). Fails red until overlay columns, control deprecate, and discovery announcement exist. **Satisfies**: FR-002, FR-003 / SC-001. **Proves**: T-J1-01.
- [ ] T003 [US1] Add named test `T-J1-02 deprecated_serves_inside_overlap_window` to `ai-platform/test/capability-deprecation.test.ts`: pin to a version whose effective lifecycle is `deprecated` and `now < retire_after` (OD-9 window) → `resolve()` returns `{ ok: true, manifest }` (FR-001, FR-004, FR-006, FR-007 / SC-002). Fails red until effective-lifecycle resolve serves `deprecated` inside the window. **Satisfies**: FR-001, FR-004, FR-006, FR-007 / SC-002. **Proves**: T-J1-02.
- [ ] T004 [US1] Add named test `T-J1-03 retired_pin_returns_capability_retired` to `ai-platform/test/capability-deprecation.test.ts`: after `retire`, the same pin → `{ ok: false, code: "capability_retired" }` (not opaque) (FR-005 / SC-003). Fails red until retire mutation and resolve rejection on effective `retired` exist. **Satisfies**: FR-005 / SC-003. **Proves**: T-J1-03.
- [ ] T005 [US1] Add named test `T-J1-04 retire_journaled_with_operator_identity` to `ai-platform/test/capability-deprecation.test.ts`: retire writes a `control_audit` row with that operator id and action `retire` (FR-008 / SC-004). Fails red until control retire + audit write exist. **Satisfies**: FR-008 / SC-004. **Proves**: T-J1-04.
- [ ] T006 [US1] Add named test `T-J1-05 lifecycle_survives_cold_isolate_manifest_unchanged` to `ai-platform/test/capability-deprecation.test.ts`: after deprecate (or retire), a fresh `ConfigCache` (cold isolate) reconstructs lifecycle via `loadConfig("grants", …)` for discovery and resolve; published manifest content / `hashManifest` unchanged (FR-009, FR-010 / SC-005). Fails red until overlay is durable on `capability_grant` and read through the config cache. **Satisfies**: FR-009, FR-010 / SC-005. **Proves**: T-J1-05.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Vitest entries, harness config, or Documentation. Migration + `schema.snap.sql` are one FR-009 schema unit (A5 precedent: snapshot reflects post-migration shape). Consumed C1/B2/A5 modules are extended or imported, not rewritten (delivery plan §2.3). Contracts are already frozen. Tests turn green in matching groups per plan Sequencing: migration → overlay read + resolve/discover → control deprecate/retire + worker routes.

- [ ] T007 [US1] Create `ai-platform/migrations/20260802100000_capability_grant_lifecycle.sql` — forward-only `ALTER TABLE capability_grant ADD` nullable `lifecycle_state`, `successor_id`, `deprecated_at`, `retire_after`. Update `ai-platform/schema.snap.sql` so the snapshot matches the post-migration `capability_grant` shape (FR-009; delivery plan §3.9 band J note; §13.4). No new table. **Satisfies**: FR-009. **Proved by**: T-J1-05 (and every case that seeds/writes the overlay).
- [ ] T008 [US1] Modify `ai-platform/src/capability/index.ts` — `effectiveLifecycle(manifest, overlay)`; resolve rejects only effective `retired` (`capability_retired`); serves effective `deprecated` inside the OD-9 overlap window (named constant: two client release cycles, minimum 90 days — not a configuration surface); discovery includes granted effective-`active` **and** effective-`deprecated` (with successor) and excludes effective `retired`; overlay loaded through `loadConfig("grants", "global/{id}/{version}")`; registry / published manifest bytes untouched (FR-001..007, FR-010). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-010. **Proved by**: T-J1-01, T-J1-02, T-J1-03, T-J1-05.
- [ ] T009 [US1] Modify `ai-platform/src/control/index.ts` — `handleDeprecate` / `handleRetire`; append-only global-scope `capability_grant` overlay row (lifecycle state, successor, `deprecated_at`, `retire_after`); `control_audit` actions `deprecate` / `retire` with operator identity; refuse retire without prior announced deprecation (successor set) or before `retire_after`; `dispatchControlRequest` routes (FR-008, FR-009; gates FR-002, FR-005, FR-007). Does not redefine enroll / rotate / suspend / resume / delete or the `control_audit` row shape. **Satisfies**: FR-008, FR-009. **Proved by**: T-J1-01, T-J1-03, T-J1-04, T-J1-05.
- [ ] T010 [US1] Modify `ai-platform/src/worker.ts` — dispatch new `/control/capabilities/...` paths to the control handlers (same `/control` boundary B2 froze; FR-008). **Satisfies**: FR-008. **Proved by**: T-J1-01, T-J1-04 (mutation path through the Worker control boundary).

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T011 [US1] From `ai-platform/`, run this slice's suite — `npx vitest run --config vitest.workers.config.ts test/capability-deprecation.test.ts`. Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm J1's five named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. The only error code this slice's retirement path emits is `capability_retired` (T-J1-03); unknown / disabled remain C1's. **Satisfies**: the §3.10 checkpoint rule (T-J1-01 .. T-J1-05 + prior suites). Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T012 [US1] Create `specs/048-capability-deprecation/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.9 row J1; Implements §5.7, §12.4, A12; what the spec delivered; what the plan scoped. **§2 What was implemented** — additive `capability_grant` overlay migration; control-plane deprecate / retire; resolve / discovery overlay reads; OD-9 overlap constant; frozen `contracts/capability-deprecation.md`. **§3 Files to review** — only this slice's migration, `src/capability/index.ts` diff, `src/control/index.ts` diff, `src/worker.ts` diff, `test/capability-deprecation.test.ts`, and the frozen contract (no prior-slice files). **§4 Prerequisites** — Miniflare D1 workers pool (`vitest.workers.config.ts`); one-time `npm install` in `ai-platform/`. **§5 Run the automated suite** — slice-only `npx vitest run --config vitest.workers.config.ts test/capability-deprecation.test.ts` (no full-suite `npm test`, no combined prior-slice counts). **§6 Inspect the changes** — grep overlay columns / `deprecate`/`retire` actions; read the frozen contract; confirm manifests unchanged after a lifecycle mutation. **§7 Manual validation** — omit; CI is the only verification path (plan). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — no dependencies; blocks the Tests phase (workers include / Node exclude must be wired before any test runs in the right pool).
- **Tests (T002–T006)** — depends on Setup; every test is written against overlay / control / resolve behaviour that is absent or incomplete, so the file is red until the Implementation phase lands. All five append to the same file — sequential (T002 creates the substrate).
- **Implementation (T007–T010)** — after tests exist (red). Order follows plan Sequencing: migration + snapshot (T007) → capability overlay read / resolve / discover (T008) → control deprecate / retire (T009) → worker routes (T010). Tests turn green in matching groups: T-J1-02/03 against seeded overlay with T008; T-J1-01/04 through the mutation path with T009–T010; T-J1-05 with durable overlay + cold cache (T007–T008).
- **Verification (T011)** — depends on T001–T010; runs this slice plus every prior slice per §3.10.
- **Documentation (T012)** — depends on T011 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing: migration (T007) → overlay resolve/discover (T008) → control handlers (T009) → worker dispatch (T010) → quickstart (T012).
- Vitest entry Files-section row (`capability-deprecation.test.ts`) is produced by Phase 2; vitest config pair by Phase 1. Remaining Files units are T007–T010 plus T012 (`quickstart.md`). `contracts/capability-deprecation.md` is already frozen — no task recreates it.

### Parallel Opportunities

- Phase 1 (T001) is a single task — no internal parallelism.
- Phase 2 (T002–T006) all touch the same file (`capability-deprecation.test.ts`) — no `[P]`; sequential, each appending to the substrate T002 created.
- Phase 3 (T007–T010) are sequential per plan Sequencing (migration before overlay reads; control before worker routes). No `[P]` — later units depend on earlier ones.
- Phase 5 (T012) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Within this slice's single-file test phase and sequential implementation chain there is no `[P]`.
- Every named test T-J1-01 .. T-J1-05 from `spec.md` is covered by its own task; no test is folded into another.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (C1, B2).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism; no Flutter update UX beyond returning `capability_retired`; no second Quota DO / R2 object; no guard-rejection `ai_request` row; no per-request server-side state; no manifest edit or republish for a lifecycle transition.
