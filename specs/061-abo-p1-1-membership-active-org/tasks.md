# Tasks: Membership, active organisation and current_org_id()

**Input**: Design documents from `specs/061-abo-p1-1-membership-active-org/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `data-model.md`, `contracts/` (`AVAILABLE_DOCS`: `data-model.md`, `contracts/`). `research.md` is omitted (Spikes is None). `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id in the spec Test plan, written to fail before the migration and the fixture inserts. Test Layout names no extra test. Nothing ships before P8 (rule S2). No Setup phase: Files names no file that must exist before the tests. No Foundational phase (Consumes Binding is none). No Polish phase.

**Task count**: 25. Size L targets 32–40 (rule S3). The count is the honest list: eight E2E tests, the migration split across the three stories, one fixture-insert task per domain section in Sequencing, the `backend-sql` CI job, verification, and `quickstart.md`. It is not padded upward.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/supabase/migrations/`, `backend/supabase/config.toml`, `backend/tests/`, `backend/tests/catalog/`
- **CI**: `.github/workflows/ci.yml`
- **Spec Kit artifacts**: `specs/061-abo-p1-1-membership-active-org/`
- This unit's Files section names `backend/` and `.github/workflows/ci.yml`. `backend/supabase/config.toml` and `backend/tests/catalog/run.sh` stay as they are. Historical migration files stay untouched. The new migration is `backend/supabase/migrations/20261002120000_membership_active_org.sql`.

---

## 3. Tests

**Purpose**: One task per E2E id. Titles start with the E2E id (rule V3). E2E-P1.1-01 through E2E-P1.1-07 are appended to `backend/tests/membership_active_org.sql` and fail until the migration exists. E2E-P1.1-08 is the existing H-BK scripts, executed red after the migration and before the fixture inserts.

### 3.1 User Story 1 - Staff membership backfill (Priority: P1)

**Independent Test**: E2E-P1.1-07 in harness H-BK (psql on local Supabase, `backend/tests/`).

- [X] T001 [US1] Add the failing test `E2E-P1.1-07` in `backend/tests/membership_active_org.sql`, and register that file from `backend/tests/run_all_backend_tests.sh` with `run_sql_test` — produces the red test, satisfies FR-001 and FR-002, proved by E2E-P1.1-07. After migrations, every non-deleted staff member whose database has a non-deleted organisation has exactly one `ai_internal.membership` row for the earliest such organisation and that staff member's role. A non-deleted staff member and no organisation — the bootstrap administrator from `20260516100400_auth_rbac_seed.sql` on a fresh database — has no membership row. The test fails because `ai_internal.membership` is absent. Leave existing suite claims and assertions unchanged.

**Checkpoint**: E2E-P1.1-07 exists and fails.

### 3.2 User Story 2 - Active organisation for the session (Priority: P2)

**Independent Test**: E2E-P1.1-01, E2E-P1.1-02, and E2E-P1.1-03 in harness H-BK.

- [X] T002 [US2] Add the failing test `E2E-P1.1-01` to `backend/tests/membership_active_org.sql` — produces the red test, satisfies FR-003 and FR-005, proved by E2E-P1.1-01. One membership; call `public.get_custom_claims` with the GoTrue event shape `{"user_id","claims"}`; assert `active_org`; then `current_org_id()` equals that organisation. Depends on T001 (same file). Fails because `current_org_id()` and the `active_org` claim are absent.

- [X] T003 [US2] Add the failing test `E2E-P1.1-02` to `backend/tests/membership_active_org.sql` — produces the red test, satisfies FR-004 and FR-008, proved by E2E-P1.1-02. Memberships in organisations A and B; `set_active_organization(B)`; hook refresh; `current_org_id()` equals B; `public.list_appointments` returns only B's rows. Depends on T002 (same file). Fails because `set_active_organization` is absent.

- [X] T004 [US2] Add the failing test `E2E-P1.1-03` to `backend/tests/membership_active_org.sql` — produces the red test, satisfies FR-004, proved by E2E-P1.1-03. `set_active_organization(C)` returns `success = false` and `error_code = 'FORBIDDEN'`; the active-organisation row and the following hook claim stay as they were. Depends on T003 (same file). Fails because `set_active_organization` is absent.

**Checkpoint**: E2E-P1.1-01, E2E-P1.1-02, and E2E-P1.1-03 exist and fail.

### 3.3 User Story 3 - Membership re-check and role (Priority: P3)

**Independent Test**: E2E-P1.1-04, E2E-P1.1-05, E2E-P1.1-06, and E2E-P1.1-08 in harness H-BK.

- [X] T005 [US3] Add the failing test `E2E-P1.1-04` to `backend/tests/membership_active_org.sql` — produces the red test, satisfies FR-005 and FR-008, proved by E2E-P1.1-04. Delete the membership while the impersonated claims remain; `current_org_id()` is NULL; a `public.branches` select returns 0 rows; `public.list_appointments` raises `FORBIDDEN`. Depends on T004 (same file). The existing `public.branches` policy and `public.list_appointments` body stay in place. Fails because `current_org_id()` is absent.

- [X] T006 [US3] Add the failing test `E2E-P1.1-05` to `backend/tests/membership_active_org.sql` — produces the red test, satisfies FR-005 and FR-006, proved by E2E-P1.1-05. Crafted `active_org` and, separately, crafted `organization_id`, each with no membership; `current_org_id()` is NULL. Depends on T005 (same file). Fails because `current_org_id()` is absent.

- [X] T007 [US3] Add the failing test `E2E-P1.1-06` to `backend/tests/membership_active_org.sql` — produces the red test, satisfies FR-007, proved by E2E-P1.1-06. `current_membership_role()` returns `administrator` and `doctor`; an `UPDATE` on `public.roles_permissions` leaves both results unchanged. Depends on T006 (same file). Fails because `current_membership_role()` is absent.

- [ ] T008 [P] [US3] Treat `E2E-P1.1-08` as the unchanged commands `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` — produces the red run, satisfies FR-009, proved by E2E-P1.1-08. Author this alongside T005–T007; it does not edit `backend/tests/membership_active_org.sql`. Execute it after T011 and before T012–T022 finish: both scripts fail once `public.jwt_organization_id()` re-checks membership and the fixture users still lack a membership row. Leave every pre-existing claim and assertion unchanged. `backend/tests/catalog/run.sh` stays as it is.

**Checkpoint**: E2E-P1.1-04, E2E-P1.1-05, and E2E-P1.1-06 exist and fail. E2E-P1.1-08 is the two existing scripts, run red after the migration.

---

## 4. Implementation

**Purpose**: Implementation units from Files, labelled by the story they serve. `data-model.md` and `contracts/` are plan-phase inputs. The migration file is `backend/supabase/migrations/20261002120000_membership_active_org.sql`. Follow `data-model.md` for the two tables and the three contract files for the frozen function semantics and the `set_active_organization` result body. Fixture inserts are one task per domain section in Sequencing, not one task per file.

### 4.1 User Story 1 - Staff membership backfill (Priority: P1)

**Independent Test**: E2E-P1.1-07 in harness H-BK (psql on local Supabase, `backend/tests/`).

- [X] T009 [US1] Create `backend/supabase/migrations/20261002120000_membership_active_org.sql` with `ai_internal.membership` and the FR-002 backfill — produces the membership table and one backfill row per existing staff user, satisfies FR-001 and FR-002, proved by E2E-P1.1-07. Columns are the spec entity `(user_id, organization_id, role)` plus `membership.created_at`. Primary key and foreign keys enforce the row shape, with `ON DELETE CASCADE` from `auth.users` and `public.organizations`. Deny-all RLS, with no privilege for `anon`, `authenticated`, or `service_role`. The backfill matches E2E-P1.1-07: one membership per non-deleted staff member for the earliest non-deleted organisation and that staff member's role; the bootstrap administrator with no organisation gets no row. Depends on T001–T007 (those tests are already failing). Historical migrations stay untouched.

**Checkpoint**: E2E-P1.1-07 passes.

### 4.2 User Story 2 - Active organisation for the session (Priority: P2)

**Independent Test**: E2E-P1.1-01, E2E-P1.1-02, and E2E-P1.1-03 in harness H-BK.

- [X] T010 [US2] Append the active-organisation objects to `backend/supabase/migrations/20261002120000_membership_active_org.sql` — produces the session's active organisation, `set_active_organization`, and `current_org_id()`, satisfies FR-003, FR-004, FR-005, FR-006, and FR-008, proved by E2E-P1.1-01, E2E-P1.1-02, E2E-P1.1-03, E2E-P1.1-04, and E2E-P1.1-05. Depends on T009 (same file). Add `ai_internal.user_active_organization` (one active organisation per user, `updated_at`, primary key and foreign keys, `ON DELETE CASCADE` from `auth.users` and `public.organizations`, deny-all RLS, no privilege for `anon`, `authenticated`, or `service_role`). Add `auth_internal.sync_active_organization(uuid)` and `CREATE OR REPLACE` of `public.get_custom_claims(jsonb)` so the hook writes the `active_org` claim from the user's sole membership at sign-in and from the active-organisation row after `set_active_organization`. `EXECUTE` on `auth_internal.sync_active_organization(uuid)` to `supabase_auth_admin`. The renamed `public.get_staff_claims_for_user(uuid)` stays. The `get_custom_claims(uuid)` overload stays absent. `auth_internal.build_staff_claims` keeps emitting `organization_id` as the first organisation. Add `public.set_active_organization(uuid)` with `EXECUTE` to `authenticated`: membership required, otherwise `success = false` and `error_code = 'FORBIDDEN'` and the active-organisation row unchanged. The active organisation changes only through this RPC. Add `public.current_org_id()` with `EXECUTE` to `authenticated`: return the `active_org` claim only while a live membership `(sub, org)` exists, re-checked on every call; otherwise NULL, and definer RPCs raise. A JWT with no `active_org` claim falls back to `organization_id`, and the same membership re-check applies. `org` comes from `current_org_id()`, never from an argument. `CREATE OR REPLACE` `public.jwt_organization_id()` as `SELECT public.current_org_id()`. Leave the dependent policy and RPC bodies in place, including `public.list_appointments` and the `public.branches` policy. `backend/supabase/config.toml` stays as it is. `backend/tests/jwt_claims_contract.sql` and `backend/tests/auth_flow_smoke.sh` keep their current assertions.

**Checkpoint**: E2E-P1.1-01, E2E-P1.1-02, and E2E-P1.1-03 pass. E2E-P1.1-04 and E2E-P1.1-05 pass with them, because `current_org_id()` includes the membership re-check.

### 4.3 User Story 3 - Membership re-check and role (Priority: P3)

**Independent Test**: E2E-P1.1-04, E2E-P1.1-05, E2E-P1.1-06, and E2E-P1.1-08 in harness H-BK.

FR-009 insert, used by T012–T022: for every impersonated fixture user whose `request.jwt.claims` includes `organization_id` and who has a `public.staff_members` row, insert `ai_internal.membership (user_id, organization_id, role)` with that claim's `sub`, that claim's `organization_id`, and that staff row's `role`, in the same fixture setup that inserts the staff row, after the backfill has already run. Leave the claim JSON and the assertions unchanged. An impersonation that has no staff row stays without a membership, so its denial assertion still holds.

#### 4.3.1 User Story 3 - Membership re-check and role (part 1)

**Independent Test**: E2E-P1.1-04, E2E-P1.1-05, E2E-P1.1-06, and E2E-P1.1-08 in harness H-BK.

- [X] T011 [US3] Append `public.current_membership_role()` to `backend/supabase/migrations/20261002120000_membership_active_org.sql` — produces the membership role, satisfies FR-007, proved by E2E-P1.1-06. Depends on T010 (same file). The function returns the membership role (`administrator`, `doctor`, `receptionist`, or `lab_staff`). Billing authority is the membership role `administrator`. `EXECUTE` to `authenticated`. An edit to `public.roles_permissions` does not change the result. Semantics follow `contracts/current-membership-role.md`.

- [X] T012 [P] [US3] Add the FR-009 membership insert to the Auth / RBAC fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/admin_reset_staff_password.sql`, `backend/tests/auth_security_extensions.sql`, `backend/tests/bootstrap_rpc.sql`, `backend/tests/create_staff_rpc.sql`, `backend/tests/rls_isolation.sql`, `backend/tests/auth_rbac_extended.sql`. Leave `backend/tests/jwt_claims_contract.sql` and `backend/tests/auth_flow_smoke.sh` unchanged.

