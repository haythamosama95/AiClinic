# Data Model: Billing (V1-6)

Introduces billing domain tables, enums, indexes, RLS, and the organization-level billing settings record. Builds on V1-1 auth, V1-2 org/branch/settings, V1-3 patients, V1-4 appointments, V1-5 visits.

## Migration: `20260605180000_billing.sql`

### ENUMs

```sql
CREATE TYPE public.invoice_status AS ENUM ('draft', 'issued', 'partially_paid', 'paid', 'voided');
CREATE TYPE public.payment_method AS ENUM ('cash', 'card', 'bank_transfer', 'insurance_settlement');
CREATE TYPE public.discount_kind  AS ENUM ('percentage', 'fixed');
```

### TABLE: `invoices`

| Column                     | Type                          | Notes                                                                                            |
| -------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `id`                       | uuid PK                       | `gen_random_uuid()`                                                                              |
| `organization_id`          | uuid FK → organizations       | Denormalized from branch for org-scoped reporting and FK consistency                             |
| `branch_id`                | uuid FK → branches            | Derived from visit; immutable                                                                    |
| `patient_id`               | uuid FK → patients            | Derived from visit; immutable                                                                    |
| `visit_id`                 | uuid FK → visits              | **NOT NULL** — every invoice tied to a `completed` visit (FR-006)                                |
| `invoice_number`           | text                          | NULL until issue; assigned `INV-<branch_code>-NNNNNN` (FR-008)                                   |
| `status`                   | invoice_status                | Default `draft`                                                                                  |
| `subtotal`                 | numeric(14,2)                 | `sum(invoice_items.line_total)`; frozen at issue                                                 |
| `discount_kind`            | discount_kind                 | NULL when no invoice-level discount                                                              |
| `discount_value`           | numeric(14,2)                 | Percentage 0–100 or fixed amount; NULL when no invoice-level discount                            |
| `discount_amount`          | numeric(14,2)                 | Resolved invoice-level discount amount; default `0.00`; banker's rounding                        |
| `insurance_provider_id`    | uuid FK → insurance_providers | Nullable                                                                                         |
| `insurance_covered_amount` | numeric(14,2)                 | Default `0.00`; `0 ≤ amount ≤ subtotal − discount_amount`                                        |
| `currency`                 | text                          | Org currency code; default org setting                                                           |
| `issued_at`                | timestamptz                   | Set on issue; NULL while draft                                                                   |
| `void_reason`              | text                          | NULL except after void                                                                           |
| `voided_at`                | timestamptz                   | NULL except after void                                                                           |
| `voided_by`                | uuid FK → staff_members       | NULL except after void                                                                           |
| audit columns              | standard                      | `created_at`, `created_by`, `updated_at`, `updated_by`, `deleted_at`, `deleted_by` (soft delete) |

**Constraints / Indexes**:

- `CHECK (subtotal >= 0 AND discount_amount >= 0 AND insurance_covered_amount >= 0)`
- `CHECK ((discount_kind IS NULL) = (discount_value IS NULL))`
- `CHECK (discount_kind <> 'percentage' OR (discount_value BETWEEN 0 AND 100))`
- `CHECK (insurance_covered_amount <= subtotal - discount_amount)`
- `CHECK ((status = 'voided') = (voided_at IS NOT NULL) AND ((status = 'voided') = (void_reason IS NOT NULL)))`
- Partial unique: `UNIQUE (visit_id) WHERE status <> 'voided' AND deleted_at IS NULL` — one active invoice per visit (FR-005)
- Partial unique: `UNIQUE (branch_id, invoice_number) WHERE invoice_number IS NOT NULL`
- Indexes on `(branch_id, created_at DESC)`, `(patient_id, created_at DESC)`, `(visit_id)`, `(status, branch_id)`

### TABLE: `invoice_items`

| Column                 | Type          | Notes                                                             |
| ---------------------- | ------------- | ----------------------------------------------------------------- |
| `id`                   | uuid PK       |                                                                   |
| `invoice_id`           | uuid FK       | Cascade delete on hard delete (never used in app flows)           |
| `description`          | text NOT NULL | Max 500 chars                                                     |
| `quantity`             | numeric(14,2) | `> 0`                                                             |
| `unit_price`           | numeric(14,2) | `≥ 0`                                                             |
| `line_subtotal`        | numeric(14,2) | Computed `quantity * unit_price`, persisted on write              |
| `line_discount_kind`   | discount_kind | Nullable (mutually exclusive with invoice-level discount, FR-010) |
| `line_discount_value`  | numeric(14,2) | Nullable; percentage 0–100 or fixed ≤ `line_subtotal`             |
| `line_discount_amount` | numeric(14,2) | Default `0.00`; banker's rounding; `≤ line_subtotal`              |
| `line_total`           | numeric(14,2) | `line_subtotal - line_discount_amount`                            |
| audit columns          | standard      | Soft delete                                                       |

**Constraints**:

