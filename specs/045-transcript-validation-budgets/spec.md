# Feature Specification: Transcript validation, conversation budgets, and composer rendering

**Feature Branch**: `ai/045-h2-transcript-validation-budgets`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `H2` — "Transcript validation, conversation budgets, and composer rendering" (delivery plan §3.8, band H).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.8, row H2):

> §4.3.5, §6.7.1, §6.7.3, §4.3.6, §6.7.2

### Freezes

Contracts this slice establishes for the first time:

- **The closed, platform-owned transcript wire shape**: the submit surface
  carries `transcript` as a JSON array of turn objects; every turn declares
  exactly two common fields — `turn_ordinal` (integer, required, strictly
  increasing across the array, no duplicates, every value strictly less than
  the leg's own `turn_ordinal`, gaps legal) and `kind` (string, required, one
  of four values, no other value accepted) — plus the one payload field its
  kind defines: `user` → `text` (string), `model` → `text` (string),
  `context_requested` → `requests` (array), `context_resolved` → `context`
  (object). A capability may choose what its assistant talks about, never how a
  turn is spelled (§6.7.1).
- **Transcript validation at the context validator** for
  `interaction_mode: conversational`: turn ordering, the declared turn shapes
  of the §6.7.1 wire contract, and the conversation budget counted from the
  supplied transcript itself (§4.3.5; §6.7.1; §6.7.3).
- **`context_invalid` as the shape/order rejection for a transcript turn**: a
  turn carrying no payload field, the wrong payload field for its `kind`, a
  payload of the wrong type, an unknown `kind`, a missing or non-integer
  `turn_ordinal`, or a `turn_ordinal` that does not respect the ordering rule
  is a malformed turn rejected with `context_invalid` — the same code, and the
  same client remedy ("bug: report with request reference"), as any context
  payload that violates its declared shape. No new taxonomy code is introduced
  for it (§4.3.5; §6.7.1; §5.4).
- **Whole-transcript accept-or-reject**: there is no coercion and no silent
  drop of a bad turn — a transcript is accepted whole or rejected whole. The
  allowlist drop applies only to keys *inside* a `context_resolved` turn, where
  a key outside the manifest's permitted set is dropped rather than rejecting
  the request (§6.7.1; §4.3.5).
- **Shape before budgets**: all three bounds are evaluated only after the
  transcript has passed shape validation; a malformed or out-of-order
  transcript fails with `context_invalid` and is never counted, so a budget
  code is never emitted for a transcript that failed shape validation
  (§6.7.3; §4.3.5).
- **Conversation budget breach code `conversation_budget_exhausted`**: a
  well-formed transcript that is merely too long is not `context_invalid` —
  exceeding max history turns or max context rounds per turn, both counted from
  the submitted transcript alone, is `conversation_budget_exhausted` (§6.7.3;
  §4.3.5).
- **Permitted-key allowlist enforcement at the validator** for conversational
  capabilities: a key the manifest does not permit cannot enter a prompt even
  if the model asked for it and the client supplied it; unknown keys are
  dropped, not forwarded (§4.3.5).
- **Per-turn cost pre-flight over the transcript with no new mechanism**: the
  existing cost pre-flight prices the whole request (transcript included); an
  oversized transcript yields `request_too_large` (§6.7.3).
- **Composer rendering of the supplied transcript** as prior turns of
  delimited typed data on the same footing as context, using the closed
  canonical role-tag set: `user` for transcript user turns, `assistant` for
  prior model turns, `data` for context; the composer draws no distinction
  between chat text and clinical free text (R-10) (§4.3.6).
- **Context-request schema as a second permitted output shape alongside
  prose**: the composer offers it; the response validator accepts either a
  valid prose answer or a valid context request, and rejects output that is
  neither (§4.3.6; §6.7.2).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (C2, D1, D6, H1). Changing any is
out of scope by definition:

