# Implementation Plan: First real provider adapter

**Branch**: `ai/032-d5-first-real-provider-adapter` | **Date**: 2026-08-02 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/032-first-real-provider-adapter/spec.md`

## Summary

Slice D5 freezes the first real provider adapter behind D2's async provider port: one DeepSeek adapter that maps the canonical inference request to DeepSeek's wire format, normalizes streamed chunks onto port `chunks` (exactly one empty-terminal marker), usage counters (`include_usage` / `cached` / `usage_absent`), and failures into the canonical form and shared error taxonomy (retryable vs terminal under D2 classification — HTTP status wins; finish-reason and SSE failure rules below), proves those behaviours against recorded fixtures (including malformed JSON/SSE, truncated `length`/stream-cut, and timeout with abort), measures `provider_ms` around the outbound call, and loads credentials only from the platform secret store (`consumedBudget: false` when the provider was never reached). Fixture transport is buffered (full-body string, post-hoc SSE parse). D5 sits after D2 in band D and is the real-adapter boundary that F1 (evals), D7 (second provider by adapter + policy alone), and CP4 consume.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime, `compatibility_date` 2026-05-03). No new language or runtime version is introduced.

**Primary Dependencies**: The Cloudflare Worker in `ai-platform/` (Wrangler bundler, Vitest). No new external package or provider SDK is added. Outbound HTTP is exercised through an injectable transport/fetch port fed with recorded request/response (or stream) pairs — full response body as one string; post-hoc SSE parse (Clarification Q3; review Deviation 4). Credentials are read through an injectable secret-store binding; credential-absence spies inspect returned canonical errors and captured wire artifacts (Clarification Q4 amended — no adapter logger/journal sinks per D2 repair). Consumes D2's async `ProviderPort` (`chunks`, caller `signal`), classification helpers, and fake (unchanged) plus A3 canonical types via D2.

**Storage**: None. The adapter holds no per-request Durable Object or other server-side request state (§4.3.8; §4.4 / §9.7). Credentials come from the platform secrets binding (§4.4; §13.4), never from D1, R2, config files, or request input. D5 adds no D1 migration, no R2 write, and no Quota DO round trip.

**Testing**: Vitest (`npx vitest run`). All named tests are Adapter fixtures / Provider adapter tests (delivery plan §3.11.4 row D5; §13.5 Provider adapter tests — recorded provider fixtures, including malformed and truncated responses). No live provider egress in the permanent suite. Transport is injected with recorded pairs (Clarification Q3). T8 / T10 / T11 use a fake secret-store binding and assert secret absence from returned errors / wire artifacts; T10 asserts no logger-journal sink surface (Clarification Q4 amended).

**Target Platform**: Cloudflare Worker (`ai-platform-gateway`). No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway component. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase.

**Performance Goals**: Adapter work is in-isolate mapping plus one outbound provider call when wired; this slice's permanent suite uses recorded fixtures with no live egress (delivery plan §3.5 Done when; §3.11.4 D5). No Quota DO round trip, no D1 insert, and no R2 object from this slice (§7.5, §13.6; delivery plan §6.4). Outgoing-connection cap of six remains a D2 router bound — D5 does not raise, bypass, or add speculative fan-out (§4.3.8).

**Constraints**: Adapters own authentication, request/response mapping, stream-chunk normalization (empty terminal), provider-specific structured-output *wire* mechanics, timeouts (remaining-ms `deadline` min'd with `timeoutMs`; caller `signal`), measured `provider_ms`, and retryable/terminal classification — and nothing else: no retry decisions, no fallback decisions, no logging policy / no logger-journal sinks (§4.3.8; D2 repair). No new taxonomy codes (Consumes D2 / A2). Exactly one adapter per provider; a second provider is D7 (FR-009). Credentials never in returned canonical errors or captured wire artifacts; missing key → `consumedBudget: false` (§4.3.8). Pipeline tests continue to use the D2 fake — D5 does not replace or redefine it. No per-request server-side state (§4.4, §9.7). No mechanism from §9.14 (R-20). Provider names and model identifiers never enter the Flutter client (R-12). Fixture harness is buffered (Deviation 4); true byte-streaming is out of scope for this slice.

**Scale/Scope**: One real adapter module under existing `ai-platform/src/provider/` (sibling to port + fake; Clarification Q1–Q2). One §4 component group touched (§4.3.8 — see Components Touched). Eleven named adapter-fixture tests (T1–T11), with T4 expanded to one subcase per DeepSeek wire error class the adapter maps. Roughly 16–20 tasks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — a shared-port real adapter lets clinics survive provider incidents by later adding fallback targets without a client release; fixture-based tests keep CI free of live-provider cost (spec Constitution Alignment → Clinic Fit; DP-3).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — D5 adds one in-isolate adapter module under the existing Worker `src/provider/`; no new deployable, no store, no async orchestration beyond the adapter's owned timeout on the injected transport.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — D5 touches only `ai-platform/`; provider identity stays in adapter internals and routing-policy data, never in the Flutter client (R-12; spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — D5 performs no write to Supabase and adds no D1 schema; journal rows remain C3's concern; the adapter accepts no logger/journal sinks (D2 repair); spies assert credential absence from returned errors / wire artifacts.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — D5 is not inventing auth; credentials come only from the platform secret store and must not appear in returned canonical errors or captured wire artifacts (FR-007, FR-008; Clarification Q4 amended).
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — D5 holds no domain logic and no business data; adapter or provider failure degrades AI features only; clinic workflows continue (spec Constitution Alignment → Failure Handling; A11 / §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. D5 adds no store, no Quota DO / R2 / D1 I/O of its own, and no per-request state; the DeepSeek adapter is a CPU-and-egress mapping module behind the existing D2 async port, proven by recorded fixtures (buffered transport / post-hoc SSE parse).

## Project Structure

### Documentation (this feature)

```text
specs/032-first-real-provider-adapter/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── first-real-provider-adapter.md
        # Frozen DeepSeek adapter duties, recorded-fixture suite shape, secret-store credential path
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`: (1) Architecture context — cites delivery plan §3.5 row D5 and `17-ai-platform.md` §4.3.8; (2) What was implemented — DeepSeek real adapter behind the D2 async port, recorded-fixture suite, secret-store credential path with absence spy; (3) Files to review — this slice's source, fixture, and test files only; (4) Run the automated suite — `npx vitest run test/deepseek-adapter.test.ts` (slice-only, no full-suite `npm test`); (5) Inspect the changes — the frozen contract under `contracts/` and the `provider/deepseek.ts` module; (6) Manual validation omitted — CI is the only verification path (no behaviour beyond CI; permanent suite uses recorded fixtures, not live egress).

`contracts/first-real-provider-adapter.md` freezes the first real (DeepSeek) adapter's duties behind `ProviderPort`, the recorded-fixture suite shape D7 must mirror, secret-store credential path, and review-resolution semantics (stream terminal, SSE failure classes, finish reasons, usage/timing, buffered transport, deadline interpretation). `data-model.md` is not produced — D5 defines no D1 entities (spec Key Entities). `research.md` is not produced — research is `17-ai-platform.md`.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   └── provider/
│       └── deepseek.ts                 # DeepSeekAdapter implements ProviderPort; injectable transport + secret store (FR-001..FR-009)
└── test/
    ├── deepseek-adapter.test.ts        # T1–T11 (adapter fixtures / spy)
    └── fixtures/
        └── deepseek/                   # Recorded request/response and stream pairs for the permanent suite (FR-004, FR-005)
            ├── request-mapping/        # Canonical request → outbound wire golden (T1)
            ├── stream/                 # Provider stream fixtures (T2)
            ├── usage/                  # Usage-bearing responses (T3)
            ├── errors/                 # One recorded failure per mapped provider error class (T4)
            ├── malformed/              # Malformed body (T5)
            ├── truncated/              # Truncated body / finish (T6)
            └── timeout/                # Deadline-exceeded harness input (T7)
```

