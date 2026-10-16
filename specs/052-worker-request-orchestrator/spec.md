# Feature Specification: Worker request orchestrator on `POST /v1/requests` (I1)

**Feature Branch**: `ai/052-i1-worker-request-orchestrator`

**Created**: 2026-08-07

**Status**: Draft

**Input**: Slice `I1` — *Worker request orchestrator on `POST /v1/requests`* (Delivery Plan §3.10, row I1).

> Constitution note: This slice lives entirely inside the Cloudflare AI Gateway Worker
> (`ai-platform/`), the additive, non-primary component. Per §14 acknowledgement of
> `01-ai-platform.md`, the gateway holds no domain logic, no business data, and has no write path
> into Supabase. I1 wires an already-frozen pipeline onto the live `POST /v1/requests` route; it
> invents no new store, contract, or stage.

## Slice Contract

### Implements

§6.1 stages 1–16, §4.3.1, §4.3.10, §5.5, §6.4 (copied verbatim from the I1 `Canonical` cell,
Delivery Plan §3.10).

### Freezes

**None.** Band I freezes no new contract (Delivery Plan §3.10; §2.3). I1 composes contracts already
frozen by A6, B3, B4, C1, C2, C3, D1, D2, D3, D4, and D6 onto the production Worker fetch path. Later
slices may not rewrite those consumed contracts through this slice.

What this slice *does* establish for the first time is **production wiring only**: `worker.ts`
supplies a production `preAccept` + `eventSource` to the protocol adapter so a live
`POST /v1/requests` runs the §6.1 sequence end to end with deferred `accepted`. That is composition
(plus the documented A6 framing extension for the pre-stream accept gate), not a new wire or
pipeline contract.

### Consumes

Contracts frozen by the slices in `Needs` (A6, B3, B4, C1, C2, C3, D1, D2, D3, D4, D6). Rewriting
those contracts' published behaviour is out of scope. **One documented exception for A6 framing:**
I1 is allowed to implement A6's composition extension
(`specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md` §8 — pre-stream accept gate /
deferred `accepted`) in `ai-platform/src/adapter.ts` as in-scope live-composition work. That
extension does not invent new platform behaviour; it makes §4.3.11 / §5.5 / §6.1 composable on the
live path. I1 does not otherwise redefine A6's event vocabulary, terminal invariant, or header set.

- **From A6 (protocol adapter and SSE framing)**: request parsing, ingress size limits, header
  handling (idempotency key, client trace id, capability version pin), SSE framing, taxonomy-to-HTTP
  translation, `accepted` opening event (**deferred until the pre-stream accept gate succeeds**),
  heartbeat framing, one-terminal-event invariant, the injected `eventSource` (post-accept only),
  and the optional `preAccept` gate (§4.3.1, §5.5; A6 contract §8). I1 supplies `preAccept` (guard
  through journal) and `eventSource` (post-accept pipeline / broker); implementing the deferred-
  `accepted` framing in the adapter is allowed composition, not a Consumes violation.
- **From B3 (guard stages 2–4)**: identity verification through the token verifier port, immutable
  request principal, rate-limit composite keys, entitlement and kill-switch evaluation from the
  config cache, and the rule that guard rejections are never journaled as requests (§6.1 stages 2–4).
- **From B4 (Quota DO and admission)**: one admission Durable Object round trip answering `jti`
  freshness, idempotency novelty, budget, and concurrency; a separate credit call after the response;
  repeated idempotency key returns the prior request state and starts no second inference; capped
  fail-open grace when the DO is unavailable (Open Decision 3) (§6.1 stage 8, §6.6).
- **From C1 (capability resolve)**: `capability id + version` resolves to one immutable manifest;
  distinct `capability_unknown`, `capability_retired`, and `capability_disabled` (§6.1 stage 5).
- **From C2 (context validate and cost pre-flight)**: required keys and shapes; `context_required`
  with missing-key manifest; `context_invalid`; undeclared keys dropped; CPU-only cost ceiling
  producing `request_too_large` before egress (§6.1 stages 6–7).
- **From C3 (journal writer and post-response detail)**: synchronous `ai_request` insert before work
  (stage 9); terminal-state update and Quota DO credit (stage 15); exactly one R2 payload envelope
  plus attempt and usage rows after the response, never failing the request (stage 16); no journal
  row on guard rejection (§6.1 stages 9, 15, 16).
