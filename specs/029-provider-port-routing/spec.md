# Feature Specification: Provider port, fake adapter, and routing policy

**Feature Branch**: `029-d2-provider-port-routing`

**Created**: 2026-08-01

**Status**: Draft

**Input**: Slice `D2` — "Provider port, fake adapter, and routing policy" (delivery plan §3.5, band D).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.5, row D2):

> §4.3.8, §13.5, §4.3.7, §7.3

### Freezes

Contracts this slice establishes for the first time:

- The **provider port contract**: one adapter per provider translates the canonical inference request to that provider's wire format and normalizes responses, streaming chunks, usage counters, and errors back into the canonical form and the shared error taxonomy; adapters own authentication to the provider, request/response mapping, stream chunk normalization, provider-specific structured-output mechanics, timeouts, and **classification of every failure as retryable or terminal**; adapters own nothing else — no retry decisions, no fallback decisions, no logging policy (§4.3.8). Later slices (D3 invocation, D5/D7 real adapters) implement against this port and must not move retry/fallback into an adapter.
- The **retryable-versus-terminal classification contract**: every failure returned through the port is classified as retryable or terminal; the contract is exhaustive over the error taxonomy — every taxonomy code has exactly one classification for adapter purposes — and the classification is carried on the canonical error (§4.3.8; Consumes A3's canonical error `retryability` field and A2's frozen taxonomy). Later slice D3 retries only adapter-classified retryable failures.
- The **deterministic fake adapter**: a test double behind the same port that produces success, each retryable failure class, each terminal failure class, truncation, and a malformed response, so pipeline and adapter suites need no live provider (§4.3.8, §13.5 Provider adapter tests / Pipeline tests). Later slices D3–D4 and the CP3 walking skeleton run against this fake; D5/D7 replace it with real adapters for their fixture suites.
- The **routing-policy-as-data contract**: a versioned routing policy stored as data (the §7.3 `routing_policy` entity — policy id, version, content pointer, active_from, activated_by), not conditionals in the code path, yields an ordered **candidate chain** of provider+model targets from capability requirements (structured output support, context window, language, latency class), installation overrides, cost class, and — where a soft quota threshold was crossed — a degraded tier; the router records *why* a target was chosen (selection reason) on the request; routing is **stateless** — the chain depends only on the capability, the policy, and this request, with no circuit breaker and no shared provider-health state (§4.3.7, §7.3). Later slices D3 (invocation), D5/D7 (real targets), F4 (soft-threshold signal), and J3 (policy activation) consume this contract and must not consult provider history when building the chain.

### Consumes

Contracts frozen by the slices in `Needs` (A3, A5). Changing any of these is out of scope by definition:

- **From A3 (canonical inference representation)**: the canonical request, stream chunk, result, and error types — including the canonical error's taxonomy code, retryability, provider-native code/message (diagnostics only), and whether the attempt consumed budget — and the rule that nothing upstream of the adapters may contain a provider-shaped field (§5.3). D2's port accepts canonical requests and returns canonical results, chunks, and errors; it does not redefine those shapes.
- **From A2 (via A3)**: the closed error taxonomy and each code's retryability; the classification contract is exhaustive over that set and does not add, remove, or rename codes (§5.4).
- **From A5 (D1 schema)**: the `routing_policy` entity shape — policy id, version, content pointer, active_from, activated_by — and full-history retention (§7.3). D2 interprets policy content and selects chains; it does not alter the entity's columns.
- **From A5 (config cache)**: the warm-isolate config cache that holds the active routing policy among other kinds and serves it with no I/O when warm (§4.3.2, §4.4, §9.15; A5 Freezes). D2's router reads the active policy through that cache contract; it does not reimplement the cache.
- **From A4 / C1 (upstream, not in Needs but supplying router inputs)**: capability requirements that the router filters on — structured output support, context window, language, latency class, degraded-tier policy — are named by §4.3.7 and declared on the manifest's Routing group; D2 receives them as request/capability inputs and does not load or resolve manifests.

### Open decisions relied on

None. D2 defines the provider port, the fake adapter, and routing-policy selection from sections that fully specify the behaviour; no §15 recommended default is assumed. (Open Decision 5's "no per-clinic model preference initially" is consistent with leaving installation overrides as a policy mechanism rather than a product preference UI; D2 does not assume OD-5 beyond what §4.3.7 already names. Open Decision 6's region-aware routing remains deferred.)

## Clarifications

