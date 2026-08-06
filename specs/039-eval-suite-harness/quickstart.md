# Quickstart: Eval suite harness and first capability eval (F1)

Slice F1 freezes the capability eval harness (A9): golden cases for `clinic.visit_summary` run in CI against D5 recorded fixtures (`d5_fixture_subdir` → `test/fixtures/deepseek/`) on the current pinned prompt (composition + schema; fixture-output sanity only), a deliberately worse prompt fails the gate, each run writes a JSON score report, and a scheduled workflow invokes live adapter smoke against pinned product/version model IDs (workflow-supplied secrets; `run_kind: "live_smoke"`).

**Scope rule:** This quickstart documents **this slice only** — F1 files, tests, and workflows.

## 1. Architecture context

- **Delivery plan row F1** ([`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.7): eval suite harness and first capability eval after D1 and D5.
- **Architecture sections implemented** ([`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)):
  - §13.5 Capability evals (A9) — golden cases against recorded fixtures in CI; smaller live smoke on schedule against pinned models.
- **Spec delivered** ([`spec.md`](spec.md)): CI-gated golden suite per capability, deliberately regressed prompt blocks CI, per-run JSON score recording, scheduled live smoke against pinned `model_id` values, recorded-fixture goldens (no permanent live egress).
- **Plan scoped** ([`plan.md`](plan.md)): harness under `ai-platform/test/eval/` only (no `src/eval/`); first capability `clinic.visit_summary`; frozen contract in `contracts/capability-eval-harness.md`; CI golden gate and scheduled workflow.

## 2. What was implemented

- `ai-platform/test/eval/harness.ts` — runner/scorer: per-capability cases, D1 compose + D5 fixture-backed adapter invoke (`d5_fixture_subdir` → `test/fixtures/deepseek/`), quality + schema scoring, current vs deliberately regressed prompt builds, `runLiveSmokeSuite` for scheduled live egress.
- `ai-platform/test/eval/score-report.ts` — JSON score-report writer (per-case quality + schema pass/fail; empty suite → fail; no numeric cutoff).
- `ai-platform/test/eval/clinic.visit_summary/` — first-capability cases, D5 fixture bindings, request-system goldens, and golden expectations.
- `ai-platform/test/eval/prompts/clinic.visit_summary.worse/` — checked-in deliberately worse prompt artifact for T2.
- `ai-platform/test/eval/reports/` — per-run score report output directory (runtime JSON gitignored).
- `ai-platform/test/eval/golden.test.ts`, `live-smoke.test.ts`, `scorer.test.ts`, `prohibitions.test.ts` — named tests T1–T8 plus scorer branch coverage.
- `.github/workflows/ci.yml` — `ai-platform-eval-golden` job gates CI on golden + prohibitions entries.
- `.github/workflows/ai-platform-eval-live-smoke.yml` — scheduled live-smoke workflow with provider API secrets.
- Frozen contract: [`contracts/capability-eval-harness.md`](contracts/capability-eval-harness.md).

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/test/eval/harness.ts` | Golden runner, fixture replay, scoring, live-smoke model targets |
| `ai-platform/test/eval/score-report.ts` | JSON score-report shape and writer |
| `ai-platform/test/eval/clinic.visit_summary/cases/` | First-capability golden case inputs |
| `ai-platform/test/eval/clinic.visit_summary/fixtures/` | Capability-scoped bindings (`d5_fixture_subdir` → D5 `test/fixtures/deepseek/`) |
| `ai-platform/test/eval/clinic.visit_summary/expectations/` | Per-case quality + schema expectations |
| `ai-platform/test/eval/prompts/clinic.visit_summary.worse/` | Deliberately worse prompt artifact (T2) |
| `ai-platform/test/eval/golden.test.ts` | T1, T2, T3, T5, T6 |
| `ai-platform/test/eval/live-smoke.test.ts` | T4 (+ live-smoke execution / skip paths) |
| `ai-platform/test/eval/scorer.test.ts` | Scorer branch coverage (§3.10) |
| `ai-platform/test/eval/prohibitions.test.ts` | T7, T8 |
| `.github/workflows/ci.yml` | CI golden-eval job |
| `.github/workflows/ai-platform-eval-live-smoke.yml` | Scheduled live-smoke workflow (provider secrets) |
| `specs/039-eval-suite-harness/contracts/capability-eval-harness.md` | Frozen harness gate, regression gate, score report |

## 4. Prerequisites

From the repository root, first time only:

```bash
cd ai-platform
npm install
```

Golden and prohibitions tests are CPU-only (D5 recorded fixtures, injectable transport). Live-smoke tests exercise `runLiveSmokeSuite` with an injected recorded-live transport in CI; credential-less local runs skip real egress. The scheduled workflow supplies `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` from GitHub Actions secrets for true provider smoke.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/eval/golden.test.ts test/eval/live-smoke.test.ts test/eval/prohibitions.test.ts test/eval/scorer.test.ts
```

Expected: all F1 eval entries green (T1–T8 plus scorer branch coverage and live-smoke execution/skip cases).

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