- **From D1 (prompt registry and composer)**: canonical request composition from pinned artifacts and
  validated context (stage 10).
- **From D2 (provider port, fake adapter, routing policy)**: provider port and deterministic fake
  adapter; versioned routing-policy data yields the candidate chain; selection reason recorded;
  chain depends only on capability, policy, and request — never provider history (§6.1 stage 11).
- **From D3 (invocation with bounded retry and fallback)**: bounded jittered retry for retryable
  failures; separate attempt journaling; exhausted chain → `provider_unavailable`; regenerating on
  fallback after partial streaming (§6.1 stage 11).
- **From D4 (stream broker and cancellation)**: normalized chunk relay, heartbeats during silence,
  connection-scoped disconnect abort of the in-flight provider fetch, `cancelled` terminal state,
  partial-usage credit, no per-request server-side state (§4.3.10, §5.5, §6.1 stages 12–14).
- **From D6 (response validator, repair, structured modes)**: ordered validation and optional
  bounded repair; `validation_failed` when exhausted; terminal payload self-contained and never
  assembled from chunks; provisional content never authoritative (§4.3.9 via D6 Done when; §6.4;
  §6.1 stage 13).

I1 consumes the existing `src/pipeline` composer (`runGuard` / settle) and D4's stream broker —
`runGuard` (through acceptance / journal) as the adapter `preAccept` gate, and the broker / settle
path as the post-accept `eventSource`. It does not rewrite those pipeline or broker modules
(Delivery Plan §3.10). It may extend A6 adapter framing only as documented in A6 contract §8.

### Open decisions relied on

- **Open Decision 3** (Quota DO unavailable: fail open or fail closed?): recommended default — fail
  open with a capped grace allowance and reconciliation. Assumed because I1 wires B4's admission
  stage onto the live path; I1 does not change the grace policy.

No other §15 decision is assumed. Soft-threshold / degraded routing remains F4 and is not part of
this slice. First-capability choice (OD-1) is exercised by the fake-adapter CP3 Worker half only as
routing-policy and fixture data already frozen by D2; I1 does not select the product capability.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — I1: Worker request orchestrator on `POST /v1/requests` (Priority: P1)

As the platform reviewer, I want `worker.ts` to supply a production `preAccept` gate and
`eventSource` to the A6 protocol adapter (deferred `accepted` per A6 contract §8) so that a live
`POST /v1/requests` runs the full §6.1 sequence end to end — guard stages 1–10 (including one Quota
DO admission and one D1 journal insert) before the stream opens, then route/invoke through the fake
adapter selected by routing policy, stream relay with heartbeats and disconnect abort,
validate/repair, exactly one terminal SSE event, then credit and post-response detail — so that CP2
and the Worker half of CP3 are reified on the real HTTP path rather than only in injectable
harnesses.

**Why this priority**: I1 sits first in Band I because its `Needs` (A6, B3, B4, C1, C2, C3, D1, D2,
D3, D4, D6) are the complete set of modules required to compose a request path. Earlier bands froze
each §4 component behind an injectable surface and deferred production wiring; without I1,
`POST /v1/requests` still returns an adapter shell with no `eventSource` (Delivery Plan §3.10).
Completing I1 reifies CP2 on live HTTP and the Worker half of CP3.

**Independent Test**: `worker.ts` supplies a production `preAccept` + `eventSource` to the protocol
adapter so a live `POST /v1/requests` runs the §6.1 sequence end to end: guard stages 1–10
(including one Quota DO admission and one D1 journal insert) complete before `accepted` / stream
open; route/invoke, stream relay with heartbeats and disconnect abort, validate/repair, exactly one
terminal SSE event, then credit and post-response detail; a guard rejection returns taxonomy **HTTP**
(no SSE stream, no `accepted`) with **no** `ai_request` row; the fake adapter path satisfies the CP3
Worker half; real adapters (D5/D7) are selected only by routing policy; no per-request server-side
state and no second DO or R2 object per request (Delivery Plan §3.10 Done when; A6 contract §8).

**Acceptance Scenarios**:

1. **Given** an enrolled installation with a valid AAT and a routing policy that selects the fake
   adapter, **When** the client `POST`s `/v1/requests` through `SELF.fetch` (or equivalent), **Then**
   the stream opens with `accepted`, streams fake-provider chunks, and ends with exactly one
   `completed` terminal event. *(happy path — live compose)*
