-- CodeRabbit review fixes (comments 54, 56, 59).

-- -----------------------------------------------------------------------------
-- get_simplified_booking_slots: reject null p_local_date before range check.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_simplified_booking_slots(
  p_branch_id uuid,
  p_local_date date,
  p_preferred_doctor_id uuid
)
RETURNS public.rpc_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_tz text;
  v_schedule jsonb;
  v_today_local date;
  v_max_local date;
  v_day_name text;
  v_day jsonb;
  v_open time;
  v_close time;
  v_duration int;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_cursor timestamptz;
  v_block_end timestamptz;
  v_doctor_id uuid;
  v_available_ids uuid[] := ARRAY[]::uuid[];
  v_state text;
  v_blocks jsonb := '[]'::jsonb;
BEGIN
  PERFORM auth_internal.assert_appointment_access();
  PERFORM auth_internal.assert_appointment_branch(p_branch_id);
  PERFORM auth_internal.assert_appointment_doctor(p_preferred_doctor_id, p_branch_id);

  IF p_local_date IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Booking date is required.');
  END IF;

  SELECT
    COALESCE(NULLIF(trim(o.timezone), ''), 'UTC'),
    b.working_schedule
  INTO v_org_tz, v_schedule
  FROM public.branches b
  JOIN public.organizations o ON o.id = b.organization_id
  WHERE b.id = p_branch_id
    AND b.is_deleted = false
    AND b.is_active = true;

  v_today_local := (now() AT TIME ZONE v_org_tz)::date;
  v_max_local := v_today_local + 90;

  IF p_local_date < v_today_local OR p_local_date > v_max_local THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Date must be between today and 90 days ahead.');
  END IF;

  v_duration := auth_internal.resolve_appointment_default_duration(p_branch_id);

  IF v_schedule IS NULL THEN
    RETURN public.rpc_success(
      jsonb_build_object(
        'default_duration_minutes', v_duration,
        'blocks', '[]'::jsonb
      )
    );
  END IF;

  v_day_name := CASE extract(isodow FROM p_local_date)
    WHEN 1 THEN 'monday'
    WHEN 2 THEN 'tuesday'
    WHEN 3 THEN 'wednesday'
    WHEN 4 THEN 'thursday'
    WHEN 5 THEN 'friday'
    WHEN 6 THEN 'saturday'
    ELSE 'sunday'
  END;

  SELECT d.value
  INTO v_day
  FROM jsonb_array_elements(v_schedule -> 'days') AS d(value)
  WHERE lower(trim(COALESCE(d.value ->> 'day', ''))) = v_day_name
  LIMIT 1;

  IF v_day IS NULL OR NOT COALESCE((v_day ->> 'is_working_day')::boolean, false) THEN
    RETURN public.rpc_success(
      jsonb_build_object(
        'default_duration_minutes', v_duration,
        'blocks', '[]'::jsonb
      )
    );
  END IF;

  v_open := (v_day ->> 'open_time')::time;
  v_close := (v_day ->> 'close_time')::time;
  v_day_start := ((p_local_date::timestamp + v_open) AT TIME ZONE v_org_tz);
  v_day_end := ((p_local_date::timestamp + v_close) AT TIME ZONE v_org_tz);
  v_cursor := v_day_start;

  WHILE v_cursor + make_interval(mins => v_duration) <= v_day_end LOOP
    v_block_end := v_cursor + make_interval(mins => v_duration);

    IF NOT auth_internal.appointment_within_branch_working_hours(p_branch_id, v_cursor, v_block_end) THEN
      v_cursor := v_cursor + make_interval(mins => v_duration);
      CONTINUE;
    END IF;

    v_available_ids := ARRAY[]::uuid[];

    FOR v_doctor_id IN
      SELECT sm.id
      FROM public.staff_members sm
      JOIN public.staff_branch_assignments sba
        ON sba.staff_member_id = sm.id
       AND sba.branch_id = p_branch_id
       AND sba.is_deleted = false
      WHERE sm.role = 'doctor'
        AND sm.is_deleted = false
        AND sm.is_active = true
      ORDER BY sm.full_name
    LOOP
      IF NOT auth_internal.appointment_has_overlap(p_branch_id, v_doctor_id, v_cursor, v_block_end, NULL) THEN
        v_available_ids := array_append(v_available_ids, v_doctor_id);
      END IF;
    END LOOP;

    IF p_local_date = v_today_local AND v_cursor < now() THEN
      v_state := 'past';
    ELSIF p_preferred_doctor_id = ANY (v_available_ids) THEN
      v_state := 'available';
    ELSIF cardinality(v_available_ids) > 0 THEN
      v_state := 'alternate_doctors_available';
    ELSE
      v_state := 'fully_unavailable';
    END IF;

    v_blocks := v_blocks || jsonb_build_array(
      jsonb_build_object(
        'start_time', v_cursor,
        'end_time', v_block_end,
        'state', v_state,
        'available_doctor_ids', to_jsonb(v_available_ids)
      )
    );

    v_cursor := v_cursor + make_interval(mins => v_duration);
  END LOOP;

  RETURN public.rpc_success(
    jsonb_build_object(
      'default_duration_minutes', v_duration,
      'blocks', v_blocks
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('FORBIDDEN', 'INVALID_BRANCH', 'INVALID_DOCTOR') THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view booking slots.');
      END IF;
      IF SQLERRM = 'INVALID_BRANCH' THEN
        RETURN public.rpc_error('INVALID_BRANCH', 'Branch is not valid for this session.');
      END IF;
      RETURN public.rpc_error('INVALID_DOCTOR', 'Doctor is not valid for this branch.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- record_investigation_result: use assert_visit_branch_scope like adjacent RPCs.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.record_investigation_result(
  p_investigation_line_id uuid,
  p_result text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.visit_investigations%ROWTYPE;
  v_org_id uuid;
  v_recorded_at timestamptz;
  v_normalized_result text;
BEGIN
  PERFORM auth_internal.assert_permission('visits.edit_soap');
  v_org_id := public.jwt_organization_id();

  SELECT vi.* INTO v_row
  FROM public.visit_investigations vi
  JOIN public.visits v ON v.id = vi.visit_id
  WHERE vi.id = p_investigation_line_id
    AND vi.is_deleted = false
    AND v.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Investigation was not found.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_visit_branch_scope(v_row.visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  v_normalized_result := CASE WHEN p_result IS NULL THEN NULL ELSE NULLIF(trim(p_result), '') END;

  IF v_normalized_result IS NOT NULL AND length(v_normalized_result) > 10000 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Investigation result exceeds maximum length.');
  END IF;

  v_recorded_at := now();

  UPDATE public.visit_investigations vi
  SET
    result = v_normalized_result,
    result_recorded_at = CASE WHEN v_normalized_result IS NULL THEN NULL ELSE v_recorded_at END,
    result_recorded_by = CASE WHEN v_normalized_result IS NULL THEN NULL ELSE auth.uid() END,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE vi.id = p_investigation_line_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(), v_org_id, 'visit.investigation.result_record', 'visit_investigations', p_investigation_line_id,
    jsonb_build_object(
      'investigation_line_id', p_investigation_line_id,
      'result_recorded_at', CASE WHEN v_normalized_result IS NULL THEN NULL ELSE v_recorded_at END
    )
  );

  RETURN public.rpc_success(jsonb_build_object(
    'investigation_line_id', p_investigation_line_id,
    'result_recorded_at', CASE WHEN v_normalized_result IS NULL THEN NULL ELSE v_recorded_at END
  ));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to record investigation results.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- remove_coded_diagnosis follow-up: drop stale 4-arg auth_internal overloads;
-- grant execute on 3-arg auth_internal chronic-condition RPCs.
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS auth_internal.create_patient_chronic_condition(uuid, text, uuid, text);
DROP FUNCTION IF EXISTS auth_internal.update_patient_chronic_condition(uuid, text, uuid, text);

GRANT EXECUTE ON FUNCTION auth_internal.create_patient_chronic_condition(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION auth_internal.update_patient_chronic_condition(uuid, text, text) TO authenticated;
