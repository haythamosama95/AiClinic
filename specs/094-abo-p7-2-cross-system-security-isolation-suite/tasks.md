# Tasks: Cross-system security and isolation suite

**Input**: Design documents from `specs/094-abo-p7-2-cross-system-security-isolation-suite/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: none. P6.4 and P4.11 publish no Outputs / freezes line. Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is omitted (no spike). `data-model.md` and `contracts/` are omitted (no entities; this unit freezes no wire shape). `quickstart.md` is written in Documentation after the test files exist.

**Organization**: P7.2 is User Story 1, User Story 2, and User Story 3 (`[US1]`, `[US2]`, `[US3]`), size M (rule S3). Branch `ai/094-abo-p7-2-cross-system-security-isolation-suite`. E2E ids stay `E2E-P7.2-01` through `E2E-P7.2-09`. Tests are one task per E2E id, written before any product edit. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 15. Size M is 20–32 (rule S3). Plan sequencing implies 16. Sequencing step 2 is two **Files** units, so it is two tasks. Sequencing steps 13 and 15 would boot wrangler through the H-FS stack; those steps are the nine test files, not a run. Sequencing step 14 names no product path, so it is not a task. The count is not padded. `npm test` in `e2e/fullstack` is not a task. This unit does not boot wrangler and does not start the H-FS stack.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Harness H-FS**: `e2e/fullstack/`. Tests are Node (`node:test`) files. The shared boot module is `e2e/fullstack/test/p7-2-stack.mjs`. The harness worker is the existing `e2e/fullstack/src/register-issuer.ts`. The Dart driver is `e2e/fullstack/dart/`
- **Unit command** (recorded for `quickstart.md`; this workflow does not run it), from `e2e/fullstack/`:

```bash
node --import tsx --test test/p7-2-untrusted-callers.test.mjs test/p7-2-vendor-entrypoint.test.mjs test/p7-2-credential-isolation.test.mjs
```

- **Unchanged by this unit**: `e2e/fullstack/package.json` stays on its current `test` script. No new platform route and no new ABO route. No file under `frontend/test/`. Product files stay unchanged. `POST /register-issuer-key` stays as it is
- **Spec Kit artifacts**: `specs/094-abo-p7-2-cross-system-security-isolation-suite/`

---

## 3. Setup

**Purpose**: Sequencing steps 1–3. Scaffold the three test files import. These files are the harness, not the product behaviour the tests cover. Create them and do not execute them. Do not boot wrangler. Do not start the H-FS stack. Do not run `npm test` in `e2e/fullstack`.

### 3.1 User Story 2 - VendorEntrypoint paid grant and class H/HP (Priority: P2) — vendor-call route

**Independent Test**: E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 in harness H-FS.

- [X] T001 [US2] Add `POST /vendor-call` on `e2e/fullstack/src/register-issuer.ts` — harness route, FR-005, FR-006, FR-007, E2E-P7.2-05, E2E-P7.2-06, E2E-P7.2-09. Depends on nothing. The body is `{ method, args }`. `args` is the `vendorCall` payload (`access_jwt`, and `assertion` when present). The worker calls `env.PLATFORM[method](args)` only for `grant`, `suspend`, `resume`, `armKillSwitch`, `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, and `voidGrant`. Any other method answers 404. Leave `POST /register-issuer-key` in place. The Node runner is the only caller. Do not boot wrangler. Do not start the H-FS stack.

**Checkpoint**: E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 have a harness route. The route is not called.

### 3.2 User Story 3 - Credential isolation (Priority: P3) — dart package

**Independent Test**: E2E-P7.2-07 and E2E-P7.2-08 in harness H-FS. Earlier suites stay green, and E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 still pass.

- [X] T002 [US3] Create `e2e/fullstack/dart/pubspec.yaml` — Dart package, FR-009, E2E-P7.2-08. Depends on T001. Package name `abo_p7_2_session_capture`, `publish_to: none`, SDK ^3.11.5, path dependency `ai_clinic` → `../../../frontend`. Do not run `dart`. Do not boot wrangler.

**Checkpoint**: E2E-P7.2-08 has a package manifest. The driver is not started.

### 3.3 User Story 3 - Credential isolation (Priority: P3) — dart driver

**Independent Test**: E2E-P7.2-07 and E2E-P7.2-08 in harness H-FS. Earlier suites stay green, and E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 still pass.

