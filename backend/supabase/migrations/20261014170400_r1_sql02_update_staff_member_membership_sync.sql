-- =============================================================================
-- R1-SQL-02 (P1) steps 1–2: Staff demotion never updates membership billing
-- authority.
--
-- Provisioning writes ai_internal.membership.role
-- (20261009120000_fix_staff_membership_session_rls.sql), but the final
-- auth_internal.update_staff_member changed only staff_members.role and
-- assignments (20260611170000_restore_last_administrator_guard.sql). No later
-- membership synchronization existed, so an administrator legitimately demoted
-- to doctor kept a stale administrator membership and could keep minting fresh
-- administrator billing tokens forever (the mint authorizes through
-- public.current_membership_role(), canonical_billing_jwt_json.sql);
-- promotion failed inversely. AI token roles/scopes stayed stale too.
--
-- Forward override of auth_internal.update_staff_member that, within the same
-- transaction as the authorized staff change:
--   1. locks and verifies the target user's membership row for
--      public.current_org_id();
--   2. atomically updates that row's role with the authorized staff change.
--
-- The membership role is the authorization authority in each org (04 §2.1);
-- staff_members.role is retained only for the existing compatibility/profile
-- representation. Roles of the same user in other organisations are NOT
-- overwritten. Role is never inferred from branch assignment creation.
-- The existing administrator-count, org/branch and permission checks (and the
-- last-administrator guard) are preserved exactly.
-- Step 3 (D-1 data repair) is the follow-up migration
-- 20261014170500_r1_sql02_membership_role_repair.sql.
-- Forward-only migration; never edit an applied migration file.
-- =============================================================================

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
  v_locked_membership_org uuid;
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
  SELECT m.organization_id
  INTO v_locked_membership_org
  FROM ai_internal.membership m
  WHERE m.user_id = v_target_auth_user_id
    AND m.organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.rpc_error('MEMBERSHIP_NOT_FOUND', 'Staff member has no membership in your organization.');
  END IF;

  v_old_role := v_target.role;

  IF v_old_role = 'administrator' AND p_role != 'administrator' THEN
    BEGIN
      PERFORM auth_internal.assert_not_last_administrator(p_staff_member_id);
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

-- ACLs on auth_internal.update_staff_member are unchanged: the public
-- SECURITY INVOKER wrapper (20260611150000_remove_owner_role.sql) delegates to
-- this function and authenticated callers keep EXECUTE via
-- 20260525120200_fix_restrict_auth_internal_grants.sql.