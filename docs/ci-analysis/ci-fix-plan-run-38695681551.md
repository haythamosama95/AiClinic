# CI fix plan — run 38695681551 (branch `ai/abo-master`, base `953e5e6e`)

Self-contained implementation plan. Apply it without reading any other analysis file.
Do **not** use `ci-failure-analysis-run-38695681551.md` (repo root); it is wrong in several places.

---

## 1. TL;DR

**What is broken in run 38695681551**

| Campaign | Result | Root cause (verified) |
|---|---|---|
| ai-platform/npm-test | 81 FAIL + 10 NOT_RECORDED | (a) 7 workers-pool test files hand-list migrations and miss `20261014120000_ai_request_idempotency_fingerprint.sql` → `no such column: request_fingerprint` (70 tests + 10 NR). (b) `schema.snap.sql` puts the new column mid-table (SQLite appends it). (c) new export `hashCanonicalJson` not in manifest allowlist. (d) 8 system tests: replay bodies regenerated (409), same-jti replay (401), settlement read too early. |
| ai-platform/load | 10 NOT_RECORDED | same missing migration in `test/load/load-and-cost.test.ts` `beforeAll`. |
| ai-platform/e2e | 11 FAIL | 8 replay tests regenerate the body (random `visit_id`/`recorded_at`) → fingerprint mismatch → 409 (correct product behaviour); 3 tests read settlement before it lands. |
| abo/cross-worker | 4 FAIL + 1 NR | same missing migration in `abo/test/system/cross-worker-harness.ts`; P4.2-03 never ran because the step sequence stops on first failure. |
| vendor-contracts/all | 1 FAIL (E2E-P2.2-08) | bundle never builds: `ai-platform/node_modules` not installed in that CI job. |
| e2e-fullstack/all-ci | 2 FAIL | ai-platform + abo not installed (bundle), p5-2 imports `cloudflare:workers` into Node; hidden: `Buffer` in workerd, non-canonical PG JWT JSON (billing + feed), ABO vars passed as env (ignored), missing Host header on ABO readiness, pg_net cannot reach 127.0.0.1-bound platform. |
| e2e-fullstack/all-manual | 12 FAIL, exit 130, 14 tests never ran | all files run in parallel on one `.wrangler` + fixed ports; variant tomls lack `migrations_dir`; one-org-per-installation; Supabase state leaks between files; Dart helper not compilable; everything above. |
| frontend/all | 12 FAIL | fullstack-tagged files run in the unit step; boundary step never ran (checks docker-compose, no profile, no psql). |
| frontend/fullstack | exit 1, 0 tests | no npm installs; plus no `--machine`, P7.3-06 port clash, ORG_ALREADY_EXISTS in prepare, no offers/grant globals seeded, GoTrue rate limit 30/5 min. |

Green and must stay green: backend/all 73, backend/catalog 8, vendor-contracts 10 others, abo system 23 / import-boundary 2 / version-matrix 1, ai-platform eval 24 / eval-all 39 / version-matrix 2, ops-launch 2, plus 1375 npm-test and 525 e2e passes.

**Fix shape:** 9 phases (one commit each), ~60 files. No production logic change in ai-platform/src. Product-code changes are limited to: `packages/vendor-contracts` base64 decoding (`atob`), abo GET `/v1/checkouts` 404 JSON body, two backend migrations (canonical JWT JSON for billing + feed tokens), local-only Supabase rate limits.

**Expected outcome of the first CI run after all phases:** ai-platform, abo, vendor-contracts, backend, ops-launch green; e2e-fullstack all-ci green with high probability; e2e-fullstack all-manual and frontend (boundary, fullstack) are run for the first time ever in CI — expect *attempted == total* and most tests green, with a possible tuning pass (see §8).

---

## 2. Ground rules for the implementer

1. Work on branch `ai/abo-master`, starting from `953e5e6e` (`git log -1 --format=%h` must print `953e5e6e`; tree must be clean: `git status --porcelain` prints nothing except this plan file and the `docs/ci-analysis/run-38695681551/` reference folder).
2. Apply phases **in order P1 → P9**. Make **exactly one commit per phase** with the commit message given in the phase. Do not squash, do not reorder.
3. **Never "improve" beyond the plan.** No refactors, no extra cleanups, no formatting passes, no renames, no new tests except the ones the plan lists.
4. **No tests can be run locally** (no vitest/wrangler/flutter/supabase). Use only the self-checks listed per phase (`git diff --stat`, `rg`, `node --check`, `bash -n`, `python -m py_compile`, `git apply --check`).
5. **Line endings: LF.** The repo has `core.autocrlf=true`; commits are normalised to LF. When creating new files, write LF. Do not add a BOM.
6. **Exact-match edits.** Each step gives a BEFORE snippet copied from the file and an AFTER snippet. Replace BEFORE with AFTER exactly (preserve indentation: 2 spaces in JS/TS/Dart, 4 in Python).
   - Line numbers are hints only. If a BEFORE snippet does not match at the hinted line, **locate it by its anchor text** (search for a distinctive line from the snippet).
   - If the anchor is not found, or matches more than once and the plan does not say which, **STOP and report** the phase/step id and what you found. Do not improvise.
7. For files changed by P5 (the revert), BEFORE snippets in later phases refer to the **post-revert** content (= `git show e1a42092:<path>`).
8. Never touch: `ai-platform/src/**` (no step edits it), anything from the `ai/reg-fixes` branch, `test/harness/test_campaign_live_stats.py`, the repo-root `ci-failure-analysis-run-38695681551.md`.
9. After all phases: push (`git push origin ai/abo-master`) and trigger CI as described in §7.

---

## 3. Decisions log

### User decisions
- **U1.** Everything runs in CI, nothing excluded: e2e-fullstack `all-ci` **and** `all-manual` must pass; frontend `boundary` step (inside frontend/all) **and** `frontend/fullstack` are wired properly in CI.
- **U2.** E2E-P6.3-01 option (b): its final assertion is narrowed to "AAT mint succeeds and `get_ai_status` is active". The real AI request to `ai.example.workers.dev` is removed. The real AI path stays covered by ai-platform e2e and abo cross-worker.
- **U3.** **e1a42092 was reverted (cb99ded0) because CI still failed, not because it caused regressions.** Hunks 1–7 are re-applied per agent F's recommendation via `git revert --no-commit cb99ded0` + `git checkout HEAD -- test/harness/test_campaign_live_stats.py` (hunk 8 skipped: it is red at HEAD). The remaining failures it did not cover are fixed in phases **P6–P9** (plus P1–P4 for areas it never touched). Nothing from e1a42092 or from the unmerged `ai/reg-fixes` branch is re-applied unless an agent recommended it.

### Coordinator decisions (verified)
- **C1.** Migrations: per-file `?raw` import + one apply line in the 7 ai-platform test files and in `abo/test/system/cross-worker-harness.ts`. **No shared "apply all migrations" loader** (it breaks intentional subsets such as `plan-catalogue.test.ts` and `retention.test.ts`).
- **C2.** `schema.snap.sql`: delete the mid-table `request_fingerprint TEXT,` line; append ` request_fingerprint TEXT,` to the `turn_ordinal INTEGER,` line (matches the CI diff). Manifest: extend the allowlist with `hashCanonicalJson` (option A, test-only).
- **C3.** Replay 409s: memoise the visit context per installation in `test/e2e/harness/clinic.ts` and `test/system/harness.ts` (agent B F1). `ai-platform/src` has no freshness check on `recorded_at`. F1' (thread one body through each test) is a documented fallback only. Plus F2 (fresh token for P3.4-11), F3 (settlement polls, **exactly as agent B wrote them, including `failWithEmptyChain` and SYS-5.6**), and the admission-credit companion edit.
- **C4.** Re-apply e1a42092 mechanically (see U3). `git diff cb99ded0 HEAD` is empty for all e1a42092 paths, so the revert reproduces hunks 1–7 exactly.
- **C5.** CI excludes pushes to `ai/abo-master` (`branches: [..., "!ai/abo-master"]`) but has `workflow_dispatch`; trigger with `gh workflow run ci.yml --ref ai/abo-master` (§7). `manual-campaign.yml` is updated in P4 for parity (tool installs per area).

### Wrap-up decisions (conflicts between reports, resolved here)
- **W1. One-org-per-installation (`ORG_ALREADY_EXISTS`).** Reuse e1a42092's approach everywhere: `p7-2-stack.mjs` gets it from the revert (P5); the same `findTestOrganizationId` / `insertTestOrganization` / `findTestBranchId` + `set_active_organization` logic is **ported into `p7-3-stack.mjs` `createOrgClinic`** (P7). Additionally `p7-3-06-prepare.mjs` passes `createClinics: false` (agent D), because the frontend path never uses harness orgs and creating them would leak orgs into the Dart test installation. Result: e2e P7.2/P7.3 get two orgs reliably; the frontend path creates none.
- **W2. Supabase reset between e2e-fullstack files** (`supabase db reset` + readiness poll) lives only in `e2e/fullstack/run_campaigns.py` and is gated by `HFS_RESET_SUPABASE=1`, which `ci.yml` sets **only** for the e2e-fullstack matrix entry. The frontend path (`frontend/tool/run_campaigns.py` → `hfl-run-flutter.mjs`) never calls it. The readiness poll checks `/auth/v1/health` **and** `/rest/v1/` (agent C R7).
- **W3. Platform bind host.** `PLATFORM_BIND_HOST` (env `HFS_PLATFORM_BIND_HOST`, default `127.0.0.1`) is used by every platform `startWorker` in p5-1, p5-2, p7-2-stack, p7-3-stack. CI sets `0.0.0.0` only for e2e-fullstack. Frontend keeps `127.0.0.1`. Clients always use `http://127.0.0.1:8787`.
- **W4. Pinned wrangler.** The post-revert `wrangler-persist.mjs` defines `const WRANGLER_CLI`; P7 makes it `export const` and p5-1, p5-2, p7-3-stack spawn `process.execPath WRANGLER_CLI`. Post-revert `p7-2-stack.mjs` already spawns the same path inline; left as is. `npx supabase` in p5-2 becomes `supabase` (CLI on PATH from setup-cli).
- **W5. ABO vars.** Each file keeps exactly the vars it passes today, moved from `env` to `--var KEY:VALUE`: p5-1 = `PAYMOB_BASE_URL`, `ISSUER_KEYS`; p5-2 and p7-3-stack = those plus `ABO_GRANT_KEY`, `PLATFORM_PUBLIC_KEYS` (p7-2-stack already does this after P5).
- **W6. p5-1/p5-2 stack fixes (agent F §4.3):** `waitForHttp` gains a `headers` option and the ABO waits send `Host: billing.vendor.test` (same as e1a42092 p7-2-stack); `spawnDevProcess` uses the pinned CLI with `detached`; `stopChild` becomes the process-group version copied from `p7-3-stack.mjs`; `stop()` stops `stackRef.abo` (the restarted ABO), not the original.
- **W7. p5-2 live-DB writes:** `runPlatformD1Command` body becomes `execPlatformD1Sql(sql)` (agent C F.3c). `insertGrantAppliedEvent` (also `wrangler d1 execute` on the live persist) is **not** changed — no agent recommended it; listed as residual risk R8.
- **W8. `execPlatformD1Sql` busy timeout.** On top of the post-revert direct-write version, add `PRAGMA busy_timeout = 5000` (agent C F.3c).
- **W9. Backend rate limits** (`backend/supabase/config.toml`, agent D N1/F4) are committed together with the backend feed-JCS migration in P6, so all backend-touching changes are in one bisectable commit (backend campaign must re-run).
- **W10. All e2e/fullstack/test edits in one phase (P7)**, including the frontend-only ones (`hfl-run-flutter.mjs` seeds, `p7-3-06-prepare.mjs` `createClinics:false`, `seedPlatformGrantGlobals` export), so each shared file gets one consistent set of edits after the P5 revert. P9 only wires the frontend runner and Dart tests.
- **W11. Timeouts.** e2e-fullstack per-file `test_timeout_ms` 360000 (all JSONs except `p5-2b.json`); job `timeout_minutes`: e2e-fullstack 110, frontend 120. `manual-campaign.yml` job timeout raised 90 → 120.
- **W12. p5-1/p5-2 run twice** (all-ci then all-manual): kept (agent C F.1c); safe because each file starts on a clean `.wrangler` + clean Supabase.
- **W13. abo `continue_on_step_failure` is NOT added** (agent C: skip). P4.2-03 runs once the cross-worker step passes (P3).
- **W14. E2E-P6.3-01 narrowing (U2) implementation:** replace the `_expectAiRequestSucceeds(composition)` call with a direct `issue_ai_token` RPC assertion; keep the now-unused helper with `// ignore: unused_element` (no analyzer gate exists; avoids touching imports).
- **W15. Agent D F10** (per-org platform `tenant_binding` seed in the Dart billing test) is applied in P9 (needed for P6.3 "Active").
- **W16. Governor Flutter parser fix (H1–H3)** is applied in P9; its pytest is developer-run only (not in CI).

---

## 4. Phases

### P1 — ai-platform: fingerprint migration in 7 test files, schema snapshot, manifest allowlist

All paths relative to `ai-platform/`. The migration file content is
`ALTER TABLE ai_request ADD COLUMN request_fingerprint TEXT;` — it only needs `platform_schema` first, so it is applied **last** in each `beforeAll`.

**P1.1 `test/admission-credit.test.ts`**
BEFORE (line ~8):
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
AFTER:
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
BEFORE (line ~667):
```ts
beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, planCatalogueMigrationSql);
  await applyPlatformSchema(env.DB, graceQueueMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, usageTermMigrationSql);
  await applySqlStatements(env.DB, fallbackAdmissionFeedMigrationSql);
});
```
AFTER:
```ts
beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, planCatalogueMigrationSql);
  await applyPlatformSchema(env.DB, graceQueueMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, usageTermMigrationSql);
  await applySqlStatements(env.DB, fallbackAdmissionFeedMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
});
```

**P1.2 `test/conversational-journaling.test.ts`**
BEFORE (line ~7):
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
AFTER:
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
BEFORE (line ~715):
```ts
beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, conversationIndexSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, usageTermMigrationSql);
});
```
AFTER:
```ts
beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, conversationIndexSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, usageTermMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
});
```

**P1.3 `test/pipeline.test.ts`**
BEFORE (line ~12):
```ts
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
AFTER:
```ts
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
BEFORE (line ~727):
```ts
beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, conversationIndexSql);
  await applyPlatformSchema(env.DB, planCatalogueSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
});
```
AFTER:
```ts
beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, conversationIndexSql);
  await applyPlatformSchema(env.DB, planCatalogueSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
});
```

**P1.4 `test/soft-threshold-routing.test.ts`**
BEFORE (line ~7):
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
AFTER:
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
BEFORE (line ~819):
```ts
beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, planCatalogueMigrationSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, usageTermMigrationSql);
});
```
AFTER:
```ts
beforeAll(async () => {
  await applyPlatformSchema(env.DB, migrationSql);
  await applyPlatformSchema(env.DB, planCatalogueMigrationSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, usageTermMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
});
```