2. **Given** the happy-path request above, **When** the request passes the guard and reaches invoke,
   **Then** exactly one `ai_request` row is written before the provider is invoked. *(one journal
   insert before invoke)*
3. **Given** the happy-path request above, **When** the terminal event has been emitted, **Then**
   exactly one R2 payload envelope is written after the response. *(one R2 envelope after)*
4. **Given** the happy-path request above, **When** admission and settlement complete, **Then**
   exactly two Quota Durable Object round trips occur (admit + credit) and no third. *(exactly two DO
   round trips)*
5. **Given** a request with an invalid or missing AAT, **When** `POST /v1/requests` is issued,
   **Then** the response is the `unauthenticated` taxonomy error, no `ai_request` row is written, and
   the provider is not called. *(guard reject — unauthenticated)*
6. **Given** a caller that has tripped a rate-limit composite key, **When** `POST /v1/requests` is
   issued, **Then** the response is `rate_limited`, no journal row, and no provider call. *(guard
   reject — rate_limited)*
7. **Given** an installation not entitled for the requested capability, **When** `POST /v1/requests`
   is issued, **Then** the response is `forbidden_capability`, no journal row, and no provider call.
   *(guard reject — forbidden_capability)*
8. **Given** an unknown capability id, **When** `POST /v1/requests` is issued, **Then** the response
   is `capability_unknown`, no journal row, and no provider call. *(guard reject —
   capability_unknown)*
9. **Given** a retired capability id, **When** `POST /v1/requests` is issued, **Then** the response
   is `capability_retired`, no journal row, and no provider call. *(guard reject —
   capability_retired)*
10. **Given** a capability disabled by kill switch, **When** `POST /v1/requests` is issued, **Then**
    the response is `capability_disabled`, no journal row, and no provider call. *(guard reject —
    capability_disabled)*
11. **Given** a request missing a required context key, **When** `POST /v1/requests` is issued,
    **Then** the response is `context_required`, no journal row, and no provider call. *(guard reject
    — context_required)*
12. **Given** a request with malformed or shape-invalid context, **When** `POST /v1/requests` is
    issued, **Then** the response is `context_invalid`, no journal row, and no provider call. *(guard
    reject — context_invalid)*
13. **Given** a request that fails ingress size or cost pre-flight, **When** `POST /v1/requests` is
    issued, **Then** the response is `request_too_large`, no journal row (when rejected before stage
    9), and no provider call. *(guard reject — request_too_large)*
14. **Given** an installation with exhausted quota, **When** `POST /v1/requests` is issued, **Then**
    the response is `quota_exhausted`, no journal row, and no provider call. *(guard reject —
    quota_exhausted)*
15. **Given** a prior successful (or in-flight) request under an idempotency key, **When** the same
    installation submits again with that key, **Then** the platform returns the prior request's state
    and starts no second inference. *(idempotency)*
16. **Given** an in-flight live request streaming from the fake provider, **When** the client
    disconnects, **Then** the in-flight provider fetch is aborted, the terminal state is `cancelled`,
    and partial usage is credited when present. *(cancel)*
17. **Given** any live request path composed by I1, **When** the request runs to any terminal
    outcome, **Then** no per-request Durable Object and no other per-request server-side request
    state is created. *(invariant — no per-request state)*
18. **Given** a routing-policy edit that changes provider selection, **When** a subsequent live
    request is admitted, **Then** the selected adapter changes only via that routing-policy data —
    not via a pipeline code change — and the fake adapter path remains the CP3 Worker half default
    until policy selects otherwise; real adapters (D5/D7) are reached only when policy says so.
    *(invariant — provider selection via routing policy)*

### Test plan