- **From C2 (context validator and cost pre-flight)**: the filtered,
  declaration-conformant context payload; the cost pre-flight decision surface
  that rejects with `request_too_large` before egress; and the stage-6/7
  placement as CPU-only checks. H2 extends the same validator for
  conversational transcript validation, permitted-key allowlisting, and budget
  counting, and relies on the existing pre-flight to price the transcript; it
  does not invent a second cost mechanism or rewrite C2's single-shot
  required/optional key behaviour (§4.3.5; §6.7.3; C2 Freezes).
- **From D1 (prompt registry and composer)**: the prompt registry pin contract
  and the `single_shot` composer output contract (canonical request from system
  instruction, business-rule fragments, schema-derived format instruction,
  validated context as delimited typed data, user intent, output constraints;
  R-10). H2 extends composition for conversational transcripts and the second
  permitted output shape; it does not rewrite registry immutability, pin
  checks, or `single_shot` composition (§4.3.6; D1 Freezes).
- **From D6 (response validator, bounded repair, structured modes)**: the
  ordered validation phases, bounded repair, `validation_failed` on exhaustion,
  and structured-mode emission rules. H2 extends acceptance so a
  conversational leg may validate as prose or as the shared context-request
  schema; it does not reorder phases, unbound repair, or return invalid content
  (§6.7.2; D6 Freezes).
- **From H1 (conversational manifest fields and context-request schema)**:
  `interaction_mode: conversational` with max history turns, max context rounds
  per turn, transcript size limit, and permitted key set; interaction mode
  fixed for the life of a capability version; the platform-owned
  `{key, arguments}` context-request schema; `context_requested` as a terminal
  event kind (not a taxonomy code); and `AwaitingContext` as terminal and
  immutable. H2 enforces those limits and shapes at runtime; it does not
  redefine the manifest fields or the shared schema (§6.7.2; §6.7.3; H1
  Freezes).

### Open decisions relied on

None — H2 enforces budgets and shapes already declared on a conversational
manifest (H1) and extends the existing validator and composer. Concrete numeric
limits and permitted key sets remain product values on a capability version
(Open Decisions 12 and 13 apply at capability authoring, not in this slice).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Transcript validation, conversation budgets, and composer rendering (Priority: P1)

As the AI Gateway Worker's context validator and prompt composer, for a
capability with `interaction_mode: conversational`, I validate the
client-supplied transcript against the closed §6.7.1 wire contract — rejecting
a malformed, unknown-kind, or out-of-order turn as `context_invalid`, whole
transcript at a time, before any budget is counted — then count max history
turns and max context rounds from that transcript alone, enforce the
permitted key set as an allowlist, and price the transcript through the
existing cost pre-flight; I then render prior turns as delimited typed data on
the same footing as context and accept either a prose answer or a
platform-owned context request as the permitted output shapes — so that
conversation loops stay bounded and untrusted transcript content cannot act as
an instruction, without holding conversation state on the platform.

**Why this priority**: H2 sits where it does because its `Needs` (C2, D1, D6,
H1) freeze the context validator and cost pre-flight, the `single_shot`
composer, the response validator, and the conversational manifest /
context-request schema. Without those, H2 would invent budget fields, a second
cost mechanism, or a per-capability context-request schema. Band H is placed
late as the largest capability addition; `interaction_mode` defaults to
`single_shot`, so no existing button-invoked capability acquires behaviour from
this slice's existence (delivery plan §3.8).

**Independent Test**: Turn ordering and declared turn shapes are validated, max
history turns and max context rounds are counted from the submitted transcript
alone, a breach produces `conversation_budget_exhausted`, the permitted key set
is an allowlist enforced at the validator, and per-turn cost pre-flight prices
the transcript with no new mechanism; the transcript renders as prior turns of
delimited typed data on the same footing as context, the context-request schema
is offered as a second permitted output shape alongside prose, and the
validator accepts either (delivery plan §3.8 Done when; §3.11.7 row H2).

**Acceptance Scenarios**:

1. **Given** a `conversational` capability and a well-formed `transcript`
   array whose turns carry strictly increasing `turn_ordinal` values below the
   leg's own and one of the four declared `kind`/payload pairings (`user`/`text`,
   `model`/`text`, `context_requested`/`requests`,
   `context_resolved`/`context`), **When** the context validator runs, **Then**
   the transcript passes. *(Transcript: valid transcript passes)*
