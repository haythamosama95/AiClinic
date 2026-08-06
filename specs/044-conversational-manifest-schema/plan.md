# Implementation Plan: Conversational manifest fields and context-request schema (H1)

**Branch**: `ai/044-h1-conversational-manifest-schema` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/044-conversational-manifest-schema/spec.md`

**Note**: Filled in by the `/ai-platform-plan` command. The AI platform variant adds five sections (`## Consumes Binding`, `## Components Touched`, `## Files`, `## Test Layout`, `## Sequencing`) and never produces `research.md`.

## Summary

H1 freezes the A14 conversational contract surface: when `interaction_mode` is `conversational`, the
manifest must declare max history turns, max context rounds per turn, transcript size limit, and a
permitted key set; a single platform-owned `{key, arguments}` context-request schema is shared by
every conversational capability; `context_requested` is a fourth SSE terminal event kind (not a §5.4
taxonomy code); and `AwaitingContext` is a terminal immutable request state reachable only for
`conversational`. It sits in band H after A2/A4/A6 so later H2/H3 can validate transcripts and stream
context negotiation against frozen artifacts rather than inventing them (delivery plan §3.8, row H1).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), Node ≥22 for the toolchain (`ai-platform/package.json`).

**Primary Dependencies**: Existing `ai-platform/` modules — A4 `src/manifest/`, A6 `src/adapter.ts`, A2 `src/errors.ts`, A5 published context-key vocabulary in `src/context/index.ts` (`validateKey`; Assumptions — not a Needs rewrite). Vitest ~3.2. No new runtime dependency; schemas are hand-rolled TS narrowing matching A3/A4 (R-20; no schema-validation library named by the cited sections).

**Storage**: None. H1 defines no D1 entity, no R2 object, no Durable Object, and no conversation/session store (§6.7.4; FR-011; delivery plan §6.4). Integrity is build-time and contract-time only.

**Testing**: `npx vitest run` against this slice's test files — Contract + build + integration (delivery plan §3.11.7 row H1; §13.5 Contract tests and Pipeline tests). Integration cases extend A6 stub/terminal helpers gated on `interactionMode` (Clarification Session 2026-08-02 Q2) — no H2/H3 transcript or negotiation pipeline.

**Target Platform**: The `ai-platform/` Cloudflare Worker at the repository root, sibling of `frontend/` and `backend/` (delivery plan §7.1). No Worker live-path product behaviour beyond the adapter terminal-kind extension is required for Done when.

**Project Type**: Additive, non-primary AI gateway contract slice (§14 acknowledgement) — extends frozen A4/A6 surfaces and adds the shared context-request schema; no domain logic, no business data, no write path into Supabase.

**Performance Goals**: Not applicable to a build-time / contract slice. Platform I/O budgets are preserved by introducing no new Quota DO round trip, no second R2 object, and no per-request server state (§7.5, §13.6; FR-011).

**Constraints**: Conversational mechanisms remain unreachable unless a manifest opts into `conversational` (FR-005; A14). Extension only of A2/A4/A6 Freezes — no taxonomy rewrite, no ten-group rewrite, no rewrite of the three existing terminal kinds or the one-terminal-event invariant (delivery plan §2.3). Hand-rolled narrowing; no feature flags; no §9.14 mechanism (R-20). Clarification Q1 placement: conversational load rules in `src/manifest/`; context-request schema in `src/context/`; fourth terminal kind in `src/adapter.ts`.

