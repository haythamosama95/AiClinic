# Feature Specification: Appointment Management

**Feature Branch**: `specs/005-appointment-management`

**Created**: 2026-05-23

**Status**: Draft

**Input**: User description: "Read V1-4 from @docs/architecture/12-roadmap-phases.md and according to the best practices of speckit, create the fifth spec"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

This feature delivers appointment scheduling and front-desk queue operations for a multi-branch clinic after authentication, organization administration, staff management, and patient registration exist. Reception staff need to book planned appointments, register walk-ins, manage the day's queue, and advance appointment status through check-in and completion. Doctors need a reliable view of their schedule. The clinic must prevent double-booking the same doctor at the same branch.

The primary beneficiaries are receptionists who book and check in patients, doctors who follow their daily schedule and progress visits, and administrators who oversee branch operations. Visit documentation (V1-5), billing (V1-6), and shift planning (V1-7) depend on appointments being created and completed with correct status and timing.

V1-3 (`specs/004-patient-management`) delivered the patient registry. This feature introduces the `appointments` domain: branch-scoped records linked to patients and doctors, conflict-safe booking, status lifecycle management, calendar and queue views, and optional live queue updates when connectivity allows.

## Clarifications

### Session 2026-05-23

- Q: Which permission keys gate appointment actions? → A: Use seeded keys `appointments.create` and `appointments.cancel` from V1-1; viewing schedules and queues requires at least one of these grants (or owner/administrator full access). Lab staff without these keys cannot access appointment screens.
- Q: Who may advance appointment status (check-in, in progress, complete)? → A: Any user with `appointments.create` at the branch may perform all forward transitions (`scheduled` → `checked_in` → `in_progress` → `completed`), including check-in, start, and complete, regardless of whether they are the assigned doctor; `appointments.cancel` gates cancel and no-show. Doctor assignment affects schedule display and booking only, not who may advance status in V1-4.
- Q: How are scheduling conflicts handled? → A: The system rejects create or reschedule that would overlap another non-cancelled, non–no-show appointment for the same doctor at the same branch; the user sees which slot conflicts and can choose another time.
- Q: What is the difference between planned and walk-in? → A: `planned` appointments are booked at an explicit `start_time`/`end_time` chosen by staff (confirmed slots). `walk_in` appointments are registered for today; the system assigns `start_time`/`end_time` into a slot that does not overlap confirmed (non–cancelled, non–no-show) appointments for the same doctor at the branch—walk-ins fill gaps, not confirmed slots.
- Q: Can appointments reference patients from other branches? → A: Yes, within the same organization: any non-archived patient in the organization may be selected when booking at the active branch; the appointment's `branch_id` is always the active branch at create time.
- Q: Are visits created in this feature? → A: No. Completing an appointment records `completed` status only; visit creation from appointments is V1-5.
- Q: What happens when realtime updates are unavailable? → A: Queue and calendar views fall back to manual refresh; core booking and status changes remain available through standard requests.
- Q: Is rescheduling existing appointments in V1-4 scope? → A: Yes — dedicated reschedule updates `start_time` and `end_time` on an existing appointment with the same conflict detection as create; only while status is `scheduled` (not after check-in or terminal states).
- Q: What is the initial status for walk-in vs planned appointments? → A: **Planned** (`type` `planned`): created as `scheduled`, then happy path is `scheduled` → `checked_in` → `in_progress` → `completed`. **Walk-in** (`type` `walk_in`): skips `scheduled` — created directly as `checked_in` (patient is already at the desk); then `checked_in` → `in_progress` → `completed`. Walk-ins never use `scheduled` as an entry status.
- Q: Who may set `in_progress` and `completed`? → A: Any user with `appointments.create` for the branch (e.g. receptionist or doctor), not restricted to the assigned doctor.
- Q: How should today's queue be sorted? → A: **`start_time` ascending** only. Walk-ins and planned appointments share one ordered queue by assigned/ booked time; `queue_number` is not used for V1-4 ordering.
- Q: How are walk-ins placed in the queue relative to confirmed appointments? → A: Confirmed planned appointments reserve their booked times. Walk-ins receive an auto-assigned `start_time` (and `end_time`) in a non-overlapping slot on the same day for the selected doctor at the branch; the queue order follows `start_time` because walk-ins are timed like other appointments.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Book a Planned Appointment (Priority: P1)

