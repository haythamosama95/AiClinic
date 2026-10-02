# Data Model: Membership and active organisation

**Unit**: P1.1 · **Spec**: [spec.md](./spec.md) · **Date**: 2026-10-02

PostgreSQL is the authority and the only writer. There is no copy (FR-001). Both tables live in the existing non-exposed `ai_internal` schema (03 §4).

## 1. membership

One row is one user's membership in one organisation (FR-001). A user may hold a membership in more than one organisation.

| Column | Type | Notes |
| --- | --- | --- |
| `user_id` | `uuid` NOT NULL | JWT `sub`. References `auth.users(id)` ON DELETE CASCADE. |
| `organization_id` | `uuid` NOT NULL | References `public.organizations(id)` ON DELETE CASCADE. |
| `role` | `public.staff_role` NOT NULL | `administrator`, `doctor`, `receptionist`, or `lab_staff` (FR-007, T-5). |
| `created_at` | `timestamptz` NOT NULL DEFAULT `now()` | Sign-in ordering key (01 §7 R-1). Backfill copies `public.staff_members.created_at`. |

Primary key: `(user_id, organization_id)`.

A membership is live while the row exists. This unit does not add `is_deleted`. Removing a membership deletes the row (E2E-P1.1-04).

### 1.1 Backfill

The migration inserts one row per non-deleted `public.staff_members` row when at least one non-deleted organisation exists (FR-002, T-1):

- `user_id` = `staff_members.auth_user_id`
- `organization_id` = the earliest non-deleted `public.organizations` row by `created_at` (the organisation `auth_internal.build_staff_claims` already takes)
- `role` = `staff_members.role`
- `created_at` = `staff_members.created_at`

`is_active` does not exclude a row. A non-deleted staff member and no non-deleted organisation produces no membership, because there is no organisation for the claim to take. That is the bootstrap administrator created by `20260516100400_auth_rbac_seed.sql` on a fresh database.

### 1.2 Access

Row level security is enabled with a deny-all policy. `anon`, `authenticated`, and `service_role` receive no privileges. `public.current_org_id()`, `public.current_membership_role()`, `auth_internal.sync_active_organization(uuid)`, and `public.set_active_organization(uuid)` are `SECURITY DEFINER` and are the readers and writers.

## 2. user_active_organization

One mutable active organisation per user. It is the source of the session `active_org` claim (FR-003, 03 §4).

| Column | Type | Notes |
| --- | --- | --- |
| `user_id` | `uuid` PRIMARY KEY | References `auth.users(id)` ON DELETE CASCADE. |
| `organization_id` | `uuid` NOT NULL | References `public.organizations(id)` ON DELETE CASCADE. |
| `updated_at` | `timestamptz` NOT NULL DEFAULT `now()` | Set when the chosen organisation changes. |

### 2.1 Writers

Only these two writers (03 §4):

1. `auth_internal.sync_active_organization(uuid)`, called from the access-token hook `public.get_custom_claims(jsonb)`.
2. `public.set_active_organization(uuid)`, and only after a live membership in the named organisation exists (FR-004).

Sign-in choice (01 §7 R-1, 06 §6 OQ-2, FR-003):

- The stored `organization_id` is kept when it still names a live membership.
- Otherwise the row becomes the first live membership by `(created_at, organization_id)`.
- With no live membership the row is deleted and the claim carries no `active_org`.

The active organisation changes only through `set_active_organization` after sign-in (OQ-2). The hook does not accept an organisation argument.

### 2.2 Access

Same deny-all posture as `membership`. No client privilege on the table.
