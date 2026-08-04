# Implementation Plan: Second provider adapter

**Branch**: `ai/034-d7-second-provider-adapter` | **Date**: 2026-08-02 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/034-second-provider-adapter/spec.md`

## Summary

Slice D7 freezes the second real provider adapter (Gemini) behind the same D2 provider port already used by D5: one adapter that maps the canonical inference request to Gemini's wire format (wire-mapping floor in contract §2.7), normalizes streamed chunks onto port `chunks` (exactly one empty-terminal marker), usage counters (`cached` / `usage_absent`), and failures into the canonical form and shared error taxonomy, proves the full D5 recorded-fixture suite shape against Gemini (including malformed JSON/SSE, truncated `MAX_TOKENS`/stream-cut, timeout with abort, and credential-absence spies with `consumedBudget: false`), and registers Gemini as a low-priority fallback target by a routing-policy data edit alone — with no inference-pipeline change — so fallback ordering is honoured at router output + wiring constructibility (contract §2.9). Fixture transport is buffered (full-body string, post-hoc SSE parse — contract §2.6); deadline is remaining-ms (contract §2.5). D7 sits after D5 in band D. F1 has landed; live-smoke targets `gemini-1.5-flash`; golden-eval inclusion of Gemini remains the permanent proof path for the CP4 eval half (contract §5.3). Review resolution aligned `gemini.ts` patterns with D5/DeepSeek, added fixtures, and strengthened tests — architecture docs untouched.

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime, `compatibility_date` 2026-05-03). No new language or runtime version is introduced.

**Primary Dependencies**: The Cloudflare Worker in `ai-platform/` (Wrangler bundler, Vitest). No new external package or provider SDK is added. Outbound HTTP is exercised through an injectable transport/fetch port fed with recorded request/response (or stream) pairs — full response body as one string; post-hoc SSE parse (Clarification Q6; contract §2.6). Credentials are read through an injectable secret-store binding; credential-absence spies inspect returned canonical errors and captured wire artifacts (no adapter logger/journal sinks per D2 repair). Consumes D5's DeepSeek adapter / fixture-suite shape / secret-store path (unchanged), D2's async `ProviderPort` (`chunks`, caller `signal`) / classification / routing-policy-as-data (unchanged), A3 canonical types via those slices, and F1 eval harness (`specs/039-eval-suite-harness/`, `ai-platform/test/eval/`).

**Storage**: None. The adapter holds no per-request Durable Object or other server-side request state (§4.3.8; §4.4 / §9.7). Credentials come from the platform secrets binding (§4.4; §13.4), never from D1, R2, config files, or request input. D7 adds no D1 migration, no R2 write, and no Quota DO round trip. Routing-policy registration is a versioned **data** document under the D2 contract, not a schema change.

**Testing**: Vitest (`npx vitest run`). Named tests T1–T11 are Adapter fixtures / Provider adapter tests (delivery plan §3.11.4 row D7 ← D5; §13.5 Provider adapter tests) — review resolution strengthened empty terminal, exact usage/`cached`, malformed SSE, truncated SSE, abort signal, `consumedBudget: false`. T13 is Adapter fixtures + policy / structural (path allowlist). T14 is Unit (router + policy). T12 capability-eval clause is unblocked by F1; live-smoke covers `gemini-1.5-flash`; golden-eval inclusion remains the permanent proof path (contract §5.3). No live provider egress in the adapter-fixture suite.

**Target Platform**: Cloudflare Worker (`ai-platform-gateway`). No `frontend/` (Flutter) or `backend/` (Supabase) code is touched.

**Project Type**: Additive, non-primary AI gateway component. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase.

**Performance Goals**: Adapter work is in-isolate mapping plus one outbound provider call when wired; this slice's permanent suite uses recorded fixtures with no live egress (delivery plan §3.5 Done when adapter/fixture/policy half; §3.11.4 D7). No Quota DO round trip, no D1 insert, and no R2 object from this slice (§7.5, §13.6; delivery plan §6.4). Outgoing-connection cap of six remains a D2 router bound — D7 does not raise, bypass, or add speculative fan-out (§4.3.8).

**Constraints**: Adapters own authentication, request/response mapping (wire-mapping floor — contract §2.7), stream-chunk normalization (empty terminal), provider-specific structured-output *wire* mechanics, timeouts (remaining-ms `deadline` min'd with `timeoutMs`; caller `signal` — contract §2.5), measured `provider_ms`, and retryable/terminal classification — and nothing else: no retry decisions, no fallback decisions, no logging policy / no logger-journal sinks (§4.3.8; D2 repair). No new taxonomy codes (Consumes D2 / D5). Exactly one adapter per provider; Gemini is a separate module and MUST NOT be folded into `deepseek.ts` (FR-004; Consumes D5). Credentials never in returned canonical errors or captured wire artifacts; missing key → `consumedBudget: false` (§4.3.8). Registration as low-priority fallback is a routing-policy *data* edit with no change to invocation, retry/fallback, stream broker, validator, or journal pipeline modules (FR-011; Clarification Q3); wiring map hand-off and model pin per contract §2.8–§2.9. FR-010 / T12 / SC-005 unblocked by F1; golden-eval inclusion is the permanent proof path. Fixture harness is buffered (contract §2.6). No per-request server-side state (§4.4, §9.7). No mechanism from §9.14 (R-20). Provider names and model identifiers never enter the Flutter client (R-12). Open Decision 11 (no on-LAN adapter now) and Open Decision 5 (no per-clinic preference initially) hold. Architecture docs not amended.

**Scale/Scope**: One real Gemini adapter module under existing `ai-platform/src/provider/` (sibling to port, fake, and DeepSeek; Clarification Q2). One §4 component group touched (§4.3.8 — see Components Touched). Thirteen named tests in this slice's Test plan (T1–T11, T13, T14); T12 deferred. Roughly 18–22 tasks.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — a second shared-port adapter registered by policy data alone lets clinics survive a primary-provider incident without a client release or pipeline rewrite; fixture-based tests keep CI free of live-provider cost (spec Constitution Alignment → Clinic Fit; DP-3; CP4 with F1).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — D7 adds one in-isolate adapter module (plus policy data and an optional thin provider wiring map) under the existing Worker; no new deployable, no store, no async orchestration beyond the adapter's owned timeout on the injected transport.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — D7 touches only `ai-platform/`; provider identity stays in adapter internals and routing-policy data, never in the Flutter client (R-12; spec Constitution Alignment → Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — D7 performs no write to Supabase and adds no D1 schema; journal rows remain C3's concern; this slice only spies that credentials are absent from any journalable record it emits under test.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — D7 is not inventing auth; credentials come only from the platform secret store, are never logged, and are never present in the journal (FR-008, FR-009).
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — D7 holds no domain logic and no business data; adapter or provider failure degrades AI features only; clinic workflows continue (spec Constitution Alignment → Failure Handling; A11 / §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. D7 adds no store, no Quota DO / R2 / D1 I/O of its own, and no per-request state; the Gemini adapter is a CPU-and-egress mapping module behind the existing D2 port, proven by recorded fixtures, with policy-data registration for fallback ordering.

## Project Structure

### Documentation (this feature)

```text
specs/034-second-provider-adapter/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
├── quickstart.md        # Written during the Documentation task after implementation/verification
└── contracts/
    └── second-provider-adapter.md
        # Frozen Gemini adapter duties, D5 suite shape applied to second provider,
        # secret-store path, and policy-data registration / independence proof (adapter half)
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`: (1) Architecture context — cites delivery plan §3.5 row D7 and `17-ai-platform.md` §4.3.8 / §13.5; (2) What was implemented — Gemini real adapter behind the D2 port, recorded-fixture suite (full D5 case list), secret-store credential path with absence spy, routing-policy low-priority registration with no pipeline diff, fallback ordering; note F1 landed and capability-eval permanent proof path; (3) Files to review — this slice's source, fixture, policy-data, and test files only; (4) Run the automated suite — slice-only `npx vitest run` against this slice's test files (no full-suite `npm test`); (5) Inspect the changes — the frozen contract under `contracts/` and the `provider/gemini.ts` module plus policy data; (6) Manual validation omitted — CI is the only verification path (no behaviour beyond CI; permanent suite uses recorded fixtures, not live egress).

`contracts/second-provider-adapter.md` freezes the second real (Gemini) adapter's duties behind `ProviderPort`, the recorded-fixture suite shape mirrored from D5, the secret-store credential path, the routing-policy data registration / no-pipeline-diff independence proof, and review-resolution semantics (deadline §2.5, buffered transport §2.6, wire-mapping floor §2.7, model identity §2.8, wiring map hand-off §2.9; stream/SSE/usage/credentials; F1 capability-eval clause §5.3). `data-model.md` is not produced — D7 defines no D1 entities (spec Key Entities). `research.md` is not produced — research is `17-ai-platform.md`.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   └── provider/
│       ├── gemini.ts                   # GeminiAdapter implements ProviderPort; injectable transport + secret store (FR-001..FR-009); review resolution aligned with D5 patterns
│       └── wiring.ts                   # Thin provider_id → adapter wiring map (DeepSeek + Gemini); allowlisted under FR-011 / T13 — not pipeline; constructibility hand-off (§2.9)
├── control/
│   └── routing-policy/
│       └── platform-default/
│           └── 1.json                  # Versioned routing-policy document listing Gemini as low-priority fallback (FR-011, FR-012)
└── test/
    ├── gemini-adapter.test.ts          # T1–T11 (adapter fixtures / spy; strengthened asserts)
    ├── second-provider-policy.test.ts  # T13 (structural allowlist) + T14 (fallback ordering)
    └── fixtures/
        └── gemini/                     # Recorded request/response and stream pairs (FR-005, FR-006, FR-007); review-resolution fixtures added
            ├── request-mapping/        # Canonical request → outbound wire golden (T1)
            ├── stream/                 # Provider stream fixtures (T2)
            ├── usage/                  # Usage-bearing responses (T3)
            ├── errors/                 # One recorded failure per mapped Gemini wire error class (T4)
            ├── malformed/              # Malformed body + SSE (T5)
            ├── truncated/              # Truncated body / finish + stream-cut (T6)
            └── timeout/                # Deadline-exceeded harness input (T7)
```

