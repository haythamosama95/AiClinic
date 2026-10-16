-- =============================================================================
-- P5.2: Coverage feed puller, projection tables, and availability drop.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T008: Extensions, projection tables, feed state singleton, status refresh
-- -----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE TABLE ai_internal.clinic_ai_coverage (
  organization_id uuid PRIMARY KEY,
  installation_id uuid NOT NULL,
  binding_epoch bigint NOT NULL,
  clinic_seq bigint NOT NULL,
  state text NOT NULL,
  reason text,
  term_ref text,
  plan_display_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  grace_ends_at timestamptz,
  allowance integer,
  used integer,
  band text,
  queued_count integer NOT NULL,
  held_count integer NOT NULL,
  suspended boolean NOT NULL,
  event_at timestamptz NOT NULL,
  applied_at timestamptz NOT NULL
);

ALTER TABLE ai_internal.clinic_ai_coverage ENABLE ROW LEVEL SECURITY;

CREATE POLICY clinic_ai_coverage_deny_all ON ai_internal.clinic_ai_coverage
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.clinic_ai_coverage FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE ai_internal.feed_state (
  singleton boolean PRIMARY KEY CHECK (singleton),
  cursor bigint NOT NULL,
  pending_request_id bigint,
  pending_since timestamptz,
  last_success_at timestamptz,
  consecutive_failures integer NOT NULL
);

ALTER TABLE ai_internal.feed_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY feed_state_deny_all ON ai_internal.feed_state
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.feed_state FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO ai_internal.feed_state (
  singleton,
  cursor,
  pending_request_id,
  pending_since,
  last_success_at,
  consecutive_failures
)
VALUES (
  true,
  0,
  NULL,
  NULL,
  NULL,
  0
);

CREATE TABLE ai_internal.status_refresh (
  organization_id uuid PRIMARY KEY,
  requested_at timestamptz NOT NULL
);

ALTER TABLE ai_internal.status_refresh ENABLE ROW LEVEL SECURITY;

CREATE POLICY status_refresh_deny_all ON ai_internal.status_refresh
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.status_refresh FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- T009: Drop clinic-written availability flag
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.set_ai_availability(boolean, text);
DROP FUNCTION IF EXISTS auth_internal.set_ai_availability(boolean, text);
DROP FUNCTION IF EXISTS public.get_ai_availability();
DROP FUNCTION IF EXISTS auth_internal.get_ai_availability();

DELETE FROM ai_internal.app_settings
WHERE key = 'ai.availability';

-- -----------------------------------------------------------------------------
-- T017–T019: Coverage feed pull (request, response checks, ordering upsert)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.pull_coverage_feed()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal, ai_internal, net, extensions
AS $$
DECLARE
  v_feed_state ai_internal.feed_state%ROWTYPE;
  v_response RECORD;
  v_sent_version integer;
  v_platform_url text;
  v_request_url text;
  v_token text;
  v_body jsonb;
  v_header_version text;
  v_request_id bigint;
  v_cursor bigint;
  v_prev_feed_seq bigint;
  v_event jsonb;
  v_snapshot jsonb;
  v_term jsonb;
  v_reason text;
  v_page_valid boolean;
