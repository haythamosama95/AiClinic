# Senior Code Review — `ui/006-settings`

**Base branch:** `ui/005-first-setup` (merge-base `c756400`)
**Head:** `ui/006-settings` (`24c4307`)
**Scope:** 167 files, +16,995 / −736. Settings hub (general/clinic-setup/staff/staff-roles), staff administration (create/edit/deactivate/delete/username change), role-permission matrix, branch delete + working-hours, idle-timeout settings, and 8 new SQL migrations.

This review inspects the actual diff. Findings are ordered by severity. The `.cursor/skills/ui-ux-pro-max/**` files are tooling/data and were not security-reviewed.

---

## Findings

### 1. Settings hub "Clinic Setup" tab is not permission-gated
- **Severity:** High
- **Files:** `frontend/lib/features/settings/presentation/pages/settings_page.dart`, `.../widgets/clinic_setup_settings_tab.dart`, `.../widgets/branch_settings_section.dart`, `.../widgets/organization_settings_section.dart`, `frontend/lib/app/router.dart`
- **Explanation:** The router deliberately redirects non-admins away from the deep-link admin routes (`/settings/branches`, `/settings/organization`, `/settings/permissions`) via `AuthRouteGuard.adminSettingsRedirect`, and the integration tests assert a doctor is bounced back to the hub. However, the hub itself (`SettingsPage`) renders the **static** `SettingsTabs.all` list (`general`, `clinic-setup`, `staff`, `staff-roles`) to every authenticated user, with no filtering by role/permission. The `Staff Management` tab is correctly gated (`StaffListPage` checks `AuthRouteGuard.canAccessStaffManagement`) and `Staff Roles` shows a permission-denied state, but **`ClinicSetupSettingsTab` has no permission check at all** — it directly renders organization details and `BranchSettingsSection`, which exposes edit / deactivate / delete branch controls. A grep across `settings/presentation/widgets` finds zero permission checks. So a doctor/receptionist can open the Clinic Setup tab and see the same org/branch admin surface the redirect was designed to block. Mutations are still rejected server-side (RPCs call `assert_permission`), so this is not privilege escalation, but it is an authorization/UX inconsistency and potential data exposure (org/branch config) that contradicts an explicit security control for the same feature.
- **Suggested fix:** Filter the tab list by permission (mirror `canAccessStaffManagement` / `canAccessPermissionMatrix` with a `canManageBranches`/`canManageOrganization` guard), and add a permission-denied state to `ClinicSetupSettingsTab` exactly like `StaffListPage`. Hide write controls in `BranchSettingsSection`/`OrganizationSettingsSection` for users without `settings.manage_branches`.

### 2. `staff_login_usernames` exposes login usernames to any org member
- **Severity:** Medium
- **Files:** `backend/supabase/migrations/20260613160000_staff_login_usernames.sql`, `frontend/lib/features/settings/data/staff_admin_repository.dart`
- **Explanation:** This `SECURITY DEFINER` function returns login usernames (the value stored in `auth.users.email`) for every staff member in the caller's organization. The only gate is org membership via a branch assignment — there is **no `settings.manage_staff` permission check**. `GRANT EXECUTE ... TO authenticated` means any logged-in user (e.g. a receptionist) can pass a set of staff ids and enumerate login identifiers, half of every staff member's credentials. Usernames are sensitive in a username/password login model.
- **Suggested fix:** Add `PERFORM auth_internal.assert_permission('settings.manage_staff');` at the top (convert to plpgsql), or restrict the returned set to the caller's own id plus, for managers only, the full org. Keep the org-scope subquery as defense-in-depth.

### 3. Role-permission save is non-transactional and issues N sequential RPCs
- **Severity:** Medium
- **Files:** `frontend/lib/features/settings/presentation/providers/role_permissions_notifier.dart` (`saveChanges`)
- **Explanation:** `saveChanges` loops over every dirty cell and `await`s `updateRolePermission` one at a time. Two problems: (a) **no atomicity** — if cell 3 of 5 fails, cells 1–2 are already persisted, but the catch block sets state back from `current` (the pre-save working matrix) and the success path refetches; on partial failure the user's other intended edits are silently discarded and the DB is left half-updated; (b) **performance** — a full matrix change can be dozens of round trips, each its own network call.
- **Suggested fix:** Add a batch RPC (e.g. `update_role_permissions(jsonb)`) that applies all changes in a single transaction and audit-logs them together. At minimum, on partial failure refetch and clearly report which changes were/weren't applied rather than resetting to the stale working matrix.

