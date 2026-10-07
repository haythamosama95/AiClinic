# Tasks: Coverage feed puller, projection and status refresh

**Input**: Design documents from `specs/088-abo-p5-2-coverage-feed-puller-status-projection/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P3.9 (`GET /v1/feed/coverage`, `feedConsumerHealth`) and P5.1 (`auth_internal.issue_feed_token()`, `ai.platform_base_url`, `ai.abo_base_url`, `ai.contract_versions`, `public.current_org_id()`, `public.current_membership_role()`). Plan artifacts from `AVAILABLE_DOCS`: `research.md`, `data-model.md`, `contracts/`. `research.md` is not a task: the local R-4 spike already passed, so the pull interval stays 30 seconds. `data-model.md` and `contracts/` are not tasks: plan already wrote them. `quickstart.md` is written in Documentation after this half's harness is green.

**Organization**: P5.2a is User Story 1 and User Story 4 (`[US1]`, `[US4]`), size M (rule S3). E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11 stay `E2E-P5.2-*` and belong to P5.2b (spec 088b). They are not tasks on this branch. P5.2b also owns grace, lapse, notices, `days_left`, the `reason` read mapping, and `get_ai_billing_status`. This half owns the pull, the projection (including `reason` on upsert), `status_refresh`, `request_ai_status_refresh`, available/active and `stale` on `get_ai_status`, the availability drop, cursor rebuild, and the recorded R-4 outcome. Tests are one task per E2E id of this half, written to fail before the behavior exists. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 32. Size M is 20–32 (rule S3). Plan sequencing steps 1, 2, 5, 6, 7, 8, 10, 12–22, 25, 26, 27, 28, 31, 32, 33, 34, and 36 are tasks here. Steps 3, 4, 9, 11, 23, 24, 29, 30, 35, and 37 are P5.2b. Step 14 is two tasks, one per catalog file. Step 17 is three tasks, one per stage-06 file. Step 22 is only available/active and `stale`. Step 38's harness run and `quickstart.md` are two tasks, scoped to this half's seven E2E ids. The count is not padded. `npm test` in `e2e/fullstack` and any command other than the unit command in §3 and §5.1 are not the harness.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US4`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`, `backend/tests/catalog/` — the Files paths in `plan.md` that this half edits
- **Full-stack harness**: `e2e/fullstack/test/p5-2.test.mjs` — this file does not import `e2e/fullstack/test/p5-1.test.mjs`. `e2e/fullstack/package.json` is not edited
- **CI**: `.github/workflows/ci.yml` — job `fullstack` keeps `npm test` on the P5.1 file, then runs this unit's command
- **AI Platform**: `ai-platform/` — consumed and not modified
- **ABO**: `abo/src/` — consumed and not modified
- **Shared package**: `packages/vendor-contracts/` — consumed and not modified. This half does not read `subscriptionRef`
- **Spec Kit artifacts**: `specs/088-abo-p5-2-coverage-feed-puller-status-projection/`
- Leave the availability migrations named in 04 §3.1 unedited, including `backend/supabase/migrations/20260821120000_fix_get_ai_availability_security_definer.sql`, `backend/supabase/migrations/20260905120100_set_ai_availability_rpc.sql`, and `backend/supabase/migrations/20260905120400_fix_set_ai_availability_created_by.sql`

---

## 3. Tests (H-FS)

**Purpose**: Sequencing steps 1, 2, 5, 6, 7, 8, and 10. One failing test per P5.2a E2E id. Titles are prefixed with the E2E id. Leave `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` uncreated. Do not add E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, or E2E-P5.2-11.

```bash
node --import tsx --test test/p5-2.test.mjs
```

Run that command from `e2e/fullstack/`.

### 3.1 User Story 1 - Coverage pull and projection (Priority: P1) — tests (part 1)

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T001 [US1] Add the failing test `E2E-P5.2-01` in `e2e/fullstack/test/p5-2.test.mjs` — red test, FR-001, FR-006, FR-014, FR-016, E2E-P5.2-01. Depends on nothing. Create the file. Do not import `e2e/fullstack/test/p5-1.test.mjs` and do not edit `e2e/fullstack/package.json`. Start the stack that file starts: local Supabase, platform `startWorker` on port 8787, the harness worker with the `PLATFORM` binding, ABO `wrangler dev` on port 8788, and the Paymob stub on port 8789. Sign in an administrator with supabase-js. Owner SQL uses `psql` and `DB_URL`. Platform D1 writes use the local database the H-FS platform already persists. Title `E2E-P5.2-01 Grant applied on the platform reaches get_ai_status available and active`. A `grant_applied` event is on the live feed. `cron.job` for `ai_coverage_feed_pull` has schedule `30 seconds`. The runner calls `auth_internal.pull_coverage_feed` so the two-phase pull requests the page and applies the response, without sleeping 60 seconds. `get_ai_status(1)` is available and `active` and `contract_version` is 1. The accepted page echoed the sent feed version on `Aip-Contract-Version` and `contract_version`. The unit command fails because the pull and `get_ai_status` are absent.

**Checkpoint**: E2E-P5.2-01 exists and fails.

### 3.2 User Story 4 - Administrator status refresh (Priority: P4) — tests

**Independent Test**: E2E-P5.2-02 in harness H-FS. Every earlier suite stays green (rule S2).

- [X] T002 [US4] Add the failing test `E2E-P5.2-02` in `e2e/fullstack/test/p5-2.test.mjs` — red test, FR-005, FR-016, E2E-P5.2-02. Depends on T001 (same file). Title `E2E-P5.2-02 Refresh starts a pull and a second call within 10 seconds is RATE_LIMITED`. An administrator `request_ai_status_refresh(1)` returns `contract_version` 1 and `data.requested_at`, and a pull was requested. An immediate second call returns `RATE_LIMITED` and leaves `requested_at` unchanged. After owner SQL sets `requested_at` to 10 seconds ago, another call is accepted. `request_ai_status_refresh()` and `request_ai_status_refresh(2)`, including with no session, return `CONTRACT_VERSION_UNSUPPORTED` and do not write `status_refresh` or request a pull. The unit command fails because the refresh RPC is absent. E2E-P5.2-01 still fails.

**Checkpoint**: E2E-P5.2-02 exists and fails. E2E-P5.2-01 still fails.

### 3.3 User Story 1 - Coverage pull and projection (Priority: P1) — tests (part 2)

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T003 [US1] Add the failing test `E2E-P5.2-05` in `e2e/fullstack/test/p5-2.test.mjs` — red test, FR-003, E2E-P5.2-05. Depends on T002 (same file). Title `E2E-P5.2-05 Epoch 2 sequence 1 replaces epoch 1 sequence 9`. Epoch and sequence fixtures are rows in platform `coverage_event`. The test does not insert `ai_internal.clinic_ai_coverage`. The pull applies the newer pair. An older pair leaves the stored row unchanged. The unit command fails because the ordering upsert is absent. E2E-P5.2-01 and E2E-P5.2-02 still fail.

- [X] T004 [US1] Add the failing test `E2E-P5.2-06` in `e2e/fullstack/test/p5-2.test.mjs` — red test, FR-002, FR-014, E2E-P5.2-06. Depends on T003 (same file). Title `E2E-P5.2-06 Unsupported feed version keeps the cursor and does not write the projection`. For that pull only, owner SQL sets `platformFeed.current` to a version the running platform rejects, then the test restores it. The answer is the real `GET /v1/feed/coverage`. `consecutive_failures` increases. A stale read sets `feed_state.last_success_at` older than 2 minutes, and `get_ai_status` is stale. The projection row is unchanged. The unit command fails because the version refusal does not yet keep the cursor. E2E-P5.2-01, E2E-P5.2-02, and E2E-P5.2-05 still fail.

- [X] T005 [US1] Add the failing test `E2E-P5.2-07` in `e2e/fullstack/test/p5-2.test.mjs` — red test, FR-004, FR-015, E2E-P5.2-07. Depends on T004 (same file). Title `E2E-P5.2-07 Disabled pull is stale and feedConsumerHealth shows the lag`. `cron.job.active` is false. `last_success_at` is older than 2 minutes. `feed_consumer.last_pull_at` is 5 minutes back. `get_ai_status` is stale. `feedConsumerHealth` on the harness `PLATFORM` binding returns that `last_pull_at`. The unit command fails because the stale flag and the health lag are not both asserted against the live stack. E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, and E2E-P5.2-06 still fail.

- [X] T006 [US1] Add the failing test `E2E-P5.2-08` in `e2e/fullstack/test/p5-2.test.mjs` — red test, FR-012, E2E-P5.2-08. Depends on T005 (same file). Title `E2E-P5.2-08 Cursor reset to 0 reproduces the projection`. Owner SQL sets `feed_state.cursor` to 0. The same pull leaves the projection identical. The test does not insert `ai_internal.clinic_ai_coverage`. The unit command fails because cursor rebuild is absent. E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, and E2E-P5.2-07 still fail.

- [X] T007 [US1] Add the failing test `E2E-P5.2-10` in `e2e/fullstack/test/p5-2.test.mjs` — red test, FR-015, E2E-P5.2-10. Depends on T006 (same file). Title `E2E-P5.2-10 Supabase stopped during a payment still provisions and status catches up`. With Supabase up, an administrator opens a checkout through `public.issue_billing_token`. Supabase is stopped. The Paymob stub payment is posted to ABO `POST /notify/paymob` and the platform grant completes. Supabase is started. The pull runs. `get_ai_status` is available and `active`. The unit command fails because catch-up after restart is absent. E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, and E2E-P5.2-08 still fail.

**Checkpoint**: E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 exist and fail. E2E-P5.2-01 and E2E-P5.2-02 still fail.

---

## 4. Implementation

**Purpose**: Sequencing steps 12–22, 25, 26, 27, 28, 31, 32, 33, 34, and 36. Starts after T001–T007 exist and those E2E tests fail. Within a subphase the tasks run in id order. T008, T009, and T017–T022 edit only `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`. Leave `get_ai_billing_status`, notices, `days_left`, grace, lapse, and the `reason` read mapping unbuilt.

### 4.1 User Story 1 - Coverage pull and projection (Priority: P1) — projection and feed state

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T008 [US1] Add the projection tables in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` — produces `pg_cron`, `pg_net`, `ai_internal.clinic_ai_coverage`, `ai_internal.feed_state`, and `ai_internal.status_refresh`, FR-003, FR-004, FR-005, E2E-P5.2-01, E2E-P5.2-02. Depends on T007. Create the file. `CREATE EXTENSION IF NOT EXISTS pg_cron` and `CREATE EXTENSION IF NOT EXISTS pg_net`. `clinic_ai_coverage` columns are `organization_id`, `installation_id`, `binding_epoch`, `clinic_seq`, `state`, `term_ref`, `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `band`, `queued_count`, `held_count`, `suspended`, `event_at`, `applied_at`, and `reason`. `reason` is null when the applied snapshot `state` is `active` or `grace`; otherwise it stores that snapshot's `reason`. The row has no prices and no provider data, and it does not store snapshot `contract_version`. `feed_state` is a singleton: `cursor`, `pending_request_id`, `pending_since`, `last_success_at`, `consecutive_failures`. Insert that singleton. `status_refresh` is `organization_id` primary key and `requested_at timestamptz`. Deny-all RLS on these tables. No clinic grants. Leave the pull function, the cron job, and the RPCs for later tasks in this file.

**Checkpoint**: The three tables exist, the `feed_state` singleton is inserted, and clinic roles have no grants. E2E-P5.2-01 and E2E-P5.2-02 still fail.

- [X] T009 [US1] Drop the availability flag in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` — produces the removal of clinic-written availability, FR-011, E2E-P5.2-01. Depends on T008 (same file). Drop `get_ai_availability` and `set_ai_availability` in `public` and `auth_internal`, and delete the `ai.availability` settings row. Do not edit the availability migrations named in §2.

