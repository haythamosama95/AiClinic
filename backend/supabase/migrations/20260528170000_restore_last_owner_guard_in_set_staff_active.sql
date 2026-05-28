-- Restore last-owner guard in set_staff_active (regressed in 20260525121200).
-- Keeps CANNOT_DEACTIVATE_SELF from that migration.

CREATE OR REPLACE FUNCTION auth_internal.assert_not_last_owner(p_staff_member_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_target_role public.staff_role;
  v_org_id uuid;
  v_other_owners int;
BEGIN
  SELECT sm.role INTO v_target_role
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id AND sm.is_deleted = false;

  IF v_target_role IS DISTINCT FROM 'owner' THEN
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

  SELECT count(DISTINCT sm.id) INTO v_other_owners
  FROM public.staff_members sm
  JOIN public.staff_branch_assignments sba
    ON sba.staff_member_id = sm.id AND sba.is_deleted = false
  JOIN public.branches b ON b.id = sba.branch_id AND b.is_deleted = false
  WHERE sm.role = 'owner'
    AND sm.is_active = true
    AND sm.is_deleted = false
    AND sm.id != p_staff_member_id
    AND b.organization_id = v_org_id;

  IF v_other_owners < 1 THEN
    RAISE EXCEPTION 'LAST_OWNER';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.set_staff_active(p_staff_member_id uuid, p_is_active boolean)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_action text;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_staff');
  v_org_id := public.jwt_organization_id();

  IF NOT p_is_active AND p_staff_member_id = public.jwt_staff_member_id() THEN
    RETURN public.rpc_error('CANNOT_DEACTIVATE_SELF', 'You cannot deactivate your own account.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.staff_members sm
    JOIN public.staff_branch_assignments sba ON sba.staff_member_id = sm.id AND sba.is_deleted = false
    JOIN public.branches b ON b.id = sba.branch_id AND b.is_deleted = false
    WHERE sm.id = p_staff_member_id
      AND sm.is_deleted = false
      AND b.organization_id = v_org_id
  ) THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found in your organization.');
  END IF;

  IF NOT p_is_active THEN
    BEGIN
      PERFORM auth_internal.assert_not_last_owner(p_staff_member_id);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM = 'LAST_OWNER' THEN
          RETURN public.rpc_error('LAST_OWNER', 'Cannot deactivate the last active owner.');
        END IF;
        RAISE;
    END;
  END IF;

  UPDATE public.staff_members sm
  SET
    is_active = p_is_active,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sm.id = p_staff_member_id;

  v_action := CASE WHEN p_is_active THEN 'staff.reactivate' ELSE 'staff.deactivate' END;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    v_action,
    'staff_members',
    p_staff_member_id,
    jsonb_build_object('is_active', p_is_active)
  );

  RETURN public.rpc_success(jsonb_build_object('staff_member_id', p_staff_member_id, 'is_active', p_is_active));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage staff.');
    END IF;
    RAISE;
END;
$$;
