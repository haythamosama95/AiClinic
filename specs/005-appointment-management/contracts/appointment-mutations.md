# Contract: Appointment Mutations and Settings

## Purpose

Create, reschedule, cancel, status updates, and default duration settings (V1-4).

## Authorization summary

| RPC                                | Permission                                               |
| ---------------------------------- | -------------------------------------------------------- |
| `get_appointment_settings`         | `appointments.create` OR `appointments.cancel`           |
| `set_appointment_default_duration` | `settings.manage_branches` OR owner/admin (org settings) |
| `create_appointment`               | `appointments.create`                                    |
| `reschedule_appointment`           | `appointments.create`                                    |
| `cancel_appointment`               | `appointments.cancel`                                    |
| `update_appointment_status`        | create (forward) / cancel (cancel, no_show) per matrix   |

---

## RPC: `get_appointment_settings`

| Parameter     | Type | Required |
| ------------- | ---- | -------- |
| `p_branch_id` | uuid | Yes      |

**Rules**: `p_branch_id` ∈ caller JWT `branch_ids`.

**Returns** `data`:

```json
{
  "default_duration_minutes": 20,
  "min_duration_minutes": 5,
  "max_duration_minutes": 240
}
```

(`default_duration_minutes` from `app_settings` resolution; min/max are constants documented here.)

---

## RPC: `set_appointment_default_duration`

| Parameter            | Type | Required |
| -------------------- | ---- | -------- |
| `p_branch_id`        | uuid | No       | NULL = org-wide row |
| `p_duration_minutes` | int  | Yes      | 5–240               |

**Rules**: Admin permission; upsert `app_settings` key `appointment.default_duration_minutes`.

---

## RPC: `create_appointment`

| Parameter            | Type        | Required    | Notes                                                                                       |
| -------------------- | ----------- | ----------- | ------------------------------------------------------------------------------------------- |
| `p_branch_id`        | uuid        | Yes         | Active branch; ∈ JWT `branch_ids`                                                           |
| `p_patient_id`       | uuid        | Yes         | Non-archived; same org                                                                      |
| `p_doctor_id`        | uuid        | No          | Staff doctor at branch; omit or null for planned without assignment; required for `walk_in` |
| `p_type`             | text        | Yes         | `planned` \| `walk_in`                                                                      |
| `p_start_time`       | timestamptz | Conditional | Required for `planned`                                                                      |
| `p_duration_minutes` | int         | No          | Default from settings if omitted                                                            |
| `p_end_time`         | timestamptz | No          | Optional override; must imply valid duration                                                |
| `p_notes`            | text        | No          |                                                                                             |

### Planned (`p_type = planned`)

- Initial `status` = `scheduled`
- Validate `p_start_time` + effective duration; conflict check
- Staff-selected times

### Walk-in (`p_type = walk_in`)

- Initial `status` = `checked_in`
- Ignore client `p_start_time` (or reject if sent); server assigns earliest gap ≥ now today (org TZ) for `p_duration_minutes`
- `queue_number` = NULL

**Conflict**: Overlap with any same doctor+branch appointment where status ∉ (`cancelled`, `no_show`).

**Errors**: `FORBIDDEN`, `INVALID_INPUT`, `SCHEDULE_CONFLICT`, `NO_SLOT_AVAILABLE`, `PATIENT_ARCHIVED`, `INVALID_DOCTOR`

**Returns**: `data.appointment_id`, `data.start_time`, `data.end_time`, `data.status`, `data.type`

**Audit**: `appointment.create`

---

## RPC: `reschedule_appointment`

| Parameter            | Type        | Required |
| -------------------- | ----------- | -------- |
| `p_appointment_id`   | uuid        | Yes      |
| `p_start_time`       | timestamptz | Yes      |
| `p_duration_minutes` | int         | No       |
| `p_end_time`         | timestamptz | No       |

**Rules**:

- Row `status = scheduled`, `type = planned`
- Branch in JWT; conflict check excluding self

**Audit**: `appointment.reschedule`

---

## RPC: `cancel_appointment`

| Parameter          | Type | Required |
| ------------------ | ---- | -------- |
| `p_appointment_id` | uuid | Yes      |
| `p_reason`         | text | No       |

**Rules**: From `scheduled` or `checked_in` → `cancelled`.

**Audit**: `appointment.cancel`

---

## RPC: `update_appointment_status`

| Parameter          | Type | Required |
| ------------------ | ---- | -------- |
| `p_appointment_id` | uuid | Yes      |
| `p_new_status`     | text | Yes      | `appointment_status` enum |

**Rules**: Transition matrix in `data-model.md`; permission by target status; actor need not be assigned doctor.

**Errors**: `INVALID_TRANSITION`, `FORBIDDEN`

**Audit**: `appointment.status` with old/new in payload
