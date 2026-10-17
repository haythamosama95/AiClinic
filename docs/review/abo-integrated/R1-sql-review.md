# R1 SQL source review

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. Static source review, 2026-10-16. **Result: incomplete — primary SQL read, inherited authorization dependency continuation required.** Coverage and exact continuation are in [R1-sql-coverage.md](R1-sql-coverage.md). Findings below are source-established, not runtime reproductions. No source changes, tests, builds, lint, services, or branch changes.

Paths below are relative to `backend/supabase/migrations/` unless stated otherwise. These are SQL subreport IDs; the phase coordinator owns final deduplication.

## Authority and complete producer traces

`public.set_active_organization` checks membership and updates the per-user stored preference. The auth hook reads that preference through `sync_active_organization` and writes `active_org`; switching requires refreshing the Supabase session. `current_org_id` selects the session `active_org`, or legacy `organization_id` only when `active_org` is absent, validates UUID/sub and checks `(user_id, organization_id)` membership. Empty/malformed/removed membership yields NULL. It deliberately does not compare the stored preference on every call. `current_membership_role` reads that membership row. The helpers do not consult active/deleted staff state.

Final issuer SQL definitions and ACLs:

| Producer | Final definition | Claims / bounds / access |
| --- | --- | --- |
| AI | `20261007180000_issuer_key_custody.sql:964–1138` | Authenticated public versioned wrapper; session expiry, live active staff, current org membership and active assigned branch in that org; `sub=staff.id`, membership role and org-local `ai.*` scopes; `aud=ai-platform`, `ver="2"`, 600s. Internal integer signature revoked from PUBLIC/anon/authenticated/service_role. Old text[] signatures dropped. **No issuance rate check remains.** |
| Billing | `20261014170000_canonical_billing_jwt_json.sql:78–250`, public wrapper retained at custody `1311–1338` | Same staff/branch checks plus membership administrator; `aud=abo`, `role=administrator`, 300s, no scopes. Advisory transaction lock `(87201402, hashtext(staff.id || ':abo'))`, 20 live ledger rows/staff/audience/10 minutes; count and insertion in same transaction. |
| Feed | `20261014170100_canonical_feed_jwt_json.sql:4–76` | Internal only, no public wrapper; `aud=ai-platform-feed`, `sub=backend-feed`, no org/role/branch/scopes, 120s. Puller calls it and attaches only this bearer to platform URL. |

All share Ed25519 signing from the sole `issuer_key.status='signing'`, Vault secret lookup by `secret_ref`, common backend issuer id, UUID jti, integer iat/exp and `typ=JWT`. Billing/feed use the recursive constrained canonical JSON helper; AI intentionally uses ordinary JSON and sibling consumer reviewer confirms its custom verifier accepts it. No SQL client argument chooses org, audience, scopes or role. Already-minted token authority is bounded by receiver-enforced expiry, not vendor membership lookups; sibling consumer findings about billing/feed expiry must be fixed independently.

Custody `9–127` creates public-key/Vault-reference registry with unique partial signing/next indexes, deny-all RLS, private generator with explicit revoke, initial signing key then next keys. `1418–1449` switches only next→signing and old signing→retired transactionally; no clinic role grant or public wrapper. Backend statuses differ intentionally from verifier active/retiring/revoked (087:1). Signing functions do not enforce backend key dates; receiver validity and operational rotation remain essential. Source does not attest deployed owners or Vault ACLs: CREATE functions inherit migration executor ownership; no explicit ALTER OWNER was found. Search paths are fixed; table accesses and crypto/vault functions are qualified. Untrusted schema CREATE permissions need final continuation verification.

P1 adds org columns/backfills and restrictive org policies to fifteen child tables, plus invoices; its insert trigger derives org from parent, rejects a conflicting non-NULL session org and supplied org, and fills omitted org. Each changed definer lookup adds org constraints plus branch filtering where relevant. Tenant filters prevent foreign tenant IDs in the reviewed lookups, but do not repair the authorization defects below. Final session-RLS migration makes own staff/assignment reads possible while keeping colleague visibility membership-gated and adds memberships in provisioning/bootstrap only.

