# Implementation Plan: Client architecture guard in CI (E1)

**Branch**: `ai/035-e1-client-arch-guard-ci` | **Date**: 2026-08-02 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/035-client-arch-guard-ci/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

E1 installs the client architecture guard (R-12) as a permanent CI lint: a standalone Dart script that fails the Flutter build when prompt-like strings, provider names, or model identifiers appear anywhere in client source, proven by deliberately failing fixtures and by a clean-tree pass that also asserts full client-source coverage (§3.4.1 item 1; §13.5 Architecture guard (R-12); delivery plan §3.6). It sits at the head of Band E with `Needs: —` and must land before any client AI code (DP-6; E2 onward).

## Technical Context

**Language/Version**: Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`); Flutter stable for the desktop client whose sources the guard scans.

**Primary Dependencies**: The Flutter desktop client under `frontend/`; the existing GitHub Actions workflow at `.github/workflows/ci.yml` (Clarification Q1: dedicated CI step invoking a standalone Dart script). No new pub packages, no Worker, no Supabase, no D1/R2/DO.

**Storage**: N/A — E1 defines no entities, writes no rows, and opens no store (spec Key Entities: not applicable).

**Testing**: CI lint layer (§13.5 Architecture guard (R-12); delivery plan §3.11.5 row E1). The permanent suite is the dedicated CI step(s) that (a) run the script against each deliberately failing fixture expecting non-zero exit (T1–T3), (b) run it against the clean client scan roots expecting zero exit (T4), and (c) assert full client-source coverage (T5). The same commands are runnable locally via `dart` from `frontend/`. No `flutter test` cases, no Vitest, no SQL tests.

**Target Platform**: Flutter Windows desktop client sources under `frontend/`; GitHub Actions CI (`frontend-quality` job on `windows-latest`, matching the existing workflow).

**Project Type**: Client-side architectural CI component under `frontend/tool/` — not a gateway Worker slice, not a §4 behavioural component (§3.4.1; §13.5).

**Performance Goals**: None beyond ordinary CI step duration. E1 has no request path and no latency/I/O budget of its own. Platform I/O budgets (one Quota DO round trip and one D1 insert in the guard, one R2 object per request — §6.1, §7.5, §13.6) are vacuous here and remain untouched.

**Constraints**: Scan covers every client source path (FR-004; Done when "anywhere in client code"); fixtures live outside clean scan roots under the guard's tool/fixture directory (Clarification Q2); failing fixture runs are separate expect-fail invocations, not left in the clean tree (FR-005; §3.11.5 E1); no warn-and-continue mode; no client AI feature code introduced (DP-6; Out of Scope); no exhaustive worldwide catalogue of provider/model strings (Out of Scope — three categories proven by fixtures).

**Scale/Scope**: One standalone Dart script, three deliberately failing fixtures, one CI workflow modification, five named CI-lint tests (T1–T5), six FRs. Well under the ~25-task ceiling (delivery plan §6.3 stop condition 5). Touches zero §4 components (see Components Touched).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — one CI rule
      protecting the client/platform seam; no clinic-operated infrastructure (§3.4.1; R-12; spec
      Constitution Alignment).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — a Dart script plus one CI step; no new
      deployable, no queues, no orchestration.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — E1 touches
      only `frontend/` (tooling + CI); it touches neither `ai-platform/` nor `backend/`. The
      gateway §14 acknowledgement does not apply to this slice's placement (spec Layer Placement:
      E1 is not part of the gateway).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — E1 writes no domain data,
      opens no RPC, and creates no journal row.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — E1's security contribution is preventing AI internals
      (prompt text, provider names, model identifiers) from entering the client binary path (R-12;
      §3.4 Capability Contract exclusions via §3.4.1); tenant/branch RLS and audit fields are
      unchanged.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — E1 is CI-only and
      precedes every client AI surface (DP-6); clinical work is unaffected because no client AI
      path yet depends on the platform; runtime degraded mode belongs to E4 (Out of Scope).

## Project Structure

### Documentation (this feature)

```text
specs/035-client-arch-guard-ci/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify output (authoritative)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — E1 defines no D1 (or other) entities (spec Key Entities: "Not applicable").