**Checkpoint**: `get_ai_availability`, `set_ai_availability`, and `ai.availability` are gone. E2E-P5.2-01 still fails.

### 4.2 User Story 1 - Coverage pull and projection (Priority: P1) — harness catalog

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T010 [US1] Stop requiring `ai.availability` in `backend/tests/catalog/harness.sql` — produces a catalog harness that matches the dropped setting, FR-011, E2E-P5.2-01. Depends on T009. Do not edit `backend/tests/catalog/harness-smoke.sql` in this task.

**Checkpoint**: `harness.sql` does not require `ai.availability`. E2E-P5.2-01 still fails.

### 4.3 User Story 1 - Coverage pull and projection (Priority: P1) — harness smoke catalog

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T011 [US1] Stop requiring `ai.availability` in `backend/tests/catalog/harness-smoke.sql` — produces a catalog smoke harness that matches the dropped setting, FR-011, E2E-P5.2-01. Depends on T009. Do not edit `backend/tests/catalog/harness.sql` in this task.

**Checkpoint**: `harness-smoke.sql` does not require `ai.availability`. E2E-P5.2-01 still fails.

### 4.4 User Story 1 - Coverage pull and projection (Priority: P1) — stage-02 enroll catalog

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T012 [US1] Expect the availability flag to be absent in `backend/tests/catalog/stage-02-availability-and-enroll.sql` — produces a catalog that asserts the drop, FR-011, E2E-P5.2-01. Depends on T010 and T011. Assert `get_ai_availability` and `ai.availability` are absent. Leave `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` for T013.

