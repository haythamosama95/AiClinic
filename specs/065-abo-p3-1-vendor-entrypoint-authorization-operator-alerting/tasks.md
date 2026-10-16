# Tasks: `VendorEntrypoint`, authorization classes, operator credentials and platform alerting

**Input**: Design documents from `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/` (`AVAILABLE_DOCS`: `research.md`, `data-model.md`, `contracts/`). `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id in the spec Test plan, written to fail before `VendorEntrypoint` exists. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the worker already exists. Sequencing step 1 adds the H-AP self binding and harness helpers inside the first failing test. No Foundational phase (prerequisites are P2.2, already merged, listed in Consumes Binding). No Polish phase. Task ids follow plan Sequencing, so `T001` is step 1. Sections group by user story, so ids are not in numeric order in the file.

**Task count**: 34. Size L is 32–40 (rule S3). The count is the plan's implied count: ten E2E tasks (Sequencing steps 1–10), twenty-two implementation steps (11–32), one verification task (step 33, including the earlier platform suites), and `quickstart.md` (step 34). It is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **AI Platform**: `ai-platform/` — migrations, `src/vendor/entrypoint.ts`, `src/alert/`, `src/clock.ts`, `src/control/audit.ts`, `src/worker.ts`, `wrangler.toml`, `vitest.workers.config.ts`, H-AP tests, and `test/worker-entry.test.ts` (T033 S2 mock export only)
- **ABO**: `abo/` — this unit does not change it
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified (rule S7)
- **Full-stack harness**: `e2e/fullstack/` — this unit does not change it
- **Spec Kit artifacts**: `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/`
- This unit's Files section names the `ai-platform` paths above and `quickstart.md`. `research.md`, `data-model.md`, and `contracts/` stay plan-phase artifacts. `src/control/index.ts`, `src/vendor/contract-version.ts`, `src/logger.ts`, and `packages/vendor-contracts/**` stay as they are. Enrollment, `/control/entitle`, and `/control/*` stay (rule S9).

---

## 3. Tests

**Purpose**: One failing test per E2E id, under H-AP, in Sequencing order. Every test is added to `ai-platform/test/system/vendor-entrypoint.system.test.ts`. The unit command is that file only. `T001` also adds the self binding and the harness helpers from Sequencing step 1.

### 3.1 User Story 1 - Entrypoint version gate and Access JWT refusal (Priority: P1)

**Independent Test**: E2E-P3.1-05 and E2E-P3.1-06 in harness H-AP.

- [X] T005 [US1] Add the failing test `E2E-P3.1-05 revokeOperatorCredential with a missing, expired, or wrong-aud Access JWT is unauthenticated and writes nothing` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-001, FR-004, FR-005, FR-016, and FR-024, proved by E2E-P3.1-05. Depends on T004 (same file, and `vendorCall` from T001). Three `vendorCall("revokeOperatorCredential", …)` calls: missing Access JWT, expired Access JWT, and wrong `aud`. Each result is `rejected`, code `unauthenticated`, `receipt` omitted. Counts of `operator_credential`, `assertion_used`, and `control_audit` are unchanged. The unit command fails because `VendorEntrypoint` is not exported.

- [X] T006 [US1] Add the failing test `E2E-P3.1-06 A method with contract_version missing or 2 is rejected contract_version_unsupported and writes nothing` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-002 and FR-017, proved by E2E-P3.1-06. Depends on T005 (same file). Each of `registerOperatorCredential`, `revokeOperatorCredential`, and `listOperatorCredentials`, once with `contract_version` omitted and once with `2`. Result `rejected`, code `contract_version_unsupported`, and no D1 change. The refusal is asserted by a missing or wrong-`aud` JWT still producing `contract_version_unsupported`. The unit command fails because `VendorEntrypoint` is not exported.

**Checkpoint**: E2E-P3.1-05 and E2E-P3.1-06 exist and fail.

### 3.2 User Story 2 - Operator credentials and class HP (Priority: P2)

**Independent Test**: E2E-P3.1-01, E2E-P3.1-02, E2E-P3.1-03, E2E-P3.1-04, E2E-P3.1-07, and E2E-P3.1-10 in harness H-AP.

Tasks below are in Sequencing order. T005 and T006 are written between T004 and T007. T008 and T009 are written between T007 and T010. Section 7 has the global order.

#### 3.2.1 User Story 2 - Operator credentials and class HP (part 1)

- [X] T001 [US2] Add the `VENDOR` self binding and the `TEST_CLOCK` binding in `ai-platform/vitest.workers.config.ts`. `serviceBindings.VENDOR` is `{ name: kCurrentWorker, entrypoint: "VendorEntrypoint" }` from Miniflare, and `TEST_CLOCK` is `"1"`. Production wrangler has no self-binding. Add `vendorCall(method, args, {accessJwt, assertion})`, the Access team fixture from `createAccessTeam`, and email capture in `ai-platform/test/system/harness.ts`, next to the existing `operatorFetch`. Add the failing test `E2E-P3.1-01 Empty registry: bootstrap registration without approval returns pending and AL-13 bootstrap; a second unapproved registration is rejected` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test and the H-AP helpers, satisfies FR-006, FR-009, FR-013, FR-014, FR-019, FR-022, and FR-025, proved by E2E-P3.1-01. `vendorCall("registerOperatorCredential", args, { accessJwt })` with no assertion. `result` `ok`, `code` `""`, `receipt` omitted, `detail` JSON of the row with `status` `pending`. Captured `send_email` text is the AL-13 bootstrap body and carries codes and ids, plus the decoded operation. A second call with a valid Access JWT and no assertion is `rejected` with code `assertion_required`, and no second row is inserted. Run:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/vendor-entrypoint.system.test.ts
```

The run fails because `VendorEntrypoint` is not exported. Do not modify `packages/vendor-contracts`.

- [X] T002 [US2] Add `setTestClock` in `ai-platform/test/system/harness.ts` and the failing test `E2E-P3.1-02 HP call using a credential under 24 hours is rejected; after the test clock passes 24 hours it is ok` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-011 and FR-014, proved by E2E-P3.1-02. Depends on T001 (same test file and harness). Bootstrap a credential, then `revokeOperatorCredential` signed by that credential. Before `activates_at`, `rejected` with code `credential_not_active` and the row stays `pending`. `setTestClock` moves now to `activates_at`. The same call is `ok`, `code` `""`, `receipt` omitted, and `detail` is that row. No `sleep` over 2 s. The test imports `ai-platform/wrangler.toml` as text and asserts the `[env.production]` and `[env.staging]` blocks contain no `TEST_CLOCK`. The unit command fails on the missing entrypoint. T015 replaces `setTestClock` with the D1 clock row.

- [X] T003 [US2] Add the failing test `E2E-P3.1-03 HP with a valid Access JWT and an assertion over the exact operation is ok; replaying the assertion is rejected` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-003, FR-004, FR-010, FR-011, FR-012, and FR-017, proved by E2E-P3.1-03. Depends on T002 (same file). After the credential is active, `revokeOperatorCredential` is `ok`, `detail` is that row's JSON, `code` `""`, `receipt` omitted, and `contract_version` is the negotiated version. `control_audit.actor` is the Access email and `assertion_sha256` is the hex SHA-256 of the canonical operation. The same assertion again is `rejected` with code `assertion_used`. The unit command fails on the missing entrypoint.

- [X] T004 [US2] Add the failing test `E2E-P3.1-04 Assertion issued_at 6 minutes old is rejected; actor_email other than the Access email is rejected` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-011 and FR-015, proved by E2E-P3.1-04. Depends on T003 (same file). One call with `issued_at` six minutes before the test clock is `rejected` with code `assertion_expired`. Another call whose operation `actor_email` differs from the Access JWT email is `rejected` with code `actor_email_mismatch`. The unit command fails on the missing entrypoint.

- [X] T007 [US2] Add the failing test `E2E-P3.1-07 Credential A revokes B, then an HP call that uses B fails, and AL-13 is sent` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-007, FR-012, FR-018, and FR-022, proved by E2E-P3.1-07. Depends on T006 (same file). A is bootstrapped and aged to active, B is registered with A's assertion and aged to active, then A revokes B. The revoke is `ok`, `detail` is B's row with `status` `revoked`, `control_audit.actor` is the Access email, and `assertion_sha256` is stored. The captured body is AL-13 kind `revoke`. A later HP call whose `signer_credential_id` is B is `rejected` with code `credential_revoked`. The unit command fails on the missing entrypoint.

**Checkpoint**: E2E-P3.1-01, E2E-P3.1-02, E2E-P3.1-03, E2E-P3.1-04, and E2E-P3.1-07 exist and fail.

#### 3.2.2 User Story 2 - Operator credentials and class HP (part 2)

- [X] T010 [US2] Add the failing test `E2E-P3.1-10 listOperatorCredentials returns ok with the active keys in detail` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-001, FR-008, and FR-017, proved by E2E-P3.1-10. Depends on T009 (same file). With one `pending` row and one `active` row, `listOperatorCredentials` is `ok`, `code` `""`, `receipt` omitted, `contract_version` present, and `detail` is the JSON text of `[{credential_id, public_key_cose, alg}]` for the active row only. The unit command fails on the missing entrypoint.

**Checkpoint**: E2E-P3.1-10 exists and fails. User Story 2's six tests are red.

### 3.3 User Story 3 - Platform alerting and the five-minute cron (Priority: P3)

**Independent Test**: E2E-P3.1-08 and E2E-P3.1-09 in harness H-AP. Every earlier suite stays green (rule S2).

- [X] T008 [US3] Add the harness switch that makes `sendPlatformEmail` throw in `ai-platform/test/system/harness.ts`, and the failing test `E2E-P3.1-08 When send_email throws the alert stays unsent and the next five-minute run sends it once` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-019, FR-020, and FR-025, proved by E2E-P3.1-08. Depends on T007 (same test file). The harness makes `sendPlatformEmail` throw. A bootstrap still stores `platform_alert` with `send_state` `unsent`. The next `runScheduled("*/5 * * * *")` sends that body once. The captured text has the code, the credential id, and the decoded operation. A second `*/5` run does not send it again. The unit command fails on the missing entrypoint.

