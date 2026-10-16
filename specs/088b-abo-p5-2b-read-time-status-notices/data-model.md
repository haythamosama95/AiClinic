# Data model: P5.2b read-time status, notices and billing status

Entities are the ones in spec §3.2. This unit defines no new table. The migration is `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`. It does not edit `20261007230000_coverage_feed_puller_status.sql`.

## 1. Notice record

One element of `notices[]`. Not a table.

| Field | Present | Value |
| --- | --- | --- |
| `code` | Always | One of `ends_soon`, `in_grace`, `allowance_low`, `allowance_exhausted`, `lapsed`, `ended_reversed`, `suspended`, `status_stale` |
| `audience` | Always | `member` |
| `channel` | Always | `in_app` |
| `grace_days_left` | Only when `code` is `in_grace` | Non-negative integer. Whole 24-hour days from the call's `now()` until `grace_ends_at`, floored. A remaining partial day is `0`. Every other code omits this key |

The same records are returned to every member. Array order is not significant.

| Code | Raised when |
| --- | --- |
| `ends_soon` | `days_left` is 7, 3, or 1 or fewer. Null does not match. Also requires `queued_count = 0` |
| `in_grace` | Returned state is `grace` |
| `allowance_low` | Stored `band` is `75` or `90` |
| `allowance_exhausted` | Returned state is `exhausted` |
| `lapsed` | Returned state is `lapsed` |
| `ended_reversed` | Returned state is `reversed` |
| `suspended` | `clinic_ai_coverage.suspended` is true |
| `status_stale` | `stale` is true |

## 2. Status view

The success `data` of `get_ai_status`, and the same keys on `get_ai_billing_status`. Computed in `auth_internal.get_ai_status` for `current_org_id()`. Not stored.

| Field | Type | Rule |
| --- | --- | --- |
| `available` | boolean | True exactly when returned `state` is `active` or `grace` |
| `state` | text | No row: `none`. `suspended` true: `suspended` (wins over the stored state). Stored `active`: `active` while `now < ends_at`; `active` when `now >= ends_at` and `queued_count > 0`; otherwise `grace` while `now < grace_ends_at`; otherwise `lapsed`. Stored `grace`: `grace` while `now < grace_ends_at`, then `lapsed`. Any other stored state is returned as stored |
| `reason` | text or null | Null when returned `state` is `active`, `grace`, or `suspended`. `none` when the row is absent. `expired` when stored `active` or stored `grace` becomes `lapsed` at read time. Otherwise the stored `clinic_ai_coverage.reason`. The read does not update that column |
| `days_left` | integer or null | Whole 24-hour days from `now()` until `ends_at`, floored. Null when the row is absent, `ends_at` is null, or `now >= ends_at`. Independent of `grace_days_left`. Null does not raise `ends_soon` |
| `band` | text or null | Stored `clinic_ai_coverage.band` (`ok`, `75`, `90`, or `exhausted` when the puller wrote a term). Null when the row or the column is absent |
| `notices` | array | Section 1 |
| `next_change_at` | timestamptz or null | The earlier of `ends_at` and `grace_ends_at` that is still strictly after `now()`. Null when neither is |
| `as_of` | timestamptz | The single `now()` of this call. Present when the row is absent. Not `event_at`, `applied_at`, or `last_success_at`. Not stored |
| `stale` | boolean | True when `feed_state.last_success_at` is null or strictly older than 2 minutes |
| `platform_base_url` | text | `auth_internal.ai_app_setting_text('ai.platform_base_url', 'http://127.0.0.1:8787')` |

`get_ai_status` success `data` has these keys only. It has no prices, payments, or references.

## 3. Billing status fields

Flat keys added on administrator success of `get_ai_billing_status`, beside the status view. There is no `remaining` key. Remaining, when a caller computes it, is `allowance - used` when both are non-null, including when `used` exceeds `allowance`, and null when either is null.

| Field | Source |
| --- | --- |
| `plan_display_name` | `clinic_ai_coverage.plan_display_name` |
| `starts_at` | `clinic_ai_coverage.starts_at` |
| `ends_at` | `clinic_ai_coverage.ends_at` |
| `grace_ends_at` | `clinic_ai_coverage.grace_ends_at` |
| `allowance` | `clinic_ai_coverage.allowance` |
| `used` | `clinic_ai_coverage.used` |
| `queued_count` | `clinic_ai_coverage.queued_count` |
| `held_count` | `clinic_ai_coverage.held_count` |
| `subscription_ref` | SQL: `AIC-` plus the first 8 Crockford base-32 characters of SHA-256(`sub-ref:` ‖ `current_org_id()::text`). Same value as `subscriptionRef` in `packages/vendor-contracts/src/identifiers.ts` |
| `abo_base_url` | `auth_internal.ai_app_setting_text('ai.abo_base_url', 'http://127.0.0.1:8788')` |

When the projection row is absent, or a copied column is null, that JSON value is null. `subscription_ref` and `abo_base_url` do not depend on the row.

## 4. Read sources

| Source | Use |
| --- | --- |
| `ai_internal.clinic_ai_coverage` | One row per `organization_id`. Columns listed in sections 2 and 3. Written by the P5.2a pull. This unit only reads it |
| `ai_internal.feed_state.last_success_at` | Singleton row (`singleton = true`). Input to `stale` only |
| `ai_internal.app_settings` | `ai.platform_base_url` and `ai.abo_base_url` through `auth_internal.ai_app_setting_text` |
