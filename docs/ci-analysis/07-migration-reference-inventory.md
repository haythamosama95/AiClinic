# ai-platform/migrations reference inventory (read-only scan, 2026-10-15)

Repo: `C:\Users\haosama\Downloads\resources`. Scan covered `ai-platform/**` (tests, configs, wrangler.toml), `abo/**`, `e2e/fullstack/**`, `frontend/**`, `packages/**`, `test/**`, `.github/**`, plus repo-wide regex sweeps for `?raw` imports, `readdirSync`/`readFileSync` of migration dirs, `migrations_dir`, and `20261014120000`. `node_modules` excluded. Read-only; no repo files were edited.

`FP` = `20261014120000_ai_request_idempotency_fingerprint.sql` (the new fingerprint migration).
"beforeAll" / "beforeEach" / "test body" = where the SQL execution call lives. "module top-level" = none found (all execution happens inside vitest hooks or node scripts).

## 1. Full sorted file list of `ai-platform/migrations/` (24 files)

```
20260731120000_platform_schema.sql
20260802100000_capability_grant_lifecycle.sql
20260803100000_routing_policy_canary.sql
20260803120000_token_contract.sql
20260805120000_f3_retention_indexes.sql
20260805180000_h3_conversation_index.sql
20260805190000_routing_policy_status.sql
20260807120000_kill_switch.sql
20260821120000_grace_admission_queue.sql
20260821130000_entitlement_installation_unique.sql
20260911120000_plan_catalogue.sql
20260911180000_usage_rollup_quota_weight.sql
20260911200000_invoice.sql
20261003120000_operator_credential_and_platform_alert.sql
20261003130000_issuer_key_tenant_binding.sql
20261003140000_plan_version_paid_grant_coverage.sql
20261006120000_usage_term.sql
20261006130000_ceiling_policy.sql
20261006140000_grant_void.sql
20261006150000_transfer.sql
20261006160000_fallback_admission_feed.sql
20261006170000_drop_invoicing.sql
20261006170100_drop_plan_entitlement.sql
20261014120000_ai_request_idempotency_fingerprint.sql
```

Short keys used below (order = chain order above):
- SCH=20260731120000_platform_schema, CGL=20260802100000_capability_grant_lifecycle, CAN=20260803100000_routing_policy_canary, TC=20260803120000_token_contract, RI=20260805120000_f3_retention_indexes, CI=20260805180000_h3_conversation_index, RS=20260805190000_routing_policy_status, KS=20260807120000_kill_switch, GAQ=20260821120000_grace_admission_queue, EIU=20260821130000_entitlement_installation_unique, PC=20260911120000_plan_catalogue, URQ=20260911180000_usage_rollup_quota_weight, INV=20260911200000_invoice, OC=20261003120000_operator_credential_and_platform_alert, IK=20261003130000_issuer_key_tenant_binding, PGC=20261003140000_plan_version_paid_grant_coverage, UT=20261006120000_usage_term, CP=20261006130000_ceiling_policy, GV=20261006140000_grant_void, TR=20261006150000_transfer, FAF=20261006160000_fallback_admission_feed, DI=20261006170000_drop_invoicing, DPE=20261006170100_drop_plan_entitlement, FP=20261014120000_ai_request_idempotency_fingerprint.

`ALL` = all 24 files (SCH..FP).

## 2. Harnesses / execution helpers (files that own the full migration chain)

