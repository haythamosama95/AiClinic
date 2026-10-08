# Tasks: Contract version matrix

**Input**: Design documents from `specs/095-abo-p7-3-contract-version-matrix/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P6.4 none; P4.11 none. Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is omitted (Spikes: None). `data-model.md` is omitted (no entities). `contracts/` is omitted (Freezes: None). `quickstart.md` is written in Documentation after the tests and variants are on disk.

**Organization**: P7.3 is User Story 1 and User Story 2 (`[US1]`, `[US2]`), size M (rule S3). Branch `ai/095-abo-p7-3-contract-version-matrix`. E2E ids stay `E2E-P7.3-01` through `E2E-P7.3-07`. Tests are one task per Test plan id plus each extra test file **Test Layout** names, written before the variant that file imports or starts. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase. No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 29. Size M is 20–32 (rule S3). Plan **Files** is 28 paths, including `quickstart.md`. Those 28 are tasks. The verification task edits nothing and is the harness check the tasks phase requires. The count is not padded. `npm test` in `e2e/fullstack` is not a task. Worker-booting harness commands are not executed: the stack is not running and this workflow does not start wrangler.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Harness H-FS**: `e2e/fullstack/test/`. Shared boot module `e2e/fullstack/test/p7-3-stack.mjs`. Variant modules and wrangler configs under `e2e/fullstack/test/variant/`
- **Per-codebase variants**: `abo/test/version-matrix/`, `ai-platform/test/version-matrix/`, `backend/tests/contract_version_matrix.sql`, `frontend/test/integration/contract_version_matrix_fullstack_test.dart`
- **Harness commands** (recorded for `quickstart.md`; this workflow does not run the ones that boot a worker):
  - H-FS, from `e2e/fullstack/`: `node --import tsx --test test/p7-3-01.test.mjs test/p7-3-02.test.mjs test/p7-3-03.test.mjs test/p7-3-04.test.mjs test/p7-3-05.test.mjs test/p7-3-07.test.mjs`
  - ABO variant, in `abo/`: `npx vitest run --config vitest.version-matrix.config.ts`
  - Platform variants, in `ai-platform/`: `npx vitest run --config vitest.version-matrix.config.ts` and `npx vitest run --config vitest.version-matrix-do.config.ts`
  - E2E-P7.3-06: `node --import tsx e2e/fullstack/test/p7-3-06-prepare.mjs`, then in `frontend/`: `flutter test --tags fullstack test/integration/contract_version_matrix_fullstack_test.dart`
  - Backend SQL (does not boot a worker; not run in this workflow): `psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/contract_version_matrix.sql`
- **Unchanged by this unit**: `packages/vendor-contracts/`, `abo/src/`, `ai-platform/src/`, `frontend/lib/`, `backend/supabase/migrations/`, `abo/vitest.workers.config.ts`, `ai-platform/vitest.workers.config.ts`, `backend/tests/run_all_backend_tests.sh`, `e2e/fullstack/package.json`
- **Spec Kit artifacts**: `specs/095-abo-p7-3-contract-version-matrix/`

---

## 3. Tests

**Purpose**: Sequencing step 1. One failing test per E2E id, plus each extra file **Test Layout** names. Each test is written so it fails before the variant config or SQL gate it calls is in place. This workflow does not execute it. Do not boot wrangler. Do not start the H-FS stack. Do not run `npm test` in `e2e/fullstack`.

Published current is `1`. A receiver whose current version is published N+1 (`2`) accepts `1` and `2` and answers in the version the request used. Unsupported on that window is missing, `0`, or `3`.

### 3.1 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — tests (part 1)

**Independent Test**: E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07.

- [X] T001 [US1] Add the failing test `E2E-P7.3-01` in `e2e/fullstack/test/p7-3-01.test.mjs` — red test, FR-001, E2E-P7.3-01. Depends on nothing. Title `E2E-P7.3-01`. Import `e2e/fullstack/test/p7-3-stack.mjs` and start the ABO on `e2e/fullstack/test/variant/abo-n-plus-1.toml` and the platform on `e2e/fullstack/test/variant/platform-n-plus-1.toml`. Cover the channels that import `CHANNEL_VERSIONS`: ABO `handleBillingV1` → `checkContractVersion` channel `aboClinic`; ABO `handleOps` → `checkContractVersion` channel `aboConsole`; platform `fetch` → `requireAipContractVersion` on `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/coverage`; `GET /v1/feed/coverage` negotiating `CHANNEL_VERSIONS.platformFeed`; `VendorEntrypoint`; `GatewayObject.fetch`; `handleGetReturnPaymob` and `paymobReturnUrl`; `POST /notify/paymob`; platform `token_contract` and ABO `authenticateBilling`. Also run `runDueGrantWork` (`abo/src/work/grant.ts`) for the unknown-answer rule. Request `2` is accepted and answered in `2`. Request `1` is accepted and answered in `1`. Missing, `0`, or `3` gets that channel's refusal before authentication and before any write: ABO clinic and platform clinic routes HTTP 400 `contract_version_unsupported` with `accepted_versions` (clinic responses also carry `Abo-Contract-Version` or `Aip-Contract-Version` as that channel already does, and `contract_version` in the ABO body); ABO console the same and the refusal asks for a reload; platform feed HTTP 400 `contract_version_unsupported`; `VendorEntrypoint` `rejected` with `contract_version_unsupported`; per-clinic DO `rejected` with `contract_version_unsupported` and `accepted_versions`. Return URL has no version refusal, and `paymobReturnUrl` puts `2` in `v`. An unparseable Paymob body is an A23 alert and the evidence `adapter_version` is the variant `paymobAdapter`. A token `ver` other than `"2"` is `unauthenticated`. An answer `contract_version` outside the sender's pair, read by `runDueGrantWork`, is `contract_version_unsupported`. Do not replace the five `public` RPC functions. Do not create the stack module or the toml files in this task. Do not run the test.

- [X] T002 [US1] Add the failing test `E2E-P7.3-01` in `abo/test/version-matrix/channels.system.test.ts` — red test, FR-001, E2E-P7.3-01. Depends on T001. Title `E2E-P7.3-01`. ABO workers-pool channels that import `CHANNEL_VERSIONS`: `handleBillingV1` → `checkContractVersion` `aboClinic`; `handleOps` → `checkContractVersion` `aboConsole` (reload on the refusal body); `handleGetReturnPaymob` and `paymobReturnUrl`; `POST /notify/paymob`; `authenticateBilling`. Request `2` accepted and answered in `2`; request `1` accepted and answered in `1`; missing, `0`, or `3` is that channel's refusal before authentication and before any write. Console refusal asks for a reload. Return URL has no version refusal and built `v` is `2`. Unparseable Paymob body: A23 alert and evidence `adapter_version` is the variant `paymobAdapter`. Token `ver` other than `"2"` is `unauthenticated`. Do not replace the five `public` functions. The file is included only by `abo/vitest.version-matrix.config.ts`, which this task does not create. Do not run vitest. Do not boot wrangler.

- [X] T003 [US1] Add the failing test `E2E-P7.3-01` in `ai-platform/test/version-matrix/channels.system.test.ts` — red test, FR-001, E2E-P7.3-01. Depends on T002. Title `E2E-P7.3-01`. Platform workers-pool channels that import `CHANNEL_VERSIONS`: `fetch` → `requireAipContractVersion` on `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/coverage`; `GET /v1/feed/coverage` → `negotiate(CHANNEL_VERSIONS.platformFeed)`; `VendorEntrypoint`; `GatewayObject.fetch`; `ai-platform/src/identity/index.ts` `token_contract`. Request `2` accepted and answered in `2`; request `1` accepted and answered in `1`; missing, `0`, or `3` is that channel's refusal before authentication and before any write. Header `Aip-Contract-Version` is sent before the first byte of a stream. Feed refusal is HTTP 400 `contract_version_unsupported`. `VendorEntrypoint` answers `rejected` with `contract_version_unsupported`. The DO answers `rejected` with `contract_version_unsupported` and `accepted_versions`. A token `ver` other than `"2"` is `unauthenticated`. Do not replace the five `public` functions. The file is included only by `ai-platform/vitest.version-matrix.config.ts`, which this task does not create. Do not run vitest. Do not boot wrangler.

- [X] T004 [US1] Add the failing test `E2E-P7.3-01` in `backend/tests/contract_version_matrix.sql` — red test, FR-001, E2E-P7.3-01. Depends on T003. Title prefix `E2E-P7.3-01`. RPC cases only, inside one transaction: replace the five `public` gates `get_ai_status`, `issue_ai_token`, `issue_billing_token`, `get_ai_billing_status`, and `request_ai_status_refresh` so the accepted pair is `(1, 2)` and an `rpc_result` refusal's `contract_version` is `2`. `issue_ai_token` still `RAISE`s with `accepted_versions` `[1, 2]`. `auth_internal` bodies stay the published functions. Request `2` and request `1` succeed in the version sent. Missing, `0`, or `3` is `CONTRACT_VERSION_UNSUPPORTED` with `accepted_versions` `[1, 2]` before authentication and before any write. `ROLLBACK` leaves the published `(0, 1)` bodies. Do not add a migration, do not update `ai.contract_versions`, and do not change `packages/vendor-contracts`. Do not run `psql`.

- [X] T005 [US1] Add the failing test `E2E-P7.3-05` in `e2e/fullstack/test/p7-3-05.test.mjs` — red test, FR-002, E2E-P7.3-05. Depends on T004. Title `E2E-P7.3-05`. Import `e2e/fullstack/test/p7-3-stack.mjs`. Two bundles on the existing H-FS registry: the admission worker keeps published constants and sends `contract_version` `1`; its `DO` binding `script_name` is the receiver from `e2e/fullstack/test/variant/platform-do-receiver.toml`. Entry is `POST /v1/requests` (`ai-platform/src/worker.ts`) → `GatewayObject.fetch`. A call at `1` against a DO whose current version is `2` is accepted and answered in `1`. Missing, or a version outside `{1, 2}`, is DO `rejected` with `contract_version_unsupported` and `accepted_versions`, and the worker maps that to `coverage_unknown`. Do not create the stack module or the toml files in this task. Do not run the test.

**Checkpoint**: E2E-P7.3-01 is on disk in the H-FS file, both workers-pool files, and the SQL file. The H-FS half of E2E-P7.3-05 is on disk. None of them were executed.

### 3.2 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — tests (part 2)

**Independent Test**: E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07.

- [X] T006 [US1] Add the failing test `E2E-P7.3-05` in `ai-platform/test/version-matrix/worker-do.system.test.ts` — red test, FR-002, E2E-P7.3-05. Depends on T005. Title `E2E-P7.3-05`. `POST /v1/requests` on the published-constant worker → `DO` on the receiver bundle → `GatewayObject.fetch`. A call at `1` against DO current `2` is accepted and answered in `1`. Missing, or a version outside `{1, 2}`, is DO `rejected` with `contract_version_unsupported` and `accepted_versions`, and the worker maps that to `coverage_unknown`. The file is included only by `ai-platform/vitest.version-matrix-do.config.ts`, which this task does not create. Do not run vitest. Do not boot wrangler.

- [X] T007 [US1] Add the failing test `E2E-P7.3-06` in `frontend/test/integration/contract_version_matrix_fullstack_test.dart` — red test, FR-003, E2E-P7.3-06. Depends on T006. Title `E2E-P7.3-06`. Annotate `@Tags(['fullstack'])`. Desktop clients keep compiled constants (`1`). `AboClient` on `AdministratorBillingPage`; `AiAvailabilityReader`, `BillingTokenClient`, and `SubscriptionSummary` on `AiPage` and `CheckoutScreen`; `DiscoveryClient` and `HttpsSubmitPort` on `AiPage`. The update state is `AiDegradedView` mode `appUpdate`, composed in `AiPage` and `AdministratorBillingPage`. Each of the three channels shows the update state and no error dialog. The prepare script that starts the desktop-window workers is a later task. Do not run `flutter test`. Do not run the prepare script. Do not boot wrangler.

- [X] T008 [US1] Add the failing test `E2E-P7.3-07` in `e2e/fullstack/test/p7-3-07.test.mjs` — red test, FR-004, E2E-P7.3-07. Depends on T007. Title `E2E-P7.3-07`. Import `e2e/fullstack/test/p7-3-stack.mjs`. Entry is `GET /return/paymob` (`handleGetReturnPaymob` in `abo/src/notify/intake.ts`). `v` is a query value that is not this channel's version. An inquiry is still scheduled and the page is neutral. Do not create the stack module in this task. Do not run the test.

**Checkpoint**: E2E-P7.3-05 (platform variant), E2E-P7.3-06, and E2E-P7.3-07 are on disk and were not executed.

### 3.3 User Story 2 - Sender ahead of the receiver (Priority: P2) — tests

**Independent Test**: E2E-P7.3-02, E2E-P7.3-03, and E2E-P7.3-04 in their harnesses. Earlier suites stay green, and E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07 still pass.

- [X] T009 [US2] Add the failing test `E2E-P7.3-02` in `e2e/fullstack/test/p7-3-02.test.mjs` — red test, FR-005, E2E-P7.3-02. Depends on T008. Title `E2E-P7.3-02`. Import `e2e/fullstack/test/p7-3-stack.mjs`. Entry is `scheduled()` → `runMinuteInquiryBudget` → `runDueGrantWork` → `VendorEntrypoint.grant`. AL-07 is captured from `send_email`. Retry is the same grant work, also reached by `POST /ops/parked/{id}/retry` (`handlePostRetry` in `abo/src/ops/index.ts`). ABO on `e2e/fullstack/test/variant/abo-n-plus-1.toml` against the published platform: `rejected` with `contract_version_unsupported`, nothing written, row parked, AL-07 fires. Then the platform is restarted on `e2e/fullstack/test/variant/platform-n-plus-1.toml` and the retry applies. Do not create the stack module or the toml files in this task. Do not run the test.

- [X] T010 [US2] Add the failing test `E2E-P7.3-03` in `e2e/fullstack/test/p7-3-03.test.mjs` — red test, FR-006, E2E-P7.3-03. Depends on T009. Title `E2E-P7.3-03`. Import `e2e/fullstack/test/p7-3-stack.mjs` and start the platform on `e2e/fullstack/test/variant/platform-feed-window.toml`. Entry is `auth_internal.pull_coverage_feed()` → `GET /v1/feed/coverage`. The cursor is `ai_internal.feed_state.cursor`. The puller still sends published `1` from `ai.contract_versions`. The platform answers HTTP 400. The cursor is unchanged. The stale alert fires. Nothing is written. `ai.contract_versions` is unchanged. Do not create the stack module or the toml in this task. Do not run the test.

- [X] T011 [US2] Add the failing test `E2E-P7.3-04` in `e2e/fullstack/test/p7-3-04.test.mjs` — red test, FR-007, E2E-P7.3-04. Depends on T010. Title `E2E-P7.3-04`. Import `e2e/fullstack/test/p7-3-stack.mjs` and use the published ABO and platform configs. Entry is `scheduled()` → `runDueGrantWork`, and `POST /ops/parked/{id}/retry`. The retried row resends its stored envelope. The stored `contract_version` is unchanged. Do not create the stack module in this task. Do not run the test.

**Checkpoint**: E2E-P7.3-02, E2E-P7.3-03, and E2E-P7.3-04 are on disk and were not executed.

---

## 4. Implementation

**Purpose**: Sequencing step 2. Add the variant module, wrangler config, workers config, stack helper, or prepare script that a test imports or starts. The SQL gate for E2E-P7.3-01 is already inside `backend/tests/contract_version_matrix.sql`. Do not edit published package sources, `ai.contract_versions`, or migration bodies. Do not boot wrangler. Do not start the H-FS stack. Do not run `npm test` in `e2e/fullstack`.

Each `vendor-contracts-*.ts` file imports `packages/vendor-contracts/src/index.ts` by relative path, re-exports every named export except `CHANNEL_VERSIONS`, and exports a new `CHANNEL_VERSIONS`. The alias key is the bare specifier `vendor-contracts`. Wrangler configs are the development bindings from `abo/wrangler.toml` or `ai-platform/wrangler.toml` plus that alias.

### 4.1 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — variant modules (part 1)

**Independent Test**: E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07.

- [ ] T012 [US1] Create `e2e/fullstack/test/variant/vendor-contracts-n-plus-1.ts` — N+1 module, FR-001, E2E-P7.3-01. Depends on T011. Every channel current is published + 1, so the accepted pair is `1` and `2`. Do not edit `packages/vendor-contracts/`. Do not boot wrangler.

- [ ] T013 [US1] Create `e2e/fullstack/test/variant/vendor-contracts-do-receiver.ts` — DO receiver module, FR-002, E2E-P7.3-05. Depends on T012. Only `platformDo` is published + 1. Every other channel stays at the published constant. Do not boot wrangler.

- [ ] T014 [US1] Create `e2e/fullstack/test/variant/vendor-contracts-desktop-window.ts` — desktop-window module, FR-003, E2E-P7.3-06. Depends on T013. Only `aboClinic` and `platformClinic` are published + 2 (`3`), so the accepted pair is `2` and `3` and a desktop sending `1` is below the minimum. Do not boot wrangler.

- [ ] T015 [US1] Create `e2e/fullstack/test/variant/abo-n-plus-1.toml` — ABO N+1 wrangler config, FR-001, FR-005, E2E-P7.3-01, E2E-P7.3-02. Depends on T014. ABO development bindings plus the alias to `vendor-contracts-n-plus-1.ts`. Do not edit `abo/wrangler.toml`. Do not boot wrangler.

- [ ] T016 [US1] Create `e2e/fullstack/test/variant/platform-n-plus-1.toml` — platform N+1 wrangler config, FR-001, FR-005, E2E-P7.3-01, E2E-P7.3-02. Depends on T015. Platform development bindings plus the alias to `vendor-contracts-n-plus-1.ts`. Do not edit `ai-platform/wrangler.toml`. Do not boot wrangler.

**Checkpoint**: E2E-P7.3-01 and E2E-P7.3-02 have the N+1 module and both N+1 configs on disk. E2E-P7.3-05 has the DO receiver module. E2E-P7.3-06 has the desktop-window module. Nothing was started.

### 4.2 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — variant configs (part 2)

**Independent Test**: E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07.

- [ ] T017 [US1] Create `e2e/fullstack/test/variant/platform-worker-n.toml` — published platform worker config, FR-002, E2E-P7.3-05. Depends on T016. Published platform constants. The `DO` binding `script_name` points at the receiver worker from `e2e/fullstack/test/variant/platform-do-receiver.toml`. Do not boot wrangler.

- [ ] T018 [US1] Create `e2e/fullstack/test/variant/platform-do-receiver.toml` — DO receiver wrangler config, FR-002, E2E-P7.3-05. Depends on T017. Platform development bindings plus the alias to `vendor-contracts-do-receiver.ts`. Do not boot wrangler.

- [ ] T019 [US1] Create `e2e/fullstack/test/variant/abo-desktop-window.toml` — ABO desktop-window config, FR-003, E2E-P7.3-06. Depends on T018. ABO development bindings plus the alias to `vendor-contracts-desktop-window.ts`. Do not boot wrangler.

- [ ] T020 [US1] Create `e2e/fullstack/test/variant/platform-desktop-window.toml` — platform desktop-window config, FR-003, E2E-P7.3-06. Depends on T019. Platform development bindings plus the alias to `vendor-contracts-desktop-window.ts`. Do not boot wrangler.

- [ ] T021 [US1] Create `e2e/fullstack/test/p7-3-stack.mjs` — H-FS boot helper, FR-001, FR-002, FR-004, FR-005, FR-006, FR-007, E2E-P7.3-01, E2E-P7.3-02, E2E-P7.3-03, E2E-P7.3-04, E2E-P7.3-05, E2E-P7.3-07. Depends on T020. Start the worker pair a scenario names, on the existing H-FS registry and ports. This task writes the module and does not import it. Do not boot wrangler. Do not start the H-FS stack. Do not run `npm test` in `e2e/fullstack`.

**Checkpoint**: E2E-P7.3-05 has both platform worker configs. E2E-P7.3-06 has both desktop-window configs. The H-FS tests have a boot module on disk. The stack is not started.

### 4.3 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — workers configs and prepare

**Independent Test**: E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07.

- [ ] T022 [US1] Create `abo/vitest.version-matrix.config.ts` — ABO workers-pool config, FR-001, E2E-P7.3-01. Depends on T021. Workers pool, N+1 alias to `vendor-contracts`, `include` `test/version-matrix/**`. Leave `abo/vitest.workers.config.ts` unchanged. Do not run vitest. Do not boot wrangler.

- [ ] T023 [US1] Create `ai-platform/vitest.version-matrix.config.ts` — platform workers-pool config, FR-001, E2E-P7.3-01. Depends on T022. Workers pool, N+1 alias to `vendor-contracts`, `include` `test/version-matrix/channels.system.test.ts`. Leave `ai-platform/vitest.workers.config.ts` unchanged. Do not run vitest. Do not boot wrangler.

- [ ] T024 [US1] Create `ai-platform/vitest.version-matrix-do.config.ts` — platform DO workers config, FR-002, E2E-P7.3-05. Depends on T023. Published main worker plus a DO receiver auxiliary whose alias sets only `platformDo` to published + 1. Include `ai-platform/test/version-matrix/worker-do.system.test.ts`. Do not run vitest. Do not boot wrangler.

- [ ] T025 [US1] Create `e2e/fullstack/test/p7-3-06-prepare.mjs` — desktop prepare script, FR-003, E2E-P7.3-06. Depends on T024. Start the ABO on `abo-desktop-window.toml` and the platform on `platform-desktop-window.toml`. For the RPC channel only, replace the five `public` gates so the accepted pair is `(2, 3)` and an `rpc_result` refusal's `contract_version` is `3`, then restore `(0, 1)` before exit. Do not add a migration, do not update `ai.contract_versions`, and do not change `packages/vendor-contracts`. This task writes the script and does not run it. Do not boot wrangler. Do not run `flutter test`.

**Checkpoint**: E2E-P7.3-01 has both workers-pool configs. E2E-P7.3-05 has the DO workers config. E2E-P7.3-06 has a prepare script on disk. None of them were started.

### 4.4 User Story 2 - Sender ahead of the receiver (Priority: P2) — feed window

**Independent Test**: E2E-P7.3-02, E2E-P7.3-03, and E2E-P7.3-04 in their harnesses. Earlier suites stay green, and E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07 still pass.

- [ ] T026 [US2] Create `e2e/fullstack/test/variant/vendor-contracts-feed-window.ts` — feed-window module, FR-006, E2E-P7.3-03. Depends on T011. Only `platformFeed` is published + 2 (`3`), so `negotiate(3, 1)` refuses because the accepted pair is `2` and `3`. Every other channel stays at the published constant. Do not update `ai.contract_versions`. Do not boot wrangler.

- [ ] T027 [US2] Create `e2e/fullstack/test/variant/platform-feed-window.toml` — feed-window wrangler config, FR-006, E2E-P7.3-03. Depends on T026. Platform development bindings plus the alias to `vendor-contracts-feed-window.ts`. Do not edit `ai-platform/wrangler.toml`. Do not boot wrangler.

**Checkpoint**: E2E-P7.3-03 has the feed-window module and config on disk. The platform was not started.

---

## 5. Verification

**Purpose**: The seven E2E ids are on disk in the files **Test Layout** names. Proving the worker harnesses green would boot wrangler, so this task does not run them. The SQL file does not boot a worker; this workflow does not run it either.

### 5.1 User Story 2 - Sender ahead of the receiver (Priority: P2) — unit harness

**Independent Test**: E2E-P7.3-02, E2E-P7.3-03, and E2E-P7.3-04 in their harnesses. Earlier suites stay green, and E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07 still pass.

- [ ] T028 [US2] Confirm the seven E2E ids are the Test Layout files and do not execute the harness — file check, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, E2E-P7.3-01, E2E-P7.3-02, E2E-P7.3-03, E2E-P7.3-04, E2E-P7.3-05, E2E-P7.3-06, E2E-P7.3-07. Depends on T025 and T027. `e2e/fullstack/test/p7-3-01.test.mjs` holds `E2E-P7.3-01`. `abo/test/version-matrix/channels.system.test.ts` holds `E2E-P7.3-01`. `ai-platform/test/version-matrix/channels.system.test.ts` holds `E2E-P7.3-01`. `backend/tests/contract_version_matrix.sql` holds `E2E-P7.3-01`. `e2e/fullstack/test/p7-3-02.test.mjs` holds `E2E-P7.3-02`. `e2e/fullstack/test/p7-3-03.test.mjs` holds `E2E-P7.3-03`. `e2e/fullstack/test/p7-3-04.test.mjs` holds `E2E-P7.3-04`. `e2e/fullstack/test/p7-3-05.test.mjs` and `ai-platform/test/version-matrix/worker-do.system.test.ts` hold `E2E-P7.3-05`. `frontend/test/integration/contract_version_matrix_fullstack_test.dart` holds `E2E-P7.3-06`. `e2e/fullstack/test/p7-3-07.test.mjs` holds `E2E-P7.3-07`. Each title starts with that id. This task creates no file and edits no file. Do not run `node --import tsx --test`. Do not run `npx vitest`. Do not run `flutter test`. Do not run `psql`. Do not run `e2e/fullstack/test/p7-3-06-prepare.mjs`. Do not boot wrangler. Do not start the H-FS stack. Do not run `npm test` in `e2e/fullstack`. Do not run earlier suites. Leave `e2e/fullstack/package.json` on its current `test` script.

**Checkpoint**: E2E-P7.3-01, E2E-P7.3-02, E2E-P7.3-03, E2E-P7.3-04, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07 are present and were not executed.

---

## 6. Documentation

**Purpose**: Sequencing step 3. `quickstart.md` from the plan outline, after the tests and variants are on disk. The harness commands are written into that file and are not run. Plan-phase `research.md`, `data-model.md`, and `contracts/` stay omitted.

### 6.1 User Story 2 - Sender ahead of the receiver (Priority: P2) — quickstart

**Independent Test**: E2E-P7.3-02, E2E-P7.3-03, and E2E-P7.3-04 in their harnesses. Earlier suites stay green, and E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07 still pass.

- [ ] T029 [US2] Write `specs/095-abo-p7-3-contract-version-matrix/quickstart.md` — unit quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, E2E-P7.3-01, E2E-P7.3-02, E2E-P7.3-03, E2E-P7.3-04, E2E-P7.3-05, E2E-P7.3-06, E2E-P7.3-07. Depends on T028. Fill only these sections: what was implemented and the files added; the harness commands for this unit's tests only, from Sequencing (H-FS `node --import tsx --test` of the six `p7-3-*.test.mjs` files, the ABO `vitest.version-matrix.config.ts` command, both platform vitest commands, `node --import tsx e2e/fullstack/test/p7-3-06-prepare.mjs` then the Flutter `fullstack` test, and the `psql` command for `backend/tests/contract_version_matrix.sql`); the entry point → module chain per E2E id. Do not list earlier-unit files, combined counts, or full-suite commands. These scenarios are harness-visible, so the outline has no manual step. Do not run those commands. Do not boot wrangler.

**Checkpoint**: `quickstart.md` names the seven E2E ids, the unit commands, and the entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests**: No earlier phase. User Story 1 tests, then User Story 2 tests.
- **Implementation**: After the test file that imports or starts that variant. User Story 1 modules and wrangler configs, then the workers configs and the desktop prepare script. The User Story 2 feed-window files depend on the User Story 2 tests.
- **Verification**: After every test file and every variant those tests start.
- **Documentation**: After verification. `quickstart.md` only.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: Starts immediately. E2E-P7.3-01 files, then E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07.
- **User Story 2 (P2)**: Test files follow the User Story 1 tests. E2E-P7.3-02 uses the N+1 configs from User Story 1. E2E-P7.3-03 uses the feed-window files. E2E-P7.3-04 uses the published configs and the stack helper.

### 7.3 Within Each Phase

- T001 creates `e2e/fullstack/test/p7-3-01.test.mjs`. T002 creates `abo/test/version-matrix/channels.system.test.ts`. T003 creates `ai-platform/test/version-matrix/channels.system.test.ts`. T004 creates `backend/tests/contract_version_matrix.sql`. T005 creates `e2e/fullstack/test/p7-3-05.test.mjs`. T006 creates `ai-platform/test/version-matrix/worker-do.system.test.ts`. T007 creates `frontend/test/integration/contract_version_matrix_fullstack_test.dart`. T008 creates `e2e/fullstack/test/p7-3-07.test.mjs`. T009 creates `e2e/fullstack/test/p7-3-02.test.mjs`. T010 creates `e2e/fullstack/test/p7-3-03.test.mjs`. T011 creates `e2e/fullstack/test/p7-3-04.test.mjs`.
- T012 creates `e2e/fullstack/test/variant/vendor-contracts-n-plus-1.ts` after T011. T013 creates `vendor-contracts-do-receiver.ts`. T014 creates `vendor-contracts-desktop-window.ts`. T015 creates `abo-n-plus-1.toml`. T016 creates `platform-n-plus-1.toml`. T017 creates `platform-worker-n.toml`. T018 creates `platform-do-receiver.toml`. T019 creates `abo-desktop-window.toml`. T020 creates `platform-desktop-window.toml`. T021 creates `e2e/fullstack/test/p7-3-stack.mjs` and does not import it. T022 creates `abo/vitest.version-matrix.config.ts`. T023 creates `ai-platform/vitest.version-matrix.config.ts`. T024 creates `ai-platform/vitest.version-matrix-do.config.ts`. T025 creates `e2e/fullstack/test/p7-3-06-prepare.mjs` and does not run it.
- T026 creates `vendor-contracts-feed-window.ts` after T011. T027 creates `platform-feed-window.toml`.
- T028 reads the test files and does not edit them. It waits until T025 and T027 are done.
- T029 writes only `specs/095-abo-p7-3-contract-version-matrix/quickstart.md`.

---

## 8. Implementation Waves

Scheduling lives only here. One subphase is one bullet. Tasks inside a subphase run in order.

### 8.1 Wave 1

- T001–T005 [US1] — subphase: `### 3.1 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — tests (part 1)` — paths: `e2e/fullstack/test/p7-3-01.test.mjs`, `abo/test/version-matrix/channels.system.test.ts`, `ai-platform/test/version-matrix/channels.system.test.ts`, `backend/tests/contract_version_matrix.sql`, `e2e/fullstack/test/p7-3-05.test.mjs`

### 8.2 Wave 2

- T006–T008 [US1] — subphase: `### 3.2 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — tests (part 2)` — paths: `ai-platform/test/version-matrix/worker-do.system.test.ts`, `frontend/test/integration/contract_version_matrix_fullstack_test.dart`, `e2e/fullstack/test/p7-3-07.test.mjs`

### 8.3 Wave 3

- T009–T011 [US2] — subphase: `### 3.3 User Story 2 - Sender ahead of the receiver (Priority: P2) — tests` — paths: `e2e/fullstack/test/p7-3-02.test.mjs`, `e2e/fullstack/test/p7-3-03.test.mjs`, `e2e/fullstack/test/p7-3-04.test.mjs`

### 8.4 Wave 4

- T012–T016 [US1] — subphase: `### 4.1 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — variant modules (part 1)` — paths: `e2e/fullstack/test/variant/vendor-contracts-n-plus-1.ts`, `e2e/fullstack/test/variant/vendor-contracts-do-receiver.ts`, `e2e/fullstack/test/variant/vendor-contracts-desktop-window.ts`, `e2e/fullstack/test/variant/abo-n-plus-1.toml`, `e2e/fullstack/test/variant/platform-n-plus-1.toml`
- T026–T027 [US2] — subphase: `### 4.4 User Story 2 - Sender ahead of the receiver (Priority: P2) — feed window` — paths: `e2e/fullstack/test/variant/vendor-contracts-feed-window.ts`, `e2e/fullstack/test/variant/platform-feed-window.toml`

### 8.5 Wave 5

- T017–T021 [US1] — subphase: `### 4.2 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — variant configs (part 2)` — paths: `e2e/fullstack/test/variant/platform-worker-n.toml`, `e2e/fullstack/test/variant/platform-do-receiver.toml`, `e2e/fullstack/test/variant/abo-desktop-window.toml`, `e2e/fullstack/test/variant/platform-desktop-window.toml`, `e2e/fullstack/test/p7-3-stack.mjs`

### 8.6 Wave 6

- T022–T025 [US1] — subphase: `### 4.3 User Story 1 - Each channel accepts N and N−1 (Priority: P1) — workers configs and prepare` — paths: `abo/vitest.version-matrix.config.ts`, `ai-platform/vitest.version-matrix.config.ts`, `ai-platform/vitest.version-matrix-do.config.ts`, `e2e/fullstack/test/p7-3-06-prepare.mjs`

### 8.7 Wave 7

- T028 [US2] — subphase: `### 5.1 User Story 2 - Sender ahead of the receiver (Priority: P2) — unit harness` — paths: `e2e/fullstack/test/p7-3-01.test.mjs`, `abo/test/version-matrix/channels.system.test.ts`, `ai-platform/test/version-matrix/channels.system.test.ts`, `backend/tests/contract_version_matrix.sql`, `e2e/fullstack/test/p7-3-02.test.mjs`, `e2e/fullstack/test/p7-3-03.test.mjs`, `e2e/fullstack/test/p7-3-04.test.mjs`, `e2e/fullstack/test/p7-3-05.test.mjs`, `ai-platform/test/version-matrix/worker-do.system.test.ts`, `frontend/test/integration/contract_version_matrix_fullstack_test.dart`, `e2e/fullstack/test/p7-3-07.test.mjs`

### 8.8 Wave 8

- T029 [US2] — subphase: `### 6.1 User Story 2 - Sender ahead of the receiver (Priority: P2) — quickstart` — paths: `specs/095-abo-p7-3-contract-version-matrix/quickstart.md`
