-- P1.2 tenant scoping (roles_permissions and beyond). Sequencing steps 8+.

-- -----------------------------------------------------------------------------
-- Sequencing step 8 (T008): per-tenant roles_permissions key
-- -----------------------------------------------------------------------------

ALTER TABLE public.roles_permissions
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

ALTER TABLE public.roles_permissions
  DROP CONSTRAINT IF EXISTS roles_permissions_role_permission_key_key;

-- -----------------------------------------------------------------------------
-- Sequencing step 9 (T009): default matrix per organisation; remove unscoped rows
-- -----------------------------------------------------------------------------

CREATE TABLE auth_internal.roles_permissions_default_template (
  role public.staff_role NOT NULL,
  permission_key text NOT NULL,
  is_granted boolean NOT NULL,
  PRIMARY KEY (role, permission_key)
);

ALTER TABLE auth_internal.roles_permissions_default_template ENABLE ROW LEVEL SECURITY;

CREATE POLICY roles_permissions_default_template_deny_all
  ON auth_internal.roles_permissions_default_template
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE auth_internal.roles_permissions_default_template
  FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO auth_internal.roles_permissions_default_template (role, permission_key, is_granted)
SELECT rp.role, rp.permission_key, rp.is_granted
FROM public.roles_permissions rp
WHERE rp.organization_id IS NULL
  AND rp.is_deleted = false;

INSERT INTO public.roles_permissions (
  organization_id,
  role,
  permission_key,
  is_granted,
  created_at,
  created_by,
  updated_at,
  updated_by,
  is_deleted,
  deleted_at,
  deleted_by
)
SELECT
  o.id,
  t.role,
  t.permission_key,
  t.is_granted,
  now(),
  NULL,
  NULL,
  NULL,
  false,
  NULL,
  NULL
FROM public.organizations o
CROSS JOIN auth_internal.roles_permissions_default_template t
WHERE o.is_deleted = false;

DELETE FROM public.roles_permissions
WHERE organization_id IS NULL;

ALTER TABLE public.roles_permissions
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.roles_permissions
  ADD CONSTRAINT roles_permissions_organization_id_role_permission_key_key
  UNIQUE (organization_id, role, permission_key);

-- -----------------------------------------------------------------------------
-- Sequencing step 10 (T010): seed default matrix for new organisations
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.seed_roles_permissions_defaults(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_organization_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.roles_permissions (organization_id, role, permission_key, is_granted)
  SELECT p_organization_id, t.role, t.permission_key, t.is_granted
  FROM auth_internal.roles_permissions_default_template t
  ON CONFLICT (organization_id, role, permission_key) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.seed_roles_permissions_defaults(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION auth_internal.trg_seed_roles_permissions_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.seed_roles_permissions_defaults(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS seed_roles_permissions_defaults ON public.organizations;
CREATE TRIGGER seed_roles_permissions_defaults
  AFTER INSERT ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_seed_roles_permissions_defaults();

-- -----------------------------------------------------------------------------
-- Sequencing step 11 (T011): per-tenant roles_permissions SELECT policy
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS roles_permissions_select ON public.roles_permissions;

CREATE POLICY roles_permissions_select ON public.roles_permissions
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.current_org_id()
    AND (
      is_granted = true
      OR public.current_membership_role() = 'administrator'
    )
  );

-- -----------------------------------------------------------------------------
-- Sequencing step 12 (T012): per-tenant single-row role permission update
-- -----------------------------------------------------------------------------

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
  v_org uuid;
  v_old boolean := false;
  v_row public.roles_permissions%ROWTYPE;
  v_key text := trim(p_permission_key);
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();
  v_org := public.current_org_id();

  IF v_org IS NULL THEN
    RETURN public.rpc_success(
      jsonb_build_object(
        'role', p_role::text,
        'permission_key', v_key,
        'is_granted', p_is_granted
      )
    );
  END IF;

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
    WHERE rp.organization_id = v_org
      AND rp.permission_key = v_key
      AND rp.is_deleted = false
  ) THEN
    RETURN public.rpc_error('INVALID_PERMISSION', 'Permission key is not in the catalog.');
  END IF;

  SELECT rp.is_granted
  INTO v_old
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org
    AND rp.role = p_role
    AND rp.permission_key = v_key
    AND rp.is_deleted = false;

  IF NOT FOUND THEN
    v_old := false;
  END IF;

  INSERT INTO public.roles_permissions (
    organization_id,
    role,
    permission_key,
    is_granted,
    updated_by
  )
  VALUES (v_org, p_role, v_key, p_is_granted, auth.uid())
  ON CONFLICT (organization_id, role, permission_key) DO UPDATE
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

-- -----------------------------------------------------------------------------
-- Sequencing step 13 (T013): per-tenant bulk role permission update
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_role_permissions(p_changes jsonb)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_org uuid;
  v_change jsonb;
  v_role public.staff_role;
  v_key text;
  v_is_granted boolean;
  v_old boolean;
  v_row public.roles_permissions%ROWTYPE;
  v_applied jsonb := '[]'::jsonb;
BEGIN
  v_caller := auth_internal.assert_owner_or_administrator();
  v_org := public.current_org_id();

  IF v_org IS NULL THEN
    RETURN public.rpc_success(jsonb_build_object('applied', v_applied));
  END IF;

  IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'array' OR jsonb_array_length(p_changes) = 0 THEN
    RETURN public.rpc_success(jsonb_build_object('applied', v_applied));
  END IF;

  FOR v_change IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
    v_role := (v_change ->> 'role')::public.staff_role;
    v_key := trim(v_change ->> 'permission_key');
    v_is_granted := (v_change ->> 'is_granted')::boolean;

    IF NULLIF(v_key, '') IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Permission key is required.');
    END IF;

    IF v_key = 'settings.billing.manage'
       AND v_is_granted = true
       AND v_role <> 'administrator' THEN
      RETURN public.rpc_error(
        'PERMISSION_NOT_DELEGABLE',
        'settings.billing.manage cannot be granted to this role.'
      );
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      WHERE rp.organization_id = v_org
        AND rp.permission_key = v_key
        AND rp.is_deleted = false
    ) THEN
      RETURN public.rpc_error('INVALID_PERMISSION', 'Permission key is not in the catalog.');
    END IF;

    SELECT rp.is_granted
    INTO v_old
    FROM public.roles_permissions rp
    WHERE rp.organization_id = v_org
      AND rp.role = v_role
      AND rp.permission_key = v_key
      AND rp.is_deleted = false;

    IF NOT FOUND THEN
      v_old := false;
    END IF;

    INSERT INTO public.roles_permissions (
      organization_id,
      role,
      permission_key,
      is_granted,
      updated_by
    )
    VALUES (v_org, v_role, v_key, v_is_granted, auth.uid())
    ON CONFLICT (organization_id, role, permission_key) DO UPDATE
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
      jsonb_build_object('role', v_role::text, 'permission_key', v_key, 'is_granted', v_old),
      jsonb_build_object('role', v_role::text, 'permission_key', v_key, 'is_granted', v_is_granted)
    );

    v_applied := v_applied || jsonb_build_array(
      jsonb_build_object('role', v_role::text, 'permission_key', v_key, 'is_granted', v_is_granted)
    );
  END LOOP;

  RETURN public.rpc_success(jsonb_build_object('applied', v_applied));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update role permissions.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- Sequencing step 14 (T014): org-scoped AI token issuance ledger
