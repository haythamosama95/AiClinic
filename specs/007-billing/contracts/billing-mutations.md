# Contract: Billing Mutations (V1-6)

All mutations are PL/pgSQL functions exposed via Supabase RPC. Each enforces (1) permission key check, (2) branch/org scope check, (3) state validation, (4) audit write, (5) optimistic concurrency where applicable. All amounts are `numeric(14,2)`. All errors are raised with stable `SQLSTATE 'P0001'` and an error code in the message body (see Data Model "Failure Modes Reference").

---

## `create_invoice_from_visit(p_visit_id uuid) RETURNS uuid`

**Permission**: `invoices.create`

**Pre-checks**:
- Visit exists, in `completed` status, branch in caller's JWT `branch_ids`.
- No existing non-voided, non-deleted invoice for the visit.

**Behavior**: Inserts a `draft` invoice with `branch_id`, `patient_id`, `organization_id` derived from the visit. Returns `invoice_id`. Audited.

**Errors**: `visit_not_completed`, `active_invoice_exists`, `cross_branch`, `permission_denied`.

---

## `discard_draft_invoice(p_invoice_id uuid, p_expected_updated_at timestamptz) RETURNS void`

**Permission**: `invoices.create`

**Pre-checks**: Invoice in `draft`, branch scope, `expected_updated_at` matches.

**Behavior**: Soft-deletes invoice and its items. Frees the visit for a new invoice. Audited.

**Errors**: `stale_invoice`, `invoice_not_in_draft`, `permission_denied`.

---

## `add_invoice_item(p_invoice_id uuid, p_expected_updated_at timestamptz, p_description text, p_quantity numeric, p_unit_price numeric) RETURNS uuid`

## `update_invoice_item(p_item_id uuid, p_expected_updated_at timestamptz, p_description text, p_quantity numeric, p_unit_price numeric) RETURNS void`

## `remove_invoice_item(p_item_id uuid, p_expected_updated_at timestamptz) RETURNS void`

**Permission**: `invoices.create`

**Pre-checks**: Invoice in `draft`, branch scope, stale check, validation (quantity > 0, unit_price ≥ 0, description non-empty).

**Behavior**: Persists item; recomputes `invoices.subtotal = sum(line_total)`; updates `invoices.updated_at`. If a line-level discount exists on the affected item, recompute its `line_discount_amount` against the new `line_subtotal` (clamped). Audited.

---

## `apply_line_discount(p_item_id uuid, p_expected_updated_at timestamptz, p_kind discount_kind, p_value numeric) RETURNS void`

**Permission**: `invoices.apply_discount`

**Pre-checks**:
- Invoice in `draft`, branch scope, stale check.
- `p_kind = 'percentage'` ⇒ `p_value ∈ [0, 100]`; `p_kind = 'fixed'` ⇒ `p_value ∈ [0, line_subtotal]`.
- **No invoice-level discount set** on this invoice (`discount_amount = 0` AND `discount_kind IS NULL`). Otherwise raise `discount_scope_conflict`.

**Behavior**: Sets `line_discount_kind/value/amount` and recomputes `line_total` and invoice `subtotal`. Passing `(NULL, NULL)` clears the line discount. Audited with scope=line, target=item_id.

---

## `apply_invoice_discount(p_invoice_id uuid, p_expected_updated_at timestamptz, p_kind discount_kind, p_value numeric) RETURNS void`

**Permission**: `invoices.apply_discount`

**Pre-checks**:
- Invoice in `draft`, branch scope, stale check.
- `p_kind = 'percentage'` ⇒ `p_value ∈ [0, 100]`; `p_kind = 'fixed'` ⇒ `p_value ∈ [0, subtotal]`.
- **No line-level discount exists on any item** of this invoice (`SUM(line_discount_amount) = 0`). Otherwise raise `discount_scope_conflict`.

**Behavior**: Persists `discount_kind/value/amount` on invoice. Passing `(NULL, NULL)` clears. Audited with scope=invoice.

---

## `set_insurance_coverage(p_invoice_id uuid, p_expected_updated_at timestamptz, p_provider_id uuid, p_covered_amount numeric) RETURNS void`

**Permission**: `invoices.create`

**Pre-checks**: Invoice in `draft`, branch scope, stale check; provider active and same org; `0 ≤ p_covered_amount ≤ subtotal − discount_amount`.

