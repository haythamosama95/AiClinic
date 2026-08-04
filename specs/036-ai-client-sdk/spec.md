# Feature Specification: AI Client SDK

**Feature Branch**: `ai/036-e2-ai-client-sdk`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `E2` — "AI Client SDK" (delivery plan §3.6, band E).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.6, row E2):

> §4.1, §5.5, §5.4

### Freezes

Contracts this slice establishes for the first time:

- The **AI Client SDK** as the Flutter transport component named in §4.1: acquire an
  AAT, submit a capability request with an idempotency key, consume the event stream,
  surface terminal state, expose cancel, retry on transport errors, and hold the last
  request reference for support — and nothing else from the §4.1 client table.
- The **AAT acquire-and-cache** behaviour on the client: the SDK acquires an AAT and
  caches it for subsequent submissions; on `unauthenticated` it silently re-mints once
  and retries once, and it does not enter a re-mint loop (§4.1; §5.4 `unauthenticated`
  client behaviour; delivery plan §3.6 Done when; §3.11.5 E2).
- The **stable client-generated idempotency key** for a single user action: the same key
  is submitted across transport retries of that action (delivery plan §3.6 Done when;
  §3.11.5 E2; §4.1 submit-with-idempotency-key; §5.5 Submit request).
- The **client-side SSE consumption rules** for the surfaces the SDK owns: open on
  `accepted` (request reference), consume typed content/heartbeat events, end on exactly
  one terminal event (`completed`, `failed`, or `cancelled` for the capabilities this
  slice can invoke), with cancel performed by closing the stream and no separate cancel
  endpoint (§5.5 rules 1–5; §4.1).
- The **no-auto-retry-after-terminal-platform-error** rule on the client: the SDK retries
  on transport errors only; after a terminal platform error (a §5.4 taxonomy outcome that
  ends the request) it does not auto-retry, except the single `unauthenticated` re-mint
  path (§4.1 Must not; §5.4; delivery plan §3.6 Done when).
- The **unknown taxonomy code → `internal_error`** mapping on the client when a stream or
  error body carries a code outside the §5.4 closed set (delivery plan §3.11.5 E2;
  Consumes A2 via A6).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (E1, A6, C1). Changing any is out of scope by
definition:

- **E1 — Client architecture guard (R-12)**: the CI lint that fails the Flutter build on
  prompt-like strings, provider names, or model identifiers anywhere in client code.
  E2 adds client AI transport code that must remain free of those and must not weaken or
  bypass the guard (DP-6; delivery plan §3.6; §4.1 Must not: embed prompt fragments /
  decide model or provider).
- **A6 — Protocol adapter and SSE framing** (§4.3.1, §5.5): submit-request wire format
  and headers (idempotency key, client trace id, capability version pin); SSE framing
  (`accepted` with request reference, heartbeats, one-terminal-event invariant for
  `completed` / `failed` / `cancelled`); connection-scoped cancel by closing the stream;
  on-the-wire §5.4 HTTP mapping and error body. E2 is a client of this wire contract; it
  does not redefine event kinds, headers, or the one-terminal-event rule.
- **A2 via A6 — Error taxonomy and diagnostic envelope** (§5.4): the closed code set,
  retryability and client-behaviour columns, request reference on every error, and the
  rule that an unrecognised code is treated as `internal_error`. E2 branches on these
  codes; it adds none and changes none.
- **C1 — Capability registry, resolver, and discovery** (§4.3.4, §5.1, §5.5 discovery /
  version pin): capability id plus requested version resolve to an immutable manifest;
  discovery returns active manifests. E2 submits capability requests and version pins
  against that contract; it does not implement discovery UX, the Context Resolver, or
  capability branching in the client.

### Open decisions relied on

None. E2 does not depend on any §15 decision. AAT acquisition, idempotency, SSE
consumption, cancel, last request-reference retention, and the no-retry-after-terminal
rule are fully specified by §4.1, §5.5, §5.4, and delivery plan §3.6 / §3.11.5.

## Clarifications

### Session 2026-08-02

