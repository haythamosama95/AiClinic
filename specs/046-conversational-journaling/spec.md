# Feature Specification: Conversational journaling and client chat surface

**Feature Branch**: `ai/046-h3-conversational-journaling`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `H3` — "Conversational journaling and client chat surface" (delivery plan §3.8, band H).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.8, row H3):

> §7.3, §6.7.1, §8.10, §4.1, §6.7

### Freezes

Contracts this slice establishes for the first time:

- **Writing `conversation_id` and `turn_ordinal` on each conversational leg's
  `ai_request` row**: the client supplies both fields once per chat and
  incremented per leg respectively; the journal records them on the ordinary
  request row. The nullable columns were reserved in A5; this slice populates
  them and does not introduce a schema migration (§7.3; §6.7.1; delivery plan
  §3.8 Useful to know).
- **One indexed query returns a whole conversation ordered**: support and
  evals read a conversation as a unit by grouping and ordering legs on
  `conversation_id` / `turn_ordinal` — there is no `conversation` entity and
  no conversation table (§7.3; §6.7.1).
- **Each leg is independently admitted, journaled, and credited**: a
  conversation is a series of independent requests through the same pipeline;
  a `context_requested` leg is credited with actual usage because the
  inference happened; two rows, two admissions, two usage credits (§6.7.1;
  §6.7.2; §8.10).
- **No conversation entity and no per-request server-side state**: the
  platform holds no conversation session; the transcript lives on the client
  during the chat and in the per-leg R2 envelopes afterwards; the Quota
  Durable Object remains the only stateful component (§6.7.1; §6.7.4; §7.3).
- **The client Conversation store** (conversational capabilities only): holds
  the transcript of an open chat locally, resupplies it on each turn, and
  discards it when the conversation is closed; it MUST NOT interpret the
  transcript, classify the user's message, or choose which capability or
  which context keys a message needs (§4.1).
- **The client chat negotiation loop**: on `context_requested`, resolve the
  named keys through the existing Context Resolver under the user's own
  session and RLS, append the request and the resolved payload to the
  transcript, and submit the next leg with a new idempotency key; on
  `completed`, render the answer and append it to the transcript (§6.7.2;
  §8.10).
- **Cancellation stays connection-scoped per leg**: closing one leg's stream
  cancels only that leg; the conversation survives on the client, which still
  holds the transcript (§6.7.4; §8.10).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (C3, E2, E3, H1). Changing any is
out of scope by definition:

- **From C3 (journal writer, post-response detail, and get-request)**: the
  `ai_request` row written synchronously before work begins and updated with
  terminal state; every §6.3 transition timestamped; guard rejection produces
  no row; exactly one R2 envelope per request; `ai_attempt` and `usage_event`
  written after the response; get-request by request reference. H3 writes the
  reserved nullable `conversation_id` / `turn_ordinal` columns on those rows
  for conversational legs and relies on independent per-request admission and
  credit; it does not rewrite the journal lifecycle, the one-envelope rule, or
  the get-request contract (§7.3; C3 Freezes; delivery plan §3.4).
- **From E2 (AI Client SDK)**: AAT acquire/cache, submit with idempotency key,
  SSE consumption to a terminal event, cancel, no retry after a terminal
  platform error, last-N request references. H3 uses the SDK per leg with a
  **new** idempotency key for each leg; it does not rewrite transport,
  reminting, or terminal-retry rules (§4.1; §6.7.4; E2 Freezes).
- **From E3 (Context Resolver registry)**: the generic context key → resolver
  registry that assembles a payload from a key list, never receives or
  branches on a capability id, and caches only within a screen. H3 routes
  `context_requested` keys through that same Resolver with no capability
  branching; it does not add per-capability glue or a second resolution path
  (§4.1; §8.10; E3 Freezes).
