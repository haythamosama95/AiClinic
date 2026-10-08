# Tasks: Staging environment, external monitors and the staging profile

**Input**: Design documents from `specs/096-abo-p8-1-staging-environment-external-monitors-profile/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P7.1 none. Plan artifacts from `AVAILABLE_DOCS`: `research.md`. `data-model.md` is omitted (no entities). `contracts/` is omitted (Freezes: None). `quickstart.md` is written in Documentation after the local harness passes. `research.md` is already written; this phase does not edit it.

**Organization**: P8.1 is User Story 1, User Story 2, and User Story 3 (`[US1]`, `[US2]`, `[US3]`), size M (rule S3). Branch `ai/096-abo-p8-1-staging-environment-external-monitors-profile`. E2E ids stay `E2E-P8.1-01` through `E2E-P8.1-04`. Tests are one task per Test plan id, plus `run-checklists.mjs`, which **Test Layout** names as the checklist harness. Titles and checklist headings start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase. No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 15. Size M is 20–32 (rule S3). Plan **Files** is 14 paths once `research.md` is excluded, including `quickstart.md`. Those 14 are tasks. The verification task edits nothing and is the harness check the tasks phase requires. The count is not padded. `npm test` in `e2e/fullstack` is not a task. This workflow does not boot wrangler and does not deploy to Cloudflare, Supabase, or Paymob. The two local Node commands in Verification do not call a live account.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Harness H-STG**: `e2e/fullstack/staging/`. Checklist runner `e2e/fullstack/staging/run-checklists.mjs`. Node test `e2e/fullstack/staging/p8-1-04.test.mjs` (`node:test`)
- **Ops scripts**: `ops/staging/heartbeat-monitor.mjs`, `ops/staging/audit-watcher.mjs`, `ops/staging/nfr-08.md`, `ops/staging/fixtures/`
- **Wrangler**: `[env.staging]` only in `ai-platform/wrangler.toml` and `abo/wrangler.toml`. Minute cron in `abo/src/worker.ts`
- **Harness commands** (this unit only; they do not boot a worker and they do not call a live account):
  - `node --test e2e/fullstack/staging/p8-1-04.test.mjs`
  - `node e2e/fullstack/staging/run-checklists.mjs`
- **Unchanged by this unit**: `e2e/fullstack/package.json`, `backend/supabase/migrations/`, top-level and non-staging wrangler blocks, secret values, `research.md`
- **Spec Kit artifacts**: `specs/096-abo-p8-1-staging-environment-external-monitors-profile/`

---

## 3. Tests

**Purpose**: Sequencing step 1. One failing item per E2E id, plus the checklist runner **Test Layout** names. Checklist items and the Node test are written so they fail before the wrangler flags, the minute `pingHeartbeat` call, the ops scripts, the fixtures, and `nfr-08.md` exist. Do not run them in this phase. Do not boot wrangler. Do not deploy. Do not call Cloudflare, Supabase, or Paymob. Do not run `npm test` in `e2e/fullstack`.

### 3.1 User Story 1 - Staging profile runs a monthly test purchase (Priority: P1) — tests

**Independent Test**: E2E-P8.1-03 in H-STG.

- [X] T001 [US1] Add the failing checklist `E2E-P8.1-03` in `e2e/fullstack/staging/p8-1-03.checklist.md` — red checklist, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, E2E-P8.1-03. Depends on nothing. Heading prefix `E2E-P8.1-03`. One item. It names the account record: a separate Cloudflare account and Supabase project, the Paymob test integration, test cards and the callback URL configured outside git, the Email Routing destination, the R2 bucket lock, the Access application on the ops host, and deploy of the existing `backend/supabase/migrations/` set. It names the three console-published offers: Monthly (1 month, runs 30 minutes, grace about 7 minutes, 20 credits), Quarterly (3 months, runs 90 minutes, grace about 7 minutes, 60 credits), and Annual (12 months, runs 6 hours, grace about 7 minutes, 240 credits). The purchase chain is cited and not executed: `POST /v1/checkouts` → `handleBillingV1` → `handlePostCheckout`, with a Paymob test card. AI active is `public.get_ai_status` in about 1 minute. The term ends after 30 minutes. Grace lasts about 7 minutes. Term and grace follow platform `[env.staging]` `DURATION_SCALE = "staging"` (1 month = 30 minutes, 1 day = 1 minute). The item names `ops/staging/nfr-08.md`. It states the hosted R-4 command is not executed here while the pull stays `30 seconds`. It adds no miss window, no HTTP status, and no alert body field. Do not create the runner, `nfr-08.md`, or the wrangler edits in this task. Do not run the checklist. Do not deploy. Do not call a live account.

**Checkpoint**: E2E-P8.1-03 is on disk and was not executed.

### 3.2 User Story 2 - Staging hostnames stay closed (Priority: P2) — tests

**Independent Test**: E2E-P8.1-04 in H-STG.

- [X] T002 [US2] Add the failing test `E2E-P8.1-04` in `e2e/fullstack/staging/p8-1-04.test.mjs` — red test, FR-002, FR-010, E2E-P8.1-04. Depends on nothing. Title `E2E-P8.1-04` (`node:test`). Parse the `[env.staging]` block in `ai-platform/wrangler.toml` and in `abo/wrangler.toml`, not the top-level block. Both staging blocks must set `workers_dev = false` and `preview_urls = false`. Read the ops path as source: `abo/src/worker.ts` `fetch` → `handleOps` → `dispatchOps` → `verifyOpsAccess`. Do not open a live hostname. Do not set the flags in this task. Do not run `node --test`. Do not boot wrangler. Do not deploy.

**Checkpoint**: E2E-P8.1-04 is on disk and was not executed.

### 3.3 User Story 3 - External monitor and audit watcher alert (Priority: P3) — tests

**Independent Test**: E2E-P8.1-01 and E2E-P8.1-02 in H-STG. Earlier suites stay green (rule S2).

- [X] T003 [US3] Add the failing checklist `E2E-P8.1-01` in `e2e/fullstack/staging/p8-1-01.checklist.md` — red checklist, FR-008, E2E-P8.1-01. Depends on nothing. Heading prefix `E2E-P8.1-01`. One item. Expected pings to `HEARTBEAT_URL`: ABO minute (`abo/src/worker.ts` `scheduled()` `* * * * *` → `pingHeartbeat`), platform 5-minute (`ai-platform/src/worker.ts` `scheduled()` `*/5 * * * *` → `runFiveMinuteCron` → `pingPlatformHeartbeat`), and ABO daily digest (`scheduled()` `0 6 * * *` → `pingHeartbeat`). The item requires the minute branch to call `pingHeartbeat`. ABO minute ping absent → stdout is `AL-21` on the monitor's own channel. Alert output is the code `AL-21` only. No miss window, no HTTP status, and no alert body field. Do not create `ops/staging/heartbeat-monitor.mjs`, `ops/staging/fixtures/abo-cron-disabled.json`, or the minute-branch edit in this task. Do not run the checklist. Do not boot wrangler. Do not deploy.

- [X] T004 [US3] Add the failing checklist `E2E-P8.1-02` in `e2e/fullstack/staging/p8-1-02.checklist.md` — red checklist, FR-009, E2E-P8.1-02. Depends on T003. Heading prefix `E2E-P8.1-02`. One item. The job is hourly. The token is read-only and is not stored in git. Fixture mode does not read the token. Classes `deploy` and `secret` → stdout is `AL-21`, repeated per event. The four entry classes the watcher must classify are `deploy`, `secret`, `d1_export`, and `access_policy`. A staging deploy uses class `deploy`. No miss window, no HTTP status, no alert body field, no token field, and no API event name. Do not create `ops/staging/audit-watcher.mjs` or `ops/staging/fixtures/deploy-and-secret.json` in this task. Do not run the checklist. Do not call a provider API. Do not deploy.

**Checkpoint**: E2E-P8.1-01 and E2E-P8.1-02 are on disk and were not executed.

### 3.4 User Story 3 - External monitor and audit watcher alert (Priority: P3) — checklist runner

**Independent Test**: E2E-P8.1-01 and E2E-P8.1-02 in H-STG. Earlier suites stay green (rule S2).

- [X] T005 [US3] Add the failing runner in `e2e/fullstack/staging/run-checklists.mjs` — red runner, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, E2E-P8.1-01, E2E-P8.1-02, E2E-P8.1-03. Depends on T001, T003, and T004. Run the three checklist items against the ops scripts and fixtures: `p8-1-01.checklist.md` via `ops/staging/heartbeat-monitor.mjs` on `ops/staging/fixtures/abo-cron-disabled.json`; `p8-1-02.checklist.md` via `ops/staging/audit-watcher.mjs` on `ops/staging/fixtures/deploy-and-secret.json`; `p8-1-03.checklist.md` against the account text, platform `[env.staging]` `DURATION_SCALE = "staging"`, the minute-branch `pingHeartbeat` requirement recorded on the 01 item, and `ops/staging/nfr-08.md`. The runner fails while those scripts, fixtures, flags, the minute ping, or `nfr-08.md` are absent. It adds no miss window, no HTTP status, and no alert body field. It does not shell out to wrangler, Cloudflare, Supabase, or Paymob. Do not create the ops files in this task. Do not run the runner. Do not run `npm test` in `e2e/fullstack`.

**Checkpoint**: E2E-P8.1-01, E2E-P8.1-02, and E2E-P8.1-03 have a runner on disk. It was not executed.

---

## 4. Implementation

**Purpose**: Sequencing step 2. Wrangler flags, the minute `pingHeartbeat` call, the ops scripts, the fixtures, and `nfr-08.md`. Each file is the one **Files** names. Do not run the harness in this phase. Do not boot wrangler. Do not deploy. Do not commit a secret value. Do not add a migration, a binding, or a second config file. Do not edit `e2e/fullstack/package.json`.

### 4.1 User Story 2 - Staging hostnames stay closed (Priority: P2) — staging flags

**Independent Test**: E2E-P8.1-04 in H-STG.

- [X] T006 [US2] Set the staging flags in `ai-platform/wrangler.toml` — `[env.staging]` only, FR-002, FR-010, E2E-P8.1-04. Depends on T002 and T005. On that block set `workers_dev = false` and `preview_urls = false`. Keep `DURATION_SCALE = "staging"` and `HEARTBEAT_URL`. Do not edit the top-level block or any other env. Do not add a secret. Do not run the Node test. Do not deploy.

- [X] T007 [US2] Set the staging flags in `abo/wrangler.toml` — `[env.staging]` only, FR-002, FR-010, E2E-P8.1-04. Depends on T006. On that block set `workers_dev = false` and `preview_urls = false`. Keep `HEARTBEAT_URL`. Do not edit the top-level block or any other env. Do not add a secret. Do not run the Node test. Do not deploy.

**Checkpoint**: E2E-P8.1-04's two `[env.staging]` blocks carry `workers_dev = false` and `preview_urls = false`. The test was not executed.

### 4.2 User Story 3 - External monitor and audit watcher alert (Priority: P3) — monitor and watcher

**Independent Test**: E2E-P8.1-01 and E2E-P8.1-02 in H-STG. Earlier suites stay green (rule S2).

- [X] T008 [US3] Call `pingHeartbeat` from the minute cron in `abo/src/worker.ts` — minute branch, FR-008, E2E-P8.1-01. Depends on T003 and T007. The `* * * * *` branch calls `pingHeartbeat`. The `0 6 * * *` branch keeps its existing `pingHeartbeat` call. Do not add a binding. Do not run the runner. Do not boot wrangler.

- [X] T009 [US3] Add `ops/staging/heartbeat-monitor.mjs` — external monitor, FR-008, E2E-P8.1-01. Depends on T008. Configured as code, outside Cloudflare and Supabase. Expected pings: ABO minute, platform 5-minute, and ABO daily digest, named at `HEARTBEAT_URL`. A missing ping prints `AL-21` on stdout and nothing else. No vendor SDK. No miss window, no HTTP status, and no alert body field. Do not run the script against a live URL. Do not deploy.

- [X] T010 [US3] Add `ops/staging/fixtures/abo-cron-disabled.json` — ABO minute ping absent, FR-008, E2E-P8.1-01. Depends on T009. The fixture records the platform 5-minute ping and the ABO daily digest ping, and omits the ABO minute ping. No secret value. Do not run the monitor.

- [X] T011 [US3] Add `ops/staging/audit-watcher.mjs` — hourly watcher, FR-009, E2E-P8.1-02. Depends on T010. Configured as code on the same external scheduler. It does not call a provider API. It classifies checklist-supplied entries: `deploy` (production deploy; a staging deploy uses this class), `secret` (secret change), `d1_export` (D1 export), `access_policy` (Access policy edit). Any of the four prints `AL-21` on stdout, repeated per event. Fixture mode does not read the token. The token is an environment value, not a git file. No vendor SDK, no token field, and no API event name. Do not deploy.

- [X] T012 [US3] Add `ops/staging/fixtures/deploy-and-secret.json` — classes `deploy` and `secret`, FR-009, E2E-P8.1-02. Depends on T011. The fixture supplies those two classes and no token. No secret value. Do not run the watcher.

**Checkpoint**: E2E-P8.1-01 reaches `heartbeat-monitor.mjs` and the minute `pingHeartbeat` call. E2E-P8.1-02 reaches `audit-watcher.mjs`. Neither script was executed.

### 4.3 User Story 1 - Staging profile runs a monthly test purchase (Priority: P1) — NFR-08 record

**Independent Test**: E2E-P8.1-03 in H-STG.

- [X] T013 [US1] Add `ops/staging/nfr-08.md` — NFR-08 record, FR-007, E2E-P8.1-03. Depends on T001 and T012. Copy the steady-load figures: about 1,440 ABO cron runs, 288 platform cron runs, 2,880 backend pulls, about 2,250 reversal inquiries a day at the stated o/L/P example, and about two DO row writes per AI request. State that this load stays inside the included allowances of the Cloudflare Workers Paid plan and the Supabase project. Do not call a billing API. Do not deploy.

**Checkpoint**: E2E-P8.1-03 names `ops/staging/nfr-08.md`. The checklist runner was not executed.

---

## 5. Verification

**Purpose**: Sequencing step 3, before `quickstart.md`. The unit harness from **Test Layout** passes. The commands do not boot a worker and do not call a live account.

### 5.1 User Story 3 - External monitor and audit watcher alert (Priority: P3) — unit harness

**Independent Test**: E2E-P8.1-01 and E2E-P8.1-02 in H-STG. Earlier suites stay green (rule S2).

- [ ] T014 [US3] Run this unit's harness until both commands pass — local Node only, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, E2E-P8.1-01, E2E-P8.1-02, E2E-P8.1-03, E2E-P8.1-04. Depends on T002, T005, T007, and T013. Run `node --test e2e/fullstack/staging/p8-1-04.test.mjs` and `node e2e/fullstack/staging/run-checklists.mjs` until both pass. This task creates no file and edits no file. Do not run `npm test` in `e2e/fullstack`. Do not boot wrangler. Do not run `wrangler dev` or `startWorker`. Do not deploy to Cloudflare, Supabase, or Paymob. Do not open a live hostname. Do not run earlier suites. A missing live staging account is not a failure of this task.

**Checkpoint**: E2E-P8.1-01, E2E-P8.1-02, E2E-P8.1-03, and E2E-P8.1-04 passed through the two local commands. No live account was required.

---

## 6. Documentation

**Purpose**: After the harness is green. `quickstart.md` from the plan outline. Plan-phase `research.md` stays as written. `data-model.md` and `contracts/` stay omitted.

### 6.1 User Story 3 - External monitor and audit watcher alert (Priority: P3) — quickstart

**Independent Test**: E2E-P8.1-01 and E2E-P8.1-02 in H-STG. Earlier suites stay green (rule S2).

- [ ] T015 [US3] Write `specs/096-abo-p8-1-staging-environment-external-monitors-profile/quickstart.md` — unit quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, E2E-P8.1-01, E2E-P8.1-02, E2E-P8.1-03, E2E-P8.1-04. Depends on T014. Fill only these sections: what was implemented and the files added and modified; the harness commands for this unit's tests only (`node --test e2e/fullstack/staging/p8-1-04.test.mjs` and `node e2e/fullstack/staging/run-checklists.mjs`); the entry point → module chain per E2E id. E2E-P8.1-01: `ops/staging/heartbeat-monitor.mjs` on `ops/staging/fixtures/abo-cron-disabled.json`, and the minute `pingHeartbeat` call. E2E-P8.1-02: `ops/staging/audit-watcher.mjs` on `ops/staging/fixtures/deploy-and-secret.json`. E2E-P8.1-03: the checklist text, `public.get_ai_status`, platform `[env.staging]` `DURATION_SCALE = "staging"`, and `ops/staging/nfr-08.md`, not a live purchase. E2E-P8.1-04: both `[env.staging]` blocks and `fetch` → `handleOps` → `dispatchOps` → `verifyOpsAccess`. The scripted checklist items are the manual steps the runner already executes. State that the live H-STG command against a live account is not executed in this workflow. Do not list earlier-unit files, combined counts, or full-suite commands. Do not run `npm test` in `e2e/fullstack`. Do not boot wrangler. Do not deploy.

**Checkpoint**: `quickstart.md` names the four E2E ids, the two unit commands, and the entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests**: No earlier phase. User Story 1 checklist, User Story 2 Node test, and User Story 3 checklists, then the checklist runner.
- **Implementation**: After the runner and the test files are on disk. Staging flags, then the minute `pingHeartbeat` call, the monitor and its fixture, the watcher and its fixture, then the NFR-08 record.
- **Verification**: After every file those two commands read.
- **Documentation**: After verification passes. `quickstart.md` only.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: The E2E-P8.1-03 checklist starts immediately. `ops/staging/nfr-08.md` follows the watcher fixture. The purchase is not executed live.
- **User Story 2 (P2)**: The E2E-P8.1-04 test starts immediately. The two `[env.staging]` flag edits follow that test and the runner.
- **User Story 3 (P3)**: The E2E-P8.1-01 and E2E-P8.1-02 checklists start immediately. The runner follows those checklists and the User Story 1 checklist. The minute ping, monitor, watcher, and fixtures follow the staging flags.

### 7.3 Within Each Phase

- T001 creates `e2e/fullstack/staging/p8-1-03.checklist.md`. T002 creates `e2e/fullstack/staging/p8-1-04.test.mjs`. T003 creates `e2e/fullstack/staging/p8-1-01.checklist.md`. T004 creates `e2e/fullstack/staging/p8-1-02.checklist.md`. T005 creates `e2e/fullstack/staging/run-checklists.mjs` after T001, T003, and T004.
- T006 edits `[env.staging]` in `ai-platform/wrangler.toml`. T007 edits `[env.staging]` in `abo/wrangler.toml`. T008 edits the `* * * * *` branch in `abo/src/worker.ts`. T009 creates `ops/staging/heartbeat-monitor.mjs`. T010 creates `ops/staging/fixtures/abo-cron-disabled.json`. T011 creates `ops/staging/audit-watcher.mjs`. T012 creates `ops/staging/fixtures/deploy-and-secret.json`. T013 creates `ops/staging/nfr-08.md`.
- T014 runs the two local Node commands and does not edit a file. It waits until T002, T005, T007, and T013 are done.
- T015 writes only `specs/096-abo-p8-1-staging-environment-external-monitors-profile/quickstart.md`.

---

## 8. Implementation Waves

Scheduling lives only here. One subphase is one bullet. Tasks inside a subphase run in order.

### 8.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Staging profile runs a monthly test purchase (Priority: P1) — tests` — paths: `e2e/fullstack/staging/p8-1-03.checklist.md`
- T002 [US2] — subphase: `### 3.2 User Story 2 - Staging hostnames stay closed (Priority: P2) — tests` — paths: `e2e/fullstack/staging/p8-1-04.test.mjs`
- T003–T004 [US3] — subphase: `### 3.3 User Story 3 - External monitor and audit watcher alert (Priority: P3) — tests` — paths: `e2e/fullstack/staging/p8-1-01.checklist.md`, `e2e/fullstack/staging/p8-1-02.checklist.md`

