-- =============================================================================
-- V1-2: Organization and branch management (steady-state RPCs + branch code index)
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS branches_organization_code_unique
  ON public.branches (organization_id, lower(trim(code)))
  WHERE code IS NOT NULL
    AND trim(code) <> ''
    AND is_deleted = false;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_permission
-- -----------------------------------------------------------------------------

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
    RAISE EXCEPTION 'FORBIDDEN';
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
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN v_staff;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.update_organization
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_organization(
  p_name text,
  p_logo_url text DEFAULT NULL,
  p_currency_code text DEFAULT NULL,
  p_timezone text DEFAULT NULL,
  p_settings_json jsonb DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_old public.organizations%ROWTYPE;
  v_new public.organizations%ROWTYPE;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('ORG_NOT_FOUND', 'Organization was not found for this session.');
  END IF;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Organization name is required.');
  END IF;

  IF p_currency_code IS NOT NULL AND NULLIF(trim(p_currency_code), '') IS NOT NULL THEN
    IF trim(p_currency_code) !~ '^[A-Z]{3}$' THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Currency code must be a valid ISO 4217 code (three uppercase letters).');
    END IF;
  END IF;

  IF p_timezone IS NOT NULL AND NULLIF(trim(p_timezone), '') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_timezone_names tz
      WHERE tz.name = trim(p_timezone)
    ) THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Timezone must be a valid IANA identifier.');
    END IF;
  END IF;

  SELECT *
  INTO v_old
  FROM public.organizations o
  WHERE o.id = v_org_id
    AND o.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('ORG_NOT_FOUND', 'Organization was not found.');
  END IF;

  UPDATE public.organizations o
  SET
    name = trim(p_name),
    logo_url = COALESCE(NULLIF(trim(p_logo_url), ''), o.logo_url),
    currency_code = COALESCE(NULLIF(trim(p_currency_code), ''), o.currency_code),
    timezone = COALESCE(NULLIF(trim(p_timezone), ''), o.timezone),
    settings_json = COALESCE(p_settings_json, o.settings_json),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE o.id = v_org_id
  RETURNING * INTO v_new;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'organization.update',
    'organizations',
    v_org_id,
    jsonb_build_object(
      'name', v_old.name,
      'logo_url', v_old.logo_url,
      'currency_code', v_old.currency_code,
      'timezone', v_old.timezone,
      'settings_json', v_old.settings_json
    ),
    jsonb_build_object(
      'name', v_new.name,
      'logo_url', v_new.logo_url,
      'currency_code', v_new.currency_code,
      'timezone', v_new.timezone,
      'settings_json', v_new.settings_json
    )
  );

  RETURN public.rpc_success(jsonb_build_object('organization_id', v_org_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update organization settings.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.manage_create_branch
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.manage_create_branch(
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
  v_branch_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL OR public.jwt_setup_required() THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Complete clinic setup before creating branches.');
  END IF;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch name is required.');
  END IF;

  INSERT INTO public.branches (
    organization_id,
    name,
    code,
    address,
    phone,
    maps_url,
    created_by,
    updated_by
  )
  VALUES (
    v_org_id,
    trim(p_name),
    NULLIF(trim(p_code), ''),
    NULLIF(trim(p_address), ''),
    NULLIF(trim(p_phone), ''),
    NULLIF(trim(p_maps_url), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_branch_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'branch.create',
    'branches',
    v_branch_id,
    jsonb_build_object(
      'organization_id', v_org_id,
      'name', trim(p_name),
      'code', NULLIF(trim(p_code), '')
    )
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', v_branch_id));
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

-- -----------------------------------------------------------------------------
-- auth_internal.update_branch
-- -----------------------------------------------------------------------------

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
    address = NULLIF(trim(p_address), ''),
    phone = NULLIF(trim(p_phone), ''),
    maps_url = NULLIF(trim(p_maps_url), ''),
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
    jsonb_build_object('name', v_old.name, 'code', v_old.code),
    jsonb_build_object('name', v_new.name, 'code', v_new.code)
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

-- -----------------------------------------------------------------------------
-- auth_internal.set_branch_active
-- -----------------------------------------------------------------------------

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

  IF v_org_id IS NULL THEN
    SELECT b.organization_id
    INTO v_org_id
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.is_deleted = false;
  END IF;

  IF v_org_id IS NULL OR NOT EXISTS (
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

-- -----------------------------------------------------------------------------
-- auth_internal.update_staff_member
-- -----------------------------------------------------------------------------

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
SET search_path = public, auth
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

  IF p_role = 'owner' AND v_old_role <> 'owner' THEN
    IF auth_internal.owner_exists() AND v_caller.role <> 'owner' THEN
      RETURN public.rpc_error(
        'FORBIDDEN_OWNER_CREATE',
        'Only existing owners may assign the owner role.'
      );
    END IF;
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
    jsonb_build_object('role', p_role::text, 'full_name', trim(p_full_name))
  );

  RETURN public.rpc_success(jsonb_build_object('staff_member_id', p_staff_member_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage staff.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.set_staff_active
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- auth_internal.update_role_permission
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_role_permission(
  p_role public.staff_role,
  p_permission_key text,
  p_is_granted boolean
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_old boolean;
  v_row public.roles_permissions%ROWTYPE;
BEGIN
  SELECT *
  INTO v_caller
  FROM public.staff_members sm
  WHERE sm.auth_user_id = auth.uid()
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND OR v_caller.role <> 'owner' THEN
    RETURN public.rpc_error('FORBIDDEN', 'Only owners may update the permission matrix.');
  END IF;

  IF NULLIF(trim(p_permission_key), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Permission key is required.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    WHERE rp.permission_key = trim(p_permission_key)
      AND rp.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_PERMISSION', 'Permission key is not in the catalog.');
  END IF;

  SELECT rp.is_granted
  INTO v_old
  FROM public.roles_permissions rp
  WHERE rp.role = p_role
    AND rp.permission_key = trim(p_permission_key)
    AND rp.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('PERMISSION_NOT_FOUND', 'Permission row was not found for this role.');
  END IF;

  UPDATE public.roles_permissions rp
  SET
    is_granted = p_is_granted,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE rp.role = p_role
    AND rp.permission_key = trim(p_permission_key)
    AND rp.is_deleted = false
  RETURNING * INTO v_row;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'role_permission.update',
    'roles_permissions',
    v_row.id,
    jsonb_build_object('role', p_role::text, 'permission_key', trim(p_permission_key), 'is_granted', v_old),
    jsonb_build_object('role', p_role::text, 'permission_key', trim(p_permission_key), 'is_granted', p_is_granted)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'role', p_role::text,
      'permission_key', trim(p_permission_key),
      'is_granted', p_is_granted
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- roles_permissions SELECT: owners/administrators see denied grants for matrix UI
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS roles_permissions_select ON public.roles_permissions;

CREATE POLICY roles_permissions_select ON public.roles_permissions
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      is_granted = true
      OR EXISTS (
        SELECT 1
        FROM public.current_staff_member_row() sm
        WHERE sm.role IN ('owner', 'administrator')
      )
    )
  );

-- -----------------------------------------------------------------------------
-- public RPC wrappers (SECURITY INVOKER)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_organization(
  p_name text,
  p_logo_url text DEFAULT NULL,
  p_currency_code text DEFAULT NULL,
  p_timezone text DEFAULT NULL,
  p_settings_json jsonb DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_organization(
    p_name,
    p_logo_url,
    p_currency_code,
    p_timezone,
    p_settings_json
  );
$$;

CREATE OR REPLACE FUNCTION public.manage_create_branch(
  p_name text,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.manage_create_branch(p_name, p_code, p_address, p_phone, p_maps_url);
$$;

CREATE OR REPLACE FUNCTION public.update_branch(
  p_branch_id uuid,
  p_name text,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_branch(p_branch_id, p_name, p_code, p_address, p_phone, p_maps_url);
$$;

CREATE OR REPLACE FUNCTION public.set_branch_active(p_branch_id uuid, p_is_active boolean)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_branch_active(p_branch_id, p_is_active);
$$;

CREATE OR REPLACE FUNCTION public.update_staff_member(
  p_staff_member_id uuid,
  p_full_name text,
  p_role public.staff_role,
  p_branch_ids uuid[],
  p_phone text DEFAULT NULL,
  p_primary_branch_id uuid DEFAULT NULL,
  p_is_active boolean DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_staff_member(
    p_staff_member_id,
    p_full_name,
    p_role,
    p_branch_ids,
    p_phone,
    p_primary_branch_id,
    p_is_active
  );
$$;

CREATE OR REPLACE FUNCTION public.set_staff_active(p_staff_member_id uuid, p_is_active boolean)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_staff_active(p_staff_member_id, p_is_active);
$$;

CREATE OR REPLACE FUNCTION public.update_role_permission(
  p_role public.staff_role,
  p_permission_key text,
  p_is_granted boolean
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_role_permission(p_role, p_permission_key, p_is_granted);
$$;

GRANT EXECUTE ON FUNCTION public.update_organization(text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.manage_create_branch(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_branch(uuid, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_branch_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_staff_member(uuid, text, public.staff_role, uuid[], text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_staff_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_role_permission(public.staff_role, text, boolean) TO authenticated;