- **From H1 (conversational manifest fields and context-request schema)**:
  `interaction_mode: conversational` with max history turns, max context
  rounds per turn, transcript size limit, and permitted key set;
  `context_requested` as a terminal event kind (not a taxonomy code);
  `AwaitingContext` as terminal and immutable; the platform-owned
  `{key, arguments}` schema. H3 journals and drives the client loop for those
  terminals; it does not redefine the manifest fields or the shared schema
  (§6.7.2; §6.7.4; H1 Freezes).

### Open decisions relied on

None — H3 freezes journaling of the reserved conversation columns and the
client Conversation store / chat loop. Concrete permitted key sets, numeric
max history turns / max context rounds, and whether chat output may enter a
clinical record remain product values on a capability version (Open Decisions
12, 13, and 14 apply at capability authoring / acceptance wiring, not in this
slice).

## Clarifications

### Session 2026-08-02

- Q: Where should the Conversation store and chat negotiation loop live under `frontend/`? → A: Under `frontend/lib/core/ai/` beside the E2 SDK and E3 Resolver (store + negotiation loop); widget/host chrome may still live under `features/ai/` for tests `[implementation choice — no §citation]`
- Q: How should conversational submit fields (`conversation_id`, `turn_ordinal`, `transcript`) enter the E2 SDK invoke path? → A: Optional fields on existing `CapabilityInvokeInput` (`conversationId`, `turnOrdinal`, `transcript`); omitted/null for `single_shot` `[implementation choice — no §citation]`
- Q: How should the H3 journaling integration tests construct multi-leg conversational paths (write `conversation_id` / `turn_ordinal`, ordered query, independent admit/credit, no conversation state)? → A: Full pipeline integration: submit conversational legs (fake provider + admission/credit/R2 spies), then assert D1 rows / ordered `conversation_id` query / no conversation table or per-request state `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Conversational journaling and client chat surface (Priority: P1)

As the AI Gateway journal and the Flutter Conversation store, for a capability
with `interaction_mode: conversational`, I write `conversation_id` and
`turn_ordinal` on each leg's ordinary `ai_request` row so a whole conversation
is readable with one indexed query ordered by those fields; I admit, journal,
and credit each leg independently — including crediting a `context_requested`
leg with actual usage — without introducing a conversation entity or any
per-request server-side state; and on the client I hold the transcript
locally, resupply it on each leg, resolve requested keys through the existing
Context Resolver with no capability branching, append the request and resolved
payload (or the completed answer), submit the next leg with a new idempotency
key, discard the transcript when the conversation closes, and treat
cancellation as connection-scoped to one leg so the conversation survives a
cancelled leg — so that support sees the same audit story as any other
request, grouped, and the client's ignorance of AI stays intact.

**Why this priority**: H3 sits where it does because its `Needs` (C3, E2, E3,
H1) freeze the journal writer and get-request path, the AI Client SDK, the
Context Resolver registry, and the conversational manifest /
`context_requested` / `AwaitingContext` contracts. Without those, H3 would
invent a conversation table, a second resolution path, or per-request session
state. Band H is placed late as the largest capability addition; the nullable
`conversation_id` / `turn_ordinal` columns were reserved in A5 so this slice
does not require a schema migration (delivery plan §3.8).

**Independent Test**: `conversation_id` and `turn_ordinal` are written per
leg, a whole conversation is readable with one indexed query, each leg is
independently admitted, journaled, and credited, and no conversation entity
and no per-request state is introduced; the client holds the transcript
locally, resupplies it per leg, resolves requested keys through the existing
Resolver, appends the request and payload, submits the next leg with a new
idempotency key, and discards the transcript when the conversation closes
(delivery plan §3.8 Done when; §3.11.7 row H3).

**Acceptance Scenarios**:

1. **Given** a conversational leg submitted with a client-supplied
   `conversation_id` and `turn_ordinal`, **When** the journal writer records
   the request, **Then** those two fields are written on that leg's
   `ai_request` row. *(Journaling: `conversation_id` and `turn_ordinal`
   written per leg)*
2. **Given** multiple legs sharing one `conversation_id` with distinct
   `turn_ordinal` values, **When** support reads the conversation with one
   indexed query, **Then** the whole conversation is returned ordered by
   `turn_ordinal`. *(One indexed query returns a whole conversation ordered)*
3. **Given** a multi-leg conversation, **When** each leg is processed,
   **Then** each leg is independently admitted, journaled as its own
   `ai_request` row, and credited — two legs yield two rows, two admissions,
   two usage credits. *(Each leg admitted and credited independently)*
4. **Given** a leg that terminates as `context_requested` / reaches
   `awaiting_context`, **When** usage is settled, **Then** the leg is credited
   with actual usage because the inference happened. *(A `context_requested`
   leg is credited with actual usage)*
5. **Given** a completed multi-leg conversation, **When** the D1 schema and
   runtime stores are inspected, **Then** there is no `conversation` table and
   no per-request state object was created — only ordinary request rows with
   the two nullable grouping columns. *(No conversation table and no
   per-request state object created)*
6. **Given** an open chat on a conversational capability, **When** the
   clinician types a free-text question, **Then** the client holds the
   transcript locally and does not interpret or classify the message — the
   chat window is the declared capability. *(Client: transcript held locally;
   no interpretation — §8.10)*
7. **Given** a subsequent leg of an open conversation, **When** the client
   submits, **Then** it resupplies the transcript so far on that leg.
   *(Transcript held locally and resupplied per leg)*
8. **Given** a terminal `context_requested` carrying named keys and
   arguments, **When** the client continues the conversation, **Then** those
   keys are resolved through the existing Context Resolver with no capability
   branching, under the user's own session and RLS. *(Requested keys resolved
   through the existing Resolver with no capability branching)*
9. **Given** resolved key payloads (or empty payloads where RLS denies),
   **When** the client prepares the next leg, **Then** it appends the
   `context_requested` turn and the `context_resolved` payload to the
   transcript. *(Appends the request and payload)*
10. **Given** the next leg after a completed answer or a context resolution,
    **When** the client submits, **Then** it uses a new idempotency key —
    distinct from the prior leg's key. *(Each leg uses a new idempotency key)*
11. **Given** the clinician closes the conversation, **When** the Conversation
    store tears down, **Then** the transcript is discarded. *(The transcript is
    discarded on close)*
12. **Given** an in-flight leg's stream, **When** that stream is closed /
    cancelled, **Then** only that leg is cancelled; the Conversation store
    still holds the transcript and the conversation survives. *(Closing one
    leg's stream cancels only that leg; the conversation survives a cancelled
    leg)*

### Test plan

Layer: Integration (spy) + Flutter (delivery plan §3.11.7, row H3; §13.5
Pipeline tests / Client contract tests as applicable).

Named tests:

**Journaling**

- `conversation_id_and_turn_ordinal_written_per_leg` — integration — each
  conversational leg's `ai_request` row carries the client-supplied
  `conversation_id` and `turn_ordinal` (§7.3; §6.7.1; delivery plan §3.11.7
  H3).
- `one_indexed_query_returns_whole_conversation_ordered` — integration — one
  indexed query by `conversation_id` returns all legs ordered by
  `turn_ordinal` (§7.3; §6.7.1; §8.10).
- `each_leg_admitted_and_credited_independently` — integration (spy) — N legs
  produce N admissions and N usage credits; no shared conversation counter is
  consulted (§6.7.1; §8.10).
- `context_requested_leg_credited_with_actual_usage` — integration — a leg
  terminating as `context_requested` / `awaiting_context` is credited with
  actual usage (§6.7.2; §8.10).
- `no_conversation_table_and_no_per_request_state_object` — integration (spy)
  — schema has no `conversation` entity/table; runtime creates no per-request
  state object (§7.3; §6.7.1; §6.7.4; delivery plan §6.4).

**Client**

- `transcript_held_locally_and_resupplied_per_leg` — Flutter — Conversation
  store holds the open-chat transcript and resupplies it on each submit
  (§4.1; §6.7.1; §8.10).
- `requested_keys_resolved_through_existing_resolver_no_capability_branching`
  — Flutter — `context_requested` keys are resolved via the E3 Context
  Resolver registry; the resolution path receives no capability id and does
  not branch on one (§4.1; §8.10; E3 Freezes).
- `each_leg_uses_new_idempotency_key` — Flutter — successive legs of the same
  conversation carry distinct idempotency keys (§6.7.4; §8.10).
- `transcript_discarded_on_close` — Flutter — closing the conversation
  discards the local transcript (§4.1; §8.10).
- `closing_one_leg_stream_cancels_only_that_leg` — Flutter — cancel/close of
  one leg's stream cancels only that leg (§6.7.4; §8.10).
- `conversation_survives_cancelled_leg` — Flutter — after a cancelled leg the
  Conversation store still holds the transcript and a further leg can be
  submitted (§6.7.4; §8.10).

Coverage additions from delivery plan §3.10 (every branch, every inherited
prohibition, every named boundary):

- `client_never_interprets_message_or_chooses_keys` — Flutter (spy) — free
  text is forwarded without interpretation; the store does not classify the
  message or choose which context keys are needed (§4.1; §8.10).
- `append_completed_answer_to_transcript` — Flutter — on terminal `completed`,
  the validated prose is appended to the local transcript (§6.7.2; §8.10).
- `append_context_request_and_resolved_payload_to_transcript` — Flutter — on
  `context_requested`, the request and the Resolver payload are appended
  before the next submit (§6.7.2; §8.10).
- `authorization_is_users_own_rls_not_reimplemented` — Flutter / integration —
  resolution runs under the requesting user's session; a user who may not see
  a patient receives nothing for that key (§8.10; §6.7.2).
- `platform_held_no_state_between_legs` — integration (spy) — after leg 1
  terminal and before leg 2 submit, the platform holds no conversation state
  between them (§8.10; §6.7.1).
- `no_second_r2_object_and_no_second_quota_do_round_trip_from_h3` —
  integration (spy) — H3 adds no second R2 object per request and no second
  Quota Durable Object round trip beyond the existing per-request budget
  (delivery plan §6.4; §7.5; §13.6).
- `no_prompt_provider_or_model_in_conversation_store` — Flutter / architecture
  guard — Conversation store and chat surface contain no prompt text, provider
  name, or model identifier (R-12; §4.1; delivery plan §6.4).
- `single_shot_unaffected_by_h3` — integration / Flutter — a `single_shot`
  capability does not acquire Conversation store behaviour or journalled
  conversation grouping from this slice's existence (§6.7 preamble; delivery
  plan §3.8).

### Edge Cases

- **Error codes this slice can emit**: none new. H3 journals and drives the
  client loop; transcript shape/budget rejections remain H2's
  `context_invalid` / `conversation_budget_exhausted` / `request_too_large`
  path (Consumes H1; neighbouring H2). Terminal platform errors continue to
  surface through the existing E2 SDK taxonomy without a new code from this
  slice.
- **Boundary — grouping fields**: `conversation_id` is supplied by the client
  once per chat; `turn_ordinal` is incremented per leg; both are written on
  the ordinary `ai_request` row and remain nullable for non-conversational
  requests (§7.3; §6.7.1).
- **Boundary — no conversation entity**: conversations add two nullable
  columns and no table; there is nothing about a conversation the platform
  owns (§7.3).
- **Boundary — independent accountability**: each leg is independently
  authenticated, admitted, journaled, and credited; a support engineer reading
  the conversation later sees what was asked, what was fetched, and what each
  turn cost — the same audit story as any other request, grouped (§8.10;
  §6.7.1).
- **Boundary — `context_requested` credit**: quota is credited with actual
  usage on a `context_requested` leg because the inference happened; the
  journal row reaches `awaiting_context` (§6.7.2; §8.10).
- **Boundary — new idempotency key per leg**: a transport retry of a leg
  returns that leg; it never re-runs the turn; the next leg always carries a
  new key (§6.7.4).
- **Boundary — cancellation**: a leg is one connection; closing it cancels
  that leg only; the conversation survives on the client (§6.7.4).
- **Boundary — Conversation store must-nots**: the store MUST NOT interpret
  the transcript, classify the user's message, or choose which capability or
  which context keys a message needs (§4.1).
- **Boundary — Resolver unchanged**: requested keys travel to the client; the
  client resolves them against Supabase under the requesting user's own
  session and RLS; the platform never fetches (§6.7.2; §8.10).
- **Failure branch — RLS denies a key**: if the user may not see the patient,
  the Resolver yields nothing for that key; authorization is not
  re-implemented on the platform (§8.10).
- **Inherited prohibition — no per-request server-side state**: H3 introduces
  none (§4.4; §9.7; delivery plan §6.4).
- **Inherited prohibition — no second R2 object / no second Quota DO trip**:
  H3 adds neither (delivery plan §6.4).
- No retry, caching, abstraction, or configurability beyond what the cited
  sections name (R-20; delivery plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each conversational leg MUST be an independent request through
  the same pipeline, tied together only by client-supplied `conversation_id`
  (once per chat) and `turn_ordinal` (incremented per leg) (§6.7.1).
- **FR-002**: The journal MUST write `conversation_id` and `turn_ordinal` on
  each conversational leg's `ai_request` row; those columns remain nullable
  for non-conversational requests; this slice MUST NOT add a schema migration
  for them (§7.3; delivery plan §3.8).
- **FR-003**: A whole conversation MUST be readable with one indexed query
  that groups and orders legs by `conversation_id` and `turn_ordinal` (§7.3;
  §6.7.1).
- **FR-004**: Conversations MUST add two nullable columns and no table; there
  MUST NOT be a `conversation` entity, because there is nothing about a
  conversation the platform owns (§7.3).
- **FR-005**: Each leg MUST carry the transcript so far as prior turns in the
  request body; the platform MUST read it, use it, journal a reference to it,
  and forget it — MUST NOT hold conversation state between legs (§6.7.1;
  §8.10).
- **FR-006**: Each leg MUST be independently admitted, journaled, and
  credited; a multi-leg conversation MUST produce one `ai_request` row, one
  admission, and one usage credit per leg (§6.7.1; §8.10).
- **FR-007**: A leg that terminates as `context_requested` MUST reach
  `awaiting_context` and MUST be credited with actual usage because the
  inference happened (§6.7.2; §8.10).
- **FR-008**: On terminal `completed`, the client MUST render the validated
  prose answer and append it to the transcript (§6.7.2).
- **FR-009**: On terminal `context_requested`, the client MUST resolve the
  named keys through the existing Context Resolver under the requesting
  user's own session and RLS, append the request and the resolved payload to
  the transcript, and submit the next leg (§6.7.2; §8.10).
- **FR-010**: The Context Resolver path used for conversational
  context-request resolution MUST remain a generic key → resolver registry: it
  MUST NOT receive a capability id and MUST NOT branch on one (§4.1; §8.10).
- **FR-011**: Each leg MUST carry its own idempotency key; the next leg MUST
  use a new idempotency key; a transport retry of a leg MUST return that leg
  and MUST NOT re-run the turn (§6.7.4; §8.10).
- **FR-012**: The Flutter Conversation store MUST hold the transcript of an
  open chat locally, resupply it on each turn, and discard it when the
  conversation is closed (§4.1).
- **FR-013**: The Conversation store MUST NOT interpret the transcript,
  classify the user's message, or choose which capability or which context
  keys a message needs; the client MUST forward the message without
  interpretation (§4.1; §8.10).
- **FR-014**: Cancellation MUST remain connection-scoped: closing one leg's
  stream MUST cancel only that leg; the conversation MUST survive on the
  client, which still holds the transcript (§6.7.4; §8.10).
- **FR-015**: H3 MUST NOT introduce a new pipeline stage, a new store, a new
  stateful component beyond the existing Quota Durable Object, per-request
  server-side state, a second R2 object per request, or a second Quota Durable
  Object round trip (§6.7.4; delivery plan §6.4).
- **FR-016**: The Conversation store and chat surface MUST NOT contain prompt
  text, provider names, or model identifiers (R-12; §4.1).
- **FR-017**: Authorization for resolved context MUST remain the intersection
  of the manifest's permitted key set and what the requesting user can read
  through RLS; the platform MUST NEVER fetch clinic data on the client's
  behalf (§6.7.2; §8.10).
- **FR-018**: `single_shot` capabilities MUST remain unaffected by this
  slice's existence; Conversation store behaviour and journalled conversation
  grouping apply only where the manifest declares
  `interaction_mode: conversational` (§6.7 preamble; delivery plan §3.8).

### Key Entities

- **`conversation_id`**: Client-supplied identifier, once per chat, that groups
  legs in the journal so support and evals can read a conversation as a unit;
  written on each conversational `ai_request` row; nullable otherwise (§6.7.1;
  §7.3).
- **`turn_ordinal`**: Client-incremented per-leg ordering field that orders
  legs in the journal and makes a replayed or reordered transcript detectable;
  written on each conversational `ai_request` row; nullable otherwise (§6.7.1;
  §7.3).
- **Leg**: One independent request through the §6.1 pipeline for a
  conversational capability; the unit of admission, journaling, credit,
  cancellation, and idempotency — not the conversation (§6.7.1; §6.7.4).
- **Conversation store**: Client-side component (conversational capabilities
  only) that holds the open-chat transcript locally, resupplies it per leg,
  and discards it on close; must not interpret, classify, or choose keys
  (§4.1).
- **Transcript (client-held)**: The series of prior turns the client resupplies
  on each leg; lives on the client during the chat and in the per-leg R2
  envelopes afterwards; not a platform-owned entity (§7.3; §6.7.1).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Multi-turn chat is delivered without a session store or
  conversation entity — only two nullable journal columns and a client-held
  transcript — keeping the platform simple and clinic-scale (constitution I;
  §7.3; §6.7.1).
- **Layer Placement**: This slice touches `ai-platform/` (Cloudflare Worker) —
  journaling `conversation_id` / `turn_ordinal` on ordinary `ai_request` rows
  and preserving per-leg admission/credit without a conversation table — and
  `frontend/` (Flutter) — the Conversation store and chat loop that resupplies
  the transcript, resolves keys through the existing Resolver, and uses a new
  idempotency key per leg. It does not change `backend/` (Supabase/PostgreSQL)
  schema or RPCs for this slice; context resolution continues to use existing
  E3 read RPCs under the caller's RLS. Per the architecture §14
  acknowledgement, the AI platform gateway is a non-primary, additive
  component with no domain logic, no business data, and no write path into
  Supabase; this slice adds no domain logic and no business data (§14;
  §4.1; §7.3).
- **Data Integrity & Security**: No `conversation` table and no Supabase write
  path from the gateway. Integrity is per-leg journaling plus client-side
  transcript custody. Clinic data reach remains the intersection of the
  permitted key set and the user's own RLS on Resolver reads (§8.10; §6.7.2).
- **Failure Handling**: Cancelling one leg cancels only that connection; the
  conversation survives locally. Platform or network failure on a leg surfaces
  through the existing E2 SDK terminal path with the request reference; AI
  remains additive and `single_shot` capabilities are unaffected (constitution
  V; §6.7.4; delivery plan §3.8).

## Out of Scope

- Slice H1 — conversational manifest fields and context-request schema
  (already frozen; H3 consumes, does not redefine).
- Slice H2 — transcript validation, conversation budgets, and composer
  rendering (§4.3.5, §6.7.1 wire validation, §6.7.3, §4.3.6): turn-shape
  rejection, budget codes, permitted-key allowlisting at the validator, and
  composer dual-shape rendering.
- Slice H4 — conversation evals (§13.5, A9).
- Slice J2 — `context_required` self-healing for `single_shot` stale caches
  (§8.4); conversational capabilities never take that path.
- Slice E4 — first AI feature surface provisional-draft UX beyond the
  Conversation store / chat loop this slice freezes; human acceptance into a
  clinical record (F2 / Open Decision 14).
- Choosing concrete numeric max history turns / max context rounds or a chat
  capability's permitted key set (Open Decisions 12 and 13).
- Redefining C3's journal lifecycle, one-envelope rule, or get-request
  contract; E2's transport / remint / terminal-retry rules; or E3's generic
  Resolver registry contract.
- A schema migration for `conversation_id` / `turn_ordinal` (reserved in A5).
- Platform-held conversation state, a Session Durable Object, out-of-band
  cancellation, or stream resume (§9.18; §9.7; §9.14).
- General tool use beyond context-key resolution restricted to the manifest's
  permitted set and executed by the client (§6.7.4).

Prohibitions copied from delivery plan §6.4:

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

- **SC-001**: Every conversational leg's `ai_request` row carries the
  submitted `conversation_id` and `turn_ordinal` (Done when; §7.3; §6.7.1).
- **SC-002**: One indexed query by `conversation_id` returns the whole
  conversation ordered by `turn_ordinal` (Done when; §7.3).
- **SC-003**: Automated integration (spy) tests prove each leg is
  independently admitted, journaled, and credited, and that a
  `context_requested` leg is credited with actual usage (Done when; §3.11.7
  H3; §6.7.2).
- **SC-004**: Automated integration (spy) tests prove no `conversation` table
  and no per-request state object exist after a multi-leg conversation (Done
  when; §7.3; §6.7.4; delivery plan §6.4).
- **SC-005**: Automated Flutter tests prove the Conversation store holds and
  resupplies the transcript per leg, resolves requested keys through the
  existing Resolver without capability branching, uses a new idempotency key
  per leg, and discards the transcript on close (Done when; §4.1; §8.10;
  §3.11.7 H3).
- **SC-006**: Automated Flutter tests prove closing one leg's stream cancels
  only that leg and that the conversation survives a cancelled leg (§6.7.4;
  §8.10; §3.11.7 H3).
- **SC-007**: Every named test in this slice's Test plan is present in CI and
  green (DP-3; delivery plan §3.10).

## Assumptions

- Prerequisites C3, E2, E3, and H1 are complete on `ai/master` (or otherwise
  available to this branch) so journal writing, the AI Client SDK, the Context
  Resolver, and conversational manifest / terminal-event contracts exist to
  consume.
- A5's nullable `conversation_id` / `turn_ordinal` columns already exist; H3
  populates them and does not migrate schema (delivery plan §3.8).
- H2 may land before or after H3 relative to product sequencing; this slice's
  `Needs` do not include H2. Runtime transcript shape/budget enforcement
  remains H2's responsibility when that slice is present.
- Open Decisions 12, 13, and 14 are not decided by this slice; they apply when
  a conversational capability is authored or when acceptance into a clinical
  record is wired.
- Primary operators of the chat surface are clinic staff on the Flutter
  desktop client; AI remains additive and optional (constitution I, V; A11).
- Nothing ships until the whole product does (DP-1); "independently testable"
  means provable by automated tests (DP-3).
