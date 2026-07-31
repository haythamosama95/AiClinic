# Data Model: Shift Management (V1-7)

Introduces shift domain tables, indexes, RLS, helpers, and secured RPCs. Builds on V1-1 auth (`shifts.manage` seed), V1-2 org/branch/staff assignments, V1-4 appointments (timezone helper pattern), V1-5 visits, V1-6 billing (unchanged).

## Migration: `20260606180000_shift_management.sql`

### TABLE: `shifts`

| Column            | Type                    | Notes                                                                              |
| ----------------- | ----------------------- | ---------------------------------------------------------------------------------- |
| `id`              | uuid PK                 | `gen_random_uuid()`                                                                |
| `organization_id` | uuid FK → organizations | Denormalized from branch for org-scoped audit consistency                          |
| `branch_id`       | uuid FK → branches      | Immutable after create                                                             |
| `shift_date`      | date NOT NULL           | Single calendar date; no overnight span (FR-001)                                   |
| `start_time`      | time NOT NULL           | Local org-timezone interpretation with `shift_date`                                |
| `end_time`        | time NOT NULL           | Must be strictly after `start_time` on same date (FR-006)                          |
| `notes`           | text                    | Optional; max 500 chars validated in RPC; empty → `NULL`                           |
| audit columns     | standard                | `created_at`, `created_by`, `updated_at`, `updated_by`, `deleted_at`, `deleted_by` |

**Constraints / Indexes**:

- `CHECK (end_time > start_time)`
- `CHECK (notes IS NULL OR length(trim(notes)) <= 500)`
- Index `(branch_id, shift_date)` — calendar range queries (FR-016)
- Index `(branch_id, shift_date, start_time)` — overlap scans
- Partial index `(branch_id, shift_date) WHERE deleted_at IS NULL` — operational calendar

**Derived status** (not stored):

| Condition                | Status       |
| ------------------------ | ------------ |
| `deleted_at IS NOT NULL` | `cancelled`  |
| assignment count = 0     | `incomplete` |
| assignment count ≥ 1     | `active`     |

### TABLE: `shift_assignments`

