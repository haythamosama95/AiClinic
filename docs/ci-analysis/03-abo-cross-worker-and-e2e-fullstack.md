# Agent C — abo/cross-worker + e2e-fullstack (run 38695681551, HEAD 953e5e6e)

Analysis only; no repo files were modified. Everything below was checked against the CI artifacts and the source at HEAD.

---

## A) abo/cross-worker — 4 FAIL + 1 NOT_RECORDED

### A.1 E2E-P4.9-03, E2E-P4.9-05, E2E-P4.8-07, E2E-P4.4-01: one root cause

**Decisive log lines** (`abo/cross-worker/output.log` lines 1625–1719):

```
FAIL test/system/configuration-relays.cross-worker.test.ts > ... > E2E-P4.9-03 ...
Error: D1_ERROR: no such column: request_fingerprint at offset 126: SQLITE_ERROR
 ❯ platformHttpInvoke test/system/configuration-relays.cross-worker.test.ts:1224:20
...
 ❯ platformHttpInvoke test/system/console-relays.cross-worker.test.ts:1219:20     (P4.8-07)
 ❯ platformHttpInvoke test/system/configuration-relays.cross-worker.test.ts:1224:20 (P4.9-05, via :1805)
 ❯ platformHttpInvoke test/system/grant.cross-worker.test.ts:907:20              (P4.4-01, via :1212)
Test Files  3 failed | 7 passed (10)
     Tests  4 failed | 69 passed (73)
```

**How abo builds the ai-platform D1 schema.**
- `abo/vitest.cross-worker.config.ts` boots the real platform bundle (`abo/.hxw-platform/worker.js`, built by `scripts/build-platform-for-hxw.mjs` from `ai-platform/src` at HEAD, so it contains the fingerprint code). That bundle runs as an auxiliary miniflare worker named `platform`. Its `DB` binding uses the same D1 id as the test's `PLATFORM_DB` (`22222222-…`).
- The schema comes from a **hand-picked list of `?raw` imports**. It does not use `readD1Migrations`, `schema.snap.sql`, or a glob. The list lives only in `abo/test/system/cross-worker-harness.ts:28-76` (`PLATFORM_MIGRATION_SQL`), and `applyPlatformMigrations()` at `:225-238` applies it. No other abo file imports `ai-platform/migrations` (I checked with rg across `abo/`).
- The list has 23 entries and ends at `20261006170100_drop_plan_entitlement.sql`. The directory has 24 files. The **only** one missing is `20261014120000_ai_request_idempotency_fingerprint.sql`, which was added in `771ceed7`. That commit updated `ai-platform/test/system/harness.ts` and `ai-platform/test/e2e/harness/d1.ts` but not the abo harness.
- The failing SQL is `selectAiRequestByKey` in `ai-platform/src/admission/index.ts:177-187` (`SELECT … capability_id, request_fingerprint FROM ai_request …`). Offset 126 lands on `request_fingerprint`. It runs at `runAdmission` `:636` on **every** `POST /v1/requests`, before any replay logic. Only tests that call `platformHttpInvoke` hit it, which is why exactly these 4 fail and the other 69 pass.

**Duplicate-column risk: none.** `applySqlOnDb` (`cross-worker-harness.ts:210-222`) already swallows both `/already exists/i` and `/duplicate column name/i`. `resetCrossWorkerHarness()` sets `platformMigrationsApplied = false` (`:920`), so the list is re-applied on every reset. A re-applied `ALTER TABLE ai_request ADD COLUMN request_fingerprint TEXT;` is silently tolerated, the same way the existing `routing_policy_canary` ALTER already is.

**Fix (exact edit). File: `abo/test/system/cross-worker-harness.ts`.**

Before (line 50):
```ts
import dropPlanEntitlementSql from "../../../ai-platform/migrations/20261006170100_drop_plan_entitlement.sql?raw";
```
After:
```ts
import dropPlanEntitlementSql from "../../../ai-platform/migrations/20261006170100_drop_plan_entitlement.sql?raw";
import idempotencyFingerprintSql from "../../../ai-platform/migrations/20261014120000_ai_request_idempotency_fingerprint.sql?raw";
```
Before (lines 74-76):
```ts
  dropInvoicingSql,
  dropPlanEntitlementSql,
];
```
After:
```ts
  dropInvoicingSql,
  dropPlanEntitlementSql,
  idempotencyFingerprintSql,
];
```
(This uses the same variable name as `ai-platform/test/system/harness.ts:89`.)

*Optional, to stop future drift. Not required, and carries a moderate risk.* Replace the 24 imports with
`import.meta.glob("../../../ai-platform/migrations/*.sql", { query: "?raw", import: "default", eager: true })` and sort the keys. I have **not** verified that `import.meta.glob` works under `@cloudflare/vitest-pool-workers@0.8.71`, which is abo's version. Do not do this in the same change as the minimal fix.

**Will the 4 tests pass once the column exists? Very likely yes. They do not replay.**
- All three `platformHttpInvoke` helpers send `"x-idempotency-key": crypto.randomUUID()`: `grant.cross-worker.test.ts:913`, `configuration-relays…:1230`, `console-relays…:1225`. I searched for other idempotency usage and found none.
- With a fresh key, `selectAiRequestByKey` returns null. Then `journaledBindingMatches` is false, no `journaledAnswer` is built, and no `journaledConflict` is set (`admission/index.ts:647-680`). So the new fingerprint/409 replay path in admission and quota-do is never entered. The 409-on-replay bug another agent is looking at does not affect these tests.
- `configuration-relays…:1006-1031` (`seedSupportLookupRequest`) inserts into `ai_request` with an explicit column list. The new nullable column does not affect it.
- The journal insert (`ai-platform/src/journal/index.ts:248`) writes `request_fingerprint`. That works once the column exists.

### A.2 E2E-P4.2-03 NOT_RECORDED: a harness consequence, not a test problem

- `abo/run_campaigns.py:82-83`: the `cross-worker` subcampaign runs 3 steps, `[build-platform, cross-worker-vitest, platform-throw-vitest]`, through `run_subprocess_sequence`.
- `test/harness/common.py:1079-1084`: if a step exits non-zero, and neither `campaign_resume_enabled()` nor `continue_on_step_failure` is set, the loop **breaks**. `cross-worker-vitest` exited 1, so `platform-throw-vitest` (`vitest.platform-throw.config.ts`, which includes only `checkout-throw.cross-worker.test.ts`) **never ran**. `output.log` has no `== platform-throw-vitest ==` banner; it ends at `[vpw:debug] Shutting down runtimes...` after the cross-worker run.
- The vitest reconciler then compared the result against the discovered test list. It marked the test `NOT_RECORDED` with `failure_kind: "infrastructure_error"`, `reconciled: true`, and `log_file: null` (summary.json; `campaign_infrastructure_error: true`).
- So it is not a crash, a timeout, or a skip. It is a test that was never executed. Fixing A.1 makes the step run.
- `checkout-throw` uses a platform **stub** (`test/stubs/platform-throw/worker.ts`) and plain `d1Databases: ["DB"]`. It applies no ai-platform migrations. It imports `cross-worker-harness.ts` only for Paymob helpers, so one more `?raw` import there is harmless.
- *Optional:* pass `continue_on_step_failure=True` in `run_cross_worker`, so `platform-throw` still reports when the main vitest fails. Skip this for now; it would also keep running steps after a build-platform failure.

### A.3 Cross-impact (abo/system, import-boundary, version-matrix)
- `cross-worker-harness.ts` is imported only by the 11 `*.cross-worker.test.ts` files (checked with rg).
- `abo/system` uses `vitest.workers.config.ts`, which includes only `test/system/**/*.system.test.ts`, with the platform-throw stub and abo's own `test/system/harness.ts` migrations. It never touches ai-platform migrations.
- `version-matrix` includes only `test/version-matrix/**`. `import-boundary` is a static scan.
- None of the three can be affected by A.1.
- `cross-worker-main` (child, not run in CI) uses the same config and gets the same fix.

**Confidence:** high (about 90%) that the 4 tests go green. If they still fail, it would be from some other 771ceed7 behaviour, such as a quota-do idempotency binding on first admission. I traced that code and saw no conflict for fresh keys.
**CI evidence that confirms it:** `cross-worker` shows `Tests 73 passed`, then a `== platform-throw-vitest ==` banner, and P4.2-03 reports PASS/FAIL instead of NOT_RECORDED.

---

## B) e2e-fullstack — all-ci (p5-1, p5-2 FAIL) and all-manual (12 FAIL, exit 130)

### B.1 p5-1 timeout: `vendor-contracts` cannot be resolved when bundling ai-platform

**Decisive log** (`all-ci/output.log` lines 102-378):
```
✘ [ERROR] Build failed with 12 errors:
✘ [ERROR] Could not resolve "vendor-contracts"
    src/quota-do/index.ts:1:32 … src/support/index.ts … src/vendor/entrypoint.ts:19:7 … src/worker.ts:6:7
[wrangler:info] Ready on http://127.0.0.1:8790          ← only the harness worker came up
not ok 1 - test/p5-1.test.mjs   failureType: 'testTimeoutFailure'  error: 'test timed out after 180000ms'
```

