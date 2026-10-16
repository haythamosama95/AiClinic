# Feature Specification: Viewer commercial surface and stage-X page (V4)

**Feature Branch**: `ai/060-v4-viewer-commercial-surface`

**Created**: 2026-09-11

**Status**: Draft

**Input**: Slice `V4` — *Viewer commercial surface and stage-X page* (Delivery Plan §3.14, row V4).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice lives in `ai-platform-viewer/`. It is development and
> operator tooling: it freezes no platform contract, ships to no clinic, and
> appears in no §4 component group (Delivery Plan §3.14). Band V traces to
> **§13.5 (testing strategy)** and to the catalog; this slice cites the
> control-plane and HTTP surfaces it drives rather than a §4 component. A15's
> constitution check stands: no domain logic, no business data, no write path
> into Supabase.

## Slice Contract

### Implements

`— (tooling; drives A15 surfaces)` (copied verbatim from the slice's `Canonical` cell in §3.14 of
`docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`).

### Freezes

None. The viewer freezes no platform contract (Delivery Plan §3.14). Later slices may
extend the viewer and may not rewrite the G1, G3, or G4 contracts this slice drives
(Delivery Plan §2.3).

### Consumes

Contracts frozen by the slices in V4's `Needs` (`V3`, `G1`, `G3`, `G4`). Changing any is
out of scope by definition:

- **From V3 — Viewer foundations and stage pages** (Delivery Plan §3.14): the
  `ai-platform-viewer/` app that builds (`tsc -b && vite build`), drives stages 00–12,
  the guard-pipeline view, and secrets against the local stack, and shows raw
  request/response for every operation. V4 adds commercial pages and a stage-X page;
  it does not rewrite stages 00–12, the guard-pipeline view, or secrets.
- **From G1 — Plan catalogue and credit-denominated entitlement** (A15; G1 Freezes):
  operator plan CRUD on `POST /control/plans/create`, `POST /control/plans/{name}/update`,
  and `POST /control/plans/{name}/delete`; the `plan` row shape (`name`, `credit_budget`,
  `request_quota`, `max_cost_class`, `soft_threshold`, `allowed_capabilities`, `status`);
  B2 operator-auth rejection `401` `{"error":"unauthorized"}` with no D1 write. V4 drives
  those mutations from the viewer; it does not rewrite the catalogue, assignment,
  override, `credit_price` table shape, or the config-cache kind `"plans"`.
- **From G3 — Usage summary endpoint and in-app gauge** (A15; G3 Freezes):
  installation-authenticated `GET /v1/usage` answering current-period credits consumed
  against budget live from the Quota DO (`credits_used` against `credit_budget`) and
  prior periods from `usage_rollup`'s quota-weight aggregate; credits-only JSON
  `{ current_period, prior_periods }`; taxonomy `unauthenticated` for missing or
  invalid auth. The operator route `GET /control/installations/:id/quota` stays
  operator-only. V4 renders that endpoint's consumed-versus-budget in the viewer; it
  does not rewrite the endpoint, the credits-only payload, or the Flutter clinic gauge.
- **From G4 — Billing period close and invoice generation** (A15; G4 Freezes): the
  `invoice` row (`installation_id`, `period`, `credits_consumed`, `credit_price_version`,
  `total`, `status`, `issued_at`); invoice evidence as `usage_rollup` rows for that
  installation and period, each line tracing through `usage_event.request_id` to
  `ai_request.request_reference`; operator `POST /control/credit-price/activate`;
  scheduled close on Worker cron `"0 5 1 * *"` (`runPeriodClose`). G4 defines **no**
  invoice HTTP read surface; V4 reads issued rows for list and detail. V4 does not
  rewrite close, activation, immutability, or the payment-collection boundary.

### Open decisions relied on

None. Amendment A15 settled Open Decisions 2 and 15 as contract changes rather than as
§15 recommended defaults: the quota unit is the AI credit and the period is the
calendar month (OD-2), and a plan catalogue exists (OD-15 settled against its default)
(A15). This slice transcribes those settlements onto viewer pages that drive the
already-frozen G1, G3, and G4 surfaces.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Viewer commercial surface and stage-X page (Priority: P1)

A developer or operator using `ai-platform-viewer/` against the local stack maintains
the plan catalogue by driving G1's operator plan CRUD, reads one installation's
current-period credits consumed versus budget from G3's `GET /v1/usage`, and inspects
G4's issued `invoice` rows with their `usage_rollup` evidence. The same viewer has a
stage-X page from which the catalog's cron ticks and failure-journey operations are
drivable. Every operation shows the raw request and response. The viewer is not a
clinic product and does not freeze a platform contract.

