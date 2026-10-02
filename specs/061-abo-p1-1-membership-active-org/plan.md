# Implementation Plan: Membership, active organisation and current_org_id()

**Branch**: `ai/061-abo-p1-1-membership-active-org` | **Date**: 2026-10-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/061-abo-p1-1-membership-active-org/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P1.1 gives the backend a membership row `(user_id, organization_id, role)` and one active organisation per session, then makes `current_org_id()` return that organisation only while the membership still exists. It sits in phase P1 (tenancy retrofit), size L, with **Depends** none, and it runs in parallel with P2.x, P3.x, and P4.1.

The work is one new PostgreSQL migration on the existing Supabase project: the two `ai_internal` tables, the access-token hook's `active_org` claim, `set_active_organization`, `current_org_id()`, `current_membership_role()`, and a re-point of `public.jwt_organization_id()`. A new backend CI job runs that database's H-BK suites.

## Technical Context

**Language/Version**: PostgreSQL 15 SQL (`backend/supabase/config.toml` `major_version`) on the Supabase CLI local stack.

**Primary Dependencies**: The existing custom access-token hook `public.get_custom_claims(jsonb)` registered at `[auth.hook.custom_access_token]` in `backend/supabase/config.toml`; `auth_internal.build_staff_claims(uuid)`; `public.request_jwt_claims()`; `public.rpc_result`, `public.rpc_success(jsonb)`, and `public.rpc_error(text, text)`; `public.staff_role`; the existing `ai_internal` schema from `20260801120000_ai_keystore_schema.sql`.

**Storage**: Supabase PostgreSQL. `ai_internal.membership` and `ai_internal.user_active_organization` (03 §4). No copy of either table (FR-001).

**Testing**: Harness H-BK. New psql file `backend/tests/membership_active_org.sql` for E2E-P1.1-01 through E2E-P1.1-07. E2E-P1.1-08 is `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` on local Supabase. Tests are written to fail before the migration exists.

**Target Platform**: Clinic Supabase/PostgreSQL backend. CI runs the same migrations on local Supabase (FR-009, rule V1, rule V7).

**Project Type**: Backend SQL migration, functions, H-BK tests, and one job added to the existing `.github/workflows/ci.yml`. Codebase cell: backend. The CI workflow is the job FR-009 names; this unit does not change Flutter, the AI Platform, or the ABO.

**Performance Goals**: `current_org_id()` re-checks membership on every call with one primary-key lookup (FR-005). The unit is sized for a small-to-mid clinic (constitution I, 02 §7 principle I). No separate throughput target is set.

**Constraints**: One codebase (rule S3). Re-point `public.jwt_organization_id()`; leave the 115 dependent policy and RPC bodies in place (rule S5, FR-008). The active organisation changes only through `set_active_organization` (OQ-2). Billing authority is the membership role `administrator` (FR-007, T-2). Pre-existing H-BK claims and assertions stay as they are (FR-009). A JWT with no `active_org` claim falls back to `organization_id`, and the membership re-check still applies (FR-005). Enrollment, `/control/entitle`, and entitlement, plan, and invoice tables stay until their owning units (rule S9).

