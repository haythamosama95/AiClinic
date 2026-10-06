# Tasks: Fallback admission, coverage feed and administrator coverage read

**Input**: Design documents from `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged unit in the plan **Depends** line: P3.5. **Consumes Binding**: clinic states `grace` / `lapsed` and reasons `expired` / `grace_exhausted` in `buildCoverageSnapshot` and `lapsedSnapshotReason` (`ai-platform/src/quota-do/coverage.ts`). This unit reads them and does not change them. Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/` (`contracts/feed-coverage.md`, `contracts/coverage-get.md`, `contracts/feed-consumer-health.md`). There is no `research.md`. `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id in the spec Test plan, written to fail before fallback admission, the feed, the coverage read, and the usage removal exist. Test Layout names no extra new test file. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase. No Polish phase. Task ids follow plan Sequencing. Sequencing step 20 is two tasks because `worker-entry.test.ts` does not share a path with the grace-queue files.

**Task count**: 23. Size M is 20–32 (rule S3). The count is eight E2E tasks (Sequencing steps 1–8), eleven implementation tasks (steps 9–19), two tasks for Sequencing step 20, one verification task (the unit harness, step 21), and `quickstart.md`. It is not padded. `npm test` and `npm run test:e2e` are the review's earlier-suite run (SC-002, rule S2), not a task.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — the Files paths in `plan.md`
- **ABO**: `abo/` — this unit does not change it. The harness does not start an ABO worker. The backend puller stays in P5.2. The desktop client stays in P6.2.
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified
- **Spec Kit artifacts**: `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/`
- `data-model.md` and `contracts/` stay plan-phase artifacts. Do not edit earlier migrations. Do not drop `entitlement`, `plan`, or `invoice`. Do not rewrite `buildCoverageSnapshot`, `lapsedSnapshotReason`, or the grace and lapse transitions in `ai-platform/src/quota-do/coverage.ts` (rule S7). Do not change `readCoverageEvents` or `IssuerTokenVerifier`. `/control/*` stays until P3.10. Do not modify `packages/vendor-contracts`.

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/fallback-feed-coverage.system.test.ts`. The unit command is that file only, under `vitest.workers.config.ts`. `coverClinic()` remains the paid-grant helper. Clinic fetches send `Aip-Contract-Version: 1` the way `invoke` already does. `w_max` is the max `Economics.quotaWeight` among installed registry manifests whose `Identity.lifecycleState` is not `retired`. The installed visit-summary manifest is `active` with `quotaWeight` 1, so `w_max` is 1 and 5 × `w_max` is 5. `retry_after` on `coverage_unknown` is the existing `supplementaryFieldsForCode` value. No `sleep` over 2 s. No ABO worker is constructed. E2E-P3.9-05 does not call `grant`. Do not add `setAdmissionFault`, `mintFeedToken`, `harness_admission_fault`, or `feedConsumerHealth` on `VendorMethod` in these tasks.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/fallback-feed-coverage.system.test.ts
```

### 3.1 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1)

**Independent Test**: E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03, and E2E-P3.9-04 in harness H-AP.

- [X] T001 [US1] Add the failing test `E2E-P3.9-01 FM-06 DO failure admits via fallback and */5 charges once` in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` — red test, FR-001, FR-003, FR-004, E2E-P3.9-01. `coverClinic()`. `setAdmissionFault("throw")`. `SELF.fetch` `POST /v1/requests` for that clinic. The response code is not `coverage_unknown`. One `fallback_admission` row exists for that installation with `state` `pending`, a `term_id`, and a `request_id`. Clear the fault. `runScheduled("*/5 * * * *")`. That term's used increases by the row's `weight` once. A second `runScheduled("*/5 * * * *")` does not increase it again. The row is `settled`. The unit command fails because a DO throw still answers `coverage_unknown` and writes no `fallback_admission` row.

