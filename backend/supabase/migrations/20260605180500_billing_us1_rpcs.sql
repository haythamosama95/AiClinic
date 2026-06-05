-- =============================================================================
-- V1-6: Billing US1 RPCs (create/issue invoice, item mutations, detail/list)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Internal helpers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.recompute_item_line_totals(p_item_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item public.invoice_items%ROWTYPE;
  v_discount_amount numeric(14, 2);
BEGIN
  SELECT *
  INTO v_item
  FROM public.invoice_items ii
  WHERE ii.id = p_item_id
    AND ii.is_deleted = false;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_item.line_subtotal := round(v_item.quantity * v_item.unit_price, 2);

  IF v_item.line_discount_kind IS NULL OR v_item.line_discount_value IS NULL THEN
    v_discount_amount := 0.00;
  ELSIF v_item.line_discount_kind = 'percentage' THEN
    v_discount_amount := round(v_item.line_subtotal * v_item.line_discount_value / 100.0, 2);
  ELSE
    v_discount_amount := least(v_item.line_discount_value, v_item.line_subtotal);
  END IF;

  UPDATE public.invoice_items ii
  SET
    line_subtotal = v_item.line_subtotal,
    line_discount_amount = v_discount_amount,
    line_total = v_item.line_subtotal - v_discount_amount,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE ii.id = p_item_id;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.refresh_invoice_subtotal(p_invoice_id uuid)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_at timestamptz;
BEGIN
  UPDATE public.invoices i
  SET
    subtotal = auth_internal.compute_invoice_subtotal(p_invoice_id),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE i.id = p_invoice_id
  RETURNING i.updated_at INTO v_updated_at;

  RETURN v_updated_at;
END;
$$;

CREATE OR REPLACE FUNCTION auth_internal.lock_draft_invoice(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
BEGIN
  IF p_expected_updated_at IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT';
  END IF;

  SELECT *
  INTO v_invoice
  FROM public.invoices i
  WHERE i.id = p_invoice_id
    AND i.is_deleted = false
    AND i.branch_id = ANY (public.jwt_branch_ids())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;

  PERFORM auth_internal.assert_invoice_in_draft(v_invoice);

  IF v_invoice.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'STALE_INVOICE';
  END IF;

  RETURN v_invoice;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.create_invoice_from_visit
-- -----------------------------------------------------------------------------

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

  INSERT INTO public.invoices (
    organization_id,
    branch_id,
    patient_id,
    visit_id,
    status,
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
      'status', 'draft'
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

-- -----------------------------------------------------------------------------
-- auth_internal.discard_draft_invoice
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.discard_draft_invoice(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_permission('invoices.create');
  v_org_id := public.jwt_organization_id();

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(p_invoice_id, p_expected_updated_at);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_not_in_draft' THEN
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Only draft invoices can be discarded.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  UPDATE public.invoice_items ii
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE ii.invoice_id = p_invoice_id
    AND ii.is_deleted = false;

  UPDATE public.invoices i
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE i.id = p_invoice_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.discard_draft',
    'invoices',
    p_invoice_id,
    jsonb_build_object('invoice_id', p_invoice_id, 'visit_id', v_invoice.visit_id)
  );

  RETURN public.rpc_success(jsonb_build_object('invoice_id', p_invoice_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to discard invoices.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.add_invoice_item
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

-- -----------------------------------------------------------------------------
-- auth_internal.update_invoice_item
-- -----------------------------------------------------------------------------

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
    line_total = v_line_subtotal - ii.line_discount_amount,
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
-- auth_internal.remove_invoice_item
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.remove_invoice_item(
  p_item_id uuid,
  p_expected_updated_at timestamptz
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
      ELSIF SQLERRM = 'invoice_not_in_draft' THEN
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Line items can only be changed on draft invoices.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  UPDATE public.invoice_items ii
  SET
    is_deleted = true,
    deleted_at = now(),
    deleted_by = auth.uid(),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE ii.id = p_item_id;

  PERFORM auth_internal.refresh_invoice_subtotal(v_item.invoice_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.item.remove',
    'invoice_items',
    p_item_id,
    jsonb_build_object('invoice_id', v_item.invoice_id, 'item_id', p_item_id)
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
-- auth_internal.issue_invoice
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.issue_invoice(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_invoice_number text;
  v_item_count int;
BEGIN
  PERFORM auth_internal.assert_permission('invoices.create');
  v_org_id := public.jwt_organization_id();

  BEGIN
    v_invoice := auth_internal.lock_draft_invoice(p_invoice_id, p_expected_updated_at);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Invoice was not found.');
      ELSIF SQLERRM = 'invoice_not_in_draft' THEN
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Only draft invoices can be issued.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  SELECT count(*)::int
  INTO v_item_count
  FROM public.invoice_items ii
  WHERE ii.invoice_id = p_invoice_id
    AND ii.is_deleted = false;

  IF v_item_count < 1 THEN
    RETURN public.rpc_error('NO_ITEMS', 'At least one line item is required before issuing.');
  END IF;

  BEGIN
    v_invoice_number := auth_internal.assign_invoice_number(v_invoice.branch_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'branch_code_missing' THEN
        RETURN public.rpc_error(
          'BRANCH_CODE_MISSING',
          'Assign a branch code in Settings before issuing invoices.'
        );
      END IF;
      RAISE;
  END;

  UPDATE public.invoices i
  SET
    status = 'issued',
    invoice_number = v_invoice_number,
    issued_at = now(),
    subtotal = auth_internal.compute_invoice_subtotal(p_invoice_id),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE i.id = p_invoice_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.issue',
    'invoices',
    p_invoice_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'prior_status', 'draft',
      'new_status', 'issued',
      'invoice_number', v_invoice_number
    )
  );

  RETURN public.rpc_success(jsonb_build_object('invoice_number', v_invoice_number));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to issue invoices.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.get_invoice_detail
-- -----------------------------------------------------------------------------

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

  v_balance := auth_internal.compute_invoice_balance(p_invoice_id);

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
        'reference', p.reference,
        'note', p.note,
        'recorded_by', p.recorded_by,
        'recorded_at', p.recorded_at
      )
      ORDER BY p.recorded_at
    ),
    '[]'::jsonb
  )
  INTO v_payments
  FROM public.payments p
  WHERE p.invoice_id = p_invoice_id;

  SELECT jsonb_build_object('id', pt.id, 'display_name', pt.full_name)
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
      'insurance_provider', v_provider
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

-- -----------------------------------------------------------------------------
-- auth_internal.list_invoices
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
        OR i.invoice_number ILIKE v_invoice_number || '%'
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

-- -----------------------------------------------------------------------------
-- public RPC wrappers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_invoice_from_visit(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.create_invoice_from_visit(p_visit_id);
$$;

CREATE OR REPLACE FUNCTION public.discard_draft_invoice(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.discard_draft_invoice(p_invoice_id, p_expected_updated_at);
$$;

CREATE OR REPLACE FUNCTION public.add_invoice_item(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz,
  p_description text,
  p_quantity numeric,
  p_unit_price numeric
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.add_invoice_item(
    p_invoice_id,
    p_expected_updated_at,
    p_description,
    p_quantity,
    p_unit_price
  );
$$;

CREATE OR REPLACE FUNCTION public.update_invoice_item(
  p_item_id uuid,
  p_expected_updated_at timestamptz,
  p_description text,
  p_quantity numeric,
  p_unit_price numeric
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_invoice_item(
    p_item_id,
    p_expected_updated_at,
    p_description,
    p_quantity,
    p_unit_price
  );
$$;

CREATE OR REPLACE FUNCTION public.remove_invoice_item(
  p_item_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.remove_invoice_item(p_item_id, p_expected_updated_at);
$$;

CREATE OR REPLACE FUNCTION public.issue_invoice(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.issue_invoice(p_invoice_id, p_expected_updated_at);
$$;

CREATE OR REPLACE FUNCTION public.get_invoice_detail(p_invoice_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_invoice_detail(p_invoice_id);
$$;

CREATE OR REPLACE FUNCTION public.list_invoices(
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_invoices(p_filters, p_limit, p_offset);
$$;

GRANT EXECUTE ON FUNCTION public.create_invoice_from_visit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.discard_draft_invoice(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_invoice_item(uuid, timestamptz, text, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_invoice_item(uuid, timestamptz, text, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_invoice_item(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_invoice(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_invoice_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_invoices(jsonb, int, int) TO authenticated;
