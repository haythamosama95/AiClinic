-- Fix 8: Separate count query from paginated search to avoid count(*) OVER() materialization.
-- Also adds gender and marital_status to search results (Fix 33 prep).

CREATE OR REPLACE FUNCTION auth_internal.search_patients(
  p_query text DEFAULT NULL,
  p_scope text DEFAULT 'branch',
  p_branch_id uuid DEFAULT NULL,
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0
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

  -- Separate count query (avoids count(*) OVER() full materialization)
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
    );

  -- Data query with LIMIT/OFFSET (no window function)
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
        'branch_name', sub.branch_name
      )
      ORDER BY sub.full_name
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
      b.name AS branch_name
    FROM public.patients p
    JOIN public.branches b ON b.id = p.branch_id
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
    ORDER BY p.full_name ASC
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