As reception staff (or another role with appointment-create permission), I can book a planned appointment for a patient with a selected doctor, date, and time at my active branch so the clinic has a scheduled slot before the patient arrives.

**Why this priority**: Planned booking is the core scheduling workflow for multi-branch clinics.

**Independent Test**: Can be fully tested by signing in with create permission, selecting patient and doctor, choosing a non-conflicting slot, and confirming the appointment appears on the calendar and in today's queue when applicable.

**Acceptance Scenarios**:

1. **Given** a signed-in user with `appointments.create` and an active branch, **When** they submit a valid booking for a non-archived patient and available doctor/time, **Then** an appointment is created with type `planned`, status `scheduled`, `branch_id` equal to the active branch, and success is confirmed.
2. **Given** a time range that overlaps an existing non-cancelled appointment for the same doctor at the branch, **When** the user attempts to book, **Then** creation is rejected with a clear conflict message and no duplicate slot is stored.
3. **Given** required selections are missing (patient, doctor, start/end time), **When** the user submits, **Then** field-level errors are shown and no appointment is created.
4. **Given** a user without `appointments.create`, **When** they attempt to book, **Then** the action is blocked at UI and server layers.
5. **Given** an archived patient, **When** the user attempts to book, **Then** the patient cannot be selected or creation is rejected with a clear message.

---

### User Story 2 - Register a Walk-In (Priority: P1)

As reception staff, I can register a walk-in appointment for a patient who arrives without a prior booking so they enter today's queue at the active branch.

**Why this priority**: Walk-ins are common in small and mid-size clinics and must share the same queue and status flows as planned appointments.

**Independent Test**: Can be fully tested by creating a walk-in for today at the active branch and confirming it appears in the queue with appropriate type and ordering.

**Acceptance Scenarios**:

1. **Given** `appointments.create` and an active branch, **When** the user completes walk-in registration for a patient and doctor, **Then** an appointment is created with type `walk_in`, status `checked_in` (not `scheduled`), and appears in today's queue.
2. **Given** a walk-in appointment, **When** it is created, **Then** no separate check-in action is required because the patient is already checked in at registration.
3. **Given** confirmed planned appointments occupying slots for a doctor today, **When** a walk-in is registered, **Then** the system assigns `start_time`/`end_time` to the next available non-overlapping slot (same conflict rules as planned booking) and the walk-in appears in queue order by that `start_time`.
4. **Given** no available slot remains for the doctor today under clinic slot-duration rules, **When** walk-in registration is attempted, **Then** creation is rejected with a clear no-slots-available message.
5. **Given** a walk-in was assigned a slot, **When** the user views today's queue, **Then** the walk-in appears interleaved with planned appointments by `start_time`, not in a separate numbering scheme.

---

### User Story 3 - View Calendar and Doctor Schedule (Priority: P1)

As staff with appointment access, I can view branch appointments on a daily or weekly calendar and see a doctor-specific schedule so I can plan the day and answer patient inquiries.

**Why this priority**: Visibility is required before and after booking; doctors rely on schedule views.

**Independent Test**: Can be fully tested by seeding appointments across days and doctors, switching calendar range, and filtering to one doctor.

**Acceptance Scenarios**:

1. **Given** a user with `appointments.create` or `appointments.cancel` at an active branch, **When** they open the appointment calendar, **Then** they see branch-scoped appointments for the selected day or week with patient name, doctor, time, status, and type indicators.
2. **Given** doctor schedule view, **When** a doctor (or staff filtering by doctor) opens the schedule, **Then** only that doctor's appointments at the active branch for the selected period are shown.
3. **Given** cancelled or no-show appointments, **When** calendar is displayed, **Then** they are visually distinct or filterable per product policy but do not block new bookings in those slots.
4. **Given** a user without appointment permissions, **When** they open scheduling screens, **Then** access is denied with clear messaging.

