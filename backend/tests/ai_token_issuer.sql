-- B1 AAT issuer contract tests (T07–T16).
-- Run: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/ai_token_issuer.sql

BEGIN;

CREATE TEMP TABLE ai_token_issuer_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

-- base64url-decode the JWS payload segment (§4.2.1 encode/translate pattern).
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

-- Shared fixture: org, branch, doctor staff (ai.access via seed).
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'c2000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'development', true);
  PERFORM auth_internal.delete_clinic_test_fixtures(ARRAY[v_bootstrap_staff, v_doctor_staff]::uuid[]);
  DELETE FROM public.audit_log;
  UPDATE public.roles_permissions
  SET updated_by = NULL, created_by = NULL
  WHERE updated_by = v_doctor_user OR created_by = v_doctor_user;
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
    'ai-issuer-doctor',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);

  v_result := public.bootstrap_create_organization('AI Issuer Clinic', '{}'::jsonb, NULL, 'EGP', 'UTC');
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
    'AI Issuer Doctor',
    'doctor',
    false,
    v_bootstrap_user,
    v_bootstrap_user
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
  VALUES (v_doctor_staff, v_branch_id, true, v_bootstrap_user, v_bootstrap_user)
  ON CONFLICT DO NOTHING;

  INSERT INTO ai_token_issuer_results VALUES ('fixture_setup', true, 'org and doctor staff ready');
END;
$$;

-- Enroll installation keypair once before mint / session / gate tests.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  v_result := public.enroll_installation_keypair();
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'fixture enroll_installation_keypair failed: %', COALESCE(v_result.error_code, '<null>');
  END IF;
END;
$$;

-- T09: absent session → UNAUTHENTICATED; expired session → SESSION_EXPIRED (after enrollment).
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_absent_code text;
  v_expired_code text;
  v_passed boolean;
BEGIN
  IF to_regprocedure('public.issue_ai_token(text[])') IS NULL
     AND to_regprocedure('public.issue_ai_token()') IS NULL THEN
    RAISE EXCEPTION 'public.issue_ai_token is not installed yet';
  END IF;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
  v_absent_code := pg_temp.capture_issue_error();

  PERFORM pg_temp.set_authenticated_session(
    v_doctor_user,
    (extract(epoch from now() - interval '1 hour'))::bigint
  );
  v_expired_code := pg_temp.capture_issue_error();

  v_passed := v_absent_code = 'UNAUTHENTICATED'
    AND v_expired_code = 'SESSION_EXPIRED';

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T09 expired or absent session rejected',
    v_passed,
    'absent=' || COALESCE(v_absent_code, '<null>')
      || ' expired=' || COALESCE(v_expired_code, '<null>')
  );
END;
$$;

