# Implementation Plan: Catalogue price/display/`grace_days`, `credit_price` withdrawal, plan-delete fix (M1)

**Branch**: `ai/061-m1-catalogue-grace-days` | **Date**: 2026-09-23 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/061-catalogue-grace-days/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

M1 executes AP-ARCH A17 items 1–2 (and A15 item 4 as updated by A17) inside the Cloudflare AI Gateway Worker: a forward-only D1 migration adds subscription price, display copy, and `grace_days INTEGER NOT NULL DEFAULT 7` to `plan` and drops `credit_price`; control-plane plan CRUD round-trips the new fields with `control_audit`; `credit_price` activate code is deleted; and `POST /control/plans/{name}/delete` actually deletes the catalogue row. It is Band M's first slice (`Needs: G1`); M2 / P2 / later commercial bands read the columns it lands.

## Technical Context

**Language/Version**: TypeScript 5.9 (`ai-platform/package.json`) targeting the Cloudflare Worker; D1 SQLite via forward-only Wrangler migrations. Node `>=22` for the Vitest / Wrangler harness.

**Primary Dependencies**: G1 plan catalogue and control-plane plan CRUD (`ai-platform/src/control/plan.ts`, `types.ts` `PlanPayload`, barrel `index.ts`, migration `20260911120000_plan_catalogue.sql`, workers suite `test/plan-catalogue.test.ts`, A5 migrations harness `test/migrations.test.ts` + `schema.snap.sql`). B2 operator auth / `requireOperator` / `control_audit` batch pattern (unchanged). Live `credit_price` path to withdraw: `src/control/credit-price.ts`, `CreditPriceActivatePayload`, route in `index.ts`. G4-era `src/period-close/index.ts` still SELECTs `credit_price` and must lose that reference under FR-005 (temporary no-price / no-invoice until M2 — spec Assumptions). No new npm packages; no Supabase; no Flutter; no ABO Worker change.

**Storage**: Platform D1 only. One forward-only migration after `20260911200000_invoice.sql` alters `plan` with the five A17 columns and `DROP TABLE credit_price`. Schema snapshot updated. No down migration. No FK from `entitlement.plan` / `invoice.plan` to `plan.name` (delete remains a catalogue operation). Config-cache kind `"plans"` stays; `SELECT *` already returns new columns — no cache kind rewrite.

**Testing**: SQL / migration + integration (Delivery Plan §3.12.1 M1). Empty-DB and over-existing-catalogue migration applies, plus schema snapshot pin, in `ai-platform/test/migrations.test.ts` (A5/G1 harness). Workers integration (`npx vitest run --config vitest.workers.config.ts`) for credit-price grep/404, plan CRUD round-trip / validation / non-operator, and delete bug-fix — extending `test/plan-catalogue.test.ts` (same Miniflare + operator-auth pattern as G1). G4-era `test/price-list-activation.test.ts` and `test/period-close.test.ts` adjusted so they no longer require the withdrawn table/endpoint (do not implement M2 purchase-proof pricing). G1-era asserts that pin the withdrawn artefacts are adjusted as withdrawal / delete-fix fallout: `test/migrations.test.ts` drops `credit_price` from `G1_CATALOGUE_TABLES` and retires the `CREATE TABLE credit_price` snapshot-presence expectation; `test/plan-catalogue.test.ts` applies the M1 migration in `beforeAll`, extends `DEFAULT_PLAN_PAYLOAD` with valid A17 fields (FR-011), and updates `plan_delete_audit` to assert row removal (FR-013). Frozen G1 contract files stay untouched (§2.3). Suite joins CI permanently (§3.11). Band §3.2.1 matrix is `/abo-verify`, not this plan.

**Target Platform**: `ai-platform/` Cloudflare Worker (D1 + `/control`). No `ai-billing-orchestrator/`, `frontend/`, or `backend/`. Gateway remains additive, non-primary (AP-ARCH §14; constitution Operating Constraints).

**Project Type**: Band M A17 economics slice, Worker-only. Not a new deployable. Catalogue price columns are control-plane / D1 configuration only — not on the request path (A17; A6 preserved).

**Performance Goals**: Operator-rare control mutations (no guard latency budget). No second Quota DO round trip, no second D1 insert on the guard path, no second R2 object per request (§6.1, §7.5, §13.6). Request path never sees a price. Config cache warm/cold budgets for `"plans"` unchanged.

