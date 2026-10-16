# Implementation Plan: Coverage feed puller, status projection and status RPCs

**Branch**: `ai/088-abo-p5-2-coverage-feed-puller-status-projection` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/088-abo-p5-2-coverage-feed-puller-status-projection/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

The shared backend pulls `GET /v1/feed/coverage` every 30 seconds, stores one `ai_internal.clinic_ai_coverage` row per clinic, and serves `get_ai_status`, `get_ai_billing_status`, and `request_ai_status_refresh`. It is phase P5, size L, **Depends** P5.1 and P3.9, in parallel with P4.x.

## Technical Context

**Language/Version**: PostgreSQL on local Supabase. The H-FS runner is Node (`>=22`) in `e2e/fullstack/`.

**Primary Dependencies**: `pg_cron` 1.6 and `pg_net` 0.14.0, already preloaded on local Supabase ([research.md](./research.md)). `auth_internal.issue_feed_token()` from P5.1. `ai.platform_base_url`, `ai.abo_base_url`, and `ai.contract_versions` from that same migration. `public.current_org_id()` and `public.current_membership_role()`. `packages/vendor-contracts` `subscriptionRef` is read by the H-FS test at run time and is not copied into SQL or into the test. No new library.

**Storage**: Supabase PostgreSQL tables in [data-model.md](./data-model.md). Platform D1 `coverage_event` and `feed_consumer` stay the consumed P3.9 tables. The pull does not write them.

**Testing**: H-FS only. File `e2e/fullstack/test/p5-2.test.mjs`. Titles start with the E2E id (rule V3). Tests are written to fail before the behavior exists. The runner executes `auth_internal.pull_coverage_feed()` and checks `cron.job`. It does not sleep 60 seconds, 2 minutes, or 5 minutes. Stale rows set `feed_state.last_success_at` older than 2 minutes. The disabled-job case also sets platform `feed_consumer.last_pull_at` 5 minutes back. Grace, lapse, and `ends_soon` come from snapshot `ends_at` and `grace_ends_at` against the database clock. A throttled refresh is a second call at once. A later accepted refresh sets `status_refresh.requested_at` to 10 seconds ago. Compressed platform term scale stays the consumed P3 clock (1 day = 2 seconds). SQL `days_left` and `grace_days_left` use 86400-second days.

**Target Platform**: Local Supabase (`http://127.0.0.1:54321`, database port 54322). Platform and ABO are the existing H-FS workers. Clinic calls use PostgREST. Owner SQL uses `psql`.

**Project Type**: Backend. H-FS (`e2e/fullstack/`) is the named harness, including `pg_net` to the host. No second product codebase.

**Performance Goals**: A 30-second cycle applies an event within about 60 seconds of it reaching platform D1, inside the 2-minute bound. Page `limit` is 200. Feed token life stays 120 seconds. At most one accepted refresh per 10 seconds per tenant.

**Constraints**: Projection and feed state stay in `ai_internal`. The pull function is not granted to clinic roles. `get_ai_billing_status` and `request_ai_status_refresh` require membership role `administrator`. A feed page is applied only after HTTP 200, an echoed contract version, `after` equal to the cursor, and ascending `feed_seq`. An unsupported feed version does not move the cursor. An unsupported refresh version does not start a pull. No clinic RPC writes status. `ai.availability` is removed in this migration. The availability migration files named in 04 §3.1 are not edited.

