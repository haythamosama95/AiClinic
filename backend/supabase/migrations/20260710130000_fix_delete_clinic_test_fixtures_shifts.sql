-- Restore shift teardown in test fixture helper (regressed when visit/014 migrations
-- replaced delete_clinic_operational_dependents without shift rows).

CREATE OR REPLACE FUNCTION auth_internal.delete_clinic_operational_dependents()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM auth_internal.delete_billing_dependents();

  IF to_regclass('public.visit_attachments') IS NOT NULL THEN
    DELETE FROM public.visit_attachments;
  END IF;
  IF to_regclass('public.visit_vital_signs') IS NOT NULL THEN
    DELETE FROM public.visit_vital_signs;
  END IF;
  IF to_regclass('public.visit_investigations') IS NOT NULL THEN
    DELETE FROM public.visit_investigations;
  END IF;
  IF to_regclass('public.visit_clinical_notes') IS NOT NULL THEN
    DELETE FROM public.visit_clinical_notes;
  END IF;
  IF to_regclass('public.treatment_plans') IS NOT NULL THEN
    DELETE FROM public.treatment_plans;
  END IF;
  IF to_regclass('public.visits') IS NOT NULL THEN
    DELETE FROM public.visits;
  END IF;

  -- Shifts (V1-7): assignments reference staff_members; delete before staff teardown.
  IF to_regclass('public.shift_assignments') IS NOT NULL THEN
    DELETE FROM public.shift_assignments;
  END IF;
  IF to_regclass('public.shifts') IS NOT NULL THEN
    DELETE FROM public.shifts;
  END IF;

  IF to_regclass('public.appointments') IS NOT NULL THEN
    DELETE FROM public.appointments;
  END IF;

  IF to_regclass('public.patient_allergies') IS NOT NULL THEN
    DELETE FROM public.patient_allergies;
  END IF;
  IF to_regclass('public.patient_medications') IS NOT NULL THEN
    DELETE FROM public.patient_medications;
  END IF;
  IF to_regclass('public.patient_chronic_conditions') IS NOT NULL THEN
    DELETE FROM public.patient_chronic_conditions;
  END IF;

  DELETE FROM public.patients;
END;
$$;

COMMENT ON FUNCTION auth_internal.delete_clinic_operational_dependents() IS
  'Delete billing, visit, shift, appointment, patient-health, and patient rows in FK-safe order. Used by backend SQL tests.';
