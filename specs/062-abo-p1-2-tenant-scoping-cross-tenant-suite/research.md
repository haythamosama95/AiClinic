# Tenant Inventory

**Unit**: P1.2 · **Spec**: `specs/062-abo-p1-2-tenant-scoping-cross-tenant-suite/spec.md`

**Spikes**: None. This file is the tenant inventory FR-001 requires. It is not a design spike.

## 1. Org-key rule

`public.jwt_organization_id()` is defined as `SELECT public.current_org_id()` in `backend/supabase/migrations/20261002120000_membership_active_org.sql`. A live policy or definer already keys on `current_org_id()` when its latest body, or a helper it calls to load the row, compares the row's organisation to `public.jwt_organization_id()` or `public.current_org_id()`. Those objects stay as they are (rule S5). This unit does not edit that migration.

A mention of `jwt_organization_id()` that only stamps an audit row or a newly inserted organisation value is not a row predicate. `auth_internal.update_role_permission` and `auth_internal.update_role_permissions` are in that class: the audit insert calls `jwt_organization_id()`, and the `roles_permissions` row itself is not scoped.

`jwt_branch_ids()` reads the `branch_ids` claim. It is not `current_org_id()`.

## 2. Tenant tables

Live tables were taken from `backend/supabase/migrations/` in timestamp order. Dropped tables (`public.soap_notes`, `public.diagnosis_codes`, `public.visit_diagnosis_codes`, `public.visit_plan_details`) are not in the inventory.

### 2.1 Already has `organization_id` and a policy or writer that uses `jwt_organization_id()`

These tables are not given a new column. Policies that already compare `organization_id` to `jwt_organization_id()` are not replaced.

| Table | Org key today | This unit |
| --- | --- | --- |
| `ai_internal.membership` | Column. Deny-all RLS. P1.1 consume | Not rewritten |
| `ai_internal.user_active_organization` | Column. Deny-all RLS. P1.1 consume | Not rewritten |
| `public.ai_accepted_output` | Column. SELECT `organization_id = jwt_organization_id()` | Already the acceptance record. No column change |
| `public.app_settings` | Column. SELECT `organization_id = jwt_organization_id()` | None |
| `public.audit_log` | Column. SELECT uses `jwt_organization_id()` | None |
| `public.branches` | Column. SELECT and UPDATE use `jwt_organization_id()` | None |
| `public.insurance_providers` | Column. SELECT uses `jwt_organization_id()` | None |
| `public.investigations` | Column. SELECT uses `jwt_organization_id()` | None |
| `public.invoices` | Column. SELECT uses `jwt_branch_ids()` only | Add a restrictive policy `organization_id = public.current_org_id()`. Keep the existing permissive policy |
| `public.medications` | Column. SELECT uses `jwt_organization_id()` | None |
| `public.organization_billing_settings` | Column is the primary key. SELECT uses `jwt_organization_id()` | None |
| `public.organizations` | The org key is `id` | None. New rows fire the `roles_permissions` seed trigger |
| `public.patients` | Column. SELECT uses `jwt_organization_id()` | None |
| `public.predefined_vital_signs` | Column. SELECT uses `jwt_organization_id()` | None |
| `public.services` | Column. SELECT uses `jwt_organization_id()` | None |
| `public.shifts` | Column. SELECT uses `jwt_organization_id()` | None |
| `public.subscription_cache` | Column. SELECT uses `jwt_organization_id()` | None |

### 2.2 No `organization_id` column — this unit adds one

`organization_id uuid NOT NULL REFERENCES public.organizations (id)`, backfilled from the parent below, plus a restrictive RLS policy `organization_id = public.current_org_id()`. Existing permissive policies stay. A `BEFORE INSERT` trigger fills `organization_id` from the same parent when the writer omits it. When `current_org_id()` is not null, the trigger raises if the parent's organisation is not that value. When `current_org_id()` is null (migration, `dev_reset`, no JWT), the trigger copies the parent organisation and does not raise.

