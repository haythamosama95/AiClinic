# Implementation Plan: Invocation with bounded retry and fallback

**Branch**: `ai/030-d3-invocation-retry-fallback` | **Date**: 2026-08-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/030-invocation-retry-fallback/spec.md`

## Summary

Slice D3 freezes the platform-internal attempt loop: given D2's ordered candidate chain, the gateway walks targets through the provider port with per-target `max_attempts`, jittered backoff only for adapter-classified retryable failures, attempt-level `selection_reason` values, separate journal feeds per invoke, exhausted-chain `provider_unavailable`, and regenerating/no-splice on fallback after partial streaming. D3 sits after D2 in band D and is the retry/fallback boundary that D4 (stream broker), D5/D7, D6 (`repair_retry`), and CP3 consume.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime, `compatibility_date` 2026-05-03). No new language or runtime version is introduced.

**Primary Dependencies**: The Cloudflare Worker in `ai-platform/` (Wrangler bundler, Vitest). No new external package is added. Consumes D2's `provider/` (port, classify, fake) and `router/` (candidate chain / `routing_decision`) unchanged. Real provider SDKs remain D5/D7.

**Storage**: None. The attempt loop is CPU-only with an in-memory event/attempt sink (Clarification Q4). D3 adds no D1 migration, no R2 write, and no Durable Object round trip. C3's journal write-path is not modified; production later wires the sink to C3 / the stream path.

**Testing**: Vitest (`npx vitest run`). All named tests are Integration (delivery plan §3.11.4 row D3; §13.5 Pipeline tests with fake provider). No live provider, no Cloudflare resource, and no HTTP path. T6 uses a test-only port double/harness; D2's production fake outcome set is unchanged (Clarification Q2).

**Target Platform**: Cloudflare Worker (`ai-platform-gateway`). No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway component. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase.

**Performance Goals**: Invocation is in-isolate only (§8.6, §6.6). No quota DO round trip, no D1 read/write, no R2 object from this slice. I/O budgets in §6.1 / §7.5 / §13.6 are preserved by not introducing any of those calls.

**Constraints**: Retries are platform-internal, bounded, jittered, and only for adapter-classified retryable failures (§6.6). Terminal failures are not retried and do not continue the fallback walk (§6.6; §4.3.7). Fallback walks only the router-supplied chain; no circuit breaker and no shared provider-health state (§4.3.7; §8.6). Never splice providers' text; emit `regenerating` and discard earlier partial text on fallback after streaming (§8.6). Do not emit `repair_retry` (D6). Speculative parallel attempts (`max_parallel_attempts > 1`) are out of scope. No per-request server-side state (§4.4, §9.7).

**Scale/Scope**: One sibling module under `ai-platform/src/` (`invocation/`). One §4 component group touched (§4.3.7 — see Components Touched). Thirteen named integration tests (T1–T13). Roughly 15–20 tasks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — bounded jittered retry and multi-target fallback keep a single provider outage from blocking clinic AI without a health cluster or circuit-breaker fabric (spec Constitution Alignment → Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — D3 adds one in-isolate module to the existing Worker; no new deployable, no store, no async machinery beyond an injectable sleeper.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — D3 touches only `ai-platform/`; provider+model targets stay inside Worker routing/adapter data, never in the Flutter client (R-12; spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — D3 performs no write to any store; attempt records are fed to an in-memory sink for later C3 journaling; A5 schema and C3 timings are not altered.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — D3 is not on the HTTP path; it emits taxonomy outcomes already frozen by A2 (`provider_unavailable` or the adapter's terminal code); credentials stay inside adapters and are not logged by this loop.
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — D3 holds no domain logic and no business data; an exhausted chain yields `provider_unavailable`; AI remains strictly additive (spec Constitution Alignment → Failure Handling).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. D3 adds no store, no DO/R2/D1 I/O, and no per-request state; the attempt loop is a CPU-only module that consumes D2's port and chain and feeds an in-memory sink.

## Project Structure

### Documentation (this feature)

```text
specs/030-invocation-retry-fallback/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── invocation-attempt-loop.md   # Frozen attempt loop, selection_reason, regenerating, journal feed, exhausted-chain outcome
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`: (1) Architecture context — cites delivery plan §3.5 row D3 and `17-ai-platform.md` §4.3.7, §8.6, §6.6; (2) What was implemented — the attempt loop, selection reasons, regenerating/no-splice, exhausted-chain outcome, and per-attempt journal feed; (3) Files to review — this slice's source and test files only; (4) Run the automated suite — `npx vitest run test/invocation.test.ts` (slice-only, no full-suite `npm test`); (5) Inspect the changes — the frozen contract under `contracts/` and the `invocation/` module; (6) Manual validation omitted — CI is the only verification path (no behaviour beyond CI).

`contracts/invocation-attempt-loop.md` freezes the platform-internal attempt loop, attempt-level `selection_reason` values D3 emits, exhausted-chain → `provider_unavailable`, the regenerating/no-splice rule, and the per-attempt journal feed shape. `data-model.md` is not produced — D3 defines no D1 entities and adds no columns (spec Key Entities / Out of Scope C3). `research.md` is not produced — research is `17-ai-platform.md`.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   └── invocation/
│       └── index.ts                    # Attempt loop: walk chain, bounded jittered retry, fallback, regenerating, sink feed (FR-001..FR-011)
└── test/
    └── invocation.test.ts              # T1–T13 (integration against fake + test-only streaming harness)
```

No `frontend/` or `backend/` tree is shown — D3 touches neither. No migration, no `wrangler.toml` change, and no prompt/asset tree — D3 is a pure TypeScript module plus integration tests. D2's `provider/` and `router/` are consumed unchanged and are not listed as this slice's source tree.

