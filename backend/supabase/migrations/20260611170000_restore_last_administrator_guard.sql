-- Restore last-administrator guard (successor to assert_not_last_owner after owner role removal).

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
    RAISE EXCEPTION 'LAST_ADMINISTRATOR';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.update_staff_member(
  p_staff_member_id uuid,
  p_full_name text,
  p_role public.staff_role,
  p_branch_ids uuid[],
  p_phone text DEFAULT NULL,
  p_primary_branch_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_target public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_branch_id uuid;
  v_primary uuid;
  v_old_role public.staff_role;
BEGIN
  v_caller := auth_internal.assert_permission('settings.manage_staff');
  v_org_id := public.jwt_organization_id();

  IF NULLIF(trim(p_full_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Full name is required.');
  END IF;

  IF p_branch_ids IS NULL OR cardinality(p_branch_ids) = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'At least one branch assignment is required.');
  END IF;

  SELECT sm.*
  INTO v_target
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id
    AND sm.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found.');
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1
      FROM public.staff_branch_assignments sba
      JOIN public.branches b ON b.id = sba.branch_id
      WHERE sba.staff_member_id = v_target.id
        AND sba.is_deleted = false
        AND b.is_deleted = false
        AND b.organization_id = v_org_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM unnest(p_branch_ids) AS requested (branch_id)
      JOIN public.branches b ON b.id = requested.branch_id
      WHERE b.organization_id != v_org_id
        OR b.is_deleted = true
        OR b.id IS NULL
    )
  ) THEN
    RETURN public.rpc_error('CROSS_ORG_DENIED', 'Staff member is outside your organization scope.');
  END IF;

  v_old_role := v_target.role;

  IF v_old_role = 'administrator' AND p_role != 'administrator' THEN
    BEGIN
      PERFORM auth_internal.assert_not_last_administrator(p_staff_member_id);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM = 'LAST_ADMINISTRATOR' THEN
          RETURN public.rpc_error('LAST_ADMINISTRATOR', 'Cannot demote the last active administrator.');
        END IF;
        RAISE;
    END;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(p_branch_ids) AS requested (branch_id)
    LEFT JOIN public.branches b
      ON b.id = requested.branch_id
      AND b.is_deleted = false
      AND b.is_active = true
      AND b.organization_id = v_org_id
    WHERE b.id IS NULL
  ) THEN
    RETURN public.rpc_error('INVALID_BRANCH', 'At least one active branch assignment is required.');
  END IF;

  v_primary := COALESCE(p_primary_branch_id, p_branch_ids[1]);
  IF NOT v_primary = ANY (p_branch_ids) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Primary branch must be included in branch assignments.');
  END IF;

  UPDATE public.staff_members sm
  SET
    full_name = trim(p_full_name),
    role = p_role,
    phone = NULLIF(trim(p_phone), ''),
    is_active = COALESCE(p_is_active, sm.is_active),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sm.id = p_staff_member_id;

  UPDATE public.staff_branch_assignments sba
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE sba.staff_member_id = p_staff_member_id
    AND sba.is_deleted = false
    AND sba.branch_id <> ALL (p_branch_ids);

  FOREACH v_branch_id IN ARRAY p_branch_ids LOOP
    INSERT INTO public.staff_branch_assignments (
      staff_member_id,
      branch_id,
      is_primary,
      is_deleted,
      created_by,
      updated_by
    )
    VALUES (
      p_staff_member_id,
      v_branch_id,
      v_branch_id = v_primary,
      false,
      auth.uid(),
      auth.uid()
    )
    ON CONFLICT (staff_member_id, branch_id) DO UPDATE
    SET
      is_primary = EXCLUDED.is_primary,
      is_deleted = false,
      deleted_at = NULL,
      deleted_by = NULL,
      updated_at = now(),
      updated_by = auth.uid();
  END LOOP;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'staff.update',
    'staff_members',
    p_staff_member_id,
    jsonb_build_object('role', p_role::text)
  );

  RETURN public.rpc_success(jsonb_build_object('staff_member_id', p_staff_member_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update staff members.');
    END IF;
    RAISE;
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
      PERFORM auth_internal.assert_not_last_administrator(p_staff_member_id);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM = 'LAST_ADMINISTRATOR' THEN
          RETURN public.rpc_error('LAST_ADMINISTRATOR', 'Cannot deactivate the last active administrator.');
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