**Checkpoint**: The stage-02 enroll catalog expects `get_ai_availability` and `ai.availability` to be absent. E2E-P5.2-01 still fails.

### 4.5 User Story 1 - Coverage pull and projection (Priority: P1) — stage-02 revoke catalog

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T013 [US1] Expect the availability RPCs to be absent in `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` — produces a catalog that asserts the drop, FR-011, E2E-P5.2-01. Depends on T012. Assert `set_ai_availability` and `get_ai_availability` are absent.

**Checkpoint**: The stage-02 revoke catalog expects `set_ai_availability` and `get_ai_availability` to be absent. E2E-P5.2-01 still fails.

### 4.6 User Story 1 - Coverage pull and projection (Priority: P1) — stage-06 verify catalog

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T014 [US1] Stop reading `ai.availability` in `backend/tests/catalog/stage-06-verify-and-handoff.sql` — produces a catalog that survives the drop, FR-011, E2E-P5.2-01. Depends on T013. Leave the other two stage-06 files for T015 and T016.

**Checkpoint**: `stage-06-verify-and-handoff.sql` does not read `ai.availability`. E2E-P5.2-01 still fails.

### 4.7 User Story 1 - Coverage pull and projection (Priority: P1) — stage-06 happy-path catalog

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T015 [US1] Stop reading `ai.availability` in `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql` — produces a catalog that survives the drop, FR-011, E2E-P5.2-01. Depends on T013. Leave `stage-06-verify-and-handoff.sql` and `stage-06-issuer-guards.sql` for T014 and T016.

