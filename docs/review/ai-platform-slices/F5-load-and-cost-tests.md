# F5 — Load and Cost Tests: Static Review

Scope: slice F5 (`specs/043-load-and-cost-tests/`), implementation in
`ai-platform/test/load/` plus wiring in `ai-platform/package.json`,
`ai-platform/vitest.config.ts`, `ai-platform/vitest.workers.config.ts`.
Source of truth: `docs/architecture/17-ai-platform.md` §13.5 and §13.6
(including §13.6.1 and §13.6.2). Static review only — no code was executed.

## 1. Executive Summary

F5 delivers a well-organised workers-pool suite (`test/load/`) with binding
spies, a structured measurement report, a frozen contract, and nine named
tests that map cleanly onto the spec's T1–T9. The documentation (spec, plan,
tasks, contract) is unusually thorough and faithful to §13.5/§13.6.

The implementation, however, does not measure what the architecture requires
in three fundamental ways:

1. **There is no concurrency.** The "load at target concurrency N=20" run
   executes the 20 requests strictly sequentially, so T1's "guard p95 under
   concurrency" measures single-threaded latency.
2. **The harness does not drive the real request path.** It hand-assembles
   `runAdmission` → journal writes → `FakeAdapter` → `creditUsage`, bypassing
   the Worker's fetch entry, identity, context validation, prompt composition,
   and pre-flight — and "guard p95" is timed around `runAdmission` alone,
   despite the frozen contract requiring §6.1 stages 1–10.
3. **DO throughput per installation is not measured.** The report field is a
   duplicate of DO-requests-per-request (always 2), and every request uses a
   *different* installation, so per-installation Durable Object throughput and
   contention are unobservable; T5's assertion is tautological.

Additionally, the suite is not wired into CI: no job in
`.github/workflows/ci.yml` runs any ai-platform test suite, so the FR-002 /
contract §2.2 "runs before each delivery checkpoint / joins CI permanently"
gate is manual-only. CP5 ("operational honesty") is therefore satisfied on
paper by a suite whose three headline measurements do not reflect reality —
which is itself an operational-honesty problem.

## 2. Critical Issues

- **(Critical) No concurrency is generated — T1/FR-003 do not measure "p95
  under concurrency" (§13.5 Load and cost tests row; delivery-plan Done
  when).** `runLoadHappyPath` runs the 20 prepared requests in a sequential
  `for ... await` loop (`ai-platform/test/load/happy-path.ts:502-514`). The
  only `Promise.all` is in fixture *preparation*
  (`happy-path.ts:478-482`). At no point are two requests in flight
  simultaneously, so guard p95 is measured with zero contention. The test then
  asserts `report.concurrency === CONCURRENCY_FIXTURE`
  (`load-and-cost.test.ts:98-99`), but that field merely echoes the fixture
  constant passed into `buildMeasurementReport`
  (`measurement-report.ts:47-57`) — it is self-referential and proves nothing
  about actual concurrency.

- **(Critical) Assertions do not instrument the real request path — the "one
  R2 Class A / two DO trips" proof covers a test-only assembly (§13.6,
  §13.6.1).** The happy path is composed by hand in the test
  (`happy-path.ts:386-465`) from `runAdmission`, `createRequestRow`,
  `FakeAdapter.invoke`, `recordTerminalState`, `writePostResponseDetail`, and
  `creditUsage`. None of these composition functions is called from any
  production module in `ai-platform/src/` — `runAdmission`
  (`src/admission/index.ts:289`), `creditUsage` (`src/credit/index.ts:137`),
  `createRequestRow` and `writePostResponseDetail`
  (`src/journal/index.ts:176,352`) have only test callers; the real Worker
  entry (`src/worker.ts` → `handleAdapterRequest`, `src/adapter.ts:297`) never
  touches them. A regression adding a second R2 object or a third DO round
  trip in the actual pipeline would leave this suite green.

