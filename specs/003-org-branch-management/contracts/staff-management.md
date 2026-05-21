# Contract: Staff Management

## Purpose

Steady-state staff list, create, edit, deactivate, reactivate, and password reset. Builds on V1-1 provisioning contracts.

## Authorization

| Operation           | Requirement                                    |
| ------------------- | ---------------------------------------------- |
| List / view         | `settings.manage_staff`                        |
| Create              | `settings.manage_staff` + owner-creation rules |
| Update / deactivate | `settings.manage_staff`                        |
| Password reset      | `owner` or `administrator` (unchanged V1-1)    |

## Read: staff list

**Method**: PostgREST join or view query org-scoped by RLS

**Minimum columns**: `id`, `full_name`, `role`, `phone`, `is_active`, assignments summary

**Filters**: active / inactive / all (non-deleted)

## RPC: `create_staff_account` (existing)

See `specs/002-auth-rbac/contracts/bootstrap-provisioning.md`. Used from staff create form in settings area.

## RPC: `update_staff_member`

**Caller**: `settings.manage_staff`

| Parameter             | Type       | Required                     |
| --------------------- | ---------- | ---------------------------- |
| `p_staff_member_id`   | uuid       | Yes                          |
| `p_full_name`         | text       | Yes                          |
| `p_phone`             | text       | No                           |
| `p_role`              | staff_role | Yes                          |
| `p_branch_ids`        | uuid[]     | Yes                          |
| `p_primary_branch_id` | uuid       | No                           |
| `p_is_active`         | boolean    | No (omit to leave unchanged) |

**Validation**:

- Staff in caller’s organization (via assignments / org staff policy)
- At least one **active** branch in `p_branch_ids`
- `p_primary_branch_id` ∈ `p_branch_ids` when multiple
- Owner-creation rules on role change (FR-022c)
- Cannot deactivate self if last owner (optional guard — defer unless product requires)

**Side effects**:

- Replace assignments: soft-delete removed pairs, upsert new, set primary
- Role change may require user to re-login for JWT `role` claim update

**Audit**: `staff.update`

## RPC: `set_staff_active`

| Parameter           | Type    | Required |
| ------------------- | ------- | -------- |
| `p_staff_member_id` | uuid    | Yes      |
| `p_is_active`       | boolean | Yes      |

**Audit**: `staff.deactivate` / `staff.reactivate`

## RPC: `admin_reset_staff_password` (existing)

Exposed from staff detail screen in settings. See 002 contract.

## UI: Staff Management

**Routes**: `/settings/staff`, `/settings/staff/new`, `/settings/staff/:id`, `/settings/staff/:id/reset-password`

**States**: List empty/loaded; form validation; owner-creation blocked; deactivate confirm

**Post-deactivate**: Existing sessions fail on refresh (inactive staff in `build_staff_claims`)

## Related: blocked shell

Staff with assignments only to inactive branches: empty `branch_ids` at login — same UI as `NoBranchBlockedPanel` (V1-1).
