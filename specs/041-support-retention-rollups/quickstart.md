# Quickstart: Support lookup, retention purges, usage rollups, and journal dashboards (F3)

F3 freezes operator support lookup (one indexed D1 query + one R2 `GetObject`), four-class
retention purges with per-capability diagnostic horizons and purge-by-installation-id, scheduled
`usage_rollup` production with reconciliation for missing attempt rows / missing usage credit, and
six named journal dashboards answered by D1 query alone — with no second metrics store.

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). Section **1** is always
**Architecture context**. When omitting Prerequisites or Manual validation, renumber the remaining
sections — do not leave gaps (e.g. 1, 2, 4, 5).

## 1. Architecture context

F3 implements the **F3** row in
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)
§3.7, covering architecture sections **§4.5** (control plane), **§8.9** (support lookup trace),
**§7.6** (support lookup I/O budget, rollups, dashboards), **§7.7** (four-class retention),
**§13.1** (named diagnostics, no second metrics store), **R-6** (reconciliation), and **A13**
(request reference as support handle).

- **What the spec delivered** ([`spec.md`](./spec.md)): operator-authenticated support lookup;
  four-class retention purge (diagnostic / journal / ledger / ephemeral via B4); scheduled
  `usage_rollup` + reconciliation report; six named journal dashboards; frozen `contracts/*`.
- **What the plan scoped** ([`plan.md`](./plan.md)): modules under `src/support/`, `src/retention/`,
  `src/rollup/`, `src/dashboards/`; control-plane routes and Worker `scheduled` handler; four
  integration test files covering T1–T20.

## 2. What was implemented

- **`supportLookup()`** (`src/support/index.ts`) — one indexed D1 JOIN + at most one R2 `GetObject`;
  per-capability diagnostic horizon; operator-facing trace reconstruction.
- **`runRetentionPurge()` / `purgeByInstallationId()`** (`src/retention/index.ts`) — four-class
  horizon purge (7d / 90d / 2555d diagnostic/journal/ledger; ephemeral via B4); installation purge
  with `control_audit`.
- **`runRollup()` / `runReconciliation()`** (`src/rollup/index.ts`) — `usage_event` → `usage_rollup`
  with idempotent upsert; reconciliation flags missing attempts and missing usage credit.
- **Six dashboard queries** (`src/dashboards/index.ts`) — TTFT, validation-failure rate, repair
  rate, fallback rate, cost per capability/installation, quota rejection rate; read-only SELECTs.
- **Control-plane routes** (`src/control/index.ts`) — `POST /control/support/lookup?reference=…`;
  `POST /control/installations/{id}/purge`.
- **Worker cron** (`src/worker.ts`, `wrangler.toml`) — `0 3 * * *` retention; `0 4 * * *`
  rollup/reconciliation.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/support/index.ts` | Operator support lookup (FR-001–FR-006, FR-019) |
| `ai-platform/src/retention/index.ts` | Four-class retention purge + installation purge (FR-007–FR-010, FR-018) |
| `ai-platform/src/rollup/index.ts` | `usage_rollup` job + reconciliation report (FR-011–FR-014) |
| `ai-platform/src/dashboards/index.ts` | Six named diagnostic queries (FR-015–FR-017) |
| `ai-platform/src/control/index.ts` | Support-lookup + installation-purge routes |
| `ai-platform/src/worker.ts` | Control dispatch + `scheduled` handler |
| `ai-platform/wrangler.toml` | Cron triggers for retention and rollup |
| `ai-platform/test/support-lookup.test.ts` | T1–T3 |
| `ai-platform/test/retention.test.ts` | T4–T9 |
| `ai-platform/test/rollup-reconciliation.test.ts` | T10–T13 |
| `ai-platform/test/journal-dashboards.test.ts` | T14–T20 |
| `specs/041-support-retention-rollups/contracts/*.md` | Frozen Freezes artifacts |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run --config vitest.workers.config.ts \
  test/support-lookup.test.ts \
  test/retention.test.ts \
  test/rollup-reconciliation.test.ts \
  test/journal-dashboards.test.ts
```

Expected: **20 passing tests** for this slice only (four test files above).

## 5. Inspect the changes

```bash
# Support lookup route and module
rg "support/lookup|supportLookup" ai-platform/src/

# Retention purge and cron
rg "runRetentionPurge|purgeByInstallationId" ai-platform/src/
rg "crons" ai-platform/wrangler.toml

# Rollup and reconciliation
rg "runRollup|runReconciliation" ai-platform/src/

# Dashboard queries (read-only)
rg "dashboardTtft|dashboardValidation|dashboardRepair|dashboardFallback|dashboardCost|dashboardQuota" ai-platform/src/dashboards/

# Frozen contracts
ls specs/041-support-retention-rollups/contracts/
```

## 6. Manual validation

Optional when Cloudflare bindings are available: authenticate as an operator, call
`POST /control/support/lookup?reference=XXXX-XXXX` against a seeded reference, and inspect Worker
cron logs for retention (`0 3 * * *`) and rollup (`0 4 * * *`) scheduled handlers.
