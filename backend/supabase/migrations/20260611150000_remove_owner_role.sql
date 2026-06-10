-- Remove the owner staff role; existing owner accounts become administrators.
-- Administrator (and bootstrap admin) now holds all former owner privileges.

-- -----------------------------------------------------------------------------
-- Data migration
-- -----------------------------------------------------------------------------

UPDATE public.staff_members
SET role = 'administrator'
WHERE role = 'owner';

DELETE FROM public.roles_permissions
WHERE role = 'owner';

-- Policies and functions must be dropped/recreated before changing enum-backed columns.
DROP POLICY IF EXISTS roles_permissions_select ON public.roles_permissions;
DROP POLICY IF EXISTS staff_branch_assignments_select ON public.staff_branch_assignments;

-- -----------------------------------------------------------------------------
-- Enum: drop owner value
-- -----------------------------------------------------------------------------

ALTER TYPE public.staff_role RENAME TO staff_role_old;

CREATE TYPE public.staff_role AS ENUM (
  'administrator',
  'doctor',
  'receptionist',
  'lab_staff'
);

ALTER TABLE public.staff_members
  ALTER COLUMN role TYPE public.staff_role
  USING role::text::public.staff_role;

ALTER TABLE public.roles_permissions
  ALTER COLUMN role TYPE public.staff_role
  USING role::text::public.staff_role;

DROP TYPE public.staff_role_old CASCADE;

CREATE OR REPLACE FUNCTION public.jwt_staff_role()
RETURNS public.staff_role
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    NULLIF(public.request_jwt_claims() ->> 'staff_role', ''),
    NULLIF(public.request_jwt_claims() ->> 'role', '')
  )::public.staff_role;
$$;

-- -----------------------------------------------------------------------------
-- Internal helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_owner_or_administrator()
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

  IF v_staff.role <> 'administrator' AND NOT v_staff.is_bootstrap_admin THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN v_staff;
END;
$$;

DROP FUNCTION IF EXISTS auth_internal.owner_exists();
DROP FUNCTION IF EXISTS auth_internal.assert_not_last_owner(uuid);