Layer: Workers integration (spy) (Delivery Plan §3.12.9 row I1). Assertions that prove work *not*
done use spies (Delivery Plan §3.11). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `live_post_happy_path_accepted_stream_completed` | Workers integration (spy) | Valid AAT `POST /v1/requests` via `SELF.fetch` opens `accepted`, streams fake chunks, ends with exactly one `completed` (§3.12.9 I1; §5.5 rules 1, 4; §6.1) |
| T2 | `ai_request_written_before_invoke` | Workers integration (spy) | Exactly one `ai_request` insert before provider invoke (§3.12.9 I1; §6.1 stage 9) |
| T3 | `one_r2_envelope_after_response` | Workers integration (spy) | Exactly one R2 envelope after terminal event (§3.12.9 I1; §6.1 stage 16) |
| T4 | `exactly_two_do_round_trips_admit_and_credit` | Workers integration (spy) | Admit + credit only — two DO round trips (§3.12.9 I1; §6.1 stages 8, 15; §7.5) |
| T5 | `guard_reject_unauthenticated_no_journal_no_provider` | Workers integration (spy) | `unauthenticated` as taxonomy **HTTP** (no SSE / no `accepted`); no journal; no provider (§3.12.9 I1; §6.1 stage 2; A6 §8) |
| T6 | `guard_reject_rate_limited_no_journal_no_provider` | Workers integration (spy) | `rate_limited` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stage 4; A6 §8) |
| T7 | `guard_reject_forbidden_capability_no_journal_no_provider` | Workers integration (spy) | `forbidden_capability` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stage 3; A6 §8) |
| T8 | `guard_reject_capability_unknown_no_journal_no_provider` | Workers integration (spy) | `capability_unknown` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stage 5; A6 §8) |
| T9 | `guard_reject_capability_retired_no_journal_no_provider` | Workers integration (spy) | `capability_retired` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stage 5; A6 §8) |
| T10 | `guard_reject_capability_disabled_no_journal_no_provider` | Workers integration (spy) | `capability_disabled` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stage 5; A6 §8) |
| T11 | `guard_reject_context_required_no_journal_no_provider` | Workers integration (spy) | `context_required` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stage 6; A6 §8) |
| T12 | `guard_reject_context_invalid_no_journal_no_provider` | Workers integration (spy) | `context_invalid` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stage 6; A6 §8) |
| T13 | `guard_reject_request_too_large_no_journal_no_provider` | Workers integration (spy) | `request_too_large` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stages 1, 7; A6 §8) |
| T14 | `guard_reject_quota_exhausted_no_journal_no_provider` | Workers integration (spy) | `quota_exhausted` as taxonomy **HTTP**; no journal; no provider (§3.12.9 I1; §6.1 stage 8; A6 §8) |
| T15 | `idempotency_repeat_returns_prior_no_second_inference` | Workers integration (spy) | Repeated key returns prior state; no second inference (§3.12.9 I1; §6.1 stage 8; §6.6) |
| T16 | `cancel_disconnect_aborts_cancelled_credits_partial` | Workers integration (spy) | Disconnect aborts fetch; `cancelled`; partial usage credited when present (§3.12.9 I1; §4.3.10; §5.5 rule 5; §6.1 stage 12) |
| T17 | `no_per_request_server_side_state` | Workers integration (spy) | No per-request DO or other server-side request state (§3.12.9 I1; §4.3.10; Delivery Plan §6.4) |
| T18 | `provider_selection_only_via_routing_policy` | Workers integration (spy) | Adapter selection changes only via routing-policy data; fake path is CP3 Worker half; D5/D7 only by policy (§3.12.9 I1; D2; Done when) |
| T19 | `guard_reject_installation_suspended_no_journal_no_provider` | Workers integration (spy) | `installation_suspended` as taxonomy **HTTP**; no journal; no provider (§3.11 coverage — every §6.1 emit code; §6.1 stages 2–3; A6 §8) |
| T20 | `post_guard_failed_terminal_provider_unavailable` | Workers integration (spy) | Exhausted invocation chain surfaces `provider_unavailable` as exactly one `failed` terminal (§3.11 coverage; §6.1 stage 11) |
| T21 | `post_guard_failed_terminal_validation_failed` | Workers integration (spy) | Validation/repair exhaustion surfaces `validation_failed` as exactly one `failed` terminal; invalid content never emitted (§3.11 coverage; §6.1 stage 13; §6.4) |
| T22 | `exactly_one_terminal_event_on_every_live_path` | Workers integration (spy) | Every live path ends with exactly one terminal event — never inferred from silence (§5.5 rule 4; §4.3.10; §3.11 coverage) |
| T23 | `worker_supplies_production_event_source` | Workers integration (spy) | Production `worker.ts` injects non-null `preAccept` + `eventSource`; live route is not the A6 missing-source 503 shell (Done when; §4.3.1; A6 §8) |