BEGIN
  SELECT *
  INTO v_feed_state
  FROM ai_internal.feed_state
  WHERE singleton = true
  FOR UPDATE;

  IF v_feed_state.pending_request_id IS NOT NULL THEN
    SELECT
      r.id,
      r.status_code,
      r.content,
      r.headers,
      r.timed_out,
      r.error_msg,
      r.created
    INTO v_response
    FROM net._http_response r
    WHERE r.id = v_feed_state.pending_request_id;

    IF NOT FOUND THEN
      IF v_feed_state.pending_since >= now() - interval '5 minutes' THEN
        RETURN;
      END IF;

      UPDATE ai_internal.feed_state
      SET
        pending_request_id = NULL,
        pending_since = NULL,
        consecutive_failures = consecutive_failures + 1
      WHERE singleton = true;
    ELSE
      IF v_response.created < now() - interval '5 minutes' THEN
        UPDATE ai_internal.feed_state
        SET
          pending_request_id = NULL,
          pending_since = NULL,
          consecutive_failures = consecutive_failures + 1
        WHERE singleton = true;
      ELSE
        SELECT (s.value_json->'platformFeed'->>'current')::integer
        INTO v_sent_version
        FROM ai_internal.app_settings s
        WHERE s.key = 'ai.contract_versions'
          AND s.is_deleted = false;

        v_cursor := v_feed_state.cursor;
        v_page_valid := false;

        IF COALESCE(v_response.timed_out, false) THEN
          v_page_valid := false;
        ELSIF v_response.status_code = 200 THEN
          BEGIN
            v_body := v_response.content::jsonb;
          EXCEPTION
            WHEN OTHERS THEN
              v_body := NULL;
          END;

          SELECT value
          INTO v_header_version
          FROM jsonb_each_text(COALESCE(v_response.headers, '{}'::jsonb))
          WHERE lower(key) = 'aip-contract-version'
          LIMIT 1;

          IF v_body IS NOT NULL
            AND (v_body->>'contract_version')::integer = v_sent_version
            AND v_header_version = v_sent_version::text
            AND (v_body->>'after')::bigint = v_cursor
          THEN
            v_prev_feed_seq := v_cursor;
            v_page_valid := true;

            FOR v_event IN
              SELECT value
              FROM jsonb_array_elements(COALESCE(v_body->'events', '[]'::jsonb))
            LOOP
              IF (v_event->>'feed_seq')::bigint <= v_prev_feed_seq THEN
                v_page_valid := false;
                EXIT;
              END IF;

              v_prev_feed_seq := (v_event->>'feed_seq')::bigint;
            END LOOP;
          END IF;
        END IF;

        IF v_page_valid THEN
          FOR v_event IN
            SELECT value
            FROM jsonb_array_elements(COALESCE(v_body->'events', '[]'::jsonb))
          LOOP
            v_snapshot := v_event->'snapshot';
            v_term := v_snapshot->'term';

            IF v_snapshot->>'state' IN ('active', 'grace') THEN
              v_reason := NULL;
            ELSE
              v_reason := v_snapshot->>'reason';
            END IF;

            INSERT INTO ai_internal.clinic_ai_coverage (
              organization_id,
              installation_id,
              binding_epoch,
              clinic_seq,
              state,
              reason,
              term_ref,
              plan_display_name,
              starts_at,
              ends_at,
              grace_ends_at,
              allowance,
              used,
              band,
              queued_count,
              held_count,
              suspended,
              event_at,
              applied_at
            )
            VALUES (
              (v_event->>'org_id')::uuid,
              (v_event->>'installation_id')::uuid,
              (v_event->>'binding_epoch')::bigint,
              (v_event->>'clinic_seq')::bigint,
              v_snapshot->>'state',
              v_reason,
              v_term->>'ref',
              v_term->>'plan_display_name',
              NULLIF(v_term->>'starts_at', '')::timestamptz,
              NULLIF(v_term->>'ends_at', '')::timestamptz,
              NULLIF(v_term->>'grace_ends_at', '')::timestamptz,
              NULLIF(v_term->>'allowance', '')::integer,
              NULLIF(v_term->>'used', '')::integer,
              v_term->>'band',
              COALESCE((v_snapshot->>'queued_count')::integer, 0),
              COALESCE((v_snapshot->>'held_count')::integer, 0),
              COALESCE((v_snapshot->>'suspended')::boolean, false),
              (v_event->>'at')::timestamptz,
              now()
            )
            ON CONFLICT (organization_id) DO UPDATE
            SET
              installation_id = EXCLUDED.installation_id,
              binding_epoch = EXCLUDED.binding_epoch,
              clinic_seq = EXCLUDED.clinic_seq,
              state = EXCLUDED.state,
              reason = EXCLUDED.reason,
              term_ref = EXCLUDED.term_ref,
              plan_display_name = EXCLUDED.plan_display_name,
              starts_at = EXCLUDED.starts_at,
              ends_at = EXCLUDED.ends_at,
              grace_ends_at = EXCLUDED.grace_ends_at,
              allowance = EXCLUDED.allowance,
              used = EXCLUDED.used,
              band = EXCLUDED.band,
              queued_count = EXCLUDED.queued_count,
              held_count = EXCLUDED.held_count,
              suspended = EXCLUDED.suspended,
              event_at = EXCLUDED.event_at,
              applied_at = EXCLUDED.applied_at
            WHERE ai_internal.clinic_ai_coverage.binding_epoch < EXCLUDED.binding_epoch
              OR (
                ai_internal.clinic_ai_coverage.binding_epoch = EXCLUDED.binding_epoch
                AND ai_internal.clinic_ai_coverage.clinic_seq < EXCLUDED.clinic_seq
              );
          END LOOP;

          UPDATE ai_internal.feed_state
          SET
            cursor = (v_body->>'next_after')::bigint,
            last_success_at = now(),
            consecutive_failures = 0,
            pending_request_id = NULL,
            pending_since = NULL
          WHERE singleton = true;
        ELSE
          UPDATE ai_internal.feed_state
          SET
            pending_request_id = NULL,
            pending_since = NULL,
            consecutive_failures = consecutive_failures + 1
          WHERE singleton = true;
        END IF;
      END IF;
    END IF;
  END IF;

  SELECT cursor
  INTO v_cursor
  FROM ai_internal.feed_state
  WHERE singleton = true;

  SELECT (s.value_json->'platformFeed'->>'current')::integer
  INTO v_sent_version
  FROM ai_internal.app_settings s
  WHERE s.key = 'ai.contract_versions'
    AND s.is_deleted = false;

  v_token := auth_internal.issue_feed_token();

  v_platform_url := auth_internal.ai_app_setting_text(
    'ai.platform_base_url',
    'http://127.0.0.1:8787'
  );
  v_platform_url := regexp_replace(
    v_platform_url,
    '^(https?://)(127\.0\.0\.1|localhost)(?=[:/])',
    '\1host.docker.internal',
    'i'
  );

  v_request_url := v_platform_url
    || '/v1/feed/coverage?after='
    || v_cursor::text
    || '&limit=200';

  v_request_id := net.http_get(
    url := v_request_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_token,
      'Aip-Contract-Version', v_sent_version::text
    )
  );

  UPDATE ai_internal.feed_state
  SET
    pending_request_id = v_request_id,
    pending_since = now()
  WHERE singleton = true;
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.pull_coverage_feed() FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- T020: Schedule the coverage feed pull
-- -----------------------------------------------------------------------------