- `e2e/fullstack/test/p5-1.test.mjs:453` calls `startWorker({ config: ai-platform/wrangler.toml })`. esbuild resolves `"vendor-contracts"` from `ai-platform/src/**`, which looks in `ai-platform/node_modules`. The package is a `file:` dependency (`ai-platform/package.json`: `"vendor-contracts": "file:../packages/vendor-contracts"`, which `npm ci` turns into a symlink). There is no root `package.json` or `node_modules` (verified).
- `.github/scripts/setup-campaign-area.sh:43-46`:
  ```bash
  e2e-fullstack)
    need_supabase=1
    npm_dirs+=(packages/vendor-contracts e2e/fullstack)
  ```
  This installs neither `ai-platform` nor `abo`. The script has had this content since `880472dd` (2026-10-12); it has a single commit, and no change to it was ever reverted.
- The platform never serves, so `waitForHttp(PLATFORM_URL/health)` (120 s) plus the setup before it exceeds the 180 s timeout for the whole file. Node's process-isolated `--test-timeout` applies to the file-level test (`location: …p5-1.test.mjs:1:1`, `duration_ms: 180087`).

### B.2 p5-2 ERR_MODULE_NOT_FOUND, and a second bug hidden behind it

**Decisive log** (`all-ci/output.log` line 418):
```
Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'vendor-contracts' imported from /home/runner/work/AiClinic/AiClinic/ai-platform/src/vendor/entrypoint.ts
```
- `e2e/fullstack/test/p5-2.test.mjs:15`: `import { VendorEntrypoint } from "../../../ai-platform/src/vendor/entrypoint.ts";`. That loads ai-platform TypeScript **into Node** through tsx, and Node resolves `vendor-contracts` from `ai-platform/node_modules`, which is missing.
- **Hidden second bug:** `ai-platform/src/vendor/entrypoint.ts:1` is `import { WorkerEntrypoint, env as workerBindings } from "cloudflare:workers";`. Node cannot load the `cloudflare:` scheme.
  - I reproduced this with plain Node 22: a module importing `cloudflare:workers` alongside a missing bare package reports `ERR_MODULE_NOT_FOUND` first, which matches CI. Once the package resolves, it throws `ERR_UNSUPPORTED_ESM_URL_SCHEME`.
  - Nothing in `e2e/` maps `cloudflare:workers` (no loader or alias; rg confirmed).
  - I could not test under tsx itself (offline npm install failed). tsx does not handle non-file schemes, so I expect the same result.
  - This import has existed since `2e06880f` (2026-10-03), and p5-2 has imported entrypoint.ts since `db883f06` (2026-10-07). **p5-2 could never have loaded in Node.** Installing ai-platform alone will turn p5-2 into `ERR_UNSUPPORTED_ESM_URL_SCHEME`.
- The only use is `callFeedConsumerHealth()` (`p5-2.test.mjs:952-967`), called once from E2E-P5.2-07 (`:1525`). It builds `new VendorEntrypoint(getPlatformProxy().ctx, .env)` in-process. `feedConsumerHealth` (`entrypoint.ts:5113-5133`) only reads `feed_consumer` from D1.

**Fix for B.2:** call it through the harness worker's real `PLATFORM` RPC binding. `e2e/fullstack/wrangler.toml` already binds `PLATFORM` → `ai-platform-gateway-development` / `VendorEntrypoint`, and p5-2's `startStack` starts the harness on :8790 (`p5-2.test.mjs:483`).

1. `e2e/fullstack/src/register-issuer.ts`
   Before:
   ```ts
   const VENDOR_CALL_METHODS = new Set([
     "grant",
   ```
   After:
   ```ts
   const VENDOR_CALL_METHODS = new Set([
     "feedConsumerHealth",
     "grant",
   ```
   and in `interface Env { PLATFORM: { … } }`, add the line
   `    feedConsumerHealth(args: VendorCallArgs): Promise<unknown>;`
   after `registerIssuerKey(...)…;`.
2. `e2e/fullstack/test/p5-2.test.mjs`
   - Line 9, before: `import { getPlatformProxy, unstable_startWorker as startWorker } from "wrangler";`
     After: `import { unstable_startWorker as startWorker } from "wrangler";`
   - Delete line 15: `import { VendorEntrypoint } from "../../../ai-platform/src/vendor/entrypoint.ts";`
   - Delete line 107: `let platformVendorProxy = null;`
   - Replace lines 952-967 (the whole `async function callFeedConsumerHealth() { … }`) with:
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
       assert.equal(response.status, 200, "harness vendor-call feedConsumerHealth");
       return await response.json();
     }
     ```
   - In `after(...)` (lines 1265-1267), delete:
     ```js
       await platformVendorProxy?.dispose();
       platformVendorProxy = null;
     ```
   With these changes, p5-2 no longer imports ai-platform source into Node. The ai-platform install is still needed for the platform worker bundle (B.3).

   *Side benefit:* this also removes a second miniflare instance (getPlatformProxy) opening the live `PLATFORM_PERSIST` while `startWorker` owns it. `wrangler-persist.mjs:66-70` and `:126-129` warn about exactly that. Note that `runPlatformD1Command` (`p5-2.test.mjs:845-859`) still runs `wrangler d1 execute --persist-to PLATFORM_PERSIST` against the live platform. That is pre-existing and out of scope, but it is a risk.

### B.3 Which node_modules each suite needs, and the exact npm_dirs line

| Suite | Node-side imports (tsx) | Workers bundled by wrangler (resolve `vendor-contracts` from) |
|---|---|---|
| p5-1, p5-2, p7-2-* | `wrangler`, `@supabase/supabase-js`, `undici`, `vendor-contracts` → e2e/fullstack/node_modules | platform via `ai-platform/wrangler.toml` → **ai-platform/node_modules**; abo via `wrangler dev --config abo/wrangler.toml` → **abo/node_modules**; harness `e2e/fullstack/src` → e2e/fullstack/node_modules; paymob stub (no bare imports) |
| p7-3-* | same | default `ai-platform/wrangler.toml` / `abo/wrangler.toml` (p7-3-04, p7-3-07, restarts at p7-3-01:322) → ai-platform + abo; variant tomls `[alias] vendor-contracts = ./vendor-contracts-*.ts` (no node_modules needed), **except `platform-worker-n.toml`, which has no alias** → ai-platform |
| p5-2b | `vendor-contracts`, supabase | none |
| frontend/fullstack (hfl-run-flutter.mjs → p7-3-stack `startStack`) | e2e/fullstack/node_modules/tsx | default platform + abo configs → ai-platform + abo |

- The only bare runtime imports in `ai-platform/src` are `vendor-contracts` and `cloudflare:workers`. In `abo/src` it is only `vendor-contracts`. `packages/vendor-contracts/src` has **no** bare imports, so its own `npm ci` is needed only for its own tests. Keeping it is harmless.
- The abo requirement is inferred from source. CI never reached abo startup, because p5-1 stalled on the platform first.

**Fix: `.github/scripts/setup-campaign-area.sh`, `e2e-fullstack)` branch.**
Before: `    npm_dirs+=(packages/vendor-contracts e2e/fullstack)`
After:  `    npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)`

Cross-impact: each `case` branch affects only its own area, and no other area's branch changes. Install time goes up by about 1–2 min, well inside the 45 min limit. The `abo)` branch already runs `npm ci` in ai-platform and abo successfully in this same run, which proves both lockfiles install on the runner.

**Not in my scope, but caused by the same script:** the `frontend)` branch installs **no** npm dirs. `frontend/tool/run_campaigns.py:162-173` requires `e2e/fullstack/node_modules/tsx/dist/loader.mjs`. CI shows `ERROR: H-FS stack dependencies are missing. Run npm ci in e2e/fullstack/ …` (frontend/fullstack output.log), which is the "exit 1 with 0 tests". The matching fix is `frontend)` + `npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)`. Tell the frontend agent.

### B.4 all-manual: E2E-P7.2-01..09 and P7.3-01 `duplicate column name: canary_installation_ids`. The cause is a **parallel race**, not a stale seed

**Decisive lines** (`all-manual/output.log` ~480-940, plus the tail):
```
p7-2-credential-isolation … hookFailed
  wrangler d1 migrations apply ai-platform-development … --config ai-platform/wrangler.toml --persist-to e2e/fullstack/.wrangler/d1-seed failed (1):
  ✘ [ERROR] duplicate column name: canary_installation_ids: SQLITE_ERROR     (wrangler log 07-03-44_939)
