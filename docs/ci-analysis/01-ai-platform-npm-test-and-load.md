# Agent A — ai-platform/npm-test + ai-platform/load (run 38695681551, HEAD 953e5e6e)

## TL;DR

- **One root cause covers 76 of the 91 npm-test problems and the whole load campaign.** Commit `771ceed7` added
  `migrations/20261014120000_ai_request_idempotency_fingerprint.sql` (`ALTER TABLE ai_request ADD COLUMN request_fingerprint TEXT`)
  and made every admission `SELECT ... request_fingerprint` (`src/admission/index.ts:177-187`, called unconditionally at `:636`)
  and every journal INSERT write it (`src/journal/index.ts:244-251`). Seven workers-pool test files hand-pick migrations and
  never apply the new one.
- The 76 break down as: 66 direct `D1_ERROR: no such column: request_fingerprint at offset 126`, 4 cascades of that error
  (worker T16, worker cancel-usage, worker grace-degraded, cohort T-J3-05), and 10 NOT_RECORDED in load-and-cost.
  Offset 126 is the `request_fingerprint` token inside `selectAiRequestByKey`'s SELECT text.
- **Three independent, deterministic failures**, all caused by `771ceed7`:
  - `migrations.test.ts` ×2: `schema.snap.sql` was hand-edited to put the column mid-table, but SQLite's ADD COLUMN splices
    it in before the table-constraint comma.
  - `manifest.test.ts` T-A4-15: the new `hashCanonicalJson` export isn't in the manifest export allowlist.
- **8 system tests (excluded scope) are not schema-related.** Their harness applies all 24 migrations in order, and they fail
  on assertions (409, null envelope), not D1 errors.
- **Pre-`771ceed7` evidence:** the repo's older run `artifacts/katest-run-38534344174` (2026-10-14 08:20, before `771ceed7` at 16:19) shows
  worker-orchestrator 36/36, pipeline 19/19, conversational-journaling 10/10, cohort 11/11, manifest 59/59, migrations 36/36, load-and-cost 10/10 PASS.
