# Data Model: Appointment Management

Introduces `public.appointments` and appointment settings (V1-4). Builds on V1-1/V1-2 tenancy, V1-3 `patients`, and `staff_members` / `staff_branch_assignments`.

## New schema (V1-4 migration)

### ENUM: `appointment_type`

```sql
CREATE TYPE public.appointment_type AS ENUM ('planned', 'walk_in');
```

### ENUM: `appointment_status`

```sql
CREATE TYPE public.appointment_status AS ENUM (
  'scheduled',
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
| `doctor_id`     | uuid FK → staff_members | Must be `role = doctor`                                             |
| `start_time`    | timestamptz NOT NULL    |                                                                     |
| `end_time`      | timestamptz NOT NULL    | Must be > `start_time`                                              |
| `type`          | appointment_type        | `planned` \| `walk_in`                                              |
| `status`        | appointment_status      | Entry: planned→`scheduled`, walk_in→`checked_in`                    |
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

### Appointment

| Type      | Entry status | Happy path                                               |
| --------- | ------------ | -------------------------------------------------------- |
| `planned` | `scheduled`  | scheduled → checked_in → in_progress → completed         |
| `walk_in` | `checked_in` | checked_in → in_progress → completed (never `scheduled`) |

| From          | To                                    | Permission      |
| ------------- | ------------------------------------- | --------------- |
| `scheduled`   | `checked_in`, `cancelled`, `no_show`  | create / cancel |
| `checked_in`  | `in_progress`, `cancelled`, `no_show` | create / cancel |
| `in_progress` | `completed`                           | create          |
| Terminal      | —                                     | —               |

**Reschedule**: only `status = scheduled` and `type = planned`.

**Conflict**: No overlap for same `doctor_id` + `branch_id` when either side status ∉ (`cancelled`, `no_show`).

## Authorization matrix (V1-4)

| Operation                                              | Permission key                                         | Notes                |
| ------------------------------------------------------ | ------------------------------------------------------ | -------------------- |
| View calendar / queue / schedule                       | `appointments.create` OR `appointments.cancel`         | Either grant         |
| Create planned / walk-in / reschedule / forward status | `appointments.create`                                  | Any doctor at branch |
| Cancel / no-show                                       | `appointments.cancel`                                  |                      |
| Edit default duration (settings)                       | `settings.manage_branches` or owner/admin org settings |                      |

## RPC inventory

| RPC                                | Purpose                                      |
| ---------------------------------- | -------------------------------------------- |
| `get_appointment_settings`         | Default duration for branch                  |
| `set_appointment_default_duration` | Persist `app_settings`                       |
| `create_appointment`               | Planned (staff times) or walk-in (auto slot) |
| `reschedule_appointment`           | `scheduled` planned only                     |
| `cancel_appointment`               | → `cancelled` + optional reason              |
| `update_appointment_status`        | Validated transitions incl. no_show          |
| `list_appointments`                | Calendar, queue, doctor schedule             |

## Client models (Flutter)

| Type                     | Fields (representative)                                          |
| ------------------------ | ---------------------------------------------------------------- |
| `AppointmentListItem`    | id, patientName, doctorName, startTime, endTime, type, status    |
| `AppointmentDetail`      | full row + audit metadata                                        |
| `AppointmentBookingForm` | patientId, doctorId, startTime, durationMinutes, endTime?, notes |
| `WalkInFormState`        | patientId, doctorId, durationMinutes (pre-filled), notes         |
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
