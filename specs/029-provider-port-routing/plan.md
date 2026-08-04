# Implementation Plan: Provider port, fake adapter, and routing policy

**Branch**: `ai/029-d2-provider-port-routing` | **Date**: 2026-08-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/029-provider-port-routing/spec.md`

## Summary

Slice D2 freezes the provider port (canonical in; canonical chunks/result/classified error out), the exhaustive retryable-versus-terminal classification over A2's taxonomy, a deterministic fake adapter for pipeline suites, and routing-policy-as-data selection of an ordered candidate chain with a recorded selection reason — all without live providers, circuit breakers, or provider-health state. D2 sits after A3/A5 (its `Needs`) in band D and is the port+chain boundary that D3 invocation, D5/D7 real adapters, F4 soft-threshold routing, and CP3 consume.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime, `compatibility_date` 2026-05-03). No new language or runtime version is introduced.

**Primary Dependencies**: The Cloudflare Worker in `ai-platform/` (Wrangler bundler, Vitest). No new external package is added. The fake adapter and router are pure in-isolate modules; real provider SDKs are D5/D7.

**Storage**: None at request time. The router reads the active routing policy through A5's warm-isolate config cache (`active_routing_policy` kind) with no I/O when warm (§4.3.2, §4.4). D2 adds no D1 migration, no R2 write, and no Durable Object round trip. The §7.3 `routing_policy` entity columns are Consumed unchanged; policy *content* is interpreted, not stored, by this slice.

**Testing**: Vitest (`npx vitest run`). All named tests are Unit (delivery plan §3.11.4 row D2; §13.5 Provider adapter tests / Pipeline tests with fake provider). No live provider, no Cloudflare resource, and no HTTP path.

**Target Platform**: Cloudflare Worker (`ai-platform-gateway`). No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway component. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase.

**Performance Goals**: Router and fake are CPU-only pure functions of their inputs (§4.3.7, §4.4). No quota DO round trip, no D1 read/write on the request path from this slice, no R2 object. I/O budgets in §6.1 / §7.5 / §13.6 are preserved by not introducing any of those calls.

**Constraints**: Adapters own classification only — no retry, fallback, or logging policy (§4.3.8). Routing is stateless: chain depends only on capability, policy, and this request; no circuit breaker and no shared provider-health state (§4.3.7). Per-request outgoing-connection cap of six bounds speculative parallelism (§4.3.8). Credentials never appear in fake/port emissions (§4.3.8). No per-request server-side state (§4.4, §9.7). Soft-threshold *detection* is F4; D2 only applies the degraded tier when the request already carries that signal.

**Scale/Scope**: Two sibling modules under `ai-platform/src/` (`provider/`, `router/`). Two §4 component groups touched (§4.3.7 and §4.3.8 — see Components Touched). Twenty-one named unit tests (T1–T21). Roughly 20–25 tasks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — routing is stateless per request with no health cluster and no circuit-breaker fabric; the fake keeps CI free of live-provider cost (spec Constitution Alignment → Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — D2 adds two in-isolate modules to the existing Worker; no new deployable, no store, no queue/worker async machinery. The provider port's `invoke` is Promise-based so adapters can await provider I/O on the isolate event loop.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — D2 touches only `ai-platform/`; provider+model targets exist only in routing-policy data and adapter internals, never in the Flutter client (R-12; spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — D2 performs no write to any store; selection reasons are attached to the in-memory request for later journaling by C3; A5's `ai_request` schema is not altered.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — D2 is not on the HTTP path; it emits no platform taxonomy response of its own; credentials come from the secret store and appear in no log or journal record (FR-006; real secret-store wiring is D5).
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — D2 holds no domain logic and no business data; a sick provider is handled by per-request retry/fallback (D3), not shared health state; soft-threshold degraded routing is applied when the request carries that signal (F4 detects); AI remains strictly additive (spec Constitution Alignment → Failure Handling).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. D2 adds no store, no DO/R2/D1 I/O on the request path, and no per-request state; the port and router are CPU-only modules that later slices invoke.

## Project Structure

### Documentation (this feature)

```text
specs/029-provider-port-routing/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    ├── provider-port.md      # Frozen port + classification + fake outcomes (Freezes)
    └── routing-decision.md   # Frozen policy-as-data interpretation + candidate chain + selection reason
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`: (1) Architecture context — cites delivery plan §3.5 row D2 and `17-ai-platform.md` §4.3.8, §4.3.7, §7.3, §13.5; (2) What was implemented — the provider port, fake adapter, classification contract, and routing-policy engine; (3) Files to review — this slice's source and test files only; (4) Run the automated suite — `npx vitest run test/provider-port.test.ts test/router.test.ts` (slice-only, no full-suite `npm test`); (5) Inspect the changes — the frozen contracts under `contracts/` and the `provider/` / `router/` modules; (6) Manual validation omitted — CI is the only verification path (no behaviour beyond CI).

`contracts/provider-port.md` freezes the provider-port surface, the exhaustive retryable/terminal classification over the A2 taxonomy (carried on A3's canonical error `retryability`), and the fake adapter's scripted outcome queue. `contracts/routing-decision.md` freezes the §4.3.7 policy-document interpretation, the ordered candidate chain, and the request-level selection-reason / `routing_decision` object. `data-model.md` is not produced — D2 defines no D1 entities and adds no columns (spec Key Entities / Consumes A5). `research.md` is not produced — research is `17-ai-platform.md`.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── provider/
│   │   ├── port.ts                         # ProviderPort boundary: canonical in → chunks/result/classified error out (FR-001..FR-003)
│   │   ├── classify.ts                     # Exhaustive taxonomy → retryable|terminal for adapter purposes (FR-004)
│   │   └── fake.ts                         # Deterministic fake: ordered scripted-outcome queue (FR-005, FR-006)
│   └── router/
│       └── index.ts                        # Policy → ordered candidate chain + routing_decision; cap of six (FR-007..FR-012)
└── test/
    ├── provider-port.test.ts               # T1–T6, T18, T21
    └── router.test.ts                      # T7–T17, T19, T20
```