- Q: Where should the AI Client SDK module live under the Flutter client? → A: `frontend/lib/core/ai/` — SDK beside other core transport/orchestration code `[implementation choice — no §citation]`
- Q: How should Flutter unit/integration tests (T1–T28) drive AAT mint, HTTPS submit, and SSE streams without a live Worker? → A: Injectable ports (mint, HTTPS submit, SSE) backed by in-memory fakes/spies that emit canned A6 sequences and §5.4 codes — no network `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - AI Client SDK (Priority: P1)

As the Flutter calling component that will host later AI surfaces, I want a transport-only
AI Client SDK that acquires and caches an AAT, re-mints once on `unauthenticated`, submits
with a stable idempotency key, consumes the SSE event stream through to a single terminal
event, surfaces that terminal state, exposes cancel by closing the stream, retains the last
request reference for support, retries only on transport errors, and never auto-retries
after a terminal platform error — so that E3 and E4 can resolve context and render drafts
against a frozen client transport without learning prompts, providers, or models.

**Why this priority**: E2 has `Needs: E1, A6, C1` (delivery plan §3.6). E1 must already
guard the client (DP-6); A6 must already freeze the SSE/wire contract; C1 must already
freeze capability identity and discovery. Without this SDK, later band-E slices have no
shared transport for AAT, idempotency, streaming, or cancel, and would each invent one —
violating the no-rework rule (delivery plan §2.3) and the §4.1 seam that keeps AI
internals out of Flutter.

**Independent Test**: The SDK acquires and caches an AAT, re-mints once on
`unauthenticated`, submits with a stable idempotency key, consumes the event stream,
surfaces terminal state, exposes cancel, retains the last N request references, and never
retries after a terminal platform error (delivery plan §3.6 Done when; §3.11.5 row E2).
Provable by Flutter unit and integration tests (DP-3). Per §4.1, request-reference
retention is the last request reference held for support; the §3.11.5 "last-N" case
asserts that retention behaviour without inventing a numeric window beyond what §4.1
names.

**Acceptance Scenarios**:

1. **Given** an authenticated clinic session and a reachable AAT mint path, **When** the
   SDK needs an AAT for a submit, **Then** it acquires an AAT and caches it for subsequent
   submissions without re-minting on every call (§4.1; delivery plan §3.11.5 E2
   "Token acquired and cached").
2. **Given** a cached AAT that the platform rejects as `unauthenticated`, **When** the SDK
   receives that code, **Then** it silently re-mints an AAT once, retries the same
   submission once, and that retry succeeds when the new token is valid (§5.4
   `unauthenticated`; delivery plan §3.11.5 E2 "one re-mint on `unauthenticated` then
   success").
3. **Given** a platform that keeps returning `unauthenticated` after the first re-mint,
   **When** the SDK has already re-minted once for that submission, **Then** it does not
   re-mint again and surfaces `unauthenticated` (no re-mint loop) (§5.4 Retryable "After
   re-mint"; delivery plan §3.11.5 E2 "no re-mint loop").
4. **Given** a single user action whose HTTPS submit fails with a transport error before a
   terminal platform event, **When** the SDK retries that action on the transport, **Then**
   every retry carries the same client-generated idempotency key (§4.1; §5.5 Submit
   request; delivery plan §3.11.5 E2 "idempotency key is stable across transport retries").
5. **Given** an open SSE stream that emits `accepted`, optional heartbeats/content, and
   exactly one terminal event, **When** the SDK consumes the stream, **Then** it surfaces
   that terminal state to the caller and does not infer completion from silence (§5.5
   rules 1–4; §4.1; delivery plan §3.11.5 E2 "stream consumed to its terminal event").
6. **Given** an in-flight streamed request, **When** the caller invokes cancel, **Then**
   the SDK closes the stream (connection-scoped cancel; no separate cancel endpoint) and
   the request ends as cancelled (§5.5 Cancel row and rule 5; §4.1 expose cancel; delivery
   plan §3.11.5 E2 "cancel closes the stream").
7. **Given** a terminal `failed` (or equivalent terminal platform outcome) carrying any
   §5.4 taxonomy code whose client behaviour is not the `unauthenticated` re-mint path,
   **When** the SDK has surfaced that terminal state, **Then** it does not auto-retry the
   submission — one case per such code (§4.1 Must not "retry after a *terminal* platform
   error"; §5.4; delivery plan §3.11.5 E2 "one case per terminal code proving no retry").
8. **Given** a stream that has produced an `accepted` event (and/or a terminal error body)
   carrying a request reference, **When** the request ends, **Then** the SDK retains the
   last request reference for support (§4.1; delivery plan §3.11.5 E2 "last-N references
   retained"; Done when).
9. **Given** a terminal error or `failed` event whose code is not in the §5.4 closed set,
   **When** the SDK maps that code for the caller, **Then** it treats the code as
   `internal_error` (delivery plan §3.11.5 E2; Consumes A2 via A6).

### Test plan

The minimum test set is the E2 row of delivery plan §3.11.5 (layer: *Flutter unit +
integration*). Tests join CI permanently (delivery plan §3.10). Named tests use that
Flutter unit + integration layer.

| # | Named test | Layer | Asserts |
| --- | --- | --- | --- |
| T1 | `sdk_aat_acquired_and_cached` | Flutter unit + integration | Token acquired and cached; a second submit reuses the cache without a second mint when the token remains valid (§3.11.5 E2; §4.1) |
| T2 | `sdk_unauthenticated_remints_once_then_succeeds` | Flutter unit + integration | One re-mint on `unauthenticated` then success; spy shows exactly one re-mint and one retry (§5.4; §3.11.5 E2) |
| T3 | `sdk_unauthenticated_no_remint_loop` | Flutter unit + integration | After one re-mint, a second `unauthenticated` is surfaced with no further mint (§5.4; §3.11.5 E2) |
| T4 | `sdk_idempotency_key_stable_across_transport_retries` | Flutter unit + integration | The idempotency key is identical across transport retries of the same action (§4.1; §5.5; §3.11.5 E2) |
| T5 | `sdk_stream_consumed_to_terminal_event` | Flutter unit + integration | Stream consumed through `accepted` to exactly one terminal event; terminal state surfaced; completion not inferred from silence (§5.5 rules 1–4; §3.11.5 E2) |
| T6 | `sdk_cancel_closes_stream` | Flutter unit + integration | Cancel closes the stream; no separate cancel endpoint is called (§5.5; §4.1; §3.11.5 E2) |
| T7 | `sdk_no_retry_after_installation_suspended` | Flutter unit + integration | Terminal `installation_suspended` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T8 | `sdk_no_retry_after_forbidden_capability` | Flutter unit + integration | Terminal `forbidden_capability` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T9 | `sdk_no_retry_after_rate_limited` | Flutter unit + integration | Terminal `rate_limited` → SDK does not auto-retry (caller may later honour `retry_after`; SDK does not invent a loop) (§5.4; §4.1; §3.11.5 E2) |
| T10 | `sdk_no_retry_after_quota_exhausted` | Flutter unit + integration | Terminal `quota_exhausted` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T11 | `sdk_no_retry_after_request_too_large` | Flutter unit + integration | Terminal `request_too_large` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T12 | `sdk_no_retry_after_context_required` | Flutter unit + integration | Terminal `context_required` → no auto-retry in E2 (self-healing resubmit is J2) (§5.4; §4.1; §3.11.5 E2; Out of Scope J2) |
| T13 | `sdk_no_retry_after_context_invalid` | Flutter unit + integration | Terminal `context_invalid` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T14 | `sdk_no_retry_after_conversation_budget_exhausted` | Flutter unit + integration | Terminal `conversation_budget_exhausted` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T15 | `sdk_no_retry_after_capability_unknown` | Flutter unit + integration | Terminal `capability_unknown` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T16 | `sdk_no_retry_after_capability_retired` | Flutter unit + integration | Terminal `capability_retired` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T17 | `sdk_no_retry_after_capability_disabled` | Flutter unit + integration | Terminal `capability_disabled` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T18 | `sdk_no_retry_after_provider_unavailable` | Flutter unit + integration | Terminal `provider_unavailable` → no auto-retry by the SDK (§5.4; §4.1; §3.11.5 E2) |
| T19 | `sdk_no_retry_after_provider_rejected` | Flutter unit + integration | Terminal `provider_rejected` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T20 | `sdk_no_retry_after_validation_failed` | Flutter unit + integration | Terminal `validation_failed` → no auto-retry by the SDK (§5.4; §4.1; §3.11.5 E2) |
| T21 | `sdk_no_retry_after_cancelled` | Flutter unit + integration | Terminal `cancelled` → no auto-retry (§5.4; §4.1; §3.11.5 E2) |
| T22 | `sdk_no_retry_after_timeout` | Flutter unit + integration | Terminal `timeout` → no auto-retry by the SDK (§5.4; §4.1; §3.11.5 E2) |
| T23 | `sdk_no_retry_after_internal_error` | Flutter unit + integration | Terminal `internal_error` → no auto-retry by the SDK (§5.4; §4.1; §3.11.5 E2) |
| T24 | `sdk_last_request_reference_retained` | Flutter unit + integration | Last request reference retained for support after a request that carried one (§4.1; §3.11.5 E2 "last-N references retained") |
| T25 | `sdk_unknown_error_code_treated_as_internal_error` | Flutter unit + integration | An unknown error code is treated as `internal_error` (§3.11.5 E2; Consumes A2 via A6) |
| T26 | `sdk_transport_retry_allowed` | Flutter unit + integration | A transport failure before a terminal platform event is retried by the SDK with the same idempotency key (§4.1 "retry on transport errors"; T4 companion) |
| T27 | `sdk_does_not_interpret_model_output` | Flutter unit + integration | Spy/contract: the SDK surfaces stream events and terminal payload as received; it does not transform model output into a different shape (§4.1 Must not) |
| T28 | `sdk_contains_no_prompt_provider_or_model_identifiers` | Flutter unit + integration | The SDK sources under `frontend/` pass the E1 architecture guard (R-12; delivery plan §6.4; §4.1 Must not) |

Coverage (delivery plan §3.10): happy path of every requirement (T1, T4–T6, T24, T26);
every §5.4 code this slice can surface as a terminal outcome with a no-auto-retry proof
(T7–T23) plus the `unauthenticated` re-mint branches (T2–T3) and unknown→`internal_error`
(T25); every branch of the stated rules (cache hit, remint once, remint loop stop,
transport retry, cancel, stream-to-terminal); inherited prohibitions from delivery plan
§6.4 / R-12 (T28) and no client-side assembly of a final result from chunks (T27; Out of
Scope); named boundaries — one remint ceiling (T2–T3), stable idempotency across transport
retries (T4), connection-scoped cancel only (T6), last request-reference retention (T24).

### Edge Cases

- **`unauthenticated` after cache hit**: re-mint once and retry once; a second
  `unauthenticated` must not loop (§5.4; T2–T3).
- **Transport error versus terminal platform error**: transport failures may be retried
  with the same idempotency key (§4.1); taxonomy terminal outcomes must not be auto-retried
  (T7–T23; T26).
- **`rate_limited` / `timeout` / `provider_unavailable` / `validation_failed` /
  `internal_error`**: §5.4 marks some as retryable for the *caller*; the SDK still must
  not auto-retry them (T9, T18, T20, T22, T23). Offering a user-facing retry is a later
  surface concern (E4), not E2.
- **`context_required`**: §5.4 allows retry after resolving keys; automatic refresh and
  single resubmit are J2. E2 surfaces the terminal code and does not auto-resubmit (T12).
- **Cancel versus network drop**: closing the stream cancels; the platform does not
  distinguish user cancel from drop (§5.5 rule 5). The SDK exposes cancel as stream close
  (T6).
- **Unknown taxonomy code**: mapped to `internal_error` (T25); never surfaced raw
  (Consumes A2).
- **Missing or invalid AAT before first mint**: acquisition path must mint before submit
  (§4.1); failure to mint surfaces without inventing a taxonomy code beyond what the mint
  path and §5.4 already name.
- **Provisional / content events**: the SDK relays typed stream events and must not
  assemble a final result from chunks or treat provisional content as committable
  (§4.1 Must not interpret/transform; delivery plan §6.4; T27).
- **Conversational fourth terminal kind**: `context_requested` is H1. E2's single-shot
  clients never receive it (§5.5 rule 4); conversational submit/transcript handling is Out
  of Scope (H3).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Flutter application MUST include an **AI Client SDK** that is a
  transport concern only: acquire an AAT, submit a capability request with an idempotency
  key, consume the event stream, surface terminal state, expose cancel, retry on transport
  errors, and hold the last request reference for support. `(§4.1)`
- **FR-002**: The SDK MUST NOT interpret or transform model output; MUST NOT decide which
  model or provider to use; MUST NOT embed prompt fragments; and MUST NOT retry after a
  *terminal* platform error. `(§4.1)`
- **FR-003**: The SDK MUST acquire an AAT and cache it for reuse across submissions while
  the cached token remains accepted by the platform. `(§4.1; delivery plan §3.6 Done when;
  §3.11.5 E2)`
- **FR-004**: On `unauthenticated`, the SDK MUST silently re-mint an AAT and retry once,
  and MUST NOT re-mint in a loop. `(§5.4; delivery plan §3.6 Done when; §3.11.5 E2)`
- **FR-005**: Every submission MUST carry a client-generated idempotency key that remains
  stable across transport retries of the same user action. `(§4.1; §5.5 Submit request;
  delivery plan §3.6 Done when; §3.11.5 E2)`
- **FR-006**: Submit MUST create an AI request for a capability with intent, context
  payload, idempotency key, and version pin as required by the §5.5 Submit surface, and
  MUST consume the SSE stream per §5.5 rules 1–4 (`accepted` with request reference;
  typed content; heartbeats; exactly one terminal event). `(§5.5; §4.1)`
- **FR-007**: The SDK MUST surface the terminal state of the stream to the caller
  (`completed` with the validated result, `failed` with a §5.4 taxonomy code, or
  `cancelled`) and MUST NOT infer a terminal outcome from silence. `(§5.5 rule 4; §4.1)`
- **FR-008**: Cancel MUST be exposed by closing the in-flight stream; there MUST NOT be a
  separate cancel endpoint or cross-invocation cancel state. `(§5.5 Cancel row and rule 5;
  §4.1)`
- **FR-009**: After a request that carried a request reference, the SDK MUST retain the
  last request reference for support. `(§4.1; delivery plan §3.6 Done when; §3.11.5 E2)`
- **FR-010**: Clients MUST branch on §5.4 taxonomy codes (never on raw provider errors);
  an unknown code MUST be treated as `internal_error`. `(§5.4; delivery plan §3.11.5 E2)`
- **FR-011**: For every §5.4 taxonomy code that can terminate a request other than the
  `unauthenticated` re-mint path, the SDK MUST prove it does not auto-retry after that
  terminal outcome. `(§4.1; §5.4; delivery plan §3.11.5 E2)`
- **FR-012**: The SDK MUST contain no prompt text, provider name, or model identifier, and
  MUST pass the E1 client architecture guard. `(§4.1; R-12; delivery plan §6.4)`

### Key Entities

Not applicable — this slice defines no entities. (AAT, request reference, and idempotency
key are transport values consumed from earlier contracts; E2 does not define D1 entities
or new clinic tables.)

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: A transport-only Flutter SDK keeps AI additive for small-to-mid
  multi-branch clinics: the desktop client submits intent and context and displays
  terminal outcomes without operating providers, prompts, or quota machinery (§4.1). No
  clinic-operated AI infrastructure is introduced.

- **Layer Placement**: This slice touches **`frontend/`** (Flutter) only — the AI Client
  SDK named in §4.1. It does not add Worker stages in `ai-platform/` or Supabase RPCs in
  `backend/`. It calls contracts already frozen by Needs (AAT mint path from prior band B,
  SSE/wire from A6, capability identity from C1) without owning those servers. It is not
  itself the gateway; the §14 acknowledgement that the gateway is a non-primary, additive
  component (no domain logic, no business data, no write path into Supabase) remains the
  boundary the SDK must respect by never embedding AI business rules in Flutter (§4.1;
  §14).

- **Data Integrity & Security**: The SDK carries the AAT and idempotency/trace/version-pin
  headers required by §5.5; it does not mint scopes, does not bypass RLS (context assembly
  is E3), and does not write clinical records (acceptance is F2 / E4). Request references
  are retained only for support display (§4.1; A13 via Consumes). Soft-delete and clinic
  audit conventions are unchanged — this slice writes no clinic tables.

- **Failure Handling**: Transport failures may be retried with a stable idempotency key
  (§4.1). `unauthenticated` triggers exactly one silent re-mint (§5.4). All other terminal
  taxonomy outcomes are surfaced without auto-retry (§4.1; §5.4). Cancel is stream close
  (§5.5). Platform unreachability and non-enrollment UX are E4, not E2; the SDK surfaces
  transport/terminal failures to the caller so those surfaces can degrade without inventing
  a second transport stack.

## Out of Scope

Neighbouring slices and temptations this slice must not absorb:

- **E1** — Already done: architecture guard implementation and fixtures (Consumes only).
- **E3** — Context Resolver registry, first context RPC, and client contract test against
  live manifests.
- **E4** — First AI feature surface, provisional-draft UX, degraded mode, non-enrollment
  hiding, platform-unreachability as a normal state.
- **A6 / D4** — Server-side protocol adapter and stream broker behaviour; E2 only consumes
  the wire/SSE contract.
- **C1 / C3** — Implementing discovery UX, journal writer, or the get-request endpoint
  client beyond what FR-006 needs to submit and consume a stream.
- **B1–B4** — Implementing the issuer RPC, keystore, guard stages, or Quota DO; E2 only
  calls the mint/submit path as a client.
- **H1 / H3 / J2** — Conversational transcript store, `context_requested` handling, and
  `context_required` self-healing resubmit.
- **Band G** — Usage summary endpoint and in-app quota display.

Prohibitions from delivery plan §6.4 (inherited; must never be done here):

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content
  (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Automated Flutter unit/integration tests prove AAT acquire-and-cache, one
  re-mint on `unauthenticated` then success, and no re-mint loop (T1–T3) — matching
  delivery plan §3.6 Done when.
- **SC-002**: The idempotency key is identical across transport retries of the same action
  (T4, T26).
- **SC-003**: A streamed request is consumed to exactly one terminal event and that state
  is surfaced; cancel closes the stream (T5–T6).
- **SC-004**: One automated case per §5.4 terminal taxonomy code proves the SDK does not
  auto-retry after that outcome (T7–T23), and an unknown code is treated as
  `internal_error` (T25).
- **SC-005**: The last request reference from a completed or failed request remains
  available from the SDK for support (T24; §4.1).
- **SC-006**: The SDK sources pass the E1 architecture guard and do not interpret or
  assemble model output from chunks (T27–T28).

## Assumptions

- E1, A6, and C1 are complete and their frozen contracts are available to consume; E1's
  guard is already a permanent CI gate on `frontend/` (DP-6).
- Band B's AAT issuer path exists as a callable clinic-side mint for the SDK to acquire
  tokens; E2 does not re-implement issuance and does not change B1's contract.
- Integration tests may drive the SDK against test doubles for mint, HTTPS submit, and SSE
  streams that honour the A6 framing and §5.4 codes; live Worker inference is not required
  to prove this slice (DP-3).
- E2 targets `single_shot` capability traffic only; conversational surfaces are H-band.
- Primary operators of the client remain clinic staff on Windows desktop; AI remains
  optional and additive relative to clinical workflows.
- Numeric cache TTL, transport-retry ceilings, and a retention window larger than "the last
  request reference" named in §4.1 are not invented here; behaviour follows the cited
  sections and the `unauthenticated` re-mint path for expiry.