**Structure Decision**: D3 extends the `ai-platform/` tree (delivery plan §7.1) with sibling module `src/invocation/` (Clarification Q1), sibling to existing `src/provider/` and `src/router/` it consumes. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From D2 — provider port, deterministic fake adapter, and retryable-versus-terminal classification contract | `ai-platform/src/provider/port.ts` (`ProviderPort`, `ProviderInvokeResult`); `ai-platform/src/provider/fake.ts` (`FakeAdapter`); `ai-platform/src/provider/classify.ts` (`classifyFailure`, `FailureClassification`); frozen in `specs/029-provider-port-routing/contracts/provider-port.md`. D3 retries only classified-retryable failures and does not modify these modules |
| From D2 — ordered candidate chain, request-level `routing_decision`, and stateless chain rule (no circuit breaker / no provider-history) | `ai-platform/src/router/index.ts` — `RoutingDecision`, `ChainEntry`, `selectCandidateChain` / router outcome; frozen in `specs/029-provider-port-routing/contracts/routing-decision.md`. D3 walks the given `chain[]` and does not rebuild, reorder, or consult history |
| From D2 — per-target `max_attempts` and `timeout_ms` on `routing_decision.chain[]` | `ChainEntry.max_attempts` and `ChainEntry.timeout_ms` in `ai-platform/src/router/index.ts` (carried from `rules[].targets[]` per `contracts/routing-decision.md` §4.1–§4.2). D3 reads these bounds off the chain entry; it does not re-interpret policy or invent caps |

Every **Consumes** entry binds to an existing implementation. None requires modification (stop condition 2 not triggered).

## Components Touched

One §4 component group: **§4.3.7 Provider router and policy engine** — specifically the attempt-level walk through the candidate chain and the attempt-level `selection_reason` values on each journaled attempt (the request-level `routing_decision` / chain production remain D2).

§8.6 and §6.6 are cited in Implements as the failure/retry/fallback sequence and the provider-attempts row of the idempotency table; they are not additional §4 components modified by this slice. D2's §4.3.8 port is **consumed**, not modified.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/src/invocation/index.ts` | FR-001–FR-011 (ordered walk; bounded jittered retryable-only retries; terminal no-fallback; selection_reason; `provider_unavailable`; regenerating/no-splice; chain-only fallback; no history/circuit breaker; same-request internal retries; retry budget; no `repair_retry`) |
| `ai-platform/test/invocation.test.ts` | T1–T13 (FR-001–FR-011; includes test-only partial-stream harness per Clarification Q2 and recording sleeper per Clarification Q3) |
| `specs/030-invocation-retry-fallback/contracts/invocation-attempt-loop.md` | Freezes → attempt loop, selection_reason, exhausted-chain outcome, regenerating/no-splice, per-attempt journal feed |
| `specs/030-invocation-retry-fallback/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced.

## Test Layout

Per the architecture's testing strategy (§13.5 Pipeline tests with fake provider) and delivery plan §3.11.4 row D3 ("Integration"):

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `retryable_retried_to_cap_then_fallback` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |
| T2 `terminal_failure_not_retried` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |
| T3 `jitter_applied_on_backoff` | Integration (Pipeline with fake; recording sleeper) | `ai-platform/test/invocation.test.ts` |
| T4 `every_attempt_journaled_separately` | Integration (Pipeline with fake; attempt sink) | `ai-platform/test/invocation.test.ts` |
| T5 `exhausted_chain_provider_unavailable` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |
| T6 `fallback_after_partial_stream_emits_regenerating` | Integration (Pipeline with fake; test-only streaming harness) | `ai-platform/test/invocation.test.ts` |
| T7 `retry_budget_never_exceeded` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |
| T8 `first_attempt_success_no_fallback` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |
| T9 `timeout_exhaustion_fallback_reason` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |
| T10 `fallback_only_walks_given_chain` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |
| T11 `no_provider_history_consulted` | Integration (Pipeline with fake; spy) | `ai-platform/test/invocation.test.ts` |
| T12 `internal_retry_same_request_not_user_retry` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |
| T13 `repair_retry_reason_not_emitted` | Integration (Pipeline with fake) | `ai-platform/test/invocation.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). T3 asserts requested delays across retries are not all identical via an injectable recording sleeper (Clarification Q3). T4/T6 assert on the in-memory event/attempt sink (Clarification Q4). T6's partial-stream path uses a test-only harness; production `FakeAdapter` is unchanged (Clarification Q2). T11 is a spy asserting absence of provider-history / circuit-breaker consultation when choosing the next target.

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/invocation-attempt-loop.md` constrains the module; later slices bind to this artifact, not to prose (delivery plan DP-4).
2. **Invocation module skeleton + sink/sleeper surface + T8.** Happy path: primary success, single attempt, `selection_reason = primary`; establishes the chain → port → sink shape without modifying D2 modules.
3. **Bounded retry + T1, T3, T7, T12.** Same-target retryable retries to `max_attempts`, recording sleeper for jitter, budget never exceeded, same request identity across internal retries.
4. **Fallback walk + T2, T5, T9, T10, T11, T13.** Terminal no-retry/no-fallback; exhausted chain → `provider_unavailable`; timeout → `fallback_after_timeout`; chain-only walk; no history spy; no `repair_retry`.
5. **Per-attempt journal feed + T4.** One sink attempt record per invoke.
6. **Regenerating / no-splice + T6.** Test-only streaming harness yields partial chunks then retryable failure; assert `regenerating`, discarded earlier text, no splice (Clarification Q2).
7. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
