# Implementation Plan: Fallback admission, coverage feed and administrator coverage read

**Branch**: `ai/073-abo-p3-9-fallback-admission-coverage-feed-administrator` | **Date**: 2026-10-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

When a clinic DO errors or takes longer than 2 seconds, admission reads `coverage_mirror` by primary key and either writes a `fallback_admission` row or answers `coverage_unknown`. The same unit serves `GET /v1/feed/coverage` and administrator `GET /v1/coverage`, and removes `GET /v1/usage`. It is phase P3, size M, **Depends** P3.5, in parallel with P3.6–P3.8 and P4.x.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`) in `ai-platform`, TypeScript `^5.9.2`, Node `>=22` (`ai-platform/package.json`). Workers compatibility date `2026-05-03` (`ai-platform/wrangler.toml`). `GatewayObject` stays a `DurableObject`. `VendorEntrypoint` stays a `WorkerEntrypoint` from `cloudflare:workers`.

**Primary Dependencies**: `vendor-contracts` (`file:../packages/vendor-contracts`), already a dependency. This unit does not add a library and does not change the package. Feed version checks use `negotiate` and `CHANNEL_VERSIONS.platformFeed`. Feed tokens use `validateTokenClaims` with audience `ai-platform-feed`. `subscription_ref` uses the existing `subscriptionRef`. Clinic `/v1/coverage` uses the existing `requireAipContractVersion` / `withAipContractVersion` (`CHANNEL_VERSIONS.platformClinic`). Time uses `clockNowMs` / `clockNowIso` in `ai-platform/src/clock.ts`. Tests use `coverClinic`, `mintAat`, `vendorCall`, `setTestClock`, `runScheduled`, and `inspectCoverage` from `ai-platform/test/system/harness.ts`. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`.

**Storage**: New D1 tables `fallback_admission` and `feed_consumer` (03 §3.2). `grace_admission_queue` is dropped. Existing `coverage_mirror` is read by primary key and is not written by this unit's admission path. Existing `coverage_event` is read by the feed and is not given a new column. Existing `usage_event` keeps its unique index on `request_id`. The per-clinic DO already stores reservations on `hot` and replay answers. No new DO table. `packages/vendor-contracts` stays unchanged.

