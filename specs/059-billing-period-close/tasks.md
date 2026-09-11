# Tasks: Billing period close and invoice generation (G4)

**Input**: Design documents from `specs/059-billing-period-close/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` and `contracts/` (`invoice.md`, `period-close.md`, `price-list-activation.md`, `invoice-evidence.md`) are already frozen on disk (written during the plan phase). `AVAILABLE_DOCS`: `data-model.md`, `contracts/`. `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (fifteen cases) is covered by its own task, written to fail before the `invoice` table, `runPeriodClose`, Worker cron branch, and `handleCreditPriceActivate` exist. Layers are **Scheduled job** (`period-close.test.ts`) and **Workers integration** (`price-list-activation.test.ts`, including two spy cases) (delivery plan §3.12.10 row G4; §13.5 Pipeline tests). Spy cases (`no_payment_provider_call`, `invoice_prices_through_credit_price_not_token_rate_artifact`) each have their own task. Permanent suite joins CI (delivery plan §3.11).

**Organization**: One user story (US1, P1) — G4 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — plan Files names `vitest.workers.config.ts` and `vitest.config.ts` so this slice's two workers files join the workers pool and are excluded from the Node pool. No Foundational or Polish phase — prerequisites are already-merged Needs (G1, F3) in the plan's Consumes Binding.

**Task count**: 25 (≤25). Related tasks were combined to fit the cap: FR-020 `invoice` migration + `schema.snap.sql` + harness wipe (plan Sequencing step 2; same FR cluster / same files that must exist together). Named tests were not dropped or merged. Unrelated work was not merged.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by G4*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by G4*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/059-billing-period-close/`
- Period close lands as new `ai-platform/src/period-close/` (not `src/rollup/`). Price-list activation lands as `ai-platform/src/control/credit-price.ts`, wired only through G1/B2 `dispatchControlRequest` / `isControlRoute`. Worker `scheduled` gains cron `"0 5 1 * *"`. Consumed F3 `src/rollup/index.ts`, G1 `plan.ts` / `entitle.ts` / `auth.ts` / `http.ts` / `audit.ts`, and `src/pricing/index.ts` stay unmodified. Frozen Consumes contract files (`specs/056-plan-catalogue/contracts/credit-price.md`, `specs/041-support-retention-rollups/contracts/usage-rollup-reconciliation.md`) are not edited (delivery plan §2.3).

---

## Phase 1: Setup (Test harness)

**Purpose**: Plan Files names `ai-platform/vitest.workers.config.ts` and `ai-platform/vitest.config.ts` so this slice's two workers files join the workers pool and are excluded from the Node pool before or alongside the Tests phase.

- [X] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/period-close.test.ts"` and `"test/price-list-activation.test.ts"` to `include`. Modify `ai-platform/vitest.config.ts` — add those same two paths to `exclude`, so the workers-pool-only cases do not double-run in the default Node pool (plan → Files). No FR — harness; required by every named scheduled-job and integration test. Prepares the Phase 2 workers substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.12.10 row G4). Eight scheduled-job cases live in `ai-platform/test/period-close.test.ts`. Seven Workers integration cases (activation, evidence, two spies) live in `ai-platform/test/price-list-activation.test.ts`. Until the `invoice` table, `runPeriodClose`, and activation handler exist, assertions fail — the intended red state. The two suite files are `[P]` relative to each other; within each file, append sequentially.

- [X] T002 [US1] Create `ai-platform/test/period-close.test.ts` as Workers scheduled-job suite (plan Test Layout). Substrate: `beforeAll` applies A5 + G1 + `usage_rollup.quota_weight` + this slice's `invoice` migration (same `?raw` pattern as `rollup-reconciliation.test.ts`); seed `installation`, `entitlement` with `status = 'active'`, `usage_rollup` rows whose `dimensions` JSON is `{ installation_id, period }` and whose `quota_weight` is the consumed-credits figure (tokens/cost set to values that would disagree if `src/pricing/` were used); seed `credit_price` rows with ISO-8601 `active_from`. Close cases call `runPeriodClose({ db, period: "2026-08" })`. Add named test `close_one_invoice_per_active_installation`: given an `active` installation, a calendar-month period with consumed credits on `usage_rollup`, and a `credit_price` version active for that period, close writes exactly one immutable `invoice` carrying installation, period, credits consumed, that credit price list version, total, status, and `issued_at`, priced through that version (Delivery Plan §3.12.10 G4 *Close*; A15; §7.3; §4.5). Fails red until `runPeriodClose` and the `invoice` table exist. **Satisfies**: FR-007, FR-008, FR-009 / SC-001. **Proves**: `close_one_invoice_per_active_installation`.

