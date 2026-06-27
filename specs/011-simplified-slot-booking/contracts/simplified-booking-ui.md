# Contract: Simplified Booking UI

Presentation contract for the two-step booking flow and slot picker widgets. No new routes required — modal launched from calendar page.

**Entry**: `AppointmentCalendarPage` header `Book Appointment` button
**Baseline patterns**: `AppointmentBookingSheet`, reference screenshot (`assets/image-0eb4c0e7-869c-4411-9aeb-135c0c9d8b35.png`)

---

## `SimplifiedBookingFlow`

```dart
static Future<bool?> show(
  BuildContext context, {
  required String branchId,
  required BranchWorkingSchedule schedule,
  required List<StaffListItem> doctors,
});
```

| Behavior | Requirement |
| -------- | ----------- |
| Returns `true` when appointment created | Same as booking sheet |
| Step indicator | Optional "1 / 2" or back affordance |
| Permission | Caller gates with `canCreateAppointments` |

### Step 1 — `SimplifiedBookingStepOne`

| Field | Control | Validation |
| ----- | ------- | ---------- |
| Patient | Reuse patient search from booking sheet | Required |
| Doctor | `AppointmentDoctorSelector` | Required for simplified flow |
| Notes | Optional text | Max 2000 chars |

**Next** disabled until patient + doctor valid.

### Step 2 — `SimplifiedBookingStepTwo`

| Region | Widget | Notes |
| ------ | ------ | ----- |
| Header | Title "Select Date and Time" + month label | Month/year of centered day |
| Day strip | `SimplifiedDayStrip` | Centered selection; chevrons; clamp 90 days |
| Divider | Horizontal rule | |
| Blocks | `SimplifiedTimeBlockGrid` | States per FR-007 |
| Expand | `Show more slots` link | Shows hidden rows + available count |
| Footer | `SimplifiedSlotSummaryCard` | Below card body |

---

## `SimplifiedDayStrip`

| Prop | Type | Behavior |
| ---- | ---- | -------- |
| `selectedDate` | DateTime (date only) | Centered cell |
| `minDate` | today | |
| `maxDate` | today + 90 days | |
| `onDateSelected` | callback | Triggers slot reload |

Cells show weekday label + day number; selected cell bold + underline per reference.

---

## `SimplifiedTimeBlockGrid`

| Prop | Type |
| ---- | ---- |
| `slots` | `List<SimplifiedBookingSlot>` |
| `selectedStart` | DateTime? |
| `onSlotTap` | `(SimplifiedBookingSlot) → void` |

**Tap behavior**

| State | Action |
| ----- | ------ |
| `available` | Select; highlight |
| `alternateDoctorsAvailable` | Open `AlternateDoctorsDialog` |
| `fullyUnavailable`, `past` | No-op |

**Visual**

| State | Style |
| ----- | ----- |
| available | White/neutral chip, dark text |
| alternate | Lock icon, distinct muted/warning background |
| fully unavailable | Lock icon, different muted/disabled background |
| selected | Primary/teal fill, white text |

---

## `AlternateDoctorsDialog`

| Prop | Type |
| ---- | ---- |
| `slot` | `SimplifiedBookingSlot` |
| `doctors` | `List<StaffListItem>` filtered to `availableDoctorIds` |
| `onDoctorSelected` | `(doctorId) → void` |

Message: other doctors are available at `{time}`.

---

## `SimplifiedSlotSummaryCard`

| Content | Format |
| ------- | ------ |
| Label | "Currently Selected:" |
| Value | `{Weekday}, {Month} {Day}, {HH:mm} – {HH:mm}` + doctor name |
| Confirm | Primary button; disabled when no selection |

Background: light mint/teal gradient per reference.

---

## Calendar page integration

```dart
// Header button
onBookAppointment: () => SimplifiedBookingFlow.show(...)

// Slot tap (unchanged)
onSlotTap: (...) => AppointmentBookingSheet.show(...)
```

---

## Settings: `AppointmentDurationSettingsSection`

| Element | Behavior |
| ------- | -------- |
| Numeric field | Default appointment duration (minutes) |
| Save | `setDefaultDuration` |
| Validation | ≥ `min_duration_minutes` from settings |
| Scope label | Branch name |

Placed in clinic setup tab (branch settings card or dedicated row).

---

## Accessibility

- Time blocks: `Semantics` button with time label and state ("available", "locked, other doctors available")
- Day cells: button with full date label
- Dialog: focus trap, dismissible

---

## Files (implementation targets)

| Widget | Path |
| ------ | ---- |
| Flow shell | `features/appointments/presentation/widgets/simplified_booking_flow.dart` |
| Day strip | `.../simplified_day_strip.dart` |
| Block grid | `.../simplified_time_block_grid.dart` |
| Summary | `.../simplified_slot_summary_card.dart` |
| Alternate dialog | `.../alternate_doctors_dialog.dart` |
| Duration settings | `features/settings/presentation/widgets/appointment_duration_settings_section.dart` |
