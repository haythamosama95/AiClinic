# Contract: Bootstrap & Provisioning

## Purpose

Defines RPC and UI contracts for first-time clinic setup and minimal staff administration in V1-1.

## Preconditions

| Step                       | Requirement                                                             |
| -------------------------- | ----------------------------------------------------------------------- |
| Sign in as bootstrap admin | Seeded `is_bootstrap_admin` account                                     |
| Create organization        | Zero rows in `organizations`                                            |
| Create branch              | Organization exists; ≥0 branches (allow multiple in V1-1 minimal setup) |
| Create staff               | ≥1 organization AND ≥1 branch                                           |

## RPC: `bootstrap_create_organization`

**Caller**: Bootstrap administrator only (`is_bootstrap_admin` and no existing organization)

| Parameter         | Type  | Required |
| ----------------- | ----- | -------- |
| `p_name`          | text  | Yes      |
| `p_settings_json` | jsonb | No       |

**Returns**: `rpc_result` with `data.organization_id`

**Errors**: `ORG_ALREADY_EXISTS`, `NOT_BOOTSTRAP_ADMIN`

## RPC: `bootstrap_create_branch`

**Caller**: Bootstrap administrator (pre-owner) or owner/administrator after setup

| Parameter           | Type | Required |
| ------------------- | ---- | -------- |
| `p_organization_id` | uuid | Yes      |
| `p_name`            | text | Yes      |
| `p_address`         | text | No       |
| `p_phone`           | text | No       |

**Side effect**: Assign bootstrap admin to branch with `is_primary=true` when first branch for org.

## RPC: `create_staff_account`

**Caller**: Owner or administrator (bootstrap admin counts as administrator before owner exists)

| Parameter             | Type       | Required |
| --------------------- | ---------- | -------- |
| `p_email`             | text       | Yes      |
| `p_password`          | text       | Yes      |
| `p_full_name`         | text       | Yes      |
| `p_role`              | staff_role | Yes      |
| `p_branch_ids`        | uuid[]     | Yes      |
| `p_primary_branch_id` | uuid       | No       |

**Owner creation rules (FR-022c)**:

| Caller state                  | May create `owner`? |
| ----------------------------- | ------------------- |
| Bootstrap admin, no owner yet | Yes                 |
| Administrator, owner exists   | No                  |
| Owner                         | Yes                 |

**Returns**: `rpc_result` with `staff_member_id`, `assigned_password` (echo of input for admin display)

**Errors**: `ORG_SETUP_INCOMPLETE`, `FORBIDDEN_OWNER_CREATE`, `EMAIL_EXISTS`

## RPC: `admin_reset_staff_password`

**Caller**: Owner or administrator

| Parameter           | Type | Required |
| ------------------- | ---- | -------- |
| `p_staff_member_id` | uuid | Yes      |
| `p_new_password`    | text | Yes      |

**Returns**: `rpc_result` with `assigned_password` (echo only)

**Errors**: `FORBIDDEN`, `STAFF_NOT_FOUND`, `CROSS_ORG_DENIED`

## UI Flows

### First sign-in warning

- Shown once for bootstrap admin
- Dismissible; does not block navigation
- Recommends changing shipped password

### Clinic bootstrap wizard

1. Organization name (single org)
2. First branch details
3. On success → enable staff provisioning entry point

### Staff account create form

- Email, full name, role, branch multi-select, primary branch, initial password
- Success dialog shows email + password for admin to communicate

### Staff password reset form

- Select staff (simple list query scoped by RLS)
- New password field
- Show assigned password after success

## Out of Scope

- Edit/deactivate staff
- Organization settings beyond initial name
- Branch deactivate/list management UI
- Permission matrix editor
