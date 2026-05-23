# Data Model: Organization and Branch Management

Uses V1-1 tables from `specs/002-auth-rbac/data-model.md`. V1-2 adds constraints and state rules below; **no new core tenancy tables**.

## Schema delta (V1-2 migration)

### Partial unique: branch code per organization

```sql
CREATE UNIQUE INDEX IF NOT EXISTS branches_organization_code_unique
  ON public.branches (organization_id, lower(trim(code)))
  WHERE code IS NOT NULL
    AND trim(code) <> ''
    AND is_deleted = false;
```

## Entity state transitions

### Organization

| State        | Condition            | Visible in management UI          |
| ------------ | -------------------- | --------------------------------- |
| Active       | `is_deleted = false` | Yes (single row per installation) |
| Soft-deleted | `is_deleted = true`  | No                                |

**Mutations**: `update_organization` RPC only (owner/administrator). No create-second-org.

### Branch

| State        | `is_active` | `is_deleted` | In branch switcher     | In assignment pickers      |
| ------------ | ----------- | ------------ | ---------------------- | -------------------------- |
| Active       | true        | false        | Yes (if user assigned) | Yes                        |
| Deactivated  | false       | false        | No                     | No (reactivate to restore) |
| Soft-deleted | *           | true         | No                     | No                         |

**Rules**:

- Deactivate last active branch in org: **blocked** (`LAST_ACTIVE_BRANCH`).
- Deactivate does not remove `staff_branch_assignments` rows.

### Staff member

| State                                | `is_active` | `is_deleted` | Can sign in                              | JWT claims         |
| ------------------------------------ | ----------- | ------------ | ---------------------------------------- | ------------------ |
| Active                               | true        | false        | Yes (if active branch assignments exist) | Full claims        |
| Deactivated                          | false       | false        | No new session                           | N/A                |
| Active, no active branch assignments | true        | false        | Yes → blocked shell                      | `branch_ids` empty |
| Soft-deleted                         | *           | true         | No                                       | N/A                |

**Rules**:

- Owner creation: unchanged from V1-1 (bootstrap first owner; thereafter owners only).
- Role change to `owner`: server enforces FR-022c.

### Staff branch assignment

| Rule                                                       | Enforcement                                    |
| ---------------------------------------------------------- | ---------------------------------------------- |
| At least one active branch when role requires branch scope | `update_staff_member` / `create_staff_account` |
| Exactly one `is_primary = true` when multiple assignments  | RPC normalizes or rejects                      |
| Assignments to deactivated branches allowed historically   | Excluded from JWT via inactive branch join     |

### Role permission (`roles_permissions`)

| Field            | Notes                                                          |
| ---------------- | -------------------------------------------------------------- |
| `role`           | One of five `staff_role` values                                |
| `permission_key` | Catalog key from architecture; UI cannot invent keys           |
| `is_granted`     | Owner or administrator may toggle via `update_role_permission` |

**Global catalog**: Not per-organization rows (unchanged from V1-1).

## Authorization matrix (V1-2 operations)

| Operation                         | Owner                                 | Administrator | Doctor / Receptionist / Lab |
| --------------------------------- | ------------------------------------- | ------------- | --------------------------- |
| View/update organization          | Yes                                   | Yes           | No                          |
| Branch CRUD (manage)              | If `settings.manage_branches` granted | If granted    | No                          |
| Staff CRUD (manage)               | If `settings.manage_staff` granted    | If granted    | No                          |
| View permission matrix            | Yes                                   | Yes           | No                          |
| Edit permission matrix            | Yes                                   | Yes           | No                          |
| Branch switcher (active branches) | If assigned                           | If assigned   | If assigned                 |
| Password reset other staff        | Yes                                   | Yes           | No                          |

Organization settings use **role check**; branch/staff use **permission keys** from seeded matrix (owner/administrator seeded with manage grants in V1-1).

## RPC inventory (planned names)

| RPC                                       | Purpose                               |
| ----------------------------------------- | ------------------------------------- |
| `update_organization`                     | Profile/locale/settings_json update   |
| `manage_create_branch`                    | Steady-state branch create            |
| `update_branch`                           | Field update                          |
| `set_branch_active`                       | Deactivate/reactivate (`is_active`)   |
| `update_staff_member`                     | Profile, role, active, assignments    |
| `set_staff_active`                        | Deactivate/reactivate staff           |
| `update_role_permission`                  | Toggle grant (owner or administrator) |
| *(existing)* `create_staff_account`       | Create staff                          |
| *(existing)* `admin_reset_staff_password` | Reset password                        |

## Client models (Flutter)

| Type                  | Fields (representative)                                 |
| --------------------- | ------------------------------------------------------- |
| `OrganizationProfile` | id, name, logoUrl, currencyCode, timezone, settingsJson |
| `BranchListItem`      | id, name, code, isActive, phone, address                |
| `StaffListItem`       | id, fullName, role, isActive, branchNames               |
| `StaffEditorState`    | profile fields, branchIds, primaryBranchId              |
| `PermissionMatrixRow` | role, permissionKey, isGranted                          |

## Relationships (unchanged)

```text
organizations 1──* branches
branches *──* staff_members (via staff_branch_assignments)
staff_members *──1 auth.users
roles_permissions keyed by staff_role (global)
```

## Audit actions (new)

| Action                                                                        | Trigger                  |
| ----------------------------------------------------------------------------- | ------------------------ |
| `organization.update`                                                         | `update_organization`    |
| `branch.create` / `branch.update` / `branch.deactivate` / `branch.reactivate` | Branch RPCs              |
| `staff.update` / `staff.deactivate` / `staff.reactivate`                      | Staff RPCs               |
| `role_permission.update`                                                      | `update_role_permission` |

Existing `organization.bootstrap_create`, `branch.bootstrap_create`, `staff.create` from V1-1 remain.