No `frontend/` or `backend/` tree is shown — D2 touches neither. No migration, no `wrangler.toml` change, and no prompt/asset tree — D2 is pure TypeScript modules plus unit tests.

**Structure Decision**: D2 extends the `ai-platform/` tree (delivery plan §7.1) with two sibling modules `src/provider/` and `src/router/` (Clarification Q1), siblings to existing `src/contracts/`, `src/config-cache/`, and `src/errors/` modules it consumes. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From A3 — canonical request, stream chunk, result, and error types (including taxonomy code, retryability, provider-native diagnostics, consumed-budget flag); no provider-shaped field upstream of adapters | `ai-platform/src/contracts/canonical.ts` — `CanonicalRequest`, `CanonicalStreamChunk`, `CanonicalResult`, `CanonicalError`, codecs, `assertNoProviderShapedFieldNames`; frozen shapes in `specs/017-ai-canonical-inference/contracts/canonical-shapes.md` |
| From A2 (via A3) — closed error taxonomy and each code's retryability; classification exhaustive over that set | `ai-platform/src/errors.ts` — `TaxonomyCode`, `getTaxonomyEntry`, `isRetrySafe` (adapter classification maps each code to retryable/terminal without adding, removing, or renaming codes) |
| From A5 — `routing_policy` entity shape (policy id, version, content pointer, active_from, activated_by); full-history retention | `ai-platform/migrations/20260731120000_platform_schema.sql` — `routing_policy` table; `specs/019-ai-context-keys-d1-config/data-model.md` §2.5 |
| From A5 — warm-isolate config cache holding `active_routing_policy` among other kinds; no I/O when warm | `ai-platform/src/config-cache/index.ts` — `ConfigCache`, `ConfigEntityKind` including `"active_routing_policy"`, `loadConfig`, `consult` / `remember`; frozen in `specs/019-ai-context-keys-d1-config/contracts/config-cache.md`. Unit suite supplies the parsed policy document via a fake/spy `ConfigCache` preloaded under `active_routing_policy` (Clarification Q3) |
| From A4 / C1 (upstream) — capability requirements named by §4.3.7 (structured output support, context window, language, latency class, degraded-tier policy) | Request/capability fixture inputs in the router unit suite. Manifest Routing group field names exist in `ai-platform/src/manifest/index.ts` (`MANIFEST_FIELD_MANIFEST.Routing`); D2 does not load or resolve manifests |

Every **Consumes** entry binds to an existing implementation. None requires modification (stop condition 2 not triggered).

## Components Touched

Two §4 component groups: **§4.3.8 Provider adapters and egress** (provider port, classification, fake) and **§4.3.7 Provider router and policy engine** (policy-as-data → candidate chain + selection reason).

