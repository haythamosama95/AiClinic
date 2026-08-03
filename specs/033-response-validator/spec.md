# Feature Specification: Response validator, bounded repair, and structured output modes

**Feature Branch**: `ai/033-d6-response-validator`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `D6` — "Response validator, bounded repair, and structured output modes" (delivery plan §3.5, band D).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.5, row D6):

> §4.3.9, §6.4, §5.1

### Freezes

Contracts this slice establishes for the first time:

- The **response validator phase order**: transport/parse validity → schema conformance → business-constraint checks the capability declares → safety guards (leaked system instructions, refusals, empty or truncated output, prompt-injection echo), applied strictly in that order (§4.3.9). Later slices may extend which rules a capability may declare; they must not reorder or skip these phases.
- The **bounded repair contract**: on validation failure, a single budgeted re-ask with the validation errors appended is attempted only where the capability's repair policy allows it; repair attempts are capped (per the manifest's repair-policy max attempts), counted, and journaled; exhaustion produces the typed error `validation_failed` and invalid content is never returned (§4.3.9; §5.1 Output repair policy; delivery plan §3.5 Done when). Later slices must not introduce unbounded repair or return invalid content.
- The **`structured` and `structured_atomic` streaming modes** under commit-time validation: `structured` emits `partial_structured` events every one of which is flagged provisional, with the terminal `completed` event carrying the whole validated document; `structured_atomic` emits progress/heartbeat only, with the same completion semantics as `structured`; the validated terminal payload is authoritative and self-contained and is never assembled from chunks (§6.4). D4 already froze the `prose` row and broker relay/heartbeat/one-terminal-event duties; this slice freezes the two structured rows and the shared invariants as they apply to structured emission. Client UI commit affordances remain E4.

### Consumes

Contracts frozen by the slices in `Needs` (D4). Changing any of these is out of scope by definition:

- **From D4 (stream broker, prose streaming, and cancellation)**: the stream broker that relays normalized chunks, emits heartbeats, enforces provisional-versus-committed semantics, and ends every stream with exactly one terminal event; the `prose` path with incremental cheap guards and completion-time full guard set; connection-scoped cancellation via abort signal with partial-usage credit and no per-request server-side state (§4.3.10, §6.4 `prose` row, §5.5, §6.5, §9.7 Freezes in D4). D6 extends what the broker may carry for `structured` / `structured_atomic` and owns post-assembly validation and repair; it must not rewrite relay, heartbeat, one-terminal-event, prose incremental guards, or cancel duties.

### Open decisions relied on

None. D6's validator ordering, bounded repair, and structured output modes are fully specified by §4.3.9, §6.4, and §5.1 Output; no §15 recommended default is assumed.

## Clarifications

### Session 2026-08-02

