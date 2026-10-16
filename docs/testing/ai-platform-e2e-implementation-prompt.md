# AI Platform E2E Implementation Prompt — Sequential Stages, Parallel Writers

## 1. Mission

Implement the E2E test suite specified by the scenario catalog at
`docs/testing/catalog/` (README.md + 14 stage chapters + registers.md, 818
scenarios). The catalog is the spec; `ai-platform/src/` and
`backend/supabase/migrations/` remain authoritative on any conflict — record
conflicts, follow code.

## 2. Orchestration model

Three layers. No layer skips the one below it.

1. **Top-level orchestrator** (the agent reading this prompt). It never writes
   tests, never runs tests, and never edits harness or test files. It only
   launches **one controller subagent at a time**, waits for that controller's
   report, and gates the next phase/stage on green.
2. **Phase/stage controllers** (one dedicated subagent per phase or stage).
   Each controller owns its phase/stage end-to-end. It reads the spec, splits
   work, **spawns the child subagents** named in this prompt, collects their
   reports, runs the per-stage loop, and is the only agent allowed to declare
   that phase/stage green.
3. **Child subagents** (writers, runner, fixers, and Phase 15 auditors). They
   do the work under a controller. They never spawn further agents and never
   talk to the top-level orchestrator directly.

- **All subagents run on Grok 4.6 at high effort** — controllers, writers,
  runner, fixers, harness builder, and verifiers alike. Do not downgrade any
  subagent to a faster/cheaper model.
- **Phase 0 (blocking):** the orchestrator spawns one Phase 0 controller. That
  controller builds the shared harness (it typically does the work itself;
  harness file ownership is a single surface). Nothing else starts until the
  controller reports merged and exemplar tests pass.
- **Phases 1…14 (one stage at a time, in journey order 00 → X):** the
  orchestrator spawns **one stage controller** for stage N, waits until that
  controller reports green, then spawns the controller for stage N+1. Never
  start stage N+1 until stage N is green. Never spawn two stage controllers
  concurrently. Within a stage, the **stage controller** (not the
  orchestrator) parallelizes writers and fixers.
- **Per-stage loop (executed by the stage controller):**
  1. **Writers (parallel, N child subagents):** each implements a disjoint
     chunk of the stage's scenarios into its own test file. Writers NEVER run
     tests.
  2. **Runner (1 child subagent):** runs the stage's tests, writes a
     structured failure report. Does not fix anything.
  3. **Fixers (parallel, one per failing file):** each fixes only the
     failures assigned to it. Fixers may run ONLY their own assigned test
     file.
  4. Repeat runner → fixers until the stage is green, max 3 iterations; then
     stop and escalate the remaining failures to the orchestrator, which
     escalates to the human.
- **Phase 15 (blocking):** the orchestrator spawns one Phase 15 controller.
  That controller spawns coverage-audit and full-suite-runner children, then
  gap-fixer children if needed, and proves coverage plus a green full suite.

## 3. Hard rules

1. **Controller isolation.** The orchestrator launches only controllers. A
   controller launches only its own children. Writers, the runner, and fixers
   are never spawned by the orchestrator. A controller never implements tests
   itself (Phase 0 is the exception: the harness controller writes the
   harness). A child never writes files outside its assignment and never
   spawns agents.
2. **Traceability.** Every test name starts with its scenario ID:
   `test("S09-023 — <short title>", ...)`. A test without an ID is a defect;
   an automatable ID without a test is a gap.
3. **Register 5 is a DO-NOT-IMPLEMENT list** (`registers.md`, Non-Automatable
   Register, 45 rows). Each becomes `it.skip("<ID> — <reason from register>")`.
   Never silently weaken a scenario to make it runnable.
4. **[SEED] discipline.** Direct D1 seeding only where the scenario's Journey
   setup says `[SEED]`. All other prior state is built by executing the real
   earlier-stage operations through the harness.
5. **File ownership.** No subagent ever writes to a file another subagent
   owns. Writers own exactly one new test file each; fixers own only the
   failing files assigned to them; nobody modifies the harness after Phase 0.
6. **Never weaken assertions to go green.** If a test fails because the
   catalog disagrees with the code, the fixer follows the CODE, adjusts the
   test, and records the conflict in the stage report. If unsure, escalate —
   do not guess.
7. **Supabase contract scenarios are out of scope for stage writers** (Stage
   2, Stage 6, S08-061…S08-069, S11-022…S11-029). They are a separate pgTAP /
   PostgREST track handled after Phase 15. The matching stage controller still
   runs: it records those IDs as out-of-scope in the stage report and does not
   spawn writers for them.

