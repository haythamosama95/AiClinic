# Daily digest, platform watch, housekeeping and ABO rebuild

**Unit**: P4.11 · **Harness**: H-XW · **Verification**: T026 green

## 1. What was implemented

The ABO daily 06:00 UTC `scheduled()` cron (`0 6 * * *`) sends one digest email, raises AL-14 for issuer keys inside 30 days of `not_after`, deletes operational rows past the 90-day retention, and pings the heartbeat URL. The hourly cron (`0 * * * *`) raises AL-15 from `feedConsumerHealth` and AL-22 from issuer-key pins and the last-seen operator-credential list. After data loss, `rebuildAbo` replays `ledger/` into an empty D1, recomputes status, re-inquires the gap, compares `listGrants`, and ends on a clean reconciliation.

- **Daily digest** (`abo/src/digest/run.ts`) — plain-text digest with 24-hour counts, every grant, open findings, parked work, open alerts, job last-runs, backend last pull, export lag, version counts, and expiring keys. Subject `digest`. One send retry on failure.
- **AL-14** (`abo/src/digest/run.ts`, `abo/src/alert/index.ts`) — issuer key `not_after` within 30 days; repeats daily.
- **AL-15** (`abo/src/watch/hourly.ts`, `abo/src/alert/index.ts`) — `feedConsumerHealth.last_pull_at` null or older than 5 minutes; repeats hourly.
- **AL-22** (`abo/src/watch/hourly.ts`, `abo/src/alert/index.ts`) — unpinned issuer kid or unannounced active operator credential; repeats hourly.
- **Housekeeping** (`abo/src/housekeeping/run.ts`) — deletes done `work` and sent `alert` rows older than 90 days and stale `hmac-invalid/` R2 samples. Commercial facts are untouched.
- **Daily heartbeat** (`abo/src/worker.ts`) — fetches `HEARTBEAT_URL` after digest send attempts.
- **ABO rebuild** (`abo/src/rebuild.ts`, `abo/scripts/rebuild-abo.ts`, `abo/REBUILD.md`) — ledger replay, gap inquiry, `listGrants` comparison, and closing reconciliation. Operator script accepts provider transaction references from the dashboard export.
- **Scheduled entry** (`abo/src/worker.ts`) — daily and hourly branches call the new modules and stamp `scheduled_job_run`.
- **Fact log replay** (`abo/src/records/append.ts`, `abo/src/records/export.ts`) — `insertFactLog` stores `row_json`; ledger lines include `row` when present.
- **Harness** — seven E2E scenarios in `abo/test/system/digest-watch-rebuild.cross-worker.test.ts`. The harness observes every scenario; no manual steps.

### 1.1 Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/migrations/0009_digest_watch.sql` | FR-001, FR-004, FR-006 |
| `abo/src/digest/run.ts` | FR-001, FR-002, FR-007 |
| `abo/src/watch/hourly.ts` | FR-003, FR-004 |
| `abo/src/housekeeping/run.ts` | FR-005 |
| `abo/src/rebuild.ts` | FR-006 |
| `abo/scripts/rebuild-abo.ts` | FR-006 |
| `abo/REBUILD.md` | FR-006 |
| `abo/src/worker.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-007 |
| `abo/src/alert/index.ts` | FR-002, FR-003, FR-004 |
| `abo/src/clinic-api/auth.ts` | FR-004 |
| `abo/src/clinic-api/version.ts` | FR-001 |
| `abo/src/ops/index.ts` | FR-004, FR-006 |
| `abo/src/records/append.ts` | FR-006 |
| `abo/src/records/export.ts` | FR-006 |
| `abo/src/clinic-api/checkouts.ts` | FR-006 |
| `abo/src/work/runner.ts` | FR-006 |
| `abo/src/work/grant.ts` | FR-006 |
| `abo/src/work/reversal.ts` | FR-006 |
| `abo/src/reconciliation/run.ts` | FR-006 |
| `abo/vitest.cross-worker.config.ts` | FR-001–FR-007 |
| `abo/test/system/digest-watch-rebuild.cross-worker.test.ts` | FR-001–FR-007 |
| `abo/test/system/catalogue.system.test.ts` | FR-001 |
| `specs/086-abo-p4-11-daily-digest-platform-watch-housekeeping/quickstart.md` | FR-001–FR-007 |

## 2. Harness command for this unit's tests only

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/digest-watch-rebuild.cross-worker.test.ts
```

## 3. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.11-01 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `SEND_EMAIL` |
| E2E-P4.11-02 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `PLATFORM.listIssuerKeys` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-03 | `runScheduled("0 * * * *")` → `scheduled()` → `abo/src/watch/hourly.ts` → `PLATFORM.feedConsumerHealth` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-04 | `runScheduled("0 * * * *")` → `scheduled()` → `abo/src/watch/hourly.ts` → `PLATFORM.listIssuerKeys` and `PLATFORM.listOperatorCredentials` → `raiseAlert` → `sendDueAlerts` → `SEND_EMAIL` |
| E2E-P4.11-05 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/housekeeping/run.ts` |
| E2E-P4.11-06 | H-XW test imports `abo/src/rebuild.ts` → R2 `ledger/` → D1 inserts → `providerForId` inquire → `PLATFORM.listGrants` → `abo/src/work/grant.ts` → `runReconciliation` |
| E2E-P4.11-07 | `runScheduled("0 6 * * *")` → `scheduled()` → `abo/src/digest/run.ts` → `SEND_EMAIL` (retry) → outbound fetch of `HEARTBEAT_URL` |
