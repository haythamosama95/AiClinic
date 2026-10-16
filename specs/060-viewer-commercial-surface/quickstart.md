# Quickstart: Viewer commercial surface and stage-X page (V4)

V4 extends the `ai-platform-viewer/` local-stack console with commercial pages that drive frozen G1 plan CRUD, a G3 credits-only usage gauge, G4 invoice list/detail via local D1 inspect, and a stage-X page for cron ticks and HTTP failure-journey operations — all with V3's raw request/response inspector visible for every operation.

**Scope rule:** This quickstart covers **only slice V4**. It lists V4 files, V4 tests, and V4 commands — not prior-slice regression suites, combined platform counts, or files from earlier slices.

## 1. Architecture context

- **Delivery plan row:** V4 in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.14 — *Viewer commercial surface and stage-X page*. Canonical: `— (tooling; drives A15 surfaces)`. Needs: V3, G1, G3, G4. Done when the viewer gains plan-catalogue CRUD against G1's control mutations, a per-installation credit gauge reading G3's endpoint, an invoice list/detail view over G4's output, and drivable stage-X cron and failure journeys — everything against the local stack with raw request/response visible (§3.12.11 row V4 *Viewer build + smoke*).
- **Spec delivered:** Four new viewer surfaces (`/plans`, `/usage`, `/invoices`, `/stage-x`) that extend V3 without rewriting stages 00–12, guard-pipeline, or secrets. Plan catalogue drives the three G1 POST mutations with frozen `plan` columns and shows G1/B2 `401` raw bodies when credentials are missing. Credit gauge reads installation-authenticated `GET /v1/usage` and renders credits-only consumed-versus-budget. Invoice list/detail read issued G4 `invoice` rows and rollup evidence through viewer-only `wrangler d1 execute --local` inspect (no Worker invoice GET). Stage-X exposes cron triggers and HTTP failure-journey cards from the catalog. Seven named Viewer build + smoke tests.
- **Plan scoped:** Extend `ai-platform-viewer/` only — new `NavSection` members, catalog files, `JourneyStagePage` wrappers, `credit-gauge.ts` parser, `server/d1-inspect.ts` SQL runners, `/api/dev/invoices` routes, Vitest harness, and three smoke test files. Consumes V3 `sendJourneyRequest` / `RequestInspector`, G1 plan POSTs, G3 `GET /v1/usage`, and G4 D1 invoice/evidence SQL. No `ai-platform/`, `frontend/`, or `backend/` change; no Worker/D1/Flutter contract freeze.

## 2. What was implemented