## Findings

### R1-SQL-01 — P1: Any tenant member can modify staff authority directly

**High confidence; implementation-ready.** `20261002150000_tenant_scoping.sql:841–858` permits UPDATE of any non-deleted staff row whose auth user is a member of the caller's org, with the same membership predicate as WITH CHECK. It has no caller permission or protected-column predicate. The inherited authenticated table-wide UPDATE grant remains (`20260516100200_auth_rbac_rls.sql:28`); the final SELECT policy permits one's own row (`20261009120000_fix_staff_membership_session_rls.sql:58–76`). Staff `role`, `is_active`, and `is_bootstrap_admin` are ordinary writable columns (`20260516100000_auth_rbac_schema.sql:116–133`). The only identified staff triggers stamp audit fields, not authority.

A doctor can PATCH their own `role='administrator'` (or bootstrap flag); `assert_owner_or_administrator` then reads that modified live row (`20260611150000_remove_owner_role.sql:58–90`) and authorizes administrative RPCs. They can also disable colleagues without the last-administrator checks. No JWT refresh is needed for definer checks. This is an inherited flaw retained by a newly rewritten P1 security surface, within this review's explicit inherited-authority scope. It is tenant-level privilege escalation, not demonstrated cross-tenant compromise; P1, not P0.

**Fix steps:**
1. Add a forward migration revoking table-level UPDATE on `public.staff_members` from authenticated/PUBLIC/anon and removing the permissive `staff_members_update` policy. Keep profile/settings changes through guarded existing RPCs; do not grant individual authority columns.
2. Retain the existing `StaffAdminRepositoryImpl` RPC callers (`update_staff_member`, `set_staff_active`, `delete_staff_member`); the coordinator checked production frontend callers and found staff table SELECTs plus these RPC writes, with no direct staff UPDATE caller. No new profile endpoint is needed.
3. Preserve existing administrator-count, org/branch and permission checks in RPC bodies. Apply this grant closure **before** membership lifecycle synchronization, so a direct role edit cannot promote membership.
4. Completion: an ordinary member cannot directly update any staff authority/status column or another person's profile; authorized RPC updates still work; denied direct calls leave staff, memberships and audit facts unchanged.

### R1-SQL-02 — P1: Staff demotion never updates membership billing authority

**High confidence. Code remedy implementation-ready, depends on 01; existing multi-membership data repair is not implementation-ready pending per-row maintainer/clinic administrator role decisions.** Provisioning writes `ai_internal.membership.role` (`20261009120000_fix_staff_membership_session_rls.sql:436,676`), but final `auth_internal.update_staff_member` changes only `staff_members.role` and assignments (`20260611170000_restore_last_administrator_guard.sql:51–214`). No later membership synchronization trigger/write exists. Final billing mint checks membership role and only checks staff active/deleted, not its role (`canonical_billing_jwt_json.sql:104–136`). Thus an administrator legitimately demoted to doctor remains able to mint fresh administrator billing tokens forever; promotion fails inversely. AI token roles/scopes also remain stale. This exceeds the accepted short cached-token lifetime.

**Fix steps:**
1. After 01, add a forward override of `auth_internal.update_staff_member` that locks and verifies the target membership for `current_org_id()` and atomically updates that row's role with the authorized staff change. Do not overwrite roles of that user in other orgs.
2. Treat membership role as authorization authority throughout (04 below); retain `staff_members.role` only for the existing compatibility/profile representation, never as a substitute for the target org membership. Do not infer role from branch assignment creation.
3. Reconcile pre-existing mismatch rows: only auto-copy legacy staff role when a user has exactly one membership; flag multi-membership mismatches for the maintainer/clinic administrator to approve each intended per-org role rather than flattening their roles. Stop before changing those rows until the decision arrives; do not infer intention from the legacy global role. Include approved repair in deployment sequencing.
4. Completion: demotion denies all new billing mints immediately after commit and emits reduced AI scopes; promotion permits new billing mints; a user with different roles in A/B keeps B unchanged. Already-minted tokens retain only the separately enforced 300/600s window.

