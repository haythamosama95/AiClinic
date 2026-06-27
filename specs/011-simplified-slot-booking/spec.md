# Feature Specification: Simplified Slot Booking

**Feature Branch**: `ui/011-simplified-slot-booking`

**Created**: 2026-06-27

**Status**: Draft

**Input**: User description: "For the simplified booking, it shall be as follows: Make a new settings for the default appointment duration. Shall have the same UI as the photo: Simplified calendar view with days only, with the current day selected and in middle. Blocks representing the appointments in the working hours. For appointments that are reserved, it shall have a lock on it. For appointments that are available, it can be selected. When selected, its color shall change. A bottom card representing the currently selected slot. This view shall be embedded as a second step in the booking appointment procedure. This feature shall not replace booking an appointment through the calendar."

**Design reference**: The simplified date-and-time picker follows the layout shown in the provided reference screenshot — horizontal day strip with the selected day centered, a grid of time blocks within branch working hours, locked styling for reserved blocks, highlighted styling for the selected block, and a persistent summary card below the picker showing the current selection.

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Business Context

Reception staff book most planned appointments by choosing a patient, doctor, date, and time. The existing calendar-based booking flow works well for power users but requires navigating a full calendar and manually picking start/end times. A simplified slot picker reduces cognitive load by showing only nearby days and discrete time blocks that match clinic working hours and appointment length.

This feature introduces a **simplified slot booking** experience as **step two** of the planned-appointment booking procedure (after patient and doctor are chosen in step one). Staff see a compact day selector, a grid of bookable time blocks sized by the clinic's default appointment duration, clear locked indicators for unavailable slots, and a summary of the currently selected slot before confirming the booking.

The feature also delivers a **clinic setting for default appointment duration** that administrators can configure. That duration defines how time blocks are generated in the simplified picker and pre-fills the appointment length for bookings created through this flow.

**Important boundary**: Calendar-based booking (selecting a slot directly from the appointment calendar) remains fully available and is not removed or redirected by this feature. Staff may use either path.

## Clarifications

### Session 2026-06-27

- Q: How should slot locking and availability be scoped when evaluating conflicts? → A: **Branch-wide** — each time block's availability is evaluated across all doctors at the active branch. Three block states apply: (1) **available** when the preferred (step-one) doctor is free; (2) **alternate doctors available** when the preferred doctor is not free but at least one other branch doctor is free — shown locked with distinct styling, and tapping prompts that other doctors are available; (3) **fully unavailable** when no branch doctor is free — shown locked with a different distinct styling and cannot be selected or prompted as alternates.
- Q: When staff tap an alternate-doctors block, what should the prompt allow? → A: **Offer doctor switch** — the prompt lists doctors available at that time and lets staff switch to one of them while keeping the same date/time; the slot then becomes selected and the summary card reflects the new doctor.
- Q: Can staff override the default appointment duration in the simplified two-step booking flow? → A: **Default only** — simplified booking always uses the configured default duration; no per-booking duration override. Staff who need a custom duration use calendar booking.
- Q: Where should staff start the simplified two-step booking flow? → A: **Calendar header button** — the existing "Book Appointment" button on the appointments calendar page opens the two-step simplified flow; tapping a calendar slot continues to use the existing booking sheet.
- Q: How far into the future may staff navigate in the simplified day strip? → A: **90 days ahead** — staff may navigate up to three months from today; dates beyond that limit are not selectable.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure Default Appointment Duration (Priority: P1)

As a clinic administrator (or another role with organization/branch settings permission), I can set the default appointment duration for my clinic so time blocks in simplified booking and new appointments use a consistent slot length.

**Why this priority**: Slot block size and booking defaults depend on this setting; without it the simplified picker cannot generate meaningful blocks.

**Independent Test**: Can be fully tested by changing the default duration in settings, opening simplified booking, and verifying time blocks match the new duration.

**Acceptance Scenarios**:

