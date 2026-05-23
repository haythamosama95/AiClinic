# Contract: Patient List and Search

## Purpose

Paginated patient browse and search with branch vs organization scope (V1-3).

## Authorization

Requires `patients.view` (`auth_internal.assert_permission`).

## RPC: `search_patients`

**Caller**: Authenticated staff with `patients.view`

| Parameter     | Type | Required    | Notes                                                                                        |
| ------------- | ---- | ----------- | -------------------------------------------------------------------------------------------- |
| `p_query`     | text | No          | Empty = browse mode (alphabetical list)                                                      |
| `p_scope`     | text | Yes         | `branch` \| `organization`                                                                   |
| `p_branch_id` | uuid | Conditional | Required when `p_scope = branch`; must equal active branch and be in caller JWT `branch_ids` |
| `p_limit`     | int  | No          | Default 25; max 100                                                                          |
| `p_offset`    | int  | No          | Default 0                                                                                    |

### Query interpretation

| Input                             | Rule                                                      |
| --------------------------------- | --------------------------------------------------------- |
| `p_query` empty or whitespace     | Browse: all patients in scope, `ORDER BY full_name ASC`   |
| `p_query` all digits (after trim) | Phone prefix search; length ≥ 2 or return `INVALID_INPUT` |
| Otherwise                         | Name contains: `lower(full_name) LIKE '%'                 |  | lower(trim(p_query)) |  | '%'`; length ≥ 3 or `INVALID_INPUT` |

### Scope

| `p_scope`      | Filter                                                                  |
| -------------- | ----------------------------------------------------------------------- |
| `branch`       | `branch_id = p_branch_id` AND `organization_id = jwt.organization_id()` |
| `organization` | `organization_id = jwt.organization_id()` only                          |

Always: `is_deleted = false`.

### Returns

`rpc_result.data`:

```json
{
  "items": [
    {
      "id": "uuid",
      "full_name": "string",
      "phone": "string|null",
      "date_of_birth": "date|null",
      "branch_id": "uuid",
      "branch_name": "string"
    }
  ],
  "total_count": 0,
  "limit": 25,
  "offset": 0
}
```

`branch_name` included for all scopes (same as registering branch when scope is branch).

### Errors

| Code              | When                                              |
| ----------------- | ------------------------------------------------- |
| `FORBIDDEN`       | Missing `patients.view`                           |
| `INVALID_INPUT`   | Query too short; invalid scope; branch not in JWT |
| `BRANCH_REQUIRED` | `p_scope = branch` without valid `p_branch_id`    |

## Flutter: Patient list page

**Route**: `/patients`

**UI**:

- Scope toggle: **This branch only** (default after sign-in) | **All branches**
- Single search field (debounced ~300ms)
- Data table: name, phone, DOB, branch (visible when scope = all branches or always show branch column)
- Empty / loading / error / permission denied states per spec
- FAB or primary action **Register patient** when `patients.create`

**Session**: `PatientListScopeNotifier` — resets to `thisBranch` on sign-in.

**Client guard**: Hide route when `!patients.view`.

## Out of scope

- Appointment queue integration (V1-4)
- Export CSV
- Restore archived patients
