# Billing

- Purpose: Document the billing domain schema, invoice lifecycle, payment rules, and current frontend implementation status.
- Read this when: implementing invoice UI, payment flows, insurance settings, or billing RPC integrations.
- Canonical for: billing tables, RPC inventory, permission keys, and business rules for V1-6.
- Usually paired with: `docs/architecture/05-database.md`, `docs/architecture/07-frontend.md`, `docs/architecture/09-security-rbac.md`, `docs/specs/007-billing/`.
- Not covered here: V3-2 advanced billing (overdue automation, claim tracking), analytics revenue views.

---

## Implementation Status

| Layer | Status |
| ----- | ------ |
| Backend (migrations + RPCs) | **Complete** — `20260605180000_billing.sql` and US1–US8 follow-ups |
| SQL tests | **Complete** — `run_billing_tests.sh` |
| Frontend data/domain | **Complete** — `frontend/lib/features/billing/data/`, `domain/`, `application/` |
| Frontend presentation | **Complete** — `frontend/lib/features/billing/presentation/` |

Operator walkthrough for backend verification: `docs/specs/007-billing/quickstart.md`.

## Schema

### Tables

| Table | Scope | Notes |
| ----- | ----- | ----- |
| `invoices` | branch + org | One active invoice per visit (partial unique index); links `patient_id`, `visit_id` |
| `invoice_items` | per invoice | Line items with quantity, unit price, computed total |
| `payments` | per invoice | Append-only; corrections via `record_refund` |
| `insurance_providers` | **organization** | Not branch-scoped; `organization_id` FK; unique name per org |
| `organization_billing_settings` | organization | e.g. `allow_partial_payments` toggle |
| `invoice_number_sequences` | per branch | Generates `INV-{branch_code}-{seq}` on issue |

### Invoice Status Enum

```sql
CREATE TYPE public.invoice_status AS ENUM (
  'draft', 'issued', 'partially_paid', 'paid', 'voided'
);
```

There is **no** `overdue` or `cancelled` status. Voiding uses `voided` with `void_reason`, `voided_at`, `voided_by`. Overdue detection is deferred to V3-2.

### Key Business Rules

- **Draft lifecycle**: `create_invoice_from_visit` → add/update/remove items → `issue_invoice`.
- **Discounts**: line-level (`apply_line_discount`) and invoice-level (`apply_invoice_discount`) are **mutually exclusive** on draft invoices.
- **Insurance**: `set_insurance_coverage` + org-scoped `insurance_providers`; coverage capped at subtotal minus discount.
- **Payments**: `record_payment` respects `allow_partial_payments` setting (default off); only administrator can toggle via `update_billing_settings`.
- **Refunds**: `record_refund` — payments table is append-only; no UPDATE/DELETE grants.
- **Void**: `void_invoice` on `issued` or `partially_paid` only; paid invoices require refunds first.
- **Branch code**: `branches.code` required before issue; missing code returns `branch_code_missing`.

## RPC Inventory

| Public Wrapper | Purpose |
| -------------- | ------- |
| `create_invoice_from_visit` | Draft from completed visit |
| `discard_draft_invoice` | Remove draft |
| `add_invoice_item`, `update_invoice_item`, `remove_invoice_item` | Line item CRUD |
| `issue_invoice` | Assign number, set `issued` |
| `void_invoice` | Void with reason |
| `get_invoice_detail`, `list_invoices`, `list_patient_invoices` | Reads |
| `record_payment`, `record_refund` | Payment ledger |
| `apply_line_discount`, `apply_invoice_discount` | Discount scopes |
| `set_insurance_coverage` | Coverage amount on draft |
| `insurance_provider_upsert`, `insurance_provider_deactivate`, `list_insurance_providers` | Provider catalog |
| `get_billing_settings`, `update_billing_settings` | Org billing settings |

## Permissions

| Permission | Purpose |
| ---------- | ------- |
| `invoices.view` | List and detail |
| `invoices.create` | Create draft from visit |
| `invoices.apply_discount` | Line and invoice discounts |
| `invoices.void` | Void issued invoices |
| `payments.record` | Record patient/insurance payments |
| `payments.refund` | Record refunds |
| `insurance.manage` | Provider CRUD |
| `settings.billing.manage` | Toggle partial payments and org billing settings |

`invoices.apply_discount_above_threshold` from early specs was superseded by granular discount permissions checked inside RPCs.

## RLS Summary

- `invoices`, `invoice_items`, `payments`: branch-scoped SELECT via JWT `branch_ids`.
- `insurance_providers`, `organization_billing_settings`: organization-scoped.
- All mutations blocked on tables; writes via SECURITY DEFINER RPCs only.
- `REVOKE UPDATE, DELETE ON payments` — append-only ledger.

## Frontend (Current)

```
frontend/lib/features/billing/
├── data/           # InvoiceRepository, PaymentRepository, InsuranceProviderRepository, BillingSettingsRepository
├── domain/         # Invoice, InvoiceItem, Payment, InsuranceProvider, Money, DiscountKind/Scope, InvoiceActionPolicy
├── application/    # billing_rpc_messages.dart — RPC error-code → user-facing message mapping
└── presentation/   # Pages, providers, widgets (invoice list/detail/editor, payment form, visit billing flow)
```

No use-case layer exists yet (unlike `patients`/`settings`); repositories call RPCs directly from notifiers.

Implemented surfaces:

- Invoice list, editor, and detail pages
- Settings → Billing (`BillingSettingsPage` — partial payments toggle, permission-gated)
- Visit detail **Create invoice** / **Open invoice** action
- Patient profile billing section
- Draft editor: line items, invoice/line discounts (mutually exclusive), insurance coverage, discard draft

Deferred:

- Insurance provider catalog management page (`/billing/insurance-providers` remains a placeholder)

## Testing

- `backend/tests/billing_crud.sql`, `billing_rls.sql`, `billing_concurrency.sql`
- Orchestrator: `backend/tests/run_billing_tests.sh`
- Not in CI — manual/local only (see `ARCHITECTURAL_FLAWS.md`)
