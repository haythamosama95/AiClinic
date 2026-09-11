# Tasks: Viewer commercial surface and stage-X page (V4)

**Input**: Design documents from `specs/060-viewer-commercial-surface/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` and `contracts/` are **not** produced — Freezes is none; this slice defines no D1 entities. `AVAILABLE_DOCS`: (none). `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (seven cases) is covered by its own task, written to fail before the commercial pages, D1-inspect helper, stage-X page, and viewer Vitest harness exist. Layer is **Viewer build + smoke** (delivery plan §3.12.11 row V4; §13.5 names no viewer row because the viewer is tooling). Permanent suite joins CI (delivery plan §3.11). No spy-named cases in the spec Test plan — absence asserts (credits-only gauge model; no `GET /control/installations/:id/quota`; G1/B2 `401` raw body) stay inside their named outcome tests.

**Organization**: One user story (US1, P1) — V4 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — plan Files names `package.json` and `vitest.config.ts` so the viewer-package Node harness exists before or alongside the Tests phase. No Foundational or Polish phase — prerequisites are already-merged Needs (V3, G1, G3, G4) in the plan's Consumes Binding.

**Task count**: 20 (≤25). Related tasks were combined to fit the cap (naive Files split was 28). Combinations are same-file or same FR cluster / plan Sequencing step. Named tests were not dropped or merged. Unrelated work was not merged.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by V4*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by V4*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — *not touched by V4* (G1/G3/G4 consumed, not rewritten)
- **Viewer (this slice)**: `ai-platform-viewer/src/`, `ai-platform-viewer/server/`, `ai-platform-viewer/test/`
- **Spec Kit artifacts**: `specs/060-viewer-commercial-surface/`
- V4 extends V3's existing viewer: new `NavSection` members `plans` / `usage` / `invoices` / `stage-x`, catalog files, and `JourneyStagePage` wrappers. Invoice reads are viewer-only `/api/dev/…` helpers that shell `npx wrangler d1 execute ai-platform-development --local --env development` (same class as V3 platform reset), wrapping SQL + JSON into V3 `HttpExchange` for `RequestInspector`. HTTP operations reuse `sendJourneyRequest` unchanged. Do not add a Worker invoice GET or `GET /control/plans`. Do not rewrite stages 00–12, guard-pipeline, secrets, or the stage-0 scheduled-handler card.

---

## Phase 1: Setup (Test harness)

**Purpose**: Plan Files names `ai-platform-viewer/package.json` and `ai-platform-viewer/vitest.config.ts` so this slice's three smoke files have a Node harness before or alongside the Tests phase. V3 has no test tree.

- [X] T001 [US1] Modify `ai-platform-viewer/package.json` — add Vitest as a **devDependency** (no new runtime packages) and a slice test script so `npx vitest run` works from `ai-platform-viewer/`. Create `ai-platform-viewer/vitest.config.ts` — Node smoke harness for Viewer build + smoke (plan Testing; Node `>=22`). Do not add Playwright. Do not add a Worker-side vitest include. No FR — harness; required by every named test. Prepares the Phase 2 substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.12.11 row V4). `viewer_builds` lives in `ai-platform-viewer/test/viewer-builds.test.ts`. Four commercial-page cases live in `ai-platform-viewer/test/commercial-pages.smoke.test.ts`. Two stage-X cases live in `ai-platform-viewer/test/stage-x.smoke.test.ts`. Until the commercial catalogs/pages, D1-inspect helper, and stage-X page exist, imports/assertions fail — the intended red state. The three suite files are `[P]` relative to each other; within each file, append sequentially.

- [X] T002 [P] [US1] Create `ai-platform-viewer/test/viewer-builds.test.ts`. Add named test `viewer_builds`: from `ai-platform-viewer/`, `tsc -b && vite build` succeeds after the commercial and stage-X pages are added (Delivery Plan §3.12.11 V4; Consumes V3). Import (or otherwise resolve) `PlansPage`, `UsageGaugePage`, `InvoicesPage`, and `StageXPage` so the case is red until those modules exist — a green V3 build alone is not enough. Do not require the Worker. Do not add Playwright; "visible" for later pages is compile-checked here because those pages mount `RequestInspector` via `JourneyOperationCard` / `JourneyStagePage`. Fails red until T009–T018 exist and typecheck. **Satisfies**: FR-002 / SC-001. **Proves**: `viewer_builds`.

- [X] T003 [P] [US1] Create `ai-platform-viewer/test/commercial-pages.smoke.test.ts`. Substrate: `fetch` `http://127.0.0.1:8787` (the origin V3's inspector already displays) with the same headers `sendJourneyRequest` would send; wrap with V3 `buildRawRequest` / `buildRawResponse` and assert `HttpExchange.request.raw` and `response.raw` are non-empty. Operator bearer from `ai-platform/.dev.vars`. Import `ai-platform-viewer/src/catalog/commercial-plans.ts` (red until T010). Add named test `plan_catalogue_crud_drives_g1_control_mutations`: create, update, and delete hit `POST /control/plans/create`, `POST /control/plans/{name}/update`, and `POST /control/plans/{name}/delete` against the local stack; body fields are the frozen `plan` columns (`name`, `credit_budget`, `request_quota`, `max_cost_class`, `soft_threshold`, `allowed_capabilities`, `status`); `HttpExchange` raw request/response populated; without operator bearer the raw response is G1/B2 `401` `{"error":"unauthorized"}` (no new viewer diagnostic). Do not add `GET /control/plans`. Fails red until the three G1 POST cards exist. **Satisfies**: FR-003, FR-004 / SC-002. **Proves**: `plan_catalogue_crud_drives_g1_control_mutations`.

