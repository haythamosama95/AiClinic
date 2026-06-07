-- Medium-severity shift fixes:
-- #8  shift_overlap conflicts in EXCEPTION DETAIL (stable client parsing channel)
-- #14 list_shifts: drop redundant cancelled filter, add p_include_cancelled
-- #15 list_shifts: enforce max 366-day inclusive date range

-- -----------------------------------------------------------------------------
-- auth_internal.assert_no_staff_shift_overlap — conflicts via DETAIL
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
    RAISE EXCEPTION 'shift_overlap' USING DETAIL = v_conflicts::text, ERRCODE = 'P0001';
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.list_shifts — include_cancelled + max range
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.list_shifts(uuid, date, date);
DROP FUNCTION IF EXISTS auth_internal.list_shifts(uuid, date, date);

CREATE OR REPLACE FUNCTION auth_internal.list_shifts(
  p_branch_id uuid,
  p_date_from date,
  p_date_to date,
  p_include_cancelled boolean DEFAULT false
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

  IF (p_date_to - p_date_from) > 366 THEN
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
      AND s.shift_date >= p_date_from
      AND s.shift_date <= p_date_to
      AND (p_include_cancelled OR s.deleted_at IS NULL)
    GROUP BY s.id
    ORDER BY s.shift_date, s.start_time
  ) sub;

  RETURN v_items;
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'permission_denied' THEN
      RAISE;
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_shifts(
  p_branch_id uuid,
  p_date_from date,
  p_date_to date,
  p_include_cancelled boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_shifts(p_branch_id, p_date_from, p_date_to, p_include_cancelled);
$$;

GRANT EXECUTE ON FUNCTION public.list_shifts(uuid, date, date, boolean) TO authenticated;
