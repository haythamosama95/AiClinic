# Tasks: Control-plane port to `VendorEntrypoint` and removal of `/control/*`

**Input**: Design documents from `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P3.8 has none. P3.9: the HTTP feed contract (`handleFeedCoverageRequest` for `GET /v1/feed/coverage`), the `/v1/coverage` response (`handleCoverageReadRequest`), and `feedConsumerHealth`. This unit does not change those. Plan artifacts from `AVAILABLE_DOCS`: none. There is no `research.md`, no `data-model.md`, and no `contracts/`. `quickstart.md` is written in Documentation after verification.

**Organization**: Four user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`, `[US4]`). Tests are one task per E2E id that is added to the unit file, written to fail before the class-H methods, the `/control/*` removal, and the cron change exist. Test Layout names no extra new test file. E2E-P3.10-08 is the rewritten catalogues (Sequencing step 30), not a case in the unit file. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. No Foundational phase. No Polish phase. Task ids follow plan Sequencing. Sequencing step 18 is two tasks because the two migration files do not share a path.

**Task count**: 32. Size L is 32–40 (rule S3). The count is seven E2E tasks in the unit file (Sequencing steps 1–7), twenty-one implementation steps (8–28) with step 18 split into the two migration files, one unit-harness task (step 29), the E2E-P3.10-08 catalogue task (step 30), and `quickstart.md`. It is not padded. `npm test` from the repository root is not a task.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — the Files paths in `plan.md`
- **ABO**: `abo/` — this unit does not change it. The harness does not start an ABO worker
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified
- **Spec Kit artifacts**: `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/`
- Do not edit earlier migrations. Do not modify `packages/vendor-contracts`. Do not change `handleFeedCoverageRequest`, `GET /v1/feed/coverage`, `handleCoverageReadRequest`, `GET /v1/coverage`, or `feedConsumerHealth` (rule S7). Do not change `publishPlanVersion`, `retirePlanVersion`, `inspectCoverage`, `suspend`, `resume`, or `deleteInstallation` result rules. `workers_dev` and `preview_urls` stay false. Viewer and `docs/testing/catalog` stay until P7.1. Console relays stay until P4.9.

---

## 3. Tests

