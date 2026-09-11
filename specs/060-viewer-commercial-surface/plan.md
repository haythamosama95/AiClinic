# Implementation Plan: Viewer commercial surface and stage-X page (V4)

**Branch**: `ai/060-v4-viewer-commercial-surface` | **Date**: 2026-09-11 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/060-viewer-commercial-surface/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

V4 extends the existing `ai-platform-viewer/` local-stack console with commercial pages that drive already-frozen G1 plan CRUD, G3 `GET /v1/usage` (credits-only gauge), and G4 issued `invoice` rows plus rollup evidence, and with a stage-X page that drives the catalog's cron ticks and HTTP-reachable failure-journey operations. It is Band V verification tooling (Delivery Plan §3.14, after V3 and Band G): it freezes no platform contract, ships to no clinic, and does not modify Worker, D1, or Flutter product code.

## Technical Context

**Language/Version**: TypeScript ~6.0 (`ai-platform-viewer/package.json`) with React 19 and Vite 8. Node `>=22` for the slice's Vitest smoke harness (same Node major as `ai-platform/`).

**Primary Dependencies**: V3 `ai-platform-viewer/` app (Vite, `/gateway` proxy to `http://127.0.0.1:8787`, `RequestInspector` / `HttpExchange`, `sendJourneyRequest`, `JourneyStagePage` / `JourneyOperationCard`, Vite `devApiPlugin` that already shells `npx wrangler d1 execute … --local`). G1 operator plan CRUD on the local Worker. G3 installation-authenticated `GET /v1/usage`. G4 `invoice` rows and evidence joins in local D1; G4 cron `"0 5 1 * *"`. No new npm runtime packages. Vitest is added as a **viewer-package** test runner so this slice can place §3.12.11 *Viewer build + smoke* files (V3 has no test tree). No Playwright, no Worker invoice GET, no `GET /control/plans`.

**Storage**: None owned by this slice. Invoice list/detail **read** G4's D1 `invoice` / `usage_rollup` / `usage_event` / `ai_request` via V3's `wrangler d1 execute --local` class inside the existing Vite `server/dev-plugin.ts` (viewer-only `/api/dev/…` routes — not Worker HTTP). Plan CRUD and usage reads go to the local Worker through V3's `/gateway` prefix. No new D1 entity, no Supabase write, no R2 write.

**Testing**: Viewer build + smoke (Delivery Plan §3.12.11 V4). `viewer_builds` runs `tsc -b && vite build` in `ai-platform-viewer/`. Remaining named tests call V3's send/inspector path (or the D1-inspect wrapper that produces the same `HttpExchange`) against the local stack: Worker at `127.0.0.1:8787` with `wrangler dev --test-scheduled` for cron; `wrangler d1 execute --local` for invoices. §13.5's table names **no** viewer row (tooling, not a §4 component); placement is the delivery-plan layer the spec already names. Suite is required, not optional (spec Test plan).

**Target Platform**: `ai-platform-viewer/` only. Local-stack client of G1/G3/G4. No `ai-platform/` product change, no `frontend/`, no `backend/`.

**Project Type**: Band V verification tooling (Delivery Plan §3.14). Not a clinic product and not a new deployable. Appears in no §4 component group.

**Performance Goals**: Off the inference hot path. No second Quota Durable Object round trip, no second D1 insert in the guard, no second R2 object per request (§6.1, §7.5, §13.6). No per-request server-side state. The viewer adds no retry, cache, or clinic error dialog (spec Edge Cases).

**Constraints**:
- Freeze none. Do not modify G1/G3/G4 contracts or V3 stages 00–12, guard-pipeline, or secrets (FR-015).
- Plan CRUD is the three G1 POSTs only — no `GET /control/plans` (spec Edge Cases).
- Gauge is credits-only `credits_used` vs `credit_budget` from `GET /v1/usage`; never `GET /control/installations/:id/quota` for this read (FR-005, FR-006, FR-012).
- Invoice list/detail use local D1 inspection; this slice MUST NOT add a Worker invoice GET (FR-009).
- Period close is driven as G4 cron `"0 5 1 * *"` through `GET /cdn-cgi/handler/scheduled?cron=`, not a `/control` POST (FR-010).
- Viewer emits no new diagnostic code; frozen G1/G3/catalog bodies appear as raw response (FR-004).
- Request path never sees a price; no payment-provider call (FR-013, FR-014).
- Do not start Band L.