- Q: Where should the response validator, bounded repair, and structured-mode emission live under `ai-platform/src/`? → A: New `src/validate/` for ordered phases + bounded repair; extend existing `src/stream/` for `structured` / `structured_atomic` emission `[implementation choice — no §citation]`
- Q: How should bounded repair re-ask (T12–T16) be invoked so D6 owns the attempt without rewriting D3’s invocation/retry/fallback loop? → A: Validator accepts an injected `reask(errors) => Promise<assembled output>` port; tests script invalid-then-valid (or always-invalid) outcomes; production later wires the port to invocation `[implementation choice — no §citation]`
- Q: How should `outputSchemaRef` and `businessValidationRuleRefs` resolve for D6’s validator suite (T3–T4 and structured completion) without inventing a platform-wide schema/rule store ahead of a real structured capability? → A: In-memory test registries: tests register schema + rule runners keyed by the manifest refs; no on-disk schema/rule tree in this slice `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Response validator, bounded repair, and structured output modes (Priority: P1)

As the AI Gateway Worker, after the stream broker has relayed a complete generation (D4), I validate the assembled output in fixed order — transport/parse validity, schema conformance, declared business constraints, then safety guards — and I never emit invalid content. Where the capability's repair policy allows it, I attempt one budgeted re-ask with the validation errors appended, capping, counting, and journaling attempts; on exhaustion I fail with `validation_failed`. For `structured` capabilities I emit provisional `partial_structured` events during the stream and put the whole validated document only on the terminal `completed` event; for `structured_atomic` I emit progress/heartbeat only, with the same self-contained terminal payload.

**Why this priority**: D6 sits where it does because its `Needs` (D4) are the point at which normalized chunks are relayed, heartbeats keep the stream alive, and commit-time validation on assembled text is already in the pipeline for `prose` — without those, the validator would invent broker behaviour or assemble mid-stream. Later slices H2 (composer/validator for conversational answers and context requests) and E4 (provisional-draft UX) depend on ordered validation, repair discipline, and structured-mode emission rules (delivery plan §3.5).

**Independent Test**: Provable by a unit (ordering) plus integration suite: valid output passes; parse failure; schema violation; one case per declared business rule; one case per safety guard (leaked instruction, refusal, empty, truncated, injection echo); the four phases run in the stated order; invalid content is never emitted; repair allowed → one re-ask with errors appended → success; repair disallowed → immediate `validation_failed`; repair fails → `validation_failed`; the attempt cap is enforced and journaled; repair cost is counted against the request; `structured` emits `partial_structured` events all flagged provisional with the terminal event carrying the whole validated document; `structured_atomic` emits progress only; a client ignoring all chunks still receives the correct result; the terminal payload is not assembled from chunks (delivery plan §3.11.4 row D6; §3.10; Done when).

**Acceptance Scenarios**:

1. **Given** a complete provider output that is transport-valid, schema-conformant, business-valid, and passes every safety guard, **When** the response validator runs, **Then** the output passes and may be carried on the terminal `completed` event. *(valid output passes)*
2. **Given** a complete provider output that fails transport/parse validity, **When** the response validator runs, **Then** validation fails at the transport/parse phase and invalid content is not emitted. *(parse failure)*
3. **Given** a complete provider output that parses but violates the capability's output schema, **When** the response validator runs, **Then** validation fails at the schema-conformance phase and invalid content is not emitted. *(schema violation)*
4. **Given** a complete provider output that violates a declared business constraint (one acceptance case per declared business-rule category the capability under test uses — enumerations restricted to the clinic's own vocabulary, referential sanity against the supplied context, numeric ranges, required-section presence), **When** the response validator runs, **Then** validation fails at the business-constraint phase and invalid content is not emitted. *(one case per declared business rule)*
5. **Given** a complete provider output that leaks system instructions, **When** the safety-guard phase runs, **Then** validation fails and invalid content is not emitted. *(safety guard — leaked instruction)*
6. **Given** a complete provider output that is a model refusal, **When** the safety-guard phase runs, **Then** validation fails and invalid content is not emitted. *(safety guard — refusal)*
7. **Given** a complete provider output that is empty, **When** the safety-guard phase runs, **Then** validation fails and invalid content is not emitted. *(safety guard — empty)*
8. **Given** a complete provider output that is truncated, **When** the safety-guard phase runs, **Then** validation fails and invalid content is not emitted. *(safety guard — truncated)*
9. **Given** a complete provider output that echoes a prompt-injection payload, **When** the safety-guard phase runs, **Then** validation fails and invalid content is not emitted. *(safety guard — injection echo)*
10. **Given** a fixture constructed so that an earlier phase and a later phase would both fail if both ran, **When** the response validator runs, **Then** failure is reported from the earlier phase and later phases are not treated as the first failure — proving transport/parse → schema → business → safety order. *(the four phases run in the stated order)*
11. **Given** any validation failure path in this slice, **When** the request terminates, **Then** invalid content is never emitted on a terminal success path and is never returned as the accepted payload. *(invalid content is never emitted)*
12. **Given** a capability whose repair policy allows repair and an output that fails validation once then succeeds after re-ask, **When** repair runs, **Then** exactly one budgeted re-ask is performed with the validation errors appended and the request completes successfully. *(repair allowed → one re-ask with errors appended → success)*
13. **Given** a capability whose repair policy disallows repair and an output that fails validation, **When** the validator finishes, **Then** the request fails immediately with `validation_failed` and no re-ask is attempted. *(repair disallowed → immediate validation_failed)*
14. **Given** a capability whose repair policy allows repair and a re-ask that still fails validation, **When** repair exhausts, **Then** the request fails with `validation_failed` and invalid content is not returned. *(repair fails → validation_failed)*
15. **Given** a capability whose repair policy declares a max-attempts cap, **When** repair is driven to that cap, **Then** the cap is enforced, each attempt is journaled, and exhaustion produces `validation_failed`. *(the attempt cap is enforced and journaled)*
16. **Given** a request that performs a repair re-ask, **When** usage is settled, **Then** the repair cost is counted against the request. *(repair cost is counted against the request)*
17. **Given** a `structured` capability whose provider emits incrementally parseable structured content, **When** the stream runs, **Then** `partial_structured` events are emitted and every one is flagged provisional. *(structured emits partial_structured events all flagged provisional)*
18. **Given** a `structured` capability whose complete document passes validation, **When** the terminal event is emitted, **Then** that event is `completed` and carries the whole validated document. *(terminal event carries the whole validated document)*
19. **Given** a `structured_atomic` capability, **When** the stream runs before completion, **Then** only progress/heartbeat events are emitted (no provisional structured document chunks). *(structured_atomic emits progress only)*
20. **Given** a successful `structured` or `structured_atomic` request, **When** a client ignores every non-terminal event, **Then** that client still receives the correct validated result from the terminal payload alone. *(a client ignoring all chunks still receives the correct result)*
21. **Given** any successful structured-mode completion in this slice, **When** the terminal payload is inspected, **Then** it is self-contained and is not assembled from stream chunks. *(the terminal payload is not assembled from chunks)*

### Test plan

Layer: Unit (ordering) + integration (delivery plan §3.11.4, row D6; §13.5 Pipeline tests with fake provider). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `valid_output_passes` | Unit / integration | Valid output passes validation (§3.11.4 D6; §4.3.9; Done when) |
| T2 | `parse_failure` | Unit | Transport/parse failure (§3.11.4 D6; §4.3.9) |
| T3 | `schema_violation` | Unit | Schema conformance failure (§3.11.4 D6; §4.3.9; §5.1 Output schema ref) |
| T4 | `business_rule_violation` | Unit | One case per declared business-rule category under test (§3.11.4 D6; §4.3.9; §5.1 business validation rule refs) |
| T5 | `safety_guard_leaked_instruction` | Unit | Leaked system instructions (§3.11.4 D6; §4.3.9) |
| T6 | `safety_guard_refusal` | Unit | Refusals (§3.11.4 D6; §4.3.9) |
| T7 | `safety_guard_empty` | Unit | Empty output (§3.11.4 D6; §4.3.9) |
| T8 | `safety_guard_truncated` | Unit | Truncated output (§3.11.4 D6; §4.3.9) |
| T9 | `safety_guard_injection_echo` | Unit | Prompt-injection echo (§3.11.4 D6; §4.3.9) |
| T10 | `four_phases_run_in_stated_order` | Unit (ordering) | Transport/parse → schema → business → safety (§3.11.4 D6; §4.3.9) |
| T11 | `invalid_content_never_emitted` | Unit / integration | Invalid content never returned on success path (§3.11.4 D6; Done when; §3.10) |
| T12 | `repair_allowed_one_reask_success` | Integration | Repair allowed → one re-ask with errors appended → success (§3.11.4 D6; §4.3.9; §5.1 repair policy) |
| T13 | `repair_disallowed_immediate_validation_failed` | Integration | Repair disallowed → immediate `validation_failed` (§3.11.4 D6; §4.3.9; §5.1) |
| T14 | `repair_fails_validation_failed` | Integration | Repair re-ask still invalid → `validation_failed` (§3.11.4 D6; §4.3.9; Done when) |
| T15 | `repair_attempt_cap_enforced_and_journaled` | Integration | Manifest max-attempts cap enforced and journaled (§3.11.4 D6; §4.3.9; §5.1) |
| T16 | `repair_cost_counted_against_request` | Integration | Repair cost counted against the request (§3.11.4 D6; §4.3.9; Done when) |
| T17 | `structured_partial_events_provisional` | Integration | `partial_structured` events all flagged provisional (§3.11.4 D6; §6.4) |
| T18 | `structured_terminal_carries_whole_validated_document` | Integration | Terminal `completed` carries whole validated document (§3.11.4 D6; §6.4) |
| T19 | `structured_atomic_progress_only` | Integration | `structured_atomic` emits progress/heartbeat only (§3.11.4 D6; §6.4) |
| T20 | `client_ignoring_chunks_still_correct` | Integration | Client ignoring all chunks still receives correct terminal result (§3.11.4 D6; §6.4 invariant 1) |
| T21 | `terminal_payload_not_assembled_from_chunks` | Integration | Terminal payload self-contained; not assembled from chunks (§3.11.4 D6; §6.4 invariant 1; Done when) |
| T22 | `no_per_request_state_for_repair_or_structured` | Integration (spy) | No per-request server-side state introduced by validator/repair/structured paths (§4.4, §9.7; delivery plan §6.4 prohibition; §3.10) |
| T23 | `provisional_structured_not_committable_on_emission` | Integration | Provisional `partial_structured` content is never treated as the committed result (§6.4 invariant 2 as applied to emission; delivery plan §6.4; §3.10) |
| T24 | `prose_path_unchanged_by_this_slice` | Integration (spy) | D4 `prose` relay/incremental-guard/cancel contracts remain intact; D6 does not rewrite them (Consumes D4; §3.10) |

---

### Edge Cases

- **Error codes this slice can emit.** Exhaustion of validation (with or without repair) produces `validation_failed` (delivery plan §3.5 Done when; §3.11.4 D6). This slice does not invent taxonomy codes; `validation_failed` is the typed terminal failure named by the Done when cell and already present in the closed taxonomy (A2). Other taxonomy codes remain owned by their freezing slices.
- **Transport/parse failure.** Fail at phase 1; do not emit invalid content; proceed to repair only if the manifest allows it (T2, T11–T14; §4.3.9).
- **Schema violation.** Fail at phase 2 against the capability's output schema ref (§5.1 Output); invalid content not emitted (T3, T11).
- **Declared business constraints.** Categories named in §4.3.9: enumerations restricted to the clinic's own vocabulary, referential sanity against the supplied context, numeric ranges, required-section presence. One case per declared rule under test (T4). This slice does not invent clinic-specific vocabularies or numeric thresholds beyond what the capability's declared rule refs supply.
- **Safety guards.** Four named guards: leaked system instructions, refusals, empty or truncated output, prompt-injection echo (T5–T9; §4.3.9). Empty and truncated are separate cases.
- **Phase ordering.** An earlier-phase failure is the reported first failure; later phases are not reordered ahead of it (T10; §4.3.9).
- **Repair disallowed.** Immediate `validation_failed`; no re-ask (T13; §4.3.9; §5.1 repair policy `allowed`).
- **Repair allowed but failing.** One budgeted re-ask with validation errors appended; on continued failure, `validation_failed`; invalid content never returned (T12, T14; §4.3.9; Done when).
- **Attempt cap.** Manifest repair-policy max attempts is enforced, counted, and journaled; exhaustion → `validation_failed` (T15; §4.3.9; §5.1). This slice does not invent a numeric default for max attempts.
- **Repair cost.** Repair generation is counted against the request (T16; §4.3.9; Done when) — an unbounded repair loop would be an unbounded bill.
- **`structured` provisional events.** Every `partial_structured` event is flagged provisional; clients must not treat them as authoritative (T17, T23; §6.4).
- **`structured_atomic`.** Progress/heartbeat only during stream; same completion validation as `structured` (T19; §6.4).
- **Authoritative terminal payload.** Self-contained; never assembled from chunks; a client that ignores streaming is fully correct (T18, T20, T21; §6.4 invariant 1).
- **Provisional never committed.** Provisional structured content is never persisted, exported, or entered into a clinical record — enforced on emission here; client commit affordances remain E4 (T23; §6.4 invariant 2).
- **No per-request state.** Validator, repair, and structured emission create no per-request server-side state object (T22; delivery plan §6.4 / §4.4, §9.7).
- **Prose path.** Owned by D4; this slice must not rewrite D4's `prose` incremental guards or cancel path (T24; Consumes).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The response validator MUST apply checks in this order: transport/parse validity → schema conformance → business-constraint checks the capability declares → safety guards (leaked system instructions, refusals, empty or truncated output, prompt-injection echo) (§4.3.9).
- **FR-002**: Declared business-constraint checks MUST include the categories the capability declares from among: enumerations restricted to the clinic's own vocabulary, referential sanity against the supplied context, numeric ranges, and required-section presence (§4.3.9; §5.1 Output business validation rule refs).
- **FR-003**: On validation failure, when the capability's repair policy allows repair, the validator MAY attempt a single budgeted re-ask with the validation errors appended; repair attempts MUST be capped per the manifest repair-policy max attempts, MUST be counted, and MUST be journaled (§4.3.9; §5.1 Output repair policy).
- **FR-004**: Whether repair is allowed MUST be a per-capability manifest decision (repair policy), not a global one (§4.3.9; §5.1 Output).
- **FR-005**: When repair is disallowed, or when the repair budget/cap is exhausted without a valid output, the request MUST fail terminally with `validation_failed` and MUST NOT return invalid content (§4.3.9; delivery plan §3.5 Done when).
- **FR-006**: Repair cost MUST be counted against the request (§4.3.9; delivery plan §3.5 Done when).
- **FR-007**: Invalid content MUST never be emitted as the accepted or terminal success payload (§4.3.9; delivery plan §3.5 Done when; §6.4 invariant 1 as applied to emission).
- **FR-008**: For output mode `structured`, the stream MUST emit `partial_structured` events derived from incremental parsing, and every such event MUST be flagged provisional; at completion the complete document MUST be validated against schema and business rules and the terminal `completed` event MUST carry the whole validated document (§6.4; §5.1 Output mode).
- **FR-009**: For output mode `structured_atomic`, the stream MUST emit progress/heartbeat only (no provisional structured document chunks); at completion validation and the terminal payload MUST follow the same rules as `structured` (§6.4; §5.1 Output mode).
- **FR-010**: The validated terminal payload MUST be authoritative and self-contained; clients MUST NOT be required to assemble the final result from chunks; a client that ignores streaming MUST still receive the correct result from the terminal event alone (§6.4 invariant 1).
- **FR-011**: Provisional content emitted during structured streaming MUST NOT be treated as the committed result; provisional content is never persisted, exported, or entered into a clinical record at the emission boundary this slice owns (§6.4 invariant 2 as applied to emission).
- **FR-012**: Output mode (`prose` / `structured` / `structured_atomic`), output schema ref, business validation rule refs, and repair policy (allowed, max attempts) MUST be read from the capability manifest Output field group; the validator and stream broker consume those fields and MUST NOT hard-code provider or model identity (§5.1 Output; §5.1 "A manifest never names a provider or a model").
- **FR-013**: This slice MUST NOT rewrite D4's stream-broker relay, heartbeat, one-terminal-event, `prose` incremental-guard, or connection-scoped cancellation contracts; it extends structured-mode emission and owns post-assembly validation and repair only (Consumes D4; delivery plan §2.3).
- **FR-014**: Validator, repair, and structured-mode paths MUST NOT introduce per-request server-side state of any kind (§4.4, §9.7 via delivery plan §6.4 prohibitions).

### Key Entities

Not applicable — this slice defines no entities. It validates and optionally repairs using the capability manifest Output fields (A4/§5.1), existing canonical result/error types (A3), and the D4 stream broker; it adds no D1 tables or new contract entity types.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Ordered validation and capped repair keep invalid or unsafe drafts from reaching clinicians and keep repair from becoming an unbounded bill — appropriate for small-to-mid multi-branch clinics on modest hardware (§4.3.9). Structured modes let capabilities choose live provisional skeletons (`structured`) or progress-only (`structured_atomic`) when a partial draft would be clinically misleading (§6.4), without hospital-scale orchestration.
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker). It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. Prompt text, provider names, and model identifiers must never enter the Flutter client (R-12); this Worker slice does not place them there.
- **Data Integrity & Security**: Invalid content is never returned (§4.3.9; Done when). Safety guards cover leaked instructions, refusals, empty/truncated output, and injection echo (§4.3.9). Provisional structured events are flagged and non-authoritative; only the validated terminal payload is the answer (§6.4). Repair attempts are journaled and cost-counted so spend remains explainable (§4.3.9). Clinical persistence of provisional content remains forbidden on the client (E4) and by emission rules here (§6.4 invariant 2).
- **Failure Handling**: Validation failure with repair disallowed or exhausted yields `validation_failed` with no invalid content returned (§4.3.9; Done when). Structured streams still end with exactly one terminal event under D4's one-terminal-event invariant. AI remains additive: clinic workflows continue without depending on a successful generation (constitution principle V; A11).

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **D4 (stream broker / prose / cancellation)**: D6 consumes relay, heartbeats, one-terminal-event, `prose` incremental guards, and connection-scoped cancel; it does not redefine them. The §6.4 `prose` row remains D4's Freezes.
- **D3 (invocation / retry / fallback)**: Repair re-ask is a validator-owned budgeted attempt, not a D3 provider-fallback walk; D6 does not change retry/fallback policy or regenerating behaviour.
- **D1 (prompt registry / composer)**: Output-format instruction derivation and prompt artifact pinning remain D1; D6 validates the assembled result against schema and rules the manifest names.
- **D5 / D7 (real provider adapters)**: D6 runs against the fake (and any adapter behind the port) via D3/D4; live wire fixtures remain D5/D7.
- **A4 / C1 (manifest schema / resolver)**: D6 consumes the Output field group (mode, schema ref, business rule refs, repair policy); it does not change the manifest schema or resolver.
- **C3 (journal writer / get-request)**: D6 requires repair attempts to be journaled and terminal `validation_failed` / `completed` outcomes to be recordable; writing `ai_request` / `ai_attempt` / R2 remains C3.
- **E4 (first AI surface)**: Client provisional-draft UX, commit affordances, and degraded mode are E4; D6 enforces emission and validation rules only.
- **H1 / H2 (conversational manifest / transcript validation)**: Conversational interaction mode, context-request as a second permitted output shape, and conversation budgets are out of scope; D6 freezes single-shot structured validation and repair.
- **F1 (evals)**: Capability eval harnesses remain F1.

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — D6 is a Worker slice.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Unit/integration tests prove valid output passes and each failure class (parse, schema, business rules, five safety guards) fails without emitting invalid content (T1–T9, T11; Done when).
- **SC-002**: A unit (ordering) test proves the four validation phases run in the stated order (T10; Done when).
- **SC-003**: Integration tests prove repair allowed → one re-ask with errors appended → success; repair disallowed → immediate `validation_failed`; repair failure → `validation_failed` (T12–T14; Done when).
- **SC-004**: An integration test proves the repair attempt cap is enforced and journaled (T15; Done when).
- **SC-005**: An integration test proves repair cost is counted against the request (T16; Done when).
- **SC-006**: Integration tests prove `structured` emits provisional `partial_structured` events and the terminal event carries the whole validated document (T17–T18; Done when).
- **SC-007**: An integration test proves `structured_atomic` emits progress only (T19; Done when).
- **SC-008**: Integration tests prove a client ignoring all chunks still receives the correct result and the terminal payload is not assembled from chunks (T20–T21; Done when).
- **SC-009**: Integration (spy) tests prove no per-request state, non-committable provisional structured emission, and unchanged D4 `prose` contracts (T22–T24; §3.10).

## Assumptions

- D4's stream broker, `prose` path, heartbeats, one-terminal-event invariant, and connection-scoped cancellation are available and unchanged; D6 extends structured-mode emission against that broker (Needs D4).
- The capability manifest Output field group — mode (`prose` / `structured` / `structured_atomic`), output schema ref, business validation rule refs, repair policy (allowed, max attempts) — is already loadable from the frozen A4 schema and resolvable via C1; this slice consumes those fields and does not redefine the manifest schema (§5.1).
- The typed error code `validation_failed` is already present in the closed A2 taxonomy; this slice uses it as named by the Done when cell and does not add or rename taxonomy codes.
- Numeric values for repair-policy max attempts and for individual business-rule thresholds are supplied by the capability's declared manifest/rule refs; this slice does not invent those constants (§4.3.9; §5.1).
- Journaling of repair attempts and terminal states uses C3's existing journal writer contracts; D6 produces the outcomes and attempt records C3 can persist.
- Client-side provisional-draft UX and commit affordances are E4; this slice owns Worker emission and validation rules only (§6.4 invariants as applied to emission).
- The platform does not ship until the whole product does (DP-1); "independently testable" means provable by an automated unit (ordering) + integration suite, not demonstrable to a user (DP-3).
