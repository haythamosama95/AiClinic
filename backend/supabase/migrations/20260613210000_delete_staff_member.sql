-- Soft-delete inactive staff members from settings management.

CREATE OR REPLACE FUNCTION auth_internal.assert_permission(p_permission_key text)
RETURNS public.staff_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = auth.uid()
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0003';
  END IF;

  IF v_staff.is_bootstrap_admin AND NOT auth_internal.organization_exists() THEN
    RETURN v_staff;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    WHERE rp.role = v_staff.role
      AND rp.permission_key = p_permission_key
      AND rp.is_granted = true
      AND rp.is_deleted = false
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0003';
  END IF;

  RETURN v_staff;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_not_last_administrator(p_staff_member_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_target_role public.staff_role;
  v_org_id uuid;
  v_other_administrators int;
BEGIN
  SELECT sm.role INTO v_target_role
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id AND sm.is_deleted = false;

  IF v_target_role IS DISTINCT FROM 'administrator' THEN
    RETURN;
  END IF;

  SELECT b.organization_id
  INTO v_org_id
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id AND b.is_deleted = false
  WHERE sba.staff_member_id = p_staff_member_id
    AND sba.is_deleted = false
  LIMIT 1;

  IF v_org_id IS NULL THEN
    RETURN;
  END IF;

  SELECT count(DISTINCT sm.id) INTO v_other_administrators
  FROM public.staff_members sm
  JOIN public.staff_branch_assignments sba
    ON sba.staff_member_id = sm.id AND sba.is_deleted = false
  JOIN public.branches b ON b.id = sba.branch_id AND b.is_deleted = false
  WHERE sm.role = 'administrator'
    AND sm.is_active = true
    AND sm.is_deleted = false
    AND sm.id != p_staff_member_id
    AND b.organization_id = v_org_id;

  IF v_other_administrators < 1 THEN
    RAISE EXCEPTION 'LAST_ADMINISTRATOR' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.delete_staff_member(p_staff_member_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_staff public.staff_members%ROWTYPE;
BEGIN
  BEGIN
    PERFORM auth_internal.assert_permission('settings.manage_staff');
  EXCEPTION
    WHEN SQLSTATE = 'P0003' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage staff.');
  END;

  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Organization context is required to manage staff.');
  END IF;

  IF p_staff_member_id = public.jwt_staff_member_id() THEN
    RETURN public.rpc_error('CANNOT_DELETE_SELF', 'You cannot delete your own account.');
  END IF;

  SELECT sm.*
  INTO v_staff
  FROM public.staff_members sm
  JOIN public.staff_branch_assignments sba ON sba.staff_member_id = sm.id AND sba.is_deleted = false
  JOIN public.branches b ON b.id = sba.branch_id AND b.is_deleted = false
  WHERE sm.id = p_staff_member_id
    AND sm.is_deleted = false
    AND b.organization_id = v_org_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found in your organization.');
  END IF;

  IF v_staff.is_active THEN
    BEGIN
      PERFORM auth_internal.assert_not_last_administrator(p_staff_member_id);
    EXCEPTION
      WHEN SQLSTATE = 'P0002' THEN
        RETURN public.rpc_error('LAST_ADMINISTRATOR', 'Cannot delete the last active administrator.');
    END;

    RETURN public.rpc_error('STAFF_STILL_ACTIVE', 'Deactivate the staff member before deleting them.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_not_last_administrator(p_staff_member_id);
  EXCEPTION
    WHEN SQLSTATE = 'P0002' THEN
      RETURN public.rpc_error('LAST_ADMINISTRATOR', 'Cannot delete the last active administrator.');
  END;

  UPDATE public.staff_branch_assignments sba
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sba.staff_member_id = p_staff_member_id
    AND sba.is_deleted = false;

  UPDATE public.staff_members sm
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sm.id = p_staff_member_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'staff.delete',
    'staff_members',
    p_staff_member_id,
    jsonb_build_object('full_name', v_staff.full_name, 'role', v_staff.role::text, 'is_active', v_staff.is_active)
  );

  RETURN public.rpc_success(jsonb_build_object('staff_member_id', p_staff_member_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_staff_member(p_staff_member_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.delete_staff_member(p_staff_member_id);
$$;

GRANT EXECUTE ON FUNCTION auth_internal.delete_staff_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_staff_member(uuid) TO authenticated;