- [X] T009 [US3] Add heartbeat fetch capture around `runScheduled` in `ai-platform/test/system/harness.ts`, and the failing test `E2E-P3.1-09 The five-minute cron pings the heartbeat URL and a failing job raises a platform alert` in `ai-platform/test/system/vendor-entrypoint.system.test.ts` — produces the red test, satisfies FR-021, FR-023, and FR-025, proved by E2E-P3.1-09. Depends on T008 (same test file and harness). One `runScheduled("*/5 * * * *")` records an outbound fetch to `HEARTBEAT_URL`. A later run whose heartbeat `fetch` throws writes one JSON `console.log` line and inserts `platform_alert` with code `scheduled_job_failed`. The unit command fails because the `*/5` branch does not ping or alert.

**Checkpoint**: E2E-P3.1-08 and E2E-P3.1-09 exist and fail.

---

## 4. Implementation

**Purpose**: Sequencing steps 11–32. Each step starts after T001–T010 exist and fail. Within a story the tasks are in Sequencing order. Section 7 lists the global order, including tasks that sit under another story's heading.

### 4.1 User Story 1 - Entrypoint version gate and Access JWT refusal (Priority: P1)

**Independent Test**: E2E-P3.1-05 and E2E-P3.1-06 in harness H-AP.

- [X] T016 [US1] Add `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `WEBAUTHN_RP_ID`, `WEBAUTHN_ORIGIN`, `HEARTBEAT_URL`, and `ALERT_EMAIL_TO` under `[env.development.vars]`, `[env.staging.vars]`, and `[env.production.vars]` in `ai-platform/wrangler.toml` — produces those vars, satisfies FR-014, FR-021, and FR-024, proved by E2E-P3.1-02, E2E-P3.1-05, and E2E-P3.1-09. Depends on T015. `ALERT_EMAIL_TO` is the same address as the `send_email` destination. No `TEST_CLOCK` in any wrangler env, which keeps the E2E-P3.1-02 wrangler assertion true. E2E-P3.1-02 still fails on the missing entrypoint.

- [X] T020 [US1] Add `ai-platform/src/vendor/entrypoint.ts` and re-export `VendorEntrypoint` from `ai-platform/src/worker.ts` — produces the named `WorkerEntrypoint` and the version gate, satisfies FR-001, FR-002, FR-003, FR-004, FR-005, and FR-017, proved by E2E-P3.1-06. Depends on T016, T017, T018, and T019. The class table is a const in `entrypoint.ts`: `registerOperatorCredential` is HP, `revokeOperatorCredential` is HP, and `listOperatorCredentials` is M. This unit implements no class H method. `listOperatorCredentials` takes `contract_version` only. The HP methods take `access_jwt`, and the assertion argument the later HP tasks read. The first lines of every method call `negotiate(CHANNEL_VERSIONS.vendorEntrypoint, requested)`. A missing version or `2` returns `rejected` / `contract_version_unsupported` with `contract_version` `1`, empty `detail`, no `receipt`, and no D1 write. E2E-P3.1-06 passes. `src/vendor/contract-version.ts` and `src/control/index.ts` stay as they are. Production `src/worker.ts` does not import the testkit.

- [X] T021 [US1] Load Access certs from `https://${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs` in `ai-platform/src/vendor/entrypoint.ts`, map them into `AccessCertsDocument` with issuer `https://${ACCESS_TEAM_DOMAIN}`, and call `verifyAccessJwt` — produces the class HP Access JWT check, satisfies FR-004, FR-005, and FR-016, proved by E2E-P3.1-05. Depends on T020 (same file). A missing token, `{ ok: false }`, or a certs fetch failure returns `unauthenticated` and writes nothing, including no `control_audit` row. The H-AP fixture from T001 answers that URL from `createAccessTeam`. The version gate from T020 still runs before this check. E2E-P3.1-05 passes. E2E-P3.1-06 stays green.

