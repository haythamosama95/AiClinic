# Feature Specification: Conversational manifest fields and context-request schema

**Feature Branch**: `ai/044-h1-conversational-manifest-schema`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `H1` — "Conversational manifest fields and context-request schema" (delivery plan §3.8, band H).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.8, row H1):

> §5.1, §5.7, §6.7.4, §6.7.2, §5.5, §5.4, §6.3, A14

### Freezes

Contracts this slice establishes for the first time:

- The **conversational Interaction fields** on a capability manifest: when
  `interaction_mode` is `conversational`, the manifest MUST declare max history
  turns, max context rounds per turn, and transcript size limit as finite
  positive integers; those three fields are for `conversational` only and are
  rejected on a `single_shot` manifest (§5.1 Interaction row; A14).
- The **permitted key set** as the Context-requirements form for a
  `conversational` capability: the assistant may request keys only from that
  set during a turn; an empty set is legal; duplicate keys fail; a permitted
  key set naming an unknown key fails (§5.1 Context requirements row; A14).
- The rule that **interaction mode is fixed for the life of a capability
  version**: changing a capability between `single_shot` and `conversational`
  is a new capability version, never an in-place edit (§5.7 Interaction mode
  row).
- The **platform-owned context-request schema** shared by every conversational
  capability: a list of `{key, arguments}` drawn from the manifest's permitted
  set — not a per-capability schema (§6.7.2).
- The rule that **`context_requested` is a terminal event kind and not a
  taxonomy code**: it does not appear in the §5.4 error table; it is a terminal
  event kind alongside `completed`, for `conversational` capabilities only;
  A2's error-body builder is unchanged (unknown strings classify, never throw)
  (§5.4; §5.5 rule 4; §6.7.2).
- **`AwaitingContext` as a terminal, immutable request state**, reachable only
  for `conversational` capabilities (enforced on the journal write path): that
  request is over; the conversation continues as a new request with a new
  idempotency key (§6.3; §6.7.2).
- The **fourth terminal event kind** on the streaming protocol for
  `conversational` capabilities only: `context_requested` carrying a conforming
  context-request payload (validated at emission); a `single_shot` client can
  never receive that kind; the one-terminal-event invariant still holds (§5.5
  rule 4; §6.7.4).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (A2, A4, A6). Changing any is out of
scope by definition:

- **From A2 (diagnostic envelope)**: the closed §5.4 error taxonomy, error-body
  contract, request-reference format, and trace-id propagation. H1 consumes A2
  **unchanged**: `context_requested` is **absent** from that taxonomy (not a
  `TaxonomyCode`); forced / unknown string input classifies to `internal_error`
  without throwing from the error-body builder. H1 does not rewrite any existing
  code's HTTP mapping, retryability, or quota-consumption flag (§5.4; A2 Freezes).
- **From A4 (capability manifest schema and loader)**: the ten field groups, the
  loader contract (valid load / malformed fails build / in-place edit of a
  published version fails build), the `interaction_mode` default of
  `single_shot` when omitted, and the rule that conversational-only fields are
  rejected on a `single_shot` manifest. H1 extends the Interaction and
  Context-requirements groups with conversational field contents (finite
  positive integers) and the permitted key set (empty legal; duplicates
  rejected); it does not rewrite the ten-group schema, the default, or
  the presence/absence rejection rule A4 already froze (§5.1; §5.7; A4 Freezes).
- **From A6 (protocol adapter and SSE framing)**: the SSE framing with
  `accepted`, heartbeats, terminal kinds `completed` / `failed` / `cancelled`,
  and the one-terminal-event invariant. A6 explicitly reserved the fourth kind
  `context_requested` for H1 to extend; H1 adds that kind for `conversational`
  only, validates the context-request payload at emission, and does not rewrite
  the three existing kinds or the invariant (§5.5; A6 Freezes).

### Open decisions relied on

None — H1 freezes the conversational manifest fields, the shared
context-request schema, the fourth terminal event kind, and `AwaitingContext`
as terminal. It does not choose product values for a particular chat
assistant: Open Decision 12 (which keys the assistant may use) and Open
Decision 13 (numeric max history turns / max context rounds) apply when a
conversational capability is authored, not when this schema is frozen.

## Clarifications

### Session 2026-08-02