- [X] T004 [US1] Add named test `credit_gauge_renders_g3_consumed_versus_budget` to `ai-platform-viewer/test/commercial-pages.smoke.test.ts`. Import `ai-platform-viewer/src/lib/credit-gauge.ts` and the usage catalog (red until T011–T012). Authenticated `GET /v1/usage` with a minted installation AAT; wrap with V3 raw inspector helpers (`HttpExchange` raw non-empty). Parse the JSON; require `current_period.credits_used` and `current_period.credit_budget`; forbid token/cost/price keys on the rendered gauge model. Must **not** call `GET /control/installations/:id/quota`. Credits only (A15; G3). Fails red until the usage card and credits-only parser exist. **Satisfies**: FR-005, FR-006, FR-012 / SC-003. **Proves**: `credit_gauge_renders_g3_consumed_versus_budget`.

- [X] T005 [US1] Add named test `invoice_list_renders_g4_invoices` to `ai-platform-viewer/test/commercial-pages.smoke.test.ts`. Call `ai-platform-viewer/server/d1-inspect.ts` (same `wrangler d1 execute --local` class as the plugin — red until T014). Tests MAY `INSERT` issued fixture rows through that wrangler class when no invoice exists — that is not a Worker invoice GET. Assert the wrapper's `HttpExchange` carries the SQL as request raw and the JSON rows as response raw, and that listed rows expose frozen invoice columns `installation_id`, `period`, `credits_consumed`, `credit_price_version`, `total`, `status`, `issued_at`. Zero-consumption / no-applicable-price periods simply omit rows (do not invent a placeholder invoice). Fails red until list SQL exists. **Satisfies**: FR-007, FR-009 / SC-004. **Proves**: `invoice_list_renders_g4_invoices`.

- [X] T006 [US1] Add named test `invoice_detail_renders_g4_rollup_evidence` to `ai-platform-viewer/test/commercial-pages.smoke.test.ts`. Detail inspect returns that installation and period's `usage_rollup` lines and a `usage_event.request_id` → `ai_request.request_reference` trace; SQL + JSON visible as `HttpExchange` (Delivery Plan §3.12.11 V4 *Commercial pages*; A15; G4 evidence). Do not add a Worker invoice GET. Fails red until evidence SQL exists. **Satisfies**: FR-008, FR-009 / SC-004. **Proves**: `invoice_detail_renders_g4_rollup_evidence`.

