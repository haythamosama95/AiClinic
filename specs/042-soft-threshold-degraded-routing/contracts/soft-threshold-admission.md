# Contract: Soft-threshold admission answer extension (F4)

**Frozen by:** Slice F4 — Soft-threshold degraded routing  
**Implements:** §4.3.3, §8.8 of `docs/architecture/17-ai-platform.md`  
**Extends:** B4 `specs/024-quota-do-admission/contracts/quota-do-rpc.md` (admission response only)  
**Status:** Frozen. Later slices may extend these fields and may not rewrite the soft/hard
branches below (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/quota-do/index.ts` (admission soft/hard branches);
`ai-platform/src/admission/index.ts` (stage-8 mapping onto gateway outcomes and A2
`period_reset`).

**Traces to:** spec Freezes (soft-threshold admission outcome; hard-exhaustion non-lockout /
period reset); FR-001, FR-003, FR-005, FR-009, FR-010.

---

## 1. Relationship to B4

B4 froze the admission RPC that answers the four installation-scoped questions in one Durable
Object round trip, and hard budget exhaustion → `quota_exhausted`. F4 **extends** the allow path
with the soft-threshold `{ degraded }` branch B4 deferred, and threads the entitlement period end
onto hard exhaustion so the gateway can populate A2's frozen `period_reset` supplementary field.

F4 does **not** rewrite: the four questions, credit RPC, ephemeral store, fail-open grace,
`GRACE_ADMISSION_CAP`, evaluation order of replay / idempotent / concurrency, or the one-round-trip
budget (B4 Freezes; delivery plan §6.4).

---

## 2. Soft-threshold evaluation (inside the same admission RPC)

Evaluated **after** hard budget exhaustion is ruled out and **before** a plain `admitted` return
(still inside the single atomic admission read-modify-write). Soft threshold is the entitlement
snapshot field B4 already carries unchanged (`EntitlementSnapshot.soft_threshold` — a fraction of
period budget; §8.1 enroll note: soft threshold is a fraction of the budget).

Under Open Decision 2's recommended default (cost-based budget with a request-count guard), soft
threshold is crossed when any **positive** period budget dimension has
`used / budget >= soft_threshold`, while hard exhaustion remains false:

| Dimension | Used (DO counters) | Budget (entitlement) |
| --- | --- | --- |
| Requests | `periodCounters.requestsUsed` | `entitlement.request_quota` |
| Tokens | `periodCounters.tokensUsed` | `entitlement.token_cost_budget.token_budget` |
| Cost | `periodCounters.costUsed` | `entitlement.token_cost_budget.cost_budget` |

A dimension with budget `0` never contributes a soft-threshold crossing (enroll's zero-budget /
zero-threshold case never degrades). Hard exhaustion continues to use B4's existing
`isQuotaExhausted` predicate unchanged.

Soft-threshold evaluation **must not** add a second Quota DO round trip (FR-009).

---

## 3. Extended admission response shapes

### 3.1 Soft-threshold allow — `{ allowed, degraded: true }`

When budget remains and soft threshold is crossed, the DO still returns `outcome: "admitted"`
(request is allowed) and sets `degraded: true`:

```ts
interface AdmissionAdmitted {
  kind: "admission";
  outcome: "admitted";
  requestId: string;
  degraded?: boolean; // F4: true when soft threshold crossed; omitted/false otherwise
}
```

Stage-8 maps this to a gateway success that carries `degraded: true`. Below-threshold allow keeps
`degraded` absent or `false` (FR-010).

### 3.2 Hard exhaustion — period reset carrier

When budget is exhausted, the DO returns `outcome: "quota_exhausted"` and includes the period end
already present on the entitlement snapshot the DO reads for the admission decision:

```ts
interface AdmissionQuotaExhausted {
  kind: "admission";
  outcome: "quota_exhausted";
  period_end: string; // ISO-8601 — entitlement.period_bounds.period_end
}
```

Stage-8 maps `period_end` onto A2's supplementary field input `periodReset`. On the wire the
client sees `quota_exhausted` with supplementary `period_reset` (A2 Freezes). The §8.8 diagram's
`{ reset_at }` is that same value — F4 does not invent a `reset_at` field name (FR-003).

`consumed` / `limit` appear in the §8.8 diagram for narrative clarity; F4's Freezes and FR-003
require only the period-reset carrier. F4 does not add further supplementary fields.

---

## 4. Stage-8 gateway outcomes (admission caller)

| DO outcome | Gateway result | Client-facing taxonomy |
| --- | --- | --- |
| `admitted` (`degraded` absent/false) | allow, `routing_tier = standard` | stream may open `accepted` without `degraded_notice` |
| `admitted` (`degraded: true`) | allow, `routing_tier = degraded` | `accepted { degraded_notice: true }` |
| `quota_exhausted` + `period_end` | refuse | `quota_exhausted` + `period_reset` = `period_end` |

Hard exhaustion disables the additive AI feature path (refusal with clear taxonomy reason) and never
hard-locks clinical or non-AI workflows (FR-001, FR-004; constitution V). Rate-limit denial remains
B3 and is out of this contract.

---

## 5. Verification

Enforced by F4 integration suite (`ai-platform/test/soft-threshold-routing.test.ts`):

| Named test | Asserts |
| --- | --- |
| `soft_threshold_selects_degraded_target` | Soft crossed → `degraded: true` on allow |
| `hard_exhaustion_quota_exhausted_admin_path_no_lock` | Exhausted → `quota_exhausted` + `period_reset`; no product lock |
| `below_threshold_traffic_unaffected` | Below soft → no `degraded` |
| `soft_threshold_no_second_quota_do_round_trip` | Exactly one Quota DO fetch for soft-threshold admission |
| `quota_exhausted_only_error_code_on_hard_exhaustion` | Hard branch emits only `quota_exhausted` |
