-- Fix 28: Fix update_branch so omitted optional fields (address, phone, maps_url)
-- are preserved rather than set to NULL.

CREATE OR REPLACE FUNCTION auth_internal.update_branch(
  p_branch_id uuid,
  p_name text,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_old public.branches%ROWTYPE;
  v_new public.branches%ROWTYPE;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch name is required.');
  END IF;

  SELECT *
  INTO v_old
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.organization_id = v_org_id
    AND b.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('BRANCH_NOT_FOUND', 'Branch was not found in your organization.');
  END IF;

  UPDATE public.branches b
  SET
    name = trim(p_name),
    code = NULLIF(trim(p_code), ''),
    address = COALESCE(NULLIF(trim(p_address), ''), b.address),
    phone = COALESCE(NULLIF(trim(p_phone), ''), b.phone),
    maps_url = COALESCE(NULLIF(trim(p_maps_url), ''), b.maps_url),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE b.id = p_branch_id
  RETURNING * INTO v_new;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'branch.update',
    'branches',
    p_branch_id,
    jsonb_build_object('name', v_old.name, 'code', v_old.code, 'address', v_old.address, 'phone', v_old.phone, 'maps_url', v_old.maps_url),
    jsonb_build_object('name', v_new.name, 'code', v_new.code, 'address', v_new.address, 'phone', v_new.phone, 'maps_url', v_new.maps_url)
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', p_branch_id));
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('DUPLICATE_CODE', 'A branch with this code already exists in your organization.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage branches.');
    END IF;
    RAISE;
END;
$$;
