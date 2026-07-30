# Feature Specification: Diagnostic envelope — error taxonomy, request reference, trace propagation (A2)

**Feature Branch**: `ai/016-a2-diagnostic-envelope`

**Created**: 2026-07-30

**Status**: Draft

**Input**: Slice `A2` — *Diagnostic envelope: error taxonomy, request reference, trace propagation* (Delivery Plan §3.2, row A2).

> Constitution note: This slice provisions no new deployable component. It lives entirely inside the
> Cloudflare AI Gateway Worker (`ai-platform/`), the additive, non-primary component registered by A1.
> Per §14 acknowledgement of `17-ai-platform.md`, the gateway holds no domain logic, no business data,
> and has no write path into Supabase. This slice stays inside that boundary: it defines contracts and
> generators, not clinical behaviour.

## Slice Contract

### Implements

§5.4, §4.3.1, §13.1, §13.2 of `docs/architecture/17-ai-platform.md` (copied verbatim from the A2
`Canonical` cell, Delivery Plan §3.2).

### Freezes

This slice establishes, for the first time:

- **The error taxonomy**: the closed, stable set of codes from the §5.4 table, each with its meaning,
  HTTP status, retryability, and quota-consumption flag. The HTTP column is normative and is the only
  translation the protocol adapter may apply (§5.4).
- **The error-body contract**: every error response carries the request reference (A13), the trace id,
  and whether a retry is safe; the taxonomy code in the body — not the HTTP status — is what clients
  branch on (§5.4).
- **The request-reference format**: eight symbols from Crockford's base32 alphabet, uppercase, in two
  hyphen-separated groups of four — `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`, as in `7QK4-2B9F`;
  the alphabet omits `I`, `L`, `O`, `U`; values drawn from a CSPRNG; input normalised before lookup
  (case-folded up, `I`/`L` → `1`, `O` → `0`); the reference is a support handle, not a key — the
  request's identity is its ULID, and the generator retries on the vanishingly rare conflict (§8.9).
- **The trace-id propagation contract**: the trace id is client-generated and propagated through every
  stage and provider attempt as spans; structured logs always carry request reference, trace id,
  installation, capability, and prompt version (§13.1).

Later slices may extend these and may not rewrite them (Delivery Plan §2.3).

### Consumes

- **A1** — Worker skeleton and environments: the three isolated Worker environments (dev, staging,
  production) and their bindings, and the health endpoint that reports build and environment identity
  (A1 `Done when`). A2 runs inside that Worker and emits its logs and error bodies from it. Changing
  the environment topology or binding set is, by definition, out of scope.

### Open decisions relied on

None. A2 does not depend on any of the fourteen §15 decisions. The taxonomy, the request-reference
format, and the trace contract are fully specified by §5.4, §4.3.1, §13.1, §13.2, and §8.9.

## Clarifications

### Session 2026-07-30

- Q: What JSON field names and shape does the §5.4 error body use? → A: `{"code","request_reference","trace_id","retry_safe"}` with `retry_safe` as a boolean.
- Q: What is the generation-run size for the T21 uniqueness assertion? → A: 1,000,000 draws.
- Q: What format does the gateway-generated fallback trace id use? → A: ULID (26-char Crockford-base32).
- Q: How is the §5.4 "Retryable" column mapped to the boolean `retry_safe`? → A: false for `No` and `—`; true for all other Retryable values.
- Q: What does A2 actually test for `cancelled` given the get-request lookup belongs to C5/C7? → A: A2 tests `cancelled`→`499` classification + never-on-live-socket; the `200` lookup is deferred to C5/C7 (referenced, not run at A2).

## User Scenarios & Testing

### User Story 1 — A2: Diagnostic envelope — error taxonomy, request reference, trace propagation (Priority: P1)

As the platform reviewer, I want the gateway to own a closed error taxonomy with a normative HTTP
mapping, to generate a short, human-readable request reference for every request, and to thread a
caller-supplied trace id through every log line — so that every later slice that emits or handles an
error, every support lookup, and every diagnostic query is constrained by contracts that already exist
and cannot drift.