**Testing**: H-AP. E2E-P3.9-01 through E2E-P3.9-08 live in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` and run under `vitest.workers.config.ts`. Titles start with the E2E id (rule V3). Tests are written to fail before the fallback, feed, and coverage-read paths exist. The unit command is that file only. No new CI job (rule V7). Earlier platform suites stay on `npm test` and `npm run test:e2e` (rule S2). Time moves with `setTestClock` (rule V4). No local scenario sleeps more than 2 s. The feed test inserts `coverage_event` rows in D1 and does not call `grant`. The harness does not start an ABO worker.

**Target Platform**: The existing `ai-platform` worker (`main = src/worker.ts`, wrangler name `ai-platform-gateway`). Live entries are `SELF.fetch` on `ai-platform/src/worker.ts` (`POST /v1/requests`, `GET /v1/feed/coverage`, `GET /v1/coverage`, `GET /v1/usage`), `runScheduled("*/5 * * * *")` in `ai-platform/test/system/harness.ts` (`scheduled`), and `vendorCall("feedConsumerHealth", …)` on `VendorEntrypoint` (`env.VENDOR`). Production wrangler has no clock control and no admission-fault binding.

**Project Type**: Worker change inside `ai-platform`. One codebase (spec **Codebase**, rule S3). No wiring exception.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). A DO call that errors or passes 2 seconds on the platform clock either admits from the mirror under the four conditions or answers `coverage_unknown`. The `*/5` cron drains pending fallback rows. No separate throughput target. The write budget stays in P3.11.

**Constraints**: Do not modify `packages/vendor-contracts`. Do not rewrite `buildCoverageSnapshot`, `lapsedSnapshotReason`, or the grace and lapse transitions in `ai-platform/src/quota-do/coverage.ts` (rule S7). Do not change `IssuerTokenVerifier` so that a feed token becomes an AI principal. Entitlement, plan, and invoice tables, and all `/control/*` routes, stay until P3.10. The backend pull cycle in 04 §4.1 stays with P5.2. The desktop client stays with P6.2. `readCoverageEvents` is not changed. No ABO worker in these tests.

**Scale/Scope**: Size M (rule S3: 2–3 user stories, one codebase). Three user stories and eight E2E ids. Implied task count is 21. That is inside the M band and is not padded (rule S3, plan skill).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). **Spikes** is `None`, so there is no `research.md`. The Phase 1 artifacts (`data-model.md`, `contracts/`) stay on the vendor worker: D1 and the existing DO on the AI Platform worker. No clinic write and no second service. The same boxes hold after those artifacts.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One clinic can still be admitted to AI while that clinic's DO is unreachable, inside the outage cap, and an administrator can read that clinic's coverage (spec §4.1, 02 §7 principle I). The unit adds no second clinic product.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays in the existing Worker. The drain is the existing `*/5` cron. The feed is one HTTP route the backend will pull later (P5.2). No queue, no Kubernetes, and no new service (02 §7 principle I and the workflow-automation row).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `ai-platform` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The worker has no clinic database credential. The model path is unchanged.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit writes vendor D1 and, on the drain, the clinic DO's usage counters. 02 §7 principle III places clinic-side integrity in PostgreSQL and vendor-side integrity in D1 constraints and the DO's serialized writer. `fallback_admission` is keyed by installation and idempotency key. `usage_event.request_id` stays unique. Clinic RPCs, RLS, and triggers stay as they are. `coverage_mirror` is not an admission authority by itself.

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Fallback reads `coverage_mirror` by primary key and does not admit from a cache. The feed token is audience `ai-platform-feed`, `sub=backend-feed`, no `org`, and it is refused on `/v1/requests`. An AI token is refused on the feed. The feed version check runs before authentication and before any write. `GET /v1/coverage` requires `role = administrator` and does not write the DO. A staff token is HTTP 403. Feed pages are not signed (spec §4.1, 02 §3.2 Feed row, 04 §4.1, 04 §4.2).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no model call and no path from the model to D1 or the DO (02 §7 principles II and V). A DO error or a call longer than 2 seconds either admits from the mirror under the four conditions or answers `coverage_unknown` with `retry_after`. Clinical work is outside this worker.

## Project Structure

### Documentation (this feature)

```text
specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── feed-coverage.md
│   ├── coverage-get.md
│   └── feed-consumer-health.md
└── tasks.md                   # /abo-tasks, not this phase
```

No `research.md` (**Spikes** is `None`). `data-model.md` records the entities in spec §3.2. `contracts/` freezes the HTTP feed, the `GET /v1/coverage` response, and `feedConsumerHealth`.

#### quickstart.md outline

Implement writes `quickstart.md` after the H-AP run below is green. Sections:

1. What was implemented — fallback admission from `coverage_mirror`, the `*/5` drain, `GET /v1/feed/coverage`, `feedConsumerHealth`, administrator `GET /v1/coverage`, and removal of `GET /v1/usage`.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/fallback-feed-coverage.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

4. Entry point to module chain per E2E id (rule S8):

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

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20261006160000_fallback_admission_feed.sql
├── src/
│   ├── admission/
│   │   └── index.ts
│   ├── capability/
│   │   └── index.ts
│   ├── coverage-read/
│   │   └── index.ts
│   ├── credit/
│   │   └── index.ts
│   ├── quota-do/
│   │   └── index.ts
│   ├── retention/
│   │   └── index.ts
│   ├── vendor/
│   │   └── entrypoint.ts
│   └── worker.ts
└── test/
    ├── system/
    │   ├── harness.ts
    │   └── fallback-feed-coverage.system.test.ts
    └── (existing suites listed under Files, S2 only)
```

**Structure Decision**: Source stays the existing Worker. Fallback admission stays in `src/admission/index.ts`. The drain stays the function `reconcileGraceUsage` in `src/credit/index.ts`, called only from the `*/5 * * * *` branch in `src/worker.ts`. The DO charge is kind `settleFallback` on `GatewayObject`, applied in `src/quota-do/index.ts`. `GET /v1/feed/coverage` is handled in `src/worker.ts`. `feedConsumerHealth` is a class M method on `VendorEntrypoint`. `GET /v1/coverage` is `src/coverage-read/index.ts`. `src/usage-summary/index.ts` is deleted. No feed module and no second codebase.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| Clinic states `grace` / `lapsed` and reasons `expired` / `grace_exhausted` in the snapshot | `buildCoverageSnapshot` and `lapsedSnapshotReason` in `ai-platform/src/quota-do/coverage.ts`. State `grace` is the branch where a term is in `grace`. State `lapsed` is the branch that is not active, grace, exhausted, or reversed. `lapsedSnapshotReason` returns `expired` or `grace_exhausted` from the last ended term's `end_reason`. `CoverageLapseReason` in `ai-platform/src/errors.ts` already includes those two reasons. This unit reads `coverage_mirror.state` and the live snapshot. It does not change those functions, the reason strings, or the transitions that write them. |

