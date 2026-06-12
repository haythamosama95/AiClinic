-- Ensure every catalog permission exists for every staff role so administrators
-- can configure the full matrix (e.g. grant ai.access to receptionist).

INSERT INTO public.roles_permissions (role, permission_key, is_granted)
SELECT r.role::public.staff_role, p.permission_key, false
FROM (
  VALUES
    ('administrator'),
    ('doctor'),
    ('receptionist'),
    ('lab_staff')
) AS r(role)
CROSS JOIN (
  SELECT DISTINCT permission_key
  FROM public.roles_permissions
  WHERE is_deleted = false
) AS p(permission_key)
ON CONFLICT (role, permission_key) DO NOTHING;

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
  v_old boolean := false;
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
    v_old := false;
  END IF;

  INSERT INTO public.roles_permissions (role, permission_key, is_granted, updated_by)
  VALUES (p_role, v_key, p_is_granted, auth.uid())
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
