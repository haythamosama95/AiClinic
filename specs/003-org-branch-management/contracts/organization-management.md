# Contract: Organization Management

## Purpose

Steady-state organization profile updates for the single tenant per installation (V1-2).

## Authorization

| Caller role     | View | Update |
| --------------- | ---- | ------ |
| `owner`         | Yes  | Yes    |
| `administrator` | Yes  | Yes    |
| Other roles     | No   | No     |

No `settings.manage_organization` permission key. Server validates role in `auth_internal`.

## Read: organization profile

**Method**: PostgREST `GET` on `organizations` (RLS: `id = jwt.organization_id`, `is_deleted = false`)

**Fields exposed to UI**:

| Field                      | Editable in V1-2                                                                         |
| -------------------------- | ---------------------------------------------------------------------------------------- |
| `name`                     | Yes                                                                                      |
| `logo_url`                 | Yes                                                                                      |
| `currency_code`            | Yes                                                                                      |
| `timezone`                 | Yes                                                                                      |
| `settings_json`            | Yes (structured form or JSON editor — plan defers to minimal fields + optional raw view) |
| `subscription_tier`        | Display only                                                                             |
| `subscription_valid_until` | Display only                                                                             |

## RPC: `update_organization`

**Caller**: `owner` or `administrator`

| Parameter         | Type  | Required |
| ----------------- | ----- | -------- |
| `p_name`          | text  | Yes      |
| `p_logo_url`      | text  | No       |
| `p_currency_code` | text  | No       |
| `p_timezone`      | text  | No       |
| `p_settings_json` | jsonb | No       |

**Validation**:

- `p_name` non-empty after trim
- `p_currency_code` valid ISO 4217 when provided
- `p_timezone` valid IANA when provided
- Target org must be caller’s `jwt.organization_id`
- Reject if organization row missing

**Returns**: `rpc_result` with updated organization id

**Errors**: `FORBIDDEN`, `ORG_NOT_FOUND`, `INVALID_INPUT`

**Audit**: `organization.update` with `old_data_json` / `new_data_json`

## UI: Organization Settings

**Route**: `/settings/organization` (under settings hub)

**States**: Loading, Loaded, Validation Error, Submitting, Success, Permission Denied

**Out of scope**: Create second organization; subscription enforcement
