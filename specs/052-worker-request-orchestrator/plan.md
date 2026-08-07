# Implementation Plan: Worker request orchestrator on `POST /v1/requests` (I1)

**Branch**: `ai/052-i1-worker-request-orchestrator` | **Date**: 2026-08-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/052-worker-request-orchestrator/spec.md`

## Summary

I1 wires the already-frozen §6.1 pipeline onto the live Cloudflare Worker `POST /v1/requests` route: `worker.ts` supplies a production `preAccept` gate (`runGuard` through stage 9 journal) and a post-accept `eventSource` (route/invoke → D4 broker → D6 validate/repair → terminal → settle) to the A6 protocol adapter, and `adapter.ts` implements A6 contract §8 so `accepted` is deferred until the gate succeeds (taxonomy HTTP, no SSE, no journal on pre-accept failure). I1 sits first in Band I, reifies CP2 on live HTTP, and is the Worker half of CP3; it freezes no new contract and leaves soft-threshold / F4 out of scope.

## Technical Context

**Language/Version**: TypeScript 5.9 on the Cloudflare Workers runtime (`compatibility_date` 2026-05-03); Node ≥ 22 for tooling (`ai-platform/package.json`).

**Primary Dependencies**: Existing `ai-platform/` Worker stack (Wrangler ~4.86, Vitest ~3.2 with `@cloudflare/vitest-pool-workers` 0.8). No new external package. Composes A6 `handleAdapterRequest` (extended for §8 `preAccept`), `src/pipeline` `runGuard` / settle surfaces, D4 `createStreamBroker` / `createStructuredStreamBroker`, D2/D3 router + `runInvocation` + FakeAdapter, D6 `validateAndRepair`, and C3 journal/credit/detail modules without rewriting their published behaviour.

**Storage**: No new D1 entities, migrations, or R2 layout. Live path uses existing Quota DO (admit + credit), one `ai_request` D1 insert (stage 9), and exactly one R2 payload envelope (stage 16) already frozen by B4/C3. No per-request Durable Object or other server-side request state (§4.3.10; delivery plan §6.4).

**Testing**: Workers integration (spy) via `@cloudflare/vitest-pool-workers` and `SELF.fetch` (or equivalent) against the live Worker (`vitest.workers.config.ts`). Named tests T1–T23 assert behaviour and absence of work (journal / provider / DO / R2 spies) per Delivery Plan §3.11 / §3.12.9 row I1. Slice-only command: `npx vitest run --config vitest.workers.config.ts test/worker-request-orchestrator.test.ts`. Soft-threshold / F4 cases are not asserted.

**Target Platform**: Cloudflare Worker (`ai-platform-gateway`) in `ai-platform/` only. No `frontend/` or `backend/` changes.

**Project Type**: Additive, non-primary AI gateway component. Per the §14 acknowledgement: the Worker holds no domain logic, no business data, and no write path into Supabase.

**Performance Goals**: Guard stages 1–10 complete with exactly two I/O operations in the common case — one Quota DO admission and one D1 journal insert — before the stream opens and before any provider call (§6.1; FR-003). Settlement adds exactly one further DO credit call; exactly one R2 envelope after the terminal event; no second DO or R2 object per request (§7.5, §13.6; FR-012, FR-014).

**Constraints**: Freezes **None** — composition only (Delivery Plan §3.10; §2.3). A6 contract §§1–7 are consumed unchanged; I1 may extend framing only via documented §8 (`preAccept` / deferred `accepted`) in `adapter.ts`. `src/pipeline` and D4 broker modules are not rewritten. Guard rejections are taxonomy **HTTP** (no SSE, no `accepted`, no `ai_request` row). Exactly one terminal SSE event on every accepted stream. Connection-scoped cancel only. Soft-threshold / F4 behaviour is out of scope (FR-020). No §9.14 mechanism added because it looks prudent (R-20). No parallel HTTP path that bypasses the adapter.

**Scale/Scope**: Two production source files modified (`adapter.ts`, `worker.ts`), one new Workers-integration test file, `vitest.workers.config.ts` include entry, and this directory's `quickstart.md`. Twenty-three named Workers integration (spy) tests (T1–T23). Roughly 18–24 tasks — within the ~25-task sizing guidance. One §4 component group modified (§4.3.1 for §8); remaining §4 surfaces are consumed by composition only (see Components Touched).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified — I1 composes the existing request path onto live HTTP without Session DOs, queues, or per-request state clinics would have to operate (spec Constitution Alignment → Clinic Fit; §4.3.10; §9.7).
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service — production wiring inside the single existing Worker; no new deployable, store, or pipeline stage (Delivery Plan §3.10; Freezes None).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — I1 touches only `ai-platform/`; no Flutter or Supabase write path (spec Layer Placement; §14).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions — I1 writes only platform D1/R2/Quota DO artifacts already specified by consumed slices; clinical source of truth stays in PostgreSQL (spec Data Integrity & Security).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving — live path runs B3 identity/entitlement/rate-limit and B4 admission unchanged; guard rejects leave no journal row; accepted requests are auditable from stage 9 (FR-010, FR-011).
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable — gateway remains additive; provisional chunks are never authoritative (FR-016); soft-threshold economics stay F4 (FR-020); quota exhaustion disables the AI path without hard-locking clinic workflows (constitution principle V).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase. I1 adds production composition only — deferred-`accepted` framing per A6 §8 and live `preAccept` / `eventSource` wiring — and introduces no new store or contract.

## Project Structure

### Documentation (this feature)

```text
specs/052-worker-request-orchestrator/
├── spec.md              # Authoritative feature spec (input)
├── plan.md              # This file
└── quickstart.md        # Written during the Documentation task after implementation/verification
```

`quickstart.md` will contain, per `.specify/templates/ai-platform-quickstart-template.md`: (1) Architecture context — cites delivery plan §3.10 row I1 and `01-ai-platform.md` §6.1 stages 1–16, §4.3.1, §4.3.10, §5.5, §6.4; (2) What was implemented — live `preAccept` + `eventSource` wiring, A6 §8 deferred `accepted` in `adapter.ts`; (3) Files to review — this slice's source and test files only; (4) Run the automated suite — `npx vitest run --config vitest.workers.config.ts test/worker-request-orchestrator.test.ts` (slice-only, no full-suite `npm test`); (5) Inspect the changes — `worker.ts` production injectors and `adapter.ts` §8 gate; (6) Manual validation omitted — CI / Workers integration suite is the verification path.

`data-model.md` is not produced — I1 defines no D1 entities (spec Key Entities). `contracts/` is not produced — Freezes **None**; later slices bind to prior frozen artifacts (including A6 `sse-framing.md` §8), not to a new I1 wire contract. `research.md` is not produced — research is `01-ai-platform.md`.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── adapter.ts       # A6 framing + §8 pre-stream accept gate (deferred accepted / taxonomy HTTP) (FR-001, FR-004, FR-006, FR-011)
│   └── worker.ts        # Production preAccept (runGuard→stage 9) + eventSource (broker/settle) on POST /v1/requests (FR-001–FR-019)
├── test/
│   └── worker-request-orchestrator.test.ts   # T1–T23 Workers integration (spy) via SELF.fetch
└── vitest.workers.config.ts                  # Include the I1 workers-pool test file
```

