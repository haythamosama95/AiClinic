# Research: Organization and Branch Management

## Decision 1: Extend `auth_internal` + public RPC wrappers (same as V1-1)

- **Decision**: Add steady-state management functions in `auth_internal` (SECURITY DEFINER) with thin `public.*` INVOKER entry points for PostgREST, matching migration `20260521110000_auth_rbac_definer_internal_schema.sql`.
- **Rationale**: Constitution III; keeps permission checks and audit in PostgreSQL; avoids new backend service.
- **Alternatives considered**: Direct PostgREST PATCH on `organizations`/`branches` (rejected — RLS blocks inserts/updates today; bypasses centralized validation). Edge Functions (rejected — cloud-only, out of V1 scope).

## Decision 2: Organization settings authorized by role, not new permission key

- **Decision**: `update_organization` allows `owner` and `administrator` only; no `settings.manage_organization` seed row.
- **Rationale**: Clarification session 2026-05-21; reduces migration churn; aligns with business context.
- **Alternatives considered**: New permission key granted to owner+admin (rejected — unnecessary for two roles). Owner-only (rejected — user chose B).

## Decision 3: Branch lifecycle uses `is_active` only in UI

- **Decision**: Management screens expose deactivate/reactivate; no soft-delete UI for branches or staff in V1-2.
- **Rationale**: Clarification session; `is_deleted` remains for maintenance/future admin tools.
- **Alternatives considered**: Owner soft-delete with confirmation (rejected).

## Decision 4: Last active branch deactivation hard-block with edit shortcut

- **Decision**: `set_branch_active(false)` returns `LAST_ACTIVE_BRANCH` when count of active branches in org would become zero; Flutter shows message + navigates to branch edit.
- **Rationale**: Clarification session; prevents zero-branch tenant lockout.
- **Alternatives considered**: Confirm-and-allow (rejected).

## Decision 5: JWT `branch_ids` already exclude inactive branches

- **Decision**: No change to claim builder logic beyond verification tests; `auth_internal.build_staff_claims` already joins `b.is_active = true`. Staff with only inactive assignments get empty `branch_ids` → blocked shell.
- **Rationale**: Existing migration `20260521170000_fix_staff_claims_org_and_dev_reset_invoker.sql` matches clarified spec.
- **Alternatives considered**: Include inactive branches in claims with client filter (rejected — violates fail-closed).

## Decision 6: Steady-state branch create separate from bootstrap RPC

- **Decision**: New `manage_create_branch` (name TBD in contracts) requires `settings.manage_branches` and existing organization; bootstrap RPC remains for `setup_required` flows only.
- **Rationale**: Bootstrap path assigns bootstrap admin to first branch; steady-state path does not auto-assign caller unless product rule added later.
- **Alternatives considered**: Reuse `bootstrap_create_branch` for all creates (rejected — bootstrap guard and side effects differ).

## Decision 7: Staff update RPC replaces ad-hoc client patches

- **Decision**: `update_staff_member` RPC handles profile, role, `is_active`, and replacement of branch assignments in one transaction; reuse `create_staff_account` and `admin_reset_staff_password` from V1-1.
- **Rationale**: Atomic assignment updates; enforces owner-creation rules on role change server-side.
- **Alternatives considered**: Client updates `staff_members` + separate assignment RPCs (rejected — partial failure risk).

## Decision 8: Permission matrix updates owner-only; cache reload policy

- **Decision**: `update_role_permission` owner-only; after save, owner’s client reloads permissions; affected users pick up changes on next login or `AuthSessionNotifier.reloadContext()` triggers (app resume, post-save refresh hook).
- **Rationale**: Clarification FR-011; server RPCs always read current `roles_permissions` rows.
- **Alternatives considered**: Realtime broadcast to all clients (rejected — complexity, no Realtime requirement in spec).

## Decision 9: Branch switcher placement in shell status bar

- **Decision**: Move primary branch switcher from `AuthShellPage` AppBar to persistent shell status bar per `docs/architecture/07-frontend.md` → Navigation Architecture (status bar: Branch | User | Connection). AppBar may retain user menu only.
- **Rationale**: Spec FR-009 + architecture diagram; defers status-bar shell component to implementation but fixes target location.
- **Alternatives considered**: Keep AppBar dropdown (rejected for steady-state — contradicts architecture target layout).

## Decision 10: Flutter module layout under `features/settings`

- **Decision**: Expand `features/settings` with sub-routes for organization, branches, staff list/detail, and role permissions; data layer repositories call RPCs; reuse `PermissionRepository` with explicit reload API.
- **Rationale**: Existing `/settings` route and settings hub; keeps admin flows out of `auth` bootstrap module.
- **Alternatives considered**: New top-level `features/clinic_admin` (acceptable alias but duplicates settings entry — rejected).

## Decision 11: Branch code uniqueness

- **Decision**: Add partial unique index `(organization_id, lower(trim(code)))` WHERE `code IS NOT NULL AND is_deleted = false` in V1-2 migration.
- **Rationale**: Spec edge case; prevents duplicate codes within org.
- **Alternatives considered**: App-only validation (rejected — constitution III).

## Decision 12: List reads via PostgREST SELECT under RLS

- **Decision**: Branch and staff lists use filtered `.from().select()` for owners/admins with org scope; organization row single SELECT; permission matrix SELECT on `roles_permissions` for view; mutations only via RPC.
- **Rationale**: Reduces RPC surface for read-heavy screens; RLS already org-scoped.
- **Alternatives considered**: `list_branches` RPC (deferred — optional optimization if RLS proves insufficient for staff org-wide list).
