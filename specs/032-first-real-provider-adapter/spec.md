# Feature Specification: First real provider adapter

**Feature Branch**: `ai/032-d5-first-real-provider-adapter`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `D5` — "First real provider adapter" (delivery plan §3.5, band D).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.5, row D5):

> §4.3.8

### Freezes

Contracts this slice establishes for the first time:

- The **first real provider adapter** behind the D2 provider port: one adapter for one real provider that translates the canonical inference request to that provider's wire format and normalizes responses, streaming chunks, usage counters, and errors back into the canonical form and the shared error taxonomy; it owns authentication to the provider, request/response mapping, stream chunk normalization, provider-specific structured-output mechanics, timeouts, and classification of every failure as retryable or terminal, and owns nothing else — no retry decisions, no fallback decisions, no logging policy (§4.3.8). Later slice D7 adds a second adapter against the same port and must not rewrite this adapter's duties or move retry/fallback/logging into either adapter.
- The **recorded-fixture adapter suite** for a real provider: wire-mapping golden, stream normalization, usage extraction, one case per provider error class mapped to the taxonomy, malformed response, truncated response, and timeout, proven against recorded fixtures rather than live egress in the permanent suite (§4.3.8; delivery plan §3.5 Done when; §3.11.4 row D5). D7 must pass the same fixture suite shape against the second provider.
- The **secret-store credential path for a real provider**: provider credentials come from the platform's secret store, are never logged, and are never present in the journal (§4.3.8). D2 stated this rule and asserted absence on the fake; D5 freezes the real binding and the spy that credentials appear in no emitted log or journal record.

### Consumes

Contracts frozen by the slices in `Needs` (D2). Changing any of these is out of scope by definition:

- **From D2 (provider port, fake adapter, and routing policy)**: the **provider port contract** — canonical request in; canonical stream chunks, result, or classified error out; adapters own mapping, normalization, timeouts, and retryable/terminal classification; adapters own no retry, fallback, or logging policy; the classification contract is exhaustive over the error taxonomy (§4.3.8 Freezes in D2). D5 implements one real adapter against this port and does not redefine the port, the taxonomy, or retryability.
- **From D2**: the **deterministic fake adapter** remains the pipeline test double; D5 does not replace it for pipeline tests and does not change its required outcomes (§4.3.8 Freezes in D2).
- **From D2**: the **routing-policy-as-data contract** — versioned policy yields an ordered candidate chain; selection is stateless; the outgoing-connection cap of six bounds speculative parallelism (§4.3.7, §4.3.8 Freezes in D2). D5 does not change router selection logic, the cap, or policy schema; registering targets for this provider in policy data (if needed so a chain can name it) must not alter those contracts.
- **From D2 / A3 (via D2 Consumes)**: the canonical request, stream chunk, result, and error types — including taxonomy code, retryability, and provider-native diagnostics — that the adapter must emit; nothing upstream of adapters may contain a provider-shaped field (§5.3 via D2).

### Open decisions relied on

- **Open Decision 11** (local/on-LAN provider adapter): recommended default is not now. This slice assumes the first real adapter is a remote provider reached with credentials from the platform secret store, not an on-LAN OpenAI-compatible endpoint (§15 OD-11; §4.3.8).
- **Open Decision 5** (per-clinic model or provider preference): recommended default is no initially. This slice does not introduce a per-clinic preference surface; the adapter is a platform component selected by routing policy data alone (§15 OD-5; consistent with D2).

## Clarifications

### Session 2026-08-02

