-- J4 token contract rotation contract tests (T-J4-08 .. T-J4-10).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/ai_token_contract_rotation.sql

BEGIN;

CREATE TEMP TABLE ai_token_contract_rotation_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

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

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'd1000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'd2000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'development', true);
  DELETE FROM ai_internal.ai_token_issuance;
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff]::uuid[]);
  DELETE FROM public.audit_log;
  DELETE FROM auth.users WHERE id = v_doctor_user;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_doctor_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'ai-rotation-doctor',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);

  v_result := public.bootstrap_create_organization('AI Rotation Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'fixture bootstrap_create_organization failed: %', v_result.error_code;
  END IF;
  v_org_id := (v_result.data ->> 'organization_id')::uuid;

  v_result := public.bootstrap_create_branch(v_org_id, 'Main', NULL, NULL, 'MAIN', NULL);
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'fixture bootstrap_create_branch failed: %', v_result.error_code;
  END IF;
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES (
    v_doctor_staff,
    v_doctor_user,
    'AI Rotation Doctor',
    'doctor',
    false,
    v_bootstrap_user,
    v_bootstrap_user
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_doctor_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT DO NOTHING;

  INSERT INTO ai_token_contract_rotation_results VALUES ('fixture_setup', true, 'org and doctor staff ready');
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  PERFORM public.enroll_installation_keypair();
END;
$$;

-- T-J4-08: after advancing ai.aat.ver, mint carries every §5.6 claim and deliberate omissions.
DO $$
DECLARE
  v_doctor_user uuid := 'd1000000-0000-4000-8000-000000000001';
  v_advanced_ver text := '2';
  v_token text;
  v_payload jsonb;
  v_header jsonb;
  v_claim text;
  v_claims text[] := ARRAY[
    'iss', 'aud', 'sub', 'org', 'branch', 'role', 'scopes', 'jti', 'iat', 'exp', 'ver'
  ];
  v_missing text[] := ARRAY[]::text[];
  v_omitted text[] := ARRAY['patient_id', 'quota', 'provider', 'model'];
  v_omission text;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  UPDATE ai_internal.app_settings
  SET value_json = to_jsonb(v_advanced_ver)
  WHERE key = 'ai.aat.ver';

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_header := pg_temp.decode_jws_header(v_token);

  FOREACH v_claim IN ARRAY v_claims LOOP
    IF NOT (
      v_payload ? v_claim
      AND v_payload -> v_claim IS NOT NULL
      AND v_payload ->> v_claim IS NOT NULL
      AND v_payload ->> v_claim <> ''
    ) THEN
      v_missing := array_append(v_missing, v_claim);
    END IF;
  END LOOP;

  IF jsonb_typeof(v_payload -> 'scopes') <> 'array'
     OR jsonb_array_length(v_payload -> 'scopes') < 1 THEN
    v_missing := array_append(v_missing, 'scopes(non-empty array)');
  END IF;

  IF v_header ->> 'alg' <> 'EdDSA' THEN
    v_missing := array_append(v_missing, 'header.alg');
  END IF;

  IF v_payload ->> 'ver' <> v_advanced_ver THEN
    v_missing := array_append(v_missing, 'ver=' || COALESCE(v_payload ->> 'ver', '<null>'));
  END IF;

  FOREACH v_omission IN ARRAY v_omitted LOOP
    IF v_payload ? v_omission THEN
      v_missing := array_append(v_missing, 'forbidden:' || v_omission);
    END IF;
  END LOOP;

  v_passed := cardinality(v_missing) = 0;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_contract_rotation_results VALUES (
    'T-J4-08 new_contract_token_carries_every_claim',
    v_passed,
    CASE
      WHEN v_passed THEN 'all claims present under advanced ver'
      ELSE 'missing=' || array_to_string(v_missing, ',')
    END
  );
END;
$$;

-- T-J4-09: issuer mints exactly one ver from ai.aat.ver; scopes remain RBAC-derived.
DO $$
DECLARE
  v_doctor_user uuid := 'd1000000-0000-4000-8000-000000000001';
  v_setting_ver text;
  v_token text;
  v_payload jsonb;
  v_scopes jsonb;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT value_json #>> '{}' INTO v_setting_ver
  FROM ai_internal.app_settings
  WHERE key = 'ai.aat.ver';

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token(p_scopes := ARRAY['ai.forge']);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_scopes := v_payload -> 'scopes';

  v_passed := v_payload ->> 'ver' = v_setting_ver
    AND v_scopes @> '["ai.access"]'::jsonb
    AND NOT (v_scopes @> '["ai.forge"]'::jsonb);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_contract_rotation_results VALUES (
    'T-J4-09 issuer_mints_single_ver_from_ai_aat_ver',
    v_passed,
  'setting_ver=' || COALESCE(v_setting_ver, '<null>')
    || ' token_ver=' || COALESCE(v_payload ->> 'ver', '<null>')
    || ' scopes=' || COALESCE(v_scopes::text, '<null>')
  );
END;
$$;

-- T-J4-10 clinic half: same enrolled installation mints under advanced ver without re-enrollment.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'd1000000-0000-4000-8000-000000000001';
  v_installation_id uuid;
  v_key_count_before int;
  v_key_count_after int;
  v_setting_ver text;
  v_token text;
  v_payload jsonb;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  SELECT installation_id INTO v_installation_id
  FROM ai_internal.installation_keys
  WHERE is_deleted = false
  ORDER BY valid_from DESC
  LIMIT 1;

  SELECT count(*)::int INTO v_key_count_before
  FROM ai_internal.installation_keys
  WHERE installation_id = v_installation_id
    AND is_deleted = false;

  SELECT value_json #>> '{}' INTO v_setting_ver
  FROM ai_internal.app_settings
  WHERE key = 'ai.aat.ver';

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);

  PERFORM set_config('role', 'postgres', true);
  SELECT count(*)::int INTO v_key_count_after
  FROM ai_internal.installation_keys
  WHERE installation_id = v_installation_id
    AND is_deleted = false;

  v_passed := v_key_count_before = v_key_count_after
    AND v_key_count_after >= 1
    AND v_payload ->> 'iss' = v_installation_id::text
    AND v_payload ->> 'ver' = v_setting_ver;

  INSERT INTO ai_token_contract_rotation_results VALUES (
    'T-J4-10 rotation_requires_no_re_enrollment',
    v_passed,
    'installation=' || COALESCE(v_installation_id::text, '<null>')
      || ' keys_before=' || v_key_count_before::text
      || ' keys_after=' || v_key_count_after::text
      || ' ver=' || COALESCE(v_payload ->> 'ver', '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM ai_token_contract_rotation_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'ai_token_contract_rotation failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM ai_token_contract_rotation_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM ai_token_contract_rotation_results ORDER BY test_name;