| File | Mechanism | Migration files referenced (in order) | FP? | Import lines | Execution lines | Phase |
|---|---|---|---|---|---|---|
| `ai-platform/test/system/harness.ts` | raw-import | ALL (SCH,CGL,CAN,TC,RI,CI,RS,KS,GAQ,EIU,PC,URQ,INV,OC,IK,PGC,UT,CP,GV,TR,FAF,DI,DPE,FP) | YES | 66–89 | `MIGRATION_SQL` array L253; `applyAllMigrations` L325–341 (loop L329; SQL run via `db.prepare(...).run()` in `applySql`); consumed by 19 system tests in their `beforeAll` (see §3) | beforeAll (callers) |
| `ai-platform/test/e2e/harness/d1.ts` | raw-import | ALL (SCH,CGL,CAN,TC,RI,CI,RS,KS,FAF,EIU,PC,URQ,INV,OC,IK,PGC,UT,CP,GV,TR,DI,DPE,FP) | YES | 1–23 | `MIGRATION_SQL` L31–54; `applySql` L76–88 (`db.prepare(statement).run()`); `applyAllMigrations` L94–100; `bootstrapE2e` L385–388 calls it; consumed by all e2e stage tests in `beforeAll` (see §4) | beforeAll (callers) |
| `ai-platform/test/e2e/harness/index.ts` | re-export (indirect raw-import) | ALL via `d1.ts` | YES (indirect) | 48 (`MIGRATION_SQL` re-exported) | via `d1.ts` `applyAllMigrations` | beforeAll (callers) |
| `ai-platform/test/split-sql-statements.ts` | execution helper only (no migration references) | none | n/a | n/a | `splitSqlStatements` L2; `applySqlStatements` L46 (`db.prepare(...).run()` per statement) — used by unit tests below | helper |

## 3. `ai-platform/test/system/*` + `ai-platform/test/version-matrix/*` — indirect via `system/harness.ts#applyAllMigrations` (all 24 migrations, FP included)

Mechanism for every row: indirect raw-import (via harness); execution = `await applyAllMigrations(env.DB)` inside `beforeAll`; FP: YES.

| File | beforeAll lines | applyAllMigrations line |
|---|---|---|
| `ai-platform/test/system/capability-lifecycle.system.test.ts` | 34 | 35 |
| `ai-platform/test/system/complimentary-grants-ceilings.system.test.ts` | 494 | 495 |
| `ai-platform/test/system/control-plane-port.system.test.ts` | 144 | 145 |
| `ai-platform/test/system/contract-version.system.test.ts` | 22 | 23 |
| `ai-platform/test/system/entitlement-grant-interplay.system.test.ts` | 38 | 39 |
| `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts` | 42 | 43 |
| `ai-platform/test/system/fallback-feed-coverage.system.test.ts` | 350 | 351 |
| `ai-platform/test/system/golden-journey.system.test.ts` | 47 | 48 |
| `ai-platform/test/system/issuer-tokens.system.test.ts` | 382 | 383 |
| `ai-platform/test/system/lifecycle-interplay.system.test.ts` | 36 | 37 |
| `ai-platform/test/system/platform-rebuild.system.test.ts` | 494 | 495 |
| `ai-platform/test/system/quota-admission-interplay.system.test.ts` | 37 | 38 |
| `ai-platform/test/system/reversal-voids-held-terms.system.test.ts` | 400 | 401 |
| `ai-platform/test/system/routing-policy-traffic.system.test.ts` | 36 | 37 |
| `ai-platform/test/system/settlement-integrity.system.test.ts` | 39 | 40 |
| `ai-platform/test/system/token-contract-rotation.system.test.ts` | 24 | 25 |
| `ai-platform/test/system/transfer-deletion.system.test.ts` | 567 | 568 |
| `ai-platform/test/system/vendor-entrypoint.system.test.ts` | 218 | 219 |
| `ai-platform/test/version-matrix/worker-do.system.test.ts` | 84 | 85 |

(`beforeEach` in these files clears tables / reseeds — it does not re-run migrations.)

## 4. `ai-platform/test/e2e/*` — indirect via `e2e/harness/d1.ts#bootstrapE2e` (all 24 migrations, FP included)

Mechanism for every row: indirect raw-import; execution = `await bootstrapE2e()` → `applyAllMigrations()` inside `beforeAll`; FP: YES.