- [X] T003 [US3] Create `e2e/fullstack/dart/bin/session_jwt_capture.dart` — Dart driver, FR-009, E2E-P7.2-08. Depends on T001. Construct `DiscoveryClient`, `PlatformHttpsSubmitPort` (the `HttpsSubmitPort` in `frontend/lib/core/ai/https_submit_port.dart`), `UsageSummaryClient`, and `AboClient` with a recording `http.Client`. Print one JSON object `{url, authorization}` for each outbound call. The Supabase session JWT stays in the driver process and is not the AI token or the billing token those clients send. Do not run `dart`. Do not boot wrangler. Do not add a file under `frontend/test/`.

**Checkpoint**: E2E-P7.2-08 has a driver file. The driver is not started.

### 3.4 User Story 1 - Untrusted clinic and payment callers (Priority: P1) — stack helper

**Independent Test**: E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, and E2E-P7.2-04 in harness H-FS.

- [X] T004 [US1] Create `e2e/fullstack/test/p7-2-stack.mjs` — shared H-FS boot, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, E2E-P7.2-07, E2E-P7.2-08, E2E-P7.2-09. Depends on T001. Boot local Supabase, the platform worker, the harness worker, the Paymob stub, and the ABO worker the way `e2e/fullstack/test/p5-2.test.mjs` does. Start the ABO process with `--test-scheduled`. Capture platform `send_email` text from the worker log (`send_email binding called with MessageBuilder` and the text-file path). Read ABO D1 with `wrangler d1 execute`. Addresses the file boots, when a later run imports it: platform `http://127.0.0.1:8787`, ABO `http://127.0.0.1:8788`, Paymob stub `http://127.0.0.1:8789`, harness worker `http://127.0.0.1:8790`, billing host `billing.vendor.test`, ops host `ops.vendor.test`. This task writes the module and does not import it. Do not boot wrangler. Do not start the H-FS stack. Do not run `npm test` in `e2e/fullstack`.

**Checkpoint**: E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, and E2E-P7.2-04 have a boot module on disk. The stack is not started.

---

## 4. Tests

**Purpose**: Sequencing steps 4–12. One test per E2E id. Each test is written to fail if the behaviour misses its FR, and this workflow does not execute it. Leave product files unchanged. Do not boot wrangler. Do not start the H-FS stack. Do not run `npm test` in `e2e/fullstack`. Do not run the three-file `node --test` command.

The three test files import `e2e/fullstack/test/p7-2-stack.mjs`. `e2e/fullstack/package.json` stays on its current `test` script.

### 4.1 User Story 1 - Untrusted clinic and payment callers (Priority: P1) — tests

**Independent Test**: E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, and E2E-P7.2-04 in harness H-FS.

- [X] T005 [US1] Add the failing test `E2E-P7.2-01` in `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` — red test, FR-001, E2E-P7.2-01. Depends on T004. Title `E2E-P7.2-01`. ABO `fetch` → `POST /notify/paymob` and `GET /return/paymob` on `BILLING_HOST`. Junk is rate-limited and not stored. A body over 1_048_576 bytes is HTTP 413 with an empty body and nothing stored or enqueued. The request past 60 in 60 seconds is HTTP 429 with an empty body and nothing stored or enqueued. The key is `CF-Connecting-IP`, and a missing header uses `unknown`. `/return` does not create or extend service. Do not run the test.

**Checkpoint**: E2E-P7.2-01 exists and is not executed.

- [X] T006 [US1] Add the failing test `E2E-P7.2-02` in `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` — red test, FR-002, E2E-P7.2-02. Depends on T005. Title `E2E-P7.2-02`. PostgREST `public.issue_billing_token` and staff RPCs including `get_ai_status`; platform `GET /v1/coverage`. A staff user cannot obtain a billing token. `/v1/coverage` is 403. No RPC writes status. The status row is unchanged. Do not run the test.

**Checkpoint**: E2E-P7.2-01 and E2E-P7.2-02 exist and are not executed.

- [X] T007 [US1] Add the failing test `E2E-P7.2-03` in `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` — red test, FR-003, E2E-P7.2-03. Depends on T006. Title `E2E-P7.2-03`. ABO `handleBillingV1` paths `/v1/offers`, `/v1/subscription`, `/v1/payments`, `/v1/billing-contact`, `/v1/checkouts`, `/v1/checkouts/{id}`; PostgREST RPCs the administrator session can execute; platform `GET /v1/capabilities`, `POST /v1/requests`, `GET /v1/coverage`, `GET /v1/feed/coverage`. Org A's administrator replays B's ids. The answer is not found. B is unchanged. No token is obtained for B. A's open checkout locks nothing of B's. The ABO and RPCs take the tenant only from the session. Do not run the test.

