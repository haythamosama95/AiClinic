# Implementation Plan: Read-time status, notices and billing status

**Branch**: `ai/088b-abo-p5-2b-read-time-status-notices` | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/088b-abo-p5-2b-read-time-status-notices/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

`get_ai_status` computes grace, lapse, `reason`, `days_left`, `as_of`, and the closed notice records at read time from the P5.2a projection, and `get_ai_billing_status` returns that same view plus the administrator billing fields. This is phase P5, size S, and **Depends** P5.2a. It runs in parallel with P4.x.

## Technical Context

**Language/Version**: PostgreSQL on local Supabase. The H-FS runner is Node in `e2e/fullstack/`, using the existing `node --import tsx --test` entry.

**Primary Dependencies**: The P5.2a projection and `public.get_ai_status(integer)` already created in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`. `public.rpc_result` with `contract_version`, `public.rpc_success`, and `public.rpc_error` from `20261007180000_issuer_key_custody.sql`. `public.current_org_id()` and `public.current_membership_role()` (`public.staff_role`: `administrator`, `doctor`, `receptionist`, `lab_staff`). `extensions.digest` from `pgcrypto` (`20260516100000_auth_rbac_schema.sql`). `subscriptionRef` in `packages/vendor-contracts/src/identifiers.ts`, already called by `abo/src/clinic-api/billing-reads.ts` and `ai-platform/src/coverage-read/index.ts`. No new library.

**Storage**: No new table. Reads `ai_internal.clinic_ai_coverage` and `ai_internal.feed_state.last_success_at`. Reads `ai.platform_base_url` and `ai.abo_base_url` through the existing `auth_internal.ai_app_setting_text` helper. Does not write `clinic_ai_coverage.reason` or any other projection column.

**Testing**: H-FS only, one new file `e2e/fullstack/test/p5-2b.test.mjs`. Titles start with the E2E id (rule V3). Tests are written to fail before this migration. The file seeds `clinic_ai_coverage` and `feed_state` with `psql` and calls PostgREST. It does not start the platform or ABO workers, and it does not sleep the 2-minute stale window or a calendar day. `as_of` is checked against `now()` taken on that database immediately before the call and immediately after the response. `notices[]` is asserted by code, with no required array order.

**Target Platform**: Local Supabase. Clinic calls use PostgREST `public.get_ai_status` and `public.get_ai_billing_status`.

**Project Type**: Backend. The unit row names no wiring exception. H-FS (`e2e/fullstack/`) is the harness (06 §3 V1), not a second product codebase.

**Performance Goals**: One status read per call for the active organisation. No new cron, pull, or refresh.

**Constraints**: One new migration. One `auth_internal` reader returns the shared status view. `public.get_ai_status` and `public.get_ai_billing_status` are the `SECURITY DEFINER` wrappers. Each wrapper rejects a missing or unsupported `p_contract_version` before any role check, using the accepted set already on `public.get_ai_status`: null or a value other than `0` or `1` returns `CONTRACT_VERSION_UNSUPPORTED` and does not call the reader. That matches `ai.contract_versions.backendRpc` current `1`, minimum `0`. The billing wrapper then allows only `administrator` and adds the flat billing fields. `as_of` is PostgreSQL `now()` for that call, captured once and reused for `days_left`, `grace_days_left`, `next_change_at`, and `stale`. It is not `event_at`, `applied_at`, or `feed_state.last_success_at`, it is present when the projection row is absent, and it is not stored. `days_left` and `grace_days_left` are whole 24-hour days (`86400` seconds), floored. The H-FS day of 2 seconds (rule V4, OQ-5) is not applied inside the RPC; tests seed `ends_at` and `grace_ends_at` relative to database `now()` so the predicate holds on the read. `stale` stays true when `last_success_at` is null or strictly older than 2 minutes, which is the predicate P5.2a already shipped and which E2E-P5.2-06 and E2E-P5.2-07 assert at 121 seconds. A stored `active` row with `now < ends_at` still returns `available = true` and `state = active`, which E2E-P5.2-01 asserts. This unit does not edit the P5.2a migration, `request_ai_status_refresh`, or `auth_internal.pull_coverage_feed`.

**Scale/Scope**: Size S (rule S3: two user stories, one codebase). Four E2E ids: E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, E2E-P5.2-11. Implied task count is 13 (the sequencing below).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no `research.md`. The same boxes hold after the data model. This unit adds no constitution violation, so Complexity Tracking stays empty.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  A clinic member reads AI status for the active organisation. An administrator reads billing fields on that same status. Grace and lapse are results of stored dates (spec §4.1, 02 §7 principle I).

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The read is one PostgreSQL migration on the existing Supabase project. No new worker, queue, or cron (02 §7 principle I).

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Status, notices, `days_left`, `reason`, and billing fields are PostgreSQL functions reached through Supabase RPCs. Flutter is outside this unit. The pull and the projection stay the consumed P5.2a contract (spec §4.1, 02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  Coverage stays in non-exposed `ai_internal` and is read only through `SECURITY DEFINER` functions keyed on `current_org_id()`. The read does not update `clinic_ai_coverage.reason`. An unsupported contract version returns before the reader (spec §4.1, 02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `get_ai_status` is for every member of `current_org_id()`. `get_ai_billing_status` requires membership role `administrator` and otherwise returns `FORBIDDEN_ROLE` with no status payload. The version check runs before that role check. This unit deletes nothing (spec §4.1, 02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  With the platform and the ABO stopped, stored dates still move status to grace and then lapsed, and `stale` plus `status_stale` follow when `last_success_at` is more than 2 minutes old. This unit adds no model call (spec §4.1, 02 §7 principle V).

| Principle or rule | How this unit complies |
| --- | --- |
| I. Product fit and simplicity | One status read and one billing read on the existing database. No second deployable. |
| II. Replaceable layer boundaries | Codebase is backend. The Flutter app, the puller, and the workers are not modified. |
| III. Backend authority and data integrity | The view is computed in definer functions. Projection rows stay behind the existing deny-all RLS. |
| IV. Secure and human-gated operations | Billing fields require `administrator`. Staff status omits prices, payments, and references. |
| V. Operational continuity | Grace and lapse follow stored dates while vendor services are down. Clinical tables are not locked or deleted. |
| Workflow automation | No new cron and no DAG. The P5.2a pull schedule stays as it is. |
| Higher operational burden | No new operational part. The burden is the read-time view 04 §3.2 and §3.3 already name. |

## Project Structure

### Documentation (this feature)

```text
specs/088b-abo-p5-2b-read-time-status-notices/
├── plan.md
├── spec.md
├── escalations.md
├── data-model.md
├── contracts/
│   └── status-rpc.md
├── quickstart.md          # after the four H-FS tests are green; outline below
└── tasks.md               # tasks phase; not created here
```

`research.md` is omitted. Spikes are none.

`quickstart.md` is not written in this phase. After the harness is green, implement fills only these sections:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only: from `e2e/fullstack/`, `node --import tsx --test test/p5-2b.test.mjs`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour (none are expected)

### Source Code (repository root)

```text
backend/supabase/migrations/
└── 20261008010000_read_time_status_notices.sql

