# Implementation Plan: Billing period close and invoice generation (G4)

**Branch**: `ai/059-g4-billing-period-close` | **Date**: 2026-09-11 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/059-billing-period-close/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

G4 adds scheduled calendar-month period close and immutable `invoice` generation inside the existing Cloudflare AI Gateway Worker, and is the first writer that activates `credit_price` versions on G1's operator control plane. A close freezes that month's F3 `usage_rollup` as evidence, writes exactly one invoice per `active` installation priced through the latest `credit_price` with `active_from` at or before the period start, and never calls a payment provider or `src/pricing/`. It sits in Band G after G1 and F3 (`Needs: G1, F3`); G3's usage-summary gauge is out of scope.

## Technical Context

**Language/Version**: TypeScript 5.9 (`ai-platform/package.json`) targeting the Cloudflare Worker; D1 SQLite via forward-only Wrangler migrations. Node `>=22` for the Vitest / Wrangler harness.

**Primary Dependencies**: G1 `credit_price` table + operator-authenticated Entitlement management and `control_audit` (`ai-platform/src/control/` — `OperatorAuth` / `requireOperator`, `dispatchControlRequest` / `isControlRoute`, `writeAudit` / in-batch `control_audit`; `credit_price` DDL in `migrations/20260911120000_plan_catalogue.sql`). F3 scheduled `usage_rollup` production (`ai-platform/src/rollup/index.ts` — consumed, not rewritten). `usage_rollup.quota_weight` already present (G3 additive column; credits consumed are that aggregate). Existing Worker `scheduled` handler and crons `0 3 * * *` / `0 4 * * *`. No new npm packages, no Supabase schema, no Flutter surface (V4 later), no payment-provider SDK.

**Storage**: Platform D1 only. Forward-only additive migration creates `invoice` (installation, period, credits consumed, credit price list version, total, status, `issued_at`). Natural key `PRIMARY KEY (installation_id, period)` enforces one row per installation per calendar month. No freeze column on `usage_rollup`. No `invoice_line` table — `usage_rollup` rows for that installation and period are the lines. `credit_price` table shape is unchanged (G4 INSERTs activation rows). No FK invented beyond existing A5 conventions. Config cache is not extended — the request path never sees a price. No write path into Supabase.

**Testing**: Workers integration + scheduled job (`npx vitest run --config vitest.workers.config.ts`) against Miniflare D1. Scheduled-job cases call `runPeriodClose({ db, period })` with an injected calendar-month period (`YYYY-MM`, same key F3 stores on `usage_event.period` / `usage_rollup.dimensions`). Integration cases use B2/G1 `SELF.fetch` operator-auth (bearer `OPERATOR_BEARER_TOKEN`) for price-list activation. Spy cases: `vi.spyOn` on `src/pricing/` exports (`priceUsage` / `ledgerUsageFromProvider` / `ratesForModel`) asserting zero calls; wrap `globalThis.fetch` asserting zero payment-provider URLs — production code gains **no** payment-provider port (D-15). Layers per delivery plan §3.12.10 G4 (*Scheduled job + integration*) mapped to §13.5 Pipeline tests. Suite joins CI permanently (§3.11).

**Target Platform**: `ai-platform/` Cloudflare Worker (D1 + `/control` + `scheduled`). No `frontend/`, no `backend/`. Gateway remains additive, non-primary (§14).

**Project Type**: Band G commercial-surface slice, Worker-only. Not a new deployable. Nothing here is on the request path's latency budget (Delivery Plan §3.13).

**Performance Goals**: Off the inference hot path (Delivery Plan §3.13). No second Quota Durable Object round trip, no second D1 insert on the guard path, no second R2 object per request (§6.1, §7.5, §13.6). No per-request server-side state (§4.4, §9.7). Request path never sees a price (A15; FR-018). Close reads `usage_rollup` / `entitlement` / `credit_price` and writes `invoice`; it does not rewrite rollup rows or change F3 cadence.