2. **Given** a transcript whose `turn_ordinal` values are out of order,
   duplicated, missing, non-integer, or not strictly less than the leg's own,
   **When** the context validator runs, **Then** the request fails with
   `context_invalid`. *(Out-of-order `turn_ordinal` rejected)*
3. **Given** a transcript containing a turn that does not match a declared turn
   shape — no payload field, the wrong payload field for its `kind`, or a
   payload of the wrong type — **When** the context validator runs, **Then**
   the request fails with `context_invalid`. *(Malformed turn shape rejected)*
4. **Given** a transcript turn whose `kind` is not one of `user`, `model`,
   `context_requested`, `context_resolved`, **When** the context validator
   runs, **Then** the request fails with `context_invalid`. *(Unknown `kind`
   rejected)*
5. **Given** a transcript in which one turn is malformed and the rest are
   well-formed, **When** the context validator runs, **Then** the whole
   transcript is rejected with `context_invalid` — the bad turn is neither
   coerced nor silently dropped. *(Whole-transcript accept-or-reject)*
6. **Given** a malformed or out-of-order transcript that also exceeds max
   history turns, **When** the context validator runs, **Then** the failure is
   `context_invalid` and no budget code is emitted, because shape is checked
   before budgets. *(Shape before budgets)*
7. **Given** a transcript whose turn count exceeds the manifest's max history
   turns, **When** the context validator runs, **Then** the request fails with
   `conversation_budget_exhausted`. *(History-turn limit breached →
   `conversation_budget_exhausted`)*
8. **Given** a transcript whose consecutive `context_requested` turns at the
   tail exceed the manifest's max context rounds per turn, **When** the context
   validator runs, **Then** the request fails with
   `conversation_budget_exhausted`. *(Consecutive context rounds at the
   transcript tail breached → same code)*
9. **Given** a `context_resolved` turn carrying a context key outside the
   manifest's permitted set — even when the model requested it and the client
   supplied it — **When** the context validator runs, **Then** that key is
   dropped, the request is not rejected, and the key does not enter the
   composer input. *(A key outside the permitted set is dropped even when
   requested by the model)*
10. **Given** a transcript that makes the whole request exceed the existing
    cost pre-flight ceiling, **When** pre-flight runs, **Then** the request
    fails with `request_too_large` and no egress occurs. *(Oversized transcript
    → `request_too_large` from the existing pre-flight)*
11. **Given** a client-trimmed transcript with gaps in `turn_ordinal` that
    resets the round counter, **When** the validator and admission run, **Then**
    the gaps are legal, the trimmed transcript is accepted for budget counting,
    and the leg remains bounded by independent authentication, rate limiting,
    cost check, and admission (R-22). *(A trimmed transcript is accepted but
    bounded by admission (R-22))*
12. **Given** a valid conversational transcript and filtered context, **When**
    the composer runs, **Then** the transcript renders as delimited typed prior
    turns on the same footing as context. *(Composer: transcript renders as
    delimited typed prior turns)*
13. **Given** a user turn containing instruction-like text, **When** the
    composer renders it, **Then** that text does not act as an instruction
    (R-10). *(An instruction inside a user turn does not act as an instruction
    (R-10))*
14. **Given** a valid prose answer from a conversational capability, **When**
    the response validator runs, **Then** validation succeeds. *(A prose answer
    validates)*
15. **Given** a valid context request conforming to the platform-owned
    `{key, arguments}` schema drawn from the permitted set, **When** the
    response validator runs, **Then** validation succeeds. *(A context request
    validates)*
16. **Given** output that is neither valid prose nor a valid context request,
    **When** the response validator runs, **Then** validation fails. *(Output
    that is neither fails)*
17. **Given** free text from a clinical note and free text typed into a chat
    box, **When** the composer renders both, **Then** it draws no distinction —
    both are delimited typed data and neither may act as an instruction.
    *(The composer draws no distinction between chat text and clinical free
    text)*

### Test plan

Layer: Unit + golden (delivery plan §3.11.7, row H2; §13.5).
Named tests:

**Transcript**

