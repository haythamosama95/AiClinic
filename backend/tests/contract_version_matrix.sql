-- P7.3 contract version matrix RPC cases (E2E-P7.3-01).
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/contract_version_matrix.sql

BEGIN;

CREATE TEMP TABLE contract_version_matrix_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

CREATE OR REPLACE FUNCTION pg_temp.capture_contract_version_error(p_sql text)
RETURNS TABLE (
  raised boolean,
  message text,
  detail text
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_exc_detail text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    RETURN QUERY SELECT false, '<none>'::text, '<none>'::text;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_exc_detail = PG_EXCEPTION_DETAIL;
      RETURN QUERY SELECT true, SQLERRM, COALESCE(v_exc_detail, '<null>');
  END;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_authenticated_session(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.matrix_admin_fixture()
RETURNS TABLE (
  user_id uuid,
  staff_id uuid,
  org_id uuid,
  branch_id uuid
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000101';
  v_bootstrap_staff uuid := 'b0000000-0000-4000-8000-000000000101';
  v_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM pg_temp.set_authenticated_session(v_bootstrap_user);

  v_result := public.bootstrap_create_organization(
    'Contract Version Matrix Clinic',
    '{}'::jsonb,
    NULL,
    'EGP',
    'UTC'
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'fixture bootstrap_create_organization failed: %', v_result.error_code;
  END IF;
  v_org_id := (v_result.data ->> 'organization_id')::uuid;

  v_result := public.bootstrap_create_branch(
    v_org_id,
    'Contract Version Matrix Branch',
    NULL,
    NULL,
    'CVMX',
    NULL
  );
  IF NOT v_result.success THEN
    RAISE EXCEPTION 'fixture bootstrap_create_branch failed: %', v_result.error_code;
  END IF;
  v_branch_id := (v_result.data ->> 'branch_id')::uuid;

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO ai_internal.membership (user_id, organization_id, role)
  SELECT sm.auth_user_id, v_org_id, sm.role
  FROM public.staff_members sm
  WHERE sm.auth_user_id = v_bootstrap_user
    AND sm.is_deleted = false
  ON CONFLICT (user_id, organization_id) DO NOTHING;

  RETURN QUERY SELECT v_bootstrap_user, v_bootstrap_staff, v_org_id, v_branch_id;
END;
$$;

-- Transaction-local N+1 public gates: accepted pair (1, 2), rpc_result refusal contract_version 2.
CREATE OR REPLACE FUNCTION public.get_ai_status(p_contract_version integer DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
BEGIN
  IF p_contract_version IS NULL OR p_contract_version NOT IN (1, 2) THEN
    RETURN (
      false,
      jsonb_build_object('accepted_versions', jsonb_build_array(1, 2)),
      'CONTRACT_VERSION_UNSUPPORTED',
      'Contract version is not supported.',
      2
    )::public.rpc_result;
  END IF;

  RETURN auth_internal.get_ai_status(p_contract_version);
END;
$$;

CREATE OR REPLACE FUNCTION public.request_ai_status_refresh(p_contract_version integer DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
BEGIN
  IF p_contract_version IS NULL OR p_contract_version NOT IN (1, 2) THEN
    RETURN (
      false,
      jsonb_build_object('accepted_versions', jsonb_build_array(1, 2)),
      'CONTRACT_VERSION_UNSUPPORTED',
      'Contract version is not supported.',
      2
    )::public.rpc_result;
  END IF;

  RETURN auth_internal.request_ai_status_refresh(p_contract_version);
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_billing_token(p_contract_version integer DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
BEGIN
  IF p_contract_version IS NULL OR p_contract_version NOT IN (1, 2) THEN
    RETURN (
      false,
      jsonb_build_object('accepted_versions', jsonb_build_array(1, 2)),
      'CONTRACT_VERSION_UNSUPPORTED',
      'Contract version is not supported.',
      2
    )::public.rpc_result;
  END IF;

  RETURN auth_internal.issue_billing_token(p_contract_version);
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_ai_token(p_contract_version integer DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
BEGIN
  IF p_contract_version IS NULL OR p_contract_version NOT IN (1, 2) THEN
    RAISE EXCEPTION 'CONTRACT_VERSION_UNSUPPORTED'
      USING DETAIL = '{"accepted_versions":[1,2]}';
  END IF;

  RETURN auth_internal.issue_ai_token(p_contract_version);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_ai_billing_status(p_contract_version integer DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal, ai_internal, extensions
AS $$
DECLARE
  v_org uuid;
  v_status public.rpc_result;
  v_coverage ai_internal.clinic_ai_coverage%ROWTYPE;
  v_subscription_ref text;
  v_hash bytea;
  v_alphabet text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_encoded text := '';
  v_buffer bigint := 0;
  v_bits integer := 0;
  v_i integer;
  v_byte integer;
  v_index integer;
BEGIN
  IF p_contract_version IS NULL OR p_contract_version NOT IN (1, 2) THEN
    RETURN (
      false,
      jsonb_build_object('accepted_versions', jsonb_build_array(1, 2)),
      'CONTRACT_VERSION_UNSUPPORTED',
      'Contract version is not supported.',
      2
    )::public.rpc_result;
  END IF;

  IF public.current_membership_role() IS DISTINCT FROM 'administrator' THEN
    RETURN public.rpc_error(
      'FORBIDDEN_ROLE',
      'Only administrators can view billing status.',
      p_contract_version
    );
  END IF;

  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.', p_contract_version);
  END IF;

  v_status := auth_internal.get_ai_status(p_contract_version);
  IF NOT v_status.success THEN
    RETURN v_status;
  END IF;

  v_hash := extensions.digest('sub-ref:' || v_org::text, 'sha256');
  FOR v_i IN 0..(length(v_hash) - 1) LOOP
    v_byte := get_byte(v_hash, v_i);
    v_buffer := (v_buffer << 8) | v_byte;
    v_bits := v_bits + 8;
    WHILE v_bits >= 5 LOOP
      v_bits := v_bits - 5;
      v_index := ((v_buffer >> v_bits) & 31)::integer;
      v_encoded := v_encoded || substr(v_alphabet, v_index + 1, 1);
    END LOOP;
  END LOOP;
  IF v_bits > 0 THEN
    v_index := ((v_buffer << (5 - v_bits)) & 31)::integer;
    v_encoded := v_encoded || substr(v_alphabet, v_index + 1, 1);
  END IF;
  v_subscription_ref := 'AIC-' || left(v_encoded, 8);

  SELECT *
  INTO v_coverage
  FROM ai_internal.clinic_ai_coverage c
  WHERE c.organization_id = v_org;

  IF FOUND THEN
    RETURN public.rpc_success(
      v_status.data || jsonb_build_object(
        'plan_display_name', v_coverage.plan_display_name,
        'starts_at', v_coverage.starts_at,
        'ends_at', v_coverage.ends_at,
        'grace_ends_at', v_coverage.grace_ends_at,
        'allowance', v_coverage.allowance,
        'used', v_coverage.used,
        'queued_count', v_coverage.queued_count,
        'held_count', v_coverage.held_count,
        'subscription_ref', v_subscription_ref,
        'abo_base_url', auth_internal.ai_app_setting_text(
          'ai.abo_base_url',
          'http://127.0.0.1:8788'
        )
      ),
      p_contract_version
    );
  END IF;

  RETURN public.rpc_success(
    v_status.data || jsonb_build_object(
      'plan_display_name', NULL,
      'starts_at', NULL,
      'ends_at', NULL,
      'grace_ends_at', NULL,
      'allowance', NULL,
      'used', NULL,
      'queued_count', NULL,
      'held_count', NULL,
      'subscription_ref', v_subscription_ref,
      'abo_base_url', auth_internal.ai_app_setting_text(
        'ai.abo_base_url',
        'http://127.0.0.1:8788'
      )
    ),
    p_contract_version
  );
END;
$$;

-- E2E-P7.3-01: RPC receiver at N+1 accepts 1 and 2 and refuses before auth or write.
DO $$
DECLARE
  v_admin_user uuid;
  v_admin_staff uuid;
  v_org_id uuid;
  v_branch_id uuid;
  v_rows_before bigint;
  v_rows_after bigint;
  v_status_v2 public.rpc_result;
  v_status_v1 public.rpc_result;
  v_refused_v3 public.rpc_result;
  v_refused_v0 public.rpc_result;
  v_refused_null public.rpc_result;
  v_refresh_refused public.rpc_result;
  v_billing_refused public.rpc_result;
  v_v3_raise boolean;
  v_v3_message text;
  v_v3_detail text;
  v_null_raise boolean;
  v_null_message text;
  v_passed boolean;
  v_detail text;
BEGIN
  IF to_regprocedure('public.issue_ai_token(integer)') IS NULL THEN
    INSERT INTO contract_version_matrix_results VALUES (
      'E2E-P7.3-01 RPC gates accept (1, 2) and refuse unsupported before auth',
      false,
      'versioned RPC functions are absent'
    );
    RETURN;
  END IF;

  SELECT f.user_id, f.staff_id, f.org_id, f.branch_id
  INTO v_admin_user, v_admin_staff, v_org_id, v_branch_id
  FROM pg_temp.matrix_admin_fixture() f;

  PERFORM set_config('role', 'postgres', true);
  IF to_regclass('ai_internal.ai_token_issuance') IS NOT NULL THEN
    SELECT count(*) INTO v_rows_before FROM ai_internal.ai_token_issuance;
  ELSE
    v_rows_before := 0;
  END IF;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_admin_user::text,
      'role', 'authenticated',
      'organization_id', v_org_id::text,
      'branch_ids', v_branch_id::text,
      'staff_member_id', v_admin_staff::text,
      'staff_role', 'administrator',
      'setup_required', false
    )::text,
    true
  );

  v_status_v2 := public.get_ai_status(2);
  v_status_v1 := public.get_ai_status(1);
  v_refused_v3 := public.get_ai_status(3);
  v_refused_v0 := public.get_ai_status(0);
  v_refused_null := public.get_ai_status(NULL);
  v_refresh_refused := public.request_ai_status_refresh(3);
  v_billing_refused := public.get_ai_billing_status(0);

  SELECT r.raised, r.message, r.detail
  INTO v_v3_raise, v_v3_message, v_v3_detail
  FROM pg_temp.capture_contract_version_error('SELECT public.issue_ai_token(3)') r;

  SELECT r.raised, r.message, r.detail
  INTO v_null_raise, v_null_message, v_v3_detail
  FROM pg_temp.capture_contract_version_error('SELECT public.issue_ai_token()') r;

  PERFORM set_config('role', 'postgres', true);
  IF to_regclass('ai_internal.ai_token_issuance') IS NOT NULL THEN
    SELECT count(*) INTO v_rows_after FROM ai_internal.ai_token_issuance;
  ELSE
    v_rows_after := 0;
  END IF;

  v_passed := v_status_v2.success
    AND v_status_v2.contract_version = 2
    AND v_status_v1.success
    AND v_status_v1.contract_version = 1
    AND NOT v_refused_v3.success
    AND v_refused_v3.error_code = 'CONTRACT_VERSION_UNSUPPORTED'
    AND v_refused_v3.contract_version = 2
    AND (v_refused_v3.data -> 'accepted_versions') = jsonb_build_array(1, 2)
    AND NOT v_refused_v0.success
    AND v_refused_v0.error_code = 'CONTRACT_VERSION_UNSUPPORTED'
    AND (v_refused_v0.data -> 'accepted_versions') = jsonb_build_array(1, 2)
    AND NOT v_refused_null.success
    AND v_refused_null.error_code = 'CONTRACT_VERSION_UNSUPPORTED'
    AND (v_refused_null.data -> 'accepted_versions') = jsonb_build_array(1, 2)
    AND NOT v_refresh_refused.success
    AND v_refresh_refused.error_code = 'CONTRACT_VERSION_UNSUPPORTED'
    AND v_refresh_refused.contract_version = 2
    AND NOT v_billing_refused.success
    AND v_billing_refused.error_code = 'CONTRACT_VERSION_UNSUPPORTED'
    AND v_billing_refused.contract_version = 2
    AND v_v3_raise
    AND v_v3_message LIKE '%CONTRACT_VERSION_UNSUPPORTED%'
    AND v_v3_detail LIKE '%accepted_versions%'
    AND v_null_raise
    AND v_null_message LIKE '%CONTRACT_VERSION_UNSUPPORTED%'
    AND v_rows_before = v_rows_after;

  v_detail := 'status_v2=' || COALESCE(v_status_v2.contract_version::text, '<null>')
    || ' status_v1=' || COALESCE(v_status_v1.contract_version::text, '<null>')
    || ' refused_v3_cv=' || COALESCE(v_refused_v3.contract_version::text, '<null>')
    || ' rows_before=' || v_rows_before::text
    || ' rows_after=' || v_rows_after::text;

  INSERT INTO contract_version_matrix_results VALUES (
    'E2E-P7.3-01 RPC gates accept (1, 2) and refuse unsupported before auth',
    v_passed,
    v_detail
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM contract_version_matrix_results WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'contract_version_matrix variant transaction: % failed: %',
      v_failures,
      (
        SELECT string_agg(test_name || '=' || detail, '; ')
        FROM contract_version_matrix_results
        WHERE NOT passed
      );
  END IF;
END;
$$;

ROLLBACK;

BEGIN;

CREATE TEMP TABLE contract_version_matrix_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_refused public.rpc_result;
  v_passed boolean;
BEGIN
  SELECT public.get_ai_status(2) INTO v_refused;
  v_passed := NOT v_refused.success
    AND v_refused.error_code = 'CONTRACT_VERSION_UNSUPPORTED'
    AND (v_refused.data -> 'accepted_versions') = jsonb_build_array(0, 1)
    AND v_refused.contract_version = 1;

  INSERT INTO contract_version_matrix_results VALUES (
    'E2E-P7.3-01 ROLLBACK restores published (0, 1) gates',
    v_passed,
    'error_code=' || COALESCE(v_refused.error_code, '<null>')
      || ' accepted=' || COALESCE((v_refused.data -> 'accepted_versions')::text, '<null>')
      || ' contract_version=' || COALESCE(v_refused.contract_version::text, '<null>')
  );
END;
$$;

DO $$
DECLARE
  v_failures int;
BEGIN
  SELECT count(*) INTO v_failures FROM contract_version_matrix_results WHERE NOT passed;

  IF v_failures > 0 THEN
    RAISE EXCEPTION 'contract_version_matrix post-rollback: % failed: %',
      v_failures,
      (
        SELECT string_agg(test_name || '=' || detail, '; ')
        FROM contract_version_matrix_results
        WHERE NOT passed
      );
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM contract_version_matrix_results ORDER BY test_name;