**Reason for touching both:** Delivery plan §3.5 row D2 Canonical cell names both sections as one slice. D3's `Needs` is D2 alone — invocation consumes both the classified port and the policy-ordered candidate chain in a single dependency. Splitting them would leave either the port without a chain producer or the router without a port for D3/CP3 to drive, forcing a rewrite of the band-D dependency graph. §13.5 and §7.3 are cited in Implements as supporting test-strategy and entity-shape references; they are not additional §4 components modified by this slice.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/src/provider/port.ts` | FR-001, FR-002, FR-003 (typed port boundary; adapter ownership and non-ownership) |
| `ai-platform/src/provider/classify.ts` | FR-004 (exhaustive retryable/terminal classification over the taxonomy) |
| `ai-platform/src/provider/fake.ts` | FR-005, FR-006 (deterministic scripted outcomes; credentials absent from emissions) |
| `ai-platform/src/router/index.ts` | FR-007, FR-008, FR-009, FR-010, FR-011, FR-012 (cap of six; chain selection; policy-as-data; selection reason; stateless identical-inputs determinism) |
| `ai-platform/test/provider-port.test.ts` | T1–T6, T18, T21 (FR-001..FR-006) |
| `ai-platform/test/router.test.ts` | T7–T17, T19, T20 (FR-007..FR-012) |
| `specs/029-provider-port-routing/contracts/provider-port.md` | Freezes → provider port, classification contract, deterministic fake |
| `specs/029-provider-port-routing/contracts/routing-decision.md` | Freezes → routing-policy-as-data, candidate chain, selection reason |
| `specs/029-provider-port-routing/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced.

## Test Layout

Per the architecture's testing strategy (§13.5) and delivery plan §3.11.4 row D2 ("Unit"):

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `fake_success` | Unit (Provider adapter / Pipeline with fake) | `ai-platform/test/provider-port.test.ts` |
| T2 `fake_retryable_<class>` | Unit (Provider adapter) | `ai-platform/test/provider-port.test.ts` |
| T3 `fake_terminal_<class>` | Unit (Provider adapter) | `ai-platform/test/provider-port.test.ts` |
| T4 `fake_truncation` | Unit (Provider adapter) | `ai-platform/test/provider-port.test.ts` |
| T5 `fake_malformed` | Unit (Provider adapter) | `ai-platform/test/provider-port.test.ts` |
| T6 `classification_exhaustive_over_taxonomy` | Unit (Provider adapter / Contract) | `ai-platform/test/provider-port.test.ts` |
| T7 `router_chain_ordered_by_policy` | Unit (Pipeline with fake provider — router) | `ai-platform/test/router.test.ts` |
| T8 `router_filter_structured_support` | Unit | `ai-platform/test/router.test.ts` |
| T9 `router_filter_context_window` | Unit | `ai-platform/test/router.test.ts` |
| T10 `router_filter_language` | Unit | `ai-platform/test/router.test.ts` |
| T11 `router_filter_latency_class` | Unit | `ai-platform/test/router.test.ts` |
| T12 `router_installation_override_applied` | Unit | `ai-platform/test/router.test.ts` |
| T13 `router_identical_inputs_identical_chain` | Unit | `ai-platform/test/router.test.ts` |
| T14 `router_selection_reason_recorded` | Unit | `ai-platform/test/router.test.ts` |
| T15 `router_prior_failure_does_not_change_chain` | Unit | `ai-platform/test/router.test.ts` |
| T16 `router_cost_class_applied` | Unit | `ai-platform/test/router.test.ts` |
| T17 `router_degraded_tier_when_soft_threshold` | Unit | `ai-platform/test/router.test.ts` |
| T18 `adapters_own_no_retry_or_fallback` | Unit | `ai-platform/test/provider-port.test.ts` |
| T19 `routing_policy_is_versioned_data` | Unit | `ai-platform/test/router.test.ts` |
| T20 `outgoing_connection_cap_bounds_parallelism` | Unit | `ai-platform/test/router.test.ts` |
| T21 `credentials_absent_from_fake_emissions` | Unit | `ai-platform/test/provider-port.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). T18 asserts the provider-port / fake export surface has no retry or fallback API (Clarification Q4). T21 asserts returned canonical records and fake-emitted diagnostics carry no credential fields — no logger spy (Clarification Q4). T2/T3 expand to one case per retryable/terminal class derived from the classification contract (FR-004).

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contracts first.** `contracts/provider-port.md` and `contracts/routing-decision.md` constrain the modules; later slices bind to these artifacts, not to prose (delivery plan DP-4).
2. **Classification module + T6.** `classify.ts` exhaustively maps every `TaxonomyCode` to retryable or terminal; T6 locks the contract before the fake can emit classified errors.
3. **Provider port + fake + provider tests (T1–T5, T18, T21).** Port surface and scripted-outcome queue (Clarification Q2) land with success / retryable / terminal / truncation / malformed cases; T18 locks the no-retry/fallback export surface; T21 locks credential absence on returned records.
4. **Router module + router tests (T7–T17, T19, T20).** Policy-as-data selection against a fake/spy `ConfigCache` preloaded with the parsed document under `active_routing_policy` (Clarification Q3); filter cases, override, cost class, degraded tier, selection reason, determinism, prior-failure independence, versioned-data assertion, and the outgoing-connection cap of six.
5. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
