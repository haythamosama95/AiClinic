-- =============================================================================
-- V1-6: Fix billing review items #4, #8, #10 (doc), #12
-- =============================================================================

-- -----------------------------------------------------------------------------
-- lock_draft_invoice: document permission model (#10)
-- Caller RPCs must invoke assert_permission before lock_draft_invoice; the lock
-- helper only enforces branch membership via jwt_branch_ids(), not invoices.view.
-- -----------------------------------------------------------------------------

COMMENT ON FUNCTION auth_internal.lock_draft_invoice(uuid, timestamptz) IS
  'Row-locks a draft invoice for mutation. Branch scope via jwt_branch_ids() only; '
  'caller RPCs must assert invoices.create (or equivalent) before calling.';

-- -----------------------------------------------------------------------------
-- add_invoice_item / update_invoice_item: enforce description length (#4)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.add_invoice_item(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz,
  p_description text,
  p_quantity numeric,
  p_unit_price numeric
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_item_id uuid;
  v_description text := trim(p_description);
  v_line_subtotal numeric(14, 2);
BEGIN
  PERFORM auth_internal.assert_permission('invoices.create');
  v_org_id := public.jwt_organization_id();

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(p_invoice_id, p_expected_updated_at);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_voided' THEN
        RETURN public.rpc_error('INVOICE_VOIDED', 'Line items cannot be changed on voided invoices.');
      ELSIF SQLERRM = 'invoice_not_in_draft' THEN
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Line items can only be changed on draft invoices.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  IF v_description IS NULL OR v_description = '' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Description is required.');
  END IF;

  IF char_length(v_description) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Description must be 500 characters or fewer.');
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Quantity must be greater than zero.');
  END IF;

  IF p_unit_price IS NULL OR p_unit_price < 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Unit price cannot be negative.');
  END IF;

  v_line_subtotal := round(p_quantity * p_unit_price, 2);

  INSERT INTO public.invoice_items (
    invoice_id,
    description,
    quantity,
    unit_price,
    line_subtotal,
    line_discount_amount,
    line_total,
    created_by,
    updated_by
  )
  VALUES (
    p_invoice_id,
    v_description,
    p_quantity,
    p_unit_price,
    v_line_subtotal,
    0.00,
    v_line_subtotal,
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_item_id;

  PERFORM auth_internal.refresh_invoice_subtotal(p_invoice_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.item.add',
    'invoice_items',
    v_item_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'item_id', v_item_id,
      'description', v_description,
      'quantity', p_quantity,
      'unit_price', p_unit_price
    )
  );

  RETURN public.rpc_success(jsonb_build_object('item_id', v_item_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit invoice items.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.update_invoice_item(
  p_item_id uuid,
  p_expected_updated_at timestamptz,
  p_description text,
  p_quantity numeric,
  p_unit_price numeric
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item public.invoice_items%ROWTYPE;
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_description text := trim(p_description);
  v_line_subtotal numeric(14, 2);
BEGIN
  PERFORM auth_internal.assert_permission('invoices.create');
  v_org_id := public.jwt_organization_id();

  SELECT ii.*
  INTO v_item
  FROM public.invoice_items ii
  WHERE ii.id = p_item_id
    AND ii.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Invoice item was not found.');
  END IF;

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(v_item.invoice_id, p_expected_updated_at);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_voided' THEN
        RETURN public.rpc_error('INVOICE_VOIDED', 'Line items cannot be changed on voided invoices.');
      ELSIF SQLERRM = 'invoice_not_in_draft' THEN
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Line items can only be changed on draft invoices.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  IF v_description IS NULL OR v_description = '' THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Description is required.');
  END IF;

  IF char_length(v_description) > 500 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Description must be 500 characters or fewer.');
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Quantity must be greater than zero.');
  END IF;

  IF p_unit_price IS NULL OR p_unit_price < 0 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Unit price cannot be negative.');
  END IF;

  v_line_subtotal := round(p_quantity * p_unit_price, 2);

  UPDATE public.invoice_items ii
  SET
    description = v_description,
    quantity = p_quantity,
    unit_price = p_unit_price,
    line_subtotal = v_line_subtotal,
    line_discount_amount = 0,
    line_total = v_line_subtotal,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE ii.id = p_item_id;

  PERFORM auth_internal.recompute_item_line_totals(p_item_id);
  PERFORM auth_internal.refresh_invoice_subtotal(v_item.invoice_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.item.update',
    'invoice_items',
    p_item_id,
    jsonb_build_object(
      'invoice_id', v_item.invoice_id,
      'item_id', p_item_id,
      'description', v_description,
      'quantity', p_quantity,
      'unit_price', p_unit_price
    )
  );

  RETURN public.rpc_success(jsonb_build_object('item_id', p_item_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to edit invoice items.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- apply_line_discount: allow idempotent clear when no line discount exists (#8)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.apply_line_discount(
  p_item_id uuid,
  p_expected_updated_at timestamptz,
  p_kind public.discount_kind,
  p_value numeric
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item public.invoice_items%ROWTYPE;
  v_invoice public.invoices%ROWTYPE;
  v_invoice_status public.invoice_status;
  v_org_id uuid;
  v_prior_kind public.discount_kind;
  v_prior_value numeric(14, 2);
  v_prior_amount numeric(14, 2);
  v_line_subtotal numeric(14, 2);
BEGIN
  PERFORM auth_internal.assert_permission('invoices.apply_discount');
  v_org_id := public.jwt_organization_id();

  SELECT ii.*
  INTO v_item
  FROM public.invoice_items ii
  WHERE ii.id = p_item_id
    AND ii.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Invoice item was not found.');
  END IF;

  IF p_kind IS NULL AND p_value IS NULL
     AND v_item.line_discount_kind IS NULL
     AND COALESCE(v_item.line_discount_amount, 0) = 0 THEN
    RETURN public.rpc_success(jsonb_build_object('item_id', p_item_id));
  END IF;

  SELECT i.status
  INTO v_invoice_status
  FROM public.invoices i
  WHERE i.id = v_item.invoice_id
    AND i.is_deleted = false;

  IF v_invoice_status = 'voided' THEN
    RETURN public.rpc_error('INVOICE_VOIDED', 'Discounts cannot be changed on voided invoices.');
  END IF;

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(v_item.invoice_id, p_expected_updated_at);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_voided' THEN
        RETURN public.rpc_error('INVOICE_VOIDED', 'Discounts cannot be changed on voided invoices.');
      ELSIF SQLERRM = 'invoice_not_in_draft' THEN
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Discounts can only be changed on draft invoices.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  IF p_kind IS NULL AND p_value IS NULL THEN
    NULL;
  ELSIF COALESCE(v_invoice.discount_amount, 0) > 0 OR v_invoice.discount_kind IS NOT NULL THEN
    RETURN public.rpc_error(
      'DISCOUNT_SCOPE_CONFLICT',
      'Discount scopes are mutually exclusive — clear the invoice-level discount first.'
    );
  END IF;

  v_prior_kind := v_item.line_discount_kind;
  v_prior_value := v_item.line_discount_value;
  v_prior_amount := v_item.line_discount_amount;
  v_line_subtotal := round(v_item.quantity * v_item.unit_price, 2);

  IF p_kind IS NULL AND p_value IS NULL THEN
    UPDATE public.invoice_items ii
    SET
      line_discount_kind = NULL,
      line_discount_value = NULL,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE ii.id = p_item_id;
  ELSE
    IF p_kind IS NULL OR p_value IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Discount kind and value are required.');
    END IF;

    IF p_kind = 'percentage' THEN
      IF p_value < 0 OR p_value > 100 THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Percentage discount must be between 0 and 100.');
      END IF;
    ELSIF p_kind = 'fixed' THEN
      IF p_value < 0 OR p_value > v_line_subtotal THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Fixed discount cannot exceed the line subtotal.');
      END IF;
    ELSE
      RETURN public.rpc_error('INVALID_INPUT', 'Unsupported discount kind.');
    END IF;

    UPDATE public.invoice_items ii
    SET
      line_discount_kind = p_kind,
      line_discount_value = p_value,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE ii.id = p_item_id;
  END IF;

  PERFORM auth_internal.recompute_item_line_totals(p_item_id);
  PERFORM auth_internal.refresh_invoice_subtotal(v_item.invoice_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.discount.apply',
    'invoice_items',
    p_item_id,
    jsonb_build_object(
      'scope', 'line',
      'item_id', p_item_id,
      'invoice_id', v_item.invoice_id,
      'discount_kind', v_prior_kind,
      'discount_value', v_prior_value,
      'discount_amount', v_prior_amount
    ),
    jsonb_build_object(
      'scope', 'line',
      'item_id', p_item_id,
      'invoice_id', v_item.invoice_id,
      'discount_kind', p_kind,
      'discount_value', p_value
    )
  );

  RETURN public.rpc_success(jsonb_build_object('item_id', p_item_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to apply discounts.');
    ELSIF SQLERRM = 'discount_scope_conflict' THEN
      RETURN public.rpc_error(
        'DISCOUNT_SCOPE_CONFLICT',
        'Discount scopes are mutually exclusive — clear the invoice-level discount first.'
      );
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- list_invoices: escape ILIKE wildcards in invoice_number filter (#12)
-- -----------------------------------------------------------------------------

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
        'created_at', sub.created_at,
        'issued_at', sub.issued_at
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
      i.created_at,
      i.issued_at
    FROM public.invoices i
    JOIN public.patients p ON p.id = i.patient_id
    JOIN public.branches b ON b.id = i.branch_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(sum(pm.amount), 0) AS paid_amount
      FROM public.payments pm
      WHERE pm.invoice_id = i.id
    ) pay ON true
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
    LIMIT v_limit
    OFFSET v_offset
  ) sub;

  RETURN public.rpc_success(jsonb_build_object('items', v_items));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list invoices.');
    END IF;
    RAISE;
END;
$$;