- [X] T002 [US1] Add the failing test `E2E-P3.9-02 fallback weight beyond 5 × w_max is coverage_unknown` in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` — red test, FR-002, E2E-P3.9-02. Depends on T001 (same file). `coverClinic()`. Insert pending `fallback_admission` rows for that installation whose `weight` sums to 5 × `w_max`. `setAdmissionFault("throw")`. `SELF.fetch` `POST /v1/requests` with that clinic's capability. HTTP 503, body code `coverage_unknown`, and `retry_after` is present. No new `fallback_admission` row for this request. The unit command fails because weight beyond 5 × `w_max` is not HTTP 503 `coverage_unknown` with `retry_after`.

- [X] T003 [US1] Add the failing test `E2E-P3.9-03 fallback at or after hard_stop_at is coverage_unknown` in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` — red test, FR-002, E2E-P3.9-03. Depends on T002 (same file). `coverClinic()`. `setTestClock` to `coverage_mirror.hard_stop_at` or later. `setAdmissionFault("throw")`. `SELF.fetch` `POST /v1/requests`. Body code `coverage_unknown`. No new `fallback_admission` row. The unit command fails because a clock at or after `hard_stop_at` is not `coverage_unknown`.

- [X] T004 [US1] Add the failing test `E2E-P3.9-04 drain skips a request_id reserved before the admission deadline` in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` — red test, FR-004, E2E-P3.9-04. Depends on T003 (same file). `coverClinic()`. `setAdmissionFault("hold")` with `hold_until` more than 2 seconds ahead of the test clock. Start `SELF.fetch` `POST /v1/requests` without awaiting it. `vendorCall("inspectCoverage")` until a reservation exists. `setTestClock` past that deadline and past `hold_until`. After the fetch settles, `runScheduled("*/5 * * * *")`. That `request_id` is counted once: `usage_event` has one row for it, or the reservation still holds it and `used` did not gain a second `weight`. A second scheduled run still does not add a second `weight`. The admission deadline uses the platform test clock. Do not sleep more than 2 seconds of real time. The unit command fails because the drain does not skip a `request_id` the DO reserved before the deadline.

**Checkpoint**: E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03, and E2E-P3.9-04 exist and fail.

### 3.2 User Story 2 - Pull the coverage feed and read consumer health (Priority: P2)

**Independent Test**: E2E-P3.9-05 and E2E-P3.9-06 in harness H-AP.

- [X] T005 [US2] Add the failing test `E2E-P3.9-05 feed page, token separation, and feedConsumerHealth` in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` — red test, FR-005, FR-006, FR-007, E2E-P3.9-05. Depends on T004 (same file). Insert two `coverage_event` rows directly in D1. Do not call `grant`. `mintFeedToken` and `GET /v1/feed/coverage?after=<first-1>&limit=1` with `Aip-Contract-Version: 1`. Header `Aip-Contract-Version` is `1`. Body is `{contract_version, after, events, next_after, has_more}` with one event, `has_more` true, and `next_after` that event's `feed_seq`. `vendorCall("feedConsumerHealth", { contract_version: 1 })` returns that pull's `last_pull_at`. The same feed token on `POST /v1/requests` is 401. `mintAat` on `GET /v1/feed/coverage` is 401. The unit command fails because `GET /v1/feed/coverage` is not a route and `feedConsumerHealth` is not a method.

