# R1 bounded source manifest

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Deletions use baseline coordinates. Inventory only; no source reviewed by preparation.

| Path | Lines | Symbol / region | Revision |
| --- | --- | --- | --- |
| `abo/src/clinic-api/auth.ts` | 1–3 | preamble / imports / shared declarations | T |
| `abo/src/clinic-api/auth.ts` | 4–5 | textEncoder | T |
| `abo/src/clinic-api/auth.ts` | 6–12 | BillingAuthEnv | T |
| `abo/src/clinic-api/auth.ts` | 13–22 | BillingClaims | T |
| `abo/src/clinic-api/auth.ts` | 23–27 | AuthSuccess | T |
| `abo/src/clinic-api/auth.ts` | 28–32 | AuthFailure | T |
| `abo/src/clinic-api/auth.ts` | 33–50 | base64UrlDecode | T |
| `abo/src/clinic-api/auth.ts` | 51–59 | parseJsonUtf8 | T |
| `abo/src/clinic-api/auth.ts` | 60–63 | isRecord | T |
| `abo/src/clinic-api/auth.ts` | 64–75 | importEd25519PublicKey | T |
| `abo/src/clinic-api/auth.ts` | 76–120 | loadIssuerPins | T |
| `abo/src/clinic-api/auth.ts` | 121–133 | extractBearerToken | T |
| `abo/src/clinic-api/auth.ts` | 134–149 | readJwtKid | T |
| `abo/src/clinic-api/auth.ts` | 150–186 | verifyJwtSignature | T |
| `abo/src/clinic-api/auth.ts` | 187–209 | claimsFromPayload | T |
| `abo/src/clinic-api/auth.ts` | 210–222 | lifetimeValid | T |
| `abo/src/clinic-api/auth.ts` | 223–310 | authenticateBilling | T |
| `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql` | 1–11 | preamble / imports / shared declarations | T |
| `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql` | 12–28 | tenant_binding | T |
| `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql` | 29–41 | token_contract | T |
| `ai-platform/src/identity/index.ts` | 1–16 | preamble / imports / shared declarations | T |
| `ai-platform/src/identity/index.ts` | 17–29 | Principal | T |
| `ai-platform/src/identity/index.ts` | 30–44 | VerifyContext | T |
| `ai-platform/src/identity/index.ts` | 45–48 | VerifyResult | T |
| `ai-platform/src/identity/index.ts` | 49–53 | TokenVerifier | T |
| `ai-platform/src/identity/index.ts` | 54–55 | MAX_AAT_LIFETIME_SECONDS | T |
| `ai-platform/src/identity/index.ts` | 56–58 | ONE_DAY_MS | T |
| `ai-platform/src/identity/index.ts` | 59–60 | UNVERIFIED_INSTALLATION_BUCKET | T |
| `ai-platform/src/identity/index.ts` | 61–74 | AatPayload | T |
| `ai-platform/src/identity/index.ts` | 75–82 | rejectUnauthenticated | T |
| `ai-platform/src/identity/index.ts` | 83–90 | rejectSuspended | T |
| `ai-platform/src/identity/index.ts` | 91–104 | base64urlDecode | T |
| `ai-platform/src/identity/index.ts` | 105–112 | parseJson | T |
| `ai-platform/src/identity/index.ts` | 113–116 | isString | T |
| `ai-platform/src/identity/index.ts` | 117–157 | parsePayloadClaims | T |
| `ai-platform/src/identity/index.ts` | 158–173 | buildPrincipal | T |
| `ai-platform/src/identity/index.ts` | 174–198 | importEd25519PublicKey | T |
| `ai-platform/src/identity/index.ts` | 199–225 | isIssuerKeyWithinValidityWindow | T |
| `ai-platform/src/identity/index.ts` | 226–239 | isIssuerKeyUsable | T |
| `ai-platform/src/identity/index.ts` | 240–254 | loadConfigAt | T |
| `ai-platform/src/identity/index.ts` | 255–271 | countEpochOneBindingsLast24Hours | T |
| `ai-platform/src/identity/index.ts` | 272–286 | readLiveBindingFromD1 | T |
| `ai-platform/src/identity/index.ts` | 287–294 | readMaxBindingEpoch | T |
| `ai-platform/src/identity/index.ts` | 295–394 | resolveInstallationId | T |
| `ai-platform/src/identity/index.ts` | 395–556 | IssuerTokenVerifier | T |
| `ai-platform/src/vendor/entrypoint.ts` | 209–219 | IssuerKeyRow | T |
| `ai-platform/src/vendor/entrypoint.ts` | 220–230 | ServiceKeyRow | T |
| `ai-platform/src/vendor/entrypoint.ts` | 309–322 | issuerKeyRowToDetail | T |
| `ai-platform/src/vendor/entrypoint.ts` | 328–341 | readIssuerKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 342–355 | serviceKeyRowToDetail | T |
| `ai-platform/src/vendor/entrypoint.ts` | 356–369 | readServiceKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 548–562 | readActiveTenantBinding | T |
| `ai-platform/src/vendor/entrypoint.ts` | 563–577 | readLiveTenantBinding | T |
| `ai-platform/src/vendor/entrypoint.ts` | 578–591 | readTenantBindingForInstallation | T |
| `ai-platform/src/vendor/entrypoint.ts` | 592–602 | readMaxTenantBindingEpoch | T |
| `ai-platform/src/vendor/entrypoint.ts` | 676–688 | serviceKeyActiveAt | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2193–2315 | registerIssuerKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2316–2349 | listIssuerKeys | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2350–2444 | retireIssuerKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2445–2528 | revokeIssuerKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2529–2650 | registerServiceKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2651–2734 | revokeServiceKey | T |
| `ai-platform/src/vendor/entrypoint.ts` | 2735–2765 | listServiceKeys | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 1–2 | preamble / imports / shared declarations | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 3–12 | ai_internal.membership | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 13–40 | membership_deny_all | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 41–48 | ai_internal.user_active_organization | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 49–58 | user_active_organization_deny_all | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 59–122 | auth_internal.sync_active_organization | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 123–148 | public.get_custom_claims | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 149–200 | public.set_active_organization | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 201–264 | public.current_org_id | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 265–273 | public.jwt_organization_id | T |
| `backend/supabase/migrations/20261002120000_membership_active_org.sql` | 274–317 | public.current_membership_role | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1–16 | preamble / imports / shared declarations | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 17–25 | auth_internal.roles_permissions_default_template | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 26–82 | roles_permissions_default_template_deny_all | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 83–103 | auth_internal.seed_roles_permissions_defaults | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 104–116 | auth_internal.trg_seed_roles_permissions_defaults | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 117–127 | seed_roles_permissions_defaults | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 128–143 | roles_permissions_select | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 144–257 | auth_internal.update_role_permission | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 258–394 | auth_internal.update_role_permissions | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 395–410 | ai_token_issuance_select | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 411–605 | auth_internal.issue_ai_token | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 606–801 | auth_internal.issue_ai_token | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 802–827 | auth_internal.user_has_organization_membership | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 828–840 | staff_members_select | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 841–864 | staff_members_update | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 865–916 | staff_branch_assignments_select | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 917–940 | appointments_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 941–965 | visits_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 966–990 | visit_clinical_notes_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 991–1015 | visit_vital_signs_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1016–1040 | visit_investigations_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1041–1065 | visit_attachments_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1066–1089 | treatment_plans_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1090–1113 | invoice_items_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1114–1137 | payments_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1138–1161 | invoice_number_sequences_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1162–1185 | patient_allergies_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1186–1209 | patient_medications_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1210–1233 | patient_chronic_conditions_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1234–1257 | service_branches_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1258–1269 | shift_assignments_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1270–1279 | invoices_org | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1280–1367 | auth_internal.trg_fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1368–1373 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1374–1379 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1380–1385 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1386–1391 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1392–1397 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1398–1403 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1404–1409 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1410–1415 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1416–1421 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1422–1427 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1428–1433 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1434–1439 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1440–1445 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1446–1451 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1452–1460 | fill_tenant_organization_id | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1461–1542 | auth_internal.get_appointment | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1543–1587 | auth_internal.get_visit_by_appointment | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1588–1613 | auth_internal.assert_invoice_branch_scope | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1614–1652 | auth_internal.lock_draft_invoice | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1653–1686 | auth_internal.lock_payable_invoice | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1687–1885 | auth_internal.list_invoices | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1886–1917 | auth_internal.list_patient_invoices | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1918–1947 | public.jwt_branch_ids | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1948–1996 | auth_internal.assert_permission | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 1997–2033 | auth_internal.assert_appointment_branch | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 2034–2073 | auth_internal.get_appointment_settings | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 2074–2112 | public.staff_login_usernames | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 2113–2130 | auth_internal.staff_has_visit_clinical_access | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 2131–2148 | auth_internal.staff_has_visit_upload_access | T |
| `backend/supabase/migrations/20261002150000_tenant_scoping.sql` | 2149–2311 | auth_internal.create_appointment | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 1–8 | preamble / imports / shared declarations | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 9–28 | ai_internal.issuer_key | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 29–32 | issuer_key_deny_all | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 33–184 | auth_internal.insert_issuer_kid | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 185–197 | ai_token_issuance_actor_aud_iat_idx | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 198–209 | public.rpc_success | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 210–222 | public.rpc_error | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 223–418 | auth_internal.create_patient | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 419–493 | auth_internal.invoke_acceptance_domain_rpc | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 494–589 | auth_internal.reassign_patient_mrn | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 590–789 | auth_internal.update_patient | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 790–963 | auth_internal.update_patient | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 964–1115 | auth_internal.issue_ai_token | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 1116–1139 | public.issue_ai_token | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 1140–1310 | auth_internal.issue_billing_token | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 1311–1339 | public.issue_billing_token | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 1340–1417 | auth_internal.issue_feed_token | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 1418–1450 | auth_internal.switch_issuer_signing_kid | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 1451–1550 | auth_internal.verify_aat | T |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 1551–1592 | auth_internal.delete_clinic_test_fixtures | T |
| `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` | 1–4 | preamble / imports / shared declarations | T |
| `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` | 5–57 | auth_internal.upsert_organization_membership | T |
| `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` | 58–76 | staff_members_select | T |
| `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` | 77–129 | staff_branch_assignments_select | T |
| `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` | 130–208 | auth_internal.bootstrap_create_organization | T |
| `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` | 209–313 | auth_internal.bootstrap_create_branch | T |
| `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` | 314–466 | auth_internal.create_staff_account | T |
| `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` | 467–715 | auth_internal.bootstrap_finish_setup | T |
| `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql` | 1–4 | preamble / imports / shared declarations | T |
| `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql` | 5–77 | auth_internal.canonical_issuer_jwt_json | T |
| `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql` | 78–250 | auth_internal.issue_billing_token | T |
| `backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql` | 1–3 | preamble / imports / shared declarations | T |
| `backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql` | 4–76 | auth_internal.issue_feed_token | T |
| `frontend/lib/core/ai/supabase_aat_mint_port.dart` | 1–12 | preamble / imports / shared declarations | T |
| `frontend/lib/core/ai/supabase_aat_mint_port.dart` | 13–41 | SupabaseAatMintPort | T |
| `frontend/lib/core/rpc/app_rpc_invoker.dart` | 1–111 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/billing/billing_token_client.dart` | 1–12 | preamble / imports / shared declarations | T |
| `frontend/lib/features/ai/billing/billing_token_client.dart` | 13–27 | BillingTokenSession | T |
| `frontend/lib/features/ai/billing/billing_token_client.dart` | 28–128 | BillingTokenClient | T |

## Unchanged supporting dependencies

- `ai-platform/src/alert` ← `ai-platform/src/identity/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/alert` ← `ai-platform/src/identity/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/config-cache` ← `ai-platform/src/identity/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/logger.ts` ← `ai-platform/src/identity/index.ts`: unchanged supporting dependency; read only as required by owned invariant
- `ai-platform/src/rate-limit` ← `ai-platform/src/identity/index.ts`: unchanged supporting dependency; read only as required by owned invariant
