# Implementation Plan: Response validator, bounded repair, and structured output modes

**Branch**: `ai/033-d6-response-validator` | **Date**: 2026-08-02 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/033-response-validator/spec.md`

## Summary

Slice D6 freezes ordered response validation (transport/parse → schema → declared business constraints → safety guards), bounded repair via a single budgeted re-ask with validation errors appended when the capability's repair policy allows it (capped, counted, journaled; exhaustion → `validation_failed` with invalid content never returned), and the `structured` / `structured_atomic` streaming rows under commit-time validation (provisional `partial_structured` vs progress/heartbeat only; terminal `completed` carries the whole self-contained validated document). D6 sits after D4 in band D and is the validation/repair/structured-emission boundary that H2 and E4 consume.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime, `compatibility_date` 2026-05-03). No new language or runtime version is introduced.

**Primary Dependencies**: The Cloudflare Worker in `ai-platform/` (Wrangler bundler, Vitest). No new external package is added. Consumes D4's `stream/` broker (relay, heartbeat, one-terminal-event, `prose` incremental guards, connection-scoped cancel) unchanged for those duties. Extends `stream/` for structured-mode emission only. Manifest Output fields (`mode`, `outputSchemaRef`, `businessValidationRuleRefs`, `repairPolicy`) are read from the existing A4 manifest types (`ai-platform/src/manifest/index.ts`). Repair re-ask uses an injected `reask(errors) => Promise<assembled output>` port (Clarification Q2). Schema and business-rule refs resolve through in-memory test registries in this slice (Clarification Q3) — no on-disk schema/rule store.

**Storage**: None. Validator, repair, and structured emission create no per-request Durable Object, request registry, or D1 row per chunk (§4.4, §9.7; FR-014; delivery plan §6.4). D6 adds no D1 migration and no second R2 object. Repair-attempt journaling and repair-cost counting use injectable sinks in tests (Assumptions → C3 journal writer; FR-003, FR-006); C3's writer and B4's credit module are not modified.

**Testing**: Vitest (`npx vitest run`). Named tests are Unit (ordering / phase failures) plus Integration (Pipeline tests with fake provider) per delivery plan §3.11.4 row D6 and §13.5. No live provider and no Cloudflare resource required. Repair tests script the injected `reask` port (invalid-then-valid / always-invalid / disallowed). Schema and business-rule cases register runners in in-memory test registries keyed by manifest refs (Clarification Q3). Structured-mode tests drive the extended broker and assert event kinds, `provisional` flags, and self-contained terminals.

**Target Platform**: Cloudflare Worker (`ai-platform-gateway`). No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway component. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase.

**Performance Goals**: Validation and repair orchestration are in-isolate CPU after assembly (§4.3.9; §6.1 stage 13). No second Quota DO round trip, no second R2 object, no D1 row per stream chunk (§7.5, §13.6; delivery plan §6.4). Repair cost is counted against the request so an unbounded repair loop cannot become an unbounded bill (FR-006).

**Constraints**: Four validation phases run strictly in order; earlier failure is the reported first failure (FR-001; T10). Invalid content is never emitted as the accepted or terminal success payload (FR-007). Repair is per-capability (`repairPolicy.allowed` / `maxAttempts`), not global (FR-004); disallowed or exhausted repair → `validation_failed` (FR-005). `structured` emits provisional `partial_structured` only; `structured_atomic` emits progress/heartbeat only; terminal payload is authoritative and self-contained, never assembled from chunks (FR-008–FR-011). D4's prose relay/guards/cancel are not rewritten (FR-013). No per-request server-side state (FR-014). No mechanism from §9.14 added because it looks prudent (R-20). Output mode / schema / rules / repair policy come from the manifest Output group — never hard-coded provider or model identity (FR-012; §5.1).

**Scale/Scope**: New sibling module `ai-platform/src/validate/` plus an extension of existing `ai-platform/src/stream/` (Clarification Q1). Two §4 component groups touched with an explicit reason (see Components Touched). Twenty-four named tests (T1–T24). Roughly 20–24 tasks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — ordered validation and capped repair keep invalid drafts and unbounded bills away from clinicians; structured modes choose live provisional skeletons or progress-only without hospital-scale orchestration (spec Constitution Alignment → Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — D6 adds one in-isolate `validate/` module and extends existing `stream/`; no new deployable, no store, no per-request state object.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — D6 touches only `ai-platform/`; prompt text, provider names, and model identifiers never enter the Flutter client (R-12; spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — D6 performs no write to Supabase and adds no D1 schema; repair journaling and cost counting feed injectable sinks for later C3/B4 wiring; A5 schema and C3/B4 contracts are not altered.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — D6 is not inventing auth; safety guards cover leaked instructions, refusals, empty/truncated output, and injection echo; invalid content is never returned; repair attempts are journaled so spend remains explainable.
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — D6 holds no domain logic and no business data; provisional structured content is never the committed answer (FR-011); terminal failure is `validation_failed`; AI remains strictly additive (spec Constitution Alignment → Failure Handling).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. D6 adds no store, no Session DO, no second R2 object, and no per-request state; validation/repair are CPU-only after assembly, and structured emission extends D4's connection-scoped broker without rewriting its Consumes contracts.

## Project Structure

### Documentation (this feature)

```text
specs/033-response-validator/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── response-validator.md  # Frozen phase order, bounded repair, structured / structured_atomic emission
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`: (1) Architecture context — cites delivery plan §3.5 row D6 and `17-ai-platform.md` §4.3.9, §6.4, §5.1; (2) What was implemented — ordered validator, bounded repair with injected `reask` port, `structured` / `structured_atomic` emission; (3) Files to review — this slice's source and test files only; (4) Run the automated suite — `npx vitest run test/response-validator.test.ts test/structured-modes.test.ts` (slice-only, no full-suite `npm test`); (5) Inspect the changes — the frozen contract under `contracts/` and the `validate/` + extended `stream/` modules; (6) Manual validation omitted — CI is the only verification path (no behaviour beyond CI).

`contracts/response-validator.md` freezes the response-validator phase order, the bounded-repair contract (policy-gated re-ask, cap/count/journal, `validation_failed`, no invalid content returned), and the `structured` / `structured_atomic` streaming-mode emission rules (provisional `partial_structured` vs progress/heartbeat; self-contained terminal payload). `data-model.md` is not produced — D6 defines no D1 entities (spec Key Entities). `research.md` is not produced — research is `17-ai-platform.md`.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── validate/
│   │   ├── index.ts                 # Ordered validate + bounded repair orchestration; reask port; sinks (FR-001–FR-007, FR-012, FR-014)
│   │   └── phases.ts                # Transport/parse → schema → business rules → safety guards (FR-001, FR-002)
│   └── stream/
│       ├── index.ts                 # Extended for structured / structured_atomic emission; prose/cancel unchanged (FR-008–FR-011, FR-013, FR-014)
│       └── prose-guards.ts          # Unchanged (D4 Consumes — not modified by this slice)
└── test/
    ├── response-validator.test.ts   # T1–T16 (unit ordering/phases + integration repair)
    └── structured-modes.test.ts     # T17–T24 (integration structured emission + prohibitions / prose spy)
```