-- -----------------------------------------------------------------------------
-- Staff provisioning (no owner role)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_staff_account(
  p_username text,
  p_password text,
  p_full_name text,
  p_role public.staff_role,
  p_branch_ids uuid[],
  p_primary_branch_id uuid DEFAULT NULL
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
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF NOT auth_internal.organization_exists() THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Create an organization and branch before provisioning staff.');
  END IF;

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
      AND b.organization_id IN (
        SELECT o.id
        FROM public.organizations o
        WHERE o.is_deleted = false
      )
    WHERE b.id IS NULL
  ) THEN
    RETURN public.rpc_error('INVALID_BRANCH', 'One or more branch assignments are invalid for this installation.');
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
    created_by,
    updated_by
  )
  VALUES (
    v_auth_user_id,
    trim(p_full_name),
    p_role,
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
    public.jwt_organization_id(),
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

CREATE OR REPLACE FUNCTION auth_internal.bootstrap_finish_setup(
  p_org_name text,
  p_branch_name text,
  p_staff_accounts jsonb,
  p_settings_json jsonb DEFAULT '{}'::jsonb,
  p_logo_url text DEFAULT NULL,
  p_currency_code text DEFAULT NULL,
  p_timezone text DEFAULT NULL,
  p_branch_code text DEFAULT NULL,
  p_branch_address text DEFAULT NULL,
  p_branch_phone text DEFAULT NULL,
  p_branch_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_branch_id uuid;
  v_staff_entry jsonb;
  v_staff_member_id uuid;
  v_auth_user_id uuid;
  v_username text;
  v_role public.staff_role;
  v_staff_ids uuid[] := ARRAY[]::uuid[];
  v_usernames text[] := ARRAY[]::text[];
  v_admin_count int := 0;
BEGIN
  v_staff := auth_internal.assert_bootstrap_admin();

  IF auth_internal.organization_exists() THEN
    RETURN public.rpc_error('ORG_ALREADY_EXISTS', 'An organization already exists for this installation.');
  END IF;

  IF NULLIF(trim(p_org_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Organization name is required.');
  END IF;

  IF NULLIF(trim(p_branch_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch name is required.');
  END IF;

  IF p_staff_accounts IS NULL OR jsonb_typeof(p_staff_accounts) <> 'array' OR jsonb_array_length(p_staff_accounts) = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'At least one staff account is required.');
  END IF;

  FOR v_staff_entry IN SELECT value FROM jsonb_array_elements(p_staff_accounts)
  LOOP
    IF NULLIF(trim(v_staff_entry ->> 'username'), '') IS NULL
      OR NULLIF(trim(v_staff_entry ->> 'password'), '') IS NULL
      OR NULLIF(trim(v_staff_entry ->> 'full_name'), '') IS NULL
      OR NULLIF(trim(v_staff_entry ->> 'role'), '') IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Each staff account requires username, password, full name, and role.');
    END IF;

    BEGIN
      PERFORM auth_internal.assert_valid_username(v_staff_entry ->> 'username');
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM = 'INVALID_USERNAME' THEN
          RETURN public.rpc_error('INVALID_INPUT', 'Enter a valid username (3-32 letters, numbers, underscore, or hyphen).');
        END IF;
        RAISE;
    END;

    BEGIN
      PERFORM auth_internal.assert_password_complexity(v_staff_entry ->> 'password');
    EXCEPTION
      WHEN check_violation THEN
        RETURN public.rpc_error('WEAK_PASSWORD', SQLERRM);
    END;

    v_username := auth_internal.normalize_username(v_staff_entry ->> 'username');
    IF v_username = ANY (v_usernames) THEN
      RETURN public.rpc_error('USERNAME_EXISTS', 'A staff account with this username already exists.');
    END IF;
    v_usernames := array_append(v_usernames, v_username);

    BEGIN
      v_role := (v_staff_entry ->> 'role')::public.staff_role;
    EXCEPTION
      WHEN OTHERS THEN
        RETURN public.rpc_error('INVALID_INPUT', 'One or more staff roles are invalid.');
    END;

    IF v_role = 'administrator' THEN
      v_admin_count := v_admin_count + 1;
    END IF;
  END LOOP;

  IF v_admin_count = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'At least one administrator account is required to finish setup.');
  END IF;

  INSERT INTO public.organizations (
    name,
    logo_url,
    currency_code,
    timezone,
    settings_json,
    created_by,
    updated_by
  )
  VALUES (
    trim(p_org_name),
    NULLIF(trim(p_logo_url), ''),
    NULLIF(trim(p_currency_code), ''),
    NULLIF(trim(p_timezone), ''),
    COALESCE(p_settings_json, '{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_org_id;

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
    trim(p_branch_name),
    NULLIF(trim(p_branch_code), ''),
    NULLIF(trim(p_branch_address), ''),
    NULLIF(trim(p_branch_phone), ''),
    NULLIF(trim(p_branch_maps_url), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_branch_id;

  INSERT INTO public.staff_branch_assignments (
    staff_member_id,
    branch_id,
    is_primary,
    created_by,
    updated_by
  )
  VALUES (v_staff.id, v_branch_id, true, auth.uid(), auth.uid());

  FOR v_staff_entry IN SELECT value FROM jsonb_array_elements(p_staff_accounts)
  LOOP
    v_username := auth_internal.normalize_username(v_staff_entry ->> 'username');
    v_role := (v_staff_entry ->> 'role')::public.staff_role;

    v_auth_user_id := auth_internal.create_auth_user(v_staff_entry ->> 'username', v_staff_entry ->> 'password');

    INSERT INTO public.staff_members (
      auth_user_id,
      full_name,
      role,
      created_by,
      updated_by
    )
    VALUES (
      v_auth_user_id,
      trim(v_staff_entry ->> 'full_name'),
      v_role,
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_staff_member_id;

    INSERT INTO public.staff_branch_assignments (
      staff_member_id,
      branch_id,
      is_primary,
      created_by,
      updated_by
    )
    VALUES (
      v_staff_member_id,
      v_branch_id,
      true,
      auth.uid(),
      auth.uid()
    );

    v_staff_ids := array_append(v_staff_ids, v_staff_member_id);
  END LOOP;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'organization.bootstrap_finish_setup',
    'organizations',
    v_org_id,
    jsonb_build_object(
      'organization_id', v_org_id,
      'branch_id', v_branch_id,
      'staff_member_ids', to_jsonb(v_staff_ids)
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'organization_id', v_org_id,
      'branch_id', v_branch_id,
      'staff_member_ids', to_jsonb(v_staff_ids)
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'USERNAME_EXISTS' THEN
      RETURN public.rpc_error('USERNAME_EXISTS', 'A staff account with this username already exists.');
    END IF;
    IF SQLERRM = 'NOT_BOOTSTRAP_ADMIN' THEN
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may finish clinic setup.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Role permission and billing RPCs
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
  v_key text := trim(p_permission_key);
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();

  IF NULLIF(v_key, '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Permission key is required.');
  END IF;

  IF v_key = 'settings.billing.manage'
     AND p_is_granted = true
     AND p_role <> 'administrator' THEN
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
  WHERE rp.role = p_role
    AND rp.permission_key = v_key
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
    AND rp.permission_key = v_key
    AND rp.is_deleted = false
  RETURNING * INTO v_row;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'role_permission.update',
    'roles_permissions',
    v_row.id,
    jsonb_build_object('role', p_role::text, 'permission_key', v_key, 'is_granted', v_old),
    jsonb_build_object('role', p_role::text, 'permission_key', v_key, 'is_granted', p_is_granted)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'role', p_role::text,
      'permission_key', v_key,
      'is_granted', p_is_granted
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update role permissions.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.update_billing_settings(p_allow_partial_payments boolean)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_prior boolean;
  v_settings_id uuid;
BEGIN
  v_staff := auth_internal.assert_permission('settings.billing.manage');
  v_org_id := public.jwt_organization_id();

  IF v_staff.role <> 'administrator' THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'Only administrators can update billing settings.'
    );
  END IF;

  IF p_allow_partial_payments IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'allow_partial_payments is required.');
  END IF;

  SELECT obs.allow_partial_payments, obs.organization_id
  INTO v_prior, v_settings_id
  FROM public.organization_billing_settings obs
  WHERE obs.organization_id = v_org_id;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Billing settings were not found for this organization.');
  END IF;

  UPDATE public.organization_billing_settings
  SET allow_partial_payments = p_allow_partial_payments,
      updated_at = now(),
      updated_by = auth.uid()
  WHERE organization_id = v_org_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'billing_settings.update',
    'organization_billing_settings',
    v_settings_id,
    jsonb_build_object('allow_partial_payments', v_prior),
    jsonb_build_object('allow_partial_payments', p_allow_partial_payments)
  );

  RETURN public.rpc_success(jsonb_build_object('allow_partial_payments', p_allow_partial_payments));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update billing settings.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Branch access and JWT claims (administrator org-wide access)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.staff_can_access_branch(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_branch_id IS NOT NULL
    AND (
      p_branch_id = ANY (public.jwt_branch_ids())
      OR (
        public.jwt_staff_role() = 'administrator'
        AND public.jwt_organization_id() IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.branches b
          WHERE b.id = p_branch_id
            AND b.organization_id = public.jwt_organization_id()
            AND b.is_deleted = false
            AND b.is_active = true
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION auth_internal.build_staff_claims(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_branch_ids text;
  v_setup_required boolean;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = p_user_id
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT o.id
  INTO v_org_id
  FROM public.organizations o
  WHERE o.is_deleted = false
  ORDER BY o.created_at
  LIMIT 1;

  IF v_staff.role = 'administrator' AND v_org_id IS NOT NULL THEN
    SELECT string_agg(b.id::text, ',' ORDER BY b.name)
    INTO v_branch_ids
    FROM public.branches b
    WHERE b.organization_id = v_org_id
      AND b.is_deleted = false
      AND b.is_active = true;
  ELSE
    SELECT string_agg(b.id::text, ',' ORDER BY sba.is_primary DESC, b.name)
    INTO v_branch_ids
    FROM public.staff_branch_assignments sba
    JOIN public.branches b ON b.id = sba.branch_id
    WHERE sba.staff_member_id = v_staff.id
      AND sba.is_deleted = false
      AND b.is_deleted = false
      AND b.is_active = true;
  END IF;

  v_setup_required := v_staff.is_bootstrap_admin AND v_org_id IS NULL;

  RETURN jsonb_strip_nulls(
    jsonb_build_object(
      'staff_member_id', v_staff.id::text,
      'staff_role', v_staff.role::text,
      'organization_id', CASE WHEN v_setup_required THEN NULL ELSE v_org_id::text END,
      'branch_ids', COALESCE(v_branch_ids, ''),
      'setup_required', v_setup_required
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- RLS policies (recreated after enum migration)
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS staff_branch_assignments_select ON public.staff_branch_assignments;

CREATE POLICY staff_branch_assignments_select ON public.staff_branch_assignments FOR
SELECT
  TO authenticated USING (
    is_deleted = false
    AND (
      branch_id = ANY (public.jwt_branch_ids ())
      OR (
        public.jwt_setup_required ()
        AND staff_member_id = public.jwt_staff_member_id ()
      )
      OR (
        public.jwt_staff_role () = 'administrator'
        AND EXISTS (
          SELECT
            1
          FROM
            public.branches b
          WHERE
            b.id = staff_branch_assignments.branch_id
            AND b.organization_id = public.jwt_organization_id ()
            AND b.is_deleted = false
        )
      )
    )
  );

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
        WHERE sm.role = 'administrator'
      )
    )
  );

-- -----------------------------------------------------------------------------
-- Public RPC wrappers (recreated after enum CASCADE)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_staff_account(
  p_username text,
  p_password text,
  p_full_name text,
  p_role public.staff_role,
  p_branch_ids uuid[],
  p_primary_branch_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_staff_account(
    p_username,
    p_password,
    p_full_name,
    p_role,
    p_branch_ids,
    p_primary_branch_id
  );
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

CREATE OR REPLACE FUNCTION public.set_staff_active(p_staff_member_id uuid, p_is_active boolean)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_staff_active(p_staff_member_id, p_is_active);
$$;

CREATE OR REPLACE FUNCTION public.bootstrap_finish_setup(
  p_org_name text,
  p_branch_name text,
  p_staff_accounts jsonb,
  p_settings_json jsonb DEFAULT '{}'::jsonb,
  p_logo_url text DEFAULT NULL,
  p_currency_code text DEFAULT NULL,
  p_timezone text DEFAULT NULL,
  p_branch_code text DEFAULT NULL,
  p_branch_address text DEFAULT NULL,
  p_branch_phone text DEFAULT NULL,
  p_branch_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.bootstrap_finish_setup(
    p_org_name,
    p_branch_name,
    p_staff_accounts,
    p_settings_json,
    p_logo_url,
    p_currency_code,
    p_timezone,
    p_branch_code,
    p_branch_address,
    p_branch_phone,
    p_branch_maps_url
  );
$$;

REVOKE EXECUTE ON FUNCTION public.create_staff_account(text, text, text, public.staff_role, uuid[], uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_staff_account(text, text, text, public.staff_role, uuid[], uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_staff_member(uuid, text, public.staff_role, uuid[], text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_role_permission(public.staff_role, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_staff_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bootstrap_finish_setup(
  text, text, jsonb, jsonb, text, text, text, text, text, text, text
) TO authenticated;
