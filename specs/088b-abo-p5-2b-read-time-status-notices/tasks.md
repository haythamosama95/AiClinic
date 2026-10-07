# Tasks: Read-time status, notices and billing status

**Input**: Design documents from `specs/088b-abo-p5-2b-read-time-status-notices/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P5.2a (the pull, the projection, and `request_ai_status_refresh` in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`; CP-D already covered by `e2e/fullstack/test/p5-2.test.mjs`). Plan artifacts from `AVAILABLE_DOCS`: `data-model.md`, `contracts/`. `research.md` is omitted (no spike) and is not a task. `data-model.md` and `contracts/` are not tasks: plan already wrote them. `quickstart.md` is written in Documentation after this unit's harness is green.

**Organization**: P5.2b is User Story 2 and User Story 3 (`[US2]`, `[US3]`), size S (rule S3). Branch `ai/088b-abo-p5-2b-read-time-status-notices`. E2E ids stay `E2E-P5.2-03`, `E2E-P5.2-04`, `E2E-P5.2-09`, and `E2E-P5.2-11`. This unit owns grace, lapse, notices, `days_left`, the `reason` read mapping, and `get_ai_billing_status`. The puller, projection writes, `request_ai_status_refresh`, the availability drop, and the R-4 spike stay with P5.2a. Tests are one task per E2E id, written to fail before `20261008010000_read_time_status_notices.sql` exists, plus the plan sequencing steps for the shared fixture and the red run. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 13. Size S is 12–20 (rule S3). Plan sequencing steps 1–13 are these tasks. The count is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` — the only migration this unit creates
- **Full-stack harness**: `e2e/fullstack/test/p5-2b.test.mjs` — this file does not import `e2e/fullstack/test/p5-2.test.mjs` or `wrangler`, and it does not call `startWorker`. `e2e/fullstack/package.json` is not edited
- **Consumed and not modified**: `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`, `auth_internal.pull_coverage_feed`, `auth_internal.request_ai_status_refresh`, `public.request_ai_status_refresh`, `e2e/fullstack/test/p5-2.test.mjs`, `specs/088-abo-p5-2-coverage-feed-puller-status-projection/`
- **Read only**: `ai_internal.clinic_ai_coverage`, `ai_internal.feed_state.last_success_at`, `ai.platform_base_url`, `ai.abo_base_url` through `auth_internal.ai_app_setting_text`
- **Shared package**: `packages/vendor-contracts/src/identifiers.ts` (`subscriptionRef`, `crockfordEncode`) and `packages/vendor-contracts/vectors/identifiers.json` — consumed by the SQL expression and the H-FS comparison, not modified
- **Spec Kit artifacts**: `specs/088b-abo-p5-2b-read-time-status-notices/`

---

## 3. Tests (H-FS)

**Purpose**: Sequencing steps 1–6. One failing test per E2E id. Titles are prefixed with the E2E id. Leave `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` uncreated through T006.

```bash
node --import tsx --test test/p5-2b.test.mjs
```

Run that command from `e2e/fullstack/`. That command is the unit harness. `npm test` in `e2e/fullstack` is not the harness.

### 3.1 User Story 2 - Read-time status and notices (Priority: P1) — tests (part 1)

**Independent Test**: E2E-P5.2-03, E2E-P5.2-04, and E2E-P5.2-11 in harness H-FS.

- [X] T001 [US2] Add the H-FS clinic fixture and SQL seed helpers in `e2e/fullstack/test/p5-2b.test.mjs` — fixture for the four failing tests, FR-001, FR-002, E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, E2E-P5.2-11. Depends on nothing. Create the file. Sign in through local Supabase with `create_staff_account` for each `public.staff_role` (`administrator`, `doctor`, `receptionist`, `lab_staff`) and call PostgREST with supabase-js. Seed `ai_internal.clinic_ai_coverage` and `ai_internal.feed_state` with `psql`. Set `ends_at`, `grace_ends_at`, and `last_success_at` relative to database `now()` so a predicate holds on the read. Do not sleep the 2-minute stale window or a calendar day. Do not import `wrangler` or `e2e/fullstack/test/p5-2.test.mjs`, and do not call `startWorker`. Do not edit `e2e/fullstack/package.json` or `e2e/fullstack/test/p5-2.test.mjs`. This task adds no `test()` body.

**Checkpoint**: The fixture file exists and starts no workers. E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11 are not written yet.

- [X] T002 [US2] Add the failing test `E2E-P5.2-03` in `e2e/fullstack/test/p5-2b.test.mjs` — red test, FR-001, FR-002, FR-003, FR-005, FR-008, E2E-P5.2-03. Depends on T001 (same file). Title `E2E-P5.2-03 Stored dates pass to grace then lapsed while workers are stopped, then stale and status_stale`. Workers are not started. Seed stored `active` or `grace` with `queued_count` not greater than 0. After `ends_at`, state is `grace` while `now < grace_ends_at`, then `lapsed`. `reason` is null in grace and `expired` on that clock lapse. `notices[]` is asserted by code, with no required array order: `in_grace` with `grace_days_left` during grace, and `lapsed` once lapsed. `last_success_at` older than 2 minutes makes `stale` true and adds `status_stale`. `contract_version` echoes the request. Take database `now()` on that database immediately before the call and immediately after the response, and assert `as_of` lies between those two timestamps, including when the projection row is absent. When `event_at`, `applied_at`, or `last_success_at` are seeded to other times, `as_of` is not those values. When the projection row is absent, `state` is `none`, `available` is false, `reason` is `none`, and `days_left` is null. The unit command fails because the current `get_ai_status` has no grace clock, no notices, and no `days_left`.

**Checkpoint**: E2E-P5.2-03 exists and fails.

- [X] T003 [US2] Add the failing test `E2E-P5.2-04` in `e2e/fullstack/test/p5-2b.test.mjs` — red test, FR-001, FR-004, FR-005, FR-006, FR-008, E2E-P5.2-04. Depends on T002 (same file). Title `E2E-P5.2-04 ends_soon at 7, 3, and 1 days when queued_count is 0, staff status has no prices, and staff billing is FORBIDDEN_ROLE`. `ends_soon` is present when `days_left` is 7, 3, or 1 or fewer (including 0) and `queued_count = 0`. A null `days_left` does not add `ends_soon`. Assert `notices[]` by code, with no required array order. Staff `get_ai_status` data has no price, payment, or reference keys (`subscription_ref`, `term_ref`, `abo_base_url`, plan, allowance). A non-administrator `get_ai_billing_status` returns `success = false`, `error_code = FORBIDDEN_ROLE`, and null `data`. A missing `p_contract_version` and version `2` on either RPC return `CONTRACT_VERSION_UNSUPPORTED` and leave `clinic_ai_coverage.reason` unchanged. The unit command fails because notices and `get_ai_billing_status` are absent. E2E-P5.2-03 still fails.

**Checkpoint**: E2E-P5.2-03 and E2E-P5.2-04 exist and fail. The E2E-P5.2-04 billing half is the User Story 3 `FORBIDDEN_ROLE` scenario in this same test.

### 3.2 User Story 3 - Administrator billing status (Priority: P2) — tests

**Independent Test**: E2E-P5.2-04 and E2E-P5.2-09 in harness H-FS. Every earlier suite stays green (rule S2).

- [X] T004 [US3] Add the failing test `E2E-P5.2-09` in `e2e/fullstack/test/p5-2b.test.mjs` — red test, FR-006, FR-007, FR-008, E2E-P5.2-09. Depends on T003 (same file). Title `E2E-P5.2-09 SQL subscription ref equals the package vector and the ABO and platform values`. For the clinic org, SQL `subscription_ref` from PostgREST `public.get_ai_billing_status` equals `await subscriptionRef(orgId)` from `packages/vendor-contracts`. That function is the value `abo/src/clinic-api/billing-reads.ts` and `ai-platform/src/coverage-read/index.ts` return for the same org. The package vector for org `7c9e6679-7425-40de-944b-e07fc1f90ae7` is `AIC-2W3W7P9G`. Success `data` also carries the other flat billing fields (`plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, `subscription_ref`, `abo_base_url`) and has no `remaining` key. `contract_version` echoes the request. Workers stay stopped. The unit command fails because `get_ai_billing_status` is absent. E2E-P5.2-03 and E2E-P5.2-04 still fail.

