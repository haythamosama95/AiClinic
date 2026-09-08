-- Stage 06 catalog SQL: S06-017 … S06-032 (happy-path mint + key/config lifecycle).
-- Run via backend/tests/catalog/run.sh (do not execute from a stage-writer task).

BEGIN;

\ir harness.sql

-- Stage-local helpers (harness API stays frozen).
CREATE OR REPLACE FUNCTION pg_temp.capture_issue_error()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_token text;
BEGIN
  BEGIN
    v_token := public.issue_ai_token();
    RETURN '<none>';
  EXCEPTION
    WHEN undefined_function THEN
      RAISE;
    WHEN OTHERS THEN
      RETURN SQLERRM;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_staff_session(
  p_user_id uuid,
  p_org_id uuid,
  p_staff_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'organization_id', p_org_id::text,
      'staff_member_id', p_staff_id::text
    )::text,
    true
  );
END;
$$;

CREATE TEMP TABLE catalog_s06_text (
  key text PRIMARY KEY,
  value text NOT NULL
);

-- TEMP tables are postgres-owned; authenticated cannot read or write them.
CREATE OR REPLACE FUNCTION pg_temp.s06_stash_text(p_key text, p_value text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.reset_postgres();
  INSERT INTO catalog_s06_text (key, value)
  VALUES (p_key, p_value)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s06_text(p_key text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_value text;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT t.value INTO v_value FROM catalog_s06_text t WHERE t.key = p_key;
  RETURN v_value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s06_setup(p_key text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_value uuid;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT s.value INTO STRICT v_value FROM catalog_setup s WHERE s.key = p_key;
  RETURN v_value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.s06_stash_setup(p_key text, p_value uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.reset_postgres();
  INSERT INTO catalog_setup (key, value)
  VALUES (p_key, p_value)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.record_caught(p_id text, p_sqlstate text, p_sqlerrm text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pg_temp.reset_postgres();
  PERFORM pg_temp.record(
    p_id,
    false,
    'unexpected sqlstate=' || COALESCE(p_sqlstate, '<none>')
      || ' sqlerrm=' || COALESCE(p_sqlerrm, '<none>')
  );
END;
$$;

-- Full-row fingerprint of user columns only (`t.*`). row::text excludes
-- system columns, so xmax is not part of the hash (ledger INSERT KEY SHARE
-- on staff_members would otherwise false-positive).
CREATE OR REPLACE FUNCTION pg_temp.row_md5(p_rel regclass)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_hash text;
BEGIN
  EXECUTE format(
    $q$SELECT md5(string_agg(r::text, E'\n' ORDER BY r::text))
       FROM (SELECT t.* FROM %s t) r$q$,
    p_rel
  ) INTO v_hash;
  RETURN v_hash;
END;
$$;

-- -----------------------------------------------------------------------------
-- Stage 06 Baseline B0 (Nadia/Lina/Rami personas; do not call catalog_common_setup)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid := 'a0000000-0000-4000-8000-000000000001';
  v_boot_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_doc_id uuid;
  v_adm_id uuid;
  v_rec_id uuid;
  v_doc_auth uuid;
  v_adm_auth uuid;
  v_rec_auth uuid;
  v_k0 text;
  v_i0 uuid;
  v_schedule jsonb := '{
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
BEGIN
  PERFORM pg_temp.reset_postgres();
  PERFORM set_config('app.environment', 'development', true);

  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_boot_staff]::uuid[]);

  -- Mirror harness leftover-identity cleanup for Stage 06 personas.
  -- CONFLICT: catalog B0 usernames nadia.h/lina.k/rami.s contain '.' ;
  -- code auth_internal.assert_valid_username allows [a-z0-9_-] only
  -- (20260521190000). Using nadia_h/lina_k/rami_s so bootstrap can succeed.
  DELETE FROM auth.identities
  WHERE provider = 'email'
    AND provider_id IN ('nadia.h', 'lina.k', 'rami.s', 'nadia_h', 'lina_k', 'rami_s');
  DELETE FROM auth.users
  WHERE lower(email) IN ('nadia.h', 'lina.k', 'rami.s', 'nadia_h', 'lina_k', 'rami_s');

  PERFORM pg_temp.reset_keystore();

  -- CODE B0 defaults (20260905120000 seed 10 min → 600 s). Pin here so a
  -- drifted local row cannot change S06-019/S06-020 lifetime assertions.
  INSERT INTO ai_internal.app_settings (key, value_json)
  VALUES
    ('ai.aat.lifetime_minutes', '10'::jsonb),
    ('ai.aat.audience', '"ai-platform"'::jsonb),
    ('ai.aat.ver', '"1"'::jsonb),
    ('ai.issuer.rate_limit.ceiling', '100'::jsonb),
    ('ai.issuer.rate_limit.window_seconds', '3600'::jsonb)
  ON CONFLICT (key) DO UPDATE
  SET
    value_json = EXCLUDED.value_json,
    is_deleted = false,
    deleted_at = NULL,
    deleted_by = NULL;

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);

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
    v_schedule
  );

  IF NOT v_result.success THEN
    RAISE EXCEPTION 'stage-06 B0 bootstrap_finish_setup failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM pg_temp.reset_postgres();

  -- Look up REAL uuids by full_name+role. Never INSERT catalog alias UUIDs
  -- (Register 5 #14). Catalog aliases DOC/ADM/REC/ORG/BR-A/I0/K0 are docs only.
  SELECT sm.id, sm.auth_user_id
  INTO STRICT v_doc_id, v_doc_auth
  FROM public.staff_members sm
  WHERE sm.full_name = 'Nadia Haddad'
    AND sm.role = 'doctor'
    AND sm.is_deleted = false;

  SELECT sm.id, sm.auth_user_id
  INTO STRICT v_adm_id, v_adm_auth
  FROM public.staff_members sm
  WHERE sm.full_name = 'Lina Khoury'
    AND sm.role = 'administrator'
    AND sm.is_deleted = false;

  SELECT sm.id, sm.auth_user_id
  INTO STRICT v_rec_id, v_rec_auth
  FROM public.staff_members sm
  WHERE sm.full_name = 'Rami Saleh'
    AND sm.role = 'receptionist'
    AND sm.is_deleted = false;

  DELETE FROM catalog_setup;
  INSERT INTO catalog_setup (key, value) VALUES
    ('org', v_org_id),
    ('branch', v_branch_id),
    ('doctor', v_doc_id),
    ('doctor_auth', v_doc_auth),
    ('admin', v_adm_id),
    ('admin_auth', v_adm_auth),
    ('receptionist', v_rec_id),
    ('receptionist_auth', v_rec_auth),
    ('boot', v_boot_staff),
    ('boot_auth', v_boot_auth);

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_result := public.enroll_installation_keypair();
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'stage-06 B0 enroll_installation_keypair failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  v_k0 := v_result.data ->> 'kid';
  v_i0 := (v_result.data ->> 'installation_id')::uuid;

  PERFORM pg_temp.reset_postgres();

  INSERT INTO catalog_setup (key, value) VALUES ('i0', v_i0);
  INSERT INTO catalog_s06_text (key, value) VALUES ('k0', v_k0);
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-017 — Role without any ai.* grant is AI_ACCESS_DENIED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_rec_auth uuid;
  v_sqlstate text;
  v_sqlerrm text;
  v_raised boolean := false;
  v_issuance_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  v_rec_auth := pg_temp.s06_setup('receptionist_auth');

  PERFORM pg_temp.set_authenticated_session(v_rec_auth);

  BEGIN
    PERFORM public.issue_ai_token();
    v_raised := false;
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      v_sqlstate := 'P0001';
      GET STACKED DIAGNOSTICS v_sqlerrm = MESSAGE_TEXT;
      v_raised := true;
    WHEN OTHERS THEN
      v_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_sqlerrm = MESSAGE_TEXT;
      v_raised := true;
  END;

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_issuance_count FROM ai_internal.ai_token_issuance;

  v_ok := v_raised
    AND v_sqlstate = 'P0001'
    AND v_sqlerrm = 'AI_ACCESS_DENIED'
    AND v_issuance_count = 0;

  v_detail := 'sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' sqlerrm=' || COALESCE(v_sqlerrm, '<none>')
    || ' issuance=' || v_issuance_count::text;

  PERFORM pg_temp.record(
    'S06-017 — Role without any ai.* grant is AI_ACCESS_DENIED',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-017 — Role without any ai.* grant is AI_ACCESS_DENIED',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-018 — Role whose ai.* grant was revoked is AI_ACCESS_DENIED
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_adm uuid;
  v_adm_auth uuid;
  v_org uuid;
  v_doc_auth uuid;
  v_setup public.rpc_result;
  v_sqlstate text;
  v_sqlerrm text;
  v_raised boolean := false;
  v_issuance_count int;
  v_ok boolean;
  v_detail text;
BEGIN
  v_adm := pg_temp.s06_setup('admin');
  v_adm_auth := pg_temp.s06_setup('admin_auth');
  v_org := pg_temp.s06_setup('org');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');

  PERFORM pg_temp.set_staff_session(v_adm_auth, v_org, v_adm);
  v_setup := public.update_role_permission('doctor', 'ai.access', false);

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);

  BEGIN
    PERFORM public.issue_ai_token();
    v_raised := false;
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      v_sqlstate := 'P0001';
      GET STACKED DIAGNOSTICS v_sqlerrm = MESSAGE_TEXT;
      v_raised := true;
    WHEN OTHERS THEN
      v_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_sqlerrm = MESSAGE_TEXT;
      v_raised := true;
  END;

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_issuance_count FROM ai_internal.ai_token_issuance;

  v_ok := v_setup.success
    AND v_raised
    AND v_sqlstate = 'P0001'
    AND v_sqlerrm = 'AI_ACCESS_DENIED'
    AND v_issuance_count = 0;

  v_detail := 'setup=' || COALESCE(v_setup.error_code, 'ok')
    || ' sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' sqlerrm=' || COALESCE(v_sqlerrm, '<none>')
    || ' issuance=' || v_issuance_count::text;

  PERFORM pg_temp.record(
    'S06-018 — Role whose ai.* grant was revoked is AI_ACCESS_DENIED',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-018 — Role whose ai.* grant was revoked is AI_ACCESS_DENIED',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

DO $$
DECLARE
  v_adm uuid;
  v_adm_auth uuid;
  v_org uuid;
  v_restore public.rpc_result;
BEGIN
  -- Restore is required setup for later doctor mints; do not swallow failure.
  v_adm := pg_temp.s06_setup('admin');
  v_adm_auth := pg_temp.s06_setup('admin_auth');
  v_org := pg_temp.s06_setup('org');
  PERFORM pg_temp.set_staff_session(v_adm_auth, v_org, v_adm);
  v_restore := public.update_role_permission('doctor', 'ai.access', true);
  PERFORM pg_temp.reset_postgres();
  IF NOT v_restore.success THEN
    RAISE EXCEPTION 'S06-018 restore doctor ai.access failed: % — %',
      COALESCE(v_restore.error_code, '<null>'),
      COALESCE(v_restore.error_message, '');
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-019 — Happy path: doctor mints a fully-populated AAT
-- CONFLICT: S06-019 catalog=exp=iat+900 (seed 15 min) code=seed 10 min → exp-iat=600
--   (20260905120000_fix_aat_lifetime_minutes_seed.sql)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc uuid;
  v_doc_auth uuid;
  v_org uuid;
  v_branch uuid;
  v_i0 uuid;
  v_k0 text;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_header_keys text[];
  v_payload_keys text[];
  v_jti text;
  v_iat bigint;
  v_exp bigint;
  v_now_epoch bigint;
  v_issuance_before int;
  v_issuance_after int;
  v_ledger ai_internal.ai_token_issuance%ROWTYPE;
  v_dup_jti int;
  v_keys_before text;
  v_keys_after text;
  v_settings_before text;
  v_settings_after text;
  v_audit_before int;
  v_audit_after int;
  v_pub_before text;
  v_pub_after text;
  v_ok_jws boolean;
  v_ok_header boolean;
  v_ok_claims boolean;
  v_ok_lifetime boolean;
  v_ok_ledger boolean;
  v_ok_keys boolean;
  v_ok_settings boolean;
  v_ok_audit boolean;
  v_ok_pub boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  v_doc := pg_temp.s06_setup('doctor');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');
  v_org := pg_temp.s06_setup('org');
  v_branch := pg_temp.s06_setup('branch');
  v_i0 := pg_temp.s06_setup('i0');
  v_k0 := pg_temp.s06_text('k0');

  SELECT count(*)::int INTO v_issuance_before FROM ai_internal.ai_token_issuance;
  SELECT count(*)::int INTO v_audit_before FROM public.audit_log;

  -- Full-row md5(string_agg(r::text …)) over user columns. Do not hash xmax
  -- (KEY SHARE on the ledger FK is not a business write; see conflicts.md).
  v_keys_before := pg_temp.row_md5('ai_internal.installation_keys'::regclass);
  v_settings_before := pg_temp.row_md5('ai_internal.app_settings'::regclass);
  v_pub_before := md5(concat_ws(
    E'\n',
    pg_temp.row_md5('public.staff_members'::regclass),
    pg_temp.row_md5('public.staff_branch_assignments'::regclass),
    pg_temp.row_md5('public.branches'::regclass),
    pg_temp.row_md5('public.organizations'::regclass),
    pg_temp.row_md5('public.roles_permissions'::regclass)
  ));

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_now_epoch := extract(epoch FROM now())::bigint;
  v_token := public.issue_ai_token();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);

  SELECT array_agg(k ORDER BY k)
  INTO v_header_keys
  FROM jsonb_object_keys(COALESCE(v_header, '{}'::jsonb)) AS t(k);

  SELECT array_agg(k ORDER BY k)
  INTO v_payload_keys
  FROM jsonb_object_keys(COALESCE(v_payload, '{}'::jsonb)) AS t(k);

  v_jti := v_payload ->> 'jti';
  v_iat := (v_payload ->> 'iat')::bigint;
  v_exp := (v_payload ->> 'exp')::bigint;

  PERFORM pg_temp.reset_postgres();
  SELECT count(*)::int INTO v_issuance_after FROM ai_internal.ai_token_issuance;
  SELECT * INTO v_ledger
  FROM ai_internal.ai_token_issuance i
  WHERE i.jti = v_jti::uuid;
  SELECT count(*)::int INTO v_dup_jti
  FROM ai_internal.ai_token_issuance i
  WHERE i.jti = v_jti::uuid;
  SELECT count(*)::int INTO v_audit_after FROM public.audit_log;

  v_keys_after := pg_temp.row_md5('ai_internal.installation_keys'::regclass);
  v_settings_after := pg_temp.row_md5('ai_internal.app_settings'::regclass);
  v_pub_after := md5(concat_ws(
    E'\n',
    pg_temp.row_md5('public.staff_members'::regclass),
    pg_temp.row_md5('public.staff_branch_assignments'::regclass),
    pg_temp.row_md5('public.branches'::regclass),
    pg_temp.row_md5('public.organizations'::regclass),
    pg_temp.row_md5('public.roles_permissions'::regclass)
  ));

  v_ok_jws := v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND split_part(v_token, '.', 1) <> ''
    AND split_part(v_token, '.', 2) <> ''
    AND split_part(v_token, '.', 3) <> ''
    AND position('{' IN v_token) = 0;

  v_ok_header := v_header = jsonb_build_object('alg', 'EdDSA', 'kid', v_k0)
    AND v_header_keys = ARRAY['alg', 'kid'];

  v_ok_claims := v_payload_keys = ARRAY[
      'aud', 'branch', 'exp', 'iat', 'iss', 'jti', 'org', 'role', 'scopes', 'sub', 'ver'
    ]
    AND (v_payload ->> 'iss') = v_i0::text
    AND (v_payload ->> 'aud') = 'ai-platform'
    AND (v_payload ->> 'sub') = v_doc::text
    AND (v_payload ->> 'org') = v_org::text
    AND (v_payload ->> 'branch') = v_branch::text
    AND (v_payload ->> 'role') = 'doctor'
    AND (v_payload -> 'scopes') = '["ai.access"]'::jsonb
    AND v_jti IS NOT NULL
    AND v_jti ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND jsonb_typeof(v_payload -> 'iat') = 'number'
    AND jsonb_typeof(v_payload -> 'exp') = 'number'
    AND (v_payload ->> 'ver') = '1'
    AND NOT (v_payload ? 'patient_id')
    AND NOT (v_payload ? 'patient')
    AND NOT (v_payload ? 'quota')
    AND NOT (v_payload ? 'provider')
    AND NOT (v_payload ? 'model')
    AND NOT (v_payload ? 'routing_tier')
    AND NOT (v_payload ? 'routing');

  v_ok_lifetime := abs(v_iat - v_now_epoch) <= 5
    AND v_exp = v_iat + 600;

  -- CODE inserts iat = to_timestamp(payload iat). Prefer that equality over
  -- extract(epoch)::bigint, which can off-by-one on float epoch.
  v_ok_ledger := v_issuance_before = 0
    AND v_issuance_after = 1
    AND v_dup_jti = 1
    AND v_ledger.installation_id = v_i0
    AND v_ledger.jti::text = v_jti
    AND v_ledger.actor_staff_id = v_doc
    AND v_ledger.iat = to_timestamp(v_iat)
    AND v_ledger.created_by = v_doc_auth
    AND v_ledger.updated_by = v_doc_auth;

  v_ok_keys := v_keys_before IS NOT DISTINCT FROM v_keys_after;
  v_ok_settings := v_settings_before IS NOT DISTINCT FROM v_settings_after;
  v_ok_audit := v_audit_after = v_audit_before;
  v_ok_pub := v_pub_before IS NOT DISTINCT FROM v_pub_after;

  v_ok := v_ok_jws AND v_ok_header AND v_ok_claims AND v_ok_lifetime
    AND v_ok_ledger AND v_ok_keys AND v_ok_settings AND v_ok_audit AND v_ok_pub;

  IF v_ok THEN
    PERFORM pg_temp.s06_stash_text('aat0', v_token);
    PERFORM pg_temp.s06_stash_text('j0', v_jti);
  END IF;

  v_detail := 'jws=' || COALESCE(v_ok_jws::text, 'f')
    || ' header=' || COALESCE(v_ok_header::text, 'f')
    || ' claims=' || COALESCE(v_ok_claims::text, 'f')
    || ' lifetime=' || COALESCE(v_ok_lifetime::text, 'f')
    || ' ledger=' || COALESCE(v_ok_ledger::text, 'f')
    || ' keys=' || COALESCE(v_ok_keys::text, 'f')
    || ' settings=' || COALESCE(v_ok_settings::text, 'f')
    || ' audit=' || COALESCE(v_ok_audit::text, 'f')
    || ' pub=' || COALESCE(v_ok_pub::text, 'f')
    || ' kid=' || COALESCE(v_header ->> 'kid', '<null>')
    || ' iss=' || COALESCE(v_payload ->> 'iss', '<null>')
    || ' sub=' || COALESCE(v_payload ->> 'sub', '<null>')
    || ' scopes=' || COALESCE((v_payload -> 'scopes')::text, '<null>')
    || ' delta=' || COALESCE((v_exp - v_iat)::text, '<null>')
    || ' payload_iat=' || COALESCE(v_iat::text, '<null>')
    || ' ledger_iat=' || COALESCE(v_ledger.iat::text, '<null>')
    || ' ledger_iat_epoch=' || COALESCE((extract(epoch FROM v_ledger.iat)::bigint)::text, '<null>')
    || ' to_ts_eq=' || COALESCE((v_ledger.iat = to_timestamp(v_iat))::text, 'f')
    || ' issuance=' || COALESCE(v_issuance_after::text, '<null>')
    || ' created_by=' || COALESCE(v_ledger.created_by::text, '<null>');

  PERFORM pg_temp.record(
    'S06-019 — Happy path: doctor mints a fully-populated AAT',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-019 — Happy path: doctor mints a fully-populated AAT',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-020 — Administrator mint carries both granted ai.* scopes, sorted
-- CONFLICT: S06-020 catalog=exp-iat=900 code=seed 10 min → 600
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_adm uuid;
  v_adm_auth uuid;
  v_org uuid;
  v_branch uuid;
  v_i0 uuid;
  v_k0 text;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_payload_keys text[];
  v_iat bigint;
  v_exp bigint;
  v_actor uuid;
  v_ok boolean;
  v_detail text;
BEGIN
  v_adm := pg_temp.s06_setup('admin');
  v_adm_auth := pg_temp.s06_setup('admin_auth');
  v_org := pg_temp.s06_setup('org');
  v_branch := pg_temp.s06_setup('branch');
  v_i0 := pg_temp.s06_setup('i0');
  v_k0 := pg_temp.s06_text('k0');

  PERFORM pg_temp.set_authenticated_session(v_adm_auth);
  v_token := public.issue_ai_token();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);

  SELECT array_agg(k ORDER BY k)
  INTO v_payload_keys
  FROM jsonb_object_keys(COALESCE(v_payload, '{}'::jsonb)) AS t(k);

  v_iat := (v_payload ->> 'iat')::bigint;
  v_exp := (v_payload ->> 'exp')::bigint;

  PERFORM pg_temp.reset_postgres();
  SELECT i.actor_staff_id INTO v_actor
  FROM ai_internal.ai_token_issuance i
  WHERE i.jti = (v_payload ->> 'jti')::uuid;

  v_ok := v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND (v_header ->> 'kid') = v_k0
    AND (v_header ->> 'alg') = 'EdDSA'
    AND v_payload_keys = ARRAY[
      'aud', 'branch', 'exp', 'iat', 'iss', 'jti', 'org', 'role', 'scopes', 'sub', 'ver'
    ]
    AND (v_payload ->> 'role') = 'administrator'
    AND (v_payload -> 'scopes') = '["ai.access","ai.visit_summary"]'::jsonb
    AND (v_payload ->> 'sub') = v_adm::text
    AND (v_payload ->> 'branch') = v_branch::text
    AND (v_payload ->> 'org') = v_org::text
    AND (v_payload ->> 'iss') = v_i0::text
    AND v_exp = v_iat + 600
    AND (v_payload ->> 'ver') = '1'
    AND jsonb_typeof(v_payload -> 'iat') = 'number'
    AND jsonb_typeof(v_payload -> 'exp') = 'number'
    AND v_actor = v_adm;

  v_detail := 'role=' || COALESCE(v_payload ->> 'role', '<null>')
    || ' scopes=' || COALESCE((v_payload -> 'scopes')::text, '<null>')
    || ' kid=' || COALESCE(v_header ->> 'kid', '<null>')
    || ' delta=' || COALESCE((v_exp - v_iat)::text, '<null>')
    || ' actor=' || COALESCE(v_actor::text, '<null>');

  PERFORM pg_temp.record(
    'S06-020 — Administrator mint carries both granted ai.* scopes, sorted',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-020 — Administrator mint carries both granted ai.* scopes, sorted',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-021 — Caller-supplied p_scopes subset is ignored
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_adm uuid;
  v_adm_auth uuid;
  v_token text;
  v_payload jsonb;
  v_actor uuid;
  v_ok boolean;
  v_detail text;
BEGIN
  v_adm := pg_temp.s06_setup('admin');
  v_adm_auth := pg_temp.s06_setup('admin_auth');

  PERFORM pg_temp.set_authenticated_session(v_adm_auth);
  v_token := public.issue_ai_token(p_scopes := ARRAY['ai.access']);
  v_payload := pg_temp.decode_jws_payload(v_token);

  PERFORM pg_temp.reset_postgres();
  SELECT i.actor_staff_id INTO v_actor
  FROM ai_internal.ai_token_issuance i
  WHERE i.jti = (v_payload ->> 'jti')::uuid;

  v_ok := v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND (v_payload -> 'scopes') = '["ai.access","ai.visit_summary"]'::jsonb
    AND v_actor = v_adm;

  v_detail := 'scopes=' || COALESCE((v_payload -> 'scopes')::text, '<null>')
    || ' actor=' || COALESCE(v_actor::text, '<null>');

  PERFORM pg_temp.record(
    'S06-021 — Caller-supplied p_scopes subset is ignored',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-021 — Caller-supplied p_scopes subset is ignored',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-022 — Caller-supplied scope the role lacks (or bogus scope) is ignored
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc uuid;
  v_doc_auth uuid;
  v_token text;
  v_payload jsonb;
  v_scopes jsonb;
  v_actor uuid;
  v_ok boolean;
  v_detail text;
BEGIN
  v_doc := pg_temp.s06_setup('doctor');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_token := public.issue_ai_token(p_scopes := ARRAY['ai.visit_summary', 'ai.forge']);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_scopes := v_payload -> 'scopes';

  PERFORM pg_temp.reset_postgres();
  SELECT i.actor_staff_id INTO v_actor
  FROM ai_internal.ai_token_issuance i
  WHERE i.jti = (v_payload ->> 'jti')::uuid;

  v_ok := v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND v_scopes = '["ai.access"]'::jsonb
    AND NOT (v_scopes @> '["ai.visit_summary"]'::jsonb)
    AND NOT (v_scopes @> '["ai.forge"]'::jsonb)
    AND v_actor = v_doc;

  v_detail := 'scopes=' || COALESCE(v_scopes::text, '<null>')
    || ' actor=' || COALESCE(v_actor::text, '<null>');

  PERFORM pg_temp.record(
    'S06-022 — Caller-supplied scope the role lacks (or bogus scope) is ignored',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-022 — Caller-supplied scope the role lacks (or bogus scope) is ignored',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-023 — Caller-supplied empty scope array is ignored
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc uuid;
  v_doc_auth uuid;
  v_token text;
  v_payload jsonb;
  v_sqlstate text;
  v_sqlerrm text;
  v_raised boolean := false;
  v_actor uuid;
  v_ok boolean;
  v_detail text;
BEGIN
  v_doc := pg_temp.s06_setup('doctor');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);

  BEGIN
    v_token := public.issue_ai_token(p_scopes := ARRAY[]::text[]);
    v_raised := false;
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      v_sqlstate := 'P0001';
      GET STACKED DIAGNOSTICS v_sqlerrm = MESSAGE_TEXT;
      v_raised := true;
    WHEN OTHERS THEN
      v_sqlstate := SQLSTATE;
      GET STACKED DIAGNOSTICS v_sqlerrm = MESSAGE_TEXT;
      v_raised := true;
  END;

  IF NOT v_raised THEN
    v_payload := pg_temp.decode_jws_payload(v_token);
    PERFORM pg_temp.reset_postgres();
    SELECT i.actor_staff_id INTO v_actor
    FROM ai_internal.ai_token_issuance i
    WHERE i.jti = (v_payload ->> 'jti')::uuid;
  ELSE
    PERFORM pg_temp.reset_postgres();
  END IF;

  v_ok := v_raised IS FALSE
    AND v_sqlerrm IS DISTINCT FROM 'AI_ACCESS_DENIED'
    AND v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND (v_payload -> 'scopes') = '["ai.access"]'::jsonb
    AND v_actor = v_doc;

  v_detail := 'raised=' || v_raised::text
    || ' sqlstate=' || COALESCE(v_sqlstate, '<none>')
    || ' sqlerrm=' || COALESCE(v_sqlerrm, '<none>')
    || ' scopes=' || COALESCE((v_payload -> 'scopes')::text, '<null>');

  PERFORM pg_temp.record(
    'S06-023 — Caller-supplied empty scope array is ignored',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-023 — Caller-supplied empty scope array is ignored',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-024 — Branch claim is the primary active branch, not an arbitrary one
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_adm uuid;
  v_adm_auth uuid;
  v_org uuid;
  v_doc uuid;
  v_doc_auth uuid;
  v_br_a uuid;
  v_br_b uuid;
  v_create public.rpc_result;
  v_token text;
  v_payload jsonb;
  v_schedule jsonb := '{
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
  v_ok boolean;
  v_detail text;
BEGIN
  v_adm := pg_temp.s06_setup('admin');
  v_adm_auth := pg_temp.s06_setup('admin_auth');
  v_org := pg_temp.s06_setup('org');
  v_doc := pg_temp.s06_setup('doctor');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');
  v_br_a := pg_temp.s06_setup('branch');

  PERFORM pg_temp.set_staff_session(v_adm_auth, v_org, v_adm);
  v_create := public.manage_create_branch(
    'North Branch',
    v_schedule,
    'NORTH',
    NULL,
    NULL,
    NULL
  );

  IF v_create.success THEN
    v_br_b := (v_create.data ->> 'branch_id')::uuid;
  ELSE
    PERFORM pg_temp.reset_postgres();
    INSERT INTO public.branches (
      organization_id, name, code, working_schedule, created_by, updated_by
    )
    VALUES (
      v_org, 'North Branch', 'NORTH', v_schedule, v_adm_auth, v_adm_auth
    )
    RETURNING id INTO v_br_b;
  END IF;

  PERFORM pg_temp.reset_postgres();
  INSERT INTO public.staff_branch_assignments (
    staff_member_id, branch_id, is_primary, created_by, updated_by
  )
  VALUES (v_doc, v_br_b, false, v_adm_auth, v_adm_auth);

  PERFORM pg_temp.s06_stash_setup('branch_b', v_br_b);

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);
  PERFORM pg_temp.reset_postgres();

  v_ok := v_br_b IS NOT NULL
    AND v_br_b IS DISTINCT FROM v_br_a
    AND v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND (v_payload ->> 'branch') = v_br_a::text
    AND (v_payload ->> 'branch') IS DISTINCT FROM v_br_b::text;

  v_detail := 'create=' || COALESCE(v_create.error_code, 'ok')
    || ' br_a=' || v_br_a::text
    || ' br_b=' || COALESCE(v_br_b::text, '<null>')
    || ' claim=' || COALESCE(v_payload ->> 'branch', '<null>');

  PERFORM pg_temp.record(
    'S06-024 — Branch claim is the primary active branch, not an arbitrary one',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-024 — Branch claim is the primary active branch, not an arbitrary one',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-025 — Successive mints get unique jti with stable identity claims
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_k0 text;
  v_aat0 text;
  v_j0 text;
  v_payload0 jsonb;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_j1 text;
  v_dup int;
  v_ok boolean;
  v_detail text;
BEGIN
  v_doc_auth := pg_temp.s06_setup('doctor_auth');
  v_k0 := pg_temp.s06_text('k0');
  v_aat0 := pg_temp.s06_text('aat0');
  v_j0 := pg_temp.s06_text('j0');

  IF v_aat0 IS NULL OR v_j0 IS NULL THEN
    PERFORM pg_temp.record(
      'S06-025 — Successive mints get unique jti with stable identity claims',
      false,
      'AAT0/J0 not stashed; S06-019 did not pass'
    );
  ELSE
    v_payload0 := pg_temp.decode_jws_payload(v_aat0);

    PERFORM pg_temp.set_authenticated_session(v_doc_auth);
    v_token := public.issue_ai_token();
    v_header := pg_temp.decode_jws_header(v_token);
    v_payload := pg_temp.decode_jws_payload(v_token);
    v_j1 := v_payload ->> 'jti';

    PERFORM pg_temp.reset_postgres();
    SELECT count(*)::int INTO v_dup
    FROM (
      SELECT i.jti
      FROM ai_internal.ai_token_issuance i
      GROUP BY i.jti
      HAVING count(*) > 1
    ) d;

    v_ok := v_j1 IS NOT NULL
      AND v_j1 <> v_j0
      AND (v_payload ->> 'iss') IS NOT DISTINCT FROM (v_payload0 ->> 'iss')
      AND (v_header ->> 'kid') = v_k0
      AND (v_payload ->> 'sub') IS NOT DISTINCT FROM (v_payload0 ->> 'sub')
      AND (v_payload ->> 'org') IS NOT DISTINCT FROM (v_payload0 ->> 'org')
      AND (v_payload ->> 'branch') IS NOT DISTINCT FROM (v_payload0 ->> 'branch')
      AND (v_payload ->> 'role') IS NOT DISTINCT FROM (v_payload0 ->> 'role')
      AND (v_payload -> 'scopes') IS NOT DISTINCT FROM (v_payload0 -> 'scopes')
      AND (v_payload ->> 'iat')::bigint >= (v_payload0 ->> 'iat')::bigint
      AND v_dup = 0
      AND EXISTS (
        SELECT 1 FROM ai_internal.ai_token_issuance i WHERE i.jti = v_j1::uuid
      )
      AND EXISTS (
        SELECT 1 FROM ai_internal.ai_token_issuance i WHERE i.jti = v_j0::uuid
      );

    v_detail := 'j0=' || v_j0
      || ' j1=' || COALESCE(v_j1, '<null>')
      || ' distinct=' || (v_j1 IS DISTINCT FROM v_j0)::text
      || ' dup_jti=' || v_dup::text
      || ' iat0=' || COALESCE(v_payload0 ->> 'iat', '<null>')
      || ' iat1=' || COALESCE(v_payload ->> 'iat', '<null>');

    PERFORM pg_temp.record(
      'S06-025 — Successive mints get unique jti with stable identity claims',
      v_ok,
      v_detail
    );
  END IF;
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-025 — Successive mints get unique jti with stable identity claims',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-026 — Missing app_settings rows fall back to built-in defaults
-- CONFLICT: original issuer fallback was 15; CODE 20260905120300 is 10 min → 600 s
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_token text;
  v_payload jsonb;
  v_iat bigint;
  v_exp bigint;
  v_actor uuid;
  v_doc uuid;
  v_ok boolean;
  v_detail text;
BEGIN
  v_doc := pg_temp.s06_setup('doctor');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');

  -- [SEED]: no RPC manages these rows; simulates a lost-settings restore.
  DELETE FROM ai_internal.app_settings
  WHERE key IN (
    'ai.aat.lifetime_minutes',
    'ai.aat.audience',
    'ai.aat.ver',
    'ai.issuer.rate_limit.ceiling',
    'ai.issuer.rate_limit.window_seconds'
  );

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_iat := (v_payload ->> 'iat')::bigint;
  v_exp := (v_payload ->> 'exp')::bigint;

  PERFORM pg_temp.reset_postgres();
  SELECT i.actor_staff_id INTO v_actor
  FROM ai_internal.ai_token_issuance i
  WHERE i.jti = (v_payload ->> 'jti')::uuid;

  -- Restore CODE seed (lifetime 10, not catalog 15).
  INSERT INTO ai_internal.app_settings (key, value_json)
  VALUES
    ('ai.aat.lifetime_minutes', '10'::jsonb),
    ('ai.aat.audience', '"ai-platform"'::jsonb),
    ('ai.aat.ver', '"1"'::jsonb),
    ('ai.issuer.rate_limit.ceiling', '100'::jsonb),
    ('ai.issuer.rate_limit.window_seconds', '3600'::jsonb)
  ON CONFLICT (key) DO UPDATE
  SET
    value_json = EXCLUDED.value_json,
    is_deleted = false,
    deleted_at = NULL,
    deleted_by = NULL;

  v_ok := v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND (v_payload ->> 'aud') = 'ai-platform'
    AND (v_payload ->> 'ver') = '1'
    AND v_exp = v_iat + 600
    AND v_actor = v_doc;

  v_detail := 'aud=' || COALESCE(v_payload ->> 'aud', '<null>')
    || ' ver=' || COALESCE(v_payload ->> 'ver', '<null>')
    || ' delta=' || COALESCE((v_exp - v_iat)::text, '<null>');

  PERFORM pg_temp.record(
    'S06-026 — Missing app_settings rows fall back to built-in defaults',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-026 — Missing app_settings rows fall back to built-in defaults',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-027 — After additive rotation the new kid signs and old tokens still verify
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_doc_auth uuid;
  v_k0 text;
  v_i0 uuid;
  v_aat0 text;
  v_rotate public.rpc_result;
  v_k1 text;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_verified boolean;
  v_k0_revoked timestamptz;
  v_ok boolean;
  v_detail text;
BEGIN
  v_boot_auth := pg_temp.s06_setup('boot_auth');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');
  v_i0 := pg_temp.s06_setup('i0');
  v_k0 := pg_temp.s06_text('k0');
  v_aat0 := pg_temp.s06_text('aat0');

  IF v_k0 IS NULL THEN
    PERFORM pg_temp.record(
      'S06-027 — After additive rotation the new kid signs and old tokens still verify',
      false,
      'K0 not stashed; B0 enroll did not pass'
    );
  ELSE
    IF v_aat0 IS NULL THEN
      PERFORM pg_temp.set_authenticated_session(v_doc_auth);
      v_aat0 := public.issue_ai_token();
      PERFORM pg_temp.s06_stash_text('aat0', v_aat0);
    END IF;

    PERFORM pg_temp.set_authenticated_session(v_boot_auth);
    v_rotate := public.rotate_installation_key();
    v_k1 := v_rotate.data ->> 'kid';
    IF v_k1 IS NOT NULL THEN
      PERFORM pg_temp.s06_stash_text('k1', v_k1);
    END IF;

    PERFORM pg_temp.set_authenticated_session(v_doc_auth);
    v_token := public.issue_ai_token();
    v_header := pg_temp.decode_jws_header(v_token);
    v_payload := pg_temp.decode_jws_payload(v_token);

    PERFORM pg_temp.reset_postgres();
    v_verified := auth_internal.verify_aat(v_aat0);
    SELECT ik.revoked_at INTO v_k0_revoked
    FROM ai_internal.installation_keys ik
    WHERE ik.kid = v_k0;

    v_ok := v_rotate.success
      AND v_k1 IS NOT NULL
      AND v_k1 <> v_k0
      AND (v_rotate.data ->> 'installation_id') = v_i0::text
      AND (v_header ->> 'kid') = v_k1
      AND (v_payload ->> 'iss') = v_i0::text
      AND v_verified IS TRUE
      AND v_k0_revoked IS NULL;

    v_detail := 'rotate=' || COALESCE(v_rotate.error_code, 'ok')
      || ' k1=' || COALESCE(v_k1, '<null>')
      || ' mint_kid=' || COALESCE(v_header ->> 'kid', '<null>')
      || ' iss=' || COALESCE(v_payload ->> 'iss', '<null>')
      || ' verify_aat0=' || COALESCE(v_verified::text, '<null>')
      || ' k0_revoked=' || COALESCE(v_k0_revoked::text, '<null>');

    PERFORM pg_temp.record(
      'S06-027 — After additive rotation the new kid signs and old tokens still verify',
      v_ok,
      v_detail
    );
  END IF;
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-027 — After additive rotation the new kid signs and old tokens still verify',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-028 — After revoking the old kid, minting continues on the new kid and old-kid tokens die
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_doc_auth uuid;
  v_k0 text;
  v_k1 text;
  v_aat0 text;
  v_revoke public.rpc_result;
  v_token text;
  v_header jsonb;
  v_verified boolean;
  v_ok boolean;
  v_detail text;
BEGIN
  v_boot_auth := pg_temp.s06_setup('boot_auth');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');
  v_k0 := pg_temp.s06_text('k0');
  v_k1 := pg_temp.s06_text('k1');
  v_aat0 := pg_temp.s06_text('aat0');

  IF v_k0 IS NULL OR v_k1 IS NULL OR v_aat0 IS NULL THEN
    PERFORM pg_temp.record(
      'S06-028 — After revoking the old kid, minting continues on the new kid and old-kid tokens die',
      false,
      'K0/K1/AAT0 not stashed; S06-027/S06-019 did not pass'
    );
  ELSE
    PERFORM pg_temp.set_authenticated_session(v_boot_auth);
    v_revoke := public.revoke_installation_key(v_k0);

    PERFORM pg_temp.set_authenticated_session(v_doc_auth);
    v_token := public.issue_ai_token();
    v_header := pg_temp.decode_jws_header(v_token);

    PERFORM pg_temp.reset_postgres();
    v_verified := auth_internal.verify_aat(v_aat0);

    v_ok := v_revoke.success
      AND v_token IS NOT NULL
      AND (v_header ->> 'kid') = v_k1
      AND v_verified IS FALSE;

    v_detail := 'revoke=' || COALESCE(v_revoke.error_code, 'ok')
      || ' mint_kid=' || COALESCE(v_header ->> 'kid', '<null>')
      || ' expected_k1=' || v_k1
      || ' verify_aat0=' || COALESCE(v_verified::text, '<null>');

    PERFORM pg_temp.record(
      'S06-028 — After revoking the old kid, minting continues on the new kid and old-kid tokens die',
      v_ok,
      v_detail
    );
  END IF;
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-028 — After revoking the old kid, minting continues on the new kid and old-kid tokens die',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-029 — Re-enrollment after a zero-active-keystore recovers minting with the same installation id
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_boot_auth uuid;
  v_doc_auth uuid;
  v_i0 uuid;
  v_k1 text;
  v_enroll public.rpc_result;
  v_k2 text;
  v_token text;
  v_header jsonb;
  v_payload jsonb;
  v_ok boolean;
  v_detail text;
BEGIN
  v_boot_auth := pg_temp.s06_setup('boot_auth');
  v_doc_auth := pg_temp.s06_setup('doctor_auth');
  v_i0 := pg_temp.s06_setup('i0');
  v_k1 := pg_temp.s06_text('k1');

  -- [SEED] like S06-011: RPC last-active guard blocks revoking K1; zero-active
  -- via direct UPDATE. ALREADY_ENROLLED fires only when an active key exists.
  UPDATE ai_internal.installation_keys
  SET revoked_at = clock_timestamp()
  WHERE is_deleted = false
    AND revoked_at IS NULL;

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);
  v_enroll := public.enroll_installation_keypair();
  v_k2 := v_enroll.data ->> 'kid';

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_token := public.issue_ai_token();
  v_header := pg_temp.decode_jws_header(v_token);
  v_payload := pg_temp.decode_jws_payload(v_token);
  PERFORM pg_temp.reset_postgres();

  v_ok := v_enroll.success
    AND v_enroll.error_code IS DISTINCT FROM 'ALREADY_ENROLLED'
    AND v_k2 IS NOT NULL
    AND (v_k1 IS NULL OR v_k2 <> v_k1)
    AND (v_enroll.data ->> 'installation_id') = v_i0::text
    AND v_token IS NOT NULL
    AND (v_header ->> 'kid') = v_k2
    AND (v_payload ->> 'iss') = v_i0::text;

  IF v_k2 IS NOT NULL THEN
    PERFORM pg_temp.s06_stash_text('k2', v_k2);
  END IF;

  v_detail := 'enroll=' || COALESCE(v_enroll.error_code, 'ok')
    || ' k2=' || COALESCE(v_k2, '<null>')
    || ' iid=' || COALESCE(v_enroll.data ->> 'installation_id', '<null>')
    || ' mint_kid=' || COALESCE(v_header ->> 'kid', '<null>')
    || ' iss=' || COALESCE(v_payload ->> 'iss', '<null>');

  PERFORM pg_temp.record(
    'S06-029 — Re-enrollment after a zero-active-keystore recovers minting with the same installation id',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-029 — Re-enrollment after a zero-active-keystore recovers minting with the same installation id',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-030 — The ver claim comes from ai.aat.ver
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_token text;
  v_payload jsonb;
  v_ok boolean;
  v_detail text;
BEGIN
  v_doc_auth := pg_temp.s06_setup('doctor_auth');

  UPDATE ai_internal.app_settings
  SET value_json = '"2"'::jsonb
  WHERE key = 'ai.aat.ver';

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);

  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.app_settings
  SET value_json = '"1"'::jsonb
  WHERE key = 'ai.aat.ver';

  v_ok := v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND (v_payload ->> 'ver') = '2';

  v_detail := 'ver=' || COALESCE(v_payload ->> 'ver', '<null>');

  PERFORM pg_temp.record(
    'S06-030 — The ver claim comes from ai.aat.ver',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-030 — The ver claim comes from ai.aat.ver',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-031 — The aud claim comes from ai.aat.audience
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_token text;
  v_payload jsonb;
  v_ok boolean;
  v_detail text;
BEGIN
  v_doc_auth := pg_temp.s06_setup('doctor_auth');

  UPDATE ai_internal.app_settings
  SET value_json = '"clinic-portal"'::jsonb
  WHERE key = 'ai.aat.audience';

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);

  PERFORM pg_temp.reset_postgres();
  UPDATE ai_internal.app_settings
  SET value_json = '"ai-platform"'::jsonb
  WHERE key = 'ai.aat.audience';

  v_ok := v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND (v_payload ->> 'aud') = 'clinic-portal';

  v_detail := 'aud=' || COALESCE(v_payload ->> 'aud', '<null>');

  PERFORM pg_temp.record(
    'S06-031 — The aud claim comes from ai.aat.audience',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-031 — The aud claim comes from ai.aat.audience',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- S06-032 — Lifetime boundary: exp − iat exactly 600 seconds
-- CONFLICT: S06-032 catalog restore=15 code seed=10 (20260905120000)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_doc_auth uuid;
  v_token text;
  v_payload jsonb;
  v_iat bigint;
  v_exp bigint;
  v_ok boolean;
  v_detail text;
BEGIN
  v_doc_auth := pg_temp.s06_setup('doctor_auth');

  UPDATE ai_internal.app_settings
  SET value_json = '10'::jsonb
  WHERE key = 'ai.aat.lifetime_minutes';

  PERFORM pg_temp.set_authenticated_session(v_doc_auth);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_iat := (v_payload ->> 'iat')::bigint;
  v_exp := (v_payload ->> 'exp')::bigint;

  PERFORM pg_temp.reset_postgres();
  -- Restore CODE seed 10, not catalog 15.
  UPDATE ai_internal.app_settings
  SET value_json = '10'::jsonb
  WHERE key = 'ai.aat.lifetime_minutes';

  v_ok := v_token IS NOT NULL
    AND array_length(string_to_array(v_token, '.'), 1) = 3
    AND jsonb_typeof(v_payload -> 'iat') = 'number'
    AND jsonb_typeof(v_payload -> 'exp') = 'number'
    AND v_exp = v_iat + 600;

  v_detail := 'delta=' || COALESCE((v_exp - v_iat)::text, '<null>')
    || ' iat=' || COALESCE(v_iat::text, '<null>')
    || ' exp=' || COALESCE(v_exp::text, '<null>');

  PERFORM pg_temp.record(
    'S06-032 — Lifetime boundary: exp − iat exactly 600 seconds',
    v_ok,
    v_detail
  );
EXCEPTION
  WHEN undefined_function THEN
    PERFORM pg_temp.reset_postgres();
    RAISE;
  WHEN OTHERS THEN
    PERFORM pg_temp.record_caught(
      'S06-032 — Lifetime boundary: exp − iat exactly 600 seconds',
      SQLSTATE,
      SQLERRM
    );
END;
$$;

SELECT test_name, passed, detail FROM catalog_results ORDER BY test_name;
SELECT pg_temp.fail_if_any();
ROLLBACK;