-- -----------------------------------------------------------------------------

ALTER TABLE ai_internal.ai_token_issuance
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE ai_internal.ai_token_issuance i
SET organization_id = earliest.organization_id
FROM public.staff_members sm
JOIN LATERAL (
  SELECT m.organization_id
  FROM ai_internal.membership m
  WHERE m.user_id = sm.auth_user_id
  ORDER BY m.created_at ASC, m.organization_id ASC
  LIMIT 1
) earliest ON true
WHERE i.actor_staff_id = sm.id
  AND i.is_deleted = false;

ALTER TABLE ai_internal.ai_token_issuance
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS ai_token_issuance_deny_all ON ai_internal.ai_token_issuance;

CREATE POLICY ai_token_issuance_select ON ai_internal.ai_token_issuance
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND organization_id = public.current_org_id()
  );

-- The SELECT policy is the live read. Writes stay closed (no insert/update/delete grant).
GRANT USAGE ON SCHEMA ai_internal TO authenticated;
GRANT SELECT ON TABLE ai_internal.ai_token_issuance TO authenticated;

-- -----------------------------------------------------------------------------
-- Sequencing step 15 (T015): issue_ai_token writes organization_id and org claim
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.issue_ai_token(p_scopes text[] DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, auth_internal
AS $$
DECLARE
  v_uid uuid;
  v_claims jsonb;
  v_org uuid;
  v_staff public.staff_members%ROWTYPE;
  v_branch_id uuid;
  v_installation_id uuid;
  v_signing_key ai_internal.installation_keys%ROWTYPE;
  v_scopes jsonb;
  v_jti uuid;
  v_iat bigint;
  v_exp bigint;
  v_lifetime_minutes numeric;
  v_rate_ceiling int;
  v_rate_window_seconds int;
  v_recent_mints int;
  v_header_text text;
  v_payload_text text;
  v_header_b64 text;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_token text;
BEGIN
  v_uid := auth_internal.assert_valid_ai_session();

  v_claims := auth_internal.build_staff_claims(v_uid);
  IF v_claims = '{}'::jsonb
     OR NULLIF(v_claims ->> 'staff_member_id', '') IS NULL THEN
    RAISE EXCEPTION 'STAFF_NOT_FOUND';
  END IF;

  -- Prefer the session org. A session that only sets `sub` still has the
  -- staff organisation on the claims object the pre-P1.2 issuer used.
  v_org := COALESCE(
    public.current_org_id(),
    NULLIF(v_claims ->> 'organization_id', '')::uuid
  );

  SELECT sm.*
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.id = (v_claims ->> 'staff_member_id')::uuid
    AND sm.is_deleted = false
    AND sm.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'STAFF_NOT_FOUND';
  END IF;

  SELECT b.id
  INTO v_branch_id
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  WHERE sba.staff_member_id = v_staff.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.is_active = true
  ORDER BY sba.is_primary DESC, b.name
  LIMIT 1;

  IF v_branch_id IS NULL THEN
    RAISE EXCEPTION 'BRANCH_NOT_FOUND';
  END IF;

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
  ORDER BY ik.valid_from ASC, ik.kid ASC
  LIMIT 1;

  IF v_installation_id IS NULL THEN
    RAISE EXCEPTION 'INSTALLATION_NOT_ENROLLED';
  END IF;

  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.installation_keys ik
  WHERE ik.installation_id = v_installation_id
    AND ik.is_deleted = false
    AND ik.revoked_at IS NULL
  ORDER BY ik.valid_from DESC, ik.kid DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INSTALLATION_NOT_ENROLLED';
  END IF;

  v_lifetime_minutes := auth_internal.ai_app_setting_numeric('ai.aat.lifetime_minutes', 10);
  v_rate_ceiling := auth_internal.ai_app_setting_numeric('ai.issuer.rate_limit.ceiling', 100)::int;
  v_rate_window_seconds := auth_internal.ai_app_setting_numeric(
    'ai.issuer.rate_limit.window_seconds',
    3600
  )::int;

  -- Serialize per-actor mint counting against the ledger insert (§4.2 rate limit).
  PERFORM pg_advisory_xact_lock(
    87201401,
    hashtext(v_staff.id::text)
  );

  SELECT count(*)::int
  INTO v_recent_mints
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_staff.id
    AND i.is_deleted = false
    AND i.iat >= now() - make_interval(secs => v_rate_window_seconds);

  IF v_recent_mints >= v_rate_ceiling THEN
    RAISE EXCEPTION 'RATE_LIMITED';
  END IF;

  SELECT coalesce(
    jsonb_agg(rp.permission_key ORDER BY rp.permission_key),
    '[]'::jsonb
  )
  INTO v_scopes
  FROM public.roles_permissions rp
  WHERE rp.role = v_staff.role
    AND rp.permission_key LIKE 'ai.%'
    AND rp.is_granted = true
    AND rp.is_deleted = false;

  IF jsonb_array_length(v_scopes) < 1 THEN
    RAISE EXCEPTION 'AI_ACCESS_DENIED';
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + (v_lifetime_minutes * 60)::bigint;

  v_header_text := jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid
  )::text;

  v_payload_text := jsonb_build_object(
    'iss', v_installation_id::text,
    'aud', auth_internal.ai_app_setting_text('ai.aat.audience', 'ai-platform'),
    'sub', v_staff.id::text,
    'org', v_org::text,
    'branch', v_branch_id::text,
    'role', v_staff.role::text,
    'scopes', v_scopes,
    'jti', v_jti::text,
    'iat', v_iat,
    'exp', v_exp,
    'ver', auth_internal.ai_app_setting_text('ai.aat.ver', '1')
  )::text;

  v_header_b64 := auth_internal.base64url_encode(convert_to(v_header_text, 'utf8'));
  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload_text, 'utf8'));
  v_signing_input := v_header_b64 || '.' || v_payload_b64;

  v_signature := pgsodium.crypto_sign_detached(
    convert_to(v_signing_input, 'utf8'),
    v_signing_key.secret_key
  );

  v_token := v_signing_input || '.' || auth_internal.base64url_encode(v_signature);

  INSERT INTO ai_internal.ai_token_issuance (
    installation_id,
    jti,
    actor_staff_id,
    organization_id,
    iat,
    created_by,
    updated_by
  )
  VALUES (
    v_installation_id,
    v_jti,
    v_staff.id,
    v_org,
    to_timestamp(v_iat),
    v_uid,
    v_uid
  );

  RETURN v_token;
