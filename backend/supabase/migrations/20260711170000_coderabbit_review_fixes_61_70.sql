-- CodeRabbit review fixes (comment 61).

-- -----------------------------------------------------------------------------
-- resolve_appointment_default_duration: protect fallback minutes cast.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.resolve_appointment_default_duration(p_branch_id uuid)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_value jsonb;
  v_minutes int;
BEGIN
  SELECT b.organization_id
  INTO v_org_id
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.is_deleted = false;

  IF NOT FOUND THEN
    RETURN 30;
  END IF;

  SELECT s.value_json
  INTO v_value
  FROM public.app_settings s
  WHERE s.organization_id = v_org_id
    AND s.branch_id = p_branch_id
    AND s.key = 'appointment.default_duration_minutes'
    AND s.is_deleted = false
  LIMIT 1;

  IF v_value IS NULL THEN
    SELECT s.value_json
    INTO v_value
    FROM public.app_settings s
    WHERE s.organization_id = v_org_id
      AND s.branch_id IS NULL
      AND s.key = 'appointment.default_duration_minutes'
      AND s.is_deleted = false
    LIMIT 1;
  END IF;

  IF v_value IS NULL THEN
    RETURN 30;
  END IF;

  BEGIN
    v_minutes := (v_value #>> '{}')::int;
  EXCEPTION
    WHEN OTHERS THEN
      BEGIN
        v_minutes := (v_value ->> 'minutes')::int;
      EXCEPTION
        WHEN OTHERS THEN
          v_minutes := NULL;
      END;
  END;

  IF v_minutes IS NULL OR v_minutes < 5 OR v_minutes > 240 THEN
    RETURN 30;
  END IF;

  RETURN v_minutes;
END;
$$;