| Column            | Type                    | Notes                                                                                                                                                                      |
| ----------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`              | uuid PK                 |                                                                                                                                                                            |
| `shift_id`        | uuid FK → shifts        |                                                                                                                                                                            |
| `staff_member_id` | uuid FK → staff_members |                                                                                                                                                                            |
| audit columns     | standard                | Soft delete on assignment remove not used in V1-7 — rows are hard-deleted on remove to keep assignment count accurate; shift soft-delete cascades logically via cancel RPC |

**Constraints / Indexes**:

- `UNIQUE (shift_id, staff_member_id)` — no duplicate active assignment per pair (FR-002)
- Index `(staff_member_id, shift_id)` — overlap helper joins
- Index `(shift_id)` — detail fetch

**Note on assignment removal**: V1-7 removes assignment rows with `DELETE` (not soft-delete) because assignments are join facts, not independently audited entities beyond the audit log entry. Shift cancellation soft-deletes the parent shift only.

### RLS Policies

**`shifts`**:

- `SELECT`: authenticated AND `branch_id = ANY(jwt branch_ids)` AND `organization_id = jwt org` AND operational queries filter `deleted_at IS NULL` in RPC/SQL (RLS may allow SELECT of deleted for audit tooling; list RPCs exclude cancelled)
- `INSERT/UPDATE/DELETE`: denied to `authenticated` (mutations via RPC only)

**`shift_assignments`**:

- `SELECT`: authenticated AND parent shift's `branch_id` ∈ JWT `branch_ids`
- `INSERT/UPDATE/DELETE`: denied to `authenticated`

### GRANTs

```sql
REVOKE INSERT, UPDATE, DELETE ON public.shifts, public.shift_assignments FROM PUBLIC, authenticated, anon;
GRANT SELECT ON public.shifts, public.shift_assignments TO authenticated;
```

### Helpers (`auth_internal` schema)

| Helper                                  | Purpose                                                             |
| --------------------------------------- | ------------------------------------------------------------------- |
| `get_org_today(p_organization_id)`      | Returns `date` in org timezone (reuse or mirror appointment helper) |
| `assert_shift_branch_scope(p_shift_id)` | Shift exists, not deleted, branch ∈ JWT                             |
| `assert_shifts_manage()`                | Caller has `shifts.manage` permission key                           |
| `assert_shift_mutable(p_shift_date)`    | `shift_date >= get_org_today(org)`                                  |
| `assert_shift_staff_eligible(...)`      | Staff active + assigned to shift branch                             |
| `assert_no_staff_shift_overlap(...)`    | Strict intersection overlap per staff (D4)                          |
| `shift_assignee_count(p_shift_id)`      | Count assignments for derived status                                |

### RPC Functions (public wrappers)

| RPC                        | Permission / Scope                              | Notes                                      |
| -------------------------- | ----------------------------------------------- | ------------------------------------------ |
| `create_shift`             | `shifts.manage` + branch scope                  | Optional initial staff; atomic assignments |
| `update_shift`             | `shifts.manage` + branch scope                  | Date/time/notes; stale check               |
| `modify_shift_assignments` | `shifts.manage` + branch scope                  | Add/remove arrays; overlap on add          |
| `cancel_shift`             | `shifts.manage` + branch scope                  | Soft-delete shift                          |
| `list_shifts`              | branch assignment (no `shifts.manage` required) | Date range + assignee summaries            |
| `get_shift_detail`         | branch assignment                               | Full shift + assignments                   |

### Audit Actions

| Action                    | Trigger                          | Payload highlights                                       |
| ------------------------- | -------------------------------- | -------------------------------------------------------- |
| `shift.create`            | `create_shift`                   | branch, date, times, notes, initial staff ids            |
| `shift.update`            | `update_shift`                   | prior/new date, times, notes                             |
| `shift.cancel`            | `cancel_shift`                   | shift id, date, times                                    |
| `shift.assignment.add`    | `modify_shift_assignments` (add) | shift id, staff_member_id                                |
| `shift.assignment.remove` | `modify_shift_assignments` (rem) | shift id, staff_member_id; note if last assignee removed |

Routine calendar reads are not individually audited (per spec Audit Requirements).

### Failure Modes Reference

All RPC errors use `SQLSTATE 'P0001'` with stable message codes:

| Code                        | When raised                                                           |
| --------------------------- | --------------------------------------------------------------------- |
| `permission_denied`         | Missing `shifts.manage` on mutation or branch not in JWT              |
| `shift_not_found`           | Unknown id or cross-branch access masqueraded as not found            |
| `shift_cancelled`           | Mutation on soft-deleted shift                                        |
| `shift_read_only_past_date` | `shift_date` before org today on create/update/assign/cancel          |
| `shift_invalid_time_range`  | `end_time <= start_time`                                              |
| `shift_overlap`             | Strict intersection conflict; payload lists staff + conflicting times |
| `staff_not_eligible`        | Inactive or not branch-assigned staff                                 |
| `staff_already_assigned`    | Duplicate assignment on same shift                                    |
| `stale_shift`               | `p_expected_updated_at` ≠ `shifts.updated_at`                         |
| `notes_too_long`            | Notes exceed 500 chars                                                |
| `invalid_shift_date`        | Null or malformed date on create/update                               |

## Flutter Domain Types

| Type                   | Fields (summary)                                                                             |
| ---------------------- | -------------------------------------------------------------------------------------------- |
| `ShiftListItem`        | id, branchId, shiftDate, startTime, endTime, status (derived), assigneeNames[], isUnassigned |
| `ShiftDetail`          | ShiftListItem fields + notes, updatedAt, assignments[] (id, staffMemberId, displayName)      |
| `ShiftOverlapConflict` | staffMemberId, displayName, conflictingShiftId, startTime, endTime                           |
| `ShiftCalendarMode`    | week, month                                                                                  |

## Test Utilities

| File                               | Coverage                                                                                                                     |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `shift_management_crud.sql`        | Create incomplete/active, overlap reject/accept adjacent, assign, remove last → incomplete, update, cancel, past-date reject |
| `shift_management_rls.sql`         | Cross-branch/org denial; receptionist read-only; owner mutate                                                                |
| `shift_management_concurrency.sql` | Concurrent `update_shift` stale rejection                                                                                    |
| `run_shift_management_tests.sh`    | Orchestrator                                                                                                                 |
