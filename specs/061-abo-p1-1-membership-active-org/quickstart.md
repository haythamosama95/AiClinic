# Membership and active organisation

**Unit**: P1.1 · **Harness**: H-BK · **Verification**: T024 green

## 1. What was implemented

PostgreSQL on the existing Supabase project is the authority for tenancy and membership (FR-001 through FR-009).

- **Membership.** `ai_internal.membership` stores `(user_id, organization_id, role)` plus `created_at`. The migration backfills one row per non-deleted staff member for the earliest non-deleted organisation and that staff member's role. A non-deleted staff member and no organisation — the bootstrap administrator on a fresh database — gets no row (FR-001, FR-002).
- **Active-organisation record.** `ai_internal.user_active_organization` stores one active organisation per user. The access-token hook `public.get_custom_claims(jsonb)` writes the `active_org` claim from the user's sole membership at sign-in and from that row after a successful switch (FR-003).
- **`set_active_organization`.** `public.set_active_organization(uuid)` is the only way to change the active organisation after sign-in. A live membership is required. Without one the call returns `success = false` and `error_code = 'FORBIDDEN'`, and the stored row stays as it was. The issued JWT updates on the next hook run (FR-004).
- **`current_org_id()`.** Returns the `active_org` claim, or the legacy `organization_id` claim when `active_org` is absent, only while a live membership `(sub, org)` exists. Otherwise it returns NULL. The organisation always comes from this function (FR-005, FR-006).
- **`current_membership_role()`.** Returns the membership role (`administrator`, `doctor`, `receptionist`, or `lab_staff`) for `(sub, current_org_id())`. Billing authority is the membership role `administrator`. The function does not read `public.roles_permissions` (FR-007).
- **`public.jwt_organization_id()`.** Re-pointed to `SELECT public.current_org_id()`. Existing RLS policies and tenant RPCs keep calling `public.jwt_organization_id()` and inherit the membership re-check (FR-008).
- **Fixture membership rows.** Each impersonated fixture user whose `request.jwt.claims` includes `organization_id` and who has a `public.staff_members` row receives `ai_internal.membership (user_id, organization_id, role)` in that fixture's staff setup. Claim JSON and assertions stay as they were. An impersonation with no staff row stays without a membership. `backend/tests/ai_token_contract_rotation.sql` restores `ai_internal.app_settings` key `ai.aat.ver` to `'"1"'::jsonb` before `COMMIT` so the shared local database still satisfies the catalog stage-06 seed (FR-009).
- **Backend CI job.** `.github/workflows/ci.yml` job `backend-sql` checks out the repo, installs the Supabase CLI, runs `supabase start` in `backend/` (all migrations, including the hook already registered in `backend/supabase/config.toml`), then runs `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh`. Existing jobs stay in place (FR-009).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/061-abo-p1-1-membership-active-org/data-model.md` | FR-001, FR-002, FR-003 |
| `specs/061-abo-p1-1-membership-active-org/contracts/current-org-id.md` | FR-005, FR-006, FR-008 |
| `specs/061-abo-p1-1-membership-active-org/contracts/current-membership-role.md` | FR-007 |
| `specs/061-abo-p1-1-membership-active-org/contracts/set-active-organization.md` | FR-004 |
| `specs/061-abo-p1-1-membership-active-org/quickstart.md` | FR-001–FR-009 |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `backend/tests/membership_active_org.sql` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-008 |
| `backend/tests/run_all_backend_tests.sh` | FR-009 |
| `backend/tests/ai_token_contract_rotation.sql` | FR-009 |
| `.github/workflows/ci.yml` | FR-009 |

FR-009 fixture membership inserts:

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

`backend/supabase/config.toml` and `backend/tests/catalog/run.sh` stay as they are. The hook URI is already `pg-functions://postgres/public/get_custom_claims`.

## 3. Harness command

Harness H-BK, from the repository root, against local Supabase (`supabase start` in `backend/`):

```bash
backend/tests/run_all_backend_tests.sh
backend/tests/catalog/run.sh
```

`backend/tests/run_all_backend_tests.sh` registers `membership_active_org.sql` (`run_sql_test "Membership active org"`), which asserts E2E-P1.1-01 through E2E-P1.1-07. E2E-P1.1-08 is both commands. Both scripts share that one local database.

## 4. How to inspect the change

Every scenario is asserted by H-BK. This file records those harness commands and where the objects live.

- Migration `backend/supabase/migrations/20261002120000_membership_active_org.sql`: `ai_internal.membership` and the backfill, `ai_internal.user_active_organization`, `auth_internal.sync_active_organization(uuid)`, `public.get_custom_claims(jsonb)`, `public.set_active_organization(uuid)`, `public.current_org_id()`, `public.current_membership_role()`, and `public.jwt_organization_id()` as `SELECT public.current_org_id()`.
- Hook entry: `[auth.hook.custom_access_token]` in `backend/supabase/config.toml` is `pg-functions://postgres/public/get_custom_claims`.
- CI: job `backend-sql` in `.github/workflows/ci.yml`.
- Fixture membership `INSERT`s sit in the staff setup of the files in section 2. `backend/tests/ai_token_contract_rotation.sql` restores `ai.aat.ver` to `'"1"'::jsonb` after its failure-check block and before `COMMIT`.

## 5. Entry point → module chain

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
