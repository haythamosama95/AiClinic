-- Grant visit-summary scope to clinic administrators.
INSERT INTO public.roles_permissions (role, permission_key, is_granted)
VALUES
  ('administrator', 'ai.visit_summary', true)
ON CONFLICT (role, permission_key) DO UPDATE
SET is_granted = EXCLUDED.is_granted,
    is_deleted = false;
