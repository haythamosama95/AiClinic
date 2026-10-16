# Implementation Plan: Conversation evals

**Branch**: `ai/047-h4-conversation-evals` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/047-conversation-evals/spec.md`

**Note**: Filled in by the `/ai-platform-plan` command. The AI platform variant adds five sections (`## Consumes Binding`, `## Components Touched`, `## Files`, `## Test Layout`, `## Sequencing`) and never produces `research.md`.

## Summary

H4 extends F1's CI-gated A9 eval suite with conversation evals: scripted multi-leg conversations against recorded fixtures for one fixture conversational capability, scored per conversation on the three §13.5 criteria (right keys, permitted set, round-budget convergence). It sits in band H after F1 and H2 so multi-leg scoring binds to the frozen capability-eval harness and H2's allowlist, budget, and dual-output contracts rather than inventing a second gate (delivery plan §3.8, row H4).

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers / Node Vitest harness under `ai-platform/`, `engines.node` `>=22` as declared in `ai-platform/package.json`). No new language or runtime version is introduced.

**Primary Dependencies**: Existing F1 Vitest eval harness under `ai-platform/test/eval/` (Vitest ~3.2) and H2 conversational runtime contracts (validator allowlist / budgets; dual output-shape acceptance). Conversation cases and scoring are a **sibling module** under that tree, invoked by the **same CI gate** (Clarification Q3). Active harness loop advances legs against recorded fixtures and scores the whole conversation at the end (Clarification Q1). One fixture conversational capability (`clinic.chat_assistant`, matching H-band test fixtures) with three scripted cases (Clarification Q2). No new external package.

**Storage**: None at request time and no new D1 table. Per-conversation scores are a JSON score report under `ai-platform/test/eval/` (extends F1 per-run recording without redefining capability quality/schema fields). Scripted fixtures and the fixture capability's declared round budget / permitted set live under the eval tree. No conversation entity and no per-request server-side state (delivery plan §6.4; FR-001–FR-010).

**Testing**: Vitest (`npx vitest run`) at the §13.5 **Conversation evals (A14)** layer / delivery plan §3.11.7 row H4 ("Evals"). Named tests T1–T9 live under `ai-platform/test/eval/` beside F1 capability evals. Pass/fail of the three per-conversation criteria only — no numeric cutoff (spec Assumptions; OD-10). H4 emits **no** §5.4 taxonomy codes.

**Target Platform**: Cloudflare Worker tree under `ai-platform/` plus the existing GitHub Actions CI golden-eval job. No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway CI harness extension. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase. H4 adds no runtime pipeline stage.

**Performance Goals**: None beyond ordinary CI job duration. H4 has no request path and introduces no Quota DO round trip, no D1 insert, and no R2 object (§7.5, §13.6; delivery plan §6.4). Platform I/O budgets remain untouched.

**Constraints**: Sibling module under `test/eval/` only; same CI gate as F1 goldens (Clarification Q3). Active multi-leg harness loop against recorded fixtures; score whole conversation at end (Clarification Q1). One fixture conversational capability; three scripted cases (Clarification Q2). Must not redefine F1 golden/smoke gating or capability score-report quality/schema fields (FR-010; Consumes F1). Must not rewrite H2 allowlist, budget codes, transcript wire, or dual-output acceptance (Consumes H2). Round budget and permitted set come from the fixture capability's declared manifest fields — H4 invents neither (spec Edge Cases). No prompt/provider/model strings in Flutter (T8 / R-12). No per-request server-side state (T9 / §4.4, §9.7). No §9.14 mechanism (R-20). OD-5: single platform matrix, not per-clinic.