**Checkpoint**: E2E-P3.1-06 passes at T020. E2E-P3.1-05 passes at T021.

### 4.2 User Story 2 - Operator credentials and class HP (Priority: P2)

**Independent Test**: E2E-P3.1-01, E2E-P3.1-02, E2E-P3.1-03, E2E-P3.1-04, E2E-P3.1-07, and E2E-P3.1-10 in harness H-AP.

#### 4.2.1 User Story 2 - Operator credentials and class HP (part 1)

- [X] T011 [US2] Add `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` with `operator_credential`, `assertion_used`, and `platform_alert`, plus nullable `control_audit.actor` and `control_audit.assertion_sha256` — produces the D1 tables and columns, satisfies FR-009, FR-010, FR-012, and FR-019, proved by E2E-P3.1-01, E2E-P3.1-03, E2E-P3.1-05, and E2E-P3.1-08. Depends on T010. `operator_credential` has `credential_id`, `operator_email`, `public_key_cose`, `alg`, `status` (`pending`, `active`, `revoked`), `activates_at`, `approved_by`, and `revoked_by`. `assertion_used` has `challenge_sha256`, `credential_id`, and `used_at`. `platform_alert` has the same shape as the ABO's `alert`, as `contracts/platform-alert.md` already records. `operator_id` stays. Existing inserts name their columns and keep writing `operator_id`. The ten E2E tests still fail.

