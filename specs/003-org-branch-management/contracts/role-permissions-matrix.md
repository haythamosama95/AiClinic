# Contract: Role Permissions Matrix

## Purpose

View and edit global `roles_permissions` grants per staff role (V1-2).

## Authorization

| Action       | Owner | Administrator | Other |
| ------------ | ----- | ------------- | ----- |
| View matrix  | Yes   | Yes           | No    |
| Update grant | Yes   | No            | No    |

## Read: permission matrix

**Method**: PostgREST

```text
from('roles_permissions')
  .select('role, permission_key, is_granted')
  .eq('is_deleted', false)
  .order('role')
  .order('permission_key')
```

**UI shape**: Rows grouped by `permission_key`; columns or tabs per `staff_role` (five roles). Toggle only for owner.

**Catalog**: Only keys present in seed + architecture doc; UI does not add arbitrary keys in V1-2.

## RPC: `update_role_permission`

**Caller**: `owner` only

| Parameter          | Type       | Required |
| ------------------ | ---------- | -------- |
| `p_role`           | staff_role | Yes      |
| `p_permission_key` | text       | Yes      |
| `p_is_granted`     | boolean    | Yes      |

**Validation**:

- Row must exist for (`p_role`, `p_permission_key`) or insert if seed allows extension (prefer UPDATE existing seed rows only)
- Reject unknown `p_permission_key` not in catalog whitelist

**Returns**: `rpc_result`

**Audit**: `role_permission.update` with old/new grant

## Effective timing (FR-011)

| Layer               | Behavior                                                                      |
| ------------------- | ----------------------------------------------------------------------------- |
| Server RPCs         | Read current `is_granted` immediately                                         |
| Client cache        | Updates on next login or `AuthSessionNotifier.reloadContext()`                |
| Triggers for reload | App resume, successful matrix save (owner), optional explicit refresh control |

**Test implication**: After owner revokes `settings.manage_branches` for administrator, administrator’s **RPC** branch create fails immediately; **UI** may hide controls only after reload.

## UI: Role Permissions

**Route**: `/settings/permissions`

**States**: View-only (administrator), Editable toggles (owner), Permission denied

**Out of scope**: Per-organization permission overrides; custom permission key authoring