**P1.5 `test/worker-request-orchestrator.test.ts`**
BEFORE (line ~75):
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
AFTER:
```ts
import usageTermMigrationSql from "../migrations/20261006120000_usage_term.sql?raw";
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
BEFORE (line ~746, inside `if (!schemaApplied) {`):
```ts
    await applySql(env.DB, planVersionPaidGrantCoverageMigrationSql);
    await applySql(env.DB, usageTermMigrationSql);
    await env.DB.prepare(
```
AFTER:
```ts
    await applySql(env.DB, planVersionPaidGrantCoverageMigrationSql);
    await applySql(env.DB, usageTermMigrationSql);
    await applySql(env.DB, idempotencyFingerprintMigrationSql);
    await env.DB.prepare(
```
(If this 3-line BEFORE occurs more than once, use the occurrence inside the `beforeAll` at line ~734.)

**P1.6 `test/cohort-activate-promote.test.ts`**
BEFORE (line ~9):
```ts
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
AFTER:
```ts
import planVersionPaidGrantCoverageMigrationSql from "../migrations/20261003140000_plan_version_paid_grant_coverage.sql?raw";
import idempotencyFingerprintMigrationSql from "../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "./split-sql-statements";
```
BEFORE (line ~483):
```ts
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
});
```
AFTER:
```ts
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, planVersionPaidGrantCoverageMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
});
```
(Use the occurrence that closes the `beforeAll` starting at line ~483.)

**P1.7 `test/load/load-and-cost.test.ts`** (note `../../` paths; fixes both npm-test NR×10 and the load campaign)
BEFORE (line ~10):
```ts
import fallbackAdmissionFeedMigrationSql from "../../migrations/20261006160000_fallback_admission_feed.sql?raw";
import { applySqlStatements } from "../split-sql-statements";
```
AFTER:
```ts
import fallbackAdmissionFeedMigrationSql from "../../migrations/20261006160000_fallback_admission_feed.sql?raw";
import idempotencyFingerprintMigrationSql from "../../migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
import { applySqlStatements } from "../split-sql-statements";
```
BEFORE (line ~116):
```ts
  await applySqlStatements(env.DB, fallbackAdmissionFeedMigrationSql);
  await clearLoadTables();
```
AFTER:
```ts
  await applySqlStatements(env.DB, fallbackAdmissionFeedMigrationSql);
  await applySqlStatements(env.DB, idempotencyFingerprintMigrationSql);
  await clearLoadTables();
```

**P1.8 `schema.snap.sql`** (at `ai-platform/schema.snap.sql`)
BEFORE (lines ~27-29):
```sql
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT,
  state TEXT NOT NULL,
```
AFTER:
```sql
  idempotency_key TEXT NOT NULL,
  state TEXT NOT NULL,
```
BEFORE (line ~39, the only `turn_ordinal INTEGER,` line):
```sql
  turn_ordinal INTEGER,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
```
AFTER:
```sql
  turn_ordinal INTEGER, request_fingerprint TEXT,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
```
Keep every other line (including the whitespace-only line ~19) unchanged.

**P1.9 `test/manifest.test.ts`** (line ~253)
BEFORE:
```ts
    const allowedRuntimeExports = [
      "hashManifest",
```
AFTER:
```ts
    const allowedRuntimeExports = [
      "hashCanonicalJson",
      "hashManifest",
```

**P1 self-check**
- `git diff --stat` → 9 files under `ai-platform/`, ~+19 / −1 lines.
- `rg -c "idempotencyFingerprintMigrationSql" ai-platform/test/admission-credit.test.ts ai-platform/test/conversational-journaling.test.ts ai-platform/test/pipeline.test.ts ai-platform/test/soft-threshold-routing.test.ts ai-platform/test/worker-request-orchestrator.test.ts ai-platform/test/cohort-activate-promote.test.ts ai-platform/test/load/load-and-cost.test.ts` → `2` for each file.
- `rg -n "request_fingerprint" ai-platform/schema.snap.sql` → exactly one hit, on the `turn_ordinal INTEGER, request_fingerprint TEXT,` line.

**Commit:** `ai-platform tests: apply request_fingerprint migration, fix schema snapshot and manifest allowlist`

---

### P2 — ai-platform: replay bodies, fresh token, settlement polls, admission-credit contract

Why: since `771ceed7` an idempotent replay is bound to a fingerprint of the filtered request body (correct per spec FR-015). The harness regenerates `visit_id`/`recorded_at` per call, so replays are different requests → 409. Settlement of Completed/Cancelled runs in `waitUntil`; its last write is `ai_request.payload_pointer`, so tests must poll for it. All edits are test-only.

**P2.1 (F1) `ai-platform/test/e2e/harness/clinic.ts`** (line ~17)
BEFORE:
```ts
export function visitSummaryInvokeBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: {
      org: scenario.orgId,
      branch: scenario.branchId,
      [VISIT_CHIEF_COMPLAINT_V1]: {
        visit_id: crypto.randomUUID(),
        complaint: "Headache for three days.",
        recorded_at: new Date().toISOString(),
      },
```
AFTER:
```ts
const visitContextByInstallation = new Map<
  string,
  { visitId: string; recordedAt: string }
>();

function visitContextFor(installationId: string): { visitId: string; recordedAt: string } {
  let visit = visitContextByInstallation.get(installationId);
  if (visit === undefined) {
    visit = { visitId: crypto.randomUUID(), recordedAt: new Date().toISOString() };
    visitContextByInstallation.set(installationId, visit);
  }
  return visit;
}

export function visitSummaryInvokeBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: {
      org: scenario.orgId,
      branch: scenario.branchId,
      [VISIT_CHIEF_COMPLAINT_V1]: {
        visit_id: visitContextFor(scenario.installationId).visitId,
        complaint: "Headache for three days.",
        recorded_at: visitContextFor(scenario.installationId).recordedAt,
      },
```

**P2.2 (F1) `ai-platform/test/system/harness.ts`** (line ~820) — same change, using the file's own `randomUuid()`.
BEFORE:
```ts
export function visitSummaryInvokeBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: {
      org: scenario.orgId,
      branch: scenario.branchId,
      [VISIT_CHIEF_COMPLAINT_V1]: {
        visit_id: randomUuid(),
        complaint: "Headache for three days.",
        recorded_at: new Date().toISOString(),
      },
```
AFTER:
```ts
const visitContextByInstallation = new Map<
  string,
  { visitId: string; recordedAt: string }
>();

function visitContextFor(installationId: string): { visitId: string; recordedAt: string } {
  let visit = visitContextByInstallation.get(installationId);
  if (visit === undefined) {
    visit = { visitId: randomUuid(), recordedAt: new Date().toISOString() };
    visitContextByInstallation.set(installationId, visit);
  }
  return visit;
}

export function visitSummaryInvokeBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    capability_id: CAPABILITY_ID,
    capability_version: CAPABILITY_VERSION,
    user_intent: "Summarize the visit.",
    context: {
      org: scenario.orgId,
      branch: scenario.branchId,
      [VISIT_CHIEF_COMPLAINT_V1]: {
        visit_id: visitContextFor(scenario.installationId).visitId,
        complaint: "Headache for three days.",
        recorded_at: visitContextFor(scenario.installationId).recordedAt,
      },
```

**P2.3 (F3) `ai-platform/test/system/harness.ts` — new export** directly after `getUsageEvents` (line ~1213).
BEFORE:
```ts
export async function getUsageEvents(requestId: string): Promise<Record<string, unknown>[]> {
  return queryAll("SELECT * FROM usage_event WHERE request_id = ?", [requestId]);
}
```
AFTER:
```ts
export async function getUsageEvents(requestId: string): Promise<Record<string, unknown>[]> {
  return queryAll("SELECT * FROM usage_event WHERE request_id = ?", [requestId]);
}

export async function waitForSettledRequest(
  requestReference: string,
  timeoutMs = 8000,
): Promise<Record<string, unknown>> {
  const started = Date.now();
  for (;;) {
    const row = await getAiRequest(requestReference);
    if (row !== null && typeof row.payload_pointer === "string" && row.payload_pointer.length > 0) {
      return row;
    }
    if (Date.now() - started > timeoutMs) {
      throw new Error(`settlement did not land for ${requestReference}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}
```

**P2.4 (F2+F3) `ai-platform/test/system/admission-settlement.system.test.ts`**
- Import: BEFORE `  ensureDefaultCohortGrants,\n  type Scenario,\n} from "./harness";` → AFTER:
```ts
  ensureDefaultCohortGrants,
  waitForSettledRequest,
  type Scenario,
} from "./harness";
```
- E2E-P3.4-01 (line ~362). BEFORE:
```ts
    await flushBackgroundWork();

    const ref = String(invoked.events[0]?.data.request_reference);
    const request = await getAiRequest(ref);
```
AFTER:
```ts
    await flushBackgroundWork();

    const ref = String(invoked.events[0]?.data.request_reference);
    await waitForSettledRequest(ref);
    const request = await getAiRequest(ref);
```
- E2E-P3.4-11 (line ~731). BEFORE:
```ts
    expect(first.status).toBe(200);
    await flushBackgroundWork();

    const replayIdempotency = await invoke(scenario, { token, idempotencyKey });
```
AFTER:
```ts
    expect(first.status).toBe(200);
    await flushBackgroundWork();

    await waitForSettledRequest(String(first.events[0]?.data.request_reference));
    const replayIdempotency = await invoke(scenario, {
      token: await mintAat(scenario),
      idempotencyKey,
    });
```
  (`mintAat` is already imported in this file. If `mintAat` takes different arguments, mint the fresh token the same way `token` is minted earlier in this test.)

**P2.5 (F3) `ai-platform/test/system/cron-retention-interplay.system.test.ts`**
- Import: BEFORE `  setupPromotedFakePolicy,\n} from "./harness";` → AFTER:
```ts
  setupPromotedFakePolicy,
  waitForSettledRequest,
} from "./harness";
```
- SYS-8.1 (line ~45). BEFORE:
```ts
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const request = await getAiRequest(ref);
```
AFTER:
```ts
    const ref = String(invoked.events[0]?.data.request_reference);
    await flushBackgroundWork();
    await waitForSettledRequest(ref);

    const request = await getAiRequest(ref);
```

**P2.6 (F3) `ai-platform/test/system/quota-admission-interplay.system.test.ts`**
- Import: BEFORE `  visitSummaryInvokeBody,\n  type CoverClinicOptions,\n} from "./harness";` → AFTER:
```ts
  visitSummaryInvokeBody,
  waitForSettledRequest,
  type CoverClinicOptions,
} from "./harness";
```
- SYS-5.5 (line ~259). BEFORE:
```ts
    const ref = String(first.events[0]?.data.request_reference);
    await flushBackgroundWork();

    const requestBefore = await getAiRequest(ref);
```
AFTER:
```ts
    const ref = String(first.events[0]?.data.request_reference);
    await flushBackgroundWork();
    await waitForSettledRequest(ref);

    const requestBefore = await getAiRequest(ref);
```
- SYS-5.6 failed half (line ~316). BEFORE:
```ts
    expect(failed.events[1]?.data.code).toBe("provider_unavailable");
    await flushBackgroundWork();
    const failedAttemptsBefore = await count("ai_attempt");
```
AFTER:
```ts
    expect(failed.events[1]?.data.code).toBe("provider_unavailable");
    await flushBackgroundWork();
    await waitForSettledRequest(String(failed.events[0]?.data.request_reference));
    const failedAttemptsBefore = await count("ai_attempt");
```
- SYS-5.6 cancelled half (line ~399). BEFORE:
```ts
    expect(cancelledRow?.state).toBe("Cancelled");

    const cancelledReplay = await invoke(cancelledScenario, {
```
AFTER:
```ts
    expect(cancelledRow?.state).toBe("Cancelled");
    const cancelledRef = await env.DB.prepare(
      `SELECT request_reference FROM ai_request
       WHERE installation_id = ? AND idempotency_key = ?`,
    )
      .bind(cancelledScenario.installationId, cancelledKey)
      .first<{ request_reference: string }>();
    await waitForSettledRequest(String(cancelledRef?.request_reference));

    const cancelledReplay = await invoke(cancelledScenario, {
```

**P2.7 (F3) `ai-platform/test/system/settlement-integrity.system.test.ts`**
- Import: BEFORE `  visitSummaryInvokeBody,\n  type Scenario,\n} from "./harness";` → AFTER:
```ts
  visitSummaryInvokeBody,
  waitForSettledRequest,
  type Scenario,
} from "./harness";
```
- `completeRequest` (line ~82) **and** `failWithEmptyChain` (line ~113): the following 2-line BEFORE occurs exactly twice (once in each helper); replace **both** occurrences.
BEFORE:
```ts
  await flushBackgroundWork();
  const request = await getAiRequest(ref);
```
AFTER:
```ts
  const request = await waitForSettledRequest(ref);
```
- SYS-7.3 (line ~330). BEFORE:
```ts
      expect(usageCount).toBe(1);
      expect(await r2Exists(String(request?.payload_pointer))).toBe(true);
```
AFTER:
```ts
      expect(usageCount).toBe(1);
      const settled = await waitForSettledRequest(String(request?.request_reference));
      expect(await r2Exists(String(settled.payload_pointer))).toBe(true);
```
- SYS-7.4 (line ~427). BEFORE:
```ts
        .bind(cancelledKey)
        .first<{ request_id: string; request_reference: string }>();
      expect(cancelledRow?.request_id).toBeTruthy();
```
AFTER:
```ts
        .bind(cancelledKey)
        .first<{ request_id: string; request_reference: string }>();
      expect(cancelledRow?.request_id).toBeTruthy();
      await waitForSettledRequest(String(cancelledRow?.request_reference));
```

**P2.8 (F3) `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts`** (local helper; the e2e harness barrel gets no new files)
- BEFORE (line ~442):
```ts
async function requireAiRequest(ref: string): Promise<Record<string, unknown>> {
  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  return row!;
}
```
AFTER:
```ts
async function requireAiRequest(ref: string): Promise<Record<string, unknown>> {
  const row = await getAiRequest(ref);
  expect(row).not.toBeNull();
  return row!;
}

async function waitForSettledRow(ref: string): Promise<Record<string, unknown>> {
  const started = Date.now();
  for (;;) {
    const row = await requireAiRequest(ref);
    if (typeof row.payload_pointer === "string" && row.payload_pointer.length > 0) return row;
    if (Date.now() - started > 8000) throw new Error(`settlement did not land for ${ref}`);
    await flushBackgroundWork(50);
  }
}
```
- S10-001 (line ~486). BEFORE:
```ts
    const ref = assertHappyPathEvents(result.events, "s10-001-trace");

    const row = await requireAiRequest(ref);
```
AFTER:
```ts
    const ref = assertHappyPathEvents(result.events, "s10-001-trace");

    const row = await waitForSettledRow(ref);
```
- S10-016 (line ~1406). BEFORE: `    const firstRow = await requireAiRequest(firstRef);` → AFTER: `    const firstRow = await waitForSettledRow(firstRef);`

**P2.9 (F3) `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts`**
- S11-002 (line ~858). BEFORE:
```ts
        assertCompletedEvent(completed, FAKE_SUMMARY);

        const row = await requireAiRequest(ref);
        expect(row.state).toBe("Completed");
        const attempts = await getAttempts(String(row.request_id));
```
AFTER:
```ts
        assertCompletedEvent(completed, FAKE_SUMMARY);

        const row = await waitForCompletedEnvelope(ref);
        expect(row.state).toBe("Completed");
        const attempts = await getAttempts(String(row.request_id));
```
- S11-010 (line ~1591). BEFORE:
```ts
      const envelope = await getR2Json(String(row.payload_pointer));
      expect(envelope.attempts as unknown[]).toHaveLength(2);
```
AFTER:
```ts
      let settledRow = await requireAiRequest(String(row.request_reference));
      const pointerStarted = Date.now();
      while (typeof settledRow.payload_pointer !== "string" && Date.now() - pointerStarted < 8000) {
        await flushBackgroundWork(50);
        settledRow = await requireAiRequest(String(row.request_reference));
      }
      const envelope = await getR2Json(String(settledRow.payload_pointer));
      expect(envelope.attempts as unknown[]).toHaveLength(2);
```

**P2.10 admission-credit companion edit — `ai-platform/test/admission-credit.test.ts`** (new contract: a journaled row replays only with a matching fingerprint and after the DO authorises the fresh jti, i.e. 1 DO fetch)
- `defaultAdmissionInput` (line ~585). BEFORE:
```ts
    idempotencyKey?: string;
    requestReference?: string;
  } = {},
): AdmissionInput {
  return {
    principal: makePrincipal(installationId, overrides.principal),
    idempotencyKey: overrides.idempotencyKey ?? uniqueIdempotencyKey(),
    requestReference: overrides.requestReference ?? uniqueRequestReference(),
    capabilityId: "clinic.visit_summary",
    quotaWeight: 1,
    cache,
    reader,
  };
}
```
AFTER:
```ts
    idempotencyKey?: string;
    requestReference?: string;
    requestFingerprint?: string;
  } = {},
): AdmissionInput {
  return {
    principal: makePrincipal(installationId, overrides.principal),
    idempotencyKey: overrides.idempotencyKey ?? uniqueIdempotencyKey(),
    requestReference: overrides.requestReference ?? uniqueRequestReference(),
    capabilityId: "clinic.visit_summary",
    quotaWeight: 1,
    cache,
    reader,
    ...(overrides.requestFingerprint === undefined
      ? {}
      : { requestFingerprint: overrides.requestFingerprint }),
  };
}
```
- `journalAdmittedRequest` (line ~624). BEFORE:
```ts
  idempotencyKey: string;
}): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO ai_request (
       request_id, request_reference, installation_id, actor_id, branch_id,
       capability_id, capability_version, prompt_artifact_hash, idempotency_key,
       state, created_at, updated_at, completed_at, terminal_error_code,
       trace_id, payload_pointer, conversation_id, turn_ordinal
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL, NULL, NULL)`,
  )
```
AFTER:
```ts
  idempotencyKey: string;
  requestFingerprint?: string;
}): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO ai_request (
       request_id, request_reference, installation_id, actor_id, branch_id,
       capability_id, capability_version, prompt_artifact_hash, idempotency_key,
       state, created_at, updated_at, completed_at, terminal_error_code,
       trace_id, payload_pointer, conversation_id, turn_ordinal, request_fingerprint
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL, NULL, NULL, ?)`,
  )