---

### User Story 4 - Manage Today's Queue (Priority: P1)

As reception staff, I can view today's appointment queue for the active branch with timely updates when connectivity allows so I can call patients and manage flow at the front desk.

**Why this priority**: The queue is the primary receptionist operational surface named in architecture.

**Independent Test**: Can be fully tested by seeding today's appointments, opening the queue, changing status from another session, and observing update via live subscription or manual refresh fallback.

**Acceptance Scenarios**:

1. **Given** today's appointments at the active branch, **When** the user opens the queue view, **Then** appointments are sorted by `start_time` ascending (planned and walk-in interleaved), with patient, doctor, status, and type shown.
2. **Given** live updates are supported and connected, **When** another user changes an appointment in the queue, **Then** the view updates without a full page reload.
3. **Given** live updates are unavailable, **When** the user refreshes, **Then** the queue reflects current server state.
4. **Given** appointments on other days or branches, **When** the user views today's queue, **Then** those records are excluded.

---

### User Story 5 - Check In and Progress Appointment Status (Priority: P1)

As reception or clinical staff with appropriate permissions, I can move appointments through check-in, in progress, and completed so the clinic records what stage each patient is in.

**Why this priority**: Status progression bridges scheduling to future visit documentation.

**Independent Test**: Can be fully tested by stepping one appointment through `scheduled` → `checked_in` → `in_progress` → `completed` and verifying invalid skips are rejected.

**Acceptance Scenarios**:

1. **Given** a `scheduled` **planned** appointment and a user with `appointments.create`, **When** they check in the patient, **Then** status becomes `checked_in` and audit records the change.
1b. **Given** a `walk_in` appointment created at registration, **When** it appears in the queue, **Then** it is already `checked_in` and the check-in action is not offered (only forward clinical transitions apply).
2. **Given** a `checked_in` appointment and a user with `appointments.create`, **When** they start the visit segment, **Then** status becomes `in_progress` (assigned doctor not required).
3. **Given** an `in_progress` appointment and a user with `appointments.create`, **When** they complete the appointment, **Then** status becomes `completed` (assigned doctor not required).
4. **Given** an invalid transition (e.g., `scheduled` directly to `completed` if not allowed), **When** the user attempts the change, **Then** the server rejects with a clear message.
5. **Given** a receptionist with `appointments.create` who is not the assigned doctor, **When** they check in, start, or complete another doctor's appointment at the branch, **Then** the action succeeds if the transition is valid.
6. **Given** a user without `appointments.create`, **When** they attempt any forward status change, **Then** the action is blocked.

---

### User Story 6 - Reschedule a Planned Appointment (Priority: P2)

As reception staff with appointment-create permission, I can change the date and time of a `scheduled` planned appointment so the patient can move to another slot without canceling and rebooking manually.

**Why this priority**: Rescheduling is common front-desk work; dedicated flow reduces errors versus cancel-plus-create.

**Independent Test**: Can be fully tested by rescheduling a `scheduled` appointment to a non-conflicting slot and verifying calendar, queue, and conflict rejection on overlap.

**Acceptance Scenarios**:

1. **Given** a `scheduled` appointment and `appointments.create`, **When** the user selects a new non-conflicting `start_time`/`end_time`, **Then** the appointment times update, success is confirmed, and views reflect the new slot.
2. **Given** the new time overlaps another non-cancelled, non–no-show appointment for the same doctor at the branch, **When** the user attempts reschedule, **Then** the update is rejected with conflict feedback and times remain unchanged.
3. **Given** an appointment in `checked_in`, `in_progress`, `completed`, `cancelled`, or `no_show`, **When** the user attempts reschedule, **Then** the action is rejected with a clear message.
4. **Given** a user without `appointments.create`, **When** they attempt reschedule, **Then** the action is blocked.