- [X] T007 [P] [US1] Create `ai-platform-viewer/test/stage-x.smoke.test.ts`. Import `ai-platform-viewer/src/catalog/stage-x.ts` (red until T017). Add named test `stage_x_cron_operations_drivable`: `GET /cdn-cgi/handler/scheduled?cron=` against `http://127.0.0.1:8787` for `"0 3 * * *"` (retention), `"0 4 * * *"` (rollup), `"0 5 1 * *"` (G4 period close), and SX-003 `"0 5 * * *"` (unknown-cron fallthrough); wrap with V3 raw inspector helpers (`HttpExchange` raw non-empty). Local stack must be `wrangler dev --test-scheduled`; catalog `404` without it is the frozen raw body, not a viewer diagnostic. Do not rewrite the stage-0 scheduled card. Fails red until the stage-X cron cards exist. **Satisfies**: FR-010 / SC-005. **Proves**: `stage_x_cron_operations_drivable`.

- [X] T008 [US1] Add named test `stage_x_failure_journey_operations_drivable` to `ai-platform-viewer/test/stage-x.smoke.test.ts`: catalog HTTP failure-journey cards `GET /v1/requests/{request_reference}` (SX-054 / SX-055) and `POST /control/support/lookup?reference=` (SX-054 / SX-055) are sendable against the local stack with raw inspector payloads. Do not add in-process stubs, DO-namespace cards, or D1/DO shims (those stay catalog E2E). Do not rewrite stage 12's lookup cards. Fails red until the stage-X HTTP failure-journey cards exist. **Satisfies**: FR-011 / SC-005. **Proves**: `stage_x_failure_journey_operations_drivable`.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Setup (T001), Tests (Phase 2), or Documentation. Order follows plan Sequencing (nav/routes → plan catalogue → credit gauge → invoice D1 inspect → stage-X → AppShell mount). Related Files in the same FR cluster / Sequencing step are combined so the list fits ≤25. Consumed V3 `sendJourneyRequest` / `RequestInspector` / `JourneyStagePage` / `dev-plugin.ts` spawn class, G1 plan handlers, G3 `GET /v1/usage`, and G4 `invoice` / `runPeriodClose` stay unmodified (delivery plan §2.3). No `ai-platform/` product file, no `frontend/`, no `backend/`. Test-file Files-section rows are produced by Phase 2. `index.css` is modified only if new nav accents reuse existing tokens — folded into the nav cluster, not a separate task.

- [X] T009 [US1] Modify `ai-platform-viewer/src/types.ts` — widen `NavSection` with `plans`, `usage`, `invoices`, `stage-x`; do not rename or drop existing V3 members. Modify `ai-platform-viewer/src/lib/routes.ts` — add paths `/plans`, `/usage`, `/invoices`, `/stage-x` to `SECTION_PATHS`. Modify `ai-platform-viewer/src/components/SideNav.tsx` — append commercial + stage-X nav items after V3's stage 00–12 + guard-pipeline entries; do not rename or drop V3 items; do not merge commercial surfaces into stage 4. Modify `ai-platform-viewer/src/index.css` only if new nav accents need existing token reuse. Do not rewrite `SessionContext.tsx` (NavSection union widening is `types.ts`). **Satisfies**: FR-001, FR-002, FR-015. **Proved by**: `viewer_builds`.

- [X] T010 [P] [US1] Create `ai-platform-viewer/src/catalog/commercial-plans.ts` — three `JourneyOperationDefinition` cards that `POST` G1's real control mutations `POST /control/plans/create`, `POST /control/plans/{name}/update`, and `POST /control/plans/{name}/delete` through V3 `/gateway` with operator bearer (`auth: 'operator'`). Body fields are the frozen `plan` columns (`name`, `credit_budget`, `request_quota`, `max_cost_class`, `soft_threshold`, `allowed_capabilities`, `status`). Missing credentials: send without bearer; show G1/B2 `401` `{"error":"unauthorized"}` as raw response — do not invent a viewer diagnostic. Do not add `GET /control/plans`. Create `ai-platform-viewer/src/components/PlansPage.tsx` — `JourneyStagePage` over those cards (reuses `RequestInspector` via `JourneyOperationCard`). Do not rewrite stage 4 entitle cards. **Satisfies**: FR-003, FR-004. **Proved by**: `plan_catalogue_crud_drives_g1_control_mutations`.

