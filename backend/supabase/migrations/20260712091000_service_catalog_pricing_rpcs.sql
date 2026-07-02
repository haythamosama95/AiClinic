-- =============================================================================
-- Service Catalog (015): pricing, eligibility, and catalog read RPCs (US1+)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- auth_internal.get_service
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth_internal.get_service(p_service_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_branches jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT EXISTS (
    SELECT 1
    FROM public.roles_permissions rp
    JOIN public.staff_members sm ON sm.role = rp.role
    WHERE sm.auth_user_id = auth.uid()
      AND sm.is_deleted = false
      AND sm.is_active = true
      AND rp.permission_key IN ('services.view', 'services.manage')
      AND rp.is_granted = true
      AND rp.is_deleted = false
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view the service catalog.');
  END IF;

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  SELECT *
  INTO v_service
  FROM public.services s
  WHERE s.id = p_service_id
    AND s.organization_id = v_org_id
    AND s.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'service_branch_id', sb.id,
        'branch_id', sb.branch_id,
        'status', sb.status::text,
        'price_override', sb.price_override,
        'promotion_price', sb.promotion_price,
        'promotion_start_date', sb.promotion_start_date,
        'promotion_end_date', sb.promotion_end_date,
        'updated_at', sb.updated_at
      )
      ORDER BY sb.branch_id
    ),
    '[]'::jsonb
  )
  INTO v_branches
  FROM public.service_branches sb
  WHERE sb.service_id = p_service_id
    AND sb.is_deleted = false
    AND sb.branch_id = ANY (public.jwt_branch_ids());

  RETURN public.rpc_success(
    jsonb_build_object(
      'service', jsonb_build_object(
        'id', v_service.id,
        'name', v_service.name,
        'default_price', v_service.default_price,
        'global_status', v_service.global_status::text,
        'created_at', v_service.created_at,
        'updated_at', v_service.updated_at
      ),
      'branches', v_branches
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_service(p_service_id uuid)
RETURNS public.rpc_result
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, auth_internal
AS $$
  SELECT auth_internal.get_service(p_service_id);
$$;

GRANT EXECUTE ON FUNCTION public.get_service(uuid) TO authenticated;
