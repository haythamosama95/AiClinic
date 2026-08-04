# Feature Specification: Invocation with bounded retry and fallback

**Feature Branch**: `030-d3-invocation-retry-fallback`

**Created**: 2026-08-01

**Status**: Draft

**Input**: Slice `D3` — "Invocation with bounded retry and fallback" (delivery plan §3.5, band D).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.5, row D3):

> §4.3.7, §8.6, §6.6

### Freezes

Contracts this slice establishes for the first time:

- The **platform-internal attempt loop**: given the ordered candidate chain from the router (D2), the gateway walks targets in order, invoking each through the provider port; per-target retries are bounded by that target's `max_attempts` from the routing-policy document, each attempt is raced against the entry's `timeout_ms` (AbortSignal on invoke options; timed-out attempts classify as taxonomy `timeout`), backoff is exponential+jitter capped at `BACKOFF_CAP_MS` (10_000) and truncated to the remaining request `deadline` budget, and a retry occurs only when the adapter classifies the failure as retryable (§4.3.7 targets[].`max_attempts`; §6.6 Provider attempts; §8.6).
- The **fallback walk and attempt-level selection reasons**: advancing to the next target after retryable exhaustion records why *that* attempt was tried on `ai_attempt.selection_reason` as one of `primary`, `fallback_after_retryable_error`, `fallback_after_timeout` (and, only when speculative parallel attempts are executed, `speculative`); `fallback_after_timeout` applies when the prior target's **exhausting (final) failure** was timeout-classified (including mixed scripts); `repair_retry` is reserved for D6 and is not emitted by this slice (§4.3.7; §8.6).
- The **exhausted-chain outcome**: when every candidate target has been exhausted under retryable failure, **or the chain has no targets**, the request fails with `provider_unavailable` (§8.6; delivery plan §3.5 Done when).
- The **no-splice regenerating rule**: if the failed target had already produced streamed text (relayed `text_delta` chunks, including optional `chunks` on error results), a fallback restarts generation with an explicit `regenerating` event and discards the earlier provider's partial text — two providers' text are never spliced (§8.6). Detection uses a run-scoped sink wrapper; the caller-owned sink is never mutated.
- The **per-attempt journal feed**: each provider attempt is recorded separately (one journaled attempt per invoke) with required `idempotency_key`, outcome including distinct `truncation`, and optional usage/timing when the port returns them, for the existing journal writer (C3) to persist as `ai_attempt` rows / envelope `attempts[]`; this slice does not change C3's write-path contract (§6.6; §4.3.7; §8.6 diagram).

### Consumes

Contracts frozen by the slices in `Needs` (D2). Changing any of these is out of scope by definition:

- **From D2 (provider port and classification)**: the provider port, the deterministic fake adapter, and the retryable-versus-terminal classification contract — every failure through the port is classified exactly once; adapters own classification and own no retry or fallback decisions (§4.3.8 Freezes in D2). D3 retries only adapter-classified retryable failures and never moves retry/fallback into an adapter.
- **From D2 (routing-policy-as-data / candidate chain)**: the ordered candidate chain of provider+model targets, the selection reason recorded on the request (`routing_decision`), and the rule that the chain depends only on capability, policy, and this request — no circuit breaker and no shared provider-health state (§4.3.7, §7.3 Freezes in D2). D3 walks the chain it is given; it does not rebuild, reorder, or consult provider history when choosing the next target.
- **From D2 (target attempt bounds)**: each chain entry's `max_attempts` and `timeout_ms`, carried through unchanged from `rules[].targets[]` in the routing-policy document onto `routing_decision.chain[]` (§4.3.7; D2 `contracts/routing-decision.md` §4.1–§4.2). D3 reads and enforces those bounds off the chain entry it is walking (`max_attempts` invoke cap; `timeout_ms` raced with AbortSignal); it does not re-interpret policy and does not invent alternate caps.

### Open decisions relied on

None. D3's attempt loop, fallback, regenerating rule, and `provider_unavailable` outcome are fully specified by §4.3.7, §8.6, and §6.6; no §15 recommended default is assumed.

## Clarifications

### Session 2026-08-01

