-- =============================================================================
-- MIGRATION 6: Supabase Security & Performance Advisor fixes (spec002)
-- =============================================================================
-- Resolves linter findings from docs/implementation/spec002/supabase-warnings.md:
--   • function_search_path_mutable (0011)
--   • pg_graphql_* table exposure (0026/0027) — anon SELECT + unused GraphQL API
--   • anon/authenticated SECURITY DEFINER RPC exposure (0028/0029)
--   • auth_rls_initplan (0003)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Immutable search_path on helper / trigger functions (lint 0011)
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.request_jwt_claims() SET search_path = public, auth;
ALTER FUNCTION public.jwt_organization_id() SET search_path = public;
ALTER FUNCTION public.jwt_branch_ids() SET search_path = public;
ALTER FUNCTION public.jwt_staff_member_id() SET search_path = public;
ALTER FUNCTION public.jwt_staff_role() SET search_path = public;
ALTER FUNCTION public.jwt_setup_required() SET search_path = public;
ALTER FUNCTION public.rpc_success(jsonb) SET search_path = public;
ALTER FUNCTION public.rpc_error(text, text) SET search_path = public;
ALTER FUNCTION public.set_updated_at() SET search_path = public;
ALTER FUNCTION public.set_audit_user() SET search_path = public;
ALTER FUNCTION public.apply_standard_audit_triggers(regclass) SET search_path = public;

-- -----------------------------------------------------------------------------
-- 2) Anon must not read tenant tables (lint 0026; RLS does not apply to anon here)
-- -----------------------------------------------------------------------------
REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM anon;

-- AiClinic uses PostgREST REST + RPC only (Flutter SDK), not pg_graphql.
DROP EXTENSION IF EXISTS pg_graphql;

-- -----------------------------------------------------------------------------
-- 3) Restrict SECURITY DEFINER function EXECUTE (lint 0028 / 0029)
-- -----------------------------------------------------------------------------
-- Revoke broad defaults (Postgres grants EXECUTE to PUBLIC on new functions).
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;

-- Internal helpers: not callable via /rest/v1/rpc (still invoked by other DEFINER RPCs).
REVOKE EXECUTE ON FUNCTION public.assert_bootstrap_admin() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.assert_owner_or_administrator() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.build_staff_claims(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_auth_user(text, text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.organization_exists() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.owner_exists() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_audit_user() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_custom_claims(uuid) FROM anon, authenticated;

-- Used inside RLS policies; authenticated needs EXECUTE, anon must not call via RPC.
REVOKE EXECUTE ON FUNCTION public.current_staff_member_row() FROM anon;

-- Intentional staff RPCs: authenticated only (authorization enforced inside each function).
REVOKE EXECUTE ON FUNCTION public.bootstrap_create_organization(text, jsonb, text, text, text)
  FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.bootstrap_create_branch(uuid, text, text, text, text, text)
  FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_staff_account(text, text, text, public.staff_role, uuid[], uuid)
  FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_reset_staff_password(uuid, text) FROM anon, PUBLIC;

GRANT EXECUTE ON FUNCTION public.bootstrap_create_organization(text, jsonb, text, text, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.bootstrap_create_branch(uuid, text, text, text, text, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_staff_account(text, text, text, public.staff_role, uuid[], uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reset_staff_password(uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.current_staff_member_row() TO authenticated;

GRANT EXECUTE ON FUNCTION public.request_jwt_claims() TO authenticated;
GRANT EXECUTE ON FUNCTION public.jwt_organization_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.jwt_branch_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.jwt_staff_member_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.jwt_staff_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.jwt_setup_required() TO authenticated;

-- Preserve auth-hook and service paths from migration 4.
GRANT EXECUTE ON FUNCTION public.get_custom_claims(uuid) TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    REVOKE EXECUTE ON FUNCTION public.get_custom_claims(jsonb) FROM anon, authenticated, PUBLIC;
    GRANT EXECUTE ON FUNCTION public.get_custom_claims(jsonb) TO supabase_auth_admin;
  END IF;
END;
$$;

-- New functions in public should not auto-grant EXECUTE to API roles.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4) RLS: evaluate auth.uid() once per query, not per row (lint 0003)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS staff_members_select ON public.staff_members;
CREATE POLICY staff_members_select ON public.staff_members
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      auth_user_id = (SELECT auth.uid())
      OR EXISTS (
        SELECT 1
        FROM public.staff_branch_assignments sba
        JOIN public.branches b ON b.id = sba.branch_id
        WHERE sba.staff_member_id = staff_members.id
          AND sba.is_deleted = false
          AND b.is_deleted = false
          AND b.organization_id = public.jwt_organization_id()
      )
    )
  );

DROP POLICY IF EXISTS staff_members_update ON public.staff_members;
CREATE POLICY staff_members_update ON public.staff_members
  FOR UPDATE
  TO authenticated
  USING (
    is_deleted = false
    AND (
      auth_user_id = (SELECT auth.uid())
      OR EXISTS (
        SELECT 1
        FROM public.staff_branch_assignments sba
        JOIN public.branches b ON b.id = sba.branch_id
        WHERE sba.staff_member_id = staff_members.id
          AND sba.is_deleted = false
          AND b.organization_id = public.jwt_organization_id()
      )
    )
  )
  WITH CHECK (is_deleted = false);

DROP POLICY IF EXISTS audit_log_select ON public.audit_log;
CREATE POLICY audit_log_select ON public.audit_log
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR (
      organization_id IS NOT NULL
      AND organization_id = public.jwt_organization_id()
    )
  );
