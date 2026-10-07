-- =============================================================================
-- P5.2b: Read-time status, notices, and billing status.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T007–T008: Shared reader and public.get_ai_status wrapper
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
  v_as_of timestamptz;
  v_coverage ai_internal.clinic_ai_coverage%ROWTYPE;
  v_last_success_at timestamptz;
  v_available boolean;
  v_state text;
  v_reason text;
  v_days_left integer;
  v_grace_days_left integer;
  v_next_change_at timestamptz;
  v_stale boolean;
  v_notices jsonb := '[]'::jsonb;
  v_band text;
  v_has_row boolean := false;
BEGIN
  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.', p_contract_version);
  END IF;

  v_as_of := now();

  SELECT fs.last_success_at
  INTO v_last_success_at
  FROM ai_internal.feed_state fs
  WHERE fs.singleton = true;

  v_stale := v_last_success_at IS NULL
    OR v_last_success_at < v_as_of - interval '2 minutes';

  SELECT *
  INTO v_coverage
  FROM ai_internal.clinic_ai_coverage c
  WHERE c.organization_id = v_org;

  v_has_row := FOUND;

  IF NOT v_has_row THEN
    v_available := false;
    v_state := 'none';
    v_reason := 'none';
    v_days_left := NULL;
    v_grace_days_left := NULL;
    v_next_change_at := NULL;
    v_band := NULL;
  ELSIF v_coverage.suspended THEN
    v_available := false;
    v_state := 'suspended';
    v_reason := NULL;
    v_band := v_coverage.band;

    IF v_coverage.ends_at IS NOT NULL AND v_coverage.ends_at > v_as_of THEN
      IF v_coverage.grace_ends_at IS NOT NULL
        AND v_coverage.grace_ends_at > v_as_of
        AND v_coverage.grace_ends_at < v_coverage.ends_at
      THEN
        v_next_change_at := v_coverage.grace_ends_at;
      ELSE
        v_next_change_at := v_coverage.ends_at;
      END IF;
    ELSIF v_coverage.grace_ends_at IS NOT NULL AND v_coverage.grace_ends_at > v_as_of THEN
      v_next_change_at := v_coverage.grace_ends_at;
    ELSE
      v_next_change_at := NULL;
    END IF;

    IF v_coverage.ends_at IS NOT NULL AND v_as_of < v_coverage.ends_at THEN
      v_days_left := floor(
        extract(epoch FROM (v_coverage.ends_at - v_as_of)) / 86400
      )::integer;
    ELSE
      v_days_left := NULL;
    END IF;

    IF v_coverage.grace_ends_at IS NOT NULL AND v_as_of < v_coverage.grace_ends_at THEN
      v_grace_days_left := floor(
        extract(epoch FROM (v_coverage.grace_ends_at - v_as_of)) / 86400
      )::integer;
    ELSE
      v_grace_days_left := NULL;
    END IF;
  ELSIF v_coverage.state = 'active' THEN
    v_band := v_coverage.band;

    IF v_coverage.ends_at IS NOT NULL AND v_as_of < v_coverage.ends_at THEN
      v_state := 'active';
      v_available := true;
      v_reason := NULL;
      v_days_left := floor(
        extract(epoch FROM (v_coverage.ends_at - v_as_of)) / 86400
      )::integer;
    ELSIF v_coverage.queued_count > 0 THEN
      v_state := 'active';
      v_available := true;
      v_reason := NULL;
      v_days_left := NULL;
    ELSIF v_coverage.grace_ends_at IS NOT NULL AND v_as_of < v_coverage.grace_ends_at THEN
      v_state := 'grace';
      v_available := true;
      v_reason := NULL;
      v_days_left := NULL;
      v_grace_days_left := floor(
        extract(epoch FROM (v_coverage.grace_ends_at - v_as_of)) / 86400
      )::integer;
    ELSE
      v_state := 'lapsed';
      v_available := false;
      v_reason := 'expired';
      v_days_left := NULL;
    END IF;

    IF v_coverage.ends_at IS NOT NULL AND v_coverage.ends_at > v_as_of THEN
      IF v_coverage.grace_ends_at IS NOT NULL
        AND v_coverage.grace_ends_at > v_as_of
        AND v_coverage.grace_ends_at < v_coverage.ends_at
      THEN
        v_next_change_at := v_coverage.grace_ends_at;
      ELSE
        v_next_change_at := v_coverage.ends_at;
      END IF;
    ELSIF v_coverage.grace_ends_at IS NOT NULL AND v_coverage.grace_ends_at > v_as_of THEN
      v_next_change_at := v_coverage.grace_ends_at;
    ELSE
      v_next_change_at := NULL;
    END IF;

    IF v_grace_days_left IS NULL
      AND v_coverage.grace_ends_at IS NOT NULL
      AND v_as_of < v_coverage.grace_ends_at
    THEN
      v_grace_days_left := floor(
        extract(epoch FROM (v_coverage.grace_ends_at - v_as_of)) / 86400
      )::integer;
    END IF;
  ELSIF v_coverage.state = 'grace' THEN
    v_band := v_coverage.band;
    v_days_left := NULL;

    IF v_coverage.grace_ends_at IS NOT NULL AND v_as_of < v_coverage.grace_ends_at THEN
      v_state := 'grace';
      v_available := true;
      v_reason := NULL;
      v_grace_days_left := floor(
        extract(epoch FROM (v_coverage.grace_ends_at - v_as_of)) / 86400
      )::integer;
      v_next_change_at := v_coverage.grace_ends_at;
    ELSE
      v_state := 'lapsed';
      v_available := false;
      v_reason := 'expired';
      v_grace_days_left := NULL;
      v_next_change_at := NULL;
    END IF;

    IF v_coverage.ends_at IS NOT NULL AND v_coverage.ends_at > v_as_of THEN
      IF v_next_change_at IS NULL OR v_coverage.ends_at < v_next_change_at THEN
        v_next_change_at := v_coverage.ends_at;
      END IF;
    END IF;
  ELSE
    v_state := v_coverage.state;
    v_available := false;
    v_reason := v_coverage.reason;
    v_band := v_coverage.band;
    v_days_left := NULL;
    v_grace_days_left := NULL;

    IF v_coverage.ends_at IS NOT NULL AND v_coverage.ends_at > v_as_of THEN
      IF v_coverage.grace_ends_at IS NOT NULL
        AND v_coverage.grace_ends_at > v_as_of
        AND v_coverage.grace_ends_at < v_coverage.ends_at
      THEN
        v_next_change_at := v_coverage.grace_ends_at;
      ELSE
        v_next_change_at := v_coverage.ends_at;
      END IF;
    ELSIF v_coverage.grace_ends_at IS NOT NULL AND v_coverage.grace_ends_at > v_as_of THEN
      v_next_change_at := v_coverage.grace_ends_at;
    ELSE
      v_next_change_at := NULL;
    END IF;
  END IF;

  IF v_has_row THEN
    IF v_days_left IS NOT NULL
      AND v_coverage.queued_count = 0
      AND (v_days_left = 7 OR v_days_left = 3 OR v_days_left <= 1)
    THEN
      v_notices := v_notices || jsonb_build_array(
        jsonb_build_object(
          'code', 'ends_soon',
          'audience', 'member',
          'channel', 'in_app'
        )
      );
    END IF;

    IF v_state = 'grace' THEN
      v_notices := v_notices || jsonb_build_array(
        jsonb_build_object(
          'code', 'in_grace',
          'audience', 'member',
          'channel', 'in_app',
          'grace_days_left', v_grace_days_left
        )
      );
    END IF;

    IF v_band IN ('75', '90') THEN
      v_notices := v_notices || jsonb_build_array(
        jsonb_build_object(
          'code', 'allowance_low',
          'audience', 'member',
          'channel', 'in_app'
        )
      );
    END IF;

    IF v_state = 'exhausted' THEN
      v_notices := v_notices || jsonb_build_array(
        jsonb_build_object(
          'code', 'allowance_exhausted',
          'audience', 'member',
          'channel', 'in_app'
        )
      );
    END IF;

    IF v_state = 'lapsed' THEN
      v_notices := v_notices || jsonb_build_array(
        jsonb_build_object(
          'code', 'lapsed',
          'audience', 'member',
          'channel', 'in_app'
        )
      );
    END IF;

    IF v_state = 'reversed' THEN
      v_notices := v_notices || jsonb_build_array(
        jsonb_build_object(
          'code', 'ended_reversed',
          'audience', 'member',
          'channel', 'in_app'
        )
      );
    END IF;

    IF v_coverage.suspended THEN
      v_notices := v_notices || jsonb_build_array(
        jsonb_build_object(
          'code', 'suspended',
          'audience', 'member',
          'channel', 'in_app'
        )
      );
    END IF;
  END IF;

  IF v_stale THEN
    v_notices := v_notices || jsonb_build_array(
      jsonb_build_object(
        'code', 'status_stale',
        'audience', 'member',
        'channel', 'in_app'
      )
    );
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object(
      'available', v_available,
      'state', v_state,
      'reason', v_reason,
      'days_left', v_days_left,
      'band', v_band,
      'notices', v_notices,
      'next_change_at', v_next_change_at,
      'as_of', v_as_of,
      'stale', v_stale,
      'platform_base_url', auth_internal.ai_app_setting_text(
        'ai.platform_base_url',
        'http://127.0.0.1:8787'
      )
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
-- T009–T011: subscription_ref, public.get_ai_billing_status, and grant
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_ai_billing_status(p_contract_version integer DEFAULT NULL)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth_internal, ai_internal, extensions
AS $$
DECLARE
  v_org uuid;
  v_status public.rpc_result;
  v_coverage ai_internal.clinic_ai_coverage%ROWTYPE;
  v_subscription_ref text;
  v_hash bytea;
  v_alphabet text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_encoded text := '';
  v_buffer bigint := 0;
  v_bits integer := 0;
  v_i integer;
  v_byte integer;
  v_index integer;
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

  IF public.current_membership_role() IS DISTINCT FROM 'administrator' THEN
    RETURN public.rpc_error(
      'FORBIDDEN_ROLE',
      'Only administrators can view billing status.',
      p_contract_version
    );
  END IF;

  v_org := public.current_org_id();
  IF v_org IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.', p_contract_version);
  END IF;

  v_status := auth_internal.get_ai_status(p_contract_version);
  IF NOT v_status.success THEN
    RETURN v_status;
  END IF;

  v_hash := extensions.digest('sub-ref:' || v_org::text, 'sha256');
  FOR v_i IN 0..(length(v_hash) - 1) LOOP
    v_byte := get_byte(v_hash, v_i);
    v_buffer := (v_buffer << 8) | v_byte;
    v_bits := v_bits + 8;
    WHILE v_bits >= 5 LOOP
      v_bits := v_bits - 5;
      v_index := ((v_buffer >> v_bits) & 31)::integer;
      v_encoded := v_encoded || substr(v_alphabet, v_index + 1, 1);
    END LOOP;
  END LOOP;
  IF v_bits > 0 THEN
    v_index := ((v_buffer << (5 - v_bits)) & 31)::integer;
    v_encoded := v_encoded || substr(v_alphabet, v_index + 1, 1);
  END IF;
  v_subscription_ref := 'AIC-' || left(v_encoded, 8);

  SELECT *
  INTO v_coverage
  FROM ai_internal.clinic_ai_coverage c
  WHERE c.organization_id = v_org;

  IF FOUND THEN
    RETURN public.rpc_success(
      v_status.data || jsonb_build_object(
        'plan_display_name', v_coverage.plan_display_name,
        'starts_at', v_coverage.starts_at,
        'ends_at', v_coverage.ends_at,
        'grace_ends_at', v_coverage.grace_ends_at,
        'allowance', v_coverage.allowance,
        'used', v_coverage.used,
        'queued_count', v_coverage.queued_count,
        'held_count', v_coverage.held_count,
        'subscription_ref', v_subscription_ref,
        'abo_base_url', auth_internal.ai_app_setting_text(
          'ai.abo_base_url',
          'http://127.0.0.1:8788'
        )
      ),
      p_contract_version
    );
  END IF;

  RETURN public.rpc_success(
    v_status.data || jsonb_build_object(
      'plan_display_name', NULL,
      'starts_at', NULL,
      'ends_at', NULL,
      'grace_ends_at', NULL,
      'allowance', NULL,
      'used', NULL,
      'queued_count', NULL,
      'held_count', NULL,
      'subscription_ref', v_subscription_ref,
      'abo_base_url', auth_internal.ai_app_setting_text(
        'ai.abo_base_url',
        'http://127.0.0.1:8788'
      )
    ),
    p_contract_version
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_ai_billing_status(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ai_billing_status(integer) TO authenticated;