- [X] T013 [P] [US3] Add the FR-009 membership insert to the org / branch fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/org_branch_management_crud.sql`, `backend/tests/org_branch_management_rls.sql`, `backend/tests/org_branch_management_extended.sql`, `backend/tests/admin_update_staff_username.sql`, `backend/tests/delete_staff_member.sql`.

- [X] T014 [P] [US3] Add the FR-009 membership insert to the patient fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/patient_mrn_generation.sql`, `backend/tests/patient_mrn_reassign.sql`, `backend/tests/invoices_patient_mrn_payload_test.sql`, `backend/tests/patient_management_crud.sql`, `backend/tests/patient_transfer_restore.sql`, `backend/tests/patient_management_rls.sql`, `backend/tests/patient_management_extended.sql`, `backend/tests/patient_management_roles.sql`, `backend/tests/patient_management_search_advanced.sql`, `backend/tests/patient_management_search_filters.sql`, `backend/tests/patient_management_concurrent.sql`.

- [X] T015 [P] [US3] Add the FR-009 membership insert to the appointment fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/appointment_management_crud.sql`, `backend/tests/appointment_get_update.sql`, `backend/tests/appointment_simplified_booking_slots.sql`, `backend/tests/appointment_management_patient_filter.sql`, `backend/tests/appointment_management_rls.sql`, `backend/tests/appointment_calendar_backend_integrity.sql`, `backend/tests/appointments_patient_mrn_payload_test.sql`, `backend/tests/appointment_queue_qa.sql`.

#### 4.3.2 User Story 3 - Membership re-check and role (part 2)

**Independent Test**: E2E-P1.1-04, E2E-P1.1-05, E2E-P1.1-06, and E2E-P1.1-08 in harness H-BK.

- [X] T016 [P] [US3] Add the FR-009 membership insert to the visit fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/visit_medical_records_crud.sql`, `backend/tests/visit_medical_records_rls.sql`, `backend/tests/visit_attachment_storage_rls.sql`, `backend/tests/visit_attachment_delete_storage.sql`, `backend/tests/patient_visit_attachments_list.sql`, `backend/tests/visit_encounter_workspace_crud.sql`, `backend/tests/visit_encounter_workspace_rls.sql`, `backend/tests/visit_predefined_vital_signs_backfill.sql`, `backend/tests/visit_documentation_complete_validation.sql`.