## Files

| File | FR |
| --- | --- |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/data-model.md` | FR-001, FR-003, FR-005, FR-007 |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/feed-coverage.md` | FR-005, FR-006 |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/coverage-get.md` | FR-008 |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/feed-consumer-health.md` | FR-007 |
| `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/quickstart.md` (implement, after verification) | FR-001 through FR-009 |
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

`buildCoverageSnapshot`, `lapsedSnapshotReason`, `readCoverageEvents`, and `IssuerTokenVerifier` stay as they are. `packages/vendor-contracts/**` stays. `/control/*` stays until P3.10.

## Test Layout

Titles start with the E2E id (rule V3). The file is `ai-platform/test/system/fallback-feed-coverage.system.test.ts` under H-AP (`vitest.workers.config.ts`). Each test calls the entry point below and fails while the behavior it names is absent. `coverClinic()` remains the paid-grant helper. `harness.ts` adds `feedConsumerHealth` to the `VendorMethod` union, `setAdmissionFault`, and `mintFeedToken`.

`mintFeedToken` signs with the harness issuer key. The payload bytes are `canonicalize` from `vendor-contracts`. Claims are `iss` of the harness issuer, `aud` `ai-platform-feed`, `sub` `backend-feed`, no `org`, `ver` `"2"`, `jti` a UUID, and `exp - iat` ≤ 120. `mintAat` stays the AI token (`aud` `ai-platform`). Clinic fetches send `Aip-Contract-Version: 1` the way `invoke` already does. No `sleep` over 2 s. No ABO worker is constructed. E2E-P3.9-05 does not call `grant`.

The admission fault table `harness_admission_fault` (`mode`, `hold_until`) is created in the harness setup script, not in a product migration. `GatewayObject` reads it only when `TEST_CLOCK === "1"`. A missing table is ignored. `mode = "throw"` throws before `admissionRPC`. `mode = "hold"` runs `admissionRPC`, then waits until `clockNowMs` is at or past `hold_until`.

`w_max` for these tests is the max `Economics.quotaWeight` among installed registry manifests whose `Identity.lifecycleState` is not `retired`. The installed visit-summary manifest is `active` with `quotaWeight` 1, so `w_max` is 1 and 5 × `w_max` is 5. `retry_after` on `coverage_unknown` is the existing `supplementaryFieldsForCode` value (`DEFAULT_RATE_LIMITED_RETRY_AFTER_SECONDS` when admission passes no other hint).

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P3.9-01 | H-AP | Title `E2E-P3.9-01 FM-06 DO failure admits via fallback and */5 charges once`. `coverClinic()`. `setAdmissionFault("throw")`. `SELF.fetch` `POST /v1/requests` for that clinic. The response code is not `coverage_unknown`. One `fallback_admission` row exists for that installation with `state` `pending`, a `term_id`, and a `request_id`. Clear the fault. `runScheduled("*/5 * * * *")`. That term's used increases by the row's `weight` once. A second `runScheduled("*/5 * * * *")` does not increase it again. The row is `settled`. |
| E2E-P3.9-02 | H-AP | Title `E2E-P3.9-02 fallback weight beyond 5 × w_max is coverage_unknown`. `coverClinic()`. Insert pending `fallback_admission` rows for that installation whose `weight` sums to 5 × `w_max`. `setAdmissionFault("throw")`. `SELF.fetch` `POST /v1/requests` with that clinic's capability. HTTP 503, body code `coverage_unknown`, and `retry_after` is present. No new `fallback_admission` row for this request. |
| E2E-P3.9-03 | H-AP | Title `E2E-P3.9-03 fallback at or after hard_stop_at is coverage_unknown`. `coverClinic()`. `setTestClock` to `coverage_mirror.hard_stop_at` or later. `setAdmissionFault("throw")`. `SELF.fetch` `POST /v1/requests`. Body code `coverage_unknown`. No new `fallback_admission` row. |
| E2E-P3.9-04 | H-AP | Title `E2E-P3.9-04 drain skips a request_id reserved before the admission deadline`. `coverClinic()`. `setAdmissionFault("hold")` with `hold_until` more than 2 seconds ahead of the test clock. Start `SELF.fetch` `POST /v1/requests` without awaiting it. `vendorCall("inspectCoverage")` until a reservation exists. `setTestClock` past that deadline and past `hold_until`. After the fetch settles, `runScheduled("*/5 * * * *")`. That `request_id` is counted once: `usage_event` has one row for it, or the reservation still holds it and `used` did not gain a second `weight`. A second scheduled run still does not add a second `weight`. |
| E2E-P3.9-05 | H-AP | Title `E2E-P3.9-05 feed page, token separation, and feedConsumerHealth`. Insert two `coverage_event` rows directly. `mintFeedToken` and `GET /v1/feed/coverage?after=<first-1>&limit=1` with `Aip-Contract-Version: 1`. Header `Aip-Contract-Version` is `1`. Body is `{contract_version, after, events, next_after, has_more}` with one event, `has_more` true, and `next_after` that event's `feed_seq`. `vendorCall("feedConsumerHealth", { contract_version: 1 })` returns that pull's `last_pull_at`. The same feed token on `POST /v1/requests` is 401. `mintAat` on `GET /v1/feed/coverage` is 401. |
| E2E-P3.9-06 | H-AP | Title `E2E-P3.9-06 feed version missing or unsupported is refused before auth`. `GET /v1/feed/coverage` with no `Aip-Contract-Version` and no `Authorization` is HTTP 400 `contract_version_unsupported`. The same call with `Aip-Contract-Version: 2` is HTTP 400 `contract_version_unsupported`. `feed_consumer` has no `last_pull_at`. |
| E2E-P3.9-07 | H-AP | Title `E2E-P3.9-07 administrator coverage read does not write the DO`. `coverClinic()`, then a second paid grant so one term is `queued`. `vendorCall("getCoverage")` records `detail`. `mintAat` with `role` `administrator` calls `GET /v1/coverage`. The body has `subscription_ref` equal to `subscriptionRef(org_id)`, `snapshot`, `queued_terms`, and `recent_terms` as in [contracts/coverage-get.md](./contracts/coverage-get.md). A second `getCoverage` `detail` is unchanged. `mintAat` with `role` `staff` is HTTP 403 and does not change `getCoverage`. |
| E2E-P3.9-08 | H-AP | Title `E2E-P3.9-08 GET /v1/usage is 404`. `SELF.fetch` `GET /v1/usage` is HTTP 404. |

