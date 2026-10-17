# R1 SQL exact coverage and continuation

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; reviewed 2026-10-16. HEAD verified unchanged. Worktree contains the authorized review documents only. This covers the SQL worker, not the sibling consumer regions. **Primary SQL bodies read; overall SQL assignment incomplete until inherited-dependency reviewer completes its named work.**

All paths in the next tables are under `backend/supabase/migrations/`. Ranges are final target line numbers actually displayed/read, not diff counts. Searches are discovery evidence only, not whole-file coverage claims.

## Primary source

| File | Ranges actually read | Disposition |
| --- | --- | --- |
| `20261002120000_membership_active_org.sql` | 1–317, entire file | Membership/backfill, active preference/hook/current-org/current-role; ACLs and malformed/legacy/session cases traced. |
| `20261002150000_tenant_scoping.sql` | 1–2311, entire file, in bounded sections | All 15 child org additions/backfills, invoices restrictive policy, trigger definitions/attachments, permission matrix/defaults, both historical text[] issuers, all definer replacements, branch and permission helpers. Findings 01/04/06; inherited helper finding 05. |
| `20261007180000_issuer_key_custody.sql` | 1–1592, entire file, in bounded sections; 419–493 reread separately after output truncation | Registry and private generator/switch, DROP/replacement signatures, setting/ledger/result-type changes, patient RPC replacements, installed domain dispatch, all three issuers/wrappers/ACLs, verification helper. Installed development cleanup definition at 1551–1592 was read only as deployed migration source/exposure, not fixture data or test implementation; no external test/fixture file read. Its access/caller chain is left to dependency continuation. |
| `20261009120000_fix_staff_membership_session_rls.sql` | 1–715, entire file | Provision/bootstrap membership insertion, repair, own staff/assignment RLS and final drop of assignment-derived membership sync. No lifecycle update/delete trigger. |
| `20261014170000_canonical_billing_jwt_json.sql` | 1–250, entire file | Constrained canonical JSON, final billing function preserving underlying integer signature and revoked execution. |
| `20261014170100_canonical_feed_jwt_json.sql` | 1–76, entire file | Final feed definition and revoked execution. |

Primary total: 5,261 physical source lines, including comments and overwritten bodies. Navigation manifest counts are not proof of inherited dependency completion.

## Supporting source actually read

| File | Read ranges / reason |
| --- | --- |
| `20260516100000_auth_rbac_schema.sql` | 1–70, 116–190; staff authority columns, auth FK, global role schema, assignment shape. Remaining relevant table/index/trigger inventory belongs to continuation. |
| `20260516100100_auth_rbac_audit_triggers.sql` | 1–118 (whole file through displayed application calls); audit-only staff triggers. |
| `20260516100200_auth_rbac_rls.sql` | 1–50; inherited broad table grants and claim accessor start. Other helper declarations located by search, not fully read. |
| `20260521100000_auth_rbac_supabase_linter_fixes.sql` | 110–145; prior staff UPDATE policy and following audit predicate start. |
| `20260521110000_auth_rbac_definer_internal_schema.sql` | 1–130, 735–783; initial default privileges, initial claim/bootstrap/admin helpers, final current_staff_member_row and public grants. Hook trailing grants not fully displayed. |
| `20260524110400_fix_bootstrap_credential_hardening.sql` | 1–80; historical claims helper; superseded final claims tracked below. |
| `20260525120200_fix_restrict_auth_internal_grants.sql` | Entire file (1–EOF); explicit internal wrapper grants and privileged role grants. |
| `20260523140000_patient_management.sql` | 50–75, 184–222; final patient SELECT/mutation denial RLS and assert_org_patient. |
| `20260526140000_appointment_management.sql` | 64–150, 264–308; appointment RLS, historical access helper and final doctor-assignment guard. |
| `20260531180000_visit_medical_records.sql` | 125–250; permissive visits/treatment/attachments read plus mutation denial policies. Grant/definition positions additionally located by rg. |
| `20260601180000_appointment_medium_severity_fixes.sql` | 21–82; final appointment access permission OR helper, following status function preamble. |
| `20260605180000_billing.sql` | 480–608; adjacent provision/discount/seed source displayed while tracing final billing helper positions. RLS/ACL symbols located separately by rg. |
| `20260605180300_billing_rls_permission_gate.sql` | Entire file (1–81); final invoice/payment read helpers, RLS and grants. |
| `20260605181000_billing_us2_payment_rpcs.sql` | 370–400; get_billing_settings inline permission query. |
| `20260606180000_shift_management.sql` | 90–132, 164–205; shift-assignment policies/revokes, shift-manage helper and branch guard preamble. Consumer/consequence supplied by dependency worker, not read by this worker. |
| `20260611150000_remove_owner_role.sql` | 1–130, 820–932; final admin guard, final branch access helper and claims helper, adjacent role migration/policy source. |
| `20260611170000_restore_last_administrator_guard.sql` | 1–284, entire file | Final staff update/deactivation and last-admin check. |
| `20260613210000_delete_staff_member.sql` | Entire file (1–EOF) | Previous delete and helper/ACL lineage; later override read below. |
| `20260614100000_settings_code_review_fixes.sql` | 1–45, 299–385 | Prior usernames/grants and final delete_staff_member; no membership cleanup. |
| `20260628140000_visit_documentation_redesign.sql` | 226–285 | Clinical note/vitals/investigation read/mutation policies. |
| `20260701120000_visit_encounter_workspace.sql` | 1–238 | Safety-table declarations, audit/RLS and patient allergy/medication/chronic-condition policies. |
| `20260712090000_service_catalog.sql` | 122–142, 170–211 | Services permission helper and service-branch policies. |
| `20260801120000_ai_keystore_schema.sql` | 1–90, 117–148 | Private schema/default config, old key schema start, issuance table/RLS. Other declaration positions located by rg. |
| `20260803140000_b1_review_resolution.sql` | 327–434 | Final base64/settings helpers and session verifier. Schema/private-role and function ACL positions located by rg, not whole file. |
| `20261007230000_coverage_feed_puller_status.sql` | 1–105, 320–378, 466–560 | Private projection/feed/refresh tables; removed availability signatures; feed issuer/header consumer and revoked puller ACL/cron; final role-source refresh wrapper. Feed parsing/status behavior remains R7. |
| `20261008010000_read_time_status_notices.sql` | 349–402 | Billing-status authorization and version gate only. Rest remains R7. |

