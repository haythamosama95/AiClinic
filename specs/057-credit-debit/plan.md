# Implementation Plan: Declared-weight credit debit in admission (G2)

**Branch**: `ai/057-g2-credit-debit` | **Date**: 2026-09-11 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/057-credit-debit/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

G2 extends B4’s Quota Durable Object so stage-15 settlement debits the resolved manifest’s declared `quota_weight` from the installation’s monthly credit budget, cancelled requests still debit that weight, and guard rejections debit nothing. Admission answers remaining budget in AI credits (`quota_exhausted` with `{ reset_at }` when exhausted; `{ allowed, degraded: true }` when the credit ratio crosses the soft threshold) while token and cost counters stay settlement-only. It sits in Band G after G1, B4, and F4 (`Needs: G1, B4, F4`); G3 reads `creditsUsed` from this slice and must not rewrite it.

## Technical Context

**Language/Version**: TypeScript 5.9 (`ai-platform/package.json`) targeting the Cloudflare Worker and `cloudflare:workers` Durable Object. Node `>=22` for the Vitest / Wrangler harness (`@cloudflare/vitest-pool-workers`).

**Primary Dependencies**: B4 Quota DO + stage-8 admission + stage-15 credit (`ai-platform/src/quota-do/index.ts`, `src/admission/index.ts`, `src/credit/index.ts`); G1 entitlement column / snapshot name `credit_budget` served on config-cache kind `"entitlements"` (`SELECT * FROM entitlement`); F4 `{ allowed, degraded: true }` flag and `isSoftThresholdCrossed` used/budget comparison; A4 resolved manifest `Economics.quotaWeight` (already on the stage-15 call path). No new npm packages, no new modules, no Supabase schema, no Flutter surface.

**Storage**: Per-installation Quota Durable Object only. G1 already persisted `entitlement.credit_budget`; this slice maps that column onto B4’s `EntitlementSnapshot` and adds in-object `PeriodCounters.creditsUsed`. No D1 migration (spec Assumptions). No R2 write. No Supabase write path. B4’s ephemeral store, fail-open grace queue, and token/cost counters are not rewritten.

**Testing**: DO unit + integration (spy) per delivery plan §3.12.10 row G2 and architecture §13.5 Pipeline tests. Eight named DO unit cases land in `ai-platform/test/quota-do.test.ts` (same Miniflare `env.DO` RPC harness). The two spy cases reuse B4’s counting spy (`createDoSpy(env.DO)` in `ai-platform/test/admission-credit.test.ts` — B4’s `env.QUOTA_DO` spy). Suite joins CI permanently (§3.11).

**Target Platform**: `ai-platform/` Cloudflare Worker + per-installation Quota Durable Object. No `frontend/`, no `backend/`. Gateway remains additive, non-primary (§14).

**Project Type**: Band G commercial-surface slice, Worker-only. Extends B4’s existing three surfaces rather than adding a module. Nothing here adds request-path I/O (Delivery Plan §3.13).

**Performance Goals**: Exactly two Durable Object round trips per admitted request — one admission (stage 8) and one credit (stage 15). No third trip for credits, replay, or the degraded decision (FR-013; §4.3.3; §7.5; §13.6; delivery plan §6.4). Guard I/O budget unchanged (one DO round trip and one D1 insert in the guard). No second R2 object per request. No per-request server-side state.