- `CHECK (quantity > 0 AND unit_price >= 0 AND line_subtotal = quantity * unit_price)`
- `CHECK ((line_discount_kind IS NULL) = (line_discount_value IS NULL))`
- `CHECK (line_discount_amount <= line_subtotal AND line_total = line_subtotal - line_discount_amount)`

### TABLE: `payments`

| Column        | Type                    | Notes                                                                         |
| ------------- | ----------------------- | ----------------------------------------------------------------------------- |
| `id`          | uuid PK                 |                                                                               |
| `invoice_id`  | uuid FK → invoices      |                                                                               |
| `branch_id`   | uuid FK → branches      | Denormalized from invoice for RLS                                             |
| `method`      | payment_method          |                                                                               |
| `amount`      | numeric(14,2)           | Signed; positive = payment, negative = refund; `<> 0`                         |
| `reference`   | text                    | Optional (transaction id, receipt number)                                     |
| `note`        | text                    | Optional; **required non-empty for refunds** (FR-016)                         |
| `recorded_by` | uuid FK → staff_members | Caller                                                                        |
| `recorded_at` | timestamptz             | Default `now()`                                                               |
| audit columns | standard                | `created_at`, `created_by`; **no `updated_at`, no soft delete** — append-only |

**Constraints / Grants**:

- `CHECK (amount <> 0)`
- `CHECK (amount > 0 OR (amount < 0 AND note IS NOT NULL AND length(trim(note)) > 0))`
- `REVOKE UPDATE, DELETE ON public.payments FROM PUBLIC, authenticated, anon` — append-only (D5)
- Indexes on `(invoice_id, recorded_at)`, `(branch_id, recorded_at DESC)`

### TABLE: `insurance_providers`

| Column            | Type                    | Notes          |
| ----------------- | ----------------------- | -------------- |
| `id`              | uuid PK                 |                |
| `organization_id` | uuid FK → organizations | Org-scoped     |
| `name`            | text NOT NULL           | Max 200 chars  |
| `contact_info`    | text                    | Optional       |
| `is_active`       | boolean                 | Default `true` |
| audit columns     | standard                | Soft delete    |

- `UNIQUE (organization_id, lower(name)) WHERE deleted_at IS NULL`

### TABLE: `organization_billing_settings`

| Column                   | Type                       | Notes                      |
| ------------------------ | -------------------------- | -------------------------- |
| `organization_id`        | uuid PK FK → organizations | One row per org            |
| `allow_partial_payments` | boolean NOT NULL           | Default `false` (FR-033)   |
| audit columns            | standard                   | `updated_at`, `updated_by` |

- Trigger `AFTER INSERT ON organizations`: insert row with defaults.
- Backfill migration: `INSERT ... SELECT id, false FROM organizations ON CONFLICT DO NOTHING`.

### TABLE: `invoice_number_sequences`

| Column       | Type                  | Notes                      |
| ------------ | --------------------- | -------------------------- |
| `branch_id`  | uuid PK FK → branches |                            |
| `last_value` | bigint NOT NULL       | Default `0`                |
| `updated_at` | timestamptz           | `now()` on every increment |

Row is created lazily on first issue at the branch. `assign_invoice_number(branch_id)` uses `SELECT ... FOR UPDATE` (D2).

## RLS Policies

| Table                           | Read                                                                                                        | Write                                                                      |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `invoices`                      | `branch_id = ANY(jwt.branch_ids)` AND `deleted_at IS NULL`                                                  | Deny direct; via RPC only                                                  |
| `invoice_items`                 | Joined via invoice with same branch scope                                                                   | Deny direct; via RPC only                                                  |
| `payments`                      | Branch scope joined via invoice                                                                             | Deny direct; via `record_payment` RPC only; UPDATE/DELETE revoked entirely |
| `insurance_providers`           | `organization_id = jwt.organization_id` AND `deleted_at IS NULL`                                            | Deny direct; via RPC only                                                  |
| `organization_billing_settings` | `organization_id = jwt.organization_id` (readable by any authenticated org member to render UI affordances) | Deny direct; via `update_billing_settings` RPC only                        |
| `invoice_number_sequences`      | No direct SELECT (RPC-internal table)                                                                       | Deny direct                                                                |

Cross-org and cross-branch reads MUST be denied. Soft-deleted rows excluded from all operational queries.

## Permission Keys (seeded)

| Key                       | Owner | Admin | Doctor | Receptionist | Lab Staff |
| ------------------------- | :---: | :---: | :----: | :----------: | :-------: |
| `invoices.view`           |   ✓   |   ✓   |        |      ✓       |           |
| `invoices.create`         |   ✓   |   ✓   |        |      ✓       |           |
| `invoices.apply_discount` |   ✓   |   ✓   |        |              |           |
| `invoices.void`           |   ✓   |   ✓   |        |              |           |
| `payments.record`         |   ✓   |   ✓   |        |      ✓       |           |
| `payments.refund`         |   ✓   |   ✓   |        |              |           |
| `insurance.manage`        |   ✓   |   ✓   |        |              |           |
| `settings.billing.manage` |   ✓   |   ✓   |        |              |           | (non-delegable per D10) |

