# Agent E — Fix-history forensics: why fixing one campaign breaks another

Repo: `C:\Users\haosama\Downloads\resources`, branch `ai/abo-master`, HEAD `953e5e6e` (= the commit CI run 38695681551 tested).
Method: `git log/show/diff` + reading the CI artifacts + reading the source. No tests were run. No repo files were modified.

## TL;DR

1. **No single spec existed.** Each commit fixed whichever campaign was red by changing *shared production behavior* (the Quota DO admission order, denial codes, replay semantics) and then *flipped the test expectations to match*. That flips other campaigns that assert the old behavior. In about 13 hours the jti-replay branch of `ai-platform/src/quota-do/index.ts::admitOnHotRow` was rewritten **6 times**, and the denial codes flipped 4 times.
2. **Schema changes are not propagated.** 771ceed7 added a D1 migration (`request_fingerprint`). About 42 test files hand-list ai-platform migrations via `?raw` imports, but only 3 got the new file. ai-platform/load, the load-and-cost part of npm-test, and 4 abo cross-worker cases all fail with `no such column: request_fingerprint`. The same commit also broke the schema snapshot (wrong column position) and the manifest export allowlist (a new export).
3. **The CI environment differs per area.** `.github/scripts/setup-campaign-area.sh` installs different `node_modules` per area. A fix that works locally, where everything is installed, fails in CI. That covers vendor-contracts bundle-scan, e2e-fullstack p5-1/p5-2, and frontend/fullstack.
4. **The harness accounting makes infra failures look like test failures, and test absences look like nothing.** Vitest file-level failures turn into N × NOT_RECORDED plus a forced exit 1. A step break hides later steps. Node-test campaigns (e2e-fullstack) have no reconcile at all, so 14 of 30 tests silently vanished under exit 130.
5. **e1a42092 → cb99ded0.** A large cross-area "restore" was reverted 10 hours later with no message. At least 4 of its pieces are still required: the abo 404 JSON body, the JCS issuer migration, `Buffer` → `atob`, and the p7-2-stack process-group handling. It was not re-applied in 953e5e6e.
6. **Parallel, divergent fix lines.** `ai/reg-fixes` (17 commits, unmerged) solves the same isolated-storage and alias problems differently (DO-alarm gating, `[alias]` in the main wrangler.tomls). HEAD went with an email stub, a pool upgrade, and `retry: 1`.

---

## 1. Commit-by-commit table (bdb78457..953e5e6e, oldest at bottom)

Tag legend: **[PROD]** = changes production `src/`; **[EXPECT]** = flips test expectations; **[SCHEMA]** = migration/snapshot; **[HARNESS]** = governor/reporting; **[ENV]** = CI install/workflow.