- [X] T011 [P] [US1] Create `ai-platform-viewer/src/catalog/commercial-usage.ts` — one `GET /v1/usage` card with installation AAT (`auth: 'aat'`). Do not call `GET /control/installations/:id/quota`. Do not put `credit_price` or a provider price onto `POST /v1/requests`. **Satisfies**: FR-005, FR-006, FR-013. **Proved by**: `credit_gauge_renders_g3_consumed_versus_budget`.

- [X] T012 [P] [US1] Create `ai-platform-viewer/src/lib/credit-gauge.ts` — parse G3 `GET /v1/usage` JSON to a credits-only current-period model (`credits_used` against `credit_budget`); forbid token/cost/price keys on the rendered model. Create `ai-platform-viewer/src/components/CreditGauge.tsx` — render consumed versus budget only; no analytics dashboard; no provider prices, token actuals, or cost actuals. **Satisfies**: FR-005, FR-006, FR-012. **Proved by**: `credit_gauge_renders_g3_consumed_versus_budget`.

- [X] T013 [US1] Create `ai-platform-viewer/src/components/UsageGaugePage.tsx` — compose `CreditGauge` with the usage catalog card so V3's inspector shows raw request/response for `GET /v1/usage`. Reuse `JourneyStagePage` / `RequestInspector`. Do not add an analytics dashboard. Depends on T011 and T012. **Satisfies**: FR-005, FR-006, FR-012. **Proved by**: `credit_gauge_renders_g3_consumed_versus_budget`, `viewer_builds`.

- [X] T014 [P] [US1] Create `ai-platform-viewer/server/d1-inspect.ts` — fixed invoice list and detail SQL runners via `npx wrangler d1 execute ai-platform-development --local --env development` (same class V3 already uses for platform reset). List SELECTs issued G4 `invoice` rows (`installation_id`, `period`, `credits_consumed`, `credit_price_version`, `total`, `status`, `issued_at`). Detail SELECTs that installation and period's `usage_rollup` rows and traces a line through `usage_event.request_id` to `ai_request.request_reference` (frozen G4 evidence SQL). Wrap SQL + JSON into V3 `HttpExchange` (SQL as request raw, JSON as response raw). No generic SQL console (R-20). No Worker invoice GET. **Satisfies**: FR-007, FR-008, FR-009. **Proved by**: `invoice_list_renders_g4_invoices`, `invoice_detail_renders_g4_rollup_evidence`.

- [X] T015 [US1] Modify `ai-platform-viewer/server/dev-plugin.ts` — add viewer-only `/api/dev/invoices` and `/api/dev/invoices/detail` that call T014's runners; no generic SQL console; no other `/api/dev` rewrite. Modify `ai-platform-viewer/src/lib/dev-api.ts` — client wrappers that fetch those inspect routes into `HttpExchange`. Do not add a Worker invoice GET. Depends on T014. **Satisfies**: FR-007, FR-008, FR-009. **Proved by**: `invoice_list_renders_g4_invoices`, `invoice_detail_renders_g4_rollup_evidence`.

- [X] T016 [US1] Create `ai-platform-viewer/src/catalog/commercial-invoices.ts` — list + detail local-D1 operations that call the T015 wrappers (not Worker HTTP). Create `ai-platform-viewer/src/components/InvoicesPage.tsx` — `JourneyStagePage` over those operations so `RequestInspector` shows the D1 read. Do not integrate a payment provider and do not call one while rendering invoices. Depends on T015. **Satisfies**: FR-007, FR-008, FR-009, FR-014. **Proved by**: `invoice_list_renders_g4_invoices`, `invoice_detail_renders_g4_rollup_evidence`.