**Scale/Scope**: Zero §4 runtime components modified (see Components Touched). Nine named tests (T1–T9). Three Freezes entries. One fixture conversational capability with three scripted cases. Roughly 14–20 tasks — under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — CI-gated conversation evals catch wrong-key / out-of-allowlist / non-converging behaviour without a per-clinic eval farm (spec Constitution Alignment → Clinic Fit; OD-5).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — H4 adds a sibling Vitest module under `test/eval/` and wires it into the existing CI golden-eval job; no new deployable, queue, or eval farm.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — H4 touches only `ai-platform/` (conversation eval fixtures + scoring + CI entry); no `frontend/` or `backend/` code is modified (spec Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — H4 writes no clinical records and opens no write path into Supabase; scores stay as a JSON artifact under `test/eval/`.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — H4 is CI-only; permitted-set and budget semantics remain H2's at runtime; fixtures exercise behaviour against those contracts without inventing a parallel key vocabulary or auth path.
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — a failing conversation eval blocks prompt/behaviour promotion only; clinic workflows remain usable without AI (spec Failure Handling; §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. H4 adds no store, no request-path I/O, and no per-request state; conversation evals are CI tooling under `ai-platform/test/eval/` that extend F1's A9 harness with multi-leg, per-conversation scoring.

## Project Structure

### Documentation (this feature)

```text
specs/047-conversation-evals/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── conversation-evals.md
        # Frozen conversation-eval gate, per-conversation scoring, and three criteria (Freezes)
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`:

1. **Architecture context** — cites delivery plan §3.8 row H4 and `01-ai-platform.md` §13.5 Conversation evals / A9; what the spec delivered; what the plan scoped.
2. **What was implemented** — sibling conversation harness + scoring, one fixture conversational capability with three scripted multi-leg cases, per-conversation JSON scores, same CI gate as F1.
3. **Files to review** — this slice's `ai-platform/test/eval/` conversation files, CI delta, and frozen contract only.
4. **Run the automated suite** — slice-only `npx vitest run test/eval/conversation...` commands (no full-suite `npm test`, no prior-slice counts).
5. **Inspect the changes** — open the conversation harness, three cases, score-report shape, and frozen contract.
6. **Manual validation** — omitted; CI/`vitest` is the only verification path for this eval-harness slice.

`data-model.md` is **not** produced — H4 defines no D1 entities (spec Key Entities: not applicable). `research.md` is **not** produced — research is `docs/architecture/ai-platform/01-ai-platform.md`.

`contracts/conversation-evals.md` freezes the three Freezes entries so later work (and J3's "evals pass" half) binds to a frozen artifact, not prose: conversation evals as a CI-gated extension of the A9 suite, per-conversation (not per-turn) scoring, and the three acceptance criteria with their recorded score payload.

### Source Code (repository root)

```text
ai-platform/
└── test/
    └── eval/                                              # EXISTING — F1 harness root (Consumes; not rewritten)
        ├── harness.ts                                     # CONSUMED (F1) — golden runner; H4 added one-predicate `expectations/` discriminator in `listEvalCapabilities()` so sibling conversation dirs without `expectations/` stay outside golden gating (tasks.md T018; behaviour-preserving for goldens)
        ├── score-report.ts                                # CONSUMED (F1) — capability quality/schema report unchanged
        ├── golden.test.ts                                 # CONSUMED (F1) — capability goldens unchanged
        ├── live-smoke.test.ts                             # CONSUMED (F1) — live smoke unchanged
        ├── prohibitions.test.ts                           # MODIFIED — extend T8/T9 coverage for conversation module files
        ├── conversation-harness.ts                        # NEW — active multi-leg loop: per-leg fixtures, append scripted turns, score whole conversation at end (Clarification Q1; FR-001, FR-002, FR-010)
        ├── conversation-score-report.ts                   # NEW — per-conversation JSON scores for the three criteria (FR-003–FR-006; Freezes)
        ├── clinic.chat_assistant/                         # NEW — one fixture conversational capability (Clarification Q2)
        │   ├── cases/                                     # NEW — required positives + negative-control cases (FR-007–FR-009)
        │   │   ├── converges_within_round_budget.json
        │   │   ├── assistant_must_request_correct_key.json
        │   │   ├── cannot_obtain_key_outside_permitted_set.json
        │   │   ├── fails_to_converge_within_budget.json
        │   │   ├── exceeds_round_budget.json
        │   │   ├── requests_wrong_permitted_key.json
        │   │   ├── requests_key_outside_permitted_set.json
        │   │   └── criterion_fails_mid_conversation.json
        │   ├── fixtures/                                  # NEW — per-leg recorded assistant-turn fixtures (FR-002; A9; Clarification Q1 — no composer/adapter path)
        │   └── capability.json                            # NEW — fixture manifest declaring round budget + permitted key set (Consumes H2/H1 fields; does not invent defaults)
        └── conversation.test.ts                           # NEW — T1–T7 + negative-control coverage (conversation eval suite)

.github/
└── workflows/
    └── ci.yml                                             # MODIFIED — include conversation.test.ts in the existing ai-platform-eval-golden job (same CI gate; Clarification Q3; FR-001, FR-010)
```

No `frontend/` or `backend/` tree is shown — H4 touches neither. No `ai-platform/src/` module is added. F1 capability-eval modules and H2 runtime modules are **consumed**; `harness.ts` receives only the `expectations/`-directory discriminator noted above (not a rewrite of golden/smoke gating). `prohibitions.test.ts` / `ci.yml` are modified as listed.

**Structure Decision**: H4 places conversation cases and scoring as a sibling under the existing `ai-platform/test/eval/` tree and joins the same CI golden-eval gate (Clarification Q3; delivery plan §7.1). The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From F1 — capability eval harness (A9): golden cases per capability against recorded provider fixtures in CI, smaller live smoke on schedule against pinned models, per-run score recording, CI regression gate for prompt changes | `ai-platform/test/eval/harness.ts` (`runGoldenSuite` / golden runner; **H4 one-predicate extension:** `listEvalCapabilities()` requires an `expectations/` directory so conversation fixture dirs without one are excluded from golden gating); `ai-platform/test/eval/score-report.ts` (`ScoreReport`, `CaseScore`, `writeScoreReport`); `ai-platform/test/eval/golden.test.ts`; `ai-platform/test/eval/live-smoke.test.ts`; CI job `.github/workflows/ci.yml` → `ai-platform-eval-golden`; scheduled smoke `.github/workflows/ai-platform-eval-live-smoke.yml`; frozen in `specs/039-eval-suite-harness/contracts/capability-eval-harness.md`. H4 **extends** with a sibling conversation module and the same CI gate; it does **not** redefine how capability goldens gate CI, how live smoke is scheduled, or how capability quality/schema scores are recorded, and does not invent a second eval product |
| From H2 — permitted-key allowlist enforcement at the validator; conversation budget counting from the submitted transcript alone (`conversation_budget_exhausted` on breach); context-request as a second permitted output shape alongside prose; closed transcript wire / validation rules | `ai-platform/src/context/validator.ts` (`validateContext` conversational path, allowlist drop via `permittedKeySet`, budget breach → `conversation_budget_exhausted`); `ai-platform/src/manifest/index.ts` (`Interaction.maxHistoryTurns`, `maxContextRoundsPerTurn`, `permittedKeySet`); `ai-platform/src/context/context-request.ts` (`validateContextRequest`); `ai-platform/src/validate/phases.ts` / `index.ts` (dual prose \| context-request acceptance); frozen in `specs/045-transcript-validation-budgets/contracts/transcript-validation-budgets.md`, `transcript-wire.md`, and `conversational-composition.md`. H4 **scores** scripted conversations against those contracts; it does **not** rewrite allowlist semantics, budget codes, transcript shape, or dual-output acceptance |

Every **Consumes** entry binds to an existing implementation. None requires modification of a frozen contract (stop condition 2 not triggered). The fixture capability id `clinic.chat_assistant` is the same fixture id already used by H1/H2/H3 unit tests — H4 does not invent a second conversational capability vocabulary.

## Components Touched

H4 modifies **no** §4 runtime component of `01-ai-platform.md`. Implements cites **§13.5** and **A9** — testing-strategy / eval-suite layers, not a Worker pipeline stage. Conversation evals live under `ai-platform/test/eval/` only (Clarification Q3), matching the F1 precedent.

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.3.5 Context validator | **Not touched** | Consumed via H2 binding; evals score against allowlist/budget behaviour |
| §4.3.6 Prompt composer and prompt registry | **Not touched** | Consumed via H2 composition / dual-output contracts; not rewritten |
| §4.3.9 Response validator and repair | **Not touched** | Consumed via H2 dual acceptance; not rewritten |
| All other §4.x | **Not touched** | Out of scope |

Stop condition 5 (multi-component without reason) is not triggered.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/test/eval/harness.ts` | FR-010 (CONSUMED F1 — one-predicate `expectations/` discriminator in `listEvalCapabilities()`; golden/smoke gating otherwise unchanged) |
| `ai-platform/test/eval/conversation-harness.ts` | FR-001, FR-002, FR-010 (active multi-leg loop against fixtures; extends F1 harness without a second product; Clarification Q1) |
| `ai-platform/test/eval/conversation-score-report.ts` | FR-003, FR-004, FR-005, FR-006 (per-conversation scores for right keys, permitted set, round-budget convergence; Freezes) |
| `ai-platform/test/eval/clinic.chat_assistant/capability.json` | FR-005, FR-007 (fixture capability declares round budget + permitted set; Clarification Q2; Consumes H2/H1 fields) |
| `ai-platform/test/eval/clinic.chat_assistant/cases/converges_within_round_budget.json` | FR-007 (T1 case) |
| `ai-platform/test/eval/clinic.chat_assistant/cases/assistant_must_request_correct_key.json` | FR-008 (T2 case — *correct* key, not merely any permitted key) |
| `ai-platform/test/eval/clinic.chat_assistant/cases/cannot_obtain_key_outside_permitted_set.json` | FR-009 (T3 case) |
| `ai-platform/test/eval/clinic.chat_assistant/cases/*.json` | Negative-control + mid-conversation fail cases (falsifiable gate; T4 e2e) |
| `ai-platform/test/eval/clinic.chat_assistant/fixtures/**` | FR-002 (per-leg recorded fixtures; A9 fixture discipline via Consumes F1; Clarification Q1 — no composer/adapter) |
| `ai-platform/test/eval/conversation.test.ts` | T1–T7 + negative-control coverage (FR-001–FR-010) |
| `ai-platform/test/eval/prohibitions.test.ts` | T8, T9 (delivery plan §6.4 / R-12; §4.4, §9.7) — extend existing F1 prohibitions entry to cover conversation module files without inventing a second gate |
| `.github/workflows/ci.yml` | FR-001, FR-010 (include conversation suite in existing `ai-platform-eval-golden` job; Clarification Q3) |
| `specs/047-conversation-evals/contracts/conversation-evals.md` | Freezes → conversation evals as CI-gated A9 extension; per-conversation scoring; three criteria |
| `specs/047-conversation-evals/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced. Consumed F1 capability-eval and H2 runtime modules are not rewritten beyond the documented `harness.ts` discriminator.

## Test Layout

Per the architecture's testing strategy (§13.5 Conversation evals — scripted multi-leg conversations against fixtures, scored per conversation rather than per turn) and delivery plan §3.11.7 row H4:

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `scripted_conversation_converges_within_round_budget` | Conversation evals | `ai-platform/test/eval/conversation.test.ts` |
| T2 `assistant_must_request_correct_key` | Conversation evals | `ai-platform/test/eval/conversation.test.ts` |
| T3 `cannot_obtain_key_outside_permitted_set` | Conversation evals | `ai-platform/test/eval/conversation.test.ts` |
| T4 `scoring_is_per_conversation_not_per_turn` | Conversation evals | `ai-platform/test/eval/conversation.test.ts` |
| T5 `scripted_multi_leg_against_fixtures` | Conversation evals | `ai-platform/test/eval/conversation.test.ts` |
| T6 `extends_f1_harness_without_redefining_capability_evals` | Conversation evals | `ai-platform/test/eval/conversation.test.ts` |
| T7 `conversation_eval_scores_recorded_per_conversation` | Conversation evals | `ai-platform/test/eval/conversation.test.ts` |
| T8 `no_prompt_text_in_flutter_client` | Conversation evals (inherited prohibition) | `ai-platform/test/eval/prohibitions.test.ts` |
| T9 `harness_holds_no_per_request_server_state` | Conversation evals (inherited prohibition) | `ai-platform/test/eval/prohibitions.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). H4 emits **no** §5.4 taxonomy codes — pass/fail of conversation evals are CI outcomes (spec Test plan coverage note). T1–T3 are the three required scripted cases against one fixture capability (Clarification Q2). T4 asserts the acceptance unit is the whole conversation's criteria, not turn-level aggregation. T5 asserts the active harness loop runs multi-leg against recorded fixtures (Clarification Q1). T6 asserts F1 capability golden/smoke entries and score-report quality/schema fields remain unchanged. T7 asserts per-conversation scores for the three criteria are written per run. T8/T9 extend the existing prohibitions entry for the conversation module.

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/conversation-evals.md` constrains the CI-gated extension, per-conversation scoring, and three criteria so later work binds to a frozen artifact (delivery plan DP-4 / Freezes).
2. **Conversation score-report helper.** Land `conversation-score-report.ts` with the three-criterion per-conversation payload so T4/T7 have a shape to assert (FR-003–FR-006).
3. **Fixture capability + three scripted cases + per-leg fixtures.** Land `clinic.chat_assistant/capability.json`, three cases, and fixtures so T1–T3/T5 have something to drive (Clarification Q2; FR-002, FR-007–FR-009).
4. **Active conversation harness.** Land `conversation-harness.ts` — each leg against fixtures, append scripted user/context turns, score whole conversation at end (Clarification Q1; FR-001, FR-002).
5. **Conversation Vitest entry + T1–T7.** Suite proves converge / correct key / outside-permitted / per-conversation scoring / multi-leg fixtures / F1 non-redefinition / score recording.
6. **Prohibitions + T8, T9.** Extend `prohibitions.test.ts` for conversation module files (R-12 / no per-request state).
7. **CI wiring.** Add `conversation.test.ts` to the existing `ai-platform-eval-golden` job in `.github/workflows/ci.yml` (Clarification Q3; FR-001, FR-010).
8. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
