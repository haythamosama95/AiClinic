# Implementation Plan: Quota Durable Object and admission stage (B4)

**Branch**: `ai/024-b4-quota-do-admission` | **Date**: 2026-07-31 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/024-quota-do-admission/spec.md`

## Summary

Slice B4 implements the platform's only stateful side-car — the per-installation Quota Durable Object
— and the pipeline's stage-8 admission call and stage-15 credit call that use it. One admission round
trip answers `jti` freshness, idempotency novelty, remaining budget, and concurrency headroom at once;
a separate credit call settles actual usage (including partial usage on cancellation) after the request.
Ephemeral `jti` replay and idempotency records expire in place inside the object; Quota DO unavailability
is served under the capped fail-open grace policy Open Decision 3 names, with later reconciliation.

B4 is sequenced after A5 and B3 (its `Needs`) and precedes C3: admission is the last word before the
journal writer's stage 9 sits where a request stops being a candidate and starts being work.

## Technical Context

**Language/Version**: TypeScript on Cloudflare Workers (Workers runtime, `cloudflare:workers` DO); Vitest
under `@cloudflare/vitest-pool-workers`.

**Primary Dependencies**: `cloudflare:workers` `DurableObject` base; the existing `ConfigCache` /
`D1Reader` seam from A5 (`ai-platform/src/config-cache/index.ts`); the verified `Principal` from B3
(`ai-platform/src/entitlement/index.ts`); the parsed idempotency-key header and `TaxonomyCode` from
A6 / A2 (`ai-platform/src/adapter.ts`, `ai-platform/src/errors.ts`).

**Storage**: The Quota Durable Object only — the per-installation instance holds the entitlement
snapshot (read-only, supplied by A5's `ConfigCache`), the period counters, and the in-flight count, plus
the in-object ephemeral `jti` replay set and idempotency records. No D1 writes, no R2 writes, no D1
tables are introduced by this slice (§4.4; §7.7 `ephemeral`; §9.17). D1's only read on the hot path is
the one A5 already pays on a cold isolate; on a warm isolate admission adds no D1 read (§4.3.2; A5
`Freezes`). Admission rejections are tallied to `platform_counter` rows whose shape B3 froze — B4 reuses
that bucketing discipline and adds no new counter shape.

**Testing**: `npx vitest run` under `vitest.workers.config.ts` against the real Miniflare Durable
Object binding (`env.DO`) for the DO unit + concurrency cases, and an injected counting spy around
`env.QUOTA_DO` for the one-fetch-per-request and grace-reconciliation integration (spy) cases
(§3.11.2 row B4 layer "DO unit + concurrency + integration (spy)"; Clarification Q3, Q4).

**Target Platform**: Cloudflare Workers + Durable Objects (per-installation instances via
`env.DO.idFromName(installationId)`); clinic LAN for the Worker's callers.

**Project Type**: AI gateway, additive non-primary component (§14).

**Performance Goals**: The guard must complete in low tens of milliseconds with exactly two I/O
operations in the common case — one Durable Object round trip (admission) and one D1 insert (stage 9,
C3's, not here) (§6.1). The credit call is one additional DO round trip at stage 15 (post-response);
no third DO round trip exists (§7.5; §13.6).

**Constraints**: One Quota Durable Object round trip per request at admission; one credit call per
request lifecycle; no pre-flight reservations against estimated cost; no per-request server-side state;
no second R2 object per request (§4.3.3; §4.4; §7.5; §13.6; delivery plan §6.4). The Quota DO never
writes to the clinic database (§14).

**Scale/Scope**: One Durable Object instance per installation; serialized counting at clinic volumes
(§4.4); the ephemeral store is bounded by the `ephemeral` retention horizon (§7.7).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — one DO instance
      per installation, serialized counting, no queues, no second metrics store (§4.3.3; §4.4; §14 I).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one Durable Object class, no per-request state,
      mechanisms left out by §9.14 are not added here (§4.4; §14 I; delivery plan §6.4 R-20).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — B4 touches
      `ai-platform/` only; the Worker is a non-primary additive component with no domain logic, no
      business data, and no write path into Supabase (§14 acknowledgement; delivery plan §7.1).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — admission has already been
      authenticated, entitled, rate-limited, and kill-switch-checked by B3; the Quota DO never writes
      to the clinic database or to the clinic Supabase (§4.3.3; §14 III).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — admission is installation-scoped (one DO instance per
      installation), so two isolated Worker invocations cannot double-spend a budget or replay a `jti`;
      the `jti` replay set is bounded by the ephemeral horizon and never leaves the object (§4.3.3;
      §4.4; §7.7).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — quota exhaustion disables
      an additive feature and never hard-locks a clinical workflow (constitution V; §14 V; §8.8); Quota
      DO unavailability fails open under a capped grace allowance so an infrastructure blip does not
      block care (§15 #3; R-15).

## Project Structure

### Documentation (this feature)

```text
specs/024-quota-do-admission/
├── plan.md              # This file
├── quickstart.md        # Filled during the Documentation task after verification
├── contracts/
│   └── quota-do-rpc.md  # The admission RPC and the credit RPC wire shapes (Freezes → wire shape)
└── tasks.md             # Produced by /ai-platform-tasks (not this phase)
```

`data-model.md` is **not** produced — this slice defines no D1 entity and writes no D1 schema; it
reads `installation` / `installation_key` / `entitlement` through the config cache frozen by A5 and
writes only bucketed `platform_counter` rows whose shape B3 froze (spec § Key Entities).
`research.md` is **not** produced — the research is `docs/architecture/17-ai-platform.md`, and redoing
it is how architecture drift starts. `contracts/quota-do-rpc.md` **is** produced: the spec's
`## Slice Contract → Freezes` lists the admission and credit RPCs as contracts this slice establishes
for the first time, and a later slice's **Consumes** must bind to a frozen artifact (the two RPC message
shapes plus the in-object ephemeral entry shape), not to prose.

