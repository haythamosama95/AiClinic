# Data model: P5.2 coverage projection and status

Entities are the ones in spec §3.2, plus `ai_internal.status_refresh` from the binding assumption in `escalations.md` §1. The migration is `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql`. It does not edit `20260802140000_ai_availability_flag.sql`, `20260821120000_fix_get_ai_availability_security_definer.sql`, `20260905120100_set_ai_availability_rpc.sql`, or `20260905120400_fix_set_ai_availability_created_by.sql`.

All three tables are in non-exposed `ai_internal`. RLS is on with a deny-all policy. No grant to `anon`, `authenticated`, or `service_role`. Clinic roles reach them only through the definer functions in `plan.md`.

## 1. `ai_internal.clinic_ai_coverage`

One row per clinic. Primary key `organization_id`.

| Column | Type | Notes |
| --- | --- | --- |
| `organization_id` | `uuid` primary key | Event `org_id` |
| `installation_id` | `uuid` not null | |
| `binding_epoch` | `bigint` not null | |
| `clinic_seq` | `bigint` not null | |
| `state` | `text` not null | Snapshot `state` |
| `reason` | `text` | Null when the applied snapshot `state` is `active` or `grace`. Otherwise the snapshot `reason`: `none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, or `transfer_pending`. Status reads do not update it |
| `term_ref` | `text` | Snapshot `term.ref`, null when `term` is null |
| `plan_display_name` | `text` | From `term` |
| `starts_at` | `timestamptz` | From `term` |
| `ends_at` | `timestamptz` | From `term`. `days_left` counts toward this column |
| `grace_ends_at` | `timestamptz` | From `term` |
| `allowance` | `integer` | From `term` |
| `used` | `integer` | From `term` |
| `band` | `text` | `ok`, `75`, `90`, or `exhausted` |
| `queued_count` | `integer` not null | |
| `held_count` | `integer` not null | |
| `suspended` | `boolean` not null | |
| `event_at` | `timestamptz` not null | Event `at` |
| `applied_at` | `timestamptz` not null | `now()` when the pull applies the event |

No `contract_version` column. No price column and no provider column. Feed upserts replace the row only when `(binding_epoch, clinic_seq)` is greater than the stored pair: a higher epoch wins, and an equal epoch wins only with a higher `clinic_seq`. A missing row accepts the first event. An older pair is ignored. The comparison is the only writer of these columns.

## 2. `ai_internal.feed_state`

One row. Primary key `singleton boolean` with `CHECK (singleton)`. The migration inserts `singleton = true`, `cursor = 0`, `consecutive_failures = 0`, and nulls for the other columns.

| Column | Type | Notes |
| --- | --- | --- |
| `singleton` | `boolean` primary key | Always `true` |
| `cursor` | `bigint` not null | Feed `after`. Rebuild sets this to 0 from the database owner. No clinic RPC writes it |
| `pending_request_id` | `bigint` | `net.http_get` id |
| `pending_since` | `timestamptz` | When that id was stored |
| `last_success_at` | `timestamptz` | Set to `now()` only when a page is applied. `stale` is true when this is null or older than 2 minutes |
| `consecutive_failures` | `integer` not null | Incremented by 1 on a failed or abandoned page. Set to 0 when a page is applied |

This row is not a per-tenant refresh clock. Feed upserts do not write `status_refresh`.

## 3. `ai_internal.status_refresh`

Per tenant. Primary key `organization_id`.

| Column | Type | Notes |
| --- | --- | --- |
| `organization_id` | `uuid` primary key | `current_org_id()` |
| `requested_at` | `timestamptz` not null | Written only when `request_ai_status_refresh` accepts the call |

Accept when the row is absent or `now() - requested_at >= interval '10 seconds'`. A closer call does not change `requested_at`.

## 4. `subscription_ref`

Computed inside `get_ai_billing_status` for `current_org_id()`. It is not a column. The text is `AIC-` plus the first 8 characters of the Crockford encoding of SHA-256 of the UTF-8 bytes of `sub-ref:` concatenated with `organization_id::text`.

Crockford alphabet: `0123456789ABCDEFGHJKMNPQRSTVWXYZ`. Bytes are encoded 5 bits at a time, most significant bit first, and a trailing partial group is padded, matching `subscriptionRef` in `packages/vendor-contracts/src/identifiers.ts`. The UUID text is the lowercase hyphenated form PostgreSQL emits, the same text `issue_billing_token` puts in the `org` claim.

## 5. Dropped availability

`public.get_ai_availability()`, `auth_internal.get_ai_availability()`, `public.set_ai_availability(boolean, text)`, and `auth_internal.set_ai_availability(boolean, text)` are dropped. The `ai.availability` row is deleted from `ai_internal.app_settings`. No replacement RPC writes status.