| Commit | Time (10-xx) | Intent (message) | Key files | Side effects / campaigns it can break |
|---|---|---|---|---|
| **953e5e6e** | 15 09:57 | Fix CI flakiness: email stub, pool upgrade, deterministic clock | `ai-platform/test/stub-send-email-binding.ts` (new), imported in `test/setup-isolate-config-cache.ts` and `test/e2e/setup.ts`; `ai-platform/package.json`/lock: `@cloudflare/vitest-pool-workers` 0.8.71→**0.12.21**; `retry: 1` in `vitest.workers/e2e/version-matrix` configs; `clockNowMs` in `src/worker.ts`, `src/rollup/index.ts`, `src/vendor/entrypoint.ts`; sleep→poll in tests | **[PROD][ENV]** Pool upgrade **only in ai-platform**. abo and vendor-contracts remain on 0.8.71 while abo configs import `ai-platform/test/pin-workerd-compatibility-date.ts`, which resolves `miniflare` from **ai-platform/node_modules** (the newer miniflare). That creates a version skew across areas. `retry: 1` hides genuine flakes and doubles the runtime of broken tests. The email stub is not applied in abo's pool configs. It does **not** fix the request_fingerprint fallout, which predates it. |
| **cb99ded0** | 15 06:42 | Revert "Restore CI campaign fixes" | Reverts all of e1a42092 | Re-breaks abo/p7-2 404 body, JCS billing token, `Buffer` in workerd, and p7-2 stack spawn. The revert has no explanation (see §2). |
| **e1a42092** | 14 20:45 | Restore CI campaign fixes | abo/src/worker.ts, backend migration `20261014170000_canonical_billing_jwt_json.sql`, backend/tests/issuer_rpc.sql, e2e/fullstack dart+mjs harness, vendor-contracts token-claims.ts, test/harness test | Content appears in **no prior commit**; it was restored from an uncommitted working copy. It spans 4 areas, so a regression in any of them makes reverting all of it attractive (see §2). |
| **771ceed7** | 14 16:19 | Fixing rest of ai platform npm-tests | **[SCHEMA]** new `migrations/20261014120000_ai_request_idempotency_fingerprint.sql` + `test/schema.snap.sql`; **[PROD]** admission, quota-do, journal, pipeline (`hashCanonicalJson` fingerprint), `worker.ts` (`assertAdmissionArgs`; `branchId` must be a string), `errors.ts` (`idempotency_conflict`→409), `manifest/index.ts` (new export `hashCanonicalJson`); **[EXPECT]** S08-045→403 allowance_exhausted, S09 replay probe→"replay"; specs/068 docs | **The biggest blast radius in the history.** (a) Only `test/journal.test.ts`, `test/system/harness.ts`, `test/e2e/harness/d1.ts` got the new migration, so `test/load/load-and-cost.test.ts` (ai-platform/load + npm-test/workers) and `abo/test/.../cross-worker-harness.ts` fail with `no such column: request_fingerprint`. (b) The snapshot puts `request_fingerprint` after `idempotency_key`, but SQLite `ALTER TABLE ADD COLUMN` appends it at the end of the stored DDL, so migrations.test.ts T-A5-13 fails. (c) The new `hashCanonicalJson` function export breaks manifest.test.ts T-A4-15 (allowlist = hashManifest, load, verifyManifestTree, verifyPublishedRegistry). (d) The fingerprint now covers the whole body, but e2e `visitSummaryInvokeBody` randomizes `visit_id`/`recorded_at`. Tests that rebuild the body for the replay (S09-068/069, S10-016/018/019, S11-013/014/015) therefore get **409 idempotency_conflict**. (e) `branchId` strictness can break abo/vendor callers that pass null. |
| **0cc4c6f6** | 14 15:21 | Fixing rest of ai platform npm-tests | quota-do `admitOnHotRow`: replay(jti) check moved **back before** idempotency; admission-credit/retention tests → "replay"/unauthenticated | **[PROD][EXPECT]** Undoes 065dca52's ordering 16 minutes later. Any test written against 065dca52 (idempotent retry with the same jti → stored answer) flips again. |
| **065dca52** | 14 15:05 | Fix campaign test failure reporting and cases | quota-do: idempotency check **before** replay; DO concurrency → `concurrency_exhausted`; admission maps DO `quota_exhausted`→`allowance_exhausted`; `coverClinic` runs alarm; **[HARNESS]** reconcile: missing → `NOT_RECORDED` + `campaign_infrastructure_error` + **forced exit_code=1**; `should_reconcile` always true for vitest; KeyboardInterrupt during reconcile → exit 130; `vitest_list_count` via Popen; new version-matrix-do config | **[PROD][EXPECT][HARNESS]** Denial-code rename ripples into e2e taxonomy tests, abo error mapping, and system failure-taxonomy-matrix. The harness change turns every file-level vitest failure into a red campaign with N NOT_RECORDED, which is correct but noisy. It also adds a second 130 source: an interrupt during reconcile. |
| **9005e4fa** | 14 13:31 | Fix campaign reporting and config cache tests | **[HARNESS]** reconcile: missing → `SKIP`/`not_executed` (previously FAIL `runner_missing_outcome`); ai-platform `npm-test` steps `continue_on_step_failure=True`; config-cache tests | Hid missing tests as SKIP (green with absences) for about 1.5 hours until 065dca52 reversed it. That is the accounting flip-flop: FAIL → SKIP → NOT_RECORDED. |
| **05919c95** | 14 12:52 | Improve AI Platform campaign failure reports | quota-do: term-exhausted **and concurrency** both → `quota_exhausted`+period_end (concurrency was wrong); `chargeStaleReservations` writes `hot.idempotency` entries **without binding**; `plan:*` capability_grant lookup; zero-TTL config-cache bypass; degraded handling; `normalizeRequestReference`; about 53k lines of committed artifacts | **[PROD]** Unbound idempotency entries later collide with 771ceed7's fingerprint binding (an unbound entry vs a bound lookup). Plan-grant lookup changes the entitlement result for abo/system tests. Large committed artifacts pollute diffs and grep. |
| **25eea3b6** | 14 11:19 | Fix AI platform E2E failures | e2e tests; `worker.ts` `replayIdempotentTerminal` uses `streamCtx.requestReference` | **[PROD]** Changes the replay reference echoed to callers, which affects abo's stored request reference. |
| **13f972f4** | 14 05:35 | Test campaign missing-result diagnostics | harness tests only | Low risk. |
| **6c80d533** | 14 05:35 | Fix AI platform campaign failures | Replay **always** returns `"replay"`; entitlement `suspended` split from installation_status; report changes | **[PROD][EXPECT]** Third replay semantics in 1 hour (deb077a6 → 5d0a687f → 6c80d533). Splitting `suspended` vs `installation_suspended` changes the taxonomy that abo and vendor-contracts consume. |
| **b68299b9** | 14 05:20 | Fix frontend fullstack test orchestration | `e2e/fullstack/test/hfl-run-flutter.mjs` (requires `e2e/fullstack/node_modules/tsx`); p7-3-stack rewritten (detached process groups); variant tomls | **[ENV]** frontend/fullstack now **needs e2e/fullstack npm deps**, but the CI frontend area installs **none**, so it fails with "H-FS stack dependencies are missing". p7-3 got process-group handling, but p7-2-stack did **not** (that was only in the reverted e1a42092). |
| **5d0a687f** | 14 04:38 | Fix ai-platform npm test failures | Replay returns the **stored answer** again; adds `suspended` taxonomy code; load test adds fallback_admission_feed migration | **[PROD][EXPECT]** Reverses deb077a6 within 1 hour. Precedent: load-and-cost gets migrations added by hand when someone notices. |
| **07615507** | 14 04:23 | Fix frontend campaign failures | Flutter UI | Isolated. |
| **c513428f** | 14 03:53 | Disable automatic CI on ai/abo-master | `.github/workflows/ci.yml` | **[ENV]** From here on there is no CI feedback per commit. The 20 following commits were validated only locally, where the environment differs (see trap T7). |
| **396ecfa7** | 14 03:42 | Add campaign run comparison workflow | workflow | Low. |
| **dcc63d70** | 14 03:34 | Fix ABO cross-worker campaign failures | abo import-boundary re-exports via provider/registry; **edits applied migration** `ai-platform/migrations/20260803120000_token_contract.sql` → `INSERT OR IGNORE` | **[SCHEMA]** Edits a historical migration. Persisted D1 that already applied it won't re-run. `?raw` importers get the new text, but `wrangler d1 migrations apply` on persisted state does not. Local and CI then diverge. |
| **deb077a6** | 14 03:33 | Fix ai-platform npm-test failures | Replay → `"replay"` with no stored answer; removes replay deletion on settlement; drops text_delta from replay | **[PROD][EXPECT]** Start of the replay ping-pong. |
| 89ed6442 | 14 03:12 | Fix storage fixture conflict compatibility | backend fixtures | backend/all. |
| 28f64e2d | 14 03:10 | Improve campaign log artifacts | harness | Low. |
| 8494b4a5 | 14 02:44 | Improve campaign workflow reporting | workflow/report | Low. |
| 175045be | 14 02:28 | Merge origin/ai/abo-master | — | Merge point; the commits arrived locally via `pull --all`, so the revert happened on another machine or agent. |
| 5752531d | 14 02:27 | Version Quota DO test RPCs | quota-do test RPC | abo cross-worker + ai-platform DO tests share these RPCs. |
| 258670cc | 12 10:00 | Enhancing tests view on CI | CI view | Low. |

