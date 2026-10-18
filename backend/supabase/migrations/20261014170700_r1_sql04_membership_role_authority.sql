-- =============================================================================
-- R1-SQL-04 (P2): Backend administrative permission checks use global staff
-- role.
--
-- auth_internal.assert_permission (tenant_scoping.sql T-reader) matched
-- roles_permissions against the global staff_members.role, and
-- auth_internal.assert_owner_or_administrator (remove_owner_role.sql) trusted
-- that same global role. A dual-membership user whose global staff role is
-- administrator but whose membership role in B is doctor could switch to B and
-- edit B's permission matrix or invoke B's administrator-only provisioning.
-- The clinical/upload helpers joined the global staff role as well, and
-- staff_can_access_branch fell back to the JWT/global administrator claim.
--
-- Forward overrides resolving the role from public.current_membership_role()
-- once the current org is non-NULL. A NULL membership role denies.
-- R1-SQL-04 step 3 coordination: the shared predicate
-- auth_internal.staff_has_membership_permissions(text[]) performs every
-- org-local permission lookup with (current_org_id(), current_membership_role())
-- and active/non-deleted caller staff (current_org_id() enforces the live-staff
-- predicate added by R1-SQL-03). The R1-SQL-05 readers reuse it in
-- 20261014170800_r1_sql05_org_scoped_permission_readers.sql.
-- Bootstrap exception (step 2) retained only while active bootstrap staff
-- exists AND no organization exists; a bootstrap flag never bypasses an
-- existing organization's membership role.
-- Signatures, ACLs, return shapes and tenant/branch guards unchanged.
-- Forward-only migration; never edit an applied migration file.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Shared org-local permission predicate (R1-SQL-04 step 3).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.staff_has_membership_permissions(
  p_permission_keys text[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.current_membership_role() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.organization_id = public.current_org_id()
        AND rp.role = public.current_membership_role()
        AND rp.permission_key = ANY (p_permission_keys)
        AND rp.is_granted = true
        AND rp.is_deleted = false
    );
$$;

REVOKE ALL ON FUNCTION auth_internal.staff_has_membership_permissions(text[])
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- assert_permission: membership-role lookup; NULL context/role denies.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.assert_permission(p_permission_key text)
RETURNS public.staff_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org uuid;
  v_role public.staff_role;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = auth.uid()
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0003';
  END IF;

  -- R1-SQL-04 step 2: bootstrap exception only while no organization exists.
  IF v_staff.is_bootstrap_admin AND NOT auth_internal.organization_exists() THEN
    RETURN v_staff;
  END IF;

  v_org := public.current_org_id();
  v_role := public.current_membership_role();

  -- R1-SQL-04 step 1: NULL current org or NULL membership role denies; the
  -- global staff_members.role no longer substitutes for the membership role.
  IF v_org IS NULL OR v_role IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0003';
  END IF;

  IF NOT auth_internal.staff_has_membership_permissions(ARRAY[p_permission_key]) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0003';
  END IF;

  RETURN v_staff;
END;
$$;

-- -----------------------------------------------------------------------------
-- assert_owner_or_administrator: current-org membership administrator.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.assert_owner_or_administrator()
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

  -- R1-SQL-04 step 2: a bootstrap flag never bypasses an existing
  -- organization's membership role; the exception survives only while no
  -- organization exists (fresh installation setup).
  IF v_staff.is_bootstrap_admin AND NOT auth_internal.organization_exists() THEN
    RETURN v_staff;
  END IF;

  IF public.current_membership_role() IS DISTINCT FROM 'administrator' THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN v_staff;
END;
$$;

-- -----------------------------------------------------------------------------
-- Visit clinical/upload helpers: membership-role lookup.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.staff_has_visit_clinical_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth_internal.staff_has_membership_permissions(
    ARRAY['visits.create', 'visits.edit_soap']
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.staff_has_visit_upload_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth_internal.staff_has_membership_permissions(
    ARRAY['visits.upload_attachment', 'visits.create', 'visits.edit_soap']
  );
$$;

-- -----------------------------------------------------------------------------
-- staff_can_access_branch: live staff required; membership-role administrator
-- fallback; current-org assigned-branch path preserved.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.staff_can_access_branch(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_branch_id IS NOT NULL
    -- R1-SQL-04 step 1: live (non-deleted, active) caller staff required.
    AND EXISTS (
      SELECT 1
      FROM public.staff_members sm
      WHERE sm.auth_user_id = auth.uid()
        AND sm.is_deleted = false
        AND sm.is_active = true
    )
    AND (
      -- Current-org assigned-branch path (preserved).
      p_branch_id = ANY (public.jwt_branch_ids())
      OR (
        -- R1-SQL-04 step 1: the administrator fallback resolves from the
        -- current-org membership role, replacing the JWT/global administrator
        -- claim; active branch in the current organization.
        public.current_membership_role() = 'administrator'
        AND public.current_org_id() IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.branches b
          WHERE b.id = p_branch_id
            AND b.organization_id = public.current_org_id()
            AND b.is_deleted = false
            AND b.is_active = true
        )
      )
    );
$$;
