# Tasks: Usage summary endpoint and in-app gauge (G3)

**Input**: Design documents from `specs/058-usage-summary-gauge/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` and `contracts/` (`usage-summary.md`) are already frozen on disk (written during the plan phase). `AVAILABLE_DOCS`: `data-model.md`, `contracts/`. `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (nine cases) is covered by its own task, written to fail before the usage-summary handler, `usage_rollup.quota_weight` column, rollup SUM extension, Flutter GET client, and gauge exist. Layers are **Workers integration** (`usage-summary.test.ts`) and **Flutter widget (spy)** (`usage_gauge_test.dart`) (delivery plan §3.12.10 row G3; §13.5 Pipeline tests + Flutter widget suite). Spy cases (`usage_summary_live_and_historical_from_different_sources`, `gauge_non_enrolled_hides_with_no_network_probe`, `gauge_unreachable_is_normal_state_not_error_dialog`) each have their own task. Permanent suite joins CI (delivery plan §3.11).

**Organization**: One user story (US1, P1) — G3 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts and data-model are already on disk; plan Files are produced by Tests / Implementation / Documentation. No Foundational or Polish phase — prerequisites are already-merged Needs (G2, E4) in the plan's Consumes Binding.

**Task count**: 19 (≤25). Related tasks were not combined — the naive split already fits the cap.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by G3*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/058-usage-summary-gauge/`
- Worker handler lives in new `ai-platform/src/usage-summary/` wired from `ai-platform/src/worker.ts` next to I2 `GET /v1/capabilities`, not from `src/control/`. Flutter GET lives in `frontend/lib/core/ai/usage_summary_client.dart` beside `DiscoveryClient`. Gauge lives under `frontend/lib/features/ai/surface/` and is composed on the E4 host. Consumed G2 `src/quota-do/index.ts` (`inspectRPC`) and E4 availability/degraded/draft-accept-discard stay unmodified aside from the listed host compose. Operator `src/control/quota-inspect.ts` stays operator-only. Frozen Consumes contract files are not edited (delivery plan §2.3).

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.12.10 row G3). Six Workers integration cases (one spy) live in `ai-platform/test/usage-summary.test.ts`. Three Flutter widget cases (two spies) live in `frontend/test/widget/ai/usage_gauge_test.dart`. Until `GET /v1/usage`, `usage_rollup.quota_weight`, and the gauge exist, assertions fail — the intended red state. Worker file vs Flutter file are `[P]`; within each file, append sequentially.

- [X] T001 [US1] Create `ai-platform/test/usage-summary.test.ts` as Workers integration (plan Test Layout). Register `test/usage-summary.test.ts` in `ai-platform/vitest.workers.config.ts` `include` and `ai-platform/vitest.config.ts` `exclude` so the six cases join the workers pool and do not double-run in the Node pool (plan Testing; delivery plan §3.11). Substrate: apply `ai-platform/migrations/20260911180000_usage_rollup_quota_weight.sql` in `beforeAll`; Bearer AAT via I2 enrolled-key verifier; seed G2 Quota DO `creditsUsed` / snapshot `credit_budget`; seed `usage_rollup` rows. Add named test `usage_summary_current_period_live_from_quota_do`: authenticated `GET /v1/usage` current-period `credits_used` / `credit_budget` match live Quota DO `creditsUsed` against snapshot `credit_budget` (Delivery Plan §3.12.10 G3 *Endpoint*; A15; §7.6). Fails red until the handler reads `inspectRPC` + entitlements snapshot. Do not open `src/control/quota-inspect.ts` to installations. **Satisfies**: FR-001 / SC-001. **Proves**: `usage_summary_current_period_live_from_quota_do`.

- [X] T002 [US1] Add named test `usage_summary_prior_periods_from_usage_rollup` to `ai-platform/test/usage-summary.test.ts`: authenticated read, prior `credits_used` equals `usage_rollup.quota_weight` for this installation excluding the current period key; SQL / spy shows no `usage_event` scan (Delivery Plan §3.12.10 G3 *Endpoint*; A15; §7.3; §7.6). Fails red until the handler SELECTs `usage_rollup.quota_weight` and does not scan the ledger. **Satisfies**: FR-001, FR-013 / SC-001. **Proves**: `usage_summary_prior_periods_from_usage_rollup`.