**Scale/Scope**: Zero §4 components (see Components Touched). Four viewer surfaces (plan catalogue, credit gauge, invoice list/detail, stage-X) plus a viewer-only D1 inspect helper and seven named smoke tests. Roughly 18–22 tasks — under the ~25-task ceiling (delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified —
      the viewer ships to no clinic (Delivery Plan §3.14). Clinic commercial behaviour
      stays the A15 surfaces G1/G3/G4 already froze (small plan catalogue, credit
      gauge, platform-issued invoices with payment collection outside). This slice
      only makes those surfaces drivable on the local stack (spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — pages and a Vite `/api/dev`
      D1-inspect wrapper on the existing viewer; no new deployable, no Worker route.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated —
      this slice touches **`ai-platform-viewer/` only**. Flutter (`frontend/`),
      Supabase (`backend/`), and Worker product code (`ai-platform/`) are unchanged.
      **§14 acknowledgement:** the Worker remains an additive, non-primary component
      with no domain logic, no business data, and no write path into Supabase. A15's
      constitution check stands; the viewer is a local-stack client of frozen
      surfaces, not a clinic product.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — clinic
      Supabase integrity is untouched. Plan CRUD remains G1 operator mutations
      audited on `control_audit`. Invoice list/detail are reads of G4 D1 rows; they
      do not write invoices. No new D1 entity.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — plan CRUD uses operator bearer (B2/G1);
      the gauge uses installation AAT (G3); missing credentials surface frozen `401`
      bodies in the raw panel. Invoice inspect is a local-dev D1 read, not a new
      public Worker surface. No clinic table is written.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — the
      viewer is not on a clinic workflow. Worker unreachability is the V3 raw-panel
      transport failure. Nothing hard-locks (A15; constitution V).

*Re-checked after Phase 1 design: all boxes remain ticked. No Complexity Tracking row.*

## Project Structure

### Documentation (this feature)

```text
specs/060-viewer-commercial-surface/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify (authoritative; no ## Clarifications)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`research.md` is **never** produced on this platform — the research is
`docs/architecture/ai-platform/01-ai-platform.md`.

`data-model.md` is **not** produced — this slice defines no D1 entities (G1 `plan`, G3
rollup column, G4 `invoice` already exist).

`contracts/` is **not** produced — Freezes is none; later slices must not bind to a V4
wire shape.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — V4 row of the delivery plan (§3.14; Canonical
  `— (tooling; drives A15 surfaces)`); what the spec delivered; what this plan scoped.
- **§2 What was implemented** — plan-catalogue CRUD cards on G1 POSTs; credits-only
  gauge on `GET /v1/usage`; invoice list/detail via local D1 inspect; stage-X cron and
  HTTP failure-journey cards; no Worker/D1/Flutter contract change.
- **§3 Files to review** — only this slice's viewer catalogs, pages, D1-inspect helper,
  nav/route wiring, and this slice's smoke test files.
- **§4 Prerequisites** — local Worker with `wrangler dev --test-scheduled`; Vite
  (`npm run dev` in `ai-platform-viewer/`) for the human console; operator bearer and a
  minted AAT for HTTP smokes.
- **§5 Run the automated suite** — slice-only:
  `npx vitest run test/viewer-builds.test.ts`
  `npx vitest run test/commercial-pages.smoke.test.ts`
  `npx vitest run test/stage-x.smoke.test.ts`
  from `ai-platform-viewer/`; no full-suite `npm test`, no prior-slice counts.
- **§6 Inspect the changes** — open the four new routes; grep G1/G3 paths and
  `wrangler d1 execute`; confirm `ai-platform/src/` and V3 stage 00–12 files untouched.
- **§7 Manual validation** — the viewer is a human console beyond CI: open `/plans`,
  `/usage`, `/invoices`, `/stage-x` against the local stack and confirm each new
  operation shows V3's raw inspector (and the usage page shows the credits-only gauge).

### Source Code (repository root)

```text
ai-platform-viewer/
├── package.json                                 # MODIFIED — add vitest + slice test script
├── vitest.config.ts                             # NEW — Node smoke harness for this slice
├── vite.config.ts                               # UNCHANGED (V3 /gateway proxy + dev plugin)
├── server/
│   ├── dev-plugin.ts                            # MODIFIED — invoice D1 inspect routes (wrangler d1 execute --local)
│   └── d1-inspect.ts                            # NEW — fixed invoice list/detail SQL runners
├── src/
│   ├── types.ts                                 # MODIFIED — extend NavSection (do not rename existing members)
│   ├── App.tsx                                  # UNCHANGED
│   ├── index.css                                # MODIFIED only if new nav accents need existing token reuse
│   ├── lib/
│   │   ├── routes.ts                            # MODIFIED — /plans /usage /invoices /stage-x
│   │   ├── journey-api.ts                       # UNCHANGED (Consumes V3 sendJourneyRequest)
│   │   ├── raw-http.ts                          # UNCHANGED (Consumes V3 inspector payloads)
│   │   ├── gateway-api.ts                       # UNCHANGED
│   │   ├── dev-api.ts                           # MODIFIED — client wrappers for invoice D1 inspect
│   │   └── credit-gauge.ts                      # NEW — parse GET /v1/usage current_period credits-only
│   ├── catalog/
│   │   ├── journey-types.ts                     # UNCHANGED
│   │   ├── commercial-plans.ts                  # NEW — create/update/delete cards → G1 POSTs
│   │   ├── commercial-usage.ts                  # NEW — GET /v1/usage card
│   │   ├── commercial-invoices.ts               # NEW — list/detail local-D1 operations
│   │   ├── stage-x.ts                           # NEW — cron + HTTP failure-journey cards
│   │   ├── stage-0-platform-boot.ts             # UNCHANGED (do not rewrite the stage-0 scheduled card)
│   │   └── stage-{1..12}-*.ts                   # UNCHANGED
│   ├── components/
│   │   ├── AppShell.tsx                         # MODIFIED — mount four new pages
│   │   ├── SideNav.tsx                          # MODIFIED — add commercial + stage-X items
│   │   ├── JourneyStagePage.tsx                 # UNCHANGED (reuse)
│   │   ├── JourneyOperationCard.tsx             # UNCHANGED (reuse RequestInspector)
│   │   ├── RequestInspector.tsx                 # UNCHANGED
│   │   ├── PlansPage.tsx                        # NEW
│   │   ├── UsageGaugePage.tsx                   # NEW — gauge + inspector
│   │   ├── CreditGauge.tsx                      # NEW — credits_used vs credit_budget only
│   │   ├── InvoicesPage.tsx                     # NEW
│   │   └── StageXPage.tsx                       # NEW
│   └── context/SessionContext.tsx               # UNCHANGED (NavSection union widening is types.ts)
└── test/
    ├── viewer-builds.test.ts                    # NEW — viewer_builds
    ├── commercial-pages.smoke.test.ts           # NEW — plan CRUD, gauge, invoice list/detail
    └── stage-x.smoke.test.ts                    # NEW — cron + failure-journey drivability

ai-platform/                                     # UNCHANGED — G1/G3/G4 consumed, not rewritten
frontend/                                        # UNCHANGED — G3 Flutter gauge is out of scope
backend/                                         # UNCHANGED
```

**Structure Decision**: Extend V3's existing viewer module — new `NavSection` members, catalog
files, and `JourneyStagePage` wrappers — rather than a second app or a frozen viewer platform
contract. Invoice reads land as **viewer-only** `/api/dev/…` helpers that shell the same
`npx wrangler d1 execute ai-platform-development --local --env development` class V3 already
uses for platform reset, wrapping SQL + JSON into V3 `HttpExchange` for `RequestInspector`.
HTTP operations reuse `sendJourneyRequest` unchanged. Worker `ai-platform/` is not in the
source tree of this slice.

**Route/module split** (implementation choice, not a requirement): four nav sections
`plans` → `/plans`, `usage` → `/usage`, `invoices` → `/invoices`, `stage-x` → `/stage-x`,
appended after V3's stage 00–12 + guard-pipeline items. Do not merge commercial surfaces into
stage 4 or rewrite stage 0's single scheduled-handler card.

**Stage-X card inventory** (implementation choice, not a requirement; from
`docs/testing/catalog/stage-X-cron-and-failure-journeys.md`, which the spec already cites):

Cron operations (FR-010; catalog §1 local trigger `GET /cdn-cgi/handler/scheduled?cron=`):
- `"0 3 * * *"` retention
- `"0 4 * * *"` rollup
- `"0 5 1 * *"` G4 period close
- `"0 5 * * *"` unknown-cron fallthrough (catalog SX-003)

HTTP failure-journey operations drivable against the local stack (FR-011; catalog Actions
that are Worker HTTP, not in-process stubs):
- `GET /v1/requests/{request_reference}` — SX-054 journal-purged 404 and SX-055 Completed
  without `result`
- `POST /control/support/lookup?reference=` — SX-054 / SX-055 operator lookup

Not viewer cards (V1 E2E / in-process; adding them would require a new Worker surface or a
D1/DO shim, which this slice must not add): direct `runRetentionPurge`/`runRollupAndReconciliation`
clock injection, DO-namespace stubs, D1 SQL proxies, GatewayObject `quota-do.internal` method
and JSON guards (SX-057–SX-063), and injected-`now` DO sweeps (SX-046–SX-052). Those stay
catalog E2E. Grace/retention/rollup **journeys** are driven by the cron cards above; state
setup uses existing V3 stage pages. Do not rewrite stage 4's quota-inspect or stage 12's
lookup cards.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How V4 binds to it |
| --- | --- | --- |
| **V3 — Viewer foundations and stage pages** (`ai-platform-viewer/` builds; stages 00–12, guard-pipeline, secrets; raw request/response) | `ai-platform-viewer/package.json` (`tsc -b && vite build`); `src/lib/routes.ts`, `src/types.ts` `NavSection`; `src/lib/journey-api.ts` `sendJourneyRequest`; `src/lib/raw-http.ts` `buildRawRequest` / `buildRawResponse`; `src/components/RequestInspector.tsx` + `HttpExchange`; `src/components/JourneyStagePage.tsx` / `JourneyOperationCard.tsx`; `vite.config.ts` `/gateway` proxy; `server/dev-plugin.ts` `wrangler d1 execute … --local` for reset; `src/catalog/stage-0-platform-boot.ts` `scheduled-cron` card. | V4 **extends** nav/routes and **adds** catalogs/pages. It **reuses** `sendJourneyRequest` + `RequestInspector` for every new HTTP operation. Invoice inspect **reuses** the wrangler D1 `--local` spawn class, not a new Worker route. It does **not** rewrite stages 00–12, guard-pipeline, secrets, or the stage-0 health/scheduled card. |
| **G1 — Plan catalogue and credit-denominated entitlement** (operator plan CRUD; `plan` row shape; B2 `401` `{"error":"unauthorized"}`) | `ai-platform/src/control/plan.ts` (`handlePlanCreate` / `Update` / `Delete`); routes `POST /control/plans/create`, `POST /control/plans/{name}/update`, `POST /control/plans/{name}/delete`; `PlanPayload` in `ai-platform/src/control/types.ts`; frozen `specs/056-plan-catalogue/contracts/plan-catalogue.md` §2–§3.1. B2 reject in `ai-platform/src/control/http.ts`. | Viewer plan page **POSTs** those three paths through `/gateway` with operator bearer. Body fields are the frozen `plan` columns (`name`, `credit_budget`, `request_quota`, `max_cost_class`, `soft_threshold`, `allowed_capabilities`, `status`). Missing credentials: send without bearer and show the frozen `401` body as raw response. Does **not** add `GET /control/plans`, does **not** rewrite assignment/override/`credit_price`/config-cache `"plans"`. |
| **G3 — Usage summary endpoint and in-app gauge** (`GET /v1/usage`; credits-only `{ current_period, prior_periods }`; taxonomy `unauthenticated`) | `ai-platform/src/usage-summary/index.ts` `handleUsageSummaryRequest`; dispatch in `ai-platform/src/worker.ts`; frozen `specs/058-usage-summary-gauge/contracts/usage-summary.md` §2–§4 (`current_period.credits_used`, `current_period.credit_budget`). Operator `GET /control/installations/:id/quota` in `src/control/quota-inspect.ts` stays operator-only. | Viewer usage page **GETs** `/v1/usage` with installation AAT via `sendJourneyRequest`. `credit-gauge.ts` / `CreditGauge` render **only** `credits_used` against `credit_budget`. Must **not** call quota-inspect for this gauge. Must **not** display provider prices, token actuals, or cost actuals. Flutter clinic gauge is out of scope. |
| **G4 — Billing period close and invoice generation** (`invoice` row; rollup evidence; `POST /control/credit-price/activate`; cron `"0 5 1 * *"` / `runPeriodClose`; **no** invoice HTTP read) | `ai-platform/migrations/20260911200000_invoice.sql`; `ai-platform/src/period-close/index.ts` `runPeriodClose`; Worker `scheduled` branch and wrangler cron `"0 5 1 * *"`; frozen `specs/059-billing-period-close/contracts/invoice.md` and `invoice-evidence.md` (SQL joins). Activate: `ai-platform/src/control/credit-price.ts` (unchanged; not a required viewer card). | Invoice list/detail **SELECT** issued rows and evidence via local D1 inspect using the frozen column list and evidence SQL. Stage-X **drives** close as `GET /cdn-cgi/handler/scheduled?cron=0+5+1+*+*`. Does **not** add a Worker invoice GET, does **not** rewrite close, activation, immutability, or `src/rollup/`. Zero-consumption / no-price periods simply omit rows (G4 already issues none). |

No consumed entry lacks an implementation. No consumed **contract** is rewritten (delivery plan §2.3). Stop condition 2 is not triggered.

## Components Touched

**None.** Delivery Plan §3.14: the viewer appears in no §4 component group; this slice cites
the control-plane and HTTP surfaces it drives. Stop condition 5 (more than one §4 component
without a reason) is not triggered. Task count stays ~18–22.

Reason this is not an implicit Worker / Flutter / control-plane change: FR-001 and FR-015
forbid modifying `ai-platform/`, G1/G3/G4 contracts, and the G3 Flutter gauge.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform-viewer/src/types.ts` | Modified | FR-001, FR-002 — widen `NavSection` with `plans`, `usage`, `invoices`, `stage-x` |
| `ai-platform-viewer/src/lib/routes.ts` | Modified | FR-002 — paths `/plans`, `/usage`, `/invoices`, `/stage-x` |
| `ai-platform-viewer/src/components/SideNav.tsx` | Modified | FR-001, FR-002 — nav entries; do not rename or drop V3 items |
| `ai-platform-viewer/src/components/AppShell.tsx` | Modified | FR-002 — mount the four new pages |
| `ai-platform-viewer/src/catalog/commercial-plans.ts` | Created | FR-003, FR-004 — three G1 POST cards |
| `ai-platform-viewer/src/components/PlansPage.tsx` | Created | FR-003, FR-004 — `JourneyStagePage` over those cards |
| `ai-platform-viewer/src/catalog/commercial-usage.ts` | Created | FR-005, FR-006 — `GET /v1/usage` card (AAT) |
| `ai-platform-viewer/src/lib/credit-gauge.ts` | Created | FR-005, FR-006, FR-012 — parse credits-only current period |
| `ai-platform-viewer/src/components/CreditGauge.tsx` | Created | FR-005, FR-006, FR-012 — render consumed vs budget; no analytics dashboard |
| `ai-platform-viewer/src/components/UsageGaugePage.tsx` | Created | FR-005, FR-006, FR-012 — gauge + V3 inspector |
| `ai-platform-viewer/server/d1-inspect.ts` | Created | FR-007, FR-008, FR-009 — `wrangler d1 execute --local` list + evidence SQL |
| `ai-platform-viewer/server/dev-plugin.ts` | Modified | FR-009 — `/api/dev/invoices` and `/api/dev/invoices/detail` only; no generic SQL console (R-20) |
| `ai-platform-viewer/src/lib/dev-api.ts` | Modified | FR-007, FR-008, FR-009 — fetch those inspect routes into `HttpExchange` |
| `ai-platform-viewer/src/catalog/commercial-invoices.ts` | Created | FR-007, FR-008, FR-009 — list + detail operations |
| `ai-platform-viewer/src/components/InvoicesPage.tsx` | Created | FR-007, FR-008, FR-009 |
| `ai-platform-viewer/src/catalog/stage-x.ts` | Created | FR-010, FR-011 — cron + HTTP failure-journey cards (inventory above) |
| `ai-platform-viewer/src/components/StageXPage.tsx` | Created | FR-010, FR-011 |
| `ai-platform-viewer/package.json` | Modified | FR-002 / Test plan — vitest + slice test script |
| `ai-platform-viewer/vitest.config.ts` | Created | Test plan — Node harness for Viewer build + smoke |
| `ai-platform-viewer/test/viewer-builds.test.ts` | Created | `viewer_builds` / SC-001 / FR-002 |
| `ai-platform-viewer/test/commercial-pages.smoke.test.ts` | Created | plan CRUD, gauge, invoice list/detail named tests / SC-002–SC-004 |
| `ai-platform-viewer/test/stage-x.smoke.test.ts` | Created | cron + failure-journey named tests / SC-005 |
| `specs/060-viewer-commercial-surface/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above |

Every file traces to an `FR-###` (or deferred Documentation). No Consumes module is rewritten.
Untraced files are out of scope. No `ai-platform/` product file is listed.

## Test Layout

The spec's `### Test plan` names seven tests (Delivery Plan §3.12.11 V4 *Viewer build + smoke*).
§13.5 has no viewer row; the spec already places them on that delivery-plan layer. Every named
test is placeable. Stop condition 3 is not triggered.

**Harness invocation** (implementation choice, not a requirement): Vitest in
`ai-platform-viewer/` (V3 has no test tree). `viewer_builds` does not need the Worker.
HTTP smokes `fetch` `http://127.0.0.1:8787` (the origin V3's inspector already displays) with
the same headers `sendJourneyRequest` would send, then wrap results with V3
`buildRawRequest` / `buildRawResponse` and assert `HttpExchange.request.raw` and
`response.raw` are non-empty. Invoice smokes call `server/d1-inspect.ts` (same wrangler class
as the plugin) and assert the wrapper's `HttpExchange` carries the SQL as request raw and the
JSON rows as response raw. Do not add Playwright; "visible" means the V3 inspector payload is
produced and the new pages mount `RequestInspector` via `JourneyOperationCard` (compile-checked
by `viewer_builds`).

**Local stack**: Worker must be running with `--test-scheduled` for cron smokes (catalog `404`
without it is the frozen raw body, not a viewer diagnostic). Plan CRUD / usage smokes need the
Worker and credentials from `ai-platform/.dev.vars` plus a minted AAT (usage). Invoice
list/detail need local D1 only (`--local`); tests may `INSERT` issued fixture rows through the
same wrangler class when no invoice exists — that is not a Worker invoice GET.

**Credits-only gauge assertion**: parse the `GET /v1/usage` JSON; require
`current_period.credits_used` and `current_period.credit_budget`; forbid token/cost/price keys
on the rendered gauge model (`credit-gauge.ts`).

| Spec Test plan name | File | Spec layer | Asserts (FR / SC) |
| --- | --- | --- | --- |
| `viewer_builds` | `ai-platform-viewer/test/viewer-builds.test.ts` | Viewer build + smoke | FR-002 / SC-001 — `tsc -b && vite build` succeeds after the new pages exist |
| `plan_catalogue_crud_drives_g1_control_mutations` | `ai-platform-viewer/test/commercial-pages.smoke.test.ts` | Viewer build + smoke | FR-003, FR-004 / SC-002 — create/update/delete hit the three G1 POSTs; `HttpExchange` raw request/response populated; without operator bearer the raw response is G1/B2 `401` `{"error":"unauthorized"}` |
| `credit_gauge_renders_g3_consumed_versus_budget` | `ai-platform-viewer/test/commercial-pages.smoke.test.ts` | Viewer build + smoke | FR-005, FR-006, FR-012 / SC-003 — `GET /v1/usage`; gauge model is `credits_used` vs `credit_budget`; no token/cost/price fields; raw inspector payload present |
| `invoice_list_renders_g4_invoices` | `ai-platform-viewer/test/commercial-pages.smoke.test.ts` | Viewer build + smoke | FR-007, FR-009 / SC-004 — local D1 list returns frozen invoice columns; SQL+JSON visible as `HttpExchange` |
| `invoice_detail_renders_g4_rollup_evidence` | `ai-platform-viewer/test/commercial-pages.smoke.test.ts` | Viewer build + smoke | FR-008, FR-009 / SC-004 — detail SQL returns `usage_rollup` lines and a `usage_event.request_id` → `ai_request.request_reference` trace |
| `stage_x_cron_operations_drivable` | `ai-platform-viewer/test/stage-x.smoke.test.ts` | Viewer build + smoke | FR-010 / SC-005 — `GET /cdn-cgi/handler/scheduled?cron=` for the three named expressions (and SX-003 unknown cron); raw request/response present |
| `stage_x_failure_journey_operations_drivable` | `ai-platform-viewer/test/stage-x.smoke.test.ts` | Viewer build + smoke | FR-011 / SC-005 — catalog HTTP failure-journey cards (`GET /v1/requests/{ref}`, `POST /control/support/lookup`) are sendable against the local stack with raw inspector payloads |

This slice emits **no** new diagnostic code. Inherited §6.4 prohibitions are out of scope and
are not implemented (spec Coverage). Catalog `404` on scheduled trigger without
`--test-scheduled` is shown as raw response.

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this slice:

1. **Tests first (or alongside)** — add failing `viewer-builds.test.ts`,
   `commercial-pages.smoke.test.ts`, and `stage-x.smoke.test.ts` plus `vitest.config.ts` /
   package.json script (never after the pages exist untested).
2. **Nav/routes** — extend `NavSection`, `routes.ts`, `SideNav`, `AppShell` without renaming
   V3 sections (FR-001, FR-002, FR-015).
3. **Plan catalogue** — `commercial-plans.ts` + `PlansPage` driving the three G1 POSTs through
   `sendJourneyRequest`; operator `401` left as raw body (FR-003, FR-004).
4. **Credit gauge** — `commercial-usage.ts`, `credit-gauge.ts`, `CreditGauge`,
   `UsageGaugePage`; `GET /v1/usage` only; credits-only render (FR-005, FR-006, FR-012).
5. **Invoice D1 inspect** — `server/d1-inspect.ts` + two `/api/dev` routes wrapping
   `wrangler d1 execute --local`; `dev-api.ts` → `HttpExchange`; list/detail page (FR-007–FR-009).
6. **Stage-X** — `stage-x.ts` + `StageXPage` with the cron and HTTP failure-journey inventory
   above; do not rewrite stage 0 (FR-010, FR-011, FR-015).
7. **Turn tests green** — build; G1 POSTs; gauge parse; D1 list/detail; scheduled trigger;
   lookup drivability; confirm `ai-platform/src/` git-clean for this slice.
8. **Documentation** — write `quickstart.md` per sections above.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