- Q: How should the attempt loop (retry / fallback / regenerating) be organised under `ai-platform/src/`? → A: New sibling module `src/invocation/` (attempt loop + tests); consumes `provider/` and `router/` `[implementation choice — no §citation]`
- Q: How should T6 (partial stream then retryable failure → fallback) drive the provider port without changing D2’s frozen fake outcome set? → A: Test-only port double/harness that yields partial chunks then a retryable error; production fake unchanged `[implementation choice — no §citation]`
- Q: How should T3 assert that backoff includes jitter without freezing a delay table or formula? → A: Inject a recording sleeper/delay function; assert requested delays across retries are not all identical `[implementation choice — no §citation]`
- Q: How should the integration suite observe per-attempt journal feeds (T4) and regenerating / discarded text (T6) without pulling in C3’s D1/R2 writer or D4’s stream broker? → A: Invocation accepts an in-memory event/attempt sink (collector); tests assert on collected attempts, `regenerating`, and discarded-vs-final text; production later wires the sink to C3 / the stream path `[implementation choice — no §citation]`

### Session 2026-08-04 (review resolution)

- Q: Which injectables belong on the frozen input surface? → A: Port resolver, event/attempt sink, sleeper, and injectable RNG for jitter proofs. `providerHistoryStore` is **not** an injectable (removed; §9.14 / FR-008) `[implementation choice — no §citation]`
- Q: Who enforces chain-entry `timeout_ms`? → A: D3 races each `port.invoke` against `timeout_ms`, passes `AbortSignal` on `ProviderInvokeOptions`, and classifies the loser as taxonomy `timeout` `[implementation choice — aligns with D2 port options; §4.3.7 carry-through]`
- Q: How is backoff bounded in time? → A: Exponential + jitter capped at `BACKOFF_CAP_MS` (10_000); sleeps truncated to remaining `CanonicalRequest.deadline` budget (relative ms from walk start; null = no truncation) `[implementation choice — no §citation]`
- Q: When is `fallback_after_timeout` recorded? → A: When the prior target's **exhausting (final) failure** was timeout-classified — including mixed non-timeout then timeout scripts (§8.6) `[clarifies §4.3.7 / §8.6]`
- Q: How is partial streaming detected without mutating the caller sink? → A: Relayed `text_delta` chunks (including optional `chunks` on error/malformed results) through a run-scoped observing sink wrapper; never mutate the injected sink `[implementation choice — no §citation]`
- Q: What does the attempt feed require beyond identity/outcome? → A: Required `idempotency_key`; outcome enum includes `truncation`; optional usage/timing when the port returns them; unmapped invoke kinds → classified `internal_error` attempt (no bare throw) `[implementation choice — no §citation]`
## User Scenarios & Testing *(mandatory)*

### User Story 1 - Invocation with bounded retry and fallback (Priority: P1)

As the AI Gateway Worker, after the router has produced an ordered candidate chain (D2), I invoke providers through the provider port with a platform-internal attempt loop: retries are bounded by each target's `max_attempts`, backoff is jittered, and a retry happens only for adapter-classified retryable failures; a terminal failure is not retried. When retries on a target are exhausted I fall back to the next chain entry, recording an attempt-level `selection_reason` (`primary`, `fallback_after_retryable_error`, or `fallback_after_timeout`). Each attempt is journaled separately. If every target fails retryably, I terminate with `provider_unavailable`. If a stream had already begun from a failed target, I emit an explicit `regenerating` event, discard that target's partial text, and never splice two providers' output.

**Why this priority**: D3 sits where it does because its `Needs` (D2) are the point at which the port, fake, classification contract, and policy-driven candidate chain exist — without those, the attempt loop would embed provider-shaped retry logic or consult history, both forbidden (§4.3.7, §6.6, §8.6). Every later inference-path slice (D4 stream broker, D5/D7 real adapters, CP3) depends on uniform bounded retry and fallback outside the adapters (delivery plan §3.5).

**Independent Test**: Provable by an integration suite against the deterministic fake adapter: drive retryable failure to the per-target cap then fallback; assert a terminal failure is not retried; assert jitter on backoff; assert one journaled attempt per invoke; assert an exhausted chain yields `provider_unavailable`; assert fallback after partial streaming emits `regenerating` and discards earlier text; assert the retry budget (`max_attempts` per target, and the walk across the chain) is never exceeded (delivery plan §3.11.4 row D3; §3.10).

