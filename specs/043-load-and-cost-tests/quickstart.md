# Quickstart: Load and cost tests (F5)

F5 adds the §13.5 load and cost test layer: under workers-pool Miniflare at concurrency
fixture N=20, the suite drives the full happy path with a fake provider, asserts guard p95
< 100 ms, exactly one R2 Class A operation and two Quota DO requests per request, and
emits a structured in-test measurement report for D1 write headroom and DO throughput per
installation (finite values, no invented ceilings). The `test:load` npm script is the CP5
checkpoint gate.

## 1. Architecture context

- **Delivery plan** — Band F row F5 in
  [`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md)
  (Needs: D7; satisfies checkpoint CP5).
- **Architecture** — Implements the testing strategy in
  [`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md)
  §13.5 Load and cost tests, §13.6 metered-footprint assertions, and §13.6.1 clinic-scale
  design-shape budget proof.
- **Spec** — [`spec.md`](./spec.md) freezes the load layer, under-load one-R2 / two-DO proof,
  and the CP5 measurement gate.
- **Plan** — [`plan.md`](./plan.md) scoped workers-pool binding spies, fake-provider happy-path
  driver, structured measurement report, Vitest wiring, and nine named tests under
  `ai-platform/test/load/`.

## 2. What was implemented

- Workers-pool load suite (`test/load/load-and-cost.test.ts`) with nine named cases T1–T9.
- Counting spies on D1 / R2 / Quota DO bindings (`binding-spies.ts`).
- Fake-provider happy-path driver under concurrency N=20 (`happy-path.ts`).
- Structured in-test measurement report with finite values and no D1/DO ceilings
  (`measurement-report.ts`).
- `test:load` workers-pool checkpoint script in `package.json`.
- Node-pool exclude and workers-pool include for `test/load/**`.
- Frozen contract [`contracts/load-and-cost-tests.md`](./contracts/load-and-cost-tests.md).

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/test/load/load-and-cost.test.ts` | T1–T9 load and inherited prohibition cases |
| `ai-platform/test/load/binding-spies.ts` | Counting spies on D1 / R2 / DO bindings |
| `ai-platform/test/load/measurement-report.ts` | Structured measurement report shape and p95 helper |
| `ai-platform/test/load/happy-path.ts` | Full happy path under load with FakeAdapter |
| `ai-platform/package.json` | `test:load` checkpoint gate script |
| `ai-platform/vitest.config.ts` | Excludes `test/load/**` from Node pool |
| `ai-platform/vitest.workers.config.ts` | Includes load suite in workers pool |
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

Expected: **9 passing tests** in `test/load/load-and-cost.test.ts` (T1–T9).

## 5. Inspect the changes

```bash
cd ai-platform
ls test/load/
rg 'guard_p95|d1_hot_path_writes|do_throughput|CONCURRENCY_FIXTURE' test/load/
cat package.json | rg test:load
cat ../specs/043-load-and-cost-tests/contracts/load-and-cost-tests.md
```