No `frontend/` or `backend/` tree is shown — D7 touches neither. No migration and no prompt/asset tree. D5's `deepseek.ts`, D2's `port.ts` / `classify.ts` / `fake.ts` / `router/`, and pipeline modules (invocation, stream broker, validator, journal) are **consumed unchanged** and are not listed as this slice's modified source. `wrangler.toml` may gain a second secrets-binding *name* documentation comment only if required to name `GEMINI_API_KEY`; production secret values are never committed.

**Structure Decision**: D7 extends the existing `ai-platform/src/provider/` module (Clarification Q2) with `gemini.ts` as a sibling to `port.ts`, `fake.ts`, and `deepseek.ts`, per delivery plan §7.1 and the skill's repository-layout rule. Routing-policy registration is a data document under `ai-platform/control/routing-policy/` matching the D2 `content_pointer` convention. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| From D5 — first real provider adapter; recorded-fixture adapter suite shape; secret-store credential path | `ai-platform/src/provider/deepseek.ts` (`DeepSeekAdapter`, injectable transport / `SecretStorePort`); `ai-platform/test/deepseek-adapter.test.ts` + `ai-platform/test/fixtures/deepseek/`; frozen in `specs/032-first-real-provider-adapter/contracts/first-real-provider-adapter.md`. D7 mirrors the suite shape for Gemini and does **not** rewrite DeepSeek's adapter, suite contract, or secret-store binding rules (Clarification Q6: duplicate inject pattern in D7 tests if helpers are not already shared) |
| From D5 / D2 — provider port contract (canonical request in; canonical stream chunks, result, or classified error out; adapters own mapping, normalization, timeouts, and retryable/terminal classification; adapters own no retry, fallback, or logging policy; classification exhaustive over the error taxonomy) | `ai-platform/src/provider/port.ts` (`ProviderPort`, `ProviderInvokeResult`); `ai-platform/src/provider/classify.ts` (`classifyFailure`, `setRetryabilityFromClassification`); frozen in `specs/029-provider-port-routing/contracts/provider-port.md`. D7 implements `GeminiAdapter` against this port and does not redefine the port, the taxonomy, or retryability |
| From D5 / D2 — routing-policy-as-data contract (versioned policy → ordered candidate chain; selection stateless; selection reason recorded; outgoing-connection cap of six) | `ai-platform/src/router/index.ts` (`selectCandidateChain`, `RoutingDecision`, `ChainEntry`); frozen in `specs/029-provider-port-routing/contracts/routing-decision.md`. D7 registers Gemini by editing policy **data** only and does not alter router selection logic, the cap, or policy schema meaning |
| From D5 / D2 / A3 — canonical request, stream chunk, result, and error types (taxonomy code, retryability, provider-native diagnostics); no provider-shaped field upstream of adapters | `ai-platform/src/contracts/canonical.ts` (`CanonicalRequest`, `CanonicalStreamChunk`, `CanonicalResult`, `CanonicalError`, `assertNoProviderShapedFieldNames`); `ai-platform/src/errors.ts` (`TaxonomyCode`, `getTaxonomyEntry`). D7 maps into these types and adds no taxonomy code |
| From F1 — capability eval harness | `specs/039-eval-suite-harness/`; `ai-platform/test/eval/` (incl. live-smoke targeting `gemini-1.5-flash`). Golden-eval inclusion of Gemini remains the permanent proof path for FR-010 / T12 / SC-005 (contract §5.3) |

