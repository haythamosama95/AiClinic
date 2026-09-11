# Quickstart: Usage summary endpoint and in-app gauge (G3)

G3 freezes an installation-authenticated usage-summary read that answers current-period credits consumed against budget live from the Quota Durable Object and prior-period credits from `usage_rollup`'s quota-weight aggregate, and extends the E4 AI Feature Surface with a simple consumed-versus-budget gauge. The response is credits only; non-enrolled installations hide the gauge with no network probe; platform unreachability is a normal state, not an error dialog.

**Scope rule:** This quickstart covers **only slice G3**. It lists G3 files, G3 tests, and G3 commands — not prior-slice regression suites, combined platform counts, or files from earlier slices.

## 1. Architecture context

- **Delivery plan row:** G3 in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.13 — *Usage summary endpoint and in-app gauge* (`Needs: G2, E4`). Done when an authenticated installation reads current-period credits consumed against budget (live from the Quota DO) and prior periods from `usage_rollup`; the response carries credits only; the Flutter client renders a simple gauge, hides it for non-enrolled installations without probing, and renders platform unreachability as a normal state.
- **Architecture sections:** `§7.6` (usage-summary read path — live current period from the Quota DO, prior periods from `usage_rollup`, different sources), `§4.1` (AI Feature Surfaces — gauge is additive UI with no prompt text, provider names, or model identifiers), **A11** (degraded mode — hide without probe, unreachable is a normal state, no AI failure blocks clinical work), and **A15** (credit-denominated monthly quota; credits-only payload; operator quota inspect stays operator-only).
- **Spec delivered:** Installation-facing `GET /v1/usage` with Bearer AAT; current-period `credits_used` / `credit_budget` live from Quota DO `creditsUsed` against snapshot `credit_budget`; prior periods from `usage_rollup.quota_weight` without scanning `usage_event`; credits-only JSON; taxonomy `unauthenticated` for missing/invalid auth; Flutter consumed-versus-budget gauge; hide-without-probe for non-enrolled; unreachable as E4 normal state; nine named tests (six Workers integration, three Flutter widget spy).
- **Plan scoped:** New `src/usage-summary/` handler and `GET /v1/usage` dispatch in `worker.ts`; forward-only `usage_rollup.quota_weight` column and F3 rollup SUM extension; `UsageSummaryClient` and `UsageGauge` composed on the E4 host; frozen `contracts/usage-summary.md` and `data-model.md`; Consumes G2 (`inspectRPC`) and E4 (availability/degraded/host) extended, not rewritten; operator `quota-inspect.ts` stays operator-only.

## 2. What was implemented

- **Installation-facing `GET /v1/usage`** — Bearer AAT via the same `EnrolledKeyVerifier` as I2; occasional read off the request path.
- **Credits-only payload** — `{ current_period, prior_periods }` with `credits_used` and `credit_budget`; no provider prices, token fields, or cost actuals.
- **`usage_rollup.quota_weight` SUM extension** — F3 `aggregateUsageEvents` adds `SUM(usage_event.quota_weight)`; `request_count`, `tokens`, and `cost` meanings unchanged.
- **Flutter consumed-versus-budget gauge** — `UsageGauge` under `features/ai/surface/`; no prompt text, provider names, or model identifiers.
- **Hide without probe** — non-enrolled installations never call `UsageSummaryClient`; gauge gate renders nothing.
- **Unreachable as a normal state** — enrolled but unreachable uses E4 `AiDegradedMode.unreachable`; not an error dialog; clinical work continues.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/migrations/20260911180000_usage_rollup_quota_weight.sql` | Forward-only `ALTER TABLE usage_rollup ADD COLUMN quota_weight` |
| `ai-platform/schema.snap.sql` | Pins `usage_rollup.quota_weight INTEGER NOT NULL DEFAULT 0` |
| `ai-platform/src/rollup/index.ts` | `SUM(usage_event.quota_weight)` in aggregation; INSERT/UPSERT the new column |
| `ai-platform/src/usage-summary/index.ts` | Installation-facing handler: AAT verify, `inspectRPC` for live counters, D1 rollup select for history, credits-only JSON |
| `ai-platform/src/worker.ts` | Dispatches `GET /v1/usage` next to I2 `GET /v1/capabilities` |
| `ai-platform/test/usage-summary.test.ts` | Six named Workers integration cases (one spy): `usage_summary_current_period_live_from_quota_do` through `usage_summary_credits_only_no_prices_tokens_or_cost_actuals` |
| `frontend/lib/core/ai/usage_summary_client.dart` | Occasional `GET /v1/usage` with Bearer AAT and injectable `http.Client` |
| `frontend/lib/features/ai/surface/usage_gauge.dart` | Simple consumed-versus-budget UI |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | Composes gauge when enrolled and reachable; hide-without-probe; unreachable normal state |
| `frontend/test/widget/ai/usage_gauge_test.dart` | Three named Flutter widget (spy) cases: `gauge_renders_consumed_versus_budget` through `gauge_unreachable_is_normal_state_not_error_dialog` |
| `specs/058-usage-summary-gauge/data-model.md` | `usage_rollup.quota_weight` column semantics and aggregation binding |
| `specs/058-usage-summary-gauge/contracts/usage-summary.md` | Frozen: route, Bearer AAT, credits-only JSON, taxonomy `unauthenticated` |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run --config vitest.workers.config.ts test/usage-summary.test.ts
```

