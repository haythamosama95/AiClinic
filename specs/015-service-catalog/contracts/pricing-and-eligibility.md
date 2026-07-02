# Contract: Pricing, Eligibility & Catalog Read RPCs

**Feature**: 015-service-catalog | **Migration**: `20260712091000_service_catalog_pricing_rpcs.sql`

Same envelope conventions. Read RPCs are gated for catalog viewing (`services.view` or `services.manage`) or, for selection, `invoices.create`. A shared internal helper backs both price preview and add-to-invoice so pricing is computed once (server-authoritative, FR-026/NFR-008).

## Internal helper (not a public RPC)

`auth_internal.resolve_effective_service_price(p_service_id uuid, p_branch_id uuid, p_on_date date) RETURNS jsonb`

Returns:
```json
{ "eligible": true, "unit_price": "120.00", "applied_rule": "promo|override|default", "reason": null }
```
- `eligible=false` with `reason` in { `GLOBAL_INACTIVE`, `NOT_ASSIGNED`, `BRANCH_INACTIVE` } and `unit_price=null` when ineligible.
- Resolution when eligible: promo (if `p_on_date BETWEEN start AND end`) → override (if set) → default. `unit_price` returned as scale-2 string (wire format matching `Money.wireValue`).

## `resolve_effective_service_price` (public read)

Price preview for the UI.

**Params**: `p_service_id uuid`, `p_branch_id uuid`, `p_on_date date` (default `current_date`)

**Behavior**: assert read access (`services.view`/`services.manage`, or `invoices.create` for the branch); branch in `jwt_branch_ids()`; return the helper's jsonb inside `rpc_success`.

**Success data**: the helper object above.

## `search_eligible_services` (public read — invoice selector)

Type-ahead search of services **eligible** for a given branch/date, for the billing invoice editor.

**Params**: `p_branch_id uuid`, `p_query text` (default `''`), `p_on_date date` (default `current_date`), `p_limit int` (default 20, clamped 1..50)

**Behavior**: assert `invoices.create` (or `services.view`/`services.manage`) for the branch; branch in `jwt_branch_ids()`; return only eligible services (global active + assigned + branch-active) whose name `ILIKE '%query%'`, each with resolved price + `on_promotion` flag.

**Success data**:
```json
{ "items": [ { "service_id": uuid, "name": "Consultation", "unit_price": "120.00", "applied_rule": "promo", "on_promotion": true } ] }
```

## `list_services` (public read — management surface)

Paginated catalog browse with filters (US6).

**Params**: `p_query text` (nullable), `p_global_status text` (nullable `active`|`inactive`), `p_branch_id uuid` (nullable filter), `p_limit int` (default 25, clamped 1..100), `p_offset int` (default 0)

**Behavior**: assert `services.view` or `services.manage`; org scope; exclude soft-deleted; when `p_branch_id` set, restrict to services assigned to that branch and include that branch's status/effective price summary; order by `name`.

**Success data**:
```json
{
  "total": 137,
  "items": [
    {
      "service_id": uuid,
      "name": "Consultation",
      "default_price": "200.00",
      "global_status": "active",
      "assigned_branch_count": 3,
      "updated_at": "…",
      "branch_summary": { "status": "active", "effective_price": "150.00", "on_promotion": false }
    }
  ]
}
```
(`branch_summary` present only when `p_branch_id` is provided.)

## `get_service` (public read — editor load)

Load one service with its full per-branch configuration for the editor (backend-first fetch, FR-028).

**Params**: `p_service_id uuid`

**Behavior**: assert `services.view`/`services.manage`; org scope; return the service plus all its non-deleted `service_branches` rows (status, override, promotion) limited to branches in `jwt_branch_ids()`.

**Success data**:
```json
{
  "service": { "id": uuid, "name": "…", "default_price": "200.00", "global_status": "active", "updated_at": "…" },
  "branches": [
    { "service_branch_id": uuid, "branch_id": uuid, "status": "active",
      "price_override": "150.00", "promotion_price": "100.00",
      "promotion_start_date": "2026-01-01", "promotion_end_date": "2026-01-31", "updated_at": "…" }
  ]
}
```

## Error codes (this file)

`FORBIDDEN`, `NOT_FOUND`, `BRANCH_NOT_IN_ORG`.