**Why this priority**: A2 sits second in Band A (Delivery Plan §3.2). It has `Needs: A1`: it presumes
the Worker skeleton and its bindings already exist, and nothing else. Every later slice that produces
or classifies a failure (B4–B8 rejections, C1 capability codes, C3 `context_required`/`context_invalid`,
C4 `request_too_large`, D5 `provider_unavailable`, D9/D10 `validation_failed`, D7 `cancelled`, A8 the
`accepted` event) presumes the taxonomy, the error body, the reference generator, and the trace
contract are already frozen. Without A2 those slices would each invent a code or a format, and the
no-rework rule (Delivery Plan §2.3) would make the resulting drift unfixable inside a slice.

**Independent Test**: Provable by automated unit and contract tests — every code in the §5.4 table
exists with its HTTP status, retryability, and quota-consumption flag; an unrecognised code is treated
as `internal_error`; every error body carries reference, trace id, and retry-safety; the request
reference generator produces a format-valid identifier unique across a large generation run; a
supplied trace id reaches every log line for that request; an absent trace id is generated (Delivery
Plan §3.2 A2 `Done when`, §3.11.1 A2). No user-facing behaviour is demonstrated (DP-3).

**Acceptance Scenarios**:

1. **Given** the §5.4 `unauthenticated` code, **When** an error response is built for it, **Then** the
   response carries HTTP 401, retryability "after re-mint", quota-consumption flag "No", and a body
   whose code is `unauthenticated`.
2. **Given** the §5.4 `installation_suspended` code, **When** an error response is built for it,
   **Then** the response carries HTTP 403, retryability "No", quota-consumption flag "No", and body
   code `installation_suspended`.
3. **Given** the §5.4 `forbidden_capability` code, **When** an error response is built for it,
   **Then** the response carries HTTP 403, retryability "No", quota-consumption flag "No", and body
   code `forbidden_capability`.
4. **Given** the §5.4 `rate_limited` code, **When** an error response is built for it, **Then** the
   response carries HTTP 429 with a `retry_after` value, retryability "Yes, after `retry_after`",
   quota-consumption flag "No", and body code `rate_limited`.
5. **Given** the §5.4 `quota_exhausted` code, **When** an error response is built for it, **Then** the
   response carries HTTP 429 with the period reset instant, retryability "Not until period reset",
   quota-consumption flag "No", and body code `quota_exhausted`.
6. **Given** the §5.4 `request_too_large` code, **When** an error response is built for it, **Then**
   the response carries HTTP 413, retryability "No", quota-consumption flag "No", and body code
   `request_too_large`.
7. **Given** the §5.4 `context_required` code, **When** an error response is built for it, **Then**
   the response carries HTTP 422, retryability "Yes, after resolving", quota-consumption flag "No",
   and body code `context_required`.
8. **Given** the §5.4 `context_invalid` code, **When** an error response is built for it, **Then** the
   response carries HTTP 422, retryability "No", quota-consumption flag "No", and body code
   `context_invalid`.
9. **Given** the §5.4 `conversation_budget_exhausted` code, **When** an error response is built for
   it, **Then** the response carries HTTP 409, retryability "No, within this conversation",
   quota-consumption flag "No", and body code `conversation_budget_exhausted`.
10. **Given** the §5.4 `capability_unknown` code, **When** an error response is built for it, **Then**
    the response carries HTTP 404, retryability "No", quota-consumption flag "No", and body code
    `capability_unknown`.
11. **Given** the §5.4 `capability_retired` code, **When** an error response is built for it, **Then**
    the response carries HTTP 404, retryability "No", quota-consumption flag "No", and body code
    `capability_retired`.
12. **Given** the §5.4 `capability_disabled` code, **When** an error response is built for it, **Then**
    the response carries HTTP 503, retryability "Later", quota-consumption flag "No", and body code
    `capability_disabled`.
