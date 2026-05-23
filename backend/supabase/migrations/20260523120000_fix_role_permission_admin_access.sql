-- =============================================================================
-- Fix: allow administrators to update the permission matrix (Phase 7 contract)
-- =============================================================================
--
-- Installations that applied 20260522100000_org_branch_management.sql before
-- Phase 7 still have owner-only auth_internal.update_role_permission. The app
-- UI allows owner and administrator; re-apply the corrected function here.
-- =============================================================================

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
  v_caller := auth_internal.assert_owner_or_administrator();

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
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'Only owners and administrators may update the permission matrix.');
    END IF;
    RAISE;
END;
$$;
