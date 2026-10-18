-- =============================================================================
-- R1-SQL-01 (P1): Any tenant member can modify staff authority directly.
--
-- The table-wide grant from 20260516100200_auth_rbac_rls.sql (GRANT SELECT,
-- INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated)
-- combined with the permissive staff_members_update policy
-- (20261002150000_tenant_scoping.sql) let any member UPDATE any non-deleted
-- staff row of their organisation — including role, is_active and
-- is_bootstrap_admin — with no caller permission predicate. That is
-- tenant-level privilege escalation (a doctor could PATCH their own role to
-- administrator).
--
-- This migration closes the direct UPDATE path:
--   1. revoke the table-level UPDATE grant on public.staff_members from
--      authenticated/PUBLIC/anon;
--   2. drop the permissive staff_members_update policy.
--
-- Profile/settings changes stay with the guarded SECURITY DEFINER RPCs
-- (auth_internal.update_staff_member, auth_internal.set_staff_active,
-- auth_internal.delete_staff_member), which the coordinator confirmed are the
-- only staff write callers in the frontend (StaffAdminRepositoryImpl uses
-- staff SELECTs plus these RPCs; no direct staff UPDATE caller). The definer
-- RPCs run as the migration owner and are unaffected by this revoke.
--
-- Ordering: this grant closure lands in its own migration BEFORE any
-- membership lifecycle synchronization (plan §4.1.1 note), so a direct role
-- edit can no longer promote membership.
-- Forward-only migration; never edit an applied migration file.
-- =============================================================================

REVOKE UPDATE ON public.staff_members FROM authenticated, anon, PUBLIC;

DROP POLICY IF EXISTS staff_members_update ON public.staff_members;