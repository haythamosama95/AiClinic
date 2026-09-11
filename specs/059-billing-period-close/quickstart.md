# Quickstart: Billing period close and invoice generation (G4)

G4 adds a scheduled calendar-month period close inside the existing Cloudflare AI Gateway Worker that freezes F3 `usage_rollup` as invoice evidence and writes exactly one immutable `invoice` per `active` installation, priced through the latest `credit_price` version whose `active_from` is at or before the period start. It is also the first writer that activates `credit_price` versions on G1's operator control plane; close never calls a payment provider and never uses `src/pricing/` for totals.

**Scope rule:** This quickstart covers **only slice G4**. It lists G4 files, G4 tests, and G4 commands — not prior-slice regression suites, combined platform counts, or files from earlier slices.

## 1. Architecture context

- **Delivery plan row:** G4 in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.13 — *Billing period close and invoice generation* (`Needs: G1, F3`). Done when a scheduled close freezes the period's `usage_rollup` and writes exactly one immutable `invoice` per active installation, priced through the `credit_price` version active for that period; re-runs are idempotent; zero-consumption periods issue no invoice; price-list activation is an audited operator mutation that never reprices a closed period; every invoice line traces to request references; no payment-provider integration exists.
- **Architecture sections:** `§7.3` (D1 shapes for `invoice`, `credit_price`, `usage_rollup` evidence, and `control_audit`), `§4.5` (control-plane Entitlement management and billing — operator price-list activation, no request-path price), `§12.3` (billing boundary — platform issues invoices; payment collection stays outside), and **A15** (credit-denominated monthly quota; latest `credit_price` with `active_from` at or before period start prices the close; request path never sees a price).
- **Spec delivered:** Forward-only additive `invoice` migration; scheduled `runPeriodClose` job (new `src/period-close/`, not an F3 rollup change); operator `POST /control/credit-price/activate` with audited `credit_price_activate` journaling; invoice evidence as `usage_rollup` lines traced through `usage_event` to `ai_request.request_reference`; fifteen named tests (eight scheduled-job, seven Workers integration including two spies).
- **Plan scoped:** `invoice` migration + schema snapshot + harness wipe; `src/period-close/index.ts`; Wrangler cron `"0 5 1 * *"` and Worker `scheduled` branch mapping `scheduledTime` to the previous UTC calendar month; `CreditPriceActivatePayload` and `handleCreditPriceActivate` wired through G1/B2 control dispatch; frozen `contracts/` and `data-model.md`; Consumes G1 (`credit_price`, operator auth, audit) and F3 (`usage_rollup` read-only evidence) extended, not rewritten.

## 2. What was implemented

