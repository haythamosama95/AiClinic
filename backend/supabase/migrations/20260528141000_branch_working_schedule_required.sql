-- V1-2: require branch working days/hours per day.

ALTER TABLE public.branches
ADD COLUMN IF NOT EXISTS working_schedule jsonb;

CREATE OR REPLACE FUNCTION auth_internal.validate_branch_working_schedule(p_working_schedule jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_day jsonb;
  v_day_name text;
  v_is_working boolean;
  v_open text;
  v_close text;
BEGIN
  IF p_working_schedule IS NULL OR jsonb_typeof(p_working_schedule) <> 'object' THEN
    RETURN 'Working schedule is required.';
  END IF;
  IF jsonb_typeof(p_working_schedule -> 'days') <> 'array' THEN
    RETURN 'Working schedule must include a days array.';
  END IF;
  IF jsonb_array_length(p_working_schedule -> 'days') = 0 THEN
    RETURN 'Working schedule must include at least one day.';
  END IF;

  FOR v_day IN SELECT value FROM jsonb_array_elements(p_working_schedule -> 'days')
  LOOP
    v_day_name := trim(COALESCE(v_day ->> 'day', ''));
    v_is_working := COALESCE((v_day ->> 'is_working_day')::boolean, false);
    IF v_day_name NOT IN ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday') THEN
      RETURN 'Working schedule contains an invalid day.';
    END IF;
    IF v_is_working THEN
      v_open := trim(COALESCE(v_day ->> 'open_time', ''));
      v_close := trim(COALESCE(v_day ->> 'close_time', ''));
      IF v_open !~ '^([01]\d|2[0-3]):([0-5]\d)$' OR v_close !~ '^([01]\d|2[0-3]):([0-5]\d)$' THEN
        RETURN format('Working hours for %s must use HH:mm format.', v_day_name);
      END IF;
      IF v_open >= v_close THEN
        RETURN format('Open time must be before close time for %s.', v_day_name);
      END IF;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_working_schedule -> 'days') AS d(value)
    WHERE COALESCE((d.value ->> 'is_working_day')::boolean, false)
  ) THEN
    RETURN 'At least one working day is required.';
  END IF;

  RETURN NULL;
END;
$$;

UPDATE public.branches b
SET working_schedule = jsonb_build_object(
  'days',
  jsonb_build_array(
    jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'sunday', 'is_working_day', false)
  )
)
WHERE b.working_schedule IS NULL;

ALTER TABLE public.branches
ALTER COLUMN working_schedule SET DEFAULT jsonb_build_object(
  'days',
  jsonb_build_array(
    jsonb_build_object('day', 'monday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'tuesday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'wednesday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'thursday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'friday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'saturday', 'is_working_day', true, 'open_time', '09:00', 'close_time', '17:00'),
    jsonb_build_object('day', 'sunday', 'is_working_day', false)
  )
);

ALTER TABLE public.branches
ALTER COLUMN working_schedule SET NOT NULL;

DROP FUNCTION IF EXISTS public.manage_create_branch(text, text, text, text, text);
DROP FUNCTION IF EXISTS auth_internal.manage_create_branch(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.update_branch(uuid, text, text, text, text, text);
DROP FUNCTION IF EXISTS auth_internal.update_branch(uuid, text, text, text, text, text);

CREATE OR REPLACE FUNCTION auth_internal.manage_create_branch(
  p_name text,
  p_working_schedule jsonb,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_branch_id uuid;
  v_schedule_error text;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL OR public.jwt_setup_required() THEN
    RETURN public.rpc_error('ORG_SETUP_INCOMPLETE', 'Complete clinic setup before creating branches.');
  END IF;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch name is required.');
  END IF;
  IF p_code IS NOT NULL AND NULLIF(trim(p_code), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch code cannot be empty when provided.');
  END IF;
  v_schedule_error := auth_internal.validate_branch_working_schedule(p_working_schedule);
  IF v_schedule_error IS NOT NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', v_schedule_error);
  END IF;

  INSERT INTO public.branches (
    organization_id,
    name,
    code,
    address,
    phone,
    maps_url,
    working_schedule,
    created_by,
    updated_by
  )
  VALUES (
    v_org_id,
    trim(p_name),
    NULLIF(trim(p_code), ''),
    NULLIF(trim(p_address), ''),
    NULLIF(trim(p_phone), ''),
    NULLIF(trim(p_maps_url), ''),
    p_working_schedule,
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_branch_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'branch.create',
    'branches',
    v_branch_id,
    jsonb_build_object(
      'organization_id', v_org_id,
      'name', trim(p_name),
      'code', NULLIF(trim(p_code), ''),
      'working_schedule', p_working_schedule
    )
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', v_branch_id));
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('DUPLICATE_CODE', 'A branch with this code already exists in your organization.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage branches.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.update_branch(
  p_branch_id uuid,
  p_name text,
  p_working_schedule jsonb,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_old public.branches%ROWTYPE;
  v_new public.branches%ROWTYPE;
  v_schedule_error text;
BEGIN
  PERFORM auth_internal.assert_permission('settings.manage_branches');
  v_org_id := public.jwt_organization_id();

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch name is required.');
  END IF;
  IF p_code IS NOT NULL AND NULLIF(trim(p_code), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch code cannot be empty when provided.');
  END IF;
  v_schedule_error := auth_internal.validate_branch_working_schedule(p_working_schedule);
  IF v_schedule_error IS NOT NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', v_schedule_error);
  END IF;

  SELECT *
  INTO v_old
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.organization_id = v_org_id
    AND b.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('BRANCH_NOT_FOUND', 'Branch was not found in your organization.');
  END IF;

  UPDATE public.branches b
  SET
    name = trim(p_name),
    code = NULLIF(trim(p_code), ''),
    address = COALESCE(NULLIF(trim(p_address), ''), b.address),
    phone = COALESCE(NULLIF(trim(p_phone), ''), b.phone),
    maps_url = COALESCE(NULLIF(trim(p_maps_url), ''), b.maps_url),
    working_schedule = p_working_schedule,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE b.id = p_branch_id
  RETURNING * INTO v_new;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'branch.update',
    'branches',
    p_branch_id,
    jsonb_build_object(
      'name', v_old.name,
      'code', v_old.code,
      'address', v_old.address,
      'phone', v_old.phone,
      'maps_url', v_old.maps_url,
      'working_schedule', v_old.working_schedule
    ),
    jsonb_build_object(
      'name', v_new.name,
      'code', v_new.code,
      'address', v_new.address,
      'phone', v_new.phone,
      'maps_url', v_new.maps_url,
      'working_schedule', v_new.working_schedule
    )
  );

  RETURN public.rpc_success(jsonb_build_object('branch_id', p_branch_id));
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('DUPLICATE_CODE', 'A branch with this code already exists in your organization.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage branches.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.manage_create_branch(
  p_name text,
  p_working_schedule jsonb,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.manage_create_branch(p_name, p_working_schedule, p_code, p_address, p_phone, p_maps_url);
$$;

CREATE OR REPLACE FUNCTION public.update_branch(
  p_branch_id uuid,
  p_name text,
  p_working_schedule jsonb,
  p_code text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_maps_url text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_branch(p_branch_id, p_name, p_working_schedule, p_code, p_address, p_phone, p_maps_url);
$$;

GRANT EXECUTE ON FUNCTION public.manage_create_branch(text, jsonb, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_branch(uuid, text, jsonb, text, text, text, text) TO authenticated;
