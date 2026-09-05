# AI Platform — Full-Journey Scenario Catalog Prompt

Purpose: a self-contained prompt whose **only deliverable is a markdown scenario
catalog** covering the **entire AI Platform journey** — from platform boot and
enrollment through entitlements, routing policy, discovery, AAT minting, live
requests, settlement, and support/retention — every reachable scenario, error
code, and side effect. No test implementation. It encodes the assumptions and
decisions that a one-paragraph brief would leave implicit, so the executing agent
does not have to guess scope, depth, or done-ness.

---

## Table of Contents

1. [The Prompt](#1-the-prompt)
2. [Assumptions Encoded](#2-assumptions-encoded)
3. [Open Questions to Resolve Before Implementation](#3-open-questions-to-resolve-before-implementation)

---

## 1. The Prompt

Copy everything between the `BEGIN PROMPT` / `END PROMPT` markers.

---

BEGIN PROMPT

### 1.1 Mission

Compile a **complete scenario catalog** for the whole AI Platform data journey —
every stage from platform boot to request settlement, support, and retention —
covering **every reachable scenario**: every control-plane operation and its
failure paths, every guard-stage rejection, every post-accept outcome, every error
code in the taxonomy, every cron-driven behavior, and all happy paths.

**The deliverable is a single markdown file:
`docs/testing/ai-platform-e2e-scenario-catalog.md`. You are NOT implementing
tests. Do not write test code, fixtures, helpers, or harnesses.** Scenario count
and catalog length are not constraints — completeness is.

### 1.2 Source of truth

- **Code is authoritative:** `ai-platform/src/` (worker, control plane, guard
  pipeline, quota DO, router, invocation, stream, journal, pricing, errors),
  `ai-platform/migrations/`, `ai-platform/manifests/`, `ai-platform/control/`
  artifacts, and — for the Supabase-side stages — `backend/supabase/migrations/`.
- **Docs are orientation only:** `docs/architecture/ai-platform/data-journey/`
  (stages 0–12 + alternative/failure journeys + reference docs) and
  `docs/architecture/ai-platform/request-lifecycle-brief.md`. Where docs and code
  disagree, follow the code and record the discrepancy in the catalog.

### 1.3 The journey under test (stage map)

The catalog is organized as one chapter **per stage**, in journey order; each
stage's scenarios produce the state the next stage consumes. The stages (from the
data-journey docs, to be verified against code — add, rename, or reorder stages if
the code disagrees):

### 1.4 Core principle — scenarios mimic production, not branch coverage

This is the most important instruction in this prompt.

**Every scenario must be a production-faithful journey, not an isolated branch
probe.** A scenario is NOT "set flag X, call endpoint, expect error Y." A
scenario IS: a realistic sequence of operations that a real operator, clinic
client, or cron tick would perform — starting from the beginning of the flow —
where the system under test passes through the **actual stage pipeline in the
actual order**, with realistic payloads, realistic prior state, and realistic
timing, until it reaches the outcome under test.

Concretely:

1. **Full-path execution.** A scenario targeting guard stage 5 starts at the
   adapter gate and passes stages 1–4 legitimately (real AAT, real entitlement,
   real rate-limit pass) — it does not stub or bypass earlier stages to reach
   stage 5. The only permitted doubles are the seams production itself has:
   the provider adapter (FakeAdapter), and — where unavoidable in a test
   environment — the CF rate-limiter bindings and DO failure injection.
2. **Realistic state, honestly built.** Required prior state (enrolled
   installation, active entitlement, published routing policy, DO counters) is
   created by **executing the earlier stages' real operations** wherever
   possible, not by writing rows directly into D1. Direct seeding is a documented
   exception, used only where the real operation cannot produce the state (e.g.
   aged rows for retention, exhausted budgets without burning thousands of
   requests).
3. **Blocker escalation.** Within each stage, scenarios form a progressive
   chain: scenario N satisfies every condition for blockers 1…N−1 through real
   execution and trips blocker N; scenario N+1 clears blocker N and trips blocker
   N+1; the final scenarios clear everything and reach the happy path. Across
   stages, each stage's happy-path scenarios produce the handoff state the next
   stage's chain consumes.
4. **Observable outcomes, not internals.** Expected results are stated in terms
   of what production observers see: HTTP status + taxonomy body, SSE event
   sequences, D1/DO/R2 state after the operation, cron side effects — not
   internal function returns.
5. **Combinations are journeys too.** Input-field combinations (boundary +
   pairwise per operation, not exhaustive cartesian) are expressed as distinct
   realistic requests, each driven through the full path.

### 1.5 The deliverable — scenario catalog format

Write `docs/testing/ai-platform-e2e-scenario-catalog.md` with one chapter per
stage (§1.3) and, within each chapter, scenarios in blocker-escalation order.
Every scenario must specify:

| Field | Content |
|-------|---------|
| ID | Stable identifier, e.g. `S08-014` (stage 8, scenario 14) |
| Title | Behavior under test, in plain language |
| Journey setup | The real operations executed first (with references to the scenario IDs that establish reused state) and any documented direct-seeding exceptions |
| Action | The exact request(s)/operation(s): method, path, headers, body — with concrete realistic values, not placeholders |
| Expected outcome | HTTP status + full taxonomy body, or SSE event sequence, or control-plane response — as the code produces it |
| Side effects | Exact D1/DO/R2/Supabase writes that must and must not occur, verified against code |
| Code reference | File and function in `ai-platform/src/` (or `backend/supabase/`) that implements the behavior |

Additionally, the catalog must include:

1. **Error-code inventory:** every code in `errors.ts`, mapped to the scenario(s)
   that produce it; any code with no producing path is flagged as unreachable
   (dead path).
2. **Auth-boundary matrix:** every route × {no credentials, wrong credentials,
   insufficient scope, cross-installation access} with expected results.
3. **Input-field appendix:** per operation, every field (headers, path params,
   body fields, JWT claims, context keys, transcript shape) with its validation
   rules and boundary values, each mapped to the scenarios covering it.
4. **Doc-drift register:** every behavior the docs describe that the code does
   not implement, and every code path no doc mentions.
5. **Non-automatable register:** any scenario that cannot be executed against the
   real worker in a test environment (e.g. a binding that cannot be forced to
   trip), with the reason and the proposed seam.

### 1.6 Coverage rules

**Coverage is decided by you from the code, not by this prompt.** This prompt
deliberately enumerates no per-stage scenarios. You are explicitly required to:

1. Treat every conditional branch, validation check, error return, state
   transition, and auth boundary in the source as a scenario candidate, whether
   or not it appears in any doc.
2. Derive every scenario's trigger condition, required storage state, expected
   error code/status, and side-effect contract from the code itself.
3. Flag doc drift in both directions (docs describe what code lacks; code
   implements what docs omit).
4. Never use "no doc or prompt mentioned it" as a reason to skip a code path.
5. Include the cron-driven behaviors (retention, counter flush, grace
   reconciliation, DO ephemeral sweep) as first-class scenarios with forced
   timing, not wall-clock waits.

### 1.7 Implementation constraints the scenarios must respect

You are not building the harness, but scenarios must be **implementable** against
the real worker. Write them so that a later implementation phase can execute them
via `@cloudflare/vitest-pool-workers` (or the repo's existing test setup) with
real D1 migrations, the `FakeAdapter` provider seam, directly-invoked cron
handlers, and an AAT minting helper with full claim control. Where a scenario
needs something this environment cannot provide, put it in the non-automatable
register instead of silently weakening it. Supabase-side stages (2, and
`record_ai_acceptance` in 11) are specified as contract scenarios against
`backend/supabase/migrations/`; if they cannot execute from this repo, that gap
is recorded, not skipped.

### 1.8 Orchestration — multi-subagent execution

Execute this task with parallel subagents (kimi-k3-high), orchestrated by you.
Do not author the whole catalog in a single context.

1. **Template is fixed here — no bootstrap chapter.** All subagents start in
   parallel from the canonical chapter template below; nobody waits for anyone.
   Deviations from the template are not permitted.

   ```markdown
   # Stage NN — <stage name>

   Source files read: <list of files actually read before authoring>

   ## Scenario SNN-001 — <plain-language behavior under test>

   | Field | Content |
   |-------|---------|
   | ID | SNN-001 |
   | Journey setup | <real operations executed first, referencing prior scenario IDs; direct-seeding exceptions marked [SEED] with justification> |
   | Action | <exact method, path, headers, body — concrete realistic values> |
   | Expected outcome | <HTTP status + full taxonomy body, or SSE event sequence, or control-plane response> |
   | Side effects | <exact D1/DO/R2/Supabase writes that must and must not occur> |
   | Code reference | <path/to/file.ts:Lstart-Lend — function name> |

   ## Scenario SNN-002 — ...
   ```

2. **One subagent per stage, all in parallel.** Spawn one subagent per stage
   (0–12, X) simultaneously, each writing exactly one file:
   `docs/testing/catalog/stage-NN-<name>.md`. Each subagent prompt must include:
   this entire prompt, its assigned stage and scenario-ID prefix (`SNN-`), and
   the stage's source files to read before authoring.
3. **No shared files.** Subagents never write to the same file. You merge the
   per-stage files into `docs/testing/ai-platform-e2e-scenario-catalog.md` after
   all complete.
4. **Registers are a separate pass.** The error-code inventory, auth-boundary
   matrix, input-field appendix, doc-drift register, and non-automatable
   register are compiled by you (or a dedicated subagent) after the merge — not
   by stage subagents — to avoid duplicates and boundary gaps.
5. **Verification pass.** After merging, spawn a fresh verification subagent
   that re-scans `errors.ts`, the route table in `worker.ts`, and every
   `control/*.ts` handler, and proves every error code, route, and rejection
   branch maps to a scenario ID. Every gap it finds is fixed before delivery.
6. **Line-anchored citations.** Every scenario's code reference must include
   file path and line range. A scenario without a verifiable anchor is treated
   as a hallucination suspect and re-derived from source.

### 1.9 Definition of done

1. The catalog exists at `docs/testing/ai-platform-e2e-scenario-catalog.md`
   (merged from per-stage files) and every scenario follows the §1.5 format with
   all fields populated.
2. Every stage in the (code-verified) stage map has a chapter; every endpoint and
   operation within it has happy-path, auth-failure, validation-failure, and
   state-precondition scenarios.
3. Every error code in `errors.ts` maps to at least one scenario, or is flagged
   unreachable.
4. Every scenario is a full production-faithful journey per §1.4 — the catalog
   contains no "set flag, expect error" branch probes.
5. The error-code inventory, auth-boundary matrix, input-field appendix,
   doc-drift register, and non-automatable register are complete.
6. The §1.8 verification pass ran and reported zero unmapped codes, routes, or
   branches.
7. No test code, fixtures, or implementation artifacts were written.

I do not care if the tests number are huge. What I care about is covering all possible scenarios.

END PROMPT

---

## 2. Assumptions Encoded

| # | Assumption | Rationale |
|---|-----------|-----------|
| 1 | Scope is the **full data journey** (stages 0–12 + failure journeys), not just `POST /v1/requests` | Confirmed by the requester: "test everything — installation, entitlements, routing, discovery, minting, requests, and all steps I did not mention" |
| 2 | The deliverable is a scenario catalog MD file, not implemented tests | Confirmed by the requester: "the prompt shall compile an md file with all the scenarios, not implement" |
| 3 | Scenarios must mimic production flows, not probe branches | Confirmed by the requester: "tests need to mimic the production stages, not just dumb if conditions and error codes" — so each scenario runs the real pipeline end-to-end with honestly-built state |
| 4 | Prior state should be built by executing real earlier-stage operations, with direct seeding as a documented exception | This is what makes scenarios production-faithful rather than fixture theater; exceptions (aged rows, exhausted budgets) are unavoidable |
| 5 | The stage map is a starting scaffold, not gospel — the executor may restructure it if the code disagrees | The map is doc-derived and this repo has known doc/code drift |
| 6 | "All combinations of input fields" means boundary + pairwise per operation, not full cartesian | Full cartesian is unbounded; pairwise catches the overwhelming majority of interaction bugs |
| 7 | Scenarios must be implementable against the real worker (vitest workers pool, FakeAdapter, direct cron invocation, AAT minting helper) even though implementation is out of scope | A scenario that cannot be executed is a wish, not a test case; the non-automatable register keeps this honest |
| 8 | Supabase-side RPCs (stage 2, `record_ai_acceptance`) may only be contract-specifiable from this repo | They live in `backend/supabase/`; gaps are recorded, not silently skipped |

## 3. Open Questions to Resolve Before Implementation

These do not block catalog authoring, but the catalog's scenarios should be
written with answers in mind (or flag where an answer changes a scenario):

1. Does an AAT minting helper already exist in `ai-platform/` test utilities, or
   must one be built (EdDSA signing with controllable claims)?
2. Can the Quota DO be instantiated directly in the test pool for counter
   pre-loading, or is a test-only RPC needed?
3. Is there an existing fixture/seed pattern in the repo (e.g. under
   `ai-platform/tests/`) that the eventual suite should follow?
4. Are the Supabase RPC stages (2 and parts of 11) executable from this repo, or
   contract-only?
5. Where should the eventual suite live (`ai-platform/tests/e2e/`?) and what
   command should run it (`npm run test:e2e`?)?
