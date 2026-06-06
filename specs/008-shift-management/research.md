# Research: Shift Management (V1-7)

Phase 0 research consolidates decisions for ambiguities and best practices identified during planning. All NEEDS CLARIFICATION items from the plan's Technical Context are resolved here; remaining open items would block Phase 1.

## Decisions

### D1. Shift status representation

- **Decision**: No `status` column on `shifts`. Operational status is **derived at read time**: `cancelled` when `deleted_at IS NOT NULL`; otherwise `incomplete` when assignment count = 0; `active` when assignment count ≥ 1.
- **Rationale**: Spec FR-002 explicitly states status is derived from assignment count with no separate status column in V1-7. Cancelled state maps to existing soft-delete columns.
- **Alternatives considered**: `shift_status` enum column (redundant with assignment count + soft delete); materialized status trigger (unnecessary complexity for two non-cancelled states).

### D2. Notes maximum length

- **Decision**: `notes` column `text` with application validation max **500** characters (trimmed); empty string stored as `NULL`.
- **Rationale**: Consistent with invoice item descriptions and visit note field limits elsewhere in the codebase; sufficient for coverage-planning annotations.
- **Alternatives considered**: 2000 chars (overkill for shift notes); unlimited `text` (no client guardrail).

### D3. Past-date mutation boundary

- **Decision**: Reuse the V1-4 appointment pattern: resolve organization timezone via `organizations.timezone` (fallback `UTC`), compute `v_today := (now() AT TIME ZONE v_tz)::date`, and reject mutations when `shift_date < v_today` with error `shift_read_only_past_date`. Past shifts remain readable in list/detail queries.
- **Rationale**: Clarifications and FR-006a mandate org-timezone evaluation; existing helper pattern in appointment RPCs is proven and consistent.
- **Alternatives considered**: UTC-only boundary (rejects valid local "today" near midnight); client-side date gate only (insufficient per NFR-004 defense in depth).

### D4. Overlap detection query

- **Decision**: Central helper `auth_internal.assert_no_staff_shift_overlap(p_branch_id, p_shift_date, p_start_time, p_end_time, p_staff_ids uuid[], p_exclude_shift_id uuid DEFAULT NULL)` runs per staff member:

  ```sql
  EXISTS (
    SELECT 1
    FROM public.shifts s
    JOIN public.shift_assignments sa ON sa.shift_id = s.id AND sa.deleted_at IS NULL
    WHERE s.branch_id = p_branch_id
      AND s.shift_date = p_shift_date
      AND s.deleted_at IS NULL
      AND (p_exclude_shift_id IS NULL OR s.id <> p_exclude_shift_id)
      AND sa.staff_member_id = v_staff_id
      AND s.start_time < p_end_time
      AND s.end_time > p_start_time
  )
  ```

  On conflict, raise `shift_overlap` with JSON payload listing `{ staff_member_id, display_name, conflicting_shift_id, start_time, end_time }` per conflict.
- **Rationale**: FR-007 mandates strict intersection; adjacent (touching) boundaries pass because `end = start` fails the strict inequality. Skipping overlap when `p_staff_ids` is empty supports incomplete shifts.
- **Alternatives considered**: Exclusion constraint on `(staff_member_id, branch_id, shift_date, tstzrange)` (harder to express time-only columns and exclusion messages); overlap only at INSERT trigger (cannot return rich conflict payload).

### D5. Assignment mutation RPC shape

- **Decision**: Single RPC `modify_shift_assignments(p_shift_id uuid, p_expected_updated_at timestamptz, p_add_staff_ids uuid[] DEFAULT '{}', p_remove_staff_ids uuid[] DEFAULT '{}')` performs atomic add/remove in one transaction. Overlap checks run only for `p_add_staff_ids`. Removing the last assignee is allowed and leaves shift `incomplete`.
- **Rationale**: Spec FR-010 requires add/remove on one shift without recreating it; atomic multi-change avoids partial state if one add fails overlap after a remove succeeded.
- **Alternatives considered**: Replace-all `p_staff_ids` array (loses granular audit per add/remove); separate add/remove RPCs (two round trips, race window).

