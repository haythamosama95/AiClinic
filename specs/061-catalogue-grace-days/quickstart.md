# Quickstart: Catalogue price/display/`grace_days`, `credit_price` withdrawal, plan-delete fix (M1)

M1 lands A17 subscription price, display copy, and `grace_days` on the platform `plan`
catalogue, withdraws `credit_price` (table + control activate path), and fixes plan delete so
the catalogue row is actually removed — all inside the Cloudflare AI Gateway Worker.

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the G1 baseline". Slice-floor regression (§3.12)
belongs in the implement Verification task; the band verification matrix (§3.2.1) is
implemented via `/abo-verify`, not in `quickstart.md`.

## 1. Architecture context

- **Delivery-plan row:** M1 in
  [`../../docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md`](../../docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md)
  §3.2 — *Catalogue price/display/`grace_days` columns, `credit_price` withdrawal, plan-delete
  fix* (`Needs: G1`).
- **Implements:** AP-ARCH A17 items 1–2, A15 item 4 (as updated by A17); ABO §4.1.6, §4.2,
  §5.10 (column shape only — endpoint is P2). See
  [`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)
  §2.11 and
  [`../../docs/architecture/ai-billing-orchestration/architecture/04-data-model.md`](../../docs/architecture/ai-billing-orchestration/architecture/04-data-model.md)
  §4.1.6 / `plan` column additions.
- **Spec delivered:** Forward-only migration adding A17 columns and dropping `credit_price`;
  control-plane plan CRUD carrying the new fields with `control_audit`; credit-price module and
  route gone; plan delete removes the row; three §3.12.1 floor groups (Migration / Code / Bug
  fix).
- **Plan scoped:** One migration + snapshot; extend `plan.ts` / `PlanPayload`; delete
  `credit-price.ts` and unregister its route; strip `period-close` `credit_price` reads
  (temporary no invoices until M2); floor tests in `migrations.test.ts` and
  `plan-catalogue.test.ts`. See [`spec.md`](./spec.md) and [`plan.md`](./plan.md).

## 2. What was implemented

- **A17 catalogue columns** — `price_cents`, `currency`, `display_name`, `description`,
  `grace_days INTEGER NOT NULL DEFAULT 7` on `plan`.
- **`credit_price` withdrawal** — table dropped; `src/control/credit-price.ts` deleted; route
  and `CreditPriceActivatePayload` removed; no matching references left in `ai-platform/src/`.
- **Plan CRUD** — create/update round-trip A17 fields with `control_audit`; validation and
  auth behaviour per FR-009–FR-012 / FR-016.
- **Plan-delete fix** — `POST /control/plans/{name}/delete` deletes the row and writes
  `plan_delete` audit.
- **Period-close interim** — no `credit_price` reads; no invoices until M2 (not M2 pricing).

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability. Entity binding: [`data-model.md`](./data-model.md).

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/migrations/20260923120000_catalogue_grace_days.sql` | Forward-only A17 `ALTER` + `DROP TABLE credit_price` |
| `ai-platform/schema.snap.sql` | Pinned post-M1 schema (A17 columns; no `credit_price`) |
| `ai-platform/src/control/plan.ts` | A17 create/update fields; delete removes the row |
| `ai-platform/src/control/types.ts` | Extended `PlanPayload`; `CreditPriceActivatePayload` removed |
| `ai-platform/src/control/index.ts` | Credit-price route/export removed |
| `ai-platform/src/period-close/index.ts` | `credit_price` reads removed (interim until M2) |
| `ai-platform/test/migrations.test.ts` | M1 — Migration floor |
| `ai-platform/test/plan-catalogue.test.ts` | M1 — Code + Bug fix floor |

## 4. Prerequisites

- **Workers pool:** Node.js `>=22` and `ai-platform` dependencies (`npm install` in
  `ai-platform/`).
- **Operator bindings:** When exercising control e2e via `SELF.fetch`, Miniflare must expose
  `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID` (same as G1/B2).

## 5. Run the automated suite

From the repository root — **slice-only** commands:

```bash
cd ai-platform && npx vitest run test/migrations.test.ts
cd ai-platform && npx vitest run --config vitest.workers.config.ts test/plan-catalogue.test.ts
```

If implement also adjusts G4 fallout suites for the withdrawn table/endpoint, run those named
files only (do not run full-suite `npm test` or Band M e2e/x-e2e here):

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts test/price-list-activation.test.ts test/period-close.test.ts
```

Expected: Migration + Code + Bug fix floor cases green for this slice. Band verification
(§3.2.1) is `/abo-verify`, not this quickstart.

## 6. Inspect the changes

- Open the M1 migration and confirm `grace_days INTEGER NOT NULL DEFAULT 7` and
  `DROP TABLE credit_price`.
- Open `handlePlanDelete` and confirm the D1 batch includes `DELETE FROM plan` plus
  `plan_delete` audit.
- Grep `ai-platform/src/` for `credit_price`, `CreditPriceActivatePayload`, and
  `credit-price` — expect zero hits; `credit-price.ts` absent.
- Confirm G1 economics columns and assign/enroll handlers were not rewritten; no
  `GET /v1/plans` route added.
