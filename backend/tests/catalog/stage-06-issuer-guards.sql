-- Stage 06 catalog SQL: S06-001 … S06-016 (issuer session/staff/branch/keystore/rate guards).
-- Run via backend/tests/catalog/run.sh (do not execute from a stage-writer task).
--
-- CONFLICT: catalog B0 / S06-019 seed lifetime_minutes=15 (900s); code seed=10 via
--   20260905120000_fix_aat_lifetime_minutes_seed.sql. This chunk does not assert 900s.
-- CONFLICT: catalog aliases (ORG/DOC/K0/`d2000000-…`/`a1000000-…099`) are documentation
--   only (Register 5 #14); ids are captured from bootstrap/enroll/gen_random_uuid().
-- CONFLICT: catalog B0 usernames nadia.h/lina.k/rami.s contain '.' ;
--   code auth_internal.assert_valid_username allows [a-z0-9_-] only
--   (20260521190000). Using nadia_h/lina_k/rami_s so bootstrap can succeed.
-- CONFLICT: S06-006 catalog names delete_staff_member alone; code returns STAFF_STILL_ACTIVE
--   unless the member is deactivated first (20260614100000). Production path used here:
--   set_staff_active(false) then delete_staff_member.

BEGIN;

\ir harness.sql

-- -----------------------------------------------------------------------------
-- Stage 06 helpers (not harness). Personas differ from Stage 02.
-- -----------------------------------------------------------------------------

CREATE TEMP TABLE catalog_s06_ids (
  key text PRIMARY KEY,
  value text NOT NULL
);

CREATE OR REPLACE FUNCTION pg_temp.capture_issue_error(
  OUT p_sqlstate text,
  OUT p_message text
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_token text;
BEGIN
  BEGIN
    v_token := public.issue_ai_token();
    p_sqlstate := NULL;
    p_message := '<none>';
  EXCEPTION
    WHEN undefined_function THEN
      RAISE;
    WHEN OTHERS THEN
      p_sqlstate := SQLSTATE;
      p_message := SQLERRM;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_staff_mgmt_session(
  p_auth_id uuid,
  p_staff_id uuid,
  p_org_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Staff-management RPCs read jwt_organization_id() / jwt_staff_member_id().
  PERFORM pg_temp.set_authenticated_session(p_auth_id);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_auth_id::text,
      'role', 'authenticated',
      'organization_id', p_org_id::text,
      'staff_member_id', p_staff_id::text
    )::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.is_compact_jws(p_token text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_token IS NOT NULL
    AND p_token <> ''
    AND array_length(string_to_array(p_token, '.'), 1) = 3
    AND split_part(p_token, '.', 1) <> ''
    AND split_part(p_token, '.', 2) <> ''
    AND split_part(p_token, '.', 3) <> '';
$$;

CREATE OR REPLACE FUNCTION pg_temp.issuance_count(p_staff uuid DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_count int;
BEGIN
  PERFORM pg_temp.reset_postgres();
  IF p_staff IS NULL THEN
    SELECT count(*)::int INTO v_count
    FROM ai_internal.ai_token_issuance i
    WHERE i.is_deleted = false;
  ELSE
    SELECT count(*)::int INTO v_count
    FROM ai_internal.ai_token_issuance i
    WHERE i.is_deleted = false
      AND i.actor_staff_id = p_staff;
  END IF;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.insert_bare_auth_user(p_username text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_id uuid := gen_random_uuid();
BEGIN
  -- Mirror auth_internal.create_auth_user minus the staff_members insert.
  PERFORM pg_temp.reset_postgres();
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    p_username,
    extensions.crypt('Cl1nic!pass', extensions.gen_salt('bf')),
    now(),
    '',
    '',
    '',
    '',
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    '{}'::jsonb,
    now(),
    now()
  );

  INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', p_username),
    'email',
    p_username,
    now(),
    now(),
    now()
  );

  RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.stage06_working_schedule()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT '{
    "days": [
      {"day":"monday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"tuesday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"wednesday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"thursday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"friday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"saturday","is_working_day":true,"open_time":"09:00","close_time":"17:00"},
      {"day":"sunday","is_working_day":false}
    ]
  }'::jsonb;
$$;

CREATE OR REPLACE FUNCTION pg_temp.stage06_isolate()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_boot_auth uuid := 'a0000000-0000-4000-8000-000000000001';
  v_boot_staff uuid := 'b0000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM pg_temp.reset_postgres();
  PERFORM set_config('app.environment', 'development', true);

  -- Issuance ledger FKs staff_members; clear keystore before clinic teardown.
  PERFORM pg_temp.reset_keystore();

  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_boot_staff]::uuid[]);

  DELETE FROM auth.identities
  WHERE provider = 'email'
    AND provider_id IN (
      'nadia_karim', 'omar_haddad',
      'nadia.h', 'lina.k', 'rami.s', 'nadia.r',
      'nadia_h', 'lina_k', 'rami_s',
      'ghost.user', 's06008doc'
    );
  DELETE FROM auth.users
  WHERE lower(email) IN (
    'nadia_karim', 'omar_haddad',
    'nadia.h', 'lina.k', 'rami.s', 'nadia.r',
    'nadia_h', 'lina_k', 'rami_s',
    'ghost.user', 's06008doc'
  );

  DELETE FROM catalog_setup;
  INSERT INTO catalog_setup (key, value) VALUES
    ('boot', v_boot_staff),
    ('boot_auth', v_boot_auth);

  DELETE FROM catalog_s06_ids;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.stage06_bootstrap()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_boot_auth uuid;
  v_boot_staff uuid;
  v_result public.rpc_result;
  v_org uuid;
  v_branch uuid;
  v_doc uuid;
  v_adm uuid;
  v_rec uuid;
  v_doc_auth uuid;
  v_adm_auth uuid;
  v_rec_auth uuid;
  v_doc_name text;
  v_adm_name text;
  v_rec_name text;
  v_doc_role public.staff_role;
  v_adm_role public.staff_role;
  v_rec_role public.staff_role;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';
  SELECT value INTO STRICT v_boot_staff FROM catalog_setup WHERE key = 'boot';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);

  -- 12-arg wrapper (required working_schedule) so the call is not ambiguous
  -- against the leftover 11-arg public overlay.
  v_result := public.bootstrap_finish_setup(
    'Sunrise Dental Clinic'::text,
    'Main Branch'::text,
    -- CONFLICT: catalog B0 usernames nadia.h/lina.k/rami.s ; code regex [a-z0-9_-]
    '[{"username":"nadia_h","password":"Cl1nic!pass","full_name":"Nadia Haddad","role":"doctor"},{"username":"lina_k","password":"Cl1nic!pass","full_name":"Lina Khoury","role":"administrator"},{"username":"rami_s","password":"Cl1nic!pass","full_name":"Rami Saleh","role":"receptionist"}]'::jsonb,
    '{}'::jsonb,
    NULL::text,
    'EGP'::text,
    'Africa/Cairo'::text,
    'MAIN'::text,
    '12 Nile St, Cairo'::text,
    '+201000000010'::text,
    NULL::text,
    pg_temp.stage06_working_schedule()
  );

  IF NOT v_result.success THEN
    RAISE EXCEPTION 'stage06_bootstrap bootstrap_finish_setup failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  v_org := (v_result.data ->> 'organization_id')::uuid;
  v_branch := (v_result.data ->> 'branch_id')::uuid;
  v_doc := (v_result.data -> 'staff_member_ids' ->> 0)::uuid;
  v_adm := (v_result.data -> 'staff_member_ids' ->> 1)::uuid;
  v_rec := (v_result.data -> 'staff_member_ids' ->> 2)::uuid;

  PERFORM pg_temp.reset_postgres();

  SELECT sm.auth_user_id, sm.full_name, sm.role
  INTO STRICT v_doc_auth, v_doc_name, v_doc_role
  FROM public.staff_members sm
  WHERE sm.id = v_doc;

  SELECT sm.auth_user_id, sm.full_name, sm.role
  INTO STRICT v_adm_auth, v_adm_name, v_adm_role
  FROM public.staff_members sm
  WHERE sm.id = v_adm;

  SELECT sm.auth_user_id, sm.full_name, sm.role
  INTO STRICT v_rec_auth, v_rec_name, v_rec_role
  FROM public.staff_members sm
  WHERE sm.id = v_rec;

  IF v_doc_name IS DISTINCT FROM 'Nadia Haddad' OR v_doc_role IS DISTINCT FROM 'doctor' THEN
    RAISE EXCEPTION 'stage06_bootstrap doctor mismatch: % / %', v_doc_name, v_doc_role;
  END IF;
  IF v_adm_name IS DISTINCT FROM 'Lina Khoury' OR v_adm_role IS DISTINCT FROM 'administrator' THEN
    RAISE EXCEPTION 'stage06_bootstrap admin mismatch: % / %', v_adm_name, v_adm_role;
  END IF;
  IF v_rec_name IS DISTINCT FROM 'Rami Saleh' OR v_rec_role IS DISTINCT FROM 'receptionist' THEN
    RAISE EXCEPTION 'stage06_bootstrap receptionist mismatch: % / %', v_rec_name, v_rec_role;
  END IF;

  DELETE FROM catalog_setup;
  INSERT INTO catalog_setup (key, value) VALUES
    ('org', v_org),
    ('branch', v_branch),
    ('doctor', v_doc),
    ('admin', v_adm),
    ('receptionist', v_rec),
    ('doctor_auth', v_doc_auth),
    ('admin_auth', v_adm_auth),
    ('receptionist_auth', v_rec_auth),
    ('boot', v_boot_staff),
    ('boot_auth', v_boot_auth);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.stage06_enroll()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_boot_auth uuid;
  v_result public.rpc_result;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.enroll_installation_keypair();
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'stage06_enroll enroll_installation_keypair failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  -- catalog_s06_ids is postgres-owned; authenticated cannot INSERT.
  PERFORM pg_temp.reset_postgres();
  DELETE FROM catalog_s06_ids WHERE key IN ('kid', 'installation_id');
  INSERT INTO catalog_s06_ids (key, value) VALUES
    ('kid', v_result.data ->> 'kid'),
    ('installation_id', v_result.data ->> 'installation_id');
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.stage06_b0()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.stage06_isolate();
  PERFORM pg_temp.stage06_bootstrap();
  PERFORM pg_temp.stage06_enroll();
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.stage06_restore_rate_defaults()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.app_settings
  SET value_json = '100'::jsonb
  WHERE key = 'ai.issuer.rate_limit.ceiling';
  UPDATE ai_internal.app_settings
  SET value_json = '3600'::jsonb
  WHERE key = 'ai.issuer.rate_limit.window_seconds';