-- T07: §5.6 claims populated with correct aud/sub/iss, unique jti, RBAC scopes equality.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_doctor_staff uuid := 'c2000000-0000-4000-8000-000000000001';
  v_token1 text;
  v_token2 text;
  v_payload1 jsonb;
  v_payload2 jsonb;
  v_claim text;
  v_claims text[] := ARRAY[
    'iss', 'aud', 'sub', 'org', 'branch', 'role', 'scopes', 'jti', 'iat', 'exp', 'ver'
  ];
  v_missing text[] := ARRAY[]::text[];
  v_installation_id uuid;
  v_expected_aud text;
  v_rbac_scopes jsonb;
  v_scopes jsonb;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  SELECT ik.installation_id
  INTO v_installation_id
  FROM ai_internal.installation_keys ik
  WHERE ik.is_deleted = false
    AND ik.revoked_at IS NULL
  ORDER BY ik.valid_from DESC, ik.kid DESC
  LIMIT 1;

  v_expected_aud := auth_internal.ai_app_setting_text('ai.aat.audience', 'ai-platform');

  SELECT coalesce(
    jsonb_agg(rp.permission_key ORDER BY rp.permission_key),
    '[]'::jsonb
  )
  INTO v_rbac_scopes
  FROM public.roles_permissions rp
  WHERE rp.role = 'doctor'
    AND rp.permission_key LIKE 'ai.%'
    AND rp.is_granted = true
    AND rp.is_deleted = false;

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token1 := public.issue_ai_token();
  v_token2 := public.issue_ai_token();
  v_payload1 := pg_temp.decode_jws_payload(v_token1);
  v_payload2 := pg_temp.decode_jws_payload(v_token2);
  v_scopes := v_payload1 -> 'scopes';

  FOREACH v_claim IN ARRAY v_claims LOOP
    IF NOT (
      v_payload1 ? v_claim
      AND v_payload1 -> v_claim IS NOT NULL
      AND v_payload1 ->> v_claim IS NOT NULL
      AND v_payload1 ->> v_claim <> ''
    ) THEN
      v_missing := array_append(v_missing, v_claim);
    END IF;
  END LOOP;

  IF jsonb_typeof(v_scopes) <> 'array'
     OR jsonb_array_length(v_scopes) < 1 THEN
    v_missing := array_append(v_missing, 'scopes(non-empty array)');
  END IF;

  IF v_payload1 ->> 'aud' IS DISTINCT FROM v_expected_aud THEN
    v_missing := array_append(
      v_missing,
      'aud=' || COALESCE(v_payload1 ->> 'aud', '<null>')
    );
  END IF;

  IF v_payload1 ->> 'sub' IS DISTINCT FROM v_doctor_staff::text THEN
    v_missing := array_append(
      v_missing,
      'sub=' || COALESCE(v_payload1 ->> 'sub', '<null>')
    );
  END IF;

  IF v_payload1 ->> 'iss' IS DISTINCT FROM v_installation_id::text THEN
    v_missing := array_append(
      v_missing,
      'iss=' || COALESCE(v_payload1 ->> 'iss', '<null>')
    );
  END IF;

  IF (v_payload1 ->> 'jti') IS NULL
     OR (v_payload2 ->> 'jti') IS NULL
     OR (v_payload1 ->> 'jti') = (v_payload2 ->> 'jti') THEN
    v_missing := array_append(v_missing, 'jti_not_unique');
  END IF;

  IF NOT (v_scopes @> v_rbac_scopes AND v_rbac_scopes @> v_scopes) THEN
    v_missing := array_append(
      v_missing,
      'scopes_mismatch expected=' || v_rbac_scopes::text
        || ' got=' || COALESCE(v_scopes::text, '<null>')
    );
  END IF;

  v_passed := cardinality(v_missing) = 0;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T07 all section 5.6 claims populated',
    v_passed,
    CASE
      WHEN v_passed THEN
        'aud=' || v_expected_aud
          || ' sub=' || v_doctor_staff::text
          || ' iss=' || v_installation_id::text
          || ' jtis_unique scopes_eq'
      ELSE 'missing=' || array_to_string(v_missing, ',')
    END
  );
END;
$$;

-- T07b: JWS header alg=EdDSA and non-null kid.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_token text;
  v_header jsonb;
  v_passed boolean;
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token();
  v_header := pg_temp.decode_jws_header(v_token);

  v_passed := (v_header ->> 'alg') = 'EdDSA'
    AND NULLIF(v_header ->> 'kid', '') IS NOT NULL;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T07b header alg EdDSA and kid present',
    v_passed,
    'alg=' || COALESCE(v_header ->> 'alg', '<null>')
      || ' kid=' || COALESCE(v_header ->> 'kid', '<null>')
  );
END;
$$;

-- T08: scopes derived from RBAC; caller-supplied scopes ignored.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_token text;
  v_payload jsonb;
  v_scopes jsonb;
  v_passed boolean;
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token(p_scopes := ARRAY['ai.forge']);
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_scopes := v_payload -> 'scopes';

  v_passed := v_scopes @> '["ai.access"]'::jsonb
    AND NOT (v_scopes @> '["ai.forge"]'::jsonb);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T08 scopes derived from RBAC and unaffected by caller-supplied scopes',
    v_passed,
    'scopes=' || COALESCE(v_scopes::text, '<null>')
  );
END;
$$;

-- T08b: deliberate omissions — no patient/quota/model/provider keys in payload.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_token text;
  v_payload jsonb;
  v_forbidden text[] := ARRAY['patient_id', 'patient', 'quota', 'model', 'provider'];
  v_key text;
  v_present text[] := ARRAY[]::text[];
  v_passed boolean;
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);

  FOREACH v_key IN ARRAY v_forbidden LOOP
    IF v_payload ? v_key THEN
      v_present := array_append(v_present, v_key);
    END IF;
  END LOOP;

  v_passed := cardinality(v_present) = 0;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T08b deliberate omissions absent from payload',
    v_passed,
    CASE
      WHEN v_passed THEN 'no forbidden keys'
      ELSE 'present=' || array_to_string(v_present, ',')
    END
  );