- [X] T006 [US2] Add the failing test `E2E-P3.9-06 feed version missing or unsupported is refused before auth` in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` — red test, FR-006, E2E-P3.9-06. Depends on T005 (same file). `GET /v1/feed/coverage` with no `Aip-Contract-Version` and no `Authorization` is HTTP 400 `contract_version_unsupported`. The same call with `Aip-Contract-Version: 2` is HTTP 400 `contract_version_unsupported`. `feed_consumer` has no `last_pull_at`. The unit command fails because a missing or unsupported feed version is not HTTP 400 before authentication.

**Checkpoint**: E2E-P3.9-05 and E2E-P3.9-06 exist and fail.

### 3.3 User Story 3 - Read coverage as an administrator (Priority: P3)

**Independent Test**: E2E-P3.9-07 and E2E-P3.9-08 in harness H-AP. Every earlier suite stays green (rule S2).

- [X] T007 [US3] Add the failing test `E2E-P3.9-07 administrator coverage read does not write the DO` in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` — red test, FR-008, E2E-P3.9-07. Depends on T006 (same file). `coverClinic()`, then a second paid grant so one term is `queued`. `vendorCall("getCoverage")` records `detail`. `mintAat` with `role` `administrator` calls `GET /v1/coverage`. The body has `subscription_ref` equal to `subscriptionRef(org_id)`, `snapshot`, `queued_terms`, and `recent_terms` as in `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/coverage-get.md`. `subscription_ref` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`), computed with no lookup. A second `getCoverage` `detail` is unchanged. `mintAat` with `role` `staff` is HTTP 403 and does not change `getCoverage`. The unit command fails because `GET /v1/coverage` is not a route.

- [X] T008 [US3] Add the failing test `E2E-P3.9-08 GET /v1/usage is 404` in `ai-platform/test/system/fallback-feed-coverage.system.test.ts` — red test, FR-009, E2E-P3.9-08. Depends on T007 (same file). `SELF.fetch` `GET /v1/usage` is HTTP 404. The unit command fails because `GET /v1/usage` is still served.

**Checkpoint**: E2E-P3.9-07 and E2E-P3.9-08 exist and fail.

---

## 4. Implementation

**Purpose**: Sequencing steps 9–20. Each step starts after T001–T008 exist and fail. Within a subphase the tasks run in id order. Do not modify `packages/vendor-contracts`. Do not change `buildCoverageSnapshot`, `lapsedSnapshotReason`, `readCoverageEvents`, or `IssuerTokenVerifier`.

### 4.1 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1) (part 1)

**Independent Test**: E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03, and E2E-P3.9-04 in harness H-AP.

- [X] T009 [US1] Add `ai-platform/migrations/20261006160000_fallback_admission_feed.sql` — produces `fallback_admission` and `feed_consumer`, FR-003, FR-005, E2E-P3.9-01, E2E-P3.9-05. Depends on T008. Match `data-model.md`. Do not edit earlier migrations. Do not drop `entitlement`, `plan`, or `invoice`. Drop `grace_admission_queue`. `fallback_admission` columns are `installation_id`, `idempotency_key`, `term_id`, `weight`, `admitted_at`, `state` (`pending`, `settled`), and `request_id`, keyed by installation and idempotency key, with an index on `state`. `feed_consumer` columns are `consumer`, `last_pull_at`, and `last_cursor`.

- [X] T010 [US1] Add the admission fault and the feed test helpers in `ai-platform/test/system/harness.ts`, honor them on `GatewayObject` in `ai-platform/src/worker.ts`, and accept a caller `requestId` in `admissionRPC` in `ai-platform/src/quota-do/index.ts` — produces `setAdmissionFault`, `mintFeedToken`, and the test-clock fault, FR-001, FR-004, FR-005, FR-007, E2E-P3.9-01, E2E-P3.9-04, E2E-P3.9-05. Depends on T009. Create `harness_admission_fault` (`mode`, `hold_until`) in the harness setup script, not in a product migration. Add `setAdmissionFault` and `mintFeedToken`. Add `feedConsumerHealth` to the `VendorMethod` union. `mintFeedToken` signs with the harness issuer key. Payload bytes are `canonicalize` from `vendor-contracts`. Claims are `iss` of the harness issuer, `aud` `ai-platform-feed`, `sub` `backend-feed`, no `org`, `ver` `"2"`, `jti` a UUID, and `exp - iat` ≤ 120. When `TEST_CLOCK === "1"`, `GatewayObject` reads `harness_admission_fault`. A missing table is ignored. `mode = "throw"` throws before `admissionRPC`. `mode = "hold"` runs `admissionRPC`, then waits until `clockNowMs` is at or past `hold_until`. `admissionRPC` uses a caller `requestId` when the body has one, and otherwise keeps `crypto.randomUUID()`.

- [X] T011 [US1] Export `publishedQuotaWeightMax()` from `ai-platform/src/capability/index.ts` and replace the grace queue in `ai-platform/src/admission/index.ts` — produces mirror fallback admission, FR-001, FR-002, FR-003, E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03. Depends on T010. `publishedQuotaWeightMax()` is the max `Economics.quotaWeight` (missing or non-positive counts as 1) among installed registry manifests whose `Identity.lifecycleState` is not `retired`. Delete `GRACE_ADMISSION_CAP`, `admitUnderGrace`, and the `grace_admission_queue` reads and writes. On DO throw or deadline, read `coverage_mirror` with `SELECT … WHERE installation_id = ?` and no cache. Admit only when `state` is `active` or `grace`, `suspended` is 0, `clockNowIso` is strictly before `hard_stop_at`, the capability id is in `term_snapshot.capabilities`, and pending `fallback_admission.weight` for that installation plus this `w` is at most 5 × `publishedQuotaWeightMax()`. Otherwise return `coverage_unknown` with `retryAfter` so the existing taxonomy answers HTTP 503 and `retry_after`. On admit, insert `fallback_admission` (`term_id` = `term_snapshot.ref`, `request_id` allocated before the DO call, `weight` = `w`, `state` `pending`). A DO throw returns the existing `grace_admitted` outcome so the pipeline does not set `termAdmission` and does not insert `usage_event`. A deadline that fires after the DO has stored that `request_id` returns `admitted` with that `reservationId` and `termId` so the existing credit path counts it once. The deadline race itself is T012.

- [X] T012 [US1] Race the DO call against the platform clock in `ai-platform/src/admission/index.ts` — produces the 2 second admission deadline, FR-001, FR-004, E2E-P3.9-04. Depends on T011 (same file). The admission deadline is `clockNowMs` at the start of the DO call plus 2000. Race the DO call against a loop that resolves when `clockNowMs` has passed that instant. Under `TEST_CLOCK`, each iteration yields so `setTestClock` can move the clock while the call is in flight. Production `clockNowMs` is `Date.now()`, so the limit stays 2 seconds of real time.

- [X] T013 [US1] Add DO kind `settleFallback` on `GatewayObject` in `ai-platform/src/worker.ts`, applied in `ai-platform/src/quota-do/index.ts` — produces the one-time charge, FR-004, E2E-P3.9-01, E2E-P3.9-04. Depends on T012. If a reservation `id` or a replay answer `requestId` equals the row's `request_id`, return skipped and do not change `used`. Otherwise add `weight` to `hot.used` when `term_id` is `hot.active_term_id`, and to that term's `used_final` otherwise. Do not call the grace or lapse transitions.

**Checkpoint**: E2E-P3.9-01 and E2E-P3.9-04 still need the `*/5` drain. E2E-P3.9-02 and E2E-P3.9-03 still need the unit command after T011.

### 4.2 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1) (part 2)

**Independent Test**: E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03, and E2E-P3.9-04 in harness H-AP.

- [X] T014 [US1] Replace the body of `reconcileGraceUsage` in `ai-platform/src/credit/index.ts` and call it only from the `*/5` branch in `ai-platform/src/worker.ts` — produces the fallback drain, FR-004, E2E-P3.9-01, E2E-P3.9-04. Depends on T013. Select `fallback_admission` where `state` is `pending`. Skip a row whose `request_id` the DO still holds or that already has a `usage_event` (leave it `pending` when the DO still holds it; do not add `used`). Otherwise call `settleFallback`, `INSERT OR IGNORE` into `usage_event` on that `request_id`, and set `state` to `settled`. Remove the 2-hour drop and the zero-credit reconcile. Call this function only from the `scheduled` branch `cron === "*/5 * * * *"`, not from the other crons. Leave `runFiveMinuteCron` on that branch.

**Checkpoint**: E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03, and E2E-P3.9-04 still need the unit command after T014. E2E-P3.9-05 through E2E-P3.9-08 still fail.

### 4.3 User Story 2 - Pull the coverage feed and read consumer health (Priority: P2)

**Independent Test**: E2E-P3.9-05 and E2E-P3.9-06 in harness H-AP.

- [X] T015 [US2] Handle `GET /v1/feed/coverage` version negotiation in `ai-platform/src/worker.ts` — produces the pre-auth refusal, FR-006, E2E-P3.9-06. Depends on T014 (same file). Call `negotiate(CHANNEL_VERSIONS.platformFeed, …)` before the `Authorization` header is read and before any D1 write. Failure is HTTP 400 `{code: "contract_version_unsupported", accepted_versions}` and does not update `feed_consumer`.

- [X] T016 [US2] Verify the feed token and return the coverage page from `ai-platform/src/worker.ts` — produces the feed page and `feed_consumer.last_pull_at`, FR-005, FR-007, E2E-P3.9-05. Depends on T015 (same file). After the version check, verify the bearer token with `validateTokenClaims` for audience `ai-platform-feed`, using the issuer key already loaded for AI tokens. Failure is 401 and does not update `feed_consumer`. Success reads `coverage_event` as in `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/feed-coverage.md`, echoes `Aip-Contract-Version`, and upserts `feed_consumer` for `consumer` `backend-feed`. The body is `{contract_version, after, events, next_after, has_more}`. Each event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`. Pages are not signed. A feed token stays invalid for `IssuerTokenVerifier` on `POST /v1/requests`.