- [X] T012 [P] [US2] Replace `ai-platform/schema.snap.sql` with the post-migration `CREATE TABLE` dump — produces the snapshot that matches the migration, satisfies FR-009, FR-010, FR-012, and FR-019, proved by E2E-P3.1-01 and E2E-P3.1-05. Depends on T011. The existing `T-A5-13 schema_snapshot_matches` test stays green when T033 runs. This task does not edit the migration file.

- [X] T013 [P] [US2] Make `ai-platform/test/system/harness.ts` apply `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` and delete the new tables in its reset — produces a clean registry for each test, satisfies FR-009 and FR-025, proved by E2E-P3.1-01 through E2E-P3.1-10. Depends on T011. The ten E2E tests still fail. This task does not edit `schema.snap.sql` or `src/clock.ts`.

- [X] T014 [P] [US2] Add `ai-platform/src/clock.ts` — produces the one clock module, satisfies FR-014, proved by E2E-P3.1-02. Depends on T010. When `env.TEST_CLOCK` is absent it returns `Date.now()`. When it is `"1"` it reads the harness clock row. E2E-P3.1-02 still fails on the missing entrypoint. This task does not edit wrangler, the harness, or the migration.

- [X] T015 [US2] Implement `setTestClock` as a D1 row the harness creates in `ai-platform/test/system/harness.ts` — produces the test clock advance, satisfies FR-014, proved by E2E-P3.1-02. Depends on T013 and T014. `src/clock.ts` reads that row when `TEST_CLOCK` is `"1"`. E2E-P3.1-02 still fails on the missing entrypoint. No local scenario sleeps more than 2 s.

**Checkpoint**: E2E-P3.1-01 through E2E-P3.1-10 are still red. E2E-P3.1-02 still fails on the missing entrypoint.

#### 4.2.2 User Story 2 - Operator credentials and class HP (part 2)

