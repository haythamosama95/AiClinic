# SQL definition navigation

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`.

Changed SQL function names are traced through all production backend migration declarations. [Machine data](regions-sql-definitions.json) retains argument text and definition locations. No SQL correctness review was performed. R1 reviews issuer/tenant/auth functions and their grants/RLS; R7 reviews projection/status functions; R9 reads full migration consistency. Last declaration by name is only a locator: overloaded signatures and DROP/ALTER must be resolved in migration order.

## `auth_internal.assert_appointment_branch`

- `backend/supabase/migrations/20260526140000_appointment_management.sql:222` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1997` — changed migration

## `auth_internal.assert_invoice_branch_scope`

- `backend/supabase/migrations/20260605180000_billing.sql:699` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1587` — changed migration

## `auth_internal.assert_permission`

- `backend/supabase/migrations/20260522100000_org_branch_management.sql:14` — unchanged supporting prior definition
- `backend/supabase/migrations/20260613210000_delete_staff_member.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1948` — changed migration

## `auth_internal.bootstrap_create_branch`

- `backend/supabase/migrations/20260521110000_auth_rbac_definer_internal_schema.sql:298` — unchanged supporting prior definition
- `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql:208` — changed migration

## `auth_internal.bootstrap_create_organization`

- `backend/supabase/migrations/20260521110000_auth_rbac_definer_internal_schema.sql:228` — unchanged supporting prior definition
- `backend/supabase/migrations/20260628150000_seed_organization_catalog_defaults.sql:78` — unchanged supporting prior definition
- `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql:129` — changed migration

## `auth_internal.bootstrap_finish_setup`

- `backend/supabase/migrations/20260611140000_allow_admin_create_owner_and_atomic_bootstrap_setup.sql:331` — unchanged supporting prior definition
- `backend/supabase/migrations/20260611150000_remove_owner_role.sql:439` — unchanged supporting prior definition
- `backend/supabase/migrations/20260611160000_fix_bootstrap_finish_setup_admin_count.sql:4` — unchanged supporting prior definition
- `backend/supabase/migrations/20260613120000_bootstrap_finish_setup_working_schedule.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20260613150000_create_staff_account_phone.sql:177` — unchanged supporting prior definition
- `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql:466` — changed migration

## `auth_internal.canonical_issuer_jwt_json`

- `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql:4` — changed migration

## `auth_internal.create_appointment`

- `backend/supabase/migrations/20260526140000_appointment_management.sql:568` — unchanged supporting prior definition
- `backend/supabase/migrations/20260527170000_optional_appointment_doctor.sql:33` — unchanged supporting prior definition
- `backend/supabase/migrations/20260528100000_walkin_doctor_optional.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20260528150500_appointment_slot_and_patient_day_conflicts.sql:138` — unchanged supporting prior definition
- `backend/supabase/migrations/20260528153000_enforce_appointment_branch_working_hours.sql:196` — unchanged supporting prior definition
- `backend/supabase/migrations/20260528160000_appointment_confirmed_remove_walkin.sql:8` — unchanged supporting prior definition
- `backend/supabase/migrations/20260531120000_remove_appointment_walk_in_type.sql:24` — unchanged supporting prior definition
- `backend/supabase/migrations/20260531200000_fix_create_appointment_exceptions.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20260604130000_fix_create_appointment_exception_handlers.sql:3` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:2148` — changed migration

## `auth_internal.create_patient`

- `backend/supabase/migrations/20260523140000_patient_management.sql:515` — unchanged supporting prior definition
- `backend/supabase/migrations/20260523150000_patient_registration_fields.sql:298` — unchanged supporting prior definition
- `backend/supabase/migrations/20260525120400_fix_patient_phone_index.sql:9` — unchanged supporting prior definition
- `backend/supabase/migrations/20260724120000_patient_mrn_field.sql:45` — unchanged supporting prior definition
- `backend/supabase/migrations/20260724125000_create_patient_optional_mrn_param.sql:5` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:222` — changed migration

## `auth_internal.create_staff_account`

- `backend/supabase/migrations/20260521110000_auth_rbac_definer_internal_schema.sql:397` — unchanged supporting prior definition
- `backend/supabase/migrations/20260521190000_staff_username_auth.sql:120` — unchanged supporting prior definition
- `backend/supabase/migrations/20260525120100_fix_remove_plaintext_password_from_responses.sql:3` — unchanged supporting prior definition
- `backend/supabase/migrations/20260525120300_fix_password_complexity_validation.sql:28` — unchanged supporting prior definition
- `backend/supabase/migrations/20260611140000_allow_admin_create_owner_and_atomic_bootstrap_setup.sql:3` — unchanged supporting prior definition
- `backend/supabase/migrations/20260611150000_remove_owner_role.sql:93` — unchanged supporting prior definition
- `backend/supabase/migrations/20260613150000_create_staff_account_phone.sql:5` — unchanged supporting prior definition
- `backend/supabase/migrations/20260614100000_settings_code_review_fixes.sql:158` — unchanged supporting prior definition
- `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql:313` — changed migration

## `auth_internal.delete_clinic_test_fixtures`

- `backend/supabase/migrations/20260605260000_delete_clinic_test_fixtures.sql:35` — unchanged supporting prior definition
- `backend/supabase/migrations/20260712100000_fix_dev_reset_orgs_before_auth_users.sql:174` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:1550` — changed migration

