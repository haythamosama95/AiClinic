# Billing Feature End‑to‑End Review (V1‑6)

Scope: `frontend/lib/features/billing` and `backend/supabase/migrations/2026060518*…20260605270000_*` plus contracts in `specs/007-billing/contracts/`.

Severity scale: Critical (data corruption / unhandled exception path), High (likely user-facing failure or contract drift), Medium (incorrect behavior under edge cases), Low (maintenance / UX consistency).

---

## 1. CRITICAL — `update_invoice_item` can violate `invoice_items_line_discount_amount_bounds`

**Files**: `backend/supabase/migrations/20260605180500_billing_us1_rpcs.sql` (`auth_internal.update_invoice_item`, lines ~459–470).

**Problem**: The function first executes
```sql
UPDATE invoice_items
SET line_subtotal = v_line_subtotal,
    line_total    = v_line_subtotal - ii.line_discount_amount,
    ...
```
*before* re-running `recompute_item_line_totals`. If quantity or unit_price is lowered such that the new `line_subtotal` is smaller than the existing `line_discount_amount`, the row immediately violates the CHECK constraint `line_discount_amount <= line_subtotal` (and `line_total = line_subtotal - line_discount_amount` becomes negative). PostgreSQL raises `23514` and the whole RPC aborts with an unmapped raw SQL error reaching the client.

**Fix**: Recompute and clamp `line_discount_amount` *in the same UPDATE* (or first zero out `line_discount_amount`/`line_total`, then call `recompute_item_line_totals`). Example:

```sql
UPDATE invoice_items ii
SET description = v_description,
    quantity    = p_quantity,
    unit_price  = p_unit_price,
    line_subtotal        = v_line_subtotal,
    line_discount_amount = 0,
    line_total           = v_line_subtotal,
    ...
WHERE ii.id = p_item_id;

PERFORM auth_internal.recompute_item_line_totals(p_item_id);
```

---

## 2. CRITICAL — Item mutations can violate `invoices_insurance_covered_bounds`

**Files**: `20260605180500_billing_us1_rpcs.sql` (`add_invoice_item`, `update_invoice_item`, `remove_invoice_item`, `discard_draft_invoice`), constraint defined in `20260605180000_billing.sql`.

**Problem**: The invoice constraint is `insurance_covered_amount <= subtotal − discount_amount`. After removing/updating an item, `refresh_invoice_subtotal` lowers `subtotal`; if the new `subtotal − discount_amount < insurance_covered_amount`, the UPDATE fails with raw `23514`. There is no clamp/recalculation of `insurance_covered_amount` (or invoice-level `discount_amount` when it was `fixed`).

Concrete trigger: subtotal=200, fixed invoice discount=50, insurance=100. Remove the only item → new subtotal 0; constraint check `0 − 50 ≥ 100` fails.

**Fix**: In `refresh_invoice_subtotal` (or in each item-mutation RPC) recompute and clamp dependent fields atomically:
- If `discount_kind = 'fixed'` and `discount_value > subtotal` → cap `discount_amount := least(discount_value, subtotal)`.
- If `discount_kind = 'percentage'` → recompute `discount_amount = round(subtotal * value/100, 2)`.
- Then cap `insurance_covered_amount := least(insurance_covered_amount, subtotal − discount_amount)`.