**Checkpoint**: E2E-P7.2-01, E2E-P7.2-02, and E2E-P7.2-03 exist and are not executed.

- [X] T008 [US1] Add the failing test `E2E-P7.2-04` in `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` — red test, FR-004, E2E-P7.2-04. Depends on T007. Title `E2E-P7.2-04`. ABO `POST /notify/paymob`, then the ABO inquiry of that callback against the H-FS Paymob stub. A callback forged with the leaked HMAC secret (the secret the ABO worker is started with) does not confirm. No payment is created. Inquiry answers are matched to the checkout's stored order id, amount, and currency. Do not run the test.

**Checkpoint**: E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, and E2E-P7.2-04 exist and are not executed.

### 4.2 User Story 2 - VendorEntrypoint paid grant and class H/HP (Priority: P2) — tests

**Independent Test**: E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 in harness H-FS.

- [X] T009 [US2] Add the failing test `E2E-P7.2-05` in `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs` — red test, FR-005, E2E-P7.2-05. Depends on T008. Title `E2E-P7.2-05`. Harness `POST /vendor-call` → `VendorEntrypoint.grant` and the class HP methods. A paid grant is `grant` with `abo_kid`, `abo_signature`, and `envelope_b64`. The envelope is canonicalized with `vendor-contracts` and signed with the H-FS ABO grant key (`kid` `abo-grant-test`). The published plan row already on the H-FS platform is the bound. The within-bound grant has no ABO payment. A paid grant beyond that bound is rejected and does not apply. One within the bound applies and raises AL-11, AL-17, and finding kind `grant_without_payment`. AL-11 and AL-17 are read from the platform `SEND_EMAIL` capture. After the within-bound grant, the test triggers the ABO cron `0 6 * * *` through the local `/__scheduled` path so `scheduled()` runs `runReconciliation`. The ABO D1 `finding` row kind is `grant_without_payment`. An HP call without an assertion is rejected. The AL-11 body shows the operation the passkey signed, when that operation is not the one shown to the operator. Do not run the test.

**Checkpoint**: E2E-P7.2-05 exists and is not executed.

- [X] T010 [US2] Add the failing test `E2E-P7.2-06` in `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs` — red test, FR-006, E2E-P7.2-06. Depends on T009. Title `E2E-P7.2-06`. Class H: harness `POST /vendor-call` → `suspend`, `resume`, `armKillSwitch`; ABO `POST /ops/checkouts/{id}/cancel` and `POST /ops/parked/{id}/retry` with `Cf-Access-Jwt-Assertion`. Class HP: `grant` (complimentary), `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, `voidGrant`. An Access JWT alone allows the class H actions and rejects the class HP actions. A passkey plus a session still enforces ceilings (≤ 31 days, and ≤ 62 days per clinic per 90 days). A complimentary grant of a year is blocked by the 31-day ceiling. Class H and class HP use the existing testkit Access JWT and WebAuthn assertion through `POST /vendor-call`. Do not run the test.

**Checkpoint**: E2E-P7.2-05 and E2E-P7.2-06 exist and are not executed.

- [X] T011 [US2] Add the failing test `E2E-P7.2-09` in `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs` — red test, FR-007, E2E-P7.2-09. Depends on T010. Title `E2E-P7.2-09`. Harness `POST /vendor-call` → class HP methods `grant`, `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, `voidGrant`. The fixture token is the literal string `ci-staging-token` in this test. It is not read from the environment. It is sent as `access_jwt` with `assertion` omitted. That token cannot reach any of those methods. Do not run the test.

**Checkpoint**: E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 exist and are not executed.

### 4.3 User Story 3 - Credential isolation (Priority: P3) — tests

**Independent Test**: E2E-P7.2-07 and E2E-P7.2-08 in harness H-FS. Earlier suites stay green, and E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 still pass.

- [X] T012 [US3] Add the failing test `E2E-P7.2-07` in `e2e/fullstack/test/p7-2-credential-isolation.test.mjs` — red test, FR-008, E2E-P7.2-07. Depends on T011. Title `E2E-P7.2-07`. Read `abo/wrangler.toml` and `ai-platform/wrangler.toml`. Neither config holds a Supabase credential. A billing token, an AI token, and a feed token presented to PostgREST on local Supabase are rejected. Do not edit those config files. Do not run the test.