```
  and in the same function's `.bind(` list, BEFORE:
```ts
      "01ADMJOURNALTRACE00000001",
    )
```
  AFTER:
```ts
      "01ADMJOURNALTRACE00000001",
      input.requestFingerprint ?? null,
    )
```
  (Use the occurrence inside `journalAdmittedRequest`, line ~651.)
- Test `admission_repeated_key_no_second_inference` (line ~718): make these four changes inside that `it(...)` only:
  1. After `    const requestReference = uniqueRequestReference();` add `    const requestFingerprint = "f".repeat(64);`
  2. In the first `defaultAdmissionInput(... { idempotencyKey, requestReference, })` call: BEFORE `        idempotencyKey,\n        requestReference,\n      }),` → AFTER `        idempotencyKey,\n        requestReference,\n        requestFingerprint,\n      }),`
  3. In `journalAdmittedRequest({ installationId, requestId: first.requestId, requestReference, idempotencyKey, })`: BEFORE `      requestReference,\n      idempotencyKey,\n    });` → AFTER `      requestReference,\n      idempotencyKey,\n      requestFingerprint,\n    });`
  4. In the second call: BEFORE `        principal: { jti: uniqueJti() },\n      }),` → AFTER `        principal: { jti: uniqueJti() },\n        requestFingerprint,\n      }),`; and BEFORE `    expect(secondSpy.fetchCount()).toBe(0);` → AFTER `    expect(secondSpy.fetchCount()).toBe(1);`

**P2 self-check**
- `git diff --stat` → 10 files under `ai-platform/test/`.
- `rg -n "crypto.randomUUID\(\)|randomUuid\(\)" ai-platform/test/e2e/harness/clinic.ts` → only inside `visitContextFor`.
- `rg -c "waitForSettledRequest" ai-platform/test/system` → harness.ts 2+, admission-settlement 3, cron 2, quota 4, settlement-integrity 5 (import + call sites).
- `rg -n "fetchCount\(\)\).toBe\(0\)" ai-platform/test/admission-credit.test.ts` → no hit inside `admission_repeated_key_no_second_inference` (other tests may keep theirs).

**Commit:** `ai-platform tests: deterministic replay bodies, fresh-token replay, poll for settlement`

---

### P3 — abo: apply the fingerprint migration in the cross-worker harness

The harness applies a hand-maintained list of ai-platform migrations to the platform D1. The ai-platform invoke path now writes `request_fingerprint` → `no such column` → all invoke-dependent cross-worker tests fail, and the step sequence stops before P4.2-03 runs.

**P3.1 `abo/test/system/cross-worker-harness.ts`**
BEFORE (line ~50):
```ts
import dropPlanEntitlementSql from "../../../ai-platform/migrations/20261006170100_drop_plan_entitlement.sql?raw";
```
AFTER:
```ts
import dropPlanEntitlementSql from "../../../ai-platform/migrations/20261006170100_drop_plan_entitlement.sql?raw";
import idempotencyFingerprintSql from "../../../ai-platform/migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
```
BEFORE (line ~74, end of the platform migration list):
```ts
  dropInvoicingSql,
  dropPlanEntitlementSql,
];
```
AFTER:
```ts
  dropInvoicingSql,
  dropPlanEntitlementSql,
  idempotencyFingerprintSql,
];
```

**P3 self-check**
- `git diff --stat` → 1 file, +2 lines.
- `rg -c "idempotencyFingerprintSql" abo/test/system/cross-worker-harness.ts` → `2`.

**Commit:** `abo cross-worker harness: apply ai_request idempotency fingerprint migration`

---

### P4 — CI wiring: per-area installs, tools, env, timeouts

Fixes the vendor-contracts bundle failure (E2E-P2.2-08), the e2e-fullstack/frontend-fullstack "module not found" failures, and gives the frontend boundary step a profile + psql. YAML BEFORE snippets are given by **key path**; keep existing indentation.

**P4.1 `.github/scripts/setup-campaign-area.sh` — `case "${area}"` branches**

| Branch | BEFORE (body) | AFTER (body) |
|---|---|---|
| `frontend)` | `need_supabase=1` + `need_flutter=1` | add a line `npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)` after `need_flutter=1` |
| `e2e-fullstack)` | `need_supabase=1` + `npm_dirs+=(packages/vendor-contracts e2e/fullstack)` | `need_supabase=1` + `need_flutter=1` + `npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)` |
| `vendor-contracts)` | `npm_dirs+=(packages/vendor-contracts)` | `npm_dirs+=(packages/vendor-contracts ai-platform)` |

All other branches unchanged. Use the indentation of the surrounding lines.

**P4.2 same file — Dart helper package for e2e-fullstack.** Inside the existing flutter block:
BEFORE:
```bash
  (cd "${repo_root}/frontend" && flutter pub get)
fi
```
AFTER:
```bash
  (cd "${repo_root}/frontend" && flutter pub get)
  if [[ "${area}" == "e2e-fullstack" ]]; then
    (cd "${repo_root}/e2e/fullstack/dart" && flutter pub get)
  fi
fi
```

**P4.3 same file — frontend deployment profile** (agent D F2). Insert directly **before** the line `echo "Campaign area ${area} ready."` (i.e. after the supabase-start block closes):
```bash
if [[ "${area}" == "frontend" ]]; then
  echo "Writing frontend local deployment profile..."
  anon_key=""
  api_url=""
  if status_env="$(cd "${repo_root}/backend" && supabase status -o env 2>/dev/null)"; then
    anon_key="$(printf '%s\n' "${status_env}" | sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -n 1)"
    api_url="$(printf '%s\n' "${status_env}" | sed -n 's/^API_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -n 1)"
  fi
  anon_key="${anon_key:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0}"
  api_url="${api_url:-http://127.0.0.1:54321}"
  mkdir -p "${repo_root}/frontend/config/local"
  cat > "${repo_root}/frontend/config/local/deployment-profile.json" <<EOF
{
  "deployment_mode": "local",
  "supabase_url": "${api_url}",
  "supabase_anon_key": "${anon_key}"
}
EOF
fi

```
(The heredoc terminator `EOF` must start at column 0.)

**P4.4 `.github/workflows/ci.yml`**
1. Job-level `env:` block — BEFORE:
```yaml
      CI: "true"
      CAMPAIGN_AREA: ${{ matrix.area }}
```
AFTER (same indentation):
```yaml
      CI: "true"
      CAMPAIGN_AREA: ${{ matrix.area }}
      HFS_RESET_SUPABASE: ${{ matrix.area == 'e2e-fullstack' && '1' || '0' }}
      HFS_PLATFORM_BIND_HOST: ${{ matrix.area == 'e2e-fullstack' && '0.0.0.0' || '127.0.0.1' }}
```
2. Matrix entry `area: frontend`: `timeout_minutes: 90` → `120`; its postgresql-client flag (`postgresql_client` / psql key, currently `false`) → `true`.
3. Matrix entry `area: e2e-fullstack`: `timeout_minutes: 45` → `110`; `flutter: false` → `true`.
4. The postgresql-client install step — BEFORE `run: sudo apt-get update && sudo apt-get install -y postgresql-client` → AFTER `run: sudo apt-get update && sudo apt-get install -y postgresql-client sqlite3`.
5. Do **not** change `on.push.branches` (the `"!ai/abo-master"` exclusion stays; CI is dispatched manually, §7).

**P4.5 `.github/workflows/manual-campaign.yml`** (parity with ci.yml)
1. `timeout-minutes: 90` → `timeout-minutes: 120`.
2. Flutter setup step — BEFORE `if: inputs.area == 'frontend'` → AFTER `if: contains(fromJSON('["frontend", "e2e-fullstack"]'), inputs.area)`.
3. postgresql-client step — BEFORE `if: contains(fromJSON('["backend", "e2e-fullstack"]'), inputs.area)` → AFTER `if: contains(fromJSON('["frontend", "backend", "e2e-fullstack"]'), inputs.area)`; and its `apt-get install -y postgresql-client` → `apt-get install -y postgresql-client sqlite3`.
4. Job `env:` — after the `CAMPAIGN_SUBCAMPAIGN:` line add:
```yaml
      HFS_RESET_SUPABASE: ${{ inputs.area == 'e2e-fullstack' && '1' || '0' }}
      HFS_PLATFORM_BIND_HOST: ${{ inputs.area == 'e2e-fullstack' && '0.0.0.0' || '127.0.0.1' }}
```

**P4 self-check**
- `bash -n .github/scripts/setup-campaign-area.sh` → no output.
- `python -c "import yaml,sys; [yaml.safe_load(open(p)) for p in ('.github/workflows/ci.yml','.github/workflows/manual-campaign.yml')]"` → no error (skip if PyYAML missing; then eyeball indentation in `git diff`).
- `rg -n "HFS_RESET_SUPABASE|HFS_PLATFORM_BIND_HOST" .github/workflows` → 4 hits.
- `git diff --stat` → 3 files.

**Commit:** `ci: install cross-package deps per area, flutter/psql for fullstack paths, fullstack env and timeouts`

---

### P5 — Re-apply e1a42092 hunks 1–7 (revert of cb99ded0, minus the harness test file)

Mechanical; no hand edits. Re-applies: base64url-safe PG JWT JSON for billing tokens (new migration `20261014170000_canonical_billing_jwt_json.sql` + `backend/tests/issuer_rpc.sql`), ABO `GET /v1/checkouts` 404 JSON body (`abo/src/worker.ts`), `atob`-based decoding in `packages/vendor-contracts/src/token-claims.ts`, compilable `e2e/fullstack/dart/bin/session_jwt_capture.dart`, and the e2e-fullstack harness rework in `p7-2-stack.mjs`, `p7-2-untrusted-callers.test.mjs`, `wrangler-persist.mjs` (pinned wrangler CLI, `--var`, Host header, idempotent org creation, direct-SQLite D1 writes with WAL checkpoint).

**P5.1 Commands** (repo root, clean tree):
```bash
git revert --no-commit cb99ded0
git checkout HEAD -- test/harness/test_campaign_live_stats.py
git status --short
```
Expected `git status --short` (exactly these 8 entries, order may differ):
```
M  abo/src/worker.ts
A  backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql
M  backend/tests/issuer_rpc.sql
M  e2e/fullstack/dart/bin/session_jwt_capture.dart
M  e2e/fullstack/test/p7-2-stack.mjs
M  e2e/fullstack/test/p7-2-untrusted-callers.test.mjs
M  e2e/fullstack/test/wrangler-persist.mjs
M  packages/vendor-contracts/src/token-claims.ts
```
If `git revert` reports a conflict, or `test/harness/test_campaign_live_stats.py` still shows as modified, **STOP and report** (expected: no conflict, because `git diff cb99ded0 HEAD -- <these paths>` is empty).

**P5 self-check**
- `git diff --stat e1a42092^ e1a42092 -- . ':!test/harness/test_campaign_live_stats.py'` matches `git diff --cached --stat` (same 8 files, same line counts).
- `node --check e2e/fullstack/test/p7-2-stack.mjs && node --check e2e/fullstack/test/wrangler-persist.mjs && node --check e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` → no output.
- `rg -n "Buffer\." packages/vendor-contracts/src/token-claims.ts` → no hit.

**Commit** (use `git commit`, not `git revert --continue`, so the message is ours):
```
Re-apply e1a42092 hunks 1-7 (revert cb99ded0, keep test_campaign_live_stats.py)

e1a42092 was reverted because CI still failed, not because it caused
regressions. The remaining failures it did not cover are fixed in the
following commits.
```

---

### P6 — Siblings e1a42092 missed: `receipt.ts` Buffer, feed-token JCS, local GoTrue rate limits

**P6.1 `packages/vendor-contracts/src/receipt.ts`** (`payloadBytesFromJws`, line ~135). Under workerd without `nodejs_compat`, `Buffer` throws inside the try → `null` → abo parks grant/reversal work as `receipt_unverified`.
BEFORE:
```ts
  try {
    return Uint8Array.from(Buffer.from(padded, "base64"));
  } catch {
    return null;
  }
```
AFTER:
```ts
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
```

**P6.2 New file `backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql`** (must sort after `20261014170000_canonical_billing_jwt_json.sql` from P5, whose helper it uses). Full content, LF line endings:
```sql
-- Re-emit the internal feed token with RFC 8785 canonical header/payload bytes
-- so ai-platform validateTokenClaims byte-equality accepts it.

CREATE OR REPLACE FUNCTION auth_internal.issue_feed_token()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, vault, auth_internal
AS $$
DECLARE
  v_signing_key ai_internal.issuer_key%ROWTYPE;
  v_secret_key bytea;
  v_jti uuid;
  v_iat bigint;
  v_exp bigint;
  v_header_text text;
  v_payload_text text;
  v_header_b64 text;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_token text;