**Constraints**:
- Extend B4’s existing surfaces (`src/quota-do/`, `src/admission/`, `src/credit/`) rather than adding modules.
- Map G1’s `credit_budget` onto B4’s `EntitlementSnapshot`; add `credits` on the credit RPC and `creditsUsed` on `PeriodCounters`. Existing token, cost, request-count, and other credit-RPC fields keep their meanings (FR-012; delivery plan §2.3).
- Drive the debit from the already-resolved manifest `quotaWeight` as the RPC `credits` field (FR-004, FR-005, FR-014). No provider price on the request path.
- Remaining-budget: keep B4’s request-quota exhaustion (`requestsUsed >= request_quota`). Add credit-budget exhaustion (`creditsUsed >= credit_budget`). Token and cost counters settle actuals only and do not determine remaining-budget or the soft-threshold decision (FR-011, FR-015; A15).
- Soft threshold: apply F4’s used/budget comparison to the credit ratio (`creditsUsed / credit_budget`); do not rewrite F4’s `routing_tier` / `degraded_notice` path (FR-009).
- `quota_exhausted` carries `{ reset_at }` via the existing F4/A2 chain (`period_end` → `periodReset` → wire `period_reset`). Do not invent a new DO field named `reset_at`.
- Do not fold rate limiting (B3) or the token-denominated cost ceiling (C2) into the credit debit or the credit remaining-budget answer (FR-015).
- Do not rewrite B4’s four admission questions, one-then-one round-trip budget, replay, idempotency, concurrency, ephemeral store, or fail-open grace. Do not migrate D1. Do not rewrite G1 catalogue/assignment or F4 routing.
- Do not modify frozen Consumes contract files (`specs/024-quota-do-admission/contracts/quota-do-rpc.md`, `specs/042-soft-threshold-degraded-routing/contracts/*`, `specs/056-plan-catalogue/contracts/plan-catalogue.md`).