**Scale/Scope**: Three §4 component surfaces (manifest contract, protocol adapter terminal set, journal state-machine immutability) plus one colocated context-request schema module — see Components Touched for the multi-component reason. Roughly 18–24 tasks — under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — H1 freezes
      bounded context negotiation for a declared chat capability without a session store or
      enterprise orchestration (spec Constitution Alignment → Clinic Fit; §6.7.4).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — contract/schema/terminal extensions only;
      no new deployable or queue (FR-011).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — H1 lives
      wholly in `ai-platform/`; neither `frontend/` nor `backend/` is modified (spec Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — H1 opens no Supabase write
      path and defines no clinic domain table; gateway integrity is build/contract-time only
      (spec Data Integrity & Security; §14).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — H1 adds no authn/authz surface; permitted keys are
      allowlisted against the published vocabulary; `context_requested` is not an error code and
      does not weaken A2's taxonomy (FR-006, FR-008).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — omitting
      `conversational` leaves button-invoked capabilities unchanged; the platform asks and never
      fetches (FR-005, FR-012; A14; A11).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no
domain logic, no business data, and no write path into Supabase. H1 adds contract surface only
(manifest conversational fields, shared context-request schema, fourth terminal kind, terminal
`AwaitingContext` immutability) and introduces no store and no per-request state.

## Project Structure

### Documentation (this feature)

```text
specs/044-conversational-manifest-schema/
├── plan.md                         # This file
├── spec.md                         # /ai-platform-specify + /ai-platform-clarify (already present)
├── contracts/
│   ├── conversational-manifest.md  # Frozen conversational Interaction fields + permitted key set
│   ├── context-request-schema.md   # Frozen platform-owned {key, arguments} list schema
│   └── context-requested-terminal.md  # Fourth terminal kind + AwaitingContext + not-a-taxonomy-code
└── quickstart.md                   # Named here; filled during Documentation after verification
```

`data-model.md` is omitted — H1 defines no D1 entity (spec Key Entities; FR-011).
`research.md` is never produced — the research is `docs/architecture/ai-platform/01-ai-platform.md` (delivery plan §6).

**`quickstart.md` sections (to fill after implementation + verification):** Architecture context;
What was implemented; Files to review (this slice only); Run the automated suite (`npx vitest run`
against this slice's test files only); Inspect the changes. Omit Prerequisites and Manual validation
— CI/`vitest` is the only verification path for this contract slice.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── manifest/
│   │   └── index.ts              # MODIFIED — conversational Interaction required fields
│   │                             #   (finite positive integers); permitted key set form
│   │                             #   (empty legal; duplicates rejected); unknown-key
│   │                             #   rejection via A5 validateKey; extend single_shot
│   │                             #   rejection to include permitted key set
│   ├── context/
│   │   ├── index.ts              # CONSUMED (A5) — validateKey / published vocabulary; unchanged
│   │   ├── validator.ts          # untouched (H2)
│   │   ├── preflight.ts          # untouched
│   │   └── context-request.ts    # NEW — platform-owned {key, arguments} list schema + validate()
│   ├── adapter.ts                # MODIFIED — add context_requested to terminal kinds; gate
│   │                             #   emission on interactionMode; validate context_request
│   │                             #   payload via validateContextRequest (no silent [])
│   ├── journal/
│   │   └── index.ts              # MODIFIED — AwaitingContext terminal immutable;
│   │                             #   canReachAwaitingContext wired into
│   │                             #   isJournalTransitionAllowed / journalTransition /
│   │                             #   recordTerminalState (optional interactionMode,
│   │                             #   default single_shot)
│   └── errors.ts                 # CONSUMED (A2) — unchanged; taxonomy absence proved
│                                 #   by tests (not a TaxonomyCode; forced string
│                                 #   classifies to internal_error — no throw)
└── test/
    ├── conversational-manifest.test.ts      # NEW — manifest contract/build named tests
    ├── context-request.test.ts              # NEW — shared schema + platform-owned + coverage
    ├── awaiting-context.test.ts             # NEW — AwaitingContext terminal/immutable
    └── context-requested-terminal.test.ts   # NEW — taxonomy absence + adapter integration
```

**Structure Decision**: Per Clarification Session 2026-08-02 Q1, conversational load rules extend
`src/manifest/`, the shared context-request schema lives in `src/context/context-request.ts`
(colocated with A5's vocabulary, not a new pipeline stage), and the fourth terminal kind extends
`src/adapter.ts`. Journal wires `canReachAwaitingContext` into the write path required by
FR-010 / §6.3 without a new store. Integration tests drive A6 stub helpers gated on
`interactionMode` (Clarification Q2) — no full conversational pipeline. No `frontend/` or
`backend/` path is touched.

## Consumes Binding

| **Consumes** entry | Existing module / file bound to | How H1 binds to it |
| --- | --- | --- |
| A2 — closed §5.4 error taxonomy, error-body contract, request-reference format, trace-id propagation | `ai-platform/src/errors.ts` (`TaxonomyCode`, `TAXONOMY` / `isTaxonomyCode`, `buildErrorBody`); `reference.ts`; `trace.ts` | H1 **consumes** A2 unchanged. `context_requested` is **not** a `TaxonomyCode` (proved by contract test). Forced / unknown string input to `buildErrorBody` / `classifyErrorCode` classifies to `internal_error` — A2 resilience, **no throw** in the error-body builder (FR-008; delivery plan §2.3). |
| A4 — ten field groups, loader contract, `interaction_mode` default `single_shot`, conversational-only rejection on `single_shot` | `ai-platform/src/manifest/index.ts` (`MANIFEST_FIELD_MANIFEST`, `load`, `hashManifest`, `verifyPublishedRegistry`, `Manifest`) | H1 **extends** Interaction content validation (require the three conversational numeric fields as finite positive integers when mode is `conversational`) and Context-requirements form (permitted key set for `conversational`; empty array legal; duplicates rejected). It does **not** rewrite the ten-group set, the omitted-mode default, or A4's presence/absence rejection rule — it widens that rejection to include the permitted key set (FR-001–FR-006). |
| A6 — SSE framing (`accepted`, heartbeats, terminals `completed` / `failed` / `cancelled`), one-terminal-event invariant; fourth kind reserved for H1 | `ai-platform/src/adapter.ts` (`TERMINAL_EVENT_KINDS`, `StubEventSourceController`, `handleAdapterRequest`) | H1 **extends** the terminal kind set with `context_requested` for `conversational` only, gating stub/terminal helpers on `interactionMode`, and validating `context_request` via `validateContextRequest` at emit (missing/malformed throws; no silent `[]` default). It does **not** rewrite the three existing kinds or the one-terminal-event invariant (FR-009). |

**Assumptions dependency (not a Consumes rewrite):** Permitted-key unknown-key rejection (FR-006) calls A5's `validateKey` in `ai-platform/src/context/index.ts` against the published vocabulary. H1 does not redefine key shapes and does not list A5 in Needs (spec Assumptions).

No Consumes entry lacks an implementation; satisfying H1 does not require changing A2's taxonomy table or A4/A6 invariants beyond the reserved extensions (stop condition 2 not triggered).

## Components Touched

| §4 component | What H1 changes | Behaviour added? |
| --- | --- | --- |
| **§4.3.4 Capability resolver** | **Contract surface only** — conversational Interaction required fields (finite positive integers) and permitted-key-set Context-requirements form (empty legal; duplicates rejected) on the A4 loader | Build-time load/reject rules only. Resolver runtime behaviour remains C1. |
| **§4.3.1 Protocol adapter** | Fourth terminal event kind `context_requested`, gated on `interactionMode`; emit-time `validateContextRequest` | Terminal emission allow/deny for conversational vs `single_shot`; conforming payload required; one-terminal invariant preserved. |
| **§4.3.11 Journal writer** | `AwaitingContext` terminal immutability; `canReachAwaitingContext` wired into `isJournalTransitionAllowed`, `journalTransition`, and `recordTerminalState` (optional `interactionMode`, default `single_shot`) | Write-path enforcement that `AwaitingContext` cannot transition and AwaitingContext writes refuse for `single_shot`. No new table. |

**Reason for touching more than one:** Delivery plan §3.8 row H1 Freezes the complete A14 contract set in one slice — conversational manifest fields (§5.1 / §5.7), the shared context-request schema and `AwaitingContext` (§6.7.2 / §6.3), and the fourth SSE terminal kind (§5.5). Done when and §3.11.7 require all three surfaces together; A14's load-bearing property is that every conversational mechanism is gated by one mode switch. Splitting them would leave H2/H3 binding to an incomplete Freezes set. These surfaces cannot be tested apart for H1's acceptance scenarios 1–14.

**Not a fourth §4 ownership claim:** `src/context/context-request.ts` is a platform-owned schema module (Clarification Q1) colocated with A5's vocabulary. Stage-13 / composer wiring that *offers* that schema as a second output shape is H2 (§4.3.6 / §4.3.9) — out of scope here (FR-011: no new pipeline stage).

## Files

| Path | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/manifest/index.ts` | Modified — require conversational Interaction fields as finite positive integers; permitted key set form (empty legal, duplicates rejected); unknown-key fail; extend `single_shot` rejection | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006 |
| `ai-platform/src/context/context-request.ts` | Created — shared `{key, arguments}` list schema + validator | FR-007, FR-011 |
| `ai-platform/src/adapter.ts` | Modified — `context_requested` terminal kind; gate stub helpers on `interactionMode`; `pushTerminalEvent` validates `context_request` via `validateContextRequest` | FR-008, FR-009 |
| `ai-platform/src/journal/index.ts` | Modified — terminal immutability; wire `canReachAwaitingContext` into transition allow-check and write path (`journalTransition` / `recordTerminalState`) | FR-010 |
| `ai-platform/src/errors.ts` | **CONSUMED unchanged** (A2) — not modified by H1 | FR-008 |
| `ai-platform/test/conversational-manifest.test.ts` | Created | SC-001–SC-005; manifest named tests + coverage (malformed numerics; permitted-key edges) |
| `ai-platform/test/context-request.test.ts` | Created | SC-006; context-request named tests + coverage |
| `ai-platform/test/awaiting-context.test.ts` | Created | SC-008; FR-010 |
| `ai-platform/test/context-requested-terminal.test.ts` | Created | SC-007, SC-009; FR-008, FR-009 (taxonomy classifies not throws; emission payload validation; production-gated single_shot stream) |
| `specs/044-conversational-manifest-schema/contracts/conversational-manifest.md` | Created | Freezes (conversational Interaction fields, permitted key set, mode fixed for version life) |
| `specs/044-conversational-manifest-schema/contracts/context-request-schema.md` | Created | Freezes (platform-owned `{key, arguments}` schema) |
| `specs/044-conversational-manifest-schema/contracts/context-requested-terminal.md` | Created | Freezes (fourth terminal kind; not taxonomy; `AwaitingContext` terminal) |
| `specs/044-conversational-manifest-schema/quickstart.md` | Created during Documentation task after verification | Documentation mandate |

No Consumes module is rewritten. `errors.ts` is CONSUMED / unchanged. No D1 migration, no `wrangler.toml` change, no Flutter/Supabase files.

## Test Layout

Layer: **Contract + build + integration** (delivery plan §3.11.7 row H1). Mapped to §13.5 **Contract tests** (CI, every change) for manifest/schema/taxonomy/state-machine cases, and §13.5 **Pipeline tests** (fake/stub adapter, deterministic) for the two stream terminal cases (Clarification Q2).

| Spec Test plan name | Layer (§13.5) | File | Asserts |
| --- | --- | --- | --- |
| `conversational_manifest_loads_all_four_extra_fields` | Contract / build | `conversational-manifest.test.ts` | FR-001, FR-002 / SC-001 |
| `conversational_manifest_omits_max_history_turns_fails` | Contract / build | `conversational-manifest.test.ts` | FR-001 / SC-002 |
| `conversational_manifest_omits_max_context_rounds_fails` | Contract / build | `conversational-manifest.test.ts` | FR-001 / SC-002 |
| `conversational_manifest_omits_transcript_size_limit_fails` | Contract / build | `conversational-manifest.test.ts` | FR-001 / SC-002 |
| `conversational_manifest_omits_permitted_key_set_fails` | Contract / build | `conversational-manifest.test.ts` | FR-002 / SC-002 |
| `conversational_fields_rejected_on_single_shot` | Contract / build | `conversational-manifest.test.ts` | FR-003 / SC-003 |
| `interaction_mode_in_place_change_fails_build` | Build | `conversational-manifest.test.ts` | FR-004 / SC-004 |
| `permitted_key_set_unknown_key_fails` | Contract / build | `conversational-manifest.test.ts` | FR-006 / SC-005 |
| `shared_context_request_schema_accepts_conforming` | Contract | `context-request.test.ts` | FR-007 / SC-006 |
| `shared_context_request_schema_rejects_malformed_<form>` (not a list; missing `key`; missing `arguments`; element not `{key, arguments}`) | Contract | `context-request.test.ts` | FR-007 / SC-006 |
| `context_requested_absent_from_error_taxonomy` | Contract | `context-requested-terminal.test.ts` | FR-008 / SC-007 — absent from taxonomy; forced string classifies to `internal_error` (no throw) |
| `awaiting_context_is_terminal_and_immutable` | Contract / integration | `awaiting-context.test.ts` | FR-010 / SC-008 — terminal; mode-gated reachability; omitted mode defaults refuse |
| `single_shot_never_emits_context_requested` | Pipeline (integration) | `context-requested-terminal.test.ts` | FR-009 / SC-009 — production `pushTerminalEvent` deny on stream path |
| `conversational_leg_still_one_terminal_event` | Pipeline (integration) | `context-requested-terminal.test.ts` | FR-009 / SC-009 |

**Coverage additions (§3.10):**

| Named test | Layer | File | Asserts |
| --- | --- | --- | --- |
| `interaction_mode_fixed_for_life_of_version` | Contract | `conversational-manifest.test.ts` | FR-004 / §5.7 |
| `conversational_numeric_fields_reject_malformed_values` | Contract / build | `conversational-manifest.test.ts` | FR-001 — wrong type / negative / zero / non-integer |
| `permitted_key_set_edge_policies` | Contract / build | `conversational-manifest.test.ts` | FR-002 — empty legal; duplicates rejected |
| `context_requested_payload_must_conform` | Contract / integration | `context-requested-terminal.test.ts` | FR-007, FR-009 — emission validates payload |
| `context_request_schema_is_platform_owned_not_per_capability` | Contract | `context-request.test.ts` | FR-007 / §6.7.2 |
| `no_new_pipeline_stage_from_conversational_mode` | Contract | `context-request.test.ts` | FR-011 / §6.7.4 |
| `no_per_request_server_state_from_h1` | Contract | `context-request.test.ts` | FR-011 / §6.7.4; delivery plan §6.4 |

H1 emits no new §5.4 taxonomy codes — the taxonomy case is absence (and classify-unknown resilience), not a new code path (spec Edge Cases). Write-path SQL immutability for `AwaitingContext` is covered in `journal.test.ts` (C3 suite) alongside the pure-helper cases in `awaiting-context.test.ts`.

## Sequencing

1. **`ai-platform/src/context/context-request.ts`** — define the platform-owned list-of-`{key, arguments}` schema and `validateContextRequest()` (FR-007).
2. **`ai-platform/test/context-request.test.ts`** — conforming accept, four malformed rejects, platform-owned (no per-capability alternate), no-new-stage / no-per-request-state coverage cases — alongside or before step 1's branches.
3. **`ai-platform/src/manifest/index.ts`** — extend load validation for conversational Interaction fields (finite positive integers), permitted key set form (empty legal; duplicates rejected), unknown-key check via A5 `validateKey`, and `single_shot` rejection of the permitted key set (FR-001–FR-006); keep omitted-mode default and ten-group schema intact.
4. **`ai-platform/test/conversational-manifest.test.ts`** — all eight manifest named tests plus `interaction_mode_fixed_for_life_of_version`, malformed-numeric cases, and permitted-key edge policies — alongside / before matching loader branches.
5. **`ai-platform/src/journal/index.ts`** — export terminal-state helpers; enforce no transition out of `AwaitingContext` (and peer terminals); wire `canReachAwaitingContext` into `isJournalTransitionAllowed`, `journalTransition`, and `recordTerminalState` (FR-010).
6. **`ai-platform/test/awaiting-context.test.ts`** — terminal + immutable + conversational-only reachability (including omitted-mode default refuse); SQL immutability covered in `journal.test.ts`.
7. **`ai-platform/src/adapter.ts`** — add `context_requested` to terminal kinds; extend stub/terminal helpers to accept `interactionMode` and allow/deny emission; validate payload via `validateContextRequest` on emit (FR-008, FR-009; Clarification Q2).
8. **`ai-platform/test/context-requested-terminal.test.ts`** — taxonomy absence (classifies to `internal_error`, no throw); production-gated `single_shot` stream deny; emission payload validation; conversational leg still exactly one terminal event.
9. **Run** `npx vitest run` on the four H1 test files — all green; prior suites remain green (delivery plan §3.10 checkpoint rule).
10. **Contracts** — write the three `contracts/*.md` artifacts so H2/H3 **Consumes** bind to frozen shapes, not prose.
11. **`quickstart.md`** — fill from the AI platform quickstart template (slice-only files and commands).

Tests land alongside or before their implementation branches; no test is written after its implementation. Documentation artifacts (steps 10–11) are written only after the suite is green — the plan names them here; the implement phase fills `quickstart.md`.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. Multi-component touch is
> recorded under Components Touched with an explicit reason (stop condition 5 satisfied by reason,
> not by Complexity Tracking).