## 4. Top-level orchestrator procedure

Launch controllers **strictly one at a time**. After each returns, read its
report under `ai-platform/test/e2e/reports/` and gate:

| Order | Controller to spawn | Green means |
|---|---|---|
| 0 | Phase 0 harness controller | `test/e2e/harness/` + README exist; 3 exemplars pass |
| 1 | Stage 00 controller | Stage 00 suite green; stage report written |
| 2 | Stage 01 controller | Stage 01 suite green; stage report written |
| … | … | … |
| 14 | Stage X controller | Stage X suite green; stage report written |
| 15 | Phase 15 verification controller | Coverage complete; full suite green |

If a controller reports not-green or hits the iteration cap, **stop**. Do not
launch the next controller. Escalate the controller's remaining-failures list
to the human.

Do not re-split work, re-spawn writers, or re-run tests at the orchestrator
layer. That is the controller's job. If a controller's report is vague
(missing IDs, missing error output, no pass/skip counts), reject it and
re-spawn **that same controller** with the rejection reason — do not reach
around it to its children.

## 5. Phase 0 — Harness (controller, blocking)

The orchestrator spawns **one** Phase 0 controller with the PHASE 0
CONTROLLER PROMPT. That controller owns every file under `test/e2e/harness/`
and `test/e2e/README.md`. It does the work itself (no child writers): shared
harness ownership must stay on one agent.

Inventory the existing test setup (`ai-platform/vitest.config.*`,
`ai-platform/test/`), then build in `ai-platform/test/e2e/`:

- D1 bootstrap applying the real migrations per test database
- AAT minting helper with full claim control (kid, iss, aud, exp/iat, ver,
  scopes, roles), signed by a test keypair enrolled through the real enroll
  path
- Control-plane request helper (operator bearer, wrong-bearer variants)
- Direct GatewayObject RPC helper (`idFromName` → `stub.fetch`, `now`
  injection)
- Cron invoker calling `worker.scheduled({ cron })` directly
- SSE stream reader asserting event sequences
- Doubled CF rate-limiter bindings and fault-injecting D1/DO wrappers
  (Register 5 seams)
- 3 exemplar tests that PASS: one control-plane 401, one guard rejection with
  full taxonomy body, one happy-path SSE `accepted`

Deliverable: `test/e2e/harness/` + `test/e2e/README.md` documenting the frozen
API. Exemplars green before any stage controller starts. Write
`test/e2e/reports/phase-00-harness.md` for the orchestrator.

## 6. Stage controller procedure (stages 00…12, X — one controller at a time)

The orchestrator spawns **one** stage controller with the STAGE CONTROLLER
PROMPT, substituting the stage number, chapter path, and ID prefix. That
controller then runs the loop below. The orchestrator does not perform these
steps itself.

### 6.1 Step A — Writers (parallel children of the stage controller)

Split the stage chapter into chunks of 15–25 scenarios by ID range. Spawn one
writer subagent per chunk, each with the WRITER PROMPT below. Each writer
creates exactly one file: `test/e2e/stage-NN-<chunk-slug>.test.ts`.

Wait for **all** writers to finish before Step B. If a writer fails to
produce its file, re-spawn that writer only; do not start the runner with a
missing chunk.

### 6.2 Step B — Runner (single child of the stage controller)

Spawn one runner with the RUNNER PROMPT. It runs
`npx vitest run test/e2e/stage-NN-*` and writes
`test/e2e/reports/stage-NN-failures.md` with one entry per failure:

```
### <scenario ID> — <test file>
- Error: <exact assertion/exception output>
- Expected per catalog: <status/body/side effect>
- Actual: <observed>
- Suspected cause: harness | test-logic | catalog-vs-code conflict
```

Reject a vague runner report and re-spawn the runner. Do not fix tests in
the controller.

### 6.3 Step C — Fixers (parallel children of the stage controller)

Group failures by test file. Spawn one fixer per file with the FIXER PROMPT
below. Fixers may run ONLY their assigned file
(`npx vitest run <their-file>`). When all fixers finish, go to Step B again.

Green = stage suite passes with zero failures and zero unexpected skips.
The **stage controller** declares green only after a runner pass with a
clean report — never from fixer self-reports. Then it writes
`test/e2e/reports/stage-NN.md` and returns to the orchestrator, which
proceeds to the next stage controller.