- **Cross-impact (important):** `abo/test/system/cross-worker-harness.ts` has the same missing migration. All 4
  abo/cross-worker FAILs (E2E-P4.9-03, E2E-P4.9-05, E2E-P4.8-07, E2E-P4.4-01) log `no such column: request_fingerprint`
  (32 occurrences in that campaign's output.log).
- **Predicted next-layer failure after the schema fix:** `admission-credit.test.ts > admission_repeated_key_no_second_inference`.
  It encodes the pre-`771ceed7` contract (a journaled D1 row replays with **0** DO fetches). `771ceed7` deliberately removed
  that path, so the test will get `idempotency_conflict` after 1 DO fetch. This is product semantics, so it belongs to the
  idempotency owner.

No previous attempt to fix any of this was made and reverted: `git log --all -S ai_request_idempotency_fingerprint` and
`-S hashCanonicalJson` return only `771ceed7`. `e1a42092`, `cb99ded0` and `953e5e6e` touch none of these files.

---

## 1. Per-test classification (npm-test: 81 FAIL + 10 NOT_RECORDED; load: 10 NOT_RECORDED)

Note: the briefing says 11 NOT_RECORDED, but there are **10**: load-and-cost has exactly 10 `it(` blocks, and `summary.json`
`not_recorded` lists 10 in both campaigns.

Class (a) = `no such column: request_fingerprint` from the file's hand-rolled migration list; (a′) = cascade of (a) showing a different assertion; (b) = independent.

| Test file | # | Class | Decisive evidence | Predicted after fix |
|---|---|---|---|---|
| test/admission-credit.test.ts | 18 | (a) | every error `D1_ERROR: no such column: request_fingerprint at offset 126` (vitest-report.json) | 17 pass; **`admission_repeated_key_no_second_inference` will fail** (see §7) |
| test/conversational-journaling.test.ts | 9 | (a) | same | pass |
| test/pipeline.test.ts | 8 | (a) | same | pass (stage-8 duplicate-key goes through `runGuard`, so the fingerprint is computed and persisted) |
| test/soft-threshold-routing.test.ts | 10 | (a) | same | pass |
| test/worker-request-orchestrator.test.ts | 21 | (a) | same | pass (T15 does two real POSTs with an identical body, so the bindings match; medium confidence) |
| test/worker-request-orchestrator.test.ts — T16 `disconnect aborts…` | 1 | (a′) | `expected false to be true` at `:1560` = `expect(invokeEntered).toBe(true)`. Admission threw in `selectAiRequestByKey`, so the provider was never invoked | pass |
| test/worker-request-orchestrator.test.ts — `writes ai_attempt and usage_event when cancel has accrued usage` | 1 | (a′) | `:1672` = `expect(invokeEntered).toBe(true)`. Same cause | pass |
| test/worker-request-orchestrator.test.ts — `routes the degraded chain when grace admission journals routing_tier degraded` | 1 | (a′) | `expected 500 to be 200` at `:1889`. This test **mocks `runAdmission`** (`:1871`), so admission passes, but the stage-9 `createRequestRow` INSERT (`src/journal/index.ts:244`, writes `request_fingerprint`) throws → caught → `internal_error` → `fail(9, …)` (`src/pipeline/index.ts:599-606`) → HTTP 500 | pass |
| test/cohort-activate-promote.test.ts — T-J3-05 | 1 | (a′) | `expected false to be true` at `:761` = `expect(createResult.ok).toBe(true)`. `createRequestRow` INSERT fails on the missing column, error caught → `ok:false` | pass |
| test/load/load-and-cost.test.ts (npm-test) | 10 NR | (a) | suite-level `beforeAll` (`:111-127`) → `runLoadHappyPath` → `happy-path.ts:564` `runGuard` → `selectAiRequestByKey` throws → `Failed Suites 1`, all 10 tests "skipped", so the governor records NOT_RECORDED | pass |
| test/manifest.test.ts — T-A4-15 | 1 | (b) | `export hashCanonicalJson must be data, not executable wiring` (`:269`) | pass after allowlist edit |
| test/migrations.test.ts — T-A5-13 + `schema_snapshot_matches` | 2 | (b) | exact diff from output.log, shown below | pass after snapshot edit |
| test/system/* (E2E-P3.4-01, E2E-P3.4-11, SYS-5.5, SYS-5.6, SYS-7.1, SYS-7.3, SYS-7.4, SYS-8.1) | 8 | (b) excluded | assertion failures only (409/401/null envelope); **0** `no such column` in their vitest-report errors. The `request_fingerprint` line printed beside E2E-P3.4-01 in output.log is interleaved output from `worker-request-orchestrator.test.ts:1967` | other agent |

Totals: 66 (a) + 4 (a′) + 3 (b in scope) + 8 (b excluded) = 81 FAIL. Plus 10 NOT_RECORDED (a).

The only schema error in the whole npm-test output.log is `no such column: request_fingerprint` (1164 hits). There are no `no such table` and no `duplicate column` errors.

### Load campaign (exit 1, 0 passed, 10 NOT_RECORDED)

`load/output.log` (all 230 lines read):
- vitest runs `vitest.workers.config.ts` against `test/load/load-and-cost.test.ts` only (`npm run test:load`), 2.67 s.
- `FAIL test/load/load-and-cost.test.ts [ test/load/load-and-cost.test.ts ]`, `Error: D1_ERROR: no such column: request_fingerprint at offset 126`.
- Stack: `selectAiRequestByKey src/admission/index.ts:177` ← `runAdmission :636` ← `runGuard src/pipeline/index.ts:494` ← `test/load/happy-path.ts:564` ← `binding-spies.ts:101` ← `runWorker happy-path.ts:497`.
- `Tests 10 skipped (10)`, then `× load: runner stalled (no progress) 0ms` and `harness: runner exited with code 1 before reporting a result`, which `summary.json` marks as `campaign_infrastructure_error: true`.

This is **not** a crash, timeout, or governor bug. The governor correctly reports a suite-level hook failure as NOT_RECORDED.
It is the same missing migration. The file is also in `vitest.workers.config.ts` (line 30), so npm-test shows the identical 10 NOT_RECORDED, and **one edit fixes both campaigns.**

---

## 2. Inventory — every file under ai-platform/test that builds a D1 schema

All workers-pool files run with `fileParallelism:false` and per-file fresh isolated storage. Proof: every file applies
`20260731120000_platform_schema.sql`, which uses plain `CREATE TABLE` (no `IF NOT EXISTS`), in `beforeAll`, and that would
throw on a second application. So **a single `ALTER` in the same `beforeAll` is exactly as re-run-safe as the `CREATE TABLE`
lines before it**. vitest `retry:1` re-runs the test plus `beforeEach`/`afterEach`, not `beforeAll`.

`ai_request` is created **only** by `platform_schema`, and no later migration rebuilds it. So the fingerprint ALTER has a
single prerequisite (platform_schema) and can be appended last.

Applier abbreviations: **A** = the file's local `applyPlatformSchema` (naive `split(";")`); **S** = `applySqlStatements` (`test/split-sql-statements.ts`, sequential `prepare().run()`); **L** = load's quote-aware splitter. None use `DB.exec`. `batch` is used only for `DELETE` resets.

| File | Migrations applied (in order) | How | Touches ai_request via admission/journal? | Fingerprint needed? |
|---|---|---|---|---|
| admission-credit.test.ts | platform_schema, plan_catalogue, grace_queue (A); plan_version_paid, usage_term, fallback_feed (S) — `beforeAll` 667-674 | A+S | **yes** (`runAdmission`, direct INSERT helper) | **REQUIRED** |
| conversational-journaling.test.ts | platform_schema, h3_conversation_index (A); issuer_key_tenant, plan_version_paid, usage_term (S) — 715-721 | A+S | **yes** (`runGuard`, `createRequestRow`) | **REQUIRED** |
| pipeline.test.ts | platform_schema, h3_conversation_index, plan_catalogue (A); issuer_key_tenant, plan_version_paid (S) — 727-733 | A+S | **yes** (`runGuard`) | **REQUIRED** |
| soft-threshold-routing.test.ts | platform_schema, plan_catalogue (A); issuer_key_tenant, plan_version_paid, usage_term (S) — 819-825 | A+S | **yes** | **REQUIRED** |
| worker-request-orchestrator.test.ts | platform_schema, token_contract, canary, status, kill_switch, fallback_feed, plan_catalogue, issuer_key_tenant, plan_version_paid, usage_term — 734-757, behind a `schemaApplied` flag | local `applySql` = S | **yes** (`SELF.fetch` live POST) | **REQUIRED** |
| cohort-activate-promote.test.ts | platform_schema, lifecycle, canary, status, kill_switch (A); issuer_key_tenant, plan_version_paid (S) — 483-491. Also `import.meta.glob("../migrations/*.sql")` at 58, used **only** for text scans (`assertNoPromptActivationPointerInSqlArtifacts`) | A+S | **yes** (`createRequestRow` in T-J3-05) | **REQUIRED** |
| load/load-and-cost.test.ts | platform_schema (L); issuer_key_tenant, plan_version_paid, usage_term, fallback_feed (S) — 111-116 | L+S | **yes** (`runGuard` in beforeAll) | **REQUIRED** |
| journal.test.ts | platform_schema, usage_term, **fingerprint** — 568-572 | A | yes | already done (771ceed7) |
| system/harness.ts | all 24 in filename order (`MIGRATION_SQL` 253-278, includes `grace_queue` and **fingerprint**), applied once via `applyAllMigrations` 325-342 behind a `migrationsApplied` flag | S | yes | already done. Used by all `test/system/*.system.test.ts` **and** `test/version-matrix/*.system.test.ts` |
| e2e/harness/d1.ts | 23 files (`MIGRATION_SQL` 31-55, includes **fingerprint**; omits `20260821120000_grace_admission_queue`, but `fallback_admission_feed` and `drop_plan_entitlement` both `DROP TABLE IF EXISTS grace_admission_queue`, so the net schema is identical). Tolerant `applySql` ignores `already exists`/`UNIQUE`/`duplicate column` | splitSqlStatements | yes | already done |
| discovery-http.test.ts | platform_schema, token_contract, kill_switch, issuer_key_tenant, plan_version_paid, usage_term — 329-336 | S | no (GET discovery; passed) | optional (safe) |
| rate-limit.test.ts | platform_schema — 269 | A | counts rows only | optional (safe) |
| retention.test.ts | platform_schema, token_contract, grace_queue, fallback_feed, f3_retention, issuer_key_tenant, plan_version_paid, usage_term — 113-122 | S | direct INSERT, explicit columns | optional (safe) |
| rollup-reconciliation.test.ts | platform_schema, f3_retention, quota_weight, usage_term — 149-154 | A | direct INSERT | optional (safe) |
| support-lookup.test.ts | platform_schema — 232 | A | direct INSERT | optional (safe) |
| support-purge.test.ts | platform_schema, grace_queue, fallback_feed — 199-201 | A | direct INSERT | optional (safe) |
| journal-dashboards.test.ts | platform_schema — 291 | A | direct INSERT | optional (safe) |
| capability.test.ts | platform_schema, kill_switch, issuer_key_tenant, plan_version_paid — 658-661 | A+S | no | not needed |
| capability-deprecation.test.ts | lifecycle?, platform_schema, issuer_key_tenant, operator_cred, plan_version_paid — 416-423 | A+S | no | not needed |
| config-readers.test.ts | platform_schema … usage_term (9 files) — 182-190 | S | no | not needed |
| entitlement.test.ts | platform_schema, lifecycle, kill_switch, issuer_key_tenant, plan_version_paid — 445-449 | A+S | no | not needed |
| identity.test.ts | platform_schema, token_contract, issuer_key_tenant, plan_version_paid, usage_term — 1052-1056 | S | no | not needed |
| routing-policy-canary.test.ts | platform_schema, canary, status, operator_cred, plan_version_paid — 587-591 | A+S | no | not needed |
| token-contract-control.test.ts | platform_schema, token_contract, issuer_key_tenant, plan_version_paid, usage_term, operator_cred — 300-305 | S | no | not needed |
| vendor-entrypoint.test.ts | platform_schema, token_contract, issuer_key_tenant, operator_cred — 68-71 | S | no | not needed |
| plan-catalogue.test.ts | platform_schema, operator_cred, issuer_key_tenant, plan_version_paid, drop_invoicing, drop_plan_entitlement — 190-197 (**intentional subset**: skips plan_catalogue, asserts on drop results) | S | no | not needed — **do not touch** |
| migrations.test.ts | `npx wrangler d1 migrations apply --local` on a fresh temp `--persist-to` dir (`applyMigrations` 92-97), so it **reads the whole directory automatically** | wrangler | n/a | n/a (auto-included; this is why the snapshot diff appears) |
| context-request.test.ts (97-100), prompt-registry.test.ts (200-206) | `readdirSync(migrations)` **text scans only**, no DB | — | — | n/a |

Outside ai-platform/test (cross-impact only):
- `abo/test/system/cross-worker-harness.ts` 28-50 (imports) and 52-76 (`PLATFORM_MIGRATION_SQL`, 23 entries, **no fingerprint**), applied by `applyPlatformMigrations` 225-238 → see §6.
- `e2e/fullstack/test/variant/platform-desktop-window.toml:54` `migrations_dir = "../../../../ai-platform/migrations"` uses wrangler, so it is auto-included.

### Centralized "apply ALL migrations" helper — not recommended (now)

It is higher risk, with concrete counter-examples:
- `plan-catalogue.test.ts` intentionally applies a subset (no `plan_catalogue`, plus the drop migrations).
- `retention.test.ts:876` does `INSERT INTO entitlement` and `:982` reads `FROM entitlement`. An "all" chain ends with
  `drop_plan_entitlement` (`DROP TABLE IF EXISTS entitlement`), which would break it.
- `f3_retention_indexes` and `usage_term` each `DROP TABLE usage_event` and rebuild it with different columns and FKs. Files
  that skip them (pipeline, cohort, soft-threshold, admission-credit…) have fixtures and DELETE lists written against their
  chosen shape, so changing it is an unbounded regression surface across ~25 currently-green files.
- `issuer_key_tenant_binding` drops `installation_key`.

The lowest-risk fix is **per-file: one import plus one apply line in the 7 failing files**, using the file's existing applier,
placed last in `beforeAll`. A future-proofing helper could export only the fingerprint SQL (or a named latest-`ai_request`
chain), but that is optional and not needed to go green.

---

## 3. Exact proposed edits (line numbers at HEAD 953e5e6e)

All 7 files use the same two edits: (1) import the fingerprint SQL, (2) apply it as the **last** statement in the existing
schema `beforeAll` (after `platform_schema`, which creates `ai_request`).

### 3.1 test/admission-credit.test.ts
Import, after line 8:
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
`beforeAll`, lines 667-674 → add after line 673:
```ts
  await applySqlStatements(env.DB, fallbackAdmissionFeedMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
});
```

### 3.2 test/conversational-journaling.test.ts
Import, after line 7 (`usageTermMigrationSql`):
```ts
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
```
`beforeAll` 715-721 → after line 720 (`await applySqlStatements(env.DB, usageTermMigrationSql);`):
```ts
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
```

### 3.3 test/pipeline.test.ts
Import, after line 12 (`planVersionPaidGrantCoverageMigrationSql`):
```ts
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
```
`beforeAll` 727-733 → after line 732 (`await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);`):
```ts
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
```

### 3.4 test/soft-threshold-routing.test.ts
Import, after line 7 (`usageTermMigrationSql`):
```ts
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
```
`beforeAll` 819-825 → after line 824 (`await applySqlStatements(env.DB, usageTermMigrationSql);`):
```ts
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
```

### 3.5 test/worker-request-orchestrator.test.ts
Import, after line 75 (`usageTermMigrationSql`):
```ts
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
```
`beforeAll` 734-757, inside `if (!schemaApplied)` → after line 747 (`await applySql(env.DB, usageTermMigrationSql);`), before the `token_contract` INSERTs:
```ts
    await applySql(env.DB, usageTermMigrationSql);
    await applySql(env.DB, idempotencyFingerprintMigrationSql);
    await env.DB.prepare(
```

### 3.6 test/cohort-activate-promote.test.ts
Import, after line 9 (`planVersionPaidGrantCoverageMigrationSql`):
```ts
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
```
`beforeAll` 483-491 → after line 490:
```ts
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
});
```
The `?raw` import does not change the existing glob-based text scans: the fingerprint SQL contains no `prompt.?text` or `activation.?pointer`.

### 3.7 test/load/load-and-cost.test.ts (fixes both npm-test NR×10 and the load campaign)
Import, after line 10 (note the `../../` path):
```ts
import fallbackAdmissionFeedMigrationSql from "../../migrations/20261006160000_fallback_admission_feed.sql?raw";
import idempotencyFingerprintMigrationSql from "../../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "../split-sql-statements";
```
`beforeAll` 111-127 → after line 116, before `clearLoadTables()`:
```ts
  await applySqlStatements(env.DB, fallbackAdmissionFeedMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
  await clearLoadTables();
```
`load_suite_introduces_no_per_request_server_state` and `load_suite_joins_ci_permanently` scan `happy-path.ts`, the pipeline source, and `ci.yml`, not this import list, so they are unaffected.

### 3.8 ai-platform/schema.snap.sql (fixes T-A5-13 and `schema_snapshot_matches`)
The CI diff (npm-test output.log ~2788-2815) is the complete and only hunk:
```
@@ -23,22 +23,21 @@
    idempotency_key TEXT NOT NULL,
-   request_fingerprint TEXT,
    state TEXT NOT NULL,
 ...
-   turn_ordinal INTEGER,
+   turn_ordinal INTEGER, request_fingerprint TEXT,
    FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
```
Why: SQLite's `ALTER TABLE ADD COLUMN` rewrites `sqlite_master.sql` by splicing `", <coldef>"` at `addColOffset`. When the
table has table constraints, that offset is the comma before the first constraint (the `conslist_opt ::= COMMA conslist`
token); otherwise it is the closing `)`. The same snapshot already shows this, e.g. line 223 for `routing_policy`
(`activated_by TEXT NOT NULL, canary_installation_ids TEXT, status TEXT NOT NULL DEFAULT 'published',` then `PRIMARY KEY …`)
and lines 58, 81 and 296 for tables without constraints.

Edit:
- **Delete line 28** (`  request_fingerprint TEXT,`).
- **Line 39** (becomes 38 after the delete): `  turn_ordinal INTEGER,` → `  turn_ordinal INTEGER, request_fingerprint TEXT,`

Exact before → after (lines 26-41):
```sql
  prompt_artifact_hash TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT,          <-- remove
  state TEXT NOT NULL,
  ...
  conversation_id TEXT,
  turn_ordinal INTEGER,              <-- becomes: "  turn_ordinal INTEGER, request_fingerprint TEXT,"
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);
```
Keep the existing whitespace-only line 19 (`  `) as is: it is the residue of the stripped `-- A2 RequestReference…` comment and matches the actual DDL.
Other readers of `schema.snap.sql`: only `cohort-activate-promote.test.ts:11`, which regex-scans for prompt text/activation pointer, so it is unaffected.

### 3.9 test/manifest.test.ts T-A4-15 (`hashCanonicalJson` export)
Only importer: `src/pipeline/index.ts:34` (used at `:462` for the request fingerprint). No test imports or spies on it.
`abo/`, `packages/` and `e2e/` do not import `ai-platform/src/manifest`.

**Option A (recommended, lowest risk, test-only).** `test/manifest.test.ts` lines 253-258:
```ts
    const allowedRuntimeExports = [
      "hashCanonicalJson",
      "hashManifest",
      "load",
      "verifyManifestTree",
      "verifyPublishedRegistry",
    ].sort();
```
There is precedent: `verifyManifestTree` was added to this same list in `c7140fe8`. Both the `isData` loop (via the filter) and
the `toEqual(allowedRuntimeExports)` at 272-274 then pass. There is zero runtime change, so no other campaign can be affected.

**Option B (spec-purer, still behaviour-neutral, touches src).** `specs/018` Clarification says the manifest module exports `load()` and
`Manifest`, with the validator internal. To honour that, move `canonicalStringify` + `bufferToHex` + `hashCanonicalJson`
(`src/manifest/index.ts:623-643, 655-660`) into a new `src/canonical-json.ts`. Have `hashManifest` call it, and change
`src/pipeline/index.ts:34` to `import { type Manifest } from "../manifest";` plus `import { hashCanonicalJson } from "../canonical-json";`.
Checked tests that scan source/module paths:
- cohort `assertNoPromptActivationPointerModule` (glob `src/**/*.ts`, name regex): fine.
- `conversational-journaling.test.ts:1013-1015` (raw pipeline/journal source, forbids `ConversationSession|…`): fine.
- load-and-cost (`pipelineSource`): fine.
- vendor-contracts `bundle-scan.test.ts` (greps the bundle for the `vendor-contracts-testkit` marker only): fine.

Option B is fine too, but it rebundles the hot path that e2e, abo cross-worker and fullstack all load, so A is strictly lower risk.

---

## 4. Non-schema failures — verdicts

| Test | Verdict | Fix |
|---|---|---|
| manifest.test.ts T-A4-15 | **Independent**, deterministic. Caused by `771ceed7` exporting `hashCanonicalJson` (`src/manifest/index.ts:656`) | §3.9 |
| migrations.test.ts T-A5-13 / `schema_snapshot_matches` | **Independent**. The comparison is `dumpCreateTableDdl()` (`:127-139`): `SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND NOT LIKE 'd1_%' AND NOT LIKE '_cf_%' ORDER BY name`, joined with `";\n\n"` plus a trailing `";\n"`, compared with `toBe` after `.trim()` to the file. The only diff is the column position | §3.8 |
| cohort-activate-promote T-J3-05 | **Cascade**: `createRequestRow` INSERT names `request_fingerprint` and catches the error → `ok:false` (`:761`) | §3.6 |
| worker T16, worker cancel-usage | **Cascade**: admission throws, so `invokeEntered` stays false (`:1560`, `:1672`) | §3.5 |
| worker grace-degraded | **Cascade**: `runAdmission` is mocked; stage-9 journal INSERT fails → `internal_error` → 500 (`:1889`) | §3.5 |

---

## 5. Git history (task 5)

- `771ceed7` added the migration and changed `admission`, `journal`, `pipeline`, `quota-do`, `worker`, `manifest` and `schema.snap.sql`. It updated only
  `test/journal.test.ts`, `test/system/harness.ts` and `test/e2e/harness/d1.ts`. The other 7 workers-pool files and `abo/.../cross-worker-harness.ts` were missed.
- `e1a42092` "Restore CI campaign fixes" touched only abo/worker.ts, backend, e2e/fullstack, vendor-contracts token-claims and the campaign harness. `cb99ded0` is its exact revert. `953e5e6e` (email stub, pool 0.12.21, `retry:1`, deterministic clocks) touched none of the files above.
- **No earlier fix for this was tried and reverted.**

---

## 6. Cross-impact verdicts

- **e2e harness** `test/e2e/harness/d1.ts:23,54`: applies the fingerprint migration (confirmed). It skips `grace_admission_queue`, but the net schema matches.
- **System harness** `test/system/harness.ts:89,277`: applies all 24 migrations in filename order (confirmed). It is shared by `test/version-matrix/*` (which passes).
  **So the 8 excluded system failures are NOT schema-related**, which matches the zero schema errors in their messages.
- **abo/cross-worker (owned by another agent): the same bug.** `abo/test/system/cross-worker-harness.ts` `PLATFORM_MIGRATION_SQL` (52-76) ends at
  `dropPlanEntitlementSql`, so `request_fingerprint` is missing from `env.PLATFORM_DB`. The abo/cross-worker output.log has 32×
  `no such column: request_fingerprint`, under the FAIL headers of E2E-P4.9-03, E2E-P4.9-05, E2E-P4.8-07 and E2E-P4.4-01. Suggested edit:
  - after line 50: `import idempotencyFingerprintSql from "../../../ai-platform/migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";`
  - after line 75: `  idempotencyFingerprintSql,`

  The harness applies the list once, behind `platformMigrationsApplied` (225-238). E2E-P4.2-03 (NOT_RECORDED) was not traced.
- **e2e-fullstack** uses `migrations_dir` via wrangler, so it is auto-included.
- **Edits in §3.1-3.7 are test-local**: each touches one file's `beforeAll`, and no other file imports from these test files.
  `split-sql-statements.ts` is not modified.
- `migrations.test.ts` runs in the unit config (`vitest.config.ts`), not the workers config; `schema.snap.sql` affects only it and cohort's text scan.

---

## 7. Open risks / predicted next-layer failures

1. **`admission-credit.test.ts > admission_repeated_key_no_second_inference` (high confidence it fails after the schema fix).**
   - The test (`:718-767`) admits, then journals a row via `journalAdmittedRequest` (`:624-649`, direct INSERT, no fingerprint),
     then re-admits the same key **without** `requestFingerprint`. It expects `secondSpy.fetchCount()` = **0** and `outcome:"idempotent"`.
   - Since `771ceed7`, `runAdmission` no longer returns early from the journal (the removed `if (journaled) return idempotentFromJournal(journaled)`).
     With `idempotencyBinding` undefined, `journaledBindingMatches` is false (`src/admission/index.ts:647-653`), so admission sends
     `journaledConflict: true` and the DO returns `idempotency_conflict` (`src/quota-do/index.ts:516-522`). The result is 1 fetch and `ok:false`.
   - The `771ceed7` comment ("A D1 row is not sufficient to replay a request: the per-installation DO must authorize the JTI") shows the change is intentional.
     So this test must be updated to the new contract by the idempotency owner, or the product logic revisited.
   - It is the same mechanism as many of the e2e 409-vs-200 replay failures (S09-068/069, S10-016/018/019, S11-013/014/015) and SYS-5.5/5.6/7.4.
2. Worker T15 (repeated key through the live route) and pipeline stage-8 duplicate key: I expect them to pass, because both calls go through
   `runGuard`, which computes and persists the same fingerprint. Confidence is medium, because the e2e and system replay tests that fail with 409 use the same route. If they
   fail after the fix, they belong with the idempotency owner's work.
3. I could not run vitest. Edits are verified by reading source and CI logs only.

## Confidence
- Classification and root cause for the 70 (a)/(a′) + 10 NR: **very high** (decisive log lines, stack traces, pre-`771ceed7` green run).
- `schema.snap.sql` fix: **very high** (the exact CI diff is shown).
- T-A4-15 fix: **very high**.
- Post-fix prediction for `admission_repeated_key_no_second_inference`: **high**. T15 / stage-8: **medium**.

CI evidence that would confirm the fix: npm-test shows 0 `no such column` errors; load-and-cost reports 10/10; the load campaign exits 0;
and the npm-test FAIL set shrinks to the 8 system tests plus (predicted) `admission_repeated_key_no_second_inference`.