p7-2-untrusted-callers … ✘ [ERROR] table grace_admission_queue already exists at offset 154 (wrangler log 07-03-47_133)
p7-3-01 … --config e2e/fullstack/test/variant/platform-n-plus-1.toml … ✘ [ERROR] No migrations present at e2e/fullstack/test/variant/migrations.
*** Fatal uncaught kj::Exception: … ::bind(...): Address already in use; toString() = 127.0.0.1:8787     ← last line of the log
```

**Root cause:**
- `e2e/fullstack/run_campaigns.py:116-118`: `run_all_manual` passes **all 12** `*.test.mjs` files to **one** `node --import tsx --test …` command. `campaigns/all-manual.json` has `"test_concurrency": null`, so `apply_campaign_args` adds no `--test-concurrency` (`test/harness/campaign_config.py:156-158`).
- Node 22 then runs test files in **parallel child processes**; the default concurrency is `availableParallelism()-1`, which is 3 on ubuntu-latest.
- Every stack (p5-1, p5-2, p7-2-stack, p7-3-stack) uses the **same** `.wrangler/{d1-seed,platform,abo,harness,registry}` dirs and the **same fixed ports** (8787/8788/8789/8790, inspector 9230/9231).
- Timeline: `prepare_fullstack_e2e_stack()` (`test/harness/local_dev_ports.py:159-168`) wiped `.wrangler` once at 07:03:40.9. At 07:03:44 and 07:03:47, two processes started their own `wrangler d1 migrations apply` on the fresh `d1-seed` while p5-1 was still applying migrations there. Each one read `d1_migrations` before the other had recorded a migration, then re-ran it. `20260803100000_routing_policy_canary.sql:2` (`ALTER TABLE routing_policy ADD COLUMN canary_installation_ids`) gave "duplicate column", and `20260821120000_grace_admission_queue.sql:3` (plain `CREATE TABLE`) gave "already exists".
- The 4-second gap after a full wipe rules out "migrations re-applied over an old persisted seed". The prior summary's claim is wrong. No seed is checked in, and `d1_migrations` is fine: wrangler `migrations apply` creates and maintains it, and both `ai-platform/wrangler.toml` and `platform-desktop-window.toml` point at the same folder and default table.

**Exit 130 (not the 45-minute job timeout):** the subcampaign ran 07:03:40 → 07:06:51, about 190 s. The last line is the workerd `Fatal uncaught kj::Exception … Address already in use 127.0.0.1:8787`: a second stack tried to bind the platform port that p5-1's stuck platform still held. The governor's `RunnerCrashGuard` matches `_FATAL_WORKERD` (`test/harness/live_progress.py:37-39`; `should_abort` at `:392-399`). `_run_monitored_child_process` (`common.py:414-431`) then calls `_terminate_process`, which sends **SIGINT** to the process tree (`common.py:327-343`). Node exits 130 and the subcampaign records `max(1, 130) = 130`. Tests P7.3-02..07 never ran, and node-test runs have no reconciliation for unreported tests, so they are absent from summary.json rather than marked NOT_RECORDED.

**The same race also exists in the `p7-2` and `p7-3` subcampaigns** (`run_p7_2`/`run_p7_3`, `run_campaigns.py:96-103`, which also pass several files to one `node --test`), but those subcampaigns are not run in CI.

**Fix B.4a (root fix): run multi-file e2e subcampaigns one file at a time, resetting persist and ports per file.** `all-ci` already does this through `_run_node_steps`, which calls `_prepare_fullstack_stack_ports()` before each step (that is the `Reset fullstack wrangler persist` line in the all-ci log).

File `e2e/fullstack/run_campaigns.py`. Add after `_node_cmd` (line 41):
```python
def _per_file_steps(files: list[str]) -> list[tuple[str, list[str]]]:
    return [(Path(f).stem.removesuffix(".test"), [f]) for f in files]
```
Replace:
```python
def run_p7_3(_: str) -> int:
    files = _node_test_files("p7-3*.test.mjs")
    return _run_node_tests("p7-3", files)


def run_p7_2(_: str) -> int:
    files = _node_test_files("p7-2*.test.mjs")
    return _run_node_tests("p7-2", files)
```
with:
```python
def run_p7_3(_: str) -> int:
    return _run_node_steps("p7-3", _per_file_steps(_node_test_files("p7-3*.test.mjs")))


def run_p7_2(_: str) -> int:
    return _run_node_steps("p7-2", _per_file_steps(_node_test_files("p7-2*.test.mjs")))
```
and replace:
```python
def run_all_manual(_: str) -> int:
    files = _node_test_files("*.test.mjs")
    return _run_node_tests("all-manual", files)
```
with:
```python
def run_all_manual(_: str) -> int:
    return _run_node_steps("all-manual", _per_file_steps(_node_test_files("*.test.mjs")))
```
- Step names become `p5-1`, `p5-2`, `p5-2b`, `p7-2-credential-isolation`, …, `p7-3-07`. For `p5-1`/`p5-2`/`p5-2b`, `nested_subcampaign_config` picks up the same-named JSON, which has identical values.
- Expected counts (`test/harness/dynamic_test_counts.py:270-289`, `campaign_counts.py:268-276`) are computed from the source files, so they do not change.
- *Weaker alternative:* set `"test_concurrency": 1` in `campaigns/all-manual.json`, `p7-2.json`, `p7-3.json`. That removes the race but **not** state leakage between files. `.wrangler` is not reset between files, and `execPlatformD1Sql` writes into `d1-seed`, which the next file's `preparePlatformD1` copies over the platform DB. Prefer B.4a.
- Reverted commit `e1a42092` instead wiped `D1_SEED_PERSIST` at the top of `preparePlatformD1`. That makes things *worse* under parallelism (one process deletes the seed while another migrates it). It was reverted in `cb99ded0` together with other changes, so it gives no signal about this race either way.

**Fix B.4b (separate real bug behind P7.3-01, and P7.3-02/03/05 once they run):** several variant tomls lack `migrations_dir`. Wrangler then defaults to `<toml dir>/migrations` = `e2e/fullstack/test/variant/migrations`, which does not exist. Only `platform-desktop-window.toml` and `abo-desktop-window.toml` got the line (`b68299b9`, for frontend H-FS). In each file below, add the line directly under `database_id = "11111111-1111-1111-1111-111111111111"` in the `[[env.development.d1_databases]]` block:
- `e2e/fullstack/test/variant/platform-n-plus-1.toml` (p7-3-01, p7-3-02), `platform-feed-window.toml` (p7-3-03), `platform-worker-n.toml` and `platform-do-receiver.toml` (p7-3-05):
  `migrations_dir = "../../../../ai-platform/migrations"`
- `e2e/fullstack/test/variant/abo-n-plus-1.toml` (p7-3-01/02 `applyAboMigrations(activeAboConfig)`, `p7-3-stack.mjs:317`, `:880`):
  `migrations_dir = "../../../../abo/migrations"`

Using the same folder means `d1_migrations` names match across configs, so a later apply is a no-op rather than a re-run.

**Fix B.4c (policy: should all-manual run in CI at all?)** My recommendation is **no**.
- `test/harness/campaign_catalog.py:199-203` describes all-ci as "The pair of scenarios run in continuous integration" and all-manual as "Every Node scenario file … in one run".
- `--full-area` (`test/run_campaigns.py:321-333` → `campaign_selection.full_area_minimal_picks`) selects every **root** in `campaign_tree.py:56-64`. Both `all-ci` and `all-manual` are roots, so CI runs both, and p5-1/p5-2 run twice.
- P7.2-07 (`p7-2-credential-isolation.test.mjs:110-133`) spawns `dart run bin/session_jwt_capture.dart`, but the e2e-fullstack matrix sets `flutter: false` (`ci.yml:42-46`), so there is no `dart` and no `dart pub get`.

Minimal edit in `test/run_campaigns.py`: add `import os` next to `import argparse`, then in the `if args.full_area:` branch:
```python
        picked = full_area_minimal_picks(args.full_area, area_subs)
        if os.environ.get("CI") == "true":
            picked = [p for p in picked if p != ("e2e-fullstack", "all-manual")]