**Behavior**: Persists provider and amount. Passing `(NULL, 0)` clears. Audited.

---

## `issue_invoice(p_invoice_id uuid, p_expected_updated_at timestamptz) RETURNS text`

**Permission**: `invoices.create`

**Pre-checks**: Invoice in `draft`, branch scope, stale check, ≥1 item, `branches.code IS NOT NULL`.

**Behavior**: Inside a single transaction:
1. `SELECT ... FOR UPDATE` on `invoice_number_sequences` for `branch_id` (insert row at 0 if missing).
2. Increment `last_value`; compose `INV-<branch.code>-<lpad(last_value, 6, '0')>`.
3. Freeze `subtotal`, `discount_amount`, items snapshot; set `status='issued'`, `invoice_number`, `issued_at=now()`.
4. Audit with new invoice number.

Returns the assigned `invoice_number`.

**Errors**: `branch_code_missing`, `no_items`, `stale_invoice`, `permission_denied`.

---

## `record_payment(p_invoice_id uuid, p_method payment_method, p_amount numeric, p_reference text, p_note text) RETURNS uuid`

**Permission**: `payments.record`

**Pre-checks**:
- `p_amount > 0`.
- Invoice in `issued` or `partially_paid`; branch scope.
- `SELECT ... FOR UPDATE` on invoice; recompute `current_balance = subtotal − discount_amount − insurance_covered_amount − sum(payments.amount)`.
- `p_amount ≤ current_balance` else raise `overpayment`.
- If `allow_partial_payments = false` (read from `organization_billing_settings`) AND `p_method IN ('cash','card','bank_transfer')` AND `p_amount < current_balance` → raise `partial_payments_disabled`. `insurance_settlement` is exempt.

**Behavior**: Insert payment row; recompute new balance; update invoice status (`partially_paid` if balance > 0, `paid` if balance = 0). Audited with method, amount, prior balance, new balance.

Returns `payment_id`.

---

## `record_refund(p_invoice_id uuid, p_method payment_method, p_amount numeric, p_note text) RETURNS uuid`

**Permission**: `payments.refund`

**Pre-checks**: `p_amount > 0` (stored as negative); `p_note` non-empty; invoice not `voided`; absolute refund amount ≤ net positive payments on invoice.

**Behavior**: Insert payment row with `amount = -p_amount`. Transition: if new balance > 0 and prior `paid` → `partially_paid` (or `issued` when no remaining net positive payments). Audited.

---

## `void_invoice(p_invoice_id uuid, p_reason text) RETURNS void`

**Permission**: `invoices.void`

**Pre-checks**: Invoice in `issued` or `partially_paid`; `p_reason` non-empty; branch scope.

**Behavior**: Set `status='voided'`, `void_reason=p_reason`, `voided_at=now()`, `voided_by=caller`. Locks invoice from further mutation. Audited.

**Errors**: `invoice_not_voidable` (e.g., when `paid` — caller must refund first).

---

## `insurance_provider_upsert(p_id uuid, p_name text, p_contact_info text, p_is_active boolean) RETURNS uuid`

## `insurance_provider_deactivate(p_id uuid) RETURNS void`

**Permission**: `insurance.manage`

**Behavior**: Create/edit/deactivate org-scoped providers. Soft delete is not used; `is_active=false` removes from selectors but preserves history references on existing invoices.

---

## `update_billing_settings(p_allow_partial_payments boolean) RETURNS void`

**Permission**: `settings.billing.manage` **AND** caller's role ∈ {`owner`, `administrator`} (non-delegable per D10).

**Behavior**: Updates `organization_billing_settings.allow_partial_payments` for the caller's org. Audited with prior and new values. Takes effect on the next payment attempt; in-flight transactions are unaffected.

**Errors**: `permission_denied`.

---

## Audit log payloads (FR-023)

Every mutation RPC writes an `audit_log` row with at minimum: `actor_id`, `organization_id`, `action`, `target_table`, `target_id`, and a JSONB `payload` containing the prior and new key values (e.g., `{"prior_status":"issued","new_status":"voided","reason":"..."}`, or `{"method":"cash","amount":50.00,"prior_balance":120.00,"new_balance":70.00}`).