**Checkpoint**: `stage-06-happy-path-and-lifecycle.sql` does not read `ai.availability`. E2E-P5.2-01 still fails.

### 4.8 User Story 1 - Coverage pull and projection (Priority: P1) — stage-06 issuer catalog

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [X] T016 [US1] Stop reading `ai.availability` in `backend/tests/catalog/stage-06-issuer-guards.sql` — produces a catalog that survives the drop, FR-011, E2E-P5.2-01. Depends on T013. Leave the other two stage-06 files for T014 and T015.

**Checkpoint**: `stage-06-issuer-guards.sql` does not read `ai.availability`. E2E-P5.2-01 still fails.

### 4.9 User Story 1 - Coverage pull and projection (Priority: P1) — pull, projection, and minimal status

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [ ] T017 [US1] Add the feed request in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` — produces `auth_internal.pull_coverage_feed` issuing the next page, FR-001, FR-014, E2E-P5.2-01. Depends on T014, T015, and T016 (same migration file as T009). `auth_internal.pull_coverage_feed()` returns `void`. `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, and `service_role`. No public wrapper. The bearer token is `auth_internal.issue_feed_token()`. Rewrite a loopback host in `ai.platform_base_url` to `host.docker.internal`. `net.http_get` uses `ai.platform_base_url` plus `/v1/feed/coverage?after=<cursor>&limit=200`. Header `Aip-Contract-Version` is `platformFeed.current` from `ai.contract_versions`. Store the returned request id and `pending_since = now()`. Omit the timeout argument. Leave response checks, the ordering upsert, and the cron job for later tasks.

**Checkpoint**: `pull_coverage_feed` can request a page and store the pending id. Clinic roles cannot execute it. E2E-P5.2-01 still fails.

- [ ] T018 [US1] Add feed response checks in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` — produces failure counting without a projection write, FR-002, FR-004, FR-014, FR-015, E2E-P5.2-06, E2E-P5.2-07. Depends on T017 (same file). If `pending_request_id` is set and `net._http_response` has no row and `pending_since` is within 5 minutes, return. If that pending response is missing after 5 minutes, or the response row's `created` is older than 5 minutes, clear the pending id, increment `consecutive_failures`, and do not read the body. When a response row exists, require HTTP 200, body `contract_version` equal to the version this pull sent, and header `Aip-Contract-Version` equal to that same version. Require body `after` equal to `cursor` and strictly ascending `feed_seq`, each greater than `after`. A 400 `contract_version_unsupported` body, a timeout, or any other failed check increments `consecutive_failures`, leaves `cursor` and the projection unchanged, and clears the pending id. `last_success_at` is not updated. Leave the success upsert for T019.

**Checkpoint**: A failed page keeps `cursor`, counts the failure, and does not write the projection. E2E-P5.2-06 still fails until `get_ai_status` reports `stale`.

- [ ] T019 [US1] Add the ordering upsert in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` — produces the projection replace rule, FR-003, FR-012, E2E-P5.2-05, E2E-P5.2-08. Depends on T018 (same file). On a successful page, upsert each event only when `(binding_epoch, clinic_seq)` is greater than the stored pair. Copy `reason` from the snapshot: null when that snapshot `state` is `active` or `grace`; otherwise the snapshot `reason`. Then set `cursor` to `next_after`, `last_success_at` to `now()`, `consecutive_failures` to 0, and clear the pending id. When `has_more` is true, the next cycle continues from the new cursor.

**Checkpoint**: A newer epoch and sequence replace the stored row, and an older pair does not. E2E-P5.2-05 still fails until the runner's pull is green.

