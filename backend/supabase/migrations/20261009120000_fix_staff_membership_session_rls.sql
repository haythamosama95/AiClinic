-- Fix login session load after tenant scoping: allow reading your own staff row and
-- branch assignments; keep colleague visibility membership-gated; sync membership
-- from bootstrap / staff provisioning RPCs (not from branch assignments alone).

CREATE OR REPLACE FUNCTION auth_internal.upsert_organization_membership(
  p_user_id uuid,
  p_organization_id uuid,
  p_role public.staff_role
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL OR p_organization_id IS NULL OR p_role IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES (p_user_id, p_organization_id, p_role)
  ON CONFLICT (user_id, organization_id) DO UPDATE
    SET role = EXCLUDED.role;
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.upsert_organization_membership(uuid, uuid, public.staff_role)
  FROM PUBLIC, anon, authenticated, service_role;

-- Repair bootstrap administrators who have a branch in an org but no membership row
-- (common after tenant-scoping landed on an existing local database).
INSERT INTO ai_internal.membership (user_id, organization_id, role)
SELECT DISTINCT
  sm.auth_user_id,
  b.organization_id,
  sm.role
FROM public.staff_members sm
JOIN public.staff_branch_assignments sba
  ON sba.staff_member_id = sm.id
  AND sba.is_deleted = false
JOIN public.branches b
  ON b.id = sba.branch_id
  AND b.is_deleted = false
WHERE sm.is_deleted = false
  AND sm.is_active = true
  AND sm.is_bootstrap_admin = true
  AND NOT EXISTS (
    SELECT 1
    FROM ai_internal.membership m
    WHERE m.user_id = sm.auth_user_id
      AND m.organization_id = b.organization_id
  )
ON CONFLICT (user_id, organization_id) DO UPDATE
  SET role = EXCLUDED.role;

DROP POLICY IF EXISTS staff_members_select ON public.staff_members;

CREATE POLICY staff_members_select ON public.staff_members
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      auth_user_id = auth.uid()
      OR (
        public.current_org_id() IS NOT NULL
        AND auth_internal.user_has_organization_membership(
          staff_members.auth_user_id,
          public.current_org_id()
        )
      )
    )
  );

DROP POLICY IF EXISTS staff_branch_assignments_select ON public.staff_branch_assignments;

CREATE POLICY staff_branch_assignments_select ON public.staff_branch_assignments
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      (
        public.current_org_id() IS NULL
        AND public.jwt_setup_required()
        AND staff_member_id = public.jwt_staff_member_id()
      )
      OR (
        EXISTS (
          SELECT 1
          FROM public.staff_members sm
          WHERE sm.id = staff_branch_assignments.staff_member_id
            AND sm.is_deleted = false
            AND sm.auth_user_id = auth.uid()
        )
        AND (
          public.current_org_id() IS NULL
          OR EXISTS (
            SELECT 1
            FROM public.branches b
            WHERE b.id = staff_branch_assignments.branch_id
              AND b.is_deleted = false
              AND b.organization_id = public.current_org_id()
          )
        )
      )
      OR (
        public.current_org_id() IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.branches b
          WHERE b.id = staff_branch_assignments.branch_id
            AND b.is_deleted = false
            AND b.organization_id = public.current_org_id()
        )
        AND EXISTS (
          SELECT 1
          FROM public.staff_members sm
          WHERE sm.id = staff_branch_assignments.staff_member_id
            AND sm.is_deleted = false
            AND auth_internal.user_has_organization_membership(
              sm.auth_user_id,
              public.current_org_id()
            )
        )
      )
    )
  );

