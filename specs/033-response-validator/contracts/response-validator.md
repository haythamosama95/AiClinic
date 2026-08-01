# Response validator, bounded repair, and structured output modes (D6)

Frozen contracts for ordered response validation, policy-gated bounded repair, and
`structured` / `structured_atomic` streaming-mode emission under commit-time validation.
Later slices **H2** (composer/validator for conversational answers) and **E4** (provisional-draft
UX) **consume** this artifact — they must not reorder or skip validation phases, introduce
unbounded repair or return invalid content, or weaken structured-mode emission invariants
(provisional vs committed; self-contained terminal payload).

**Source of truth in code (this slice):** `ai-platform/src/validate/` (phases + repair),
extended `ai-platform/src/stream/index.ts` (structured emission).

**Traces to:** spec Freezes (phase order; bounded repair; structured / structured_atomic modes);
FR-001–FR-014; architecture §4.3.9, §6.4, §5.1.

---

## 1. Overview

After D4's stream broker has relayed a complete generation (or while streaming structured content),
the gateway validates assembled output in a fixed phase order and never emits invalid content as the
accepted answer. Where the capability's Output repair policy allows it, the validator may perform a
single budgeted re-ask with validation errors appended, capping, counting, and journaling attempts;
exhaustion fails with `validation_failed`. For `structured` capabilities the broker emits provisional
`partial_structured` events during the stream and puts the whole validated document only on the
terminal `completed` event; for `structured_atomic` it emits progress/heartbeat only, with the same
completion semantics (§4.3.9; §6.4; §5.1 Output).

D4 owns relay, heartbeats, one-terminal-event, `prose` incremental guards, and connection-scoped
cancel. D6 owns post-assembly validation, repair, and the two structured §6.4 rows.

---

## 2. Response validator phase order

**Module:** `ai-platform/src/validate/phases.ts` (phases); orchestration in `validate/index.ts`.

Phases run **strictly in this order**. An earlier-phase failure is the reported first failure; later
phases are not reordered ahead of it (FR-001; T10).

| Order | Phase | Behaviour |
| --- | --- | --- |
| 1 | Transport / parse validity | Assembled output must be transport-valid and parseable for the capability's output mode (FR-001; T2) |
| 2 | Schema conformance | Parsed output must conform to the capability's `outputSchemaRef` (FR-001, FR-012; T3; §5.1 Output) |
| 3 | Declared business constraints | Checks the capability declares via `businessValidationRuleRefs`, from among: enumerations restricted to the clinic's own vocabulary; referential sanity against the supplied context; numeric ranges; required-section presence (FR-002; T4; §4.3.9) |
| 4 | Safety guards | Leaked system instructions; refusals; empty output; truncated output; prompt-injection echo — empty and truncated are separate cases (FR-001; T5–T9; §4.3.9) |

| Rule | Detail |
| --- | --- |
| Valid path | Output that passes all four phases may be carried on the terminal `completed` event (T1) |
| Invalid never returned | On any validation failure path, invalid content is never emitted as the accepted or terminal success payload (FR-007; T11) |
| Manifest-sourced | Output mode, schema ref, business rule refs, and repair policy are read from the capability manifest Output group; the validator does not hard-code provider or model identity (FR-012; §5.1) |
| Schema / rule resolution (this slice) | Tests register schema and rule runners in **in-memory registries** keyed by manifest refs; this slice does not introduce an on-disk schema/rule store (Clarification Q3) |

Later slices may extend which rules a capability may declare; they must not reorder or skip these
phases (Freezes).

---

## 3. Bounded repair contract

**Module:** `ai-platform/src/validate/index.ts`

| Rule | Detail |
| --- | --- |
| Policy gate | Whether repair is allowed is a per-capability manifest decision (`Output.repairPolicy.allowed`), not a global one (FR-004; §4.3.9; §5.1) |
| Re-ask shape | When allowed, the validator may attempt a **single budgeted re-ask** with the validation errors appended (FR-003; T12) |
| Invocation port | Repair is invoked through an injected `reask(errors) => Promise<assembled output>` port so D6 owns the attempt without rewriting D3's invocation/retry/fallback loop (Clarification Q2; Out of Scope D3) |
| Cap | Attempts are capped by `Output.repairPolicy.maxAttempts`; this slice does not invent a numeric default (FR-003; T15; Assumptions) |
| Count + journal | Each repair attempt is counted and journaled (FR-003; T15). Production journaling remains C3; this slice feeds injectable attempt/journal sinks |
| Cost | Repair generation cost is counted against the request (FR-006; T16) |
| Disallowed | Immediate terminal failure with `validation_failed`; no re-ask (FR-005; T13) |
| Exhausted / still invalid | Terminal failure with `validation_failed`; invalid content is not returned (FR-005; T14; Done when) |
| Error code | Uses existing A2 taxonomy code `validation_failed`; this slice does not add or rename taxonomy codes (Edge Cases; Assumptions) |