**Checkpoint**: E2E-P5.2-09 exists and fails. E2E-P5.2-03 and E2E-P5.2-04 still fail.

### 3.3 User Story 2 - Read-time status and notices (Priority: P1) — tests (part 2)

**Independent Test**: E2E-P5.2-03, E2E-P5.2-04, and E2E-P5.2-11 in harness H-FS.

- [X] T005 [US2] Add the failing test `E2E-P5.2-11` in `e2e/fullstack/test/p5-2b.test.mjs` — red test, FR-001, FR-005, E2E-P5.2-11. Depends on T004 (same file). Title `E2E-P5.2-11 Band 90 raises allowance_low for every role`. Seed `band` `90`. For each `public.staff_role`, `notices[]` includes `allowance_low` as `{code, audience: member, channel: in_app}` with no `grace_days_left` key. Assert by code, with no required array order. The unit command fails because `allowance_low` is absent. E2E-P5.2-03, E2E-P5.2-04, and E2E-P5.2-09 still fail.

**Checkpoint**: E2E-P5.2-11 exists and fails. E2E-P5.2-03, E2E-P5.2-04, and E2E-P5.2-09 still fail.

### 3.4 User Story 2 - Read-time status and notices (Priority: P1) — red run

**Independent Test**: E2E-P5.2-03, E2E-P5.2-04, and E2E-P5.2-11 in harness H-FS.

