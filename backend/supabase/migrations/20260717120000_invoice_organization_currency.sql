-- Use organization currency when creating invoices and expose it on list queries.

-- Backfill existing invoices whose currency does not match the organization setting.
UPDATE public.invoices i
SET
  currency = upper(trim(o.currency_code)),
  updated_at = now()
FROM public.organizations o
WHERE i.organization_id = o.id
  AND o.currency_code IS NOT NULL
  AND trim(o.currency_code) <> ''
  AND upper(trim(o.currency_code)) <> upper(trim(i.currency));

CREATE OR REPLACE FUNCTION auth_internal.create_invoice_from_visit(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_visit public.visits%ROWTYPE;
  v_org_id uuid;
  v_invoice_id uuid;
  v_currency text;
BEGIN
  v_staff := auth_internal.assert_permission('invoices.create');
  v_org_id := public.jwt_organization_id();

  IF p_visit_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Visit ID is required.');
  END IF;

  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(p_visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  IF v_visit.status::text <> 'completed' THEN
    RETURN public.rpc_error(
      'VISIT_NOT_COMPLETED',
      'Every invoice must be tied to a completed visit.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.invoices i
    WHERE i.visit_id = p_visit_id
      AND i.is_deleted = false
      AND i.status <> 'voided'
  ) THEN
    RETURN public.rpc_error(
      'ACTIVE_INVOICE_EXISTS',
      'One active invoice per visit is allowed.'
    );
  END IF;

  SELECT upper(trim(o.currency_code))
  INTO v_currency
  FROM public.organizations o
  WHERE o.id = v_org_id;

  IF v_currency IS NULL OR v_currency = '' THEN
    v_currency := 'USD';
  END IF;

  INSERT INTO public.invoices (
    organization_id,
    branch_id,
    patient_id,
    visit_id,
    status,
    currency,
    created_by,
    updated_by,
    updated_at
  )
  VALUES (
    v_org_id,
    v_visit.branch_id,
    v_visit.patient_id,
    p_visit_id,
    'draft',
    v_currency,
    auth.uid(),
    auth.uid(),
    now()
  )
  RETURNING id INTO v_invoice_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.create_from_visit',
    'invoices',
    v_invoice_id,
    jsonb_build_object(
      'invoice_id', v_invoice_id,
      'visit_id', p_visit_id,
      'patient_id', v_visit.patient_id,
      'branch_id', v_visit.branch_id,
      'status', 'draft',
      'currency', v_currency
    )
  );

  RETURN public.rpc_success(jsonb_build_object('invoice_id', v_invoice_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to create invoices.');
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
            'reference', pm.reference,
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
        OR p.full_name ILIKE '%' || v_patient_search || '%'
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
