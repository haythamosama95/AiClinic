-- Seed patients.reassign_mrn permission (administrator only).

INSERT INTO public.roles_permissions (role, permission_key, is_granted)
VALUES
  ('administrator', 'patients.reassign_mrn', true),
  ('doctor', 'patients.reassign_mrn', false),
  ('receptionist', 'patients.reassign_mrn', false),
  ('lab_staff', 'patients.reassign_mrn', false)
ON CONFLICT (role, permission_key) DO UPDATE
SET is_granted = EXCLUDED.is_granted,
    is_deleted = false;