- Q: Where should conversational-field content validation and the shared context-request schema live under `ai-platform/src/`? → A: Extend `src/manifest/` for conversational Interaction + permitted-key-set load rules; put the shared context-request schema in `src/context/`; extend `src/adapter.ts` terminal kinds with `context_requested` `[implementation choice — no §citation]`
- Q: How should the integration tests `single_shot_never_emits_context_requested` and `conversational_leg_still_one_terminal_event` be constructed without H2/H3 transcript or negotiation runtime? → A: Extend A6 adapter/stream terminal emission helpers: gate `context_requested` on `interactionMode`; drive with stubs/fakes and assert mode-based allow/deny plus the one-terminal invariant — no full conversational pipeline `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Conversational manifest fields and context-request schema (Priority: P1)

As the platform's build and protocol reviewer, I need a capability to declare
`interaction_mode: conversational` with the four conversational extras (max
history turns, max context rounds per turn, transcript size limit, and a
permitted key set), a single platform-owned `{key, arguments}` context-request
schema shared by every conversational capability, `context_requested` as a
fourth terminal event kind (not a taxonomy code), and `AwaitingContext` as a
terminal immutable state — so that later band-H slices can validate transcripts
and stream context negotiation without inventing contracts, and so that no
`single_shot` capability acquires conversational behaviour by this slice's
existence (A14).

**Why this priority**: H1 sits where it does because its `Needs` (A2, A4, A6)
are the frozen error taxonomy, manifest schema/loader, and SSE framing that
conversational mode extends; without those, H1 would invent taxonomy codes,
manifest groups, or terminal event kinds. Band H is placed late as the largest
capability addition, not because it is under-specified; `interaction_mode`
defaults to `single_shot`, so no existing button-invoked capability acquires
behaviour from this band's existence (delivery plan §3.8).

**Independent Test**: A manifest may declare `interaction_mode: conversational`
with max history turns, max context rounds per turn, transcript size limit, and
a permitted key set, interaction mode is fixed for the life of a capability
version, and conversational-only fields are rejected on a `single_shot`
manifest; one platform-owned `{key, arguments}` schema is shared by every
conversational capability, `context_requested` is a terminal event kind and not
a taxonomy code, `AwaitingContext` is terminal and immutable, and a
`single_shot` client can never receive the fourth kind (delivery plan §3.8 Done
when; §3.11.7 row H1).

**Acceptance Scenarios**:

1. **Given** a manifest declaring `interaction_mode: conversational` with max
   history turns, max context rounds per turn, transcript size limit, and a
   permitted key set all present and well-formed (the three numeric fields are
   finite positive integers; the permitted key set may be empty), **When** the
   loader/build runs, **Then** the conversational manifest loads. *(Manifest: a
   conversational manifest loads with all four extra fields)*
2. **Given** a `conversational` manifest that omits max history turns, **When**
   the build runs, **Then** the build fails naming that omission. *(One failure
   case per omitted field — max history turns)*
3. **Given** a `conversational` manifest that omits max context rounds per turn,
   **When** the build runs, **Then** the build fails naming that omission.
   *(One failure case per omitted field — max context rounds per turn)*
4. **Given** a `conversational` manifest that omits transcript size limit,
   **When** the build runs, **Then** the build fails naming that omission.
   *(One failure case per omitted field — transcript size limit)*
5. **Given** a `conversational` manifest that omits the permitted key set,
   **When** the build runs, **Then** the build fails naming that omission.
   *(One failure case per omitted field — permitted key set)*
6. **Given** a `single_shot` manifest that also carries any conversational-only
   field (max history turns, max context rounds per turn, transcript size
   limit, or permitted key set), **When** the build runs, **Then** the build
   fails. *(Conversational fields on a `single_shot` manifest are rejected)*
7. **Given** a published capability version, **When** its `interaction_mode` is
   changed in place between `single_shot` and `conversational`, **Then** the
   build fails rather than accepting the edit. *(Changing interaction mode in
   place fails the build)*
8. **Given** a `conversational` manifest whose permitted key set names a key
   unknown to the platform's published context-key vocabulary, **When** the
   build runs, **Then** the build fails. *(A permitted key set naming an
   unknown key fails)*
9. **Given** a context request conforming to the platform-owned list of
   `{key, arguments}`, **When** the shared schema validates it, **Then**
   validation succeeds. *(Context request: the shared schema validates a
   conforming request)*
10. **Given** each malformed form of a context request (not a list; an
    element missing `key`; an element missing `arguments`; an element that is
    not a `{key, arguments}` object), **When** the shared schema validates it,
    **Then** each form is rejected. *(…and rejects each malformed form)*
11. **Given** the closed §5.4 error taxonomy as frozen by A2, **When** the
    taxonomy is inspected for `context_requested`, **Then** that name is
    absent from the taxonomy. *(`context_requested` is absent from the error
    taxonomy)*
12. **Given** a request whose validated output is a context request on a
    `conversational` capability, **When** the leg reaches `AwaitingContext`,
    **Then** that state is terminal and no further state transition from
    `AwaitingContext` is allowed. *(`AwaitingContext` is terminal and cannot
    transition)*
13. **Given** a `single_shot` capability, **When** its stream ends, **Then**
    the terminal event is one of `completed`, `failed`, or `cancelled` and is
    never `context_requested`. *(A `single_shot` capability can never emit the
    fourth kind)*
14. **Given** a `conversational` leg that ends in `context_requested`, **When**
    the stream is observed through completion, **Then** exactly one terminal
    event is emitted for that leg (still the one-terminal-event invariant).
    *(Still exactly one terminal event per leg)*
15. **Given** a `conversational` manifest whose numeric Interaction field is
    malformed (wrong type, negative, zero, or non-integer), **When** the build
    runs, **Then** the build fails naming that field. *(Well-formed numerics)*
16. **Given** a `conversational` manifest whose permitted key set contains a
    duplicate key, **When** the build runs, **Then** the build fails. *(Duplicate
    permitted keys rejected)*
17. **Given** a `conversational` emission of `context_requested` with a missing
    or malformed `context_request` payload, **When** the adapter pushes the
    terminal, **Then** emission fails rather than streaming a silent default.
    *(Emission-time payload validation)*

### Test plan

Layer: Contract + build + integration (delivery plan §3.11.7, row H1; §13.5).
Named tests:

**Manifest**

- `conversational_manifest_loads_all_four_extra_fields` — contract/build — a
  `conversational` manifest loads with max history turns, max context rounds
  per turn, transcript size limit, and permitted key set present and
  well-formed (§5.1; delivery plan §3.11.7 H1).
- `conversational_manifest_omits_max_history_turns_fails` — contract/build —
  omitting max history turns fails the build (§5.1 Interaction row).
- `conversational_manifest_omits_max_context_rounds_fails` — contract/build —
  omitting max context rounds per turn fails the build (§5.1 Interaction row).
- `conversational_manifest_omits_transcript_size_limit_fails` — contract/build —
  omitting transcript size limit fails the build (§5.1 Interaction row).
- `conversational_manifest_omits_permitted_key_set_fails` — contract/build —
  omitting the permitted key set fails the build (§5.1 Context requirements
  row).
- `conversational_fields_rejected_on_single_shot` — contract/build —
  conversational-only fields on a `single_shot` manifest fail the build (§5.1;
  A14).
- `conversational_numeric_fields_reject_malformed_values` — contract/build —
  wrong type, negative, zero, or non-integer values for the three numeric
  Interaction fields fail the build (§5.1).
- `permitted_key_set_edge_policies` — contract/build — empty `permittedKeySet`
  is legal; duplicate keys are rejected (§5.1).
- `interaction_mode_in_place_change_fails_build` — build — changing
  `interaction_mode` in place on a published version fails the build (§5.7).
- `permitted_key_set_unknown_key_fails` — contract/build — a permitted key set
  naming a key unknown to the published context-key vocabulary fails (§5.1;
  A14).

**Context request**

- `shared_context_request_schema_accepts_conforming` — contract — a list of
  `{key, arguments}` validates (§6.7.2).
- `shared_context_request_schema_rejects_malformed_<form>` — contract — one
  rejection case per malformed form (not a list; missing `key`; missing
  `arguments`; element not a `{key, arguments}` object) (§6.7.2).
- `context_requested_absent_from_error_taxonomy` — contract —
  `context_requested` is not a §5.4 taxonomy code; forced string input
  classifies to `internal_error` without throwing from the error-body builder
  (§5.4; A2 resilience).
- `awaiting_context_is_terminal_and_immutable` — contract/integration —
  `AwaitingContext` is terminal; no transition out of it is permitted; write
  path refuses `single_shot` (and omitted-mode default) (§6.3; §6.7.2).
- `single_shot_never_emits_context_requested` — integration — a `single_shot`
  capability's stream never ends with `context_requested`; deny is via
  production `pushTerminalEvent` (§5.5 rule 4; §6.7.4).
- `context_requested_payload_must_conform` — contract/integration —
  `pushTerminalEvent` rejects missing/malformed `context_request` payloads
  (§6.7.2; §5.5 rule 4).
- `conversational_leg_still_one_terminal_event` — integration — a
  `conversational` leg ending in `context_requested` still emits exactly one
  terminal event (§5.5 rule 4; A6 one-terminal-event invariant).

Coverage additions from delivery plan §3.10 (every branch, every inherited
prohibition, every named boundary):

- `interaction_mode_fixed_for_life_of_version` — contract — a loaded
  manifest's `interaction_mode` is immutable for that version; changing it
  requires a new version (§5.7).
- `context_request_schema_is_platform_owned_not_per_capability` — contract —
  every conversational capability shares the same `{key, arguments}` schema;
  the validator does not accept a per-capability alternate shape (§6.7.2).
- `no_new_pipeline_stage_from_conversational_mode` — contract — declaring
  `conversational` does not introduce a new §6.1 stage; stage 13 gains a
  second valid output shape and stage 14 a fourth terminal event kind only
  (§6.7.4).
- `no_per_request_server_state_from_h1` — contract — H1 introduces no
  conversation table and no per-request Durable Object or session store
  (§6.7.4; delivery plan §6.4).

### Edge Cases

- H1 emits no new §5.4 taxonomy codes. `context_requested` is deliberately
  **not** an error code (§5.4). A2's error-body builder is **unchanged**: forced
  string input of that literal classifies to `internal_error` and does not
  throw (A2 resilience). Runtime budget breaches
  (`conversation_budget_exhausted`) belong to H2, not H1.
- Build-time failure: any of the four conversational extras omitted on a
  `conversational` manifest. Rejected; there is no silent default for those
  fields (§5.1; delivery plan §3.11.7).
- Build-time failure: conversational numeric fields present but malformed
  (non-finite, non-integer, ≤ 0, or wrong type). Rejected (§5.1).
- Build-time failure: conversational-only fields on a `single_shot` manifest
  (including when `interaction_mode` is omitted and defaults). Rejected; there
  is no silent-stripping path (§5.1; A14).
- Build-time failure: in-place change of `interaction_mode` on a published
  version. Rejected; a new capability version is required (§5.7).
- Build-time failure: permitted key set names an unknown key. Rejected against
  the published context-key vocabulary (§5.1).
- Build-time policy: empty `permittedKeySet` is **legal** (allowlist of zero);
  duplicate keys in the set are **rejected** (§5.1).
- Schema failure: each malformed context-request form is rejected by the shared
  schema; there is no per-capability override (§6.7.2).
- Emission failure: `context_requested` with a missing or non-conforming
  `context_request` payload is refused at push time — no silent `[]` default
  (§6.7.2; §5.5 rule 4).
- Boundary: a `single_shot` capability can never emit `context_requested`; the
  fourth kind is unreachable unless the manifest opts into `conversational`
  (§5.5 rule 4; §5.1; A14).
- Boundary: `AwaitingContext` is terminal — that request is over; continuing
  the conversation is a new request with a new idempotency key. Journal write
  paths refuse entering `AwaitingContext` for `single_shot` (§6.3; §6.7.2).
- Boundary: exactly one terminal event per leg remains mandatory when the
  terminal kind is `context_requested` (§5.5 rule 4).
- No retry, caching, abstraction, or configurability beyond what the cited
  sections name (R-20; delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A capability manifest MAY declare `interaction_mode:
  conversational`; when it does, it MUST declare max history turns, max context
  rounds per turn, and transcript size limit as Interaction fields for
  `conversational` only — each a finite positive integer (§5.1 Interaction row;
  A14).
- **FR-002**: A `conversational` capability MUST declare a **permitted key set**
  as its Context-requirements form — the keys the assistant may request during
  a turn — instead of the ordered required/optional key list used by
  `single_shot`. An empty set is legal; duplicate keys are rejected (§5.1
  Context requirements row; A14).
- **FR-003**: Conversational-only fields (max history turns, max context rounds
  per turn, transcript size limit, and permitted key set) MUST be rejected on a
  `single_shot` manifest (§5.1; A14; delivery plan §3.8 Done when).
- **FR-004**: Interaction mode MUST be fixed for the life of a capability
  version; changing a capability between `single_shot` and `conversational`
  MUST be a new capability version, never an in-place edit (§5.7 Interaction
  mode row).
- **FR-005**: Omitting `interaction_mode` MUST continue to default to
  `single_shot`; every mechanism A14 introduces — transcripts, context
  negotiation, turn budgets — MUST remain unreachable unless a manifest opts
  into `conversational` (§5.1; A14).
- **FR-006**: A permitted key set that names a key unknown to the platform's
  published context-key vocabulary MUST fail validation (§5.1; A14; delivery
  plan §3.11.7).
- **FR-007**: The context request MUST be structured output validated against
  one **platform-owned schema shared by every conversational capability**: a
  list of `{key, arguments}` drawn from the manifest's permitted set — not a
  per-capability schema (§6.7.2).
- **FR-008**: `context_requested` MUST be a terminal event kind alongside
  `completed`, and MUST NOT appear as a §5.4 taxonomy code; it is not an error
  — the turn ran, the provider was called, and the platform is asking for data.
  A2's error-body path remains unchanged: unknown / non-taxonomy strings
  classify to `internal_error` without throwing (§5.4; §5.5 rule 4; §6.7.2).
- **FR-009**: Exactly one terminal event MUST end every stream: `completed`,
  `failed`, `cancelled`, or — for `conversational` capabilities only —
  `context_requested` carrying a conforming context-request payload; missing
  or malformed payloads MUST fail at emission. A client that does not implement
  conversational capabilities MUST never receive the fourth kind (§5.5 rule 4;
  §6.7.2).
- **FR-010**: `AwaitingContext` MUST be reachable only for `conversational`
  capabilities and MUST be terminal and immutable in the same sense as
  `Completed`, `Failed`, `Cancelled`, and `Rejected`: that request is over; the
  conversation continues as a new request with a new idempotency key. Journal
  transition / terminal-write APIs MUST refuse `AwaitingContext` for
  `single_shot` (§6.3; §6.7.2).
- **FR-011**: Conversational mode MUST NOT add a new pipeline stage, a new
  store, a new stateful component, a change to cancellation, a change to
  idempotency, a change to the advisory rule, or general tool use — stage 13
  gains a second valid output shape and stage 14 a fourth terminal event kind,
  both parameterized by the manifest (§6.7.4).
- **FR-012**: The invoking surface MUST always name the capability; the
  platform MUST never infer which capability the user wants. A chat window is
  one declared capability whose user intent is the literal typed message; what
  the platform may infer is which context that named capability now needs, by
  asking the client rather than fetching (A14).

### Key Entities

- **Conversational Interaction fields**: Manifest Interaction contents for
  `interaction_mode: conversational` — max history turns, max context rounds
  per turn, transcript size limit — each a finite positive integer (§5.1).
- **Permitted key set**: The allowlist of context keys a conversational
  capability may request during a turn; declared on the manifest in place of
  the `single_shot` ordered required/optional key list; empty legal; duplicates
  rejected (§5.1; A14).
- **Context-request schema**: Platform-owned shared schema — a list of
  `{key, arguments}` — validating the structured output that ends a leg in
  `context_requested` / `AwaitingContext`; also enforced at emission (§6.7.2).
- **Terminal event kind `context_requested`**: Fourth terminal SSE event kind,
  conversational only; carries a conforming context-request payload; not a
  taxonomy code (§5.5; §5.4; §6.7.2).
- **Request state `AwaitingContext`**: Terminal immutable journal state for a
  leg that ended in a valid context request; reachable only for
  `conversational` capabilities (write-path enforced) (§6.3; §6.7.2).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: This slice serves small-to-mid multi-branch clinics by
  freezing the contract for an open chat surface as a declared capability with
  bounded context negotiation (A14), without adding a session store,
  microservices, or per-request state — keeping the platform clinic-scale and
  simple (constitution I; §6.7.4).
- **Layer Placement**: This slice touches `ai-platform/` (Cloudflare Worker) —
  extending the manifest schema/loader, the shared context-request schema, the
  SSE terminal-event set, and the request-state terminal set. It touches
  neither `backend/` (Supabase/PostgreSQL) nor `frontend/` (Flutter). Per the
  architecture §14 acknowledgement, the AI platform gateway is a non-primary,
  additive component with a separate store and no write path into Supabase;
  this slice adds contract surface only and adds no domain logic and no
  business data (§14; delivery plan §7.1).
- **Data Integrity & Security**: H1 defines no new D1 table and no Supabase
  write path. Integrity is build-time and contract-time: conversational field
  presence, permitted-key allowlisting against the published vocabulary, the
  shared `{key, arguments}` schema, and terminal-state immutability. No RLS,
  RPCs, or clinic audit fields are introduced by this slice.
- **Failure Handling**: H1 has no product UI path. Build failures reject
  malformed conversational manifests; schema validation rejects malformed
  context requests. At the protocol boundary, `single_shot` streams cannot emit
  `context_requested`, and every leg still ends with exactly one terminal
  event. There is no fall-back, retry, or degraded path added beyond what A2/A4/A6
  already provide (R-20). AI remains additive: omitting `conversational`
  leaves button-invoked capabilities unchanged (§5.1; A14; A11).

## Out of Scope

- Slice H2 — transcript validation, conversation budgets, and composer
  rendering (§4.3.5, §6.7.1, §6.7.3, §4.3.6, §6.7.2): counting max history
  turns / max context rounds from a submitted transcript,
  `conversation_budget_exhausted`, allowlist enforcement at the validator
  against model-requested keys, and composer rendering of prior turns.
- Slice H3 — conversational journaling and client chat surface (§7.3, §6.7.1,
  §8.10, §4.1, §6.7): writing `conversation_id` / `turn_ordinal`, the client
  holding and resupplying the transcript, and Resolver integration for
  requested keys.
- Slice H4 — conversation evals (§13.5, A9).
- Slice J2 — `context_required` self-healing for `single_shot` stale caches
  (§8.4); conversational capabilities never take that path.
- Choosing the chat assistant's concrete permitted key set or numeric turn /
  round limits (Open Decisions 12 and 13) — those are product values on a
  capability version, not this schema freeze.
- Redefining A2's taxonomy codes, A4's ten field groups or `single_shot`
  default, or A6's three existing terminal kinds — extension only (delivery
  plan §2.3).
- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client
  (R-12).
- No second Quota Durable Object round trip and no second R2 object per
  request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk
  (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable
  provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A contract + build test proves a `conversational` manifest with
  all four extra fields loads successfully (delivery plan §3.8 Done when;
  §3.11.7).
- **SC-002**: A contract + build test proves the build fails for each of the
  four omitted conversational extras (one named case each) (delivery plan
  §3.11.7).
- **SC-003**: A contract + build test proves conversational-only fields are
  rejected on a `single_shot` manifest (delivery plan §3.8 Done when; §5.1).
- **SC-004**: A build test proves changing `interaction_mode` in place on a
  published version fails the build (§5.7; delivery plan §3.11.7).
- **SC-005**: A contract + build test proves a permitted key set naming an
  unknown key fails (delivery plan §3.11.7).
- **SC-006**: A contract test proves the shared `{key, arguments}` schema
  accepts a conforming request and rejects each malformed form (§6.7.2;
  delivery plan §3.11.7).
- **SC-007**: A contract test proves `context_requested` is absent from the
  §5.4 error taxonomy (§5.4; delivery plan §3.8 Done when).
- **SC-008**: A contract/integration test proves `AwaitingContext` is terminal
  and cannot transition (§6.3; delivery plan §3.8 Done when).
- **SC-009**: An integration test proves a `single_shot` capability never emits
  `context_requested`, and a `conversational` leg ending in that kind still
  emits exactly one terminal event (§5.5 rule 4; delivery plan §3.11.7).

## Assumptions

- The schema and protocol extensions live in `ai-platform/` (Cloudflare Worker
  source), alongside the A4 manifest loader and A6 protocol adapter (delivery
  plan §7.1).
- Feature number **044** is the next free prefix under `specs/` after
  `043-load-and-cost-tests`. Spec Kit's `create-new-feature.sh --dry-run`
  allocates against `docs/specs/` and does not parse `ai/<NNN>-*` branch names,
  so the number was confirmed from `specs/` and applied with `--number 044`.
- The published context-key vocabulary used to reject an unknown permitted key
  is the vocabulary already frozen by A5; H1 does not redefine key shapes and
  does not list A5 in `Needs` (delivery plan §3.8 Needs remain A2, A4, A6).
- Concrete numeric values for max history turns / max context rounds, and the
  concrete permitted key set of any chat capability, are left to capability
  authoring under Open Decisions 12 and 13; this slice only freezes that those
  fields exist and validate.
- H1 is proved by contract + build + integration tests; full transcript
  validation and client chat UX belong to H2 and H3 (delivery plan §3.11.7).