### Edge Cases

- **Every guard failure code the live path can emit before stage 9** produces a taxonomy **HTTP**
  error (**no** SSE stream, **no** `accepted` event), **no** `ai_request` row, and **no** provider
  call: `unauthenticated`, `installation_suspended`, `forbidden_capability`, `rate_limited`,
  `capability_unknown`, `capability_retired`, `capability_disabled`, `context_required`,
  `context_invalid`, `request_too_large`, `quota_exhausted` (§6.1 stages 1–8; §3.12.9 I1; Delivery
  Plan §6.4 — no guard rejection journaled; A6 contract §8 deferred `accepted`).
- **Ingress `request_too_large` (stage 1)** rejects before other work; **cost-preflight
  `request_too_large` (stage 7)** rejects before egress — both before journal insert (§6.1 stages 1,
  7, 9).
- **Idempotent replay** after admission returns the original request state and must not start a
  second inference or a second journal insert for a new request (§6.1 stage 8; §6.6).
- **Client disconnect** (Cancel or network drop — indistinguishable) aborts the in-flight provider
  fetch via its abort signal, terminates as `cancelled`, credits partial usage when present, and
  leaves the journal row explainable (§4.3.10; §5.5 rules 5–6; §6.1 stage 12).
- **Post-guard failures** (`provider_unavailable`, `provider_rejected`, `timeout`,
  `validation_failed`) end the stream with exactly one `failed` terminal event; the journal row
  exists (accepted before invoke) and is updated to the terminal state (§6.1 stages 11–15; §5.5
  rule 4).
- **Stage 16 detail failure** (attempt rows, usage ledger, R2 envelope) must never fail the request
  the client already received (§6.1 stage 16).
- **No second Quota DO round trip** beyond admit + credit, and **no second R2 object** per request
  (§7.5 via Delivery Plan §6.4; Done when).
- **No per-request server-side state** of any kind; out-of-band cancel is not supported (§4.3.10;
  Delivery Plan §6.4).
- **Soft-threshold / degraded routing** is out of scope (F4). Crossing a soft threshold is not an I1
  acceptance criterion and must not be asserted here.
- **Provisional stream chunks** are never the authoritative result; the terminal `completed` payload
  is self-contained (§6.4 invariants 1–2). I1 does not assemble a final result from chunks on any
  server path that would imply otherwise.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `worker.ts` MUST supply a production `preAccept` gate and `eventSource` to the
  protocol adapter so that a live `POST /v1/requests` is not the missing-`eventSource` adapter shell
  and runs the composed pipeline with deferred `accepted` (§4.3.1; A6 contract §8; Delivery Plan
  §3.10 Done when).
- **FR-002**: A live `POST /v1/requests` MUST traverse §6.1 stages 1–16 in order: ingress and shape;
  identity; entitlement; rate limit; capability resolve; context validate; cost pre-flight;
  admission (single Quota DO round trip); journal the request; prompt composition; route and invoke;
  stream relay; validate (and optionally repair); terminal emit; record outcome (journal update +
  Quota DO credit); detail and payloads (post-response) (§6.1). Stage 9 (journal) MUST complete
  before the SSE stream opens.
- **FR-003**: Stages 1–10 (the guard) MUST complete with exactly two I/O operations in the common
  case — one Durable Object round trip (admission) and one D1 insert (journal) — before any provider
  call (§6.1).
- **FR-004**: The protocol adapter remains the owner of wire format only — request parsing, size
  limits, header handling, SSE framing, taxonomy-to-HTTP translation, and the pre-stream accept gate
  — while I1 provides production `preAccept` (guard through journal) and `eventSource` (post-accept
  stream work) (§4.3.1; A6 contract §8). Implementing that deferred-`accepted` framing in
  `adapter.ts` is in-scope I1 composition.
- **FR-005**: Submit-request MUST accept capability, intent, context payload, idempotency key, and
  version pin; Cancel MUST remain connection-scoped (close the stream; no separate endpoint); the
  streaming protocol rules of §5.5 MUST hold on the live path (§5.5).
- **FR-006**: An **accepted** stream MUST open with an `accepted` event carrying the request
  reference, emitted only after the pre-stream accept gate succeeds; pre-accept guard failure MUST
  NOT open a stream or emit `accepted` (§5.5 rule 1; A6 contract §8).
