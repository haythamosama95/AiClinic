# Final Review — Backend Cross-Phase Integrity (RM00–RM38)

Reviewer scope: `backend/` only, branch `ai/abo-remediation` vs `master`, cross-phase interactions only.
Changed migrations (all appended after master's last migration `20261014170100`):
`20261014170200`–`20261014170900` (R1-SQL-01..06, R2-C2; RM01/RM02), `20261022120000_rm35_launch_state_reader.sql`,
`20261022130000_rm36_status_refresh_claim.sql`. No edge functions or other backend source changed.

## 1. Summary

- Critical: 0
- Major: 2
- Verdict: **FAIL** (two Major defects; both have workarounds and limited blast radius, but both should be fixed before launch)

## 2. What was checked

1. Migration ordering / silent undo — every function redefined on the branch was diffed against its latest prior definition
   (master or branch). No function is redefined twice on the branch. All bodies carry forward earlier fixes; the only deltas are
   the intended authority/locking changes (`issue_ai_token`, `issue_billing_token`, `update_staff_member`, `assert_permission`,
   `assert_owner_or_administrator`, `staff_can_access_branch`, `current_org_id`, `sync_active_organization`,
   `set_active_organization`, all R1-SQL-05 readers incl. `get_visit`/service-catalog RPCs, `request_ai_status_refresh`).
   CREATE OR REPLACE preserves existing ACLs. **No defect.** However, the existing last-administrator guard was *not* updated to
   the new membership-role authority model — see M-2.
2. New tables / RLS — only one new table (`ai_internal.membership_role_repair_mapping`): RLS enabled, deny-all policy, all
   client grants revoked. **No defect.**
3. SECURITY DEFINER / search_path / grants — every new or replaced DEFINER function sets a fixed `search_path`. The new shared
   helper `staff_has_membership_permissions` is revoked from all client roles and is only called from other DEFINER functions
   (no direct use in RLS policies). `ai_internal.launch_state()` (RM35) is executable only by the NOLOGIN `launch_check_reader`
   role. RM36 keeps the original role/session/org checks. No new grants to `anon`/`authenticated`. **No defect.**
4. Existing-data / dependency safety — no NOT NULL additions; every referenced helper (`organization_exists`, `jwt_branch_ids`,
   `ai_app_setting_numeric`, `current_membership_role`, `assert_visit_branch_scope`) exists earlier in order. The D-1 role repair
   migration has a documented abort path whose recovery procedure cannot work — see M-1.

## 3. Critical findings

None.

## 4. Major findings

### 4.1 M-1 — Role-repair abort path cannot be recovered as documented; blocks the whole remaining migration chain

- Files: `backend/supabase/migrations/20261014170500_r1_sql02_membership_role_repair.sql:34-53,171-175`;
  `docs/review/abo-remediation/RM01.md:127-131`
- RMs: RM01 (R1-SQL-02 step 3); blocks every later migration including RM02 (R1-SQL-05), R2-C2, RM35, RM36.
- Failure scenario: a production/staging database has at least one "held" row (a multi-membership user whose membership and
  staff roles are both non-administrator but differ, or whose admin demotion would leave an org with no administrator). The
  `DO` block raises `MEMBERSHIP_ROLE_REPAIR_HELD_ROWS`. The mapping table is created **in the same migration**:
  - If the migration runs in a transaction (Supabase CLI default), the `CREATE TABLE` is rolled back. The operator step "insert
    approved rows into `ai_internal.membership_role_repair_mapping`, then re-apply" fails because the table does not exist.
  - If it runs without a transaction, the table survives, but re-applying fails at line 48: `CREATE POLICY
    membership_role_repair_mapping_deny_all` has no `IF NOT EXISTS` / preceding `DROP POLICY IF EXISTS` (error 42710).
  In both cases the migration cannot complete via the documented procedure, and every later migration (`170600`…`RM36`) stays
  unapplied. That leaves the AI-token rate limit, org-scoped permission readers, and the RM36 throttle off on that environment.
- Confidence: High for the mechanics (read the code). Medium on whether production actually contains held rows.
- Proposed fix: move the table DDL (create table, enable RLS, policy, revoke) into its own migration ordered before the repair
  (e.g. `20261014170450_r1_sql02_membership_role_repair_mapping.sql`). Make it idempotent with `CREATE TABLE IF NOT EXISTS` +
  `DROP POLICY IF EXISTS … ; CREATE POLICY …`, and keep `170500` data-only. If an environment has already recorded `170500`,
  use `--include-all` or a re-timestamped equivalent. Update the RM01 operator checklist so mappings are inserted after the
  table migration and before the repair migration.

### 4.2 M-2 — Last-administrator guard still keys on global `staff_members.role`, while authority is now the per-org membership role

- Files: `backend/supabase/migrations/20260613210000_delete_staff_member.sql:54-87` (`assert_not_last_administrator`, unchanged);
  `backend/supabase/migrations/20261014170400_r1_sql02_update_staff_member_membership_sync.sql:116-128,161-164`;
  `backend/supabase/migrations/20261014170700_r1_sql04_membership_role_authority.sql:107-140,174-208`
- RMs: RM01 (R1-SQL-02 membership sync + R1-SQL-04 membership-role authority) interacting with the pre-existing guard.
- Failure scenario: after R1-SQL-04, administrator authority in an org comes only from `ai_internal.membership.role` for that
  org. `update_staff_member` writes the per-org membership role but still decides whether to run the guard from the **global**
  `v_target.role`. The guard counts "other administrators" by **global** `sm.role` (and picks the org via `LIMIT 1` on branch
  assignments). For multi-membership users these diverge by design (R1-SQL-02 never overwrites other orgs). Two concrete cases:
  1. User X is the only membership administrator of org A. An administrator of org B demotes X in B, which sets the global
     `staff_members.role` to `doctor`. X then edits themself in A with `p_role = 'doctor'`. `v_old_role` is `doctor`, so the
     guard is skipped, membership A becomes `doctor`, and org A has zero administrators.
  2. X is the only membership administrator of A. Y is assigned to an A branch with global role `administrator` but membership
     role `doctor` in A. X demotes themself. The guard counts Y as an administrator and passes, leaving A with zero
     administrators.
  Result: `assert_owner_or_administrator` and administrator-only provisioning are permanently unavailable for org A. The
  bootstrap exception does not apply because an organization exists, so there is no in-app recovery and an operator SQL fix is
  required. The same guard backs the deactivate/delete paths. Single-org tenants are unaffected because the roles stay synced.
  No test in `backend/tests/r1_rm01_staff_authority.sql` covers `LAST_ADMINISTRATOR`.
- Confidence: Medium-High (code paths read end-to-end; the scenario needs multi-membership users, which the repair migration
  explicitly supports).
- Proposed fix: add a forward migration that redefines `auth_internal.assert_not_last_administrator(uuid)` to take the org
  (`public.current_org_id()`). It should count other active, non-deleted staff whose `ai_internal.membership.role =
  'administrator'` for that org, and decide whether the target is an administrator from the target's membership row in that
  org. Then redefine `update_staff_member` (and the deactivate/delete callers) to gate the guard on the target's current-org
  membership role instead of `v_target.role`. Add multi-org tests for both scenarios above.

## 5. Could not verify

- Whether the target production/staging databases contain held rows for the D-1 repair (decides whether M-1 fires). The
  reconciliation query in the RM01 operator checklist must be run first.
- Whether the deployment pipeline applies each migration in a transaction. M-1 fails in either mode, but the error differs.
- I did not check every legacy SQL path that writes `public.staff_members` against the R1-SQL-01 `UPDATE` revoke. A spot check
  showed only reads from the Flutter client and DEFINER RPC writers, but I did not review each writer's security mode.
- RM35: `set_ai_availability_present` matches `pg_proc.proname` in any schema. That is informational only, not a
  security issue, and is not rated.