No `frontend/` or `backend/` tree is shown — D5 touches neither. No migration, no `wrangler.toml` change, and no prompt/asset tree. D2's `port.ts`, `classify.ts`, `fake.ts`, and `router/` are **consumed unchanged** and are not listed as this slice's source tree. Pipeline registration of DeepSeek into the live Worker request path is out of scope for this slice's Done when (fixture suite is the permanent proof).

**Structure Decision**: D5 extends the existing `ai-platform/src/provider/` module (Clarification Q2) with `deepseek.ts` as a sibling to `port.ts` and `fake.ts`, per delivery plan §7.1 and the skill's repository-layout rule. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From D2 — provider port contract (async canonical request in; `chunks` + result or classified error out; caller `signal`; adapters own mapping, normalization, timeouts, and retryable/terminal classification; adapters own no retry, fallback, or logging policy / no logger-journal sinks; classification exhaustive over the error taxonomy) | `ai-platform/src/provider/port.ts` (`ProviderPort`, `ProviderInvokeResult`, `ProviderInvokeOptions`); `ai-platform/src/provider/classify.ts` (`classifyFailure`, `setRetryabilityFromClassification`); frozen in `specs/029-provider-port-routing/contracts/provider-port.md`. D5 implements `DeepSeekAdapter` against this port and does not redefine the port, the taxonomy, or retryability |
| From D2 — deterministic fake adapter remains the pipeline test double | `ai-platform/src/provider/fake.ts` (`FakeAdapter`, `ScriptedOutcome`). D5 does not replace it for pipeline tests and does not change its required outcomes |
| From D2 — routing-policy-as-data contract (versioned policy → ordered candidate chain; selection stateless; outgoing-connection cap of six) | `ai-platform/src/router/index.ts` (`selectCandidateChain`, `RoutingDecision`, `ChainEntry`); frozen in `specs/029-provider-port-routing/contracts/routing-decision.md`. D5 does not change router selection logic, the cap, or policy schema; this slice does not edit policy documents |
| From D2 / A3 (via D2 Consumes) — canonical request, stream chunk, result, and error types (taxonomy code, retryability, provider-native diagnostics); no provider-shaped field upstream of adapters | `ai-platform/src/contracts/canonical.ts` (`CanonicalRequest`, `CanonicalStreamChunk`, `CanonicalResult`, `CanonicalError`, `assertNoProviderShapedFieldNames`, `assertExactlyOneTerminal`); `ai-platform/src/errors.ts` (`TaxonomyCode`, `getTaxonomyEntry`). D5 maps into these types and adds no taxonomy code |