**Checkpoint**: E2E-P7.2-07 exists and is not executed.

- [X] T013 [US3] Add the failing test `E2E-P7.2-08` in `e2e/fullstack/test/p7-2-credential-isolation.test.mjs` — red test, FR-009, E2E-P7.2-08. Depends on T003 and T012. Title `E2E-P7.2-08`. The test starts `dart run bin/session_jwt_capture.dart` from `e2e/fullstack/dart/` against H-FS. The driver constructs `DiscoveryClient`, `PlatformHttpsSubmitPort`, `UsageSummaryClient`, and `AboClient`. The captured URL and `Authorization` headers for the ABO and the platform do not contain the Supabase session JWT. Do not run the test. Do not run `dart`. Do not add a file under `frontend/test/`.

**Checkpoint**: E2E-P7.2-07 and E2E-P7.2-08 exist and are not executed. E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 are already files and are not executed.

---

## 5. Verification

**Purpose**: The nine tests are on disk, one title per E2E id. Proving the harness green would boot wrangler, so this task does not run it. There is no Implementation phase: **Files** names no product path, and sequencing step 14 is not a task.

### 5.1 User Story 3 - Credential isolation (Priority: P3) — unit harness

**Independent Test**: E2E-P7.2-07 and E2E-P7.2-08 in harness H-FS. Earlier suites stay green, and E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 still pass.

- [X] T014 [US3] Confirm the nine tests are the three files and do not execute the harness — file check, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, E2E-P7.2-07, E2E-P7.2-08, E2E-P7.2-09. Depends on T013. `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` holds `E2E-P7.2-01`, `E2E-P7.2-02`, `E2E-P7.2-03`, and `E2E-P7.2-04`. `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs` holds `E2E-P7.2-05`, `E2E-P7.2-06`, and `E2E-P7.2-09`. `e2e/fullstack/test/p7-2-credential-isolation.test.mjs` holds `E2E-P7.2-07` and `E2E-P7.2-08`. Each title starts with that id. This task creates no file and edits no file. Do not run `node --import tsx --test`. Do not boot wrangler. Do not start the H-FS stack. Do not run `npm test` in `e2e/fullstack`. Do not run earlier suites. Leave `e2e/fullstack/package.json` on its current `test` script. Add no platform route and no ABO route.

**Checkpoint**: E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, E2E-P7.2-07, E2E-P7.2-08, and E2E-P7.2-09 are present and were not executed.

---

## 6. Documentation

**Purpose**: Sequencing step 16. `quickstart.md` from the plan outline. The harness command is written into that file and is not run. Plan-phase `research.md`, `data-model.md`, and `contracts/` stay omitted.

### 6.1 User Story 3 - Credential isolation (Priority: P3) — quickstart

**Independent Test**: E2E-P7.2-07 and E2E-P7.2-08 in harness H-FS. Earlier suites stay green, and E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 still pass.

- [X] T015 [US3] Write `specs/094-abo-p7-2-cross-system-security-isolation-suite/quickstart.md` — unit quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, E2E-P7.2-07, E2E-P7.2-08, E2E-P7.2-09. Depends on T014. Fill only these sections: what was implemented and the files added or modified; the harness command for this unit's tests only, from `e2e/fullstack/`, `node --import tsx --test test/p7-2-untrusted-callers.test.mjs test/p7-2-vendor-entrypoint.test.mjs test/p7-2-credential-isolation.test.mjs`; the entry point → module chain per E2E id. Do not list earlier-unit files, combined counts, or full-suite commands. These nine scenarios are harness-visible, so the outline has no manual step. Do not run that command. Do not boot wrangler.

