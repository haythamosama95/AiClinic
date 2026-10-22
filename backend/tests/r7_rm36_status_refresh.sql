-- RM36 (R7-PS3) — administrator status refresh throttle claims one window per organization.
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/r7_rm36_status_refresh.sql
-- The file ends with ROLLBACK: the pull stub below is local to this transaction and fixtures are not kept.
-- Concurrency: this file checks the single-claim outcome sequentially (the second claim in the window
-- is refused). The guarantee rests on one statement: INSERT ... ON CONFLICT ... WHERE. Known gap:
-- simultaneous same-org calls are not tested here or in any other file in this repository.

BEGIN;

CREATE TEMP TABLE r7_rm36_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE TEMP TABLE r7_rm36_pull_calls (
  call_no serial PRIMARY KEY
);

CREATE OR REPLACE FUNCTION pg_temp.r7_set_session(p_user_id uuid, p_org_id uuid)
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
      'exp', extract(epoch FROM now())::bigint + 3600
    )::text,
    true
  );
END;
$$;

-- Local stub: the pull is exercised by its own campaign; here only the call count matters.
CREATE OR REPLACE FUNCTION auth_internal.pull_coverage_feed()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO r7_rm36_pull_calls DEFAULT VALUES;
END;
$$;

DO $$
DECLARE
  v_admin_a uuid := '7a360000-0000-4000-8000-000000000001';
  v_member_a uuid := '7a360000-0000-4000-8000-000000000002';
  v_admin_b uuid := '7a360000-0000-4000-8000-000000000003';
  v_org_a uuid := '7a360000-0000-4000-8000-00000000000a';
  v_org_b uuid := '7a360000-0000-4000-8000-00000000000b';
BEGIN
  PERFORM set_config('role', 'postgres', true);

  DELETE FROM ai_internal.status_refresh WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM ai_internal.membership WHERE organization_id IN (v_org_a, v_org_b);
  DELETE FROM public.staff_members WHERE auth_user_id IN (v_admin_a, v_member_a, v_admin_b);
  DELETE FROM public.organizations WHERE id IN (v_org_a, v_org_b);
  DELETE FROM auth.users WHERE id IN (v_admin_a, v_member_a, v_admin_b);

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  )
  SELECT u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, extensions.crypt('pw-r7-rm36', extensions.gen_salt('bf')), now(), now(), now()
  FROM (VALUES
    (v_admin_a,  'r7-rm36-admin-a'),
    (v_member_a, 'r7-rm36-member-a'),
    (v_admin_b,  'r7-rm36-admin-b')
  ) AS u(id, email);

  INSERT INTO public.staff_members (
    id, auth_user_id, full_name, role, is_bootstrap_admin, created_by, updated_by
  )
  VALUES
    ('7a360000-0000-4000-8000-000000000101', v_admin_a,  'R7 RM36 Admin A',  'administrator', false, v_admin_a, v_admin_a),
    ('7a360000-0000-4000-8000-000000000102', v_member_a, 'R7 RM36 Member A', 'doctor',         false, v_admin_a, v_admin_a),
    ('7a360000-0000-4000-8000-000000000103', v_admin_b,  'R7 RM36 Admin B',  'administrator', false, v_admin_a, v_admin_a);

  INSERT INTO public.organizations (id, name, created_by, updated_by)
  VALUES
    (v_org_a, 'R7 RM36 Org A', v_admin_a, v_admin_a),
    (v_org_b, 'R7 RM36 Org B', v_admin_b, v_admin_b);

  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  VALUES
    (v_admin_a,  v_org_a, 'administrator'),
    (v_member_a, v_org_a, 'doctor'),
    (v_admin_b,  v_org_b, 'administrator');
END;
$$;

DO $$
DECLARE
  v_admin_a uuid := '7a360000-0000-4000-8000-000000000001';
  v_member_a uuid := '7a360000-0000-4000-8000-000000000002';
  v_admin_b uuid := '7a360000-0000-4000-8000-000000000003';
  v_org_a uuid := '7a360000-0000-4000-8000-00000000000a';
  v_org_b uuid := '7a360000-0000-4000-8000-00000000000b';
  v_first public.rpc_result;
  v_second public.rpc_result;
  v_other_org public.rpc_result;
  v_member public.rpc_result;
  v_calls_before bigint;
  v_calls_after bigint;
  v_row_before timestamptz;
  v_row_after timestamptz;