END;
$$;

-- -----------------------------------------------------------------------------
-- Sequencing step 16 (T016): issue_ai_token scopes from per-tenant roles_permissions
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.issue_ai_token(p_scopes text[] DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, auth_internal
AS $$
DECLARE
  v_uid uuid;
  v_claims jsonb;
  v_org uuid;
  v_staff public.staff_members%ROWTYPE;
  v_branch_id uuid;
  v_installation_id uuid;
  v_signing_key ai_internal.installation_keys%ROWTYPE;
  v_scopes jsonb;
  v_jti uuid;
  v_iat bigint;
  v_exp bigint;
  v_lifetime_minutes numeric;
  v_rate_ceiling int;
  v_rate_window_seconds int;
  v_recent_mints int;
  v_header_text text;
  v_payload_text text;
  v_header_b64 text;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_token text;
BEGIN
  v_uid := auth_internal.assert_valid_ai_session();

  v_claims := auth_internal.build_staff_claims(v_uid);
  IF v_claims = '{}'::jsonb
     OR NULLIF(v_claims ->> 'staff_member_id', '') IS NULL THEN
    RAISE EXCEPTION 'STAFF_NOT_FOUND';
  END IF;

  -- Prefer the session org. A session that only sets `sub` still has the
  -- staff organisation on the claims object the pre-P1.2 issuer used.
  v_org := COALESCE(
    public.current_org_id(),
    NULLIF(v_claims ->> 'organization_id', '')::uuid
  );

  SELECT sm.*
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.id = (v_claims ->> 'staff_member_id')::uuid
    AND sm.is_deleted = false
    AND sm.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'STAFF_NOT_FOUND';
  END IF;

  SELECT b.id
  INTO v_branch_id
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  WHERE sba.staff_member_id = v_staff.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.is_active = true
  ORDER BY sba.is_primary DESC, b.name
  LIMIT 1;

  IF v_branch_id IS NULL THEN
    RAISE EXCEPTION 'BRANCH_NOT_FOUND';
  END IF;

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
  ORDER BY ik.valid_from ASC, ik.kid ASC
  LIMIT 1;

  IF v_installation_id IS NULL THEN
    RAISE EXCEPTION 'INSTALLATION_NOT_ENROLLED';
  END IF;

  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.installation_keys ik
  WHERE ik.installation_id = v_installation_id
    AND ik.is_deleted = false
    AND ik.revoked_at IS NULL
  ORDER BY ik.valid_from DESC, ik.kid DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INSTALLATION_NOT_ENROLLED';
  END IF;

  v_lifetime_minutes := auth_internal.ai_app_setting_numeric('ai.aat.lifetime_minutes', 10);
  v_rate_ceiling := auth_internal.ai_app_setting_numeric('ai.issuer.rate_limit.ceiling', 100)::int;
  v_rate_window_seconds := auth_internal.ai_app_setting_numeric(
    'ai.issuer.rate_limit.window_seconds',
    3600
  )::int;

  -- Serialize per-actor mint counting against the ledger insert (§4.2 rate limit).
  PERFORM pg_advisory_xact_lock(
    87201401,
    hashtext(v_staff.id::text)
  );

  SELECT count(*)::int
  INTO v_recent_mints
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_staff.id
    AND i.is_deleted = false
    AND i.iat >= now() - make_interval(secs => v_rate_window_seconds);

  IF v_recent_mints >= v_rate_ceiling THEN
    RAISE EXCEPTION 'RATE_LIMITED';
  END IF;

  SELECT coalesce(
    jsonb_agg(rp.permission_key ORDER BY rp.permission_key),
    '[]'::jsonb
  )
  INTO v_scopes
  FROM public.roles_permissions rp
  WHERE rp.organization_id = v_org
    AND rp.role = COALESCE(public.current_membership_role(), v_staff.role)
    AND rp.permission_key LIKE 'ai.%'
    AND rp.is_granted = true
    AND rp.is_deleted = false;

  IF jsonb_array_length(v_scopes) < 1 THEN
    RAISE EXCEPTION 'AI_ACCESS_DENIED';
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + (v_lifetime_minutes * 60)::bigint;

  v_header_text := jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid
  )::text;

  v_payload_text := jsonb_build_object(
    'iss', v_installation_id::text,
    'aud', auth_internal.ai_app_setting_text('ai.aat.audience', 'ai-platform'),
    'sub', v_staff.id::text,
    'org', v_org::text,
    'branch', v_branch_id::text,
    'role', COALESCE(public.current_membership_role(), v_staff.role)::text,
    'scopes', v_scopes,
    'jti', v_jti::text,
    'iat', v_iat,
    'exp', v_exp,
    'ver', auth_internal.ai_app_setting_text('ai.aat.ver', '1')
  )::text;

  v_header_b64 := auth_internal.base64url_encode(convert_to(v_header_text, 'utf8'));
  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload_text, 'utf8'));
  v_signing_input := v_header_b64 || '.' || v_payload_b64;

  v_signature := pgsodium.crypto_sign_detached(
    convert_to(v_signing_input, 'utf8'),
    v_signing_key.secret_key
  );

  v_token := v_signing_input || '.' || auth_internal.base64url_encode(v_signature);

  INSERT INTO ai_internal.ai_token_issuance (
    installation_id,
    jti,
    actor_staff_id,
    organization_id,
    iat,
    created_by,
    updated_by
  )
  VALUES (
    v_installation_id,
    v_jti,
    v_staff.id,
    v_org,
    to_timestamp(v_iat),
    v_uid,
    v_uid
  );

  RETURN v_token;