No `frontend/` or `backend/` tree is shown — I1 touches neither. No migration, no new D1/R2 schema, no new frozen contract file. Consumed modules (`pipeline/`, `stream/`, `invocation/`, `router/`, `validate/`, `journal/`, `provider/fake.ts`, identity/entitlement/rate-limit/admission/capability/context/prompt, …) remain in place and are not listed as this slice's deliverables.

**Structure Decision**: I1 extends the existing `ai-platform/` Worker tree (delivery plan §7.1) by production composition in `worker.ts` and the documented A6 §8 framing extension in `adapter.ts`. The Spec Kit template's `frontend/`/`backend/` conventions are deleted as unused, per the skill's repository-layout rule.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| **From A6** — request parsing, ingress size limits, headers, SSE framing, taxonomy→HTTP, `accepted`, heartbeats, one-terminal, cancel, injected `eventSource`, optional `preAccept` (contract §8) | `ai-platform/src/adapter.ts` (`handleAdapterRequest`, `HandleAdapterRequestOptions`, `AdapterEventSourceFactory`, `INGRESS_BODY_SIZE_LIMIT`, SSE encode helpers); frozen in `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md` (§§1–7 consumed; **§8 implemented by I1** in `adapter.ts` as allowed composition — not a Consumes violation and not a new frozen contract). Omitted `preAccept` preserves A6 harness behaviour. Taxonomy HTTP uses A2 `buildErrorBody` / `liveHttpStatusForCode` (`ai-platform/src/errors.ts`). |
| **From B3** — identity / principal / rate-limit / entitlement / kill-switch; guard rejects never journaled | `ai-platform/src/identity/index.ts` (`TokenVerifier`, `EnrolledKeyVerifier`, `Principal`); `ai-platform/src/entitlement/index.ts` (`evaluateEntitlement`); `ai-platform/src/rate-limit/index.ts` (`checkRateLimit`); composed inside `runGuard` (`ai-platform/src/pipeline/index.ts`). Contracts: `specs/023-guard-stages/contracts/token-verifier.md`, `request-principal.md`. |
| **From B4** — one Quota DO admit; separate credit; idempotency prior state; capped fail-open grace (OD-3) | `ai-platform/src/admission/index.ts` (`runAdmission`); `ai-platform/src/quota-do/index.ts`; `ai-platform/src/credit/index.ts` (`creditUsage`); invoked from `runGuard` (stage 8) and settle (stage 15). Contract: `specs/024-quota-do-admission/contracts/quota-do-rpc.md`. |
| **From C1** — capability resolve; unknown / retired / disabled | `ai-platform/src/capability/index.ts` (`resolve`); `ai-platform/src/manifest/index.ts`. Contract: `specs/025-capability-resolver-discovery/contracts/capability-registry.md`. |
| **From C2** — context validate + cost pre-flight | `ai-platform/src/context/validator.ts` (`validateContext`); `ai-platform/src/context/preflight.ts` (`runCostPreflight`). Contract: `specs/026-context-validator-cost-preflight/contracts/context-validator.md`. |
| **From C3** — stage 9 journal insert; stage 15 terminal + credit; stage 16 detail + one R2 envelope; no journal on guard reject | `ai-platform/src/journal/index.ts` (`createRequestRow`, `recordTerminalState`, `writePostResponseDetail`). Contract: `specs/027-journal-writer-get-request/contracts/journal.md`. |
| **From D1** — prompt composition from pinned artifacts | `ai-platform/src/prompt/composer.ts` (`composeRequest`); `ai-platform/src/prompt/registry.ts`. Contract: `specs/028-prompt-registry-composer/contracts/composer-output.md`. Injected into `runGuard` as `ComposeRequestFn`. |
| **From D2** — provider port, FakeAdapter, routing-policy candidate chain | `ai-platform/src/provider/port.ts` (`ProviderPort`); `ai-platform/src/provider/fake.ts` (`FakeAdapter`); `ai-platform/src/router/index.ts` (`selectCandidateChain`); `ai-platform/src/provider/wiring.ts` (real adapters selected only when policy says so). Contracts: `specs/029-provider-port-routing/contracts/provider-port.md`, `routing-decision.md`. |
| **From D3** — bounded retry / fallback invocation | `ai-platform/src/invocation/index.ts` (`runInvocation`). Contract: `specs/030-invocation-retry-fallback/contracts/invocation-attempt-loop.md`. |
| **From D4** — stream broker, heartbeats, disconnect abort, `cancelled`, partial-usage credit, no per-request state | `ai-platform/src/stream/index.ts` (`createStreamBroker`, `createChunkSourceFromInvocationEvents`); `ai-platform/src/stream/structured.ts` (`createStructuredStreamBroker` when mode requires it). Contract: `specs/031-stream-broker/contracts/stream-broker.md`. |
| **From D6** — validate / repair; `validation_failed`; authoritative terminal payload | `ai-platform/src/validate/index.ts` (`validateAndRepair`); `ai-platform/src/validate/phases.ts`. Contract: `specs/033-response-validator/contracts/response-validator.md`. |
| **Pipeline composer (spec Consumes closing paragraph)** — `runGuard` as `preAccept`; broker / settle as `eventSource` | `ai-platform/src/pipeline/index.ts` (`runGuard`, `GuardResult`, `settleHappyPath` settle surfaces). **Not rewritten** — live `worker.ts` supplies `preAccept` → `runGuard` through stage 9; `eventSource` composes D2–D4/D6 + C3 settle after accept. Soft-threshold helpers already present in pipeline remain untouched for F4 (FR-020). |

