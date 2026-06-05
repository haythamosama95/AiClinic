-- Force-clear clinic installation data between boundary test campaigns.
-- Keeps bootstrap admin and global role permission seeds intact.
\set ON_ERROR_STOP on

-- Billing (V1-6): clear before visits/branches/organizations.
DO $$
BEGIN
  IF to_regclass('public.payments') IS NOT NULL THEN
    DELETE FROM public.payments WHERE true;
  END IF;
  IF to_regclass('public.invoice_items') IS NOT NULL THEN
    DELETE FROM public.invoice_items WHERE true;
  END IF;
  IF to_regclass('public.invoices') IS NOT NULL THEN
    DELETE FROM public.invoices WHERE true;
  END IF;
  IF to_regclass('public.invoice_number_sequences') IS NOT NULL THEN
    DELETE FROM public.invoice_number_sequences WHERE true;
  END IF;
  IF to_regclass('public.insurance_providers') IS NOT NULL THEN
    DELETE FROM public.insurance_providers WHERE true;
  END IF;
  IF to_regclass('public.organization_billing_settings') IS NOT NULL THEN
    DELETE FROM public.organization_billing_settings WHERE true;
  END IF;
END $$;

-- Visit module (when migrated): clear dependents before appointments.
DO $$
BEGIN
  IF to_regclass('public.visit_attachments') IS NOT NULL THEN
    DELETE FROM public.visit_attachments WHERE true;
  END IF;
  IF to_regclass('public.soap_notes') IS NOT NULL THEN
    DELETE FROM public.soap_notes WHERE true;
  END IF;
  IF to_regclass('public.treatment_plans') IS NOT NULL THEN
    DELETE FROM public.treatment_plans WHERE true;
  END IF;
  IF to_regclass('public.visits') IS NOT NULL THEN
    DELETE FROM public.visits WHERE true;
  END IF;
END $$;

DELETE FROM public.appointments WHERE true;
DELETE FROM public.audit_log WHERE true;

DELETE FROM public.staff_branch_assignments sba
WHERE sba.staff_member_id IN (
  SELECT id FROM public.staff_members WHERE NOT is_bootstrap_admin
);

DELETE FROM public.staff_members WHERE NOT is_bootstrap_admin;

DELETE FROM auth.users au
WHERE NOT EXISTS (
  SELECT 1 FROM public.staff_members sm WHERE sm.auth_user_id = au.id
);

DELETE FROM public.staff_branch_assignments WHERE true;
DELETE FROM public.patients WHERE true;
DELETE FROM public.app_settings WHERE true;
DELETE FROM public.subscription_cache WHERE true;
DELETE FROM public.branches WHERE true;
DELETE FROM public.organizations WHERE true;

UPDATE public.roles_permissions SET is_granted = true, updated_at = now()
WHERE role IN ('owner', 'administrator', 'doctor', 'receptionist')
  AND permission_key IN ('patients.view', 'patients.create', 'patients.edit', 'patients.delete')
  AND is_deleted = false;

UPDATE public.roles_permissions SET is_granted = true, updated_at = now()
WHERE role = 'lab_staff' AND permission_key = 'patients.view' AND is_deleted = false;

UPDATE public.roles_permissions SET is_granted = false, updated_at = now()
WHERE role = 'lab_staff'
  AND permission_key IN ('patients.create', 'patients.edit', 'patients.delete')
  AND is_deleted = false;