- [X] T017 [US2] Add a `send_email` binding named `SEND_EMAIL` with `destination_address` `alerts@clinic.invalid` on development, staging, and production in `ai-platform/wrangler.toml` — produces the fixed email binding, satisfies FR-019, FR-024, and FR-025, proved by E2E-P3.1-01 and E2E-P3.1-08. Depends on T016 (same file). The address is the local stand-in for the verified destination. `ALERT_EMAIL_TO` from T016 is that same address. Deploy replaces the binding and `ALERT_EMAIL_TO` together.

- [X] T019 [P] [US2] Add `writeEntrypointAudit` in `ai-platform/src/control/audit.ts` — produces the entrypoint audit insert, satisfies FR-012, proved by E2E-P3.1-03 and E2E-P3.1-07. Depends on T011. It inserts `actor`, `assertion_sha256`, and `operator_id` set to that same Access email. The existing `writeAudit` function stays. May run in parallel with T016, T017, and T018. Finishes before T020.

- [X] T022 [US2] Implement bootstrap `registerOperatorCredential` in `ai-platform/src/vendor/entrypoint.ts` — produces empty-registry registration, satisfies FR-006, FR-009, and FR-013, proved by E2E-P3.1-01. Depends on T021 (same file). Empty table, no assertion, Access JWT still required. Insert `pending` with `activates_at` 24 hours ahead, `approved_by` null, and `operator_email` the Access email. `detail` is the row JSON. A second call without an assertion is `assertion_required`. E2E-P3.1-01 stays red until T023 sends AL-13.

- [X] T023 [US2] Add `ai-platform/src/alert/email.ts` and the AL-13 bootstrap insert in `ai-platform/src/alert/index.ts`, and call it from bootstrap in `ai-platform/src/vendor/entrypoint.ts` — produces the bootstrap alert and the only `env.SEND_EMAIL.send` call, satisfies FR-013, FR-019, FR-022, and FR-025, proved by E2E-P3.1-01. Depends on T017 and T022. `email.ts` is the only call to `env.SEND_EMAIL.send`. The email `text` is the bootstrap body in `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/contracts/alert-body.md`. E2E-P3.1-01 passes.

- [X] T024 [US2] Implement the HP assertion path for register and revoke in `ai-platform/src/vendor/entrypoint.ts` — produces assertion checks for both HP methods, satisfies FR-011 and FR-015, proved by E2E-P3.1-04. Depends on T023 (same file). Read `signer_credential_id`, call `verifyAssertion` with `WEBAUTHN_RP_ID` and `WEBAUTHN_ORIGIN`, compare `actor_email` with the Access email, and require `issued_at` within five minutes of `ai-platform/src/clock.ts`. E2E-P3.1-04 is observed failing on `credential_not_active` until T025. That failure is the clock gate.

**Checkpoint**: E2E-P3.1-01 passes at T023. E2E-P3.1-04 is observed failing on `credential_not_active`.

#### 4.2.3 User Story 2 - Operator credentials and class HP (part 3)

- [X] T025 [US2] On the signer read, and inside `listOperatorCredentials`, in `ai-platform/src/vendor/entrypoint.ts`, set `pending` to `active` when `activates_at` is at or before now — produces the 24-hour activation, satisfies FR-011 and FR-014, proved by E2E-P3.1-02 and E2E-P3.1-04. Depends on T024 (same file). The promotion raises no alert. A signer still `pending` is `credential_not_active` and does not insert `assertion_used`. E2E-P3.1-02 passes, and E2E-P3.1-04 passes.

- [X] T026 [US2] After the signer is active and the assertion checks pass, insert `assertion_used.challenge_sha256` and write `control_audit` from `ai-platform/src/vendor/entrypoint.ts` through `writeEntrypointAudit` — produces single-use assertions and the audit row, satisfies FR-010 and FR-012, proved by E2E-P3.1-03. Depends on T019 and T025. A duplicate is `assertion_used` and does not change the credential. Write `control_audit` for every H/HP call that passed the Access JWT check, including the rejected ones in E2E-P3.1-04. A missing, expired, or wrong-`aud` Access JWT still writes nothing. E2E-P3.1-03 passes.