### Unmerged parallel branch `ai/reg-fixes` (forks at bdb78457; **0 commits reachable from HEAD**)

| Commit | Intent | Conflict / duplication with HEAD line |
|---|---|---|
| fd3ad546 | Inline-ship coverage outbox in test mode | Another way to fix "unshipped mirrors"; HEAD used `runAlarm` in coverClinic (065dca52). |
| eab34f06 / 96798a27 | `DISABLE_DO_ALARMS` gate + `disarmAlarm` in drain (isolated-storage cascade) | HEAD solved the same cascade with an email stub, the pool upgrade, and `retry:1`. Two incompatible strategies. |
| 08bd1586 | `[alias] vendor-contracts = "../packages/vendor-contracts/src/index.ts"` in `ai-platform/wrangler.toml` and `abo/wrangler.toml` | **Directly relevant to the bundle-scan and p5-1 failures**, but an alias fixes only esbuild bundling. It does not fix Node/tsx imports (p5-2) or vitest (which ignores wrangler `[alias]`). |
| cdcbf20e | Run #210 clusters: DO gate, alarm wedge, term_id drift, replay/taxonomy | Its replay/taxonomy decisions differ from HEAD's final state, so cherry-picking it re-opens the ping-pong. |
| df9fc1aa | abo vitest version-matrix `resolve.alias` for N+1 | Needed if abo version-matrix fails on resolution. |
| 4db25211 / 742c74a6 | Settle platform DO alarms in abo grant cross-worker / P4.5-09 | Depends on eab34f06's gate. |
| 6d708b30 | abo `run_cross_worker` `continue_on_step_failure=True` | **Still needed**: HEAD's abo cross-worker breaks before platform-throw, so P4.2-03 is NOT_RECORDED. |
| e18049fb | abo paymob import-boundary fix | HEAD solved it differently in dcc63d70 (re-exports via provider/registry). |
| fb1e512a / 18c5471b / c1ab7829 / eb47b49b + reverts a1047c52/e6a706be | abo paymob/intention tweaks, two reverted | Another revert pair with no explanation. |
| eb20f33a | Disable push CI | Duplicated by c513428f. |

---

## 2. e1a42092 ("Restore CI campaign fixes") vs cb99ded0 (its revert)

**Why it was reverted:** there is no explanation in the message or anywhere in history. Circumstantial evidence:
- It touched four areas at once: abo, backend, e2e-fullstack, and vendor-contracts.
- It added a backend migration and a backend test that asserts it, so backend/all depends on the migration being present in the Supabase test DB.
- Its p7-2-stack rewrite spawns wrangler via `process.execPath + node_modules/wrangler/bin/wrangler.js`. That needs `e2e/fullstack/node_modules/wrangler`, which only the e2e-fullstack area installs.