**Why this priority**: V4's `Needs` are V3 (viewer foundations and stages 00–12), G1
(plan-catalogue control mutations), G3 (usage-summary endpoint), and G4 (invoices and
period close). V3 is largely implemented; V4 adds what Band G and stage X need
(Delivery Plan §3.14). Band V is ordered by what it verifies rather than by a §4
component. Nothing in this slice is a clinic-facing Flutter surface or a Worker
contract change.

**Independent Test**: The viewer gains plan-catalogue CRUD against G1's control
mutations, a per-installation credit gauge reading G3's endpoint, and an invoice
list/detail view over G4's output; the stage-X cron and failure journeys are
drivable; everything runs against the local stack with raw request/response visible
(Delivery Plan §3.14 row V4 Done when; DP-3).

**Acceptance Scenarios**:

1. **Given** the `ai-platform-viewer/` tree after this slice's pages are added, **When**
   `tsc -b && vite build` runs, **Then** the viewer builds (Delivery Plan §3.12.11 row
   V4 *Viewer build + smoke*; Consumes V3).
2. **Given** the local stack and operator credentials, **When** the viewer plan-catalogue
   page runs create, update, and delete, **Then** those cards drive G1's real control
   mutations `POST /control/plans/create`, `POST /control/plans/{name}/update`, and
   `POST /control/plans/{name}/delete`, and each operation shows the raw request and
   response (Delivery Plan §3.12.11 row V4 *Commercial pages*; A15; G1 HTTP surface).
3. **Given** the local stack and an installation AAT, **When** the viewer credit gauge
   for that installation is shown, **Then** it reads G3's `GET /v1/usage` and renders
   that endpoint's current-period consumed-versus-budget (`credits_used` against
   `credit_budget`), with the raw request and response visible (Delivery Plan §3.12.11
   row V4 *Commercial pages*; A15 item 6; G3 `GET /v1/usage`).
4. **Given** issued G4 `invoice` rows on the local stack, **When** the viewer invoice
   list is shown, **Then** it renders those invoices (`installation_id`, `period`,
   `credits_consumed`, `credit_price_version`, `total`, `status`, `issued_at`) with raw
   request/response (or the local D1 read) visible (Delivery Plan §3.12.11 row V4
   *Commercial pages*; A15; G4 `invoice` entity).
5. **Given** an issued G4 `invoice` on the local stack, **When** the viewer invoice
   detail is shown, **Then** it renders that invoice's `usage_rollup` rows for the same
   installation and period, and a line traces through `usage_event.request_id` to
   `ai_request.request_reference`, with raw request/response (or the local D1 read)
   visible (Delivery Plan §3.12.11 row V4 *Commercial pages*; A15; G4 invoice evidence).
6. **Given** the local stack with `wrangler dev --test-scheduled`, **When** the viewer
   stage-X page runs cron operations, **Then** those operations are drivable via the
   catalog's local trigger `GET /cdn-cgi/handler/scheduled?cron=<expression>` (including
   `"0 3 * * *"` retention, `"0 4 * * *"` rollup, and G4 `"0 5 1 * *"` period close),
   and each shows the raw request and response (Delivery Plan §3.12.11 row V4
   *Stage X*; §13.5; `docs/testing/catalog/stage-X-cron-and-failure-journeys.md`).
7. **Given** the local stack, **When** the viewer stage-X page runs failure-journey
   operations, **Then** those catalog failure-journey operations are drivable from the
   viewer against the local stack, with raw request/response visible (Delivery Plan
   §3.12.11 row V4 *Stage X*; §13.5;
   `docs/testing/catalog/stage-X-cron-and-failure-journeys.md`).

### Test plan

Every named test is required (Delivery Plan §3.11; DP-3). The slice's required-case
layer in Delivery Plan §3.12.11 is **Viewer build + smoke**. Band V traces to §13.5
(testing strategy); that table names no viewer row because the viewer is tooling, not
a §4 component (Delivery Plan §3.14). Tests are smoke against the local stack, not
optional.