- **Additive `invoice` migration** — one immutable row per installation per calendar month (`PRIMARY KEY (installation_id, period)`); credits consumed, credit price list version, total, status, `issued_at`; no `invoice_line` table and no freeze column on `usage_rollup`.
- **Scheduled period-close job** — new `src/period-close/` module with `runPeriodClose({ db, period })`; reads `usage_rollup.quota_weight` SUM as credits consumed; resolves latest `credit_price` with `active_from` ≤ `{period}-01T00:00:00.000Z`; skips zero consumption or no applicable price list; `INSERT … ON CONFLICT DO NOTHING`; never UPDATEs issued rows or rewrites `usage_rollup`; does not import `src/rollup/` or `src/pricing/`.
- **Operator `credit_price` activation** — `POST /control/credit-price/activate` on G1's control plane inserts a `credit_price` row and journals `control_audit` with `action = credit_price_activate`; non-operator credentials get B2 `401 unauthorized`; activation never reprices closed invoices.
- **Worker cron wiring** — `wrangler.toml` appends `"0 5 1 * *"` (05:00 UTC on the 1st); `worker.ts` `scheduled` branch derives the **previous** UTC calendar month from `scheduledTime` and calls `runPeriodClose`.
- **Invoice evidence** — `usage_rollup` rows for the installation and period are the lines; trace through `usage_event.request_id` to `ai_request.request_reference`.
- **No payment-provider integration** — close and activation make no payment-provider `fetch`; production gains no payment-provider port.
- **`src/pricing/` unused for totals** — invoice `total` = `credits_consumed * price_per_credit` from the resolved `credit_price` version; ledger tokens/cost do not determine the debit.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/migrations/20260911200000_invoice.sql` | Forward-only `CREATE TABLE invoice` with natural key `(installation_id, period)` |
| `ai-platform/schema.snap.sql` | Pins the `invoice` table shape after the G4 migration |
| `ai-platform/src/period-close/index.ts` | `runPeriodClose` — active entitlements, rollup SUM, credit-price resolution, immutable INSERT |
| `ai-platform/src/control/credit-price.ts` | `handleCreditPriceActivate` — operator INSERT + `credit_price_activate` audit |
| `ai-platform/src/control/types.ts` | `CreditPriceActivatePayload` (`version`, price per credit, currency, `active_from`) |
| `ai-platform/src/control/index.ts` | `isControlRoute` / `dispatchControlRequest` for `POST /control/credit-price/activate` |
| `ai-platform/wrangler.toml` | `[triggers] crons` includes `"0 5 1 * *"` |
| `ai-platform/src/worker.ts` | `scheduled` branch maps cron `"0 5 1 * *"` + `scheduledTime` → previous UTC month → `runPeriodClose` |
| `ai-platform/test/period-close.test.ts` | Eight named scheduled-job cases: `close_one_invoice_per_active_installation` through `close_no_applicable_price_list_no_invoice` |
| `ai-platform/test/price-list-activation.test.ts` | Seven named integration cases (two spies): `price_list_activation_audited` through `invoice_prices_through_credit_price_not_token_rate_artifact` |
| `specs/059-billing-period-close/data-model.md` | `invoice` entity semantics and evidence binding |
| `specs/059-billing-period-close/contracts/invoice.md` | Frozen: issued invoice shape and immutability |
| `specs/059-billing-period-close/contracts/period-close.md` | Frozen: close job behaviour, idempotency, skip rules |
| `specs/059-billing-period-close/contracts/price-list-activation.md` | Frozen: operator activation route and audit |
| `specs/059-billing-period-close/contracts/invoice-evidence.md` | Frozen: rollup → usage_event → request_reference trace |

## 4. Prerequisites

- **Workers pool:** Node.js `>=22` and `ai-platform` dependencies (`npm install` in `ai-platform/`).
- **Operator bindings:** When exercising control e2e via `SELF.fetch` (price-list activation tests), Miniflare must expose `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID` (same as B2/G1 `plan-catalogue.test.ts`).

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run --config vitest.workers.config.ts test/period-close.test.ts
npx vitest run --config vitest.workers.config.ts test/price-list-activation.test.ts
```

Expected for this slice: **15 passing tests** — **8** in `period-close.test.ts` (`close_one_invoice_per_active_installation`, `close_one_invoice_each_of_two_active_installations`, `close_rerun_idempotent`, `close_zero_consumption_no_invoice`, `close_freezes_usage_rollup_without_rewriting_rows`, `close_prices_through_latest_version_active_at_period_start`, `mid_period_activation_does_not_apply_to_current_period`, `close_no_applicable_price_list_no_invoice`) and **7** in `price-list-activation.test.ts` (`price_list_activation_audited`, `price_list_activation_non_operator_rejected`, `price_list_activation_never_reprices_closed_period`, `invoice_resolves_to_usage_rollup`, `invoice_line_traces_to_request_references`, `no_payment_provider_call`, `invoice_prices_through_credit_price_not_token_rate_artifact`). Do not run `npm test` for the full platform suite.

To run a subset of this slice's tests:

```bash
npx vitest run --config vitest.workers.config.ts test/period-close.test.ts -t close_rerun_idempotent
npx vitest run --config vitest.workers.config.ts test/price-list-activation.test.ts -t price_list_activation_audited
```

## 6. Inspect the changes

1. Open `ai-platform/migrations/20260911200000_invoice.sql` — `invoice` columns and `PRIMARY KEY (installation_id, period)`.
2. Open `ai-platform/src/period-close/index.ts` — `SUM(usage_rollup.quota_weight)` for credits consumed; latest `credit_price` with `active_from` ≤ period start; `ON CONFLICT DO NOTHING`; no imports from `src/rollup/` or `src/pricing/`.
3. Open `ai-platform/src/control/credit-price.ts` — operator-gated INSERT and `control_audit` with `action = credit_price_activate`; no UPDATE of issued `invoice` rows.
4. Grep for close wiring and audit action:

```bash
cd ai-platform
rg 'invoice' migrations/20260911200000_invoice.sql src/period-close/ schema.snap.sql
rg 'credit_price_activate' src/control/credit-price.ts
rg '0 5 1 \* \*' wrangler.toml src/worker.ts
```

5. Confirm `src/rollup/` and `src/pricing/` are **not** used for close totals — `period-close/index.ts` has no rollup or pricing imports; spy test `invoice_prices_through_credit_price_not_token_rate_artifact` asserts zero calls to `priceUsage`, `ledgerUsageFromProvider`, and `ratesForModel`.
6. Read the frozen contracts and data model — `specs/059-billing-period-close/contracts/` and `specs/059-billing-period-close/data-model.md`.