| File | beforeAll line | bootstrapE2e line | extra |
|---|---|---|---|
| `ai-platform/test/e2e/phase-00-exemplars.test.ts` | 14 | 15 | — |
| `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts` | 41 | 42 | also `applyAllMigrations()` at L287 (restart scenario, test body) |
| `ai-platform/test/e2e/stage-00-boot-bindings-routing.test.ts` | 39 | 40 | — |
| `ai-platform/test/e2e/stage-01-auth-validation.test.ts` | 16 | 17 | — |
| `ai-platform/test/e2e/stage-03-auth-routing.test.ts` | 11 | 12 | — |
| `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts` | 30 | 31 | — |
| `ai-platform/test/e2e/stage-04-cohort-promote-deprecate.test.ts` | 24 | 25 | — |
| `ai-platform/test/e2e/stage-04-deprecate-retire-auth.test.ts` | 27 | 28 | — |
| `ai-platform/test/e2e/stage-04-entitle-happy-cohort-activate.test.ts` | 19 | 20 | — |
| `ai-platform/test/e2e/stage-05-canary-promote.test.ts` | 26 | 27 | — |
| `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts` | 53 | 54 | — |
| `ai-platform/test/e2e/stage-05-publish.test.ts` | 27 | 28 | — |
| `ai-platform/test/e2e/stage-05-rollback-serving.test.ts` | 42 | 43 | — |
| `ai-platform/test/e2e/stage-07-entitlement-filters.test.ts` | 31 | 32 | — |
| `ai-platform/test/e2e/stage-07-etag-cache.test.ts` | 32 | 33 | — |
| `ai-platform/test/e2e/stage-07-routing-identity.test.ts` | 31 | 32 | — |
| `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts` | 36 | 37 | — |
| `ai-platform/test/e2e/stage-08-size-json-headers.test.ts` | 19 | 20 | — |
| `ai-platform/test/e2e/stage-08-trace-auth.test.ts` | 26 | 27 | — |
| `ai-platform/test/e2e/stage-09-adapter-identity.test.ts` | 27 | 28 | — |
| `ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts` | 63 | 64 | — |
| `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts` | 41 | 42 | — |
| `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts` | 36 | 37 | — |
| `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` | 53 | 54 | — |
| `ai-platform/test/e2e/stage-10-route-retry-idempotency.test.ts` | 58 | 59 | — |
| `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts` | 45 | 46 | — |
| `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts` | 56 | 57 | — |
| `ai-platform/test/e2e/stage-12-get-lookup.test.ts` | 48 | 49 | — |
| `ai-platform/test/e2e/stage-12-quota-inspect-dashboard.test.ts` | 39 | 40 | — |
| `ai-platform/test/e2e/stage-12-support-lookup.test.ts` | 52 | 53 | — |
| `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts` | 53 | 54 | — |
| `ai-platform/test/e2e/stage-X-cron-flush-reconcile.test.ts` | 50 | 51 | — |
| `ai-platform/test/e2e/stage-X-grace-retention.test.ts` | 52 | 53 | — |
| `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts` | 46 | 47 | — |

## 5. `ai-platform` unit tests — direct `?raw` imports, executed in `beforeAll`

Every row: mechanism = raw-import; execution phase = beforeAll.