- [X] T017 [P] [US1] Create `ai-platform-viewer/src/catalog/stage-x.ts` — cron cards via `GET /cdn-cgi/handler/scheduled?cron=<expression>` for `"0 3 * * *"` (retention), `"0 4 * * *"` (rollup), `"0 5 1 * *"` (G4 period close), and `"0 5 * * *"` (SX-003 unknown-cron fallthrough); HTTP failure-journey cards `GET /v1/requests/{request_reference}` and `POST /control/support/lookup?reference=` (catalog SX-054 / SX-055 Worker HTTP Actions). Period close is this G4 cron, not a `/control` POST. Do not add cards for in-process `runRetentionPurge` / `runRollupAndReconciliation` clock injection, DO-namespace stubs, D1 SQL proxies, GatewayObject `quota-do.internal` methods, or injected-`now` DO sweeps (SX-046–SX-063) — those stay catalog E2E. Create `ai-platform-viewer/src/components/StageXPage.tsx` — `JourneyStagePage` over those cards. Do not rewrite `ai-platform-viewer/src/catalog/stage-0-platform-boot.ts` or stage 12 lookup cards. **Satisfies**: FR-010, FR-011, FR-015. **Proved by**: `stage_x_cron_operations_drivable`, `stage_x_failure_journey_operations_drivable`.