- [X] T003 [US1] Add named test `usage_rollup_carries_quota_weight_aggregate` to `ai-platform/test/usage-summary.test.ts`: after F3 `runRollup`, `usage_rollup.quota_weight` equals `SUM(usage_event.quota_weight)` for that installation/period; `request_count`, `tokens`, and `cost` keep prior meanings (Delivery Plan §2.3; A15; §7.3). Fails red until aggregation and UPSERT include the SUM. Do not weaken F3 equality assertions. **Satisfies**: FR-013 / SC-001. **Proves**: `usage_rollup_carries_quota_weight_aggregate`.

- [X] T004 [US1] Add named spy test `usage_summary_live_and_historical_from_different_sources` to `ai-platform/test/usage-summary.test.ts`: spy — live current-period answer is not served from `usage_rollup`; historical answer is not served from the Quota DO (§7.6 constraint; Delivery Plan §3.11 every named boundary). Spy — source absence is separate from T001–T003 outcome asserts. Fails red until the two answers come from different places. **Satisfies**: FR-002 / SC-001. **Proves**: `usage_summary_live_and_historical_from_different_sources`.

- [X] T005 [US1] Add named test `usage_summary_unauthenticated_taxonomy_unauthorized` to `ai-platform/test/usage-summary.test.ts`: missing/invalid installation auth → taxonomy `unauthenticated` (HTTP 401 via `liveHttpStatusForCode("unauthenticated")`); no credits body (Delivery Plan §3.12.10 G3 *Endpoint*; Delivery Plan §3.11 every error code; A2 closed set). Fails red until the handler rejects unauthenticated callers. `quota_exhausted` is not emitted here. **Satisfies**: FR-006 / SC-002. **Proves**: `usage_summary_unauthenticated_taxonomy_unauthorized`.

- [X] T006 [US1] Add named test `usage_summary_credits_only_no_prices_tokens_or_cost_actuals` to `ai-platform/test/usage-summary.test.ts`: response JSON has no provider prices, no token fields, no cost actuals (Delivery Plan §3.12.10 G3 *Endpoint*; A15; `contracts/usage-summary.md` §4.3). Fails red until the payload is credits-only `{ current_period, prior_periods }`. **Satisfies**: FR-004 / SC-003. **Proves**: `usage_summary_credits_only_no_prices_tokens_or_cost_actuals`.

- [X] T007 [P] [US1] Create `frontend/test/widget/ai/usage_gauge_test.dart` as Flutter widget suite (plan Test Layout). Reuse E4 host spies (`PlatformNetworkSpy`, availability reader, reachability port) from `frontend/lib/features/ai/host/ai_feature_host_page.dart` / existing widget harness — do not rewrite E4 draft/accept/discard tests. Add named test `gauge_renders_consumed_versus_budget`: enrolled and reachable, the gauge shows consumed versus budget (Delivery Plan §3.12.10 G3 *Client*; A15). Fails red until `UsageGauge` is composed on the E4 host. No prompt text, provider name, or model identifier. **Satisfies**: FR-003, FR-005 / SC-004. **Proves**: `gauge_renders_consumed_versus_budget`.

- [X] T008 [US1] Add named spy test `gauge_non_enrolled_hides_with_no_network_probe` to `frontend/test/widget/ai/usage_gauge_test.dart`: non-enrolled — gauge hidden; network spy shows no usage-summary GET (Delivery Plan §3.12.10 G3 *Client*; A11; §4.1). Spy — absence of the probe is separate from T007's render assert. Fails red until the host hides without calling `UsageSummaryClient`. **Satisfies**: FR-008 / SC-005. **Proves**: `gauge_non_enrolled_hides_with_no_network_probe`.