- [ ] T020 [US1] Schedule the pull in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` — produces cron job `ai_coverage_feed_pull`, FR-001, FR-013, E2E-P5.2-01. Depends on T019 (same file). One job, schedule `30 seconds`, command `SELECT auth_internal.pull_coverage_feed()`. The local R-4 spike already passed, so this interval stays 30 seconds. Hosted confirmation stays with P8.1.

**Checkpoint**: `cron.job` schedules `ai_coverage_feed_pull` every 30 seconds. E2E-P5.2-01 still fails until `get_ai_status` returns available/active.

- [ ] T021 [US1] Add minimal `get_ai_status` in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` — produces available/active and `stale` for a current grant, FR-006, FR-007, FR-016, E2E-P5.2-01, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-10. Depends on T020 (same file). `public.get_ai_status(p_contract_version integer)` and `auth_internal.get_ai_status` are `SECURITY DEFINER`. Grant `public.get_ai_status` to `authenticated`. `REVOKE ALL` on the `auth_internal` body from `PUBLIC`, `anon`, `authenticated`, and `service_role`. The public body checks `p_contract_version` before `auth_internal`. A version outside the accepted range answers `CONTRACT_VERSION_UNSUPPORTED` with `contract_version` set to the accepted request version. A member call, keyed on `current_org_id()`, returns `rpc_result` with `contract_version` for the version the request used. When the stored projection `state` is `active`, `available` is true and `state` is `active`. `stale` is true when `feed_state.last_success_at` is more than 2 minutes old. Leave grace, lapse, notices, `days_left`, the `reason` read mapping, and `get_ai_billing_status` for P5.2b.

**Checkpoint**: `get_ai_status(1)` is available and `active` for a stored active grant, and `stale` follows `last_success_at`. E2E-P5.2-02 still fails.

### 4.10 User Story 4 - Administrator status refresh (Priority: P4) — request_ai_status_refresh

**Independent Test**: E2E-P5.2-02 in harness H-FS. Every earlier suite stays green (rule S2).

- [ ] T022 [US4] Add `request_ai_status_refresh` in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` — produces the administrator pull request and the per-tenant clock, FR-005, FR-016, E2E-P5.2-02. Depends on T021 (same file). `public.request_ai_status_refresh(p_contract_version integer)` is `SECURITY DEFINER`, granted to `authenticated`, and delegates to `auth_internal` after the version check. `REVOKE ALL` on the `auth_internal` body from `PUBLIC`, `anon`, `authenticated`, and `service_role`. A missing version, or a version outside the accepted range, returns `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any pull, and writes nothing. A caller whose membership role is not `administrator` returns `success = false`, `error_code = 'FORBIDDEN_ROLE'`, with no pull and no write to `status_refresh`. Both refusals set `contract_version` to the accepted request version. An administrator call is accepted when no `status_refresh` row exists for `current_org_id()` or `now() - requested_at >= interval '10 seconds'`. On accept, upsert `requested_at = now()`, return `rpc_result` success with `data = {requested_at}` set to that stored value and `contract_version` for the version the request used, and call `auth_internal.pull_coverage_feed()`. When the row exists and `now() - requested_at < interval '10 seconds'`, return `success = false`, `error_code = 'RATE_LIMITED'`, do not start a pull, and do not change `requested_at`.

**Checkpoint**: An accepted refresh stores `requested_at` and starts a pull. A second call inside 10 seconds is `RATE_LIMITED` and leaves the clock unchanged. E2E-P5.2-01 still fails until its runner assertions pass.

### 4.11 User Story 1 - Coverage pull and projection (Priority: P1) — CI command

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [ ] T023 [US1] Run this unit's command after `npm test` in `.github/workflows/ci.yml` — produces the fullstack job step for P5.2a, FR-001, FR-016, E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, E2E-P5.2-10. Depends on T022. In job `fullstack`, after `npm test` in `e2e/fullstack`, run `node --import tsx --test test/p5-2.test.mjs`. Leave `npm test` on the P5.1 file.

**Checkpoint**: Job `fullstack` runs the P5.1 `npm test` and then this unit's command. The seven E2E tests still fail until T024–T030.

### 4.12 User Story 1 - Coverage pull and projection (Priority: P1) — E2E-P5.2-01 passes

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [ ] T024 [US1] Make E2E-P5.2-01 pass in `e2e/fullstack/test/p5-2.test.mjs` — produces the grant reaching available/active, FR-001, FR-006, FR-014, FR-016, E2E-P5.2-01. Depends on T023 (same test file as T007). `cron.job` for `ai_coverage_feed_pull` has schedule `30 seconds`. The runner calls `auth_internal.pull_coverage_feed` through both phases without sleeping 60 seconds. `get_ai_status(1)` is available and `active` and `contract_version` is 1. The accepted page echoed the sent feed version on `Aip-Contract-Version` and `contract_version`. E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 still fail.

**Checkpoint**: E2E-P5.2-01 passes.

### 4.13 User Story 4 - Administrator status refresh (Priority: P4) — E2E-P5.2-02 passes

**Independent Test**: E2E-P5.2-02 in harness H-FS. Every earlier suite stays green (rule S2).

