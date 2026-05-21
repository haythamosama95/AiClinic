-- Staff auth: replace email identifiers with usernames (stored in auth.users.email for GoTrue).

DROP FUNCTION IF EXISTS public.create_staff_account(text, text, text, public.staff_role, uuid[], uuid);
DROP FUNCTION IF EXISTS auth_internal.create_staff_account(text, text, text, public.staff_role, uuid[], uuid);
DROP FUNCTION IF EXISTS auth_internal.create_auth_user(text, text);

CREATE OR REPLACE FUNCTION auth_internal.normalize_username(p_username text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(p_username));
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_valid_username(p_username text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_normalized text := auth_internal.normalize_username(p_username);
BEGIN
  IF v_normalized IS NULL OR v_normalized = '' THEN
    RAISE EXCEPTION 'INVALID_USERNAME' USING ERRCODE = '22023';
  END IF;

  IF position('@' IN v_normalized) > 0 THEN
    RAISE EXCEPTION 'INVALID_USERNAME' USING ERRCODE = '22023';
  END IF;

  IF char_length(v_normalized) < 3 OR char_length(v_normalized) > 32 THEN
    RAISE EXCEPTION 'INVALID_USERNAME' USING ERRCODE = '22023';
  END IF;

  IF v_normalized !~ '^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$' THEN
    RAISE EXCEPTION 'INVALID_USERNAME' USING ERRCODE = '22023';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.create_auth_user(p_username text, p_password text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid := gen_random_uuid();
  v_username text;
BEGIN
  PERFORM auth_internal.assert_valid_username(p_username);
  v_username := auth_internal.normalize_username(p_username);

  IF EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE lower(u.email) = v_username
  ) THEN
    RAISE EXCEPTION 'USERNAME_EXISTS';
  END IF;

  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
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
    v_username,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '',
    '',
    '',
    '',
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
    jsonb_build_object('sub', v_user_id::text, 'email', v_username),
    'email',
    v_username,
    now(),
    now(),
    now()
  );

  RETURN v_user_id;
END;
$$;

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
    PERFORM auth_internal.assert_valid_username(p_username);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'INVALID_USERNAME' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Enter a valid username (3-32 letters, numbers, underscore, or hyphen).');
      END IF;
      RAISE;
  END;

  v_username := auth_internal.normalize_username(p_username);

  IF p_role = 'owner' THEN
    IF auth_internal.owner_exists() THEN
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
      'assigned_password', p_password
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

REVOKE EXECUTE ON FUNCTION public.create_staff_account(text, text, text, public.staff_role, uuid[], uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_staff_account(text, text, text, public.staff_role, uuid[], uuid) TO authenticated;

-- Fail fast if any existing email local-part cannot become a valid username.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id, email
    FROM auth.users
    WHERE email LIKE '%@%'
  LOOP
    BEGIN
      PERFORM auth_internal.assert_valid_username(split_part(r.email, '@', 1));
    EXCEPTION
      WHEN SQLSTATE '22023' THEN
        RAISE EXCEPTION
          'staff_username_migration: cannot convert auth.users email=% (id=%) to a valid username (3-32 chars, [a-z0-9_-])',
          r.email, r.id
          USING ERRCODE = '22023';
    END;
  END LOOP;
END;
$$;

-- Migrate existing email-shaped auth identities to username local-part.
UPDATE auth.users
SET email = auth_internal.normalize_username(split_part(email, '@', 1))
WHERE email LIKE '%@%';

UPDATE auth.identities i
SET
  provider_id = u.email,
  identity_data = jsonb_set(
    COALESCE(i.identity_data, '{}'::jsonb),
    '{email}',
    to_jsonb(u.email),
    true
  )
FROM auth.users u
WHERE i.user_id = u.id
  AND i.provider = 'email';

-- Bootstrap seed account: admin@admin -> admin
UPDATE auth.users
SET email = 'admin'
WHERE lower(email) IN ('admin@admin', 'admin@clinic.local');

UPDATE auth.identities i
SET
  provider_id = 'admin',
  identity_data = jsonb_set(
    COALESCE(i.identity_data, '{}'::jsonb),
    '{email}',
    '"admin"'::jsonb,
    true
  )
FROM auth.users u
WHERE i.user_id = u.id
  AND i.provider = 'email'
  AND u.email = 'admin';
