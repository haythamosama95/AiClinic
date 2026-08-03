# Implementation Plan: Prompt registry and composer

**Branch**: `ai/028-d1-prompt-registry-composer` | **Date**: 2026-08-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/028-prompt-registry-composer/spec.md`

## Summary

Slice D1 makes pipeline stage 10 (prompt composition) real. It deploys prompt artifacts as immutable, hash-pinned assets bundled with the Worker, and assembles the canonical provider-bound request from those artifacts plus the resolved capability manifest and the filtered context payload — with the output-format instruction derived from the output schema and context rendered as delimited typed data (R-10). D1 sits in the delivery sequence after A3/A4/C2 (its `Needs`) and before D2/D3 (routing/invocation) and D6 (validator), which consume its frozen canonical request.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime, `compatibility_date` 2026-05-03). No new language or runtime version is introduced.

**Primary Dependencies**: The Cloudflare Worker in `ai-platform/` (Wrangler bundler, Vitest). No new external dependency is added; prompt artifacts are imported as Wrangler `[rules]` type `"Text"` modules (Clarification Q1).

**Storage**: None at request time. Prompt artifacts are immutable files under `ai-platform/prompts/` bundled into the Worker at build time. D1 holds no prompt text (FR-003); the only D1 column D1's output touches is `prompt_artifact_hash`, which C3 already writes from the manifest's `systemInstructionArtifactRef` (consumed, not modified). The registry is a build-time bundle, not a runtime store (FR-010).

**Testing**: Vitest (`npx vitest run`). Registry cases are Build + contract (build-time pin verification + no-prompt-text-in-D1 invariant); composer cases are Unit (golden) against a fixture capability; the R-10 injection case is a Pipeline test (guard-rejection-style assertion). Per delivery plan §3.11.4 row D1: "Build + golden + unit".

**Target Platform**: Cloudflare Worker (`ai-platform-gateway`). No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway component. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase.

**Performance Goals**: Stage 10 is CPU-only (§6.1). Composition is a pure function of (manifest, filtered context, user intent, output constraints) with no I/O (FR-010). No quota DO round trip, no D1 read/write, no R2 object is introduced by this slice.

**Constraints**: No per-request server-side state (§4.4, §9.7). No prompt text in any D1 table (§9.5). No provider-shaped field upstream of the adapters (§5.3). Context is data, never command (R-10). The composer invents no threshold, timeout, limit, or default beyond manifest values and the canonical representation; max tokens, stop conditions, and language come from the manifest's Output and Input field groups (spec Assumptions).

**Scale/Scope**: One fixture capability (`clinic.visit_summary`, `prose` output, `advisory_display` acceptance — Open Decision 1's recommended default). One §4 component group touched (§4.3.6). Roughly 20–25 tasks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — prompts are immutable, reviewed, versioned artifacts pinned by the manifest; the registry is a build-time bundle with no runtime store, no queue, no per-request state (spec Constitution Alignment → Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — D1 adds two in-isolate modules (registry, composer) to the existing Worker; no new deployable, no store, no async machinery.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — D1 touches only `ai-platform/`; no `frontend/` or `backend/` code is modified (spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — D1 performs no write to any store; it only reads bundled artifacts and in-memory inputs (spec Constitution Alignment → Data Integrity & Security).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — D1 reads the immutable request principal (B3) for correlation ids only; it does not verify the token and emits no auditable signal itself (the resolved prompt version is surfaced for C3's journal row, not written by D1).
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — D1 holds no domain logic and no business data; its only runtime failure is `internal_error` from a composition defect, which rejects before any provider is invoked; AI remains strictly additive (spec Constitution Alignment → Failure Handling).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. D1 adds no store, no I/O, and no per-request state to it; the registry is a build-time bundle and composition is CPU-only (§6.1 stage 10).

## Project Structure

### Documentation (this feature)

```text
specs/028-prompt-registry-composer/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── composer-output.md   # Frozen canonical-request assembly contract (Freezes → composer output)
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`: (1) Architecture context — cites delivery plan §3.5 row D1 and `17-ai-platform.md` §4.3.6, §5.7, §9.5, §5.3; (2) What was implemented — the prompt registry and the composer; (3) Files to review — this slice's source and test files only; (4) Run the automated suite — `npx vitest run test/prompt-registry.test.ts test/prompt-composer.test.ts` (slice-only, no full-suite `npm test`); (5) Inspect the changes — the fixture prompt artifacts under `ai-platform/prompts/` and the frozen contract; (6) Manual validation omitted — CI is the only verification path (no behaviour beyond CI).

`contracts/composer-output.md` freezes the wire shape a later slice's **Consumes** must bind to: the ordered role-tagged message parts (`system`, `user`, `data`), the output-format instruction derivation rule (derived from the Output field group's `mode` + `outputSchemaRef`, never authored separately), the delimited-typed-data rendering (`<key name="…" shape="…">value</key>` blocks with `</` neutralization), the output constraints carried on the canonical request (max output tokens, stop conditions, language, tone, refusal policy), and the resolved prompt artifact version surfaced for the journal row. `data-model.md` is not produced — D1 defines no D1 entities (spec Key Entities: not applicable).

### Source Code (repository root)

```text
ai-platform/
├── prompts/
│   └── clinic.visit_summary/
│       ├── system.md                       # System instruction artifact (FR-001)
│       ├── rules-visit-summary.md          # Business-rule fragment (FR-004)
│       ├── template-visit-summary.md       # Context rendering template (FR-004, FR-006)
│       └── registry.json                   # Build-time pin index: ref → content hash (FR-001, FR-002)
├── src/
│   └── prompt/
│       ├── registry.ts                     # Build-time bundle: resolves manifest-pinned refs to artifacts; build-time pin verification (FR-001, FR-002, FR-008)
│       └── composer.ts                     # Stage 10: assembles the canonical request; surfaces resolved prompt version; emits internal_error on failure (FR-004..FR-010)
└── test/
    ├── prompt-registry.test.ts              # T1–T5 (build + contract)
    └── prompt-composer.test.ts              # T6–T12 (unit golden + pipeline)
