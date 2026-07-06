# Backend Architecture Review — Third Pass (AUTH, RPC, GRANTS)

**Date:** 2026-07-05  
**Scope:** `auth_internal` functions, `public` SECURITY INVOKER wrappers, GRANT EXECUTE chains (`authenticated` → `public` → `auth_internal`), GoTrue hooks/JWT claims, staff provisioning RPCs, PostgREST table exposure vs RPC-only mutations, auth/authz edge cases  
**Prior art:** [backend-architecture-review.md](./backend-architecture-review.md), [backend-architecture-review-second-pass.md](./backend-architecture-review-second-pass.md)  
**Method:** Targeted grep/read of migrations and tests; all first/second-pass Critical and High items treated as already reported.

---

## Executive Summary

Third pass focused on grant-chain integrity, JWT vs live authorization, and staff/bootstrap RPC edges **not covered** in prior reviews. It confirms prior Critical/High items (C-01/C-02, H-01–H-25) still present and adds **three new High** findings:

1. **`bootstrap_finish_setup` INVOKER chain broken** after signature change (12th parameter added; `auth_internal` grant left on 11-param signature).
2. **`admin_update_staff_username` missing `auth_internal` EXECUTE grant** (public INVOKER wrapper only).
3. **RLS and branch-access helpers trust stale JWT claims** instead of live `staff_members` state (deactivated staff retain read access; demoted administrators retain org-wide branch access until token expiry).

**No new Critical findings.**

| Severity | New in 3rd pass |
|----------|-----------------|
| Critical | 0 |
| High     | 3 |

*Synthesis doc renumbers these as H-31–H-33 to avoid collision with config findings H-26–H-30.*

---

## 1. Critical Issues

*None new. Prior C-01 (`staff_members` PATCH escalation) and C-02 (service-catalog `auth_internal` grants) re-verified still open.*

---

## 2. High Priority Issues (New)

### H-26 — `bootstrap_finish_setup` `auth_internal` EXECUTE grant signature drift (INVOKER chain broken)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260611140000_allow_admin_create_owner_and_atomic_bootstrap_setup.sql`, `backend/supabase/migrations/20260613120000_bootstrap_finish_setup_working_schedule.sql`, `backend/supabase/migrations/20260613150000_create_staff_account_phone.sql` |
| **Evidence** | Only `auth_internal` grant is at `20260611140000:593-595` on **11-parameter** signature. `20260613120000` adds `p_branch_working_schedule jsonb` (12th param) via `CREATE OR REPLACE` — a new function identity in PostgreSQL. `20260613120000:279-281` re-grants **public** 12-param wrapper only; no matching `auth_internal` re-grant. Public wrapper is `SECURITY INVOKER` (`20260613120000:240-273`). |
| **Why it is a problem** | PostgREST runs as `authenticated`. INVOKER wrapper requires `EXECUTE` on the **current** `auth_internal` function signature. Orphan 11-param grant does not cover the 12-param function. |
| **Potential impact** | Atomic clinic bootstrap (`bootstrap_finish_setup`) fails under PostgREST for all callers, including paths passing `p_branch_working_schedule` (see `backend/tests/bootstrap_rpc.sql:290-309`). Separate bootstrap RPCs may still work, but the intended atomic setup path is broken in production. Tests pass as `postgres` superuser. |
| **Recommended solution** | Add migration: `GRANT EXECUTE ON FUNCTION auth_internal.bootstrap_finish_setup(text, text, jsonb, jsonb, text, text, text, text, text, text, text, jsonb) TO authenticated;` Add grant regression test modeled on `appointment_management_grants.sql`. |

---

