-- Require bootstrap administrator role for clinic setup RPCs (admin login only).

CREATE OR REPLACE FUNCTION auth_internal.assert_bootstrap_admin()
RETURNS public.staff_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = auth.uid()
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND
    OR NOT v_staff.is_bootstrap_admin
    OR v_staff.role <> 'administrator'::public.staff_role THEN
    RAISE EXCEPTION 'NOT_BOOTSTRAP_ADMIN';
  END IF;

  RETURN v_staff;
END;
$$;
