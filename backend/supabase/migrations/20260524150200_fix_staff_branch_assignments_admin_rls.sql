-- Fix 39: Expand staff_branch_assignments RLS so owners/admins can see
-- all branch assignments within their organization (needed for staff management UI).

DROP POLICY IF EXISTS staff_branch_assignments_select ON public.staff_branch_assignments;

CREATE POLICY staff_branch_assignments_select ON public.staff_branch_assignments
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      -- Normal staff: see assignments for branches they belong to
      branch_id = ANY (public.jwt_branch_ids())
      -- Setup phase: bootstrap admin can see own assignments
      OR (
        public.jwt_setup_required()
        AND staff_member_id = public.jwt_staff_member_id()
      )
      -- Owner/Administrator: see all assignments within their organization
      OR (
        EXISTS (
          SELECT 1 FROM public.current_staff_member_row() sm
          WHERE sm.role IN ('owner', 'administrator')
        )
        AND EXISTS (
          SELECT 1 FROM public.branches b
          WHERE b.id = staff_branch_assignments.branch_id
            AND b.organization_id = public.jwt_organization_id()
            AND b.is_deleted = false
        )
      )
    )
  );