Every **Consumes** entry binds to an existing implementation. Modifying `adapter.ts` solely to implement A6 contract **§8** is the documented Band I composition extension (escalation resolution (a); delivery plan §3.10 Useful to know) — **not** stop condition 2. No parallel HTTP path bypasses the adapter.

## Components Touched

One §4 component group is **modified**:

- **§4.3.1 Protocol adapter** — implement A6 contract §8 pre-stream accept gate in `ai-platform/src/adapter.ts`: optional `preAccept` on `HandleAdapterRequestOptions`; defer SSE open + `accepted` until `{ ok: true }`; on `{ ok: false, code }` return A2 taxonomy HTTP (no stream, no `accepted`, no `eventSource` call); omitted `preAccept` preserves A6 harness behaviour.

Production wiring in `worker.ts` **composes** (does not modify) the frozen modules for §4.3.2–§4.3.11 / §4.3.9–§4.3.10 already delivered by B3–D6. §4.3.10 Stream broker is **consumed** via `createStreamBroker` / structured broker as the post-accept `eventSource` body — not rewritten. §5.5 / §6.1 / §6.4 are contracts realised by that composition, not additional §4 components edited by this slice.

**Why only one modified component:** Band I freezes no new contract and must not rewrite Consumes modules (Delivery Plan §3.10; §2.3). The only allowed source change outside `worker.ts` is the documented A6 §8 framing extension.