| File | Migration files referenced (import order) | FP? | Import lines | Execution lines |
|---|---|---|---|---|
| `ai-platform/test/admission-credit.test.ts` | SCH, GAQ, FAF, PC, PGC, UT | NO | 3–8 | 668–673 (`applyPlatformSchema`/`applySqlStatements`), beforeAll L667 |
| `ai-platform/test/capability-deprecation.test.ts` | SCH, CGL, IK, OC, PGC | NO | 3–7 | 419–423 (`applyPlatformSchema` L419, LIFECYCLE_MIGRATION_SQL L420 via alias L416), beforeAll L418 |
| `ai-platform/test/capability.test.ts` | SCH, IK, PGC, KS | NO | 3–6 | 658–661 (`applySqlStatements`), beforeAll L657 |
| `ai-platform/test/cohort-activate-promote.test.ts` | SCH, CGL, CAN, RS, KS, IK, PGC (explicit imports 3–9) **plus ALL 24** via `import.meta.glob("../migrations/*.sql", {eager:true, query:"?raw"})` L58–62 (used as `sqlBlobs` L476) | YES (via glob) | 3–9, 58–62 | 484–490 (`applyPlatformSchema`/`applySqlStatements`), beforeAll L483 |
| `ai-platform/test/config-readers.test.ts` | SCH, CGL, TC, CAN, RS, KS, IK, PGC, UT | NO | 3–11 | 182–190 (`applyPlatformSchema`), beforeAll L181 |
| `ai-platform/test/conversational-journaling.test.ts` | SCH, CI, IK, PGC, UT | NO | 3–7 | 716–720, beforeAll L715 |
| `ai-platform/test/discovery-http.test.ts` | SCH, TC, KS, IK, PGC, UT | NO | 3–8 | 330–335, beforeAll L329 |
| `ai-platform/test/entitlement.test.ts` | SCH, CGL, KS, IK, PGC | NO | 3–7 | 445–449, beforeAll L444 |
| `ai-platform/test/identity.test.ts` | SCH, TC, IK, PGC, UT | NO | 2–6 | 1052–1056 (`applyPlatformSchema`), beforeAll L1049 |
| `ai-platform/test/journal.test.ts` | SCH, UT, FP | **YES** | 3–5 | 569–571, beforeAll L568 |
| `ai-platform/test/journal-dashboards.test.ts` | SCH | NO | 3 | 291, beforeAll L290 |
| `ai-platform/test/load/load-and-cost.test.ts` | SCH, IK, PGC, UT, FAF | NO | 6–10 | 112–116, beforeAll L111 |
| `ai-platform/test/pipeline.test.ts` | SCH, CI, PC, IK, PGC | NO | 8–12 | 728–732, beforeAll L727 |
| `ai-platform/test/plan-catalogue.test.ts` | SCH, OC, IK, PGC, DI, DPE | NO | 9–14 | 191–196, beforeAll L190 |
| `ai-platform/test/rate-limit.test.ts` | SCH | NO | 3 | 269, beforeAll L268 |
| `ai-platform/test/retention.test.ts` | SCH, TC, GAQ, FAF, RI, IK, PGC, UT | NO | 4–11 | 114–121, beforeAll L113 |
| `ai-platform/test/rollup-reconciliation.test.ts` | SCH, RI, URQ, UT | NO | 3–6 | 150–153, beforeAll L149 |
| `ai-platform/test/routing-policy-canary.test.ts` | SCH, CAN, RS, OC, PGC | NO | 3–7 | 587–591, beforeAll L586 |
| `ai-platform/test/soft-threshold-routing.test.ts` | SCH, PC, IK, PGC, UT | NO | 3–7 | 820–824, beforeAll L819 |
| `ai-platform/test/support-lookup.test.ts` | SCH | NO | 3 | 232, beforeAll L231 |
| `ai-platform/test/support-purge.test.ts` | SCH, GAQ, FAF | NO | 3–5 | 199–201, beforeAll L198 |
| `ai-platform/test/token-contract-control.test.ts` | SCH, TC, IK, PGC, UT, OC | NO | 3–8 | 300–305, beforeAll L299 |
| `ai-platform/test/vendor-entrypoint.test.ts` | SCH, TC, IK, OC | NO | 5–8 | 68–71, beforeAll L67 |
| `ai-platform/test/worker-request-orchestrator.test.ts` | SCH, TC, CAN, RS, KS, FAF, PC, IK, PGC, UT | NO | 66–75 | 736–747 (inside try, beforeAll L734) |

FP direct raw-imports: only `journal.test.ts` (L5) in unit tests; the full-chain harnesses also import it (`system/harness.ts` L89, `e2e/harness/d1.ts` L23); `cohort-activate-promote.test.ts` covers it via `import.meta.glob` (L58–62).

## 6. fs-read / dynamic-directory mechanisms