## RPC Surface (PL/pgSQL under `auth_internal`, public wrappers)

| RPC                             | Inputs                                                                     | Returns                         | Notes                                                                                       |
| ------------------------------- | -------------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------- |
| `create_invoice_from_visit`     | `visit_id`                                                                 | `invoice_id`                    | Validates visit `completed`, branch scope, no active invoice; derives `branch/patient/org`. |
| `discard_draft_invoice`         | `invoice_id`, `expected_updated_at`                                        | void                            | Soft-deletes draft + items; releases visit (FR-009a).                                       |
| `add_invoice_item`              | `invoice_id`, `expected_updated_at`, item payload                          | `item_id`                       | Draft only; recomputes subtotal.                                                            |
| `update_invoice_item`           | `item_id`, `expected_updated_at`, item payload                             | void                            | Draft only.                                                                                 |
| `remove_invoice_item`           | `item_id`, `expected_updated_at`                                           | void                            | Draft only.                                                                                 |
| `apply_line_discount`           | `item_id`, `expected_updated_at`, `kind`, `value`                          | void                            | Draft + permission; rejected if invoice-level discount exists (D3).                         |
| `apply_invoice_discount`        | `invoice_id`, `expected_updated_at`, `kind`, `value` (NULL clears)         | void                            | Draft + permission; rejected if any line discount exists.                                   |
| `set_insurance_coverage`        | `invoice_id`, `expected_updated_at`, `provider_id`, `covered_amount`       | void                            | Draft only.                                                                                 |
| `issue_invoice`                 | `invoice_id`, `expected_updated_at`                                        | `invoice_number`                | Requires `branches.code IS NOT NULL`, ≥1 item; assigns number; freezes totals.              |
| `record_payment`                | `invoice_id`, `method`, `amount` (positive), `reference?`, `note?`         | `payment_id`                    | Locks invoice; checks balance and `allow_partial_payments` (D4); status transitions.        |
| `record_refund`                 | `invoice_id`, `method`, `amount` (positive value, stored negative), `note` | `payment_id`                    | Requires `payments.refund` + non-empty note; status transitions back.                       |
| `void_invoice`                  | `invoice_id`, `reason`                                                     | void                            | `issued`/`partially_paid` only; locks invoice.                                              |
| `get_invoice_detail`            | `invoice_id`                                                               | json (items, payments, balance) | Backend-first detail with server-computed balance.                                          |
| `list_invoices`                 | filters (status, branch, patient, date range, search)                      | rows + paging                   | Branch-scoped.                                                                              |
| `list_patient_invoices`         | `patient_id`, paging                                                       | rows                            | For patient profile billing tab.                                                            |
| `insurance_provider_upsert`     | id?, name, contact_info?, is_active                                        | `provider_id`                   | Permission-gated.                                                                           |
| `insurance_provider_deactivate` | `provider_id`                                                              | void                            | Permission-gated.                                                                           |
| `get_billing_settings`          | —                                                                          | `{ allow_partial_payments }`    | Read by any user with `invoices.view` OR `payments.record`.                                 |
| `update_billing_settings`       | `allow_partial_payments`                                                   | void                            | Requires `settings.billing.manage` AND caller role ∈ {owner, administrator}; audited.       |

All mutation RPCs write an `audit_log` row per FR-023 with prior/new values.

## Status Transitions (enforced in RPCs)

```
                    issue
       draft  ───────────────►  issued
         │                         │
         │ discard_draft           │ record_payment (partial)
         │ (soft delete)           ▼
         ▼                    partially_paid
      (gone)                       │
                                   │ record_payment (final) ─► paid
                                   │
                                   │ void_invoice (with reason)
                                   ▼
                                 voided    (terminal; locked)

   paid ──record_refund (raises balance)──► partially_paid | issued
```

## Failure Modes Reference

| Error code                   | When                                                                        |
| ---------------------------- | --------------------------------------------------------------------------- |
| `visit_not_completed`        | Visit referenced is not in `completed` status                               |
| `active_invoice_exists`      | Another non-voided, non-deleted invoice already references the visit        |
| `branch_code_missing`        | Issue attempted when `branches.code IS NULL`                                |
| `stale_invoice`              | `expected_updated_at` does not match current invoice `updated_at`           |
| `discount_scope_conflict`    | Mutual-exclusion rule violated                                              |
| `overpayment`                | Payment would make balance negative                                         |
| `partial_payments_disabled`  | Patient-tender payment < balance while setting is off                       |
| `invoice_voided`             | Mutation attempted on a voided invoice                                      |
| `invoice_not_voidable`       | Void attempted on `paid` invoice (refund first) or other non-voidable state |
| `permission_denied`          | Missing required key or non-delegable role check                            |
| `cross_branch` / `cross_org` | RLS denied access                                                           |
