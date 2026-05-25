-- Fix 29: Block bootstrap admin password reset by other staff members.
-- Only the bootstrap admin themselves can reset their own password.

CREATE OR REPLACE FUNCTION auth_internal.admin_reset_staff_password(
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
  PERFORM auth_internal.assert_owner_or_administrator();

  IF NULLIF(trim(p_new_password), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'A new password is required.');
  END IF;

  -- Password complexity validation
  BEGIN
    PERFORM auth_internal.assert_password_complexity(p_new_password);
  EXCEPTION
    WHEN check_violation THEN
      RETURN public.rpc_error('WEAK_PASSWORD', SQLERRM);
  END;

  SELECT sm.*
  INTO v_target
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id
    AND sm.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('STAFF_NOT_FOUND', 'Staff member was not found.');
  END IF;

  -- Protect bootstrap admin: only they can reset their own password
  IF v_target.is_bootstrap_admin AND v_target.auth_user_id != auth.uid() THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'The bootstrap administrator password can only be changed by the bootstrap admin themselves.'
    );
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

  RETURN public.rpc_success(
    jsonb_build_object(
      'staff_member_id', p_staff_member_id,
      'password_reset', true
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to reset staff passwords.');
    END IF;
    RAISE;
END;
$$;