| Table | Backfill parent |
| --- | --- |
| `public.appointments` | `branches.organization_id` via `branch_id` |
| `public.visits` | `branches.organization_id` via `branch_id` |
| `public.visit_clinical_notes` | `visits` → branch |
| `public.visit_vital_signs` | `visits` → branch |
| `public.visit_investigations` | `visits` → branch |
| `public.visit_attachments` | `visits` → branch |
| `public.treatment_plans` | `visits` → branch |
| `public.invoice_items` | `invoices.organization_id` |
| `public.payments` | `invoices.organization_id` |
| `public.invoice_number_sequences` | `branches.organization_id` via `branch_id`. Existing deny-all policies stay |
| `public.patient_allergies` | `patients.organization_id` |
| `public.patient_medications` | `patients.organization_id` |
| `public.patient_chronic_conditions` | `patients.organization_id` |
| `public.service_branches` | `services.organization_id` |
| `public.shift_assignments` | `shifts.organization_id` |

### 2.3 Named shapes that are not a new column on a child

| Object | Org key | This unit |
| --- | --- | --- |
| `public.roles_permissions` | No column today. SELECT is `is_deleted = false` and granted or `current_staff_member_row().role = administrator` | Add `organization_id`, unique `(organization_id, role, permission_key)`, seed per organisation, SELECT `organization_id = public.current_org_id()` |
| `ai_internal.ai_token_issuance` | No column. Policy `ai_token_issuance_deny_all` is `USING (false)` | Add `organization_id`, backfill from the actor staff member's earliest membership `(created_at, organization_id)`, replace the deny-all SELECT with `organization_id = public.current_org_id()`. Insert, update, and delete stay closed to `authenticated` |
| `public.staff_members` | No column. SELECT/UPDATE allow `auth_user_id = auth.uid()` or a branch in `jwt_organization_id()` | No column (FR-004). SELECT and UPDATE require a row in `ai_internal.membership` for `(staff_members.auth_user_id, public.current_org_id())` |
| `public.staff_branch_assignments` | No column. SELECT allows `jwt_branch_ids()`, a setup-required own row, or an administrator branch in `jwt_organization_id()` | No column. SELECT requires `branches.organization_id = public.current_org_id()` and a membership for the assigned staff member's `auth_user_id` in that organisation. The setup-required own-row arm remains only when `current_org_id()` is null |
| `ai_internal.acceptance_targets` | Global registry `(target_key, domain_function, table_name)`. Not tenant state | Not a tenant table |
| `ai_internal.installation_keys` | No column. Deny-all. Single-installation trigger | Out of scope (P5.1) |
| `ai_internal.app_settings` | No column. Deny-all. Holds `ai.availability` | Out of scope (P5.2) |

## 3. Policies this unit changes

Every other live policy either compares to `jwt_organization_id()` or is deny-all (`USING (false)` or `WITH CHECK (false)`) and is left in place. Deny-all write policies on the tables in §2.2 stay; the new restrictive policy only adds the org predicate.

| Policy | Table | Change |
| --- | --- | --- |
| `roles_permissions_select` | `public.roles_permissions` | Replace. `organization_id = public.current_org_id()`, and the row is granted or `public.current_membership_role() = 'administrator'` |
| `ai_token_issuance_deny_all` | `ai_internal.ai_token_issuance` | Replace SELECT with `organization_id = public.current_org_id()` for `authenticated`. Writes stay denied |
| `staff_members_select` | `public.staff_members` | Replace with the membership predicate in §2.3 |
| `staff_members_update` | `public.staff_members` | Same predicate |
| `staff_branch_assignments_select` | `public.staff_branch_assignments` | Replace with the membership predicate in §2.3 |
| `invoices_select` | `public.invoices` | Keep. Add restrictive `invoices_org` `organization_id = public.current_org_id()` |
| (new restrictive) | Each table in §2.2 | `organization_id = public.current_org_id()` |

## 4. Definer RPCs

### 4.1 Already keyed — not rewritten

A public or `auth_internal` definer whose row lookup already goes through `jwt_organization_id()` or `current_org_id()` is unchanged. That includes `auth_internal.record_ai_acceptance`, which sets `ai_accepted_output.organization_id` from `public.jwt_organization_id()`. After P1.1 that value is `current_org_id()`.