- `valid_transcript_passes` — unit — a well-formed `transcript` array whose
  turns carry strictly increasing `turn_ordinal` values and the four declared
  `kind`/payload pairings passes (§4.3.5; §6.7.1; delivery plan §3.11.7 H2).
- `out_of_order_turn_ordinal_rejected_context_invalid` — unit — an
  out-of-order, duplicate, missing, or non-integer `turn_ordinal`, or one not
  strictly less than the leg's own, is rejected with `context_invalid`
  (§4.3.5; §6.7.1; §5.4).
- `malformed_turn_shape_rejected_context_invalid` — unit — a turn with no
  payload field, the wrong payload field for its `kind`, or a payload of the
  wrong type is rejected with `context_invalid` (§4.3.5; §6.7.1; §5.4).
- `unknown_turn_kind_rejected_context_invalid` — unit — a `kind` outside
  `user` / `model` / `context_requested` / `context_resolved` is rejected with
  `context_invalid` (§6.7.1; §4.3.5; §5.4).
- `transcript_rejected_whole_not_coerced_or_dropped` — unit — one malformed
  turn rejects the whole transcript; no turn is coerced or silently dropped
  (§6.7.1).
- `shape_checked_before_budgets` — unit — a transcript that is both malformed
  and over the history-turn limit fails with `context_invalid`, and no budget
  code is emitted (§6.7.3; §4.3.5).
- `history_turn_limit_breached_conversation_budget_exhausted` — unit —
  exceeding max history turns (counted from the submitted transcript) yields
  `conversation_budget_exhausted` (§6.7.3).
- `context_rounds_at_tail_breached_conversation_budget_exhausted` — unit —
  consecutive `context_requested` turns at the transcript tail exceeding max
  context rounds per turn yields `conversation_budget_exhausted` (§6.7.3).
- `key_outside_permitted_set_dropped` — unit (spy) — a key inside a
  `context_resolved` turn that is outside the permitted set is dropped (not a
  rejection) and is absent from the composer input even when requested by the
  model and supplied by the client (§4.3.5; §6.7.1).
- `oversized_transcript_request_too_large` — unit (spy) — an oversized
  transcript fails the existing cost pre-flight with `request_too_large` and
  produces no egress (§6.7.3).
- `trimmed_transcript_accepted_bounded_by_admission` — unit — a trimmed
  transcript with `turn_ordinal` gaps is legal and accepted for budget
  counting; containment remains
  per-leg authentication, rate limiting, cost check, and admission (R-22;
  §6.7.3).

**Composer**

- `transcript_renders_as_delimited_typed_prior_turns` — golden — composed
  request renders the transcript as delimited typed prior turns on the same
  footing as context (§4.3.6).
- `instruction_in_user_turn_does_not_act_as_instruction` — unit/golden — an
  instruction embedded in a user turn does not act as an instruction (R-10;
  §4.3.6).
- `prose_answer_validates` — unit — a valid prose answer passes the response
  validator (§4.3.6; §6.7.2).
- `context_request_validates` — unit — a conforming `{key, arguments}` context
  request passes the response validator (§6.7.2).
- `output_neither_prose_nor_context_request_fails` — unit — output that is
  neither fails validation (§4.3.6; §6.7.2).
- `composer_no_distinction_chat_vs_clinical_free_text` — golden — chat text and
  clinical free text are rendered equivalently as delimited typed data
  (§4.3.6).

Coverage additions from delivery plan §3.10 (every branch, every inherited
prohibition, every named boundary):

- `budgets_counted_from_submitted_transcript_alone` — unit — max history turns
  and max context rounds are computed only from the submitted request; no
  platform-held conversation counter is consulted (§6.7.3; §6.7.1).
- `per_turn_cost_ceiling_uses_existing_preflight_no_new_mechanism` — unit —
  transcript growth is priced only by the existing pre-flight; no running
  conversation total and no §9.14 reservation (§6.7.3; delivery plan §6.4).
- `role_tags_user_assistant_data_for_transcript` — golden — `user` turns
  render as `user` parts, `model` turns as `assistant` parts,
  `context_resolved` turns as `data` parts, and ordinary context as `data`; no
  invented role tag (§4.3.6; §6.7.1).