- [X] T017 [P] [US3] Add the FR-009 membership insert to the billing fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/billing_rls.sql`, `backend/tests/billing_crud.sql`, `backend/tests/billing_concurrency.sql`.

- [X] T018 [P] [US3] Add the FR-009 membership insert to the service catalog fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/service_catalog_crud.sql`, `backend/tests/service_catalog_list.sql`, `backend/tests/service_catalog_rls.sql`, `backend/tests/service_catalog_pricing.sql`, `backend/tests/service_catalog_concurrency.sql`.

- [X] T019 [P] [US3] Add the FR-009 membership insert to the shift fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/shift_management_rls.sql`, `backend/tests/shift_management_crud.sql`, `backend/tests/shift_management_concurrency.sql`.

- [X] T020 [P] [US3] Add the FR-009 membership insert to the AI platform trust fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. This is the AI Platform Trust section of `backend/tests/run_all_backend_tests.sh`. Files: `backend/tests/ai_keystore_rls.sql`, `backend/tests/context_provider_rpc.sql`, `backend/tests/ai_acceptance_recording.sql`.

#### 4.3.3 User Story 3 - Membership re-check and role (part 3)

**Independent Test**: E2E-P1.1-04, E2E-P1.1-05, E2E-P1.1-06, and E2E-P1.1-08 in harness H-BK.

- [ ] T021 [P] [US3] Add the FR-009 membership insert to the catalog stage fixture files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/catalog/stage-02-availability-and-enroll.sql`, `backend/tests/catalog/stage-02-revoke-rotate-availability.sql`, `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql`, `backend/tests/catalog/stage-06-issuer-guards.sql`, `backend/tests/catalog/stage-08-context-provider-rpc.sql`, `backend/tests/catalog/stage-11-record-ai-acceptance.sql`. `backend/tests/catalog/run.sh` stays as it is.