```
(`ci.yml:16` sets `CI: "true"`.) `test/harness/test_campaign_selection.py` tests `full_area_minimal_picks` directly for abo and backend, so filtering in `run_campaigns.py` leaves that test intact.

If the owner wants P7 in CI instead, all of the following are needed: B.3, B.4a, B.4b, `flutter: true` for e2e-fullstack in ci.yml, and `(cd e2e/fullstack/dart && dart pub get)` in setup. Each file then cold-starts 4 wranglers, so budget the time.

### B.5 New fingerprint migration and e2e-fullstack
`preparePlatformD1` (`wrangler-persist.mjs:72-111`) runs `wrangler d1 migrations apply` over the whole `ai-platform/migrations` folder, so `20261014120000` is picked up automatically and tracked in `d1_migrations`. In sequential runs it is applied exactly once per fresh seed. It is subject to the same parallel race as every other non-idempotent migration, and B.4a removes that race. No other interaction.

### B.6 Open risks for e2e-fullstack (unverified)
1. **Time limit per file.** Node's `--test-timeout=180000` (`campaign_config.py:159-162`; all-ci.json/p5-*.json `test_timeout_ms: 180000`) is enforced on the **whole file**, as the p5-1 failure proves. p5-1 starts platform twice, then harness, paymob, and abo, then restarts abo twice. p5-2 is a 1.6k-line file with cron/feed flows. I cannot tell whether a healthy run fits in 180 s. If after B.1–B.3 a file fails with `testTimeoutFailure` at `:1:1` with no other error, raise `test_timeout_ms` to `600000` in `campaigns/all-ci.json`, `p5-1.json`, `p5-2.json` (and `all-manual.json`, `p7-2.json`, `p7-3.json`).
2. **Unpinned wrangler.** `runWranglerSync` and `spawnDevProcess` call `npx wrangler` with `cwd = REPO_ROOT` (`wrangler-persist.mjs:34-46`, `p5-1.test.mjs:95-101`). There is no root package.json, so npx cannot see `e2e/fullstack/node_modules/.bin`. In CI it auto-installs the **latest** wrangler from the registry rather than the pinned `~4.86.0`, so the migrations-apply and `wrangler dev` versions can drift from the `unstable_startWorker` in-process version. Reverted `e1a42092` had switched this to `process.execPath + e2e/fullstack/node_modules/wrangler/bin/wrangler.js`. That part is worth restoring later, but it is not needed to fix this run.
3. B.2 is inferred from plain-Node behaviour; I could not install tsx offline to confirm it under tsx.
4. B.4b paths are relative to the toml, matching the existing working `platform-desktop-window.toml`. I could not run them.

---

## Summary of edits (in order)

| # | File | Change | Fixes |
|---|---|---|---|
| 1 | `abo/test/system/cross-worker-harness.ts` | import and append `idempotencyFingerprintSql` | P4.9-03, P4.9-05, P4.8-07, P4.4-01; unblocks P4.2-03 |
| 2 | `.github/scripts/setup-campaign-area.sh` (`e2e-fullstack)`) | `npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)` | p5-1 bundle, p5-2 resolution, abo `wrangler dev` |
| 3 | `e2e/fullstack/test/p5-2.test.mjs` and `e2e/fullstack/src/register-issuer.ts` | drop the in-Node `VendorEntrypoint` import; call `feedConsumerHealth` via harness `/vendor-call` | p5-2 `cloudflare:workers` (hidden behind #2) |
| 4 | `test/run_campaigns.py` | skip `e2e-fullstack/all-manual` under `CI=true` | all-manual's 12 failures and exit 130 in CI |
| 5 | `e2e/fullstack/run_campaigns.py` | per-file `_run_node_steps` for all-manual, p7-2, p7-3 | parallel D1-seed and port race (local / if kept in CI) |
| 6 | 5 variant tomls | add `migrations_dir` | P7.3-01/02/03/05 "No migrations present" |
| (frontend agent) | `setup-campaign-area.sh` (`frontend)`) | same npm_dirs as #2 | frontend/fullstack "H-FS stack dependencies are missing" |

Edits 1–4 are enough to turn both target CI campaigns green, subject to risk B.6.1. Edits 5–6 are correctness fixes for manual/local runs, and are prerequisites if all-manual is ever kept in CI.

**Confidence:**
- A: high.
- B.1, B.3: high.
- B.2: high that it is a blocker; medium-high on the exact fix, since it relies on harness RPC to `feedConsumerHealth`, which needs no Access JWT (verified at `entrypoint.ts:5113-5133`).
- B.4 root cause: high (the timestamps, the port-bind fatal, and the shared paths all point the same way).
- B.4c is a policy recommendation.


---

# FOLLOW-UP: all-manual in CI

User decision: everything runs in CI. `e2e-fullstack/all-manual` stays in CI and must pass, and all-ci must stay green. No repo files were edited. Every statement below comes from reading the source and the CI artifacts; nothing was executed except `git show`, `git apply --check` and file searches.

## F.0 Headline and a correction to round 1

**Correction.** Round 1 said "Edits 1–4 are enough to turn both target CI campaigns green". That is wrong for e2e-fullstack. The round-1 fixes only remove the *first* failure in each file. Under it are deterministic product and harness bugs that also hit **all-ci**:

- p5-1 (P5.1-02, P5.1-06): blocked by F.4 B1, B2 and B3.
- p5-2: blocked by F.4 B1, B2, B3 and B8.

Those items (B1 Buffer, B2 non-canonical JWT JSON, B3 ABO vars, B8 Docker networking) are described in F.4. Evidence for each is given there.

The fix set comes in four layers. All four are needed for all-manual, and layers 3–4 are also needed for all-ci.

1. **Orchestration:** one `node --test` process per file, with port release and a `.wrangler` reset between files (F.1). Add a Supabase DB reset between files (F.1b), because Supabase state is shared across files (F.4 B10).
2. **CI environment:**
   - npm installs for `ai-platform` and `abo`
   - Flutter, for the Dart helper used by P7.2-08
   - environment variables
   - longer timeouts (F.2, F.5, F.7)
3. **Harness determinism** (F.3):
   - one pinned wrangler
   - live-DB-safe platform D1 writes
   - `migrations_dir` in the variant tomls
   - port release that also sees `0.0.0.0` listeners
4. **Hidden blockers** in product, backend and test code (F.4). Most of them were already fixed in the reverted commit `e1a42092`. `git apply --check` of `e1a42092` on HEAD `953e5e6e` succeeds (check only). **The coordinator should find out why `cb99ded0` reverted it** before re-applying it. Nothing in the repo records a reason; the commit message is the bare default "Revert ...".

---

## F.1 Run each file in its own node process (item 1)

### F.1a `e2e/fullstack/run_campaigns.py`

The pattern is the same as `run_all_ci`. `_run_node_steps` (lines 65-81) calls `_prepare_fullstack_stack_ports()`, which releases ports 8787-8790 and 9230/9231 and runs `rmtree e2e/fullstack/.wrangler`. It does this before **each** step and then runs one `run_subprocess_sequence([(name, cmd)])` per step. A failing or crash-aborted step therefore does not stop the later steps; the exit code is the max over all steps. CI confirms that the per-step results merge: `all-ci/summary.json` holds both `test/p5-1.test.mjs` and `test/p5-2.test.mjs` rows.

Before (lines 96-118):
```python
def run_p7_3(_: str) -> int:
    files = _node_test_files("p7-3*.test.mjs")
    return _run_node_tests("p7-3", files)


def run_p7_2(_: str) -> int:
    files = _node_test_files("p7-2*.test.mjs")
    return _run_node_tests("p7-2", files)
...
def run_all_manual(_: str) -> int:
    files = _node_test_files("*.test.mjs")
    return _run_node_tests("all-manual", files)
```
After:
```python
def _per_file_steps(files: list[str]) -> list[tuple[str, list[str]]]:
    return [(Path(f).name.removesuffix(".test.mjs"), [f]) for f in files]


def run_p7_3(_: str) -> int:
    return _run_node_steps("p7-3", _per_file_steps(_node_test_files("p7-3*.test.mjs")))


def run_p7_2(_: str) -> int:
    return _run_node_steps("p7-2", _per_file_steps(_node_test_files("p7-2*.test.mjs")))
...
def run_all_manual(_: str) -> int:
    return _run_node_steps("all-manual", _per_file_steps(_node_test_files("*.test.mjs")))
```

### F.1b Same file: guard against an empty step list, and reset Supabase between files

```python
import os
import subprocess
import time
import urllib.request

_SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
_SUPABASE_ANON_KEY = os.environ.get(
    "SUPABASE_ANON_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
)


def _reset_supabase_between_files() -> bool:
    if os.environ.get("HFS_RESET_SUPABASE") != "1":
        return True
    result = subprocess.run(["supabase", "db", "reset", "--local"], cwd=REPO_ROOT / "backend")
    if result.returncode != 0:
        print("error: supabase db reset failed", file=sys.stderr)
        return False
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        try:
            request = urllib.request.Request(
                f"{_SUPABASE_URL}/auth/v1/health", headers={"apikey": _SUPABASE_ANON_KEY}
            )
            with urllib.request.urlopen(request, timeout=3) as response:
                if response.status == 200:
                    return True
        except OSError:
            pass
        time.sleep(1)
    print("error: Supabase auth did not become ready after db reset", file=sys.stderr)
    return False


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
        ...  # unchanged