1. **Given** a user with permission to manage clinic appointment settings, **When** they set the default appointment duration to a valid value (e.g., 15, 30, or 45 minutes within allowed bounds), **Then** the value is saved for the clinic/branch scope and success is confirmed.
2. **Given** a saved default duration, **When** staff open the simplified slot picker, **Then** available time blocks are generated at intervals equal to that duration within branch working hours.
3. **Given** an invalid duration (below minimum, above maximum, or empty), **When** the administrator attempts to save, **Then** validation errors are shown and the previous valid value remains in effect.
4. **Given** a user without settings permission, **When** they attempt to change the default duration, **Then** the action is blocked with clear messaging.

---

### User Story 2 - Select Date and Time via Simplified Slot Picker (Priority: P1)

As reception staff with appointment-create permission, I can pick a date from a compact day strip and select an available time block so I can book an appointment without using the full calendar.

**Why this priority**: This is the core user-facing value of the feature — faster, clearer slot selection.

**Independent Test**: Can be fully tested by opening step two of booking with a chosen patient and doctor, selecting a day and an available block, and confirming the selection is reflected in the summary card.

**Acceptance Scenarios**:

1. **Given** step two of planned booking with a selected doctor at the active branch, **When** the simplified picker loads, **Then** a horizontal day strip shows day-of-week labels and day numbers; the initially selected day appears centered in the strip (typically today when booking for the current period).
2. **Given** the day strip, **When** the user swipes or uses navigation controls to move to adjacent days within 90 days of today, **Then** the centered selection updates and the time block grid refreshes for the newly selected day.
3. **Given** a date more than 90 days in the future, **When** the user attempts to navigate to it, **Then** that date is not reachable and navigation stops at the 90-day limit.
4. **Given** branch working hours for the selected day, **When** the time grid renders, **Then** blocks cover only in-hours times at intervals matching the default appointment duration; each block displays its start time (and implied end time via duration).
5. **Given** branch-wide availability evaluation for a time block where the preferred doctor is free and the block is not in the past, **When** the grid renders, **Then** the block appears **available** (no lock) and can be selected.
6. **Given** a time block where the preferred doctor is not free but at least one other doctor at the branch is free, **When** the grid renders, **Then** the block appears **locked with alternate-doctors styling** (visually distinct from fully unavailable blocks) and cannot be confirmed for the preferred doctor.
7. **Given** an alternate-doctors block, **When** the user taps it, **Then** a prompt lists the doctors available at that time and offers to switch from the preferred doctor.
8. **Given** the alternate-doctors prompt, **When** the user selects an available doctor, **Then** the preferred doctor is updated to that doctor, the block becomes the active selected slot (highlighted), and the summary card reflects the new doctor with the same date and time.
9. **Given** the alternate-doctors prompt, **When** the user dismisses without choosing a doctor, **Then** no slot is selected and the preferred doctor from step one remains unchanged.
10. **Given** a time block where no doctor at the branch is free, **When** the grid renders, **Then** the block appears **fully unavailable** with lock styling distinct from alternate-doctors blocks and cannot be selected.
11. **Given** an available block, **When** the user taps it, **Then** the block's visual style changes to a selected/highlighted state and becomes the active selection.
12. **Given** a previously selected block, **When** the user selects a different available block, **Then** only the new block remains highlighted.
13. **Given** a fully unavailable or past block, **When** the user attempts to select it, **Then** nothing is selected and no booking prompt is shown beyond the locked visual state.
14. **Given** more time blocks than fit on screen, **When** the user chooses "show more" (or equivalent expand control), **Then** additional blocks (all states) are revealed without leaving the booking flow.

---

### User Story 3 - View Selected Slot Summary and Complete Booking (Priority: P1)

As reception staff, I see a bottom summary card showing my current date-and-time selection and can confirm the booking as part of the multi-step procedure.

**Why this priority**: Staff must verify their choice before committing; the summary card closes the feedback loop shown in the reference design.

**Independent Test**: Can be fully tested by selecting a slot, reading the summary card, proceeding to confirmation, and verifying the created appointment matches the summary.

**Acceptance Scenarios**:

