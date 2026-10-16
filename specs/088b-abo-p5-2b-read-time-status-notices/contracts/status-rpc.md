# Status RPC results and notice codes

Frozen for P6.x. Shape of `public.get_ai_status(p_contract_version integer)` and `public.get_ai_billing_status(p_contract_version integer)`. Field rules are in [data-model.md](../data-model.md).

## 1. Envelope

Both RPCs return `public.rpc_result`:

| Field | Success | Refusal |
| --- | --- | --- |
| `success` | `true` | `false` |
| `data` | JSON object in the sections below | `FORBIDDEN_ROLE`: `null`. `CONTRACT_VERSION_UNSUPPORTED`: `{"accepted_versions": [0, 1]}`, the payload `public.get_ai_status` already returns |
| `error_code` | `null` | Code in section 5 |
| `error_message` | `null` | Text |
| `contract_version` | The `p_contract_version` the request used | On `CONTRACT_VERSION_UNSUPPORTED`, `1`. On `FORBIDDEN_ROLE`, the accepted request version |

Accepted versions are `0` and `1` (`ai.contract_versions.backendRpc` current 1, minimum 0). A null argument and any other integer are unsupported. The check runs in the public wrapper before the reader and before the billing role check, and it writes nothing.

## 2. `get_ai_status` success `data`

Keys, and no others:

`available`, `state`, `reason`, `days_left`, `band`, `notices`, `next_change_at`, `as_of`, `stale`, `platform_base_url`.

`as_of` is the call's `now()` and is present when the clinic has no projection row. `notices` order is not significant. `grace_days_left` appears only on the `in_grace` element and is omitted on every other element.

## 3. `get_ai_billing_status` success `data`

Every key in section 2, plus:

`plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, `subscription_ref`, `abo_base_url`.

There is no `remaining` key. A copied projection field is JSON `null` when the row is absent or that column is null.

`subscription_ref` is `AIC-` plus the first 8 Crockford base-32 characters of SHA-256 of the UTF-8 string `sub-ref:` concatenated with `current_org_id()::text`. Alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`. For org `7c9e6679-7425-40de-944b-e07fc1f90ae7` the value is `AIC-2W3W7P9G`.

## 4. Notice codes

Closed set. Each element is `{code, audience, channel}`. `audience` is `member`. `channel` is `in_app`.

| `code` | When |
| --- | --- |
| `ends_soon` | `days_left` is 7, 3, or 1 or fewer, and `queued_count = 0`. Null `days_left` does not match |
| `in_grace` | `state` is `grace`. Also carries `grace_days_left` |
| `allowance_low` | `band` is `75` or `90` |
| `allowance_exhausted` | `state` is `exhausted` |
| `lapsed` | `state` is `lapsed` |
| `ended_reversed` | `state` is `reversed` |
| `suspended` | The suspended flag is true |
| `status_stale` | `stale` is true |

## 5. Refusals

| RPC | Condition | `error_code` | `data` |
| --- | --- | --- | --- |
| Either | `p_contract_version` is null or not `0` or `1` | `CONTRACT_VERSION_UNSUPPORTED` | `{"accepted_versions": [0, 1]}` |
| `get_ai_billing_status` | Membership role is not `administrator` | `FORBIDDEN_ROLE` | `null` |

`get_ai_status` has no role refusal. A member of the active organisation receives the status view.

## 6. `reason`

| Returned `state` | `reason` |
| --- | --- |
| Row absent (`state` `none`) | `none` |
| `active`, `grace`, or `suspended` | JSON `null` |
| `lapsed` because stored `active` or stored `grace` crossed `grace_ends_at` on this read | `expired` |
| Any other stored state, including a row already stored as `lapsed` | The stored `clinic_ai_coverage.reason` (`none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, or `transfer_pending`) |

The read does not write `clinic_ai_coverage.reason`.
