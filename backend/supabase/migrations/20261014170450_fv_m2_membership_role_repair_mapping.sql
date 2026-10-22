-- =============================================================================
-- FV-M2 (Major): membership role repair mapping table, ordered before the
-- repair migration.
--
-- 20261014170500 used to create this table in the same migration that aborts
-- with MEMBERSHIP_ROLE_REPAIR_HELD_ROWS. The abort rolled the table back, so
-- the documented recovery (insert approved mappings, then re-apply) could not
-- work, and a non-transactional re-apply failed on CREATE POLICY. The DDL now
-- lives here and is idempotent; 170500 keeps only the repair DO block.
-- =============================================================================

-- Approved per-org mapping for held rows. approved_role is the final
-- membership role; it can preserve a valid difference (equal to the current
-- membership role) but can never add administrator authority.
CREATE TABLE IF NOT EXISTS ai_internal.membership_role_repair_mapping (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  approved_role public.staff_role NOT NULL,
  approved_by text NOT NULL,
  approved_note text,
  approved_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, organization_id),
  CONSTRAINT membership_role_repair_mapping_no_admin_add
    CHECK (approved_role <> 'administrator')
);

ALTER TABLE ai_internal.membership_role_repair_mapping ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS membership_role_repair_mapping_deny_all ON ai_internal.membership_role_repair_mapping;
CREATE POLICY membership_role_repair_mapping_deny_all ON ai_internal.membership_role_repair_mapping
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.membership_role_repair_mapping
  FROM PUBLIC, anon, authenticated, service_role;