- [X] T003 [US1] Add named test `close_one_invoice_each_of_two_active_installations` to `ai-platform/test/period-close.test.ts`: two `active` installations with consumption in the same period each receive exactly one `invoice`; none that combine installations (Delivery Plan §3.12.10 G4 *Close*; §7.3). Fails red until close iterates `active` entitlements independently. **Satisfies**: FR-007 / SC-001. **Proves**: `close_one_invoice_each_of_two_active_installations`.

- [X] T004 [US1] Add named test `close_rerun_idempotent` to `ai-platform/test/period-close.test.ts`: a second close of the same period writes no additional `invoice` and does not mutate credits consumed, credit price list version, total, status, or `issued_at` (Delivery Plan §3.12.10 G4 *Close*; A15; §7.3). Fails red until INSERT is idempotent (`ON CONFLICT DO NOTHING`; no UPDATE of issued rows). **Satisfies**: FR-011 / SC-002. **Proves**: `close_rerun_idempotent`.

- [X] T005 [US1] Add named test `close_zero_consumption_no_invoice` to `ai-platform/test/period-close.test.ts`: an `active` installation whose period has `SUM(usage_rollup.quota_weight) = 0` receives no `invoice` (Delivery Plan §3.12.10 G4 *Close*; A15; §4.5). Fails red until close skips zero-consumption installations. **Satisfies**: FR-012 / SC-002. **Proves**: `close_zero_consumption_no_invoice`.

- [X] T006 [US1] Add named test `close_freezes_usage_rollup_without_rewriting_rows` to `ai-platform/test/period-close.test.ts`: snapshot `usage_rollup` before/after close (deep-equal) and assert `runRollup` is not invoked — close freezes the period's rows as invoice evidence and does not rewrite F3 rollup production (A15; Delivery Plan §3.13 "not a rollup change"). Absence of the rollup rewrite/call is separate from T002–T005 outcome asserts. Fails red until close reads rollup without UPDATE/DELETE and without importing `src/rollup/`. **Satisfies**: FR-006 / SC-006. **Proves**: `close_freezes_usage_rollup_without_rewriting_rows`.

- [X] T007 [US1] Add named test `close_prices_through_latest_version_active_at_period_start` to `ai-platform/test/period-close.test.ts`: several `credit_price` versions whose `active_from` all fall at or before the period start (`{period}-01T00:00:00.000Z`) — the invoice carries the latest such version (greatest `active_from` ≤ period start) (A15 item 5; §7.3). Fails red until version resolution is latest-`active_from`-at-or-before-period-start. **Satisfies**: FR-008, FR-023 / SC-001. **Proves**: `close_prices_through_latest_version_active_at_period_start`.

- [X] T008 [US1] Add named test `mid_period_activation_does_not_apply_to_current_period` to `ai-platform/test/period-close.test.ts`: a version whose `active_from` falls inside the current unclosed period does not price that period; close still uses the latest version with `active_from` at or before the period start (A15 item 5; §7.3). Fails red until mid-period `active_from` is excluded. **Satisfies**: FR-023, FR-025 / SC-001. **Proves**: `mid_period_activation_does_not_apply_to_current_period`.

- [X] T009 [US1] Add named test `close_no_applicable_price_list_no_invoice` to `ai-platform/test/period-close.test.ts`: with consumption but no `credit_price` row whose `active_from` is at or before the period start, close issues no `invoice` and invents no default price or currency — same outcome shape as zero consumption (A15 item 5; §7.3). Fails red until the no-applicable-version skip exists. **Satisfies**: FR-024 / SC-002. **Proves**: `close_no_applicable_price_list_no_invoice`.