1. **Given** a selected date and time block, **When** the summary card is visible, **Then** it displays the full selected date (weekday, month, day), time range (start through end based on default duration), and the effective doctor (including after an alternate-doctor switch from step two).
2. **Given** no block selected yet, **When** step two is shown, **Then** the summary card indicates that a slot must be selected (or remains hidden/disabled per product policy) and the user cannot proceed to final confirmation.
3. **Given** a valid selection and completed step one (patient and doctor), **When** the user confirms the booking, **Then** a planned appointment is created with the selected start time and the configured default appointment duration (no per-booking override), subject to the same server-side conflict and validation rules as calendar booking.
4. **Given** the simplified booking flow, **When** the user is on step two, **Then** no control is offered to change appointment duration; duration is fixed to the clinic default for that session.
5. **Given** a conflict detected at confirmation time (another user booked the slot), **When** submission fails, **Then** the user sees a clear conflict message and the grid refreshes to reflect current availability.

---

### User Story 4 - Use Simplified Booking as Step Two of the Booking Procedure (Priority: P1)

As reception staff, I follow a guided booking procedure where I choose patient and doctor first, then pick date and time in the simplified picker, so the flow is structured and easy to complete.

**Why this priority**: Embedding the picker as step two is an explicit product requirement and defines how the feature integrates with existing booking.

**Independent Test**: Can be fully tested by starting a new planned appointment, completing step one, advancing to step two (simplified picker), and finishing the booking without opening the calendar.

**Acceptance Scenarios**:

1. **Given** a user with `appointments.create` at the active branch, **When** they tap **Book Appointment** on the appointments calendar page header, **Then** the two-step simplified booking procedure opens with step one (patient and doctor) before step two (slot picker).
2. **Given** a user taps an empty slot on the appointment calendar, **When** the booking UI opens, **Then** the existing calendar booking sheet is used (not the simplified two-step flow).
3. **Given** step one is incomplete, **When** the user attempts to advance to step two, **Then** validation prevents progression with field-level guidance.
4. **Given** step one is complete, **When** the user advances to step two, **Then** the simplified slot picker is displayed inline or within the same booking procedure (not as a separate unrelated screen).
5. **Given** the user is on step two, **When** they go back to step one and change the doctor, **Then** the time grid refreshes for the new doctor's availability and any prior slot selection is cleared.

---

### User Story 5 - Calendar Booking Remains Available (Priority: P2)

As reception staff who prefer the calendar, I can still book appointments by selecting a time slot directly on the appointment calendar without being forced through the simplified picker.

**Why this priority**: Explicit non-goal enforcement — protects existing workflows and trained user habits.

**Independent Test**: Can be fully tested by opening the calendar, tapping an empty slot, and completing booking through the existing calendar path with no simplified picker required.

**Acceptance Scenarios**:

1. **Given** the appointment calendar, **When** a user selects an empty slot, **Then** the existing calendar booking sheet opens and functions as before this feature.
2. **Given** the appointment calendar header, **When** a user taps **Book Appointment**, **Then** the two-step simplified booking flow opens instead of the existing single-sheet booking form.
3. **Given** both booking entry points exist, **When** a booking is created via either path, **Then** the resulting appointment record is identical in structure, permissions, and conflict rules (calendar booking may still allow per-appointment duration override; simplified booking does not).

---

### Edge Cases

