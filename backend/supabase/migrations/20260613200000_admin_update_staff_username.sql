-- Allow clinic administrators to change a staff member's login username.

CREATE OR REPLACE FUNCTION auth_internal.admin_update_staff_username(
  p_staff_member_id uuid,
  p_new_username text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_target public.staff_members%ROWTYPE;
  v_auth_user_id uuid;
  v_username text;
BEGIN
  PERFORM auth_internal.assert_owner_or_administrator();

  IF NULLIF(trim(p_new_username), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'A new username is required.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_valid_username(p_new_username);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'INVALID_USERNAME' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Enter a valid username (3-32 letters, numbers, underscore, or hyphen).');
      END IF;
      RAISE;
  END;

  v_username := auth_internal.normalize_username(p_new_username);

  SELECT sm.*
  INTO v_target
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id
    AND sm.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found.');
  END IF;

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

  IF EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE lower(u.email) = v_username
      AND u.id <> v_auth_user_id
  ) THEN
    RETURN public.rpc_error('USERNAME_EXISTS', 'A staff account with this username already exists.');
  END IF;

  UPDATE auth.users
  SET
    email = v_username,
    updated_at = now()
  WHERE id = v_auth_user_id;

  UPDATE auth.identities
  SET
    provider_id = v_username,
    identity_data = jsonb_build_object('sub', v_auth_user_id::text, 'email', v_username),
    updated_at = now()
  WHERE user_id = v_auth_user_id
    AND provider = 'email';

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'staff.username_update',
    'staff_members',
    p_staff_member_id,
    jsonb_build_object('staff_member_id', p_staff_member_id, 'username', v_username)
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'staff_member_id', p_staff_member_id,
      'username', v_username
    )
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('USERNAME_EXISTS', 'A staff account with this username already exists.');
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_staff_username(
  p_staff_member_id uuid,
  p_new_username text
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.admin_update_staff_username(p_staff_member_id, p_new_username);
$$;

REVOKE ALL ON FUNCTION public.admin_update_staff_username(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_staff_username(uuid, text) TO authenticated;