### R1-SQL-03 — P1: Deactivated/deleted staff retain tenant membership on backend reads

**High confidence; implementation-ready, depends on 01.** Final deactivate (`20260611170000_restore_last_administrator_guard.sql:216–284`) and delete (`20260614100000_settings_code_review_fixes.sql:299–385`) never alter membership. `current_org_id`/`current_membership_role` (`20261002120000_membership_active_org.sql:201–317`) read membership only. Direct patient SELECT checks org but no live staff state (`20260523140000_patient_management.sql:50–56`); appointments additionally rely on JWT branch IDs whose helper does not recheck live assignments/staff (`tenant_scoping.sql:1918–1946`). A staff member deactivated or soft-deleted while their session is live can continue reading clinic records. `get_ai_billing_status` and refresh also authorize membership role without active staff checks. Minting itself does check staff and is blocked after deactivation; this does not close direct reads.

**Fix steps:**
1. In a forward migration make `current_org_id` require a non-deleted, active `staff_members` row for the JWT sub in addition to its existing membership check. Preserve bootstrap-only setup paths explicitly; do not restore an org fallback for a removed member.
2. Apply the same live-staff predicate to `sync_active_organization` and `set_active_organization`, so disabled users neither receive nor select tenant context. `current_membership_role` will then fail closed through current_org_id.
3. In final delete_staff_member delete that auth user's memberships and stored active preference in the same transaction as staff soft deletion. These are authorization association rows, not clinical hard deletion. Deactivation should preserve memberships/roles for reactivation while the common active predicate denies them.
4. Completion: existing sessions receive no tenant context or patient/appointment/billing-status data immediately after disable/delete; reactivation restores preserved memberships only for non-deleted staff; token mints remain blocked. Fix receiver expiry separately so cached vendor tokens cannot survive their intended lifetime.

### R1-SQL-04 — P1: Backend administrative permission checks use global staff role

**High confidence; implementation-ready, dependent on 01/02.** `auth_internal.assert_permission` uses `rp.role=v_staff.role` (`tenant_scoping.sql:1948–1994`), while `assert_owner_or_administrator` trusts that same global role (`remove_owner_role.sql:58–90`). For a dual-membership database state with global staff role administrator, membership administrator in A and doctor in B (the per-membership schema permits this; ordinary provisioning creates new auth users and does not itself establish this unequal-role state), that user can switch to B and call `update_role_permission(s)`; their first check sees global administrator and writes B's permission matrix. AI/billing token issuers correctly use B's membership role, so the backend and vendors disagree on current authority. Clinical/upload permission helpers at `tenant_scoping.sql:2113–2148` also join the global role.

**Fix steps:**
1. Add forward overrides of `assert_permission`, `assert_owner_or_administrator`, and reviewed staff clinical/upload helpers plus `staff_can_access_branch` (`remove_owner_role.sql:820–844`), resolving role from `current_membership_role()` once current org is non-NULL. A NULL membership role must deny.
2. Retain bootstrap exception only when active bootstrap staff exists **and no organization exists**. A bootstrap flag must not bypass an existing org's membership role.
3. Coordinate final inherited appointment/billing/services helpers with 05: every org-local permission lookup uses `(current_org_id(), current_membership_role())`; keep existing active staff checks.
4. Completion: global administrator/member doctor B cannot edit B role permissions or invoke B administrator-only provisioning, even with fresh/stale staff-role JWT claims. Member administrator B remains authorized independently of the global compatibility role; A remains unchanged. R7 handoff: the auth hook/`build_staff_claims`, JWT `staff_role` and session-context loader still use the global compatibility role for display; align org-specific role presentation with these authority changes without treating that UI as the enforcement boundary.

