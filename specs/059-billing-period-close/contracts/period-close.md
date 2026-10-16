# Contract: Scheduled billing period close (G4)

**Frozen by:** Slice G4 — Billing period close and invoice generation
**Implements:** §4.5 Billing, §7.3, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices may **extend** this contract; they may not **rewrite** it
(Delivery Plan §2.3).

**Source of truth in code:** `ai-platform/src/period-close/index.ts` (`runPeriodClose`);
Worker `scheduled` handler in `ai-platform/src/worker.ts`; cron in `ai-platform/wrangler.toml`.

**Traces to:** spec FR-006–FR-012, FR-017, FR-018, FR-021, FR-023–FR-025; Freezes in `spec.md`
Slice Contract (*Scheduled billing period close*).

**Consumes (unchanged):** F3 `src/rollup/` production; G1 `credit_price` table shape and
`entitlement.status`.

---

## 1. Overview

A scheduled job in the existing Worker freezes the calendar month's `usage_rollup` (reads it as
evidence; does not rewrite F3 rows) and writes exactly one immutable `invoice` per `active`
installation, priced through the `credit_price` version active for that period. The close is a
**new** scheduled job; it is not a change to F3's `src/rollup/` production job (Delivery Plan
§3.13). It is not operator-authenticated HTTP.

---

## 2. Job surface

| Property | Value |
| --- | --- |
| **Module** | `ai-platform/src/period-close/index.ts` — **not** `src/rollup/` |
| **Entry** | `runPeriodClose({ db, period })` where `period` is `YYYY-MM` |
| **Production schedule** | Worker cron `"0 5 1 * *"` (05:00 UTC on the 1st). The handler derives the **previous** UTC calendar month from `scheduledTime` and calls `runPeriodClose`. Tests inject `period`. |
| **Existing crons** | F3 `"0 3 * * *"` (retention) and `"0 4 * * *"` (rollup) are unchanged |
| **Deployable** | Existing Worker only (FR-021) |

---

## 3. Close algorithm

For the given `period`:

1. Load installations whose `entitlement.status` is `active`.
2. Resolve the `credit_price` version active for the period: the latest row whose `active_from`
   is at or before the period start (`{period}-01T00:00:00.000Z`). A version whose `active_from`
   falls inside or after the period MUST NOT apply (FR-023, FR-025).
3. If no such row exists, issue **no** `invoice` for the period — the same outcome shape as
   zero consumption. Invent no default price or currency. Emit no new diagnostic code (FR-024).
4. For each `active` installation, sum `usage_rollup.quota_weight` for that installation and
   period. Tokens and cost on the rollup MUST NOT determine the invoice debit (FR-010).
5. If the sum is zero (or there are no matching rollup rows), issue **no** `invoice` for that
   installation (FR-012).
6. Otherwise INSERT exactly one `invoice` row: installation, period, credits consumed, credit
   price list version, total (`credits_consumed * price_per_credit`), status `"issued"`,
   `issued_at`. Priced through `credit_price`, not `src/pricing/` (FR-017, FR-018).
7. A re-run is idempotent: `ON CONFLICT (installation_id, period) DO NOTHING` — no second row,
   no mutation of the existing row (FR-011).
8. Do not INSERT/UPDATE/DELETE `usage_rollup`. Do not call `runRollup` (FR-006).
9. Make no payment-provider call (FR-019).

Two `active` installations with consumption produce two invoices; none combine installations
(FR-007).

---

## 4. Prohibitions

- Must not change F3 `src/rollup/` cadence, reconciliation, retention, or support lookup.
- Must not import or call `src/pricing/` (`priceUsage`, `ledgerUsageFromProvider`, `ratesForModel`).
- Must not add a freeze column on `usage_rollup` or an `invoice_line` table.
- Must not expose period close as an Entitlement-management HTTP mutation.
- Must not write into Supabase.
- Must not put a price on the request path.