- **FR-007**: Heartbeats MUST be emitted so intermediaries do not time out an idle stream (§4.3.10;
  §5.5 rule 3).
- **FR-008**: Every live stream MUST end with exactly one terminal event — `completed` with the
  validated result, `failed` with a taxonomy code, or `cancelled` — never inferred from silence
  (§4.3.10; §5.5 rule 4). Conversational `context_requested` is not in scope for I1's first compose
  path (H1).
- **FR-009**: Closing the stream MUST cancel the request: the Worker observes disconnect, aborts the
  in-flight provider fetch through its abort signal, and ends as `cancelled` (§4.3.10; §5.5 rule 5;
  §6.1 stage 12).
- **FR-010**: A request that passes the guard MUST leave a journal record from the moment it is
  accepted (stage 9), **before** the stream opens and before `accepted` is emitted, including when
  later cancelled or failed (§5.5 rule 6; §4.3.11; §6.1 stage 9).
- **FR-011**: A guard rejection MUST return the taxonomy error as **HTTP** (no SSE stream, no
  `accepted` event), MUST NOT write an `ai_request` row, and MUST NOT call the provider (§6.1
  stages 1–8 vs 9; A6 contract §8; Delivery Plan §3.10 Done when; Delivery Plan §6.4).
- **FR-012**: Admission MUST be exactly one Quota DO round trip per request; settlement MUST credit
  actual usage with one further DO call; the live path MUST NOT add a second DO round trip beyond
  admit + credit (§6.1 stages 8, 15; Delivery Plan §6.4).
- **FR-013**: A repeated idempotency key for the same installation MUST return the prior request's
  state and MUST NOT start a second inference (§6.1 stage 8; Done when).
- **FR-014**: Post-response detail MUST write attempt rows, the usage ledger row, and exactly one R2
  payload envelope per request after the terminal event, and a failure there MUST NEVER fail the
  request (§6.1 stage 16; Delivery Plan §6.4 — no second R2 object).
- **FR-015**: The stream broker on the live path MUST relay normalized chunks, enforce
  provisional-versus-committed emission semantics required by §6.4, and create no per-request
  server-side state (§4.3.10; §6.4).
- **FR-016**: The validated terminal payload MUST be authoritative and self-contained; the live
  path MUST NOT require clients to assemble the final result from chunks (§6.4 invariant 1).
- **FR-017**: The fake adapter path MUST satisfy the CP3 Worker half; real adapters introduced by
  D5/D7 MUST be selected only by routing-policy data, not by rewriting the orchestrator (§6.1 stage
  11; D2; Done when).
- **FR-018**: Partial usage present at cancellation MUST be credited to the Quota DO (§4.3.10; §6.1
  stage 15; Done when).
- **FR-019**: The live orchestrator MUST NOT introduce per-request server-side state of any kind
  (§4.3.10; Delivery Plan §6.4; Done when).
- **FR-020**: Soft-threshold degraded routing is NOT a requirement of this slice; I1 MUST NOT add
  F4 soft-threshold behaviour or assertions (Delivery Plan §3.12.9 I1 after amendment; F4 retains
  soft-threshold).

### Key Entities

Not applicable — this slice defines no entities. It composes existing request-path modules onto the
live Worker route and introduces no new D1 tables or contract types.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: I1 enables a clinic installation to submit an authenticated AI request over the
  live Worker path and receive a streamed, validated result with an auditable request reference —
  without adding microservices, queues, or per-request session infrastructure. Soft-threshold
  economics remain a later hardening slice (F4); I1 only composes what bands A–D already proved.
- **Layer Placement**: Touches **`ai-platform/`** (Cloudflare Worker) only — specifically production
  wiring in `worker.ts` / the request orchestrator that supplies `eventSource`. Does not touch
  `backend/` (Supabase) or `frontend/` (Flutter). Per §14 acknowledgement, the gateway is a
  non-primary, additive component: no domain logic, no business data, no write path into Supabase.
- **Data Integrity & Security**: Authentication, entitlement, admission, and journaling remain the
  contracts frozen by B3, B4, and C3. Guard rejections produce no journal row. Clinical source of
  truth stays in PostgreSQL; this slice writes only platform D1/R2/Quota DO artifacts already
  specified by consumed slices.