Every **Consumes** entry binds to an existing implementation. None requires modification (stop condition 2 not triggered). Injectable transport and secret-store are adapter constructor dependencies for fixture control (Clarifications Q3–Q4); no logger/journal sinks (D2 repair).

## Components Touched

One §4 component group: **§4.3.8 Provider adapters and egress** — the first real provider adapter behind the provider port (wire mapping, stream normalization, usage extraction, error classification, secret-store credentials, adapter-owned timeouts).

D2's port, fake, classification, and router are **consumed**, not modified. D3 retry/fallback, D4 stream broker, D6 validation/repair, and C3 journal writer are neighbouring slices and are not modified here.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/src/provider/deepseek.ts` | FR-001–FR-009 (DeepSeek adapter behind async `ProviderPort`; owns auth, mapping, stream normalization onto `chunks`, structured-output wire mechanics, timeouts + measured `provider_ms`, classification; owns no retry/fallback/logging policy; credentials from injectable secret store; exactly one real provider in this module) |
| `ai-platform/test/fixtures/deepseek/**` | FR-004, FR-005 (recorded request/response and stream pairs for wire golden, stream, usage, error classes, malformed JSON/SSE, truncated length/stream-cut, timeout) |
| `ai-platform/test/deepseek-adapter.test.ts` | T1–T11 (FR-001–FR-009; injectable transport per Clarification Q3; fake secret store + credential/wire spies per Clarification Q4 amended) |
| `specs/032-first-real-provider-adapter/contracts/first-real-provider-adapter.md` | Freezes → first real adapter duties; recorded-fixture suite shape; secret-store credential path; review-resolution semantics |
| `specs/032-first-real-provider-adapter/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced. D2 modules under Consumes are not modified.

## Test Layout

Per the architecture's testing strategy (§13.5 Provider adapter tests — recorded provider fixtures) and delivery plan §3.11.4 row D5 ("Adapter fixtures"):

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `request_mapping_golden` | Provider adapter tests / Adapter fixtures | `ai-platform/test/deepseek-adapter.test.ts` |
| T2 `stream_normalization` | Provider adapter tests / Adapter fixtures | `ai-platform/test/deepseek-adapter.test.ts` |
| T3 `usage_extraction` | Provider adapter tests / Adapter fixtures | `ai-platform/test/deepseek-adapter.test.ts` |
| T4 `provider_error_class_mapped_to_taxonomy` | Provider adapter tests / Adapter fixtures (one subcase per mapped DeepSeek wire error class) | `ai-platform/test/deepseek-adapter.test.ts` |
| T5 `malformed_response` | Provider adapter tests / Adapter fixtures | `ai-platform/test/deepseek-adapter.test.ts` |
| T6 `truncated_response` | Provider adapter tests / Adapter fixtures | `ai-platform/test/deepseek-adapter.test.ts` |
| T7 `timeout` | Provider adapter tests / Adapter fixtures | `ai-platform/test/deepseek-adapter.test.ts` |
| T8 `credentials_absent_from_logs_and_journal` | Provider adapter tests / Adapter fixtures (spy) | `ai-platform/test/deepseek-adapter.test.ts` |
| T9 `adapter_owns_no_retry_or_fallback` | Provider adapter tests / Adapter fixtures | `ai-platform/test/deepseek-adapter.test.ts` |
| T10 `adapter_owns_no_logging_policy` | Provider adapter tests / Adapter fixtures (spy) | `ai-platform/test/deepseek-adapter.test.ts` |
| T11 `credentials_from_secret_store_only` | Provider adapter tests / Adapter fixtures (spy) | `ai-platform/test/deepseek-adapter.test.ts` |

Every named test in the spec's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). T1–T7 drive the adapter through an injected buffered transport that returns recorded full-body pairs — no live egress; post-hoc SSE parse (Clarification Q3; Deviation 4). T4 expands to one named subcase per DeepSeek wire error class enumerated in `contracts/first-real-provider-adapter.md`, each mapping to an existing `TaxonomyCode` under D2 classification with no new codes (finish-reason / mid-stream / HTTP-status-wins rules included). T8 / T10 / T11 inject a fake secret-store binding and assert the secret was read and never appears in returned canonical errors / captured wire artifacts; T10 asserts no logger-journal sink surface (Clarification Q4 amended). T9 asserts the DeepSeek adapter export surface exposes classification only — no retry or fallback decision API (§4.3.8; §3.10). T2 asserts `assertExactlyOneTerminal` with empty terminal payload; T3 asserts concrete usage counters / `usage_absent`; T6 covers `length` and stream-cut truncation; T7 asserts abort signal fired.

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/first-real-provider-adapter.md` constrains the adapter, fixture suite shape, and secret-store path; later slices (D7, F1) bind to this artifact, not to prose (delivery plan DP-4).
2. **Adapter skeleton + injectable ports + T9, T11.** `DeepSeekAdapter` implements async `ProviderPort`; constructor takes transport/fetch and secret-store ports only (Clarifications Q3–Q4 amended); T11 proves credentials are read from the secret store only; T9 locks no retry/fallback API on the adapter surface.
3. **Request-mapping golden + T1.** Canonical request → DeepSeek wire body/headers match recorded outbound golden (stream requests include `stream_options.include_usage`); Authorization uses the secret-store value without placing it in mapped body fields.
4. **Stream normalization + usage + T2, T3.** Recorded stream fixtures normalize to port `chunks` (exactly one empty terminal; no provider-shaped fields); usage counters / `cached` / `usage_absent` land in canonical form; `provider_ms` measured.
5. **Error classes + malformed + truncated + timeout + T4–T7.** One fixture per mapped wire error class → taxonomy + D2 retryability (HTTP status wins; finish-reason mapping); malformed JSON/SSE → classified failure; truncated `length` / stream-cut → port `truncation`; adapter-owned deadline (remaining-ms) → `timeout` with abort + D2 retryability.
6. **Credential absence + logging-policy prohibition + T8, T10.** Spies assert credentials absent from returned errors / wire artifacts; missing key → `consumedBudget: false`; adapter accepts no logger-journal sinks.
7. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