- [X] T010 [P] [US1] Create `ai-platform/test/price-list-activation.test.ts` as Workers integration (plan Test Layout). Substrate: same migration apply as T002; operator `SELF.fetch` with bearer `OPERATOR_BEARER_TOKEN` (G1 `plan-catalogue.test.ts` pattern); seed `installation` / `entitlement` / `usage_rollup` / `credit_price` as needed. Add named test `price_list_activation_audited`: `POST /control/credit-price/activate` with operator credentials writes a `credit_price` row (`version`, price per credit, currency, `active_from`, `activated_by`) and a `control_audit` row carrying the operator identity (`action = credit_price_activate`) (Delivery Plan §3.12.10 G4 *Price list*; §4.5; §7.3). Fails red until `handleCreditPriceActivate` and dispatch wiring exist. **Satisfies**: FR-003, FR-013 / SC-003. **Proves**: `price_list_activation_audited`.

- [X] T011 [US1] Add named test `price_list_activation_non_operator_rejected` to `ai-platform/test/price-list-activation.test.ts`: credentials that are not operator identity are rejected (B2 `401 unauthorized`; no new diagnostic code); no `credit_price` or `control_audit` row is written (§4.5). Fails red until the route is operator-gated via `requireOperator`. **Satisfies**: FR-001, FR-004 / SC-003. **Proves**: `price_list_activation_non_operator_rejected`.

- [X] T012 [US1] Add named test `price_list_activation_never_reprices_closed_period` to `ai-platform/test/price-list-activation.test.ts`: after close has invoiced a period through version *V*, activating a new `credit_price` version leaves that invoice's credit price list version and total unchanged (Delivery Plan §3.12.10 G4 *Price list*; A15; §7.3). Fails red until issued invoices are immutable and activation does not UPDATE them. **Satisfies**: FR-014 / SC-003. **Proves**: `price_list_activation_never_reprices_closed_period`.

- [X] T013 [US1] Add named test `invoice_resolves_to_usage_rollup` to `ai-platform/test/price-list-activation.test.ts`: an issued `invoice` resolves to that installation and period's `usage_rollup` rows (Delivery Plan §3.12.10 G4 *Evidence*; §7.3). Evidence cases also seed `usage_event.request_id` as needed. Fails red until close has written the invoice against those rollup rows. **Satisfies**: FR-015 / SC-004. **Proves**: `invoice_resolves_to_usage_rollup`.

- [X] T014 [US1] Add named test `invoice_line_traces_to_request_references` to `ai-platform/test/price-list-activation.test.ts`: any invoice line (`usage_rollup` row for that installation and period) traces through `usage_event.request_id` to `ai_request.request_reference` (Delivery Plan §3.12.10 G4 *Evidence*; §7.3; A15). Seed `usage_event` and `ai_request.request_reference`. Fails red until the evidence join is asserted. **Satisfies**: FR-016 / SC-004. **Proves**: `invoice_line_traces_to_request_references`.

- [X] T015 [US1] Add named spy test `no_payment_provider_call` to `ai-platform/test/price-list-activation.test.ts`: wrap `globalThis.fetch` and assert zero calls whose URL looks like a payment provider, after both `runPeriodClose` and price-list activation (Delivery Plan §3.12.10 G4 *Evidence*; A15; §12.3; §4.5). Spy — absence of the call is separate from T010–T014 outcome asserts. Production code gains **no** payment-provider port (D-15). Fails red if either path performs a payment-provider fetch. **Satisfies**: FR-002, FR-019 / SC-005. **Proves**: `no_payment_provider_call`.