END;
$$;

-- -----------------------------------------------------------------------------
-- Sequencing step 17 (T017): staff_members membership predicate
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.user_has_organization_membership(
  p_user_id uuid,
  p_organization_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_user_id IS NOT NULL
    AND p_organization_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM ai_internal.membership m
      WHERE m.user_id = p_user_id
        AND m.organization_id = p_organization_id
    );
$$;

REVOKE ALL ON FUNCTION auth_internal.user_has_organization_membership(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth_internal.user_has_organization_membership(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS staff_members_select ON public.staff_members;

CREATE POLICY staff_members_select ON public.staff_members
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND auth_internal.user_has_organization_membership(
      staff_members.auth_user_id,
      public.current_org_id()
    )
  );

DROP POLICY IF EXISTS staff_members_update ON public.staff_members;

CREATE POLICY staff_members_update ON public.staff_members
  FOR UPDATE
  TO authenticated
  USING (
    is_deleted = false
    AND auth_internal.user_has_organization_membership(
      staff_members.auth_user_id,
      public.current_org_id()
    )
  )
  WITH CHECK (
    is_deleted = false
    AND auth_internal.user_has_organization_membership(
      staff_members.auth_user_id,
      public.current_org_id()
    )
  );

-- -----------------------------------------------------------------------------
-- Sequencing step 18 (T018): staff_branch_assignments membership predicate
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS staff_branch_assignments_select ON public.staff_branch_assignments;

CREATE POLICY staff_branch_assignments_select ON public.staff_branch_assignments
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      (
        public.current_org_id() IS NULL
        AND public.jwt_setup_required()
        AND staff_member_id = public.jwt_staff_member_id()
      )
      OR (
        public.current_org_id() IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.branches b
          WHERE b.id = staff_branch_assignments.branch_id
            AND b.is_deleted = false
            AND b.organization_id = public.current_org_id()
        )
        AND EXISTS (
          SELECT 1
          FROM public.staff_members sm
          WHERE sm.id = staff_branch_assignments.staff_member_id
            AND sm.is_deleted = false
            AND auth_internal.user_has_organization_membership(
              sm.auth_user_id,
              public.current_org_id()
            )
        )
      )
    )
  );

-- -----------------------------------------------------------------------------
-- Sequencing step 19 (T019): public.appointments org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.appointments
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.appointments a
SET organization_id = b.organization_id
FROM public.branches b
WHERE b.id = a.branch_id
  AND a.organization_id IS NULL;

ALTER TABLE public.appointments
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS appointments_org ON public.appointments;

CREATE POLICY appointments_org ON public.appointments
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 20 (T020): public.visits org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.visits
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.visits v
SET organization_id = b.organization_id
FROM public.branches b
WHERE b.id = v.branch_id
  AND v.organization_id IS NULL;

ALTER TABLE public.visits
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS visits_org ON public.visits;

CREATE POLICY visits_org ON public.visits
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 21 (T021): public.visit_clinical_notes org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.visit_clinical_notes
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.visit_clinical_notes vcn
SET organization_id = b.organization_id
FROM public.visits v
JOIN public.branches b ON b.id = v.branch_id
WHERE v.id = vcn.visit_id
  AND vcn.organization_id IS NULL;

ALTER TABLE public.visit_clinical_notes
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS visit_clinical_notes_org ON public.visit_clinical_notes;

CREATE POLICY visit_clinical_notes_org ON public.visit_clinical_notes
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 22 (T022): public.visit_vital_signs org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.visit_vital_signs
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.visit_vital_signs vvs
SET organization_id = b.organization_id
FROM public.visits v
JOIN public.branches b ON b.id = v.branch_id
WHERE v.id = vvs.visit_id
  AND vvs.organization_id IS NULL;

ALTER TABLE public.visit_vital_signs
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS visit_vital_signs_org ON public.visit_vital_signs;

CREATE POLICY visit_vital_signs_org ON public.visit_vital_signs
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 23 (T023): public.visit_investigations org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.visit_investigations
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.visit_investigations vi
SET organization_id = b.organization_id
FROM public.visits v
JOIN public.branches b ON b.id = v.branch_id
WHERE v.id = vi.visit_id
  AND vi.organization_id IS NULL;

ALTER TABLE public.visit_investigations
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS visit_investigations_org ON public.visit_investigations;

CREATE POLICY visit_investigations_org ON public.visit_investigations
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 24 (T024): public.visit_attachments org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.visit_attachments
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.visit_attachments va
SET organization_id = b.organization_id
FROM public.visits v
JOIN public.branches b ON b.id = v.branch_id
WHERE v.id = va.visit_id
  AND va.organization_id IS NULL;

ALTER TABLE public.visit_attachments
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS visit_attachments_org ON public.visit_attachments;

CREATE POLICY visit_attachments_org ON public.visit_attachments
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 25 (T025): public.treatment_plans org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.treatment_plans
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.treatment_plans tp
SET organization_id = b.organization_id
FROM public.visits v
JOIN public.branches b ON b.id = v.branch_id
WHERE v.id = tp.visit_id
  AND tp.organization_id IS NULL;

ALTER TABLE public.treatment_plans
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS treatment_plans_org ON public.treatment_plans;

CREATE POLICY treatment_plans_org ON public.treatment_plans
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 26 (T026): public.invoice_items org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.invoice_items
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.invoice_items ii
SET organization_id = i.organization_id
FROM public.invoices i
WHERE i.id = ii.invoice_id
  AND ii.organization_id IS NULL;

ALTER TABLE public.invoice_items
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS invoice_items_org ON public.invoice_items;

CREATE POLICY invoice_items_org ON public.invoice_items
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 27 (T027): public.payments org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.payments
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.payments p
SET organization_id = i.organization_id
FROM public.invoices i
WHERE i.id = p.invoice_id
  AND p.organization_id IS NULL;

ALTER TABLE public.payments
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS payments_org ON public.payments;