| Test name | Layer | Asserts |
| --- | --- | --- |
| `viewer_builds` | Viewer build + smoke | `tsc -b && vite build` succeeds after the commercial and stage-X pages are added (Delivery Plan §3.12.11 V4; Consumes V3) |
| `plan_catalogue_crud_drives_g1_control_mutations` | Viewer build + smoke | Plan create, update, and delete drive `POST /control/plans/create`, `POST /control/plans/{name}/update`, and `POST /control/plans/{name}/delete` against the local stack, with raw request/response visible (Delivery Plan §3.12.11 V4 *Commercial pages*; A15; G1) |
| `credit_gauge_renders_g3_consumed_versus_budget` | Viewer build + smoke | The per-installation gauge reads `GET /v1/usage` and renders current-period `credits_used` versus `credit_budget`, credits only, with raw request/response visible (Delivery Plan §3.12.11 V4 *Commercial pages*; A15; G3) |
| `invoice_list_renders_g4_invoices` | Viewer build + smoke | The invoice list renders G4 `invoice` rows with their frozen fields, with the read visible (Delivery Plan §3.12.11 V4 *Commercial pages*; A15; G4) |
| `invoice_detail_renders_g4_rollup_evidence` | Viewer build + smoke | Invoice detail renders that installation and period's `usage_rollup` lines and traces a line to request references (Delivery Plan §3.12.11 V4 *Commercial pages*; A15; G4 evidence) |
| `stage_x_cron_operations_drivable` | Viewer build + smoke | Stage-X cron operations are drivable via `GET /cdn-cgi/handler/scheduled?cron=` against the local stack, with raw request/response visible (Delivery Plan §3.12.11 V4 *Stage X*; §13.5) |
| `stage_x_failure_journey_operations_drivable` | Viewer build + smoke | Stage-X failure-journey operations are drivable from the viewer against the local stack, with raw request/response visible (Delivery Plan §3.12.11 V4 *Stage X*; §13.5) |

Coverage (Delivery Plan §3.11): happy path of every requirement above; the viewer
emits **no** new diagnostic code — G1/G3/G4 rejections appear as the frozen raw
response (`401` `{"error":"unauthorized"}` on G1 plan CRUD without operator
credentials; G3 taxonomy `unauthenticated` on `GET /v1/usage` without a valid AAT;
catalog `404` on the scheduled trigger without `--test-scheduled`); inherited §6.4
prohibitions are out of scope and are not implemented. No new Worker, D1, or Flutter
product contract is added.

### Edge Cases

- **This slice emits no new error code.** Plan CRUD without operator credentials is
  G1/B2 `401` `{"error":"unauthorized"}` with no D1 write. `GET /v1/usage` without a
  valid installation AAT is G3 taxonomy `unauthenticated`. The scheduled-handler
  trigger without `wrangler dev --test-scheduled` is the catalog's `404`. The viewer
  shows those frozen bodies as raw response; it does not invent a viewer diagnostic.
- **Credits-only gauge.** The viewer gauge MUST render G3's `credits_used` against
  `credit_budget`. It MUST NOT display provider prices, token actuals, or cost
  actuals (A15; G3 credits-only response). It MUST NOT call
  `GET /control/installations/:id/quota` for this gauge (G3: that route stays
  operator-only).
- **No invoice HTTP read.** G4 froze no invoice HTTP read surface. List and detail
  read issued `invoice` rows and their `usage_rollup` evidence on the local stack
  (G4: "V4 reads issued rows"). This slice MUST NOT add a Worker invoice GET.
- **G4 close is scheduled, not an Entitlement-management HTTP mutation.** Period
  close is driven as the G4 cron `"0 5 1 * *"` (and the catalog's other cron
  expressions) through `GET /cdn-cgi/handler/scheduled?cron=`, not as a new
  `/control` POST (G4 period-close freeze).
- **Zero-consumption and no-applicable-price periods.** G4 issues no `invoice` for
  those outcomes (A15 item 5). The list renders issued rows; it does not invent a
  default price, currency, or placeholder invoice.
- **Local-stack unreachability.** When the Worker is down, the viewer shows the
  transport failure in the raw response panel (Consumes V3). It does not add retry,
  caching, or an error dialog that would imply a clinic product.
- **Catalogue "CRUD" has no G1 GET list.** G1 froze create/update/delete POSTs only.
  The viewer drives those three mutations. It MUST NOT add `GET /control/plans`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: This slice MUST be development and operator tooling in
  `ai-platform-viewer/`. It MUST freeze no platform contract, MUST ship to no clinic,
  and MUST appear in no §4 component group. It MUST cite the control-plane and HTTP
  surfaces it drives rather than a §4 component. `(§13.5; Delivery Plan §3.14; A15)`