- [X] T017 [US2] Add `feedConsumerHealth` on `VendorEntrypoint` in `ai-platform/src/vendor/entrypoint.ts` — produces `last_pull_at` and `last_cursor`, FR-007, E2E-P3.9-05. Depends on T016. Class M, per `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/feed-consumer-health.md`. Beyond `contract_version` it takes no input. It reads `feed_consumer` and does not write.

**Checkpoint**: E2E-P3.9-05 and E2E-P3.9-06 still need the unit command after T017. E2E-P3.9-07 and E2E-P3.9-08 still fail.

### 4.4 User Story 3 - Read coverage as an administrator (Priority: P3)

**Independent Test**: E2E-P3.9-07 and E2E-P3.9-08 in harness H-AP. Every earlier suite stays green (rule S2).

- [X] T018 [US3] Add `ai-platform/src/coverage-read/index.ts` and `GET /v1/coverage` in `ai-platform/src/worker.ts` — produces the administrator coverage read, FR-008, E2E-P3.9-07. Depends on T017. Per `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/contracts/coverage-get.md`. Version check uses the existing clinic helper (`requireAipContractVersion` / `withAipContractVersion`, `CHANNEL_VERSIONS.platformClinic`). `role` other than `administrator` is HTTP 403 and does not call the DO. The administrator path calls DO kind `read_coverage` only and `subscriptionRef(org_id)`. `subscription_ref` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`), computed with no lookup. The read does not write the DO. `queued_terms` is the unheld terms in state `queued`, in ascending `position`. Each object is `{plan_id, plan_version, plan_display_name, duration_unit, duration_count}`. `recent_terms` is at most the last 12 terms whose state is `active`, `grace`, or `ended`, highest `position` first. Each object is `{term_id, state, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used}`. `used` is the `hot` row's `used` when the term is `hot.active_term_id`, and `used_final` otherwise.

- [X] T019 [US3] Remove `GET /v1/usage` from `ai-platform/src/worker.ts`, and delete `ai-platform/src/usage-summary/index.ts` and `ai-platform/test/usage-summary.test.ts` — produces HTTP 404, FR-009, E2E-P3.9-08. Depends on T018. Remove that test from `ai-platform/vitest.config.ts`. `GET /v1/usage` falls through to HTTP 404. `src/coverage-read/index.ts` replaces `src/usage-summary/index.ts`.

**Checkpoint**: E2E-P3.9-07 and E2E-P3.9-08 still need the unit command after T019. Earlier suites still mention `grace_admission_queue` or `src/usage-summary` until T020 and T021.

### 4.5 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1) — existing suite updates

**Independent Test**: E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03, and E2E-P3.9-04 in harness H-AP. Every earlier suite stays green (rule S2).

- [ ] T020 [US1] Update the existing files that still mention `grace_admission_queue`, `GRACE_ADMISSION_CAP`, or the 2-hour grace drop — produces suites that do not require the dropped table or the old drain, FR-003, FR-004, FR-005, E2E-P3.9-01, E2E-P3.9-04. Depends on T014 and T019. `ai-platform/src/retention/index.ts` stops deleting `grace_admission_queue`. `ai-platform/test/migrations.test.ts` expects `fallback_admission` and `feed_consumer` and does not require `grace_admission_queue`. The same expectation update applies to `ai-platform/test/admission-credit.test.ts`, `ai-platform/test/retention.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/support-purge.test.ts`, `ai-platform/test/system/cron-retention-interplay.system.test.ts`, `ai-platform/test/e2e/harness/d1.ts`, `ai-platform/test/e2e/harness/env.ts`, `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts`, `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts`, `ai-platform/test/e2e/stage-09-adapter-identity.test.ts`, `ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts`, `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts`, `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts`, `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts`, `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts`, `ai-platform/test/e2e/stage-X-grace-retention.test.ts`, `ai-platform/test/e2e/stage-X-cron-flush-reconcile.test.ts`, and `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts`. Do not require `reconcileGraceUsage` to drop rows after two hours.

### 4.6 User Story 3 - Read coverage as an administrator (Priority: P3) — usage-route assertions

**Independent Test**: E2E-P3.9-08 in harness H-AP. Every earlier suite stays green (rule S2).

- [ ] T021 [US3] Update `ai-platform/test/worker-entry.test.ts` — produces assertions that do not require `src/usage-summary` or `GET /v1/usage`, FR-009, E2E-P3.9-08. Depends on T019. This file does not share a path with T020.

**Checkpoint**: Earlier suites match the dropped table, the fallback drain, and the removed usage route. The unit file is ready for the harness command.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes. Earlier suites are the review's run (rule S2). This task does not name that run. Sequencing step 21's path check is this command: the only vitest path is the unit file, and `ai-platform/src/coverage-read/index.ts` is reached from `GET /v1/coverage`.

### 5.1 Unit harness

- [ ] T022 Run harness H-AP for this unit and confirm E2E-P3.9-01 through E2E-P3.9-08 pass together — produces the green run, FR-001 through FR-009, E2E-P3.9-01 through E2E-P3.9-08. Depends on T009 through T021 (and therefore on T001–T008). This task may edit only `ai-platform/test/system/fallback-feed-coverage.system.test.ts`. `packages/vendor-contracts/**` stays unchanged. `buildCoverageSnapshot`, `lapsedSnapshotReason`, `readCoverageEvents`, and `IssuerTokenVerifier` stay unchanged. SC-002 is the review's run of earlier suites, not this command.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/fallback-feed-coverage.system.test.ts
```

---

## 6. Documentation

**Purpose**: Written after T022 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` and `contracts/` stay plan-phase artifacts. No other doc task.

### 6.1 Quickstart

- [ ] T023 Create `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-009, E2E-P3.9-01 through E2E-P3.9-08. Depends on T022. Sections: (1) what was implemented — fallback admission from `coverage_mirror`, the `*/5` drain, `GET /v1/feed/coverage`, `feedConsumerHealth`, administrator `GET /v1/coverage`, and removal of `GET /v1/usage`; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) harness command for this unit's tests only — the command below; (4) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/fallback-feed-coverage.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

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

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests**: T001 through T008, in Sequencing steps 1–8. No Setup phase.
- **Implementation**: T009 through T021, after those tests exist and fail. T009 through T019 are Sequencing steps 9–19. T020 and T021 are Sequencing step 20, after the table drop, the drain replacement, and the usage removal.
- **Verification**: T022, after T009 through T021.
- **Documentation**: T023, after T022 is green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: T001–T004, then T009–T014. T020 updates the existing grace-queue and drain suites after T014 and after T019 has removed the usage route. Fallback admission and the `*/5` drain are the path E2E-P3.9-01 through E2E-P3.9-04 call.
- **User Story 2 (P2)**: T005–T006 after the User Story 1 tests, because they share `ai-platform/test/system/fallback-feed-coverage.system.test.ts`. Implementation T015–T017 starts after T014. T015 and T016 edit `ai-platform/src/worker.ts`. T017 edits `ai-platform/src/vendor/entrypoint.ts` after the feed route writes `feed_consumer`.
- **User Story 3 (P3)**: T007–T008 after T006 (same test file). T018 starts after T017 and edits `ai-platform/src/worker.ts` and `ai-platform/src/coverage-read/index.ts`. T019 follows T018 on `ai-platform/src/worker.ts` and deletes the usage-summary module and its unit test. T021 follows T019 and edits only `ai-platform/test/worker-entry.test.ts`.

### 7.3 Parallel Opportunities

- T001–T008 are not marked `[P]`. They all write `ai-platform/test/system/fallback-feed-coverage.system.test.ts`.
- T009 writes only `ai-platform/migrations/20261006160000_fallback_admission_feed.sql`. T010 writes `ai-platform/test/system/harness.ts`, `ai-platform/src/worker.ts`, and `ai-platform/src/quota-do/index.ts`. T011 writes `ai-platform/src/capability/index.ts` and `ai-platform/src/admission/index.ts`. T012 writes `ai-platform/src/admission/index.ts`. T013 writes `ai-platform/src/worker.ts` and `ai-platform/src/quota-do/index.ts`. They stay in id order.
- T014 writes `ai-platform/src/credit/index.ts` and `ai-platform/src/worker.ts` only after T013.
- T015 and T016 write `ai-platform/src/worker.ts` only after T014. T017 writes `ai-platform/src/vendor/entrypoint.ts` only after T016.
- T018 writes `ai-platform/src/coverage-read/index.ts` and `ai-platform/src/worker.ts` only after T017. T019 writes `ai-platform/src/worker.ts`, deletes `ai-platform/src/usage-summary/index.ts` and `ai-platform/test/usage-summary.test.ts`, and edits `ai-platform/vitest.config.ts` only after T018.
- T020 writes `ai-platform/src/retention/index.ts` and the existing grace-queue test files named in that task. T021 writes only `ai-platform/test/worker-entry.test.ts`. Both follow T019. They do not share a path.
- T022 and T023 are single tasks. T023 waits until T022 is green.

---

## 8. Implementation Waves

### Wave 1

- T001–T004 [US1] — subphase: `### 3.1 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1)` — paths: `ai-platform/test/system/fallback-feed-coverage.system.test.ts`