- [ ] T025 [US4] Make E2E-P5.2-02 pass in `e2e/fullstack/test/p5-2.test.mjs` — produces the immediate pull and the 10-second refusal, FR-005, FR-016, E2E-P5.2-02. Depends on T024 (same file). An administrator `request_ai_status_refresh(1)` returns `contract_version` 1 and `data.requested_at`, and a pull was requested. An immediate second call returns `RATE_LIMITED` and leaves `requested_at` unchanged. After owner SQL sets `requested_at` to 10 seconds ago, another call is accepted. `request_ai_status_refresh()` and `request_ai_status_refresh(2)`, including with no session, return `CONTRACT_VERSION_UNSUPPORTED` and do not write `status_refresh` or request a pull. E2E-P5.2-01 still passes. E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 still fail.

**Checkpoint**: E2E-P5.2-02 passes. E2E-P5.2-01 still passes.

### 4.14 User Story 1 - Coverage pull and projection (Priority: P1) — remaining projection scenarios pass

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [ ] T026 [US1] Make E2E-P5.2-05 pass in `e2e/fullstack/test/p5-2.test.mjs` — produces the epoch replace, FR-003, E2E-P5.2-05. Depends on T025 (same file). The pull applies epoch 2, `clinic_seq` 1 over epoch 1, `clinic_seq` 9. An older pair leaves the stored row unchanged. The test does not insert `ai_internal.clinic_ai_coverage`. E2E-P5.2-01 and E2E-P5.2-02 still pass. E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 still fail.

- [ ] T027 [US1] Make E2E-P5.2-06 pass in `e2e/fullstack/test/p5-2.test.mjs` — produces the unsupported-version refusal, FR-002, FR-014, E2E-P5.2-06. Depends on T026 (same file). `platformFeed.current` is set to a version the running platform rejects for that pull only, then restored. `consecutive_failures` increases. `feed_state.last_success_at` is older than 2 minutes and `get_ai_status` is stale. The projection row is unchanged. E2E-P5.2-01, E2E-P5.2-02, and E2E-P5.2-05 still pass. E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 still fail.

- [ ] T028 [US1] Make E2E-P5.2-07 pass in `e2e/fullstack/test/p5-2.test.mjs` — produces the disabled-job stale flag and the health lag, FR-004, FR-015, E2E-P5.2-07. Depends on T027 (same file). `cron.job.active` is false. `last_success_at` is older than 2 minutes. `feed_consumer.last_pull_at` is 5 minutes back. `get_ai_status` is stale. `feedConsumerHealth` returns that `last_pull_at`. E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, and E2E-P5.2-06 still pass. E2E-P5.2-08 and E2E-P5.2-10 still fail.

- [ ] T029 [US1] Make E2E-P5.2-08 pass in `e2e/fullstack/test/p5-2.test.mjs` — produces the cursor rebuild, FR-012, E2E-P5.2-08. Depends on T028 (same file). Owner SQL sets `feed_state.cursor` to 0. The same pull leaves the projection identical. E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, and E2E-P5.2-07 still pass. E2E-P5.2-10 still fails.

- [ ] T030 [US1] Make E2E-P5.2-10 pass in `e2e/fullstack/test/p5-2.test.mjs` — produces catch-up after Supabase returns, FR-015, E2E-P5.2-10. Depends on T029 (same file). With Supabase up, an administrator opens a checkout. Supabase is stopped. The Paymob stub payment is posted to ABO `POST /notify/paymob` and the platform grant completes. Supabase is started. The pull runs. `get_ai_status` is available and `active`. E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, and E2E-P5.2-08 still pass.

**Checkpoint**: E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 pass. E2E-P5.2-01 and E2E-P5.2-02 still pass.

---

## 5. Verification (H-FS)

**Purpose**: Sequencing step 38, the harness run, for this half's seven E2E ids. After T024–T030, before `quickstart.md`. The harness is the unit command from `e2e/fullstack/`. `npm test` in that package is not this task.

### 5.1 User Story 1 - Coverage pull and projection (Priority: P1) — H-FS harness

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [ ] T031 [US1] Run the unit command from `e2e/fullstack/` until E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 pass — produces the green P5.2a harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-012, FR-014, FR-015, FR-016, E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, E2E-P5.2-10. Depends on T030 (and therefore on T001–T029). This task may edit only `e2e/fullstack/test/p5-2.test.mjs`. It does not add an E2E id.

```bash
node --import tsx --test test/p5-2.test.mjs
```

**Checkpoint**: E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 pass.

---

## 6. Documentation

**Purpose**: Sequencing step 38, the quickstart write, for this half. After the H-FS harness is green (rule S8). The plan leaves `quickstart.md` for implement. No `research.md`, `data-model.md`, or `contracts/` task. The chains for E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11 are P5.2b.

