# Implementation Plan: Load and cost tests

**Branch**: `ai/043-f5-load-and-cost-tests` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/043-load-and-cost-tests/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Slice F5 freezes the §13.5 load and cost test layer and the under-load §13.6 / §13.6.1 metered-footprint proof: under workers-pool Miniflare load at target concurrency, guard p95 stays within tens of milliseconds; each request performs exactly one R2 Class A operation and exactly two Durable Object requests (admission + credit); and D1 write headroom and Durable Object throughput per installation are measured via a structured in-test report with no invented ceilings. F5 sits in band F after D7 (its `Needs`); completing it satisfies checkpoint **CP5**.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers / Vitest workers-pool under `ai-platform/`, `engines.node` `>=22` as declared in `ai-platform/package.json`). No new language or runtime version is introduced.

**Primary Dependencies**: Existing `ai-platform/` Worker tree — `@cloudflare/vitest-pool-workers` / Miniflare with real D1, R2, and Quota DO (`DO` → `GatewayObject`) bindings via `vitest.workers.config.ts` and Wrangler development env; Vitest ~3.2. Counting spies wrap those bindings (Clarification Q1). Happy-path under load drives production `src/pipeline` (`runGuard` stages 1–10 + `settleHappyPath` with D2's **fake** provider) under a bounded pool on one shared installation (Clarification Q2 / 2026-08-05) — no live provider egress. No new external package.

**Storage**: No new D1 entity, migration, or R2 layout. The suite exercises existing hot-path D1 writes, the existing one-envelope R2 `PutObject`, and existing Quota DO admission/credit RPCs under load. Measurement evidence is a structured **in-test** report (finite values, no ceilings for D1 headroom / DO throughput — Clarification Q4), not a second metrics store.

**Testing**: Vitest workers-pool (`npx vitest run --config vitest.workers.config.ts`). Named tests T1–T9 are the §13.5 **Load and cost tests** layer / delivery plan §3.11.6 row F5. Dedicated npm script `test:load` is the checkpoint gate; `.github/workflows/ci.yml` job `ai-platform-tests` runs it permanently (Clarification Q4 / 2026-08-05; FR-002). Concurrency fixture `N=20` on one shared installation with pool `Math.min(20, 16)`; production design target `GUARD_P95_PRODUCTION_TARGET_MS = 100`; workers-pool Miniflare ceiling `GUARD_P95_CEILING_MS = 2000` (Clarification Q3 / 2026-08-05). Tests share one `beforeAll` load run.

**Target Platform**: Cloudflare Worker tree under `ai-platform/` (workers-pool Miniflare). No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway load/cost suite. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase. F5 adds a thin production pipeline composer (`src/pipeline`) shared by the harness; it does not add a `src/load/` module or a new HTTP orchestrator.

**Performance Goals**: Guard p95 under the concurrency fixture is measured over full `runGuard` (stages 1–10). Production design target remains 100 ms; workers-pool Miniflare fixture ceiling is 2000 ms because a single sequential Miniflare guard is already ~300–400 ms (Clarification Q3 / 2026-08-05). Under load, preserve platform I/O budgets: one R2 Class A and two DO trips per request (§13.6; §13.6.1; delivery plan §6.4). D1 headroom and DO throughput (fetches/sec on the pinned installation) are measured, not ceiling-gated here (FR-006, FR-007).

**Constraints**: Workers-pool Miniflare + binding spies only (Clarification Q1). Full happy path via `src/pipeline` with fake provider on one shared installation (Clarification Q2 / 2026-08-05). No rewrite of D7 adapter / fixtures / policy registration (FR-010; Consumes D7). No invented numeric ceilings for D1 headroom or DO throughput (FR-006, FR-007; Edge Cases). No §5.4 taxonomy codes from this suite. No per-request server-side state (T8; §4.4, §9.7). No Flutter prompt/provider/model strings (T9; R-12). No second R2 object or third DO trip (T6, T7; §7.5, §13.6). No §9.14 mechanism (R-20). Pre-flight estimator remains C2 (Out of Scope).

**Scale/Scope**: One load/cost suite under `ai-platform/test/load/` plus thin `src/pipeline` composer. Zero §4 runtime components modified (see Components Touched). Nine named tests (T1–T9). One Freezes contract. Roughly 14–20 tasks — under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — measuring guard p95, D1 headroom, and per-installation DO throughput, and asserting one R2 / two DO under load, keeps the platform inside the §13.6.1 clinic-scale metered footprint without hospital-scale capacity planning (spec Constitution Alignment → Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — F5 adds a Vitest workers-pool load suite and a `test:load` script under the existing Worker; no new deployable, queue, or load farm.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — F5 touches only `ai-platform/` (load tests); no `frontend/` or `backend/` code is modified (spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — F5 writes no clinical records and opens no write path into Supabase; spies measure existing gateway D1/R2/DO behaviour only.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — load exercises installation-scoped Quota DO and existing guard/admission paths without weakening isolation or inventing a second metrics store.
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — a failing load assertion fails the suite / CP5 gate only; clinic workflows continue without AI (spec Constitution Alignment → Failure Handling; §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. F5 adds a thin production composer at `src/pipeline/` (no store, no HTTP orchestrator) and workers-pool tooling under `ai-platform/test/load/` that proves the §13.6.1 metered footprint and CP5 measurement gate; the suite introduces no per-request server-side state.

## Project Structure

### Documentation (this feature)

```text
specs/043-load-and-cost-tests/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── load-and-cost-tests.md
        # Frozen load/cost layer, under-load one-R2 / two-DO proof,
        # CP5 measurement gate, and structured measurement report (Freezes)
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`:

1. **Architecture context** — cites delivery plan §3.7 row F5 and `17-ai-platform.md` §13.5 Load and cost tests / §13.6 / §13.6.1; what the spec delivered; what the plan scoped.
2. **What was implemented** — workers-pool load suite, binding spies, `src/pipeline` composer, fake-provider happy path under bounded-pool concurrency on one shared installation, structured measurement report (production target 100 ms / Miniflare ceiling 2000 ms), `test:load` + CI checkpoint gate, frozen contract.
3. **Files to review** — this slice's `ai-platform/src/pipeline/`, `ai-platform/test/load/` files, `package.json` / vitest / CI config deltas, and frozen contract only.
4. **Run the automated suite** — slice-only `npm run test:load` (workers-pool) / `npx vitest run --config vitest.workers.config.ts test/load/load-and-cost.test.ts` (no full-suite `npm test`, no prior-slice counts).
5. **Inspect the changes** — open the pipeline composer, load entry, measurement-report shape, binding spies, and frozen contract.
6. **Manual validation** — omitted; CI / `test:load` is the verification path (no behaviour beyond the automated suite).

`data-model.md` is **not** produced — F5 defines no D1 entities (spec Key Entities: not applicable). `research.md` is **not** produced — research is `docs/architecture/17-ai-platform.md`.

`contracts/load-and-cost-tests.md` freezes the three Freezes entries so later checkpoints bind to a frozen artifact, not prose: the load and cost test layer (placement, timing, `test:load` + CI gate), the under-load one-R2 / two-DO metered-footprint assertion, the CP5 measurement gate, and the structured in-test measurement report (finite values; no D1/DO ceilings; suite fixture `N=20` / production target 100 ms / Miniflare ceiling 2000 ms).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   └── pipeline/
│       └── index.ts                          # NEW — production runGuard (stages 1–10) + settleHappyPath
├── package.json                              # MODIFIED — add "test:load" workers-pool script (Clarification Q4; FR-002)
├── vitest.config.ts                          # MODIFIED — exclude test/load/** from Node-pool include
├── vitest.workers.config.ts                  # MODIFIED — include test/load/load-and-cost.test.ts (permanent join §3.10)
└── test/
    └── load/                                 # NEW — load/cost suite root only (no src/load/)
        ├── binding-spies.ts                  # NEW — counting spies on D1 / R2 / DO bindings (ALS maxima; Clarification Q1)
        ├── measurement-report.ts             # NEW — structured in-test report + p95 fixtures (Clarification Q3/Q4)
        ├── happy-path.ts                     # NEW — bounded pool + shared installation calling src/pipeline (Clarification Q2 / 2026-08-05)
        └── load-and-cost.test.ts             # NEW — T1–T9 (shared beforeAll load run)
.github/workflows/
└── ci.yml                                    # MODIFIED — ai-platform-tests job runs npm test + test:load
```

No `frontend/` or `backend/` tree is shown — F5 touches neither. Review resolution adds `ai-platform/src/pipeline/` (shared production composition); there is still no `src/load/` module. D7 Gemini adapter / fixtures / policy data, B4 admission/credit / Quota DO, C3 journal / R2 envelope, and D2 `FakeAdapter` are **consumed or exercised unchanged** and are not listed as this slice's source tree beyond the pipeline composer that wires them.

**Structure Decision**: F5 extends the `ai-platform/test/` tree with a `load/` suite on the existing workers-pool Miniflare config (delivery plan §7.1; Clarification Q1), siblings to journal / admission / soft-threshold workers-pool tests, and adds a thin `src/pipeline` composer so the harness and a future Worker orchestrator share one §6.1 composition. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From D7 — second real provider adapter behind the D2 provider port; recorded-fixture suite applied to that provider; registration as a low-priority fallback target by routing-policy data alone with no inference-pipeline change | `ai-platform/src/provider/gemini.ts` (`GeminiAdapter`); `ai-platform/src/provider/wiring.ts`; `ai-platform/test/fixtures/gemini/`; `ai-platform/control/routing-policy/platform-default/1.json`; frozen in `specs/034-second-provider-adapter/contracts/second-provider-adapter.md`. F5 load- and cost-tests the platform **after** that second provider exists (Needs D7 / post-CP4 platform) and does **not** rewrite the adapter, fixture-suite shape, policy registration, or fallback ordering (FR-010). The load happy path uses D2's fake provider (Clarification Q2) and does not invent a second provider or live-egress load path |

Every **Consumes** entry binds to an existing implementation. None requires modification (stop condition 2 not triggered). Adjacent pipeline modules exercised under load (B4 admission/credit / Quota DO, C3 journal / one R2 envelope, D2 `FakeAdapter` in `ai-platform/src/provider/fake.ts`) are composed by `src/pipeline` and driven by the test harness — they are **not** modified and are not Freezes/Consumes rewrites for this slice.

## Components Touched

F5 modifies **no** §4 runtime component of `17-ai-platform.md`. Implements cites **§13.5** and **§13.6** (testing strategy / cost model) — operational concerns, not a new Worker pipeline stage. Review resolution adds a thin production composer at `ai-platform/src/pipeline/` (`runGuard` / `settleHappyPath`) so the load harness and a future Worker orchestrator share one composition; there is still no `src/load/` module. §4.3.3 (quota / admission), §4.3.8 (adapters), and §4.3.11 (journal) are **exercised or consumed**, not modified.

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.3.3 Entitlement, quota, and rate control | **Not touched** | Admission + credit RPCs exercised under load via existing B4 modules; counts asserted, behaviour not rewritten |
| §4.3.8 Provider adapters and egress | **Not touched** | Consumes D7 unchanged; load path uses D2 `FakeAdapter` |
| §4.3.11 Journal writer | **Not touched** | One R2 envelope / hot-path D1 write exercised under load via existing C3 modules; counts/headroom measured, layout not rewritten |
| All other §4.x | **Not touched** | Out of scope |

This matches the F1 / E1 precedent (CI / test-layer slices outside §4). Stop condition 5 (multi-component without reason) is not triggered.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/test/load/binding-spies.ts` | FR-004, FR-005, FR-006, FR-008 (counting spies on R2 Class A, DO fetch, D1 hot-path writes; Clarification Q1) |
| `ai-platform/test/load/measurement-report.ts` | FR-001, FR-006, FR-007, FR-009 (structured in-test measurement report — finite values, no D1/DO ceilings; Clarification Q4) |
| `ai-platform/src/pipeline/index.ts` | FR-001, FR-003, FR-008 (production guard+settle composition used by the load harness; review resolution) |
| `ai-platform/test/load/happy-path.ts` | FR-001, FR-003, FR-008 (full happy path under load via pipeline + bounded pool; Clarification Q2 / 2026-08-05) |
| `.github/workflows/ci.yml` | FR-002 (`ai-platform-tests` job runs `test:load`; review resolution) |
| `ai-platform/test/load/load-and-cost.test.ts` | T1–T9 (FR-001–FR-010; suite fixtures Clarification Q3) |
| `ai-platform/package.json` | FR-002, FR-009 (`test:load` workers-pool script as checkpoint gate; Clarification Q4) |
| `ai-platform/vitest.workers.config.ts` | FR-001, FR-002 (include load suite in workers-pool; permanent join §3.10) |
| `ai-platform/vitest.config.ts` | FR-001 (exclude `test/load/**` from Node-pool so load tests run only on workers-pool bindings) |
| `specs/043-load-and-cost-tests/contracts/load-and-cost-tests.md` | Freezes → load and cost test layer; under-load metered-footprint assertion; CP5 measurement gate |
| `specs/043-load-and-cost-tests/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced. Consumed D7 modules and exercised B4/C3/D2 modules are not modified.

## Test Layout

Per the architecture's testing strategy (§13.5 Load and cost tests — guard latency under concurrency; D1 write headroom; DO throughput per installation; before each delivery checkpoint) and delivery plan §3.11.6 row F5:

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `guard_p95_within_tens_of_ms_at_target_concurrency` | Load and cost tests | `ai-platform/test/load/load-and-cost.test.ts` |
| T2 `exactly_one_r2_class_a_per_request_under_load` | Load and cost tests | `ai-platform/test/load/load-and-cost.test.ts` |
| T3 `exactly_two_durable_object_requests_per_request_under_load` | Load and cost tests | `ai-platform/test/load/load-and-cost.test.ts` |
| T4 `d1_write_headroom_measured` | Load and cost tests | `ai-platform/test/load/load-and-cost.test.ts` |
| T5 `do_throughput_per_installation_measured` | Load and cost tests | `ai-platform/test/load/load-and-cost.test.ts` |
| T6 `no_second_r2_object_per_request` | Load and cost tests (inherited prohibition) | `ai-platform/test/load/load-and-cost.test.ts` |
| T7 `no_second_quota_do_round_trip_beyond_two` | Load and cost tests (inherited prohibition) | `ai-platform/test/load/load-and-cost.test.ts` |
| T8 `load_suite_introduces_no_per_request_server_state` | Load and cost tests (inherited prohibition) | `ai-platform/test/load/load-and-cost.test.ts` |
| T9 `no_prompt_provider_model_in_flutter_from_load_suite` | Load and cost tests (inherited prohibition) | `ai-platform/test/load/load-and-cost.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). F5 emits **no** §5.4 taxonomy codes — pass/fail of p95 / one-R2 / two-DO and completion of measurements are suite outcomes (spec Test plan coverage note).

Fixture / assertion notes (follow Clarifications; do not promote into FR prose):

- T1: concurrency fixture `N=20` on one shared installation; bounded pool `Math.min(20, 16)`; time full `runGuard` (stages 1–10); production target 100 ms / Miniflare ceiling 2000 ms; wall-clock overlap proves concurrency (Clarification Q3 / 2026-08-05).
- T2 / T6: spy counts R2 Class A (put/list/multipart) — exactly one per request (average and max); no second object.
- T3 / T7: spy counts Quota DO fetches — exactly two per request (admission + credit; average and max); no third trip.
- T4 / T5: structured measurement report carries finite `d1_hot_path_writes_per_request` (one INSERT) and time-dimensioned `do_throughput_per_installation` with **no** numeric ceilings (Clarification Q4).
- T8: asserts composition lives in `src/pipeline` and the suite introduces no per-request server-side state / no `src/load/`.
- T9: asserts this suite introduces no Flutter client files; R-12 content scan is pointed at the existing CI architecture guard.
- Shared `beforeAll` load run feeds T1–T7; schema loader splits SQL outside string literals.

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/load-and-cost-tests.md` constrains the load layer, under-load one-R2 / two-DO proof, CP5 gate, and measurement-report shape so later checkpoints bind to a frozen artifact (delivery plan DP-4 / §2.3).
2. **Production pipeline composer.** Land `src/pipeline/index.ts` (`runGuard` stages 1–10 + `settleHappyPath`) so the harness and a future Worker orchestrator share one composition (2026-08-05).
3. **Binding spies + measurement report helpers.** Land `binding-spies.ts` and `measurement-report.ts` so T2–T7 / T4–T5 have metering (ALS maxima, D1 run/batch INSERT, R2 Class A coverage) and report shapes including both p95 fixtures (Clarifications Q1, Q3, Q4; FR-004–FR-008).
4. **Happy-path driver under load.** Land `happy-path.ts` calling the pipeline on one shared installation with a bounded worker pool and no warm-up (Clarification Q2 / 2026-08-05; FR-001, FR-008).
5. **Load Vitest entry + T1–T5.** Shared `beforeAll` load run; concurrency / p95 / one-R2 / two-DO / measurement assertions (Clarification Q3; FR-003–FR-007, FR-009).
6. **Inherited prohibitions + T6–T9.** Reinforce no second R2 / no third DO trip / pipeline composition / CI R-12 pointer (delivery plan §6.4).
7. **Workers-pool wiring + `test:load` + CI.** Include the load file in `vitest.workers.config.ts`, exclude it from the Node-pool config, add `package.json` `"test:load"`, and wire `.github/workflows/ci.yml` `ai-platform-tests` (Clarification Q4 / 2026-08-05; FR-002; §3.10).
8. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