---

### User Story 7 - Cancel or Mark No-Show (Priority: P2)

As staff with cancel permission, I can cancel an appointment or mark it as no-show with appropriate confirmation so slots are freed and the schedule stays accurate.

**Why this priority**: Cancellations are frequent but secondary to happy-path booking and check-in.

**Independent Test**: Can be fully tested by cancelling a scheduled appointment and marking another as no-show; verify calendar and queue updates.

**Acceptance Scenarios**:

1. **Given** a cancellable status (`scheduled` or `checked_in` per policy) and `appointments.cancel`, **When** the user confirms cancellation with optional reason, **Then** status becomes `cancelled` and the slot can be rebooked.
2. **Given** a patient who did not arrive, **When** staff with `appointments.cancel` marks no-show, **Then** status becomes `no_show`.
3. **Given** a `completed` appointment, **When** the user attempts cancel, **Then** the action is rejected.
4. **Given** a user without `appointments.cancel`, **When** they attempt cancel or no-show, **Then** the action is blocked.

---

### Edge Cases

- Booking across midnight or outside clinic hours: validation rejects or warns per branch settings defined in planning (default: end time after start time, same-day or future date rules for planned type).
- Doctor with no staff-doctor role mapping: booking rejected if selected provider is not a valid doctor at the branch.
- Patient from another branch in the organization: allowed; appointment remains at active branch.
- Archived patient: cannot book new appointments.
- Concurrent booking of the same slot: second transaction fails conflict check without corrupting data.
- Reschedule of the same appointment to an overlapping slot: rejected; concurrent reschedule and create for same doctor: second transaction fails conflict check.
- Status change while offline: user sees error; no false success; queue shows last known state until refresh.
- AI services are not part of this feature; AI unavailability must not block any appointment workflow.
- Completed appointments cannot be edited back to scheduled without an explicit out-of-scope admin correction path.
- Permission grant changes follow V1-2 rules: client cache updates on auth-context reload; server enforces current grants immediately.
- Realtime disconnect: banner or indicator with manual refresh; booking and status RPCs still work.
- Cancelled and no-show appointments excluded from conflict detection for the same doctor/time window.
- Visit creation is not triggered on complete in V1-4; downstream V1-5 owns visit linkage.
- Walk-in type must not be created with status `scheduled`; planned type must not skip `scheduled` on create unless rescheduled or transitioned through check-in.
- Walk-in registration when the doctor's day has no remaining gap: rejected with clear messaging.
- Multiple walk-ins for same doctor: each receives distinct non-overlapping assigned times via auto-slot logic.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST introduce an `appointments` store with fields aligned to architecture: `branch_id`, `patient_id`, `doctor_id`, `start_time`, `end_time`, `type` (`planned` or `walk_in`), `status`, optional `queue_number`, `notes`, plus standard audit columns.
- **FR-002**: The system MUST set `branch_id` from the signed-in user's active branch at create time; branch reassignment is out of scope for V1-4.
- **FR-003**: The system MUST enforce branch-scoped isolation for appointment reads and writes via data-layer policies limited to the user's assigned branches within their organization.
- **FR-004**: The system MUST enforce permission key `appointments.create` for booking, walk-in registration, and all forward status transitions (check-in, in progress, complete) at UI and server layers; users with this permission MAY perform these transitions on any appointment at their branch regardless of assigned `doctor_id`.
- **FR-005**: The system MUST enforce permission key `appointments.cancel` for cancellation and no-show at UI and server layers.
- **FR-006**: The system MUST allow users with either `appointments.create` or `appointments.cancel` to view calendar, queue, and doctor schedule data for branches they are assigned to; users with neither key MUST NOT access appointment operational screens.
- **FR-007**: The system MUST provide planned appointment booking with patient selection (organization patients, non-archived), doctor selection, time slot selection, optional notes, and client-side validation before server submission.
- **FR-008**: The system MUST provide walk-in registration flow sharing patient and doctor selection with type `walk_in`, initial status `checked_in` (never `scheduled`), for today at the active branch.
- **FR-008a**: The system MUST set initial status `scheduled` only for `planned` appointments; `walk_in` appointments MUST be created with status `checked_in`.
- **FR-008b**: The system MUST auto-assign `start_time` and `end_time` on walk-in create by placing the appointment in the next available slot for the selected doctor at the branch on the current day that does not overlap any confirmed appointment (any non–`cancelled`, non–`no_show` appointment for that doctor, including other walk-ins once assigned).
- **FR-008c**: Confirmed appointments are planned (`type` `planned`) bookings with reserved times; walk-ins MUST NOT displace or override confirmed slot times—only use gaps or free time.
- **FR-009**: The system MUST reject overlapping appointments for the same `doctor_id`, `branch_id`, and overlapping `start_time`/`end_time` when either appointment is not `cancelled` or `no_show`.
- **FR-010**: The system MUST expose conflict feedback on failed create and reschedule identifying the conflicting slot or appointment.
- **FR-010a**: The system MUST provide reschedule of `scheduled` appointments (update `start_time` and `end_time`) with the same overlap conflict rules as create, excluding the appointment being rescheduled from the conflict set.
- **FR-011**: The system MUST support appointment status values: `scheduled`, `checked_in`, `in_progress`, `completed`, `cancelled`, `no_show`.
- **FR-012**: The system MUST enforce valid status transitions server-side; invalid transitions MUST be rejected with actionable errors.
- **FR-013**: The system MUST provide daily and weekly calendar views of branch appointments with status and type visible.
- **FR-014**: The system MUST provide a doctor schedule view filtered to one doctor at the active branch for a selected period.
- **FR-015**: The system MUST provide today's queue view for the active branch sorted by `start_time` ascending only (planned and walk-in interleaved).
- **FR-015a**: The system MUST NOT use `queue_number` for queue ordering in V1-4; ordering is determined solely by `start_time`.
- **FR-016**: The system MUST support live queue updates when realtime connectivity is available, with manual refresh when it is not.
- **FR-017**: The system MUST implement appointment creation, reschedule, cancellation, and status updates through secured server-side functions with permission, branch, conflict, and transition validation—not unguarded direct client writes for protected operations.
- **FR-018**: The system MUST record appointment create, cancel, and status changes in the audit log with actor, action, target, and meaningful payload.
- **FR-019**: The system MUST create database indexes supporting `branch_id` with `doctor_id` and `start_time`, and `branch_id` with `status` and `start_time` per architecture.
- **FR-020**: The system MUST include backend verification utilities that validate conflict detection, status transitions, branch isolation, and blocked cross-organization access.
- **FR-021**: The system MUST derive requirements from the architecture documents listed under Required Architecture Docs and treat `specs/operations/appointments.spec.md` as an external reference until authored.
- **FR-022**: The system MUST NOT deliver visit, SOAP, billing, shift, workflow automation, or AI workflows as part of this feature.
- **FR-023**: The system MUST NOT create visit records when an appointment is marked completed (deferred to V1-5).
- **FR-024**: The system MUST NOT change patient, organization, branch, or staff management behavior except where appointment screens integrate with active branch, patient picker, and staff/doctor lists from prior features.