**Constraints**:
- Control plane remains separately authenticated by operator identity, not clinic identity, for price-list activation (FR-001, FR-004). Non-operator rejection reuses B2 `401 unauthorized`; no new diagnostic code.
- Period close is a **new scheduled job**, not an Entitlement-management HTTP mutation and not a change to F3 `src/rollup/` (FR-006, FR-021).
- Wrangler cron (implementation choice, not a requirement): `"0 5 1 * *"` — 05:00 UTC on the 1st, after F3's daily `0 4 * * *` rollup, distinct from the unrecognized-cron fixture `"0 5 * * *"`. The handler closes the **previous** UTC calendar month derived from `scheduledTime`; tests inject `period`.
- Invoice totals are `credits_consumed * credit_price.price_per_credit` for the resolved version. Credits consumed = `SUM(usage_rollup.quota_weight)` for that installation and period. Ledger tokens/cost MUST NOT determine the debit (FR-010, FR-017).
- Version active for a period = latest `credit_price` row with `active_from` ≤ period start (`{period}-01T00:00:00.000Z`). Mid-period `active_from` does not apply. No applicable row → no invoice, no default price/currency (FR-023–FR-025, FR-024). Closed invoices never reprice (FR-014).
- `src/pricing/` remains unused for invoice totals (FR-017). No payment-provider call exists (FR-019).
- Invoice `status` is persisted TEXT; this slice writes `"issued"` on insert and never updates the row; it does not freeze a closed enum (spec Assumptions).
- Do not implement usage-summary gauge, credit debit, overage, self-service enrollment, or payment collection (FR-022).
- Do not modify frozen Consumes contracts (G1 `contracts/credit-price.md`, F3 `contracts/usage-rollup-reconciliation.md`) — delivery plan §2.3.

**Scale/Scope**: One §4 component (§4.5 Control plane — see Components Touched). Roughly: one additive `invoice` migration + snapshot, one `period-close` scheduled module outside `src/rollup/`, one `credit-price` activation handler on G1's `/control` barrel, Worker cron wiring, two workers test files, vitest include/exclude, system-harness wipe. Twenty-five FRs. Fifteen named tests. Roughly 20–24 tasks — under the ~25-task ceiling (delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified —
      platform-issued monthly invoices from declared credit prices; no payment-provider
      integration, no self-service enrollment, no hospital-scale billing engine
      (constitution I; spec Clinic Fit; A15).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — additive D1 `invoice` table,
      one new cron on the existing Worker, one `/control` mutation; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated —
      G4 touches only `ai-platform/` (D1, scheduled close, operator price-list
      activation). It does not touch `backend/` or `frontend/`. **§14 acknowledgement:**
      the Worker is an additive, non-primary component with no domain logic, no
      business data, and no write path into Supabase. Period close is a scheduled job
      in the existing Worker; invoices and the versioned credit price list are
      platform D1 commercial records, not clinic business data (A15 constitution check).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — clinic Supabase
      integrity is untouched. Platform D1 integrity is held by the `invoice` natural
      key (one per installation per period), immutability (no UPDATE of issued rows),
      and `control_audit` with operator identity on price-list activation (B2/G1 pattern).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — price-list activation uses operator
      identity (B2 `OperatorAuth`); audited via `control_audit`; invoices are immutable
      once issued. Operator scope is correctly above clinic-tenant scope for the
      control plane, as B2 established. Close is scheduled, not clinic-authenticated
      HTTP. No clinic table is written.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — close and
      activation are off the request hot path; control-plane or scheduler
      unavailability does not hard-lock clinic workflows; the worst allowed operational
      mode remains read-only with existing data preserved (A15; constitution V; A11).

*Re-checked after Phase 1 design: all boxes remain ticked. No Complexity Tracking row.*

## Project Structure

### Documentation (this feature)

