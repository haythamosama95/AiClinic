# Data Model: Simplified Slot Booking

Extends V1-4 appointment management (`specs/005-appointment-management/data-model.md`). **No new tables.** One migration adjusts overlap helper and adds a read RPC.

## Schema changes (011 migration)

### FUNCTION: `auth_internal.appointment_has_overlap` (amend)

Restore per-doctor conflict detection:

```sql
-- Pseudocode shape (see migration for full body)
SELECT EXISTS (
  SELECT 1 FROM public.appointments a
  WHERE a.branch_id = p_branch_id
    AND a.doctor_id = p_doctor_id          -- restored filter
    AND a.is_deleted = false
    AND a.status NOT IN ('cancelled', 'no_show')
    AND (p_exclude_appointment_id IS NULL OR a.id <> p_exclude_appointment_id)
    AND a.start_time < p_end_time
    AND a.end_time > p_start_time
);
```

When `p_doctor_id IS NULL`, treat as no overlap (planned booking requires doctor in simplified flow).

**Impact**: Two different doctors may hold concurrent appointments at the same branch clock time. Supersedes branch-wide slot uniqueness tests in `appointment_management_crud.sql` — update expectations.

### FUNCTION: `auth_internal.get_simplified_booking_slots`

**Inputs**

| Parameter | Type | Required | Notes |
| --------- | ---- | -------- | ----- |
| `p_branch_id` | uuid | Yes | Active branch |
| `p_local_date` | date | Yes | Calendar day in org timezone |
| `p_preferred_doctor_id` | uuid | Yes | Step-one doctor |

**Authorization**: `auth_internal.assert_appointment_access()` + `assert_appointment_branch(p_branch_id)`; requires `appointments.create` or `appointments.cancel` (same as list).

**Algorithm (summary)**

1. Load org timezone, branch `working_schedule`, `default_duration_minutes`
2. If day not working → return empty `blocks[]`
3. Generate block start times from open→close stepping by duration; skip past blocks when `p_local_date` is today
4. Load branch doctors (assigned, role doctor, not deleted)
5. Load day appointments (non-cancelled, non–no-show) for branch
6. For each block `[start, end)`:
   - For each doctor, `free(d) = NOT overlap(d.appointments, block)`
   - `available_doctor_ids` = doctors where `free(d)`
   - If preferred ∈ `available_doctor_ids` → `state = available`
   - Else if `available_doctor_ids` non-empty → `state = alternate_doctors_available`
   - Else → `state = fully_unavailable`

**Returns** `rpc_success` data:

```json
{
  "default_duration_minutes": 30,
  "blocks": [
    {
      "start_time": "2026-11-12T07:15:00+00:00",
      "end_time": "2026-11-12T07:30:00+00:00",
      "state": "available|alternate_doctors_available|fully_unavailable|past",
      "available_doctor_ids": ["uuid", "..."]
    }
  ]
}
```

### PUBLIC wrapper

`public.get_simplified_booking_slots(p_branch_id uuid, p_local_date date, p_preferred_doctor_id uuid)` → delegates to `auth_internal`.

## Client domain models (Flutter)

### `SlotAvailabilityState` (enum)

| Value | Meaning |
| ----- | ------- |
| `available` | Preferred doctor free |
| `alternateDoctorsAvailable` | Other doctors free |
| `fullyUnavailable` | No doctor free |
| `past` | Block start before now (today only) |

### `SimplifiedBookingSlot`

| Field | Type | Notes |
| ----- | ---- | ----- |
| `startTime` | DateTime | UTC from RPC |
| `endTime` | DateTime | start + duration |
| `state` | SlotAvailabilityState | |
| `availableDoctorIds` | List\<String\> | For alternate dialog |

### `SimplifiedBookingSession` (in-memory)

| Field | Type | Notes |
| ----- | ---- | ----- |
| `branchId` | String | |
| `patientId` | String? | Step one |
| `preferredDoctorId` | String? | Step one |
| `effectiveDoctorId` | String? | May change in step two |
| `selectedDate` | DateTime | Local date |
| `selectedSlot` | SimplifiedBookingSlot? | |
| `defaultDurationMinutes` | int | Frozen at step-two open |
| `notes` | String? | Optional step one |

## Settings (unchanged storage)

| Key | Scope | Usage |
| --- | ----- | ----- |
| `appointment.default_duration_minutes` | branch / org via `app_settings` | Block step size + create duration |

**UI addition**: branch settings section exposes read/write via existing RPCs.

## Validation rules

| Rule | Layer |
| ---- | ----- |
| Duration 5–∞ minutes (no max after `20260615120000`) | PostgreSQL `assert_appointment_duration_bounds` |
| `p_local_date` within today..today+90 | Flutter clamp (RPC may reject out-of-range with `INVALID_INPUT`) |
| Doctor must be branch-assigned | RPC doctor list + `create_appointment` |
| Create uses default duration only in simplified path | Flutter omits override; server validates |

## State transitions (booking session)

```text
[Header Book tap]
  → step1 (patient + doctor)
  → step2 (load slots RPC)
  → select available block OR alternate dialog → selected
  → confirm → create_appointment → success close
```

Back step1 → clears `selectedSlot`; changing doctor → reload RPC.

## Audit / security

- No new write paths beyond existing `create_appointment` and `set_appointment_default_duration`
- Slot query is read-only; RLS on `appointments` applies to underlying SELECT
- Audit log on create unchanged
