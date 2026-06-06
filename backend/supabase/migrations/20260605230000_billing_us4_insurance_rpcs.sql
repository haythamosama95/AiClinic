-- =============================================================================
-- V1-6: Billing US4 — insurance coverage and provider catalog RPCs
-- =============================================================================

-- -----------------------------------------------------------------------------
-- auth_internal.set_insurance_coverage
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.set_insurance_coverage(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz,
  p_provider_id uuid,
  p_covered_amount numeric
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
  v_org_id uuid;
  v_provider public.insurance_providers%ROWTYPE;
  v_max_amount numeric(14, 2);
  v_prior_provider_id uuid;
  v_prior_amount numeric(14, 2);
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
        RETURN public.rpc_error('INVOICE_NOT_IN_DRAFT', 'Insurance coverage can only be changed on draft invoices.');
      ELSIF SQLERRM = 'STALE_INVOICE' THEN
        RETURN public.rpc_error('STALE_INVOICE', 'This invoice was updated elsewhere. Reload and try again.');
      ELSIF SQLERRM = 'INVALID_INPUT' THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Expected updated timestamp is required.');
      END IF;
      RAISE;
  END;

  v_prior_provider_id := v_invoice.insurance_provider_id;
  v_prior_amount := v_invoice.insurance_covered_amount;
  v_max_amount := v_invoice.subtotal - COALESCE(v_invoice.discount_amount, 0);

  IF p_provider_id IS NULL AND COALESCE(p_covered_amount, 0) = 0 THEN
    UPDATE public.invoices i
    SET
      insurance_provider_id = NULL,
      insurance_covered_amount = 0.00,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE i.id = p_invoice_id;
  ELSE
    IF p_provider_id IS NULL THEN
      RETURN public.rpc_error('INVALID_INPUT', 'An insurance provider is required when covered amount is greater than zero.');
    END IF;

    IF p_covered_amount IS NULL OR p_covered_amount < 0 THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Insurance covered amount cannot be negative.');
    END IF;

    IF p_covered_amount > v_max_amount THEN
      RETURN public.rpc_error(
        'INVALID_INPUT',
        'Insurance covered amount cannot exceed the invoice total after discounts.'
      );
    END IF;

    SELECT *
    INTO v_provider
    FROM public.insurance_providers ip
    WHERE ip.id = p_provider_id
      AND ip.is_deleted = false
      AND ip.organization_id = v_org_id;

    IF NOT FOUND THEN
      RETURN public.rpc_error('NOT_FOUND', 'Insurance provider was not found.');
    END IF;

    IF NOT v_provider.is_active THEN
      RETURN public.rpc_error('INVALID_INPUT', 'Only active insurance providers can be selected.');
    END IF;

    UPDATE public.invoices i
    SET
      insurance_provider_id = p_provider_id,
      insurance_covered_amount = p_covered_amount,
      updated_at = now(),
      updated_by = auth.uid()
    WHERE i.id = p_invoice_id;
  END IF;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'invoice.insurance.set',
    'invoices',
    p_invoice_id,
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'insurance_provider_id', v_prior_provider_id,
      'insurance_covered_amount', v_prior_amount
    ),
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'insurance_provider_id', p_provider_id,
      'insurance_covered_amount', COALESCE(p_covered_amount, 0)
    )
  );

  RETURN public.rpc_success(
    jsonb_build_object(
      'invoice_id', p_invoice_id,
      'insurance_provider_id', p_provider_id,
      'insurance_covered_amount', COALESCE(p_covered_amount, 0),
      'balance', auth_internal.compute_invoice_balance(p_invoice_id)
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to set insurance coverage.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.insurance_provider_upsert
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.insurance_provider_upsert(
  p_id uuid,
  p_name text,
  p_contact_info text,
  p_is_active boolean
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_name text;
  v_provider_id uuid;
  v_prior_name text;
  v_prior_contact text;
  v_prior_active boolean;
BEGIN
  PERFORM auth_internal.assert_permission('insurance.manage');
  v_org_id := public.jwt_organization_id();
  v_name := NULLIF(btrim(p_name), '');

  IF v_name IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Provider name is required.');
  END IF;

  IF char_length(v_name) > 200 THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Provider name cannot exceed 200 characters.');
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.insurance_providers (
      organization_id,
      name,
      contact_info,
      is_active,
      created_by,
      updated_by
    )
    VALUES (
      v_org_id,
      v_name,
      NULLIF(btrim(p_contact_info), ''),
      COALESCE(p_is_active, true),
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_provider_id;

    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
    VALUES (
      auth.uid(),
      v_org_id,
      'insurance_provider.create',
      'insurance_providers',
      v_provider_id,
      jsonb_build_object('name', v_name, 'contact_info', NULLIF(btrim(p_contact_info), ''), 'is_active', COALESCE(p_is_active, true))
    );
  ELSE
    SELECT ip.name, ip.contact_info, ip.is_active
    INTO v_prior_name, v_prior_contact, v_prior_active
    FROM public.insurance_providers ip
    WHERE ip.id = p_id
      AND ip.organization_id = v_org_id
      AND ip.is_deleted = false;

    IF NOT FOUND THEN
      RETURN public.rpc_error('NOT_FOUND', 'Insurance provider was not found.');
    END IF;

    UPDATE public.insurance_providers ip
    SET
      name = v_name,
      contact_info = NULLIF(btrim(p_contact_info), ''),
      is_active = COALESCE(p_is_active, ip.is_active),
      updated_at = now(),
      updated_by = auth.uid()
    WHERE ip.id = p_id;

    v_provider_id := p_id;

    INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
    VALUES (
      auth.uid(),
      v_org_id,
      'insurance_provider.update',
      'insurance_providers',
      v_provider_id,
      jsonb_build_object('name', v_prior_name, 'contact_info', v_prior_contact, 'is_active', v_prior_active),
      jsonb_build_object('name', v_name, 'contact_info', NULLIF(btrim(p_contact_info), ''), 'is_active', COALESCE(p_is_active, v_prior_active))
    );
  END IF;

  RETURN public.rpc_success(jsonb_build_object('provider_id', v_provider_id));
EXCEPTION
  WHEN unique_violation THEN
    RETURN public.rpc_error('INVALID_INPUT', 'An insurance provider with this name already exists.');
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage insurance providers.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.insurance_provider_deactivate
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.insurance_provider_deactivate(p_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_prior_active boolean;
BEGIN
  PERFORM auth_internal.assert_permission('insurance.manage');
  v_org_id := public.jwt_organization_id();

  IF p_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Provider id is required.');
  END IF;

  SELECT ip.is_active
  INTO v_prior_active
  FROM public.insurance_providers ip
  WHERE ip.id = p_id
    AND ip.organization_id = v_org_id
    AND ip.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Insurance provider was not found.');
  END IF;

  UPDATE public.insurance_providers ip
  SET
    is_active = false,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE ip.id = p_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'insurance_provider.deactivate',
    'insurance_providers',
    p_id,
    jsonb_build_object('is_active', v_prior_active),
    jsonb_build_object('is_active', false)
  );

  RETURN public.rpc_success(jsonb_build_object('provider_id', p_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to manage insurance providers.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- auth_internal.list_insurance_providers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.list_insurance_providers(p_only_active boolean DEFAULT true)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_providers jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT (
    auth_internal.staff_has_invoices_view_access()
    OR EXISTS (
      SELECT 1
      FROM public.roles_permissions rp
      JOIN public.staff_members sm ON sm.role = rp.role
      WHERE sm.auth_user_id = auth.uid()
        AND sm.is_deleted = false
        AND sm.is_active = true
        AND rp.permission_key IN ('invoices.create', 'insurance.manage')
        AND rp.is_granted = true
        AND rp.is_deleted = false
    )
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list insurance providers.');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ip.id,
        'name', ip.name,
        'contact_info', ip.contact_info,
        'is_active', ip.is_active
      )
      ORDER BY ip.name
    ),
    '[]'::jsonb
  )
  INTO v_providers
  FROM public.insurance_providers ip
  WHERE ip.organization_id = v_org_id
    AND ip.is_deleted = false
    AND (NOT COALESCE(p_only_active, true) OR ip.is_active = true);

  RETURN public.rpc_success(jsonb_build_object('providers', v_providers));
END;
$$;

-- -----------------------------------------------------------------------------
-- public RPC wrappers
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_insurance_coverage(
  p_invoice_id uuid,
  p_expected_updated_at timestamptz,
  p_provider_id uuid,
  p_covered_amount numeric
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.set_insurance_coverage(p_invoice_id, p_expected_updated_at, p_provider_id, p_covered_amount);
$$;

CREATE OR REPLACE FUNCTION public.insurance_provider_upsert(
  p_id uuid,
  p_name text,
  p_contact_info text DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.insurance_provider_upsert(p_id, p_name, p_contact_info, p_is_active);
$$;

CREATE OR REPLACE FUNCTION public.insurance_provider_deactivate(p_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.insurance_provider_deactivate(p_id);
$$;

CREATE OR REPLACE FUNCTION public.list_insurance_providers(p_only_active boolean DEFAULT true)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.list_insurance_providers(p_only_active);
$$;

GRANT EXECUTE ON FUNCTION public.set_insurance_coverage(uuid, timestamptz, uuid, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insurance_provider_upsert(uuid, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insurance_provider_deactivate(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_insurance_providers(boolean) TO authenticated;
