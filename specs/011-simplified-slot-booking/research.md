# Research: Simplified Slot Booking (011)

Phase 0 research resolves implementation choices for the simplified two-step booking flow. All Technical Context items are resolved.

## Decisions

### D1. Entry point wiring

- **Decision**: Header **Book Appointment** on `appointment_calendar_page.dart` opens `SimplifiedBookingFlow`; calendar empty-slot tap continues to call `AppointmentBookingSheet.show` unchanged.
- **Rationale**: Matches clarification FR-009a/FR-009b; minimal navigation churn; reuses existing permission `onBookAppointment` callback.
- **Alternatives considered**: Replace all booking with simplified flow (rejected — spec forbids); queue entry point (deferred — not in clarifications).

### D2. Branch-wide evaluation vs per-doctor conflict

- **Decision**: **Branch-wide evaluation** means the slot RPC iterates **all doctors assigned to the branch** when classifying each block. **Per-doctor appointment overlap** determines whether a specific doctor is free (`appointment_has_overlap` filters by `doctor_id`). Restore per-doctor overlap in PostgreSQL (revert branch-wide uniqueness from `20260528150500`).
- **Rationale**: Clarified three states require: preferred doctor busy at 7:15 while another doctor free at 7:15. Current branch-wide `appointment_has_overlap` blocks that scenario on create and makes alternate-doctors UI unreachable for real conflicts.
- **Alternatives considered**: Client-only per-doctor display with branch-wide server (rejected — false "available" alternates fail on submit); branch-wide display only (rejected — contradicts user clarification).

### D3. Server-authoritative slot grid

- **Decision**: New RPC `get_simplified_booking_slots(p_branch_id, p_date, p_preferred_doctor_id)` returns discrete blocks with `state` enum and `available_doctor_ids` for alternate prompts. Block generation uses branch `working_schedule`, org timezone, `default_duration_minutes`, and non-cancelled appointments for the day.
- **Rationale**: Constitution Principle III — correctness and slot states must not be Flutter-only; keeps create validation and display aligned.
- **Alternatives considered**: Pure client derivation from `list_appointments` (rejected — duplicates working-hours logic, drift risk); extend `list_appointments` only (rejected — payload too heavy for 90-day prefetch).

### D4. Default duration settings UI placement

- **Decision**: Add `AppointmentDurationSettingsSection` under clinic setup settings tab, scoped to **active branch** (or per-branch card in branch settings grid) calling existing `get_appointment_settings` / `set_appointment_default_duration`.
- **Rationale**: RPCs and repository methods exist; grep shows no settings UI field yet despite V1-4 plan reference. Branch-scoped duration matches `get_appointment_settings(p_branch_id)`.
- **Alternatives considered**: Organization-only settings page without branch context (rejected — RPC is branch-scoped); embed duration in simplified flow (rejected — admin settings belong in clinic setup).

### D5. Duration in simplified flow

- **Decision**: Fixed to `default_duration_minutes` loaded at step-two open; hide duration controls; pass default to `create_appointment` as `p_duration_minutes` without user override.
- **Rationale**: Clarification A; keeps block grid and summary aligned.
- **Alternatives considered**: Step-one duration picker (rejected); step-two override (rejected).

### D6. Two-step shell pattern

- **Decision**: Modal overlay matching `AppointmentBookingSheet` scrim pattern (`showGeneralDialog` + blurred scrim) with internal `PageView` or indexed step state (`step 1 | step 2`), back navigation from step two to step one clears slot selection.
- **Rationale**: Consistent with existing booking modal; keeps user in appointments context.
- **Alternatives considered**: Full-page route (heavier navigation); single scrolling form (rejected — spec requires distinct step two picker).

### D7. Day strip behavior

- **Decision**: Horizontal `ListView` or `PageView` with ~7 visible day cells; selected day centered via `scrollController` animate; chevrons shift by one day; clamp date to `[today, today+90]`.
- **Rationale**: Matches reference screenshot and FR-006/FR-006a; 90-day cap limits RPC volume.
- **Alternatives considered**: Month grid (out of scope per spec); infinite scroll (rejected — 90-day cap).

### D8. Time block grid + "show more"

- **Decision**: `Wrap` or fixed-column grid of `SimplifiedTimeBlock` chips; initially show first N rows (e.g. 14 blocks); **Show more slots** expands inline with count of `available` blocks in subtitle.
- **Rationale**: Reference screenshot pattern; FR user story 2 scenario 14.
- **Alternatives considered**: Scrollable grid only (acceptable fallback); paginated RPC (unnecessary for single day).

### D9. Three visual block states + selected

- **Decision**: Use semantic color tokens — `available`: default surface; `alternate_doctors_available`: muted + lock icon + warning/accent border; `fully_unavailable` / `past`: muted + lock + reduced opacity; `selected`: primary fill (same as reference teal highlight).
- **Rationale**: FR-007; distinct styling requirement from clarifications.
- **Alternatives considered**: Text-only distinction (fails accessibility/contrast goals).

### D10. Alternate-doctors prompt

- **Decision**: `AlternateDoctorsDialog` (or bottom sheet) listing `available_doctor_ids` from RPC for that block; on select → update session `effectiveDoctorId`, mark block selected, refresh summary card; dismiss leaves state unchanged.
- **Rationale**: Clarification B; FR-004b/FR-004c.
- **Alternatives considered**: Navigate to step one (rejected); info-only toast (rejected).

### D11. Summary card

- **Decision**: `SimplifiedSlotSummaryCard` below picker inside step two — mint/teal tinted background per reference; shows weekday, date, time range, doctor name; confirm button disabled until slot selected.
- **Rationale**: FR-008; reference design footer.
- **Alternatives considered**: Floating bottom bar across steps (summary only relevant in step two).

### D12. Testing strategy

- **Decision**: SQL tests for RPC states and overlap regression; Flutter unit tests for date clamp and slot state mapping; widget tests for grid interactions and dialog; one widget test verifying calendar header opens simplified flow while slot tap opens legacy sheet.
- **Rationale**: SC-003 requires display/server alignment; dual entry point is regression-sensitive.
- **Alternatives considered**: Manual QA only (insufficient for overlap change).

## Resolved unknowns

| Unknown | Resolution |
| ------- | ---------- |
| Settings UI exists? | No — add branch settings section |
| Slot data source | New `get_simplified_booking_slots` RPC |
| Overlap semantics for alternates | Per-doctor (migration) |
| Entry point | Calendar header button only |
| Booking horizon | 90 days |
| Duration override | None in simplified flow |

## Dependencies validated

- `get_appointment_settings` returns `default_duration_minutes`, `min_duration_minutes`, `working_schedule`
- `create_appointment` accepts `p_duration_minutes`
- `list_appointments` pattern for day range usable in tests
- `AppointmentBookingSheet` remains for calendar slot path
