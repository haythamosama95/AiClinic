# Contract: Shift Queries (V1-7)

Read paths. All reads honor branch RLS. Listing and detail require branch assignment in JWT; **`shifts.manage` is NOT required** for reads (FR-003a). Clients MUST perform a backend-first fetch (FR-022) before rendering actionable content.

---

## `list_shifts(p_branch_id uuid, p_date_from date, p_date_to date) RETURNS jsonb`

**Scope**: Caller must be assigned to `p_branch_id`.

**Parameters**:

- `p_date_from`, `p_date_to`: inclusive date range for `shift_date`. Caller SHOULD keep range ≤ 42 days for month view performance (NFR-003).

**Returns**: JSON array sorted by `shift_date`, `start_time`:

```jsonc
[
  {
    "id": "uuid",
    "branch_id": "uuid",
    "shift_date": "2026-06-10",
    "start_time": "09:00",
    "end_time": "17:00",
    "status": "active",           // active | incomplete (cancelled excluded)
    "is_unassigned": false,
    "assignee_names": ["Reception A", "Dr. Sara"],
    "assignee_count": 2,
    "notes_preview": "Morning coverage"  // first 80 chars or null
  }
]
```

**Filters**: Excludes soft-deleted (`deleted_at IS NOT NULL`) shifts.

**Errors**: `permission_denied` (branch not in JWT), `invalid_date_range` (`p_date_to < p_date_from`)

---

## `get_shift_detail(p_shift_id uuid) RETURNS jsonb`

**Scope**: Shift's `branch_id` ∈ caller JWT `branch_ids`.

**Returns**:

```jsonc
{
  "shift": {
    "id": "uuid",
    "branch_id": "uuid",
    "shift_date": "2026-06-10",
    "start_time": "09:00",
    "end_time": "17:00",
    "notes": "Optional notes",
    "status": "active",           // active | incomplete | cancelled
    "is_unassigned": false,
    "is_past": false,             // shift_date < org_today
    "is_read_only": false,        // true when is_past OR caller lacks shifts.manage OR cancelled
    "updated_at": "timestamptz"
  },
  "assignments": [
    {
      "id": "uuid",
      "staff_member_id": "uuid",
      "display_name": "Dr. Sara"
    }
  ],
  "branch": {
    "id": "uuid",
    "name": "Main Clinic",
    "code": "MAIN"
  }
}
```

**`is_read_only` computation** (server-side, returned for UI gating):

- `true` if shift cancelled, or `shift_date < org_today`, or caller lacks `shifts.manage`.
- Branch-assigned staff without `shifts.manage` still receive detail with `is_read_only: true`.

**Errors**: `permission_denied`, `shift_not_found` (includes cross-branch — no existence leak)

---

## Calendar period helpers (client-side)

The Flutter calendar provider computes fetch bounds:

| Mode  | `p_date_from`            | `p_date_to              |
| ----- | ------------------------ | ----------------------- |
| Week  | Monday of focus week     | Sunday of focus week    |
| Month | First day of focus month | Last day of focus month |

On branch switch, client clears cached items and refetches (edge case: active branch change reloads calendar).

---

## Staff picker data source

No new query RPC. Assignment UI uses existing V1-2 staff list filtered client-side to:

- `is_active = true`
- assigned to shift's `branch_id`

Server re-validates on `create_shift` and `modify_shift_assignments`.