### R1-SQL-05 — P1: Inherited permission helpers borrow another tenant's grants

**High confidence; known helper remedy ready, full reader inventory/fix target list pending inherited-dependency continuation. Do not implement an incomplete helper-only repair.** Final `assert_appointment_access` (`20260601180000_appointment_medium_severity_fixes.sql:23–62`), billing read helpers (`20260605180300_billing_rls_permission_gate.sql:3–35`) and services helper (`20260712090000_service_catalog.sql:122–138`) query `roles_permissions` without `organization_id`. They run SECURITY DEFINER, so its SELECT RLS does not constrain the query. After P1 creates one matrix per org, a grant for the same role in B satisfies an explicit denial in A. A's tenant filters still confine returned rows to A, but its administrator's permission decisions fail. Changed `get_appointment` and settings call the appointment helper; invoice/item/payment/service-branch SELECT policies use these read helpers.

**Fix steps:**
1. Add forward overrides of appointment access, both billing read helpers and services read helper: require `rp.organization_id=public.current_org_id()` and `rp.role=public.current_membership_role()`, with active/non-deleted caller staff, preserving each helper's permission-key OR set.
2. Apply the same predicates to the inline fallback in `auth_internal.get_billing_settings` (`20260605181000_billing_us2_payment_rpcs.sql:381–393`) and also apply them to `staff_has_shifts_manage` (`20260606180000_shift_management.sql:164–179`, secondary read-only-display effect), and inventory equivalent final readers in the inherited continuation; use 04's membership-role authority consistently.
3. Keep tenant restrictive RLS and public wrappers/grants; change permission evaluation, not data visibility or response wire shapes.
4. Completion: A denies appointment/invoice/payment/service reads when only B grants the same role; enabling A's exact permission permits it; global staff role cannot substitute for A's membership role. No B facts are returned.

### R1-SQL-06 — P2: Final AI issuer drops its issuance rate limit

**High confidence; implementation-ready.** Previous final text[] issuer serialized per-staff ledger count and enforced configured rate ceiling/window (`tenant_scoping.sql:701–723`). The custody integer replacement `964–1114` signs and inserts on every permitted call with no lock/count/refusal. Billing retains a separate throttle. `03-abo-data-model-and-lifecycle.md:255` and spec 087 FR-007 preserve per-audience rate limits. An authenticated AI member can now incur unbounded signing and issuance-ledger writes; platform admission rate limits do not protect this backend endpoint. This is bounded resource/contract regression, not demonstrated uncontrolled coverage creation, hence P2.

**Fix steps:**
1. Add a forward override of `auth_internal.issue_ai_token(integer)` restoring the prior per-staff advisory transaction lock and configured ceiling/window, filtering ledger `aud='ai-platform'` and `is_deleted=false`.
2. Count and reject `RATE_LIMITED` before key secret loading/signing/insertion; leave 600s lifetime and membership/branch/scope validation unchanged. Billing's 20/10min counter remains independent.
3. Completion: the configured AI ceiling's next call fails without a new ledger row; concurrent mints cannot overshoot; billing mints do not consume AI quota and vice versa.

## Escalations and handoff

SQL directly resolves 087:1 (private backend statuses/switch); sibling owns platform/pin propagation of 066:1/4. 066:2/3 are consumer binding/cap rules; 066:5 adds no independent rule; 066:6 final cache/admission removal goes to R5/R8. 066:7/8/9 and 087:2 have excluded harness effects; no harness implementation inspected. 076:1 host/version/ledger effects and 077:1 checkout jti/return remain R2/R3; SQL emits UUID jti. 088:1's role source is subject to 02–04; exact throttle behavior and status refusal versioning remain R7, not declared reviewed here.

R2/R3/R5/R7 must consume the authority table and SQL findings alongside the sibling consumer report. All findings require forward migrations rather than editing historical migration files alone. No finding depends on a live provider assumption. Deployed executor ownership, private key configuration and actual key ceremonies remain operational limits.
