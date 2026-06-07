-- =============================================================================
-- V1-7: Shift management (schema, RLS, helpers, read-path RPCs)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- shifts
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id),
  branch_id uuid NOT NULL REFERENCES public.branches (id),
  shift_date date NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT shifts_end_after_start CHECK (end_time > start_time),
  CONSTRAINT shifts_notes_length CHECK (notes IS NULL OR length(trim(notes)) <= 500)
);

CREATE INDEX IF NOT EXISTS shifts_branch_date_idx
  ON public.shifts (branch_id, shift_date);

CREATE INDEX IF NOT EXISTS shifts_branch_date_start_idx
  ON public.shifts (branch_id, shift_date, start_time);

CREATE INDEX IF NOT EXISTS shifts_branch_date_active_idx
  ON public.shifts (branch_id, shift_date)
  WHERE deleted_at IS NULL;

-- -----------------------------------------------------------------------------
-- shift_assignments
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.shift_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id uuid NOT NULL REFERENCES public.shifts (id) ON DELETE CASCADE,
  staff_member_id uuid NOT NULL REFERENCES public.staff_members (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id),
  updated_at timestamptz,
  updated_by uuid REFERENCES auth.users (id),
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users (id),
  CONSTRAINT shift_assignments_unique_staff UNIQUE (shift_id, staff_member_id)
);

CREATE INDEX IF NOT EXISTS shift_assignments_staff_shift_idx
  ON public.shift_assignments (staff_member_id, shift_id);

CREATE INDEX IF NOT EXISTS shift_assignments_shift_idx
  ON public.shift_assignments (shift_id);

SELECT public.apply_standard_audit_triggers('public.shifts'::regclass);
SELECT public.apply_standard_audit_triggers('public.shift_assignments'::regclass);

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shift_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shifts_select ON public.shifts;
CREATE POLICY shifts_select ON public.shifts
  FOR SELECT
  TO authenticated
  USING (
    organization_id = public.jwt_organization_id()
    AND branch_id = ANY (public.jwt_branch_ids())
  );

DROP POLICY IF EXISTS shifts_insert ON public.shifts;
CREATE POLICY shifts_insert ON public.shifts
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS shifts_update ON public.shifts;
CREATE POLICY shifts_update ON public.shifts
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS shifts_delete ON public.shifts;
CREATE POLICY shifts_delete ON public.shifts
  FOR DELETE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS shift_assignments_select ON public.shift_assignments;
CREATE POLICY shift_assignments_select ON public.shift_assignments
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.shifts s
      WHERE s.id = shift_assignments.shift_id
        AND s.organization_id = public.jwt_organization_id()
        AND s.branch_id = ANY (public.jwt_branch_ids())
    )
  );

DROP POLICY IF EXISTS shift_assignments_insert ON public.shift_assignments;
CREATE POLICY shift_assignments_insert ON public.shift_assignments
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS shift_assignments_update ON public.shift_assignments;
CREATE POLICY shift_assignments_update ON public.shift_assignments
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS shift_assignments_delete ON public.shift_assignments;
CREATE POLICY shift_assignments_delete ON public.shift_assignments
  FOR DELETE
  TO authenticated
  USING (false);

REVOKE INSERT, UPDATE, DELETE ON public.shifts, public.shift_assignments FROM PUBLIC, authenticated, anon;
GRANT SELECT ON public.shifts, public.shift_assignments TO authenticated;