**Scale/Scope**: Size L (rule S3: 4 user stories, one codebase plus the H-FS harness). Eleven E2E ids. Implied task count is 38 (the sequencing below).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (version 1.0.0, rule S12). The local R-4 spike passed, so the interval stays 30 seconds. The same boxes hold after the data model.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  A clinic member reads AI status for the active organisation. An administrator reads the billing view and can request one immediate pull. Staff do not receive prices (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The pull is `pg_cron` and `pg_net` on the existing Supabase database. H-FS is a test runner. No second deployable (02 §7 principle I, 05 §7).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  The pull, the ordering rule, the read-time status, and the notice vocabulary are PostgreSQL functions reached through Supabase RPCs. Flutter is out of this unit. The platform feed and `feedConsumerHealth` stay the consumed P3.9 contract (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  Projection rows, feed state, and the refresh clock are written only by definer functions. The page is applied in one transaction. A failed page writes nothing to the projection (02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  Status RPCs are keyed on `current_org_id()`. Billing status and refresh require role `administrator`. The feed mint stays ungranted. Dropping `ai.availability` removes the superseded flag the design names. Clinic clinical rows are not hard-deleted (02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit does not add a model call. When the pull, the platform, or the ABO is stopped, stored dates still move status to grace and then lapsed, and clinical work is not locked (02 §7 principle V, FM-10, FM-11).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | One pull job on the existing Supabase project. No second service. |
| II. Replaceable layer boundaries | Codebase is backend. The H-FS harness calls the platform and the ABO. Their source is not modified. |
| III. Backend authority and data integrity | Coverage state is a definer pull and definer RPCs. `ai_internal` is not exposed. |
| IV. Secure and human-gated operations | Members read status. Administrators read billing status and request a refresh. A non-administrator receives `FORBIDDEN_ROLE`. |
| V. Operational continuity | A stopped pull becomes `stale`. Dates still evaluate. Supabase downtime does not stop ABO and platform provisioning. |
| Workflow automation | One `pg_cron` command. No DAG. |
| Higher operational burden | `pg_cron` and `pg_net` are the parts 05 §7 already names. The local spike kept the 30-second interval. |

## Project Structure

### Documentation (this feature)

```text
specs/088-abo-p5-2-coverage-feed-puller-status-projection/
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   └── status-rpc-results.md
├── spec.md
├── escalations.md
└── quickstart.md        # implement writes this after the unit command is green
```

No `tasks.md` in this phase.

`quickstart.md` sections, written by implement after the unit command is green:

1. What was implemented — the 30-second pull, the projection, the three status RPCs, and the dropped availability flag.
2. Files added or modified — the Files section of this plan.
3. Harness command for this unit's tests only — the command in Test Layout. No earlier-unit files, no combined counts, and no full-suite command.
4. Entry point → module chain per E2E id — the table below.

| E2E id | Chain |
| --- | --- |
| E2E-P5.2-01 | Platform `coverage_event` → `auth_internal.pull_coverage_feed` → `net.http_get` `GET /v1/feed/coverage` → `ai-platform/src/worker.ts` `handleFeedCoverageRequest` → upsert `ai_internal.clinic_ai_coverage` → PostgREST `public.get_ai_status` |
| E2E-P5.2-02 | PostgREST `public.request_ai_status_refresh` → `auth_internal.request_ai_status_refresh` → `ai_internal.status_refresh` → `auth_internal.pull_coverage_feed` |
| E2E-P5.2-03 | Owner SQL sets projection dates and `feed_state.last_success_at` → workers stopped → PostgREST `public.get_ai_status` |
| E2E-P5.2-04 | PostgREST `public.get_ai_status` and `public.get_ai_billing_status` as staff |
| E2E-P5.2-05 | Platform `coverage_event` rows for epoch 2 / seq 1 and an older pair → `auth_internal.pull_coverage_feed` → `ai_internal.clinic_ai_coverage` |
| E2E-P5.2-06 | Owner SQL sets `platformFeed.current` to a version the platform rejects → `auth_internal.pull_coverage_feed` → `GET /v1/feed/coverage` → cursor and projection unchanged |
| E2E-P5.2-07 | `cron.job` deactivated → owner SQL sets `last_success_at` and platform `feed_consumer.last_pull_at` → PostgREST `public.get_ai_status` → harness `PLATFORM.feedConsumerHealth` → `ai-platform/src/vendor/entrypoint.ts` |
| E2E-P5.2-08 | Owner SQL sets `feed_state.cursor` to 0 → `auth_internal.pull_coverage_feed` → same projection |
| E2E-P5.2-09 | PostgREST `public.get_ai_billing_status` → SQL `subscription_ref` compared with `subscriptionRef` from `packages/vendor-contracts` and with the local ABO and platform values for that org |
| E2E-P5.2-10 | PostgREST `public.issue_billing_token` → ABO `POST /v1/checkouts` → Supabase stopped → ABO `POST /notify/paymob` → platform grant → Supabase started → `auth_internal.pull_coverage_feed` → PostgREST `public.get_ai_status` |
| E2E-P5.2-11 | Platform `coverage_event` with band `90` → `auth_internal.pull_coverage_feed` → PostgREST `public.get_ai_status` for each membership role |

### Source Code (repository root)

```text
backend/
├── supabase/migrations/20261007230000_coverage_feed_puller_status.sql
└── tests/catalog/
    ├── harness.sql
    ├── harness-smoke.sql
    ├── stage-02-availability-and-enroll.sql
    ├── stage-02-revoke-rotate-availability.sql
    ├── stage-06-verify-and-handoff.sql
    ├── stage-06-happy-path-and-lifecycle.sql
    └── stage-06-issuer-guards.sql

e2e/fullstack/test/p5-2.test.mjs

.github/workflows/ci.yml
```

**Structure Decision**: One new backend migration holds the tables, the pull, the cron job, and the three RPCs. The pull function is `auth_internal.pull_coverage_feed()`. H-FS adds `e2e/fullstack/test/p5-2.test.mjs` and does not change `package.json`. Platform source and ABO source are not modified.

## Consumes Binding

| Consumes | Existing module | This unit |
| --- | --- | --- |
| P3.9 HTTP feed | `GET /v1/feed/coverage` in `ai-platform/src/worker.ts` (`handleFeedCoverageRequest`). Body `{contract_version, after, events[], next_after, has_more}`. Each event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`. Header `Aip-Contract-Version`. | Called by `net.http_get`. Not modified. |
| P3.9 `/v1/coverage` | `handleCoverageReadRequest` in `ai-platform/src/coverage-read/index.ts`, routed from `ai-platform/src/worker.ts`. | Not called and not modified. |
| P3.9 `feedConsumerHealth` | `VendorEntrypoint.feedConsumerHealth` in `ai-platform/src/vendor/entrypoint.ts`. Detail `{last_pull_at, last_cursor}` from D1 `feed_consumer` where `consumer = 'backend-feed'`. | Called from the H-FS harness binding in E2E-P5.2-07. Not modified. |
| P5.1 | The unit row states no Outputs / freezes line. | `auth_internal.issue_feed_token()` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` is called and not modified. `ai.platform_base_url`, `ai.abo_base_url`, and `ai.contract_versions` in that migration are read. `public.current_org_id()` and `public.current_membership_role()` in `backend/supabase/migrations/20261002120000_membership_active_org.sql` are called and not modified. |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `specs/088-abo-p5-2-coverage-feed-puller-status-projection/research.md` | R-4 local outcome. | FR-013 |
| `specs/088-abo-p5-2-coverage-feed-puller-status-projection/data-model.md` | Entities in spec §3.2 and `status_refresh`. | FR-003, FR-004, FR-005, FR-010, FR-011 |
| `specs/088-abo-p5-2-coverage-feed-puller-status-projection/contracts/status-rpc-results.md` | Frozen status results and notice codes. | FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-016 |
| `specs/088-abo-p5-2-coverage-feed-puller-status-projection/quickstart.md` | Implement phase, after the unit command is green. | FR-001–FR-016 |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | Create the objects in [data-model.md](./data-model.md) and the functions below. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-014, FR-015, FR-016 |
| `backend/tests/catalog/harness.sql` | Stop requiring the `ai.availability` row. | FR-011 |
| `backend/tests/catalog/harness-smoke.sql` | Stop requiring the `ai.availability` row. | FR-011 |
| `backend/tests/catalog/stage-02-availability-and-enroll.sql` | Assert `get_ai_availability` and `ai.availability` are absent. | FR-011 |
| `backend/tests/catalog/stage-02-revoke-rotate-availability.sql` | Assert `set_ai_availability` and `get_ai_availability` are absent. | FR-011 |
| `backend/tests/catalog/stage-06-verify-and-handoff.sql` | Stop reading `ai.availability`. | FR-011 |
| `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql` | Stop reading `ai.availability`. | FR-011 |
| `backend/tests/catalog/stage-06-issuer-guards.sql` | Stop reading `ai.availability`. | FR-011 |
| `e2e/fullstack/test/p5-2.test.mjs` | E2E-P5.2-01 through E2E-P5.2-11. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-012, FR-014, FR-015, FR-016 |
| `.github/workflows/ci.yml` | The `fullstack` job runs `npm test` (P5.1) and then this unit's command. | FR-001, FR-016 |

Inside the migration:

- `CREATE EXTENSION IF NOT EXISTS pg_cron` and `CREATE EXTENSION IF NOT EXISTS pg_net`.
- `auth_internal.pull_coverage_feed()` returns `void`. It is the cron command and the function an accepted refresh calls. `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, and `service_role`. No public wrapper.
- One cron job, name `ai_coverage_feed_pull`, schedule `30 seconds`, command `SELECT auth_internal.pull_coverage_feed()`.
- `public.get_ai_status(p_contract_version integer)`, `public.get_ai_billing_status(p_contract_version integer)`, and `public.request_ai_status_refresh(p_contract_version integer)` are `SECURITY DEFINER`, granted to `authenticated`, and delegate to `auth_internal` after the version check. The `auth_internal` bodies are not granted.
- Results match [contracts/status-rpc-results.md](./contracts/status-rpc-results.md).

`pull_coverage_feed` in one transaction:

1. If `pending_request_id` is set and `net._http_response` has no row and `pending_since` is within 5 minutes, return.
2. If that pending response is missing after 5 minutes, or the response row's `created` is older than 5 minutes, clear the pending id, increment `consecutive_failures`, and do not read the body.
3. Otherwise, when a response row exists, require HTTP 200, body `contract_version` equal to the version this pull sent, and header `Aip-Contract-Version` equal to that same version. Require body `after` equal to `cursor` and strictly ascending `feed_seq`, each greater than `after`. A 400 `contract_version_unsupported` body, a timeout, or any other failed check increments `consecutive_failures`, leaves `cursor` and the projection unchanged, and clears the pending id. `last_success_at` is not updated, so status is stale once that timestamp is older than 2 minutes.
4. On success, upsert each event under the ordering rule in [data-model.md](./data-model.md). Then set `cursor` to `next_after`, `last_success_at` to `now()`, `consecutive_failures` to 0, and clear the pending id.
5. Issue `net.http_get` for the next page unless step 1 returned. The URL is `ai.platform_base_url` plus `/v1/feed/coverage?after=<cursor>&limit=200`, with a loopback host rewritten to `host.docker.internal` ([research.md](./research.md)). The bearer token is `auth_internal.issue_feed_token()`. The header `Aip-Contract-Version` is `platformFeed.current` from `ai.contract_versions`. Store the returned id and `pending_since = now()`. The timeout argument is omitted, so `pg_net` uses 5000 ms.

The four availability migration files named in 04 §3.1 are not edited. `ai-platform/` and `abo/src/` are not edited. `e2e/fullstack/package.json` is not edited. `npm test` in that package stays the P5.1 file.

## Test Layout

### H-FS

File: `e2e/fullstack/test/p5-2.test.mjs`. The runner creates real Auth users with supabase-js, signs in, and calls the RPCs as those users. Membership roles exercised are `administrator`, `doctor`, `receptionist`, and `lab_staff`. Owner SQL uses `psql` and `DB_URL`. Platform D1 writes use the local database the H-FS platform already persists. The stack is the one `e2e/fullstack/test/p5-1.test.mjs` starts: local Supabase, platform `startWorker` on port 8787, harness worker with the `PLATFORM` binding, ABO `wrangler dev` on port 8788, and the Paymob stub on port 8789. This file does not import that test.

Epoch, sequence, and band 90 fixtures are rows in platform `coverage_event`. The test does not insert `ai_internal.clinic_ai_coverage`. The pull applies them. E2E-P5.2-06 sets `platformFeed.current` to a version the running platform rejects for that pull only, then restores it. E2E-P5.2-09 reads `subscriptionRef` from `packages/vendor-contracts` at run time.

Unit command, from `e2e/fullstack/`:

```bash
node --import tsx --test test/p5-2.test.mjs
```

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P5.2-01 | H-FS | Title `E2E-P5.2-01 Grant applied on the platform reaches get_ai_status available and active`. A `grant_applied` event is on the live feed. `cron.job` for `ai_coverage_feed_pull` has schedule `30 seconds`. The runner calls `auth_internal.pull_coverage_feed`. `get_ai_status(1)` is available and `active` and `contract_version` is 1. The accepted page echoed the sent feed version on `Aip-Contract-Version` and `contract_version`. |
| E2E-P5.2-02 | H-FS | Title `E2E-P5.2-02 Refresh starts a pull and a second call within 10 seconds is RATE_LIMITED`. An administrator `request_ai_status_refresh(1)` returns `contract_version` 1 and `data.requested_at`, and a pull was requested. An immediate second call returns `RATE_LIMITED` and leaves `requested_at` unchanged. After owner SQL sets `requested_at` to 10 seconds ago, another call is accepted. `request_ai_status_refresh()` and `request_ai_status_refresh(2)`, including with no session, return `CONTRACT_VERSION_UNSUPPORTED` and do not write `status_refresh` or request a pull. |
| E2E-P5.2-03 | H-FS | Title `E2E-P5.2-03 Stored dates move status to grace then lapsed while the platform and ABO are stopped`. Workers are stopped. Dates placed against the database clock make `get_ai_status(1)` `grace`, then `lapsed`, with no sleep. `last_success_at` older than 2 minutes makes `stale` true and includes `status_stale`. |
| E2E-P5.2-04 | H-FS | Title `E2E-P5.2-04 ends_soon at 7, 3, and 1 days when queued_count is 0, and staff billing status is FORBIDDEN_ROLE`. Staff `get_ai_status(1)` has no price fields. `ends_soon` is present at those three `days_left` values only when `queued_count = 0`, and absent when `queued_count > 0`. Staff `get_ai_billing_status(1)` returns `FORBIDDEN_ROLE`. |
| E2E-P5.2-05 | H-FS | Title `E2E-P5.2-05 Epoch 2 sequence 1 replaces epoch 1 sequence 9`. The pull applies the newer pair. An older pair leaves the stored row unchanged. |
| E2E-P5.2-06 | H-FS | Title `E2E-P5.2-06 Unsupported feed version keeps the cursor and does not write the projection`. `consecutive_failures` increases. `get_ai_status` is stale. The projection row is unchanged. The setting is restored. |
| E2E-P5.2-07 | H-FS | Title `E2E-P5.2-07 Disabled pull is stale and feedConsumerHealth shows the lag`. `cron.job.active` is false. `last_success_at` is older than 2 minutes. `feed_consumer.last_pull_at` is 5 minutes back. `get_ai_status` is stale. `feedConsumerHealth` returns that `last_pull_at`. |
| E2E-P5.2-08 | H-FS | Title `E2E-P5.2-08 Cursor reset to 0 reproduces the projection`. Owner SQL sets `feed_state.cursor` to 0. The same pull leaves the projection identical. |
| E2E-P5.2-09 | H-FS | Title `E2E-P5.2-09 SQL subscription ref equals the package vector and the ABO and platform values`. The runner compares `get_ai_billing_status(1)` `subscription_ref` with `subscriptionRef(org)` from `packages/vendor-contracts` and with the subscription ref the local ABO and platform return for that org. The test source does not contain a copied vector. |
| E2E-P5.2-10 | H-FS | Title `E2E-P5.2-10 Supabase stopped during a payment still provisions and status catches up`. With Supabase up, an administrator opens a checkout. Supabase is stopped. The Paymob stub payment is posted to ABO `POST /notify/paymob` and the platform grant completes. Supabase is started. The pull runs. `get_ai_status` is available and `active`. |
| E2E-P5.2-11 | H-FS | Title `E2E-P5.2-11 Band 90 yields allowance_low for every role`. After the pull, `get_ai_status(1)` for `administrator`, `doctor`, `receptionist`, and `lab_staff` includes notice `allowance_low`. |

## Sequencing

Tests before implementation. Each new test is observed failing before the code that makes it pass. 38 steps.

1. Add `e2e/fullstack/test/p5-2.test.mjs` with the H-FS stack and E2E-P5.2-01. Run the unit command. It fails.
2. Add E2E-P5.2-02. Run the unit command. It fails.
3. Add E2E-P5.2-03. Run the unit command. It fails.
4. Add E2E-P5.2-04. Run the unit command. It fails.
5. Add E2E-P5.2-05. Run the unit command. It fails.
6. Add E2E-P5.2-06. Run the unit command. It fails.
7. Add E2E-P5.2-07. Run the unit command. It fails.
8. Add E2E-P5.2-08. Run the unit command. It fails.
9. Add E2E-P5.2-09. Run the unit command. It fails.
10. Add E2E-P5.2-10. Run the unit command. It fails.
11. Add E2E-P5.2-11. Run the unit command. It fails.
12. Add `20261007230000_coverage_feed_puller_status.sql` with `pg_cron`, `pg_net`, `clinic_ai_coverage`, `feed_state`, and `status_refresh` as in [data-model.md](./data-model.md). Insert the `feed_state` singleton. RLS deny-all. No clinic grants.
13. In that migration, drop `get_ai_availability` and `set_ai_availability` in `public` and `auth_internal`, and delete the `ai.availability` settings row. Do not edit the four older availability migrations.
14. Update `backend/tests/catalog/harness.sql` and `harness-smoke.sql` so they do not require `ai.availability`.
15. Update `stage-02-availability-and-enroll.sql` so it expects `get_ai_availability` and `ai.availability` to be absent.
16. Update `stage-02-revoke-rotate-availability.sql` so it expects `set_ai_availability` and `get_ai_availability` to be absent.
17. Update the three stage-06 catalog files so they do not read `ai.availability`.
18. Add `auth_internal.pull_coverage_feed`: feed token, loopback rewrite, `Aip-Contract-Version` from `platformFeed.current`, `net.http_get`, and the stored pending id. Revoke execute from clinic roles.
19. Add the response checks, the 5-minute abandon, and failure counting. A failed page does not write the projection and does not move `cursor`.
20. Add the ordering upsert, `cursor = next_after`, `last_success_at = now()`, and `consecutive_failures = 0` on success.
21. Schedule `ai_coverage_feed_pull` at `30 seconds`.
22. Add `get_ai_status` in `public` and `auth_internal`: version check, every member, the read-time state, `reason`, `days_left`, `as_of`, `stale`, and `platform_base_url`.
23. Add the notice records from [contracts/status-rpc-results.md](./contracts/status-rpc-results.md).
24. Add `get_ai_billing_status`: administrator, `FORBIDDEN_ROLE` otherwise, the flat fields, and the SQL subscription ref.
25. Add `request_ai_status_refresh`: version refusal before authentication, `FORBIDDEN_ROLE`, the 10-second clock, `RATE_LIMITED` with no pull, and an accepted call that stores `requested_at` and runs `pull_coverage_feed`.
26. In `.github/workflows/ci.yml`, after `npm test` in `e2e/fullstack`, run `node --import tsx --test test/p5-2.test.mjs`. Leave `npm test` on the P5.1 file.
27. Run the unit command. E2E-P5.2-01 passes.
28. E2E-P5.2-02 passes.
29. E2E-P5.2-03 passes.
30. E2E-P5.2-04 passes.
31. E2E-P5.2-05 passes.
32. E2E-P5.2-06 passes.
33. E2E-P5.2-07 passes.
34. E2E-P5.2-08 passes.
35. E2E-P5.2-09 passes.
36. E2E-P5.2-10 passes.
37. E2E-P5.2-11 passes.
38. Run the unit command once and confirm E2E-P5.2-01 through E2E-P5.2-11 pass. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation is recorded for this unit in 02 §7. Nothing to justify.