- Q: Which commercial remote provider should the first real adapter target? → A: DeepSeek `[implementation choice — no §citation]`
- Q: Where should the DeepSeek real adapter live under `ai-platform/src/`? → A: Under existing `src/provider/` (sibling to port + fake), e.g. `deepseek.ts` + adapter-fixture tests `[implementation choice — no §citation]`
- Q: How should the adapter-fixture suite drive outbound HTTP so recorded fixtures prove wire mapping without live provider egress? → A: Inject a transport/fetch port; tests feed recorded request/response (or stream) pairs and assert the outbound wire golden `[implementation choice — no §citation]`
- Q: How should T8 / T10 / T11 prove credentials come from the secret store and appear in no emitted log and no journal record? → A: Inject a fake secret-store binding plus recording logger and journal sinks; assert the secret was read from the store and never appears in collected log/journal emissions `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - First real provider adapter (Priority: P1)

As the AI Gateway Worker, after the provider port and fake adapter exist (D2), I run one real provider adapter behind that same port: I map a canonical inference request to the provider's wire format, normalize streamed chunks and the final response into canonical form, extract usage counters, and classify every provider failure as retryable or terminal into the shared error taxonomy. I prove those behaviours against recorded fixtures — including malformed and truncated responses and timeout — and I obtain credentials only from the platform's secret store so that credentials appear in no log line and no journal row.

**Why this priority**: D5 sits where it does because its `Needs` (D2) are the point at which the provider port, the retryable-versus-terminal classification contract, and the fake adapter exist — without those, a real adapter would invent the port or the taxonomy. Later slices F1 (evals against a real adapter), D7 (second provider by adapter and policy alone), and CP4 depend on one real adapter proven by fixtures with secret-store credentials (delivery plan §3.5).

**Independent Test**: Provable by an adapter-fixture suite against recorded responses (no requirement that the permanent suite call a live provider): request-mapping golden; stream normalization; usage extraction; one case per provider error class mapped to the taxonomy; malformed response; truncated response; timeout; credentials absent from every emitted log and journal record (delivery plan §3.11.4 row D5; Done when; §3.10).

**Acceptance Scenarios**:

1. **Given** a canonical inference request fixture and the first real provider adapter, **When** the adapter maps the request to the provider's wire format, **Then** the emitted wire request matches the recorded request-mapping golden for that fixture. *(request-mapping golden)*
2. **Given** a recorded provider stream fixture, **When** the adapter normalizes stream chunks, **Then** every chunk is emitted in the canonical stream-chunk form (no provider-shaped fields at the port boundary). *(stream normalization)*
3. **Given** a recorded provider response that reports usage, **When** the adapter completes normalization, **Then** usage counters are extracted into the canonical usage form. *(usage extraction)*
4. **Given** a recorded provider failure for each provider error class the adapter must map, **When** the adapter classifies the failure, **Then** each class maps to exactly one taxonomy code with the D2 retryable-versus-terminal classification — one acceptance case per class. *(one case per provider error class mapped to the taxonomy)*
5. **Given** a recorded malformed provider response, **When** the adapter handles it, **Then** the outcome is a classified canonical error (or equivalent port-normalized failure) and not an unclassified throw. *(malformed response)*
6. **Given** a recorded truncated provider response, **When** the adapter handles it, **Then** the outcome is normalized into the canonical form required by the port (classified failure or truncated result as the port contract requires) without inventing a new taxonomy code. *(truncated response)*
7. **Given** a recorded or simulated provider deadline exceeded, **When** the adapter's owned timeout path fires, **Then** the failure is classified into the taxonomy as the timeout class with the D2 retryability for that code. *(timeout)*
8. **Given** the adapter invoked with credentials loaded from the platform secret store, **When** it emits any log lines and any journalable records for the attempt, **Then** credentials are absent from every emitted log and every journal record. *(credentials absent from every emitted log and journal record)*

### Test plan

Layer: Provider adapter tests / Adapter fixtures (delivery plan §3.11.4, row D5; §13.5 Provider adapter tests — recorded provider fixtures, including malformed and truncated responses). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `request_mapping_golden` | Adapter fixtures | Canonical request → provider wire format matches golden (§3.11.4 D5; §4.3.8; Done when) |
| T2 | `stream_normalization` | Adapter fixtures | Provider stream chunks normalized to canonical form (§3.11.4 D5; §4.3.8; Done when) |
| T3 | `usage_extraction` | Adapter fixtures | Usage counters extracted into canonical usage (§3.11.4 D5; §4.3.8; Done when) |
| T4 | `provider_error_class_mapped_to_taxonomy` | Adapter fixtures | One case per provider error class mapped to the taxonomy with D2 retryable/terminal classification (§3.11.4 D5; §4.3.8; §3.10 — suite expands to one named subcase per class under the D2 classification contract; no new taxonomy codes) |
| T5 | `malformed_response` | Adapter fixtures | Malformed recorded response → classified/normalized failure (§3.11.4 D5; §4.3.8; Done when) |
| T6 | `truncated_response` | Adapter fixtures | Truncated recorded response → port-normalized outcome (§3.11.4 D5; §4.3.8; Done when) |
| T7 | `timeout` | Adapter fixtures | Adapter-owned timeout / deadline exceeded → taxonomy timeout class (§3.11.4 D5; §4.3.8) |
| T8 | `credentials_absent_from_logs_and_journal` | Adapter fixtures (spy) | Credentials from secret store; absent from every emitted log and journal record (§3.11.4 D5; §4.3.8; Done when) |
| T9 | `adapter_owns_no_retry_or_fallback` | Adapter fixtures | Adapter surface exposes classification only — no retry or fallback decision API (§4.3.8; §3.10 inherited prohibition) |
| T10 | `adapter_owns_no_logging_policy` | Adapter fixtures (spy) | Adapter does not own logging policy; credential and diagnostic emissions still satisfy T8 (§4.3.8; §3.10) |
| T11 | `credentials_from_secret_store_only` | Adapter fixtures (spy) | Authentication credentials are obtained from the platform secret store binding, not from config files or request input (§4.3.8) |

---

### Edge Cases

- **Error codes this slice can emit.** The adapter does not invent taxonomy codes. It maps provider wire failures into the shared error taxonomy under the D2 classification contract (retryable versus terminal). The suite must include one case per provider error class the adapter maps (§3.11.4 D5; §3.10). Exhausting a candidate chain and surfacing `provider_unavailable` remains D3.
- **Malformed response.** A recorded malformed body must not escape as an unclassified exception; it is normalized through the port into a classified canonical error (or the port's required failure form) (§4.3.8; delivery plan §3.11.4 D5).
- **Truncated response.** Truncation is a required fixture outcome (§3.11.4 D5; Done when). Mapping stays inside the port's normalization duty; no new taxonomy code is invented here.
- **Timeout.** Adapters own timeouts (§4.3.8). The timeout case proves deadline exceeded is classified into the taxonomy's timeout class with D2 retryability. This slice does not invent a numeric timeout default beyond what routing-policy `timeout_ms` or the adapter's owned enforcement already requires when invoked through the port.
- **Credentials.** Credentials come only from the platform secret store; they are never logged and never present in the journal (§4.3.8). T8/T11 spy every emission path the adapter uses in the fixture suite.
- **Retry / fallback / logging policy.** The adapter classifies only. Bounded retry, fallback, regenerating, and uniform logging policy remain outside the adapter (D3 / platform telemetry) (§4.3.8).
- **Structured-output mechanics.** The adapter may own provider-specific structured-output wire mechanics (§4.3.8). Pipeline-level structured/`structured_atomic` streaming modes and validation/repair remain D6; this slice does not pull D6 forward.
- **Outgoing-connection cap of six.** Stated in §4.3.8 and frozen by D2 for routing parallelism. D5 does not raise or bypass the cap and does not add speculative fan-out in the adapter.
- **No per-request server-side state.** The adapter holds no per-request Durable Object or other server-side request state; an in-flight call exists only as the open provider connection plus journal rows owned elsewhere (§4.3.8 with §4.4 / §9.7 prohibitions inherited via delivery plan §6.4).
- **Fake adapter coexistence.** Pipeline tests continue to use the D2 fake. D5's fixture suite exercises the real adapter; it does not delete or redefine the fake (Consumes D2).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The first real provider adapter MUST translate the canonical inference request to that provider's wire format and normalize its responses, streaming chunks, usage counters, and errors back into the canonical form and the shared error taxonomy (§4.3.8).
- **FR-002**: The adapter MUST own authentication to the provider, request/response mapping, stream chunk normalization, provider-specific structured-output mechanics, timeouts, and classification of every failure as retryable or terminal (§4.3.8).
- **FR-003**: The adapter MUST own nothing else — no retry decisions, no fallback decisions, no logging policy — so those behaviours stay uniform across providers (§4.3.8).
- **FR-004**: Wire mapping, stream normalization, usage extraction, and error classification MUST pass against recorded fixtures, including malformed and truncated responses (§4.3.8; delivery plan §3.5 Done when; §3.11.4 D5).
- **FR-005**: Every provider error class the adapter maps MUST have exactly one fixture case that maps it into the shared error taxonomy under the D2 retryable-versus-terminal classification contract, without adding taxonomy codes (§4.3.8; delivery plan §3.11.4 D5; Consumes D2).
- **FR-006**: The adapter MUST classify timeout / deadline-exceeded failures into the taxonomy's timeout class consistent with D2 classification (§4.3.8; delivery plan §3.11.4 D5).
- **FR-007**: Provider credentials MUST come from the platform's secret store, MUST never be logged, and MUST never be present in the journal (§4.3.8).
- **FR-008**: Credentials MUST be absent from every emitted log and every journal record produced while exercising the adapter (delivery plan §3.5 Done when; §3.11.4 D5; §4.3.8).
- **FR-009**: There MUST be exactly one adapter per provider; this slice adds the first real provider's adapter and MUST NOT fold a second provider into the same adapter module (§4.3.8; D7 owns the second).

### Key Entities

Not applicable — this slice defines no entities. It implements one real adapter against the provider port and related contracts already frozen by D2 (and A3 via D2).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: A real provider adapter behind a shared port lets the clinic's AI path survive provider incidents by later adding fallback targets without a client release — clinic-scale operations cannot absorb a desktop update for every vendor outage (§4.3.8). Fixture-based adapter tests keep CI free of live-provider cost and flakiness at clinic scale (delivery plan §3.11.4 D5; DP-3).
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker). It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. Provider credentials stay in the Worker's secret store; provider names and model identifiers must never enter the Flutter client (R-12).
- **Data Integrity & Security**: Credentials come from the secret-store binding and appear in no log or journal row (§4.3.8). The adapter does not write clinical data and does not open a write path into Supabase. Journal rows remain C3's concern; this slice only guarantees credential absence from any journalable record it emits into those sinks under test.
- **Failure Handling**: Adapter-classified retryable failures remain what D3 retries; terminal failures are not retried by the platform attempt loop (§4.3.8). Malformed, truncated, and timeout fixtures prove classification without live egress. Provider unavailability of the whole chain remains D3 (`provider_unavailable`). AI remains additive: adapter or provider failure degrades AI features only; clinic workflows continue (A11 / §14).

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **D2 (provider port, fake, routing policy)**: D5 consumes the port and classification contract; it does not redefine them, replace the fake for pipeline tests, or change router selection logic or the outgoing-connection cap of six (§4.3.8 Freezes/Consumes from D2).
- **D3 (invocation with bounded retry and fallback)**: D5 classifies failures; it does not retry, jitter, fall back, journal attempts as the attempt loop, emit `provider_unavailable`, or emit regenerating (§4.3.7, §8.6).
- **D4 (stream broker)**: D5 normalizes chunks at the adapter boundary; relaying to the client, heartbeats, incremental guards, and cancellation are D4 (§4.3.10).
- **D6 (response validator, repair, structured output modes)**: Adapter-owned provider-specific structured-output *wire* mechanics may exist here; schema/business/safety validation, bounded repair, and `structured` / `structured_atomic` broker modes are D6 (§4.3.9).
- **D7 (second provider adapter)**: A second provider, the same fixture suite against it, capability evals, and registration as a low-priority fallback by routing-policy edit alone are D7 (delivery plan §3.5 row D7; §4.3.8).
- **F1 (eval suite harness)**: Golden capability evals and scheduled live smoke against pinned models are F1 (Needs D1, D5); D5 only proves the adapter fixture suite.
- **C3 (journal writer)**: D5 asserts credentials are absent from journal records under spy; writing `ai_attempt` / R2 envelopes is C3 (§4.3.11).
- **J3 (staged rollout / canary)**: Activating a routing-policy version for a cohort is J3.
- **On-LAN / local provider adapter**: Deferred (Open Decision 11 / later band); not this slice.
- **Health-based provider routing / circuit breakers**: Deliberate deferrals under §9.14; not added because they look prudent (R-20).

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — D5 is a Worker slice; provider identity stays in adapter internals and routing-policy data.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — D5 performs no Quota DO and no R2 I/O of its own.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An adapter-fixture suite proves request-mapping golden, stream normalization, and usage extraction against recorded fixtures — the wire-mapping / normalization / usage clause of `Done when` (T1–T3).
- **SC-002**: The suite proves one case per provider error class mapped to the taxonomy under the D2 classification contract, plus malformed response, truncated response, and timeout (T4–T7; §3.11.4 D5; Done when).
- **SC-003**: A spy proves credentials come from the secret store and appear in no emitted log and no journal record (T8, T11; Done when; §4.3.8).
- **SC-004**: Tests prove the adapter owns no retry or fallback decisions and no logging policy (T9–T10; §4.3.8; §3.10).
- **SC-005**: Exactly one real provider adapter is added; a second provider remains absent from this slice's deliverable (FR-009; D7).

## Assumptions

- The provider port and retryable-versus-terminal classification contract are frozen by D2; D5 implements against them and does not amend them (§4.3.8 Freezes in D2).
- The canonical inference types and shared error taxonomy are already frozen (A3/A2 via D2); D5 maps into them and adds no code (§5.3 / §5.4 via Consumes).
- Which commercial remote provider is "first" is not named in §4.3.8 or the delivery plan row; the adapter duties and fixture suite are fully specified without that product pick. Selecting among architecture-permitted remote providers is an implementation choice for the clarify stage, not a licence to invent port fields or taxonomy codes.
- Recorded fixtures (not live egress) are the permanent proof for this slice's suite (delivery plan §3.5 Done when; §3.11.4 D5; DP-3).
- Secret-store bindings for provider credentials exist as part of the Worker environment model (A1 / §4.4 secrets binding); D5 wires the first real adapter to that binding and does not invent a second credential store.
- The platform does not ship until the whole product does (DP-1); "independently testable" means provable by an automated fixture suite, not demonstrable to a user (DP-3).
- Open Decision 11's default (no on-LAN adapter now) and Open Decision 5's default (no per-clinic preference initially) hold for this slice (§15).