`quickstart.md` will follow `.specify/templates/ai-platform-quickstart-template.md` with sections:
1. Architecture context — row B4 of `17b-…md` §3.3 and `17-…md` §4.3.3 / §4.4 / §6.1 stage 8 / §9.17.
2. What was implemented — the Quota DO handlers, admission stage-8 caller, credit stage-15 caller,
   fail-open grace path.
3. Files to review — this slice's `ai-platform/src/quota-do/index.ts`,
   `ai-platform/src/admission/index.ts`, `ai-platform/src/credit/index.ts`, the `GatewayObject`
   extension in `ai-platform/src/worker.ts`, and the two test files.
4. Prerequisites — omitted; `npx vitest run` against this slice's test files is sufficient.
5. Run the automated suite — `cd ai-platform && npx vitest run test/quota-do.test.ts
   test/admission-credit.test.ts` with the expected count from this slice only.
6. Inspect the changes — read `contracts/quota-do-rpc.md`, grep the DO RPC dispatch in `worker.ts`,
   run a focused test file.
7. Manual validation — omitted; CI is the only verification path (no behaviour exposed beyond the
   suite, per the slice's no-user-facing-surface nature DP-3).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── quota-do/
│   │   └── index.ts         # Quota DO handlers: admissionRPC, creditRPC, ephemeral sweep, soft-threshold degraded flag
│   ├── admission/
│   │   └── index.ts         # Stage-8 caller: id = env.DO.idFromName(installationId); grace path; maps concurrency→quota_exhausted
│   ├── credit/
│   │   └── index.ts         # Stage-15 caller + reconcileGraceUsage (re-admit then credit DO-issued requestId)
│   └── worker.ts            # GatewayObject.fetch/rpc (+ optional now); scheduled flush + reconcileGraceUsage
└── test/
    ├── quota-do.test.ts     # DO unit + concurrency cases
    └── admission-credit.test.ts  # Integration (spy) cases
```

**Structure Decision**: Mirror B3's per-stage sibling-module split (Clarification Q1). The Quota
Durable Object's logic lives in `src/quota-do/` and is invoked by the stage-8 caller (`src/admission/`)
and the stage-15 caller (`src/credit/`). The empty `GatewayObject` class A1 declared in `worker.ts` and
bound in `wrangler.toml` (`DO` → `GatewayObject`) is **extended** — its `fetch`/rpc method is added and
delegates to `src/quota-do/` handlers — it is not renamed and its binding is not rewritten, so A1's
skeleton contract (the binding surface) is preserved as extension, not rework (delivery plan §2.3;
spec `## Out of Scope`). `wrangler.toml`'s existing `DO → GatewayObject` binding is consumed unchanged.
Worker `scheduled` runs the shared rejection-counter flush and `reconcileGraceUsage` so grace admissions
are settled when the DO is reachable again. The Cloudflare Worker / Supabase / Flutter layer boundaries
in the template are not used verbatim; the Worker source tree in `ai-platform/` is the relevant one for
this slice (delivery plan §7.1).

## Consumes Binding

| Consumes entry | Bound to |
| --- | --- |
| A5 — config cache / `entitlement` snapshot | `ai-platform/src/config-cache/index.ts` (`ConfigCache`, `D1Reader`, `loadConfig`, `ConfigEntityKind`); `entitlements` kind holds `plan`, `period_bounds`, `request_quota`, `token_cost_budget`, `allowed_capabilities`, `soft_threshold`, `status` |
| B3 — immutable request principal | `ai-platform/src/entitlement/index.ts` `Principal` type (`installationId`, `jti`, `exp`, …) — consumed read-only by admission |
| B3 — guard-stage rejection discipline | `ai-platform/src/rate-limit/index.ts` (bucketed `platform_counter` tally flush shape) — admission rejections use the same bucketing, no new counter shape |
| B2 — `installation` / `entitlement` lifecycle status | read through the A5 config cache `entitlements` / `installations` kinds — admission sees only the snapshot B3 already validated; B4 does not write lifecycle |
| B1 — AAT `jti` / `exp` claims | read off the verified B3 `Principal` (`jti`, `exp`, `installationId`) — no signing or claim re-definition |
| A6 — parsed idempotency-key header | `ai-platform/src/adapter.ts` `AdapterStreamContext.headers.idempotencyKey` — admission consumes the key the adapter parsed |
| A2 — `§5.4` error taxonomy | `ai-platform/src/errors.ts` (`TaxonomyCode`, `buildErrorBody`, `liveHttpStatusForCode`) — admission emits `unauthenticated` / `quota_exhausted`; HTTP translation stays the adapter's |

Every Consumes entry resolves to an existing module, file, or type. No Consumes implementation is
rewritten: `worker.ts` is the one file B4 touches that an earlier slice created, and the touch is the
addition of a `fetch`/rpc delegation method on the empty `GatewayObject` class — extension, not
modification of its binding, name, or skeleton (delivery plan §2.3).

## Components Touched

The §4 component group this slice modifies is the **Quota Durable Object** (§4.4 *Storage ownership*,
the Durable Object row) plus the **admission stage** that queries it (§4.3.3 *Entitlement, quota, and
rate control* stage 8). These are one cohesive component group — the per-installation stateful side-car
and the single round trip that consults it — and §4.4 explicitly groups "Per-installation quota,
concurrency, `jti` replay set, idempotency records" as the Durable Object's ownership. No second §4
component is touched: the journal writer (§4.3.11, C3), the cost pre-flight (§4.3.3 stage 7, C2), and
soft-threshold routing (§8.8, F4) are explicitly out of scope by spec `## Out of Scope`. The reason this
reads as two §4 sub-sections rather than one is that the architecture splits the one mechanism across a
storage section (§4.4) and a pipeline-stage section (§4.3.3); they are not two components, and the
delivery plan sized the slice as one component group (delivery plan §2.5; §3.3 row B4).

## Files

| File | Trace |
| --- | --- |
| `ai-platform/src/quota-do/index.ts` (new) — the in-object admission handler (`jti` replay check, idempotency lookup, budget/concurrency check, optional `degraded` when soft_threshold crossed, lazy sweep of expired ephemeral entries including `admittedRequests` / `creditedRequests`), the credit handler (period counter adjustment incl. partial usage; closes idempotency to `completed`/`cancelled`), and the in-object ephemeral entry shape | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-015 |
| `ai-platform/src/admission/index.ts` (new) — stage-8 caller: load entitlement snapshot via `loadConfig(cache, reader, "entitlements", installationId)`, build the admission RPC payload from `Principal.jti`, `Principal.installationId`, and the parsed idempotency key, call `env.DO.get(env.DO.idFromName(installationId)).fetch(...)` once, map DO outcomes to `{admitted}` / `{replay}` / `{idempotent: priorState}` / `{quota_exhausted}` (including mapped `concurrency_exhausted`); fail-open grace path with reconciliation queue preserved on cap exhaustion | FR-001, FR-004, FR-005, FR-006, FR-007, FR-011, FR-012, FR-013, FR-014 |
| `ai-platform/src/credit/index.ts` (new) — stage-15 caller: build the credit RPC payload with actual usage (tokens/cost) plus a `partial` flag, call the same DO instance once; `reconcileGraceUsage` re-admits then credits the DO-issued `requestId` | FR-008, FR-013, FR-016 |
| `ai-platform/src/worker.ts` (modified — extension only) — implement `GatewayObject`'s `fetch`/rpc method (optional injectable `now` for ephemeral-sweep tests), dispatching on the RPC kind to `admissionRPC` / `creditRPC` from `src/quota-do/`; `scheduled` runs rejection flush + `reconcileGraceUsage`; the binding `DO → GatewayObject` in `wrangler.toml` and the class export are unchanged in name | FR-001, FR-011, FR-013 |
| `ai-platform/test/quota-do.test.ts` (new) — DO unit + concurrency cases | (Test Layout) |
| `ai-platform/test/admission-credit.test.ts` (new) — integration (spy) cases | (Test Layout) |
| `ai-platform/vitest.workers.config.ts` (modified — test registration only) — add the two new test files to `test.include` | (Test Layout) |
| `specs/024-quota-do-admission/contracts/quota-do-rpc.md` (new) — the admission and credit RPC request/response message shapes and the ephemeral entry shape, frozen for later slices' `Consumes` | `## Slice Contract → Freezes` (admission RPC, credit RPC, in-object ephemeral store) |
| `specs/024-quota-do-admission/quickstart.md` (new, written during Documentation task after verification) — this slice's review/test surface per the template | `## Project Structure → Documentation` |

No file traces to a non-`FR-###`: the `worker.ts` and `vitest.workers.config.ts` modifications are
test/invocation plumbing whose behaviour is asserted by FR-001 and FR-011, and the `contracts/` /
`quickstart.md` documents trace to the spec's `Freezes` and Documentation sections respectively.

## Test Layout

Per §13.5 layers and §3.11.2 row B4 layer "DO unit + concurrency + integration (spy)":

| Named test (spec Test plan) | Layer | File |
| --- | --- | --- |
| `admission_fresh_jti_accepted` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `admission_repeated_jti_rejected` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `admission_new_idempotency_key_accepted` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `admission_repeat_idempotency_key_returns_prior_record` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `admission_budget_exhaustion_rejected` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `admission_concurrency_ceiling_rejected` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `credit_adjusts_counters_with_actual_usage` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `credit_adjusts_counters_with_partial_usage` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `parallel_admissions_exact_final_count` | Concurrency | `ai-platform/test/quota-do.test.ts` |
| `ephemeral_entries_expire_in_place` | DO unit | `ai-platform/test/quota-do.test.ts` |
| `admission_exactly_one_do_fetch_per_request` | Integration (spy) | `ai-platform/test/admission-credit.test.ts` |
| `admission_repeated_key_no_second_inference` | Integration (spy) | `ai-platform/test/admission-credit.test.ts` |
| `admission_expired_token_same_key_unauthenticated` | Integration | `ai-platform/test/admission-credit.test.ts` |
| `quota_do_unavailable_capped_grace_then_rejection` | Integration | `ai-platform/test/admission-credit.test.ts` |
| `grace_usage_reconciled_afterwards` | Integration (spy) | `ai-platform/test/admission-credit.test.ts` |
| `admission_rejection_counted_not_journaled` | Integration (spy) | `ai-platform/test/admission-credit.test.ts` |

Every named test in the spec's Test plan is placed in exactly one §13.5 layer and one file. DO unit +
concurrency cases drive the real Miniflare DO via `cloudflare:test`'s `env.DO`
(`env.DO.get(env.DO.idFromName(installationId)).fetch(...)`) against an installation-scoped
instance — the real binding is what reproduces DO-level serialized counting (Clarification Q3). The
integration (spy) cases inject a counting spy around `env.DO` (Miniflare DO namespace) to assert fetch
count and the post-reconciliation counter delta — the same injection shape A5/B3 use for D1 reads,
extended to the DO binding (Clarification Q4). `admission_rejection_counted_not_journaled` spies on
the `platform_counter` flush (the B3-frozen bucketing) and asserts no `ai_request` row is created — no
new counter shape. No test is placed in a layer §13.5 does not name.

## Sequencing

1. **Contracts first.** Write `specs/024-quota-do-admission/contracts/quota-do-rpc.md` first — the
   admission and credit RPC message shapes plus the in-object ephemeral entry shape. The Quota DO
   handlers, the two callers, and the tests all bind to these frozen shapes; writing them first
   constrains the implementer against prose instead (DP-4).
2. **`src/quota-do/index.ts`** — `admissionRPC`, `creditRPC`, and the lazy ephemeral sweep
   (Clarification Q5: admission evicts expired entries before answering, no `alarm()` handler). Pure
   functions over the DO's `ctx.storage` (`blockConcurrencyWhile` for the atomic read-modify-write the
   serialized-counting test exercises).
