-- Frozen catalog SQL harness helpers.
-- Include after BEGIN in a scenario file:  \ir harness.sql
-- (or \i harness.sql when cwd is backend/tests/catalog)
--
-- Writers own BEGIN / catalog_results rows / fail_if_any / ROLLBACK.
-- Do not modify this file from a stage-writer task.

CREATE TEMP TABLE IF NOT EXISTS catalog_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE TEMP TABLE IF NOT EXISTS catalog_setup (
  key text PRIMARY KEY,
  value uuid NOT NULL
);

CREATE OR REPLACE FUNCTION pg_temp.decode_jws_header(p_token text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT convert_from(
    decode(
      rpad(
        translate(split_part(p_token, '.', 1), '-_', '+/'),
        length(split_part(p_token, '.', 1))
          + ((4 - length(split_part(p_token, '.', 1)) % 4) % 4),
        '='
      ),
      'base64'
    ),
    'utf8'
  )::jsonb;
$$;

CREATE OR REPLACE FUNCTION pg_temp.decode_jws_payload(p_token text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT convert_from(
    decode(
      rpad(
        translate(split_part(p_token, '.', 2), '-_', '+/'),
        length(split_part(p_token, '.', 2))
          + ((4 - length(split_part(p_token, '.', 2)) % 4) % 4),
        '='
      ),
      'base64'
    ),
    'utf8'
  )::jsonb;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_authenticated_session(
  p_user_id uuid,
  p_exp_epoch bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_claims jsonb;
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  v_claims := jsonb_build_object(
    'sub', p_user_id::text,
    'role', 'authenticated'
  );
  IF p_exp_epoch IS NOT NULL THEN
    v_claims := v_claims || jsonb_build_object('exp', p_exp_epoch);
  END IF;
  PERFORM set_config('request.jwt.claims', v_claims::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_anon_session()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.reset_postgres()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

-- Catalog empty-keystore [SEED] (Stage 02 common journey step 3).
-- Leaves the session as postgres so writers can inspect ai_internal.
CREATE OR REPLACE FUNCTION pg_temp.reset_keystore()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM ai_internal.ai_token_issuance;
  DELETE FROM ai_internal.installation_keys;
  UPDATE ai_internal.app_settings
  SET
    value_json = '{"enrolled": false, "platform_base_url": null}'::jsonb,
    is_deleted = false,
    deleted_at = NULL,
    deleted_by = NULL
  WHERE key = 'ai.availability';
END;
$$;

-- Stage 02 common journey setup: isolate prior fixtures, BOOT session,
-- bootstrap_finish_setup (Sunrise Dental / Nadia / Omar), empty keystore.
-- Stashes ids in catalog_setup. Leaves the session as postgres.
CREATE OR REPLACE FUNCTION pg_temp.catalog_common_setup()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_boot_auth uuid := 'a0000000-0000-4000-8000-000000000001';
  v_boot_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_admin_id uuid;
  v_doctor_id uuid;
  v_admin_auth uuid;
  v_doctor_auth uuid;
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

  DELETE FROM auth.identities
  WHERE provider = 'email'
    AND provider_id IN ('nadia_karim', 'omar_haddad');
  DELETE FROM auth.users
  WHERE lower(email) IN ('nadia_karim', 'omar_haddad');

  PERFORM pg_temp.reset_keystore();

  PERFORM pg_temp.set_authenticated_session(v_boot_auth);

  -- 12-arg wrapper (required working_schedule) so the call is not ambiguous
  -- against the leftover 11-arg public overlay.
  v_result := public.bootstrap_finish_setup(
    'Sunrise Dental Clinic'::text,
    'Main Branch'::text,
    '[{"username":"nadia_karim","password":"Nadia#Karim2026!","full_name":"Nadia Karim","role":"administrator"},{"username":"omar_haddad","password":"Omar#Haddad2026!","full_name":"Omar Haddad","role":"doctor"}]'::jsonb,
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
    RAISE EXCEPTION 'catalog_common_setup bootstrap_finish_setup failed: % — %',
      COALESCE(v_result.error_code, '<null>'),
      COALESCE(v_result.error_message, '');
  END IF;

  v_org_id := (v_result.data ->> 'organization_id')::uuid;
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;
  v_admin_id := (v_result.data -> 'staff_member_ids' ->> 0)::uuid;
  v_doctor_id := (v_result.data -> 'staff_member_ids' ->> 1)::uuid;

  PERFORM pg_temp.reset_postgres();

  SELECT sm.auth_user_id INTO STRICT v_admin_auth
  FROM public.staff_members sm
  WHERE sm.id = v_admin_id;

  SELECT sm.auth_user_id INTO STRICT v_doctor_auth
  FROM public.staff_members sm
  WHERE sm.id = v_doctor_id;

  DELETE FROM catalog_setup;
  INSERT INTO catalog_setup (key, value) VALUES
    ('org', v_org_id),
    ('branch', v_branch_id),
    ('admin', v_admin_id),
    ('doctor', v_doctor_id),
    ('admin_auth', v_admin_auth),
    ('doctor_auth', v_doctor_auth),
    ('boot', v_boot_staff),
    ('boot_auth', v_boot_auth);

  PERFORM pg_temp.reset_keystore();
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.record(p_id text, p_passed boolean, p_detail text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO catalog_results (test_name, passed, detail)
  VALUES (p_id, p_passed, p_detail)
  ON CONFLICT (test_name) DO UPDATE
  SET passed = EXCLUDED.passed,
      detail = EXCLUDED.detail;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.fail_if_any()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_failures int;
BEGIN
  PERFORM pg_temp.reset_postgres();
  SELECT count(*) INTO v_failures FROM catalog_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'catalog failed: %', (
      SELECT string_agg(test_name || ': ' || COALESCE(detail, ''), '; ')
      FROM catalog_results
      WHERE NOT passed
    );
  END IF;
END;
$$;
