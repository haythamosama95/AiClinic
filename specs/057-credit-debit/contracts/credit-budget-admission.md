# Contract: Credit-budget admission extension (G2)

**Frozen by:** Slice G2 — Declared-weight credit debit in admission
**Implements:** §4.3.3, §8.8, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Extends:** B4 `specs/024-quota-do-admission/contracts/quota-do-rpc.md` (entitlement snapshot
and remaining-budget answer); F4
`specs/042-soft-threshold-degraded-routing/contracts/soft-threshold-admission.md`
(which ratio sets `degraded`)
**Status:** Frozen. Later slices may **extend** these fields; they may not **rewrite** them
(Delivery Plan §2.3). G3 reads current-period credits consumed from the Quota DO.

**Source of truth in code:** `ai-platform/src/quota-do/index.ts` (`EntitlementSnapshot`,
`isQuotaExhausted`, `isSoftThresholdCrossed`, `admissionRPC`);
`ai-platform/src/admission/index.ts` (`mapEntitlementSnapshot`, stage-8 mapping).

**Traces to:** spec Freezes (credit-budget admission; credit-ratio soft threshold;
admission/credit field extension); FR-001, FR-003, FR-008, FR-009, FR-010, FR-012, FR-015.

B4 `quota-do-rpc.md` and F4 `soft-threshold-admission.md` / `degraded-routing-signal.md`
are **not** rewritten.

---

## 1. Relationship to B4 and F4

B4 froze the admission RPC that answers the four installation-scoped questions in one
Durable Object round trip, including remaining budget. F4 froze `{ allowed, degraded: true }`
when remaining budget is not exhausted but the entitlement soft threshold has been crossed,
and the routing that consumes that flag.

G2 **extends** remaining-budget to the monthly credit budget G1 persisted as snapshot
`credit_budget`, and **sets** `degraded` from the credit ratio. It does **not** rewrite:
the four questions, the one-then-one round-trip budget, replay, idempotency, concurrency,
ephemeral store, fail-open grace, F4’s `routing_tier` / `degraded_notice` path, or B3
`rate_limited`.

---

## 2. Entitlement snapshot field `credit_budget`

G1 froze the D1 column and the admission snapshot **name** `credit_budget`. G2 is the first
slice to put that name on B4’s `EntitlementSnapshot`. Adding the field is extension; no
existing snapshot field changes meaning (A15; Delivery Plan §2.3).

```ts
interface EntitlementSnapshot {
  plan: string;
  period_bounds: {
    period_start: string;
    period_end: string;
  };
  request_quota: number;
  token_cost_budget: {
    token_budget: number;
    cost_budget: number;
  };
  credit_budget: number; // G2 — monthly AI-credit budget (G1 column)
  allowed_capabilities: string[];
  soft_threshold: number;
  status: string;
}
```

Stage-8 loads the row through A5 `loadConfig(cache, reader, "entitlements", installationId)`
and copies `credit_budget` in `mapEntitlementSnapshot`. The Quota DO treats the snapshot as
read-only input. This slice does not write D1.

---

## 3. Remaining-budget answer

The per-installation budget answered at admission is denominated in **AI credits** on a
monthly period (FR-001; §4.3.3; A15). There is no overage.

Evaluated inside the same atomic admission read-modify-write, in B4’s existing order
(replay → idempotent → **budget exhausted** → concurrency → admitted):

| Dimension | Exhausted when | Meaning |
| --- | --- | --- |
| Request-count guard | `periodCounters.requestsUsed >= entitlement.request_quota` | B4’s existing remaining-budget meaning — **kept** |
| Credit budget | `periodCounters.creditsUsed >= entitlement.credit_budget` | G2 — monthly AI-credit budget |
| Tokens | — | Settlement-only (A15). Not remaining-budget |
| Cost | — | Settlement-only (A15). Not remaining-budget |

Rate limiting (B3) and the token-denominated cost ceiling (C2) stay separate. G2 does not
fold either into the credit remaining-budget answer (FR-015).

On exhaustion the DO still returns B4’s outcome:

