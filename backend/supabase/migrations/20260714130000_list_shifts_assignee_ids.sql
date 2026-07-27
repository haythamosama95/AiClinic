-- C3: expose stable staff ids alongside assignee_names in list_shifts so the
-- appointments queue can resolve doctors by id instead of display-name matching.

DROP FUNCTION IF EXISTS public.list_shifts(uuid, date, date, boolean);
DROP FUNCTION IF EXISTS auth_internal.list_shifts(uuid, date, date, boolean);

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
        'assignee_ids', sub.assignee_ids,
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
      COALESCE(
        jsonb_agg(sm.id::text ORDER BY sm.full_name) FILTER (WHERE sm.id IS NOT NULL),
        '[]'::jsonb
      ) AS assignee_ids,
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