3. **`worker.ts` extension** — add `GatewayObject`'s `fetch`/rpc dispatch to the handlers (pass optional
   injectable `now`); verify the `DO → GatewayObject` binding is unchanged; wire `scheduled` to flush
   rejection tallies and call `reconcileGraceUsage`.
4. **`src/admission/index.ts`** and **`src/credit/index.ts`** — the two callers; admission reads the
   entitlement snapshot through `loadConfig` (Clarification Q2) and invokes the DO once via
   `idFromName`; credit invokes the same instance once with actual usage and a `partial` flag;
   `reconcileGraceUsage` re-admits then credits.
5. **Fail-open grace path** in `src/admission/index.ts` — Quota DO `fetch` rejection triggers the
   capped-grace admission (record the grace admission; preserve queue on cap exhaustion) and queues
   reconciliation for `scheduled` / credit-side drain when the DO is reachable again (§15 #3).
6. **Tests land alongside**, not after. `ai-platform/test/quota-do.test.ts` (DO unit + concurrency) is
   written with the handlers so each handler is verified in isolation; `ai-platform/test/admission-
   credit.test.ts` (integration spy, including the grace path) lands with the callers. The
   `vitest.workers.config.ts` registration is updated in the same step each test file is added.
7. **`quickstart.md`** is filled during the Documentation task after the suite is green.