-- Restore branch-wide slot conflict detection for appointments.
-- 20260528150500 intended branch-wide overlap, but the live function still
-- matches the doctor-only variant from 20260527170000 (optional doctor_id).

CREATE OR REPLACE FUNCTION auth_internal.appointment_has_overlap(
  p_branch_id uuid,
  p_doctor_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_exclude_appointment_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.appointments a
    WHERE a.branch_id = p_branch_id
      AND a.is_deleted = false
      AND a.status NOT IN ('cancelled', 'no_show')
      AND (p_exclude_appointment_id IS NULL OR a.id <> p_exclude_appointment_id)
      AND a.start_time < p_end_time
      AND a.end_time > p_start_time
  );
$$;