Earlier tests that `DELETE FROM grace_admission_queue`, import `src/usage-summary`, or expect `reconcileGraceUsage` to drop rows after two hours are updated in the same change that drops the table and replaces the drain, so `npm test` and `npm run test:e2e` stay green (rule S2).

## Sequencing

Tests are written and observed failing before fallback admission, the feed, the coverage read, and the usage removal exist. Each step is one task. The implied count is 21.

1. Add `test/system/fallback-feed-coverage.system.test.ts` with E2E-P3.9-01. Run the unit command. It fails because a DO throw still answers `coverage_unknown` and writes no `fallback_admission` row.
2. Add E2E-P3.9-02. The run fails because weight beyond 5 × `w_max` is not HTTP 503 `coverage_unknown` with `retry_after`.
3. Add E2E-P3.9-03. The run fails because a clock at or after `hard_stop_at` is not `coverage_unknown`.
4. Add E2E-P3.9-04. The run fails because the drain does not skip a `request_id` the DO reserved before the deadline.
5. Add E2E-P3.9-05. The run fails because `GET /v1/feed/coverage` is not a route and `feedConsumerHealth` is not a method.
6. Add E2E-P3.9-06. The run fails because a missing or unsupported feed version is not HTTP 400 before authentication.
7. Add E2E-P3.9-07. The run fails because `GET /v1/coverage` is not a route.
8. Add E2E-P3.9-08. The run fails because `GET /v1/usage` is still served.
9. Add `ai-platform/migrations/20261006160000_fallback_admission_feed.sql` as in `data-model.md`. Do not edit earlier migrations. Do not drop `entitlement`, `plan`, or `invoice`.
10. In `test/system/harness.ts`, create `harness_admission_fault`, add `setAdmissionFault` and `mintFeedToken`, and add `feedConsumerHealth` to `VendorMethod`. In `GatewayObject`, when `TEST_CLOCK === "1"`, honor `throw` and `hold` as in the Test Layout. `admissionRPC` uses a caller `requestId` when the body has one, and otherwise keeps `crypto.randomUUID()`.
11. In `src/capability/index.ts`, export `publishedQuotaWeightMax()`: the max `Economics.quotaWeight` (missing or non-positive counts as 1) among installed registry manifests whose `Identity.lifecycleState` is not `retired`. In `src/admission/index.ts`, delete `GRACE_ADMISSION_CAP`, `admitUnderGrace`, and the `grace_admission_queue` reads and writes. On DO throw or deadline, read `coverage_mirror` with `SELECT … WHERE installation_id = ?` and no cache. Admit only when `state` is `active` or `grace`, `suspended` is 0, `clockNowIso` is strictly before `hard_stop_at`, the capability id is in `term_snapshot.capabilities`, and pending `fallback_admission.weight` for that installation plus this `w` is at most 5 × `publishedQuotaWeightMax()`. Otherwise return `coverage_unknown` with `retryAfter` so the existing taxonomy answers HTTP 503 and `retry_after`. On admit, insert `fallback_admission` (`term_id` = `term_snapshot.ref`, `request_id` allocated before the DO call, `weight` = `w`, `state` `pending`). A DO throw returns the existing `grace_admitted` outcome so the pipeline does not set `termAdmission` and does not insert `usage_event`. A deadline that fires after the DO has stored that `request_id` returns `admitted` with that `reservationId` and `termId` so the existing credit path counts it once.
12. The admission deadline is `clockNowMs` at the start of the DO call plus 2000. Race the DO call against a loop that resolves when `clockNowMs` has passed that instant. Under `TEST_CLOCK`, each iteration yields so `setTestClock` can move the clock while the call is in flight. Production `clockNowMs` is `Date.now()`, so the limit stays 2 seconds of real time.
13. Add DO kind `settleFallback` on `GatewayObject`, applied in `src/quota-do/index.ts`. If a reservation `id` or a replay answer `requestId` equals the row's `request_id`, return skipped and do not change `used`. Otherwise add `weight` to `hot.used` when `term_id` is `hot.active_term_id`, and to that term's `used_final` otherwise. Do not call the grace or lapse transitions.
14. Replace the body of `reconcileGraceUsage` with the drain. Select `fallback_admission` where `state` is `pending`. Skip a row whose `request_id` the DO still holds or that already has a `usage_event` (leave it `pending` when the DO still holds it; do not add `used`). Otherwise call `settleFallback`, `INSERT OR IGNORE` into `usage_event` on that `request_id`, and set `state` to `settled`. Remove the 2-hour drop and the zero-credit reconcile. Call this function only from the `scheduled` branch `cron === "*/5 * * * *"`, not from the other crons. Leave `runFiveMinuteCron` on that branch.
15. In `src/worker.ts`, handle `GET /v1/feed/coverage` by calling `negotiate(CHANNEL_VERSIONS.platformFeed, …)` before the `Authorization` header is read and before any D1 write. Failure is HTTP 400 `{code: "contract_version_unsupported", accepted_versions}` and does not update `feed_consumer`.
16. After the version check, verify the bearer token with `validateTokenClaims` for audience `ai-platform-feed`, using the issuer key already loaded for AI tokens. Failure is 401 and does not update `feed_consumer`. Success reads `coverage_event` as in [contracts/feed-coverage.md](./contracts/feed-coverage.md), echoes `Aip-Contract-Version`, and upserts `feed_consumer` for `consumer` `backend-feed`. A feed token stays invalid for `IssuerTokenVerifier` on `POST /v1/requests`.
17. Add `feedConsumerHealth` on `VendorEntrypoint` as class M, per [contracts/feed-consumer-health.md](./contracts/feed-consumer-health.md). It reads `feed_consumer` and does not write.
18. Add `src/coverage-read/index.ts` and `GET /v1/coverage` per [contracts/coverage-get.md](./contracts/coverage-get.md). Version check uses the existing clinic helper. `role` other than `administrator` is HTTP 403 and does not call the DO. The administrator path calls DO kind `read_coverage` only and `subscriptionRef(org_id)`.
19. Delete the `GET /v1/usage` branch, delete `src/usage-summary/index.ts` and `test/usage-summary.test.ts`, and remove that test from `vitest.config.ts`. `GET /v1/usage` falls through to HTTP 404.
20. Update the existing files in the Files section that still mention `grace_admission_queue`, `GRACE_ADMISSION_CAP`, the 2-hour grace drop, or `src/usage-summary`, so those suites do not require the dropped table or the removed route. `src/retention/index.ts` stops deleting `grace_admission_queue`.
21. Run the unit command and confirm E2E-P3.9-01 through E2E-P3.9-08 pass. Confirm the vitest path is that file only, and that `src/coverage-read/index.ts` is reached from `GET /v1/coverage`.

## Complexity Tracking

02 §7 records no constitution violation for this unit. Nothing is filled in here.
