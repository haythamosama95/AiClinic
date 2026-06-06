# Quickstart: Shift Management (V1-7) Operator Verification

This walkthrough verifies end-to-end shift planning against a local Supabase + Flutter desktop build: create, calendar views, assignments, overlap rules, past-date read-only, read-only staff access, edit, cancel, and concurrency.

## Preconditions

- V1-0..V1-6 features are implemented and migrated.
- Local Supabase stack running; `20260606180000_shift_management.sql` applied; `run_shift_management_tests.sh` passes.
- An organization with configured timezone, at least two branches, one **administrator** (has `shifts.manage`), one **receptionist** (branch-assigned, no `shifts.manage`), and at least three active staff members assigned to the primary branch.

## Steps

### 1. Read-only calendar access (receptionist)

1. Log in as **receptionist** with active branch set to **Main**.
2. Open **Shifts** from the app shell.
3. **Expect**: weekly calendar loads (backend-first fetch); no Create/Edit/Cancel buttons visible.
4. Switch to **month** view and navigate to next month.
5. **Expect**: calendar updates; still read-only.

### 2. Create incomplete shift (administrator)

1. Log in as **administrator** on **Main** branch.
2. Open **Shifts** → **Create shift**.
3. Choose a date **7 days ahead**, time **19:00–22:00** (outside branch working hours if applicable).
4. Leave staff unassigned; add note "Evening coverage".
5. Submit.
6. **Expect**: success; shift appears on calendar with **Unassigned** indicator; status incomplete.

### 3. Assign staff → active

1. Open the new shift detail.
2. Add two eligible staff members.
3. **Expect**: both names on calendar tile; Unassigned badge gone; status active.

### 4. Adjacent shift allowed

1. Create another shift same date for one of the assigned staff: **17:00–19:00** (touching the 19:00 start of the evening shift).
2. **Expect**: creation succeeds (adjacent boundaries permitted).

### 5. Overlap rejected

1. Attempt to create a shift same date for the same staff: **18:00–20:00**.
2. **Expect**: rejection with `shift_overlap` naming the staff member and conflicting time range **19:00–22:00**.

### 6. Assignment overlap on existing shift

1. On the **17:00–19:00** shift, try adding a second staff member who already works **19:00–22:00** the same day.
2. **Expect**: rejection with conflict details; no partial assignment stored.

### 7. Remove last assignee → incomplete

1. On a shift with one assignee, remove that assignment.
2. **Expect**: shift remains on calendar as **Unassigned**; does not block other overlap checks until staff re-assigned.

### 8. Edit shift times

1. Edit the **19:00–22:00** shift end time to **21:00**.
2. **Expect**: calendar updates; no overlap if times remain valid.

### 9. Past-date read-only

1. Note a shift on a **past date** (or wait until a created shift ages to past).
2. As administrator, attempt to edit, reassign, or cancel it.
3. **Expect**: `shift_read_only_past_date`; shift still visible on calendar for history.

### 10. Cancel shift

1. Cancel a **future** shift with confirmation.
2. **Expect**: disappears from default calendar; no longer affects overlap checks.
3. Attempt to edit the cancelled shift via RPC.
4. **Expect**: `shift_cancelled`.

### 11. Cross-branch denial

1. As administrator assigned only to **Main**, call `list_shifts` for the **other** branch id.
2. **Expect**: `permission_denied`.

### 12. Concurrent edit (optional two-session test)

1. Open the same shift detail in two administrator sessions.
2. Save an edit in session A.
3. Save a different edit in session B without refreshing.
4. **Expect**: session B receives `stale_shift` with prompt to refresh.

## Backend test command

```bash
cd backend/tests && ./run_shift_management_tests.sh
```

## Acceptance mapping

| Quickstart step | Spec acceptance criteria    |
| --------------- | --------------------------- |
| 1               | FR-003a, AC #7              |
| 2–3             | US1, AC #1                  |
| 4–5             | US1 scenario 7–8, AC #2     |
| 6               | US3 scenario 3              |
| 7               | US3 scenario 4, AC #4       |
| 8               | US4 scenario 1, AC #5       |
| 9               | FR-006a, AC #11             |
| 10              | US4 scenario 3, AC #6       |
| 11              | FR-004, AC #8               |
| 12              | Edge case: concurrent edits |
