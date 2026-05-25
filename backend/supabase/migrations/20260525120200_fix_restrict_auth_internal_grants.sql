-- Fix 2: Restrict auth_internal grants to specific functions called by public INVOKER wrappers.
-- Revokes the blanket GRANT EXECUTE ON ALL FUNCTIONS and grants only needed functions.

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA auth_internal FROM authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA auth_internal
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated;

-- Grant EXECUTE only on functions that public SECURITY INVOKER wrappers call directly.
-- Each public wrapper runs as the caller (authenticated), so it needs EXECUTE on the
-- auth_internal function it delegates to.

GRANT EXECUTE ON FUNCTION auth_internal.build_staff_claims(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.bootstrap_create_organization(text, jsonb, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.bootstrap_create_branch(uuid, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_staff_account(text, text, text, public.staff_role, uuid[], uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.admin_reset_staff_password(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_organization(text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.manage_create_branch(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_branch(uuid, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.set_branch_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_staff_member(uuid, text, public.staff_role, uuid[], text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.set_staff_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_role_permission(public.staff_role, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.search_patients(text, text, uuid, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.get_patient(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.check_patient_duplicates(text, text, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.create_patient(uuid, text, text, date, text, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_patient(uuid, text, timestamptz, text, date, text, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.archive_patient(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.dev_reset_clinic_installation() TO authenticated;

-- service_role still needs full access for internal call chains and GoTrue hooks.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth_internal TO service_role;

-- supabase_auth_admin for GoTrue custom claims hook
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth_internal TO supabase_auth_admin;
  END IF;
END;
$$;