### 8.2 Wave 2

- T005 [US3] — subphase: `### 3.4 User Story 3 - External monitor and audit watcher alert (Priority: P3) — checklist runner` — paths: `e2e/fullstack/staging/run-checklists.mjs`

### 8.3 Wave 3

- T006–T007 [US2] — subphase: `### 4.1 User Story 2 - Staging hostnames stay closed (Priority: P2) — staging flags` — paths: `ai-platform/wrangler.toml`, `abo/wrangler.toml`

### 8.4 Wave 4

- T008–T012 [US3] — subphase: `### 4.2 User Story 3 - External monitor and audit watcher alert (Priority: P3) — monitor and watcher` — paths: `abo/src/worker.ts`, `ops/staging/heartbeat-monitor.mjs`, `ops/staging/fixtures/abo-cron-disabled.json`, `ops/staging/audit-watcher.mjs`, `ops/staging/fixtures/deploy-and-secret.json`

### 8.5 Wave 5

- T013 [US1] — subphase: `### 4.3 User Story 1 - Staging profile runs a monthly test purchase (Priority: P1) — NFR-08 record` — paths: `ops/staging/nfr-08.md`

### 8.6 Wave 6

- T014 [US3] — subphase: `### 5.1 User Story 3 - External monitor and audit watcher alert (Priority: P3) — unit harness` — paths: `e2e/fullstack/staging/p8-1-04.test.mjs`, `e2e/fullstack/staging/run-checklists.mjs`

### 8.7 Wave 7

- T015 [US3] — subphase: `### 6.1 User Story 3 - External monitor and audit watcher alert (Priority: P3) — quickstart` — paths: `specs/096-abo-p8-1-staging-environment-external-monitors-profile/quickstart.md`