-- -----------------------------------------------------------------------------
-- auth_internal.get_org_today
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_org_today(p_organization_id uuid)
RETURNS date
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tz text;
BEGIN
  SELECT COALESCE(NULLIF(trim(o.timezone), ''), 'UTC')
  INTO v_tz
  FROM public.organizations o
  WHERE o.id = p_organization_id
    AND o.is_deleted = false;

  IF NOT FOUND THEN
    RETURN (now() AT TIME ZONE 'UTC')::date;
  END IF;

  RETURN (now() AT TIME ZONE v_tz)::date;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.staff_has_shifts_manage
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.staff_has_shifts_manage()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.current_staff_member_row() sm
    JOIN public.roles_permissions rp ON rp.role = sm.role
    WHERE rp.permission_key = 'shifts.manage'
      AND rp.is_granted = true
      AND rp.is_deleted = false
  );
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_shift_branch
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_shift_branch(p_branch_id uuid)
RETURNS public.branches
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_branch public.branches%ROWTYPE;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = 'P0001';
  END IF;

  IF p_branch_id IS NULL OR NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = 'P0001';
  END IF;

  SELECT *
  INTO v_branch
  FROM public.branches b
  WHERE b.id = p_branch_id
    AND b.organization_id = v_org_id
    AND b.is_deleted = false
    AND b.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = 'P0001';
  END IF;

  RETURN v_branch;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_shift_branch_scope
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_shift_branch_scope(p_shift_id uuid)
RETURNS public.shifts
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shift public.shifts%ROWTYPE;
BEGIN
  IF p_shift_id IS NULL THEN
    RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0001';
  END IF;

  SELECT *
  INTO v_shift
  FROM public.shifts s
  WHERE s.id = p_shift_id
    AND s.organization_id = public.jwt_organization_id()
    AND s.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0001';
  END IF;

  RETURN v_shift;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_shifts_manage
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_shifts_manage()
RETURNS public.staff_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
BEGIN
  BEGIN
    v_staff := auth_internal.assert_permission('shifts.manage');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'FORBIDDEN' THEN
        RAISE EXCEPTION 'permission_denied' USING ERRCODE = 'P0001';
      END IF;
      RAISE;
  END;

  RETURN v_staff;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_shift_mutable
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_shift_mutable(p_shift_date date)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_today date;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = 'P0001';
  END IF;

  IF p_shift_date IS NULL THEN
    RAISE EXCEPTION 'invalid_shift_date' USING ERRCODE = 'P0001';
  END IF;

  v_today := auth_internal.get_org_today(v_org_id);

  IF p_shift_date < v_today THEN
    RAISE EXCEPTION 'shift_read_only_past_date' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_shift_staff_eligible
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_shift_staff_eligible(
  p_staff_member_id uuid,
  p_branch_id uuid
)
RETURNS public.staff_members
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.id = p_staff_member_id
    AND sm.is_deleted = false
    AND sm.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'staff_not_eligible' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.staff_branch_assignments sba
    WHERE sba.staff_member_id = p_staff_member_id
      AND sba.branch_id = p_branch_id
      AND sba.is_deleted = false
  ) THEN
    RAISE EXCEPTION 'staff_not_eligible' USING ERRCODE = 'P0001';
  END IF;

  RETURN v_staff;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.shift_assignee_count
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.shift_assignee_count(p_shift_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::int
  FROM public.shift_assignments sa
  WHERE sa.shift_id = p_shift_id;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.assert_no_staff_shift_overlap
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.assert_no_staff_shift_overlap(
  p_branch_id uuid,
  p_shift_date date,
  p_start_time time,
  p_end_time time,
  p_staff_ids uuid[],
  p_exclude_shift_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_id uuid;
  v_conflict record;
  v_conflicts jsonb := '[]'::jsonb;
BEGIN
  IF p_staff_ids IS NULL OR cardinality(p_staff_ids) = 0 THEN
    RETURN;
  END IF;

  IF p_end_time <= p_start_time THEN
    RAISE EXCEPTION 'shift_invalid_time_range' USING ERRCODE = 'P0001';
  END IF;

  FOREACH v_staff_id IN ARRAY p_staff_ids
  LOOP
    SELECT
      s.id AS conflicting_shift_id,
      s.start_time,
      s.end_time,
      sm.id AS staff_member_id,
      sm.full_name AS display_name
    INTO v_conflict
    FROM public.shifts s
    JOIN public.shift_assignments sa ON sa.shift_id = s.id
    JOIN public.staff_members sm ON sm.id = sa.staff_member_id
    WHERE s.branch_id = p_branch_id
      AND s.shift_date = p_shift_date
      AND s.deleted_at IS NULL
      AND (p_exclude_shift_id IS NULL OR s.id <> p_exclude_shift_id)
      AND sa.staff_member_id = v_staff_id
      AND s.start_time < p_end_time
      AND s.end_time > p_start_time
    LIMIT 1;

    IF FOUND THEN
      v_conflicts := v_conflicts || jsonb_build_array(
        jsonb_build_object(
          'staff_member_id', v_conflict.staff_member_id,
          'display_name', v_conflict.display_name,
          'conflicting_shift_id', v_conflict.conflicting_shift_id,
          'start_time', to_char(v_conflict.start_time, 'HH24:MI'),
          'end_time', to_char(v_conflict.end_time, 'HH24:MI')
        )
      );
    END IF;
  END LOOP;

  IF jsonb_array_length(v_conflicts) > 0 THEN
    RAISE EXCEPTION 'shift_overlap: %', v_conflicts::text USING ERRCODE = 'P0001';
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.derive_shift_status
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.derive_shift_status(
  p_deleted_at timestamptz,
  p_assignee_count int
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_deleted_at IS NOT NULL THEN 'cancelled'
    WHEN COALESCE(p_assignee_count, 0) = 0 THEN 'incomplete'
    ELSE 'active'
  END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.list_shifts
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.list_shifts(
  p_branch_id uuid,
  p_date_from date,
  p_date_to date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items jsonb;
BEGIN
  PERFORM auth_internal.assert_shift_branch(p_branch_id);

  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_to < p_date_from THEN
    RAISE EXCEPTION 'invalid_date_range' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sub.id,
        'branch_id', sub.branch_id,
        'shift_date', sub.shift_date,
        'start_time', to_char(sub.start_time, 'HH24:MI'),
        'end_time', to_char(sub.end_time, 'HH24:MI'),
        'status', sub.status,
        'is_unassigned', sub.is_unassigned,
        'assignee_names', sub.assignee_names,
        'assignee_count', sub.assignee_count,
        'notes_preview', sub.notes_preview
      )
      ORDER BY sub.shift_date, sub.start_time
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      s.id,
      s.branch_id,
      s.shift_date,
      s.start_time,
      s.end_time,
      auth_internal.derive_shift_status(s.deleted_at, count(sa.id)::int) AS status,
      (count(sa.id) = 0) AS is_unassigned,
      COALESCE(
        jsonb_agg(sm.full_name ORDER BY sm.full_name) FILTER (WHERE sm.id IS NOT NULL),
        '[]'::jsonb
      ) AS assignee_names,
      count(sa.id)::int AS assignee_count,
      CASE
        WHEN s.notes IS NULL THEN NULL
        ELSE left(trim(s.notes), 80)
      END AS notes_preview
    FROM public.shifts s
    LEFT JOIN public.shift_assignments sa ON sa.shift_id = s.id
    LEFT JOIN public.staff_members sm ON sm.id = sa.staff_member_id
    WHERE s.branch_id = p_branch_id
      AND s.deleted_at IS NULL
      AND s.shift_date >= p_date_from
      AND s.shift_date <= p_date_to
    GROUP BY s.id
    ORDER BY s.shift_date, s.start_time
  ) sub
  WHERE sub.status <> 'cancelled';

  RETURN v_items;
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'permission_denied' THEN
      RAISE;
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_shift_detail
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_shift_detail(p_shift_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shift public.shifts%ROWTYPE;
  v_branch public.branches%ROWTYPE;
  v_assignee_count int;
  v_status text;
  v_org_today date;
  v_is_past boolean;
  v_is_read_only boolean;
  v_assignments jsonb;
BEGIN
  v_shift := auth_internal.assert_shift_branch_scope(p_shift_id);

  SELECT *
  INTO v_branch
  FROM public.branches b
  WHERE b.id = v_shift.branch_id;

  v_assignee_count := auth_internal.shift_assignee_count(v_shift.id);
  v_status := auth_internal.derive_shift_status(v_shift.deleted_at, v_assignee_count);
  v_org_today := auth_internal.get_org_today(v_shift.organization_id);
  v_is_past := v_shift.shift_date < v_org_today;
  v_is_read_only := v_status = 'cancelled' OR v_is_past OR NOT auth_internal.staff_has_shifts_manage();

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sa.id,
        'staff_member_id', sa.staff_member_id,
        'display_name', sm.full_name
      )
      ORDER BY sm.full_name
    ),
    '[]'::jsonb
  )
  INTO v_assignments
  FROM public.shift_assignments sa
  JOIN public.staff_members sm ON sm.id = sa.staff_member_id
  WHERE sa.shift_id = v_shift.id;

  RETURN jsonb_build_object(
    'shift', jsonb_build_object(
      'id', v_shift.id,
      'branch_id', v_shift.branch_id,
      'shift_date', v_shift.shift_date,
      'start_time', to_char(v_shift.start_time, 'HH24:MI'),
      'end_time', to_char(v_shift.end_time, 'HH24:MI'),
      'notes', v_shift.notes,
      'status', v_status,
      'is_unassigned', v_assignee_count = 0,
      'is_past', v_is_past,
      'is_read_only', v_is_read_only,
      'updated_at', v_shift.updated_at
    ),
    'assignments', v_assignments,
    'branch', jsonb_build_object(
      'id', v_branch.id,
      'name', v_branch.name,
      'code', v_branch.code
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM IN ('shift_not_found', 'permission_denied') THEN
      RAISE;
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.create_shift
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.create_shift(
  p_branch_id uuid,
  p_shift_date date,
  p_start_time time,
  p_end_time time,
  p_notes text DEFAULT NULL,
  p_staff_ids uuid[] DEFAULT '{}'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller public.staff_members%ROWTYPE;
  v_branch public.branches%ROWTYPE;
  v_shift_id uuid;
  v_staff_id uuid;
  v_notes text;
  v_org_today date;
BEGIN
  v_caller := auth_internal.assert_shifts_manage();
  v_branch := auth_internal.assert_shift_branch(p_branch_id);

  IF p_shift_date IS NULL THEN
    RAISE EXCEPTION 'invalid_shift_date' USING ERRCODE = 'P0001';
  END IF;

  v_org_today := auth_internal.get_org_today(v_branch.organization_id);

  IF p_shift_date < v_org_today THEN
    RAISE EXCEPTION 'shift_read_only_past_date' USING ERRCODE = 'P0001';
  END IF;

  IF p_end_time IS NULL OR p_start_time IS NULL OR p_end_time <= p_start_time THEN
    RAISE EXCEPTION 'shift_invalid_time_range' USING ERRCODE = 'P0001';
  END IF;

  v_notes := NULLIF(trim(COALESCE(p_notes, '')), '');

  IF v_notes IS NOT NULL AND length(v_notes) > 500 THEN
    RAISE EXCEPTION 'notes_too_long' USING ERRCODE = 'P0001';
  END IF;

  IF p_staff_ids IS NOT NULL THEN
    p_staff_ids := ARRAY(SELECT DISTINCT unnest(p_staff_ids));
  END IF;

  IF p_staff_ids IS NOT NULL THEN
    FOREACH v_staff_id IN ARRAY p_staff_ids
    LOOP
      PERFORM auth_internal.assert_shift_staff_eligible(v_staff_id, p_branch_id);
    END LOOP;
  END IF;

  PERFORM auth_internal.assert_no_staff_shift_overlap(
    p_branch_id,
    p_shift_date,
    p_start_time,
    p_end_time,
    COALESCE(p_staff_ids, '{}'::uuid[]),
    NULL
  );

  INSERT INTO public.shifts (
    organization_id,
    branch_id,
    shift_date,
    start_time,
    end_time,
    notes,
    created_by,
    updated_by
  )
  VALUES (
    v_branch.organization_id,
    p_branch_id,
    p_shift_date,
    p_start_time,
    p_end_time,
    v_notes,
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_shift_id;

  IF p_staff_ids IS NOT NULL THEN
    FOREACH v_staff_id IN ARRAY p_staff_ids
    LOOP
      INSERT INTO public.shift_assignments (shift_id, staff_member_id, created_by, updated_by)
      VALUES (v_shift_id, v_staff_id, auth.uid(), auth.uid());
    END LOOP;
  END IF;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_branch.organization_id,
    'shift.create',
    'shifts',
    v_shift_id,
    jsonb_build_object(
      'branch_id', p_branch_id,
      'shift_date', p_shift_date,
      'start_time', to_char(p_start_time, 'HH24:MI'),
      'end_time', to_char(p_end_time, 'HH24:MI'),
      'staff_ids', COALESCE(to_jsonb(p_staff_ids), '[]'::jsonb),
      'notes', v_notes
    )
  );

  RETURN v_shift_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.modify_shift_assignments
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.modify_shift_assignments(
  p_shift_id uuid,
  p_expected_updated_at timestamptz,
  p_add_staff_ids uuid[] DEFAULT '{}',
  p_remove_staff_ids uuid[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shift public.shifts%ROWTYPE;
  v_staff_id uuid;
  v_assignee_count int;
  v_status text;
  v_new_updated_at timestamptz;
  v_add_ids uuid[];
  v_remove_ids uuid[];
BEGIN
  PERFORM auth_internal.assert_shifts_manage();

  IF p_shift_id IS NULL THEN
    RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0001';
  END IF;

  SELECT *
  INTO v_shift
  FROM public.shifts s
  WHERE s.id = p_shift_id
    AND s.organization_id = public.jwt_organization_id()
    AND s.branch_id = ANY (public.jwt_branch_ids())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_shift.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'shift_cancelled' USING ERRCODE = 'P0001';
  END IF;

  PERFORM auth_internal.assert_shift_mutable(v_shift.shift_date);

  IF p_expected_updated_at IS NULL OR v_shift.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'stale_shift' USING ERRCODE = 'P0001';
  END IF;

  v_add_ids := ARRAY(SELECT DISTINCT unnest(COALESCE(p_add_staff_ids, '{}'::uuid[])));
  v_remove_ids := ARRAY(SELECT DISTINCT unnest(COALESCE(p_remove_staff_ids, '{}'::uuid[])));

  IF cardinality(v_add_ids) = 0 AND cardinality(v_remove_ids) = 0 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE = 'P0001';
  END IF;

  FOREACH v_staff_id IN ARRAY v_remove_ids
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM public.shift_assignments sa
      WHERE sa.shift_id = p_shift_id
        AND sa.staff_member_id = v_staff_id
    ) THEN
      RAISE EXCEPTION 'staff_not_eligible' USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.shift_assignments sa
    WHERE sa.shift_id = p_shift_id
      AND sa.staff_member_id = v_staff_id;

    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
    VALUES (
      auth.uid(),
      v_shift.organization_id,
      'shift.assignment.remove',
      'shift_assignments',
      p_shift_id,
      jsonb_build_object('shift_id', p_shift_id, 'staff_member_id', v_staff_id)
    );
  END LOOP;

  FOREACH v_staff_id IN ARRAY v_add_ids
  LOOP
    PERFORM auth_internal.assert_shift_staff_eligible(v_staff_id, v_shift.branch_id);

    IF EXISTS (
      SELECT 1
      FROM public.shift_assignments sa
      WHERE sa.shift_id = p_shift_id
        AND sa.staff_member_id = v_staff_id
    ) THEN
      RAISE EXCEPTION 'staff_already_assigned' USING ERRCODE = 'P0001';
    END IF;

    PERFORM auth_internal.assert_no_staff_shift_overlap(
      v_shift.branch_id,
      v_shift.shift_date,
      v_shift.start_time,
      v_shift.end_time,
      ARRAY[v_staff_id]::uuid[],
      p_shift_id
    );

    INSERT INTO public.shift_assignments (shift_id, staff_member_id, created_by, updated_by)
    VALUES (p_shift_id, v_staff_id, auth.uid(), auth.uid());

    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
    VALUES (
      auth.uid(),
      v_shift.organization_id,
      'shift.assignment.add',
      'shift_assignments',
      p_shift_id,
      jsonb_build_object('shift_id', p_shift_id, 'staff_member_id', v_staff_id)
    );
  END LOOP;

  v_new_updated_at := now();

  UPDATE public.shifts
  SET updated_at = v_new_updated_at,
      updated_by = auth.uid()
  WHERE id = p_shift_id;

  v_assignee_count := auth_internal.shift_assignee_count(p_shift_id);
  v_status := auth_internal.derive_shift_status(NULL, v_assignee_count);

  RETURN jsonb_build_object(
    'shift_id', p_shift_id,
    'status', v_status,
    'assignee_count', v_assignee_count,
    'updated_at', v_new_updated_at
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.update_shift
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.update_shift(
  p_shift_id uuid,
  p_expected_updated_at timestamptz,
  p_shift_date date,
  p_start_time time,
  p_end_time time,
  p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shift public.shifts%ROWTYPE;
  v_notes text;
  v_org_today date;
  v_staff_ids uuid[];
  v_prior jsonb;
  v_new jsonb;
BEGIN
  PERFORM auth_internal.assert_shifts_manage();

  IF p_shift_id IS NULL THEN
    RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0001';
  END IF;

  SELECT *
  INTO v_shift
  FROM public.shifts s
  WHERE s.id = p_shift_id
    AND s.organization_id = public.jwt_organization_id()
    AND s.branch_id = ANY (public.jwt_branch_ids())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_shift.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'shift_cancelled' USING ERRCODE = 'P0001';
  END IF;

  PERFORM auth_internal.assert_shift_mutable(v_shift.shift_date);

  IF p_expected_updated_at IS NULL OR v_shift.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'stale_shift' USING ERRCODE = 'P0001';
  END IF;

  v_org_today := auth_internal.get_org_today(v_shift.organization_id);

  IF p_shift_date IS NULL OR p_shift_date < v_org_today THEN
    RAISE EXCEPTION 'shift_read_only_past_date' USING ERRCODE = 'P0001';
  END IF;

  IF p_end_time IS NULL OR p_start_time IS NULL OR p_end_time <= p_start_time THEN
    RAISE EXCEPTION 'shift_invalid_time_range' USING ERRCODE = 'P0001';
  END IF;

  v_notes := NULLIF(trim(COALESCE(p_notes, '')), '');

  IF v_notes IS NOT NULL AND length(v_notes) > 500 THEN
    RAISE EXCEPTION 'notes_too_long' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(array_agg(sa.staff_member_id), '{}'::uuid[])
  INTO v_staff_ids
  FROM public.shift_assignments sa
  WHERE sa.shift_id = p_shift_id;

  IF cardinality(v_staff_ids) > 0 THEN
    PERFORM auth_internal.assert_no_staff_shift_overlap(
      v_shift.branch_id,
      p_shift_date,
      p_start_time,
      p_end_time,
      v_staff_ids,
      p_shift_id
    );
  END IF;

  v_prior := jsonb_build_object(
    'shift_date', v_shift.shift_date,
    'start_time', to_char(v_shift.start_time, 'HH24:MI'),
    'end_time', to_char(v_shift.end_time, 'HH24:MI'),
    'notes', v_shift.notes
  );

  v_new := jsonb_build_object(
    'shift_date', p_shift_date,
    'start_time', to_char(p_start_time, 'HH24:MI'),
    'end_time', to_char(p_end_time, 'HH24:MI'),
    'notes', v_notes
  );

  UPDATE public.shifts
  SET shift_date = p_shift_date,
      start_time = p_start_time,
      end_time = p_end_time,
      notes = v_notes,
      updated_at = now(),
      updated_by = auth.uid()
  WHERE id = p_shift_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_shift.organization_id,
    'shift.update',
    'shifts',
    p_shift_id,
    v_prior,
    v_new
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.cancel_shift
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.cancel_shift(
  p_shift_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shift public.shifts%ROWTYPE;
BEGIN
  PERFORM auth_internal.assert_shifts_manage();

  IF p_shift_id IS NULL THEN
    RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0001';
  END IF;

  SELECT *
  INTO v_shift
  FROM public.shifts s
  WHERE s.id = p_shift_id
    AND s.organization_id = public.jwt_organization_id()
    AND s.branch_id = ANY (public.jwt_branch_ids())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_shift.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'shift_cancelled' USING ERRCODE = 'P0001';
  END IF;

  PERFORM auth_internal.assert_shift_mutable(v_shift.shift_date);

  IF p_expected_updated_at IS NULL OR v_shift.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'stale_shift' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.shifts
  SET deleted_at = now(),
      deleted_by = auth.uid(),
      updated_at = now(),
      updated_by = auth.uid()
  WHERE id = p_shift_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_shift.organization_id,
    'shift.cancel',
    'shifts',
    p_shift_id,
    jsonb_build_object(
      'shift_id', p_shift_id,
      'shift_date', v_shift.shift_date,
      'start_time', to_char(v_shift.start_time, 'HH24:MI'),
      'end_time', to_char(v_shift.end_time, 'HH24:MI')
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- Public RPC wrappers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_shift(
  p_branch_id uuid,
  p_shift_date date,
  p_start_time time,
  p_end_time time,
  p_notes text DEFAULT NULL,
  p_staff_ids uuid[] DEFAULT '{}'
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_shift(
    p_branch_id,
    p_shift_date,
    p_start_time,
    p_end_time,
    p_notes,
    p_staff_ids
  );
$$;

CREATE OR REPLACE FUNCTION public.list_shifts(
  p_branch_id uuid,
  p_date_from date,
  p_date_to date
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_shifts(p_branch_id, p_date_from, p_date_to);
$$;

CREATE OR REPLACE FUNCTION public.get_shift_detail(p_shift_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_shift_detail(p_shift_id);
$$;

CREATE OR REPLACE FUNCTION public.modify_shift_assignments(
  p_shift_id uuid,
  p_expected_updated_at timestamptz,
  p_add_staff_ids uuid[] DEFAULT '{}',
  p_remove_staff_ids uuid[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.modify_shift_assignments(
    p_shift_id,
    p_expected_updated_at,
    p_add_staff_ids,
    p_remove_staff_ids
  );
$$;

CREATE OR REPLACE FUNCTION public.update_shift(
  p_shift_id uuid,
  p_expected_updated_at timestamptz,
  p_shift_date date,
  p_start_time time,
  p_end_time time,
  p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_shift(
    p_shift_id,
    p_expected_updated_at,
    p_shift_date,
    p_start_time,
    p_end_time,
    p_notes
  );
$$;

CREATE OR REPLACE FUNCTION public.cancel_shift(
  p_shift_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.cancel_shift(p_shift_id, p_expected_updated_at);
$$;

GRANT EXECUTE ON FUNCTION public.create_shift(uuid, date, time, time, text, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_shifts(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_shift_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.modify_shift_assignments(uuid, timestamptz, uuid[], uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_shift(uuid, timestamptz, date, time, time, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_shift(uuid, timestamptz) TO authenticated;

REVOKE ALL ON FUNCTION auth_internal.staff_has_shifts_manage() FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION auth_internal.staff_has_shifts_manage() TO authenticated;

-- -----------------------------------------------------------------------------
-- Test fixture teardown: include shifts in operational dependents delete
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.delete_clinic_operational_dependents()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.delete_billing_dependents();

  IF to_regclass('public.shift_assignments') IS NOT NULL THEN
    DELETE FROM public.shift_assignments;
  END IF;
  IF to_regclass('public.shifts') IS NOT NULL THEN
    DELETE FROM public.shifts;
  END IF;

  IF to_regclass('public.visit_attachments') IS NOT NULL THEN
    DELETE FROM public.visit_attachments;
  END IF;
  IF to_regclass('public.soap_notes') IS NOT NULL THEN
    DELETE FROM public.soap_notes;
  END IF;
  IF to_regclass('public.treatment_plans') IS NOT NULL THEN
    DELETE FROM public.treatment_plans;
  END IF;
  IF to_regclass('public.visits') IS NOT NULL THEN
    DELETE FROM public.visits;
  END IF;

  IF to_regclass('public.appointments') IS NOT NULL THEN
    DELETE FROM public.appointments;
  END IF;

  DELETE FROM public.patients;
END;
$$;