- [ ] T022 [P] [US3] Add the FR-009 membership insert to the remaining settings, dev-reset, role-matrix, and staff sign-in files — produces those fixture membership rows, satisfies FR-009, proved by E2E-P1.1-08. Depends on T011. Files: `backend/tests/settings_code_review_fixes.sql`, `backend/tests/dev_reset_clinic_installation.sql`, `backend/tests/role_permissions_matrix.sql`, `backend/tests/staff_sign_in_after_create.sh`.

- [ ] T023 [US3] Add the `backend-sql` job to `.github/workflows/ci.yml` — produces the backend CI job, satisfies FR-009, proved by E2E-P1.1-08. Depends on T012–T022. The job checks out the repo, installs the Supabase CLI, runs `supabase start` in `backend/` (that applies all migrations, including the hook already registered in `backend/supabase/config.toml`), then runs `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh`. Existing jobs stay in place (rule V7).

**Checkpoint**: E2E-P1.1-06 passes. E2E-P1.1-04 and E2E-P1.1-05 already pass from T010. E2E-P1.1-08 passes once T012–T022 are in place.

---

## 5. Verification

**Purpose**: This unit's H-BK suite passes, then every earlier suite is still green (rule S2). Consumes Binding is none; the pre-existing backend suites inside the two H-BK commands are that regression.

