-- Fix 11: Harden bootstrap credentials.
-- Adds must_change_password flag to force bootstrap admin to change default password.

-- 1. Add the column
ALTER TABLE public.staff_members
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

-- 2. Mark the bootstrap admin as requiring a password change
UPDATE public.staff_members
SET must_change_password = true
WHERE is_bootstrap_admin = true
  AND is_deleted = false;

-- 3. Redefine build_staff_claims to include must_change_password in JWT
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
  FROM public.organizations o
  WHERE o.is_deleted = false
  ORDER BY o.created_at
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
      'setup_required', v_setup_required,
      'must_change_password', CASE WHEN v_staff.must_change_password THEN true ELSE NULL END
    )
  );
END;
$$;

-- Note: admin_reset_staff_password is redefined in 20260524130100 (Fix 29).
-- The must_change_password clearing is added there to avoid ordering conflicts.