**Acceptance Scenarios**:

1. **Given** a candidate chain whose first target is configured (via the fake) to fail retryably fewer times than its `max_attempts` then succeed, **When** invocation runs, **Then** the gateway retries that target with jittered backoff and completes successfully without falling back. *(retry then success on same target — happy / bounded retry)*
2. **Given** a candidate chain whose first target fails retryably up to its `max_attempts` and whose second target succeeds, **When** invocation runs, **Then** the gateway retries the first target to the cap, falls back to the second, and succeeds; attempt `selection_reason` values reflect `primary` then `fallback_after_retryable_error` (or `fallback_after_timeout` when the prior target's exhausting failure was timeout-classified, including mixed non-timeout then timeout scripts). *(retryable failure retried to the cap then falls back)*
3. **Given** a candidate chain whose first target returns an adapter-classified terminal failure, **When** invocation runs, **Then** that target is not retried and the chain is not continued for fallback; the request fails with that terminal error. *(terminal failure is not retried)*
4. **Given** any retryable backoff between attempts, **When** multiple retries occur, **Then** backoff includes jitter (requested delay ≠ pure exponential; delays ≤ `BACKOFF_CAP_MS`; sleeps truncated to remaining request deadline). *(jitter is applied; backoff time-bounded)*
5. **Given** a request that performs N provider invokes (retries and/or fallbacks), **When** attempt records are produced for the journal writer, **Then** exactly N separately journaled attempts are emitted — one per invoke — each carrying the same `idempotency_key`. *(every attempt is journaled separately)*
6. **Given** a candidate chain on which every target exhausts its retryable attempts, **or an empty chain**, **When** invocation finishes the walk, **Then** the request fails with `provider_unavailable` (empty chain: zero attempts). *(exhausted chain → provider_unavailable)*
7. **Given** a first target that streams partial text (`text_delta` chunks, including optional chunks on error) then fails retryably such that fallback is required, **When** the gateway starts the fallback target, **Then** it emits an explicit `regenerating` event before the fallback target's output, discards the earlier partial text, and never splices the first provider's text with the second's. *(fallback after partial streaming → regenerating; no splice)*
8. **Given** targets with declared `max_attempts` (including `max_attempts = 1`), **When** invocation runs under any failure script, **Then** no target is invoked more times than its `max_attempts`, no sleeper call occurs on a target's final attempt, and the walk never exceeds the chain's retry budget. *(retry budget is never exceeded)*
### Test plan

Layer: Integration (delivery plan §3.11.4, row D3; §13.5 Pipeline tests with fake provider). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `retryable_retried_to_cap_then_fallback` | Integration | Retryable failure retried to the cap then falls back (§3.11.4 D3; §8.6) |
| T2 | `terminal_failure_not_retried` | Integration | Terminal failure is not retried; no fallback walk after terminal (§3.11.4 D3; §6.6) |
| T3 | `jitter_applied_on_backoff` | Integration | Backoff with jitter (injectable RNG; ≤ `BACKOFF_CAP_MS`; deadline truncation) (§3.11.4 D3; §6.6; §8.6) |
| T4 | `every_attempt_journaled_separately` | Integration | One journaled attempt per invoke; feed carries `idempotency_key` (§3.11.4 D3; §6.6) |
| T5 | `exhausted_chain_provider_unavailable` | Integration | Exhausted or empty chain → `provider_unavailable` (§8.6; Done when) |
| T6 | `fallback_after_partial_stream_emits_regenerating` | Integration | Regenerating from relayed `text_delta`; earlier text discarded; no splice (§3.11.4 D3; §8.6) |
| T7 | `retry_budget_never_exceeded` | Integration | Per-target `max_attempts` (incl. `= 1`) / chain retry budget never exceeded (§3.11.4 D3; §4.3.7) |
| T8 | `first_attempt_success_no_fallback` | Integration | Happy path: primary success, single attempt, `selection_reason = primary` (§3.10; §4.3.7) |
| T9 | `timeout_exhaustion_fallback_reason` | Integration | Exhausting failure timeout-classified (incl. mixed) → `fallback_after_timeout` (§4.3.7; §8.6; §3.10 branch) |
| T10 | `fallback_only_walks_given_chain` | Integration | Fallback uses only router-supplied targets that already satisfy capability requirements — no invented targets (§8.6; §3.10 named boundary) |
| T11 | `no_provider_history_consulted` | Integration (spy) | Next target choice does not consult prior-request provider history / no circuit breaker; store not on input (§4.3.7; §8.6; R-20 / §9.14) |
| T12 | `internal_retry_same_request_not_user_retry` | Integration | Platform-internal retries keep same `request_id` / `idempotency_key` on the attempt feed (§6.6; §3.10) |
| T13 | `repair_retry_reason_not_emitted` | Integration | D3 never records `selection_reason = repair_retry` (reserved for D6) (§4.3.7; §3.10 inherited boundary) |

---

### Edge Cases

- **Error codes this slice can emit.** `provider_unavailable` when the candidate chain is exhausted under retryable failure or empty (Done when; §8.6). Adapter-classified **terminal** errors returned from the port are surfaced as the request's failure without retry or fallback (T2); D3 does not invent new taxonomy codes. Unmapped invoke result kinds become a classified `internal_error` attempt — never a bare throw.
- **Retryable vs terminal boundary.** Retries occur only for adapter-classified retryable failures (§6.6). A terminal failure is not retried on that target and does not continue the fallback walk — selection_reason values name only `fallback_after_retryable_error` and `fallback_after_timeout` for advancing (§4.3.7).
- **Retry budget / `max_attempts`.** Each target's `max_attempts` from the routing-policy document bounds invokes of that target; the budget is never exceeded (T7; §4.3.7). `max_attempts = 1` is one invoke with no inter-retry sleep. No alternate numeric cap is invented in this slice.
- **Per-attempt `timeout_ms`.** D3 races each invoke against the chain entry's `timeout_ms` and passes `AbortSignal` on `ProviderInvokeOptions`; timed-out attempts classify as taxonomy `timeout` (retryable).
- **Jitter / backoff cap / deadline.** Backoff between retries is exponential + jitter, capped at `BACKOFF_CAP_MS` (10_000). Sleeps are truncated to the remaining `CanonicalRequest.deadline` budget (relative ms from walk start; null = no truncation). Jitter proofs use an injectable RNG (delay ≠ pure exponential).
- **Timeouts and fallback reason.** Timeouts are retryable in the §8.6 sequence. `fallback_after_timeout` is set when the prior target's **exhausting (final) failure** was timeout-classified — including mixed non-timeout then timeout scripts (§4.3.7, §8.6).
- **Partial stream then fallback.** Explicit `regenerating` event (once, before fallback output) when prior target produced relayed `text_delta` text; discard earlier partial text; never splice across providers (§8.6). No regenerating without prior partial text. Sink is wrapped locally, never mutated. Stream *relay*, heartbeats, and incremental guards remain D4.
- **Truncation in the attempt feed.** Port `truncation` outcomes are journaled as `outcome: truncation` (distinct from `success`), with optional usage/timing when present.
- **Fallback eligibility.** Fallback is only to targets that satisfy the capability's declared requirements (§8.6). D3 walks the D2-filtered chain and must not add targets outside it (T10).
- **Stateless routing during outage.** The router consults no history; each request independently walks its chain, paying failed first attempts during an outage (§8.6, §4.3.7). No circuit breaker and no `providerHistoryStore` on the invocation input (R-20 / §9.14).
- **Internal retry vs user-initiated retry.** An internal retry is the same request, new attempt, separately journaled with the same `idempotency_key` on the feed. A user-initiated retry is a distinct new request with a new idempotency key (§6.6). D3 implements only the internal path.
- **`repair_retry`.** Named on `ai_attempt.selection_reason` in §4.3.7 but owned by D6's bounded repair; D3 must not emit it (T13).
- **Speculative parallelism (`max_parallel_attempts` > 1).** Named on the policy document and as a `selection_reason` value in §4.3.7; the §8.6 sequence and the §3.11.4 D3 case list specify the sequential retry/fallback walk. Parallel speculative execution is out of scope for this slice's Done when (see Out of Scope).
- **Client idempotency / duplicate suppression.** The Platform and Client submission rows of §6.6 are owned by earlier slices (B4 / client); D3 does not re-admit or map idempotency keys.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Given the router's ordered candidate chain, the gateway MUST attempt targets in order through the provider port, with per-target retries bounded by that target's `max_attempts` from the routing-policy document and each attempt bounded by that entry's `timeout_ms` (§4.3.7; §8.6).
- **FR-002**: Retries MUST be platform-internal, bounded (attempt count and backoff time: jittered exponential capped at `BACKOFF_CAP_MS`, truncated to remaining request `deadline`), and only for adapter-classified retryable failures; each attempt MUST be journaled separately with the same `idempotency_key` (§6.6).
- **FR-003**: A terminal (non-retryable) adapter-classified failure MUST NOT be retried on that target and MUST NOT continue the fallback walk; the request fails with that terminal error (§6.6; §4.3.7 selection_reason set).
- **FR-004**: After retryable exhaustion on a target (including when the exhausting failure is timeout-classified), the gateway MUST fall back to the next chain entry when one remains, recording attempt-level `selection_reason` as `primary`, `fallback_after_retryable_error`, or `fallback_after_timeout` as appropriate (§4.3.7; §8.6).
- **FR-005**: When every candidate target has failed retryably to its bound, or the chain is empty, the gateway MUST fail the request with `provider_unavailable` (§8.6; delivery plan §3.5 Done when).
- **FR-006**: Fallback MUST restart generation: if the failed target had already produced streamed text (relayed `text_delta`), the gateway MUST emit an explicit `regenerating` event and MUST NOT splice partial text from the failed provider with another provider's text (§8.6).
- **FR-007**: Fallback MUST only use targets from the router-supplied chain (targets that already satisfy the capability's declared requirements); the attempt loop MUST NOT invent, widen, or history-reorder the chain (§8.6; §4.3.7).
- **FR-008**: Routing during the walk MUST remain explainable from this request's journal: the attempt loop MUST NOT consult shared provider-health state or a circuit breaker, and MUST NOT accept a `providerHistoryStore` injectable (§4.3.7; §8.6; §9.14).
- **FR-009**: Platform-internal retries MUST stay on the same request and MUST carry the same `idempotency_key` on the attempt feed; they MUST NOT be conflated with a user-initiated retry (a distinct new request with a new idempotency key) (§6.6).
- **FR-010**: The attempt loop MUST NOT exceed any target's `max_attempts` (the retry budget) under any failure script (§4.3.7; delivery plan §3.11.4 D3).
- **FR-011**: The attempt loop MUST NOT record `selection_reason = repair_retry` (reserved for bounded repair in D6) (§4.3.7).

### Key Entities

- **Attempt (journal feed)**: One provider invoke within a request — target identity, outcome (`success` \| `truncation` \| `retryable_failure` \| `terminal_failure` \| `timeout`), required `idempotency_key`, optional usage/timing, and `selection_reason` (`primary` \| `fallback_after_retryable_error` \| `fallback_after_timeout` \| `speculative` \| `repair_retry`). D3 produces these records for C3 to persist; it adds no new D1 columns (§4.3.7; §6.6).
- **Regenerating signal**: The explicit stream event that marks a restarted generation after fallback when partial text was already relayed; paired with discard of the prior provider's partial text (§8.6).
## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Bounded, jittered retry and multi-target fallback keep a single provider outage from blocking clinic AI assistance, while keeping "why this provider?" answerable from one request's journal — operable without a health cluster or circuit-breaker fabric clinics cannot staff (§4.3.7, §8.6). Failed first attempts cost latency during an outage by design; that trade is preferred over shared health state (§8.6, §9.14).
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker). It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. Provider names and model identifiers remain inside Worker routing/adapter data; they must never enter the Flutter client (R-12).
- **Data Integrity & Security**: Each attempt is journaled separately for the existing C3 journal writer (`ai_attempt` / envelope `attempts[]`); D3 does not alter A5 schema or C3 timings (§6.6, §4.3.7). No clinical data is interpreted by the attempt loop. Credentials stay inside adapters (D2/D5); D3 does not log them.
- **Failure Handling**: Retryable adapter failures are retried with jitter up to `max_attempts`, then fall back; terminal failures fail the request immediately; an exhausted chain yields `provider_unavailable` (§6.6, §8.6). Partial streamed text from a failed target is discarded and replaced after a `regenerating` event — never spliced (§8.6). Stream cancellation on disconnect is D4. User-initiated retry is a new client request (§6.6), not this loop.

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **D2 (provider port, fake, routing)**: D3 consumes the port, classification, and candidate chain; it does not redefine them or add circuit breakers (§4.3.7, §4.3.8).
- **D4 (stream broker, prose streaming, cancellation)**: Relaying normalized chunks, heartbeats, incremental guards, disconnect→abort→`cancelled`, and partial usage credit are D4. D3 owns the regenerating decision and discard-on-fallback rule when the attempt loop restarts a target (§4.3.10, §8.6).
- **D5 / D7 (real provider adapters)**: D3 runs against D2's fake; live wire fixtures and a second provider are D5/D7.
- **D6 (response validator and repair)**: Validation order, bounded re-ask, and `selection_reason = repair_retry` are D6 (§4.3.9).
- **C3 (journal writer)**: D3 feeds per-attempt records; writing `ai_attempt` rows, the R2 envelope, and usage events on C3's schedule is unchanged (§4.3.11).
- **B4 (idempotency / admission)**: Client idempotency keys mapping to at most one request per installation are B4; D3 does not re-implement the Platform or Client submission rows of §6.6.
- **Speculative parallel attempts (`max_parallel_attempts` > 1)**: Named in §4.3.7; this slice's Done when and §8.6 sequence are the sequential retry/fallback walk. Parallel speculative execution is not in the §3.11.4 D3 case list.
- **Health-based provider routing / circuit breakers**: Deliberate deferrals under §9.14; not added because they look prudent (R-20) (§4.3.7, §8.6).

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20). D3 adds no circuit breaker and no shared provider-health store.
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — D3 is a Worker slice.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — D3 performs no DO and no R2 I/O of its own.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5) — D3 journals attempts via C3's existing per-attempt path, not per chunk.
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integration test proves a retryable failure is retried to the per-target cap then falls back to a succeeding target (T1; Done when).
- **SC-002**: An integration test proves a terminal failure is not retried and does not continue the fallback walk (T2; Done when).
- **SC-003**: An integration test proves backoff between retries includes jitter (T3; Done when).
- **SC-004**: An integration test proves every provider invoke is journaled as a separate attempt (T4; Done when).
- **SC-005**: An integration test proves an exhausted retryable chain fails with `provider_unavailable` (T5; Done when).
- **SC-006**: An integration test proves fallback after partial streaming emits `regenerating`, discards earlier text, and never splices providers (T6; Done when).
- **SC-007**: An integration test proves the retry budget (`max_attempts` / chain walk) is never exceeded (T7; Done when).
- **SC-008**: Integration tests prove the happy path, timeout fallback reason, chain-only fallback, no history/circuit breaker, internal-vs-user retry distinction, and that `repair_retry` is not emitted (T8–T13; §3.10).

## Assumptions

- D2's provider port, fake adapter, classification contract, and routing-policy candidate chain are available and unchanged; D3's suite drives the fake (§4.3.8, §4.3.7; Needs D2).
- C3's journal writer already accepts per-attempt records and persists `ai_attempt` rows in the post-response continuation; D3 feeds that contract and does not change it (§4.3.11).
- Per-target `max_attempts` and `timeout_ms` are present on routing-policy targets as named in §4.3.7; fixture policies in tests supply them — D3 does not invent numeric defaults for those fields. D3 **does** enforce `timeout_ms` by racing the invoke and classifying the loser as `timeout`.
- Jitter is required (§6.6, §8.6). The concrete schedule is exponential + jitter with documented ceiling `BACKOFF_CAP_MS = 10_000` and deadline-aware truncation — an implementation choice constrained by "bounded" and "jittered."
- Speculative parallel execution (`max_parallel_attempts` > 1) is deferred beyond this slice's Done when; sequential walk covers §8.6 and §3.11.4 D3.
- The platform does not ship until the whole product does (DP-1); "independently testable" means provable by an automated integration suite, not demonstrable to a user (DP-3).