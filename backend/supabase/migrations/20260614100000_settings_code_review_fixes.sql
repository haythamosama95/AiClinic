-- Code review fixes: permission gates, batch role updates, org-scoped branch validation, delete precedence.

-- Finding 2: gate staff_login_usernames behind settings.manage_staff.
CREATE OR REPLACE FUNCTION public.staff_login_usernames(p_staff_ids uuid[])
RETURNS TABLE (staff_member_id uuid, username text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  BEGIN
    PERFORM auth_internal.assert_permission('settings.manage_staff');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE = 'P0003' OR SQLERRM = 'FORBIDDEN' THEN
        RETURN;
      END IF;
      RAISE;
  END;

  RETURN QUERY
  SELECT sm.id, lower(trim(u.email::text))
  FROM public.staff_members sm
  JOIN auth.users u ON u.id = sm.auth_user_id
  WHERE sm.is_deleted = false
    AND sm.id = ANY (p_staff_ids)
    AND (
      sm.auth_user_id = (SELECT auth.uid())
      OR EXISTS (
        SELECT 1
        FROM public.staff_branch_assignments sba
        JOIN public.branches b ON b.id = sba.branch_id
        WHERE sba.staff_member_id = sm.id
          AND sba.is_deleted = false
          AND b.is_deleted = false
          AND b.organization_id = public.jwt_organization_id()
      )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.staff_login_usernames(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.staff_login_usernames(uuid[]) TO authenticated;

-- Finding 3: atomic batch role permission updates.
CREATE OR REPLACE FUNCTION auth_internal.update_role_permissions(p_changes jsonb)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_change jsonb;
  v_role public.staff_role;
  v_key text;
  v_is_granted boolean;
  v_old boolean;
  v_row public.roles_permissions%ROWTYPE;
  v_applied jsonb := '[]'::jsonb;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'array' OR jsonb_array_length(p_changes) = 0 THEN
    RETURN public.rpc_success(jsonb_build_object('applied', v_applied));
  END IF;

  FOR v_change IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
    v_role := (v_change ->> 'role')::public.staff_role;
    v_key := trim(v_change ->> 'permission_key');
    v_is_granted := (v_change ->> 'is_granted')::boolean;

    IF NULLIF(v_key, '') IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Permission key is required.');
    END IF;

    IF v_key = 'settings.billing.manage'
       AND v_is_granted = true
       AND v_role <> 'administrator' THEN
      RETURN public.rpc_error(
        'PERMISSION_NOT_DELEGABLE',
        'settings.billing.manage cannot be granted to this role.'
      );
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.permission_key = v_key
        AND rp.is_deleted = false
    ) THEN
      RETURN public.rpc_error('INVALID_PERMISSION', 'Permission key is not in the catalog.');
    END IF;

    SELECT rp.is_granted
    INTO v_old
    FROM public.roles_permissions rp
    WHERE rp.role = v_role
      AND rp.permission_key = v_key
      AND rp.is_deleted = false;

    IF NOT FOUND THEN
      v_old := false;
    END IF;

    INSERT INTO public.roles_permissions (role, permission_key, is_granted, updated_by)
    VALUES (v_role, v_key, v_is_granted, auth.uid())
    ON CONFLICT (role, permission_key) DO UPDATE
    SET
      is_granted = EXCLUDED.is_granted,
      is_deleted = false,
      deleted_at = NULL,
      deleted_by = NULL,
      updated_at = now(),
      updated_by = auth.uid()
    RETURNING * INTO v_row;

    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
    VALUES (
      auth.uid(),
      public.jwt_organization_id(),
      'role_permission.update',
      'roles_permissions',
      v_row.id,
      jsonb_build_object('role', v_role::text, 'permission_key', v_key, 'is_granted', v_old),
      jsonb_build_object('role', v_role::text, 'permission_key', v_key, 'is_granted', v_is_granted)
    );

    v_applied := v_applied || jsonb_build_array(
      jsonb_build_object('role', v_role::text, 'permission_key', v_key, 'is_granted', v_is_granted)
    );
  END LOOP;

  RETURN public.rpc_success(jsonb_build_object('applied', v_applied));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update role permissions.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_role_permissions(p_changes jsonb)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_role_permissions(p_changes);
$$;

GRANT EXECUTE ON FUNCTION auth_internal.update_role_permissions(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_role_permissions(jsonb) TO authenticated;

-- Finding 5: scope create_staff_account branch validation to caller organization.
CREATE OR REPLACE FUNCTION auth_internal.create_staff_account(
  p_username text,
  p_password text,
  p_full_name text,
  p_role public.staff_role,
  p_branch_ids uuid[],
  p_primary_branch_id uuid DEFAULT NULL,
  p_phone text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_auth_user_id uuid;
  v_staff_id uuid;
  v_branch_id uuid;
  v_primary uuid;
  v_username text;
  v_org_id uuid;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF NOT auth_internal.organization_exists() THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Create an organization and branch before provisioning staff.');
  END IF;

  v_org_id := public.jwt_organization_id();

  IF p_branch_ids IS NULL OR cardinality(p_branch_ids) = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'At least one branch assignment is required.');
  END IF;

  IF NULLIF(trim(p_username), '') IS NULL OR NULLIF(trim(p_password), '') IS NULL OR NULLIF(trim(p_full_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Username, password, and full name are required.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_password_complexity(p_password);
  EXCEPTION
    WHEN check_violation THEN
      RETURN public.rpc_error('WEAK_PASSWORD', SQLERRM);
  END;

  BEGIN
    PERFORM auth_internal.assert_valid_username(p_username);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'INVALID_USERNAME' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Enter a valid username (3-32 letters, numbers, underscore, or hyphen).');
      END IF;
      RAISE;
  END;

  v_username := auth_internal.normalize_username(p_username);

  IF EXISTS (
    SELECT 1
    FROM unnest(p_branch_ids) AS requested (branch_id)
    LEFT JOIN public.branches b
      ON b.id = requested.branch_id
      AND b.is_deleted = false
      AND (v_org_id IS NULL OR b.organization_id = v_org_id)
    WHERE b.id IS NULL
  ) THEN
    RETURN public.rpc_error('INVALID_BRANCH', 'One or more branch assignments are invalid for this organization.');
  END IF;

  v_primary := COALESCE(p_primary_branch_id, p_branch_ids[1]);
  IF NOT v_primary = ANY (p_branch_ids) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Primary branch must be included in branch assignments.');
  END IF;

  v_auth_user_id := auth_internal.create_auth_user(p_username, p_password);

  INSERT INTO public.staff_members (
    auth_user_id,
    full_name,
    role,
    phone,
    created_by,
    updated_by
  )
  VALUES (
    v_auth_user_id,
    trim(p_full_name),
    p_role,
    NULLIF(trim(p_phone), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_staff_id;

  FOREACH v_branch_id IN ARRAY p_branch_ids LOOP
    INSERT INTO public.staff_branch_assignments (
      staff_member_id,
      branch_id,
      is_primary,
      created_by,
      updated_by
    )
    VALUES (
      v_staff_id,
      v_branch_id,
      v_branch_id = v_primary,
      auth.uid(),
      auth.uid()
    );
  END LOOP;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    COALESCE(v_org_id, public.jwt_organization_id()),
    'staff.create',
    'staff_members',
    v_staff_id,
    jsonb_build_object('username', v_username, 'role', p_role::text)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'staff_member_id', v_staff_id,
      'username', v_username
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'USERNAME_EXISTS' THEN
      RETURN public.rpc_error('USERNAME_EXISTS', 'A staff account with this username already exists.');
    END IF;
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create staff accounts.');
    END IF;
    RAISE;
END;
$$;

-- Finding 6: return STAFF_STILL_ACTIVE before last-administrator check for active staff.
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
    WHEN OTHERS THEN
      IF SQLSTATE = 'P0003' OR SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage staff.');
      END IF;
      RAISE;
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
    RETURN public.rpc_error('STAFF_STILL_ACTIVE', 'Deactivate the staff member before deleting them.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_not_last_administrator(p_staff_member_id);
  EXCEPTION
    WHEN SQLSTATE 'P0002' THEN
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