- **(Critical) "Guard p95" is timed around admission only, not the guard
  stages the contract freezes (contracts/load-and-cost-tests.md §2.3: "p95 of
  stages that constitute the guard (architecture §6.1 stages 1–10)").**
  `guardLatencyMs` is `performance.now()` bracketing only
  `admission.runAdmission` (`happy-path.ts:399-406`). Protocol adaptation,
  identity verification, entitlement/rate checks beyond admission, capability
  resolution, context validation, prompt composition, and the §13.6.2
  pre-flight are all excluded from the measurement.

- **(Critical) `do_throughput_per_installation` is neither a throughput nor
  per-installation — T5 is vacuous (§13.5; FR-007/SC-005).** The field is
  computed with the identical formula as `durable_object_requests_per_request`
  (`measurement-report.ts:53-54`: `doFetchesTotal / requestCount`), has no time
  dimension, and is therefore always exactly 2. Worse, `prepareRequest` mints
  a **new installation per request** (`happy-path.ts:377`), so 20 requests hit
  20 different Durable Object instances once each — per-installation DO
  throughput and single-DO serialization/contention cannot be observed. T5
  asserts only `> 0` (`load-and-cost.test.ts:129-134`), which is tautological.

- **(High) The checkpoint gate is not wired into CI (FR-002; contract §2.2
  "Permanent join"; §13.5 How "Before each delivery checkpoint").**
  `test:load` exists (`ai-platform/package.json:15`) and the file is included
  in the workers pool (`vitest.workers.config.ts:21`), but
  `.github/workflows/ci.yml` contains only `frontend-quality` and
  `ai-platform-eval-golden` jobs — no job runs `npm test`, the workers-pool
  suite, or `test:load`. The load layer runs only when someone invokes it
  manually, so "before each delivery checkpoint" is unenforced.

## 3. Bugs

- **(High) Silent warm-up admissions corrupt the measured scenario
  (`happy-path.ts:483-496`).** Before counters are reset, the harness runs a
  full extra admission for each of the 20 requests and discards every result —
  no `assertAdmitted`, no error check. These admissions consume 20 quota units
  against the same entitlement used by the measured run and mutate DO state
  (ephemeral tallies, idempotency keys). If a warm-up admission fails, the
  suite proceeds obliviously. The loop appears to exist only to "warm" the DO,
  but it doubles the scenario's DO traffic and makes quota state depend on
  test ordering.

- **(Medium) "Exactly one/two per request" is asserted only as an average
  (§13.6).** `r2_class_a_ops_per_request` and
  `durable_object_requests_per_request` are `total / requestCount`
  (`measurement-report.ts:51-52`). A hypothetical request performing 2 R2 puts
  while another performs 0 yields average 1.0 and total 20, passing T2 and T6
  (`load-and-cost.test.ts:105-110, 137-143`). The architecture's contract is
  per-request ("**One payload envelope per request**", "**Two round trips per
  request**"), not per-run-average.

- **(Medium) D1 write spy counts statements prepared, not writes executed,
  and only one table (§13.6 D1 writes row).** `createD1Spy` increments on
  `prepare("insert into ai_request…")` (`binding-spies.ts:36-42`): a prepared-
  but-never-run statement counts, and the hot-path `UPDATE` from
  `recordTerminalState` (`happy-path.ts:444`) plus any other metered D1 write
  are invisible. `d1_hot_path_writes_per_request` therefore undercounts actual
  metered D1 writes on the hot path.

- **(Medium) R2 Class A spy only intercepts `put` (§13.6 R2 Class A row).**
  `createR2Spy` wraps only `put` (`binding-spies.ts:61-69`). R2 Class A
  operations also include `list` and multipart create/upload/complete; a
  pipeline regression introducing a per-request `list` would not be counted.

- **(Low) Naive SQL splitting in the schema loader
  (`load-and-cost.test.ts:31-41`).** `applyPlatformSchema` strips `--`
  comments via regex and splits on `;`. This works for today's migration but
  breaks on future migrations containing triggers/procedures or semicolons
  inside string literals — a latent, order-dependent test-harness bug.

- **(Low) Module-level mutable counters contradict the T8 spirit
  (`happy-path.ts:105-107`).** `jtiCounter`, `idempotencyKeyCounter`, and
  `requestReferenceCounter` are module-scope mutable `let`s reset per run.
  They are in-test (not per-request server) state, so the prohibition is not
  violated, but T8's own regexes (below) are designed to catch exactly this
  class of thing and miss it.

- **(Low) D1 spy spread drops prototype methods (`binding-spies.ts:34-35`).**
  `{...realDb}` copies own enumerable properties only; `exec`, `dump`,
  `withSession` are lost. Any future harness or pipeline code calling them
  through the spy fails with a TypeError at test time.

## 4. Architectural Deviations

- **(Critical) §13.5 "Guard latency under concurrency"** — not implemented;
  see Critical Issues (sequential loop).
- **(High) Contract §2.3 / §6.1 stages 1–10 as the guard measurement
  boundary** — implemented as admission-only timing; see Critical Issues.
- **(High) §13.5 How ("Before each delivery checkpoint") / contract §2.2
  ("joins CI permanently") / FR-002** — no CI job runs the suite; the gate is
  manual-only. The plan (`plan.md` Sequencing step 6) claims `test:load` is
  "the checkpoint gate", but nothing invokes it automatically.
- **(Medium) §13.5 "DO throughput per installation"** — the metric and fixture
  design (one request per installation, no time dimension) cannot express the
  architectural quantity; see Critical Issues.
- **(Low) "Tens of milliseconds" encoded as `p95 < 100 ms`
  (`measurement-report.ts:6`; contract §4.2; spec Clarification Q3).**
  Strictly, "tens of milliseconds" suggests < ~90 ms; 100 ms is a borderline
  reading. It is disclosed as an implementation choice and frozen in the
  contract, so this is a documentation-level note rather than a violation.
- **Architecture-vs-Speckit mismatches:** none found. Spec, plan, tasks, and
  contract cite §13.5/§13.6/§13.6.1 accurately (one R2 envelope, two DO trips,
  D1 one-row-hot-path, measured-not-ceilinged headroom). The deviations above
  are implementation-vs-architecture and implementation-vs-own-contract, not
  Speckit-vs-architecture.

## 5. Missing or Weak Tests

- **(Critical) Missing: any test that generates actual concurrency.** No
  `Promise.all`/worker-pool over in-flight requests exists anywhere in the
  suite; T1's required case ("Guard p95 … at target concurrency") is
  uncovered in substance.
- **(Critical) Missing: measurement of Durable Object throughput *per
  installation*.** No test drives multiple concurrent requests against a
  single installation's DO, so the §13.5 metric and the corresponding
  delivery-plan case are uncovered.
- **(High) Missing: any test exercising the real Worker entry under load.**
  No `SELF.fetch`/`handleAdapterRequest`-level request is made; the load path
  is a private composition. The delivery-plan case "exactly one R2 Class A
  operation and two Durable Object requests per request under load" is covered
  only for the hand-built sequence.
- **(Medium) T4 is thin (`load-and-cost.test.ts:121-126`).** It asserts only
  that `d1_hot_path_writes_per_request` is finite and > 0; given the spy
  undercounts (Bugs), the "headroom measured" case rests on a number that is
  neither complete nor compared against anything (e.g. the §13.6
  "one row per request on the hot path" shape is never verified — a value of
  5 would pass).
- **(Medium) T8 is stringly and partially trivial
  (`load-and-cost.test.ts:155-163`).** `LOAD_ROOT.includes("src") === false`
  is true by construction; the `new Map(`/`globalThis.` regexes on
  `happy-path.ts` source miss the module-level `let` counters that actually
  exist and cannot generalise to other state forms. It cannot prove "no
  per-request server-side state".
- **(Low) T9 checks locations, not content
  (`load-and-cost.test.ts:166-179`).** It asserts no `.dart` files under
  `test/load/` and no `frontend/lib/load` directory; it never scans for
  prompt/provider/model strings and would not catch such strings added by
  this slice elsewhere in `frontend/`. The real R-12 protection already lives
  in the CI architecture guard (`.github/workflows/ci.yml:32-56`), making T9
  redundant as well as weak.
- **(Low) No negative-path coverage under load** (e.g. quota-exhausted
  admissions at concurrency, verifying still-zero R2 puts and exactly one DO
  trip on rejection). The spec scopes F5 to the happy path, so this is a
  suggestion, not a gap against T1–T9.

## 6. Recommended Improvements

1. **Generate real concurrency (Critical).** Drive the 20 requests with
   `Promise.all` (or a bounded worker pool) so requests are genuinely in
   flight together; record wall-clock duration and assert it is
   substantially below the sequential sum as a sanity check that concurrency
   happened, rather than echoing `CONCURRENCY_FIXTURE` into the report.
2. **Load the real request path (Critical).** Prefer `SELF.fetch` (workers-
   pool) against `src/worker.ts` with signed test tokens, or extract the
   pipeline composition into a production module that both the Worker and the
   harness call, so the R2/DO/D1 spies observe the same code clinics run.
3. **Time the whole guard (High).** Bracket §6.1 stages 1–10 (protocol
   adapter → identity → admission → capability resolution → context
   validation → prompt composition → §13.6.2 pre-flight), or publish
   per-stage timings in the report so "guard p95" is auditable against
   contract §2.3.
4. **Fix the DO throughput metric (Critical).** Pin a meaningful share of the
   N requests to one installation, give `do_throughput_per_installation` a
   time dimension (DO requests per second per installation, or settle
   latency under contention), and stop duplicating the per-request formula.
5. **Assert per-request maxima, not averages (Medium).** Track R2 put keys
   and DO fetches grouped per request (the spy already records `putKeys`;
   extend it to tag by request) and assert `max === 1` / `max === 2`.
6. **Strengthen the spies (Medium).** Count D1 writes at `run()`/`batch()`
   execution time, include `UPDATE`/`INSERT` across hot-path tables, and
   intercept `list`/multipart in the R2 spy. Construct the D1 spy via
   prototype-preserving wrapping instead of object spread.
7. **Wire the gate into CI (High).** Add an `ai-platform-tests` job to
   `.github/workflows/ci.yml` running at least `npm run test:load` (ideally
   the full workers pool), so §13.5's "before each delivery checkpoint" is
   enforced rather than aspirational.
8. **Remove or legitimize the warm-up (High).** Either drop the discarded
   admission loop, or assert each warm-up result and use a separate
   entitlement/installation set so it cannot perturb the measured scenario.
9. **De-duplicate load runs (Low).** Seven of nine tests each re-run the full
   20-request scenario (`load-and-cost.test.ts:74-85` plus per-`describe`
   calls); run once in `beforeAll` and share the report/spies, cutting
   wall-clock time roughly 7×.
10. **Replace T8/T9 stringly checks (Low).** Either point T9 at the existing
    R-12 architecture guard and drop the location checks, and give T8 a
    semantic assertion (e.g. static check that `test/load/` adds no `src/`
    module and no D1/R2/DO writes outside the spied bindings), or accept them
    as placeholders and document their limited evidential value.