CREATE POLICY payments_org ON public.payments
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 28 (T028): public.invoice_number_sequences org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.invoice_number_sequences
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.invoice_number_sequences ins
SET organization_id = b.organization_id
FROM public.branches b
WHERE b.id = ins.branch_id
  AND ins.organization_id IS NULL;

ALTER TABLE public.invoice_number_sequences
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS invoice_number_sequences_org ON public.invoice_number_sequences;

CREATE POLICY invoice_number_sequences_org ON public.invoice_number_sequences
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 29 (T029): public.patient_allergies org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.patient_allergies
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.patient_allergies pa
SET organization_id = p.organization_id
FROM public.patients p
WHERE p.id = pa.patient_id
  AND pa.organization_id IS NULL;

ALTER TABLE public.patient_allergies
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS patient_allergies_org ON public.patient_allergies;

CREATE POLICY patient_allergies_org ON public.patient_allergies
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 30 (T030): public.patient_medications org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.patient_medications
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.patient_medications pm
SET organization_id = p.organization_id
FROM public.patients p
WHERE p.id = pm.patient_id
  AND pm.organization_id IS NULL;

ALTER TABLE public.patient_medications
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS patient_medications_org ON public.patient_medications;

CREATE POLICY patient_medications_org ON public.patient_medications
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 31 (T031): public.patient_chronic_conditions org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.patient_chronic_conditions
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.patient_chronic_conditions pcc
SET organization_id = p.organization_id
FROM public.patients p
WHERE p.id = pcc.patient_id
  AND pcc.organization_id IS NULL;

ALTER TABLE public.patient_chronic_conditions
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS patient_chronic_conditions_org ON public.patient_chronic_conditions;

CREATE POLICY patient_chronic_conditions_org ON public.patient_chronic_conditions
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 32 (T032): public.service_branches org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.service_branches
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.service_branches sb
SET organization_id = s.organization_id
FROM public.services s
WHERE s.id = sb.service_id
  AND sb.organization_id IS NULL;

ALTER TABLE public.service_branches
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS service_branches_org ON public.service_branches;

CREATE POLICY service_branches_org ON public.service_branches
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 33 (T033): public.shift_assignments org key
-- -----------------------------------------------------------------------------

ALTER TABLE public.shift_assignments
  ADD COLUMN organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE;

UPDATE public.shift_assignments sa
SET organization_id = s.organization_id
FROM public.shifts s
WHERE s.id = sa.shift_id
  AND sa.organization_id IS NULL;

ALTER TABLE public.shift_assignments
  ALTER COLUMN organization_id SET NOT NULL;

DROP POLICY IF EXISTS shift_assignments_org ON public.shift_assignments;

CREATE POLICY shift_assignments_org ON public.shift_assignments
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 34 (T034): public.invoices restrictive org policy
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS invoices_org ON public.invoices;

CREATE POLICY invoices_org ON public.invoices
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (organization_id = public.current_org_id());

-- -----------------------------------------------------------------------------
-- Sequencing step 35 (T035): shared BEFORE INSERT organization_id fill
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.trg_fill_tenant_organization_id()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_org uuid;
  v_session_org uuid;
BEGIN
  v_session_org := public.current_org_id();

  CASE TG_TABLE_NAME
    WHEN 'appointments' THEN
      SELECT b.organization_id
      INTO v_parent_org
      FROM public.branches b
      WHERE b.id = NEW.branch_id;
    WHEN 'visits' THEN
      SELECT b.organization_id
      INTO v_parent_org
      FROM public.branches b
      WHERE b.id = NEW.branch_id;
    WHEN 'visit_clinical_notes',
         'visit_vital_signs',
         'visit_investigations',
         'visit_attachments',
         'treatment_plans' THEN
      SELECT b.organization_id
      INTO v_parent_org
      FROM public.visits v
      JOIN public.branches b ON b.id = v.branch_id
      WHERE v.id = NEW.visit_id;
    WHEN 'invoice_items' THEN
      SELECT i.organization_id
      INTO v_parent_org
      FROM public.invoices i
      WHERE i.id = NEW.invoice_id;
    WHEN 'payments' THEN
      SELECT i.organization_id
      INTO v_parent_org
      FROM public.invoices i
      WHERE i.id = NEW.invoice_id;
    WHEN 'invoice_number_sequences' THEN
      SELECT b.organization_id
      INTO v_parent_org
      FROM public.branches b
      WHERE b.id = NEW.branch_id;
    WHEN 'patient_allergies',
         'patient_medications',
         'patient_chronic_conditions' THEN
      SELECT p.organization_id
      INTO v_parent_org
      FROM public.patients p
      WHERE p.id = NEW.patient_id;
    WHEN 'service_branches' THEN
      SELECT s.organization_id
      INTO v_parent_org
      FROM public.services s
      WHERE s.id = NEW.service_id;
    WHEN 'shift_assignments' THEN
      SELECT s.organization_id
      INTO v_parent_org
      FROM public.shifts s
      WHERE s.id = NEW.shift_id;
    ELSE
      RAISE EXCEPTION 'unsupported tenant table %', TG_TABLE_NAME;
  END CASE;

  IF v_parent_org IS NULL THEN
    RAISE EXCEPTION 'tenant parent organization not found';
  END IF;

  IF v_session_org IS NOT NULL AND v_parent_org IS DISTINCT FROM v_session_org THEN
    RAISE EXCEPTION 'tenant_organization_mismatch';
  END IF;

  IF NEW.organization_id IS NULL THEN
    NEW.organization_id := v_parent_org;
  ELSIF NEW.organization_id IS DISTINCT FROM v_parent_org THEN
    RAISE EXCEPTION 'tenant_organization_mismatch';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.appointments;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.visits;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.visits
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.visit_clinical_notes;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.visit_clinical_notes
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.visit_vital_signs;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.visit_vital_signs
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.visit_investigations;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.visit_investigations
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.visit_attachments;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.visit_attachments
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.treatment_plans;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.treatment_plans
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.invoice_items;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.invoice_items
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.payments;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.invoice_number_sequences;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.invoice_number_sequences
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.patient_allergies;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.patient_allergies
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.patient_medications;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.patient_medications
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.patient_chronic_conditions;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.patient_chronic_conditions
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.service_branches;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.service_branches
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

DROP TRIGGER IF EXISTS fill_tenant_organization_id ON public.shift_assignments;
CREATE TRIGGER fill_tenant_organization_id
  BEFORE INSERT ON public.shift_assignments
  FOR EACH ROW
  EXECUTE FUNCTION auth_internal.trg_fill_tenant_organization_id();