| File | Mechanism | Migration files referenced | FP? | Import/dir lines | Execution lines | Phase |
|---|---|---|---|---|---|---|
| `ai-platform/test/context-request.test.ts` | fs-read (`readdirSync` + `readFileSync`) of `ai-platform/migrations/*.sql` | ALL 24 (every `*.sql` in dir, filename order) | YES (reads all files) | dir built at L97 (`join(__dirname, "../migrations")`) | readdirSync L98, readFileSync L100 (assertions L101–104: no conversation tables) | test body (`it`) |
| `ai-platform/test/prompt-registry.test.ts` | fs-read (`readdirSync` + `readFileSync`) of `MIGRATIONS_DIR` | ALL 24 (filtered to `.sql`) | YES (reads all files) | `MIGRATIONS_DIR` L20 | readdirSync L200, readFileSync L206 | test body |
| `ai-platform/test/migrations.test.ts` | other — wrangler CLI `d1 migrations apply` (local, temp persist) | ALL 24 (wrangler default migrations dir of `ai-platform/wrangler.toml` = `ai-platform/migrations`) | YES | `applyMigrations` runs `runWrangler(["d1","migrations","apply",D1_DATABASE,"--local"])` L92–96 | applied repeatedly in test bodies: L170, 182, 186, 196, 208, 218, 282, 302, 332, 364, 380; `beforeEach` L158 creates temp persist | beforeEach + test body |
| `ai-platform/test/token-contract-rotation.test.ts` | fs-read of `src/**` only (readdirSync L381, readFileSync L398) — no migration references | none | n/a | — | — | test body |
| `ai-platform/test/soft-threshold-hygiene.test.ts` | fs-read of `src/**` only (readdirSync L12, readFileSync L27) — no migration references | none | n/a | — | — | test body |
| `ai-platform/test/prompt-registry-gate.test.ts` | fs-read of prompt registry dirs only — no migration references | none | n/a | — | — | test body |

Note: `migrations.test.ts` relies on wrangler's *default* migrations dir because `ai-platform/wrangler.toml` has no `migrations_dir` key (see §8).

## 7. `abo/**` (cross-worker harness pulls the platform chain)

| File | Mechanism | Migration files referenced (order) | FP? | Import lines | Execution lines | Phase |
|---|---|---|---|---|---|---|
| `abo/test/system/cross-worker-harness.ts` | raw-import from `../../../ai-platform/migrations/` | SCH, CGL, CAN, TC, RI, CI, RS, KS, GAQ, EIU, PC, URQ, INV, OC, IK, PGC, UT, CP, GV, TR, FAF, DI, DPE (23 files — **all except FP**) | **NO** | 28–50 (`PLATFORM_MIGRATION_SQL` array L52–76) | `applyPlatformMigrations` L225–236 (loop L229; `applyPlatformSql` L166; `applySqlOnDb` L169–221 runs statements via `db.prepare(...).run()`); called from `setupCrossWorkerHarness` L851–857 and `setupPlatformCoverageFeed` L573 | beforeAll (via `setupCrossWorkerHarness` in tests) |

The abo test files that trigger this in their `beforeAll` (`await setupCrossWorkerHarness()`): `checkout.cross-worker` L177, `grant.cross-worker` L1179, `sweeps.cross-worker` L1168, `reconciliation.cross-worker` L1398, `hp-actions.cross-worker` L1156, `coverage-view.cross-worker` L25, `console-relays.cross-worker` L1583, `ops.cross-worker` L783, `configuration-relays.cross-worker` L1391, `digest-watch-rebuild.cross-worker` L1221. Their direct `?raw` imports (e.g. `0001_records.sql`, `0002_checkout.sql`, … `0009_digest_watch.sql`) are **abo/migrations**, not ai-platform migrations, so they are listed here only for completeness and excluded from the ai-platform table.

`abo/test/version-matrix/channels.system.test.ts` (imports L9–10, `applySql` L122–123, `setupHarness` in beforeAll L234) also only applies abo migrations. `abo/test/system/harness.ts` applies only abo migrations (`ABO_MIGRATION_SQL` L17–28, loop L176, `setupHarness` L508).

## 8. TOML configs

