-- RM36 (R7-PS3): atomic tenant throttle for request_ai_status_refresh.
--
-- Forward override of auth_internal.request_ai_status_refresh(integer) defined in
-- 20261007230000_coverage_feed_puller_status.sql. The earlier body read requested_at and then
-- upserted unconditionally, so two concurrent administrator calls could both pass the ten-second
-- check and both start a pull. The window is now claimed by one conditional INSERT ... ON CONFLICT
-- DO UPDATE: exactly one transaction for an organization returns a row. Role, session, version and
-- rollback behavior are unchanged.

CREATE OR REPLACE FUNCTION auth_internal.request_ai_status_refresh(p_contract_version integer)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, auth_internal, ai_internal
AS $$
DECLARE
  v_org uuid;
  v_requested_at timestamptz;
BEGIN
  PERFORM auth_internal.assert_valid_ai_session();

  IF public.current_membership_role() IS DISTINCT FROM 'administrator' THEN
    RETURN public.rpc_error(
      'FORBIDDEN_ROLE',
      'Only administrators can request status refresh.',
      p_contract_version
    );
  END IF;

  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.', p_contract_version);
  END IF;

  -- Claim the window in one statement. A row is returned only when no request was accepted in the
  -- last ten seconds (equality at exactly ten seconds accepts, per 04 section 3.1).
  INSERT INTO ai_internal.status_refresh AS sr (organization_id, requested_at)
  VALUES (v_org, now())
  ON CONFLICT (organization_id) DO UPDATE
  SET requested_at = EXCLUDED.requested_at
  WHERE sr.requested_at <= now() - interval '10 seconds'
  RETURNING sr.requested_at INTO v_requested_at;

  IF v_requested_at IS NULL THEN
    RETURN public.rpc_error(
      'RATE_LIMITED',
      'Refresh was requested recently.',
      p_contract_version
    );
  END IF;

  PERFORM auth_internal.pull_coverage_feed();

  RETURN public.rpc_success(
    jsonb_build_object('requested_at', v_requested_at),
    p_contract_version
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('UNAUTHENTICATED', 'SESSION_EXPIRED') THEN
      RETURN public.rpc_error(SQLERRM, SQLERRM, p_contract_version);
    END IF;
    RAISE;
END;
$$;
