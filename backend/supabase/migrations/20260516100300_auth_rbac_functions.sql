-- =============================================================================
-- MIGRATION 4 of 5: Business logic functions (RPCs) and JWT custom claims
-- =============================================================================
--
-- WHAT THIS FILE DOES:
--   1) Builds JWT "custom claims" at login so RLS policies know org/branches/role.
--   2) Exposes RPC functions the Flutter app calls for bootstrap and staff admin.
--   3) Creates auth users server-side (staff provisioning) with hashed passwords.
--
-- KEY CONCEPTS:
--   • RPC = Remote Procedure Call; Flutter: supabase.rpc('function_name', params).
--   • SECURITY DEFINER = runs as function owner, can bypass RLS carefully; must validate caller.
--   • GoTrue = Supabase Auth service; calls get_custom_claims(jsonb) on each token issue.
--   • auth.users / auth.identities = internal Supabase tables for logins (not in public schema).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- build_staff_claims: assemble JWT payload for one user id
-- -----------------------------------------------------------------------------
-- Called at login. If user is not active staff, returns empty {} (no org access).
-- setup_required = true when bootstrap admin exists but organization table is empty.
CREATE OR REPLACE FUNCTION public.build_staff_claims(p_user_id uuid)
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

  -- V1-1: single organization per installation (first non-deleted org wins)
  SELECT o.id
  INTO v_org_id
  FROM public.organizations o
  WHERE o.is_deleted = false
  ORDER BY o.created_at
  LIMIT 1;

  -- Comma-separated branch UUIDs; primary branch listed first for UI defaults
  SELECT string_agg(b.id::text, ',' ORDER BY sba.is_primary DESC, b.name)
  INTO v_branch_ids
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  WHERE sba.staff_member_id = v_staff.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.is_active = true;

  v_setup_required := v_staff.is_bootstrap_admin AND v_org_id IS NULL;

  RETURN jsonb_strip_nulls(
    jsonb_build_object(
      'staff_member_id', v_staff.id::text,
      'role', v_staff.role::text,
      'organization_id', CASE WHEN v_setup_required THEN NULL ELSE v_org_id::text END,
      'branch_ids', COALESCE(v_branch_ids, ''),
      'setup_required', v_setup_required
    )
  );
END;
$$;

-- Wrapper for tests and direct SQL calls
CREATE OR REPLACE FUNCTION public.get_custom_claims(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT public.build_staff_claims(p_user_id);
$$;

-- -----------------------------------------------------------------------------
-- get_custom_claims(event jsonb): GoTrue Auth Hook entry point
-- -----------------------------------------------------------------------------
-- Supabase Auth passes an event like { "user_id": "...", "claims": { ... } }.
-- We merge existing claims with staff-specific fields from build_staff_claims.
-- Configure this hook in Supabase dashboard / config for custom access tokens.
CREATE OR REPLACE FUNCTION public.get_custom_claims(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_claims jsonb;
  v_custom jsonb;
BEGIN
  v_user_id := (event ->> 'user_id')::uuid;
  v_claims := COALESCE(event -> 'claims', '{}'::jsonb);
  v_custom := public.build_staff_claims(v_user_id);
  RETURN jsonb_build_object('claims', v_claims || v_custom);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_custom_claims(uuid) TO authenticated, service_role;

-- GoTrue runs as supabase_auth_admin; grant only if that role exists (local vs hosted)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    GRANT EXECUTE ON FUNCTION public.get_custom_claims(jsonb) TO supabase_auth_admin;
    GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- RPC helpers: uniform success/error responses for the Flutter client
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_success(p_data jsonb DEFAULT '{}'::jsonb)
RETURNS public.rpc_result
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (true, p_data, NULL::text, NULL::text)::public.rpc_result;
$$;

CREATE OR REPLACE FUNCTION public.rpc_error(p_code text, p_message text)
RETURNS public.rpc_result
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (false, NULL::jsonb, p_code, p_message)::public.rpc_result;
$$;

-- -----------------------------------------------------------------------------
-- Authorization guards (internal; used by RPCs, not called from Flutter directly)
-- -----------------------------------------------------------------------------

-- Must be the seeded bootstrap admin (first installer)
CREATE OR REPLACE FUNCTION public.assert_bootstrap_admin()
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

  IF NOT FOUND OR NOT v_staff.is_bootstrap_admin THEN
    RAISE EXCEPTION 'NOT_BOOTSTRAP_ADMIN';
  END IF;

  RETURN v_staff;
END;
$$;

-- Must be owner, administrator, or bootstrap admin
CREATE OR REPLACE FUNCTION public.assert_owner_or_administrator()
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

  IF v_staff.role NOT IN ('owner', 'administrator') AND NOT v_staff.is_bootstrap_admin THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN v_staff;
END;
$$;

-- Installation state checks
CREATE OR REPLACE FUNCTION public.organization_exists()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organizations o
    WHERE o.is_deleted = false
  );
$$;

CREATE OR REPLACE FUNCTION public.owner_exists()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.staff_members sm
    WHERE sm.role = 'owner'
      AND sm.is_deleted = false
      AND sm.is_active = true
  );
$$;