BEGIN
  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.issuer_key ik
  WHERE ik.status = 'signing'
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ISSUER_KEY_NOT_CONFIGURED';
  END IF;

  SELECT decode(ds.decrypted_secret, 'base64')
  INTO v_secret_key
  FROM vault.decrypted_secrets ds
  WHERE ds.id = v_signing_key.secret_ref;

  IF v_secret_key IS NULL THEN
    RAISE EXCEPTION 'ISSUER_KEY_NOT_CONFIGURED';
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + 120;

  v_header_text := auth_internal.canonical_issuer_jwt_json(jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid,
    'typ', 'JWT'
  ));

  v_payload_text := auth_internal.canonical_issuer_jwt_json(jsonb_build_object(
    'iss', auth_internal.ai_app_setting_text('ai.issuer_id', 'issuer-test'),
    'aud', 'ai-platform-feed',
    'sub', 'backend-feed',
    'jti', v_jti::text,
    'iat', v_iat,
    'exp', v_exp,
    'ver', '2'
  ));

  v_header_b64 := auth_internal.base64url_encode(convert_to(v_header_text, 'utf8'));
  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload_text, 'utf8'));
  v_signing_input := v_header_b64 || '.' || v_payload_b64;

  v_signature := pgsodium.crypto_sign_detached(
    convert_to(v_signing_input, 'utf8'),
    v_secret_key
  );

  RETURN v_signing_input || '.' || auth_internal.base64url_encode(v_signature);
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.issue_feed_token() FROM PUBLIC, anon, authenticated, service_role;
```
Before writing it, compare against the HEAD definition in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` (~lines 1334–1406): the only intended difference is the two `auth_internal.canonical_issuer_jwt_json(...)` wrappers replacing `jsonb_build_object(...)::text`. If anything else differs (search_path, DECLARE list, `ai_app_setting_text` call), **copy the HEAD body and change only those two lines**.

**P6.3 `backend/supabase/config.toml`** — section `[auth.rate_limit]` (local dev/CI stack only; the fullstack suites sign in/refresh far more than 30 per 5 min per IP):
- `token_refresh = 150` → `token_refresh = 100000`
- `sign_in_sign_ups = 30` → `sign_in_sign_ups = 100000`
- `token_verifications = 30` → `token_verifications = 100000`

Leave every other key (including any comment lines) unchanged.

**P6 self-check**
- `rg -n "Buffer" packages/vendor-contracts/src` → no hit.
- `rg -n "::text" backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql` → only `v_jti::text`.
- `rg -n "= 100000" backend/supabase/config.toml` → 3 hits, all under `[auth.rate_limit]`.
- `git diff --stat` + `git status --short` → 2 modified, 1 new file.

**Commit:** `Fix receipt base64 decoding in workerd, canonical feed-token JSON, raise local auth rate limits`

---

### P7 — e2e-fullstack harness: stack scripts, runner isolation, timeouts, variant tomls

All paths relative to `e2e/fullstack/` unless stated. BEFORE snippets for `test/wrangler-persist.mjs` and `test/p7-2-stack.mjs` are the **post-P5** content. Every other file is at HEAD content. P7 is written in two parts below (P7.1–P7.4, then P7.5–P7.12); both parts form **one** commit.

**P7.1 `test/wrangler-persist.mjs`** (post-P5)
1. Export the pinned CLI path. BEFORE: `const WRANGLER_CLI = path.join(` → AFTER: `export const WRANGLER_CLI = path.join(`
2. Directly after the line `export const PAYMOB_PERSIST = path.join(FULLSTACK_ROOT, ".wrangler/paymob");` add:
```js
export const PLATFORM_BIND_HOST = process.env.HFS_PLATFORM_BIND_HOST ?? "127.0.0.1";
```
3. `execPlatformD1Sql` — BEFORE:
```js
export function execPlatformD1Sql(sql) {
  const db = new DatabaseSync(platformD1DatabaseFile());
  try {
    db.exec(sql);
```
AFTER:
```js
export function execPlatformD1Sql(sql) {
  const db = new DatabaseSync(platformD1DatabaseFile());
  try {
    db.exec("PRAGMA busy_timeout = 5000");
    db.exec(sql);
```

**P7.2 `test/p5-1.test.mjs`** (HEAD)
1. Imports (line ~24). BEFORE:
```js
  runWranglerSync,
  wranglerLocalEnv,
} from "./wrangler-persist.mjs";
```
AFTER:
```js
  runWranglerSync,
  wranglerLocalEnv,
  WRANGLER_CLI,
  PLATFORM_BIND_HOST,
} from "./wrangler-persist.mjs";
```
2. `waitForHttp`, `spawnDevProcess`, `stopChild` (lines ~79–119). BEFORE (whole block):
```js
async function waitForHttp(url, { timeoutMs = 120_000, accept = [200] } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
```
AFTER:
```js
async function waitForHttp(url, { timeoutMs = 120_000, accept = [200], headers = {} } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { headers });
```
BEFORE:
```js
function spawnDevProcess(args, env = {}) {
  const child = spawn("npx", ["wrangler", ...args], {
    cwd: REPO_ROOT,
    env: wranglerLocalEnv(env),
    stdio: ["ignore", "pipe", "pipe"],
  });
  return child;
}

async function stopChild(child) {
  if (!child || child.killed) {
    return;
  }
  child.kill("SIGTERM");
  await new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      resolve();
    }, 5_000);
    child.on("exit", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}
```
AFTER (`stopChild` copied verbatim from HEAD `test/p7-3-stack.mjs` lines 233–286):
```js
function spawnDevProcess(args, env = {}) {
  const child = spawn(process.execPath, [WRANGLER_CLI, ...args], {
    cwd: REPO_ROOT,
    env: wranglerLocalEnv(env),
    stdio: ["ignore", "pipe", "pipe"],
    detached: process.platform !== "win32",
  });
  return child;
}

async function stopChild(child) {
  if (!child) return;

  if (process.platform === "win32" || !child.pid) {
    if (child.exitCode !== null || child.signalCode !== null) return;
    child.kill("SIGTERM");
    await new Promise((resolve) => {
      const timer = setTimeout(() => {
        child.kill("SIGKILL");
        resolve();
      }, 5_000);
      child.once("exit", () => {
        clearTimeout(timer);
        resolve();
      });
    });
    return;
  }

  const signalGroup = (signal) => {
    try {
      process.kill(-child.pid, signal);
      return true;
    } catch (error) {
      if (error.code === "ESRCH") return false;
      throw error;
    }
  };
  const groupExists = () => {
    try {
      process.kill(-child.pid, 0);
      return true;
    } catch (error) {
      if (error.code === "ESRCH") return false;
      throw error;
    }
  };
  const waitForGroupExit = async (timeoutMs) => {
    const deadline = Date.now() + timeoutMs;
    while (groupExists() && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return !groupExists();
  };

  // The Wrangler leader may already have exited while workerd descendants
  // remain in this dedicated process group, so signal the group regardless.
  if (!signalGroup("SIGTERM")) return;
  if (await waitForGroupExit(5_000)) return;
  signalGroup("SIGKILL");
  if (!(await waitForGroupExit(1_000))) {
    throw new Error(`Process group ${child.pid} did not exit after SIGKILL`);
  }
}
```
3. Platform worker bind (line ~457, the `startWorker` with `config: PLATFORM_CONFIG`). BEFORE: `      server: { hostname: "127.0.0.1", port: 8787 },` → AFTER: `      server: { hostname: PLATFORM_BIND_HOST, port: 8787 },` (only the port-8787 line; leave the harness 8790 line).
4. Initial ABO spawn (line ~520). BEFORE:
```js
      "--persist-to",
      ABO_PERSIST,
    ],
    {
      PAYMOB_BASE_URL: PAYMOB_URL,
      ISSUER_KEYS: JSON.stringify(issuerKeys),
    },
  );
  await waitForHttp(`${ABO_URL}/v1/offers`, {
    accept: [401, 403, 400],
  });
```
AFTER:
```js
      "--persist-to",
      ABO_PERSIST,
      "--var",
      `PAYMOB_BASE_URL:${PAYMOB_URL}`,
      "--var",
      `ISSUER_KEYS:${JSON.stringify(issuerKeys)}`,
    ],
  );
  await waitForHttp(`${ABO_URL}/v1/offers`, {
    accept: [401, 403, 400],
    headers: { Host: BILLING_HOST },
  });
```
5. `stop()` (line ~548). BEFORE:
```js
      await stopChild(paymob);
      await stopChild(abo);
```
AFTER:
```js
      await stopChild(paymob);
      await stopChild(stackRef.abo);
```
6. `restartAbo` spawn (line ~570). BEFORE:
```js
          "--persist-to",
          ABO_PERSIST,
        ],
        {
          PAYMOB_BASE_URL: PAYMOB_URL,
          ISSUER_KEYS: JSON.stringify(nextIssuerKeys),
        },
      );
      await waitForHttp(`${ABO_URL}/v1/offers`, {
        accept: [401, 403, 400],
      });
```
AFTER:
```js
          "--persist-to",
          ABO_PERSIST,
          "--var",
          `PAYMOB_BASE_URL:${PAYMOB_URL}`,
          "--var",
          `ISSUER_KEYS:${JSON.stringify(nextIssuerKeys)}`,
        ],
      );
      await waitForHttp(`${ABO_URL}/v1/offers`, {
        accept: [401, 403, 400],
        headers: { Host: BILLING_HOST },
      });
```

**P7.3 `test/p5-2.test.mjs`** (HEAD)
1. Line 9. BEFORE: `import { getPlatformProxy, unstable_startWorker as startWorker } from "wrangler";` → AFTER: `import { unstable_startWorker as startWorker } from "wrangler";`
2. Line 15: delete the whole line `import { VendorEntrypoint } from "../../../ai-platform/src/vendor/entrypoint.ts";` (it pulls `cloudflare:workers` into Node).
3. Imports from `./wrangler-persist.mjs`: same edit as P7.2 step 1 (add `  WRANGLER_CLI,` and `  PLATFORM_BIND_HOST,` before `} from "./wrangler-persist.mjs";`).
4. Line ~107: delete the line `let platformVendorProxy = null;`.
5. `waitForHttp` / `spawnDevProcess` / `stopChild` (lines ~129–169): identical BEFORE/AFTER to P7.2 step 2.
6. Platform bind (line ~473): same as P7.2 step 3.
7. Initial ABO spawn (line ~537). BEFORE:
```js
      "--persist-to",
      ABO_PERSIST,
    ],
    {
      PAYMOB_BASE_URL: PAYMOB_URL,
      ISSUER_KEYS: JSON.stringify(issuerKeys),
      ABO_GRANT_KEY: JSON.stringify(ABO_GRANT_KEY),
      PLATFORM_PUBLIC_KEYS: JSON.stringify(PLATFORM_PUBLIC_KEYS),
    },
  );
  await waitForHttp(`${ABO_URL}/v1/offers`, {
    accept: [401, 403, 400],
  });
```
AFTER:
```js
      "--persist-to",
      ABO_PERSIST,
      "--var",
      `PAYMOB_BASE_URL:${PAYMOB_URL}`,
      "--var",
      `ISSUER_KEYS:${JSON.stringify(issuerKeys)}`,
      "--var",
      `ABO_GRANT_KEY:${JSON.stringify(ABO_GRANT_KEY)}`,
      "--var",
      `PLATFORM_PUBLIC_KEYS:${JSON.stringify(PLATFORM_PUBLIC_KEYS)}`,
    ],
  );
  await waitForHttp(`${ABO_URL}/v1/offers`, {
    accept: [401, 403, 400],
    headers: { Host: BILLING_HOST },
  });
```
8. `stop()` (line ~565): same as P7.2 step 5.
9. `restartAbo` (line ~586): same shape as step 7 with `nextIssuerKeys` and 10/8-space indentation. BEFORE:
```js
          "--persist-to",
          ABO_PERSIST,
        ],
        {
          PAYMOB_BASE_URL: PAYMOB_URL,
          ISSUER_KEYS: JSON.stringify(nextIssuerKeys),
          ABO_GRANT_KEY: JSON.stringify(ABO_GRANT_KEY),
          PLATFORM_PUBLIC_KEYS: JSON.stringify(PLATFORM_PUBLIC_KEYS),
        },
      );
      await waitForHttp(`${ABO_URL}/v1/offers`, {
        accept: [401, 403, 400],
      });
```
AFTER:
```js
          "--persist-to",
          ABO_PERSIST,
          "--var",
          `PAYMOB_BASE_URL:${PAYMOB_URL}`,
          "--var",
          `ISSUER_KEYS:${JSON.stringify(nextIssuerKeys)}`,
          "--var",
          `ABO_GRANT_KEY:${JSON.stringify(ABO_GRANT_KEY)}`,
          "--var",
          `PLATFORM_PUBLIC_KEYS:${JSON.stringify(PLATFORM_PUBLIC_KEYS)}`,
        ],
      );
      await waitForHttp(`${ABO_URL}/v1/offers`, {
        accept: [401, 403, 400],
        headers: { Host: BILLING_HOST },
      });
```
10. `runPlatformD1Command` (line ~845). BEFORE:
```js
function runPlatformD1Command(sql) {
  runWrangler([
    "d1",
    "execute",
    "ai-platform-development",
    "--local",
    "--env",
    "development",
    "--config",
    PLATFORM_CONFIG,
    "--persist-to",
    PLATFORM_PERSIST,
    "--command",
    sql,
  ]);
}
```
AFTER:
```js
function runPlatformD1Command(sql) {
  execPlatformD1Sql(sql);
}
```
11. `callFeedConsumerHealth` (line ~952). BEFORE:
```js
async function callFeedConsumerHealth() {
  if (!platformVendorProxy) {
    platformVendorProxy = await getPlatformProxy({
      configPath: PLATFORM_CONFIG,
      environment: "development",
      persist: { path: PLATFORM_PERSIST },
    });
  }
  const entrypoint = new VendorEntrypoint(
    platformVendorProxy.ctx,
    platformVendorProxy.env,
  );
  return await entrypoint.feedConsumerHealth({
    contract_version: 1,
  });
}
```
AFTER:
```js
async function callFeedConsumerHealth() {
  const response = await fetch(`${HARNESS_URL}/vendor-call`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      method: "feedConsumerHealth",
      args: { contract_version: 1 },
    }),
  });
  assert.equal(response.status, 200, "harness /vendor-call feedConsumerHealth");
  return await response.json();
}
```
12. `stopSupabase` / `startSupabase` (line ~1206): BEFORE `spawnSync("npx", ["supabase", "stop"], {` → AFTER `spawnSync("supabase", ["stop"], {`; BEFORE `spawnSync("npx", ["supabase", "start"], {` → AFTER `spawnSync("supabase", ["start"], {`.
13. `after()` (line ~1265). BEFORE:
```js
after(async () => {
  await platformVendorProxy?.dispose();
  platformVendorProxy = null;
  await stack?.stop();
```
AFTER:
```js
after(async () => {
  await stack?.stop();
```
14. Leave `insertGrantAppliedEvent` (line ~651) unchanged (W7). If `runWrangler` becomes unused after step 10, leave its definition in place (still used by `insertGrantAppliedEvent` and migrations).

