# Contract: Branch Management

## Purpose

Steady-state branch list, create, edit, deactivate, and reactivate under the caller’s organization.

## Authorization

Mutations require `settings.manage_branches` (server checks `roles_permissions` for caller’s role).

Reads: owner/administrator with manage permission, or broader read policy per RLS (org-scoped SELECT).

## Read: branch list

**Method**: PostgREST

```text
from('branches')
  .select('id, name, code, address, phone, maps_url, is_active, updated_at')
  .eq('organization_id', organizationId)
  .eq('is_deleted', false)
  .order('name')
```

**UI filters**:

| Tab/filter      | Query                 |
| --------------- | --------------------- |
| Active          | `is_active = true`    |
| Inactive        | `is_active = false`   |
| All non-deleted | no `is_active` filter |

## RPC: `manage_create_branch`

**Caller**: Authenticated with `settings.manage_branches`

| Parameter    | Type | Required |
| ------------ | ---- | -------- |
| `p_name`     | text | Yes      |
| `p_code`     | text | No       |
| `p_address`  | text | No       |
| `p_phone`    | text | No       |
| `p_maps_url` | text | No       |

**Validation**:

- Organization must exist for caller (`jwt.organization_id`)
- `setup_required` must be false (use bootstrap RPC during setup)
- Unique code per org when `p_code` provided (index `branches_organization_code_unique`)

**Returns**: `rpc_result` with `branch_id`

**Audit**: `branch.create`

## RPC: `update_branch`

| Parameter     | Type | Required |
| ------------- | ---- | -------- |
| `p_branch_id` | uuid | Yes      |
| `p_name`      | text | Yes      |
| `p_code`      | text | No       |
| `p_address`   | text | No       |
| `p_phone`     | text | No       |
| `p_maps_url`  | text | No       |

**Validation**: Branch in caller’s organization; code uniqueness excluding self

**Audit**: `branch.update`

## RPC: `set_branch_active`

| Parameter     | Type    | Required |
| ------------- | ------- | -------- |
| `p_branch_id` | uuid    | Yes      |
| `p_is_active` | boolean | Yes      |

**Rules**:

- `p_is_active = false` when branch is the **only** active branch in org → error `LAST_ACTIVE_BRANCH`
- Branch must belong to caller’s organization

**Audit**: `branch.deactivate` or `branch.reactivate`

## UI: Branch Management

**Routes**: `/settings/branches`, `/settings/branches/new`, `/settings/branches/:id/edit`

**Last-active-branch UX**: On `LAST_ACTIVE_BRANCH`, show dialog with message and **Edit branch** action routing to edit form (FR-003a).

**Out of scope**: Soft-delete UI; bootstrap create (see `bootstrap-provisioning.md` in 002)