## `auth_internal.get_ai_status`

- `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql:378` — changed migration
- `backend/supabase/migrations/20261008010000_read_time_status_notices.sql:8` — changed migration

## `auth_internal.get_appointment`

- `backend/supabase/migrations/20260618120000_get_appointment.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1460` — changed migration

## `auth_internal.get_appointment_settings`

- `backend/supabase/migrations/20260526140000_appointment_management.sql:457` — unchanged supporting prior definition
- `backend/supabase/migrations/20260604140000_appointment_low_severity_fixes.sql:8` — unchanged supporting prior definition
- `backend/supabase/migrations/20260615120000_remove_appointment_max_duration.sql:15` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:2033` — changed migration

## `auth_internal.get_visit_by_appointment`

- `backend/supabase/migrations/20260531180000_visit_medical_records.sql:1512` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1542` — changed migration

## `auth_internal.insert_issuer_kid`

- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:32` — changed migration

## `auth_internal.invoke_acceptance_domain_rpc`

- `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql:63` — unchanged supporting prior definition
- `backend/supabase/migrations/20260805150000_f2_review_resolution.sql:10` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:418` — changed migration

## `auth_internal.issue_ai_token`

- `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:113` — unchanged supporting prior definition
- `backend/supabase/migrations/20260803140000_b1_review_resolution.sql:435` — unchanged supporting prior definition
- `backend/supabase/migrations/20260905120300_fix_aat_lifetime_fallback.sql:3` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:410` — changed migration
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:605` — changed migration
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:963` — changed migration

## `auth_internal.issue_billing_token`

- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:1139` — changed migration
- `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql:77` — changed migration

## `auth_internal.issue_feed_token`

- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:1339` — changed migration
- `backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql:3` — changed migration

## `auth_internal.list_invoices`

- `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql:808` — unchanged supporting prior definition
- `backend/supabase/migrations/20260605290000_fix_billing_review_items_4_8_12.sql:403` — unchanged supporting prior definition
- `backend/supabase/migrations/20260605310000_fix_billing_review_items_18_21_24.sql:344` — unchanged supporting prior definition
- `backend/supabase/migrations/20260713130000_list_invoices_include_payments.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20260717120000_invoice_organization_currency.sql:123` — unchanged supporting prior definition
- `backend/supabase/migrations/20260724123000_list_invoices_include_mrn.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20260727140000_remove_payment_reference.sql:152` — unchanged supporting prior definition
- `backend/supabase/migrations/20260727150000_search_by_mrn.sql:298` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1686` — changed migration

## `auth_internal.list_patient_invoices`

- `backend/supabase/migrations/20260605240000_billing_us5_list_patient_invoices.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1885` — changed migration

## `auth_internal.lock_draft_invoice`

- `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql:70` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1613` — changed migration

## `auth_internal.lock_payable_invoice`

- `backend/supabase/migrations/20260605181000_billing_us2_payment_rpcs.sql:8` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1652` — changed migration

## `auth_internal.pull_coverage_feed`

- `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql:104` — changed migration

## `auth_internal.reassign_patient_mrn`

- `backend/supabase/migrations/20260724120100_reassign_patient_mrn_rpc.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:493` — changed migration

## `auth_internal.request_ai_status_refresh`

- `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql:470` — changed migration

## `auth_internal.seed_roles_permissions_defaults`

- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:82` — changed migration

## `auth_internal.staff_has_visit_clinical_access`

- `backend/supabase/migrations/20260531180000_visit_medical_records.sql:268` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:2112` — changed migration

## `auth_internal.staff_has_visit_upload_access`

- `backend/supabase/migrations/20260531180000_visit_medical_records.sql:285` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:2130` — changed migration

## `auth_internal.switch_issuer_signing_kid`

- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:1417` — changed migration

## `auth_internal.sync_active_organization`

- `backend/supabase/migrations/20261002120000_membership_active_org.sql:59` — changed migration

## `auth_internal.trg_fill_tenant_organization_id`

- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1279` — changed migration

## `auth_internal.trg_seed_roles_permissions_defaults`

- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:103` — changed migration

## `auth_internal.update_patient`

- `backend/supabase/migrations/20260523140000_patient_management.sql:671` — unchanged supporting prior definition
- `backend/supabase/migrations/20260523140100_fix_update_patient_preserve_gender.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20260523150000_patient_registration_fields.sql:458` — unchanged supporting prior definition
- `backend/supabase/migrations/20260524120000_fix_patient_clearable_fields.sql:15` — unchanged supporting prior definition
- `backend/supabase/migrations/20260525121200_fix_backend_test_alignment.sql:220` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:589` — changed migration
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:789` — changed migration

## `auth_internal.update_role_permission`

- `backend/supabase/migrations/20260522100000_org_branch_management.sql:621` — unchanged supporting prior definition
- `backend/supabase/migrations/20260523120000_fix_role_permission_admin_access.sql:9` — unchanged supporting prior definition
- `backend/supabase/migrations/20260605180000_billing.sql:608` — unchanged supporting prior definition
- `backend/supabase/migrations/20260611150000_remove_owner_role.sql:665` — unchanged supporting prior definition
- `backend/supabase/migrations/20260613140000_role_permissions_full_matrix.sql:19` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:143` — changed migration

## `auth_internal.update_role_permissions`

- `backend/supabase/migrations/20260614100000_settings_code_review_fixes.sql:47` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:257` — changed migration

## `auth_internal.upsert_organization_membership`

- `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql:4` — changed migration

## `auth_internal.user_has_organization_membership`

- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:801` — changed migration

## `auth_internal.verify_aat`

- `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:294` — unchanged supporting prior definition
- `backend/supabase/migrations/20260803140000_b1_review_resolution.sql:616` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:1450` — changed migration

## `public.current_membership_role`

- `backend/supabase/migrations/20261002120000_membership_active_org.sql:273` — changed migration

## `public.current_org_id`

- `backend/supabase/migrations/20261002120000_membership_active_org.sql:200` — changed migration

## `public.get_ai_billing_status`

- `backend/supabase/migrations/20261008010000_read_time_status_notices.sql:349` — changed migration

## `public.get_ai_status`

- `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql:441` — changed migration
- `backend/supabase/migrations/20261008010000_read_time_status_notices.sql:320` — changed migration

## `public.get_custom_claims`

- `backend/supabase/migrations/20260516100300_auth_rbac_functions.sql:80` — unchanged supporting prior definition
- `backend/supabase/migrations/20260516100300_auth_rbac_functions.sql:96` — unchanged supporting prior definition
- `backend/supabase/migrations/20260521110000_auth_rbac_definer_internal_schema.sql:636` — unchanged supporting prior definition
- `backend/supabase/migrations/20260521110000_auth_rbac_definer_internal_schema.sql:646` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002120000_membership_active_org.sql:123` — changed migration

## `public.issue_ai_token`

- `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql:386` — unchanged supporting prior definition
- `backend/supabase/migrations/20260803140000_b1_review_resolution.sql:708` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:1115` — changed migration

## `public.issue_billing_token`

- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:1310` — changed migration

## `public.jwt_branch_ids`

- `backend/supabase/migrations/20260516100200_auth_rbac_rls.sql:69` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:1917` — changed migration

## `public.jwt_organization_id`

- `backend/supabase/migrations/20260516100200_auth_rbac_rls.sql:59` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002120000_membership_active_org.sql:264` — changed migration

## `public.request_ai_status_refresh`

- `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql:533` — changed migration

## `public.rpc_error`

- `backend/supabase/migrations/20260516100300_auth_rbac_functions.sql:137` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:209` — changed migration

## `public.rpc_success`

- `backend/supabase/migrations/20260516100300_auth_rbac_functions.sql:129` — unchanged supporting prior definition
- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql:197` — changed migration

## `public.set_active_organization`

- `backend/supabase/migrations/20261002120000_membership_active_org.sql:148` — changed migration

## `public.staff_login_usernames`

- `backend/supabase/migrations/20260613160000_staff_login_usernames.sql:2` — unchanged supporting prior definition
- `backend/supabase/migrations/20260614100000_settings_code_review_fixes.sql:4` — unchanged supporting prior definition
- `backend/supabase/migrations/20261002150000_tenant_scoping.sql:2073` — changed migration

Coverage-feed puller/status migration remains R7 primary, with R1 supporting review of issuer helper calls and R9 migration/scheduling context. Canonical feed JWT migration is R1 primary. Read-time migration overrides `auth_internal.get_ai_status` and `public.get_ai_status`; R7 must read final read-time definitions instead of stopping at the earlier puller migration. This is navigation, not a finding.
