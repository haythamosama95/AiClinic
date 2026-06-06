# Feature Specification: Shift Management

**Feature Branch**: `specs/008-shift-management`

**Created**: 2026-06-06

**Status**: Draft

**Input**: User description: "Read V1-7 from docs/architecture/12-roadmap-phases.md and according to the best practices of speckit, create the eighth spec. This spec should be on the current branch."

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

This feature delivers staff shift planning for a multi-branch clinic after authentication, organization administration, staff management, patient registration, appointment scheduling, visit documentation, and billing exist. Clinic administrators and owners need to schedule who is working at each branch on specific dates and times, assign one or more staff members to each shift, and prevent double-booking the same person for overlapping shifts at the same branch.

The primary beneficiaries are **owners** and **administrators** with shift-management permission who plan reception and clinical coverage, and **all branch-assigned staff** who view the published schedule read-only to know who is on duty. Only users with `shifts.manage` may create, edit, assign, or cancel shifts in V1-7. Shift planning is separate from appointment scheduling: appointments track patient visits; shifts track staff availability and coverage.

V1-6 (`specs/007-billing`) closed the financial loop for completed visits. This feature introduces the shifts domain: branch-scoped, non-recurring shift records with date and time range, multi-staff assignments, overlap validation for assigned staff at the same branch, calendar views for planning, and clear conflict feedback when scheduling rules are violated. Recurring shift templates, cross-branch shift copying, time-clock/punch-in, payroll integration, workflow automation on assignment, and AI-assisted shift creation remain out of scope for V1-7.

## Clarifications

### Session 2026-06-06