- [X] T018 [US1] Modify `ai-platform-viewer/src/components/AppShell.tsx` — mount `PlansPage`, `UsageGaugePage`, `InvoicesPage`, and `StageXPage` for the four new `NavSection` members. Do not rewrite V3 stage 00–12, guard-pipeline, or secrets mounts. Depends on T009, T010, T013, T016, and T017. **Satisfies**: FR-002, FR-015. **Proved by**: `viewer_builds`.

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T019 [US1] From `ai-platform-viewer/`, run this slice's suite — `npx vitest run test/viewer-builds.test.ts` (`viewer_builds`), `npx vitest run test/commercial-pages.smoke.test.ts` (`plan_catalogue_crud_drives_g1_control_mutations`, `credit_gauge_renders_g3_consumed_versus_budget`, `invoice_list_renders_g4_invoices`, `invoice_detail_renders_g4_rollup_evidence`), and `npx vitest run test/stage-x.smoke.test.ts` (`stage_x_cron_operations_drivable`, `stage_x_failure_journey_operations_drivable`). Then from `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, including G1 `plan-catalogue.test.ts`, G3 `usage-summary.test.ts`, and G4 `period-close.test.ts` / `price-list-activation.test.ts`). Confirm V4's seven named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions: `ai-platform/src/` git-clean for this slice (no Worker invoice GET, no `GET /control/plans`, G1/G3/G4 contracts untouched); V3 stage 00–12 / guard-pipeline / secrets / stage-0 scheduled card not rewritten; no payment-provider call; request path never sees a price; no Band L start; no §9.14 mechanism; no second Quota DO / R2; no per-request server-side state; no write path into Supabase (delivery plan §6.4; FR-001, FR-013, FR-014, FR-015). **Satisfies**: the §3.10 checkpoint rule (seven named tests + prior suites); FR-001, FR-013, FR-014, FR-015. Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T020 [US1] Create `specs/060-viewer-commercial-surface/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — V4 row of the delivery plan (§3.14; Canonical `— (tooling; drives A15 surfaces)`); what the spec delivered; what this plan scoped. **§2 What was implemented** — plan-catalogue CRUD cards on G1 POSTs; credits-only gauge on `GET /v1/usage`; invoice list/detail via local D1 inspect; stage-X cron and HTTP failure-journey cards; no Worker/D1/Flutter contract change. **§3 Files to review** — only this slice's viewer catalogs, pages, D1-inspect helper, nav/route wiring, and this slice's smoke test files (no prior-slice files). **§4 Prerequisites** — local Worker with `wrangler dev --test-scheduled`; Vite (`npm run dev` in `ai-platform-viewer/`) for the human console; operator bearer and a minted AAT for HTTP smokes. **§5 Run the automated suite** — slice-only from `ai-platform-viewer/`: `npx vitest run test/viewer-builds.test.ts`, `npx vitest run test/commercial-pages.smoke.test.ts`, `npx vitest run test/stage-x.smoke.test.ts`; no full-suite `npm test`, no prior-slice counts. **§6 Inspect the changes** — open the four new routes; grep G1/G3 paths and `wrangler d1 execute`; confirm `ai-platform/src/` and V3 stage 00–12 files untouched. **§7 Manual validation** — the viewer is a human console beyond CI: open `/plans`, `/usage`, `/invoices`, `/stage-x` against the local stack and confirm each new operation shows V3's raw inspector (and the usage page shows the credits-only gauge). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — none; can start immediately. Viewer-package Vitest harness for the three new test files.
- **Tests (T002–T008)** — T002 / T003 / T007 depend on T001 (harness). T002, T003, and T007 are `[P]` relative to each other (three different files). T004–T006 append sequentially after T003 (same `commercial-pages.smoke.test.ts`). T008 appends after T007 (same `stage-x.smoke.test.ts`). Written to fail before the commercial pages / D1-inspect helper / stage-X page exist.
- **Implementation (T009–T018)** — after tests exist (red). Order follows plan Sequencing: nav/routes (T009) → plan catalogue (T010) → credit gauge (T011–T013) → invoice D1 inspect (T014–T016) → stage-X (T017) → AppShell mount (T018).
- **Verification (T019)** — depends on T001–T018; runs this slice's viewer suites plus every prior `ai-platform/` suite per §3.10.
- **Documentation (T020)** — depends on T019 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: nav types/routes/SideNav (T009) → G1 plan cards + page (T010) → usage card (T011) + credits-only gauge (T012) + usage page (T013) → D1 inspect (T014) + `/api/dev` routes (T015) + invoice page (T016) → stage-X (T017) → AppShell (T018); Documentation last.
- Test-file and harness Files-section rows are produced by Phase 1–2. Remaining Files units are T009–T018 plus T020 (`quickstart.md`).

### Parallel Opportunities

- Phase 1 (T001) is a single harness-pair task — no internal parallelism.
- Phase 2: T002, T003, and T007 are `[P]` relative to each other (different files). Within each suite file, append sequentially (no `[P]`).
- Phase 3: T010, T011, T012, T014, and T017 are `[P]` relative to each other after T009 (different files / FR clusters). T013 depends on T011 and T012. T015 depends on T014. T016 depends on T015. T018 depends on T009, T010, T013, T016, and T017.
- Phase 5 (T020) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T002, T003, T007, T010, T011, T012, T014, T017.
- Every named test from `spec.md` is covered by its own task; no test is folded into another. The spec Test plan names no spy cases; credits-only / no quota-inspect / G1 `401` raw body stay inside their named outcome tests (T003, T004).
- Related implementation tasks combined to fit ≤25: T001 (`package.json` + `vitest.config.ts`, harness); T009 (`types.ts` + `routes.ts` + `SideNav.tsx` + optional `index.css`, nav FR cluster / Sequencing step 2); T010 (`commercial-plans.ts` + `PlansPage.tsx`, FR-003/004); T012 (`credit-gauge.ts` + `CreditGauge.tsx`, FR-005/006/012); T015 (`dev-plugin.ts` + `dev-api.ts`, FR-007–009 inspect wiring); T016 (`commercial-invoices.ts` + `InvoicesPage.tsx`, FR-007–009); T017 (`stage-x.ts` + `StageXPage.tsx`, FR-010/011). Named tests were not combined.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart / harness Setup. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are V3, G1, G3, G4 (Consumes Binding).
- Consumed modules are imported/bound, not rewritten (delivery plan §2.3 — extend, never rewrite). V4 does not absorb V3 stages 00–12, G1 assignment/override, G2 debit, G3 Flutter gauge, G4 `runPeriodClose` / activation, V1/V2 catalog E2E, or Band L.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism; no second Quota DO or R2 object; no per-request server-side state; no prompt/provider/model in the Flutter client; request path never sees a price (FR-013); no payment-provider call (FR-014).
