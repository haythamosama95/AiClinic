# Quickstart: Declared-weight credit debit in admission (G2)

G2 extends the Quota Durable Object so stage-15 settlement debits the resolved manifest's declared `quota_weight` from the installation's monthly credit budget. Admission answers remaining budget in AI credits — `quota_exhausted` with `{ reset_at }` when exhausted, `{ admitted, degraded: true }` when the credit ratio crosses the soft threshold — while token and cost counters stay settlement-only. The two-round-trip request-path invariant is unchanged.

**Scope rule:** This quickstart covers **only slice G2**. It lists G2 files, G2 tests, and G2 commands — not prior-slice regression suites, combined platform counts, or files from earlier slices.

## 1. Architecture context

- **Delivery plan row:** G2 in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.13 — *Declared-weight credit debit in admission* (`Needs: G1, B4, F4`). Done when the stage-15 credit call debits the manifest's declared `quota_weight` (per leg for `conversational`), cancelled requests debit in full, guard rejections debit nothing; admission answers credit-budget exhaustion with `quota_exhausted` and crosses the soft threshold on the credit ratio into the `degraded` flag; token and cost counters settle actuals unchanged; the two-round-trip and no-journal-on-rejection invariants hold.
- **Architecture sections:** `§4.3.3` (Quota Durable Object admission and credit RPCs), `§5.1` (Economics — declared `quota_weight` as the credit debit), `§8.8` (soft-threshold degraded routing on the credit ratio), and **A15** (credit-denominated monthly quota; request path never sees a price).
- **Spec delivered:** Snapshot `credit_budget`; credit RPC `credits` debit; period `creditsUsed`; credit-budget exhaustion at admission; credit-ratio soft threshold sets `degraded`; cancelled requests debit full declared weight; guard rejections debit nothing; token/cost settlement unchanged; ten named tests (eight DO unit, two integration spy).
- **Plan scoped:** Field extensions on B4's `src/quota-do/`, `src/admission/`, and `src/credit/`; stage-15 `creditUsage` wiring passes existing `quotaWeight` as `credits` in `src/pipeline/index.ts` and `src/worker.ts`; two frozen contracts; no D1 migration; Consumes G1, B4, and F4 modules extended, not rewritten.

## 2. What was implemented

- **Declared-weight `credits` debit** — stage-15 `creditRPC` adds the manifest's `quotaWeight` to `creditsUsed`; per-leg for `conversational`; full weight even when `partial: true` on cancel.
- **Snapshot `credit_budget`** — G1 entitlement column mapped onto `EntitlementSnapshot` via `mapEntitlementSnapshot`; drives remaining-budget and soft-threshold ratio.
- **Period `creditsUsed`** — new counter on `PeriodCounters`; initialized to zero; incremented on each credit call.
- **Credit-budget exhaustion** — `creditsUsed >= credit_budget` answers `quota_exhausted` with `{ reset_at }` via the existing F4/A2 chain; no overage.
- **Credit-ratio `degraded`** — `isSoftThresholdCrossed` uses `creditsUsed / credit_budget`; F4 routing consumes the flag unchanged.
- **Token/cost settlement unchanged** — `tokensUsed` / `costUsed` follow `usage` only; they do not determine remaining-budget or the soft-threshold decision.
- **Two-round-trip invariant held** — admission (stage 8) then credit (stage 15); no third Durable Object fetch; guard rejection writes no journal row and invokes no credit RPC.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/quota-do/index.ts` | `credit_budget` snapshot, `creditsUsed` counter, `credits` debit, remaining-budget, credit-ratio soft threshold |
| `ai-platform/src/admission/index.ts` | `mapEntitlementSnapshot` copies `credit_budget`; stage-8 outcome mapping unchanged |
| `ai-platform/src/credit/index.ts` | `CreditInput.credits` → credit RPC body |
| `ai-platform/src/pipeline/index.ts` | `settleHappyPath` passes `quotaWeight` as `credits` into `creditUsage` |
| `ai-platform/src/worker.ts` | `settleTerminal`, `settleCompletedRequest`, and broker `creditSink` pass `quotaWeight` as `credits` |
| `ai-platform/test/quota-do.test.ts` | Eight G2 DO unit cases: `credit_debits_declared_quota_weight` through `credit_rpc_gains_fields_without_changing_existing_meanings` |
| `ai-platform/test/admission-credit.test.ts` | Two G2 spy cases: `guard_rejection_debits_nothing_and_writes_no_journal_row`, `exactly_two_durable_object_round_trips_per_request` |
| `specs/057-credit-debit/contracts/credit-budget-admission.md` | Frozen: snapshot `credit_budget`, remaining-budget, `quota_exhausted`, credit-ratio `degraded` |
| `specs/057-credit-debit/contracts/credit-rpc-debit.md` | Frozen: `credits` debit, `creditsUsed`, cancelled full debit, guard non-debit, token/cost unchanged |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run --config vitest.workers.config.ts test/quota-do.test.ts test/admission-credit.test.ts
```

Expected for this slice: **10 passing tests** — the eight named DO unit cases in `quota-do.test.ts` and the two named spy cases in `admission-credit.test.ts` (`credit_debits_declared_quota_weight` through `exactly_two_durable_object_round_trips_per_request`). Do not run `npm test` for the full platform suite.

To run a subset of this slice's tests:

```bash
npx vitest run --config vitest.workers.config.ts test/quota-do.test.ts -t credit_debits_declared_quota_weight
npx vitest run --config vitest.workers.config.ts test/admission-credit.test.ts -t exactly_two_durable_object_round_trips_per_request
```

## 5. Inspect the changes

1. Open `ai-platform/src/quota-do/index.ts` — `EntitlementSnapshot.credit_budget`, `PeriodCounters.creditsUsed`, `CreditRequest.credits`, remaining-budget on credit exhaustion, credit-ratio `isSoftThresholdCrossed`.
2. Open `ai-platform/src/admission/index.ts` — `mapEntitlementSnapshot` copies `credit_budget` from the config-cache entitlement row.
3. Open `ai-platform/src/credit/index.ts` — `CreditInput.credits` forwarded in `invokeCreditRpc`.
4. Open `ai-platform/src/pipeline/index.ts` and `ai-platform/src/worker.ts` — `quotaWeight` passed as `credits` at existing `creditUsage` call sites.
5. Grep for G2 field names:

```bash
cd ai-platform
rg 'credit_budget' src/quota-do/index.ts src/admission/index.ts
rg 'creditsUsed' src/quota-do/index.ts
rg 'credits:' src/credit/index.ts src/pipeline/index.ts src/worker.ts
```

6. Read the two frozen contracts — `specs/057-credit-debit/contracts/credit-budget-admission.md` and `specs/057-credit-debit/contracts/credit-rpc-debit.md`.
7. Confirm Consumes modules are not rewritten — `specs/024-quota-do-admission/contracts/quota-do-rpc.md`, `specs/042-soft-threshold-degraded-routing/contracts/*`, `specs/056-plan-catalogue/contracts/plan-catalogue.md`, and `ai-platform/src/soft-threshold/` remain unchanged aside from G2's credit-ratio input to the existing `degraded` flag.