### Non-Functional Requirements

- **NFR-001**: Appointment screens must use plain language suitable for reception and clinical staff.
- **NFR-002**: Today's queue and day calendar must remain usable with at least 200 appointments per branch per day under normal local clinic network conditions.
- **NFR-003**: Conflict rejection must be returned within perceived interactive time under normal local conditions so staff can pick another slot immediately.
- **NFR-004**: Permission and scope checks must follow defense in depth: client gating, server function validation, and data-layer isolation.
- **NFR-005**: Save and status failures due to connectivity or validation errors must not leave the user believing the change was saved.

### Required Architecture Docs

- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Appointments`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Audit Trail`, permission keys for appointments
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

### External Spec Dependencies

- `specs/operations/appointments.spec.md` is referenced by the roadmap but is not yet present. This specification captures appointment management expectations for V1-4 until that shared operations spec is authored.
- `specs/004-patient-management` is a hard prerequisite: patient registry, search, and archival rules must exist.
- `specs/003-org-branch-management` and `specs/002-auth-rbac` are hard prerequisites: active branch, staff/doctor identities, permissions, and session management must exist.

### Data Model

- **Appointment**: Scheduled or walk-in encounter slot at a branch linking a patient and doctor with start/end time, status, and notes. Branch-scoped; organization scope derived via branch. `queue_number` may exist in schema but is not used for V1-4 queue ordering.
- **Confirmed appointment**: A planned booking with a reserved `start_time`/`end_time` that is not `cancelled` or `no_show`; occupies the doctor's schedule until terminal.
- **Patient** (existing): Linked subject of care; must be non-archived for booking.
- **Staff member / Doctor** (existing): `doctor_id` references clinical staff designated as doctors for the branch or organization per staff model from V1-2.
- **Branch** (existing): Operational location; all V1-4 appointment screens default to active branch context.