```text
specs/059-billing-period-close/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify (authoritative; no ## Clarifications)
├── data-model.md        # D1 entity this slice defines (`invoice`)
├── contracts/
│   ├── invoice.md                 # Invoice table (Freezes entity)
│   ├── period-close.md            # Scheduled close job (Freezes close)
│   ├── price-list-activation.md   # Operator activation mutation (Freezes price list)
│   └── invoice-evidence.md        # Rollup lines + request-reference trace (Freezes evidence)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`research.md` is **never** produced on this platform — the research is
`docs/architecture/ai-platform/01-ai-platform.md`.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — G4 row of the delivery plan (§3.13) and §7.3 / §4.5 /
  §12.3 / A15; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — additive `invoice` migration; scheduled period-close
  job outside `src/rollup/`; operator `credit_price` activation on G1's control plane;
  evidence as `usage_rollup` lines traced through `usage_event` to `ai_request`; no
  payment-provider integration; `src/pricing/` unused for totals.
- **§3 Files to review** — only this slice's migration, `src/period-close/`,
  `src/control/credit-price.ts`, Worker cron wiring, this slice's workers test files,
  and the schema snapshot.
- **§4 Prerequisites** — Node/workers pool; `OPERATOR_*` bindings when exercising
  `SELF.fetch` control e2e (same as B2/G1).
- **§5 Run the automated suite** — slice-only:
  `npx vitest run --config vitest.workers.config.ts test/period-close.test.ts`
  and
  `npx vitest run --config vitest.workers.config.ts test/price-list-activation.test.ts`;
  no full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open migration + `period-close/index.ts` + `credit-price.ts`;
  grep `invoice` / `credit_price_activate` / cron `0 5 1 * *`; confirm `src/rollup/` and
  `src/pricing/` not used for close totals.
- No **§7 Manual validation** — CI is the only verification path beyond the suite
  (close, activation, evidence, and spies are fully named in the fifteen tests).

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   ├── 20260731120000_platform_schema.sql                 # A5 — UNCHANGED (consumed)
│   ├── 20260911120000_plan_catalogue.sql                  # G1 — UNCHANGED (consumed credit_price)
│   ├── 20260911180000_usage_rollup_quota_weight.sql       # G3 column — UNCHANGED (read quota_weight)
│   └── 20260911200000_invoice.sql                         # NEW — CREATE TABLE invoice
├── schema.snap.sql                                        # MODIFIED — include invoice
├── wrangler.toml                                          # MODIFIED — add cron "0 5 1 * *"
├── src/
│   ├── period-close/
│   │   └── index.ts                                       # NEW — runPeriodClose (not src/rollup/)
│   ├── rollup/
│   │   └── index.ts                                       # UNCHANGED (Consumes F3)
│   ├── pricing/
│   │   └── index.ts                                       # UNCHANGED (must not price invoices)
│   ├── control/
│   │   ├── credit-price.ts                                # NEW — handleCreditPriceActivate
│   │   ├── types.ts                                       # MODIFIED — CreditPriceActivatePayload
│   │   ├── index.ts                                       # MODIFIED — isControlRoute + dispatch
│   │   ├── auth.ts                                        # UNCHANGED (Consumes G1/B2)
│   │   ├── http.ts                                        # UNCHANGED (Consumes G1/B2)
│   │   ├── audit.ts                                       # UNCHANGED (Consumes G1/B2)
│   │   └── plan.ts                                        # UNCHANGED (Consumes G1)
│   └── worker.ts                                          # MODIFIED — scheduled branch for close cron
├── vitest.workers.config.ts                               # MODIFIED — include this slice's tests
├── vitest.config.ts                                       # MODIFIED — exclude those from Node pool
└── test/
    ├── period-close.test.ts                               # NEW — eight scheduled-job named tests
    ├── price-list-activation.test.ts                      # NEW — seven integration named tests
    ├── system/harness.ts                                  # MODIFIED — DELETE FROM invoice in wipe
    ├── rollup-reconciliation.test.ts                      # UNCHANGED (Consumes F3)
    └── plan-catalogue.test.ts                             # UNCHANGED (Consumes G1)
```

