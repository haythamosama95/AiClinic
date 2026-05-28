-- Fix RLS recursion between staff_members and staff_branch_assignments policies.
-- Using current_staff_member_row() here can recurse because staff_members policy
-- itself checks staff_branch_assignments visibility.
DROP POLICY IF EXISTS staff_branch_assignments_select ON public.staff_branch_assignments;

CREATE POLICY staff_branch_assignments_select ON public.staff_branch_assignments FOR
SELECT
  TO authenticated USING (
    is_deleted = false
    AND (
      -- Normal staff: see assignments for branches they belong to
      branch_id = ANY (public.jwt_branch_ids ())
      -- Setup phase: bootstrap admin can see own assignments
      OR (
        public.jwt_setup_required ()
        AND staff_member_id = public.jwt_staff_member_id ()
      )
      -- Owner/Administrator: see all assignments within their organization.
      -- Use JWT role claim directly to avoid recursive policy evaluation.
      OR (
        public.jwt_staff_role () IN ('owner', 'administrator')
        AND EXISTS (
          SELECT
            1
          FROM
            public.branches b
          WHERE
            b.id = staff_branch_assignments.branch_id
            AND b.organization_id = public.jwt_organization_id ()
            AND b.is_deleted = false
        )
      )
    )
  );