# Implementation Plan: Transcript validation, conversation budgets, and composer rendering (H2)

**Branch**: `ai/045-h2-transcript-validation-budgets` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/045-transcript-validation-budgets/spec.md`

**Note**: Filled in by the `/ai-platform-plan` command. The AI platform variant adds five sections (`## Consumes Binding`, `## Components Touched`, `## Files`, `## Test Layout`, `## Sequencing`) and never produces `research.md`.

## Summary

H2 extends the existing stage-6 context validator, stage-10 prompt composer, and stage-13 response
validator so a capability with `interaction_mode: conversational` validates a closed, platform-owned
transcript wire shape (whole-transcript accept-or-reject, shape before budgets), enforces transcript-
local history-turn and context-round budgets as `conversation_budget_exhausted`, allowlists permitted
keys (including inside `context_resolved`), prices the transcript through the existing cost
pre-flight, renders prior turns as delimited typed data with the closed role-tag set, and accepts
either prose or the platform-owned context-request schema as output. It sits in band H after C2, D1,
D6, and H1 so budgets and dual output shapes bind to frozen validator, composer, response-validator,
and conversational-manifest artifacts rather than inventing them (delivery plan §3.8, row H2).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), Node ≥22 for the toolchain (`ai-platform/package.json`).

**Primary Dependencies**: Existing `ai-platform/` modules — C2 `src/context/validator.ts` + `src/context/preflight.ts`, D1 `src/prompt/composer.ts` + `src/prompt/registry.ts`, D6 `src/validate/`, H1 `src/manifest/index.ts` conversational fields + `src/context/context-request.ts`, A2 `src/errors.ts` (`context_invalid`, `conversation_budget_exhausted`, `request_too_large`, `validation_failed`), A3 `src/contracts/canonical.ts` role-tagged parts. Vitest ~3.2. No new runtime dependency; hand-rolled TS narrowing matching C2/D1/D6 (R-20).

**Storage**: None. H2 defines no D1 entity, no R2 object, no Durable Object, and no conversation/session store (FR-019; §6.7.1; delivery plan §6.4). Integrity is request-time CPU validation and composition only.

**Testing**: `npx vitest run` against this slice's test files — Unit + golden (delivery plan §3.11.7 row H2; §13.5 Pipeline tests for unit/spy guard paths; Unit (golden) for composer fixtures, matching D1). No `vitest.workers.config.ts` cases — H2 adds no D1/DO/R2 I/O.

**Target Platform**: The `ai-platform/` Cloudflare Worker at the repository root, sibling of `frontend/` and `backend/` (delivery plan §7.1). No Flutter or Supabase changes.

**Project Type**: Additive, non-primary AI gateway runtime extension (§14 acknowledgement) — extends frozen C2/D1/D6/H1 surfaces for conversational legs; no domain logic, no business data, no write path into Supabase.

**Performance Goals**: Stages 6–7 remain CPU-only (§6.1). Platform I/O budgets preserved: no second Quota DO round trip, no second R2 object, no per-request server state (§7.5, §13.6; FR-019).

**Constraints**: Extension only of C2/D1/D6/H1 Freezes — no rewrite of single-shot required/optional key behaviour, registry pin/`single_shot` composition, phase order/repair/structured modes, or H1 manifest/schema fields (delivery plan §2.3). Shape before budgets; whole-transcript accept-or-reject; allowlist drop only inside `context_resolved` / ordinary permitted keys; no new cost mechanism; no §9.14 reservation (R-20). `single_shot` capabilities acquire no transcript validation, budget codes, or second output shape from this slice's existence.