```

This is gated by `HFS_RESET_SUPABASE=1`, which F.2c sets for e2e-fullstack in CI. Local runs keep today's behaviour. The cost is about 45–75 s per file (198 backend migrations plus seed). Why it is needed is explained in F.4 B10.

### F.1c p5-1 and p5-2 run twice

`--full-area` picks both roots. They are sorted, so **all-ci runs first, then all-manual** (`campaign_selection.full_area_minimal_picks` → `minimal_run_picks(sorted(...))`). With F.1a and F.1b, each run starts from a clean `.wrangler` and a clean Supabase, so the double run is **safe** but costs about 8–10 minutes.

- **Recommendation: keep it.** Skipping p5-1 and p5-2 inside all-manual would leave all-manual's expected IDs unrecorded.
- Optional dedupe: in `test/harness/campaign_tree.py`, make `"all-ci": "all-manual"` a child instead of a root. `minimal_run_picks` then drops all-ci under `--full-area`. Before doing that, check `dynamic_test_counts.py:270-289` and the catalog roll-ups for double counting. I did not verify this, so I do not recommend it for this round.

---

## F.2 External tools and the CI and setup edits (item 2)

### F.2a What each file needs

| File | node 22.13+ (`node:sqlite` unflagged) | psql | Supabase (Docker) | dart/flutter | Other |
|---|---|---|---|---|---|
| p5-1 | yes | yes | yes | – | `ss` (port release) |
| p5-2 | yes | yes | yes, plus pg_net reaching the host (F.4 B8) | – | `supabase` CLI (`stopSupabase`/`startSupabase` at lines 1205-1224) |
| p5-2b | yes (psql only, no workers) | yes | yes | – | – |
| p7-2-credential-isolation | yes | yes | yes | **P7.2-08 runs `dart run bin/session_jwt_capture.dart`** with cwd `e2e/fullstack/dart` | Flutter SDK, because the `ai_clinic` path dependency needs `sdk: flutter` |
| p7-2-untrusted-callers, p7-2-vendor-entrypoint | yes | yes | yes | – | – |
| p7-3-01, 02, 04, 05, 07 | yes | yes | yes | – | – |
| p7-3-03 | yes | yes | yes, plus pg_net reaching the host (F.4 B8) | – | – |

No file needs the `sqlite3` CLI. `setup-node "22"` resolves to the latest 22.x, so `node:sqlite` is unflagged; it only prints an ExperimentalWarning, which does not trigger the crash guard. `ss` and Docker are present on `ubuntu-latest`.

**Correction to the earlier summary:** the Dart test is **P7.2-08**, not P7.2-07. P7.2-07 uses `issue_billing_token` and `issue_feed_token`.

### F.2b `.github/scripts/setup-campaign-area.sh`

Before (lines 42-45 and 62-66):
```bash
  e2e-fullstack)
    need_supabase=1
    npm_dirs+=(packages/vendor-contracts e2e/fullstack)
    ;;
...
if [[ "${need_flutter}" -eq 1 ]]; then
  require_command flutter
  echo "Installing Flutter dependencies..."
  (cd "${repo_root}/frontend" && flutter pub get)
fi
```
After:
```bash
  e2e-fullstack)
    need_supabase=1
    need_flutter=1
    npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)
    ;;
...
if [[ "${need_flutter}" -eq 1 ]]; then
  require_command flutter
  echo "Installing Flutter dependencies..."
  (cd "${repo_root}/frontend" && flutter pub get)
  if [[ "${area}" == "e2e-fullstack" ]]; then
    (cd "${repo_root}/e2e/fullstack/dart" && flutter pub get)
  fi
fi
```

Use `flutter pub get`, not `dart pub get`. The helper's pubspec depends on `ai_clinic: path: ../../../frontend`, and frontend's pubspec has `flutter: sdk: flutter` and `supabase_flutter`. Resolving that graph needs the Flutter SDK. `subosito/flutter-action` puts `flutter/bin` on PATH, which also provides the `dart` that the test spawns, and it sets `FLUTTER_ROOT`. Both pubspecs need `sdk: ^3.11.5`, so the current Flutter stable must ship Dart 3.11.5 or newer. The frontend job already depends on the same thing.

### F.2c `.github/workflows/ci.yml`

Before (lines 15-17 and 42-46):
```yaml
    env:
      CI: "true"
      CAMPAIGN_AREA: ${{ matrix.area }}
...
          - area: e2e-fullstack
            timeout_minutes: 45
            flutter: false
            supabase: true
            postgresql_client: true
```
After:
```yaml
    env:
      CI: "true"
      CAMPAIGN_AREA: ${{ matrix.area }}
      HFS_RESET_SUPABASE: ${{ matrix.area == 'e2e-fullstack' && '1' || '0' }}
      HFS_PLATFORM_BIND_HOST: ${{ matrix.area == 'e2e-fullstack' && '0.0.0.0' || '127.0.0.1' }}
...
          - area: e2e-fullstack
            timeout_minutes: 110
            flutter: true
            supabase: true
            postgresql_client: true
