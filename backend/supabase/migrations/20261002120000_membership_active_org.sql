-- Membership (user, organisation, role) and the staff backfill (FR-001, FR-002).

CREATE TABLE ai_internal.membership (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  role public.staff_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, organization_id)
);

ALTER TABLE ai_internal.membership ENABLE ROW LEVEL SECURITY;

CREATE POLICY membership_deny_all ON ai_internal.membership
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.membership FROM PUBLIC, anon, authenticated, service_role;

-- One row per non-deleted staff member, for the earliest non-deleted
-- organisation (the organisation auth_internal.build_staff_claims takes).
-- is_active does not exclude a row. No non-deleted organisation yields no rows,
-- so the bootstrap administrator on a fresh database gets no membership.
INSERT INTO ai_internal.membership (user_id, organization_id, role, created_at)
SELECT
  sm.auth_user_id,
  earliest.id,
  sm.role,
  sm.created_at
FROM public.staff_members sm
CROSS JOIN (
  SELECT o.id
  FROM public.organizations o
  WHERE o.is_deleted = false
  ORDER BY o.created_at
  LIMIT 1
) earliest
WHERE sm.is_deleted = false;

-- Active organisation for the session (FR-003, FR-004, FR-005, FR-006, FR-008).

CREATE TABLE ai_internal.user_active_organization (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE ai_internal.user_active_organization ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_active_organization_deny_all ON ai_internal.user_active_organization
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.user_active_organization FROM PUBLIC, anon, authenticated, service_role;

-- Keeps the stored organisation while that membership is live. Otherwise
-- takes the first live membership by (created_at, organization_id), or
-- deletes the row when the user has none. Returns the organisation the
-- hook should write as active_org, or NULL when the claim must be absent.
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

-- Hook stays SECURITY INVOKER. build_staff_claims still supplies organization_id.
-- active_org comes from sync_active_organization, which reads the stored row.
CREATE OR REPLACE FUNCTION public.get_custom_claims(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
DECLARE
  v_user_id uuid;
  v_claims jsonb;
  v_custom jsonb;
  v_active_org uuid;
BEGIN
  v_user_id := (event ->> 'user_id')::uuid;
  v_claims := COALESCE(event -> 'claims', '{}'::jsonb);
  v_custom := auth_internal.build_staff_claims(v_user_id);
  v_active_org := auth_internal.sync_active_organization(v_user_id);
  v_claims := v_claims || v_custom;
  IF v_active_org IS NULL THEN
    v_claims := v_claims - 'active_org';
  ELSE
    v_claims := v_claims || jsonb_build_object('active_org', v_active_org::text);
  END IF;
  RETURN jsonb_build_object('claims', v_claims);
END;
$$;

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

CREATE OR REPLACE FUNCTION public.jwt_organization_id()
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.current_org_id();
$$;

CREATE OR REPLACE FUNCTION public.current_membership_role()
RETURNS public.staff_role
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claims jsonb;
  v_sub_text text;
  v_sub uuid;
  v_org uuid;
  v_role public.staff_role;
BEGIN
  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RETURN NULL;
  END IF;

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

  SELECT m.role
  INTO v_role
  FROM ai_internal.membership m
  WHERE m.user_id = v_sub
    AND m.organization_id = v_org;

  RETURN v_role;
END;
$$;

REVOKE ALL ON FUNCTION public.current_membership_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_membership_role() TO authenticated;