BEGIN
  -- Admin in org A claims the window once: accepted and one pull starts.
  PERFORM pg_temp.r7_set_session(v_admin_a, v_org_a);
  v_first := public.request_ai_status_refresh(1);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r7_rm36_results VALUES (
    'R7-PS3-01 first administrator refresh is accepted and starts one pull',
    v_first.success
      AND (SELECT count(*) FROM r7_rm36_pull_calls) = 1,
    coalesce(v_first.error_code, 'ok')
  );

  -- A second same-org call inside the ten-second window is refused and starts no pull.
  PERFORM pg_temp.r7_set_session(v_admin_a, v_org_a);
  v_second := public.request_ai_status_refresh(1);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r7_rm36_results VALUES (
    'R7-PS3-02 concurrent same-org call in the window is RATE_LIMITED without a pull',
    NOT v_second.success
      AND v_second.error_code = 'RATE_LIMITED'
      AND (SELECT count(*) FROM r7_rm36_pull_calls) = 1,
    coalesce(v_second.error_code, 'ok')
  );

  -- Equality at exactly ten seconds accepts.
  UPDATE ai_internal.status_refresh
  SET requested_at = now() - interval '10 seconds'
  WHERE organization_id = v_org_a;

  PERFORM pg_temp.r7_set_session(v_admin_a, v_org_a);
  v_first := public.request_ai_status_refresh(1);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r7_rm36_results VALUES (
    'R7-PS3-03 refresh at exactly ten seconds is accepted',
    v_first.success AND (SELECT count(*) FROM r7_rm36_pull_calls) = 2,
    coalesce(v_first.error_code, 'ok')
  );

  -- Another organization keeps its own window in the same instant.
  PERFORM pg_temp.r7_set_session(v_admin_b, v_org_b);
  v_other_org := public.request_ai_status_refresh(1);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO r7_rm36_results VALUES (
    'R7-PS3-04 a different organization is accepted within the same instant',
    v_other_org.success AND (SELECT count(*) FROM r7_rm36_pull_calls) = 3,
    coalesce(v_other_org.error_code, 'ok')
  );

  -- A non-administrator is refused before any claim: no row written and no pull.
  SELECT requested_at INTO v_row_before
  FROM ai_internal.status_refresh WHERE organization_id = v_org_a;
  SELECT count(*) INTO v_calls_before FROM r7_rm36_pull_calls;

  PERFORM pg_temp.r7_set_session(v_member_a, v_org_a);
  v_member := public.request_ai_status_refresh(1);

  PERFORM set_config('role', 'postgres', true);
  SELECT requested_at INTO v_row_after
  FROM ai_internal.status_refresh WHERE organization_id = v_org_a;
  SELECT count(*) INTO v_calls_after FROM r7_rm36_pull_calls;

  INSERT INTO r7_rm36_results VALUES (
    'R7-PS3-05 non-administrator refresh is FORBIDDEN_ROLE and leaves the claim and pulls unchanged',
    NOT v_member.success
      AND v_member.error_code = 'FORBIDDEN_ROLE'
      AND v_row_after IS NOT DISTINCT FROM v_row_before
      AND v_calls_after = v_calls_before,
    coalesce(v_member.error_code, 'ok')
  );
END;
$$;

DO $$
DECLARE
  v_failed text;
BEGIN
  SELECT string_agg(test_name || ' (' || coalesce(detail, '') || ')', '; ')
  INTO v_failed
  FROM r7_rm36_results
  WHERE NOT passed;

  IF v_failed IS NOT NULL THEN
    RAISE EXCEPTION 'RM36 status refresh checks failed: %', v_failed;
  END IF;
END;
$$;

SELECT test_name, passed, detail
FROM r7_rm36_results
ORDER BY test_name;

ROLLBACK;
