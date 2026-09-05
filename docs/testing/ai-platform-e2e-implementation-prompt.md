# AI Platform E2E Implementation Prompt — Sequential Stages, Parallel Writers

## Mission

Implement the E2E test suite specified by the scenario catalog at
`docs/testing/catalog/` (README.md + 14 stage chapters + registers.md, 818
scenarios). The catalog is the spec; `ai-platform/src/` and
`backend/supabase/migrations/` remain authoritative on any conflict — record
conflicts, follow code.

## Orchestration model

- **All subagents run on Grok 4.6 at high effort** — writers, runner, fixers,
  harness builder, and the final verifier alike. Do not downgrade any subagent
  to a faster/cheaper model.
- **Phase 0 (blocking):** one agent builds the shared harness. Nothing else
  starts until it is merged and its exemplar tests pass.
- **Phases 1…14 (one stage at a time, in journey order 00 → X):** within each
  stage, work is parallel; across stages, strictly sequential. Never start
  stage N+1 until stage N is green.
- **Per-stage loop:**
  1. **Writers (parallel, N subagents):** each implements a disjoint chunk of
     the stage's scenarios into its own test file. Writers NEVER run tests.
  2. **Runner (1 subagent):** runs the stage's tests, writes a structured
     failure report. Does not fix anything.
  3. **Fixers (parallel, one per failing file):** each fixes only the failures
     assigned to it. Fixers may run ONLY their own assigned test file.
  4. Repeat runner → fixers until the stage is green, max 3 iterations; then
     stop and escalate the remaining failures to the human.
- **Phase 15 (blocking):** one fresh verification agent proves coverage and
  runs the whole suite.

## Hard rules

1. **Traceability.** Every test name starts with its scenario ID:
   `test("S09-023 — <short title>", ...)`. A test without an ID is a defect;
   an automatable ID without a test is a gap.
2. **Register 5 is a DO-NOT-IMPLEMENT list** (`registers.md`, Non-Automatable
   Register, 45 rows). Each becomes `it.skip("<ID> — <reason from register>")`.
   Never silently weaken a scenario to make it runnable.
3. **[SEED] discipline.** Direct D1 seeding only where the scenario's Journey
   setup says `[SEED]`. All other prior state is built by executing the real
   earlier-stage operations through the harness.
4. **File ownership.** No subagent ever writes to a file another subagent
   owns. Writers own exactly one new test file each; fixers own only the
   failing files assigned to them; nobody modifies the harness after Phase 0.
5. **Never weaken assertions to go green.** If a test fails because the
   catalog disagrees with the code, the fixer follows the CODE, adjusts the
   test, and records the conflict in the stage report. If unsure, escalate —
   do not guess.
6. **Supabase contract scenarios are out of scope for stage writers** (Stage
   2, Stage 6, S08-061…S08-069, S11-022…S11-029). They are a separate pgTAP /
   PostgREST track handled after Phase 15.

## Phase 0 — Harness (single agent, blocking)

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
API. Exemplars green before any stage starts.

## Per-stage procedure (stages 00…12, X — one at a time)

### Step A — Writers (parallel)

Split the stage chapter into chunks of 15–25 scenarios by ID range. Spawn one
writer subagent per chunk, each with the WRITER PROMPT below. Each writer
creates exactly one file: `test/e2e/stage-NN-<chunk-slug>.test.ts`.

### Step B — Runner (single subagent)

Run `npx vitest run test/e2e/stage-NN-*`. Write
`test/e2e/reports/stage-NN-failures.md` with one entry per failure:

```
### <scenario ID> — <test file>
- Error: <exact assertion/exception output>
- Expected per catalog: <status/body/side effect>
- Actual: <observed>
- Suspected cause: harness | test-logic | catalog-vs-code conflict
```

### Step C — Fixers (parallel)

Group failures by test file. Spawn one fixer per file with the FIXER PROMPT
below. Fixers may run ONLY their assigned file
(`npx vitest run <their-file>`). When all fixers finish, go to Step B again.

Green = stage suite passes with zero failures and zero unexpected skips.
Then proceed to the next stage.

## Phase 15 — Verification (single fresh agent, blocking)

1. Extract every scenario ID from `docs/testing/catalog/`; extract every ID
   from test names and `it.skip` calls; diff. Every automatable ID must have a
   test; every skipped ID must cite a Register 5 row.
2. Run the FULL suite (all stages). Zero failures.
3. Fix all gaps before reporting done.

## WRITER PROMPT (template — one per chunk)

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
```

## RUNNER PROMPT (template)

```markdown
Run the Stage NN test suite: `npx vitest run test/e2e/stage-NN-*`.
Do NOT fix anything. Write `test/e2e/reports/stage-NN-failures.md` using the
entry format from the orchestrator prompt. Include passing/skipped counts.
Classify each failure's suspected cause (harness | test-logic |
catalog-vs-code conflict) from the error output and the catalog entry.
```

## FIXER PROMPT (template — one per failing file)

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
```

## Definition of done

- All 14 stages green, in sequence; full suite green in Phase 15
- Every automatable scenario ID has a test; every Register 5 ID is skipped
  with a reason; zero untagged tests
- All catalog-vs-code conflicts recorded in the stage reports
- No production source files modified

## Pitfalls (learned while building the catalog)

- Writers not running their own tests means harness misuse WILL surface in the
  first runner pass — expect iteration 1 to have the most failures; that's
  normal, not a crisis.
- Keep writer chunks small (15–25 scenarios): large one-shot file writes stall
  agents.
- The runner's structured report is the contract between steps — reject vague
  reports and re-run the runner if entries lack exact error output.
- Fixers grading their own fixes is fine (they run their file); the STAGE is
  only declared green by the runner, not by fixers.
