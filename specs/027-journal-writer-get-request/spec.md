# Feature Specification: Journal writer, post-response detail, and get-request endpoint

**Feature Branch**: `027-c3-journal-writer-get-request`

**Created**: 2026-08-01

**Status**: Draft

**Input**: Slice `C3` — "Journal writer, post-response detail, and get-request endpoint" (delivery plan §3.4, band C).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.4, row C3):

> §4.3.11, §6.1 stages 9, 15, 16, §6.3, §7.4, §7.4.1, §7.6, §5.5

### Freezes

Contracts this slice establishes for the first time:

- The **R2 payload envelope contract**: one request produces exactly one R2 object keyed `request/{id}/envelope`, a single document with the four sections `context`, `prompt`, `attempts[]`, and `result` (§7.4). Later slices (F3 support lookup) consume this layout; nothing may split it into multiple objects (§7.4.1).
- The **journal write-path contract**: the `ai_request` row is created at stage 9 before any work begins, every §6.3 state transition is journaled with a timestamp, and the row is updated with the terminal state at stage 15; `ai_attempt` rows, the single `usage_event` row, and the one R2 envelope are written in the post-response continuation at stage 16, and a failure there never fails the request (§4.3.11, §6.1 stages 9/15/16, §6.3, §7.5). Later slices (D3, D4, D6) feed this writer with per-attempt and validated-result data and rely on these timings.
- The **get-request endpoint response contract**: a request reference resolves, through one indexed D1 lookup on `request_reference`, to the terminal state and — for a completed request only — the validated result fetched from the R2 envelope's `result` section; a failed request returns state plus the terminal error code and no content; a cancelled request returns state only; an unknown reference returns not found (§5.5, §7.6, §7.4).

### Consumes

Contracts frozen by the slices in `Needs` (A5, C1). Changing any of these is out of scope by definition:

- **From A5 (D1 schema)**: the `ai_request`, `ai_attempt`, `usage_event`, and `platform_counter` entities and their field shapes — request id, **request reference**, installation, actor, branch, capability id+version, prompt artifact hash, idempotency key, state, timestamps, terminal error code, trace id, payload pointers, and the nullable `conversation_id` / `turn_ordinal` columns — and the unique index on `request_reference` (§7.3). C3 writes to these entities and adds none.
- **From A5 (config cache)**: the warm-isolate config cache that serves installation, entitlement, and capability data with no I/O (§7.3, §4.3.2).
- **From A2**: the error taxonomy as a closed set and the diagnostic envelope (request reference, trace id) carried on every request (§5.4, §13.1, §13.2).
- **From A3**: the canonical request, stream chunk, result, and error types (§5.3).
- **From A4 / C1**: the immutable, resolved capability manifest — its `interaction_mode`, its pinned prompt artifact hash, its Economics field group (quota weight), and its retention class (§5.1, §5.7).
- **From A6**: the request reference carried in the `accepted` event and the SSE terminal-event invariant (§4.3.1, §5.5).
- **From B3**: the immutable request principal (installation id, actor, branch, org, trace id) established upstream in the guard (§4.3.2, §5.6).
- **From B4**: the Quota Durable Object's credit interface that settles actual usage against the installation's counters (§4.3.3, §6.1 stage 15). C3 does not reimplement the DO; the credit call is B4's contract (see Out of Scope).
- **From C2**: the filtered, declaration-conformant context payload (declared keys only) that becomes the envelope's `context` section (§4.3.5, §5.2).

### Open decisions relied on