SELECT cron.schedule(
  'ai_coverage_feed_pull',
  '30 seconds',
  $$SELECT auth_internal.pull_coverage_feed()$$
);

-- -----------------------------------------------------------------------------
-- T021: Minimal get_ai_status (available/active and stale)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_ai_status(p_contract_version integer)
RETURNS public.rpc_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth_internal, ai_internal
AS $$
DECLARE
  v_org uuid;
  v_coverage ai_internal.clinic_ai_coverage%ROWTYPE;
  v_last_success_at timestamptz;
  v_available boolean;
  v_state text;
  v_stale boolean;
BEGIN
  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.', p_contract_version);
  END IF;

  SELECT fs.last_success_at
  INTO v_last_success_at
  FROM ai_internal.feed_state fs
  WHERE fs.singleton = true;

  v_stale := v_last_success_at IS NULL
    OR v_last_success_at < now() - interval '2 minutes';

  SELECT *
  INTO v_coverage
  FROM ai_internal.clinic_ai_coverage c
  WHERE c.organization_id = v_org;

  IF NOT FOUND THEN
    v_available := false;
    v_state := 'none';
  ELSIF v_coverage.suspended THEN
    v_available := false;
    v_state := 'suspended';
  ELSIF v_coverage.state = 'active' THEN
    v_available := true;
    v_state := 'active';
  ELSE
    v_available := false;
    v_state := v_coverage.state;
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'available', v_available,
      'state', v_state,
      'stale', v_stale,
      'platform_base_url', auth_internal.ai_app_setting_text(
        'ai.platform_base_url',
        'http://127.0.0.1:8787'
      ),
      'as_of', to_jsonb(now())
    ),
    p_contract_version
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_ai_status(p_contract_version integer DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
BEGIN
  IF p_contract_version IS NULL OR p_contract_version NOT IN (0, 1) THEN
    RETURN (
      false,
      jsonb_build_object('accepted_versions', jsonb_build_array(0, 1)),
      'CONTRACT_VERSION_UNSUPPORTED',
      'Contract version is not supported.',
      1
    )::public.rpc_result;
  END IF;

  RETURN auth_internal.get_ai_status(p_contract_version);
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.get_ai_status(integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_ai_status(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ai_status(integer) TO authenticated;

-- -----------------------------------------------------------------------------
-- T022: request_ai_status_refresh
-- -----------------------------------------------------------------------------

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

  SELECT sr.requested_at
  INTO v_requested_at
  FROM ai_internal.status_refresh sr
  WHERE sr.organization_id = v_org;

  IF FOUND AND now() - v_requested_at < interval '10 seconds' THEN
    RETURN public.rpc_error(
      'RATE_LIMITED',
      'Refresh was requested recently.',
      p_contract_version
    );
  END IF;

  INSERT INTO ai_internal.status_refresh (organization_id, requested_at)
  VALUES (v_org, now())
  ON CONFLICT (organization_id) DO UPDATE
  SET requested_at = EXCLUDED.requested_at;

  SELECT sr.requested_at
  INTO v_requested_at
  FROM ai_internal.status_refresh sr
  WHERE sr.organization_id = v_org;

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

CREATE OR REPLACE FUNCTION public.request_ai_status_refresh(p_contract_version integer DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal
AS $$
BEGIN
  IF p_contract_version IS NULL OR p_contract_version NOT IN (0, 1) THEN
    RETURN (
      false,
      jsonb_build_object('accepted_versions', jsonb_build_array(0, 1)),
      'CONTRACT_VERSION_UNSUPPORTED',
      'Contract version is not supported.',
      1
    )::public.rpc_result;
  END IF;

  RETURN auth_internal.request_ai_status_refresh(p_contract_version);
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.request_ai_status_refresh(integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.request_ai_status_refresh(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_ai_status_refresh(integer) TO authenticated, anon;