No `frontend/` or `backend/` tree is shown — D6 touches neither. No migration, no `wrangler.toml` change, and no on-disk schema/rule tree — Clarification Q3 keeps schema/rule resolution in-memory for this slice's suite. D4's `stream/` prose and cancel paths are consumed/extended, not rewritten; `prose-guards.ts` is listed only to show it stays untouched.

**Structure Decision**: D6 extends the `ai-platform/` tree (delivery plan §7.1) with new sibling module `src/validate/` and extends existing `src/stream/` for structured-mode emission (Clarification Q1). The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From D4 — stream broker that relays normalized chunks, emits heartbeats, enforces provisional-versus-committed semantics, and ends every stream with exactly one terminal event | `ai-platform/src/stream/index.ts` (`createStreamBroker`, `StreamBrokerOptions`, `StreamBrokerController`, heartbeat / one-terminal emit); frozen in `specs/031-stream-broker/contracts/stream-broker.md` §2. D6 extends emission for `structured` / `structured_atomic` and does not rewrite relay, heartbeat, or one-terminal-event duties |
| From D4 — `prose` path with incremental cheap guards and completion-time full guard set | `ai-platform/src/stream/prose-guards.ts` (`checkIncrementalGuards`, `runFullGuardSet`) and prose application in `ai-platform/src/stream/index.ts`; frozen in `specs/031-stream-broker/contracts/stream-broker.md` §3. D6 must not rewrite prose incremental or completion-time guards (FR-013; T24) |
| From D4 — connection-scoped cancellation via abort signal with partial-usage credit and no per-request server-side state | `createStreamBroker` disconnect / `fetchSignal` / credit + journal-terminal sinks in `ai-platform/src/stream/index.ts`; frozen in `specs/031-stream-broker/contracts/stream-broker.md` §4–§5. D6 does not redefine cancel, Session DO rejection, or the no-per-request-state rule |