**P7.4 `src/register-issuer.ts`**
1. BEFORE (line 1–2):
```ts
const VENDOR_CALL_METHODS = new Set([
  "grant",
```
AFTER:
```ts
const VENDOR_CALL_METHODS = new Set([
  "feedConsumerHealth",
  "grant",
```
2. BEFORE (line ~22): `    grant(args: VendorCallArgs): Promise<unknown>;` → AFTER:
```ts
    feedConsumerHealth(args: VendorCallArgs): Promise<unknown>;
    grant(args: VendorCallArgs): Promise<unknown>;
```

**P7.5 `test/p7-2-stack.mjs`** (post-P5; already has pinned CLI, `--var`, Host header, idempotent org creation)
1. In the `import { ... } from "./wrangler-persist.mjs";` block add `  PLATFORM_BIND_HOST,` as the last named import (directly above `} from "./wrangler-persist.mjs";`).
2. Platform worker bind (the `startWorker` with `config: PLATFORM_CONFIG`, line ~754). BEFORE: `      server: { hostname: "127.0.0.1", port: 8787 },` → AFTER: `      server: { hostname: PLATFORM_BIND_HOST, port: 8787 },`. If the line occurs more than once, change only the port-8787 occurrence(s) that belong to the platform admission worker.

**P7.6 `test/p7-3-stack.mjs`** (HEAD)
1. Imports (line ~24). BEFORE:
```js
  runWranglerSync,
  wranglerLocalEnv,
} from "./wrangler-persist.mjs";
```
AFTER:
```js
  runWranglerSync,
  wranglerLocalEnv,
  WRANGLER_CLI,
  PLATFORM_BIND_HOST,
} from "./wrangler-persist.mjs";
```
2. `spawnDevProcess` (line ~222). BEFORE: `  const child = spawn("npx", ["wrangler", ...args], {` → AFTER: `  const child = spawn(process.execPath, [WRANGLER_CLI, ...args], {` (keep the existing `detached` and log capture lines).
3. Org helpers. Directly **above** the line `function seedStaffMembership(orgId, username, role) {` insert (copied from post-P5 `p7-2-stack.mjs`):
```js
function findTestOrganizationId(orgName) {
  return psqlQuery(
    `SELECT id FROM public.organizations
     WHERE name = ${sqlLiteral(orgName)} AND is_deleted = false
     LIMIT 1`,
  );
}

function insertTestOrganization(orgName) {
  const adminUserId = psqlQuery(
    "SELECT id FROM auth.users WHERE email = 'admin' LIMIT 1",
  );
  if (!adminUserId) {
    throw new Error("Cannot seed a test organization without the bootstrap admin user");
  }
  return psqlQuery(
    `WITH inserted AS (
       INSERT INTO public.organizations (
         name, currency_code, timezone, settings_json, created_by, updated_by
       ) VALUES (
         ${sqlLiteral(orgName)}, 'EGP', 'UTC', '{}'::jsonb,
         ${sqlLiteral(adminUserId)}::uuid, ${sqlLiteral(adminUserId)}::uuid
       ) RETURNING id
     )
     SELECT id FROM inserted`,
  );
}

function findTestBranchId(orgId, branchCode) {
  return psqlQuery(
    `SELECT id FROM public.branches
     WHERE organization_id = ${sqlLiteral(orgId)}::uuid
       AND code = ${sqlLiteral(branchCode)}
       AND is_deleted = false
     LIMIT 1`,
  );
}

```
   (`psqlQuery` and `sqlLiteral` already exist in this file. If `sqlLiteral` does not exist, **STOP and report**.)
4. `createOrgClinic` (line ~616). BEFORE:
```js
  const bootstrap = await signIn("admin", "admin");

  const orgResult = await rpc(bootstrap, "bootstrap_create_organization", {
    p_name: orgName,
    p_settings_json: {},
    p_currency_code: "EGP",
    p_timezone: "UTC",
  });
  if (!orgResult?.success) {
    throw new Error(`bootstrap_create_organization failed for ${prefix}`);
  }
  const orgId = orgResult.data.organization_id;
  await bootstrap.auth.refreshSession();

  const branchResult = await rpc(bootstrap, "bootstrap_create_branch", {
    p_organization_id: orgId,
    p_name: branchName,
    p_code: branchCode,
  });
  if (!branchResult?.success) {
    throw new Error(`bootstrap_create_branch failed for ${prefix}`);
  }
  const branchId = branchResult.data.branch_id;
  await bootstrap.auth.refreshSession();
```
AFTER:
```js
  const bootstrap = await signIn("admin", "admin");

  let orgId = findTestOrganizationId(orgName);
  if (!orgId) {
    const orgResult = await rpc(bootstrap, "bootstrap_create_organization", {
      p_name: orgName,
      p_settings_json: {},
      p_currency_code: "EGP",
      p_timezone: "UTC",
    });
    if (orgResult?.success) {
      orgId = orgResult.data.organization_id;
    } else if (orgResult?.error_code === "ORG_ALREADY_EXISTS") {
      // Bootstrap is intentionally single-organization per installation. The
      // cross-tenant E2E fixture needs a second organization, so seed it through
      // the privileged local test database connection.
      orgId = insertTestOrganization(orgName);
    } else {
      throw new Error(
        `bootstrap_create_organization failed for ${prefix}: ${orgResult?.error_code ?? "unknown"} ${orgResult?.error_message ?? ""}`,
      );
    }
  }

  let branchId = findTestBranchId(orgId, branchCode);
  if (!branchId) {
    const branchResult = await rpc(bootstrap, "bootstrap_create_branch", {
      p_organization_id: orgId,
      p_name: branchName,
      p_code: branchCode,
    });
    if (!branchResult?.success) {
      throw new Error(
        `bootstrap_create_branch failed for ${prefix}: ${branchResult?.error_code ?? "unknown"} ${branchResult?.error_message ?? ""}`,
      );
    }
    branchId = branchResult.data.branch_id;
  }

  const activeOrganization = await rpc(
    bootstrap,
    "set_active_organization",
    { p_organization_id: orgId },
  );
  if (!activeOrganization?.success) {
    throw new Error(
      `set_active_organization failed for ${prefix}: ${activeOrganization?.error_code ?? "unknown"}`,
    );
  }
  await bootstrap.auth.refreshSession();
```
5. `spawnAboProcess` (line ~698). BEFORE:
```js
      "--persist-to",
      ABO_PERSIST,
      "--test-scheduled",
    ],
    {
      PAYMOB_BASE_URL: PAYMOB_URL,
      ISSUER_KEYS: JSON.stringify(issuerKeys),
      ABO_GRANT_KEY: JSON.stringify(ABO_GRANT_KEY),
      PLATFORM_PUBLIC_KEYS: JSON.stringify(PLATFORM_PUBLIC_KEYS),
    },
  );
}
```
AFTER:
```js
      "--persist-to",
      ABO_PERSIST,
      "--var",
      `PAYMOB_BASE_URL:${PAYMOB_URL}`,
      "--var",
      `ISSUER_KEYS:${JSON.stringify(issuerKeys)}`,
      "--var",
      `ABO_GRANT_KEY:${JSON.stringify(ABO_GRANT_KEY)}`,
      "--var",
      `PLATFORM_PUBLIC_KEYS:${JSON.stringify(PLATFORM_PUBLIC_KEYS)}`,
      "--test-scheduled",
    ],
  );
}
```
6. `startPlatformAdmissionWorker` (line ~745). BEFORE: `      server: { hostname: "127.0.0.1", port: 8787 },` → AFTER: `      server: { hostname: PLATFORM_BIND_HOST, port: 8787 },`
7. New export directly **after** the closing `}` of `export function ensurePlatformGrantPrerequisites(orgId, installationId) {` (line ~1148; i.e. directly above `export async function putBillingContact(billingToken) {`):
```js
export function seedPlatformGrantGlobals() {
  runPlatformD1Command(`
    INSERT OR REPLACE INTO service_key (
      kid, service, public_key, status, not_before, not_after,
      registered_by, assertion_sha256
    ) VALUES (
      ${sqlLiteral(ABO_GRANT_KEY.kid)},
      'abo',
      ${sqlLiteral(ABO_GRANT_KEY.public_key)},
      'active',
      '2020-01-01T00:00:00.000Z',
      '2099-01-01T00:00:00.000Z',
      ${sqlLiteral(OPERATOR_EMAIL)},
      'harness'
    );
    INSERT OR IGNORE INTO plan_version (
      plan_id, version, display_name, capabilities, max_cost_class,
      concurrency_limit, max_allowance_per_month, status, published_by,
      assertion_sha256
    ) VALUES (
      '${PLAN_ID}', ${PLAN_VERSION}, 'Clinic Pro',
      ${sqlLiteral(JSON.stringify([CAPABILITY_ID]))},
      '2', 4, ${ALLOWANCE_CREDITS}, 'published',
      ${sqlLiteral(OPERATOR_EMAIL)}, 'harness'
    );
  `);
}

```

**P7.7 `test/hfl-run-flutter.mjs`** (frontend/fullstack wrapper; seeds the ABO offer catalogue and platform grant globals the Dart billing tests need)
1. Imports (line 7). BEFORE:
```js
import {
  ABO_URL,
  HARNESS_URL,
  PAYMOB_URL,
  PLATFORM_URL,
  startStack,
  SUPABASE_URL,
} from "./p7-3-stack.mjs";
```
AFTER:
```js
import {
  ABO_URL,
  HARNESS_URL,
  PAYMOB_URL,
  PLATFORM_URL,
  seedAboOffers,
  seedPlatformGrantGlobals,
  startStack,
  SUPABASE_URL,
} from "./p7-3-stack.mjs";
```
2. Main (line ~239). BEFORE:
```js
      if (requestedSignal) {
        exitCode = SIGNAL_EXIT_CODES[requestedSignal];
      } else {
        exitCode = await runFlutter(commandArgs[0], commandArgs.slice(1));
      }
```
AFTER:
```js
      if (requestedSignal) {
        exitCode = SIGNAL_EXIT_CODES[requestedSignal];
      } else {
        await seedAboOffers();
        seedPlatformGrantGlobals();
        exitCode = await runFlutter(commandArgs[0], commandArgs.slice(1));
      }
```
(`await` is harmless if `seedAboOffers` is synchronous.)

**P7.8 `test/p7-3-06-prepare.mjs`** (line ~154). BEFORE:
```js
  stack = await startStack({
    aboConfig: ABO_DESKTOP_CONFIG,
    platformConfig: PLATFORM_DESKTOP_CONFIG,
  });
```
AFTER:
```js
  stack = await startStack({
    aboConfig: ABO_DESKTOP_CONFIG,
    platformConfig: PLATFORM_DESKTOP_CONFIG,
    createClinics: false,
  });
```

**P7.9 `run_campaigns.py`** (one `node --test` process per file; ports + `.wrangler` reset before each; optional Supabase reset)
1. Imports. BEFORE:
```python
from __future__ import annotations

import sys
from pathlib import Path
```
AFTER:
```python
from __future__ import annotations

import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
```
2. Directly after the line `TEST_DIR = E2E_ROOT / "test"` add:
```python
_SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
_SUPABASE_ANON_KEY = os.environ.get(
    "SUPABASE_ANON_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
)
```
3. Replace the whole `_run_node_steps` function (lines ~65–81). BEFORE:
```python
def _run_node_steps(subcampaign: str, steps: list[tuple[str, list[str]]]) -> int:
    config = load_campaign_config(AREA, subcampaign)
    exit_code = 0
    log_dir = _log_dir(subcampaign)
    for name, files in steps:
        _prepare_fullstack_stack_ports()
        cmd = apply_campaign_args(_node_cmd(files), config)
```
AFTER:
```python
def _supabase_endpoint_ready(path: str) -> bool:
    try:
        request = urllib.request.Request(
            f"{_SUPABASE_URL}{path}", headers={"apikey": _SUPABASE_ANON_KEY}
        )
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status == 200
    except OSError:
        return False


def _reset_supabase_between_files() -> bool:
    if os.environ.get("HFS_RESET_SUPABASE") != "1":
        return True
    result = subprocess.run(["supabase", "db", "reset", "--local"], cwd=REPO_ROOT / "backend")
    if result.returncode != 0:
        print("error: supabase db reset failed", file=sys.stderr)
        return False
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        if _supabase_endpoint_ready("/auth/v1/health") and _supabase_endpoint_ready("/rest/v1/"):
            return True
        time.sleep(1)
    print("error: Supabase did not become ready after db reset", file=sys.stderr)
    return False


def _per_file_steps(files: list[str]) -> list[tuple[str, list[str]]]:
    return [(Path(f).name.removesuffix(".test.mjs"), [f]) for f in files]


def _run_node_steps(subcampaign: str, steps: list[tuple[str, list[str]]]) -> int:
    if not steps:
        print(f"error: no test files for {subcampaign}", file=sys.stderr)
        return 1
    config = load_campaign_config(AREA, subcampaign)
    exit_code = 0
    log_dir = _log_dir(subcampaign)
    for name, files in steps:
        _prepare_fullstack_stack_ports()
        if not _reset_supabase_between_files():
            exit_code = max(exit_code, 1)
            continue
        cmd = apply_campaign_args(_node_cmd(files), config)
```
(The rest of `_run_node_steps` — the `run_subprocess_sequence` call and `exit_code = max(...)` — stays unchanged.)
4. BEFORE:
```python
def run_p7_3(_: str) -> int:
    files = _node_test_files("p7-3*.test.mjs")
    return _run_node_tests("p7-3", files)


def run_p7_2(_: str) -> int:
    files = _node_test_files("p7-2*.test.mjs")
    return _run_node_tests("p7-2", files)
```
AFTER:
```python
def run_p7_3(_: str) -> int:
    return _run_node_steps("p7-3", _per_file_steps(_node_test_files("p7-3*.test.mjs")))


def run_p7_2(_: str) -> int:
    return _run_node_steps("p7-2", _per_file_steps(_node_test_files("p7-2*.test.mjs")))
```
5. BEFORE:
```python
def run_all_manual(_: str) -> int:
    files = _node_test_files("*.test.mjs")
    return _run_node_tests("all-manual", files)
```
AFTER:
```python
def run_all_manual(_: str) -> int:
    return _run_node_steps("all-manual", _per_file_steps(_node_test_files("*.test.mjs")))
```
(`run_all_ci` and the p5 runners are unchanged; all-ci already runs one step per file.)

**P7.10 `campaigns/*.json`** — in `all-ci.json`, `all-manual.json`, `p5-1.json`, `p5-2.json`, `p7-2.json`, `p7-3.json`: `"test_timeout_ms": 180000` → `"test_timeout_ms": 360000`. Leave `p5-2b.json` at 180000. No other key changes.

**P7.11 Variant tomls** under `test/variant/` (`wrangler d1 migrations apply` otherwise looks for `migrations/` next to the toml). In each file, directly after the single line `database_id = "11111111-1111-1111-1111-111111111111"` add one line:
- `platform-n-plus-1.toml`, `platform-feed-window.toml`, `platform-worker-n.toml`, `platform-do-receiver.toml`: `migrations_dir = "../../../../ai-platform/migrations"`
- `abo-n-plus-1.toml`: `migrations_dir = "../../../../abo/migrations"`

Before saving, confirm the relative path resolves: from `e2e/fullstack/test/variant/`, `../../../../ai-platform/migrations` must be the repo's `ai-platform/migrations` (it is: 4 levels up = repo root). If the tomls are not in `test/variant/`, recompute the `../` depth so it reaches the repo root.