**Scale/Scope**: Size L (rule S3, 32–40 tasks, 3 user stories, one codebase). One membership per existing staff user per organisation, and one active-organisation row per user.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no research phase. The Phase 1 artifacts (`data-model.md`, `contracts/`) use the same placement as this check.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  Clinic-scale backend tenancy (spec §4.1, 02 §7 principle I). One membership and one active organisation per user. No hospital-scale or enterprise requirement.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  Tables and functions in the existing Supabase PostgreSQL database. The access-token hook is the hook already registered in `config.toml`. The CI job is another job in the existing workflow. 02 §7 principle I: no microservices, queues, or Kubernetes.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  PostgreSQL holds the tables, `current_org_id()`, `current_membership_role()`, and the re-pointed `public.jwt_organization_id()`. Supabase Auth calls `public.get_custom_claims`. `set_active_organization` is a PostgREST RPC. Flutter and the AI path are untouched (02 §7 principle II).

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  Membership and the active-organisation row are written by the definer hook helper and by `set_active_organization` (03 §1, FR-001, FR-004). Primary keys and foreign keys enforce the row shape. Deny-all RLS keeps clients off both tables (constitution III, 02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  `current_org_id()` re-checks a live membership on every call; that is tenant-isolation layer 1 (02 §4.3, 02 §2 TB-4). Existing branch claims and `public.jwt_branch_ids()` stay. `set_active_organization` requires a membership and returns `FORBIDDEN` without one. `user_active_organization.updated_at` and `membership.created_at` are the timestamps the design names. Application flows gain no delete path; existing soft-delete behaviour on clinical tables is unchanged (constitution IV). E2E-P1.1-04 deletes a membership row inside the test so the re-check can be observed.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  This unit adds no AI action and no credential for the ABO or the platform (02 §7 principles II and V). Clinical work does not call these functions.

## Project Structure

### Documentation (this feature)

```text
specs/061-abo-p1-1-membership-active-org/
├── plan.md
├── spec.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── current-org-id.md
│   ├── current-membership-role.md
│   └── set-active-organization.md
└── tasks.md                   # /abo-tasks, not this phase
```

`research.md` is omitted. **Spikes** is `None`; the cited design is the research (rule S6).

`data-model.md` records `membership` and the active-organisation record because the spec defines those entities.

`contracts/` records the frozen function semantics and the `set_active_organization` result body. Later units bind to the function files (P1.2, P5.1, P5.2).

#### quickstart.md outline

Implement writes `quickstart.md` after the H-BK runs below are green. Sections:

1. What was implemented — membership, the active-organisation record, the `active_org` claim, `set_active_organization`, `current_org_id()`, `current_membership_role()`, the re-point of `public.jwt_organization_id()`, fixture membership rows, and the backend CI job.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests — the H-BK commands in Test Layout. E2E-P1.1-08's command is the two scripts the spec names for that id.
4. Entry point → module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P1.1-01 | `[auth.hook.custom_access_token]` → `public.get_custom_claims(jsonb)` → `auth_internal.build_staff_claims` and `auth_internal.sync_active_organization` → `ai_internal.membership` and `ai_internal.user_active_organization` → claim `active_org` → `public.current_org_id()` |
| E2E-P1.1-02 | `public.set_active_organization` → `ai_internal.user_active_organization` → `public.get_custom_claims(jsonb)` → `public.current_org_id()` → `public.jwt_organization_id()` → `public.list_appointments` |
| E2E-P1.1-03 | `public.set_active_organization` → `public.rpc_error('FORBIDDEN', …)` with `ai_internal.user_active_organization` unchanged → `public.get_custom_claims(jsonb)` emits the same `active_org` |
| E2E-P1.1-04 | Delete the membership row → `public.current_org_id()` NULL → `SELECT` on `public.branches` (policy calls `public.jwt_organization_id()`) returns 0 rows → `public.list_appointments` raises `FORBIDDEN` through `auth_internal.assert_appointment_branch` |
| E2E-P1.1-05 | psql `request.jwt.claims` with a crafted `active_org` or `organization_id` and no membership → `public.current_org_id()` NULL |
| E2E-P1.1-06 | `public.current_membership_role()` for an `administrator` membership and a `doctor` membership → `UPDATE public.roles_permissions` → the function returns the same roles |
| E2E-P1.1-07 | psql read of `ai_internal.membership` against `public.staff_members` and `public.organizations` after migrations |
| E2E-P1.1-08 | `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` |

### Source Code (repository root)

```text
backend/
├── supabase/
│   ├── config.toml
│   └── migrations/
│       └── 20261002120000_membership_active_org.sql
└── tests/
    ├── membership_active_org.sql
    ├── run_all_backend_tests.sh
    └── catalog/
        └── run.sh

.github/workflows/ci.yml
```

`backend/supabase/config.toml` and `backend/tests/catalog/run.sh` stay as they are. The hook URI is already `pg-functions://postgres/public/get_custom_claims`. Fixture files under `backend/tests/` that gain a membership `INSERT` are listed in Files.

**Structure Decision**: Backend only. The new migration is the next timestamp after `20260905120600_revoke_fresh_return_stored_revoked_at.sql` (rule S7). Historical migration files stay untouched. `public.jwt_organization_id()`, `public.get_custom_claims(jsonb)`, and the new functions are `CREATE OR REPLACE` in the new migration.

## Consumes Binding

None.

## Files

| File | FR |
| --- | --- |
| `specs/061-abo-p1-1-membership-active-org/data-model.md` | FR-001, FR-002, FR-003 |
| `specs/061-abo-p1-1-membership-active-org/contracts/current-org-id.md` | FR-005, FR-006, FR-008 |
| `specs/061-abo-p1-1-membership-active-org/contracts/current-membership-role.md` | FR-007 |
| `specs/061-abo-p1-1-membership-active-org/contracts/set-active-organization.md` | FR-004 |
| `specs/061-abo-p1-1-membership-active-org/quickstart.md` (implement, after verification) | FR-001–FR-009 |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `backend/tests/membership_active_org.sql` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-008 |
| `backend/tests/run_all_backend_tests.sh` | FR-009 |
| `.github/workflows/ci.yml` | FR-009 |

The migration contains only:

- `ai_internal.membership` and the FR-002 backfill.
- `ai_internal.user_active_organization`.
- `auth_internal.sync_active_organization(uuid)` and `CREATE OR REPLACE` of `public.get_custom_claims(jsonb)`. The renamed `public.get_staff_claims_for_user(uuid)` stays. A `get_custom_claims(uuid)` overload is not recreated (`jwt_claims_contract.sql` asserts it is absent). `auth_internal.build_staff_claims` keeps emitting `organization_id` as the first organisation (T-1) so existing claim assertions stay valid.
- `public.current_org_id()`, `public.current_membership_role()`, and `CREATE OR REPLACE` of `public.jwt_organization_id()` as `SELECT public.current_org_id()`.
- `public.set_active_organization(uuid)`.
- Grants from the contracts: `EXECUTE` on `auth_internal.sync_active_organization(uuid)` to `supabase_auth_admin`; `EXECUTE` on `public.current_org_id()`, `public.current_membership_role()`, and `public.set_active_organization(uuid)` to `authenticated`. Both tables stay deny-all, with no privilege for `anon`, `authenticated`, or `service_role`.

FR-009 fixture edits, each file traced to FR-009. For every impersonated fixture user whose `request.jwt.claims` includes `organization_id` and who has a `public.staff_members` row, insert `ai_internal.membership (user_id, organization_id, role)` with that claim's `sub`, that claim's `organization_id`, and that staff row's `role`. Insert it in the same fixture setup that inserts the staff row, after the backfill has already run. Leave the claim JSON and the assertions unchanged. An impersonation that has no staff row stays without a membership, so its denial assertion still holds.

- `backend/tests/admin_reset_staff_password.sql`
- `backend/tests/admin_update_staff_username.sql`
- `backend/tests/ai_acceptance_recording.sql`
- `backend/tests/ai_keystore_rls.sql`
- `backend/tests/appointment_calendar_backend_integrity.sql`
- `backend/tests/appointment_get_update.sql`
- `backend/tests/appointment_management_crud.sql`
- `backend/tests/appointment_management_patient_filter.sql`
- `backend/tests/appointment_management_rls.sql`
- `backend/tests/appointment_queue_qa.sql`
- `backend/tests/appointment_simplified_booking_slots.sql`
- `backend/tests/appointments_patient_mrn_payload_test.sql`
- `backend/tests/auth_rbac_extended.sql`
- `backend/tests/auth_security_extensions.sql`
- `backend/tests/billing_concurrency.sql`
- `backend/tests/billing_crud.sql`
- `backend/tests/billing_rls.sql`
- `backend/tests/bootstrap_rpc.sql`
- `backend/tests/context_provider_rpc.sql`
- `backend/tests/create_staff_rpc.sql`
- `backend/tests/delete_staff_member.sql`
- `backend/tests/dev_reset_clinic_installation.sql`
- `backend/tests/invoices_patient_mrn_payload_test.sql`
- `backend/tests/org_branch_management_crud.sql`
- `backend/tests/org_branch_management_extended.sql`
- `backend/tests/org_branch_management_rls.sql`
- `backend/tests/patient_management_concurrent.sql`
- `backend/tests/patient_management_crud.sql`
- `backend/tests/patient_management_extended.sql`
- `backend/tests/patient_management_rls.sql`
- `backend/tests/patient_management_roles.sql`
- `backend/tests/patient_management_search_advanced.sql`
- `backend/tests/patient_management_search_filters.sql`
- `backend/tests/patient_mrn_generation.sql`
- `backend/tests/patient_mrn_reassign.sql`
- `backend/tests/patient_transfer_restore.sql`
- `backend/tests/patient_visit_attachments_list.sql`
- `backend/tests/rls_isolation.sql`
- `backend/tests/role_permissions_matrix.sql`
- `backend/tests/service_catalog_concurrency.sql`
- `backend/tests/service_catalog_crud.sql`
- `backend/tests/service_catalog_list.sql`
- `backend/tests/service_catalog_pricing.sql`
- `backend/tests/service_catalog_rls.sql`
- `backend/tests/settings_code_review_fixes.sql`
- `backend/tests/shift_management_concurrency.sql`
- `backend/tests/shift_management_crud.sql`
- `backend/tests/shift_management_rls.sql`
- `backend/tests/staff_sign_in_after_create.sh`
- `backend/tests/visit_attachment_delete_storage.sql`
- `backend/tests/visit_attachment_storage_rls.sql`
- `backend/tests/visit_documentation_complete_validation.sql`
- `backend/tests/visit_encounter_workspace_crud.sql`
- `backend/tests/visit_encounter_workspace_rls.sql`
- `backend/tests/visit_medical_records_crud.sql`
- `backend/tests/visit_medical_records_rls.sql`
- `backend/tests/visit_predefined_vital_signs_backfill.sql`
- `backend/tests/catalog/stage-02-availability-and-enroll.sql`
- `backend/tests/catalog/stage-02-revoke-rotate-availability.sql`
- `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql`
- `backend/tests/catalog/stage-06-issuer-guards.sql`
- `backend/tests/catalog/stage-08-context-provider-rpc.sql`
- `backend/tests/catalog/stage-11-record-ai-acceptance.sql`

`ON DELETE CASCADE` from `auth.users` and `public.organizations` lets existing fixture teardown that deletes those parents remove the new rows. `backend/tests/jwt_claims_contract.sql` and `backend/tests/auth_flow_smoke.sh` keep their current assertions: the former reads `build_staff_claims` and does not impersonate `organization_id`; the latter checks that a real sign-in JWT still carries `organization_id`, which `build_staff_claims` still sets.

The CI job `backend-sql` is added to `.github/workflows/ci.yml` and leaves the existing jobs in place (rule V7). It checks out the repo, installs the Supabase CLI, runs `supabase start` in `backend/` (that applies all migrations, including the hook in `config.toml`), then runs `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh`.

## Test Layout

Titles start with the E2E id (rule V3). E2E-P1.1-01 through E2E-P1.1-07 live in `backend/tests/membership_active_org.sql` and fail until the migration exists. The file is registered from `run_all_backend_tests.sh` so the CI job runs it.

Teardown: the `AFTER INSERT` trigger `trg_organizations_provision_billing_settings` (from `20260605180000_billing.sql`, a historical migration that stays untouched) provisions a `public.organization_billing_settings` row for every fixture organisation, and its foreign key to `public.organizations` has no `ON DELETE CASCADE`. Every fixture cleanup and teardown in `membership_active_org.sql` therefore deletes `public.organization_billing_settings` for the fixture organisations before deleting from `public.organizations`, matching the pattern in `backend/tests/billing_rls.sql` and `backend/tests/service_catalog_crud.sql`.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P1.1-01 | H-BK | `membership_active_org.sql`: one membership, call `public.get_custom_claims` with the GoTrue event shape `{"user_id","claims"}`, assert `active_org`, then `current_org_id()` equals that organisation. |
| E2E-P1.1-02 | H-BK | `membership_active_org.sql`: memberships in A and B, `set_active_organization(B)`, hook refresh, `current_org_id()` equals B, `public.list_appointments` returns only B's rows. |
| E2E-P1.1-03 | H-BK | `membership_active_org.sql`: `set_active_organization(C)` returns `success = false` and `error_code = 'FORBIDDEN'`; the active-organisation row and the following hook claim stay as they were. |
| E2E-P1.1-04 | H-BK | `membership_active_org.sql`: delete the membership while the impersonated claims remain; `current_org_id()` is NULL; a `public.branches` select returns 0 rows; `public.list_appointments` raises `FORBIDDEN`. |
| E2E-P1.1-05 | H-BK | `membership_active_org.sql`: crafted `active_org` and, separately, crafted `organization_id`, each with no membership; `current_org_id()` is NULL. |
| E2E-P1.1-06 | H-BK | `membership_active_org.sql`: `current_membership_role()` returns `administrator` and `doctor`; an `UPDATE` on `public.roles_permissions` leaves both results unchanged. |
| E2E-P1.1-07 | H-BK | `membership_active_org.sql`: after migrations, every non-deleted staff member whose database has a non-deleted organisation has exactly one membership for the earliest such organisation and that staff member's role. A non-deleted staff member and no organisation — the bootstrap administrator from `20260516100400_auth_rbac_seed.sql` on a fresh database — has no membership row. |
| E2E-P1.1-08 | H-BK | `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh`. Pre-existing suites pass with the same impersonated claims and the same assertions. Fixture users who carry `organization_id` also hold the matching membership. Suites that impersonate a user with no staff row still assert denial. |

## Sequencing

Tests are written and observed failing before the migration and the fixture inserts.

1. Add `backend/tests/membership_active_org.sql` with E2E-P1.1-01 through E2E-P1.1-07, and register it from `run_all_backend_tests.sh`. Run the file against local Supabase before the migration. It fails because `ai_internal.membership`, `current_org_id()`, and `set_active_organization` are absent.
2. Add `20261002120000_membership_active_org.sql` and make E2E-P1.1-01 through E2E-P1.1-07 pass.
3. Add the FR-009 membership inserts, grouped by the domain sections already in `run_all_backend_tests.sh` (auth/RBAC, org/branch, patient, appointment, visit, billing, service catalog, shift, catalog stages, and the remaining settings, dev-reset, role-matrix, and staff sign-in files). One repeated insert per fixture user; one task group per domain section.
4. Run E2E-P1.1-08 (`run_all_backend_tests.sh` and `catalog/run.sh`) and keep going until both are green.
5. Add the `backend-sql` CI job and write `quickstart.md` from the outline above.

The fixture insert is one change repeated across the files in Files, grouped as one task per existing runner section so the tasks phase does not emit one task per file. With the failing test file, the migration, those groups, the CI job, and `quickstart.md`, the implied count stays at or under 40. It is not padded upward.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
