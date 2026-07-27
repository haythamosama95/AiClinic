-- Match patient and invoice list searches against MRN (016 polish).

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
  v_escaped_mrn_query text;
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
    v_escaped_mrn_query :=
      replace(replace(replace(upper(v_query), '\', '\\'), '%', '\%'), '_', '\_');

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
        v_escaped_mrn_query IS NOT NULL
        AND upper(p.mrn) LIKE '%' || v_escaped_mrn_query || '%' ESCAPE '\'
      )
      OR (
        NOT v_is_phone
        AND v_escaped_name_query IS NOT NULL
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
        'mrn', sub.mrn,
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
      p.mrn,
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
          v_escaped_mrn_query IS NOT NULL
          AND upper(p.mrn) LIKE '%' || v_escaped_mrn_query || '%' ESCAPE '\'
        )
        OR (
          NOT v_is_phone
          AND v_escaped_name_query IS NOT NULL
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

CREATE OR REPLACE FUNCTION auth_internal.list_invoices(
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items jsonb;
  v_branch_ids uuid[];
  v_statuses text[];
  v_patient_id uuid;
  v_visit_id uuid;
  v_patient_search text;
  v_patient_search_pattern text;
  v_invoice_number text;
  v_invoice_number_pattern text;
  v_date_from timestamptz;
  v_date_to timestamptz;
  v_limit int := greatest(coalesce(p_limit, 50), 1);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_fetch_limit int;
  v_has_more boolean := false;
  v_item_count int;
BEGIN
  PERFORM auth_internal.assert_permission('invoices.view');

  IF p_filters ? 'branch_ids' AND jsonb_typeof(p_filters -> 'branch_ids') = 'array' THEN
    SELECT COALESCE(array_agg(value::uuid), ARRAY[]::uuid[])
    INTO v_branch_ids
    FROM jsonb_array_elements_text(p_filters -> 'branch_ids') AS value;
  END IF;

  IF p_filters ? 'statuses' AND jsonb_typeof(p_filters -> 'statuses') = 'array' THEN
    SELECT COALESCE(array_agg(value), ARRAY[]::text[])
    INTO v_statuses
    FROM jsonb_array_elements_text(p_filters -> 'statuses') AS value;
  END IF;

  IF p_filters ? 'patient_id' THEN
    v_patient_id := nullif(trim(p_filters ->> 'patient_id'), '')::uuid;
  END IF;

  IF p_filters ? 'visit_id' THEN
    v_visit_id := nullif(trim(p_filters ->> 'visit_id'), '')::uuid;
  END IF;

  v_patient_search := nullif(trim(p_filters ->> 'patient_search'), '');
  v_invoice_number := nullif(trim(p_filters ->> 'invoice_number'), '');

  IF v_patient_search IS NOT NULL THEN
    v_patient_search_pattern :=
      replace(replace(replace(v_patient_search, '\', '\\'), '%', '\%'), '_', '\_');
  END IF;

  IF v_invoice_number IS NOT NULL THEN
    v_invoice_number_pattern :=
      replace(replace(replace(v_invoice_number, '\', '\\'), '%', '\%'), '_', '\_');
  END IF;

  IF p_filters ? 'date_from' THEN
    v_date_from := nullif(trim(p_filters ->> 'date_from'), '')::timestamptz;
  END IF;

  IF p_filters ? 'date_to' THEN
    v_date_to := nullif(trim(p_filters ->> 'date_to'), '')::timestamptz;
  END IF;

  v_fetch_limit := v_limit + 1;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', sub.id,
        'invoice_number', sub.invoice_number,
        'status', sub.status,
        'patient_display_name', sub.patient_display_name,
        'patient_mrn', sub.patient_mrn,
        'branch_code', sub.branch_code,
        'subtotal', sub.subtotal,
        'discount_amount', sub.discount_amount,
        'insurance_covered_amount', sub.insurance_covered_amount,
        'paid_amount', sub.paid_amount,
        'balance', sub.balance,
        'currency', sub.currency,
        'created_at', sub.created_at,
        'issued_at', sub.issued_at,
        'payments', sub.payments
      )
      ORDER BY sub.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      i.id,
      i.invoice_number,
      i.status::text AS status,
      p.full_name AS patient_display_name,
      p.mrn AS patient_mrn,
      b.code AS branch_code,
      i.subtotal,
      i.discount_amount,
      i.insurance_covered_amount,
      COALESCE(pay.paid_amount, 0)::numeric(14, 2) AS paid_amount,
      auth_internal.compute_invoice_balance(i.id) AS balance,
      i.currency,
      i.created_at,
      i.issued_at,
      COALESCE(pay_lines.payments, '[]'::jsonb) AS payments
    FROM public.invoices i
    JOIN public.patients p ON p.id = i.patient_id
    JOIN public.branches b ON b.id = i.branch_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(sum(pm.amount), 0) AS paid_amount
      FROM public.payments pm
      WHERE pm.invoice_id = i.id
    ) pay ON true
    LEFT JOIN LATERAL (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', pm.id,
            'method', pm.method,
            'amount', pm.amount,
            'note', pm.note,
            'recorded_by', jsonb_build_object(
              'id', pm.recorded_by,
              'display_name', sm.full_name
            ),
            'recorded_at', pm.recorded_at
          )
          ORDER BY pm.recorded_at
        ),
        '[]'::jsonb
      ) AS payments
      FROM public.payments pm
      LEFT JOIN public.staff_members sm ON sm.id = pm.recorded_by
      WHERE pm.invoice_id = i.id
    ) pay_lines ON true
    WHERE i.is_deleted = false
      AND i.branch_id = ANY (public.jwt_branch_ids())
      AND (
        v_branch_ids IS NULL
        OR cardinality(v_branch_ids) = 0
        OR i.branch_id = ANY (v_branch_ids)
      )
      AND (
        v_statuses IS NULL
        OR cardinality(v_statuses) = 0
        OR i.status::text = ANY (v_statuses)
      )
      AND (v_patient_id IS NULL OR i.patient_id = v_patient_id)
      AND (v_visit_id IS NULL OR i.visit_id = v_visit_id)
      AND (
        v_patient_search IS NULL
        OR p.full_name ILIKE '%' || v_patient_search_pattern || '%' ESCAPE '\'
        OR upper(p.mrn) LIKE '%' || upper(v_patient_search_pattern) || '%' ESCAPE '\'
        OR i.invoice_number ILIKE '%' || v_patient_search_pattern || '%' ESCAPE '\'
      )
      AND (
        v_invoice_number IS NULL
        OR i.invoice_number = v_invoice_number
        OR i.invoice_number ILIKE v_invoice_number_pattern || '%' ESCAPE '\'
      )
      AND (v_date_from IS NULL OR i.created_at >= v_date_from)
      AND (v_date_to IS NULL OR i.created_at <= v_date_to)
    ORDER BY i.created_at DESC
    LIMIT v_fetch_limit
    OFFSET v_offset
  ) sub;

  v_item_count := COALESCE(jsonb_array_length(v_items), 0);
  IF v_item_count > v_limit THEN
    v_has_more := true;
    SELECT COALESCE(jsonb_agg(elem ORDER BY ord), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT elem, ord
      FROM jsonb_array_elements(v_items) WITH ORDINALITY AS t(elem, ord)
      WHERE ord <= v_limit
    ) trimmed;
  END IF;

  RETURN public.rpc_success(jsonb_build_object('items', v_items, 'has_more', v_has_more));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list invoices.');
    END IF;
    RAISE;
END;
$$;
