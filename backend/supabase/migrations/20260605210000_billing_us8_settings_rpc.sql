-- =============================================================================
-- V1-6: Billing US8 — update_billing_settings RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_internal.update_billing_settings(p_allow_partial_payments boolean)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_prior boolean;
  v_settings_id uuid;
BEGIN
  v_staff := auth_internal.assert_permission('settings.billing.manage');
  v_org_id := public.jwt_organization_id();

  IF v_staff.role NOT IN ('owner', 'administrator') THEN
    RETURN public.rpc_error(
      'FORBIDDEN',
      'Only owners and administrators can update billing settings.'
    );
  END IF;

  IF p_allow_partial_payments IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'allow_partial_payments is required.');
  END IF;

  SELECT obs.allow_partial_payments, obs.organization_id
  INTO v_prior, v_settings_id
  FROM public.organization_billing_settings obs
  WHERE obs.organization_id = v_org_id;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'Billing settings were not found for this organization.');
  END IF;

  UPDATE public.organization_billing_settings
  SET allow_partial_payments = p_allow_partial_payments
  WHERE organization_id = v_org_id;

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'billing_settings.update',
    'organization_billing_settings',
    v_settings_id,
    jsonb_build_object('allow_partial_payments', coalesce(v_prior, false)),
    jsonb_build_object('allow_partial_payments', p_allow_partial_payments)
  );

  RETURN public.rpc_success(
    jsonb_build_object('allow_partial_payments', p_allow_partial_payments)
  );
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'FORBIDDEN' THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to update billing settings.');
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_billing_settings(p_allow_partial_payments boolean)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.update_billing_settings(p_allow_partial_payments);
$$;

GRANT EXECUTE ON FUNCTION public.update_billing_settings(boolean) TO authenticated;
