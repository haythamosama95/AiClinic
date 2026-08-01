# Contract: Service Management RPCs

**Feature**: 015-service-catalog | **Migration**: `20260712090500_service_catalog_rpcs.sql`

Conventions (all RPCs): defined in `auth_internal.*` (`SECURITY DEFINER`, `SET search_path = public`) with a thin `public.*` wrapper (`SECURITY INVOKER`, `GRANT EXECUTE ... TO authenticated`). Return `public.rpc_result` (`public.rpc_success(jsonb)` / `public.rpc_error(code, msg)`). Permission via `auth_internal.assert_permission('services.manage')`. Org scope via `public.jwt_organization_id()`. Every mutation writes `public.audit_log` (`user_id`, `organization_id`, `action`, `table_name`, `record_id`, `old_data_json`/`new_data_json`). Client calls the **public** name via `AppRpcInvoker.invokeRpc`.

## `create_service`

Create a service and its initial branch assignments.

**Params**
- `p_name text`
- `p_default_price numeric`
- `p_global_status text` (`active`|`inactive`, default `active`)
- `p_assign_all_branches boolean`
- `p_branch_ids uuid[]` (used when `p_assign_all_branches = false`)

**Behavior**: assert `services.manage`; trim/validate name and uniqueness (case-insensitive, non-deleted) → `DUPLICATE_NAME`; validate `default_price >= 0` → `INVALID_PRICE`; insert `services`; expand assignment to `service_branches` rows (all current org branches, or the provided branch ids — each validated to belong to the org → `BRANCH_NOT_IN_ORG`) with `status='active'`, null override/promotion; audit `service.create` + `service.branch.assign`.

**Success data**: `{ "service_id": uuid, "assigned_branch_ids": uuid[] }`

## `update_service`

Update name / default price / global status. Never touches historical invoice items.

**Params**: `p_service_id uuid`, `p_expected_updated_at timestamptz`, `p_name text`, `p_default_price numeric`, `p_global_status text`

**Behavior**: assert `services.manage`; lock row `FOR UPDATE`; org scope check → `NOT_FOUND`; optimistic concurrency vs `updated_at` → `STALE_SERVICE`; name uniqueness on change → `DUPLICATE_NAME`; price validity → `INVALID_PRICE`; **invariant guard**: if lowering `default_price` would leave any branch with `price_override IS NULL` and an existing `promotion_price > new default_price`, reject → `PROMO_EXCEEDS_PRICE` (with offending branch ids in message); apply update; audit `service.update` with old/new.

**Success data**: `{ "service_id": uuid, "updated_at": timestamptz }`

## `set_service_global_status`

Convenience/explicit toggle (may be folded into `update_service`).

**Params**: `p_service_id uuid`, `p_expected_updated_at timestamptz`, `p_global_status text`

**Behavior**: assert `services.manage`; concurrency; set `global_status`; audit `service.status`. `inactive` ⇒ non-selectable everywhere (enforced by resolution/eligibility, no data change to branch rows).

**Success data**: `{ "service_id": uuid, "global_status": text, "updated_at": timestamptz }`

## `set_service_branch_assignment`

Assign or unassign branches for a service.

**Params**: `p_service_id uuid`, `p_branch_ids uuid[]`, `p_assign boolean` (true=assign, false=unassign)

**Behavior**: assert `services.manage`; validate branches in org; when assigning, upsert non-deleted `service_branches` rows (`status='active'`, null override/promotion) — reactivate a previously soft-deleted row rather than duplicate; when unassigning, **soft-delete** the `service_branches` rows (retains history) → their branches become ineligible; audit `service.branch.assign` / `service.branch.unassign`.

**Success data**: `{ "service_id": uuid, "assigned_branch_ids": uuid[], "unassigned_branch_ids": uuid[] }`

## `soft_delete_service`

**Params**: `p_service_id uuid`, `p_expected_updated_at timestamptz`

**Behavior**: assert `services.manage`; concurrency; set `is_deleted=true`, `deleted_at`, `deleted_by`; also soft-delete child `service_branches`; the service disappears from selectors/lists but remains referenced by historical `invoice_items` for display. Hard delete is never performed → referenced or not, the operation is always a soft delete. Audit `service.delete`.

**Success data**: `{ "service_id": uuid }`

## Error codes (this file)

`FORBIDDEN`, `NOT_FOUND`, `STALE_SERVICE`, `DUPLICATE_NAME`, `INVALID_PRICE`, `BRANCH_NOT_IN_ORG`, `PROMO_EXCEEDS_PRICE`.
