# Feature Specification: Stream broker, prose streaming, and cancellation

**Feature Branch**: `ai/031-d4-stream-broker`

**Created**: 2026-08-01

**Status**: Draft

**Input**: Slice `D4` — "Stream broker, prose streaming, and cancellation" (delivery plan §3.5, band D).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.5, row D4):

> §4.3.10, §6.4, §5.5, §6.5, §9.7

### Freezes

Contracts this slice establishes for the first time:

- The **stream broker**: relays normalized chunks to the client, enforces provisional-versus-committed semantics for streamed content, emits heartbeats so intermediaries do not time out an idle stream, and guarantees every stream ends with exactly one terminal event — success with the validated payload, a typed error, or `cancelled` (§4.3.10; §5.5 rules 3–4). Later slices (D6 structured modes, H1 `context_requested`) extend what the broker may carry; they must not rewrite the relay, heartbeat, or one-terminal-event duties.
- The **`prose` streaming path with commit-time validation**: during the stream, `text_delta` events are relayed and cheap guards are applied incrementally — length ceiling, stop-sequence, and system-prompt-leak detection; a violation aborts the stream and fails terminally. At completion, the full guard set runs on the assembled text, and the terminal `completed` event carries the validated payload. Clients display live and must not treat chunks as authoritative; the validated terminal payload is self-contained (§6.4 `prose` row; invariants 1–2 as they apply to broker emission).
- The **broker-owned, connection-scoped cancellation path**: cancellation requires no stateful component. The Worker observes client disconnect (deliberate Cancel or network drop — indistinguishable), aborts the in-flight provider fetch through its abort signal, terminates the request as `cancelled`, credits partial usage to the Quota Durable Object, and leaves a complete journalable record — all without creating per-request server-side state (§4.3.10; §5.5 Cancel row and rules 5–6; §6.5; §9.7).
- The **explicit non-support of out-of-band cancellation and stream resume**: cancel from a different window, after reconnect, or via a separate endpoint is not supported; a Session Durable Object is not introduced (§4.3.10; §6.5; §9.7).

### Consumes

Contracts frozen by the slices in `Needs` (A6, D3). Changing any of these is out of scope by definition:

- **From A6 (protocol adapter and SSE framing)**: the SSE event framing; the `accepted` opening event carrying the request reference; the heartbeat event shape; the terminal event kinds `completed`, `failed`, and `cancelled`; the one-terminal-event invariant under every path including abort; and connection-scoped cancellation at the framing level — closing the stream ends the request as `cancelled`, with no separate cancel endpoint and no cross-invocation state (§4.3.1, §5.5 Freezes in A6). D4 owns broker behaviour that *uses* this framing (chunk relay, heartbeat emission during provider silence, provider-fetch abort, partial-usage credit); it does not redefine wire framing or the one-terminal-event rule.
- **From D3 (invocation with bounded retry and fallback)**: the platform-internal attempt loop that invokes the provider port, produces normalized stream chunks, journals each attempt separately, emits `regenerating` and discards earlier partial text on fallback after partial streaming, and never splices two providers' text (§4.3.7, §8.6 Freezes in D3). D4 relays what invocation emits; it does not own retry, fallback, or the regenerating decision.

### Open decisions relied on

None. D4's stream broker, prose guards, heartbeats, and connection-scoped cancellation are fully specified by §4.3.10, §6.4, §5.5, §6.5, and §9.7; no §15 recommended default is assumed. (The connection-scoped recommendation in §9.7 is part of this slice's `Implements`, not a §15 open decision.)

## Clarifications

### Session 2026-08-01