**Scale/Scope**: Three §4 component surfaces (context validator, prompt composer, response validator) — see Components Touched for the multi-component reason. Roughly 22–25 tasks — at the skill / delivery-plan ~25-task ceiling by colocating named tests into three test files (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — H2 bounds
      conversational loops with transcript-local budgets and the existing pre-flight, without a
      session store or running conversation total (spec Clinic Fit; §6.7.1; §6.7.3).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — extends three pure Worker modules; no new
      deployable, queue, or store (FR-019).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — H2 lives
      wholly in `ai-platform/`; neither `frontend/` nor `backend/` is modified (spec Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — H2 opens no Supabase write
      path and defines no clinic domain table; gateway integrity is request-time only (spec Data
      Integrity & Security; §14).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — H2 adds no authn/authz surface; permitted keys are
      allowlisted at the validator; malformed transcripts use existing `context_invalid` (FR-005,
      FR-011).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — `single_shot`
      capabilities are unaffected; AI remains additive (delivery plan §3.8; constitution V).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no
domain logic, no business data, and no write path into Supabase. H2 extends validator, composer, and
response-validator behaviour for conversational legs only and introduces no store and no per-request
state.

## Project Structure

### Documentation (this feature)

```text
specs/045-transcript-validation-budgets/
├── plan.md                              # This file
├── spec.md                              # /ai-platform-specify + /ai-platform-clarify (already present)
├── contracts/
│   ├── transcript-wire.md               # Frozen closed transcript turn wire shape (§6.7.1)
│   ├── transcript-validation-budgets.md # Frozen shape/order/budget/allowlist enforcement + codes
│   └── conversational-composition.md    # Frozen prior-turn role tags + dual permitted output shapes
└── quickstart.md                        # Named here; filled during Documentation after verification
```

`data-model.md` is omitted — H2 defines no D1 entity (spec Key Entities; FR-019).
`research.md` is never produced — the research is `docs/architecture/17-ai-platform.md` (delivery plan §6).

**`quickstart.md` sections (to fill after implementation + verification):** Architecture context;
What was implemented; Files to review (this slice only); Run the automated suite (`npx vitest run`
against this slice's test files only); Inspect the changes. Omit Prerequisites and Manual validation
— CI/`vitest` is the only verification path for this CPU-only slice.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── context/
│   │   ├── validator.ts          # MODIFIED — conversational transcript shape/order;
│   │   │                         #   budgets; permitted-key allowlist (incl. context_resolved);
│   │   │                         #   extend ValidateResult with conversation_budget_exhausted;
│   │   │                         #   single_shot path unchanged
│   │   ├── preflight.ts          # EXTENDED (C2) — serializePreflightInput includes transcript;
│   │   │                         #   estimator / runCostPreflight predicates unchanged
│   │   ├── context-request.ts    # CONSUMED (H1) — shared {key, arguments} schema; unchanged
│   │   └── index.ts              # CONSUMED (A5) — validatePayload for resolved context shapes
│   ├── prompt/
│   │   ├── composer.ts           # MODIFIED — render transcript prior turns (role tags);
│   │   │                         #   offer context-request schema as second output shape;
│   │   │                         #   single_shot composition unchanged
│   │   └── registry.ts           # CONSUMED (D1) — pin resolution unchanged
│   ├── validate/
│   │   ├── phases.ts             # MODIFIED — conversational dual acceptance (prose OR
│   │   │                         #   platform context-request schema); phase order unchanged
│   │   └── index.ts              # MODIFIED — wire dual-shape acceptance for conversational;
│   │                             #   repair / validation_failed path unchanged
│   ├── manifest/index.ts         # CONSUMED (H1) — interactionMode, maxHistoryTurns,
│   │                             #   maxContextRoundsPerTurn, permittedKeySet; unchanged
│   ├── errors.ts                 # CONSUMED (A2) — context_invalid, conversation_budget_exhausted,
│   │                             #   request_too_large, validation_failed; unchanged
│   └── contracts/canonical.ts    # CONSUMED (A3) — role-tagged message parts; unchanged
└── test/
    ├── transcript-validation.test.ts          # NEW — transcript shape/order/budget/allowlist
    │                                          #   + coverage unit/spy cases
    ├── conversational-composer.test.ts        # NEW — golden prior-turn rendering + R-10
    └── conversational-response-validator.test.ts  # NEW — dual output-shape acceptance
```

**Structure Decision**: H2 extends the three modules named by Freezes / Done when —
`src/context/validator.ts` (§4.3.5), `src/prompt/composer.ts` (§4.3.6), and `src/validate/`
(§4.3.9 / §6.7.2 dual acceptance) — without a new pipeline stage or store. Cost pre-flight remains
C2's `runCostPreflight`; the conversational path includes the transcript in the serialized input
passed to it (FR-012). No `frontend/` or `backend/` path is touched.

## Consumes Binding

| **Consumes** entry | Existing module / file bound to | How H2 binds to it |
| --- | --- | --- |
| **C2** — filtered, declaration-conformant context payload; cost pre-flight `request_too_large`; stage-6/7 CPU-only placement | `ai-platform/src/context/validator.ts` (`ValidateResult`, `validateContext`); `ai-platform/src/context/preflight.ts` (`estimateInputTokens`, `runCostPreflight`, `serializePreflightInput`, `PreflightResult`); frozen in `specs/026-context-validator-cost-preflight/contracts/context-validator.md` | H2 **extends** `validateContext` for `interactionMode: "conversational"`: transcript shape/order, budget counting, `transcriptSizeLimit`, permitted-key allowlist (including keys inside `context_resolved`), published-shape/size checks, and a `conversation_budget_exhausted` failure branch. It does **not** rewrite C2's `single_shot` required/optional key behaviour, tenant check, `context_required` wire, estimator formula, or stage-7 predicates. Oversized cost fails by calling the existing `runCostPreflight` with `serializePreflightInput` that includes the transcript — no second cost mechanism (FR-001, FR-011, FR-012). |
| **D1** — prompt registry pin contract and `single_shot` composer output contract (R-10 delimited typed data) | `ai-platform/src/prompt/registry.ts` (`resolveArtifact`, `resolvePromptVersion`, `verifyBuildPins`); `ai-platform/src/prompt/composer.ts` (`composeRequest`, `ComposeRequestInput`); frozen in `specs/028-prompt-registry-composer/contracts/composer-output.md` | H2 **extends** `composeRequest` for conversational legs: accept a validated transcript, render prior turns with closed role tags (`user` / `assistant` / `data`) and delimited `<turn>` / `<key>` payloads, and offer H1's context-request schema as a second permitted output shape alongside prose. It does **not** rewrite registry immutability, pin checks, or `single_shot` part order / delimited context rendering (FR-014–FR-016). |
| **D6** — ordered validation phases, bounded repair, `validation_failed` on exhaustion, structured-mode emission | `ai-platform/src/validate/phases.ts` (`runValidationPhases`, `VALIDATION_PHASES`); `ai-platform/src/validate/index.ts` (`validateAndRepair`); frozen in `specs/033-response-validator/contracts/response-validator.md` | H2 **extends** acceptance so a conversational leg may validate as prose **or** as the shared context-request schema (`validateContextRequest` from H1), with keys drawn from the manifest permitted set. It does **not** reorder phases, unbound repair, return invalid content, or rewrite structured / `structured_atomic` emission (FR-017, FR-018). Output that is neither fails under the existing `validation_failed` path. |
| **H1** — `interaction_mode: conversational` fields, permitted key set, platform-owned `{key, arguments}` schema, `context_requested` terminal, `AwaitingContext` | `ai-platform/src/manifest/index.ts` (`interactionMode`, `maxHistoryTurns`, `maxContextRoundsPerTurn`, `transcriptSizeLimit`, `permittedKeySet`); `ai-platform/src/context/context-request.ts` (`validateContextRequest`, `CONTEXT_REQUEST_SCHEMA_ID`); frozen in `specs/044-conversational-manifest-schema/contracts/conversational-manifest.md` and `context-request-schema.md` | H2 **enforces** those limits and shapes at runtime (budgets from Interaction fields; allowlist from `permittedKeySet`; dual output via `validateContextRequest`). It does **not** redefine the manifest fields, the shared schema, the fourth terminal kind, or `AwaitingContext` (FR-009, FR-010, FR-011, FR-018). |

No Consumes entry lacks an implementation; satisfying H2 does not require rewriting C2/D1/D6/H1 frozen invariants beyond the reserved conversational extensions (stop condition 2 not triggered).

## Components Touched

| §4 component | What H2 changes | Behaviour added? |
| --- | --- | --- |
| **§4.3.5 Context validator** | Conversational transcript wire validation, shape-before-budgets ordering, history-turn and context-round budgets, permitted-key allowlist (incl. `context_resolved`), reliance on existing stage-7 pre-flight for transcript size | Yes — conversational stage-6 path; `single_shot` unchanged |
| **§4.3.6 Prompt composer and prompt registry** | Render supplied transcript as prior turns with closed role tags; offer context-request schema as second output shape; R-10 delimited opacity for user/clinical free text | Yes — conversational composition; registry and `single_shot` composition unchanged |
| **§4.3.9 Response validator and repair** | Accept prose **or** platform-owned context-request schema for conversational legs; neither → existing `validation_failed` | Yes — dual acceptance only; phase order, repair, structured modes unchanged |

**Reason for touching more than one:** Delivery plan §3.8 row H2 Done when and this slice's Freezes jointly require transcript validation + budgets (validator), prior-turn rendering + second output-shape offer (composer), and dual-shape acceptance (response validator / §6.7.2). The Canonical cell names §4.3.5, §4.3.6, and §6.7.2 together; splitting them would leave H3/H4 binding to an incomplete Freezes set. These surfaces cannot be tested apart for H2's acceptance scenarios 1–17.

## Files

| Path | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/context/validator.ts` | Modified — conversational transcript shape/order/budgets/allowlist/shape-size; extend `ValidateResult` | FR-001–FR-011, FR-013, FR-019 |
| `ai-platform/src/context/preflight.ts` | Extended — `serializePreflightInput` includes transcript; estimator unchanged | FR-012 |
| `ai-platform/src/prompt/composer.ts` | Modified — transcript prior-turn rendering; second output-shape offer; R-10 delimited `<turn>` | FR-014, FR-015, FR-016, FR-018 |
| `ai-platform/src/validate/phases.ts` | Modified — conversational dual acceptance (prose \| context-request) | FR-017, FR-018 |
| `ai-platform/src/validate/index.ts` | Modified — wire dual-shape path for conversational; preserve repair | FR-017, FR-018 |
| `ai-platform/test/transcript-validation.test.ts` | Created | SC-001–SC-008; transcript + coverage unit/spy tests |
| `ai-platform/test/conversational-composer.test.ts` | Created | SC-009; composer golden + R-10 + role-tag coverage |
| `ai-platform/test/conversational-response-validator.test.ts` | Created | SC-010; dual output-shape unit tests |
| `specs/045-transcript-validation-budgets/contracts/transcript-wire.md` | Created | Freezes (closed transcript wire shape) |
| `specs/045-transcript-validation-budgets/contracts/transcript-validation-budgets.md` | Created | Freezes (validation order, budgets, allowlist, codes) |
| `specs/045-transcript-validation-budgets/contracts/conversational-composition.md` | Created | Freezes (role-tag rendering, dual output shapes) |
| `specs/045-transcript-validation-budgets/quickstart.md` | Created during Documentation task after verification | Documentation mandate |

No Consumes module is rewritten beyond the reserved extensions. `registry.ts`, `context-request.ts`, `errors.ts`, and `manifest/index.ts` are not modified. `preflight.ts` gains only the `serializePreflightInput` seam (estimator/predicates unchanged). No D1 migration, no `wrangler.toml` change, no Flutter/Supabase files.

## Test Layout

Layer: **Unit + golden** (delivery plan §3.11.7 row H2). Unit/spy cases map to §13.5 **Pipeline tests** (guard/stage rejection paths, CPU-only — same realisation C2 used for Unit (spy)). Golden cases map to **Unit (golden)** under vitest fixtures — same placement D1 used for composer golden.

| Spec Test plan name | Layer (§13.5) | File | Asserts |
| --- | --- | --- | --- |
| `valid_transcript_passes` | Pipeline (unit) | `transcript-validation.test.ts` | FR-001, FR-003 / SC-001 |
| `out_of_order_turn_ordinal_rejected_context_invalid` | Pipeline (unit) | `transcript-validation.test.ts` | FR-004, FR-005 / SC-001 |
| `malformed_turn_shape_rejected_context_invalid` | Pipeline (unit) | `transcript-validation.test.ts` | FR-005 / SC-001 |
| `unknown_turn_kind_rejected_context_invalid` | Pipeline (unit) | `transcript-validation.test.ts` | FR-005 / SC-001 |
| `transcript_rejected_whole_not_coerced_or_dropped` | Pipeline (unit) | `transcript-validation.test.ts` | FR-006 / SC-002 |
| `shape_checked_before_budgets` | Pipeline (unit) | `transcript-validation.test.ts` | FR-007 / SC-003 |
| `history_turn_limit_breached_conversation_budget_exhausted` | Pipeline (unit) | `transcript-validation.test.ts` | FR-008, FR-009 / SC-004 |
| `context_rounds_at_tail_breached_conversation_budget_exhausted` | Pipeline (unit) | `transcript-validation.test.ts` | FR-008, FR-010 / SC-005 |
| `key_outside_permitted_set_dropped` | Pipeline (unit spy) | `transcript-validation.test.ts` | FR-006, FR-011 / SC-006 |
| `oversized_transcript_request_too_large` | Pipeline (unit spy) | `transcript-validation.test.ts` | FR-012 / SC-007 |
| `trimmed_transcript_accepted_bounded_by_admission` | Pipeline (unit) | `transcript-validation.test.ts` | FR-013 / SC-008 |
| `transcript_renders_as_delimited_typed_prior_turns` | Unit (golden) | `conversational-composer.test.ts` | FR-014, FR-015 / SC-009 |
| `instruction_in_user_turn_does_not_act_as_instruction` | Unit (golden) | `conversational-composer.test.ts` | FR-015 / SC-009 |
| `prose_answer_validates` | Pipeline (unit) | `conversational-response-validator.test.ts` | FR-017 / SC-010 |
| `context_request_validates` | Pipeline (unit) | `conversational-response-validator.test.ts` | FR-017, FR-018 / SC-010 |
| `output_neither_prose_nor_context_request_fails` | Pipeline (unit) | `conversational-response-validator.test.ts` | FR-017 / SC-010 |
| `composer_no_distinction_chat_vs_clinical_free_text` | Unit (golden) | `conversational-composer.test.ts` | FR-015 / SC-009 |

**Coverage additions (§3.10):**

| Named test | Layer | File | Asserts |
| --- | --- | --- | --- |
| `budgets_counted_from_submitted_transcript_alone` | Pipeline (unit) | `transcript-validation.test.ts` | FR-009, FR-010 / §6.7.3 |
| `per_turn_cost_ceiling_uses_existing_preflight_no_new_mechanism` | Pipeline (unit spy) | `transcript-validation.test.ts` | FR-012 / delivery plan §6.4 |
| `role_tags_user_assistant_data_for_transcript` | Unit (golden) | `conversational-composer.test.ts` | FR-016 / §4.3.6 |
| `no_per_request_server_state_from_h2` | Pipeline (unit spy) | `transcript-validation.test.ts` | FR-019 / delivery plan §6.4 |
| `single_shot_unaffected_by_h2` | Pipeline (unit) | `transcript-validation.test.ts` | FR-019 / delivery plan §3.8 |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). H2 emits no new taxonomy codes — `context_invalid`, `conversation_budget_exhausted`, and `request_too_large` already exist in A2; dual-shape failure uses D6's `validation_failed`.

## Sequencing

1. **Frozen contracts first** — write `contracts/transcript-wire.md`, `transcript-validation-budgets.md`, and `conversational-composition.md` so implementation and later H3/H4 **Consumes** bind to frozen shapes, not prose (delivery plan DP-4).
2. **`ai-platform/src/context/validator.ts` + `transcript-validation.test.ts`** — conversational transcript shape/order (whole reject, `context_invalid`), then budgets (`conversation_budget_exhausted`), then allowlist drop; shape-before-budgets; trimmed gaps legal; spy that oversized path calls existing `runCostPreflight` only; spy that no DO/session store is introduced; `single_shot` path regression (FR-001–FR-013, FR-019). Tests land alongside or before matching branches.
3. **`ai-platform/src/prompt/composer.ts` + `conversational-composer.test.ts`** — prior-turn role tags, delimited typed rendering, R-10 instruction opacity, chat-vs-clinical equivalence, second output-shape offer; `single_shot` golden path unchanged (FR-014–FR-016, FR-018).
4. **`ai-platform/src/validate/phases.ts` + `index.ts` + `conversational-response-validator.test.ts`** — accept prose or H1 `validateContextRequest` for conversational; neither fails via `validation_failed`; phase order and repair untouched (FR-017, FR-018).
5. **Run** `npx vitest run` on the three H2 test files — all green; prior suites remain green (delivery plan §3.10 checkpoint rule).
6. **`quickstart.md`** — fill from the AI platform quickstart template (slice-only files and commands) after verification.

Tests land alongside or before their implementation branches; no test is written after its implementation. Documentation artifact `quickstart.md` (step 6) is written only after the suite is green — the plan names it here; the implement phase fills it.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. Multi-component touch is
> recorded under Components Touched with an explicit reason (stop condition 5 satisfied by reason,
> not by Complexity Tracking).
