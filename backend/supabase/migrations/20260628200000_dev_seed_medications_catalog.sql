-- Dev-only bulk import for organization medication catalog (used by Flutter Fill Dummy Clinic).

CREATE OR REPLACE FUNCTION auth_internal.dev_seed_medications_catalog(p_names text[])
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_env text;
  v_org_id uuid;
  v_inserted int;
BEGIN
  v_env := current_setting('app.environment', true);
  IF v_env IS NOT NULL AND v_env NOT IN ('development', 'local', 'test') THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'dev_seed_medications_catalog can only run in development/local/test environments.'
    );
  END IF;

  PERFORM auth_internal.assert_bootstrap_admin();
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF p_names IS NULL OR cardinality(p_names) = 0 THEN
    RETURN public.rpc_success(jsonb_build_object('inserted', 0, 'requested', 0));
  END IF;

  INSERT INTO public.medications (organization_id, name, created_by, updated_by)
  SELECT v_org_id, seeds.v_name, auth.uid(), auth.uid()
  FROM (
    SELECT DISTINCT ON (lower(trim(n))) trim(n) AS v_name
    FROM unnest(p_names) AS n
    WHERE trim(n) <> '' AND length(trim(n)) <= 200
  ) AS seeds
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.medications m
    WHERE m.organization_id = v_org_id
      AND m.is_deleted = false
      AND lower(trim(m.name)) = lower(seeds.v_name)
  );

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  RETURN public.rpc_success(
    jsonb_build_object(
      'inserted', v_inserted,
      'requested', cardinality(p_names)
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'NOT_BOOTSTRAP_ADMIN' THEN
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may seed medications.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_seed_medications_catalog(p_names text[])
RETURNS public.rpc_result
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$ SELECT auth_internal.dev_seed_medications_catalog(p_names); $$;

GRANT EXECUTE ON FUNCTION auth_internal.dev_seed_medications_catalog(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dev_seed_medications_catalog(text[]) TO authenticated;