```
F.7 explains the 110.

---

## F.3 Harness determinism (item 3)

### F.3a Variant tomls: add `migrations_dir`

Paths are relative to the toml, the same as the two that already work (`platform-desktop-window.toml:54` and `abo-desktop-window.toml:45`). Each edit adds one line directly after `database_id = "11111111-1111-1111-1111-111111111111"` in `[[env.development.d1_databases]]`.

| File | After line | Line to add | Used by |
|---|---|---|---|
| `test/variant/platform-n-plus-1.toml` | 53 | `migrations_dir = "../../../../ai-platform/migrations"` | P7.3-01, P7.3-02 |
| `test/variant/platform-feed-window.toml` | 53 | `migrations_dir = "../../../../ai-platform/migrations"` | P7.3-03 |
| `test/variant/platform-worker-n.toml` | 50 | `migrations_dir = "../../../../ai-platform/migrations"` | P7.3-05 (this is the config passed to `preparePlatformD1`) |
| `test/variant/abo-n-plus-1.toml` | 44 | `migrations_dir = "../../../../abo/migrations"` | P7.3-01, P7.3-02 (`applyAboMigrations(activeAboConfig)`) |
| `test/variant/platform-do-receiver.toml` | 49 | `migrations_dir = "../../../../ai-platform/migrations"` | optional; never passed to a migrate call, kept for consistency |

`platform-worker-n.toml` has no `vendor-contracts` alias. That is intentional, because the N worker uses the real N contracts.

### F.3b Pin wrangler: one version for the CLI and for `unstable_startWorker`

Today every CLI call is `npx wrangler` with cwd `REPO_ROOT`, and the repo root has no `package.json`. npx cannot see `e2e/fullstack/node_modules/.bin`, so under `CI=true` it silently downloads the **latest** wrangler. Meanwhile `unstable_startWorker` in-process is the locked `4.86.0` (`e2e/fullstack/package-lock.json`). Where the versions could drift:

- the dev registry format: the ABO `wrangler dev` has to find the in-process platform through `REGISTRY_DIR`
- the D1 local storage layout
- the `--var` parsing used in F.4 B3

The CI logs print no wrangler banner for e2e-fullstack, so I could not see which version actually ran.

**`e2e/fullstack/test/wrangler-persist.mjs`**, after the `REPO_ROOT` export:
```js
export const WRANGLER_CLI = path.join(FULLSTACK_ROOT, "node_modules/wrangler/bin/wrangler.js");
```
In `runWranglerSync`, before and after:
```js
  const result = spawnSync("npx", ["wrangler", ...args], {
```
```js
  const result = spawnSync(process.execPath, [WRANGLER_CLI, ...args], {
```

Make the same change in every `spawnDevProcess`. Import `WRANGLER_CLI` from `./wrangler-persist.mjs`.

- `p5-1.test.mjs:96`, `p5-2.test.mjs:146`, `p7-2-stack.mjs:194`, `p7-3-stack.mjs:222`
  - Before: `spawn("npx", ["wrangler", ...args], {`
  - After: `spawn(process.execPath, [WRANGLER_CLI, ...args], {`
  - Side benefit: `stopChild`'s SIGTERM now reaches wrangler itself instead of an npx wrapper.
- `p5-2.test.mjs:1206` and `:1217`
  - Before: `spawnSync("npx", ["supabase", ...])`
  - After: `spawnSync("supabase", [...])`
  - `backend/` has no `package.json`, so npx downloads the npm `supabase` package (an extra ~30–60 s and an unpinned binary). setup-cli already puts `supabase` on PATH.

### F.3c Platform D1 writes must go to the live runtime file

`execPlatformD1Sql` (`wrangler-persist.mjs:130-153`) runs `d1 execute` on the seed and then `cpSync`s the seed over `PLATFORM_PERSIST`. Its own doc comment says it is only for use *before* any `startWorker`. But it is called **mid-test, while the platform worker is running**:

- through `ensurePlatformGrantPrerequisites`: p7-2-untrusted-callers:202/203/396; p7-2-vendor-entrypoint:302/437/663; p7-3-01:135, -02:78, -04:63, -05:70
- through `seedLocalPlatformIssuerKey` (`p7-3-stack.mjs:371`, after the platform has started), which `hfl-run-flutter` uses

Each such call overwrites the live DB with the seed. That **drops every row the live worker has written since boot**, for example the issuer key registered through `/register-issuer-key` in `startStack`. It also leaves the live `-wal`/`-shm` files beside a replaced main file (`copyD1SqliteTree` copies only `*.sqlite`).

After (as in `e1a42092`, plus a busy timeout):
```js
/** Apply fixture SQL directly to the runtime D1 file. */
export function execPlatformD1Sql(sql) {
  const db = new DatabaseSync(platformD1DatabaseFile());
  try {
    db.exec("PRAGMA busy_timeout = 5000");
    db.exec(sql);
  } finally {
    db.close();
  }
}
```
In `preparePlatformD1`, wipe the seed first. Import `rmSync`.
```js
  rmSync(D1_SEED_PERSIST, { recursive: true, force: true });
  mkdirSync(D1_SEED_PERSIST, { recursive: true });
```
In `copyD1SqliteTree`, use `e1a42092`'s WAL-safe copy: `PRAGMA wal_checkpoint(TRUNCATE)` on the source, then `rmSync` the target's `-wal` and `-shm`, then `cpSync`.

Also, `p5-2.test.mjs:845-859` (`runPlatformD1Command`) runs `wrangler d1 execute --persist-to PLATFORM_PERSIST`, a second Miniflare on the live tree. Replace its body with `execPlatformD1Sql(sql)`, which is already imported at line 205. Then P5.2-07's `setFeedConsumerLastPullAt` row is written by the same path `queryPlatformD1One` already reads.

### F.3d The platform must be reachable from the Supabase DB container (needed by F.4 B8)

**`wrangler-persist.mjs`:**
```js
export const PLATFORM_BIND_HOST = process.env.HFS_PLATFORM_BIND_HOST ?? "127.0.0.1";
```
In the platform `startWorker` server options, `server: { hostname: "127.0.0.1", port: 8787 }` becomes `server: { hostname: PLATFORM_BIND_HOST, port: 8787 }`. The places are:

- `p5-1.test.mjs` (~line 453)
- `p5-2.test.mjs:473`
- the `p7-2-stack.mjs` platform `startWorker`
- `p7-3-stack.mjs:745` (`startPlatformAdmissionWorker`)

The brief boot in `preparePlatformD1` can stay on 127.0.0.1. Clients keep using `PLATFORM_URL = http://127.0.0.1:8787`.

**`test/harness/local_dev_ports.py`, `pids_listening_on_tcp_port`.** It matches only the `"127.0.0.1:{port}"` needle, so a stale `0.0.0.0:8787` listener would **not** be released. Before and after:
```python
    needle = f"{host}:{port}"
    ...
        if needle not in line:
            continue
```
```python
    needles = (f"{host}:{port}", f"0.0.0.0:{port}", f"*:{port}", f"[::]:{port}")
    ...
        if not any(needle in line for needle in needles):
            continue
```
The kill filter `_is_stale_fullstack_dev_process` (workerd, wrangler, or node under the repo) is unchanged, so nothing else on the runner is killed.

---

## F.4 Blockers hidden behind the round-1 failures

These are deterministic unless marked otherwise. Each one would fail even with perfect orchestration.

**B1. `Buffer` in Worker code (no `nodejs_compat` anywhere).** Affects p5-1 P5.1-02/06, p5-2 P5.2-10, all P7.2 billing/ABO checks, and P7.3-01/02/04.

- `packages/vendor-contracts/src/token-claims.ts:24` and `receipt.ts:135` decode with `Buffer.from(padded, "base64")` inside `try { } catch { return null; }`.
- None of `ai-platform/wrangler.toml`, `abo/wrangler.toml`, `e2e/fullstack/wrangler.toml` or the variants set `compatibility_flags`. Under real `wrangler dev` / `unstable_startWorker`, `Buffer` is undefined, so a ReferenceError is caught and decoding returns `null`.
- Consequences:
  - `validateTokenClaims` rejects **every** billing token at the ABO (`abo/src/clinic-api/auth.ts:261`) and every feed token at the platform (`ai-platform/src/worker.ts:2234`).
  - `verifyReceiptSignature` fails in ABO grant and reversal work (`abo/src/work/grant.ts:496`, `reversal.ts:436`).
- vitest-pool-workers enables Node compatibility itself, which is why the abo and ai-platform suites do not catch this.
- Fix: in both places, use `e1a42092`'s replacement, which `e1a42092` applied only to token-claims:
  ```ts
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
  ```
- Behaviour change: input whose length mod 4 is 1 now returns `null` (atob throws), where Buffer used to decode it leniently. Such input is not valid base64url anyway.

**B2. PostgreSQL signs non-canonical JWT JSON.** Affects billing tokens (ABO) and feed tokens (platform, including pg_net pulls), so P5.1-02/06, P5.2-01/02/05/06/08/10, P7.2-02/03/04/06/07 and P7.3-01/02/03/04.

- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` builds the header and payload as `jsonb_build_object(...)::text`:
  - billing at lines 1239-1256
  - feed at 1377-1391
  - AAT at 1056-1074
- `jsonb::text` emits `{"alg": "EdDSA", ...}`, with spaces and jsonb's length-first key order. The shared verifier compares bytes exactly against `canonicalize(...)`, at `token-claims.ts:91-95` (header) and `:227` (payload).
- The AAT verifier in `ai-platform/src/identity` does not compare bytes, so AATs work, but billing and feed tokens cannot.
- Fix: add a new migration, for example `20261015120000_canonical_issuer_jwt_json.sql`. Start from `e1a42092`'s `20261014170000_canonical_billing_jwt_json.sql`, which adds `auth_internal.canonical_issuer_jwt_json` and redefines `issue_billing_token`.
- **Also** `CREATE OR REPLACE` `auth_internal.issue_feed_token()`. Copy it from 20261007180000:1334-1406, wrapping both `jsonb_build_object(...)` calls in `auth_internal.canonical_issuer_jwt_json(...)` instead of `::text`. `e1a42092` missed this one. No later migration redefines either function; 20261007230000 only calls `issue_feed_token()`.
- Do the same to `issue_ai_token` if you want consistency; it is optional.
- Apply `e1a42092`'s `backend/tests/issuer_rpc.sql` hunk. **This touches the backend area.** The backend campaign must re-run.

**B3. ABO bindings are passed as process env, which `wrangler dev` ignores.** Affects every ABO-dependent test in p5-1, p5-2, P7.2 and P7.3.

- `spawnAboProcess` passes `PAYMOB_BASE_URL`, `ISSUER_KEYS`, `ABO_GRANT_KEY` and `PLATFORM_PUBLIC_KEYS` through the child's `env`:
  - p5-1:524-525, 574-575
  - p5-2:540-541, 590-591
  - p7-2-stack:572-573
  - p7-3-stack:717-721
- wrangler does not turn process env into bindings unless `CLOUDFLARE_INCLUDE_PROCESS_ENV=true`. So the ABO runs with `abo/wrangler.toml [env.development.vars]`: `ISSUER_KEYS = "[]"`, `ABO_GRANT_KEY = "{}"`, `PLATFORM_PUBLIC_KEYS = "[]"`, and `PAYMOB_BASE_URL` = the real Paymob.
- `e1a42092` switched p7-2-stack to `--var`. That is the only commit in history that ever did, which is strong evidence the author hit this problem.
- Fix: in all four files, and in each `restartAbo`, pass each key as an argument instead of in `env`:
  ```js
      "--var", `PAYMOB_BASE_URL:${PAYMOB_URL}`,
      "--var", `ISSUER_KEYS:${JSON.stringify(issuerKeys)}`,
      "--var", `ABO_GRANT_KEY:${JSON.stringify(ABO_GRANT_KEY)}`,
      "--var", `PLATFORM_PUBLIC_KEYS:${JSON.stringify(PLATFORM_PUBLIC_KEYS)}`,
  ```
- Confidence is about 85%. I could not read wrangler 4.86 locally because no `node_modules/wrangler` was installed. Do not use the `CLOUDFLARE_INCLUDE_PROCESS_ENV=true` alternative: it would inject the whole CI environment as vars.

**B4. Only one organization per installation.** Affects all P7.2 and P7.3 files (`createTwoOrgClinics`).

- `bootstrap_create_organization` returns `ORG_ALREADY_EXISTS` whenever an org exists (latest definition `20261009120000_fix_staff_membership_session_rls.sql`).
- `createOrgClinic` throws on that, at `p7-2-stack.mjs:480` and the identical code at `p7-3-stack.mjs:618-626`. Org B therefore always fails, and Org A fails too if p5-1 or p5-2 created an org first.
- Fix: apply `e1a42092`'s `createOrgClinic` hunk to `p7-2-stack.mjs`, and port the same code into `p7-3-stack.mjs:597-680`, which `e1a42092` did not touch. The hunk:
  - adds `findTestOrganizationId`, `insertTestOrganization` and `findTestBranchId`
  - falls back to a privileged insert on `ORG_ALREADY_EXISTS`
  - calls `set_active_organization`, which exists in `20261002120000_membership_active_org.sql`

**B5. Stale assertions in P7.2-03.** In `p7-2-untrusted-callers.test.mjs`:

- **:377/:383** query `checkout ... AND org = ...`, but the column is `org_id` (`abo/migrations/0002_checkout.sql`). `d1 execute` fails with "no such column".
- **:242** `assertAboNotFound("/v1/checkouts")` expects a JSON body with `code: "not_found"`. `abo/src/worker.ts:275` returns `emptyNotFound()` (`new Response(null, {status: 404})`), so `response.json()` throws.
- **:338** sends `input:` instead of a schema-valid `context:`, and Org A has no coverage. That rejection does not match the accepted regex at :356.
- Fix: apply all of `e1a42092`'s hunks for:
  - `p7-2-untrusted-callers.test.mjs`
  - `p7-2-stack.mjs` (`ensurePlatformActiveCoverage`)
  - `abo/src/worker.ts`, which uses `clinicErrorResponse("not_found", 404, version)`. That function exists at `abo/src/clinic-api/version.ts:126`.
- Check: no abo test calls GET `/v1/checkouts` without `?open=1`; every abo match is a POST. This makes the abo change low-risk, but abo/cross-worker must re-run.

**B6. The Dart helper cannot compile under `dart run`.** Affects P7.2-08.

- `e2e/fullstack/dart/bin/session_jwt_capture.dart` imports `core/ai/supabase_aat_mint_port.dart` and `features/ai/billing/billing_token_client.dart`. Both import `package:supabase_flutter/supabase_flutter.dart`, which pulls in `package:flutter` and therefore `dart:ui`. That fails to compile on the Dart VM.
- Fix: apply `e1a42092`'s hunk for this file. It drops those imports and uses `rpc.call('issue_ai_token' | 'issue_billing_token')` plus a direct `GET {abo_base_url}/v1/offers`.
- The remaining imports (`discovery_client`, `https_submit_port`, `ports`, `usage_summary_client`, `contract_versions`, `ai_availability`, `taxonomy`, `sse_events`) contain no Flutter imports. I checked each one.

**B7. Mid-test D1 writes clobber the live database.** Fixed by F.3c. Affects P7.2-02..06, P7.2-09 and P7.3-01/02/04/05.

**B8. pg_net cannot reach the platform on Linux.** Affects p5-2 P5.2-01/02/05/06/08/10 and P7.3-03.

- The feed puller runs inside the Supabase DB container and rewrites `127.0.0.1` to `host.docker.internal` (`20261007230000_coverage_feed_puller_status.sql:331-341`). `specs/088.../research.md §1.4` records that this was spiked on Docker Desktop, which proxies to the host's loopback.
- On a Linux runner, `host.docker.internal` resolves to the bridge gateway (Supabase CLI adds `host-gateway`; that is my understanding, not verified). Every stack binds the platform to **127.0.0.1 only**, so the connection is refused.
- `net._http_response.status_code` is not 200, which fails `p5-2.test.mjs:1295` and P7.3-03's checks.
- Fix: F.3d (bind to `0.0.0.0` under CI) and F.2c (env var).

**B9. Re-check of the p5-2 `/vendor-call` fix (item 6).**

- Harness: `e2e/fullstack/src/register-issuer.ts:43-56` checks `body.method` against `VENDOR_CALL_METHODS` and calls `env.PLATFORM[method](args)`.
- The `PLATFORM` binding is service `ai-platform-gateway-development`, entrypoint `VendorEntrypoint`, resolved through `REGISTRY_DIR`. It is the same path p5-2 already uses successfully for `registerIssuerKey` (p5-2:303), and p7-2/p7-3 use for `grant`.
- `VendorEntrypoint.feedConsumerHealth(args)` (`ai-platform/src/vendor/entrypoint.ts:5113-5133`):
  - only negotiates `contract_version` and reads `feed_consumer`
  - has no Access JWT and no WebAuthn check
  - returns `ok(version, detail)` with `detail` as a JSON string, which matches the test's `health.result === "ok"` and `JSON.parse(health.detail)`
- Exact edits:
  - **`register-issuer.ts`:** add `"feedConsumerHealth",` to `VENDOR_CALL_METHODS`, and `feedConsumerHealth(args: VendorCallArgs): Promise<unknown>;` to `Env.PLATFORM`.
  - **`p5-2.test.mjs`:**
    - Delete line 15 (the `VendorEntrypoint` import), line 107 (`let platformVendorProxy`) and lines 1266-1267 (the dispose).
    - Drop `getPlatformProxy` from line 9.
    - Replace `callFeedConsumerHealth` (952-967) with:
      ```js
      async function callFeedConsumerHealth() {
        const response = await fetch(`${HARNESS_URL}/vendor-call`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ method: "feedConsumerHealth", args: { contract_version: 1 } }),
        });
        assert.equal(response.status, 200);
        return await response.json();
      }
      ```
- Requirement: the live worker must see the `feed_consumer` row that `setFeedConsumerLastPullAt` wrote, so F.3c's change to p5-2 `runPlatformD1Command` is part of this fix.
- Confidence: high on the routing, medium-high on visibility (see R5).

**B10. Supabase state is shared across files.** This blocker only appears in sequential runs.

- `ai_internal.ai_token_issuance.actor_staff_id REFERENCES public.staff_members (id)` has no cascade (`20260801120000_ai_keystore_schema.sql:126`). Every stack's cleanup deletes its prefix's staff and users:
  - p5-1:326-335 (`p5-1-%`)
  - p5-2 (`p5-2-%`)
  - p7-2-stack and p7-3-stack (`p7-2-a-%` and `p7-2-b-%`, shared by **9** files)
- Once any file has minted a token, the next file with the same prefix fails in `psql` with a foreign-key violation inside `startStack`. That breaks the second p5-1 and p5-2 runs (all-manual after all-ci) and every P7.2/P7.3 file after the first.
- Other state also leaks between files:
  - the Supabase feed cursor, against a fresh platform feed in each file
  - `ai.contract_versions.platformFeed.current`, which P5.2-06 changes and P7.3-03 asserts
  - the issuer-key rotation from P5.1-06
- Fix: F.1b (`supabase db reset` between files).
- Cheaper alternative, which I do not recommend: delete `ai_internal.ai_token_issuance` rows (and any other `created_by`/staff FK rows) for the prefix before deleting staff. The full set of referencing tables is unknown, and it does not fix the leaks listed above.

---

## F.5 Per-file timeouts (item 4)

Node applies `--test-timeout` to the **whole file**. CI shows p5-1 failing at `:1:1` after 180087 ms. The stall guard limit is `test_timeout_ms + 15 s` (`live_progress.py:240-251`), and `startStack` emits no progress lines during boot.

The estimates below are for `ubuntu-latest` with a pinned local wrangler. A stack boot (seed migrate, platform and harness `startWorker`, paymob and abo `wrangler dev`, abo migrate, two orgs) takes about 60–80 s. Each wrangler CLI call takes about 2–4 s, and each ABO or platform restart about 15–20 s. The CLI-call counts come from scanning each file statically.

| File | CLI calls / restarts | Estimate |
|---|---|---|
| p5-1 | 3 / 3 | ~150 s |
| p5-2 | 17 / 2, plus Supabase stop/start (~60–90 s) and pg_net waits | ~240–300 s |
| p5-2b | 0 / 0 (psql only) | ~30 s |
| p7-2-credential-isolation | 0 / 0, plus Dart compile (~30–60 s) | ~150 s |
| p7-2-untrusted-callers | 27 / 0 | ~200 s |
| p7-2-vendor-entrypoint | 4 / 0 | ~130 s |
| p7-3-01 | 12 / 2 | ~160 s |
| p7-3-02 | 7 / 1 | ~130 s |
| p7-3-03 | 0 / 0 | ~100 s |
| p7-3-04 | 5 / 0 | ~110 s |
| p7-3-05 | 1 / 0, plus the DO receiver worker | ~120 s |
| p7-3-07 | 5 / 0 | ~110 s |

**Proposal:** set `"test_timeout_ms": 360000` in `e2e/fullstack/campaigns/all-ci.json`, `all-manual.json`, `p5-1.json`, `p5-2.json`, `p7-2.json` and `p7-3.json`. That is 6 minutes, more than 1.2× the worst estimate (p5-2). p5-2b.json can stay at 180000. Leave `test_concurrency` at `null`; with one file per process it has no effect.

---

## F.6 Crash and stall guard tripwires (item 5)

1. **Port bind fatal (`Fatal uncaught kj::Exception ... Address already in use 127.0.0.1:8787`).** This was the only crash-guard trigger in the CI artifacts (all-manual `output.log:1025-1026`).
   - Running one file per process removes the cause. The port release before each step also kills leftovers from a file that timed out (the node test child is SIGINTed, and in-process workerd children may survive).
   - With F.3d, the release must also match `0.0.0.0` listeners (the `local_dev_ports.py` edit).
2. **`_WORKERD_UNCAUGHT` (`workerd/...: error|warn: uncaught exception`).** It aborts the step after **0.75 s** unless a test result line arrives first (`live_progress.py:41-44, 312, 397-399`).
   - In-process `startWorker` output (platform, harness, DO receiver) reaches the governor.
   - Tests that deliberately provoke platform-side failures could emit it: P7.3-05 version skew between the N worker and the N+1 DO receiver, P7.2-05/06/09 rejected vendor calls, and P5.2-10 Supabase going down mid-payment.
   - I cannot tell whether workerd logs these at `error` or `info` level, so this is a residual risk (R3).
   - The abort only kills that file's step. The other steps still run (`_run_node_steps` uses one `run_subprocess_sequence` per step).
3. **Stall guard.** It fires after `test_timeout_ms + 15 s` without a result line. With F.5 that is 375 s, which fits the longest silent stretch (p5-2 boot plus the first test).
4. **Exit 130.** This is node's own exit code after the guard's SIGINT. Children run with `start_new_session=True` (`common.py:231`), so the governor's Python never receives SIGINT and later steps continue.
5. Other things checked:
   - `--inspector-port 9230/9231` bind failures are warnings, not fatals.
   - The `node:sqlite` ExperimentalWarning matches no guard pattern.
   - Dart output from P7.2-08 is captured by the test, not echoed, so `_DART_UNHANDLED` cannot fire.

---

## F.7 Total CI wall time (item 7)

| Phase | Estimate |
|---|---|
| Setup: checkout, node, pip, 4× `npm ci`, flutter-action (cached), 2× `flutter pub get`, `supabase start` with image pulls | 7–9 min |
| all-ci: p5-1 and p5-2, plus 2 Supabase resets | 8–10 min |
| all-manual: 12 files (~29 min), plus 12 resets (~12 min), plus port and persist resets | 40–45 min |
| **Total (nominal)** | **55–64 min** |

The current 45-minute limit is too low even without the resets. **Proposal: `timeout_minutes: 110`.** That is about 1.7× the nominal time. It also gives every file room to reach its own 6-minute timeout and *report*, instead of GitHub cancelling the job and leaving tests NOT_RECORDED. The pathological worst case (14 files × 6 min, plus resets and setup) is about 106 minutes.

If the optional dedupe in F.1c is adopted later, subtract about 9 minutes.

---

## F.8 Cross-impact on frontend/fullstack and other areas (item 8)

`hfl-run-flutter.mjs` calls `startStack({createClinics:false, registerIssuer:false})` from `p7-3-stack.mjs`. `p7-3-06-prepare.mjs` (manual) also calls `startStack`. The `staging/stg-*.mjs` files only mention the stacks in text and are not wired into any campaign.

| Shared file / change | Effect on frontend/fullstack and others | Invariant preserved |
|---|---|---|
| `wrangler-persist.mjs`: `WRANGLER_CLI` (local 4.86.0) | The frontend job must run `npm ci` in `e2e/fullstack`. It already must, for tsx: "H-FS stack dependencies are missing". | Every wrangler CLI call and `unstable_startWorker` use the same locked wrangler version. |
| `wrangler-persist.mjs`: direct-write `execPlatformD1Sql`, seed wipe in `preparePlatformD1`, WAL-safe copy | Fixes a latent frontend bug: `seedLocalPlatformIssuerKey` runs after the platform starts (`p7-3-stack.mjs:865`) and today overwrites the live DB. | After `startWorker`, the runtime D1 file is the single source of truth. The seed exists only to migrate an empty database once per `preparePlatformD1`. |
| `wrangler-persist.mjs`: `PLATFORM_BIND_HOST` | The frontend job leaves it unset, so 127.0.0.1 is unchanged. If frontend H-FS ever depends on pg_net feed pulls, set it to `0.0.0.0` there too. | Clients always use `PLATFORM_URL = 127.0.0.1:8787`. Only the listening address changes, and only when opted in. |
| `p7-3-stack.mjs`: `--var` for ABO, local wrangler in `spawnDevProcess`, `createOrgClinic` fallback | The frontend H-FS ABO now actually receives `ISSUER_KEYS`/`PLATFORM_PUBLIC_KEYS`/the Paymob stub URL, so its billing flows start working. `createOrgClinic` is not used by hfl (`createClinics:false`). | ABO config comes only from the stack, never from the ambient environment. Stack startup is idempotent against an installation that already has an org. |
| `local_dev_ports.py`: wider listener match | `prepare_fullstack_e2e_stack` is shared with the frontend tool. It now also frees `0.0.0.0` listeners on the same six ports. | Only processes passing `_is_stale_fullstack_dev_process` (workerd, wrangler, or node under the repo) are ever killed. |
| `setup-campaign-area.sh` `frontend)` (frontend agent) | Needs `npm_dirs+=(packages/vendor-contracts ai-platform abo e2e/fullstack)`. Also note the frontend matrix has `postgresql_client: false`, while `p7-3-stack` calls `psql` (`readIssuerKeyByStatus`) even when `createClinics:false`. | Each area installs exactly the node_modules its bundles resolve. |
| `vendor-contracts` `atob` (B1) | Affects vendor-contracts, ai-platform, abo and frontend (through the workers). Same bytes for valid base64url. Run the vendor-contracts, abo and ai-platform campaigns. | Token, receipt and grant verification behave the same in vitest-pool-workers and in real `wrangler dev`. |
| Backend canonical-JSON migration (B2) | Affects the backend campaign (`issuer_rpc.sql`). Frontend Dart that decodes token payloads still gets valid JSON. | PG-issued JWT bytes are RFC 8785 canonical, which is what `vendor-contracts` verifies. |
| `abo/src/worker.ts` 404 body (B5) | Affects abo/cross-worker and version-matrix. No abo test GETs `/v1/checkouts` without `?open=1`. | Every ABO clinic-API error is a JSON `{code}` body with `Abo-Contract-Version`. |

---

## F.9 Recommended order of edits

1. Round-1 fixes: abo fingerprint migration, npm_dirs, the p5-2 `/vendor-call` fix. **Drop round-1 edit #4** (skip all-manual under CI).
2. F.4 B1 and B2: `vendor-contracts` `atob`, and the backend canonical-JSON migration. These two plus B3 unblock all-ci.
3. F.4 B3, F.3b, F.3c and F.3d: `--var`, pinned wrangler, live-DB writes, bind host and the port-release match.
4. F.1a/F.1b, F.2b/F.2c, F.5: per-file steps, Supabase reset, setup, ci.yml, timeouts.
5. F.3a, F.4 B4, B5 and B6: variant tomls, second org, the P7.2-03 hunks, the Dart helper. Most of this is `git show e1a42092 -- <file> | git apply` for `p7-2-stack.mjs`, `p7-2-untrusted-callers.test.mjs`, `abo/src/worker.ts`, `session_jwt_capture.dart`, `wrangler-persist.mjs` and `token-claims.ts`. Then port the org fallback to `p7-3-stack.mjs` by hand.

---

## F.10 Residual risks (could still fail in CI; not verifiable here)

- **R1.** B3 depends on wrangler 4.86 behaviour (process env is ignored unless `CLOUDFLARE_INCLUDE_PROCESS_ENV`, and `--var KEY:VALUE` splits on the first colon). The source was not available offline. If ABO auth still fails, look at `ISSUER_KEYS` inside the worker first.
- **R2.** B8 assumes the Supabase CLI adds `host.docker.internal:host-gateway` to its containers on Linux, and that the runner's iptables allow bridge-to-host traffic to `0.0.0.0:8787`. If `net._http_response` shows a DNS error, set `ai.platform_base_url` to `http://172.17.0.1:8787` in p5-2's and p7-3-03's setup instead. The rewrite only touches loopback hosts.
- **R3.** Crash-guard false positives from `workerd ... error: uncaught exception` in tests that provoke platform failures (P7.3-05, P7.2-05/06/09, P5.2-10). If a file aborts with "harness aborted: runner error without a test result", the guard needs an allow-list. That would be a harness change.
- **R4.** `atob`/`--var`/canonical JSON were reasoned from source. `e1a42092` had the author's local run behind it for billing tokens, but not for **feed** tokens or `receipt.ts`, which are my additions.
- **R5.** Two processes writing the same D1 SQLite file:
  - node:sqlite (F.3c) alongside workerd's Durable Object SQLite
  - P7.3-05's two in-process workers on one `PLATFORM_PERSIST`
  - `wrangler d1 execute` on the live `ABO_PERSIST` while `wrangler dev` runs (`queryAboD1One` / `runAboD1Command`)

  These depend on workerd's VFS locking. `queryPlatformD1One` already reads the live file this way at HEAD, but writes are new.
- **R6.** The time estimates in F.5 and F.7 are not measured. The first CI run should log each step's elapsed time (the governor already records `elapsed_seconds`). Tune `test_timeout_ms` from that.
- **R7.** `supabase db reset` cost and side effects: it restarts Postgres and reloads seed, cron and vault. The `admin`/`admin` bootstrap user and the `signing` issuer key must come back from migrations or seed, which they do on the first `supabase start` in CI. PostgREST's schema-cache reload may take a few seconds after `/auth/v1/health` is green. If the first RPC after a reset intermittently fails, also poll `/rest/v1/` with the apikey.
- **R8.** B4's `insertTestOrganization` writes `public.organizations` directly (`name, currency_code, timezone, settings_json, created_by, updated_by`). I did not re-check the columns against the latest org migrations.
- **R9.** P5.2-10 runs `supabase stop` / `supabase start` twice per job (once in all-ci, once in all-manual). That is about 2–3 minutes and depends on the Docker images still being cached.
- **R10.** The reason `cb99ded0` reverted `e1a42092` is unknown. If it was reverted for a backend or abo regression, re-applying `e1a42092` hunks (B1, B2, B5) reintroduces it. Re-run the backend, abo and vendor-contracts campaigns after applying them.
- **R11.** Flutter stable must ship Dart 3.11.5 or newer, for both `frontend` and `e2e/fullstack/dart`. `flutter pub get` in `e2e/fullstack/dart` needs network access to pub.dev.
- **R12.** `vendor-contracts/all` (P2.2-08 bundle scan, outside this agent's scope) may interact with B1. If that scan flags Node globals, `Buffer` was already a finding there.

**Confidence:**
- F.1 orchestration and F.3a: high.
- B4, B5, B6, B10: high, read directly from code and schema.
- B1, B2: high (about 85–90%).
- B3, B8: medium-high (about 75–85%, because of environment behaviour I could not run).
- That all-manual passes on the first CI run after every edit: medium. Expect one tuning pass for R3, R5 and R6.