-- -----------------------------------------------------------------------------
-- Sequencing step 36 (T036): definer row lookups keyed on current_org_id()
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_appointment(p_appointment_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_created_by_display text;
BEGIN
  PERFORM auth_internal.assert_appointment_access();

  IF p_appointment_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Appointment id is required.');
  END IF;

  SELECT
    a.id,
    a.branch_id,
    a.patient_id,
    p.full_name AS patient_name,
    a.doctor_id,
    sm.full_name AS doctor_name,
    a.start_time,
    a.end_time,
    a.type::text AS type,
    a.status::text AS status,
    a.queue_number,
    a.notes,
    a.cancel_reason,
    a.created_at,
    a.updated_at,
    a.created_by
  INTO v_row
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  LEFT JOIN public.staff_members sm ON sm.id = a.doctor_id
  WHERE a.id = p_appointment_id
    AND a.is_deleted = false
    AND a.organization_id = public.current_org_id()
    AND a.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  SELECT sm.full_name
  INTO v_created_by_display
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_row.created_by
    AND sm.is_deleted = false
  LIMIT 1;

  RETURN public.rpc_success(
    jsonb_build_object(
      'id', v_row.id,
      'branch_id', v_row.branch_id,
      'patient_id', v_row.patient_id,
      'patient_name', v_row.patient_name,
      'doctor_id', v_row.doctor_id,
      'doctor_name', v_row.doctor_name,
      'start_time', v_row.start_time,
      'end_time', v_row.end_time,
      'type', v_row.type,
      'status', v_row.status,
      'queue_number', v_row.queue_number,
      'notes', v_row.notes,
      'cancel_reason', v_row.cancel_reason,
      'created_at', v_row.created_at,
      'updated_at', v_row.updated_at,
      'created_by_display', v_created_by_display
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view appointments.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.get_visit_by_appointment(p_appointment_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.appointments a
    WHERE a.id = p_appointment_id
      AND a.is_deleted = false
      AND a.organization_id = public.current_org_id()
      AND a.branch_id = ANY (public.jwt_branch_ids())
  ) THEN
    RETURN public.rpc_error('NOT_FOUND', 'Appointment was not found.');
  END IF;

  SELECT *
  INTO v_visit
  FROM public.visits v
  WHERE v.appointment_id = p_appointment_id
    AND v.is_deleted = false
    AND v.organization_id = public.current_org_id();

  IF NOT FOUND THEN
    RETURN public.rpc_success(
      jsonb_build_object(
        'visit_id', NULL,
        'status', NULL
      )
    );
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'visit_id', v_visit.id,
      'status', v_visit.status::text
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.assert_invoice_branch_scope(p_invoice_id uuid)
RETURNS public.invoices
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
BEGIN
  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false
    AND i.organization_id = public.current_org_id()
    AND i.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  RETURN v_invoice;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.lock_draft_invoice(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
BEGIN
  IF p_expected_updated_at IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT';
  END IF;

  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false
    AND i.organization_id = public.current_org_id()
    AND i.branch_id = ANY (public.jwt_branch_ids())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  PERFORM auth_internal.assert_invoice_in_draft(v_invoice);

  IF v_invoice.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'STALE_INVOICE';
  END IF;

  RETURN v_invoice;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.lock_payable_invoice(p_invoice_id uuid)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
BEGIN
  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false
    AND i.organization_id = public.current_org_id()
    AND i.branch_id = ANY (public.jwt_branch_ids())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  IF v_invoice.status = 'voided' THEN
    RAISE EXCEPTION 'invoice_voided';
  END IF;

  IF v_invoice.status NOT IN ('issued', 'partially_paid') THEN
    RAISE EXCEPTION 'invoice_not_payable';
  END IF;

  RETURN v_invoice;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.list_invoices(
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items jsonb;
  v_branch_ids uuid[];
  v_statuses text[];
  v_patient_id uuid;
  v_visit_id uuid;
  v_patient_search text;
  v_patient_search_pattern text;
  v_invoice_number text;
  v_invoice_number_pattern text;
  v_date_from timestamptz;
  v_date_to timestamptz;
  v_limit int := greatest(coalesce(p_limit, 50), 1);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_fetch_limit int;
  v_has_more boolean := false;
  v_item_count int;
BEGIN
  PERFORM auth_internal.assert_permission('invoices.view');

  IF p_filters ? 'branch_ids' AND jsonb_typeof(p_filters -> 'branch_ids') = 'array' THEN
    SELECT COALESCE(array_agg(value::uuid), ARRAY[]::uuid[])
    INTO v_branch_ids
    FROM jsonb_array_elements_text(p_filters -> 'branch_ids') AS value;
  END IF;

  IF p_filters ? 'statuses' AND jsonb_typeof(p_filters -> 'statuses') = 'array' THEN
    SELECT COALESCE(array_agg(value), ARRAY[]::text[])
    INTO v_statuses
    FROM jsonb_array_elements_text(p_filters -> 'statuses') AS value;
  END IF;

  IF p_filters ? 'patient_id' THEN
    v_patient_id := nullif(trim(p_filters ->> 'patient_id'), '')::uuid;
  END IF;

  IF p_filters ? 'visit_id' THEN
    v_visit_id := nullif(trim(p_filters ->> 'visit_id'), '')::uuid;
  END IF;

  v_patient_search := nullif(trim(p_filters ->> 'patient_search'), '');
  v_invoice_number := nullif(trim(p_filters ->> 'invoice_number'), '');

  IF v_patient_search IS NOT NULL THEN
    v_patient_search_pattern :=
      replace(replace(replace(v_patient_search, '\', '\\'), '%', '\%'), '_', '\_');
  END IF;

  IF v_invoice_number IS NOT NULL THEN
    v_invoice_number_pattern :=
      replace(replace(replace(v_invoice_number, '\', '\\'), '%', '\%'), '_', '\_');
  END IF;

  IF p_filters ? 'date_from' THEN
    v_date_from := nullif(trim(p_filters ->> 'date_from'), '')::timestamptz;
  END IF;

  IF p_filters ? 'date_to' THEN
    v_date_to := nullif(trim(p_filters ->> 'date_to'), '')::timestamptz;
  END IF;

  v_fetch_limit := v_limit + 1;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sub.id,
        'invoice_number', sub.invoice_number,
        'status', sub.status,
        'patient_display_name', sub.patient_display_name,
        'patient_mrn', sub.patient_mrn,
        'branch_code', sub.branch_code,
        'subtotal', sub.subtotal,
        'discount_amount', sub.discount_amount,
        'insurance_covered_amount', sub.insurance_covered_amount,
        'paid_amount', sub.paid_amount,
        'balance', sub.balance,
        'currency', sub.currency,
        'created_at', sub.created_at,
        'issued_at', sub.issued_at,
        'payments', sub.payments
      )
      ORDER BY sub.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      i.id,
      i.invoice_number,
      i.status::text AS status,
      p.full_name AS patient_display_name,
      p.mrn AS patient_mrn,
      b.code AS branch_code,
      i.subtotal,
      i.discount_amount,
      i.insurance_covered_amount,
      COALESCE(pay.paid_amount, 0)::numeric(14, 2) AS paid_amount,
      auth_internal.compute_invoice_balance(i.id) AS balance,
      i.currency,
      i.created_at,
      i.issued_at,
      COALESCE(pay_lines.payments, '[]'::jsonb) AS payments
    FROM public.invoices i
    JOIN public.patients p ON p.id = i.patient_id
    JOIN public.branches b ON b.id = i.branch_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(sum(pm.amount), 0) AS paid_amount
      FROM public.payments pm
      WHERE pm.invoice_id = i.id
    ) pay ON true
    LEFT JOIN LATERAL (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', pm.id,
            'method', pm.method,
            'amount', pm.amount,
            'note', pm.note,
            'recorded_by', jsonb_build_object(
              'id', pm.recorded_by,
              'display_name', sm.full_name
            ),
            'recorded_at', pm.recorded_at
          )
          ORDER BY pm.recorded_at
        ),
        '[]'::jsonb
      ) AS payments
      FROM public.payments pm
      LEFT JOIN public.staff_members sm ON sm.id = pm.recorded_by
      WHERE pm.invoice_id = i.id
    ) pay_lines ON true
    WHERE i.is_deleted = false
      AND i.organization_id = public.current_org_id()
      AND i.branch_id = ANY (public.jwt_branch_ids())
      AND (
        v_branch_ids IS NULL
        OR cardinality(v_branch_ids) = 0
        OR i.branch_id = ANY (v_branch_ids)
      )
      AND (
        v_statuses IS NULL
        OR cardinality(v_statuses) = 0
        OR i.status::text = ANY (v_statuses)
      )
      AND (v_patient_id IS NULL OR i.patient_id = v_patient_id)
      AND (v_visit_id IS NULL OR i.visit_id = v_visit_id)
      AND (
        v_patient_search IS NULL
        OR p.full_name ILIKE '%' || v_patient_search_pattern || '%' ESCAPE '\'
        OR upper(p.mrn) LIKE '%' || upper(v_patient_search_pattern) || '%' ESCAPE '\'
        OR i.invoice_number ILIKE '%' || v_patient_search_pattern || '%' ESCAPE '\'
      )
      AND (
        v_invoice_number IS NULL
        OR i.invoice_number = v_invoice_number
        OR i.invoice_number ILIKE v_invoice_number_pattern || '%' ESCAPE '\'
      )
      AND (v_date_from IS NULL OR i.created_at >= v_date_from)
      AND (v_date_to IS NULL OR i.created_at <= v_date_to)
    ORDER BY i.created_at DESC
    LIMIT v_fetch_limit
    OFFSET v_offset
  ) sub;

  v_item_count := COALESCE(jsonb_array_length(v_items), 0);
  IF v_item_count > v_limit THEN
    v_has_more := true;
    SELECT COALESCE(jsonb_agg(elem ORDER BY ord), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT elem, ord
      FROM jsonb_array_elements(v_items) WITH ORDINALITY AS t(elem, ord)
      WHERE ord <= v_limit
    ) trimmed;
  END IF;

  RETURN public.rpc_success(jsonb_build_object('items', v_items, 'has_more', v_has_more));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list invoices.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.list_patient_invoices(
  p_patient_id uuid,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_patient_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'patient_id is required.');
  END IF;

  RETURN auth_internal.list_invoices(
    jsonb_build_object('patient_id', p_patient_id::text),
    p_limit,
    p_offset
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list invoices.');
    END IF;
    RAISE;
END;
$$;

-- Scope JWT branch_ids to the active organisation (FR-007, E2E-P1.2-04).
-- Claims may still list every assignment; callers use jwt_branch_ids() for guards.

CREATE OR REPLACE FUNCTION public.jwt_branch_ids()
RETURNS uuid[]
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT array_agg(sub.bid ORDER BY sub.ord)
      FROM (
        SELECT t.bid, t.ord
        FROM unnest(
          COALESCE(
            string_to_array(NULLIF(public.request_jwt_claims() ->> 'branch_ids', ''), ',')::uuid[],
            ARRAY[]::uuid[]
          )
        ) WITH ORDINALITY AS t(bid, ord)
        JOIN public.branches b ON b.id = t.bid
        WHERE b.is_deleted = false
          AND (
            public.current_org_id() IS NULL
            OR b.organization_id = public.current_org_id()
          )
      ) sub
    ),
    ARRAY[]::uuid[]
  );
$$;

-- Cross-tenant E2E: permission matrix is per organisation (FR-005, FR-006).
CREATE OR REPLACE FUNCTION auth_internal.assert_permission(p_permission_key text)
RETURNS public.staff_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org uuid;
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

  IF v_staff.is_bootstrap_admin AND NOT auth_internal.organization_exists() THEN
    RETURN v_staff;
  END IF;

  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0003';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    WHERE rp.organization_id = v_org
      AND rp.role = v_staff.role
      AND rp.permission_key = p_permission_key
      AND rp.is_granted = true
      AND rp.is_deleted = false
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'P0003';
  END IF;

  RETURN v_staff;
END;
$$;

-- A branch outside the session stays INVALID_BRANCH, the code this helper
-- already raised before tenant scoping.
CREATE OR REPLACE FUNCTION auth_internal.assert_appointment_branch(p_branch_id uuid)
RETURNS public.branches
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_branch public.branches%ROWTYPE;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF p_branch_id IS NULL OR NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RAISE EXCEPTION 'INVALID_BRANCH';
  END IF;

  SELECT *
  INTO v_branch
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.organization_id = v_org_id
    AND b.is_deleted = false
    AND b.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_BRANCH';
  END IF;

  RETURN v_branch;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.get_appointment_settings(p_branch_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_default int;
  v_schedule jsonb;
BEGIN
  PERFORM auth_internal.assert_appointment_access();
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);

  SELECT b.working_schedule
  INTO v_schedule
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.is_deleted = false;

  v_default := auth_internal.resolve_appointment_default_duration(p_branch_id);

  RETURN public.rpc_success(
    jsonb_build_object(
      'default_duration_minutes', v_default,
      'min_duration_minutes', 5,
      'working_schedule', v_schedule
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('FORBIDDEN', 'INVALID_BRANCH') THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view appointment settings.');
      END IF;
      RETURN public.rpc_error('INVALID_BRANCH', 'Branch is not valid for this session.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_login_usernames(p_staff_ids uuid[])
RETURNS TABLE (staff_member_id uuid, username text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  BEGIN
    PERFORM auth_internal.assert_permission('settings.manage_staff');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE = 'P0003' OR SQLERRM = 'FORBIDDEN' THEN
        RETURN;
      END IF;
      RAISE;
  END;

  RETURN QUERY
  SELECT sm.id, lower(trim(u.email::text))
  FROM public.staff_members sm
  JOIN auth.users u ON u.id = sm.auth_user_id
  WHERE sm.is_deleted = false
    AND sm.id = ANY (p_staff_ids)
    AND (
      sm.auth_user_id = (SELECT auth.uid())
      OR EXISTS (
        SELECT 1
        FROM public.staff_branch_assignments sba
        JOIN public.branches b ON b.id = sba.branch_id
        WHERE sba.staff_member_id = sm.id
          AND sba.is_deleted = false
          AND b.is_deleted = false
          AND b.organization_id = public.jwt_organization_id()
      )
    );
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.staff_has_visit_clinical_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.current_staff_member_row() sm
    JOIN public.roles_permissions rp ON rp.role = sm.role
    WHERE rp.organization_id = public.current_org_id()
      AND rp.permission_key IN ('visits.create', 'visits.edit_soap')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.staff_has_visit_upload_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.current_staff_member_row() sm
    JOIN public.roles_permissions rp ON rp.role = sm.role
    WHERE rp.organization_id = public.current_org_id()
      AND rp.permission_key IN ('visits.upload_attachment', 'visits.create', 'visits.edit_soap')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );
$$;

CREATE OR REPLACE FUNCTION auth_internal.create_appointment(
  p_branch_id uuid,
  p_patient_id uuid,
  p_doctor_id uuid,
  p_type text,
  p_start_time timestamptz DEFAULT NULL,
  p_duration_minutes int DEFAULT NULL,
  p_end_time timestamptz DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_patient public.patients%ROWTYPE;
  v_type public.appointment_type;
  v_status public.appointment_status;
  v_duration int;
  v_start timestamptz;
  v_end timestamptz;
  v_appointment_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('appointments.create');
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);

  IF p_doctor_id IS NOT NULL THEN
    PERFORM auth_internal.assert_appointment_doctor(p_doctor_id, p_branch_id);
  END IF;

  BEGIN
    v_patient := auth_internal.assert_org_patient(p_patient_id, false);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      IF SQLERRM = 'PATIENT_ARCHIVED' THEN
        RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived.');
      END IF;
      RAISE;
  END;

  IF p_notes IS NOT NULL AND length(trim(p_notes)) > 2000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Notes must be 2000 characters or fewer.');
  END IF;

  BEGIN
    v_type := lower(trim(p_type))::public.appointment_type;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Type must be planned.');
  END;

  IF v_type <> 'planned' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Type must be planned.');
  END IF;

  v_duration := COALESCE(p_duration_minutes, auth_internal.resolve_appointment_default_duration(p_branch_id));

  BEGIN
    PERFORM auth_internal.assert_appointment_duration_bounds(v_duration);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Duration must be between 5 and 240 minutes.');
  END;

  IF p_start_time IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Start time is required.');
  END IF;

  SELECT rt.resolved_start, rt.resolved_end
  INTO v_start, v_end
  FROM auth_internal.resolve_appointment_times(p_start_time, v_duration, p_end_time) rt;

  IF NOT auth_internal.appointment_within_branch_working_hours(p_branch_id, v_start, v_end) THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Appointment must be within branch working hours.');
  END IF;

  IF auth_internal.appointment_has_overlap(p_branch_id, p_doctor_id, v_start, v_end, NULL) THEN
    RETURN public.rpc_error('SCHEDULE_CONFLICT', 'This time slot overlaps another appointment.');
  END IF;

  v_status := 'scheduled';

  IF auth_internal.patient_has_same_day_appointment(p_branch_id, p_patient_id, v_start, NULL) THEN
    RETURN public.rpc_error(
      'PATIENT_ALREADY_BOOKED_SAME_DAY',
      'This patient already has an appointment on the same day.'
    );
  END IF;

  INSERT INTO public.appointments (
    branch_id,
    patient_id,
    doctor_id,
    start_time,
    end_time,
    type,
    status,
    queue_number,
    notes,
    created_by,
    updated_by
  )
  VALUES (
    p_branch_id,
    p_patient_id,
    p_doctor_id,
    v_start,
    v_end,
    v_type,
    v_status,
    NULL,
    NULLIF(trim(COALESCE(p_notes, '')), ''),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_appointment_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    public.jwt_organization_id(),
    'appointment.create',
    'appointments',
    v_appointment_id,
    jsonb_build_object(
      'appointment_id', v_appointment_id,
      'branch_id', p_branch_id,
      'patient_id', p_patient_id,
      'doctor_id', p_doctor_id,
      'start_time', v_start,
      'end_time', v_end,
      'type', v_type::text,
      'status', v_status::text
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'appointment_id', v_appointment_id,
      'start_time', v_start,
      'end_time', v_end,
      'status', v_status::text,
      'type', v_type::text
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create appointments.');
    END IF;
    IF SQLERRM = 'INVALID_DOCTOR' THEN
      RETURN public.rpc_error('INVALID_DOCTOR', 'Doctor is not valid for this branch.');
    END IF;
    IF SQLERRM IN ('INVALID_BRANCH', 'NOT_FOUND') THEN
      RETURN public.rpc_error('NOT_FOUND', 'Branch was not found.');
    END IF;
    RAISE;
END;
$$;