## 7. Phase 15 — Verification (controller, blocking)

The orchestrator spawns **one** Phase 15 controller with the PHASE 15
CONTROLLER PROMPT. That controller does not audit or run the suite itself.
It spawns:

1. **Coverage auditor (1 child):** extract every scenario ID from
   `docs/testing/catalog/`; extract every ID from test names and `it.skip`
   calls; diff. Every automatable ID must have a test; every skipped ID must
   cite a Register 5 row. Write `test/e2e/reports/phase-15-coverage.md`.
2. **Full-suite runner (1 child):** run the FULL suite (all stages). Write
   `test/e2e/reports/phase-15-failures.md` in the same entry format as the
   stage runner. Zero failures required.
3. **Gap fixers (parallel, only if needed):** one child per file that has a
   coverage gap or a remaining failure. Same FIXER PROMPT constraints. Then
   re-spawn the auditor and/or full-suite runner.

The Phase 15 controller declares done only when coverage is complete and the
full-suite runner is green. Write `test/e2e/reports/phase-15.md` for the
orchestrator.

## 8. PHASE 0 CONTROLLER PROMPT (template — spawn exactly one)

```markdown
You are the Phase 0 harness controller for the AI Platform E2E suite.

You own the harness. Do the work yourself — do not spawn child agents.
Do not write stage test files.

Follow section 5 of `docs/testing/ai-platform-e2e-implementation-prompt.md`
exactly.

When exemplars pass, write `ai-platform/test/e2e/reports/phase-00-harness.md`
with: files created, frozen API summary, exemplar results. Return that path
to the orchestrator. If exemplars fail, report the failures and stop; do not
start any stage.
```

## 9. STAGE CONTROLLER PROMPT (template — one per stage, spawned by the orchestrator)

```markdown
You are the Stage NN controller for the AI Platform E2E suite. You own this
stage end-to-end. The orchestrator will not spawn your children for you.

Read first, in order:
1. `docs/testing/ai-platform-e2e-implementation-prompt.md` — follow section 6
   and the hard rules. Spawn writers, then a runner, then fixers, using the
   WRITER / RUNNER / FIXER prompts in that document.
2. `docs/testing/catalog/stage-NN-<name>.md` — the stage spec
3. `docs/testing/catalog/registers.md` — Register 5 skip list; Register 1
   error bodies
4. `ai-platform/test/e2e/README.md` — frozen harness API (do not modify)

Your job:
- Split this stage into disjoint 15–25 scenario chunks by ID range.
- Spawn one writer child per chunk **in a single parallel batch**. Writers
  never run tests. You never write test files yourself.
- After every writer has produced its file, spawn one runner child.
- If the runner reports failures, spawn one fixer child per failing file
  **in a single parallel batch**, then spawn the runner again.
- Max 3 runner→fixer iterations. Then stop and escalate remaining failures.
- Out-of-scope Supabase contract IDs (see hard rule 7): do not assign them
  to writers; list them as deferred in your stage report.
- You may not modify the harness. You may not touch another stage's files.
- Green is declared only by a clean runner pass, never by fixer self-reports.

Write `ai-platform/test/e2e/reports/stage-NN.md` with: chunk map (file → ID
range), writer outcomes, iteration count, passing/skipped/failing counts,
conflicts + harness gaps, remaining failures (if any). Return that path.
```

## 10. WRITER PROMPT (template — one per chunk, spawned by the stage controller)

```markdown
You are writing E2E tests for Stage NN of the AI Platform catalog, scenarios
SNN-XXX…SNN-YYY only.

Read first, in order:
1. `docs/testing/catalog/stage-NN-<name>.md` — your spec; implement ONLY your
   assigned scenario range
2. `docs/testing/catalog/registers.md` — Register 5 (skip list) and Register 1
   (exact expected error bodies)
3. `ai-platform/test/e2e/README.md` — the frozen harness API (use as-is; you
   may NOT modify it)
4. `ai-platform/test/e2e/stage-00-*.test.ts` — the exemplar style

Rules:
- Create ONLY `ai-platform/test/e2e/stage-NN-<chunk-slug>.test.ts`. Never
  touch any other file.
- DO NOT RUN the tests. Write only. Another agent runs them.
- Implement scenarios in catalog order. Test names start with the ID:
  `test("SNN-014 — <short title>", ...)`.
- Expected outcomes must match the catalog exactly: HTTP status, full taxonomy
  body, SSE event sequence, and the listed D1/DO/R2 side effects — including
  the "must not occur" writes.
- Build prior state via the harness's real operations; direct seeding only
  where the scenario says [SEED].
- Register 5 scenarios: `it.skip("SNN-0XX — <reason>")`.
- If the harness lacks something you need, write the test against the
  documented API as best you can and add a `// HARNESS-GAP: <what's missing>`
  comment — do NOT extend the harness yourself.
