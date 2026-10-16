# Contract: Usage-summary read (G3)

**Frozen by:** Slice G3 — Usage summary endpoint and in-app gauge
**Implements:** §7.6, §5.5 Usage summary, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices (V4) may **extend** this contract; they may not **rewrite**
the installation-facing audience, the live-versus-historical source split, or the credits-only
payload (Delivery Plan §2.3).

**Source of truth in code:** `ai-platform/src/usage-summary/index.ts`; `GET /v1/usage` dispatch
in `ai-platform/src/worker.ts`. Flutter consumer: `frontend/lib/core/ai/usage_summary_client.dart`.

**Traces to:** spec Freezes (usage-summary read endpoint; credits-only usage response);
FR-001, FR-002, FR-004, FR-006, FR-012, FR-013.

**Entity binding:** [`../data-model.md`](../data-model.md) (`usage_rollup.quota_weight`).

G2 `specs/057-credit-debit/contracts/credit-rpc-debit.md` and
`credit-budget-admission.md`, E4 `specs/038-first-ai-feature-surface/contracts/ai-availability-flag.md`,
and operator `GET /control/installations/:id/quota` are **not** rewritten.

---

## 1. Overview

An installation-authenticated, client-facing read that answers:

- **Current period** — credits consumed against budget, live from the Quota Durable Object
  (`creditsUsed` against snapshot `credit_budget`).
- **Prior periods** — credits from `usage_rollup`'s quota-weight aggregate
  (`usage_rollup.quota_weight` = pre-aggregated `SUM(usage_event.quota_weight)`).

Live and historical answers come from different places (§7.6). The response carries credits
only: no provider prices, no token or cost actuals. This is a different audience from the
operator-only quota inspect path; that route stays operator-only. The handler MAY reuse
`inspectRPC` internally for live current-period counters.

The architecture names the surface by sources and credits-only semantics (§5.5, §7.6). This
artifact names the wire without rewriting G2 counter meanings.

---

## 2. Route

| Field | Value |
| --- | --- |
| Method | `GET` |
| Path | `/v1/usage` |
| Installation id | **Never** on the path — the authenticated AAT `iss` is the installation |
| Query | None |

This is an **occasional** read, off the request-path latency budget (FR-012). It MUST NOT be
invoked from the capability request path and MUST NOT add a second Quota DO round trip or a
second R2 object per inference request.

---

## 3. Authentication

| Rule | Detail |
| --- | --- |
| Header | `Authorization: Bearer <AAT>` |
| Scope | Installation-scoped |
| Verifier | Same enrolled-key verifier as I2 discovery / submit (`EnrolledKeyVerifier` / §4.3.2 / §5.6) |

### 3.1 Failure

Missing `Authorization`, non-Bearer scheme, empty token, or an AAT the enrolled-key verifier
rejects as unauthenticated → closed taxonomy code `unauthenticated` (spec phrasing "taxonomy
unauthorized"; A2 closed set; HTTP 401 via `liveHttpStatusForCode("unauthenticated")`):

| Field | Value |
| --- | --- |
| HTTP status | `liveHttpStatusForCode("unauthenticated")` (401) |
| Body | Taxonomy error body (`buildErrorBody` with code `unauthenticated`) |
| Usage-summary body | **Absent** — no `{ current_period, prior_periods }` |

This is the only diagnostic this slice owns. `quota_exhausted` remains G2 admission and is
not emitted here.

---

## 4. Success response

HTTP 200. JSON object. Credits only.

```json
{
  "current_period": {
    "period": "2026-09",
    "credits_used": 12,
    "credit_budget": 10000
  },
  "prior_periods": [
    {
      "period": "2026-08",
      "credits_used": 800
    }
  ]
}
```

### 4.1 `current_period`

| JSON field | Type | Source | G2 name (unchanged) |
| --- | --- | --- | --- |
| `period` | string | Calendar-month key `YYYY-MM` from entitlement `period_start` via existing `periodFromIso` | — (A15 monthly period) |
| `credits_used` | number | Quota DO `inspectRPC` → `state.periodCounters.creditsUsed` | `creditsUsed` |
| `credit_budget` | number | Entitlement snapshot already mapped by G2 — config-cache kind `"entitlements"` column `credit_budget` | `credit_budget` |

MUST NOT be served from `usage_rollup`.

### 4.2 `prior_periods`

Array of prior calendar months for this installation, each:

| JSON field | Type | Source |
| --- | --- | --- |
| `period` | string | `usage_rollup.dimensions.period` |
| `credits_used` | number | `usage_rollup.quota_weight` |

MUST NOT be served from the Quota DO. MUST NOT be produced by scanning `usage_event`.
Rows whose `period` equals `current_period.period` are omitted from this array.

`credits_used` here is the quota-weight aggregate (AI credits), not tokens and not ledger
cost.

### 4.3 Prohibited fields

The object MUST NOT contain provider prices, token actuals (`tokens`, `tokens_used`,
`tokensUsed`, …), or cost actuals (`cost`, `cost_used`, `costUsed`, …). G2 token and cost
counters remain reconciliation evidence and stay off this payload.

---

## 5. Internal sources (not the operator route)

| Answer | Implementation |
| --- | --- |
| Live current-period `credits_used` | `env.DO.get(idFromName(installationId)).fetch` with `{ kind: "inspect" }` — reuse `inspectRPC`, do not expose `GET /control/installations/:id/quota` |
| Current-period `credit_budget` and period key | Config-cache entitlements row for that installation (G1 column / G2 snapshot name). Do not persist a new DO field |
| Prior-period credits | `SELECT` `usage_rollup` for this `installation_id` where `period` ≠ current period; read `quota_weight` |

The operator handler `src/control/quota-inspect.ts` stays operator-only and is not this
slice's response shape (it carries token/cost remaining, maps, and entitlement fields this
payload forbids).

---

## 6. Prohibitions

- Must not open the operator quota inspect route to installations.
- Must not debit, admit, or set `degraded` (Consumes G2).
- Must not scan `usage_event` on this read.
- Must not introduce a table.
- Must not rewrite F3 cadence, retention, purge, or reconciliation.
- Must not write clinic business data or open a write path into Supabase (FR-011).
- Must not add request-path I/O, a second request-path Quota DO round trip, a second R2
  object per request, retry, caching, or per-request server-side state.
