# Contract: Declared-weight credit RPC debit (G2)

**Frozen by:** Slice G2 — Declared-weight credit debit in admission
**Implements:** §4.3.3, §5.1 Economics, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Extends:** B4 `specs/024-quota-do-admission/contracts/quota-do-rpc.md` (credit RPC request
and `PeriodCounters` only)
**Status:** Frozen. Later slices may **extend** these fields; they may not **rewrite** them
(Delivery Plan §2.3). G3 reads `creditsUsed`.

**Source of truth in code:** `ai-platform/src/quota-do/index.ts` (`CreditRequest`,
`PeriodCounters`, `creditRPC`); `ai-platform/src/credit/index.ts` (`CreditInput`,
`creditUsage`).

**Traces to:** spec Freezes (declared-weight credit debit at stage 15; cancelled-request
credit debit in full; guard-rejection non-debit; admission/credit field extension);
FR-002, FR-004, FR-005, FR-006, FR-007, FR-011, FR-012, FR-013, FR-014.

B4 `quota-do-rpc.md` is **not** rewritten.

---

## 1. Relationship to B4

B4 froze a separate stage-15 credit RPC that settles actual token and cost usage
(including partial usage on cancellation) on the same per-installation Durable Object as
admission. G2 **extends** that RPC with a `credits` debit and `PeriodCounters` with
`creditsUsed`. Existing `usage.tokens`, `usage.cost`, `partial`, `requestsUsed`,
`tokensUsed`, `costUsed`, and `inFlight` keep their meanings (A15; Delivery Plan §2.3).

There is still exactly one credit call per admitted request and exactly two Durable Object
round trips per admitted request lifecycle (admission then credit). No third trip (FR-013;
§4.3.3; delivery plan §6.4).

---

## 2. Credit RPC field `credits`

The debit is the capability’s declared price in AI credits per request — per leg for
`conversational` — taken from the already-resolved manifest `Economics.quotaWeight`
(§5.1; A15). The request path never sees a price. No provider price appears in the Worker
(FR-014).

```ts
interface CreditRequest {
  kind: "credit";
  installationId: string;
  requestId: string;
  requestReference: string;
  usage: { tokens: number; cost: number };
  partial: boolean;
  credits: number; // G2 — declared quota_weight debit
  idempotencyState?: "completed" | "failed" | "cancelled";
  terminalErrorCode?: TaxonomyCode;
  entitlement?: EntitlementSnapshot;
}
```

Stage-15 callers (`CreditInput` → `creditUsage`) set `credits` from the resolved
`quotaWeight` they already hold. The Quota DO does not load a manifest.

On `ok: true`, the DO **adds** `credits` to `periodCounters.creditsUsed` in the same
read-modify-write that already adds `usage.tokens` / `usage.cost` and increments
`requestsUsed` by 1. Token and cost counters remain reconciliation and billing evidence;
they do **not** determine the credit debit (FR-002, FR-005, FR-011).

---

## 3. Period counter `creditsUsed`

```ts
interface PeriodCounters {
  requestsUsed: number;
  tokensUsed: number;
  costUsed: number;
  creditsUsed: number; // G2 — credits consumed in the current monthly period
  inFlight: number;
}
```

Period rollover (B4 `maybeResetPeriod`) resets `creditsUsed` with the other usage
counters; `inFlight` is still carried across. Token and cost counters remain alongside
`creditsUsed` for reconciliation (A15; §4.3.3).

G3 reads current-period credits consumed from this counter. This slice does not expose a
usage endpoint.

---

## 4. Debit rules

| Case | `credits` debit | Token / cost counters |
| --- | --- | --- |
| Completed request, declared weight W | Exactly W (`creditsUsed` += W) | Settle provider-reported actuals unchanged |
| Conversational leg, declared weight W | W **per credited leg** (two legs → 2W, not one conversation-level debit) | Per-leg actuals |
| Cancelled after the provider call has begun (`partial: true`) | Full declared W | Settle **partial** actuals |
| Guard rejection (including credit-budget exhaustion at admission) | None — credit RPC is **not invoked** | None — no journal row |

A conversational leg is one independently admitted request and therefore one stage-15
credit call. Per-leg debit does not require a conversation entity (H3; spec Assumptions).

`partial` does not change the **credit** arithmetic — the declared weight is always
debited in full when credit runs. `partial` still selects idempotency close
(`cancelled` vs `completed`) and still carries partial token/cost actuals (B4 meaning
kept).

---

## 5. Guard-rejection non-debit

A guard rejection debits nothing because no request exists (A15). Credit is not invoked.
No `ai_request` row is written (inherited C3 / delivery plan §6.4). Exhaustion at
admission is this case for credits: there is no request to settle.

This slice asserts that invariant; it does not rewrite the journal writer.

---

## 6. Two-round-trip budget

| Call | Stage | Count |
| --- | --- | --- |
| Admission RPC | 8 | 1 |
| Credit RPC | 15 | 1 |
| **Total per admitted request** | | **2** |

No third trip for credits, replay, or the degraded decision. The new `credits` field does
not change the meaning of any existing credit-RPC field and does not add I/O.

---

## 7. Consumers

| Slice | Binding |
| --- | --- |
| **G3** | Reads `creditsUsed` (live from the Quota DO) against snapshot `credit_budget` |
| **G4** | Token and cost actuals this call still settles remain reconciliation input; this slice does not write `invoice` |

---

## 8. Verification

Enforced by G2 tests in `ai-platform/test/quota-do.test.ts` (DO unit) and
`ai-platform/test/admission-credit.test.ts` (B4 `createDoSpy(env.DO)`):

| Test | Asserts |
| --- | --- |
| `credit_debits_declared_quota_weight` | `creditsUsed` increases by exactly W |
| `conversational_leg_debits_per_leg` | Two legs → 2W |
| `cancelled_request_debits_full_declared_weight` | `partial: true` still debits full W |
| `token_and_cost_counters_settle_actuals_unchanged` | Token/cost follow `usage`, including partial; they do not set `credits` |
| `credit_rpc_gains_fields_without_changing_existing_meanings` | `credits` / `creditsUsed` added; existing fields keep meanings |
| `guard_rejection_debits_nothing_and_writes_no_journal_row` | No credit RPC; no `ai_request` row |
| `exactly_two_durable_object_round_trips_per_request` | Spy `fetchCount === 2` |