### 4. `admin_update_staff_username` mutates GoTrue internal tables directly
- **Severity:** Medium
- **Files:** `backend/supabase/migrations/20260613200000_admin_update_staff_username.sql`, `backend/supabase/migrations/20260614000000_fix_admin_update_staff_username_forbidden.sql`
- **Explanation:** The function writes directly to `auth.users.email` and `auth.identities.provider_id`/`identity_data`. This couples the app to GoTrue's internal schema, which Supabase can change across upgrades; it also rewrites `identity_data` wholesale (only `sub`/`email`) and doesn't touch related columns (`email_confirmed_at`, change tokens). The uniqueness check (`SELECT ... WHERE lower(email)=...`) plus the `unique_violation` handler is reasonable for races, but the broader approach is fragile. (Note: the original `200000` migration also lacked a `FORBIDDEN` handler; `20260614000000` correctly fixes that — good catch, but it leaves two near-identical 100-line migrations.)
- **Suggested fix:** Prefer GoTrue admin APIs / Supabase auth admin where possible. If direct SQL is required, centralize it in one `auth_internal` helper (reused by `create_auth_user`) so the auth-schema coupling lives in exactly one place, and document the GoTrue version assumption.

### 5. Cross-org branch validation in staff create checks all organizations
- **Severity:** Low (Medium if the system ever becomes multi-tenant)
- **Files:** `backend/supabase/migrations/20260613150000_create_staff_account_phone.sql` (lines ~61–75)
- **Explanation:** The branch-validity `EXISTS` check accepts any branch whose `organization_id IN (SELECT id FROM organizations WHERE is_deleted=false)` — i.e. **any** organization, not the caller's `jwt_organization_id()`. The codebase is single-installation, so this is currently benign, but it's inconsistent with the org-scoping used elsewhere (e.g. `delete_branch`, `delete_staff_member`) and would allow cross-tenant branch assignment if a second org ever exists.
- **Suggested fix:** Scope the validation to `b.organization_id = public.jwt_organization_id()` for consistency and defense-in-depth.

### 6. `delete_staff_member` error precedence on active members
- **Severity:** Low
- **Files:** `backend/supabase/migrations/20260613210000_delete_staff_member.sql`
- **Explanation:** When the target is still active, the function runs `assert_not_last_administrator` *before* returning `STAFF_STILL_ACTIVE`. For an active last administrator the caller gets `LAST_ADMINISTRATOR` instead of the more accurate `STAFF_STILL_ACTIVE` ("deactivate first"). The last-admin check is then repeated on the delete path. Not a correctness bug (delete is still blocked), just redundant work and a slightly misleading message.
- **Suggested fix:** Return `STAFF_STILL_ACTIVE` first when `v_staff.is_active`, and run the last-admin guard only on the actual delete path.

### 7. Idle-timeout setting is device-local but framed as a clinic policy
- **Severity:** Low
- **Files:** `frontend/lib/features/settings/application/idle_timeout_settings_notifier.dart`, `.../data/idle_timeout_preferences_store*.dart`, `.../presentation/widgets/idle_timeout_settings_card.dart`, `frontend/lib/app/providers/auth_session_provider.dart`
- **Explanation:** The idle sign-out duration is persisted only in a local preferences store (per workstation). The copy ("Shared clinic workstations…") makes the per-device intent mostly clear, but it sits under admin Settings and reads like an org-wide control; changing it on one machine does not propagate. The async load in `_enableIdleWithPersistedDuration` correctly falls back to `kIdleTimeoutDuration` and re-checks `ref.mounted`/auth before applying — that part is solid.
- **Suggested fix:** Either label it explicitly as "this workstation only," or move enforcement to org settings (`organizations.settings_json`) so it is consistent across devices.

