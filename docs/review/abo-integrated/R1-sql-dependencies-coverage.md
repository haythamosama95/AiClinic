# R1 SQL dependency coverage checkpoint

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`, 2026-10-16. **Complete with findings for this bounded supporting assignment.** Searches are metadata/lineage evidence; ranges below are actual displayed source, not claims about entire files. Only review documents written.

All SQL paths are under `backend/supabase/migrations/`.

| File | Actual read ranges |
| --- | --- |
| `20261002150000_tenant_scoping.sql` | 1–190, 790–1459, 1910–2035, 2149–2311 |
| `20261002120000_membership_active_org.sql` | 1–85, 190–310 |
| `20261009120000_fix_staff_membership_session_rls.sql` | 1–75 |
| `20261007180000_issuer_key_custody.sql` | 222–493, 1530–1592 (installed helper and ACL/exposure context only) |
| `20260611150000_remove_owner_role.sql` | 1–100, 820–852 |
| `20260802150000_ai_acceptance_recording.sql` | 1–230 |
| `20260805150000_f2_review_resolution.sql` | 1–EOF |
| `20260601180000_appointment_medium_severity_fixes.sql` | 1–100 |
| `20260605180300_billing_rls_permission_gate.sql` | 1–EOF |
| `20260712090000_service_catalog.sql` | 1–220 |
| `20260523140000_patient_management.sql` | 77–90, 184–225, 910–932 |
| `20260724122000_get_patient_include_mrn.sql` | 1–EOF |
| `20260724125000_create_patient_optional_mrn_param.sql` | 196–235 |
| `20260724120000_patient_mrn_field.sql` | 29–45, 274–304 (reset guard only) |
| `20260523150000_patient_registration_fields.sql` | 94–167, 230–298 |
| `20260521110000_auth_rbac_definer_internal_schema.sql` | 1–28, 735–768 |
| `20260525120200_fix_restrict_auth_internal_grants.sql` | 1–EOF |
| `20260516100200_auth_rbac_rls.sql` | 1–100, 280–322 |
| `20260516100300_auth_rbac_functions.sql` | 680–750 |
| `20260516100100_auth_rbac_audit_triggers.sql` | 1–EOF |
| `20260526140000_appointment_management.sql` | 1–100, 263–314 |
| `20260528153000_enforce_appointment_branch_working_hours.sql` | 1–160 (remaining walk-in helper superseded; current appointment helper at 3–82 read) |
| `20260531180000_visit_medical_records.sql` | 1–255 |
| `20260601140000_fix_visit_attachment_storage_admin_branch_access.sql` | 1–112 |
| `20260606180000_shift_management.sql` | 1–260; usage at 578 discovered, not full get_shift body |
| `20260628140000_visit_documentation_redesign.sql` | 1–160, 185–325, 1588–1636; grants1725/1741 found by search |
| `20260711120000_coderabbit_review_fixes.sql` | 397–560 (includes final save_visit_documentation) |
| `20260701120000_visit_encounter_workspace.sql` | 1–310, 1650–1700 (latter overridden get_visit context only) |
| `20260704120000_simplify_vital_signs.sql` | 1–137 |
| `20260707120000_delete_visit_attachment.sql` | 104–EOF (final get_visit) |
| `20260605180000_billing.sql` | 1–215 |
| `20260605181000_billing_us2_payment_rpcs.sql` | 350–445 |
| `20260605230000_billing_us4_insurance_rpcs.sql` | 300–445 |
| `20260712091000_service_catalog_pricing_rpcs.sql` | 1–EOF, in complementary bounded reads |
| `20260605260000_delete_clinic_test_fixtures.sql` | 60–70, grants only; no external test implementation read |
| `20260521170000_fix_staff_claims_org_and_dev_reset_invoker.sql` | 60–68, reset wrapper only |

Other actual source: `frontend/lib/features/ai/acceptance/clinical_acceptance_client.dart` whole file; `backend/supabase/config.toml:12–16`. PostgreSQL authoritative ALTER DEFAULT PRIVILEGES documentation read for static SQL ACL semantics. Full plan requested by parent was loaded with output truncation, then central phase/ownership sections reread; don't infer truncated lines as full reference coverage. Packet/index/manifest/escalation/declaration inventories were loaded; oversized combined JSON output truncated, so only relevant displayed records are reference coverage, not whole inventory claim.

## Fifteen tenant tables: established inheritance

P1 restrictive policies and insertion trigger/attachments read at tenant_scoping 906–1459. Parent mappings: appointments/visits→branch; clinical notes/vitals/investigations/attachments/treatment→visit→branch; invoice items/payments→invoice; number sequence→branch; patient allergy/medication/chronic-condition→patient; service branch→service; shift assignment→shift. Each org NOT NULL/FK, backfill and restrictive policy inspected; invoices already org-bearing receive additional restrictive policy. Trigger rejects parent/session mismatch when session org non-NULL and mismatched supplied org, and fills omitted org; it is INSERT-only. Inherited permissive policies inspected in base appointment/visit/billing-gate/service/shift/clinical-redesign/patient-workspace ranges above. Direct mutation policies deny; definer consumers require independent guards.

## Final closure reads and disposition

The earlier checkpoint's five remaining items are closed below. No inherited source remains unread **within this bounded R1 authority assignment**; this is not a claim to audit all historical domain code.

- Appointment helpers: `20260711170000_coderabbit_review_fixes_61_70.sql:1–72`; `20260615120000_remove_appointment_max_duration.sql:1–15`; `20260526140000_appointment_management.sql:415–457,1053–1074`; `20260528150500_appointment_slot_and_patient_day_conflicts.sql:95–138`; `20260628160000_simplified_slot_booking.sql` whole file (only overlap and guarded slot consumer relevant).
- Primary wrappers/ACL: `20260618120000_get_appointment.sql:80–EOF`; `20260531180000_visit_medical_records.sql:2150–2170,2190–2230`; `20260605180500_billing_us1_rpcs.sql:1048–1068`; `20260605240000_billing_us5_list_patient_invoices.sql` whole file; `20260611150000_remove_owner_role.sql:1008–1035`; `20260614100000_settings_code_review_fixes.sql:140–158` plus explicit staff-login grant/revoke lines43–44 located; `20261002150000_tenant_scoping.sql:1588–1687,2074–2149`; `20260527150000_grant_appointment_auth_internal_execute.sql` whole file.
- Patient overloads: `20260524120000_fix_patient_clearable_fields.sql:241–280`; `20260724120100_reassign_patient_mrn_rpc.sql:98–110`; custody `493–789,789–964` complementary reads (all patient mutation bodies now displayed across reads; 9-argument public wrapper694–729 found through lineage and SQL-primary context, no signature change); helpers previously covered.
- Billing lock guard-only consumer reads (not whole body coverage): `20260605180500_billing_us1_rpcs.sql:214–231,503–531,581–600`; `20260605290000_fix_billing_review_items_4_8_12.sql:19–42,129–162`; `20260605310000_fix_billing_review_items_18_21_24.sql:28–55,178–230`; `20260605230000_billing_us4_insurance_rpcs.sql:9–32`; `20260712091500_service_catalog_billing_integration.sql:16–47`; `20260727140000_remove_payment_reference.sql:6–43`. Source prefixes read directly from final function declaration inventory; each guard is before its lock. No billing-algorithm review claim.
- Schema/policy closure: `20260605180000_billing.sql:215–232,478–488`; complete extracted ALTER TABLE statements for all fifteen table names across migrations, including the previously unread declarations at `20260701120000:1387–1407`, `20260702120000:526–527`, `20260704120000:550`, `20260712091500:5–6`, `20260727140000:3–4`, `20260627120000:3–5`, `20260527170000:3–4`, `20260531120000:9–17`, `20260601100000:3–4`, `20260628140000:161–163`. No production ALTER POLICY found. No later RLS disable/parent-FK replacement/owner/FORCE RLS statements found. These are exact extracted DDL source statements, not whole-file reads.
- Storage helper closure: `20260601150000_fix_visit_storage_visit_exists_helper.sql` whole file; prior storage helper grant lines192–206 in `20260601140000` and final staff branch fallback previously read.
- Inline reader/public grant closure: `20260605181000_billing_us2_payment_rpcs.sql:445–EOF`; `20260701120000_visit_encounter_workspace.sql:2030–2060`; service whole file already covered. Invoice list wrappers rely on native PUBLIC EXECUTE or external defaults for internal functions; no explicit repository internal grant/revoke found. This is a bounded deployment-default assumption, not a proven unauthorized API path or proven broken function.

Canonical findings remain SQL01–06 in the SQL owner's report; this dependency review supplies exact five shared + nine inline SQL05 edit targets, staff_can_access_branch SQL04 extension, runtime acceptance caller/registry/ACL trace, and verified SQL privilege-semantic caveat. SQL04 trigger qualified and P2 per coordinator; no independently ordinary unequal-role producer was proved. SQL03 correction preserves membership/preference rows and denies effective authority via live-staff checks.

No phase-tracker edit; coordinator owns tracker and final synthesis. Runtime production ownership/ACL/environment attestation remains impossible under static source-only scope and is routed to R9 as an operational limit.