Apply the same in `apply_invoice_discount` (see #3).

---

## 3. CRITICAL — `apply_invoice_discount` / `apply_line_discount` do not re-clamp `insurance_covered_amount`

**Files**: `20260605220000_billing_us3_discount_rpcs.sql`.

**Problem**: Increasing the discount can leave `insurance_covered_amount > subtotal − discount_amount`, again hitting `invoices_insurance_covered_bounds` with a raw CHECK error rather than a mapped `INVALID_INPUT`. Same for line discount (it changes `subtotal` via `refresh_invoice_subtotal`).

**Fix**: After computing the new `discount_amount` (and after `refresh_invoice_subtotal` for line discounts), clamp `insurance_covered_amount := least(insurance_covered_amount, subtotal − discount_amount)` inside the same transaction. Alternatively, return a friendly `INSURANCE_OVER_COVERAGE` rpc_error before mutating.

---

## 4. HIGH — Description length not enforced before INSERT (raw CHECK violation)

**Files**: `add_invoice_item` / `update_invoice_item` in `20260605180500_billing_us1_rpcs.sql` and `frontend/.../invoice_repository.dart`.

**Problem**: Schema constrains `description <= 500` (`invoice_items_description_length`) but the RPC only checks empty-string. A 501-char description aborts with raw `23514`. The frontend repository also does not validate length (only the widget validator does).

**Fix**: Add `IF char_length(v_description) > 500 THEN RETURN rpc_error('INVALID_INPUT', 'Description must be 500 characters or fewer.') ` in both RPCs, and mirror in `_assertNonEmpty`/new helper in `InvoiceRepository`.

---

## 5. HIGH — `findForVisit` may return a voided invoice

**Files**: `frontend/lib/features/billing/data/invoice_repository.dart` (`findForVisit`).

**Problem**:
```dart
final items = await listInvoices(filters: {'visit_id': visitId}, limit: 1);
```
Backend `list_invoices` returns rows ordered by `created_at DESC` and does **not** exclude voided invoices. If a prior invoice was voided and a new one is being created, callers that act on the “current invoice for visit” will pick up the voided one (or a stale one) instead of the active draft. The active-invoice uniqueness index lives only on the non-voided partial index, so semantics intend a single active row.

**Fix**: Either pass `statuses: ['draft','issued','partially_paid','paid']` (exclude `voided`), or add a dedicated `get_active_invoice_for_visit(visit_id)` RPC that mirrors the active-invoice predicate already in `create_invoice_from_visit`.

---

## 6. HIGH — Refund form max amount is wrong (gross vs net)

**Files**: `frontend/lib/features/billing/presentation/widgets/refund_form.dart` (`_netPositivePayments`).

**Problem**: Frontend computes the max refund as the **sum of positive payments only**, ignoring any prior refunds already issued. Backend (`record_refund`) checks `p_amount > SUM(payments.amount)` — i.e. positives **minus prior refunds**. A user can therefore type an amount that passes client validation but is rejected by the server (and the displayed “Maximum refundable” misleads them).

**Fix**: Compute `net = sum(positive) − sum(absolute_negatives)` (i.e. simply `payments.fold(0, (a, p) => a + parse(p.amount))`) and use that as the cap and helper text.

---

## 7. HIGH — `_load()` aborts the editor for non-draft invoices, blocking payments / refunds entry flows that re-use it

**Files**: `frontend/lib/features/billing/presentation/providers/invoice_editor_notifier.dart` (`_load` throws `StateError` when `!detail.status.isDraft`).

**Problem**: The provider is shared, but it hard-throws after a successful network call when the invoice is not draft. Any UI that ends up watching `invoiceEditorProvider(id)` for an issued/paid invoice (e.g. navigation back from a payment) will surface a misleading exception rather than a clean read-only state. Editor state and read-only state should be different concerns.

**Fix**: Return an `InvoiceEditorState(detail: detail, editorStatus: idle)` regardless of status; let widgets gate write actions on `detail.status.isDraft`. If a strict-edit guard is desired, raise a typed `RpcFailure(code: 'INVOICE_NOT_IN_DRAFT')` so `billingMessageForRpc` formats it.

---

## 8. HIGH — `apply_line_discount` rejects *clearing* when an invoice-level discount exists

**Files**: `20260605220000_billing_us3_discount_rpcs.sql` (lines ~113–118).

**Problem**: The scope-conflict guard runs unconditionally, including when `(p_kind, p_value) = (NULL, NULL)` (the documented “clear” path). In practice, with the mutual-exclusion invariant, a line discount can’t coexist with an invoice discount, so a clear-call from the UI to “reset” a line will fail with `DISCOUNT_SCOPE_CONFLICT` if there is any invoice-level discount on the same row, even though there is nothing to clear. This makes recovery scripts and idempotent UI flows brittle.

**Fix**: Skip the scope-conflict check (and the `recompute_item_line_totals` body changes) when `p_kind IS NULL AND p_value IS NULL` and the item already has no line discount; otherwise return success no-op.

---

## 9. HIGH — `billingMessageForRpc` is missing several backend codes

**Files**: `frontend/lib/features/billing/presentation/billing_rpc_messages.dart`.

**Problem**: Backend can emit `INVALID_INPUT`, `NOT_FOUND`, `INVOICE_VOIDED` (mapped), `RPC_NOT_APPLIED`, `RPC_NOT_CONFIGURED`, `AUTH_ERROR` (added by `AppRpcInvoker`), and DB raw codes like `23514`/`23505`. Only some are mapped; the rest fall through to the raw server message, which can be `null` or English-only with PII (e.g. constraint name).

**Fix**: Add explicit cases for at least: `INVALID_INPUT`, `NOT_FOUND`, `RPC_NOT_APPLIED`, `RPC_NOT_CONFIGURED`, `AUTH_ERROR`, and a generic “Something went wrong” fallback for unknown codes.

---

## 10. HIGH — `discard_draft_invoice` audit references `v_invoice` before it is fetched on the discard branch

**Files**: `20260605180500_billing_us1_rpcs.sql` (`discard_draft_invoice`).

**Problem**: After the `EXCEPTION` block, `v_invoice` is populated only on the success path of `lock_draft_invoice`. If an `OTHERS` exception not in the WHEN list bubbles, the `RAISE` re-raises before audit — fine. But `lock_draft_invoice` actually selects the invoice using only `branch_id = ANY (jwt_branch_ids())` without checking `staff_has_invoices_view_access` — same SECURITY DEFINER bypass exists in other locks. This means a user without `invoices.view` but with `invoices.create` (`receptionist`) can probe invoice existence cross-edits. That matches the seed permissions, so functionally OK, but the `assert_permission('invoices.create')` line gates it correctly. Note for future auditors.

**Fix**: No correctness fix required; document that `lock_draft_invoice` relies on caller-side permission assertion.

---

## 11. HIGH — `_assertNonNegativeDecimal` hard-codes the message “Unit price cannot be negative.”

**Files**: `frontend/lib/features/billing/data/invoice_repository.dart` (lines ~249–260).

**Problem**: The helper is reused for `coveredAmount` (insurance) and `unitPrice`. When `coveredAmount` validation fails, the user sees “Unit price cannot be negative.”, which is misleading.

**Fix**: Interpolate the field name: `'$field cannot be negative.'`.

---

## 12. HIGH — `list_invoices.invoice_number` ILIKE accepts unescaped `%`/`_`

**Files**: `20260605180500_billing_us1_rpcs.sql` (`list_invoices`).

**Problem**: `i.invoice_number ILIKE v_invoice_number || '%'` lets a user pass `%` to match arbitrarily and `_` to match any single char. Combined with the equality clause it is mostly cosmetic but can leak existence-information for non-active branches if RLS predicates ever change.

**Fix**: Escape the filter: `replace(replace(v_invoice_number, '\\', '\\\\'), '%','\\%')` and use `ILIKE … ESCAPE '\\'`.

---

## 13. MEDIUM — `list_invoices` accepts `visit_id` but contract does not document it

**Files**: `specs/007-billing/contracts/billing-queries.md`, `20260605180500_billing_us1_rpcs.sql` (`v_visit_id` parsing), `invoice_repository.findForVisit`.

**Problem**: Frontend depends on this filter; if the contract is treated as source of truth and the param is dropped later, `findForVisit` silently degrades to a scan of all invoices.

**Fix**: Add `visit_id (uuid)` to the documented filter list, and add a contract test.

---

## 14. MEDIUM — `record_payment` audit_log omits `reference`

**Files**: `20260605181000_billing_us2_payment_rpcs.sql`.

**Problem**: `record_refund` writes `note`; `record_payment` audit payload omits `reference` and `note`. This weakens the audit trail for FR‑023 (which says “new key values”).

**Fix**: Add `'reference'` and `'note'` to the `record_payment` `audit_log.new_data_json`.

---

## 15. MEDIUM — `InsurancePanel` empty-amount comparison uses `'0'`, but server returns `'0.00'`

**Files**: `frontend/lib/features/billing/presentation/widgets/insurance_panel.dart` (`_syncFromDetail`).

**Problem**: `widget.detail.insuranceCoveredAmount == '0'` never matches the server-formatted `'0.00'`, so the field shows `0.00` instead of blanking on first render — a minor UX regression and a divergence from the equivalent zero-handling in `InvoiceDiscountPanel`.

**Fix**: `final parsed = double.tryParse(widget.detail.insuranceCoveredAmount) ?? 0; _amountController.text = parsed == 0 ? '' : widget.detail.insuranceCoveredAmount;`

---

## 16. MEDIUM — Payment.recordedBy comes from `staff_members.id` but type is opaque to UI

**Files**: `20260605180500_billing_us1_rpcs.sql` (`get_invoice_detail` payment block), `frontend/.../domain/payment.dart`.

**Problem**: The detail payload returns `recorded_by` as a UUID, with no display name. The UI currently does nothing with it, but receipts and audit views will want a staff display name. Today, callers cannot map the id without a second query (staff RLS may also block them).

**Fix**: Join `staff_members` in `get_invoice_detail` and emit `{ id, display_name }` for `recorded_by`. Also include the staff display name on `payments[].recorded_by` rather than only the UUID — needed for the receipt feature.

---

## 17. MEDIUM — `record_refund` is allowed only on invoices in `('issued','partially_paid','paid')`, but the contract also implies refunds after a void should be impossible — fine. However, the FE form only renders for `paid`/`partiallyPaid`, never `issued`

**Files**: `frontend/.../refund_form.dart` (`_canRefund`).

**Problem**: An `issued` invoice with a partial refund-eligible payment (e.g. credit applied then later increased) is allowed by backend but blocked by the FE. Right now this is unreachable because issued-with-payments transitions to `partially_paid`. Safe today; will break the day someone adds “credits” or pre-paid balances.

**Fix**: Use `netPositivePayments > 0 && status != voided` as the gate, matching backend semantics.

---

## 18. LOW — Frontend `InvoiceListNotifier.hasMore` is `items.length >= pageSize`

**Files**: `frontend/.../invoice_list_notifier.dart`.

**Problem**: When the last page is exactly `pageSize`, the UI shows “load more” which then returns 0 rows; not strictly wrong but causes a wasted RPC. Backend doesn’t return a `has_more`/`next_offset` cursor.

**Fix**: Have `list_invoices` return `{ items, has_more }` (or a cursor) and use it directly. Aligns with the “cursor pagination once result sets exceed ~1000 rows” note in the contract.

---

## 19. LOW — `invoiceDetailProvider` (FE) is `autoDispose` but the editor and payment notifiers also fetch detail; cache fragmentation

**Files**: `frontend/.../providers/invoice_detail_provider.dart`, `invoice_editor_notifier._mutate`.

**Problem**: After every mutation the editor calls `repo.getDetail` directly (bypassing `invoiceDetailProvider`) and then unrelated UI watching `invoiceDetailProvider(id)` does its own fetch. Two RPCs per action.

**Fix**: After a successful mutation, update the editor’s state from a single call and `ref.invalidate(invoiceDetailProvider(id))` so all readers reconcile from one source.

---

## 20. LOW — `BillingSettings.fromRow` returns null on missing key, but the repository throws `StateError`, not `RpcFailure`

**Files**: `frontend/.../data/billing_settings_repository.dart`, `domain/billing_settings.dart`.

**Problem**: Loss of error code propagation — UI shows a Dart stack-trace string. Same pattern in other repositories.

**Fix**: Throw `RpcFailure(RpcResult(success: false, errorCode: 'UNEXPECTED_RESPONSE', errorMessage: …))` so `billingMessageForRpc` produces a friendly string.

---

## 21. LOW — `discount_amount` not zeroed on percentage-rate change when value drops to 0

**Files**: `apply_invoice_discount`.

**Problem**: Setting a percentage of `0` writes `discount_kind='percentage', discount_value=0, discount_amount=0`. The discount is technically present but inert. `apply_line_discount` and `set_insurance_coverage`’s scope-conflict check uses `discount_kind IS NOT NULL OR discount_amount > 0`, which blocks any line discount even though the invoice discount is 0.

**Fix**: Treat `value=0` as “clear” in both apply paths, or relax the scope check to `discount_amount > 0 OR (discount_kind IS NOT NULL AND discount_value > 0)`.

---

## 22. LOW — Frontend domain models store decimals as `String` with no central parser

**Files**: All `frontend/lib/features/billing/domain/*.dart`.

**Problem**: Each widget re-parses with `double.tryParse(...) ?? 0`, which is locale-naive (commas would silently become 0). With server always emitting `.` it works today, but any localized echo or copy/paste with commas drops silently to 0 — a real money bug if Intl formatting is later added on the way out.

**Fix**: Introduce a `Money`/`Decimal` value object (e.g. `package:decimal`) wrapping these strings, parse once on `fromRow`, format consistently for display, and reject malformed input loudly.

---

## 23. LOW — `permissionServiceProvider` is read inside `build()` of multiple AsyncNotifiers without `ref.watch`

**Files**: `invoice_editor_notifier`, `payment_notifier`, `billing_settings_notifier`.

**Problem**: Permissions are read with `ref.read` at build time; if permissions change at runtime (impersonation, role edit pushed via realtime, etc.) the notifiers won’t rebuild. Today these don’t change mid-session, but they’re intended to.

**Fix**: `ref.watch(permissionServiceProvider)` so notifiers rebuild when the permission snapshot changes.

---

## 24. LOW — `voidInvoice` repository doesn’t take `expectedUpdatedAt`

**Files**: `frontend/.../invoice_repository.dart` and backend `void_invoice`.

**Problem**: All other state-changing RPCs implement optimistic concurrency, but voiding does not. Two concurrent voids by different users are racy: both succeed, the second overwrites `voided_by`/`void_reason`.

**Fix**: Add `p_expected_updated_at` to `void_invoice`, lock the row with the same stale-check semantics as `lock_draft_invoice`. Update the FE repo and call sites.

---

## 25. LOW — Insurance provider unique index is case-insensitive but FE allows whitespace-only edits to be saved

**Files**: `insurance_provider_upsert` already does `btrim` — OK. FE `insurance_provider_repository.upsertProvider` only checks non-empty after trim — also OK. No fix; included for completeness.

---

## Future-proofing notes (no action required, but tracked)

- **Multi-currency**: `currency` is stored on the invoice but the UI assumes a single org currency (no rate, no FX). Adding per-branch or per-patient currency will require a money table or rate snapshot at issue time.
- **Tax**: Schema has no concept of tax; adding VAT/GST will require new columns (`tax_kind`, `tax_amount`) and another scope-exclusion rule with discounts.
- **Multiple invoices per visit**: Today `invoices_visit_active_unique` enforces one active invoice/visit. Adopting split-billing (lab vs consult) will require dropping that constraint and introducing an invoice grouping concept.
- **Payment gateway integration**: `payments` is append-only with no idempotency key. Adding async gateway capture should add `external_reference` + unique index to avoid double-record on webhook retries.
- **Receipt PDF**: Receipt generation is client-side from `get_invoice_detail` + org header. There is no server-side rendering or storage of the issued receipt snapshot. For tax-audit jurisdictions this is insufficient; consider persisting a frozen snapshot on `issue_invoice`.

---

## Summary by severity

| Severity | Count | Items                                 |
| -------- | ----- | ------------------------------------- |
| Critical | 3     | #1, #2, #3                            |
| High     | 9     | #4, #5, #6, #7, #8, #9, #10, #11, #12 |
| Medium   | 5     | #13, #14, #15, #16, #17               |
| Low      | 8     | #18–#25                               |

Recommended first wave for the cheaper model:
1. Fix #1 (`update_invoice_item` discount clamp).
2. Fix #2/#3 (re-clamp insurance + invoice discount after subtotal changes).
3. Fix #5 (`findForVisit` voided-invoice exclusion).
4. Fix #6 (refund form net cap).
5. Fix #4 (description length pre-check) and #9 (error code mapping) together — small touches that materially improve UX.
