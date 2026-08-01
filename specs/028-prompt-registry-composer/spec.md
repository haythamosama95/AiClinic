# Feature Specification: Prompt registry and composer

**Feature Branch**: `028-d1-prompt-registry-composer`

**Created**: 2026-08-01

**Status**: Draft

**Input**: Slice `D1` — "Prompt registry and composer" (delivery plan §3.5, band D).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.5, row D1):

> §4.3.6, §5.7, §9.5, §5.3

### Freezes

Contracts this slice establishes for the first time:

- The **prompt registry contract**: prompt artifacts are immutable assets deployed with the Worker, and the version in force is pinned by the capability manifest itself — one artifact, one pointer to it, one answer to "which prompt was live?" (§4.3.6, §5.7 Prompt artifact row, §9.5). A manifest-pinned hash resolves to its artifact; the build fails if a pinned artifact is missing or altered. Later slices (D3 invocation, C3 journal) consume the pinned artifact version recorded on the journal row, and F1 evals treat a prompt change as a new capability build (§5.7).
- The **composer output contract**: the canonical request is assembled from the system instruction artifact, the business-rule fragments the capability declares, the output-format instruction derived from the capability's output schema (not authored separately), the validated context payload rendered through the capability's template, the user intent, and the output constraints (max tokens, stop sequences, language, tone, refusal policy), with context rendered as delimited, typed data and never merged into instructions (R-10) (§4.3.6, §5.3). Later slices (D2/D3 invocation, D6 validator) consume this canonical request; the output schema is the single source of truth for the format instruction, the provider's structured-output configuration, and the response validator (§4.3.6).

### Consumes

Contracts frozen by earlier slices that this slice uses. Changing any of these is out of scope by definition:

- **From A3**: the canonical inference representation — the canonical request element (ordered role-tagged message parts, output format directive, sampling constraints, max output tokens, stop conditions, stream flag, deadline, correlation ids) that the composer assembles into (§5.3). D1 produces canonical requests; it does not redefine the canonical types, and nothing upstream of the adapters may contain a provider-shaped field.
- **From A4 / C1**: the immutable capability manifest, specifically its **Prompt binding** field group (system instruction artifact ref, business-rule fragment refs, context rendering template ref, output-format instruction derivation rule) and its **Output** field group (mode, output schema ref) (§5.1, §5.7). D1 reads a fully-resolved, immutable manifest object from C1 and does not resolve capability ids or honour version pins.
- **From C2**: the filtered, declaration-conformant context payload — only the manifest-declared keys, each conforming to its published shape, with everything else dropped — that the composer renders through the capability's template (§4.3.5, §5.2 Minimization).
- **From A2**: the error taxonomy as a closed set; stage 10 (prompt composition) emits only `internal_error` on failure (§5.4, §6.1 stage 10).
- **From B3 (upstream)**: the immutable request principal established by the guard, available to later stages (§4.3.2). The composer reads it for correlation ids and does not verify the token.

## Clarifications

### Session 2026-08-01

- Q: Where do the prompt artifacts live in the repo and how are they bundled into the Worker? → A: A dedicated `ai-platform/prompts/<capability-id>/` tree imported into the Worker bundle as Wrangler `[rules]` type `"Text"` modules, with the registry built from a build-time index of those imports `[implementation choice — no §citation]`
- Q: What does "the build fails if a pinned artifact is missing or altered" run as? → A: A Vitest build test in the registry suite that hashes each pinned artifact against its manifest pin and fails CI on mismatch or absence `[implementation choice — no §citation]`
- Q: What concrete delimiter syntax does the composer use for "delimited, typed data"? → A: XML-style block tags (`<key name="…" shape="…">value</key>`), with literal `</` inside a value escaped to a neutralized form `[implementation choice — no §citation]`
- Q: How does T4 assert "no prompt text is present in any D1 table"? → A: Both — schema inspection (no prompt-text columns/tables in D1 migrations) plus a spy on the D1 binding asserting zero D1 calls across all registry/composer cases `[implementation choice — no §citation]`

### Open decisions relied on