13. **Given** the §5.4 `provider_unavailable` code, **When** an error response is built for it,
    **Then** the response carries HTTP 503, retryability "Yes", quota-consumption flag "Partially,
    recorded", and body code `provider_unavailable`.
14. **Given** the §5.4 `provider_rejected` code, **When** an error response is built for it, **Then**
    the response carries HTTP 422, retryability "No", quota-consumption flag "Yes", and body code
    `provider_rejected`.
15. **Given** the §5.4 `validation_failed` code, **When** an error response is built for it, **Then**
    the response carries HTTP 422, retryability "Yes, at user discretion", quota-consumption flag
    "Yes", and body code `validation_failed`.
16. **Given** the §5.4 `cancelled` code, **When** the envelope classifies it, **Then** it maps to the
    terminal value `499`, and `499` is never written to a live socket (a cancellation happens by the
    client closing the stream). The end-to-end "journaled `499` → later get-request lookup returns
    HTTP 200 with body code `cancelled`" path is a C5/C7 contract, referenced here and not run at A2.
17. **Given** the §5.4 `timeout` code, **When** an error response is built for it, **Then** the
    response carries HTTP 504, retryability "Yes", quota-consumption flag "Partially, recorded", and
    body code `timeout`.
18. **Given** the §5.4 `internal_error` code, **When** an error response is built for it, **Then**
    the response carries HTTP 500, retryability "Yes", quota-consumption flag "No", and body code
    `internal_error`.
19. **Given** a code string that is not one of the §5.4 codes, **When** the envelope classifies it,
    **Then** it is treated as `internal_error` (HTTP 500) rather than surfaced raw.
20. **Given** any error response produced by the gateway, **When** its body is inspected, **Then** it
    carries the fields `code`, `request_reference`, `trace_id`, and `retry_safe` (a boolean), so the
    client never has to guess and support never has to ask the user to reproduce.
21. **Given** the request reference generator runs for a generation run of 1,000,000 draws, **When** its output is
    inspected, **Then** every value matches `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`, is
    uppercase, contains no `I`/`L`/`O`/`U`, and is unique across the run.
22. **Given** a caller-supplied trace id is present on the request, **When** any log line is emitted
    for that request, **Then** every log line carries that supplied trace id.
23. **Given** no trace id is supplied by the caller, **When** the gateway handles the request, **Then**
    the gateway generates a trace id — a ULID (26-char Crockford-base32) — so that every log line still
    carries one, and it is propagated identically to a caller-supplied id.
24. **Given** a §5.4 code whose "Retryable" value is `No` or `—` (e.g. `installation_suspended`,
    `forbidden_capability`, `cancelled`), **When** its error body is built, **Then** `retry_safe` is
    false; and for every other §5.4 "Retryable" value, **Then** `retry_safe` is true.

### Edge Cases

- **No code maps to a bare `400`.** A malformed request body never reaches the taxonomy — it is
  rejected by the adapter's own parsing before a taxonomy code exists — so every taxonomy failure has
  a more specific status than "bad request" (§5.4). A test asserts the adapter rejects a malformed
  body without producing a taxonomy-coded error body.
- **`499` is not a registered status and is never written to a live socket.** A cancellation happens
  by the client closing the stream, so there is nobody left to receive a response; `499` is the value
  journaled for the terminal state and returned in the body of a later "get request" lookup, which is
  itself a `200` (§5.4). A test asserts `cancelled` is never emitted as an HTTP status on the stream
  and is present only as the journaled terminal code.
- **`429` carries two different payloads.** `rate_limited` carries `retry_after`; `quota_exhausted`
  carries the period reset instant. The pair shares a status because both mean "come back later", and
  the code distinguishes the remedy (§5.4). A test asserts each carries its own payload and not the
  other's.
