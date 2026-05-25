-- Fix 37: Rename audit_log.timestamp to created_at for naming consistency.
-- Also recreates the index and updates cleanup_audit_log to reference the new column name.

ALTER TABLE public.audit_log RENAME COLUMN "timestamp" TO created_at;

-- Recreate index with consistent name (the old audit_log_timestamp_idx may
-- have been auto-renamed by the column rename, but let's be explicit)
DROP INDEX IF EXISTS public.audit_log_timestamp_idx;
CREATE INDEX audit_log_created_at_idx ON public.audit_log (created_at DESC);

-- Redefine cleanup_audit_log to use the renamed column
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
  WHERE created_at < v_cutoff;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

  RETURN public.rpc_success(
    jsonb_build_object(
      'deleted_count', v_deleted_count,
      'cutoff_date', v_cutoff
    )
  );
END;
$$;