### Wave 2

- T005–T006 [US2] — subphase: `### 3.2 User Story 2 - Pull the coverage feed and read consumer health (Priority: P2)` — paths: `ai-platform/test/system/fallback-feed-coverage.system.test.ts`

### Wave 3

- T007–T008 [US3] — subphase: `### 3.3 User Story 3 - Read coverage as an administrator (Priority: P3)` — paths: `ai-platform/test/system/fallback-feed-coverage.system.test.ts`

### Wave 4

- T009–T013 [US1] — subphase: `### 4.1 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1) (part 1)` — paths: `ai-platform/migrations/20261006160000_fallback_admission_feed.sql`, `ai-platform/test/system/harness.ts`, `ai-platform/src/worker.ts`, `ai-platform/src/quota-do/index.ts`, `ai-platform/src/capability/index.ts`, `ai-platform/src/admission/index.ts`

### Wave 5

- T014 [US1] — subphase: `### 4.2 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1) (part 2)` — paths: `ai-platform/src/credit/index.ts`, `ai-platform/src/worker.ts`

### Wave 6

- T015–T017 [US2] — subphase: `### 4.3 User Story 2 - Pull the coverage feed and read consumer health (Priority: P2)` — paths: `ai-platform/src/worker.ts`, `ai-platform/src/vendor/entrypoint.ts`

