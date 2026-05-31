-- V1-5 US3 follow-up: org-level specialty form schema configuration RPC.

-- -----------------------------------------------------------------------------
-- auth_internal.validate_specialty_form_schema_json
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.validate_specialty_form_schema_json(p_schema_json jsonb)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
  v_prop jsonb;
  v_type text;
  v_required jsonb;
BEGIN
  IF p_schema_json IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT';
  END IF;

  IF jsonb_typeof(p_schema_json) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_INPUT';
  END IF;

  IF p_schema_json = '{}'::jsonb THEN
    RETURN;
  END IF;

  IF p_schema_json ? 'type'
    AND COALESCE(p_schema_json ->> 'type', 'object') <> 'object' THEN
    RAISE EXCEPTION 'INVALID_INPUT';
  END IF;

  IF p_schema_json ? 'properties' THEN
    IF jsonb_typeof(p_schema_json -> 'properties') <> 'object' THEN
      RAISE EXCEPTION 'INVALID_INPUT';
    END IF;

    FOR v_key IN
      SELECT jsonb_object_keys(p_schema_json -> 'properties')
    LOOP
      v_prop := p_schema_json -> 'properties' -> v_key;
      IF jsonb_typeof(v_prop) <> 'object' THEN
        RAISE EXCEPTION 'INVALID_INPUT';
      END IF;

      v_type := COALESCE(v_prop ->> 'type', 'string');
      IF v_type NOT IN ('string', 'number', 'integer', 'boolean') THEN
        RAISE EXCEPTION 'INVALID_INPUT';
      END IF;

      IF v_prop ? 'enum' AND jsonb_typeof(v_prop -> 'enum') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_INPUT';
      END IF;
    END LOOP;
  END IF;

  IF p_schema_json ? 'required' THEN
    IF jsonb_typeof(p_schema_json -> 'required') <> 'array' THEN
      RAISE EXCEPTION 'INVALID_INPUT';
    END IF;

    v_required := p_schema_json -> 'required';
    FOR v_key IN
      SELECT jsonb_array_elements_text(v_required)
    LOOP
      IF p_schema_json ? 'properties'
        AND NOT (p_schema_json -> 'properties' ? v_key) THEN
        RAISE EXCEPTION 'INVALID_INPUT';
      END IF;
    END LOOP;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.set_specialty_form_schema
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.set_specialty_form_schema(p_schema_json jsonb)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_setting_id uuid;
  v_schema jsonb;
BEGIN
  PERFORM auth_internal.assert_owner_or_administrator();
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  v_schema := COALESCE(p_schema_json, '{}'::jsonb);

  BEGIN
    PERFORM auth_internal.validate_specialty_form_schema_json(v_schema);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Specialty form schema is not valid.');
  END;

  SELECT s.id
  INTO v_setting_id
  FROM public.app_settings s
  WHERE s.organization_id = v_org_id
    AND s.branch_id IS NULL
    AND s.key = 'specialty.form_schema_json'
    AND s.is_deleted = false
  LIMIT 1;

  IF v_setting_id IS NULL THEN
    INSERT INTO public.app_settings (organization_id, branch_id, key, value_json, created_by, updated_by)
    VALUES (v_org_id, NULL, 'specialty.form_schema_json', v_schema, auth.uid(), auth.uid());
  ELSE
    UPDATE public.app_settings s
    SET
      value_json = v_schema,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE s.id = v_setting_id;
  END IF;

  RETURN public.rpc_success(jsonb_build_object('schema_json', v_schema));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to change specialty form settings.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- public RPC wrapper
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_specialty_form_schema(p_schema_json jsonb)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_specialty_form_schema(p_schema_json);
$$;

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION auth_internal.validate_specialty_form_schema_json(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.set_specialty_form_schema(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_specialty_form_schema(jsonb) TO authenticated;