- [ ] T024 Run harness H-BK on local Supabase and confirm it is green — produces the green run, satisfies FR-009, SC-001, and SC-002, proved by E2E-P1.1-01 through E2E-P1.1-08. Depends on T001–T023. Run `backend/tests/run_all_backend_tests.sh` (it includes `membership_active_org.sql` for E2E-P1.1-01 through E2E-P1.1-07, plus the pre-existing suites) and `backend/tests/catalog/run.sh` (E2E-P1.1-08). Pre-existing suites keep their impersonated claims and their assertions. There is no earlier ABO unit suite to add. A full-product `npm test` is not this command.

---

## 6. Documentation

**Purpose**: Written after T024 is green (rule S8). The plan leaves `quickstart.md` for implement. `data-model.md` and `contracts/` stay plan-phase artifacts.

- [ ] T025 Create `specs/061-abo-p1-1-membership-active-org/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, satisfies FR-001 through FR-009, proved by E2E-P1.1-01 through E2E-P1.1-08. Depends on T024. Sections: (1) what was implemented — membership, the active-organisation record, the `active_org` claim, `set_active_organization`, `current_org_id()`, `current_membership_role()`, the re-point of `public.jwt_organization_id()`, fixture membership rows, and the backend CI job; (2) files this unit adds or modifies — the Files section of `plan.md`, with no earlier-unit files, no combined counts, and no full-suite regression (that is T024); (3) harness command for this unit's tests only — H-BK as in Test Layout, including `backend/tests/run_all_backend_tests.sh` and `backend/tests/catalog/run.sh` for E2E-P1.1-08; (4) how to inspect the change; (5) the entry point → module chain per E2E id below. Every scenario is asserted by H-BK, so this file records harness commands only.

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

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T008)**: Start immediately. T001 creates `backend/tests/membership_active_org.sql` and registers it. T002–T007 append to that file in order. T008 is `[P]` with T005–T007. Sequencing step 1: T001–T007 are observed failing before any migration task.
- **Implementation (T009–T023)**: After T001–T007 exist and fail. Order is Sequencing: migration (T009, then T010, then T011), then the fixture groups (T012–T022), then the CI job (T023). T008's red run sits after T011 and before T012–T022 finish.
- **Verification (T024)**: After every implementation task.
- **Documentation (T025)**: After T024 is green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: No dependency on another story. Its test (T001) is first. Its implementation (T009) waits until T001–T007 are failing, because Sequencing writes E2E-P1.1-01 through E2E-P1.1-07 before the migration.
- **User Story 2 (P2)**: Depends on User Story 1. Tests T002–T004 append after T001 and do not wait for T009. Implementation T010 waits on T009.
- **User Story 3 (P3)**: Depends on User Story 2. Tests T005–T007 append after T004 and do not wait for T010. T008 is `[P]` with those tests. Implementation T011 waits on T010. Fixture tasks T012–T022 wait on T011, then run in parallel with each other. T023 waits on T012–T022.

### 7.3 Parallel Opportunities

- T008 is `[P]` with T005, T006, and T007. T008 does not edit `backend/tests/membership_active_org.sql`. T005–T007 are sequential on that file.
- T002, T003, and T004 are sequential on that same file. They are not `[P]`.
- T009, T010, and T011 are sequential on the migration file. They are not `[P]`.
- T012–T022 are `[P]` with each other after T011. Each group edits different files. A pair from another story is not parallel with them: User Story 2's implementation is the same migration file and Sequencing places it before these inserts.
- T023 edits `.github/workflows/ci.yml` and waits until the fixture inserts exist, so it is not `[P]` with T012–T022.
- T024 and T025 are single tasks.

```bash
# Two User Story 3 test tasks launched together.
# T008 does not edit membership_active_org.sql; T005 appends E2E-P1.1-04 there.
Task: "T005 [US3] Add the failing test E2E-P1.1-04 in backend/tests/membership_active_org.sql"
Task: "T008 [P] [US3] E2E-P1.1-08 red run of backend/tests/run_all_backend_tests.sh and backend/tests/catalog/run.sh"
```