### Wave 7

- T018–T019 [US3] — subphase: `### 4.4 User Story 3 - Read coverage as an administrator (Priority: P3)` — paths: `ai-platform/src/coverage-read/index.ts`, `ai-platform/src/worker.ts`, `ai-platform/src/usage-summary/index.ts`, `ai-platform/test/usage-summary.test.ts`, `ai-platform/vitest.config.ts`

### Wave 8

- T020 [US1] — subphase: `### 4.5 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1) — existing suite updates` — paths: `ai-platform/src/retention/index.ts`, `ai-platform/test/migrations.test.ts`, `ai-platform/test/admission-credit.test.ts`, `ai-platform/test/retention.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/support-purge.test.ts`, `ai-platform/test/system/cron-retention-interplay.system.test.ts`, `ai-platform/test/e2e/harness/d1.ts`, `ai-platform/test/e2e/harness/env.ts`, `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts`, `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts`, `ai-platform/test/e2e/stage-09-adapter-identity.test.ts`, `ai-platform/test/e2e/stage-09-admission-journal-compose.test.ts`, `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts`, `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts`, `ai-platform/test/e2e/stage-11-completed-failed-cancelled.test.ts`, `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts`, `ai-platform/test/e2e/stage-X-grace-retention.test.ts`, `ai-platform/test/e2e/stage-X-cron-flush-reconcile.test.ts`, `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts`
- T021 [US3] — subphase: `### 4.6 User Story 3 - Read coverage as an administrator (Priority: P3) — usage-route assertions` — paths: `ai-platform/test/worker-entry.test.ts`

### Wave 9

- T022 — subphase: `### 5.1 Unit harness` — paths: `ai-platform/test/system/fallback-feed-coverage.system.test.ts`

### Wave 10

- T023 — subphase: `### 6.1 Quickstart` — paths: `specs/073-abo-p3-9-fallback-admission-coverage-feed-administrator/quickstart.md`