- Q: Where should the stream broker live under `ai-platform/src/`? → A: New `src/stream/` (broker + prose guards + cancel wiring + tests) `[implementation choice — no §citation]`
- Q: How should T2 assert a heartbeat during provider silence without freezing a heartbeat interval? → A: Inject a controllable heartbeat ticker; force a silent gap and assert ≥1 heartbeat `[implementation choice — no §citation]`
- Q: How should cancel tests (T8, T13, T14) drive disconnect and prove the provider fetch was aborted via its abort signal? → A: Broker takes an `AbortSignal` for the in-flight fetch; test closes the client stream and asserts `signal.aborted` `[implementation choice — no §citation]`
- Q: How should T10/T11 assert partial-usage credit and journal completeness without owning B4’s Quota DO or C3’s D1 writer? → A: Inject in-memory credit + journal-terminal sinks; tests assert credit(partial) and a complete terminal `cancelled` record `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stream broker, prose streaming, and cancellation (Priority: P1)

As the AI Gateway Worker, after invocation (D3) has begun producing normalized chunks against the fake provider, I relay those chunks to the client over the A6 SSE framing: for `prose`, I emit `text_delta` events in order, apply cheap incremental guards (length ceiling, stop-sequence, system-prompt-leak), emit heartbeats during provider silence, and at completion run the full guard set on the assembled text so the terminal `completed` event carries the validated payload. When the client disconnects, I abort the in-flight provider fetch through its abort signal, terminate as `cancelled`, credit partial usage to the Quota Durable Object, and create no per-request server-side state — whether cancel happens before the first token or mid-stream.

**Why this priority**: D4 sits where it does because its `Needs` (A6, D3) are the point at which SSE framing, the one-terminal-event invariant, and an invocation loop that can stream (and regenerate on fallback) already exist — without those, the broker would invent wire protocol or retry behaviour. Every later path that shows live draft text (D6 structured modes, E4 surface, CP3) depends on ordered relay, heartbeats, prose guards, and honest cancel-with-credit (delivery plan §3.5).

**Independent Test**: Provable by an integration (spy) suite: chunks relayed in order; heartbeat during provider silence; one case per incremental guard aborting and failing terminally; full guard set run on assembled text; terminal event carries validated payload; disconnect aborts the provider fetch via abort signal; state becomes `cancelled`; partial usage credited; journal row complete; no per-request state object; cancel-before-first-token and cancel-mid-stream are separate cases (delivery plan §3.11.4 row D4; §3.10).

**Acceptance Scenarios**:

1. **Given** a `prose` request whose fake provider emits a sequence of normalized text chunks, **When** the stream broker relays them, **Then** chunks arrive at the client sink in order as `text_delta` events. *(chunks relayed in order)*
2. **Given** a `prose` request whose provider is silent before the first token (or between tokens), **When** the stream remains open without content, **Then** heartbeat events are emitted so intermediaries do not close the idle stream. *(heartbeat during provider silence)*
3. **Given** a `prose` stream whose assembled or incremental output exceeds the length ceiling, **When** the incremental length-ceiling guard trips, **Then** the broker aborts the stream and the request fails terminally (exactly one `failed` terminal event). *(incremental guard — length ceiling)*
4. **Given** a `prose` stream that produces a stop-sequence violation under the incremental guard, **When** the stop-sequence guard trips, **Then** the broker aborts the stream and the request fails terminally (exactly one `failed` terminal event). *(incremental guard — stop sequence)*
5. **Given** a `prose` stream that produces a system-prompt-leak under the incremental guard, **When** the system-prompt-leak guard trips, **Then** the broker aborts the stream and the request fails terminally (exactly one `failed` terminal event). *(incremental guard — system-prompt leak)*
6. **Given** a `prose` stream that completes without an incremental-guard abort, **When** generation finishes, **Then** the full guard set runs on the assembled text before the terminal event. *(full guard set on assembled text)*
7. **Given** a `prose` stream that passes the full guard set, **When** the broker emits the terminal event, **Then** that event is `completed` and carries the validated payload (self-contained; not assembled by the client from chunks). *(terminal event carries validated payload)*
8. **Given** an in-flight provider fetch with an abort signal, **When** the client disconnects (stream close), **Then** the broker aborts that fetch through the abort signal. *(disconnect aborts provider fetch via abort signal)*
9. **Given** a client disconnect on an in-flight request, **When** cancellation completes, **Then** the request terminal state is `cancelled`. *(state becomes cancelled)*
10. **Given** a cancelled request that had produced partial provider usage, **When** settlement runs, **Then** that partial usage is credited to the Quota Durable Object. *(partial usage is credited)*
11. **Given** a cancelled request, **When** cancellation completes, **Then** the journal row for the request is complete (the request remains explainable; the row survives). *(journal row is complete)*
12. **Given** any streaming or cancellation path in this slice, **When** the broker runs, **Then** no per-request server-side state object is created. *(no per-request state object)*
13. **Given** a client disconnect before any content token has been relayed, **When** cancellation runs, **Then** the provider fetch is aborted, the request terminates as `cancelled`, and partial usage (if any) is credited. *(cancel before the first token)*
14. **Given** a client disconnect after one or more `text_delta` events have been relayed, **When** cancellation runs, **Then** the provider fetch is aborted, the request terminates as `cancelled`, and partial usage is credited. *(cancel mid-stream)*

### Test plan

Layer: Integration (spy) (delivery plan §3.11.4, row D4; §13.5 Pipeline tests with fake provider). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `chunks_relayed_in_order` | Integration (spy) | Normalized chunks relayed in order as `text_delta` (§3.11.4 D4; §4.3.10; §6.4) |
| T2 | `heartbeat_during_provider_silence` | Integration (spy) | Heartbeat emitted during provider silence (§3.11.4 D4; §4.3.10; §5.5 rule 3) |
| T3 | `incremental_guard_length_ceiling_aborts` | Integration (spy) | Length-ceiling guard aborts stream and fails terminally (§3.11.4 D4; §6.4) |
| T4 | `incremental_guard_stop_sequence_aborts` | Integration (spy) | Stop-sequence guard aborts stream and fails terminally (§3.11.4 D4; §6.4) |
| T5 | `incremental_guard_system_prompt_leak_aborts` | Integration (spy) | System-prompt-leak guard aborts stream and fails terminally (§3.11.4 D4; §6.4) |
| T6 | `full_guard_set_runs_on_assembled_text` | Integration (spy) | Full guard set runs on assembled text at completion (§3.11.4 D4; §6.4) |
| T7 | `terminal_completed_carries_validated_payload` | Integration (spy) | Terminal `completed` carries validated payload; payload not client-assembled from chunks (§3.11.4 D4; §6.4 invariant 1) |
| T8 | `disconnect_aborts_provider_fetch_via_abort_signal` | Integration (spy) | Disconnect aborts in-flight provider fetch via abort signal (§3.11.4 D4; §4.3.10; §6.5) |
| T9 | `disconnect_terminates_as_cancelled` | Integration (spy) | Terminal state becomes `cancelled` (§3.11.4 D4; §5.5 rule 5; §6.5) |
| T10 | `partial_usage_credited_on_cancel` | Integration (spy) | Partial usage credited to Quota DO on cancel (§3.11.4 D4; §6.5; Done when) |
| T11 | `journal_row_complete_on_cancel` | Integration (spy) | Journal row complete / request explainable after cancel (§3.11.4 D4; §5.5 rule 6; §6.5) |
| T12 | `no_per_request_state_object_created` | Integration (spy) | No per-request server-side state object (§3.11.4 D4; §4.3.10; §9.7; §6.4 prohibitions) |
| T13 | `cancel_before_first_token` | Integration (spy) | Cancel before first token — abort, `cancelled`, credit (§3.11.4 D4; §6.5) |
| T14 | `cancel_mid_stream` | Integration (spy) | Cancel mid-stream — abort, `cancelled`, credit (§3.11.4 D4; §6.5) |
| T15 | `one_terminal_event_under_guard_abort_and_cancel` | Integration (spy) | Exactly one terminal event under incremental-guard abort and under disconnect (§5.5 rule 4; A6 Consumes; §3.10) |
| T16 | `network_drop_indistinguishable_from_cancel` | Integration (spy) | Network drop follows the same abort → `cancelled` → credit path as deliberate Cancel (§5.5 rule 5; §6.5; §3.10 branch) |
| T17 | `no_out_of_band_cancel_endpoint_or_session_do` | Integration (spy) | No separate cancel endpoint and no per-request Session Durable Object (§4.3.10; §6.5; §9.7; R-20 / §9.14 prohibition) |
| T18 | `provisional_chunks_not_authoritative` | Integration (spy) | Relayed `text_delta` chunks are for responsiveness; only the terminal validated payload is authoritative (§6.4 invariant 1; §3.10) |
| T19 | `no_d1_row_per_stream_chunk` | Integration (spy) | Broker does not write a D1 row per stream chunk (§7.5 / delivery plan §6.4 prohibition; §3.10) |

---

### Edge Cases

- **Error codes / terminal kinds this slice can emit.** `cancelled` when the client closes the stream or the connection drops (§5.5 rules 4–5; §6.5; Done when). Incremental prose-guard violations abort the stream and **fail terminally** as a `failed` terminal event with a taxonomy code (§6.4; §5.5 rule 4). This slice does not invent taxonomy codes; it uses the existing closed set (A2 via A6) and does not rename codes.
- **Length ceiling / stop-sequence / system-prompt-leak.** Each of the three named incremental cheap guards, when violated, aborts the stream and fails terminally (T3–T5; §6.4). Boundaries are the named guards themselves; numeric thresholds are not invented in this slice beyond what the cited sections name.
- **Full guard set at completion.** After streaming without an incremental abort, the full guard set runs on the assembled text before `completed` (T6–T7; §6.4). Schema/business-rule validation, bounded repair, and structured output modes remain D6.
- **Cancel before first token vs mid-stream.** Separate cases (T13–T14); both abort via abort signal, terminate as `cancelled`, and credit partial usage when any exists (§6.5).
- **Deliberate Cancel vs network drop.** Indistinguishable; same path (T16; §5.5 rule 5; §6.5).
- **Out-of-band cancel / resume.** Not supported; no cancel endpoint; no Session Durable Object; no stream resume after reconnect (T17; §4.3.10; §6.5; §9.7).
- **One terminal event.** Guard abort and disconnect each still yield exactly one terminal event; no duplicate terminal (T15; §5.5 rule 4; A6).
- **Partial usage on cancel.** Tokens already generated are billed by the provider; cancellation credits partial usage rather than zeroing cost — free cancellation would be quota evasion (T10; §6.5).
- **Journal survival.** Cancelled or dropped requests remain explainable; the journal row exists from acceptance and survives cancellation (T11; §5.5 rule 6; §6.5). Writing the row remains C3; D4 must leave a terminal `cancelled` outcome the journal can record.
- **No per-request state.** An in-flight request exists only as an open connection plus a journal row; the broker creates no per-request Durable Object or other live request registry (T12; §4.3.10; §9.7).
- **No D1 row per chunk.** Stream chunks are not journaled as rows (T19; delivery plan §6.4 / §7.5).
- **Authoritative terminal payload.** Clients must not assemble the final result from chunks; provisional streamed text is never the committed answer (T7, T18; §6.4 invariants 1–2 as enforced on emission). Client UI commit affordances are E4.
- **Regenerating / fallback splice.** Owned by D3; D4 relays normalized events and must not reintroduce splicing across providers.
- **Structured / `structured_atomic` modes.** Named in §6.4 but owned by D6 (Needs D4); out of scope for this slice's Done when, which names incremental cheap guards for `prose`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The stream broker MUST relay normalized chunks to the client in order, using the A6 SSE framing, and MUST emit heartbeats while the stream is idle during provider silence so intermediaries do not time out (§4.3.10; §5.5 rule 3).
- **FR-002**: For `prose`, the broker MUST emit `text_delta` events and MUST apply cheap guards incrementally — length ceiling, stop-sequence, and system-prompt-leak detection; a violation MUST abort the stream and fail terminally (§6.4).
- **FR-003**: At `prose` completion, the broker MUST run the full guard set on the assembled text before emitting the terminal event (§6.4).
- **FR-004**: On successful `prose` completion after the full guard set passes, the broker MUST emit exactly one `completed` terminal event that carries the validated payload; that payload MUST be authoritative and self-contained so clients need not assemble the final result from chunks (§4.3.10; §5.5 rule 4; §6.4 invariant 1).
- **FR-005**: Exactly one terminal event MUST end every stream under broker paths — `completed` with the validated result, `failed` with a taxonomy code, or `cancelled` — and a terminal event MUST NOT be inferred from silence (§4.3.10; §5.5 rule 4).
- **FR-006**: Closing the stream MUST cancel the request; the platform MUST NOT distinguish a user Cancel from a network drop; both MUST abort the in-flight provider fetch through its abort signal and end the request as `cancelled` (§5.5 rules 5–6; §6.5; §4.3.10).
- **FR-007**: Cancellation MUST be connection-scoped: no separate cancel endpoint, no request registry, and no per-request server-side state of any kind (§4.3.10; §6.5; §9.7).
- **FR-008**: On cancellation, the broker MUST credit partial usage to the Quota Durable Object rather than treating cancelled generation as free (§6.5; delivery plan §3.5 Done when).
- **FR-009**: A cancelled or dropped request MUST remain fully explainable afterwards — the journal row survives regardless of whether a result was delivered (§5.5 rule 6; §6.5).
- **FR-010**: Out-of-band cancellation (from a different window or after reconnect) and stream resume MUST NOT be supported; a Session Durable Object MUST NOT be introduced (§4.3.10; §6.5; §9.7).
- **FR-011**: Cancel before the first token and cancel mid-stream MUST both follow FR-006–FR-009 (abort via abort signal, `cancelled`, partial-usage credit when applicable, journal row complete, no per-request state) (§6.5; delivery plan §3.11.4 D4).
- **FR-012**: The broker MUST NOT write a D1 row per stream chunk and MUST NOT create per-request server-side state (§4.3.10; §9.7; delivery plan §6.4).
- **FR-013**: Provisional streamed content emitted by the broker MUST NOT be treated as the committed result; only the validated terminal payload is authoritative for success (§6.4 invariants 1–2 as applied to broker emission).

### Key Entities

Not applicable — this slice defines no entities. It relays and terminates streams using existing canonical chunk/result/error types (A3), SSE framing (A6), invocation output (D3), and the Quota Durable Object credit call (B4); it adds no D1 tables or contract types.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Connection-scoped cancel (close the stream) matches the only product need — a clinician abandoning a generation on the screen that is showing it — without a Session Durable Object, cancel endpoint, or per-request state clinics would have to operate (§4.3.10, §9.7). Heartbeats and ordered prose streaming keep live draft usable on ordinary clinic networks; a dropped connection loses that generation and the user retries, which is affordable for seconds-long generations (§5.5 rule 5, §6.5).
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker). It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. Prompt text, provider names, and model identifiers must never enter the Flutter client (R-12); this Worker slice does not place them there.
- **Data Integrity & Security**: Cancel credits partial usage so quota cannot be evaded by disconnect (§6.5). The journal row from acceptance survives cancel so support can explain the request (§5.5 rule 6). No per-request state object and no D1 row per chunk keep write-path economics and audit shape intact (§4.3.10, §9.7, delivery plan §6.4). Clinical persistence of provisional text is forbidden structurally on the client (E4) and by broker emission rules (§6.4 invariant 2).
- **Failure Handling**: Incremental prose-guard violations abort and fail terminally (§6.4). Disconnect or Cancel aborts the provider fetch, terminates as `cancelled`, and credits partial usage (§6.5). Network drop is the same path as Cancel (§5.5 rule 5). Out-of-band cancel and resume are not offered (§9.7). Provider retry/fallback remains D3; schema/business validation and repair remain D6.

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **A6 (protocol adapter / SSE framing)**: D4 consumes framing, `accepted`, heartbeat shape, terminal kinds, and the one-terminal-event invariant; it does not redefine wire parsing or HTTP error mapping.
- **D3 (invocation / retry / fallback)**: D4 relays chunks and `regenerating` when present; it does not own attempt bounds, jitter, fallback walk, or splice prevention.
- **D6 (response validator, bounded repair, structured modes)**: Transport/schema/business validation order, repair re-ask, `validation_failed` after repair exhaustion, `partial_structured` / `structured_atomic` streaming semantics are D6 (§4.3.9; §6.4 structured rows). D4 owns the `prose` incremental cheap guards and completion-time full guard set named in §6.4's `prose` row.
- **D5 / D7 (real provider adapters)**: D4 runs against D2's fake via D3; live wire fixtures are D5/D7.
- **C3 (journal writer / get-request)**: D4 produces terminal `cancelled` / `completed` / `failed` outcomes the journal can record; writing `ai_request` updates, R2 envelopes, and get-request lookup remain C3.
- **B4 (Quota DO credit)**: D4 invokes partial-usage credit on cancel using B4's existing credit call; it does not redefine admission or credit RPCs.
- **E4 (first AI surface)**: Client provisional-draft UX, commit affordances, and degraded mode are E4; D4 enforces broker-side emission rules only.
- **H1 (conversational fourth terminal kind)**: `context_requested` is out of scope; A6/D4 realise the three `single_shot` terminal kinds.
- **Session Durable Object / out-of-band cancel / stream resume**: Explicitly rejected for now under §9.7; not added because they look prudent (R-20).

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20). D4 adds no Session Durable Object and no out-of-band cancel.
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — D4 is a Worker slice.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — D4's cancel path uses the existing credit call; it does not add a second credit or a second R2 object.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integration (spy) test proves normalized chunks are relayed in order (T1; Done when).
- **SC-002**: An integration (spy) test proves a heartbeat is emitted during provider silence (T2; Done when).
- **SC-003**: Integration (spy) tests prove each incremental prose guard (length ceiling, stop-sequence, system-prompt leak) aborts the stream and fails terminally (T3–T5; Done when).
- **SC-004**: An integration (spy) test proves the full guard set runs on the assembled text at completion (T6; Done when).
- **SC-005**: An integration (spy) test proves the terminal `completed` event carries the validated payload (T7; Done when).
- **SC-006**: An integration (spy) test proves client disconnect aborts the in-flight provider fetch via its abort signal (T8; Done when).
- **SC-007**: An integration (spy) test proves disconnect terminates the request as `cancelled` (T9; Done when).
- **SC-008**: An integration (spy) test proves partial usage is credited to the Quota Durable Object on cancel (T10; Done when).
- **SC-009**: An integration (spy) test proves the journal row is complete after cancel (T11; Done when).
- **SC-010**: An integration (spy) test proves no per-request state object is created (T12; Done when).
- **SC-011**: Integration (spy) tests prove cancel-before-first-token and cancel-mid-stream as separate cases (T13–T14; Done when).
- **SC-012**: Integration (spy) tests prove one-terminal-event under abort paths, network-drop≡cancel, no out-of-band cancel/Session DO, non-authoritative provisional chunks, and no D1 row per chunk (T15–T19; §3.10).

## Assumptions

- A6's SSE framing, terminal kinds, heartbeat event shape, and one-terminal-event invariant are available and unchanged; D4 implements broker behaviour against that framing (Needs A6).
- D3's invocation loop and fake-provider streaming path are available and unchanged; D4 relays invocation output and does not reimplement retry/fallback (Needs D3).
- B4's separate Quota Durable Object credit call already settles actual and partial usage; D4's cancel path invokes that existing credit contract and does not change it (§6.5; B4 Freezes).
- C3 already journals terminal states including `cancelled` and preserves the request row from acceptance; D4 supplies terminal outcomes and does not reimplement the journal writer (§5.5 rule 6; C3).
- Numeric thresholds for length ceiling and stop-sequence detection are supplied by capability/manifest or platform config already named elsewhere; this slice does not invent new threshold constants beyond the three named incremental guard *kinds* in §6.4.
- The specific §5.4 taxonomy code carried on a `failed` terminal event after an incremental-guard abort is taken from the existing closed taxonomy (A2); this slice does not add or rename codes.
- `structured` and `structured_atomic` streaming behaviour in §6.4 is deferred to D6; this slice's Done when and §3.11.4 case list cover `prose` plus cancellation.
- The platform does not ship until the whole product does (DP-1); "independently testable" means provable by an automated integration (spy) suite, not demonstrable to a user (DP-3).