- **Failure Handling**: Guard failures return taxonomy errors with no inference. Provider and
  validation failures emit exactly one `failed` terminal event after the request was journaled.
  Disconnect yields `cancelled` with partial-usage credit when present. Stage 16 failures never fail
  the client-visible request. Quota exhaustion disables the additive AI feature path without
  hard-locking clinic workflows (constitution principle V; §6.1 stage 8). Soft-threshold downgrade
  is F4, not I1.

## Out of Scope

- **I2** — Discovery HTTP route and production config-cache readers for every entity kind.
- **I3** — Live Flutter invoke on the first AI feature surface (client half of CP3).
- **I4** — Entitle-and-grant operator path and live `context_required` self-heal.
- **D5 / D7** — Implementing or wiring real provider adapters beyond selection-by-routing-policy;
  I1's CP3 Worker half uses the fake adapter.
- **F4** — Soft-threshold / degraded routing notices and behaviour.
- **H1–H4** — Conversational mode, `context_requested` terminal kind, transcript budgets.
- **J2** — Client `context_required` self-heal (hosted on live submit by I4, not I1).
- **Get-request, usage summary, support lookup, enrollment** HTTP surfaces beyond what the composed
  request path already uses.
- Rewriting `src/pipeline`, the D4 broker, or any Consumes contract beyond the documented A6
  deferred-`accepted` / `preAccept` framing extension (A6 contract §8), which I1 may implement in
  `adapter.ts` as composition work.
- Delivery plan §6.4 prohibitions (must never do):
  - No mechanism from §9.14 added because it looks prudent (R-20).
  - No prompt text, provider name, or model identifier in the Flutter client (R-12).
  - No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
  - No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
  - No per-request server-side state of any kind (§4.4, §9.7).
  - No client-side assembly of a final result from chunks; no committable provisional content
    (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A live `POST /v1/requests` through `SELF.fetch` (or equivalent) with a valid AAT and
  fake-adapter routing completes the §6.1 sequence end to end and ends with exactly one `completed`
  terminal event (Done when; §5.5 rule 4).
- **SC-002**: The happy path writes exactly one `ai_request` before invoke, exactly one R2 envelope
  after the response, and exactly two Quota DO round trips (admit + credit) (Done when; §3.12.9 I1).
- **SC-003**: Each listed guard rejection returns its taxonomy code with **no** `ai_request` row and
  **no** provider call (§3.12.9 I1; FR-011).
- **SC-004**: Repeated idempotency key returns the prior state and starts no second inference
  (Done when).
- **SC-005**: Client disconnect aborts the in-flight provider fetch, terminates as `cancelled`, and
  credits partial usage when present (Done when; §4.3.10).
- **SC-006**: Production `worker.ts` injects `preAccept` and `eventSource`; the live route is not the
  missing-source 503 shell; guard rejects are HTTP with no stream (Done when; §4.3.1; A6 contract §8).
- **SC-007**: No per-request Durable Object or other server-side request state exists on any I1 path;
  provider selection changes only via routing-policy data (Done when; §3.12.9 I1).
- **SC-008**: Soft-threshold / F4 behaviour is absent from the I1 suite and implementation scope
  (Delivery Plan §3.12.9 I1 amendment).

## Assumptions

- Needs slices A6, B3, B4, C1, C2, C3, D1, D2, D3, D4, and D6 are complete and their suites remain
  green; I1 composes them rather than re-implementing them.
- The existing `src/pipeline` composer (`runGuard` / settle) and D4 stream broker are the surfaces
  wired as production `preAccept` + `eventSource` (Delivery Plan §3.10; A6 contract §8).
- A6 adapter framing may be extended in this slice only for deferred `accepted` / `preAccept` as
  documented in A6 contract §8; A6 harness behaviour with omitted `preAccept` remains valid.
- Test environment can exercise `POST /v1/requests` through `SELF.fetch` (or equivalent Workers
  integration harness) with spies on D1, R2, Quota DO, and provider calls.
- Routing-policy fixtures can select the fake adapter for the CP3 Worker half without requiring D5
  or D7 to be implemented in this slice.
- Open Decision 3's capped fail-open grace remains as frozen by B4; I1 does not reopen it.
- Soft-threshold degraded routing stays with F4 after delivery-plan commit `5b910a6f`; I1 neither
  implements nor asserts it.