- [X] T027 [US2] Finish `revokeOperatorCredential` and the register idempotency cases in `ai-platform/src/vendor/entrypoint.ts`, and raise AL-13 kind `revoke` through `ai-platform/src/alert/index.ts` — produces revoke, rotation failure, and the revoke alert, satisfies FR-006, FR-007, FR-018, and FR-022, proved by E2E-P3.1-07. Depends on T026 (same entrypoint file). `revokeOperatorCredential` sets `status` `revoked` and `revoked_by` to the Access email, returns `ok` when the row is already `revoked`, and raises AL-13 kind `revoke`. A missing target is `rejected` / `credential_not_found` with no `assertion_used` insert. An HP call whose signer is `revoked` is `credential_revoked`. An HP register raises AL-13 for register (FR-022). Same `credential_id` and same `public_key_cose` on register returns the existing row and does not insert another; a different key is `conflict` / `public_key_cose_mismatch` with empty `detail`. E2E-P3.1-07 passes.

- [X] T028 [US2] Implement `listOperatorCredentials` in `ai-platform/src/vendor/entrypoint.ts` — produces the active-key read, satisfies FR-008 and FR-017, proved by E2E-P3.1-10. Depends on T025 and T027 (same file). The result is `ok` and the active `{credential_id, public_key_cose, alg}` array in `detail`, after the promotion in T025. `code` is empty, `receipt` is omitted, and `contract_version` is present. E2E-P3.1-10 passes.

**Checkpoint**: E2E-P3.1-02 and E2E-P3.1-04 pass at T025. E2E-P3.1-03 passes at T026. E2E-P3.1-07 passes at T027. E2E-P3.1-10 passes at T028.

### 4.3 User Story 3 - Platform alerting and the five-minute cron (Priority: P3)

**Independent Test**: E2E-P3.1-08 and E2E-P3.1-09 in harness H-AP. Every earlier suite stays green (rule S2).

- [X] T018 [US3] Set top-level `workers_dev = false`, `preview_urls = false`, and `[observability] enabled = true` in `ai-platform/wrangler.toml`. Append `*/5 * * * *` to the existing `[triggers]` cron list — produces the closed entrypoint, observability, and the five-minute trigger, satisfies FR-001, FR-021, and FR-023, proved by E2E-P3.1-08 and E2E-P3.1-09. Depends on T017 (same file). Leave `0 3 * * *`, `0 4 * * *`, and `0 5 1 * *` in place. The `scheduled` handler for that cron is T030.

- [X] T029 [US3] When `sendPlatformEmail` throws, leave `send_state` `unsent` in `ai-platform/src/alert/index.ts` and do not mark the `*/5` job failed — produces the unsent row, satisfies FR-020, proved by E2E-P3.1-08. Depends on T023 (same alert module). E2E-P3.1-08 stays red until T030 sends the row.

- [X] T030 [US3] Handle cron `*/5 * * * *` in `scheduled` in `ai-platform/src/worker.ts` by calling alert retry, then the heartbeat ping — produces the five-minute branch, satisfies FR-020 and FR-021, proved by E2E-P3.1-08. Depends on T018, T020, and T029. Existing `0 3`, `0 4`, and `0 5 1` branches stay. Retry sends each `unsent` row once and sets `sent`. E2E-P3.1-08 passes. The heartbeat `fetch` itself is T031.

- [X] T031 [US3] The heartbeat job fetches `HEARTBEAT_URL` from the `*/5` branch, via `ai-platform/src/alert/index.ts` called by `ai-platform/src/worker.ts` — produces the heartbeat ping, satisfies FR-021, proved by E2E-P3.1-09. Depends on T030. The harness from T009 records that fetch. The failing-job half of E2E-P3.1-09 stays red until T032.

- [X] T032 [US3] A thrown job in the `*/5` branch logs one JSON line through `console.log` and inserts `platform_alert` with code `scheduled_job_failed` — produces the scheduled-job alert, satisfies FR-021 and FR-023, proved by E2E-P3.1-09. Depends on T031. The log and the insert live on the `*/5` path in `ai-platform/src/worker.ts` and `ai-platform/src/alert/index.ts`. `ai-platform/src/logger.ts` stays on its current line format so earlier suites keep their log shape. E2E-P3.1-09 passes.

**Checkpoint**: E2E-P3.1-08 passes at T030. E2E-P3.1-09 passes at T032.

---

## 5. Verification

**Purpose**: This unit's H-AP file passes, then every earlier platform suite is still green on its current command (rule S2). Consumes Binding says this unit does not re-run or edit the P2.2 package suite (CP-A).

