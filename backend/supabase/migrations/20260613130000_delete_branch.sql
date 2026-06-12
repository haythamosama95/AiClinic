-- Soft-delete inactive branches from settings management.

CREATE OR REPLACE FUNCTION auth_internal.delete_branch(p_branch_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_branch public.branches%ROWTYPE;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Organization context is required to manage branches.');
  END IF;

  SELECT b.*
  INTO v_branch
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.organization_id = v_org_id;

  IF NOT FOUND THEN
    RETURN public.rpc_error('BRANCH_NOT_FOUND', 'Branch was not found in your organization.');
  END IF;

  IF v_branch.is_deleted THEN
    RETURN public.rpc_error('BRANCH_ALREADY_DELETED', 'That branch has already been deleted.');
  END IF;

  IF v_branch.is_active THEN
    RETURN public.rpc_error('BRANCH_STILL_ACTIVE', 'Deactivate the branch before deleting it.');
  END IF;

  UPDATE public.staff_branch_assignments sba
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sba.branch_id = p_branch_id
    AND sba.is_deleted = false;

  UPDATE public.branches b
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE b.id = p_branch_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'branch.delete',
    'branches',
    p_branch_id,
    jsonb_build_object('name', v_branch.name, 'code', v_branch.code, 'is_active', v_branch.is_active)
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', p_branch_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage branches.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_branch(p_branch_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.delete_branch(p_branch_id);
$$;

GRANT EXECUTE ON FUNCTION auth_internal.delete_branch(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_branch(uuid) TO authenticated;