**Checkpoint**: `quickstart.md` names the nine E2E ids, the unit command, and the entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Setup (Phase 3)**: T001 adds `POST /vendor-call` on `e2e/fullstack/src/register-issuer.ts`. T002 creates `e2e/fullstack/dart/pubspec.yaml`. T003 creates `e2e/fullstack/dart/bin/session_jwt_capture.dart`. T004 creates `e2e/fullstack/test/p7-2-stack.mjs`. None of these tasks start a process.
- **Tests (Phase 4)**: Starts after T004. T005 creates `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs` with `E2E-P7.2-01`. T006, T007, and T008 add `E2E-P7.2-02`, `E2E-P7.2-03`, and `E2E-P7.2-04` in that file. T009 creates `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs` with `E2E-P7.2-05`. T010 and T011 add `E2E-P7.2-06` and `E2E-P7.2-09`. T012 creates `e2e/fullstack/test/p7-2-credential-isolation.test.mjs` with `E2E-P7.2-07`. T013 adds `E2E-P7.2-08` and is the task that starts the Dart driver in source only. No test is executed.
- **Verification (Phase 5)**: Starts after T013. T014 reads the three test files and does not run them. There is no product implementation task.
- **Documentation (Phase 6)**: Starts after T014. One file: `quickstart.md`.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: The boot module is T004. The four failing tests are T005 through T008. E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, and E2E-P7.2-04 are in the file check (T014).
- **User Story 2 (P2)**: The harness route is T001, before the stack module. The three failing tests are T009 through T011, after the User Story 1 tests. E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 are in the file check (T014).
- **User Story 3 (P3)**: The Dart package and driver are T002 and T003, after the harness route and before `E2E-P7.2-08`. The two failing tests are T012 and T013, after the User Story 2 tests. E2E-P7.2-07 and E2E-P7.2-08 are in the file check (T014). The quickstart is T015.

### 7.3 Within Each Phase

- T001 writes `e2e/fullstack/src/register-issuer.ts`. T002 writes `e2e/fullstack/dart/pubspec.yaml`. T003 writes `e2e/fullstack/dart/bin/session_jwt_capture.dart`. T004 writes `e2e/fullstack/test/p7-2-stack.mjs` and does not import it.
- T005 creates `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs`. T006 through T008 write that same file in id order. T009 creates `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs`. T010 and T011 write that same file in id order. T012 creates `e2e/fullstack/test/p7-2-credential-isolation.test.mjs`. T013 writes that same file.
- T014 reads the three test files and does not edit them.
- T015 writes only `specs/094-abo-p7-2-cross-system-security-isolation-suite/quickstart.md`.

---

## 8. Implementation Waves

The Dart package manifest and the driver share no path, and both follow the vendor-call route, so that wave has two bullets. Every other subphase is serial with the one before it.

### 8.1 Wave 1

- T001 [US2] — subphase: `### 3.1 User Story 2 - VendorEntrypoint paid grant and class H/HP (Priority: P2) — vendor-call route` — paths: `e2e/fullstack/src/register-issuer.ts`

### 8.2 Wave 2

- T002 [US3] — subphase: `### 3.2 User Story 3 - Credential isolation (Priority: P3) — dart package` — paths: `e2e/fullstack/dart/pubspec.yaml`
- T003 [US3] — subphase: `### 3.3 User Story 3 - Credential isolation (Priority: P3) — dart driver` — paths: `e2e/fullstack/dart/bin/session_jwt_capture.dart`

### 8.3 Wave 3

- T004 [US1] — subphase: `### 3.4 User Story 1 - Untrusted clinic and payment callers (Priority: P1) — stack helper` — paths: `e2e/fullstack/test/p7-2-stack.mjs`

### 8.4 Wave 4

- T005–T008 [US1] — subphase: `### 4.1 User Story 1 - Untrusted clinic and payment callers (Priority: P1) — tests` — paths: `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs`

### 8.5 Wave 5

- T009–T011 [US2] — subphase: `### 4.2 User Story 2 - VendorEntrypoint paid grant and class H/HP (Priority: P2) — tests` — paths: `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs`

### 8.6 Wave 6

- T012–T013 [US3] — subphase: `### 4.3 User Story 3 - Credential isolation (Priority: P3) — tests` — paths: `e2e/fullstack/test/p7-2-credential-isolation.test.mjs`

### 8.7 Wave 7

- T014 [US3] — subphase: `### 5.1 User Story 3 - Credential isolation (Priority: P3) — unit harness` — paths: `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs`, `e2e/fullstack/test/p7-2-vendor-entrypoint.test.mjs`, `e2e/fullstack/test/p7-2-credential-isolation.test.mjs`

### 8.8 Wave 8

- T015 [US3] — subphase: `### 6.1 User Story 3 - Credential isolation (Priority: P3) — quickstart` — paths: `specs/094-abo-p7-2-cross-system-security-isolation-suite/quickstart.md`