- **FR-002**: The viewer MUST build (`tsc -b && vite build`) and MUST run the
  commercial and stage-X pages against the local stack, with raw request/response
  visible for every operation this slice adds. `(§13.5; Delivery Plan §3.12.11 V4;
  Consumes V3)`
- **FR-003**: The viewer MUST provide plan-catalogue create, update, and delete that
  drive G1's real control mutations `POST /control/plans/create`,
  `POST /control/plans/{name}/update`, and `POST /control/plans/{name}/delete`.
  `(A15; G1 plan CRUD)`
- **FR-004**: Plan CRUD MUST remain operator-authenticated. A mutation without
  operator credentials MUST surface G1/B2's existing `401` `{"error":"unauthorized"}`
  as the raw response and MUST NOT be rewritten into a new code. `(A15; G1 operator
  plan CRUD)`
- **FR-005**: The viewer MUST provide a per-installation credit gauge that reads
  G3's `GET /v1/usage` with an installation AAT and renders that endpoint's
  current-period consumed-versus-budget (`credits_used` against `credit_budget`).
  `(A15 item 6; G3 usage-summary read)`
- **FR-006**: That gauge's displayed payload MUST be credits only. It MUST NOT
  render provider prices, token actuals, or cost actuals, and MUST NOT use
  `GET /control/installations/:id/quota` for this read. `(A15; G3 credits-only
  response)`
- **FR-007**: The viewer MUST provide an invoice list that renders G4's issued
  `invoice` rows: `installation_id`, `period`, `credits_consumed`,
  `credit_price_version`, `total`, `status`, `issued_at`. `(A15; G4 invoice entity)`
- **FR-008**: The viewer MUST provide an invoice detail that renders that invoice's
  `usage_rollup` rows for the same installation and period, and MUST show a line
  traced through `usage_event.request_id` to `ai_request.request_reference`.
  `(A15; G4 invoice evidence)`
- **FR-009**: Invoice list and detail MUST read G4's issued rows. This slice MUST
  NOT add an invoice HTTP read surface on the Worker. `(A15; G4 freeze: no invoice
  HTTP read surface)`
- **FR-010**: The viewer MUST provide a stage-X page from which the catalog's cron
  operations are drivable via `GET /cdn-cgi/handler/scheduled?cron=<expression>`,
  including `"0 3 * * *"` (retention), `"0 4 * * *"` (rollup), and G4
  `"0 5 1 * *"` (period close). `(§13.5; A15 period close; Delivery Plan §3.12.11
  V4 *Stage X*)`
- **FR-011**: The stage-X page MUST make the catalog's failure-journey operations
  drivable against the local stack, with raw request/response visible. `(§13.5;
  Delivery Plan §3.12.11 V4 *Stage X*)`
- **FR-012**: The usage surface this slice drives MUST remain a gauge. No analytics
  dashboard MUST be added. `(A15 item 6)`
- **FR-013**: The request path MUST never see a price. The viewer MUST NOT put
  `credit_price` or a provider price onto `POST /v1/requests`. `(A15)`
- **FR-014**: Payment collection MUST remain outside. The viewer MUST NOT integrate
  a payment provider and MUST NOT call one while rendering invoices. `(A15 item 5)`
- **FR-015**: This slice MUST NOT change G1, G3, or G4 frozen contracts, MUST NOT
  start Band L, and MUST NOT rewrite V3 stages 00–12, the guard-pipeline view, or
  secrets. `(Delivery Plan §2.3, §3.14, §3.15)`

### Key Entities

Not applicable — this slice defines no entities.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: The viewer ships to no clinic (Delivery Plan §3.14). Small-to-mid
  multi-branch clinic commercial behaviour stays the A15 surfaces already frozen by
  G1, G3, and G4: a small plan catalogue, a credit gauge, and platform-issued
  invoices with payment collection outside (A15; constitution principle I). This
  slice only makes those surfaces drivable and inspectable on the local stack.
- **Layer Placement**: This slice touches **`ai-platform-viewer/`** only. It does
  not modify `ai-platform/` (Cloudflare Worker), `backend/` (Supabase), or
  `frontend/` (Flutter). It calls G1/G3/G4 surfaces already on the Worker as a
  local-stack client. A15's constitution check stands: no domain logic, no business
  data, no write path into Supabase.