Supplemental metadata-only searches: migration-wide membership writes; staff table UPDATE grants/revokes and triggers; final CREATE OR REPLACE/DROP/ALTER declaration lineage; roles_permissions helper calls; final patient/appointment/staff policies. Only the source ranges above are coverage claims. No migration executable was run.

## Reference material

Read repository AGENTS.md; constitution; review plan sections and packet index/system map; packet-R1; manifest-R1.md, machine manifest backend rows; SQL definition navigation; escalation-R1 resolutions/rationales/amendments/consumer routing. Architecture 02 §§2–3,6–7; 03 §4 and identity registry rows in §3.2; 04 §§2.1,3.1,4.1–4.2. Source-excluded escalation effects were dispositioned from reference metadata, not implementation inspection. Relevant spec 061/062 membership/role/org requirements and 087 issuance/rate requirements read by targeted reference queries; no tests were opened.

## Exact continuation, delegated to r1_sql_dependencies

The coordinator opened a fresh same-phase worker, so these remain explicit work rather than a hidden 'complete' claim:

1. Finish inherited schema/grants/RLS dependencies for every P1-touched table and reviewed RPC, including final inherited patient create/get chains, branch/permission/read helpers, public invoker wrappers and final EXECUTE ACLs. The primary replacements themselves are fully read here. Read final declarations, not superseded versions.
2. Complete all relevant roles_permissions reader inventory (known missing-org read helpers in SQL05; global role checks in SQL04), including effects of final staff_can_access_branch on safety/attachment reads. Resolve unequal-role dual-membership source trace and narrow severity/recipe if needed. SQL04 explicitly states the unequal-role setup is schema-supported but not produced by ordinary provisioning.
3. Verify exact default function/table privileges, schema CREATE access, migration-executor ownership assumptions, and absence of later relevant ACL overrides; no deployed ownership attestation is possible from static source.
4. Trace production grants/callers of installed `invoke_acceptance_domain_rpc`, `verify_aat`, and development cleanup exposure without opening tests/fixtures. Their final installed bodies have been read here.
5. Follow old installation public RPC/text[] drops through actual remaining production callers to establish removal/reachability. The drop statements and integer replacement have been read here; sibling consumer has Dart current callsites.
6. Check supporting callee org filtering reached by create_appointment/patient mutation/read chains where not yet covered here; do not expand into R2–R10 behavior.

Findings and recipes: [R1-sql-review.md](R1-sql-review.md). Initial SQL IDs 01–06 reserved there; continuation should append/refine rather than create duplicates. Coordinator alone updates overall phase tracker.