| File | Mechanism | Migration files referenced | FP? | Lines | Notes |
|---|---|---|---|---|---|
| `e2e/fullstack/test/variant/platform-desktop-window.toml` | toml `migrations_dir` | ALL 24 (wrangler applies whole dir via `d1 migrations apply`) | YES | `migrations_dir = "../../../../ai-platform/migrations"` L54 (inside `[[env.development.d1_databases]]` L50–54); `[[migrations]]` L22 is the DO class migration tag (GatewayObject), not SQL | exercised by `p7-3-06-prepare.mjs` / `p7-3-stack.mjs` via `wrangler d1 migrations apply --config ...` |
| `ai-platform/wrangler.toml` | toml — **no `migrations_dir`**; `[[migrations]]` L22 is DO `new_sqlite_classes` only | ALL 24 implicitly (wrangler default migrations dir = `ai-platform/migrations`) for `d1 migrations apply` | YES (implicit) | L22 | used by `migrations.test.ts` and `preparePlatformD1` (`p5-1`, `p5-2`, `p7-2-stack`, `p7-3-stack`) |
| `e2e/fullstack/test/variant/platform-do-receiver.toml` | toml — d1_databases **without** `migrations_dir`; `[[migrations]]` L18 = DO tag | none explicit (default dir `test/variant/migrations` does not exist) | n/a | L18, L46–48 | used with `wrangler d1 migrations apply` via `p7-3-stack.mjs` `restartPlatform` |
| `e2e/fullstack/test/variant/platform-worker-n.toml` | toml — same pattern, no `migrations_dir` | none explicit | n/a | L22, L47–49 | used via `p7-3-05.test.mjs` / `p7-3-stack.mjs` |
| `e2e/fullstack/test/variant/platform-n-plus-1.toml` | toml — same pattern, no `migrations_dir` | none explicit | n/a | L22, L50–52 | used via `p7-3-01/02.test.mjs` |
| `e2e/fullstack/test/variant/platform-feed-window.toml` | toml — same pattern, no `migrations_dir` | none explicit | n/a | L22 | used via `p7-3-03.test.mjs` |
| `e2e/fullstack/test/variant/abo-desktop-window.toml` | toml `migrations_dir` — points at **abo** migrations (`../../../../abo/migrations` L45), not ai-platform | abo migrations only | n/a | L45 | out of ai-platform scope; listed for completeness |
| `backend/supabase/config.toml` | toml `migrations_dir` — Supabase backend migrations, not ai-platform | backend migrations | n/a | — | out of scope |

## 9. `e2e/fullstack/**` scripts that drive the wrangler migration apply

| File | Mechanism | Migration files referenced | FP? | Lines | Phase |
|---|---|---|---|---|---|
| `e2e/fullstack/test/wrangler-persist.mjs` | other — `wrangler d1 migrations apply` CLI against `--config` (see L83–94: `["d1","migrations","apply",database,"--local","--env",env,"--config",platformConfig,"--persist-to",D1_SEED_PERSIST]`), then copies the sqlite tree | ALL 24 when `platformConfig` is `ai-platform/wrangler.toml` or `platform-desktop-window.toml` | YES | `preparePlatformD1` L72–112 (runWranglerSync L36–45) | called from stack setup / `beforeAll`-style startup in p5-1, p5-2, p7-2-stack, p7-3-stack |
| `e2e/fullstack/test/p5-1.test.mjs` | other — `preparePlatformD1({platformConfig: ai-platform/wrangler.toml})` (config const L32) | ALL 24 | YES | call L425 | worker startup (beforeAll-equivalent) |
| `e2e/fullstack/test/p5-2.test.mjs` | other — same (config const L35) | ALL 24 | YES | call L441 | startup |
| `e2e/fullstack/test/p7-2-stack.mjs` | other — same (config const L35) | ALL 24 | YES | call L586 | startup |
| `e2e/fullstack/test/p7-3-stack.mjs` | other — `preparePlatformD1({platformConfig: activePlatformConfig})` (default `PLATFORM_CONFIG` = ai-platform/wrangler.toml L36; restarts may switch to variant tomls) | ALL 24 (via whatever platform config is active) | YES | call L795 | startup / restart |
| `e2e/fullstack/test/p7-3-06-prepare.mjs` | other — `startStack({platformConfig: "test/variant/platform-desktop-window.toml"})` (L156) → platform D1 migrations via that toml's `migrations_dir` (ai-platform/migrations); also edits **backend/supabase** migration files L68/L75/L82 (RPC gates, not ai-platform) | ALL 24 (indirect via desktop-window toml) | YES | L19 (config const), L156 | standalone long-running stack script |
| `e2e/fullstack/test/p5-1.test.mjs` `applyAboMigrations` (L121–134), `p5-2.test.mjs` (L~170), `p7-2-stack.mjs` (L~224), `p7-3-stack.mjs` `applyAboMigrations` (L318–331) | other — `wrangler d1 migrations apply abo-development --config <abo toml>` | abo migrations only | n/a | see lines | startup |