`contracts/` is **not** produced — the **Freezes** entries (the CI guard as architectural component, the deliberately failing fixture proof, the full client-source coverage rule) have no wire shape (no table, payload, token, event, or error taxonomy). Later slices (E2+) must not weaken, bypass, or relocate the guard; they bind to the permanent CI step and script, not to a prose contract file. `research.md` is **not** produced — the research is `docs/architecture/ai-platform/01-ai-platform.md`.

`quickstart.md` (written during the implement-phase Documentation task, per `.specify/templates/ai-platform-quickstart-template.md`) will contain:

- **§1 Architecture context** — E1 row of the delivery plan (§3.6) and §13.5 / §3.4.1 / R-12; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — the standalone Dart guard script, the three fixtures, the dedicated CI step, the clean-tree + coverage gate.
- **§3 Files to review** — this slice's `frontend/tool/architecture_guard/` files and the CI workflow delta only.
- **§5 Run the automated suite** — the slice-only CI-lint commands (`dart run` / `dart` invocations against fixtures expecting failure and against clean roots expecting success); no full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open the script, the fixtures, and the CI step; grep the workflow for the guard step name.
- Manual validation omitted — CI is the only verification path (E1 exposes no runtime behaviour).

### Source Code (repository root)

```text
frontend/
├── tool/
│   └── architecture_guard/                    # NEW — guard tool root (Clarification Q1–Q2)
│       ├── architecture_guard.dart            # NEW — standalone Dart CI lint script
│       └── fixtures/                          # NEW — outside clean scan roots (Clarification Q2)
│           ├── prompt_like_string/
│           │   └── forbidden.dart             # NEW — prompt-like string fixture (T1)
│           ├── provider_name/
│           │   └── forbidden.dart             # NEW — provider name fixture (T2)
│           └── model_identifier/
│               └── forbidden.dart             # NEW — model identifier fixture (T3)
├── lib/                                       # UNCHANGED — clean scan root (shipping client sources)
└── …                                          # other frontend paths unchanged

.github/
└── workflows/
    └── ci.yml                                 # MODIFIED — dedicated architecture-guard CI step(s)
```

**Structure Decision**: The guard lives under `frontend/tool/architecture_guard/` as a standalone Dart script (Clarification Q1), sibling to existing `frontend/tool/` helpers, not under `frontend/lib/` (so the tool and its fixtures are outside the clean client scan roots — Clarification Q2). Clean scan roots are `lib/`, `test/`, `windows/`, `linux/`, and `web/` — the Flutter application sources under `frontend/` that ship in or build the desktop client (spec Assumptions). Coverage discovery walks the whole `frontend/` tree and requires every non-excluded, scannable file to lie under a configured scan root (explicit exclusion list for `build/`, `.dart_tool/`, `tool/`, ephemeral generated trees, assets, and root metadata). Fixtures are invoked only in controlled expect-fail runs; they never remain in the clean-tree gate (FR-005). No `ai-platform/` or `backend/` path is touched.

## Consumes Binding

E1 has `Needs: —` (delivery plan §3.6). It consumes no frozen contract from any earlier slice.

| Consumes entry | Existing module / file / type it binds to |
| --- | --- |
| *(none)* | — |

No consumed entry lacks an implementation. None is modified (delivery plan §2.3).

## Components Touched

E1 modifies **no** §4 component of `01-ai-platform.md`. §4.1 enumerates the AI Client SDK, Context Resolver, AI Feature Surfaces, and Conversation store — all out of scope (E2–E4 / H). The architecture places the client-side lint explicitly **outside** §4: it is an architectural CI component (§3.4.1 item 1; §13.5 Architecture guard (R-12)) that "protect[s] the decoupling more reliably than any component in §4". This is the explicit reason a multi-component-touch rule is not violated: there is no §4 component to touch. (Stop condition 5 is not triggered.)

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.1 AI Client SDK | **Not touched** | E2 |
| §4.1 Context Resolver | **Not touched** | E3 |
| §4.1 AI Feature Surfaces | **Not touched** | E4 |
| §4.1 Conversation store | **Not touched** | H band |
| §4.2–§4.5 | **Not touched** | Out of scope (bands A–D, F+) |

## Files