- [X] T006 [US2] Run the failing H-FS file `e2e/fullstack/test/p5-2b.test.mjs` — red run, FR-001, FR-006, E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, E2E-P5.2-11. Depends on T005. From `e2e/fullstack/`, run `node --import tsx --test test/p5-2b.test.mjs` and confirm those four tests fail on the current `get_ai_status` (no grace clock, no notices, no `days_left`) and on the absent `get_ai_billing_status`. Leave `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` uncreated. Do not edit `e2e/fullstack/test/p5-2b.test.mjs` in this task. Do not run `npm test` in `e2e/fullstack`. Do not start workers.

**Checkpoint**: E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11 fail. The read-time migration does not exist yet.

---

## 4. Implementation

**Purpose**: Sequencing steps 7–11. Starts after T006 has shown the four tests fail. Within a subphase the tasks run in id order. T007–T011 edit only `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`. One `auth_internal` reader returns the shared status view. The billing wrapper calls that reader and adds fields. It does not add a second status implementation.

### 4.1 User Story 2 - Read-time status and notices (Priority: P1) — read-time status

**Independent Test**: E2E-P5.2-03, E2E-P5.2-04, and E2E-P5.2-11 in harness H-FS.

- [ ] T007 [US2] Replace `auth_internal.get_ai_status(integer)` in `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` — produces the read-time status view, FR-001, FR-002, FR-003, FR-004, FR-005, E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-11. Depends on T006. Create the file. `CREATE OR REPLACE` the function as `STABLE` `SECURITY DEFINER` with `search_path = public, auth_internal, ai_internal`, keyed on `current_org_id()`. Capture PostgreSQL `now()` once as `as_of` and reuse that instant for `days_left`, `grace_days_left`, `next_change_at`, and `stale`. `as_of` is not `event_at`, `applied_at`, or `feed_state.last_success_at`. It is present when the projection row is absent, and it is not stored. Return `available`, `state`, `reason`, `days_left`, `band`, `notices[]`, `next_change_at`, `as_of`, `stale`, and `platform_base_url` on the `rpc_result` envelope, using `public.rpc_success` / `public.rpc_error`. `platform_base_url` comes from `auth_internal.ai_app_setting_text`. The result has no prices, payments, or references. Clock: no row yields `state = none`, `available = false`; suspended yields `available = false`, `state = suspended`, and that step wins over the stored state; stored `active` stays `active` while `now < ends_at`, stays `active` when `now` is past `ends_at` and `queued_count > 0`, becomes `grace` while `now < grace_ends_at`, and otherwise becomes `lapsed`; stored `grace` stays `grace` while `now < grace_ends_at`, then becomes `lapsed`; any other stored state is unavailable as stored. `available` is true exactly for `active` and `grace`. `next_change_at` is the next of `ends_at` and `grace_ends_at` still in the future, otherwise null. `stale` is true when `last_success_at` is null or strictly older than 2 minutes (121 seconds is stale). A stored `active` row with `now < ends_at` still returns `available = true` and `state = active`. `reason` is null for returned `active`, `grace`, or `suspended`; `none` when the row is absent; `expired` when stored `active` or `grace` becomes `lapsed` at read time; otherwise the stored `clinic_ai_coverage.reason` (`none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, or `transfer_pending`). A row already stored as `lapsed` with `grace_exhausted` keeps that stored `reason`. The read does not `UPDATE` `clinic_ai_coverage` or `feed_state`. `days_left` is the whole 24-hour days from that `now` until `ends_at`, floored (`86400` seconds), so a remaining partial day is `0`. It is null when the row is absent, `ends_at` is null, or `now >= ends_at`. It is separate from `grace_days_left`. A null `days_left` does not raise `ends_soon`. The H-FS day of 2 seconds is not applied inside the RPC. Each notice is `{code, audience: member, channel: in_app}`, and `grace_days_left` is present only when `code` is `in_grace`: a non-negative integer, the whole 24-hour days from that `now` until `grace_ends_at`, floored. Every other notice omits `grace_days_left`. Closed codes: `ends_soon` (`days_left` is 7, 3, or 1 or fewer, null does not match, and `queued_count = 0`), `in_grace` (state `grace`), `allowance_low` (band 75 or 90), `allowance_exhausted` (state `exhausted`), `lapsed` (state `lapsed`), `ended_reversed` (state `reversed`), `suspended` (suspended flag), and `status_stale` (`stale = true`). The same records are returned to every member. Do not replace `public.get_ai_status` in this task (T008). Do not add `public.get_ai_billing_status` (T010). Do not edit the P5.2a migration, `request_ai_status_refresh`, or `auth_internal.pull_coverage_feed`.

**Checkpoint**: The shared reader computes grace, lapse, `reason`, `days_left`, notices, `as_of`, and `stale`. `public.get_ai_billing_status` is still absent, so E2E-P5.2-04 and E2E-P5.2-09 still fail.

- [ ] T008 [US2] Replace `public.get_ai_status(integer)` in `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` — produces the member status RPC, FR-001, FR-008, E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-11. Depends on T007 (same file). `CREATE OR REPLACE` `public.get_ai_status(integer)` as `SECURITY DEFINER`. The version gate runs before any role check and before the reader: null, a missing argument, or a value other than `0` or `1` returns `CONTRACT_VERSION_UNSUPPORTED` and does not call `auth_internal.get_ai_status`. That accepted set matches `ai.contract_versions.backendRpc` current `1`, minimum `0`. Then call the reader. There is no role gate. Success `data` is the status view only: no prices, payments, or references, and no `remaining` key. `contract_version` is the version the request used. A rejected version does not write.

**Checkpoint**: `public.get_ai_status` gates the contract version and returns the read-time view. E2E-P5.2-04 and E2E-P5.2-09 still fail because `get_ai_billing_status` is absent.

### 4.2 User Story 3 - Administrator billing status (Priority: P2) — billing status

**Independent Test**: E2E-P5.2-04 and E2E-P5.2-09 in harness H-FS. Every earlier suite stays green (rule S2).

- [ ] T009 [US3] Add the SQL `subscription_ref` expression in `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` — produces the package subscription ref, FR-007, E2E-P5.2-09. Depends on T008 (same file). Compute it in the billing wrapper this migration is adding: UTF-8 SHA-256 of `sub-ref:` concatenated with `current_org_id()::text`, via `extensions.digest`, Crockford base-32 (alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, same bit packing as `crockfordEncode` in `packages/vendor-contracts/src/identifiers.ts`), first 8 characters, prefix `AIC-`. For org `7c9e6679-7425-40de-944b-e07fc1f90ae7` the value is `AIC-2W3W7P9G`. Leave the version gate, the administrator gate, the shared view, and the other flat fields to T010. Do not add a second status implementation.

**Checkpoint**: The migration contains the `subscription_ref` expression that matches `subscriptionRef`. The billing RPC gates are still T010.

- [ ] T010 [US3] Add `public.get_ai_billing_status(integer)` in `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` — produces the administrator billing RPC, FR-003, FR-004, FR-005, FR-006, FR-008, E2E-P5.2-04, E2E-P5.2-09. Depends on T009 (same file). `CREATE` the function `SECURITY DEFINER` with `search_path = public, auth_internal, ai_internal, extensions`. The version gate runs before the role check and before the reader: null, a missing argument, or a value other than `0` or `1` returns `CONTRACT_VERSION_UNSUPPORTED` and does not call the reader. Then allow only membership role `administrator`. Any other role returns `rpc_result` with `success = false`, `error_code = 'FORBIDDEN_ROLE'`, and null `data` (no status payload). Success `data` is the shared reader view plus flat fields `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, `subscription_ref` from T009, and `abo_base_url` from `auth_internal.ai_app_setting_text`. There is no `remaining` key. When the projection row is absent, or a copied column is null, that JSON value is null. `reason`, `days_left`, `notices[]`, and `as_of` are the same values the reader returns. `contract_version` is the version the request used. A rejected version does not write. Keep the T009 expression. Do not grant `EXECUTE` in this task (T011).

**Checkpoint**: `public.get_ai_billing_status` returns the shared view plus the flat billing fields for an administrator, and `FORBIDDEN_ROLE` with no status payload otherwise. `EXECUTE` is granted in T011.

- [ ] T011 [US3] Grant `EXECUTE` on `public.get_ai_billing_status(integer)` in `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` — produces the authenticated grant, FR-006, E2E-P5.2-04, E2E-P5.2-09. Depends on T010 (same file). `REVOKE` and `GRANT` `EXECUTE` the same way as `public.get_ai_status(integer)`: `authenticated` only.

**Checkpoint**: `authenticated` can execute `public.get_ai_billing_status(integer)`. The four H-FS tests are ready for the green run.

---

## 5. Verification (H-FS)

**Purpose**: Sequencing step 12. The unit harness passes. This is not a repo-wide command.

### 5.1 User Story 2 - Read-time status and notices (Priority: P1) — H-FS harness

**Independent Test**: E2E-P5.2-03, E2E-P5.2-04, and E2E-P5.2-11 in harness H-FS.

- [ ] T012 [US2] Re-run `e2e/fullstack/test/p5-2b.test.mjs` until the four tests pass — green harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, E2E-P5.2-11. Depends on T011. From `e2e/fullstack/`, run `node --import tsx --test test/p5-2b.test.mjs` until E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11 pass. Fixes stay in `e2e/fullstack/test/p5-2b.test.mjs` and `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`. Do not run `npm test` in `e2e/fullstack`. Do not start workers. Do not edit `e2e/fullstack/test/p5-2.test.mjs` or the P5.2a migration.

**Checkpoint**: E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11 pass in H-FS.

---

## 6. Documentation

**Purpose**: Sequencing step 13. `quickstart.md` after the harness is green. Plan-phase `data-model.md` and `contracts/status-rpc.md` stay as plan wrote them.

### 6.1 User Story 3 - Administrator billing status (Priority: P2) — quickstart

**Independent Test**: E2E-P5.2-04 and E2E-P5.2-09 in harness H-FS. Every earlier suite stays green (rule S2).

- [ ] T013 [US3] Write `specs/088b-abo-p5-2b-read-time-status-notices/quickstart.md` — unit quickstart, FR-001, FR-006, FR-007, E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, E2E-P5.2-11. Depends on T012. Fill only these sections: what was implemented and the files added or modified; the harness command for this unit's tests only, from `e2e/fullstack/`, `node --import tsx --test test/p5-2b.test.mjs`; the entry point → module chain per E2E id (PostgREST `public.get_ai_status` or `public.get_ai_billing_status` → version gate → `auth_internal.get_ai_status`, and for billing the administrator gate plus SQL `subscription_ref`). Do not list earlier-unit files, combined counts, or full-suite commands. Manual steps are omitted: the harness sees this behaviour. The real branch named in the doc is `ai/088b-abo-p5-2b-read-time-status-notices`.

**Checkpoint**: `quickstart.md` names the four H-FS ids, the unit command, and the entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: No setup phase. T001 creates the fixture. T002 and T003 add the User Story 2 tests that Sequencing places first. T004 adds the User Story 3 subscription-ref test. T005 adds the remaining User Story 2 test. T006 runs the file and confirms all four fail before the migration exists.
- **Implementation (Phase 4)**: Starts after T006. User Story 2 replaces the reader and `public.get_ai_status`. User Story 3 then adds `subscription_ref`, `public.get_ai_billing_status`, and the `EXECUTE` grant, in that order, in the same migration.
- **Verification (Phase 5)**: Starts after T011. One command: `node --import tsx --test test/p5-2b.test.mjs` from `e2e/fullstack/`.
- **Documentation (Phase 6)**: Starts after T012 is green. One file: `quickstart.md`.

### 7.2 User Story Dependencies

- **User Story 2 (P1)**: Starts at T001. Its tests are T002, T003, and T005. E2E-P5.2-04 also carries the User Story 3 `FORBIDDEN_ROLE` assertion because that scenario shares this E2E id. Its implementation is T007 and T008. The red run (T006) and the green harness (T012) include this story's ids.
- **User Story 3 (P2)**: The subscription-ref test is T004, after T003, because Sequencing places E2E-P5.2-09 before E2E-P5.2-11. Billing implementation is T009, T010, and T011, after the public status wrapper. `quickstart.md` is T013, after both stories' tests pass.

### 7.3 Within Each Phase

- T001 creates `e2e/fullstack/test/p5-2b.test.mjs`. T002 through T005 write that same file, in that id order. T006 runs it and does not edit it.
- T007 creates `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`. T008 through T011 write that same file, in that id order.
- T012 runs after T011 and may edit only `e2e/fullstack/test/p5-2b.test.mjs` and `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`.
- T013 writes only `specs/088b-abo-p5-2b-read-time-status-notices/quickstart.md` after T012 is green.

---

## 8. Implementation Waves

Sequencing orders every subphase after the previous one. The test subphases share `e2e/fullstack/test/p5-2b.test.mjs`, and the implementation subphases share `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`, so each wave has one bullet.

### 8.1 Wave 1

- T001–T003 [US2] — subphase: `### 3.1 User Story 2 - Read-time status and notices (Priority: P1) — tests (part 1)` — paths: `e2e/fullstack/test/p5-2b.test.mjs`

### 8.2 Wave 2

- T004 [US3] — subphase: `### 3.2 User Story 3 - Administrator billing status (Priority: P2) — tests` — paths: `e2e/fullstack/test/p5-2b.test.mjs`

### 8.3 Wave 3

- T005 [US2] — subphase: `### 3.3 User Story 2 - Read-time status and notices (Priority: P1) — tests (part 2)` — paths: `e2e/fullstack/test/p5-2b.test.mjs`

### 8.4 Wave 4

- T006 [US2] — subphase: `### 3.4 User Story 2 - Read-time status and notices (Priority: P1) — red run` — paths: `e2e/fullstack/test/p5-2b.test.mjs`

### 8.5 Wave 5

- T007–T008 [US2] — subphase: `### 4.1 User Story 2 - Read-time status and notices (Priority: P1) — read-time status` — paths: `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`

### 8.6 Wave 6

- T009–T011 [US3] — subphase: `### 4.2 User Story 3 - Administrator billing status (Priority: P2) — billing status` — paths: `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`

### 8.7 Wave 7

- T012 [US2] — subphase: `### 5.1 User Story 2 - Read-time status and notices (Priority: P1) — H-FS harness` — paths: `e2e/fullstack/test/p5-2b.test.mjs`, `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`

### 8.8 Wave 8

- T013 [US3] — subphase: `### 6.1 User Story 3 - Administrator billing status (Priority: P2) — quickstart` — paths: `specs/088b-abo-p5-2b-read-time-status-notices/quickstart.md`
