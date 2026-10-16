-- =============================================================================
-- F2 slice: AI acceptance recording RPC, registry, and ai_accepted_output.
-- =============================================================================

CREATE TABLE ai_internal.acceptance_targets (
  target_key text PRIMARY KEY,
  domain_function text NOT NULL,
  table_name text NOT NULL
);

-- Registry is read only by SECURITY DEFINER RPCs (owner). No service_role surface.
REVOKE ALL ON TABLE ai_internal.acceptance_targets FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE ai_internal.acceptance_targets TO postgres;

INSERT INTO ai_internal.acceptance_targets (target_key, domain_function, table_name)
VALUES ('visit_clinical_notes', 'save_visit_documentation', 'visit_clinical_notes')
ON CONFLICT (target_key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- public.ai_accepted_output
-- -----------------------------------------------------------------------------

CREATE TABLE public.ai_accepted_output (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id),
  branch_id uuid REFERENCES public.branches (id),
  table_name text NOT NULL,
  record_id uuid NOT NULL,
  ai_request_reference text NOT NULL,
  accepted_by uuid NOT NULL REFERENCES auth.users (id),
  accepted_at timestamptz NOT NULL DEFAULT now(),
  audit_log_id uuid NOT NULL REFERENCES public.audit_log (id),
  CONSTRAINT ai_accepted_output_request_reference_format CHECK (
    ai_request_reference ~ '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$'
  ),
  CONSTRAINT ai_accepted_output_unique_domain_reference
    UNIQUE (table_name, record_id, ai_request_reference)
);

CREATE INDEX ai_accepted_output_request_reference_idx
  ON public.ai_accepted_output (ai_request_reference);

CREATE INDEX ai_accepted_output_table_record_idx
  ON public.ai_accepted_output (table_name, record_id);

ALTER TABLE public.ai_accepted_output ENABLE ROW LEVEL SECURITY;

CREATE POLICY ai_accepted_output_select ON public.ai_accepted_output
  FOR SELECT TO authenticated
  USING (
    organization_id = public.jwt_organization_id()
    AND (
      branch_id IS NULL
      OR branch_id = ANY (public.jwt_branch_ids())
    )
  );

GRANT SELECT ON TABLE public.ai_accepted_output TO authenticated;

-- -----------------------------------------------------------------------------
-- auth_internal.invoke_acceptance_domain_rpc — registry-driven dynamic dispatch
-- -----------------------------------------------------------------------------

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

  -- Registry is the only source of which public domain RPC may be invoked.
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

-- -----------------------------------------------------------------------------
-- auth_internal.record_ai_acceptance
-- -----------------------------------------------------------------------------

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

  -- Foreseeable duplicate: reject before the delegated write so the client gets a
  -- clean rpc_result and no domain change is attempted.
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

  -- Organization context is required before any write so a missing claim cannot
  -- leave a delegated domain change committed without provenance.
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

  -- Provenance records the domain row that was written, not the request payload.
  v_record_id := coalesce(
    (v_domain_result.data ->> 'record_id')::uuid,
    (v_domain_result.data ->> 'visit_id')::uuid,
    (v_domain_result.data ->> 'id')::uuid
  );
  IF v_record_id IS NULL THEN
    -- Propagate so the delegated write rolls back with this transaction.
    RAISE EXCEPTION 'Domain write did not return a record id.';
  END IF;

  SELECT v.branch_id
  INTO v_branch_id
  FROM public.visits v
  WHERE v.id = v_record_id
    AND v.is_deleted = false;

  v_acceptance_id := gen_random_uuid();

  -- Post-write exceptions must propagate so the PostgREST transaction aborts and
  -- rolls back the delegated domain write. Do not convert them into RETURN rpc_error.
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

-- Wrapper-gate: only the public INVOKER wrapper is executable by authenticated.
REVOKE ALL ON FUNCTION auth_internal.invoke_acceptance_domain_rpc(text, jsonb)
  FROM PUBLIC, authenticated, anon;
REVOKE ALL ON FUNCTION auth_internal.record_ai_acceptance(text, text, jsonb)
  FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.record_ai_acceptance(text, text, jsonb) TO authenticated;