- What happens when branch working hours are not configured or the selected day is closed? The time grid shows an empty or informational state (e.g., "No hours configured" / "Closed") and no blocks are selectable.
- What happens when every in-hours block has no free doctor at the branch for the selected day? All blocks show as fully unavailable; the summary card cannot proceed until the user picks another day or changes the preferred doctor in step one.
- What happens when the preferred doctor is busy but other doctors are free at a slot? The block shows alternate-doctors locked styling; tapping opens a prompt listing available doctors; choosing one switches the doctor and selects the slot without returning to step one.
- What happens when the selected day is today and some blocks are in the past? Past blocks are treated as unavailable (not selectable); future in-hours blocks remain available.
- What happens when the user tries to book beyond 90 days from today? Navigation is capped at 90 days ahead; dates beyond the limit are not reachable in the day strip.
- What happens when AI is unavailable during booking? Booking does not depend on AI; the flow proceeds normally with manual slot selection.
- How does the feature behave when a user lacks tenant-scoped or branch-scoped permission for booking? Step one and step two are inaccessible or actions are blocked with the same permission messaging as existing appointment booking.
- What happens when network or backend connectivity is degraded? Slot availability may be stale; on submit, server-side conflict validation remains authoritative; the user can retry or refresh availability when connectivity returns.
- What happens when the administrator changes default duration while a user is mid-booking? The in-progress session continues with the duration loaded at step two open time; a fresh booking session picks up the updated value.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a clinic-configurable **default appointment duration** setting (within validated min/max bounds) that persists per the existing appointment-settings scope used by the product.
- **FR-002**: System MUST expose the default appointment duration setting to authorized administrators through clinic/branch settings UI with validation feedback on save.
- **FR-003a**: System MUST NOT offer per-booking duration override anywhere in the simplified two-step booking flow; all blocks, summary display, and created appointments from this flow MUST use the configured default duration.
- **FR-003**: System MUST generate simplified-picker time blocks at intervals equal to the configured default appointment duration, constrained to branch working hours for the selected day.
- **FR-004**: System MUST evaluate time-block availability **branch-wide** across all doctors at the active branch, using the same non-cancelled, non–no-show overlap semantics as planned appointment creation.
- **FR-004a**: System MUST classify each block into exactly one availability state: **available** (preferred doctor free), **alternate doctors available** (preferred doctor not free, at least one other branch doctor free), or **fully unavailable** (no branch doctor free).
- **FR-004b**: System MUST render alternate-doctors blocks as locked with styling distinct from fully unavailable blocks; tapping MUST open a prompt listing doctors available at that time and offer to switch the preferred doctor.
- **FR-004c**: System MUST, when the user selects a doctor from the alternate-doctors prompt, update the effective doctor for the booking session, mark the tapped block as selected, and update the summary card with the same date/time and the new doctor — without requiring the user to return to step one.
- **FR-004d**: System MUST render fully unavailable blocks as locked with styling distinct from alternate-doctors blocks; tapping MUST NOT produce an alternate-doctors prompt and MUST NOT allow selection.
- **FR-005**: System MUST mark past time blocks on the current day as unavailable and not selectable (treated as fully unavailable).
- **FR-006**: System MUST present a horizontal day-only selector with the selected day visually centered in the strip and support navigation to adjacent days from today through **90 days ahead** (inclusive).
- **FR-006a**: System MUST NOT allow navigation to dates before today or more than 90 days in the future in the simplified day strip.
- **FR-007**: System MUST visually distinguish four block presentations: available (default), alternate-doctors locked, fully unavailable locked, and selected (highlighted color change on user selection of an available block or after a successful alternate-doctor switch).
- **FR-008**: System MUST display a bottom summary card showing the currently selected slot as a human-readable date and time range (start through start + default duration).
- **FR-009a**: System MUST launch the simplified two-step booking procedure from the **Book Appointment** control on the appointments calendar page header.
- **FR-009b**: System MUST NOT replace the existing calendar slot-tap booking sheet with the simplified two-step flow.
- **FR-009**: System MUST embed the simplified slot picker as **step two** of the planned-appointment booking procedure, with step one collecting at minimum patient and doctor before slot selection.
- **FR-010**: System MUST allow booking confirmation from step two only when patient, effective doctor, and a selected slot are all set such that the chosen doctor is free at the selected time; fully unavailable blocks MUST NOT be confirmable, and alternate-doctors blocks MUST NOT be confirmable until the user completes a doctor switch via the alternate-doctors prompt.
- **FR-011**: System MUST preserve the existing calendar-based booking entry point and flow without requiring use of the simplified picker.
- **FR-012**: System MUST enforce `appointments.create` (and related branch scope) for simplified booking at UI and server layers, consistent with existing appointment management.
- **FR-013**: System MUST reject final submission when server-side conflict or validation fails, with user-visible error messaging and refreshed availability where applicable.
- **FR-014**: System MUST degrade safely when availability data cannot be loaded: show a recoverable error state with retry; do not allow confirmation until valid slot data is available.

### Key Entities