**P7.12 `test/harness/local_dev_ports.py`** (repo-root `test/`; recognises a platform bound to `0.0.0.0` so stale workers are killed). In `pids_listening_on_tcp_port`, BEFORE:
```python
    needle = f"{host}:{port}"
```
AFTER:
```python
    needles = (f"{host}:{port}", f"0.0.0.0:{port}", f"*:{port}", f"[::]:{port}")
```
and BEFORE:
```python
        if needle not in line:
```
AFTER:
```python
        if not any(needle in line for needle in needles):
```

**P7 self-check**
- `node --check` on: `e2e/fullstack/test/wrangler-persist.mjs`, `p5-1.test.mjs`, `p5-2.test.mjs`, `p7-2-stack.mjs`, `p7-3-stack.mjs`, `hfl-run-flutter.mjs`, `p7-3-06-prepare.mjs` → no output.
- `python -m py_compile e2e/fullstack/run_campaigns.py test/harness/local_dev_ports.py` → no output (use `py -3` on Windows if `python` is missing).
- `rg -n '"npx"' e2e/fullstack/test/p5-1.test.mjs e2e/fullstack/test/p5-2.test.mjs e2e/fullstack/test/p7-3-stack.mjs` → no hit.
- `rg -n "getPlatformProxy|VendorEntrypoint|platformVendorProxy" e2e/fullstack/test/p5-2.test.mjs` → no hit.
- `rg -n "PAYMOB_BASE_URL: PAYMOB_URL" e2e/fullstack/test` → no hit.
- `rg -n "hostname: \"127.0.0.1\", port: 8787" e2e/fullstack/test` → no hit in p5-1, p5-2, p7-2-stack, p7-3-stack.
- `rg -c "migrations_dir" e2e/fullstack/test/variant` → 5 files, 1 each.
- `rg -n "180000" e2e/fullstack/campaigns` → only `p5-2b.json`.
- `git diff --stat` → ~19 files.

**Commit:** `e2e-fullstack: per-file isolation, pinned wrangler + --var, Host-header waits, idempotent orgs, 0.0.0.0 platform bind, variant migrations_dir`

---

### P8 — frontend/all: keep fullstack tests out of unit, make the boundary step run in CI

All paths relative to `frontend/`.

**P8.1 `tool/discover_tests.py`** (line ~157). BEFORE:
```python
def unit_test_files(cwd: Path) -> list[str]:
    return discover_test_files(cwd, *UNIT_TEST_ROOTS)
```
AFTER:
```python
def unit_test_files(cwd: Path) -> list[str]:
    fullstack = set(fullstack_test_files(cwd))
    return [
        path
        for path in discover_test_files(cwd, *UNIT_TEST_ROOTS)
        if path not in fullstack
    ]
```
(`fullstack_test_files` is defined later in the module; it is resolved at call time.)

**P8.2 `tool/run_unit_tests.py`** (line ~45). BEFORE:
```python
            "flutter",
            "test",
            *test_files,
            "--machine",
        ],
```
AFTER:
```python
            "flutter",
            "test",
            *test_files,
            "--machine",
            "--exclude-tags",
            "fullstack",
        ],
```

**P8.3 `tool/run_boundary_tests.py`**
1. Imports — directly after the line `import sys` add:
```python
import urllib.error
import urllib.request
```
2. `ensure_stack_running` (line ~48): accept the Supabase CLI stack. BEFORE:
```python
def ensure_stack_running():
    result = subprocess.run(
        ["docker", "compose", "-f", str(COMPOSE_FILE), "ps", "--status", "running"],
```
AFTER:
```python
def _supabase_http_ready() -> bool:
    url = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321").rstrip("/") + "/rest/v1/"
    try:
        urllib.request.urlopen(url, timeout=3)
        return True
    except urllib.error.HTTPError as error:
        return error.code < 500
    except (urllib.error.URLError, OSError):
        return False


def ensure_stack_running():
    if _supabase_http_ready():
        return
    result = subprocess.run(
        ["docker", "compose", "-f", str(COMPOSE_FILE), "ps", "--status", "running"],
```
(Rest of the function unchanged.)
3. `run_tests` env (line ~102). BEFORE:
```python
    env = {
        **os.environ,
        "AICLINIC_BOUNDARY_INTEGRATION": "1",
        "AICLINIC_DEPLOYMENT_PROFILE_PATH": "config/local/deployment-profile.json",
    }
```
AFTER:
```python
    env = {
        **os.environ,
        "AICLINIC_BOUNDARY_INTEGRATION": "1",
        "AICLINIC_DEPLOYMENT_PROFILE_PATH": "config/local/deployment-profile.json",
    }
    if os.environ.get("CI"):
        env.setdefault("AICLINIC_BOUNDARY_REQUIRE_LIVE", "1")
```

**P8.4 `test/boundary/harness/live_supabase_harness.dart`** (line ~116; the only `Skip` site in `frontend/test`). In CI a missing stack/profile must fail loudly instead of skipping. BEFORE:
```dart
void markTestSkipped(String message) {
  throw Skip(message);
}
```
AFTER:
```dart
void markTestSkipped(String message) {
  if (Platform.environment['AICLINIC_BOUNDARY_REQUIRE_LIVE'] == '1') {
    throw StateError('Live Supabase stack required (AICLINIC_BOUNDARY_REQUIRE_LIVE=1): $message');
  }
  throw Skip(message);
}
```
(`dart:io` is already imported at line 1. If it is not, **STOP and report**.)

**P8 self-check**
- `python -m py_compile frontend/tool/discover_tests.py frontend/tool/run_unit_tests.py frontend/tool/run_boundary_tests.py` → no output.
- `cd frontend && python -c "import sys; sys.path.insert(0,'tool'); import discover_tests as d; from pathlib import Path; u=set(d.unit_test_files(Path('.'))); f=set(d.fullstack_test_files(Path('.'))); print(len(u), len(f), len(u & f))"` → last number `0`, middle number `5` (the five `*fullstack*_test.dart` files).
- `git diff --stat` → 4 files.

**Commit:** `frontend: exclude fullstack-tagged tests from unit, run boundary against the Supabase CLI stack, fail instead of skip in CI`

---

### P9 — frontend/fullstack: runner wiring, P6.3 test fixes, governor Flutter-hook attribution

**P9.1 `frontend/tool/run_campaigns.py`**
1. Directly after the line `import json` add `import os` (keep `import sys` etc. as they are).
2. Directly after the closing `)` of the `from harness.common import (` block add:
```python
from harness.local_dev_ports import prepare_fullstack_e2e_stack  # noqa: E402
```
3. Directly after the line starting `BOUNDARY_RUNNER = ` add:
```python
SELF_MANAGED_STACK_FILES = frozenset(
    {"test/integration/contract_version_matrix_fullstack_test.dart"}
)
```
4. Replace the **whole** function `def _run_fullstack(` (line ~146 up to, not including, the next top-level `def`) with:
```python
def _run_fullstack(_subcampaign: str) -> int:
    run_id = resolve_governor_run_id()
    log_dir = resolve_campaign_log_dir(AREA, "fullstack", run_id)
    config = load_campaign_config(AREA, "fullstack")
    test_files = fullstack_test_files(FRONTEND_ROOT)
    if not test_files:
        print(
            "ERROR: no fullstack integration test files found under "
            f"{FULLSTACK_INTEGRATION_DIR}.",
            file=sys.stderr,
        )
        return 1
    stack_runner = FRONTEND_ROOT.parent / "e2e/fullstack/test/hfl-run-flutter.mjs"
    tsx_loader = (
        FRONTEND_ROOT.parent / "e2e/fullstack/node_modules/tsx/dist/loader.mjs"
    )
    if not tsx_loader.is_file():
        print(
            "ERROR: H-FS stack dependencies are missing. Run `npm ci` in "
            "e2e/fullstack/ before the frontend fullstack campaign.",
            file=sys.stderr,
        )
        return 1

    os.environ.setdefault("AICLINIC_BOUNDARY_INTEGRATION", "1")
    os.environ.setdefault(
        "AICLINIC_DEPLOYMENT_PROFILE_PATH", "config/local/deployment-profile.json"
    )
    if os.environ.get("CI"):
        os.environ.setdefault("AICLINIC_BOUNDARY_REQUIRE_LIVE", "1")
    prepare_fullstack_e2e_stack()

    def flutter_cmd(files: list[str]) -> list[str]:
        return apply_campaign_args(
            [
                "flutter",
                "test",
                *files,
                "--tags",
                "fullstack",
                "--timeout",
                "6m",
                "--machine",
            ],
            config,
        )

    shared_stack = [f for f in test_files if f not in SELF_MANAGED_STACK_FILES]
    self_managed = [f for f in test_files if f in SELF_MANAGED_STACK_FILES]
    steps: list[tuple[str, list[str]]] = []
    if shared_stack:
        steps.append(
            (
                "hfs-shared-stack",
                [
                    "node",
                    "--import",
                    str(tsx_loader),
                    str(stack_runner),
                    "--",
                    *flutter_cmd(shared_stack),
                ],
            )
        )
    if self_managed:
        steps.append(("hfs-self-managed-stack", flutter_cmd(self_managed)))

    return run_subprocess_sequence(
        steps,
        FRONTEND_ROOT,
        log_dir,
        status_label=_status_label("fullstack"),
        campaign_config=config,
        config_area=AREA,
        continue_on_step_failure=True,
    )
```
   Names it relies on, all already in the module at HEAD: `AREA`, `FRONTEND_ROOT`, `FULLSTACK_INTEGRATION_DIR`, `fullstack_test_files`, `apply_campaign_args`, `load_campaign_config`, `resolve_campaign_log_dir`, `resolve_governor_run_id`, `run_subprocess_sequence`, `_status_label`. If any of them is missing, or `fullstack_test_files` returns paths that are not `test/integration/<name>.dart`, **STOP and report**. If `run_subprocess_sequence` rejects `continue_on_step_failure`, STOP and report.
   If the old `_run_fullstack` checked the loader path differently (e.g. a different `tsx` path), keep the **old** path string in `tsx_loader`.

**P9.2 `frontend/test/integration/administrator_billing_fullstack_test.dart`**
1. E2E-P6.3-01 final assertion (user decision U2), line ~190. BEFORE:
```dart
      expect(data['available'], isTrue);
      expect(data['state'], 'active');

      await _expectAiRequestSucceeds(composition);
    });
```
AFTER:
```dart
      expect(data['available'], isTrue);
      expect(data['state'], 'active');

      final aat = await LiveSupabaseHarness.client.rpc(
        'issue_ai_token',
        params: {'p_contract_version': backendRpc},
      );
      expect(aat, isA<String>(), reason: 'AAT mint should succeed after billing completes');
      expect((aat as String).split('.'), hasLength(3));
    });
```
   (If this BEFORE matches more than once, use the occurrence inside the test whose title starts with `E2E-P6.3-01`.)
2. Keep the helper, silence the unused warning. BEFORE (line ~694): `Future<void> _expectAiRequestSucceeds(` → AFTER:
```dart
// ignore: unused_element
Future<void> _expectAiRequestSucceeds(
```
3. Agent D F10 helper — insert directly **above** the top-level function declaration of `_seedEndsSoonCoverage` (search `Future<void> _seedEndsSoonCoverage(`):
```dart
Future<void> _seedPlatformTenantBinding({required String orgId, required String installationId}) async {
  final repoRoot = File('pubspec.yaml').existsSync() ? Directory.current.parent.path : Directory.current.path;
  final dbDir = Directory('$repoRoot/e2e/fullstack/.wrangler/platform/v3/d1/miniflare-D1DatabaseObject');
  final files = dbDir.existsSync()
      ? (dbDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sqlite') && !f.path.endsWith('metadata.sqlite'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  if (files.isEmpty) {
    fail('Local platform D1 database not found under e2e/fullstack/.wrangler/platform');
  }
  final now = DateTime.now().toUtc().toIso8601String();
  final sql = '''
INSERT OR IGNORE INTO installation (installation_id, org_id, status, display_name, region, enrolled_at)
VALUES ('$installationId', '$orgId', 'active', '', '', '$now');
INSERT OR REPLACE INTO tenant_binding (org_id, installation_id, epoch, status, retired_at, reason, created_at)
VALUES ('$orgId', '$installationId', 1, 'active', NULL, NULL, '$now');
''';
  final result = await Process.run('sqlite3', [files.first.path, sql]);
  if (result.exitCode != 0) {
    fail('platform sqlite3 seed failed: ${result.stderr}');
  }
}

```
   (`dart:io` must be imported in this file for `File`/`Directory`/`Process`; it is used by the existing `sqlite3` helpers. If it is not imported, add `import 'dart:io';` as the first import.)
4. F10 call sites — in **E2E-P6.3-01, E2E-P6.3-02 and E2E-P6.3-05** only: directly after that test's `await _seedEndsSoonCoverage(...);` statement (P6.3-01: line ~119–123), add one statement that passes **the same** org id and installation id expressions that the `_seedEndsSoonCoverage` call passes as `orgId:` / `installationId:`. For P6.3-01 that is:
```dart
      await _seedPlatformTenantBinding(orgId: clinic.organizationId, installationId: installationId);
```
   For P6.3-02 / P6.3-05 copy the argument expressions from their own `_seedEndsSoonCoverage(` call. If one of those tests has no `_seedEndsSoonCoverage(` call, **STOP and report**.

**P9.3 `test/harness/flutter_machine_labels.py`** (H1) — append at end of file:
```python


def flutter_pseudo_test_failure_label(test: dict, suite_path: str | None) -> str:
    """Label for a failed loading/hook pseudo-test, e.g. ``foo_test.dart (setUpAll)``."""
    name = (test.get("name") or "").strip()
    if is_loading_pseudo_test(test):
        loaded = name.split(" ", 1)[1] if " " in name else name
        return f"{Path(loaded).name} (loading)"
    suite_file = Path(suite_path).name if suite_path else _filename_from_url(test.get("url"))
    if suite_file:
        return f"{suite_file} {name}".strip()
    return name or "flutter hook"
```
(`Path`, `is_loading_pseudo_test`, `_filename_from_url` already exist in the module; if not, STOP and report.)

**P9.4 `test/harness/live_progress.py`** (H2) — class `FlutterMachineParser` (line ~1409)
1. `__init__`, BEFORE:
```python
        self._active: dict[int, str] = {}
        self._ignored_ids: set[int] = set()
```
AFTER:
```python
        self._active: dict[int, str] = {}
        self._ignored_ids: set[int] = set()
        self._pseudo: dict[int, str] = {}
        self._failed_pseudo: set[int] = set()
        self._suite_paths: dict[int, str] = {}
```
   (Use the occurrence inside `FlutterMachineParser.__init__`.)