### 6.1 User Story 1 - Coverage pull and projection (Priority: P1) — quickstart

**Independent Test**: E2E-P5.2-01 in harness H-FS.

- [ ] T032 [US1] Create `specs/088-abo-p5-2-coverage-feed-puller-status-projection/quickstart.md` from the plan's quickstart outline — produces this half's quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-011, FR-012, FR-013, FR-014, FR-015, FR-016, E2E-P5.2-01, E2E-P5.2-02, E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, E2E-P5.2-10. Depends on T031. Sections: (1) what was implemented — the 30-second pull, the projection, `request_ai_status_refresh`, available/active and `stale` on `get_ai_status`, and the dropped availability flag; (2) files added or modified — the Files paths this half edits; (3) the harness command below, and no earlier-unit files, no combined counts, and no full-suite command; (4) the entry point → module chain per E2E id below.

```bash
node --import tsx --test test/p5-2.test.mjs
```

| ID | Chain |
| --- | --- |
| E2E-P5.2-01 | Platform `coverage_event` → `auth_internal.pull_coverage_feed` → `net.http_get` `GET /v1/feed/coverage` → `ai-platform/src/worker.ts` `handleFeedCoverageRequest` → upsert `ai_internal.clinic_ai_coverage` → PostgREST `public.get_ai_status` |
| E2E-P5.2-02 | PostgREST `public.request_ai_status_refresh` → `auth_internal.request_ai_status_refresh` → `ai_internal.status_refresh` → `auth_internal.pull_coverage_feed` |
| E2E-P5.2-05 | Platform `coverage_event` rows for epoch 2 / seq 1 and an older pair → `auth_internal.pull_coverage_feed` → `ai_internal.clinic_ai_coverage` |
| E2E-P5.2-06 | Owner SQL sets `platformFeed.current` to a version the platform rejects → `auth_internal.pull_coverage_feed` → `GET /v1/feed/coverage` → cursor and projection unchanged |
| E2E-P5.2-07 | `cron.job` deactivated → owner SQL sets `last_success_at` and platform `feed_consumer.last_pull_at` → PostgREST `public.get_ai_status` → harness `PLATFORM.feedConsumerHealth` → `ai-platform/src/vendor/entrypoint.ts` |
| E2E-P5.2-08 | Owner SQL sets `feed_state.cursor` to 0 → `auth_internal.pull_coverage_feed` → same projection |
| E2E-P5.2-10 | PostgREST `public.issue_billing_token` → ABO `POST /v1/checkouts` → Supabase stopped → ABO `POST /notify/paymob` → platform grant → Supabase started → `auth_internal.pull_coverage_feed` → PostgREST `public.get_ai_status` |

**Checkpoint**: `quickstart.md` names the files, the unit command, and the seven chains.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (H-FS, §3)**: No dependencies. One failing test per P5.2a E2E id, in sequencing order: E2E-P5.2-01, then E2E-P5.2-02, then E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10. All of them fail before the migration exists.
- **Implementation (§4)**: Depends on §3. Tables and the availability drop, then the catalog files, then the pull and the minimal status RPC, then refresh, then the CI command, then each E2E id turning green in that same order.
- **Verification (H-FS, §5)**: Depends on §4. The unit command passes for the seven ids before `quickstart.md` exists.
- **Documentation (§6)**: Depends on §5.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: E2E-P5.2-01 is the first test. The projection tables, the availability drop, the catalog edits, the pull, the cron job, and minimal `get_ai_status` land before E2E-P5.2-01 is green. E2E-P5.2-05, E2E-P5.2-06, E2E-P5.2-07, E2E-P5.2-08, and E2E-P5.2-10 follow E2E-P5.2-02.
- **User Story 4 (P4)**: E2E-P5.2-02 is the second test. `status_refresh` is created with the projection tables. `request_ai_status_refresh` follows minimal `get_ai_status` and calls `pull_coverage_feed`. E2E-P5.2-02 turns green after E2E-P5.2-01 and before E2E-P5.2-05.

### 7.3 Within Each Phase

- T001 creates `e2e/fullstack/test/p5-2.test.mjs`. T002 through T007, T024 through T030, and T031 write that same file, in that id order.
- T008 creates `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`. T009 and T017 through T022 write that same file, in that id order.
- T010 writes only `backend/tests/catalog/harness.sql`. T011 writes only `backend/tests/catalog/harness-smoke.sql`. Neither edits the other.
- T012 writes only `backend/tests/catalog/stage-02-availability-and-enroll.sql` after T010 and T011. T013 writes only `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` after T012.
- T014 writes only `backend/tests/catalog/stage-06-verify-and-handoff.sql`. T015 writes only `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql`. T016 writes only `backend/tests/catalog/stage-06-issuer-guards.sql`. Each follows T013. None edits the others.
- T017 through T022 follow T014, T015, and T016.
- T023 writes only the `fullstack` job in `.github/workflows/ci.yml` and leaves `npm test` on the P5.1 file.
- T031 runs after T030 and may edit only `e2e/fullstack/test/p5-2.test.mjs`.
- T032 writes only `specs/088-abo-p5-2-coverage-feed-puller-status-projection/quickstart.md` after T031 is green.