- [X] T033 Run harness H-AP for this unit and confirm E2E-P3.1-01 through E2E-P3.1-10 pass together, then confirm the earlier platform suites are still green — produces the green run, satisfies FR-001 through FR-025, SC-001, and SC-002, proved by E2E-P3.1-01 through E2E-P3.1-10. Depends on T012 and T032 (and therefore on T001–T031). Before the earlier-suite command, edit only the existing `vi.mock("cloudflare:workers")` in `ai-platform/test/worker-entry.test.ts`: add a `WorkerEntrypoint` class with the same `(ctx, env)` constructor as that file's `DurableObject` stub, and return `{ DurableObject, WorkerEntrypoint, env: runtimeEnv }`. Keep `export { VendorEntrypoint } from "./vendor/entrypoint"` in `ai-platform/src/worker.ts`. Consumes contracts and `packages/vendor-contracts/**` stay unchanged. This unit's harness:

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/vendor-entrypoint.system.test.ts
```

The earlier platform suites, on their current commands (rule S2). `npm test` runs manifest verification, the Node vitest run (including `T-A5-13 schema_snapshot_matches` in `ai-platform/test/migrations.test.ts`), and `vitest.workers.config.ts` (including P2.1's `ai-platform/test/system/contract-version.system.test.ts`). `npm run test:e2e` runs `vitest.e2e.config.ts`:

```bash
cd ai-platform && npm test && npm run test:e2e
```

Do not re-run `packages/vendor-contracts` (CP-A). A full-product `npm test` from the repository root is not this command.

---

## 6. Documentation

**Purpose**: Written after T033 is green (rule S8). The plan leaves `quickstart.md` for implement. `research.md`, `data-model.md`, and `contracts/` stay plan-phase artifacts. No other doc task: the plan does not leave those files for implement.

- [X] T034 Create `specs/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, satisfies FR-001 through FR-025, proved by E2E-P3.1-01 through E2E-P3.1-10. Depends on T033. Sections: (1) what was implemented — `VendorEntrypoint`, the three methods, the D1 tables, the `*/5` branch, and the H-AP helpers; (2) files this unit adds or modifies — the Files section of `plan.md`, with no earlier-unit files, no combined counts, and no full-suite regression (that is T033); (3) harness command for this unit's tests only — the command below; (4) how to inspect the change — read `ai-platform/src/vendor/entrypoint.ts`, the `VendorEntrypoint` re-export in `ai-platform/src/worker.ts`, the `*/5` cron and `[observability]` in `ai-platform/wrangler.toml`, and the H-AP output; (5) the entry point → module chain per E2E id below. Every scenario is asserted by H-AP, so this file records harness commands only.

```bash
cd ai-platform && npx vitest run --config vitest.workers.config.ts \
  test/system/vendor-entrypoint.system.test.ts
```

Earlier suites and `npm test` stay out of this command (rule S8).

