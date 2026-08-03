-- Remove payments.reference from schema, RPCs, and query payloads.

ALTER TABLE public.payments
  DROP COLUMN IF EXISTS reference;

CREATE OR REPLACE FUNCTION auth_internal.record_payment(
  p_invoice_id uuid,
  p_method public.payment_method,
  p_amount numeric,
  p_note text
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_prior_balance numeric(14, 2);
  v_new_balance numeric(14, 2);
  v_allow_partial boolean;
  v_prior_status public.invoice_status;
  v_new_status public.invoice_status;
  v_payment_id uuid;
  v_note text;
BEGIN
  v_staff := auth_internal.assert_permission('payments.record');
  v_org_id := public.jwt_organization_id();

  IF p_invoice_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Invoice ID is required.');
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Payment amount must be greater than zero.');
  END IF;

  v_note := nullif(trim(p_note), '');

  BEGIN
    v_invoice := auth_internal.lock_payable_invoice(p_invoice_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_voided' THEN
        RETURN public.rpc_error('INVOICE_VOIDED', 'Payments cannot be recorded on voided invoices.');
      ELSIF SQLERRM = 'invoice_not_payable' THEN
        RETURN public.rpc_error('INVOICE_NOT_PAYABLE', 'Payments can only be recorded on issued or partially paid invoices.');
      END IF;
      RAISE;
  END;

  v_prior_status := v_invoice.status;
  v_prior_balance := auth_internal.compute_invoice_balance(p_invoice_id);

  IF p_amount > v_prior_balance THEN
    RETURN public.rpc_error(
      'OVERPAYMENT',
      'Payment amount exceeds the current balance.'
    );
  END IF;

  SELECT obs.allow_partial_payments
  INTO v_allow_partial
  FROM public.organization_billing_settings obs
  WHERE obs.organization_id = v_org_id;

  IF coalesce(v_allow_partial, false) = false
     AND p_method IN ('cash', 'card', 'bank_transfer')
     AND p_amount < v_prior_balance THEN
    RETURN public.rpc_error(
      'PARTIAL_PAYMENTS_DISABLED',
      'Partial payments are not allowed for this organization; please collect the full balance.'
    );
  END IF;

  INSERT INTO public.payments (
    invoice_id,
    branch_id,
    method,
    amount,
    note,
    recorded_by
  )
  VALUES (
    p_invoice_id,
    v_invoice.branch_id,
    p_method,
    p_amount,
    v_note,
    v_staff.id
  )
  RETURNING id INTO v_payment_id;

  v_new_balance := auth_internal.compute_invoice_balance(p_invoice_id);
  v_new_status := auth_internal.recompute_invoice_status_after_payment(
    p_invoice_id,
    v_prior_status,
    v_new_balance
  );

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'payment.record',
    'payments',
    v_payment_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'payment_id', v_payment_id,
      'method', p_method::text,
      'amount', p_amount,
      'note', v_note,
      'prior_balance', v_prior_balance,
      'new_balance', v_new_balance,
      'prior_status', v_prior_status::text,
      'new_status', v_new_status::text
    )
  );

  RETURN public.rpc_success(jsonb_build_object('payment_id', v_payment_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to record payments.');
    END IF;
    RAISE;
END;
$$;

DROP FUNCTION IF EXISTS public.record_payment(uuid, public.payment_method, numeric, text, text);

CREATE OR REPLACE FUNCTION public.record_payment(
  p_invoice_id uuid,
  p_method public.payment_method,
  p_amount numeric,
  p_note text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.record_payment(p_invoice_id, p_method, p_amount, p_note);
$$;

GRANT EXECUTE ON FUNCTION public.record_payment(uuid, public.payment_method, numeric, text) TO authenticated;

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

CREATE OR REPLACE FUNCTION auth_internal.get_invoice_detail(p_invoice_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_items jsonb;
  v_payments jsonb;
  v_patient jsonb;
  v_branch jsonb;
  v_provider jsonb;
  v_visit jsonb;
  v_balance numeric(14, 2);
BEGIN
  PERFORM auth_internal.assert_permission('invoices.view');
  v_org_id := public.jwt_organization_id();

  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false
    AND i.branch_id = ANY (public.jwt_branch_ids());

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
  END IF;

  IF v_invoice.status = 'voided' THEN
    v_balance := 0::numeric(14, 2);
  ELSE
    v_balance := auth_internal.compute_invoice_balance(p_invoice_id);
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ii.id,
        'description', ii.description,
        'quantity', ii.quantity,
        'unit_price', ii.unit_price,
        'line_subtotal', ii.line_subtotal,
        'line_discount_kind', ii.line_discount_kind,
        'line_discount_value', ii.line_discount_value,
        'line_discount_amount', ii.line_discount_amount,
        'line_total', ii.line_total
      )
      ORDER BY ii.created_at
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM public.invoice_items ii
  WHERE ii.invoice_id = p_invoice_id
    AND ii.is_deleted = false;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'method', p.method,
        'amount', p.amount,
        'note', p.note,
        'recorded_by', jsonb_build_object(
          'id', p.recorded_by,
          'display_name', sm.full_name
        ),
        'recorded_at', p.recorded_at
      )
      ORDER BY p.recorded_at
    ),
    '[]'::jsonb
  )
  INTO v_payments
  FROM public.payments p
  LEFT JOIN public.staff_members sm ON sm.id = p.recorded_by
  WHERE p.invoice_id = p_invoice_id;

  SELECT jsonb_build_object(
    'id', pt.id,
    'display_name', pt.full_name,
    'mrn', pt.mrn,
    'patient_mrn', pt.mrn
  )
  INTO v_patient
  FROM public.patients pt
  WHERE pt.id = v_invoice.patient_id;

  SELECT jsonb_build_object('id', b.id, 'code', b.code, 'name', b.name)
  INTO v_branch
  FROM public.branches b
  WHERE b.id = v_invoice.branch_id;

  IF v_invoice.insurance_provider_id IS NOT NULL THEN
    SELECT jsonb_build_object('id', ip.id, 'name', ip.name)
    INTO v_provider
    FROM public.insurance_providers ip
    WHERE ip.id = v_invoice.insurance_provider_id;
  END IF;

  SELECT jsonb_build_object(
    'visit_date', v.visit_date,
    'doctor_name', sm.full_name,
    'branch_name', vb.name
  )
  INTO v_visit
  FROM public.visits v
  LEFT JOIN public.staff_members sm ON sm.id = v.doctor_id AND sm.is_deleted = false
  LEFT JOIN public.branches vb ON vb.id = v.branch_id AND vb.is_deleted = false
  WHERE v.id = v_invoice.visit_id
    AND v.is_deleted = false;

  RETURN public.rpc_success(
    jsonb_build_object(
      'invoice', jsonb_build_object(
        'id', v_invoice.id,
        'invoice_number', v_invoice.invoice_number,
        'status', v_invoice.status::text,
        'branch_id', v_invoice.branch_id,
        'patient_id', v_invoice.patient_id,
        'visit_id', v_invoice.visit_id,
        'subtotal', v_invoice.subtotal,
        'discount_kind', v_invoice.discount_kind,
        'discount_value', v_invoice.discount_value,
        'discount_amount', v_invoice.discount_amount,
        'insurance_provider_id', v_invoice.insurance_provider_id,
        'insurance_covered_amount', v_invoice.insurance_covered_amount,
        'currency', v_invoice.currency,
        'issued_at', v_invoice.issued_at,
        'voided_at', v_invoice.voided_at,
        'void_reason', v_invoice.void_reason,
        'balance', v_balance,
        'updated_at', v_invoice.updated_at
      ),
      'items', v_items,
      'payments', v_payments,
      'patient', v_patient,
      'branch', v_branch,
      'insurance_provider', v_provider,
      'visit', v_visit
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view invoices.');
    END IF;
    RAISE;
END;
$$;
