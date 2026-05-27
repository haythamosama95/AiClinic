-- Force-clear clinic installation data between boundary test campaigns.
-- Keeps bootstrap admin and global role permission seeds intact.
\set ON_ERROR_STOP on

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
DELETE FROM public.audit_log WHERE organization_id IS NOT NULL;
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
