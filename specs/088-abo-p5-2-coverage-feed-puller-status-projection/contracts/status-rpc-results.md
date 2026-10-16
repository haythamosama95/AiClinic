# Status RPC results

Frozen for P6.x. CP-D. All three RPCs are `SECURITY DEFINER` in `public`, delegate to `auth_internal`, and return `public.rpc_result` `(success, data, error_code, error_message, contract_version)`.

Accepted `p_contract_version` values are `backendRpc` minimum and current from `ai.contract_versions`: 0 and 1. Success sets `contract_version` to the version the request used.

A missing version, or any integer other than 0 or 1, returns `success = false`, `error_code = 'CONTRACT_VERSION_UNSUPPORTED'`, `error_message` a short refusal, `contract_version = 1`, and `data = {"accepted_versions": [0, 1]}`. On `request_ai_status_refresh` that refusal happens before authentication and before a pull. Nothing is written.

`RATE_LIMITED` and `FORBIDDEN_ROLE` set `contract_version` to the accepted request version, `success = false`, and `data` null.

## 1. `get_ai_status(p_contract_version)`

Every member of `current_org_id()`. `data` on success:

| Field | JSON |
| --- | --- |
| `available` | boolean. True only for returned state `active` or `grace` |
| `state` | `none`, `suspended`, `active`, `grace`, `lapsed`, or the stored state |
| `reason` | JSON null for returned `active`, `grace`, or `suspended`. `none` when the projection row is absent. `expired` when stored `active` or stored `grace` becomes `lapsed` at read time. Otherwise the stored `reason` |
| `days_left` | integer or null. Whole 24-hour days from `now()` until `ends_at`, floored. Null when the row is absent, `ends_at` is null, or `now() >= ends_at`. A null does not raise `ends_soon` |
| `band` | stored `band`, or null when the row is absent |
| `notices` | array of records in §3 |
| `next_change_at` | the earlier of `ends_at` and `grace_ends_at` that is still after `now()`, or null |
| `as_of` | `now()` at the read |
| `stale` | true when `feed_state.last_success_at` is null or older than 2 minutes |
| `platform_base_url` | stored `ai.platform_base_url` |

No price, payment, or reference field. The read does not update `clinic_ai_coverage` or `feed_state`.

Read-time state for that row and `now()`:

1. No row: `state = none`, `available = false`, `reason = none`.
2. `suspended` is true: `state = suspended`, `available = false`, `reason = null`. This step wins over the clock.
3. Stored `active`: `active` while `now() < ends_at`; still `active` when `now() >= ends_at` and `queued_count > 0`; otherwise `grace` while `now() < grace_ends_at`; otherwise `lapsed`. `reason` is null for `active` and `grace`, and `expired` for `lapsed`.
4. Stored `grace`: `grace` while `now() < grace_ends_at`, then `lapsed` with `reason = expired`.
5. Any other stored state stays as stored and is unavailable. `reason` is the stored column.

## 2. Notice records

Each element is `{code, audience, channel}`. `audience` is `member`. `channel` is `in_app`. `in_grace` also has `grace_days_left`: a non-negative integer, the whole 24-hour days from `now()` until `grace_ends_at`, floored. Every other code omits `grace_days_left`. The same array is returned to every member. Order is the table order, skipping codes that are not raised.

| `code` | Raised when |
| --- | --- |
| `ends_soon` | `days_left` is 0, 1, 3, or 7, and `queued_count = 0` |
| `in_grace` | returned state is `grace` |
| `allowance_low` | `band` is `75` or `90` |
| `allowance_exhausted` | returned state is `exhausted` |
| `lapsed` | returned state is `lapsed` |
| `ended_reversed` | returned state is `reversed` |
| `suspended` | `suspended` is true |
| `status_stale` | `stale` is true |

## 3. `get_ai_billing_status(p_contract_version)`

Administrator only. A caller whose `current_membership_role()` is not `administrator` gets `FORBIDDEN_ROLE`, no status payload, and no write.

Success `data` is the §1 object plus these flat fields. There is no `remaining` field and no nested `term` object. A missing projection row, or a null column, is JSON null.

| Field | Source |
| --- | --- |
| `plan_display_name` | `clinic_ai_coverage.plan_display_name` |
| `starts_at` | `starts_at` |
| `ends_at` | `ends_at` |
| `grace_ends_at` | `grace_ends_at` |
| `allowance` | `allowance` |
| `used` | `used` |
| `queued_count` | `queued_count` |
| `held_count` | `held_count` |
| `subscription_ref` | [data-model.md](../data-model.md) §4 |
| `abo_base_url` | stored `ai.abo_base_url` |

`notices`, `days_left`, and `reason` are the §1 and §2 values.

## 4. `request_ai_status_refresh(p_contract_version)`

Administrator only. Non-administrators get `FORBIDDEN_ROLE`, no pull, and no write to `status_refresh`.

Success `data` is `{"requested_at": "<timestamptz>"}` using the stored `requested_at`. The call upserts that timestamp and then runs `auth_internal.pull_coverage_feed()` once.

When the row exists and `now() - requested_at < interval '10 seconds'`, the result is `RATE_LIMITED`. `requested_at` is unchanged and the pull does not run.