Expected for this slice: **6 passing tests** in `usage-summary.test.ts` (`usage_summary_current_period_live_from_quota_do`, `usage_summary_prior_periods_from_usage_rollup`, `usage_rollup_carries_quota_weight_aggregate`, `usage_summary_live_and_historical_from_different_sources`, `usage_summary_unauthenticated_taxonomy_unauthorized`, `usage_summary_credits_only_no_prices_tokens_or_cost_actuals`). Do not run `npm test` for the full platform suite.

```bash
cd frontend
flutter test test/widget/ai/usage_gauge_test.dart
```

Expected for this slice: **3 passing tests** (`gauge_renders_consumed_versus_budget`, `gauge_non_enrolled_hides_with_no_network_probe`, `gauge_unreachable_is_normal_state_not_error_dialog`).

To run a subset of this slice's tests:

```bash
cd ai-platform
npx vitest run --config vitest.workers.config.ts test/usage-summary.test.ts -t usage_summary_current_period_live_from_quota_do

cd frontend
flutter test test/widget/ai/usage_gauge_test.dart --plain-name gauge_non_enrolled_hides_with_no_network_probe
```

## 5. Inspect the changes

1. Grep for the route and column:

```bash
cd ai-platform
rg 'GET /v1/usage|/v1/usage' src/worker.ts src/usage-summary/
rg 'quota_weight' src/rollup/index.ts src/usage-summary/index.ts migrations/20260911180000_usage_rollup_quota_weight.sql
```

2. Read the frozen contract and data model — `specs/058-usage-summary-gauge/contracts/usage-summary.md` and `specs/058-usage-summary-gauge/data-model.md`.
3. Open `ai-platform/src/usage-summary/index.ts` — live current period via internal `inspectRPC`; prior periods from `usage_rollup.quota_weight` SELECT; no `usage_event` scan.
4. Open `frontend/lib/features/ai/host/ai_feature_host_page.dart` — gauge composed only when enrolled and reachable; `UsageGaugeGate` for non-enrolled; `UsageGaugeUnreachableMarker` for unreachable.
5. Confirm operator `quota-inspect.ts` is **not** opened to installations — route remains `GET /control/installations/:id/quota` under `src/control/`; installations use `GET /v1/usage` only.
6. Confirm Consumes G2/E4 modules are **not** rewritten — `ai-platform/src/quota-do/index.ts`, `frontend/lib/features/ai/availability/`, `frontend/lib/features/ai/degraded/`, and `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` are unchanged aside from E4 host compose.

## 6. Manual validation

Optional (DP-3 — widget and Worker suites are the primary verification path):

- **Enrolled host** — with a reachable platform and valid AAT, the AI feature host shows the consumed-versus-budget gauge.
- **Non-enrolled** — with AI disabled for the installation, the gauge is absent and no `GET /v1/usage` request is issued.