No new core tenancy tables are required beyond the `appointments` table and its policies, indexes, and functions.

### RPC Functions

Exact names follow architecture; required capabilities:

- **Create appointment**: Validate `appointments.create`, active branch, patient and doctor validity; for `planned`, accept staff-chosen time range and conflict rule; for `walk_in`, auto-assign next available slot today with conflict rule, set status `checked_in`; set type and initial status (`planned` → `scheduled`); audit log.
- **Cancel appointment**: Validate `appointments.cancel`, allowed current status, optional reason; set `cancelled`; audit log.
- **Update appointment status**: Validate permission (create for all forward transitions per transition table, cancel for cancel/no-show), branch scope, and valid transition only—do not require the actor to be the assigned doctor; audit log.
- **Reschedule appointment**: Validate `appointments.create`, status is `scheduled`, branch scope, new time range, conflict rule (exclude self); update times; audit log.

### Status Transition Rules

**Entry status by type**: `planned` → `scheduled` on create; `walk_in` → `checked_in` on create (walk-ins do not use `scheduled`).

| From          | Allowed to                            | Permission      |
| ------------- | ------------------------------------- | --------------- |
| `scheduled`   | `checked_in`, `cancelled`, `no_show`  | create / cancel |
| `checked_in`  | `in_progress`, `cancelled`, `no_show` | create / cancel |
| `in_progress` | `completed`                           | create          |
| `completed`   | (none)                                | —               |
| `cancelled`   | (none)                                | —               |
| `no_show`     | (none)                                | —               |

### RLS Policies

Policies on `appointments` MUST enforce:

- Authenticated access only.
- Branch isolation: `branch_id` must be in the user's JWT `branch_ids` within their organization.
- Exclusion of soft-deleted rows from normal operational queries.
- No cross-tenant reads or writes in verification scenarios.

### API Contracts

- Create appointment (planned and walk-in) with conflict detection.
- Reschedule appointment (`scheduled` only) with conflict detection.
- Cancel appointment with reason.
- Update appointment status with transition validation.
- List/query appointments for calendar, doctor schedule, and today's queue (branch-scoped, date filters).
- Optional realtime channel for queue changes at the active branch.

Visit, billing, and AI APIs remain out of scope.

### UI States

- **Calendar - Loading / Daily / Weekly / Empty / Error / Permission Denied**
- **Booking Form - Initial / Validation Error / Conflict Error / Submitting / Success / Permission Denied**
- **Reschedule Form - Initial / Validation Error / Conflict Error / Submitting / Success / Not allowed (wrong status) / Permission Denied**
- **Walk-In Form - Initial / Validation Error / Conflict Error / Submitting / Success / Permission Denied**
- **Today's Queue - Loading / Loaded / Live connected / Live degraded (manual refresh) / Empty / Error / Permission Denied**
- **Doctor Schedule - Loading / Loaded / Empty / Error / Permission Denied**
- **Status Actions - Available / Disabled by transition / Submitting / Error**

