# Data Model: Appointment Management

Introduces `public.appointments` and appointment settings (V1-4). Builds on V1-1/V1-2 tenancy, V1-3 `patients`, and `staff_members` / `staff_branch_assignments`.

## New schema (V1-4 migration)

### ENUM: `appointment_type`

```sql
CREATE TYPE public.appointment_type AS ENUM ('planned', 'walk_in');
```

`walk_in` remains in the enum for backward compatibility but is **rejected** by `create_appointment` (booking is planned-only).

### ENUM: `appointment_status`

```sql
CREATE TYPE public.appointment_status AS ENUM (
  'scheduled',
  'confirmed',
  'checked_in',
  'in_progress',
  'completed',
  'cancelled',
  'no_show'
);
```

### TABLE: `appointments`

| Column          | Type                    | Notes                                                               |
| --------------- | ----------------------- | ------------------------------------------------------------------- |
| `id`            | uuid PK                 | `gen_random_uuid()`                                                 |
| `branch_id`     | uuid FK → branches      | Active branch at create; immutable in V1-4                          |
| `patient_id`    | uuid FK → patients      | Non-archived patient in org                                         |
| `doctor_id`     | uuid FK → staff_members | Optional; when set, must be `role = doctor` at branch               |
| `start_time`    | timestamptz NOT NULL    |                                                                     |
| `end_time`      | timestamptz NOT NULL    | Must be > `start_time`                                              |
| `type`          | appointment_type        | `planned` only (new bookings)                                       |
| `status`        | appointment_status      | Entry: `scheduled` on create                                        |
| `queue_number`  | int                     | Nullable; **unused** in V1-4 (always NULL)                          |
| `notes`         | text                    | Optional; max 2000 chars (app + DB)                                 |
| `cancel_reason` | text                    | Optional; set on cancel                                             |
| audit columns   | standard                | `created_at`, `created_by`, `updated_at`, `updated_by`, soft delete |

**Check**: `end_time > start_time`

### Indexes

```sql
CREATE INDEX appointments_branch_doctor_start_idx
  ON public.appointments (branch_id, doctor_id, start_time)
  WHERE is_deleted = false;

CREATE INDEX appointments_branch_status_start_idx
  ON public.appointments (branch_id, status, start_time)
  WHERE is_deleted = false;

CREATE INDEX appointments_branch_start_idx
  ON public.appointments (branch_id, start_time)
  WHERE is_deleted = false;
```

### RLS (summary)

| Policy                | Rule                                                                             |
| --------------------- | -------------------------------------------------------------------------------- |
| `appointments_select` | Authenticated; `is_deleted = false`; `branch_id` ∈ JWT `branch_ids` (via helper) |
| `appointments_insert` | Deny direct insert                                                               |
| `appointments_update` | Deny direct update                                                               |
| `appointments_delete` | Deny direct delete                                                               |

Mutations **only** via RPC. Reads may use SELECT under RLS **or** `list_appointments` RPC.

## Settings (existing `app_settings`)

| Key                                    | Scope                     | Value                  |
| -------------------------------------- | ------------------------- | ---------------------- |
| `appointment.default_duration_minutes` | `branch_id` or NULL (org) | JSON number, e.g. `20` |

Resolution: branch row → org row (`branch_id IS NULL`) → RPC fallback 20.

## Entity lifecycle

### Appointment (planned booking only)

| Entry status | Happy path                                                   |
| ------------ | ------------------------------------------------------------ |
| `scheduled`  | scheduled → confirmed → checked_in → in_progress → completed |

| From          | To                                    | Permission      |
| ------------- | ------------------------------------- | --------------- |
| `scheduled`   | `confirmed`, `cancelled`, `no_show`   | create / cancel |
| `confirmed`   | `checked_in`, `cancelled`, `no_show`  | create / cancel |
| `checked_in`  | `in_progress`, `cancelled`, `no_show` | create / cancel |
| `in_progress` | `completed`                           | create          |
| Terminal      | —                                     | —               |

**Phone confirmation**: Reception advances `scheduled` → `confirmed` after calling the patient. `confirmed` → `checked_in` on arrival, or `confirmed` → `cancelled` if the patient does not confirm.

**Reschedule**: only `status = scheduled` (before confirmation).

**Conflict**: No overlap for same `doctor_id` + `branch_id` when either side status ∉ (`cancelled`, `no_show`).

## Authorization matrix (V1-4)

| Operation                          | Permission key                                         | Notes                |
| ---------------------------------- | ------------------------------------------------------ | -------------------- |
| View calendar / queue / schedule   | `appointments.create` OR `appointments.cancel`         | Either grant         |
| Book / reschedule / forward status | `appointments.create`                                  | Any doctor at branch |
| Cancel / no-show                   | `appointments.cancel`                                  |                      |
| Edit default duration (settings)   | `settings.manage_branches` or owner/admin org settings |                      |

## RPC inventory

| RPC                                | Purpose                                     |
| ---------------------------------- | ------------------------------------------- |
| `get_appointment_settings`         | Default duration for branch                 |
| `set_appointment_default_duration` | Persist `app_settings`                      |
| `create_appointment`               | Planned booking only → `scheduled`          |
| `reschedule_appointment`           | `scheduled` planned only                    |
| `cancel_appointment`               | From `scheduled`, `confirmed`, `checked_in` |
| `update_appointment_status`        | Validated transitions incl. no_show         |
| `list_appointments`                | Calendar, queue, doctor schedule            |

## Client models (Flutter)

| Type                     | Fields (representative)                                          |
| ------------------------ | ---------------------------------------------------------------- |
| `AppointmentListItem`    | id, patientName, doctorName, startTime, endTime, type, status    |
| `AppointmentDetail`      | full row + audit metadata                                        |
| `AppointmentBookingForm` | patientId, doctorId, startTime, durationMinutes, endTime?, notes |
| `CalendarViewMode`       | day \| week                                                      |

## Relationships

```text
branches 1──* appointments
patients 1──* appointments
staff_members (doctor) 1──* appointments
appointments ── (future V1-5) visits
```

## Audit actions

| Action                   | Trigger                     |
| ------------------------ | --------------------------- |
| `appointment.create`     | `create_appointment`        |
| `appointment.reschedule` | `reschedule_appointment`    |
| `appointment.cancel`     | `cancel_appointment`        |
| `appointment.status`     | `update_appointment_status` |