| File | FR(s) | Status |
| --- | --- | --- |
| `frontend/tool/architecture_guard/architecture_guard.dart` | FR-001, FR-002, FR-003, FR-004, FR-006 | Standalone Dart script: scans configured client source roots (Dart + native/web text) for prompt-like strings, provider names, and model identifiers via whole-file matching; exits 1 on violations/coverage gaps and 2 on missing scan roots; asserts tree-wide client-source coverage (T5). Representative detection patterns include the platform-integrated provider and current vendor model naming. |
| `frontend/tool/architecture_guard/fixtures/prompt_like_string/forbidden.dart` | FR-005 | Deliberately failing multi-line prompt fixture (T1 / SC-001). Outside clean scan roots. |
| `frontend/tool/architecture_guard/fixtures/provider_name/forbidden.dart` | FR-005 | Deliberately failing provider fixture using the platform-integrated provider id (T2 / SC-002). Outside clean scan roots. |
| `frontend/tool/architecture_guard/fixtures/model_identifier/forbidden.dart` | FR-005 | Deliberately failing model fixture using current vendor + platform model ids (T3 / SC-003). Outside clean scan roots. |
| `frontend/tool/architecture_guard/fixtures/multi_root/` | FR-004 | Two-root probe proving a violation under the second configured root is detected. |
| `.github/workflows/ci.yml` | FR-005, FR-006 | Dedicated architecture-guard CI step with exit-code-1 + category assertions, omission/multi-root/missing-root proofs, clean-tree gate; workflow triggers include `ai/**` pushes and PRs to `ai/master`. |
| `specs/035-client-arch-guard-ci/quickstart.md` | — | Written during the implement-phase Documentation task (sections named in Project Structure → Documentation). |

Every file traces to an `FR-###` (or the deferred Documentation task). No file is created for an unstated requirement. No `frontend/lib/` application source is added (DP-6: no client AI code). No `ai-platform/` or `backend/` file is touched.

## Test Layout

The spec's Test plan names five tests at layer **CI lint** (delivery plan §3.11.5 row E1; §13.5 Architecture guard (R-12)). Tests join CI permanently (delivery plan §3.10). Clarification Q2: separate expect-fail fixture runs versus the clean-tree run.

| Test name | Spec layer | Where it lives | How it runs |
| --- | --- | --- | --- |
| `guard_prompt_like_string_fails_build` | CI lint | Fixture `fixtures/prompt_like_string/` (multi-line prompt) + expect-fail CI step | Script exits **exactly 1**; stderr names `prompt-like string`; CI fails on any other exit |
| `guard_provider_name_fails_build` | CI lint | Fixture `fixtures/provider_name/` (platform-integrated provider id) + expect-fail CI step | Exit exactly 1; stderr names `provider name` |
| `guard_model_identifier_fails_build` | CI lint | Fixture `fixtures/model_identifier/` (current vendor + platform model ids) + expect-fail CI step | Exit exactly 1; stderr names `model identifier` |
| `guard_clean_tree_passes` | CI lint | Clean scan of `lib/`, `test/`, `windows/`, `linux/`, `web/` via CI step | Script exits zero on the real client tree with none of the three forbidden categories |
| `guard_covers_every_client_source_path` | CI lint | Tree-wide discovery in `architecture_guard.dart` during the clean-tree run; omission case is `dart … lib --assert-coverage` | Omitting a client source path from configured scan roots fails (non-zero); multi-root and `test/` probe prove each configured root is live |

Every named test places in the §13.5 **Architecture guard (R-12)** / CI lint layer — stop condition 3 not triggered. E1 emits no §5.4 platform error codes; failures are CI build failures only.

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this slice:

1. **Fixtures (FR-005 / T1–T3)** — land the three deliberately failing fixture files under `frontend/tool/architecture_guard/fixtures/` (outside clean scan roots) so expect-fail cases have something to point at.
2. **Guard script (FR-001–FR-004)** — implement `architecture_guard.dart` so that scanning a fixture with forbidden content exits non-zero (T1–T3) and scanning clean roots exits zero while asserting full client-source coverage (T4–T5). Prove T1–T3 and T4–T5 locally with the same `dart` invocations CI will use, before or as the workflow is wired.
3. **CI wiring (FR-006)** — add the dedicated step(s) to `.github/workflows/ci.yml` that permanently run expect-fail fixture invocations then the clean-tree gate (Clarification Q1–Q2; delivery plan §3.10).
4. **Documentation** — fill `quickstart.md` after implementation and verification (sections named above).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