- `no_per_request_server_state_from_h2` — unit (spy) — H2 introduces no
  conversation store and no per-request Durable Object or session object
  (§6.7.1; delivery plan §6.4).
- `single_shot_unaffected_by_h2` — unit — a `single_shot` capability does not
  acquire transcript validation, budget codes, or the second output shape from
  this slice's existence (§6.7 conversational preamble; delivery plan §3.8).

### Edge Cases

- **Error codes this slice can emit**: `context_invalid` (422, not retryable,
  no quota; client remedy "bug: report with request reference") when a
  transcript turn is malformed, of unknown `kind`, or out of `turn_ordinal`
  order (§4.3.5; §6.7.1; §5.4); `conversation_budget_exhausted` (history turns
  or context rounds breached — §6.7.3); `request_too_large` from the existing
  pre-flight when the transcript makes the request oversized (§6.7.3). Output
  that is neither prose nor context request fails under D6's existing
  `validation_failed` path (Consumes D6); H2 does not invent a new taxonomy
  code for any of these cases.
- **Ordering — shape before budgets**: all three bounds are evaluated only
  after shape validation passes; a transcript that cannot be parsed into turns
  cannot be counted, so a budget code is never emitted for a transcript that
  failed shape validation (§6.7.3; §4.3.5).
- **Boundary — turn ordering**: `turn_ordinal` must be an integer, strictly
  increasing across the array, without duplicates, and strictly less than the
  leg's own; gaps are legal. A violation is `context_invalid`, so a replayed or
  reordered transcript is detectable (§6.7.1; §4.3.5).
- **Boundary — declared turn shapes**: the declared shapes are the closed
  §6.7.1 wire table — `user`/`text` (string), `model`/`text` (string),
  `context_requested`/`requests` (array), `context_resolved`/`context`
  (object). A missing payload field, the wrong payload field for the `kind`, a
  payload of the wrong type, or an unknown `kind` is `context_invalid`; there
  is no coercion (§6.7.1; §4.3.5).
- **Boundary — whole-transcript accept-or-reject**: a bad turn is never
  silently dropped; the transcript is accepted whole or rejected whole. The
  drop rule applies only to keys inside a `context_resolved` turn (§6.7.1).
- **Boundary — max history turns**: counted from turns in the supplied
  transcript; breach → `conversation_budget_exhausted` (§6.7.3).
- **Boundary — max context rounds per turn**: counted as consecutive
  `context_requested` turns at the tail of the supplied transcript; breach →
  `conversation_budget_exhausted` (§6.7.3).
- **Boundary — permitted key allowlist**: non-permitted keys inside a
  `context_resolved` turn (and in the ordinary context payload) are dropped,
  not forwarded and not a rejection — including when the model requested them
  (§4.3.5; §6.7.1).
- **Boundary — per-turn cost ceiling**: no new mechanism; transcript is part of
  the request the existing pre-flight already prices (§6.7.3).
- **Accepted failure branch — transcript tampering (R-22)**: a malicious client
  may trim context-request turns to reset the round counter; that is accepted
  rather than solved. Containment is per-leg authentication, rate limiting,
  cost check, and admission against the installation's own budget (§6.7.3).
- **R-10**: instruction-like text inside a user turn or clinical free text must
  not act as an instruction; escaping and `data`-part opacity enforce this as a
  property of shape (§4.3.6).
- **No platform-held conversation**: each leg carries the transcript so far;
  the platform reads it, uses it, and forgets it (§6.7.1).
