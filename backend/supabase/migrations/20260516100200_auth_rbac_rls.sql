-- =============================================================================
-- MIGRATION 3 of 5: Row Level Security (RLS) policies
-- =============================================================================
--
-- WHAT THIS FILE DOES:
--   Defines WHO can read/write WHICH rows in each table. Supabase attaches the
--   user's JWT (JSON Web Token) to every API request; policies read claims from it.
--
-- KEY CONCEPTS:
--   • authenticated role = any logged-in user (anon = not logged in).
--   • POLICY ... USING (...) = filter for SELECT/UPDATE/DELETE (which rows you see).
--   • WITH CHECK (...) = rules for INSERT/UPDATE (what values you may write).
--   • JWT custom claims = extra fields injected at login (org id, branch ids, role).
--   • Direct INSERT on sensitive tables is blocked (WITH CHECK false); clients must
--     use SECURITY DEFINER RPC functions from migration 4 instead.
--
-- FLOW:
--   User logs in → GoTrue calls get_custom_claims → JWT includes organization_id,
--   branch_ids, staff_member_id, role, setup_required → PostgREST enforces policies.
-- =============================================================================

-- Allow authenticated users to reference auth schema helpers if needed
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Broad table grants; RLS still restricts which ROWS are visible (grants ≠ bypass RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;

-- -----------------------------------------------------------------------------
-- Read JWT claims from the current HTTP request
-- -----------------------------------------------------------------------------
-- PostgREST sets request.jwt.claims; auth.jwt() is the fallback inside Supabase.
-- Returns {} if not logged in or in a context without a JWT (e.g. some migrations).
CREATE OR REPLACE FUNCTION public.request_jwt_claims()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_raw text;
BEGIN
  v_raw := current_setting('request.jwt.claims', true);
  IF v_raw IS NOT NULL AND v_raw <> '' THEN
    RETURN v_raw::jsonb;
  END IF;

  BEGIN
    RETURN auth.jwt();
  EXCEPTION
    WHEN insufficient_privilege OR undefined_function THEN
      RETURN '{}'::jsonb;
  END;
END;
$$;

-- Convenience extractors (used in policies below)
CREATE OR REPLACE FUNCTION public.jwt_organization_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(public.request_jwt_claims() ->> 'organization_id', '')::uuid;
$$;

-- branch_ids stored as comma-separated UUIDs in the JWT, e.g. "uuid1,uuid2"
CREATE OR REPLACE FUNCTION public.jwt_branch_ids()
RETURNS uuid[]
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    string_to_array(NULLIF(public.request_jwt_claims() ->> 'branch_ids', ''), ',')::uuid[],
    ARRAY[]::uuid[]
  );
$$;

CREATE OR REPLACE FUNCTION public.jwt_staff_member_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(public.request_jwt_claims() ->> 'staff_member_id', '')::uuid;
$$;

CREATE OR REPLACE FUNCTION public.jwt_staff_role()
RETURNS public.staff_role
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(public.request_jwt_claims() ->> 'role', '')::public.staff_role;
$$;

-- true when bootstrap admin has not yet created an organization (first-time setup)
CREATE OR REPLACE FUNCTION public.jwt_setup_required()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((public.request_jwt_claims() ->> 'setup_required')::boolean, false);
$$;

-- Load the staff_members row for whoever is logged in (bypasses RLS via SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.current_staff_member_row()
RETURNS public.staff_members
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT sm.*
  FROM public.staff_members sm
  WHERE sm.auth_user_id = auth.uid()
    AND sm.is_deleted = false
  LIMIT 1;
$$;

-- =============================================================================
-- TABLE: organizations
-- =============================================================================

-- SELECT: see your org OR (during setup) bootstrap admin before org exists
CREATE POLICY organizations_select ON public.organizations
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      id = public.jwt_organization_id()
      OR (
        public.jwt_setup_required()
        AND EXISTS (
          SELECT 1
          FROM public.current_staff_member_row() sm
          WHERE sm.is_bootstrap_admin
        )
      )
    )
  );