- [X] T009 [US1] Add named spy test `gauge_unreachable_is_normal_state_not_error_dialog` to `frontend/test/widget/ai/usage_gauge_test.dart`: enrolled but unreachable platform → E4 unreachable normal state, not an error dialog; clinical work not blocked (Delivery Plan §3.12.10 G3 *Client*; A11). Spy — unreachability presentation is separate from T008's no-probe absence. Fails red until the host reuses E4 degraded unreachable rather than an error dialog. **Satisfies**: FR-009, FR-010 / SC-005. **Proves**: `gauge_unreachable_is_normal_state_not_error_dialog`.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Tests (Phase 1) or Documentation. Order follows plan Sequencing (D1 column + schema snapshot → rollup SUM → usage-summary handler → Worker dispatch → Flutter GET + gauge + host compose). Consumed G2 DO admission/credit, E4 draft/accept/discard / availability / degraded modules, operator quota inspect, and F3 cadence/retention/purge/reconciliation stay unchanged aside from the listed rollup SUM extension (delivery plan §2.3). No `backend/` file. No new table. Test-file Files-section rows (`usage-summary.test.ts`, `usage_gauge_test.dart`) are produced by Phase 1. `data-model.md` and `contracts/usage-summary.md` are already frozen — no task recreates them.

- [X] T010 [US1] Create `ai-platform/migrations/20260911180000_usage_rollup_quota_weight.sql` — `ALTER TABLE usage_rollup ADD COLUMN quota_weight INTEGER NOT NULL DEFAULT 0` (forward-only; A5 discipline). Default 0 keeps existing `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)` statements green. Do not introduce a table; do not rewrite A5 or F3 contract files. **Satisfies**: FR-013. **Proved by**: `usage_rollup_carries_quota_weight_aggregate`, `usage_summary_prior_periods_from_usage_rollup`.

- [X] T011 [P] [US1] Modify `ai-platform/schema.snap.sql` — pin `usage_rollup.quota_weight INTEGER NOT NULL DEFAULT 0` on the existing rollup row. Do not change `request_count` / `tokens` / `cost` meanings. **Satisfies**: FR-013. **Proved by**: `usage_rollup_carries_quota_weight_aggregate`.

- [X] T012 [US1] Modify `ai-platform/src/rollup/index.ts` — extend `UsageAggregate` and both `aggregateUsageEvents` SELECTs with `SUM(usage_event.quota_weight)` as `quota_weight`; INSERT/UPSERT the new column; `request_count` / `tokens` / `cost` unchanged. Do not change F3 cadence, retention, purge, reconciliation flags, or equality-to-ledger for count/tokens/cost. Depends on T010. **Satisfies**: FR-013. **Proved by**: `usage_rollup_carries_quota_weight_aggregate`.

- [X] T013 [P] [US1] Create `ai-platform/src/usage-summary/index.ts` — installation-facing `GET /v1/usage` handler: Bearer AAT via the same `EnrolledKeyVerifier` as I2; unauthenticated → taxonomy `unauthenticated` (no credits body); internal `inspectRPC` for live `creditsUsed`; entitlements snapshot for `credit_budget` and current period key (`periodFromIso(period_start)` → `YYYY-MM`); D1 `SELECT` of `usage_rollup.quota_weight` for this installation excluding the current period; credits-only JSON `{ current_period, prior_periods }` per `contracts/usage-summary.md`; no `usage_event` scan; no write to clinic Supabase; occasional read (not on the inference request path). MAY reuse `inspectRPC`; MUST NOT expose `GET /control/installations/:id/quota`. Do not debit, admit, or set `degraded`. Depends on T010 (column exists for the history SELECT). **Satisfies**: FR-001, FR-002, FR-004, FR-006, FR-011, FR-012, FR-013. **Proved by**: `usage_summary_current_period_live_from_quota_do`, `usage_summary_prior_periods_from_usage_rollup`, `usage_summary_live_and_historical_from_different_sources`, `usage_summary_unauthenticated_taxonomy_unauthorized`, `usage_summary_credits_only_no_prices_tokens_or_cost_actuals`.