Every **Consumes** entry binds to an existing implementation. Satisfying the spec extends structured emission on the broker without changing D4's frozen prose/relay/cancel contracts (stop condition 2 not triggered). A4 Output field types (`Manifest.Output` in `ai-platform/src/manifest/index.ts`), A2 `validation_failed` (`ai-platform/src/errors.ts`), A3 `partial_structured` chunk kind (`ai-platform/src/contracts/canonical.ts`), and C3 journal / usage sinks are Assumptions / Freezes consumers — not Consumes entries — and are not modified.

## Components Touched

Two §4 component groups, with explicit reason:

1. **§4.3.9 Response validator and repair** — ordered phases, declared business-constraint categories, safety guards, and bounded repair (policy, cap, count, journal, `validation_failed`).
2. **§4.3.10 Stream broker** — **extend only** for `structured` / `structured_atomic` emission under §6.4 (provisional `partial_structured` vs progress/heartbeat; self-contained terminal payload). Relay, heartbeat, one-terminal-event, `prose` guards, and connection-scoped cancel remain D4's frozen duties (FR-013).

**Reason for two components:** Delivery plan §3.5 row D6 Done when and this slice's Freezes jointly require both the validator/repair behaviour (§4.3.9) and the two structured streaming rows (§6.4). Architecture assigns streaming emission to the stream broker (§4.3.10), which D4 already owns for the `prose` row; Clarification Q1 places validator work in `src/validate/` and structured emission as an extension of `src/stream/` without rewriting Consumes. Touching both is the minimal way to freeze what D6's Canonical cell names; it is not scope creep into neighbouring slices.

§5.1 Output field group is cited in Implements as the manifest fields the validator and broker consume; it is not an additional §4 component modified by this slice (A4/C1 remain owners of schema/resolver).

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/src/validate/phases.ts` | FR-001, FR-002 (ordered transport/parse → schema → business-constraint categories → safety guards) |
| `ai-platform/src/validate/index.ts` | FR-001–FR-007, FR-012, FR-014 (orchestrate phases; repair policy / reask port / cap / count / journal; `validation_failed`; never return invalid content; read Output fields; no per-request state) |
| `ai-platform/src/stream/index.ts` | FR-008–FR-011, FR-013, FR-014 (structured provisional `partial_structured`; structured_atomic progress/heartbeat only; self-contained terminal; non-committable provisional emission; extend without rewriting D4 prose/cancel; no per-request state) |
| `ai-platform/test/response-validator.test.ts` | T1–T16 (FR-001–FR-007, FR-012; in-memory schema/rule registries per Clarification Q3; injected `reask` per Clarification Q2) |
| `ai-platform/test/structured-modes.test.ts` | T17–T24 (FR-008–FR-011, FR-013, FR-014) |
| `specs/033-response-validator/contracts/response-validator.md` | Freezes → phase order; bounded repair; structured / structured_atomic emission |
| `specs/033-response-validator/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced. `prose-guards.ts` is not modified and is not a Files row.

## Test Layout