**Structure Decision**: Period close lands as a **new** module `ai-platform/src/period-close/`
— outside F3 `src/rollup/`, matching Delivery Plan §3.13 ("the close is a new scheduled job,
not a rollup change"). Price-list activation lands as a sibling under `ai-platform/src/control/`
(`credit-price.ts`), wired only through the existing G1/B2 barrel `dispatchControlRequest` /
`isControlRoute` (same pattern as `plan.ts` / `token-contract.ts`). The Worker `scheduled`
handler gains one cron branch; F3's `0 3 * * *` / `0 4 * * *` branches stay. `src/pricing/`
is not imported by either new module.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How G4 binds to it |
| --- | --- | --- |
| **G1 — Plan catalogue and credit-denominated entitlement** (`credit_price` table created empty of activation behaviour; operator-authenticated Entitlement management and `control_audit` journaling; entitlement status `pending` / `active` / `suspended`; monthly credit budget column; G1 config-cache kinds) | `ai-platform/migrations/20260911120000_plan_catalogue.sql` (`CREATE TABLE credit_price`); `ai-platform/src/control/` — `auth.ts` (`createSecretOperatorAuth`), `http.ts` (`requireOperator`, `reject`, `ok`, `parseJsonBody`), `audit.ts` (`writeAudit`), barrel `index.ts` (`dispatchControlRequest` / `isControlRoute`), `plan.ts` / `entitle.ts` (unchanged). Entitlement `status` column (`pending` / `active` / `suspended`). Frozen artifacts: `specs/056-plan-catalogue/contracts/credit-price.md`, `specs/056-plan-catalogue/contracts/plan-catalogue.md`; B2 `specs/022-control-plane-enrollment/contracts/control-plane.md`. | G4 **INSERTs** `credit_price` rows via a new `handleCreditPriceActivate` on the same operator surface. It does **not** rewrite the table shape, plan CRUD, assign-plan, override, enroll, or G1 config-cache kinds (`"plans"` / `"entitlements"`). `credit_price` stays uncached. Non-operator rejection stays B2 `401 unauthorized`. `control_audit.action` vocabulary is **extended** (not rewritten) with `credit_price_activate`. Close **reads** `entitlement.status = 'active'`; it does not rewrite entitlement rows or the credit-budget column. |
| **F3 — Support lookup, retention, usage rollups, and journal dashboards** (scheduled `usage_rollup` production in `src/rollup/`; per installation/period rows with dimensions, counts, quota weight, tokens, cost; idempotent re-run) | `ai-platform/src/rollup/index.ts` (`runRollup` / `runRollupAndReconciliation`); Worker `scheduled` cron `"0 4 * * *"`; A5 `usage_rollup` / `usage_event` / `ai_request` tables. Physical dimensions JSON `{ installation_id, period }` (F3 freeze). `usage_rollup.quota_weight` already present (`migrations/20260911180000_usage_rollup_quota_weight.sql`; `SUM(usage_event.quota_weight)` in rollup UPSERT). Frozen artifact: `specs/041-support-retention-rollups/contracts/usage-rollup-reconciliation.md`. | G4 **reads** `usage_rollup` as frozen invoice evidence and **reads** `usage_event.request_id` → `ai_request.request_reference` for line tracing. Credits consumed = `SUM(quota_weight)` for that installation and period. It does **not** change rollup production, reconciliation, retention, support lookup, F3 cadence, or dimensions. Close MUST NOT call `runRollup` and MUST NOT UPDATE/DELETE `usage_rollup` rows. F3 contract files are not edited. |

No consumed entry lacks an implementation. No consumed **contract** is rewritten (delivery plan §2.3). Stop condition 2 is not triggered.

G3's usage-summary gauge is **not** a Consumes entry (spec Out of Scope / FR-022). G4 reads the already-present `quota_weight` column as F3 rollup evidence; it does not pull gauge work.

## Components Touched

**One** §4 component:

| §4 component | What G4 changes | Behaviour added? |
| --- | --- | --- |
| §4.5 Control plane | Realises **Billing**: scheduled period close and invoice generation from the usage ledger and the versioned credit price list; payment collection remains external. Realises price-list activation as an audited operator Entitlement-management-adjacent mutation on the existing `/control` surface (price list lives in the control plane; A15). Does not rewrite Installation lifecycle, plan CRUD, assign-plan, F3 support lookup / retention / rollup jobs, or G3 usage-summary. | Yes — operators can activate `credit_price` versions; the Worker cron closes a calendar month and writes immutable `invoice` rows. |

No other §4 component is touched (config cache, Quota DO, Flutter, journal writer, providers, `src/pricing/`, F3 `src/rollup/` unchanged). Stop condition 5 (multi-component without reason) is not triggered — only §4.5. Task count stays ~20–24.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `specs/059-billing-period-close/contracts/invoice.md` | Created | Freezes (`invoice` entity); FR-009, FR-011, FR-020 |
| `specs/059-billing-period-close/contracts/period-close.md` | Created | Freezes (scheduled close); FR-006–FR-012, FR-023–FR-025 |
| `specs/059-billing-period-close/contracts/price-list-activation.md` | Created | Freezes (price-list activation); FR-001, FR-003, FR-004, FR-013, FR-014, FR-025 |
| `specs/059-billing-period-close/contracts/invoice-evidence.md` | Created | Freezes (invoice evidence); FR-010, FR-015, FR-016, FR-019 |
| `specs/059-billing-period-close/data-model.md` | Created | FR-009, FR-020 — `invoice` entity |
| `ai-platform/migrations/20260911200000_invoice.sql` | Created | FR-020 — `CREATE TABLE invoice` |
| `ai-platform/schema.snap.sql` | Modified | FR-020 — snapshot includes `invoice` |
| `ai-platform/src/period-close/index.ts` | Created | FR-006–FR-012, FR-017, FR-018, FR-023–FR-025 — `runPeriodClose`; no `src/rollup/` / `src/pricing/` import |
| `ai-platform/src/control/credit-price.ts` | Created | FR-001, FR-003, FR-004, FR-013, FR-014 — operator activation; `control_audit`; B2 reject |
| `ai-platform/src/control/types.ts` | Modified | FR-013 — `CreditPriceActivatePayload` only |
| `ai-platform/src/control/index.ts` | Modified | FR-001, FR-004 — extend `isControlRoute` / `dispatchControlRequest` for activation; do not alter G1 plan/entitle routes |
| `ai-platform/src/worker.ts` | Modified | FR-006, FR-021 — `scheduled` branch for `"0 5 1 * *"` calling `runPeriodClose`; F3 cron branches unchanged |
| `ai-platform/wrangler.toml` | Modified | FR-006 — add `"0 5 1 * *"` to `[triggers] crons` |
| `ai-platform/test/period-close.test.ts` | Created | SC-001, SC-002, SC-006 — eight scheduled-job named tests |
| `ai-platform/test/price-list-activation.test.ts` | Created | SC-003–SC-005 — seven integration named tests (activation, evidence, spies) |
| `ai-platform/vitest.workers.config.ts` | Modified | SC-001–SC-006 — include the two new test files |
| `ai-platform/vitest.config.ts` | Modified | SC-001–SC-006 — exclude those workers files from the Node pool |
| `ai-platform/test/system/harness.ts` | Modified | FR-020 — `DELETE FROM invoice` in the shared wipe (same as G1 `credit_price`) |
| `specs/059-billing-period-close/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above |

Every file traces to an `FR-###` (or Freezes / deferred Documentation). No Consumes module is rewritten. Untraced files are out of scope.

## Test Layout

The spec's `### Test plan` names fifteen tests (delivery plan §3.12.10 G4 *Scheduled job + integration*). Mapped to §13.5 **Pipeline tests** (Worker scheduled entrypoints and `/control` handlers against Miniflare D1; spy on call counts). Every named test is placeable. Stop condition 3 is not triggered.

**Fixture construction** (implementation choice, not a requirement): `beforeAll` applies A5 + G1 + `usage_rollup.quota_weight` + this slice's `invoice` migration (same `?raw` pattern as `rollup-reconciliation.test.ts` / `usage-summary.test.ts`). Seed `installation`, `entitlement` with `status = 'active'`, `usage_rollup` rows whose `dimensions` JSON is `{ installation_id, period }` and whose `quota_weight` is the consumed-credits figure (tokens/cost set to values that would disagree if `src/pricing/` were used). Seed `credit_price` rows with ISO-8601 `active_from`. Evidence cases also seed `usage_event.request_id` and `ai_request.request_reference`. Close cases call `runPeriodClose({ db, period: "2026-08" })`. Activation cases `SELF.fetch` `POST /control/credit-price/activate` with operator bearer (G1 `plan-catalogue.test.ts` pattern).

**Spy construction** (implementation choice, not a requirement): no payment-provider port is added. `no_payment_provider_call` wraps `globalThis.fetch` and asserts zero calls whose URL looks like a payment provider, after both close and activation. `invoice_prices_through_credit_price_not_token_rate_artifact` uses `vi.spyOn` on `priceUsage`, `ledgerUsageFromProvider`, and `ratesForModel` from `ai-platform/src/pricing/index.ts` and asserts zero calls; `invoice.total` equals `credits_consumed * price_per_credit`. `close_freezes_usage_rollup_without_rewriting_rows` snapshots `usage_rollup` before/after close (deep-equal) and asserts `runRollup` is not invoked.

| Spec Test plan name | File | Spec layer | Asserts (FR / SC) |
| --- | --- | --- | --- |
| `close_one_invoice_per_active_installation` | `ai-platform/test/period-close.test.ts` | Scheduled job | FR-007–FR-009 / SC-001 — one immutable `invoice` for the `active` installation, priced through the version active for that period |
| `close_one_invoice_each_of_two_active_installations` | `ai-platform/test/period-close.test.ts` | Scheduled job | FR-007 / SC-001 — two `active` installations → two invoices; none that combine installations |
| `close_rerun_idempotent` | `ai-platform/test/period-close.test.ts` | Scheduled job | FR-011 / SC-002 — second close inserts no row and does not mutate credits consumed, version, total, status, or `issued_at` |
| `close_zero_consumption_no_invoice` | `ai-platform/test/period-close.test.ts` | Scheduled job | FR-012 / SC-002 — `quota_weight` sum 0 → no invoice |
| `close_freezes_usage_rollup_without_rewriting_rows` | `ai-platform/test/period-close.test.ts` | Scheduled job | FR-006 / SC-006 — rollup rows unchanged; F3 production job not called |
| `close_prices_through_latest_version_active_at_period_start` | `ai-platform/test/period-close.test.ts` | Scheduled job | FR-008, FR-023 / SC-001 — several versions with `active_from` ≤ period start → invoice carries the latest such version |
| `mid_period_activation_does_not_apply_to_current_period` | `ai-platform/test/period-close.test.ts` | Scheduled job | FR-023, FR-025 / SC-001 — `active_from` inside the unclosed period does not price that period |
| `close_no_applicable_price_list_no_invoice` | `ai-platform/test/period-close.test.ts` | Scheduled job | FR-024 / SC-002 — no row with `active_from` ≤ period start → no invoice; no default price/currency |
| `price_list_activation_audited` | `ai-platform/test/price-list-activation.test.ts` | Integration | FR-003, FR-013 / SC-003 — writes `credit_price` (`version`, price per credit, currency, `active_from`, `activated_by`) and `control_audit` with operator identity |
| `price_list_activation_non_operator_rejected` | `ai-platform/test/price-list-activation.test.ts` | Integration | FR-004 / SC-003 — B2 `401 unauthorized`; no `credit_price` or `control_audit` write |
| `price_list_activation_never_reprices_closed_period` | `ai-platform/test/price-list-activation.test.ts` | Integration | FR-014 / SC-003 — after close priced through *V*, a new version leaves that invoice's version and total unchanged |
| `invoice_resolves_to_usage_rollup` | `ai-platform/test/price-list-activation.test.ts` | Integration | FR-015 / SC-004 — invoice resolves to that installation and period's `usage_rollup` rows |
| `invoice_line_traces_to_request_references` | `ai-platform/test/price-list-activation.test.ts` | Integration | FR-016 / SC-004 — a `usage_rollup` line traces through `usage_event.request_id` to `ai_request.request_reference` |
| `no_payment_provider_call` | `ai-platform/test/price-list-activation.test.ts` | Integration (spy) | FR-019 / SC-005 — close and activation make no payment-provider call |
| `invoice_prices_through_credit_price_not_token_rate_artifact` | `ai-platform/test/price-list-activation.test.ts` | Integration (spy) | FR-010, FR-017 / SC-005 — `src/pricing/` spies unused; total from `credit_price` |

Every named test from the spec is placeable in §13.5. No named test is orphaned. This slice emits no new diagnostic code; inherited §6.4 prohibitions are out of scope and are not implemented (spec Coverage).

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this slice:

1. **Tests first (or alongside)** — add the failing `period-close.test.ts` scheduled-job cases and `price-list-activation.test.ts` integration/spy cases against a missing `invoice` table / missing handlers (never after implementation). Register both files in the workers pool.
2. **Migration** — `20260911200000_invoice.sql` + update `schema.snap.sql`; add `invoice` to the system-harness wipe (FR-020).
3. **Period close job** — `src/period-close/index.ts` `runPeriodClose`: select `active` entitlements, sum `usage_rollup.quota_weight` for the period, resolve latest `credit_price` with `active_from` ≤ period start, INSERT immutable `invoice` or skip (zero consumption / no applicable price); `ON CONFLICT DO NOTHING`; do not UPDATE rollup (FR-006–FR-012, FR-023–FR-025).
4. **Wrangler cron + Worker scheduled wiring** — append `"0 5 1 * *"`; `scheduled` maps that cron + `scheduledTime` to the previous UTC `YYYY-MM` and calls `runPeriodClose`. Leave F3 `0 3` / `0 4` branches untouched (FR-006, FR-021).
5. **Price-list activation** — `credit-price.ts` + `CreditPriceActivatePayload`; `POST /control/credit-price/activate`; `control_audit.action = credit_price_activate`; B2 `requireOperator` (FR-001, FR-003, FR-004, FR-013, FR-014).
6. **Turn tests green** — including latest-version / mid-period / no-price / idempotent / two-installation close cases; evidence joins; both spies (FR-017, FR-019).
7. **Verification** — slice-only vitest commands above; confirm `src/rollup/index.ts`, G1 `plan.ts` / `entitle.ts`, and `src/pricing/index.ts` untouched; confirm no invoice HTTP read surface (V4) and no payment-provider module.
8. **Documentation** — write `quickstart.md` per sections above.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
