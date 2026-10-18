-- =============================================================================
-- R1-SQL-02 (P1) step 3: membership role repair (decision D-1, 01 §3.8).
--
-- Pre-existing membership/staff role mismatches are repaired under D-1:
--   * The read-only reconciliation lists (user_id, organization_id,
--     membership.role, staff.role) wherever the two roles differ. It runs in
--     CI through the R1-SQL-02 test suite (backend/tests/
--     r1_sql01_to_r1_sql06_staff_authority.sql) and against staging/
--     production by the operator before rollout (see "Operator checklist" in
--     docs/review/abo-remediation/RM01.md).
--   * A user with exactly one membership gets staff.role copied to it.
--   * For a user with several memberships, each org's row is decided alone:
--       - when exactly one of the two roles is 'administrator', the row gets
--         the other, non-administrator role;
--       - when both are non-administrator roles and they differ, the row is
--         held;
--       - when the result would leave that org with no active administrator
--         membership, the row is held.
--   * Held rows need an explicit per-org approved mapping from that clinic's
--     administrator and the maintainer. The repair aborts (nothing applied)
--     while any held row lacks an approved mapping. Approved mappings are
--     supplied as rows in ai_internal.membership_role_repair_mapping; once
--     present, re-running this migration applies them transactionally and
--     proceeds.
--
-- The global role is used only to remove administrator authority, never to
-- add it; roles are never flattened across orgs.
-- Forward-only migration; never edit an applied migration file.
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

CREATE POLICY membership_role_repair_mapping_deny_all ON ai_internal.membership_role_repair_mapping
  FOR ALL
  USING (false);

REVOKE ALL ON TABLE ai_internal.membership_role_repair_mapping
  FROM PUBLIC, anon, authenticated, service_role;

DO $$
DECLARE
  v_row record;
  v_approved public.staff_role;
  v_unresolved text[] := ARRAY[]::text[];
  v_entry text;
  v_auto_updated bigint;
  v_single_updated bigint;
BEGIN
  -- 1. Single-membership users: copy staff.role to the membership (D-1).
  UPDATE ai_internal.membership m
  SET role = sm.role
  FROM public.staff_members sm
  WHERE sm.auth_user_id = m.user_id
    AND NOT EXISTS (
      SELECT 1
      FROM ai_internal.membership m2
      WHERE m2.user_id = m.user_id
        AND m2.organization_id <> m.organization_id
    )
    AND m.role <> sm.role;
  GET DIAGNOSTICS v_single_updated = ROW_COUNT;

  -- 2. Multi-membership users: decide each org's row alone. Exactly one of
  --    the two roles is 'administrator' -> the row gets the non-administrator
  --    role, unless that write would leave the org with no active
  --    administrator membership (such rows are held for step 3).
  UPDATE ai_internal.membership m
  SET role = CASE
    WHEN m.role = 'administrator' THEN sm.role  -- the other role is non-admin here
    ELSE m.role                                 -- staff.role is the administrator; keep the non-admin membership role
  END
  FROM public.staff_members sm
  WHERE sm.auth_user_id = m.user_id
    AND EXISTS (
      SELECT 1
      FROM ai_internal.membership m2
      WHERE m2.user_id = m.user_id
        AND m2.organization_id <> m.organization_id
    )
    AND m.role <> sm.role
    AND (m.role = 'administrator') <> (sm.role = 'administrator')
    AND NOT (
      m.role = 'administrator'
      AND NOT EXISTS (
        SELECT 1
        FROM ai_internal.membership m3
        JOIN public.staff_members sm3 ON sm3.auth_user_id = m3.user_id
          AND sm3.is_deleted = false
          AND sm3.is_active = true
        WHERE m3.organization_id = m.organization_id
          AND m3.role = 'administrator'
          AND NOT (
            m3.user_id = m.user_id
            AND m3.organization_id = m.organization_id
          )
      )
    );
  GET DIAGNOSTICS v_auto_updated = ROW_COUNT;

  -- 3. Held rows: multi-membership mismatches that the auto rules did not
  --    settle (both roles non-administrator and different, or an
  --    administrator row whose demotion would orphan the org). Apply an
  --    approved mapping when present; otherwise collect the row for the
  --    abort listing.
  FOR v_row IN
    SELECT m.user_id, m.organization_id, m.role AS membership_role, sm.role AS staff_role
    FROM ai_internal.membership m
    JOIN public.staff_members sm ON sm.auth_user_id = m.user_id
    WHERE EXISTS (
      SELECT 1
      FROM ai_internal.membership m2
      WHERE m2.user_id = m.user_id
        AND m2.organization_id <> m.organization_id
    )
      AND m.role <> sm.role
      AND (
        (m.role <> 'administrator' AND sm.role <> 'administrator')
        OR (
          m.role = 'administrator'
          AND NOT EXISTS (
            SELECT 1
            FROM ai_internal.membership m3
            JOIN public.staff_members sm3 ON sm3.auth_user_id = m3.user_id
              AND sm3.is_deleted = false
              AND sm3.is_active = true
            WHERE m3.organization_id = m.organization_id
              AND m3.role = 'administrator'
              AND NOT (
                m3.user_id = m.user_id
                AND m3.organization_id = m.organization_id
              )
          )
        )
      )
  LOOP
    SELECT r.approved_role
    INTO v_approved
    FROM ai_internal.membership_role_repair_mapping r
    WHERE r.user_id = v_row.user_id
      AND r.organization_id = v_row.organization_id;

    IF FOUND THEN
      UPDATE ai_internal.membership m
      SET role = v_approved
      WHERE m.user_id = v_row.user_id
        AND m.organization_id = v_row.organization_id;
    ELSE
      v_entry := format(
        '(user_id=%s, organization_id=%s, membership.role=%s, staff.role=%s)',
        v_row.user_id, v_row.organization_id, v_row.membership_role, v_row.staff_role
      );
      v_unresolved := array_append(v_unresolved, v_entry);
    END IF;
  END LOOP;

  IF array_length(v_unresolved, 1) > 0 THEN
    RAISE EXCEPTION 'MEMBERSHIP_ROLE_REPAIR_HELD_ROWS: % unresolved held rows need an approved per-org mapping in ai_internal.membership_role_repair_mapping from that clinic''s administrator and the maintainer: %',
      array_length(v_unresolved, 1),
      array_to_string(v_unresolved, '; ');
  END IF;

  RAISE NOTICE 'R1-SQL-02 repair: single_membership_copies=%, multi_membership_decisions=%, unresolved_held_rows=%',
    v_single_updated, v_auto_updated, coalesce(array_length(v_unresolved, 1), 0);
END;
$$;