# Quickstart: Billing (V1-6) Operator Verification

This walkthrough verifies the end-to-end billing flow against a local Supabase + Flutter desktop build, covering invoice creation, both discount scopes (mutually exclusive), the new "Allow partial payments" setting, payments, refund, void, and receipt printing.

## Preconditions

- V1-0..V1-5 features are implemented and migrated.
- Local Supabase stack running; `20260605180000_billing.sql` migration applied; `run_billing_tests.sh` passes.
- An organization, at least one branch with `branches.code` set (e.g., `MAIN`), one administrator account, one receptionist account, and one completed visit attached to a patient.

## Steps

### 1. Verify default settings

1. Log in as **administrator**.
2. Open **Settings → Organization → Billing**.
3. **Expect**: the "Allow partial payments" toggle is visible and **off** by default.
4. Log in as **receptionist** in a separate window.
5. Open the same Settings page.
6. **Expect**: the toggle is hidden or shown read-only. A direct RPC call to `update_billing_settings` fails with `permission_denied`.

### 2. Create an invoice from a completed visit

1. As **receptionist**, open the completed visit detail.
2. Click **Create invoice**. A draft invoice opens.
3. Add three items: e.g., Consultation 1×100, Lab Test 1×50, Dressing 1×20. Subtotal = 170.
4. **Expect**: invoice number not yet assigned; `status = draft`.

### 3. Attempt mutually-exclusive discounts

1. Apply a **10% line-level discount** to the Lab Test item. Subtotal updates to 165.
2. Attempt to apply an **invoice-level discount** of 20.
3. **Expect**: rejection with `discount_scope_conflict` ("clear all line-level discounts first").
4. Clear the line discount. Now apply an invoice-level discount of 20.
5. **Expect**: acceptance; subtotal 170, invoice-level discount 20, total 150.
6. Attempt to add another line discount.
7. **Expect**: rejection (symmetric).

### 4. Add insurance and issue

1. Select an active insurance provider; enter covered amount 50.
2. Click **Issue invoice**.
3. **Expect**: status → `issued`; invoice number `INV-MAIN-000001` (or next in sequence); items frozen; balance = 150 − 20 − 50 = 80.

### 5. Partial payment with setting OFF

1. With "Allow partial payments" still **off**, attempt to record a cash payment of 30.
2. **Expect**: rejection with `partial_payments_disabled`.
3. Record an **insurance_settlement** payment of 25.
4. **Expect**: acceptance (insurance settlements are exempt). Balance = 55.
5. Attempt a cash payment of 30 again.
6. **Expect**: still rejected — patient-tender must be the full remaining balance (55).
7. Record cash 55.
8. **Expect**: acceptance; status → `paid`.

### 6. Toggle setting ON; refund and partial collection

1. As administrator, toggle **Allow partial payments** to **on**.
2. **Expect**: audit log row recorded with prior=false, new=true.
3. As receptionist, record a refund of 30 with reason "patient overpaid".
4. **Expect**: status moves from `paid` → `partially_paid`; balance = 30.
5. Record a partial card payment of 20.
6. **Expect**: acceptance (setting now allows partial). Balance = 10.
7. Record card payment of 10.
8. **Expect**: status → `paid`.

### 7. Void path

1. As administrator, attempt to void the `paid` invoice.
2. **Expect**: rejection (`invoice_not_voidable`) prompting full refund first.
3. Refund the remaining net positive payments; once invoice is `partially_paid` or `issued`, void with a reason.
4. **Expect**: status → `voided`; reason captured; all mutation paths return `invoice_voided`.

### 8. Receipt print

1. Open the voided invoice receipt preview.
2. **Expect**: "VOIDED" watermark with the captured reason.
3. Create a fresh invoice for another completed visit, issue it, and open the print preview.
4. **Expect**: organization header, branch, patient, invoice number, items with quantities/prices, any discount lines (line OR invoice scope, not both), insurance line, total, payments list, and current balance.
5. Invoke OS print dialog and save to PDF.
6. **Expect**: OS-native print dialog opens; PDF saved correctly.

### 9. Cross-branch / cross-org denial

1. As a user assigned to a different branch, attempt to open the prior invoice by id.
2. **Expect**: `not_found` (RLS).
3. As a user in another organization, attempt the same.
4. **Expect**: `not_found`.

### 10. Concurrent payment race

1. Open the same `issued` invoice on two stations; on both, prepare a payment equal to the full balance.
2. Submit both as close to simultaneously as possible.
3. **Expect**: one accepted (`paid`), one rejected with `overpayment` (transactional balance check).

## Success criteria

All ten steps pass with the expected outcomes. Any deviation indicates a regression against `spec.md` acceptance criteria.

## Phase 11 acceptance notes (2026-06-06)

Automated verification for polish/cross-cutting tasks:

| Check                                   | Command / artifact                                                                           | Expected                                                             |
| --------------------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Backend billing suite                   | `bash backend/tests/run_billing_tests.sh`                                                    | Exit 0; 12 RLS + 85 CRUD + 3 concurrency checks                      |
| Flutter billing tests                   | `cd frontend && flutter test test/unit/billing test/widget/billing test/integration/billing` | 80 tests green                                                       |
| Payments append-only                    | `information_schema.role_table_grants` on `public.payments` for `authenticated`              | No `UPDATE` or `DELETE`; `billing_rls.sql` confirms DML denial       |
| `settings.billing.manage` non-delegable | `billing_rls.sql` → `settings_billing_manage_non_delegable`                                  | `PERMISSION_NOT_DELEGABLE` for receptionist                          |
| List pagination indexes                 | `invoices_branch_created_idx`, `invoices_status_branch_idx` on `public.invoices`             | Present; supports branch-scoped `ORDER BY created_at DESC` (NFR-003) |
| Receipt render budget                   | `receipt_print_preview_test.dart` NFR-004 case                                               | 100 line items render in < 2s                                        |

Quickstart step mapping (automated vs manual):

| Step                                 | Automated coverage                                                                    | Manual gap                                                               |
| ------------------------------------ | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| 1 Settings                           | `billing_settings_section_test.dart`, `billing_crud.sql` settings scenarios           | —                                                                        |
| 2–4 Create/issue/discounts/insurance | `create_and_issue_invoice_test.dart`, `discount_scopes_test.dart`, `billing_crud.sql` | —                                                                        |
| 5–6 Payments/refunds                 | `record_payment_test.dart`, `billing_crud.sql`, `billing_concurrency.sql`             | —                                                                        |
| 7 Void                               | `void_invoice_test.dart`, `billing_crud.sql` void scenarios                           | —                                                                        |
| 8 Receipt print                      | `receipt_print_preview_test.dart`, `print_receipt_test.dart`                          | OS print dialog + save-to-PDF requires interactive desktop run           |
| 9 Cross-branch/org                   | `billing_rls.sql`                                                                     | —                                                                        |
| 10 Concurrent race                   | `billing_concurrency.sql`, `record_payment_test.dart` scenario 6                      | Two-station simultaneous UI submit still worth spot-check before rollout |

**Deviations / follow-ups:** None blocking. `specs/operations/billing.spec.md` remains unauthored (FR-026 placeholder). Manual steps 8 (OS print dialog) and 10 (two-station UI race) should be recorded in a release checklist when cutting a clinic build.