END;
$$;

-- Baseline B0. S06-007 is isolated in catalog order (tear down clinic, enroll as
-- BOOT, then rebuild B0 so later IDs still have a doctor + keystore).
-- Record a bootstrap failure instead of a bare ON_ERROR_STOP abort, then re-raise:
-- later IDs need B0 ids (username fix should make this succeed).
DO $$
BEGIN
  PERFORM pg_temp.stage06_b0();
EXCEPTION
  WHEN OTHERS THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'B0 — baseline bootstrap and enroll',
      false,
      SQLERRM
    );
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-001 — Anonymous role cannot execute the issuer at all
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.set_anon_session();
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = '42501'
    AND COALESCE(v_message, '') ILIKE '%issue_ai_token%'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-001 — Anonymous role cannot execute the issuer at all',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-002 — Authenticated role without JWT claims is UNAUTHENTICATED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = 'P0001'
    AND v_message = 'UNAUTHENTICATED'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-002 — Authenticated role without JWT claims is UNAUTHENTICATED',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-003 — Expired clinic session JWT is SESSION_EXPIRED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_authenticated_session(
    v_doc_auth,
    (extract(epoch from now())::bigint - 60)
  );
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = 'P0001'
    AND v_message = 'SESSION_EXPIRED'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-003 — Expired clinic session JWT is SESSION_EXPIRED',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-004 — Auth user with no staff row is STAFF_NOT_FOUND
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_ghost uuid;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  -- Do not insert catalog alias a1000000-…099 (Register 5 #14).
  v_ghost := pg_temp.insert_bare_auth_user('ghost.user');

  PERFORM pg_temp.set_authenticated_session(v_ghost);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = 'P0001'
    AND v_message = 'STAFF_NOT_FOUND'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-004 — Auth user with no staff row is STAFF_NOT_FOUND',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-005 — Deactivated staff member is STAFF_NOT_FOUND
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_adm uuid;
  v_adm_auth uuid;
  v_doc uuid;
  v_doc_auth uuid;
  v_setup public.rpc_result;
  v_restore public.rpc_result;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_doc_active boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_adm FROM catalog_setup WHERE key = 'admin';
  SELECT value INTO STRICT v_adm_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO STRICT v_doc FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_staff_mgmt_session(v_adm_auth, v_adm, v_org);
  v_setup := public.set_staff_active(v_doc, false);
  IF NOT v_setup.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-005 — Deactivated staff member is STAFF_NOT_FOUND',
      false,
      'set_staff_active(false) failed: '
        || COALESCE(v_setup.error_code, '<null>')
        || ' — ' || COALESCE(v_setup.error_message, '')
    );
    RETURN;
  END IF;

  PERFORM pg_temp.reset_postgres();
  SELECT sm.is_active INTO STRICT v_doc_active
  FROM public.staff_members sm
  WHERE sm.id = v_doc;

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_doc_active IS FALSE
    AND v_sqlstate = 'P0001'
    AND v_message = 'STAFF_NOT_FOUND'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' active=' || COALESCE(v_doc_active::text, '<null>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-005 — Deactivated staff member is STAFF_NOT_FOUND',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.set_staff_mgmt_session(v_adm_auth, v_adm, v_org);
  v_restore := public.set_staff_active(v_doc, true);
  PERFORM pg_temp.reset_postgres();
  IF NOT v_restore.success THEN
    -- S06-007 rebuilds B0. Do not abort remaining IDs on restore failure.
    NULL;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-006 — Soft-deleted staff member is STAFF_NOT_FOUND
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_adm uuid;
  v_adm_auth uuid;
  v_doc uuid;
  v_doc_auth uuid;
  v_deactivate public.rpc_result;
  v_delete public.rpc_result;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_deleted boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_adm FROM catalog_setup WHERE key = 'admin';
  SELECT value INTO STRICT v_adm_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO STRICT v_doc FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.set_staff_mgmt_session(v_adm_auth, v_adm, v_org);
  v_deactivate := public.set_staff_active(v_doc, false);
  IF NOT v_deactivate.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-006 — Soft-deleted staff member is STAFF_NOT_FOUND',
      false,
      'set_staff_active(false) failed: '
        || COALESCE(v_deactivate.error_code, '<null>')
        || ' — ' || COALESCE(v_deactivate.error_message, '')
    );
    RETURN;
  END IF;

  v_delete := public.delete_staff_member(v_doc);
  IF NOT v_delete.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-006 — Soft-deleted staff member is STAFF_NOT_FOUND',
      false,
      'delete_staff_member failed: '
        || COALESCE(v_delete.error_code, '<null>')
        || ' — ' || COALESCE(v_delete.error_message, '')
    );
    RETURN;
  END IF;

  PERFORM pg_temp.reset_postgres();
  SELECT sm.is_deleted INTO STRICT v_deleted
  FROM public.staff_members sm
  WHERE sm.id = v_doc;

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_deleted IS TRUE
    AND v_sqlstate = 'P0001'
    AND v_message = 'STAFF_NOT_FOUND'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' deleted=' || COALESCE(v_deleted::text, '<null>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-006 — Soft-deleted staff member is STAFF_NOT_FOUND',
    v_ok,
    v_detail
  );

  -- Soft-deleted DOC is not restored here. S06-007 isolates and rebuilds B0
  -- so later IDs still have an active doctor.
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-007 — Bootstrap admin before clinic setup is BRANCH_NOT_FOUND
-- Isolated: no organization/branches. Enroll as BOOT, mint, then rebuild B0.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  PERFORM pg_temp.stage06_isolate();
  PERFORM pg_temp.stage06_enroll();

  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = 'P0001'
    AND v_message = 'BRANCH_NOT_FOUND'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-007 — Bootstrap admin before clinic setup is BRANCH_NOT_FOUND',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.stage06_b0();
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-008 — Staff with no branch assignment is BRANCH_NOT_FOUND
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_auth uuid;
  v_staff uuid;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_boot_auth FROM catalog_setup WHERE key = 'boot_auth';

  v_auth := pg_temp.insert_bare_auth_user('s06008doc');

  PERFORM pg_temp.reset_postgres();
  INSERT INTO public.staff_members (
    auth_user_id,
    full_name,
    role,
    is_bootstrap_admin,
    is_active,
    created_by,
    updated_by
  )
  VALUES (
    v_auth,
    'Throwaway No Branch',
    'doctor',
    false,
    true,
    v_boot_auth,
    v_boot_auth
  )
  RETURNING id INTO v_staff;

  PERFORM pg_temp.set_authenticated_session(v_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = 'P0001'
    AND v_message = 'BRANCH_NOT_FOUND'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text
    || ' staff=' || v_staff::text;

  PERFORM pg_temp.record(
    'S06-008 — Staff with no branch assignment is BRANCH_NOT_FOUND',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-009 — Staff whose only branch is inactive is BRANCH_NOT_FOUND
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_branch uuid;
  v_doc_auth uuid;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_branch FROM catalog_setup WHERE key = 'branch';
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.reset_postgres();
  UPDATE public.branches SET is_active = false WHERE id = v_branch;

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = 'P0001'
    AND v_message = 'BRANCH_NOT_FOUND'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-009 — Staff whose only branch is inactive is BRANCH_NOT_FOUND',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.reset_postgres();
  UPDATE public.branches SET is_active = true WHERE id = v_branch;
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-010 — Mint before any key is enrolled is INSTALLATION_NOT_ENROLLED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_key_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.reset_keystore();
  SELECT count(*)::int INTO v_key_count FROM ai_internal.installation_keys;

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_key_count = 0
    AND v_sqlstate = 'P0001'
    AND v_message = 'INSTALLATION_NOT_ENROLLED'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' keys=' || v_key_count::text
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-010 — Mint before any key is enrolled is INSTALLATION_NOT_ENROLLED',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.stage06_enroll();
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-011 — Mint when the only key is revoked is INSTALLATION_NOT_ENROLLED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_kid text;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';
  SELECT value INTO STRICT v_kid FROM catalog_s06_ids WHERE key = 'kid';

  -- [SEED]: last-active-key guard blocks public.revoke_installation_key on K0.
  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.installation_keys
  SET revoked_at = now()
  WHERE kid = v_kid;

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = 'P0001'
    AND v_message = 'INSTALLATION_NOT_ENROLLED'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-011 — Mint when the only key is revoked is INSTALLATION_NOT_ENROLLED',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.installation_keys
  SET revoked_at = NULL
  WHERE kid = v_kid;
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-012 — Mint when the only key is soft-deleted is INSTALLATION_NOT_ENROLLED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_kid text;
  v_sqlstate text;
  v_message text;
  v_issuance int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';
  SELECT value INTO STRICT v_kid FROM catalog_s06_ids WHERE key = 'kid';

  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.installation_keys
  SET is_deleted = true, deleted_at = now()
  WHERE kid = v_kid;

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_issuance := pg_temp.issuance_count();

  v_ok := v_sqlstate = 'P0001'
    AND v_message = 'INSTALLATION_NOT_ENROLLED'
    AND v_issuance = 0;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' issuance=' || v_issuance::text;

  PERFORM pg_temp.record(
    'S06-012 — Mint when the only key is soft-deleted is INSTALLATION_NOT_ENROLLED',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.installation_keys
  SET is_deleted = false, deleted_at = NULL
  WHERE kid = v_kid;
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-013 — Minting at the per-actor ceiling is RATE_LIMITED (boundary)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc uuid;
  v_doc_auth uuid;
  v_token text;
  v_i int;
  v_sqlstate text;
  v_message text;
  v_before int;
  v_after int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doc FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';

  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.app_settings
  SET value_json = '2'::jsonb
  WHERE key = 'ai.issuer.rate_limit.ceiling';

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  FOR v_i IN 1..2 LOOP
    BEGIN
      v_token := public.issue_ai_token();
    EXCEPTION
      WHEN OTHERS THEN
        PERFORM pg_temp.reset_postgres();
        PERFORM pg_temp.record(
          'S06-013 — Minting at the per-actor ceiling is RATE_LIMITED (boundary)',
          false,
          'setup mint ' || v_i::text || ' raised: ' || SQLSTATE || ' ' || SQLERRM
        );
        RETURN;
    END;
    IF NOT pg_temp.is_compact_jws(v_token) THEN
      PERFORM pg_temp.reset_postgres();
      PERFORM pg_temp.record(
        'S06-013 — Minting at the per-actor ceiling is RATE_LIMITED (boundary)',
        false,
        'setup mint ' || v_i::text || ' did not return a compact JWS'
      );
      RETURN;
    END IF;
  END LOOP;

  v_before := pg_temp.issuance_count(v_doc);

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_after := pg_temp.issuance_count(v_doc);

  v_ok := v_before = 2
    AND v_sqlstate = 'P0001'
    AND v_message = 'RATE_LIMITED'
    AND v_after = 2;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' before=' || v_before::text
    || ' after=' || v_after::text;

  PERFORM pg_temp.record(
    'S06-013 — Minting at the per-actor ceiling is RATE_LIMITED (boundary)',
    v_ok,
    v_detail
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-014 — The rate ceiling is per actor, not per installation
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_adm uuid;
  v_adm_auth uuid;
  v_token text;
  v_payload jsonb;
  v_adm_rows int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_adm FROM catalog_setup WHERE key = 'admin';
  SELECT value INTO STRICT v_adm_auth FROM catalog_setup WHERE key = 'admin_auth';

  PERFORM pg_temp.set_authenticated_session(v_adm_auth);
  BEGIN
    v_token := public.issue_ai_token();
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.reset_postgres();
      PERFORM pg_temp.record(
        'S06-014 — The rate ceiling is per actor, not per installation',
        false,
        'issue_ai_token raised: ' || SQLSTATE || ' ' || SQLERRM
      );
      PERFORM pg_temp.stage06_restore_rate_defaults();
      DELETE FROM ai_internal.ai_token_issuance;
      RETURN;
  END;
  v_payload := pg_temp.decode_jws_payload(v_token);

  v_adm_rows := pg_temp.issuance_count(v_adm);

  v_ok := pg_temp.is_compact_jws(v_token)
    AND (v_payload ->> 'sub') = v_adm::text
    AND v_adm_rows = 1;
  v_detail := 'compact=' || pg_temp.is_compact_jws(v_token)::text
    || ' sub=' || COALESCE(v_payload ->> 'sub', '<null>')
    || ' adm_rows=' || v_adm_rows::text;

  PERFORM pg_temp.record(
    'S06-014 — The rate ceiling is per actor, not per installation',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.stage06_restore_rate_defaults();
  DELETE FROM ai_internal.ai_token_issuance;
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-015 — Mints older than the window do not count
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc uuid;
  v_doc_auth uuid;
  v_token text;
  v_i int;
  v_before int;
  v_after int;
  v_fresh int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_doc FROM catalog_setup WHERE key = 'doctor';
  SELECT value INTO STRICT v_doc_auth FROM catalog_setup WHERE key = 'doctor_auth';

  -- 014 restored ceiling/ledger; re-establish the S06-013 boundary then backdate.
  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.app_settings
  SET value_json = '2'::jsonb
  WHERE key = 'ai.issuer.rate_limit.ceiling';

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  FOR v_i IN 1..2 LOOP
    BEGIN
      v_token := public.issue_ai_token();
    EXCEPTION
      WHEN OTHERS THEN
        PERFORM pg_temp.reset_postgres();
        PERFORM pg_temp.record(
          'S06-015 — Mints older than the window do not count',
          false,
          'setup mint ' || v_i::text || ' raised: ' || SQLSTATE || ' ' || SQLERRM
        );
        RETURN;
    END;
    IF NOT pg_temp.is_compact_jws(v_token) THEN
      PERFORM pg_temp.reset_postgres();
      PERFORM pg_temp.record(
        'S06-015 — Mints older than the window do not count',
        false,
        'setup mint ' || v_i::text || ' did not return a compact JWS'
      );
      RETURN;
    END IF;
  END LOOP;

  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.ai_token_issuance
  SET iat = now() - interval '2 hours'
  WHERE actor_staff_id = v_doc
    AND is_deleted = false;

  v_before := pg_temp.issuance_count(v_doc);

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  BEGIN
    v_token := public.issue_ai_token();
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM pg_temp.reset_postgres();
      PERFORM pg_temp.record(
        'S06-015 — Mints older than the window do not count',
        false,
        'issue_ai_token raised: ' || SQLSTATE || ' ' || SQLERRM
      );
      PERFORM pg_temp.stage06_restore_rate_defaults();
      RETURN;
  END;

  v_after := pg_temp.issuance_count(v_doc);
  SELECT count(*)::int INTO v_fresh
  FROM ai_internal.ai_token_issuance i
  WHERE i.actor_staff_id = v_doc
    AND i.is_deleted = false
    AND i.iat >= now() - interval '1 minute';

  v_ok := v_before = 2
    AND pg_temp.is_compact_jws(v_token)
    AND v_after = 3
    AND v_fresh = 1;
  v_detail := 'compact=' || pg_temp.is_compact_jws(v_token)::text
    || ' before=' || v_before::text
    || ' after=' || v_after::text
    || ' fresh=' || v_fresh::text;

  PERFORM pg_temp.record(
    'S06-015 — Mints older than the window do not count',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.stage06_restore_rate_defaults();
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-016 — Rate check fires before the scope check
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_org uuid;
  v_adm uuid;
  v_adm_auth uuid;
  v_rec uuid;
  v_rec_auth uuid;
  v_token text;
  v_i int;
  v_revoke public.rpc_result;
  v_sqlstate text;
  v_message text;
  v_before int;
  v_after int;
  v_ok boolean;
  v_detail text;
BEGIN
  SELECT value INTO STRICT v_org FROM catalog_setup WHERE key = 'org';
  SELECT value INTO STRICT v_adm FROM catalog_setup WHERE key = 'admin';
  SELECT value INTO STRICT v_adm_auth FROM catalog_setup WHERE key = 'admin_auth';
  SELECT value INTO STRICT v_rec FROM catalog_setup WHERE key = 'receptionist';
  SELECT value INTO STRICT v_rec_auth FROM catalog_setup WHERE key = 'receptionist_auth';

  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.app_settings
  SET value_json = '2'::jsonb
  WHERE key = 'ai.issuer.rate_limit.ceiling';

  UPDATE public.roles_permissions
  SET is_granted = true, updated_at = now()
  WHERE role = 'receptionist'
    AND permission_key = 'ai.access'
    AND is_deleted = false;

  PERFORM pg_temp.set_authenticated_session(v_rec_auth);
  FOR v_i IN 1..2 LOOP
    BEGIN
      v_token := public.issue_ai_token();
    EXCEPTION
      WHEN OTHERS THEN
        PERFORM pg_temp.reset_postgres();
        PERFORM pg_temp.record(
          'S06-016 — Rate check fires before the scope check',
          false,
          'setup mint ' || v_i::text || ' raised: ' || SQLSTATE || ' ' || SQLERRM
        );
        RETURN;
    END;
    IF NOT pg_temp.is_compact_jws(v_token) THEN
      PERFORM pg_temp.reset_postgres();
      PERFORM pg_temp.record(
        'S06-016 — Rate check fires before the scope check',
        false,
        'setup mint ' || v_i::text || ' did not return a compact JWS'
      );
      RETURN;
    END IF;
  END LOOP;

  PERFORM pg_temp.set_staff_mgmt_session(v_adm_auth, v_adm, v_org);
  v_revoke := public.update_role_permission('receptionist', 'ai.access', false);
  IF NOT v_revoke.success THEN
    PERFORM pg_temp.reset_postgres();
    PERFORM pg_temp.record(
      'S06-016 — Rate check fires before the scope check',
      false,
      'update_role_permission(false) failed: '
        || COALESCE(v_revoke.error_code, '<null>')
        || ' — ' || COALESCE(v_revoke.error_message, '')
    );
    RETURN;
  END IF;

  v_before := pg_temp.issuance_count(v_rec);

  PERFORM pg_temp.set_authenticated_session(v_rec_auth);
  SELECT x.p_sqlstate, x.p_message
  INTO v_sqlstate, v_message
  FROM pg_temp.capture_issue_error() AS x;

  v_after := pg_temp.issuance_count(v_rec);

  v_ok := v_before = 2
    AND v_sqlstate = 'P0001'
    AND v_message = 'RATE_LIMITED'
    AND v_message IS DISTINCT FROM 'AI_ACCESS_DENIED'
    AND v_after = 2;
  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' message=' || COALESCE(v_message, '<none>')
    || ' before=' || v_before::text
    || ' after=' || v_after::text;

  PERFORM pg_temp.record(
    'S06-016 — Rate check fires before the scope check',
    v_ok,
    v_detail
  );

  PERFORM pg_temp.stage06_restore_rate_defaults();
  UPDATE public.roles_permissions
  SET is_granted = false, updated_at = now()
  WHERE role = 'receptionist'
    AND permission_key = 'ai.access'
    AND is_deleted = false;
  DELETE FROM ai_internal.ai_token_issuance;
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