- Q: Who can VIEW shift calendar/data vs. who can mutate shifts? → A: **Read-only for all branch-assigned staff; mutations require `shifts.manage`.** Any authenticated staff member assigned to the active branch may open the shift calendar and view shift details; create, update, assignment changes, and cancel remain gated by `shifts.manage` (owner and administrator by default).
- Q: Do adjacent shifts (one ends when another starts, e.g. 09:00–17:00 and 17:00–21:00) count as overlap? → A: **No — adjacent shifts are allowed.** Touching boundaries (`end_time` of one shift equals `start_time` of another) are **not** treated as overlap; only strict time-range intersection is blocked.
- Q: Can managers create, edit, or cancel shifts for past dates? → A: **Mutations only for today and future; past shifts are read-only.** Create, update, assignment changes, and cancel are allowed only when `shift_date` is today or a future date (evaluated in the organization's configured timezone). Past shifts remain visible on the calendar but cannot be mutated.
- Q: Must at least one staff member be assigned when a shift is created? → A: **Optional at create — empty shifts allowed; at least one assignee required for active (complete) status.** A shift may be saved without staff (incomplete/unassigned); it becomes **active** once at least one eligible staff member is assigned. Removing all assignees returns the shift to **incomplete**.
- Q: Should shift times be constrained to branch working hours? → A: **Unconstrained — any valid start/end on the shift date is allowed.** Shift times are not validated against the branch `working_schedule`; shifts represent staff coverage planning, not patient appointment slots.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a Shift (Priority: P1)

As an owner or administrator with shift-management permission, I can create a shift at my active branch by choosing a date, start and end time, optional notes, and optionally staff members so the clinic has a recorded coverage block that can be staffed immediately or assigned later.

**Why this priority**: Creating shifts is the foundational write operation; without it, the calendar and assignment flows have no data.

**Independent Test**: Can be fully tested by signing in with `shifts.manage`, creating a shift for a future date without staff (incomplete), verifying it appears as unassigned on the calendar, then assigning staff and confirming it transitions to active with assignee names shown.

**Acceptance Scenarios**:

1. **Given** a signed-in user with `shifts.manage` and an active branch, **When** they submit a valid shift (date, start time before end time) with zero or more eligible staff assignments, **Then** a shift is created scoped to the active branch; if staff were selected they are assigned and the shift is **active**, otherwise the shift is **incomplete** (unassigned) and success is confirmed.
2. **Given** a shift where an assigned staff member already has an overlapping shift at the same branch on the same date, **When** the user attempts to create or save the shift, **Then** creation is rejected with a clear conflict message naming the affected staff member(s) and conflicting shift time(s), and no duplicate assignment is stored.
3. **Given** a staff member who is inactive or not assigned to the branch, **When** the user attempts to assign them to a shift, **Then** assignment is rejected with a clear eligibility message.
4. **Given** end time equal to or before start time, **When** the user submits, **Then** validation errors are shown and no shift is created.
5. **Given** a user without `shifts.manage`, **When** they attempt to create a shift, **Then** the action is blocked at UI and server layers.
6. **Given** a user with `shifts.manage` at branch A, **When** they attempt to create a shift at branch B outside their JWT branch assignments, **Then** access is denied.
7. **Given** a staff member already assigned to a shift ending at 17:00, **When** a manager creates a second shift for the same staff on the same date starting at 17:00, **Then** creation succeeds because adjacent (touching) shifts are not overlap.
8. **Given** a `shift_date` before today (organization timezone), **When** a user with `shifts.manage` attempts to create a shift for that date, **Then** creation is rejected with a clear message that only today and future dates may be scheduled.
9. **Given** a branch `working_schedule` that ends at 18:00 on a weekday, **When** a manager creates a shift from 19:00–22:00 on that day, **Then** creation succeeds because shift times are not constrained to branch working hours.

---

### User Story 2 - View Branch Shift Calendar (Priority: P1)

As any staff member assigned to the active branch, I can view shifts for that branch on a weekly or monthly calendar so I can see who is scheduled and when coverage is planned.

**Why this priority**: Visibility is required immediately after creation; managers need calendar context for planning, and all branch staff need read-only access to know coverage.

**Independent Test**: Can be fully tested by signing in as a receptionist (no `shifts.manage`), opening the shift calendar, and verifying branch-scoped shifts appear read-only; then signing in as an administrator and confirming the same data with create/edit actions available.

**Acceptance Scenarios**:

1. **Given** a user assigned to the active branch (with or without `shifts.manage`), **When** they open the shift calendar, **Then** they see branch-scoped shifts for the selected week or month with shift time range and assigned staff names (or an **Unassigned** indicator for incomplete shifts).
2. **Given** week view, **When** the user navigates forward or backward, **Then** the calendar updates to the adjacent week while preserving the active branch context.
3. **Given** month view, **When** the user selects a day with multiple shifts, **Then** they can distinguish shifts (list, popover, or day detail per product policy) without leaving branch scope.
4. **Given** soft-deleted (cancelled) shifts, **When** the calendar is displayed, **Then** they are excluded from the default operational view.
5. **Given** a user without `shifts.manage`, **When** they open shift screens, **Then** they see the calendar and shift detail in **read-only** mode with create, edit, assign, and cancel actions hidden or disabled.
6. **Given** a user not assigned to the active branch, **When** they attempt to list shifts for that branch, **Then** access is denied.
7. **Given** no shifts exist in the selected period, **When** the calendar loads, **Then** an empty state is shown; users with `shifts.manage` see guidance to create the first shift, while read-only users see informational messaging only.

---

### User Story 3 - Manage Staff Assignments on an Existing Shift (Priority: P2)

As an owner or administrator, I can add or remove staff assignments on an existing shift so coverage can be adjusted without recreating the entire shift.

**Why this priority**: Staff availability changes frequently; assignment management is a daily operational need secondary to initial shift creation.

**Independent Test**: Can be fully tested by creating a shift with one staff member, adding a second eligible staff member, verifying both appear, removing one assignment, and confirming overlap rules still apply when adding staff who would conflict.

**Acceptance Scenarios**:

1. **Given** an existing shift and `shifts.manage`, **When** the user adds an eligible staff member not already assigned, **Then** the assignment is stored and reflected on the calendar and shift detail.
2. **Given** an existing shift with multiple assignees, **When** the user removes one staff assignment, **Then** the assignment is removed, the shift remains for remaining assignees, and the change is auditable.
3. **Given** adding a staff member would cause overlap with another shift at the same branch, **When** the user submits, **Then** the assignment is rejected with conflict details and no partial assignment is stored.
4. **Given** an attempt to remove the last remaining staff assignment, **When** the user confirms removal, **Then** the assignment is removed, the shift transitions to **incomplete** (unassigned), remains visible on the calendar with an Unassigned indicator, and does not participate in staff overlap checks until staff are assigned again.
5. **Given** a user without `shifts.manage`, **When** they attempt to change assignments, **Then** the action is blocked.

---

### User Story 4 - Edit or Cancel an Existing Shift (Priority: P2)

As an owner or administrator, I can update a shift's date, time range, or notes, or cancel a shift that is no longer needed, so the published schedule stays accurate.

**Why this priority**: Corrections are common after initial planning; cancel supports schedule changes without leaving orphaned records.

**Independent Test**: Can be fully tested by editing a shift's end time, verifying calendar update, attempting an edit that would cause staff overlap and verifying rejection, then soft-cancelling the shift and confirming it disappears from the default calendar.

**Acceptance Scenarios**:

1. **Given** an existing shift and `shifts.manage`, **When** the user updates date, start time, end time, or notes with valid values, **Then** the shift is updated and the calendar reflects the new values.
2. **Given** an edit that would cause any currently assigned staff member to overlap another shift at the same branch, **When** the user saves, **Then** the update is rejected with conflict details and the prior shift values remain unchanged.
3. **Given** an existing shift, **When** the user cancels (soft-deletes) it with confirmation, **Then** the shift is excluded from operational queries and calendar views, assignments are no longer active for overlap checks, and the cancellation is auditable.
4. **Given** a cancelled shift, **When** any user attempts to edit or reassign staff, **Then** the action is rejected with a clear message that the shift is no longer active.
5. **Given** a user without `shifts.manage`, **When** they attempt to edit or cancel, **Then** the action is blocked.
6. **Given** an existing shift with `shift_date` before today, **When** a user with `shifts.manage` attempts to edit, reassign, or cancel it, **Then** the mutation is rejected with a clear read-only message; the shift remains visible on the calendar for historical reference.

---

### Edge Cases

- What happens when AI is unavailable during a workflow that normally offers assistance? Shift management in V1-7 is fully manual; no AI dependency exists. Future AI shift assistance (V2) must fail back to these manual screens without blocking shift CRUD.
- How does the feature behave when a user lacks tenant-scoped or branch-scoped permission for the requested action? Users without branch assignment cannot view or mutate shifts for that branch. Branch-assigned users without `shifts.manage` may view the calendar and shift detail read-only but cannot mutate; server-side checks return permission errors on mutation attempts even if UI is bypassed.
- What happens when network, sync, or backend connectivity is degraded but clinic work still needs to continue safely? Calendar and forms show connection errors; no optimistic shift creation or assignment is treated as persisted until the server confirms success. Users may retry when connectivity returns.
- What happens when two managers edit the same shift concurrently? Stale updates are rejected with a refresh prompt based on the shift's last-updated timestamp; the user must reload and retry.
- What happens when a staff member is deactivated after being assigned to future shifts? Existing assignments remain visible on historical and future shifts until a manager removes them or cancels the shift; newly deactivated staff cannot be added to new or updated assignments.
- What happens when a staff member is removed from a branch assignment but still appears on old shifts? Existing shift assignments are not auto-removed; managers must update shifts manually. New assignments reject staff not currently assigned to the branch.
- Does overlap detection consider shifts at other branches for the same staff member? V1-7 enforces overlap only for the **same branch** per architecture. Cross-branch double-booking is not blocked in V1 but may be surfaced as a future enhancement.
- What happens when a shift spans midnight? V1-7 shifts are single-calendar-date records with start and end times on that date; end time must be after start time on the same date. Overnight shifts spanning two dates are out of scope.
- What happens when the active branch is switched while viewing the calendar? The calendar reloads for the newly selected branch; no cross-branch shift data is shown unless the user changes active branch context.
- What happens when two shifts for the same staff touch at a boundary (e.g., 09:00–17:00 and 17:00–21:00)? Both are allowed; overlap detection uses strict intersection only (`existing_start < new_end AND existing_end > new_start`), so equal boundary times do not conflict.
- What happens when a manager tries to correct a past shift? Past shifts (`shift_date` before today in organization timezone) are **read-only** for all users, including those with `shifts.manage`. Historical coverage remains visible but cannot be created, edited, assigned, or cancelled retroactively in V1-7.
- What happens when a manager edits a shift's date from a future date to a past date? The update is rejected; `shift_date` after save must remain today or future.
- What happens when a shift has no assigned staff? It remains on the calendar as **incomplete** (unassigned). Overlap validation runs only when staff are assigned or when updating times on a shift that currently has assignees. Managers may assign staff later or cancel the empty shift.
- What happens when a shift is scheduled outside branch working hours? Creation and update are **allowed**; shift times are not validated against the branch `working_schedule`. Appointment booking rules remain unchanged and continue to enforce branch hours independently.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST introduce shift records scoped to a branch with fields: shift date, start time, end time, and optional notes. Shifts are **non-recurring** in V1-7 (no recurrence templates or series).
- **FR-002**: The system MUST introduce shift assignment records linking one shift to zero or more staff members. A shift with **zero** assignees is **incomplete**; a shift with **one or more** assignees is **active**. Status is derived from assignment count (no separate status column required in V1-7).
- **FR-003**: The system MUST enforce permission key `shifts.manage` for all shift **mutations** (creation, update, assignment changes, and cancellation). Only roles seeded with this key in V1-1 (**owner** and **administrator** by default) may perform these actions unless an administrator explicitly grants the key to another role later.
- **FR-003a**: The system MUST allow **read-only** access to the shift calendar and shift detail for any authenticated staff member assigned to the shift's branch, without requiring `shifts.manage`. Read-only users MUST NOT see enabled create, edit, assign, or cancel controls.
- **FR-004**: The system MUST restrict shift visibility to the user's organization and to branches present in the caller's branch assignments. Cross-branch shift access outside assigned branches MUST be denied. Mutations additionally require `shifts.manage` per FR-003.
- **FR-005**: The system MUST allow assigning only **active** staff members who are currently assigned to the shift's branch via staff–branch assignment records from V1-2.
- **FR-006**: The system MUST reject shift creation or updates where `end_time` is not strictly after `start_time` on the given `shift_date`. Shift times MUST NOT be validated against branch `working_schedule` in V1-7.
- **FR-006a**: The system MUST restrict shift **mutations** (create, update, assignment changes, cancel) to shifts whose `shift_date` is **today or a future date**, evaluated in the organization's configured timezone. Past-date shifts MUST remain readable on the calendar but MUST reject all mutation attempts with a clear read-only error.
- **FR-007**: The system MUST detect overlapping shifts for the same staff member at the **same branch** on the same calendar date using **strict intersection**: ranges overlap when `existing_start < new_end AND existing_end > new_start`. **Adjacent (touching) shifts are allowed** — when one shift's `end_time` equals another's `start_time`, that is not overlap. Overlap checks MUST consider all non-cancelled shifts except the shift being edited.
- **FR-008**: The system MUST return clear conflict feedback identifying which staff member(s) conflict and the time range(s) of the conflicting shift(s) when overlap validation fails.
- **FR-009**: The system MUST implement shift creation with **optional** initial staff assignments through a secured server-side function that validates permission, branch scope, staff eligibility (when provided), time validity, and overlap rules (only when initial staff are provided) before persisting the shift and any assignments atomically.
- **FR-010**: The system MUST implement staff assignment changes on an existing shift through a secured server-side function that validates permission, branch scope, staff eligibility, duplicate-assignment prevention, and overlap rules on add. Removing the last assignee is **allowed** and transitions the shift to **incomplete**.
- **FR-011**: The system MUST implement shift update (date, time range, notes) through a secured server-side function with the same validation as creation, excluding cancelled shifts.
- **FR-012**: The system MUST implement shift cancellation via soft delete (standard audit and soft-delete columns). Cancelled shifts MUST be excluded from default list and calendar queries and MUST NOT participate in overlap detection.
- **FR-013**: The system MUST implement listing/query of shifts for a branch within a date range to power weekly and monthly calendar views, filterable by branch and period.
- **FR-014**: The system MUST apply branch-scoped row-level security on shift and shift-assignment data: any authenticated user assigned to a branch may read non-deleted shifts in that branch within their organization; direct client writes to domain tables MUST be denied with mutations routed through secured functions that additionally enforce `shifts.manage`.
- **FR-015**: The system MUST record shift create, update, cancel, and staff assignment add/remove events in the audit log with actor, action, target shift, and meaningful payload (including affected staff identifiers).
- **FR-016**: The system MUST create database indexes supporting shift lookups by branch and date per architecture conventions.
- **FR-017**: The system MUST include backend verification utilities that validate shift creation, overlap detection, branch isolation, permission enforcement, and assignment eligibility.
- **FR-018**: The system MUST provide a branch-specific shift calendar with **weekly** and **monthly** view modes showing shift time range, assigned staff summary, and a distinct **Unassigned** indicator for incomplete shifts.
- **FR-019**: The system MUST provide a shift creation form capturing date, start time, end time, notes, and **optional** multi-select staff assignment with inline validation feedback.
- **FR-020**: The system MUST provide staff assignment UI on shift detail supporting multi-select add and per-assignee remove with conflict error display when overlap validation fails.
- **FR-021**: The system MUST display shift conflict errors prominently when create, update, or assign actions are rejected due to overlap, including enough detail for the manager to choose an alternate time or staff member.
- **FR-022**: When opening the shift calendar or shift detail, the client MUST perform a **backend-first fetch** for latest persisted data before rendering actionable content; cached state MAY appear only as a transient loading placeholder and MUST be reconciled with the server response.
- **FR-023**: The system MUST derive requirements from the architecture documents listed under Required Architecture Docs and treat `specs/operations/shifts.spec.md` as an external reference until that shared operations spec is authored.
- **FR-024**: The system MUST NOT deliver recurring shift templates, shift swap/trade workflows between staff, time-clock or attendance tracking, payroll export, appointment auto-blocking based on shifts, workflow automation execution, or AI-assisted shift creation as part of V1-7.
- **FR-025**: The system MUST NOT alter appointment scheduling rules, visit documentation, billing, or patient management behavior except where navigation integrates shift management into the app shell at the active branch from prior features.

### Non-Functional Requirements

- **NFR-001**: Shift management screens must use plain language suitable for clinic administrators and owners.
- **NFR-002**: Calendar navigation and shift save operations must feel responsive under normal local clinic network conditions.
- **NFR-003**: A branch calendar with up to 200 shifts in a selected month must remain usable without unacceptable loading delay.
- **NFR-004**: Permission and scope checks must follow defense in depth: client gating, server function validation, and data-layer isolation.
- **NFR-005**: Save and assignment failures due to connectivity or validation errors must not leave the user believing the change was persisted.

### Key Entities

- **Shift**: A branch-specific, non-recurring scheduled work block on a single calendar date with start time, end time, and optional notes. Represents planned staff coverage, not patient appointments. **Incomplete** when unassigned; **active** when at least one staff member is assigned.
- **Shift Assignment**: Links a staff member to a shift. A shift has one or more assignments; overlap rules apply per assigned staff member at the branch.
- **Staff Member** (existing): Assignable resource; must be active and branch-assigned to appear in selection lists.
- **Branch** (existing): Scope boundary for shifts, calendar views, and overlap detection.

### Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch clinics where owners or administrators manually plan who works each day. Enterprise workforce management, union rules, multi-site float pools, and hospital-grade scheduling are out of scope.
- **Layer Placement**: Flutter provides calendar views, shift forms, staff multi-select, and conflict display. Supabase/PostgreSQL holds shifts and assignments as the source of truth, enforces overlap and eligibility in secured functions, applies branch-scoped RLS, and writes audit entries. The AI service has no role in V1-7; manual UI is the only path.
- **Data Integrity & Security**: Shifts are branch-scoped with standard audit and soft-delete columns. Mutations require `shifts.manage` and branch membership. Overlap validation runs in the secured function layer before commit. Assignments reference active staff with branch assignment. No cross-tenant reads or writes.
- **Failure Handling**: When the backend is unavailable, shift screens show errors and block unsaved changes from being treated as confirmed. When AI is added in V2, shift planning must continue to work through this manual module without AI dependency.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An administrator with `shifts.manage` can create a shift with staff assignments and see it on the branch calendar in under 2 minutes.
- **SC-002**: 100% of overlapping shift attempts for the same staff member at the same branch are rejected with a conflict message that identifies the staff member and conflicting time range.
- **SC-003**: Weekly and monthly calendar views load the selected period's branch shifts within 3 seconds under normal clinic network conditions for up to 200 shifts in range.
- **SC-004**: 95% of shift create, update, and assignment tasks complete successfully on the first attempt when staff eligibility and times are valid (excluding intentional conflict tests).
- **SC-005**: Zero cross-branch or cross-organization shift data leaks in backend verification scenarios for branch isolation and RLS.

## Assumptions

- Primary **editors** are **owners** and **administrators** on Windows desktop systems planning branch coverage. All branch-assigned staff may **view** the schedule read-only; self-serve shift edits remain limited to users with `shifts.manage` in V1-7.
- Shifts are **non-recurring**; each record stands alone. Recurring patterns may be added in a future version.
- Overlap detection scope is **same branch only**, matching architecture documentation. Cross-branch conflicts for staff assigned to multiple branches are not blocked in V1-7.
- Shifts are independent of appointment slots: booking appointments does not consult shift coverage in V1-7, and shift times are not constrained by branch `working_schedule` (unlike appointment slot validation).
- Staff eligibility for assignment follows V1-2 branch assignments; doctors, receptionists, and other roles may all be assigned to shifts if they are active branch members.
- Time values use the organization's configured timezone from V1-2 for display and date-boundary interpretation.
- `shifts.manage` remains seeded for owner and administrator only unless changed through the existing role-permission matrix from V1-2.
- Workflow automation trigger `shift.assigned` is defined in architecture but workflow rule execution is not implemented in V1-7.
- AI shift agent capabilities referenced in V2 are optional future enhancements and must not be required for any V1-7 acceptance scenario.

### Required Architecture Docs

- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Shifts`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

### External Spec Dependencies

- `specs/operations/shifts.spec.md` is referenced by the roadmap but is not yet present. This specification captures shift management expectations for V1-7 until that shared operations spec is authored.
- `specs/007-billing` is a sequential prerequisite in the V1 roadmap; billing behavior is unchanged by V1-7.
- `specs/003-org-branch-management` is a hard prerequisite: branches, staff members, staff–branch assignments, and active branch context must exist.
- `specs/002-auth-rbac` is a hard prerequisite: session management, `shifts.manage` permission seed, and branch-scoped JWT claims must exist.

### Data Model

- **Shift**: `branch_id`, `shift_date`, `start_time`, `end_time`, `notes` (optional), plus standard audit and soft-delete columns.
- **Shift Assignment**: `shift_id`, `staff_member_id`, plus standard audit columns. Unique active assignment per (shift, staff member) pair.

No new core tenancy tables are required beyond shifts, shift_assignments, their policies, indexes, and secured functions.

### RPC Functions

Required capabilities (exact names follow architecture and planning):

- **Create shift**: Validate `shifts.manage`, branch scope, time validity, staff eligibility, overlap rules; persist shift and initial assignments atomically; audit log.
- **Assign staff to shift**: Validate `shifts.manage`, shift active, staff eligibility, no duplicate assignment, overlap rules, minimum-one-assignee on removal; audit log.
- **Update shift**: Validate `shifts.manage`, shift active, time validity, overlap rules for all current assignees; audit log.
- **Cancel shift**: Validate `shifts.manage`, soft-delete shift; audit log.
- **List shifts**: Validate branch assignment (caller must be assigned to requested branch); return shifts with assignee summaries for calendar rendering. No `shifts.manage` required for list/read.

### RLS Policies

Policies on shift domain tables MUST enforce:

- Authenticated access only.
- Branch isolation: shift `branch_id` must be in the user's assigned branches within their organization.
- Exclusion of soft-deleted rows from normal operational queries.
- Direct INSERT/UPDATE/DELETE on domain tables denied; mutations via secured functions only.
- No cross-tenant reads or writes in verification scenarios.

### API Contracts

- Create shift (with optional initial staff list).
- Assign staff to shift (add/remove assignments).
- Update shift (date, time, notes).
- Cancel shift (soft delete).
- List shifts for branch and date range (weekly/monthly calendar).

Billing, appointment, visit, workflow automation, and AI APIs remain unchanged.

### UI States

- **Shift Calendar - Loading / Week view / Month view / Read-only (no shifts.manage) / Empty / Error / Permission Denied (not branch-assigned)**
- **Shift Create Form - Initial / Validating / Submitting / Success / Validation Error / Conflict Error / Permission Denied**
- **Shift Detail - Loading / Active (assigned) / Incomplete (unassigned) / Editing / Saving / Read-only (past date) / Read-only (no shifts.manage) / Conflict Error / Cancel confirm / Cancelled / Permission Denied**
- **Staff Assignment - Select staff / Add success / Remove confirm / Transition to incomplete (last assignee removed) / Conflict Error**

Navigation integrates with the app shell, active branch switcher from V1-2, and permission gates from V1-1.

### Validation Rules

- `shift_date` is required and must be a valid calendar date. On create and on update, `shift_date` MUST be today or a future date (organization timezone). Past dates are rejected for mutations.
- `start_time` and `end_time` are required; `end_time` must be strictly after `start_time` on `shift_date`. No branch working-hours validation applies to shift times.
- Staff assignment is **optional at create**. Zero assignees yields an **incomplete** shift; one or more assignees yields an **active** shift. Removing all assignees returns the shift to incomplete.
- Assigned staff must be active and assigned to the shift's branch.
- Overlap rejection when any assignee has another non-cancelled shift at the same branch on the same date with strictly intersecting time range (`existing_start < new_end AND existing_end > new_start`). Touching boundaries (`end_time` = `start_time`) are permitted.
- Notes optional with a reasonable maximum length defined in planning.
- Cancelled shifts are immutable for assignment and time edits.

### AI Hooks

This feature introduces no AI-assisted workflow. Shift planning remains fully manual. The V2 shift agent must not be required for any V1-7 acceptance scenario; when AI is added later, all AI-proposed shift changes require manager approval per product principles.

### Audit Requirements

- Shift create MUST write an audit log entry.
- Shift update MUST write an audit log entry with prior and new time/date/notes where applicable.
- Shift cancel MUST write an audit log entry.
- Staff assignment add and remove MUST write audit log entries naming shift and staff member.
- Routine calendar reads are not individually audited unless architecture mandates access logging later.

### Acceptance Criteria

1. User with `shifts.manage` can create a shift with or without initial staff; ineligible staff and invalid times are rejected; shifts without staff appear as incomplete/unassigned.
2. Strictly overlapping shifts for the same staff at the same branch are rejected on create, update, and assignment with identifiable conflict feedback; adjacent (touching) shifts are accepted.
3. Weekly and monthly calendar views show branch-scoped shifts (active and incomplete) for the selected period, with incomplete shifts marked Unassigned.
4. User can add and remove staff assignments on a shift; removing the last assignee transitions the shift to incomplete rather than being blocked.
5. User can update shift date, time, and notes on an active shift; cancelled shifts cannot be edited.
6. User can cancel a shift; cancelled shifts disappear from default calendar and no longer affect overlap checks.
7. Branch-assigned user without `shifts.manage` can view calendar and shift detail read-only but cannot mutate at UI or server layers.
8. Cross-branch and cross-organization access attempts are denied in backend verification tests.
9. Backend-first fetch is used before rendering actionable shift calendar and detail content.
10. No recurring templates, time-clock, payroll, workflow automation, or AI shift features are introduced in V1-7.
11. Shift mutations are rejected for past `shift_date`; past shifts remain viewable read-only on the calendar.
12. Shifts may be scheduled outside branch working hours; no working-schedule validation is applied to shift create or update.
