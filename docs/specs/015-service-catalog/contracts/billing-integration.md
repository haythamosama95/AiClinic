# Contract: Billing Integration (invoice_items)

**Feature**: 015-service-catalog | **Migration**: `20260712091500_service_catalog_billing_integration.sql`

This is the single cross-feature coupling: catalog selection replaces free-text invoice item authoring from `007-billing`.

## Schema change (additive)

```sql
ALTER TABLE public.invoice_items
  ADD COLUMN service_id uuid REFERENCES public.services (id);
CREATE INDEX invoice_items_service_idx ON public.invoice_items (service_id) WHERE is_deleted = false;
```

- `service_id` nullable (historical rows have none); new authoring MUST populate it.
- `description` is repurposed as the **service name snapshot** for catalog items; `unit_price`, `quantity`, `line_subtotal`, `line_total`, and line-discount columns are reused unchanged.
- Existing `invoice_items` RLS and billing SELECTs are unchanged.

## `add_invoice_item_from_service` (public RPC)

Replaces the editor's free-text `add_invoice_item` path. Draft-only, snapshot-at-add, create-or-increment.

**Params**: `p_invoice_id uuid`, `p_expected_updated_at timestamptz`, `p_service_id uuid`

**Behavior**:
1. assert `invoices.create`.
2. `auth_internal.lock_draft_invoice(p_invoice_id, p_expected_updated_at)` → draft check + branch scope + `STALE_INVOICE`.
3. Derive the invoice's `branch_id`; compute `on_date := current_date` (add-to-invoice date, FR-010).
4. `auth_internal.resolve_effective_service_price(p_service_id, branch_id, on_date)`; if `eligible=false` → `SERVICE_NOT_ELIGIBLE` (with `reason`).
5. **Create-or-increment** (FR-015): if a non-deleted `invoice_items` row for this invoice already has `service_id = p_service_id`, increment its `quantity` by 1 and recompute `line_subtotal`/`line_total` from its **existing snapshot** `unit_price` (do not re-resolve); else insert a new item with `service_id`, `description = service.name` (snapshot), `unit_price = resolved`, `quantity = 1`, computed totals.
6. `auth_internal.refresh_invoice_subtotal(p_invoice_id)`.
7. audit `invoice.item.add_from_service` with `{ service_id, unit_price, applied_rule, on_date }`.

**Success data**: `{ "item_id": uuid, "quantity": "2", "unit_price": "120.00", "applied_rule": "promo" }`

## Quantity edit (reuse existing billing RPC)

Changing quantity continues to use the existing billing `update_invoice_item` path but the client **exposes only quantity** (unit price read-only, FR-014). The snapshot `unit_price` is never re-resolved or user-typed. (If the existing `update_invoice_item` requires description/unit_price params, pass back the stored snapshot values unchanged; no new RPC required.)

## Editor path change

- The billing invoice editor stops calling free-text `add_invoice_item`; the free-text description input is removed (FR-012).
- `frontend/lib/features/billing/presentation/widgets/invoice_items_editor.dart` embeds the new `InvoiceServiceSelector` (from the service_catalog feature) which calls `search_eligible_services` for the invoice branch and, on selection, calls `add_invoice_item_from_service`.
- Legacy `add_invoice_item` remains defined for backward data integrity but is no longer invoked for new authoring.

## Error codes (this file)

`FORBIDDEN`, `STALE_INVOICE`, `NOT_FOUND`, `SERVICE_NOT_ELIGIBLE` (reason: `GLOBAL_INACTIVE`|`NOT_ASSIGNED`|`BRANCH_INACTIVE`).
