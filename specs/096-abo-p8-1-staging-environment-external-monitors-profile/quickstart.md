# Quickstart — P8.1 staging environment, external monitors and staging profile

**Unit**: P8.1 · **Branch**: `ai/096-abo-p8-1-staging-environment-external-monitors-profile` · **Verification**: T014 (four E2E ids)

## 1. What was implemented

- **Staging hostname flags** — Both `[env.staging]` blocks in `ai-platform/wrangler.toml` and `abo/wrangler.toml` set `workers_dev = false` and `preview_urls = false`. The platform block keeps `DURATION_SCALE = "staging"` and `HEARTBEAT_URL`.
- **ABO minute heartbeat** — The `* * * * *` cron branch in `abo/src/worker.ts` calls `pingHeartbeat`. The `0 6 * * *` daily digest branch keeps its existing `pingHeartbeat` call.
- **External heartbeat monitor** — `ops/staging/heartbeat-monitor.mjs` reads ping state from a fixture and prints `AL-21` when the ABO minute ping is absent.
- **Hourly audit watcher** — `ops/staging/audit-watcher.mjs` classifies fixture entries (`deploy`, `secret`, `d1_export`, `access_policy`) and prints `AL-21` once per alerting event.
- **NFR-08 record** — `ops/staging/nfr-08.md` copies the steady-load figures from 05 §7 and states they stay inside the Cloudflare Workers Paid plan and Supabase project allowances.
- **H-STG harness** — One Node test (`p8-1-04.test.mjs`), three scripted checklists, and `run-checklists.mjs` to execute the checklist items against the ops scripts and fixtures.

## 2. Files this unit adds and modifies

| File | Change |
| --- | --- |
| `ai-platform/wrangler.toml` | Modified `[env.staging]` flags |
| `abo/wrangler.toml` | Modified `[env.staging]` flags |
| `abo/src/worker.ts` | Minute cron calls `pingHeartbeat` |
| `ops/staging/heartbeat-monitor.mjs` | Added |
| `ops/staging/fixtures/abo-cron-disabled.json` | Added |
| `ops/staging/audit-watcher.mjs` | Added |
| `ops/staging/fixtures/deploy-and-secret.json` | Added |
| `ops/staging/nfr-08.md` | Added |
| `e2e/fullstack/staging/p8-1-01.checklist.md` | Added |
| `e2e/fullstack/staging/p8-1-02.checklist.md` | Added |
| `e2e/fullstack/staging/p8-1-03.checklist.md` | Added |
| `e2e/fullstack/staging/p8-1-04.test.mjs` | Added |
| `e2e/fullstack/staging/run-checklists.mjs` | Added |
| `specs/096-abo-p8-1-staging-environment-external-monitors-profile/quickstart.md` | Added |

## 3. Harness commands (this unit only)

From the repository root:

```bash
node --test e2e/fullstack/staging/p8-1-04.test.mjs
node e2e/fullstack/staging/run-checklists.mjs
```

Do not run `npm test` in `e2e/fullstack`. Do not boot wrangler. Do not deploy.

The live H-STG command against a live staging account is **not executed** in this workflow because this workflow does not deploy or start wrangler.

## 4. Entry point → module chain (E2E ids)

| ID | Chain |
| --- | --- |
| E2E-P8.1-01 | `run-checklists.mjs` → `ops/staging/heartbeat-monitor.mjs` on `ops/staging/fixtures/abo-cron-disabled.json`. Expected pings: ABO minute (`abo/src/worker.ts` `scheduled()` `* * * * *` → `pingHeartbeat`), platform 5-minute (`ai-platform/src/worker.ts` `scheduled()` `*/5 * * * *` → `runFiveMinuteCron` → `pingPlatformHeartbeat`), ABO daily digest (`scheduled()` `0 6 * * *` → `pingHeartbeat`). ABO minute ping absent → stdout is `AL-21` only |
| E2E-P8.1-02 | `run-checklists.mjs` → `ops/staging/audit-watcher.mjs` on `ops/staging/fixtures/deploy-and-secret.json`. Hourly job; token is read-only and not stored in git. Fixture mode does not read the token. Classes `deploy` and `secret` → stdout is `AL-21`, repeated per event |
| E2E-P8.1-03 | `run-checklists.mjs` → checklist text in `p8-1-03.checklist.md`. Purchase chain cited, not executed live: `POST /v1/checkouts` → `handleBillingV1` → `handlePostCheckout` with a Paymob test card. AI active is `public.get_ai_status` in about 1 minute. Term and grace follow platform `[env.staging]` `DURATION_SCALE = "staging"` (1 month = 30 minutes, 1 day = 1 minute). NFR-08 cost check in `ops/staging/nfr-08.md`. Hosted R-4 command not executed; `ai_coverage_feed_pull` stays `30 seconds` |
| E2E-P8.1-04 | `p8-1-04.test.mjs` parses `[env.staging]` in `ai-platform/wrangler.toml` and `abo/wrangler.toml` (both set `workers_dev = false` and `preview_urls = false`). Ops chain read as source: `abo/src/worker.ts` `fetch` → `handleOps` → `dispatchOps` → `verifyOpsAccess`. No live hostname is opened |

The scripted checklist items in sections 4 are the manual steps `run-checklists.mjs` already executes.