- [X] T014 [US1] Modify `ai-platform/src/worker.ts` — dispatch `GET /v1/usage` to the usage-summary handler next to I2 `GET /v1/capabilities`. Do not attach this read to `POST /v1/requests`. Do not open the operator quota inspect route to installations. Depends on T013. **Satisfies**: FR-001, FR-006, FR-012. **Proved by**: `usage_summary_current_period_live_from_quota_do`, `usage_summary_unauthenticated_taxonomy_unauthorized`.

- [X] T015 [P] [US1] Create `frontend/lib/core/ai/usage_summary_client.dart` — occasional `GET /v1/usage` with Bearer AAT and injectable `http.Client` (same shape as `DiscoveryClient`; no extra port interface — D-15). Do not rewrite `discovery_client.dart` or invoke/SSE. Do not call this client from the capability request path. **Satisfies**: FR-005, FR-012. **Proved by**: `gauge_renders_consumed_versus_budget`, `gauge_non_enrolled_hides_with_no_network_probe`.

- [X] T016 [P] [US1] Create `frontend/lib/features/ai/surface/usage_gauge.dart` — simple consumed-versus-budget UI; no analytics dashboard; no prompt text, provider names, model names, or AI business rules (R-12; §4.1). Do not rewrite `first_ai_feature_surface.dart`. **Satisfies**: FR-003, FR-007. **Proved by**: `gauge_renders_consumed_versus_budget`.