None. C3 writes the journal, the envelope, and the get-request response from data and contracts the architecture fully specifies; no §15 recommended default is assumed by this slice. (Open Decision 4's diagnostic retention horizon governs when envelopes expire, but expiry is performed by F3's retention purges, not by C3's write path.)

## Clarifications

### Session 2026-08-01

- Q: In what serialization format should the R2 payload envelope (the single document with the four sections `context`, `prompt`, `attempts[]`, `result`, keyed `request/{id}/envelope`) be written? → A: JSON `[implementation choice — no §citation]`
- Q: How should the journal writer, the post-response continuation, and the get-request endpoint be organised as modules within `ai-platform/src/`? → A: a single `journal/` module, with the envelope builder inlined as an internal helper `[implementation choice — no §citation]`
- Q: How should stage 16 (the post-response continuation that writes the `ai_attempt` rows, the `usage_event` row, and the one R2 envelope) be scheduled to run after the terminal event, given it must "never fail the request" and must run entirely after the response? → A: `ctx.waitUntil` — schedule the stage-16 writes as a continuation on the Workers execution context; a failure is swallowed/logged, never returned to the client `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Journal writer, post-response detail, and get-request endpoint (Priority: P1)

As the AI Gateway Worker, once the guard has passed and the request has been admitted (B4), I create the durable `ai_request` row synchronously at stage 9 before any inference work begins, journal every §6.3 state transition with a timestamp, and update the row with its terminal state at stage 15; after the terminal event has been emitted to the client, I write the per-attempt `ai_attempt` rows, exactly one `usage_event` ledger row, and exactly one R2 payload envelope (keyed `request/{id}/envelope`, containing the four sections `context`, `prompt`, `attempts[]`, `result`) in the post-response continuation at stage 16, and a failure in that continuation never fails the already-completed request. A request rejected by the guard produces no journal row. Through the get-request endpoint, a request reference resolves to its terminal state — and, if completed, the validated result — via a single indexed D1 lookup.

**Why this priority**: C3 sits where it does because its `Needs` (A5, C1) are the point at which the D1 schema and the resolved manifest exist, and because the journal is the audit backbone that band F's support lookup and dashboards query (delivery plan §3.4). Stage 9 is where a request stops being a candidate and starts being work — the row must exist before the provider is invoked so no request a user witnessed can vanish from the record (§4.3.11, §6.2). Downstream slices D3, D4, D6, and F3 consume the frozen journal and envelope contracts.

**Independent Test**: Provable by an integration (ordering + spy) suite with no real provider: drive the journal writer and post-response continuation with fixture inputs (filtered context, composed prompt, per-attempt raw responses, validated result), and assert, per case, the row's existence and timing relative to a provider-call spy, the terminal state written, every §6.3 transition timestamped, the absence of a row on guard rejection, exactly one R2 `PutObject` with all four sections, one `ai_attempt` per attempt, exactly one `usage_event`, that a stage-16 failure does not fail the request, and the get-request response per terminal state — all with exactly one indexed D1 lookup (§3.11.3, row C3; §3.10).

**Acceptance Scenarios**:

1. **Given** a request that has passed the guard and been admitted, **When** stage 9 runs, **Then** the `ai_request` row exists before the provider is invoked (a provider-call spy observes the row is already present). *(request row exists before provider — ordering)*
2. **Given** a request that reaches a terminal state, **When** stage 15 runs, **Then** the row is updated with that terminal state — one case each for `completed`, `failed`, and `cancelled`. *(terminal-state cases)*
3. **Given** a request rejected by the guard, **When** the guard rejects it, **Then** no `ai_request` row is created (spy on D1 inserts: zero for the request) — the rejection is counted in `platform_counter`, not journaled as a request. *(rejected — no row)*
4. **Given** any §6.3 state transition, **When** the transition occurs, **Then** it is journaled with a timestamp, so the state timeline is reconstructable from the row. *(every §6.3 transition timestamped)*
5. **Given** a request whose generation fails, **When** the failure is handled, **Then** the `ai_request` row survives (it was created at stage 9 and carries the failure's terminal state). *(row survives a failed generation)*
6. **Given** a completed request, **When** stage 16 runs, **Then** exactly one R2 `PutObject` is performed, keyed `request/{id}/envelope`, and the envelope contains all four sections `context`, `prompt`, `attempts[]`, and `result`. *(exactly one R2 object, four sections)*
7. **Given** a request with N provider attempts, **When** stage 16 runs, **Then** exactly N `ai_attempt` rows are written — one per attempt. *(one ai_attempt per attempt)*
8. **Given** a request, **When** stage 16 runs, **Then** exactly one `usage_event` row is written. *(exactly one usage_event)*
9. **Given** a request whose stage-16 continuation fails (R2 or D1 error), **When** that failure occurs, **Then** the request is not failed by it — the terminal event already emitted stands, and no error surfaces to the client. *(stage-16 failure does not fail the request)*
10. **Given** the stage-16 continuation, **When** it runs, **Then** all of it runs after the terminal event (the terminal event is emitted before any stage-16 write). *(post-response runs after terminal event — ordering)*
11. **Given** a completed request, **When** the get-request endpoint is called with its reference, **Then** it returns the terminal state plus the validated result, via exactly one indexed D1 lookup (plus the one R2 `GetObject` for the `result` section). *(get-request completed)*
12. **Given** a failed request, **When** the get-request endpoint is called with its reference, **Then** it returns the state plus the terminal error code and no content. *(get-request failed)*
13. **Given** a cancelled request, **When** the get-request endpoint is called with its reference, **Then** it returns the state only. *(get-request cancelled)*
14. **Given** an unknown reference, **When** the get-request endpoint is called with it, **Then** it returns not found, via the indexed lookup. *(get-request unknown)*

### Test plan

Layer for every named case is **Integration (ordering + spy)** per delivery plan §3.11.3 (row C3), exercising the journal writer, the post-response continuation, and the get-request endpoint against a fake provider and fixture inputs; the "spy" assertion style (asserting on the number or absence of calls) follows the coverage rule in §3.10 and corresponds to the **Pipeline tests** layer of the architecture's testing strategy (§13.5: "Stage ordering, guard rejection paths").

| # | Named test | Asserts |
| --- | --- | --- |
| T1 | `request_row_exists_before_provider_invoked` | a provider-call spy observes the `ai_request` row is present before the provider is called (§4.3.11, §6.1 stage 9 precedes stage 11) |
| T2 | `terminal_state_completed` | a completed request's row is updated to `completed` at stage 15 (§6.1 stage 15, §6.3) |
| T3 | `terminal_state_failed` | a failed request's row is updated to `failed` at stage 15 (§6.1 stage 15, §6.3) |
| T4 | `terminal_state_cancelled` | a cancelled request's row is updated to `cancelled` at stage 15 (§6.1 stage 15, §6.3) |
| T5 | `guard_rejected_produces_no_row` | a guard-rejected request produces zero `ai_request` inserts (spy); the rejection is counted in `platform_counter` (§6.2, §7.5, §7.3) |
| T6 (one per transition) | `every_state_transition_timestamped` | each §6.3 transition (Accepted, Composing, Invoking, Streaming, Validating, Repairing, AwaitingContext, Completed, Failed, Cancelled) is journaled with a timestamp; the state timeline is reconstructable (§4.3.11, §6.3, §8.9) |
| T7 | `row_survives_failed_generation` | a failed generation leaves the row present, carrying the failure's terminal state (§4.3.11) |
| T8 | `exactly_one_r2_putobject_per_request` | exactly one R2 `PutObject` is performed per request, keyed `request/{id}/envelope` (spy on R2) (§7.4, §7.4.1) |
| T9 | `envelope_contains_all_four_sections` | the envelope document contains the `context`, `prompt`, `attempts[]`, and `result` sections (§7.4) |
| T10 (one per N) | `one_ai_attempt_row_per_attempt` | N provider attempts produce exactly N `ai_attempt` rows (§7.3, §6.1 stage 16) |
| T11 | `exactly_one_usage_event` | exactly one `usage_event` row is written per request (§7.3, §6.1 stage 16) |
| T12 | `stage16_failure_does_not_fail_request` | an injected R2/D1 failure in stage 16 does not fail the request; the terminal event already emitted stands (§6.1 stage 16, §3.11.3) |
| T13 | `stage16_runs_after_terminal_event` | the terminal event is emitted before any stage-16 write (ordering spy) (§6.1 stage 14 precedes stage 16) |
| T14 | `get_request_completed_returns_state_and_result` | a completed request's reference returns state plus the validated result, via one indexed D1 lookup (§5.5, §7.6, §7.4) |
| T15 | `get_request_failed_returns_state_and_error_no_content` | a failed request's reference returns state plus the terminal error code and no content (§5.5, §7.6) |
| T16 | `get_request_cancelled_returns_state_only` | a cancelled request's reference returns state only (§5.5, §7.6) |
| T17 | `get_request_unknown_reference_returns_not_found` | an unknown reference returns not found, via the indexed lookup (§5.5, §7.6) |
| T18 | `get_request_uses_exactly_one_indexed_query` | the get-request path performs exactly one indexed D1 lookup on `request_reference` (spy on D1 queries) (§7.6) |

Coverage of every error code the slice can emit (§3.10 item 2): C3's own stages (9, 15, 16) emit only `internal_error` on a stage-9 D1 insert failure (§6.1 stage 9); stage 16 emits no error to the client by construction ("never fails the request"). Terminal error codes written to the row (`completed`/`failed`/`cancelled` and the taxonomy codes carried by `failed`) are produced by later stages (D3/D4/D6) and are recorded, not generated, by C3. The get-request endpoint returns not found for an unknown reference, which is a response state, not a taxonomy error code.

### Edge Cases

- **Error codes this slice can emit** (closed set, §5.4): stage 9 emits `internal_error` if the synchronous D1 insert fails — the row must exist before work begins, so a failure to create it must fail the request before the provider is called (§6.1 stage 9). Stages 15 and 16 emit no error to the client: stage 15 updates an already-durable row, and stage 16 "never fails the request" by construction (§6.1 stage 16).
- **Guard rejection produces no row**: a request rejected at any guard stage (1–8) is counted in `platform_counter` and is never journaled as a request — putting a D1 write in the cheap-rejection path is the named anti-pattern (§6.2, §7.5). The `rejected` terminal state is therefore asserted by the *absence* of a row, not by a row in that state.
- **Stage 9 precedes prompt composition (stage 10)**: the `ai_request` row's prompt artifact hash is the one pinned by the resolved capability manifest (§5.7, A4), not one computed from a composed prompt, so it is known at stage 9 before stage 10 runs. C3 does not compose the prompt.
- **One R2 object, not four**: writing one envelope rather than four is what keeps R2 Class A operations proportional to requests (§7.4.1); a support lookup interested only in the prompt still transfers the whole envelope, which the architecture accepts because envelopes are kilobytes and R2 egress is free (§7.4.1).
- **Post-response failure isolation**: an R2 `PutObject` failure or a D1 insert failure at stage 16 must not surface to the client or change the terminal state already emitted; the request's *existence* is durable from stage 9, and stage 16 carries only detail that improves diagnosis (§6.1, §4.3.11).
- **Get-request result source**: the validated result lives in the R2 envelope's `result` section (§7.4); D1 holds payload pointers, not result text (§7.3, §7.5). The get-request endpoint therefore performs one indexed D1 lookup (state + pointer) and, for a completed request only, one R2 `GetObject` for the `result` section; failed and cancelled requests perform no R2 read (no content / state only).
- **Exactly one indexed query**: the `request_reference` index (A5) is what makes the get-request and support lookup a single indexed lookup rather than a scan (§7.6); a get-request must never fall back to a second D1 lookup or a table scan.
- **`AwaitingContext` and `Repairing` transitions**: these §6.3 states are reached only by later slices (H1 conversational, D6 repair), but the journal writer is generic over §6.3 and must timestamp them when they occur; C3's tests drive them synthetically to prove the mechanism without implementing the behaviours that reach them.
- **Conversational columns**: for a `single_shot` request the nullable `conversation_id` / `turn_ordinal` columns (A5) are written null; C3 writes them from the request when present and does not introduce a conversation entity (§7.3, §6.7 — the conversational *behaviour* is band H).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The journal writer MUST create the `ai_request` row synchronously at stage 9, before any inference work begins, so that a request a user witnessed always has a record; a failure of this synchronous insert MUST fail the request with `internal_error` before the provider is called. (§4.3.11, §6.1 stage 9, §6.2)
- **FR-002**: The `ai_request` row created at stage 9 MUST carry the request id, request reference, installation, actor, branch, capability id+version, the prompt artifact hash pinned by the resolved manifest, idempotency key, trace id, the initial `Accepted` state, and — when present — `conversation_id` / `turn_ordinal`; payload pointers are null until stage 16. (§4.3.11, §7.3, §5.7)
- **FR-003**: Every state transition in §6.3 MUST be journaled with a timestamp, so the state timeline is reconstructable from the row; `Completed`, `Failed`, `Cancelled`, `Rejected`, and `AwaitingContext` are terminal and immutable. (§4.3.11, §6.3, §8.9)
- **FR-004**: At stage 15 the journal writer MUST update the `ai_request` row with the terminal state and the terminal error code (when failed); this update is to an already-durable row and MUST NOT emit an error to the client. (§6.1 stage 15, §4.3.11)
- **FR-005**: A request rejected by any guard stage (1–8) MUST produce no `ai_request` row; the rejection MUST be counted in `platform_counter` instead, never journaled as a request. (§6.2, §7.5, §7.3)
- **FR-006**: The `ai_request` row MUST survive a failed generation — it was created at stage 9 and is updated to the failure's terminal state, never deleted on generation failure. (§4.3.11)
- **FR-007**: In the post-response continuation at stage 16, the journal writer MUST write exactly one R2 object per request, keyed `request/{id}/envelope`, containing the four sections `context` (the filtered context from C2), `prompt` (the composed provider-bound prompt), `attempts[]` (raw provider response or error body per attempt), and `result` (the validated terminal payload). (§7.4, §7.4.1, §6.1 stage 16, §4.3.11)
- **FR-008**: In stage 16 the journal writer MUST write exactly one `ai_attempt` row per provider attempt, and exactly one `usage_event` row per request — never one row per stream chunk and never more than one `usage_event`. (§7.3, §6.1 stage 16, §7.5)
- **FR-009**: Stage 16 MUST run entirely after the terminal event has been emitted to the client, and a failure in stage 16 (R2 `PutObject` or D1 insert) MUST NOT fail the request or change the terminal state already emitted. (§6.1 stages 14–16, §4.3.11, §3.11.3)
- **FR-010**: The get-request endpoint MUST resolve a request reference to its terminal state through a single indexed D1 lookup on `request_reference`; for a completed request it MUST additionally return the validated result fetched from the R2 envelope's `result` section; for a failed request it MUST return the state plus the terminal error code and no content; for a cancelled request it MUST return the state only; for an unknown reference it MUST return not found. (§5.5, §7.6, §7.4, §7.3)
- **FR-011**: The get-request endpoint MUST use exactly one indexed D1 lookup on `request_reference` and MUST NOT perform a second D1 lookup or a table scan; failed and cancelled requests MUST perform no R2 read. (§7.6, §7.3)
- **FR-012**: The journal writer MUST NOT write a D1 row per stream chunk, MUST NOT journal a guard rejection as a request, MUST NOT create a second R2 object per request, and MUST NOT introduce any per-request server-side state. (§7.5, §4.4, §9.7)

### Key Entities *(include if feature involves data)*

C3 defines no new D1 entities (the `ai_request`, `ai_attempt`, `usage_event`, and `platform_counter` entities and the `request_reference` index are frozen by A5, §7.3). C3 freezes two contract types:

- **R2 payload envelope** (§7.4): one object per request keyed `request/{id}/envelope`, a single document with sections `context`, `prompt`, `attempts[]`, `result`. Established here; consumed by F3 support lookup.
- **Get-request response** (§5.5, §7.6): `{ state, terminal_error_code?, result? }` — state always present; `terminal_error_code` present only for `failed`; `result` (the validated terminal payload) present only for `completed`; `cancelled` returns state only; unknown reference returns not found. Established here for the client-facing read path (distinct from F3's operator-only support lookup, which returns the full trace plus the whole envelope).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: The journal is what makes every request explainable from its reference after the fact — the audit requirement the architecture names as the platform's hardest (§4.3.11, §8.9). At clinic volumes (tens of requests per day per clinic, §13.6.1), one D1 insert at stage 9 and one R2 object at stage 16 keep the metered footprint proportional to requests, not to a multiple of them (§7.4.1, §7.5). No enterprise-scale assumption is introduced; the design stays within the 2 MB row / 10 GB database ceilings precisely because payloads live in R2 and pointers in D1 (§7.3, §7.5).
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker) and its D1/R2 bindings. It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. C3's only stores are the platform's own D1 and R2.
- **Data Integrity & Security**: The journal row is the auditable life of a request — submission, principal, capability and prompt artifact versions, state timeline, terminal error code, and payload pointers (§4.3.11, §7.3). The row is created before work begins so it cannot be lost to a later failure, and a guard rejection produces no row (rejections are counted, not journaled) so the cheap-rejection path stays cheap (§6.2, §7.5). The R2 envelope carries prompt, context, raw responses, and result; its retention class is a per-capability manifest field (§5.1, §7.7), expired by F3 — C3 writes it but does not purge it. The get-request endpoint exposes only the terminal state and the validated result to the caller; operator-only full-trace support lookup is F3, not C3 (§5.5).
- **Failure Handling**: A stage-9 insert failure fails the request before any paid work (`internal_error`); a stage-16 failure never fails the already-completed request, because the request's existence is durable from stage 9 and stage 16 carries only diagnostic detail (§6.1, §4.3.11). The get-request endpoint degrades to not found for an unknown reference and to state-only for a cancelled request; it does not synthesize a result. Quota DO unavailability and provider failures are handled by B4 and D3, not C3.

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **C1 (capability resolver, discovery)**: C3 reads the resolved, immutable manifest (for the pinned prompt artifact hash, quota weight, retention class, and `interaction_mode`); it does not resolve capability ids, honour version pins, or serve discovery. (§4.3.4)
- **C2 (context validator)**: C3 stores the filtered context payload as the envelope's `context` section; it does not validate context, enforce the Context Contract, or run the cost pre-flight. (§4.3.5)
- **D1 (prompt composer)**: C3 stores the composed prompt as the envelope's `prompt` section; it does not compose a prompt, render context as delimited typed data, or derive the output-format instruction. (§4.3.6)
- **D3 (invocation) / D4 (stream broker)**: C3 journals per-attempt data from `ai_attempt` rows and raw provider responses in the envelope; it does not invoke providers, retry, fall back, or relay stream chunks. The terminal states those slices produce are recorded by C3, not generated by it. (§4.3.7, §4.3.10)
- **D6 (response validator)**: C3 stores the validated terminal payload as the envelope's `result` section; it does not validate, repair, or enforce structured-output modes. (§4.3.9)
- **B4 (Quota DO credit)**: stage 15's "credit actual usage to the Quota DO" is B4's DO method (§4.3.3, §6.1 stage 15); C3 updates the journal row with terminal state only and does not invoke or reimplement the Quota Durable Object. (§4.4, §9.17)
- **F3 (support lookup, retention purges, dashboards)**: C3 freezes the envelope layout and the journal row that F3 reads, but F3 owns the operator-only full-trace support lookup, the retention purges that expire envelopes by class, the `usage_rollup` scheduled job, and the dashboard queries. (§4.5, §7.6, §7.7, §8.9)
- **H3 (conversational journaling)**: C3 writes the nullable `conversation_id` / `turn_ordinal` columns (reserved by A5) when present; the conversational *behaviour* — a conversation entity, transcript handling, per-leg admission — is band H. C3 introduces no conversation entity. (§7.3, §6.7)

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20). C3 adds no retry, no caching, no batching, no abstraction beyond the named stages and the one-envelope-per-request rule.
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — not applicable to this Worker slice, but nothing C3 stores pulls any such string into the client; the envelope is platform-internal.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — C3 writes exactly one R2 object per request and performs no DO I/O.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5) — C3 journals at stage 9 only after the guard passes, and writes only aggregates at stage 16.
- No per-request server-side state of any kind (§4.4, §9.7) — the journal row is the durable record, not in-flight state.
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5) — the get-request endpoint returns the validated terminal payload from the envelope, never an assembly of chunks.

C3 invents no field names, table names, error codes, thresholds, or retention horizons: the D1 entities and index are frozen by A5 (§7.3), the envelope key and section names by §7.4, the terminal states by §6.3, and the retention class by §5.1. The get-request response shape is the only contract C3 establishes, and it restates §5.5 and §7.6.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An automated integration test proves the `ai_request` row exists before the provider is invoked (provider-call spy) and is updated with each of `completed`, `failed`, and `cancelled` at stage 15 — the full request-row clause of the `Done when` cell, each branch a named test.
- **SC-002**: An automated test proves a guard-rejected request produces zero `ai_request` inserts (spy) and is counted in `platform_counter` — the "no row on rejection" invariant.
- **SC-003**: An automated test proves every §6.3 state transition is journaled with a timestamp, so the state timeline is reconstructable from the row (§8.9).
- **SC-004**: An automated test proves exactly one R2 `PutObject` is performed per request, keyed `request/{id}/envelope`, and the envelope contains all four sections `context`, `prompt`, `attempts[]`, `result`; a second `PutObject` is provably absent (spy).
- **SC-005**: An automated test proves N provider attempts produce exactly N `ai_attempt` rows and exactly one `usage_event` row — never one row per chunk, never more than one `usage_event`.
- **SC-006**: An automated test proves a stage-16 failure (injected R2/D1 error) does not fail the request and does not change the terminal state already emitted, and that stage 16 runs entirely after the terminal event.
- **SC-007**: An automated test proves the get-request endpoint returns, via exactly one indexed D1 lookup on `request_reference`: completed → state plus validated result; failed → state plus terminal error code and no content; cancelled → state only; unknown reference → not found — and that failed/cancelled perform no R2 read.

## Assumptions

- The D1 schema (entities, fields, and the unique `request_reference` index) is frozen by A5 (§7.3) and applied by A5's forward-only migrations before C3 runs; C3 writes to existing entities and adds none.
- The resolved capability manifest — including its pinned prompt artifact hash, Economics (quota weight), and retention class — is available from C1 and the config cache (§5.1, §5.7, §4.3.4); C3 reads it and does not resolve capability ids.
- The request principal (installation id, actor, branch, org, trace id) and the request reference are established upstream by B3 and A6 (§4.3.2, §5.5, §4.3.1); C3 reads them and does not authenticate or mint.
- The filtered context payload (C2), the composed prompt (D1), per-attempt raw responses (D3), and the validated terminal payload (D6) are handed to C3's stage-16 writer by the pipeline; C3 stores them and does not produce them. Until those slices land, C3's tests drive the writer with fixtures.
- The Quota Durable Object credit call (stage 15's second action) is B4's contract (§4.3.3, §6.1 stage 15); C3 updates the journal row only and does not perform DO I/O.
- Retention purges that expire envelopes by per-capability class are F3's (§7.7); C3 writes the envelope and does not delete it. Open Decision 4's horizon is consumed by F3, not assumed by C3.
