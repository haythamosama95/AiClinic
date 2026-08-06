# Quickstart: Load and cost tests (F5)

F5 adds the §13.5 load and cost test layer: under workers-pool Miniflare, the suite
drives N=20 happy-path requests on **one shared installation** via a bounded pool
(`Math.min(20, CONCURRENCY_LIMIT=16)`), calling production `src/pipeline`
(`runGuard` stages 1–10 + `settleHappyPath`). It asserts finite guard p95 under the
Miniflare ceiling (3000 ms; production design target remains 100 ms), exactly one R2
Class A operation and two Quota DO requests per request (average and max), and emits
a structured in-test measurement report for D1 write headroom and time-dimensioned DO
throughput. The `test:load` npm script — run by CI job `ai-platform-tests` — is the
CP5 checkpoint gate.

## 1. Architecture context

- **Delivery plan** — Band F row F5 in
  [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)
  (Needs: D7; satisfies checkpoint CP5).
- **Architecture** — Implements the testing strategy in
  [`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)
  §13.5 Load and cost tests, §13.6 metered-footprint assertions, and §13.6.1 clinic-scale
  design-shape budget proof.
- **Spec** — [`spec.md`](./spec.md) freezes the load layer, under-load one-R2 / two-DO proof,
  and the CP5 measurement gate (Clarifications Q3 / 2026-08-05 encode the p95 fixtures).
- **Plan** — [`plan.md`](./plan.md) scoped `src/pipeline`, workers-pool binding spies,
  bounded-pool happy path, structured measurement report, Vitest + CI wiring, and nine
  named tests under `ai-platform/test/load/`.

## 2. What was implemented

- Production pipeline composer (`src/pipeline/index.ts`): `runGuard` (§6.1 stages 1–10) +
  `settleHappyPath` (FakeAdapter + credit + one R2 envelope).
- Workers-pool load suite (`test/load/load-and-cost.test.ts`) with nine named cases T1–T9
  sharing one `beforeAll` load run; no warm-up admissions.
- Bounded concurrency on one shared installation; observed in-flight peak reported as
  `concurrency`; DO throughput = pinned-installation DO fetches / wall_clock_seconds.
- Counting spies with AsyncLocalStorage per-request maxima (`binding-spies.ts`): D1
  INSERT at run/batch; R2 Class A put/list/multipart; prototype-preserving D1 spy.
- Structured measurement report with `GUARD_P95_PRODUCTION_TARGET_MS = 100` and
  `GUARD_P95_CEILING_MS = 3000` (`measurement-report.ts`).
- `test:load` workers-pool checkpoint script; CI job `ai-platform-tests` runs
  `npm test` + `npm run test:load`.
- T8 asserts pipeline composition; T9 points R-12 at the existing CI architecture guard.
- Frozen contract [`contracts/load-and-cost-tests.md`](./contracts/load-and-cost-tests.md).

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/pipeline/index.ts` | Production `runGuard` / `settleHappyPath` composition |
| `ai-platform/test/load/load-and-cost.test.ts` | T1–T9 load and inherited prohibition cases |
| `ai-platform/test/load/binding-spies.ts` | Counting spies on D1 / R2 / DO bindings |
| `ai-platform/test/load/measurement-report.ts` | Report shape, p95 fixtures, throughput helper |
| `ai-platform/test/load/happy-path.ts` | Bounded pool + shared installation calling pipeline |
| `ai-platform/package.json` | `test:load` checkpoint gate script |
| `ai-platform/vitest.config.ts` | Excludes `test/load/**` from Node pool |
| `ai-platform/vitest.workers.config.ts` | Includes load suite in workers pool |
| `.github/workflows/ci.yml` | `ai-platform-tests` job runs `test:load` |
| `specs/043-load-and-cost-tests/contracts/load-and-cost-tests.md` | Frozen load layer / CP5 gate contract |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm run test:load
```

Equivalent slice-only command:

```bash
cd ai-platform
npx vitest run --config vitest.workers.config.ts test/load/load-and-cost.test.ts
```

Expected: **9+ passing tests** in `test/load/load-and-cost.test.ts` (T1–T9 plus the
CI-join assertion). What is measured: full `runGuard` p95 under real pool concurrency,
one R2 Class A and two DO trips per request (maxima), D1 hot-path INSERT headroom, and
time-dimensioned DO throughput on the pinned installation.

## 5. Inspect the changes

```bash
cd ai-platform
ls src/pipeline/ test/load/
rg 'runGuard|GUARD_P95|LOAD_POOL|do_throughput|CONCURRENCY_FIXTURE' src/pipeline/ test/load/
cat package.json | rg test:load
rg 'ai-platform-tests|test:load' ../.github/workflows/ci.yml
cat ../specs/043-load-and-cost-tests/contracts/load-and-cost-tests.md
```
