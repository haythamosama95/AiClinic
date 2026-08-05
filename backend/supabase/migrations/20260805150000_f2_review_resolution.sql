-- =============================================================================
-- F2 review resolution: hardened acceptance recording for DBs that already
-- ran 20260802150000. Idempotent with the updated original (CREATE OR REPLACE /
-- REVOKE / GRANT patterns).
-- =============================================================================

-- Drop incorrect service_role surface on the registry (DEFINER reads as owner).
REVOKE ALL ON TABLE ai_internal.acceptance_targets FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE ai_internal.acceptance_targets TO postgres;

CREATE OR REPLACE FUNCTION auth_internal.invoke_acceptance_domain_rpc(
  p_domain_function text,
  p_target_args jsonb
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_oid oid;
  v_argnames text[];
  v_argtypes oidvector;
  v_nargs int;
  v_parts text[] := ARRAY[]::text[];
  v_i int;
  v_sql text;
  v_success boolean;
  v_data jsonb;
  v_error_code text;
  v_error_message text;
BEGIN
  IF p_domain_function IS NULL OR length(trim(p_domain_function)) = 0 THEN
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM ai_internal.acceptance_targets t
    WHERE t.domain_function = p_domain_function
  ) THEN
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

  SELECT p.oid, p.proargnames, p.proargtypes
  INTO v_oid, v_argnames, v_argtypes
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = p_domain_function
    AND p.prokind = 'f'
    AND pg_get_function_result(p.oid) = 'rpc_result'
  ORDER BY p.oid
  LIMIT 1;

  IF v_oid IS NULL THEN
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

  v_nargs := coalesce(array_length(v_argnames, 1), 0);
  IF v_nargs = 0 THEN
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

  FOR v_i IN 1 .. v_nargs LOOP
    v_parts := v_parts || format(
      '($1->>%L)::%s',
      v_argnames[v_i],
      format_type(v_argtypes[v_i - 1], NULL)
    );
  END LOOP;

  v_sql := format(
    'SELECT r.success, r.data, r.error_code, r.error_message FROM public.%I(%s) AS r',
    p_domain_function,
    array_to_string(v_parts, ', ')
  );
  EXECUTE v_sql
    USING coalesce(p_target_args, '{}'::jsonb)
    INTO v_success, v_data, v_error_code, v_error_message;

  RETURN (v_success, v_data, v_error_code, v_error_message)::public.rpc_result;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.record_ai_acceptance(
  p_request_reference text,
  p_target_key text,
  p_target_args jsonb
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target ai_internal.acceptance_targets%ROWTYPE;
  v_domain_result public.rpc_result;
  v_org_id uuid;
  v_branch_id uuid;
  v_record_id uuid;
  v_acceptance_id uuid;
  v_audit_log_id uuid;
  v_merged_data jsonb;
BEGIN
  IF p_request_reference IS NULL
     OR p_request_reference !~ '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Request reference must use the standard format.');
  END IF;

  SELECT *
  INTO v_target
  FROM ai_internal.acceptance_targets
  WHERE target_key = p_target_key;

  IF NOT FOUND THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Acceptance target is not registered.');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.ai_accepted_output a
    WHERE a.ai_request_reference = p_request_reference
      AND a.table_name = v_target.table_name
  ) THEN
    RETURN public.rpc_error(
      'INVALID_INPUT',
      'This AI output was already accepted for this record.'
    );
  END IF;

  v_org_id := public.jwt_organization_id();
  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  v_domain_result := auth_internal.invoke_acceptance_domain_rpc(
    v_target.domain_function,
    p_target_args
  );

  IF NOT v_domain_result.success THEN
    RETURN v_domain_result;
  END IF;

  v_record_id := coalesce(
    (v_domain_result.data ->> 'record_id')::uuid,
    (v_domain_result.data ->> 'visit_id')::uuid,
    (v_domain_result.data ->> 'id')::uuid
  );
  IF v_record_id IS NULL THEN
    RAISE EXCEPTION 'Domain write did not return a record id.';
  END IF;

  SELECT v.branch_id
  INTO v_branch_id
  FROM public.visits v
  WHERE v.id = v_record_id
    AND v.is_deleted = false;

  v_acceptance_id := gen_random_uuid();

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'ai.acceptance_record',
    v_target.table_name,
    v_record_id,
    jsonb_build_object(
      'ai_request_reference', p_request_reference,
      'acceptance_id', v_acceptance_id
    )
  )
  RETURNING id INTO v_audit_log_id;

  INSERT INTO public.ai_accepted_output (
    id,
    organization_id,
    branch_id,
    table_name,
    record_id,
    ai_request_reference,
    accepted_by,
    audit_log_id
  )
  VALUES (
    v_acceptance_id,
    v_org_id,
    v_branch_id,
    v_target.table_name,
    v_record_id,
    p_request_reference,
    auth.uid(),
    v_audit_log_id
  );

  v_merged_data := coalesce(v_domain_result.data, '{}'::jsonb)
    || jsonb_build_object(
      'acceptance_id', v_acceptance_id,
      'table_name', v_target.table_name,
      'record_id', v_record_id,
      'audit_log_id', v_audit_log_id
    );

  RETURN public.rpc_success(v_merged_data);
END;
$$;

CREATE OR REPLACE FUNCTION public.record_ai_acceptance(
  p_request_reference text,
  p_target_key text,
  p_target_args jsonb
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.record_ai_acceptance(
    p_request_reference,
    p_target_key,
    p_target_args
  );
$$;

REVOKE ALL ON FUNCTION auth_internal.invoke_acceptance_domain_rpc(text, jsonb)
  FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.record_ai_acceptance(text, text, jsonb)
  FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.record_ai_acceptance(text, text, jsonb) TO authenticated;
GRANT SELECT ON TABLE public.ai_accepted_output TO authenticated;
