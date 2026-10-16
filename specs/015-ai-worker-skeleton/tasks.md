# Tasks: Worker skeleton and environments (A1)

**Input**: Design documents from `/specs/015-ai-worker-skeleton/`

**Prerequisites**: `plan.md` (required), `spec.md` (required). No `research.md`, no `data-model.md`,
no `contracts/` — A1 defines no entities and freezes no machine-readable contract (plan Project
Structure → Documentation).

**Tests**: Every case in the spec's Test plan is a task. The template's optional-tests note does
not apply to this platform (Delivery Plan §3.10).

**Organization**: One slice, one user story (US1). Tasks are grouped by phase, not by story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (the single story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by A1*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by A1*
- **AI Gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/` *(none in A1)*, `ai-platform/test/`
- A1 creates the `ai-platform/` directory for the first time (plan Project Structure → Source Code)

---

## Phase 1: Setup

**Purpose**: Create the `ai-platform/` tree the plan's Files section names, so the tests and
implementation have files to live in.

- [X] T001 [US1] Create `ai-platform/` directory with `package.json` declaring `wrangler`,
      `vitest`, and `@cloudflare/vitest-pool-workers`, and `tsconfig.json` targeting the Workers
      runtime. Produces the project skeleton plan Files names. Satisfies no FR directly; it is the
      prerequisite for every later task. Proved by the suite running at all in T008.
- [X] T002 [US1] Create `ai-platform/wrangler.toml` defining three named environments
      (`development`, `staging`, `production`), each with its own `d1_databases`, `r2_buckets`,
      and `durable_objects` binding, and a per-environment `vars.BUILD_SHA` placeholder. Produces
      the binding topology. Satisfies FR-001, FR-002, FR-004. Proved by T005, T006, T007.

**Checkpoint**: The Worker project compiles and `wrangler` can parse the three environments.

---

## Phase 2: Tests

**Purpose**: One task per named test in the spec's Test plan, written to fail before the code
exists (Delivery Plan §3.10). All at the Contract-tests layer (§13.5), run in CI.

- [X] T003 [P] [US1] Write `ai-platform/test/health.test.ts` — T2
      `health_returns_build_and_environment_identity`: for each of the three environments, call
      the health endpoint through `unstable_dev` and assert the response carries build identity
      (the git commit SHA bound as `BUILD_SHA`) and environment identity (the wrangler environment
      name), as two distinct fields. Satisfies FR-005. Fails before `src/worker.ts` serves the
      endpoint.
- [X] T004 [P] [US1] Write `ai-platform/test/env-deploys.test.ts` — T1
      `env_each_environment_deploys`: assert `development`, `staging`, and `production` each
      deploy via `unstable_dev` and each exposes its own D1, R2, and Durable Object namespace
      binding (no cross-environment aliasing). Satisfies FR-001. Fails before T002's bindings are
      real.
- [X] T005 [P] [US1] Add to `ai-platform/test/env-deploys.test.ts` — T3
      `env_no_binding_shared_between_environments`: assert no D1 database id, R2 bucket name, or
      Durable Object namespace id is shared by any two of the three environments; the test fails
      on a deliberately shared binding. Satisfies FR-002. Fails while T002 points two envs at one
      resource. *(Separate task from T004 — it asserts an absence, the spy-style invariant from
      Delivery Plan §3.10, not an outcome.)*
- [X] T006 [P] [US1] Add to `ai-platform/test/env-deploys.test.ts` — T4
      `env_missing_required_binding_fails_at_startup`: for each required infrastructure binding
      (D1, R2, DO namespace), start an environment with that binding omitted and assert the Worker
      throws at startup (top-level scope) rather than succeeding and failing on first fetch.
      Satisfies FR-006. The missing-secret branch is **not** a case here — deferred to the slice
      that first introduces a secret binding (spec Clarifications 2026-07-30, FR-006). Fails before
      `src/worker.ts` performs the startup check.

**Checkpoint**: Four named tests exist and fail red.

---

## Phase 3: Implementation

**Purpose**: One task per implementation unit in the plan's Files section, each satisfying the
test(s) written red above.

- [X] T007 [US1] Implement the startup binding-presence check in `ai-platform/src/worker.ts`: at
      module top level, read the D1, R2, and Durable Object bindings from the runtime environment
      and throw if any is missing for the active environment, so the Worker fails at startup
      rather than at first use. Satisfies FR-006. Proved by T006. *(Depends on T001 for the file
      to exist; makes T006 green.)*
- [X] T008 [US1] Implement the health endpoint in `ai-platform/src/worker.ts`: a `fetch` handler
      matching the health path that returns a JSON body with two distinct fields — build identity
      (`BUILD_SHA` injected at deploy) and environment identity (the wrangler environment name).
      No other fields; no secret material (FR-003 edge case). Satisfies FR-005. Proved by T003.
      *(Depends on T007; makes T003 green.)*

**Checkpoint**: All four named tests pass green.

---

## Phase 4: Verification

**Purpose**: Run the whole suite, including every prior slice's suite (Delivery Plan §3.10).
A1 is the first slice, so "every prior suite" is empty — this task still exists and remains in
every later slice's verification phase.

- [X] T009 [US1] Run the full A1 suite (`vitest run` in `ai-platform/`) and confirm T1–T4 are
      green; confirm no prior-slice suite exists yet to regress. Satisfies the §3.10 "every prior
      suite green" rule for A1. Proved by the green run itself.

**Checkpoint**: Slice complete and provable by an automated test a human can read and believe
(Delivery Plan §2.2).

---

## Documentation

**Purpose**: The two documentation artifacts the plan's Files section names.

- [X] T010 [P] [US1] Write `specs/015-ai-worker-skeleton/quickstart.md`: the exact commands a
      human runs to deploy each of the three environments and to call the health endpoint, so the
      reviewer can reproduce the green suite. Satisfies FR-001, FR-005 from a human-verification
      angle (plan Project Structure → Documentation: quickstart.md exists because a human must run
      something to verify it).
- [X] T011 [P] [US1] Write `ai-platform/README.md`: one paragraph orienting future readers to the
      gateway directory and pointing at `wrangler.toml` and the health endpoint. Satisfies the
      plan's Structure Decision (orient future readers to the new `ai-platform/` directory).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T001 before T002 (the wrangler config
  is a file the package project must exist to hold).
- **Tests (Phase 2)**: Depends on T001 (the test files need the project) and T002 (T004/T005
  introspect the wrangler env definitions). Written to fail before Phase 3.
- **Implementation (Phase 3)**: Depends on Phase 2 tests existing red. T007 before T008 (the
  startup check runs before the fetch handler mounts).
- **Verification (Phase 4)**: Depends on Phase 3.
- **Documentation**: T010 and T011 are [P] and may run any time after T002 and T008 respectively
  (they document the now-passing deploy and health check).

### Within the Slice

- Tests are written red before the implementation that makes them green (Delivery Plan §3.10).
- The startup binding-presence check (T007) lands before the health endpoint (T008): a missing
  binding must fail before any handler runs.
- No model/service/endpoint layering — A1 has one source file.

### Parallel Opportunities

- T003, T004, T005, T006 are all [P] — four separate test concerns across two files, no
  dependencies among them once T001 and T002 exist. (T004/T005/T006 share a file but append
  distinct `describe` blocks; they may be authored in parallel and concatenated.)
- T010 and T011 are [P] — two different documentation files.

---

## Notes

- 11 tasks, under the 25-task cap (Delivery Plan §6.3 stop condition 5).
- Every task traces to a spec FR or a named test; no task adds a requirement the spec does not
  name.
- The missing-secret test is intentionally absent — it is deferred to the slice that first
  introduces a secret binding (spec Clarifications 2026-07-30). Adding it here would be work the
  spec does not name (R-20).
- No Polish phase: cleanup, refactoring, and generic "security hardening" are forbidden — each
  would be work the spec does not name (R-20).
- No Foundational phase: A1 has `Needs: —`; prerequisites are other slices, of which there are
  none.
- Commit after each task or logical group; the slice is complete at the T009 green run.