### Session 2026-08-01

- Q: How should the provider port / fake adapter and the routing-policy engine be organised under `ai-platform/src/`? → A: Two sibling modules: `src/provider/` (port + fake) and `src/router/` (policy → candidate chain + `routing_decision`), each with its own test file `[implementation choice — no §citation]`
- Q: How should the deterministic fake adapter be configured to produce success, each failure class, truncation, and malformed outcomes across tests? → A: Constructor takes an ordered queue of scripted outcomes (success / retryable code / terminal code / truncation / malformed); each invoke consumes the next `[implementation choice — no §citation]`
- Q: How should the router unit suite supply the active routing-policy document? → A: Through a fake/spy `ConfigCache` preloaded with the parsed document under `active_routing_policy` `[implementation choice — no §citation]`
- Q: How should T18 (`adapters_own_no_retry_or_fallback`) and T21 (`credentials_absent_from_fake_emissions`) assert their prohibitions? → A: T18: assert the provider-port / fake export surface has no retry or fallback API. T21: assert returned canonical records and any fake-emitted diagnostics carry no credential fields (no logger spy) `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Provider port, fake adapter, and routing policy (Priority: P1)

As the AI Gateway Worker, after the canonical request has been composed (D1), I select an ordered candidate chain of provider+model targets from a versioned routing policy stored as data — filtering by the capability's requirements (structured output support, context window, language, latency class), applying installation overrides and cost class, and using the degraded tier when the request indicates a soft quota threshold was crossed — and I record the selection reason on the request. The chain depends only on the capability, the policy, and this request; a prior provider failure never changes the next request's chain. Behind a single provider port, a deterministic fake adapter produces success, each retryable failure class, each terminal failure class, truncation, and a malformed response, and every failure returned through the port is classified as retryable or terminal exhaustively over the error taxonomy, so later invocation (D3) can retry and fall back uniformly without any adapter owning those decisions.

**Why this priority**: D2 sits where it does because its `Needs` (A3, A5) are the point at which the canonical representation (including the error's retryability field) and the `routing_policy` entity plus config cache exist, and because every later inference-path slice (D3 invocation, D4 stream, D5/D7 real adapters, F4 soft-threshold routing, CP3/CP4) depends on a frozen port and a policy-driven chain rather than provider-shaped conditionals in the pipeline (delivery plan §3.5). Health-based routing and circuit breakers are deliberate deferrals (§4.3.7, §9.14).

**Independent Test**: Provable by a unit suite with no live provider: drive the fake adapter through the provider port for success, each retryable class, each terminal class, truncation, and a malformed response; assert the classification contract is exhaustive over the error taxonomy; drive the router with fixture capability requirements, policy versions, and request inputs and assert chain order, one filtering case per named capability requirement, installation override, identical inputs → identical chain, selection reason recorded, and that a prior failure does not change the next request's chain (delivery plan §3.11.4 row D2; §3.10).

**Acceptance Scenarios**:

1. **Given** the fake adapter configured for success, **When** it is invoked through the provider port with a canonical request, **Then** it returns a canonical result (success). *(fake — success)*
2. **Given** the fake adapter configured for a retryable failure class, **When** it is invoked through the port, **Then** it returns a canonical error classified retryable — one case per retryable class. *(fake — retryable classes)*
3. **Given** the fake adapter configured for a terminal failure class, **When** it is invoked through the port, **Then** it returns a canonical error classified terminal — one case per terminal class. *(fake — terminal classes)*
4. **Given** the fake adapter configured for truncation, **When** it is invoked through the port, **Then** it produces a truncated response outcome. *(fake — truncation)*
5. **Given** the fake adapter configured for a malformed response, **When** it is invoked through the port, **Then** it produces a malformed response outcome. *(fake — malformed)*
6. **Given** the error taxonomy, **When** the classification contract is enumerated, **Then** every taxonomy code is classified exactly once as retryable or terminal for adapter purposes — the contract is exhaustive. *(classification exhaustive)*
7. **Given** a versioned routing policy and capability requirements, **When** the router selects targets, **Then** the candidate chain is ordered by the policy. *(router — chain ordered by policy)*
8. **Given** a capability that requires structured output support, **When** the router filters candidates, **Then** targets that lack structured output support are excluded. *(router — filter structured support)*
9. **Given** a capability that declares a context-window requirement, **When** the router filters candidates, **Then** targets below that context window are excluded. *(router — filter context window)*
10. **Given** a capability that declares a language requirement, **When** the router filters candidates, **Then** targets that do not satisfy that language are excluded. *(router — filter language)*
11. **Given** a capability that declares a latency class, **When** the router filters candidates, **Then** targets outside that latency class are excluded. *(router — filter latency class)*
12. **Given** an installation override in the active routing policy, **When** the router selects targets for that installation, **Then** the override is applied. *(router — installation override)*
13. **Given** identical capability, policy, and request inputs, **When** the router runs twice, **Then** it produces an identical candidate chain. *(router — identical inputs → identical chain)*
14. **Given** a routing selection, **When** the router returns the chain, **Then** the selection reason is present on the routing outcome (`RouterOutcome.routing_decision`). Persistence onto `ai_request.routing_decision` is C3. *(router — selection reason recorded)*
15. **Given** a prior request whose provider attempt failed, **When** a subsequent request with the same capability, policy, and request inputs is routed, **Then** the candidate chain is unchanged — no provider history is consulted. *(router — prior failure does not change next chain)*

### Test plan

Layer: Unit (delivery plan §3.11.4, row D2; §13.5 Provider adapter tests / Pipeline tests with fake provider). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `fake_success` | Unit | Fake produces success (§3.11.4 D2; §13.5) |
| T2 | `fake_retryable_<class>` | Unit | One case per retryable failure class (§3.11.4 D2) |
| T3 | `fake_terminal_<class>` | Unit | One case per terminal failure class (§3.11.4 D2) |
| T4 | `fake_truncation` | Unit | Fake produces truncation (§3.11.4 D2; §13.5 malformed and truncated) |
| T5 | `fake_malformed` | Unit | Fake produces a malformed response (§3.11.4 D2; §13.5) |
| T6 | `classification_exhaustive_over_taxonomy` | Unit | Classification contract exhaustive over the error taxonomy (§3.11.4 D2; §4.3.8) |
| T7 | `router_chain_ordered_by_policy` | Unit | Chain ordered by policy (§3.11.4 D2; §4.3.7) |
| T8 | `router_filter_structured_support` | Unit | Filtering by structured output support (§3.11.4 D2; §4.3.7) |
| T9 | `router_filter_context_window` | Unit | Filtering by context window (§3.11.4 D2; §4.3.7) |
| T10 | `router_filter_language` | Unit | Filtering by language (§3.11.4 D2; §4.3.7) |
| T11 | `router_filter_latency_class` | Unit | Filtering by latency class (§3.11.4 D2; §4.3.7) |
| T12 | `router_installation_override_applied` | Unit | Installation override applied (§3.11.4 D2; §4.3.7) |
| T13 | `router_identical_inputs_identical_chain` | Unit | Identical inputs → identical chain (§3.11.4 D2; §4.3.7) |
| T14 | `router_selection_reason_recorded` | Unit | Selection reason recorded on the request (§3.11.4 D2; §4.3.7) |
| T15 | `router_prior_failure_does_not_change_chain` | Unit | Prior failure does not change the next request's chain (§3.11.4 D2; §4.3.7) |
| T16 | `router_cost_class_applied` | Unit | Cost class participates in selection (§4.3.7; §3.10 branch coverage) |
| T17 | `router_degraded_tier_when_soft_threshold` | Unit | Soft-threshold signal selects the degraded tier from policy (§4.3.7; §3.10 branch coverage; F4 supplies the signal later) |
| T18 | `adapters_own_no_retry_or_fallback` | Unit | Port/adapter surface exposes classification only — no retry or fallback API on the adapter (§4.3.8; §3.10 prohibition) |
| T19 | `routing_policy_is_versioned_data` | Unit | Active policy is read as versioned `routing_policy` data (id, version, content pointer), not code conditionals (§4.3.7, §7.3) |
| T20 | `outgoing_connection_cap_bounds_parallelism` | Unit | Routing policy may not request speculative parallelism beyond the per-request outgoing-connection cap of six (§4.3.8; §3.10 named boundary) |
| T21 | `credentials_absent_from_fake_emissions` | Unit (spy) | Fake/port emissions carry no provider credentials in logs or returned records (§4.3.8; §3.10 inherited prohibition) |

---

### Edge Cases

- **Error codes this slice can emit.** D2 is a unit-level port, fake, and router slice; it is not on the HTTP request path and emits no platform taxonomy response of its own. The fake *produces* classified canonical errors for consumers (D3+); those codes are drawn from the A2 taxonomy via the classification contract, not newly defined here. Exhausting a chain and surfacing `provider_unavailable` is D3, not D2.
- **Retryable vs terminal boundary.** Every failure through the port is classified exactly once; an unclassified failure is a contract violation. Adapters do not decide whether to retry or fall back — they only classify (§4.3.8). D3 owns bounded retry and fallback.
- **Truncation and malformed responses.** Both are required fake outcomes (§3.11.4 D2; §13.5). They are fixture behaviours of the fake, not new taxonomy codes invented by D2; mapping them into the canonical error/result form stays inside the port's normalization duty (§4.3.8).
- **Empty candidate chain after filtering.** §4.3.7 does not define a D2-emitted error for "no target matched". The router may return an empty chain (`chain: []` with all targets in `excluded`); invoking that chain and producing `provider_unavailable` is D3.
- **Document validation failures.** Before interpreting rules, the router requires `document.policy_id` / `document.policy_version` to equal the owning cache row, `schema_version` to be a supported value (currently `1` only), and the last rule to be a catch-all (empty/absent match). Failures throw typed `RoutingPolicyError` with discriminant `code` — not a bare `Error`.
- **Cost-class sources.** Effective class is the lowest of manifest, entitlement cap, and installation `force_cost_class` from the matched **policy-document** override. `defaults.cost_class` is schema-retained for §4.3.7 table parity and does not participate. Equal-class ties resolve by `SOURCE_PRIORITY` (`installation_override` < `entitlement_cap` < `manifest`).
- **Rule `requires` floor.** Targets must satisfy both request requirements and the matched rule's `requires` (stricter floor per dimension).
- **Latency exclusion reason.** Latency-class mismatches are recorded as `feature_unsupported` — the frozen `reason_code` enum has no latency-specific value.
- **Kill switch.** Optional request-context `killedProviderIds` excludes matching providers with `reason_code: kill_switch`.
- **Stateless routing / no health state.** A sick provider is handled by retry and fallback on each request (D3), not by a circuit breaker or shared provider-health store in D2 (§4.3.7). A test asserts a prior failure does not change the next chain (T15).
- **Soft-threshold degraded tier.** The router applies the policy's degraded tier when the request indicates the soft threshold was crossed (§4.3.7). Detecting the threshold crossing and setting that signal is F4 (Needs D2, B4); D2 does not read quota counters.
- **Installation override vs per-clinic preference UI.** Installation overrides are a named routing-policy input (§4.3.7). A product preference surface is out of scope (Open Decision 5); D2 applies overrides present in policy data only — including `force_cost_class`.
- **Outgoing-connection cap of six.** The per-request outgoing-connection cap of six bounds how much speculative parallelism a routing policy may request (§4.3.8). T20 asserts that bound (exact clamp and rule-over-default precedence); the cap value is stated in §4.3.8 and is not invented here.
- **Credentials.** Provider credentials come from the platform's secret store, are never logged, and are never present in the journal (§4.3.8). The fake has no real credentials; real secret-store wiring is D5. D2 still asserts the port/fake emits none (T21).
- **No per-request server-side state.** The router and fake hold no per-request Durable Object or other server-side request state; selection is a pure function of capability, policy, and this request (§4.3.7, §4.4, §9.7).
- **Selection reason storage.** The router records the selection reason on the request (§4.3.7; Done when). D2 asserts the reason is present on the routing outcome; persisting it into D1/R2 is the journal writer's concern (C3) and must not invent a new `ai_request` column in this slice (A5 schema is Consumed).
- **Per-installation policy cache key (J3).** `selectCandidateChain` consults `${policyCacheKey}/${installationId}` before the global key; `preloadRoutingPolicyForInstallation` warms that key. Allowed delivery-plan §2.3 extension; not a second policy store.
## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The provider port MUST translate the canonical inference request to a provider's wire format and normalize responses, streaming chunks, usage counters, and errors back into the canonical form and the shared error taxonomy (§4.3.8).
- **FR-002**: Adapters MUST own authentication to the provider, request/response mapping, stream chunk normalization, provider-specific structured-output mechanics, timeouts, and classification of every failure as retryable or terminal (§4.3.8).
- **FR-003**: Adapters MUST own nothing else — no retry decisions, no fallback decisions, no logging policy — so those behaviours stay uniform across providers (§4.3.8).
- **FR-004**: The retryable-versus-terminal classification contract MUST be exhaustive over the error taxonomy: every taxonomy code has exactly one adapter classification, carried on the canonical error (§4.3.8; Consumes A3/A2).
- **FR-005**: A deterministic fake adapter behind the same port MUST produce success, each retryable failure class, each terminal failure class, truncation, and a malformed response (§4.3.8, §13.5; delivery plan §3.5 Done when / §3.11.4 D2).
- **FR-006**: Provider credentials MUST come from the platform's secret store, MUST never be logged, and MUST never be present in the journal (§4.3.8).
- **FR-007**: The per-request outgoing-connection cap of six MUST bound how much speculative parallelism a routing policy may request (§4.3.8).
- **FR-008**: The provider router MUST select an ordered candidate chain of provider+model targets from routing policy using capability requirements (structured output support, context window, language, latency class), installation overrides, cost class, and — where a soft quota threshold was crossed — a degraded tier (§4.3.7).
- **FR-009**: Routing policy MUST be data, versioned and auditable, not conditionals in the code path; the §7.3 `routing_policy` entity (policy id, version, content pointer, active_from, activated_by) is the versioned store (§4.3.7, §7.3).
- **FR-010**: The router MUST return why a target was chosen as `RouterOutcome.routing_decision` (selection reason). Delivery-plan / §4.3.7 wording "on the request" is satisfied when C3 persists that object onto `ai_request.routing_decision`; D2 freezes the in-memory outcome shape only.
- **FR-011**: Routing MUST be stateless: the chain MUST depend only on the capability, the policy, and this request; there MUST be no circuit breaker and no shared provider-health state (§4.3.7).
- **FR-012**: Identical capability, policy, and request inputs MUST produce an identical candidate chain, and a prior provider failure MUST NOT change the next request's chain (§4.3.7; delivery plan §3.11.4 D2).

### Key Entities

- **Provider port**: The typed boundary every provider adapter implements — async `invoke(CanonicalRequest, options?)` returning a Promise of success/truncation (with ordered `CanonicalStreamChunk` sequence ending in exactly one terminal) or classified error; options name an abort `signal` (deadline remains on the request); owns mapping, normalization, timeouts, and retryable/terminal classification; owns no retry, fallback, or logging policy (§4.3.8).
- **Fake adapter**: A deterministic adapter behind the provider port for tests; produces success, each retryable class, each terminal class, truncation, and malformed response (§13.5).
- **Routing policy (`routing_policy`)**: Versioned target chains and selection rules already shaped by A5 (§7.3); D2 freezes the interpretation that yields an ordered candidate chain and a selection reason from the named inputs in §4.3.7. No new D1 columns are added.
- **Candidate chain**: An ordered list of provider+model targets for one request, plus the selection reason recorded on that request (§4.3.7).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Provider independence and policy-as-data let the platform change models and fall back during an outage without a client release — the property clinics need when they cannot absorb a desktop update for every provider incident (§4.3.7, §4.3.8). No enterprise-scale assumption is introduced: routing is stateless per request, there is no health cluster and no circuit-breaker fabric, and the fake adapter keeps the suite free of live-provider cost at clinic-scale CI (§4.3.7, §13.5).
- **Layer Placement**: This slice touches only **`ai-platform/`** (the Cloudflare Worker). It adds no `backend/` (Supabase) or `frontend/` (Flutter) code. Per the §14 acknowledgement, the gateway is a non-primary, additive component — it holds no domain logic and no business data, has no write path into Supabase, and is always optional. Provider names and model identifiers exist only inside adapters and routing-policy data on the Worker; they must never enter the Flutter client (R-12).
- **Data Integrity & Security**: The router reads the active `routing_policy` through A5's config cache and writes no journal rows; credentials come from the secret store and appear in no log or journal record (§4.3.8, §7.3). Selection reasons are attached to the request for later journaling by C3; D2 does not alter the A5 `ai_request` schema. No clinical data is interpreted by the router or the fake.
- **Failure Handling**: Adapter-classified retryable failures are what D3 will retry; terminal failures are not retried by the platform's attempt loop (§4.3.8). A sick provider is handled by the per-request retry/fallback chain (D3), not by shared health state in D2 (§4.3.7). Soft-threshold degraded routing is applied when the request carries that signal; detecting the threshold is F4. Provider credential or live-provider failure modes for real adapters are D5. This slice's own suite fails closed on an unclassified error (contract violation) and never invents a new taxonomy code.

## Out of Scope

Neighbouring slices this slice touches but does not implement:

- **D1 (prompt registry and composer)**: D2 consumes a canonical request; it does not compose prompts or resolve prompt artifacts (§4.3.6).
- **D3 (invocation with bounded retry and fallback)**: D2 classifies failures and yields the candidate chain; it does not retry, jitter, fall back, journal attempts, emit `provider_unavailable`, or emit a regenerating event (§4.3.7, §8.6, §6.6).
- **D4 (stream broker)**: D2's port normalizes stream chunks at the adapter boundary; relaying, heartbeats, incremental guards, and cancellation are D4 (§4.3.10).
- **D5 / D7 (real provider adapters)**: D2 freezes the port and the fake; wire mapping against recorded live-provider fixtures, secret-store credential wiring, and registering a second provider by policy edit alone are D5/D7 (§4.3.8, §13.5).
- **D6 (response validator and repair)**: Normalization of adapter output into canonical form is D2; schema/business/safety validation and bounded repair are D6 (§4.3.9).
- **C3 (journal writer)**: D2 records the selection reason on the request and produces per-attempt outcomes via the fake; writing `ai_attempt` rows, the R2 envelope, and usage events is C3 (§4.3.11, §7.4).
- **F4 (soft-threshold degraded routing)**: D2's router honours a degraded-tier signal and policy; detecting soft-threshold crossing from quota and setting that signal is F4 (§4.3.3, §8.8).
- **J3 (staged rollout / canary)**: Activating a new routing-policy version for a cohort, promoting, or rolling back by deploy with a `control_audit` row is J3; D2 reads the active policy (§12.4, §7.3).
- **Health-based provider routing / circuit breakers**: Deliberate deferrals under §9.14; not added because they look prudent (R-20) (§4.3.7).

Prohibitions copied from delivery plan §6.4 (inherited by every slice):

- No mechanism from §9.14 added because it looks prudent (R-20). D2 adds no circuit breaker, no shared provider-health store, and no health-based routing.
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — D2 is a Worker slice; provider+model targets exist only in routing-policy data and adapter internals.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — D2 performs no DO and no R2 I/O.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5) — D2 writes no D1 rows on the request path.
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A unit suite proves the fake adapter produces success, each retryable failure class, each terminal failure class, truncation, and a malformed response through the provider port — the full fake clause of `Done when`, each branch a named test (T1–T5).
- **SC-002**: A unit test proves the classification contract is exhaustive over the error taxonomy — every code is classified exactly once as retryable or terminal for adapter purposes (T6; §4.3.8).
- **SC-003**: A unit suite proves the router yields a policy-ordered candidate chain, applies one filtering case per capability requirement (structured support, context window, language, latency class), applies installation overrides, records the selection reason, and produces an identical chain for identical inputs (T7–T14; §4.3.7).
- **SC-004**: A unit test proves a prior provider failure does not change the next request's chain — routing depends only on capability, policy, and this request (T15; §4.3.7; Done when).
- **SC-005**: Unit tests prove cost class and soft-threshold degraded-tier inputs affect selection as §4.3.7 names them, without D2 reading quota counters (T16–T17; §3.10).
- **SC-006**: Unit tests prove adapters expose no retry/fallback API, routing policy is versioned data from `routing_policy`, speculative parallelism is bounded by the outgoing-connection cap of six, and credentials are absent from fake/port emissions (T18–T21; §4.3.7, §4.3.8, §7.3).

## Assumptions

- The canonical inference representation is frozen by A3; D2's port speaks only those types at its boundary and does not redefine them (§5.3).
- The error taxonomy and each code's retryability are frozen by A2; D2's classification contract is exhaustive over that set and adds no code (§5.4).
- The `routing_policy` entity and the config-cache kind that serves the active routing policy are frozen by A5; D2 reads and interprets policy content and does not migrate new columns (§7.3).
- Capability requirements used as router inputs (structured output support, context window, language, latency class, degraded-tier policy) are named in §4.3.7; fixture tests supply them directly without requiring the C1 resolver to run inside this slice's unit suite.
- Soft-threshold *detection* is F4; D2 only applies the degraded tier when the request already carries that signal (§4.3.7).
- Real provider credentials, wire fixtures, and a second live provider are D5/D7; D2's fake is sufficient for D3–D4 and CP3 (§13.5).
- The platform does not ship until the whole product does (DP-1); "independently testable" means provable by an automated unit suite, not demonstrable to a user (DP-3).
