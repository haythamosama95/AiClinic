-- Push patient list last-visit filters and sort ordering into search_patients so
-- pagination and total_count stay consistent across pages.

DROP FUNCTION IF EXISTS public.search_patients(text, text, uuid, int, int);
DROP FUNCTION IF EXISTS auth_internal.search_patients(text, text, uuid, int, int);

CREATE OR REPLACE FUNCTION auth_internal.search_patients(
  p_query text DEFAULT NULL,
  p_scope text DEFAULT 'branch',
  p_branch_id uuid DEFAULT NULL,
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0,
  p_last_visit_filter text DEFAULT 'any',
  p_sort_field text DEFAULT 'name_asc'
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_query text;
  v_scope text;
  v_is_phone boolean := false;
  v_phone_prefix text;
  v_name_query text;
  v_escaped_name_query text;
  v_limit int;
  v_offset int;
  v_last_visit_filter text;
  v_sort_field text;
  v_items jsonb;
  v_total int;
BEGIN
  PERFORM auth_internal.assert_permission('patients.view');
  v_org_id := public.jwt_organization_id();

  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  v_scope := lower(trim(COALESCE(p_scope, '')));
  IF v_scope NOT IN ('branch', 'organization') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Scope must be branch or organization.');
  END IF;

  IF v_scope = 'branch' THEN
    IF p_branch_id IS NULL THEN
      RETURN public.rpc_error('BRANCH_REQUIRED', 'Branch id is required for branch scope.');
    END IF;

    IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Branch is not in your assigned branches.');
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = p_branch_id
        AND b.organization_id = v_org_id
        AND b.is_deleted = false
        AND b.is_active = true
    ) THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Branch is not active for this organization.');
    END IF;
  END IF;

  v_query := NULLIF(trim(COALESCE(p_query, '')), '');
  IF v_query IS NOT NULL THEN
    IF v_query ~ '^[0-9]+$' THEN
      IF length(v_query) < 2 THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Phone search requires at least 2 digits.');
      END IF;
      v_is_phone := true;
      v_phone_prefix := v_query;
    ELSE
      IF length(v_query) < 3 THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Name search requires at least 3 characters.');
      END IF;
      v_name_query := lower(v_query);
      v_escaped_name_query := replace(replace(replace(v_name_query, '\', '\\'), '%', '\%'), '_', '\_');
    END IF;
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  v_last_visit_filter := lower(trim(COALESCE(p_last_visit_filter, 'any')));
  IF v_last_visit_filter NOT IN ('any', 'last_30_days', 'last_90_days', 'over_90_days', 'never') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Last visit filter is invalid.');
  END IF;

  v_sort_field := lower(trim(COALESCE(p_sort_field, 'name_asc')));
  IF v_sort_field NOT IN ('name_asc', 'name_desc', 'last_visit_asc', 'last_visit_desc') THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Sort field is invalid.');
  END IF;

  SELECT count(*)
  INTO v_total
  FROM public.patients p
  WHERE p.is_deleted = false
    AND p.organization_id = v_org_id
    AND (
      v_scope = 'organization'
      OR p.branch_id = p_branch_id
    )
    AND (
      v_query IS NULL
      OR (
        v_is_phone
        AND p.phone LIKE v_phone_prefix || '%'
      )
      OR (
        NOT v_is_phone
        AND lower(p.full_name) LIKE '%' || v_escaped_name_query || '%' ESCAPE '\'
      )
    )
    AND (
      v_last_visit_filter = 'any'
      OR (
        v_last_visit_filter = 'never'
        AND NOT EXISTS (
          SELECT 1
          FROM public.visits v
          WHERE v.patient_id = p.id
            AND v.is_deleted = false
            AND v.status = 'completed'
        )
      )
      OR (
        v_last_visit_filter = 'last_30_days'
        AND (
          SELECT MAX(v.visit_date)
          FROM public.visits v
          WHERE v.patient_id = p.id
            AND v.is_deleted = false
            AND v.status = 'completed'
        ) >= (CURRENT_DATE - INTERVAL '30 days')
      )
      OR (
        v_last_visit_filter = 'last_90_days'
        AND (
          SELECT MAX(v.visit_date)
          FROM public.visits v
          WHERE v.patient_id = p.id
            AND v.is_deleted = false
            AND v.status = 'completed'
        ) >= (CURRENT_DATE - INTERVAL '90 days')
      )
      OR (
        v_last_visit_filter = 'over_90_days'
        AND (
          SELECT MAX(v.visit_date)
          FROM public.visits v
          WHERE v.patient_id = p.id
            AND v.is_deleted = false
            AND v.status = 'completed'
        ) < (CURRENT_DATE - INTERVAL '90 days')
      )
    );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sub.id,
        'full_name', sub.full_name,
        'phone', sub.phone,
        'date_of_birth', sub.date_of_birth,
        'gender', sub.gender,
        'marital_status', sub.marital_status,
        'branch_id', sub.branch_id,
        'branch_name', sub.branch_name,
        'last_visit_at', sub.last_visit_at,
        'next_appointment_at', sub.next_appointment_at
      )
      ORDER BY
        sub.name_match_rank ASC,
        CASE WHEN v_sort_field = 'name_asc' THEN lower(sub.full_name) END ASC NULLS LAST,
        CASE WHEN v_sort_field = 'name_desc' THEN lower(sub.full_name) END DESC NULLS LAST,
        CASE WHEN v_sort_field = 'last_visit_asc' THEN sub.last_visit_at END ASC NULLS LAST,
        CASE WHEN v_sort_field = 'last_visit_desc' THEN sub.last_visit_at END DESC NULLS LAST,
        sub.id ASC
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      p.id,
      p.full_name,
      p.phone,
      p.date_of_birth,
      p.gender::text,
      p.marital_status::text,
      p.branch_id,
      b.name AS branch_name,
      lv.last_visit_at,
      na.next_appointment_at,
      CASE
        WHEN v_query IS NOT NULL
          AND NOT v_is_phone
          AND lower(p.full_name) LIKE v_escaped_name_query || '%' ESCAPE '\'
        THEN 0
        ELSE 1
      END AS name_match_rank
    FROM public.patients p
    JOIN public.branches b ON b.id = p.branch_id
    LEFT JOIN LATERAL (
      SELECT MAX(v.visit_date) AS last_visit_at
      FROM public.visits v
      WHERE v.patient_id = p.id
        AND v.is_deleted = false
        AND v.status = 'completed'
    ) lv ON true
    LEFT JOIN LATERAL (
      SELECT MIN(a.start_time) AS next_appointment_at
      FROM public.appointments a
      WHERE a.patient_id = p.id
        AND a.is_deleted = false
        AND a.start_time > now()
        AND a.status IN ('scheduled', 'confirmed', 'checked_in')
    ) na ON true
    WHERE p.is_deleted = false
      AND p.organization_id = v_org_id
      AND (
        v_scope = 'organization'
        OR p.branch_id = p_branch_id
      )
      AND (
        v_query IS NULL
        OR (
          v_is_phone
          AND p.phone LIKE v_phone_prefix || '%'
        )
        OR (
          NOT v_is_phone
          AND lower(p.full_name) LIKE '%' || v_escaped_name_query || '%' ESCAPE '\'
        )
      )
      AND (
        v_last_visit_filter = 'any'
        OR (
          v_last_visit_filter = 'never'
          AND lv.last_visit_at IS NULL
        )
        OR (
          v_last_visit_filter = 'last_30_days'
          AND lv.last_visit_at >= (CURRENT_DATE - INTERVAL '30 days')
        )
        OR (
          v_last_visit_filter = 'last_90_days'
          AND lv.last_visit_at >= (CURRENT_DATE - INTERVAL '90 days')
        )
        OR (
          v_last_visit_filter = 'over_90_days'
          AND lv.last_visit_at < (CURRENT_DATE - INTERVAL '90 days')
        )
      )
    ORDER BY
      name_match_rank ASC,
      CASE WHEN v_sort_field = 'name_asc' THEN lower(p.full_name) END ASC NULLS LAST,
      CASE WHEN v_sort_field = 'name_desc' THEN lower(p.full_name) END DESC NULLS LAST,
      CASE WHEN v_sort_field = 'last_visit_asc' THEN lv.last_visit_at END ASC NULLS LAST,
      CASE WHEN v_sort_field = 'last_visit_desc' THEN lv.last_visit_at END DESC NULLS LAST,
      p.id ASC
    LIMIT v_limit OFFSET v_offset
  ) sub;

  RETURN public.rpc_success(
    jsonb_build_object(
      'items', COALESCE(v_items, '[]'::jsonb),
      'total_count', COALESCE(v_total, 0),
      'limit', v_limit,
      'offset', v_offset
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view patients.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_patients(
  p_query text DEFAULT NULL,
  p_scope text DEFAULT 'branch',
  p_branch_id uuid DEFAULT NULL,
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0,
  p_last_visit_filter text DEFAULT 'any',
  p_sort_field text DEFAULT 'name_asc'
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.search_patients(
    p_query,
    p_scope,
    p_branch_id,
    p_limit,
    p_offset,
    p_last_visit_filter,
    p_sort_field
  );
$$;

GRANT EXECUTE ON FUNCTION auth_internal.search_patients(text, text, uuid, int, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_patients(text, text, uuid, int, int, text, text) TO authenticated;