- **Default Appointment Duration Setting**: Clinic/branch-scoped configuration value (minutes) defining standard slot length for simplified booking blocks and default end-time calculation for bookings created through this flow.
- **Time Block**: A discrete interval within working hours on a given day; attributes include start time, end time (derived from duration), branch-wide availability state (`available`, `alternate_doctors_available`, `fully_unavailable`, or `past`), and selection state (only applicable when `available`).
- **Simplified Booking Session**: In-progress multi-step booking context linking step-one selections (patient, preferred doctor, branch) with step-two slot selection; the effective doctor may be updated in step two via the alternate-doctors prompt without returning to step one.
- **Appointment**: Existing planned appointment record created on confirmation; unchanged in lifecycle and permissions relative to calendar booking.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Serves small-to-mid-size multi-branch clinics where receptionists book many short appointments daily. Simplifies front-desk throughput without removing the calendar for staff who prefer it. Enterprise/hospital scheduling (resource pools, multi-provider blocks, patient self-service portals) is out of scope.
- **Layer Placement**: Default duration setting is stored and validated in PostgreSQL-backed appointment settings (existing or extended RPC/settings table); conflict and working-hours rules remain server-authoritative. The simplified picker UI, day strip, block grid, selection state, and summary card live in the Flutter presentation layer. Branch-wide availability for all doctors at the active branch is loaded via existing appointment query patterns (no new source of truth). AI service is not involved in this feature.
- **Data Integrity & Security**: Slot states are derived from branch-wide appointment overlap rules cross-referenced with the preferred doctor from step one; creates use the same permission keys (`appointments.create`) and branch scoping as V1-4 appointment management. Settings changes require appropriate admin/settings permissions. Audit expectations for appointment creation and settings updates follow existing conventions.
- **Failure Handling**: If availability cannot be fetched, the picker shows retry and blocks confirmation. If AI or ancillary services are unavailable, booking is unaffected. Network loss on submit surfaces standard error/conflict handling without partial appointment records.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Reception staff with appointment-create permission can complete a planned booking through the simplified two-step flow (patient/doctor, then slot) in under 60 seconds for a typical case with an open slot.
- **SC-002**: 95% of slot selections in usability testing are completed without using the full calendar or manual time entry fields.
- **SC-003**: 100% of block availability states (available, alternate-doctors, fully unavailable) shown in the simplified picker match server-side conflict results on submission (no false "available" blocks that fail at create time except race conditions, which surface clear conflict feedback).
- **SC-004**: Calendar-based booking entry points remain available and functional — zero regression in calendar booking task completion rate after release.
- **SC-005**: Administrators can configure default appointment duration and see the change reflected in new simplified booking sessions within one settings save action.

## Assumptions

- The simplified two-step flow is entered via the **Book Appointment** button on the appointments calendar page; calendar slot tap retains the existing booking sheet.
- Step one of the booking procedure collects **patient** and **doctor** (and any other required fields already present in planned booking, such as notes if applicable); step two is exclusively date/time selection via the simplified picker.
- Default appointment duration reuses or extends the appointment settings concept introduced in appointment management (V1-4); this feature adds or completes the **settings UI** exposure if not already present, rather than inventing a duplicate setting.
- Time block availability is evaluated branch-wide across all doctors; the doctor chosen in step one is the **preferred doctor** whose free/busy status determines whether a block is directly bookable or falls into the alternate-doctors state.
- Branch working hours from existing branch schedule configuration define the outer bounds of generatable blocks.
- Bookable date range in the simplified day strip is **today through 90 days ahead**; past dates and dates beyond 90 days are not reachable.
- The reference screenshot's month header, chevron navigation, and "show more slots" expand pattern are desirable UX targets; exact visual tokens will be aligned during planning to the application design system.
- Edit/reschedule of existing appointments continues to use existing flows; simplified picker is for **new planned booking** initiated outside the calendar unless explicitly extended later.
- Simplified booking always uses the configured default appointment duration with no per-booking override; custom durations require calendar booking.
- Minimum and maximum duration bounds follow existing appointment management validation (e.g., 5–240 minutes).

## Dependencies

- Appointment management (V1-4): permissions, appointment create RPC, conflict detection, default duration storage.
- Branch working hours / schedule configuration: bounds for generatable time blocks.
- Patient registry (V1-3): patient selection in step one.
- Staff/doctor listing: doctor selection in step one.

## Out of Scope

- Replacing or removing calendar-based booking.
- Patient self-service online booking.
- Simplified picker for walk-in or emergency slots.
- Rescheduling existing appointments via the simplified picker (unless added in a follow-up).
- Per-booking duration override within the simplified two-step booking flow (calendar booking retains override capability from V1-4).