`public.set_active_organization`, `public.current_org_id`, `public.current_membership_role`, `public.get_custom_claims`, and `auth_internal.sync_active_organization` are P1.1 consumes and are not edited.

### 4.2 Row predicates to fix

Latest body filters with `jwt_branch_ids()` and does not constrain the row's organisation. Each lookup gains `AND <organisation> = public.current_org_id()`. A foreign id returns the existing `NOT_FOUND` (or an empty list, for the list functions). No new error code.

| Function | Latest file |
| --- | --- |
| `auth_internal.get_appointment(uuid)` | `20260618120000_get_appointment.sql` |
| `auth_internal.get_visit_by_appointment(uuid)` | `20260531180000_visit_medical_records.sql` |
| `auth_internal.list_invoices` | `20260727150000_search_by_mrn.sql` |
| `auth_internal.list_patient_invoices` | `20260605240000_billing_us5_list_patient_invoices.sql` |
| `auth_internal.assert_invoice_branch_scope(uuid)` | `20260605180000_billing.sql` |
| `auth_internal.lock_draft_invoice` | `20260605180500_billing_us1_rpcs.sql` |
| `auth_internal.lock_payable_invoice` | `20260605181000_billing_us2_payment_rpcs.sql` |

`public.get_appointment`, `public.get_visit_by_appointment`, `public.list_invoices`, and `public.list_patient_invoices` are invoker wrappers. Fixing the `auth_internal` bodies fixes the PostgREST entry.

### 4.3 Writes to fix

| Function | Latest file | Change |
| --- | --- | --- |
| `auth_internal.update_role_permission(public.staff_role, text, boolean)` | `20260613140000_role_permissions_full_matrix.sql` | Load and upsert only `organization_id = public.current_org_id()`. The `ON CONFLICT` target becomes `(organization_id, role, permission_key)` |
| `auth_internal.update_role_permissions(jsonb)` | `20260614100000_settings_code_review_fixes.sql` | Same scope |
| `auth_internal.issue_ai_token(text[])` | `20260905120300_fix_aat_lifetime_fallback.sql` | Insert `ai_token_issuance.organization_id = public.current_org_id()`. Token claim `org` is `current_org_id()::text`. Scopes are `roles_permissions` rows with that `organization_id`, `role = public.current_membership_role()`, `permission_key LIKE 'ai.%'`, `is_granted`, not deleted |

`public.update_role_permission`, `public.update_role_permissions`, and `public.issue_ai_token` stay invoker wrappers.

### 4.4 Not tenant RPCs

Bootstrap (`bootstrap_create_organization`, `bootstrap_create_branch`, `bootstrap_finish_setup`), `dev_reset_clinic_installation`, `dev_seed_medications_catalog`, `dev_seed_investigations_catalog`, audit triggers (`set_updated_at`, `set_audit_user`, `set_payment_created_by`, `set_billing_settings_audit_user`), JWT readers (`jwt_branch_ids`, `jwt_staff_member_id`, `jwt_staff_role`, `jwt_setup_required`, `request_jwt_claims`), `rpc_success`, `rpc_error`, and `current_staff_member_row` are not tenant stores. They are not given an org predicate.

Installation-key functions (`enroll_installation_keypair`, `rotate_installation_key`, `revoke_installation_key`) and availability functions (`get_ai_availability`, `set_ai_availability`, `ai_app_setting_text`, `ai_app_setting_numeric`) stay unchanged (P5.1 and P5.2).

Helpers that do not choose a tenant (`assert_permission`, overlap checks, invoice arithmetic, `invoke_acceptance_domain_rpc`) stay unchanged. They run under a caller that already keyed the row, or they are not tenant stores.

## 5. Seed

At migration time the current `roles_permissions` matrix is the default. The migration copies that `(role, permission_key, is_granted)` set onto every existing `public.organizations` row, then removes the unscoped rows. An `AFTER INSERT` trigger on `public.organizations` inserts that same default set for a new organisation. It does not copy another organisation's later edits.

## 6. Cross-tenant result