Any one of these going red would motivate a blanket revert. **Undetermined:** which campaign actually regressed.

| File in e1a42092 | Change | Still needed at HEAD? | Coupling / risk if re-applied |
|---|---|---|---|
| `abo/src/worker.ts` | GET `/v1/checkouts` without `open=1` → `clinicErrorResponse("not_found",404,version)` instead of `emptyNotFound()` | **Yes.** p7-2 `assertAboNotFound` does `response.json()` and checks `body.code==="not_found"`. | abo system/version-matrix tests that assert an empty 404 body must be checked; grep for `emptyNotFound` expectations. |
| `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql` | Adds `auth_internal.canonical_issuer_jwt_json(jsonb)` (RFC 8785 JCS) and redefines `auth_internal.issue_billing_token` | **Yes.** The current issuer uses `jsonb_build_object(...)::text` (spaces after `:`/`,`), while vendor-contracts `validateTokenClaims` requires byte equality with `canonicalize()`. | Fixes **billing only**. `issue_feed_token` (audience `ai-platform-feed`, validated strictly in `ai-platform/src/worker.ts` ≈ line 2234) is still non-canonical. `issue_ai_token` survives only because `identity/index.ts` parses it leniently via `JSON.parse`. |
| `backend/tests/issuer_rpc.sql` | JCS escaping test + canonical billing token assertion | Yes, with the migration | Couples backend/all to the migration above; they must land together. |
| `e2e/fullstack/dart/bin/session_jwt_capture.dart` | Uses raw RPCs instead of frontend `SupabaseAatMintPort`/`BillingTokenClient`/`AboClient` | Probably (pure-Dart compatibility; unverified) | The frontend classes still exist, so this is a choice rather than a forced change. |
| `e2e/fullstack/test/p7-2-stack.mjs` | wrangler via `process.execPath`+`wrangler.js`; **detached process group + group kill**; spawn/exit detection in `waitForHttp` with Host header; `--var` flags; paymob `--persist-to`; `prepareAboD1` seed+copy; idempotent org/branch (handles `ORG_ALREADY_EXISTS` via psql); `set_active_organization`; `ensurePlatformActiveCoverage` (signed grant via harness `/vendor-call`) | **Yes, most of it.** The process-group handling is the leading hypothesis for the e2e-fullstack exit 130 and "Address already in use :8787". | Needs `e2e/fullstack/node_modules/wrangler`. It must also stay consistent with the p7-3-stack rewrite in b68299b9. |
| `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` | `org` → `org_id` (matches `abo/migrations/0002_checkout.sql`); schema-valid context + coverage seed | **Yes** | — |
| `e2e/fullstack/test/wrangler-persist.mjs` | WAL checkpoint before copy; wipes seed in `preparePlatformD1`; `execPlatformD1Sql` writes to the runtime D1 file; `prepareAboD1` | **Yes** (seed copy without a checkpoint loses writes) | Does **not** solve concurrent `migrations apply` on the shared `.wrangler/d1-seed` when files run in parallel (see T9). |
| `packages/vendor-contracts/src/token-claims.ts` | `Buffer.from` → `atob` | **Yes.** No wrangler.toml sets `compatibility_flags = ["nodejs_compat"]`, so `Buffer` is undefined in workerd. | `packages/vendor-contracts/src/receipt.ts:135` has the same `Buffer.from(padded,"base64")` and was **not** fixed. |
| `test/harness/test_campaign_live_stats.py` | Tests for `apply_campaign_stats` without a queue | Optional | — |

**Verdict:** re-apply e1a42092 **selectively and per area**, not as one blob. Fix the remaining siblings in the same change: `receipt.ts` Buffer and the `issue_feed_token` canonicalization.

---

## 3. Coupling-point matrix (file → campaigns → invariants)

