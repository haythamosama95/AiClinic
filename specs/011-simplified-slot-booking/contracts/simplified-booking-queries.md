# Contract: Simplified Booking Queries

Read paths for the simplified slot picker (011). Builds on V1-4 `specs/005-appointment-management/contracts/appointment-queries.md`.

## Authorization

- `get_simplified_booking_slots`: requires `appointments.create` OR `appointments.cancel` at branch (same as `list_appointments`)
- `get_appointment_settings`: existing appointment access rules
- `set_appointment_default_duration`: settings/admin permission per V1-4 grants

---

## RPC: `get_simplified_booking_slots`

| Parameter | Type | Required | Notes |
| --------- | ---- | -------- | ----- |
| `p_branch_id` | uuid | Yes | Active branch ∈ JWT `branch_ids` |
| `p_local_date` | date | Yes | Calendar date in organization timezone (caller passes local date; server validates not before today nor more than 90 days ahead) |
| `p_preferred_doctor_id` | uuid | Yes | Doctor selected in step one |

**Rules**:

- Returns blocks only for branch working hours on `p_local_date`
- Block length = `default_duration_minutes` from branch settings
- `state` derived per data-model.md (branch-wide doctor iteration, per-doctor overlap)
- `past` blocks included for today but not selectable client-side
- Empty `blocks` when day closed or no working schedule

**Success** `data`:

```json
{
  "default_duration_minutes": 30,
  "blocks": [
    {
      "start_time": "timestamptz",
      "end_time": "timestamptz",
      "state": "available|alternate_doctors_available|fully_unavailable|past",
      "available_doctor_ids": ["uuid"]
    }
  ]
}
```

**Errors**:

| Code | When |
| ---- | ---- |
| `FORBIDDEN` | Missing appointment access |
| `INVALID_BRANCH` | Branch not in session |
| `INVALID_INPUT` | Date out of allowed range; invalid doctor |
| `INVALID_DOCTOR` | Preferred doctor not at branch |

---

## RPC: `get_appointment_settings` (existing)

Used when opening simplified booking step two and settings UI.

**Returns** (relevant fields):

```json
{
  "default_duration_minutes": 30,
  "min_duration_minutes": 5,
  "working_schedule": { }
}
```

---

## RPC: `set_appointment_default_duration` (existing)

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_duration_minutes` | int | Yes |
| `p_branch_id` | uuid | No |

**Validation**: duration ≥ 5

---

## RPC: `create_appointment` (existing)

Simplified flow submission:

| Field | Value |
| ----- | ----- |
| `p_branch_id` | session branch |
| `p_patient_id` | step one |
| `p_doctor_id` | `effectiveDoctorId` (may differ from preferred after alternate dialog) |
| `p_start_time` | selected slot start |
| `p_duration_minutes` | `default_duration_minutes` (no override) |
| `p_type` | `planned` |

**Conflict**: `SCHEDULE_CONFLICT` when per-doctor overlap detected server-side.

---

## Flutter repository

```dart
Future<SimplifiedBookingDaySlots> getSimplifiedBookingSlots({
  required String branchId,
  required DateTime localDate,
  required String preferredDoctorId,
});
```

- Parses `blocks[]` into `SimplifiedBookingSlot` list
- Maps RPC `state` strings to `SlotAvailabilityState`
- Surfaces `RpcFailure` for retry UI (FR-014)

---

## Caching / refresh

- Refetch slots when: selected date changes, preferred/effective doctor changes, after failed create (`SCHEDULE_CONFLICT`), manual retry
- No Realtime subscription for slot grid in v1 (optional later)

---

## Overlap amendment

`appointment_has_overlap` restored to per-doctor filtering. Document in migration comments; update `appointment_management_crud.sql` cases that asserted branch-wide same-time denial.