- [X] T016 [US1] Add named spy test `invoice_prices_through_credit_price_not_token_rate_artifact` to `ai-platform/test/price-list-activation.test.ts`: `vi.spyOn` on `priceUsage`, `ledgerUsageFromProvider`, and `ratesForModel` from `ai-platform/src/pricing/index.ts` asserting zero calls; `invoice.total` equals `credits_consumed * price_per_credit` for the resolved `credit_price` version; credits consumed = `SUM(usage_rollup.quota_weight)` — ledger tokens/cost MUST NOT determine the debit (A15 item 5; Delivery Plan §3.13). Spy — unused `src/pricing/` is separate from T002's priced-invoice outcome. Fails red until totals come from `credit_price` only. **Satisfies**: FR-010, FR-017 / SC-005. **Proves**: `invoice_prices_through_credit_price_not_token_rate_artifact`.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Setup (T001), Tests (Phase 2), or Documentation. Order follows plan Sequencing (migration cluster → period-close job → Wrangler cron + Worker scheduled wiring → price-list activation). Consumed F3 `src/rollup/`, G1 `plan.ts` / `entitle.ts` / operator auth / audit helpers, and `src/pricing/` stay unmodified (delivery plan §2.3). No `frontend/` or `backend/` file. Test-file Files-section rows (`period-close.test.ts`, `price-list-activation.test.ts`) are produced by Phase 2. `data-model.md` and the four contracts are already frozen — no task recreates them. FR-020 migration + snapshot + harness wipe are one task (related Files in plan Sequencing step 2) so the list fits ≤25.

- [ ] T017 [US1] Create `ai-platform/migrations/20260911200000_invoice.sql` — forward-only additive `CREATE TABLE invoice` with installation, period, credits consumed, credit price list version, total, status, `issued_at`; natural key `PRIMARY KEY (installation_id, period)` (one row per installation per calendar month). No freeze column on `usage_rollup`. No `invoice_line` table. No FK invented beyond existing A5 conventions. Then modify `ai-platform/schema.snap.sql` so the snapshot includes `invoice`, and modify `ai-platform/test/system/harness.ts` to `DELETE FROM invoice` in the shared wipe (same as G1 `credit_price`). Do not rewrite G1 `credit_price` DDL or F3 rollup schema. Do not write into Supabase. **Satisfies**: FR-020, FR-009, FR-011, FR-021. **Proved by**: `close_one_invoice_per_active_installation`, `close_rerun_idempotent`, `close_one_invoice_each_of_two_active_installations`.

- [ ] T018 [US1] Create `ai-platform/src/period-close/index.ts` — `runPeriodClose({ db, period })`: select entitlements with `status = 'active'`; credits consumed = `SUM(usage_rollup.quota_weight)` for that installation and period (`dimensions` JSON `{ installation_id, period }`); resolve the latest `credit_price` with `active_from` ≤ period start (`{period}-01T00:00:00.000Z`); INSERT immutable `invoice` (`status = "issued"`; total = `credits_consumed * price_per_credit`) or skip (zero consumption / no applicable price — no default price or currency); `ON CONFLICT DO NOTHING`; never UPDATE issued rows or `usage_rollup`; do not import `src/rollup/` or `src/pricing/`; do not call a payment provider; do not extend the config cache (request path never sees a price). Calendar month is the invoiced period; quota unit remains the AI credit. Depends on T017 (table exists). **Satisfies**: FR-002, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-017, FR-018, FR-019, FR-023, FR-024, FR-025. **Proved by**: `close_one_invoice_per_active_installation`, `close_one_invoice_each_of_two_active_installations`, `close_rerun_idempotent`, `close_zero_consumption_no_invoice`, `close_freezes_usage_rollup_without_rewriting_rows`, `close_prices_through_latest_version_active_at_period_start`, `mid_period_activation_does_not_apply_to_current_period`, `close_no_applicable_price_list_no_invoice`, `invoice_prices_through_credit_price_not_token_rate_artifact`, `no_payment_provider_call`.