- **Open Decision 1 — which capability is built first.** D1's composer and registry are exercised against a fixture capability; the recommended default (one non-clinical-record capability, `prose` output mode, `advisory_display` acceptance) is assumed for the fixture's manifest shape, so that F2 (acceptance recording) is not a prerequisite for the composer and no clinical-record write path is implied (§15 OD1, delivery plan §7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prompt registry and composer (Priority: P1)

As the AI Gateway Worker, after the guard has authenticated the caller, resolved the immutable capability manifest (C1), and validated the context payload (C2), I assemble the canonical provider-bound request at pipeline stage 10: I resolve the manifest-pinned prompt artifacts from the immutable registry deployed with the Worker, compose the final message set from the system instruction artifact, the business-rule fragments, the output-format instruction derived from the capability's output schema, the validated context rendered through the capability's template as delimited typed data, the user intent, and the output constraints (max tokens, stop sequences, language, tone, refusal policy). A composition failure is rejected with `internal_error`; a missing or altered pinned artifact fails the build before any request runs. No prompt text is readable from D1, and the resolved prompt version is what the journal records.

**Why this priority**: D1 sits where it does because its `Needs` (A3, A4, C2) are the point at which the canonical representation, the manifest's Prompt binding and Output field groups, and the filtered context payload are all frozen and resolvable. Stage 10 is the last CPU-only stage before the paid I/O of routing and invocation (stage 11); D1 is what makes stage 10 real, and downstream slices D2/D3 (routing, invocation) and D6 (validator) consume its frozen canonical request. Prompt text never lives in D1 because prompts are immutable deployed artifacts pinned by hash, not editable rows (§9.5).

**Independent Test**: Provable by a build + golden + unit suite, with no provider, no D1 I/O for prompt text, and no network: drive the registry and composer with a fixture capability manifest and a filtered context payload, and assert, per case, that the pinned hash resolves, that an altered or missing artifact fails the build, that no prompt text is present in any D1 table, that the composed request matches the golden, that the output-format instruction tracks the output schema, that context is rendered as delimited typed data, that an embedded instruction does not act as an instruction (R-10), that the output constraints are present, and that the output carries no provider-shaped field (§3.11.4, row D1; §3.10).

**Acceptance Scenarios**:

1. **Given** a capability manifest whose Prompt binding pins a prompt artifact by hash, **When** the registry resolves that pin at build time, **Then** the hash resolves to its deployed artifact and the composer can read it. *(manifest-pinned hash resolves to its artifact)*
2. **Given** a pinned prompt artifact, **When** the artifact's content is altered after the pin was recorded, **Then** the build fails. *(altered artifact fails the build)*
3. **Given** a manifest that pins a prompt artifact, **When** the pinned artifact is absent from the deployment, **Then** the build fails. *(missing artifact fails the build)*
4. **Given** the prompt registry deployed with the Worker, **When** the registry is inspected, **Then** no prompt text is present in any D1 table — prompts are immutable deployed assets, not D1 rows (§9.5). *(no prompt text in any D1 table)*
5. **Given** a resolved prompt artifact, **When** the composer runs for a request, **Then** the resolved prompt version (the pinned artifact's version) is surfaced for the journal row, so there is exactly one answer to "which prompt was live for this request?". *(prompt version recorded on the journal row)*
6. **Given** a fixture capability with a frozen manifest and a filtered context payload, **When** the composer assembles the canonical request, **Then** the composed request matches the golden fixture byte-for-byte. *(composed request matches the golden for a fixture capability)*
7. **Given** a capability whose Output field group declares an output schema, **When** the output schema changes (a new capability build), **Then** the derived output-format instruction changes accordingly — the format instruction is derived from the schema, not authored separately. *(changing the output schema changes the derived format instruction)*
8. **Given** a filtered context payload, **When** the composer renders it through the capability's template, **Then** context is rendered as delimited, typed data on its own footing, never merged into the instructions. *(context rendered as delimited typed data)*
9. **Given** a context payload that contains text attempting to act as an instruction, **When** the composer renders it, **Then** the embedded text does not act as an instruction — it is data, not command (R-10). *(an instruction embedded in context does not act as an instruction)*
10. **Given** a capability manifest declaring output constraints, **When** the composer assembles the request, **Then** max tokens, stop conditions, and language constraints are present on the canonical request. *(max tokens, stop conditions, and language constraints present)*
11. **Given** a composed canonical request, **When** it is inspected, **Then** it contains no provider-shaped field — nothing upstream of the adapters may carry a provider's wire shape (§5.3). *(no provider-shaped field in the output)*
12. **Given** a composition that fails (e.g. an artifact that cannot be parsed), **When** stage 10 fails, **Then** the request is rejected with `internal_error` and no provider is invoked. *(the only runtime code stage 10 emits)*

### Test plan

Layers follow the architecture's testing strategy (§13.5). Registry cases are **Build + contract** (the build-time pin and the no-prompt-text-in-D1 invariant); composer cases are **Unit (golden)** (deterministic composition against a fixture); the R-10 injection case is a **Pipeline test** (guard-rejection-style assertion that an embedded instruction does not command the model). Per delivery plan §3.11.4, row D1 is "Build + golden + unit".

| # | Named test | Asserts |
| --- | --- | --- |
| T1 | `registry_pinned_hash_resolves_to_artifact` | a manifest-pinned hash resolves to its deployed artifact (§4.3.6, §5.7) |
| T2 | `registry_altered_artifact_fails_build` | altering a pinned artifact's content fails the build (§4.3.6, §5.7) |
| T3 | `registry_missing_artifact_fails_build` | a pinned but absent artifact fails the build (§4.3.6) |
| T4 | `registry_no_prompt_text_in_any_d1_table` | no prompt text is present in any D1 table; prompts are deployed assets, not rows (§9.5) |
| T5 | `registry_prompt_version_surfaced_for_journal` | the resolved prompt artifact version is surfaced for the journal row (§4.3.6, §4.3.11) |
| T6 | `composer_matches_golden_for_fixture_capability` | the composed canonical request matches the golden fixture (§4.3.6, §5.3) |
| T7 | `composer_format_instruction_tracks_output_schema` | changing the output schema changes the derived format instruction (§4.3.6, §5.1 Output) |
| T8 | `composer_renders_context_as_delimited_typed_data` | context is rendered as delimited typed data, never merged into instructions (§4.3.6, R-10) |
| T9 | `composer_embedded_instruction_does_not_act_as_instruction` | an instruction embedded in context is data, not command (R-10, §4.3.6) |
| T10 | `composer_output_constraints_present` | max tokens, stop conditions, and language constraints are present on the canonical request (§4.3.6, §5.3) |
| T11 | `composer_no_provider_shaped_field` | the composed request contains no provider-shaped field (§5.3) |
| T12 | `composer_failure_emits_internal_error` | a composition failure rejects with `internal_error` and invokes no provider (§5.4, §6.1 stage 10) |

Coverage of every error code the slice can emit (§3.10 item 2): `internal_error` (T12) — the only runtime taxonomy code stage 10 emits (§6.1). Build-time pin failures (T2, T3) are not runtime taxonomy codes; they fail the build before any request runs.

### Edge Cases

- **Error codes this slice can emit** (closed set, §5.4; stage 10 emits no other, §6.1): `internal_error` (500, retryable, consumes no quota). Build-time registry failures (missing/altered pinned artifact) are build failures, not runtime codes.
- **Prompt artifact immutability vs. edit**: an in-place edit to a published prompt artifact is a build failure, not a silent update — swapping a prompt is a new capability *build*, not a new capability version, as long as the output schema and behaviour contract hold (§5.7 Prompt artifact row). The slice enforces the pin at build time and performs no runtime mutation.
- **Output schema as single source of truth**: the output-format instruction, the provider's structured-output/JSON-mode configuration, and the response validator all derive from one output schema (§4.3.6). D1 derives the format instruction; the structured-output configuration is consumed by the adapter (D2/D5) and the validator by D6 — D1 must not author a separate format instruction or the classic prompt/validator mismatch returns.
- **Context as data, not command (R-10)**: free text that arrived from a clinical note and free text a clinician typed are on the same footing; neither may act as an instruction (§4.3.6, R-10). The composer draws no distinction between them and renders both as delimited typed data.
- **No prompt text in D1**: the rejected alternative — prompts as editable D1 rows — gets no code review, no diff history, no CI eval, and no reproducibility (§9.5). The registry is deployed with the Worker; D1 holds no prompt text in any D1 table.
- **No per-request server-side state**: composition is a pure function of (manifest, filtered context, user intent, output constraints) and holds nothing between requests (§4.4, §9.7). The registry is a build-time bundle, not a runtime store.
- **Conversational rendering is out of scope**: §4.3.6's conversational paragraph — rendering the supplied transcript as prior turns and offering the shared context-request schema as a second output shape — is band H (H2), not D1. D1 composes for a `single_shot` capability only; a `conversational` manifest is not composed by this slice.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Prompt artifacts MUST be immutable assets deployed with the Worker, and the version in force MUST be pinned by the capability manifest itself, so that one artifact, one pointer, and one answer to "which prompt was live?" exist (§4.3.6, §5.7 Prompt artifact row, §9.5).
- **FR-002**: The build MUST fail if a manifest-pinned prompt artifact is missing or altered, so that a prompt change is a reviewed, tested, reproducible deploy rather than a silent edit (§4.3.6, §5.7, §9.5).
- **FR-003**: No prompt text MUST be present in any D1 table; prompts are deployed assets pinned by hash, not editable D1 rows (§9.5).
- **FR-004**: The composer MUST assemble the canonical request from the system instruction artifact, the business-rule fragments the capability declares, the output-format instruction derived from the capability's output schema, the validated context payload rendered through the capability's template, the user intent, and the output constraints (max tokens, stop sequences, language, tone, refusal policy) (§4.3.6, §5.3).
- **FR-005**: The output-format instruction MUST be derived from the capability's output schema rather than authored separately, so the schema is the single source of truth for the format instruction, the provider's structured-output configuration, and the response validator (§4.3.6).
- **FR-006**: Context MUST be rendered as delimited, typed data and never merged into the instructions; free text from a clinical note and free text a clinician typed are on the same footing, and neither may act as an instruction (R-10) (§4.3.6, R-10).
- **FR-007**: The composed canonical request MUST contain no provider-shaped field; everything upstream of the adapters speaks only the canonical representation (§5.3).
- **FR-008**: The resolved prompt artifact version MUST be surfaced for the journal row, so the journal records which prompt was live for the request (§4.3.6, §4.3.11).
- **FR-009**: Stage 10 (prompt composition) MUST emit only `internal_error` on failure, and a composition failure MUST NOT invoke a provider (§5.4, §6.1 stage 10).
- **FR-010**: The composer MUST hold no per-request server-side state; composition is a pure function of its inputs and the registry is a build-time bundle (§4.4, §9.7).

### Key Entities *(include if feature involves data)*

Not applicable — this slice defines no D1 entities and no new contract types. It consumes the canonical inference representation (§5.3) and the manifest's Prompt binding and Output field groups (§5.1), and produces a canonical request in memory per request. Prompt artifacts are immutable deployed assets, not D1 rows (§9.5).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Prompts are logic deployed as immutable, reviewed, versioned artifacts pinned by the manifest — the property that makes a journal entry trustworthy during an incident at clinic scale (§4.3.6, §9.5). No enterprise-scale assumption is introduced; the registry is a build-time bundle with no runtime store, no queue, and no per-request state.
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker). It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. D1 performs no Supabase or D1 access for prompt text; the registry is deployed with the Worker and composition is CPU-only (§6.1 stage 10).
- **Data Integrity & Security**: The registry holds no prompt text in D1 and writes nothing to any store at request time; the only auditable signal D1 produces is the resolved prompt artifact version, which C3's journal records (§4.3.11). Prompt immutability is enforced at build time by the hash pin, so a journal entry pointing at a pinned version is reproducible — the property that makes the journal worth having (§9.5). No clinical data leaves the clinic; context is rendered as data, never merged into instructions (R-10).
- **Failure Handling**: This slice's only runtime failure is `internal_error` from a composition defect (§6.1 stage 10), which rejects the request before any provider is invoked. A missing or altered pinned artifact is a build failure, not a runtime degradation. The slice holds no per-request state and performs no I/O that can fail; there is no retry, cache, or fallback to specify here. Provider unreachability and quota exhaustion are handled by later stages (D3, B4) and are out of scope.

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **C1 (capability resolver, discovery)**: D1 consumes the resolved, immutable manifest; it does not resolve capability ids, honour version pins, or serve discovery. (§4.3.4)
- **C2 (context validator)**: D1 consumes the filtered context payload C2 produces; it does not validate context, enforce shapes, or run the cost pre-flight. (§4.3.5)
- **C3 (journal writer)**: D1 surfaces the resolved prompt artifact version for the journal row; it does not write the `ai_request` row, the attempt rows, the usage ledger, or the R2 envelope. (§4.3.11)
- **D2 (provider port, fake adapter, routing policy)**: D1 produces the canonical request; it does not define the provider port, classify failures, or compute the routing chain. (§4.3.8, §4.3.7)
- **D3 (invocation)**: D1 does not invoke a provider, retry, or fall back. (§4.3.7, §6.1 stage 11)
- **D6 (response validator, repair)**: D1 derives the output-format instruction from the output schema; the validator that consumes the schema and the bounded-repair behaviour are D6. (§4.3.9)
- **F1 (eval suite)**: D1 freezes prompts as immutable artifacts; the CI eval that blocks a regressing prompt change is F1. (§13.5, A9)
- **H2 (conversational transcript rendering)**: §4.3.6's conversational paragraph — rendering the supplied transcript as prior turns and offering the shared context-request schema as a second output shape — is band H. D1 composes for `single_shot` only. (§4.3.6 conversational paragraph, §6.7)
- **J3 (staged rollout / activation pointer)**: the deliberately deferred runtime activation pointer that would allow rollback without a deploy is J3; D1 pins prompts at build time only. (§9.5, §9.14)

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20). D1 adds no runtime activation pointer, no prompt caching, no retry, no abstraction beyond the registry and the composer.
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — D1 is a Worker slice and emits nothing into the client; the manifest never names a provider or model (§5.1).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — D1 performs no DO and no R2 I/O.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5) — D1 writes no D1 rows; the prompt version is surfaced to C3, not written by D1.
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