2. Replace the whole method `def _handle_event(self, event: dict) -> None:` of `FlutterMachineParser` (lines ~1441–1502, up to the next method definition at the same indentation) with:
```python
    def _handle_event(self, event: dict) -> None:
        from harness.flutter_machine_labels import (
            flutter_pseudo_test_failure_label,
            flutter_test_label,
            is_flutter_hook_pseudo_test,
            is_loading_pseudo_test,
        )

        kind = event.get("type")
        if kind == "suite":
            suite = event.get("suite") or {}
            suite_id = suite.get("id")
            if suite_id is not None and suite.get("path"):
                self._suite_paths[int(suite_id)] = str(suite["path"])
            return
        if kind == "testStart":
            test = event.get("test") or {}
            test_id = test.get("id")
            if test_id is None:
                return
            tid = int(test_id)
            if is_loading_pseudo_test(test) or is_flutter_hook_pseudo_test(test):
                suite_id = test.get("suiteID")
                suite_path = (
                    self._suite_paths.get(int(suite_id)) if suite_id is not None else None
                )
                self._pseudo[tid] = flutter_pseudo_test_failure_label(test, suite_path)
                return
            label = flutter_test_label(test)
            if label is None:
                self._ignored_ids.add(tid)
                return
            self._active[tid] = label
            if self.log_session is not None:
                self.log_session.start_test(label)
            self.display.set_current(label)
        elif kind == "testDone":
            test_id = event.get("testID")
            if test_id is None:
                return
            tid = int(test_id)
            if tid in self._pseudo:
                label = self._pseudo.pop(tid)
                already_failed = tid in self._failed_pseudo
                self._failed_pseudo.discard(tid)
                result = event.get("result")
                if not already_failed and result not in (None, "success"):
                    self._record_failure(label, f"{label} finished with result {result}")
                return
            if event.get("hidden"):
                return
            if tid in self._ignored_ids:
                self._ignored_ids.discard(tid)
                return
            name = self._active.pop(tid, None)
            if name is None:
                return
            result = event.get("result")
            status = "PASS" if result == "success" else "FAIL"
            self.display.add_finished(name, status)
            if self.log_session is not None:
                self.log_session.end_test(name, status=status)
        elif kind == "error":
            test_id = event.get("testID")
            tid = int(test_id) if test_id is not None else None
            name: str | None = None
            if tid is not None and tid in self._pseudo:
                if tid in self._failed_pseudo:
                    return
                self._failed_pseudo.add(tid)
                name = self._pseudo[tid]
            elif tid is not None and tid in self._active:
                name = self._active.pop(tid, None)
            if name is None:
                name = self.display.current
                if name in ("(starting…)", "starting…", "Interrupted"):
                    name = "flutter test error"
            err = (event.get("error") or "flutter test error").strip()
            self._record_failure(name, err, stack_trace=event.get("stackTrace"))

    def _record_failure(
        self, name: str, err: str, *, stack_trace: object = None
    ) -> None:
        if self.log_session is not None:
            if not self.log_session.has_active():
                self.log_session.start_test(name)
            if stack_trace:
                self.log_session.append_line(str(stack_trace))
            self.log_session.append_line(err)
            self.log_session.end_test(name, status="FAIL", error=err)
        self.display.add_finished(name, "FAIL")
```
   Before replacing, compare the HEAD `error` branch with the AFTER: the AFTER's fallback (`display.current` / `"flutter test error"`) and the `log_session` calls (`has_active`, `start_test`, `append_line`, `end_test(..., error=...)`) must be the ones HEAD uses. If HEAD uses different method names, keep HEAD's calls inside `_record_failure` and **report it** in the PR description. If `FlutterMachineParser` already defines `_record_failure`, STOP and report.

**P9.5 `test/harness/test_flutter_machine_parser.py`** (H3) — append at end of file (`json`, `FlutterMachineParser`, `CampaignProgressDisplay` are already imported by the existing tests; if `json` is not, add `import json` to the imports):
```python


def _feed(parser: FlutterMachineParser, event: dict) -> None:
    parser.feed(json.dumps(event) + "\n")


def test_setup_all_error_is_attributed_to_suite_file() -> None:
    display = CampaignProgressDisplay("[frontend/fullstack]")
    parser = FlutterMachineParser(display)
    _feed(parser, {"type": "suite", "suite": {"id": 0, "platform": "vm", "path": "/proj/test/integration/foo_fullstack_test.dart"}})
    _feed(parser, {"type": "testStart", "test": {"id": 3, "name": "(setUpAll)", "suiteID": 0}})
    _feed(parser, {"type": "error", "testID": 3, "error": "Bad state: prepare exited 1"})
    _feed(parser, {"type": "testDone", "testID": 3, "result": "error", "hidden": False})
    assert display.failed == 1
    assert display.passed == 0
    assert display.current == "foo_fullstack_test.dart (setUpAll)"


def test_passing_setup_all_is_not_counted() -> None:
    display = CampaignProgressDisplay("[frontend/fullstack]")
    parser = FlutterMachineParser(display)
    _feed(parser, {"type": "suite", "suite": {"id": 0, "path": "/proj/a_test.dart"}})
    _feed(parser, {"type": "testStart", "test": {"id": 1, "name": "(setUpAll)", "suiteID": 0}})
    _feed(parser, {"type": "testDone", "testID": 1, "result": "success", "hidden": True})
    assert display.failed == 0
    assert display.passed == 0


def test_loading_failure_is_attributed_to_file() -> None:
    display = CampaignProgressDisplay("[frontend/unit]")
    parser = FlutterMachineParser(display)
    _feed(parser, {"type": "testStart", "test": {"id": 1, "name": "loading /proj/test/broken_test.dart", "suiteID": 0}})
    _feed(parser, {"type": "error", "testID": 1, "error": "Compilation failed"})
    _feed(parser, {"type": "testDone", "testID": 1, "result": "error", "hidden": False})
    assert display.failed == 1
    assert display.current == "broken_test.dart (loading)"
```
If a helper named `_feed` already exists in the file, do not add a second one; reuse it if its signature matches, otherwise STOP and report.

**P9 self-check**
- `python -m py_compile frontend/tool/run_campaigns.py test/harness/flutter_machine_labels.py test/harness/live_progress.py test/harness/test_flutter_machine_parser.py` → no output.
- `rg -n "_expectAiRequestSucceeds\(composition\)" frontend/test/integration/administrator_billing_fullstack_test.dart` → no hit.
- `rg -c "_seedPlatformTenantBinding" frontend/test/integration/administrator_billing_fullstack_test.dart` → `4` (1 definition + 3 calls).
- `rg -n "continue_on_step_failure=True|\"6m\"|SELF_MANAGED_STACK_FILES" frontend/tool/run_campaigns.py` → hits for all three.
- Optional, developer-only (not CI): `python -m pytest test/harness/test_flutter_machine_parser.py test/harness/test_runner_crash.py` with `test/` on `sys.path`, if pytest is available. Not required.
- `git diff --stat` → 5 files.

**Commit:** `frontend fullstack: machine output, isolated P7.3-06 step, P6.3 tenant binding + narrowed P6.3-01, attribute Flutter hook failures`

---

## 5. Traceability matrix

Every FAIL / NOT_RECORDED entry of run 38695681551, grouped by file, plus the suites that run for the first time after this plan. "Expect" = expected status on the first CI run after P1–P9.

### 5.1 ai-platform/npm-test (81 FAIL + 10 NR) and ai-platform/load (10 NR)

| File (count) | Tests | Root cause | Fixed by | Expect |
|---|---|---|---|---|
| `test/admission-credit.test.ts` (18) | admission_exactly_one_do_fetch_per_request; admission_expired_token_same_key_unauthenticated; admission_missing_entitlement_fail_closed; admission_rejection_counted_not_journaled ×4 (concurrency_limited, repeated jti, allowance_exhausted, fallback-cap); exactly_two_durable_object_round_trips_per_request; fallback_reconcile_drains_pending_rows ×2; grace_cap_refusal_distinct_from_quota_exhausted; grace_durable_cap_across_isolate_maps; grace_idempotency_key_replay_during_do_outage; grace_rejects_when_ledger_quota_exhausted ×2; guard_rejection_debits_nothing_and_writes_no_journal_row; quota_do_unavailable_capped_grace_then_rejection | `no such column: request_fingerprint` | P1.1 | PASS |
| ↳ same file | admission_repeated_key_no_second_inference | migration + replay contract (fingerprint + DO jti check → 1 fetch) | P1.1 + P2.10 | PASS |
| `test/cohort-activate-promote.test.ts` (1) | T-J3-05 journal_records_serving_version_under_cohort_split | missing migration | P1.6 | PASS |
| `test/conversational-journaling.test.ts` (9) | context_requested_leg_credited…; conversation_id_and_turn_ordinal_written_per_leg; each_leg_admitted_and_credited_independently; no_conversation_table…; no_second_r2_object…; one_indexed_query…; platform_held_no_state_between_legs; run_guard_writes_conversational_grouping_from_body; single_shot_unaffected_by_h3 | missing migration | P1.2 | PASS |
| `test/manifest.test.ts` (1) | T-A4-15 manifest_is_data_not_code | new export `hashCanonicalJson` | P1.9 | PASS |
| `test/migrations.test.ts` (2) | T-A5-13 schema_snapshot_matches; schema_snapshot_matches | snapshot column position | P1.8 | PASS |
| `test/pipeline.test.ts` (8) | pipeline_compose_stream_flag; pipeline_soft_threshold_exposes_degraded_routing_tier; pipeline_stage_failures ×5 (stage 10 compose, stage 8 duplicate key, stage 8 quota, stage 9 D1 insert, stage 9 prompt hash); pipeline_transcript_threading | missing migration | P1.3 | PASS |
| `test/soft-threshold-routing.test.ts` (10) | below_threshold…; hard_exhaustion…; quota_exhausted_only…; soft_threshold_cost_dimension…; …just_below_boundary…; …no_second_quota_do_round_trip; …persists_routing_tier; …selects_degraded_target; …token_dimension…; …zero_never_degrades | missing migration | P1.4 | PASS |
| `test/worker-request-orchestrator.test.ts` (24) | T1, T2, T3 (+raw body), T4, T15, T16 (+cancel usage), T17, T18, T20 (+empty chain), T21, T22, T23, 3× prose_safety_markers, completed cost agree, live grace routing tier, journals promptVersion hash, live soft threshold, routing_decision_persisted, usage_event_term_id | missing migration | P1.5 | PASS |
| `test/system/admission-settlement.system.test.ts` (2) | E2E-P3.4-01; E2E-P3.4-11 | settlement read early; same-jti replay 401 + body regenerated 409 | P2.2–P2.4 | PASS |
| `test/system/cron-retention-interplay.system.test.ts` (1) | SYS-8.1 | settlement read early | P2.3, P2.5 | PASS |
| `test/system/quota-admission-interplay.system.test.ts` (2) | SYS-5.5; SYS-5.6 | regenerated body 409 + settlement race | P2.2, P2.3, P2.6 | PASS |
| `test/system/settlement-integrity.system.test.ts` (3) | SYS-7.1; SYS-7.3; SYS-7.4 | settlement race (+ 409 for 7.4) | P2.2, P2.3, P2.7 | PASS |
| `test/load/load-and-cost.test.ts` (10 NR in npm-test, 10 NR in load) | d1_write_headroom_measured; do_throughput_per_installation_measured; exactly_one_r2_class_a_per_request_under_load; exactly_two_durable_object_requests_per_request_under_load; guard_p95_within_tens_of_ms_at_target_concurrency; load_suite_introduces_no_per_request_server_state; load_suite_joins_ci_permanently; no_prompt_provider_model_in_flutter_from_load_suite; no_second_quota_do_round_trip_beyond_two; no_second_r2_object_per_request | `beforeAll` crash (missing migration) | P1.7 | PASS (both campaigns; T19 double count) |

### 5.2 ai-platform/e2e (11 FAIL)

| File | Tests | Root cause | Fixed by | Expect |
|---|---|---|---|---|
| `stage-09-admission-journal-compose.test.ts` | S09-068, S09-069 | replay body regenerated → 409 | P2.1 | PASS |
| `stage-10-prose-guard-stream.test.ts` | S10-018, S10-019 | same | P2.1 | PASS |
| `stage-10-route-retry-idempotency.test.ts` | S10-001 | settlement race (`payload_pointer`) | P2.8 | PASS |
| ↳ same | S10-016 | 409 + settlement race | P2.1 + P2.8 | PASS |
| `stage-11-completed-failed-cancelled.test.ts` | S11-002, S11-010 | settlement race | P2.9 | PASS |
| `stage-11-replay-envelope-grace.test.ts` | S11-013, S11-014, S11-015 | replay body regenerated → 409 | P2.1 | PASS |

### 5.3 abo/cross-worker (4 FAIL + 1 NR)

| File | Test | Fixed by | Expect |
|---|---|---|---|
| `configuration-relays.cross-worker.test.ts` | E2E-P4.9-03, E2E-P4.9-05 | P3 | PASS |
| `console-relays.cross-worker.test.ts` | E2E-P4.8-07 | P3 | PASS |
| `grant.cross-worker.test.ts` | E2E-P4.4-01 | P3 | PASS |
| `checkout-throw.cross-worker.test.ts` | E2E-P4.2-03 (NR: sequence stopped) | P3 (step no longer fails) | PASS (recorded) |

### 5.4 vendor-contracts/all (1 FAIL)

| Test | Root cause | Fixed by | Expect |
|---|---|---|---|
| `bundle-scan.test.ts` E2E-P2.2-08 | `ai-platform/node_modules` (vendor-contracts link) not installed → bundle never builds | P4.1 (vendor-contracts npm_dirs) | PASS |

### 5.5 e2e-fullstack/all-ci (2 FAIL) and all-manual (12 FAIL, exit 130, 14 never ran)

| File / test | Root causes | Fixed by | Expect |
|---|---|---|---|
| `p5-1.test.mjs` (all-ci, all-manual) | ai-platform/abo not installed; ABO vars via env; no Host header; npx wrangler orphans; `stop()` leaks restarted ABO; `Buffer` in workerd; non-canonical billing JWT | P4, P5, P6.1, P7.1–P7.2 | PASS (likely) |
| `p5-2.test.mjs` (all-ci, all-manual) | as p5-1 + `cloudflare:workers` import into Node; non-canonical feed JWT; pg_net can't reach 127.0.0.1 platform; live-DB `wrangler d1 execute` | P4, P5, P6.1–P6.2, P7.1, P7.3, P7.4, W3 | PASS (medium; R2, R3) |
| E2E-P7.2-01..09 (`p7-2-credential-isolation`, `p7-2-untrusted-callers`, `p7-2-vendor-entrypoint`) | all files in parallel on one `.wrangler`/ports; ORG_ALREADY_EXISTS; Dart helper not compiling (P7.2-08); billing JWT; Supabase state leak | P5, P6, P7.5, P7.9 (per-file + reset) | PASS (likely) |
| E2E-P7.3-01 | variant toml migrations; feed JWT; `Buffer` in receipt; parallel run | P6, P7.6, P7.9, P7.11 | PASS (medium) |
| E2E-P7.3-02..05, -07 (never ran: exit 130) | same + ORG_ALREADY_EXISTS in p7-3-stack | P7.6, P7.9, P7.11 | first real run — mostly PASS expected |
| `p5-2b.test.mjs` (never ran in all-manual) | parallel run | P7.9 | first real run |

Pass criterion: all-ci 2/2 files; all-manual 12 files, **attempted == total** (T12).

### 5.6 frontend/all (12 FAIL) and frontend/fullstack (exit 1, 0 tests)