---

## 8. Implementation Waves

### 8.1 Wave 1

- T001 [US1] — subphase: `### 3.1 User Story 1 - Coverage pull and projection (Priority: P1) — tests (part 1)` — paths: `e2e/fullstack/test/p5-2.test.mjs`

### 8.2 Wave 2

- T002 [US4] — subphase: `### 3.2 User Story 4 - Administrator status refresh (Priority: P4) — tests` — paths: `e2e/fullstack/test/p5-2.test.mjs`

### 8.3 Wave 3

- T003–T007 [US1] — subphase: `### 3.3 User Story 1 - Coverage pull and projection (Priority: P1) — tests (part 2)` — paths: `e2e/fullstack/test/p5-2.test.mjs`

### 8.4 Wave 4

- T008–T009 [US1] — subphase: `### 4.1 User Story 1 - Coverage pull and projection (Priority: P1) — projection and feed state` — paths: `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`

### 8.5 Wave 5

- T010 [US1] — subphase: `### 4.2 User Story 1 - Coverage pull and projection (Priority: P1) — harness catalog` — paths: `backend/tests/catalog/harness.sql`
- T011 [US1] — subphase: `### 4.3 User Story 1 - Coverage pull and projection (Priority: P1) — harness smoke catalog` — paths: `backend/tests/catalog/harness-smoke.sql`

### 8.6 Wave 6

- T012 [US1] — subphase: `### 4.4 User Story 1 - Coverage pull and projection (Priority: P1) — stage-02 enroll catalog` — paths: `backend/tests/catalog/stage-02-availability-and-enroll.sql`

### 8.7 Wave 7

- T013 [US1] — subphase: `### 4.5 User Story 1 - Coverage pull and projection (Priority: P1) — stage-02 revoke catalog` — paths: `backend/tests/catalog/stage-02-revoke-rotate-availability.sql`

### 8.8 Wave 8

- T014 [US1] — subphase: `### 4.6 User Story 1 - Coverage pull and projection (Priority: P1) — stage-06 verify catalog` — paths: `backend/tests/catalog/stage-06-verify-and-handoff.sql`
- T015 [US1] — subphase: `### 4.7 User Story 1 - Coverage pull and projection (Priority: P1) — stage-06 happy-path catalog` — paths: `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql`
- T016 [US1] — subphase: `### 4.8 User Story 1 - Coverage pull and projection (Priority: P1) — stage-06 issuer catalog` — paths: `backend/tests/catalog/stage-06-issuer-guards.sql`

### 8.9 Wave 9

- T017–T021 [US1] — subphase: `### 4.9 User Story 1 - Coverage pull and projection (Priority: P1) — pull, projection, and minimal status` — paths: `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`

### 8.10 Wave 10

- T022 [US4] — subphase: `### 4.10 User Story 4 - Administrator status refresh (Priority: P4) — request_ai_status_refresh` — paths: `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`

### 8.11 Wave 11

- T023 [US1] — subphase: `### 4.11 User Story 1 - Coverage pull and projection (Priority: P1) — CI command` — paths: `.github/workflows/ci.yml`

### 8.12 Wave 12

- T024 [US1] — subphase: `### 4.12 User Story 1 - Coverage pull and projection (Priority: P1) — E2E-P5.2-01 passes` — paths: `e2e/fullstack/test/p5-2.test.mjs`

### 8.13 Wave 13

- T025 [US4] — subphase: `### 4.13 User Story 4 - Administrator status refresh (Priority: P4) — E2E-P5.2-02 passes` — paths: `e2e/fullstack/test/p5-2.test.mjs`

### 8.14 Wave 14

- T026–T030 [US1] — subphase: `### 4.14 User Story 1 - Coverage pull and projection (Priority: P1) — remaining projection scenarios pass` — paths: `e2e/fullstack/test/p5-2.test.mjs`

### 8.15 Wave 15

- T031 [US1] — subphase: `### 5.1 User Story 1 - Coverage pull and projection (Priority: P1) — H-FS harness` — paths: `e2e/fullstack/test/p5-2.test.mjs`

### 8.16 Wave 16

- T032 [US1] — subphase: `### 6.1 User Story 1 - Coverage pull and projection (Priority: P1) — quickstart` — paths: `specs/088-abo-p5-2-coverage-feed-puller-status-projection/quickstart.md`