-- INSERT blocked at RLS layer; use bootstrap_create_organization() RPC instead
CREATE POLICY organizations_insert ON public.organizations
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

-- UPDATE: only rows matching your JWT organization_id
CREATE POLICY organizations_update ON public.organizations
  FOR UPDATE
  TO authenticated
  USING (is_deleted = false AND id = public.jwt_organization_id())
  WITH CHECK (is_deleted = false AND id = public.jwt_organization_id());

-- =============================================================================
-- TABLE: branches
-- =============================================================================

CREATE POLICY branches_select ON public.branches
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.jwt_organization_id()
  );

CREATE POLICY branches_insert ON public.branches
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

-- UPDATE: must be in your org AND branch must be one you're assigned to (jwt_branch_ids)
CREATE POLICY branches_update ON public.branches
  FOR UPDATE
  TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.jwt_organization_id()
    AND id = ANY (public.jwt_branch_ids())
  )
  WITH CHECK (
    is_deleted = false
    AND organization_id = public.jwt_organization_id()
  );

-- =============================================================================
-- TABLE: staff_members
-- =============================================================================

-- SELECT: yourself OR colleagues who share a branch in your organization
CREATE POLICY staff_members_select ON public.staff_members
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      auth_user_id = auth.uid()
      OR EXISTS (
        SELECT 1
        FROM public.staff_branch_assignments sba
        JOIN public.branches b ON b.id = sba.branch_id
        WHERE sba.staff_member_id = staff_members.id
          AND sba.is_deleted = false
          AND b.is_deleted = false
          AND b.organization_id = public.jwt_organization_id()
      )
    )
  );

CREATE POLICY staff_members_insert ON public.staff_members
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

CREATE POLICY staff_members_update ON public.staff_members
  FOR UPDATE
  TO authenticated
  USING (
    is_deleted = false
    AND (
      auth_user_id = auth.uid()
      OR EXISTS (
        SELECT 1
        FROM public.staff_branch_assignments sba
        JOIN public.branches b ON b.id = sba.branch_id
        WHERE sba.staff_member_id = staff_members.id
          AND sba.is_deleted = false
          AND b.organization_id = public.jwt_organization_id()
      )
    )
  )
  WITH CHECK (is_deleted = false);

-- =============================================================================
-- TABLE: staff_branch_assignments
-- =============================================================================

-- SELECT: only assignments for branches you are allowed to work in
CREATE POLICY staff_branch_assignments_select ON public.staff_branch_assignments
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      branch_id = ANY (public.jwt_branch_ids())
      OR (
        public.jwt_setup_required()
        AND staff_member_id = public.jwt_staff_member_id()
      )
    )
  );

CREATE POLICY staff_branch_assignments_insert ON public.staff_branch_assignments
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

-- =============================================================================
-- TABLE: roles_permissions
-- =============================================================================

-- Read-only permission matrix: only granted, non-deleted rows (for UI permission checks)
CREATE POLICY roles_permissions_select ON public.roles_permissions
  FOR SELECT
  TO authenticated
  USING (is_deleted = false AND is_granted = true);

-- =============================================================================
-- TABLE: audit_log
-- =============================================================================

-- See your own actions OR audit rows for your organization
CREATE POLICY audit_log_select ON public.audit_log
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      organization_id IS NOT NULL
      AND organization_id = public.jwt_organization_id()
    )
  );

-- =============================================================================
-- TABLE: app_settings
-- =============================================================================

-- Org-scoped settings: org-wide (branch_id NULL) or branch rows you are assigned to
CREATE POLICY app_settings_select ON public.app_settings
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.jwt_organization_id()
    AND (
      branch_id IS NULL
      OR branch_id = ANY (public.jwt_branch_ids())
    )
  );

CREATE POLICY app_settings_insert ON public.app_settings
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

-- =============================================================================
-- TABLE: subscription_cache
-- =============================================================================

CREATE POLICY subscription_cache_select ON public.subscription_cache
  FOR SELECT
  TO authenticated
  USING (organization_id = public.jwt_organization_id());
