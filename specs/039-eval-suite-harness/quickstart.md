# Quickstart: Eval suite harness and first capability eval (F1)

Slice F1 freezes the capability eval harness (A9): golden cases for `clinic.visit_summary` run in CI against recorded provider fixtures on the current pinned prompt, a deliberately worse prompt fails the gate, each run writes a JSON score report, and a scheduled workflow exercises pinned model targets via the live-smoke Vitest entry.

**Scope rule:** This quickstart documents **this slice only** — F1 files, tests, and workflows.

## 1. Architecture context

- **Delivery plan row F1** ([`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md) §3.7): eval suite harness and first capability eval after D1 and D5.
- **Architecture sections implemented** ([`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md)):
  - §13.5 Capability evals (A9) — golden cases against recorded fixtures in CI; smaller live smoke on schedule against pinned models.
- **Spec delivered** ([`spec.md`](spec.md)): CI-gated golden suite per capability, deliberately regressed prompt blocks CI, per-run JSON score recording, scheduled live smoke against pinned `model_id` values, recorded-fixture goldens (no permanent live egress).
- **Plan scoped** ([`plan.md`](plan.md)): harness under `ai-platform/test/eval/` only (no `src/eval/`); first capability `clinic.visit_summary`; frozen contract in `contracts/capability-eval-harness.md`; CI golden gate and scheduled workflow.

## 2. What was implemented

- `ai-platform/test/eval/harness.ts` — runner/scorer: per-capability cases, D1 compose + D5 fixture-backed adapter invoke, quality + schema scoring, current vs deliberately regressed prompt builds.
- `ai-platform/test/eval/score-report.ts` — JSON score-report writer (per-case quality + schema pass/fail; no numeric cutoff).
- `ai-platform/test/eval/clinic.visit_summary/` — first-capability cases, fixture bindings, and golden expectations.
- `ai-platform/test/eval/prompts/clinic.visit_summary.worse/` — checked-in deliberately worse prompt artifact for T2.
- `ai-platform/test/eval/reports/` — per-run score report output directory (runtime JSON gitignored).
- `ai-platform/test/eval/golden.test.ts`, `live-smoke.test.ts`, `prohibitions.test.ts` — named tests T1–T8.
- `.github/workflows/ci.yml` — `ai-platform-eval-golden` job gates CI on golden + prohibitions entries.
- `.github/workflows/ai-platform-eval-live-smoke.yml` — scheduled live-smoke workflow.
- Frozen contract: [`contracts/capability-eval-harness.md`](contracts/capability-eval-harness.md).

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/test/eval/harness.ts` | Golden runner, fixture replay, scoring, live-smoke model targets |
| `ai-platform/test/eval/score-report.ts` | JSON score-report shape and writer |
| `ai-platform/test/eval/clinic.visit_summary/cases/` | First-capability golden case inputs |
| `ai-platform/test/eval/clinic.visit_summary/fixtures/` | Capability-scoped recorded provider fixture bindings |
| `ai-platform/test/eval/clinic.visit_summary/expectations/` | Per-case quality + schema expectations |
| `ai-platform/test/eval/prompts/clinic.visit_summary.worse/` | Deliberately worse prompt artifact (T2) |
| `ai-platform/test/eval/golden.test.ts` | T1, T2, T3, T5, T6 |
| `ai-platform/test/eval/live-smoke.test.ts` | T4 |
| `ai-platform/test/eval/prohibitions.test.ts` | T7, T8 |
| `.github/workflows/ci.yml` | CI golden-eval job |
| `.github/workflows/ai-platform-eval-live-smoke.yml` | Scheduled live-smoke workflow |
| `specs/039-eval-suite-harness/contracts/capability-eval-harness.md` | Frozen harness gate, regression gate, score report |

## 4. Prerequisites

From the repository root, first time only:

```bash
cd ai-platform
npm install
```

Golden and prohibitions tests are CPU-only (recorded fixtures, injectable transport). Live-smoke tests assert pinned model targeting and workflow schedule without requiring live provider credentials.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/eval/golden.test.ts test/eval/live-smoke.test.ts test/eval/prohibitions.test.ts
```

Expected: **9 passing tests** for this slice only (5 in `golden.test.ts`, 2 in `live-smoke.test.ts`, 2 in `prohibitions.test.ts`).

To run a subset by named case:

```bash
npx vitest run test/eval/golden.test.ts -t "golden_set_passes_on_current_prompt"
```

## 6. Inspect the changes

Read the frozen contract:

```bash
cat specs/039-eval-suite-harness/contracts/capability-eval-harness.md
```

Open the harness and a score report after a golden run:

```bash
less ai-platform/test/eval/harness.ts
ls ai-platform/test/eval/reports/
```

Inspect CI and scheduled workflow entries:

```bash
grep -A20 ai-platform-eval-golden .github/workflows/ci.yml
cat .github/workflows/ai-platform-eval-live-smoke.yml
```
