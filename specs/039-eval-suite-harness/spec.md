# Feature Specification: Eval suite harness and first capability eval

**Feature Branch**: `ai/039-f1-eval-suite-harness`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `F1` — "Eval suite harness and first capability eval" (delivery plan §3.7, band F).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.7, row F1):

> §13.5, A9

### Freezes

Contracts this slice establishes for the first time:

- The **capability eval harness (A9)**: a prompt/capability evaluation suite gated in CI. Golden cases per capability run against recorded provider fixtures; a smaller live smoke set runs on a schedule against pinned model versions. The suite tests output quality and schema conformance per capability (§13.5 Capability evals row; A9). Later slices (D7's capability-eval clause, H4 conversation evals, J3 staged rollout) consume this harness and must not redefine how golden cases gate CI or how live smoke is scheduled against pinned models.
- The **CI regression gate for prompt changes**: a deliberately regressed prompt fails the golden set so a prompt change that regresses quality or schema conformance is blocked in CI; the current prompt's golden set passes (delivery plan §3.7 Done when; §3.11.6 row F1; A9). Prompt artifacts remain immutable D1 assets; swapping a prompt is a new capability *build* guarded by this suite (Consumes D1).
- The **per-run score recording contract**: eval scores are recorded per run so regression is measurable across CI and scheduled smoke executions (delivery plan §3.11.6 row F1; §13.5 Capability evals — output quality and schema conformance).

### Consumes

Contracts frozen by the slices in `Needs` (D1, D5). Changing any of these is out of scope by definition:

- **From D1 (prompt registry and composer)**: the **prompt registry contract** — immutable prompt artifacts deployed with the Worker, pinned by the capability manifest; a prompt change is a new capability *build*, not an editable D1 row; the composer produces the canonical request the capability under eval uses (§4.3.6 / §5.7 Freezes in D1). F1 evaluates against those pinned artifacts and does not store prompt text in D1, invent an editable-prompt path, or redefine composition.
- **From D5 (first real provider adapter)**: the **first real provider adapter** and its **recorded-fixture adapter suite** behind the D2 provider port — wire mapping, stream normalization, usage extraction, and error classification proven against recorded fixtures (§4.3.8 Freezes in D5). F1's golden cases run against recorded provider fixtures (A9; §13.5); F1 does not redefine the adapter port, invent a second real adapter, or replace D5's fixture-suite duties. Live smoke exercises pinned model versions through the existing adapter/routing path without changing adapter ownership.

### Open decisions relied on

- **Open Decision 1** (which capability is built first): recommended default is one non-clinical-record capability. F1's first capability eval assumes the fixture capability already exercised by D1 (and selected under that default), so the first eval suite does not imply a clinical-record write path or F2 (§15 OD-1; delivery plan §7).
- **Open Decision 5** (per-clinic model or provider preference): recommended default is no initially, because preference multiplies the eval matrix. F1 assumes a single platform eval matrix — golden cases and live smoke are not per-clinic (§15 OD-5).
- **Open Decision 10** (who reviews prompt changes, and against what acceptance bar): recommended default is a named clinical reviewer plus a passing eval suite. F1 freezes the suite half of that bar; it does not invent a reviewer workflow or a numeric acceptance threshold beyond pass/fail of the golden set and recorded scores (§15 OD-10; A9).

## Clarifications

### Session 2026-08-02

- Q: Where should the capability-eval harness live under `ai-platform/`? → A: Under `ai-platform/test/eval/` only (cases, fixtures, scorer/runner helpers); CI goldens and scheduled smoke both invoke that Node/Vitest entry — no new `src/eval/` module `[implementation choice — no §citation]`
- Q: How should per-run eval scores (output quality and schema conformance) be recorded? → A: Suite writes a JSON score report per run under `ai-platform/test/eval/` (quality + schema scores per case); CI/smoke uploads or retains that artifact — no new D1 table `[implementation choice — no §citation]`
- Q: How should the scheduled live smoke set be triggered? → A: GitHub Actions scheduled workflow runs the live-smoke Vitest entry against pinned models (same `test/eval/` harness as CI goldens) `[implementation choice — no §citation]`
- Q: How should T2 construct the deliberately regressed prompt that must fail the golden set? → A: Checked-in deliberately-worse prompt artifact under `ai-platform/test/eval/` (separate from the production pinned prompt); T2 runs the golden set against that build and expects failure `[implementation choice — no §citation]`
- Q: How should golden cases assert output quality (alongside schema conformance) against recorded provider fixtures? → A: Per-case golden expectations under `test/eval/` — `system_instruction_must_contain` / optional request-system golden for composition, plus canned-output sanity (`output_must_contain` / `output_min_length`) and schema validation of the fixture-backed result; pass/fail only. Live model output-quality drift is caught by scheduled live smoke, not by fixture replay `[implementation choice — no §citation]`
- Q: How does live smoke prove it ran against providers? → A: `runLiveSmokeSuite` invokes wired adapters per pinned routing-policy target, writes `run_kind: "live_smoke"` score reports, and the scheduled workflow supplies `DEEPSEEK_API_KEY` / `GEMINI_API_KEY`; credential-less local runs may skip live egress `[implementation choice — no §citation]`
- Q: What counts as a pinned model version for smoke? → A: Explicit product/version IDs from routing policy (e.g. `deepseek-v4-flash`, `gemini-3.5-flash`); reject floating aliases (`latest` / `auto` / `default`, legacy `deepseek-chat` / `deepseek-reasoner`, bare `gemini-1.5-flash`) `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Eval suite harness and first capability eval (Priority: P1)

As the platform operator and reviewer of prompt changes, after a real prompt registry (D1) and a real provider adapter with recorded fixtures (D5) exist, I run a capability evaluation suite gated in CI: golden cases for the first capability execute against recorded provider fixtures and must pass on the current prompt; a deliberately regressed prompt fails and blocks the change; scores are recorded per run; and a smaller scheduled live smoke set runs against pinned model versions so silent model drift is caught even when no prompt edit occurs.

**Why this priority**: F1 sits where it does because its `Needs` (D1, D5) are the point at which evals have a real prompt artifact and a real adapter path — without those, golden cases and live smoke would invent prompts or providers. Prompts are the platform's core logic and have no type system; without regression evals every prompt edit is an unreviewable change (A9). Completing F1 unblocks D7's deferred capability-eval clause (written against this harness) and is half of CP4 with D7 (delivery plan §3.5 row D7; §5 CP4).

**Independent Test**: Golden cases run per capability in CI against fixtures and block a prompt change that regresses them; a scheduled live smoke set runs against pinned model versions (delivery plan §3.7 Done when; §3.11.6 row F1).

**Acceptance Scenarios**:

1. **Given** the first capability's current pinned prompt artifact and its golden case set against recorded provider fixtures, **When** the eval suite runs in CI, **Then** the golden set passes (output quality and schema conformance). *(The golden set passes on the current prompt)*
2. **Given** a deliberately regressed prompt artifact for that capability (a new capability build that worsens quality or breaks schema conformance relative to the golden expectations), **When** the eval suite runs in CI, **Then** the golden set fails and the change is blocked. *(A deliberately regressed prompt fails)*
3. **Given** any eval suite run (CI golden or scheduled smoke), **When** the run completes, **Then** scores for output quality and schema conformance are recorded for that run. *(Scores are recorded per run)*
4. **Given** pinned model versions in routing policy (never floating aliases), **When** the scheduled live smoke set executes, **Then** the smoke set runs against those pinned model versions. *(The scheduled live smoke set runs against pinned model versions)*

### Test plan

Layer: **CI** (delivery plan §3.11.6, row F1; §13.5 Capability evals (A9) — golden cases against fixtures in CI; a small live smoke set on schedule against pinned models). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `golden_set_passes_on_current_prompt` | CI | The golden set passes on the current prompt for the first capability (§3.11.6 F1; A9; §13.5; Done when) |
| T2 | `deliberately_regressed_prompt_fails` | CI | A deliberately regressed prompt fails the golden set and blocks the change (§3.11.6 F1; A9; Done when) |
| T3 | `scores_recorded_per_run` | CI | Eval scores (output quality and schema conformance) are recorded per run (§3.11.6 F1; §13.5 Capability evals) |
| T4 | `scheduled_live_smoke_against_pinned_models` | CI (scheduled) | The scheduled live smoke set runs against pinned model versions (§3.11.6 F1; A9; §13.5; Done when) |
| T5 | `golden_cases_use_recorded_fixtures` | CI | Golden cases run against recorded provider fixtures, not as the permanent live-egress path (A9; §13.5; Consumes D5 fixtures) |
| T6 | `evals_are_per_capability` | CI | The suite is scoped per capability — the first capability has its golden cases; the harness does not require a cross-capability aggregate gate (A9; §13.5) |
| T7 | `no_prompt_text_in_flutter_client` | CI (inherited prohibition) | The eval harness and fixtures introduce no prompt text, provider name, or model identifier into Flutter client code (delivery plan §6.4 / R-12) |
| T8 | `harness_holds_no_per_request_server_state` | CI (inherited prohibition) | Running evals does not introduce per-request server-side state of any kind (delivery plan §6.4 / §4.4, §9.7) |

Coverage of every error code the slice can emit (§3.10 item 2): this slice is a CI / scheduled harness, not a pipeline stage. It emits **no** runtime §5.4 taxonomy codes. Pass/fail of the golden set and completion of scheduled smoke are build/schedule outcomes (T1–T4), not request error codes.

---

### Edge Cases

- **No runtime taxonomy codes.** F1 does not emit `validation_failed`, `provider_unavailable`, or any other §5.4 code. A failing golden case fails CI; it does not invent a new request error code (A9; §13.5; §3.10).
- **Current prompt vs regressed prompt.** The happy path is the current pinned prompt passing goldens (T1). The regression branch is a deliberate worse prompt failing and blocking the change (T2). There is no third "soft fail" or warn-only mode named in A9 or §13.5.
- **Fixtures vs live smoke.** Golden cases use recorded provider fixtures in CI (A9; §13.5). Live smoke is the smaller scheduled set against pinned models — not a substitute for the CI golden gate, and not an unbounded live matrix (A9; OD-5).
- **Pinned models only.** Live smoke targets pinned model versions; floating aliases are out of scope for this harness's smoke set (§13.5; Consumes routing/policy pinning already required by the platform — F1 does not invent pin syntax).
- **Scores recorded, thresholds not invented.** Scores for output quality and schema conformance are recorded per run (§3.11.6 F1; §13.5). A9 and §13.5 name no numeric score cutoff beyond the golden pass/fail gate; this slice does not invent one.
- **Per-capability scope.** Evals are per capability (A9; §13.5). Conversation-scored multi-leg evals are H4, not F1.
- **Second-provider eval clause.** D7's "capability evals pass" case is written against this harness and lands with F1's harness available, not as D7-alone work (delivery plan §3.5 row D7; §3.11.4 D7). F1 does not rework D7's adapter or policy registration.
- **Inherited prohibitions.** No §9.14 mechanism added because it looks prudent; no prompt/provider/model strings in Flutter; no second Quota DO round trip or second R2 object per request; no guard-rejection journal rows or per-chunk D1 rows; no per-request server-side state; no client assembly of final results from chunks (delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST provide a prompt/capability evaluation suite gated in CI (A9).
- **FR-002**: The suite MUST include golden cases per capability, run against recorded provider fixtures (A9; §13.5 Capability evals).
- **FR-003**: The suite MUST include a smaller live smoke set that runs on a schedule against pinned model versions (A9; §13.5 Capability evals).
- **FR-004**: Capability evals MUST test output quality and schema conformance per capability (§13.5 Capability evals).
- **FR-005**: The golden set MUST pass on the current prompt for the first capability under eval (delivery plan §3.7 Done when; §3.11.6 F1).
- **FR-006**: A deliberately regressed prompt MUST fail the golden set so a prompt change that regresses the suite is blocked in CI (delivery plan §3.7 Done when; §3.11.6 F1; A9).
- **FR-007**: Eval scores MUST be recorded per run (delivery plan §3.11.6 F1; §13.5).
- **FR-008**: The scheduled live smoke set MUST run against pinned model versions (delivery plan §3.7 Done when; §3.11.6 F1; §13.5).
- **FR-009**: Golden CI cases MUST use recorded provider fixtures rather than depending on live provider egress as the permanent regression gate (A9; §13.5; Consumes D5).
- **FR-010**: The harness MUST NOT redefine D1 prompt immutability or D5 adapter/port contracts; it evaluates against those frozen artifacts and adapters (Consumes D1, D5; A9).

### Key Entities

Not applicable — this slice defines no entities. It freezes a CI/scheduled eval harness and scoring/recording behaviour over prompt artifacts and provider fixtures already established by D1 and D5.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Prompts are clinical-facing logic with no type system; gating them with golden cases in CI and a small scheduled live smoke set against pinned models keeps prompt edits reviewable at clinic scale without multiplying an eval matrix per clinic (A9; §13.5; OD-5). No hospital-scale or enterprise eval farm is introduced.
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker — prompt artifacts, fixtures, eval harness, and CI/scheduled jobs that exercise the gateway). It adds no `backend/` (Supabase) domain writes and no `frontend/` (Flutter) eval UI. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. Eval fixtures and scores stay with the platform; prompt text, provider names, and model identifiers must never enter the Flutter client (R-12 / delivery plan §6.4).
- **Data Integrity & Security**: F1 does not write clinical records and does not open a write path into Supabase. Golden cases use recorded fixtures; live smoke uses pinned models through the existing adapter path. Prompt text remains in immutable Worker-deployed artifacts (Consumes D1), not in D1 editable rows and not in the client.
- **Failure Handling**: A golden failure fails CI and blocks the regressing prompt change (A9; Done when). Scheduled smoke exercises pinned models so drift is visible without a prompt edit (§13.5). Eval or provider failure degrades or blocks AI prompt promotion only; clinic workflows remain usable without AI (additive / §14). This slice invents no new runtime degraded-mode UI (that remains A11 / E4).

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **D1 (prompt registry and composer)**: F1 evaluates pinned prompt artifacts; it does not redefine the registry, composer, or pin/hash build rules (Consumes D1).
- **D5 (first real provider adapter)**: F1 consumes recorded fixtures and the real adapter path; it does not rewrite adapter mapping, classification, or the D5 fixture-suite duties (Consumes D5).
- **D6 (response validator and repair)**: Schema conformance in evals asserts outcomes; F1 does not implement pipeline validation, repair, or structured output modes.
- **D7 (second provider adapter)**: Adapter, fixture suite, policy registration, and fallback ordering remain D7. The capability-eval clause that needs this harness is written against F1 and is satisfied when F1 lands; F1 does not rework D7's adapter or policy (delivery plan §3.5 row D7).
- **F2 (acceptance recording)**: Not required for the first capability under OD-1 / `advisory_display`; F1 does not implement accept/discard RPCs.
- **F3–F5**: Support lookup, retention, soft-threshold routing, and load/cost tests are later F slices.
- **H4 (conversation evals)**: Scripted multi-leg conversation scoring is H4; F1 freezes single-capability golden/smoke evals only (§13.5 Conversation evals vs Capability evals).
- **J3 (staged rollout / canary)**: Cohort activation of a prompt or policy after evals pass is J3; F1 only gates and smokes.
- **Open Decision 10 reviewer workflow**: F1 provides the passing-eval-suite half; naming and operating a clinical reviewer is outside this slice (§15 OD-10).

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: CI proves the golden set passes on the current prompt for the first capability (T1; Done when).
- **SC-002**: CI proves a deliberately regressed prompt fails the golden set and is blocked (T2; Done when; A9).
- **SC-003**: Every eval run records scores for output quality and schema conformance (T3; §3.11.6 F1; §13.5).
- **SC-004**: The scheduled live smoke set runs against pinned model versions (T4; Done when; §13.5).
- **SC-005**: Golden cases are proven to use recorded provider fixtures (T5; A9; §13.5).
- **SC-006**: The harness is per-capability and introduces no Flutter prompt/provider/model strings and no per-request server-side state (T6–T8; A9; delivery plan §6.4).

## Assumptions

- D1's prompt registry and composer are complete; the first capability's prompt artifacts are immutable, manifest-pinned assets available to the eval harness (Needs D1).
- D5's first real provider adapter and recorded-fixture suite are complete; golden cases can bind to recorded fixtures without inventing a new adapter (Needs D5).
- The first capability under eval follows Open Decision 1's recommended default (non-clinical-record, suitable for eval without F2) as already assumed by D1's fixture capability (§15 OD-1).
- Per-clinic model or provider preference is not a product requirement initially, so F1 does not multiply the eval matrix per installation (§15 OD-5).
- A9 and §13.5 name no numeric score threshold beyond golden pass/fail; recording scores is required, inventing cutoffs is not.
- Conversation evals (A14 / H4) are a separate §13.5 layer and are not part of this slice's Done when.
- The platform does not ship until the whole product does (DP-1); "independently testable" means provable by the automated CI and scheduled smoke cases above, not demonstrable to a clinic user (DP-3).
- Nothing from §9.14 is pulled forward because it looks prudent (R-20).
