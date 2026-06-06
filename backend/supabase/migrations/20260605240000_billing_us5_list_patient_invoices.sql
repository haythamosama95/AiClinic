-- V1-6 US5: patient profile billing tab query.

CREATE OR REPLACE FUNCTION auth_internal.list_patient_invoices(
  p_patient_id uuid,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_patient_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'patient_id is required.');
  END IF;

  RETURN auth_internal.list_invoices(
    jsonb_build_object('patient_id', p_patient_id::text),
    p_limit,
    p_offset
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list invoices.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_patient_invoices(
  p_patient_id uuid,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_patient_invoices(p_patient_id, p_limit, p_offset);
$$;

GRANT EXECUTE ON FUNCTION public.list_patient_invoices(uuid, int, int) TO authenticated;
