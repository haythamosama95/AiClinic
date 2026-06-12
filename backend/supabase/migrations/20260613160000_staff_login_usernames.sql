-- Expose staff login usernames (stored in auth.users.email) for administration list search.

CREATE OR REPLACE FUNCTION public.staff_login_usernames(p_staff_ids uuid[])
RETURNS TABLE (staff_member_id uuid, username text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT sm.id, lower(trim(u.email::text))
  FROM public.staff_members sm
  JOIN auth.users u ON u.id = sm.auth_user_id
  WHERE sm.is_deleted = false
    AND sm.id = ANY (p_staff_ids)
    AND (
      sm.auth_user_id = (SELECT auth.uid())
      OR EXISTS (
        SELECT 1
        FROM public.staff_branch_assignments sba
        JOIN public.branches b ON b.id = sba.branch_id
        WHERE sba.staff_member_id = sm.id
          AND sba.is_deleted = false
          AND b.is_deleted = false
          AND b.organization_id = public.jwt_organization_id()
      )
    );
$$;

REVOKE ALL ON FUNCTION public.staff_login_usernames(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.staff_login_usernames(uuid[]) TO authenticated;