- [X] T017 [US1] Modify `frontend/lib/features/ai/host/ai_feature_host_page.dart` — compose `UsageGauge` when enrolled and reachable (via `UsageSummaryClient`); hide with no usage GET when non-enrolled; unreachable uses E4 `AiDegradedMode.unreachable` normal state, not an error dialog; no AI failure blocks clinical work. Do not rewrite draft/accept/discard, provisional content, or request-reference display. Do not rewrite `frontend/lib/features/ai/availability/` or `frontend/lib/features/ai/degraded/`. Depends on T015 and T016. **Satisfies**: FR-003, FR-005, FR-008, FR-009, FR-010. **Proved by**: `gauge_renders_consumed_versus_budget`, `gauge_non_enrolled_hides_with_no_network_probe`, `gauge_unreachable_is_normal_state_not_error_dialog`.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T018 [US1] From `ai-platform/`, run this slice's Workers suite — `npx vitest run --config vitest.workers.config.ts test/usage-summary.test.ts` (named cases `usage_summary_current_period_live_from_quota_do` … `usage_summary_credits_only_no_prices_tokens_or_cost_actuals`). From `frontend/`, run this slice's Flutter suite — `flutter test test/widget/ai/usage_gauge_test.dart` (named cases `gauge_renders_consumed_versus_budget` … `gauge_unreachable_is_normal_state_not_error_dialog`). Confirm FR-007 / E1: paths under `frontend/lib/features/ai/` still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (do not alter the guard). Keep prior Band E Flutter suites green: `flutter test test/widget/ai/first_ai_feature_surface_test.dart test/widget/ai/ai_degraded_mode_test.dart test/widget/ai/live_client_invoke_test.dart test/unit/core/ai/ai_client_sdk_test.dart test/unit/core/ai/context_resolver_test.dart test/unit/core/ai/context_contract_test.dart`. Then from `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, including F3 `rollup-reconciliation.test.ts` and G2 `quota-do.test.ts` / `admission-credit.test.ts`). Confirm G3's nine named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions: Consumes contract files, `src/quota-do/index.ts`, `src/control/quota-inspect.ts`, and E4 draft/accept/discard not rewritten; no `usage_event` scan; no new table; no second request-path Quota DO round trip or second R2 object; no per-request server-side state; no §9.14 mechanism; no prompt/provider/model in the Flutter client; no `backend/` write path (delivery plan §6.4). **Satisfies**: the §3.10 checkpoint rule (nine named tests + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. `data-model.md` and `contracts/usage-summary.md` were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T019 [US1] Create `specs/058-usage-summary-gauge/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.13 row G3; `01-ai-platform.md` §7.6 / §4.1 / A11 / A15; what the spec delivered; what the plan scoped. **§2 What was implemented** — installation-facing `GET /v1/usage`; credits-only payload; `usage_rollup.quota_weight` SUM extension; Flutter consumed-versus-budget gauge; hide without probe; unreachable as a normal state. **§3 Files to review** — only this slice's `src/usage-summary/`, rollup SUM extension, forward migration, Worker route, Flutter `core/ai` GET client and `features/ai` gauge / host compose, this slice's named tests, `data-model.md`, and `contracts/usage-summary.md` (no prior-slice files). **§4 Prerequisites** — omit (`npx vitest run` / `flutter test` against this slice's test files are sufficient). **§5 Run the automated suite** — slice-only `npx vitest run --config vitest.workers.config.ts test/usage-summary.test.ts` (G3's six named Worker tests) and `flutter test test/widget/ai/usage_gauge_test.dart` (G3's three named Flutter tests); no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — grep `GET /v1/usage` and `quota_weight`; read the contract and data-model; confirm operator `quota-inspect.ts` is not opened to installations; confirm Consumes G2/E4 modules are not rewritten. **§7 Manual validation** — optional: enrolled host shows the gauge; non-enrolled hides it. Widget/Worker suites remain the primary verification path (DP-3). Renumber remaining sections sequentially with no gaps (omit §4 Prerequisites and renumber). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T009)** — none beyond already-frozen contracts/data-model and Consumes Binding modules (G2, E4, I2, F3); written to fail before the code exists. T001 creates the workers substrate (migration apply, AAT, DO/rollup seed, vitest pool registration) and the first Worker case. T002–T006 append to `usage-summary.test.ts`. T007 is `[P]` relative to T001–T006 (Flutter file vs Worker file) and creates `usage_gauge_test.dart`; T008–T009 append after T007 (same Flutter file).
- **Implementation (T010–T017)** — after tests exist (red). Order follows plan Sequencing: D1 column (T010) + schema snapshot (T011) → rollup SUM (T012) → usage-summary handler (T013) → Worker dispatch (T014) → Flutter GET (T015) + gauge (T016) → E4 host compose (T017).
- **Verification (T018)** — depends on T001–T017; runs this slice's workers and Flutter suites plus every prior suite per §3.10.
- **Documentation (T019)** — depends on T018 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: `quota_weight` column + snapshot (T010–T011) → `aggregateUsageEvents` SUM (T012) → handler (T013) → `GET /v1/usage` dispatch (T014) → `UsageSummaryClient` + `UsageGauge` + host (T015–T017) → quickstart (T019).
- Test-file Files-section rows for the nine named tests are produced by Phase 1. Remaining Files units are T010–T017 plus T019 (`quickstart.md`). Contract and data-model are already frozen — no task recreates them.

### Parallel Opportunities

- Phase 1: T007 is `[P]` relative to T001–T006 (different file). Within each suite file, append sequentially (no `[P]`). Spy cases T004, T008, and T009 remain separate tasks from each other and from outcome asserts T001–T003 / T005–T007.
- Phase 2: T011 is `[P]` relative to T010 (schema snap vs migration — different files). T013 is `[P]` relative to T012 after T010 (handler vs rollup — different files). T015 and T016 are `[P]` relative to each other and to the Worker chain (Flutter vs Worker; client vs gauge — different files). T012 follows T010. T014 follows T013. T017 follows T015–T016.
- Phase 4 (T019) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T007, T011, T013, T015, T016.
- Every named test from `spec.md` is covered by its own task; no test is folded into another. Spy cases `usage_summary_live_and_historical_from_different_sources` (source absence), `gauge_non_enrolled_hides_with_no_network_probe` (no probe), and `gauge_unreachable_is_normal_state_not_error_dialog` (unreachable presentation) are each a separate task.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are G2, E4 (Consumes Binding).
- Consumed modules are imported/bound, not rewritten (delivery plan §2.3 — extend, never rewrite). G3 does not absorb G2 debit/admission, G4 invoice/activation, G1 catalogue/assignment, E4 draft/accept/discard, F3 cadence/retention/purge, or the operator quota inspect route.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism; no second request-path Quota DO round trip or second R2 object; no per-request server-side state; no prompt/provider/model in the Flutter client; no client-side chunk assembly or committable provisional content.