Every **Consumes** entry binds to an existing implementation. None requires modification (stop condition 2 not triggered). The F1 capability-eval clause is **unblocked** by F1 presence — golden-eval inclusion is the permanent proof path; architecture is not amended.

## Components Touched

One §4 component group: **§4.3.8 Provider adapters and egress** — the second real provider adapter behind the provider port (wire mapping, stream normalization, usage extraction, error classification, secret-store credentials, adapter-owned timeouts), plus the thin provider wiring map that registers the new adapter by `provider_id` without touching pipeline stages.

D2's port, fake, classification, and router are **consumed**, not modified. Routing-policy registration is a **data** edit under the Consumed §4.3.7 routing-policy-as-data contract; the router module itself is unchanged. D3 retry/fallback, D4 stream broker, D6 validation/repair, and C3 journal writer are neighbouring slices and are not modified here. F1 eval harness is consumed for the capability-eval clause.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/src/provider/gemini.ts` | FR-001–FR-009 (Gemini adapter behind `ProviderPort`; owns auth, mapping, stream normalization, structured-output wire mechanics, timeouts, classification; owns no retry/fallback/logging policy; credentials from injectable secret store; separate module from DeepSeek — FR-004; review resolution aligned with D5/DeepSeek patterns) |
| `ai-platform/src/provider/wiring.ts` | FR-011 (thin `provider_id` → adapter wiring for DeepSeek + Gemini; allowlisted with adapter + policy data under T13; constructibility hand-off — contract §2.9; does not change invocation / retry-fallback / stream-broker / validator / journal) |
| `ai-platform/control/routing-policy/platform-default/1.json` | FR-011, FR-012 (versioned policy document listing Gemini as a low-priority fallback after higher-priority targets; `model_id` decorative vs adapter pin — contract §2.8) |
| `ai-platform/test/fixtures/gemini/**` | FR-005, FR-006, FR-007 (recorded request/response and stream pairs for wire golden, stream, usage, error classes, malformed JSON/SSE, truncated finish/stream-cut, timeout; review-resolution fixtures added) |
| `ai-platform/test/gemini-adapter.test.ts` | T1–T11 (FR-001–FR-009; injectable buffered transport duplicating D5 inject pattern; strengthened asserts; fake secret store) |
| `ai-platform/test/second-provider-policy.test.ts` | T13 (FR-011 structural allowlist), T14 (FR-012 fallback ordering via unchanged `selectCandidateChain`) |
| `specs/034-second-provider-adapter/contracts/second-provider-adapter.md` | Freezes → second real adapter duties; D5 suite shape applied to second provider; secret-store path; policy-data registration / independence proof; review-resolution semantics (§2.5–§2.9, §3.2–§3.6, §5.3) |
| `specs/034-second-provider-adapter/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or a Freezes entry. No untraced file is introduced. Consumed D5/D2/A3 modules are not modified.

## Test Layout

Per the architecture's testing strategy (§13.5 Provider adapter tests — recorded provider fixtures) and delivery plan §3.11.4 row D7 ("Adapter fixtures + evals"):

| Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- |
| T1 `second_provider_request_mapping_golden` | Provider adapter tests / Adapter fixtures | `ai-platform/test/gemini-adapter.test.ts` |
| T2 `second_provider_stream_normalization` | Provider adapter tests / Adapter fixtures | `ai-platform/test/gemini-adapter.test.ts` |
| T3 `second_provider_usage_extraction` | Provider adapter tests / Adapter fixtures | `ai-platform/test/gemini-adapter.test.ts` |
| T4 `second_provider_error_class_mapped_to_taxonomy` | Provider adapter tests / Adapter fixtures (one subcase per mapped Gemini wire error class) | `ai-platform/test/gemini-adapter.test.ts` |
| T5 `second_provider_malformed_response` | Provider adapter tests / Adapter fixtures | `ai-platform/test/gemini-adapter.test.ts` |
| T6 `second_provider_truncated_response` | Provider adapter tests / Adapter fixtures | `ai-platform/test/gemini-adapter.test.ts` |
| T7 `second_provider_timeout` | Provider adapter tests / Adapter fixtures | `ai-platform/test/gemini-adapter.test.ts` |
| T8 `second_provider_credentials_absent_from_logs_and_journal` | Provider adapter tests / Adapter fixtures (spy) | `ai-platform/test/gemini-adapter.test.ts` |
| T9 `second_adapter_owns_no_retry_or_fallback` | Provider adapter tests / Adapter fixtures | `ai-platform/test/gemini-adapter.test.ts` |
| T10 `second_adapter_owns_no_logging_policy` | Provider adapter tests / Adapter fixtures (spy) | `ai-platform/test/gemini-adapter.test.ts` |
| T11 `second_provider_credentials_from_secret_store_only` | Provider adapter tests / Adapter fixtures (spy) | `ai-platform/test/gemini-adapter.test.ts` |
| T12 `capability_evals_pass_with_second_provider` | Capability evals (A9) / CI | F1 harness under `ai-platform/test/eval/` — unblocked; live-smoke covers `gemini-1.5-flash`; golden-eval inclusion permanent proof (contract §5.3) |
| T13 `added_by_routing_policy_edit_no_pipeline_diff` | Adapter fixtures + policy / structural | `ai-platform/test/second-provider-policy.test.ts` |
| T14 `fallback_ordering_honoured` | Unit (router + policy) | `ai-platform/test/second-provider-policy.test.ts` |

Every named test in this slice's Test plan is placed in a §13.5 layer (stop condition 3 not triggered). T12 is tracked as the F1 capability-eval clause (unblocked; permanent proof = golden-eval inclusion).

T1–T7 drive the adapter through an injected buffered transport that returns recorded full-body pairs — no live egress; post-hoc SSE parse (Clarification Q6; contract §2.6). T4 expands to one named subcase per Gemini wire error class enumerated in `contracts/second-provider-adapter.md`, each mapping to an existing `TaxonomyCode` under D2 classification with no new codes. T8 / T10 / T11 inject a fake secret-store binding and assert the secret was read and never appears in returned canonical errors / captured wire artifacts; T10 asserts no logger-journal sink surface. T9 asserts the Gemini adapter export surface exposes classification only. T2 asserts `assertExactlyOneTerminal` with empty terminal payload; T3 asserts concrete usage counters / `cached` / `usage_absent`; T5 covers malformed JSON/SSE; T6 covers `MAX_TOKENS` and stream-cut; T7 asserts abort signal fired. T13 asserts a structural path allowlist: only second-adapter + routing-policy data (+ provider wiring map) may be required; fails if invocation / retry-fallback / stream-broker / validator / journal pipeline modules must change (Clarification Q3). T14 drives unchanged `selectCandidateChain` with the versioned policy document and asserts Gemini appears after higher-priority targets with selection reason recorded (router output + wiring constructibility — contract §2.9).

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). The order within the slice:

1. **Frozen contract first.** `contracts/second-provider-adapter.md` constrains the Gemini adapter, suite shape, secret-store path, and policy-registration proof (incl. review-resolution §2.5–§2.9); later slices (F1 closing the eval half, F5) bind to this artifact, not to prose (delivery plan DP-4).
2. **Adapter skeleton + injectable ports + T9, T11.** `GeminiAdapter` implements `ProviderPort`; constructor takes transport/fetch and secret-store ports (duplicate D5 inject pattern; Clarification Q6); T11 proves credentials are read from the secret store only; T9 locks no retry/fallback API on the adapter surface.
3. **Request-mapping golden + T1.** Canonical request → Gemini wire body/headers match recorded outbound golden (wire-mapping floor §2.7); auth uses the secret-store value without placing it in mapped body fields.
4. **Stream normalization + usage + T2, T3.** Recorded stream fixtures normalize to port `chunks` (empty terminal; no provider-shaped fields); usage counters / `cached` / `usage_absent` land in canonical form.
5. **Error classes + malformed + truncated + timeout + T4–T7.** One fixture per mapped wire error class → taxonomy + D2 retryability; malformed JSON/SSE → classified failure; truncated `MAX_TOKENS` / stream-cut → port `truncation`; adapter-owned deadline (remaining-ms) → `timeout` with abort + D2 retryability.
6. **Credential absence + logging-policy prohibition + T8, T10.** Spy asserts credentials absent from returned errors / wire; missing key → `consumedBudget: false`; adapter does not own logging policy.
7. **Policy data + wiring map + T13, T14.** Versioned routing-policy document lists Gemini as low-priority fallback; thin wiring map registers the adapter by `provider_id`; T13 proves structural allowlist (no pipeline module change); T14 proves ordered chain and recorded selection reason via unchanged router.
8. **Quickstart.** `quickstart.md` is written last, after the suite is green, documenting only this slice's files and commands — including the F1 capability-eval permanent proof note.

## Review resolution (2026-08-04)

Review-resolution file changes (architecture docs untouched):

- `ai-platform/src/provider/gemini.ts` — patterns aligned with D5/DeepSeek (async invoke, empty terminal, SSE malformed/truncation, abort on timeout, measured `provider_ms`, `consumedBudget: false`, wire-mapping floor).
- Fixtures added/strengthened under `ai-platform/test/fixtures/gemini/` (malformed SSE, truncated stream-cut, usage-absent, mapping-floor cases as needed).
- Tests strengthened in `ai-platform/test/gemini-adapter.test.ts` (empty terminal; exact usage + `cached`; malformed SSE; truncated SSE; abort signal; `consumedBudget: false`).
- Spec Kit: contract §2.5 (deadline), §2.6 (buffered transport), §2.7 (wire mapping floor), §2.8 (model identity), §2.9 (wiring map hand-off), §5.3 (F1 capability-eval clause); `spec.md` / `plan.md` / `tasks.md` synced.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