END;
$$;

-- T10: issuance ledger row written for the minted jti.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_token text;
  v_payload jsonb;
  v_jti text;
  v_row_count int;
  v_passed boolean;
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_jti := v_payload ->> 'jti';

  PERFORM set_config('role', 'postgres', true);

  SELECT count(*)::int
  INTO v_row_count
  FROM ai_internal.ai_token_issuance i
  WHERE i.jti = v_jti::uuid
    AND i.is_deleted = false;

  v_passed := v_row_count = 1;

  INSERT INTO ai_token_issuer_results VALUES (
    'T10 issuance row written',
    v_passed,
    'jti=' || COALESCE(v_jti, '<null>') || ' rows=' || v_row_count::text
  );
END;
$$;

-- T11: third mint with ceiling=2 raises RATE_LIMITED; different actor can still mint.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_ceiling int := 2;
  v_token text;
  v_i int;
  v_limited_code text;
  v_admin_token text;
  v_admin_ok boolean := false;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM ai_internal.ai_token_issuance;
  INSERT INTO ai_internal.app_settings (key, value_json)
  VALUES
    ('ai.issuer.rate_limit.ceiling', to_jsonb(v_ceiling)),
    ('ai.issuer.rate_limit.window_seconds', to_jsonb(3600))
  ON CONFLICT (key) DO UPDATE
  SET value_json = EXCLUDED.value_json;

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);

  FOR v_i IN 1..v_ceiling LOOP
    v_token := public.issue_ai_token();
    IF v_token IS NULL OR v_token = '' THEN
      RAISE EXCEPTION 'expected mint % of % to succeed', v_i, v_ceiling;
    END IF;
  END LOOP;

  v_limited_code := pg_temp.capture_issue_error();

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  BEGIN
    v_admin_token := public.issue_ai_token();
    v_admin_ok := v_admin_token IS NOT NULL AND v_admin_token <> '';
  EXCEPTION
    WHEN OTHERS THEN
      v_admin_ok := false;
      v_admin_token := SQLERRM;
  END;

  v_passed := v_limited_code = 'RATE_LIMITED' AND v_admin_ok;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_internal.app_settings (key, value_json)
  VALUES
    ('ai.issuer.rate_limit.ceiling', '100'::jsonb),
    ('ai.issuer.rate_limit.window_seconds', '3600'::jsonb)
  ON CONFLICT (key) DO UPDATE
  SET value_json = EXCLUDED.value_json;

  INSERT INTO ai_token_issuer_results VALUES (
    'T11 issuer rate limit trips',
    v_passed,
    'ceiling=' || v_ceiling::text
      || ' limited_code=' || COALESCE(v_limited_code, '<null>')
      || ' admin_ok=' || v_admin_ok::text
      || ' admin_detail=' || COALESCE(left(v_admin_token, 64), '<null>')
  );
END;
$$;

-- T12: exp within configured minutes of iat.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_token text;
  v_payload jsonb;
  v_iat numeric;
  v_exp numeric;
  v_delta numeric;
  v_lifetime_minutes numeric;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_internal.app_settings (key, value_json)
  VALUES
    ('ai.issuer.rate_limit.ceiling', '100'::jsonb),
    ('ai.issuer.rate_limit.window_seconds', '3600'::jsonb)
  ON CONFLICT (key) DO UPDATE
  SET value_json = EXCLUDED.value_json;
  DELETE FROM ai_internal.ai_token_issuance;

  SELECT (value_json)::numeric
  INTO v_lifetime_minutes
  FROM ai_internal.app_settings
  WHERE key = 'ai.aat.lifetime_minutes';

  IF v_lifetime_minutes IS NULL OR v_lifetime_minutes <= 0 THEN
    v_lifetime_minutes := 15;
  END IF;

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);
  v_iat := (v_payload ->> 'iat')::numeric;
  v_exp := (v_payload ->> 'exp')::numeric;
  v_delta := v_exp - v_iat;

  v_passed := v_delta > 0
    AND v_delta <= (v_lifetime_minutes * 60);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T12 exp within configured minutes',
    v_passed,
    'delta_seconds=' || v_delta::text
      || ' configured_minutes=' || v_lifetime_minutes::text
  );
END;
$$;

