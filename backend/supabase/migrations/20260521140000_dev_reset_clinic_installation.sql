-- Development-only: wipe organization, branches, and related tenant rows so bootstrap can be re-run.
-- Callable only by the bootstrap administrator. Intended for local debugging, not production clinics.

CREATE OR REPLACE FUNCTION auth_internal.dev_reset_clinic_installation()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_orgs_deleted int;
  v_branches_deleted int;
  v_had_org boolean;
BEGIN
  v_staff := auth_internal.assert_bootstrap_admin();
  v_had_org := auth_internal.organization_exists();

  -- PostgREST / supautils require a WHERE clause on DELETE when invoked via the API.
  DELETE FROM public.staff_branch_assignments WHERE true;
  DELETE FROM public.audit_log WHERE organization_id IS NOT NULL;
  DELETE FROM public.app_settings WHERE true;
  DELETE FROM public.subscription_cache WHERE true;
  DELETE FROM public.branches WHERE true;
  GET DIAGNOSTICS v_branches_deleted = ROW_COUNT;

  DELETE FROM public.organizations WHERE true;
  GET DIAGNOSTICS v_orgs_deleted = ROW_COUNT;

  IF v_had_org AND auth_internal.organization_exists() THEN
    RETURN public.rpc_error(
      'RESET_INCOMPLETE',
      'Organization data could not be removed. Check database permissions and migrations.'
    );
  END IF;

  INSERT INTO public.audit_log (user_id, action, table_name, new_data_json)
  VALUES (
    auth.uid(),
    'organization.dev_reset',
    'organizations',
    jsonb_build_object(
      'organizations_deleted', v_orgs_deleted,
      'branches_deleted', v_branches_deleted,
      'bootstrap_staff_member_id', v_staff.id,
      'had_organization_before_reset', v_had_org
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'organizations_deleted', v_orgs_deleted,
      'branches_deleted', v_branches_deleted,
      'had_organization_before_reset', v_had_org
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'NOT_BOOTSTRAP_ADMIN' THEN
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may reset clinic installation data.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_reset_clinic_installation()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
BEGIN
  RETURN auth_internal.dev_reset_clinic_installation();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.dev_reset_clinic_installation() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_reset_clinic_installation() TO authenticated;
