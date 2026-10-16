# Feature Specification: Conversation evals

**Feature Branch**: `ai/047-h4-conversation-evals`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `H4` — "Conversation evals" (delivery plan §3.8, band H).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.8, row H4):

> §13.5, A9

### Freezes

Contracts this slice establishes for the first time:

- **Conversation evals as a CI-gated extension of the A9 suite**: for conversational
  capabilities, scripted multi-leg conversations run against fixtures and are scored
  per conversation on three criteria — does the assistant request the *right* keys,
  does it stay inside the permitted set, and does it converge within the round budget
  (§13.5 Conversation evals row; A9; delivery plan §3.8 Done when). Later work may
  extend cases; it must not redefine per-conversation scoring or replace F1's
  capability-eval harness with a second, incompatible gate.
- **Per-conversation scoring (not per turn)**: a conversation eval pass/fail and its
  recorded scores are computed over the whole scripted conversation, not turn-by-turn
  aggregation as the acceptance unit (§13.5 Conversation evals — "scored per
  conversation rather than per turn"; delivery plan §3.11.7 row H4).
- **The three conversation-eval criteria as the H4 acceptance bar**: (1) the assistant
  requests the correct key when the script requires it; (2) the assistant stays inside
  the permitted set — no out-of-set **request** and no out-of-set **obtainment** after
  H2 allowlist drop; (3) the scripted conversation converges within the capability's
  declared round budget (budget non-breach **and**, when `expect_convergence` is set,
  a terminal `model` answer) (§13.5 Conversation evals; delivery plan §3.8 Done when;
  §3.11.7 H4).

### Consumes

Contracts frozen by the slices in `Needs` (F1, H2). Changing any is out of scope by
definition:

- **From F1 (eval suite harness and first capability eval)**: the **capability eval
  harness (A9)** — golden cases per capability against recorded provider fixtures in
  CI, a smaller live smoke set on schedule against pinned models, per-run score
  recording, and the CI regression gate for prompt changes (F1 Freezes; §13.5
  Capability evals; A9). H4 extends that harness with conversation-scored multi-leg
  cases; it does not redefine how goldens gate CI, how live smoke is scheduled, or how
  scores are recorded for capability evals, and does not invent a second eval product
  beside F1.
- **From H2 (transcript validation, conversation budgets, and composer rendering)**:
  **permitted-key allowlist enforcement** at the validator (a key outside the
  manifest's permitted set cannot enter a prompt even if the model asked for it);
  **conversation budget** counting from the submitted transcript alone, with breach
  producing `conversation_budget_exhausted`; **context-request as a second permitted
  output shape** alongside prose; and the closed transcript wire / validation rules
  that make multi-leg scripted fixtures meaningful (H2 Freezes). H4 scores behaviour
  against those contracts; it does not rewrite allowlist semantics, budget codes,
  transcript shape, or dual-output acceptance.

### Open decisions relied on

- **Open Decision 5** (per-clinic model or provider preference): recommended default is
  no initially, because preference multiplies the eval matrix. H4 assumes a single
  platform conversation-eval matrix — scripted cases are not per-clinic (§15 OD-5; A9).
- **Open Decision 10** (who reviews prompt changes, and against what acceptance bar):
  recommended default is a named clinical reviewer plus a passing eval suite. H4
  extends the suite half of that bar with conversation evals; it does not invent a
  reviewer workflow or a numeric acceptance threshold beyond pass/fail of the named
  conversation cases and recorded per-conversation scores (§15 OD-10; A9).

## Clarifications

### Session 2026-08-02

- Q: How should H4's eval harness advance scripted multi-leg conversations without H3's client chat surface? → A: Active harness loop: each leg runs against recorded fixtures; the harness appends scripted user/context turns and scores the whole conversation at the end `[implementation choice — no §citation]`
- Q: Should the three required conversation-eval cases share one fixture conversational capability, or each use its own? → A: One fixture conversational capability; three scripted cases against that capability's budget and permitted set `[implementation choice — no §citation]`
- Q: Where should conversation-eval cases and scoring live relative to F1's capability-eval suite in `ai-platform/`? → A: Sibling module under the existing evals tree (e.g. conversation cases + scoring beside capability evals), invoked by the same CI gate `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Conversation evals (Priority: P1)

As a platform reviewer (or CI operator), I need scripted multi-leg conversational
fixtures scored per conversation so a prompt or behaviour change that requests the
wrong keys, escapes the permitted set, or fails to converge within the round budget is
caught in CI — the same A9 discipline F1 established for single-shot capability
quality, applied to conversational negotiation (§13.5 Conversation evals; A9).

**Why this priority**: H4 sits after F1 and H2 because conversation scoring needs the
F1 CI-gated harness and H2's enforced permitted set, round-budget counting, and
context-request output acceptance. Without those, multi-leg scripts would invent a
second gate or score against undefined allowlist/budget behaviour (Needs: F1, H2;
delivery plan §3.8).

**Independent Test**: Scripted multi-leg conversations are scored per conversation:
does the assistant request the right keys, stay inside the permitted set, and converge
within the round budget (delivery plan §3.8 Done when; §3.11.7 row H4).

**Acceptance Scenarios**:

1. **Given** a scripted multi-leg conversational fixture against recorded fixtures for
   a conversational capability, **When** the conversation eval suite runs, **Then** the
   conversation is scored as converging within the capability's declared round budget.
   *(A scripted conversation converges within the round budget)*
2. **Given** a scripted conversation whose correct next step is for the assistant to
   request a specific permitted context key, **When** the conversation eval suite runs,
   **Then** the per-conversation score requires that the assistant request that correct
   key. *(One case where the assistant must request the correct key)*
3. **Given** a scripted conversation that would obtain a context key outside the
   capability's permitted set, **When** the conversation eval suite runs, **Then** the
   per-conversation score proves the assistant cannot obtain that key (the permitted-set
   criterion fails the conversation if the key is obtained). *(One case proving it
   cannot obtain a key outside the permitted set)*
4. **Given** any scripted multi-leg conversation under eval, **When** scores are
   recorded for the run, **Then** scoring is per conversation, not per turn — the
   acceptance unit is the whole conversation's criteria, not turn-level pass/fail as
   the gate. *(Scoring is per conversation, not per turn)*

### Test plan

Layer: **Evals** (delivery plan §3.11.7, row H4; §13.5 Conversation evals —
scripted multi-leg conversations against fixtures, scored per conversation rather than
per turn; gated in CI under A9). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `scripted_conversation_converges_within_round_budget` | Evals | A scripted conversation converges within the round budget (§3.11.7 H4; §13.5 Conversation evals; Done when) |
| T2 | `assistant_must_request_correct_key` | Evals | One case where the assistant must request the correct key (§3.11.7 H4; §13.5; Done when) |
| T3 | `cannot_obtain_key_outside_permitted_set` | Evals | One case proving a key outside the permitted set cannot be obtained (§3.11.7 H4; §13.5; Consumes H2 allowlist) |
| T4 | `scoring_is_per_conversation_not_per_turn` | Evals | Scoring is per conversation, not per turn (§3.11.7 H4; §13.5 Conversation evals) |
| T5 | `scripted_multi_leg_against_fixtures` | Evals | Conversation evals run as scripted multi-leg conversations against fixtures (§13.5 Conversation evals; A9 fixture discipline via Consumes F1) |
| T6 | `extends_f1_harness_without_redefining_capability_evals` | Evals | H4 extends F1's A9 harness; it does not redefine capability golden/smoke gating or invent a second incompatible CI product (Consumes F1; A9) |
| T7 | `conversation_eval_scores_recorded_per_conversation` | Evals | Per-conversation scores for the three criteria are recorded per run (extends F1 per-run recording; §13.5; Done when) |
| T8 | `no_prompt_text_in_flutter_client` | Evals (inherited prohibition) | Conversation eval fixtures and harness introduce no prompt text, provider name, or model identifier into Flutter client code (delivery plan §6.4 / R-12) |
| T9 | `harness_holds_no_per_request_server_state` | Evals (inherited prohibition) | Running conversation evals does not introduce per-request server-side state of any kind (delivery plan §6.4 / §4.4, §9.7) |

Coverage of every error code the slice can emit (§3.10 item 2): this slice is an eval
harness extension, not a pipeline stage. It emits **no** runtime §5.4 taxonomy codes.
Pass/fail of conversation evals are CI outcomes (T1–T4), not request error codes. H2's
`conversation_budget_exhausted` and allowlist drop behaviour remain H2's; H4 only
scores whether scripted conversations satisfy the §13.5 criteria against those
contracts.

---

### Edge Cases

- **No runtime taxonomy codes.** H4 does not emit `conversation_budget_exhausted`,
  `context_invalid`, `validation_failed`, or any other §5.4 code. A failing conversation
  eval fails CI; it does not invent a new request error code (A9; §13.5; §3.10).
- **Round budget is the declared capability budget.** Convergence is judged against the
  conversational capability's declared round budget (Consumes H2 / H1 manifest fields).
  This slice does not invent a numeric default or a second budget mechanism (§13.5;
  Consumes H2).
- **Permitted set is the manifest allowlist.** "Outside the permitted set" means outside
  the capability's permitted key set as enforced by H2; H4 does not redefine the
  allowlist or invent a parallel key vocabulary (§13.5; Consumes H2).
- **Right keys vs any permitted key.** T2 requires the *correct* key for the scripted
  scenario, not merely any key inside the permitted set (§13.5 — "request the *right*
  keys"; §3.11.7 H4).
- **Per conversation, not per turn.** A conversation that fails a criterion on one leg
  fails as a conversation; turn-level scores are not the acceptance unit (§13.5;
  §3.11.7 H4; T4).
- **Fixtures, not unbounded live chat.** Scripted multi-leg cases use fixtures under the
  A9/F1 discipline; H4 does not open an unbounded live conversation matrix or a
  per-clinic eval farm (A9; §13.5; OD-5; Consumes F1).
- **Capability evals remain F1.** Single-shot output-quality / schema-conformance goldens
  and scheduled live smoke against pinned models stay F1's Freezes; H4 adds conversation
  scoring only (§13.5 Capability evals vs Conversation evals; Consumes F1).
- **Inherited prohibitions.** No §9.14 mechanism added because it looks prudent; no
  prompt/provider/model strings in Flutter; no second Quota DO round trip or second R2
  object per request; no guard-rejection journal rows or per-chunk D1 rows; no
  per-request server-side state; no client assembly of final results from chunks
  (delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST provide conversation evals for conversational
  capabilities as part of the CI-gated evaluation suite (A9; §13.5 Conversation evals).
- **FR-002**: Conversation evals MUST run as scripted multi-leg conversations against
  fixtures (§13.5 Conversation evals; A9).
- **FR-003**: Conversation evals MUST score whether the assistant requests the right
  keys (§13.5 Conversation evals; delivery plan §3.8 Done when).
- **FR-004**: Conversation evals MUST score whether the assistant stays inside the
  permitted key set (§13.5 Conversation evals; Consumes H2).
- **FR-005**: Conversation evals MUST score whether the conversation converges within
  the round budget (§13.5 Conversation evals; delivery plan §3.8 Done when; Consumes H2).
- **FR-006**: Scoring MUST be per conversation rather than per turn (§13.5 Conversation
  evals; delivery plan §3.11.7 H4).
- **FR-007**: The suite MUST include a case where a scripted conversation converges
  within the round budget (delivery plan §3.11.7 H4).
- **FR-008**: The suite MUST include one case where the assistant must request the
  correct key (delivery plan §3.11.7 H4).
- **FR-009**: The suite MUST include one case proving a key outside the permitted set
  cannot be obtained (delivery plan §3.11.7 H4).
- **FR-010**: Conversation evals MUST extend F1's A9 harness and MUST NOT redefine
  capability golden/smoke gating or invent a second incompatible CI eval product
  (Consumes F1; A9).

### Key Entities

Not applicable — this slice defines no entities. It freezes conversation-eval scoring
behaviour over F1's harness and H2's conversational contracts.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Conversational capabilities negotiate context through the client's
  Resolver under the user's RLS; CI-gated conversation evals catch wrong-key,
  out-of-allowlist, and non-converging behaviour before a prompt change reaches a
  clinic, without a per-clinic eval farm (A9; §13.5; OD-5). No hospital-scale agent
  evaluation infrastructure is introduced.
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker —
  conversation eval fixtures, scoring, and CI entry that extends the F1 harness). It
  adds no `backend/` (Supabase) domain writes and no `frontend/` (Flutter) eval UI. Per
  the §14 acknowledgement, the gateway is a non-primary, additive component — it holds
  no domain logic and no business data, has no write path into Supabase, and is always
  optional. Eval fixtures and scores stay with the platform; prompt text, provider
  names, and model identifiers must never enter the Flutter client (R-12 / delivery
  plan §6.4).
- **Data Integrity & Security**: H4 does not write clinical records and does not open a
  write path into Supabase. Scripted fixtures exercise conversational behaviour against
  recorded fixtures under F1's harness; permitted-set and budget semantics remain
  enforced by H2 at runtime. No conversation entity or per-request server-side state is
  introduced by the eval harness (delivery plan §6.4; Consumes H2 / F1).
- **Failure Handling**: A failing conversation eval fails CI and blocks the regressing
  change (A9; Done when). Eval failure degrades or blocks AI prompt promotion only;
  clinic workflows remain usable without AI (additive / §14). This slice invents no new
  runtime degraded-mode UI (that remains A11 / E4).

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **F1 (eval suite harness and first capability eval)**: Capability goldens, scheduled
  live smoke against pinned models, and the base A9 harness remain F1. H4 only adds
  conversation-scored multi-leg cases (Consumes F1; §13.5 Capability evals vs
  Conversation evals).
- **H1 (conversational manifest fields and context-request schema)**: Manifest fields,
  shared context-request schema, and `context_requested` / `AwaitingContext` contracts
  remain H1; H4 scores against them via H2's runtime enforcement, and does not redefine
  schema or terminal kinds.
- **H2 (transcript validation, budgets, composer rendering)**: Allowlist drop,
  `conversation_budget_exhausted`, transcript wire validation, and dual output-shape
  acceptance remain H2 (Consumes H2). H4 does not reimplement those stages.
- **H3 (conversational journaling and client chat surface)**: Journal
  `conversation_id` / `turn_ordinal`, client transcript store, and negotiation loop are
  H3. H4 Needs are F1 and H2 only; H3 journaling/UI is not required for scripted
  fixture-based conversation evals and is not pulled forward.
- **D6 / D1 pipeline stages**: Response validation, repair, and composition remain their
  owning slices; H4 asserts conversation-level outcomes through the eval harness, not by
  rewriting those stages.
- **J3 (staged rollout / canary)**: Cohort activation after evals pass is J3; H4 only
  scores conversations in CI.
- **Open Decision 10 reviewer workflow**: H4 extends the passing-eval-suite half; naming
  and operating a clinical reviewer is outside this slice (§15 OD-10).
- **Open Decision 12 / 13 product defaults**: Choosing which keys the assistant may use
  and the numeric history/round defaults for a product capability are product/manifest
  authoring decisions; H4 scores against whatever the fixture capability declares
  (§15 OD-12, OD-13 are not assumed as invented thresholds here).

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional
  content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: CI proves a scripted conversation converges within the round budget (T1;
  Done when; §13.5).
- **SC-002**: CI proves one case where the assistant must request the correct key (T2;
  Done when; §3.11.7 H4).
- **SC-003**: CI proves one case that a key outside the permitted set cannot be obtained
  (T3; Done when; §3.11.7 H4).
- **SC-004**: Scoring is proven per conversation, not per turn (T4; §13.5; §3.11.7 H4).
- **SC-005**: Conversation evals run as scripted multi-leg cases against fixtures and
  extend F1's A9 harness without redefining capability evals (T5–T7; A9; Consumes F1).
- **SC-006**: The harness introduces no Flutter prompt/provider/model strings and no
  per-request server-side state (T8–T9; delivery plan §6.4).

## Assumptions

- F1's A9 capability-eval harness, fixture discipline, per-run score recording, and CI
  gate are complete and available for extension (Needs F1).
- H2's permitted-key allowlist, conversation budget counting, transcript validation, and
  dual output-shape acceptance are complete so conversation criteria are scored against
  frozen runtime contracts (Needs H2).
- Per-clinic model or provider preference is not a product requirement initially, so H4
  does not multiply the conversation-eval matrix per installation (§15 OD-5).
- A9 and §13.5 name no numeric score threshold beyond conversation pass/fail on the three
  criteria; recording per-conversation scores is required, inventing cutoffs is not.
- The fixture conversational capability declares its own round budget and permitted key
  set; H4 does not invent those values (Consumes H2 / H1).
- H3 journaling and client chat surface are not prerequisites for scripted fixture-based
  conversation evals (Needs: F1, H2 only).
- The platform does not ship until the whole product does (DP-1); "independently
  testable" means provable by the automated eval cases above, not demonstrable to a
  clinic user (DP-3).
- Nothing from §9.14 is pulled forward because it looks prudent (R-20).
