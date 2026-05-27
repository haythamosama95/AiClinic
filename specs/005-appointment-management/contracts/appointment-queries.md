# Contract: Appointment List, Calendar, and Queue

## Purpose

Read paths for calendar (day/week), today's queue, and doctor schedule (V1-4).

## Authorization

Requires `appointments.create` OR `appointments.cancel`.

---

## RPC: `list_appointments`

| Parameter     | Type        | Required | Notes                                                                                     |
| ------------- | ----------- | -------- | ----------------------------------------------------------------------------------------- |
| `p_branch_id` | uuid        | Yes      | ∈ JWT `branch_ids`                                                                        |
| `p_from`      | timestamptz | Yes      | Inclusive range start                                                                     |
| `p_to`        | timestamptz | Yes      | Exclusive or inclusive end (document: inclusive end of day via +1 day boundary in caller) |
| `p_doctor_id` | uuid        | No       | Filter single doctor (schedule view)                                                      |
| `p_statuses`  | text[]      | No       | Filter subset; default all non-deleted in range                                           |

**Rules**:

- `is_deleted = false`
- Order: `start_time ASC` (FR-015)
- Join patient name, doctor display name for UI

**Returns** `data.items[]`:

```json
{
  "id": "uuid",
  "patient_id": "uuid",
  "patient_name": "string",
  "doctor_id": "uuid",
  "doctor_name": "string",
  "start_time": "timestamptz",
  "end_time": "timestamptz",
  "type": "planned|walk_in",
  "status": "scheduled|..."
}
```

### Today's queue

Caller computes `p_from` / `p_to` as start/end of **today** in organization timezone (from `organizations.timezone` via branch).

### Calendar week

Caller passes seven-day or Mon–Sun window for active branch; optional `p_doctor_id` for doctor schedule screen.

---

## Realtime (client contract)

Not an RPC — Flutter subscription:

- Channel: postgres changes on `public.appointments`
- Filter client-side: `branch_id == activeBranchId` AND `start_time` within today (org TZ)
- On event: invalidate `appointmentQueueProvider` / merge row
- Fallback: manual refresh (FR-016)

---

## Error codes (shared)

| Code                 | Meaning                       |
| -------------------- | ----------------------------- |
| `FORBIDDEN`          | Permission or branch          |
| `NOT_FOUND`          | Unknown id                    |
| `INVALID_INPUT`      | Validation                    |
| `SCHEDULE_CONFLICT`  | Overlapping doctor slot       |
| `NO_SLOT_AVAILABLE`  | Walk-in; no gap fits duration |
| `INVALID_TRANSITION` | Status change not allowed     |