## 10. Other repo locations checked (no ai-platform migration references)

| File | Mechanism | Migration files referenced | FP? | Lines | Notes |
|---|---|---|---|---|---|
| `test/harness/local_dev_ports.py` | other (doc comment) | none | NO | L145 ("Platform D1 migrations must use `d1-seed/` only; see `e2e/fullstack/test/wrangler-persist.mjs`") | py harness; no file reads of migrations |
| `.github/scripts/control-residue-guard.sh` | other (path scanner) | none (skips any path containing a `migrations` segment: L14–15, L53–54) | NO | — | guards against control-plane residue in non-migrations paths |
| `frontend/**` | — | none | NO | — | only user-facing strings mentioning "migrations" (e.g. `frontend/lib/features/setup/application/setup_rpc_messages.dart` L10); no file references to ai-platform/migrations |
| `packages/**` | — | none | NO | — | `packages/vendor-contracts/test/bundle-scan.test.ts` uses readdirSync but only over package src dirs |
| `web-reference/scripts/validate-dev-nav.mjs` | fs-read of web-reference sources only | none | NO | L1, L8 | readdirSync/readFileSync not of migrations |
| `specs/**`, `docs/**` | markdown prose mentions | various | mixed | — | documentation only; e.g. `specs/058-usage-summary-gauge/quickstart.md` L29 cites `20260911180000_usage_rollup_quota_weight.sql`; `specs/068-abo-p3-4-admission-settlement-against-terms/data-model.md` L55 cites the FP migration. Not execution paths; excluded from the main table |
| `ai-platform/test/eval/*` (`harness.ts`, `conversation-harness.ts`, `prohibitions.test.ts`, etc.) | — | none | NO | — | no migration references found |
| `ai-platform/vitest*.ts` configs | — | none | NO | — | no migration/setupFiles references to migrations |

## 11. Summary counts

- Files referencing `ai-platform/migrations` SQL: **69 code files** (2 full-chain harnesses + 1 re-export + 24 unit tests with direct `?raw` (incl. cohort-activate-promote's glob) + 19 system tests + 34 e2e tests (counting phase-00 once; stage files listed individually above) + `migrations.test.ts` + 2 fs-read tests (`context-request`, `prompt-registry`) + 1 abo harness + 6 e2e/fullstack mjs scripts + tomls/config files as detailed per section above).
- Direct `?raw` import of `20261014120000_ai_request_idempotency_fingerprint.sql`: `ai-platform/test/system/harness.ts` (L89), `ai-platform/test/e2e/harness/d1.ts` (L23), `ai-platform/test/journal.test.ts` (L5), and **`abo/test/system/cross-worker-harness.ts` does NOT import it** (its chain ends at `20261006170100_drop_plan_entitlement.sql`, L50).
- Files that run the *entire* chain including FP: system tests (via `system/harness.ts`), e2e tests (via `e2e/harness/d1.ts`), `migrations.test.ts` (via wrangler CLI), `cohort-activate-promote.test.ts` (via `import.meta.glob`), fullstack p5/p7 scripts (via wrangler CLI + toml `migrations_dir`), `context-request.test.ts` and `prompt-registry.test.ts` (fs-read of all `.sql` files).
- Every unit/e2e/system test applies migrations in `beforeAll` (never `beforeEach`, never module top-level); `migrations.test.ts` applies inside test bodies against a temp persist created in `beforeEach`.