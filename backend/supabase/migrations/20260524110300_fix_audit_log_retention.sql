-- Fix 10: Implement audit log retention strategy.
-- Adds index on timestamp for efficient range queries and a cleanup function.

CREATE INDEX IF NOT EXISTS audit_log_timestamp_idx
  ON public.audit_log ("timestamp");

CREATE OR REPLACE FUNCTION auth_internal.cleanup_audit_log(
  p_retention_days int DEFAULT 365
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cutoff timestamptz;
  v_deleted_count int;
BEGIN
  PERFORM auth_internal.assert_bootstrap_admin();

  IF p_retention_days < 1 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Retention days must be at least 1.');
  END IF;

  v_cutoff := now() - (p_retention_days || ' days')::interval;

  DELETE FROM public.audit_log
  WHERE "timestamp" < v_cutoff;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

  RETURN public.rpc_success(
    jsonb_build_object(
      'deleted_count', v_deleted_count,
      'cutoff_date', v_cutoff
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_audit_log(p_retention_days int DEFAULT 365)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
BEGIN
  RETURN auth_internal.cleanup_audit_log(p_retention_days);
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_audit_log(int) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.cleanup_audit_log(int) TO authenticated;