### 8. Dead/duplicated migration code for `bootstrap_finish_setup`
- **Severity:** Low
- **Files:** `backend/supabase/migrations/20260613120000_bootstrap_finish_setup_working_schedule.sql`, `20260613150000_create_staff_account_phone.sql`
- **Explanation:** `120000` defines a 12-arg `bootstrap_finish_setup` that inserts staff **without** phone; `150000` immediately redefines the same signature to add phone. The final state is correct (later migration wins), but `120000`'s body is dead on arrival. Additionally the prior 11-arg overload is left in the database (explicitly `REVOKE`d from `authenticated`, which is what avoids PostgREST overload ambiguity — good — but it's lingering surface area).
- **Suggested fix:** Squash the two redefinitions where practical, and `DROP FUNCTION IF EXISTS` the obsolete 11-arg overload once nothing depends on it.

### 9. Function-signature drops create a deploy-ordering window
- **Severity:** Low
- **Files:** `20260613150000_create_staff_account_phone.sql` (`DROP FUNCTION ... create_staff_account(6 args)`), `20260613120000_*` (bootstrap signature change)
- **Explanation:** These migrations drop the previous `create_staff_account`/`bootstrap_finish_setup` signatures and recreate them with extra params. An old frontend running against the new schema (mid-deploy) would call the now-missing 6-arg overload and fail. For a desktop app deployed in lockstep with the DB this is low risk, but worth noting.
- **Suggested fix:** Deploy DB before clients, or keep a thin backward-compatible overload for one release.

---

## Positive notes
- Every migration is **non-destructive**: soft-deletes (`is_deleted`/`deleted_at`), `CREATE OR REPLACE`, and idempotent `INSERT … ON CONFLICT DO NOTHING`. No column/table drops, no data rewrites, no obvious long locks.
- Consistent audit-logging on all new mutating RPCs (`branch.delete`, `staff.delete`, `staff.username_update`, `role_permission.update`).
- Server-side authorization is enforced on all mutations (`assert_permission` / `assert_owner_or_administrator`), and `settings.billing.manage` is correctly non-delegable to non-admin roles.
- `assert_not_last_administrator` and `CANNOT_DELETE_SELF` guards prevent lockout/self-deletion.
- Frontend domain logic is clean and well-tested: `BranchWorkingSchedule`/`StaffListQuery`/`PermissionMatrixView` are immutable with correct `==`/`hashCode`, and the diff adds substantial unit/widget/integration coverage (settings, staff sheet, role matrix, working hours).
- Repository reads are batched (`inFilter`), not N+1; `_loadUsernamesByStaffId` degrades gracefully on error.
- Frontend/backend wire contracts line up (working-schedule JSON shape, staff create params incl. optional phone, time `HH:mm` validation matched on both ends).

---

## Overall assessment
A large, well-structured feature branch with strong test coverage and disciplined, non-destructive migrations. Server-side authorization is solid. The headline issue is a **UI authorization gap** (Finding 1): the Clinic Setup tab in the settings hub is not gated the way the equivalent deep-link routes are, so admin org/branch controls render for non-admin roles. Findings 2 (username enumeration) and 3 (non-atomic permission save) are the next most important. The remaining items are low-risk consistency/cleanliness issues.

## Migration risk assessment
**Low–Medium.** All changes are additive and idempotent with soft-delete semantics — safe against existing production data and easy to re-run. Risks are limited to: function-signature drops creating a brief client/DB version skew (Finding 9), a leftover stale `bootstrap_finish_setup` overload (Finding 8), and the direct manipulation of GoTrue's `auth` schema (Finding 4), which is the single most upgrade-fragile piece. No forward-only rollback blockers, but there are no down-migrations.

## UI quality assessment
**Good.** Modern, token-driven composition (spacing/shape/semantic colors), thoughtful loading/error/empty states, animated tab and filter-grid transitions, and accessible affordances (tooltips, cursors, focus management in the working-hours sheet). Main concerns: the permission-gating inconsistency across settings tabs (Finding 1) and the device-local idle setting framed as policy (Finding 7). No layout/responsiveness regressions spotted in the reviewed widgets.

## Deployment risk
**Medium** — driven almost entirely by Finding 1 (authorization exposure of admin controls to non-admin roles) plus the auth-schema coupling in Finding 4. The migrations themselves are low risk.

## Decision
**Request changes.** Address Finding 1 (gate the Clinic Setup tab / hide admin controls for non-admins) and Finding 2 (permission-gate `staff_login_usernames`) before merge; Finding 3 should be fixed or explicitly accepted. The remaining low-severity items can be follow-ups.
