# Clinic administration (V1-2)

Steady-state organization, branch, staff, and permission management after V1-1 bootstrap is complete (`setup_required = false`).

## Prerequisites

- Completed [bootstrap-admin.md](./bootstrap-admin.md) (organization + first branch exist).
- Signed-in user with the appropriate role or permission (see table below).
- Local Supabase stack running ([server-node.md](./server-node.md)).

## Settings hub

From the authenticated shell, open **Settings** (home screen link or `/settings`). The hub lists:

| Screen           | Route                    | Who can access                                  |
| ---------------- | ------------------------ | ----------------------------------------------- |
| Organization     | `/settings/organization` | Owner, administrator (role check)               |
| Branches         | `/settings/branches`     | `settings.manage_branches`                      |
| Staff            | `/settings/staff`        | `settings.manage_staff`                         |
| Role permissions | `/settings/permissions`  | Owner, administrator (view); owner edits matrix |
| Idle timeout     | `/settings/idle-timeout` | Authenticated staff                             |

## Organization

- Edit clinic name, logo URL, currency, timezone, and settings summary JSON.
- Saves call `update_organization` RPC; doctors and other roles without owner/administrator role are redirected to the settings hub.

## Branches

- List with **Active**, **Inactive**, and **All** filters.
- Create (`/settings/branches/new`) and edit (`/settings/branches/:id/edit`).
- **Deactivate** / **Reactivate** only — there is no delete action (FR-018a).
- Deactivating the sole active branch is blocked with an **Edit branch** shortcut (`LAST_ACTIVE_BRANCH`).

## Staff

- List, create, edit, deactivate, and reactivate staff.
- Branch multi-select and primary branch on create/edit.
- Password reset from staff detail (`/settings/staff/:id/reset-password`) reuses V1-1 `admin_reset_staff_password`.
- Owner-creation rules from V1-1 still apply (administrator cannot create a second owner).

## Branch switcher

- Primary control: **shell status bar** (bottom), not the AppBar.
- Lists only **active** branches assigned to the signed-in user.
- Staff with no active assignments see the blocked shell (no permission demo).

## Role permissions

- Owner and administrator can open the matrix; toggles persist via `update_role_permission`.
- After save, the owner session reloads permission cache (`reloadContext`); other users pick up changes on next login or resume.
- Server enforces current grants immediately on RPC; client cache is UX-only.

## Legacy V1-1 routes

When setup is complete:

- `/staff/create` → `/settings/staff/new` (if permitted) or settings hub
- `/staff/password-reset` → `/settings/staff`

Bootstrap wizard routes remain active only while `setup_required` is true.

## Verification

| Layer                   | Command                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| Backend V1-2            | `./backend/tests/run_org_branch_management_tests.sh`                                               |
| Backend V1-1 regression | `./backend/tests/run_auth_backend_tests.sh`                                                        |
| Flutter acceptance      | `cd frontend && flutter test test/integration/settings/org_branch_management_acceptance_test.dart` |
| Full Flutter            | `cd frontend && flutter test`                                                                      |

Feature quickstart: [specs/003-org-branch-management/quickstart.md](../../specs/003-org-branch-management/quickstart.md).