- **`context_requested` is deliberately not a taxonomy code.** It is a terminal *event kind*
  alongside `completed`, not an error; conflating the two would make a normal conversational turn
  look like a failure in every dashboard the journal feeds (§5.4). A test asserts the envelope refuses
  to build an error response for `context_requested`.
- **The request reference is a support handle, not a key.** The request's identity is its ULID, and
  uniqueness is enforced by the unique index on `request_reference` in D1, with the generator retrying
  on the vanishingly rare conflict (§8.9). A2 owns the generator's format and CSPRNG sourcing; the
  D1-enforced uniqueness and retry-on-conflict against a stored row is established by the slice that
  owns the D1 schema (A6) — it is out of scope here. A test asserts the generator yields
  format-valid, collision-improbable values across a large in-memory run only.
- **Reference normalisation at lookup.** Input is normalised before lookup: case-folded up, and
  `I`/`L` → `1`, `O` → `0`, so a user who reads the string the way it looks still resolves it (§8.9).
  A test asserts a lowercase or confused-character input normalises to the stored reference. (The
  lookup itself belongs to F3; A2 provides the normalisation rule.)
- **Structured logs never carry prompts, context, or credentials.** The trace id and request reference
  appear on every log line, but no log line carries prompt text, context payload, or credentials
  (§13.1). A test asserts an error/log emission for a request containing a prompt and context emits
  neither.

### Test plan

Layer: Unit + contract (Delivery Plan §3.11.1 A2).

| # | Test | Layer | Source |
| --- | --- | --- | --- |
| T1 | `unauthenticated` → HTTP 401, retryability "after re-mint", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T2 | `installation_suspended` → HTTP 403, retryability "No", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T3 | `forbidden_capability` → HTTP 403, retryability "No", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T4 | `rate_limited` → HTTP 429 with `retry_after`, retryability "Yes, after `retry_after`", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T5 | `quota_exhausted` → HTTP 429 with period reset instant, retryability "Not until period reset", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T6 | `request_too_large` → HTTP 413, retryability "No", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T7 | `context_required` → HTTP 422, retryability "Yes, after resolving", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T8 | `context_invalid` → HTTP 422, retryability "No", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T9 | `conversation_budget_exhausted` → HTTP 409, retryability "No, within this conversation", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T10 | `capability_unknown` → HTTP 404, retryability "No", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T11 | `capability_retired` → HTTP 404, retryability "No", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T12 | `capability_disabled` → HTTP 503, retryability "Later", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T13 | `provider_unavailable` → HTTP 503, retryability "Yes", quota-consumption "Partially, recorded" | Unit + contract | §5.4; §3.11.1 A2 |
| T14 | `provider_rejected` → HTTP 422, retryability "No", quota-consumption "Yes" | Unit + contract | §5.4; §3.11.1 A2 |
| T15 | `validation_failed` → HTTP 422, retryability "Yes, at user discretion", quota-consumption "Yes" | Unit + contract | §5.4; §3.11.1 A2 |
| T16 | `cancelled` → classified to `499`; `499` is never written to a live socket (a cancellation happens by the client closing the stream). The end-to-end journaled-`499`-then-`200`-lookup path is a C5/C7 contract, referenced, not run at A2 | Unit + contract | §5.4; §3.11.1 A2 |
| T17 | `timeout` → HTTP 504, retryability "Yes", quota-consumption "Partially, recorded" | Unit + contract | §5.4; §3.11.1 A2 |
| T18 | `internal_error` → HTTP 500, retryability "Yes", quota-consumption "No" | Unit + contract | §5.4; §3.11.1 A2 |
| T19 | An unrecognised code is treated as `internal_error` (HTTP 500), never surfaced raw | Unit + contract | §5.4; §3.11.1 A2 |
| T20 | Every error body is the JSON object `{"code","request_reference","trace_id","retry_safe"}` with `retry_safe` a boolean | Unit + contract | §5.4; §3.11.1 A2 |
| T21 | Generated request references match `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`, are uppercase, omit `I`/`L`/`O`/`U`, and are unique across a generation run of 1,000,000 draws | Unit + contract | §8.9; §3.11.1 A2 |
| T22 | A supplied trace id appears on every log line emitted for that request | Unit + contract | §13.1; §4.3.1; §3.11.1 A2 |
| T23 | An absent trace id is generated as a ULID (26-char Crockford-base32), so every log line still carries one, and is propagated identically to a caller-supplied id | Unit + contract | §13.1; §3.11.1 A2 |
| T24 | No error body is built for `context_requested` (it is an event kind, not a taxonomy code) | Unit + contract | §5.4 |
| T25 | A malformed request body is rejected by the adapter's own parsing and never produces a taxonomy-coded error body (no code maps to bare `400`) | Unit + contract | §5.4 |
| T26 | A `rate_limited` body carries `retry_after` and not the period reset instant; a `quota_exhausted` body carries the period reset instant and not `retry_after` | Unit + contract | §5.4 |
| T27 | No log line carries prompt text, context payload, or credentials, even for a request that contained them | Unit + contract | §13.1 |
| T28 | Request-reference normalisation: a lowercase or `I`/`L`/`O`-confused input normalises to the stored reference form | Unit + contract | §8.9 |
| T29 | `retry_safe` is false for §5.4 "Retryable" values `No` and `—`, and true for every other value (`After re-mint`, `Yes`, `Yes, after retry_after`, `Not until period reset`, `No, within this conversation`, `Later`, `Yes, at user discretion`) | Unit + contract | §5.4 |