**Constraints**:
- Spec is authoritative; do not add files, endpoints, or behaviour the spec does not name.
- Do not rewrite G1 frozen contracts (`specs/056-plan-catalogue/contracts/*`) or G1 economics columns — extend plan CRUD payloads and DDL only (Consumes G1; delivery plan §2.3). A17-authorized withdrawal of `credit_price` is the sole exception to "do not change Consumes." G1-era test asserts that pin the withdrawn `credit_price` or the audit-only delete are adjusted as part of that withdrawal and the delete fix (FR-002, FR-003, FR-011, FR-013) — test-suite fallout, not a frozen-contract rewrite.
- Do not implement `GET /v1/plans`, period-close repricing, `purchase_proof` DDL, or invoice reshape (FR-017; M2 / P2).
- Plan delete removes the `plan` row and writes `plan_delete` audit (fixes G-era audit-only delete). Unknown plan → `404` `plan_not_found`; no audit.
- Invalid A17 payloads → `400` `invalid_payload`; no row; no audit. Omitted `grace_days` on create → schema default `7`; explicit `0` stored as `0`.
- Unauthenticated plan create/update/delete → `401` `{"error":"unauthorized"}`; no writes.
- No shared bearer introduced; operator auth remains G1/B2 until Band N (spec Assumptions).
- No plan/price table in the ABO; no clinic Postgres write; no money on the request path (Delivery Plan §5.3 / §8.1).