-- T13: STAFF_NOT_FOUND for auth user with no staff_members row.
DO $$
DECLARE
  v_nostaff_user uuid := 'c3000000-0000-4000-8000-000000000001';
  v_code text;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM auth.users WHERE id = v_nostaff_user;
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_nostaff_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'ai-issuer-nostaff',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  PERFORM pg_temp.set_authenticated_session(v_nostaff_user);
  v_code := pg_temp.capture_issue_error();
  v_passed := v_code = 'STAFF_NOT_FOUND';

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T13 STAFF_NOT_FOUND',
    v_passed,
    'code=' || COALESCE(v_code, '<null>')
  );
END;
$$;

-- T14: BRANCH_NOT_FOUND for staff with no branch assignment.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_nobranch_user uuid := 'c4000000-0000-4000-8000-000000000001';
  v_nobranch_staff uuid := 'c5000000-0000-4000-8000-000000000001';
  v_code text;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.staff_branch_assignments WHERE staff_member_id = v_nobranch_staff;
  DELETE FROM public.staff_members WHERE id = v_nobranch_staff;
  DELETE FROM auth.users WHERE id = v_nobranch_user;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  VALUES (
    v_nobranch_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'ai-issuer-nobranch',
    extensions.crypt('test-password', extensions.gen_salt('bf')),
    now(),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.staff_members (id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by)
  VALUES (
    v_nobranch_staff,
    v_nobranch_user,
    'AI Issuer No Branch',
    'doctor',
    false,
    v_bootstrap_user,
    v_bootstrap_user
  )
  ON CONFLICT (id) DO NOTHING;

  PERFORM pg_temp.set_authenticated_session(v_nobranch_user);
  v_code := pg_temp.capture_issue_error();
  v_passed := v_code = 'BRANCH_NOT_FOUND';

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T14 BRANCH_NOT_FOUND',
    v_passed,
    'code=' || COALESCE(v_code, '<null>')
  );
END;
$$;

-- T15: INSTALLATION_NOT_ENROLLED when no keys remain.
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_result public.rpc_result;
  v_code text;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM ai_internal.ai_token_issuance WHERE true;
  DELETE FROM ai_internal.installation_keys WHERE true;

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_code := pg_temp.capture_issue_error();
  v_passed := v_code = 'INSTALLATION_NOT_ENROLLED';

  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  v_result := public.enroll_installation_keypair();
  IF NOT v_result.success THEN
    RAISE EXCEPTION 're-enroll after T15 failed: %', COALESCE(v_result.error_code, '<null>');
  END IF;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T15 INSTALLATION_NOT_ENROLLED',
    v_passed,
    'code=' || COALESCE(v_code, '<null>')
  );
END;
$$;

-- T16: AI_ACCESS_DENIED when doctor ai.* grants temporarily revoked.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_code text;
  v_passed boolean;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.roles_permissions
  SET is_granted = false, updated_at = now()
  WHERE role = 'doctor'
    AND permission_key LIKE 'ai.%'
    AND is_deleted = false;

  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_code := pg_temp.capture_issue_error();
  v_passed := v_code = 'AI_ACCESS_DENIED';

  PERFORM set_config('role', 'postgres', true);
  UPDATE public.roles_permissions
  SET is_granted = true, updated_at = now()
  WHERE role = 'doctor'
    AND permission_key LIKE 'ai.%'
    AND is_deleted = false;

  INSERT INTO ai_token_issuer_results VALUES (
    'T16 AI_ACCESS_DENIED',
    v_passed,
    'code=' || COALESCE(v_code, '<null>')
  );
END;
$$;

-- Final hygiene: restore rate-limit settings to seed defaults.
DO $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_internal.app_settings (key, value_json)
  VALUES
    ('ai.issuer.rate_limit.ceiling', '100'::jsonb),
    ('ai.issuer.rate_limit.window_seconds', '3600'::jsonb)
  ON CONFLICT (key) DO UPDATE
  SET value_json = EXCLUDED.value_json;
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM ai_token_issuer_results WHERE NOT passed;
  IF v_failures > 0 THEN
    RAISE EXCEPTION 'ai_token_issuer failed: %', (
      SELECT string_agg(test_name || ': ' || detail, '; ')
      FROM ai_token_issuer_results
      WHERE NOT passed
    );
  END IF;
END;
$$;

SELECT test_name, passed, detail FROM ai_token_issuer_results ORDER BY test_name;

ROLLBACK;