## Files

| File | FRs traced |
| --- | --- |
| `ai-platform/src/adapter.ts` | FR-001, FR-004, FR-006, FR-011 — §8 `preAccept` gate; deferred `accepted`; taxonomy HTTP on pre-accept failure; omitted gate = A6 harness path |
| `ai-platform/src/worker.ts` | FR-001–FR-019 — supply production `preAccept` (`runGuard` through stage 9) + `eventSource` (concurrent route/invoke/broker/validate/terminal; settle credit+R2 only after `completed`); live `POST /v1/requests` composition; I/O budgets; idempotency; cancel via immediate broker disconnect; request-scoped accept handoff (no module-global per-request store); provider selection via routing policy; no F4 soft-threshold |
| `ai-platform/test/worker-request-orchestrator.test.ts` | T1–T23 (FR-001–FR-020 coverage via Workers integration spy) |
| `ai-platform/vitest.workers.config.ts` | Register I1 test file in the workers pool so `SELF.fetch` exercises production `worker.ts` |
| `specs/052-worker-request-orchestrator/quickstart.md` | Documentation task (written after implementation/verification) |

Every file traces to an FR or the Test plan. No untraced file. No new `contracts/` artifact (Freezes None). `src/pipeline` and `src/stream` are not Files rows — consumed unchanged.

## Test Layout

Per architecture §13.5 (Pipeline tests with fake provider) and Delivery Plan §3.12.9 row I1 ("Workers integration (spy)"):