Foreign ids keep the existing `rpc_error` code `NOT_FOUND`, or the list is empty. This unit does not add an error body. Direct table reads as `authenticated` return no row whose organisation is not `current_org_id()`.

## 7. Public functions and the E2E-P1.2-02 call list
E2E-P1.2-02 calls each **keyed** and **fix** row as `authenticated`. Uuid arguments that identify a row are organisation B's ids. A function with no row id is still invoked, and B's rows must be unchanged. **skip** rows are §4.4 or a consumed helper and are not part of the call list. **fix** rows are §4.2 and §4.3: they must return not found or empty, or leave B unchanged, after this unit. **keyed** rows already reach `current_org_id()` and must stay not found or empty. `public.issue_ai_token` and `public.record_ai_acceptance` are also asserted by E2E-P1.2-05. `public.update_role_permission` and `public.update_role_permissions` are also asserted by E2E-P1.2-01.

| Function | Class |
| --- | --- |
| `public.add_invoice_item` | keyed |
| `public.add_invoice_item_from_service` | keyed |
| `public.admin_reset_staff_password` | keyed |
| `public.admin_update_staff_username` | keyed |
| `public.apply_invoice_discount` | keyed |
| `public.apply_line_discount` | keyed |
| `public.apply_standard_audit_triggers` | skip |
| `public.archive_patient` | keyed |
| `public.archive_patient_allergy` | keyed |
| `public.archive_patient_chronic_condition` | keyed |
| `public.archive_patient_medication` | keyed |
| `public.archive_treatment_plan` | keyed |
| `public.archive_visit_diagnosis_code` | keyed |
| `public.archive_visit_investigation` | keyed |
| `public.archive_visit_vital_sign` | keyed |
| `public.assert_bootstrap_admin` | skip |
| `public.assert_owner_or_administrator` | skip |
| `public.bootstrap_create_branch` | skip |
| `public.bootstrap_create_organization` | skip |
| `public.bootstrap_finish_setup` | skip |
| `public.build_staff_claims` | skip |
| `public.cancel_appointment` | keyed |
| `public.cancel_shift` | keyed |
| `public.check_patient_duplicates` | keyed |
| `public.cleanup_audit_log` | skip |
| `public.complete_visit` | keyed |
| `public.configure_service_branch` | keyed |
| `public.copy_service_branch_configuration` | keyed |
| `public.create_appointment` | keyed |
| `public.create_auth_user` | skip |
| `public.create_catalog_diagnosis_code` | keyed |
| `public.create_catalog_investigation` | keyed |
| `public.create_catalog_medication` | keyed |
| `public.create_invoice_from_visit` | keyed |
| `public.create_patient` | keyed |
| `public.create_patient_allergy` | keyed |
| `public.create_patient_chronic_condition` | keyed |
| `public.create_patient_medication` | keyed |
| `public.create_predefined_vital_sign` | keyed |
| `public.create_service` | keyed |
| `public.create_shift` | keyed |
| `public.create_staff_account` | keyed |
| `public.create_treatment_plan` | keyed |
| `public.create_visit` | keyed |
| `public.create_visit_diagnosis_code` | keyed |
| `public.create_visit_investigation` | keyed |
| `public.create_visit_vital_sign` | keyed |
| `public.current_membership_role` | skip |
| `public.current_org_id` | skip |
| `public.current_staff_member_row` | skip |
| `public.delete_branch` | keyed |
| `public.delete_staff_member` | keyed |
| `public.delete_visit_attachment` | keyed |
| `public.dev_reset_clinic_installation` | skip |
| `public.dev_seed_investigations_catalog` | skip |
| `public.dev_seed_medications_catalog` | skip |
| `public.discard_draft_invoice` | keyed |
| `public.enroll_installation_keypair` | skip |
| `public.get_ai_availability` | skip |
| `public.get_appointment` | fix |
| `public.get_appointment_settings` | keyed |
| `public.get_billing_settings` | keyed |
| `public.get_custom_claims` | skip |
| `public.get_invoice_detail` | keyed |
| `public.get_patient` | keyed |
| `public.get_patient_safety_context` | keyed |
| `public.get_service` | keyed |
| `public.get_shift_detail` | keyed |
| `public.get_simplified_booking_slots` | keyed |
| `public.get_specialty_form_schema` | keyed |
| `public.get_visit` | keyed |
| `public.get_visit_attachment_download` | keyed |
| `public.get_visit_by_appointment` | fix |
| `public.get_visit_chief_complaint` | keyed |
| `public.insurance_provider_deactivate` | keyed |
| `public.insurance_provider_upsert` | keyed |
| `public.issue_ai_token` | fix |
| `public.issue_invoice` | keyed |
| `public.jwt_branch_ids` | skip |
| `public.jwt_organization_id` | skip |
| `public.jwt_setup_required` | skip |
| `public.jwt_staff_member_id` | skip |
| `public.jwt_staff_role` | skip |
| `public.list_appointments` | keyed |
| `public.list_insurance_providers` | keyed |
| `public.list_invoices` | fix |
| `public.list_patient_invoices` | fix |
| `public.list_patient_visit_attachments` | keyed |
| `public.list_patient_visits` | keyed |
| `public.list_predefined_vital_signs` | keyed |
| `public.list_services` | keyed |
| `public.list_shifts` | keyed |
| `public.manage_create_branch` | keyed |
| `public.modify_shift_assignments` | keyed |
| `public.organization_exists` | skip |
| `public.owner_exists` | skip |
| `public.reassign_patient_mrn` | keyed |
| `public.record_ai_acceptance` | keyed |
| `public.record_investigation_result` | keyed |
| `public.record_payment` | keyed |
| `public.record_refund` | keyed |
| `public.register_visit_attachment` | keyed |
| `public.remove_invoice_item` | keyed |
| `public.request_jwt_claims` | skip |
| `public.reschedule_appointment` | keyed |
| `public.resolve_effective_service_price` | keyed |
| `public.restore_patient` | keyed |
| `public.revoke_installation_key` | skip |
| `public.rotate_installation_key` | skip |
| `public.rpc_error` | skip |
| `public.rpc_success` | skip |
| `public.save_soap_note` | keyed |
| `public.save_visit_documentation` | keyed |
| `public.save_visit_plan_details` | keyed |
| `public.search_diagnosis_codes` | keyed |
| `public.search_eligible_services` | keyed |
| `public.search_investigations` | keyed |
| `public.search_medications` | keyed |
| `public.search_patients` | keyed |
| `public.set_active_organization` | skip |
| `public.set_ai_availability` | skip |
| `public.set_appointment_default_duration` | keyed |
| `public.set_audit_user` | skip |
| `public.set_billing_settings_audit_user` | skip |
| `public.set_branch_active` | keyed |
| `public.set_insurance_coverage` | keyed |
| `public.set_payment_created_by` | skip |
| `public.set_service_branch_assignment` | keyed |
| `public.set_service_global_status` | keyed |
| `public.set_service_promotion` | keyed |
| `public.set_specialty_form_schema` | keyed |
| `public.set_staff_active` | keyed |
| `public.set_updated_at` | skip |
| `public.setup_new_branch_services` | keyed |
| `public.soft_delete_service` | keyed |
| `public.staff_login_usernames` | keyed |
| `public.transfer_patient` | keyed |
| `public.update_appointment` | keyed |
| `public.update_appointment_status` | keyed |
| `public.update_billing_settings` | keyed |
| `public.update_branch` | keyed |
| `public.update_invoice_item` | keyed |
| `public.update_organization` | keyed |
| `public.update_patient` | keyed |
| `public.update_patient_allergy` | keyed |
| `public.update_patient_chronic_condition` | keyed |
| `public.update_patient_medication` | keyed |
| `public.update_role_permission` | fix |
| `public.update_role_permissions` | fix |
| `public.update_service` | keyed |
| `public.update_shift` | keyed |
| `public.update_staff_member` | keyed |
| `public.update_treatment_plan` | keyed |
| `public.update_visit_investigation` | keyed |
| `public.update_visit_vital_sign` | keyed |
| `public.void_invoice` | keyed |