- **Plan-catalogue CRUD cards** — three `JourneyOperationDefinition` cards POST to G1's `POST /control/plans/create`, `POST /control/plans/{name}/update`, and `POST /control/plans/{name}/delete` through V3's `/gateway` with operator bearer; missing credentials show frozen `401` `{"error":"unauthorized"}` as raw response. No `GET /control/plans`.
- **Credits-only gauge** — one `GET /v1/usage` card with installation AAT; `credit-gauge.ts` / `CreditGauge` render `current_period.credits_used` against `current_period.credit_budget` only — no token, cost, or price fields; no `GET /control/installations/:id/quota`.
- **Invoice list/detail via local D1 inspect** — `server/d1-inspect.ts` runs fixed list and evidence SQL through `npx wrangler d1 execute ai-platform-development --local --env development`; `/api/dev/invoices` and `/api/dev/invoices/detail` wrap SQL + JSON into V3 `HttpExchange` for `RequestInspector`. No Worker invoice GET.
- **Stage-X cron and HTTP failure-journey cards** — `GET /cdn-cgi/handler/scheduled?cron=` for retention (`0 3 * * *`), rollup (`0 4 * * *`), G4 period close (`0 5 1 * *`), and unknown-cron fallthrough (`0 5 * * *`); HTTP cards for `GET /v1/requests/{request_reference}` and `POST /control/support/lookup?reference=` (SX-054 / SX-055). Stage-0 scheduled card and stage 12 lookup cards are not rewritten.
- **No Worker/D1/Flutter contract change** — `ai-platform/src/`, G1/G3/G4 frozen contracts, and V3 stage 00–12 / guard-pipeline / secrets pages stay untouched.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform-viewer/package.json` | Vitest devDependency and slice test script |
| `ai-platform-viewer/vitest.config.ts` | Node smoke harness for Viewer build + smoke |
| `ai-platform-viewer/src/types.ts` | `NavSection` widened with `plans`, `usage`, `invoices`, `stage-x` |
| `ai-platform-viewer/src/lib/routes.ts` | Paths `/plans`, `/usage`, `/invoices`, `/stage-x` |
| `ai-platform-viewer/src/components/SideNav.tsx` | Commercial + stage-X nav items after V3 stages |
| `ai-platform-viewer/src/components/AppShell.tsx` | Mounts `PlansPage`, `UsageGaugePage`, `InvoicesPage`, `StageXPage` |
| `ai-platform-viewer/src/catalog/commercial-plans.ts` | Three G1 POST cards (create / update / delete) |
| `ai-platform-viewer/src/components/PlansPage.tsx` | `JourneyStagePage` over plan-catalogue cards |
| `ai-platform-viewer/src/catalog/commercial-usage.ts` | `GET /v1/usage` card with installation AAT |
| `ai-platform-viewer/src/lib/credit-gauge.ts` | Parses G3 JSON to credits-only current-period model |
| `ai-platform-viewer/src/components/CreditGauge.tsx` | Renders consumed versus budget only |
| `ai-platform-viewer/src/components/UsageGaugePage.tsx` | Gauge + V3 raw inspector for usage |
| `ai-platform-viewer/server/d1-inspect.ts` | Fixed invoice list and evidence SQL via `wrangler d1 execute --local` |
| `ai-platform-viewer/server/dev-plugin.ts` | `/api/dev/invoices` and `/api/dev/invoices/detail` routes |
| `ai-platform-viewer/src/lib/dev-api.ts` | Client wrappers fetching inspect routes into `HttpExchange` |
| `ai-platform-viewer/src/catalog/commercial-invoices.ts` | List + detail local-D1 operations |
| `ai-platform-viewer/src/components/InvoicesPage.tsx` | `JourneyStagePage` over invoice inspect operations |
| `ai-platform-viewer/src/catalog/stage-x.ts` | Cron + HTTP failure-journey cards |
| `ai-platform-viewer/src/components/StageXPage.tsx` | `JourneyStagePage` over stage-X cards |
| `ai-platform-viewer/test/viewer-builds.test.ts` | `viewer_builds` |
| `ai-platform-viewer/test/commercial-pages.smoke.test.ts` | `plan_catalogue_crud_drives_g1_control_mutations`, `credit_gauge_renders_g3_consumed_versus_budget`, `invoice_list_renders_g4_invoices`, `invoice_detail_renders_g4_rollup_evidence` |
| `ai-platform-viewer/test/stage-x.smoke.test.ts` | `stage_x_cron_operations_drivable`, `stage_x_failure_journey_operations_drivable` |

## 4. Prerequisites

1. **Local Worker** — from `ai-platform/`, run `wrangler dev --test-scheduled` so cron smokes and stage-X scheduled triggers work (`127.0.0.1:8787`).
2. **Vite dev server** — from `ai-platform-viewer/`, run `npm run dev` for the human console (proxies `/gateway` to the Worker).
3. **Credentials** — operator bearer from `ai-platform/.dev.vars` for plan CRUD smokes; a minted installation AAT for `GET /v1/usage` smokes. Invoice list/detail smokes need local D1 only (`wrangler d1 execute --local`).

## 5. Run the automated suite

From `ai-platform-viewer/`:

```bash
npm install   # first time only
npx vitest run test/viewer-builds.test.ts
npx vitest run test/commercial-pages.smoke.test.ts
npx vitest run test/stage-x.smoke.test.ts
```

Expected for this slice: **7 passing tests** — `viewer_builds` (1); `plan_catalogue_crud_drives_g1_control_mutations`, `credit_gauge_renders_g3_consumed_versus_budget`, `invoice_list_renders_g4_invoices`, `invoice_detail_renders_g4_rollup_evidence` (4); `stage_x_cron_operations_drivable`, `stage_x_failure_journey_operations_drivable` (2). Do not run `npm test` for the full platform suite.

To run a subset of this slice's tests:

```bash
npx vitest run test/commercial-pages.smoke.test.ts -t plan_catalogue_crud_drives_g1_control_mutations
npx vitest run test/stage-x.smoke.test.ts -t stage_x_cron_operations_drivable
```

## 6. Inspect the changes

1. **Open the four new routes** in the viewer (`npm run dev` in `ai-platform-viewer/`): `/plans`, `/usage`, `/invoices`, `/stage-x`. Each page mounts `JourneyStagePage` / `RequestInspector` over its operation cards.

2. **Grep G1/G3 paths and D1 inspect:**

```bash
cd ai-platform-viewer
rg 'POST /control/plans|GET /v1/usage' src/catalog/
rg 'wrangler d1 execute' server/d1-inspect.ts server/dev-plugin.ts
```

3. **Confirm Worker product code is untouched** — no V4 edits under `ai-platform/src/`:

```bash
git diff --name-only -- ai-platform/src/
```

Expected: empty (no Worker invoice GET, no `GET /control/plans`, G1/G3/G4 contracts unchanged).

4. **Confirm V3 stage 00–12 files are untouched** — no rewrites to `src/catalog/stage-0-platform-boot.ts` or `src/catalog/stage-{1..12}-*.ts`, guard-pipeline, or secrets pages:

```bash
cd ai-platform-viewer
git diff --name-only -- src/catalog/stage-0-platform-boot.ts src/catalog/stage-*.ts
```

Expected: only new `src/catalog/stage-x.ts` (and commercial catalog files), not modifications to existing stage 00–12 catalogs.

## 7. Manual validation

The viewer is a human console beyond CI. With the local Worker (`wrangler dev --test-scheduled`) and Vite (`npm run dev` in `ai-platform-viewer/`) running:

1. **`/plans`** — run create, update, and delete cards; confirm each operation shows V3's raw request/response inspector with G1 POST bodies and responses (or frozen `401` without operator bearer).
2. **`/usage`** — with a minted installation AAT in session, run the `GET /v1/usage` card; confirm the credits-only gauge shows consumed versus budget and the raw inspector panel is populated. No token, cost, or price fields on the gauge.
3. **`/invoices`** — run list and detail operations; confirm the inspector shows the D1 SQL as request raw and JSON rows as response raw (frozen G4 invoice columns and rollup evidence).
4. **`/stage-x`** — run cron cards (retention, rollup, period close, unknown cron) and failure-journey HTTP cards; confirm raw request/response for each against the local stack.