## Requirements

### Functional Requirements

- **FR-001**: The platform MUST own a closed, stable set of error codes; providers' native errors are
  always mapped into them and never surfaced raw (§5.4).
- **FR-002**: For each code in the §5.4 table, the envelope MUST expose its meaning, its HTTP status,
  its retryability, and its quota-consumption flag, exactly as the table lists them; the HTTP column is
  normative and is the only translation the protocol adapter (`§4.3.1`) may apply (§5.4).
- **FR-003**: The taxonomy code carried in the error body — not the HTTP status — MUST be what clients
  branch on (§5.4).
- **FR-004**: Every error response MUST carry the request reference (A13), the trace id, and whether a
  retry is safe, so the client never has to guess and support never has to ask the user to reproduce
  (§5.4). The error body is the JSON object `{"code","request_reference","trace_id","retry_safe"}`,
  where `retry_safe` is a boolean (Delivery Plan §3.2 A2; §5.4). The `retry_safe` boolean MUST be
  false for the §5.4 "Retryable" values `No` and `—` (no retry is productive) and true for every other
  value in that column (`After re-mint`, `Yes`, `Yes, after retry_after`, `Not until period reset`,
  `No, within this conversation`, `Later`, `Yes, at user discretion`) — i.e. a retry *can* succeed
  once the gate clears (§5.4).
- **FR-005**: No code MUST map to a bare `400`; a malformed request body is rejected by the adapter's
  own parsing and never reaches the taxonomy (§5.4).
- **FR-006**: `429` MUST carry `retry_after` for `rate_limited` and the period reset instant for
  `quota_exhausted`; the pair shares a status and the code distinguishes the remedy (§5.4).
- **FR-007**: `499` MUST NOT be written to a live socket — a cancellation happens by the client closing
  the stream — and is the value journaled for the terminal state, returned in the body of a later "get
  request" lookup, which is itself a `200` (§5.4). At A2, only the taxonomy classification (`cancelled`
  → `499`) and the never-on-live-socket rule are in scope and testable; the journaled-`499`-then-`200`-
  lookup end-to-end path is a C5/C7 contract and is referenced here, not run by this slice.
- **FR-008**: `context_requested` MUST NOT appear in the taxonomy; it is a terminal event kind
  alongside `completed`, not an error, and the envelope MUST NOT build an error response for it (§5.4).
