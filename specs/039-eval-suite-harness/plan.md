# Implementation Plan: Eval suite harness and first capability eval

**Branch**: `ai/039-f1-eval-suite-harness` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/039-eval-suite-harness/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Slice F1 freezes the prompt/capability evaluation harness (A9 / §13.5): golden cases for the first capability (`clinic.visit_summary`) run in CI against recorded provider fixtures and must pass on the current pinned prompt; a deliberately regressed prompt fails and blocks the change; each run writes a JSON score report; and a smaller scheduled live-smoke Vitest entry runs against pinned model versions. F1 sits in band F after D1 and D5 (its `Needs`), unblocks D7's deferred capability-eval clause and H4/J3 consumers of this harness, and with D7 forms CP4.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers / Node Vitest harness under `ai-platform/`, `engines.node` `>=22` as declared in `ai-platform/package.json`). No new language or runtime version is introduced.

**Primary Dependencies**: The existing `ai-platform/` Worker tree (Vitest ~3.2, Wrangler). Harness lives under `ai-platform/test/eval/` only — no `src/eval/` module (Clarification Q1). Golden cases bind to D1 prompt artifacts/composer and D5 recorded DeepSeek fixtures behind the D2 provider port. Live smoke uses the existing adapter/routing path and pinned `model_id` values from the platform routing-policy document (never floating aliases). Scheduled live smoke is a GitHub Actions scheduled workflow invoking the same Vitest harness entry (Clarification Q3). No new external package is required beyond the existing Vitest stack.

**Storage**: None at request time and no new D1 table. Per-run scores are a JSON score report written under `ai-platform/test/eval/` (quality + schema scores per case); CI/smoke uploads or retains that artifact (Clarification Q2). Prompt artifacts remain immutable Worker-deployed assets (Consumes D1). The deliberately worse prompt for T2 is a checked-in artifact under `ai-platform/test/eval/`, separate from production pinned prompts (Clarification Q4).

**Testing**: Vitest (`npx vitest run`) at the §13.5 **Capability evals (A9)** layer / delivery plan §3.11.6 row F1 ("CI"). Named tests T1–T8 live under `ai-platform/test/eval/`. Goldens use recorded fixtures (no permanent live egress). Live smoke is the smaller scheduled set against pinned models. Pass/fail only — no numeric score cutoff (Clarification Q5; A9 / §13.5).

**Target Platform**: Cloudflare Worker tree under `ai-platform/` plus GitHub Actions CI and a scheduled workflow. No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway CI/scheduled harness. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase. F1 adds no runtime pipeline stage.

**Performance Goals**: None beyond ordinary CI/scheduled job duration. F1 has no request path and introduces no Quota DO round trip, no D1 insert, and no R2 object (§7.5, §13.6; delivery plan §6.4). Platform I/O budgets remain untouched.

**Constraints**: Harness under `test/eval/` only (Clarification Q1). No redefinition of D1 prompt immutability or D5 adapter/port contracts (FR-010). Golden cases use recorded fixtures, not live egress as the permanent gate (FR-009). Live smoke targets pinned model versions only (FR-008). Scores recorded per run; no numeric cutoff invented (FR-007; Clarification Q5). Per-capability scope — first capability only; no cross-capability aggregate gate (T6). No prompt/provider/model strings in Flutter (T7 / R-12). No per-request server-side state (T8 / §4.4, §9.7). No §5.4 taxonomy codes emitted (spec Edge Cases). No mechanism from §9.14 (R-20).

