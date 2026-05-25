-- Fix 30: Fix set_branch_active org fallback bypass.
-- Remove the fallback that reads org from the branch itself when JWT org is NULL.

CREATE OR REPLACE FUNCTION auth_internal.set_branch_active(p_branch_id uuid, p_is_active boolean)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_active_count int;
  v_action text;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  -- Fail fast if organization context is missing (no unsafe fallback)
  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Organization context is required to manage branches.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_FOUND', 'Branch was not found in your organization.');
  END IF;

  IF NOT p_is_active THEN
    SELECT count(*)::int
    INTO v_active_count
    FROM public.branches b
    WHERE b.organization_id = v_org_id
      AND b.is_deleted = false
      AND b.is_active = true;

    IF v_active_count <= 1 THEN
      RETURN public.rpc_error(
        'LAST_ACTIVE_BRANCH',
        'Cannot deactivate the last active branch. Edit the branch or create another branch first.'
      );
    END IF;
  END IF;

  UPDATE public.branches b
  SET
    is_active = p_is_active,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE b.id = p_branch_id;

  v_action := CASE WHEN p_is_active THEN 'branch.reactivate' ELSE 'branch.deactivate' END;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    v_action,
    'branches',
    p_branch_id,
    jsonb_build_object('is_active', p_is_active)
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', p_branch_id, 'is_active', p_is_active));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage branches.');
    END IF;
    RAISE;
END;
$$;