| Shared file / artifact | Campaigns that depend on it | Invariant that must hold |
|---|---|---|
| `ai-platform/migrations/*.sql` | ai-platform npm-test (unit+workers), load, e2e, version-matrix(-do); abo cross-worker, system, version-matrix; e2e-fullstack p5-*, p7-*; vendor-contracts (via bundle); frontend/fullstack (via p7-3-stack) | **Every** consumer applies the **full** ordered set. About 42 test files hand-list migrations via `?raw`. Only `cohort-activate-promote.test.ts` (`import.meta.glob`), `context-request.test.ts` (readdir), and `migrations.test.ts` (wrangler apply) are dynamic. Never edit an applied migration (dcc63d70 did). |
| `ai-platform/test/schema.snap.sql` | ai-platform npm-test T-A5-13 | Exact text of the sqlite_master DDL after migrations. `ALTER TABLE ADD COLUMN` columns go **at the end** of the CREATE TABLE text (see `routing_policy` for the pattern). |
| `ai-platform/src/manifest/index.ts` exports | ai-platform npm-test T-A4-15 | Function exports ⊆ {hashManifest, load, verifyManifestTree, verifyPublishedRegistry}. Put new helpers (e.g. `hashCanonicalJson`) in another module or extend the allowlist deliberately. |
| `ai-platform/src/quota-do/index.ts::admitOnHotRow` (order of replay / idempotency / term / concurrency checks; `hot.idempotency` lifecycle) | ai-platform npm-test (admission-credit, retention, quota-do, pipeline), e2e S08–S12, system (failure-taxonomy-matrix, quota-admission-interplay, golden-journey); abo cross-worker (grant/settle); e2e-fullstack p7-2 | **One written spec**: (1) same jti + same idempotency key + same fingerprint → ?; (2) same jti, different key → ?; (3) different jti, same key, different fingerprint → 409. Settlement and release currently delete `hot.idempotency` (≈ line 1620), so replays after settlement go to the D1 journal path. `chargeStaleReservations` writes entries without binding, so the fingerprint comparison must handle unbound entries. |
| Denial codes (`errors.ts`, taxonomy, admission mapping) | ai-platform e2e taxonomy tests, system failure-taxonomy-matrix, abo error mapping, vendor-contracts taxonomy | Fixed vocabulary: `allowance_exhausted` vs `quota_exhausted` vs `concurrency_exhausted`, `suspended` vs `installation_suspended`. Changed 4 times; must be frozen. |
| Request fingerprint (`hashCanonicalJson` over the invoke body) | e2e S09/S10/S11 replay tests; `test/e2e/harness/clinic.ts::visitSummaryInvokeBody` | Replay tests must **reuse the exact body** (S09-067 does and passes). Otherwise the fingerprint must exclude volatile context fields. Decide one; don't do both. |
| `ai-platform/src/worker.ts::assertAdmissionArgs` (`branchId` string) | abo cross-worker, e2e-fullstack p5-2 (VendorEntrypoint), system vendor-entrypoint | All callers pass a string `branchId`; null/undefined → explicit error. |
| `packages/vendor-contracts/src/token-claims.ts`, `receipt.ts` | vendor-contracts node+workers; ai-platform (feed/billing token validation); abo; e2e-fullstack p7-2/p7-3 | Runs in workerd **without nodejs_compat**: no `Buffer`. Byte-exact JCS comparison of the token payload. |
| `backend/supabase/migrations/*issue_*_token*` | backend/all (issuer_rpc.sql), e2e-fullstack p5-1/p7-*, frontend/fullstack | Issuer output = `canonicalize(claims)` bytes, for **billing and feed** (and AI if it's ever strict). |
| `vendor-contracts` package resolution (raw TS `file:` dep) | vendor-contracts bundle-scan (E2E-P2.2-08); e2e-fullstack p5-1 (bundle) and p5-2 (Node import of `ai-platform/src/vendor/entrypoint.ts`); abo/ai-platform vitest | Resolvable in **each** consumer's environment. esbuild/wrangler: `[alias]` **or** `ai-platform/node_modules` installed. Node/tsx: needs `ai-platform/node_modules`; alias doesn't help. Vitest: ignores wrangler `[alias]`, needs `resolve.alias` or the install. |
| `.github/scripts/setup-campaign-area.sh` `npm_dirs` | All CI campaigns | frontend: none; ai-platform: vendor-contracts, ai-platform; abo: vendor-contracts, ai-platform, abo; e2e-fullstack: vendor-contracts, e2e/fullstack (**no ai-platform**, **no abo**); vendor-contracts: vendor-contracts only (**no ai-platform**). Each must match what the area's tests import or execute. |
| `ai-platform/test/pin-workerd-compatibility-date.ts` (imports `miniflare`) | ai-platform all vitest configs; **abo** workers/cross-worker/platform-throw/version-matrix configs | Resolves `miniflare` from `ai-platform/node_modules` even for abo. After 953e5e6e that is the 0.12.21 pool's miniflare, while abo runs pool 0.8.71: a cross-area version skew. Requires ai-platform to be installed in the abo area (it is). |
| `@cloudflare/vitest-pool-workers` version | ai-platform (0.12.21), abo (0.8.71), vendor-contracts (0.8.71) | Same major across areas, or explicitly isolated. Isolated-storage semantics differ between versions. |
| `ai-platform/vitest.*.config.ts` `retry: 1` | ai-platform workers / e2e / version-matrix / load (shares workers config) | Retries mask nondeterminism. The harness keeps the **latest** PASS/FAIL per name, so a flake that passes on retry looks green. |
| `e2e/fullstack/test/variant/*.toml` | e2e-fullstack p7-3 (N/N+1, DO receiver, feed window), frontend/fullstack (desktop window) | Each D1-using variant needs `migrations_dir` (only `*-desktop-window.toml` have it; `platform-n-plus-1` → "No migrations present"), and `[alias]` where bundling needs it (`platform-worker-n.toml` has none). |
| `e2e/fullstack/.wrangler/d1-seed`, ports 8787-8790/9230/9231 | All e2e-fullstack node-test files, frontend/fullstack | Exactly **one** stack at a time per checkout. `prepare_fullstack_e2e_stack` wipes `.wrangler` and kills listeners only once, before the run. |
| `e2e/fullstack/run_campaigns.py` all-manual (`node --import tsx --test` on all `*.test.mjs`) | e2e-fullstack all-manual | Must run files **serially**. `campaign_config.py` adds `--test-concurrency` only when `test_concurrency` is set; all e2e-fullstack JSONs have `null`, so node's default runs about `availableParallelism()-1` files concurrently. |
| `abo/run_campaigns.py::run_cross_worker` (`_BUILD`, `_CROSS_WORKER`, `_PLATFORM_THROW`) | abo cross-worker, cross-worker-main, platform-throw | No `continue_on_step_failure`, so a cross-worker failure skips platform-throw and E2E-P4.2-03 becomes NOT_RECORDED. `abo/scripts/build-platform-for-hxw.mjs` bundles ai-platform (`wrangler deploy --dry-run --env development`), so every ai-platform bundling break also breaks abo. |
| `frontend/tool/discover_tests.py` UNIT_TEST_ROOTS (includes `test/integration`) | frontend/all (unit) | `@Tags(['fullstack'])` tests (administrator_billing/subscription_fullstack_test.dart) must be excluded from unit (`--exclude-tags fullstack`); they currently run without a stack. Pre-existing. |
| `frontend/tool/run_campaigns.py::_run_fullstack` | frontend/fullstack | Requires `e2e/fullstack/node_modules/tsx/dist/loader.mjs`; returns 1 with 0 tests if it's missing. |

---

## 4. Harness accounting rules (as implemented at HEAD)

**Status dedupe (`test/harness/test_result_stats.py::dedupe_test_statuses`).** The **latest** PASS/FAIL per test name wins; other statuses are ignored for counting. Combined with vitest `retry: 1`, a test that fails then passes counts as PASS. `stats_from_summary_payload` trusts the summary counts when they match the list or the list is empty.

**Vitest reconcile (`test/harness/campaign_vitest_reconcile.py::reconcile_vitest_summary_log`).**
- Applies only to `kind: vitest` campaigns, or commands containing "vitest" (065dca52 made `should_reconcile` always true for these).
- Gets the expected label set from `npx vitest list` (`vitest_list_count.py`). If `vitest list` fails or times out, it returns `None` and **no reconcile happens**, so missing tests are silently uncounted.
- Drops summary entries whose label isn't in the set; keeps PASS/FAIL/SKIP.
- Every label with no outcome in either the summary or the vitest JSON report becomes `status: NOT_RECORDED`, `failure_kind: infrastructure_error`.
- If any are NOT_RECORDED, it sets `not_recorded`, `campaign_infrastructure_error: true`, `runner_exit_code` = original, and **forces `exit_code: 1`**.
- History: this rule flipped FAIL (`runner_missing_outcome`) → SKIP (`not_executed`, 9005e4fa; that hid absences) → NOT_RECORDED + forced exit 1 (065dca52).

**Why file-level failures become NOT_RECORDED.** `ai-platform/run_campaigns.py::_report_tests` keeps only `assertionResults` with `status == "failed"`. When `beforeAll` or an import throws, vitest marks the cases `skipped` and the *file* failed, so the report has `{"tests": []}`. All cases in the file become NOT_RECORDED.
- Example, ai-platform/load: beforeAll hits `no such column: request_fingerprint`; vitest shows "10 skipped, 1 file failed"; the governor shows "runner exited with code 1 before reporting a result"; the stall-guard artifact row is filtered out. The result is 0 passed, 0 failed, 10 NOT_RECORDED, exit 1.

**Exit 1 with 0 failing tests.** This happens when the runner exits non-zero before any test result: missing deps (frontend/fullstack), a build failure, or a file-level failure where reconcile could not list the tests. Also when reconcile forces 1 because of NOT_RECORDED.

**Exit 130.** There are two sources:
- (a) A KeyboardInterrupt in the governor (`common.py` SIGINT handler) sets `interrupted: true`, including an interrupt *during reconcile* (065dca52 records `reconciliation_interrupted`).
- (b) The **child** exiting with 130. e2e-fullstack/all-manual shows `exit_code: 130, interrupted: false`, so the node test runner itself returned 130: some process in its group received SIGINT. `_subprocess_popen_kwargs` starts a new session only for top-level children. p7-2-stack spawned `npx wrangler dev` **not detached** at HEAD, and e1a42092 added detached + group-kill.
- Leading hypothesis (**undetermined**): a SIGINT sent to wrangler's group during teardown or a port clash reached the node test runner.

**Node-test campaigns (e2e-fullstack) have no reconcile.** Tests that never ran are not NOT_RECORDED. all-manual recorded 16 of 30 attempted, and 14 silently vanished. "total" comes from static counts, so the gap shows only as `attempted < total`.

**Step sequences (`common.py::run_subprocess_sequence`).** `continue_on_step_failure` defaults to False, so the sequence **breaks at the first failing step**. Later steps' tests become NOT_RECORDED (vitest) or vanish (non-vitest).
- ai-platform npm-test: True since 9005e4fa.
- abo cross-worker: False, so P4.2-03 is NOT_RECORDED.
- e2e-fullstack all-ci: separate sequential p5-1 and p5-2 steps.

**Area → job result.**
- `github_campaign_report.area_has_incomplete_or_failed_campaigns`: true if no subcampaigns were picked, or **any** subcampaign's `exit_code != 0`.
- `report_area_exit_code`: 1 if any `exit_code not in (None, 0)` or incomplete.
- ci.yml fails the job if the campaign exit ≠ 0 **or** report_code ≠ 0.
- So one subcampaign with exit 1 and 0 failed tests fails the whole area.

**Full-area selection (`campaign_selection.full_area_minimal_picks`).** Runs only the **root** subcampaigns of `campaign_tree.SUBCAMPAIGN_PARENT`.
- ai-platform: `npm-test` (unit + workers), `load`, `e2e`, `eval`, `eval-all`, `version-matrix`. `test/load` also runs inside npm-test/workers, so the load breakage is **counted twice**.
- e2e-fullstack: `all-manual` **and** `all-ci` are both roots, so p5-1 and p5-2 run twice (once concurrently, once serially).
- frontend: `all` and `fullstack`.
- abo: `cross-worker`, `system`, `import-boundary`, `version-matrix`.

**Per-test log attribution in flutter campaigns can be off.** E2E-P6.3-01's log file is named `002-e2e-p6-4-01…`. Read the failure text, not the log filename.

---

## 5. Prior CI analysis docs: what was wrong

The only prior analysis doc is the repo-root `ci-failure-analysis-run-38695681551.md` (the briefing said not to trust it). A `git log --all --diff-filter=A` search finds no other CI analysis docs. `ai-platform/test/e2e/reports/stage-*-failures.md` are catalog reports, not analyses.

| Prior conclusion | Actual cause (verified against logs and source) |
|---|---|
| vendor-contracts E2E-P2.2-08: "bundle still flags testkit code" | The bundle **fails to build**: `Could not resolve "vendor-contracts"` ×12. In the vendor-contracts area `ai-platform/node_modules` isn't installed and the main `ai-platform/wrangler.toml` has no `[alias]`. No `ai-platform/src` file imports testkit. |
| P7.2 "duplicate column canary_installation_ids / table service_key already exists" = migrations re-applied over an already-migrated persisted seed | The harness wipes `.wrangler` before the run. The real cause is **concurrent** `migrations apply` on the same `.wrangler/d1-seed`, plus "Address already in use 127.0.0.1:8787", because all-manual runs `*.test.mjs` files in parallel (node default concurrency; `test_concurrency: null`). |
| Schema snapshot mismatch = "smoking gun" of a migration ordering bug | The snapshot is simply **wrong**. 771ceed7 placed `request_fingerprint` mid-table, but ALTER appends it at the end. The migration itself is fine. |
| T-A4-15 manifest export failure = cascade from other failures | Direct cause: 771ceed7 added the `hashCanonicalJson` export to `manifest/index.ts`, which the allowlist rejects. |
| e2e 409 on replay = product replay/idempotency bug | Test-data issue. The new fingerprint covers the full body, and the tests rebuild bodies with a random `visit_id`/`recorded_at` for the replay. S09-067, which reuses the body, passes. |
| Fix = "add ai-platform to npm_dirs" (for e2e-fullstack) | Partially right. vendor-contracts **also** needs it (bundle-scan), and frontend needs e2e/fullstack deps (frontend/fullstack). all-manual concurrency also needs fixing, otherwise P7.2 still collides. p5-2 needs the install specifically, because an alias can't fix a Node/tsx import. |

---

## 6. Traps the consolidated fix must avoid

- **T1 — Hand-maintained migration lists.** Adding a migration without updating about 42 `?raw` lists breaks load, abo cross-worker, and abo system silently and in different areas. Fix: one shared loader (e.g. `import.meta.glob("../migrations/*.sql", {query:"?raw", eager:true})` sorted by name) used by **all** harnesses, including `abo/test/**/cross-worker-harness.ts` and `ai-platform/test/load/load-and-cost.test.ts`. At minimum, add `20261014120000_ai_request_idempotency_fingerprint.sql` everywhere.
- **T2 — Snapshot column position.** Regenerate `schema.snap.sql` from real sqlite_master output, not by hand-editing. Columns added by ALTER go at the end.
- **T3 — Manifest export allowlist.** Don't export new helpers from `manifest/index.ts`. Move `hashCanonicalJson` to a utility module, or deliberately extend T-A4-15.
- **T4 — Fingerprint vs randomized test bodies.** Choose one: make replay tests reuse the identical body (preferred; matches S09-067), or exclude volatile context from the fingerprint. Don't change both, and don't "fix" it by dropping the 409, because the conflict is a correct product behavior.
- **T5 — Replay-order ping-pong.** Write the admission-order spec first (replay jti vs idempotency key vs fingerprint vs term vs concurrency), then make **all** tests (ai-platform unit, e2e, system, abo) agree. Never flip a test expectation just to make one campaign green. The history shows 6 reversals in about 13 hours.
- **T6 — Denial-code churn.** Freeze the taxonomy (`allowance_exhausted`/`quota_exhausted`/`concurrency_exhausted`, `suspended`/`installation_suspended`) and grep every consumer (abo, vendor-contracts, system matrix) before renaming.
- **T7 — The CI environment is not your machine.** Push-CI was disabled at c513428f, and every later commit was validated locally with all `node_modules` present. The per-area `npm_dirs` gaps are: vendor-contracts lacks ai-platform; e2e-fullstack lacks ai-platform (and abo if needed); frontend lacks e2e/fullstack. Fix `setup-campaign-area.sh` **and** verify by simulating an area-only install.
- **T8 — An alias is not a universal resolution fix.** `[alias]` in wrangler.toml fixes esbuild bundling only (bundle-scan, p5-1, the hxw build). Vitest ignores it (it needs `resolve.alias`), and Node/tsx imports (p5-2 importing `ai-platform/src/vendor/entrypoint.ts`) need the actual install.
- **T9 — all-manual concurrency.** Set `test_concurrency: 1` in the e2e-fullstack all-manual config, or give each file its own persist dir and ports. Without this, the P7.2 migration collisions, port clashes, and probably the exit 130 remain no matter what else is fixed.
- **T10 — Step breaks hide tests.** abo `run_cross_worker` needs `continue_on_step_failure=True` (as in reg-fixes 6d708b30), or P4.2-03 stays NOT_RECORDED whenever any cross-worker case fails.
- **T11 — File-level failures look like N test failures.** One `beforeAll` crash yields 10 NOT_RECORDED plus exit 1. Read `output.log`, not the NOT_RECORDED count, and fix the root cause once.
- **T12 — Node-test campaigns don't count absences.** e2e-fullstack can "improve" by running fewer tests. Check `attempted == total`.
- **T13 — Re-applying e1a42092 as one blob.** It couples backend/all (new migration + test), e2e-fullstack (needs `node_modules/wrangler`), abo, and vendor-contracts. Apply it per area. Bring along the unfixed siblings: `receipt.ts:135` `Buffer`, and `issue_feed_token` JCS (strictly validated feed audience).
- **T14 — Pool/miniflare skew.** ai-platform is on vitest-pool-workers 0.12.21; abo and vendor-contracts are on 0.8.71. abo configs import a helper that pulls `miniflare` from ai-platform/node_modules. Align versions or stop sharing the helper. The SEND_EMAIL stub from 953e5e6e is not wired into abo's pool configs.
- **T15 — Edited historical migration** (`20260803120000_token_contract.sql`, dcc63d70). Persisted D1 state and `?raw` consumers diverge. Prefer a new forward migration.
- **T16 — Divergent unmerged branch `ai/reg-fixes`.** Don't cherry-pick wholesale. Its alarm-gating, replay, and taxonomy choices conflict with HEAD's. Take only orthogonal pieces: the abo `continue_on_step_failure`, the abo version-matrix `resolve.alias`, and possibly the wrangler `[alias]`.
- **T17 — `retry: 1` masks nondeterminism.** With "latest status wins" dedupe, retried flakes report green. Don't treat a green run with retries as proof of a fix; check for retried tests in the vitest JSON.
- **T18 — Variant tomls.** `platform-n-plus-1.toml`, `platform-do-receiver.toml`, `platform-feed-window.toml`, and `abo-n-plus-1.toml` have D1 but no `migrations_dir`. `platform-worker-n.toml` has no `[alias]`. P7.3 variants fail with "No migrations present".
- **T19 — Double counting.** ai-platform `load` and npm-test/workers both run `test/load`, and e2e-fullstack `all-ci` and `all-manual` both run p5-1 and p5-2. One root cause shows up as multiple red subcampaigns; don't fix them separately.
- **T20 — frontend unit runs fullstack-tagged tests.** Add `--exclude-tags fullstack` to the unit/all discovery. This is pre-existing and unrelated to the recent churn, so don't attribute it to recent commits.
- **T21 — `branchId` strictness (771ceed7).** Any caller passing null or a number now fails at `assertAdmissionArgs`. Check the abo and VendorEntrypoint callers.

## 7. Undetermined

- The actual reason for cb99ded0 (which campaign regressed after e1a42092).
- The exact SIGINT source behind e2e-fullstack all-manual exit 130 (`interrupted: false`, so it came from a child). The leading hypothesis is a non-detached `npx wrangler dev` group signal during teardown or a port clash.
- Whether the abo pool 0.8.71 + ai-platform miniflare (0.12.x line) skew causes any current abo failure (abo/system passed 23/23, so probably not yet).
- Whether `session_jwt_capture.dart` must use raw RPCs (pure-Dart compatibility) or just prefers them.