**Purpose**: One failing test per E2E id in Sequencing steps 1–7, under H-AP, in that order. Story sections follow that order. Every test is added to `ai-platform/test/system/control-plane-port.system.test.ts`. The unit command is that file only, under `vitest.workers.config.ts`. Class-H calls use `vendorCall(method, args, { accessJwt })` with the harness Access JWT (`VENDOR_OPERATOR_EMAIL`). No assertion object. No `sleep` over 2 s. No ABO worker is constructed. A class-H success is `result` `ok`, `code` empty, `receipt` absent, and `detail` the JSON text of the object the handler returns today.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/control-plane-port.system.test.ts
```

### 3.1 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2)

**Independent Test**: E2E-P3.10-01 in harness H-AP.

- [ ] T001 [US2] Add the failing test `E2E-P3.10-01 former /control paths are 404 and the worker boots without the bearer` in `ai-platform/test/system/control-plane-port.system.test.ts` — red test, FR-007, FR-008, E2E-P3.10-01. `SELF.fetch` POST for one path of each pattern `isControlRoute` accepts: `/control/installations/{id}/suspend`, `resume`, `delete`, `purge`, `entitle`, `override`; `/control/capabilities/{id}/versions/{ver}/deprecate`, `retire`, `activate`, `promote`; `/control/routing-policies/publish`; `/control/routing-policies/{id}/versions/{ver}/canary`, `promote`, `rollback`; `/control/token-contract/begin-rotation`, `retire`; `/control/support/lookup`; `/control/kill-switches/arm`, `disarm`; `/control/plans/create`; `/control/plans/{id}/update`, `delete`; `/control/credit-price/activate`. GET `/control/installations/{id}/quota`. Every response is 404. The workers binding set for this run has no `OPERATOR_BEARER_TOKEN`, and the worker has already loaded. The unit command fails because former `/control/*` paths are not all 404.

**Checkpoint**: E2E-P3.10-01 exists and fails.

### 3.2 User Story 1 - Operate configuration and support lookup on VendorEntrypoint (Priority: P1)

**Independent Test**: E2E-P3.10-02, E2E-P3.10-03, E2E-P3.10-04, E2E-P3.10-05, and E2E-P3.10-06 in harness H-AP.

- [ ] T002 [US1] Add the failing test `E2E-P3.10-02 routing policy publish canary promote and traffic follows` in `ai-platform/test/system/control-plane-port.system.test.ts` — red test, FR-001, FR-002, E2E-P3.10-02. Depends on T001 (same file). Port of SYS suite 4 (`ai-platform/test/system/routing-policy-traffic.system.test.ts`): `coverClinic` and `newClinic`, then `publishRoutingPolicy`, `canaryRoutingPolicy`, and `promoteRoutingPolicy` over `env.VENDOR`. The promoted version is `active`, the previous version is `superseded`, and `POST /v1/requests` is served with that promoted policy. The unit command fails because `publishRoutingPolicy` is not a method.

- [ ] T003 [US1] Add the failing test `E2E-P3.10-03 kill switch answers capability_disabled and raises AL-19` in `ai-platform/test/system/control-plane-port.system.test.ts` — red test, FR-001, FR-003, E2E-P3.10-03. Depends on T002 (same file). `armKillSwitch` for a capability. `POST /v1/requests` for that capability is `capability_disabled`. `platform_alert.code` is `AL-19`. `control_audit.actor` is the Access email. `control_audit.assertion_sha256` is stored (null when the call has no assertion). The unit command fails because `armKillSwitch` is not a method.

- [ ] T004 [US1] Add the failing test `E2E-P3.10-04 capability deprecate and retire show on discovery` in `ai-platform/test/system/control-plane-port.system.test.ts` — red test, FR-001, FR-004, E2E-P3.10-04. Depends on T003 (same file). `deprecateCapability` and `retireCapability` over `env.VENDOR`. `GET /v1/capabilities` reflects `deprecated` and then `retired`. The unit command fails because `deprecateCapability` is not a method.

- [ ] T005 [US1] Add the failing test `E2E-P3.10-05 token-contract rotation leaves version 2 current` in `ai-platform/test/system/control-plane-port.system.test.ts` — red test, FR-001, FR-005, E2E-P3.10-05. Depends on T004 (same file). `beginTokenContractRotation` over `env.VENDOR`. `token_contract` ver `2` has `retired_at` null. A repeat is the current-version success, not a conflict. The unit command fails because `beginTokenContractRotation` is not a method.

- [ ] T006 [US1] Add the failing test `E2E-P3.10-06 supportLookup by subscription ref and by reference` in `ai-platform/test/system/control-plane-port.system.test.ts` — red test, FR-006, E2E-P3.10-06. Depends on T005 (same file). `supportLookup` with the clinic's `subscriptionRef` returns that clinic's requests. `supportLookup` with the request reference returns the envelope within retention. The unit command fails because `supportLookup` is not a method.

**Checkpoint**: E2E-P3.10-02, E2E-P3.10-03, E2E-P3.10-04, E2E-P3.10-05, and E2E-P3.10-06 exist and fail.

### 3.3 User Story 3 - Run retention and rollup without the monthly period close (Priority: P3)

**Independent Test**: E2E-P3.10-07 in harness H-AP.

- [ ] T007 [US3] Add the failing test `E2E-P3.10-07 monthly period close is gone and 0 3 and 0 4 run retention and rollup` in `ai-platform/test/system/control-plane-port.system.test.ts` — red test, FR-010, FR-011, E2E-P3.10-07. Depends on T006 (same file). `[triggers].crons` in `ai-platform/wrangler.toml` has `0 3 * * *`, `0 4 * * *`, and `*/5 * * * *`, and does not have `0 5 1 * *`. `runScheduled("0 3 * * *")` runs retention. `runScheduled("0 4 * * *")` runs rollup whose dimensions include `term_id`. The unit command fails because `[triggers].crons` still lists `0 5 1 * *`.

**Checkpoint**: E2E-P3.10-07 exists and fails.

---

## 4. Implementation

**Purpose**: Sequencing steps 8–28. Each step starts after T001–T007 exist and fail. Within a subphase the tasks run in id order. Do not modify `packages/vendor-contracts`. Do not change the feed route, the coverage read, or `feedConsumerHealth`.

### 4.1 User Story 1 - Operate configuration and support lookup on VendorEntrypoint (Priority: P1) (part 1)

**Independent Test**: E2E-P3.10-02, E2E-P3.10-03, E2E-P3.10-04, E2E-P3.10-05, and E2E-P3.10-06 in harness H-AP.

- [ ] T008 [US1] Add the thirteen class-H names to `METHOD_CLASS` in `ai-platform/src/vendor/entrypoint.ts` and to `VendorMethod` in `ai-platform/test/system/harness.ts` — produces the method names, FR-001, FR-006, E2E-P3.10-02. Depends on T007. Names: `publishRoutingPolicy`, `canaryRoutingPolicy`, `promoteRoutingPolicy`, `rollbackRoutingPolicy`, `armKillSwitch`, `disarmKillSwitch`, `deprecateCapability`, `retireCapability`, `activateCohort`, `promoteCohort`, `beginTokenContractRotation`, `retireTokenContract`, `supportLookup`. All are class H. Each method checks `access_jwt` with `verifyHpAccess` and negotiates the vendor channel. No assertion is required.

- [ ] T009 [US1] Implement `publishRoutingPolicy`, `canaryRoutingPolicy`, `promoteRoutingPolicy`, and `rollbackRoutingPolicy` on `VendorEntrypoint` — produces routing policy over the entrypoint, FR-001, FR-002, E2E-P3.10-02. Depends on T008. Files: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/control/routing-policy.ts`. They call the existing logic in `src/control/routing-policy.ts`. Input fields stay the handler bodies today (`document`, policy id, version, canary installation ids). Success `detail` is that handler's ok object. Illegal transitions stay rejected with the handler's current code. Drop the `Request` and bearer arguments from that module.