e2e/fullstack/test/
└── p5-2b.test.mjs
```

**Structure Decision**: Backend only. The new migration replaces `auth_internal.get_ai_status` and `public.get_ai_status` and adds `public.get_ai_billing_status`. H-FS coverage is the new Node test file. `e2e/fullstack/test/p5-2.test.mjs` and `20261007230000_coverage_feed_puller_status.sql` stay untouched.

## Consumes Binding

| Consumes | Existing module | This unit |
| --- | --- | --- |
| P5.2a pull | `auth_internal.pull_coverage_feed()` and cron job `ai_coverage_feed_pull` in `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | Not called and not modified |
| P5.2a projection | `ai_internal.clinic_ai_coverage` and `ai_internal.feed_state` in that migration. Status reads `organization_id`, `state`, `reason`, `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `band`, `queued_count`, `held_count`, `suspended`, `event_at`, `applied_at`, and `feed_state.last_success_at` | Read only. No `UPDATE` of those tables |
| `request_ai_status_refresh` | `auth_internal.request_ai_status_refresh(integer)` and `public.request_ai_status_refresh(integer)` in that migration | Not modified |
| CP-D | P5.2a checkpoint: a coverage event reaches `get_ai_status` through local Supabase. Already covered by `e2e/fullstack/test/p5-2.test.mjs` (`E2E-P5.2-01`) | Not re-implemented. The replacement reader must still return `available = true` and `state = active` for a stored `active` row while `now < ends_at` |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `specs/088b-abo-p5-2b-read-time-status-notices/data-model.md` | Create | FR-001, FR-004, FR-005, FR-006 |
| `specs/088b-abo-p5-2b-read-time-status-notices/contracts/status-rpc.md` | Create | FR-001, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` | Create. `CREATE OR REPLACE` `auth_internal.get_ai_status(integer)` as the shared reader (`STABLE`, `SECURITY DEFINER`, `search_path = public, auth_internal, ai_internal`). `CREATE OR REPLACE` `public.get_ai_status(integer)` with the version gate, then that reader. `CREATE` `public.get_ai_billing_status(integer)` (`SECURITY DEFINER`, `search_path = public, auth_internal, ai_internal, extensions`) with the version gate, then the `administrator` gate, then the shared view plus flat fields and `subscription_ref`. Revoke and grant `EXECUTE` the same way as `public.get_ai_status`: `authenticated` only | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `e2e/fullstack/test/p5-2b.test.mjs` | Create | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `specs/088b-abo-p5-2b-read-time-status-notices/quickstart.md` | Create after the four tests are green | FR-001, FR-006, FR-007 |