| Named test (spec Test plan) | Layer (§13.5 / delivery plan) | File |
| --- | --- | --- |
| T1 `live_post_happy_path_accepted_stream_completed` | Workers integration (spy) | `ai-platform/test/worker-request-orchestrator.test.ts` |
| T2 `ai_request_written_before_invoke` | Workers integration (spy) | same |
| T3 `one_r2_envelope_after_response` | Workers integration (spy) | same |
| T4 `exactly_two_do_round_trips_admit_and_credit` | Workers integration (spy) | same |
| T5 `guard_reject_unauthenticated_no_journal_no_provider` | Workers integration (spy) | same |
| T6 `guard_reject_rate_limited_no_journal_no_provider` | Workers integration (spy) | same |
| T7 `guard_reject_forbidden_capability_no_journal_no_provider` | Workers integration (spy) | same |
| T8 `guard_reject_capability_unknown_no_journal_no_provider` | Workers integration (spy) | same |
| T9 `guard_reject_capability_retired_no_journal_no_provider` | Workers integration (spy) | same |
| T10 `guard_reject_capability_disabled_no_journal_no_provider` | Workers integration (spy) | same |
| T11 `guard_reject_context_required_no_journal_no_provider` | Workers integration (spy) | same |
| T12 `guard_reject_context_invalid_no_journal_no_provider` | Workers integration (spy) | same |
| T13 `guard_reject_request_too_large_no_journal_no_provider` | Workers integration (spy) | same |
| T14 `guard_reject_quota_exhausted_no_journal_no_provider` | Workers integration (spy) | same |
| T15 `idempotency_repeat_returns_prior_no_second_inference` | Workers integration (spy) | same |
| T16 `cancel_disconnect_aborts_cancelled_credits_partial` | Workers integration (spy) | same |
| T17 `no_per_request_server_side_state` | Workers integration (spy) | same |
| T18 `provider_selection_only_via_routing_policy` | Workers integration (spy) | same |
| T19 `guard_reject_installation_suspended_no_journal_no_provider` | Workers integration (spy) | same |
| T20 `post_guard_failed_terminal_provider_unavailable` | Workers integration (spy) | same |
| T21 `post_guard_failed_terminal_validation_failed` | Workers integration (spy) | same |
| T22 `exactly_one_terminal_event_on_every_live_path` | Workers integration (spy) | same |
| T23 `worker_supplies_production_event_source` | Workers integration (spy) | same |

Every named test in the spec's Test plan is placed in a §13.5 / delivery-plan Workers integration (spy) layer (stop condition 3 not triggered). Guard-reject cases assert taxonomy **HTTP** (no SSE / no `accepted`), no journal, no provider (A6 §8). Happy-path and post-guard cases assert deferred `accepted` after stage 9, then exactly one terminal. Soft-threshold / F4 is absent from this suite (FR-020).

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule). Order within the slice:

1. **Adapter §8 gate + A6-regression check.** Extend `HandleAdapterRequestOptions` with optional `preAccept`; defer SSE/`accepted` until success; taxonomy HTTP on failure; confirm omitted `preAccept` still matches A6 harness behaviour (existing `adapter` suites remain green — not rewritten).
2. **T23 + T5 skeleton.** Prove production `worker.ts` injects non-null `preAccept` + `eventSource`, and one guard reject returns HTTP with no stream (establishes the composition spine).
3. **`preAccept` → `runGuard` through stage 9.** Wire identity/config/bindings from the Worker env; map `GuardFailure` → `{ ok: false, code }`; map fresh success → `{ ok: true }` with accepted context for `eventSource`; handle `GuardIdempotentSuccess` without a second inference (T15).
4. **Guard-reject matrix T5–T14, T19.** One Workers integration case per live pre-stage-9 taxonomy code; spies prove no journal and no provider.
5. **`eventSource` happy path T1–T4.** Post-accept: route via policy → FakeAdapter (CP3 Worker half) → D4 broker relay → D6 validate → one `completed` → credit + one R2 envelope; assert one journal before invoke and exactly two DO trips.
6. **Post-guard failure + one-terminal T20–T22.** Exhausted invocation → `provider_unavailable` as one `failed`; validation exhaustion → `validation_failed` as one `failed`; every live path ends with exactly one terminal.
7. **Cancel + invariants T16–T18.** Disconnect aborts fetch, `cancelled`, partial credit when present; no per-request server-side state; adapter selection changes only via routing-policy data.
8. **Quickstart.** `quickstart.md` last, after the suite is green, documenting only this slice's files and commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