- [ ] T010 [US1] Implement `armKillSwitch` and `disarmKillSwitch` on `VendorEntrypoint` — produces the kill switch, AL-19, and the Access-email actor, FR-001, FR-003, E2E-P3.10-03. Depends on T009. Files: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/control/kill-switch.ts`, `ai-platform/src/control/audit.ts`. They call the existing logic in `src/control/kill-switch.ts` (`scope`, `target`). The actor passed into `writeEntrypointAudit` is the Access email. `assertion_sha256` is the column value (null on class H). On a kill-switch change, call `raiseAl19FromOutbox` so `platform_alert.code` is `AL-19` and the email body is that code plus ids. A live `POST /v1/requests` for an armed capability still returns `capability_disabled` through the existing capability check.

- [ ] T011 [US1] Implement `deprecateCapability` and `retireCapability` on `VendorEntrypoint` — produces capability lifecycle over the entrypoint, FR-001, FR-004, E2E-P3.10-04. Depends on T010. Files: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/control/capability-lifecycle.ts`. They call the existing logic in `src/control/capability-lifecycle.ts`. `GET /v1/capabilities` already reads the overlay those handlers write. Drop the `Request` and bearer arguments.

- [ ] T012 [US1] Implement `beginTokenContractRotation` and `retireTokenContract` on `VendorEntrypoint` — produces token-contract rotation, FR-001, FR-005, E2E-P3.10-05. Depends on T011. Files: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/control/token-contract.ts`. `beginTokenContractRotation` uses `src/control/token-contract.ts` to make ver `"2"` current (`retired_at` null). If ver `2` is already current, the result is `ok` and nothing else is inserted. `retireTokenContract` keeps today's retire rules. Drop the caller-supplied `ver` on the rotation method. Drop the `Request` and bearer arguments.

**Checkpoint**: E2E-P3.10-02, E2E-P3.10-03, E2E-P3.10-04, and E2E-P3.10-05 have their class-H methods. The unit file is not required to pass until verification.

### 4.2 User Story 1 - Operate configuration and support lookup on VendorEntrypoint (Priority: P1) (part 2)

**Independent Test**: E2E-P3.10-02, E2E-P3.10-03, E2E-P3.10-04, E2E-P3.10-05, and E2E-P3.10-06 in harness H-AP.

- [ ] T013 [US1] Implement class-H `supportLookup` — produces lookup by reference, subscription ref, and org, FR-006, E2E-P3.10-06. Depends on T012. Files: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/support/index.ts`. `src/support/index.ts` still looks up by request reference and returns the envelope within retention. The same function also accepts a subscription ref (`subscriptionRef(org_id)` from `vendor-contracts`) and an `org_id`, and returns that clinic's requests via `tenant_binding.installation_id` and `ai_request.installation_id`. One of reference, subscription ref, or `org_id` is required.