- [ ] T019 [P] [US1] Modify `ai-platform/wrangler.toml` — append `"0 5 1 * *"` to `[triggers] crons` (05:00 UTC on the 1st, after F3's daily `0 4 * * *` rollup; distinct from the unrecognized-cron fixture `"0 5 * * *"`). Do not change F3 `0 3 * * *` / `0 4 * * *`. **Satisfies**: FR-006. **Proved by**: `close_one_invoice_per_active_installation` (job exists as a scheduled close; cron string inspected under Verification).

- [ ] T020 [US1] Modify `ai-platform/src/worker.ts` — `scheduled` maps cron `"0 5 1 * *"` plus `scheduledTime` to the **previous** UTC calendar month (`YYYY-MM`) and calls `runPeriodClose`. Leave F3 `0 3` / `0 4` branches untouched. No new deployable. Depends on T018 and T019. **Satisfies**: FR-006, FR-021. **Proved by**: `close_one_invoice_per_active_installation`, `close_freezes_usage_rollup_without_rewriting_rows`.

- [ ] T021 [P] [US1] Modify `ai-platform/src/control/types.ts` — add `CreditPriceActivatePayload` only (`version`, price per credit, currency, `active_from`). Do not alter G1 plan/entitle payloads or B2 lifecycle types. **Satisfies**: FR-013. **Proved by**: `price_list_activation_audited`.

- [ ] T022 [US1] Create `ai-platform/src/control/credit-price.ts` — `handleCreditPriceActivate` as an operator-authenticated control-plane mutation: INSERT `credit_price` (`version`, price per credit, currency, `active_from`, `activated_by`); journal `control_audit` with operator identity and `action = credit_price_activate`; reject non-operator with B2 `401 unauthorized` (no new diagnostic code) and write neither `credit_price` nor `control_audit`; do not UPDATE issued `invoice` rows. Use B2/G1 `requireOperator` / `writeAudit` helpers — Consumes, do not rewrite `auth.ts` / `http.ts` / `audit.ts`. Do not call a payment provider. Depends on T021. **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-013, FR-014, FR-019. **Proved by**: `price_list_activation_audited`, `price_list_activation_non_operator_rejected`, `price_list_activation_never_reprices_closed_period`, `no_payment_provider_call`.

- [ ] T023 [US1] Modify `ai-platform/src/control/index.ts` — extend `isControlRoute` / `dispatchControlRequest` for `POST /control/credit-price/activate` without altering G1 plan/entitle or other control routes (Consumes G1/B2 barrel). Depends on T022. **Satisfies**: FR-001, FR-004. **Proved by**: `price_list_activation_audited`, `price_list_activation_non_operator_rejected`.

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T024 [US1] From `ai-platform/`, run this slice's Workers suite — `npx vitest run --config vitest.workers.config.ts test/period-close.test.ts` (named cases `close_one_invoice_per_active_installation`, `close_one_invoice_each_of_two_active_installations`, `close_rerun_idempotent`, `close_zero_consumption_no_invoice`, `close_freezes_usage_rollup_without_rewriting_rows`, `close_prices_through_latest_version_active_at_period_start`, `mid_period_activation_does_not_apply_to_current_period`, `close_no_applicable_price_list_no_invoice`) and `npx vitest run --config vitest.workers.config.ts test/price-list-activation.test.ts` (named cases `price_list_activation_audited`, `price_list_activation_non_operator_rejected`, `price_list_activation_never_reprices_closed_period`, `invoice_resolves_to_usage_rollup`, `invoice_line_traces_to_request_references`, `no_payment_provider_call`, `invoice_prices_through_credit_price_not_token_rate_artifact`). Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, including F3 `rollup-reconciliation.test.ts` and G1 `plan-catalogue.test.ts`). Confirm G4's fifteen named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions: `src/rollup/index.ts`, G1 `plan.ts` / `entitle.ts`, and `src/pricing/index.ts` untouched; no invoice HTTP read surface (V4); no payment-provider module; no usage-summary gauge, credit debit, overage, self-service enrollment, or payment collection (FR-022); Consumes contract files not rewritten; no §9.14 mechanism; no second Quota DO / R2; no per-request server-side state; no write path into Supabase (delivery plan §6.4). **Satisfies**: the §3.10 checkpoint rule (fifteen named tests + prior suites); FR-018, FR-021, FR-022. Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. `data-model.md` and the four contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T025 [US1] Create `specs/059-billing-period-close/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.13 row G4 and §7.3 / §4.5 / §12.3 / A15; what the spec delivered; what the plan scoped. **§2 What was implemented** — additive `invoice` migration; scheduled period-close job outside `src/rollup/`; operator `credit_price` activation on G1's control plane; evidence as `usage_rollup` lines traced through `usage_event` to `ai_request`; no payment-provider integration; `src/pricing/` unused for totals. **§3 Files to review** — only this slice's migration, `src/period-close/`, `src/control/credit-price.ts`, Worker cron wiring, this slice's workers test files, and the schema snapshot (no prior-slice files). **§4 Prerequisites** — Node/workers pool; `OPERATOR_*` bindings when exercising `SELF.fetch` control e2e (same as B2/G1). **§5 Run the automated suite** — slice-only `npx vitest run --config vitest.workers.config.ts test/period-close.test.ts` and `npx vitest run --config vitest.workers.config.ts test/price-list-activation.test.ts`; no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open migration + `period-close/index.ts` + `credit-price.ts`; grep `invoice` / `credit_price_activate` / cron `0 5 1 * *`; confirm `src/rollup/` and `src/pricing/` not used for close totals. **No §7 Manual validation** — CI is the only verification path beyond the suite (plan: close, activation, evidence, and spies are fully named in the fifteen tests). Renumber remaining sections sequentially with no gaps. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — none; can start immediately. Workers-pool include / Node-pool exclude for both new test files.
- **Tests (T002–T016)** — T002 depends on T001 (workers include). T003–T009 append sequentially after T002 (same `period-close.test.ts`). T010 is `[P]` relative to T002–T009 (different file) and also depends on T001; T011–T016 append sequentially after T010 (same `price-list-activation.test.ts`). Written to fail before the `invoice` table / `runPeriodClose` / activation handler exist.
- **Implementation (T017–T023)** — after tests exist (red). Order follows plan Sequencing: FR-020 cluster (T017) → period-close job (T018) → Wrangler cron (T019) + Worker scheduled wiring (T020) → types (T021) → `credit-price.ts` (T022) → dispatch (T023).
- **Verification (T024)** — depends on T001–T023; runs this slice's workers suites plus every prior suite per §3.10.
- **Documentation (T025)** — depends on T024 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: `invoice` migration + snapshot + harness wipe (T017) → `runPeriodClose` (T018) → cron `"0 5 1 * *"` (T019) → `scheduled` previous-UTC-month branch (T020) → `CreditPriceActivatePayload` (T021) → `handleCreditPriceActivate` (T022) → control dispatch (T023); Documentation last.
- Test-file and harness Files-section rows are produced by Phase 1–2. Remaining Files units are T017–T023 plus T025 (`quickstart.md`). Contract and data-model are already frozen — no task recreates them.

### Parallel Opportunities

- Phase 1 (T001) is a single harness-pair task — no internal parallelism.
- Phase 2: T010 is `[P]` relative to T002–T009 (activation suite vs scheduled-job suite — different files). Within each suite file, append sequentially (no `[P]`). Spy cases T015 and T016 remain separate tasks from each other and from outcome asserts T010–T014; T006's rollup-absence assert remains separate from T002–T005 outcomes.
- Phase 3: T018 depends on T017 (table must exist). T019 is `[P]` relative to T017–T018 (wrangler cron vs migration/period-close — different files). T021 is `[P]` relative to T017–T020 (payload types vs close/cron — different files). T020 depends on T018 and T019. T022 depends on T021. T023 depends on T022.
- Phase 5 (T025) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T010, T019, T021.
- Every named test from `spec.md` is covered by its own task; no test is folded into another. Spy cases `no_payment_provider_call` (payment-provider absence) and `invoice_prices_through_credit_price_not_token_rate_artifact` (`src/pricing/` unused) are each a separate task.
- Related implementation tasks combined to fit ≤25: T017 covers `ai-platform/migrations/20260911200000_invoice.sql`, `ai-platform/schema.snap.sql`, and `ai-platform/test/system/harness.ts` (FR-020; plan Sequencing step 2). Named tests were not combined.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart / harness Setup. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are G1, F3 (Consumes Binding).
- Consumed modules are imported/bound, not rewritten (delivery plan §2.3 — extend, never rewrite). G4 does not absorb G1 catalogue/assignment, G2 debit, G3 gauge, F3 rollup production, V4 invoice UI, or Band L payment collection (FR-022).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism; no second Quota DO or R2 object; no per-request server-side state; no Flutter invoice UI (V4 later); request path never sees a price (FR-018); no payment-provider port (FR-019).