-- -----------------------------------------------------------------------------
-- RPC: bootstrap_create_organization
-- -----------------------------------------------------------------------------
-- First-time setup: bootstrap admin creates the single clinic organization.
-- Fails if org already exists or caller is not bootstrap admin.
CREATE OR REPLACE FUNCTION public.bootstrap_create_organization(
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
  v_org_id uuid;
BEGIN
  PERFORM public.assert_bootstrap_admin();

  IF public.organization_exists() THEN
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

-- -----------------------------------------------------------------------------
-- RPC: bootstrap_create_branch
-- -----------------------------------------------------------------------------
-- Creates a branch under the org. First branch auto-assigns bootstrap admin as primary.
CREATE OR REPLACE FUNCTION public.bootstrap_create_branch(
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
  v_staff := public.assert_bootstrap_admin();

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

-- -----------------------------------------------------------------------------
-- Internal: create_auth_user
-- -----------------------------------------------------------------------------
-- Inserts into Supabase auth.users + auth.identities (email provider).
-- Password hashed with bcrypt via pgcrypto (extensions.crypt / gen_salt).
-- NOT granted to clients; only called from create_staff_account.
CREATE OR REPLACE FUNCTION public.create_auth_user(
  p_email text,
  p_password text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid := gen_random_uuid();
BEGIN
  IF EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE lower(u.email) = lower(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'EMAIL_EXISTS';
  END IF;

  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    lower(trim(p_email)),
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    '{}'::jsonb,
    now(),
    now()
  );

  INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', lower(trim(p_email))),
    'email',
    lower(trim(p_email)),
    now(),
    now(),
    now()
  );

  RETURN v_user_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- RPC: create_staff_account
-- -----------------------------------------------------------------------------
-- Owner/admin creates a new staff login + staff_members row + branch assignments.
-- Returns assigned_password once so admin can share it (no email in V1-1).
CREATE OR REPLACE FUNCTION public.create_staff_account(
  p_email text,
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
BEGIN
  v_caller := public.assert_owner_or_administrator();

  IF NOT public.organization_exists() THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Create an organization and branch before provisioning staff.');
  END IF;

  IF p_branch_ids IS NULL OR cardinality(p_branch_ids) = 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'At least one branch assignment is required.');
  END IF;

  IF NULLIF(trim(p_email), '') IS NULL OR NULLIF(trim(p_password), '') IS NULL OR NULLIF(trim(p_full_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Email, password, and full name are required.');
  END IF;

  -- Owner role: only one "first owner" via bootstrap; later owners need existing owner caller
  IF p_role = 'owner' THEN
    IF public.owner_exists() THEN
      IF v_caller.role <> 'owner' THEN
        RETURN public.rpc_error(
          'FORBIDDEN_OWNER_CREATE',
          'Only existing owners may create additional owner accounts.'
        );
      END IF;
    ELSIF NOT v_caller.is_bootstrap_admin THEN
      RETURN public.rpc_error(
        'FORBIDDEN_OWNER_CREATE',
        'Only the bootstrap administrator may create the first owner account.'
      );
    END IF;
  END IF;

  -- Every branch id must belong to a live branch in this installation's org
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

  v_auth_user_id := public.create_auth_user(p_email, p_password);

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
    jsonb_build_object('email', lower(trim(p_email)), 'role', p_role::text)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'staff_member_id', v_staff_id,
      'assigned_password', p_password
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'EMAIL_EXISTS' THEN
      RETURN public.rpc_error('EMAIL_EXISTS', 'A staff account with this email already exists.');
    END IF;
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create staff accounts.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- RPC: admin_reset_staff_password
-- -----------------------------------------------------------------------------
-- Owner/admin sets a new password for another staff member in the same organization.
CREATE OR REPLACE FUNCTION public.admin_reset_staff_password(
  p_staff_member_id uuid,
  p_new_password text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_target public.staff_members%ROWTYPE;
  v_auth_user_id uuid;
BEGIN
  PERFORM public.assert_owner_or_administrator();

  IF NULLIF(trim(p_new_password), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'A new password is required.');
  END IF;

  SELECT sm.*
  INTO v_target
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id
    AND sm.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found.');
  END IF;

  -- Prevent resetting staff in another organization (cross-tenant safety)
  IF EXISTS (
    SELECT 1
    FROM public.staff_branch_assignments sba
    JOIN public.branches b ON b.id = sba.branch_id
    WHERE sba.staff_member_id = v_target.id
      AND sba.is_deleted = false
      AND b.organization_id IS DISTINCT FROM public.jwt_organization_id()
  ) THEN
    RETURN public.rpc_error('CROSS_ORG_DENIED', 'Staff member is outside your organization scope.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.staff_branch_assignments sba
    JOIN public.branches b ON b.id = sba.branch_id
    WHERE sba.staff_member_id = v_target.id
      AND sba.is_deleted = false
      AND b.organization_id = public.jwt_organization_id()
  ) THEN
    RETURN public.rpc_error('CROSS_ORG_DENIED', 'Staff member is outside your organization scope.');
  END IF;

  v_auth_user_id := v_target.auth_user_id;

  UPDATE auth.users
  SET
    encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
    updated_at = now()
  WHERE id = v_auth_user_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'staff.password_reset',
    'staff_members',
    p_staff_member_id,
    jsonb_build_object('staff_member_id', p_staff_member_id)
  );

  RETURN public.rpc_success(jsonb_build_object('assigned_password', p_new_password));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to reset staff passwords.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Grant Flutter clients permission to call these RPCs (authenticated role only)
-- -----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.bootstrap_create_organization(text, jsonb, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bootstrap_create_branch(uuid, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_staff_account(text, text, text, public.staff_role, uuid[], uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reset_staff_password(uuid, text) TO authenticated;