```ts
interface AdmissionQuotaExhausted {
  kind: "admission";
  outcome: "quota_exhausted";
  period_end: string; // entitlement.period_bounds.period_end
}
```

Stage-8 maps `period_end` onto A2 `periodReset`. The client-facing supplementary field is
`period_reset` — the `{ reset_at }` in §8.8. G2 does not invent a DO field named `reset_at`
(F4 already froze this chain).

Quota exhaustion never hard-locks: the additive AI feature is refused and says so; non-AI
workflows remain fully usable (FR-010; constitution V). An operator raises the budget (G1
Entitlement management, not this slice).

---

## 4. Credit-ratio soft threshold

Evaluated **after** hard exhaustion is ruled out and **before** a plain `admitted` return
(still inside the single admission round trip). G2 applies F4’s used/budget comparison to
the **credit ratio** only:

| Dimension | Used | Budget |
| --- | --- | --- |
| Credits | `periodCounters.creditsUsed` | `entitlement.credit_budget` |

Rules inherited from F4, applied to that ratio:

- `soft_threshold` is a fraction of period budget in `[0, 1]`; `0` never degrades (enroll
  sentinel). Out-of-range values coerce to `0`. Early-return when
  `!(threshold > 0) || threshold > 1`.
- A dimension with budget `0` never contributes a crossing (`credit_budget > 0` required).
- Crossed when `creditsUsed / credit_budget >= soft_threshold` while hard exhaustion is
  false.

Token and cost counters do **not** determine the soft-threshold decision (FR-011; A15).
Request-quota remains a hard remaining-budget dimension (section 3) and does not set
`degraded`.

When crossed with credit budget remaining:

```ts
interface AdmissionAdmitted {
  kind: "admission";
  outcome: "admitted";
  requestId: string;
  degraded?: boolean; // true when the credit ratio has crossed soft_threshold
}
```

This is the flag F4 already routes on. G2 sets it; G2 does not implement `routing_tier` or
`degraded_notice`. Below-threshold allow omits `degraded` (or leaves it false). Soft-threshold
evaluation must not add a second Quota DO round trip (FR-013; F4 FR-009).

**Conscious acceptance (§4.3.3):** in-flight admissions do not count toward the credit
ratio — `creditsUsed` increments only on credit; no pre-flight reservations.

---

## 5. §8.8 branches this slice owns

| Branch | Admission answer | Client |
| --- | --- | --- |
| Credit budget exhausted | `quota_exhausted` + `period_end` | `quota_exhausted` `{ reset_at }` |
| Soft threshold crossed, credit budget remaining | `{ admitted, degraded: true }` | F4 routes (`routing_tier = degraded`) |
| Credit ratio below threshold, budget remaining | `{ admitted }` without `degraded` | Normal allow |

`rate_limited` remains B3. Exhaustion at admission is a guard rejection: no request exists,
so stage 15 is not invoked (see [`credit-rpc-debit.md`](./credit-rpc-debit.md)).

---

## 6. Consumers

| Slice | Binding |
| --- | --- |
| **G3** | Reads current-period credits consumed against `credit_budget` live from the Quota DO (`creditsUsed` is frozen in [`credit-rpc-debit.md`](./credit-rpc-debit.md)) |
| **F4 routing** | Continues to consume `degraded` on `admitted`; G2 only changes which ratio sets the flag |

---

## 7. Verification

Enforced by G2 DO unit cases in `ai-platform/test/quota-do.test.ts`:

| Test | Asserts |
| --- | --- |
| `credit_budget_exhausted_quota_exhausted_with_reset_at` | Exhausted credit budget → `quota_exhausted` with `period_end`; no overage |
| `credit_ratio_soft_threshold_sets_degraded_flag` | Credit ratio crossed + budget remaining → `{ admitted, degraded: true }` |
| `below_credit_soft_threshold_not_degraded` | Below threshold + budget remaining → admitted without `degraded` |
| `credit_rpc_gains_fields_without_changing_existing_meanings` | Snapshot gains `credit_budget`; existing snapshot fields keep their meanings |