Navigation integrates with the main app shell, patient picker from patient management, and active branch from V1-2.

### Validation Rules

- Patient, doctor, `start_time`, and `end_time` are required for **planned** booking (staff-selected).
- Walk-in registration requires patient and doctor; `start_time` and `end_time` are assigned by the system unless planning adds optional manual override.
- `end_time` must be after `start_time`.
- Doctor must be eligible to practice at the branch (per staff/role data from V1-2).
- Patient must belong to the user's organization and not be archived.
- Conflict check runs on every create and reschedule.
- Reschedule is allowed only when status is `scheduled`; walk-in and checked-in-or-later appointments cannot be rescheduled in V1-4.
- Cancel and no-show require confirmation per product UX standards.
- Notes length must respect schema maximum.

### AI Hooks

This feature introduces no AI-assisted workflow. Scheduling remains fully manual. AI scheduling agents (V2) must not be required for any V1-4 acceptance scenario.

### Audit Requirements

- Appointment create and reschedule MUST write audit log entries.
- Appointment cancel and no-show MUST write audit log entries with reason when captured.
- Each status change MUST write an audit log entry with prior and new status.
- Routine calendar/queue reads are not individually audited unless architecture mandates access logging later.

### Acceptance Criteria

1. User with `appointments.create` can book a non-conflicting planned appointment at the active branch; it appears on calendar and today's queue when dated today.
2. User without `appointments.create` cannot book.
3. Overlapping booking for the same doctor at the same branch is rejected with conflict messaging.
4. Walk-in registration creates a `walk_in` appointment with status `checked_in`, auto-assigned `start_time` in a non-conflicting slot, visible in today's queue ordered by time (never `scheduled`).
5. User with queue access sees only today's appointments for the active branch, sorted by `start_time` ascending.
6. Valid status progression from `scheduled` through `completed` succeeds with audit entries.
7. Invalid status skip is rejected.
8. User with `appointments.cancel` can cancel and mark no-show; user without it cannot.
9. Doctor schedule shows only selected doctor's appointments at the branch.
10. Backend verification utilities demonstrate conflict detection, transition rules, and cross-organization denial.
11. User with `appointments.create` can reschedule a `scheduled` appointment to a non-conflicting slot; overlap and wrong-status attempts are rejected.
12. No visit, billing, shift, or AI workflow is required to pass this feature.

### Test Cases

1. Book planned appointment; verify calendar and queue.
2. Attempt overlapping second booking; verify rejection.
3. Register walk-in with confirmed slots on calendar; verify auto-assigned time in a gap, status `checked_in`, queue position by `start_time`, and type `walk_in`.
4. Check in, start, and complete as receptionist on another doctor's appointment; verify statuses and audit.
5. Cancel scheduled appointment; verify slot reusable.
6. Mark no-show; verify status and display rules.
7. Attempt booking without permission; verify denial.
8. Open queue as user at branch A; verify no branch B appointments.
9. Simulate realtime update on queue; verify UI updates or refresh fallback.
10. Doctor views own schedule filter; verify other doctors' appointments hidden in that view.
11. Book with patient registered at another branch in same org; verify success at active branch.
12. Reschedule `scheduled` appointment to new slot; verify conflict rejection and blocked reschedule after check-in.
13. Run backend verification utilities for conflict, transitions, reschedule, and cross-org denial.

### Implementation Constraints

- MUST build on completed `specs/002-auth-rbac`, `specs/003-org-branch-management`, and `specs/004-patient-management`.
- Domain validation and authorization source of truth for mutations MUST live in database functions and policies—not solely in client logic.
- MUST use architecture status and type enums; hard delete is not used for appointments.
- MUST NOT implement visit, billing, shift, or AI schemas or screens in this feature.
- Cloud-only deployment enhancements are out of scope unless already supported by the local deployment path from V1-0.