- **FR-009**: An unrecognised code — one not in the §5.4 table — MUST be treated as `internal_error` and
  MUST NOT be surfaced raw; a code outside the closed set is a platform defect (§5.4).
- **FR-010**: The request reference generator MUST produce values of eight symbols from Crockford's
  base32 alphabet, uppercase, in two hyphen-separated groups of four, matching
  `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` (e.g. `7QK4-2B9F`); the alphabet MUST omit `I`, `L`,
  `O`, and `U` (§8.9).
- **FR-011**: Reference values MUST be drawn from a CSPRNG rather than derived from a counter or
  timestamp, so collisions are not a practical concern at clinic-scale volumes (§8.9).
- **FR-012**: The request reference MUST be treated as a support handle, not a key; the request's
  identity is its ULID, and uniqueness is enforced by the unique index on `request_reference` in D1,
  with the generator retrying on the vanishingly rare conflict (§8.9).
- **FR-013**: Reference-input lookup MUST normalise before comparison: case-folded up, and `I`/`L` → `1`,
  `O` → `0`, so a user who reads the string the way it looks still resolves it (§8.9).
- **FR-014**: The trace id MUST be client-generated and propagated through every stage and provider
  attempt as spans, so logs, metrics, and the journal join without a correlation heuristic (§13.1,
  §8.9 property 3, §4.3.1 "client trace id" header).
- **FR-015**: Structured logs MUST always carry the request reference, the trace id, installation,
  capability, and prompt version; logs MUST never carry prompts, context, or credentials (§13.1).
- **FR-016**: When the caller supplies no trace id, the gateway MUST generate one — a ULID (26-char
  Crockford-base32), the same opaque identifier shape the request identity uses (§8.9) — so that every
  log line still carries a trace id (§13.1 — "always carrying ... trace id"). The generated id MUST
  be treated identically to a caller-supplied one for propagation and logging; it is not a separate
  kind of value.

### Key Entities

Not applicable — this slice defines no D1 entities. The request-reference generator produces an
in-memory value; the D1 column and unique index that persist it are established by A6 (D1 schema and
migrations), which is out of scope here.

## Constitution Alignment

### Architecture & Operations Impact

- **Clinic Fit**: This slice serves small-to-mid-size multi-branch clinics by giving every AI request
  failure a short reference a clinician can read aloud over the phone, and by keeping provider native
  errors out of the client. No enterprise-scale assumption is introduced.
- **Layer Placement**: This slice touches `ai-platform/` (the Cloudflare Worker) only — specifically the
  protocol adapter (`§4.3.1`) and the diagnostic contracts (`§5.4`, `§13.1`, `§13.2`). It touches
  neither `backend/` (Supabase) nor `frontend/` (Flutter). The gateway is a non-primary, additive
  component per the §14 acknowledgement: it holds no domain logic, no business data, and has no write
  path into Supabase; this slice stays inside that boundary.
- **Data Integrity & Security**: A2 writes no business data. It emits structured logs that MUST NOT
  carry prompts, context, or credentials (§13.1). The request reference is a non-key support handle
  derived from a CSPRNG; the request's authoritative identity is its ULID, persisted and indexed by a
  later slice (A6).
- **Failure Handling**: The taxonomy itself is the failure-handling contract: every failure the later
  guard can produce has a named code, a normative HTTP status, and a retry-safety flag, so a later
  client can degrade correctly. A2 does not introduce runtime degradation behaviour of its own.

## Out of Scope