Per the architecture's testing strategy (§13.5 Pipeline tests with fake provider / unit ordering) and delivery plan §3.11.4 row D6 ("Unit (ordering) + integration"):

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `valid_output_passes` | Unit (+ integration assertion on terminal success path) | `ai-platform/test/response-validator.test.ts` |
| T2 `parse_failure` | Unit | `ai-platform/test/response-validator.test.ts` |
| T3 `schema_violation` | Unit | `ai-platform/test/response-validator.test.ts` |
| T4 `business_rule_violation` | Unit | `ai-platform/test/response-validator.test.ts` |
| T5 `safety_guard_leaked_instruction` | Unit | `ai-platform/test/response-validator.test.ts` |
| T6 `safety_guard_refusal` | Unit | `ai-platform/test/response-validator.test.ts` |
| T7 `safety_guard_empty` | Unit | `ai-platform/test/response-validator.test.ts` |
| T8 `safety_guard_truncated` | Unit | `ai-platform/test/response-validator.test.ts` |
| T9 `safety_guard_injection_echo` | Unit | `ai-platform/test/response-validator.test.ts` |
| T10 `four_phases_run_in_stated_order` | Unit (ordering) | `ai-platform/test/response-validator.test.ts` |
| T11 `invalid_content_never_emitted` | Unit / integration | `ai-platform/test/response-validator.test.ts` |
| T12 `repair_allowed_one_reask_success` | Integration (Pipeline with fake; injected `reask`) | `ai-platform/test/response-validator.test.ts` |
| T13 `repair_disallowed_immediate_validation_failed` | Integration (Pipeline with fake) | `ai-platform/test/response-validator.test.ts` |
| T14 `repair_fails_validation_failed` | Integration (Pipeline with fake; injected `reask`) | `ai-platform/test/response-validator.test.ts` |
| T15 `repair_attempt_cap_enforced_and_journaled` | Integration (Pipeline with fake; journal sink spy) | `ai-platform/test/response-validator.test.ts` |
| T16 `repair_cost_counted_against_request` | Integration (Pipeline with fake; usage/cost sink spy) | `ai-platform/test/response-validator.test.ts` |
| T17 `structured_partial_events_provisional` | Integration (Pipeline with fake) | `ai-platform/test/structured-modes.test.ts` |
| T18 `structured_terminal_carries_whole_validated_document` | Integration (Pipeline with fake) | `ai-platform/test/structured-modes.test.ts` |
| T19 `structured_atomic_progress_only` | Integration (Pipeline with fake) | `ai-platform/test/structured-modes.test.ts` |
| T20 `client_ignoring_chunks_still_correct` | Integration (Pipeline with fake) | `ai-platform/test/structured-modes.test.ts` |
| T21 `terminal_payload_not_assembled_from_chunks` | Integration (Pipeline with fake) | `ai-platform/test/structured-modes.test.ts` |
| T22 `no_per_request_state_for_repair_or_structured` | Integration (Pipeline with fake; spy — absence) | `ai-platform/test/structured-modes.test.ts` |
| T23 `provisional_structured_not_committable_on_emission` | Integration (Pipeline with fake) | `ai-platform/test/structured-modes.test.ts` |
| T24 `prose_path_unchanged_by_this_slice` | Integration (Pipeline with fake; spy — D4 prose contracts intact) | `ai-platform/test/structured-modes.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). T3/T4 use in-memory schema and business-rule registries keyed by manifest refs (Clarification Q3). T12–T16 inject `reask(errors)` so D6 owns repair without rewriting D3's invocation loop (Clarification Q2). Terminal failure uses existing A2 taxonomy code `validation_failed`; this slice does not add or rename codes (spec Assumptions / Edge Cases).

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/response-validator.md` constrains the modules; later slices (H2, E4) bind to this artifact, not to prose (delivery plan DP-4).
2. **Phases + T1–T11.** Implement ordered phases in `validate/phases.ts` / orchestrator; unit suite proves valid pass, each failure class, phase order, and no invalid emission. Schema/rule refs resolve via in-memory test registries (Clarification Q3).
3. **Bounded repair + T12–T16.** Injected `reask` port; allowed → one re-ask with errors → success; disallowed → immediate `validation_failed`; fail after re-ask → `validation_failed`; max-attempts cap journaled; repair cost counted on injectable sinks (Clarification Q2).
4. **Structured emission + T17–T21.** Extend `stream/index.ts` for `structured` (`partial_structured` provisional) and `structured_atomic` (progress/heartbeat only); terminal carries whole validated document; client ignoring chunks still correct; terminal not assembled from chunks.
5. **Prohibitions + T22–T24.** No per-request state; provisional structured not committable on emission; D4 `prose` path unchanged (spy).
6. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