The reader is one function. The billing wrapper calls it and adds fields; it does not add a second status implementation. `subscription_ref` is computed in that wrapper: UTF-8 SHA-256 of `sub-ref:` concatenated with `current_org_id()::text`, Crockford base-32 (alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, same bit packing as `crockfordEncode` in `packages/vendor-contracts/src/identifiers.ts`), first 8 characters, prefix `AIC-`. The package vector for org `7c9e6679-7425-40de-944b-e07fc1f90ae7` is `AIC-2W3W7P9G` (`packages/vendor-contracts/vectors/identifiers.json`).

## Test Layout

Harness H-FS. File `e2e/fullstack/test/p5-2b.test.mjs`. Command, from `e2e/fullstack/`: `node --import tsx --test test/p5-2b.test.mjs`. Each test is red before `20261008010000_read_time_status_notices.sql` is applied. The fixture signs in through local Supabase (`create_staff_account` for each `public.staff_role`) and does not import `wrangler` or call `startWorker`.

| ID | Title prefix | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P5.2-03 | `E2E-P5.2-03` | PostgREST `public.get_ai_status` → version gate → `auth_internal.get_ai_status` | Workers are not started. Seeded `active` or `grace` with `queued_count` not greater than 0: after `ends_at`, state is `grace` while `now < grace_ends_at`, then `lapsed`. `reason` is null in grace and `expired` on that clock lapse. `notices[]` includes `in_grace` with `grace_days_left` during grace, and `lapsed` once lapsed. `last_success_at` older than 2 minutes makes `stale` true and adds `status_stale`. `contract_version` echoes the request. `as_of` lies between the database `now()` taken immediately before the call and immediately after the response, and is not a seeded `event_at`, `applied_at`, or `last_success_at` |
| E2E-P5.2-04 | `E2E-P5.2-04` | PostgREST `public.get_ai_status` and `public.get_ai_billing_status` | `ends_soon` when `days_left` is 7, 3, or 1 and `queued_count = 0`. A null `days_left` does not add `ends_soon`. Staff `get_ai_status` data has no price, payment, or reference keys (`subscription_ref`, `term_ref`, `abo_base_url`, plan, allowance). A non-administrator `get_ai_billing_status` returns `success = false`, `error_code = FORBIDDEN_ROLE`, and null `data`. A missing `p_contract_version` and version `2` on either RPC return `CONTRACT_VERSION_UNSUPPORTED` and leave `clinic_ai_coverage.reason` unchanged |
| E2E-P5.2-09 | `E2E-P5.2-09` | PostgREST `public.get_ai_billing_status` → shared reader → SQL `subscription_ref` | For the clinic org, SQL `subscription_ref` equals `await subscriptionRef(orgId)` from `vendor-contracts`. That function is the value `abo/src/clinic-api/billing-reads.ts` and `ai-platform/src/coverage-read/index.ts` return for the same org. Success `data` also carries the other flat billing fields. `contract_version` echoes the request. Workers stay stopped |
| E2E-P5.2-11 | `E2E-P5.2-11` | PostgREST `public.get_ai_status` for each `public.staff_role` | Seeded `band` `90`: every role's `notices[]` includes `allowance_low` as `{code, audience: member, channel: in_app}` with no `grace_days_left` key |

## Sequencing

Tests before the migration. The four tests are observed failing on the current `get_ai_status` (no grace clock, no notices, no `days_left`) and on the absent `get_ai_billing_status`. Implied task count: 13.

1. Add `e2e/fullstack/test/p5-2b.test.mjs` with the local Supabase clinic fixture and SQL seed helpers. Do not start workers.
2. Add the failing `E2E-P5.2-03` test.
3. Add the failing `E2E-P5.2-04` test.
4. Add the failing `E2E-P5.2-09` test.
5. Add the failing `E2E-P5.2-11` test.
6. Run `node --import tsx --test test/p5-2b.test.mjs` and confirm those four tests fail.
7. Add `20261008010000_read_time_status_notices.sql`: replace `auth_internal.get_ai_status` with the read-time view (state clock, `reason`, `days_left`, notices, `as_of`, `stale`, `next_change_at`, `band`, `platform_base_url`).
8. Replace `public.get_ai_status` so the version gate runs, then the reader. No role gate. No prices, payments, or references.
9. In that migration, compute `subscription_ref` with the package algorithm above.
10. Add `public.get_ai_billing_status`: version gate, then `administrator`, else `FORBIDDEN_ROLE` with null data; success data is the shared view plus the flat fields, with no `remaining` key.
11. `REVOKE`/`GRANT` `EXECUTE` on `public.get_ai_billing_status(integer)` to `authenticated` only.
12. Re-run `node --import tsx --test test/p5-2b.test.mjs` until E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11 pass.
13. Write `quickstart.md` from the outline in Project Structure.

## Complexity Tracking

No constitution violation is recorded in 02 §7 for this unit. Nothing to justify.
