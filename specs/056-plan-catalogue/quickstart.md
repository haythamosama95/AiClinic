# Quickstart: Plan catalogue and credit-denominated entitlement (G1)

G1 adds the operator-maintained plan catalogue, the versioned `credit_price` table (created but not activated), and the entitlement monthly credit-budget column inside the Cloudflare AI Gateway Worker. Assignment reads the catalogue and copies plan economics onto a pending installation entitlement in one audited mutation; plans and entitlements are served through the A5 config cache.

**Scope rule:** This quickstart covers **only slice G1**. It lists G1 files, G1 tests, and G1 commands — not prior-slice regression suites, combined platform counts, or files from earlier slices.

## 1. Architecture context

- **Delivery plan row:** G1 in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.13 — *Plan catalogue and credit-denominated entitlement* (`Needs: A5, B2`). Done when forward-only migrations create `plan`, `credit_price`, and the entitlement credit-budget column; operator plan CRUD and plan-based assignment are audited control-plane mutations; assignment populates every economics field in one mutation; plans and entitlements are served through the config cache with the A5 warm/cold read pattern.
- **Architecture sections:** `§4.5` (control-plane Entitlement management — maintain catalogue, assign plan, set quota/budget, set period bounds and soft threshold), `§7.3` (D1 shapes for `plan`, `credit_price`, `entitlement`, `control_audit`), `§4.3.2` (config cache warm/cold read pattern), and **A15** (credit-denominated monthly quota, small plan catalogue, request path never sees a price).
- **Spec delivered:** Forward-only additive D1 migration; operator plan create/update/delete; plan-based entitlement assignment (`pending` → `active`) copying catalogue economics in one mutation; per-installation override journaled distinctly; config-cache kind `"plans"`; thirteen named tests (two SQL / migration, eleven Workers integration).
- **Plan scoped:** One migration + schema snapshot update; `plan.ts` CRUD module; extension of I4 `entitle.ts` (catalogue read on assign, `handleOverride`); `ConfigEntityKind` `"plans"` reader branch; `plan-catalogue.test.ts` — Consumes A5 config cache and B2 control-plane modules extended, not rewritten.

## 2. What was implemented

- **Additive migration** — `plan` and `credit_price` tables; `entitlement.credit_budget` and `entitlement.max_cost_class` columns with non-null defaults (pending enroll stays zeroed).
- **Operator plan CRUD** — `handlePlanCreate` / `handlePlanUpdate` / `handlePlanDelete` on `/control/plans/*`; every mutation journals `control_audit` with operator identity; non-operator rejected with B2 `401 unauthorized`.
- **Plan-based entitle assignment** — `handleEntitle` reads the catalogue row and copies monthly credit budget, request-count guard, `max_cost_class`, soft threshold, and capability set in one D1 batch with I4 grant writes; status → `active`.
- **Per-installation override** — `handleOverride` on `POST /control/installations/{id}/override` with distinct `control_audit.action = override`.
- **Config-cache kind `"plans"`** — forward-only `ConfigEntityKind` extension and `createD1ConfigReader` branch; entitlements including `credit_budget` continue through the existing `"entitlements"` kind. `credit_price` is not cached.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/migrations/20260911120000_plan_catalogue.sql` | Forward-only G1 migration: `plan`, `credit_price`, entitlement `credit_budget` / `max_cost_class` |
| `ai-platform/schema.snap.sql` | Post-migration schema snapshot including G1 tables and columns |
| `ai-platform/src/control/plan.ts` | Operator plan create, update, delete handlers |
| `ai-platform/src/control/entitle.ts` | Catalogue read on assign-plan; `handleOverride` |
| `ai-platform/src/config-cache/index.ts` | `ConfigEntityKind` `"plans"` and D1 reader branch |
| `ai-platform/test/plan-catalogue.test.ts` | Eleven named integration tests (CRUD, assignment, override, non-operator, four cache spies) |

## 4. Prerequisites

- **Workers pool:** Node.js `>=22` and `ai-platform` dependencies (`npm install` in `ai-platform/`).
- **Operator bindings:** When exercising control e2e via `SELF.fetch`, Miniflare must expose `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID` (same as B2 `control.test.ts`).

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/migrations.test.ts
```

Expected for this slice: **2 passing tests** — `migrations_apply_cleanly_empty_database`, `schema_snapshot_matches` (G1-named cases in the migrations harness).

```bash
npx vitest run --config vitest.workers.config.ts test/plan-catalogue.test.ts
```

Expected for this slice: **11 passing tests** — `plan_create_audit` through `config_cache_entitlement_warm_zero_io`.

**13 passing tests total** for G1 (do not cite prior-slice cases in `migrations.test.ts` or run `npm test` for the full platform suite).

## 6. Inspect the changes

1. Open `ai-platform/migrations/20260911120000_plan_catalogue.sql` — `plan`, `credit_price`, and entitlement column additions.
2. Open `ai-platform/src/control/plan.ts` — operator CRUD handlers and `control_audit` actions (`plan_create`, `plan_update`, `plan_delete`).
3. Open `ai-platform/src/control/entitle.ts` — catalogue `SELECT` and economics copy in `handleEntitle`; distinct `handleOverride` audit path.
4. Grep for `credit_budget` and `ConfigEntityKind` / `"plans"`:

```bash
cd ai-platform
rg 'credit_budget' src/control/entitle.ts src/config-cache/index.ts
rg '"plans"' src/config-cache/index.ts
```

5. Confirm Consumes modules are not rewritten — `lifecycle.ts` (enroll), B2 `auth.ts` / `http.ts` / `audit.ts`, and A5 `contracts/config-cache.md` remain unchanged aside from the listed extensions; `ai-platform/src/pricing/` is untouched.