### D6. Optimistic concurrency on shift edits

- **Decision**: `update_shift`, `modify_shift_assignments`, and `cancel_shift` accept `p_expected_updated_at timestamptz` compared to `shifts.updated_at` under `SELECT ... FOR UPDATE`; mismatch raises `stale_shift`.
- **Rationale**: Edge case in spec requires stale concurrent edits rejected with refresh prompt; consistent with V1-5 SOAP and V1-6 billing draft patterns.
- **Alternatives considered**: Last-write-wins (violates spec); version integer column (redundant with `updated_at`).

### D7. Calendar view implementation

- **Decision**: Reuse existing `calendar_view` package (already in `pubspec.yaml` for appointments). **Week view**: `WeekView<ShiftListItem>` with time-axis tiles. **Month view**: `MonthView<ShiftListItem>` with `cellBuilder` showing shift count + "Unassigned" badge; day tap opens a bottom sheet listing that day's shifts (popover/day-detail pattern per FR-018).
- **Rationale**: Package already vendored; `MonthView` exists in `calendar_view` 2.0.0; avoids bespoke month grid. Shift tiles are simpler than appointments (no slot conflict grid).
- **Alternatives considered**: Week-only V1 (rejected — spec requires both modes); custom `TableCalendar` (new dependency); day view as third mode (out of spec scope).

### D8. Shift times not constrained to branch working hours

- **Decision**: No call to `auth_internal` branch working-hours validators in shift RPCs. Only validate `end_time > start_time` on `shift_date` (both `time` type, same calendar date).
- **Rationale**: Clarifications Q5 and FR-006 explicitly unconstrain shift times from `working_schedule`.
- **Alternatives considered**: Warning-only UI hint (not requested); soft validation with override (adds complexity).

### D9. Direct table write denial

- **Decision**: `REVOKE INSERT, UPDATE, DELETE ON public.shifts, public.shift_assignments FROM authenticated, anon`. Grant `SELECT` under RLS. All mutations via public RPC wrappers delegating to `auth_internal` functions.
- **Rationale**: FR-014 and constitution Principle III; matches billing and appointment patterns.
- **Alternatives considered**: RLS-only INSERT deny (less discoverable than explicit REVOKE).

### D10. Eligible staff for assignment picker

- **Decision**: Reuse existing V1-2 staff list filtered client-side to active staff assigned to the shift's branch (`staff_branch_assignments`). Server re-validates eligibility on every mutation RPC. No new `list_eligible_shift_staff` RPC in V1-7.
- **Rationale**: Staff roster already available in settings domain; server is authoritative for eligibility anyway.
- **Alternatives considered**: Dedicated RPC returning eligible staff (extra surface area for same data).

### D11. Cross-branch overlap scope

- **Decision**: V1-7 overlap checks are **same branch only**. No warning or block when a staff member has overlapping shifts at another branch.
- **Rationale**: Spec assumptions and edge cases explicitly defer cross-branch blocking.
- **Alternatives considered**: Advisory UI warning (out of scope).

## Open Questions

None. All ambiguities surfaced during `/speckit-clarify` are answered in `spec.md` Clarifications and integrated above.

## References

- Spec: `specs/008-shift-management/spec.md`
- Constitution: `.specify/memory/constitution.md`
- V1-4 calendar + timezone patterns: `specs/005-appointment-management`
- V1-2 staff/branch assignments: `specs/003-org-branch-management`
- V1-1 permission seed (`shifts.manage`): `specs/002-auth-rbac/data-model.md`
- Architecture: `docs/architecture/04-backend.md`, `05-database.md`, `07-frontend.md`, `09-security-rbac.md`