### Key Entities *(include if feature involves data)*

- **Appointment**: Branch-scoped scheduled or walk-in slot linking patient and doctor with lifecycle status.
- **Active Branch Context**: Session field from V1-2 used for all V1-4 operational views and create `branch_id`.
- **Patient** (existing): Subject of the appointment.
- **Doctor** (existing): Clinical staff member assigned to the appointment.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch clinics where reception books and checks in patients at the desk, doctors follow a daily schedule, and walk-ins share the same queue as planned arrivals. Hospital OR scheduling, telehealth, and resource scheduling beyond doctors are out of scope.
- **Layer Placement**: The desktop client owns calendar, booking and walk-in forms, queue presentation, doctor schedule filter, status action controls, conflict messaging, and permission-aware UI. The backend platform owns secured create, cancel, and status functions, optional realtime delivery, and audit writes. The database layer owns the `appointments` schema, branch isolation policies, conflict detection, indexes, and verification utilities. The AI layer remains absent.
- **Data Integrity & Security**: Mutations use audit conventions; row-level policies preserve branch isolation within the organization; permission keys gate operations; conflict rules prevent double-booking; defense in depth applies across UI, RPC, and policies.
- **Failure Handling**: Booking and status failures surface clear errors without false success; queue and calendar show last known good data with connectivity messaging when degraded; realtime loss falls back to manual refresh; AI unavailability does not affect appointments; subscription state does not block core scheduling workflows.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 95% of test runs, authorized users complete a planned booking and see confirmation within 20 seconds under normal local clinic network conditions.
- **SC-002**: In 100% of conflict test scenarios, overlapping bookings for the same doctor at the same branch are rejected.
- **SC-003**: In 100% of status transition test scenarios, only valid lifecycle changes succeed; invalid skips are rejected with clear errors.
- **SC-004**: In 100% of permission test scenarios, users without `appointments.create` cannot book or perform create-gated status changes, and users without `appointments.cancel` cannot cancel or mark no-show.
- **SC-005**: In 100% of queue test scenarios, today's queue for the active branch lists only same-day branch appointments sorted by `start_time` ascending, with walk-ins interleaved at their assigned times.
- **SC-006**: In 100% of backend verification scenarios, cross-organization appointment access is blocked.
- **SC-007**: In 100% of walk-in test scenarios, walk-in appointments appear in today's queue with type `walk_in`, status `checked_in` at creation, and distinguishable from `planned` appointments that start as `scheduled`.
- **SC-008**: When realtime is enabled in test environments, queue view reflects another user's status change within 5 seconds in at least 95% of trials; when disabled, manual refresh shows the change.

## Assumptions

- `specs/002-auth-rbac`, `specs/003-org-branch-management`, and `specs/004-patient-management` are implemented.
- Permission keys `appointments.create` and `appointments.cancel` are seeded per V1-1; viewing operational appointment UI requires at least one of these grants.
- Doctors are identified from staff records with the doctor role; planning aligns `doctor_id` with staff member identifiers used elsewhere.
- Today's queue sort order is `start_time` ascending only; walk-ins receive auto-assigned times in slots not occupied by confirmed (non–cancelled, non–no-show) appointments for the same doctor.
- Default walk-in slot duration and gap-finding algorithm are defined in implementation planning (e.g., fixed minutes per walk-in); must be consistent and testable.
- Walk-in appointments are always created as `checked_in`; only `planned` appointments use `scheduled` as the initial status.
- Reschedule is in scope for V1-4: dedicated update of `start_time`/`end_time` for `scheduled` appointments only, with conflict detection equivalent to create.
- `specs/operations/appointments.spec.md` will be authored later; this feature spec is authoritative for V1-4 until that shared spec exists.
- AI remains optional and non-blocking for all appointment flows.