**Scale/Scope**: One first capability under eval (`clinic.visit_summary` — D1 fixture capability / OD-1 recommended default). Zero §4 runtime components modified (see Components Touched). Eight named tests (T1–T8). One Freezes contract. Roughly 16–22 tasks — under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — golden cases in CI plus a small scheduled live smoke set against pinned models keep prompt edits reviewable without a per-clinic eval matrix (spec Constitution Alignment → Clinic Fit; OD-5).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — F1 adds a Vitest harness under `test/eval/`, CI wiring, and one scheduled GitHub Actions workflow; no new deployable, no queue, no eval farm.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — F1 touches only `ai-platform/` (harness + workflows); no `frontend/` or `backend/` code is modified (spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — F1 writes no clinical records and opens no write path into Supabase; scores stay as a JSON artifact under `test/eval/` (Clarification Q2).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — F1 is CI/scheduled only; prompt text remains in immutable Worker artifacts (Consumes D1); live smoke uses existing adapter credentials/secrets without inventing a new auth path.
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — a golden failure blocks prompt promotion only; clinic workflows remain usable without AI (spec Constitution Alignment → Failure Handling; §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. F1 adds no store, no request-path I/O, and no per-request state; the eval harness is CI/scheduled tooling under `ai-platform/test/eval/` that exercises pinned prompt artifacts and recorded (or scheduled live) adapter paths.

## Project Structure

### Documentation (this feature)

```text
specs/039-eval-suite-harness/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── capability-eval-harness.md
        # Frozen harness gate, CI regression gate, and per-run JSON score report (Freezes)
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`:

1. **Architecture context** — cites delivery plan §3.7 row F1 and `17-ai-platform.md` §13.5 Capability evals (A9) / A9; what the spec delivered; what the plan scoped.
2. **What was implemented** — the `test/eval/` harness, first-capability golden cases, deliberately-worse prompt artifact, JSON score report, CI golden gate, scheduled live-smoke workflow.
3. **Files to review** — this slice's `ai-platform/test/eval/` files, workflow deltas, and frozen contract only.
4. **Run the automated suite** — slice-only `npx vitest run test/eval/...` commands (no full-suite `npm test`, no prior-slice counts).
5. **Inspect the changes** — open the harness entry, golden expectations, score report path, and frozen contract.
6. **Manual validation** — omitted for goldens (CI is the verification path); scheduled smoke may note how to inspect the workflow run / retained score artifact when live credentials are available, without expanding scope beyond this slice.

`data-model.md` is **not** produced — F1 defines no D1 entities (spec Key Entities: not applicable). `research.md` is **not** produced — research is `docs/architecture/17-ai-platform.md`.

`contracts/capability-eval-harness.md` freezes the three Freezes entries so later slices (D7's capability-eval clause, H4 conversation evals, J3 staged rollout) bind to a frozen artifact, not prose: how golden cases gate CI against recorded fixtures, how the deliberately regressed prompt fails the gate, how live smoke is scheduled against pinned models, and the per-run JSON score-report payload (quality + schema, pass/fail only).

### Source Code (repository root)

```text
ai-platform/
└── test/
    └── eval/                                         # NEW — harness root only (Clarification Q1; no src/eval/)
        ├── harness.ts                                # NEW — runner/scorer helpers: load cases, invoke fixture-backed path, score quality+schema, write JSON report (FR-001..FR-007, FR-009)
        ├── score-report.ts                           # NEW — JSON score-report writer/shape (FR-007; Clarification Q2)
        ├── clinic.visit_summary/
        │   ├── cases/                                # NEW — per-case golden expectations (Clarification Q5)
        │   ├── fixtures/                             # NEW — capability-scoped recorded provider fixture bindings for goldens (Consumes D5; FR-002, FR-009)
        │   └── expectations/                         # NEW — structured quality checks / expected-output fixtures (Clarification Q5; FR-004)
        ├── prompts/
        │   └── clinic.visit_summary.worse/           # NEW — deliberately-worse prompt artifact for T2 (Clarification Q4; FR-006)
        ├── reports/                                  # NEW — per-run JSON score reports (gitignore runtime outputs as needed; shape frozen) (FR-007)
        ├── golden.test.ts                            # NEW — T1, T2, T3, T5, T6 (CI goldens)
        ├── live-smoke.test.ts                        # NEW — T4 (scheduled live smoke against pinned models)
        └── prohibitions.test.ts                      # NEW — T7, T8 (inherited prohibitions)

.github/
└── workflows/
    ├── ci.yml                                        # MODIFIED — add ai-platform golden-eval Vitest job/step gated in CI (FR-001, FR-005, FR-006)
    └── ai-platform-eval-live-smoke.yml               # NEW — scheduled workflow running live-smoke Vitest entry (Clarification Q3; FR-003, FR-008)
```

No `frontend/` or `backend/` tree is shown — F1 touches neither. No `ai-platform/src/` module is added (Clarification Q1). D1 prompt registry/composer and D5 DeepSeek adapter + fixtures are **consumed unchanged** and are not listed as this slice's source tree.

**Structure Decision**: F1 extends the `ai-platform/test/` tree with an `eval/` harness (delivery plan §7.1; Clarification Q1), siblings to existing adapter and pipeline tests. CI and scheduled smoke both invoke that Node/Vitest entry. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From D1 — prompt registry contract (immutable prompt artifacts deployed with the Worker, pinned by the capability manifest; a prompt change is a new capability *build*; composer produces the canonical request the capability under eval uses) | `ai-platform/src/prompt/registry.ts` (`resolveArtifact`, `resolvePromptVersion`, `verifyBuildPins`); `ai-platform/src/prompt/composer.ts` (`composeRequest`, `ComposeRequestResult`); production artifacts under `ai-platform/prompts/clinic.visit_summary/`; frozen in `specs/028-prompt-registry-composer/contracts/composer-output.md`. F1 evaluates against those pinned artifacts and does not store prompt text in D1, invent an editable-prompt path, or redefine composition |
| From D5 — first real provider adapter and its recorded-fixture adapter suite behind the D2 provider port (wire mapping, stream normalization, usage extraction, error classification proven against recorded fixtures) | `ai-platform/src/provider/deepseek.ts` (`DeepSeekAdapter`); `ai-platform/src/provider/port.ts` (`ProviderPort`); recorded fixtures under `ai-platform/test/fixtures/deepseek/`; frozen in `specs/032-first-real-provider-adapter/contracts/first-real-provider-adapter.md`. F1's golden cases run against recorded provider fixtures; F1 does not redefine the adapter port, invent a second real adapter, or replace D5's fixture-suite duties. Live smoke exercises pinned model versions through the existing adapter/routing path without changing adapter ownership |

Every **Consumes** entry binds to an existing implementation. None requires modification (stop condition 2 not triggered). Pinned `model_id` values for live smoke are read from the existing routing-policy document (`ai-platform/control/routing-policy/platform-default/1.json`) — F1 does not invent pin syntax and does not modify D2's router (spec Edge Cases / Assumptions).

## Components Touched

F1 modifies **no** §4 runtime component of `17-ai-platform.md`. Implements cites **§13.5** and **A9** (Capability evals) — a testing-strategy layer, not a Worker pipeline stage. Clarification Q1 places the harness under `ai-platform/test/eval/` only with no `src/eval/` module. §4.3.6 mentions CI evals (A9) as the reason prompts are immutable assets; F1 does not modify the prompt composer/registry — it evaluates against them. §4.3.8 (adapters) and §4.3.7 (router) are **consumed**, not modified.

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.3.6 Prompt composer and prompt registry | **Not touched** | Consumed via D1 binding; evals exercise pinned artifacts |
| §4.3.8 Provider adapters and egress | **Not touched** | Consumed via D5 binding; goldens use recorded fixtures |
| §4.3.7 Provider router and policy engine | **Not touched** | Live smoke reads existing pinned `model_id` values; no router rewrite |
| All other §4.x | **Not touched** | Out of scope |

This matches the E1 precedent (CI architectural component outside §4). Stop condition 5 (multi-component without reason) is not triggered.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/test/eval/harness.ts` | FR-001, FR-002, FR-004, FR-005, FR-006, FR-009, FR-010 (runner: per-capability golden cases against recorded fixtures; quality + schema scoring; current vs worse prompt builds) |
| `ai-platform/test/eval/score-report.ts` | FR-007 (JSON score report per run under `test/eval/`; Clarification Q2) |
| `ai-platform/test/eval/clinic.visit_summary/cases/**` | FR-002, FR-004, FR-005 (first-capability golden case set; Clarification Q5) |
| `ai-platform/test/eval/clinic.visit_summary/fixtures/**` | FR-002, FR-009 (bindings to recorded provider fixtures; Consumes D5) |
| `ai-platform/test/eval/clinic.visit_summary/expectations/**` | FR-004 (structured quality checks / expected-output fixtures + schema validation; Clarification Q5) |
| `ai-platform/test/eval/prompts/clinic.visit_summary.worse/**` | FR-006 (checked-in deliberately-worse prompt artifact; Clarification Q4) |
| `ai-platform/test/eval/reports/` | FR-007 (score-report output directory under `test/eval/`) |
| `ai-platform/test/eval/golden.test.ts` | T1, T2, T3, T5, T6 (FR-001, FR-002, FR-004–FR-007, FR-009, FR-010) |
| `ai-platform/test/eval/live-smoke.test.ts` | T4 (FR-003, FR-008) |
| `ai-platform/test/eval/prohibitions.test.ts` | T7, T8 (delivery plan §6.4 / R-12; §4.4, §9.7) |
| `.github/workflows/ci.yml` | FR-001, FR-005, FR-006 (CI golden gate permanently joins CI; delivery plan §3.10) |
| `.github/workflows/ai-platform-eval-live-smoke.yml` | FR-003, FR-008 (scheduled live-smoke Vitest; Clarification Q3) |
| `specs/039-eval-suite-harness/contracts/capability-eval-harness.md` | Freezes → capability eval harness; CI regression gate; per-run score recording |
| `specs/039-eval-suite-harness/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced. Consumed D1/D5 modules are not modified.

## Test Layout

Per the architecture's testing strategy (§13.5 Capability evals (A9) — golden cases against fixtures in CI; small live smoke on schedule against pinned models) and delivery plan §3.11.6 row F1:

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `golden_set_passes_on_current_prompt` | Capability evals (A9) / CI | `ai-platform/test/eval/golden.test.ts` |
| T2 `deliberately_regressed_prompt_fails` | Capability evals (A9) / CI | `ai-platform/test/eval/golden.test.ts` |
| T3 `scores_recorded_per_run` | Capability evals (A9) / CI | `ai-platform/test/eval/golden.test.ts` |
| T4 `scheduled_live_smoke_against_pinned_models` | Capability evals (A9) / CI (scheduled) | `ai-platform/test/eval/live-smoke.test.ts` + `.github/workflows/ai-platform-eval-live-smoke.yml` |
| T5 `golden_cases_use_recorded_fixtures` | Capability evals (A9) / CI | `ai-platform/test/eval/golden.test.ts` |
| T6 `evals_are_per_capability` | Capability evals (A9) / CI | `ai-platform/test/eval/golden.test.ts` |
| T7 `no_prompt_text_in_flutter_client` | Capability evals (A9) / CI (inherited prohibition) | `ai-platform/test/eval/prohibitions.test.ts` |
| T8 `harness_holds_no_per_request_server_state` | Capability evals (A9) / CI (inherited prohibition) | `ai-platform/test/eval/prohibitions.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). F1 emits **no** §5.4 taxonomy codes — pass/fail of goldens and completion of scheduled smoke are build/schedule outcomes (spec Test plan coverage note). T2 expects failure when the golden set is run against the checked-in worse prompt artifact (Clarification Q4), not against the production prompt. T4 asserts the smoke entry targets pinned `model_id` values from routing policy (Clarification Q3). T5 spies/asserts that golden execution uses recorded fixtures rather than live egress. T7 asserts this slice introduces no Flutter client files carrying prompt/provider/model strings. T8 asserts the harness introduces no per-request server-side state.

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/capability-eval-harness.md` constrains the harness gate, regression gate, smoke schedule, and JSON score-report shape so D7/H4/J3 bind to a frozen artifact (delivery plan DP-4).
2. **Harness + score-report helpers + first-capability cases/expectations/fixture bindings.** Land `harness.ts`, `score-report.ts`, and `clinic.visit_summary/` case/expectation/fixture trees so T1/T3/T5/T6 have something to drive (FR-001, FR-002, FR-004, FR-007, FR-009; Clarifications Q1, Q2, Q5).
3. **Golden Vitest entry + T1, T3, T5, T6.** Current pinned prompt passes goldens; scores written; fixtures proven; per-capability scope locked.
4. **Deliberately-worse prompt artifact + T2.** Checked-in worse build under `test/eval/prompts/`; golden set against that build expects failure and blocks the change (Clarification Q4; FR-006).
5. **Live-smoke Vitest entry + scheduled workflow + T4.** Smoke entry asserts pinned models; GitHub Actions schedule invokes it (Clarification Q3; FR-003, FR-008).
6. **Prohibitions + T7, T8.** Inherited R-12 / no per-request state proofs.
7. **CI wiring.** Add the ai-platform golden-eval job/step to `.github/workflows/ci.yml` so the golden set permanently gates CI (FR-001; delivery plan §3.10).
8. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
