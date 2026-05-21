-- PostgREST uses the JWT "role" claim as the PostgreSQL session role (must be "authenticated").
-- Staff job title was also emitted as "role", breaking REST queries with: role "administrator" does not exist.
-- Emit staff_role in custom claims instead; jwt_staff_role() reads staff_role (legacy "role" fallback).

CREATE OR REPLACE FUNCTION auth_internal.build_staff_claims(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
  v_org_id uuid;
  v_branch_ids text;
  v_setup_required boolean;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = p_user_id
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT o.id
  INTO v_org_id
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  JOIN public.organizations o ON o.id = b.organization_id
  WHERE sba.staff_member_id = v_staff.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.is_active = true
    AND o.is_deleted = false
  ORDER BY sba.is_primary DESC, b.created_at
  LIMIT 1;

  SELECT string_agg(b.id::text, ',' ORDER BY sba.is_primary DESC, b.name)
  INTO v_branch_ids
  FROM public.staff_branch_assignments sba
  JOIN public.branches b ON b.id = sba.branch_id
  WHERE sba.staff_member_id = v_staff.id
    AND sba.is_deleted = false
    AND b.is_deleted = false
    AND b.is_active = true;

  v_setup_required := v_staff.is_bootstrap_admin AND v_org_id IS NULL;

  RETURN jsonb_strip_nulls(
    jsonb_build_object(
      'staff_member_id', v_staff.id::text,
      'staff_role', v_staff.role::text,
      'organization_id', CASE WHEN v_setup_required THEN NULL ELSE v_org_id::text END,
      'branch_ids', COALESCE(v_branch_ids, ''),
      'setup_required', v_setup_required
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.jwt_staff_role()
RETURNS public.staff_role
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    NULLIF(public.request_jwt_claims() ->> 'staff_role', ''),
    NULLIF(public.request_jwt_claims() ->> 'role', '')
  )::public.staff_role;
$$;
