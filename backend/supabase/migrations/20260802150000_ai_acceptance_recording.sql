-- =============================================================================
-- F2 slice: AI acceptance recording RPC, registry, and ai_accepted_output.
-- =============================================================================

CREATE TABLE ai_internal.acceptance_targets (
  target_key text PRIMARY KEY,
  domain_function text NOT NULL,
  table_name text NOT NULL
);

-- F2 needs service_role read of the registry; B1 no longer grants schema USAGE broadly.
GRANT USAGE ON SCHEMA ai_internal TO service_role;
REVOKE ALL ON TABLE ai_internal.acceptance_targets FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE ai_internal.acceptance_targets TO postgres, service_role;

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

-- -----------------------------------------------------------------------------
-- auth_internal.record_ai_acceptance
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
BEGIN
  IF p_domain_function = 'save_visit_documentation' THEN
    RETURN public.save_visit_documentation(
      (p_target_args ->> 'p_visit_id')::uuid,
      p_target_args ->> 'p_complaint',
      p_target_args ->> 'p_history',
      p_target_args ->> 'p_examination',
      p_target_args ->> 'p_diagnosis',
      p_target_args ->> 'p_plan',
      (p_target_args ->> 'p_expected_updated_at')::timestamptz
    );
  END IF;

  RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
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

  v_domain_result := auth_internal.invoke_acceptance_domain_rpc(
    v_target.domain_function,
    p_target_args
  );

  IF NOT v_domain_result.success THEN
    RETURN v_domain_result;
  END IF;

  v_org_id := public.jwt_organization_id();
  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF v_target.domain_function = 'save_visit_documentation' THEN
    v_record_id := (p_target_args ->> 'p_visit_id')::uuid;
    SELECT v.branch_id
    INTO v_branch_id
    FROM public.visits v
    WHERE v.id = v_record_id
      AND v.is_deleted = false;
  ELSE
    RETURN public.rpc_error('INTERNAL_ERROR', 'Domain function is not configured.');
  END IF;

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
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to record AI acceptance.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_ai_acceptance(
  p_request_reference text,
  p_target_key text,
  p_target_args jsonb
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT auth_internal.record_ai_acceptance(
    p_request_reference,
    p_target_key,
    p_target_args
  );
$$;

GRANT EXECUTE ON FUNCTION auth_internal.invoke_acceptance_domain_rpc(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.record_ai_acceptance(text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_ai_acceptance(text, text, jsonb) TO authenticated;
