-- Membership (user, organisation, role) and the staff backfill (FR-001, FR-002).

CREATE TABLE ai_internal.membership (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  role public.staff_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, organization_id)
);

ALTER TABLE ai_internal.membership ENABLE ROW LEVEL SECURITY;

CREATE POLICY membership_deny_all ON ai_internal.membership
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.membership FROM PUBLIC, anon, authenticated, service_role;

-- One row per non-deleted staff member, for the earliest non-deleted
-- organisation (the organisation auth_internal.build_staff_claims takes).
-- is_active does not exclude a row. No non-deleted organisation yields no rows,
-- so the bootstrap administrator on a fresh database gets no membership.
INSERT INTO ai_internal.membership (user_id, organization_id, role, created_at)
SELECT
  sm.auth_user_id,
  earliest.id,
  sm.role,
  sm.created_at
FROM public.staff_members sm
CROSS JOIN (
  SELECT o.id
  FROM public.organizations o
  WHERE o.is_deleted = false
  ORDER BY o.created_at
  LIMIT 1
) earliest
WHERE sm.is_deleted = false;