| ID | Chain |
| --- | --- |
| E2E-P3.1-01 | `vendorCall` → `env.VENDOR.registerOperatorCredential` → `src/vendor/entrypoint.ts` bootstrap insert → `src/alert/index.ts` AL-13 → `src/alert/email.ts` `SEND_EMAIL.send` |
| E2E-P3.1-02 | `setTestClock` → `src/clock.ts` → `vendorCall` `revokeOperatorCredential` → signer credential read in `src/vendor/entrypoint.ts`. The test also reads `wrangler.toml` and asserts the production and staging envs have no `TEST_CLOCK` |
| E2E-P3.1-03 | `vendorCall` `revokeOperatorCredential` → `verifyAccessJwt` → `verifyAssertion` → `assertion_used` insert → `src/control/audit.ts` |
| E2E-P3.1-04 | `vendorCall` `revokeOperatorCredential` → `src/clock.ts` freshness and Access email comparison in `src/vendor/entrypoint.ts` |
| E2E-P3.1-05 | `vendorCall` `revokeOperatorCredential` with a bad Access JWT → `verifyAccessJwt` → `rejected` `unauthenticated` before any D1 write |
| E2E-P3.1-06 | `vendorCall` on each of the three methods → `negotiate` in `src/vendor/entrypoint.ts` before `verifyAccessJwt` |
| E2E-P3.1-07 | `vendorCall` `revokeOperatorCredential` (signer A, target B) → revoke update → `src/alert/email.ts` → a later `vendorCall` whose signer is B |
| E2E-P3.1-08 | `src/alert/email.ts` throws → `platform_alert` stays `unsent` → `runScheduled("*/5 * * * *")` → `src/worker.ts` `scheduled` → `src/alert/index.ts` retry → `src/alert/email.ts` |
| E2E-P3.1-09 | `runScheduled("*/5 * * * *")` → `src/worker.ts` → heartbeat `fetch` captured in the harness; a thrown heartbeat `fetch` → JSON `console.log` → `platform_alert` insert |
| E2E-P3.1-10 | `vendorCall` `listOperatorCredentials` → promote-due read → active-key JSON in `detail` |

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T010)**: No Setup phase. T001 starts immediately. It adds the `VENDOR` self binding, the `TEST_CLOCK` binding, `vendorCall`, the Access team fixture, and email capture, then adds E2E-P3.1-01. The other tests append in Sequencing order and are observed failing before T011: T001, T002, T003, T004, T005, T006, T007, T008, T009, T010.
- **Implementation (T011–T032)**: Starts after T001–T010 exist and fail. Default order is Sequencing. After T011, T012, T013, and T014 may run together. T015 waits on T013 and T014. T016, T017, and T018 follow in order on `wrangler.toml`. T019 may overlap T016–T018 and finishes before T020. T020 through T028 follow Sequencing on the entrypoint. T029 follows T028. T030, T031, and T032 follow in order.
- **Verification (T033)**: After every implementation task, including T012 and T032.
- **Documentation (T034)**: After T033 is green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: Tests T005 and T006 wait on T004 because they append to the file T001 created. They do not wait on User Story 2's implementation. T016 waits on T015. T020 waits on T016, T017, T018, and T019. T021 waits on T020. E2E-P3.1-06 passes at T020. E2E-P3.1-05 passes at T021. User Story 2's credential methods are calls on this entrypoint, so bootstrap (T022) waits on T021.
- **User Story 2 (P2)**: T001 starts immediately. T002, T003, T004, and T007 append in that order. T007 waits on T006. T010 waits on T009. Schema, clock, audit, bootstrap, and the HP path are T011–T015, T017, T019, and T022–T028. E2E-P3.1-01 passes at T023. E2E-P3.1-02 and E2E-P3.1-04 pass at T025. E2E-P3.1-03 passes at T026. E2E-P3.1-07 passes at T027. E2E-P3.1-10 passes at T028.
- **User Story 3 (P3)**: T008 waits on T007. T009 waits on T008. Those tests do not wait on User Story 2's modules. T018 waits on T017 and does not wait for an AL-13 row. T029 waits on T023, because the retry sends the alert User Story 2 stored. T030 waits on T018, T020, and T029. T031 waits on T030. T032 waits on T031. E2E-P3.1-08 passes at T030. E2E-P3.1-09 passes at T032. The earlier-suite half of this story's Independent Test line is T033, not T008 or T009.

### 7.3 Parallel Opportunities

- T001–T010 are not `[P]`. They all write `ai-platform/test/system/vendor-entrypoint.system.test.ts`. T001, T002, T008, and T009 also write `ai-platform/test/system/harness.ts`. T001 also writes `ai-platform/vitest.workers.config.ts`. A pair in another story is not parallel with these, because Sequencing appends every E2E to that one file.
- After T011, T012 (`ai-platform/schema.snap.sql`), T013 (`ai-platform/test/system/harness.ts`), and T014 (`ai-platform/src/clock.ts`) touch different files and may launch together. T015 waits on T013 and T014. T012 must finish before T033.
- T016, T017, and T018 share `ai-platform/wrangler.toml`. They are not `[P]` with each other.
- T019 writes `ai-platform/src/control/audit.ts`. It may launch with T016–T018 after T011. T020 waits until T019 has finished. T020 and T021 share `ai-platform/src/vendor/entrypoint.ts` and are not `[P]`.
- T022–T028 share `ai-platform/src/vendor/entrypoint.ts`. They are not `[P]` with each other. T023 also adds `ai-platform/src/alert/email.ts` and `ai-platform/src/alert/index.ts`.
- T029, T030, T031, and T032 stay in Sequencing order. T030 and T032 edit `ai-platform/src/worker.ts`, which T020 already re-exports from.
- T033 and T034 are single tasks. T034 waits until T033 is green.

```bash
# Two User Story 2 tasks launched together after T011.
# Different files. Neither waits on the other.
Task: "T012 [P] [US2] Replace ai-platform/schema.snap.sql with the post-migration CREATE TABLE dump"
Task: "T014 [P] [US2] Add ai-platform/src/clock.ts, the one clock module"
```
