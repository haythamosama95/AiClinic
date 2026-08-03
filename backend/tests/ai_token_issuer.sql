-- B1 AAT issuer contract tests (T07–T12).
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

-- T09: absent or expired session rejected (runs before enrollment; needs only the issuer RPC).
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_token text;
  v_absent_rejected boolean := false;
  v_expired_rejected boolean := false;
  v_detail text := '';
BEGIN
  IF to_regprocedure('public.issue_ai_token(text[])') IS NULL
     AND to_regprocedure('public.issue_ai_token()') IS NULL THEN
    RAISE EXCEPTION 'public.issue_ai_token is not installed yet';
  END IF;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
  BEGIN
    v_token := public.issue_ai_token();
  EXCEPTION
    WHEN undefined_function THEN
      RAISE;
    WHEN OTHERS THEN
      v_absent_rejected := true;
      v_detail := v_detail || 'absent=' || SQLERRM || '; ';
  END;

  PERFORM pg_temp.set_authenticated_session(
    v_doctor_user,
    (extract(epoch from now() - interval '1 hour'))::bigint
  );
  BEGIN
    v_token := public.issue_ai_token();
  EXCEPTION
    WHEN undefined_function THEN
      RAISE;
    WHEN OTHERS THEN
      v_expired_rejected := true;
      v_detail := v_detail || 'expired=' || SQLERRM;
  END;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T09 expired or absent session rejected',
    v_absent_rejected AND v_expired_rejected,
    NULLIF(v_detail, '')
  );
END;
$$;

-- Enroll installation keypair once for mint tests (T07, T08, T10, T11, T12).
DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);
  PERFORM public.enroll_installation_keypair();
END;
$$;

-- T07: every §5.6 claim populated on one minted AAT.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_token text;
  v_payload jsonb;
  v_claim text;
  v_claims text[] := ARRAY[
    'iss', 'aud', 'sub', 'org', 'branch', 'role', 'scopes', 'jti', 'iat', 'exp', 'ver'
  ];
  v_missing text[] := ARRAY[]::text[];
  v_passed boolean;
BEGIN
  PERFORM pg_temp.set_authenticated_session(v_doctor_user);
  v_token := public.issue_ai_token();
  v_payload := pg_temp.decode_jws_payload(v_token);

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

  v_passed := cardinality(v_missing) = 0;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T07 all section 5.6 claims populated',
    v_passed,
    CASE
      WHEN v_passed THEN 'all claims present'
      ELSE 'missing=' || array_to_string(v_missing, ',')
    END
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

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T10 issuance row written',
    v_passed,
    'jti=' || COALESCE(v_jti, '<null>') || ' rows=' || v_row_count::text
  );
END;
$$;

-- T11: issuer rate limit trips beyond the configured ceiling.
DO $$
DECLARE
  v_doctor_user uuid := 'c1000000-0000-4000-8000-000000000001';
  v_ceiling int := 2;
  v_token text;
  v_i int;
  v_rate_limited boolean := false;
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

  BEGIN
    v_token := public.issue_ai_token();
  EXCEPTION WHEN OTHERS THEN
    v_rate_limited := true;
  END;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_token_issuer_results VALUES (
    'T11 issuer rate limit trips',
    v_rate_limited,
    'ceiling=' || v_ceiling::text || ' limited=' || v_rate_limited::text
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
  UPDATE ai_internal.app_settings
  SET value_json = '100'::jsonb
  WHERE key = 'ai.issuer.rate_limit.ceiling';
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

COMMIT;

SELECT test_name, passed, detail FROM ai_token_issuer_results ORDER BY test_name;