| Test(s) | Root cause | Fixed by | Expect |
|---|---|---|---|
| E2E-P6.3-01..07, E2E-P6.4-01..05 in frontend/all **unit** | fullstack-tagged files run without a stack | P8.1, P8.2 (moved to frontend/fullstack) | removed from unit; unit 0 FAIL |
| frontend/all **boundary** step (~170 tests, never ran) | docker-compose check, no profile, no psql | P4.1, P4.3, P4.4, P6.3, P8.3, P8.4 | **first real run** — some genuine failures possible (R1) |
| frontend/fullstack: E2E-P6.1-01 | Skip in setUpAll, misattributed | P4.3, P8.4, P9.1, P9.4 | PASS (medium) |
| frontend/fullstack: E2E-P6.3-01 | AI call to `ai.example.workers.dev` (test design) | U2 narrowing P9.2 + F10 | PASS (medium; R3) |
| frontend/fullstack: E2E-P6.3-02, -05 | no platform tenant binding for fresh org | P9.2 F10 + P7.7 seeds | PASS (medium; R3) |
| frontend/fullstack: E2E-P6.3-03, -04, -06, -07 | no offers/grant globals, rate limits, deps | P4, P6.3, P7.7 | PASS (medium) |
| frontend/fullstack: E2E-P6.4-01..05 | same + sqlite3 CLI | P4.4 (sqlite3), P7.7 | PASS (medium) |
| frontend/fullstack: E2E-P7.3-06 | port/persist clash with wrapper; ORG_ALREADY_EXISTS; tsx missing | P4.1, P7.8, P9.1 (own step) | PASS (medium) |

### 5.7 Green campaigns that must stay green

backend/all 73, backend/catalog 8 (new migrations P5/P6 + config.toml); abo/system 23, import-boundary 2, version-matrix 1; ai-platform/eval 24, eval-all 39, version-matrix 2; vendor-contracts other 10 (atob in token-claims/receipt); ops-launch 2; the 1375 npm-test and 525 e2e passes (P2 harness changes). See §6.

---

## 6. Shared-file / conflict matrix and regression argument

### 6.1 Files touched by more than one phase or consumed by more than one area

| File | Phases | Consumers (areas) | Conflict resolved / invariant kept |
|---|---|---|---|
| `e2e/fullstack/test/wrangler-persist.mjs` | P5 (revert), P7.1 | e2e-fullstack, frontend/fullstack (via p7-3-stack) | P7.1 is additive (`export`, new const, `busy_timeout`); default bind host stays `127.0.0.1`, so frontend is unchanged (W3, W8). |
| `e2e/fullstack/test/p7-2-stack.mjs` | P5, P7.5 | e2e-fullstack (P7.2) | P7.5 only swaps the platform bind host; org/wrangler logic is e1a42092's (W1, W4). |
| `e2e/fullstack/test/p7-3-stack.mjs` | P7.6 | e2e-fullstack (P7.3), frontend/fullstack (hfl wrapper, p7-3-06-prepare) | Idempotent `createOrgClinic` (W1); `seedPlatformGrantGlobals` is a new export, `ensurePlatformGrantPrerequisites` unchanged; `--var` replaces env (W5). Frontend path passes `createClinics:false` so no org code runs there. |
| `test/harness/local_dev_ports.py` | P7.12 | e2e-fullstack, frontend/fullstack (`prepare_fullstack_e2e_stack`) | Only widens the match (`0.0.0.0`, `*`, `[::]`); existing `127.0.0.1` match and `test_local_dev_ports.py` still hold. |
| `backend/supabase/config.toml` | P6.3 | backend, e2e-fullstack, frontend | Local-only; no test asserts GoTrue 429 (W9). |
| `backend/supabase/migrations/2026101417000{0,100}_*.sql` | P5, P6.2 | backend/all + catalog, e2e-fullstack, frontend | Ordered (feed after billing helper); bodies identical except serialization; re-REVOKE keeps `insufficient_privilege` expectations in `ai_keystore_rls.sql`. |
| `packages/vendor-contracts/src/token-claims.ts`, `receipt.ts` | P5, P6.1 | vendor-contracts, ai-platform, abo, e2e-fullstack | `atob` gives identical bytes for valid base64url; same pattern already used in `jws.ts`, ai-platform `worker.ts`, abo `rebuild.ts`. |
| `.github/scripts/setup-campaign-area.sh` | P4 | all CI jobs | Each `case` branch independent; profile block is frontend-only; Dart helper `pub get` is e2e-fullstack-only. |
| `.github/workflows/ci.yml`, `manual-campaign.yml` | P4 | all CI jobs | New env vars default to `0` / `127.0.0.1` for non-e2e-fullstack areas; apt adds a package only. |
| `ai-platform/test/system/harness.ts`, `test/e2e/harness/clinic.ts` | P2 | ai-platform npm-test (system), e2e | Memoised body only changes replays that were *meant* to be identical; first-call bodies are still valid; no test asserts distinct `visit_id` across calls of one installation (agent B). F1' is the fallback (R7). |
| `ai-platform/test/admission-credit.test.ts` | P1.1, P2.10 | npm-test | P1.1 touches imports/`beforeAll`; P2.10 touches helpers + one test. Disjoint hunks. |
| `frontend/tool/run_campaigns.py` vs `e2e/fullstack/run_campaigns.py` | P9.1, P7.9 | frontend vs e2e-fullstack | Supabase reset only in the e2e runner and only with `HFS_RESET_SUPABASE=1` (W2), which is `0` in the frontend job. |
| `test/harness/live_progress.py`, `flutter_machine_labels.py` | P9.3–P9.4 | every Flutter campaign | Normal-test PASS/FAIL accounting unchanged; only pseudo-test failures change (now attributed). |

### 6.2 Conflicts between agent reports and how they were resolved

| Conflict | Resolution |
|---|---|
| Shared migration loader (E T1) vs per-file imports (A) | Per-file (C1). A loader would break intentional subsets. |
| Fix replays by memoising bodies (B F1) vs excluding volatile context from the fingerprint (E T4 option 2) | F1 only (test-side); product fingerprint unchanged; 409 kept. |
| abo `continue_on_step_failure` (E T10/T16) vs C "skip" | Skip (W13). P4.2-03 recorded once P3 lands. |
| `test_concurrency: 1` (E T9) vs per-file processes (C F.1a) | Per-file processes + ports/`.wrangler` reset + Supabase reset (P7.9); concurrency stays `null`. |
| Frontend profile: D's hard-fail vs fallback demo key | Fallback to the documented local demo key (P4.3); a wrong key fails loudly via P8.4 anyway. |
| `createClinics:false` (D) vs idempotent org creation (F/e1a42092) | Both (W1): they cover different callers. |
| Re-apply e1a42092 per area (E T13) vs as a whole (F) | Whole hunks 1–7 in one commit (U3), siblings in P6; one commit keeps bisect simple; hunk 8 skipped. |
| p5 `runPlatformD1Command` vs `insertGrantAppliedEvent` | Only the former changed (W7); the latter is R8. |

### 6.3 Regression argument against agent E's traps

| Trap | How this plan handles it |
|---|---|
| T1 hand-maintained migration lists | Fingerprint migration added to all 8 hand-maintained lists that apply `ai_request` DDL (P1, P3). The intentional-subset files are untouched. |
| T2 snapshot column position | P1.8 places the column on the `turn_ordinal` line, exactly where SQLite emits it (matches the CI diff). |
| T3 manifest allowlist | Deliberately extended (C2); test-only. |
| T4 fingerprint vs random bodies | Test bodies made identical (P2.1–P2.2); product behaviour kept. |
| T5 replay-order ping-pong | No product order change; only tests aligned to HEAD's documented order (DO jti check → journal replay). P2.10 is the only expectation flip, and it matches HEAD's code path. |
| T6 denial-code churn | No codes renamed. |
| T7 CI ≠ local | P4 installs exactly what each area imports; first run is CI-dispatched (§7). |
| T8 alias ≠ install | No alias added; real installs instead. |
| T9 all-manual concurrency | One process per file (P7.9). |
| T10 step breaks hide tests | Root cause fixed (P3); frontend/fullstack uses `continue_on_step_failure=True` for its two steps (P9.1). |
| T11 file-level failures | Each NR group traced to one `beforeAll` (load) or one step (abo). |
| T12 node-test absences | Check `attempted == total` (§7). |
| T13 e1a42092 as a blob | Hunks 1–7 only; siblings `receipt.ts` + feed JCS added (P6). |
| T14 pool/miniflare skew | Not touched (no version bumps). |
| T15 edited historical migration | New forward migration for the feed token (P6.2); no historical file edited. |
| T16 `ai/reg-fixes` | Nothing taken from it. |
| T17 `retry: 1` masks flakes | §7 asks to check the vitest JSON for retried tests. |
| T18 variant tomls | `migrations_dir` added to all 5 (P7.11). |
| T19 double counting | load fixed once (P1.7), counted in two campaigns; p5-1/p5-2 run in all-ci and all-manual (W12). |
| T20 frontend unit runs fullstack tests | P8.1 + P8.2. |
| T21 `branchId` strictness | No caller changed; harness bodies keep their `branch` value. |

---

## 7. How to trigger CI and what to check

### 7.1 Trigger

Pushes to `ai/abo-master` do **not** start `ci.yml` (`"!ai/abo-master"` in `on.push.branches`). After the 9 commits:
```bash
git push origin ai/abo-master
gh workflow run ci.yml --ref ai/abo-master
gh run list --workflow ci.yml --branch ai/abo-master --limit 1
gh run watch <run-id>
```
Re-run a single area while iterating (same tool installs after P4.5):
```bash
gh workflow run manual-campaign.yml --ref ai/abo-master -f area=e2e-fullstack -f subcampaign=all-manual
gh workflow run manual-campaign.yml --ref ai/abo-master -f area=frontend -f subcampaign=fullstack
gh workflow run manual-campaign.yml --ref ai/abo-master -f area=ai-platform
```
Download artifacts: `gh run download <run-id> -D ci-art-<run-id>`.

### 7.2 What to check, per area

| Area / campaign | Pass criterion | Also check |
|---|---|---|
| ai-platform/npm-test | 0 FAIL, 0 NOT_RECORDED; ~1466 tests | `output.log` has no `no such column`; vitest JSON shows no test with `retryCount > 0` among the 8 system tests and S10/S11 (T17) |
| ai-platform/load | 10/10 PASS | — |
| ai-platform/e2e | 536/536 PASS | no 409 `idempotency_conflict` in S09/S10/S11 logs |
| ai-platform eval, eval-all, version-matrix | unchanged 24 / 39 / 2 | — |
| abo/cross-worker | 74 recorded (73 + P4.2-03), 0 FAIL | — |
| abo system / import-boundary / version-matrix | 23 / 2 / 1 | — |
| vendor-contracts/all | 11/11 | bundle-scan log shows the bundle was built |
| backend/all, backend/catalog | 73 / 8 | migrations `20261014170000` and `20261014170100` applied in `supabase start` log |
| e2e-fullstack/all-ci | 2/2 files PASS | per-file `db reset` lines present; no `EADDRINUSE` |
| e2e-fullstack/all-manual | 12 files, **attempted == total**, exit 0 (not 130) | no `_FATAL_WORKERD` crash-guard trip; no `ORG_ALREADY_EXISTS`; no `No migrations present`; p5-2 feed pull got 200 |
| frontend/all | unit 0 FAIL (P6.x absent); boundary ~170 tests attempted | boundary log does **not** say `backend/local stack is not running`; no `Live Supabase stack required` StateError (would mean profile/stack missing) |
| frontend/fullstack | 14 tests recorded across 2 steps (`hfs-shared-stack`, `hfs-self-managed-stack`) | no `H-FS stack dependencies are missing`; P7.3-06 setUpAll did not hit EADDRINUSE |
| ops-launch | 2/2 | — |
| Job wall time | frontend ≤ 120 min, e2e-fullstack ≤ 110 min | note actual minutes for tuning |

### 7.3 If something is red

1. Read the campaign `output.log` first, not the NR count (T11).
2. Map the failure to its phase via §5, fix inside that phase's files only, add a fixup commit with message `fixup(P<n>): <what>`.
3. Use the fallbacks in §8 before inventing new approaches.

---

## 8. Residual risks (ranked) and fallbacks

| # | Risk | Likelihood / impact | Fallback |
|---|---|---|---|
| R1 | **Boundary (~170) and frontend/fullstack (14) have never run green in CI.** Genuine product/test defects may surface once wiring works. | High / medium (frontend job red, others unaffected) | Triage per test; known pre-emptive knob: raise `_waitForPostgrestReady` attempts 20 → 80. Fix real defects in follow-up PRs; do not re-skip (P8.4 is deliberate). |
| R2 | **pg_net → platform on Linux** (`host.docker.internal` in the Supabase container) for E2E-P5.2-01 even with `0.0.0.0` bind. | Medium / P5.2-01 + P7.3-01 feed | Set `ai.platform_base_url` host to the docker bridge gateway `172.17.0.1` in the p5-2 setup, or add `--add-host` via Supabase config; verify with `docker exec supabase_db_* curl`. |
| R3 | **External SQLite writes into a live workerd D1** (`execPlatformD1Sql`, Dart F10 `sqlite3`, `insertGrantAppliedEvent` via wrangler) may be invisible or hit `SQLITE_BUSY`. | Medium / P5.2, P6.3 "Active", P7.3 | `busy_timeout` already added (P7.1). Next: route the writes through a harness worker endpoint (`e2e/fullstack/src/register-issuer.ts` → platform binding), as agent D suggested. |
| R4 | **Wall time / timeouts**: per-file Supabase reset (45–75 s × 14 files), cold wrangler bundles, Flutter compile. | Medium / exit by job timeout | Raise `test_timeout_ms` (P7.10) or job `timeout_minutes` (P4.4); as a last resort run all-ci and all-manual in separate dispatches (§7.1). |
| R5 | **wrangler 4.86 `--var` with JSON values** (colons, quotes) and crash-guard `_WORKERD_UNCAUGHT` false positives; boundary atexit reset wiping `ai_internal.app_settings` before frontend/fullstack runs. | Low–medium | `--var` is what e1a42092's p7-2-stack used locally; if it misparses, fall back to a generated `.dev.vars` file per spawn. For the app_settings wipe: run `supabase db reset` at the start of `_run_fullstack` (frontend runner) before `prepare_fullstack_e2e_stack()`. |
| R6 | P2.10 expectation (`fetchCount` 0 → 1) relies on HEAD's admission order (DO jti check before journal replay). | Low | If it fails with a different count, re-read `src/admission/index.ts` replay branch and align the single assertion; do not change src. |
| R7 | Memoised visit context (F1) collides with a test that expects two *different* requests from the same installation with default bodies (would now get 409). | Low (agent B checked) | F1': pass one explicit body through each replay test (`invoke(scenario, { body })`) and revert the memo. |
| R8 | `insertGrantAppliedEvent` in p5-2 still uses `wrangler d1 execute` on the live persist. | Low–medium / one p5-2 case | Switch it to `execPlatformD1Sql` like `runPlatformD1Command`. |
| R9 | `retry: 1` hides flakes in vitest areas (T17). | Low | Check retry counts (§7.2) before declaring success. |
| R10 | P9.4 parser rewrite diverges from HEAD's `log_session` API. | Low | Guarded by the compare-before-replace instruction in P9.4; developer-run pytest exists. |

### Tests still expected to possibly fail after the first run
- Some frontend **boundary** tests (never executed in CI before) — R1.
- frontend/fullstack **E2E-P6.3-01/-02/-05** if the external `sqlite3` tenant-binding write is not seen by workerd (R3); **E2E-P6.4-01..05** and **E2E-P7.3-06** (medium confidence, first execution).
- e2e-fullstack **E2E-P5.2-01** / p5-2 feed checks if pg_net cannot reach the platform on Linux (R2).
- Any campaign tripping the crash guard (`_FATAL_WORKERD`, exit 130) on a workerd uncaught log line (R5).

Everything else in §5 is expected to pass.