D1 invents no threshold, timeout, limit, or default beyond the manifest values and the canonical representation: max tokens, stop conditions, and language come from the manifest's Output and Input field groups (§5.1), and the canonical request shape is frozen by A3 (§5.3). Per-clinic prompt customization is not offered; if ever required it arrives as constrained, validated parameters injected into a reviewed template, never as free-text overrides (§9.5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A build + golden + unit suite proves a manifest-pinned hash resolves to its artifact, an altered pinned artifact fails the build, and a missing pinned artifact fails the build — the full `Done when` registry clause, each branch a named test.
- **SC-002**: A test proves no prompt text is present in any D1 table, and the resolved prompt artifact version is surfaced for the journal row — prompts are immutable deployed assets, not D1 rows (§9.5).
- **SC-003**: A golden test proves the composed canonical request matches the fixture byte-for-byte, and a second test proves changing the output schema changes the derived format instruction — the format instruction is derived from the schema, not authored separately (§4.3.6).
- **SC-004**: A test proves context is rendered as delimited typed data and an instruction embedded in context does not act as an instruction (R-10), and a test proves max tokens, stop conditions, and language constraints are present on the canonical request.
- **SC-005**: A test proves the composed canonical request contains no provider-shaped field, satisfying the §5.3 invariant that nothing upstream of the adapters may carry a provider's wire shape.
- **SC-006**: The slice emits exactly one runtime taxonomy code — `internal_error` — on a composition failure, with no provider invoked, satisfying the §3.10 item-2 coverage rule for stage 10 (§6.1).

## Assumptions

- The capability manifest's Prompt binding field group (system instruction artifact ref, business-rule fragment refs, context rendering template ref, output-format instruction derivation rule) and Output field group (mode, output schema ref) are frozen by A4 and resolvable by C1 before D1 runs; D1 reads a fully-resolved, immutable manifest object.
- The canonical inference representation is frozen by A3 (§5.3); D1 assembles into the canonical request element and does not redefine its fields.
- The filtered, declaration-conformant context payload is produced by C2 (§4.3.5); D1 renders it through the capability's template and does not re-validate keys or shapes.
- The error taxonomy is frozen by A2 (§5.4); D1 consumes `internal_error` for stage 10 failure and adds no code.
- The first capability follows Open Decision 1's recommended default — one non-clinical-record capability, `prose` output, `advisory_display` acceptance — so the fixture manifest D1 composes against implies no clinical-record write path and no F2 prerequisite (§15 OD1).
- Prompt artifacts are deployed with the Worker as immutable assets; D1 introduces no D1, DO, R2, or provider I/O for prompt text, and no per-request server-side state (§6.1 stage 10, §9.5).