### H-27 — `admin_update_staff_username` missing `auth_internal` EXECUTE grant

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260613200000_admin_update_staff_username.sql`, `backend/supabase/migrations/20260614000000_fix_admin_update_staff_username_forbidden.sql` |
| **Evidence** | `public.admin_update_staff_username` is `SECURITY INVOKER` (`20260613200000:114-124`). Only grant: `GRANT EXECUTE ON FUNCTION public.admin_update_staff_username(uuid, text) TO authenticated` (`20260613200000:127`). Repository-wide grep: **zero** `GRANT EXECUTE ON FUNCTION auth_internal.admin_update_staff_username`. Contrast `delete_branch` / `delete_staff_member`, which grant both `public` and `auth_internal` (`20260613130000:86-87`, `20260613210000:192-193`). |
| **Why it is a problem** | Same INVOKER grant-gap class as H-09/H-10/C-02. Wrapper delegates to `auth_internal.admin_update_staff_username`; `authenticated` lacks EXECUTE on the definer function. |
| **Potential impact** | Staff username changes non-functional via API; settings credential management broken under PostgREST. SQL tests pass as superuser (`admin_update_staff_username.sql:28` uses `set_config('role', 'postgres', true)`). |
| **Recommended solution** | `GRANT EXECUTE ON FUNCTION auth_internal.admin_update_staff_username(uuid, text) TO authenticated;` in same migration pattern as other settings RPCs. |

---

### H-28 — JWT-stale authorization: RLS and `staff_can_access_branch` trust claims over live staff state

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files involved** | `backend/supabase/migrations/20260528133000_fix_staff_branch_assignments_rls_recursion.sql`, `backend/supabase/migrations/20260611150000_remove_owner_role.sql` (`staff_can_access_branch`), `backend/supabase/migrations/20260523140000_patient_management.sql` (`patients_select`), `backend/local/docker-compose.yml` (`GOTRUE_JWT_EXP: 3600`) |
| **Evidence** | `staff_branch_assignments_select` grants org-wide visibility when `public.jwt_staff_role() IN ('owner', 'administrator')` (`20260528133000:20-31`) — reads JWT, not `staff_members.role`. `auth_internal.staff_can_access_branch` grants administrators org-wide branch access via `public.jwt_staff_role() = 'administrator'` (`20260611150000:820-839`). RPC `assert_permission` correctly reads live `staff_members.is_active` and `role` from DB (`20260613210000:12-37`). RLS `patients_select` filters only `organization_id = public.jwt_organization_id()` (`20260523140000:50-56`) — no caller `is_active` check. `build_staff_claims` returns `{}` for inactive staff on **new** token issue (`auth_security_extensions.sql:74-79`), but GoTrue does not revoke outstanding JWTs on deactivation. JWT lifetime: 3600s (`docker-compose.yml:39`). |
| **Why it is a problem** | Authorization is **split-brain**: RPC mutations use live DB state; RLS SELECT and branch helpers use JWT claims that can lag up to 1 hour after `set_staff_active(false)` or role demotion. |
| **Potential impact** | (1) Deactivated staff with unexpired JWT retain PostgREST read access to org patients, branches, appointments, audit entries, etc. (2) Demoted administrators retain org-wide branch visibility in RLS and storage policies until re-login. |
| **Recommended solution** | Add stable helper `auth_internal.current_staff_is_active()` / `current_staff_role()` reading live `staff_members` row; use in RLS policies and `staff_can_access_branch` instead of `jwt_staff_role()`. Optionally shorten JWT TTL or force session invalidation on deactivation/role change via GoTrue admin API. Add regression tests: deactivate staff → authenticated SELECT on `patients` must fail. |

---

## 3. What Was Checked (No New Critical/High)

| Area | Result |
|------|--------|
| Prior C-01, C-02, H-01–H-25 | Re-verified; not re-documented |
| H-21 (`create_staff_account` cross-org branches) | **Remediated** in `20260614100000_settings_code_review_fixes.sql:216-226 (`v_org_id := public.jwt_organization_id()` guard) — not a new finding |
| `auth_internal` schema PostgREST exposure | `PGRST_DB_SCHEMAS: public` only (`docker-compose.yml:55`) — direct REST calls to `auth_internal` not possible; grants matter for INVOKER chains |
| `staff_branch_assignments` INSERT/UPDATE | INSERT blocked (`WITH CHECK (false)`); no UPDATE policy → deny-by-default |
| `roles_permissions`, `app_settings` | No writable RLS policies; RPC-only |
| `assert_permission` / `assert_owner_or_administrator` | Read live `staff_members` — correct for RPC path |
| `get_custom_claims` hook | `supabase_auth_admin` only on jsonb overload; uuid overload removed; contract tested in `jwt_claims_contract.sql` |
| Appointment / visit / patient `auth_internal` grants | Present where checked (`list_appointments` 6-param grant at `20260627120000:483-485`, `update_appointment`, `delete_branch`, `delete_staff_member`, visit medical records block) |
| Billing / shifts / service-catalog grant gaps | Already H-09, H-10, C-02, H-22 — not duplicated |
| `assert_patient_branch_scope` / `assert_visit_branch_scope` direct grants | Follow H-24 pattern (second pass); not re-reported |
| `seed_organization_catalog_defaults` | Revoked from `authenticated` at `20260711120000:7` — not new |

---

## 4. Recommended Remediation (New Items Only)

| Priority | Action | Addresses |
|----------|--------|-----------|
| P0 | Re-grant `auth_internal.bootstrap_finish_setup` on 12-param signature | H-26 |
| P0 | Grant `auth_internal.admin_update_staff_username` to `authenticated` | H-27 |
| P1 | Replace `jwt_staff_role()` in RLS/branch helpers with live staff row lookups; add deactivation SELECT denial test | H-28 |

---

*End of third-pass review. 3 new High findings; 0 new Critical. Prior review items unchanged.*
