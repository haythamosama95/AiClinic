# Contract: Billing Queries (V1-6)

Read paths. All reads honor branch RLS for invoices/items/payments and org RLS for insurance providers and billing settings. Clients MUST perform a backend-first fetch (FR-030) before rendering actionable content.

---

## `get_invoice_detail(p_invoice_id uuid) RETURNS jsonb`

Returns a single JSON envelope containing:

```jsonc
{
  "invoice": {
    "id": "...", "invoice_number": "INV-MAIN-000123",
    "status": "partially_paid",
    "branch_id": "...", "patient_id": "...", "visit_id": "...",
    "subtotal": "150.00",
    "discount_kind": null, "discount_value": null, "discount_amount": "0.00",
    "insurance_provider_id": "...", "insurance_covered_amount": "50.00",
    "currency": "USD",
    "issued_at": "...", "voided_at": null, "void_reason": null,
    "balance": "30.00",                  // server-computed source of truth
    "updated_at": "..."                  // for optimistic concurrency
  },
  "items": [
    {
      "id": "...",
      "description": "Consultation",
      "quantity": "1.00", "unit_price": "100.00",
      "line_subtotal": "100.00",
      "line_discount_kind": "percentage", "line_discount_value": "10.00",
      "line_discount_amount": "10.00",
      "line_total": "90.00"
    }
  ],
  "payments": [
    { "id": "...", "method": "cash", "amount": "70.00",
      "reference": null, "note": null,
      "recorded_by": { "id": "...", "display_name": "Reception" },
      "recorded_at": "..." }
  ],
  "patient": { "id": "...", "display_name": "..." },
  "branch":  { "id": "...", "code": "MAIN", "name": "..." },
  "insurance_provider": { "id": "...", "name": "..." }
}
```

**Errors**: `permission_denied`, `not_found` (also returned for cross-branch access — never leak existence).

---

## `list_invoices(p_filters jsonb, p_limit int, p_offset int) RETURNS TABLE(...)`

Filters supported in `p_filters`:

- `branch_ids` (array; intersected with JWT scope)
- `statuses` (array of `invoice_status`)
- `patient_id` (uuid)
- `visit_id` (uuid; exact match on `invoices.visit_id`)
- `patient_search` (text, ILIKE on patient name)
- `invoice_number` (text exact or prefix)
- `date_from`, `date_to` (timestamptz; applied to `created_at`)

Returns rows with `id`, `invoice_number`, `status`, `patient_display_name`, `branch_code`, `subtotal`, `discount_amount`, `insurance_covered_amount`, `paid_amount`, `balance`, `created_at`, `issued_at`. Sorted by `created_at DESC` by default. Pagination via `p_limit`/`p_offset`; clients SHOULD use cursor pagination once result sets exceed ~1000 rows.

---

## `list_patient_invoices(p_patient_id uuid, p_limit int, p_offset int) RETURNS TABLE(...)`

Convenience query for the patient profile billing tab. Same row shape as `list_invoices` filtered to the patient and intersected with caller branch scope.

---

## `get_billing_settings() RETURNS jsonb`

Returns `{ "allow_partial_payments": true|false }` for the caller's organization.

**Permission**: any user with `invoices.view` OR `payments.record` may read (UI needs this to render correct affordances). Mutation goes through `update_billing_settings`.

**Errors**: `permission_denied` if caller has neither key.

---

## `list_insurance_providers(p_only_active boolean) RETURNS TABLE(...)`

Returns org-scoped providers. UI uses `p_only_active = true` in the invoice editor selector and `false` in the management page.

---

## Receipt payload

The receipt print preview is rendered client-side from `get_invoice_detail` plus the organization header (already cached from V1-2). No separate RPC; the client supplies the additional org header from its existing organization context store.

## Backend-first contract

For invoice list, invoice detail, payment screens, and billing settings UI, the client MUST call the corresponding query RPC and reconcile state before enabling actionable controls. Cached/local state MAY be shown only as a transient loading placeholder (FR-030).
