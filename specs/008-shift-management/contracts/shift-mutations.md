# Contract: Shift Mutations (V1-7)

All mutations are PL/pgSQL functions exposed via Supabase RPC. Each enforces (1) `shifts.manage` permission, (2) branch scope, (3) shift mutability (not cancelled, not past date), (4) domain validation, (5) audit write, (6) optimistic concurrency where applicable. Errors use `SQLSTATE 'P0001'` with stable codes from `data-model.md` Failure Modes Reference.

---

## `create_shift(p_branch_id uuid, p_shift_date date, p_start_time time, p_end_time time, p_notes text DEFAULT NULL, p_staff_ids uuid[] DEFAULT '{}') RETURNS uuid`

**Permission**: `shifts.manage`

**Pre-checks**:

- `p_branch_id` ∈ caller JWT `branch_ids` and caller's organization.
- `p_shift_date >= org_today` (organization timezone).
- `p_end_time > p_start_time`.
- `p_notes` trimmed length ≤ 500 (empty → `NULL`).
- For each id in `p_staff_ids`: staff active and assigned to `p_branch_id`.
- If `cardinality(p_staff_ids) > 0`: overlap check for all staff at branch/date/times.

**Behavior**: Inserts `shifts` row with denormalized `organization_id`. Inserts `shift_assignments` for each staff id. Single transaction. Audited as `shift.create` with staff ids.

**Returns**: `shift_id`

**Errors**: `permission_denied`, `shift_read_only_past_date`, `shift_invalid_time_range`, `notes_too_long`, `staff_not_eligible`, `shift_overlap`, `invalid_shift_date`

---

## `update_shift(p_shift_id uuid, p_expected_updated_at timestamptz, p_shift_date date, p_start_time time, p_end_time time, p_notes text DEFAULT NULL) RETURNS void`

**Permission**: `shifts.manage`

**Pre-checks**:

- Shift exists, not soft-deleted, branch scope.
- `p_expected_updated_at` matches `shifts.updated_at` (`FOR UPDATE`); else `stale_shift`.
- New `p_shift_date >= org_today` (rejects moving shift to past).
- `p_end_time > p_start_time`; notes length valid.
- Overlap check for **all current assignees** against new date/times (exclude self).

**Behavior**: Updates shift fields; bumps `updated_at`. Audited as `shift.update` with prior/new values.

**Errors**: `stale_shift`, `shift_cancelled`, `shift_read_only_past_date`, `shift_invalid_time_range`, `shift_overlap`, `notes_too_long`, `permission_denied`, `shift_not_found`

---

## `modify_shift_assignments(p_shift_id uuid, p_expected_updated_at timestamptz, p_add_staff_ids uuid[] DEFAULT '{}', p_remove_staff_ids uuid[] DEFAULT '{}') RETURNS jsonb`

**Permission**: `shifts.manage`

**Pre-checks**:

- Shift exists, not soft-deleted, not past date (`shift_date >= org_today`), branch scope.
- Stale check on `p_expected_updated_at`.
- Removes: each id must be currently assigned; hard-delete assignment row.
- Adds: staff eligible; not already assigned; overlap check per added staff against shift date/times.
- At least one of add/remove arrays non-empty.

**Behavior**: Applies removes then adds in one transaction. Updates `shifts.updated_at`. Per-add/remove audit entries (`shift.assignment.add` / `shift.assignment.remove`). Returns:

```json
{
  "shift_id": "uuid",
  "status": "active|incomplete",
  "assignee_count": 2,
  "updated_at": "timestamptz"
}
```

**Errors**: `stale_shift`, `shift_cancelled`, `shift_read_only_past_date`, `staff_not_eligible`, `staff_already_assigned`, `shift_overlap`, `permission_denied`, `shift_not_found`

---

## `cancel_shift(p_shift_id uuid, p_expected_updated_at timestamptz) RETURNS void`

**Permission**: `shifts.manage`

**Pre-checks**:

- Shift exists, not already cancelled, branch scope.
- `shift_date >= org_today` (past shifts cannot be cancelled retroactively in V1-7).
- Stale check on `p_expected_updated_at`.

**Behavior**: Sets `deleted_at`, `deleted_by`. Shift excluded from operational queries and overlap checks. Assignments remain for audit context but parent shift is cancelled. Audited as `shift.cancel`.

**Errors**: `stale_shift`, `shift_cancelled`, `shift_read_only_past_date`, `permission_denied`, `shift_not_found`

---

## Conflict payload shape (`shift_overlap`)

When overlap validation fails, the error detail (JSON in exception message or structured return) includes:

```json
{
  "code": "shift_overlap",
  "conflicts": [
    {
      "staff_member_id": "uuid",
      "display_name": "Dr. Ahmed",
      "conflicting_shift_id": "uuid",
      "shift_date": "2026-06-10",
      "start_time": "09:00",
      "end_time": "17:00"
    }
  ]
}
```

Client MUST surface staff name and conflicting time range per FR-008/FR-021.