Later slices must not introduce unbounded repair or return invalid content (Freezes).

### 3.1 Injectable dependencies (implementation surface, not new architecture)

| Dependency | Role |
| --- | --- |
| `reask(errors)` port | Returns a new assembled output for re-validation; tests script invalid-then-valid or always-invalid (Clarification Q2) |
| Schema registry | Map `outputSchemaRef` → conformance runner (in-memory in this slice; Clarification Q3) |
| Business-rule registry | Map each `businessValidationRuleRefs` entry → rule runner (in-memory; Clarification Q3) |
| Repair-attempt / journal sink | Records capped attempts for later C3 persistence (unchanged C3 contract) |
| Repair-cost / usage sink | Counts repair cost against the request (FR-006) |

---

## 4. Structured and structured_atomic streaming modes

**Module:** extended `ai-platform/src/stream/index.ts` (D4 broker duties preserved).

| Mode | During stream | At completion |
| --- | --- | --- |
| `structured` | Emit `partial_structured` events derived from incremental parsing; **every** such event is flagged provisional (FR-008; T17; §6.4) | Complete document validated (schema + business rules via the validator); terminal `completed` carries the **whole** validated document (FR-008; T18) |
| `structured_atomic` | Progress / heartbeat only — **no** provisional structured document chunks (FR-009; T19; §6.4) | Same validation and terminal payload rules as `structured` (FR-009) |

| Invariant | Detail |
| --- | --- |
| Authoritative terminal | Validated terminal payload is self-contained and authoritative; clients must not assemble the final result from chunks; a client that ignores all non-terminal events still receives the correct result (FR-010; T20–T21; §6.4 invariant 1) |
| Provisional never committed | Provisional `partial_structured` content is never treated as the committed result at the emission boundary this slice owns — never persisted, exported, or entered into a clinical record here (FR-011; T23; §6.4 invariant 2). Client commit affordances remain E4 |
| One terminal | Structured paths still end with exactly one terminal event under D4's one-terminal-event duty (Consumes D4) |
| Prose unchanged | D4 `prose` relay, incremental guards, and cancel path remain intact; D6 does not rewrite them (FR-013; T24; Consumes) |

D4 already froze the `prose` row and broker relay/heartbeat/one-terminal/cancel duties. This slice
freezes the two structured rows and the shared §6.4 invariants as they apply to structured emission.

---

## 5. Explicit prohibitions

| Not allowed | Why frozen here |
| --- | --- |
| Reorder or skip validation phases | Freezes phase order (§4.3.9; FR-001) |
| Unbounded repair / return invalid content | Freezes repair discipline (FR-003–FR-007; Done when) |
| Per-request server-side state for validator, repair, or structured paths | §4.4, §9.7; delivery plan §6.4; FR-014; T22 |
| Client assembly of final result from chunks | §6.4 invariant 1; FR-010; T21 |
| Committable provisional structured content at emission | §6.4 invariant 2; FR-011; T23 |
| Rewrite D4 prose / cancel / relay / heartbeat / one-terminal contracts | Consumes D4; FR-013; delivery plan §2.3; T24 |
| Second Quota DO round trip or second R2 object per request | delivery plan §6.4; §7.5, §13.6 |
| D1 row per stream chunk | delivery plan §6.4; §7.5 |
| Mechanism from §9.14 because it looks prudent | R-20; delivery plan §6.4 |

---

## 6. Consumers

| Slice | Binding |
| --- | --- |
| **H2** | Conversational composer/validator and context-request as a second permitted output shape — must honour phase order and repair discipline |
| **E4** | Client provisional-draft UX and commit affordances — must treat provisional structured events as non-authoritative; terminal payload is the answer |

---

## 7. Out of scope (neighbouring owners)

| Concern | Owner |
| --- | --- |
| Stream broker relay, heartbeats, one-terminal, `prose` guards, connection-scoped cancel | D4 |
| Invocation retry / fallback / regenerating | D3 |
| Prompt artifacts / composer | D1 |
| Real provider adapters | D5 / D7 |
| Manifest schema / resolver | A4 / C1 |
| Journal D1 / R2 writes | C3 |
| Client provisional UX / commit | E4 |
| Conversational interaction mode | H1 / H2 |
| Capability eval harnesses | F1 |