```

The `wrangler.toml` `[rules]` configuration for `"Text"` module imports of `ai-platform/prompts/**` is added as part of the registry module (Clarification Q1). No `frontend/` or `backend/` tree is shown — D1 touches neither.

**Structure Decision**: D1 extends the `ai-platform/` tree (delivery plan §7.1) with a `prompts/` asset tree and a `src/prompt/` module, siblings to the existing `src/manifest/`, `src/context/`, and `src/capability/` modules it consumes. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From A3 — canonical inference representation (canonical request element) | `ai-platform/src/contracts/canonical.ts` — `CanonicalRequest`, `encodeCanonicalRequest`, `assertNoProviderShapedFieldNames` (T11 binds to the provider-shape guard) |
| From A4 / C1 — immutable capability manifest; Prompt binding + Output field groups | `ai-platform/src/manifest/index.ts` — `Manifest`, `load`, `MANIFEST_FIELD_MANIFEST["Prompt binding"]`, `MANIFEST_FIELD_MANIFEST.Output`; `ai-platform/src/capability/index.ts` — `resolve`, `freezeManifest` (the manifest D1 reads is the fully-resolved, frozen object C1 returns) |
| From C2 — filtered, declaration-conformant context payload | `ai-platform/src/context/validator.ts` — `validateContext` → `ValidateResult.ok` branch's `filteredContext: Record<string, unknown>` (the composer renders this through the capability's template; it does not re-validate keys or shapes) |
| From A2 — error taxonomy as a closed set; stage 10 emits only `internal_error` | `ai-platform/src/errors.ts` — `TaxonomyCode`, `buildErrorBody` (T12 asserts the only runtime code stage 10 emits is `internal_error`) |
| From B3 (upstream) — immutable request principal | `ai-platform/src/identity/index.ts` — `Principal` (read for correlation ids only; the composer does not verify the token) |

Every **Consumes** entry binds to an existing implementation. None requires modification (stop condition 2 not triggered).

## Components Touched

One §4 component group: **§4.3.6 Prompt composer and prompt registry** (the slice's own component). D1 does not modify §4.3.4 (capability resolver), §4.3.5 (context validator), §4.3.11 (journal writer), or any other §4 component — it reads their frozen outputs. No multi-component reason is needed.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/prompts/clinic.visit_summary/system.md` | FR-001 (immutable deployed artifact pinned by manifest) |
| `ai-platform/prompts/clinic.visit_summary/rules-visit-summary.md` | FR-001, FR-004 (business-rule fragment the capability declares) |
| `ai-platform/prompts/clinic.visit_summary/template-visit-summary.md` | FR-004, FR-006 (context rendering template) |
| `ai-platform/prompts/clinic.visit_summary/registry.json` | FR-001, FR-002 (build-time pin index: ref → content hash; the manifest pin the build test hashes against) |
| `ai-platform/src/prompt/registry.ts` | FR-001, FR-002, FR-003, FR-008, FR-010 (resolves manifest-pinned refs to artifacts; build-time pin verification; surfaces resolved version; holds no runtime store) |
| `ai-platform/src/prompt/composer.ts` | FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010 (assembles canonical request; derives format instruction from output schema; renders context as delimited typed data; carries output constraints; surfaces resolved prompt version; emits `internal_error` on failure; pure function) |
| `ai-platform/wrangler.toml` (modified — add `[rules]` for `"Text"` imports of `prompts/**`) | FR-001 (artifacts bundled with the Worker) |
| `ai-platform/test/prompt-registry.test.ts` | T1, T2, T3, T4, T5 (FR-001, FR-002, FR-003, FR-008) |
| `ai-platform/test/prompt-composer.test.ts` | T6, T7, T8, T9, T10, T11, T12 (FR-004..FR-010) |
| `specs/028-prompt-registry-composer/contracts/composer-output.md` | Freezes → composer output contract (the wire shape D2/D3/D6 bind to) |
| `specs/028-prompt-registry-composer/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR. No untraced file is introduced.

## Test Layout

Per the architecture's testing strategy (§13.5) and delivery plan §3.11.4 row D1 ("Build + golden + unit"):

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `registry_pinned_hash_resolves_to_artifact` | Contract | `ai-platform/test/prompt-registry.test.ts` |
| T2 `registry_altered_artifact_fails_build` | Contract (build) | `ai-platform/test/prompt-registry.test.ts` |
| T3 `registry_missing_artifact_fails_build` | Contract (build) | `ai-platform/test/prompt-registry.test.ts` |
| T4 `registry_no_prompt_text_in_any_d1_table` | Contract (build + spy) | `ai-platform/test/prompt-registry.test.ts` |
| T5 `registry_prompt_version_surfaced_for_journal` | Unit | `ai-platform/test/prompt-registry.test.ts` |
| T6 `composer_matches_golden_for_fixture_capability` | Unit (golden) | `ai-platform/test/prompt-composer.test.ts` |
| T7 `composer_format_instruction_tracks_output_schema` | Unit (golden) | `ai-platform/test/prompt-composer.test.ts` |
| T8 `composer_renders_context_as_delimited_typed_data` | Unit (golden) | `ai-platform/test/prompt-composer.test.ts` |
| T9 `composer_embedded_instruction_does_not_act_as_instruction` | Pipeline | `ai-platform/test/prompt-composer.test.ts` |
| T10 `composer_output_constraints_present` | Unit (golden) | `ai-platform/test/prompt-composer.test.ts` |
| T11 `composer_no_provider_shaped_field` | Unit (contract) | `ai-platform/test/prompt-composer.test.ts` |
| T12 `composer_failure_emits_internal_error` | Unit | `ai-platform/test/prompt-composer.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). T4 implements Clarification Q4's "both" answer: schema inspection (no prompt-text columns/tables in D1 migrations) plus a spy on the D1 binding asserting zero D1 calls across all registry/composer cases. T9 is a Pipeline test in the guard-rejection style: it asserts an instruction embedded in a context value is rendered as data (escaped and block-delimited) and does not appear in any `system`/`user` instruction part.

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/composer-output.md` is written before the composer, so the composer is constrained by the frozen wire shape, not by prose (delivery plan DP-4). This is the Documentation artifact that gates the rest.
2. **Prompt artifact tree + registry pin index** (`ai-platform/prompts/...`, `registry.json`) and the `wrangler.toml` `[rules]` edit — the immutable deployed assets the registry resolves.
3. **Registry module + registry tests (T1–T5).** T1, T2, T3 (build/contract) and T4 (build + spy) land with `registry.ts`; T5 (version surfaced) lands with the composer's surfacing output. The build-time pin verification (T2, T3) must exist before the composer can trust a resolved artifact.
4. **Composer module + composer tests (T6–T12).** T6 (golden) and T7 (format instruction tracks schema) land with the assembly + derivation logic; T8 and T9 (delimited typed data + R-10) land with the renderer + escaper; T10 (output constraints) with the constraint forwarding; T11 (no provider-shaped field) binds to A3's `assertNoProviderShapedFieldNames`; T12 (`internal_error`) with the failure path.
5. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