- [ ] T014 [US1] Take cohort plan membership from `plan_version` and expose `activateCohort` and `promoteCohort` — produces cohort grants without `entitlement`, FR-001, E2E-P3.10-08. Depends on T013. Files: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/control/cohort.ts`. Replace the `entitlement` select with published `plan_version` rows (`plan_id`, `capabilities` where `status = 'published'`) for plan-scoped grants, and active `tenant_binding` rows whose `coverage_mirror.term_snapshot` capabilities include the capability for installation grants. `activateCohort` and `promoteCohort` call that logic. The actor stored as `changed_by` is the Access email.

**Checkpoint**: E2E-P3.10-06 has `supportLookup`. Cohort is reached later by the rewritten catalogue (E2E-P3.10-08).

### 4.3 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2) (part 1)

**Independent Test**: E2E-P3.10-01 in harness H-AP.

- [ ] T015 [US2] Remove the `/control/*` dispatch and delete the HTTP control modules — produces 404 for former control paths, FR-007, E2E-P3.10-01. Depends on T014. Remove the `isControlRoute` branch from `ai-platform/src/worker.ts` `fetch`. Delete `ai-platform/src/control/index.ts`, `ai-platform/src/control/auth.ts`, `ai-platform/src/control/http.ts`, `ai-platform/src/control/entitle.ts`, and `ai-platform/src/control/credit-price.ts`. Kept modules stop importing `http.ts`. `ai-platform/src/control/audit.ts` keeps its id and timestamp helpers locally. Delete `ai-platform/src/period-close/index.ts` and the `cron === "0 5 1 * *"` branch in `scheduled`. `0 3 * * *` stays `runRetentionPurge`. `0 4 * * *` stays `runRollupAndReconciliation` (already grouped by `term_id`). The `*/5 * * * *` branch stays. `GET /v1/feed/coverage` and `GET /v1/coverage` stay.

- [ ] T016 [US2] Delete the remaining HTTP-only control modules and narrow `types.ts` — produces entrypoint methods without those HTTP handlers, FR-008, E2E-P3.10-01. Depends on T015. Delete `ai-platform/src/control/lifecycle.ts`, `ai-platform/src/control/plan.ts`, `ai-platform/src/control/quota-inspect.ts`, and `ai-platform/src/control/support-purge.ts`. `suspend`, `resume`, `deleteInstallation`, `publishPlanVersion`, `retirePlanVersion`, and `inspectCoverage` stay on `VendorEntrypoint` unchanged. `ai-platform/src/control/types.ts` keeps only the types the remaining control modules use.

- [ ] T017 [US2] Drop `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID` from `Env` — produces a worker that boots without the bearer, FR-008, E2E-P3.10-01. Depends on T016. File: `ai-platform/src/worker.ts`. `Env` drops `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID`. Boot does not read either binding. `assertRequiredBindings` stays DB, R2, and DO.

**Checkpoint**: The `/control/*` dispatch, the shared bearer, and `OPERATOR_ID` are gone from the worker. E2E-P3.10-01 is confirmed in verification.

### 4.4 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2) — drop invoicing

**Independent Test**: E2E-P3.10-01 in harness H-AP.

- [ ] T018 [US2] Add `ai-platform/migrations/20261006170000_drop_invoicing.sql` — produces the invoicing drop, FR-009, E2E-P3.10-08. Depends on T017. `DROP TABLE IF EXISTS invoice` and `DROP TABLE IF EXISTS credit_price`. Do not edit earlier migrations.

### 4.5 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2) — drop plan and entitlement

**Independent Test**: E2E-P3.10-01 in harness H-AP.

- [ ] T019 [US2] Add `ai-platform/migrations/20261006170100_drop_plan_entitlement.sql` — produces the plan and entitlement drop, FR-009, E2E-P3.10-08. Depends on T017. `DROP TABLE IF EXISTS plan`, `DROP TABLE IF EXISTS entitlement`, and `DROP TABLE IF EXISTS grace_admission_queue`. Do not edit earlier migrations.

**Checkpoint**: Both drop migrations exist. Readers of those tables are removed in the next task.

### 4.6 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2) — readers

**Independent Test**: E2E-P3.10-01 in harness H-AP.

- [ ] T020 [US2] Stop reading `plans` and `entitlements` from the config cache and admission — produces readers that survive the drop, FR-009, E2E-P3.10-08. Depends on T018 and T019. Files: `ai-platform/src/config-cache/index.ts`, `ai-platform/src/admission/index.ts`. In `src/config-cache/index.ts`, the `plans` and `entitlements` reader cases return `"miss"` and do not query those tables. In `src/admission/index.ts`, delete `loadInstallationEntitlement` and use the snapshot object already built in the `??` branch. Do not change the fallback conditions, `fallback_admission` insert, or `GET /v1/feed/coverage`.

**Checkpoint**: Transitional `invoice`, `credit_price`, `plan`, and `entitlement` tables are dropped and unread.

### 4.7 User Story 3 - Run retention and rollup without the monthly period close (Priority: P3)

**Independent Test**: E2E-P3.10-07 in harness H-AP.

- [ ] T021 [US3] Remove `OPERATOR_ID` and `0 5 1 * *` from `ai-platform/wrangler.toml` — produces the final cron list and vars, FR-010, FR-011, E2E-P3.10-07. Depends on T020. Remove `OPERATOR_ID` from development, staging, and production vars, and remove `0 5 1 * *` from `[triggers].crons`. Leave `workers_dev`, `preview_urls`, the DO class, rate limits, Access vars, `ISSUER_ID`, `PLATFORM_SIGNING_KEY`, `HEARTBEAT_URL`, `send_email`, and staging-only `DURATION_SCALE` as they are.

**Checkpoint**: E2E-P3.10-07's cron list matches this file. The scheduled run is confirmed in verification.

### 4.8 User Story 4 - Finish the harness migration off the bearer (Priority: P4) (part 1)

**Independent Test**: E2E-P3.10-08 in harness H-AP and the e2e catalogue. Every earlier suite stays green (rule S2).

- [ ] T022 [US4] Delete `operatorFetch` and `operatorFetchRaw` from `ai-platform/test/system/harness.ts` — produces system helpers on `vendorCall`, FR-012, E2E-P3.10-08. Depends on T021. Point `publishPolicy`, `canary`, `promote`, and `rollback` at the new `vendorCall` methods.

- [ ] T023 [US4] Rewrite the e2e control harness off the bearer — produces Access JWT and passkey calls on `VendorEntrypoint`, FR-012, E2E-P3.10-08. Depends on T022. Files: `ai-platform/test/e2e/harness/control.ts`, `ai-platform/test/e2e/harness/env.ts`. Call `VendorEntrypoint` with test Access JWTs and test passkey assertions, and mint issuer tokens with the test issuer key. Remove `OPERATOR_BEARER_TOKEN` from those files.

- [ ] T024 [US4] Delete the 04 §6.5 Delete-row suites and drop them from the workers include list — produces a catalogue without those files, FR-012, E2E-P3.10-08. Depends on T023. Delete `ai-platform/test/period-close.test.ts`, `ai-platform/test/price-list-activation.test.ts`, `ai-platform/test/entitle-grant.test.ts`, `ai-platform/test/e2e/stage-03-enroll-validation.test.ts`, `ai-platform/test/e2e/stage-03-lifecycle-rotate.test.ts`, `ai-platform/test/e2e/stage-04-entitle-auth-period.test.ts`, and `ai-platform/test/e2e/stage-04-entitle-quota-grants-validation.test.ts`. Remove those workers-pool files from the `include` list in `ai-platform/vitest.workers.config.ts`.

- [ ] T025 [US4] Replace `ai-platform/test/control.test.ts` with `ai-platform/test/vendor-entrypoint.test.ts` — produces class-H coverage without a bearer, FR-012, E2E-P3.10-08. Depends on T024. The new file calls the class-H methods on `env.VENDOR` and does not send a bearer. Point the workers `include` list in `ai-platform/vitest.workers.config.ts` at the new file. Drop cases that only asserted a deleted HTTP handler. Delete `ai-platform/test/control.test.ts`.

- [ ] T026 [US4] Rewrite system tests that still call `operatorFetch` or `/control/*` — produces system suites on `vendorCall`, FR-012, E2E-P3.10-08. Depends on T025. Files: `ai-platform/test/system/golden-journey.system.test.ts`, `ai-platform/test/system/settlement-integrity.system.test.ts`, `ai-platform/test/system/entitlement-grant-interplay.system.test.ts`, `ai-platform/test/system/token-contract-rotation.system.test.ts`, `ai-platform/test/system/issuer-tokens.system.test.ts`, `ai-platform/test/system/capability-lifecycle.system.test.ts`, `ai-platform/test/system/lifecycle-interplay.system.test.ts`, `ai-platform/test/system/cron-retention-interplay.system.test.ts`, `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts`, `ai-platform/test/system/routing-policy-traffic.system.test.ts`. Use `vendorCall`, `coverClinic`, and `newClinic`. Leave `handleFeedCoverageRequest` and `GET /v1/coverage` assertions as they are. Do not edit `ai-platform/test/system/control-plane-port.system.test.ts` here.

**Checkpoint**: `operatorFetch` is gone. The e2e harness and the named system suites call `VendorEntrypoint`.

### 4.9 User Story 4 - Finish the harness migration off the bearer (Priority: P4) (part 2)

**Independent Test**: E2E-P3.10-08 in harness H-AP and the e2e catalogue. Every earlier suite stays green (rule S2).

- [ ] T027 [US4] Rewrite e2e tests that still enroll or entitle through `/control/*` — produces those suites on `vendorCall`, FR-012, E2E-P3.10-08. Depends on T026. Rewrite each listed file that still enrolls or entitles through `/control/*` the same way as T026 (`vendorCall`, `coverClinic`, `newClinic`). Leave a listed file unchanged when it does not. Leave `GET /v1/coverage` and feed assertions as they are. Files: `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts`, `ai-platform/test/e2e/stage-00-boot-bindings-routing.test.ts`, `ai-platform/test/e2e/stage-01-auth-validation.test.ts`, `ai-platform/test/e2e/stage-01-rotation-retire.test.ts`, `ai-platform/test/e2e/stage-03-auth-routing.test.ts`, `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts`, `ai-platform/test/e2e/stage-04-cohort-promote-deprecate.test.ts`, `ai-platform/test/e2e/stage-04-deprecate-retire-auth.test.ts`, `ai-platform/test/e2e/stage-04-entitle-happy-cohort-activate.test.ts`, `ai-platform/test/e2e/stage-05-canary-promote.test.ts`, `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts`, `ai-platform/test/e2e/stage-05-publish.test.ts`, `ai-platform/test/e2e/stage-05-rollback-serving.test.ts`, `ai-platform/test/e2e/stage-07-entitlement-filters.test.ts`, `ai-platform/test/e2e/stage-07-etag-cache.test.ts`, `ai-platform/test/e2e/stage-08-trace-auth.test.ts`, `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts`, `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts`, `ai-platform/test/e2e/stage-12-get-auth.test.ts`, `ai-platform/test/e2e/stage-12-quota-inspect-dashboard.test.ts`, `ai-platform/test/e2e/stage-12-support-lookup.test.ts`, `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts`, `ai-platform/test/e2e/phase-00-exemplars.test.ts`.

- [ ] T028 [US4] Remove the bearer binding from both vitest configs — produces configs with no `OPERATOR_BEARER_TOKEN`, FR-012, E2E-P3.10-08. Depends on T027. Files: `ai-platform/vitest.workers.config.ts`, `ai-platform/vitest.e2e.config.ts`. Remove `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID`. Keep `ISSUER_ID` and the Access bindings. Add `DURATION_SCALE` = `"staging"`.

- [ ] T029 [US4] Update remaining workers-pool tests that still read or write the dropped tables — produces setup through `coverClinic` and `plan_version`, FR-009, FR-012, E2E-P3.10-08. Depends on T028. Update a listed file only when it still `INSERT`s or `SELECT`s `entitlement`, `plan`, `invoice`, or `credit_price`. Setup goes through `coverClinic` and `plan_version`. Files: `ai-platform/test/entitlement.test.ts`, `ai-platform/test/admission-credit.test.ts`, `ai-platform/test/capability.test.ts`, `ai-platform/test/support-purge.test.ts`, `ai-platform/test/retention.test.ts`, `ai-platform/test/soft-threshold-routing.test.ts`, `ai-platform/test/conversational-journaling.test.ts`, `ai-platform/test/pipeline.test.ts`, `ai-platform/test/capability-deprecation.test.ts`, `ai-platform/test/cohort-activate-promote.test.ts`, `ai-platform/test/routing-policy-canary.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `ai-platform/test/discovery-http.test.ts`, `ai-platform/test/config-readers.test.ts`, `ai-platform/test/load/load-and-cost.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/plan-catalogue.test.ts`, `ai-platform/test/quota-inspect.test.ts`.

**Checkpoint**: Both vitest configs have no bearer token. Dropped tables are unread by the remaining workers-pool tests.

---

## 5. Verification

**Purpose**: The unit harness named in Test Layout passes, then the rewritten catalogues pass (E2E-P3.10-08). These commands are the harnesses for this unit. A repository-root `npm test` is not a task.

### 5.1 Unit harness

- [ ] T030 Run harness H-AP for this unit and confirm E2E-P3.10-01 through E2E-P3.10-07 pass together — produces the green unit file, FR-001 through FR-008, FR-010, FR-011, E2E-P3.10-01 through E2E-P3.10-07. Depends on T008 through T029 (and therefore on T001–T007). This task may edit only `ai-platform/test/system/control-plane-port.system.test.ts`. `packages/vendor-contracts/**` stays unchanged. `handleFeedCoverageRequest`, `handleCoverageReadRequest`, and `feedConsumerHealth` stay unchanged.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/control-plane-port.system.test.ts
```

### 5.2 Rewritten catalogues

- [ ] T031 [US4] Run the rewritten SYS and e2e catalogues and confirm no bearer remains — produces the green catalogues, FR-009, FR-012, E2E-P3.10-08. Depends on T030. Title check: `E2E-P3.10-08 rewritten SYS and e2e catalogues are green without a bearer`. `test/system` under `vitest.workers.config.ts` and `test/e2e` under `vitest.e2e.config.ts` pass. Neither config contains `OPERATOR_BEARER_TOKEN`. `operatorFetch` and `operatorFetchRaw` are absent from `ai-platform/test/system/harness.ts`. `ai-platform/src/support/index.ts`, the kept `ai-platform/src/control/*` modules, and the new methods are reached from the entry points in Test Layout.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system
cd ai-platform && npx vitest run --config vitest.e2e.config.ts test/e2e
```

**Checkpoint**: E2E-P3.10-01 through E2E-P3.10-08 pass. SC-002 is this catalogue run.

---

## 6. Documentation

**Purpose**: Written after T031 is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task.

### 6.1 Quickstart

- [ ] T032 Create `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, FR-001 through FR-012, E2E-P3.10-01 through E2E-P3.10-08. Depends on T031. Sections: (1) what was implemented — class-H methods on `VendorEntrypoint`, `/control/*` removed, bearer and `OPERATOR_ID` removed, transitional tables dropped, crons without `0 5 1 * *`, harness off `operatorFetch`; (2) files this unit adds or modifies — the Files section of `plan.md`; (3) harness command for this unit's tests only — the unit command below, then the two catalogue commands; (4) the entry point → module chain per E2E id below. `npm test` and other packages stay out of these commands (rule S8).

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/control-plane-port.system.test.ts
```

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system
cd ai-platform && npx vitest run --config vitest.e2e.config.ts test/e2e
```

| ID | Chain |
| --- | --- |
| E2E-P3.10-01 | `SELF.fetch` on `worker.ts` `fetch` for each former `isControlRoute` path → 404. Worker module loads with `OPERATOR_BEARER_TOKEN` absent from the vitest bindings. |
| E2E-P3.10-02 | `vendorCall("publishRoutingPolicy")` → `vendorCall("canaryRoutingPolicy")` → `vendorCall("promoteRoutingPolicy")` on `VendorEntrypoint` → `src/control/routing-policy.ts` → `POST /v1/requests` follows the promoted policy. |
| E2E-P3.10-03 | `vendorCall("armKillSwitch")` → `src/control/kill-switch.ts` → `writeEntrypointAudit` → `raiseAl19FromOutbox` → `POST /v1/requests` returns `capability_disabled`. |
| E2E-P3.10-04 | `vendorCall("deprecateCapability")` or `vendorCall("retireCapability")` → `src/control/capability-lifecycle.ts` → `GET /v1/capabilities`. |
| E2E-P3.10-05 | `vendorCall("beginTokenContractRotation")` → `src/control/token-contract.ts` → `token_contract` ver `2` current. |
| E2E-P3.10-06 | `vendorCall("supportLookup")` → `src/support/index.ts`, once by subscription ref and once by reference. |
| E2E-P3.10-07 | `ai-platform/wrangler.toml` `[triggers].crons` → `runScheduled("0 3 * * *")` → `runRetentionPurge`; `runScheduled("0 4 * * *")` → `runRollupAndReconciliation` keyed by `term_id`. |
| E2E-P3.10-08 | Rewritten `test/system/` and `test/e2e/` catalogues, `test/e2e/harness/control.ts`, `test/e2e/harness/env.ts`, `vitest.workers.config.ts`, `vitest.e2e.config.ts`. |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests**: T001 through T007, in Sequencing steps 1–7. No Setup phase. T001 starts immediately. T002 through T007 append to the same file.
- **Implementation**: T008 through T029, after those tests exist and fail. T008 through T014 are Sequencing steps 8–14. T015 through T017 are steps 15–17. T018 and T019 are Sequencing step 18. T020 is step 19. T021 is step 20. T022 through T029 are steps 21–28.
- **Verification**: T030 after T008 through T029. T031 after T030.
- **Documentation**: T032, after T031 is green.

### 7.2 User Story Dependencies

- **User Story 2 (P2)**: T001 is the first test. Implementation T015 through T020 removes `/control/*`, the bearer, and the transitional tables after the class-H methods exist. E2E-P3.10-01 is confirmed at T030.
- **User Story 1 (P1)**: T002 through T006 follow T001 because they share `ai-platform/test/system/control-plane-port.system.test.ts`. T008 through T014 add the class-H methods those tests call. T008 also writes `ai-platform/test/system/harness.ts`, which T022 edits later.
- **User Story 3 (P3)**: T007 follows T006 (same test file). T021 edits `ai-platform/wrangler.toml` after the table readers in T020. E2E-P3.10-07 is confirmed at T030.
- **User Story 4 (P4)**: T022 through T029 follow T021. T022 edits `ai-platform/test/system/harness.ts` after T008. T024 and T025 both edit `ai-platform/vitest.workers.config.ts`, in that order. T028 edits both vitest configs after the suite rewrites. T031 is this story's catalogue run.

### 7.3 Parallel Opportunities

- T001–T007 are not separate launches. They all write `ai-platform/test/system/control-plane-port.system.test.ts`.
- T008–T014 share `ai-platform/src/vendor/entrypoint.ts`. They stay in id order.
- T015 and T017 share `ai-platform/src/worker.ts`. T016 follows T015 because it deletes modules that imported `http.ts`.
- T018 writes only `ai-platform/migrations/20261006170000_drop_invoicing.sql`. T019 writes only `ai-platform/migrations/20261006170100_drop_plan_entitlement.sql`. Both follow T017. They do not share a path. T020 waits until both have finished.
- T022 through T029 stay in id order. T024, T025, and T028 all write `ai-platform/vitest.workers.config.ts`.
- T030, T031, and T032 are single tasks. T032 waits until T031 is green.

---

## 8. Implementation Waves

### Wave 1

- T001 [US2] — subphase: `### 3.1 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2)` — paths: `ai-platform/test/system/control-plane-port.system.test.ts`

### Wave 2

- T002–T006 [US1] — subphase: `### 3.2 User Story 1 - Operate configuration and support lookup on VendorEntrypoint (Priority: P1)` — paths: `ai-platform/test/system/control-plane-port.system.test.ts`

### Wave 3

- T007 [US3] — subphase: `### 3.3 User Story 3 - Run retention and rollup without the monthly period close (Priority: P3)` — paths: `ai-platform/test/system/control-plane-port.system.test.ts`

### Wave 4

- T008–T012 [US1] — subphase: `### 4.1 User Story 1 - Operate configuration and support lookup on VendorEntrypoint (Priority: P1) (part 1)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/test/system/harness.ts`, `ai-platform/src/control/routing-policy.ts`, `ai-platform/src/control/kill-switch.ts`, `ai-platform/src/control/audit.ts`, `ai-platform/src/control/capability-lifecycle.ts`, `ai-platform/src/control/token-contract.ts`

### Wave 5

- T013–T014 [US1] — subphase: `### 4.2 User Story 1 - Operate configuration and support lookup on VendorEntrypoint (Priority: P1) (part 2)` — paths: `ai-platform/src/vendor/entrypoint.ts`, `ai-platform/src/support/index.ts`, `ai-platform/src/control/cohort.ts`

### Wave 6

- T015–T017 [US2] — subphase: `### 4.3 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2) (part 1)` — paths: `ai-platform/src/worker.ts`, `ai-platform/src/control/index.ts`, `ai-platform/src/control/auth.ts`, `ai-platform/src/control/http.ts`, `ai-platform/src/control/entitle.ts`, `ai-platform/src/control/credit-price.ts`, `ai-platform/src/control/audit.ts`, `ai-platform/src/period-close/index.ts`, `ai-platform/src/control/lifecycle.ts`, `ai-platform/src/control/plan.ts`, `ai-platform/src/control/quota-inspect.ts`, `ai-platform/src/control/support-purge.ts`, `ai-platform/src/control/types.ts`

### Wave 7

- T018 [US2] — subphase: `### 4.4 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2) — drop invoicing` — paths: `ai-platform/migrations/20261006170000_drop_invoicing.sql`
- T019 [US2] — subphase: `### 4.5 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2) — drop plan and entitlement` — paths: `ai-platform/migrations/20261006170100_drop_plan_entitlement.sql`

### Wave 8

- T020 [US2] — subphase: `### 4.6 User Story 2 - Remove /control/* and boot without the bearer (Priority: P2) — readers` — paths: `ai-platform/src/config-cache/index.ts`, `ai-platform/src/admission/index.ts`

### Wave 9

- T021 [US3] — subphase: `### 4.7 User Story 3 - Run retention and rollup without the monthly period close (Priority: P3)` — paths: `ai-platform/wrangler.toml`

### Wave 10

- T022–T026 [US4] — subphase: `### 4.8 User Story 4 - Finish the harness migration off the bearer (Priority: P4) (part 1)` — paths: `ai-platform/test/system/harness.ts`, `ai-platform/test/e2e/harness/control.ts`, `ai-platform/test/e2e/harness/env.ts`, `ai-platform/test/period-close.test.ts`, `ai-platform/test/price-list-activation.test.ts`, `ai-platform/test/entitle-grant.test.ts`, `ai-platform/test/e2e/stage-03-enroll-validation.test.ts`, `ai-platform/test/e2e/stage-03-lifecycle-rotate.test.ts`, `ai-platform/test/e2e/stage-04-entitle-auth-period.test.ts`, `ai-platform/test/e2e/stage-04-entitle-quota-grants-validation.test.ts`, `ai-platform/vitest.workers.config.ts`, `ai-platform/test/control.test.ts`, `ai-platform/test/vendor-entrypoint.test.ts`, `ai-platform/test/system/golden-journey.system.test.ts`, `ai-platform/test/system/settlement-integrity.system.test.ts`, `ai-platform/test/system/entitlement-grant-interplay.system.test.ts`, `ai-platform/test/system/token-contract-rotation.system.test.ts`, `ai-platform/test/system/issuer-tokens.system.test.ts`, `ai-platform/test/system/capability-lifecycle.system.test.ts`, `ai-platform/test/system/lifecycle-interplay.system.test.ts`, `ai-platform/test/system/cron-retention-interplay.system.test.ts`, `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts`, `ai-platform/test/system/routing-policy-traffic.system.test.ts`

### Wave 11

- T027–T029 [US4] — subphase: `### 4.9 User Story 4 - Finish the harness migration off the bearer (Priority: P4) (part 2)` — paths: `ai-platform/test/e2e/stage-00-auth-schema-cron-happy.test.ts`, `ai-platform/test/e2e/stage-00-boot-bindings-routing.test.ts`, `ai-platform/test/e2e/stage-01-auth-validation.test.ts`, `ai-platform/test/e2e/stage-01-rotation-retire.test.ts`, `ai-platform/test/e2e/stage-03-auth-routing.test.ts`, `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts`, `ai-platform/test/e2e/stage-04-cohort-promote-deprecate.test.ts`, `ai-platform/test/e2e/stage-04-deprecate-retire-auth.test.ts`, `ai-platform/test/e2e/stage-04-entitle-happy-cohort-activate.test.ts`, `ai-platform/test/e2e/stage-05-canary-promote.test.ts`, `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts`, `ai-platform/test/e2e/stage-05-publish.test.ts`, `ai-platform/test/e2e/stage-05-rollback-serving.test.ts`, `ai-platform/test/e2e/stage-07-entitlement-filters.test.ts`, `ai-platform/test/e2e/stage-07-etag-cache.test.ts`, `ai-platform/test/e2e/stage-08-trace-auth.test.ts`, `ai-platform/test/e2e/stage-09-capability-context-preflight.test.ts`, `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts`, `ai-platform/test/e2e/stage-12-get-auth.test.ts`, `ai-platform/test/e2e/stage-12-quota-inspect-dashboard.test.ts`, `ai-platform/test/e2e/stage-12-support-lookup.test.ts`, `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts`, `ai-platform/test/e2e/phase-00-exemplars.test.ts`, `ai-platform/vitest.workers.config.ts`, `ai-platform/vitest.e2e.config.ts`, `ai-platform/test/entitlement.test.ts`, `ai-platform/test/admission-credit.test.ts`, `ai-platform/test/capability.test.ts`, `ai-platform/test/support-purge.test.ts`, `ai-platform/test/retention.test.ts`, `ai-platform/test/soft-threshold-routing.test.ts`, `ai-platform/test/conversational-journaling.test.ts`, `ai-platform/test/pipeline.test.ts`, `ai-platform/test/capability-deprecation.test.ts`, `ai-platform/test/cohort-activate-promote.test.ts`, `ai-platform/test/routing-policy-canary.test.ts`, `ai-platform/test/token-contract-control.test.ts`, `ai-platform/test/discovery-http.test.ts`, `ai-platform/test/config-readers.test.ts`, `ai-platform/test/load/load-and-cost.test.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/test/plan-catalogue.test.ts`, `ai-platform/test/quota-inspect.test.ts`

### Wave 12

- T030 — subphase: `### 5.1 Unit harness` — paths: `ai-platform/test/system/control-plane-port.system.test.ts`

### Wave 13

- T031 [US4] — subphase: `### 5.2 Rewritten catalogues` — paths: `ai-platform/test/system/`, `ai-platform/test/e2e/`, `ai-platform/vitest.workers.config.ts`, `ai-platform/vitest.e2e.config.ts`, `ai-platform/test/system/harness.ts`

### Wave 14

- T032 — subphase: `### 6.1 Quickstart` — paths: `specs/074-abo-p3-10-control-plane-port-vendor-entrypoint-removal/quickstart.md`
