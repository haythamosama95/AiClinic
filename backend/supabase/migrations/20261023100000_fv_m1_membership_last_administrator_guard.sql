-- =============================================================================
-- FV-M1 (Major): membership-based last-administrator guard.
--
-- RM02 made ai_internal.membership.role the per-organization authority, but the
-- last-administrator guard still read the global staff_members.role and picked
-- the organization with LIMIT 1 over branch assignments. A multi-org user could
-- leave an organization with no administrator.
--
--   1. New auth_internal.assert_not_last_administrator(uuid, uuid): org-scoped,
--      membership-based; locks the org's administrator memberships so two
--      concurrent demotions serialize. Raises LAST_ADMINISTRATOR (P0002).
--   2. The one-argument form keeps its signature and ACLs (used for global
--      deactivation and deletion by set_staff_active / delete_staff_member) and
--      now checks every organization where the target is an administrator.
--   3. update_staff_member decides on the locked current-org membership role
--      and calls the two-argument form; the body is otherwise identical to
--      20261014170400.
-- set_staff_active and delete_staff_member call the one-argument form and need
-- no redefinition. Forward-only.
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.assert_not_last_administrator(
  p_staff_member_id uuid,
  p_org_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_target_user uuid;
  v_other_administrators int;
BEGIN
  SELECT sm.auth_user_id INTO v_target_user
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id AND sm.is_deleted = false;

  IF v_target_user IS NULL OR p_org_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM ai_internal.membership m
    WHERE m.user_id = v_target_user
      AND m.organization_id = p_org_id
      AND m.role = 'administrator'
  ) THEN
    RETURN;
  END IF;

  -- Serialize concurrent demotions/deactivations in this organization.
  PERFORM 1
  FROM ai_internal.membership m
  WHERE m.organization_id = p_org_id
    AND m.role = 'administrator'
  ORDER BY m.user_id
  FOR UPDATE;

  SELECT count(*) INTO v_other_administrators
  FROM ai_internal.membership m
  JOIN public.staff_members sm ON sm.auth_user_id = m.user_id
  WHERE m.organization_id = p_org_id
    AND m.role = 'administrator'
    AND m.user_id <> v_target_user
    AND sm.is_active = true
    AND sm.is_deleted = false;

  IF v_other_administrators < 1 THEN
    RAISE EXCEPTION 'LAST_ADMINISTRATOR' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.assert_not_last_administrator(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION auth_internal.assert_not_last_administrator(p_staff_member_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_target_user uuid;
  v_org_id uuid;
BEGIN
  SELECT sm.auth_user_id INTO v_target_user
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id AND sm.is_deleted = false;

  IF v_target_user IS NULL THEN
    RETURN;
  END IF;

  -- Deactivation and deletion are global: check every organization where the
  -- target holds an administrator membership (stable order avoids deadlocks).
  FOR v_org_id IN
    SELECT m.organization_id
    FROM ai_internal.membership m
    WHERE m.user_id = v_target_user
      AND m.role = 'administrator'
    ORDER BY m.organization_id
  LOOP
    PERFORM auth_internal.assert_not_last_administrator(p_staff_member_id, v_org_id);
  END LOOP;
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
  v_old_role public.staff_role;
  v_target_auth_user_id uuid;
  v_locked_membership_role public.staff_role;
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

  v_target_auth_user_id := v_target.auth_user_id;

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

  -- R1-SQL-02: lock and verify the target membership for the caller's current
  -- organisation before mutating anything. A target without a membership in
  -- this organisation cannot be updated here; the authorization authority for
  -- this org must exist and stay in step with the staff change.
  SELECT m.role
  INTO v_locked_membership_role
  FROM ai_internal.membership m
  WHERE m.user_id = v_target_auth_user_id
    AND m.organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('MEMBERSHIP_NOT_FOUND', 'Staff member has no membership in your organization.');
  END IF;

  -- FV-M1: the locked current-org membership role is the authority, not the
  -- global staff_members.role.
  v_old_role := v_locked_membership_role;

  IF v_old_role = 'administrator' AND p_role != 'administrator' THEN
    BEGIN
      PERFORM auth_internal.assert_not_last_administrator(p_staff_member_id, v_org_id);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM = 'LAST_ADMINISTRATOR' THEN
          RETURN public.rpc_error('LAST_ADMINISTRATOR', 'Cannot demote the last active administrator.');
        END IF;
        RAISE;
    END;
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

  -- R1-SQL-02: keep the current-org membership role in step with the
  -- authorized staff change, atomically in this transaction. Roles of the
  -- same user in other organisations are untouched.
  UPDATE ai_internal.membership m
  SET role = p_role
  WHERE m.user_id = v_target_auth_user_id
    AND m.organization_id = v_org_id;

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
    jsonb_build_object('role', p_role::text, 'membership_role', p_role::text)
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