- **Data Integrity & Security**: Plan CRUD remains operator-authenticated G1
  mutations audited on `control_audit`. The gauge is installation-authenticated
  `GET /v1/usage`. Invoice list/detail read G4 D1 rows; they do not write invoices.
  No clinic table is written. No new D1 entity or Worker route is added.
- **Failure Handling**: Frozen G1/G3/G4 and catalog errors appear as raw responses.
  Worker unreachability is visible in the raw panel (Consumes V3). The viewer is
  not on a clinic workflow; it adds no retry, no second Quota Durable Object round
  trip, and no per-request server-side state. Nothing hard-locks (A15; constitution
  principle V).

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **V3 — Viewer foundations and stage pages**: stages 00–12, guard-pipeline view,
  secrets, existing raw-inspector behaviour. Consumed, not rewritten. Remaining V3
  smoke belongs to V3.
- **V1 / V2 — Scenario catalog suite and remediation**: E2E ID-tagged tests and the
  work order. Not this slice.
- **G1** beyond driving plan CRUD: assignment (`POST /control/installations/{id}/entitle`),
  override, config-cache warm/cold, migrations. Stage 4 already drives entitle
  (Consumes V3). This slice MUST NOT rewrite those contracts.
- **G2 — Declared-weight credit debit in admission**: `quota_weight` debit,
  `quota_exhausted`, `degraded` on the credit ratio.
- **G3 Flutter clinic gauge**: hide-without-probe and unreachable-as-normal-state on
  the E4 host. This slice renders `GET /v1/usage` in the viewer only.
- **G4** beyond reading invoices and driving the already-frozen close cron and
  (if used to populate local invoices) `POST /control/credit-price/activate`: no
  change to `runPeriodClose`, immutability, or `src/rollup/`.
- **Band L — AI Billing Orchestrator and self-service provisioning**: CAT auth,
  attestations, purchase, receipts (Delivery Plan §3.15).
- **A new Worker invoice GET, a `GET /control/plans` list, or any other new
  Worker/D1/Flutter product contract.**
- **Shipping the viewer to clinics.**

Prohibitions inherited from delivery plan §6.4, copied verbatim:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional
  content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The viewer builds with `tsc -b && vite build` (asserted by
  `viewer_builds`).
- **SC-002**: Plan create, update, and delete from the viewer drive G1's
  `POST /control/plans/create`, `POST /control/plans/{name}/update`, and
  `POST /control/plans/{name}/delete` against the local stack, with raw
  request/response visible (asserted by
  `plan_catalogue_crud_drives_g1_control_mutations`).
- **SC-003**: The per-installation credit gauge renders G3 `GET /v1/usage`
  current-period `credits_used` versus `credit_budget`, credits only, with raw
  request/response visible (asserted by
  `credit_gauge_renders_g3_consumed_versus_budget`).
- **SC-004**: The invoice list renders G4 `invoice` rows and the detail renders
  their `usage_rollup` evidence including a request-reference trace (asserted by
  `invoice_list_renders_g4_invoices` and
  `invoice_detail_renders_g4_rollup_evidence`).
- **SC-005**: Stage-X cron and failure-journey operations are drivable from the
  viewer against the local stack, with raw request/response visible (asserted by
  `stage_x_cron_operations_drivable` and
  `stage_x_failure_journey_operations_drivable`).

## Assumptions

- V3's `ai-platform-viewer/` app, Vite/dev-plugin local-stack proxy, and raw
  request/response inspector are present. This slice adds pages and operation cards;
  it does not replace the shell.
- G1, G3, and G4 are present on the local Worker the viewer already calls through
  the V3 `/gateway` prefix (and the catalog scheduled-handler path).
- G4 issued no invoice HTTP read; list/detail use the same class of local D1
  inspection V3 already uses for platform reset (`wrangler d1 execute --local`),
  not a new Worker route.
- Stage-X operation cards drive surfaces named in
  `docs/testing/catalog/stage-X-cron-and-failure-journeys.md` (scheduled trigger,
  grace/retention/rollup/DO-sweep journeys). They do not reimplement the V1 E2E
  suite.
- Stage 0 already exposes one scheduled-handler card; the stage-X page is the
  Band V place that makes the catalog's cron **and** failure-journey set drivable.
  This slice does not rewrite the stage-0 health card.
- A15's clinic gauge, hide-without-probe, and unreachable-as-normal-state remain
  G3's Flutter work. The viewer gauge is operator/dev inspection of `GET /v1/usage`.
- No §15 recommended default is assumed beyond A15's settlements of OD-2 and OD-15.
