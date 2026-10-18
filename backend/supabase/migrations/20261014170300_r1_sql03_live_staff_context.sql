-- =============================================================================
-- R1-SQL-03 (P1): Deactivated/deleted staff retain tenant membership on
-- backend reads.
--
-- Final deactivate (20260611170000_restore_last_administrator_guard.sql) and
-- delete (20260614100000_settings_code_review_fixes.sql) never alter
-- membership, and current_org_id()/current_membership_role()
-- (20261002120000_membership_active_org.sql) read membership only. A staff
-- member deactivated or soft-deleted while their session is live could keep
-- reading clinic records until the JWT expired.
--
-- Forward override of the session-context functions with a live-staff
-- predicate (non-deleted AND active staff_members row for the JWT sub):
--   1. public.current_org_id() requires live staff in addition to its
--      existing membership check, so every consumer (patient/appointment
--      RLS, billing status reads, current_membership_role) fails closed
--      immediately after disable/delete. Bootstrap-only setup paths are
--      preserved: on a fresh database the bootstrap administrator has no
--      membership and current_org_id() already returned NULL; the bootstrap
--      RPCs (auth_internal.bootstrap_create_organization / _branch) authorize
--      through assert_bootstrap_admin() and do not depend on current_org_id().
--   2. auth_internal.sync_active_organization() returns NULL immediately for
--      a non-live staff member — no tenant context and no fallback selection
--      of another tenant; membership and active-preference rows are preserved
--      for audit/authorized reactivation.
--   3. public.set_active_organization() returns forbidden without a write for
--      a non-live staff member.
--
-- Membership and active-preference rows are never hard-deleted: the common
-- predicate makes every retained association ineffective while
-- staff_members.is_active = false OR is_deleted = true. The final staff
-- update/deactivate/delete RPCs and their last-administrator guards are
-- unchanged; their status transactions now revoke effective authority through
-- this shared predicate.
-- No org fallback is restored for a removed member.
-- Forward-only migration; never edit an applied migration file.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. current_org_id(): live-staff predicate added to the membership check.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_org_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claims jsonb;
  v_sub_text text;
  v_org_text text;
  v_sub uuid;
  v_org uuid;
BEGIN
  v_claims := public.request_jwt_claims();
  v_sub_text := v_claims ->> 'sub';

  BEGIN
    IF v_sub_text IS NULL OR btrim(v_sub_text) = '' THEN
      RETURN NULL;
    END IF;
    v_sub := v_sub_text::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN NULL;
  END;

  -- active_org when that claim is present and non-empty; otherwise the
  -- legacy organization_id claim. Empty or non-uuid yields NULL.
  IF v_claims ? 'active_org' THEN
    v_org_text := NULLIF(btrim(v_claims ->> 'active_org'), '');
    IF v_org_text IS NULL THEN
      RETURN NULL;
    END IF;
  ELSE
    v_org_text := NULLIF(btrim(v_claims ->> 'organization_id'), '');
    IF v_org_text IS NULL THEN
      RETURN NULL;
    END IF;
  END IF;

  BEGIN
    v_org := v_org_text::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN NULL;
  END;

  -- R1-SQL-03: the JWT subject must still be a live (non-deleted, active)
  -- staff member. A deactivated or soft-deleted staff member gets no tenant
  -- context, so every downstream org-scoped read and current_membership_role
  -- fails closed immediately.
  IF NOT EXISTS (
    SELECT 1
    FROM public.staff_members sm
    WHERE sm.auth_user_id = v_sub
      AND sm.is_deleted = false
      AND sm.is_active = true
  ) THEN
    RETURN NULL;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM ai_internal.membership m
    WHERE m.user_id = v_sub
      AND m.organization_id = v_org
  ) THEN
    RETURN v_org;
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.current_org_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_org_id() TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. sync_active_organization(): live-staff guard before any selection.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.sync_active_organization(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stored uuid;
  v_first uuid;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- R1-SQL-03: a deactivated or soft-deleted staff member neither receives
  -- nor selects tenant context. Return NULL immediately without selecting
  -- another tenant; the stored active-preference row is left untouched so an
  -- authorized reactivation resumes it.
  IF NOT EXISTS (
    SELECT 1
    FROM public.staff_members sm
    WHERE sm.auth_user_id = p_user_id
      AND sm.is_deleted = false
      AND sm.is_active = true
  ) THEN
    RETURN NULL;
  END IF;

  SELECT u.organization_id
  INTO v_stored
  FROM ai_internal.user_active_organization u
  WHERE u.user_id = p_user_id;

  IF v_stored IS NOT NULL AND EXISTS (
    SELECT 1
    FROM ai_internal.membership m
    WHERE m.user_id = p_user_id
      AND m.organization_id = v_stored
  ) THEN
    RETURN v_stored;
  END IF;

  SELECT m.organization_id
  INTO v_first
  FROM ai_internal.membership m
  WHERE m.user_id = p_user_id
  ORDER BY m.created_at, m.organization_id
  LIMIT 1;

  IF v_first IS NULL THEN
    DELETE FROM ai_internal.user_active_organization
    WHERE user_id = p_user_id;
    RETURN NULL;
  END IF;

  INSERT INTO ai_internal.user_active_organization (user_id, organization_id, updated_at)
  VALUES (p_user_id, v_first, now())
  ON CONFLICT (user_id) DO UPDATE
    SET organization_id = EXCLUDED.organization_id,
        updated_at = now();

  RETURN v_first;
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.sync_active_organization(uuid) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    GRANT EXECUTE ON FUNCTION auth_internal.sync_active_organization(uuid) TO supabase_auth_admin;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. set_active_organization(): live-staff guard, forbidden without a write.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_active_organization(p_organization_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw_sub text;
  v_sub uuid;
BEGIN
  v_raw_sub := public.request_jwt_claims() ->> 'sub';

  BEGIN
    IF v_raw_sub IS NULL OR btrim(v_raw_sub) = '' THEN
      v_sub := NULL;
    ELSE
      v_sub := v_raw_sub::uuid;
    END IF;
  EXCEPTION
    WHEN invalid_text_representation THEN
      v_sub := NULL;
  END;

  IF v_sub IS NULL
    OR p_organization_id IS NULL
    OR NOT EXISTS (
      -- R1-SQL-03: a disabled user neither receives nor selects tenant
      -- context; return forbidden without writing the preference row.
      SELECT 1
      FROM public.staff_members sm
      WHERE sm.auth_user_id = v_sub
        AND sm.is_deleted = false
        AND sm.is_active = true
    )
    OR NOT EXISTS (
      SELECT 1
      FROM ai_internal.membership m
      WHERE m.user_id = v_sub
        AND m.organization_id = p_organization_id
    )
  THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'You do not have a membership in that organisation.'
    );
  END IF;

  INSERT INTO ai_internal.user_active_organization (user_id, organization_id, updated_at)
  VALUES (v_sub, p_organization_id, now())
  ON CONFLICT (user_id) DO UPDATE
    SET organization_id = EXCLUDED.organization_id,
        updated_at = now();

  RETURN public.rpc_success(jsonb_build_object('organization_id', p_organization_id));
END;
$$;

REVOKE ALL ON FUNCTION public.set_active_organization(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_active_organization(uuid) TO authenticated;