**Scale/Scope**: One §4 component (§4.3.3). Fifteen FRs. Ten named tests. Field extensions on three existing B4 modules plus the existing stage-15 `creditUsage` call sites that already hold `quotaWeight`. Roughly 16–20 tasks — under the ~25-task ceiling (delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — declared
      per-capability credit prices, no overage, no marketplace, no payment-provider
      integration (constitution I; spec Clinic Fit; A15).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — extends the existing Quota Durable
      Object and its two RPCs inside one Worker; no new deployable, queue, or store.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated —
      G2 touches only `ai-platform/` (Quota DO, stage-8 admission, stage-15 credit). It
      does not touch `backend/` or `frontend/`. **§14 acknowledgement:** the Worker is an
      additive, non-primary component with no domain logic, no business data, and no
      write path into Supabase. Credit debit, `credit_budget` admission, and period
      `creditsUsed` are platform Quota Durable Object accounting, not clinic business
      data (A15 constitution check).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — clinic Supabase
      integrity is untouched. Serialized credit accounting stays inside the
      per-installation Quota Durable Object (§4.3.3). This slice does not write clinic
      tables.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — admission remains installation-scoped
      (one DO instance per installation); `credit_budget` is read from the entitlement
      snapshot G1 already serves through the config cache; no clinic table is written.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — credit-budget
      exhaustion returns `quota_exhausted` with `{ reset_at }` and never hard-locks
      clinical work (constitution V; FR-008, FR-010; §8.8). Soft-threshold pressure sets
      `degraded` rather than refusing. Quota Durable Object unavailability remains B4’s
      capped fail-open grace (Consumes B4).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component
with no domain logic, no business data, and no write path into Supabase. G2 extends Quota
DO admission and credit accounting only; it never writes clinic data and never hard-locks
non-AI workflows.

## Project Structure

### Documentation (this feature)

```text
specs/057-credit-debit/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify (authoritative)
├── contracts/
│   ├── credit-budget-admission.md  # Freezes: snapshot credit_budget, remaining-budget,
│   │                               #   quota_exhausted, credit-ratio degraded
│   └── credit-rpc-debit.md         # Freezes: credits debit, creditsUsed, cancelled full,
│                                   #   guard non-debit, token/cost unchanged
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — this slice defines no D1 entity and writes no D1
schema. G1 already created `entitlement.credit_budget`; G2 maps that column onto the
admission snapshot (spec Key Entities; Assumptions).

`research.md` is **never** produced on this platform — the research is
`docs/architecture/ai-platform/01-ai-platform.md`.

`contracts/` is produced because **Freezes** entries have wire shapes later slices’
**Consumes** must bind to (G3 reads `creditsUsed`): snapshot `credit_budget`, credit RPC
`credits`, period `creditsUsed`, `quota_exhausted` `{ reset_at }`, `{ allowed, degraded: true }`
from the credit ratio. B4 / F4 / G1 contract files are **not** edited (delivery plan §2.3).

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — G2 row of the delivery plan (§3.13) and §4.3.3 / §5.1 /
  §8.8 / A15; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — declared-weight `credits` debit; snapshot `credit_budget`;
  period `creditsUsed`; credit-budget exhaustion and credit-ratio `degraded`; token/cost
  settlement unchanged; two-round-trip invariant held.
- **§3 Files to review** — only this slice’s `src/quota-do/index.ts`, `src/admission/index.ts`,
  `src/credit/index.ts`, stage-15 `creditUsage` wiring that passes `quotaWeight`, this slice’s
  named tests in `test/quota-do.test.ts` and `test/admission-credit.test.ts`, and `contracts/*`.
- **§4 Prerequisites** — omitted; `npx vitest run` against this slice’s test files is sufficient.
- **§5 Run the automated suite** — slice-only:
  `npx vitest run --config vitest.workers.config.ts test/quota-do.test.ts test/admission-credit.test.ts`
  (G2’s ten named tests live in those files). No full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — grep `credit_budget` / `creditsUsed` / `credits:`; read the two
  contract files; confirm Consumes contract files and `src/soft-threshold/` are not rewritten.
- No **§7 Manual validation** — CI is the only verification path beyond the suite
  (no user-facing surface beyond the gateway outcomes the ten tests assert; DP-3).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── quota-do/
│   │   └── index.ts              # MODIFIED — EntitlementSnapshot.credit_budget;
│   │                             #   PeriodCounters.creditsUsed; CreditRequest.credits;
│   │                             #   remaining-budget + credit-ratio soft threshold
│   ├── admission/
│   │   └── index.ts              # MODIFIED — mapEntitlementSnapshot copies credit_budget
│   ├── credit/
│   │   └── index.ts              # MODIFIED — CreditInput.credits → credit RPC
│   ├── pipeline/
│   │   └── index.ts              # MODIFIED (wiring) — pass settle quotaWeight as credits
│   ├── worker.ts                 # MODIFIED (wiring) — pass manifest.Economics.quotaWeight
│   │                             #   as credits at existing creditUsage call sites
│   └── soft-threshold/
│       └── index.ts              # UNCHANGED (Consumes F4 routing)
├── test/
│   ├── quota-do.test.ts          # MODIFIED — eight G2 DO unit cases + fixture extension
│   ├── admission-credit.test.ts  # MODIFIED — two G2 spy cases; reuse createDoSpy(env.DO)
│   └── soft-threshold-routing.test.ts  # MODIFIED (fixture only) — seed credit ratio
└── contracts live under specs/057-credit-debit/contracts/ (this feature)
```

**Structure Decision**: Extend B4’s three existing modules rather than adding a fourth
(clarify; D-15 — one implementation needs no interface). Snapshot mapping stays in
`src/admission/` (`mapEntitlementSnapshot` copies G1 `credit_budget` from the config-cache
row). Remaining-budget and soft-threshold predicates stay inside `admissionRPC` so they ride
the existing single round trip. The debit is applied inside `creditRPC` from the new `credits`
field; `src/credit/` forwards it from `CreditInput`. Production callers already hold the
resolved manifest `quotaWeight` (`pipeline` settle and `worker.ts` settlement / broker
`creditSink`) and pass it as `credits` — wiring, not a new §4 component. The Spec Kit
template’s `frontend/` / `backend/` trees are unused; the Worker source tree in
`ai-platform/` is the relevant one (delivery plan §7.1).

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How G2 binds to it |
| --- | --- | --- |
| **G1 — Plan catalogue and credit-denominated entitlement** (entitlement monthly credit-budget column; frozen snapshot name `credit_budget`; plan-populated soft threshold; token and cost budgets keep their meanings) | D1 column `entitlement.credit_budget` (`ai-platform/migrations/20260911120000_plan_catalogue.sql`); config-cache kind `"entitlements"` already `SELECT *` so the loaded row includes `credit_budget` (`ai-platform/src/config-cache/index.ts` `createD1ConfigReader`). Frozen artifacts: `specs/056-plan-catalogue/contracts/plan-catalogue.md` §6, `specs/056-plan-catalogue/data-model.md`. | G2 **maps** `credit_budget` onto B4 `EntitlementSnapshot` in `mapEntitlementSnapshot`. It does **not** create the column, assign plans, or maintain the catalogue. G1 contract files are not edited. |
| **B4 — Quota Durable Object and admission stage** (per-installation Quota DO; stage-8 admission RPC answering the four questions in one round trip; separate stage-15 credit RPC; two-round-trip budget; ephemeral store; capped fail-open grace) | `ai-platform/src/quota-do/index.ts` (`admissionRPC`, `creditRPC`, `EntitlementSnapshot`, `PeriodCounters`, `CreditRequest`, `isQuotaExhausted`, `isSoftThresholdCrossed`); `ai-platform/src/admission/index.ts` (`runAdmission`, `mapEntitlementSnapshot`); `ai-platform/src/credit/index.ts` (`creditUsage`, `invokeCreditRpc`). Frozen artifact: `specs/024-quota-do-admission/contracts/quota-do-rpc.md` (explicitly names G2 as the scheduled additive extension). Spy: `createDoSpy(env.DO)` in `ai-platform/test/admission-credit.test.ts`. | G2 **extends** the snapshot with `credit_budget`, the credit RPC with `credits`, and period counters with `creditsUsed`. It does **not** rewrite the four questions, the one-then-one round-trip budget, replay, idempotency, concurrency, ephemeral store, or grace. B4’s contract file is not edited. |
| **F4 — Soft-threshold degraded routing** (admission outcome `{ allowed, degraded: true }` when remaining budget is not exhausted but the soft threshold has been crossed; routing that consumes that flag) | `ai-platform/src/quota-do/index.ts` `isSoftThresholdCrossed` / `coerceSoftThreshold`; `AdmissionAdmitted.degraded`; `ai-platform/src/soft-threshold/index.ts` (`resolveRoutingTier`, `routing_tier`, `degraded_notice`) **unchanged**. Frozen artifacts: `specs/042-soft-threshold-degraded-routing/contracts/soft-threshold-admission.md`, `contracts/degraded-routing-signal.md`. | G2 **applies** F4’s used/budget comparison to the credit ratio. It does **not** rewrite F4’s routing path, `routing_tier`, or `degraded_notice`. F4 contract files are not edited. |

No consumed entry lacks an implementation. No consumed **contract file** is rewritten (delivery plan §2.3). B4’s own quota-do-rpc contract already scheduled this additive field set. Stop condition 2 is not triggered.

**Transitive, not Consumes (do not rewrite):** A4 `Economics.quotaWeight` on the resolved manifest (`ai-platform/src/manifest/index.ts`; already forwarded as journal `quotaWeight` from `worker.ts` / `pipeline`). A2 `quota_exhausted` + `period_reset` (`ai-platform/src/errors.ts` `supplementaryFieldsForCode`). C3 journal writer — G2 asserts the inherited no-journal-on-rejection invariant and does not rewrite `ai_request` / `usage_event`.

## Components Touched

| §4 component | What G2 changes | Behaviour added? |
| --- | --- | --- |
| **§4.3.3 Entitlement, quota, and rate control** | Extends the Quota DO entitlement snapshot, remaining-budget answer, soft-threshold predicate, and stage-15 credit RPC for credit-denominated monthly quota | Yes — declared-weight debit, credit-budget exhaustion, credit-ratio `degraded` |

Only one §4 component. Delivery plan §3.13 row **G2** Canonical names §4.3.3 together with contract §5.1 (manifest `quota_weight`, already frozen by A4 and consumed here), sequence §8.8 (the budget branches this slice owns), and amendment A15. §5.1 is not modified — G2 reads the resolved `quotaWeight`. §8.8 is the sequence this slice realises on B4’s existing RPCs, not a second component.

**Wiring extensions (not additional §4 component ownership):**

- **Stage-15 `creditUsage` call sites** (`src/credit/index.ts` payload; `src/pipeline/index.ts` settle; `src/worker.ts` `settleTerminal` / `settleCompletedRequest` / broker `creditSink`) — pass already-resolved `quotaWeight` as `credits`. These are the existing credit callers, not a new pipeline stage.
- **F4 `src/soft-threshold/`** — consumed unchanged.

Stop condition 5 is satisfied: one §4 component, ~16–20 tasks.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/quota-do/index.ts` | Modified — `EntitlementSnapshot.credit_budget`; `PeriodCounters.creditsUsed`; `CreditRequest.credits`; `initialPeriodCounters` includes `creditsUsed: 0`; remaining-budget = request-quota (B4) **or** credit-budget; `isSoftThresholdCrossed` uses the credit ratio with F4’s used/budget rules (`credit_budget > 0`, `soft_threshold` in `(0, 1]`); `creditRPC` adds `credits` to `creditsUsed` (full weight when `partial: true`) and still adds `usage.tokens` / `usage.cost` / `requestsUsed` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-008, FR-009, FR-010, FR-011, FR-012, FR-015 |
| `ai-platform/src/admission/index.ts` | Modified — `mapEntitlementSnapshot` copies G1 `credit_budget` onto the snapshot sent in the admission RPC. Outcome mapping (`quota_exhausted` + `periodReset`, `degraded`) unchanged | FR-001, FR-003, FR-008, FR-012 |
| `ai-platform/src/credit/index.ts` | Modified — `CreditInput.credits`; `invokeCreditRpc` JSON body gains `credits`. Token/cost `usage` and `partial` keep their meanings. Grace queue schema and reconcile persistence are not rewritten (Consumes B4) | FR-002, FR-005, FR-006, FR-011, FR-012, FR-013 |
| `ai-platform/src/pipeline/index.ts` | Modified (wiring) — `settleHappyPath` passes existing `quotaWeight` as `credits` into `creditUsage` | FR-004, FR-005, FR-014 |
| `ai-platform/src/worker.ts` | Modified (wiring) — `settleTerminal`, `settleCompletedRequest`, and broker `creditSink` pass `Number(manifest.Economics.quotaWeight)` as `credits` | FR-004, FR-005, FR-006, FR-014 |
| `ai-platform/test/quota-do.test.ts` | Modified — eight G2 DO unit describes; `buildEntitlementSnapshot` default `credit_budget`; existing `PeriodCounters` equality includes `creditsUsed`; request-quota exhaustion kept; token/cost remaining-budget cases retargeted to settlement-only; existing soft-threshold unit case seeds the credit ratio | Test Layout / SC-001–SC-005; FR-012 |
| `ai-platform/test/admission-credit.test.ts` | Modified — two G2 spy describes using `createDoSpy(env.DO)`; apply G1 migration so `credit_budget` exists; `seedEntitlement` gains a positive `creditBudget` default | Test Layout / SC-002, SC-005 |
| `ai-platform/test/soft-threshold-routing.test.ts` | Modified (fixture only) — seed `credit_budget` / `creditsUsed` so F4 routing cases still cross the flag G2 now sets from the credit ratio. Routing assertions (`routing_tier`, `degraded_notice`) unchanged | FR-009 (do not rewrite F4 routing) |
| `specs/057-credit-debit/contracts/credit-budget-admission.md` | Created | Freezes → credit-budget admission, `quota_exhausted` `{ reset_at }`, credit-ratio `degraded` |
| `specs/057-credit-debit/contracts/credit-rpc-debit.md` | Created | Freezes → declared-weight `credits` debit, `creditsUsed`, cancelled full, guard non-debit, token/cost unchanged |
| `specs/057-credit-debit/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above |

Every code file traces to an `FR-###`. No file is created for an unstated requirement. Consumed B4 RPC discriminants, F4 routing module, G1 catalogue, and D1 schema stay unchanged aside from the listed extensions. `src/pricing/` is not touched. No new D1 migration.

## Test Layout

The spec’s `### Test plan` names ten tests (delivery plan §3.12.10 G2; §13.5 Pipeline tests; layers **DO unit** and **Integration (spy)**). Place them as follows:

| Spec Test plan name | File | §13.5 layer | Asserts (FR / SC) |
| --- | --- | --- | --- |
| `credit_debits_declared_quota_weight` | `ai-platform/test/quota-do.test.ts` | Pipeline (DO unit) | FR-002, FR-004, FR-005 / SC-001 — stage-15 credit with `credits: W` increases `creditsUsed` by exactly W |
| `conversational_leg_debits_per_leg` | `ai-platform/test/quota-do.test.ts` | Pipeline (DO unit) | FR-004 / SC-001 — two credited legs each with `credits: W` → `creditsUsed` increases by 2W |
| `cancelled_request_debits_full_declared_weight` | `ai-platform/test/quota-do.test.ts` | Pipeline (DO unit) | FR-006 / SC-002 — `partial: true` still adds full `credits` (token/cost may be partial) |
| `credit_budget_exhausted_quota_exhausted_with_reset_at` | `ai-platform/test/quota-do.test.ts` | Pipeline (DO unit) | FR-001, FR-008, FR-010 / SC-003 — `creditsUsed >= credit_budget` → `quota_exhausted` with `period_end` (wire `{ reset_at }`); no overage |
| `credit_ratio_soft_threshold_sets_degraded_flag` | `ai-platform/test/quota-do.test.ts` | Pipeline (DO unit) | FR-009, FR-010 / SC-003 — credit ratio ≥ `soft_threshold` with budget remaining → `{ admitted, degraded: true }` |
| `below_credit_soft_threshold_not_degraded` | `ai-platform/test/quota-do.test.ts` | Pipeline (DO unit) | FR-009 / SC-003 — credit ratio below threshold with budget remaining → admitted without `degraded` |
| `token_and_cost_counters_settle_actuals_unchanged` | `ai-platform/test/quota-do.test.ts` | Pipeline (DO unit) | FR-002, FR-005, FR-011, FR-015 / SC-004 — `tokensUsed` / `costUsed` follow `usage` (including partial); they do not set `credits` or remaining-budget / soft-threshold |
| `credit_rpc_gains_fields_without_changing_existing_meanings` | `ai-platform/test/quota-do.test.ts` | Pipeline (DO unit) | FR-012 / SC-005 — snapshot has `credit_budget`; credit body has `credits`; counters have `creditsUsed`; `usage.tokens` / `usage.cost` / `requestsUsed` / `partial` keep prior meanings |
| `guard_rejection_debits_nothing_and_writes_no_journal_row` | `ai-platform/test/admission-credit.test.ts` | Pipeline (Integration spy) | FR-007 / SC-002 — credit-budget exhaustion at admission: spy shows no credit RPC; no `ai_request` row (reuse `createDoSpy(env.DO)` and B4’s no-journal assertion) |
| `exactly_two_durable_object_round_trips_per_request` | `ai-platform/test/admission-credit.test.ts` | Pipeline (Integration spy) | FR-013 / SC-005 — admitted then credited: `createDoSpy(env.DO).fetchCount() === 2` (admission + credit); no third trip |

Every named test from the spec is placeable in §13.5. No named test is orphaned. Inherited §6.4 prohibitions (no second DO trip; no guard-rejection journal) are asserted by the two spy cases. `rate_limited` remains B3 and is not emitted here.

## Sequencing

1. **Tests first (or alongside)** — add the eight failing DO unit describes to `quota-do.test.ts` and the two spy describes to `admission-credit.test.ts` against missing `credits` / `creditsUsed` / `credit_budget` (never after implementation).
2. **Snapshot field** — `EntitlementSnapshot.credit_budget` + `mapEntitlementSnapshot` copy from the G1 column (FR-001, FR-012). Extend `buildEntitlementSnapshot` / `seedEntitlement` with a positive default so existing admits stay green.
3. **Remaining-budget and soft threshold** — keep request-quota exhaustion; add credit-budget exhaustion; retarget token/cost off remaining-budget; apply F4’s used/budget comparison to `creditsUsed / credit_budget` (FR-003, FR-008, FR-009, FR-015).
4. **Credit RPC debit** — `CreditRequest.credits` + `PeriodCounters.creditsUsed`; `creditRPC` adds `credits` even when `partial: true`; token/cost/`requestsUsed` arithmetic unchanged (FR-002, FR-005, FR-006, FR-011, FR-012).
5. **Stage-15 wiring** — `CreditInput.credits`; pipeline and `worker.ts` pass resolved `quotaWeight` (FR-004, FR-014).
6. **Turn tests green** — including per-leg 2W, field-extension equality, spy `fetchCount === 2`, and no-journal on credit-budget exhaustion. Fixture-only update of F4 routing tests to seed the credit ratio (FR-009).
7. **Verification** — slice-only vitest command above; confirm Consumes contract files, `src/soft-threshold/`, and D1 migrations are untouched; confirm no third DO trip.
8. **Documentation** — write `quickstart.md` per sections above.

## Complexity Tracking

> No constitution violations requiring justification. Empty by design.