- No retry, caching, abstraction, or configurability beyond what the cited
  sections name (R-20; delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: For a conversational capability, the context validator MUST
  validate the supplied transcript for turn ordering, the declared turn shapes
  of the closed §6.7.1 wire contract, and the conversation budget counted from
  the transcript itself (§4.3.5).
- **FR-002**: Each conversational leg MUST carry the transcript so far as prior
  turns in the request body; the platform MUST read it, use it, and MUST NOT
  retain conversation state between legs (§6.7.1).
- **FR-003**: The submit surface MUST carry `transcript` as a JSON array of
  turn objects in which every turn declares exactly two common fields —
  `turn_ordinal` (integer, required) and `kind` (string, required, one of the
  four declared kinds, no other value accepted) — plus the one payload field
  its kind defines: `user` → `text` (string), `model` → `text` (string),
  `context_requested` → `requests` (array), `context_resolved` → `context`
  (object, keyed and shaped exactly as an ordinary context payload). The wire
  shape is closed and platform-owned; a capability MUST NOT redefine how a turn
  is spelled (§6.7.1).
- **FR-004**: `turn_ordinal` MUST be strictly increasing across the transcript
  array with no duplicates and every value strictly less than the leg's own
  `turn_ordinal`; gaps MUST be legal. `turn_ordinal` MUST make a replayed or
  reordered transcript detectable (§6.7.1).
- **FR-005**: A turn carrying no payload field, the wrong payload field for its
  `kind`, a payload of the wrong type, an unknown `kind`, a missing or
  non-integer `turn_ordinal`, or a `turn_ordinal` that does not respect the
  ordering rule is a malformed turn and MUST be rejected by the context
  validator with `context_invalid`; no new taxonomy code MAY be introduced for
  it (§6.7.1; §4.3.5; §5.4).
- **FR-006**: A transcript MUST be accepted whole or rejected whole: there MUST
  be no coercion and no silent drop of a bad turn. The drop rule MUST apply
  only to keys inside a `context_resolved` turn, where a key outside the
  manifest's permitted set is dropped rather than rejecting the request
  (§6.7.1; §4.3.5).
- **FR-007**: The three bounds MUST be evaluated only after the transcript has
  passed shape validation; a malformed or out-of-order transcript MUST fail
  with `context_invalid` and MUST NOT be counted, so a budget code MUST NOT be
  emitted for a transcript that failed shape validation (§6.7.3; §4.3.5).
- **FR-008**: A well-formed transcript that is merely too long MUST NOT be
  `context_invalid`; exceeding max history turns or max context rounds MUST be
  `conversation_budget_exhausted` and exceeding the cost ceiling MUST be
  `request_too_large` (§4.3.5; §6.7.3).
- **FR-009**: Max history turns MUST be enforced by counting turns in the
  supplied transcript alone; a breach MUST produce
  `conversation_budget_exhausted` (§6.7.3).
- **FR-010**: Max context rounds per turn MUST be enforced by counting
  consecutive `context_requested` turns at the tail of the supplied transcript
  alone; a breach MUST produce `conversation_budget_exhausted` (§6.7.3).
- **FR-011**: The permitted key set MUST be enforced as an allowlist at the
  validator: a key the manifest does not permit MUST NOT enter a prompt even if
  the model asked for it and the client supplied it; unknown keys MUST be
  dropped, not forwarded (§4.3.5).
- **FR-012**: Per-turn cost MUST be enforced by the existing cost pre-flight
  (pipeline stage 7), which estimates input tokens from the whole request
  including the transcript; a breach MUST produce `request_too_large`; H2 MUST
  NOT add a new cost mechanism, running conversation total, or pre-flight
  reservation (§6.7.3).
- **FR-013**: A client-trimmed transcript that resets the round counter MUST be
  accepted for budget counting rather than rejected as integrity failure; every
  leg MUST remain independently authenticated, rate-limited, cost-checked, and
  admitted (R-22; §6.7.3).
- **FR-014**: For a conversational capability, the composer MUST render the
  supplied transcript as prior turns, and MUST offer the shared context-request
  schema as a second permitted output shape alongside prose (§4.3.6).
- **FR-015**: Transcript user turns and any context resolved during the
  conversation MUST be rendered as delimited, typed data on the same footing as
  ordinary context; the composer MUST draw no distinction between free text
  from a clinical note and free text typed into a chat box; neither MAY act as
  an instruction (R-10; §4.3.6).
- **FR-016**: The composer MUST emit transcript parts using the closed
  canonical role-tag set: `user` for a transcript's `user` turns, `assistant`
  for a transcript's `model` turns, `data` for context — including a
  `context_resolved` turn's `context` payload; it MUST invent no tag of its own
  (§4.3.6; §6.7.1).
- **FR-017**: The response validator MUST accept either a validated prose
  answer or a context request validated against the platform-owned
  `{key, arguments}` schema drawn from the manifest's permitted set; output
  that is neither MUST fail (§4.3.6; §6.7.2).
- **FR-018**: The context request MUST remain structured output against the
  one platform-owned schema shared by every conversational capability — not a
  per-capability schema (§6.7.2).
- **FR-019**: H2 MUST NOT introduce a conversation session store, a new
  pipeline stage, or per-request server-side state; the unit of work remains a
  leg through the existing pipeline (§6.7.1; delivery plan §6.4).

### Key Entities

- **Transcript**: A JSON array of turn objects, closed and platform-owned,
  carried on each conversational leg; untrusted in the same sense as any
  context payload; validated whole for ordering and declared shapes, then for
  budgets, then forgotten after the leg (§6.7.1; §6.7.3; §4.3.5).
- **Turn**: `turn_ordinal` (integer) + `kind` (one of `user`, `model`,
  `context_requested`, `context_resolved`) + the one payload field the kind
  defines (`text` string, `text` string, `requests` array, `context` object
  respectively). Any deviation is a malformed turn → `context_invalid`
  (§6.7.1).
- **Turn ordinal**: Client-incremented per-leg ordering field, strictly
  increasing with no duplicates and below the leg's own value (gaps legal),
  that makes replay/reorder detectable at validation (§6.7.1).
- **Conversation budgets**: Manifest-declared max history turns and max context
  rounds per turn, both counted from the submitted transcript alone; breach
  code `conversation_budget_exhausted` (§6.7.3).
- **Permitted key allowlist (runtime)**: Enforcement at the context validator
  that drops any key outside the H1-declared permitted set before composition —
  including keys inside a `context_resolved` turn — without rejecting the
  request (§4.3.5; §6.7.1).
- **Dual permitted output shapes**: Prose answer and platform-owned context
  request (`{key, arguments}`), both accepted by the response validator for
  conversational capabilities (§4.3.6; §6.7.2).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Bounds conversational loops with transcript-local budgets and
  the existing cost pre-flight, without a session store or running conversation
  total — keeping the platform simple and clinic-scale (constitution I;
  §6.7.1; §6.7.3).
- **Layer Placement**: This slice touches `ai-platform/` (Cloudflare Worker) —
  extending the context validator (transcript, budgets, allowlist), the prompt
  composer (prior-turn rendering and second output shape), and the response
  validator's accepted shapes for conversational legs. It touches neither
  `backend/` (Supabase/PostgreSQL) nor `frontend/` (Flutter). Per the
  architecture §14 acknowledgement, the AI platform gateway is a non-primary,
  additive component with a separate store and no write path into Supabase;
  this slice adds no domain logic and no business data (§14; delivery plan
  §7.1).
- **Data Integrity & Security**: No new D1 table and no Supabase write path.
  Integrity is request-time: transcript shape/order validation, allowlist
  drops, budget codes, and R-10 delimited rendering. Clinic data reach remains
  bounded by the permitted key set and the caller's own RLS on later client
  resolution (H3); H2 only enforces the allowlist at the gateway (§4.3.5;
  §6.7.2).
- **Failure Handling**: Malformed, unknown-kind, or out-of-order transcript
  turn → `context_invalid` (422, not retryable, whole transcript rejected,
  evaluated before any budget); budget breach → `conversation_budget_exhausted`;
  oversized transcript → `request_too_large` from the existing pre-flight with
  no egress; invalid dual-shape output fails under D6's validation path.
  Trimmed-transcript tampering is accepted and contained by per-leg admission
  (§6.7.3). AI remains additive: `single_shot` capabilities are unaffected
  (delivery plan §3.8; constitution V).

## Out of Scope

- Slice H1 — conversational manifest fields and context-request schema (already
  frozen; H2 consumes, does not redefine).
- Slice H3 — conversational journaling and client chat surface (§7.3, §6.7.1,
  §8.10, §4.1, §6.7): writing `conversation_id` / `turn_ordinal` to the
  journal, the client holding and resupplying the transcript, Resolver
  integration for requested keys, and new idempotency keys per leg.
- Slice H4 — conversation evals (§13.5, A9).
- Slice J2 — `context_required` self-healing for `single_shot` stale caches
  (§8.4); conversational capabilities never take that path.
- Choosing concrete numeric max history turns / max context rounds or a chat
  capability's permitted key set (Open Decisions 12 and 13).
- Redefining C2's single-shot required/optional validation, D1's registry pin
  or `single_shot` composition, or D6's phase order / repair / structured modes
  — extension only (delivery plan §2.3).
- Holding conversation state on the platform or making the platform
  authoritative over transcript integrity (§6.7.1; §6.7.3).
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

- **SC-001**: Unit tests prove a valid transcript passes and that an
  out-of-order `turn_ordinal`, a malformed turn shape, and an unknown `kind`
  are each rejected with `context_invalid` (delivery plan §3.11.7 H2; §4.3.5;
  §6.7.1; §5.4).
- **SC-002**: A unit test proves one malformed turn rejects the whole
  transcript with `context_invalid` — no turn is coerced or silently dropped —
  while a non-permitted key inside a `context_resolved` turn is dropped without
  rejecting the request (§6.7.1; §4.3.5).
- **SC-003**: A unit test proves shape is checked before budgets: a transcript
  that is both malformed and over a budget fails with `context_invalid` and
  emits no budget code (§6.7.3; §4.3.5).
- **SC-004**: A unit test proves exceeding max history turns yields
  `conversation_budget_exhausted` (delivery plan §3.8 Done when; §6.7.3).
- **SC-005**: A unit test proves consecutive context rounds at the transcript
  tail exceeding the limit yields `conversation_budget_exhausted` (§6.7.3;
  delivery plan §3.11.7).
- **SC-006**: A unit (spy) test proves a key outside the permitted set inside a
  `context_resolved` turn is absent from the composer input even when requested
  by the model (§4.3.5; §6.7.1; delivery plan §3.8 Done when).
- **SC-007**: A unit (spy) test proves an oversized transcript fails the
  existing pre-flight with `request_too_large` and no egress (§6.7.3;
  delivery plan §3.11.7).
- **SC-008**: A unit test proves a trimmed transcript with `turn_ordinal` gaps
  is accepted for budget counting while the leg remains bounded by admission
  (R-22; §6.7.1; §6.7.3).
- **SC-009**: A golden test proves the transcript renders as delimited typed
  prior turns on the same footing as context, with no distinction between chat
  text and clinical free text, and that an instruction in a user turn does not
  act as an instruction (R-10; §4.3.6; delivery plan §3.11.7).
- **SC-010**: Unit tests prove a prose answer validates, a context request
  validates, and output that is neither fails (§4.3.6; §6.7.2; delivery plan
  §3.8 Done when; §3.11.7).

## Assumptions

- Runtime work lives in `ai-platform/` (Cloudflare Worker), extending C2's
  context validator / pre-flight, D1's composer, and D6's response validator
  (delivery plan §7.1).
- Feature number **045** is the next free prefix under `specs/` after
  `044-conversational-manifest-schema`. Spec Kit's `create-new-feature.sh
  --dry-run` allocates against `docs/specs/` and does not parse `ai/<NNN>-*`
  branch names, so the number was confirmed from `specs/` (same approach as
  H1).
- Manifest fields this slice enforces (max history turns, max context rounds,
  permitted key set, transcript size limit via pre-flight) are those H1 froze;
  H2 does not invent alternate field names or defaults.
- "Declared turn shapes" is not an assumption: it is the closed transcript wire
  contract stated in §6.7.1 (the `turn_ordinal` / `kind` common fields and the
  four `kind` → payload rows), which §4.3.5 names as the shapes it validates
  against. H2 invents no schema vocabulary beyond that table.
- H2 is proved by unit + golden tests; journaling and the Flutter chat surface
  belong to H3 (delivery plan §3.11.7).