CREATE OR REPLACE FUNCTION auth_internal.bootstrap_create_organization(
  p_name text,
  p_settings_json jsonb DEFAULT '{}'::jsonb,
  p_logo_url text DEFAULT NULL,
  p_currency_code text DEFAULT NULL,
  p_timezone text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org_id uuid;
BEGIN
  v_staff := auth_internal.assert_bootstrap_admin();

  IF auth_internal.organization_exists() THEN
    RETURN public.rpc_error('ORG_ALREADY_EXISTS', 'An organization already exists for this installation.');
  END IF;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Organization name is required.');
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
    trim(p_name),
    NULLIF(trim(p_logo_url), ''),
    NULLIF(trim(p_currency_code), ''),
    NULLIF(trim(p_timezone), ''),
    COALESCE(p_settings_json, '{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_org_id;

  PERFORM auth_internal.upsert_organization_membership(
    v_staff.auth_user_id,
    v_org_id,
    v_staff.role
  );

  PERFORM auth_internal.seed_organization_catalog_defaults(v_org_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'organization.bootstrap_create',
    'organizations',
    v_org_id,
    jsonb_build_object(
      'name', trim(p_name),
      'logo_url', NULLIF(trim(p_logo_url), ''),
      'currency_code', NULLIF(trim(p_currency_code), ''),
      'timezone', NULLIF(trim(p_timezone), '')
    )
  );

  RETURN public.rpc_success(jsonb_build_object('organization_id', v_org_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'NOT_BOOTSTRAP_ADMIN' THEN
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may create the organization.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.bootstrap_create_branch(
  p_organization_id uuid,
  p_name text,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_code text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_branch_id uuid;
  v_is_first_branch boolean;
BEGIN
  v_staff := auth_internal.assert_bootstrap_admin();

  IF NOT EXISTS (
    SELECT 1
    FROM public.organizations o
    WHERE o.id = p_organization_id
      AND o.is_deleted = false
  ) THEN
    RETURN public.rpc_error('ORG_NOT_FOUND', 'Organization was not found.');
  END IF;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch name is required.');
  END IF;

  SELECT NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.organization_id = p_organization_id
      AND b.is_deleted = false
  )
  INTO v_is_first_branch;

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
    p_organization_id,
    trim(p_name),
    NULLIF(trim(p_code), ''),
    NULLIF(trim(p_address), ''),
    NULLIF(trim(p_phone), ''),
    NULLIF(trim(p_maps_url), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_branch_id;

  IF v_is_first_branch THEN
    INSERT INTO public.staff_branch_assignments (
      staff_member_id,
      branch_id,
      is_primary,
      created_by,
      updated_by
    )
    VALUES (v_staff.id, v_branch_id, true, auth.uid(), auth.uid());

    PERFORM auth_internal.upsert_organization_membership(
      v_staff.auth_user_id,
      p_organization_id,
      v_staff.role
    );
  END IF;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    p_organization_id,
    'branch.bootstrap_create',
    'branches',
    v_branch_id,
    jsonb_build_object(
      'organization_id', p_organization_id,
      'name', trim(p_name),
      'code', NULLIF(trim(p_code), ''),
      'maps_url', NULLIF(trim(p_maps_url), '')
    )
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', v_branch_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'NOT_BOOTSTRAP_ADMIN' THEN
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may create the first branch.');
    END IF;
    RAISE;
END;
$$;

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

  IF v_org_id IS NULL THEN
    SELECT b.organization_id
    INTO v_org_id
    FROM public.branches b
    WHERE b.id = v_primary
      AND b.is_deleted = false
    LIMIT 1;
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

  IF v_org_id IS NOT NULL THEN
    PERFORM auth_internal.upsert_organization_membership(v_auth_user_id, v_org_id, p_role);
  END IF;

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
  p_branch_maps_url text DEFAULT NULL,
  p_branch_working_schedule jsonb DEFAULT NULL
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
  v_schedule_error text;
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

  IF p_branch_working_schedule IS NOT NULL THEN
    v_schedule_error := auth_internal.validate_branch_working_schedule(p_branch_working_schedule);
    IF v_schedule_error IS NOT NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', v_schedule_error);
    END IF;
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

  PERFORM auth_internal.upsert_organization_membership(
    v_staff.auth_user_id,
    v_org_id,
    v_staff.role
  );

  INSERT INTO public.branches (
    organization_id,
    name,
    code,
    address,
    phone,
    maps_url,
    working_schedule,
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
    p_branch_working_schedule,
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
      phone,
      created_by,
      updated_by
    )
    VALUES (
      v_auth_user_id,
      trim(v_staff_entry ->> 'full_name'),
      v_role,
      NULLIF(trim(v_staff_entry ->> 'phone'), ''),
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

    PERFORM auth_internal.upsert_organization_membership(v_auth_user_id, v_org_id, v_role);

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

DROP TRIGGER IF EXISTS staff_branch_assignments_sync_membership ON public.staff_branch_assignments;
DROP FUNCTION IF EXISTS auth_internal.sync_membership_from_branch_assignment();