- **Neighbouring slices this one touches:**
  - **A1** — Worker skeleton and environments: A2 consumes the Worker and its bindings; it does not
    alter the environment topology or the health endpoint.
  - **A6** — D1 schema and migrations: the `request_reference` column and its unique index, and the
    generator's retry-on-conflict against a stored row, belong to A6. A2 provides the generator's
    format, CSPRNG sourcing, and normalisation rule only; the uniqueness assertion in A2 is a
    generative, in-memory one.
  - **A8** — Protocol adapter and SSE framing: A8 owns the `accepted` event that carries the request
    reference on the stream, the header parsing of the client trace id, and the actual emission of
    HTTP status on the wire. A2 owns the contracts and generators those emit; the live-stream
    behaviour is A8.
  - **C5 / C7** — Journal writer and get-request endpoint: the `499` journaled terminal state and the
    `200` get-request body that returns `cancelled` are produced by the journal and lookup slices.
    A2 defines the code and the prohibition against writing `499` to a live socket; the persistence
    is theirs.
  - **F3** — Support lookup: the indexed D1 lookup by reference and the input normalisation at lookup
    time belong to F3. A2 pins the normalisation rule; F3 applies it.

- **Prohibitions (Delivery Plan §6.4) — none are added here, and all are observed:**
  - No mechanism from §9.14 is added because it looks prudent (R-20).
  - No prompt text, provider name, or model identifier is placed in the Flutter client (R-12) — A2
    touches no client code.
  - No second Quota Durable Object round trip and no second R2 object per request is introduced
    (§7.5, §13.6) — A2 does neither.
  - No guard rejection is journaled as a request, and no D1 row per stream chunk is written (§7.5) —
    A2 writes no D1.
  - No per-request server-side state of any kind is introduced (§4.4, §9.7) — the reference generator
    is stateless.
  - No client-side assembly of a final result from chunks and no committable provisional content
    (§6.4, A5) — A2 is unrelated to streaming content.

- **No additional error handling, retries, caching, abstraction, or configurability** beyond the cited
  sections is introduced (R-20). In particular: no retry of reference generation beyond the
  D1-index-driven retry defined in §8.9 (which belongs to A6); no log sampling or export policy (§13.1
  states logs may be sampled and exported, but the policy is not this slice's to set); no metrics store
  (§13.1 places metrics on the journal's side of the line, owned by later slices).

## Success Criteria

- **SC-001**: All eighteen §5.4 codes (`unauthenticated`, `installation_suspended`, `forbidden_capability`,
  `rate_limited`, `quota_exhausted`, `request_too_large`, `context_required`, `context_invalid`,
  `conversation_budget_exhausted`, `capability_unknown`, `capability_retired`, `capability_disabled`,
  `provider_unavailable`, `provider_rejected`, `validation_failed`, `cancelled`, `timeout`,
  `internal_error`) are present and each maps to the exact HTTP status, retryability, and
  quota-consumption flag the table specifies — provable by T1–T18.
- **SC-002**: An unrecognised code is treated as `internal_error` and never surfaced raw — provable by
  T19.
- **SC-003**: Every error body carries `code`, `request_reference`, `trace_id`, and `retry_safe` (a
  boolean that is false for §5.4 "Retryable" values `No` and `—`, true for every other value) —
  provable by T20 and T29.
- **SC-004**: The request reference generator produces format-valid, uppercase, Crockford-base32
  values, unique across a large generation run — provable by T21.
- **SC-005**: A caller-supplied trace id reaches every log line for that request, and an absent trace
  id is generated — provable by T22 and T23.
- **SC-006**: No log line carries prompt text, context, or credentials — provable by T27.

## Assumptions

- The Worker skeleton, its three environments, and its bindings already exist from A1; A2 adds
  contracts and generators to that Worker and does not provision infrastructure.
- A2's reference generator is stateless and in-memory; the D1 unique index on `request_reference` and
  the retry-on-conflict-against-a-stored-row behaviour are established by A6, so A2's uniqueness
  evidence is a large in-memory generation run, not a stored-row conflict test.
- The trace id is client-generated in the ordinary case (§13.1); the "generate when absent" behaviour
  (FR-016, T23) exists only to keep the "every log line carries a trace id" invariant true for callers
  that omit one, and does not change the contract that the trace id is client-generated when supplied.
- The platform does not ship until the whole product does (DP-1); "independently testable" means
  provable by an automated test, not demonstrable to a user (DP-3).