- Write the file in chunks if large.
- Report: implemented IDs, skipped IDs + reasons, harness gaps, any
  catalog/code conflicts noticed.
- Do not spawn subagents.
```

## 11. RUNNER PROMPT (template — spawned by the stage controller, or by the Phase 15 controller for the full suite)

```markdown
Run the Stage NN test suite: `npx vitest run test/e2e/stage-NN-*`.
Do NOT fix anything. Write `test/e2e/reports/stage-NN-failures.md` using the
entry format from the orchestrator prompt. Include passing/skipped counts.
Classify each failure's suspected cause (harness | test-logic |
catalog-vs-code conflict) from the error output and the catalog entry.
Do not spawn subagents.
```

## 12. FIXER PROMPT (template — one per failing file, spawned by the stage controller)

```markdown
You are fixing failing tests in `test/e2e/stage-NN-<chunk-slug>.test.ts` ONLY.

Read first:
1. `test/e2e/reports/stage-NN-failures.md` — your assigned entries
2. The scenario entries in `docs/testing/catalog/stage-NN-<name>.md` for each
   failing ID
3. The referenced source files in `ai-platform/src/` — code is authoritative

Rules:
- Touch ONLY your assigned test file.
- You may run ONLY your file: `npx vitest run test/e2e/stage-NN-<chunk-slug>.test.ts`.
- NEVER weaken an assertion to make a test pass. If the catalog disagrees
  with the code, follow the code, fix the test, and append the conflict to
  `test/e2e/reports/stage-NN-conflicts.md` (ID, catalog claim, code behavior,
  file:line).
- If the failure is a harness gap, do not work around it — record it in the
  conflicts file and leave the test failing.
- Report: fixed IDs, remaining failures + why.
- Do not spawn subagents.
```

## 13. PHASE 15 CONTROLLER PROMPT (template — spawn exactly one)

```markdown
You are the Phase 15 verification controller for the AI Platform E2E suite.

Do not audit coverage or run the full suite yourself. Spawn children as
specified in section 7 of
`docs/testing/ai-platform-e2e-implementation-prompt.md`:

1. Spawn a coverage-auditor child (extract catalog IDs vs test/`it.skip` IDs;
   write `test/e2e/reports/phase-15-coverage.md`).
2. Spawn a full-suite-runner child (`npx vitest run test/e2e`; write
   `test/e2e/reports/phase-15-failures.md`).
3. If gaps or failures remain, spawn one fixer per affected file using the
   FIXER PROMPT, then re-spawn auditor and/or runner.

You declare done only when coverage is complete and the full suite is green.
Write `ai-platform/test/e2e/reports/phase-15.md` and return that path.
Do not modify production source. Do not modify the harness.
```

## 14. Definition of done

- All 14 stages green, in sequence, each declared green by its **stage
  controller** after a clean runner pass; full suite green in Phase 15 as
  declared by the **Phase 15 controller**
- Every automatable scenario ID has a test; every Register 5 ID is skipped
  with a reason; zero untagged tests
- All catalog-vs-code conflicts recorded in the stage reports
- No production source files modified

## 15. Pitfalls (learned while building the catalog)

- The orchestrator must not skip the controller layer and spawn writers or
  fixers itself. Parallelism lives **inside** a stage controller, not across
  stages and not at the top level.
- Writers not running their own tests means harness misuse WILL surface in the
  first runner pass — expect iteration 1 to have the most failures; that's
  normal, not a crisis.
- Keep writer chunks small (15–25 scenarios): large one-shot file writes stall
  agents.
- The runner's structured report is the contract between steps — the stage
  controller must reject vague reports and re-spawn the runner if entries
  lack exact error output.
- Fixers grading their own fixes is fine (they run their file); the STAGE is
  only declared green by the stage controller after a runner pass, not by
  fixers and not by the orchestrator eyeballing fixer summaries.
- A stage controller that implements tests itself (instead of spawning
  writers) violates file-ownership and makes the runner/fixer split
  meaningless. Re-spawn that controller if it does this.