**Scale/Scope**: One §4 component (§4.5 Control plane — see Components Touched). Roughly: one forward-only migration + snapshot; plan CRUD / types / dispatch extensions; credit-price module deletion; period-close strip of `credit_price` reads; floor tests in migrations + plan-catalogue suites; G4 test fallout adjustments. Seventeen FRs. Three §3.12 floor groups. Roughly 16–20 tasks — under the ~25-task ceiling (delivery plan §5 / AP §6.3 stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — a
      handful of plan rows with subscription price and grace (A17); no marketplace,
      self-service enrollment, or payment-provider integration (constitution I; spec
      Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — additive D1 columns, one DROP,
      and `/control` mutations on the existing Worker; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated —
      M1 touches only `ai-platform/` (D1 migration, control-plane plan CRUD, credit-price
      withdrawal). It does not touch `backend/`, `frontend/`, or
      `ai-billing-orchestrator/`. **§14 acknowledgement:** the Worker is an additive,
      non-primary component with no domain logic, no clinic business data, and no write
      path into Supabase. Extended `plan` columns are platform D1 configuration, not
      clinic business data (A15/A17 constitution check; Operating Constraints).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — clinic Supabase
      integrity is untouched. Platform D1 integrity is held by NOT NULL / DEFAULT on the
      new columns, forward-only migration discipline, and `control_audit` with operator
      identity on every catalogue mutation (G1/B2 pattern).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — control mutations use operator identity
      (B2 `OperatorAuth`); audited via `control_audit`. Catalogue **delete** hard-deletes
      the `plan` row (Delivery Plan §3.2 Code sync / M1 Done when — retirement-by-status
      remains the policy for live entitlements; delete is a catalogue operation). No
      clinic table is written. Operator scope remains correctly above clinic-tenant
      scope for the control plane.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — plan CRUD
      is operator-invoked, not on the request hot path; AI request-path availability is
      unaffected; public catalogue read remains P2 (spec Failure Handling).

*Re-checked after Phase 1 design: all boxes remain ticked. No Complexity Tracking row.*

## Project Structure

### Documentation (this feature)

```text
specs/061-catalogue-grace-days/
├── plan.md              # This file
├── spec.md              # /abo-specify + /abo-clarify (authoritative)
├── data-model.md        # A17 `plan` columns; `credit_price` withdrawal; delete semantics
└── quickstart.md        # Slice-only review surface (abo-quickstart-template)
```

`research.md` is **never** produced — the research is the ABO architecture corpus and AP-ARCH A17.

`contracts/` is **not** produced: Freezes' cross-deployable HTTP wire (`GET /v1/plans`, ABO §5.10)
is owned by P2 (FR-017). M1 freezes D1 column shape and same-deployable control CRUD extensions;
column binding for later slices is [`data-model.md`](./data-model.md). G1
`specs/056-plan-catalogue/contracts/plan-catalogue.md` and `credit-price.md` are **not** rewritten
(§2.3); A17 withdraws the `credit_price` artifact in code/schema.

`quickstart.md` (per `.specify/templates/abo-quickstart-template.md`) contains:
- **§1 Architecture context** — Delivery Plan §3.2 row M1; Implements A17 items 1–2, A15
  item 4; ABO §4.1.6 / §4.2 / §5.10 (columns only); what the spec delivered; what the plan
  scoped.
- **§2 What was implemented** — A17 plan columns migration; `credit_price` drop + control
  withdrawal; plan CRUD carrying A17 fields; plan-delete fix; period-close stripped of
  `credit_price` reads (temporary until M2).
- **§3 Files to review** — only this slice's migration, plan/types/index/period-close
  changes, deleted credit-price module, this slice's test files, schema snapshot.
- **§4 Prerequisites** — Node/workers pool; `OPERATOR_*` bindings for `SELF.fetch` control
  e2e (same as G1/B2).
- **§5 Run the automated suite** — slice-only vitest commands from Test Layout; no full-suite
  `npm test`, no band e2e/x-e2e.
- **§6 Inspect the changes** — open migration + `plan.ts` delete batch; grep `credit_price`
  over `src/` (expect zero); confirm G1 economics columns untouched.
- No **§7 Manual validation** — CI / floor suite is the verification path.

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   ├── 20260911120000_plan_catalogue.sql          # G1 — UNCHANGED (consumed)
│   ├── 20260911200000_invoice.sql                 # prior — UNCHANGED
│   └── 20260923120000_catalogue_grace_days.sql    # NEW — ALTER plan A17 columns;
│                                                  #   DROP TABLE credit_price
├── schema.snap.sql                                # MODIFIED — A17 plan columns;
│                                                  #   credit_price absent
├── src/
│   ├── control/
│   │   ├── plan.ts                                # MODIFIED — A17 fields on create/update;
│   │   │                                          #   DELETE plan row in delete batch
│   │   ├── types.ts                               # MODIFIED — PlanPayload A17 fields;
│   │   │                                          #   remove CreditPriceActivatePayload
│   │   ├── index.ts                               # MODIFIED — unregister credit-price route
│   │   │                                          #   / export
│   │   ├── credit-price.ts                        # DELETED
│   │   ├── auth.ts / http.ts / audit.ts           # UNCHANGED (Consumes G1/B2)
│   │   └── entitle.ts / lifecycle.ts              # UNCHANGED (out of scope)
│   ├── period-close/
│   │   └── index.ts                               # MODIFIED — remove credit_price reads;
│   │                                              #   issue no invoices until M2
│   └── config-cache/index.ts                      # UNCHANGED — SELECT * already returns
│                                                  #   new columns
├── vitest.workers.config.ts                       # UNCHANGED unless new test file added
└── test/
    ├── migrations.test.ts                         # MODIFIED — M1 Migration floor
    ├── plan-catalogue.test.ts                     # MODIFIED — M1 Code + Bug fix floor
    ├── price-list-activation.test.ts              # MODIFIED — withdraw activate cases /
    │                                              #   assert 404; no credit_price writes
    └── period-close.test.ts                       # MODIFIED — no credit_price fixture;
                                                   #   no G-era priced invoices (M2 later)
```

**Structure Decision**: M1 extends G1's existing `plan.ts` / `PlanPayload` / plan-catalogue
workers suite rather than adding a parallel control module. Credit-price withdrawal deletes the
G1/G4 activate module and unregisters its route. Period-close loses `credit_price` SELECTs so
`ai-platform/src/` stays clean (FR-005); paid-amount pricing waits for M2. Config-cache kind
`"plans"` needs no code change. Enroll / entitle / assign-plan stay untouched.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How M1 binds to it |
| --- | --- | --- |
| **G1 — Plan catalogue and control-plane plan CRUD** (A15 item 4; `plan` entity; operator-authenticated plan CRUD; `control_audit` journaling; config-cache `"plans"`; forward-only additive D1 migration discipline). M1 adds A17 columns and extends plan CRUD payloads; it does not rewrite G1 economics columns or enroll/assign semantics. | `ai-platform/migrations/20260911120000_plan_catalogue.sql`; `ai-platform/schema.snap.sql`; `ai-platform/src/control/plan.ts` (`handlePlanCreate` / `Update` / `Delete`); `ai-platform/src/control/types.ts` (`PlanPayload`); `ai-platform/src/control/index.ts` (plan routes); `ai-platform/src/config-cache/index.ts` (kind `"plans"`); `ai-platform/test/migrations.test.ts`; `ai-platform/test/plan-catalogue.test.ts`. Frozen artifacts: `specs/056-plan-catalogue/contracts/plan-catalogue.md`, `specs/056-plan-catalogue/data-model.md`. Spec/plan: `specs/056-plan-catalogue/`. | M1 **appends** one forward-only migration and updates the snapshot. It **extends** `PlanPayload` validation and INSERT/UPDATE SQL with A17 fields; **fixes** `handlePlanDelete` to `DELETE FROM plan` in the same batch as `plan_delete` audit. It does **not** rewrite G1 economics column meanings, assign-plan / override, enroll, or cache TTL/miss/ownership. G1 contract files are not edited. |
| **A17-authorized withdrawal of G1's `credit_price`** (table, control activate path, payload type). M1 executes the withdrawal; it does not redefine period-close pricing (M2). | Live artifacts to remove/unbind: `ai-platform/src/control/credit-price.ts`; `CreditPriceActivatePayload` in `types.ts`; route/export in `index.ts`; D1 table from G1 migration (dropped by M1 migration); G4 `src/period-close/index.ts` `resolveCreditPrice` / invoice insert that reads `credit_price`. Frozen G1 artifact `specs/056-plan-catalogue/contracts/credit-price.md` is **not** rewritten — withdrawal is recorded in M1 `data-model.md` and code deletion. | M1 **drops** the table, **deletes** the control module/route/type, and **strips** period-close's `credit_price` reads so no `credit_price` / `CreditPriceActivatePayload` / `credit-price` reference remains in `ai-platform/src/` (FR-005). Period-close issues no invoices until M2 (spec Assumptions). |

No consumed entry lacks an implementation. No consumed **contract file** is rewritten (delivery plan §2.3). Stop condition 2 is not triggered.

## Components Touched

| §4 component | What M1 changes | Behaviour added? |
| --- | --- | --- |
| §4.5 Control plane | Extends Entitlement-management "maintain the plan catalogue" with A17 price/display/`grace_days` on create/update; withdraws credit-price activate; fixes plan delete to remove the row with `plan_delete` audit. Does not rewrite Installation lifecycle, assign-plan, override, or grant paths. | Yes — operators maintain subscription price, display copy, and grace on catalogue rows; `credit_price` activate is gone; delete removes the row. |

**Written reason (single §4 component):** Delivery Plan §3.2 row **M1** Canonical centres A17 catalogue columns + control CRUD / withdrawal + plan-delete fix on the existing control plane (A15 item 4 as updated by A17). Schema work is §7.3 / ABO §4.2 DDL, not a second §4 component. Config cache (§4.3.2) is unchanged. Stop condition 5 is satisfied; task count stays ~16–20.

No other §4 component is touched (Quota DO, Flutter, journal, providers, rate-limit, guard evaluation, `GET /v1/plans`).

## Files

| File | Created / Modified / Deleted | Traces to |
| --- | --- | --- |
| `ai-platform/migrations/20260923120000_catalogue_grace_days.sql` | Created | FR-001, FR-002, FR-004 — `ALTER TABLE plan ADD` `price_cents`, `currency`, `display_name`, `description`, `grace_days INTEGER NOT NULL DEFAULT 7`; `DROP TABLE credit_price`; forward-only. Non-grace A17 columns use SQLite-required backfill defaults on ALTER so the migration applies over an existing catalogue (FR-004); create/update validation still rejects empty/invalid values (FR-011). |
| `ai-platform/schema.snap.sql` | Modified | FR-003 — pin A17 `plan` columns including `grace_days … DEFAULT 7`; `credit_price` absent. |
| `ai-platform/src/control/plan.ts` | Modified | FR-009–FR-016 — accept/persist A17 fields; validate `400 invalid_payload`; omit `grace_days` → default 7; explicit `0` stored; update-only A17 leaves G1 economics unchanged; delete removes row + `plan_delete` audit; unknown → `404 plan_not_found`; non-operator → `401`. |
| `ai-platform/src/control/types.ts` | Modified | FR-005, FR-009 — extend `PlanPayload` with A17 fields; remove `CreditPriceActivatePayload`. |
| `ai-platform/src/control/index.ts` | Modified | FR-005, FR-006 — remove credit-price route registration and export. |
| `ai-platform/src/control/credit-price.ts` | Deleted | FR-005, FR-006 — module gone; activate → 404. |
| `ai-platform/src/period-close/index.ts` | Modified | FR-005 — remove `credit_price` references; issue no invoices until M2 (spec Assumptions; FR-017). |
| `ai-platform/test/migrations.test.ts` | Modified | FR-003, FR-004 / SC-001 — M1 Migration floor (empty DB + over existing catalogue; snapshot pin). |
| `ai-platform/test/plan-catalogue.test.ts` | Modified | FR-005–FR-016 / SC-002–SC-005 — M1 Code + Bug fix floor. |
| `ai-platform/test/price-list-activation.test.ts` | Modified | FR-005, FR-006 — withdraw activate happy-path writes; assert route 404 / no `credit_price` table dependency. |
| `ai-platform/test/period-close.test.ts` | Modified | FR-005, FR-017 — remove `credit_price` fixtures; do not assert G-era credits×price invoices (M2 owns repricing). |
| `specs/061-catalogue-grace-days/data-model.md` | Created (this phase) | FR-001, FR-002, FR-007, FR-008, FR-013 — entity binding for later slices. |
| `specs/061-catalogue-grace-days/quickstart.md` | Created (this phase) | — template-mandated review surface; sections named above. |

Every code file traces to an `FR-###`. No file is created for an unstated requirement. Consumed G1 assign/enroll handlers and A5 cache mechanics stay unchanged aside from the listed extensions. `GET /v1/plans` is not added (FR-017).

## Test Layout

The spec's `### Test plan` names three §3.12.1 floor groups (Delivery Plan §3.12.1 M1; layer SQL / migration + integration). Place them as follows. **Only these floor cases** belong in this plan — not §3.2.1 M1-V* / M-E* / M-X*.

| Spec Test plan name | File | Layer | Asserts (FR / SC) |
| --- | --- | --- | --- |
| M1 — Migration | `ai-platform/test/migrations.test.ts` | SQL / migration + integration | FR-001–FR-004 / SC-001 — applies cleanly to an empty database and over the existing pre-A17 catalogue (seeded `plan` + existing `credit_price`); snapshot pinned including `grace_days DEFAULT 7`; `credit_price` absent from the snapshot; no down migration. |
| M1 — Code | `ai-platform/test/plan-catalogue.test.ts` (grep + route + CRUD cases); credit-price 404 may live here or as a focused case in the adjusted `price-list-activation.test.ts` | SQL / migration + integration | FR-005–FR-012, FR-016 / SC-002, SC-003, SC-005 — no `credit_price` / `CreditPriceActivatePayload` / `credit-price` in `src/` (grep); activate → 404; plan CRUD round-trips A17 fields with `control_audit`; omit `grace_days` → 7; explicit `0` stored; invalid payloads → `400 invalid_payload` with no writes; update-only A17 leaves G1 economics unchanged; non-operator → `401` with no writes. |
| M1 — Bug fix | `ai-platform/test/plan-catalogue.test.ts` | SQL / migration + integration | FR-013–FR-015 / SC-004 — delete removes the `plan` row and writes `plan_delete` audit; unknown plan → `404 plan_not_found` with no audit; delete succeeds while `entitlement.plan` / `invoice.plan` still reference the name (referencing rows untouched). |

Every named floor group from the spec is placeable. No named floor test is orphaned.

## Band verification

Expanded matrix: Delivery Plan §3.2.1 (M1-V1…M1-V14 and Band M e2e/x-e2e rows that exercise M1). Implemented only via `/abo-verify` after Band M slices land — **not** as extra Spec Kit user stories, Files entries, or tasks in this plan.

## Sequencing

1. **Tests first (or alongside)** — add failing M1 Migration asserts in `migrations.test.ts` and failing Code / Bug fix cases in `plan-catalogue.test.ts` (and adjust G4 suites that would otherwise require `credit_price`) against missing columns / still-live credit-price / audit-only delete.
2. **Migration** — `20260923120000_catalogue_grace_days.sql` + update `schema.snap.sql`; turn Migration floor green (FR-001–FR-004).
3. **Credit-price withdrawal** — delete `credit-price.ts`; remove type, route, export; strip `period-close` `credit_price` reads (no invoices until M2); turn grep + activate-404 green (FR-005, FR-006).
4. **Plan CRUD A17 fields** — extend `PlanPayload` + validators + INSERT/UPDATE; omit/`0`/`invalid_payload` / economics-unchanged cases (FR-009–FR-012, FR-016).
5. **Plan delete fix** — `DELETE FROM plan` in the same batch as `plan_delete` audit; unknown 404; referenced-name delete (FR-013–FR-015).
6. **Turn integration floor green** — including non-operator via B2 `requireOperator`.
7. **G1 suite fallout** — `migrations.test.ts`: drop `credit_price` from `G1_CATALOGUE_TABLES` and retire the snapshot-presence expectation (FR-002, FR-003). `plan-catalogue.test.ts`: apply the M1 migration in `beforeAll`; extend `DEFAULT_PLAN_PAYLOAD` with valid A17 fields (FR-011); update `plan_delete_audit` to assert row removal (FR-013).
8. **Verification** — slice-only vitest commands from Test Layout; confirm `grep` over `ai-platform/src/` is clean for `credit_price` / `CreditPriceActivatePayload` / `credit-price`; confirm G1 contract files / entitle / enroll / config-cache kind untouched; confirm no `GET /v1/plans`.
9. **Documentation** — write `quickstart.md` per sections above.

## Complexity Tracking

> No constitution violations requiring justification. Empty by design.
