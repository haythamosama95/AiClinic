# Fallback admission, coverage feed and administrator coverage read

## 1. What was implemented

Fallback admission from `coverage_mirror` when the clinic DO is unreachable: mirror checks, pending `fallback_admission` rows, a 2 s admission deadline race, and `coverage_unknown` when weight would exceed 5 × `w_max` or the clock is at or after `hard_stop_at`.

The `*/5` cron drain (`reconcileGraceUsage`) settles pending fallback rows via DO `settleFallback`, inserts `usage_event`, and skips rows whose `request_id` the DO still holds.

`GET /v1/feed/coverage` with feed-token auth, pre-auth contract version negotiation, and `feed_consumer` cursor updates.

`feedConsumerHealth` (class M) exposes `last_pull_at` and `last_cursor` for the backend feed consumer.

Administrator `GET /v1/coverage` (read-only DO `read_coverage`, `subscription_ref`, snapshot, `queued_terms`, `recent_terms`).

Removal of `GET /v1/usage` and the `usage-summary` module (HTTP 404).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/data-model.md` | FR-001, FR-003, FR-005, FR-007 |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/feed-coverage.md` | FR-005, FR-006 |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/coverage-get.md` | FR-008 |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/feed-consumer-health.md` | FR-007 |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/quickstart.md` | FR-001 through FR-009 |
| `ai-platform/migrations/20261006160000_fallback_admission_feed.sql` | FR-003, FR-005 |
| `ai-platform/src/admission/index.ts` | FR-001, FR-002, FR-003, FR-004 |
| `ai-platform/src/capability/index.ts` | FR-002 |
| `ai-platform/src/credit/index.ts` | FR-004 |
| `ai-platform/src/quota-do/index.ts` | FR-004 |
| `ai-platform/src/worker.ts` | FR-004, FR-005, FR-006, FR-008, FR-009 |
| `ai-platform/src/coverage-read/index.ts` | FR-008 |
| `ai-platform/src/vendor/entrypoint.ts` | FR-007 |
| `ai-platform/src/retention/index.ts` | FR-003 |
| `ai-platform/src/usage-summary/index.ts` (delete) | FR-009 |
| `ai-platform/test/system/harness.ts` | FR-001, FR-004, FR-005, FR-007 |
| `ai-platform/test/system/fallback-feed-coverage.system.test.ts` | FR-001 through FR-009 |
| `ai-platform/test/usage-summary.test.ts` (delete) | FR-009 |
| `ai-platform/vitest.config.ts` | FR-009 |
| `ai-platform/test/migrations.test.ts` | FR-003, FR-005 |
| `ai-platform/test/admission-credit.test.ts` | FR-003, FR-004 |
| `ai-platform/test/retention.test.ts` | FR-003 |
| `ai-platform/test/worker-entry.test.ts` | FR-009 |
| `ai-platform/test/worker-request-orchestrator.test.ts` | FR-003 |
| `ai-platform/test/support-purge.test.ts` | FR-003 |
| `ai-platform/test/system/cron-retention-interplay.system.test.ts` | FR-004 |
| `ai-platform/test/e2e/harness/d1.ts` | FR-003 |
| `ai-platform/test/e2e/harness/env.ts` | FR-003 |
| `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts` | FR-003, FR-004 |
| `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts` | FR-003 |
| `ai-platform/test/e2e/stage-09-adapter-identity.test.ts` | FR-003 |
| `ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts` | FR-003 |
| `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts` | FR-003 |
| `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts` | FR-003 |
| `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts` | FR-003 |
| `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts` | FR-003 |
| `ai-platform/test/e2e/stage-X-grace-retention.test.ts` | FR-003, FR-004 |
| `ai-platform/test/e2e/stage-X-cron-flush-reconcile.test.ts` | FR-004 |
| `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts` | FR-003 |

## 3. Harness command (this unit only)

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/fallback-feed-coverage.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

## 4. Entry point → module chain per E2E id

Every scenario is asserted by H-AP; use the harness command above only.

| ID | Chain |
| --- | --- |
| E2E-P3.9-01 | `coverClinic()` → harness admission fault `throw` → `SELF.fetch` `POST /v1/requests` → `src/admission/index.ts` reads `coverage_mirror` and inserts `fallback_admission` → clear the fault → `runScheduled("*/5 * * * *")` → `reconcileGraceUsage` → DO `settleFallback` |
| E2E-P3.9-02 | Pending `fallback_admission` weight already at 5 × `w_max` → fault `throw` → `SELF.fetch` `POST /v1/requests` → `coverage_unknown` |
| E2E-P3.9-03 | `setTestClock` at or after `coverage_mirror.hard_stop_at` → fault `throw` → `SELF.fetch` `POST /v1/requests` → `coverage_unknown` |
| E2E-P3.9-04 | Fault `hold` → `SELF.fetch` `POST /v1/requests` → `inspectCoverage` sees the reservation → `setTestClock` past 2 seconds → `runScheduled("*/5 * * * *")` skips that `request_id` |
| E2E-P3.9-05 | Insert `coverage_event` rows → `SELF.fetch` `GET /v1/feed/coverage` → `feed_consumer` → `vendorCall("feedConsumerHealth")`; the same feed token on `POST /v1/requests`; `mintAat` on the feed |
| E2E-P3.9-06 | `SELF.fetch` `GET /v1/feed/coverage` with no `Aip-Contract-Version`, then with an unsupported version |
| E2E-P3.9-07 | `mintAat` `role = administrator` → `SELF.fetch` `GET /v1/coverage` → `src/coverage-read/index.ts` → DO `read_coverage`; staff `mintAat` → 403; `getCoverage` detail unchanged |
| E2E-P3.9-08 | `SELF.fetch` `GET /v1/usage` |
