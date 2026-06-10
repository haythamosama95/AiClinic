-- Count the signed-in bootstrap administrator when validating setup staff accounts.
-- The bootstrap admin is already an administrator and is assigned to the first branch
-- during finish setup; drafts may be operational roles only (doctor, receptionist, etc.).

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

  IF v_staff.role = 'administrator' THEN
    v_admin_count := 1;
  END IF;

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
